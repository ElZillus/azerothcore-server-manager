# =====================================================================
#  AzerothCore 1-Klick-Installer fuer Windows
#  Start ueber Install-AzerothCore.bat (fordert Adminrechte an)
# =====================================================================
param([string]$Root = '')

$commonCandidates = @("$PSScriptRoot\tools\AC.Common.ps1", "$PSScriptRoot\AC.Common.ps1")
$common = $commonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not $common) {
    [Windows.Forms.MessageBox]::Show("AC.Common.ps1 is missing next to the installer.", 'AzerothCore Installer', 'OK', 'Error') | Out-Null
    exit 1
}
try {
    . $common
} catch {
    [Windows.Forms.MessageBox]::Show("AC.Common.ps1 could not be loaded:" + [Environment]::NewLine + $_.Exception.Message, 'AzerothCore Installer', 'OK', 'Error') | Out-Null
    exit 1
}

# ---------------------------------------------------------------------
#  GUI
# ---------------------------------------------------------------------
$font = New-Object Drawing.Font('Segoe UI', 9.5)
$form = New-Object Windows.Forms.Form
$form.Text = T 'app.installer'
$form.Size = New-Object Drawing.Size(760, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

# ---- Seite 1: Einstellungen ----
$page1 = New-Object Windows.Forms.Panel
$page1.Dock = 'Fill'
$form.Controls.Add($page1)

function New-Label($text, $x, $y, $w, $bold) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y); $l.AutoSize = $false
    $l.Size = New-Object Drawing.Size($w, 22)
    if ($bold) { $l.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold) }
    return $l
}

# Sprachauswahl oben rechts - schaltet die gesamte Oberflaeche um
$cmbLangIns = New-Object Windows.Forms.ComboBox
$cmbLangIns.DropDownStyle = 'DropDownList'
$cmbLangIns.Location = New-Object Drawing.Point(575, 12); $cmbLangIns.Size = New-Object Drawing.Size(145, 26)
foreach ($code in @('de', 'en')) { [void]$cmbLangIns.Items.Add($script:AcLanguages[$code]) }
$cmbLangIns.SelectedIndex = @('de', 'en').IndexOf($script:AcLanguage)
$page1.Controls.Add($cmbLangIns)

$y = 15
$title = New-Label (T 'ins.title') 20 $y 700 $true
$title.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold); $title.Height = 32
$page1.Controls.Add($title); $y += 38
$intro = New-Label (T 'ins.intro') 20 $y 700 $false
$intro.Height = 60; $page1.Controls.Add($intro); $y += 70

# Ordner
$lblFolder = New-Label (T 'ins.folder') 20 $y 700 $true
$page1.Controls.Add($lblFolder); $y += 26
$txtRoot = New-Object Windows.Forms.TextBox
$txtRoot.Location = New-Object Drawing.Point(20, $y); $txtRoot.Size = New-Object Drawing.Size(580, 26)
$txtRoot.Text = if ($Root) { $Root } else { 'C:\AC' }
$btnBrowse = New-Object Windows.Forms.Button
$btnBrowse.Text = T 'ins.browse'; $btnBrowse.Location = New-Object Drawing.Point(610, ($y - 1)); $btnBrowse.Size = New-Object Drawing.Size(110, 28)
$btnBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = T 'ins.pickFolder'
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq 'OK') { $txtRoot.Text = $dlg.SelectedPath }
})
$page1.Controls.AddRange(@($txtRoot, $btnBrowse)); $y += 40

# Variante  (eigenes Panel -> eigene Optionsgruppe, unabhaengig von den Client-Daten)
$lblVariant = New-Label (T 'ins.variant') 20 $y 300 $true
$page1.Controls.Add($lblVariant); $y += 24
$pnlVariant = New-Object Windows.Forms.Panel
$pnlVariant.Location = New-Object Drawing.Point(10, $y); $pnlVariant.Size = New-Object Drawing.Size(715, 54)
$rbStandard = New-Object Windows.Forms.RadioButton
$rbStandard.Text = T 'ins.variantStandard'
$rbStandard.Location = New-Object Drawing.Point(20, 2); $rbStandard.Size = New-Object Drawing.Size(680, 24); $rbStandard.Checked = $true
$rbBots = New-Object Windows.Forms.RadioButton
$rbBots.Text = T 'ins.variantBots'
$rbBots.Location = New-Object Drawing.Point(20, 28); $rbBots.Size = New-Object Drawing.Size(690, 24)
$pnlVariant.Controls.AddRange(@($rbStandard, $rbBots))
$page1.Controls.Add($pnlVariant); $y += 60

