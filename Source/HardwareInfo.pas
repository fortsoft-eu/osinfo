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

// Reads hardware details and formats memory and disk capacities with ShowSize.
unit HardwareInfo;

interface

// Reports the native architecture, falling back to GetSystemInfo on older Windows.
function GetProcessorArchitecture: string;

// Reads the CPU name from the registry, with identifier and processor-family fallbacks.
function GetProcessorModel: string;

// Shows physical cores with the logical count, or only the known logical count on unsupported systems.
function GetProcessorInformation: string;

// Preserves the C# ShowSize scaling, threshold and fixed-digit rules through QB and QiB.
// C# Double formatting rounds to 15 significant digits before the fixed decimal conversion.
function ShowSize(Length: Double; UseDecimalPrefix: Boolean = False): string;

// Reads total and currently available physical RAM using the API supported by the running Windows.
function GetMemoryInformation: string;

// Reads total and free space on the volume containing Windows, including support for the legacy API.
function GetSystemDiskInformation: string;

implementation

uses
    Windows, SysUtils, Registry;

// System query selectors for all processor groups and physical-core relationships.
const
    AllProcessorGroups = $FFFF;
    ProcessorCoreRelationship = 0;

type
    // Matches the 32-bit fixed-size legacy processor-topology record.
    TLogicalProcessorInformation = record
        ProcessorMask: DWORD;
        Relationship: DWORD;
        Reserved: array[0..1] of Int64;
    end;

    // Addresses one fixed-size legacy processor-topology record.
    PLogicalProcessorInformation = ^TLogicalProcessorInformation;

    // Reads the relationship and size of a variable-length topology record.
    TProcessorInformationHeader = record
        Relationship: DWORD;
        Size: DWORD;
    end;

    // Addresses the common header of an extended processor-topology record.
    PProcessorInformationHeader = ^TProcessorInformationHeader;

    // Optional legacy query for processor relationships.
    TGetLogicalProcessorInformation = function(Buffer: Pointer; var Length: DWORD): BOOL; stdcall;

    // Optional group-aware topology query for counting active physical cores.
    TGetLogicalProcessorInformationEx = function(Relationship: DWORD;
        Buffer: Pointer; var Length: DWORD): BOOL; stdcall;

    // Optional count of active logical processors across processor groups.
    TGetActiveProcessorCount = function(GroupNumber: Word): DWORD; stdcall;

    // Optional 64-bit disk query, kept dynamic for old Windows compatibility.
    TGetDiskFreeSpaceEx = function(DirectoryName: PChar;
        var AvailableBytes, TotalBytes, FreeBytes: Int64): BOOL; stdcall;

    // Optional native-architecture query for 32-bit processes on 64-bit Windows.
    TGetNativeSystemInfo = procedure(var SystemInfo: TSystemInfo); stdcall;

    // Matches MEMORYSTATUSEX and retains its 64-bit memory counters.
    TMemoryStatus64 = record
        dwLength: DWORD;
        dwMemoryLoad: DWORD;
        ullTotalPhys: Int64;
        ullAvailPhys: Int64;
        ullTotalPageFile: Int64;
        ullAvailPageFile: Int64;
        ullTotalVirtual: Int64;
        ullAvailVirtual: Int64;
        ullAvailExtendedVirtual: Int64;
    end;

    // Optional extended memory query, kept dynamic for legacy Windows support.
    TGlobalMemoryStatusEx = function(var Status: TMemoryStatus64): BOOL; stdcall;

// Reports the native architecture, falling back to GetSystemInfo on older Windows.
function GetProcessorArchitecture: string;
var
    SystemInfo: TSystemInfo;
    NativeSystemInfo: TGetNativeSystemInfo;
