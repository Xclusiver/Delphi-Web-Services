unit Infrastructure.Container;

interface

uses
  System.SysUtils,
  System.TypInfo,
  System.Generics.Collections,
  System.SyncObjs,
  Core.Interfaces;

type
  TContainer = class
  private
    class var FRegistry: TDictionary<TGUID, TFunc<IInterface>>;
    class var FLock: TCriticalSection;
  public
    class constructor Create;
    class destructor Destroy;

    // Rejestracja zależności (AFactory to funkcja anonimowa tworząca obiekt)
    class procedure RegisterType<T: IInterface>(const AFactory: TFunc<T>);

    // Wyciąganie gotowego obiektu
    class function Resolve<T: IInterface>: T;
  end;

implementation

class constructor TContainer.Create;
begin
  FRegistry := TDictionary < TGUID, TFunc < IInterface >>.Create;
  FLock := TCriticalSection.Create;
end;

class destructor TContainer.Destroy;
begin
  FLock.Free;
  FRegistry.Free;
end;

class procedure TContainer.RegisterType<T>(const AFactory: TFunc<T>);
var
  LTypeInfo: PTypeInfo;
  LGUID: TGUID;
begin
  FLock.Enter;
  try
    LTypeInfo := TypeInfo(T);
    LGUID := GetTypeData(LTypeInfo)^.Guid;

    FRegistry.AddOrSetValue(LGUID,
      function: IInterface
      begin
        Result := AFactory();
      end);
  finally
    FLock.Leave;
  end;
end;

class function TContainer.Resolve<T>: T;
var
  LTypeInfo: PTypeInfo;
  LGUID: TGUID;
  LFactory: TFunc<IInterface>;
begin
  FLock.Enter;
  try
    LTypeInfo := TypeInfo(T);
    LGUID := GetTypeData(LTypeInfo)^.Guid;

    if not FRegistry.TryGetValue(LGUID, LFactory) then
      raise Exception.CreateFmt('Typ %s nie został zarejestrowany w kontenerze', [LTypeInfo^.Name]);

    // Tworzymy instancję i rzutujemy na konkretny typ
    Result := T(LFactory());
  finally
    FLock.Leave;
  end;
end;

end.