# Realm + Port
$lblRealm = New-Label (T 'ins.realmName') 20 $y 140 $true
$page1.Controls.Add($lblRealm)
$txtRealm = New-Object Windows.Forms.TextBox
$txtRealm.Location = New-Object Drawing.Point(160, ($y - 2)); $txtRealm.Size = New-Object Drawing.Size(260, 26); $txtRealm.Text = 'AzerothCore'
$lblPort = New-Label (T 'ins.mysqlPort') 450 $y 110 $true
$page1.Controls.Add($lblPort)
$numPort = New-Object Windows.Forms.NumericUpDown
$numPort.Location = New-Object Drawing.Point(560, ($y - 2)); $numPort.Size = New-Object Drawing.Size(90, 26)
$numPort.Minimum = 1024; $numPort.Maximum = 65535
$numPort.Value = if (Test-AcPortFree 3306) { 3306 } else { 3307 }
$page1.Controls.AddRange(@($txtRealm, $numPort)); $y += 40

# Client-Daten  (eigenes Panel -> eigene Optionsgruppe)
$lblData = New-Label (T 'ins.clientData') 20 $y 500 $true
$page1.Controls.Add($lblData); $y += 24
$pnlData = New-Object Windows.Forms.Panel
$pnlData.Location = New-Object Drawing.Point(10, $y); $pnlData.Size = New-Object Drawing.Size(715, 56)
$rbDataDl = New-Object Windows.Forms.RadioButton
$rbDataDl.Text = T 'ins.dataDownload'
$rbDataDl.Location = New-Object Drawing.Point(20, 2); $rbDataDl.Size = New-Object Drawing.Size(680, 24); $rbDataDl.Checked = $true
$rbDataOwn = New-Object Windows.Forms.RadioButton
$rbDataOwn.Text = T 'ins.dataOwn'
$rbDataOwn.Location = New-Object Drawing.Point(20, 28); $rbDataOwn.Size = New-Object Drawing.Size(290, 24)
$txtData = New-Object Windows.Forms.TextBox
$txtData.Location = New-Object Drawing.Point(315, 27); $txtData.Size = New-Object Drawing.Size(275, 26); $txtData.Enabled = $false
$btnData = New-Object Windows.Forms.Button
$btnData.Text = '...'; $btnData.Location = New-Object Drawing.Point(600, 26); $btnData.Size = New-Object Drawing.Size(40, 28); $btnData.Enabled = $false
$btnData.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $txtData.Text = $d.SelectedPath } })
$rbDataOwn.Add_CheckedChanged({ $txtData.Enabled = $rbDataOwn.Checked; $btnData.Enabled = $rbDataOwn.Checked })
$pnlData.Controls.AddRange(@($rbDataDl, $rbDataOwn, $txtData, $btnData))
$page1.Controls.Add($pnlData); $y += 62

$lblCpu = New-Label (T 'ins.buildProfile') 20 $y 260 $true
$cmbCpu = New-Object Windows.Forms.ComboBox
$cmbCpu.DropDownStyle = 'DropDownList'; $cmbCpu.Location = New-Object Drawing.Point(290, ($y - 2)); $cmbCpu.Size = New-Object Drawing.Size(300, 26)
foreach ($k in @('full', 'balanced', 'background')) { [void]$cmbCpu.Items.Add((T ('ins.cpu.' + $k))) }
$cmbCpu.SelectedIndex = 0
$page1.Controls.AddRange(@($lblCpu, $cmbCpu)); $y += 34

$chkShortcut = New-Object Windows.Forms.CheckBox
$chkShortcut.Text = T 'ins.shortcut'
$chkShortcut.Location = New-Object Drawing.Point(20, $y); $chkShortcut.Size = New-Object Drawing.Size(500, 24); $chkShortcut.Checked = $true
$page1.Controls.Add($chkShortcut); $y += 40

$btnStart = New-Object Windows.Forms.Button
$btnStart.Text = T 'ins.start'
$btnStart.Location = New-Object Drawing.Point(20, $y); $btnStart.Size = New-Object Drawing.Size(220, 40)
$btnStart.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$btnStart.Tag = 'primary'
$page1.Controls.Add($btnStart)
$lblAdmin = New-Label '' 260 ($y + 8) 460 $false
if (-not (Test-AcIsAdmin)) { $lblAdmin.Text = T 'ins.noAdmin'; $lblAdmin.ForeColor = 'DarkRed' }
$page1.Controls.Add($lblAdmin)

