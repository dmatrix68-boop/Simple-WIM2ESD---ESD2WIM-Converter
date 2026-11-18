<#
.SYNOPSIS
    Simple WIM2ESD / ESD2WIM Converter (PowerShell edition).

.DESCRIPTION
    Converts WIM images to ESD images and vice-versa using DISM.

    Without parameters the script runs the interactive wizard (same flow as the
    original batch script). When -Mode is given it runs non-interactively, which
    is useful for automation. Non-interactive mode must be started from an
    elevated (Administrator) PowerShell.

    The DISM shipped with Windows (%SystemRoot%\System32\dism.exe) is used by
    default. The bundled DISM folder next to this script is only a fallback.

.PARAMETER Mode
    WimToEsd or EsdToWim. Enables non-interactive mode.

.PARAMETER Source
    Path to the source image. Default: install.wim / install.esd next to the script.

.PARAMETER Destination
    Path to the destination image. Default: install.esd / install.wim next to the script.
    An existing destination file is deleted before the export starts.

.PARAMETER Compression
    None, Fast, Maximum or Recovery. Default: Recovery (WimToEsd) / Maximum (EsdToWim).

.PARAMETER Index
    Index number to export, or 'All' (default) to export every index.

.EXAMPLE
    .\Simple-WIM2ESD---ESD2WIM-Converter.ps1
    Starts the interactive wizard.

.EXAMPLE
    .\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode WimToEsd -Source D:\sources\install.wim -Destination C:\Temp\install.esd -Index 6
    Exports index 6 of install.wim to an ESD image (Recovery compression).

.NOTES
    Version         : 0.7.0-beta
    Original author : Joel Didier (Studisys)
    Fork            : https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter
    License         : AGPL 3.0
