unit TechnologieMTB;

{
 Technologie MTB: rozhrani pro pouzivani MTB.

 Vsechny ostatni casti programu by mely volat metody tridy TMTB, ktera interaguje
 s MTB. Trida TMTB v sob2 skryva interakci s TCSIFace. Trida TMTB pomerne <= TODO: tohle neni pravda
 intenzivne interaguje s dalsimi technologickymi prvku hJOPserveru -- je tedy
 nedilnou soucasti serveru.

 Pricip:
  - na zacatku vytvorime tridy pro vsechna existujici MTB
  - po otevreni MTB zjistime, ktere desky jsou skutecne dostupne a ktere ne
}

interface

uses SysUtils, Classes, IniFiles, Generics.Collections, RCS;

type
  TErrEvent = procedure(Sender:TObject; errValue: word; errAddr: byte; errMsg:string) of object;
  TMTBReadyEvent = procedure (Sender:TObject; ready:boolean) of object;
  TMTBBoardChangeEvent = procedure (Sender:TObject; board:byte) of object;

  //////////////////////////////////////////////////////////////

  //toto se pouziva pro identifikaci desky a portu VSUDE v technologii
  TMTBAddr = record                                                             // jedno fyzicke MTB spojeni
   board:Byte;                                                                    // cislo desky
   port:Byte;                                                                     // cislo portu
  end;

  TMTBBoard = class                                                               // jedna MTB deska
    needed:boolean;                                                               // jestli jed eska potrebna pro technologii (tj. jeslti na ni referuji nejake bloky atp.)
    inputChangedEv:TList<TMTBBoardChangeEvent>;
    outputChangedEv:TList<TMTBBoardChangeEvent>;

    constructor Create();
    destructor Destroy(); override;
  end;

  //////////////////////////////////////////////////////////////

  // Technologie MTB
  TMTB = class(TRCSIFace)
   public const
     _MAX_MTB = 192;                                        // maximalni pocet MTB desek

   private
     Desky:array [0.._MAX_MTB-1] of TMTBBoard;              // MTB desky, pole je indexovano MTB adresami

     afilename:string;                                      // filename ke konfiguracnimu souboru
     aReady:boolean;                                        // jestli je nactena knihovna vporadku a tudiz jestli lze zapnout systemy

     fGeneralError:boolean;                                 // flag oznamujici nastani "MTB general IO error" -- te nejhorsi veci na svete

     //events to the main program
     fOnReady : TMTBReadyEvent;
     fAfterClose : TNotifyEvent;

      //events from libraly
      procedure DllAfterClose(Sender:TObject);

      procedure DllOnError(Sender: TObject; errValue: word; errAddr: byte; errMsg:PChar);
      procedure DllOnInputChanged(Sender:TObject; module:byte);
      procedure DllOnOutputChanged(Sender:TObject; module:byte);

   public
      constructor Create();
      destructor Destroy; override;

      procedure LoadLib(NewLib:string;Must:Boolean=false);                      // nacte knihovnu

      procedure InputSim();                                                     // pokud je nactena knihovna Simulator.dll, simuluje vstupy (koncove polohy vyhybek atp.)
      procedure SoupravaUsekSim();                                              // nastavit MTB vstupy tak, aby useky, n akterych existuje souprava, byly obsazene

      function NoExStarted():boolean;
      function NoExOpened():boolean;

      procedure SetNeeded(MtbAdr:Integer; state:boolean = true);
      function GetNeeded(MtbAdr:Integer):boolean;

      procedure LoadFromFile(FileName:string);
      function SaveToFile(FileName:string):Byte;

      procedure AddInputChangeEvent(board:Integer; event:TMTBBoardChangeEvent);
      procedure RemoveInputChangeEvent(event:TMTBBoardChangeEvent; board:Integer = -1);

      procedure AddOutputChangeEvent(board:Integer; event:TMTBBoardChangeEvent);
      procedure RemoveOutputChangeEvent(event:TMTBBoardChangeEvent; board:Integer = -1);

      property generalError:boolean read fGeneralError;

      //events
      property AfterClose:TNotifyEvent read fAfterClose write fAfterClose;

      property OnReady:TMTBReadyEvent read fOnReady write fOnReady;
      property ready:boolean read aready;
      property filename:string read afilename;
  end;

var
  MTB:TMTB;


implementation

uses fMain, fAdminForm, GetSystems, TBloky, TBlok, TBlokVyhybka, TBlokUsek,
     TBlokIR, TBlokSCom, BoosterDb, TBlokPrejezd, RCSErrors, TOblsRizeni,
     Logging, TCPServerOR, SprDb, DataMTB, appEv, Booster, StrUtils;

