unit fSystemAutoStart;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TF_AutoStartSystems = class(TForm)
    B_Abort: TButton;
    L_Systems1: TLabel;
    L_Systems2: TLabel;
    L_Cas: TLabel;
    L_Systems3: TLabel;
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure B_AbortClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  F_AutoStartSystems: TF_AutoStartSystems;

implementation

uses fLoginPozadi, fMain, Logging;

{$R *.dfm}

procedure TF_AutoStartSystems.FormShow(Sender: TObject);
 begin
  F_Pozadi.OpenForm(false);
  F_AutoStartSystems.Show;
 end;//procedure

procedure TF_AutoStartSystems.FormClose(Sender: TObject;
  var Action: TCloseAction);
 begin
  F_Pozadi.CloseForm;
 end;//procedure

procedure TF_AutoStartSystems.B_AbortClick(Sender: TObject);
 begin
  WriteLog('Automaticke pripojovani k systemum selhalo - vstup uzivatele',WR_MESSAGE); 
  F_Main.KomunikacePocitani := 0;
  F_AutoStartSystems.Close;
 end;//procedure

end.//unit
