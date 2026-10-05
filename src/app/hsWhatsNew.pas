unit hsWhatsNew;

{ The release notes window.  build.sh compiles WHATS_NEW.md into
  whatsnew.inc before every build.  This picks the sections newer than the
  version an update replaced (or all of them from the menu) and hands the
  Markdown to a LazInk TInkPage styled in the dialog theme.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, StdCtrls,
  ExtCtrls, LCLType, LCLIntf, BCPanel, BCButton, InkPage, InkMarkdown,
  hsUpdater, hsSkin, hsDialogSkin, hsSurface;

type
  TWhatsNewForm = class(TForm)
    pnlHead: TBCPanel;
    { a plain transparent label: a drawn one fills its rectangle with the
      inherited color, not what the skinned panel painted, and shows a box }
    lblTitle: TLabel;
    btnShut: TBCButton;
    pnlBody: TBCPanel;
    Page: TInkPage;
    pnlFoot: TBCPanel;
    lblWhich: TLabel;
    btnGo: TBCButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HeadDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure HeadMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure HeadUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GoClick(Sender: TObject);
    procedure PageLinkClick(Sender: TObject; const URL: string);
  private
    { the notes, as Markdown }
    FNotes: string;
    FDrag: hsDialogSkin.TFormDrag;
    procedure ShowNotes;
  public
    { after an update: what changed since PreviousVersion }
    procedure ShowRelease(const PreviousVersion, NewVersion: string);
    { from the menu: the whole history }
    procedure ShowAll;
  end;

{ Every release section newer than Since, or all when Since is empty; ''
  when nothing is newer.  "Next release" is the running build and is shown
  under its own version. }
function ReleaseNotesMarkdown(const Since: string): string;
{ The page's CSS, in the dialog theme's colors. }
function ReleaseNotesStyle(const T: TTheme): string;

implementation

{$R *.lfm}

{$I whatsnew.inc}

{ --- reading the file -------------------------------------------------- }

{ The sections of WHATS_NEW.md newer than Since; the file's own title and
  editor comment are dropped. }
function ReleaseNotesMarkdown(const Since: string): string;
var
  Lines, Out_: TStringList;
  I: Integer;
  L, Title: string;
  Keep: Boolean;
begin
  Lines := TStringList.Create;
  Out_ := TStringList.Create;
  try
    Lines.Text := WHATS_NEW_MD;
    Keep := False;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Lines[I];
      if Copy(L, 1, 3) = '## ' then
      begin
        Title := Trim(Copy(L, 4, MaxInt));
        if SameText(Title, 'Next release') then
        begin
          Keep := True;
          Title := CurrentVersion;
        end
        else
          Keep := (Since = '') or NewerThan(Title, Since);
        if Keep then
        begin
          if Out_.Count > 0 then Out_.Add('');
          Out_.Add('## ' + Title);
          Out_.Add('');
          Out_.Add('---');
        end;
        Continue;
      end;
      if not Keep then Continue;
      Out_.Add(L);
    end;
    if Out_.Count = 0 then Result := ''
    else Result := Out_.Text;
  finally
    Out_.Free;
    Lines.Free;
  end;
end;

{ Dialog theme colors, accent headings and a themed scrollbar. }
function ReleaseNotesStyle(const T: TTheme): string;

  function Hex(const P: TPix): string;
  begin
    Result := Format('#%.2x%.2x%.2x', [P.R, P.G, P.B]);
  end;

begin
  Result :=
    'html { scrollbar-color: ' + Hex(T.Accent) + ' ' +
      Hex(MixPix(T.Panel, Pix(0, 0, 0), 0.25)) + '; scrollbar-width: thin }' +
    ' body { background: ' + Hex(T.Panel) + '; color: ' + Hex(T.TextDim) +
      '; font-size: 14px; padding: 6px }' +
    ' h2 { color: ' + Hex(T.Accent) + '; font-size: 20px; margin-top: 20px }' +
    ' h3 { color: ' + Hex(T.TextDim) + '; font-size: 13px; margin-top: 8px }' +
    ' strong, b { color: ' + Hex(T.Text) + ' }' +
    ' li { margin-bottom: 6px }' +
    ' code { background: ' + Hex(MixPix(T.Panel, T.Text, 0.12)) + ' }' +
    ' hr { color: ' + Hex(T.TextDim) + ' }' +
    ' a { color: ' + Hex(T.Accent) + ' }';
end;

{ --- the window -------------------------------------------------------- }

{ No window manager frame; the head is drawn here and dragged by hand. }
procedure TWhatsNewForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
  { the head is square edge to edge; the panels under it are rounded }
  hsDialogSkin.SkinPanel(pnlHead, True, 0);
  hsDialogSkin.SkinPanel(pnlBody, False, 12);
  hsDialogSkin.SkinPanel(pnlFoot, False, 12);
  Page.Color := PixToColor(hsDialogSkin.DlgTheme.Panel);
  Page.Font.Color := PixToColor(hsDialogSkin.DlgTheme.Text);
  { drag-scrolling is how touch scrolls the page; keep it on }
  Page.DragScroll := True;
end;

procedure TWhatsNewForm.GoClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TWhatsNewForm.HeadDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then hsDialogSkin.DragBegin(FDrag, Self);
end;

procedure TWhatsNewForm.HeadMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  hsDialogSkin.DragTo(FDrag, Self);
end;

procedure TWhatsNewForm.HeadUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  hsDialogSkin.DragEnd(FDrag);
end;

{ Web links open in the browser. }
procedure TWhatsNewForm.PageLinkClick(Sender: TObject; const URL: string);
begin
  if (Pos('http://', URL) = 1) or (Pos('https://', URL) = 1) then OpenURL(URL);
end;

procedure TWhatsNewForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  { Esc and Enter close; other keys scroll the page.  With KeyPreview the
    form sees keys before the find bar, so leave them to the bar while it
    is open. }
  if Page.FindBarVisible then Exit;
  case Key of
    VK_ESCAPE, VK_RETURN:
      begin
        ModalResult := mrOk;
        Key := 0;
      end;
  end;
end;

procedure TWhatsNewForm.ShowNotes;
begin
  Page.TextFormat := itfMarkdown;
  { <kbd> and the like draw; a placeholder like "/tiles <folder>" stays text }
  Page.MarkdownInlineHTML := True;
  Page.StyleSheet.Text := ReleaseNotesStyle(hsDialogSkin.DlgTheme);
  Page.Source := FNotes;
  Page.ScrollTo(0);
  ActiveControl := Page;
end;

procedure TWhatsNewForm.ShowRelease(const PreviousVersion,
  NewVersion: string);
begin
  lblTitle.Caption := 'Heckers Sketch has been updated';
  if PreviousVersion <> '' then
    lblWhich.Caption := PreviousVersion + '  ' + #$E2#$86#$92 + '  ' + NewVersion
  else
    lblWhich.Caption := NewVersion;
  FNotes := ReleaseNotesMarkdown(PreviousVersion);
  { older than the notes go back: show the whole history, not nothing }
  if FNotes = '' then FNotes := ReleaseNotesMarkdown('');
  ShowNotes;
  ShowModal;
end;

procedure TWhatsNewForm.ShowAll;
begin
  lblTitle.Caption := 'What''s new in Heckers Sketch';
  lblWhich.Caption := 'This is ' + CurrentVersion;
  FNotes := ReleaseNotesMarkdown('');
  ShowNotes;
  ShowModal;
end;

end.
