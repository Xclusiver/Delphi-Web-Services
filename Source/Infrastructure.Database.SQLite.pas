unit Infrastructure.Database.SQLite;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Core.Interfaces,
  FireDAC.Comp.Client,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  Data.DB,
  FireDAC.DApt,
{$IFDEF FMX}
  FireDAC.FMXUI.Wait; // Używane, gdy kompilujemy dla FireMonkey
{$ELSE}
  FireDAC.VCLUI.Wait; // Domyślny dla VCL
{$ENDIF}

type
  TDbSQLiteManager = class(TInterfacedObject, IDatabaseManager)
  private
    FLogger: IAppLogger;
    function GetPooledConnection: TFDConnection;
  public
    constructor Create(const ALogger: IAppLogger);
    class procedure InitializePool(const ADatabasePath: string);
    class procedure DestroyPool;
    class procedure InitializeDatabase;
    function GetRecordCount: Integer;
    function GetLastRecordId: Integer;
    function GetDataAsJson: string;
    function GetAllDataAsJsonArray: string;
    procedure SaveData(const AJsonData: string);
    procedure UpdateData(AId: Integer; const ANewJson: string);
  end;

const
  POOL_DEF_NAME = 'MyDataSyncPool';

implementation

constructor TDbSQLiteManager.Create(const ALogger: IAppLogger);
begin
  inherited Create;
  FLogger := ALogger; // Logger wstrzyknięty przez DI
end;

class procedure TDbSQLiteManager.InitializeDatabase;
var
  LConn: TFDConnection;
begin
  LConn := TFDConnection.Create(nil);
  try
    LConn.ConnectionDefName := POOL_DEF_NAME;
    LConn.Open;

    LConn.ExecSQL('CREATE TABLE IF NOT EXISTS MyTable (' + '  Id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      '  Data TEXT NOT NULL, ' + '  CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP' + ')');
  finally
    LConn.Free;
  end;
end;

class procedure TDbSQLiteManager.InitializePool(const ADatabasePath: string);
var
  LParams: TStringList;
begin
  LParams := TStringList.Create;
  try
    LParams.Add('Database=' + ADatabasePath);
    LParams.Add('LockingMode=Normal'); // Ważne dla SQLite przy wielowątkowości
    LParams.Add('Synchronous=Normal');
    LParams.Add('JournalMode=WAL');
    LParams.Add('BusyTimeout=10000');
    LParams.Add('Pooled=True');
    LParams.Add('POOL_MaximumItems=50');

    FDManager.AddConnectionDef(POOL_DEF_NAME, 'SQLite', LParams);
    FDManager.Active := True;
  finally
    LParams.Free;
  end;
end;

class procedure TDbSQLiteManager.DestroyPool;
begin
  FDManager.Close;
end;

function TDbSQLiteManager.GetPooledConnection: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := POOL_DEF_NAME;
  // W momencie wykonania .Open(), FireDAC pobiera z puli otwarte fizyczne połączenie
  Result.Open;
end;

procedure TDbSQLiteManager.SaveData(const AJsonData: string);
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
begin
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LConn.StartTransaction;
      try
        LQuery.SQL.Text := 'INSERT INTO MYTABLE (Data) VALUES (:data)';
        LQuery.ParamByName('data').AsString := AJsonData;
        LQuery.ExecSQL;
        LConn.Commit;
        FLogger.LogInfo('Pomyślnie zsynchronizowano dane do bazy.');
      except
        on E: Exception do
        begin
          LConn.Rollback;
          FLogger.LogError('Błąd podczas zapisu do bazy: ' + E.Message, E);
          raise;
        end;
      end;
    finally
      LQuery.Free;
    end;
  finally
    // Zwrócenie połączenia do puli
    LConn.Free;
  end;
end;

procedure TDbSQLiteManager.UpdateData(AId: Integer; const ANewJson: string);
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
begin
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LConn.StartTransaction;
      try
        LQuery.SQL.Text := 'UPDATE MyTable SET Data = :data WHERE Id = :id';
        LQuery.ParamByName('data').AsString := ANewJson;
        LQuery.ParamByName('id').AsInteger := AId;
        LQuery.ExecSQL;
        LConn.Commit;
        FLogger.LogInfo(Format('Zaktualizowano w bazie zedytowany na Gridzie rekord o ID: %d', [AId]));
      except
        on E: Exception do
        begin
          LConn.Rollback;
          FLogger.LogError(Format('Błąd aktualizacji rekordu ID %d: %s', [AId, E.Message]), E);
          raise;
        end;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TDbSQLiteManager.GetRecordCount: Integer;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
begin
  Result := 0;
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := 'SELECT COUNT(Id) AS Cnt FROM MyTable';
      LQuery.Open;
      Result := LQuery.FieldByName('Cnt').AsInteger;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TDbSQLiteManager.GetDataAsJson: string;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
begin
  Result := '';
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := 'SELECT Data FROM MyTable ORDER BY Id DESC LIMIT 1';
      LQuery.Open;
      if not LQuery.IsEmpty then
        Result := LQuery.FieldByName('Data').AsString;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TDbSQLiteManager.GetLastRecordId: Integer;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
begin
  Result := 0;
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := 'SELECT MAX(Id) AS MaxId FROM MyTable';
      LQuery.Open;
      if not LQuery.FieldByName('MaxId').IsNull then
        Result := LQuery.FieldByName('MaxId').AsInteger;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TDbSQLiteManager.GetAllDataAsJsonArray: string;
var
  LConn: TFDConnection;
  LQuery: TFDQuery;
  LJsonArray: TJSONArray;
  LJsonRow: TJSONObject;
begin
  Result := '[]';
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := 'SELECT Id, Data, CreatedAt FROM MyTable ORDER BY Id DESC';
      LQuery.Open;

      LJsonArray := TJSONArray.Create;
      try
        while not LQuery.Eof do
        begin
          LJsonRow := TJSONObject.Create;
          try
            LJsonRow.AddPair('id', TJSONNumber.Create(LQuery.FieldByName('Id').AsInteger));
            LJsonRow.AddPair('data', LQuery.FieldByName('Data').AsString);
            LJsonRow.AddPair('created_at', LQuery.FieldByName('CreatedAt').AsString);
            LJsonArray.AddElement(LJsonRow);
            LJsonRow := nil; // ownership przejęte przez array
          finally
            LJsonRow.Free;
          end;
          LQuery.Next;
        end;
        // ToJSON automatycznie i bezbłędnie sformatuje stringi, ucieczki i cudzysłowy!
        Result := LJsonArray.ToJSON;
      finally
        LJsonArray.Free;
      end;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

end.
