unit UI.PresenterMain;

interface

uses
  System.SysUtils,
  System.Classes,
  Core.Events,
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
    FSubs: TArray<IEventSubscription>;
    FIsDestroyed: Boolean;

    procedure SubscribeEvents;
  public
    constructor Create(aView: IMainView; aEventBus: IEventBus);
    destructor Destroy; override;

    procedure Init;
  end;

implementation

constructor TPresenterMain.Create(aView: IMainView; aEventBus: IEventBus);
begin
  inherited Create;
  FView := aView;
  FEventBus := aEventBus;
end;

destructor TPresenterMain.Destroy;
var
  i: Integer;
begin
  FIsDestroyed := True;

  for i := 0 to High(FSubs) do
    if Assigned(FSubs[i]) then
      FSubs[i].Unsubscribe;

  FView := nil;

  inherited;
end;

procedure TPresenterMain.Init;
begin
  SubscribeEvents;
end;

{ ================= EVENT SUBSCRIPTIONS ================= }

procedure TPresenterMain.SubscribeEvents;
begin
  // W każdym evencie operujemy wyłącznie na kopiach danych przed TThread.Queue!
  // np.:
  // var LType: TLogEventType := TLogEvent(AEvent).EventType;
  // var LMsg: string := TLogEvent(AEvent).Message;
  // var LIsRunning: Boolean := TSyncStateEvent(AEvent).IsRunning;
  // itd...

  SetLength(FSubs, 4);

  // LOG
  FSubs[0] := FEventBus.Subscribe(TLogEvent,
    procedure(AEvent: TObject)
    begin
      if FIsDestroyed then
        Exit;

      // kopiujemy dane
      var LType: TLogEventType := TLogEvent(AEvent).EventType;
      var LMsg: string := TLogEvent(AEvent).Message;

      TThread.Queue(nil,
        procedure
        var LView: IMainView;
        begin
          if FIsDestroyed then
            Exit;

          LView := FView;
          if Assigned(LView) then
            LView.ViewRenderLog(LType, LMsg);
        end);
    end);

  // SYNC STATE
  FSubs[1] := FEventBus.Subscribe(TSyncStateEvent,
    procedure(AEvent: TObject)
    begin
      if FIsDestroyed then
        Exit;

      // kopiujemy dane
      var LIsRunning: Boolean := TSyncStateEvent(AEvent).IsRunning;
      var LInterval: Integer := TSyncStateEvent(AEvent).IntervalSec;

      TThread.Queue(nil,
        procedure
        var LView: IMainView;
        begin
          if FIsDestroyed then
            Exit;

          LView := FView;
          if Assigned(LView) then
            LView.ViewUpdateSyncState(LIsRunning, LInterval);
        end);
    end);

  // SERVER STATE
  FSubs[2] := FEventBus.Subscribe(TServerStateEvent,
    procedure(AEvent: TObject)
    begin
      if FIsDestroyed then
        Exit;

      // kopiujemy dane
      var LIsRunning: Boolean := TServerStateEvent(AEvent).IsRunning;

      TThread.Queue(nil,
        procedure
        var LView: IMainView;
        begin
          if FIsDestroyed then
            Exit;

          LView := FView;
          if Assigned(LView) then
            LView.ViewUpdateServerState(LIsRunning);
        end);
    end);

  // NEW DATA
  FSubs[3] := FEventBus.Subscribe(TNewDataEvent,
    procedure(AEvent: TObject)
    begin
      if FIsDestroyed then
        Exit;

      // kopiujemy dane
      var LJson: string := TNewDataEvent(AEvent).Json;

      TThread.Queue(nil,
        procedure
        var LView: IMainView;
        begin
          if FIsDestroyed then
            Exit;

          LView := FView;
          if Assigned(LView) then
            LView.ViewDisplayNewData(LJson);
        end);
    end);
end;

end.
