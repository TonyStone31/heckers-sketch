unit hsRadiantLicense;

{ The radiant tools ask for a license before they open.  No number is ever
  accepted: until there is a real licensing system, the arrow keys pressed
  up, up, down, down, left, right, down in this window let you in, and the
  program remembers it from then on. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType, BCButton, InkLabel, InkEdit;

type

  { TRadiantLicenseForm }

  TRadiantLicenseForm = class(TForm)
    pnlBody: TPanel;
    lblHead: TInkLabel;
    lblBody: TInkLabel;
    lblNumber: TInkLabel;
    edNumber: TInkEdit;
    lblVerdict: TInkLabel;
    btnCancel: TBCButton;
    btnCheck: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure btnCheckClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    { the last arrow keys pressed, oldest first }
    FArrows: array of word;
  end;

{ True when the radiant tools may open: unlocked before, or unlocked now in
  the license window. }
function RadiantUnlocked(AOwner: TComponent): boolean;

implementation

{$R *.lfm}

uses
  IniFiles, hsPaths, hsDialogSkin;

const
  SECTION = 'radiant';
  CODE: array[0..6] of word = (VK_UP, VK_UP, VK_DOWN, VK_DOWN, VK_LEFT, VK_RIGHT, VK_DOWN);

function Unlocked: boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Result := Ini.ReadBool(SECTION, 'licensed', False);
    finally
      Ini.Free;
    end;
  except
  end;
end;

procedure Unlock;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteBool(SECTION, 'licensed', True);
    finally
      Ini.Free;
    end;
  except
    { an unwritable config: unlocked for this time only }
  end;
end;

function RadiantUnlocked(AOwner: TComponent): boolean;
var
  F: TRadiantLicenseForm;
begin
  if Unlocked then Exit(True);
  F := TRadiantLicenseForm.Create(AOwner);
  try
    Result := F.ShowModal = mrOk;
  finally
    F.Free;
  end;
end;

procedure TRadiantLicenseForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
  FArrows := nil;
end;

procedure TRadiantLicenseForm.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  I: integer;
  Match: boolean;
begin
  case Key of
    VK_ESCAPE:
    begin
      ModalResult := mrCancel;
      Key := 0;
    end;
    VK_RETURN:
    begin
      btnCheckClick(nil);
      Key := 0;
    end;
    VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT:
    begin
      if Length(FArrows) = Length(CODE) then Delete(FArrows, 0, 1);
      Insert(Key, FArrows, Length(FArrows));
      Match := Length(FArrows) = Length(CODE);
      for I := 0 to High(FArrows) do Match := Match and (FArrows[I] = CODE[I]);
      if Match then
      begin
        Unlock;
        ModalResult := mrOk;
      end;
    end;
  end;
end;

procedure TRadiantLicenseForm.btnCheckClick(Sender: TObject);
begin
  if Trim(edNumber.Text) = '' then
    lblVerdict.Caption := InkSpan('Enter the license number first.', ToneColor(False), False, False)
  else
    lblVerdict.Caption := InkSpan('That license number is not valid.', ToneColor(False), False, False);
  edNumber.SetFocus;
end;

procedure TRadiantLicenseForm.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