$applyInsTexts = {
    $form.Text = T 'app.installer'
    $title.Text = T 'ins.title'; $intro.Text = T 'ins.intro'
    $lblFolder.Text = T 'ins.folder'; $btnBrowse.Text = T 'ins.browse'
    $lblVariant.Text = T 'ins.variant'
    $rbStandard.Text = T 'ins.variantStandard'; $rbBots.Text = T 'ins.variantBots'
    $lblRealm.Text = T 'ins.realmName'; $lblPort.Text = T 'ins.mysqlPort'
    $lblData.Text = T 'ins.clientData'
    $rbDataDl.Text = T 'ins.dataDownload'; $rbDataOwn.Text = T 'ins.dataOwn'
    $chkShortcut.Text = T 'ins.shortcut'; $btnStart.Text = T 'ins.start'
    $lblCpu.Text = T 'ins.buildProfile'
    $selCpu = $cmbCpu.SelectedIndex
    $cmbCpu.Items.Clear()
    foreach ($k in @('full', 'balanced', 'background')) { [void]$cmbCpu.Items.Add((T ('ins.cpu.' + $k))) }
    $cmbCpu.SelectedIndex = $(if ($selCpu -ge 0) { $selCpu } else { 0 })
    if (-not (Test-AcIsAdmin)) { $lblAdmin.Text = T 'ins.noAdmin' }
    $btnManager.Text = T 'ins.openManager'; $btnRetry.Text = T 'ins.retry'; $btnClose.Text = T 'btn.close'
}
$cmbLangIns.Add_SelectedIndexChanged({
    $code = @('de', 'en')[$cmbLangIns.SelectedIndex]
    if ($code -eq $script:AcLanguage) { return }
    Set-AcLanguage $code
    $script:InstallerLanguage = $code
    & $applyInsTexts
})

# ---- Seite 2: Fortschritt ----
$page2 = New-Object Windows.Forms.Panel
$page2.Dock = 'Fill'; $page2.Visible = $false
$form.Controls.Add($page2)

$lblStep = New-Object Windows.Forms.Label
$lblStep.Location = New-Object Drawing.Point(20, 15); $lblStep.Size = New-Object Drawing.Size(700, 26)
$lblStep.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblSub = New-Object Windows.Forms.Label
$lblSub.Location = New-Object Drawing.Point(20, 44); $lblSub.Size = New-Object Drawing.Size(700, 22)
$bar = New-Object Windows.Forms.ProgressBar
$bar.Location = New-Object Drawing.Point(20, 70); $bar.Size = New-Object Drawing.Size(700, 22)
$log = New-Object Windows.Forms.RichTextBox
$log.Location = New-Object Drawing.Point(20, 100); $log.Size = New-Object Drawing.Size(700, 430)
$log.ReadOnly = $true; $log.Font = New-Object Drawing.Font('Consolas', 9); $log.BackColor = 'Black'; $log.ForeColor = 'Gainsboro'
$log.DetectUrls = $false; $log.WordWrap = $false; $log.ScrollBars = 'Both'
$btnManager = New-Object Windows.Forms.Button
$btnManager.Tag = 'primary'; $btnManager.Text = T 'ins.openManager'; $btnManager.Location = New-Object Drawing.Point(20, 545); $btnManager.Size = New-Object Drawing.Size(220, 36); $btnManager.Enabled = $false
$btnRetry = New-Object Windows.Forms.Button
$btnRetry.Text = T 'ins.retry'; $btnRetry.Location = New-Object Drawing.Point(250, 545); $btnRetry.Size = New-Object Drawing.Size(170, 36); $btnRetry.Visible = $false
$btnClose = New-Object Windows.Forms.Button
$btnClose.Text = T 'btn.close'; $btnClose.Location = New-Object Drawing.Point(600, 545); $btnClose.Size = New-Object Drawing.Size(120, 36); $btnClose.Enabled = $false
$btnClose.Add_Click({ $form.Close() })
$page2.Controls.AddRange(@($lblStep, $lblSub, $bar, $log, $btnManager, $btnRetry, $btnClose))

$script:AcLogHandler = {
    param($line, $level)
    $color = switch ($level) { 'WARN' { 'Orange' } 'ERROR' { 'Tomato' } 'CMD' { 'DeepSkyBlue' } 'STEP' { 'LightGreen' } default { 'Gainsboro' } }
    if ($log.TextLength -gt 4000000) { $log.Clear() }
    $log.SelectionStart = $log.TextLength; $log.SelectionColor = $color
    $log.AppendText($line + "`r`n")
    $log.SelectionStart = $log.TextLength; $log.ScrollToCaret()
    Invoke-AcDoEvents
}
$script:AcProgressHandler = {
    param($pct, $text)
    if ($pct -lt 0) { $bar.Style = 'Marquee' } else { $bar.Style = 'Continuous'; $bar.Value = [Math]::Min(100, [Math]::Max(0, $pct)) }
    if ($text) { $lblSub.Text = $text }
    Invoke-AcDoEvents
}

# ---------------------------------------------------------------------
#  Installationsschritte
# ---------------------------------------------------------------------
$script:P = $null           # Pfade
$script:S = $null           # Einstellungen
$script:MySqlState = $null  # laufender mysqld

function Complete-Step($name) {
    $done = @($script:S.CompletedSteps | Where-Object { $_ })
    if ($done -notcontains $name) { $done += $name }
    $script:S.CompletedSteps = $done
    Save-AcSettings $script:P.Root $script:S
}
function Test-StepDone($name) { return (@($script:S.CompletedSteps | Where-Object { $_ }) -contains $name) }

