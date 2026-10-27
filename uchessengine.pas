unit uchessengine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, DateUtils;

type
  TCol   = 0..7;
  TRow   = 0..7;
  TSquare = record Col: TCol; Row: TRow; end;

  TPieceColor = (pcWhite, pcBlack, pcNone);
  TPieceType  = (ptPawn, ptKnight, ptBishop, ptRook, ptQueen, ptKing, ptNone);

  TPiece = record
    Color: TPieceColor;
    Kind : TPieceType;
  end;

  TMove = record
    FromCol, FromRow: ShortInt;
    ToCol,   ToRow  : ShortInt;
    Promotion: TPieceType;   // ptNone se non è promozione
    CapturedPiece: TPiece;   // per undo (e per MVV-LVA)
    IsEnPassant  : Boolean;
    IsCastle     : Boolean;
  end;

  TUndoInfo = record
    Move: TMove;
    CastlingRights: Byte;   // bitmask
    EnPassantCol, EnPassantRow: ShortInt;
    EnPassantValid: Boolean;
    FiftyMove: Integer;
    WhiteToMove: Boolean;
  end;

  TMoveArray = array of TMove;

  TChessEngine = class
  private
    FSquares : array[TCol, TRow] of TPiece;
    FWhiteToMove: Boolean;
    FCastling   : Byte;   // bit0=WK, bit1=WQ, bit2=BK, bit3=BQ
    FEnPassantCol, FEnPassantRow: ShortInt;
    FEnPassantValid: Boolean;
    FFiftyMove : Integer;
    FFullMove  : Integer;
    FHistory   : array of TUndoInfo;
    FNodesSearched: Int64;
    FStartTime : TDateTime;
    FTimeLimitMs: Integer;
    FStopSearch: Boolean;
    FKillerMoves: array[0..63, 0..1] of TMove;
    FHasKiller  : array[0..63, 0..1] of Boolean;
    FHistoryTable: array[TCol, TRow, TCol, TRow] of Integer;

    function  GetPiece(c, r: Integer): TPiece; inline;
    procedure SetPiece(c, r: Integer; const P: TPiece); inline;
    function  PieceAt(c, r: Integer): TPiece; inline;
    procedure AddMove(var List: TMoveArray; var n: Integer;
                      fc, fr, tc, tr: Integer; Promo: TPieceType = ptNone);
    procedure GenerateMoves(var List: TMoveArray; CapturesOnly: Boolean);
    procedure GeneratePseudoLegal(var List: TMoveArray; CapturesOnly: Boolean);
    function  IsSquareAttacked(c, r: Integer; byColor: TPieceColor): Boolean;
    function  KingSquare(color: TPieceColor; out c, r: Integer): Boolean;
    function  InCheck(color: TPieceColor): Boolean;
    procedure MakeMoveInternal(const M: TMove);
    procedure UndoMoveInternal;
    function  IsLegalMove(const M: TMove): Boolean;
    procedure FilterLegal(const Pseudo: TMoveArray; var Legal: TMoveArray);

    // valutazione
    function  Evaluate: Integer;
    function  PieceValue(pt: TPieceType): Integer; inline;

    // ricerca
    function  Quiescence(alpha, beta: Integer; color: TPieceColor): Integer;
    function  AlphaBeta(depth, alpha, beta: Integer; color: TPieceColor;
                        ply: Integer): Integer;
    procedure OrderMoves(var List: TMoveArray; ply: Integer;
                         const BestFromTT: TMove; HasTT: Boolean);
    function  ScoreMove(const M: TMove; ply: Integer): Integer;
    procedure CheckTime;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure SetupInitial;
    procedure LoadFEN(const FEN: string);
    function  GetFEN: string;
    procedure Clear;

    // API di ricerca
    function  Search(Depth: Integer; TimeLimitMs: Integer = 0): TMove;
    function  NodesSearched: Int64;

    // API di gioco
    function  ApplyMove(const M: TMove): Boolean;
    procedure UndoLastMove;
    procedure PlayFromTo(fc, fr, tc, tr: Integer;
                         Promotion: TPieceType = ptNone): Boolean;
    function  LegalMovesFrom(fc, fr: Integer): TMoveArray;
    function  AllLegalMoves: TMoveArray;
    function  GameOver: Boolean;

    property  WhiteToMove: Boolean read FWhiteToMove;
    property  Pieces[c: Integer; r: Integer]: TPiece read GetPiece write SetPiece;
  end;

