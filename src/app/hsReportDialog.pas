unit hsReportDialog;

{ The problem report form: the note, the send-drawing tick and the
  screenshot.  Retaking or dropping the picture closes the form so the window
  is out of the shot; the main window reopens it with the note and tick as
  left (see TMainForm.ReportBug).  Nothing is sent from here.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLType,
  BCButton, BGRATheme, BGRAThemeCheckBox, hsDialogSkin;

type
  TReportDialog = class(TForm)
    lblSay: TLabel;
    memNote: TMemo;
    cbDrawing: TBGRAThemeCheckBox;
    lblFine: TLabel;
    imgShot: TImage;
    lblNoPic: TLabel;
    btnAgain: TBCButton;
    btnLater: TBCButton;
    btnDrop: TBCButton;
    btnSend: TBCButton;
    btnCancel: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnAgainClick(Sender: TObject);
    procedure btnLaterClick(Sender: TObject);
    procedure btnDropClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    FGrown: Boolean;
  public
    { Note and DocOn go in and come back out whatever button closed it, so
      retaking the picture loses nothing.  mrOK Send, mrCancel Cancel,
      mrRetry picture now, mrAll picture in ten seconds, mrIgnore no picture. }
    class function Ask(AOwner: TComponent; Crashed: Boolean; NThings: Integer;
      Shot: TBitmap; var Note: string; var DocOn: Boolean): TModalResult;
  end;

implementation

{$R *.lfm}

procedure TReportDialog.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
end;

{ The label above the note sizes itself and the form grows to match, so a
  larger font does not cut off its last line. }
procedure TReportDialog.FormShow(Sender: TObject);
var
  Grow: Integer;
begin
  if FGrown then Exit;
  FGrown := True;
  Grow := lblSay.Height - lblSay.Constraints.MinHeight;
  if Grow > 0 then ClientHeight := ClientHeight + Grow;
  ActiveControl := memNote;
end;

{ Esc cancels.  Enter is left alone on purpose: it is a new line in the
  note, not Send. }
procedure TReportDialog.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

procedure TReportDialog.btnAgainClick(Sender: TObject);
begin
  ModalResult := mrRetry;
end;

procedure TReportDialog.btnLaterClick(Sender: TObject);
begin
  ModalResult := mrAll;
end;

procedure TReportDialog.btnDropClick(Sender: TObject);
begin
  if btnDrop.Enabled then ModalResult := mrIgnore;
end;

procedure TReportDialog.btnSendClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TReportDialog.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TReportDialog.Ask(AOwner: TComponent; Crashed: Boolean;
  NThings: Integer; Shot: TBitmap; var Note: string;
  var DocOn: Boolean): TModalResult;
var
  F: TReportDialog;
begin
  F := TReportDialog.Create(AOwner);
  try
    if Crashed then
      F.lblSay.Caption := 'It crashed last time.  What were you doing when it ' +
        'went?  A line or two is plenty - the crash report itself is ' +
        'attached automatically, along with what the program was doing and ' +
        'what machine this is - RAM, processor, graphics, operating system; ' +
        'nothing about you.';
    F.memNote.Text := Note;

    { NThings counts the drawing that will actually be sent, which after a
      crash is the one saved then, not what is on screen.  With nothing
      drawn the box is unticked and disabled. }
    if NThings = 0 then
      F.cbDrawing.Caption := 'Send the drawing too - nothing drawn yet'
    else if NThings = 1 then
      F.cbDrawing.Caption := 'Send the drawing too - 1 thing drawn so far'
    else
      F.cbDrawing.Caption := Format('Send the drawing too - %d things drawn so far',
        [NThings]);

    { Use DocOn, not True: the form reopens after each retake, and the
      user's untick must survive that. }
    F.cbDrawing.Checked := (NThings > 0) and DocOn;
    F.cbDrawing.Enabled := NThings > 0;
    { the fine print would contradict a disabled box }
    if NThings = 0 then F.lblFine.Caption := '';

    if Shot <> nil then
      F.imgShot.Picture.Assign(Shot)
    else
    begin
      F.imgShot.Visible := False;
      F.lblNoPic.Visible := True;
    end;
    F.btnDrop.Enabled := Shot <> nil;

    Result := F.ShowModal;
    Note := Trim(F.memNote.Text);
    DocOn := F.cbDrawing.Checked and F.cbDrawing.Enabled;
  finally
    F.Free;
  end;
end;

end.
