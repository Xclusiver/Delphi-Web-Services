unit Infrastructure.ApiClient;

interface

uses
  System.SysUtils,
  System.Net.HttpClient,
  Core.Interfaces;

type
  TRestApiClient = class(TInterfacedObject, IApiClient)
  private
    FLogger: IAppLogger;
    FUrl: string;
  public
    constructor Create(const ALogger: IAppLogger; const AUrl: string);
    function FetchData: string;
  end;

implementation

constructor TRestApiClient.Create(const ALogger: IAppLogger; const AUrl: string);
begin
  inherited Create;
  FLogger := ALogger;
  FUrl := AUrl;
end;

function TRestApiClient.FetchData: string;
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
begin
  Result := '';
  LClient := THTTPClient.Create;
  try
    // Ustawienie Timeouts, by wątek nie zawiesił się w nieskończoność
    LClient.ConnectionTimeout := 5000;
    LClient.ResponseTimeout := 5000;

    try
      LResponse := LClient.Get(FUrl);
      if LResponse.StatusCode = 200 then
        Result := LResponse.ContentAsString(TEncoding.UTF8)
      else
        FLogger.LogError(Format('Błąd HTTP %d', [LResponse.StatusCode]));
    except
      on E: ENetHTTPClientException do
        FLogger.LogError('Timeout lub błąd sieci w ApiClient: ' + E.Message);
      on E: Exception do
        FLogger.LogError('Inny wyjątek w ApiClient', E);
    end;
  finally
    LClient.Free;
  end;
end;

end.