constructor TMTB.Create();
var i:Integer;
begin
 inherited;

 for i := 0 to _MAX_MTB-1 do
   Self.Desky[i] := TMTBBoard.Create();

 Self.aReady := false;
 Self.fGeneralError := false;

 //assign events
 TRCSIFace(Self).AfterClose := Self.DllAfterClose;
 TRCSIFace(Self).OnError    := Self.DllOnError;
 TRCSIFace(Self).OnInputChanged  := Self.DllOnInputChanged;
 TRCSIFace(Self).OnOutputChanged := Self.DllOnOutputChanged;
end;

destructor TMTB.Destroy();
var i:Integer;
begin
 //ulozeni lib po zavreni
 Self.SaveToFile(Self.afilename);

 for i := 0 to _MAX_MTB-1 do
   if (Assigned(Self.Desky[i])) then FreeAndNil(Self.Desky[i]);

 inherited;
end;

procedure TMTB.LoadLib(NewLib:string; Must:Boolean=false);
var str, tmp:string;
begin
 if ((NewLib <> Self.Lib) or (Must)) then
  begin
   if (not FileExists(NewLib)) then
     raise Exception.Create('Library file not found, not loading');

   if (Self.ready) then
    begin
     Self.aReady := false;
     if (Assigned(Self.OnReady)) then Self.OnReady(Self, Self.aReady);
    end;

   TRCSIFace(Self).LoadLib(NewLib);

   writelog('Na�tena knihovna '+ Self.lib, WR_MTB);

   // kontrola bindnuti vsech eventu
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
end;

procedure TMTB.InputSim();
var i:integer;
    Blk:TBlk;
    booster:TBooster;
begin
 //nastaveni vyhybek do +
 for i := 0 to Blky.Cnt-1 do
  begin
   Blky.GetBlkByIndex(i, Blk);
   if (Blk.GetGlobalSettings.typ = _BLK_VYH) then
     Self.SetInput((Blk as TBlkVyhybka).GetSettings().MTBAddrs.data[0].board, (Blk as TBlkVyhybka).GetSettings().MTBAddrs.data[0].port,1);
   if (Blk.GetGlobalSettings.typ = _BLK_PREJEZD) then
     Self.SetInput((Blk as TBlkPrejezd).GetSettings().MTB, (Blk as TBlkPrejezd).GetSettings().MTBInputs.Otevreno, 1);
   if ((F_Admin.CHB_SimSoupravaUsek.Checked) and ((Blk.GetGlobalSettings.typ = _BLK_USEK) or (Blk.GetGlobalSettings.typ = _BLK_TU)) and ((Blk as TBlkUsek).Souprava > -1)) then
     Self.SetInput((Blk as TBlkUsek).GetSettings().MTBAddrs.data[0].board, (Blk as TBlkUsek).GetSettings().MTBAddrs.data[0].port, 1);
  end;//for cyklus

 //defaultni stav zesilovacu
 for booster in Boosters.sorted do
  begin
   Self.SetInput(booster.bSettings.MTB.Napajeni.board, booster.bSettings.MTB.Napajeni.port, 0);
   Self.SetInput(booster.bSettings.MTB.Zkrat.board, booster.bSettings.MTB.Zkrat.port, 0);
  end;
end;//procedure

//simulace obaszeni useku, na kterem je souprava
procedure TMTB.SoupravaUsekSim;
var i:Integer;
    Blk:TBlk;
begin
 for i := 0 to Blky.Cnt-1 do
  begin
   Blky.GetBlkByIndex(i,Blk);
   if ((Blk.GetGlobalSettings().typ <> _BLK_USEK) and (Blk.GetGlobalSettings().typ <> _BLK_TU)) then continue;
   if ((Blk as TBlkUsek).Souprava > -1) then
     Self.SetInput((Blk as TBlkUsek).GetSettings().MTBAddrs.data[0].board,(Blk as TBlkUsek).GetSettings().MTBAddrs.data[0].port,1);
  end;
end;

procedure TMTB.LoadFromFile(FileName:string);
var ini:TMemIniFile;
    lib:string;
begin
  Self.afilename := FileName;

  ini := nil;
  try
    ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
    lib := ini.ReadString('MTB', 'lib', 'simulator.dll')
  except
    lib := 'simulator.dll';
  end;

  try
    Self.LoadLib(lib, true);
  except
    on E:Exception do
      writeLog('Nelze na��st knihovnu '+lib+', ' + E.Message, WR_ERROR);
  end;

  ini.Free();
end;

function TMTB.SaveToFile(FileName:string):Byte;
var ini:TMemIniFile;
begin
  try
    DeleteFile(FileName);
    ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
  except
    Exit(1);
  end;

  if (Self.Lib <> '') then
    ini.WriteString('MTB', 'lib', Self.Lib);

  ini.UpdateFile();
  ini.Free();

  Result := 0;
end;

procedure TMTB.DllAfterClose(Sender:TObject);
begin
 Self.fGeneralError := false;
 if (Assigned(Self.fAfterClose)) then Self.fAfterClose(Self);
