unit Core.Interfaces;

interface

uses
  System.SysUtils;

type
  TSupportedDatabase = (dbSQLite, dbOracle, dbFirebird, dbMSSQL, dbUnknown);

  IAppLogger = interface
    ['{4E9C0D6A-34FC-4CF4-94F2-FCD134D336E3}']
    procedure LogInfo(const AMessage: string);
    procedure LogError(const AMessage: string; const AException: Exception = nil);
  end;

  IDatabaseManager = interface
    ['{1F2E3D4C-5B6A-7F8E-9D0C-1B2A3F4E5D6C}']
    function GetRecordCount: Integer;
    function GetLastRecordId: Integer;
    function GetDataAsJson: string;
    function GetAllDataAsJsonArray: string;
    procedure SaveData(const AJsonData: string);
    procedure UpdateData(AId: Integer; const ANewJson: string);
  end;

  IApiClient = interface
    ['{A1B2C3D4-E5F6-47B8-9A1C-2D3E4F5A6B7C}']
    function FetchData: string;
  end;

  ISyncService = interface
    ['{C3D4E5F6-A7B8-4C9D-1E2F-3A4B5C6D7E8F}']
    procedure ExecuteSync;
  end;

  IAppConfig = interface
    ['{9C62D10D-1868-42DB-B90B-B4ED871D890E}']
    function GetApiUrl: string;
    function GetApiKey: string;
    function GetDbType: TSupportedDatabase;
    function GetDbConnectionString: string;
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

end.
