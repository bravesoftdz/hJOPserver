unit Verze;

interface

uses Windows, SysUtils, Forms, jclPEImage;

 function NactiVerzi(const FileName: string): string;//cteni verze z nastaveni
 function GetLastBuildDate:string;
 function GetLastBuildTime:string;
 function ZkontrolujSpusteno:Boolean;

var runningMsg:Cardinal;
    Mutex:THandle;

implementation

function NactiVerzi(const FileName: string): string;//cteni verze z nastaveni
var
  size, len: longword;
  handle: THandle;
  buffer: pchar;
  pinfo: ^VS_FIXEDFILEINFO;
  Major, Minor, Release: word;
begin
  Result:='Nen� dostupn�';
  size := GetFileVersionInfoSize(Pointer(FileName), handle);
  if size > 0 then begin
    GetMem(buffer, size);
    if GetFileVersionInfo(Pointer(FileName), 0, size, buffer)
    then
      if VerQueryValue(buffer, '\', pointer(pinfo), len) then begin
        Major   := HiWord(pinfo.dwFileVersionMS);
        Minor   := LoWord(pinfo.dwFileVersionMS);
        Release := HiWord(pinfo.dwFileVersionLS);
        Result := Format('%d.%d.%d',[Major, Minor, Release]);
      end;
    FreeMem(buffer);
  end;
end;
 
function GetLastBuildDate():String;
 begin
  DateTimeToString(Result, 'dd.mm.yyyy', jclPEImage.PeReadLinkerTimeStamp(Application.ExeName));
 end;//function

function GetLastBuildTime():String;
 begin
  DateTimeToString(Result, 'hh:mm:ss', jclPEImage.PeReadLinkerTimeStamp(Application.ExeName));
 end;//function

function ZkontrolujSpusteno:Boolean;
 begin
  Mutex := CreateMutex(nil, True, 'Ridici_program');
  runningMsg := RegisterWindowMessage('RPSpusten');
  if ((Mutex = 0) OR (GetLastError = ERROR_ALREADY_EXISTS)) then
   begin
    SendMessage(HWND_BROADCAST, runningMsg, 0, 0);
    Result := true;
   end else begin
    Result := false;
   end;
 end;//function

end.//unit
