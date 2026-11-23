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

Last modified for version 1.1.1.0
}

// Displays system details and handles refresh, copying, and extended edit selection.
unit MainForm;

interface

uses
    Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls, SelectionEdit, WindowsRelease;

type
    // Owns the information controls and their edit-selection handlers.
    TMainForm = class(TForm)
        OperatingSystemLabel: TLabel;
        OperatingSystemEdit: TEdit;
        VirtualBoxNameLabel: TLabel;
        VirtualBoxNameEdit: TEdit;
        ProcessorLabel: TLabel;
        ProcessorEdit: TEdit;
        ArchitectureLabel: TLabel;
        ArchitectureEdit: TEdit;
        ProcessorCountLabel: TLabel;
        ProcessorCountEdit: TEdit;
        MemoryLabel: TLabel;
        MemoryEdit: TEdit;
        SystemDiskLabel: TLabel;
        SystemDiskEdit: TEdit;
        DotNetLabel: TLabel;
        DotNetEdit: TEdit;
        RefreshButton: TButton;
        CopyButton: TButton;
        CloseButton: TButton;

        // Applies the Windows font and icon, fills fields, and installs edit-selection handlers.
        procedure FormCreate(Sender: TObject);

        // Uses the same complete refresh operation as the F5 shortcut.
        procedure RefreshButtonClick(Sender: TObject);

        // Copies the displayed snapshot, including every label and value, in the visual tab order.
        procedure CopyButtonClick(Sender: TObject);

        // Closes the main form; the button also handles Escape through its Cancel property.
        procedure CloseButtonClick(Sender: TObject);

        // KeyPreview routes F5 here even when one of the read-only edits has keyboard focus.
        procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

    private
        FOperatingSystemSelection: TSelectionEditHandler;
        FVirtualBoxSelection: TSelectionEditHandler;
        FProcessorSelection: TSelectionEditHandler;
        FArchitectureSelection: TSelectionEditHandler;
        FProcessorCountSelection: TSelectionEditHandler;
        FMemorySelection: TSelectionEditHandler;
        FSystemDiskSelection: TSelectionEditHandler;
        FDotNetSelection: TSelectionEditHandler;

        // Reads kernel32.dll's file version; Win9x uses its three-part display format.
        function GetKernelVersion(LegacyFormat: Boolean; out Version: TWindowsFileVersion;
            out ReactOSVersion: string): string;

        // Uses the System Properties release number for Windows 95 and the API version for other systems.
        procedure SetVersionInformation;

        // Applies the current Windows message font to the form and inheriting controls.
        procedure ApplySystemDialogFont;

        // Reloads every displayed value, including available .NET runtimes and current free capacities.
        procedure RefreshInformation;

    protected
        // Reapplies the Windows font after the system broadcasts a settings change.
        procedure WMSettingChange(var Message: TWMSettingChange); message WM_SETTINGCHANGE;

        // Invalidates the form and its child controls after keyboard cues change.
        procedure WMUpdateUIState(var Message: TMessage); message WM_UPDATEUISTATE;

    public
        // Detaches edit hooks before the form destroys their controls.
        destructor Destroy; override;
    end;

var
    Form: TMainForm;

implementation

uses
    HardwareInfo, DotNetInfo, Clipbrd;

// Windows product/suite identifiers and the Windows 95 display release number.
const
    NTWorkstationProductType = 1;
    NTEnterpriseSuite = $0002;
    NTDatacenterSuite = $0080;
    NTWebSuite = $0400;
    ServerR2SystemMetric = 89;
    Windows95DisplayBuild = 950;

type
    // Matches OSVERSIONINFOEXW, including service-pack, suite, and product-type fields.
    TRtlOSVersionInfoExW = record
        dwOSVersionInfoSize: DWORD;
        dwMajorVersion: DWORD;
        dwMinorVersion: DWORD;
        dwBuildNumber: DWORD;
        dwPlatformId: DWORD;
        szCSDVersion: array[0..127] of WideChar;
        wServicePackMajor: Word;
        wServicePackMinor: Word;
        wSuiteMask: Word;
        wProductType: Byte;
        wReserved: Byte;
    end;
    // Optional native version query that avoids manifest-based GetVersionEx limits.
    TRtlGetVersion = function(var VersionInfo: TRtlOSVersionInfoExW): LongInt; stdcall;

