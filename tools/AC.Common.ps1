# =====================================================================
#  AC.Common.ps1 - gemeinsame Funktionen fuer Installer und Manager
#  Wird per Dot-Sourcing geladen:  . "$PSScriptRoot\AC.Common.ps1"
#  Benoetigt: Windows 10/11, PowerShell 5.1 (Windows-Standard), -STA
# =====================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Oberflaechen-Bibliotheken zuerst: sie werden auch gebraucht, um einen Ladefehler
# ueberhaupt in einem Fenster anzeigen zu koennen
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Stop-AcWithMessage {
    # Abbruch mit einer lesbaren Meldung statt einer Fehlerlawine
    param([string]$Message)
    try { [Windows.Forms.MessageBox]::Show($Message, 'AzerothCore Server Manager', 'OK', 'Error') | Out-Null } catch {}
    Write-Host $Message
    exit 1
}

$acMissing = @(@('AC.Lang.ps1', 'AC.Char.ps1', 'AC.Theme.ps1') | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
if ($acMissing.Count -gt 0) {
    Stop-AcWithMessage ("These script files are missing in $PSScriptRoot :" + [Environment]::NewLine +
                        ($acMissing -join ', ') + [Environment]::NewLine + [Environment]::NewLine +
                        "Copy ALL .ps1 files from the package into that folder.")
}
. (Join-Path $PSScriptRoot 'AC.Lang.ps1')

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# ---------------------------------------------------------------------
#  Versionen / Quellen  (hier anpassen, wenn sich etwas aendert)
# ---------------------------------------------------------------------
$script:AcVersions = @{
    BoostVersion   = '1.87.0'          # Boost-Binaries (msvc-14.3 = Visual Studio 2022)
    BoostToolset   = '14.3'
    MySqlVersion   = '8.4.6'           # MySQL 8.4 LTS, ZIP-Archiv (portabel im Serverordner)
    MySqlFallbacks = @('8.4.6', '8.4.5', '8.4.4', '8.4.3')   # falls eine Version nicht mehr angeboten wird
    VsGenerator    = 'Visual Studio 17 2022'
    BuildConfig    = 'RelWithDebInfo'
}

$script:AcRepos = @{
    standard = @{
        Label   = 'AzerothCore (offiziell, ohne Playerbots)'
        Core    = 'https://github.com/azerothcore/azerothcore-wotlk.git'
        Branch  = 'master'
        Modules = @()
    }
    playerbots = @{
        Label   = 'AzerothCore Playerbot-Fork + mod-playerbots'
        Core    = 'https://github.com/mod-playerbots/azerothcore-wotlk.git'
        Branch  = 'Playerbot'
        Modules = @(
            @{ Name = 'mod-playerbots'; Url = 'https://github.com/mod-playerbots/mod-playerbots.git'; Branch = 'master' }
        )
    }
}

$script:AcWingetPackages = @{
    Git      = 'Git.Git'
    CMake    = 'Kitware.CMake'
    # OpenSSL-Vollversion (mit include/ und lib/), NICHT die "Light"-Variante.
    # Die ID wurde von Microsoft mehrfach umbenannt -> mehrere Kandidaten der Reihe nach probieren.
    OpenSSL  = @('ShiningLight.OpenSSL.Dev', 'ShiningLight.OpenSSL', 'FireDaemon.OpenSSL')
    VCRedist = 'Microsoft.VCRedist.2015+.x64'
    VSBuild  = 'Microsoft.VisualStudio.2022.BuildTools'
}

# ---------------------------------------------------------------------
#  Logging / Fortschritt (GUI haengt sich hier ein)
# ---------------------------------------------------------------------
$script:AcToolsVersion = '2026-09-06.98'   # wird im Manager (Titel/Info) angezeigt
$script:AcUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
$script:AcLogHandler      = $null
$script:AcProgressHandler = $null
$script:AcLogFile         = $null

function Write-AcLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($script:AcLogFile) { try { Add-Content -Path $script:AcLogFile -Value $line -Encoding UTF8 } catch {} }
    if ($script:AcLogHandler) { & $script:AcLogHandler $line $Level } else { Write-Host $line }
}

function Set-AcProgress {
    param([int]$Percent, [string]$Text)
    if ($script:AcProgressHandler) { & $script:AcProgressHandler $Percent $Text }
}

function Invoke-AcDoEvents { [System.Windows.Forms.Application]::DoEvents() }

# ---------------------------------------------------------------------
#  Pfade & Einstellungen
# ---------------------------------------------------------------------
function Get-AcPaths {
    param([Parameter(Mandatory)][string]$Root)
    $root = $Root.TrimEnd('\')
    $build = Join-Path $root 'build'
    $bin   = Join-Path $build ("bin\" + $script:AcVersions.BuildConfig)
    return @{
        Root       = $root
        Source     = Join-Path $root 'source'
        Modules    = Join-Path $root 'source\modules'
        Build      = $build
        Bin        = $bin
        Configs    = Join-Path $bin 'configs'
        ModConfigs = Join-Path $bin 'configs\modules'
        Data       = Join-Path $root 'data'
        MySql      = Join-Path $root 'mysql'
        MySqlData  = Join-Path $root 'mysql\data'
        MySqlIni   = Join-Path $root 'mysql\my.ini'
        MySqlCnf   = Join-Path $root 'mysql\client.cnf'
        Deps       = Join-Path $root 'deps'
        Downloads  = Join-Path $root 'deps\downloads'
        Logs       = Join-Path $root 'logs'
        Tools      = Join-Path $root 'tools'
        Settings   = Join-Path $root 'ac-settings.json'
    }
}

function Get-AcSettings {
    param([string]$Root)
    $p = Get-AcPaths $Root
    if (Test-Path $p.Settings) {
        $raw = Get-Content $p.Settings -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        foreach ($prop in $raw.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
        if (-not $h.ContainsKey('Language') -or -not $h.Language) { $h.Language = 'en' }
        if (-not $h.ContainsKey('Theme') -or -not $h.Theme) { $h.Theme = 'light' }
        Set-AcLanguage $h.Language
        Set-AcTheme $h.Theme
        return $h
    }
    return @{
        Language       = 'en'
        Theme          = 'light'
        LuaVersion     = 'lua52'
        BuildProfile   = 'full'
        UpdateListHeight = 0
        Variant        = 'standard'
        CoreUrl        = $script:AcRepos.standard.Core
        CoreBranch     = $script:AcRepos.standard.Branch
        Modules        = @()
        MySqlPort      = 3306
        MySqlRootPassword = ''
        DbUser         = 'acore'
        DbPassword     = ''
        RealmName      = 'AzerothCore'
        BoostRoot      = ''
        OpenSslRoot    = ''
        VsInstallPath  = ''
        CompletedSteps = @()
        NeedsRebuild   = $false
        BuiltModules   = @()
    }
}

function Save-AcSettings {
    param([string]$Root, [hashtable]$Settings)
    $p = Get-AcPaths $Root
    $json = $Settings | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($p.Settings, $json, (New-Object Text.UTF8Encoding($false)))
}

function New-AcPassword {
    param([int]$Length = 20)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $rng = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rng)
    $sb = New-Object Text.StringBuilder
    foreach ($b in $rng) { [void]$sb.Append($chars[$b % $chars.Length]) }
    return $sb.ToString()
}

function ConvertTo-AcSlashPath { param([string]$Path) return ($Path -replace '\\', '/').TrimEnd('/') }

function Test-AcIsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-AcPathEntries {
    <#
      Setzt PATH neu aus den uebergebenen Eintraegen - ohne Doppelte und mit
      Laengenbegrenzung. Frueher wurde einfach vorne angehaengt, wodurch die
      Variable bei jedem Aufruf wuchs und irgendwann kein Prozess mehr startete
      ("Der Umgebungsvariablenname oder -wert ist zu lang").
    #>
    param([string[]]$Entries)
    $seen = New-Object Collections.Generic.HashSet[string]
    $clean = New-Object Collections.Generic.List[string]
    foreach ($e in $Entries) {
        if (-not $e) { continue }
        foreach ($part in ($e -split ';')) {
            $t = $part.Trim().TrimEnd('\')
            if (-not $t) { continue }
            if ($seen.Add($t.ToLower())) { $clean.Add($t) }
        }
    }
    $value = ($clean -join ';')
    if ($value.Length -gt 30000) { $value = $value.Substring(0, 30000) }
    $env:Path = $value
}

function Update-AcEnvPath {
    # PATH-Aenderungen von winget-Installationen in den laufenden Prozess uebernehmen
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    Set-AcPathEntries @($script:AcExtraPaths, $machine, $user, $env:Path)
}

# ---------------------------------------------------------------------
#  Prozesse mit Live-Ausgabe (ohne Events -> funktioniert in WinForms)
# ---------------------------------------------------------------------
function Get-AcOemEncoding {
    # Konsolenprogramme unter Windows schreiben in der OEM-Codepage (z.B. 850),
    # nicht in UTF-8. Wird als Rueckfall gebraucht, sonst werden Umlaute zu Muell.
    if ($script:AcOemEncoding) { return $script:AcOemEncoding }
    $cp = 437
    try { $cp = [int][Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage } catch {}
    try { $script:AcOemEncoding = [Text.Encoding]::GetEncoding($cp) }
    catch { $script:AcOemEncoding = [Text.Encoding]::Default }
    return $script:AcOemEncoding
}

function ConvertFrom-AcOutputBytes {
    <#
      Dekodiert eine Ausgabezeile. Git und CMake liefern UTF-8, MSBuild und die
      Windows-Werkzeuge die OEM-Codepage. Deshalb erst UTF-8 streng versuchen und
      bei ungueltigen Bytes auf OEM ausweichen - so bleibt beides lesbar.
    #>
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -eq 0) { return '' }
    try {
        $strict = New-Object Text.UTF8Encoding($false, $true)
        return $strict.GetString($Bytes)
    } catch {
        return (Get-AcOemEncoding).GetString($Bytes)
    }
}

function New-AcReaderState {
    param($Stream)
    $st = @{
        Stream  = $Stream
        Buffer  = New-Object byte[] 8192
        Bytes   = New-Object Collections.Generic.List[byte]
        Pending = New-Object Text.StringBuilder   # nur noch fuer Restausgabe am Ende
        Task    = $null
        Eof     = $false
    }
    $st.Task = $Stream.ReadAsync($st.Buffer, 0, $st.Buffer.Length)
    return $st
}

function Read-AcReaderLines {
    # Zeilen eines einzelnen Streams (nicht blockierend), byteweise gepuffert
    param($r)
    $lines = New-Object Collections.Generic.List[string]
    while (-not $r.Eof -and $r.Task.IsCompleted) {
        $n = 0
        try { $n = $r.Task.Result } catch { $n = 0 }
        if ($n -le 0) { $r.Eof = $true; break }
        for ($i = 0; $i -lt $n; $i++) { [void]$r.Bytes.Add($r.Buffer[$i]) }
        $r.Task = $r.Stream.ReadAsync($r.Buffer, 0, $r.Buffer.Length)
    }
    # vollstaendige Zeilen herausloesen (Zeilenende 10 oder 13)
    $start = 0
    for ($i = 0; $i -lt $r.Bytes.Count; $i++) {
        $b = $r.Bytes[$i]
        if ($b -ne 10 -and $b -ne 13) { continue }
        $len = $i - $start
        if ($len -gt 0) {
            $chunk = New-Object byte[] $len
            $r.Bytes.CopyTo($start, $chunk, 0, $len)
            $text = ConvertFrom-AcOutputBytes $chunk
            if ($text.Trim().Length -gt 0) { $lines.Add($text.TrimEnd()) }
        }
        $start = $i + 1
    }
    if ($start -gt 0) { $r.Bytes.RemoveRange(0, $start) }
    # sehr lange Zeile ohne Umbruch (z.B. Fortschrittsbalken) nicht endlos puffern
    if ($r.Bytes.Count -gt 32768) {
        $chunk = $r.Bytes.ToArray()
        $r.Bytes.Clear()
        $text = ConvertFrom-AcOutputBytes $chunk
        if ($text.Trim().Length -gt 0) { $lines.Add($text.TrimEnd()) }
    }
    return $lines
}

function Start-AcProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ArgumentList = '',
        [string]$WorkingDirectory = $null,
        [switch]$RedirectInput
    )
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName  = $FilePath
    $psi.Arguments = $ArgumentList
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardInput  = [bool]$RedirectInput
    $psi.CreateNoWindow         = $true
    $proc = [Diagnostics.Process]::Start($psi)
    return @{
        Process = $proc
        Readers = @(
            (New-AcReaderState $proc.StandardOutput.BaseStream),
            (New-AcReaderState $proc.StandardError.BaseStream)
        )
    }
}

function Read-AcProcessLines {
    # Alle verfuegbaren Zeilen aus stdout und stderr
    param($State)
    $lines = New-Object Collections.Generic.List[string]
    foreach ($r in $State.Readers) { foreach ($l in (Read-AcReaderLines $r)) { $lines.Add($l) } }
    return $lines
}

function Invoke-AcCaptureUi {
    <#
      Wie Invoke-AcCapture, haelt aber die Oberflaeche waehrend der Wartezeit bedienbar.
      Wird fuer alle Datenbankabfragen benutzt, damit das Fenster nicht einfriert.
    #>
    param([string]$FilePath, [string]$ArgumentList, [string]$WorkingDirectory = $null, [int]$TimeoutSeconds = 180)
    $state = Start-AcProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory
    $out = New-Object Text.StringBuilder
    $err = New-Object Text.StringBuilder
    $collect = {
        foreach ($l in (Read-AcReaderLines $state.Readers[0])) { [void]$out.AppendLine($l) }
        foreach ($l in (Read-AcReaderLines $state.Readers[1])) { [void]$err.AppendLine($l) }
    }
    $t0 = Get-Date
    while (-not (Test-AcProcessDone $state)) {
        & $collect
        Invoke-AcDoEvents
        Start-Sleep -Milliseconds 30
        if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSeconds) { try { $state.Process.Kill() } catch {}; throw ((T 'log.timeout') + ": $FilePath") }
    }
    & $collect
    foreach ($pair in @(@($state.Readers[0], $out), @($state.Readers[1], $err))) {
        if ($pair[0].Bytes.Count -gt 0) {
            [void]$pair[1].Append((ConvertFrom-AcOutputBytes $pair[0].Bytes.ToArray()))
            $pair[0].Bytes.Clear()
        }
    }
    return @{ ExitCode = $state.Process.ExitCode; Output = $out.ToString().TrimEnd(); Error = $err.ToString().Trim() }
}

function Test-AcProcessDone {
    param($State)
    if (-not $State.Process.HasExited) { return $false }
    foreach ($r in $State.Readers) { if (-not $r.Eof) { return $false } }
    return $true
}

function Get-AcPendingText {
    # noch nicht abgeschlossene Restzeilen beider Streams
    param($State)
    $sb = New-Object Text.StringBuilder
    foreach ($r in $State.Readers) {
        if ($r.Bytes.Count -gt 0) {
            [void]$sb.Append((ConvertFrom-AcOutputBytes $r.Bytes.ToArray()))
            $r.Bytes.Clear()
        }
    }
    return $sb.ToString()
}

function Invoke-AcProcess {
    # Fuehrt ein Programm aus, streamt Ausgabe ins Log, haelt GUI responsiv.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ArgumentList = '',
        [string]$WorkingDirectory = $null,
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 0,
        [string]$Priority = ''
    )
    Write-AcLog ("> {0} {1}" -f $FilePath, $ArgumentList) 'CMD'
    $state = Start-AcProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory
    # Unterprozesse (cl.exe usw.) erben die Prioritaet - so bleibt der Rechner bedienbar
    if ($Priority) { try { $state.Process.PriorityClass = [Diagnostics.ProcessPriorityClass]$Priority } catch {} }
    $started = Get-Date
    while (-not (Test-AcProcessDone $state)) {
        foreach ($l in (Read-AcProcessLines $state)) { Write-AcLog $l 'OUT' }
        Invoke-AcDoEvents
        Start-Sleep -Milliseconds 60
        if ($TimeoutSeconds -gt 0 -and ((Get-Date) - $started).TotalSeconds -gt $TimeoutSeconds) {
            try { $state.Process.Kill() } catch {}
            throw ((T 'log.timeout') + ": $FilePath")
        }
    }
    foreach ($l in (Read-AcProcessLines $state)) { Write-AcLog $l 'OUT' }
    $rest = Get-AcPendingText $state
    if ($rest.Trim()) { Write-AcLog $rest.Trim() 'OUT' }
    $code = $state.Process.ExitCode
    if ($code -ne 0 -and -not $AllowFailure) {
        throw (T 'log.cmdFailed' @($code, "$FilePath $ArgumentList"))
    }
    return $code
}

