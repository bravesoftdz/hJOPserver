unit Souprava;

// trida "TSouprava"

interface

uses IniFiles, SysUtils, Classes, Forms, IBUtils, THnaciVozidlo, houkEvent,
     Generics.Collections, predvidanyOdjezd, TBlok;

const
  _MAX_SPR_HV = 4;

type
  TSoupravaHV = record
   HVs:array [0.._MAX_SPR_HV-1] of Integer;
   cnt:Integer;
  end;

  TSoupravaData = record
   nazev : string;
   pocet_vozu : Word;
   poznamka : string;
   delka:Integer;     // delka soupravy v centimetrech - polde toho se urcuje zastavovani na blocich
   typ:string;        // MOs, Os, Mn, Pn, ... - podle toho se urcuje zastavovaci udalost

   // ovlivnuje vybarvovani sipecky
   smer_L:boolean;
   smer_S:boolean;

   HV:TSoupravaHV;

   OblRizeni:TObject;
   rychlost:Integer;
   smer:THVStanoviste;
   front:TObject;   // nejprednejsi blok, kde je souprava

   vychoziOR:TObject;
   cilovaOR:TObject;

   hlaseniPrehrano:boolean;
   podj:TDictionary<Integer, TPOdj>;  // id useku : predvidany odjezd
  end;//TSoupravaData

  TSouprava = class
   private
    data:TSoupravaData;
    findex:Integer;
    filefront:Integer;
    speedBuffer:PInteger;                                                       // pokud tento ukazatel neni nil, rychlost je nastavovana do promenne, na kterou ukazuje a ne primo souprave; to se hodi napriklad v zastavce v TU

    procedure LoadFromFile(ini:TMemIniFile; const section:string);
    procedure LoadFromPanelStr(spr:TStrings; Usek:TObject; OblR:TObject);

    procedure ReleaseAllLoko();

    procedure SetOR(OblRizeni:TObject);

    procedure HVComErr(Sender:TObject; Data:Pointer);
    procedure SetSpeed(speed:Integer);
    procedure SetSmer(smer:THVStanoviste);
    procedure SetFront(front:TObject);

    function IsUkradeno():boolean;

   public

    changed:boolean;

    constructor Create(ini:TMemIniFile; const section:string; index:Integer); overload;
    constructor Create(panelStr:TStrings; Usek:TObject; index:Integer; OblR:TObject); overload;
    destructor Destroy(); override;

    procedure SaveToFile(ini:TMemIniFile; const section:string);

    function GetPanelString():string;   // vraci string, kterym je definovana souprava, do panelu
    procedure UpdateSprFromPanel(spr:TStrings; Usek:TObject; OblR:TObject);
    procedure SetRychlostSmer(speed:Integer; dir:THVStanoviste);
    procedure VezmiVlak();
    procedure UpdateFront();
    procedure ChangeSmer();
    procedure InterChangeStanice(change_ev:Boolean = true);
    procedure SetSpeedBuffer(speedBuffer:PInteger);
    procedure LokDirChanged();
    procedure CheckSH(nav:TObject);

    procedure ToggleHouk(desc:string);
    procedure SetHoukState(desc:string; state:boolean);

    procedure AddOrUpdatePOdj(usekid:Integer; var podj:TPOdj); overload;
    procedure AddOrUpdatePOdj(usek:TBlk; var podj:TPOdj); overload;
    function IsPOdj(usekid:Integer):Boolean; overload;
    function IsPOdj(usek:TBlk):Boolean; overload;
    function GetPOdj(usekid:Integer):TPOdj; overload;
    function GetPOdj(usek:TBlk):TPOdj; overload;
    procedure RemovePOdj(usekid:Integer); overload;
    procedure RemovePOdj(usek:TBlk); overload;
    procedure ClearPOdj();

    property nazev:string read data.nazev;
    property sdata:TSoupravaData read data;
    property index:Integer read findex;
    property stanice:TObject read data.OblRizeni write SetOR;
    property rychlost:Integer read data.rychlost write SetSpeed;
    property smer:THVStanoviste read data.smer write SetSmer;
    property ukradeno:boolean read IsUkradeno;
    property front:TObject read data.front write SetFront;
    property delka:Integer read data.delka;
    property typ:string read data.typ;
    property vychoziOR:TObject read data.vychoziOR;
    property cilovaOR:TObject read data.cilovaOR;
    property hlaseniPrehrano:boolean read data.hlaseniPrehrano;

    // uvolni stara hnaci vozidla ze soupravy (pri zmene HV na souprave)
    class procedure UvolV(old:TSoupravaHV; new:TSoupravaHV);

  end;//TSouprava

