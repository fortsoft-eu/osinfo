# OS Info

OS Info is a small, native Windows utility for viewing and copying operating-system and hardware details.
It also lists detected .NET runtimes and generates a descriptive name suitable for a VirtualBox machine.

This README is the application's user guide and project documentation. The application has no separate Help
window or About dialog.

## Quick start

1. Run `osinfo.exe` from the `Build` directory or from the location to which you copied it.
2. Read the information in the main window. You can select and copy text from every field.
3. Click **Refresh** or press **F5** to read all information again.
4. Click **Copy** to copy the complete displayed report to the clipboard.
5. Click **Close** or press **Esc** to exit.

The executable is a 32-bit Win32 application. It does not require Delphi, Delphi runtime packages, or .NET to
be installed on the computer on which it runs. VirtualBox is also optional: OS Info works on physical machines
and inside virtual machines. The embedded icon and manifest do not need to be distributed as separate files.

## Information shown

| Field | Meaning |
| --- | --- |
| Operating system version | Windows name, version, build, service pack, DLL version, and language code. |
| VirtualBox friendly name | A suggested machine name assembled from the local Windows information. |
| Processor model | The processor name or identifier reported by Windows, with a legacy-family fallback. |
| Processor architecture | The native Windows architecture, such as `x86 (32-bit)` or `x86-64 (64-bit)`. |
| Processors | Physical core count and logical processor count, when both can be determined. |
| Total RAM | Total physical memory visible to Windows, with currently available memory in parentheses. |
| Total system disk size | Capacity of the volume containing Windows, with free space in parentheses. |
| Available .NET runtimes | Detected .NET Framework and modern .NET shared-runtime versions. |

All fields are read-only but selectable. Their background follows the Windows button-face color. The window
has a fixed size, can be minimized, and has no maximize button. Windows chooses its initial screen position.

### Windows version and friendly name

The first field uses the longer Windows name and service-pack description. The version in parentheses is
read from the file-version resource of `kernel32.dll`; it can differ from the operating-system build number.
The final three-letter language code comes from the Windows system locale. Its original case is preserved in
the first field and converted to uppercase in the friendly name.

For example, the same Vista installation can be described as:

```text
Windows Vista 6.0.6002 Service Pack 2 (6.0.6002.18005) ENU
Windows Vista 6.0.6002 SP2 (6.0.6002.18005) ENU
```

The friendly name normally starts with `Windows`. Names starting with `Server` use `W Server` instead.
Windows Server 2003 includes `R2` when detected and the Standard, Enterprise, Datacenter, or Web designation.
The first field includes `Edition`; the friendly name omits it, for example `W Server 2003 R2 Standard`.

Longhorn identification uses the native version, full kernel DLL version, and the installed product/build
metadata. It covers the early Longhorn branch, the 5.2.3790.1232 reset when explicitly identified, the later
Longhorn previews, and parallel branches such as 5203. Vista Beta 1 and later beta/RC builds are marked
`Vista (pre-release)`. The plain `Vista` name requires a matching released kernel baseline: 6000.16386,
6001.18000, or 6002.18005, including later servicing revisions. Missing or ambiguous information is labeled
explicitly rather than presented as a confirmed retail Vista installation. Server Longhorn and Server 2008
pre-release builds are handled separately. A `longhorn_rtm` build-lab string does not make released Vista SP1
a Longhorn preview. Preinstallation-environment product names are not treated as desktop Vista.

The displayed OS name is identification, not an application-compatibility test. A development build can
report NT 6.0 while lacking APIs supplied by the released Windows Vista.

Windows 95 uses the familiar `4.00.950` release number, with the DLL version shown separately in parentheses.
Releases identified by Windows as `B` or `C` include `OEM` in the displayed name.

OS Info generates the friendly name locally. It does not read the current VirtualBox machine name, inspect
VirtualBox settings, or rename a machine. Copy the suggested name and apply it in VirtualBox yourself.

### Processor information

The **Processors** field counts cores rather than physical CPU sockets. For example, `4 (8 logical)` means
four physical cores and eight logical processors. When Windows cannot provide the core count through the
supported APIs, only the logical count is shown, for example `1 logical`; a core count is not guessed.

Core detection uses the extended processor-topology API when available and the older topology API on Vista
and later. Earlier systems use the logical-count display. Logical processors are counted across processor
groups when the corresponding Windows API is available.

Inside a virtual machine, processor details describe the processor information and topology exposed to the
guest operating system. They need not match the physical host's processor model or core count.

Architecture bitness describes the native Windows platform reported by `SYSTEM_INFO`.
All recognized platforms include it: x86, MIPS, Alpha, PowerPC and ARM use `(32-bit)`; IA-64,
x86-64 and ARM64 use `(64-bit)`. This is platform bitness, not necessarily the width of every CPU
register or the full instruction set supported by the physical processor. Unknown architectures
do not receive a guessed bitness. The shorter token in the VirtualBox-friendly name omits it.

### Memory and disk capacity

Both fields show the total followed by the available capacity, for example:

