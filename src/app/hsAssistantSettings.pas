unit hsAssistantSettings;

{ Who the assistant is: the provider, an address for one's own server, the
  model, and the key.  The key is never shown - it is pasted in, or
  forgotten - and is kept apart from the settings (see hsAssistantContext). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType, Clipbrd,
  BCButton, InkLabel, BCComboBox, InkEdit, BGRATheme, BGRAThemeCheckBox, hsAssistantContext;

type

  { TAssistantSettingsForm }

  TAssistantSettingsForm = class(TForm)
    pnlBody: TPanel;
    lblHead: TInkLabel;
    lblProvider: TInkLabel;
    cbProvider: TBCComboBox;
    lblEndpoint: TInkLabel;
    edEndpoint: TInkEdit;
    lblModel: TInkLabel;
    edModel: TInkEdit;
    lblKey: TInkLabel;
    lblKeyState: TInkLabel;
    btnPasteKey: TBCButton;
    btnForgetKey: TBCButton;
    lblKeyWhere: TInkLabel;
    chkThink: TBGRAThemeCheckBox;
    btnCancel: TBCButton;
    btnSave: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnPasteKeyClick(Sender: TObject);
    procedure btnForgetKeyClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    FKey: string;
    procedure ShowKey;
  end;

{ True when saved. }
function EditAssistantSettings(AOwner: TComponent): Boolean;

implementation

{$R *.lfm}

uses
  hsDialogSkin;

function EditAssistantSettings(AOwner: TComponent): Boolean;
var
  F: TAssistantSettingsForm;
begin
  F := TAssistantSettingsForm.Create(AOwner);
  try
    Result := F.ShowModal = mrOK;
  finally
    F.Free;
  end;
end;

procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
var
  S: TAssistantSettings;
  I: Integer;
begin
  hsDialogSkin.ThemeForm(Self);
  S := LoadAssistantSettings;
  cbProvider.Items.Clear;
  for I := 0 to High(PROVIDERS) do cbProvider.Items.Add(PROVIDERS[I]);
  cbProvider.ItemIndex := cbProvider.Items.IndexOf(S.Provider);
  if cbProvider.ItemIndex < 0 then cbProvider.ItemIndex := 0;
  edEndpoint.Text := S.Endpoint;
  edModel.Text := S.Model;
  chkThink.Checked := S.Think;
  lblKeyWhere.Caption := DimSpan('Kept in ', False) + TextSpan(AssistantKeyFile, False, False) +
    DimSpan(', apart from the settings, and never shown here.', False);
  FKey := LoadAssistantKey;
  ShowKey;
end;

procedure TAssistantSettingsForm.ShowKey;
begin
  if FKey = '' then lblKeyState.Caption := DimSpan('No key saved', False)
  else if Length(FKey) > 8 then
    lblKeyState.Caption := InkSpan('A key ending ...' + Copy(FKey, Length(FKey) - 3, 4), ToneColor(True), False, False)
  else
    lblKeyState.Caption := InkSpan('A key is saved', ToneColor(True), False, False);
  btnForgetKey.Enabled := FKey <> '';
end;

procedure TAssistantSettingsForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    btnSaveClick(nil);
    Key := 0;
  end;
end;

procedure TAssistantSettingsForm.btnPasteKeyClick(Sender: TObject);
var
  K: string;
begin
  K := Trim(Clipboard.AsText);
  { one word, no spaces: anything else is not a key }
  if (K = '') or (Pos(' ', K) > 0) or (Pos(#10, K) > 0) or (Length(K) > 400) then
  begin
    lblKeyState.Caption := InkSpan('The clipboard holds no key', ToneColor(False), False, False);
    Exit;
  end;
  FKey := K;
  ShowKey;
end;

procedure TAssistantSettingsForm.btnForgetKeyClick(Sender: TObject);
begin
  FKey := '';
  ShowKey;
end;

procedure TAssistantSettingsForm.btnSaveClick(Sender: TObject);
var
  S: TAssistantSettings;
begin
  S := LoadAssistantSettings;
  S.Provider := cbProvider.Text;
  S.Endpoint := Trim(edEndpoint.Text);
  S.Model := Trim(edModel.Text);
  S.Think := chkThink.Checked;
  SaveAssistantSettings(S);
  if FKey <> LoadAssistantKey then SaveAssistantKey(FKey);
  ModalResult := mrOK;
end;

procedure TAssistantSettingsForm.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
