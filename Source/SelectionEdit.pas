{
This is open-source software licensed under the terms of the MIT License.

Copyright (c) 2026 Petr Červinka - FortSoft <cervinka@fortsoft.eu>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Last modified for version 1.0.0.0
}

unit SelectionEdit;

// Adds repeated-click selection and Ctrl+A to ANSI VCL edit controls.
// Windows NT 3.x predates EM_CHARFROMPOS. Every even click uses native caret placement
// followed by the same word-selection logic, including the second click.
interface

uses
    Windows, Messages, Classes, StdCtrls;

type
    // Distinguishes native presses from held word and line selection gestures.
    TSelectionUnit = (suNone, suNative, suWord, suLine);

    // Groups adjacent characters for complete word, space and punctuation selection.
    TSelectionCharacterType = (ctWord, ctSpace, ctPunctuation, ctLineBreak);

    // Optional Win32 entry points are resolved at run time for older systems.
    TSelectionTickCount64 = function: Int64; stdcall;
    TSelectionStringType = function(Locale: LCID; InfoType: DWORD; Source: PChar;
        Count: Integer; Types: PWord): BOOL; stdcall;

    // Adds repeated-click selection and Ctrl+A to an ANSI VCL edit control.
    TSelectionEditHandler = class(TComponent)
    private
        FEdit: TCustomEdit;
        FPreviousWindowProc: TWndMethod;
        FTickCount64: TSelectionTickCount64;
        FStringType: TSelectionStringType;
        FText: string;
        FUnit: TSelectionUnit;
        FClickCount: Integer;
        FClickTime: Int64;
        FClickPoint: TPoint;
        FMousePoint: TPoint;
        FAnchorStart: Integer;
        FAnchorEnd: Integer;

        // NT 3.x needs native click hit testing because EM_CHARFROMPOS is unavailable.
        FUseNativePosition: Boolean;
        function ClickTime: Int64;
        function ContinuesClickSequence(const Point: TPoint; Time: Int64): Boolean;
        function SelectionPosition(const Point: TPoint): Integer;
        function MeasuredPosition(const Point: TPoint; const Area: TRect): Integer;
        function NativePosition(const Point: TPoint; ButtonState: WPARAM): Integer;
        function CharacterType(Character: Char): TSelectionCharacterType;
        procedure WordBounds(Position: Integer; var Start, Finish: Integer);
        procedure LineBounds(Position: Integer; var Start, Finish: Integer);
        procedure EndSelection;
        procedure ScrollSelection(const Point: TPoint);
        procedure UpdateSelection(const Point: TPoint; Scroll: Boolean);
        procedure BeginSelection(const Point: TPoint; ButtonState: WPARAM);
        procedure WindowProc(var Message: TMessage);
    public
        constructor Create(AOwner: TComponent; AEdit: TCustomEdit); reintroduce;
        destructor Destroy; override;
    end;

implementation

// Win32 message and character-class values used by the edit handler.
const
    SelectionScrollTimer = $CC02;
    SelectionCType1 = 1;
    SelectionCType3 = 3;
    SelectionDigit = $0004;
    SelectionSpace = $0008;
    SelectionAlpha = $0100;
    SelectionNonspacing = $0001;
    SelectionDiacritic = $0002;
    SelectionVowelMark = $0004;
    SelectionXButtonDown = $020B;
    SelectionXButtonDoubleClick = $020D;

// Installs the edit hook and enables native click positioning on NT 3.x,
// whose edit control does not implement EM_CHARFROMPOS.
constructor TSelectionEditHandler.Create(AOwner: TComponent; AEdit: TCustomEdit);
var
    Kernel: HMODULE;
    VersionInfo: TOSVersionInfo;
