unit Tests.Backend;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Net.HttpClient,
  Core.Interfaces,
  Infrastructure.Config,
  Infrastructure.Container,
  Infrastructure.Logger,
  Infrastructure.ApiClient,
  Infrastructure.Database.SQLite,
  Services.Sync,
  Services.HorseServer;

type

  [TestFixture]
  TBackendTests = class
  private
    FConfigPath: string;
    FLogPath: string;
    FDbPath: string;
    FServerPort: Integer;
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;
    [Test]
    procedure Test_01_ConfigAndLogger;
    [Test]
    procedure Test_02_ContainerDI;
    [Test]
    procedure Test_03_DatabaseOperations;
    [Test]
    procedure Test_04_ApiClient;
    [Test]
    procedure Test_05_SyncService;
    [Test]
    procedure Test_06_HorseServer;
  end;

implementation

{ TBackendTests }

procedure TBackendTests.SetupFixture;
var
  LConfig: IAppConfig;
  LLogger: IAppLogger;
begin
  FConfigPath := TPath.Combine(TPath.GetTempPath, 'test_config.json');
  FLogPath := TPath.Combine(TPath.GetTempPath, 'test_log.txt');
  FDbPath := TPath.Combine(TPath.GetTempPath, 'test_db.db');
  FServerPort := 9999;

  // Czyszczenie pozostałości po starych testach
  if TFile.Exists(FConfigPath) then
    TFile.Delete(FConfigPath);
  if TFile.Exists(FLogPath) then
    TFile.Delete(FLogPath);
  if TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);

  // 1. INICJALIZACJA WSPÓŁDZIELONEJ INFRASTRUKTURY DLA WSZYSTKICH TESTÓW
  LConfig := TAppConfig.Create(FConfigPath);
  LLogger := TFileLogger.Create(FLogPath);

  TContainer.RegisterType<IAppConfig>(
    function: IAppConfig
    begin
      Result := LConfig;
    end);
  TContainer.RegisterType<IAppLogger>(
    function: IAppLogger
    begin
      Result := LLogger;
    end);

  // 2. INICJALIZACJA BAZY DANYCH (Wykonana tylko raz!)
  TDbSQLiteManager.InitializePool(FDbPath);
  TDbSQLiteManager.InitializeDatabase;

  TContainer.RegisterType<IDatabaseManager>(
    function: IDatabaseManager
    begin
      Result := TDbSQLiteManager.Create(TContainer.Resolve<IAppLogger>);
    end);
end;

procedure TBackendTests.TearDownFixture;
begin
  TDbSQLiteManager.DestroyPool;
  if TFile.Exists(FConfigPath) then
    TFile.Delete(FConfigPath);
  if TFile.Exists(FLogPath) then
    TFile.Delete(FLogPath);
  if TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);
end;

[Test]
procedure TBackendTests.Test_01_ConfigAndLogger;
var
  LConfig: IAppConfig;
  LLogger: IAppLogger;
begin
  // TEST: Tworzenie domyślnej konfiguracji i poprawność zapisu
  LConfig := TAppConfig.Create(FConfigPath);
  Assert.IsTrue(TFile.Exists(FConfigPath), 'Plik konfiguracji nie został utworzony');
  Assert.AreEqual(15000, LConfig.GetWorkerInterval, 'Domyślny interwał jest nieprawidłowy');

  // TEST: Zapis i praca Loggera
  LLogger := TFileLogger.Create(FLogPath);
  LLogger.LogInfo('Test log message');
  Assert.IsTrue(TFile.Exists(FLogPath), 'Plik logu nie został utworzony');
end;

[Test]
procedure TBackendTests.Test_02_ContainerDI;
var
  LConfig: IAppConfig;
  LLogger: IAppLogger;
begin
  // Przygotowanie zależności
  LConfig := TAppConfig.Create(FConfigPath);
  LLogger := TFileLogger.Create(FLogPath);

  // TEST: Rejestracja w kontenerze
  TContainer.RegisterType<IAppConfig>(
    function: IAppConfig
    begin
      Result := LConfig;
    end);
  TContainer.RegisterType<IAppLogger>(
    function: IAppLogger
    begin
      Result := LLogger;
    end);

  // TEST: Wyciągnięcie z kontenera
  Assert.IsNotNull(TContainer.Resolve<IAppConfig>(), 'Nie odnaleziono konfiguracji w DI');
  Assert.IsNotNull(TContainer.Resolve<IAppLogger>(), 'Nie odnaleziono loggera w DI');
end;

[Test]
procedure TBackendTests.Test_03_DatabaseOperations;
var
  LDb: IDatabaseManager;
  LTestJson: string;
