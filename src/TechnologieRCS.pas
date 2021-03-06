unit TechnologieRCS;

{
 Technologie RCS: rozhrani pro pouzivani Railroad Control System.

 RCS je obecny nazev pro sbernici resici rizeni prislusenstvi, napriklad MTB,
 touto sbernici ale muze byt klidne i XpressNET.

 Vsechny ostatni casti programu by mely volat metody tridy TRCS, ktera interaguje
 s RCS. Trida TRCS v sobe skryva interakci s TCSIFace. Trida TRCS pomerne <= TODO: tohle neni pravda
 intenzivne interaguje s dalsimi technologickymi prvku hJOPserveru -- je tedy
 nedilnou soucasti serveru.

 Pricip:
  - na zacatku vytvorime tridy pro vsechny existujici moduly RCS
  - po otevreni RCS zjistime, ktere desky jsou skutecne dostupne a ktere ne
}

interface

uses SysUtils, Classes, IniFiles, Generics.Collections, RCS;

type
  TErrEvent = procedure(Sender:TObject; errValue: word; errAddr: byte; errMsg:string) of object;
  TRCSReadyEvent = procedure (Sender:TObject; ready:boolean) of object;
  TRCSBoardChangeEvent = procedure (Sender:TObject; board:byte) of object;

  //////////////////////////////////////////////////////////////

  //toto se pouziva pro identifikaci desky a portu VSUDE v technologii
  TRCSAddr = record                                                             // jedno fyzicke RCS spojeni
   board:Byte;                                                                    // cislo desky
   port:Byte;                                                                     // cislo portu
  end;

  TRCSBoard = class                                                               // jedna RCS deska
    needed:boolean;                                                               // jestli jed eska potrebna pro technologii (tj. jeslti na ni referuji nejake bloky atp.)
    inputChangedEv:TList<TRCSBoardChangeEvent>;
    outputChangedEv:TList<TRCSBoardChangeEvent>;

    constructor Create();
    destructor Destroy(); override;
  end;

  //////////////////////////////////////////////////////////////

  // Technologie RCS
  TRCS = class(TRCSIFace)
   public const
     _MAX_RCS = 192;                                        // maximalni pocet RCS desek

   private const
     _DEFAULT_LIB = 'simulator.dll';
     _INIFILE_SECTNAME = 'RCS';

   private
     Desky:array [0.._MAX_RCS-1] of TRCSBoard;              // RCS desky, pole je indexovano RCS adresami

     aReady:boolean;                                        // jestli je nactena knihovna vporadku a tudiz jestli lze zapnout systemy

     fGeneralError:boolean;                                 // flag oznamujici nastani "RCS general IO error" -- te nejhorsi veci na svete
     fLibDir:string;

     //events to the main program
     fOnReady : TRCSReadyEvent;
     fAfterClose : TNotifyEvent;

      //events from libraly
      procedure DllAfterClose(Sender:TObject);

      procedure DllOnError(Sender: TObject; errValue: word; errAddr: byte; errMsg:PChar);
      procedure DllOnInputChanged(Sender:TObject; module:byte);
      procedure DllOnOutputChanged(Sender:TObject; module:byte);

   public
      constructor Create();
      destructor Destroy; override;

      procedure LoadLib(filename:string);                                       // nacte knihovnu

      procedure InputSim();                                                     // pokud je nactena knihovna Simulator.dll, simuluje vstupy (koncove polohy vyhybek atp.)
      procedure SoupravaUsekSim();                                              // nastavit RCS vstupy tak, aby useky, n akterych existuje souprava, byly obsazene

      function NoExStarted():boolean;
      function NoExOpened():boolean;

      procedure SetNeeded(RCSAdr:Integer; state:boolean = true);
      function GetNeeded(RCSAdr:Integer):boolean;

      procedure LoadFromFile(ini:TMemIniFile);
      procedure SaveToFile(ini:TMemIniFile);

      procedure AddInputChangeEvent(board:Integer; event:TRCSBoardChangeEvent);
      procedure RemoveInputChangeEvent(event:TRCSBoardChangeEvent; board:Integer = -1);

      procedure AddOutputChangeEvent(board:Integer; event:TRCSBoardChangeEvent);
      procedure RemoveOutputChangeEvent(event:TRCSBoardChangeEvent; board:Integer = -1);

      function IsSimulatorMode():boolean;

      property generalError:boolean read fGeneralError;

      //events
      property AfterClose:TNotifyEvent read fAfterClose write fAfterClose;

      property OnReady:TRCSReadyEvent read fOnReady write fOnReady;
      property ready:boolean read aready;
      property libDir:string read fLibDir;
  end;

var
  RCSi:TRCS;


implementation

uses fMain, fAdminForm, GetSystems, TBloky, TBlok, TBlokVyhybka, TBlokUsek,
     TBlokIR, TBlokSCom, BoosterDb, TBlokPrejezd, RCSErrors, TOblsRizeni,
     Logging, TCPServerOR, SprDb, DataRCS, appEv, Booster, StrUtils;