implementation

const
  INF          = 30000;
  MATE_SCORE   = 29000;
  MAX_PLY      = 64;

  // Valori materiali (in centipedoni)
  PIECE_VALUE: array[TPieceType] of Integer =
    (100, 320, 330, 500, 900, 20000, 0);

  // Tabelle posizionali per pedine e cavalli (dal punto di vista del bianco)
  // riga 0 = traversa 8, riga 7 = traversa 1
  PAWN_TABLE: array[0..63] of Integer = (
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0);

  KNIGHT_TABLE: array[0..63] of Integer = (
   -50,-40,-30,-30,-30,-30,-40,-50,
   -40,-20,  0,  0,  0,  0,-20,-40,
   -30,  0, 10, 15, 15, 10,  0,-30,
   -30,  5, 15, 20, 20, 15,  5,-30,
   -30,  0, 15, 20, 20, 15,  0,-30,
   -30,  5, 10, 15, 15, 10,  5,-30,
   -40,-20,  0,  5,  5,  0,-20,-40,
   -50,-40,-30,-30,-30,-30,-40,-50);

  BISHOP_TABLE: array[0..63] of Integer = (
   -20,-10,-10,-10,-10,-10,-10,-20,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -10,  0,  5, 10, 10,  5,  0,-10,
   -10,  5,  5, 10, 10,  5,  5,-10,
   -10,  0, 10, 10, 10, 10,  0,-10,
   -10, 10, 10, 10, 10, 10, 10,-10,
   -10,  5,  0,  0,  0,  0,  5,-10,
   -20,-10,-10,-10,-10,-10,-10,-20);

  ROOK_TABLE: array[0..63] of Integer = (
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0);

  KING_MID_TABLE: array[0..63] of Integer = (
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -20,-30,-30,-40,-40,-30,-30,-20,
   -10,-20,-20,-20,-20,-20,-20,-10,
    20, 20,  0,  0,  0,  0, 20, 20,
    20, 30, 10,  0,  0, 10, 30, 20);

function TableIndex(c, r: Integer; color: TPieceColor): Integer; inline;
begin
  if color = pcWhite then Result := r * 8 + c
  else Result := (7 - r) * 8 + c;
end;

{ -------------------- costruzione -------------------- }

constructor TChessEngine.Create;
begin
  inherited;
  SetupInitial;
end;

destructor TChessEngine.Destroy;
begin
  inherited;
end;

procedure TChessEngine.Clear;
var c, r: Integer;
begin
  for c := 0 to 7 do
    for r := 0 to 7 do
      FSquares[c, r] := Default(TPiece);
  FWhiteToMove := True;
  FCastling := 0;
  FEnPassantValid := False;
  FFiftyMove := 0;
  FFullMove := 1;
  FHistory := nil;
end;

procedure TChessEngine.SetupInitial;
begin
  LoadFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
end;

procedure TChessEngine.LoadFEN(const FEN: string);
var parts, rows: TStringArray;
    i, j, c, r, num: Integer;
    ch: Char; p: TPiece;
