unit Game;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, Grids, Menus,
  StdCtrls, Types;

type

  TPiece = (pcNone, pcWPawn, pcWKnight, pcWBishop, pcWRook, pcWQueen, pcWKing,
                    pcBPawn, pcBKnight, pcBBishop, pcBRook, pcBQueen, pcBKing);



  TBoard = array[0..7, 0..7] of TPiece;

  { TForm1 }

  TForm1 = class(TForm)
    BoardGrid: TDrawGrid;
    MainMenu1: TMainMenu;
    CommentMemo: TMemo;
    StatusBar1: TStatusBar;
    MovesTree: TTreeView;
    procedure AddMoveToTree(FromC, FromR, ToC, ToR: Integer);
    procedure BoardGridDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
    procedure BoardGridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoardGridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoardGridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;
  Board: TBoard;
  SelectedCol, SelectedRow: Integer;
  PieceSelected: Boolean;
  Dragg: Boolean;
  DragCol, DragRow: Integer;
  DragX, DragY: Integer;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.AddMoveToTree(FromC, FromR, ToC, ToR: Integer);
var
  MoveText: string;
  Node: TTreeNode;
begin
  MoveText := Format('%s%d-%s%d',
    [Chr(Ord('a') + FromC), 8-FromR,
     Chr(Ord('a') + ToC),   8-ToR]);

  if MovesTree.Selected = nil then
    Node := MovesTree.Items.Add(nil, MoveText)
  else
    Node := MovesTree.Items.AddChild(MovesTree.Selected, MoveText);

  MovesTree.Selected := Node;
end;


procedure TForm1.BoardGridMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  DragCol := X div BoardGrid.DefaultColWidth;
  DragRow := Y div BoardGrid.DefaultRowHeight;

  if (DragCol in [0..7]) and (DragRow in [0..7]) and
     (Board[DragCol, DragRow] <> pcNone) then
  begin
    Dragg := True;
    DragX := X;
    DragY := Y;
    BoardGrid.Invalidate;
  end;
end;

procedure TForm1.BoardGridMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
   if Dragg then
  begin
    DragX := X;
    DragY := Y;
    BoardGrid.Invalidate;
  end;
end;

procedure TForm1.BoardGridMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  TargetCol, TargetRow: Integer;
begin
  if not Dragg then Exit;

  TargetCol := X div BoardGrid.DefaultColWidth;
  TargetRow := Y div BoardGrid.DefaultRowHeight;

  if (TargetCol in [0..7]) and (TargetRow in [0..7]) then
  begin
    Board[TargetCol, TargetRow] := Board[DragCol, DragRow];
    Board[DragCol, DragRow] := pcNone;
    AddMoveToTree(DragCol, DragRow, TargetCol, TargetRow);
  end;

  Dragg := False;
  BoardGrid.Invalidate;
end;

procedure TForm1.BoardGridDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
  var
    Piece: TPiece;
    IsSource: Boolean;
    cx, cy: Integer;
begin
  IsSource := Dragg and (ACol = DragCol) and (ARow = DragRow);

  if (ACol + ARow) mod 2 = 0 then
    BoardGrid.Canvas.Brush.Color := $F0D9B5
  else
    BoardGrid.Canvas.Brush.Color := $B58863;
  if IsSource then
    BoardGrid.Canvas.Brush.Color := clYellow;
  BoardGrid.Canvas.FillRect(aRect);
  Piece := Board[ACol, ARow];

  if IsSource and Dragg then     // se stiamo trascinando, non disegnare il pezzo nella casella sorgente
    Piece := pcNone;
  BoardGrid.Canvas.Font.Size := 32;

  case Piece of
    pcWPawn:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♙');
    pcWKnight: BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♘');
    pcWBishop: BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♗');
    pcWRook:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♖');
    pcWQueen:  BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♕');
    pcWKing:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♔');
    pcBPawn:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♟');
    pcBKnight: BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♞');
    pcBBishop: BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♝');
    pcBRook:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♜');
    pcBQueen:  BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♛');
    pcBKing:   BoardGrid.Canvas.TextOut(aRect.Left+16, aRect.Top+8, '♚');
  end;

  // pezzo “in volo”

  if Dragg and (ACol = 0) and (ARow = 0) then

  begin

    // disegna sopra la griglia, usando le coordinate DragX/DragY

    Piece := Board[DragCol, DragRow];
    if Piece <> pcNone then
    begin
      cx := DragX - BoardGrid.DefaultColWidth div 2;
      cy := DragY - BoardGrid.DefaultRowHeight div 2;
      case Piece of
        pcWPawn:   BoardGrid.Canvas.TextOut(cx, cy, '♙');
        pcWKnight: BoardGrid.Canvas.TextOut(cx, cy, '♘');
        pcWBishop: BoardGrid.Canvas.TextOut(cx, cy, '♗');
        pcWRook:   BoardGrid.Canvas.TextOut(cx, cy, '♖');
        pcWQueen:  BoardGrid.Canvas.TextOut(cx, cy, '♕');
        pcWKing:   BoardGrid.Canvas.TextOut(cx, cy, '♔');
        pcBPawn:   BoardGrid.Canvas.TextOut(cx, cy, '♟');
        pcBKnight: BoardGrid.Canvas.TextOut(cx, cy, '♞');
        pcBBishop: BoardGrid.Canvas.TextOut(cx, cy, '♝');
        pcBRook:   BoardGrid.Canvas.TextOut(cx, cy, '♜');
        pcBQueen:  BoardGrid.Canvas.TextOut(cx, cy, '♛');
        pcBKing:   BoardGrid.Canvas.TextOut(cx, cy, '♚');
      end;
    end;
  end;
end;


procedure InitBoard;
var
  i: integer;
begin

  for i := 0 to 7 do begin  // Pedoni
    Board[i,1] := pcWPawn;
    Board[i,6] := pcBPawn;
  end;

  Board[0,0] := pcWRook;    // Pezzi bianchi
  Board[1,0] := pcWKnight;
  Board[2,0] := pcWBishop;
  Board[3,0] := pcWQueen;
  Board[4,0] := pcWKing;
  Board[5,0] := pcWBishop;
  Board[6,0] := pcWKnight;
  Board[7,0] := pcWRook;
  Board[0,7] := pcBRook;    // Pezzi neri
  Board[1,7] := pcBKnight;
  Board[2,7] := pcBBishop;
  Board[3,7] := pcBQueen;
  Board[4,7] := pcBKing;
  Board[5,7] := pcBBishop;
  Board[6,7] := pcBKnight;
  Board[7,7] := pcBRook;

end;


procedure TForm1.FormCreate(Sender: TObject);
begin
  InitBoard;
  BoardGrid.Invalidate;
  Dragg := False;
  PieceSelected:= False;
end;

end.

