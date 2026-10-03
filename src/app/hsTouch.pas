unit hsTouch;

{ Raw touch events for the drawing.  The LCL GTK3 backend asks GDK for
  touch events and then drops them, and GDK no longer turns those fingers
  into mouse events, so the drawing would get nothing.  This hooks the
  form's touch-event signal and passes each finger on; hsMainForm decides
  what the gestures mean.  GTK3 only; elsewhere HookTouch returns False. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms;

type
  TTouchKind = (tkBegin, tkUpdate, tkEnd, tkCancel);
  { Seq tells one finger from another while it is down; SX, SY are screen
    coordinates, so the program can ask any control where that is }
  TTouchHandler = procedure(Kind: TTouchKind; Seq: Pointer; SX, SY: Double) of object;

{ True when the platform supports it }
function HookTouch(Form: TCustomForm; Handler: TTouchHandler): Boolean;

implementation

{$IFDEF LCLGTK3}
uses
  LazGLib2, LazGObject2, LazGdk3, LazGtk3, gtk3widgets;

var
  TheHandler: TTouchHandler = nil;

function TouchCb(w: PGtkWidget; ev: PGdkEventTouch; data: gpointer): gboolean; cdecl;
var
  K: TTouchKind;
begin
  Result := False;
  if (ev = nil) or not Assigned(TheHandler) then Exit;
  case ev^.type_ of
    GDK_TOUCH_BEGIN: K := tkBegin;
    GDK_TOUCH_UPDATE: K := tkUpdate;
    GDK_TOUCH_END: K := tkEnd;
    GDK_TOUCH_CANCEL: K := tkCancel;
  else
    Exit;
  end;
  try
    TheHandler(K, ev^.sequence, ev^.x_root, ev^.y_root);
  except
    { never let an exception escape into the toolkit's event loop }
  end;
  Result := True;
end;

function HookTouch(Form: TCustomForm; Handler: TTouchHandler): Boolean;
var
  W: PGtkWidget;
begin
  Result := False;
  if (Form = nil) or not Form.HandleAllocated then Exit;
  W := TGtk3Widget(Form.Handle).Widget;
  if W = nil then Exit;
  TheHandler := Handler;
  { hook the window: the drawing area has no widget of its own, so its
    touches arrive here through the form's container }
  g_signal_connect_data(PGObject(W), 'touch-event', TGCallback(@TouchCb), nil, nil, G_CONNECT_DEFAULT);
  Result := True;
end;
{$ELSE}
function HookTouch(Form: TCustomForm; Handler: TTouchHandler): Boolean;
begin
  Result := False;
end;
{$ENDIF}

end.
