unit hsAbout;

{ The about box: a LazInk HTML page, so the credits can carry links, inside
  the same painted shell as the main window.  It uses the dialog theme,
  whatever hsDialogSkin.UseTheme was last given.

  Copyright (c) 2021-2026 Tony Stone - MIT, see LICENSE.
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, LCLType, LCLIntf,
  InkPage, hsSurface, hsSkin, hsDialogSkin, hsUpdater;

type
  TAboutBox = class(TForm)
    Page: TInkPage;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PageLinkClick(Sender: TObject; const URL: string);
  private
    FSkin: TArtSurface;
    FTheme: TTheme;
    FScale: Single;
    function PageHTML: string;
    function PageStyle: string;
  end;

{ Shows the box modally. }
procedure ShowAboutBox(AOwner: TComponent);

implementation

{$R *.lfm}

const
  APP_NAME = 'Heckers Sketch';

procedure ShowAboutBox(AOwner: TComponent);
var
  Box: TAboutBox;
begin
  Box := TAboutBox.Create(AOwner);
  try
    Box.ShowModal;
  finally
    Box.Free;
  end;
end;

procedure TAboutBox.FormCreate(Sender: TObject);
begin
  FTheme := hsDialogSkin.DlgTheme;
  FScale := EnsureRange(Screen.PixelsPerInch / 96, 1.0, 3.0);
  hsDialogSkin.ThemeForm(Self);
  Color := PixToColor(FTheme.Shell2);
  { the designed size is for a desktop; shrink to fit smaller screens }
  with Screen.WorkAreaRect do
  begin
    if ClientWidth > (Right - Left) * 9 div 10 then
      ClientWidth := (Right - Left) * 9 div 10;
    if ClientHeight > (Bottom - Top) * 9 div 10 then
      ClientHeight := (Bottom - Top) * 9 div 10;
  end;
  { the page sits inside the painted frame, with the shell showing round it }
  Page.Color := PixToColor(FTheme.Panel);
  Page.Font.Color := PixToColor(FTheme.Text);
  Page.StyleSheet.Text := PageStyle;
  Page.LoadHTML(PageHTML);
end;

procedure TAboutBox.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FSkin);
end;

