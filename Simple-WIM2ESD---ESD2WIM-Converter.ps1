<#
.SYNOPSIS
    Simple WIM2ESD / ESD2WIM Converter.

.DESCRIPTION
    Converts WIM images to ESD images and vice-versa using DISM, with a live
    progress dashboard (current edition, per-edition and overall progress,
    remaining time, ETA, throughput, memory/CPU usage) and a final statistics
    report (sizes before/after, codec, compression ratio, duration, ...).

    Without parameters the script runs the interactive wizard. When -Mode is
    given it runs non-interactively, which is useful for automation.
    Non-interactive mode must be started from an elevated (Administrator)
    PowerShell.

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
    Editions to export: 'All' (default), a single index (6), or a list/range (1,3-5).

.PARAMETER ReportPath
    Optional: write the final statistics report to this text file.

.EXAMPLE
    .\Simple-WIM2ESD---ESD2WIM-Converter.ps1
    Starts the interactive wizard.

.EXAMPLE
    .\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode WimToEsd -Source D:\sources\install.wim -Destination C:\Temp\install.esd -Index 6
    Exports index 6 of install.wim to an ESD image (Recovery compression).

.EXAMPLE
    .\Simple-WIM2ESD---ESD2WIM-Converter.ps1 -Mode EsdToWim -Source C:\Temp\install.esd -Destination C:\Temp\install.wim -Index 1,3-5 -ReportPath C:\Temp\report.txt
    Exports editions 1, 3, 4 and 5 to a WIM image and saves the statistics report.

.NOTES
    Version         : 1.0.0
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

    [ValidatePattern('^\s*(all|\d+(\s*-\s*\d+)?(\s*,\s*\d+(\s*-\s*\d+)?)*)\s*$')]
    [string[]]$Index = @('All'),

    [string]$ReportPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:Version     = '1.0.0'
$Script:AppName     = 'Simple WIM2ESD / ESD2WIM Converter'
$Script:BaseTitle   = "$Script:AppName $Script:Version"
$Script:RepoUrl     = 'https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter/'
$Script:ScriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:Interactive = -not $PSBoundParameters.ContainsKey('Mode')
$Script:Run         = $null
$Script:DashTop     = -1
$Script:DashLines   = 16

# Codec that DISM uses for each /Compress value
$Script:CodecOf = @{
    None     = 'none (stored)'
    Fast     = 'XPRESS'
    Maximum  = 'LZX'
    Recovery = 'LZMS solid (ESD)'
}

# Thrown by the menus when the user presses 'S' (start over) or 'Q' (quit).
class StartOverSignal : System.Exception { }
class QuitSignal : System.Exception { }

# =============================================================================
# Console UI basics
# =============================================================================

function Initialize-Ui {
    $redirected = $true
    try { $redirected = [Console]::IsOutputRedirected } catch { }

    # Live dashboard needs a real console (not ISE, not redirected output)
    $Script:CanDraw = $false
    if ($Host.Name -eq 'ConsoleHost' -and -not $redirected) {
        try { $null = [Console]::CursorTop; $Script:CanDraw = $true } catch { }
    }

    if (-not $redirected) {
        $Script:G = @{
            TL = [string][char]0x2554; TR = [string][char]0x2557
            BL = [string][char]0x255A; BR = [string][char]0x255D
            H  = [string][char]0x2550; V  = [string][char]0x2551
            ML = [string][char]0x2560; MR = [string][char]0x2563
            Rule = [string][char]0x2500
            Full = [string][char]0x2588; Empty = [string][char]0x2591
            Arrow = [string][char]0x2192; Dot = [string][char]0x00B7
        }
    }
    else {
        $Script:G = @{
            TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '='; V = '|'; ML = '+'; MR = '+'
            Rule = '-'; Full = '#'; Empty = '.'; Arrow = '->'; Dot = '-'
        }
    }

    $width = 80
    try { $width = $Host.UI.RawUI.WindowSize.Width } catch { }
    if (-not $width -or $width -lt 40) { $width = 80 }
    $Script:W = [Math]::Min(76, $width - 4)
    $Script:Margin = ' ' * [Math]::Max(1, [int][Math]::Floor(($width - $Script:W) / 2))
}

function Set-Title {
    param([string]$Text)
    try { $Host.UI.RawUI.WindowTitle = $Text } catch { }
}

function Set-TaskbarProgress {
    # Windows Terminal: progress in tab and taskbar (0 = off, 1 = normal, 2 = error)
    param([int]$State, [int]$Percent = 0)
    if ($env:WT_SESSION -and $Script:CanDraw) {
        try { [Console]::Write("$([char]27)]9;4;$State;$Percent$([char]7)") } catch { }
    }
}

function Out-Row {
    <#
        Writes one line: Out-Row 'text' Color 'text' Color ...
        The line is indented by the margin, cut to the content width and padded
        with spaces (so it fully overwrites older content on the dashboard).
    #>
    $max  = $Script:W
    $used = 0
    Write-Host -NoNewline $Script:Margin
    for ($i = 0; $i -lt $args.Count; $i += 2) {
        $text  = [string]$args[$i]
        $color = if ($i + 1 -lt $args.Count -and $args[$i + 1]) { [string]$args[$i + 1] } else { 'White' }
        if ($used + $text.Length -gt $max) { $text = $text.Substring(0, [Math]::Max(0, $max - $used)) }
        if ($text.Length -gt 0) { Write-Host -NoNewline $text -ForegroundColor $color }
        $used += $text.Length
    }
    Write-Host (' ' * [Math]::Max(0, $max - $used))
}

function Write-Header {
    param([string[]]$Lines, [string]$Accent = 'Yellow')
    $g = $Script:G
    $inner = $Script:W - 2
    if ($Script:Interactive) { Clear-Host }
    Write-Host ''
    Out-Row ($g.TL + ($g.H * $inner) + $g.TR) Cyan
    $left  = '  ' + $Script:AppName
    $right = "v$Script:Version  "
    Out-Row $g.V Cyan $left White (' ' * [Math]::Max(1, $inner - $left.Length - $right.Length)) White $right Gray $g.V Cyan
    if ($Lines) {
        Out-Row ($g.ML + ($g.H * $inner) + $g.MR) Cyan
        foreach ($l in $Lines) {
            $t = Get-ShortText ('  ' + $l) $inner
            Out-Row $g.V Cyan $t $Accent (' ' * ($inner - $t.Length)) White $g.V Cyan
        }
    }
    Out-Row ($g.BL + ($g.H * $inner) + $g.BR) Cyan
    Write-Host ''
}

function Write-Footer {
    param([string]$ExtraKey, [string]$ExtraText)
    Write-Host ''
    Out-Row ($Script:G.Rule * $Script:W) DarkCyan
    if ($ExtraKey) {
        Out-Row '  ' White "[$ExtraKey]" Yellow " $ExtraText     " Gray '[Q]' Yellow ' Exit     ' Gray '[S]' Yellow ' Start over' Gray
    }
    else {
        Out-Row '  ' White '[Q]' Yellow ' Exit     ' Gray '[S]' Yellow ' Start over' Gray
    }
    Write-Host ''
}

