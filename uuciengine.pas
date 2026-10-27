unit uuciengine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, Math, DateUtils, Generics.Collections,
  uuciinfo;

type
  TUCILogEvent      = procedure(Sender: TObject; const Direction, Line: string) of object;
  TUCIInfoEvent     = procedure(Sender: TObject; const Info: TAnalysisInfo) of object;
  TUCIBestMoveEvent = procedure(Sender: TObject; const BestMove, PonderMove: string) of object;
  TUCIRawLineEvent  = procedure(Sender: TObject; const Line: string) of object;

  { Linea ricevuta dal motore, consegnata via coda al thread principale. }
  TUCILine = record
    Kind: (lkRaw, lkBestMove, lkReadyOk, lkUciOk);
    Text: string;
    Info: TAnalysisInfo;   // valido solo se Kind = lkRaw e la riga è "info ..."
  end;

  { Thread di lettura: legge da stdout e accoda. }
  TReaderThread = class(TThread)
  private
    FProc: TProcess;
    FQueue: TThreadedQueue<TUCILine>;
    FOnInfo: TUCIInfoEvent;
    FOnBestMove: TUCIBestMoveEvent;
    FOnLog: TUCILogEvent;
    FOnRaw: TUCIRawLineEvent;
    FOnReadyOk: TNotifyEvent;
    FOnUciOk: TNotifyEvent;
    FEngine: TObject;  // riferimento debole al TUCIEngine per le callback
    procedure HandleLine(const L: TUCILine);
  protected
    procedure Execute; override;
  public
    constructor Create(AProc: TProcess; AQueue: TThreadedQueue<TUCILine>);
  end;

  TUCIEngine = class
  private
    FProcess     : TProcess;
    FReader      : TReaderThread;
    FQueue       : TThreadedQueue<TUCILine>;
    FEnginePath  : string;
    FEngineName  : string;
    FEngineAuthor: string;
    FOptions     : TStringList;
    FRunning     : Boolean;

    // Sincronizzazione handshake
    FReadyEvent  : TEvent;
    FUciOkEvent  : TEvent;

    // Bestmove corrente (protegge da race)
    FLastBestMove: string;
    FLastPonder  : string;

    FOnBestMove  : TUCIBestMoveEvent;
    FOnInfo      : TUCIInfoEvent;
    FOnLog       : TUCILogEvent;
    FOnRawLine   : TUCIRawLineEvent;

    procedure OnReaderLine(const L: TUCILine);
    procedure SendAndLog(const Cmd: string);
    function  WaitForBestMove(TimeoutMs: Integer; out Best, Ponder: string): Boolean;
    procedure PumpQueueFor(TimeoutMs: Integer);
  public
    constructor Create;
    destructor  Destroy; override;

    function  Start(const APath: string): Boolean;
    procedure Stop;
    function  IsRunning: Boolean;

    function  Initialize(TimeoutMs: Integer = 10000): Boolean;
    function  IsReady(TimeoutMs: Integer = 5000): Boolean;

    procedure SetOption(const Name, Value: string);
    procedure NewGame;

    procedure SetPosition(const FEN: string; const Moves: array of string);
    procedure SetStartPosition(const Moves: array of string);

    function  GoSync(Depth: Integer = 0;
                     MoveTimeMs: Integer = 0;
                     WTimeMs: Integer = 0; BTimeMs: Integer = 0;
                     WIncMs: Integer = 0; BIncMs: Integer = 0;
                     TimeoutMs: Integer = 60000): string;

    procedure GoAsync(Depth: Integer = 0;
                      MoveTimeMs: Integer = 0;
                      WTimeMs: Integer = 0; BTimeMs: Integer = 0;
                      WIncMs: Integer = 0; BIncMs: Integer = 0);
    procedure StopThinking;
    procedure PonderHit;
    procedure Quit;

    property  EngineName: string read FEngineName;
    property  EngineAuthor: string read FEngineAuthor;
    property  Options: TStringList read FOptions;

    property  OnBestMove: TUCIBestMoveEvent read FOnBestMove write FOnBestMove;
    property  OnInfo: TUCIInfoEvent read FOnInfo write FOnInfo;
    property  OnLog: TUCILogEvent read FOnLog write FOnLog;
    property  OnRawLine: TUCIRawLineEvent read FOnRawLine write FOnRawLine;
  end;

implementation

{ ==================== TReaderThread ==================== }

