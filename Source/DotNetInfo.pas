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

Last modified for version 1.1.0.0
}

// Detects installed Framework releases and shared runtimes without loading their binaries.
unit DotNetInfo;

interface

// Rebuilds the Framework and shared-runtime display text without loading runtimes.
function GetAvailableDotNetRuntimes: string;

implementation

uses
    Windows, SysUtils, Classes, Registry;

// Registry paths for Framework setup and legacy 1.0 service-pack metadata.
const
    FrameworkRoot = '\SOFTWARE\Microsoft\NET Framework Setup\NDP\';
    Framework10Key = '\SOFTWARE\Microsoft\.NETFramework\Policy\v1.0';
    Framework10ServicePackKey = '\SOFTWARE\Microsoft\Active Setup\Installed Components\' +
        '{78705F0D-E8DB-4B2D-8193-982BDDA15ECD}';

// Maps the Framework 4 Release registry value to its installed product version.
function Framework4Name(ReleaseKey: Integer): string;
begin
    case ReleaseKey of
        533320..MaxInt: Result := '4.8.1';
        528040..533319: Result := '4.8';
        461808..528039: Result := '4.7.2';
        461308..461807: Result := '4.7.1';
        460798..461307: Result := '4.7';
        394802..460797: Result := '4.6.2';
        394254..394801: Result := '4.6.1';
        393295..394253: Result := '4.6';
        379893..393294: Result := '4.5.2';
        378675..379892: Result := '4.5.1';
        378389..378674: Result := '4.5';
    else
        Result := '4.0';
    end;
end;

// Adds an installed Framework version and its service pack when the setup flag is set.
procedure AddFrameworkVersion(Registry: TRegistry; Versions: TStrings;
    const Key, InstallValue, Version: string);
var
    DisplayVersion: string;
    ServicePack: Integer;
begin
    if not Registry.OpenKey(Key, False) then
    begin
        Exit;
    end;
    if not Registry.ValueExists(InstallValue) then
    begin
        Exit;
    end;
    if Registry.ReadInteger(InstallValue) <> 1 then
    begin
        Exit;
    end;

    DisplayVersion := Version;
    if Registry.ValueExists('SP') then
    begin
        ServicePack := Registry.ReadInteger('SP');
        if ServicePack > 0 then
        begin
            DisplayVersion := DisplayVersion + ' SP' + IntToStr(ServicePack);
        end;
    end;
    Versions.Add(DisplayVersion);
end;

// Reads the Framework 1.0 service pack from the final Active Setup Version field.
function GetFramework10Version(Registry: TRegistry): string;
var
    SetupVersion: string;
    Separator: Integer;
    ServicePack: Integer;
begin
    Result := '1.0';
    if not Registry.OpenKey(Framework10ServicePackKey, False) then
    begin
        Exit;
    end;
    if not Registry.ValueExists('Version') then
    begin
        Exit;
    end;

    SetupVersion := Registry.ReadString('Version');
    Separator := LastDelimiter(',', SetupVersion);
    if Separator = 0 then
    begin
        Exit;
    end;
    ServicePack := StrToIntDef(Copy(SetupVersion, Separator + 1, MaxInt), 0);
    if ServicePack > 0 then
    begin
        Result := Result + ' SP' + IntToStr(ServicePack);
    end;
end;

// Collects Framework releases from setup keys, including the legacy 1.0 policy value.
procedure CollectFrameworkVersions(Versions: TStrings);
var
    Version: string;
    FrameworkRegistry: TRegistry;
begin
    FrameworkRegistry := TRegistry.Create(KEY_READ);
    try
        FrameworkRegistry.RootKey := HKEY_LOCAL_MACHINE;
        if FrameworkRegistry.OpenKey(Framework10Key, False) then
        begin
            if FrameworkRegistry.ValueExists('3705') then
            begin
                if Trim(FrameworkRegistry.ReadString('3705')) <> '' then
                begin
                    Versions.Add(GetFramework10Version(FrameworkRegistry));
                end;
            end;
        end;

        AddFrameworkVersion(FrameworkRegistry, Versions, FrameworkRoot + 'v1.1.4322', 'Install', '1.1');
        AddFrameworkVersion(FrameworkRegistry, Versions, FrameworkRoot + 'v2.0.50727', 'Install', '2.0');
        AddFrameworkVersion(FrameworkRegistry, Versions, FrameworkRoot + 'v3.0\Setup',
            'InstallSuccess', '3.0');
        AddFrameworkVersion(FrameworkRegistry, Versions, FrameworkRoot + 'v3.5', 'Install', '3.5');

        Version := '';
        if FrameworkRegistry.OpenKey(FrameworkRoot + 'v4\Full', False) then
        begin
            if FrameworkRegistry.ValueExists('Release') then
            begin
                Version := Framework4Name(FrameworkRegistry.ReadInteger('Release'));
            end
            else if FrameworkRegistry.ValueExists('Install') then
            begin
                if FrameworkRegistry.ReadInteger('Install') = 1 then
                begin
                    Version := '4.0';
                end;
            end;
        end;
        if Version = '' then
        begin
            if FrameworkRegistry.OpenKey(FrameworkRoot + 'v4\Client', False) then
            begin
                if FrameworkRegistry.ValueExists('Install') then
                begin
                    if FrameworkRegistry.ReadInteger('Install') = 1 then
                    begin
                        Version := '4.0 Client';
                    end;
                end;
            end;
        end;
        if Version <> '' then
        begin
            Versions.Add(Version);
        end;
    finally
        FrameworkRegistry.Free;
    end;