implementation

uses THVDatabase, Logging, ownStrUtils, SprDb, TBlokUsek, DataSpr, appEv,
      DataHV, TOblsRizeni, TOblRizeni, TCPServerOR, TBloky, TBlokSCom,
      fRegulator, Trakce, fMain, TBlokTratUsek, stanicniHlaseniHelper,
      stanicniHlaseni;

////////////////////////////////////////////////////////////////////////////////

constructor TSouprava.Create(ini:TMemIniFile; const section:string; index:Integer);
begin
 inherited Create();
 Self.speedBuffer := nil;
 Self.changed := false;
 Self.findex := index;
 Self.data.podj := TDictionary<Integer, TPOdj>.Create();
 Self.LoadFromFile(ini, section);
 Self.data.hlaseniPrehrano := false;
end;//ctor

constructor TSouprava.Create(panelStr:TStrings; Usek:TObject; index:Integer; OblR:TObject);
begin
 inherited Create();
 Self.speedBuffer := nil;
 Self.findex := index;
 Self.data.podj := TDictionary<Integer, TPOdj>.Create();
 Self.LoadFromPanelStr(panelStr, Usek, OblR);
end;//ctor

destructor TSouprava.Destroy();
begin
 Self.ReleaseAllLoko();
 Self.ClearPOdj();
 Self.data.podj.Free();

 inherited;
end;//dtor

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.LoadFromFile(ini:TMemIniFile; const section:string);
var i:Integer;
    data:TStrings;
begin
 Self.data.nazev      := ini.ReadString(section, 'nazev', section);
 Self.data.pocet_vozu := ini.ReadInteger(section, 'vozu', 0);
 Self.data.poznamka   := ini.ReadString(section, 'poznamka', '');
 Self.data.smer_L     := ini.ReadBool(section, 'L', false);
 Self.data.smer_S     := ini.ReadBool(section, 'S', false);
 Self.data.delka      := ini.ReadInteger(section, 'delka', 0);
 Self.data.typ        := ini.ReadString(section, 'typ', '');
 Self.filefront       := ini.ReadInteger(section, 'front', -1);
 Self.data.smer       := THVStanoviste(ini.ReadInteger(section, 'smer', Integer(THVStanoviste.lichy)));

 Self.data.vychoziOR  := ORs.GetORById(ini.ReadString(section, 'z', ''));
 Self.data.cilovaOR   := ORs.GetORById(ini.ReadString(section, 'do', ''));
 Self.data.OblRizeni  := ORs.GetORById(ini.ReadString(section, 'OR', ''));

 data := TStringList.Create();
 ExtractStrings([';', ','], [], PChar(ini.ReadString(section, 'HV', '')), data);

 // HV se nacitaji takto prapodivne pro osetreni pripadu, kdy u soupravy je uvedene HV, ktere neexistuje
 Self.data.HV.cnt := 0;
 try
   for i := 0 to data.Count-1 do
    begin
     Self.data.HV.HVs[Self.data.HV.cnt] := StrToInt(data[i]);
     if (Assigned(HVDb.HVozidla[Self.data.HV.HVs[Self.data.HV.cnt]])) then
      begin
       HVDb.HVozidla[Self.data.HV.HVs[Self.data.HV.cnt]].Stav.souprava := Self.index;
       Inc(Self.data.HV.cnt);
      end;
    end;
 except

 end;

 data.Free();
 Self.changed := true;
end;//procedure

procedure TSouprava.SaveToFile(ini:TMemIniFile; const section:string);
var str:string;
    i: Integer;
