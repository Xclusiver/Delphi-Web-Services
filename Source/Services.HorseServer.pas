unit Services.HorseServer;

interface

uses
  System.SysUtils,
  System.StrUtils,
  Horse,
  Horse.Request,
  Horse.Response,
  Core.Interfaces,
  Infrastructure.Container;

type
  THorseServerManager = class
  private
    FLogger: IAppLogger;
    FPort: Integer;
    FStarted: Boolean;
  public
    property Started: Boolean read FStarted write FStarted;
    constructor Create(const ALogger: IAppLogger; APort: Integer);
    procedure Start;
    procedure Stop;
  end;

implementation

constructor THorseServerManager.Create(const ALogger: IAppLogger; APort: Integer);
begin
  FLogger := ALogger;
  FPort := APort;
end;

procedure THorseServerManager.Start;
begin
  // Endpoint
  THorse.Get('/api/data',
    procedure(aReq: THorseRequest; aRes: THorseResponse; aNext: TNextProc)
    begin
      var lDb: IDatabaseManager := TContainer.Resolve<IDatabaseManager>;
      aRes.Status(200).Send(lDb.GetDataAsJson);
    end);

  // Start serwera
  THorse.Listen(FPort,
    procedure
    begin
      if Assigned(FLogger) then
        FLogger.LogInfo(Format('Serwer HORSE uruchomiony na porcie %d', [FPort]));
    end);

  FStarted := True;
end;

procedure THorseServerManager.Stop;
begin
  if THorse.IsRunning then
  begin
    THorse.StopListen;
    FLogger.LogInfo('Serwer HORSE zatrzymany');
    FStarted := False;
  end;
end;

end.
