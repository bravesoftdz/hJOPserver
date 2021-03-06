unit fUserEdit;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, User, ComCtrls;

type
  TF_UserEdit = class(TForm)
    Label1: TLabel;
    E_UserName: TEdit;
    Label2: TLabel;
    E_FirstName: TEdit;
    Label3: TLabel;
    E_LastName: TEdit;
    GB_Password: TGroupBox;
    Label4: TLabel;
    E_Password1: TEdit;
    Label5: TLabel;
    E_Password2: TEdit;
    CHB_root: TCheckBox;
    B_Apply: TButton;
    B_Cancel: TButton;
    GroupBox1: TGroupBox;
    LV_ORs: TListView;
    CB_Rights: TComboBox;
    CHB_Ban: TCheckBox;
    CHB_Reg: TCheckBox;
    procedure B_CancelClick(Sender: TObject);
    procedure B_ApplyClick(Sender: TObject);
    procedure LV_ORsChange(Sender: TObject; Item: TListItem;
      Change: TItemChange);
    procedure CB_RightsChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure LV_ORsCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
  private
    OpenUser:TUser;
    new:boolean;

    procedure FillORs();

  public
    procedure OpenForm(User:TUser);
    procedure NewUser();
  end;

var
  F_UserEdit: TF_UserEdit;

implementation

{$R *.dfm}

uses UserDb, DataUsers, TOblsRizeni, TOblRizeni, fMain;

////////////////////////////////////////////////////////////////////////////////

procedure TF_UserEdit.B_CancelClick(Sender: TObject);
begin
 Self.Close();
end;

procedure TF_UserEdit.CB_RightsChange(Sender: TObject);
var i:Integer;
begin
 for i := 0 to Self.LV_ORs.Items.Count-1 do
  begin
   if (Self.LV_ORs.Items[i].Selected) then
    begin
     Self.OpenUser.SetRights(Self.LV_ORs.Items[i].Caption, TORControlRights(Self.CB_Rights.ItemIndex));
     Self.LV_ORs.Items[i].SubItems.Strings[1] := TOR.ORRightsToString(TORControlRights(Self.CB_Rights.ItemIndex));
     TORControlRights(Self.LV_ORs.Items[i].Data^) := TORControlRights(Self.CB_Rights.ItemIndex);
    end;
  end;

 Self.LV_ORs.Repaint();
end;

procedure TF_UserEdit.FormClose(Sender: TObject; var Action: TCloseAction);
var i:Integer;
begin
 Self.new := false;

 for i := 0 to Self.LV_ORs.Items.Count-1 do
  FreeMem(Self.LV_ORs.Items.Item[i].Data);
 Self.LV_ORs.Clear();
end;

procedure TF_UserEdit.LV_ORsChange(Sender: TObject; Item: TListItem;
  Change: TItemChange);
var rights, rights2:TORControlRights;
    i:Integer;
begin
 if (Self.LV_ORs.SelCount = 0) then
  begin
   // 0 vybranych polozek
   Self.CB_Rights.ItemIndex := -1;
   Self.CB_Rights.Enabled   := false;
  end else begin
   Self.CB_Rights.Enabled := true;
   if (Self.LV_ORs.SelCount = 1) then
    begin
     // 1 vybrana polozka
     if (Self.OpenUser.OblR.TryGetValue(Self.LV_ORs.Selected.Caption, rights)) then
      Self.CB_Rights.ItemIndex := Integer(rights)
     else
      Self.CB_Rights.ItemIndex := -1;
    end else begin
     // vic vybranych polozek -> pokud jsou opravenni stejna, vyplnime, jinak -1

     for i := 0 to Self.LV_ORs.Items.Count-1 do
       if (Self.LV_ORs.Items[i].Selected) then
         Self.OpenUser.OblR.TryGetValue(Self.LV_ORs.Items[i].Caption, rights);

     for i := 0 to Self.LV_ORs.Items.Count-1 do
       if (Self.LV_ORs.Items[i].Selected) then
        begin
         Self.OpenUser.OblR.TryGetValue(Self.LV_ORs.Items[i].Caption, rights2);
         if (rights2 <> rights) then
          begin
           Self.CB_Rights.ItemIndex := -1;
           Exit();
          end;
        end;

     Self.CB_Rights.ItemHeight := Integer(rights);
    end;// else SelCount > 1
  end;//else Selected = nil
end;

procedure TF_UserEdit.LV_ORsCustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
 case TORCOntrolRights(Item.Data^) of
  TORCOntrolRights.null      : Self.LV_ORs.Canvas.Brush.Color := clWhite;
  TORCOntrolRights.read      : Self.LV_ORs.Canvas.Brush.Color := $FFFFAA;
  TORCOntrolRights.write     : Self.LV_ORs.Canvas.Brush.Color := $AAFFFF;
  TORCOntrolRights.superuser : Self.LV_ORs.Canvas.Brush.Color := $AAAAFF;
 end;//case
end;

///////////////////////////////////////////////////////////////////////////////