begin
 ini.WriteString(section, 'nazev', Self.data.nazev);
 ini.WriteInteger(section, 'vozu', Self.data.pocet_vozu);

 if (Self.data.poznamka <> '') then
   ini.WriteString(section, 'poznamka', Self.data.poznamka)
 else
   ini.DeleteKey(section, 'poznamka');

 ini.WriteInteger(section, 'delka', Self.data.delka);
 ini.WriteString(section, 'typ', Self.data.typ);
 ini.WriteBool(section, 'L', Self.data.smer_L);
 ini.WriteBool(section, 'S', Self.data.smer_S);
 ini.WriteInteger(section, 'smer', Integer(Self.data.smer));

 if (Self.data.vychoziOR <> nil) then
   ini.WriteString(section, 'z', TOR(Self.data.vychoziOR).id)
 else
   ini.DeleteKey(section, 'z');

 if (Self.data.cilovaOR <> nil) then
   ini.WriteString(section, 'do', TOR(Self.data.cilovaOR).id)
 else
   ini.DeleteKey(section, 'do');

 if (Self.data.front <> nil) then
   ini.WriteInteger(section, 'front', (Self.data.front as TBlk).id)
 else
   ini.WriteInteger(section, 'front', -1);

 if (Self.data.OblRizeni <> nil) then
   ini.WriteString(section, 'OR', (Self.data.OblRizeni as TOR).id)
 else
   ini.DeleteKey(section, 'OR');

 str := '';
 for i := 0 to Self.data.HV.cnt-1 do
  str := str + IntToStr(Self.data.HV.HVs[i]) + ';';
 ini.WriteString(section, 'HV', str);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

// vraci string, kterym je definovana souprava, do panelu
// format dat soupravy: nazev;pocet_vozu;poznamka;smer_Lsmer_S;delka;typ;hnaci vozidla;vychozi stanice;cilova stanice
function TSouprava.GetPanelString():string;
var i:Integer;
begin
 Result := Self.data.nazev + ';' + IntToStr(Self.data.pocet_vozu) + ';{' + Self.data.poznamka + '};';

 if (Self.data.smer_L) then
  Result := Result + '1'
 else
  Result := Result + '0';

 if (Self.data.smer_S) then
  Result := Result + '1'
 else
  Result := Result + '0';

 Result := Result + ';' + IntToStr(Self.data.delka) + ';' + Self.data.typ + ';{';

 for i := 0 to Self.data.HV.cnt-1 do
  Result := Result + '[{' + HVDb.HVozidla[Self.data.HV.HVs[i]].GetPanelLokString() + '}]';
 Result := Result + '};';

 if (Self.vychoziOR <> nil) then
   Result := Result + TOR(Self.vychoziOR).id;
 Result := Result + ';';

 if (Self.cilovaOR <> nil) then
   Result := Result + TOR(Self.cilovaOR).id;
 Result := Result + ';';
end;//function

////////////////////////////////////////////////////////////////////////////////

// format dat soupravy: nazev;pocet_vozu;poznamka;smer_Lsmer_S;delka;typ;hnaci vozidla;vychozi stanice;cilova stanice
// format hnaciho vozidla:  nazev|majitel|oznaceni|poznamka|adresa|trida|souprava|stanovisteA|funkce
procedure TSouprava.LoadFromPanelStr(spr:TStrings; Usek:TObject; OblR:TObject);
var hvs,hv:TStrings;
    i,j,timeout:Integer;
    old:TSoupravaHV;
    Func:TFunkce;
    max_func:Integer;
    smer:THVStanoviste;