begin
  Clear;
  parts := FEN.Split([' ']);
  if Length(parts) < 1 then Exit;
  rows := parts[0].Split(['/']);
  if Length(rows) <> 8 then Exit;
  for i := 0 to 7 do
  begin
    r := i; c := 0;
    for ch in rows[i] do
    begin
      if (ch >= '1') and (ch <= '8') then
        Inc(c, Ord(ch) - Ord('0'))
      else
      begin
        p := Default(TPiece);
        case ch of
          'P': begin p.Color := pcWhite; p.Kind := ptPawn;   end;
          'N': begin p.Color := pcWhite; p.Kind := ptKnight; end;
          'B': begin p.Color := pcWhite; p.Kind := ptBishop; end;
          'R': begin p.Color := pcWhite; p.Kind := ptRook;   end;
          'Q': begin p.Color := pcWhite; p.Kind := ptQueen;  end;
          'K': begin p.Color := pcWhite; p.Kind := ptKing;   end;
          'p': begin p.Color := pcBlack; p.Kind := ptPawn;   end;
          'n': begin p.Color := pcBlack; p.Kind := ptKnight; end;
          'b': begin p.Color := pcBlack; p.Kind := ptBishop; end;
          'r': begin p.Color := pcBlack; p.Kind := ptRook;   end;
          'q': begin p.Color := pcBlack; p.Kind := ptQueen;  end;
          'k': begin p.Color := pcBlack; p.Kind := ptKing;   end;
        end;
        if (c <= 7) then begin FSquares[c, r] := p; Inc(c); end;
      end;
    end;
  end;

  if Length(parts) >= 2 then FWhiteToMove := parts[1] = 'w';

  FCastling := 0;
  if (Length(parts) >= 3) and (parts[2] <> '-') then
  begin
    if Pos('K', parts[2]) > 0 then FCastling := FCastling or 1;
    if Pos('Q', parts[2]) > 0 then FCastling := FCastling or 2;
    if Pos('k', parts[2]) > 0 then FCastling := FCastling or 4;
    if Pos('q', parts[2]) > 0 then FCastling := FCastling or 8;
  end;

  FEnPassantValid := False;
  if (Length(parts) >= 4) and (parts[3] <> '-') and (Length(parts[3]) = 2) then
  begin
    FEnPassantCol := Ord(parts[3][1]) - Ord('a');
    FEnPassantRow := 8 - (Ord(parts[3][2]) - Ord('0'));
    if (FEnPassantCol in [0..7]) and (FEnPassantRow in [0..7]) then
      FEnPassantValid := True;
  end;

  if Length(parts) >= 5 then FFiftyMove := StrToIntDef(parts[4], 0);
  if Length(parts) >= 6 then FFullMove  := StrToIntDef(parts[5], 1);
  FHistory := nil;
end;

function TChessEngine.GetFEN: string;
var c, r, empty: Integer; sb: TStringBuilder; p: TPiece;
  function PChar(pp: TPiece): Char;
  begin
    case pp.Kind of
      ptPawn:   if pp.Color = pcWhite then Result := 'P' else Result := 'p';
      ptKnight: if pp.Color = pcWhite then Result := 'N' else Result := 'n';
      ptBishop: if pp.Color = pcWhite then Result := 'B' else Result := 'b';
      ptRook:   if pp.Color = pcWhite then Result := 'R' else Result := 'r';
      ptQueen:  if pp.Color = pcWhite then Result := 'Q' else Result := 'q';
      ptKing:   if pp.Color = pcWhite then Result := 'K' else Result := 'k';
    else Result := '?';
    end;
  end;