{$R *.dfm}

// Reads kernel32.dll's file version; Win9x uses its three-part display format.
function TMainForm.GetKernelVersion(LegacyFormat: Boolean; out Version: TWindowsFileVersion;
    out ReactOSVersion: string): string;
var
    FileName: string;
    SystemDirectory: array[0..MAX_PATH] of Char;
    Size: DWORD;
    Handle: DWORD;
    Buffer: Pointer;
    Info: PVSFixedFileInfo;
    InfoSize: UINT;
begin
    Result := '';
    ReactOSVersion := '';
    FillChar(Version, SizeOf(Version), 0);
    if GetSystemDirectory(SystemDirectory, SizeOf(SystemDirectory)) = 0 then
        Exit;

    FileName := IncludeTrailingPathDelimiter(SystemDirectory) + 'kernel32.dll';
    Size := GetFileVersionInfoSize(PChar(FileName), Handle);
    if Size = 0 then
        Exit;

    GetMem(Buffer, Size);
    try
        if GetFileVersionInfo(PChar(FileName), 0, Size, Buffer) and
            VerQueryValue(Buffer, '\', Pointer(Info), InfoSize) then
        begin
            Version.Available := True;
            Version.Major := HiWord(Info.dwFileVersionMS);
            Version.Minor := LoWord(Info.dwFileVersionMS);
            Version.Build := HiWord(Info.dwFileVersionLS);
            Version.Revision := LoWord(Info.dwFileVersionLS);
            ReactOSVersion := ReadReactOSVersion(Buffer, Info^);
            if LegacyFormat then
            begin
                Result := Format('%d.%.2d.%d', [
                    HiWord(Info.dwFileVersionMS),
                    LoWord(Info.dwFileVersionMS),
                    LoWord(Info.dwFileVersionLS)
                ]);
            end
            else
            begin
                Result := Format('%d.%d.%d.%d', [
                    HiWord(Info.dwFileVersionMS),
                    LoWord(Info.dwFileVersionMS),
                    HiWord(Info.dwFileVersionLS),
                    LoWord(Info.dwFileVersionLS)
                ]);
            end;
        end;
    finally
        FreeMem(Buffer);
    end;
end;

// Standard Edition has no dedicated suite flag; other Server 2003 editions set their suite flags.
function GetServer2003Edition(SuiteMask: Word): string;
begin
    if SuiteMask and NTDatacenterSuite <> 0 then
    begin
        Result := 'Datacenter';
    end
    else if SuiteMask and NTEnterpriseSuite <> 0 then
    begin
        Result := 'Enterprise';
    end
    else if SuiteMask and NTWebSuite <> 0 then
    begin
        Result := 'Web';
    end
    else
    begin
        Result := 'Standard';
    end;
end;

// Uses the System Properties release number for Windows 95 and the API version for other systems.
procedure TMainForm.SetVersionInformation;
var
    OS: TOSVersionInfo;
    RtlOS: TRtlOSVersionInfoExW;
    RtlGetVersion: TRtlGetVersion;
    IsServer: Boolean;
    BuildNumber: DWORD;
    Name: string;
    ShortName: string;
    Edition: string;
    FriendlyName: string;
    ServicePack: string;
    ShortServicePack: string;
    Language: string;
    VersionText: string;
    KernelVersion: string;
    ReactOSVersion: string;
    Kernel: TWindowsFileVersion;
    ProductName: string;
    BuildLab: string;
    DevelopmentName: string;
    FeatureVersion: string;
    Details: string;
    FriendlyDetails: string;
    LanguageBuffer: array[0..15] of Char;
begin
    FillChar(OS, SizeOf(OS), 0);
    OS.dwOSVersionInfoSize := SizeOf(OS);
    if not GetVersionEx(OS) then
    begin
        OperatingSystemEdit.Text := 'Unknown Windows version';
        VirtualBoxNameEdit.Text := 'Unknown Windows';
        Exit;
    end;

    IsServer := False;
    ProductName := '';
    if OS.dwPlatformId = VER_PLATFORM_WIN32_NT then
    begin
        ReadWindowsBuildMetadata(ProductName, BuildLab);
        RtlGetVersion := TRtlGetVersion(GetProcAddress(GetModuleHandle('ntdll.dll'), 'RtlGetVersion'));
        if Assigned(RtlGetVersion) then
        begin
            FillChar(RtlOS, SizeOf(RtlOS), 0);
            RtlOS.dwOSVersionInfoSize := SizeOf(RtlOS);
            if RtlGetVersion(RtlOS) = 0 then
            begin
                OS.dwMajorVersion := RtlOS.dwMajorVersion;
                OS.dwMinorVersion := RtlOS.dwMinorVersion;
                OS.dwBuildNumber := RtlOS.dwBuildNumber;
                IsServer := RtlOS.wProductType <> NTWorkstationProductType;
            end;
        end;
    end;

    BuildNumber := OS.dwBuildNumber;
    if OS.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS then
        BuildNumber := BuildNumber and $FFFF;

    Name := '';
    Edition := '';
    if OS.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS then
    begin
        case OS.dwMinorVersion of
            0: Name := '95';
            10: Name := '98';
            90: Name := 'Me';
        end;
    end
    else if OS.dwPlatformId = VER_PLATFORM_WIN32_NT then
    begin
        case OS.dwMajorVersion of
            3, 4: Name := 'NT';
            5: case OS.dwMinorVersion of
                0: if IsServer then Name := '2000 Server' else Name := '2000';
                1: Name := 'XP';
                2: if IsServer then
                begin
                    Name := 'Server 2003';
                    if GetSystemMetrics(ServerR2SystemMetric) <> 0 then
                    begin
                        Name := Name + ' R2';
                    end;
                    Edition := GetServer2003Edition(RtlOS.wSuiteMask);
                end
                else
                begin
                    Name := 'XP';
                end;
            end;
            6: case OS.dwMinorVersion of
                0: if IsServer then Name := 'Server 2008' else Name := 'Vista';
                1: if IsServer then Name := 'Server 2008 R2' else Name := '7';
                2: if IsServer then Name := 'Server 2012' else Name := '8';
                3: if IsServer then Name := 'Server 2012 R2' else Name := '8.1';
            end;
            10: if IsServer then
            begin
                if BuildNumber >= 26100 then
                    Name := 'Server 2025'
                else if BuildNumber >= 20348 then
                    Name := 'Server 2022'
                else if BuildNumber >= 17763 then
                    Name := 'Server 2019'
                else
                    Name := 'Server 2016';
            end
            else if BuildNumber >= 22000 then
                Name := '11'
            else
                Name := '10';
        end;
    end;

    if (OS.dwPlatformId = VER_PLATFORM_WIN32_NT)
        and (OS.dwMajorVersion = 10)
        and (OS.dwMinorVersion = 0)
        and not IsServer then
    begin
        FeatureVersion := ReadWindowsFeatureVersion(BuildNumber);
        if FeatureVersion <> '' then
        begin
            Name := Name + ' ' + FeatureVersion;
        end;
    end;

    KernelVersion := GetKernelVersion(OS.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS,
        Kernel, ReactOSVersion);
    if (OS.dwPlatformId = VER_PLATFORM_WIN32_NT)
            and ((OS.dwMajorVersion = 5) or ((OS.dwMajorVersion = 6) and (OS.dwMinorVersion = 0))) then
    begin
        DevelopmentName := WindowsDevelopmentName(OS.dwMajorVersion, OS.dwMinorVersion,
            BuildNumber, IsServer, Kernel, ProductName, BuildLab);
        if DevelopmentName <> '' then
        begin
            Name := DevelopmentName;
            Edition := '';
        end;
    end;

    if OS.dwPlatformId = VER_PLATFORM_WIN32_WINDOWS then
    begin
        if Name = '95' then
        begin
            VersionText := Format('%d.%.2d.%d', [
                OS.dwMajorVersion,
                OS.dwMinorVersion,
                Windows95DisplayBuild
            ]);
        end
        else
        begin
            VersionText := Format('%d.%.2d.%d', [
                OS.dwMajorVersion,
                OS.dwMinorVersion,
                BuildNumber
            ]);
        end;
    end
    else
    begin
        VersionText := Format('%d.%d.%d', [
            OS.dwMajorVersion,
            OS.dwMinorVersion,
            BuildNumber
        ]);
    end;
    ServicePack := Trim(OS.szCSDVersion);
    if (Name = '95') and ((ServicePack = 'B') or (ServicePack = 'C')) then
    begin
        Name := '95 OEM';
    end;
    ShortServicePack := ServicePack;
    if Pos('Service Pack ', ShortServicePack) = 1 then
        ShortServicePack := 'SP' + Copy(ShortServicePack, 14, MaxInt);

    if GetLocaleInfo(LOCALE_SYSTEM_DEFAULT, LOCALE_SABBREVLANGNAME,
        LanguageBuffer, SizeOf(LanguageBuffer) div SizeOf(Char)) > 0 then
        Language := LanguageBuffer
    else
        Language := '???';

    Details := VersionText;
    FriendlyDetails := VersionText;
    if ServicePack <> '' then
    begin
        Details := Details + ' ' + ServicePack;
        FriendlyDetails := FriendlyDetails + ' ' + ShortServicePack;
    end;
    if KernelVersion <> '' then
    begin
        Details := Details + ' (' + KernelVersion + ')';
        FriendlyDetails := FriendlyDetails + ' (' + KernelVersion + ')';
    end;
    Details := Details + ' ' + Language;
    FriendlyDetails := FriendlyDetails + ' ' + GetProcessorArchitecture(False) + ' ' + UpperCase(Language);

    ShortName := Name;
    if Edition <> '' then
    begin
        ShortName := Name + ' ' + Edition;
        Name := ShortName + ' Edition';
    end;

    if Name = '' then
    begin
        OperatingSystemEdit.Text := 'Windows ' + Details;
        FriendlyName := 'Windows';
    end
    else
    begin
        OperatingSystemEdit.Text := 'Windows ' + Name + ' ' + Details;
        if Pos('Server ', ShortName) = 1 then
        begin
            FriendlyName := 'W ' + ShortName;
        end
        else
        begin
            FriendlyName := 'Windows ' + ShortName;
        end;
    end;
    if ReactOSVersion <> '' then
    begin
        FriendlyName := 'ReactOS ' + ReactOSVersion + ' NT';
    end
    else if SameText(Trim(ProductName), 'ReactOS') then
    begin
        FriendlyName := 'ReactOS NT';
    end;
    VirtualBoxNameEdit.Text := FriendlyName + ' ' + FriendlyDetails;
end;

// Detaches edit hooks before the form destroys their controls.
destructor TMainForm.Destroy;
begin
    FreeAndNil(FDotNetSelection);
    FreeAndNil(FSystemDiskSelection);
    FreeAndNil(FMemorySelection);
    FreeAndNil(FProcessorCountSelection);
    FreeAndNil(FArchitectureSelection);
    FreeAndNil(FProcessorSelection);
    FreeAndNil(FVirtualBoxSelection);
    FreeAndNil(FOperatingSystemSelection);
    inherited Destroy;
end;

// Applies the current Windows message font to the form and inheriting controls.
procedure TMainForm.ApplySystemDialogFont;
var
    Metrics: TNonClientMetrics;
    DialogFont: HFONT;
begin
    FillChar(Metrics, SizeOf(Metrics), 0);
    Metrics.cbSize := SizeOf(Metrics);
    if not SystemParametersInfo(SPI_GETNONCLIENTMETRICS, SizeOf(Metrics), @Metrics, 0) then
    begin
        Exit;
    end;

    DialogFont := CreateFontIndirect(Metrics.lfMessageFont);
    if DialogFont <> 0 then
    begin
        Font.Handle := DialogFont;
    end;
end;

// Reapplies the Windows font after the system broadcasts a settings change.
procedure TMainForm.WMSettingChange(var Message: TWMSettingChange);
begin
    inherited;
    ApplySystemDialogFont;
end;

// Invalidates the form and its child controls after keyboard cues change.
procedure TMainForm.WMUpdateUIState(var Message: TMessage);
begin
    inherited;
    RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
end;

// Reloads every displayed value, including available .NET runtimes and current free capacities.
procedure TMainForm.RefreshInformation;
begin
    SetVersionInformation;
    ProcessorEdit.Text := GetProcessorModel;
    ArchitectureEdit.Text := GetProcessorArchitecture;
    ProcessorCountEdit.Text := GetProcessorInformation;
    MemoryEdit.Text := GetMemoryInformation;
    SystemDiskEdit.Text := GetSystemDiskInformation;
    DotNetEdit.Text := GetAvailableDotNetRuntimes;
end;

// KeyPreview routes F5 here even when one of the read-only edits has keyboard focus.
procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
    if Key = VK_F5 then
    begin
        RefreshInformation;
        Key := 0;
    end;
end;

// Applies the Windows font and icon, fills fields, and installs edit-selection handlers.
procedure TMainForm.FormCreate(Sender: TObject);
begin
    ApplySystemDialogFont;
    Icon.Handle := CopyIcon(LoadIcon(HInstance, 'MAINICON'));
    Application.Icon.Assign(Icon);
    RefreshInformation;
    FOperatingSystemSelection := TSelectionEditHandler.Create(Self, OperatingSystemEdit);
    FVirtualBoxSelection := TSelectionEditHandler.Create(Self, VirtualBoxNameEdit);
    FProcessorSelection := TSelectionEditHandler.Create(Self, ProcessorEdit);
    FArchitectureSelection := TSelectionEditHandler.Create(Self, ArchitectureEdit);
    FProcessorCountSelection := TSelectionEditHandler.Create(Self, ProcessorCountEdit);
    FMemorySelection := TSelectionEditHandler.Create(Self, MemoryEdit);
    FSystemDiskSelection := TSelectionEditHandler.Create(Self, SystemDiskEdit);
    FDotNetSelection := TSelectionEditHandler.Create(Self, DotNetEdit);
end;

// Uses the same complete refresh operation as the F5 shortcut.
procedure TMainForm.RefreshButtonClick(Sender: TObject);
begin
    RefreshInformation;
end;

// Copies the displayed snapshot, including every label and value, in the visual tab order.
procedure TMainForm.CopyButtonClick(Sender: TObject);
begin
    Clipboard.AsText := OperatingSystemLabel.Caption + ': ' + OperatingSystemEdit.Text + #13#10 +
        VirtualBoxNameLabel.Caption + ': ' + VirtualBoxNameEdit.Text + #13#10 +
        ProcessorLabel.Caption + ': ' + ProcessorEdit.Text + #13#10 +
        ArchitectureLabel.Caption + ': ' + ArchitectureEdit.Text + #13#10 +
        ProcessorCountLabel.Caption + ': ' + ProcessorCountEdit.Text + #13#10 +
        MemoryLabel.Caption + ': ' + MemoryEdit.Text + #13#10 +
        SystemDiskLabel.Caption + ': ' + SystemDiskEdit.Text + #13#10 +
        DotNetLabel.Caption + ': ' + DotNetEdit.Text;
end;

// Closes the main form; the button also handles Escape through its Cancel property.
procedure TMainForm.CloseButtonClick(Sender: TObject);
begin
    Close;
end;

end.