begin
 hvs  := TStringList.Create();
 hv   := TStringList.Create();

 // zkontrolujeme, jestli nejaka souprava s timto cislem uz nahodou neexistuje
 for i := 0 to _MAX_SPR-1 do
  begin
   if (soupravy.soupravy[i] = nil) then continue;

   if ((Soupravy.soupravy[i].nazev = spr[0]) and (Soupravy.soupravy[i] <> Self)) then
    begin
     if (Soupravy.soupravy[i].stanice <> nil) then
       raise Exception.Create('Souprava '+Soupravy.soupravy[i].nazev+' ji� existuje v O� '+(Soupravy.soupravy[i].stanice as TOR).Name)
     else
       raise Exception.Create('Souprava '+Soupravy.soupravy[i].nazev+' ji� existuje');

     Exit();
    end;
  end;

 try
  StrToInt(spr[0]);
 except
   on E:EConvertError do
     raise Exception.Create('��slo soupravy nen� validn� ��slo!');
 end;

 Self.changed := true;

 Self.data.nazev := spr[0];
 Self.data.pocet_vozu := StrToInt(spr[1]);
 Self.data.poznamka := spr[2];
 Self.data.smer_L := (spr[3][1] = '1');
 Self.data.smer_S := (spr[3][2] = '1');

 Self.data.delka := StrToInt(spr[4]);
 Self.data.typ   := spr[5];

 Self.data.OblRizeni := OblR;
 Self.data.front     := Usek;

 if (spr.Count > 7) then
   Self.data.vychoziOR := ORs.GetORById(spr[7]);

 if (spr.Count > 8) then
   Self.data.cilovaOR := ORs.GetORById(spr[8]);

 ExtractStringsEx([']'], ['['], spr[6], hvs);

 // nejprve si zapamtujeme stara hnaci vozidla na souprave, abychom pak vedeli rozdil
 old.cnt := Self.data.HV.cnt;
 for i := 0 to Self.data.HV.cnt-1 do
  old.HVs[i] := Self.data.HV.HVs[i];

 // pak nacteneme samotna HV
 Self.data.HV.cnt := hvs.Count;
 for i := 0 to Self.data.HV.cnt-1 do
  begin
   hv.Clear();
   ExtractStringsEx(['|'], [], hvs[i], hv);
   Self.data.HV.HVs[i] := StrToInt(hv[4]);

   if (not Assigned(HVDb.HVozidla[Self.data.HV.HVs[i]])) then
    begin
     Self.data.HV.cnt := i;
     raise Exception.Create('Hnac� vozidlo s adresou '+IntToStr(Self.data.HV.HVs[i])+' neexistuje');
     Exit();
    end;

   if ((HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.souprava > -1) and (HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.souprava <> Self.index)) then
    begin
     Self.data.HV.cnt := i;
     raise Exception.Create('Loko '+IntToStr(Self.data.HV.HVs[i])+' ji� p�i�azena souprav� '+Soupravy.GetSprNameByIndex(HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.souprava));
     Exit();
    end;

   for j := 0 to i-1 do
    if (Self.data.HV.HVs[i] = Self.data.HV.HVs[j]) then
     begin
      Self.data.HV.cnt := i;
      raise Exception.Create('Duplicitn� loko!');
      Exit();
     end;

   if ((not HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.prevzato) or (HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.stolen)) then
    begin
     // pripravit funkce:
     max_func := Min(Length(hv[8]), _HV_FUNC_MAX);
     for j := 0 to max_func do
       HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.funkce[j] := (hv[8][j+1] = '1');

     try
       TrkSystem.PrevzitLoko(HVDb.HVozidla[Self.data.HV.HVs[i]]);
     except
       on E:Exception do
         raise Exception.Create('PrevzitLoko exception : '+E.Message);
     end;

     timeout := 0;
     while (not HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.prevzato_full) do
      begin
       Sleep(1);
       timeout := timeout + 1;
       Application.ProcessMessages;

       if (timeout > 1000) then  //timeout 1 sec na kazde hnaci vozidlo
        begin
         raise Exception.Create('Loko '+ IntToStr(Self.data.HV.HVs[i]) +' nep�evzato');
         Exit();
        end;
      end;//while

    end else begin
     // nastavit funkce
     for j := 0 to _HV_FUNC_MAX do
       if (j < Length(hv[8])) then
         Func[j] := (hv[8][j+1] = '1')
       else
         Func[j] := HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.funkce[j];

     TrkSystem.LokSetFunc(Self, HVDb.HVozidla[Self.data.HV.HVs[i]], Func);
    end;

   HVDb.HVozidla[Self.data.HV.HVs[i]].Data.Poznamka := hv[3];
   HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA := THVStanoviste(StrToInt(hv[7]));
   HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.souprava := Self.index;
  end;

 Self.UvolV(old, Self.data.HV);

 if ((Self.rychlost = 0) and (Self.data.smer_L xor Self.data.smer_S)) then
  begin
    // vypocet smeru ze sipky
    if (Self.data.smer_L) then
      smer := THVStanoviste.lichy
    else
      smer := THVStanoviste.sudy;
  end else
    smer := Self.smer;

 Self.SetRychlostSmer(Self.rychlost, smer);

 hvs.Free();
 hv.Free();

 Blky.ChangeSprToTrat(Self.index);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.UpdateSprFromPanel(spr:TStrings; Usek:TObject; OblR:TObject);