begin
  sb := TStringBuilder.Create;
  try
    for r := 0 to 7 do
    begin
      empty := 0;
      for c := 0 to 7 do
      begin
        p := FSquares[c, r];
        if p.Kind = ptNone then Inc(empty)
        else
        begin
          if empty > 0 then begin sb.Append(IntToStr(empty)); empty := 0; end;
          sb.Append(PChar(p));
        end;
      end;
      if empty > 0 then sb.Append(IntToStr(empty));
      if r < 7 then sb.Append('/');
    end;
    sb.Append(' ');
    if FWhiteToMove then sb.Append('w') else sb.Append('b');
    sb.Append(' ');
    if FCastling = 0 then sb.Append('-')
    else
    begin
      if (FCastling and 1) <> 0 then sb.Append('K');
      if (FCastling and 2) <> 0 then sb.Append('Q');
      if (FCastling and 4) <> 0 then sb.Append('k');
      if (FCastling and 8) <> 0 then sb.Append('q');
    end;
    sb.Append(' ');
    if FEnPassantValid then
      sb.Append(Chr(Ord('a') + FEnPassantCol) + Chr(Ord('0') + (8 - FEnPassantRow)))
    else
      sb.Append('-');
    sb.Append(' ').Append(IntToStr(FFiftyMove));
    sb.Append(' ').Append(IntToStr(FFullMove));
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ -------------------- accesso base -------------------- }

function TChessEngine.GetPiece(c, r: Integer): TPiece;
begin
  if (c in [0..7]) and (r in [0..7]) then Result := FSquares[c, r]
  else Result := Default(TPiece);
end;

procedure TChessEngine.SetPiece(c, r: Integer; const P: TPiece);
begin
  if (c in [0..7]) and (r in [0..7]) then FSquares[c, r] := P;
end;

function TChessEngine.PieceAt(c, r: Integer): TPiece; inline;
begin
  Result := FSquares[c, r];
end;

procedure TChessEngine.AddMove(var List: TMoveArray; var n: Integer;
  fc, fr, tc, tr: Integer; Promo: TPieceType);
begin
  if n >= Length(List) then SetLength(List, Max(64, Length(List) * 2));
  List[n].FromCol := fc; List[n].FromRow := fr;
  List[n].ToCol   := tc; List[n].ToRow   := tr;
  List[n].Promotion := Promo;
  List[n].CapturedPiece := FSquares[tc, tr];
  List[n].IsEnPassant := False;
  List[n].IsCastle := False;
  Inc(n);
end;

{ -------------------- generazione mosse -------------------- }

procedure TChessEngine.GeneratePseudoLegal(var List: TMoveArray; CapturesOnly: Boolean);
var
  c, r, dc, dr, tc, tr: Integer;
  p: TPiece;
  n: Integer;

  procedure AddPawnMoves;
  var dir, startRow, promoRow: Integer;
  begin
    if p.Color = pcWhite then begin dir := -1; startRow := 6; promoRow := 0; end
    else begin dir := 1; startRow := 1; promoRow := 7; end;

    // spinta avanti
    tr := r + dir;
    if (tr >= 0) and (tr <= 7) and (FSquares[c, tr].Kind = ptNone) then
    begin
      if not CapturesOnly then
      begin
        if tr = promoRow then
        begin
          AddMove(List, n, c, r, c, tr, ptQueen);
          AddMove(List, n, c, r, c, tr, ptRook);
          AddMove(List, n, c, r, c, tr, ptBishop);
          AddMove(List, n, c, r, c, tr, ptKnight);
        end
        else
          AddMove(List, n, c, r, c, tr);
      end;
      // doppia spinta
      if (not CapturesOnly) and (r = startRow) then
      begin
        tr := r + 2 * dir;
        if (tr >= 0) and (tr <= 7) and (FSquares[c, tr].Kind = ptNone) then
          AddMove(List, n, c, r, c, tr);
      end;
    end;
    // catture
    for dc := -1 to 1 do
      if dc <> 0 then
      begin
        tc := c + dc; tr := r + dir;
        if (tc in [0..7]) and (tr in [0..7]) then
        begin
          if (FSquares[tc, tr].Kind <> ptNone) and
             (FSquares[tc, tr].Color <> p.Color) then
          begin
            if tr = promoRow then
            begin
              AddMove(List, n, c, r, tc, tr, ptQueen);
              AddMove(List, n, c, r, tc, tr, ptRook);
              AddMove(List, n, c, r, tc, tr, ptBishop);
              AddMove(List, n, c, r, tc, tr, ptKnight);
            end
            else
              AddMove(List, n, c, r, tc, tr);
          end
          else if FEnPassantValid and (tc = FEnPassantCol) and (tr = FEnPassantRow) then
          begin
            AddMove(List, n, c, r, tc, tr);
            List[n-1].IsEnPassant := True;
            if p.Color = pcWhite then
              List[n-1].CapturedPiece.Color := pcBlack
            else
              List[n-1].CapturedPiece.Color := pcWhite;
            List[n-1].CapturedPiece.Kind := ptPawn;
          end;
        end;
      end;
  end;

  procedure AddSliding(dirs: array of const);
  var k: Integer; ddc, ddr: Integer;
  begin
    for k := 0 to High(dirs) do
    begin
      ddc := dirs[k].VInteger div 100;
      ddr := dirs[k].VInteger mod 100 - 10;   // trucco: codifica dc+10
      ddc := dirs[k].VInteger div 10 - 1;
      ddr := dirs[k].VInteger mod 10 - 1;
      tc := c + ddc; tr := r + ddr;
      while (tc in [0..7]) and (tr in [0..7]) do
      begin
        if FSquares[tc, tr].Kind = ptNone then
        begin
          if not CapturesOnly then AddMove(List, n, c, r, tc, tr);
        end
        else
        begin
          if FSquares[tc, tr].Color <> p.Color then
            AddMove(List, n, c, r, tc, tr);
          Break;
        end;
        Inc(tc, ddc); Inc(tr, ddr);
      end;
    end;
  end;

