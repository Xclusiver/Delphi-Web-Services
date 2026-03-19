program AppTests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$R App.dres}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  Core.Interfaces in 'Source\Core.Interfaces.pas',
  Services.Sync in 'Source\Services.Sync.pas',
  Services.HorseServer in 'Source\Services.HorseServer.pas',
  Infrastructure.Config in 'Source\Infrastructure.Config.pas',
  Infrastructure.Container in 'Source\Infrastructure.Container.pas',
  Infrastructure.Logger in 'Source\Infrastructure.Logger.pas',
  Infrastructure.ApiClient in 'Source\Infrastructure.ApiClient.pas',
  Infrastructure.Database.SQLite in 'Source\Infrastructure.Database.SQLite.pas',
  Infrastructure.Database.Firebird in 'Source\Infrastructure.Database.Firebird.pas',
  Infrastructure.Database.Oracle in 'Source\Infrastructure.Database.Oracle.pas',
  Infrastructure.Database.MSSQL in 'Source\Infrastructure.Database.MSSQL.pas',
  UI.FormMain in 'Source\UI.FormMain.pas',
  Tests.Frontend in 'Tests\Tests.Frontend.pas',
  Tests.Backend in 'Tests\Tests.Backend.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  Logger: ITestLogger;
  nunitLogger: ITestLogger;

begin
  try
    // Tworzenie runnera testów
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;

    // Logowanie wyników do konsoli
    Logger := TDUnitXConsoleLogger.Create(True);
    runner.AddLogger(Logger);

    // Zrzut wyników do XML
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    // Uruchomienie wszystkich zarejestrowanych testów
    results := runner.Execute;

{$IFNDEF CI}
    // Zatrzymanie konsoli, aby można było przeczytać wyniki
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Naciśnij [Enter], aby wyjść...');
      System.Readln;
    end;
{$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;

end.
