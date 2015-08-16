unit TOblsRizeni;

{
  Trida TORs sdruzuje oblasti rizeni do databaze.
}

interface

uses TOblRizeni, IniFiles, SysUtils, Classes, RPConst, COmCtrls, IdContext,
      StdCtrls, Generics.Collections;

type
  //recordy vyuzivany pri externich implementacich navaznosti na OR (napriklad u technologickych bloku)
  // vyuziva se i u TCP serveru - kazde spojeni si pamatuje, jake jsou na nem oblasti rizeni
  TORsRef = record
    ORs:array [0.._MAX_ORREF-1] of TOR;
    Cnt:Integer;
  end;

  TORs = class
   private const
     _SECT_OR = 'OR';                                                           // sekce ini souboru .spnl, ve ktere jsou ulozeny oblasti rizeni

   private
     ORsDatabase:TList<TOR>;                                                    // databaze oblasti rizeni

     procedure FreeORs();                                                       // zniceni a vymazani vsech OR
     function GetORCnt():Integer;                                               // vrati pocet OR

   public
      constructor Create();
      destructor Destroy(); override;

      function LoadData(const filename:string):Byte;
      function GetORIndex(const id:string):Integer;
      function ParseORs(str:string):TORsRef;                                    // parsuje seznam oblasti rizeni
      procedure MTBFail(addr:integer);                                          // je vyvolano pri vypadku MTB modulu, resi zobrazeni chyby do panelu v OR
      function GetORByIndex(index:Integer;var obl:TOR):Byte;
      function GetORNameByIndex(index:Integer):string;
      function GetORIdByIndex(index:Integer):string;
      function GetORShortNameByIndex(index:Integer):string;

      procedure Update();                                                       // aktualizuje stav OR
      procedure DisconnectPanels();                                             // odpoji vsechny panely dane OR
      procedure SendORList(Context:TIdContext);                                 // odesle seznam vsech OR na spojeni \Context

      procedure FillCB(CB:TComboBox; selected:TOR);                             // naplni ComboBox seznamem oblasti rizeni

      property Count:Integer read GetORCnt;                                     // vrati seznam oblasti rizeni
  end;//TORs

var
  ORs:TORs;

implementation

uses Prevody, Logging, TCPServerOR, THVDatabase;

////////////////////////////////////////////////////////////////////////////////

constructor TORs.Create();
begin
 inherited;
 Self.ORsDatabase := TList<TOR>.Create();
end;//ctor

destructor TORs.Destroy();
begin
 Self.FreeORs();
 Self.ORsDatabase.Free();
 inherited Destroy();
end;//dtor

////////////////////////////////////////////////////////////////////////////////

//nacitani OR a vytvareni vsech OR
function TORs.LoadData(const filename:string):Byte;
var ini:TMemIniFile;
    oblasti:TStrings;
    i:Integer;
    OblR:TOR;
begin
 if (not FileExists(filename)) then
  begin
   writelog('Soubor se stanicemi neexistuje - '+filename,WR_ERROR);
   Exit(1);
  end;

 writelog('Na��t�m stanice - '+filename,WR_DATA);

 Self.ORsDatabase.Clear();
 ini := TMemIniFile.Create(filename);
 oblasti := TStringList.Create();

 ini.ReadSection(_SECT_OR, oblasti);

 for i := 0 to oblasti.Count-1 do
  begin
   OblR := TOR.Create(i);
   if (OblR.LoadData(ini.ReadString(_SECT_OR, oblasti[i], '')) = 0) then Self.ORsDatabase.Add(OblR);
  end;//for i

 oblasti.Free();
 ini.Free();
 Result := 0;

 writelog('Na�teno '+IntToStr(Self.ORsDatabase.Count)+' stanic',WR_DATA);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

//smazani databaze a regulerni zniceni trid v teto databazi
procedure TORs.FreeORs();
var i:Integer;
begin
 for i := 0 to Self.ORsDatabase.Count-1 do
   if (Assigned(Self.ORsDatabase[i])) then Self.ORsDatabase[i].Free();
 Self.ORsDatabase.Clear();