function Invoke-AcCapture {
    # Kurzbefehl, Ausgabe als String zurueck (fuer git rev-parse usw.)
    param([string]$FilePath, [string]$ArgumentList, [string]$WorkingDirectory = $null)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath; $psi.Arguments = $ArgumentList
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; Output = $out.Trim(); Error = $err.Trim() }
}

function Stop-AcProcessTree {
    param([int]$ProcessId)
    try { & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null } catch {}
}

# ---------------------------------------------------------------------
#  Download & Entpacken
# ---------------------------------------------------------------------

function Get-AcReferer {
    # Manche Anbieter (Oracle/MySQL) liefern 403, wenn der Herkunftsverweis fehlt
    param([string]$Url)
    if ($Url -match 'mysql\.com')     { return 'https://dev.mysql.com/downloads/mysql/' }
    if ($Url -match 'slproweb\.com')  { return 'https://slproweb.com/products/Win32OpenSSL.html' }
    if ($Url -match 'sourceforge\.net') { return 'https://sourceforge.net/projects/boost/files/boost-binaries/' }
    return ''
}

function Set-AcWebHeaders {
    param($Client, [string]$Url)
    $Client.Headers['User-Agent'] = $script:AcUserAgent
    $Client.Headers['Accept'] = '*/*'
    $Client.Headers['Accept-Language'] = 'en-US,en;q=0.9'
    $ref = Get-AcReferer $Url
    if ($ref) { $Client.Headers['Referer'] = $ref }
}

function Invoke-AcDownload {
    param(
        [Parameter(Mandatory)][string[]]$Urls,     # erste erreichbare URL gewinnt
        [Parameter(Mandatory)][string]$OutFile,
        [string]$Description = 'Download'
    )
    if (Test-Path $OutFile) {
        if ((Get-Item $OutFile).Length -gt 1MB) { Write-AcLog (T 'log.alreadyPresent' @($OutFile)); return $OutFile }
        Remove-Item $OutFile -Force
    }
    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $lastError = $null
    foreach ($url in $Urls) {
        Write-AcLog "$Description : $url"
        $tmp = "$OutFile.part"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        $total = 0L
        try {
            $req = [Net.WebRequest]::Create($url)
            $req.Method = 'HEAD'; $req.UserAgent = $script:AcUserAgent; $req.Timeout = 20000; $req.Accept = '*/*'
            $ref = Get-AcReferer $url; if ($ref) { $req.Referer = $ref }
            $resp = $req.GetResponse(); $total = $resp.ContentLength; $resp.Close()
        } catch { $total = 0L }
        $wc = New-Object Net.WebClient
        Set-AcWebHeaders $wc $url
        try {
            $task = $wc.DownloadFileTaskAsync($url, $tmp)
            $lastShown = -1
            while (-not $task.IsCompleted) {
                Invoke-AcDoEvents
                Start-Sleep -Milliseconds 250
                if (Test-Path $tmp) {
                    $have = (Get-Item $tmp).Length
                    if ($total -gt 0) {
                        $pct = [int](($have * 100) / $total)
                        if ($pct -ne $lastShown) { $lastShown = $pct; Set-AcProgress $pct ("{0}: {1} MB / {2} MB" -f $Description, [int]($have/1MB), [int]($total/1MB)) }
                    } else {
                        Set-AcProgress -1 ("{0}: {1} MB" -f $Description, [int]($have/1MB))
                    }
                }
            }
            if ($task.IsFaulted) { throw $task.Exception.InnerException }
            if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 1024) { throw (T 'log.downloadEmpty') }
            Move-Item $tmp $OutFile -Force
            Write-AcLog (T 'log.downloadDone' @([int]((Get-Item $OutFile).Length/1MB)))
            return $OutFile
        } catch {
            $lastError = $_
            $more = ($url -ne $Urls[-1])
            Write-AcLog (T 'log.downloadFailed' @($_.Exception.Message)) $(if ($more) { 'INFO' } else { 'WARN' })
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        } finally { $wc.Dispose() }
    }
    throw (T 'log.allDownloadsFailed' @($Description, $lastError.Exception.Message))
}

function Expand-AcZip {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$StripTopLevel
    )
    Write-AcLog (T 'log.extracting' @((Split-Path $ZipPath -Leaf), $Destination))
    Set-AcProgress -1 (T 'log.extractingShort' @((Split-Path $ZipPath -Leaf)))
    Invoke-AcDoEvents
    $tmp = Join-Path (Split-Path $Destination -Parent) ("_extract_" + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $tmp)
    $src = $tmp
    if ($StripTopLevel) {
        $entries = Get-ChildItem $tmp
        if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $src = $entries[0].FullName }
    }
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination | Out-Null }
    Get-ChildItem $src -Force | ForEach-Object { Move-Item $_.FullName -Destination $Destination -Force }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------