begin
  // Pobieramy gotowego Managera z DI
  LDb := TContainer.Resolve<IDatabaseManager>;

  Assert.AreEqual(0, LDb.GetRecordCount, 'Baza powinna być pusta przed dodaniem danych');

  LTestJson := '{"test_key": "test_value"}';
  LDb.SaveData(LTestJson);

  Assert.AreEqual(1, LDb.GetRecordCount, 'Zapis do bazy nie powiódł się');
  Assert.AreEqual(LTestJson, LDb.GetDataAsJson, 'Zwrócony JSON nie zgadza się z zapisanym');

  LTestJson := '{"test_key": "updated_value"}';
  LDb.UpdateData(LDb.GetLastRecordId, LTestJson);
  Assert.AreEqual(LTestJson, LDb.GetDataAsJson, 'Aktualizacja rekordu nie powiodła się');
end;

[Test]
procedure TBackendTests.Test_04_ApiClient;
var
  LClient: IApiClient;
  LResponse: string;
begin
  // Mockujemy otwarte, niezawodne API darmowe (JSONPlaceholder) do testu sieciowego
  LClient := TRestApiClient.Create(TContainer.Resolve<IAppLogger>, 'https://jsonplaceholder.typicode.com/posts/1');
  LResponse := LClient.FetchData;

  Assert.IsNotEmpty(LResponse, 'ApiClient zwrócił puste dane z żądania');
  Assert.IsTrue(LResponse.Contains('userId'), 'ApiClient nie pobrał prawidłowego strukturalnie JSONa');
end;

[Test]
procedure TBackendTests.Test_05_SyncService;
var
  LClient: IApiClient;
  LDb: IDatabaseManager;
  LSync: ISyncService;
  LInitialCount: Integer;
begin
  // TEST: Test pełnego Service'u synchronizacji
  LClient := TRestApiClient.Create(TContainer.Resolve<IAppLogger>, 'https://jsonplaceholder.typicode.com/posts/2');
  LDb := TDbSQLiteManager.Create(TContainer.Resolve<IAppLogger>);

  LSync := TSyncService.Create(TContainer.Resolve<IAppLogger>, LClient, LDb);
  LInitialCount := LDb.GetRecordCount;

  LSync.ExecuteSync; // Wykonanie akcji w tle (pobranie API -> wstawienie DB)
  Assert.AreEqual(LInitialCount + 1, LDb.GetRecordCount, 'Serwis synchronizacji nie zapisał nowego rekordu w bazie');
end;

[Test]
procedure TBackendTests.Test_06_HorseServer;
var
  LServer: THorseServerManager;
  LHttpClient: THTTPClient;
  LHttpResponse: IHTTPResponse;
  LWasConsole: Boolean;
  LDb: IDatabaseManager;
  LTestJson, LDbLastRecord: string;
begin
  // 1. Wyciągamy gotowe połączenie do bazy z poziomu kontenera DI
  LDb := TContainer.Resolve<IDatabaseManager>;

  // 2. Przygotowujemy dane wzorcowe
  LTestJson := '{"wiadomosc": "Testowy json na potrzeby serwera Horse"}';
  LDb.SaveData(LTestJson);
  LDbLastRecord := LDb.GetDataAsJson;

  LServer := THorseServerManager.Create(TContainer.Resolve<IAppLogger>, FServerPort);

  // Wyłączamy flagę konsoli dla serwera Horse
  LWasConsole := System.IsConsole;
  System.IsConsole := False;
  try
    LServer.Start;
    Assert.IsTrue(LServer.Started, 'Serwer HORSE nie uruchomił się (flaga Started)');

    Sleep(200);

    LHttpClient := THTTPClient.Create;
    try
      try
        LHttpClient.ConnectionTimeout := 5000;
        LHttpClient.ResponseTimeout := 5000;

        LHttpResponse := LHttpClient.Get(Format('http://localhost:%d/api/data', [FServerPort]));

        Assert.AreEqual(200, LHttpResponse.StatusCode, 'Endpoint /api/data nie zwrócił kodu 200 OK');

        // 3. Weryfikujemy czy pobrane API pokrywa się z naszą bazą danych
        Assert.AreEqual(LDbLastRecord, LHttpResponse.ContentAsString, 'Dane z serwera Horse różnią się od bazy!');
      except
        on E: Exception do
          Assert.Fail('Błąd komunikacji HTTP: ' + E.Message);
      end;
    finally
      LHttpClient.Free;
    end;
  finally
    LServer.Stop;
    System.IsConsole := LWasConsole;
    Assert.IsFalse(LServer.Started, 'Serwer HORSE nie zatrzymał się poprawnie');
  end;
end;

initialization

TDUnitX.RegisterTestFixture(TBackendTests);

end.
