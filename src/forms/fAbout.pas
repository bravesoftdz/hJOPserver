unit fAbout;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, jpeg, ExtCtrls, StdCtrls, fMain, ShellAPI, pngimage;

type
  TF_About = class(TForm)
    ST_about1: TStaticText;
    ST_about2: TStaticText;
    ST_about3: TStaticText;
    ST_about4: TStaticText;
    ST_about5: TStaticText;
    B_OK: TButton;
    I_Horasystems: TImage;
    GB_Info: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    L_VApp: TLabel;
    L_VMTBLib: TLabel;
    L_VMTBUSB: TLabel;
    Label6: TLabel;
    L_VMTBDriver: TLabel;
    I_AppIcon: TImage;
    procedure FormShow(Sender: TObject);
    procedure B_OKClick(Sender: TObject);
    procedure ST_about5Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ST_about3Click(Sender: TObject);
    procedure B_RegistraceClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  F_About: TF_About;

implementation

uses Verze, fLoginPozadi, TechnologieRCS, Logging, appEv;

{$R *.dfm}

procedure TF_About.FormShow(Sender: TObject);
 begin
  writelog('Zobrazeno okno O programu',WR_MESSAGE);
  Self.ST_about5.Font.Color := clBlue;
  Self.ST_about3.Font.Color := clBlue;

  Self.L_VApp.Caption       := NactiVerzi(Application.ExeName)+' ('+GetLastBuildDate+' '+GetLastBuildTime+')';

  Self.L_VMTBLib.Caption    := RCSi.Lib;

  try
    Self.L_VMTBDriver.Caption := RCSi.GetDllVersion();
  except
    on E:Exception do
     begin
      Self.L_VMTBDriver.Caption := 'nelze z�skat';
      AppEvents.LogException(e, 'MTB.GetDllVersion');
     end;
  end;

  try
    if (RCSi.Opened) then
      Self.L_VMTBUSB.Caption := RCSi.GetDeviceVersion()
    else
      Self.L_VMTBUSB.Caption := 'za��zen� uzav�eno';
  except
    on E:Exception do
     begin
      Self.L_VMTBUSB.Caption := 'nelze z�skat';
      AppEvents.LogException(e, 'MTB.GetDeviceVersion');
     end;
  end;
 end;//procedure

procedure TF_About.B_OKClick(Sender: TObject);
begin
 F_About.Close;
end;

procedure TF_About.ST_about5Click(Sender: TObject);
 begin
  Screen.Cursor := crAppStart;
  ShellExecute(0,nil,PChar(ST_about5.Caption),nil,nil,0);
  Screen.Cursor := crDefault;
  ST_about5.Font.Color := clPurple;
 end;//procedure

procedure TF_About.FormClose(Sender: TObject; var Action: TCloseAction);
 begin
  writelog('Skryto okno O programu',WR_MESSAGE);
 end;//procedure

procedure TF_About.ST_about3Click(Sender: TObject);
 begin
  Screen.Cursor := crAppStart;
  ShellExecute(0,nil,PChar('mailto:'+ST_about3.Caption),nil,nil,0);
  Screen.Cursor := crDefault;
  ST_about3.Font.Color := clPurple;
 end;//procedure

procedure TF_About.B_RegistraceClick(Sender: TObject);
 begin
  F_About.Close;
 end;//procedure

end.//unit