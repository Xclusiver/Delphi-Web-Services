unit Infrastructure.Database.MSSQL;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Core.Interfaces,
  Data.DB,
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
  FireDAC.Phys.ODBCBase,
  FireDAC.Phys.ODBCCli,
  FireDAC.Phys.ODBCWrapper,
{$IFDEF FMX}
  FireDAC.FMXUI.Wait; // Używane, gdy kompilujemy dla FireMonkey
{$ELSE}
  FireDAC.VCLUI.Wait; // Domyślny dla VCL
{$ENDIF}

type
  TDbMSSQLManager = class(TInterfacedObject, IDatabaseManager)
  private
    FLogger: IAppLogger;
    function GetPooledConnection: TFDConnection;
  public
    constructor Create(const ALogger: IAppLogger);
    class procedure InitializePool(const AConnectionString: string);
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
  POOL_DEF_NAME_MSSQL = 'MyDataSyncPool_MSSQL';

implementation

constructor TDbMSSQLManager.Create(const ALogger: IAppLogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

class procedure TDbMSSQLManager.InitializeDatabase;
var
  LConn: TFDConnection;
begin
  LConn := TFDConnection.Create(nil);
  try
    LConn.ConnectionDefName := POOL_DEF_NAME_MSSQL;
    LConn.Open;
    LConn.ExecSQL('IF OBJECT_ID(''MyTable'', ''U'') IS NULL ' +
      'CREATE TABLE MyTable (Id INT IDENTITY(1,1) PRIMARY KEY, ' +
      'Data NVARCHAR(MAX) NOT NULL, CreatedAt DATETIME DEFAULT GETDATE())');
  finally
    LConn.Free;
  end;
end;

class procedure TDbMSSQLManager.InitializePool(const AConnectionString: string);
var
  LParams: TStringList;
begin
  LParams := TStringList.Create;
  try
    // Parametry z connection stringa np. Server=...;Database=...;User_Name=...;Password=...
    LParams.Text := StringReplace(AConnectionString, ';', sLineBreak, [rfReplaceAll]);
    LParams.Add('DriverID=MSSQL');
    LParams.Add('Pooled=True');
    LParams.Add('POOL_MaximumItems=50');
    FDManager.AddConnectionDef(POOL_DEF_NAME_MSSQL, 'MSSQL', LParams);
    FDManager.Active := True;
  finally
    LParams.Free;
  end;
end;

class procedure TDbMSSQLManager.DestroyPool;
begin
  FDManager.Close;
end;

function TDbMSSQLManager.GetPooledConnection: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.ConnectionDefName := POOL_DEF_NAME_MSSQL;
  Result.Open;
end;

procedure TDbMSSQLManager.SaveData(const AJsonData: string);
var LConn: TFDConnection; LQuery: TFDQuery;
begin
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LConn.StartTransaction;
      try
        LQuery.SQL.Text := 'INSERT INTO MyTable (Data) VALUES (:data)';
        LQuery.ParamByName('data').AsWideString := AJsonData; // NVARCHAR = AsWideString
        LQuery.ExecSQL;
        LConn.Commit;
      except
        on E: Exception do
        begin
          LConn.Rollback;
          FLogger.LogError('Błąd zapisu MSSQL: ' + E.Message, E);
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

procedure TDbMSSQLManager.UpdateData(AId: Integer; const ANewJson: string);
var LConn: TFDConnection; LQuery: TFDQuery;
begin
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LConn.StartTransaction;
      try
        LQuery.SQL.Text := 'UPDATE MyTable SET Data = :data WHERE Id = :id';
        LQuery.ParamByName('data').AsWideString := ANewJson;
        LQuery.ParamByName('id').AsInteger := AId;
        LQuery.ExecSQL;
        LConn.Commit;
      except
        on E: Exception do
        begin
          LConn.Rollback;
          FLogger.LogError('Błąd aktualizacji MSSQL', E);
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

function TDbMSSQLManager.GetRecordCount: Integer;
var LConn: TFDConnection; LQuery: TFDQuery;
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

function TDbMSSQLManager.GetLastRecordId: Integer;
var LConn: TFDConnection; LQuery: TFDQuery;
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

function TDbMSSQLManager.GetDataAsJson: string;
var LConn: TFDConnection; LQuery: TFDQuery;
begin
  Result := '';
  LConn := GetPooledConnection;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConn;
      LQuery.SQL.Text := 'SELECT TOP 1 Data FROM MyTable ORDER BY Id DESC';
      LQuery.Open;
      if not LQuery.IsEmpty then
        Result := LQuery.FieldByName('Data').AsWideString;
    finally
      LQuery.Free;
    end;
  finally
    LConn.Free;
  end;
end;

function TDbMSSQLManager.GetAllDataAsJsonArray: string;
var LConn: TFDConnection; LQuery: TFDQuery; LJsonArray: TJSONArray; LJsonRow: TJSONObject;
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
            LJsonRow.AddPair('data', LQuery.FieldByName('Data').AsWideString);
            LJsonRow.AddPair('created_at', LQuery.FieldByName('CreatedAt').AsString);
            LJsonArray.AddElement(LJsonRow);
            LJsonRow := nil;
          finally
            LJsonRow.Free;
          end;
          LQuery.Next;
        end;
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