var nav:TBlk;
begin
 Self.LoadFromPanelStr(spr, Usek, OblR);
 (Usek as TBlkUsek).Change();

 for nav in (Usek as TBlkUsek).SComJCRef do
   (nav as TBlkScom).UpdateRychlostSpr(true);

 Self.changed := true;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

class procedure TSouprava.UvolV(old:TSoupravaHV; new:TSoupravaHV);
var i, j:Integer;
    old_marked:array [0.._MAX_SPR_HV] of boolean;
begin
 for i := 0 to _MAX_SPR_HV-1 do
  old_marked[i] := false;

 for i := 0 to new.cnt-1 do
   for j := 0 to old.cnt-1 do
     if (new.HVs[i] = old.HVs[j]) then
      old_marked[j] := true;

 for i := 0 to old.cnt-1 do
  begin
   if (not old_marked[i]) then
    begin
     // vozidlo, ktere neni v novem seznamu -> uvolnit
     HVDb.HVozidla[old.HVs[i]].Stav.souprava := -1;
     TrkSystem.LokSetSpeed(nil, HVDb.HVozidla[old.HVs[i]], 0);

     if ((TrkSystem.openned) and (not HVDb.HVozidla[old.HVs[i]].ruc) and
         (HVDb.HVozidla[old.HVs[i]].Stav.regulators.Count = 0) and (not RegCollector.IsLoko(HVDb.HVozidla[old.HVs[i]]))) then
      begin
       try
         TrkSystem.OdhlasitLoko(HVDb.HVozidla[old.HVs[i]]);
       except

       end;
      end;
    end;
  end;

end;//procedure

////////////////////////////////////////////////////////////////////////////////

// uvolnit vsechna loko
// pred uvolnenim loko take zastavime
procedure TSouprava.ReleaseAllLoko();
var i:Integer;
begin
 if ((not Assigned(HVDb)) or (not Assigned(TrkSystem))) then Exit();

 for i := 0 to Self.data.HV.cnt-1 do
  begin
   if (Assigned(HVDb.HVozidla[Self.data.HV.HVs[i]])) then
    begin
     HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.souprava := -1;

     if ((TrkSystem.openned) and (not HVDb.HVozidla[Self.data.HV.HVs[i]].ruc)) then
      begin
       // lokomotivu fyzicky odhlasujeme jen pokud jsme pripojeni k centrale
       TrkSystem.LokSetDirectSpeed(Self, HVDb.HVozidla[Self.data.HV.HVs[i]], 0);
       if ((HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.regulators.Count = 0) and
          (not RegCollector.IsLoko(HVDb.HVozidla[Self.data.HV.HVs[i]]))) then
        begin
         try
           TrkSystem.OdhlasitLoko(HVDb.HVozidla[Self.data.HV.HVs[i]]);
         except

         end;
        end;
      end;
    end;
  end;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.SetOR(OblRizeni:TObject);
var i:Integer;
begin
 Self.data.OblRizeni := OblRizeni;
 for i := 0 to Self.data.HV.cnt-1 do
   HVDb.HVozidla[Self.data.HV.HVs[i]].PredejStanici(OblRizeni as TOR);
 Self.Data.hlaseniPrehrano := false;
 Self.changed := true;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.SetRychlostSmer(speed:Integer; dir:THVStanoviste);
var i:Integer;
    smer:Integer;
begin
 if ((TBlk(Self.front).typ = _BLK_TU) and (TBlkTU(Self.front).rychUpdate)) then
   TBlkTU(Self.front).rychUpdate := false;

 Self.data.smer := dir;
 if (Self.speedBuffer = nil) then
   Self.data.rychlost := speed
 else begin
   Self.speedBuffer^ := speed;
   Exit();
 end;

 for i := 0 to Self.data.HV.cnt-1 do
  begin
   if (not HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.prevzato) then continue;
   
   if (HVDb.HVozidla[Self.data.HV.HVs[i]].ruc) then
    begin      // pokud je loko prevzato na rucni rizeni, ignoruji ho
      writelog('LOKO ' + IntToStr(Self.data.HV.HVs[i]) + ' v ru�n�m regul�toru, nenastavuji rychlost', WR_MESSAGE, 0);
      continue;
    end;

   TrkSystem.callback_err := TTrakce.GenerateCallback(Self.HVComErr);
   smer := (Integer(dir) xor Integer(HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA));

   if (not HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.stolen) then
     TrkSystem.LokSetSpeed(Self, HVDb.HVozidla[Self.data.HV.HVs[i]], speed, smer)
   else
    writelog('LOKO ' + IntToStr(Self.data.HV.HVs[i]) + ' ukradena, nenastavuji rychlost', WR_MESSAGE, 0);
  end;

 if ((speed > 0) and (Assigned(Self.front)) and
     ((Self.front as TBlkUsek).IsVlakPresun()) and
      ((Self.front as TBlkUsek).Soupravs[(Self.front as TBlkUsek).vlakPresun] = Self.index)) then
  (Self.front as TBlkUsek).VlakPresun := -1;

 writelog('Souprava ' + Self.nazev + ' : rychlost '+IntToStr(speed)+', sm�r : '+IntToStr(Integer(dir)), WR_MESSAGE, 0);

 Self.changed := true;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.SetSpeed(speed:Integer);
