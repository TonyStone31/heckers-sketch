{ hsMainForm - the keyboard and commands.  Part of TMainForm; included by hsMainForm.pas }

{ ======================================================================== }
{ keyboard                                                                  }
{ ======================================================================== }

procedure TMainForm.FormKeyPress(Sender: TObject; var Key: char);
begin
  if FBusy then Exit;

  { while a note or a dimension's label is being typed, everything is text }
  if ((FTool = ptText) and (FStage = 1)) or (FDimEdit >= 0) then
  begin
    if Key >= ' ' then
    begin
      FInput := FInput + Key;
      pbCmd.Invalidate;
      Key := #0;
    end;
    Exit;
  end;

  { one note picked and nothing typed: + and - change its text size by a
    quarter, between half and four times (the box follows, as in SketchUp) }
  if (FInput = '') and (FStage = 0) and (Length(FSel) = 1) and
     (FD.Doc[FSel[0]].Kind = ekText) and (Key in ['+', '=', '-']) then
  begin
    PushUndo;
    if Key = '-' then
      FD.Doc.SetNoteSize(FSel[0], FD.Doc.NoteSize(FSel[0]) / 1.25)
    else
      FD.Doc.SetNoteSize(FSel[0], FD.Doc.NoteSize(FSel[0]) * 1.25);
    FCmdMsg := Format('Text at %d%% of normal.  + and - change it.',
      [Round(FD.Doc.NoteSize(FSel[0]) * 100)]);
    RenderInk;
    RecomposeAll;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { right after a copy, 3x or /3 makes an array: x, * and / go in with the
    digits, and Enter does the rest }
  if FArray.Live and (Key in ['x', 'X', '*', '/']) and
     ((FInput = '') or (FInput[1] in ['0'..'9'])) and
     (Pos('x', FInput) = 0) and (Pos('*', FInput) = 0) and (Pos('/', FInput) = 0) then
  begin
    if Key = 'X' then Key := 'x';
    FInput := FInput + Key;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;
  if FArray.Live and (Key in ['0'..'9']) and (FInput <> '') and (FInput[1] in ['x', '*', '/']) then
  begin
    FInput := FInput + Key;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { circle and arc sides: + and - step the count, and s goes into the input
    for SketchUp's 24s (or s24) }
  if (FTool in [ptCircle, ptArc]) and (FInput = '') and (Key in ['+', '=', '-']) then
  begin
    if FTool = ptCircle then
    begin
      if Key = '-' then FSidesCircle := Max(3, FSidesCircle - 1)
      else FSidesCircle := Min(360, FSidesCircle + 1);
      FCmdMsg := Format('%d sides.  + and - change it, or type 24s.', [FSidesCircle]);
    end
    else
    begin
      if Key = '-' then FSidesArc := Max(2, FSidesArc - 1)
      else FSidesArc := Min(360, FSidesArc + 1);
      FCmdMsg := Format('%d segments.  + and - change it, or type 12s.', [FSidesArc]);
    end;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;
  if (FTool in [ptCircle, ptArc]) and (Key in ['s', 'S']) and
     ((FInput = '') or (FInput[1] in ['0'..'9'])) and (Pos('s', FInput) = 0) then
  begin
    FInput := FInput + 's';
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { a leading '/' starts a typed command; after that every character is text,
    otherwise letters are tool shortcuts }
  if (Copy(FInput, 1, 1) = '/') and (Key >= ' ') then
  begin
    FInput := FInput + Key;
    { and the list narrows with it }
    SyncCmdList;
    pbCmd.Invalidate;
    Key := #0;
    Exit;
  end;

  { x, comma or semicolon separate a rectangle's sides while it waits for its
    size; elsewhere letters stay shortcuts.  The first slash works too, for
    the number pad (2/2 is a two foot square); a later slash is a fraction
    (2/2 1/2).  Only once a number is typed: a bare slash starts a command. }
  if ((Key in ['x', 'X', ',', ';']) or
      ((Key = '/') and (FInput <> '') and (FInput[1] in ['0'..'9']) and
       (Pos('x', FInput) = 0))) and
     (FTool = ptRect) and (FStage = 1) then
  begin
    FInput := FInput + 'x';
    FCmdMsg := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
    Exit;
  end;

  { a sum in a length (8' + 8", 8'17" / 2; see ParseLen): plus and times once
    something is typed, brackets any time }
  if ((Key in ['+', '*', ')']) and (FInput <> '')) or (Key = '(') then
  begin
    FInput := FInput + Key;
    FCmdMsg := '';
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
    Exit;
  end;

  { brackets and commas for coordinates: [x,y,z] a point, <x,y,z> an offset }
  if Key in ['0'..'9', '.', '/', '''', '"', ' ', '-', ',', ';',
             '[', ']', '<', '>', ':'] then
  begin
    FInput := FInput + Key;
    FCmdMsg := '';
    { a slash with nothing before it starts a command: bring up the list }
    if FInput = '/' then SyncCmdList;
    pbCmd.Invalidate;
    pbScreen.Invalidate;
    Key := #0;
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Handled: Boolean;
  Step: Double;

  { SketchUp's arrows name an axis by color in every view: right red, left
    green, up blue.  A lock is on the axis, not a direction along it. }
  function ArrowAxis(K: word): Integer;
  begin
    case K of
      VK_RIGHT: Result := 0;      // red, X
      VK_LEFT: Result := 2;       // green, Y
      VK_UP: Result := 4;         // blue, Z
      VK_PRIOR: Result := 4;
      VK_NEXT: Result := 5;
    else
      Result := -1;               // down lets go
    end;
  end;

  { nudging the cursor with arrows wants a screen direction instead }
  function ArrowStep(K: word): Integer;
  begin
    if FD.View = vkIso then
      case K of
        VK_RIGHT: Result := 0;
        VK_LEFT: Result := 1;
        VK_PRIOR: Result := 2;
        VK_NEXT: Result := 3;
        VK_UP: Result := 4;
      else
        Result := 5;
      end
    else
      case K of
        VK_RIGHT: Result := 0;
        VK_LEFT: Result := 1;
        VK_UP: Result := 2;
      else
        Result := 3;
      end;
  end;

  procedure Arrow(K: word);
  var
    D: TP3;
  begin
    if (FTool in [ptLine, ptMove]) and (FStage = 1) then
    begin
      FDirLock := ArrowAxis(K);
      { recorded for replay: the length alone does not say which way }
      Act('dir ' + IntToStr(FDirLock));
      if FDirLock < 0 then FCmdMsg := 'Free again.'
      else FCmdMsg := 'Locked to ' + AxisName(FDirLock) + '.';
    end
    else if FTool in [ptRotate, ptProtractor] then
    begin
      { the arrow names the axis the protractor turns about }
      FRotAxisIx := ArrowAxis(K);
      if FRotAxisIx < 0 then
        FCmdMsg := 'Plane from whatever is under the cursor again.'
      else
      begin
        FRotAxis := AxisDir(FRotAxisIx);
        FCmdMsg := 'Turning about ' + AxisName(FRotAxisIx) + '.';
      end;
      pbScreen.Invalidate;
      pbCmd.Invalidate;
      Exit;
    end
    else
    begin
      D := AxisDir(ArrowStep(K));
      Step := SnapStep;
      if Step <= 0 then Step := 1 / 12;
      if ssShift in Shift then
      begin
        JumpSnap(Round(Sign(ScreenOf(P3(FCur.X + D.X, FCur.Y + D.Y, FCur.Z + D.Z)).X
                             - ScreenOf(FCur).X)),
                 Round(Sign(ScreenOf(P3(FCur.X + D.X, FCur.Y + D.Y, FCur.Z + D.Z)).Y
                             - ScreenOf(FCur).Y)));
        Exit;
      end;
      if ssCtrl in Shift then Step := Step / 4;
      FCur := P3(FCur.X + D.X * Step, FCur.Y + D.Y * Step, FCur.Z + D.Z * Step);
      FSnapKind := snNone;
      FMouseSX := Round(ScreenOf(FCur).X);
      FMouseSY := Round(ScreenOf(FCur).Y);
    end;
    pbScreen.Invalidate;
    pbCmd.Invalidate;
    InvalidateStatus;
  end;

begin
  { picking for the stairs: Esc goes back to the dialog as it was }
  if (FStairPick > 0) and (Key = VK_ESCAPE) then
  begin
    FStairPick := 0;
    FCmdMsg := '';
    Key := 0;
    Application.QueueAsyncCall(@StairResume, 0);
    Exit;
  end;
  { the source window's Pick ends on Esc, before anything else sees it }
  if FTextPick and (Key = VK_ESCAPE) then
  begin
    SourcePick(False);
    if SourceForm <> nil then SourceForm.PickEnded;
    Key := 0;
    Exit;
  end;
  if FBusy then Exit;
  Handled := True;

  if ssCtrl in Shift then
  begin
    case Key of
      VK_Z: DoUndo;
      VK_Y: DoRedo;
      VK_G: MakeGroup;     { SketchUp's Ctrl+G }
      { what is typed, when something is; otherwise the drawing }
      VK_C:
        if FInput <> '' then
        begin
          Clipboard.AsText := FInput;
          FCmdMsg := 'Copied what is typed.';
        end
        else CopySelection(False);
      VK_X: CopySelection(True);
      { clipboard text goes into the typing when there is typing already or
        it is a command; otherwise it is the drawing's paste }
      VK_V:
        if Clipboard.HasFormat(CF_TEXT) and
           ((FInput <> '') or (Copy(TrimLeft(Clipboard.AsText), 1, 1) = '/')) then
        begin
          if FInput = '' then FInput := TrimLeft(Clipboard.AsText)
          else FInput := FInput + Clipboard.AsText;
          { one line only }
          if Pos(#10, FInput) > 0 then FInput := Copy(FInput, 1, Pos(#10, FInput) - 1);
          FInput := StringReplace(FInput, #13, '', [rfReplaceAll]);
          if Copy(FInput, 1, 1) = '/' then SyncCmdList;
          pbCmd.Invalidate;
        end
        else PasteClip;
      VK_S: if ssShift in Shift then DoSaveAs else DoSave;
      VK_O: DoOpen;
      VK_M: ShowFileMenu;
      VK_E: DoExport;
      VK_P: DoPrint;
      VK_N: NewDrawing(-1);
      VK_T: NewDrawing(-1);
      VK_W: CloseDrawing(FTabIdx);
      VK_TAB: SelectDrawing((FTabIdx + 1) mod Length(FDrawings));
    else
      Handled := False;
    end;
    if Handled then
    begin
      Key := 0;
      Exit;
    end;
  end;

  case Key of
    VK_F1: begin ShowAbout; Key := 0; Exit; end;
    VK_DELETE:
      begin
        { Delete takes the selection; with nothing selected, clearing the
          sheet asks first (it is easy to hit). }
        if Length(FSel) > 0 then
          DeleteSelection
        else if FD.Doc.Live = 0 then
          FCmdMsg := 'Nothing selected, and nothing to clear.'
        else if MessageDlg('Clear the sheet?',
             Format('Throw away all %d things on "%s"?'#13#10#13#10 +
               'Ctrl+Z will bring them back.',
               [FD.Doc.Live, FD.Name]),
             mtConfirmation, [mbYes, mbNo], 0) = mrYes then
        begin
          PushUndo;
          StartErase;          { the shake, as the discard }
        end
        else
          FCmdMsg := 'Left alone.';
        Key := 0;
        Exit;
      end;
  end;

  { With the tape in hand, Ctrl cycles what it leaves (SketchUp's key for
    it), and says the mode each time. }
  if (Key = VK_CONTROL) and (FTool = ptMeasure) then
  begin
    FTapeDrop := (FTapeDrop + 1) mod 4;
    FCmdMsg := 'The tape leaves ' + TapeDropSays + '.';
    pbCmd.Invalidate;
    Key := 0;
    Exit;
  end;

  if Key = VK_MENU then
  begin
    { Mid-line, Alt steps through the inferences (SketchUp's, see
      TInferMode); before the first click it holds the working plane.
      For the arc it is the tangent lock; we already know the edge the
      first click landed on. }
    if (FTool = ptArc) and (FStage = 2) then
    begin
      if not FArcTanHas then
        FCmdMsg := 'Nothing to be tangent to - start an arc on an edge and ' +
          'Alt runs it out of that edge smoothly.'
      else
      begin
        FArcTanLock := not FArcTanLock;
        if FArcTanLock then
          FCmdMsg := 'Tangent to the edge it starts on, held.  Alt again to ' +
            'pull the bulge by hand.'
        else
          FCmdMsg := 'The bulge follows the cursor again.';
      end;
      FCur := ResolveSnapAt(FMouseSX, FMouseSY);
      InvalidateStatus;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    { the protractor's Alt: stop taking the plane from the face under the
      cursor }
    if (FTool in [ptRotate, ptProtractor]) and (FStage = 0) then
    begin
      FRotFree := not FRotFree;
      if FRotFree then
        FCmdMsg := 'Free of the face under the cursor: it turns flat unless ' +
          'an arrow picks a plane.  Alt again to follow faces.'
      else
        FCmdMsg := 'Following the face under the cursor again.';
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    { the offset's Alt: keep a tight corner's overlaps instead of tidying
      them (see OffsetLoop) }
    if (FTool = ptOffset) and (FStage >= 1) then
    begin
      FOffsetRaw := not FOffsetRaw;
      if FOffsetRaw then
        FCmdMsg := 'Overlaps kept: a corner taken in further than it is ' +
          'round comes back as it falls, loops and all.  Alt again to tidy them.'
      else
        FCmdMsg := 'Overlaps tidied, which is the usual way.';
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;

    if (FTool = ptLine) and (FStage >= 1) then
    begin
      if FInferMode = High(TInferMode) then FInferMode := Low(TInferMode)
      else Inc(FInferMode);
      case FInferMode of
        imNoLinear: FCmdMsg := 'Inferences: the points only - no axis, ' +
          'nothing parallel.  Alt again for parallel and square.';
        imParPerp: FCmdMsg := 'Inferences: parallel and square to the last ' +
          'edge only.  Alt again for all of them.';
      else
        FCmdMsg := 'Inferences: all of them.  Alt steps through them.';
      end;
      { resolve the cursor again now, or the key seems to do nothing until
        the mouse twitches }
      FCur := ResolveSnapAt(FMouseSX, FMouseSY);
      InvalidateStatus;
      pbCmd.Invalidate;
      pbScreen.Invalidate;
      Key := 0;
      Exit;
    end;
    { otherwise Alt steps through the flat planes and latches, for drawing
      in mid air }
    if FD.View = vkPlan then
    begin
      { in plan the upright planes are edge-on and nothing drawn in them
        could be seen, so plan stays on the ground and says so }
      FD.Plane := plXY;
      FPlaneHeld := False;
      FCmdMsg := 'Plan draws flat on the ground.  ISO or 3D to work upright.';
      pbCmd.Invalidate;
      Key := 0;
      Exit;
    end;
    FD.Plane := TPlane((Ord(FD.Plane) + 1) mod 3);
    FPlaneHeld := True;
    case FD.Plane of
      plXZ: FCmdMsg := 'Plane held upright, XZ.  Alt again to change, Esc to follow faces.';
      plYZ: FCmdMsg := 'Plane held on the side, YZ.  Alt again to change, Esc to follow faces.';
    else
      FCmdMsg := 'Plane held flat, XY.  Alt again to change, Esc to follow faces.';
    end;
    RepaintPaper;
    RenderInk;
    RecomposeAll;
    pbCmd.Invalidate;
    Key := 0;
    Exit;
  end;

  { while a note, label or /command is typed, letters are letters; only
    keys that finish or edit it are handled }
  if ((FTool = ptText) and (FStage = 1)) or (Copy(FInput, 1, 1) = '/') or
     (FDimEdit >= 0) then
  begin
    case Key of
      { up and down walk the open command list; Tab completes to the row
        without running it }
      VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
        if FPopup = POP_CMDS then MoveCmdHighlight(Key) else Exit;
      VK_TAB:
        if (FPopup = POP_CMDS) and (FPopupHot >= 0) then
        begin
          FInput := '/' + CMD_LIST[FCmdOrder[FPopupHot]].Name;
          SyncCmdList;
          pbCmd.Invalidate;
        end
        else
          Exit;
      VK_RETURN:
        { Shift+Enter is another line of the note; Enter finishes it }
        if (ssShift in Shift) and (FTool = ptText) and (FStage = 1) then
        begin
          FInput := FInput + #10;
          pbCmd.Invalidate;
        end
        { Enter takes the highlighted row, unless what is typed is already
          a whole command (/line runs /line) }
        else if (FPopup = POP_CMDS) and (FPopupHot >= 0) and
                not ExactCmd(FInput) then
          TakeCmdHighlight
        else
        begin
          if FPopup = POP_CMDS then ClosePopup;
          CommandEnter;
        end;
      VK_ESCAPE:
        if FDimEdit >= 0 then
        begin
          FDimEdit := -1;
          FInput := '';
          FCmdMsg := 'Left as it was.';
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end
        { the list first, then the typing, then the tool: one press each }
        else if FPopup = POP_CMDS then
        begin
          ClosePopup;
          FInput := '';
          pbCmd.Invalidate;
        end
        else
          ResetTool;
      VK_BACK:
        begin
          if FInput <> '' then SetLength(FInput, Length(FInput) - 1);
          { erasing letters widens the list; erasing the slash puts it away }
          SyncCmdList;
          pbCmd.Invalidate;
          pbScreen.Invalidate;
        end;
    else
      Exit;      // let OnKeyPress see it
    end;
    Key := 0;
    Exit;
  end;

  case Key of
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT:
      { the command list takes up and down while it is open }
      if (FPopup = POP_CMDS) and (Key in [VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT]) then
        MoveCmdHighlight(Key)
      { Ctrl turns the view a cube step instead, in 3D and only between
        shapes, so a mid-line arrow lock is never taken away }
      else if (ssCtrl in Shift) and (FD.View = vkOrbit) and
         (FStage = 0) and (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN]) then
        StepCubeView(Key)
      { before a shape is under way the arrows pick the plane; after, they
        lock a direction, which only means something for a line }
      else if (FTool in [ptRect, ptCircle, ptArc]) or
         ((FTool = ptLine) and (FStage = 0)) then
        PlaneByArrow(Key)
      else
        Arrow(Key);
    { Enter takes the highlighted row unless what is typed is already a
      whole command }
    VK_RETURN:
      if (FPopup = POP_CMDS) and (FPopupHot >= 0) and
         not ExactCmd(FInput) then TakeCmdHighlight
      else
      begin
        if FPopup = POP_CMDS then ClosePopup;
        CommandEnter;
      end;
    { and Tab completes without running }
    VK_TAB: if (FPopup = POP_CMDS) and (FPopupHot >= 0) then
            begin
              FInput := '/' + CMD_LIST[FCmdOrder[FPopupHot]].Name;
              SyncCmdList;
              pbCmd.Invalidate;
            end
            else
              SetTool(TTool((Ord(FTool) + 1) mod (Ord(High(TTool)) + 1)));
    { Space is SketchUp's select; mid-shape it still finishes the shape.
      Once something is typed a space is a space (sums like 8' + 8"). }
    VK_SPACE:
      if (FStage = 0) and (FInput = '') then SetTool(ptSelect)
      else if FInput <> '' then Handled := False
      else CommandEnter;
    VK_ESCAPE:
      begin
        if FSliceEdit <> 0 then
        begin
          FSliceEdit := 0;
          FInput := '';
          FCmdMsg := 'Left as it was.';
          pbSlice.Invalidate;
        end
        else if FPopup <> POP_NONE then
          ClosePopup
        { One press per thing: the typing, then the shape in progress with
          all its locks (ResetTool), then a held plane, the selection, the
          open group.  The shape comes before the held plane, or ending a
          line took several presses. }
        else if FInput <> '' then
          FInput := ''
        else if FStage > 0 then
          ResetTool
        else if FPlaneHeld then
        begin
          FPlaneHeld := False;
          FCmdMsg := 'Following the face under the cursor again.';
        end
        else if Length(FSel) > 0 then
          SelectNone
        else if FD.Doc.Context <> 0 then
          CloseGroup
        else
          SetTool(ptSelect);
        FCmdMsg := '';
        pbCmd.Invalidate;
        pbScreen.Invalidate;
      end;
    VK_BACK:
      begin
        if FInput <> '' then SetLength(FInput, Length(FInput) - 1);
        { erasing letters widens the list; erasing the slash puts it away }
        SyncCmdList;
        pbCmd.Invalidate;
        pbScreen.Invalidate;
      end;
    VK_Q: SetTool(ptRotate);      // SketchUp's key; Space is select
    VK_L: SetTool(ptLine);
    VK_R: SetTool(ptRect);
    VK_A: SetTool(ptArc);
    VK_C: SetTool(ptCircle);
    VK_P: SetTool(ptPush);
    VK_B: SetTool(ptDrill);       // bore
    VK_N: SetTool(ptText);
    VK_E: SetTool(ptErase);
    VK_M: SetTool(ptMove);
    VK_T: SetTool(ptMeasure);
    VK_D: SetTool(ptDim);
    VK_V:
      if ssShift in Shift then CycleViewPreset(-1) else CycleViewPreset(1);
    VK_I: RunCommand(IfThen(FD.View = vkIso, 'plan', 'iso'));
    VK_K: RunCommand('plane');
    { SketchUp puts Offset on F; zoom-to-fit is Shift+F and /fit }
    VK_F:
      if ssShift in Shift then FitView else SetTool(ptOffset);
    VK_O: SetTool(ptOrbit);
    VK_G: RunCommand('grid');
    VK_U: RunCommand('units');
    VK_H: CycleTheme(1);
    VK_OEM_4: SetEdgeWidth(FEdgeW - 1);
    VK_OEM_6: SetEdgeWidth(FEdgeW + 1);
  else
    Handled := False;
  end;
  if Handled then Key := 0;
end;

procedure TMainForm.FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  { Alt steps the inferences (see FormKeyDown), so its release is kept too }
  if Key = VK_MENU then Key := 0;
end;

{ ======================================================================== }
{ commands                                                                  }
{ ======================================================================== }

{ An index from a settings file or an older build may be out of range; the
  dark theme is the default. }
procedure TMainForm.ApplyTheme;
begin
  if (FThemeIdx < 0) or (FThemeIdx > THEME_COUNT - 1) then
    FThemeIdx := THEME_DARK;
  if FInkAuto then SetInk(PixToColor(Theme.Ink), True);
end;

procedure TMainForm.CycleTheme(Step: Integer);
begin
  { two looks differing only in chrome; the paper stays white }
  FThemeIdx := (FThemeIdx + Step + THEME_COUNT) mod THEME_COUNT;
  { only ink not deliberately chosen follows the theme }
  if FInkAuto then
    SetInk(PixToColor(Theme.Ink), True);
  { the ink is its own layer, so a theme change only repapers underneath }
  RepaintPaper;
  RenderInk;
  RecomposeAll;
  RefreshChrome;
  ThemeSourceWindow;
end;