begin
    inherited Create(AOwner);
    FEdit := AEdit;
    FillChar(VersionInfo, SizeOf(VersionInfo), 0);
    VersionInfo.dwOSVersionInfoSize := SizeOf(VersionInfo);
    FUseNativePosition := GetVersionEx(VersionInfo) and
        (VersionInfo.dwPlatformId = VER_PLATFORM_WIN32_NT) and
        (VersionInfo.dwMajorVersion < 4);
    Kernel := GetModuleHandle('kernel32.dll');
    FTickCount64 := TSelectionTickCount64(GetProcAddress(Kernel, 'GetTickCount64'));
    FStringType := TSelectionStringType(GetProcAddress(Kernel, 'GetStringTypeA'));
    FPreviousWindowProc := FEdit.WindowProc;
    FEdit.WindowProc := WindowProc;
end;

// Stops any gesture and restores the edit's original window procedure.
destructor TSelectionEditHandler.Destroy;
begin
    EndSelection;
    FEdit.WindowProc := FPreviousWindowProc;
    inherited Destroy;
end;

// Returns 64-bit ticks when available and otherwise uses wrapping 32-bit ticks.
function TSelectionEditHandler.ClickTime: Int64;
begin
    if Assigned(FTickCount64) then
    begin
        Result := FTickCount64;
    end
    else
    begin
        Result := GetTickCount;
    end;
end;

// Checks a press against the system double-click time and rectangle.
function TSelectionEditHandler.ContinuesClickSequence(
    const Point: TPoint; Time: Int64): Boolean;
var
    Area: TRect;
    Elapsed: Int64;
    Width: Integer;
    Height: Integer;
begin
    Result := False;
    if FClickCount = 0 then
    begin
        Exit;
    end;

    Elapsed := Time - FClickTime;
    if not Assigned(FTickCount64) then
    begin
        Elapsed := DWORD(Elapsed);
    end;
    if Elapsed > GetDoubleClickTime then
    begin
        Exit;
    end;

    Width := GetSystemMetrics(SM_CXDOUBLECLK);
    Height := GetSystemMetrics(SM_CYDOUBLECLK);
    if Width < 1 then
    begin
        Width := 1;
    end;
    if Height < 1 then
    begin
        Height := 1;
    end;

    Area.Left := FClickPoint.X - Width div 2;
    Area.Top := FClickPoint.Y - Height div 2;
    Area.Right := Area.Left + Width;
    Area.Bottom := Area.Top + Height;
    Result := PtInRect(Area, Point);
end;

// Uses EM_CHARFROMPOS to reconstruct the full index and measures text if its result is unusable.
function TSelectionEditHandler.SelectionPosition(const Point: TPoint): Integer;
var
    Area: TRect;
    HitPoint: TPoint;
    Hit: LRESULT;
    LineStart: Integer;
begin
    FillChar(Area, SizeOf(Area), 0);
    SendMessage(FEdit.Handle, EM_GETRECT, 0, Longint(@Area));
    if (Area.Right <= Area.Left) or (Area.Bottom <= Area.Top) then
    begin
        GetClientRect(FEdit.Handle, Area);
    end;

    HitPoint := Point;
    if HitPoint.X < Area.Left then
    begin
        HitPoint.X := Area.Left;
    end;
    if HitPoint.X >= Area.Right then
    begin
        HitPoint.X := Area.Right - 1;
    end;
    if HitPoint.Y < Area.Top then
    begin
        HitPoint.Y := Area.Top;
    end;
    if HitPoint.Y >= Area.Bottom then
    begin
        HitPoint.Y := Area.Bottom - 1;
    end;

    Hit := SendMessage(FEdit.Handle, EM_CHARFROMPOS, 0,
        Longint(Word(HitPoint.X)) or Longint(Word(HitPoint.Y)) shl 16);
    if Hit = 0 then
    begin
        Result := MeasuredPosition(HitPoint, Area);
        Exit;
    end;

    LineStart := SendMessage(FEdit.Handle, EM_LINEINDEX, HiWord(Hit), 0);
    if LineStart < 0 then
    begin
        Result := MeasuredPosition(HitPoint, Area);
        Exit;
    end;

    Result := LineStart and not $FFFF or LoWord(Hit);
    if Result < LineStart then
    begin
        Inc(Result, $10000);
    end;
    if Result > Length(FText) then
    begin
        Result := Length(FText);
    end;
end;

// Estimates a character index from the visible line and widths in the edit's current font.
function TSelectionEditHandler.MeasuredPosition(
    const Point: TPoint; const Area: TRect): Integer;