constructor TRCS.Create();
var i:Integer;
begin
 inherited;

 for i := 0 to _MAX_RCS-1 do
   Self.Desky[i] := TRCSBoard.Create();

 Self.aReady := false;
 Self.fGeneralError := false;

 //assign events
 TRCSIFace(Self).AfterClose := Self.DllAfterClose;
 TRCSIFace(Self).OnError    := Self.DllOnError;
 TRCSIFace(Self).OnInputChanged  := Self.DllOnInputChanged;
 TRCSIFace(Self).OnOutputChanged := Self.DllOnOutputChanged;
end;

destructor TRCS.Destroy();
var i:Integer;
begin
 for i := 0 to _MAX_RCS-1 do
   if (Assigned(Self.Desky[i])) then FreeAndNil(Self.Desky[i]);

 inherited;
end;

procedure TRCS.LoadLib(filename:string);
var str, tmp, libName:string;
begin
 libName := ExtractFileName(filename);

 if (not FileExists(filename)) then
   raise Exception.Create('Library file not found, not loading');

 if (Self.ready) then
  begin
   Self.aReady := false;
   if (Assigned(Self.OnReady)) then Self.OnReady(Self, Self.aReady);
  end;

 TRCSIFace(Self).LoadLib(filename);

 writelog('Na�tena knihovna '+ libName, WR_RCS);

 // kontrola bindnuti vsech eventu

 // bind SetInput neni striktne vyzadovan
 if (Self.unbound.Contains('SetInput')) then
   Self.unbound.Remove('SetInput');

 if (Self.unbound.Count = 0) then
  begin
   Self.aReady := true;
   if (Assigned(Self.OnReady)) then Self.OnReady(Self, Self.aReady);
  end else begin
   str := '';
   for tmp in Self.unbound do
     str := str + tmp + ', ';
   str := LeftStr(str, Length(str)-2);
   F_Main.LogStatus('ERR: RCS: nepoda�ilo se sv�zat n�sleduj�c� funkce : ' + str);
  end;
end;

procedure TRCS.InputSim();
var i:integer;
    Blk:TBlk;
    booster:TBooster;
begin
 //nastaveni vyhybek do +
 for i := 0 to Blky.Cnt-1 do
  begin
   Blky.GetBlkByIndex(i, Blk);
   if (Blk.GetGlobalSettings.typ = _BLK_VYH) then
     Self.SetInput((Blk as TBlkVyhybka).GetSettings().RCSAddrs.data[0].board, (Blk as TBlkVyhybka).GetSettings().RCSAddrs.data[0].port,1);
   if (Blk.typ = _BLK_PREJEZD) then
     Self.SetInput((Blk as TBlkPrejezd).GetSettings().MTB, (Blk as TBlkPrejezd).GetSettings().MTBInputs.Otevreno, 1);
   if ((F_Admin.CHB_SimSoupravaUsek.Checked) and ((Blk.typ = _BLK_USEK) or (Blk.typ = _BLK_TU)) and ((Blk as TBlkUsek).IsSouprava())) then
     Self.SetInput((Blk as TBlkUsek).GetSettings().RCSAddrs.data[0].board, (Blk as TBlkUsek).GetSettings().RCSAddrs.data[0].port, 1);
  end;//for cyklus

 //defaultni stav zesilovacu
 for booster in Boosters.sorted do
  begin
   Self.SetInput(booster.bSettings.MTB.Napajeni.board, booster.bSettings.MTB.Napajeni.port, 0);
   Self.SetInput(booster.bSettings.MTB.Zkrat.board, booster.bSettings.MTB.Zkrat.port, 0);
  end;
end;//procedure

//simulace obaszeni useku, na kterem je souprava
procedure TRCS.SoupravaUsekSim;
var i:Integer;
    Blk:TBlk;
begin
 for i := 0 to Blky.Cnt-1 do
  begin
   Blky.GetBlkByIndex(i,Blk);
   if ((Blk.typ <> _BLK_USEK) and (Blk.typ <> _BLK_TU)) then continue;
   if ((Blk as TBlkUsek).IsSouprava()) then
     Self.SetInput((Blk as TBlkUsek).GetSettings().RCSAddrs.data[0].board,(Blk as TBlkUsek).GetSettings().RCSAddrs.data[0].port,1);
  end;
end;

