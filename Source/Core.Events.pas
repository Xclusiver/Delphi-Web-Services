unit Core.Events;

interface

type
  TNewDataEvent = class
  private
    FJson: string;
  public
    constructor Create(const AJson: string);
    property Json: string read FJson;
  end;

  TLogEventType = (letInfo, letSystem, letError);

  TLogEvent = class
  private
    FEventType: TLogEventType;
    FMessage: string;
  public
    constructor Create(AType: TLogEventType; const AMessage: string);
    property EventType: TLogEventType read FEventType;
    property Message: string read FMessage;
  end;

  TSyncStateEvent = class
  private
    FIsRunning: Boolean;
    FIntervalSec: Integer;
  public
    constructor Create(AIsRunning: Boolean; AIntervalSec: Integer);
    property IsRunning: Boolean read FIsRunning;
    property IntervalSec: Integer read FIntervalSec;
  end;

  TServerStateEvent = class
  private
    FIsRunning: Boolean;
  public
    constructor Create(AIsRunning: Boolean);
    property IsRunning: Boolean read FIsRunning;
  end;

implementation

constructor TNewDataEvent.Create(const AJson: string);
begin
  FJson := AJson;
end;

constructor TLogEvent.Create(AType: TLogEventType; const AMessage: string);
begin
  FEventType := AType;
  FMessage := AMessage;
end;

constructor TSyncStateEvent.Create(AIsRunning: Boolean; AIntervalSec: Integer);
begin
  FIsRunning := AIsRunning;
  FIntervalSec := AIntervalSec;
end;

constructor TServerStateEvent.Create(AIsRunning: Boolean);
begin
  FIsRunning := AIsRunning;
end;

end.
