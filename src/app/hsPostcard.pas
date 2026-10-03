unit hsPostcard;

{ The one-time postcard: on the second start the program asks once whether
  it may send a note about the machine, plus an optional line from the user.
  The full text is shown first and it is never asked again.  No identifier
  of any kind goes in it.  Sent like a bug report (see hsBugReport).
  --offline never asks; /postcard asks again. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs;

type

  { THelloForm }

  THelloForm = class(TForm)
    lblHead: TLabel;
    lblWhy: TLabel;
    lblWhat: TLabel;
    memText: TMemo;
    lblNote: TLabel;
    memNote: TMemo;
    lblHonest: TLabel;
    lblStage: TLabel;
    btnSave: TButton;
    btnNo: TButton;
    btnSend: TButton;
    procedure btnNoClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormShow(Sender: TObject);
    procedure memNoteChange(Sender: TObject);
  private
    FVersion: string;
    FSent, FBusy, FAnswered: Boolean;
    procedure Refresh_;
    procedure Stage(const S: string);
  public
    Version: string;
    { true once a postcard was sent from this window }
    property Sent: Boolean read FSent;
  end;

{ Counts a start, for deciding when to ask. }
procedure CountLaunch;

{ Second start or later, never answered, and not --offline. }
function PostcardDue: Boolean;

{ The exact text that would be sent. }
function PostcardText(const Version, Note: string): string;

{ Records the answer either way so it is not asked again.  Forced is
  /postcard, which asks regardless. }
procedure OfferPostcard(AOwner: TComponent; const Version: string; Forced: Boolean);

implementation

{$R *.lfm}

uses
  IniFiles, Graphics, hsPaths, hsSysInfo, hsBugReport, hsNet, hsDialogSkin, hsSurface;

const
  SECTION = 'postcard';
  { skip the first start; it is for seeing whether the program runs }
  ASK_ON_LAUNCH = 2;

procedure CountLaunch;
var
  Ini: TIniFile;
  N: Integer;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      N := Ini.ReadInteger(SECTION, 'launches', 0);
      if N < 1000 then Ini.WriteInteger(SECTION, 'launches', N + 1);
    finally
      Ini.Free;
    end;
  except
    { an unwritable config is not worth an error here }
  end;
end;

function PostcardDue: Boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  if NetOffline then Exit;
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Result := (Ini.ReadInteger(SECTION, 'launches', 0) >= ASK_ON_LAUNCH) and
                (Ini.ReadString(SECTION, 'answer', '') = '');
    finally
      Ini.Free;
    end;
  except
    Result := False;
  end;
end;

procedure RecordAnswer(const Answer: string);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(ConfigFile);
    try
      Ini.WriteString(SECTION, 'answer', Answer);
      Ini.WriteString(SECTION, 'when', FormatDateTime('yyyy-mm-dd', Now));
    finally
      Ini.Free;
    end;
  except
  end;
end;

function PostcardText(const Version, Note: string): string;
var
  N: string;
begin
  { The collector keys on the first line.  The rest is the machine facts a
    bug report carries, and the day only.  Nothing about the person (see
    hsSysInfo). }
  Result := 'Heckers Sketch hello' + LineEnding +
    'version: ' + Version + LineEnding +
    'sent: ' + FormatDateTime('yyyy-mm-dd', Now) + LineEnding +
    SystemFacts;
  N := Trim(Note);
  if N = '' then
    Result := Result + 'they said: nothing' + LineEnding
  else
    Result := Result + 'they said:' + LineEnding + N + LineEnding;
end;

procedure OfferPostcard(AOwner: TComponent; const Version: string; Forced: Boolean);
var
  F: THelloForm;
begin
  if NetOffline and not Forced then Exit;
  F := THelloForm.Create(AOwner);
  try
    F.Version := Version;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ THelloForm }