function Write-Text {
    param([string]$Text = '', [string]$Color = 'White')
    Out-Row '  ' White $Text $Color
}

function Write-Wrapped {
    # Writes long text word-wrapped to the content width
    param([string]$Text, [string]$Color = 'White')
    $max = $Script:W - 4
    foreach ($para in ($Text -split "`r?`n")) {
        $line = ''
        foreach ($word in ($para -split ' ')) {
            if ($line.Length -gt 0 -and ($line.Length + 1 + $word.Length) -gt $max) {
                Write-Text $line $Color
                $line = ''
            }
            $line = if ($line.Length -gt 0) { "$line $word" } else { $word }
        }
        Write-Text $line $Color
    }
}

function Write-Field {
    param([string]$Label, [string]$Value, [string]$Color = 'White', [string]$Note = '', [string]$NoteColor = 'Gray')
    $sep = if ($Label) { ': ' } else { '  ' }
    Out-Row '  ' White $Label.PadRight(16) Gray $sep Gray $Value $Color $Note $NoteColor
}

function Write-Option {
    param([string]$Key, [string]$Text, [string]$Hint = '', [string]$HintColor = 'Gray')
    Out-Row '   [' Gray $Key Yellow ']  ' Gray $Text White $Hint $HintColor
}

function Get-ShortText {
    param([string]$Text, [int]$Max)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, [Math]::Max(0, $Max - 3)) + '...'
}

function Get-ShortPath {
    param([string]$Path, [int]$Max = 56)
    if ($null -eq $Path) { return '' }
    if ($Path.Length -le $Max) { return $Path }
    return '...' + $Path.Substring($Path.Length - ($Max - 3))
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -lt 0) { return '-' }
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt 4) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return ('{0:N0} B' -f $Bytes) }
    return ('{0:N2} {1}' -f $Bytes, $units[$i])
}

function Format-Duration {
    param([TimeSpan]$Span)
    if ($Span.TotalSeconds -lt 0) { $Span = [TimeSpan]::Zero }
    return ('{0:00}:{1:00}:{2:00}' -f [Math]::Floor($Span.TotalHours), $Span.Minutes, $Span.Seconds)
}

function New-Bar {
    param([double]$Percent, [int]$Width = 30)
    $p = [Math]::Max(0, [Math]::Min(100, $Percent))
    $full = [int][Math]::Round($p / 100 * $Width)
    return ($Script:G.Full * $full) + ($Script:G.Empty * ($Width - $full))
}

function Read-Key {
    <#
        Equivalent of CHOICE: waits for one of the allowed keys and returns it
        in upper case. 'Q' and 'S' are handled globally (quit / start over).
    #>
    param([string]$Allowed, [string]$Prompt = 'Your choice : ')

    $Allowed = ($Allowed + 'QS').ToUpperInvariant()
    Write-Host -NoNewline ($Script:Margin + '  ' + $Prompt) -ForegroundColor Yellow
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
            Write-Host $key -ForegroundColor White
            switch ($key) {
                'Q' { throw [QuitSignal]::new() }
                'S' { throw [StartOverSignal]::new() }
            }
            return $key
        }
    }
}

function Read-Line {
    param([string]$Prompt)
    Write-Host -NoNewline ($Script:Margin + '  ' + $Prompt) -ForegroundColor Yellow
    $answer = Read-Host
    if ($null -eq $answer) { return '' }
    return $answer.Trim()
}

function Wait-AnyKey {
    Write-Host ''
    Write-Host -NoNewline ($Script:Margin + '  Press any key to continue . . . ') -ForegroundColor Gray
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { $null = Read-Host }
    Write-Host ''
}

# =============================================================================
# System / file helpers
# =============================================================================

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

function Get-FileLength {
    param([string]$Path)
    try {
        $fi = New-Object System.IO.FileInfo($Path)
        if ($fi.Exists) { return [long]$fi.Length }
    }
    catch { }
    return [long]0
}

function Get-FreeSpace {
    param([string]$Path)
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        $drive = New-Object System.IO.DriveInfo($root)
        return [pscustomobject]@{ Root = $root; Free = [long]$drive.AvailableFreeSpace; Format = $drive.DriveFormat }
    }
    catch { return $null }
}

function Get-SystemMemory {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize
        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $free  = [double]$os.FreePhysicalMemory * 1KB
        return [pscustomobject]@{ Used = $total - $free; Total = $total }
    }
    catch { return $null }
}

function Get-DismTreeUsage {
    # Working set and CPU time of dism.exe plus its child processes (DismHost.exe)
    param([System.Diagnostics.Process]$Process)
    $mem = [long]0
    $cpu = 0.0
    try {
        $Process.Refresh()
        $mem += $Process.WorkingSet64
        $cpu += $Process.TotalProcessorTime.TotalSeconds
    }
    catch { }
    try {
        $children = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($Process.Id)" -Property WorkingSetSize, KernelModeTime, UserModeTime)
        foreach ($c in $children) {
            $mem += [long]$c.WorkingSetSize
            $cpu += ([double]$c.KernelModeTime + [double]$c.UserModeTime) / 1e7
        }
    }
    catch { }
    return [pscustomobject]@{ Memory = $mem; CpuSeconds = $cpu }
}

function Get-WimHeaderInfo {
    <#
        Reads the WIM/ESD file header to report the real codec of an image:
        compression flags, chunk size, solid (ESD) format and image count.
    #>
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $buf = New-Object byte[] 48
            $n = $fs.Read($buf, 0, 48)
        }
        finally { $fs.Dispose() }
        if ($n -lt 48 -or [System.Text.Encoding]::ASCII.GetString($buf, 0, 5) -ne 'MSWIM') { return $null }

        $version = [BitConverter]::ToUInt32($buf, 12)
        $flags   = [BitConverter]::ToUInt32($buf, 16)
        $chunk   = [BitConverter]::ToUInt32($buf, 20)
        $count   = [BitConverter]::ToUInt32($buf, 44)

        $codec = 'none'
        if ($flags -band 0x2) {
            if     ($flags -band 0x80000)  { $codec = 'LZMS' }
            elseif ($flags -band 0x40000)  { $codec = 'LZX' }
            elseif ($flags -band 0x220000) { $codec = 'XPRESS' }
            else                           { $codec = 'unknown' }
        }
        $solid = ($version -eq 0xE00)
        $text = $codec
        if ($solid) { $text += ' solid (ESD format)' }
        elseif ($codec -ne 'none' -and $chunk -gt 0) { $text += ", $([int]($chunk / 1KB)) KB chunks" }

        return [pscustomobject]@{ Codec = $codec; ChunkSize = $chunk; Solid = $solid; ImageCount = $count; Text = $text }
    }
    catch { return $null }
}