begin
  if Length(List) < 128 then SetLength(List, 128);
  n := 0;
  for c := 0 to 7 do
    for r := 0 to 7 do
    begin
      p := FSquares[c, r];
      if p.Kind = ptNone then Continue;
      if (p.Color = pcWhite) <> FWhiteToMove then Continue;

      case p.Kind of
        ptPawn: AddPawnMoves;
        ptKnight:
          begin
            for dc := -2 to 2 do
              for dr := -2 to 2 do
              begin
                if (Abs(dc) = 0) or (Abs(dr) = 0) then Continue;
                if Abs(dc) + Abs(dr) <> 3 then Continue;
                tc := c + dc; tr := r + dr;
                if not (tc in [0..7]) or not (tr in [0..7]) then Continue;
                if FSquares[tc, tr].Kind = ptNone then
                begin
                  if not CapturesOnly then AddMove(List, n, c, r, tc, tr);
                end
                else if FSquares[tc, tr].Color <> p.Color then
                  AddMove(List, n, c, r, tc, tr);
              end;
          end;
        ptBishop: AddSliding([-9, -11, 9, 11]);
        ptRook:   AddSliding([-10, -1, 1, 10]);
        ptQueen:  AddSliding([-10, -1, 1, 10, -9, -11, 9, 11]);
        ptKing:
          begin
            for dc := -1 to 1 do
              for dr := -1 to 1 do
              begin
                if (dc = 0) and (dr = 0) then Continue;
                tc := c + dc; tr := r + dr;
                if not (tc in [0..7]) or not (tr in [0..7]) then Continue;
                if FSquares[tc, tr].Kind = ptNone then
                begin
                  if not CapturesOnly then AddMove(List, n, c, r, tc, tr);
                end
                else if FSquares[tc, tr].Color <> p.Color then
                  AddMove(List, n, c, r, tc, tr);
              end;
            // arrocco (semplificato: verifica diritti + caselle libere)
            if not CapturesOnly then
            begin
              if p.Color = pcWhite then
              begin
                if ((FCastling and 1) <> 0)
                   and (FSquares[5,7].Kind = ptNone)
                   and (FSquares[6,7].Kind = ptNone) then
                begin
                  AddMove(List, n, 4, 7, 6, 7);
                  List[n-1].IsCastle := True;
                end;
                if ((FCastling and 2) <> 0)
                   and (FSquares[1,7].Kind = ptNone)
                   and (FSquares[2,7].Kind = ptNone)
                   and (FSquares[3,7].Kind = ptNone) then
                begin
                  AddMove(List, n, 4, 7, 2, 7);
                  List[n-1].IsCastle := True;
                end;
              end
              else
              begin
                if ((FCastling and 4) <> 0)
                   and (FSquares[5,0].Kind = ptNone)
                   and (FSquares[6,0].Kind = ptNone) then
                begin
                  AddMove(List, n, 4, 0, 6, 0);
                  List[n-1].IsCastle := True;
                end;
                if ((FCastling and 8) <> 0)
                   and (FSquares[1,0].Kind = ptNone)
                   and (FSquares[2,0].Kind = ptNone)
                   and (FSquares[3,0].Kind = ptNone) then
                begin
                  AddMove(List, n, 4, 0, 2, 0);
                  List[n-1].IsCastle := True;
                end;
              end;
            end;
          end;
      end;
    end;
  SetLength(List, n);