begin
 Self.SetRychlostSmer(speed, Self.data.smer);
end;//procedure

procedure TSouprava.SetSmer(smer:THVStanoviste);
begin
 Self.SetRychlostSmer(Self.data.rychlost, smer);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.HVComErr(Sender:TObject; Data:Pointer);
begin
 if (Self.data.OblRizeni <> nil) then
   (Self.data.OblRizeni as TOR).BlkWriteError(nil, 'Souprava '+Self.nazev+' nekomunikuje s centr�lou', 'CENTR�LA');
end;//procedure

////////////////////////////////////////////////////////////////////////////////

function TSouprava.IsUkradeno():boolean;
var i:Integer;
begin
 for i := 0 to Self.data.HV.cnt-1 do
  if (HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.stolen) then
    Exit(true);
 Result := false;
end;//function

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.VezmiVlak();
var i, timeout:Integer;
    taken:boolean;
begin
 taken := false;
 for i := 0 to Self.data.HV.cnt-1 do
  begin
   if (HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.stolen) then
    begin
     try
       TrkSystem.PrevzitLoko(HVDb.HVozidla[Self.data.HV.HVs[i]]);
     except
       on E:Exception do
         raise Exception.Create('PrevzitLoko exception : '+E.Message);
     end;
     taken := true;

     timeout := 0;
     while (not HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.Prevzato) do
      begin
       Sleep(1);
       timeout := timeout + 1;
       Application.ProcessMessages;

       if (timeout > 1000) then  //timeout 1 sec
        begin
         raise Exception.Create('Loko '+ IntToStr(Self.data.HV.HVs[i]) +' nep�evzato');
         Exit();
        end;
      end;//while
    end;//stolen
  end;//for i

 if (taken) then
   Self.SetRychlostSmer(Self.rychlost, Self.smer);
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.SetFront(front:TObject);
var i:Integer;
begin
 if (Self.data.front = front) then Exit();

 if (Assigned(Self.data.front)) then
   (Self.data.front as TBlkUsek).zpomalovani_ready := false;
 Self.data.front := front;

 // pricteme delku tohoto useku k front:
 for i := 0 to Self.data.HV.cnt-1 do
  begin
   case (HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.smer) of
    0 : begin
      HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vpred.Metru := HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vpred.Metru + (front as TBlkUsek).GetSettings().Lenght/100;
      Inc(HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vpred.Bloku);
    end;
    1 : begin
      HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vzad.Metru := HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vzad.Metru + (front as TBlkUsek).GetSettings().Lenght/100;
      Inc(HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.najeto_vzad.Bloku);
    end;//case 1
   end;//case

   HVDb.HVozidla[Self.data.HV.HVs[i]].changed := true;
  end;//for

 Self.changed := true;
end;//procedure

procedure TSouprava.UpdateFront();
var blk:TBlk;
begin
 Blky.GetBlkByID(Self.filefront, blk);
 Self.front := blk;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

// zmena smeru pri naslapu na smyckovy blok
procedure TSouprava.ChangeSmer();
var i:Integer;
    tmp:boolean;
