unit Infrastructure.Config;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Core.Interfaces;

type
  TAppConfig = class(TInterfacedObject, IAppConfig)
  private
    FApiUrl: string;
    FApiKey: string;
    FDbType: TSupportedDatabase;
    FDbConnectionString: string;
    FLogPath: string;
    FWorkerInterval: Integer;
    FHorsePort: Integer;
    FWindowLeft: Integer;
    FWindowTop: Integer;
    FWindowWidth: Integer;
    FWindowHeight: Integer;
    function StringToDbType(const ATypeStr: string): TSupportedDatabase;
    procedure LoadFromFile(const AFileName: string);
    procedure CreateDefault(const AFileName: string);
  public
    constructor Create(const AFileName: string);
    function GetDbType: TSupportedDatabase;
    function GetDbConnectionString: string;
    function GetApiUrl: string;
    function GetApiKey: string;
    function GetLogPath: string;
    function GetWorkerInterval: Integer;
    function GetHorsePort: Integer;
    function GetWindowLeft: Integer;
    function GetWindowTop: Integer;
    function GetWindowWidth: Integer;
    function GetWindowHeight: Integer;
    procedure UpdateSettings(const AApiUrl: string; AWorkerInterval: Integer);
    procedure SaveWindowState(ALeft, ATop, AWidth, AHeight: Integer);
  end;

implementation

constructor TAppConfig.Create(const AFileName: string);
begin
  inherited Create;
  if TFile.Exists(AFileName) then
    LoadFromFile(AFileName)
  else
    CreateDefault(AFileName);
end;

procedure TAppConfig.UpdateSettings(const AApiUrl: string; AWorkerInterval: Integer);
var
  LJsonStr: string;
  LJson: TJSONObject;
  LPath: string;
  lPair: TJSONPair;
begin
  FApiUrl := AApiUrl;
  FWorkerInterval := AWorkerInterval;

  LPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'config.json');
  if TFile.Exists(LPath) then
  begin
    LJsonStr := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LJsonStr) as TJSONObject;
    if Assigned(LJson) then
      try
        // Zapisujemy nowe wartości do struktury JSON
        lPair := LJson.RemovePair('apiUrl');
        lPair.Free;
        LJson.AddPair('apiUrl', FApiUrl);
        lPair := LJson.RemovePair('workerIntervalMs');
        lPair.Free;
        LJson.AddPair('workerIntervalMs', TJSONNumber.Create(FWorkerInterval));

        // Nadpisujemy plik na dysku
        TFile.WriteAllText(LPath, LJson.Format(2), TEncoding.UTF8);
      finally
        LJson.Free;
      end;
  end;
end;

procedure TAppConfig.CreateDefault(const AFileName: string);
var
  LJson: TJSONObject;
begin
  LJson := TJSONObject.Create;
  try
    FApiUrl := 'https://randomuser.me/api';
    FDbType := dbSQLite;

    // Dla Oracle @ ODBC := "ODBCDriver=Oracle in OraClient11g_home1;DataSource=MójTNSName;User_Name=admin;Password=tajne"
    // Dla MS SQL @ ODBC := "Driver={ODBC Driver 17 for SQL Server};Server=ADRES_IP_LUB_NAZWA;Database=NAZWA_BAZY;Uid=UZYTKOWNIK;Pwd=HASLO;"
    // Dla Firebird i SQLite := nazwa_pliku
    FDbConnectionString := 'database.db';

    FLogPath := 'log.txt';
    FWorkerInterval := 15000;
    FHorsePort := 9000;
    FApiKey := 'SECRET_TOKEN_123'; // Domyślny klucz zabezpieczający
    FWindowLeft := 100;
    FWindowTop := 100;
    FWindowWidth := 1050;
    FWindowHeight := 800;

    LJson.AddPair('apiUrl', FApiUrl);
    LJson.AddPair('dbType', 'sqlite'); // Wartości: sqlite, oracle, firebird, mssql
    LJson.AddPair('dbConnectionString', FDbConnectionString);
    LJson.AddPair('logPath', FLogPath);
    LJson.AddPair('workerIntervalMs', TJSONNumber.Create(FWorkerInterval));
    LJson.AddPair('horsePort', TJSONNumber.Create(FHorsePort));
    LJson.AddPair('apiKey', FApiKey);
    LJson.AddPair('windowLeft', TJSONNumber.Create(FWindowLeft));
    LJson.AddPair('windowTop', TJSONNumber.Create(FWindowTop));
    LJson.AddPair('windowWidth', TJSONNumber.Create(FWindowWidth));
    LJson.AddPair('windowHeight', TJSONNumber.Create(FWindowHeight));

    TFile.WriteAllText(AFileName, LJson.Format(2), TEncoding.UTF8);
  finally
    LJson.Free;
  end;