end;

procedure TChessEngine.GenerateMoves(var List: TMoveArray; CapturesOnly: Boolean);
var pseudo, legal: TMoveArray;
begin
  GeneratePseudoLegal(pseudo, CapturesOnly);
  FilterLegal(pseudo, legal);
  List := legal;
end;

{ -------------------- attacco / scacco -------------------- }

function TChessEngine.IsSquareAttacked(c, r: Integer; byColor: TPieceColor): Boolean;
var
  dc, dr, tc, tr: Integer;
  p: TPiece;

  function SlideHit(dirs: array of const): Boolean;
  var k, ddc, ddr: Integer;
  begin
    Result := False;
    for k := 0 to High(dirs) do
    begin
      ddc := dirs[k].VInteger div 10 - 1;
      ddr := dirs[k].VInteger mod 10 - 1;
      tc := c + ddc; tr := r + ddr;
      while (tc in [0..7]) and (tr in [0..7]) do
      begin
        if FSquares[tc, tr].Kind <> ptNone then
        begin
          p := FSquares[tc, tr];
          if p.Color = byColor then Exit(True);
          Break;
        end;
        Inc(tc, ddc); Inc(tr, ddr);
      end;
    end;
  end;

begin
  Result := False;
  // pedoni
  if byColor = pcWhite then
  begin
    if (c-1 in [0..7]) and (r+1 in [0..7]) then
      if (FSquares[c-1, r+1].Kind = ptPawn) and (FSquares[c-1, r+1].Color = pcWhite) then Exit(True);
    if (c+1 in [0..7]) and (r+1 in [0..7]) then
      if (FSquares[c+1, r+1].Kind = ptPawn) and (FSquares[c+1, r+1].Color = pcWhite) then Exit(True);
  end
  else
  begin
    if (c-1 in [0..7]) and (r-1 in [0..7]) then
      if (FSquares[c-1, r-1].Kind = ptPawn) and (FSquares[c-1, r-1].Color = pcBlack) then Exit(True);
    if (c+1 in [0..7]) and (r-1 in [0..7]) then
      if (FSquares[c+1, r-1].Kind = ptPawn) and (FSquares[c+1, r-1].Color = pcBlack) then Exit(True);
  end;

  // cavalli
  for dc := -2 to 2 do
    for dr := -2 to 2 do
    begin
      if Abs(dc) + Abs(dr) <> 3 then Continue;
      tc := c + dc; tr := r + dr;
      if not (tc in [0..7]) or not (tr in [0..7]) then Continue;
      if (FSquares[tc, tr].Kind = ptKnight) and (FSquares[tc, tr].Color = byColor) then Exit(True);
    end;

  // re
  for dc := -1 to 1 do
    for dr := -1 to 1 do
    begin
      if (dc = 0) and (dr = 0) then Continue;
      tc := c + dc; tr := r + dr;
      if not (tc in [0..7]) or not (tr in [0..7]) then Continue;
      if (FSquares[tc, tr].Kind = ptKing) and (FSquares[tc, tr].Color = byColor) then Exit(True);
    end;

  // diagonali (alfiere/regina)
  if SlideHit([-9, -11, 9, 11]) then Exit(True);
  // ortogonali (torre/regina)
  if SlideHit([-10, -1, 1, 10]) then Exit(True);