#>
[CmdletBinding()]
param(
    [ValidateSet('WimToEsd', 'EsdToWim')]
    [string]$Mode,

    [string]$Source,

    [string]$Destination,

    [ValidateSet('None', 'Fast', 'Maximum', 'Recovery')]
    [string]$Compression,

    [ValidatePattern('^(All|[1-9][0-9]*)$')]
    [string]$Index = 'All'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:Version    = '0.7.0-beta'
$Script:AppName    = 'Simple WIM2ESD / ESD2WIM Converter'
$Script:BaseTitle  = "$Script:AppName - By Joel Didier (Studisys)"
$Script:RepoUrl    = 'https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter/'
$Script:ScriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:Interactive = -not $PSBoundParameters.ContainsKey('Mode')

# Thrown by the menus when the user presses 'S' (start over) or 'Q' (quit).
class StartOverSignal : System.Exception { }
class QuitSignal : System.Exception { }

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function Resolve-FullPath {
    param([string]$Path, [string]$BasePath)
    $Path = $Path.Trim().Trim('"').Trim()
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $BasePath $Path
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Find-Dism {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\dism.exe'),
        (Join-Path $Script:ScriptDir 'DISM\dism.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Dism {
    <#
        Runs DISM with an exact command line (paths are quoted like in the
        batch version). With -Capture the output is returned instead of being
        shown, otherwise DISM writes directly to the console (progress bar).
    #>
    param([string]$Arguments, [switch]$Capture)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $Script:DismExe
    $psi.Arguments       = $Arguments
    $psi.UseShellExecute = $false
    if ($Capture) {
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.StandardOutputEncoding = [Console]::OutputEncoding
        $psi.StandardErrorEncoding  = [Console]::OutputEncoding
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $output = ''
    if ($Capture) {
        $errTask = $proc.StandardError.ReadToEndAsync()
        $output  = $proc.StandardOutput.ReadToEnd()
        $output += $errTask.Result
    }
    $proc.WaitForExit()

    [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Output   = $output
    }
}

function Get-ImageIndexes {
    param([string]$ImagePath)

    $result = Invoke-Dism -Arguments "/English /Get-WimInfo /WimFile:`"$ImagePath`"" -Capture
    if ($result.ExitCode -ne 0) {
        throw "DISM could not read the image (exit code $($result.ExitCode)).`n$($result.Output)"
    }

    $indexes = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ($line -match '^Index\s*:\s*(\d+)\s*$') {
            $current = [pscustomobject]@{ Index = [int]$Matches[1]; Name = ''; Size = '' }
            $indexes.Add($current)
        }
        elseif ($current -and $line -match '^Name\s*:\s*(.*)$') {
            $current.Name = $Matches[1].Trim()
        }
        elseif ($current -and $line -match '^Size\s*:\s*(.*)$') {
            $current.Size = $Matches[1].Trim()
        }
    }

    if ($indexes.Count -eq 0) {
        throw "No index found in the image.`n$($result.Output)"
    }
    return $indexes.ToArray()
}

function Export-ImageIndex {
    param([int]$SourceIndex)

    $arguments = "/Export-Image /SourceImageFile:`"$($Script:Cfg.Source)`" /SourceIndex:$SourceIndex " +
                 "/DestinationImageFile:`"$($Script:Cfg.Destination)`" /Compress:$($Script:Cfg.Compression) /CheckIntegrity"
    $result = Invoke-Dism -Arguments $arguments
    if ($result.ExitCode -ne 0) {
        throw "DISM failed while exporting index $SourceIndex (exit code $($result.ExitCode))."
    }
}

function Remove-Destination {
    $dst = $Script:Cfg.Destination
    if (Test-Path -LiteralPath $dst) {
        Remove-Item -LiteralPath $dst -Force
    }
    $dir = Split-Path -Parent $dst
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Assert-ValidPaths {
    if (-not (Test-Path -LiteralPath $Script:Cfg.Source -PathType Leaf)) {
        throw "The source image `"$($Script:Cfg.Source)`" does not exist."
    }
    if ([string]::Equals($Script:Cfg.Source, $Script:Cfg.Destination, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source and destination image must not be the same file.'
    }
}

function Get-Preset {
    param([string]$ConversionMode)
    if ($ConversionMode -eq 'WimToEsd') {
        return @{ SrcType = 'WIM'; DstType = 'ESD'; Source = 'install.wim'; Destination = 'install.esd'; Compression = 'Recovery' }
    }
    return @{ SrcType = 'ESD'; DstType = 'WIM'; Source = 'install.esd'; Destination = 'install.wim'; Compression = 'Maximum' }
}

# -----------------------------------------------------------------------------
# Console UI
# -----------------------------------------------------------------------------

function Set-Title {
    param([string]$Text)
    try { $Host.UI.RawUI.WindowTitle = $Text } catch { }
}

function Write-Banner {
    param([string[]]$Lines)
    $width = 64
    $indent = ' ' * 27
    $rule = $indent + ('=' * $width)
    Clear-Host
    Write-Host ''
    Write-Host $rule
    foreach ($l in @($Script:AppName) + $Lines) {
        $pad = [Math]::Max(0, [int](($width - $l.Length) / 2))
        Write-Host ($indent + (' ' * $pad) + $l)
    }
    Write-Host $rule
    Write-Host ''
}

function Write-Footer {
    param([string]$Text = "Press 'Q' to exit, 'S' to start over")
    $width = 64
    $indent = ' ' * 27
    $rule = $indent + ('=' * $width)
    $pad = [Math]::Max(0, [int](($width - $Text.Length) / 2))
    Write-Host ''
    Write-Host $rule
    Write-Host ($indent + (' ' * $pad) + $Text)
    Write-Host $rule
    Write-Host ''
}

function Read-Key {
    <#
        Equivalent of CHOICE: waits for one of the allowed keys and returns it
        in upper case. 'Q' and 'S' are handled globally (quit / start over).
    #>
    param([string]$Allowed, [string]$Prompt = '  Your choice :  ')

    $Allowed = ($Allowed + 'QS').ToUpperInvariant()
    Write-Host -NoNewline $Prompt
    while ($true) {
        $key = $null
        try {
            $char = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
            if ($char -ne [char]0) { $key = ([string]$char).ToUpperInvariant() }
        }
        catch {
            # Hosts without ReadKey support (e.g. PowerShell ISE)
            $answer = Read-Host
            if (-not [string]::IsNullOrWhiteSpace($answer)) { $key = $answer.Trim().Substring(0, 1).ToUpperInvariant() }
        }
        if ($key -and $key.Length -eq 1 -and $Allowed.Contains($key)) {
            Write-Host $key
            switch ($key) {
                'Q' { throw [QuitSignal]::new() }
                'S' { throw [StartOverSignal]::new() }
            }
            return $key
        }
    }
}

function Wait-AnyKey {
    Write-Host ''
    Write-Host -NoNewline '  Press any key to continue . . . '
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { $null = Read-Host }
    Write-Host ''
}

function Read-PathInput {
    param([string]$Header, [string]$What)
    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", $Header)
    Write-Host "  Please enter the path to the $What image."
    Write-Host '  Paths containing spaces are supported, quotes are removed automatically.'
    Write-Host ''
    $answer = Read-Host '  Path '
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
    return Resolve-FullPath -Path $answer -BasePath $Script:ScriptDir
}

function Show-Home {
    Set-Title $Script:BaseTitle
    Write-Banner @('Welcome')
    Write-Host "  Welcome to the $Script:AppName (version $Script:Version, PowerShell edition)"
    Write-Host ''
    Write-Host '  This tool allows to quickly convert a WIM Image to an ESD Image, and vice-versa.'
    Write-Host ''
    Write-Host "  Using DISM : $Script:DismExe"
    Write-Host ''
    Write-Host '  Please read the full documentation on :'
    Write-Host "  $Script:RepoUrl"
    Wait-AnyKey
}

function Select-ConversionType {
    Write-Banner @('Program Parameters', 'Conversion Type')
    Write-Host '  What type of conversion do you want ?'
    Write-Host ''
    Write-Host '  [1] WIM --> ESD'
    Write-Host '  [2] ESD --> WIM'
    Write-Footer
    $mode = if ((Read-Key '12') -eq '1') { 'WimToEsd' } else { 'EsdToWim' }
    $Script:Cfg = Get-Preset $mode
    $Script:Cfg.Source      = Resolve-FullPath $Script:Cfg.Source $Script:ScriptDir
    $Script:Cfg.Destination = Resolve-FullPath $Script:Cfg.Destination $Script:ScriptDir
}

function Select-SourcePath {
    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", 'Path to Source Image')
    Write-Host "  Current Path to the source Image is : $($Script:Cfg.Source)"
    Write-Host '  Do you wish to change it ?'
    Write-Host ''
    Write-Host '  [Y] Yes'
    Write-Host '  [N] No'
    Write-Footer
    $change = (Read-Key 'YN') -eq 'Y'

    while ($true) {
        if ($change) {
            $p = Read-PathInput -Header 'Path to Source Image' -What 'source'
            if ($p) { $Script:Cfg.Source = $p }
        }
        if (Test-Path -LiteralPath $Script:Cfg.Source -PathType Leaf) { return }
        Write-Host ''
        Write-Host "  The source image `"$($Script:Cfg.Source)`" does not exist. Please enter a valid path."
        Wait-AnyKey
        $change = $true
    }
}

function Select-DestinationPath {
    while ($true) {
        Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", 'Path to Destination Image')
        Write-Host "  Current Path to the destination Image is : $($Script:Cfg.Destination)"
        Write-Host '  Do you wish to change it ?'
        Write-Host ''
        Write-Host '  [Y] Yes'
        Write-Host '  [N] No'
        Write-Footer
        if ((Read-Key 'YN') -eq 'Y') {
            $p = Read-PathInput -Header 'Path to Destination Image' -What 'destination'
            if ($p) { $Script:Cfg.Destination = $p }
        }
        if (-not [string]::Equals($Script:Cfg.Source, $Script:Cfg.Destination, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        Write-Host ''
        Write-Host '  Source and destination image must not be the same file. Please choose another destination.'
        Wait-AnyKey
    }
}

function Select-Compression {
    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", 'Compress Type')
    Write-Host "  Current Compression Type is : $($Script:Cfg.Compression)"
    Write-Host '  Do you wish to change it ?'
    Write-Host ''
    Write-Host '  [Y] Yes'
    Write-Host '  [N] No'
    Write-Footer
    if ((Read-Key 'YN') -ne 'Y') { return }

    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", 'Compress Type')
    Write-Host '  Please enter the compression type.'
    Write-Host ''
    Write-Host '  Available Compression Types :'
    Write-Host ''
    Write-Host "  [1] None :  No Compression (Fastest) [Destination Image bigger than Source Image]"
    Write-Host ''
    Write-Host "  [2] Fast :  Low Compression (Fast) [Destination Image 'may' be bigger than Source Image]"
    Write-Host ''
    Write-Host '  [3] Maximum :  Very High Compression (Slow) [Recommended maximum for WIM Images]'
    Write-Host ''
    Write-Host '  [4] Recovery :  Insane Compression (Slowest) [ESD format - only use for ESD Images]'
    Write-Footer
    $Script:Cfg.Compression = switch (Read-Key '1234') {
        '1' { 'None' }
        '2' { 'Fast' }
        '3' { 'Maximum' }
        '4' { 'Recovery' }
    }
}

function Write-IndexList {
    param([object[]]$Indexes)
    foreach ($i in $Indexes) {
        $size = if ($i.Size) { "  ($($i.Size))" } else { '' }
        Write-Host "  [$($i.Index)] $($i.Name)$size"
    }
}

function Write-ExportNotice {
    Write-Host '     PLEASE NOTE :'
    Write-Host '     This operation may take a few minutes to complete depending on your PC Hardware.'
    Write-Host '     This operation will use a lot of CPU and Memory resources.'
    Write-Host '     Your system may be hotter or may seem unresponsive while processing your request.'
    Write-Host '     Please do not interfere with the process before it has ended.'
    Write-Host ''
}

function Invoke-Export {
    param([int[]]$IndexNumbers, [int]$Total)

    $conv = "$($Script:Cfg.SrcType)2$($Script:Cfg.DstType)"
    Remove-Destination
    $n = 0
    foreach ($idx in $IndexNumbers) {
        $n++
        if ($IndexNumbers.Count -eq 1) {
            Set-Title "$Script:AppName - $conv - Exporting Index $idx . . ."
            $lines = @('Export Single Index', "Exporting Index $idx . . .")
        }
        else {
            Set-Title "$Script:AppName - $conv - Exporting Index $n / $Total . . ."
            $lines = @('Exporting All Indexes', "Exporting Index $n of $Total . . .")
        }
        if ($Script:Interactive) {
            Write-Banner (@("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)") + $lines)
            Write-ExportNotice
        }
        else {
            Write-Host "[$n/$($IndexNumbers.Count)] Exporting index $idx -> $($Script:Cfg.Destination) (Compress: $($Script:Cfg.Compression))"
        }
        Export-ImageIndex -SourceIndex $idx
    }
}

function Select-AndExport {
    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", "Analyzing $($Script:Cfg.SrcType) . . .")
    $indexes = @(Get-ImageIndexes -ImagePath $Script:Cfg.Source)

    Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)")
    Write-Host "         The $($Script:Cfg.SrcType) Image contains the following $($indexes.Count) indexes :"
    Write-Host ''
    Write-IndexList $indexes
    Write-Host ''
    Write-Host '         What do you want to do ?'
    Write-Host ''
    Write-Host '  [1] Export a single Index'
    Write-Host '  [2] Export all Indexes'
    Write-Footer

    if ((Read-Key '12') -eq '2') {
        Invoke-Export -IndexNumbers ($indexes | ForEach-Object { $_.Index }) -Total $indexes.Count
        return
    }

    $valid = @($indexes | ForEach-Object { $_.Index })
    while ($true) {
        Write-Banner @("$($Script:Cfg.SrcType) --> $($Script:Cfg.DstType)", 'Export Single Index')
        Write-Host '     Please enter the Index number you want to export.'
        Write-Host ''
        Write-Host '     Here are the Indexes :'
        Write-Host ''
        Write-IndexList $indexes
        Write-Footer
        $answer = (Read-Host '     Your choice ').Trim()
        switch ($answer.ToUpperInvariant()) {
            'Q' { throw [QuitSignal]::new() }
            'S' { throw [StartOverSignal]::new() }
        }
        $num = 0
        if ([int]::TryParse($answer, [ref]$num) -and $valid -contains $num) {
            Invoke-Export -IndexNumbers @($num) -Total $indexes.Count
            return
        }
    }
}

function Show-Result {
    param([bool]$Success, [string]$Message)

    Set-Title $Script:BaseTitle
    if ($Success) {
        Write-Banner @('Success')
        Write-Host '  Successfully performed requested tasks.'
        Write-Host ''
        Write-Host '  Thanks for using my script.'
        Write-Host "  GitHub Page : $Script:RepoUrl"
        Write-Host "  Version : $Script:Version"
        Write-Host '  Original Author : Joel Didier (Studisys)'
    }
    else {
        # No Clear-Host here, so the DISM output above stays visible.
        Write-Host ''
        Write-Host ('=' * 64)
        Write-Host "  $Script:AppName - Error"
        Write-Host ('=' * 64)
        Write-Host ''
        Write-Host '  Something wrong occured . . .'
        Write-Host ''
        if ($Message) {
            foreach ($l in ($Message -split "`r?`n")) { Write-Host "  $l" }
            Write-Host ''
        }
        Write-Host '  Please check the error given by DISM above and the log located in :'
        Write-Host "  $env:SystemRoot\Logs\DISM\dism.log"
        Write-Host ''
        Write-Host '  If the problem persists, please open an issue on :'
        Write-Host "  $($Script:RepoUrl)issues"
    }
    Write-Footer
    $null = Read-Key '' -Prompt ''
}

# -----------------------------------------------------------------------------
# Modes
# -----------------------------------------------------------------------------

function Start-Interactive {
    $rawUI = $Host.UI.RawUI
    $oldColors = $null
    $oldTitle = $null
    try {
        $oldTitle = $rawUI.WindowTitle
        $oldColors = @($rawUI.BackgroundColor, $rawUI.ForegroundColor)
        $rawUI.BackgroundColor = 'DarkBlue'
        $rawUI.ForegroundColor = 'White'
    }
    catch { }

    try {
        while ($true) {
            # 'S' = start over, 'Q' = quit (both raised by Read-Key)
            $action = $null
            $errorMessage = $null
            try {
                Show-Home
                Select-ConversionType
                Select-SourcePath
                Select-DestinationPath
                Select-Compression
                Select-AndExport
                Show-Result -Success $true
            }
            catch [StartOverSignal] { $action = 'S' }
            catch [QuitSignal]      { $action = 'Q' }
            catch                   { $errorMessage = $_.Exception.Message }

            if ($null -ne $errorMessage) {
                try { Show-Result -Success $false -Message $errorMessage }
                catch [StartOverSignal] { $action = 'S' }
                catch [QuitSignal]      { $action = 'Q' }
            }
            if ($action -eq 'Q') { break }
        }
    }
    finally {
        if ($oldColors) {
            try {
                $rawUI.BackgroundColor = $oldColors[0]
                $rawUI.ForegroundColor = $oldColors[1]
            }
            catch { }
        }
        if ($oldTitle) { Set-Title $oldTitle }
        Clear-Host
    }
}

function Start-NonInteractive {
    $preset = Get-Preset $Mode
    $Script:Cfg = $preset
    $Script:Cfg.Source      = if ($Source)      { $Source }      else { Resolve-FullPath $preset.Source $Script:ScriptDir }
    $Script:Cfg.Destination = if ($Destination) { $Destination } else { Resolve-FullPath $preset.Destination $Script:ScriptDir }
    if ($Compression) { $Script:Cfg.Compression = $Compression }

    Write-Host "$Script:AppName $Script:Version"
    Write-Host "DISM        : $Script:DismExe"
    Write-Host "Conversion  : $($Script:Cfg.SrcType) -> $($Script:Cfg.DstType)"
    Write-Host "Source      : $($Script:Cfg.Source)"
    Write-Host "Destination : $($Script:Cfg.Destination)"
    Write-Host "Compression : $($Script:Cfg.Compression)"

    Assert-ValidPaths
    $indexes = @(Get-ImageIndexes -ImagePath $Script:Cfg.Source)
    Write-Host 'Indexes     :'
    Write-IndexList $indexes

    if ($Index -eq 'All') {
        $selected = @($indexes | ForEach-Object { $_.Index })
    }
    else {
        $num = [int]$Index
        if (-not (@($indexes | ForEach-Object { $_.Index }) -contains $num)) {
            throw "Index $num does not exist in the image (valid: 1-$($indexes.Count))."
        }
        $selected = @($num)
    }

    Invoke-Export -IndexNumbers $selected -Total $indexes.Count
    Write-Host ''
    Write-Host 'Successfully performed requested tasks.'
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

# Resolve parameter paths now, relative to the caller's current directory.
if ($Source)      { $Source      = Resolve-FullPath $Source      (Get-Location).Path }
if ($Destination) { $Destination = Resolve-FullPath $Destination (Get-Location).Path }

$Script:DismExe = Find-Dism
if (-not $Script:DismExe) {
    $msg = "No usable DISM executable was found.`n" +
           "Looked for : $env:SystemRoot\System32\dism.exe`n" +
           "Fallback   : $(Join-Path $Script:ScriptDir 'DISM\dism.exe')"
    if ($Script:Interactive) {
        Write-Banner @('DISM not found')
        foreach ($l in ($msg -split "`n")) { Write-Host "  $l" }
        Wait-AnyKey
    }
    else {
        Write-Error $msg -ErrorAction Continue
    }
    exit 1
}

if (-not (Test-IsAdmin)) {
    if (-not $Script:Interactive) {
        Write-Error 'Administrator rights are required. Please run this script from an elevated PowerShell.' -ErrorAction Continue
        exit 1
    }
    Write-Banner @('Administrator Rights Required')
    Write-Host '  You did not execute the script as Administrator.'
    Write-Host '  Administrator rights are required.'
    Write-Host '  You will now be prompted for Administrator rights.'
    Write-Host '  If you do not grant Administrator rights, this script will not run.'
    Wait-AnyKey

    # Re-launch with the same PowerShell edition (works from ISE as well).
    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs | Out-Null
    }
    catch {
        Write-Host ''
        Write-Host '  Administrator rights were not granted. The script will now exit.'
        Wait-AnyKey
        exit 1
    }
    exit 0
}

if ($Script:Interactive) {
    Start-Interactive
    exit 0
}

try {
    Start-NonInteractive
    exit 0
}
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    Write-Host "See also: $env:SystemRoot\Logs\DISM\dism.log"
    exit 1
}
