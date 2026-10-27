unit uchessboardview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, LCLIntf, Math,
  uchesslogic;

type
  TChessBoardView = class(TWinControl)
  private
    FBoard        : TChessBoard;
    FSquareSize   : Integer;    // calcolato dinamicamente
    FBoardOrigin  : TPoint;     // angolo in alto a sinistra dell'area scacchiera (dopo bordo)
    FBorderWidth  : Integer;

    // immagini pezzi (indice = [colore][tipo])
    FPieceImages  : array[TPieceColor, TPieceType] of TBitmap;
    FDarkColor    : TColor;
    FLightColor   : TColor;
    FBorderColor  : TColor;
    FHighlightColor: TColor;

    // drag & drop
    FDragging     : Boolean;
    FDragFrom     : TSquare;
    FDragPiece    : TPiece;
    FDragPos      : TPoint;     // posizione corrente del mouse
    FLegalDests   : array of TSquare;

    procedure SetBorderWidth(AValue: Integer);
    procedure RecalcGeometry;
    function  SquareAt(X, Y: Integer; out S: TSquare): Boolean;
    function  SquareToRect(const S: TSquare): TRect;
    procedure LoadDefaultPieces;
    procedure DrawBoard(ACanvas: TCanvas);
    procedure DrawPiece(ACanvas: TCanvas; const S: TSquare);
    procedure DrawHighlights(ACanvas: TCanvas);
    procedure DrawDragging(ACanvas: TCanvas);
    function  FindPieceBitmap(const P: TPiece): TBitmap;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                        X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
                      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    procedure SetBoard(ABoard: TChessBoard);   // collega il modello
    procedure RefreshBoard;                    // ridisegna

    // API di alto livello (delegate al modello + repaint)
    procedure NewGame;
    procedure LoadFEN(const FEN: string);
    function  GetFEN: string;
    procedure ClearMoves;
    procedure StepBackward;
    procedure StepForward;
    function  MoveCount: Integer;
    function  GetMove(Index: Integer): TChessMove;
    procedure PlayMove(const FromSq, ToSq: TSquare);
    procedure UndoMove;
    function  GetCurrentMoveIndex: Integer;
  published
    property BorderWidth: Integer read FBorderWidth write SetBorderWidth default 2;
    property DarkColor: TColor read FDarkColor write FDarkColor default clGray;
    property LightColor: TColor read FLightColor write FLightColor default clWhite;
    property BorderColor: TColor read FBorderColor write FBorderColor default clBlack;
    property HighlightColor: TColor read FHighlightColor write FHighlightColor
      default TColor($0080FF80);  // verde tenue
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Giochi', [TChessBoardView]);
end;

{ ---------- helper ---------- }

function TChessBoardView.SquareToRect(const S: TSquare): TRect;
begin
  Result.Left   := FBoardOrigin.X + S.Col * FSquareSize;
  Result.Top    := FBoardOrigin.Y + S.Row * FSquareSize;
  Result.Right  := Result.Left + FSquareSize;
  Result.Bottom := Result.Top  + FSquareSize;
end;

function TChessBoardView.FindPieceBitmap(const P: TPiece): TBitmap;
begin
  if (P.Kind <> ptNone) then Result := FPieceImages[P.Color, P.Kind]
  else Result := nil;
end;

{ ---------- costruzione ---------- }

constructor TChessBoardView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Width := 400; Height := 400;
  FBorderWidth := 2;
  FDarkColor  := clGray;
  FLightColor := clWhite;
  FBorderColor := clBlack;
  FHighlightColor := TColor($0080FF80);
  FBoard := TChessBoard.Create;
  LoadDefaultPieces;
  RecalcGeometry;
end;

destructor TChessBoardView.Destroy;
var c: TPieceColor; k: TPieceType;
begin
  for c := Low(TPieceColor) to High(TPieceColor) do
    for k := Low(TPieceType) to High(TPieceType) do
      FPieceImages[c, k].Free;
  FBoard.Free;
  inherited Destroy;
end;

