unit uuciinfo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TScoreKind = (skNone, skCentipawns, skMate);

  TAnalysisInfo = record
    Depth      : Integer;
    SelDepth   : Integer;
    MultiPV    : Integer;   // 1 se assente
    ScoreKind  : TScoreKind;
    ScoreValue : Integer;   // in cp oppure mosse-per-matto (segno = chi è avanti)
    Nodes      : Int64;
    NPS        : Int64;
    TimeMs     : Integer;
    HashFull   : Integer;
    PV         : TStringList;   // mosse in notazione UCI
    Raw        : string;        // riga originale
  end;

  { Inizializza/azzera una struttura TAnalysisInfo (PV incluso). }
  procedure InitInfo(out Info: TAnalysisInfo);
  procedure FreeInfo(var Info: TAnalysisInfo);
  procedure AssignInfo(const Src: TAnalysisInfo; var Dst: TAnalysisInfo);
  function  CloneInfo(const Src: TAnalysisInfo): TAnalysisInfo;

  { Parsa una riga "info ..." e riempie Info.
    Restituisce False se non è una riga "info" o è malformata. }
  function ParseInfoLine(const Line: string; out Info: TAnalysisInfo): Boolean;

  { Produce una stringa leggibile del punteggio, es. "+0.25" o "#3" }
  function FormatScore(const Info: TAnalysisInfo): string;

  { Converte il PV in stringa separata da spazi }
  function FormatPV(const Info: TAnalysisInfo): string;

implementation

procedure InitInfo(out Info: TAnalysisInfo);
begin
  Info.Depth := 0;
  Info.SelDepth := 0;
  Info.MultiPV := 1;
  Info.ScoreKind := skNone;
  Info.ScoreValue := 0;
  Info.Nodes := 0;
  Info.NPS := 0;
  Info.TimeMs := 0;
  Info.HashFull := 0;
  Info.PV := TStringList.Create;
  Info.Raw := '';
end;

procedure FreeInfo(var Info: TAnalysisInfo);
begin
  Info.PV.Free;
  Info.PV := nil;
end;

procedure AssignInfo(const Src: TAnalysisInfo; var Dst: TAnalysisInfo);
begin
  Dst.Depth := Src.Depth;
  Dst.SelDepth := Src.SelDepth;
  Dst.MultiPV := Src.MultiPV;
  Dst.ScoreKind := Src.ScoreKind;
  Dst.ScoreValue := Src.ScoreValue;
  Dst.Nodes := Src.Nodes;
  Dst.NPS := Src.NPS;
  Dst.TimeMs := Src.TimeMs;
  Dst.HashFull := Src.HashFull;
  if Dst.PV = nil then Dst.PV := TStringList.Create;
  Dst.PV.Assign(Src.PV);
  Dst.Raw := Src.Raw;
end;

function CloneInfo(const Src: TAnalysisInfo): TAnalysisInfo;
begin
  InitInfo(Result);
  AssignInfo(Src, Result);
end;

function ParseInfoLine(const Line: string; out Info: TAnalysisInfo): Boolean;
var
  parts: TStringArray;
  i, n: Integer;
  token: string;
  inPV: Boolean;

  function NextToken(out t: string): Boolean;
  begin
    Inc(i);
    if i <= High(parts) then begin t := parts[i]; Result := True; end
    else begin t := ''; Result := False; end;
  end;

begin
  Result := False;
  InitInfo(Info);

  if Copy(Line, 1, 5) <> 'info ' then
  begin
    FreeInfo(Info);
    Exit;
  end;

  Info.Raw := Line;
  parts := Line.Split([' ']);
  n := Length(parts);
  i := 0;               // parts[0] = 'info'
  inPV := False;

  while i < n - 1 do
  begin
    Inc(i);
    token := parts[i];
    if inPV then
    begin
      Info.PV.Add(token);
      Continue;
    end;

    if token = 'depth' then
    begin
      if NextToken(token) then Info.Depth := StrToIntDef(token, 0);
    end
    else if token = 'seldepth' then
    begin
      if NextToken(token) then Info.SelDepth := StrToIntDef(token, 0);
    end
    else if token = 'multipv' then
    begin
      if NextToken(token) then Info.MultiPV := StrToIntDef(token, 1);
    end
    else if token = 'nodes' then
    begin
      if NextToken(token) then Info.Nodes := StrToInt64Def(token, 0);
    end
    else if token = 'nps' then
    begin
      if NextToken(token) then Info.NPS := StrToInt64Def(token, 0);
    end
    else if token = 'time' then
    begin
      if NextToken(token) then Info.TimeMs := StrToIntDef(token, 0);
    end
    else if token = 'hashfull' then
    begin
      if NextToken(token) then Info.HashFull := StrToIntDef(token, 0);
    end
    else if token = 'score' then
    begin
      if NextToken(token) then
      begin
        if token = 'cp' then
        begin
          if NextToken(token) then
          begin
            Info.ScoreKind := skCentipawns;
            Info.ScoreValue := StrToIntDef(token, 0);
          end;
        end
        else if token = 'mate' then
        begin
          if NextToken(token) then
          begin
            Info.ScoreKind := skMate;
            Info.ScoreValue := StrToIntDef(token, 0);
          end;
        end;
      end;
    end
    else if token = 'pv' then
    begin
      inPV := True;
    end
    // token sconosciuti (currmove, currmovenumber, tbhits, ...) vengono ignorati
  end;

  Result := True;
end;

function FormatScore(const Info: TAnalysisInfo): string;
var
  v: Integer;
begin
  case Info.ScoreKind of
    skNone: Result := 'n/a';
    skCentipawns:
      begin
        v := Info.ScoreValue;
        if v >= 0 then
          Result := Format('+%.2f', [v / 100.0])
        else
          Result := Format('%.2f', [v / 100.0]);
      end;
    skMate:
      begin
        v := Info.ScoreValue;
        if v > 0 then
          Result := Format('#%d', [v])
        else if v < 0 then
          Result := Format('-#%d', [-v])
        else
          Result := '#0';
      end;
  else
    Result := 'n/a';
  end;
end;

function FormatPV(const Info: TAnalysisInfo): string;
begin
  Result := Info.PV.CommaText;
  if Result <> '' then
    Result := StringReplace(Result, ',', ' ', [rfReplaceAll]);
end;

end.