procedure THelloForm.FormShow(Sender: TObject);
begin
  FVersion := Version;
  hsDialogSkin.SkinForm(Self);
  { bold labels have their own font, so set their color; stock buttons keep
    the toolkit's text color }
  lblHead.Font.Color := PixToColor(DlgTheme.Text);
  lblWhat.Font.Color := PixToColor(DlgTheme.Text);
  btnSave.Font.Color := clBtnText;
  btnNo.Font.Color := clBtnText;
  btnSend.Font.Color := clBtnText;
  memText.Color := PixToColor(DlgTheme.Shell2);
  memText.Font.Color := PixToColor(DlgTheme.Text);
  memNote.Color := PixToColor(DlgTheme.Shell2);
  memNote.Font.Color := PixToColor(DlgTheme.Text);
  lblWhy.Caption :=
    'Two people are making this, and we cannot tell whether anyone is ' +
    'trying it: GitHub counts downloads, and most of those are our own ' +
    'machines.  So the program asks, once, whether it may send us one ' +
    'note saying what sort of computer it is running on.  That is all it ' +
    'is - a postcard, not a subscription.';
  lblHonest.Caption :=
    'Plainly: nothing in it names you.  No user name, no machine name, no ' +
    'network address, no files, no drawing, and no number that would let ' +
    'two postcards be matched up.  It is encrypted before it leaves, to a ' +
    'key only we hold, and goes to a public postbox that throws files away ' +
    'after a few days - we never see where it came from, though the postbox ' +
    'does, briefly, as any website would.  It is sent once, now, and never ' +
    'again.  Whichever button you press you will not be asked again; ' +
    '/postcard in the command bar brings this back if you change your mind, ' +
    'and starting with --offline means it never asks at all.';
  Stage('');
  Refresh_;
  ActiveControl := memNote;
end;

procedure THelloForm.Refresh_;
var
  Top_: Integer;
begin
  Top_ := memText.VertScrollBar.Position;
  memText.Lines.Text := PostcardText(FVersion, memNote.Lines.Text);
  memText.VertScrollBar.Position := Top_;
end;

procedure THelloForm.Stage(const S: string);
begin
  lblStage.Caption := S;
  lblStage.Repaint;
  Application.ProcessMessages;
end;

procedure THelloForm.memNoteChange(Sender: TObject);
begin
  Refresh_;
end;

procedure THelloForm.btnNoClick(Sender: TObject);
begin
  Close;
end;

procedure THelloForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  { closing the window counts as No and is not asked again }
  if not FAnswered then
  begin
    FAnswered := True;
    RecordAnswer('declined');
  end;
  CloseAction := caHide;
end;

procedure THelloForm.btnSaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  L: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Save a copy of the postcard';
    Dlg.FileName := 'heckers-sketch-postcard.txt';
    Dlg.Filter := 'Text|*.txt';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
    begin
      L := TStringList.Create;
      try
        L.Text := PostcardText(FVersion, memNote.Lines.Text);
        L.SaveToFile(Dlg.FileName);
      finally
        L.Free;
      end;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure THelloForm.btnSendClick(Sender: TObject);
var
  Body, Name_, Err: string;
begin
  if FBusy then Exit;
  FBusy := True;
  btnSend.Enabled := False;
  btnNo.Enabled := False;
  memNote.ReadOnly := True;
  try
    Body := PostcardText(FVersion, memNote.Lines.Text);
    Name_ := UniqueReportName('hello', FVersion);
    { SendReport does the encrypting; the stage is shown so the user sees it }
    Stage('Encrypting...');
    Sleep(400);
    Stage('Sending...');
    if SendReport(Name_, Body, Err) then
    begin
      FSent := True;
      FAnswered := True;
      RecordAnswer('sent');
      Stage('Sent - thank you.');
      btnNo.Caption := 'Close';
      btnNo.Enabled := True;
    end
    else
    begin
      { the answer was yes and it was tried; do not ask again }
      FAnswered := True;
      RecordAnswer('tried');
      Stage('It did not go: ' + Err);
      btnNo.Caption := 'Close';
      btnNo.Enabled := True;
      btnSend.Enabled := True;
      memNote.ReadOnly := False;
    end;
  finally
    FBusy := False;
  end;
end;

end.