function Get-ErrorHint {
    param([int]$ExitCode)
    switch ('0x{0:X8}' -f $ExitCode) {
        '0x80070070' { return 'Not enough free disk space on the destination drive.' }
        '0x80070005' { return 'Access denied - is the file read-only or opened by another program?' }
        '0x80070020' { return 'The file is in use by another process.' }
        '0x8007000D' { return 'The image file is corrupt or not a valid WIM/ESD file.' }
        '0xC1420113' { return 'The image is mounted or in use. Run "dism /Cleanup-Wim" and try again.' }
        '0x00000057' { return 'Invalid parameter - check the index and the compression type.' }
        '0x800704C7' { return 'The operation was cancelled.' }
    }
    return $null
}

function Get-DismMessages {
    # Text output of DISM without banner and progress bar fragments
    param([string]$Text, [int]$Last = 12)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($raw in ($Text -split "`n")) {
        foreach ($seg in ($raw -split "`r")) {
            $s = $seg.Trim()
            if (-not $s) { continue }
            if ($s -match '^\[[=\s\d.,%]*\]?$') { continue }
            if ($s -match '^(Deployment Image Servicing and Management tool|Version:)') { continue }
            $result.Add($s)
        }
    }
    if ($result.Count -gt $Last) { return $result.GetRange($result.Count - $Last, $Last).ToArray() }
    return $result.ToArray()
}

# =============================================================================
# DISM
# =============================================================================

function Invoke-DismCapture {
    param([string]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Script:DismExe
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [Console]::OutputEncoding
    $psi.StandardErrorEncoding  = [Console]::OutputEncoding

    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $output  = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $output += $errTask.Result

    return [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $output }
}

function Get-ImageIndexes {
    param([string]$ImagePath)

    $result = Invoke-DismCapture -Arguments "/English /Get-WimInfo /WimFile:`"$ImagePath`""
    if ($result.ExitCode -ne 0) {
        $msg = "DISM could not read the image (exit code $('0x{0:X8}' -f $result.ExitCode))."
        $hint = Get-ErrorHint $result.ExitCode
        if ($hint) { $msg += "`n$hint" }
        throw ($msg + "`n" + ((Get-DismMessages $result.Output) -join "`n"))
    }

    $indexes = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in ($result.Output -split "`r?`n")) {
        if ($line -match '^Index\s*:\s*(\d+)\s*$') {
            $current = [pscustomobject]@{ Index = [int]$Matches[1]; Name = ''; Bytes = [long]0 }
            $indexes.Add($current)
        }
        elseif ($current -and $line -match '^Name\s*:\s*(.*)$') {
            $current.Name = $Matches[1].Trim()
        }
        elseif ($current -and $line -match '^Size\s*:\s*(.*)$') {
            $digits = $Matches[1] -replace '[^\d]', ''
            if ($digits) { $current.Bytes = [long]$digits }
        }
    }

    if ($indexes.Count -eq 0) {
        throw "No index found in the image.`n$($result.Output)"
    }
    return $indexes.ToArray()
}

function ConvertTo-IndexSelection {
    # Parses 'All', '6' or '1,3-5' into the matching index objects
    param([string]$Text, [object[]]$Indexes)

    $Text = $Text.Trim()
    if ($Text -match '^(?i)all$') { return $Indexes }

    $numbers = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($Text -split ',')) {
        $p = $part.Trim()
        if ($p -match '^(\d+)\s*-\s*(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ([Math]::Abs($b - $a) -gt 1000) { throw "Range '$p' is too large." }
            foreach ($n in ($a..$b)) { if (-not $numbers.Contains($n)) { $numbers.Add($n) } }
        }
        elseif ($p -match '^\d+$') {
            if (-not $numbers.Contains([int]$p)) { $numbers.Add([int]$p) }
        }
        else {
            throw "Invalid index selection '$p'."
        }
    }

    $selected = foreach ($n in $numbers) {
        $item = $Indexes | Where-Object { $_.Index -eq $n } | Select-Object -First 1
        if (-not $item) { throw "Index $n does not exist in the image (valid: $($Indexes[0].Index)-$($Indexes[-1].Index))." }
        $item
    }
    return @($selected)
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

function Get-ConversionLabel {
    return "$($Script:Cfg.SrcType) $($Script:G.Arrow) $($Script:Cfg.DstType)"
}

# =============================================================================
# Live progress dashboard
# =============================================================================

function Start-Dashboard {
    param([object]$Item)
    $r = $Script:Run
    $conv = Get-ConversionLabel
    if ($Script:CanDraw) {
        if ($Script:Interactive) {
            Write-Header @("$conv  $($Script:G.Dot)  Converting edition $($r.Position) of $($r.Count)", $Item.Name)
        }
        else {
            Write-Host ''
        }
        Write-Text 'High CPU and memory load is normal. Please do not interrupt the process.' Gray
        Write-Host ''
        for ($i = 0; $i -lt $Script:DashLines; $i++) { Write-Host '' }
        $Script:DashTop = [Console]::CursorTop - $Script:DashLines
        try { [Console]::CursorVisible = $false } catch { }
    }
    else {
        Write-Host ("[{0}/{1}] Exporting index {2} - {3}" -f $r.Position, $r.Count, $Item.Index, $Item.Name)
    }
}

