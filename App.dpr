program App;

{$R *.dres}

uses
  Vcl.Forms,
  System.IOUtils,
  System.SysUtils,
  Core.Interfaces in 'Source\Core.Interfaces.pas',
  Core.Events in 'Source\Core.Events.pas',
  Infrastructure.EventBus in 'Source\Infrastructure.EventBus.pas',
  Infrastructure.Config in 'Source\Infrastructure.Config.pas',
  Infrastructure.Container in 'Source\Infrastructure.Container.pas',
  Infrastructure.Logger in 'Source\Infrastructure.Logger.pas',
  Infrastructure.ApiClient in 'Source\Infrastructure.ApiClient.pas',
  Infrastructure.Database.SQLite in 'Source\Infrastructure.Database.SQLite.pas',
  Infrastructure.Database.Firebird in 'Source\Infrastructure.Database.Firebird.pas',
  Infrastructure.Database.Oracle in 'Source\Infrastructure.Database.Oracle.pas',
  Infrastructure.Database.MSSQL in 'Source\Infrastructure.Database.MSSQL.pas',
  Services.Sync in 'Source\Services.Sync.pas',
  Services.HorseServer in 'Source\Services.HorseServer.pas',
  UI.PresenterMain in 'Source\UI.PresenterMain.pas',
  UI.FormMain in 'Source\UI.FormMain.pas';

{$R *.res}

var
  LEventBus: IEventBus;
  LConfig: IAppConfig;
  LAppLogger: IAppLogger;
  LConfigPath: string;

begin
  ReportMemoryLeaksOnShutdown := True;
  
  LConfigPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'config.json');
  LConfig := TAppConfig.Create(LConfigPath);
  LAppLogger := TFileLogger.Create(LConfig.GetLogPath);  
  LEventBus := TEventBus.Create;

  TContainer.RegisterType<IEventBus>(
    function: IEventBus
    begin
      Result := LEventBus;
    end);

  // Inicjalizacja puli bazy danych (Œcie¿ka z pliku konfiguracyjnego)
  case LConfig.GetDbType of
    dbSQLite:
      begin
        TDbSQLiteManager.InitializePool(LConfig.GetDbConnectionString);
        TDbSQLiteManager.InitializeDatabase;
        TContainer.RegisterType<IDatabaseManager>(
          function: IDatabaseManager
          begin
            Result := TDbSQLiteManager.Create(TContainer.Resolve<IAppLogger>);
          end);
      end;

    dbOracle:
      begin
        TDbOracleManager.InitializePool(LConfig.GetDbConnectionString);
        TDbOracleManager.InitializeDatabase;
        TContainer.RegisterType<IDatabaseManager>(
          function: IDatabaseManager
          begin
            Result := TDbOracleManager.Create(TContainer.Resolve<IAppLogger>);
          end);
      end;

    dbFirebird:
      begin
        TDbFirebirdManager.InitializePool(LConfig.GetDbConnectionString);
        TDbFirebirdManager.InitializeDatabase;
        TContainer.RegisterType<IDatabaseManager>(
          function: IDatabaseManager
          begin
            Result := TDbFirebirdManager.Create(TContainer.Resolve<IAppLogger>);
          end);
      end;

    dbMSSQL:
      begin
        TDbMSSQLManager.InitializePool(LConfig.GetDbConnectionString);
        TDbMSSQLManager.InitializeDatabase;
        TContainer.RegisterType<IDatabaseManager>(
          function: IDatabaseManager
          begin
            Result := TDbMSSQLManager.Create(TContainer.Resolve<IAppLogger>);
          end);
      end;

    dbUnknown:
      begin
        raise Exception.Create('Nieznany typ bazy danych');
      end;
  end;

  // Konfiguracja DI
  TContainer.RegisterType<IAppConfig>(
    function: IAppConfig
    begin
      Result := LConfig;
    end);
  TContainer.RegisterType<IAppLogger>(
    function: IAppLogger
    begin
      Result := LAppLogger;
    end);

  TContainer.RegisterType<IApiClient>(
    function: IApiClient
    begin
      // Dynamiczny URL z pliku konfiguracyjnego
      Result := TRestApiClient.Create(TContainer.Resolve<IAppLogger>, TContainer.Resolve<IAppConfig>.GetApiUrl);
    end);

  TContainer.RegisterType<ISyncService>(
    function: ISyncService
    begin
      Result := TSyncService.Create(TContainer.Resolve<IAppLogger>(), TContainer.Resolve<IApiClient>(),
        TContainer.Resolve<IDatabaseManager>());
    end);

  // Uruchomienie aplikacji
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;

  // Sprz¹tanie
  case LConfig.GetDbType of
    dbOracle:
      TDbOracleManager.DestroyPool;
    dbFirebird:
      TDbFirebirdManager.DestroyPool;
    dbMSSQL:
      TDbMSSQLManager.DestroyPool;
    else
      TDbSQLiteManager.DestroyPool;
  end;

end.
