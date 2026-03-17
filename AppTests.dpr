program AppTests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,  
  Core.Interfaces in 'Source\Core.Interfaces.pas',
  Services.Sync in 'Source\Services.Sync.pas',
  Tests.SyncService in 'Tests\Tests.SyncService.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;

begin
  try
    // Tworzenie runnera testów
    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;

    // Logowanie wyników do konsoli
    logger := TDUnitXConsoleLogger.Create(True);
    runner.AddLogger(logger);

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