function Step-Prepare {
    $p = $script:P
    foreach ($d in @($p.Root, $p.Deps, $p.Downloads, $p.Logs, $p.Tools, $p.Data)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    # Werkzeuge in den Serverordner kopieren - ALLE Skripte, keine feste Liste,
    # sonst fehlen neu hinzugekommene Dateien im Zielordner
    $srcTools = if (Test-Path "$PSScriptRoot\tools\AC.Common.ps1") { "$PSScriptRoot\tools" } else { $PSScriptRoot }
    $copied = 0
    foreach ($src in (Get-ChildItem $srcTools -Filter '*.ps1' -File)) {
        $dst = Join-Path $p.Tools $src.Name
        if ($src.FullName -eq $dst) { continue }
        Copy-Item $src.FullName $dst -Force
        $copied++
    }
    # Pflichtdateien pruefen, damit ein unvollstaendiges Paket sofort auffaellt
    foreach ($req in @('AC.Common.ps1', 'AC.Lang.ps1', 'AC.Char.ps1', 'AC.Theme.ps1', 'AzerothCore-Manager.ps1')) {
        if (-not (Test-Path (Join-Path $p.Tools $req))) { throw (T 'ins.log.toolMissing' @($req, $srcTools)) }
    }
    Write-AcLog (T 'ins.log.toolsCopied' @($copied, $p.Tools))
    if ((Resolve-Path $PSCommandPath).Path -ne (Join-Path $p.Tools 'AzerothCore-Installer.ps1')) { Copy-Item $PSCommandPath (Join-Path $p.Tools 'AzerothCore-Installer.ps1') -Force }
    $bat = @'
@echo off
title AzerothCore Server-Manager
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tools\AzerothCore-Manager.ps1" -Root "%~dp0."
if %errorlevel% neq 0 pause
'@
    [IO.File]::WriteAllText((Join-Path $p.Root 'Start-Manager.bat'), $bat, [Text.Encoding]::ASCII)
    $bat2 = @'
@echo off
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tools\AzerothCore-Installer.ps1" -Root "%~dp0."
pause
'@
    [IO.File]::WriteAllText((Join-Path $p.Root 'Resume-Installation.bat'), $bat2, [Text.Encoding]::ASCII)
    # frueher hiess die Datei deutsch - Altbestand entfernen
    $legacy = Join-Path $p.Root 'Installer-erneut-ausfuehren.bat'
    if (Test-Path $legacy) { Remove-Item $legacy -Force -ErrorAction SilentlyContinue }
    Write-AcLog (T 'ins.log.prepared' @($p.Root, $script:AcToolsVersion, $p.Tools))
}

function Step-Dependencies {
    $winget = Find-AcWinget
    if (-not $winget) { throw (T 'ins.log.wingetMissing') }

    Install-AcWingetPackage @($script:AcWingetPackages.VCRedist) 'Visual C++ Redistributable' | Out-Null

    if (-not (Find-AcGit)) { Install-AcWingetPackage @($script:AcWingetPackages.Git) 'Git' | Out-Null } else { Write-AcLog (T 'ins.log.present' @('Git', (Find-AcGit))) }
    if (-not (Find-AcGit)) { throw (T 'ins.log.installFailed' @('Git')) }

    if (-not (Find-AcCMake)) { Install-AcWingetPackage @($script:AcWingetPackages.CMake) 'CMake' | Out-Null } else { Write-AcLog (T 'ins.log.present' @('CMake', (Find-AcCMake))) }
    if (-not (Find-AcCMake)) { throw (T 'ins.log.installFailed' @('CMake')) }

    $ssl = Find-AcOpenSsl
    if ($ssl) { Write-AcLog (T 'ins.log.present' @('OpenSSL', $ssl)) } else { Install-AcOpenSsl | Out-Null; $ssl = Find-AcOpenSsl }
    if (-not $ssl) {
        throw (T 'ins.log.opensslManual' @("`n"))
    }
    $sslVer = Get-AcOpenSslVersion $ssl
    if ($sslVer) {
        Write-AcLog (T 'ins.log.opensslVersion' @($sslVer))
        if ($sslVer -match '^([0-9]+)\.') {
            $sslMajor = [int]$Matches[1]
            if ($sslMajor -lt 3) { throw (T 'ins.log.opensslOld' @($sslVer)) }
            if ($sslMajor -ge 4) { Write-AcLog (T 'ins.log.openssl4' @($sslVer)) 'WARN' }
        }
    }
    $script:S.OpenSslRoot = $ssl

    $vs = Find-AcVisualStudio
    if (-not $vs) {
        Write-AcLog (T 'ins.log.vsInstall')
        Install-AcWingetPackage @($script:AcWingetPackages.VSBuild) 'Visual Studio 2022 Build Tools' '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' | Out-Null
        $vs = Find-AcVisualStudio
    } else { Write-AcLog (T 'ins.log.present' @('Visual Studio 2022 (C++)', $vs)) }
    if (-not $vs) { throw (T 'ins.log.vsMissing') }
    $script:S.VsInstallPath = $vs
    Save-AcSettings $script:P.Root $script:S
}

function Step-Boost {
    $p = $script:P
    $existing = Find-AcBoost $p.Deps
    if ($existing) { $script:S.BoostRoot = $existing; Save-AcSettings $p.Root $script:S; Write-AcLog (T 'ins.log.present' @('Boost', $existing)); return }
    $ver = $script:AcVersions.BoostVersion; $verU = $ver -replace '\.', '_'; $ts = $script:AcVersions.BoostToolset
    $file = "boost_${verU}-msvc-${ts}-64.exe"
    $out = Join-Path $p.Downloads $file
    $boostUrls = @(Select-AcWorkingUrls @(
        "https://sourceforge.net/projects/boost/files/boost-binaries/$ver/$file/download",
        "https://github.com/userdocs/boost/releases/download/boost-$ver/$file"
    ) 2 'Boost')
    Invoke-AcDownload -Urls $boostUrls -OutFile $out -Description "Boost $ver"
    $target = Join-Path $p.Deps (Get-AcBoostDirName)
    Set-AcProgress -1 (T 'ins.log.boostInstall')
    Invoke-AcProcess -FilePath $out -ArgumentList "/VERYSILENT /SP- /SUPPRESSMSGBOXES /NORESTART /DIR=`"$target`"" -TimeoutSeconds 1800
    $found = Find-AcBoost $p.Deps
    if (-not $found) { throw (T 'ins.log.boostFailed' @($target)) }
    $script:S.BoostRoot = $found; Save-AcSettings $p.Root $script:S
}

function Step-MySql {
    $p = $script:P; $s = $script:S
    $mysqld = Get-AcMySqlExe $p 'mysqld.exe'
    if (-not (Test-Path $mysqld)) {
        # Weg 1: ein manuell abgelegtes ZIP (mysql-8.x.x-winx64.zip) in deps\downloads
        $manual = @(Get-ChildItem $p.Downloads -Filter 'mysql-*winx64*.zip' -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1)
        $zip = $null
        if ($manual.Count -gt 0 -and $manual[0].Length -gt 50MB) { $zip = $manual[0].FullName; Write-AcLog (T 'ins.log.useArchive' @($zip)) }
        # Weg 2: Download von mysql.com
        if (-not $zip) {
            $out = Join-Path $p.Downloads 'mysql-winx64.zip'
            try { $zip = Invoke-AcDownload -Urls (Get-AcMySqlDownloadUrls) -OutFile $out -Description 'MySQL Server' }
            catch { Write-AcLog (T 'ins.log.mysqlDlFail' @($_.Exception.Message)) 'WARN' }
        }
        if ($zip) {
            Expand-AcZip -ZipPath $zip -Destination $p.MySql -StripTopLevel
        } else {
            # Weg 3: winget-Installation nach Program Files, Dateien in den Serverordner kopieren
            if (-not (Install-AcMySqlViaWinget $p)) {
                throw (T 'ins.log.mysqlManual' @("`n", $p.Downloads))
            }
        }
        if (-not (Test-Path $mysqld)) { throw (T 'ins.log.mysqlIncomplete' @('bin\mysqld.exe')) }
        if (-not (Test-Path (Join-Path $p.MySql 'lib\libmysql.lib'))) { throw (T 'ins.log.mysqlIncomplete' @('lib\libmysql.lib')) }
    } else { Write-AcLog (T 'ins.log.mysqlPresent') }

    if (-not (Test-Path $p.MySqlIni)) {
        $base = ConvertTo-AcSlashPath $p.MySql
        $ini = @"
[mysqld]
basedir="$base"
datadir="$base/data"
port=$($s.MySqlPort)
bind-address=127.0.0.1
max_allowed_packet=128M
innodb_buffer_pool_size=512M
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
log-error="$base/mysql-error.log"
mysqlx=OFF

[client]
port=$($s.MySqlPort)
"@
        [IO.File]::WriteAllText($p.MySqlIni, $ini, (New-Object Text.UTF8Encoding($false)))
    }

    $freshInit = $false
    if (-not (Test-Path (Join-Path $p.MySqlData 'mysql'))) {
        if (-not (Test-AcPortFree $s.MySqlPort)) { throw (T 'ins.log.portBusy' @($s.MySqlPort)) }
        Write-AcLog (T 'ins.log.mysqlInit')
        Set-AcProgress -1 (T 'ins.log.mysqlInit')
        Invoke-AcProcess -FilePath $mysqld -ArgumentList "--defaults-file=`"$($p.MySqlIni)`" --initialize-insecure --console" -WorkingDirectory $p.MySql
        Write-AcMySqlClientCnf $p '' $s.MySqlPort
        $freshInit = $true
    } elseif (-not (Test-Path $p.MySqlCnf)) {
        Write-AcMySqlClientCnf $p $s.MySqlRootPassword $s.MySqlPort
    }

    $script:MySqlState = Start-AcMySql $p
    if (-not $s.DbPassword) { $s.DbPassword = New-AcPassword 16 }
    $rootPw = if ($freshInit -or -not $s.MySqlRootPassword) { New-AcPassword 20 } else { $s.MySqlRootPassword }
    $dbs = @('acore_auth', 'acore_characters', 'acore_world')
    if ($s.Variant -eq 'playerbots') { $dbs += 'acore_playerbots' }
    $sql = ''
    foreach ($db in $dbs) { $sql += "CREATE DATABASE IF NOT EXISTS ``$db`` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`n" }
    foreach ($h in @('%', 'localhost')) {
        $sql += "CREATE USER IF NOT EXISTS '$($s.DbUser)'@'$h' IDENTIFIED BY '$($s.DbPassword)';`n"
        $sql += "ALTER USER '$($s.DbUser)'@'$h' IDENTIFIED BY '$($s.DbPassword)';`n"
        foreach ($db in $dbs) { $sql += "GRANT ALL PRIVILEGES ON ``$db``.* TO '$($s.DbUser)'@'$h';`n" }
    }
    foreach ($h in @('%', 'localhost')) { $sql += "GRANT RELOAD ON *.* TO '$($s.DbUser)'@'$h';`n" }
    $sql += "FLUSH PRIVILEGES;`n"
    if ($freshInit -or $rootPw -ne $s.MySqlRootPassword) { $sql += "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPw';`n" }
    Write-AcLog (T 'ins.log.createDb')
    Invoke-AcMySql $p $sql | Out-Null
    $s.MySqlRootPassword = $rootPw
    Write-AcMySqlClientCnf $p $rootPw $s.MySqlPort
    Save-AcSettings $p.Root $s
    if (-not (Test-AcMySqlAlive $p)) { throw (T 'ins.log.mysqlAfterPw') }
    Write-AcLog (T 'ins.log.dbReady' @($s.DbUser, $s.MySqlPort))
}

