unit hsLongText;

{ A scrolling, fixed-width text box with a Copy button, for long output
  like /state that is too wide or too long for the facts box.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  LCLType, Clipbrd, BCButton, hsDialogSkin, InkMemo;

type
  TLongTextForm = class(TForm)
    memText: TInkMemo;
    pnlBar: TPanel;
    btnCopy: TBCButton;
    btnClose: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnCopyClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
  public
    { Show AText under Title; True when it was copied on the way out. }
    class function ShowText(AOwner: TComponent; const Title, AText: string): Boolean;
  end;

implementation

{$R *.lfm}

procedure TLongTextForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
  { fixed width so columns line up; the font name differs per system }
  memText.Font.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
  ClientWidth := Min(ClientWidth, Screen.WorkAreaWidth - 80);
  ClientHeight := Min(ClientHeight, Screen.WorkAreaHeight - 80);
end;

{ Enter and Esc both close it. }
procedure TLongTextForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) or (Key = VK_RETURN) then
  begin
    ModalResult := mrOK;
    Key := 0;
  end;
end;

procedure TLongTextForm.btnCopyClick(Sender: TObject);
begin
  ModalResult := mrYes;
end;

procedure TLongTextForm.btnCloseClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

class function TLongTextForm.ShowText(AOwner: TComponent;
  const Title, AText: string): Boolean;
var
  F: TLongTextForm;
begin
  F := TLongTextForm.Create(AOwner);
  try
    F.Caption := Title;
    F.memText.Lines.Text := AText;
    Result := F.ShowModal = mrYes;
    if Result then Clipboard.AsText := AText;
  finally
    F.Free;
  end;
end;

end.