end;//procedure

////////////////////////////////////////////////////////////////////////////////

//vrati index OR s danym ID (index v databazi ORs)
function TORs.GetORIndex(const id:string):Integer;
var i:Integer;
begin
 for i := 0 to Self.ORsDatabase.Count-1 do
   if (Self.ORsDatabase[i].id = id) then
     Exit(i);

 Result := -1;
end;//function

////////////////////////////////////////////////////////////////////////////////

//parsing OR stringu
function TORs.ParseORs(str:string):TORsRef;
var parsed:TStrings;
    i:Integer;
begin
 parsed := TStringList.Create();

 ExtractStrings(['|'],[],PChar(str),parsed);

 Result.Cnt := parsed.Count;
 for i := 0 to parsed.Count-1 do
    Result.ORs[i] := Self.ORsDatabase[Self.GetORIndex(parsed[i])];

 parsed.Free();
end;//function

////////////////////////////////////////////////////////////////////////////////

function TORs.GetORByIndex(index:Integer; var obl:TOR):Byte;
begin
 if ((index < 0) or (index >= Self.ORsDatabase.Count)) then Exit(1);
 obl := Self.ORsDatabase[index];
 Result := 0;
end;//function

////////////////////////////////////////////////////////////////////////////////

function TORs.GetORNameByIndex(index:Integer):string;
begin
 if ((index < 0) or (index >= Self.ORsDatabase.Count)) then
   Exit('## OR s timto indexem neexistuje ##');

 Result := Self.ORsDatabase[index].Name;
end;//function

function TORs.GetORIdByIndex(index:Integer):string;
begin
 if ((index < 0) or (index >= Self.ORsDatabase.Count)) then
   Exit('## OR s timto indexem neexistuje ##');

 Result := Self.ORsDatabase[index].id;
end;//function

function TORs.GetORShortNameByIndex(index:Integer):string;
begin
 if ((index < 0) or (index >= Self.ORsDatabase.Count)) then
   Exit('## OR s timto indexem neexistuje ##');

 Result := Self.ORsDatabase[index].ShortName;
end;//function

procedure TORs.Update();
var i:Integer;
begin
 for i := 0 to Self.ORsDatabase.Count-1 do
   Self.ORsDatabase[i].Update();
end;//procedure

procedure TORs.DisconnectPanels();
var i:Integer;
begin
 for i := 0 to Self.ORsDatabase.Count-1 do
   Self.ORsDatabase[i].DisconnectPanels();

 // vymazeme vsechny otevrene regulatory u klientu
 for i := 0 to _MAX_ADDR-1 do
  if (Assigned(HVDb.HVozidla[i])) then
    HVDb.HVozidla[i].Stav.regulators.Clear();
end;//procedure

procedure TORs.SendORList(Context:TIdContext);
var i:Integer;
    str:string;
begin
 str := '-;OR-LIST;';
 for i := 0 to Self.ORsDatabase.Count-1 do
   str := str + '[' + Self.ORsDatabase[i].id + ',' + Self.ORsDatabase[i].Name + ']';

 ORTCPServer.SendLn(Context, str);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TORs.MTBFail(addr:integer);
var i:Integer;
begin
 for i := 0 to Self.ORsDatabase.Count-1 do
  Self.ORsDatabase[i].MTBFail(addr);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TORs.FillCB(CB:TComboBox; selected:TOR);
var i:Integer;
begin
 CB.Clear();
 for i := 0 to Self.ORsDatabase.Count-1 do
  begin
   CB.Items.Add(Self.ORsDatabase[i].Name);
   if (Self.ORsDatabase[i] = selected) then
    CB.ItemIndex := i;
  end;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

function TORs.GetORCnt():Integer;
begin
 Result := Self.ORsDatabase.Count;
end;

////////////////////////////////////////////////////////////////////////////////

end.//unit