function Step-Clone {
    $p = $script:P; $s = $script:S
    $git = Find-AcGit

    # --- Core ---
    if (-not (Test-Path (Join-Path $p.Source '.git'))) {
        if (Test-Path $p.Source) { Remove-Item $p.Source -Recurse -Force }
        Set-AcProgress -1 (T 'ins.log.cloneCore' @($s.CoreBranch))
        Invoke-AcProcess -FilePath $git -ArgumentList "clone --branch $($s.CoreBranch) --progress --recurse-submodules `"$($s.CoreUrl)`" `"$($p.Source)`"" -WorkingDirectory $p.Root | Out-Null
    } else {
        # Bereits vorhandener Quellcode kann aus einem frueheren Anlauf stammen und
        # Tage alt sein - vor dem Bauen auf den neuesten Stand bringen
        Write-AcLog (T 'ins.log.sourcePresent')
        Set-AcProgress -1 (T 'ins.log.pullCore')
        $r = Invoke-AcCapture $git 'pull --ff-only' $p.Source
        if ($r.ExitCode -ne 0) { Write-AcLog (T 'ins.log.pullFailed' @('core', $r.Error)) 'WARN' }
    }

    # --- Module der gewaehlten Variante ---
    foreach ($m in @($s.Modules)) {
        if (-not $m) { continue }
        $target = Join-Path $p.Modules $m.Name
        if (Test-Path (Join-Path $target '.git')) {
            Write-AcLog (T 'ins.log.modPresent' @($m.Name))
            $r = Invoke-AcCapture $git 'pull --ff-only' $target
            if ($r.ExitCode -ne 0) { Write-AcLog (T 'ins.log.pullFailed' @($m.Name, $r.Error)) 'WARN' }
            continue
        }
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Set-AcProgress -1 (T 'ins.log.cloneMod' @($m.Name))
        Invoke-AcProcess -FilePath $git -ArgumentList "clone --branch $($m.Branch) --progress --recurse-submodules `"$($m.Url)`" `"$target`"" -WorkingDirectory $p.Modules | Out-Null
    }

    # fehlende Submodule nachholen (aeltere Installationen, abgebrochene Klone)
    Update-AcAllSubmodules $p | Out-Null

    # gebauten Stand protokollieren, damit spaeter nachvollziehbar ist, was drin steckt
    foreach ($repo in (Get-AcGitRepos $p)) {
        $h = (Invoke-AcCapture $git 'rev-parse --short HEAD' $repo.Path).Output
        $dt = (Invoke-AcCapture $git 'log -1 --format=%cd --date=short' $repo.Path).Output
        Write-AcLog (T 'ins.log.buildingCommit' @($repo.Name, $h, $dt))
    }

    # SQL-Dateien der Module pruefen und ggf. in den automatisch importierten Pfad einbinden
    Sync-AcAllModuleSql $p | Out-Null
}

