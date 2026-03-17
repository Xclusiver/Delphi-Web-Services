unit Tests.SyncService;

interface

uses
  DUnitX.TestFramework,
  Core.Interfaces,
  Services.Sync,
  System.SysUtils;

type
  // MOCKI DLA TESTÓW
  TMockLogger = class(TInterfacedObject, IAppLogger)
  public
    ErrorLogged: Boolean;
    procedure LogInfo(const AMessage: string);
    procedure LogError(const AMessage: string; const AException: Exception = nil);
  end;

  TMockApiClient = class(TInterfacedObject, IApiClient)
  public
    DataToReturn: string;
    function FetchData: string;
  end;

  TMockDbManager = class(TInterfacedObject, IDatabaseManager)
  public
    SavedData: string;
    SaveCallCount: Integer;
    procedure SaveData(const AJsonData: string);
    function GetDataAsJson: string;
  end;

  // KLASA TESTOWA DUNITX
  [TestFixture]
  TTestSyncService = class
  private
    FSyncService: ISyncService;
    FMockLogger: TMockLogger;
    FMockApi: TMockApiClient;
    FMockDb: TMockDbManager;
  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_ExecuteSync_WithValidData_ShouldSaveToDb;

    [Test]
    procedure Test_ExecuteSync_WithEmptyData_ShouldLogErrorAndNotSave;
  end;

implementation

procedure TMockLogger.LogInfo(const AMessage: string);
begin
  // Logi informacyjne pomijamy
end;

procedure TMockLogger.LogError(const AMessage: string; const AException: Exception);
begin
  ErrorLogged := True; // Oznaczamy, że serwis zaraportował błąd
end;

function TMockApiClient.FetchData: string;
begin
  Result := DataToReturn; // Zwracamy to, co ustawiliśmy w teście
end;

procedure TMockDbManager.SaveData(const AJsonData: string);
begin
  SavedData := AJsonData;
  Inc(SaveCallCount);
end;

function TMockDbManager.GetDataAsJson: string;
begin
  Result := '';
end;

procedure TTestSyncService.Setup;
begin
  // Tworzymy mocki
  FMockLogger := TMockLogger.Create;
  FMockApi := TMockApiClient.Create;
  FMockDb := TMockDbManager.Create;
  FMockDb.SaveCallCount := 0;
  FMockLogger.ErrorLogged := False;

  // Wstrzykujemy mocki do prawdziwego serwisu
  FSyncService := TSyncService.Create(FMockLogger, FMockApi, FMockDb);
end;

procedure TTestSyncService.TearDown;
begin
  // Interfejsy wyczyszczą się same dzięki ARC,
  // pozbywamy się tylko referencji
  FSyncService := nil;
end;

procedure TTestSyncService.Test_ExecuteSync_WithValidData_ShouldSaveToDb;
const
  EXPECTED_JSON = '{"id": 1, "name": "Test"}';
begin
  // Przygotowanie i wykonanie
  FMockApi.DataToReturn := EXPECTED_JSON;
  FSyncService.ExecuteSync;

  // Sprawdzenie
  Assert.AreEqual(1, FMockDb.SaveCallCount, 'Metoda SaveData powinna zostać wywołana dokładnie raz.');
  Assert.AreEqual(EXPECTED_JSON, FMockDb.SavedData, 'Zapisany JSON różni się od pobranego z API.');
  Assert.IsFalse(FMockLogger.ErrorLogged, 'Nie powinien zostać zalogowany żaden błąd.');
end;

procedure TTestSyncService.Test_ExecuteSync_WithEmptyData_ShouldLogErrorAndNotSave;
begin
  // Przygotowanie i wykonanie
  FMockApi.DataToReturn := ''; // Symulujemy awarię API (brak danych)
  FSyncService.ExecuteSync;

  // Sprawdzenie
  Assert.AreEqual(0, FMockDb.SaveCallCount, 'Metoda SaveData nie powinna zostać wywołana dla pustych danych.');
  Assert.IsTrue(FMockLogger.ErrorLogged, 'Awaria pobierania (puste dane) powinna zostać zalogowana jako błąd.');
end;

initialization

TDUnitX.RegisterTestFixture(TTestSyncService);

end.