```text
Total RAM: 255.5 MiB (128.1 MiB free)
Total system disk size: 10.0 GiB (7.3 GiB free)
```

RAM means physical memory reported by Windows, not virtual memory or the page file. The available amount
includes memory Windows can currently make available to applications; it is a snapshot taken during refresh.

The disk field describes the volume containing the Windows directory. It does not add together all disks or
partitions and does not report the size of the entire physical drive. Its free value is total free space on
that volume, rather than a per-user disk-quota allowance.

Capacities use binary units: `B`, `KiB`, `MiB`, `GiB`, `TiB`, `PiB`, `EiB`, `ZiB`, `YiB`, `RiB`, and `QiB`.
Conversion divides by 1024. To avoid values near 1024 in the smaller unit, the formatter advances to the next
unit when the current value reaches 1000. For example, `1023.98 MiB` is displayed as `1.0 GiB`.

Bytes have no decimal places; larger units have one decimal place. Decimal numbers always use a period,
regardless of the Windows regional settings. Displayed values are rounded.

### .NET runtimes

The runtime field combines the following detected families, separated by semicolons:

- **.NET Framework:** setup-registry detection for 1.0, 1.1, 2.0, 3.0, 3.5, and the 4.x family through 4.8.1.
- **.NET Runtime:** versions found under `Microsoft.NETCore.App`.
- **.NET Desktop:** versions found under `Microsoft.WindowsDesktop.App`.
- **ASP.NET Core:** versions found under `Microsoft.AspNetCore.App`.

Framework service packs are included when their setup metadata is available, including .NET Framework 1.0
service packs. The Framework 4.x entry uses the installed release information; it does not list every earlier
4.x release separately. A detected 4.0 Client Profile is labeled `4.0 Client` when the Full entry is absent.

Modern shared runtimes are found in the `dotnet\shared` directories under the locations identified by
`ProgramFiles`, `ProgramW6432`, `ProgramFiles(x86)`, and `DOTNET_ROOT`. Duplicate versions within each runtime
family are combined. The display does not distinguish x86 and x64 installations.

Every family, including .NET Framework, is sorted in ascending order by the numeric components
separated by dots. Service-pack and preview numbers are compared numerically as well; a preview
precedes its matching stable release.

Detection reads registry entries and directory names without loading the runtimes. It does not validate an
installation, list SDKs, or search every application directory for private or self-contained runtimes.
`None detected` means nothing was found in the locations checked. Runtime presence alone is not a guarantee
that a particular .NET application will run.

## Controls and shortcuts

| Action | Control or shortcut |
| --- | --- |
| Refresh every field, including .NET runtimes | **Refresh**, **F5**, or **Alt+R** |
| Copy every label and displayed value | **Copy** or **Alt+C** |
| Select all text in the focused information field | **Ctrl+A** |
| Copy selected text from the focused information field | **Ctrl+C** |
| Move through fields and buttons | **Tab** / **Shift+Tab** |
| Activate the focused button or the default button | **Enter** |
| Close the application | **Close**, **Esc**, the title-bar close button, or **Alt+F4** |

Information is read when the window opens and when you request a refresh. There is no periodic information
refresh. Use **Refresh** after installing a runtime or when you need current free-memory or free-disk values.

**Copy** uses the values currently displayed; it does not refresh them first. The report contains all eight
label-and-value pairs, one per line, in this order: Windows version, friendly name, processor model,
architecture, processors, RAM, system disk, and .NET runtimes. Each pair uses `Label: value`, with Windows
line endings. Use **Ctrl+C** in an individual field to copy just the selected portion of that field.

Tab order follows the field order, then **Refresh**, **Copy**, and **Close**. **Close** is the default and
cancel button.

### Mouse selection

- A single click places the caret; dragging selects text normally.
- A double-click selects a word.
- A triple-click selects the entire line, which is the entire value in these single-line fields.
- Further rapid clicks alternate word and line selection: the fourth selects a word, the fifth a line, etc.
- Dragging after word or line selection extends the selection by words or lines.

Repeated clicks follow the Windows double-click timing and movement limits. The selection handler includes
legacy hit-testing support for Windows NT 3.x, where `EM_CHARFROMPOS` is unavailable.

## Windows compatibility and appearance

The project retains compatibility paths for Windows 95/98/Me and Windows NT 3.x onward. Windows-name mapping
covers NT 3.x/4.0, 2000, XP, Vista, 7, 8, 8.1, 10, and 11, plus implemented server names through Server 2025.
Server 2003 edition and R2 identification have dedicated handling. Other Windows product editions are not
listed individually. An unmapped Windows name falls back to its numeric version details.

On NT systems, OS Info uses `RtlGetVersion` when available to avoid the compatibility-dependent version
reported by `GetVersionEx`. Information available on old Windows is limited by that system's APIs. These
compatibility paths and name mappings are not a claim that every Windows release has been tested.

The build is an x86 executable. Other processor architectures require Windows support for running x86
applications; recognizing an architecture does not make the executable native to that architecture.

At startup, the form requests the Windows message/dialog font and reapplies it when Windows announces a
settings change. The embedded manifest requests Common Controls version 6 for themed controls where Windows
and the active theme support them. The appearance therefore follows the running system.