function Step-Configure {
    Sync-AcAllModuleSql $script:P | Out-Null
    Invoke-AcConfigure $script:P $script:S
}
function Step-Build {
    Invoke-AcBuild $script:P $script:S
    Save-AcBuiltModules $script:P $script:S
}

function Step-ClientData {
    $p = $script:P; $s = $script:S
    $ok = @('dbc', 'maps', 'vmaps', 'mmaps') | ForEach-Object { Test-Path (Join-Path $p.Data $_) }
    if ($ok -notcontains $false) { Write-AcLog (T 'ins.log.dataPresent'); return }
    if ($s.ClientDataSource) {
        Write-AcLog (T 'ins.log.dataCopy' @($s.ClientDataSource))
        Set-AcProgress -1 (T 'ins.log.dataCopyShort')
        foreach ($d in @('dbc', 'maps', 'vmaps', 'mmaps', 'Cameras')) {
            $src = Join-Path $s.ClientDataSource $d
            if (Test-Path $src) { Copy-Item $src (Join-Path $p.Data $d) -Recurse -Force }
        }
    } else {
        Write-AcLog (T 'ins.log.dataLookup')
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/wowgaming/client-data/releases/latest' -Headers @{ 'User-Agent' = $script:AcUserAgent }
        $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' } | Sort-Object { if ($_.name -ieq 'data.zip') { 0 } else { 1 } }) | Select-Object -First 1
        if (-not $asset) { throw (T 'ins.log.dataNoZip') }
        $out = Join-Path $p.Downloads ("client-data-" + $rel.tag_name + ".zip")
        Invoke-AcDownload -Urls @($asset.browser_download_url) -OutFile $out -Description (T 'ins.log.clientData' @($rel.tag_name))
        Expand-AcZip -ZipPath $out -Destination $p.Data
    }
    $ok = @('dbc', 'maps', 'vmaps', 'mmaps') | ForEach-Object { Test-Path (Join-Path $p.Data $_) }
    if ($ok -contains $false) { throw (T 'ins.log.dataIncomplete' @($p.Data)) }
}

