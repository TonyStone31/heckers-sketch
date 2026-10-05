unit hsSendReport;

{ The window that shows a report going out, laid out like the update
  window.  Each stage is held on screen for a moment so the user can read
  what is leaving even on a fast machine. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, Graphics,
  InkPage, InkMarkdown, LCLType, BCButton, hsDialogSkin, BGRAFlashProgressBar, hsText;

type
  { progress of one file of the report }
  TSendState = (ssWaiting, ssEncrypting, ssSending, ssSent, ssFailed, ssNone);

  TSendFile = record
    What, Name_, Size, Encrypted, Why: string;
    State: TSendState;
  end;

  { TSendForm }

  TSendForm = class(TForm)
    lblStage: TLabel;
    lblDetail: TLabel;
    pbProgress: TBGRAFlashProgressBar;
    Page: TInkPage;
    btnClose: TBCButton;
    procedure btnCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FFailed, FDone: Boolean;
    FFiles: array of TSendFile;
    FFacts: TStringList;      { section TAB key TAB value, in the order given }
    FBanner, FBannerSub, FClosing: string;
    procedure PauseFor(Milliseconds: QWord);
    procedure Repaint_;
    function PageHTML: string;
  public
    constructor CreateSending(AOwner: TComponent; const Title: string);
    destructor Destroy; override;
    { shows a step and holds it for Hold milliseconds }
    procedure Stage(const AStage, ADetail: string; Percent: Integer;
      Hold: Integer = 450);
    { The file table.  Every file is listed as waiting before the first is
      sent, and its row updates as it goes; the page is redrawn each time. }
    function AddFile(const What, Name_, Size: string;
      State: TSendState = ssWaiting): Integer;
    procedure FileState(Idx: Integer; State: TSendState;
      const Encrypted: string = ''; const Why: string = '');
    { A summary line under the files.  The first two sections sit side by
      side; later ones run full width, for long values. }
    procedure Fact(const Section, Key, Value: string);
    { Shows the result banner and stays open until Close, so the user can
      see what went. }
    procedure Finish(const Msg, Detail, ClosingHTML: string; OK: Boolean);
  end;


implementation

{$R *.lfm}

const
  { HTML rather than Markdown, for status colors, small file name text and
    side-by-side cards. }
  PAGE_CSS =
    'body { background: #ffffff; color: #0f172a; font-size: 14px; ' +
    '       line-height: 1.45; margin: 0; padding: 18px 22px } ' +
    'h3 { font-size: 12px; color: #64748b; text-transform: uppercase; ' +
    '     margin-top: 18px; margin-bottom: 6px } ' +
    'table { width: 100%; border-collapse: collapse } ' +
    'th { text-align: left; background: #f1f5f9; color: #475569; ' +
    '     font-size: 12px; padding: 7px 10px; border: 1px solid #e2e8f0 } ' +
    'td { padding: 7px 10px; border: 1px solid #e2e8f0 } ' +
    'td.part { font-weight: bold; white-space: nowrap } ' +
    'td.file { font-size: 12px; font-family: monospace; color: #1e293b } ' +
    'td.num { text-align: right; color: #334155; white-space: nowrap } ' +
    'td.key { background: #f8fafc; color: #475569; font-size: 13px; ' +
    '         white-space: nowrap } ' +
    'td.val { font-size: 13px } ' +
    'td.banner { border: 0; border-radius: 8px; padding: 14px 18px; ' +
    '            color: #ffffff } ' +
    'td.b-ok  { background: #15803d } ' +
    'td.b-bad { background: #b91c1c } ' +
    'td.b-run { background: #1d4ed8 } ' +
    'div.title { font-size: 22px; font-weight: bold } ' +
    'div.sub { font-size: 14px; margin-top: 4px } ' +
    '.cards { display: grid; grid-template-columns: 1fr 1fr; gap: 16px } ' +
    'span.pill { border-radius: 10px; padding: 2px 10px; font-weight: bold } ' +
    'span.wait { background: #f1f5f9; color: #64748b } ' +
    'span.busy { background: #fef3c7; color: #92400e } ' +
    'span.send { background: #dbeafe; color: #1d4ed8 } ' +
    'span.ok   { background: #dcfce7; color: #15803d } ' +
    'span.bad  { background: #fee2e2; color: #b91c1c } ' +
    'li { margin-bottom: 4px; font-size: 13px } ' +
    'code { font-size: 12px } ' +
    'small { color: #64748b }';

constructor TSendForm.CreateSending(AOwner: TComponent; const Title: string);
begin
  inherited Create(AOwner);
  Caption := Title;
  FFailed := False;
  FDone := False;
  FFacts := TStringList.Create;
  { the frame is themed; the page stays white with its own colors }
  Page.Color := clWhite;
  Page.Font.Color := clBlack;
  Page.TextFormat := itfHTML;
  { Shown non-modal while sending.  On Windows a plain window shown while a
    modal wizard is up is disabled with everything else; naming the active
    form as popup parent keeps it enabled. }
  PopupMode := pmExplicit;
  if Screen.ActiveForm <> nil then PopupParent := Screen.ActiveForm
  else if AOwner is TCustomForm then PopupParent := TCustomForm(AOwner);
  Repaint_;
  Show;
  Application.ProcessMessages;
end;

destructor TSendForm.Destroy;
begin
  FFacts.Free;
  inherited Destroy;
end;

function TSendForm.PageHTML: string;
const
  PILL: array[TSendState] of string = ('wait', 'busy', 'send', 'ok', 'bad', 'wait');
  WORD_: array[TSendState] of string = ('waiting', 'encrypting', 'sending',
    'sent', 'did not go', 'not included');
var
  H: TStringList;
  Sections: TStringList;
  I, J: Integer;
  Sec, Line, Verdict: string;

  { one section's facts: its heading and a key/value table }
  function Card(const Name_: string): string;
  var
    K, P1, P2: Integer;
    L: string;
  begin
    Result := '<h3>' + HtmlEsc(Name_) + '</h3><table>';
    for K := 0 to FFacts.Count - 1 do
    begin
      L := FFacts[K];
      P1 := Pos(#9, L);
      if Copy(L, 1, P1 - 1) <> Name_ then Continue;
      Delete(L, 1, P1);
      P2 := Pos(#9, L);
      Result := Result + '<tr><td class="key">' + HtmlEsc(Copy(L, 1, P2 - 1)) +
        '</td><td class="val">' + HtmlEsc(Copy(L, P2 + 1, MaxInt)) + '</td></tr>';
    end;
    Result := Result + '</table>';
  end;

begin
  H := TStringList.Create;
  Sections := TStringList.Create;
  try
    H.Add('<html><head><meta charset="utf-8"><style>' + PAGE_CSS +
      '</style></head><body>');

    if FBanner <> '' then
    begin
      if not FDone then Sec := 'b-run'
      else if FFailed then Sec := 'b-bad' else Sec := 'b-ok';
      H.Add('<table><tr><td class="banner ' + Sec + '">' +
        '<div class="title">' + HtmlEsc(FBanner) + '</div>' +
        '<div class="sub">' + HtmlEsc(FBannerSub) + '</div></td></tr></table>');
    end;

    H.Add('<h3>Files</h3><table>');
    H.Add('<tr><th>Part</th><th>File</th><th>Size</th>' +
      '<th>Encrypted</th><th>Status</th></tr>');
    if Length(FFiles) = 0 then
      H.Add('<tr><td colspan="5"><small>getting ready</small></td></tr>');
    for I := 0 to High(FFiles) do
    begin
      Verdict := '<span class="pill ' + PILL[FFiles[I].State] + '">' +
        WORD_[FFiles[I].State] + '</span>';
      if FFiles[I].Why <> '' then
        Verdict := Verdict + '<br><small>' + HtmlEsc(FFiles[I].Why) + '</small>';
      Line := FFiles[I].Encrypted;
      if Line = '' then Line := '-';
      H.Add('<tr><td class="part">' + HtmlEsc(FFiles[I].What) + '</td>' +
        '<td class="file">' + HtmlEsc(FFiles[I].Name_) + '</td>' +
        '<td class="num">' + HtmlEsc(FFiles[I].Size) + '</td>' +
        '<td class="num">' + HtmlEsc(Line) + '</td>' +
        '<td>' + Verdict + '</td></tr>');
    end;
    H.Add('</table>');

    { sections in the order first named; the first two side by side }
    for I := 0 to FFacts.Count - 1 do
    begin
      Sec := Copy(FFacts[I], 1, Pos(#9, FFacts[I]) - 1);
      if Sections.IndexOf(Sec) < 0 then Sections.Add(Sec);
    end;
    J := 0;
    if Sections.Count >= 2 then
    begin
      H.Add('<div class="cards"><div>' + Card(Sections[0]) + '</div><div>' +
        Card(Sections[1]) + '</div></div>');
      J := 2;
    end;
    for I := J to Sections.Count - 1 do H.Add(Card(Sections[I]));

    H.Add(FClosing);
    H.Add('</body></html>');
    Result := H.Text;
  finally
    Sections.Free;
    H.Free;
  end;
end;

procedure TSendForm.Repaint_;
begin
  Page.Source := PageHTML;
  if not FDone then Page.ScrollTo(0);
  Application.ProcessMessages;
end;

function TSendForm.AddFile(const What, Name_, Size: string;
  State: TSendState): Integer;
begin
  Result := Length(FFiles);
  SetLength(FFiles, Result + 1);
  FFiles[Result].What := What;
  FFiles[Result].Name_ := Name_;
  FFiles[Result].Size := Size;
  FFiles[Result].State := State;
  Repaint_;
end;

procedure TSendForm.FileState(Idx: Integer; State: TSendState;
  const Encrypted: string; const Why: string);
begin
  if (Idx < 0) or (Idx > High(FFiles)) then Exit;
  FFiles[Idx].State := State;
  if Encrypted <> '' then FFiles[Idx].Encrypted := Encrypted;
  FFiles[Idx].Why := Why;
  Repaint_;
end;

procedure TSendForm.Fact(const Section, Key, Value: string);
begin
  if Trim(Value) = '' then Exit;
  FFacts.Add(Section + #9 + Key + #9 + Value);
end;

procedure TSendForm.PauseFor(Milliseconds: QWord);
var
  UntilTick: QWord;
begin
  UntilTick := GetTickCount64 + Milliseconds;
  repeat
    Application.ProcessMessages;
    Sleep(10);
  until GetTickCount64 >= UntilTick;
end;

procedure TSendForm.Stage(const AStage, ADetail: string; Percent: Integer;
  Hold: Integer);
begin
  lblStage.Caption := AStage;
  lblDetail.Caption := ADetail;
  pbProgress.Value := Percent;
  Application.ProcessMessages;
  PauseFor(Hold);
end;

procedure TSendForm.Finish(const Msg, Detail, ClosingHTML: string; OK: Boolean);
begin
  lblStage.Caption := Msg;
  lblDetail.Caption := Detail;
  FFailed := not OK;
  FDone := True;
  FBanner := Msg;
  FBannerSub := Detail;
  FClosing := ClosingHTML;
  if OK then pbProgress.Value := 100 else pbProgress.Value := 0;
  { the banner says it now, so the page takes over the labels' and bar's
    room }
  Page.SetBounds(Page.Left, lblStage.Top, Page.Width,
    Page.Top + Page.Height - lblStage.Top);
  lblStage.Visible := False;
  lblDetail.Visible := False;
  pbProgress.Visible := False;
  Repaint_;
  Page.ScrollTo(0);
  btnClose.Enabled := True;
  { Go modal now: a modal close works inside a wizard's modal loop, where
    closing a plain shown window does not on GTK. }
  Hide;
  ShowModal;
end;

procedure TSendForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
end;

{ A drawn button cannot be the default, so Enter is handled here once Close
  is enabled. }
procedure TSendForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_RETURN) and btnClose.Enabled then
  begin
    btnCloseClick(btnClose);
    Key := 0;
  end;
end;

procedure TSendForm.btnCloseClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

end.
