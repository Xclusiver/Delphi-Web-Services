unit Infrastructure.EventBus;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs;

type
  TEventHandler = reference to procedure(AEvent: TObject);

  IEventSubscription = interface
    ['{D9C5B6E2-8C61-4F8D-9A4E-112233445566}']
    procedure Unsubscribe;
  end;

  IEventBus = interface
    ['{A7C1B2E3-9F45-4D21-8A77-123456789ABC}']
    function Subscribe(AEventClass: TClass; const AHandler: TEventHandler): IEventSubscription;
    procedure Publish(AEvent: TObject);
  end;

  TEventSubscription = class(TInterfacedObject, IEventSubscription)
  private
    FToken: Integer;
    FBus: Pointer;
  public
    constructor Create(AToken: Integer; ABus: Pointer);
    procedure Unsubscribe;
  end;

  TEventBus = class(TInterfacedObject, IEventBus)
  private type
    THandlerRec = record
      Token: Integer;
      Handler: TEventHandler;
    end;

  private
    FHandlers: TDictionary<TClass, TList<THandlerRec>>;
    FLock: TCriticalSection;
    FNextToken: Integer;
    FShuttingDown: Boolean;

    procedure RemoveHandler(AToken: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    function Subscribe(AEventClass: TClass; const AHandler: TEventHandler): IEventSubscription;
    procedure Publish(AEvent: TObject);
  end;

implementation

constructor TEventSubscription.Create(AToken: Integer; ABus: Pointer);
begin
  inherited Create;
  FToken := AToken;
  FBus := ABus;
end;

procedure TEventSubscription.Unsubscribe;
begin
  if Assigned(FBus) then
  begin
    TEventBus(FBus).RemoveHandler(FToken);
    FBus := nil;
  end;
end;

constructor TEventBus.Create;
begin
  inherited;
  FHandlers := TDictionary < TClass, TList < THandlerRec >>.Create;
  FLock := TCriticalSection.Create;
  FNextToken := 1;
end;

destructor TEventBus.Destroy;
var
  LList: TList<THandlerRec>;
begin
  FShuttingDown := True;

  for LList in FHandlers.Values do
    LList.Free;

  FHandlers.Free;
  FLock.Free;

  inherited;
end;

function TEventBus.Subscribe(AEventClass: TClass; const AHandler: TEventHandler): IEventSubscription;
var
  LList: TList<THandlerRec>;
  LRec: THandlerRec;
begin
  FLock.Enter;
  try
    if not FHandlers.TryGetValue(AEventClass, LList) then
    begin
      LList := TList<THandlerRec>.Create;
      FHandlers.Add(AEventClass, LList);
    end;

    LRec.Token := FNextToken;
    Inc(FNextToken);
    LRec.Handler := AHandler;

    LList.Add(LRec);

    Result := TEventSubscription.Create(LRec.Token, Self);
  finally
    FLock.Leave;
  end;
end;

procedure TEventBus.RemoveHandler(AToken: Integer);
var
  LList: TList<THandlerRec>;
  i: Integer;
begin
  FLock.Enter;
  try
    for LList in FHandlers.Values do
    begin
      for i := LList.Count - 1 downto 0 do
        if LList[i].Token = AToken then
          LList.Delete(i);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TEventBus.Publish(AEvent: TObject);
var
  LHandlers: TArray<THandlerRec>;
  LList: TList<THandlerRec>;
  LRec: THandlerRec;
begin
  if FShuttingDown then
  begin
    AEvent.Free;
    Exit;
  end;

  FLock.Enter;
  try
    if not FHandlers.TryGetValue(AEvent.ClassType, LList) then
    begin
      AEvent.Free;
      Exit;
    end;

    LHandlers := LList.ToArray;
  finally
    FLock.Leave;
  end;

  try
    for LRec in LHandlers do
    begin
      try
        LRec.Handler(AEvent);
      except
        on E: Exception do
        begin
          // NIE wywalaj aplikacji
        end;
      end;
    end;
  finally
    AEvent.Free;
  end;
end;

end.