function Step-Database {
    $p = $script:P; $s = $script:S
    if (-not (Test-AcMySqlAlive $p)) { $script:MySqlState = Start-AcMySql $p }
    Invoke-AcDbImport $p
    $realm = $s.RealmName -replace "'", "''"
    Invoke-AcMySql $p "UPDATE acore_auth.realmlist SET name='$realm', address='127.0.0.1', localAddress='127.0.0.1' WHERE id=1;" | Out-Null
    Write-AcLog (T 'ins.log.realmSet' @($s.RealmName))
}

function Step-Finish {
    $p = $script:P
    Stop-AcMySql $p $script:MySqlState; $script:MySqlState = $null
    # Aufraeumen: Downloads, Entpack-Reste und leere Ordner
    try { Remove-AcInstallLeftovers $p | Out-Null } catch { Write-AcLog $_.Exception.Message 'WARN' }
    if ($script:S.CreateShortcut) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'AzerothCore Manager.lnk'))
            $lnk.TargetPath = Join-Path $p.Root 'Start-Manager.bat'
            $lnk.WorkingDirectory = $p.Root
            $lnk.Description = 'AzerothCore Server-Manager'
            $lnk.Save()
            Write-AcLog (T 'ins.log.shortcut')
        } catch { Write-AcLog (T 'ins.log.shortcutFail' @($_.Exception.Message)) 'WARN' }
    }
}

$script:Steps = @(
    @{ Id = 'prepare'; TitleKey = 'ins.step.prepare'; Action = { Step-Prepare } },
    @{ Id = 'deps'; TitleKey = 'ins.step.deps'; Action = { Step-Dependencies } },
    @{ Id = 'boost'; TitleKey = 'ins.step.boost'; Action = { Step-Boost } },
    @{ Id = 'mysql'; TitleKey = 'ins.step.mysql'; Action = { Step-MySql } },
    @{ Id = 'clone'; TitleKey = 'ins.step.clone'; Action = { Step-Clone } },
    @{ Id = 'configure'; TitleKey = 'ins.step.configure'; Action = { Step-Configure } },
    @{ Id = 'build'; TitleKey = 'ins.step.build'; Action = { Step-Build } },
    @{ Id = 'data'; TitleKey = 'ins.step.data'; Action = { Step-ClientData } },
    @{ Id = 'database'; TitleKey = 'ins.step.database'; Action = { Step-Database } },
    @{ Id = 'finish'; TitleKey = 'ins.step.finish'; Action = { Step-Finish } }
)