var
    DC: HDC;
    CurrentFont: HFONT;
    PreviousFont: HGDIOBJ;
    Metrics: TTextMetric;
    Extent: TSize;
    FirstLine: Integer;
    Line: Integer;
    LineStart: Integer;
    LineEnd: Integer;
    Distance: Integer;
    Low: Integer;
    High: Integer;
    Middle: Integer;
    WidthBefore: Integer;
begin
    Result := 0;
    DC := GetDC(FEdit.Handle);
    if DC = 0 then
    begin
        Exit;
    end;

    CurrentFont := SendMessage(FEdit.Handle, WM_GETFONT, 0, 0);
    PreviousFont := 0;
    if CurrentFont <> 0 then
    begin
        PreviousFont := SelectObject(DC, CurrentFont);
    end;
    try
        if GetWindowLong(FEdit.Handle, GWL_STYLE) and ES_MULTILINE <> 0 then
        begin
            FillChar(Metrics, SizeOf(Metrics), 0);
            GetTextMetrics(DC, Metrics);
            if Metrics.tmHeight < 1 then
            begin
                Metrics.tmHeight := 1;
            end;
            FirstLine := SendMessage(FEdit.Handle, EM_GETFIRSTVISIBLELINE, 0, 0);
            Line := FirstLine + (Point.Y - Area.Top) div Metrics.tmHeight;
            LineStart := SendMessage(FEdit.Handle, EM_LINEINDEX, Line, 0);
            if LineStart < 0 then
            begin
                Result := Length(FText);
                Exit;
            end;
            LineEnd := LineStart + SendMessage(FEdit.Handle, EM_LINELENGTH, LineStart, 0);
        end
        else
        begin
            LineStart := SendMessage(FEdit.Handle, EM_GETFIRSTVISIBLELINE, 0, 0);
            LineEnd := Length(FText);
        end;

        if LineStart < 0 then
        begin
            LineStart := 0;
        end;
        if LineStart > Length(FText) then
        begin
            LineStart := Length(FText);
        end;
        if LineEnd > Length(FText) then
        begin
            LineEnd := Length(FText);
        end;
        if LineEnd < LineStart then
        begin
            LineEnd := LineStart;
        end;

        Distance := Point.X - Area.Left;
        if Distance <= 0 then
        begin
            Result := LineStart;
            Exit;
        end;

        Low := 0;
        High := LineEnd - LineStart;
        while Low < High do
        begin
            Middle := (Low + High + 1) div 2;
            GetTextExtentPoint(DC, PChar(FText) + LineStart, Middle, Extent);
            if Extent.cx <= Distance then
            begin
                Low := Middle;
            end
            else
            begin
                High := Middle - 1;
            end;
        end;

        Result := LineStart + Low;
        if Low < LineEnd - LineStart then
        begin
            WidthBefore := 0;
            if Low > 0 then
            begin
                GetTextExtentPoint(DC, PChar(FText) + LineStart, Low, Extent);
                WidthBefore := Extent.cx;
            end;
            GetTextExtentPoint(DC, PChar(FText) + LineStart, Low + 1, Extent);
            if Distance - WidthBefore >= (Extent.cx - WidthBefore) div 2 then
            begin
                Inc(Result);
            end;
        end;
    finally
        if PreviousFont <> 0 then
        begin
            SelectObject(DC, PreviousFont);
        end;
        ReleaseDC(FEdit.Handle, DC);
    end;
end;

// NT 3.x lacks EM_CHARFROMPOS, so a native press and release place the caret at the click.
// EM_GETSEL then returns that caret position for every even-click word selection.
function TSelectionEditHandler.NativePosition(
    const Point: TPoint; ButtonState: WPARAM): Integer;
var
    NativeMessage: TMessage;
    SelectionStart: DWORD;
    SelectionEnd: DWORD;