end;

function TChessEngine.KingSquare(color: TPieceColor; out c, r: Integer): Boolean;
begin
  for c := 0 to 7 do
    for r := 0 to 7 do
      if (FSquares[c, r].Kind = ptKing) and (FSquares[c, r].Color = color) then
        Exit(True);
  Result := False;
end;

function TChessEngine.InCheck(color: TPieceColor): Boolean;
var c, r: Integer;
begin
  if not KingSquare(color, c, r) then Exit(False);
  if color = pcWhite then
    Result := IsSquareAttacked(c, r, pcBlack)
  else
    Result := IsSquareAttacked(c, r, pcWhite);
end;

{ -------------------- make / undo -------------------- }

procedure TChessEngine.MakeMoveInternal(const M: TMove);
var
  undo: TUndoInfo;
  p: TPiece;
begin
  SetLength(FHistory, Length(FHistory) + 1);
  undo.Move := M;
  undo.CastlingRights := FCastling;
  undo.EnPassantCol := FEnPassantCol;
  undo.EnPassantRow := FEnPassantRow;
  undo.EnPassantValid := FEnPassantValid;
  undo.FiftyMove := FFiftyMove;
  undo.WhiteToMove := FWhiteToMove;
  FHistory[High(FHistory)] := undo;

  p := FSquares[M.FromCol, M.FromRow];

  // en passant: rimuovi pedone catturato
  if M.IsEnPassant then
  begin
    if p.Color = pcWhite then
      FSquares[M.ToCol, M.ToRow + 1] := Default(TPiece)
    else
      FSquares[M.ToCol, M.ToRow - 1] := Default(TPiece);
  end;

  // arrocco: sposta la torre
  if M.IsCastle then
  begin
    if M.ToCol = 6 then
    begin
      FSquares[5, M.ToRow] := FSquares[7, M.ToRow];
      FSquares[7, M.ToRow] := Default(TPiece);
    end
    else if M.ToCol = 2 then
    begin
      FSquares[3, M.ToRow] := FSquares[0, M.ToRow];
      FSquares[0, M.ToRow] := Default(TPiece);
    end;
  end;

  // applica movimento
  FSquares[M.ToCol, M.ToRow] := p;
  FSquares[M.FromCol, M.FromRow] := Default(TPiece);

  // promozione
  if M.Promotion <> ptNone then
    FSquares[M.ToCol, M.ToRow].Kind := M.Promotion;

  // aggiorna diritti di arrocco
  if p.Kind = ptKing then
  begin
    if p.Color = pcWhite then FCastling := FCastling and not (1 or 2)
    else FCastling := FCastling and not (4 or 8);
  end;
  if (p.Kind = ptRook) then
  begin
    if (M.FromCol = 0) and (M.FromRow = 7) then FCastling := FCastling and not 2;
    if (M.FromCol = 7) and (M.FromRow = 7) then FCastling := FCastling and not 1;
    if (M.FromCol = 0) and (M.FromRow = 0) then FCastling := FCastling and not 8;
    if (M.FromCol = 7) and (M.FromRow = 0) then FCastling := FCastling and not 4;
  end;
  // se una torre viene catturata sulla sua casella iniziale
  if (M.ToCol = 0) and (M.ToRow = 7) then FCastling := FCastling and not 2;
  if (M.ToCol = 7) and (M.ToRow = 7) then FCastling := FCastling and not 1;
  if (M