function Update-Dashboard {
    param([object]$Item, [hashtable]$M)

    $r   = $Script:Run
    $g   = $Script:G
    $pct = $M.Pct

    # Overall progress, weighted by the uncompressed size of each edition
    $p = [Math]::Max(0.0, $pct) / 100
    if ($r.Total -gt 0) { $overall = ($r.Done + $Item.Bytes * $p) / $r.Total }
    else                { $overall = (($r.Position - 1) + $p) / $r.Count }
    $overall = [Math]::Max($r.LastOverall, [Math]::Min(1.0, $overall))
    $r.LastOverall = $overall

    $elapsedAll = $r.Sw.Elapsed
    $elapsedIdx = $M.IdxElapsed

    $leftIdx = '--:--:--'
    if ($pct -ge 0.5 -and $elapsedIdx.TotalSeconds -ge 3) {
        $leftIdx = Format-Duration ([TimeSpan]::FromSeconds($elapsedIdx.TotalSeconds * (100 - $pct) / $pct))
    }
    # No overall remaining time / ETA: editions share most of their data, so the
    # first edition takes far longer than the following ones and any estimate
    # based on the overall progress would be wrong.

    $speed = '-'
    if ($pct -ge 0 -and $elapsedAll.TotalSeconds -ge 1) {
        $processed = $r.Done + $Item.Bytes * $p
        $speed = (Format-Bytes ($processed / $elapsedAll.TotalSeconds)) + '/s'
    }

    $pctText = if ($pct -ge 0) { '{0,5:N1} %' -f $pct } else { ' --.- %' }
    $allText = '{0,5:N1} %' -f ($overall * 100)

    Set-Title ('{0:N0} % - {1} - {2}' -f ($overall * 100), (Get-ConversionLabel), $Item.Name)
    Set-TaskbarProgress 1 ([int]($overall * 100))

    if (-not $Script:CanDraw) {
        # Fallback (ISE / redirected output): Write-Progress plus 10 % milestones
        Write-Progress -Id 1 -Activity "Converting $(Get-ConversionLabel)" -Status "Overall $allText - elapsed $(Format-Duration $elapsedAll)" `
            -PercentComplete ([int]($overall * 100))
        Write-Progress -Id 2 -ParentId 1 -Activity "Edition $($r.Position) of $($r.Count): $($Item.Name)" -Status "$pctText - remaining $leftIdx" `
            -PercentComplete ([int][Math]::Max(0, $pct))
        $milestone = [int][Math]::Floor($overall * 10)
        if ($milestone -gt $r.Milestone) {
            $r.Milestone = $milestone
            Write-Host ("        overall {0} - edition {1} - elapsed {2}" -f $allText.Trim(), $pctText.Trim(), (Format-Duration $elapsedAll))
        }
        return
    }

    $memText = if ($M.Memory -gt 0) { Format-Bytes $M.Memory } else { '-' }
    $sysText = '-'
    $sysColor = 'White'
    if ($M.System) {
        $ratio = $M.System.Used / $M.System.Total
        $sysText = '{0} / {1}  ({2:N0} %)' -f (Format-Bytes $M.System.Used), (Format-Bytes $M.System.Total), ($ratio * 100)
        if ($ratio -ge 0.9) { $sysColor = 'Yellow' }
    }
    $freeText = '-'
    $freeColor = 'White'
    if ($M.Free) {
        $freeText = "$(Format-Bytes $M.Free.Free) free on $($M.Free.Root)"
        if ($M.Free.Free -lt 2GB) { $freeColor = 'Yellow' }
    }

    try { [Console]::SetCursorPosition(0, $Script:DashTop) } catch { return }

    Out-Row '  ' White 'Edition      ' Gray (Get-ShortText $Item.Name 40) Yellow ("   index {0} $($g.Dot) {1} of {2}" -f $Item.Index, $r.Position, $r.Count) Gray
    Out-Row
    Out-Row '  ' White 'Current      ' Gray (New-Bar $pct) Green "  $pctText" White '   left ' Gray $leftIdx White
    Out-Row '  ' White 'Overall      ' Gray (New-Bar ($overall * 100)) Cyan "  $allText" White
    Out-Row
    Out-Row '  ' White 'Elapsed      ' Gray (Format-Duration $elapsedAll) White
    Out-Row '  ' White 'Throughput   ' Gray $speed White '  (uncompressed image data)' Gray
    Out-Row '  ' White 'Written      ' Gray (Format-Bytes $M.DstLength) White '   ' White $freeText $freeColor
    Out-Row '  ' White 'DISM memory  ' Gray $memText White "  (peak $(Format-Bytes $r.PeakMemory))" Gray '     CPU ' Gray ('{0:N0} %' -f $M.CpuPercent) White
    Out-Row '  ' White 'System RAM   ' Gray $sysText $sysColor
    Out-Row
    Out-Row '  ' White 'Completed    ' Gray ("{0} of {1} editions" -f $r.Results.Count, $r.Count) White

    $recent = @($r.Results | Select-Object -Last 3)
    for ($i = 0; $i -lt 3; $i++) {
        if ($i -lt $recent.Count) {
            $res = $recent[$i]
            Out-Row '               ' White ('[{0,2}] ' -f $res.Index) Green (Get-ShortText $res.Name 32).PadRight(33) White (Format-Duration $res.Duration) Gray ('   {0}/s' -f (Format-Bytes $res.Speed)) Gray
        }
        else { Out-Row }
    }
    Out-Row
}

function Stop-Dashboard {
    if ($Script:CanDraw -and $Script:DashTop -ge 0) {
        try { [Console]::SetCursorPosition(0, $Script:DashTop + $Script:DashLines) } catch { }
        try { [Console]::CursorVisible = $true } catch { }
    }
    $Script:DashTop = -1
}

function Invoke-MonitoredExport {
    param([object]$Item)

    $r = $Script:Run
    $r.Position++
    $cfg = $Script:Cfg

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $Script:DismExe
    $psi.Arguments = "/English /Export-Image /SourceImageFile:`"$($cfg.Source)`" /SourceIndex:$($Item.Index) " +
                     "/DestinationImageFile:`"$($cfg.Destination)`" /Compress:$($cfg.Compression) /CheckIntegrity"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [Console]::OutputEncoding
    $psi.StandardErrorEncoding  = [Console]::OutputEncoding

    Start-Dashboard $Item

    $idxSw   = [System.Diagnostics.Stopwatch]::StartNew()
    $proc    = [System.Diagnostics.Process]::Start($psi)
    $reader  = $proc.StandardOutput
    $errTask = $proc.StandardError.ReadToEndAsync()
    $buffer  = New-Object char[] 4096
    $text    = New-Object System.Text.StringBuilder
    $readTask = $reader.ReadAsync($buffer, 0, $buffer.Length)

    $pct = -1.0
    $metrics = @{ Pct = -1.0; IdxElapsed = [TimeSpan]::Zero; Memory = [long]0; CpuPercent = 0.0; System = $null; DstLength = [long]0; Free = $null }
    $cpuLast = 0.0
    $cpuLastTime = 0.0
    $cpuSeconds = 0.0
    $nextRender = 0.0
    $nextSample = 0.0
    $cores = [Math]::Max(1, [Environment]::ProcessorCount)
    $invariant = [Globalization.CultureInfo]::InvariantCulture

    while ($true) {
        if ($readTask.Wait(200)) {
            $n = $readTask.Result
            if ($n -le 0) { break }
            [void]$text.Append($buffer, 0, $n)

            # DISM progress looks like "[=====    45.3%    ]"; parse the newest value
            $start = [Math]::Max(0, $text.Length - 96)
            $tail = $text.ToString($start, $text.Length - $start)
            $found = [regex]::Matches($tail, '(\d{1,3}(?:[.,]\d+)?)\s*%')
            if ($found.Count -gt 0) {
                $v = [double]::Parse(($found[$found.Count - 1].Groups[1].Value -replace ',', '.'), $invariant)
                if ($v -le 100 -and $v -gt $pct) { $pct = $v }
            }
            $readTask = $reader.ReadAsync($buffer, 0, $buffer.Length)
        }

        $t = $idxSw.Elapsed.TotalSeconds
        if ($t -ge $nextSample) {
            $usage = Get-DismTreeUsage $proc
            if ($usage.Memory -gt 0) { $metrics.Memory = $usage.Memory }
            if ($usage.Memory -gt $r.PeakMemory) { $r.PeakMemory = $usage.Memory }
            if ($usage.CpuSeconds -gt $cpuSeconds) { $cpuSeconds = $usage.CpuSeconds }
            if ($t - $cpuLastTime -ge 0.5) {
                $metrics.CpuPercent = [Math]::Min(100, [Math]::Max(0, 100 * ($usage.CpuSeconds - $cpuLast) / (($t - $cpuLastTime) * $cores)))
                $cpuLast = $usage.CpuSeconds
                $cpuLastTime = $t
            }
            $metrics.System    = Get-SystemMemory
            $metrics.DstLength = Get-FileLength $cfg.Destination
            $metrics.Free      = Get-FreeSpace $cfg.Destination
            $nextSample = $t + 2
        }
        if ($t -ge $nextRender) {
            $metrics.Pct = $pct
            $metrics.IdxElapsed = $idxSw.Elapsed
            Update-Dashboard $Item $metrics
            $nextRender = $t + 0.5
        }
    }

    $proc.WaitForExit()
    $idxSw.Stop()
    $exitCode = $proc.ExitCode
    try { $cpuSeconds = [Math]::Max($cpuSeconds, $proc.TotalProcessorTime.TotalSeconds) } catch { }
    $r.CpuSeconds += $cpuSeconds
    $output = $text.ToString() + $errTask.Result

    if ($exitCode -ne 0) {
        $metrics.Pct = $pct
        $metrics.IdxElapsed = $idxSw.Elapsed
        Update-Dashboard $Item $metrics
        Stop-Dashboard
        $msg = "DISM failed while exporting index $($Item.Index) - $($Item.Name) (exit code $('0x{0:X8}' -f $exitCode))."
        $hint = Get-ErrorHint $exitCode
        if ($hint) { $msg += "`n$hint" }
        $msg += "`nThe destination image is incomplete and should not be used."
        throw ($msg + "`n`nDISM output:`n" + ((Get-DismMessages $output) -join "`n"))
    }

    $seconds = [Math]::Max(0.001, $idxSw.Elapsed.TotalSeconds)
    $r.Results.Add([pscustomobject]@{
        Index    = $Item.Index
        Name     = $Item.Name
        Bytes    = $Item.Bytes
        Duration = $idxSw.Elapsed
        Speed    = $Item.Bytes / $seconds
    })
    $r.Done += $Item.Bytes

    # Final state of this edition
    $metrics.Pct = 100.0
    $metrics.IdxElapsed = $idxSw.Elapsed
    $metrics.DstLength = Get-FileLength $cfg.Destination
    Update-Dashboard $Item $metrics
    Stop-Dashboard
}