end;

// Collects version-named directories for one runtime below the dotnet shared directory.
procedure CollectRuntimeVersions(const Root, RuntimeName: string; Versions: TStrings);
var
    RuntimePath: string;
    Search: TSearchRec;
begin
    RuntimePath := IncludeTrailingPathDelimiter(Root) + 'shared\' + RuntimeName;
    if FindFirst(IncludeTrailingPathDelimiter(RuntimePath) + '*', faDirectory, Search) <> 0 then
    begin
        Exit;
    end;
    try
        repeat
            if (Search.Attr and faDirectory) <> 0 then
            begin
                if (Search.Name <> '.') and (Search.Name <> '..') then
                begin
                    if (Search.Name[1] in ['0'..'9']) and (Pos('.', Search.Name) > 1) then
                    begin
                        Versions.Add(Search.Name);
                    end;
                end;
            end;
        until FindNext(Search) <> 0;
    finally
        FindClose(Search);
    end;
end;

// Scans one dotnet root for the base, Windows Desktop, and ASP.NET Core runtimes.
procedure CollectDotNetRoot(const Root: string; Core, Desktop, AspNet: TStrings);
begin
    CollectRuntimeVersions(Root, 'Microsoft.NETCore.App', Core);
    CollectRuntimeVersions(Root, 'Microsoft.WindowsDesktop.App', Desktop);
    CollectRuntimeVersions(Root, 'Microsoft.AspNetCore.App', AspNet);
end;

// Scans standard installation roots and DOTNET_ROOT for modern shared runtimes.
procedure CollectModernVersions(Core, Desktop, AspNet: TStrings);
var
    Root: string;
begin
    Root := GetEnvironmentVariable('ProgramFiles');
    if Root <> '' then
    begin
        CollectDotNetRoot(IncludeTrailingPathDelimiter(Root) + 'dotnet', Core, Desktop, AspNet);
    end;
    Root := GetEnvironmentVariable('ProgramW6432');
    if Root <> '' then
    begin
        CollectDotNetRoot(IncludeTrailingPathDelimiter(Root) + 'dotnet', Core, Desktop, AspNet);
    end;
    Root := GetEnvironmentVariable('ProgramFiles(x86)');
    if Root <> '' then
    begin
        CollectDotNetRoot(IncludeTrailingPathDelimiter(Root) + 'dotnet', Core, Desktop, AspNet);
    end;
    Root := GetEnvironmentVariable('DOTNET_ROOT');
    if Root <> '' then
    begin
        CollectDotNetRoot(Root, Core, Desktop, AspNet);
    end;
end;

// Extracts dotted numeric components and returns any service-pack or prerelease suffix.
function SplitVersion(const Version: string; Components: TStrings): string;
var
    Position: Integer;
    NumericPart: string;
begin
    Position := 1;
    while (Position <= Length(Version)) and (Version[Position] in ['0'..'9', '.']) do
    begin
        Inc(Position);
    end;
    NumericPart := Copy(Version, 1, Position - 1);
    ExtractStrings(['.'], [], PChar(NumericPart), Components);
    Result := Copy(Version, Position, MaxInt);
end;

// Reads a nonnegative numeric component without an integer-size limit.
function ReadVersionNumber(const Version: string; var Position: Integer): string;
var
    Start: Integer;
begin
    Start := Position;
    while (Position <= Length(Version)) and (Version[Position] in ['0'..'9']) do
    begin
        Inc(Position);
    end;
    Result := Copy(Version, Start, Position - Start);
    while (Length(Result) > 1) and (Result[1] = '0') do
    begin
        Delete(Result, 1, 1);
    end;
end;

// Compares numeric values exactly, including values larger than a native integer.
function CompareVersionNumbers(const First, Second: string): Integer;
begin
    Result := Length(First) - Length(Second);
    if Result = 0 then
    begin
        Result := CompareStr(First, Second);
    end;
end;

// Orders service-pack numbers numerically and prereleases before their matching stable release.
function CompareVersionSuffixes(const First, Second: string): Integer;
var
    FirstNumber: string;
    SecondNumber: string;
    FirstPosition: Integer;
    SecondPosition: Integer;
