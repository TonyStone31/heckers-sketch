unit hsHelpImage;

{ A window showing one picture from the manual, fitted to the window
  (ImageFit = iifWindow), so resizing the window zooms it and animations keep
  playing.  One window, reused for each picture; Esc closes it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, LCLType, InkPage;

type
  THelpImageForm = class(TForm)
    Page: TInkPage;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PageLinkClick(Sender: TObject; const URL: string);
  public
    procedure ShowPicture(const URL, Title: string);
  end;

var
  HelpImageForm: THelpImageForm = nil;

{ Open the picture window on URL (a file:// address or a local path). }
procedure OpenPictureWindow(const URL, Title: string);

implementation

{$R *.lfm}

uses
  hsDialogSkin, hsSurface;

procedure OpenPictureWindow(const URL, Title: string);
begin
  if HelpImageForm = nil then
    Application.CreateForm(THelpImageForm, HelpImageForm);
  HelpImageForm.ShowPicture(URL, Title);
end;

procedure THelpImageForm.FormCreate(Sender: TObject);
var
  Dark: string;
begin
  hsDialogSkin.SkinForm(Self);
  Page.ImageFit := iifWindow;
  { for looking only, no copy menu }
  Page.CopyMenu := False;
  Dark := Format('#%.2x%.2x%.2x', [DlgTheme.Shell1.R, DlgTheme.Shell1.G,
    DlgTheme.Shell1.B]);
  Page.StyleSheet.Text := 'body { background: ' + Dark +
    '; margin: 0; padding: 0 } html { scrollbar-width: none }';
  Page.Color := PixToColor(DlgTheme.Shell1);
end;

procedure THelpImageForm.FormDestroy(Sender: TObject);
begin
  if HelpImageForm = Self then HelpImageForm := nil;
end;

procedure THelpImageForm.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure THelpImageForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Close;
    Key := 0;
  end;
end;

{ the page has no links; clicks do nothing }
procedure THelpImageForm.PageLinkClick(Sender: TObject; const URL: string);
begin
end;

procedure THelpImageForm.ShowPicture(const URL, Title: string);
var
  R: TRect;
begin
  if not Visible then
  begin
    { most of the screen }
    R := Screen.WorkAreaRect;
    Width := (R.Right - R.Left) * 85 div 100;
    Height := (R.Bottom - R.Top) * 85 div 100;
  end;
  if Title <> '' then Caption := 'Heckers Sketch - ' + Title
  else Caption := 'Heckers Sketch - Picture';
  { Wrap the picture in a page of our own.  LoadFromURL only does that for
    formats it knows, and it shows .webp as raw text. }
  Page.LoadHTML('<html><head></head><body style="margin:0">' +
    '<img src="' + StringReplace(URL, '"', '&quot;', [rfReplaceAll]) +
    '" alt="' + StringReplace(Title, '"', '&quot;', [rfReplaceAll]) +
    '"></body></html>', URL);
  Page.ClearHistory;
  Show;
  BringToFront;
end;

end.