{ CSS built from the program's theme so the page matches the window. }
function TAboutBox.PageStyle: string;

  function Hex(const P: TPix): string;
  begin
    Result := Format('#%.2x%.2x%.2x', [P.R, P.G, P.B]);
  end;

var
  Base: Integer;
begin
  Base := Max(11, Round(14 * FScale));
  Result :=
    'html { scrollbar-color: ' + Hex(FTheme.Accent) + ' ' +
      Hex(MixPix(FTheme.Panel, Pix(0, 0, 0), 0.25)) + '; scrollbar-width: thin }' +
    ' body { background: ' + Hex(FTheme.Panel) + '; color: ' +
      Hex(FTheme.TextDim) + '; font-size: ' + IntToStr(Base) +
      'px; line-height: 1.55; padding: ' + IntToStr(Round(18 * FScale)) + 'px }' +
    ' h1 { color: ' + Hex(FTheme.Text) + '; font-size: ' +
      IntToStr(Round(Base * 1.9)) + 'px; margin-top: 0; margin-bottom: 2px }' +
    ' h2 { color: ' + Hex(FTheme.Accent) + '; font-size: ' +
      IntToStr(Round(Base * 1.15)) + 'px; margin-top: ' +
      IntToStr(Round(22 * FScale)) + 'px; margin-bottom: 6px;' +
      ' text-transform: uppercase }' +
    ' p { margin-top: 0; margin-bottom: ' + IntToStr(Round(10 * FScale)) + 'px }' +
    ' .lede { color: ' + Hex(FTheme.Accent) + '; margin-bottom: ' +
      IntToStr(Round(16 * FScale)) + 'px }' +
    ' strong, b { color: ' + Hex(FTheme.Text) + ' }' +
    ' a { color: ' + Hex(FTheme.Accent) + ' }' +
    ' .signed { color: ' + Hex(FTheme.TextDim) + '; font-style: italic;' +
      ' text-align: right; margin-top: ' + IntToStr(Round(18 * FScale)) + 'px }' +
    ' table.credits { width: 100%; border-collapse: separate;' +
      ' border-spacing: ' + IntToStr(Round(6 * FScale)) + 'px }' +
    ' table.credits td { background: ' +
      Hex(MixPix(FTheme.Panel, FTheme.PanelHi, 0.55)) + '; color: ' +
      Hex(FTheme.TextDim) + '; border: 1px solid ' +
      Hex(MixPix(FTheme.Panel, FTheme.Text, 0.18)) + '; border-radius: 8px;' +
      ' padding: ' + IntToStr(Round(9 * FScale)) + 'px; width: 50%;' +
      ' valign: top }' +
    ' table.credits a { font-weight: bold; text-decoration: none }';
end;

{ The page text: what the program is, then credits for what it is built on. }
function TAboutBox.PageHTML: string;
begin
  Result :=
    '<h1>' + APP_NAME + '</h1>' +
    '<p class="lede">NozelFab Incorporated &middot; ' + CurrentVersion + '</p>' +

    '<p>A 3D sketching program that gets the measurements right.  Pick a ' +
    'scale, put the cursor on a point, and type 12&#39;6&quot; to draw ' +
    'exactly that.  Lines, arcs, circles, push/pull, notes and a tape ' +
    'measure, in 3D, plan or isometric, and it prints at true scale.</p>' +

    '<h2>Standing on</h2>' +
    '<table class="credits">' +
    '<tr>' +
    '<td><a href="https://www.freepascal.org/">Free Pascal</a> and ' +
    '<a href="https://www.lazarus-ide.org/">Lazarus</a><br>' +
    'One source, every desktop.</td>' +
    '<td><a href="https://github.com/bgrabitmap/bgrabitmap">BGRABitmap</a> ' +
    'and BGRAControls<br>' +
    'The bitmaps, and the buttons round them.</td>' +
    '</tr><tr>' +
    '<td><a href="https://github.com/TonyStone31/LazInk">LazInk</a><br>' +
    'Ours.  It draws this page and the manual - HTML in a native control, ' +
    'no browser near it.</td>' +
    '<td><a href="https://github.com/Xelitan/Pure-Pascal-Webp-for-Delphi-Lazarus-Free-Pascal">' +
    'Xelitan&#39;s WebP encoder</a><br>' +
    'Pure Pascal, MIT.  It is why a film exports as a WebP with nothing ' +
    'shipped beside the program.  Thank you.</td>' +
    '</tr></table>' +

    '<p class="signed">Esc closes this.</p>';
end;

{ Only web links are opened. }
procedure TAboutBox.PageLinkClick(Sender: TObject; const URL: string);
begin
  if (Pos('http://', URL) = 1) or (Pos('https://', URL) = 1) then
    OpenURL(URL);
end;

{ Paints the shell and frame.  The surface follows the window's real size,
  not the size first asked for. }
procedure TAboutBox.FormPaint(Sender: TObject);
begin
  if (FSkin = nil) or (FSkin.Width <> ClientWidth) or
     (FSkin.Height <> ClientHeight) then
  begin
    FreeAndNil(FSkin);
    FSkin := TArtSurface.Create(Max(1, ClientWidth), Max(1, ClientHeight));
  end;
  PaintShell(FSkin, FTheme);
  FSkin.RoundFrame(Rect(1, 1, ClientWidth - 1, ClientHeight - 1),
    Round(14 * FScale), 2.0, FTheme.Accent, 0.85);
  FSkin.DrawTo(Canvas, 0, 0);
end;

procedure TAboutBox.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) or (Key = VK_RETURN) or (Key = VK_F1) then
  begin
    Close;
    Key := 0;
  end;
end;

end.
