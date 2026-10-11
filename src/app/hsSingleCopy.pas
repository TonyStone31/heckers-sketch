{ One copy at a time, because two copies would overwrite each other's
  draft.  The lock is released by the OS however the process ends, so a
  crash never leaves it behind.  --multi skips it.  After an update the new
  copy waits for the old one to let go rather than refusing to start. }
unit hsSingleCopy;

{$mode objfpc}{$H+}

interface

{ True when this process now holds the lock; False means another copy has
  it and the caller should say so and leave.  WaitSecs is 0 normally, so a
  double launch is told at once; an update passes a few seconds while the
  old copy exits. }
function BecomeTheOnlyCopy(WaitSecs: Integer = 0): Boolean;
procedure DropInheritedUpdateLock;

{ Another copy has the lock: leave it a note instead of a complaint.  The
  note lists the files named on our command line - none means "come to the
  front" - and the running copy reads it on its tick.  Returns the note's
  path, or '' when it could not be written and the caller should fall back
  to saying a copy is already running. }
function LeaveOpenRequest: string;

implementation

uses
  SysUtils, Classes, hsPaths
  {$IFDEF UNIX}, BaseUnix, Unix{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

{ Written whole: to a temporary name first, renamed once complete, so the
  reader never sees half a note. }
function LeaveOpenRequest: string;
var
  L: TStringList;
  I: Integer;
  Note, Tmp: string;
begin
  Result := '';
  L := TStringList.Create;
  try
    for I := 1 to ParamCount do
      if (Copy(ParamStr(I), 1, 1) <> '-') and FileExists(ParamStr(I)) then
        L.Add(ExpandFileName(ParamStr(I)));
    Note := NewOpenRequestName;
    Tmp := ChangeFileExt(Note, '.tmp');
    try
      L.SaveToFile(Tmp);
      if FileExists(Note) then DeleteFile(Note);
      if RenameFile(Tmp, Note) then Result := Note
      else DeleteFile(Tmp);
    except
      { a read-only folder: the old message will have to do }
    end;
  finally
    L.Free;
  end;
end;

{$IFDEF UNIX}
const
  CLOSE_ON_EXEC = 1;

var
  LockFD: cint = -1;

procedure DropInheritedUpdateLock;
var
  I: Integer;
  LockInfo, FDInfo: TStat;
begin
  if FpStat(AppDataDir + 'heckers-sketch.lock', LockInfo) <> 0 then Exit;
  for I := 3 to 1024 do
    if (FpFStat(I, FDInfo) = 0) and
       (FDInfo.st_dev = LockInfo.st_dev) and
       (FDInfo.st_ino = LockInfo.st_ino) then
      FpClose(I);
end;

function BecomeTheOnlyCopy(WaitSecs: Integer): Boolean;
var
  Path: string;
  Give: QWord;
begin
  Path := AppDataDir + 'heckers-sketch.lock';
  LockFD := FpOpen(PChar(Path), O_RDWR or O_CREAT, &644);
  if LockFD < 0 then Exit(True);   { cannot lock: better to run than not }
  FpFcntl(LockFD, F_SETFD, CLOSE_ON_EXEC);
  { whole-file lock; released when the process ends, however it ends }
  Give := GetTickCount64 + QWord(WaitSecs) * 1000;
  repeat
    Result := FpFlock(LockFD, LOCK_EX or LOCK_NB) = 0;
    if Result or (GetTickCount64 >= Give) then Break;
    Sleep(100);
  until False;
  if not Result then
  begin
    FpClose(LockFD);
    LockFD := -1;
  end;
end;
{$ENDIF}

{$IFDEF WINDOWS}
var
  Mutex: HANDLE = 0;

procedure DropInheritedUpdateLock;
begin
end;

function BecomeTheOnlyCopy(WaitSecs: Integer): Boolean;
var
  R: DWORD;
begin
  { Local\, not Global\: one copy per signed-in user.  Own it by waiting
    rather than at creation, so it can also see the old copy exit during an
    update. }
  Mutex := CreateMutex(nil, False, 'Local\HeckersSketchSingleInstance');
  if Mutex = 0 then Exit(True);   { cannot lock: better to run than not }
  R := WaitForSingleObject(Mutex, DWORD(WaitSecs) * 1000);
  { WAIT_ABANDONED means the owner exited without releasing it, which is how
    this program normally lets go, so it counts as ours. }
  Result := (R = WAIT_OBJECT_0) or (R = WAIT_ABANDONED);
  if not Result then
  begin
    CloseHandle(Mutex);
    Mutex := 0;
  end;
end;
{$ENDIF}

end.
