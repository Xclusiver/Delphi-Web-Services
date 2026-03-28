unit Infrastructure.EventBus;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs;

type
  TEventHandler = reference to procedure(AEvent: TObject);

  IEventBus = interface
    ['{A7C1B2E3-9F45-4D21-8A77-123456789ABC}']
    procedure Subscribe(AEventClass: TClass; const AHandler: TEventHandler);
    procedure Unsubscribe(AEventClass: TClass; const AHandler: TEventHandler);
    procedure Publish(AEvent: TObject);
  end;

  TEventBus = class(TInterfacedObject, IEventBus)
  private
    FHandlers: TDictionary<TClass, TList<TEventHandler>>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Subscribe(AEventClass: TClass; const AHandler: TEventHandler);
    procedure Unsubscribe(AEventClass: TClass; const AHandler: TEventHandler);
    procedure Publish(AEvent: TObject);
  end;

implementation

constructor TEventBus.Create;
begin
  inherited;
  FHandlers := TDictionary<TClass, TList<TEventHandler>>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TEventBus.Destroy;
var
  LList: TList<TEventHandler>;
begin
  for LList in FHandlers.Values do
    LList.Free;

  FHandlers.Free;
  FLock.Free;
  inherited;
end;

procedure TEventBus.Subscribe(AEventClass: TClass; const AHandler: TEventHandler);
begin
  FLock.Enter;
  try
    if not FHandlers.ContainsKey(AEventClass) then
      FHandlers.Add(AEventClass, TList<TEventHandler>.Create);

    FHandlers[AEventClass].Add(AHandler);
  finally
    FLock.Leave;
  end;
end;

procedure TEventBus.Unsubscribe(AEventClass: TClass; const AHandler: TEventHandler);
var
  LList: TList<TEventHandler>;
begin
  FLock.Enter;
  try
    if FHandlers.TryGetValue(AEventClass, LList) then
      LList.Remove(AHandler);
  finally
    FLock.Leave;
  end;
end;

procedure TEventBus.Publish(AEvent: TObject);
var
  LHandlers: TArray<TEventHandler>;
  LList: TList<TEventHandler>;
  LHandler: TEventHandler;
begin
  FLock.Enter;
  try
    if not FHandlers.TryGetValue(AEvent.ClassType, LList) then
    begin
      AEvent.Free;
      Exit;
    end;

    LHandlers := LList.ToArray; // snapshot
  finally
    FLock.Leave;
  end;

  try
    for LHandler in LHandlers do
      LHandler(AEvent);
  finally
    AEvent.Free; // kontrolowane miejsce zwolnienia
  end;
end;

end.
