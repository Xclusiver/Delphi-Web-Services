unit Services.Sync;

interface

uses
  System.SysUtils,
  System.Classes,
  Core.Interfaces;

type
  // Główny serwis synchronizujący
  TSyncService = class(TInterfacedObject, ISyncService)
  private
    FLogger: IAppLogger;
    FApiClient: IApiClient;
    FDbManager: IDatabaseManager;
  public
    constructor Create(const ALogger: IAppLogger; const AApiClient: IApiClient; const ADbManager: IDatabaseManager);
    procedure ExecuteSync;
  end;

  // Wątek działający w tle
  TWorkerThread = class(TThread)
  private
    FSyncService: ISyncService;
    FIntervalMs: Integer;
    FLogger: IAppLogger;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASyncService: ISyncService; const ALogger: IAppLogger; AIntervalMs: Integer);
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

constructor TWorkerThread.Create(const ASyncService: ISyncService; const ALogger: IAppLogger; AIntervalMs: Integer);
begin
  inherited Create(True); // Create suspended
  FSyncService := ASyncService;
  FLogger := ALogger;
  FIntervalMs := AIntervalMs;
  FreeOnTerminate := False; // Kontrolujemy cykl życia z zewnątrz
end;

procedure TWorkerThread.Execute;
begin
  NameThreadForDebugging('SyncWorkerThread');
  FLogger.LogInfo('Worker Thread uruchomiony');

  while not Terminated do
  begin
    FSyncService.ExecuteSync;

    // Zamiast blokującego Sleep, sprawdzamy co 100ms czy wątek nie został przerwany
    var LWaitTime: Integer := 0;
    while (not Terminated) and (LWaitTime < FIntervalMs) do
    begin
      Sleep(100);
      Inc(LWaitTime, 100);
    end;
  end;
  FLogger.LogInfo('Worker Thread zatrzymany');
end;

end.
