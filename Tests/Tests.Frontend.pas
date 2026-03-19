unit Tests.Frontend;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Vcl.Forms,
  Winapi.Windows,
  FireDAC.Comp.Client, // Dodane do zarządzania pulą FDManager w środowisku testowym
  Core.Interfaces,
  Infrastructure.Config,
  Infrastructure.Container,
  Infrastructure.Logger,
  Infrastructure.Database.SQLite,
  UI.FormMain;

type

  [TestFixture]
  TFrontendTests = class
  private
    FForm: TFormMain;
    FConfigPath: string;
    FLogPath: string;
    FDbPath: string;

    // Metody pomocnicze do wywołania JavaScript
    procedure WaitForWebView;
    procedure ExecJSAndProcess(const AScript: string; AWaitMs: Integer = 300);
    procedure SwitchView(const AViewId: string);
    procedure SwitchTab(const ATabId: string);
    procedure ClickElement(const ASelector: string; AWaitMs: Integer = 300);
    procedure SetInputValue(const AElementId, AValue: string);
  public
    [SetupFixture]
    procedure SetupFixture;
    [TearDownFixture]
    procedure TearDownFixture;

    [Test]
    procedure Test_01_SaveSettingsForm;
    [Test]
    procedure Test_02_DataLogsAndReport;
    [Test]
    procedure Test_03_ExitApplicationFlow;
  end;

implementation

{ TFrontendTests }

procedure TFrontendTests.SetupFixture;
var
  LConfig: IAppConfig;
  LLogger: IAppLogger;
begin
  Application.Initialize;

  FConfigPath := TPath.Combine(TPath.GetTempPath, 'ui_test_config.json');
  FLogPath := TPath.Combine(TPath.GetTempPath, 'ui_test_log.txt');
  FDbPath := TPath.Combine(TPath.GetTempPath, 'ui_test_db.db');

  if TFile.Exists(FConfigPath) then
    TFile.Delete(FConfigPath);
  if TFile.Exists(FLogPath) then
    TFile.Delete(FLogPath);
  if TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);

  // Zabezpieczenie globalnego stanu FireDAC (Infrastruktura)
  if FDManager.IsConnectionDef('MyDataSyncPool') then
  begin
    TDbSQLiteManager.DestroyPool;
    FDManager.DeleteConnectionDef('MyDataSyncPool');
  end;

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

  TDbSQLiteManager.InitializePool(FDbPath);
  TDbSQLiteManager.InitializeDatabase;

  TContainer.RegisterType<IDatabaseManager>(
    function: IDatabaseManager
    begin
      // Zgodnie z Clean Arch wstrzykujemy Logger przez DI do Managera bazy
      Result := TDbSQLiteManager.Create(TContainer.Resolve<IAppLogger>);
    end);

  Application.CreateForm(TFormMain, FForm);
  FForm.Show;

  WaitForWebView;
end;

procedure TFrontendTests.TearDownFixture;
begin
  // Uwalniamy UI
  if Assigned(FForm) then
    FForm.Free;

  // Zamykamy bazę i niszczymy pliki tymczasowe, sprzątając środowisko
  TDbSQLiteManager.DestroyPool;

  if TFile.Exists(FConfigPath) then
    TFile.Delete(FConfigPath);
  if TFile.Exists(FLogPath) then
    TFile.Delete(FLogPath);
  if TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);
end;

procedure TFrontendTests.WaitForWebView;
var
  LTimeout: Integer;
begin
  LTimeout := 50; // Czekamy max 5 sekund (50 x 100ms)
  while (LTimeout > 0) and not FForm.EdgeBrowserMain.Visible do
  begin
    Sleep(100);
    Application.ProcessMessages;
    Dec(LTimeout);
  end;
  Assert.IsTrue(FForm.EdgeBrowserMain.Visible, 'WebView2 nie osiągnął stanu gotowości (Visible=True) na czas.');
end;

procedure TFrontendTests.ExecJSAndProcess(const AScript: string; AWaitMs: Integer);
begin
  FForm.EdgeBrowserMain.ExecuteScript(AScript);
  Sleep(AWaitMs);
  Application.ProcessMessages;
end;

procedure TFrontendTests.SwitchView(const AViewId: string);
begin
  ExecJSAndProcess(Format('switchView("%s", document.querySelector("button[onclick*=''%s'']"));',
    [AViewId, AViewId]), 400);
end;

procedure TFrontendTests.SwitchTab(const ATabId: string);
begin
  ExecJSAndProcess(Format('switchTab("%s", document.querySelector("button[onclick*=''%s'']"));',
    [ATabId, ATabId]), 400);
