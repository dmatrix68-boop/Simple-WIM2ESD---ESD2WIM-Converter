# Simple WIM2ESD / ESD2WIM Converter

**Current Script Version :** 0.7.0-beta

This tool allows you to convert WIM Images to ESD Images and vice-versa.

If you want to compress WIM Images so they can fit on your favorite Bootable FAT32-formatted USB Stick, this tool is for you.
If you can't install with an ESD Image and want to go back to the good old WIM Image, this tool is also for you.

> **Note :** This is a maintained fork of the original
> [Studisys/Simple-WIM2ESD---ESD2WIM-Converter](https://github.com/Studisys/Simple-WIM2ESD---ESD2WIM-Converter)
> by Joel Didier (Studisys). The known bugs of the original 0.5.0-beta release
> (empty index names, paths with spaces not supported, broken start-over flow,
> broken elevation prompt) have been fixed — see the [Changelog](#changelog).

## DISM Version

The script now uses the **DISM that ships with your Windows installation**
(`C:\Windows\System32\dism.exe`) by default, so you always get the newest DISM
version available on your system — no separate download needed.

The `DISM` folder bundled in this repository (version 10.0.17120.1000, from 2018)
is **only used as a fallback** if no system DISM is found. On any normal
Windows 10 / 11 system you do not need it and can delete it.

## Compatibility

- Windows 10 and Windows 11 (system DISM is used directly).
- Older systems (e.g. Windows 7 / 8.1) may need a modern DISM — keep the bundled
  `DISM` folder next to the script for that case, or install a current
  [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install).
- ESD compression (`Recovery`) requires DISM 10 or newer.

## PowerShell edition (recommended)

Since 0.7.0-beta the tool is also available as a PowerShell script :
`Simple-WIM2ESD---ESD2WIM-Converter.ps1`. It offers the same interactive menus as
the batch version and can additionally be run **without menus** via parameters
(e.g. for automation). The batch script is still included and works as before.

Requirements : Windows PowerShell 5.1 (built into Windows 10 / 11) or PowerShell 7.

### Start the interactive wizard

- Right-click the script -> **Run with PowerShell**, or
- from a console :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Simple-WIM2ESD---ESD2WIM-Converter.ps1
```

If the script was downloaded from the internet, Windows may block it. Unblock it once with
`Unblock-File .\Simple-WIM2ESD---ESD2WIM-Converter.ps1`.
If the console is not elevated, the script re-launches itself with a UAC prompt.

### Non-interactive mode (parameters)

As soon as `-Mode` is given, no menus are shown. Run it from an **elevated**
PowerShell (no automatic UAC prompt in this mode). Exit code `0` = success, `1` = error.

| Parameter      | Values                                  | Default                                         |
|----------------|-----------------------------------------|-------------------------------------------------|
| `-Mode`        | `WimToEsd`, `EsdToWim`                  | — (interactive wizard if omitted)               |
| `-Source`      | path to the source image                | `install.wim` / `install.esd` next to the script |
| `-Destination` | path to the destination image           | `install.esd` / `install.wim` next to the script |
| `-Compression` | `None`, `Fast`, `Maximum`, `Recovery`   | `Recovery` (WimToEsd) / `Maximum` (EsdToWim)    |
| `-Index`       | an index number, or `All`               | `All`                                           |

Relative paths are resolved against the current directory.

```powershell
# Export index 6 of an install.wim to an ESD image
.\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode WimToEsd -Source D:\sources\install.wim -Destination C:\Temp\install.esd -Index 6

# Convert a complete ESD image back to WIM
.\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode EsdToWim -Source C:\Temp\install.esd -Destination C:\Temp\install.wim
```

Show the built-in help with `Get-Help .\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Full`.

### Differences to the batch version

- Optional parameters for non-interactive use (see above).
- Index list is read with a single DISM call and also shows the size of each index.
- Source and destination must not be the same file (the batch version would
  delete the source image in that case).
- A missing destination folder is created automatically.
- If reading the image fails, the DISM output is shown on the error screen.
- `Q` / `S` also work when entering the index number.

# How to Use (batch version)

1. Download the script `Simple-WIM2ESD---ESD2WIM-Converter.bat`.
   The `DISM` folder is optional — it is only needed on systems without a usable DISM.

2. Run the script `Simple-WIM2ESD---ESD2WIM-Converter.bat`.
   **Note :** If you didn't run the script as Administrator, you will be prompted
   for Administrator rights. They are required for DISM to work.

3. Follow the steps shown in the script :
   1. Select the type of conversion you want :
      - `1` for WIM to ESD
      - `2` for ESD to WIM
   2. Choose if you want to change the path to the source image :
      - `N` to keep the default path (`install.wim` / `install.esd` in the script's folder)
      - `Y` to enter the full path to the source image
        - Paths containing spaces are supported; surrounding quotes are removed automatically.
        - The script verifies that the source file exists before continuing.
   3. Choose if you want to change the path to the destination image (same rules as above).
   4. Choose if you want to change the type of Image Compression :
      - `1` -> None : No Compression (Fastest) [Destination Image bigger than Source Image]
      - `2` -> Fast : Low Compression (Fast) [Destination Image 'may' be bigger than Source Image]
      - `3` -> Maximum : Very High Compression (Slow) [Recommended maximum for WIM Images]
      - `4` -> Recovery : Insane Compression (Slowest) [ESD format — only use for ESD Images]
   5. Select an option :
      - `1` to export a single Index (then enter the Index number)
      - `2` to export all Indexes

4. Validate and let the fun begin.

At any menu you can press `Q` to exit or `S` to start over.

# Important Notes

## Administrator rights

- This script **requires** Administrator rights to run. If it was not started
  elevated, it re-launches itself with a UAC prompt.

## Existing destination file

- If the specified destination image already exists, it will be **deleted**
  before the export begins.

## Compression types and file formats

- `None`, `Fast` and `Maximum` produce standard WIM compression (Maximum = LZX).
- `Recovery` produces ESD (LZMS) compression. Only use it for `.esd` destination
  files — a `.wim` file with Recovery compression may not be readable by all tools.
- The presets already do the right thing : WIM -> ESD defaults to `Recovery`,
  ESD -> WIM defaults to `Maximum`.

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