#  Werkzeuge finden / installieren
# ---------------------------------------------------------------------
function Find-AcExe {
    param([string]$Name, [string[]]$Candidates)
    Update-AcEnvPath
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $Candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Find-AcGit   { Find-AcExe 'git.exe'   @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe") }
function Find-AcCMake { Find-AcExe 'cmake.exe' @("$env:ProgramFiles\CMake\bin\cmake.exe") }
function Find-AcWinget { Find-AcExe 'winget.exe' @("$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe") }

function Find-AcVisualStudio {
    # Visual Studio 2022 (17.x) mit C++-Werkzeugen (Community/Pro/BuildTools)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $r = Invoke-AcCapture $vswhere '-products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath -latest'
    if ($r.Output) { return $r.Output.Split("`n")[0].Trim() }
    return $null
}

function Test-AcOpenSslDir {
    param([string]$Dir)
    if (-not $Dir) { return $false }
    $d = $Dir.Trim().TrimEnd('\')
    if (-not (Test-Path (Join-Path $d 'include\openssl\ssl.h'))) { return $false }
    $lib = Join-Path $d 'lib'
    if (-not (Test-Path $lib)) { return $false }
    # es muss auch wirklich eine Importbibliothek geben (Light-Variante hat keine)
    $has = @(Get-ChildItem $lib -Filter '*.lib' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    return ($has.Count -gt 0)
}

function Find-AcOpenSsl {
    # 1) Umgebungsvariablen und Standardpfade
    $cands = New-Object Collections.Generic.List[string]
    foreach ($c in @($env:OPENSSL_ROOT_DIR, $env:OPENSSL_DIR, "$env:ProgramFiles\OpenSSL-Win64", "$env:ProgramFiles\OpenSSL", 'C:\OpenSSL-Win64', 'C:\Program Files\FireDaemon OpenSSL 3')) {
        if ($c) { $cands.Add($c) }
    }
    # 2) Registry: alle Deinstallations-Eintraege mit "OpenSSL" im Namen (MSI und Inno Setup, beide Registry-Sichten)
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        try {
            foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if ($props -and $props.DisplayName -match 'OpenSSL' -and $props.InstallLocation) { $cands.Add([string]$props.InstallLocation) }
            }
        } catch {}
    }
    # 3) openssl.exe im PATH -> uebergeordneter Ordner
    try {
        $cmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
        if ($cmd) { $cands.Add((Split-Path (Split-Path $cmd.Source -Parent) -Parent)) }
    } catch {}
    # 4) uebliche Installationsorte auf allen lokalen Laufwerken
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($sub in @('OpenSSL-Win64', 'OpenSSL', 'Program Files\OpenSSL-Win64')) {
            $cands.Add((Join-Path $drive.Root $sub))
        }
    }
    foreach ($c in $cands) { if (Test-AcOpenSslDir $c) { return $c.Trim().TrimEnd('\') } }
    return $null
}

function Get-AcOpenSslVersion {
    param([string]$Dir)
    $h = Join-Path $Dir 'include\openssl\opensslv.h'
    if (-not (Test-Path $h)) { return $null }
    $txt = [IO.File]::ReadAllText($h)
    if ($txt -match 'OPENSSL_VERSION_STR\s+"([^"]+)"') { return $Matches[1] }
    if ($txt -match 'OPENSSL_VERSION_TEXT\s+"OpenSSL\s+([0-9][^\s"]*)') { return $Matches[1] }
    return $null
}

function Get-AcBoostDirName { return 'boost_' + ($script:AcVersions.BoostVersion -replace '\.', '_') }

function Find-AcBoost {
    param([string]$DepsDir)
    $libDir = 'lib64-msvc-' + $script:AcVersions.BoostToolset
    $cands = @()
    if ($DepsDir) { $cands += Join-Path $DepsDir (Get-AcBoostDirName) }
    if ($env:BOOST_ROOT) { $cands += $env:BOOST_ROOT }
    if (Test-Path 'C:\local') { $cands += (Get-ChildItem 'C:\local' -Directory -Filter 'boost_*' | Sort-Object Name -Descending | ForEach-Object { $_.FullName }) }
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c 'boost\version.hpp')) -and (Test-Path (Join-Path $c $libDir))) { return $c.TrimEnd('\') }
    }
    return $null
}

function Test-AcWingetPackageExists {
    param([string]$Winget, [string]$Id)
    $r = Invoke-AcCapture $Winget "show --id $Id -e --accept-source-agreements --disable-interactivity"
    return ($r.ExitCode -eq 0)
}

function Get-AcWingetVersions {
    # Liste der von winget angebotenen Versionen eines Pakets (neueste zuerst)
    param([string]$Winget, [string]$Id)
    $r = Invoke-AcCapture $Winget "show --id $Id -e --versions --accept-source-agreements --disable-interactivity"
    if ($r.ExitCode -ne 0) { return @() }
    $vers = New-Object Collections.Generic.List[string]
    foreach ($line in ($r.Output -split "`r?`n")) {
        $l = $line.Trim()
        if ($l -match '^\d+(\.\d+)+$') { $vers.Add($l) }
    }
    return $vers.ToArray()
}

function Install-AcWingetPackage {
    param([string[]]$Id, [string]$Name, [string]$Override = '', [string]$Version = '')
    $winget = Find-AcWinget
    if (-not $winget) { throw (T 'log.wingetMissing') }
    $lastCode = -1
    foreach ($pkg in @($Id)) {
        Write-AcLog (T 'log.wingetInstall' @($Name, "$pkg$(if ($Version) { " $Version" })"))
        $wingetArgs = "install --id $pkg -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
        if ($Version)  { $wingetArgs += " --version $Version" }
        if ($Override) { $wingetArgs += " --override `"$Override`"" }
        $lastCode = Invoke-AcProcess -FilePath $winget -ArgumentList $wingetArgs -AllowFailure
        Update-AcEnvPath
        if ($lastCode -eq 0) { return 0 }
        # -1978335189 = bereits aktuell installiert, das ist kein Fehler
        if ($lastCode -eq -1978335189) { Write-AcLog (T 'log.wingetCurrent' @($Name)) ; return 0 }
        # -1978335212 = Paket-ID existiert nicht -> naechsten Kandidaten probieren
        if ($lastCode -eq -1978335212 -and @($Id).Count -gt 1) { Write-AcLog (T 'log.wingetIdGone' @($pkg)) 'WARN'; continue }
        Write-AcLog (T 'log.wingetExit' @($lastCode, $Name)) 'WARN'
        return $lastCode
    }
    return $lastCode
}


# ---------------------------------------------------------------------
#  Direkte Downloads - Ersatz fuer winget
#
#  winget bleibt der bevorzugte Weg, ist aber keine Voraussetzung mehr:
#  Fehlt es oder schlaegt ein Paket fehl, werden die Werkzeuge direkt von
#  ihren Originalquellen geladen. Git und CMake landen dabei portabel im
#  Serverordner, OpenSSL ebenso - nur die Build Tools installiert Microsoft
#  systemweit, das laesst sich nicht vermeiden.
# ---------------------------------------------------------------------

function Get-AcGitHubAssetUrl {
    <#
      Sucht in der neuesten Version eines GitHub-Projekts die erste Datei,
      deren Name zum Muster passt.
    #>
    param([string]$Repo, [string]$Pattern)
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    $rel = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = $script:AcUserAgent } -TimeoutSec 30
    foreach ($a in @($rel.assets)) {
        if ($a.name -like $Pattern) { return $a.browser_download_url }
    }
    throw (T 'log.noAssetFound' @($Repo, $Pattern))
}

function Add-AcToolPaths {
    # Portabel installierte Werkzeuge fuer diesen Prozess auffindbar machen
    param($Paths)
    $extra = @()
    foreach ($sub in @('PortableGit\cmd', 'cmake\bin')) {
        $p = Join-Path $Paths.Deps $sub
        if (Test-Path $p) { $extra += $p }
    }
    if ($extra.Count -gt 0) {
        $script:AcExtraPaths = ($extra -join ';')
        Set-AcPathEntries @($script:AcExtraPaths, $env:Path)
    }
}

function Install-AcGitDirect {
    # PortableGit: selbstentpackendes Archiv, entpackt nach deps\PortableGit
    param($Paths)
    $target = Join-Path $Paths.Deps 'PortableGit'
    if (Test-Path (Join-Path $target 'cmd\git.exe')) { Add-AcToolPaths $Paths; return $true }
    Write-AcLog (T 'log.directDownload' @('Git'))
    $url = Get-AcGitHubAssetUrl 'git-for-windows/git' 'PortableGit-*-64-bit.7z.exe'
    $file = Join-Path $Paths.Downloads (Split-Path $url -Leaf)
    Invoke-AcDownload -Urls @($url) -OutFile $file -Description 'Git (portable)'
    Set-AcProgress -1 (T 'log.extractingShort' @((Split-Path $file -Leaf)))
    # 7-Zip-SFX: -o Zielordner, -y alles bestaetigen
    Invoke-AcProcess -FilePath $file -ArgumentList "-o`"$target`" -y" -TimeoutSeconds 900 | Out-Null
    Add-AcToolPaths $Paths
    return (Test-Path (Join-Path $target 'cmd\git.exe'))
}

function Install-AcCMakeDirect {
    # CMake als ZIP nach deps\cmake
    param($Paths)
    $target = Join-Path $Paths.Deps 'cmake'
    if (Test-Path (Join-Path $target 'bin\cmake.exe')) { Add-AcToolPaths $Paths; return $true }
    Write-AcLog (T 'log.directDownload' @('CMake'))
    $url = Get-AcGitHubAssetUrl 'Kitware/CMake' 'cmake-*-windows-x86_64.zip'
    $file = Join-Path $Paths.Downloads (Split-Path $url -Leaf)
    Invoke-AcDownload -Urls @($url) -OutFile $file -Description 'CMake'
    Expand-AcZip -ZipPath $file -Destination $target -StripTopLevel
    Add-AcToolPaths $Paths
    return (Test-Path (Join-Path $target 'bin\cmake.exe'))
}

function Get-AcOpenSslDownloadUrl {
    <#
      Die Dateinamen bei Shining Light enthalten die Version, deshalb wird die
      Downloadseite gelesen. Gesucht wird die 64-Bit-Vollversion der 3.x-Reihe -
      ausdruecklich nicht "Light", die enthaelt keine Header und keine .lib-Dateien.
    #>
    $page = 'https://slproweb.com/products/Win32OpenSSL.html'
    $wc = New-Object Net.WebClient
    Set-AcWebHeaders $wc $page
    $html = $wc.DownloadString($page)
    $hits = [regex]::Matches($html, '(?i)href="(/download/Win64OpenSSL-3_\d+_\d+[a-z]?\.(?:exe|msi))"')
    $urls = New-Object Collections.Generic.List[string]
    foreach ($m in $hits) {
        $rel = $m.Groups[1].Value
        if ($rel -match 'Light') { continue }
        $urls.Add('https://slproweb.com' + $rel)
    }
    if ($urls.Count -eq 0) { throw (T 'log.opensslNoUrl') }
    # neueste Version zuerst
    return @($urls | Sort-Object -Descending -Unique)
}

function Install-AcOpenSslDirect {
    # OpenSSL-Vollversion nach deps\openssl (Inno-Setup-Installer, still)
    param($Paths)
    $target = Join-Path $Paths.Deps 'openssl'
    if (Test-AcOpenSslDir $target) { return $target }
    Write-AcLog (T 'log.directDownload' @('OpenSSL'))
    $urls = @(Get-AcOpenSslDownloadUrl)
    $file = Join-Path $Paths.Downloads (Split-Path $urls[0] -Leaf)
    Invoke-AcDownload -Urls $urls -OutFile $file -Description 'OpenSSL'
    Set-AcProgress -1 (T 'log.installing' @('OpenSSL'))
    if ($file -like '*.msi') {
        Invoke-AcProcess -FilePath 'msiexec.exe' -ArgumentList "/i `"$file`" /qn INSTALLDIR=`"$target`"" -TimeoutSeconds 1800 | Out-Null
    } else {
        Invoke-AcProcess -FilePath $file -ArgumentList "/VERYSILENT /SP- /SUPPRESSMSGBOXES /NORESTART /DIR=`"$target`"" -TimeoutSeconds 1800 | Out-Null
    }
    if (Test-AcOpenSslDir $target) { return $target }
    return $null
}

function Install-AcVCRedistDirect {
    param($Paths)
    Write-AcLog (T 'log.directDownload' @('Visual C++ Redistributable'))
    $file = Join-Path $Paths.Downloads 'vc_redist.x64.exe'
    Invoke-AcDownload -Urls @('https://aka.ms/vs/17/release/vc_redist.x64.exe') -OutFile $file -Description 'VC++ Redistributable'
    # 1638 = bereits in gleicher oder neuerer Version vorhanden
    $code = Invoke-AcProcess -FilePath $file -ArgumentList '/install /quiet /norestart' -AllowFailure -TimeoutSeconds 1800
    return ($code -eq 0 -or $code -eq 1638 -or $code -eq 3010)
}

function Install-AcVsBuildToolsDirect {
    # Microsofts Bootstrapper - installiert immer systemweit
    param($Paths)
    Write-AcLog (T 'log.directDownload' @('Visual Studio 2022 Build Tools'))
    $file = Join-Path $Paths.Downloads 'vs_BuildTools.exe'
    Invoke-AcDownload -Urls @('https://aka.ms/vs/17/release/vs_BuildTools.exe') -OutFile $file -Description 'VS Build Tools'
    Set-AcProgress -1 (T 'ins.log.vsInstall')
    $args = '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    Invoke-AcProcess -FilePath $file -ArgumentList $args -AllowFailure -TimeoutSeconds 7200 | Out-Null
    return [bool](Find-AcVisualStudio)
}

function Install-AcOpenSsl {
    # Installiert die OpenSSL-Vollversion. AzerothCore ist auf die 3.x-Reihe ausgelegt,
    # winget liefert aber inzwischen 4.x als neueste Version -> falls vorhanden gezielt die
    # neueste 3.x installieren, sonst die neueste verfuegbare.
    $winget = Find-AcWinget
    if (-not $winget) { throw (T 'log.wingetMissing') }
    foreach ($pkg in @($script:AcWingetPackages.OpenSSL)) {
        if (-not (Test-AcWingetPackageExists $winget $pkg)) { Write-AcLog (T 'log.wingetUnknown' @($pkg)) 'WARN'; continue }
        $version = ''
        $v3 = @(Get-AcWingetVersions $winget $pkg | Where-Object { $_ -match '^3\.' } | Sort-Object { [Version]($_ -replace '^(\d+\.\d+\.\d+).*$', '$1') } -Descending)
        if ($v3.Count -gt 0) { $version = $v3[0]; Write-AcLog (T 'log.opensslPick' @($version)) }
        else { Write-AcLog (T 'log.opensslNo3') 'WARN' }
        Install-AcWingetPackage @($pkg) 'OpenSSL (Vollversion)' '' $version | Out-Null
        if (Find-AcOpenSsl) { return $true }
    }
    return [bool](Find-AcOpenSsl)
}

# ---------------------------------------------------------------------
#  Konfigurationsdateien (*.conf)
# ---------------------------------------------------------------------
function Format-AcConfValue {
    param([string]$Value)
    if ($Value -match '^-?\d+(\.\d+)?$') { return $Value }
    if ($Value.StartsWith('"') -and $Value.EndsWith('"')) { return $Value }
    return '"' + $Value + '"'
}

function Set-AcConfValue {
    param([string]$File, [string]$Key, [string]$Value)
    if (-not (Test-Path $File)) { throw (T 'log.confMissing' @($File)) }
    $content = [IO.File]::ReadAllText($File)
    $formatted = Format-AcConfValue $Value
    $pattern = '(?m)^(\s*' + [regex]::Escape($Key) + '\s*=\s*).*$'
    $rx = New-Object Text.RegularExpressions.Regex($pattern)
    if ($rx.IsMatch($content)) {
        $replacement = '${1}' + ($formatted -replace '\$', '$$$$')
        $content = $rx.Replace($content, $replacement, 1)
    } else {
        if (-not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "$Key = $formatted`r`n"
    }
    [IO.File]::WriteAllText($File, $content, (New-Object Text.UTF8Encoding($false)))
}

function Get-AcConfEntries {
    # Liefert Liste von @{Key;Value;Line;Description}
    param([string]$File)
    $lines = [IO.File]::ReadAllLines($File)
    $entries = New-Object Collections.Generic.List[object]
    $desc = New-Object Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*#') { $desc.Add(($l -replace '^\s*#\s?', '')); continue }
        if ($l.Trim() -eq '' -or $l -match '^\s*\[') { $desc.Clear(); continue }
        if ($l -match '^\s*([A-Za-z0-9_.\-]+)\s*=\s*(.*?)\s*$') {
            $val = $Matches[2]
            if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length - 2) }
            $entries.Add(@{ Key = $Matches[1]; Value = $val; Line = $i; Description = ($desc -join "`r`n") })
            $desc.Clear()
        }
    }
    return $entries
}

function Copy-AcDistConfigs {
    # *.conf.dist -> *.conf (nur wenn .conf noch fehlt), fuer Core und Module
    param($Paths)
    $count = 0
    foreach ($dir in @($Paths.Configs, $Paths.ModConfigs)) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($dist in (Get-ChildItem $dir -Filter '*.conf.dist' -File)) {
            $target = Join-Path $dir ($dist.Name -replace '\.dist$', '')
            if (-not (Test-Path $target)) { Copy-Item $dist.FullName $target; $count++; Write-AcLog (T 'log.confCreated' @((Split-Path $target -Leaf))) }
        }
    }
    return $count
}

function Get-AcDbInfo {
    param($Settings, [string]$Database)
    return "127.0.0.1;{0};{1};{2};{3}" -f $Settings.MySqlPort, $Settings.DbUser, $Settings.DbPassword, $Database
}

function Set-AcServerConfigs {
    # Traegt Datenbank, Pfade und Updater-Einstellungen in die Konfigurationen ein
    param($Paths, $Settings)
    $mysqlExe = ConvertTo-AcSlashPath (Join-Path $Paths.MySql 'bin\mysql.exe')
    $world = Join-Path $Paths.Configs 'worldserver.conf'
    $auth  = Join-Path $Paths.Configs 'authserver.conf'
    $dbi   = Join-Path $Paths.Configs 'dbimport.conf'
    foreach ($f in @($world, $auth, $dbi)) {
        if (-not (Test-Path $f)) { continue }
        Set-AcConfValue $f 'LoginDatabaseInfo' (Get-AcDbInfo $Settings 'acore_auth')
        Set-AcConfValue $f 'LogsDir' (ConvertTo-AcSlashPath $Paths.Logs)
        Set-AcConfValue $f 'MySQLExecutable' $mysqlExe
    }
    foreach ($f in @($world, $dbi)) {
        if (-not (Test-Path $f)) { continue }
        Set-AcConfValue $f 'WorldDatabaseInfo'     (Get-AcDbInfo $Settings 'acore_world')
        Set-AcConfValue $f 'CharacterDatabaseInfo' (Get-AcDbInfo $Settings 'acore_characters')
        Set-AcConfValue $f 'Updates.EnableDatabases' '7'
        Set-AcConfValue $f 'Updates.AutoSetup' '1'
    }
    if (Test-Path $world) {
        Set-AcConfValue $world 'DataDir' (ConvertTo-AcSlashPath $Paths.Data)
        Set-AcConfValue $world 'Console.Enable' '1'
    }
    $pb = Join-Path $Paths.ModConfigs 'playerbots.conf'
    if (Test-Path $pb) {
        Set-AcConfValue $pb 'PlayerbotsDatabaseInfo' (Get-AcDbInfo $Settings 'acore_playerbots')
        Set-AcConfValue $pb 'Playerbot.Updates.EnableDatabases' '1'
    }
}

# ---------------------------------------------------------------------
#  Git
# ---------------------------------------------------------------------
function Get-AcGitRepos {
    # Core + alle Module mit .git
    param($Paths)
    $list = New-Object Collections.Generic.List[object]
    if (Test-Path (Join-Path $Paths.Source '.git')) { $list.Add(@{ Name = 'AzerothCore (Core)'; Path = $Paths.Source }) }
    if (Test-Path $Paths.Modules) {
        foreach ($d in (Get-ChildItem $Paths.Modules -Directory)) {
            if (Test-Path (Join-Path $d.FullName '.git')) { $list.Add(@{ Name = $d.Name; Path = $d.FullName }) }
        }
    }
    return $list
}

function Get-AcRepoStatus {
    # @{Local; Remote; Behind; Branch}
    param([string]$Git, [string]$RepoPath, [switch]$Fetch)
    if ($Fetch) { Invoke-AcCapture $Git 'fetch --quiet' $RepoPath | Out-Null }
    $branch = (Invoke-AcCapture $Git 'rev-parse --abbrev-ref HEAD' $RepoPath).Output
    $local  = (Invoke-AcCapture $Git 'rev-parse --short HEAD' $RepoPath).Output
    $remote = (Invoke-AcCapture $Git 'rev-parse --short @{u}' $RepoPath).Output
    $behind = (Invoke-AcCapture $Git 'rev-list --count HEAD..@{u}' $RepoPath).Output
    $b = 0; [void][int]::TryParse($behind, [ref]$b)
    return @{ Branch = $branch; Local = $local; Remote = $remote; Behind = $b }
}

# ---------------------------------------------------------------------
#  Build (CMake + MSBuild) und Nachbereitung
# ---------------------------------------------------------------------

$script:AcBuildProfiles = @{
    full       = @{ Share = 1.0;  Priority = 'Normal' }
    balanced   = @{ Share = 0.75; Priority = 'BelowNormal' }
    background = @{ Share = 0.5;  Priority = 'Idle' }
}

function Get-AcBuildProfile {
    <#
      Wie viele Uebersetzungsvorgaenge parallel laufen duerfen und mit welcher
      Prioritaet. Weniger Kerne = laengere Bauzeit, aber der Rechner bleibt nutzbar.
    #>
    param($Settings)
    $key = 'full'
    if ($Settings -and $Settings.BuildProfile) { $key = [string]$Settings.BuildProfile }
    if (-not $script:AcBuildProfiles.ContainsKey($key)) { $key = 'full' }
    $prof = $script:AcBuildProfiles[$key]
    $cores = [Environment]::ProcessorCount
    $jobs = [Math]::Max(1, [int][Math]::Round($cores * $prof.Share))
    return @{ Key = $key; Jobs = $jobs; Cores = $cores; Priority = $prof.Priority }
}

function Invoke-AcConfigure {
    param($Paths, $Settings)
    $cmake = Find-AcCMake
    if (-not $cmake) { throw (T 'log.notFound' @('CMake')) }
    $boost = $Settings.BoostRoot; if (-not $boost) { $boost = Find-AcBoost $Paths.Deps }
    $ssl   = $Settings.OpenSslRoot; if (-not $ssl) { $ssl = Find-AcOpenSsl }
    if (-not $boost) { throw (T 'log.notFound' @('Boost')) }
    if (-not $ssl)   { throw (T 'log.notFound' @('OpenSSL')) }
    $boostS = ConvertTo-AcSlashPath $boost
    $mysqlS = ConvertTo-AcSlashPath $Paths.MySql
    $cmakeArgs = @(
        "-S `"$($Paths.Source)`"", "-B `"$($Paths.Build)`"",
        "-G `"$($script:AcVersions.VsGenerator)`"", "-A x64",
        "-DTOOLS_BUILD=db-only", "-DSCRIPTS=static", "-DMODULES=static", "-DWITH_WARNINGS=0",
        "-DBOOST_ROOT=`"$boostS`"", "-DBOOST_LIBRARYDIR=`"$boostS/lib64-msvc-$($script:AcVersions.BoostToolset)`"",
        "-DMYSQL_INCLUDE_DIR=`"$mysqlS/include`"", "-DMYSQL_LIBRARY=`"$mysqlS/lib/libmysql.lib`"",
        "-DOPENSSL_ROOT_DIR=`"$(ConvertTo-AcSlashPath $ssl)`""
    )
    # mod-ale erwartet die Lua-Variante als CMake-Schalter (luajit, lua52, lua53, lua54)
    if (Get-AcElunaModuleName $Paths) {
        $luaVer = 'lua52'   # viele Skripte nutzen math.pow, ab Lua 5.3 entfernt
        if ($Settings.LuaVersion) { $luaVer = [string]$Settings.LuaVersion }
        $cmakeArgs += "-DLUA_VERSION=$luaVer"
    }
    $cmakeArgs = $cmakeArgs -join ' '
    Set-AcProgress -1 (T 'log.cmakeConfigure')
    Invoke-AcProcess -FilePath $cmake -ArgumentList $cmakeArgs -WorkingDirectory $Paths.Root | Out-Null
}

function Invoke-AcBuild {
    param($Paths, $Settings)
    $cmake = Find-AcCMake
    Set-AcProgress -1 (T 'log.building')
    # zusaetzlich zwei MSBuild-Protokolle: vollstaendig und nur Fehler
    if (-not (Test-Path $Paths.Logs)) { New-Item -ItemType Directory -Path $Paths.Logs | Out-Null }
    $fullLog = Join-Path $Paths.Logs 'build.log'
    $errLog  = Join-Path $Paths.Logs 'build-errors.log'
    foreach ($f in @($fullLog, $errLog)) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    $bp = Get-AcBuildProfile $Settings
    Write-AcLog (T 'log.buildProfile' @($bp.Jobs, $bp.Cores, $bp.Priority))
    $buildArgs = "--build `"$($Paths.Build)`" --config $($script:AcVersions.BuildConfig) -- /m:$($bp.Jobs) /nologo /v:minimal" +
                 " /fl /flp:logfile=`"$fullLog`";verbosity=normal" +
                 " /fl1 /flp1:logfile=`"$errLog`";errorsonly`;verbosity=quiet"
    Invoke-AcProcess -FilePath $cmake -ArgumentList $buildArgs -WorkingDirectory $Paths.Root -Priority $bp.Priority | Out-Null
    Invoke-AcPostBuild $Paths $Settings
}

function Copy-AcRuntimeDlls {
    # Laufzeit-DLLs neben die Server-Binaries legen:
    #   libmysql.dll                       (MySQL-Client)
    #   libcrypto-3-x64.dll, libssl-3-x64.dll  (OpenSSL)
    #   legacy.dll                         (OpenSSL Legacy-Provider, liegt in lib\ossl-modules\ - AzerothCore
    #                                       bricht ohne diese Datei mit "Not found 'legacy.dll'" ab)
    param($Paths, $Settings)
    if (-not (Test-Path $Paths.Bin)) { return }
    $dll = Join-Path $Paths.MySql 'lib\libmysql.dll'
    if (Test-Path $dll) { Copy-Item $dll $Paths.Bin -Force }
    $ssl = $Settings.OpenSslRoot; if (-not $ssl -or -not (Test-AcOpenSslDir $ssl)) { $ssl = Find-AcOpenSsl }
    if (-not $ssl) { Write-AcLog (T 'log.opensslDirMissing') 'WARN'; return }
    $copied = @()
    foreach ($pattern in @('libcrypto*.dll', 'libssl*.dll', 'legacy.dll')) {
        $files = @(Get-ChildItem $ssl -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(x86|Win32|debug)\\' })
        # 64-Bit-Variante bevorzugen (Ordnername oder Dateiname enthaelt x64), sonst erste Fundstelle
        $pick = @($files | Where-Object { $_.FullName -match 'x64|win64' }) + $files | Select-Object -First 1
        if ($pick) { Copy-Item $pick.FullName $Paths.Bin -Force; $copied += $pick.Name }
    }
    if ($copied -notcontains 'legacy.dll') {
        throw (T 'log.legacyMissing' @($ssl))
    }
    Write-AcLog (T 'log.dllsCopied' @(($copied -join ', ')))
}

function Invoke-AcPostBuild {
    # DLLs kopieren, Konfigurationen anlegen/aktualisieren
    param($Paths, $Settings)
    if (-not (Test-Path (Join-Path $Paths.Bin 'worldserver.exe'))) { throw (T 'log.noWorldserver') }
    Copy-AcRuntimeDlls $Paths $Settings
    foreach ($d in @($Paths.Logs, $Paths.Data)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    Copy-AcDistConfigs $Paths | Out-Null
    Set-AcServerConfigs $Paths $Settings
}



function Remove-AcInstallLeftovers {
    <#
      Raeumt nach erfolgreicher Installation auf:
        - Temporaere Entpack-Ordner (_extract_*, _zip_*)
        - Heruntergeladene Installationspakete in deps\downloads (Boost-Installer, MySQL-ZIP, Client-Daten-ZIP)
        - leere Ordner unterhalb des Serverordners (ausser denen, die der Server braucht)
      Quellcode, Build-Ordner und MySQL-Daten werden nicht angefasst.
    #>
    param($Paths, [switch]$KeepDownloads)
    $removed = 0
    # 1) Reste abgebrochener Entpackvorgaenge
    foreach ($dir in @($Paths.Root, $Paths.Deps, $Paths.Data, $Paths.MySql, $Paths.Modules)) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($t in (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_extract_*' -or $_.Name -like '_zip_*' })) {
            try { Remove-Item $t.FullName -Recurse -Force; $removed++; Write-AcLog (T 'log.cleanupRemoved' @($t.FullName)) } catch {}
        }
    }
    # 2) Downloads (nur Installationspakete - alles davon laesst sich erneut laden)
    if (-not $KeepDownloads -and (Test-Path $Paths.Downloads)) {
        $size = 0
        foreach ($f in (Get-ChildItem $Paths.Downloads -File -ErrorAction SilentlyContinue)) { $size += $f.Length; try { Remove-Item $f.FullName -Force; $removed++ } catch {} }
        if ($size -gt 0) { Write-AcLog (T 'log.cleanupDownloads' @([int]($size / 1MB))) }
    }
    # 3) leere Ordner - nur dort, wo der Installer selbst welche hinterlassen kann
    $keep = @($Paths.Root, $Paths.Logs, $Paths.Data, $Paths.Modules, $Paths.ModConfigs, $Paths.Tools, $Paths.Deps) | ForEach-Object { $_.ToLower().TrimEnd('\') }
    # deps enthaelt Boost sowie ggf. portables Git/CMake/OpenSSL - nur leere Ordner
    # werden entfernt, die Werkzeuge selbst bleiben
    $scan = @($Paths.Deps, $Paths.Data, $Paths.Tools, $Paths.Logs)
    foreach ($base in $scan) {
        if (-not (Test-Path $base)) { continue }
        # tiefste Ordner zuerst, damit Eltern danach ebenfalls leer sein koennen
        $dirs = @(Get-ChildItem $base -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($dd in $dirs) {
            if ($keep -contains $dd.FullName.ToLower().TrimEnd('\')) { continue }
            if (-not (Get-ChildItem $dd.FullName -Force -ErrorAction SilentlyContinue)) {
                try { Remove-Item $dd.FullName -Force; $removed++; Write-AcLog (T 'log.cleanupRemoved' @($dd.FullName)) } catch {}
            }
        }
    }
    # leere Ordner direkt im Serverordner (z.B. ein leeres deps\downloads)
    foreach ($dd in (Get-ChildItem $Paths.Root -Directory -ErrorAction SilentlyContinue)) {
        if ($keep -contains $dd.FullName.ToLower().TrimEnd('\')) { continue }
        if (-not (Get-ChildItem $dd.FullName -Force -ErrorAction SilentlyContinue)) { try { Remove-Item $dd.FullName -Force; $removed++ } catch {} }
    }
    Write-AcLog (T 'log.cleanupDone' @($removed))
    return $removed
}


function Update-AcSubmodules {
    <#
      Holt fehlende Git-Submodule eines Repositories nach. Ohne sie fehlen z.B.
      bei mod-eluna die Lua-Quellen und der Build bricht mit "lua.h not found" ab.
      Rueckgabe: $true, wenn etwas geholt wurde.
    #>
    param([string]$RepoPath)
    if (-not (Test-Path (Join-Path $RepoPath '.gitmodules'))) { return $false }
    $git = Find-AcGit
    if (-not $git) { return $false }
    Write-AcLog (T 'log.submodules' @((Split-Path $RepoPath -Leaf)))
    $r = Invoke-AcCapture $git 'submodule update --init --recursive' $RepoPath
    if ($r.ExitCode -ne 0) { Write-AcLog (T 'log.submodulesFailed' @((Split-Path $RepoPath -Leaf), $r.Error)) 'WARN'; return $false }
    return $true
}

function Update-AcAllSubmodules {
    # Core und alle Module pruefen
    param($Paths)
    $n = 0
    if (Test-Path (Join-Path $Paths.Source '.git')) { if (Update-AcSubmodules $Paths.Source) { $n++ } }
    if (Test-Path $Paths.Modules) {
        foreach ($m in (Get-ChildItem $Paths.Modules -Directory)) {
            if ($m.Name -like '_*') { continue }
            if (Update-AcSubmodules $m.FullName) { $n++ }
        }
    }
    return $n
}

function Get-AcModuleNames {
    param($Paths)
    if (-not (Test-Path $Paths.Modules)) { return @() }
    return @(Get-ChildItem $Paths.Modules -Directory | Where-Object { $_.Name -notlike '_*' } | ForEach-Object { $_.Name })
}

function Save-AcBuiltModules {
    # Nach einem erfolgreichen Build festhalten, welche Module tatsaechlich einkompiliert wurden
    param($Paths, $Settings)
    $Settings.BuiltModules = @(Get-AcModuleNames $Paths)
    $Settings.NeedsRebuild = $false
    Save-AcSettings $Paths.Root $Settings
}

function Test-AcModuleBuilt {
    param($Settings, [string]$Name)
    return (@($Settings.BuiltModules | Where-Object { $_ }) -contains $Name)
}




function Get-AcModuleBaseSqlFiles {
    # SQL-Dateien eines Moduls, die im base-Ordner liegen (Tabellen anlegen)
    param([string]$ModulePath)
    $result = New-Object Collections.Generic.List[object]
    foreach ($f in (Get-AcModuleSqlFiles $ModulePath)) {
        if ($f.Rel -match '(^|/)base(/|$)' -and $f.Db) { $result.Add($f) }
    }
    return $result
}

function Import-AcModuleBaseSql {
    <#
      Spielt die base-Dateien eines Moduls direkt ein. Noetig, wenn ein Modul zu einer
      bereits bestehenden Datenbank hinzukommt: AzerothCore fuehrt base-Dateien nur bei
      leerer Datenbank aus, die updates-Dateien laufen aber trotzdem und scheitern dann.
    #>
    param($Paths, [string]$ModulePath)
    $files = @(Get-AcModuleBaseSqlFiles $ModulePath)
    $done = 0
    foreach ($f in $files) {
        $db = $script:AcSqlDatabase[$f.Db]
        if (-not $db) { continue }
        Invoke-AcSqlFile $Paths $f.Full $db
        $done++
    }
    return $done
}

function Get-AcDbErrors {
    <#
      Fehler des letzten dbimport-Laufs: zuerst aus logs\DBErrors.log (dort schreibt der
      Core die fehlgeschlagene SQL-Anweisung mit), sonst die passenden Zeilen aus dem
      Manager-Protokoll.
    #>
    param($Paths, [int]$Max = 15)
    $lines = @()   # einfaches Feld statt .NET-Liste
    $dbLog = Join-Path $Paths.Logs 'DBErrors.log'
    if (Test-Path $dbLog) {
        try {
            $tail = @(Get-Content $dbLog -Tail 60 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
            foreach ($l in ($tail | Select-Object -Last $Max)) { $lines.Add($l.Trim()) }
        } catch {}
    }
    if ($lines.Count -eq 0 -and $script:AcLogFile -and (Test-Path $script:AcLogFile)) {
        try {
            $tail = @(Get-Content $script:AcLogFile -Tail 400 -ErrorAction SilentlyContinue |
                      Where-Object { $_ -match 'ERROR \d+|Applying of file|Applying update|does\S*n.t exist|Could not update|failed!' } |
                      Where-Object { $_ -notmatch 'MySQL (client|server)|Connected to MySQL' })
            foreach ($l in ($tail | Select-Object -Last $Max)) { $lines.Add(($l -replace '^\[[^\]]+\]\s*\[[^\]]+\]\s*', '').Trim()) }
        } catch {}
    }
    return $lines
}


function Get-AcMissingIncludes {
    <#
      Wertet Compilerfehler C1083 aus (fehlende Include-Datei) und sucht die
      Datei im Quellbaum. So laesst sich unterscheiden, ob sie ganz fehlt
      (Modul unvollstaendig oder Begleitmodul noetig) oder nur nicht gefunden wird.
      Rueckgabe: Feld aus @{ Header; FoundIn }
    #>
    param($Paths, [string[]]$ErrorLines)
    $seen = @{}
    $result = @()
    foreach ($line in @($ErrorLines)) {
        # deutsche und englische Fassung der Meldung
        $m = [regex]::Match([string]$line, '(?:kann nicht geoeffnet werden|kann nicht ge.ffnet werden|[Cc]annot open (?:include )?file):\s*[""'']([^""'']+)[""'']')
        if (-not $m.Success) { continue }
        $header = [string]$m.Groups[1].Value
        if ($seen.ContainsKey($header)) { continue }
        $seen[$header] = $true
        $found = @()
        try {
            $leaf = Split-Path $header -Leaf
            $hits = @(Get-ChildItem -LiteralPath $Paths.Source -Filter $leaf -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 3)
            foreach ($h in $hits) { $found += ,([string]$h.FullName) }
        } catch {}
        $result += ,@{ Header = $header; FoundIn = $found }
    }
    return $result
}

function Get-AcBuildErrors {
    <#
      Liest die Fehlerzeilen des letzten Builds. Erst aus build-errors.log (von MSBuild),
      ersatzweise aus build.log per Mustersuche.
    #>
    param($Paths, [int]$Max = 12)
    $errLog = Join-Path $Paths.Logs 'build-errors.log'
    $lines = @()
    if (Test-Path $errLog) {
        $lines = @(Get-Content $errLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
    }
    if ($lines.Count -eq 0) {
        $fullLog = Join-Path $Paths.Logs 'build.log'
        if (Test-Path $fullLog) {
            $lines = @(Select-String -Path $fullLog -Pattern 'error (C|LNK|MSB|RC)\d+|: error' -ErrorAction SilentlyContinue |
                       ForEach-Object { $_.Line.Trim() })
        }
    }
    # Doppelte Meldungen (parallele Builds melden mehrfach) zusammenfassen
    $seen = New-Object Collections.Generic.List[string]
    foreach ($l in $lines) { if (-not $seen.Contains($l)) { $seen.Add($l) } }
    return @($seen | Select-Object -First $Max)
}

function Get-AcModuleFromError {
    # Rueckschluss vom Dateipfad in der Fehlermeldung auf das verursachende Modul
    param($Paths, [string[]]$ErrorLines)
    $mods = @(Get-AcModuleNames $Paths)
    $hits = New-Object Collections.Generic.List[string]
    foreach ($l in $ErrorLines) {
        foreach ($m in $mods) {
            if ($l -match [regex]::Escape("modules\$m\") -and -not $hits.Contains($m)) { $hits.Add($m) }
        }
    }
    return $hits.ToArray()
}

function Invoke-AcDbImport {
    param($Paths, $Settings = $null)
    $exe = Join-Path $Paths.Bin 'dbimport.exe'
    if (-not (Test-Path $exe)) { throw (T 'log.noDbimport') }
    if (-not $Settings) { $Settings = Get-AcSettings $Paths.Root }
    if (-not (Test-Path (Join-Path $Paths.Bin 'legacy.dll'))) { Copy-AcRuntimeDlls $Paths $Settings }
    Set-AcProgress -1 (T 'log.dbimport')
    Invoke-AcProcess -FilePath $exe -ArgumentList '' -WorkingDirectory $Paths.Bin | Out-Null
}

# ---------------------------------------------------------------------
#  MySQL (portabel im Serverordner)
# ---------------------------------------------------------------------
function Get-AcMySqlExe  { param($Paths, [string]$Name) return (Join-Path $Paths.MySql "bin\$Name") }


function Test-AcUrl {
    <#
      Prueft still, ob eine Adresse wirklich Daten liefert. Bewusst ein echter
      Teildownload (erste Bytes) statt HEAD: Oracle beantwortet HEAD mit 200 und
      die eigentliche Datei trotzdem mit 403, wenn der Herkunftsverweis fehlt.
    #>
    param([string]$Url, [int]$TimeoutMs = 12000)
    try {
        $req = [Net.WebRequest]::Create($Url)
        $req.Method = 'GET'
        $req.UserAgent = $script:AcUserAgent
        $req.Accept = '*/*'
        $req.Timeout = $TimeoutMs
        $req.ReadWriteTimeout = $TimeoutMs
        $req.AllowAutoRedirect = $true
        $ref = Get-AcReferer $Url
        if ($ref) { $req.Referer = $ref }
        $req.AddRange(0, 2047)
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $buf = New-Object byte[] 512
        $read = $stream.Read($buf, 0, $buf.Length)
        $stream.Close(); $resp.Close()
        return ($read -gt 0)
    } catch { return $false }
}

function Select-AcWorkingUrls {
    # Liefert nur die Adressen, die tatsaechlich antworten (hoechstens $Max Stueck)
    param([string[]]$Urls, [int]$Max = 3, [string]$Description = '')
    $ok = New-Object Collections.Generic.List[string]
    $tried = 0
    foreach ($u in $Urls) {
        $tried++
        Set-AcProgress -1 (T 'log.probing' @($Description, $tried, $Urls.Count))
        Invoke-AcDoEvents
        if (Test-AcUrl $u) { $ok.Add($u); if ($ok.Count -ge $Max) { break } }
    }
    if ($ok.Count -eq 0) { return $Urls }   # nichts erreichbar - trotzdem versuchen
    return $ok.ToArray()
}

function Get-AcMySqlDownloadUrls {
    # Ermittelt die aktuelle 8.4.x-Version von der MySQL-Downloadseite und baut alle bekannten
    # Download-Pfade; als Rueckfall die fest hinterlegte Versionsliste.
    $versions = New-Object Collections.Generic.List[string]
    try {
        $wc = New-Object Net.WebClient
        Set-AcWebHeaders $wc 'https://dev.mysql.com/downloads/mysql/8.4.html'
        $html = $wc.DownloadString('https://dev.mysql.com/downloads/mysql/8.4.html')
        foreach ($m in [regex]::Matches($html, 'mysql-(8\.4\.\d+)-winx64\.zip')) { if (-not $versions.Contains($m.Groups[1].Value)) { $versions.Add($m.Groups[1].Value) } }
        if ($versions.Count -gt 0) { Write-AcLog (T 'log.mysqlLatest' @($versions[0])) }
    } catch { Write-AcLog (T 'log.mysqlPageFail' @($_.Exception.Message)) }
    foreach ($v in @($script:AcVersions.MySqlFallbacks)) { if (-not $versions.Contains($v)) { $versions.Add($v) } }
    $urls = New-Object Collections.Generic.List[string]
    foreach ($ver in $versions) {
        $major = ($ver -split '\.')[0..1] -join '.'
        $file = "mysql-$ver-winx64.zip"
        $urls.Add("https://cdn.mysql.com//Downloads/MySQL-$major/$file")
        $urls.Add("https://dev.mysql.com/get/Downloads/MySQL-$major/$file")
        $urls.Add("https://downloads.mysql.com/archives/get/p/23/file/$file")
    }
    # erreichbare Adressen vorab ermitteln, damit nicht jede veraltete Version
    # als fehlgeschlagener Download im Protokoll auftaucht
    $working = @(Select-AcWorkingUrls $urls.ToArray() 3 'MySQL')
    Write-AcLog (T 'log.urlChosen' @('MySQL', $working[0]))
    return $working
}

function Install-AcMySqlViaWinget {
    # Rueckfall: MySQL Server per winget (MSI nach Program Files) installieren und die
    # benoetigten Dateien in den portablen Serverordner kopieren.
    param($Paths)
    $winget = Find-AcWinget
    if (-not $winget) { return $false }
    Write-AcLog (T 'log.mysqlWinget')
    Install-AcWingetPackage @('Oracle.MySQL') 'MySQL Server' | Out-Null
    $cands = @()
    foreach ($base in @("$env:ProgramFiles\MySQL", "${env:ProgramFiles(x86)}\MySQL")) {
        if (Test-Path $base) { $cands += Get-ChildItem $base -Directory -Filter 'MySQL Server*' | Sort-Object Name -Descending | ForEach-Object { $_.FullName } }
    }
    foreach ($dir in $cands) {
        if (-not (Test-Path (Join-Path $dir 'bin\mysqld.exe'))) { continue }
        if (-not (Test-Path (Join-Path $dir 'lib\libmysql.lib'))) { Write-AcLog (T 'log.mysqlNoDev' @($dir)) 'WARN'; continue }
        Write-AcLog (T 'log.mysqlCopy' @($dir, $Paths.MySql))
        if (-not (Test-Path $Paths.MySql)) { New-Item -ItemType Directory -Path $Paths.MySql | Out-Null }
        foreach ($sub in @('bin', 'lib', 'include', 'share')) {
            $src = Join-Path $dir $sub
            if (Test-Path $src) { Copy-Item $src (Join-Path $Paths.MySql $sub) -Recurse -Force }
        }
        return $true
    }
    return $false
}

function Write-AcMySqlClientCnf {
    param($Paths, [string]$Password, [int]$Port)
    $cnf = "[client]`r`nuser=root`r`npassword=$Password`r`nhost=127.0.0.1`r`nport=$Port`r`n"
    [IO.File]::WriteAllText($Paths.MySqlCnf, $cnf, (New-Object Text.UTF8Encoding($false)))
}

function Test-AcMySqlPortOpen {
    <#
      Sehr schneller Test (wenige Millisekunden): Nimmt jemand auf dem MySQL-Port
      Verbindungen an? Spart den Start von mysqladmin, wenn die Datenbank gar nicht laeuft.
    #>
    param($Paths, [int]$TimeoutMs = 250)
    $port = 3306
    if (Test-Path $Paths.Settings) {
        try { $port = [int](Get-AcSettingsPort $Paths) } catch { $port = 3306 }
    }
    $client = New-Object Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($ar)
        return $true
    } catch { return $false } finally { try { $client.Close() } catch {} }
}

function Get-AcSettingsPort {
    param($Paths)
    if ($script:AcCachedPort) { return $script:AcCachedPort }
    $p = 3306
    try {
        $raw = Get-Content $Paths.Settings -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.MySqlPort) { $p = [int]$raw.MySqlPort }
    } catch {}
    $script:AcCachedPort = $p
    return $p
}

function Test-AcMySqlAlive {
    param($Paths)
    # zuerst der schnelle Porttest - laeuft nichts, sparen wir uns mysqladmin
    if (-not (Test-AcMySqlPortOpen $Paths)) { return $false }
    $admin = Get-AcMySqlExe $Paths 'mysqladmin.exe'
    if (-not (Test-Path $admin) -or -not (Test-Path $Paths.MySqlCnf)) { return $false }
    # Eine haengende Statusabfrage (z.B. waehrend MySQL gerade herunterfaehrt) darf
    # niemals eine Ausnahme ausloesen - dann gilt die Datenbank als nicht erreichbar.
    try {
        $r = Invoke-AcCaptureUi $admin "--defaults-extra-file=`"$($Paths.MySqlCnf)`" --connect-timeout=2 ping" -TimeoutSeconds 15
        return ($r.Output -match 'alive')
    } catch { return $false }
}

function Start-AcMySql {
    # Startet mysqld als Kindprozess, wartet bis erreichbar. Gibt Prozess-State zurueck (oder $null wenn schon lief).
    param($Paths, [int]$WaitSeconds = 60)
    if (Test-AcMySqlAlive $Paths) { Write-AcLog (T 'log.mysqlAlready'); return $null }
    $mysqld = Get-AcMySqlExe $Paths 'mysqld.exe'
    Write-AcLog (T 'log.mysqlStart')
    $state = Start-AcProcess -FilePath $mysqld -ArgumentList "--defaults-file=`"$($Paths.MySqlIni)`" --console" -WorkingDirectory $Paths.MySql
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $WaitSeconds) {
        foreach ($l in (Read-AcProcessLines $state)) { Write-AcLog $l 'MYSQL' }
        if ($state.Process.HasExited) { throw (T 'log.mysqlDied' @($state.Process.ExitCode)) }
        if (Test-AcMySqlAlive $Paths) { Write-AcLog (T 'log.mysqlReady'); return $state }
        Invoke-AcDoEvents; Start-Sleep -Milliseconds 500
    }
    throw (T 'log.mysqlNoAnswer')
}

function Stop-AcMySql {
    param($Paths, $State)
    $admin = Get-AcMySqlExe $Paths 'mysqladmin.exe'
    if (Test-AcMySqlAlive $Paths) {
        Write-AcLog (T 'log.mysqlStop')
        Invoke-AcCaptureUi $admin "--defaults-extra-file=`"$($Paths.MySqlCnf)`" shutdown" -TimeoutSeconds 90 | Out-Null
    }
    if ($State) {
        $t0 = Get-Date
        while (-not $State.Process.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Invoke-AcDoEvents; Start-Sleep -Milliseconds 300 }
        if (-not $State.Process.HasExited) { Write-AcLog (T 'log.mysqlForce') 'WARN'; try { $State.Process.Kill() } catch {} }
    }
    # Sicherheitsnetz: laeuft noch ein mysqld aus DIESEM Serverordner (z.B. aus einer
    # frueheren Sitzung), wird er ebenfalls beendet - sonst bleibt der Port belegt.
    $t0 = Get-Date
    while ((Test-AcMySqlAlive $Paths) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Invoke-AcDoEvents; Start-Sleep -Milliseconds 300 }
    if (Test-AcMySqlAlive $Paths) {
        $ownDir = (Join-Path $Paths.MySql 'bin').ToLower()
        foreach ($p in (Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue)) {
            try { if ($p.Path -and $p.Path.ToLower().StartsWith($ownDir)) { Write-AcLog (T 'log.mysqlKillLeft' @($p.Id)) 'WARN'; Stop-AcProcessTree $p.Id } } catch {}
        }
    }
}

function Invoke-AcMySql {
    # SQL-Text ausfuehren (als root)
    param($Paths, [string]$Sql, [string]$Database = '')
    $mysql = Get-AcMySqlExe $Paths 'mysql.exe'
    $tmp = Join-Path $env:TEMP ("ac_" + [IO.Path]::GetRandomFileName() + '.sql')
    [IO.File]::WriteAllText($tmp, $Sql, (New-Object Text.UTF8Encoding($false)))
    try {
        $mysqlArgs = "--defaults-extra-file=`"$($Paths.MySqlCnf)`""
        if ($Database) { $mysqlArgs += " $Database" }
        $mysqlArgs += " -e `"source $(ConvertTo-AcSlashPath $tmp)`""
        $r = Invoke-AcCaptureUi $mysql $mysqlArgs
        if ($r.ExitCode -ne 0) { throw (T 'log.mysqlError' @($r.Error)) }
        return $r.Output
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}


function Grant-AcDbPrivileges {
    <#
      Globale Rechte fuer den Serverbenutzer, die ueber die reinen Datenbankrechte hinausgehen:
      RELOAD wird z.B. von mod-playerbots beim Zuruecksetzen der Bots (FLUSH) gebraucht.
      Idempotent - kann bei jedem Start ausgefuehrt werden.
    #>
    param($Paths, $Settings)
    $u = ConvertTo-AcSqlString $Settings.DbUser
    $sql = ''
    foreach ($h in @('%', 'localhost')) { $sql += "GRANT RELOAD ON *.* TO '$u'@'$h';`n" }
    $sql += "FLUSH PRIVILEGES;`n"
    Invoke-AcMySql $Paths $sql | Out-Null
}


function Test-AcWorldRunning {
    <#
      Laeuft ein worldserver.exe aus DIESEM Serverordner? Wird gebraucht, um
      veraltete online-Markierungen in der Datenbank von echten Logins zu unterscheiden.
    #>
    param($Paths)
    $binDir = ($Paths.Bin).ToLower().TrimEnd('\')
    foreach ($p in (Get-Process -Name 'worldserver' -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and $p.Path.ToLower().StartsWith($binDir)) { return $true } } catch {}
    }
    return $false
}

function Test-AcPortFree {
    param([int]$Port)
    try {
        $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
        $l.Start(); $l.Stop(); return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------
#  Module
# ---------------------------------------------------------------------
function Get-AcModuleName {
    param([string]$Name)
    return ($Name -replace '-(master|main|Playerbot|playerbot)$', '' -replace '\.zip$', '')
}

function Install-AcModuleFromPath {
    # Ordner oder ZIP -> source\modules\<name>
    param($Paths, [string]$SourcePath)
    if (-not (Test-Path $Paths.Modules)) { New-Item -ItemType Directory -Path $Paths.Modules | Out-Null }
    $item = Get-Item $SourcePath
    if ($item.PSIsContainer) {
        $name = Get-AcModuleName $item.Name
        $target = Join-Path $Paths.Modules $name
        if (Test-Path $target) { throw (T 'log.modExists' @($name)) }
        Copy-Item $item.FullName $target -Recurse
        return $name
    }
    if ($item.Extension -ieq '.zip') {
        $tmp = Join-Path $Paths.Modules ("_zip_" + [IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tmp | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($item.FullName, $tmp)
        $entries = Get-ChildItem $tmp
        $src = $tmp; $name = Get-AcModuleName $item.BaseName
        if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $src = $entries[0].FullName; $name = Get-AcModuleName $entries[0].Name }
        if (-not (Test-Path (Join-Path $src 'CMakeLists.txt')) -and -not (Test-Path (Join-Path $src 'src'))) {
            Remove-Item $tmp -Recurse -Force; throw (T 'log.zipNotModule')
        }
        $target = Join-Path $Paths.Modules $name
        if (Test-Path $target) { Remove-Item $tmp -Recurse -Force; throw (T 'log.modExists' @($name)) }
        Move-Item $src $target
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $name
    }
    throw (T 'log.dropModule')
}

function Install-AcModuleFromGit {
    param($Paths, [string]$Url, [string]$Branch = '')
    $git = Find-AcGit
    if (-not $git) { throw (T 'log.notFound' @('Git')) }
    # Bei einer Git-URL ist der letzte Pfadteil bereits der exakte Repository-Name
    # (nur ein evtl. ".git" abschneiden - KEIN "-master"-Strip wie bei GitHub-ZIPs)
    $name = (($Url.TrimEnd('/') -split '/')[-1]) -replace '\.git$', ''
    if (-not $name) { throw (T 'log.noModName' @($Url)) }
    $target = Join-Path $Paths.Modules $name
    if (Test-Path $target) { throw (T 'log.modExists' @($name)) }
    # --recurse-submodules ist Pflicht: Module wie mod-eluna liefern ihre
    # Abhaengigkeiten (z.B. die Lua-Bibliothek) als Submodul mit
    $gitArgs = "clone --progress --recurse-submodules"
    if ($Branch) { $gitArgs += " --branch $Branch" }
    $gitArgs += " `"$Url`" `"$target`""
    Invoke-AcProcess -FilePath $git -ArgumentList $gitArgs -WorkingDirectory $Paths.Modules | Out-Null
    return $name
}

# ---------------------------------------------------------------------
#  Modul-SQL: erkennen, einbinden, manuell importieren
#
#  AzerothCore importiert SQL eines Moduls nur automatisch, wenn es unter
#      modules\<modul>\data\sql\db-world      (bzw. db-characters / db-auth)
#  liegt. Viele Module benutzen aber alte Layouts wie sql\world\base.
#  Diese Funktionen erkennen das Layout und legen bei Bedarf Kopien im
#  offiziellen Pfad an. Was kopiert wurde, steht in .ac-manager-sql.json
#  im Modulordner, damit vor jedem git pull sauber aufgeraeumt werden kann.
# ---------------------------------------------------------------------

$script:AcSqlTargetDir = @{ world = 'db-world'; characters = 'db-characters'; auth = 'db-auth' }   # nur diese drei werden kopiert
$script:AcSqlDatabase  = @{ world = 'acore_world'; characters = 'acore_characters'; auth = 'acore_auth'; playerbots = 'acore_playerbots' }

function Get-AcSqlManifestPath { param([string]$ModulePath) return (Join-Path $ModulePath '.ac-manager-sql.json') }

function Get-AcSqlManifest {
    param([string]$ModulePath)
    $f = Get-AcSqlManifestPath $ModulePath
    if (-not (Test-Path $f)) { return @() }
    try { return @((Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).files | Where-Object { $_ }) } catch { return @() }
}

function Get-AcHandledSql {
    # SQL-Dateien, die der Nutzer bereits von Hand eingespielt hat
    param([string]$ModulePath)
    $f = Get-AcSqlManifestPath $ModulePath
    if (-not (Test-Path $f)) { return @() }
    try { return @((Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).handled | Where-Object { $_ }) } catch { return @() }
}

function Save-AcSqlManifest {
    param([string]$ModulePath, [string[]]$Files, [string[]]$Handled = $null)
    $f = Get-AcSqlManifestPath $ModulePath
    if ($null -eq $Handled) { $Handled = @(Get-AcHandledSql $ModulePath) }
    if ((-not $Files -or $Files.Count -eq 0) -and (-not $Handled -or $Handled.Count -eq 0)) {
        if (Test-Path $f) { Remove-Item $f -Force }
        return
    }
    $json = @{ files = @($Files); handled = @($Handled) } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($f, $json, (New-Object Text.UTF8Encoding($false)))
}

function Add-AcHandledSql {
    # Merkt sich, dass diese Dateien manuell eingespielt wurden
    param([string]$ModulePath, [string[]]$RelPaths)
    $handled = New-Object Collections.Generic.List[string]
    foreach ($h in (Get-AcHandledSql $ModulePath)) { $handled.Add([string]$h) }
    foreach ($r in $RelPaths) { if (-not $handled.Contains($r)) { $handled.Add($r) } }
    Save-AcSqlManifest $ModulePath (Get-AcSqlManifest $ModulePath) $handled.ToArray()
}

function Get-AcSqlDbFromSegment {
    param([string]$Segment)
    $s = $Segment.ToLower()
    if ($s -match 'playerbot')             { return 'playerbots' }   # eigene DB von mod-playerbots, eigener Updater
    if ($s -match 'auth')                  { return 'auth' }
    if ($s -match 'char')                  { return 'characters' }
    if ($s -match 'world')                 { return 'world' }
    return $null
}

function Get-AcModuleSqlFiles {
    <#
      Liefert je SQL-Datei:
        Rel     relativer Pfad im Modul (mit /)
        Full    vollstaendiger Pfad
        Db      world | characters | auth | $null
        Status  auto     = liegt im automatisch importierten Pfad
                linked   = Kopie, die dieser Manager angelegt hat
                legacy   = anderes Layout, kann eingebunden werden
                optional = optionale/zusaetzliche SQL, nur manuell
                unknown  = Ziel-Datenbank nicht erkennbar
    #>
    param([string]$ModulePath)
    $result = New-Object Collections.Generic.List[object]
    if (-not (Test-Path $ModulePath)) { return $result }
    $managed = @(Get-AcSqlManifest $ModulePath)
    $handled = @(Get-AcHandledSql $ModulePath)
    $base = (Resolve-Path $ModulePath).Path.TrimEnd('\')
    foreach ($f in (Get-ChildItem $ModulePath -Filter '*.sql' -File -Recurse -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($base.Length + 1) -replace '\\', '/'
        $relLower = $rel.ToLower()
        if ($relLower -match '(^|/)(\.git|build)/') { continue }
        $segs = @($rel -split '/')
        $dirSegs = @($segs[0..([Math]::Max(0, $segs.Count - 2))])
        if ($segs.Count -eq 1) { $dirSegs = @() }
        $db = $null
        foreach ($s in $dirSegs) { $d = Get-AcSqlDbFromSegment $s; if ($d) { $db = $d } }
        $isOptional = $relLower -match '(optional|deprecated|archive|/old/|example)'
        $inAutoPath = $relLower -match '^data/sql/'
        $status =
            if ($managed -contains $rel)                     { 'linked' }
            elseif ($inAutoPath -and $db -and -not $isOptional) { 'auto' }
            elseif ($handled -contains $rel)                 { 'handled' }
            elseif ($isOptional)                             { 'optional' }
            elseif ($db -and $script:AcSqlTargetDir.ContainsKey($db)) { 'legacy' }
            else                                             { 'unknown' }
        $hash = $null
        try { $hash = (Get-FileHash $f.FullName -Algorithm MD5).Hash } catch {}
        $result.Add([pscustomobject]@{ Rel = $rel; Full = $f.FullName; Db = $db; Status = $status; Hash = $hash })
    }
    return $result
}

function Get-AcModuleSqlSummary {
    param([string]$ModulePath)
    $files = @(Get-AcModuleSqlFiles $ModulePath)
    if ($files.Count -eq 0) { return (T 'sql.none') }
    $parts = @()
    foreach ($grp in @('auto', 'linked', 'handled', 'legacy', 'optional', 'unknown')) {
        $n = @($files | Where-Object { $_.Status -eq $grp }).Count
        if ($n -gt 0) { $parts += ("$n " + (T ("sql." + $grp))) }
    }
    return ($parts -join ', ')
}

function Remove-AcModuleSqlLinks {
    # Entfernt alle Kopien, die dieser Manager angelegt hat (z.B. vor einem git pull)
    param([string]$ModulePath)
    $managed = @(Get-AcSqlManifest $ModulePath)
    foreach ($rel in $managed) {
        $p = Join-Path $ModulePath ($rel -replace '/', '\')
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }
    foreach ($d in @('db-world', 'db-characters', 'db-auth')) {
        $dir = Join-Path $ModulePath "data\sql\$d"
        if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force -ErrorAction SilentlyContinue }
    }
    Save-AcSqlManifest $ModulePath @()
    return $managed.Count
}

function Sync-AcModuleSql {
    <#
      Legt fuer SQL-Dateien in nicht-standardkonformen Ordnern Kopien unter
      data/sql/db-<datenbank>/ an, damit der Auto-Updater sie einspielt.
      Reihenfolge bleibt erhalten: base -> 00_, updates -> 20_, Rest -> 10_.
      Rueckgabe: @{ Linked; Skipped; Optional; Unknown; Names }
    #>
    param([string]$ModulePath, [string]$ModuleName = '')
    if (-not $ModuleName) { $ModuleName = Split-Path $ModulePath -Leaf }
    Remove-AcModuleSqlLinks $ModulePath | Out-Null
    $files = @(Get-AcModuleSqlFiles $ModulePath)
    $created = New-Object Collections.Generic.List[string]
    $names   = New-Object Collections.Generic.List[string]
    $skipped = 0
    # Inhalte, die bereits im Auto-Pfad liegen (Modul liefert beide Layouts) -> nicht nochmal kopieren
    $autoHashes = @($files | Where-Object { $_.Status -eq 'auto' -and $_.Hash } | ForEach-Object { $_.Hash })
    $modKey = ($ModuleName -replace '[^A-Za-z0-9]', '_').ToLower()
    foreach ($f in ($files | Where-Object { $_.Status -eq 'legacy' })) {
        if ($f.Hash -and ($autoHashes -contains $f.Hash)) { $skipped++; Write-AcLog (T 'log.sqlSkipDup' @($f.Rel)) ; continue }
        $relLower = $f.Rel.ToLower()
        $prefix = if ($relLower -match '/base/') { '00' } elseif ($relLower -match '/updates?/') { '20' } else { '10' }
        $flat = ($f.Rel -replace '\.sql$', '') -replace '[/\\]', '_'
        # Der Updater verfolgt Dateien ueber ihren Dateinamen -> Modulname einbauen, damit
        # gleichnamige Dateien verschiedener Module nicht kollidieren
        $targetName = "{0}_{1}_{2}.sql" -f $prefix, $modKey, $flat
        $targetDir = Join-Path $ModulePath ("data\sql\" + $script:AcSqlTargetDir[$f.Db])
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        $target = Join-Path $targetDir $targetName
        if (Test-Path $target) { $skipped++; continue }
        Copy-Item $f.Full $target -Force
        $relNew = "data/sql/{0}/{1}" -f $script:AcSqlTargetDir[$f.Db], $targetName
        $created.Add($relNew)
        $names.Add("$($f.Rel)  ->  $relNew  [$($script:AcSqlDatabase[$f.Db])]")
    }
    Save-AcSqlManifest $ModulePath $created.ToArray()
    $res = @{
        Module   = $ModuleName
        Linked   = $created.Count
        Skipped  = $skipped
        Auto     = @($files | Where-Object { $_.Status -eq 'auto' }).Count
        Optional = @($files | Where-Object { $_.Status -eq 'optional' }).Count
        Unknown  = @($files | Where-Object { $_.Status -eq 'unknown' }).Count
        Total    = $files.Count
        Names    = $names.ToArray()
    }
    if ($res.Total -eq 0) {
        Write-AcLog (T 'log.sqlNone' @($ModuleName))
    } else {
        Write-AcLog (T 'log.sqlSummary' @($ModuleName, $res.Total, $res.Auto, $res.Linked, $res.Optional, $res.Unknown))
        foreach ($n in $res.Names) { Write-AcLog "   $n" }
        if ($res.Unknown -gt 0) { Write-AcLog (T 'log.sqlUnknown' @($res.Unknown)) 'WARN' }
    }
    return $res
}

function Sync-AcAllModuleSql {
    param($Paths)
    $all = @()
    if (-not (Test-Path $Paths.Modules)) { return $all }
    foreach ($d in (Get-ChildItem $Paths.Modules -Directory)) {
        if ($d.Name -like '_*') { continue }
        $all += Sync-AcModuleSql $d.FullName $d.Name
    }
    return $all
}

function Remove-AcAllModuleSqlLinks {
    param($Paths)
    if (-not (Test-Path $Paths.Modules)) { return }
    foreach ($d in (Get-ChildItem $Paths.Modules -Directory)) {
        if ($d.Name -like '_*') { continue }
        $n = Remove-AcModuleSqlLinks $d.FullName
        if ($n -gt 0) { Write-AcLog (T 'log.sqlRemoved' @($d.Name, $n)) }
    }
}

function Get-AcSqlFileForImport {
    <#
      Bereitet eine SQL-Datei zum Einspielen vor. Manche Module enthalten eine
      fest eingetragene Datenbank des Autors ("USE azc_world_ashbringer;") oder
      CREATE DATABASE. Solche Zeilen werden in einer Arbeitskopie auskommentiert,
      damit die Datei in die hier gewaehlte Datenbank geht. Das Original bleibt
      unveraendert.
      Rueckgabe: Pfad der zu verwendenden Datei (Original oder Arbeitskopie).
    #>
    param([string]$File)
    try {
        $text = [IO.File]::ReadAllText($File)
    } catch { return $File }
    $pattern = '(?im)^\s*(USE\s+[^;]+;|CREATE\s+DATABASE[^;]*;)'
    if ($text -notmatch $pattern) { return $File }
    $hits = [regex]::Matches($text, $pattern)
    $clean = [regex]::Replace($text, $pattern, { param($m) '-- [Server-Manager] ' + $m.Value.Trim() })
    $tmp = Join-Path $env:TEMP ("acsql_" + [IO.Path]::GetRandomFileName() + '.sql')
    [IO.File]::WriteAllText($tmp, $clean, (New-Object Text.UTF8Encoding($false)))
    Write-AcLog (T 'log.sqlUseRemoved' @((Split-Path $File -Leaf), $hits.Count)) 'WARN'
    return $tmp
}

function Invoke-AcSqlFile {
    # Manueller Import einer einzelnen SQL-Datei (fuer optionale / nicht zuordenbare Dateien)
    param($Paths, [string]$File, [string]$Database)
    $mysql = Get-AcMySqlExe $Paths 'mysql.exe'
    if (-not (Test-Path $Paths.MySqlCnf)) { throw (T 'log.noDbCreds') }
    $use = Get-AcSqlFileForImport $File
    try {
        $r = Invoke-AcCapture $mysql ("--defaults-extra-file=`"$($Paths.MySqlCnf)`" --default-character-set=utf8mb4 $Database -e `"source $(ConvertTo-AcSlashPath $use)`"")
        if ($r.ExitCode -ne 0) { throw (T 'log.importFailed' @((Split-Path $File -Leaf), $r.Error)) }
        Write-AcLog (T 'log.imported' @((Split-Path $File -Leaf), $Database))
    } finally {
        if ($use -ne $File) { Remove-Item $use -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------------
#  Modul-Info: liest aus den Dateien eines Moduls heraus, was es
#  in die Welt einfuegt - vor allem NPC-, Objekt- und Item-IDs, damit
#  der Nutzer weiss, was er zum Spawnen eingeben muss.
# ---------------------------------------------------------------------

function Get-AcSqlEntries {
    <#
      Sucht in einem SQL-Text nach Eintraegen einer Tabelle und liefert @{ Id; Name }.
      Beruecksichtigt die drei ueblichen Schreibweisen:
        INSERT INTO `creature_template` (entry, ...) VALUES (190010, ..., 'Name', ...);
        DELETE FROM `creature_template` WHERE `entry` = 190010;
        SET @NPC := 190010;   (wird ueber die spaetere INSERT-Zeile miterfasst)
    #>
    param([string]$Sql, [string]$Table, [int]$MinId = 0)
    $found = New-Object Collections.Specialized.OrderedDictionary
    $t = [regex]::Escape($Table)

    # 1) DELETE FROM <table> WHERE entry IN (a, b, c)  /  = a
    foreach ($m in [regex]::Matches($Sql, "(?is)DELETE\s+FROM\s+``?$t``?\s+WHERE\s+``?(?:entry|item|id)``?\s*(?:=\s*(\d+)|IN\s*\(([^)]*)\))")) {
        $ids = @()
        if ($m.Groups[1].Success) { $ids += $m.Groups[1].Value }
        if ($m.Groups[2].Success) { $ids += ([regex]::Matches($m.Groups[2].Value, '\d+') | ForEach-Object { $_.Value }) }
        foreach ($id in $ids) { if ([int64]$id -ge $MinId -and -not $found.Contains($id)) { $found[$id] = '' } }
    }

    # 2) INSERT INTO <table> (...) VALUES (...), (...);
    foreach ($m in [regex]::Matches($Sql, "(?is)INSERT\s+(?:IGNORE\s+)?INTO\s+``?$t``?\s*(\([^)]*\))?\s*VALUES\s*(.*?);")) {
        $block = $m.Groups[2].Value
        # Wertetupel einzeln herausloesen (einfache Klammerebene, Strings duerfen Klammern enthalten)
        foreach ($tm in [regex]::Matches($block, "(?s)\(((?:'(?:[^'\\]|\\.|'')*'|[^()'])*)\)")) {
            $tuple = $tm.Groups[1].Value
            $idm = [regex]::Match($tuple, '^\s*(\d+)')
            if (-not $idm.Success) { continue }
            $id = $idm.Groups[1].Value
            if ([int64]$id -lt $MinId) { continue }
            $name = ''
            $nm = [regex]::Match($tuple, "'((?:[^'\\]|\\.|'')*)'")
            if ($nm.Success) { $name = ($nm.Groups[1].Value -replace "''", "'").Trim() }
            if ($found.Contains($id)) { if (-not $found[$id] -and $name) { $found[$id] = $name } }
            else { $found[$id] = $name }
        }
    }
    $list = New-Object Collections.Generic.List[object]
    foreach ($k in $found.Keys) { $list.Add([pscustomobject]@{ Id = $k; Name = [string]$found[$k] }) }
    return $list
}


# ---------------------------------------------------------------------
#  DBC-Dateien eines Moduls (ersetzen Dateien in data\dbc)
# ---------------------------------------------------------------------
function Get-AcModuleDbcFiles {
    param([string]$ModulePath)
    if (-not (Test-Path $ModulePath)) { return @() }
    return @(Get-ChildItem $ModulePath -Filter '*.dbc' -File -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\\.git\\' })
}

function Install-AcModuleDbc {
    <#
      Kopiert die DBC-Dateien eines Moduls nach data\dbc und legt vorher eine
      Sicherung der ersetzten Dateien an. Gibt @{ Copied; Backup } zurueck.
    #>
    param($Paths, [string]$ModulePath)
    $files = @(Get-AcModuleDbcFiles $ModulePath)
    if ($files.Count -eq 0) { return @{ Copied = @(); Backup = '' } }
    $dbcDir = Join-Path $Paths.Data 'dbc'
    if (-not (Test-Path $dbcDir)) { throw (T 'log.folderMissing' @($dbcDir)) }
    $backup = Join-Path $Paths.Data ('dbc-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $copied = New-Object Collections.Generic.List[string]
    foreach ($f in $files) {
        $target = Join-Path $dbcDir $f.Name
        if (Test-Path $target) {
            if (-not (Test-Path $backup)) { New-Item -ItemType Directory -Path $backup | Out-Null }
            Copy-Item $target (Join-Path $backup $f.Name) -Force
        }
        Copy-Item $f.FullName $target -Force
        $copied.Add($f.Name)
        Write-AcLog (T 'log.dbcApplied' @($f.Name))
    }
    return @{ Copied = $copied.ToArray(); Backup = $(if (Test-Path $backup) { $backup } else { '' }) }
}

function Get-AcModuleInfo {
    <#
      Analysiert einen Modulordner und liefert:
        Name, Npcs, GameObjects, Items, Commands, ConfigFile, ConfigKeys, Readme, SqlCount
    #>
    param([string]$ModulePath, $Paths = $null)
    $name = Split-Path $ModulePath -Leaf
    $result = [pscustomobject]@{
        Name        = $name
        Path        = $ModulePath
        Npcs        = @()
        GameObjects = @()
        Items       = @()
        Commands    = @()
        ConfigFile  = ''
        ConfigKeys  = @()
        Readme      = ''
        ReadmePath  = ''
        DbcFiles    = @()
        SqlCount    = 0
    }
    if (-not (Test-Path $ModulePath)) { return $result }

    # --- SQL-Dateien auswerten ---
    $npcs = New-Object Collections.Specialized.OrderedDictionary
    $gobs = New-Object Collections.Specialized.OrderedDictionary
    $items = New-Object Collections.Specialized.OrderedDictionary
    $sqlFiles = @(Get-ChildItem $ModulePath -Filter '*.sql' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 8MB })
    $result.SqlCount = $sqlFiles.Count
    foreach ($f in $sqlFiles) {
        $sql = ''
        try { $sql = [IO.File]::ReadAllText($f.FullName) } catch { continue }
        foreach ($e in (Get-AcSqlEntries $sql 'creature_template'))   { if (-not $npcs.Contains($e.Id))  { $npcs[$e.Id] = $e.Name }  elseif (-not $npcs[$e.Id] -and $e.Name)  { $npcs[$e.Id] = $e.Name } }
        foreach ($e in (Get-AcSqlEntries $sql 'gameobject_template')) { if (-not $gobs.Contains($e.Id))  { $gobs[$e.Id] = $e.Name }  elseif (-not $gobs[$e.Id] -and $e.Name)  { $gobs[$e.Id] = $e.Name } }
        foreach ($e in (Get-AcSqlEntries $sql 'item_template'))       { if (-not $items.Contains($e.Id)) { $items[$e.Id] = $e.Name } elseif (-not $items[$e.Id] -and $e.Name) { $items[$e.Id] = $e.Name } }
    }
    $result.Npcs        = @($npcs.Keys  | ForEach-Object { [pscustomobject]@{ Id = $_; Name = [string]$npcs[$_] } })
    $result.GameObjects = @($gobs.Keys  | ForEach-Object { [pscustomobject]@{ Id = $_; Name = [string]$gobs[$_] } })
    $result.Items       = @($items.Keys | ForEach-Object { [pscustomobject]@{ Id = $_; Name = [string]$items[$_] } })

    # --- GM-Befehle aus dem C++-Quelltext (ChatCommandTable-Eintraege) ---
    $cmds = New-Object Collections.Generic.List[string]
    foreach ($f in (Get-ChildItem $ModulePath -Include '*.cpp', '*.h' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 2MB })) {
        $code = ''
        try { $code = [IO.File]::ReadAllText($f.FullName) } catch { continue }
        if ($code -notmatch 'ChatCommandTable|ChatCommand\s') { continue }
        foreach ($m in [regex]::Matches($code, '\{\s*"([a-z][a-z0-9_ -]{1,30})"\s*,\s*(?:SEC_|rbac::)')) {
            $c = $m.Groups[1].Value
            if (-not $cmds.Contains($c)) { $cmds.Add($c) }
        }
    }
    $result.Commands = $cmds.ToArray()

    # --- Konfigurationsdatei des Moduls ---
    $dist = @(Get-ChildItem $ModulePath -Filter '*.conf*' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($dist.Count -gt 0) {
        $result.ConfigFile = ($dist[0].Name -replace '\.dist$', '')
        try {
            $keys = @(Get-AcConfEntries $dist[0].FullName | ForEach-Object { $_.Key })
            $result.ConfigKeys = $keys
        } catch {}
    }

    $result.DbcFiles = @(Get-AcModuleDbcFiles $ModulePath | ForEach-Object { $_.Name })

    # --- README (vollstaendig, nur Bilder/Abzeichen und HTML entfernt) ---
    $readme = @(Get-ChildItem $ModulePath -Filter 'README*' -File -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending | Select-Object -First 1)
    if ($readme.Count -gt 0) {
        $result.ReadmePath = $readme[0].FullName
        try {
            $lines = @(Get-Content $readme[0].FullName -Encoding UTF8 |
                       Where-Object { $_ -notmatch '^\s*(!\[|\[!\[|<)' } |
                       ForEach-Object { ($_ -replace '^#+\s*', '') -replace '\*\*', '' })
            $text = (($lines -join "`r`n") -replace '(\r\n){3,}', "`r`n`r`n").Trim()
            if ($text.Length -gt 40000) { $text = $text.Substring(0, 40000) + "`r`n..." }
            $result.Readme = $text
        } catch {}
    }
    return $result
}

function Format-AcModuleInfo {
    # Baut den anzeigefertigen Text (Sprache kommt aus AC.Lang.ps1)
    param($Info)
    $nl = [Environment]::NewLine
    $sb = New-Object Text.StringBuilder
    $add = { param($s) [void]$sb.Append($s); [void]$sb.Append($nl) }

    & $add ("=== " + (T 'info.headModule') + " ===")
    & $add ("   $($Info.Name)")
    & $add ("   $($Info.Path)")
    & $add ''

    if ($Info.ConfigFile) {
        & $add ("=== " + (T 'info.headConfig') + " ===")
        & $add ("   $($Info.ConfigFile)   ($($Info.ConfigKeys.Count) " + (T 'cfg.colKey') + ")")
        & $add ('   ' + (T 'info.configHelp' @($Info.ConfigFile)))
        if ($Info.ConfigKeys.Count -gt 0) {
            foreach ($k in ($Info.ConfigKeys | Select-Object -First 60)) { & $add "      $k" }
            if ($Info.ConfigKeys.Count -gt 60) { & $add ('      ... (' + ($Info.ConfigKeys.Count - 60) + ' ' + (T 'info.moreInConfigTab') + ')') }
        }
        & $add ''
    }

    foreach ($grp in @(
        @{ Head = 'info.headNpc';  Items = $Info.Npcs;        Cmd = '.npc add' },
        @{ Head = 'info.headGob';  Items = $Info.GameObjects; Cmd = '.gobject add' },
        @{ Head = 'info.headItem'; Items = $Info.Items;       Cmd = '.additem' }
    )) {
        if ($grp.Items.Count -eq 0) { continue }
        & $add ("=== " + (T $grp.Head) + " ===")
        $shown = @($grp.Items | Select-Object -First 60)
        foreach ($e in $shown) {
            $line = T 'info.entryLine' @($e.Id, $e.Name)
            & $add ("$line".TrimEnd() + "        $($grp.Cmd) $($e.Id)")
        }
        if ($grp.Items.Count -gt $shown.Count) { & $add ('   ... (' + ($grp.Items.Count - $shown.Count) + ')') }
        & $add ''
    }

    if ($Info.DbcFiles.Count -gt 0) {
        & $add ("=== " + (T 'info.headDbc') + " ===")
        foreach ($f in $Info.DbcFiles) { & $add "   $f" }
        & $add ('   ' + (T 'info.dbcHint'))
        & $add ''
    }

    if ($Info.Commands.Count -gt 0) {
        & $add ("=== " + (T 'info.headCommands') + " ===")
        foreach ($c in $Info.Commands) { & $add "   .$c" }
        & $add ''
    }

    if ($Info.Npcs.Count -gt 0 -or $Info.GameObjects.Count -gt 0 -or $Info.Items.Count -gt 0) {
        & $add ("=== " + (T 'info.headSpawn') + " ===")
        & $add (T 'info.spawnHelp' @($nl))
        & $add ''
    } elseif ($Info.SqlCount -eq 0) {
        & $add (T 'info.notScanned')
        & $add ''
    } else {
        & $add ("=== " + (T 'info.headNpc') + " ===")
        & $add ('   ' + (T 'info.noneFound'))
        & $add ''
    }

    if ($Info.Readme) {
        & $add ("=== " + (T 'info.headReadme') + " ===")
        & $add $Info.Readme
        & $add ''
    }

    & $add (T 'info.heuristic')
    return $sb.ToString()
}

# ---------------------------------------------------------------------
#  Charakter-Editor (Datenbankzugriff)
# ---------------------------------------------------------------------
$acCharFile = Join-Path $PSScriptRoot 'AC.Char.ps1'
if (Test-Path $acCharFile) { . $acCharFile }

# ---------------------------------------------------------------------
#  Erscheinungsbild
# ---------------------------------------------------------------------
$acThemeFile = Join-Path $PSScriptRoot 'AC.Theme.ps1'
if (Test-Path $acThemeFile) { . $acThemeFile }

# ---------------------------------------------------------------------
#  Versionen der Teildateien vergleichen
#
#  Wird nur ein Teil der Skripte nach <Ordner>\tools kopiert, passen die
#  Dateien nicht mehr zusammen und es hagelt Folgefehler. Lieber hier
#  einmal verstaendlich abbrechen.
# ---------------------------------------------------------------------
$acMismatch = @()
foreach ($pair in @(@('AC.Lang.ps1', $script:AcLangVersion), @('AC.Char.ps1', $script:AcCharVersion), @('AC.Theme.ps1', $script:AcThemeVersion))) {
    if ($pair[1] -ne $script:AcToolsVersion) {
        $acMismatch += ("{0} = {1}" -f $pair[0], $(if ($pair[1]) { $pair[1] } else { '?' }))
    }
}
if ($acMismatch.Count -gt 0) {
    Stop-AcWithMessage ("The scripts in $PSScriptRoot do not belong to the same version." + [Environment]::NewLine +
                        "AC.Common.ps1 = $($script:AcToolsVersion), but: " + ($acMismatch -join ', ') + [Environment]::NewLine + [Environment]::NewLine +
                        "Copy ALL .ps1 files from the package into that folder.")
}

# ---------------------------------------------------------------------
#  Lua-Skripte (Eluna)
#
#  AzerothCore fuehrt Lua nur aus, wenn das Modul mod-eluna einkompiliert ist.
#  Die Skripte liegen dann in einem Ordner neben den Server-Binaries, der in
#  mod_LuaEngine.conf konfiguriert wird (Standard: lua_scripts).
# ---------------------------------------------------------------------

#  Zwei Projekte, die oft verwechselt werden:
#    mod-ale            - offizielles AzerothCore-Modul, frueher "mod-eluna" (umbenannt).
#                         Eigene API, NICHT kompatibel mit Standard-Eluna-Skripten.
#    ElunaAzerothCore   - Portierung, die die Original-Eluna-API beibehaelt.
$script:AcLuaEngines = @(
    @{ Key = 'ale';   Name = 'mod-ale';  Url = 'https://github.com/azerothcore/mod-ale.git' }
    @{ Key = 'eluna'; Name = 'mod-eluna'; Url = 'https://github.com/ElunaLuaEngine/ElunaAzerothCore.git' }
)
$script:AcElunaRepo = 'https://github.com/azerothcore/mod-ale.git'


function Test-AcLuaAvailable {
    <#
      Ist eine Lua-Bibliothek zum Bauen vorhanden? Sie kann aus zwei Quellen kommen:
        - aus dem Modul selbst (mod-ale bringt src\lualib mit)
        - aus dem Core (deps\lualib, bei Cores mit eingebauter Lua-Unterstuetzung)
      Nur wenn beides fehlt, kann eine Lua-Engine nicht gebaut werden.
      Rueckgabe: @{ InModule; InCore; Ok }
    #>
    param($Paths)
    $inModule = $false
    $name = Get-AcElunaModuleName $Paths
    if ($name) {
        $modPath = Join-Path $Paths.Modules $name
        $hit = @(Get-ChildItem $modPath -Filter 'lua.h' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        $inModule = ($hit.Count -gt 0)
    }
    $inCore = $false
    $depsDir = Join-Path $Paths.Source 'deps'
    if (Test-Path $depsDir) {
        $hit = @(Get-ChildItem $depsDir -Filter 'lua.h' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        $inCore = ($hit.Count -gt 0)
    }
    return @{ InModule = $inModule; InCore = $inCore; Ok = ($inModule -or $inCore) }
}

function Get-AcModuleRemoteUrl {
    param([string]$ModulePath)
    if (-not (Test-Path (Join-Path $ModulePath '.git'))) { return $null }
    $git = Find-AcGit
    if (-not $git) { return $null }
    $r = Invoke-AcCapture $git 'config --get remote.origin.url' $ModulePath
    if ($r.ExitCode -ne 0 -or -not $r.Output) { return $null }
    return $r.Output.Trim()
}

function Get-AcModuleRemoteName {
    <#
      Der echte Projektname. Die gespeicherte Git-Adresse taugt dafuer nicht:
      Wird ein Projekt umbenannt, folgt Git der Weiterleitung, behaelt aber die
      alte Adresse. Deshalb bei GitHub den kanonischen Namen erfragen.
    #>
    param([string]$ModulePath)
    $url = Get-AcModuleRemoteUrl $ModulePath
    if (-not $url) { return $null }
    $fallback = ((($url.TrimEnd('/')) -split '/')[-1] -replace '\.git$', '')
    if ($url -notmatch 'github\.com') { return $fallback }
    if (-not $script:AcRepoNameCache) { $script:AcRepoNameCache = @{} }
    if ($script:AcRepoNameCache.ContainsKey($url)) { return $script:AcRepoNameCache[$url] }
    $name = $fallback
    try {
        $m = [regex]::Match($url, 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?$')
        if ($m.Success) {
            $api = "https://api.github.com/repos/$($m.Groups[1].Value)/$($m.Groups[2].Value)"
            $info = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:AcUserAgent } -TimeoutSec 20
            if ($info.name) { $name = [string]$info.name }
        }
    } catch {}
    $script:AcRepoNameCache[$url] = $name
    return $name
}

function Get-AcMisnamedModules {
    <#
      Module, deren Ordnername nicht zum Projekt passt. Das passiert, wenn ein
      Projekt umbenannt wurde (z.B. mod-eluna -> mod-ale) und Git der Weiterleitung
      folgt. Manche Module verweisen in ihrem CMake auf den eigenen Namen und
      finden dann ihre Dateien nicht.
    #>
    param($Paths)
    $list = @()   # einfaches Feld statt .NET-Liste
    foreach ($name in (Get-AcModuleNames $Paths)) {
        $path = Join-Path $Paths.Modules $name
        $remote = Get-AcModuleRemoteName $path
        if ($remote -and ($remote -ne $name)) {
            $list += ,[pscustomobject]@{ Folder = $name; Expected = $remote; Path = $path }
        }
    }
    return $list
}


function Remove-AcDirectoryForce {
    <#
      Loescht einen Ordner zuverlaessig. Git legt Objektdateien schreibgeschuetzt
      an, wodurch ein einfaches Remove-Item scheitert.
    #>
    param([string]$Path, [int]$Retries = 3)
    if (-not (Test-Path $Path)) { return $true }
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            foreach ($f in (Get-ChildItem $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
                if ($f.Attributes -band [IO.FileAttributes]::ReadOnly) { $f.Attributes = 'Normal' }
            }
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            if ($i -eq $Retries) { Write-AcLog (T 'mod.removeFailed' @((Split-Path $Path -Leaf), $_.Exception.Message)) 'WARN'; return $false }
            Start-Sleep -Milliseconds 400
        }
    }
    return $false
}

function Rename-AcModuleFolder {
    # Modulordner an den Repositorynamen angleichen
    param($Paths, [string]$Folder, [string]$Expected)
    $src = Join-Path $Paths.Modules $Folder
    $dst = Join-Path $Paths.Modules $Expected
    if (Test-Path $dst) { throw (T 'log.modExists' @($Expected)) }
    Rename-Item $src $dst -Force
    # Adresse auf den neuen Projektnamen setzen, damit die Pruefung nicht erneut anschlaegt
    $url = Get-AcModuleRemoteUrl $dst
    if ($url -and ($url -notmatch [regex]::Escape($Expected))) {
        $git = Find-AcGit
        $newUrl = $url -replace '[^/]+?(\.git)?$', ($Expected + '.git')
        if ($git) { Invoke-AcCapture $git "remote set-url origin `"$newUrl`"" $dst | Out-Null }
    }
    Write-AcLog (T 'mod.renamed' @($Folder, $Expected))
    return $dst
}

function Get-AcElunaModuleName {
    # Der Ordnername kann je nach Herkunft abweichen
    param($Paths)
    foreach ($n in (Get-AcModuleNames $Paths)) {
        if ($n -match '(?i)eluna|(?i)mod-ale') { return $n }
    }
    return $null
}

function Test-AcElunaInstalled {
    param($Paths, $Settings = $null)
    $name = Get-AcElunaModuleName $Paths
    if (-not $name) { return $false }
    if ($Settings) { return (Test-AcModuleBuilt $Settings $name) }
    return $true
}

function Get-AcLuaScriptPath {
    <#
      Ermittelt den Skriptordner aus mod_LuaEngine.conf; faellt auf
      <bin>\lua_scripts zurueck. Relativer Pfad bezieht sich auf den Bin-Ordner.
    #>
    param($Paths)
    $dir = 'lua_scripts'
    $conf = $null
    if (-not $Paths -or -not $Paths.Bin) { return '' }
    if ($Paths.ModConfigs -and (Test-Path -LiteralPath $Paths.ModConfigs)) {
        $conf = Get-ChildItem $Paths.ModConfigs -Filter '*LuaEngine*.conf' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $conf) { $conf = Get-ChildItem $Paths.ModConfigs -Filter '*eluna*.conf' -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    }
    if ($conf) {
        try {
            foreach ($e in (Get-AcConfEntries $conf.FullName)) {
                if ($e.Key -match 'ScriptPath' -and $e.Value) { $dir = $e.Value; break }
            }
        } catch {}
    }
    # Der Wert aus der Konfiguration kann mehrzeilig oder leer sein - hier wird
    # daraus zuverlaessig ein einzelner Pfad, sonst scheitern spaetere Aufrufe
    $dir = [string](@($dir) | Where-Object { $_ } | Select-Object -First 1)
    $dir = $dir.Trim().Trim('"')
    if (-not $dir) { $dir = 'lua_scripts' }
    try {
        if ($dir -match '^[A-Za-z]:\\' -or $dir.StartsWith('\\')) { return ([string]$dir).TrimEnd('\') }
        return ([string](Join-Path $Paths.Bin ($dir -replace '/', '\'))).TrimEnd('\')
    } catch {
        Write-AcLog ("Get-AcLuaScriptPath: " + $_.Exception.Message) 'WARN'
        return ([string](Join-Path $Paths.Bin 'lua_scripts'))
    }
}

function Get-AcLuaScripts {
    <#
      Alle Lua-Dateien im Skriptordner, deaktivierte (.lua.off) eingeschlossen.
      Bewusst mit einfachem Feld und Tabellen statt .NET-Liste und Objekten:
      diese Kombination hat sich hier als zuverlaessig erwiesen.
    #>
    param($Paths)
    $dir = [string](Get-AcLuaScriptPath $Paths)
    if (-not $dir) { return @() }
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $dirLen = $dir.Length

    $files = @()
    try { $files = @(Get-ChildItem -LiteralPath $dir -File -Recurse -Force -ErrorAction SilentlyContinue) }
    catch { Write-AcLog ("Get-AcLuaScripts: " + $_.Exception.Message) 'WARN'; return @() }

    $result = @()
    foreach ($f in $files) {
        $name = [string]$f.Name
        if (-not ($name.EndsWith('.lua') -or $name.EndsWith('.lua.off'))) { continue }
        $full = [string]$f.FullName
        if ($full -like '*\.git\*') { continue }
        $rel = $name
        if ($full.Length -gt $dirLen) { $rel = $full.Substring($dirLen).TrimStart('\') }
        $size = 0.0
        try { $size = [Math]::Round(([double]$f.Length / 1024.0), 1) } catch { $size = 0.0 }
        $result += ,@{
            Name     = ($name -replace '\.off$', '')
            Rel      = $rel
            Full     = $full
            Enabled  = $name.EndsWith('.lua')
            SizeKb   = $size
            Modified = $f.LastWriteTime
        }
    }
    return $result
}

function Install-AcLuaScript {
    <#
      Legt eine Lua-Datei (oder alle Lua-Dateien eines Ordners) im Skriptordner ab.
    #>
    param($Paths, [string]$SourcePath)
    $dir = Get-AcLuaScriptPath $Paths
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $item = Get-Item $SourcePath
    $copied = New-Object Collections.Generic.List[string]
    if ($item.Extension -ieq '.zip') {
        # ZIP eines Skript-Repositories: entpacken und die Lua-Dateien uebernehmen
        $tmp = Join-Path $env:TEMP ("aclua_" + [IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            [IO.Compression.ZipFile]::ExtractToDirectory($item.FullName, $tmp)
            $sub = Join-Path $dir ($item.BaseName -replace '-(master|main)$', '')
            if (-not (Test-Path $sub)) { New-Item -ItemType Directory -Path $sub -Force | Out-Null }
            foreach ($f in (Get-ChildItem $tmp -Filter '*.lua' -File -Recurse)) {
                Copy-Item $f.FullName (Join-Path $sub $f.Name) -Force
                $copied.Add($f.Name)
            }
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    } elseif ($item.PSIsContainer) {
        foreach ($f in (Get-ChildItem $item.FullName -Filter '*.lua' -File -Recurse)) {
            Copy-Item $f.FullName (Join-Path $dir $f.Name) -Force
            $copied.Add($f.Name)
        }
    } elseif ($item.Extension -ieq '.lua') {
        Copy-Item $item.FullName (Join-Path $dir $item.Name) -Force
        $copied.Add($item.Name)
    } else {
        throw (T 'lua.notLua' @($item.Name))
    }
    foreach ($n in $copied) { Write-AcLog (T 'lua.added' @($n)) }
    return $copied.ToArray()
}

function Set-AcLuaScriptEnabled {
    # Aktivieren/Deaktivieren durch Umbenennen (.lua <-> .lua.off)
    param([string]$FullPath, [bool]$Enabled)
    if ($Enabled) {
        if ($FullPath -match '\.off$') { Rename-Item $FullPath ($FullPath -replace '\.off$', '') -Force }
    } else {
        if ($FullPath -notmatch '\.off$') { Rename-Item $FullPath ($FullPath + '.off') -Force }
    }
}

function Install-AcLuaScriptFromGit {
    <#
      Holt ein Skript-Repository direkt in den Lua-Ordner. Es bleibt ein
      Git-Arbeitsverzeichnis, damit es spaeter aktualisiert werden kann.
      Rueckgabe: @{ Name; Path; LuaCount; SqlFiles }
    #>
    param($Paths, [string]$Url)
    $git = Find-AcGit
    if (-not $git) { throw (T 'log.notFound' @('Git')) }
    $dir = Get-AcLuaScriptPath $Paths
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $name = ((($Url.TrimEnd('/')) -split '/')[-1] -replace '\.git$', '')
    if (-not $name) { throw (T 'log.noModName' @($Url)) }
    $target = Join-Path $dir $name
    if (Test-Path $target) { throw (T 'lua.repoExists' @($name)) }
    Invoke-AcProcess -FilePath $git -ArgumentList "clone --progress --recurse-submodules `"$Url`" `"$target`"" -WorkingDirectory $dir | Out-Null
    $lua = @(Get-ChildItem $target -Filter '*.lua' -File -Recurse -ErrorAction SilentlyContinue)
    $sql = @(Get-ChildItem $target -Filter '*.sql' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    Write-AcLog (T 'lua.repoAdded' @($name, $lua.Count))
    return @{ Name = $name; Path = $target; LuaCount = $lua.Count; SqlFiles = $sql }
}

function Get-AcLuaScriptRepos {
    # Unterordner im Lua-Ordner, die ein Git-Arbeitsverzeichnis sind
    param($Paths)
    $dir = Get-AcLuaScriptPath $Paths
    $list = @()   # einfaches Feld statt .NET-Liste
    if (-not (Test-Path $dir)) { return @() }
    foreach ($sub in (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path (Join-Path $sub.FullName '.git')) { $list.Add($sub) }
    }
    return $list
}

function Update-AcLuaScriptRepos {
    # git pull fuer alle Skript-Repositories
    param($Paths)
    $git = Find-AcGit
    if (-not $git) { throw (T 'log.notFound' @('Git')) }
    $n = 0
    foreach ($repo in (Get-AcLuaScriptRepos $Paths)) {
        $r = Invoke-AcCapture $git 'pull --ff-only' $repo.FullName
        if ($r.ExitCode -eq 0) { $n++; Write-AcLog (T 'lua.repoUpdated' @($repo.Name)) }
        else { Write-AcLog (T 'log.pullFailedGeneric' @($repo.Name, $r.Error)) 'WARN' }
    }
    return $n
}

function Get-AcLuaSqlPlan {
    <#
      Ordnet die SQL-Dateien eines Skript-Repositories einer Datenbank zu.
      Skripte liefern ihre Tabellen meist ohne feste Ordnerstruktur, deshalb
      werden Pfad und Dateiname nach Schluesselwoertern durchsucht.
      Standard ist die Weltdatenbank.
    #>
    param($Paths, [string]$RepoPath)
    $plan = @()   # einfaches Feld statt .NET-Liste
    if (-not (Test-Path $RepoPath)) { return $plan }
    foreach ($f in (Get-ChildItem $RepoPath -Filter '*.sql' -File -Recurse -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($RepoPath.Length).TrimStart('\')
        $key = ($rel -replace '\\', '/').ToLower()
        $db = 'world'
        if     ($key -match 'db[_-]?auth|/auth/')       { $db = 'auth' }
        elseif ($key -match 'db[_-]?char|/characters?/'){ $db = 'characters' }
        elseif ($key -match 'db[_-]?world|/world/')     { $db = 'world' }
        elseif ($key -match 'auth|account|realmd')      { $db = 'auth' }
        elseif ($key -match 'char|player|progress|persist') { $db = 'characters' }
        $plan.Add([pscustomobject]@{
            Rel  = $rel
            Full = $f.FullName
            Db   = $db
            Name = $script:AcSqlDatabase[$db]
        })
    }
    return $plan
}

function Import-AcLuaSqlPlan {
    # Spielt die zugeordneten Dateien ein (Reihenfolge: alphabetisch je Datenbank)
    param($Paths, $Plan)
    $done = 0
    foreach ($e in ($Plan | Sort-Object Db, Rel)) {
        Invoke-AcSqlFile $Paths $e.Full $e.Name
        $done++
    }
    return $done
}

function Get-AcAllLuaSqlPlan {
    # SQL-Dateien aller Skript-Repositories im Lua-Ordner
    param($Paths)
    $plan = @()   # einfaches Feld statt .NET-Liste
    $dir = Get-AcLuaScriptPath $Paths
    if (-not (Test-Path $dir)) { return $plan }
    foreach ($sub in (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue)) {
        foreach ($e in (Get-AcLuaSqlPlan $Paths $sub.FullName)) {
            $plan += ,[pscustomobject]@{ Rel = (Join-Path $sub.Name $e.Rel); Full = $e.Full; Db = $e.Db; Name = $e.Name }
        }
    }
    return $plan
}

function Get-AcClientAddonScripts {
    <#
      Findet Lua-Dateien, die zum Spielclient gehoeren und faelschlich im
      Serverordner liegen. Erkennbar an Client-Funktionen wie CreateFrame oder
      SlashCmdList - der Server kennt sie nicht und wirft beim Laden Fehler.
      Eine .toc-Datei im selben Ordner ist ein weiterer eindeutiger Hinweis.
    #>
    param($Paths)
    $result = @()
    $tocFolders = @{}
    foreach ($s in @(Get-AcLuaScripts $Paths)) {
        $full = [string]$s.Full
        if (-not $full) { continue }
        $folder = [string](Split-Path $full -Parent)
        if (-not $tocFolders.ContainsKey($folder)) {
            $toc = @()
            try { $toc = @(Get-ChildItem -LiteralPath $folder -Filter '*.toc' -File -ErrorAction SilentlyContinue) } catch {}
            $tocFolders[$folder] = ($toc.Count -gt 0)
        }
        $isAddon = [bool]$tocFolders[$folder]
        if (-not $isAddon) {
            try {
                $text = [IO.File]::ReadAllText($full)
                if ($text -match '(?m)\b(CreateFrame|SlashCmdList|UIParent|SendChatMessage|GameTooltip)\b') { $isAddon = $true }
            } catch { }
        }
        if ($isAddon) { $result += ,$s }
    }
    return $result
}

function Disable-AcClientAddonScripts {
    # Erkannte Client-Dateien deaktivieren (.lua -> .lua.off)
    param($Paths)
    $n = 0
    foreach ($s in (Get-AcClientAddonScripts $Paths)) {
        if (-not $s.Enabled) { continue }
        Set-AcLuaScriptEnabled $s.Full $false
        Write-AcLog (T 'lua.addonDisabled' @($s.Rel))
        $n++
    }
    return $n
}

function Get-AcPlayerbotDependentModules {
    <#
      Module, die den Playerbot-Fork voraussetzen. Sie binden Header wie
      PlayerbotAI.h ein, die es im offiziellen AzerothCore nicht gibt - der Build
      scheitert dann mit "No such file or directory".
    #>
    param($Paths)
    $hits = New-Object Collections.Generic.List[string]
    foreach ($name in (Get-AcModuleNames $Paths)) {
        if ($name -match '(?i)playerbot') { continue }   # das Modul selbst bringt sie mit
        $path = Join-Path $Paths.Modules $name
        $found = $false
        foreach ($f in (Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue)) {
            if ($f.Extension -notin @('.h', '.hpp', '.cpp')) { continue }
            if ($f.Length -gt 2MB) { continue }
            try { $text = [IO.File]::ReadAllText($f.FullName) } catch { continue }
            if ($text -match '(?i)#include\s*["<](PlayerbotAI|Playerbots|PlayerbotMgr|PlayerbotAIConfig)\.h') { $found = $true; break }
        }
        if ($found) { $hits.Add($name) }
    }
    return $hits.ToArray()
}

# ---------------------------------------------------------------------
#  Modulliste sichern und wiederherstellen
# ---------------------------------------------------------------------
function Export-AcModuleList {
    <#
      Schreibt alle installierten Module mit Repository-Adresse und Branch in eine
      JSON-Datei. Der Commit wird nur zur Information mitgeschrieben - beim
      Einlesen wird bewusst der aktuelle Stand geholt.
    #>
    param($Paths, $Settings, [string]$File)
    $git = Find-AcGit
    $mods = New-Object Collections.Generic.List[object]
    foreach ($name in (Get-AcModuleNames $Paths)) {
        $path = Join-Path $Paths.Modules $name
        $url = $null; $branch = ''; $commit = ''
        if ($git -and (Test-Path (Join-Path $path '.git'))) {
            $url = Get-AcModuleRemoteUrl $path
            $branch = (Invoke-AcCapture $git 'rev-parse --abbrev-ref HEAD' $path).Output
            $commit = (Invoke-AcCapture $git 'rev-parse --short HEAD' $path).Output
        }
        $mods.Add([ordered]@{ name = $name; url = $url; branch = $branch; commit = $commit })
    }
    # Lua-Skript-Repositories mitnehmen, damit sich die Zusammenstellung
    # vollstaendig auf einem anderen Server nachbauen laesst
    $lua = New-Object Collections.Generic.List[object]
    foreach ($repo in (Get-AcLuaScriptRepos $Paths)) {
        $url = Get-AcModuleRemoteUrl $repo.FullName
        if (-not $url) { continue }
        $branch = ''; $commit = ''
        if ($git) {
            $branch = (Invoke-AcCapture $git 'rev-parse --abbrev-ref HEAD' $repo.FullName).Output
            $commit = (Invoke-AcCapture $git 'rev-parse --short HEAD' $repo.FullName).Output
        }
        $lua.Add([ordered]@{ name = $repo.Name; url = $url; branch = $branch; commit = $commit })
    }
    $doc = [ordered]@{
        generator = 'AzerothCore Server Manager'
        version   = $script:AcToolsVersion
        created   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        variant   = [string]$Settings.Variant
        coreUrl   = [string]$Settings.CoreUrl
        coreBranch= [string]$Settings.CoreBranch
        luaVersion= [string]$Settings.LuaVersion
        modules   = $mods.ToArray()
        luaScripts= $lua.ToArray()
    }
    [IO.File]::WriteAllText($File, ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Write-AcLog (T 'mod.exported' @($mods.Count, $lua.Count, $File))
    return @{ Modules = $mods.Count; Lua = $lua.Count }
}

function Read-AcModuleList {
    # Liest die Datei und liefert @{ Variant; Modules }
    param([string]$File)
    $raw = Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json
    $mods = New-Object Collections.Generic.List[object]
    foreach ($m in @($raw.modules)) {
        if (-not $m.url) { continue }
        $mods.Add([pscustomobject]@{ Name = [string]$m.name; Url = [string]$m.url; Branch = [string]$m.branch; Commit = [string]$m.commit })
    }
    $lua = New-Object Collections.Generic.List[object]
    foreach ($s in @($raw.luaScripts)) {
        if (-not $s.url) { continue }
        $lua.Add([pscustomobject]@{ Name = [string]$s.name; Url = [string]$s.url; Branch = [string]$s.branch; Commit = [string]$s.commit })
    }
    return @{ Variant = [string]$raw.variant; Modules = $mods.ToArray(); LuaScripts = $lua.ToArray(); Core = [string]$raw.coreUrl }
}


function Set-AcRepoToCommit {
    <#
      Setzt ein frisch geholtes Repository auf den in der Liste vermerkten Commit.
      Der Stand ist dann losgeloest vom Branch ("detached HEAD") - genau so, wie
      er auf dem Quellserver lief.
    #>
    param([string]$RepoPath, [string]$Commit)
    if (-not $Commit) { return $false }
    $git = Find-AcGit
    if (-not $git) { return $false }
    $r = Invoke-AcCapture $git "checkout --quiet $Commit" $RepoPath
    if ($r.ExitCode -ne 0) {
        Write-AcLog (T 'mod.commitFailed' @((Split-Path $RepoPath -Leaf), $Commit)) 'WARN'
        return $false
    }
    Write-AcLog (T 'mod.commitSet' @((Split-Path $RepoPath -Leaf), $Commit))
    return $true
}

function Import-AcModuleList {
    <#
      Holt die Module der Liste, die noch fehlen - immer den aktuellen Stand des
      angegebenen Branches. Bereits vorhandene bleiben unangetastet.
      Rueckgabe: @{ Installed; Skipped; Failed }
    #>
    param($Paths, $Modules, [switch]$UseCommit)
    $installed = New-Object Collections.Generic.List[string]
    $skipped   = New-Object Collections.Generic.List[string]
    $failed    = New-Object Collections.Generic.List[string]
    $manual    = New-Object Collections.Generic.List[object]   # SQL, die von Hand behandelt werden muss
    foreach ($m in $Modules) {
        if (Test-Path (Join-Path $Paths.Modules $m.Name)) { $skipped.Add($m.Name); continue }
        try {
            Set-AcProgress -1 (T 'ins.log.cloneMod' @($m.Name))
            $name = Install-AcModuleFromGit $Paths $m.Url $m.Branch
            if ($UseCommit -and $m.Commit) { Set-AcRepoToCommit (Join-Path $Paths.Modules $name) $m.Commit | Out-Null }
            Update-AcSubmodules (Join-Path $Paths.Modules $name) | Out-Null
            $sync = Sync-AcModuleSql (Join-Path $Paths.Modules $name) $name
            if ($sync.Optional -gt 0 -or $sync.Unknown -gt 0) {
                $manual.Add([pscustomobject]@{ Module = $name; Optional = $sync.Optional; Unknown = $sync.Unknown })
            }
            $installed.Add($name)
        } catch {
            Write-AcLog ("$($m.Name): " + $_.Exception.Message) 'WARN'
            $failed.Add($m.Name)
        }
    }
    return @{ Installed = $installed.ToArray(); Skipped = $skipped.ToArray(); Failed = $failed.ToArray(); Manual = $manual.ToArray() }
}

function Import-AcLuaScriptList {
    <#
      Holt die Lua-Skript-Repositories einer exportierten Liste nach.
      Rueckgabe: @{ Installed; Skipped; Failed; SqlPlan }
    #>
    param($Paths, $Repos, [switch]$UseCommit)
    $installed = New-Object Collections.Generic.List[string]
    $skipped   = New-Object Collections.Generic.List[string]
    $failed    = New-Object Collections.Generic.List[string]
    $dir = Get-AcLuaScriptPath $Paths
    foreach ($r in $Repos) {
        if ((Test-Path (Join-Path $dir $r.Name))) { $skipped.Add($r.Name); continue }
        try {
            $res = Install-AcLuaScriptFromGit $Paths $r.Url
            if ($UseCommit -and $r.Commit) { Set-AcRepoToCommit $res.Path $r.Commit | Out-Null }
            $installed.Add($res.Name)
        } catch {
            Write-AcLog ("$($r.Name): " + $_.Exception.Message) 'WARN'
            $failed.Add($r.Name)
        }
    }
    $plan = @()
    if ($installed.Count -gt 0) { $plan = @(Get-AcAllLuaSqlPlan $Paths) }
    return @{ Installed = $installed.ToArray(); Skipped = $skipped.ToArray(); Failed = $failed.ToArray(); SqlPlan = $plan }
}

function Test-AcIsLuaScriptRepo {
    <#
      Unterscheidet ein Lua-Skriptpaket von einem C++-Modul. Ein Modul hat eine
      CMakeLists.txt und Quelldateien; ein Skriptpaket besteht aus .lua-Dateien.
    #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    if (Test-Path (Join-Path $Path 'CMakeLists.txt')) { return $false }
    $cpp = @(Get-ChildItem $Path -File -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -in @('.cpp', '.h', '.hpp') } | Select-Object -First 1)
    if ($cpp.Count -gt 0) { return $false }
    $lua = @(Get-ChildItem $Path -Filter '*.lua' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    return ($lua.Count -gt 0)
}

function Move-AcModuleToLuaScripts {
    # Faelschlich als Modul installiertes Skriptpaket in den Lua-Ordner verschieben
    param($Paths, [string]$ModuleName)
    $src = Join-Path $Paths.Modules $ModuleName
    $dir = Get-AcLuaScriptPath $Paths
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dst = Join-Path $dir $ModuleName
    if (Test-Path $dst) { throw (T 'lua.repoExists' @($ModuleName)) }
    Move-Item $src $dst -Force
    Write-AcLog (T 'lua.movedToScripts' @($ModuleName, $dir))
    return $dst
}
