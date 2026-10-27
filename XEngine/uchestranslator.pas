unit uchestranslator;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, uchesslogic;

type
  { Converte "e2e4" → dalla casella e2 alla e4.
    Promotion: 'q','r','b','n' oppure #0 se assente.
    Restituisce False se la stringa non è valida. }
  function UCIToMove(const UCI: string;
                     out FromSq, ToSq: TSquare;
                     out Promo: TPieceType): Boolean;

  { Converte una mossa interna in stringa UCI.
    Nota: l'arrocco diventa e1g1/e1c1 anche se internamente
    potrebbe essere codificato diversamente. }
  function MoveToUCI(const M: TChessMove): string;

  { Converte coordinate interne in notazione algebrica (es. "e4") }
  function SquareToAlgebra(const S: TSquare): string;

  { Converte notazione algebrica in coordinate interne }
  function AlgebraToSquare(const S: string; out Sq: TSquare): Boolean;

  { Trova una mossa interna che corrisponde alla stringa UCI,
    cercando tra le mosse legali fornite. }
  function FindMoveByUCI(const UCI: string;
                         const LegalMoves: TMoveList): Integer;

implementation

function SquareToAlgebra(const S: TSquare): string;
begin
  if (S.Col in [0..7]) and (S.Row in [0..7]) then
    Result := Chr(Ord('a') + S.Col) + Chr(Ord('8') - S.Row)
  else
    Result := '??';
end;

function AlgebraToSquare(const S: string; out Sq: TSquare): Boolean;
begin
  Result := False;
  if Length(S) < 2 then Exit;
  Sq.Col := Ord(S[1]) - Ord('a');
  Sq.Row := Ord('8') - Ord(S[2]);
  Result := (Sq.Col in [0..7]) and (Sq.Row in [0..7]);
end;

function UCIToMove(const UCI: string;
                   out FromSq, ToSq: TSquare;
                   out Promo: TPieceType): Boolean;
var
  s: string;
  pc: Char;
begin
  Result := False;
  Promo := ptNone;
  s := Trim(LowerCase(UCI));
  if Length(s) < 4 then Exit;

  if not AlgebraToSquare(Copy(s, 1, 2), FromSq) then Exit;
  if not AlgebraToSquare(Copy(s, 3, 2), ToSq) then Exit;

  if Length(s) >= 5 then
  begin
    pc := s[5];
    case pc of
      'q': Promo := ptQueen;
      'r': Promo := ptRook;
      'b': Promo := ptBishop;
      'n': Promo := ptKnight;
    else
      Exit;
    end;
  end;
  Result := True;
end;

function MoveToUCI(const M: TChessMove): string;
var
  promoChar: Char;
begin
  Result := Chr(Ord('a') + M.FromCol) + Chr(Ord('8') - M.FromRow)
          + Chr(Ord('a') + M.ToCol)   + Chr(Ord('8') - M.ToRow);
  promoChar := #0;
  case M.Promotion of
    ptQueen : promoChar := 'q';
    ptRook  : promoChar := 'r';
    ptBishop: promoChar := 'b';
    ptKnight: promoChar := 'n';
  end;
  if promoChar <> #0 then
    Result := Result + promoChar;
end;

function FindMoveByUCI(const UCI: string;
                       const LegalMoves: TMoveList): Integer;
var
  i: Integer;
  target: string;
begin
  Result := -1;
  target := LowerCase(Trim(UCI));
  for i := 0 to High(LegalMoves) do
    if LowerCase(MoveToUCI(LegalMoves[i])) = target then
      Exit(i);
end;

end.