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
  System.SyncObjs,
  System.Threading,
  System.NetEncoding,
  System.Generics.Collections,
  Winapi.WebView2,
  Winapi.ActiveX,
  Services.Sync,
  Services.HorseServer,
  Core.Interfaces,
  Core.Events,
  Infrastructure.Container,
  Infrastructure.EventBus,
  UI.PresenterMain;

type
  TLogStatus = (lsInfo, lsSystem, lsError);

  TFormMain = class(TForm, IMainView)
    EdgeBrowserMain: TEdgeBrowser;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    procedure EdgeBrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
    procedure EdgeBrowserWebMessageReceived(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
    procedure EdgeBrowserNavigationCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
      WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
  private
    FHorseServer: THorseServerManager;
    FLogger: IAppLogger;
    FIsClosing: Boolean;
    FEventBus: IEventBus;
    FSyncTask: ITask;
    FDbWatcherTask: ITask;
    FStopEvent: TEvent;
    FPresenter: TPresenterMain;
    FCommandHandlers: TDictionary<string, TProc<string>>;

    function LoadHtmlFromResource: string;
    function GetFormBackgroundColor: string;
    procedure WMNCHitTest(var Msg: TWMNCHitTest); message WM_NCHITTEST;
    procedure SafeExecuteScript(const AScript: string);

    procedure UILogHtml(const AHtml: string);
    procedure UILogMessage(AStatus: TLogStatus; const AMessage: string);
    procedure UIParseAndLogJson(AJsonValue: TJSONValue; const AIndentPx: Integer = 0);

    procedure CommandHandle;
    procedure CommandComplexHandle(const ACmd: string);

    procedure OnSyncRequested;
    procedure OnServerToggleRequested;
    procedure OnSaveSettingsUpdateRequested(const AApiUrl: string; AIntervalMs: Integer);
    procedure OnExitRequested;
  public
    // IMainView
    procedure ViewRenderLog(AType: TLogEventType; const AMessage: string);
    procedure ViewDisplayNewData(const AJson: string);
    procedure ViewUpdateSyncState(AIsRunning: Boolean; AInterval: Integer);
    procedure ViewUpdateServerState(AIsRunning: Boolean);
  end;

const
  NOTIFY_CLOSE_SEC = 7;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

{ ================= TOOLS UI ================= }

procedure ExecuteWithRetry(const AProc: TProc; ARetries: Integer = 3);
begin
  for var i := 1 to ARetries do
  begin
    try
      AProc;
      Exit;
    except
      on E: Exception do
      begin
        if i = ARetries then
          raise;

        Sleep(500 * i);
      end;
    end;
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

procedure TFormMain.SafeExecuteScript(const AScript: string);
begin
  if FIsClosing then
    Exit;
  if not Assigned(EdgeBrowserMain) then
    Exit;
  if not Assigned(EdgeBrowserMain.DefaultInterface) then
    Exit;
  if csDestroying in ComponentState then
    Exit;

  EdgeBrowserMain.ExecuteScript(AScript);
end;

{ ================= WEB ================= }

procedure TFormMain.EdgeBrowserWebMessageReceived(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
var
  LMessage: PChar;
  LCmd: string;
  LHandler: TProc<string>;
  LJsonVal: TJSONValue;
begin
  if not Succeeded(Args.ArgsInterface.Get_webMessageAsJson(LMessage)) then
    Exit;

  try
    LJsonVal := TJSONObject.ParseJSONValue(string(LMessage));
    try
      if Assigned(LJsonVal) then
        LCmd := LJsonVal.Value
      else
        LCmd := string(LMessage);
    finally
      LJsonVal.Free;
    end;

    if FCommandHandlers.TryGetValue(LCmd, LHandler) then
    begin
      LHandler(LCmd);
      Exit;
    end;

    // obs³uga bardziej z³o¿onych komend
    CommandComplexHandle(LCmd);

  finally
    CoTaskMemFree(LMessage);
  end;
end;

procedure TFormMain.EdgeBrowserCreateWebViewCompleted(Sender: TCustomEdgeBrowser; AResult: HRESULT);
begin
  // Skrypty zostan¹ wykonane dopiero w EdgeBrowserLogNavigationCompleted!
  if Succeeded(AResult) then
    EdgeBrowserMain.NavigateToString(LoadHtmlFromResource)
  else
    ShowMessage('B³¹d inicjalizacji przegl¹darki');
end;

procedure TFormMain.EdgeBrowserNavigationCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
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
      SafeExecuteScript('setInfoContent(' + LSafeString.ToJSON + ');');
    finally
      LSafeString.Free;
    end;

    // Prze³¹cz na widok Informacji
    SafeExecuteScript('switchView("view-info", document.querySelector("button[onclick*=''view-info'']"));');
    EdgeBrowserMain.Visible := True;
    UILogMessage(lsSystem, 'Aplikacja uruchomiona. Interfejs za³adowany poprawnie');
  end
  else
    ShowMessage('B³¹d ³adowania interfejsu webowego');
end;

{ ================= COMMAND WEB HANDLE ================= }

procedure TFormMain.CommandHandle;
begin
  FCommandHandlers := TDictionary < string, TProc < string >>.Create;

  FCommandHandlers.Add('SYNC',
    procedure(ACmd: string)
    begin
      OnSyncRequested;
    end);

  FCommandHandlers.Add('SERVER',
    procedure(ACmd: string)
    begin
      OnServerToggleRequested;
    end);

  FCommandHandlers.Add('EXIT',
    procedure(ACmd: string)
    begin
      OnExitRequested;
    end);

  FCommandHandlers.Add('DRAG_WINDOW',
    procedure(ACmd: string)
    begin
      ReleaseCapture;
      Perform(WM_SYSCOMMAND, $F012, 0);
    end);

  FCommandHandlers.Add('REQ_SETTINGS_FORM',
    procedure(ACmd: string)
    begin
      var LConfig: IAppConfig := TContainer.Resolve<IAppConfig>;
      var LSecs: Integer := LConfig.GetWorkerInterval div 1000; // Wartoœæ w sekundach
      SafeExecuteScript(Format('loadSettingsForm("%s", %d);', [LConfig.GetApiUrl, LSecs]));
    end);

  FCommandHandlers.Add('REQ_GRID_DATA',
    procedure(ACmd: string)
    begin
      var LDatabase: IDatabaseManager := TContainer.Resolve<IDatabaseManager>;
      var LJsonArray: string := LDatabase.GetAllDataAsJsonArray;
      var LSafeString: TJSONString := TJSONString.Create(LJsonArray);
      try
        SafeExecuteScript('loadGridData(' + LSafeString.ToJSON + ');');
      finally
        LSafeString.Free;
      end
    end);
end;

procedure TFormMain.CommandComplexHandle(const ACmd: string);
begin
  var LParts: TArray<string>;
  if ACmd.StartsWith('UPDATE_RECORD|') then
  begin
    LParts := ACmd.Split(['|'], 4);

    if Length(LParts) = 4 then
    begin
      var LDb: IDatabaseManager := TContainer.Resolve<IDatabaseManager>;
      LDb.UpdateData(StrToIntDef(LParts[1], 0), LParts[3]);
      UILogMessage(lsInfo, Format('Zaktualizowano rekord ID: %s', [LParts[1]]));
    end;
  end
  else
    if ACmd.StartsWith('SAVE_SETTINGS|') then
    begin
      LParts := ACmd.Split(['|']);
      if Length(LParts) >= 3 then
        OnSaveSettingsUpdateRequested(LParts[1], StrToIntDef(LParts[2], 60) * 1000); // x1000 bo musimy mieæ milisekundy
    end;
end;

{ ================= ACTIONS ================= }

procedure TFormMain.OnExitRequested;
begin
  // Zamkniêcie przegl¹darki przed zamkniêciem Formy rozwi¹zuje problem blokowania
  if Assigned(EdgeBrowserMain) then
    EdgeBrowserMain.CloseWebView;
  Close;
end;

procedure TFormMain.OnServerToggleRequested;
begin
  if Assigned(FHorseServer) and not FHorseServer.Started then
  begin
    FHorseServer.Start;
    FEventBus.Publish(TServerStateEvent.Create(True));
    UILogMessage(lsSystem, 'Serwer zosta³ uruchomiony');
  end
  else
  begin
    FHorseServer.Stop;
    FEventBus.Publish(TServerStateEvent.Create(False));
    UILogMessage(lsSystem, 'Serwer zosta³ zatrzymany');
  end;
end;

procedure TFormMain.OnSyncRequested;
var
  LSyncService: ISyncService;
  LConfig: IAppConfig;
  LIntervalMs: Integer;
begin
  // Stop
  if Assigned(FSyncTask) then
  begin
    FStopEvent.SetEvent;
    try
      FSyncTask.Wait;
      FDbWatcherTask.Wait;
    except
    end;

    FSyncTask := nil;
    FDbWatcherTask := nil;

    FEventBus.Publish(TSyncStateEvent.Create(False, 0));
    UILogMessage(lsSystem, 'Synchronizacja zosta³a zatrzymana');
    Exit;
  end;

  // Start
  LSyncService := TContainer.Resolve<ISyncService>;
  LConfig := TContainer.Resolve<IAppConfig>;
  LIntervalMs := LConfig.GetWorkerInterval;
  FStopEvent.ResetEvent;

  // Task 1: API -> DB
  FSyncTask := TTask.Run(
    procedure
    begin
      UILogMessage(lsSystem, 'Task Sync START');

      while (not FIsClosing) and (FStopEvent.WaitFor(LIntervalMs) = wrTimeout) do
      begin
        try
          ExecuteWithRetry(
            procedure
            begin
              LSyncService.ExecuteSync;
            end);
        except
          on E: Exception do
            TThread.Queue(nil,
              procedure
              begin
                UILogMessage(lsError, 'B³¹d SyncTask: ' + E.Message);
              end);
        end;
      end;

      UILogMessage(lsSystem, 'Task Sync STOP');
    end);

  // Task 2: DB -> UI
  FDbWatcherTask := TTask.Run(
    procedure
    var
      LDatabase: IDatabaseManager;
      LLastId, LCurrentId: Integer;
    begin
      UILogMessage(lsSystem, 'Task DB Watcher START');

      try
        LDatabase := TContainer.Resolve<IDatabaseManager>;
        LLastId := LDatabase.GetLastRecordId;

        while (not FIsClosing) and (FStopEvent.WaitFor(1000) = wrTimeout) do
        begin
          try
            LCurrentId := LDatabase.GetLastRecordId;

            if LCurrentId > LLastId then
            begin
              LLastId := LCurrentId;
              FEventBus.Publish(TNewDataEvent.Create(LDatabase.GetDataAsJson));
            end;

          except
            on E: Exception do
              TThread.Queue(nil,
                procedure
                begin
                  UILogMessage(lsError, 'B³¹d DB Watcher: ' + E.Message);
                end);
          end;
        end;

      finally
        UILogMessage(lsSystem, 'Task DB Watcher STOP');
      end;
    end);

  FEventBus.Publish(TSyncStateEvent.Create(True, LIntervalMs div 1000));
  UILogMessage(lsSystem, 'Synchronizacja uruchomiona (PPL)');
end;

procedure TFormMain.OnSaveSettingsUpdateRequested(const AApiUrl: string; AIntervalMs: Integer);
var
  LConfig: IAppConfig;
begin
  LConfig := TContainer.Resolve<IAppConfig>;
  LConfig.UpdateSettings(AApiUrl, AIntervalMs);
  UILogMessage(lsSystem, 'Pomyœlnie zaktualizowano plik ustawieñ.');

  // Wyœwietlamy Modal (Wartoœæ 0 = Modal nie zamknie siê sam)
  SafeExecuteScript('showGlobalModal("info", true, "Informacja", "Konfiguracja zapisana", "OK", 0, null);');

  if Assigned(FSyncTask) then
  begin
    OnSyncRequested;
    OnSyncRequested; // To celowe
    UILogMessage(lsInfo, 'Automatycznie zrestartowano us³ugê synchronizacji z nowymi parametrami.');
  end;
end;

{ ================= LOG UI ================= }

procedure TFormMain.UILogHtml(const AHtml: string);
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
      SafeExecuteScript(LScript);
    end);
end;

procedure TFormMain.UILogMessage(AStatus: TLogStatus; const AMessage: string);
var
  LType: TLogEventType;
begin
  case AStatus of
    lsSystem:
      LType := letSystem;
    lsError:
      LType := letError;
    else
      LType := letInfo;
  end;

  FEventBus.Publish(TLogEvent.Create(LType, AMessage));
end;

procedure TFormMain.UIParseAndLogJson(AJsonValue: TJSONValue; const AIndentPx: Integer = 0);
var
  i: Integer;
  LPair: TJSONPair;
  LValueStr, LHtmlStr: string;
begin
  if AJsonValue is TJSONObject then
  begin
    for i := 0 to TJSONObject(AJsonValue).Count - 1 do
    begin
      LPair := TJSONObject(AJsonValue).Pairs[i];

      if (LPair.JsonValue is TJSONObject) or (LPair.JsonValue is TJSONArray) then
      begin
        LHtmlStr := Format('<div style="margin-left: %dpx"><span class="key">' + #$25A0 + ' %s:</span></div>',
          [AIndentPx, LPair.JsonString.Value]);
        UILogHtml(LHtmlStr);
        UIParseAndLogJson(LPair.JsonValue, AIndentPx + 20);
      end
      else
      begin
        LValueStr := LPair.JsonValue.Value;
        LHtmlStr := Format('<div style="margin-left: %dpx"><span class="key">' + #$25BA +
          ' %s:</span> <span class="info">%s</span></div>', [AIndentPx, LPair.JsonString.Value, LValueStr]);
        UILogHtml(LHtmlStr);

        LValueStr := LowerCase(LValueStr);
        if LValueStr.StartsWith('http') and (LValueStr.EndsWith('.png') or LValueStr.EndsWith('.jpg') or
          LValueStr.EndsWith('.jpeg') or LValueStr.EndsWith('.gif') or LValueStr.EndsWith('.webp')) then
        begin
          UILogHtml(Format('<div style="margin-left: %dpx"><img src="%s"></div>',
            [AIndentPx + 15, LPair.JsonValue.Value]));
        end;
      end;
    end;
  end
  else
    if AJsonValue is TJSONArray then
    begin
      for i := 0 to TJSONArray(AJsonValue).Count - 1 do
      begin
        UILogHtml(Format('<div style="margin-left: %dpx"><span class="info">Wpis [%d]:</span></div>', [AIndentPx, i]));
        UIParseAndLogJson(TJSONArray(AJsonValue).Items[i], AIndentPx + 20);
      end;
    end;
end;

{ ================= FORM ================= }

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

  FIsClosing := True;
  CanClose := True;
end;

procedure TFormMain.FormCreate(Sender: TObject);
var
  LConfig: IAppConfig;
begin
  FIsClosing := False;
  FLogger := TContainer.Resolve<IAppLogger>;
  FEventBus := TContainer.Resolve<IEventBus>;
  LConfig := TContainer.Resolve<IAppConfig>;

  FPresenter := TPresenterMain.Create(Self, FEventBus);
  FPresenter.Init;

  FStopEvent := TEvent.Create(nil, True, False, '');
  FHorseServer := THorseServerManager.Create(FLogger, LConfig.GetHorsePort);

  // Self.Position := poDesigned; // Domyœlnie bêdziemy centrowaæ okno
  Self.Left := LConfig.GetWindowLeft;
  Self.Top := LConfig.GetWindowTop;
  Self.Width := LConfig.GetWindowWidth;
  Self.Height := LConfig.GetWindowHeight;

  EdgeBrowserMain.Visible := False;
  EdgeBrowserMain.UserDataFolder := ExtractFilePath(ParamStr(0));
  EdgeBrowserMain.CreateWebView;
  CommandHandle;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  FIsClosing := True;

  // 1. NAJPIERW PRESENTER (odcina EventBus + UI callbacks)
  FreeAndNil(FPresenter);

  // 2. STOP TASKS
  if Assigned(FStopEvent) then
  begin
    FStopEvent.SetEvent;

    if Assigned(FSyncTask) then
    begin
      try
        FSyncTask.Wait;
      except
      end;
      FSyncTask := nil;
    end;

    if Assigned(FDbWatcherTask) then
    begin
      try
        FDbWatcherTask.Wait;
      except
      end;
      FDbWatcherTask := nil;
    end;

    FreeAndNil(FStopEvent);
  end;

  // 3. SERVER
  FreeAndNil(FHorseServer);

  // 4. INNE
  FreeAndNil(FCommandHandlers);
end;

{ ================= VIEW ================= }

procedure TFormMain.ViewRenderLog(AType: TLogEventType; const AMessage: string);
var
  LClass, LHtml: string;
begin
  case AType of
    letSystem:
      LClass := 'sys';
    letError:
      LClass := 'err';
    else
      LClass := 'info';
  end;

  LHtml := Format('<span class="time">[%s]</span><span class="%s">%s</span>', [FormatDateTime('hh:nn:ss', Now), LClass,
    AMessage]);

  UILogHtml(LHtml);
end;

procedure TFormMain.ViewDisplayNewData(const AJson: string);
var
  LJsonObj: TJSONValue;
begin
  UILogMessage(lsSystem, 'Nowy rekord z EventBus:');

  LJsonObj := TJSONObject.ParseJSONValue(AJson);
  if Assigned(LJsonObj) then
    try
      UIParseAndLogJson(LJsonObj);
    finally
      LJsonObj.Free;
    end
  else
    UILogMessage(lsInfo, AJson);

  UILogMessage(lsSystem, '---------------------------------------------------');
  SafeExecuteScript('restartCountdown();');
end;

procedure TFormMain.ViewUpdateSyncState(AIsRunning: Boolean; AInterval: Integer);
begin
  SafeExecuteScript(Format('setSyncState(%s,%d);', [LowerCase(BoolToStr(AIsRunning, True)), AInterval]));
end;

procedure TFormMain.ViewUpdateServerState(AIsRunning: Boolean);
begin
  SafeExecuteScript(Format('setServerState(%s);', [LowerCase(BoolToStr(AIsRunning, True))]));
end;

end.