## Building with Delphi 7

Use Borland Delphi 7 and its standard VCL units. No third-party components or runtime packages are required.
The established build environment for this project is the Windows 2000 virtual machine with Delphi 7.

1. Make the complete project folder available in that environment.
2. Ensure a `Build` directory exists in the project root; create it if it is absent after a fresh checkout.
3. Open `osinfo.dpr` in Delphi 7 using **File > Open Project**.
4. Choose **Project > Build** to compile the project and its resources.
5. Run the resulting `Build\osinfo.exe`.

In the existing shared-folder setup, the project is opened as `Z:\dpr\OSInfo\osinfo.dpr`. Open it through the
mapped drive so that the resource compiler can resolve the project's relative paths consistently.

The output and compiled-unit directories are configured as `Build`. Keep the project filename `osinfo.dpr`
in lowercase so that a fresh build produces `osinfo.exe`. The application window title is `OS Info`; the
project name remains OSInfo. Version information is supplied by `Resources\osinfo.rc`.

### Icon and embedded resources

Replace `Resources\icon.ico` with the desired icon under the same filename, then build the project again.
The project associates `Resources\osinfo.rc` with its compiled `Resources\osinfo.res` resource, so the Delphi
IDE's build workflow compiles and embeds these resources. Selecting the icon again in Delphi is unnecessary.

The executable, main form, and taskbar use the embedded `MAINICON` resource. The icon is not loaded from an
external file or from a Windows system DLL when the application runs. Replacing the source icon changes
future builds; it does not change an executable that has already been built.

The resource script also embeds the application manifest and executable version information. Keep the
version in the resource script and manifest consistent when updating the application version.

### Release package

Run the packaging script on the host in Windows PowerShell 5.1 or newer, from the project directory:

```powershell
.\PackageRelease.ps1
```

The script reads the four-part version embedded in `Build\osinfo.exe` and creates
`OSInfo-<file-version>-win32.zip` in the project root, beside `PackageRelease.ps1`. It packages the existing
executable without compiling the project. The ZIP contains exactly two files at its root:

- `osinfo.exe`
- `license.txt`

Previous OSInfo release packages in the project root are removed at the start of each run. Compression uses
7-Zip when available, with .NET ZIP creation as the fallback.

Optional Authenticode signing uses the `-SignerName`, `-CertificateThumbprint`, `-SignToolPath`, and
`-TimestampServer` parameters. Their defaults come from the corresponding user environment variables:
`BUILD_SIGNER_NAME`, `BUILD_CERTIFICATE_THUMBPRINT`, `BUILD_SIGNTOOL_PATH`, and `BUILD_TIMESTAMP_SERVER`.
Signing operates on a temporary copy; the original executable in `Build` is preserved. An existing signature
is verified and preserved. When no signer is configured, unsigned executables remain unsigned.

### Project files

| Path | Purpose |
| --- | --- |
| `osinfo.dpr` | Program entry point, unit references, resource declaration, and application title. |
| `osinfo.dof` | Delphi 7 project options. |
| `osinfo.cfg` | Compiler options, including output directories. |
| `Source\MainForm.pas` | Main form, Windows identification, font, refresh, and clipboard report. |
| `Source\MainForm.dfm` | Form layout, control properties, anchors, and tab order. |
| `Source\HardwareInfo.pas` | CPU, RAM, system-volume queries, and the `ShowSize` formatter. |
| `Source\DotNetInfo.pas` | .NET Framework and shared-runtime detection. |
| `Source\SelectionEdit.pas` | Extended word/line selection, dragging, and Ctrl+A for edit controls. |
| `Resources\icon.ico` | Source icon embedded as `MAINICON`. |
| `Resources\osinfo.rc` | Resource Compiler script for the icon, manifest, and version information. |
| `Resources\osinfo.manifest` | XML application manifest requesting Common Controls version 6. |
| `Resources\osinfo.res` | Compiled resources used by the build. |
| `Build\osinfo.exe` | Built application. |
| `PackageRelease.ps1` | Creates the release ZIP from the executable and license. |
| `license.txt` | Complete MIT License included in the release package. |
| `OSInfo-<file-version>-win32.zip` | Generated release package in the project root. |
| `.gitignore` | Excludes build output and Delphi-generated working and backup files. |

Delphi creates `.~pas`, `.~dfm`, and similar backup files when backup-on-save is enabled. Files such as
`.dcu`, `.ddp`, `.dsk`, `.map`, and `.tds` are generated compiler or IDE files. The ignore rules exclude these
files, ZIP packages, and the `Build` directory from version control. Keep the `.pas`, `.dfm`, project options,
and source resources.

## Author and license

**Version:** 1.1.0.0  
**Author:** Petr Červinka — FortSoft  
**Contact:** <cervinka@fortsoft.eu>

Copyright (c) 2026 Petr Červinka - FortSoft.

OS Info is open-source software licensed under the MIT License. The complete license text is in `license.txt`
and the source-file headers. The software is provided "AS IS", without warranty, under that license.
