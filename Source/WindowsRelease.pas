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

unit WindowsRelease;

interface

uses
    Windows, SysUtils, Classes;

type
    TWindowsFileVersion = record
        Available: Boolean;
        Major: DWORD;
        Minor: DWORD;
        Build: DWORD;
        Revision: DWORD;
    end;

procedure ReadWindowsBuildMetadata(out ProductName, BuildLab: string);
function WindowsDevelopmentName(Major, Minor, Build: DWORD; IsServer: Boolean;
        const Kernel: TWindowsFileVersion; const ProductName, BuildLab: string): string;

implementation

uses
    Registry;

const
    CurrentVersionKey = 'Software\Microsoft\Windows NT\CurrentVersion';
    VistaBeta1Build = 5112;
    VistaNameDate = '050722';

function ReadMetadataValue(Reg: TRegistry; const Name: string): string;
begin
    Result := '';
    if Reg.ValueExists(Name) then begin
        if Reg.GetDataType(Name) in [rdString, rdExpandString] then begin
            Result := Reg.ReadString(Name);
        end;
    end;
end;

procedure ReadWindowsBuildMetadata(out ProductName, BuildLab: string);
var
    Reg: TRegistry;
begin
    ProductName := '';
    BuildLab := '';
    Reg := TRegistry.Create(KEY_QUERY_VALUE);
    try
        Reg.RootKey := HKEY_LOCAL_MACHINE;
        try
            if Reg.OpenKeyReadOnly(CurrentVersionKey) then begin
                ProductName := ReadMetadataValue(Reg, 'ProductName');
                BuildLab := ReadMetadataValue(Reg, 'BuildLabEx');
                if BuildLab = '' then begin
                    BuildLab := ReadMetadataValue(Reg, 'BuildLab');
                end;
            end;
        except
            on E: Exception do begin
                OutputDebugString(PChar('OS Info could not read Windows build metadata: '
                    + E.ClassName + ': ' + E.Message));
            end;
        end;
    finally
        Reg.Free;
    end;
end;

function CompilationDate(const BuildLab: string): string;
var
    Tail: string;
    Index: Integer;
    Month: Integer;
    Day: Integer;
begin
    Result := '';
    Tail := Copy(BuildLab, LastDelimiter('.', BuildLab) + 1, MaxInt);
    if (Length(Tail) <> 11) or (Tail[7] <> '-') then begin
        Exit;
    end;
    for Index := 1 to 11 do begin
        if (Index <> 7) and not (Tail[Index] in ['0'..'9']) then begin
            Exit;
        end;
    end;
    Month := StrToInt(Copy(Tail, 3, 2));
    Day := StrToInt(Copy(Tail, 5, 2));
    if (Month >= 1) and (Month <= 12) and (Day >= 1) and (Day <= 31) then begin
        Result := Copy(Tail, 1, 6);
    end;
end;

function MatchesNt60Kernel(Build: DWORD; const Kernel: TWindowsFileVersion): Boolean;
begin
    Result := Kernel.Available and (Kernel.Major = 6) and (Kernel.Minor = 0) and (Kernel.Build = Build);
end;

function ReleasedVistaKernel(Build: DWORD; const Kernel: TWindowsFileVersion): Boolean;
var
    MinimumRevision: DWORD;
begin
    MinimumRevision := 0;
    case Build of
        6000: MinimumRevision := 16386;
        6001: MinimumRevision := 18000;
        6002: MinimumRevision := 18005;
    end;
    Result := MatchesNt60Kernel(Build, Kernel) and (MinimumRevision <> 0)
        and (Kernel.Revision >= MinimumRevision);
end;

function VistaClientName(Build: DWORD; const Kernel: TWindowsFileVersion;
        const ProductName, BuildLab: string): string;
var
    Date: string;
begin
    if ReleasedVistaKernel(Build, Kernel) then begin
        Result := 'Vista';
    end else if (Build > 0) and (Build < VistaBeta1Build) then begin
        Result := 'Longhorn';
    end else if Build = VistaBeta1Build then begin
        Result := 'Vista (pre-release)';
    end else if (Build > VistaBeta1Build) and (Build < 6000) then begin
        Date := CompilationDate(BuildLab);
        if (Date <> '') and (Date < VistaNameDate) then begin
            Result := 'Longhorn';
        end else if (Date >= VistaNameDate) or (Pos('VISTA', ProductName) <> 0) then begin
            Result := 'Vista (pre-release)';
        end else if Build = 5203 then begin
            Result := 'Longhorn';
        end else begin
            Result := 'NT 6.0 (unidentified pre-release)';
        end;
    end else if (Build >= 6000) and (Build <= 6002) then begin
        if MatchesNt60Kernel(Build, Kernel) then begin
            Result := 'Vista (pre-release)';
        end else begin
            Result := 'NT 6.0 (release unverified)';
        end;
    end else begin
        Result := 'NT 6.0 (unidentified build)';
    end;
end;

function LonghornServerName(Build: DWORD; const Kernel: TWindowsFileVersion;
        const ProductName: string): string;
begin
    Result := '';
    if ((Build = 6001) or (Build = 6002)) and ReleasedVistaKernel(Build, Kernel) then begin
        Exit;
    end;
    if Build > 6002 then begin
        Exit;
    end;
    if (Build >= 6001) and not MatchesNt60Kernel(Build, Kernel) then begin
        Result := 'Server 2008 (release unverified)';
    end else if Pos('2008', ProductName) <> 0 then begin
        Result := 'Server 2008 (pre-release)';
    end else begin
        Result := 'Server Longhorn';
    end;
end;

function WindowsDevelopmentName(Major, Minor, Build: DWORD; IsServer: Boolean;
        const Kernel: TWindowsFileVersion; const ProductName, BuildLab: string): string;
var
    Product: string;
begin
    Result := '';
    Product := UpperCase(ProductName);
    if ((Major = 5) or ((Major = 6) and (Minor = 0)))
            and (Pos('PREINSTALLATION ENVIRONMENT', Product) <> 0) then begin
        Result := 'PE';
    end else if (Major = 5) and (Pos('LONGHORN', Product) <> 0) then begin
        Result := 'Longhorn';
    end else if (Major = 5) and (Minor = 2) and (Build = 3790)
            and Kernel.Available and (Kernel.Major = 5) and (Kernel.Minor = 2)
            and (Kernel.Build = Build) and (Kernel.Revision = 1232) then begin
        Result := 'NT 5.2 (unidentified development build)';
    end else if (Major = 6) and (Minor = 0) then begin
        if IsServer then begin
            Result := LonghornServerName(Build, Kernel, Product);
        end else begin
            Result := VistaClientName(Build, Kernel, Product, BuildLab);
        end;
    end;
end;

end.
