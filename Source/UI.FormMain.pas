unit UI.FormMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Edge,
  Vcl.ExtCtrls,
  Vcl.Themes,
  System.JSON,
  System.Threading,
  System.NetEncoding,
  System.Generics.Collections,
  Winapi.WebView2,
  Winapi.ActiveX,
  Services.Sync,
  Services.HorseServer,
  Core.Interfaces,
  Infrastructure.Container;

type
  TLogStatus = (lsInfo, lsSystem, lsError);

  TFormMain = class(TForm)
    EdgeBrowserMain: TEdgeBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure EdgeBrowserLogCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure EdgeBrowserLogWebMessageReceived(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
    procedure EdgeBrowserLogNavigationCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
      WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
  private
    FWorker: TWorkerThread;
    FHorseServer: THorseServerManager;
    FLogger: IAppLogger;
    FIsClosing: Boolean;
    FSyncSession: Integer;
    function LoadHtmlFromResource: string;
    function GetFormBackgroundColor: string;
    procedure btnSyncClick;
    procedure btnServerClick;
    procedure btnExitClick;
    procedure SaveSettingsUpdate(const AApiUrl: string; AIntervalMs: Integer);
    procedure LogHtml(const AHtml: string);
    procedure LogMessage(AStatus: TLogStatus; const AMessage: string);
    procedure ParseAndLogJson(AJsonValue: TJSONValue; const AIndentPx: Integer = 0);
    procedure OnWorkerTerminated(Sender: TObject);
    procedure WMNCHitTest(var Msg: TWMNCHitTest); message WM_NCHITTEST; // dla rozmiaru okna
  public
  end;

const
  NOTIFY_CLOSE_SEC = 7;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

// Odbiór komunikatów z Web'a
procedure TFormMain.EdgeBrowserLogWebMessageReceived(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
var
  LMessage: PChar;
  LCmd: string;
  LParts: TArray<string>;
  LJsonVal: TJSONValue;
begin
  if Succeeded(Args.ArgsInterface.Get_webMessageAsJson(LMessage)) then
  begin
    LJsonVal := TJSONObject.ParseJSONValue(string(LMessage));
    if Assigned(LJsonVal) then
      try
        LCmd := LJsonVal.Value;
      finally
        LJsonVal.Free;
      end
    else
      LCmd := string(LMessage);

    if SameText(LCmd, 'SYNC') then
      btnSyncClick
    else
      if SameText(LCmd, 'SERVER') then
        btnServerClick
      else
        if SameText(LCmd, 'EXIT') then
          btnExitClick
        else
          if SameText(LCmd, 'DRAG_WINDOW') then
          begin
            // Przesuwanie okna z poziomu paska HTML
            ReleaseCapture;
            Perform(WM_SYSCOMMAND, $F012, 0);
          end
          else
            if SameText(LCmd, 'REQ_SETTINGS_FORM') then
            begin
              var LConfig: IAppConfig := TContainer.Resolve<IAppConfig>;
              var LSecs: Integer := LConfig.GetWorkerInterval div 1000; // Wartoœæ w sekundach
              EdgeBrowserMain.ExecuteScript(Format('loadSettingsForm("%s", %d);', [LConfig.GetApiUrl, LSecs]));
            end
            else
              if SameText(LCmd, 'REQ_GRID_DATA') then
              begin
                var LDatabase: IDatabaseManager := TContainer.Resolve<IDatabaseManager>;
                var LJsonArray: string := LDatabase.GetAllDataAsJsonArray;
                var LSafeString: TJSONString := TJSONString.Create(LJsonArray);
                try
                  EdgeBrowserMain.ExecuteScript('loadGridData(' + LSafeString.ToJSON + ');');
                finally
                  LSafeString.Free;
                end;
              end
              else
                if LCmd.StartsWith('UPDATE_RECORD|') then
                begin
                  LParts := LCmd.Split(['|'], 4);
                  if Length(LParts) = 4 then
                  begin
                    var LDb: IDatabaseManager := TContainer.Resolve<IDatabaseManager>;
                    LDb.UpdateData(StrToIntDef(LParts[1], 0), LParts[3]);
                    LogMessage(lsInfo, Format('Zaktualizowano w bazie rekord o ID: %s', [LParts[1]]));

                    // Alert potwierdzaj¹cy zapis znikaj¹cy po 7 sekundach
                    // EdgeBrowserMain.ExecuteScript
                    // ('showGlobalModal("info", false, "", "Dane zosta³y zaktualizowane", "OK", 7, null);');
                  end;
                end
                else
                  if LCmd.StartsWith('SAVE_SETTINGS|') then
                  begin
                    LParts := LCmd.Split(['|']);
                    if Length(LParts) >= 3 then
                      // JS przys³a³ SEKUNDY, a Delphi w Configu wymaga MILISEKUND
                      SaveSettingsUpdate(LParts[1], StrToIntDef(LParts[2], 60) * 1000);
                  end;

    CoTaskMemFree(LMessage);
  end;
end;

function TFormMain.LoadHtmlFromResource: string;
var
  LResStream: TResourceStream;
  LStringStream: TStringStream;
begin
  Result := '';
  // 'HTML_UI' to Resource Identifier, w którym znajduje siê interfejs webowy
  LResStream := TResourceStream.Create(HInstance, 'HTML_UI', RT_RCDATA);
  try
    LStringStream := TStringStream.Create('', TEncoding.UTF8);
    try
      LStringStream.LoadFromStream(LResStream);
      Result := LStringStream.DataString;
    finally
      LStringStream.Free;
    end;
  finally
    LResStream.Free;
  end;
end;

procedure TFormMain.EdgeBrowserLogCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
var
  LBaseHtml: string;
begin
  if Succeeded(AResult) then
  begin
    LBaseHtml := LoadHtmlFromResource;
    EdgeBrowserMain.NavigateToString(LBaseHtml);
    // Skrypty zostan¹ wykonane dopiero w EdgeBrowserLogNavigationCompleted!
  end
  else
    ShowMessage('B³¹d inicjalizacji przegl¹darki');
end;

procedure TFormMain.EdgeBrowserLogNavigationCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
var
  LInfoHtml: string;
  LSafeString: TJSONString;
begin
  if IsSuccess then
  begin
    // Wysy³amy zawartoœæ karty informacyjnej
    LInfoHtml :=
      '<h2><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="28" height="28">' +
      '<path d="M12 2L2 7l10 5 10-5-10-5z"></path>' + '<path d="M2 17l10 5 10-5"></path>' +
      '<path d="M2 12l10 5 10-5"></path></svg> Delphi Web Services</h2>' +

      '<p>Nowoczesna aplikacja hybrydowa, ³¹cz¹ca wysokowydajny backend w Delphi z interfejsem u¿ytkownika opartym o ' +
      'technologie webowe (SPA).' + '<BR><BR>' + 'Projekt stanowi demonstracjê budowy aplikacji z wykorzystaniem:<BR>' +
      '- Clean Architecture,<BR>' + '- Dependency Injection,<BR>' + '- Asynchronicznego przetwarzania,<BR>' +
      '- WebView2 jako warstwy UI.</p>' + '<p>Kluczowe cechy:</p>' + '<ul>' +
      '<li><b>WebView2 (Chromium):</b> UI w HTML5/CSS3/JS uruchomiony w TEdgeBrowser</li>' +
      '<li><b>REST API (HORSE):</b> Endpoint <code>/api/data</code></li>' +
      '<li><b>Parallel Programming (PPL):</b> Asynchroniczna synchronizacja i logika</li>' +
      '<li><b>Connection Pooling:</b> FireDAC (Pooled=True)</li>' +
      '<li><b>Multi-DB:</b> SQLite, MSSQL, Oracle, Firebird</li>' +
      '<li><b>Clean Architecture + DI:</b> Pe³na separacja warstw</li>' + '</ul>' +

      '<p style="color: #888; margin-top: 20px; font-style: italic;">' +
      'PrzejdŸ do zak³adki "Ustawienia", aby zarz¹dzaæ us³ugami serwera i synchronizacji.</p>';

    LSafeString := TJSONString.Create(LInfoHtml);
    try
      EdgeBrowserMain.ExecuteScript('setInfoContent(' + LSafeString.ToJSON + ');');
    finally
      LSafeString.Free;
    end;

    // Prze³¹cz na widok Informacji
    EdgeBrowserMain.ExecuteScript('switchView("view-info", document.querySelector("button[onclick*=''view-info'']"));');
    EdgeBrowserMain.Visible := True; // Ukazanie gotowego interfejsu
    LogMessage(lsSystem, 'Aplikacja uruchomiona. Interfejs za³adowany poprawnie');
  end
  else
    ShowMessage('B³¹d ³adowania interfejsu webowego');
end;

procedure TFormMain.btnExitClick;
begin
  // Zamkniêcie przegl¹darki przed zamkniêciem Formy rozwi¹zuje problem blokowania
  if Assigned(EdgeBrowserMain) then
    EdgeBrowserMain.CloseWebView;
  Close;
end;

procedure TFormMain.btnServerClick;
begin
  if Assigned(FHorseServer) and not FHorseServer.Started then
  begin
    FHorseServer.Start;
    EdgeBrowserMain.ExecuteScript('setServerState(true);');
    LogMessage(lsSystem, 'Serwer zosta³ uruchomiony');
  end
  else
  begin
    FHorseServer.Stop;
    EdgeBrowserMain.ExecuteScript('setServerState(false);');
    LogMessage(lsSystem, 'Serwer zosta³ zatrzymany');
  end;
end;

procedure TFormMain.btnSyncClick;
var
  LSyncService: ISyncService;
  LConfig: IAppConfig;
  LIntervalSec: Integer;
  LCurrentSession: Integer;
begin
  if Assigned(FWorker) then
  begin
    Inc(FSyncSession);
    FWorker.OnTerminate := nil;
    FWorker.Terminate;
    FWorker.WaitFor;
    FreeAndNil(FWorker);

    EdgeBrowserMain.ExecuteScript('setSyncState(false, 0);');
    LogMessage(lsSystem, 'Synchronizacja zosta³a zatrzymana');
  end
  else
  begin
    Inc(FSyncSession);
    LCurrentSession := FSyncSession;

    LSyncService := TContainer.Resolve<ISyncService>;
    LConfig := TContainer.Resolve<IAppConfig>;

    FWorker := TWorkerThread.Create(LSyncService, FLogger, LConfig.GetWorkerInterval);
    FWorker.Start;

    LIntervalSec := LConfig.GetWorkerInterval div 1000;
    EdgeBrowserMain.ExecuteScript(Format('setSyncState(true, %d);', [LIntervalSec]));
    LogMessage(lsSystem, 'Synchronizacja uruchomiona. Pobieranie danych w tle...');

    TTask.Run(
      procedure
      var
        LDatabase: IDatabaseManager;
        LJsonData: string;
        LLastId, LCurrentId: Integer;
      begin
        try
          LDatabase := TContainer.Resolve<IDatabaseManager>;
          LLastId := LDatabase.GetLastRecordId; // Zapamiêtujemy ID sprzed startu pêtli

          // Jeœli dok³adnie w tej samej milisekundzie TTask bêdzie chcia³ oceniæ warunek Assigned(FWorker)
          // mo¿e odczytaæ uwalnian¹ pamiêæ, dlatego zakomentowa³em {and Assigned(FWorker)}
          // Warunek sesyjny w zupe³noœci wystarczy
          // za ka¿dym klikniêciem przycisku g³ówny w¹tek najpierw robi Inc(FSyncSession),
          // uniewa¿niaj¹c LCurrentSession dla uœpionego TTasku,
          // a dopiero potem bezpiecznie zamyka Workera. To daje 100% bezpieczeñstwa.

          while (FSyncSession = LCurrentSession) do
          begin
            LCurrentId := LDatabase.GetLastRecordId;

            if LCurrentId > LLastId then // Sprawdzamy czy przyby³ nowy rekord (ID jest wiêksze)
            begin
              LLastId := LCurrentId; // Aktualizujemy pamiêæ ID
              LJsonData := LDatabase.GetDataAsJson; // Pobieramy ten nowy JSON

              TThread.Queue(nil,
                procedure
                var
                  LJsonObj: TJSONValue;
                begin
                  LogMessage(lsSystem, 'Zsynchronizowano nowy rekord z bazy:');
                  LJsonObj := TJSONObject.ParseJSONValue(LJsonData);
                  if Assigned(LJsonObj) then
                    try
                      ParseAndLogJson(LJsonObj);
                    finally
                      LJsonObj.Free;
                    end
                  else // W razie dziwnego tekstu
                    LogMessage(lsInfo, LJsonData);

                  LogMessage(lsSystem, '---------------------------------------------------');
                  EdgeBrowserMain.ExecuteScript('restartCountdown();');
                end);
            end;
            Sleep(1000);
          end;
        except
          on E: Exception do
          begin
            var
            LErrorMsg := E.Message;
            TThread.Queue(nil,
              procedure
              begin
                LogMessage(lsError, 'B³¹d bazy w TTask: ' + LErrorMsg);
              end);
          end;
        end;
      end);
  end;
end;


procedure TFormMain.SaveSettingsUpdate(const AApiUrl: string; AIntervalMs: Integer);
var
  LConfig: IAppConfig;
begin
  LConfig := TContainer.Resolve<IAppConfig>;
  LConfig.UpdateSettings(AApiUrl, AIntervalMs);
  LogMessage(lsSystem, 'Pomyœlnie zaktualizowano plik ustawieñ.');

  // Wyœwietlamy Modal (Wartoœæ 0 = Modal nie zamknie siê sam)
  EdgeBrowserMain.ExecuteScript('showGlobalModal("info", true, "Informacja", "Konfiguracja zapisana", "OK", 0, null);');

  if Assigned(FWorker) then
  begin
    btnSyncClick;
    btnSyncClick;
    LogMessage(lsInfo, 'Automatycznie zrestartowano us³ugê synchronizacji z nowymi parametrami.');
  end;
end;

// Umo¿liwia rozci¹ganie aplikacji bez ramek (bsNone) ³api¹c za krawêdzie okna
procedure TFormMain.WMNCHitTest(var Msg: TWMNCHitTest);
const
  EDGEDETECT = 7; // Gruboœæ strefy chwytania (7 pikseli)
var
  LDeltaRect: TRect;
begin
  inherited;
  if BorderStyle = bsNone then
  begin
    LDeltaRect := Rect(EDGEDETECT, EDGEDETECT, Width - EDGEDETECT, Height - EDGEDETECT);
    if not PtInRect(LDeltaRect, ScreenToClient(Mouse.CursorPos)) then
    begin
      if Mouse.CursorPos.Y < Top + EDGEDETECT then
      begin
        if Mouse.CursorPos.X < Left + EDGEDETECT then
          Msg.Result := HTTOPLEFT
        else
          if Mouse.CursorPos.X > Left + Width - EDGEDETECT then
            Msg.Result := HTTOPRIGHT
          else
            Msg.Result := HTTOP;
      end
      else
        if Mouse.CursorPos.Y > Top + Height - EDGEDETECT then
        begin
          if Mouse.CursorPos.X < Left + EDGEDETECT then
            Msg.Result := HTBOTTOMLEFT
          else
            if Mouse.CursorPos.X > Left + Width - EDGEDETECT then
              Msg.Result := HTBOTTOMRIGHT
            else
              Msg.Result := HTBOTTOM;
        end
        else
          if Mouse.CursorPos.X < Left + EDGEDETECT then
            Msg.Result := HTLEFT
          else
            if Mouse.CursorPos.X > Left + Width - EDGEDETECT then
              Msg.Result := HTRIGHT;
    end;
  end;
end;

procedure TFormMain.LogHtml(const AHtml: string);
begin
  TThread.Queue(nil,
    procedure
    var
      LScript: string;
      LJson: TJSONString;
    begin
      if (csDestroying in ComponentState) or not Assigned(EdgeBrowserMain.DefaultInterface) then
        Exit;

      LJson := TJSONString.Create(AHtml);
      try
        LScript := 'appendLog(' + LJson.ToJSON + ');';
      finally
        LJson.Free;
      end;
      EdgeBrowserMain.ExecuteScript(LScript);
    end);
end;

procedure TFormMain.LogMessage(AStatus: TLogStatus; const AMessage: string);
var
  LClass, LHtml: string;
begin
  case AStatus of
    lsSystem:
      LClass := 'sys';
    lsError:
      LClass := 'err';
    else
      LClass := 'info';
  end;
  LHtml := Format('<span class="time">[%s]</span><span class="%s">%s</span>', [FormatDateTime('hh:nn:ss', Now), LClass,
    AMessage]);
  LogHtml(LHtml);
end;

procedure TFormMain.ParseAndLogJson(AJsonValue: TJSONValue; const AIndentPx: Integer = 0);
var
  I: Integer;
  LPair: TJSONPair;
  LValueStr, LHtmlStr: string;
begin
  if AJsonValue is TJSONObject then
  begin
    for I := 0 to TJSONObject(AJsonValue).Count - 1 do
    begin
      LPair := TJSONObject(AJsonValue).Pairs[I];

      if (LPair.JsonValue is TJSONObject) or (LPair.JsonValue is TJSONArray) then
      begin
        LHtmlStr := Format('<div style="margin-left: %dpx"><span class="key">' + #$25A0 + ' %s:</span></div>',
          [AIndentPx, LPair.JsonString.Value]);
        LogHtml(LHtmlStr);
        ParseAndLogJson(LPair.JsonValue, AIndentPx + 20);
      end
      else
      begin
        LValueStr := LPair.JsonValue.Value;
        LHtmlStr := Format('<div style="margin-left: %dpx"><span class="key">' + #$25BA +
          ' %s:</span> <span class="info">%s</span></div>', [AIndentPx, LPair.JsonString.Value, LValueStr]);
        LogHtml(LHtmlStr);

        LValueStr := LowerCase(LValueStr);
        if LValueStr.StartsWith('http') and (LValueStr.EndsWith('.png') or LValueStr.EndsWith('.jpg') or
          LValueStr.EndsWith('.jpeg') or LValueStr.EndsWith('.gif') or LValueStr.EndsWith('.webp')) then
        begin
          LogHtml(Format('<div style="margin-left: %dpx"><img src="%s"></div>',
            [AIndentPx + 15, LPair.JsonValue.Value]));
        end;
      end;
    end;
  end
  else
    if AJsonValue is TJSONArray then
    begin
      for I := 0 to TJSONArray(AJsonValue).Count - 1 do
      begin
        LogHtml(Format('<div style="margin-left: %dpx"><span class="info">Wpis [%d]:</span></div>', [AIndentPx, I]));
        ParseAndLogJson(TJSONArray(AJsonValue).Items[I], AIndentPx + 20);
      end;
    end;
end;

function TFormMain.GetFormBackgroundColor: string;
var
  LColor: TColor;
begin
  if StyleServices.Enabled then
    LColor := StyleServices.GetSystemColor(Self.Color)
  else
    LColor := clWindow;

  LColor := ColorToRGB(LColor);

  Result := Format('#%.2x%.2x%.2x', [GetRValue(LColor), GetGValue(LColor), GetBValue(LColor)]);
end;

procedure TFormMain.OnWorkerTerminated(Sender: TObject);
begin
  // Jeœli VCL zacznie cykl niszczenia (FormDestroy) ZANIM w tle zakoñczy siê w¹tek,
  // aplikacja zawiesi siê w pamiêci RAM na komendzie WaitFor, poniewa¿ VCL zacz¹³
  // ju¿ niszczyæ mechanizmy synchronizacji wiadomoœci.
  // By jednoznacznie wymusiæ zakoñczenie zamiast Close stosuje Application.Terminate

  Application.Terminate;
end;

procedure TFormMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  var LConfig: IAppConfig := TContainer.Resolve<IAppConfig>;
  LConfig.SaveWindowState(Self.Left, Self.Top, Self.Width, Self.Height);

  if FIsClosing then
  begin
    CanClose := True;
    Exit;
  end;

  if Assigned(FHorseServer) then
    FHorseServer.Stop;

  if Assigned(FWorker) then
  begin
    CanClose := False;
    FIsClosing := True;
    FWorker.OnTerminate := OnWorkerTerminated;
    FWorker.Terminate;
    Self.Hide;
  end
  else
    CanClose := True;
end;

procedure TFormMain.FormCreate(Sender: TObject);
var
  LConfig: IAppConfig;
begin
  FIsClosing := False;
  FLogger := TContainer.Resolve<IAppLogger>;
  LConfig := TContainer.Resolve<IAppConfig>;

  // Self.Position := poDesigned; // Domyœlnie bêdziemy centrowaæ okno
  Self.Left := LConfig.GetWindowLeft;
  Self.Top := LConfig.GetWindowTop;
  Self.Width := LConfig.GetWindowWidth;
  Self.Height := LConfig.GetWindowHeight;

  EdgeBrowserMain.Visible := False;
  EdgeBrowserMain.UserDataFolder := ExtractFilePath(ParamStr(0));
  EdgeBrowserMain.CreateWebView;
  FHorseServer := THorseServerManager.Create(FLogger, LConfig.GetHorsePort);
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  if Assigned(FWorker) then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;

  if Assigned(FHorseServer) then
    FreeAndNil(FHorseServer);
end;

end.