end;//procdure

procedure TMTB.DllOnError(Sender: TObject; errValue: word; errAddr: byte; errMsg:PChar);
begin
 writelog('MTB ERR: '+errMsg+' ('+IntToStr(errValue)+':'+IntToStr(errAddr)+')', WR_MTB, 1);

 if (errAddr = 255) then
  begin
   //errors on main board (MTB-USB)
   case (errValue) of
    RCS_FT_EXCEPTION: begin
      // general IO error
      F_Main.A_System_Start.Enabled := true;
      F_Main.A_System_Stop.Enabled  := true;
      writelog('MTB FTDI Error - '+IntToStr(errValue), WR_ERROR, 0);
      ORTCPServer.BroadcastBottomError('MTB FTDI error', 'TECHNOLOGIE');
    end;
   end;//case
  end else begin
   // errors on MTB boards
   case (errValue) of
    RCS_MODULE_FAIL: ORs.MTBFail(errAddr); // communication with module failed
    RCS_MODULE_RESTORED:; // communication with module restored, nothing should be here
   end;
  end;//
end;//procedure

procedure TMTB.DllOnInputChanged(Sender:TObject; module:byte);
var i:Integer;
begin
 for i := Self.Desky[module].inputChangedEv.Count-1 downto 0 do
   if (Assigned(Self.Desky[module].inputChangedEv[i])) then Self.Desky[module].inputChangedEv[i](Self, module)
     else Self.Desky[module].inputChangedEv.Delete(i);
 MTBTableData.UpdateLine(module);
end;

procedure TMTB.DllOnOutputChanged(Sender:TObject; module:byte);
var i:Integer;
begin
 for i := Self.Desky[module].outputChangedEv.Count-1 downto 0 do
   if (Assigned(Self.Desky[module].outputChangedEv[i])) then Self.Desky[module].outputChangedEv[i](Self, module)
     else Self.Desky[module].outputChangedEv.Delete(i);
 MTBTableData.UpdateLine(module);
end;

//----- events from dll end -----
////////////////////////////////////////////////////////////////////////////////

procedure TMTB.SetNeeded(MtbAdr:Integer; state:boolean = true);
begin
 Self.Desky[MtbAdr].needed := state;
end;//procedure

function TMTB.GetNeeded(MtbAdr:Integer):boolean;
begin
 Result := Self.Desky[MtbAdr].needed;
end;//function

////////////////////////////////////////////////////////////////////////////////

constructor TMTBBoard.Create();
begin
 Self.inputChangedEv  := TList<TMTBBoardChangeEvent>.Create();
 Self.outputChangedEv := TList<TMTBBoardChangeEvent>.Create();
end;//ctor

destructor TMTBBoard.Destroy();
begin
 Self.inputChangedEv.Free();
 Self.outputChangedEv.Free();
end;//dtor

////////////////////////////////////////////////////////////////////////////////

procedure TMTB.AddInputChangeEvent(board:Integer; event:TMTBBoardChangeEvent);
begin
 if ((board >= 0) and (board < _MAX_MTB)) then
   if (Self.Desky[board].inputChangedEv.IndexOf(event) = -1) then Self.Desky[board].inputChangedEv.Add(event);
end;

procedure TMTB.RemoveInputChangeEvent(event:TMTBBoardChangeEvent; board:Integer = -1);
var i:Integer;
begin
 if (board = -1) then
  begin
   for i := 0 to _MAX_MTB-1 do
     Self.Desky[i].inputChangedEv.Remove(event);
  end else begin
   if ((board >= 0) and (board < _MAX_MTB)) then
     Self.Desky[board].inputChangedEv.Remove(event);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TMTB.AddOutputChangeEvent(board:Integer; event:TMTBBoardChangeEvent);
begin
 if ((board >= 0) and (board < _MAX_MTB)) then
   if (Self.Desky[board].outputChangedEv.IndexOf(event) = -1) then Self.Desky[board].outputChangedEv.Add(event);
end;

procedure TMTB.RemoveOutputChangeEvent(event:TMTBBoardChangeEvent; board:Integer = -1);
var i:Integer;
begin
 if (board = -1) then
  begin
   for i := 0 to _MAX_MTB-1 do
     Self.Desky[i].outputChangedEv.Remove(event);
  end else begin
   if ((board >= 0) and (board < _MAX_MTB)) then
     Self.Desky[board].outputChangedEv.Remove(event);
  end;
end;

////////////////////////////////////////////////////////////////////////////////

function TMTB.NoExStarted():boolean;
begin
 try
   Result := Self.Started();
 except
   Result := false;
 end;
end;

function TMTB.NoExOpened():boolean;
begin
 try
   Result := Self.Opened();
 except
   Result := false;
 end;
end;

////////////////////////////////////////////////////////////////////////////////

end.//unit
