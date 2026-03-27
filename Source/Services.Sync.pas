unit Services.Sync;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading,
  Core.Interfaces;

type
  TSyncService = class(TInterfacedObject, ISyncService)
  private
    FLogger: IAppLogger;
    FApiClient: IApiClient;
    FDbManager: IDatabaseManager;
  public
    constructor Create(const ALogger: IAppLogger; const AApiClient: IApiClient; const ADbManager: IDatabaseManager);
    procedure ExecuteSync;
  end;

  TSyncWorker = class
  private
    FTask: ITask;
    FStopEvent: TEvent;
    FSyncService: ISyncService;
    FLogger: IAppLogger;
    FIntervalMs: Integer;
    FRunning: Boolean;
  public
    constructor Create(const ASyncService: ISyncService; const ALogger: IAppLogger; AIntervalMs: Integer);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
  end;

implementation

constructor TSyncService.Create(const ALogger: IAppLogger; const AApiClient: IApiClient;
  const ADbManager: IDatabaseManager);
begin
  inherited Create;
  FLogger := ALogger;
  FApiClient := AApiClient;
  FDbManager := ADbManager;
end;

procedure TSyncService.ExecuteSync;
var LJsonData: string;
begin
  FLogger.LogInfo('Rozpoczęto synchronizację danych...');
  try
    LJsonData := FApiClient.FetchData;
    if LJsonData <> '' then
    begin
      FDbManager.SaveData(LJsonData);
      FLogger.LogInfo('Synchronizacja zakończona sukcesem');
    end
    else
      FLogger.LogError('Pobrano puste dane z API');
  except
    on E: Exception do
      FLogger.LogError('Błąd w TSyncService: ' + E.Message, E);
  end;
end;

constructor TSyncWorker.Create(const ASyncService: ISyncService; const ALogger: IAppLogger; AIntervalMs: Integer);
begin
  inherited Create;
  FSyncService := ASyncService;
  FLogger := ALogger;
  FIntervalMs := AIntervalMs;

  // ManualReset = True
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

destructor TSyncWorker.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TSyncWorker.Start;
begin
  if FRunning then
    Exit;

  FStopEvent.ResetEvent;

  FTask := TTask.Run(
    procedure
    var
      LWaitResult: TWaitResult;
    begin
      FRunning := True;
      FLogger.LogInfo('TSyncWorker uruchomiony');

      try
        while True do
        begin
          FSyncService.ExecuteSync;

          LWaitResult := FStopEvent.WaitFor(FIntervalMs);

          if LWaitResult = wrSignaled then
            Break;
        end;
      except
        on E: Exception do
          FLogger.LogError('Błąd w TSyncWorker: ' + E.Message, E);
      end;

      FLogger.LogInfo('TSyncWorker zatrzymany');
      FRunning := False;
    end);
end;

procedure TSyncWorker.Stop;
begin
  if not FRunning then
    Exit;

  FStopEvent.SetEvent;

  if Assigned(FTask) then
  begin
    try
      FTask.Wait;
    except
    end;
  end;
end;

function TSyncWorker.IsRunning: Boolean;
begin
  Result := FRunning;
end;

end.