function Invoke-Export {
    param([object[]]$Selected)

    $total = [long]0
    foreach ($s in $Selected) { $total += $s.Bytes }

    $Script:Run = @{
        Sw          = [System.Diagnostics.Stopwatch]::StartNew()
        Total       = $total
        Done        = [long]0
        Count       = $Selected.Count
        Position    = 0
        PeakMemory  = [long]0
        CpuSeconds  = 0.0
        Results     = New-Object System.Collections.Generic.List[object]
        LastOverall = 0.0
        Milestone   = 0
        Selected    = $Selected
        SourceSize  = Get-FileLength $Script:Cfg.Source
        SourceInfo  = Get-WimHeaderInfo $Script:Cfg.Source
    }

    Remove-Destination
    try {
        foreach ($item in $Selected) { Invoke-MonitoredExport $item }
        $Script:Run.Sw.Stop()
        Set-TaskbarProgress 0
    }
    catch {
        $Script:Run.Sw.Stop()
        Set-TaskbarProgress 2 100
        throw
    }
    finally {
        Stop-Dashboard
        if (-not $Script:CanDraw) {
            Write-Progress -Id 2 -Activity 'Edition' -Completed
            Write-Progress -Id 1 -Activity 'Converting' -Completed
        }
    }
}

# =============================================================================
# Statistics
# =============================================================================

function Get-Summary {
    $r   = $Script:Run
    $cfg = $Script:Cfg
    $rows  = New-Object System.Collections.Generic.List[object]
    $notes = New-Object System.Collections.Generic.List[object]

    function Add-Row([string]$Label, [string]$Value, [string]$Color = 'White', [string]$Note = '') {
        $rows.Add([pscustomobject]@{ Label = $Label; Value = $Value; Color = $Color; Note = $Note })
    }
    function Add-Note([string]$Text, [string]$Color = 'Gray') {
        $notes.Add([pscustomobject]@{ Text = $Text; Color = $Color })
    }

    $srcSize = $r.SourceSize
    $dstSize = Get-FileLength $cfg.Destination
    $srcInfo = $r.SourceInfo
    $dstInfo = Get-WimHeaderInfo $cfg.Destination
    $data    = $r.Total
    $elapsed = $r.Sw.Elapsed
    $arrow   = $Script:G.Arrow
    $allIdx  = if ($srcInfo) { [int]$srcInfo.ImageCount } else { 0 }

    Add-Row 'Conversion'  (Get-ConversionLabel)
    Add-Row 'Source'      (Get-ShortPath $cfg.Source)
    Add-Row 'Destination' (Get-ShortPath $cfg.Destination)
    $edText = "$($r.Count) exported"
    if ($allIdx -gt 0) { $edText += " (source contains $allIdx)" }
    Add-Row 'Editions' $edText

    $srcCodec = if ($srcInfo) { $srcInfo.Text } else { 'unknown' }
    $dstCodec = if ($dstInfo) { $dstInfo.Text } else { $Script:CodecOf[$cfg.Compression] }
    Add-Row 'Codec' "$srcCodec  $arrow  $dstCodec"
    Add-Row 'Compression' "$($cfg.Compression)  ($($Script:CodecOf[$cfg.Compression]))"
    Add-Row 'Size before' (Format-Bytes $srcSize)
    Add-Row 'Size after'  (Format-Bytes $dstSize)

    if ($srcSize -gt 0) {
        $diff = $dstSize - $srcSize
        $diffPct = 100.0 * $diff / $srcSize
        $sign = if ($diff -gt 0) { '+' } else { '-' }
        $color = if ($diff -le 0) { 'Green' } else { 'Yellow' }
        Add-Row 'Difference' ('{0}{1}  ({0}{2:N1} %)' -f $sign, (Format-Bytes ([Math]::Abs($diff))), [Math]::Abs($diffPct)) $color
        if ($dstSize -gt 0) {
            Add-Row 'Size ratio' ('{0:N2} : 1  (after = {1:N1} % of before)' -f ($srcSize / $dstSize), (100.0 * $dstSize / $srcSize))
        }
    }
    if ($data -gt 0 -and $dstSize -gt 0) {
        Add-Row 'Image data' "$(Format-Bytes $data) uncompressed"
        Add-Row 'Compress. rate' ('{0:N2} : 1  ({1:N1} % saved)' -f ($data / $dstSize), (100 - 100.0 * $dstSize / $data)) 'Green'
    }

    Add-Row 'Duration' (Format-Duration $elapsed)
    if ($elapsed.TotalSeconds -gt 0 -and $data -gt 0) {
        Add-Row 'Throughput' ("$(Format-Bytes ($data / $elapsed.TotalSeconds))/s  (read)   $(Format-Bytes ($dstSize / $elapsed.TotalSeconds))/s  (written)")
    }
    Add-Row 'Peak DISM RAM' (Format-Bytes $r.PeakMemory)
    if ($elapsed.TotalSeconds -gt 0) {
        Add-Row 'CPU time' ('{0}  (avg {1:N1} of {2} cores busy)' -f (Format-Duration ([TimeSpan]::FromSeconds($r.CpuSeconds))), ($r.CpuSeconds / $elapsed.TotalSeconds), [Environment]::ProcessorCount)
    }

    # Verification: read the destination back
    try {
        $check = @(Get-ImageIndexes -ImagePath $cfg.Destination)
        $expected = @($r.Selected | ForEach-Object { $_.Name })
        $actual   = @($check | ForEach-Object { $_.Name })
        if ($check.Count -eq $r.Count -and -not (Compare-Object $expected $actual -SyncWindow 0)) {
            Add-Row 'Verification' "OK - destination contains $($check.Count) edition(s)" 'Green'
        }
        else {
            Add-Row 'Verification' "Mismatch - destination contains $($check.Count) edition(s), expected $($r.Count)" 'Red'
        }
    }
    catch {
        Add-Row 'Verification' 'Failed - destination could not be read by DISM' 'Red'
    }

    if ($dstSize -gt 4GB - 1) {
        $tip = if ($cfg.Compression -eq 'Recovery') { "Split it with 'dism /Split-Image' (.swm files)." } else { "Use ESD/Recovery compression or 'dism /Split-Image'." }
        Add-Note "Destination is larger than 4 GB: it does not fit on a FAT32 USB stick. $tip" 'Yellow'
    }
    elseif ($dstSize -gt 0) {
        Add-Note 'Destination is below 4 GB: it fits on a FAT32 USB stick.' 'Green'
    }
    if ($allIdx -gt $r.Count) {
        Add-Note "Only $($r.Count) of $allIdx editions were exported, so 'Size before' includes editions that are not in the destination." 'Gray'
    }
    if ($cfg.Compression -eq 'Recovery' -and $cfg.Destination -match '\.wim$') {
        Add-Note 'Recovery (LZMS) data inside a .wim file may not be readable by all tools.' 'Yellow'
    }

    return [pscustomobject]@{ Rows = $rows; Notes = $notes; Results = $r.Results }
}