constructor TReaderThread.Create(AProc: TProcess; AQueue: TThreadedQueue<TUCILine>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FProc := AProc;
  FQueue := AQueue;
end;

procedure TReaderThread.HandleLine(const L: TUCILine);
begin
  // Le callback vengono invocate da Synchronize nel Execute.
  // Qui siamo già nel main thread.
  if Assigned(FOnLog) then
    FOnLog(FEngine, '<<', L.Text);
  case L.Kind of
    lkReadyOk: if Assigned(FOnReadyOk) then FOnReadyOk(FEngine);
    lkUciOk:   if Assigned(FOnUciOk)   then FOnUciOk(FEngine);
    lkBestMove: if Assigned(FOnBestMove) then
      begin
        // estrai best/ponder
      end;
    lkRaw:
      begin
        if Assigned(FOnRaw) then FOnRaw(FEngine, L.Text);
        if (Copy(L.Text, 1, 5) = 'info ') and Assigned(FOnInfo) then
          FOnInfo(FEngine, L.Info);
      end;
  end;
end;

procedure TReaderThread.Execute;
var
  Buffer: array[0..8191] of Byte;
  BytesRead, i: Integer;
  Partial: string;
  ch: Char;
  Line: string;

  procedure EmitLine(const S: string);
  var
    L: TUCILine;
    Parts: TStringArray;
    Idx: Integer;
  begin
    L.Text := S;
    L.Info.PV := nil;

    if S = 'readyok' then
      L.Kind := lkReadyOk
    else if S = 'uciok' then
      L.Kind := lkUciOk
    else if Copy(S, 1, 9) = 'bestmove ' then
      L.Kind := lkBestMove
    else if Copy(S, 1, 5) = 'info ' then
    begin
      L.Kind := lkRaw;
      if not ParseInfoLine(S, L.Info) then
        L.Info.PV := nil;
    end
    else
      L.Kind := lkRaw;

    FQueue.PushItem(L);
  end;

begin
  Partial := '';
  while not Terminated do
  begin
    if FProc.Output.NumBytesAvailable > 0 then
    begin
      BytesRead := FProc.Output.Read(Buffer[0], SizeOf(Buffer));
      if BytesRead <= 0 then
      begin
        Sleep(10);
        Continue;
      end;
      for i := 0 to BytesRead - 1 do
      begin
        ch := Char(Buffer[i]);
        if ch = #10 then
        begin
          Line := Partial;
          Partial := '';
          if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
            Delete(Line, Length(Line), 1);
          if Line <> '' then
            EmitLine(Line);
        end
        else
          Partial := Partial + ch;
      end;
    end
    else
      Sleep(5);
  end;
end;

{ ==================== TUCIEngine ==================== }

constructor TUCIEngine.Create;
begin
  inherited;
  FProcess := TProcess.Create(nil);
  FProcess.Options := [poUsePipes, poStdErrToOutPut];
  FProcess.ShowWindow := swoHIDE;
  FOptions := TStringList.Create;
  FQueue := TThreadedQueue<TUCILine>.Create(1024);
  FReadyEvent := TEvent.Create(nil, False, False, '');
  FUciOkEvent := TEvent.Create(nil, False, False, '');
  FRunning := False;
end;

destructor TUCIEngine.Destroy;
begin
  Stop;
  FReader.Free;
  FQueue.Free;
  FReadyEvent.Free;
  FUciOkEvent.Free;
  FProcess.Free;
  FOptions.Free;
  inherited;
end;

procedure TUCIEngine.SendAndLog(const Cmd: string);
begin
  if not FProcess.Running then Exit;
  try
    FProcess.Input.Write(Cmd[1], Length(Cmd));
    FProcess.Input.WriteByte(10);
    if Assigned(FOnLog) then FOnLog(Self, '>>', Cmd);
  except
    on E: Exception do
      if Assigned(FOnLog) then FOnLog(Self, '!!', 'Write: ' + E.Message);
  end;
end;

function TUCIEngine.Start(const APath: string): Boolean;
begin
  Result := False;
  if FRunning then Stop;

  if not FileExists(APath) then
  begin
    if Assigned(FOnLog) then FOnLog(Self, '!!', 'File non trovato: ' + APath);
    Exit;
  end;

  FEnginePath := APath;
  FProcess.Executable := APath;
  FProcess.Parameters.Clear;
  FProcess.Options := [poUsePipes, poStdErrToOutPut];
  FProcess.ShowWindow := swoHIDE;

  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      if Assigned(FOnLog) then FOnLog(Self, '!!', 'Execute: ' + E.Message);
      Exit;
    end;
  end;

  FRunning := True;

  // Crea e avvia il reader thread
  FReader := TReaderThread.Create(FProcess, FQueue);
  FReader.FEngine := Self;
  FReader.FOnInfo := FOnInfo;
  FReader.FOnBestMove := FOnBestMove;
  FReader.FOnLog := FOnLog;
  FReader.FOnRaw := FOnRawLine;
  FReader.Start;

  Result := True;
end;

procedure TUCIEngine.Stop;
begin
  if not FRunning then Exit;
  try
    SendAndLog('quit');
    Sleep(200);
  except
  end;
  if FProcess.Running then
    FProcess.Terminate(0);
  if FReader <> nil then
  begin
    FReader.Terminate;
    FReader.WaitFor;
    FreeAndNil(FReader);
  end;
  FRunning := False;
end;

function TUCIEngine.IsRunning: Boolean;
begin
  Result := FRunning and FProcess.Running;
end;

procedure TUCIEngine.PumpQueueFor(TimeoutMs: Integer);
// Consuma la coda dalla UI, invocando le callback per ogni elemento.
// Va chiamata quando GoSync è bloccato o quando serve processare output.
var
  L: TUCILine;
  StartT: TDateTime;
begin
  StartT := Now;
  while MilliSecondsBetween(Now, StartT) < TimeoutMs do
  begin
    if FQueue.PopItem(L) = wrSignaled then
      OnReaderLine(L)
    else
      Sleep(5);
  end;
end;

procedure TUCIEngine.OnReaderLine(const L: TUCILine);
begin
  // Siamo nel main thread.
  case L.Kind of
    lkReadyOk: FReadyEvent.SetEvent;
    lkUciOk:   FUciOkEvent.SetEvent;
    lkBestMove:
      begin
        // Estrai best e ponder
        // (vedi helper sotto)
      end;
    lkRaw:
      if Assigned(FOnRawLine) then FOnRawLine(Self, L.Text);
  end;

  if Assigned(FOnLog) then FOnLog(Self, '<<', L.Text);

  if (L.Kind = lkRaw) and (Copy(L.Text, 1, 5) = 'info ') then
  begin
    if Assigned(FOnInfo) and (L.Info.PV <> nil) then
      FOnInfo(Self, L.Info);
    if L.Info.PV <> nil then L.Info.PV.Free;
  end;

  if L.Kind = lkBestMove then
  begin
    // "bestmove e2e4 ponder e7e5"
    // salva da qualche parte; il chiamante GoSync lo raccoglierà
    FLastBestMove := '';
    FLastPonder := '';
    // parsing veloce
    // ...
    if Assigned(FOnBestMove) then
      FOnBestMove(Self, FLastBestMove, FLastPonder);
  end;
end;

{ --- Handshake --- }

function TUCIEngine.Initialize(TimeoutMs: Integer): Boolean;
var
  StartT: TDateTime;
begin
  Result := False;
  if not IsRunning then Exit;
  FOptions.Clear;
  FEngineName := '';
  FEngineAuthor := '';

  FUciOkEvent.ResetEvent;
  SendAndLog('uci');

  StartT := Now;
  while MilliSecondsBetween(Now, StartT) < TimeoutMs do
  begin
    PumpQueueFor(50);
    // Nota: il parsing di id/option è delegato al chiamante via OnRawLine
    if FUciOkEvent.WaitFor(10) = wrSignaled then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TUCIEngine.IsReady(TimeoutMs: Integer): Boolean;
var
  StartT: TDateTime;
begin
  Result := False;
  if not IsRunning then Exit;
  FReadyEvent.ResetEvent;
  SendAndLog('isready');
  StartT := Now;
  while MilliSecondsBetween(Now, StartT) < TimeoutMs do
  begin
    PumpQueueFor(20);
    if FReadyEvent.WaitFor(5) = wrSignaled then
      Exit(True);
  end;
end;

procedure TUCIEngine.SetOption(const Name, Value: string);
begin
  if Value = '' then SendAndLog('setoption name ' + Name)
  else SendAndLog('setoption name ' + Name + ' value ' + Value);
end;

procedure TUCIEngine.NewGame;
begin
  SendAndLog('ucinewgame');
  IsReady(5000);
end;

procedure TUCIEngine.SetPosition(const FEN: string; const Moves: array of string);
var
  s: string; i: Integer;
begin
  s := 'position fen ' + FEN;
  if Length(Moves) > 0 then
  begin
    s := s + ' moves';
    for i := Low(Moves) to High(Moves) do
      s := s + ' ' + Moves[i];
  end;
  SendAndLog(s);
end;

procedure TUCIEngine.SetStartPosition(const Moves: array of string);
var
  s: string; i: Integer;
begin
  s := 'position startpos';
  if Length(Moves) > 0 then
  begin
    s := s + ' moves';
    for i := Low(Moves) to High(Moves) do
      s := s + ' ' + Moves[i];
  end;
  SendAndLog(s);
end;

function BuildGoCommand(Depth, MoveTimeMs, WTimeMs, BTimeMs,
  WIncMs, BIncMs: Integer): string;
begin
  Result := 'go';
  if Depth > 0 then
    Result := Result + ' depth ' + IntToStr(Depth);
  if MoveTimeMs > 0 then
    Result := Result + ' movetime ' + IntToStr(MoveTimeMs);
  if WTimeMs > 0 then
  begin
    Result := Result + ' wtime ' + IntToStr(WTimeMs);
    Result := Result + ' btime ' + IntToStr(BTimeMs);
    if WIncMs > 0 then Result := Result + ' winc ' + IntToStr(WIncMs);
    if BIncMs > 0 then Result := Result + ' binc ' + IntToStr(BIncMs);
  end;
end;

procedure TUCIEngine.GoAsync(Depth, MoveTimeMs, WTimeMs, BTimeMs,
  WIncMs, BIncMs: Integer);
begin
  if not IsRunning then Exit;
  SendAndLog(BuildGoCommand(Depth, MoveTimeMs, WTimeMs, BTimeMs, WIncMs, BIncMs));
end;

function TUCIEngine.WaitForBestMove(TimeoutMs: Integer;
  out Best, Ponder: string): Boolean;
var
  L: TUCILine;
  StartT: TDateTime;
  Parts: TStringArray;
  i: Integer;
begin
  Result := False;
  Best := ''; Ponder := '';
  StartT := Now;
  while MilliSecondsBetween(Now, StartT) < TimeoutMs do
  begin
    if FQueue.PopItem(L) = wrSignaled then
    begin
      // log e callback info
      if Assigned(FOnLog) then FOnLog(Self, '<<', L.Text);

      if (L.Kind = lkRaw) and (Copy(L.Text, 1, 5) = 'info ') then
      begin
        if Assigned(FOnInfo) and (L.Info.PV <> nil) then
          FOnInfo(Self, L.Info);
        if L.Info.PV <> nil then L.Info.PV.Free;
      end;

      if L.Kind = lkBestMove then
      begin
        Parts := L.Text.Split([' ']);
        for i := 0 to High(Parts) - 1 do
        begin
          if Parts[i] = 'bestmove' then Best := Parts[i+1];
          if Parts[i] = 'ponder'   then Ponder := Parts[i+1];
        end;
        Result := Best <> '';
        Exit;
      end;

      if L.Kind = lkReadyOk then FReadyEvent.SetEvent;
      if L.Kind = lkUciOk then FUciOkEvent.SetEvent;
      if Assigned(FOnRawLine) and (L.Kind = lkRaw) then
        FOnRawLine(Self, L.Text);
    end
    else
      Sleep(5);
  end;
end;

function TUCIEngine.GoSync(Depth, MoveTimeMs, WTimeMs, BTimeMs,
  WIncMs, BIncMs, TimeoutMs: Integer): string;
var
  Best, Ponder: string;
begin
  Result := '';
  if not IsRunning then Exit;
  SendAndLog(BuildGoCommand(Depth, MoveTimeMs, WTimeMs, BTimeMs, WIncMs, BIncMs));
  if WaitForBestMove(TimeoutMs, Best, Ponder) then
  begin
    Result := Best;
    if Assigned(FOnBestMove) then
      FOnBestMove(Self, Best, Ponder);
  end;
end;

procedure TUCIEngine.StopThinking;
begin
  SendAndLog('stop');
end;

procedure TUCIEngine.PonderHit;
begin
  SendAndLog('ponderhit');
end;

procedure TUCIEngine.Quit;
begin
  SendAndLog('quit');
end;

end.