procedure TF_UserEdit.OpenForm(User:TUser);
begin
 Self.OpenUser := User;
 Self.FillORs();

 Self.E_UserName.Text   := User.id;
 Self.E_FirstName.Text  := User.firstname;
 Self.E_LastName.Text   := User.lastname;
 Self.CHB_root.Checked  := User.root;
 Self.CHB_Ban.Checked   := User.ban;
 Self.CHB_Reg.Checked   := User.regulator;

 Self.E_Password1.Text  := 'heslo';
 Self.E_Password2.Text  := 'heslo';

 Self.ActiveControl := Self.E_UserName;
 Self.Caption := 'Editovat u�ivatele '+User.id;
 Self.ShowModal();
end;//procedure

procedure TF_UserEdit.NewUser();
begin
 Self.new := true;
 Self.OpenUser := TUser.Create();
 Self.FillORs();

 Self.E_UserName.Text   := '';
 Self.E_FirstName.Text  := '';
 Self.E_LastName.Text   := '';
 Self.CHB_root.Checked  := false;
 Self.CHB_Ban.Checked   := false;
 Self.CHB_Reg.Checked   := true;

 Self.E_Password1.Text  := '';
 Self.E_Password2.Text  := '';

 Self.ActiveControl := Self.E_UserName;
 Self.Caption := 'Vytvo�it nov�ho u�ivatele';
 Self.ShowModal();
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TF_UserEdit.B_ApplyClick(Sender: TObject);
var index:Integer;
begin
 if (Length(Self.E_UserName.Text) < 3) then
  begin
   Application.MessageBox('U�ivatelsk� jm�no mus� m�t alespo� 3 znaky!', 'nelze ulo�it data', MB_OK OR MB_ICONWARNING);
   Exit();
  end;

 if (Self.OpenUser <> nil) then
  begin
   if (Self.E_Password1.Text = '') then
    begin
     Application.MessageBox('Heslo nem��e b�t pr�zdn�!', 'nelze ulo�it data', MB_OK OR MB_ICONWARNING);
     Exit();
    end;
  end;//if Self.OpenUser <> nil

 if (Self.E_Password1.Text <> Self.E_Password2.Text) then
  begin
   Application.MessageBox('Zadan� hesla se neshoduj�!', 'nelze ulo�it data', MB_OK OR MB_ICONWARNING);
   Exit();
  end;
 if (Length(Self.E_Password1.Text) < 3) then
  begin
   Application.MessageBox('Heslo mus� m�t alespo� 3 znaky!', 'nelze ulo�it data', MB_OK OR MB_ICONWARNING);
   Exit();
  end;


 if (Self.new) then
  begin
   Self.OpenUser.password  := Self.E_Password1.Text;
   Self.OpenUser.lastlogin := Now;
  end else begin
   if (Self.E_Password1.Text <> 'heslo') then
     Self.OpenUser.password := Self.E_Password1.Text;
  end;

 Self.OpenUser.id        := Self.E_UserName.Text;
 Self.OpenUser.firstname := Self.E_FirstName.Text;
 Self.OpenUser.lastname  := Self.E_LastName.Text;
 Self.OpenUser.root      := Self.CHB_root.Checked;
 Self.OpenUser.ban       := Self.CHB_Ban.Checked;
 Self.OpenUser.regulator := Self.CHB_Reg.Checked;

 if (new) then
  begin
   try
     UsrDB.AddUser(Self.OpenUser);
   except
     on e:Exception do
      begin
       Application.MessageBox(PChar(e.Message), 'Varov�n�', MB_OK OR MB_ICONWARNING);
       Exit();
      end;
   end;
  end else begin
   UsersTableData.UpdateTable();
  end;

 index := UsrDB.IndexOf(Self.OpenUser.id);
 if (index > -1) then
  begin
   F_Main.LV_Users.Items[index].Selected := true;
   F_Main.LV_Users.Items[index].Focused  := true;
  end;

 Self.Close();
end;//procedure

////////////////////////////////////////////////////////////////////////////////

procedure TF_UserEdit.FillORs();
var LI:TListItem;
    i:Integer;
    rights:TORCOntrolRights;
    data:Pointer;
begin
 Self.LV_ORs.Clear();

 for i := 0 to ORs.Count-1 do
  begin
   LI := Self.LV_ORs.Items.Add;
   LI.Caption := ORs.GetORIdByIndex(i);
   LI.SubItems.Add(ORs.GetORNameByIndex(i));

   if (not Self.OpenUser.OblR.TryGetValue(LI.Caption, rights)) then
    rights := TORCOntrolRights.null;
   LI.SubItems.Add(TOR.ORRightsToString(rights));

   GetMem(data, 3);
   TORControlRights(data^) := rights;

   LI.Data := data;
  end;

 Self.CB_Rights.ItemIndex := -1;
 Self.CB_Rights.Enabled   := false;

 Self.LV_ORs.Repaint();
end;//procedure

////////////////////////////////////////////////////////////////////////////////

end.//unit
