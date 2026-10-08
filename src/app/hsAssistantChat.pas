unit hsAssistantChat;

{ One question to a chat server and its answer, a piece at a time.  Spoken
  in the chat-completions form most servers take, a model on this machine
  included.  No windows here, so the tests can run it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, hsAssistantContext;

type
  TChatMsg = record
    Role: string;    { 'system', 'user' or 'assistant' }
    Text: string;
  end;
  TChatMsgs = array of TChatMsg;

  TChatPiece = procedure(Sender: TObject; const Piece: string) of object;
  TChatDone = procedure(Sender: TObject; OK: Boolean; const Err: string) of object;

  { Reads a streamed answer as it is written into it: "data: {...}" lines,
    each holding the next piece.  A server that ignores streaming answers in
    one body, which Finish reads.  Raises EAbort from Write once Stopped. }
  TChatStream = class(TStream)
  private
    FLine: string;
    FAll: string;
    FStreamed: Boolean;
    FOnPiece: TChatPiece;
    function PieceOf(const Json: string; Streamed: Boolean): string;
    procedure TakeLine(const L: string);
  public
    Stopped: Boolean;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    { what came in one body, when nothing streamed; '' otherwise }
    function Finish: string;
    { the reply as it came, for an error message }
    property All: string read FAll;
    property OnPiece: TChatPiece read FOnPiece write FOnPiece;
  end;

  { The question on its own thread; OnPiece and OnDone run on the main
    thread.  Frees itself. }
  TChatThread = class(TThread)
  private
    FURL, FKey, FBody: string;
    FStream: TChatStream;
    FPiece, FErr: string;
    FOK: Boolean;
    FOnPiece: TChatPiece;
    FOnDone: TChatDone;
    procedure GotPiece(Sender: TObject; const Piece: string);
    procedure SyncPiece;
    procedure SyncDone;
  protected
    procedure Execute; override;
  public
    constructor Create(const S: TAssistantSettings; const Key: string;
      const Msgs: TChatMsgs; AOnPiece: TChatPiece; AOnDone: TChatDone);
    procedure Stop;
    { stops it and drops its events, for a window going away }
    procedure Detach;
  end;

{ Where the question goes: the address as given, with /chat/completions
  added unless it is there; a server of one's own defaults to this
  machine. }
function ChatURL(const S: TAssistantSettings): string;

{ The request: the model, the messages, streamed. }
function ChatBody(const S: TAssistantSettings; const Msgs: TChatMsgs): string;

{ '' when a question may go; else why not.  A key goes only over https or
  to this machine. }
function ChatRefusal(const S: TAssistantSettings; const Key: string): string;

{ What the assistant is told before the conversation: what it is for, and
  the manual and the sheet when they go. }
function ChatSystemText(const Manual, Sheet, Picked: string): string;

implementation

uses
  fpjson, jsonparser, hsNet;

const
  OWN_SERVER = 'http://localhost:1234/v1';

function ChatURL(const S: TAssistantSettings): string;
begin
  Result := Trim(S.Endpoint);
  if (Result = '') and (S.Provider = PROVIDERS[1]) then Result := OWN_SERVER;
  if Result = '' then Exit;
  while (Result <> '') and (Result[Length(Result)] = '/') do SetLength(Result, Length(Result) - 1);
  if LowerCase(Copy(Result, Length(Result) - 16, 17)) <> '/chat/completions' then
    Result := Result + '/chat/completions';
end;

function ChatBody(const S: TAssistantSettings; const Msgs: TChatMsgs): string;
var
  O, M: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    if S.Model <> '' then O.Add('model', S.Model);
    O.Add('stream', True);
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

function ChatRefusal(const S: TAssistantSettings; const Key: string): string;
var
  U, Host: string;
  K: Integer;
begin
  Result := '';
  U := LowerCase(ChatURL(S));
  if U = '' then Exit('No address yet - Settings says where the questions go.');
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

function ChatSystemText(const Manual, Sheet, Picked: string): string;
begin
  Result :=
    'You help someone draw in Heckers Sketch, a 3D sketching program.  ' +
    'Drawings are written in Heck, a plain-text language; the manual below ' +
    'is all of it.  Answer plainly and briefly.  When you change the ' +
    'drawing, give the whole changed sheet as Heck in one ```heck block, ' +
    'keeping every name and comment that is there; it is looked over ' +
    'before it is used.';
  if Manual <> '' then
    Result := Result + LineEnding + LineEnding + '# The manual' + LineEnding + LineEnding + Manual;
  if Sheet <> '' then
    Result := Result + LineEnding + LineEnding + '# The sheet as it stands' + LineEnding +
      LineEnding + '```heck' + LineEnding + Sheet + '```';
  if Picked <> '' then
    Result := Result + LineEnding + LineEnding + 'Picked on the sheet: lines ' + Picked + '.';
end;

{ TChatStream }

function TChatStream.PieceOf(const Json: string; Streamed: Boolean): string;
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
    if Streamed then E := TJSONObject(C.Items[0]).FindPath('delta.content')
    else E := TJSONObject(C.Items[0]).FindPath('message.content');
    if (E <> nil) and (E.JSONType = jtString) then Result := E.AsString;
  finally
    D.Free;
  end;
end;

procedure TChatStream.TakeLine(const L: string);
var
  P: string;
begin
  if Copy(L, 1, 5) <> 'data:' then Exit;
  FStreamed := True;
  P := Trim(Copy(L, 6, MaxInt));
  if (P = '') or (P = '[DONE]') then Exit;
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
  if FStreamed then Exit('');
  Result := PieceOf(FAll, False);
end;

{ TChatThread }

constructor TChatThread.Create(const S: TAssistantSettings; const Key: string;
  const Msgs: TChatMsgs; AOnPiece: TChatPiece; AOnDone: TChatDone);
begin
  FURL := ChatURL(S);
  FKey := Key;
  FBody := ChatBody(S, Msgs);
  FOnPiece := AOnPiece;
  FOnDone := AOnDone;
  FStream := TChatStream.Create;
  FStream.OnPiece := @GotPiece;
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
  FOnDone := nil;
  Stop;
end;

procedure TChatThread.GotPiece(Sender: TObject; const Piece: string);
begin
  FPiece := Piece;
  Synchronize(@SyncPiece);
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
    H.Add('Content-Type: application/json');
    H.Add('Accept: text/event-stream');
    if FKey <> '' then H.Add('Authorization: Bearer ' + FKey);
    FOK := NetPostStream(FURL, H, Body, FStream, Status, FErr);
    One := FStream.Finish;
    if FOK and (One <> '') then GotPiece(Self, One);
    if not FOK and (FErr <> 'stopped') then
    begin
      { the server's own words say most, cut short }
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
