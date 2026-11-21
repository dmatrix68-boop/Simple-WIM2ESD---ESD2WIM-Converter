# Simple WIM2ESD / ESD2WIM Converter

**Current Version :** 1.1.0 (PowerShell)

This tool allows you to convert WIM Images to ESD Images and vice-versa.

If you want to compress WIM Images so they can fit on your favorite Bootable FAT32-formatted USB Stick, this tool is for you.
If you can't install with an ESD Image and want to go back to the good old WIM Image, this tool is also for you.

> **Note :** This is a maintained fork of the original
> [Studisys/Simple-WIM2ESD---ESD2WIM-Converter](https://github.com/Studisys/Simple-WIM2ESD---ESD2WIM-Converter)
> by Joel Didier (Studisys). See the [Changelog](CHANGELOG) for all changes.

> **The batch script `Simple-WIM2ESD---ESD2WIM-Converter.bat` is retired.**
> It is kept in the repository for reference only (last version 0.6.0-beta) and
> is no longer maintained. Please use the PowerShell script
> `Simple-WIM2ESD---ESD2WIM-Converter.ps1`.

## Features

- Interactive wizard with colored menus (WIM -> ESD or ESD -> WIM, source,
  destination, compression, editions) - `Q` exits and `S` starts over at any time.
- Export a single edition, several editions (`1,3-5`) or all editions.
- Confirmation screen before the start : sizes, codec, number of editions,
  free disk space and warnings (e.g. Recovery compression in a `.wim` file).
- **Live progress dashboard** while DISM is running :
  - name of the edition currently being converted (e.g. *Windows 11 Pro*)
  - progress bar for the current edition and an **overall progress bar**
    (weighted by the size of each edition)
  - remaining time of the current edition, elapsed time
  - bytes written so far, free space on the destination drive
  - **memory usage** of DISM (current and peak), CPU usage, system RAM usage
  - list of the editions already completed with duration and speed
  - progress also shown in the window title and (in Windows Terminal) in the
    tab / taskbar
- **Final statistics** :
  - size before / after, difference, size ratio
  - **codec** of source and destination (read from the WIM/ESD header :
    none / XPRESS / LZX / LZMS, chunk size, solid ESD format)
  - duration, write throughput, peak DISM memory, CPU time
  - per-edition table (size, duration, speed)
  - verification : the destination image is read back and its editions are compared
  - FAT32 hint (does the result fit on a FAT32 USB stick, i.e. below 4 GB?)
  - press `R` to save the statistics as a text report
- Non-interactive mode via parameters for automation, with exit codes.
- Uses the DISM of your Windows installation; the bundled `DISM` folder is only a fallback.
- **Optional : wimlib as export engine** - compresses with all CPU cores and can be
  considerably faster than DISM (see [Optional : wimlib](#optional--wimlib-faster-multi-threaded-compression)).

## Requirements

- Windows 10 / 11 with Windows PowerShell 5.1 (built in) or PowerShell 7.
- Administrator rights (the script asks via UAC if needed).
- Older systems (e.g. Windows 7 / 8.1) may need a modern DISM - keep the bundled
  `DISM` folder next to the script for that case, or install a current
  [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install).
  ESD compression (`Recovery`) requires DISM 10 or newer.

## Optional : wimlib (faster, multi-threaded compression)

[wimlib](https://wimlib.net/) is a free, open-source library and tool for WIM/ESD
images. Its `wimlib-imagex.exe` uses all CPU cores for compression and is often
much faster than DISM, especially for ESD (Recovery / LZMS). The images it creates
can be used by Windows Setup and DISM.

wimlib is **not** included in this repository - download it yourself :

1. Download the Windows binary package (e.g. `wimlib-1.14.x-windows-x86_64-bin.zip`)
   from the official site https://wimlib.net/.
2. Create a folder `wimlib` next to the script and extract **at least**
   `wimlib-imagex.exe` **and** `libwim-15.dll` into it :

   ```
   Simple-WIM2ESD---ESD2WIM-Converter.ps1
   DISM\            (optional fallback)
   wimlib\
      wimlib-imagex.exe
      libwim-15.dll
   ```

The script looks for wimlib in this order : `-WimlibPath` parameter,
`wimlib\wimlib-imagex.exe` next to the script, `wimlib-imagex.exe` next to the
script, then the `PATH`.

If wimlib is found, it is used for the export by default. On the confirmation
screen you can switch between wimlib and DISM with `E`; in non-interactive mode
use `-Engine Dism` or `-Engine Wimlib`. DISM is always used to read the image
information and to verify the result. The engine is shown in the dashboard and in
the statistics.

wimlib is licensed under the GNU GPLv3 / LGPLv3 (see its own documentation).

## DISM Version

The script uses the **DISM that ships with your Windows installation**
(`C:\Windows\System32\dism.exe`) by default, so you always get the newest DISM
version available on your system.

The `DISM` folder bundled in this repository (version 10.0.17120.1000, from 2018)
is **only used as a fallback** if no system DISM is found. On any normal
Windows 10 / 11 system you do not need it and can delete it.

# How to Use

## Interactive wizard

- Right-click the script -> **Run with PowerShell**, or
- from a console :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Simple-WIM2ESD---ESD2WIM-Converter.ps1
```

If the script was downloaded from the internet, Windows may block it. Unblock it once with
`Unblock-File .\Simple-WIM2ESD---ESD2WIM-Converter.ps1`.

Steps :

1. Conversion type : `1` WIM -> ESD, `2` ESD -> WIM
2. Source image : keep the default (`install.wim` / `install.esd` next to the script) or enter a path
3. Destination image : keep the default or enter a path
4. Compression (Enter keeps the preset) :
   - `1` None - no compression (fastest, biggest)
   - `2` Fast - XPRESS
   - `3` Maximum - LZX (recommended maximum for WIM images)
   - `4` Recovery - LZMS solid (slowest, smallest, only for ESD images)
5. Editions : `1` one or several (`6` or `1,3-5`), `2` all
6. Confirm with `Y` - the live dashboard starts (`E` switches between wimlib and DISM, if wimlib is available)
7. Statistics screen : `R` saves a report, `S` starts over, `Q` exits

Paths containing spaces are supported; surrounding quotes are removed automatically.

## Non-interactive mode (parameters)

As soon as `-Mode` is given, no menus are shown. Run it from an **elevated**
PowerShell (no automatic UAC prompt in this mode). Exit code `0` = success, `1` = error.
In a console the live dashboard is shown as well; with redirected output, progress
is written as a line every 10 %.

| Parameter      | Values                                  | Default                                          |
|----------------|-----------------------------------------|--------------------------------------------------|
| `-Mode`        | `WimToEsd`, `EsdToWim`                  | - (interactive wizard if omitted)                |
| `-Source`      | path to the source image                | `install.wim` / `install.esd` next to the script |
| `-Destination` | path to the destination image           | `install.esd` / `install.wim` next to the script |
| `-Compression` | `None`, `Fast`, `Maximum`, `Recovery`   | `Recovery` (WimToEsd) / `Maximum` (EsdToWim)     |
| `-Index`       | `All`, a number (`6`) or a list (`1,3-5`) | `All`                                          |
| `-ReportPath`  | path of a text file for the statistics  | - (no report file)                               |
| `-Engine`      | `Auto`, `Dism`, `Wimlib`                | `Auto` (wimlib if found, otherwise DISM)         |
| `-WimlibPath`  | path to `wimlib-imagex.exe` or its folder | search next to the script, then `PATH`         |

Relative paths are resolved against the current directory.

```powershell
# Export index 6 of an install.wim to an ESD image
.\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode WimToEsd -Source D:\sources\install.wim -Destination C:\Temp\install.esd -Index 6

# Convert editions 1, 3, 4 and 5 of an ESD image back to WIM and save the statistics
.\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode EsdToWim -Source C:\Temp\install.esd -Destination C:\Temp\install.wim -Index 1,3-5 -ReportPath C:\Temp\report.txt

# Force DISM even if wimlib is available
.\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode WimToEsd -Source D:\sources\install.wim -Destination C:\Temp\install.esd -Engine Dism
```

Show the built-in help with `Get-Help .\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Full`.

# Important Notes

## Administrator rights

- DISM **requires** Administrator rights. In the interactive wizard the script
  re-launches itself with a UAC prompt if needed.

## Existing destination file

- If the specified destination image already exists, it will be **deleted**
  before the export begins. Source and destination must not be the same file.
- If DISM fails or the conversion is cancelled (Ctrl+C), the destination image
  is incomplete and must not be used.

## Compression types and file formats

- `None`, `Fast` (XPRESS) and `Maximum` (LZX) produce standard WIM images.
- `Recovery` produces ESD (LZMS solid) compression. Only use it for `.esd` destination
  files - a `.wim` file with Recovery compression may not be readable by all tools.
- The presets already do the right thing : WIM -> ESD defaults to `Recovery`,
  ESD -> WIM defaults to `Maximum`.

## Progress values

- The percentages are taken from the progress output of DISM. The remaining time
  of the current edition is an estimate based on its progress so far.
- There is deliberately no overall remaining time / ETA : the editions of an image
  share most of their files, so the first edition takes much longer than the
  following ones (e.g. 11 minutes for the first, under 1 minute for each further
  edition). An overall estimate would therefore be far off.
- The overall progress bar is weighted by the uncompressed size of each edition
  and is only a rough indicator for the same reason.

## Legacy batch script (retired)

`Simple-WIM2ESD---ESD2WIM-Converter.bat` (0.6.0-beta) is retired. It still works
the same way as before (menus `1`/`2`, `Y`/`N`, `Q`/`S`), but receives no further
updates or fixes.

# More about this project

## Origin

This tool was created by Joel Didier (Studisys) as part of a much bigger project
to help manage and customize Windows Installation Images and files. The original
motivation : ISOs provided by Microsoft were too big to boot properly over USB on
UEFI systems (`install.wim` > 4GB), so a quick way of compressing `install.wim`
images was needed.

This fork fixes the bugs of the last upstream release and modernizes the script.

## Fixed in this fork (0.6.0-beta)

- The script now uses the DISM installed with the OS by default (always up to
  date); the bundled DISM folder is only a fallback.
- Fixed empty index names in the index list (FOR variable collision).
- Fixed paths containing spaces (quoting of DISM path, source, and destination;
  quotes pasted by the user are stripped automatically).
- Fixed the broken `GOTO IndexExport` jump to a non-existent label that crashed
  the script.
- Fixed the broken Administrator elevation prompt (invalid `SET params` syntax).
- Fixed the start-over flow (`S`) which previously re-ran parts of the script twice.
- Fixed error detection : DISM exit codes are now actually checked, including
  inside the "export all indexes" loop.
- Fixed index parsing on non-English systems (DISM is now called with `/English`).
- The ESD -> WIM preset now uses `Maximum` compression instead of `Recovery`
  (which produced ESD-compressed data inside a `.wim` file).
- Added input validation for the index number and a file-existence check for the
  source image.

## Versioning

- 3-digit version [Major].[Beta].[Alpha]
- [Major] : number of the stable version
- [Beta] : number of the Beta version (number of bugs greatly reduced compared to the Alpha version)
- [Alpha] : number of the Alpha version (highest number of bugs, features not properly working)

## Changelog

A changelog can be found [here](CHANGELOG).

## License [<img src="https://img.shields.io/badge/license-AGPL 3.0-blue.svg">](LICENSE)

This project is licensed under the AGPL 3.0 License.
The license file can be viewed [here](LICENSE).

## Credits and contact

- Original author : Joel Didier (Studisys)
  - Twitter : https://twitter.com/Studisys
  - Email : studisys@protonmail.com
  - Original repository : https://github.com/Studisys/Simple-WIM2ESD---ESD2WIM-Converter
- This fork : https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter
