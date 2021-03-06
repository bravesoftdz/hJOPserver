unit TBlokSouctovaHlaska;

//definice a obsluha technologickeho bloku Souctova hlaska

interface

uses IniFiles, TBlok, Menus, SysUtils, Classes, IdContext, Generics.Collections,
     TOblRizeni, TCPServerOR;

type
 TBlkSHStav = record
  enabled:boolean;
 end;

 TBlkSHSettings = record
  prejezdy:TList<Integer>; // seznam id prejezdu, ktere jsou v souctove hlasce
 end;

 TBlkSH = class(TBlk)
  const
   _def_sh_stav:TBlkSHStav = (
     enabled: false;
   );

  protected
   settings:TBlkSHSettings;
   shStav:TBlkSHStav;

    function GetKomunikace():boolean;
    function GetAnulace():boolean;
    function GetUZ():boolean;
    function GetUzavreno():boolean;
    function GetPorucha():boolean;
    function GetNOT():boolean;

    procedure CreateReferences();
    procedure RemoveReferences();

  public

    constructor Create(index:Integer);
    destructor Destroy(); override;

    //load/save data
    procedure LoadData(ini_tech:TMemIniFile; const section:string;
                       ini_rel,ini_stat:TMemIniFile); override;
    procedure SaveData(ini_tech:TMemIniFile; const section:string); override;

    procedure Enable(); override;
    procedure Disable(); override;

    function GetSettings():TBlkSHSettings;
    procedure SetSettings(data:TBlkSHSettings);

    //----- souctova hlaska own functions -----

    property stav:TBlkSHStav read shStav;
    property enabled:boolean read shStav.enabled;

    property komunikace:boolean read GetKomunikace;
    property anulace:boolean read GetAnulace;
    property UZ:boolean read GetUZ;
    property uzavreno:boolean read GetUzavreno;
    property porucha:boolean read GetPorucha;
    property nouzoveOT:boolean read GetNOT;

    //GUI:
    procedure PanelMenuClick(SenderPnl:TIdContext; SenderOR:TObject;
                             item:string; itemindex:Integer); override;
    function ShowPanelMenu(SenderPnl:TIdContext; SenderOR:TObject;
                           rights:TORCOntrolRights):string; override;
    procedure PanelClick(SenderPnl:TIdContext; SenderOR:TObject;
                         Button:TPanelButton; rights:TORCOntrolRights;
                         params:string = ''); override;
 end;//class TBlkUsek

////////////////////////////////////////////////////////////////////////////////

implementation

uses TBlokPrejezd, TBloky, TOblsRizeni;

constructor TBlkSH.Create(index:Integer);
begin
 inherited;

 Self.shStav := Self._def_sh_stav;
 Self.settings.prejezdy := TList<Integer>.Create();
 Self.GlobalSettings.typ := _BLK_SH;
end;

destructor TBlkSH.Destroy();
begin
 Self.settings.prejezdy.Free();
 inherited;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkSH.LoadData(ini_tech:TMemIniFile; const section:string;
                          ini_rel, ini_stat:TMemIniFile);
var data:TStrings;
    str:string;
begin
 inherited LoadData(ini_tech, section, ini_rel, ini_stat);

 Self.settings.prejezdy.Clear();
 data := TStringList.Create();
 try
   ExtractStrings([','], [], PChar(ini_tech.ReadString(section, 'prejezdy', '')), data);

   for str in data do
     Self.settings.prejezdy.Add(StrToInt(str));

   if (ini_rel <> nil) then
    begin
     //parsing *.spnl
     data.Clear();
     ExtractStrings([';'], [], PChar(ini_rel.ReadString('T', IntToStr(Self.GlobalSettings.id), '')), data);
     if (data.Count > 0) then
       Self.ORsRef := ORs.ParseORs(data[0]);
    end else begin
     Self.ORsRef.Cnt := 0;
    end;
 finally
   data.Free();
 end;
end;

procedure TBlkSH.SaveData(ini_tech:TMemIniFile; const section:string);
var str:string;
    n:Integer;