function Invoke-Installation {
    $btnRetry.Visible = $false; $btnClose.Enabled = $false
    $total = $script:Steps.Count
    for ($i = 0; $i -lt $total; $i++) {
        $st = $script:Steps[$i]
        $lblStep.Text = T 'ins.stepOf' @(($i + 1), $total, (T $st.TitleKey))
        # 'prepare' laeuft immer (kopiert die aktuellen Werkzeuge nach <Ordner>\tools), 'finish' ebenfalls
        if ((Test-StepDone $st.Id) -and $st.Id -notin @('prepare', 'finish')) { Write-AcLog (T 'ins.skipped' @((T $st.TitleKey))) 'STEP'; continue }
        Write-AcLog ("=== " + (T $st.TitleKey) + " ===") 'STEP'
        Set-AcProgress ([int](($i * 100) / $total)) (T $st.TitleKey)
        try {
            & $st.Action
            Complete-Step $st.Id
        } catch {
            Write-AcLog ("[" + (T $st.TitleKey) + "] " + $_.Exception.Message) 'ERROR'
            if ($_.ScriptStackTrace) { Write-AcLog $_.ScriptStackTrace 'ERROR' }
            $lblStep.Text = T 'ins.failedStep' @((T $st.TitleKey))
            $lblSub.Text = T 'ins.failedHint'
            $bar.Style = 'Continuous'
            try { if ($script:MySqlState) { Stop-AcMySql $script:P $script:MySqlState; $script:MySqlState = $null } } catch {}
            $btnRetry.Visible = $true; $btnClose.Enabled = $true
            return
        }
    }
    Set-AcProgress 100 (T 'ins.finished')
    $lblStep.Text = T 'ins.done'
    $lblSub.Text = T 'ins.doneHint' @($script:P.Root)
    Write-AcLog (T 'ins.doneLog') 'STEP'
    $btnManager.Enabled = $true; $btnClose.Enabled = $true
}

$btnStart.Add_Click({
    $root = $txtRoot.Text.Trim()
    try { $root = [IO.Path]::GetFullPath($root).TrimEnd('\') } catch {}
    if (-not $root -or $root -notmatch '^[A-Za-z]:\\') { [Windows.Forms.MessageBox]::Show((T 'ins.badFolder')) | Out-Null; return }
    if ($root -match '\s') { if ([Windows.Forms.MessageBox]::Show((T 'ins.spaceWarn'), (T 'word.warning'), 'YesNo', 'Warning') -ne 'Yes') { return } }
    if ($rbDataOwn.Checked -and -not (Test-Path (Join-Path $txtData.Text 'dbc'))) { [Windows.Forms.MessageBox]::Show((T 'ins.noDbc')) | Out-Null; return }
    if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root | Out-Null }

    $script:P = Get-AcPaths $root
    $script:S = Get-AcSettings $root
    Set-AcLanguage $script:AcLanguage   # im Assistenten gewaehlte Sprache gewinnt
    $resume = $false
    if (@($script:S.CompletedSteps | Where-Object { $_ }).Count -gt 0) {
        $r = [Windows.Forms.MessageBox]::Show((T 'ins.resume' @("`n")), (T 'ins.resumeTitle'), 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { return }
        $resume = ($r -eq 'Yes')
        if (-not $resume) { $script:S.CompletedSteps = @() }
    }
    if (-not $resume) {
        $variant = if ($rbBots.Checked) { 'playerbots' } else { 'standard' }
        $repo = $script:AcRepos[$variant]
        $script:S.Variant = $variant
        $script:S.CoreUrl = $repo.Core; $script:S.CoreBranch = $repo.Branch
        $script:S.Modules = @($repo.Modules)
        $script:S.RealmName = $txtRealm.Text.Trim()
        $script:S.MySqlPort = [int]$numPort.Value
        $script:S.ClientDataSource = if ($rbDataOwn.Checked) { $txtData.Text.Trim() } else { '' }
        $script:S.CreateShortcut = [bool]$chkShortcut.Checked
        $script:S.BuildProfile = @('full', 'balanced', 'background')[$cmbCpu.SelectedIndex]
    }
    $script:S.Language = $script:AcLanguage
    Save-AcSettings $root $script:S
    $script:AcLogFile = Join-Path $script:P.Logs 'install.log'
    if (-not (Test-Path $script:P.Logs)) { New-Item -ItemType Directory -Path $script:P.Logs | Out-Null }

    $page1.Visible = $false; $page2.Visible = $true
    Write-AcLog (T 'ins.log.start' @($root, $script:S.Variant, $script:S.CoreBranch)) 'STEP'
    Invoke-Installation
})
$btnRetry.Add_Click({ Invoke-Installation })
$btnManager.Add_Click({
    Start-Process -FilePath (Join-Path $script:P.Root 'Start-Manager.bat') -WorkingDirectory $script:P.Root
    $form.Close()
})
$form.Add_FormClosing({
    if ($script:MySqlState) { try { Stop-AcMySql $script:P $script:MySqlState } catch {} }
})

[Windows.Forms.Application]::EnableVisualStyles()
$form.Add_Shown({ Update-AcTheme $form 'light' })
[void]$form.ShowDialog()
