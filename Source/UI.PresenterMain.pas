unit UI.PresenterMain;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  Core.Events,
  Core.Interfaces,
  Infrastructure.EventBus;

type
  IMainView = interface
    procedure ViewRenderLog(AType: TLogEventType; const AMessage: string);
    procedure ViewUpdateSyncState(AIsRunning: Boolean; AInterval: Integer);
    procedure ViewUpdateServerState(AIsRunning: Boolean);
    procedure ViewDisplayNewData(const AJson: string);
  end;

  TPresenterMain = class
  private
    FEventBus: IEventBus;
    FView: IMainView;
    FIsDestroyed: Boolean;

    FLogHandler: TEventHandler;
    FSyncHandler: TEventHandler;
    FServerHandler: TEventHandler;
    FDataHandler: TEventHandler;

    procedure SubscribeEvents;
    procedure UnsubscribeEvents;
  public
    constructor Create(aView: IMainView; aEventBus: IEventBus);
    destructor Destroy; override;

    procedure Init;
  end;

implementation

constructor TPresenterMain.Create(aView: IMainView; aEventBus: IEventBus);
begin
  inherited Create;

  // Bez REF COUNT
  Pointer(FView) := Pointer(aView);
  FEventBus := aEventBus;
end;

destructor TPresenterMain.Destroy;
begin
  FIsDestroyed := True;
  UnsubscribeEvents;

  // Dodatkowe zerowanie
  Pointer(FView) := nil;
  inherited;
end;

procedure TPresenterMain.Init;
begin
  SubscribeEvents;
end;

procedure TPresenterMain.SubscribeEvents;
begin
  // LOG
  FLogHandler := procedure(AEvent: TObject)
  var
    LView: IMainView;
    LType: TLogEventType;
    LMsg: string;
  begin
    if FIsDestroyed then Exit;

    LView := FView;
    if LView = nil then Exit;

    var E := TLogEvent(AEvent);
    LType := E.EventType;
    LMsg := E.Message;

    TThread.Queue(nil,
      procedure
      begin
        if FIsDestroyed or (LView = nil) then Exit;
        LView.ViewRenderLog(LType, LMsg);
      end);
  end;

  FEventBus.Subscribe(TLogEvent, FLogHandler);

  // SYNC
  FSyncHandler := procedure(AEvent: TObject)
  var
    LView: IMainView;
    LRunning: Boolean;
    LInterval: Integer;
  begin
    if FIsDestroyed then Exit;

    LView := FView;
    if LView = nil then Exit;

    var E := TSyncStateEvent(AEvent);
    LRunning := E.IsRunning;
    LInterval := E.IntervalSec;

    TThread.Queue(nil,
      procedure
      begin
        if FIsDestroyed or (LView = nil) then Exit;
        LView.ViewUpdateSyncState(LRunning, LInterval);
      end);
  end;

  FEventBus.Subscribe(TSyncStateEvent, FSyncHandler);

  // SERVER
  FServerHandler := procedure(AEvent: TObject)
  var
    LView: IMainView;
    LRunning: Boolean;
  begin
    if FIsDestroyed then Exit;

    LView := FView;
    if LView = nil then Exit;

    var E := TServerStateEvent(AEvent);
    LRunning := E.IsRunning;

    TThread.Queue(nil,
      procedure
      begin
        if FIsDestroyed or (LView = nil) then Exit;
        LView.ViewUpdateServerState(LRunning);
      end);
  end;

  FEventBus.Subscribe(TServerStateEvent, FServerHandler);

  // DATA
  FDataHandler := procedure(AEvent: TObject)
  var
    LView: IMainView;
    LJson: string;
  begin
    if FIsDestroyed then Exit;

    LView := FView;
    if LView = nil then Exit;

    var E := TNewDataEvent(AEvent);
    LJson := E.Json;

    TThread.Queue(nil,
      procedure
      begin
        if FIsDestroyed or (LView = nil) then Exit;
        LView.ViewDisplayNewData(LJson);
      end);
  end;

  FEventBus.Subscribe(TNewDataEvent, FDataHandler);
end;

procedure TPresenterMain.UnsubscribeEvents;
begin
  if Assigned(FEventBus) then
  begin
    FEventBus.Unsubscribe(TLogEvent, FLogHandler);
    FEventBus.Unsubscribe(TSyncStateEvent, FSyncHandler);
    FEventBus.Unsubscribe(TServerStateEvent, FServerHandler);
    FEventBus.Unsubscribe(TNewDataEvent, FDataHandler);
  end;

  FLogHandler := nil;
  FSyncHandler := nil;
  FServerHandler := nil;
  FDataHandler := nil;
end;

end.
