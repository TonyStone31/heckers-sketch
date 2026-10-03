unit hsHelpView;

{ The manual viewer.  Shows the website's pages from the local copy (see
  hsHelpDocs) in a LazInk TInkPage.  It is a page viewer, not a browser:
  links off the manual go to the real browser.  Missing or stale pages are
  fetched in the background while whatever is there is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ComCtrls, ExtCtrls,
  LCLType, LCLIntf, BCPanel, BCButton, InkPage;

type
  { The page theme switch, same three as the website.  Auto follows the
    program's theme. }
  THelpTheme = (htAuto, htLight, htDark);

  THelpForm = class(TForm)
    btnBack: TBCButton;
    btnForward: TBCButton;
    btnContents: TBCButton;
    btnFind: TBCButton;
    btnRefresh: TBCButton;
    btnWeb: TBCButton;
    btnEmptyGet: TBCButton;
    btnEmptyWeb: TBCButton;
    lblTitle: TLabel;
    lblNotice: TLabel;
    lblEmptyTitle: TLabel;
    lblEmptyText: TLabel;
    pbNotice: TProgressBar;
    pbEmpty: TProgressBar;
    pnlBar: TBCPanel;
    pnlNotice: TBCPanel;
    pnlEmpty: TBCPanel;
    Page: TInkPage;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnBackClick(Sender: TObject);
    procedure btnForwardClick(Sender: TObject);
    procedure btnContentsClick(Sender: TObject);
    procedure btnFindClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnWebClick(Sender: TObject);
    procedure PageLinkClick(Sender: TObject; const URL: string);
    procedure PageNavigate(Sender: TObject);
  public
    { the window is kept between opens and the theme may change while it
      is hidden, so it is dressed again on each open }
    procedure Dress;
  private
    function PageIsLight: Boolean;
    function ThemeWord: string;
    procedure LoadThemeChoice;
    procedure SaveThemeChoice;
    procedure CycleTheme;
    function PageWithMode(const HTML: string): string;
    procedure GoToPage(const PathOrURI: string);
  private
    FWanted: string;        { the page asked for, relative to the folder }
    FFetching: Boolean;
    { the page theme switch setting }
    FThemeChoice: THelpTheme;
    procedure ShowPages(const Rel: string);
    procedure ShowEmpty(const Why: string);
    procedure Notice(const S: string; Busy: Boolean);
    procedure Fetch(Loud: Boolean);
    procedure UpdateButtons;
    function PageRelative: string;
    function LocalFileForWeb(const URL: string): string;
  public
    { Progress and finish of a fetch, this window's own or one the program
      started and passes on here. }
    procedure FetchProgress(BytesReceived, TotalBytes: Int64);
    procedure FetchDone(Sender: TObject);
    { Rel is a page like 'tools/arc.html' with an optional #anchor; empty
      means the contents page. }
    procedure OpenAt(const Rel: string);
  end;

var
  HelpForm: THelpForm = nil;

{ Creates the help window on first use and shows it at Rel. }
procedure OpenHelpWindow(const Rel: string = '');

implementation

{$R *.lfm}

uses
  hsHelpDocs, hsUpdater, hsNet, hsDialogSkin, hsSurface, hsHelpImage, hsPaths,
  IniFiles, URIParser;

procedure OpenHelpWindow(const Rel: string);
begin
  if HelpForm = nil then
    Application.CreateForm(THelpForm, HelpForm)
  else
    { the theme may have changed while it was hidden }
    HelpForm.Dress;
  HelpForm.OpenAt(Rel);
end;

procedure THelpForm.FormCreate(Sender: TObject);
begin
  LoadThemeChoice;
  Dress;
  { touch drags scroll, the mouse selects; LazInk tells them apart }
  Page.DragScroll := True;
  Page.CopyMenu := True;
end;

procedure THelpForm.FormDestroy(Sender: TObject);
begin
  if HelpForm = Self then HelpForm := nil;
end;

procedure THelpForm.FormShow(Sender: TObject);
begin
  UpdateButtons;
end;

{ Hide rather than free, so the next open returns to the same page. }
procedure THelpForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure THelpForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  { Esc closes the window unless the find bar is open; with KeyPreview the
    form sees Esc before the bar does }
  if (Key = VK_ESCAPE) and not Page.FindBarVisible then
  begin
    Close;
    Key := 0;
  end
  else if (Key = VK_HOME) and (ssAlt in Shift) then
  begin
    btnContentsClick(nil);
    Key := 0;
  end;
end;

{ Themes the window chrome; the page itself uses the manual's stylesheet. }
procedure THelpForm.Dress;
begin
  hsDialogSkin.SkinForm(Self);
  { panel color, so the lighter buttons stand out from the bar }
  hsDialogSkin.SkinPanel(pnlBar, False, 0);
  hsDialogSkin.SkinPanel(pnlNotice, False, 0);
  hsDialogSkin.SkinPanel(pnlEmpty, False, 0);
  hsDialogSkin.SkinButton(btnBack, bkPlain);
  hsDialogSkin.SkinButton(btnForward, bkPlain);
  hsDialogSkin.SkinButton(btnContents, bkPlain);
  hsDialogSkin.SkinButton(btnFind, bkPlain);
  hsDialogSkin.SkinButton(btnRefresh, bkQuiet);
  hsDialogSkin.SkinButton(btnWeb, bkQuiet);
  hsDialogSkin.SkinButton(btnEmptyGet, bkGo);
  hsDialogSkin.SkinButton(btnEmptyWeb, bkPlain);
  { rounded corners show the button's Color; match the bar, not the form }
  btnBack.Color := pnlBar.Color;
  btnForward.Color := pnlBar.Color;
  btnContents.Color := pnlBar.Color;
  btnFind.Color := pnlBar.Color;
  btnRefresh.Color := pnlBar.Color;
  btnWeb.Color := pnlBar.Color;
  btnEmptyGet.Color := pnlEmpty.Color;
  btnEmptyWeb.Color := pnlEmpty.Color;
  lblTitle.Font.Color := PixToColor(DlgTheme.Text);
  lblNotice.Font.Color := PixToColor(DlgTheme.Text);
  lblEmptyTitle.Font.Color := PixToColor(DlgTheme.Text);
  lblEmptyText.Font.Color := PixToColor(DlgTheme.TextDim);
  Page.Color := PixToColor(DlgTheme.Panel);
  Page.Font.Color := PixToColor(DlgTheme.Text);
end;

{ Whether to show the light palette.  Auto follows the program's theme,
  since LazInk cannot judge the stylesheet's media query; Light and Dark are
  the reader's override from the switch on each page. }
function THelpForm.PageIsLight: Boolean;
begin
  case FThemeChoice of
    htLight: Result := True;
    htDark: Result := False;
  else
    Result := DlgTheme.Panel.R + DlgTheme.Panel.G + DlgTheme.Panel.B >= 3 * 128;
  end;
end;

{ The switch's label, in the website's words. }
function THelpForm.ThemeWord: string;
begin
  case FThemeChoice of
    htLight: Result := 'Light';
    htDark: Result := 'Dark';
  else Result := 'Auto';
  end;
end;

{ The reader's choice is kept in the program's config file. }
procedure THelpForm.LoadThemeChoice;
var
  Ini: TIniFile;
begin
  FThemeChoice := htAuto;
  if not FileExists(ConfigFile) then Exit;
  Ini := TIniFile.Create(ConfigFile);
  try
    case LowerCase(Ini.ReadString('look', 'helptheme', 'auto')) of
      'light': FThemeChoice := htLight;
      'dark': FThemeChoice := htDark;
    end;
  finally
    Ini.Free;
  end;
end;

procedure THelpForm.SaveThemeChoice;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ConfigFile);
  try
    Ini.WriteString('look', 'helptheme', LowerCase(ThemeWord));
  finally
    Ini.Free;
  end;
end;

{ The page with style-light.css linked in after style.css when the page
  should be light.  LazInk only reads custom properties from :root and the
  page's rules beat an outside stylesheet, so a later linked sheet is the
  way that works. }
function THelpForm.PageWithMode(const HTML: string): string;
var
  Low, Prefix: string;
  P, Q: Integer;
begin
  Result := HTML;
  { In a browser theme.js writes the switch's state in; no script runs
    here, so do the same substitution. }
  Result := StringReplace(Result, '#theme" title="Light or dark">Theme</a>',
    '#theme" title="Light or dark">Theme: ' + ThemeWord + '</a>',
    [rfReplaceAll, rfIgnoreCase]);
  if not PageIsLight then Exit;
  Low := LowerCase(Result);
  P := Pos('style.css"', Low);
  if P <= 0 then Exit;
  { same relative prefix as style.css; pages under tools/ use ../ }
  Q := P;
  while (Q > 1) and (Low[Q - 1] <> '"') do Dec(Q);
  Prefix := Copy(Result, Q, P - Q);
  P := Pos('>', Low, P);
  if P <= 0 then Exit;
  Insert(LineEnding + '<link rel="stylesheet" href="' + Prefix +
    'style-light.css">', Result, P + 1);
end;

{ Every page load goes through here so each carries the light/dark mode.
  Back and Forward replay what was loaded rather than rereading the file. }
procedure THelpForm.GoToPage(const PathOrURI: string);
var
  Path, Anchor, Src, Local: string;

  L: TStringList;
  P: Integer;
begin
  Path := PathOrURI;
  Anchor := '';
  P := Pos('#', Path);
  if P > 0 then
  begin
    Anchor := Copy(Path, P + 1, MaxInt);
    Delete(Path, P, MaxInt);
  end;
  { Must be two variables.  URIToFilename's second parameter is "out",
    which FPC clears on entry, so passing Path twice wipes the URI first. }
  if LowerCase(Copy(Path, 1, 7)) = 'file://' then
    if URIToFilename(Path, Local) then Path := Local else Path := '';
  if (Path = '') or not FileExists(Path) or
     (LowerCase(ExtractFileExt(Path)) <> '.html') then
  begin
    { not one of ours - hand it to the renderer as it is }
    if FileExists(Path) then Page.LoadFromFile(Path)
    else Page.LoadFromURL(PathOrURI);
    if Anchor <> '' then Page.JumpToAnchor(Anchor);
    Exit;
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(Path);
    Src := L.Text;
  finally
    L.Free;
  end;
  Page.LoadHTML(PageWithMode(Src), FilenameToURI(ExpandFileName(Path)));
  if Anchor <> '' then Page.JumpToAnchor(Anchor);
end;

procedure THelpForm.OpenAt(const Rel: string);
var
  R: TRect;
begin
  FWanted := Rel;
  { the designed size is for a desktop; shrink to fit smaller screens }
  if not Visible then
  begin
    R := Screen.WorkAreaRect;
    if Width > (R.Right - R.Left) * 9 div 10 then
      Width := (R.Right - R.Left) * 9 div 10;
    if Height > (R.Bottom - R.Top) * 9 div 10 then
      Height := (R.Bottom - R.Top) * 9 div 10;
  end;
  if LocalHelpIndex <> '' then ShowPages(Rel)
  else ShowEmpty('');
  Show;
  BringToFront;
  { Fetch missing or stale pages.  Opening the manual is an explicit ask,
    so this ignores the auto-update setting, but not --offline. }
  if HelpIsStale(CurrentVersion) and not NetOffline then Fetch(False);
end;

procedure THelpForm.ShowPages(const Rel: string);
var
  Index, Folder, Target, Anchor: string;
  P: Integer;
begin
  Index := LocalHelpIndex;
  if Index = '' then
  begin
    ShowEmpty('');
    Exit;
  end;
  Folder := ExtractFilePath(Index);
  Target := Rel;
  Anchor := '';
  P := Pos('#', Target);
  if P > 0 then
  begin
    Anchor := Copy(Target, P, MaxInt);
    Delete(Target, P, MaxInt);
  end;
  if (Target = '') or not FileExists(Folder + SetDirSeparators(Target)) then
    Target := 'index.html';
  pnlEmpty.Visible := False;
  Page.Visible := True;
  try
    GoToPage(Folder + SetDirSeparators(Target) + Anchor);
  except
    on E: Exception do
      ShowEmpty('The page could not be read: ' + E.Message);
  end;
  UpdateButtons;
end;

procedure THelpForm.ShowEmpty(const Why: string);
begin
  Page.Visible := False;
  pnlEmpty.Visible := True;
  if Why <> '' then
    lblEmptyText.Caption := Why
  else if NetOffline then
    lblEmptyText.Caption := 'This copy was started with --offline, so it ' +
      'will not download them.  They are on the web too.'
  else
    lblEmptyText.Caption := 'They come from this version''s release on ' +
      'GitHub, a few megabytes, and are kept in a folder called help beside ' +
      'the program - so they are still here next time, with or without the ' +
      'internet.';
  pbEmpty.Visible := FFetching;
  btnEmptyGet.Enabled := not FFetching and not NetOffline;
  UpdateButtons;
end;

procedure THelpForm.Notice(const S: string; Busy: Boolean);
begin
  lblNotice.Caption := S;
  pbNotice.Visible := Busy;
  pnlNotice.Visible := S <> '';
end;

procedure THelpForm.Fetch(Loud: Boolean);
begin
  if NetOffline then
  begin
    Notice('Started with --offline - nothing was downloaded.', False);
    Exit;
  end;
  if FFetching then Exit;
  FFetching := True;
  pbNotice.Position := 0;
  pbEmpty.Position := 0;
  if LocalHelpIndex = '' then
    ShowEmpty('Downloading the help pages...')
  else
    Notice('Getting the help pages for ' + CurrentVersion + '...', True);
  { if the program already started a fetch, wait; it passes the result on }
  if not StartHelpFetch(CurrentVersion, @FetchProgress, @FetchDone) then
    Notice('The help pages are already being downloaded...', True);
  if Loud then btnRefresh.Enabled := False;
end;

procedure THelpForm.FetchProgress(BytesReceived, TotalBytes: Int64);
var
  Pct: Integer;
begin
  { size unknown: keep the bar moving anyway }
  if TotalBytes > 0 then
    Pct := Round(BytesReceived * 100.0 / TotalBytes)
  else
    Pct := (BytesReceived div (256 * 1024)) mod 100;
  pbNotice.Position := Pct;
  pbEmpty.Position := Pct;
end;

procedure THelpForm.FetchDone(Sender: TObject);
var
  F: THelpFetch;
  Rel: string;
begin
  FFetching := False;
  btnRefresh.Enabled := True;
  F := Sender as THelpFetch;
  if F.OK then
  begin
    { back to the page that was showing, in the new copy }
    Rel := PageRelative;
    if Rel = '' then Rel := FWanted;
    ShowPages(Rel);
    Notice('', False);
  end
  else if LocalHelpIndex = '' then
    ShowEmpty('The help pages could not be downloaded - ' + F.Err + '.')
  else
    Notice('Could not get newer help pages - ' + F.Err +
      '.  Showing the ones already here.', False);
end;

{ The current page relative to the help folder, so it can be found again in
  a fresh copy or on the website. }
function THelpForm.PageRelative: string;
var
  Loc, Folder: string;
begin
  Result := '';
  Loc := Page.Location;
  if Pos('file://', Loc) = 1 then Delete(Loc, 1, 7);
  if LocalHelpIndex = '' then Exit;
  Folder := ExtractFilePath(LocalHelpIndex);
  if Pos(Folder, Loc) = 1 then
    Result := StringReplace(Copy(Loc, Length(Folder) + 1, MaxInt), PathDelim,
      '/', [rfReplaceAll]);
end;

{ Maps a link to the manual's website back to the local copy, so it stays in
  this window. }
function THelpForm.LocalFileForWeb(const URL: string): string;
var
  Rel: string;
begin
  Result := '';
  if (LocalHelpIndex = '') or (Pos(MANUAL_URL, URL) <> 1) then Exit;
  Rel := Copy(URL, Length(MANUAL_URL) + 1, MaxInt);
  if Pos('#', Rel) > 0 then Rel := Copy(Rel, 1, Pos('#', Rel) - 1);
  if Rel = '' then Rel := 'index.html';
  Result := ExtractFilePath(LocalHelpIndex) + SetDirSeparators(Rel);
  if not FileExists(Result) then Result := '';
end;

{ Steps the theme switch and reloads the page, since the palette is linked
  into the page text.  The page comes back scrolled to the top. }
procedure THelpForm.CycleTheme;
var
  Rel: string;
begin
  case FThemeChoice of
    htAuto: FThemeChoice := htLight;
    htLight: FThemeChoice := htDark;
  else FThemeChoice := htAuto;
  end;
  SaveThemeChoice;
  Rel := PageRelative;
  if Rel = '' then Rel := 'index.html';
  ShowPages(Rel);
end;

procedure THelpForm.PageLinkClick(Sender: TObject; const URL: string);
var
  Local, Ext: string;
begin
  { The theme switch is an ordinary link so both a browser and this window
    can act on it (see theme.js). }
  if (Length(URL) >= 6) and (LowerCase(Copy(URL, Length(URL) - 5, 6)) = '#theme') then
  begin
    CycleTheme;
    Exit;
  end;
  { A picture opens in the picture window.  This list must hold every
    image format the manual uses, or the picture falls through to the page
    loader and shows as binary text. }
  Ext := LowerCase(ExtractFileExt(URL));
  if (Page.ClickedLink.Image <> '') or (Ext = '.png') or
     (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.webp') or
     (Ext = '.bmp') then
  begin
    if Page.ClickedLink.Image <> '' then
      OpenPictureWindow(Page.ClickedLink.Image, lblTitle.Caption)
    else
      OpenPictureWindow(URL, lblTitle.Caption);
    Exit;
  end;
  Local := LocalFileForWeb(URL);
  if Local <> '' then
  begin
    GoToPage(Local + Copy(URL, Pos('#', URL + '#'), MaxInt));
    Exit;
  end;
  { anywhere else on the internet, or an e-mail address: the real browser }
  if (Pos('http://', URL) = 1) or (Pos('https://', URL) = 1) or
     (Pos('mailto:', URL) = 1) then
  begin
    OpenURL(URL);
    Exit;
  end;
  try
    GoToPage(URL);
  except
    on E: Exception do
      Notice('That page could not be opened - ' + E.Message, False);
  end;
end;

procedure THelpForm.PageNavigate(Sender: TObject);
begin
  UpdateButtons;
end;

{ Dims the text instead of disabling the button; BGRA's disabled look is a
  light gray hole on a dark bar.  The click handlers check for themselves. }
procedure Available(B: TBCButton; On_: Boolean);
var
  C: TColor;
begin
  if On_ then C := PixToColor(DlgTheme.Text)
  else C := Shade(PixToColor(DlgTheme.Panel), 0.35);
  B.StateNormal.FontEx.Color := C;
  B.StateHover.FontEx.Color := C;
  B.StateClicked.FontEx.Color := C;
  B.Tag := Ord(On_);
end;

procedure THelpForm.UpdateButtons;
var
  OnPage: Boolean;
  Ver: string;
begin
  OnPage := Page.Visible;
  Available(btnBack, OnPage and Page.CanGoBack);
  Available(btnForward, OnPage and Page.CanGoForward);
  Available(btnContents, OnPage);
  Available(btnFind, OnPage);
  btnRefresh.Enabled := not FFetching and not NetOffline;
  if OnPage and (Page.DocumentTitle <> '') then
    lblTitle.Caption := StringReplace(Page.DocumentTitle, ' - Heckers Sketch',
      '', [])
  else
    lblTitle.Caption := 'Help';
  Ver := LocalHelpVersion;
  if Ver <> '' then
    Caption := 'Heckers Sketch - Help  (pages from ' + Ver + ')'
  else
    Caption := 'Heckers Sketch - Help';
end;

procedure THelpForm.btnBackClick(Sender: TObject);
begin
  if Page.Visible and Page.CanGoBack then Page.Back;
end;

procedure THelpForm.btnForwardClick(Sender: TObject);
begin
  if Page.Visible and Page.CanGoForward then Page.Forward;
end;

procedure THelpForm.btnContentsClick(Sender: TObject);
begin
  if LocalHelpIndex <> '' then ShowPages('');
end;

procedure THelpForm.btnFindClick(Sender: TObject);
begin
  if Page.Visible then Page.ShowFindBar;
end;

procedure THelpForm.btnRefreshClick(Sender: TObject);
begin
  Fetch(True);
end;

procedure THelpForm.btnWebClick(Sender: TObject);
begin
  OpenURL(MANUAL_URL + PageRelative);
end;

end.
