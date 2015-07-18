unit TBlokTratUsek;

// Definice a obsluha technologickeho bloku Tratovy usek
// Tratovy usek dedi z Useku
// TU = Tratovy usek

interface

uses TBlokUsek, Classes, TBlok, IniFiles, SysUtils, IdContext, RPConst;

type
 TBlkTUZastavka = record  // zastavka na useku
  enabled:boolean;
  IR_lichy:Integer;
  IR_sudy:Integer;
  soupravy:TStrings;
  max_delka:Integer;
  delay:TTime;
 end;

 TBlkTUSettings = record
   zastavka:TBlkTUZastavka;
 end;

 TBlkTUStav = record

  zast_stopped:boolean;     // jakmile zastavim soupravu v zastavce, nastavim sem true; pokud souprava jede, je zde false
  zast_run_time:TDateTime;  // tady je ulozen cas, kdy se ma souprava ze zastavky rozjet
  zast_rych:Integer;        // tady si pamatuji, jakou rychlost mela souprava puvodne (mela by to byt tratova, toto je tu pro rozsireni zastavek nejen do trati)
  zast_enabled:boolean;     // zastavku lze z panelu zapnout a vypnout (v zakladnim stavu je zapla)
  zast_passed:boolean;      // atdy je ulozeno true, pokud souprava zastavku jiz projela
 end;


 TBlkTU = class(TBlkUsek)
  private const
   _def_tu_stav:TBlkTUStav = (
    zast_stopped : false;
    zast_enabled : true;
   );

   _def_tu_zastavka:TBlkTUZastavka = (
    enabled : false;
    IR_lichy : -1;
    IR_sudy : -1;
    soupravy : nil;
    max_delka : 0;
   );

  private
   TUSettings:TBlkTUSettings;
   fTUStav:TBlkTUStav;

   fZastIRLichy, fZastIRSudy : TBlk;

    function GetZastIRLichy():TBlk;
    function GetZastIRSudy():TBlk;

    property zastIRlichy:TBlk read GetZastIRLichy;
    property zastIRsudy:TBlk read GetZastIRSudy;
    procedure ZastUpdate();
    procedure ZastRunTrain();
    procedure ZastStopTrain();

    procedure MenuZastClick(SenderPnl:TIdContext; SenderOR:TObject; new_state:boolean);
    procedure MenuJEDLokClick(SenderPnl:TIdContext; SenderOR:TObject);

    procedure SetUsekSpr(spr:Integer);
    function GetUsekSpr:Integer;

  public
    constructor Create(index:Integer);
    destructor Destroy(); override;

    function GetSettings():TBlkTUSettings; overload;
    procedure SetSettings(data:TBlkTUSettings); overload;

    function GetUSettings():TBlkUsekSettings;
    procedure SetUSettings(data:TBlkUsekSettings);

    //load/save data
    procedure LoadData(ini_tech:TMemIniFile;const section:string;ini_rel,ini_stat:TMemIniFile); override;
    procedure SaveData(ini_tech:TMemIniFile;const section:string); override;

    procedure Update(); override;

    function ShowPanelMenu(SenderPnl:TIdContext; SenderOR:TObject; rights:TORCOntrolRights):string; override;
    procedure PanelClick(SenderPnl:TIdContext; SenderOR:TObject; Button:TPanelButton; rights:TORCOntrolRights); override;
    procedure PanelMenuClick(SenderPnl:TIdContext; SenderOR:TObject; item:string); override;

    property TUStav:TBlkTUStav read fTUStav;
    property Souprava:Integer read GetUsekSpr write SetUsekSpr;

 end;//TBlkUsek


implementation

uses SprDb, TBloky, TBlokIR, TCPServerOR, TOblRizeni;

// format dat zastavky v souboru bloku: zast=IR_lichy|IR_sudy|max_delka_soupravy|delay_time|spr1;spr2;...
//  pokud je zast prazdny string, zastavka je disabled

////////////////////////////////////////////////////////////////////////////////

constructor TBlkTU.Create(index:Integer);
begin
 inherited Create(index);

 Self.GlobalSettings.typ := _BLK_TU;
 Self.fTUStav := _def_tu_stav;

 Self.fZastIRLichy := nil;
 Self.fZastIRSUdy  := nil;
end;//ctor

destructor TBlkTU.Destroy();
begin
 Self.TUSettings.Zastavka.soupravy.Free();
 inherited Destroy();