procedure TChessBoardView.LoadDefaultPieces;
var c: TPieceColor; k: TPieceType;
begin
  // Inizializza bitmap vuoti. Sostituisci con il caricamento reale
  // (es. da PNG/Lazarus resources) usando il tuo set grafico.
  for c := Low(TPieceColor) to High(TPieceColor) do
    for k := Low(TPieceType) to High(TPieceType) do
    begin
      FPieceImages[c, k] := TBitmap.Create;
      FPieceImages[c, k].SetSize(64, 64);
      FPieceImages[c, k].Transparent := True;
    end;
  // esempio di "segnaposto": qui dovresti disegnare o caricare le immagini reali
end;

procedure TChessBoardView.SetBoard(ABoard: TChessBoard);
begin
  if ABoard = nil then Exit;
  FBoard.Free;
  FBoard := ABoard;
  RefreshBoard;
end;

procedure TChessBoardView.SetBorderWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FBorderWidth = AValue then Exit;
  FBorderWidth := AValue;
  RecalcGeometry;
  Invalidate;
end;

procedure TChessBoardView.RecalcGeometry;
var
  availW, availH, side: Integer;
begin
  availW := Width  - 2 * FBorderWidth;
  availH := Height - 2 * FBorderWidth;
  side := Min(availW, availH);
  if side < 0 then side := 0;
  FSquareSize := side div 8;
  // centratura
  FBoardOrigin.X := FBorderWidth + (availW - FSquareSize * 8) div 2;
  FBoardOrigin.Y := FBorderWidth + (availH - FSquareSize * 8) div 2;
end;

procedure TChessBoardView.Resize;
begin
  inherited Resize;
  RecalcGeometry;
  Invalidate;
end;

procedure TChessBoardView.RefreshBoard;
begin
  Invalidate;
end;

{ ---------- disegno ---------- }

procedure TChessBoardView.DrawBoard(ACanvas: TCanvas);
var c, r: Integer; R: TRect;
begin
  ACanvas.Brush.Color := FLightColor;
  ACanvas.FillRect(ClientRect);
  for c := 0 to 7 do
    for r := 0 to 7 do
    begin
      R := SquareToRect(Sq(c, r));   // helper da uchesslogic
      if (c + r) mod 2 = 1 then
        ACanvas.Brush.Color := FDarkColor
      else
        ACanvas.Brush.Color := FLightColor;
      ACanvas.FillRect(R);
    end;

  // bordo
  if FBorderWidth > 0 then
  begin
    ACanvas.Pen.Color := FBorderColor;
    ACanvas.Pen.Width := FBorderWidth;
    ACanvas.Brush.Style := bsClear;
    ACanvas.Rectangle(FBoardOrigin.X - FBorderWidth,
                      FBoardOrigin.Y - FBorderWidth,
                      FBoardOrigin.X + FSquareSize * 8 + FBorderWidth,
                      FBoardOrigin.Y + FSquareSize * 8 + FBorderWidth);
    ACanvas.Brush.Style := bsSolid;
  end;
end;

procedure TChessBoardView.DrawPiece(ACanvas: TCanvas; const S: TSquare);
var
  P: TPiece; Bmp: TBitmap; R: TRect;
begin
  P := FBoard.Pieces[S.Col, S.Row];
  if P.Kind = ptNone then Exit;
  Bmp := FindPieceBitmap(P);
  if (Bmp <> nil) and (Bmp.Width > 0) then
  begin
    R := SquareToRect(S);
    ACanvas.StretchDraw(R, Bmp);
  end;
end;

procedure TChessBoardView.DrawHighlights(ACanvas: TCanvas);
var i: Integer; R: TRect;
begin
  if not FDragging then Exit;
  ACanvas.Brush.Color := FHighlightColor;
  ACanvas.Pen.Color := FHighlightColor;
  for i := 0 to High(FLegalDests) do
  begin
    R := SquareToRect(FLegalDests[i]);
    // disegna un quadratino centrale come indicatore
    InflateRect(R, -FSquareSize div 4, -FSquareSize div 4);
    ACanvas.Ellipse(R);
  end;
end;

procedure TChessBoardView.DrawDragging(ACanvas: TCanvas);
var Bmp: TBitmap; R: TRect;
begin
  if not FDragging then Exit;
  Bmp := FindPieceBitmap(FDragPiece);
  if Bmp = nil then Exit;
  R.Left := FDragPos.X - FSquareSize div 2;
  R.Top  := FDragPos.Y - FSquareSize div 2;
  R.Right := R.Left + FSquareSize;
  R.Bottom := R.Top + FSquareSize;
  ACanvas.StretchDraw(R, Bmp);