begin
 inherited;

 str := '';
 for n in Self.settings.prejezdy do
   str := str + IntToStr(n) + ',';

 if (str <> '') then
   ini_tech.WriteString(section, 'prejezdy', str);
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkSH.Enable();
begin
 Self.shStav.enabled := true;
 Self.CreateReferences();
end;

procedure TBlkSH.Disable();
begin
 Self.shStav.enabled := false;
end;

////////////////////////////////////////////////////////////////////////////////

function TBlkSH.GetSettings():TBlkSHSettings;
begin
 Result := Self.settings;
end;

procedure TBlkSH.SetSettings(data:TBlkSHSettings);
begin
 if (Self.enabled) then
   Self.RemoveReferences();
 Self.settings.prejezdy.Free();

 Self.settings := data;

 if (Self.enabled) then
   Self.CreateReferences();

 Self.Change();
end;

////////////////////////////////////////////////////////////////////////////////

//vytvoreni menu pro potreby konkretniho bloku:
function TBlkSH.ShowPanelMenu(SenderPnl:TIdContext; SenderOR:TObject;
                              rights:TORCOntrolRights):string;
var prjid:Integer;
    prj:TBlk;
begin
 Result := inherited;

 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     Result := Result + prj.name + ','
   else
     Result := Result + '#???,';
  end;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkSH.PanelClick(SenderPnl:TIdContext; SenderOR:TObject;
                            Button:TPanelButton; rights:TORCOntrolRights;
                            params:string = '');
begin
 ORTCPServer.Menu(SenderPnl, Self, (SenderOR as TOR),
                  Self.ShowPanelMenu(SenderPnl, SenderOR, rights));
end;

////////////////////////////////////////////////////////////////////////////////

//toto se zavola pri kliku na jakoukoliv itemu menu tohoto bloku
procedure TBlkSH.PanelMenuClick(SenderPnl:TIdContext; SenderOR:TObject;
                                item:string; itemindex:Integer);
var prj:TBlk;
begin
 if (not Self.enabled) then Exit();

 if ((itemindex-2 >= 0) and (itemindex-2 < Self.settings.prejezdy.Count)) then
  begin
   Blky.GetBlkByID(Self.settings.prejezdy[itemindex-2], prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     ORTCPServer.Menu(SenderPnl, prj, SenderOR as TOR,
                      prj.ShowPanelMenu(SenderPnl, SenderOR, TORControlRights.write));
  end;
end;

////////////////////////////////////////////////////////////////////////////////

function TBlkSH.GetKomunikace():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := true;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
    begin
     if (TBlkPrejezd(prj).Stav.basicStav = TBlkPrjBasicStav.disabled) then
       Exit(false);
    end else Exit(false);
  end;
end;

function TBlkSH.GetAnulace():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := false;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     if (TBlkPrejezd(prj).Stav.basicStav = TBlkPrjBasicStav.anulace) then
       Exit(true);
  end;
end;

function TBlkSH.GetUZ():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := false;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     if (TBlkPrejezd(prj).UZ) then
       Exit(true);
  end;
end;

function TBlkSH.GetUzavreno():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := false;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     if (TBlkPrejezd(prj).Stav.basicStav = TBlkPrjBasicStav.uzavreno) then
       Exit(true);
  end;
end;

function TBlkSH.GetPorucha():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := false;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     if (TBlkPrejezd(prj).Stav.basicStav = TBlkPrjBasicStav.none) then
       Exit(true);
  end;
end;

function TBlkSH.GetNOT():boolean;
var prjid:Integer;
    prj:TBlk;
begin
 Result := false;
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     if (TBlkPrejezd(prj).NOtevreni) then
       Exit(true);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TBlkSH.CreateReferences();
var prjid:Integer;
    prj:TBlk;
begin
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     TBlkPrejezd(prj).AddSH(Self);
  end;
end;

procedure TBlkSH.RemoveReferences();
var prjid:Integer;
    prj:TBlk;
begin
 for prjid in Self.settings.prejezdy do
  begin
   Blky.GetBlkByID(prjid, prj);
   if ((prj <> nil) and (prj.typ = _BLK_PREJEZD)) then
     TBlkPrejezd(prj).RemoveSH(Self);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

end.//unit