function Write-Summary {
    param([object]$Summary)
    foreach ($row in $Summary.Rows) { Write-Field $row.Label $row.Value $row.Color $row.Note }
    Write-Host ''
    Out-Row '  ' White ' Idx  ' Gray ('Edition'.PadRight(34)) Gray ('Data'.PadLeft(10)) Gray ('Duration'.PadLeft(10)) Gray ('Speed'.PadLeft(13)) Gray
    foreach ($res in $Summary.Results) {
        Out-Row '  ' White ('[{0,2}]  ' -f $res.Index) Yellow (Get-ShortText $res.Name 33).PadRight(34) White `
            (Format-Bytes $res.Bytes).PadLeft(10) Gray (Format-Duration $res.Duration).PadLeft(10) Gray ((Format-Bytes $res.Speed) + '/s').PadLeft(13) Gray
    }
    if ($Summary.Notes.Count -gt 0) {
        Write-Host ''
        foreach ($n in $Summary.Notes) { Write-Wrapped $n.Text $n.Color }
    }
}

function Save-Report {
    param([object]$Summary, [string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("$Script:AppName $Script:Version - conversion report")
    $lines.Add("Created : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
    $lines.Add("DISM    : $Script:DismExe")
    $lines.Add('')
    foreach ($row in $Summary.Rows) {
        $value = $row.Value
        if ($row.Label -eq 'Source')      { $value = $Script:Cfg.Source }
        if ($row.Label -eq 'Destination') { $value = $Script:Cfg.Destination }
        $lines.Add(('{0,-16}: {1}' -f $row.Label, $value))
    }
    $lines.Add('')
    $lines.Add(('{0,-6}{1,-40}{2,12}{3,10}{4,14}' -f 'Idx', 'Edition', 'Data', 'Duration', 'Speed'))
    foreach ($res in $Summary.Results) {
        $lines.Add(('{0,-6}{1,-40}{2,12}{3,10}{4,14}' -f $res.Index, (Get-ShortText $res.Name 39), (Format-Bytes $res.Bytes), (Format-Duration $res.Duration), ((Format-Bytes $res.Speed) + '/s')))
    }
    if ($Summary.Notes.Count -gt 0) {
        $lines.Add('')
        foreach ($n in $Summary.Notes) { $lines.Add("Note: $($n.Text)") }
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

# =============================================================================
# Interactive wizard screens
# =============================================================================

function Write-ImageInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Field '' 'file not found' Yellow
        return
    }
    $info = Get-WimHeaderInfo $Path
    $text = Format-Bytes (Get-FileLength $Path)
    if ($info) { $text += "  $($Script:G.Dot)  $($info.Text)  $($Script:G.Dot)  $($info.ImageCount) edition(s)" }
    Write-Field '' $text Gray
}

function Show-Home {
    Set-Title $Script:BaseTitle
    Set-TaskbarProgress 0
    Write-Header @('Welcome')
    Write-Text 'Convert WIM images to ESD images and vice-versa.'
    Write-Text 'Live progress, remaining time and a detailed statistics report included.' Gray
    Write-Host ''
    $dismVersion = '-'
    try { $dismVersion = (Get-Item -LiteralPath $Script:DismExe).VersionInfo.ProductVersion } catch { }
    Write-Field 'DISM' (Get-ShortPath $Script:DismExe)
    Write-Field 'DISM version' $dismVersion
    Write-Field 'PowerShell' "$($PSVersionTable.PSVersion)  ($($PSVersionTable.PSEdition))"
    Write-Field 'CPU cores' "$([Environment]::ProcessorCount)"
    Write-Host ''
    Write-Text 'Documentation :' Gray
    Write-Text $Script:RepoUrl Cyan
    Wait-AnyKey
}

function Select-ConversionType {
    Write-Header @('Step 1 of 5  ' + $Script:G.Dot + '  Conversion type')
    Write-Text 'What type of conversion do you want ?'
    Write-Host ''
    Write-Option '1' "WIM $($Script:G.Arrow) ESD" '   smaller image (Recovery / LZMS compression)'
    Write-Option '2' "ESD $($Script:G.Arrow) WIM" '   editable / installable image (Maximum / LZX compression)'
    Write-Footer
    $mode = if ((Read-Key '12') -eq '1') { 'WimToEsd' } else { 'EsdToWim' }
    $Script:Cfg = Get-Preset $mode
    $Script:Cfg.Source      = Resolve-FullPath $Script:Cfg.Source $Script:ScriptDir
    $Script:Cfg.Destination = Resolve-FullPath $Script:Cfg.Destination $Script:ScriptDir
}

function Read-PathInput {
    param([string]$Header, [string]$What)
    Write-Header @("Step $Header  $($Script:G.Dot)  $(Get-ConversionLabel)")
    Write-Text "Please enter the path to the $What image."
    Write-Text 'Paths containing spaces are supported, quotes are removed automatically.' Gray
    Write-Host ''
    $answer = Read-Line 'Path : '
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
    return Resolve-FullPath -Path $answer -BasePath $Script:ScriptDir
}

function Select-SourcePath {
    Write-Header @("Step 2 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Source image")
    Write-Field 'Source image' (Get-ShortPath $Script:Cfg.Source)
    Write-ImageInfo $Script:Cfg.Source
    Write-Host ''
    Write-Text 'Do you wish to change it ?'
    Write-Host ''
    Write-Option 'Y' 'Yes'
    Write-Option 'N' 'No'
    Write-Footer
    $change = (Read-Key 'YN') -eq 'Y'

    while ($true) {
        if ($change) {
            $p = Read-PathInput -Header '2 of 5' -What 'source'
            if ($p) { $Script:Cfg.Source = $p }
        }
        if (Test-Path -LiteralPath $Script:Cfg.Source -PathType Leaf) { return }
        Write-Host ''
        Write-Text "The source image does not exist :" Red
        Write-Text (Get-ShortPath $Script:Cfg.Source 70) Red
        Wait-AnyKey
        $change = $true
    }
}

function Select-DestinationPath {
    while ($true) {
        Write-Header @("Step 3 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Destination image")
        Write-Field 'Destination' (Get-ShortPath $Script:Cfg.Destination)
        if (Test-Path -LiteralPath $Script:Cfg.Destination) {
            Write-Field '' 'file exists and will be overwritten' Yellow
        }
        $free = Get-FreeSpace $Script:Cfg.Destination
        if ($free) { Write-Field 'Free space' "$(Format-Bytes $free.Free) on $($free.Root)  ($($free.Format))" Gray }
        Write-Host ''
        Write-Text 'Do you wish to change it ?'
        Write-Host ''
        Write-Option 'Y' 'Yes'
        Write-Option 'N' 'No'
        Write-Footer
        if ((Read-Key 'YN') -eq 'Y') {
            $p = Read-PathInput -Header '3 of 5' -What 'destination'
            if ($p) { $Script:Cfg.Destination = $p }
            continue
        }
        if (-not [string]::Equals($Script:Cfg.Source, $Script:Cfg.Destination, [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        Write-Host ''
        Write-Text 'Source and destination image must not be the same file.' Red
        Wait-AnyKey
    }
}

function Select-Compression {
    $choices = @(
        @{ Key = '1'; Name = 'None';     Codec = 'stored';   Text = 'fastest  - destination bigger than source' },
        @{ Key = '2'; Name = 'Fast';     Codec = 'XPRESS';   Text = 'fast     - destination may be bigger than source' },
        @{ Key = '3'; Name = 'Maximum';  Codec = 'LZX';      Text = 'slow     - recommended maximum for WIM images' },
        @{ Key = '4'; Name = 'Recovery'; Codec = 'LZMS';     Text = 'slowest  - smallest, only for ESD images' }
    )
    Write-Header @("Step 4 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Compression")
    Write-Text 'Select the compression type (Enter keeps the current one) :'
    Write-Host ''
    foreach ($c in $choices) {
        $current = $c.Name -eq $Script:Cfg.Compression
        $name = ('{0,-9}' -f $c.Name)
        $mark = if ($current) { '  <- current' } else { '' }
        Out-Row '   [' Gray $c.Key Yellow ']  ' Gray $name $(if ($current) { 'Green' } else { 'White' }) ('{0,-8}' -f $c.Codec) Cyan $c.Text Gray $mark Green
    }
    Write-Footer

    Write-Host -NoNewline ($Script:Margin + '  Your choice : ') -ForegroundColor Yellow
    while ($true) {
        $key = $null
        try {
            $info = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($info.VirtualKeyCode -eq 13) { $key = 'ENTER' }
            elseif ($info.Character -ne [char]0) { $key = ([string]$info.Character).ToUpperInvariant() }
        }
        catch {
            $answer = Read-Host
            $key = if ([string]::IsNullOrWhiteSpace($answer)) { 'ENTER' } else { $answer.Trim().Substring(0, 1).ToUpperInvariant() }
        }
        switch ($key) {
            'Q'     { Write-Host 'Q'; throw [QuitSignal]::new() }
            'S'     { Write-Host 'S'; throw [StartOverSignal]::new() }
            'ENTER' { Write-Host $Script:Cfg.Compression; return }
        }
        $match = $choices | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        if ($match) {
            Write-Host $match.Name
            $Script:Cfg.Compression = $match.Name
            return
        }
    }
}

function Write-IndexTable {
    param([object[]]$Indexes)
    Out-Row '   ' White ' Idx  ' Gray ('Edition'.PadRight(48)) Gray ('Size'.PadLeft(12)) Gray
    foreach ($i in $Indexes) {
        Out-Row '   ' White ('[{0,2}]  ' -f $i.Index) Yellow (Get-ShortText $i.Name 47).PadRight(48) White (Format-Bytes $i.Bytes).PadLeft(12) Gray
    }
}

function Select-Indexes {
    Write-Header @("Step 5 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Analyzing source image . . .")
    $indexes = @(Get-ImageIndexes -ImagePath $Script:Cfg.Source)

    Write-Header @("Step 5 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Editions")
    Write-Text "The $($Script:Cfg.SrcType) image contains $($indexes.Count) edition(s) :"
    Write-Host ''
    Write-IndexTable $indexes
    Write-Host ''
    Write-Option '1' 'Export one or several editions' '   e.g. 6  or  1,3-5'
    Write-Option '2' 'Export all editions'
    Write-Footer

    if ((Read-Key '12') -eq '2') { return $indexes }

    $message = $null
    while ($true) {
        Write-Header @("Step 5 of 5  $($Script:G.Dot)  $(Get-ConversionLabel)  $($Script:G.Dot)  Select editions")
        Write-IndexTable $indexes
        Write-Host ''
        Write-Text 'Enter the index number(s) to export, e.g. 6  or  1,3-5' Gray
        if ($message) { Write-Text $message Red }
        Write-Footer
        $answer = Read-Line 'Index : '
        if (-not $answer) { continue }
        switch ($answer.ToUpperInvariant()) {
            'Q' { throw [QuitSignal]::new() }
            'S' { throw [StartOverSignal]::new() }
        }
        try {
            $selected = @(ConvertTo-IndexSelection -Text $answer -Indexes $indexes)
            if ($selected.Count -gt 0) { return $selected }
        }
        catch { $message = $_.Exception.Message }
    }
}

function Show-Confirmation {
    param([object[]]$Selected)
    $cfg = $Script:Cfg
    $data = [long]0
    foreach ($s in $Selected) { $data += $s.Bytes }

    Write-Header @("$(Get-ConversionLabel)  $($Script:G.Dot)  Ready to convert")
    Write-Field 'Source' (Get-ShortPath $cfg.Source)
    Write-ImageInfo $cfg.Source
    Write-Field 'Destination' (Get-ShortPath $cfg.Destination)
    if (Test-Path -LiteralPath $cfg.Destination) { Write-Field '' 'file exists and will be overwritten' Yellow }
    Write-Field 'Compression' "$($cfg.Compression)  ($($Script:CodecOf[$cfg.Compression]))"
    Write-Field 'Editions' "$($Selected.Count) selected  $($Script:G.Dot)  $(Format-Bytes $data) of image data"
    $shown = 0
    foreach ($s in $Selected) {
        if ($shown -ge 5) { Write-Field '' "... and $($Selected.Count - 5) more" Gray; break }
        Write-Field '' ('[{0,2}] {1}' -f $s.Index, $s.Name) Gray
        $shown++
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    $free = Get-FreeSpace $cfg.Destination
    if ($free) {
        Write-Field 'Free space' "$(Format-Bytes $free.Free) on $($free.Root)  ($($free.Format))"
        if ($free.Free -lt (Get-FileLength $cfg.Source)) { $warnings.Add('Free space on the destination drive may not be sufficient.') }
    }
    if ($cfg.Compression -eq 'Recovery' -and $cfg.Destination -match '\.wim$') {
        $warnings.Add('Recovery (LZMS) inside a .wim file may not be readable by all tools.')
    }
    if ($cfg.Compression -ne 'Recovery' -and $cfg.Destination -match '\.esd$') {
        $warnings.Add('ESD images are normally created with Recovery compression.')
    }
    if ($warnings.Count -gt 0) {
        Write-Host ''
        foreach ($w in $warnings) { Write-Wrapped "Warning : $w" Yellow }
    }
    Write-Host ''
    Write-Option 'Y' 'Start conversion' '   (S = change settings)'
    Write-Footer
    $null = Read-Key 'Y'
}

function Show-Summary {
    Set-Title "$Script:BaseTitle - Completed"
    if ($Script:CanDraw) { try { [Console]::Beep(880, 150); [Console]::Beep(1175, 200) } catch { } }
    $summary = Get-Summary
    Write-Header @("$(Get-ConversionLabel)  $($Script:G.Dot)  Conversion completed successfully") -Accent Green
    Write-Summary $summary
    Write-Footer 'R' 'Save report'

    $reportFile = "$($Script:Cfg.Destination).report.txt"
    while ($true) {
        $null = Read-Key 'R'
        try {
            Save-Report $summary $reportFile
            Write-Text "Report saved : $(Get-ShortPath $reportFile 60)" Green
        }
        catch {
            Write-Text "Report could not be saved : $($_.Exception.Message)" Red
        }
    }
}

function Show-Error {
    param([string]$Message)
    Set-Title "$Script:BaseTitle - Error"
    Write-Header @('Error') -Accent Red
    Write-Text 'Something went wrong . . .' Red
    Write-Host ''
    Write-Wrapped $Message White
    Write-Host ''
    Write-Text 'DISM log file :' Gray
    Write-Text "$env:SystemRoot\Logs\DISM\dism.log" Cyan
    Write-Host ''
    Write-Text 'If the problem persists, please open an issue on :' Gray
    Write-Text "$($Script:RepoUrl)issues" Cyan
    Write-Footer
    $null = Read-Key ''
}

# =============================================================================
# Modes
# =============================================================================

function Start-Interactive {
    $rawUI = $Host.UI.RawUI
    $oldColors = $null
    $oldTitle = $null
    $quit = $false
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
                $selected = @(Select-Indexes)
                Show-Confirmation $selected
                Invoke-Export $selected
                Show-Summary
            }
            catch [StartOverSignal] { $action = 'S' }
            catch [QuitSignal]      { $action = 'Q' }
            catch                   { $errorMessage = $_.Exception.Message }

            if ($null -ne $errorMessage) {
                try { Show-Error -Message $errorMessage }
                catch [StartOverSignal] { $action = 'S' }
                catch [QuitSignal]      { $action = 'Q' }
            }
            if ($action -eq 'Q') { $quit = $true; break }
        }
    }
    finally {
        Stop-Dashboard
        Set-TaskbarProgress 0
        if ($oldColors) {
            try {
                $rawUI.BackgroundColor = $oldColors[0]
                $rawUI.ForegroundColor = $oldColors[1]
            }
            catch { }
        }
        if ($oldTitle) { Set-Title $oldTitle }
        if ($quit) { Clear-Host }
    }
}

function Start-NonInteractive {
    $preset = Get-Preset $Mode
    $Script:Cfg = $preset
    $Script:Cfg.Source      = if ($Source)      { $Source }      else { Resolve-FullPath $preset.Source $Script:ScriptDir }
    $Script:Cfg.Destination = if ($Destination) { $Destination } else { Resolve-FullPath $preset.Destination $Script:ScriptDir }
    if ($Compression) { $Script:Cfg.Compression = $Compression }

    Write-Header @("$(Get-ConversionLabel)  $($Script:G.Dot)  non-interactive mode")
    Write-Field 'DISM'        (Get-ShortPath $Script:DismExe)
    Write-Field 'Source'      (Get-ShortPath $Script:Cfg.Source)
    Write-Field 'Destination' (Get-ShortPath $Script:Cfg.Destination)
    Write-Field 'Compression' "$($Script:Cfg.Compression)  ($($Script:CodecOf[$Script:Cfg.Compression]))"

    Assert-ValidPaths
    $indexes  = @(Get-ImageIndexes -ImagePath $Script:Cfg.Source)
    $selected = @(ConvertTo-IndexSelection -Text ($Index -join ',') -Indexes $indexes)
    Write-Host ''
    Write-IndexTable $selected

    Invoke-Export $selected

    $summary = Get-Summary
    Write-Host ''
    Write-Text 'Conversion completed successfully.' Green
    Write-Host ''
    Write-Summary $summary
    if ($ReportPath) {
        Save-Report $summary $ReportPath
        Write-Host ''
        Write-Text "Report saved : $ReportPath" Green
    }
}

# =============================================================================
# Entry point
# =============================================================================

Initialize-Ui

# Resolve parameter paths now, relative to the caller's current directory.
if ($Source)      { $Source      = Resolve-FullPath $Source      (Get-Location).Path }
if ($Destination) { $Destination = Resolve-FullPath $Destination (Get-Location).Path }
if ($ReportPath)  { $ReportPath  = Resolve-FullPath $ReportPath  (Get-Location).Path }

$Script:DismExe = Find-Dism
if (-not $Script:DismExe) {
    $msg = "No usable DISM executable was found.`n" +
           "Looked for : $env:SystemRoot\System32\dism.exe`n" +
           "Fallback   : $(Join-Path $Script:ScriptDir 'DISM\dism.exe')"
    if ($Script:Interactive) {
        Write-Header @('DISM not found') -Accent Red
        foreach ($l in ($msg -split "`n")) { Write-Text $l }
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
    Write-Header @('Administrator rights required') -Accent Red
    Write-Text 'You did not execute the script as Administrator.'
    Write-Text 'Administrator rights are required for DISM.'
    Write-Text 'You will now be prompted for Administrator rights (UAC).' Gray
    Wait-AnyKey

    # Re-launch with the same PowerShell edition (works from ISE as well).
    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    try {
        Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs | Out-Null
    }
    catch {
        Write-Host ''
        Write-Text 'Administrator rights were not granted. The script will now exit.' Red
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
    Stop-Dashboard
    Write-Host ''
    Write-Error $_.Exception.Message -ErrorAction Continue
    Write-Host "See also: $env:SystemRoot\Logs\DISM\dism.log"
    exit 1
}
