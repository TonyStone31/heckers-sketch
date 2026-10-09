unit hsAssistantChat;

{ One question to an AI service and its answer, a piece at a time.  Two
  ways of asking: Anthropic's Messages API, and the chat-completions form
  OpenAI and most servers take, a model on this machine included.  No
  windows here, so the tests can run it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, hsAssistantContext;

type
  TChatMsg = record
    Role: string;    { 'user' or 'assistant' }
    Text: string;
  end;
  TChatMsgs = array of TChatMsg;

  { What goes ahead of the conversation: Fixed (what the assistant is for,
    and the manual) changes seldom and is cached where the service caches;
    Sheet (the drawing, what is picked) changes as the drawing does. }
  TChatSystem = record
    Fixed, Sheet: string;
  end;

  TChatPiece = procedure(Sender: TObject; const Piece: string) of object;
  TChatDone = procedure(Sender: TObject; OK: Boolean; const Err: string) of object;

  { Reads a streamed answer as it is written into it: "data: {...}" lines,
    each holding the next piece, in either service's shape.  A server that
    ignores streaming answers in one body, which Finish reads.  Raises
    EAbort from Write once Stopped. }
  TChatStream = class(TStream)
  private
    FLine: string;
    FAll: string;
    FStreamed: Boolean;
    FProblem: string;
    FOnPiece, FOnThink: TChatPiece;
    function PieceOf(const Json: string; Streamed: Boolean; const Field: string = 'content'): string;
    function ErrorOf(const Json: string): string;
    procedure TakeAnthropic(const Json: string);
    procedure TakeLine(const L: string);
  public
    Stopped: Boolean;
    { Anthropic's events rather than chat-completions chunks }
    Anthropic: Boolean;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    { what came in one body, when nothing streamed; '' otherwise }
    function Finish: string;
    { the reply as it came, for an error message }
    property All: string read FAll;
    { an error or a refusal the service sent in the stream; '' if none }
    property Problem: string read FProblem;
    property OnPiece: TChatPiece read FOnPiece write FOnPiece;
    { the model's reasoning before it answers, where a service sends it }
    property OnThink: TChatPiece read FOnThink write FOnThink;
  end;

  { The question on its own thread; OnPiece and OnDone run on the main
    thread.  Frees itself. }
  TChatThread = class(TThread)
  private
    FURL, FHeaders, FBody: string;
    FStream: TChatStream;
    FPiece, FErr: string;
    FOK: Boolean;
    FOnPiece, FOnThink: TChatPiece;
    FOnDone: TChatDone;
    procedure GotPiece(Sender: TObject; const Piece: string);
    procedure GotThink(Sender: TObject; const Piece: string);
    procedure SyncPiece;
    procedure SyncThink;
    procedure SyncDone;
  protected
    procedure Execute; override;
  public
    constructor Create(const S: TAssistantSettings; const Key: string;
      const Sys: TChatSystem; const Msgs: TChatMsgs; AOnPiece: TChatPiece;
      AOnDone: TChatDone; AOnThink: TChatPiece = nil);
    procedure Stop;
    { stops it and drops its events, for a window going away }
    procedure Detach;
  end;

const
  { asked when Settings leaves the model blank }
  ANTHROPIC_MODEL = 'claude-opus-5-5';

{ Where the question goes: the service's own address unless one is given;
  a chat-completions address gets /chat/completions added. }
function ChatURL(const S: TAssistantSettings): string;

{ The model asked for: as set, else the service's usual; '' lets a server
  of one's own use what it has loaded. }
function ChatModel(const S: TAssistantSettings): string;

{ The request, in the service's shape, streamed. }
function ChatBody(const S: TAssistantSettings; const Sys: TChatSystem; const Msgs: TChatMsgs): string;

{ The headers besides Content-Type: the key, and Anthropic's version. }
procedure ChatHeaders(const S: TAssistantSettings; const Key: string; H: TStrings);

{ '' when a question may go; else why not.  A key goes only over https or
  to this machine, and a service that needs a key or a model says so. }
function ChatRefusal(const S: TAssistantSettings; const Key: string): string;

{ What the assistant is told before the conversation, in its two parts. }
function ChatSystem(const Manual, Sheet, Picked: string): TChatSystem;

implementation

uses
  fpjson, jsonparser, hsNet;

const
  OWN_SERVER = 'http://localhost:1234/v1';
  OPENAI_SERVER = 'https://api.openai.com/v1';
  ANTHROPIC_SERVER = 'https://api.anthropic.com/v1/messages';

function ChatURL(const S: TAssistantSettings): string;
begin
  Result := Trim(S.Endpoint);
  case ProviderOf(S) of
    PROV_ANTHROPIC:
      if Result = '' then Result := ANTHROPIC_SERVER;
    PROV_OPENAI:
      if Result = '' then Result := OPENAI_SERVER;
  else
    if Result = '' then Result := OWN_SERVER;
  end;
  if ProviderOf(S) = PROV_ANTHROPIC then Exit;
  while (Result <> '') and (Result[Length(Result)] = '/') do SetLength(Result, Length(Result) - 1);
  { a bare server, http://localhost:1234, answers under /v1 }
  if (Pos('://', Result) > 0) and (Pos('/', Copy(Result, Pos('://', Result) + 3, MaxInt)) = 0) then
    Result := Result + '/v1';
  if LowerCase(Copy(Result, Length(Result) - 16, 17)) <> '/chat/completions' then
    Result := Result + '/chat/completions';
end;

function ChatModel(const S: TAssistantSettings): string;
begin
  Result := Trim(S.Model);
  if (Result = '') and (ProviderOf(S) = PROV_ANTHROPIC) then Result := ANTHROPIC_MODEL;
end;

function AnthropicBody(const S: TAssistantSettings; const Sys: TChatSystem;
  const Msgs: TChatMsgs): string;
var
  O, M, B, OC: TJSONObject;
  A, SysA: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    O.Add('model', ChatModel(S));
    O.Add('max_tokens', 64000);
    O.Add('stream', True);
    { the instructions and the manual, cached: they come again with every
      question; the sheet after them, as it is now }
    SysA := TJSONArray.Create;
    B := TJSONObject.Create;
    B.Add('type', 'text');
    B.Add('text', Sys.Fixed);
    B.Add('cache_control', TJSONObject.Create(['type', 'ephemeral']));
    SysA.Add(B);
    if Sys.Sheet <> '' then
      SysA.Add(TJSONObject.Create(['type', 'text', 'text', Sys.Sheet]));
    O.Add('system', SysA);
    { and the conversation so far, cached up to its end }
    O.Add('cache_control', TJSONObject.Create(['type', 'ephemeral']));
    { the model always reasons; summaries of it show progress, and effort
      says how hard }
    O.Add('thinking', TJSONObject.Create(['type', 'adaptive', 'display', 'summarized']));
    OC := TJSONObject.Create;
    if S.Think then OC.Add('effort', 'high') else OC.Add('effort', 'low');
    O.Add('output_config', OC);
    { a request a safety check declines goes on to another model, chosen
      by the service }
    O.Add('fallbacks', 'default');
    A := TJSONArray.Create;
    for I := 0 to High(Msgs) do
    begin
      M := TJSONObject.Create;
      M.Add('role', Msgs[I].Role);
      M.Add('content', Msgs[I].Text);
      A.Add(M);
    end;
    O.Add('messages', A);
    Result := O.AsJSON;
  finally
    O.Free;
  end;
end;

function CompletionsBody(const S: TAssistantSettings; const Sys: TChatSystem;
  const Msgs: TChatMsgs): string;
var
  O, M: TJSONObject;
  A: TJSONArray;
  I: Integer;
  T: string;
begin
  O := TJSONObject.Create;
  try
    if ChatModel(S) <> '' then O.Add('model', ChatModel(S));
    O.Add('stream', True);
    { a model that reasons answers sooner when told; OpenAI's least is low,
      a local server takes none; one that does not know it lets it pass }
    if not S.Think then
      if ProviderOf(S) = PROV_OPENAI then O.Add('reasoning_effort', 'low')
      else O.Add('reasoning_effort', 'none');
    A := TJSONArray.Create;
    T := Sys.Fixed;
    if Sys.Sheet <> '' then T := T + LineEnding + LineEnding + Sys.Sheet;
    A.Add(TJSONObject.Create(['role', 'system', 'content', T]));
    for I := 0 to High(Msgs) do
    begin
      M := TJSONObject.Create;
      M.Add('role', Msgs[I].Role);
      M.Add('content', Msgs[I].Text);
      A.Add(M);
    end;
    O.Add('messages', A);
    Result := O.AsJSON;
  finally
    O.Free;
  end;
end;

function ChatBody(const S: TAssistantSettings; const Sys: TChatSystem; const Msgs: TChatMsgs): string;
begin
  if ProviderOf(S) = PROV_ANTHROPIC then Result := AnthropicBody(S, Sys, Msgs)
  else Result := CompletionsBody(S, Sys, Msgs);
end;

procedure ChatHeaders(const S: TAssistantSettings; const Key: string; H: TStrings);
begin
  if ProviderOf(S) = PROV_ANTHROPIC then
  begin
    H.Add('x-api-key: ' + Key);
    H.Add('anthropic-version: 2023-06-01');
    H.Add('anthropic-beta: server-side-fallback-2026-07-01');
  end
  else if Key <> '' then
    H.Add('Authorization: Bearer ' + Key);
  H.Add('Accept: text/event-stream');
end;

function ChatRefusal(const S: TAssistantSettings; const Key: string): string;
var
  U, Host: string;
  K: Integer;
begin
  Result := '';
  if (ProviderOf(S) <> PROV_OWN) and (Key = '') then
    Exit(PROVIDERS[ProviderOf(S)] + ' wants a key - Settings takes one.');
  if (ProviderOf(S) = PROV_OPENAI) and (Trim(S.Model) = '') then
    Exit('OpenAI wants a model named in Settings.');
  U := LowerCase(ChatURL(S));
  if Copy(U, 1, 8) = 'https://' then Exit;
  if Copy(U, 1, 7) <> 'http://' then Exit('The address wants to start http:// or https://.');
  if Key = '' then Exit;
  Host := Copy(U, 8, MaxInt);
  K := Pos('/', Host);
  if K > 0 then SetLength(Host, K - 1);
  K := Pos(':', Host);
  if K > 0 then SetLength(Host, K - 1);
  if (Host <> 'localhost') and (Host <> '127.0.0.1') then
    Result := 'A key goes only over https, or to this machine.';
end;

function ChatSystem(const Manual, Sheet, Picked: string): TChatSystem;
begin
  Result.Fixed :=
    'You help someone draw in Heckers Sketch, a 3D sketching program.  ' +
    'Drawings are written in Heck, a plain-text language; the manual below ' +
    'is all of it.  Answer plainly and briefly.  When you change the ' +
    'drawing, give the whole changed sheet as Heck in one ```heck block, ' +
    'keeping every name and comment that is there; it is looked over ' +
    'before it is used.';
  if Manual <> '' then
    Result.Fixed := Result.Fixed + LineEnding + LineEnding + '# The manual' +
      LineEnding + LineEnding + Manual;
  Result.Sheet := '';
  if Sheet <> '' then
    Result.Sheet := '# The sheet as it stands' + LineEnding + LineEnding + '```heck' +
      LineEnding + Sheet + '```';
  if Picked <> '' then
    Result.Sheet := Result.Sheet + LineEnding + LineEnding + 'Picked on the sheet: lines ' +
      Picked + '.';
end;

{ TChatStream }

function TChatStream.PieceOf(const Json: string; Streamed: Boolean; const Field: string): string;
var
  D: TJSONData;
  C: TJSONArray;
  E: TJSONData;
begin
  Result := '';
  try
    D := GetJSON(Json);
  except
    Exit;
  end;
  try
    if not (D is TJSONObject) then Exit;
    C := TJSONObject(D).Find('choices', jtArray) as TJSONArray;
    if (C = nil) or (C.Count = 0) or not (C.Items[0] is TJSONObject) then Exit;
    if Streamed then E := TJSONObject(C.Items[0]).FindPath('delta.' + Field)
    else E := TJSONObject(C.Items[0]).FindPath('message.' + Field);
    if (E <> nil) and (E.JSONType = jtString) then Result := E.AsString;
  finally
    D.Free;
  end;
end;

{ a reply that is an error: {"error": "..."} or {"error": {"message": ...}},
  which some servers send with a 200; '' if it is not one }
function TChatStream.ErrorOf(const Json: string): string;
var
  D, E: TJSONData;
begin
  Result := '';
  if Pos('"error"', Json) = 0 then Exit;
  try
    D := GetJSON(Json);
  except
    Exit;
  end;
  try
    if not (D is TJSONObject) then Exit;
    E := TJSONObject(D).Find('error');
    if E = nil then Exit;
    if E.JSONType = jtString then Result := E.AsString
    else if (E is TJSONObject) and (TJSONObject(E).Find('message') <> nil) then
      Result := TJSONObject(E).Get('message', '')
    else Result := E.AsJSON;
  finally
    D.Free;
  end;
end;

{ one of Anthropic's events: text and thinking as they come, a refusal or
  an error kept for the end }
procedure TChatStream.TakeAnthropic(const Json: string);
var
  D, E: TJSONData;
  Kind, Delta: string;
begin
  try
    D := GetJSON(Json);
  except
    Exit;
  end;
  try
    if not (D is TJSONObject) then Exit;
    Kind := TJSONObject(D).Get('type', '');
    if Kind = 'content_block_delta' then
    begin
      E := TJSONObject(D).FindPath('delta.type');
      if E = nil then Exit;
      Delta := E.AsString;
      if Delta = 'text_delta' then
      begin
        E := TJSONObject(D).FindPath('delta.text');
        if (E <> nil) and Assigned(FOnPiece) then FOnPiece(Self, E.AsString);
      end
      else if Delta = 'thinking_delta' then
      begin
        E := TJSONObject(D).FindPath('delta.thinking');
        if (E <> nil) and Assigned(FOnThink) then FOnThink(Self, E.AsString);
      end;
    end
    else if Kind = 'message_delta' then
    begin
      E := TJSONObject(D).FindPath('delta.stop_reason');
      if (E <> nil) and (E.JSONType = jtString) then
        if E.AsString = 'refusal' then FProblem := 'the service declined to answer'
        else if E.AsString = 'max_tokens' then FProblem := 'the answer was cut off at its length limit';
    end
    else if Kind = 'error' then
    begin
      E := TJSONObject(D).FindPath('error.message');
      if E <> nil then FProblem := E.AsString else FProblem := 'the service sent an error';
    end;
  finally
    D.Free;
  end;
end;

procedure TChatStream.TakeLine(const L: string);
var
  P, T: string;
begin
  if Copy(L, 1, 5) <> 'data:' then Exit;
  FStreamed := True;
  P := Trim(Copy(L, 6, MaxInt));
  if (P = '') or (P = '[DONE]') then Exit;
  if Anthropic then
  begin
    TakeAnthropic(P);
    Exit;
  end;
  T := ErrorOf(P);
  if T <> '' then
  begin
    FProblem := T;
    Exit;
  end;
  if Assigned(FOnThink) then
  begin
    T := PieceOf(P, True, 'reasoning_content');
    if T <> '' then FOnThink(Self, T);
  end;
  P := PieceOf(P, True);
  if (P <> '') and Assigned(FOnPiece) then FOnPiece(Self, P);
end;

function TChatStream.Write(const Buffer; Count: LongInt): LongInt;
var
  S: string;
  K: Integer;
begin
  if Stopped then raise EAbort.Create('stopped');
  SetString(S, PChar(@Buffer), Count);
  { the whole reply is kept only up to a size, for an error message or a
    one-body answer }
  if Length(FAll) < 4 * 1024 * 1024 then FAll := FAll + S;
  FLine := FLine + S;
  K := Pos(#10, FLine);
  while K > 0 do
  begin
    TakeLine(TrimRight(Copy(FLine, 1, K - 1)));
    Delete(FLine, 1, K);
    K := Pos(#10, FLine);
  end;
  Result := Count;
end;

function TChatStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
end;

function TChatStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := Length(FAll);
end;

function TChatStream.Finish: string;
begin
  if FLine <> '' then TakeLine(TrimRight(FLine));
  FLine := '';
  if FStreamed or Anthropic then Exit('');
  FProblem := ErrorOf(Trim(FAll));
  if FProblem <> '' then Exit('');
  Result := PieceOf(FAll, False);
end;

{ TChatThread }

constructor TChatThread.Create(const S: TAssistantSettings; const Key: string;
  const Sys: TChatSystem; const Msgs: TChatMsgs; AOnPiece: TChatPiece;
  AOnDone: TChatDone; AOnThink: TChatPiece);
var
  H: TStringList;
begin
  FURL := ChatURL(S);
  FBody := ChatBody(S, Sys, Msgs);
  H := TStringList.Create;
  try
    ChatHeaders(S, Key, H);
    FHeaders := H.Text;
  finally
    H.Free;
  end;
  FOnPiece := AOnPiece;
  FOnThink := AOnThink;
  FOnDone := AOnDone;
  FStream := TChatStream.Create;
  FStream.Anthropic := ProviderOf(S) = PROV_ANTHROPIC;
  FStream.OnPiece := @GotPiece;
  if Assigned(AOnThink) then FStream.OnThink := @GotThink;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TChatThread.Stop;
begin
  FStream.Stopped := True;
  Terminate;
end;

procedure TChatThread.Detach;
begin
  FOnPiece := nil;
  FOnThink := nil;
  FOnDone := nil;
  Stop;
end;

procedure TChatThread.GotPiece(Sender: TObject; const Piece: string);
begin
  FPiece := Piece;
  Synchronize(@SyncPiece);
end;

procedure TChatThread.GotThink(Sender: TObject; const Piece: string);
begin
  FPiece := Piece;
  Synchronize(@SyncThink);
end;

procedure TChatThread.SyncThink;
begin
  if Assigned(FOnThink) then FOnThink(Self, FPiece);
end;

procedure TChatThread.SyncPiece;
begin
  if Assigned(FOnPiece) then FOnPiece(Self, FPiece);
end;

procedure TChatThread.SyncDone;
begin
  if Assigned(FOnDone) then FOnDone(Self, FOK, FErr);
end;

procedure TChatThread.Execute;
var
  H: TStringList;
  Body: TStringStream;
  Status: Integer;
  One, Why: string;
begin
  H := TStringList.Create;
  Body := TStringStream.Create(FBody);
  try
    H.Text := FHeaders;
    H.Insert(0, 'Content-Type: application/json');
    FOK := NetPostStream(FURL, H, Body, FStream, Status, FErr);
    One := FStream.Finish;
    if FOK and (One <> '') then GotPiece(Self, One);
    if FOK and (FStream.Problem <> '') then
    begin
      FOK := False;
      FErr := FStream.Problem;
    end
    else if not FOK and (FErr <> 'stopped') then
    begin
      { the service's own words say most, cut short }
      Why := Trim(FStream.All);
      if Why <> '' then FErr := FErr + ': ' + Copy(Why, 1, 300);
    end;
    Synchronize(@SyncDone);
  finally
    Body.Free;
    H.Free;
    FStream.Free;
  end;
end;

end.