end;

procedure TAppConfig.SaveWindowState(ALeft, ATop, AWidth, AHeight: Integer);
var
  LJsonStr, LPath: string;
  LJson: TJSONObject;
  lPair: TJSONPair;
begin
  FWindowLeft := ALeft;
  FWindowTop := ATop;
  FWindowWidth := AWidth;
  FWindowHeight := AHeight;
  LPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'config.json');
  if TFile.Exists(LPath) then
  begin
    LJsonStr := TFile.ReadAllText(LPath, TEncoding.UTF8);
    LJson := TJSONObject.ParseJSONValue(LJsonStr) as TJSONObject;
    if Assigned(LJson) then
      try
        lPair := LJson.RemovePair('windowLeft');
        lPair.Free;
        LJson.AddPair('windowLeft', TJSONNumber.Create(FWindowLeft));
        lPair := LJson.RemovePair('windowTop');
        lPair.Free;
        LJson.AddPair('windowTop', TJSONNumber.Create(FWindowTop));
        lPair := LJson.RemovePair('windowWidth');
        lPair.Free;
        LJson.AddPair('windowWidth', TJSONNumber.Create(FWindowWidth));
        lPair := LJson.RemovePair('windowHeight');
        lPair.Free;
        LJson.AddPair('windowHeight', TJSONNumber.Create(FWindowHeight));
        TFile.WriteAllText(LPath, LJson.Format(2), TEncoding.UTF8);
      finally
        LJson.Free;
      end;
  end;
end;

function TAppConfig.StringToDbType(const ATypeStr: string): TSupportedDatabase;
begin
  if SameText(ATypeStr, 'sqlite') then
    Result := dbSQLite
  else
    if SameText(ATypeStr, 'oracle') then
      Result := dbOracle
    else
      if SameText(ATypeStr, 'firebird') then
        Result := dbFirebird
      else
        if SameText(ATypeStr, 'mssql') then
          Result := dbMSSQL
        else
          Result := dbUnknown;
end;

procedure TAppConfig.LoadFromFile(const AFileName: string);
var
  LJsonStr, LDbString: string;
  LJson: TJSONObject;
begin
  LJsonStr := TFile.ReadAllText(AFileName, TEncoding.UTF8);
  LJson := TJSONObject.ParseJSONValue(LJsonStr) as TJSONObject;
  if Assigned(LJson) then
    try
      FApiUrl := LJson.GetValue('apiUrl').Value;
      LDbString := LJson.GetValue('dbType').Value;
      FDbType := StringToDbType(LDbString);
      FDbConnectionString := LJson.GetValue('dbConnectionString').Value;
      FLogPath := LJson.GetValue('logPath').Value;
      FWorkerInterval := (LJson.GetValue('workerIntervalMs') as TJSONNumber).AsInt;
      FHorsePort := (LJson.GetValue('horsePort') as TJSONNumber).AsInt;
      FApiKey := LJson.GetValue('apiKey').Value;

      if Assigned(LJson.GetValue('windowLeft')) then
      begin
        FWindowLeft := (LJson.GetValue('windowLeft') as TJSONNumber).AsInt;
        FWindowTop := (LJson.GetValue('windowTop') as TJSONNumber).AsInt;
        FWindowWidth := (LJson.GetValue('windowWidth') as TJSONNumber).AsInt;
        FWindowHeight := (LJson.GetValue('windowHeight') as TJSONNumber).AsInt;
      end
      else
      begin
        FWindowLeft := 100;
        FWindowTop := 100;
        FWindowWidth := 1200;
        FWindowHeight := 800;
      end;
    finally
      LJson.Free;
    end
end;

function TAppConfig.GetApiUrl: string;
begin
  Result := FApiUrl;
end;

function TAppConfig.GetApiKey: string;
begin
  Result := FApiKey;
end;

function TAppConfig.GetLogPath: string;
begin
  Result := FLogPath;
end;

function TAppConfig.GetWorkerInterval: Integer;
begin
  Result := FWorkerInterval;
end;

function TAppConfig.GetHorsePort: Integer;
begin
  Result := FHorsePort;
end;

function TAppConfig.GetDbType: TSupportedDatabase;
begin
  Result := FDbType;
end;

function TAppConfig.GetDbConnectionString: string;
begin
  Result := FDbConnectionString;
end;

function TAppConfig.GetWindowLeft: Integer;
begin
  Result := FWindowLeft;
end;

function TAppConfig.GetWindowTop: Integer;
begin
  Result := FWindowTop;
end;

function TAppConfig.GetWindowWidth: Integer;
begin
  Result := FWindowWidth;
end;

function TAppConfig.GetWindowHeight: Integer;
begin
  Result := FWindowHeight;
end;

end.
