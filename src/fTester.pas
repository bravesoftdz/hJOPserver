unit fTester;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Outputdriver, Menus, Spin, ExtCtrls, Buttons, ColorGrd,
  ComCtrls, TabNotBk, Gauges, fMain, TBloky;

type
  TF_Tester = class(TForm)
    T_tester: TTimer;
    GB_vstupy: TGroupBox;
    L_1: TLabel;
    CB_MtbAdr: TComboBox;
    CHB_LogZmeny: TCheckBox;
    GB_Change: TGroupBox;
    LB_Changes: TListBox;
    B_Clear: TButton;
    GB_vystupy: TGroupBox;
    procedure B_options_ODClick(Sender: TObject);
    procedure T_testerTimer(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure SE_OutMtbChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure CB_MtbAdrChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure B_ClearClick(Sender: TObject);
  private const
    _S_TOP    = 18;
    _S_HEIGHT = 12;
    _S_WIDTH  = 25;
    _S_INCR   = 15;
    _S_LEFT   = 10;
    _L_LEFT   = 40;

  private
   MTBAddr:Smallint;
   CB_MTBAdrData:TArI;
   SInput:array [0..15] of TShape;
   SOutput:array [0..15] of TShape;   

    procedure CreateSInput;
    procedure CreateSOutput;
    procedure SOutputMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  public
   procedure UpdateOut;
   procedure UpdateIn;

   procedure AfterMTBOpen();

  end;

var
  F_Tester: TF_Tester;

implementation

uses TechnologieMTB, Logging;

{$R *.dfm}

procedure TF_Tester.B_options_ODClick(Sender: TObject);
 begin
  MTB.ShowCfgDialog();
 end;

procedure TF_Tester.T_testerTimer(Sender: TObject);
 begin
  if (MTBAddr <> -1) then
   begin
    UpdateOut;
    UpdateIn;
   end; 
 end;//procedure

procedure TF_Tester.FormShow(Sender: TObject);
var cyklus:Integer;
 begin
  for cyklus := 0 to 15 do
   begin
    SInput[cyklus].Brush.Color  := clGray;
    SOutput[cyklus].Brush.Color := clGray;
   end;//for cyklus

  T_tester.Enabled := true; 
  writelog('Zobrazeno okno Testeru',0,0);
 end;//procedure

procedure TF_Tester.UpdateOut;
var cyklus, val:Integer;
 begin
  for cyklus := 0 to 15 do
   begin
    val := MTB.GetOutput(MTBAddr, cyklus);
    if (val < 0) then
      SOutput[cyklus].Brush.Color := clGray
    else if (val = 0) then
      SOutput[cyklus].Brush.Color := clRed
    else
      SOutput[cyklus].Brush.Color := clLime;
   end;//for cyklus
 end;//procedure

procedure TF_Tester.SE_OutMtbChange(Sender: TObject);
 begin
  UpdateOut;
 end;//procedure

procedure TF_Tester.UpdateIn;
var cyklus:Integer;
    InputState:Shortint;
    LastState:Shortint;
 begin
  for cyklus := 0 to 15 do
   begin
    InputState := MTB.GetInput(MTBAddr, cyklus);

    if (F_Tester.CHB_LogZmeny.Checked) then
     begin
      case (SInput[cyklus].Brush.Color) of
       clRed :LastState := 0;
       clLime:LastState := 1;
       clGray:LastState := -1;
      else LastState := -1;  end;

      if ((InputState <> LastState) and (LastState <> -1)) then
       begin
        F_Tester.LB_Changes.Items.Add('Zmena:: MTB:'+Format('%3d' ,[MTBAddr])+', port: '+Format('%2d' ,[cyklus])+', state:'+Format('%1d' ,[InputState]));
        Beep;
       end;//if (InputState <> LastState)
     end;//if F_Tester.CHB_LogZmeny.Checked

    if (InputState < 0) then
      SInput[cyklus].Brush.Color := clGray
    else if (InputState = 0) then
      SInput[cyklus].Brush.Color := clRed
    else
      SInput[cyklus].Brush.Color := clLime;
   end;//for cyklus
 end;//procedure

procedure TF_Tester.FormCreate(Sender: TObject);
 begin
  SetLength(Self.CB_MTBAdrData, TMTB._MAX_MTB);  // pole indexu vytvorime tak, aby bylo co nejvetsi
  Self.CreateSInput;
  Self.CreateSOutput;
 end;//procedure

procedure TF_Tester.CB_MtbAdrChange(Sender: TObject);
var cyklus:Integer;
 begin
  for cyklus := 0 to 15 do
   begin
    SInput[cyklus].Brush.Color  := clGray;
    SOutput[cyklus].Brush.Color := clGray;
   end;//for cyklus

  if ((CB_MtbAdr.ItemIndex > -1) and (CB_MtbAdr.ItemIndex < Length(CB_MTBAdrData))) then
   begin
    MTBAddr := CB_MtbAdrData[CB_MtbAdr.ItemIndex];
    if (MTB.IsModule(MTBAddr)) then Self.T_tester.Enabled := true else Self.T_tester.Enabled := false;
   end;
 end;//procedure

procedure TF_Tester.FormClose(Sender: TObject; var Action: TCloseAction);
 begin
  T_tester.Enabled := false;
  writelog('Skryto okno Testeru',0,0);
 end;//procedure

procedure TF_Tester.CreateSInput;
var cyklus:Integer;
    aTop:Integer;
    L:TLabel;
 begin
  aTop := _S_TOP;

  for cyklus := 0 to 15 do
   begin
    SInput[cyklus] := TShape.Create(F_Tester.GB_vstupy);

    SInput[cyklus].Parent := F_Tester.GB_vstupy;
    SInput[cyklus].Top    := aTop;
    SInput[cyklus].Left   := _S_LEFT;
    SInput[cyklus].Width  := _S_WIDTH;
    SInput[cyklus].Height := _S_HEIGHT;
    SInput[cyklus].Shape  := stRectangle;
    SInput[cyklus].Tag    := cyklus;
    SInput[cyklus].Brush.Color := clRed;

    L            := TLabel.Create(F_Tester.GB_vstupy);
    L.Parent     := Self.GB_vstupy;
    L.Font.Color := clWhite;
    L.Caption    := IntToStr(cyklus);
    L.Left       := _L_LEFT;
    L.Top        := aTop;

    aTop := aTop + _S_INCR;
   end;//for cyklus
 end;//procedure

procedure TF_Tester.CreateSOutput;
var cyklus:Integer;
    aTop:Integer;
    L:TLabel;
 begin
  aTop := _S_TOP;

  for cyklus := 0 to 15 do
   begin
    SOutput[cyklus] := TShape.Create(F_Tester.GB_vystupy);

    SOutput[cyklus].Parent := F_Tester.GB_vystupy;
    SOutput[cyklus].Top    := aTop;
    SOutput[cyklus].Left   := _S_LEFT;
    SOutput[cyklus].Width  := _S_WIDTH;
    SOutput[cyklus].Height := _S_HEIGHT;
    SOutput[cyklus].Shape  := stRectangle;
    SOutput[cyklus].Tag    := cyklus;
    SOutput[cyklus].Brush.Color := clRed;
    SOutput[cyklus].OnMouseUp := SOutputMouseUp;

    L            := TLabel.Create(F_Tester.GB_vystupy);
    L.Parent     := Self.GB_vystupy;
    L.Font.Color := clWhite;
    L.Caption    := IntToStr(cyklus);
    L.Left       := _L_LEFT;
    L.Top        := aTop;

    aTop := aTop + _S_INCR;
   end;//for cyklus
 end;//procedure

procedure TF_Tester.SOutputMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
 begin
  if (MTBAddr < 0) then Exit;

  if ((Sender as TShape).Brush.Color = clRed) then
   begin
    MTB.SetOutput(MTBAddr, (Sender as TShape).Tag, 1);
    (Sender as TShape).Brush.Color := clLime;
   end else begin
    MTB.SetOutput(MTBAddr, (Sender as TShape).Tag, 0);
    (Sender as TShape).Brush.Color := clRed;
   end;

  (Sender as TShape).Brush.Color := clYellow; 
 end;//procedure

procedure TF_Tester.B_ClearClick(Sender: TObject);
 begin
  F_Tester.LB_Changes.Clear;
 end;//procedure

procedure TF_Tester.AfterMTBOpen();
var i:Integer;
begin
 Self.CB_MtbAdr.Clear();

 for i := 0 to TMTB._MAX_MTB-1 do
  begin
   if (not MTB.IsModule(i)) then continue;
   Self.CB_MTBAdrData[Self.CB_MtbAdr.Items.Count] := i;
   Self.CB_MtbAdr.Items.Add(IntToStr(i) + ' : ' + MTB.GetNameMTB(i));
  end;//for i

 Self.CB_MtbAdr.ItemIndex := 0;
 Self.CB_MtbAdrChange(self);
end;//procedure

end.//unit