begin
    NativeMessage.Msg := WM_LBUTTONDOWN;
    NativeMessage.WParam := ButtonState;
    NativeMessage.LParam := Longint(Word(Point.X)) or Longint(Word(Point.Y)) shl 16;
    NativeMessage.Result := 0;
    FPreviousWindowProc(NativeMessage);

    NativeMessage.Msg := WM_LBUTTONUP;
    NativeMessage.WParam := ButtonState and not MK_LBUTTON;
    NativeMessage.Result := 0;
    FPreviousWindowProc(NativeMessage);

    SelectionStart := 0;
    SelectionEnd := 0;
    SendMessage(FEdit.Handle, EM_GETSEL, Longint(@SelectionStart), Longint(@SelectionEnd));
    Result := SelectionEnd;
    if Result > Length(FText) then
    begin
        Result := Length(FText);
    end;
end;

// Classifies ANSI text as word, space, punctuation or line break.
function TSelectionEditHandler.CharacterType(Character: Char): TSelectionCharacterType;
var
    Basic: Word;
    Extended: Word;
begin
    if (Character = #13) or (Character = #10) then
    begin
        Result := ctLineBreak;
        Exit;
    end;
    if Character = '_' then
    begin
        Result := ctWord;
        Exit;
    end;

    Basic := 0;
    Extended := 0;
    if Assigned(FStringType) then
    begin
        FStringType(LOCALE_USER_DEFAULT, SelectionCType1, @Character, 1, @Basic);
        FStringType(LOCALE_USER_DEFAULT, SelectionCType3, @Character, 1, @Extended);
    end;
    if (Basic and (SelectionAlpha or SelectionDigit) <> 0) or
        (Extended and (SelectionNonspacing or SelectionDiacritic or SelectionVowelMark) <> 0) then
    begin
        Result := ctWord;
    end
    else if Basic and SelectionSpace <> 0 then
    begin
        Result := ctSpace;
    end
    else if (Character in ['A'..'Z', 'a'..'z', '0'..'9']) or (Ord(Character) >= 128) then
    begin
        Result := ctWord;
    end
    else if Character <= ' ' then
    begin
        Result := ctSpace;
    end
    else
    begin
        Result := ctPunctuation;
    end;
end;

// Finds the complete character run at Position; Finish is exclusive.
procedure TSelectionEditHandler.WordBounds(Position: Integer; var Start, Finish: Integer);
var
    Kind: TSelectionCharacterType;
begin
    Start := Position;
    Finish := Position;
    if Length(FText) = 0 then
    begin
        Exit;
    end;
    if Position = Length(FText) then
    begin
        Dec(Position);
    end;

    Kind := CharacterType(FText[Position + 1]);
    if Kind = ctLineBreak then
    begin
        Exit;
    end;
    Start := Position;
    Finish := Position + 1;
    while (Start > 0) and (CharacterType(FText[Start]) = Kind) do
    begin
        Dec(Start);
    end;
    while (Finish < Length(FText)) and (CharacterType(FText[Finish + 1]) = Kind) do
    begin
        Inc(Finish);
    end;
end;

// Finds a logical line without its terminating CR, LF or CRLF.
procedure TSelectionEditHandler.LineBounds(Position: Integer; var Start, Finish: Integer);
begin
    if (Position > 0) and (Position < Length(FText)) and
        (FText[Position + 1] = #10) and (FText[Position] = #13) then
    begin
        Dec(Position);
    end;

    Start := Position;
    while (Start > 0) and (FText[Start] <> #13) and (FText[Start] <> #10) do
    begin
        Dec(Start);
    end;
    Finish := Position;
    while (Finish < Length(FText)) and (FText[Finish + 1] <> #13) and (FText[Finish + 1] <> #10) do
    begin
        Inc(Finish);
    end;
end;

// Stops the timer and capture and drops cached text without clearing the visible selection.
procedure TSelectionEditHandler.EndSelection;
var
    EditHandle: HWND;
begin
    FUnit := suNone;
    FText := '';
    if not FEdit.HandleAllocated then
    begin
        Exit;
    end;
    EditHandle := FEdit.Handle;
    KillTimer(EditHandle, SelectionScrollTimer);
    if GetCapture = EditHandle then
    begin
        ReleaseCapture;
    end;
end;

// Scrolls a held selection vertically when the pointer leaves the text rectangle.
procedure TSelectionEditHandler.ScrollSelection(const Point: TPoint);
var
    Area: TRect;
begin
    FillChar(Area, SizeOf(Area), 0);
    SendMessage(FEdit.Handle, EM_GETRECT, 0, Longint(@Area));
    if (Area.Right <= Area.Left) or (Area.Bottom <= Area.Top) then
    begin
        GetClientRect(FEdit.Handle, Area);
    end;

    if Point.Y < Area.Top then
    begin
        SendMessage(FEdit.Handle, WM_VSCROLL, SB_LINEUP, 0);
        SetTimer(FEdit.Handle, SelectionScrollTimer, 50, nil);
    end
    else if Point.Y >= Area.Bottom then
    begin
        SendMessage(FEdit.Handle, WM_VSCROLL, SB_LINEDOWN, 0);
        SetTimer(FEdit.Handle, SelectionScrollTimer, 50, nil);
    end
    else
    begin
        KillTimer(FEdit.Handle, SelectionScrollTimer);
    end;
end;

// Preserves the NT 3.x anchor inside the click rectangle, then extends by whole units on drag.
procedure TSelectionEditHandler.UpdateSelection(const Point: TPoint; Scroll: Boolean);
var
    Position: Integer;
    Start: Integer;
    Finish: Integer;
begin
    FMousePoint := Point;
    if FUseNativePosition and ContinuesClickSequence(Point, FClickTime) then
    begin
        SendMessage(FEdit.Handle, EM_SETSEL, FAnchorStart, FAnchorEnd);
        Exit;
    end;
    if Scroll then
    begin
        ScrollSelection(Point);
    end;
    Position := SelectionPosition(Point);
    if (Position >= FAnchorStart) and (Position <= FAnchorEnd) then
    begin
        SendMessage(FEdit.Handle, EM_SETSEL, FAnchorStart, FAnchorEnd);
        Exit;
    end;

    if FUnit = suLine then
    begin
        LineBounds(Position, Start, Finish);
    end
    else
    begin
        WordBounds(Position, Start, Finish);
    end;
    FClickCount := 0;
    if Position < FAnchorStart then
    begin
        SendMessage(FEdit.Handle, EM_SETSEL, FAnchorEnd, Start);
    end
    else
    begin
        SendMessage(FEdit.Handle, EM_SETSEL, FAnchorStart, Finish);
    end;
end;

// Starts a captured word or line gesture; NT 3.x reuses the previous word anchor on odd clicks
// and obtains a native caret position for every even click.
procedure TSelectionEditHandler.BeginSelection(
    const Point: TPoint; ButtonState: WPARAM);
var
    Position: Integer;
begin
    FText := FEdit.Text;
    if FUseNativePosition and Odd(FClickCount) then
    begin
        Position := FAnchorStart;
    end
    else if FUseNativePosition then
    begin
        Position := NativePosition(Point, ButtonState);
    end
    else
    begin
        Position := SelectionPosition(Point);
    end;
    if Odd(FClickCount) then
    begin
        FUnit := suLine;
        LineBounds(Position, FAnchorStart, FAnchorEnd);
    end
    else
    begin
        FUnit := suWord;
        WordBounds(Position, FAnchorStart, FAnchorEnd);
    end;
    FMousePoint := Point;
    SetCapture(FEdit.Handle);
    SendMessage(FEdit.Handle, EM_SETSEL, FAnchorStart, FAnchorEnd);
end;

// Uses the same word-selection path for the second and later even clicks, and handles
// Ctrl+A, drag scrolling, capture changes and gesture cancellation.
procedure TSelectionEditHandler.WindowProc(var Message: TMessage);
var
    Point: TPoint;
    Time: Int64;
    NativeMessage: TMessage;
    KeyMessage: PMsg;
begin
    case Message.Msg of
        WM_GETDLGCODE:
        begin
            FPreviousWindowProc(Message);
            if Message.WParam = VK_TAB then
            begin
                Message.Result := Message.Result and not (DLGC_WANTTAB or DLGC_WANTALLKEYS);
            end;
            if Message.LParam <> 0 then
            begin
                KeyMessage := PMsg(Message.LParam);
                if ((KeyMessage.message = WM_KEYDOWN) and (KeyMessage.wParam = Ord('A')) and
                    (GetKeyState(VK_CONTROL) < 0)) or
                    ((KeyMessage.message = WM_CHAR) and (KeyMessage.wParam = 1)) then
                begin
                    Message.Result := Message.Result or DLGC_WANTMESSAGE;
                end;
            end;
            Exit;
        end;
        WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
        begin
            EndSelection;
            if Message.WParam and (MK_SHIFT or MK_CONTROL) <> 0 then
            begin
                FClickCount := 0;
                FPreviousWindowProc(Message);
                Exit;
            end;

            FEdit.SetFocus;
            Point.X := SmallInt(LoWord(Message.LParam));
            Point.Y := SmallInt(HiWord(Message.LParam));
            Time := ClickTime;
            if not ContinuesClickSequence(Point, Time) then
            begin
                FClickCount := 1;
            end
            else
            begin
                Inc(FClickCount);
            end;
            FClickPoint := Point;
            FClickTime := Time;
            if FClickCount >= 2 then
            begin
                BeginSelection(Point, Message.WParam);
                Message.Result := 0;
                Exit;
            end;

            FUnit := suNative;
            NativeMessage := Message;
            NativeMessage.Msg := WM_LBUTTONDOWN;
            FPreviousWindowProc(NativeMessage);
            Message.Result := NativeMessage.Result;
            Exit;
        end;
        WM_MOUSEMOVE:
        begin
            if FUnit in [suWord, suLine] then
            begin
                if Message.WParam and MK_LBUTTON <> 0 then
                begin
                    Point.X := SmallInt(LoWord(Message.LParam));
                    Point.Y := SmallInt(HiWord(Message.LParam));
                    UpdateSelection(Point, True);
                end
                else
                begin
                    FClickCount := 0;
                    EndSelection;
                end;
                Message.Result := 0;
                Exit;
            end;
        end;
        WM_LBUTTONUP:
        begin
            if FUnit in [suWord, suLine] then
            begin
                Point.X := SmallInt(LoWord(Message.LParam));
                Point.Y := SmallInt(HiWord(Message.LParam));
                UpdateSelection(Point, False);
                EndSelection;
                Message.Result := 0;
                Exit;
            end;
            if FUnit = suNative then
            begin
                FUnit := suNone;
                FPreviousWindowProc(Message);
                if (FClickCount = 1) and (FEdit.SelLength <> 0) then
                begin
                    FClickCount := 0;
                end;
                Exit;
            end;
        end;
        WM_TIMER:
        begin
            if Message.WParam = SelectionScrollTimer then
            begin
                if FUnit in [suWord, suLine] then
                begin
                    UpdateSelection(FMousePoint, True);
                end;
                Message.Result := 0;
                Exit;
            end;
        end;
        WM_CAPTURECHANGED:
        begin
            if (HWND(Message.LParam) <> FEdit.Handle) and (FUnit <> suNone) then
            begin
                FClickCount := 0;
                EndSelection;
            end;
        end;
        WM_KEYDOWN:
        begin
            FClickCount := 0;
            EndSelection;
            if (Message.WParam = Ord('A')) and (GetKeyState(VK_CONTROL) < 0) then
            begin
                FEdit.SelectAll;
                Message.Result := 0;
                Exit;
            end;
        end;
        WM_CHAR:
        begin
            if Message.WParam = 1 then
            begin
                FEdit.SelectAll;
                Message.Result := 0;
                Exit;
            end;
        end;
        WM_CANCELMODE, WM_KILLFOCUS, WM_RBUTTONDOWN, WM_RBUTTONDBLCLK,
        WM_MBUTTONDOWN, WM_MBUTTONDBLCLK, SelectionXButtonDown,
        SelectionXButtonDoubleClick, EM_REPLACESEL, WM_SETTEXT, WM_NCDESTROY:
        begin
            FClickCount := 0;
            EndSelection;
        end;
    end;

    FPreviousWindowProc(Message);
end;

end.
