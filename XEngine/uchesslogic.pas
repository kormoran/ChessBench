unit uchesslogic;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Graphics, Math, StrUtils;
 
type
  TCol = 0..7;
  TRow = 0..7;
  TSquare = record
    Col: TCol;
    Row: TRow;   // 0 = riga 8 (lato nero), 7 = riga 1 (lato bianco)
  end;

  TPieceColor = (pcNone, pcWhite, pcBlack);
  TPieceType  = (ptNone, ptPawn, ptKnight, ptBishop, ptRook, ptQueen, ptKing);
  TPiece = record
    Color: TPieceColor;
    Kind : TPieceType;
  end;

  TChessMove = record
    FromCol, FromRow: Integer;
    ToCol,   ToRow  : Integer;
    MovedPiece      : TPiece;   // pezzo che si muove
    CapturedPiece   : TPiece;   // pezzo catturato (se c'è)
    IsCastle        : Boolean;
    IsEnPassant     : Boolean;
    Promotion       : TPieceType;
  end;

  TMoveList = array of TChessMove;

  TChessBoard = class
  private
    FSquares: array[TCol, TRow] of TPiece;
    FMoveHistory: TMoveList;
    FCurrentIndex: Integer;  // indice nella cronologia (per rewind/forward)
    FEnPassantTarget: TSquare;
    FEnPassantValid : Boolean;
    FWhiteToMove    : Boolean;
    FCastlingRights: set of (crWK, crWQ, crBK, crBQ);
    function  GetPiece(c, r: Integer): TPiece;
    procedure SetPiece(c, r: Integer; const P: TPiece);
  public
    constructor Create;
    procedure SetupInitial;
    procedure ClearBoard;
    procedure LoadFEN(const FEN: string);
    function  GetFEN: string;
	function PathClear(const FromSq, ToSq: TSquare): Boolean;

    function  IsValidMove(const FromSq, ToSq: TSquare): Boolean;
    function  GetLegalDestinations(const FromSq: TSquare): array of TSquare;
    function  ApplyMove(const FromSq, ToSq: TSquare): Boolean;   // esegue e registra
    procedure UndoLastMove;
    procedure ClearMoveList;
    procedure RewindOne;    // vai indietro di una mossa nella visualizzazione
    procedure ForwardOne;   // vai avanti di una mossa
    function  GetMoveCount: Integer;
    function  GetMove(Index: Integer): TChessMove;
    function  GetCurrentMoveIndex: Integer;
    property Pieces[c: Integer; r: Integer]: TPiece read GetPiece write SetPiece;
    property WhiteToMove: Boolean read FWhiteToMove;
  end;

implementation

{ helper: coordinate }
function Sq(c, r: Integer): TSquare; inline;
begin Result.Col := c; Result.Row := r; end;

function SamePiece(const A, B: TPiece): Boolean; inline;
begin Result := (A.Color = B.Color) and (A.Kind = B.Kind); end;

constructor TChessBoard.Create;
begin
  inherited;
  SetupInitial;
end;

procedure TChessBoard.ClearBoard;
var c, r: Integer;
begin
  for c := 0 to 7 do
    for r := 0 to 7 do
      FSquares[c, r] := Default(TPiece);
  FEnPassantValid := False;
  FCastlingRights := [];
end;

procedure TChessBoard.SetPiece(c, r: Integer; const P: TPiece);
begin
  if (c in [0..7]) and (r in [0..7]) then FSquares[c, r] := P;
end;

function TChessBoard.GetPiece(c, r: Integer): TPiece;
begin
  if (c in [0..7]) and (r in [0..7]) then Result := FSquares[c, r]
  else Result := Default(TPiece);
end;

procedure TChessBoard.SetupInitial;
begin
  LoadFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
  FMoveHistory := nil;
  FCurrentIndex := -1;
end;

procedure TChessBoard.LoadFEN(const FEN: string);
var
  parts: TStringArray;
  rows: TStringArray;
  i, j, r, c, num: Integer;
  ch: Char;
  pc: TPiece;