begin
 // zmenit orintaci stanoviste A hnacich vozidel
 for i := 0 to Self.data.HV.cnt-1 do
  begin
   case (HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA) of
    THVStanoviste.lichy : HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA := THVStanoviste.sudy;
    THVStanoviste.sudy  : HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA := THVStanoviste.lichy;
   end;//case
  end;//for i

 // zmenit orientaci sipky soupravy
 tmp              := Self.data.smer_L;
 Self.data.smer_L := Self.data.smer_S;
 Self.data.smer_S := tmp;

 // zmenit smer suupravy - dulezite pro zastaveni pred navestidlem
 case (Self.data.smer) of
  THVStanoviste.lichy : Self.smer := THVStanoviste.sudy;
  THVStanoviste.sudy  : Self.smer := THVStanoviste.lichy;
 end;//case

 writelog('Souprava '+ Self.nazev + ' : zmena smeru', WR_SPRPREDAT);

 if (Self.front <> nil) then
   (Self.front as TBlkUsek).Change();  // kvuli sipce
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.InterChangeStanice(change_ev:Boolean = true);
var tmp:TObject;
begin
 tmp := Self.data.vychoziOR;
 Self.data.vychoziOR := Self.data.cilovaOR;
 Self.data.cilovaOR := tmp;

 Self.changed := true;
 if ((Self.front <> nil) and (change_ev)) then
   (Self.front as TBlkUsek).Change();
end;

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.SetSpeedBuffer(speedBuffer:PInteger);
begin
 Self.speedBuffer := speedBuffer;
end;

////////////////////////////////////////////////////////////////////////////////
// V pripade, ze vsechna hnaci vozidla soupravy otocim do opacneho smeru,
// nez je smer soupravy, otoci se i smer soupravy. To umoznuje otoceni smeru
// soupravy z Rocomaus.
// Tato zmena je umoznena jen tehdy pokud nema sipka jednoznacne urceny smer
// a pokud souprava stoji.

procedure TSouprava.LokDirChanged();
var i:Integer;
    dir:Integer;
begin
 if ((Self.rychlost <> 0) or (Self.data.smer_L xor Self.data.smer_S) or
     (Self.data.HV.cnt = 0) or ((Self.front <> nil) and (not TBlkUsek(Self.front).Stav.stanicni_kolej))) then
   Exit();

 dir := HVDb.HVozidla[Self.data.HV.HVs[0]].Slot.smer xor
        Integer(HVDb.HVozidla[Self.data.HV.HVs[0]].Stav.StanovisteA);

 if (dir = Integer(Self.smer)) then Exit();
 for i := 1 to Self.data.HV.cnt-1 do
   if (dir <> (HVDb.HVozidla[Self.data.HV.HVs[i]].Slot.smer xor
              Integer(HVDb.HVozidla[Self.data.HV.HVs[i]].Stav.StanovisteA))) then
     Exit();

 // vsechna hv nastavena do opacneho smeru -> zmenit smer soupravy
 Self.smer := THVStanoviste(dir);
end;

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.ToggleHouk(desc:string);
var i:Integer;
    HV:THV;
begin
 writelog('Souprava ' + Self.nazev + ' : aktivuji houk�n� ' + desc, WR_MESSAGE, 0);

 for i := 0 to Self.sdata.HV.cnt-1 do
  begin
   HV := HVDb.HVozidla[Self.sdata.HV.HVs[i]];
   if (HV.CanPlayHouk(desc)) then
     TrkSystem.LokFuncToggle(Self, HV, HV.funcDict[desc]);
  end;
end;

procedure TSouprava.SetHoukState(desc:string; state:boolean);
var i:Integer;
    HV:THV;
    func:TFunkce;
begin
 if (state) then
   writelog('Souprava ' + Self.nazev + ' : aktivuji funkci ' + desc, WR_MESSAGE, 0)
 else
   writelog('Souprava ' + Self.nazev + ' : deaktivuji funkci ' + desc, WR_MESSAGE, 0);

 for i := 0 to Self.sdata.HV.cnt-1 do
  begin
   HV := HVDb.HVozidla[Self.sdata.HV.HVs[i]];

   if (HV.CanPlayHouk(desc)) then
    begin
     func := HV.Stav.funkce;
     func[HV.funcDict[desc]] := state;
     TrkSystem.LokSetFunc(Self, HV, func);
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TSouprava.CheckSH(nav:TObject);
var mnav:TBlkScom;
    oblr:TOR;
    shPlay:TSHToPlay;
    shSpr:TSHSpr;
    ok:boolean;
    i:Integer;