end;

procedure TChessBoardView.Paint;
var c, r: Integer;
begin
  inherited Paint;
  DrawBoard(Canvas);
  DrawHighlights(Canvas);
  // disegna i pezzi tranne quello che stiamo trascinando
  for c := 0 to 7 do
    for r := 0 to 7 do
      if not (FDragging and (FDragFrom.Col = c) and (FDragFrom.Row = r)) then
        DrawPiece(Canvas, Sq(c, r));
  DrawDragging(Canvas);
end;

{ ---------- interazione mouse ---------- }

function TChessBoardView.SquareAt(X, Y: Integer; out S: TSquare): Boolean;
var
  col, row: Integer;
begin
  Result := False;
  if FSquareSize <= 0 then Exit;
  col := (X - FBoardOrigin.X) div FSquareSize;
  row := (Y - FBoardOrigin.Y) div FSquareSize;
  if (col in [0..7]) and (row in [0..7]) then
  begin
    S.Col := col; S.Row := row;
    Result := True;
  end;
end;

procedure TChessBoardView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var S: TSquare; P: TPiece; i, n: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if not SquareAt(X, Y, S) then Exit;

  P := FBoard.Pieces[S.Col, S.Row];
  if P.Kind = ptNone then Exit;

  FDragging := True;
  FDragFrom := S;
  FDragPiece := P;
  FDragPos := Point(X, Y);

  // calcola destinazioni legali
  FLegalDests := FBoard.GetLegalDestinations(S);
  n := Length(FLegalDests);
  if n = 0 then
  begin
    // niente mosse: annulla il drag
    FDragging := False;
    Exit;
  end;
  SetCapture(Handle);
  Invalidate;
end;

procedure TChessBoardView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    FDragPos := Point(X, Y);
    Invalidate;
  end;
end;

procedure TChessBoardView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var S: TSquare; ok: Boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not FDragging then Exit;
  if Button <> mbLeft then Exit;

  ReleaseCapture;
  FDragging := False;
  FLegalDests := nil;

  if SquareAt(X, Y, S) then
  begin
    // stessa casella? annulla
    if (S.Col <> FDragFrom.Col) or (S.Row <> FDragFrom.Row) then
    begin
      ok := FBoard.ApplyMove(FDragFrom, S);
      // se non è valida, il modello non cambia nulla → il pezzo resta dov'era
      if not ok then
        Beep;   // oppure feedback visivo
    end;
  end;
  Invalidate;
end;

{ ---------- API di alto livello ---------- }

procedure TChessBoardView.NewGame;
begin
  FBoard.SetupInitial;
  FBoard.ClearMoveList;
  Invalidate;
end;

procedure TChessBoardView.LoadFEN(const FEN: string);
begin
  FBoard.LoadFEN(FEN);
  FBoard.ClearMoveList;
  Invalidate;
end;

function TChessBoardView.GetFEN: string;
begin
  Result := FBoard.GetFEN;
end;

procedure TChessBoardView.ClearMoves;
begin
  FBoard.ClearMoveList;
end;

procedure TChessBoardView.StepBackward;
begin
  FBoard.RewindOne;
  Invalidate;
end;

procedure TChessBoardView.StepForward;
begin
  FBoard.ForwardOne;
  Invalidate;
end;

function TChessBoardView.MoveCount: Integer;
begin Result := FBoard.GetMoveCount; end;

function TChessBoardView.GetMove(Index: Integer): TChessMove;
begin Result := FBoard.GetMove(Index); end;

procedure TChessBoardView.PlayMove(const FromSq, ToSq: TSquare);
begin
  if FBoard.ApplyMove(FromSq, ToSq) then
    Invalidate;
end;

procedure TChessBoardView.UndoMove;
begin
  FBoard.UndoLastMove;
  Invalidate;
end;

function TChessBoardView.GetCurrentMoveIndex: Integer;
begin Result := FBoard.GetCurrentMoveIndex; end;

end.