end;//dtor

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.LoadData(ini_tech:TMemIniFile;const section:string;ini_rel,ini_stat:TMemIniFile);
var str:TStrings;
begin
 inherited LoadData(ini_tech, section, ini_rel, ini_stat);

 str := TStringList.Create();
 ExtractStrings(['|'],[], PChar(ini_tech.ReadString(section, 'zast', '')), str);

 // nacitani zastavky
 if (Assigned(Self.TUSettings.Zastavka.soupravy)) then Self.TUSettings.Zastavka.soupravy.Free();
 Self.TUSettings.Zastavka := _def_tu_zastavka;
 Self.TUSettings.Zastavka.soupravy := TStringList.Create();

 if (str.Count > 0) then
  begin
   try
    Self.TUsettings.Zastavka.enabled   := true;
    Self.TUsettings.Zastavka.IR_lichy  := StrToInt(str[0]);
    Self.TUsettings.Zastavka.IR_sudy   := StrToInt(str[1]);
    Self.TUsettings.Zastavka.max_delka := StrToInt(str[2]);
    Self.TUsettings.Zastavka.delay     := StrToTime(str[3]);
    Self.TUsettings.Zastavka.soupravy.Clear();
    ExtractStrings([';'],[],PChar(str[4]), Self.TUsettings.Zastavka.soupravy);
   except
    Self.TUsettings.Zastavka := _def_tu_zastavka;
   end;
  end;

 str.Free();
end;//procedure

procedure TBlkTU.SaveData(ini_tech:TMemIniFile;const section:string);
var str:string;
    i:Integer;
begin
 inherited SaveData(ini_tech, section);

 // ukladani zastavky
 if (Self.TUsettings.Zastavka.enabled) then
  begin
   with (Self.TUsettings.Zastavka) do
    begin
     str := IntToStr(IR_lichy) + '|' + IntToStr(IR_sudy) + '|' + IntToStr(max_delka) + '|' + TimeToStr(delay) + '|';
     for i := 0 to soupravy.Count-1 do
      str := str + soupravy[i] + ';';
    end;

   ini_tech.WriteString(section, 'zast', str);
  end else begin
   ini_tech.WriteString(section, 'zast', '');
  end;

end;//procedure

////////////////////////////////////////////////////////////////////////////////

function TBlkTU.GetSettings():TBlkTUSettings;
begin
 Result := Self.TUSettings;
end;//function

procedure TBlkTU.SetSettings(data:TBlkTUSettings);
begin
 if (Self.TUSettings.Zastavka.soupravy <> data.Zastavka.soupravy) then
  Self.TUSettings.Zastavka.soupravy.Free();

 Self.TUSettings := data;
 Self.Change();
end;

////////////////////////////////////////////////////////////////////////////////

//update all local variables
procedure TBlkTU.Update();
begin
 inherited;

 if ((Self.InTrat > -1) and (Self.Stav.Stav = TUsekStav.obsazeno) and (Self.Souprava > -1) and (Self.TUSettings.Zastavka.enabled)) then
   Self.ZastUpdate();
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.ZastUpdate();
var i:Integer;
    found:boolean;
begin
 if (not Self.TUStav.zast_stopped) then
  begin
   // cekam na obsazeni IR
   if ((not Self.TUStav.zast_enabled) or (Self.TUStav.zast_passed) or
      (Soupravy.soupravy[Self.Souprava].delka > Self.TUSettings.Zastavka.max_delka) or (Soupravy.soupravy[Self.Souprava].front <> self)) then Exit();

   // kontrola typu soupravy:
   found := false;
   for i := 0 to Self.TUSettings.Zastavka.soupravy.Count-1 do
    begin
     if (Self.TUSettings.Zastavka.soupravy[i] = Soupravy.soupravy[Self.Souprava].typ) then
      begin
       found := true;
       break;
      end;
    end;

   if (not found) then Exit();

   case (Soupravy.soupravy[Self.Souprava].smer) of
    THVSTanoviste.lichy : if ((Assigned(Self.zastIRlichy)) and ((Self.zastIRlichy as TBlkIR).Stav = TIRStav.obsazeno)) then
                              Self.ZastStopTrain();
    THVSTanoviste.sudy  : if ((Assigned(Self.zastIRsudy)) and ((Self.zastIRsudy as TBlkIR).Stav = TIRStav.obsazeno)) then
                              Self.ZastStopTrain();
   end;//case
  end else begin
   // osetreni rozjeti vlaku z nejakeho pochybneho duvodu
   //  pokud se souprava rozjede, koncim zastavku
   if (Soupravy.soupravy[Self.Souprava].rychlost <> 0) then
    begin
     Self.fTUStav.zast_stopped := false;
     Self.Change();  // change je dulezite volat kvuli menu
    end;

   // cekam na timeout na rozjeti vlaku
   if (Now > Self.TUStav.zast_run_time) then
    Self.ZastRunTrain();
  end;
end;//procedure

////////////////////////////////////////////////////////////////////////////////
// zastavky:

function TBlkTU.GetZastIRLichy():TBlk;
begin
 if (((Self.fZastIRLichy = nil) and (Self.TUSettings.Zastavka.IR_lichy <> -1)) or ((Self.fZastIRLichy <> nil) <> (Self.fZastIRLichy.GetGlobalSettings.id <> Self.TUSettings.Zastavka.IR_lichy))) then
   Blky.GetBlkByID(Self.TUSettings.Zastavka.IR_lichy, Self.fZastIRLichy);
 Result := Self.fZastIRLichy;
