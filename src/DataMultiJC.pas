unit DataMultiJC;

// TMultiJCTableData - trida starajici se o vyplneni tabulky slozenych jizdnich
//      cest

interface

uses ComCtrls, SysUtils, RPConst;

type
  TMultiJCTableData=class
    private
      LV:TListView;

    public

      procedure LoadToTable();
      procedure UpdateTable();

      procedure UpdateLine(line:Integer);

      procedure AddJC();
      procedure RemoveJC(index:Integer);

      constructor Create(LV:TListView);
  end;

var
  MultiJCTableData : TMultiJCTableData;

implementation

uses TBlokUsek, TBlokVyhybka, TMultiJCDatabase, TechnologieMultiJC,
     TBlok, TBloky, fMain, TBlokSCom, TJCDatabase;

////////////////////////////////////////////////////////////////////////////////

constructor TMultiJCTableData.Create(LV:TListView);
begin
 inherited Create();
 Self.LV := LV;
end;//ctor

////////////////////////////////////////////////////////////////////////////////

procedure TMultiJCTableData.LoadToTable();
var i, j:Integer;
    LI:TListItem;
begin
 Self.LV.Clear();

 for i := 0 to MultiJCDb.Count-1 do
  begin
   LI := Self.LV.Items.Add;
   LI.Caption := IntToStr(i);
   for j := 0 to Self.LV.Columns.Count-2 do
    LI.SubItems.Add('');

   try
     Self.UpdateLine(i);
   except

   end;
 end;//for i

end;//procedure

procedure TMultiJCTableData.UpdateTable();
var i:Integer;
    repaint:boolean;
begin
 repaint := false;
 for i := 0 to MultiJCDb.Count-1 do
   if (MultiJCDb.GetJCByIndex(i).changed) then
    begin
     repaint := true;
     try
       Self.UpdateLine(i);
     except

     end;
    end;

 if (repaint) then
  Self.LV.Repaint();
end;//procedure

procedure TMultiJCTableData.UpdateLine(line:Integer);
var mJCData:TMultiJCprop;
    mJC:TMultiJC;
    i:Integer;
    str:string;
begin
 mJC     := MultiJCDb.GetJCByIndex(line);
 mJCData := mJC.data;
 mJC.changed := false;

 Self.LV.Items.Item[line].Caption := IntToStr(line);
 Self.LV.Items.Item[line].SubItems.Strings[0] := mJCData.Nazev;

 // krok ( = aktualne stavena JC)
 Self.LV.Items.Item[line].SubItems.Strings[1] := IntToStr(mJC.stav.JCIndex);

 // jednotlive jizdni cesty
 str := '';
 for i := 0 to mJCData.JCs.Count-1 do
  str := str + '(' + JCDb.GetJCByIndex(mJCData.JCs[i]).nazev + '), ';
 Self.LV.Items.Item[line].SubItems.Strings[2] := str;

 // variantni body
 str := '';
 for i := 0 to mJCData.vb.Count-1 do
   str := str + Blky.GetBlkName(mJCData.vb[i]) + ', ';
 Self.LV.Items.Item[line].SubItems.Strings[3] := str;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TMultiJCTableData.AddJC();
var LI:TListItem;
    j:Integer;
begin
 LI := Self.LV.Items.Add;
 LI.Caption := IntToStr(Self.LV.Items.Count);
 for j := 0 to Self.LV.Columns.Count-2 do
  LI.SubItems.Add('');

 Self.UpdateLine(Self.LV.Items.Count-1);
end;//procedure

procedure TMultiJCTableData.RemoveJC(index:Integer);
begin
 Self.LV.Items.Delete(index);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

initialization

finalization
 MultiJCTableData.Free();

end.//unit