begin
  ClearBoard;
  parts := FEN.Split([' ']);
  if Length(parts) < 1 then Exit;
  rows := parts[0].Split(['/']);
  if Length(rows) <> 8 then Exit;

  for i := 0 to 7 do
  begin
    r := i;   // riga 0 = 8a traversa
    c := 0;
    for ch in rows[i] do
    begin
      if (ch >= '1') and (ch <= '8') then
      begin
        num := Ord(ch) - Ord('0');
        Inc(c, num);
      end
      else
      begin
        pc := Default(TPiece);
        case ch of
          'P': begin pc.Color := pcWhite; pc.Kind := ptPawn; end;
          'N': begin pc.Color := pcWhite; pc.Kind := ptKnight; end;
          'B': begin pc.Color := pcWhite; pc.Kind := ptBishop; end;
          'R': begin pc.Color := pcWhite; pc.Kind := ptRook; end;
          'Q': begin pc.Color := pcWhite; pc.Kind := ptQueen; end;
          'K': begin pc.Color := pcWhite; pc.Kind := ptKing; end;
          'p': begin pc.Color := pcBlack; pc.Kind := ptPawn; end;
          'n': begin pc.Color := pcBlack; pc.Kind := ptKnight; end;
          'b': begin pc.Color := pcBlack; pc.Kind := ptBishop; end;
          'r': begin pc.Color := pcBlack; pc.Kind := ptRook; end;
          'q': begin pc.Color := pcBlack; pc.Kind := ptQueen; end;
          'k': begin pc.Color := pcBlack; pc.Kind := ptKing; end;
        end;
        if c <= 7 then
        begin
          FSquares[c, r] := pc;
          Inc(c);
        end;
      end;
    end;
  end;

  if Length(parts) >= 2 then
    FWhiteToMove := parts[1] = 'w'
  else
    FWhiteToMove := True;

  FEnPassantValid := False;
  FCastlingRights := [];
  if (Length(parts) >= 3) and (parts[2] <> '-') then
  begin
    if Pos('K', parts[2]) > 0 then Include(FCastlingRights, crWK);
    if Pos('Q', parts[2]) > 0 then Include(FCastlingRights, crWQ);
    if Pos('k', parts[2]) > 0 then Include(FCastlingRights, crBK);
    if Pos('q', parts[2]) > 0 then Include(FCastlingRights, crBQ);
  end;
end;

function TChessBoard.GetFEN: string;
var
  c, r, emptyCount: Integer;
  sb: TStringBuilder;
  p: TPiece;
  function PieceChar(const PP: TPiece): Char;
  begin
    case PP.Kind of
      ptPawn:   if PP.Color = pcWhite then Result := 'P' else Result := 'p';
      ptKnight: if PP.Color = pcWhite then Result := 'N' else Result := 'n';
      ptBishop: if PP.Color = pcWhite then Result := 'B' else Result := 'b';
      ptRook:   if PP.Color = pcWhite then Result := 'R' else Result := 'r';
      ptQueen:  if PP.Color = pcWhite then Result := 'Q' else Result := 'q';
      ptKing:   if PP.Color = pcWhite then Result := 'K' else Result := 'k';
    else Result := '?';
    end;
  end;
begin
  sb := TStringBuilder.Create;
  try
    for r := 0 to 7 do
    begin
      emptyCount := 0;
      for c := 0 to 7 do
      begin
        p := FSquares[c, r];
        if p.Kind = ptNone then Inc(emptyCount)
        else
        begin
          if emptyCount > 0 then begin sb.Append(IntToStr(emptyCount)); emptyCount := 0; end;
          sb.Append(PieceChar(p));
        end;
      end;
      if emptyCount > 0 then sb.Append(IntToStr(emptyCount));
      if r < 7 then sb.Append('/');
    end;
    sb.Append(' ');
    if FWhiteToMove then sb.Append('w') else sb.Append('b');
    sb.Append(' ');
    if FCastlingRights = [] then sb.Append('-')
    else
    begin
      if crWK in FCastlingRights then sb.Append('K');
      if crWQ in FCastlingRights then sb.Append('Q');
      if crBK in FCastlingRights then sb.Append('k');
      if crBQ in FCastlingRights then sb.Append('q');
    end;
    sb.Append(' - 0 1');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ --- Regole: qui metti la logica completa. Esempio semplificato. --- }

function TChessBoard.IsValidMove(const FromSq, ToSq: TSquare): Boolean;
var
  P, Target: TPiece;
  dc, dr: Integer;
begin
  Result := False;
  P := FSquares[FromSq.Col, FromSq.Row];
  if P.Kind = ptNone then Exit;
  if (P.Color = pcWhite) <> FWhiteToMove then Exit;

  Target := FSquares[ToSq.Col, ToSq.Row];
  if Target.Kind <> ptNone then
    if Target.Color = P.Color then Exit;

  dc := ToSq.Col - FromSq.Col;
  dr := ToSq.Row - FromSq.Row;

  case P.Kind of
    ptPawn:
      begin
        if P.Color = pcWhite then
        begin
          // avanti di 1
          if (dc = 0) and (dr = -1) and (Target.Kind = ptNone) then Exit(True);
          // avanti di 2 dalla riga 6 (indice)
          if (dc = 0) and (dr = -2) and (FromSq.Row = 6)
             and (Target.Kind = ptNone)
             and (FSquares[FromSq.Col, FromSq.Row-1].Kind = ptNone) then Exit(True);
          // cattura diagonale
          if (Abs(dc) = 1) and (dr = -1) and (Target.Kind <> ptNone)
             and (Target.Color = pcBlack) then Exit(True);
        end
        else
        begin
          if (dc = 0) and (dr = 1) and (Target.Kind = ptNone) then Exit(True);
          if (dc = 0) and (dr = 2) and (FromSq.Row = 1)
             and (Target.Kind = ptNone)
             and (FSquares[FromSq.Col, FromSq.Row+1].Kind = ptNone) then Exit(True);
          if (Abs(dc) = 1) and (dr = 1) and (Target.Kind <> ptNone)
             and (Target.Color = pcWhite) then Exit(True);
        end;
      end;
    ptKnight:
      Result := (Abs(dc) in [1,2]) and (Abs(dr) in [1,2]) and (Abs(dc) <> Abs(dr));
    ptBishop:
      Result := (Abs(dc) = Abs(dr)) and (dc <> 0) and PathClear(FromSq, ToSq);
    ptRook:
      Result := ((dc = 0) xor (dr = 0)) and PathClear(FromSq, ToSq);
    ptQueen:
      Result := ((Abs(dc) = Abs(dr)) or (dc = 0) or (dr = 0))
                and ((dc <> 0) or (dr <> 0)) and PathClear(FromSq, ToSq);
    ptKing:
      Result := (Abs(dc) <= 1) and (Abs(dr) <= 1) and ((dc <> 0) or (dr <> 0));
  end;

  // NOTA: manca il controllo "il re resta sotto scacco", en passant, arrocco,
  // promozione. Da implementare per un gioco completo.