procedure TRCS.LoadFromFile(ini:TMemIniFile);
var lib:string;
begin
  fLibDir := ini.ReadString(_INIFILE_SECTNAME, 'dir', '.');
  lib := ini.ReadString(_INIFILE_SECTNAME, 'lib', _DEFAULT_LIB);

  try
    Self.LoadLib(fLibDir + '\' + lib);
  except
    on E:Exception do
      writeLog('Nelze na��st knihovnu ' + fLibDir + '\' + lib + ', ' + E.Message, WR_ERROR);
  end;
end;

procedure TRCS.SaveToFile(ini:TMemIniFile);
begin
  if (Self.Lib <> '') then
    ini.WriteString(_INIFILE_SECTNAME, 'lib', ExtractFileName(Self.Lib));
end;

procedure TRCS.DllAfterClose(Sender:TObject);
begin
 Self.fGeneralError := false;
 if (Assigned(Self.fAfterClose)) then Self.fAfterClose(Self);
end;//procdure

procedure TRCS.DllOnError(Sender: TObject; errValue: word; errAddr: byte; errMsg:PChar);
begin
 writelog('RCS ERR: '+errMsg+' ('+IntToStr(errValue)+':'+IntToStr(errAddr)+')', WR_RCS, 1);

 if (errAddr = 255) then
  begin
   //errors on main board (MTB-USB)
   case (errValue) of
    RCS_FT_EXCEPTION: begin
      // general IO error
      F_Main.A_System_Start.Enabled := true;
      F_Main.A_System_Stop.Enabled  := true;
      writelog('RCS FTDI Error - '+IntToStr(errValue), WR_ERROR, 0);
      ORTCPServer.BroadcastBottomError('RCS FTDI error', 'TECHNOLOGIE');
    end;
   end;//case
  end else begin
   // errors on RCS boards
   case (errValue) of
    RCS_MODULE_FAIL: ORs.MTBFail(errAddr); // communication with module failed
    RCS_MODULE_RESTORED:; // communication with module restored, nothing should be here
   end;
  end;//
end;//procedure

procedure TRCS.DllOnInputChanged(Sender:TObject; module:byte);
var i:Integer;
begin
 for i := Self.Desky[module].inputChangedEv.Count-1 downto 0 do
   if (Assigned(Self.Desky[module].inputChangedEv[i])) then Self.Desky[module].inputChangedEv[i](Self, module)
     else Self.Desky[module].inputChangedEv.Delete(i);
 RCSTableData.UpdateLine(module);
end;

procedure TRCS.DllOnOutputChanged(Sender:TObject; module:byte);
var i:Integer;
begin
 for i := Self.Desky[module].outputChangedEv.Count-1 downto 0 do
   if (Assigned(Self.Desky[module].outputChangedEv[i])) then Self.Desky[module].outputChangedEv[i](Self, module)
     else Self.Desky[module].outputChangedEv.Delete(i);
 RCSTableData.UpdateLine(module);
end;

//----- events from dll end -----
////////////////////////////////////////////////////////////////////////////////

procedure TRCS.SetNeeded(RCSAdr:Integer; state:boolean = true);
begin
 Self.Desky[RCSAdr].needed := state;
end;//procedure

function TRCS.GetNeeded(RCSAdr:Integer):boolean;
begin
 Result := Self.Desky[RCSAdr].needed;
end;//function

////////////////////////////////////////////////////////////////////////////////

constructor TRCSBoard.Create();
begin
 Self.inputChangedEv  := TList<TRCSBoardChangeEvent>.Create();
 Self.outputChangedEv := TList<TRCSBoardChangeEvent>.Create();
end;//ctor

destructor TRCSBoard.Destroy();
begin
 Self.inputChangedEv.Free();
 Self.outputChangedEv.Free();
end;//dtor

////////////////////////////////////////////////////////////////////////////////

procedure TRCS.AddInputChangeEvent(board:Integer; event:TRCSBoardChangeEvent);
begin
 if ((board >= 0) and (board < _MAX_RCS)) then
   if (Self.Desky[board].inputChangedEv.IndexOf(event) = -1) then Self.Desky[board].inputChangedEv.Add(event);
end;

procedure TRCS.RemoveInputChangeEvent(event:TRCSBoardChangeEvent; board:Integer = -1);
var i:Integer;
begin
 if (board = -1) then
  begin
   for i := 0 to _MAX_RCS-1 do
     Self.Desky[i].inputChangedEv.Remove(event);
  end else begin
   if ((board >= 0) and (board < _MAX_RCS)) then
     Self.Desky[board].inputChangedEv.Remove(event);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TRCS.AddOutputChangeEvent(board:Integer; event:TRCSBoardChangeEvent);
begin
 if ((board >= 0) and (board < _MAX_RCS)) then
   if (Self.Desky[board].outputChangedEv.IndexOf(event) = -1) then Self.Desky[board].outputChangedEv.Add(event);
end;

procedure TRCS.RemoveOutputChangeEvent(event:TRCSBoardChangeEvent; board:Integer = -1);
var i:Integer;
begin
 if (board = -1) then
  begin
   for i := 0 to _MAX_RCS-1 do
     Self.Desky[i].outputChangedEv.Remove(event);
  end else begin
   if ((board >= 0) and (board < _MAX_RCS)) then
     Self.Desky[board].outputChangedEv.Remove(event);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

function TRCS.NoExStarted():boolean;
begin
 try
   Result := Self.Started();
 except
   Result := false;
 end;
end;

function TRCS.NoExOpened():boolean;
begin
 try
   Result := Self.Opened();
 except
   Result := false;
 end;
end;

////////////////////////////////////////////////////////////////////////////////

function TRCS.IsSimulatorMode():boolean;
begin
 Result := (LowerCase(ExtractFileName(Self.Lib)) = 'simulator.dll');
end;

////////////////////////////////////////////////////////////////////////////////

end.//unit