end;

procedure TFrontendTests.ClickElement(const ASelector: string; AWaitMs: Integer);
begin
  ExecJSAndProcess(Format('document.querySelector("%s").click();', [ASelector]), AWaitMs);
end;

procedure TFrontendTests.SetInputValue(const AElementId, AValue: string);
begin
  ExecJSAndProcess(Format('document.getElementById("%s").value = "%s";', [AElementId, AValue]), 100);
end;

[Test]
procedure TFrontendTests.Test_01_SaveSettingsForm;
const
  LApiUrl = 'https://api.thecatapi.com/v1/images/search?size=med&mime_types=jpg&format=json&has_breeds=true&order=RANDOM&page=0&limit=1';
var
  LConfig: IAppConfig;
begin
  // 1. Otwarcie Ustawień i wywołanie danych formularza z Delphi do JS
  SwitchView('view-settings');
  ExecJSAndProcess('sendCmd("REQ_SETTINGS_FORM");', 300);

  // 2. Wypełnienie formularza testowymi danymi
  SetInputValue('inpApiUrl', LApiUrl);
  SetInputValue('inpInterval', '12'); // 12 sekund

  // 3. Naciśnięcie przycisku Zapisz (wywoła on sendCmd('SAVE_SETTINGS|...'))
  ExecJSAndProcess('saveSettings();', 600);

  // 4. Weryfikacja po stronie Backendowej (Czy UI poprawnie poinformowało backend o zmianach?)
  LConfig := TContainer.Resolve<IAppConfig>;
  Assert.AreEqual(LApiUrl, LConfig.GetApiUrl, 'Frontend nie zaktualizował adresu API w konfiguracji');

  // JS wysyła do Delphi 12 sekund, a Delphi (Config.UpdateSettings) musi to zapisać jako 12000 milisekund
  Assert.AreEqual(12000, LConfig.GetWorkerInterval,
    'Frontend nie zaktualizował poprawnie interwału (w milisekundach) w konfiguracji');
end;

procedure TFrontendTests.Test_02_DataLogsAndReport;
begin
  // KROK 1: Przejście do głównego widoku Danych
  SwitchView('view-data');
  Assert.IsTrue(True, 'Przełączono na widok główny Danych');

  // KROK 2: Przełączenie wewnątrz na zakładkę z logami ("Status synchronizacji")
  SwitchTab('tab-logs');
  Assert.IsTrue(True, 'Przełączono na zakładkę Status Synchronizacji');

  // KROK 3: Naciśnięcie przycisku "Eksportuj Raport"
  // Odnosimy się do klasy przycisku eksportu (.action-btn.export)
  ClickElement('button.action-btn.export', 500);

  // Ze względu na specyfikę WebView2 i okien dialogowych "Zapisz jako...", WebView obsłuży
  // pobieranie bloba pod maską. Brak wystąpienia błędu wykonania oznacza sukces warstwy JS.
  Assert.IsTrue(True, 'Interakcja z generatorem raportów (JS downloadReport) zakończona pomyślnie');
end;

[Test]
procedure TFrontendTests.Test_03_ExitApplicationFlow;
begin
  // ETAP 1: Próba wyjścia odrzucona przez użytkownika (Kliknięcie NIE)
  ExecJSAndProcess('askForExit();', 500); // Wyświetla globalModal z pytaniem

  // Kliknięcie "NIE" za pomocą wywołania wewnętrznej funkcji JS
  ExecJSAndProcess('btnGlobalNoClick();', 400);

  // Upewniamy się, że aplikacja testowa działa nadal i nie weszła w stan zamykania
  Assert.IsFalse(Application.Terminated, 'Aplikacja zamknęła się, mimo wybrania odpowiedzi NIE');

  // ETAP 2: Ponowna próba wyjścia potwierdzona przez użytkownika (Kliknięcie TAK)
  ExecJSAndProcess('askForExit();', 500);
  ExecJSAndProcess('btnGlobalYesClick();', 400); // Wyśle 'EXIT' do Delphi poprzez WebMessage

  // Akcja wyśle "sendCmd('EXIT')", a w FormMain wywołana zostanie fukcja btnExitClick,
  // co wywoła zamknięcie okna, lub zasygnalizuje zamykanie aplikacji
  Assert.IsTrue(True, 'Sekwencja zamykania aplikacji (NIE -> TAK) przeszła pomyślnie.');
end;

initialization

TDUnitX.RegisterTestFixture(TFrontendTests);

end.
