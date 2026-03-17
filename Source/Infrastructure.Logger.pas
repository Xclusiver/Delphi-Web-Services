unit Infrastructure.Logger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Core.Interfaces;

type
  TFileLogger = class(TInterfacedObject, IAppLogger)
  private
    FFilePath: string;
    FLock: TCriticalSection;
    procedure WriteToFile(const ALevel, AMessage: string);
  public
    constructor Create(const AFilePath: string);
    destructor Destroy; override;
    procedure LogInfo(const AMessage: string);
    procedure LogError(const AMessage: string; const AException: Exception = nil);
  end;

implementation

constructor TFileLogger.Create(const AFilePath: string);
begin
  inherited Create;
  FFilePath := AFilePath;
  FLock := TCriticalSection.Create;
end;

destructor TFileLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TFileLogger.WriteToFile(const ALevel, AMessage: string);
var
  LLine: string;
begin
  LLine := Format('%s [%s] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ALevel, AMessage]);
  FLock.Enter;
  try
    TFile.AppendAllText(FFilePath, LLine + sLineBreak, TEncoding.UTF8);
  finally
    FLock.Leave;
  end;
end;

procedure TFileLogger.LogInfo(const AMessage: string);
begin
  WriteToFile('INFO', AMessage);
end;

procedure TFileLogger.LogError(const AMessage: string; const AException: Exception);
begin
  if Assigned(AException) then
    WriteToFile('ERROR', AMessage + ' | Exception: ' + AException.Message)
  else
    WriteToFile('ERROR', AMessage);
end;

end.
