unit hsAssistant;

{ The assistant: a conversation about the sheet, in a window of its own so
  it can later dock under the source window.  Each question goes with the
  manual, the sheet and what is picked, as ticked; the answer streams in. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, LCLType,
  BCButton, InkLabel, BGRATheme, BGRAThemeCheckBox, InkMemo, InkCodeMemo,
  hsDrawing, hsSourceWindow, hsAssistantContext, hsAssistantChat;

type

  { TAssistantForm }

  TAssistantForm = class(TForm)
    pnlTop: TPanel;
    lblTitle: TInkLabel;
    lblWho: TInkLabel;
    btnSettings: TBCButton;
    chkOnTop: TBGRAThemeCheckBox;
    pnlGiven: TPanel;
    lblGiven: TInkLabel;
    chkManual: TBGRAThemeCheckBox;
    chkSheet: TBGRAThemeCheckBox;
    chkPicked: TBGRAThemeCheckBox;
    btnShowGiven: TBCButton;
    memChat: TInkMemo;
    pnlAsk: TPanel;
    memAsk: TInkCodeMemo;
    btnSend: TBCButton;
    btnClear: TBCButton;
    lblStatus: TInkLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnShowGivenClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure chkGivenChange(Sender: TObject);
    procedure chkOnTopChange(Sender: TObject);
  private
    FSettings: TAssistantSettings;
    FLoading: Boolean;
    FChat: TChatThread;
    FHistory: TChatMsgs;
    FAnswer: string;
    FThought: Integer;
    procedure ChatPiece(Sender: TObject; const Piece: string);
    procedure ChatThink(Sender: TObject; const Piece: string);
    procedure ChatDone(Sender: TObject; OK: Boolean; const Err: string);
    procedure Busy(On: Boolean);
    procedure ShowWho;
    procedure ShowGiven;
    procedure Say(const Who, Txt: string; C: TColor);
    function SheetText(out Lines: Integer; out Picked: string; out NPicked: Integer): string;
    function GivenText: string;
    function SystemParts: TChatSystem;
  public
    { the same questions the source window asks the sheet }
    OnAskSource: TSourceAskSource;
    OnAskPicked: TSourceAskPicked;
  end;

var
  AssistantForm: TAssistantForm = nil;

{ Opens the one assistant window, making it on first use. }
procedure ShowAssistant(AOwner: TComponent; AskSource: TSourceAskSource;
  AskPicked: TSourceAskPicked);

implementation

{$R *.lfm}

uses
  hsDialogSkin, hsSurface, hsLongText, hsAssistantSettings, InkMarkdown;

procedure ShowAssistant(AOwner: TComponent; AskSource: TSourceAskSource;
  AskPicked: TSourceAskPicked);
begin
  if AssistantForm = nil then AssistantForm := TAssistantForm.Create(AOwner);
  AssistantForm.OnAskSource := AskSource;
  AssistantForm.OnAskPicked := AskPicked;
  AssistantForm.Show;
  AssistantForm.BringToFront;
end;

procedure TAssistantForm.FormCreate(Sender: TObject);
begin
  hsDialogSkin.ThemeForm(Self);
  FLoading := True;
  FSettings := LoadAssistantSettings;
  chkManual.Checked := FSettings.SendManual;
  chkSheet.Checked := FSettings.SendSheet;
  chkPicked.Checked := FSettings.SendPicked;
  FLoading := False;
  ShowWho;
  Say('', 'Ask about this sheet, or ask for a change to it.  A change comes ' +
    'back as Heck, to look over before it goes into the drawing.',
    PixToColor(DlgTheme.TextDim));
end;

procedure TAssistantForm.FormDestroy(Sender: TObject);
begin
  if FChat <> nil then FChat.Detach;
  FChat := nil;
  if AssistantForm = Self then AssistantForm := nil;
end;

procedure TAssistantForm.FormActivate(Sender: TObject);
begin
  ShowGiven;
end;

procedure TAssistantForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { Enter sends; Ctrl+Enter or Shift+Enter is a new line in the question }
  if (Key = VK_RETURN) and (Shift * [ssCtrl, ssShift, ssAlt] = []) and memAsk.Focused then
  begin
    btnSendClick(nil);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    Close;
    Key := 0;
  end;
end;

procedure TAssistantForm.ShowWho;
var
  S: string;
begin
  S := TextSpan(PROVIDERS[ProviderOf(FSettings)], True, False);
  if ChatModel(FSettings) <> '' then S := S + DimSpan(', ' + ChatModel(FSettings), False);
  if (ProviderOf(FSettings) <> PROV_OWN) and (LoadAssistantKey = '') then
    S := S + InkSpan(' - no key yet', ToneColor(False), False, False);
  lblWho.Caption := S;
end;

{ what the sheet would give, on the status line }
procedure TAssistantForm.ShowGiven;
var
  N, NP: Integer;
  Picked, S: string;
begin
  SheetText(N, Picked, NP);
  if N = 0 then S := DimSpan('No sheet open', False)
  else
  begin
    S := DimSpan('This sheet is ', False) + TextSpan(IntToStr(N), True) + DimSpan(' lines of Heck; ', False);
    if NP > 0 then S := S + TextSpan(IntToStr(NP), True) + DimSpan(' picked, on lines ' + Picked, False)
    else S := S + DimSpan('nothing picked', False);
  end;
  lblStatus.Caption := S;
end;

procedure TAssistantForm.Say(const Who, Txt: string; C: TColor);
begin
  if Who = '' then memChat.Append(InkSpan(Txt, C, False, False))
  else memChat.Append(InkSpan(Who + ':', C, True) + ' ' + TextSpan(Txt, False, False));
end;

{ The sheet as Heck, and the lines of what is picked, as "12-18, 40". }
function TAssistantForm.SheetText(out Lines: Integer; out Picked: string; out NPicked: Integer): string;
var
  L, Hints, Names: TStringList;
  First, Last, LineThing, Sel: TIntArrayW;
  Sheet: string;
  On: array of Boolean;
  I, K, A: Integer;
begin
  Result := '';
  Lines := 0;
  Picked := '';
  NPicked := 0;
  if not Assigned(OnAskSource) then Exit;
  L := TStringList.Create;
  Hints := TStringList.Create;
  Names := TStringList.Create;
  try
    OnAskSource(L, Hints, Names, First, Last, LineThing, Sheet);
    Result := L.Text;
    Lines := L.Count;
    if not Assigned(OnAskPicked) then Exit;
    OnAskPicked(Sel);
    NPicked := Length(Sel);
    SetLength(On, L.Count);
    for I := 0 to High(Sel) do
      if (Sel[I] <= High(First)) and (First[Sel[I]] >= 0) then
        for K := First[Sel[I]] to Last[Sel[I]] do
          if K < Length(On) then On[K] := True;
    I := 0;
    while I < Length(On) do
    begin
      if not On[I] then begin Inc(I); Continue; end;
      A := I;
      while (I + 1 < Length(On)) and On[I + 1] do Inc(I);
      if Picked <> '' then Picked := Picked + ', ';
      if A = I then Picked := Picked + IntToStr(A + 1)
      else Picked := Picked + IntToStr(A + 1) + '-' + IntToStr(I + 1);
      Inc(I);
    end;
  finally
    Names.Free;
    Hints.Free;
    L.Free;
  end;
end;

{ everything that would go with a question, as it would go }
function TAssistantForm.GivenText: string;
var
  Manual, Missing, Sheet, Picked: string;
  N, NP: Integer;
begin
  Result := '';
  if chkManual.Checked then
  begin
    Manual := ManualText(Missing);
    if Missing <> '' then
      Result := Result + '(the manual pages not found here: ' + Missing + ')' + LineEnding + LineEnding;
    Result := Result + Manual + LineEnding + LineEnding;
  end;
  Sheet := SheetText(N, Picked, NP);
  if chkSheet.Checked and (N > 0) then
    Result := Result + '######## the sheet' + LineEnding + LineEnding + Sheet + LineEnding;
  if chkPicked.Checked and (NP > 0) then
    Result := Result + '######## picked: lines ' + Picked + LineEnding;
  if Result = '' then Result := 'Nothing: every box is unticked.';
end;

procedure TAssistantForm.btnSettingsClick(Sender: TObject);
begin
  if EditAssistantSettings(Self) then
  begin
    FSettings := LoadAssistantSettings;
    ShowWho;
  end;
end;

procedure TAssistantForm.btnShowGivenClick(Sender: TObject);
begin
  TLongTextForm.ShowText(Self, 'What the assistant would be given', GivenText);
end;

{ what goes ahead of the conversation, as the boxes are ticked }
function TAssistantForm.SystemParts: TChatSystem;
var
  Manual, Missing, Sheet, Picked: string;
  N, NP: Integer;
begin
  Manual := '';
  if chkManual.Checked then Manual := ManualText(Missing);
  Sheet := SheetText(N, Picked, NP);
  if not chkSheet.Checked then Sheet := '';
  if not chkPicked.Checked or (NP = 0) then Picked := '';
  Result := ChatSystem(Manual, Sheet, Picked);
end;

procedure TAssistantForm.Busy(On: Boolean);
begin
  if On then btnSend.Caption := 'Stop' else btnSend.Caption := 'Send';
  btnClear.Enabled := not On;
  btnSettings.Enabled := not On;
end;

procedure TAssistantForm.btnSendClick(Sender: TObject);
var
  Q, Why, Key: string;
  Msgs: TChatMsgs;
begin
  { Send stops an answer still coming }
  if FChat <> nil then
  begin
    FChat.Stop;
    Exit;
  end;
  Q := Trim(memAsk.Text);
  if Q = '' then Exit;
  Key := LoadAssistantKey;
  Why := ChatRefusal(FSettings, Key);
  if Why <> '' then
  begin
    Say('', Why, ToneColor(False));
    Exit;
  end;
  memChat.AppendBlock(Q, itfPlain, FieldColor, 24);
  memAsk.Text := '';
  SetLength(FHistory, Length(FHistory) + 1);
  FHistory[High(FHistory)].Role := 'user';
  FHistory[High(FHistory)].Text := Q;
  { the manual and the sheet as they are now, then the conversation }
  Msgs := Copy(FHistory);
  FAnswer := '';
  FThought := 0;
  memChat.AppendBlock('...', itfMarkdown);
  Busy(True);
  FChat := TChatThread.Create(FSettings, Key, SystemParts, Msgs, @ChatPiece, @ChatDone, @ChatThink);
  ShowGiven;
end;

procedure TAssistantForm.ChatPiece(Sender: TObject; const Piece: string);
begin
  if (FAnswer = '') and (FThought > 0) then ShowGiven;
  FAnswer := FAnswer + Piece;
  memChat.ReplaceLast(FAnswer);
end;

{ a model reasoning before it answers: say so, and how far it has got }
procedure TAssistantForm.ChatThink(Sender: TObject; const Piece: string);
begin
  if FAnswer <> '' then Exit;
  if FThought = 0 then memChat.ReplaceLast('*thinking...*');
  Inc(FThought, Length(Piece));
  lblStatus.Caption := DimSpan('Thinking first - ', False) +
    TextSpan(IntToStr(FThought), True) + DimSpan(' characters so far', False);
end;

procedure TAssistantForm.ChatDone(Sender: TObject; OK: Boolean; const Err: string);
begin
  FChat := nil;
  Busy(False);
  if FAnswer <> '' then
  begin
    SetLength(FHistory, Length(FHistory) + 1);
    FHistory[High(FHistory)].Role := 'assistant';
    FHistory[High(FHistory)].Text := FAnswer;
  end
  else
  begin
    memChat.ReplaceLast('*(no answer)*');
    { a question with no answer leaves the conversation - two questions in a
      row are refused by many models - and goes back in the box to send again }
    if (Length(FHistory) > 0) and (FHistory[High(FHistory)].Role = 'user') then
    begin
      if Trim(memAsk.Text) = '' then memAsk.Text := FHistory[High(FHistory)].Text;
      SetLength(FHistory, Length(FHistory) - 1);
    end;
  end;
  if not OK then
    if Err = 'stopped' then Say('', 'Stopped.', PixToColor(DlgTheme.TextDim))
    else
    begin
      Say('', 'It went wrong: ' + Err, ToneColor(False));
      { the commonest one with a model on this machine }
      if (Pos('context', LowerCase(Err)) > 0) and (Pos('exceed', LowerCase(Err)) > 0) then
        Say('', 'The manual and this sheet do not fit in what the model was loaded ' +
          'with.  Load it with a longer context (32768 or more), or untick the manual or ' +
          'the sheet above.', PixToColor(DlgTheme.TextDim));
    end;
end;

procedure TAssistantForm.btnClearClick(Sender: TObject);
begin
  memChat.Lines.Clear;
  SetLength(FHistory, 0);
end;

procedure TAssistantForm.chkGivenChange(Sender: TObject);
begin
  if FLoading then Exit;
  FSettings.SendManual := chkManual.Checked;
  FSettings.SendSheet := chkSheet.Checked;
  FSettings.SendPicked := chkPicked.Checked;
  SaveAssistantSettings(FSettings);
end;

procedure TAssistantForm.chkOnTopChange(Sender: TObject);
begin
  hsDialogSkin.SetOnTop(Self, chkOnTop.Checked);
end;

end.