end;

// dichiarazione anticipata necessaria: aggiungi in interface
function TChessBoard.PathClear(const FromSq, ToSq: TSquare): Boolean;
var
  dc, dr, steps, i, c, r: Integer;
begin
  dc := Sign(ToSq.Col - FromSq.Col);
  dr := Sign(ToSq.Row - FromSq.Row);
  steps := Max(Abs(ToSq.Col - FromSq.Col), Abs(ToSq.Row - FromSq.Row));
  c := FromSq.Col + dc;
  r := FromSq.Row + dr;
  for i := 1 to steps - 1 do
  begin
    if FSquares[c, r].Kind <> ptNone then Exit(False);
    Inc(c, dc); Inc(r, dr);
  end;
  Result := True;
end;

function TChessBoard.GetLegalDestinations(const FromSq: TSquare): array of TSquare;
var c, r, n: Integer;
begin
  SetLength(Result, 0); n := 0;
  for c := 0 to 7 do
    for r := 0 to 7 do
      if IsValidMove(FromSq, Sq(c, r)) then
      begin
        SetLength(Result, n + 1);
        Result[n] := Sq(c, r);
        Inc(n);
      end;
end;

function TChessBoard.ApplyMove(const FromSq, ToSq: TSquare): Boolean;
var
  mv: TChessMove;
begin
  Result := False;
  if not IsValidMove(FromSq, ToSq) then Exit;

  mv.FromCol := FromSq.Col; mv.FromRow := FromSq.Row;
  mv.ToCol   := ToSq.Col;   mv.ToRow   := ToSq.Row;
  mv.MovedPiece    := FSquares[FromSq.Col, FromSq.Row];
  mv.CapturedPiece := FSquares[ToSq.Col, ToSq.Row];
  mv.IsCastle := False;
  mv.IsEnPassant := False;
  mv.Promotion := ptNone;

  // esegui sulla scacchiera
  FSquares[ToSq.Col, ToSq.Row] := mv.MovedPiece;
  FSquares[FromSq.Col, FromSq.Row] := Default(TPiece);
  FWhiteToMove := not FWhiteToMove;

  // registra
  SetLength(FMoveHistory, Length(FMoveHistory) + 1);
  FMoveHistory[High(FMoveHistory)] := mv;
  FCurrentIndex := High(FMoveHistory);
  Result := True;
end;

procedure TChessBoard.UndoLastMove;
begin
  if Length(FMoveHistory) = 0 then Exit;
  RewindOne;
  SetLength(FMoveHistory, Length(FMoveHistory) - 1);
  if FCurrentIndex >= Length(FMoveHistory) then
    FCurrentIndex := High(FMoveHistory);
end;

procedure TChessBoard.ClearMoveList;
begin
  FMoveHistory := nil;
  FCurrentIndex := -1;
end;

procedure TChessBoard.RewindOne;
var mv: TChessMove;
begin
  if FCurrentIndex < 0 then Exit;
  mv := FMoveHistory[FCurrentIndex];
  // ripristina
  FSquares[mv.FromCol, mv.FromRow] := mv.MovedPiece;
  FSquares[mv.ToCol, mv.ToRow]     := mv.CapturedPiece;
  FWhiteToMove := not FWhiteToMove;
  Dec(FCurrentIndex);
end;

procedure TChessBoard.ForwardOne;
var mv: TChessMove;
begin
  if FCurrentIndex >= High(FMoveHistory) then Exit;
  Inc(FCurrentIndex);
  mv := FMoveHistory[FCurrentIndex];
  FSquares[mv.ToCol, mv.ToRow]     := mv.MovedPiece;
  FSquares[mv.FromCol, mv.FromRow] := Default(TPiece);
  FWhiteToMove := not FWhiteToMove;
end;

function TChessBoard.GetMoveCount: Integer;
begin Result := Length(FMoveHistory); end;

function TChessBoard.GetMove(Index: Integer): TChessMove;
begin
  if (Index >= 0) and (Index < Length(FMoveHistory)) then
    Result := FMoveHistory[Index]
  else
    Result := Default(TChessMove);
end;

function TChessBoard.GetCurrentMoveIndex: Integer;
begin Result := FCurrentIndex; end;

end.