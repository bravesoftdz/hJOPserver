unit fHoukEvsUsek;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, TBlokUsek, fhoukEvs, StdCtrls, ExtCtrls;

type
  TF_HoukEvsUsek = class(TForm)
    B_Apply: TButton;
    B_Storno: TButton;
    P_HoukL: TPanel;
    Label1: TLabel;
    P_HoukS: TPanel;
    Label2: TLabel;
    procedure B_StornoClick(Sender: TObject);
    procedure B_ApplyClick(Sender: TObject);
  private
   blk:TBlkUsek;
   formL:TF_HoukEvs;
   formS:TF_HoukEvs;

  public

     constructor Create(AOwner:TComponent); override;
     destructor Destroy(); override;

     procedure Open(Blk:TBlkUsek);

  end;

var
  F_HoukEvsUsek: TF_HoukEvsUsek;

implementation

{$R *.dfm}

////////////////////////////////////////////////////////////////////////////////

constructor TF_HoukEvsUsek.Create(AOwner:TComponent);
begin
 inherited;

 Self.blk := nil;

 formL := TF_HoukEvs.Create(nil);
 formL.Parent := Self.P_HoukL;
 formL.Left := 20;
 formL.Show();

 formS := TF_HoukEvs.Create(nil);
 formS.Parent := Self.P_HoukS;
 formS.Left := 20;
 formS.Show();
end;

destructor TF_HoukEvsUsek.Destroy();
begin
 formL.Free();
 formS.Free();

 inherited;
end;

////////////////////////////////////////////////////////////////////////////////

procedure TF_HoukEvsUsek.Open(Blk:TBlkUsek);
begin
 Self.blk := Blk;

 formL.FillFromHouks(Blk.GetSettings().houkEvL);
 formS.FillFromHouks(Blk.GetSettings().houkEvS);

 Self.Caption := 'Houkac� ud�losti �seku ' + Blk.GetGlobalSettings().name;
 Self.ActiveControl := B_Apply;
 Self.ShowModal();
end;

////////////////////////////////////////////////////////////////////////////////

procedure TF_HoukEvsUsek.B_StornoClick(Sender: TObject);
begin
 Self.Close();
end;

////////////////////////////////////////////////////////////////////////////////

procedure TF_HoukEvsUsek.B_ApplyClick(Sender: TObject);
var s:TBlkUsekSettings;
begin
 if (not formL.InputValid()) then
  begin
   Application.MessageBox('N�jak� ud�lost v lich�m sm�ru je �patn� zadan�!', 'Nelze ulo�it data', MB_OK OR MB_ICONWARNING);
   Exit();
  end;

 if (not formS.InputValid()) then
  begin
   Application.MessageBox('N�jak� ud�lost v sud�m sm�ru je �patn� zadan�!', 'Nelze ulo�it data', MB_OK OR MB_ICONWARNING);
   Exit();
  end;

 if (Self.blk <> nil) then
  begin
   s := Self.blk.GetSettings();
   s.houkEvL := formL.GetHoukEvs();
   s.houkEvS := formS.GetHoukEvs();
   Self.blk.SetSettings(s); // destructors of the old data should be called manually
  end;

 Self.Close();
end;

////////////////////////////////////////////////////////////////////////////////

end.