end;//function

function TBlkTU.GetZastIRSudy():TBlk;
begin
 if (((Self.fZastIRSudy = nil) and (Self.TUSettings.Zastavka.IR_sudy <> -1)) or ((Self.fZastIRSudy <> nil) and (Self.fZastIRSudy.GetGlobalSettings.id <> Self.TUSettings.Zastavka.IR_sudy))) then
   Blky.GetBlkByID(Self.TUSettings.Zastavka.IR_sudy, Self.fZastIRSudy);
 Result := Self.fZastIRSudy;
end;//function


////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.ZastStopTrain();
begin
 Self.fTUStav.zast_stopped  := true;
 Self.fTUStav.zast_run_time := Now+Self.TUSettings.Zastavka.delay;

 try
   Self.fTUStav.zast_rych := Soupravy.soupravy[Self.Souprava].rychlost;
   Soupravy.soupravy[Self.Souprava].rychlost := 0;
 except

 end;

 Self.Change();     // change je dulezite volat kvuli menu
end;//procedure

procedure TBlkTU.ZastRunTrain();
begin
 Self.fTUStav.zast_stopped := false;
 Self.fTUStav.zast_passed  := true;

 try
   Soupravy.soupravy[Self.Souprava].rychlost := Self.TUStav.zast_rych;
 except

 end;

 Self.Change();     // change je dulezite volat kvuli menu
end;//procedure

////////////////////////////////////////////////////////////////////////////////

function TBlkTU.ShowPanelMenu(SenderPnl:TIdContext; SenderOR:TObject; rights:TORCOntrolRights):string;
begin
 Result := inherited;

 // zastavka
 if ((Self.TUSettings.Zastavka.enabled) and (Self.InTrat > -1)) then
  begin
   Result := Result + '-,';
   if (not Self.TUStav.zast_stopped) then
    begin
     // pokud neni v zastavce zastavena souprava, lze zastavku vypinat a zapinat
     case (Self.TUStav.zast_enabled) of
      false : Result := Result + 'ZAST>,';
      true  : Result := Result + 'ZAST<,';
     end;//case
    end else begin
     // pokud v zastavce osuprava stoji, lze ji rozjet
     Result := Result + 'JE� vlak';
    end;
  end;

end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.PanelClick(SenderPnl:TIdContext; SenderOR:TObject ;Button:TPanelButton; rights:TORCOntrolRights);
begin
 if (Self.Stav.Stav <= TUsekStav.none) then Exit();

 case (Button) of
  right,F2: ORTCPServer.Menu(SenderPnl, Self, (SenderOR as TOR), Self.ShowPanelMenu(SenderPnl, SenderOR, rights));
  left    : if (not Self.MenuKCClick(SenderPnl, SenderOR)) then
              if (not Self.PresunLok(SenderPnl, SenderOR)) then
                ORTCPServer.Menu(SenderPnl, Self, (SenderOR as TOR), Self.ShowPanelMenu(SenderPnl, SenderOR, rights));
  middle  : Self.MenuVBClick(SenderPnl, SenderOR);
  F3: Self.ShowPanelSpr(SenderPnl, SenderOR, rights);
 end;
end;

////////////////////////////////////////////////////////////////////////////////

function TBlkTU.GetUSettings():TBlkUsekSettings;
begin
 Result := inherited GetSettings();
end;

procedure TBlkTU.SetUSettings(data:TBlkUsekSettings);
begin
 inherited SetSettings(data);
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.SetUsekSpr(spr:Integer);
begin
 inherited;
 if (spr = -1) then
  begin
   Self.fTUStav.zast_stopped := false;
   Self.fTUStav.zast_passed  := false;
  end;
end;

function TBlkTU.GetUsekSpr:Integer;
begin
 Result := Self.Stav.Spr;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.MenuZastClick(SenderPnl:TIdContext; SenderOR:TObject; new_state:boolean);
begin
 if (not Self.TUStav.zast_stopped) then
   Self.fTUStav.zast_enabled := new_state;
end;//procedure

procedure TBlkTU.MenuJEDLokClick(SenderPnl:TIdContext; SenderOR:TObject);
begin
 if (Self.TUStav.zast_stopped) then
   Self.ZastRunTrain();
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TBlkTU.PanelMenuClick(SenderPnl:TIdContext; SenderOR:TObject; item:string);
begin
 if (Self.Stav.Stav <= TUsekStav.none) then Exit();

 if (item = 'JE� vlak')   then Self.MenuJEDLokClick(SenderPnl, SenderOR)
 else if (item = 'ZAST>') then Self.MenuZastClick(SenderPnl, SenderOR, true)
 else if (item = 'ZAST<') then Self.MenuZastClick(SenderPnl, SenderOR, false)
 else inherited;
end;//procedure

////////////////////////////////////////////////////////////////////////////////

end.//unit