begin
 if ((Self.hlaseniPrehrano) or (self.vychoziOR = nil) or (self.cilovaOR = nil)
     or (self.typ = '')) then Exit();

 ok := true;
 for i := 0 to Length(stanicniHlaseni._HLASENI_SPRTYP_FORBIDDEN)-1 do
  begin
   if (Self.typ = stanicniHlaseni._HLASENI_SPRTYP_FORBIDDEN[i]) then
    begin
     ok := false;
     break;
    end;
  end;

 if (not ok) then Exit();

 mnav := TBlkSCom(nav);
 if (mnav.OblsRizeni.Cnt < 1) then Exit();
 oblr := mnav.OblsRizeni.ORs[0];

 if ((not Assigned(oblr.hlaseni)) or (not oblr.hlaseni.available)) then Exit();

 try
   shPlay := stanicniHlaseniHelper.CanPlayPrijezdSH(self, oblr);
 except
   on E:Exception do
     AppEvents.LogException(E, 'CanPlayPrijezdSH');
 end;

 shSpr.cislo := Self.nazev;
 shSpr.typ   := Self.typ;
 shSpr.fromORid := TOR(Self.vychoziOR).id;
 shSpr.toORid := TOR(Self.cilovaOR).id;
 shSpr.timeArrive := 0;
 shSpr.timeDepart := 0;

 if (shPlay.stanicniKolej <> nil) then
  begin
   shSpr.kolej := shPlay.stanicniKolej.Stav.cislo_koleje;

   if ((Self.IsPOdj(shPlay.stanicniKolej)) and (Self.GetPOdj(shPlay.stanicniKolej).abs_enabled)) then
     shSpr.timeDepart := Self.GetPOdj(shPlay.stanicniKolej).abs;
  end;

 try
   if ((shPlay.stanicniKolej <> nil) and ((shPlay.trat = nil) or (Self.IsPOdj(shPlay.stanicniKolej)))) then begin
     oblr.hlaseni.Prijede(shSpr);
     Self.data.hlaseniPrehrano := true;
   end else if (shPlay.trat <> nil) then begin
     oblr.hlaseni.Projede(shSpr);
     Self.data.hlaseniPrehrano := true;
   end;
 except
   on E:Exception do
     AppEvents.LogException(E, 'Prehravani hlaseni');
 end;
end;

////////////////////////////////////////////////////////////////////////////////
// Predvidane odjezdy:

procedure TSouprava.AddOrUpdatePOdj(usekid:Integer; var podj:TPOdj);
begin
 if ((not podj.rel_enabled) and (not podj.abs_enabled)) then
  begin
   if (Self.data.podj.ContainsKey(usekid)) then
    begin
     Self.data.podj[usekid].Free();
     Self.data.podj.Remove(usekid);
    end;
   FreeAndNil(podj);
  end else begin
   if (Self.data.podj.ContainsKey(usekid)) then
     Self.data.podj[usekid].Free();
   Self.data.podj.AddOrSetValue(usekid, podj);
   podj := nil;
  end;
end;

function TSouprava.IsPOdj(usekid:Integer):Boolean;
begin
 Result := Self.data.podj.ContainsKey(usekid);
end;

function TSouprava.GetPOdj(usekid:Integer):TPOdj;
begin
 Result := Self.data.podj[usekid];
end;

procedure TSouprava.RemovePOdj(usekid:Integer);
begin
 Self.data.podj[usekid].Free();
 Self.data.podj.Remove(usekid);
end;

procedure TSouprava.AddOrUpdatePOdj(usek:TBlk; var podj:TPOdj);
begin
 Self.AddOrUpdatePOdj(usek.id, podj);
end;

function TSouprava.IsPOdj(usek:TBlk):Boolean;
begin
 Result := Self.IsPOdj(usek.id);
end;

function TSouprava.GetPOdj(usek:TBlk):TPOdj;
begin
 Result := Self.GetPOdj(usek.id);
end;

procedure TSouprava.RemovePOdj(usek:TBlk);
begin
 Self.RemovePOdj(usek.id);
end;

procedure TSouprava.ClearPOdj();
var podj:TPOdj;
begin
 for podj in Self.data.podj.Values do
   podj.Free();

 Self.data.podj.Clear();
end;

////////////////////////////////////////////////////////////////////////////////

end.//unit