begin
    NativeSystemInfo := TGetNativeSystemInfo(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GetNativeSystemInfo'));
    if Assigned(NativeSystemInfo) then
    begin
        NativeSystemInfo(SystemInfo);
    end
    else
    begin
        GetSystemInfo(SystemInfo);
    end;

    case Word(SystemInfo.dwOemId) of
        0: Result := 'x86 (32-bit)';
        1: Result := 'MIPS';
        2: Result := 'Alpha';
        3: Result := 'PowerPC';
        5: Result := 'ARM';
        6: Result := 'IA-64';
        9: Result := 'x64 (64-bit)';
        12: Result := 'ARM64';
    else
        Result := 'Unknown architecture';
    end;
end;

// Reads the CPU name from the registry, with identifier and processor-family fallbacks.
function GetProcessorModel: string;
var
    ProcessorRegistry: TRegistry;
    SystemInfo: TSystemInfo;
begin
    Result := '';
    ProcessorRegistry := TRegistry.Create(KEY_READ);
    try
        ProcessorRegistry.RootKey := HKEY_LOCAL_MACHINE;
        if ProcessorRegistry.OpenKey('HARDWARE\DESCRIPTION\System\CentralProcessor\0', False) then
        begin
            if ProcessorRegistry.ValueExists('ProcessorNameString') then
            begin
                Result := Trim(ProcessorRegistry.ReadString('ProcessorNameString'));
            end;
            if (Result = '') and ProcessorRegistry.ValueExists('Identifier') then
            begin
                Result := Trim(ProcessorRegistry.ReadString('Identifier'));
            end;
        end;
    finally
        ProcessorRegistry.Free;
    end;

    if Result = '' then
    begin
        GetSystemInfo(SystemInfo);
        case SystemInfo.dwProcessorType of
            386: Result := 'Intel 80386';
            486: Result := 'Intel 80486';
            586: Result := 'Intel Pentium';
        else
            Result := 'Processor family ' + IntToStr(SystemInfo.wProcessorLevel);
        end;
    end;
end;

// Counts logical processors across all processor groups when the group-aware API is available.
function GetLogicalProcessorCount: string;
var
    SystemInfo: TSystemInfo;
    ProcessorCount: DWORD;
    ActiveProcessorCount: TGetActiveProcessorCount;
begin
    ProcessorCount := 0;
    ActiveProcessorCount := TGetActiveProcessorCount(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GetActiveProcessorCount'));
    if Assigned(ActiveProcessorCount) then
    begin
        ProcessorCount := ActiveProcessorCount(AllProcessorGroups);
    end;
    if ProcessorCount = 0 then
    begin
        GetSystemInfo(SystemInfo);
        ProcessorCount := SystemInfo.dwNumberOfProcessors;
    end;
    Result := IntToStr(ProcessorCount);
end;

// Counts active cores. Before Vista the legacy API reports packages instead of cores, so it is skipped.
function GetPhysicalCoreCount: DWORD;
var
    InformationEx: TGetLogicalProcessorInformationEx;
    Information: TGetLogicalProcessorInformation;
    Buffer: Pointer;
    Header: PProcessorInformationHeader;
    ProcessorInformation: PLogicalProcessorInformation;
    BufferSize: DWORD;
    Offset: DWORD;
    QuerySucceeded: BOOL;
begin
    Result := 0;
    InformationEx := TGetLogicalProcessorInformationEx(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GetLogicalProcessorInformationEx'));
    Information := TGetLogicalProcessorInformation(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GetLogicalProcessorInformation'));
    if not Assigned(InformationEx) then
    begin
        if (Win32MajorVersion < 6) or not Assigned(Information) then
        begin
            Exit;
        end;
    end;

    BufferSize := 0;
    if Assigned(InformationEx) then
    begin
        QuerySucceeded := InformationEx(ProcessorCoreRelationship, nil, BufferSize);
    end
    else
    begin
        QuerySucceeded := Information(nil, BufferSize);
    end;
    if QuerySucceeded or (GetLastError <> ERROR_INSUFFICIENT_BUFFER) or (BufferSize = 0) then
    begin
        Exit;
    end;

    GetMem(Buffer, BufferSize);
    try
        if Assigned(InformationEx) then
        begin
            QuerySucceeded := InformationEx(ProcessorCoreRelationship, Buffer, BufferSize);
        end
        else
        begin
            QuerySucceeded := Information(Buffer, BufferSize);
        end;
        if not QuerySucceeded then
        begin
            Exit;
        end;

        Offset := 0;
        if Assigned(InformationEx) then
        begin
            while Offset + SizeOf(TProcessorInformationHeader) <= BufferSize do
            begin
                Header := PProcessorInformationHeader(PChar(Buffer) + Offset);
                if (Header.Size < SizeOf(TProcessorInformationHeader))
                        or (Header.Size > BufferSize - Offset) then
                begin
                    Result := 0;
                    Exit;
                end;
                if Header.Relationship = ProcessorCoreRelationship then
                begin
                    Inc(Result);
                end;
                Inc(Offset, Header.Size);
            end;
        end
        else
        begin
            while Offset + SizeOf(TLogicalProcessorInformation) <= BufferSize do
            begin
                ProcessorInformation := PLogicalProcessorInformation(PChar(Buffer) + Offset);
                if ProcessorInformation.Relationship = ProcessorCoreRelationship then
                begin
                    Inc(Result);
                end;
                Inc(Offset, SizeOf(TLogicalProcessorInformation));
            end;
        end;
    finally
        FreeMem(Buffer);
    end;
end;

// Shows physical cores with the logical count, or only the known logical count on unsupported systems.
function GetProcessorInformation: string;
var
    LogicalCount: string;
    PhysicalCount: DWORD;
begin
    LogicalCount := GetLogicalProcessorCount;
    PhysicalCount := GetPhysicalCoreCount;
    if PhysicalCount <> 0 then
    begin
        Result := IntToStr(PhysicalCount) + ' (' + LogicalCount + ' logical)';
    end
    else
    begin
        Result := LogicalCount + ' logical';
    end;
end;

// Preserves the C# ShowSize scaling, threshold and fixed-digit rules through QB and QiB.
// C# Double formatting rounds to 15 significant digits before the fixed decimal conversion.
function ShowSize(Length: Double; UseDecimalPrefix: Boolean): string;
const
    IecUnits: array[0..10] of string = (
        'B',
        'KiB',
        'MiB',
        'GiB',
        'TiB',
        'PiB',
        'EiB',
        'ZiB',
        'YiB',
        'RiB',
        'QiB'
    );
    SiUnits: array[0..10] of string = (
        'B',
        'kB',
        'MB',
        'GB',
        'TB',
        'PB',
        'EB',
        'ZB',
        'YB',
        'RB',
        'QB'
    );
var
    Number: Double;
    Divisor: Double;
    UnitIndex: Integer;
begin
    Number := Length;
    UnitIndex := 0;
    if UseDecimalPrefix then
    begin
        Divisor := 1000;
    end
    else
    begin
        Divisor := 1024;
    end;
    while (Number >= 1000) and (UnitIndex < High(IecUnits)) do
    begin
        Number := Number / Divisor;
        Inc(UnitIndex);
    end;
    Number := StrToFloat(FloatToStrF(Number, ffGeneral, 15, 0));
    if UnitIndex = 0 then
    begin
        Result := FloatToStrF(Number, ffFixed, 15, 0);
    end
    else
    begin
        Result := FloatToStrF(Number, ffFixed, 15, 1);
    end;
    Result := StringReplace(Result, DecimalSeparator, '.', [rfReplaceAll]);
    if UseDecimalPrefix then
    begin
        Result := Result + ' ' + SiUnits[UnitIndex];
    end
    else
    begin
        Result := Result + ' ' + IecUnits[UnitIndex];
    end;
end;

// Reads total and currently available physical RAM using the API supported by the running Windows.
function GetMemoryInformation: string;
var
    MemoryStatus: TMemoryStatus;
    MemoryStatus64: TMemoryStatus64;
    MemoryStatusEx: TGlobalMemoryStatusEx;
    TotalBytes: Int64;
    AvailableBytes: Int64;
begin
    TotalBytes := 0;
    AvailableBytes := 0;
    MemoryStatusEx := TGlobalMemoryStatusEx(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GlobalMemoryStatusEx'));
    if Assigned(MemoryStatusEx) then
    begin
        FillChar(MemoryStatus64, SizeOf(MemoryStatus64), 0);
        MemoryStatus64.dwLength := SizeOf(MemoryStatus64);
        if MemoryStatusEx(MemoryStatus64) then
        begin
            TotalBytes := MemoryStatus64.ullTotalPhys;
            AvailableBytes := MemoryStatus64.ullAvailPhys;
        end;
    end;
    if TotalBytes = 0 then
    begin
        FillChar(MemoryStatus, SizeOf(MemoryStatus), 0);
        MemoryStatus.dwLength := SizeOf(MemoryStatus);
        GlobalMemoryStatus(MemoryStatus);
        TotalBytes := MemoryStatus.dwTotalPhys;
        AvailableBytes := MemoryStatus.dwAvailPhys;
    end;
    Result := ShowSize(TotalBytes) + ' (' + ShowSize(AvailableBytes) + ' free)';
end;

// Reads total and free space on the volume containing Windows, including support for the legacy API.
function GetSystemDiskInformation: string;
var
    WindowsDirectory: array[0..MAX_PATH] of Char;
    RootPath: string;
    DirectoryLength: UINT;
    SectorsPerCluster: DWORD;
    BytesPerSector: DWORD;
    FreeClusters: DWORD;
    TotalClusters: DWORD;
    AvailableBytes: Int64;
    TotalBytes: Int64;
    FreeBytes: Int64;
    DiskFreeSpaceEx: TGetDiskFreeSpaceEx;
    DiskQuerySucceeded: BOOL;
begin
    Result := 'Unknown';
    DirectoryLength := GetWindowsDirectory(WindowsDirectory, SizeOf(WindowsDirectory));
    if (DirectoryLength = 0) or (DirectoryLength >= SizeOf(WindowsDirectory)) then
    begin
        Exit;
    end;
    RootPath := IncludeTrailingPathDelimiter(ExtractFileDrive(WindowsDirectory));
    DiskFreeSpaceEx := TGetDiskFreeSpaceEx(GetProcAddress(GetModuleHandle('kernel32.dll'),
        'GetDiskFreeSpaceExA'));
    if Assigned(DiskFreeSpaceEx) then
    begin
        if not DiskFreeSpaceEx(PChar(RootPath), AvailableBytes, TotalBytes, FreeBytes) then
        begin
            Exit;
        end;
    end
    else
    begin
        DiskQuerySucceeded := GetDiskFreeSpace(PChar(RootPath), SectorsPerCluster,
            BytesPerSector, FreeClusters, TotalClusters);
        if not DiskQuerySucceeded then
        begin
            Exit;
        end;
        TotalBytes := Int64(SectorsPerCluster) * BytesPerSector * TotalClusters;
        FreeBytes := Int64(SectorsPerCluster) * BytesPerSector * FreeClusters;
    end;
    Result := ShowSize(TotalBytes) + ' (' + ShowSize(FreeBytes) + ' free)';
end;

end.