begin
    FirstPosition := 1;
    SecondPosition := 1;
    while (FirstPosition <= Length(First)) and (SecondPosition <= Length(Second)) do
    begin
        if (First[FirstPosition] in ['0'..'9']) and (Second[SecondPosition] in ['0'..'9']) then
        begin
            FirstNumber := ReadVersionNumber(First, FirstPosition);
            SecondNumber := ReadVersionNumber(Second, SecondPosition);
            Result := CompareVersionNumbers(FirstNumber, SecondNumber);
        end
        else
        begin
            Result := Ord(First[FirstPosition]) - Ord(Second[SecondPosition]);
            Inc(FirstPosition);
            Inc(SecondPosition);
        end;
        if Result <> 0 then
        begin
            Exit;
        end;
    end;
    Result := 0;
    if FirstPosition <= Length(First) then
    begin
        if First[FirstPosition] = '-' then
        begin
            Result := -1;
        end
        else
        begin
            Result := 1;
        end;
    end
    else if SecondPosition <= Length(Second) then
    begin
        if Second[SecondPosition] = '-' then
        begin
            Result := 1;
        end
        else
        begin
            Result := -1;
        end;
    end;
end;

// Compares corresponding dotted numeric components before comparing version suffixes.
function CompareVersions(Versions: TStringList; FirstIndex, SecondIndex: Integer): Integer;
var
    FirstParts: TStringList;
    SecondParts: TStringList;
    FirstSuffix: string;
    SecondSuffix: string;
    FirstNumber: string;
    SecondNumber: string;
    Count: Integer;
    Index: Integer;
    Position: Integer;
begin
    FirstParts := TStringList.Create;
    try
        SecondParts := TStringList.Create;
        try
            FirstSuffix := SplitVersion(Versions[FirstIndex], FirstParts);
            SecondSuffix := SplitVersion(Versions[SecondIndex], SecondParts);
            Count := FirstParts.Count;
            if SecondParts.Count > Count then
            begin
                Count := SecondParts.Count;
            end;
            for Index := 0 to Count - 1 do
            begin
                FirstNumber := '0';
                if Index < FirstParts.Count then
                begin
                    Position := 1;
                    FirstNumber := ReadVersionNumber(FirstParts[Index], Position);
                end;
                SecondNumber := '0';
                if Index < SecondParts.Count then
                begin
                    Position := 1;
                    SecondNumber := ReadVersionNumber(SecondParts[Index], Position);
                end;
                Result := CompareVersionNumbers(FirstNumber, SecondNumber);
                if Result <> 0 then
                begin
                    Exit;
                end;
            end;
            Result := CompareVersionSuffixes(FirstSuffix, SecondSuffix);
        finally
            SecondParts.Free;
        end;
    finally
        FirstParts.Free;
    end;
end;

// Applies ascending numeric version ordering to any collected .NET family.
procedure SortVersions(Versions: TStringList);
begin
    Versions.Sorted := False;
    Versions.CustomSort(CompareVersions);
end;

// Appends a nonempty runtime family and its comma-separated version list.
procedure AppendVersions(var Text: string; const Heading: string; Versions: TStrings);
var
    Index: Integer;
begin
    if Versions.Count = 0 then
    begin
        Exit;
    end;
    if Text <> '' then
    begin
        Text := Text + '; ';
    end;
    Text := Text + Heading + ' ';
    for Index := 0 to Versions.Count - 1 do
    begin
        if Index > 0 then
        begin
            Text := Text + ', ';
        end;
        Text := Text + Versions[Index];
    end;
end;

// Rebuilds the Framework and shared-runtime display text without loading runtimes.
function GetAvailableDotNetRuntimes: string;
var
    Framework: TStringList;
    Core: TStringList;
    Desktop: TStringList;
    AspNet: TStringList;
begin
    Framework := TStringList.Create;
    Core := TStringList.Create;
    Desktop := TStringList.Create;
    AspNet := TStringList.Create;
    try
        Core.Sorted := True;
        Core.Duplicates := dupIgnore;
        Desktop.Sorted := True;
        Desktop.Duplicates := dupIgnore;
        AspNet.Sorted := True;
        AspNet.Duplicates := dupIgnore;

        CollectFrameworkVersions(Framework);
        CollectModernVersions(Core, Desktop, AspNet);

        SortVersions(Framework);
        SortVersions(Core);
        SortVersions(Desktop);
        SortVersions(AspNet);

        Result := '';
        AppendVersions(Result, '.NET Framework', Framework);
        AppendVersions(Result, '.NET Runtime', Core);
        AppendVersions(Result, '.NET Desktop', Desktop);
        AppendVersions(Result, 'ASP.NET Core', AspNet);
        if Result = '' then
        begin
            Result := 'None detected';
        end;
    finally
        AspNet.Free;
        Desktop.Free;
        Core.Free;
        Framework.Free;
    end;
end;

end.
