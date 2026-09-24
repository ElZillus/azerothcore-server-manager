# =====================================================================
#  AzerothCore Server-Manager (GUI)
#  Start ueber Start-Manager.bat im Serverordner (keine Adminrechte noetig)
# =====================================================================
param([string]$Root = '')

# Gemeinsame Funktionen laden. Schlaegt das fehl, bricht der Manager mit einer
# einzelnen Meldung ab - sonst laufen Hunderte Folgefehler durch die Konsole.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    . "$PSScriptRoot\AC.Common.ps1"
} catch {
    $msg = "AC.Common.ps1 could not be loaded from $PSScriptRoot" + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message
    [Windows.Forms.MessageBox]::Show($msg, 'AzerothCore Server Manager', 'OK', 'Error') | Out-Null
    exit 1
}
# Der Manager traegt seine eigene Version und vergleicht sie mit AC.Common.
# So faellt sofort auf, wenn nur ein Teil der Dateien ersetzt wurde.
$script:AcManagerVersion = '2026-09-06.94'
if (-not (Get-Command Get-AcPaths -ErrorAction SilentlyContinue)) {
    [Windows.Forms.MessageBox]::Show("AC.Common.ps1 in $PSScriptRoot is incomplete or outdated.", 'AzerothCore Server Manager', 'OK', 'Error') | Out-Null
    exit 1
}
if ($script:AcToolsVersion -ne $script:AcManagerVersion) {
    [Windows.Forms.MessageBox]::Show(
        "The scripts in $PSScriptRoot do not belong to the same version." + [Environment]::NewLine +
        "AzerothCore-Manager.ps1 = $($script:AcManagerVersion), AC.Common.ps1 = $($script:AcToolsVersion)" + [Environment]::NewLine + [Environment]::NewLine +
        "Copy ALL .ps1 files from the package into that folder.",
        'AzerothCore Server Manager', 'OK', 'Error') | Out-Null
    exit 1
}
# Pflichtfunktionen aus den Teildateien - fehlt eine, ist eine Datei veraltet
$acNeeded = @('Get-AcLuaScriptPath', 'Get-AcLuaScripts', 'Get-AcCharacters', 'Get-AcModuleSqlFiles', 'Update-AcTheme')
$acLost = @($acNeeded | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
if ($acLost.Count -gt 0) {
    [Windows.Forms.MessageBox]::Show(
        "These functions are missing in $PSScriptRoot :" + [Environment]::NewLine + ($acLost -join ', ') + [Environment]::NewLine + [Environment]::NewLine +
        "One of the script files is outdated - copy ALL .ps1 files from the package into that folder.",
        'AzerothCore Server Manager', 'OK', 'Error') | Out-Null
    exit 1
}

if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }
try { $Root = [IO.Path]::GetFullPath($Root).TrimEnd('\') } catch {}
$script:P = Get-AcPaths $Root
$script:S = Get-AcSettings $Root
if (-not (Test-Path $script:P.Settings) -or -not (Test-Path (Join-Path $script:P.Bin 'worldserver.exe'))) {
    $r = [Windows.Forms.MessageBox]::Show((T 'start.noServer' @($Root, "`n")), (T 'app.manager'), 'YesNo', 'Warning')
    if ($r -eq 'Yes') {
        $inst = Join-Path $script:P.Root 'Resume-Installation.bat'
        if (-not (Test-Path $inst)) { $inst = Join-Path $script:P.Root 'Installer-erneut-ausfuehren.bat' }   # alter Name
        if (Test-Path $inst) {
            Start-Process $inst -WorkingDirectory $script:P.Root
        } else {
            [Windows.Forms.MessageBox]::Show((T 'start.runInstaller'), (T 'app.manager'), 'OK', 'Information') | Out-Null
        }
    }
    exit
}
$script:AcLogFile = Join-Path $script:P.Logs 'manager.log'

# ---------------------------------------------------------------------
#  Nur eine Instanz je Serverordner
#
#  Zwei Manager auf demselben Ordner wuerden dieselbe Datenbank starten und
#  stoppen und sich gegenseitig die Serverprozesse wegnehmen.
# ---------------------------------------------------------------------
$acKey = ($script:P.Root.ToLower() -replace '[^a-z0-9]', '_')
if ($acKey.Length -gt 60) { $acKey = $acKey.Substring($acKey.Length - 60) }
$acCreatedNew = $false
$script:AcMutex = New-Object Threading.Mutex($true, ("Local\AzerothCoreManager_" + $acKey), [ref]$acCreatedNew)
if (-not $acCreatedNew) {
    # Immer eine sichtbare Meldung zeigen - sonst wirkt es, als passiere nichts.
    # Erst nach dem Wegklicken wird das vorhandene Fenster nach vorne geholt.
    $msgForm = New-Object Windows.Forms.Form
    $msgForm.TopMost = $true; $msgForm.ShowInTaskbar = $false
    $msgForm.StartPosition = 'CenterScreen'; $msgForm.Size = New-Object Drawing.Size(1, 1)
    $msgForm.FormBorderStyle = 'None'; $msgForm.Opacity = 0
    $msgForm.Show()
    [Windows.Forms.MessageBox]::Show($msgForm, (T 'app.alreadyRunning' @($script:P.Root, "`r`n")), (T 'app.manager'), 'OK', 'Information') | Out-Null
    $msgForm.Close()
    $pidFile = Join-Path $script:P.Root '.manager-pid'
    if (Test-Path $pidFile) {
        try {
            $otherPid = [int](Get-Content $pidFile -Raw).Trim()
            if (Get-Process -Id $otherPid -ErrorAction SilentlyContinue) {
                Add-Type -AssemblyName Microsoft.VisualBasic
                [Microsoft.VisualBasic.Interaction]::AppActivate($otherPid)
            }
        } catch {}
    }
    exit 0
}
try { [IO.File]::WriteAllText((Join-Path $script:P.Root '.manager-pid'), [string]$PID) } catch {}

# ---------------------------------------------------------------------
#  Zustand
# ---------------------------------------------------------------------
$script:MySql = $null      # Prozess-States (Start-AcProcess)
$script:Auth  = $null
$script:World = $null
$script:WorldReady = $false
$script:Busy = $false
$script:InTick = $false
$script:StopRequested = $false

# ---------------------------------------------------------------------
#  GUI-Grundgeruest
# ---------------------------------------------------------------------
[Windows.Forms.Application]::EnableVisualStyles()
# Unbehandelte Fehler in Klick-Handlern duerfen den Manager nicht beenden - sonst
# wuerden auch die gestarteten Serverprozesse mit abgeschossen.
try {
    [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException)
    [Windows.Forms.Application]::add_ThreadException([Threading.ThreadExceptionEventHandler]{
        param($sender, $e)
        $msg = $e.Exception.Message
        try {
            Write-AcLog ("UI: " + $msg) 'ERROR'
            Write-AcLog ("   Typ:    " + $e.Exception.GetType().FullName) 'ERROR'
            if ($e.Exception.StackTrace) {
                foreach ($l in (($e.Exception.StackTrace -split "`r?`n") | Select-Object -First 8)) {
                    if ($l.Trim()) { Write-AcLog ("   " + $l.Trim()) 'ERROR' }
                }
            }
            if ($e.Exception.InnerException) {
                $msg += "`r`n" + $e.Exception.InnerException.Message
                Write-AcLog ("   Ursache: " + $e.Exception.InnerException.Message) 'ERROR'
            }
        } catch {}
        [Windows.Forms.MessageBox]::Show($msg + [Environment]::NewLine + [Environment]::NewLine + (T 'err.seeLog' @((Join-Path $script:P.Logs 'manager.log'))), (T 'word.error'), 'OK', 'Error') | Out-Null
    })
} catch {}
$form = New-Object Windows.Forms.Form
$form.Text = (T 'app.manager') + " $($script:AcToolsVersion)  -  $($script:P.Root)  [$($script:S.Variant)]"
# Startgroesse: breit genug fuer alle Registerkarten, aber nie groesser als der
# nutzbare Bildschirmbereich
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$startW = [Math]::Min(1240, [Math]::Max(900, $wa.Width - 80))
$startH = [Math]::Min(820, [Math]::Max(640, $wa.Height - 80))
$form.Size = New-Object Drawing.Size($startW, $startH)
$form.MinimumSize = New-Object Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

function New-Tab($title) { $t = New-Object Windows.Forms.TabPage; $t.Text = $title; $t.Padding = New-Object Windows.Forms.Padding(8); $tabs.TabPages.Add($t); return $t }
function New-Btn($text, $x, $y, $w, $h) { $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h); return $b }
function New-Lbl($text, $x, $y, $w, $bold) { $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, 22); if ($bold) { $l.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold) }; return $l }
function New-Console() {
    $c = New-Object Windows.Forms.RichTextBox
    $c.ReadOnly = $true; $c.Font = New-Object Drawing.Font('Consolas', 9); $c.BackColor = 'Black'; $c.ForeColor = 'Gainsboro'
    $c.DetectUrls = $false; $c.WordWrap = $false; $c.ScrollBars = 'Both'
    return $c
}
function Add-ConsoleLine($box, $text, $color) {
    if ($box.TextLength -gt 3000000) { $box.Clear() }
    $box.SelectionStart = $box.TextLength; $box.SelectionColor = $color
    $box.AppendText($text + "`r`n")
    $box.SelectionStart = $box.TextLength; $box.ScrollToCaret()
}

# ===================== Tab: Server =====================
$tabServer = New-Tab 'Server'
$lblMy = New-Lbl '* MySQL: gestoppt' 12 12 220 $true
$lblAu = New-Lbl '* Authserver: gestoppt' 240 12 220 $true
$lblWo = New-Lbl '* Worldserver: gestoppt' 470 12 300 $true
$btnStartAll = New-Btn 'Start server' 12 42 150 36
$btnStartAll.Tag = 'primary'
$btnStopAll  = New-Btn 'Stop server safely' 170 42 170 36
$btnRestart  = New-Btn 'Restart' 348 42 120 36
$btnStopDb   = New-Btn 'Stop database' 476 42 160 36
$chkAutoRestart = New-Object Windows.Forms.CheckBox
$chkAutoRestart.Text = 'Restart world server automatically after a crash'; $chkAutoRestart.Location = New-Object Drawing.Point(648, 48); $chkAutoRestart.Size = New-Object Drawing.Size(400, 24)
$console = New-Console
$console.Location = New-Object Drawing.Point(12, 88)
$console.Size = New-Object Drawing.Size(($tabServer.ClientSize.Width - 24), ($tabServer.ClientSize.Height - 170))
$txtCmd = New-Object Windows.Forms.TextBox

$btnSend = New-Btn 'Senden' 0 0 90 28
$btnAccount = New-Btn 'Create account' 0 0 170 28
$lblCmd = New-Lbl 'Worldserver-Konsole:' 12 0 150 $false
$tabServer.Controls.AddRange(@($lblMy, $lblAu, $lblWo, $btnStartAll, $btnStopAll, $btnRestart, $btnStopDb, $chkAutoRestart, $console, $lblCmd, $txtCmd, $btnSend, $btnAccount))
$layoutServer = {
    $w = $tabServer.ClientSize.Width; $h = $tabServer.ClientSize.Height
    $console.Location = New-Object Drawing.Point(12, 88); $console.Size = New-Object Drawing.Size(($w - 24), ($h - 170))
    $lblCmd.Location = New-Object Drawing.Point(12, ($h - 70))
    $txtCmd.Location = New-Object Drawing.Point(12, ($h - 46)); $txtCmd.Size = New-Object Drawing.Size(([Math]::Max(120, $w - 470)), 26)
    $btnSend.Location = New-Object Drawing.Point(($w - 450), ($h - 48))
    $btnAccount.Location = New-Object Drawing.Point(($w - 182), ($h - 48))
}
$tabServer.Add_Resize($layoutServer)

# ===================== Tab: Update =====================
$tabUpdate = New-Tab 'Update'
$lblUpdInfo = New-Lbl 'Not checked yet.' 12 12 600 $true
$btnCheck = New-Btn 'Nach Updates suchen' 12 40 170 34
$btnUpdate = New-Btn 'Update Server' 190 40 150 34; $btnUpdate.Enabled = $false; $btnUpdate.Tag = 'primary'
$btnUpdate.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $btnUpdate.Tag = 'primary'
$btnCheckAll = New-Btn 'Alle' 528 40 80 34
$btnCheckNone = New-Btn 'Keine' 614 40 80 34
$btnRebuild = New-Btn 'Nur neu kompilieren' 348 40 170 34
$chkAutoStart = New-Object Windows.Forms.CheckBox
$chkAutoStart.Text = 'Start server automatically after the update'; $chkAutoStart.Location = New-Object Drawing.Point(700, 46); $chkAutoStart.Size = New-Object Drawing.Size(360, 24)   # standardmaessig aus - der Nutzer entscheidet
$lvRepos = New-Object Windows.Forms.ListView
$lvRepos.View = 'Details'; $lvRepos.FullRowSelect = $true; $lvRepos.GridLines = $true
$lvRepos.Dock = 'Top'; $lvRepos.Height = 320
$lvRepos.CheckBoxes = $true   # nur angehakte Repositories werden aktualisiert
[void]$lvRepos.Columns.Add('Repository', 260); [void]$lvRepos.Columns.Add('Branch', 110); [void]$lvRepos.Columns.Add('Lokal', 100); [void]$lvRepos.Columns.Add('Remote', 100); [void]$lvRepos.Columns.Add('Ausstehende Commits', 160)
$updLog = New-Console
$updLog.Dock = 'Fill'
# Liste und Konsole in einem Bereich mit ziehbarem Trenner - so laesst sich die
# Konsole verkleinern, wenn viele Module angezeigt werden sollen
$splitUpd = New-Object Windows.Forms.Splitter
$splitUpd.Dock = 'Top'; $splitUpd.Height = 6; $splitUpd.BackColor = 'Gainsboro'; $splitUpd.MinExtra = 80; $splitUpd.MinSize = 60
$pnlUpd = New-Object Windows.Forms.Panel
$pnlUpd.Location = New-Object Drawing.Point(12, 84); $pnlUpd.Size = New-Object Drawing.Size(900, 520)
# Reihenfolge beachten: das Fuellelement zuerst, das oben angedockte zuletzt
$pnlUpd.Controls.Add($updLog)
$pnlUpd.Controls.Add($splitUpd)
$pnlUpd.Controls.Add($lvRepos)
$tabUpdate.Controls.AddRange(@($lblUpdInfo, $btnCheck, $btnUpdate, $btnRebuild, $btnCheckAll, $btnCheckNone, $chkAutoStart, $pnlUpd))
$layoutUpdate = {
    $w = $tabUpdate.ClientSize.Width; $h = $tabUpdate.ClientSize.Height
    $pnlUpd.Location = New-Object Drawing.Point(12, 84)
    $pnlUpd.Size = New-Object Drawing.Size(($w - 24), ([Math]::Max(200, $h - 96)))
    if (-not $script:UpdSplitInit) {
        # Beim ersten Anzeigen: Liste bekommt den Grossteil, die Konsole den Rest.
        # Gespeicherte Hoehe aus ac-settings.json hat Vorrang.
        $saved = 0
        if ($script:S.UpdateListHeight) { [void][int]::TryParse([string]$script:S.UpdateListHeight, [ref]$saved) }
        if ($saved -lt 80) { $saved = [int]($pnlUpd.Height * 0.68) }
        $lvRepos.Height = [Math]::Max(120, [Math]::Min($saved, $pnlUpd.Height - 110))
        $script:UpdSplitInit = $true
    }
    # nur begrenzen, nicht zuruecksetzen - der Trenner bleibt verschiebbar
    if ($lvRepos.Height -gt ($pnlUpd.Height - 110)) { $lvRepos.Height = [Math]::Max(120, $pnlUpd.Height - 110) }
}
# verschobene Trennerposition merken
$splitUpd.Add_SplitterMoved({
    try {
        $script:S.UpdateListHeight = [int]$lvRepos.Height
        Save-AcSettings $script:P.Root $script:S
    } catch {}
})
$tabUpdate.Add_Resize($layoutUpdate)

# ===================== Tab: Einstellungen =====================
$tabCfg = New-Tab 'Settings'
$lblCfgFile = New-Lbl 'File:' 12 14 50 $true
$tabCfg.Controls.Add($lblCfgFile)
$cmbFile = New-Object Windows.Forms.ComboBox
$cmbFile.DropDownStyle = 'DropDownList'; $cmbFile.Location = New-Object Drawing.Point(60, 10); $cmbFile.Size = New-Object Drawing.Size(280, 26)
$lblCfgSearch = New-Lbl 'Search:' 360 14 55 $true
$tabCfg.Controls.Add($lblCfgSearch)
$txtFilter = New-Object Windows.Forms.TextBox
$txtFilter.Location = New-Object Drawing.Point(415, 10); $txtFilter.Size = New-Object Drawing.Size(220, 26)
$btnCfgSave = New-Btn 'Speichern' 650 8 110 30
$btnCfgReload = New-Btn 'Reload' 770 8 110 30
$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(12, 46); $grid.Size = New-Object Drawing.Size(900, 400)
$grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $false; $grid.AutoSizeColumnsMode = 'Fill'
[void]$grid.Columns.Add('Key', 'Setting'); [void]$grid.Columns.Add('Value', 'Value')
$grid.Columns[0].ReadOnly = $true; $grid.Columns[0].FillWeight = 45; $grid.Columns[1].FillWeight = 55
$txtDesc = New-Object Windows.Forms.TextBox
$txtDesc.Multiline = $true; $txtDesc.ReadOnly = $true; $txtDesc.ScrollBars = 'Vertical'
$txtDesc.Location = New-Object Drawing.Point(12, 456); $txtDesc.Size = New-Object Drawing.Size(900, 150)
$txtDesc.Font = New-Object Drawing.Font('Consolas', 9)
$lblCpu = New-Lbl 'CPU:' 640 622 50 $true
$cmbCpu = New-Object Windows.Forms.ComboBox
$cmbCpu.DropDownStyle = 'DropDownList'; $cmbCpu.Location = New-Object Drawing.Point(690, 620); $cmbCpu.Size = New-Object Drawing.Size(240, 26)
$lblTheme = New-Lbl 'Theme:' 380 622 70 $true
$cmbTheme = New-Object Windows.Forms.ComboBox
$cmbTheme.DropDownStyle = 'DropDownList'; $cmbTheme.Location = New-Object Drawing.Point(450, 620); $cmbTheme.Size = New-Object Drawing.Size(160, 26)
$lblLang = New-Lbl 'Sprache / Language:' 12 622 150 $true
$cmbLang = New-Object Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'; $cmbLang.Location = New-Object Drawing.Point(170, 620); $cmbLang.Size = New-Object Drawing.Size(180, 26)
foreach ($code in @('de', 'en')) { [void]$cmbLang.Items.Add($script:AcLanguages[$code]) }
$cmbLang.SelectedIndex = @('de', 'en').IndexOf($script:AcLanguage)
$btnResetBots = New-Btn 'Reset random bots...' 380 618 260 30
$btnResetBots.Enabled = ($script:S.Variant -eq 'playerbots')
$tabCfg.Controls.AddRange(@($cmbFile, $txtFilter, $btnCfgSave, $btnCfgReload, $grid, $txtDesc, $lblLang, $cmbLang, $lblTheme, $cmbTheme, $lblCpu, $cmbCpu, $btnResetBots))
$layoutCfg = {
    $w = $tabCfg.ClientSize.Width; $h = $tabCfg.ClientSize.Height
    $grid.Location = New-Object Drawing.Point(12, 46); $grid.Size = New-Object Drawing.Size(($w - 24), ($h - 254))
    $txtDesc.Location = New-Object Drawing.Point(12, ($h - 199)); $txtDesc.Size = New-Object Drawing.Size(($w - 24), 150)
    $lblLang.Location = New-Object Drawing.Point(12, ($h - 40))
    $cmbLang.Location = New-Object Drawing.Point(170, ($h - 43))
    $lblTheme.Location = New-Object Drawing.Point(380, ($h - 40))
    $cmbTheme.Location = New-Object Drawing.Point(450, ($h - 43))
    $lblCpu.Location = New-Object Drawing.Point(640, ($h - 40))
    $cmbCpu.Location = New-Object Drawing.Point(690, ($h - 43))
    $btnResetBots.Location = New-Object Drawing.Point(940, ($h - 45))
}
$tabCfg.Add_Resize($layoutCfg)

# ===================== Tab: Module =====================
$tabMod = New-Tab 'Modules'
# Spaltenansicht; Module und Lua-Pakete stehen in zwei zuklappbaren Gruppen
$lvMods = New-Object Windows.Forms.ListView
$lvMods.View = 'Details'; $lvMods.FullRowSelect = $true; $lvMods.HideSelection = $false
$lvMods.ShowGroups = $true
$lvMods.Location = New-Object Drawing.Point(12, 12); $lvMods.Size = New-Object Drawing.Size(560, 380)
foreach ($c in @(@('mod.colModule', 200), @('mod.colGit', 50), @('mod.colConfig', 150), @('mod.colSql', 210), @('mod.colBuilt', 100))) {
    [void]$lvMods.Columns.Add((T $c[0]), $c[1])
}
$drop = New-Object Windows.Forms.Panel
$drop.Location = New-Object Drawing.Point(590, 12); $drop.Size = New-Object Drawing.Size(320, 200); $drop.BorderStyle = 'FixedSingle'; $drop.BackColor = 'WhiteSmoke'; $drop.AllowDrop = $true

$dropLbl = New-Object Windows.Forms.Label
$dropLbl.Text = "Drop module here`r`n(folder or ZIP from GitHub)"; $dropLbl.Dock = 'Fill'; $dropLbl.TextAlign = 'MiddleCenter'
$dropLbl.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold); $dropLbl.ForeColor = 'DimGray'; $dropLbl.AllowDrop = $true
$drop.Controls.Add($dropLbl)
$lblGitUrl = New-Lbl 'Oder Git-URL:' 590 226 120 $true
$txtGitUrl = New-Object Windows.Forms.TextBox
$txtGitUrl.Location = New-Object Drawing.Point(590, 250); $txtGitUrl.Size = New-Object Drawing.Size(320, 26)
$btnGitAdd = New-Btn 'Aus Git hinzufuegen' 590 282 320 30
$btnModExport = New-Btn 'Export module list...' 590 192 320 30
$btnModImport = New-Btn 'Import module list...' 590 228 320 30
$btnLua = New-Btn 'Lua scripts (Eluna)...' 590 264 320 30
$btnModCfg = New-Btn 'Configure module...' 590 300 320 30
$btnModInfo = New-Btn 'Show module info...' 590 320 320 30
$btnModSql = New-Btn 'Check / link SQL files...' 590 356 320 30
$btnModRemove = New-Btn 'Remove module' 590 392 320 30
$btnModBuild = New-Btn 'Rebuild (apply modules)' 590 432 320 36
$btnModBuild.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $btnModBuild.Tag = 'primary'
$lblModHint = New-Lbl '' 12 400 900 $false; $lblModHint.ForeColor = 'DarkRed'
$modLog = New-Console
$modLog.Location = New-Object Drawing.Point(12, 426); $modLog.Size = New-Object Drawing.Size(900, 180)
$tabMod.Controls.AddRange(@($lvMods, $drop, $lblGitUrl, $txtGitUrl, $btnGitAdd, $btnModExport, $btnModImport, $btnLua, $btnModCfg, $btnModInfo, $btnModSql, $btnModRemove, $btnModBuild, $lblModHint, $modLog))
$layoutMod = {
    $w = $tabMod.ClientSize.Width; $h = $tabMod.ClientSize.Height
    $logH = [Math]::Max(120, [Math]::Min(180, $h - 380))     # Konsole unten
    $logTop = $h - 12 - $logH
    $hintTop = $logTop - 26                                   # Warnhinweis direkt darueber
    $contentBottom = $hintTop - 8                             # ab hier ist Schluss fuer Liste und Buttons
    $colW = 320; $colX = $w - 12 - $colW

    # rechte Spalte von unten nach oben stapeln, damit nichts in die Konsole rutscht
    $yb = $contentBottom
    $stack = @(
        @{ C = $btnModBuild;  H = 36; Gap = 10 },
        @{ C = $btnModRemove; H = 30; Gap = 8 },
        @{ C = $btnModSql;    H = 30; Gap = 6 },
        @{ C = $btnModInfo;   H = 30; Gap = 6 },
        @{ C = $btnModCfg;    H = 30; Gap = 6 },
        @{ C = $btnLua;       H = 30; Gap = 6 },
        @{ C = $btnModImport; H = 30; Gap = 6 },
        @{ C = $btnModExport; H = 30; Gap = 6 },
        @{ C = $btnGitAdd;    H = 30; Gap = 8 },
        @{ C = $txtGitUrl;    H = 26; Gap = 4 },
        @{ C = $lblGitUrl;    H = 22; Gap = 10 }
    )
    foreach ($s in $stack) {
        $yb -= $s.H
        $s.C.Location = New-Object Drawing.Point($colX, $yb)
        $s.C.Width = $colW
        if ($s.C -ne $lblGitUrl) { $s.C.Height = $s.H }
        $yb -= $s.Gap
    }
    # Ablagefeld fuellt den Rest der Spalte (mindestens 90 px hoch)
    $dropH = [Math]::Max(90, $yb - 12)
    $drop.Location = New-Object Drawing.Point($colX, 12)
    $drop.Size = New-Object Drawing.Size($colW, $dropH)

    $lvMods.Location = New-Object Drawing.Point(12, 12)
    $lvMods.Size = New-Object Drawing.Size(([Math]::Max(260, $colX - 24)), ($contentBottom - 12))

    $lblModHint.Location = New-Object Drawing.Point(12, $hintTop); $lblModHint.Width = $w - 24
    $modLog.Location = New-Object Drawing.Point(12, $logTop)
    $modLog.Size = New-Object Drawing.Size(($w - 24), $logH)
}
$tabMod.Add_Resize($layoutMod)

# ===================== Tab: Info =====================
$tabInfo = New-Tab 'Info'
$pnlRealm = New-Object Windows.Forms.Panel
$pnlRealm.Dock = 'Top'; $pnlRealm.Height = 44
$lblRealmAddr = New-Lbl 'Realm-Adresse (IP, die Spieler eintragen):' 4 12 300 $true
$pnlRealm.Controls.Add($lblRealmAddr)
$txtRealmAddr = New-Object Windows.Forms.TextBox
$txtRealmAddr.Location = New-Object Drawing.Point(310, 9); $txtRealmAddr.Size = New-Object Drawing.Size(200, 26); $txtRealmAddr.Text = '127.0.0.1'
$btnRealmAddr = New-Btn 'Setzen' 520 7 100 30
$pnlRealm.Controls.AddRange(@($txtRealmAddr, $btnRealmAddr))
$txtInfo = New-Object Windows.Forms.TextBox
$txtInfo.Multiline = $true; $txtInfo.ReadOnly = $true; $txtInfo.Dock = 'Fill'; $txtInfo.ScrollBars = 'Vertical'; $txtInfo.Font = New-Object Drawing.Font('Consolas', 9.5)
$tabInfo.Controls.Add($txtInfo); $tabInfo.Controls.Add($pnlRealm)
$btnRealmAddr.Add_Click({
    $addr = $txtRealmAddr.Text.Trim()
    if ($addr -notmatch '^[A-Za-z0-9.\-]+$') { [Windows.Forms.MessageBox]::Show((T 'inf.addressInvalid')) | Out-Null; return }
    try {
        if (-not (Confirm-DbStart 'db.reasonRealm')) { return }
        $st = Start-AcMySql $script:P; if ($st) { $script:MySql = $st; Set-Status $lblMy 'svc.mysql' 'state.running' }
        Invoke-AcMySql $script:P "UPDATE acore_auth.realmlist SET address='$addr' WHERE id=1;" | Out-Null
        [Windows.Forms.MessageBox]::Show((T 'inf.addressSet' @($addr)), 'Realm', 'OK', 'Information') | Out-Null
    } catch { Show-AcError $_ }
})

# ---------------------------------------------------------------------
#  Log-Weiche: Betriebs-Log -> aktuell passender Tab
# ---------------------------------------------------------------------
$script:OpLogTarget = $updLog
$script:AcLogHandler = {
    param($line, $level)
    $color = switch ($level) { 'WARN' { 'Orange' } 'ERROR' { 'Tomato' } 'CMD' { 'DeepSkyBlue' } 'STEP' { 'LightGreen' } 'MYSQL' { 'Gray' } default { 'Gainsboro' } }
    if ($level -eq 'MYSQL') { Add-ConsoleLine $console "[mysql] $line" 'Gray' } else { Add-ConsoleLine $script:OpLogTarget $line $color }
    Invoke-AcDoEvents
}
$script:AcProgressHandler = { param($pct, $text) if ($text) { $form.Text = (T 'app.manager') + "  -  $text" }; Invoke-AcDoEvents }

# ---------------------------------------------------------------------
#  Fehler einheitlich melden UND protokollieren
#
#  Frueher zeigten die Dialoge nur die Meldung - im Protokoll stand nichts,
#  wodurch sich Fehler nicht nachvollziehen liessen. Jetzt landet alles in
#  manager.log: Ausnahmetyp, Datei, Zeile, ausloesender Befehl und Aufrufkette.
# ---------------------------------------------------------------------
function Show-AcError {
    param($ErrorRecord, [string]$Context = '')
    $msg = ''; $type = ''; $where = ''; $cmd = ''; $stack = ''
    try {
        $msg  = [string]$ErrorRecord.Exception.Message
        $type = $ErrorRecord.Exception.GetType().FullName
        $ii = $ErrorRecord.InvocationInfo
        if ($ii) {
            $file = ''
            if ($ii.ScriptName) { $file = Split-Path $ii.ScriptName -Leaf }
            $where = "${file}:$($ii.ScriptLineNumber)"
            $cmd = ([string]$ii.Line).Trim()
        }
        $stack = [string]$ErrorRecord.ScriptStackTrace
    } catch { $msg = [string]$ErrorRecord }

    $head = $(if ($Context) { "[$Context] " } else { '' })
    Write-AcLog ($head + $msg) 'ERROR'
    if ($type)  { Write-AcLog ("   Typ:    " + $type) 'ERROR' }
    if ($where) { Write-AcLog ("   Stelle: " + $where) 'ERROR' }
    if ($cmd)   { Write-AcLog ("   Befehl: " + $cmd) 'ERROR' }
    if ($stack) { foreach ($l in ($stack -split "`r?`n")) { if ($l.Trim()) { Write-AcLog ("   " + $l.Trim()) 'ERROR' } } }

    $dlgText = $head + $msg
    if ($where) { $dlgText += [Environment]::NewLine + $where }
    $dlgText += [Environment]::NewLine + [Environment]::NewLine + (T 'err.seeLog' @((Join-Path $script:P.Logs 'manager.log')))
    [Windows.Forms.MessageBox]::Show($dlgText, (T 'word.error'), 'OK', 'Error') | Out-Null
}

function Reset-Title { $form.Text = (T 'app.manager') + " $($script:AcToolsVersion)  -  $($script:P.Root)  [$($script:S.Variant)]" }

# ---------------------------------------------------------------------
#  Server-Steuerung
# ---------------------------------------------------------------------
function Set-Status($label, $svcKey, $stateKey) {
    $col = switch ($stateKey) {
        'state.running'  { Get-AcColor 'Good' }
        'state.ready'    { Get-AcColor 'Good' }
        'state.starting' { Get-AcColor 'Warn' }
        'state.stopping' { Get-AcColor 'Warn' }
        default          { Get-AcColor 'Bad' }
    }
    $label.Tag = @{ Svc = $svcKey; State = $stateKey }
    $label.Text = "* " + (T $svcKey) + ": " + (T $stateKey); $label.ForeColor = $col
}
function Get-StatusKey($label) { if ($label.Tag) { return $label.Tag.State } return 'state.stopped' }
function Update-Buttons {
    $dbUp = ((Get-StatusKey $lblMy) -ne 'state.stopped')
    $worldUp = [bool]($script:World -and -not $script:World.Process.HasExited)
    $running = $worldUp -or [bool]($script:Auth -and -not $script:Auth.Process.HasExited)
    $btnStartAll.Enabled = (-not $running) -and (-not $script:Busy)
    $btnStopAll.Enabled  = $running -and (-not $script:Busy)
    $btnRestart.Enabled  = $running -and (-not $script:Busy)
    $btnSend.Enabled = $worldUp
    $btnAccount.Enabled = $worldUp
    # Die Datenbank laesst sich einzeln stoppen, solange keine Server sie brauchen
    $btnStopDb.Enabled = $dbUp -and (-not $running) -and (-not $script:Busy) -and (-not $script:DbBusy)
    foreach ($b in @($btnCheck, $btnRebuild, $btnModBuild, $btnGitAdd, $btnModRemove, $btnCfgSave)) { $b.Enabled = -not $script:Busy }
    $btnUpdate.Enabled = (-not $script:Busy) -and [bool]$script:UpdateAvailable
}
$script:UpdateAvailable = $false

function Send-WorldCommand([string]$cmd) {
    if (-not $script:World -or $script:World.Process.HasExited) { throw (T 'srv.notRunning') }
    Add-ConsoleLine $console "AC> $cmd" 'Yellow'
    $script:World.Process.StandardInput.WriteLine($cmd)
    $script:World.Process.StandardInput.Flush()
}

function Start-Servers {
    if ($script:Busy) { return }
    $script:Busy = $true; $script:StopRequested = $false; $script:OpLogTarget = $console; Update-Buttons
    try {
        Set-Status $lblMy 'svc.mysql' 'state.starting'
        $st = Start-AcMySql $script:P
        if ($st) { $script:MySql = $st }
        Set-Status $lblMy 'svc.mysql' 'state.running'
        if (-not $script:GrantsChecked) {
            try { Grant-AcDbPrivileges $script:P $script:S; $script:GrantsChecked = $true }
            catch { Add-ConsoleLine $console ("GRANT: " + $_.Exception.Message) 'Orange' }
        }

        if (-not (Test-Path (Join-Path $script:P.Bin 'legacy.dll'))) { Copy-AcRuntimeDlls $script:P $script:S }
        $auth = Join-Path $script:P.Bin 'authserver.exe'
        if (-not $script:Auth -or $script:Auth.Process.HasExited) {
            Add-ConsoleLine $console (T 'srv.startingAuth') 'LightGreen'
            $script:Auth = Start-AcProcess -FilePath $auth -WorkingDirectory $script:P.Bin
        }
        Set-Status $lblAu 'svc.auth' 'state.running'
        Start-Sleep -Milliseconds 1500

        $world = Join-Path $script:P.Bin 'worldserver.exe'
        if (-not $script:World -or $script:World.Process.HasExited) {
            Add-ConsoleLine $console (T 'srv.startingWorld') 'LightGreen'
            $script:WorldReady = $false
            $script:World = Start-AcProcess -FilePath $world -WorkingDirectory $script:P.Bin -RedirectInput
        }
        Set-Status $lblWo 'svc.world' 'state.starting'
    } catch {
        Add-ConsoleLine $console ((T 'srv.startFailed') + " $($_.Exception.Message)") 'Tomato'
        [Windows.Forms.MessageBox]::Show((T 'srv.startFailed') + "`n$($_.Exception.Message)", (T 'word.error'), 'OK', 'Error') | Out-Null
    } finally { $script:Busy = $false; Update-Buttons }
}

function Stop-Servers([switch]$KeepMySql) {
    if ($script:Busy) { return }
    $script:Busy = $true; $script:StopRequested = $true; $script:OpLogTarget = $console; Update-Buttons
    try {
        if ($script:World -and -not $script:World.Process.HasExited) {
            Set-Status $lblWo 'svc.world' 'state.stopping'
            Add-ConsoleLine $console (T 'srv.shuttingDown') 'LightGreen'
            try { Send-WorldCommand 'server shutdown 1' } catch {}
            $t0 = Get-Date
            while (-not $script:World.Process.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 120) { Invoke-AcDoEvents; Start-Sleep -Milliseconds 200 }
            if (-not $script:World.Process.HasExited) {
                try { Send-WorldCommand 'server exit' } catch {}
                $t0 = Get-Date
                while (-not $script:World.Process.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Invoke-AcDoEvents; Start-Sleep -Milliseconds 200 }
            }
            if (-not $script:World.Process.HasExited) { Add-ConsoleLine $console (T 'srv.notResponding') 'Orange'; try { $script:World.Process.Kill() } catch {} }
        }
        Set-Status $lblWo 'svc.world' 'state.stopped'
        if ($script:Auth -and -not $script:Auth.Process.HasExited) {
            Add-ConsoleLine $console (T 'srv.stoppingAuth') 'LightGreen'
            try { $script:Auth.Process.Kill() } catch {}
        }
        Set-Status $lblAu 'svc.auth' 'state.stopped'
        if (-not $KeepMySql) {
            Set-Status $lblMy 'svc.mysql' 'state.stopping'
            Stop-AcMySql $script:P $script:MySql; $script:MySql = $null
            $script:DbApproved = $false
            Set-Status $lblMy 'svc.mysql' 'state.stopped'
        }
    } finally { $script:Busy = $false; Update-Buttons }
}

function Stop-MySqlOnly {
    if ($script:Busy -or $script:DbBusy) { return }
    $script:Busy = $true; Update-Buttons
    try {
        $script:OpLogTarget = $console
        Set-Status $lblMy 'svc.mysql' 'state.stopping'
        Add-ConsoleLine $console (T 'srv.stoppingMysql') 'LightGreen'
        Stop-AcMySql $script:P $script:MySql
        $script:MySql = $null
        $script:DbApproved = $false
        Set-Status $lblMy 'svc.mysql' 'state.stopped'
    } catch {
        Add-ConsoleLine $console $_.Exception.Message 'Tomato'
    } finally { $script:Busy = $false; Update-Buttons }
}

# Timer: Ausgabe der Server einsammeln, Status pruefen
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
    if ($script:InTick) { return }
    $script:InTick = $true
    try {
        if ($script:MySql) { foreach ($l in (Read-AcProcessLines $script:MySql)) { Add-ConsoleLine $console "[mysql] $l" 'Gray' } }
        if ($script:Auth) {
            foreach ($l in (Read-AcProcessLines $script:Auth)) { Add-ConsoleLine $console "[auth]  $l" 'LightSteelBlue' }
            if ($script:Auth.Process.HasExited -and (Get-StatusKey $lblAu) -ne 'state.stopped') { Set-Status $lblAu 'svc.auth' 'state.stopped'; Add-ConsoleLine $console (T 'srv.exited' @((T 'svc.auth'), $script:Auth.Process.ExitCode)) 'Orange'; Update-Buttons }
        }
        if ($script:World) {
            foreach ($l in (Read-AcProcessLines $script:World)) {
                Add-ConsoleLine $console $l 'Gainsboro'
                if ($l -match 'Please reset the AiPlayerbot\.DeleteRandomBotAccounts') { Complete-BotReset }
                if (-not $script:WorldReady -and $l -match 'World initialized|ready\.\.\.|\(worldserver-daemon\) ready') {
                    $script:WorldReady = $true; Set-Status $lblWo 'svc.world' 'state.ready'; Update-Buttons
                    Complete-BotReset
                    if ($script:BotResetRestart) { $script:InTick = $false; Invoke-BotResetRestart; return }
                }
            }
            if ($script:World.Process.HasExited -and (Get-StatusKey $lblWo) -ne 'state.stopped') {
                $code = $script:World.Process.ExitCode
                Set-Status $lblWo 'svc.world' 'state.stopped'
                Add-ConsoleLine $console (T 'srv.exited' @((T 'svc.world'), $code)) 'Orange'
                Update-Buttons
                if ($script:BotResetRestart -and -not $script:StopRequested -and -not $script:Busy) {
                    # Absturz nach dem Bot-Loeschlauf: der vorgesehene Neustart holt die Bots zurueck
                    $script:InTick = $false
                    Start-Sleep -Seconds 3
                    Invoke-BotResetRestart
                    return
                }
                if ($code -ne 0 -and -not $script:StopRequested -and $chkAutoRestart.Checked -and -not $script:Busy) {
                    Add-ConsoleLine $console (T 'srv.crashRestart') 'Orange'
                    $script:InTick = $false
                    Start-Sleep -Seconds 5
                    Start-Servers
                }
            }
        }
        if ($script:MySql -and $script:MySql.Process.HasExited -and (Get-StatusKey $lblMy) -ne 'state.stopped') { Set-Status $lblMy 'svc.mysql' 'state.stopped'; $script:MySql = $null }
    } catch {} finally { $script:InTick = $false }
})

$btnStartAll.Add_Click({ Start-Servers })
$btnStopAll.Add_Click({ Stop-Servers })
$btnRestart.Add_Click({ Stop-Servers -KeepMySql; Start-Servers })
$btnStopDb.Add_Click({ Stop-MySqlOnly })
$btnSend.Add_Click({ if ($txtCmd.Text.Trim()) { try { Send-WorldCommand $txtCmd.Text.Trim() } catch { Add-ConsoleLine $console $_.Exception.Message 'Tomato' }; $txtCmd.Clear() } })
$txtCmd.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq 'Return') { $btnSend.PerformClick(); $e.SuppressKeyPress = $true; $e.Handled = $true } })
function Show-AccountDialog {
    param([bool]$AsGm)
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'acc.title'
    $dlg.Size = New-Object Drawing.Size(380, 210); $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false; $dlg.Font = $form.Font
    $dlg.Controls.Add((New-Lbl (T 'acc.name') 16 22 110 $false))
    $n = New-Object Windows.Forms.TextBox; $n.Location = New-Object Drawing.Point(136, 20); $n.Width = 210; $dlg.Controls.Add($n)
    $dlg.Controls.Add((New-Lbl (T 'acc.password') 16 57 110 $false))
    $pw = New-Object Windows.Forms.TextBox; $pw.Location = New-Object Drawing.Point(136, 55); $pw.Width = 210; $dlg.Controls.Add($pw)
    $gm = New-Object Windows.Forms.CheckBox
    $gm.Text = T 'acc.gmRights'; $gm.Location = New-Object Drawing.Point(136, 88); $gm.Width = 210; $gm.Checked = $AsGm
    $dlg.Controls.Add($gm)
    $ok = New-Btn (T 'acc.create') 136 126 105 32; $ok.DialogResult = 'OK'; $ok.Tag = 'primary'
    $no = New-Btn (T 'btn.cancel') 246 126 100 32; $no.DialogResult = 'Cancel'
    $dlg.Controls.AddRange(@($ok, $no)); $dlg.AcceptButton = $ok; $dlg.CancelButton = $no
    Update-AcTheme $dlg
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    if (-not $n.Text.Trim() -or -not $pw.Text) { return }
    try {
        Send-WorldCommand "account create $($n.Text.Trim()) $($pw.Text)"
        if ($gm.Checked) { Start-Sleep -Milliseconds 500; Send-WorldCommand "account set gmlevel $($n.Text.Trim()) 3 -1" }
    } catch { Add-ConsoleLine $console $_.Exception.Message 'Tomato' }
}

$btnAccount.Add_Click({ Show-AccountDialog $false })

# ---------------------------------------------------------------------
#  Update
# ---------------------------------------------------------------------
function Get-CheckedRepoNames {
    # Namen der angehakten Repositories; vor dem Neuaufbau der Liste sichern
    $names = @()
    foreach ($it in $lvRepos.Items) { if ($it.Checked) { $names += [string]$it.Text } }
    return $names
}

function Invoke-CheckUpdates([switch]$Quiet, [switch]$NoFetch) {
    # bisherige Auswahl merken - beim ersten Lauf ist alles angehakt
    $prevChecked = @(Get-CheckedRepoNames)
    $hadItems = ($lvRepos.Items.Count -gt 0)
    $git = Find-AcGit
    if (-not $git) { $lblUpdInfo.Text = (T 'upd.gitMissing'); return }
    $script:OpLogTarget = $updLog
    $lvRepos.Items.Clear(); $behindTotal = 0
    $lblUpdInfo.Text = (T 'upd.checking'); Invoke-AcDoEvents
    foreach ($r in (Get-AcGitRepos $script:P)) {
        try {
            $st = Get-AcRepoStatus $git $r.Path -Fetch:(-not $NoFetch)
            $it = New-Object Windows.Forms.ListViewItem($r.Name)
            # Nur Repositories mit ausstehenden Commits sind vorgemerkt. Nach einem
            # Lauf ohne Abgleich (NoFetch) bleibt die bisherige Auswahl bestehen.
            if ($NoFetch -and $hadItems) { $it.Checked = ($prevChecked -contains $r.Name) }
            else { $it.Checked = ($st.Behind -gt 0) }
            [void]$it.SubItems.Add($st.Branch); [void]$it.SubItems.Add($st.Local); [void]$it.SubItems.Add($st.Remote); [void]$it.SubItems.Add([string]$st.Behind)
            if ($st.Behind -gt 0) { $it.ForeColor = Get-AcColor 'Good'; $it.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold) }
            else { $it.ForeColor = Get-AcColor 'TextDim' }
            [void]$lvRepos.Items.Add($it)
            $behindTotal += $st.Behind
        } catch { Write-AcLog (T 'upd.statusFailed' @($r.Name, $_.Exception.Message)) 'WARN' }
    }
    $script:UpdateAvailable = [bool]($behindTotal -gt 0)
    if ($script:UpdateAvailable) { $lblUpdInfo.Text = (T 'upd.available' @($behindTotal)); $lblUpdInfo.ForeColor = 'DarkGreen'; $tabUpdate.Text = (T 'tab.updateAvailable') }
    elseif ($NoFetch) { $lblUpdInfo.Text = (T 'upd.localOnly'); $lblUpdInfo.ForeColor = 'Black'; $tabUpdate.Text = (T 'tab.update') }
    else { $lblUpdInfo.Text = (T 'upd.current' @((Get-Date -Format 'HH:mm'))); $lblUpdInfo.ForeColor = 'Black'; $tabUpdate.Text = (T 'tab.update') }
    if ($script:S.NeedsRebuild) { $lblUpdInfo.Text += (T 'upd.needsRebuild') }
    Update-Buttons
}

$script:TabsLocked = $false
function Set-TabsLocked([bool]$Locked) {
    # Waehrend Update/Build bleibt nur der Update-Tab bedienbar
    $script:TabsLocked = $Locked
    foreach ($t in @($tabServer, $tabCfg, $tabMod, $tabChar, $tabGm, $tabInfo)) {
        try { $t.Enabled = -not $Locked } catch {}
    }
    if ($Locked) { $tabs.SelectedTab = $tabUpdate }
}
# Tabwechsel abfangen, solange gesperrt
$tabs.Add_Selecting({ param($sender, $e) if ($script:TabsLocked -and $e.TabPage -ne $tabUpdate) { $e.Cancel = $true } })

function Invoke-BuildPipeline([switch]$Pull) {
    # Stoppt Server, (holt Updates), konfiguriert, kompiliert, importiert DB, startet optional wieder
    if ($script:Busy) { return }
    $wasRunning = ($script:World -and -not $script:World.Process.HasExited)
    if ($wasRunning) {
        if ([Windows.Forms.MessageBox]::Show((T 'upd.stopFirst'), (T 'upd.stopTitle'), 'YesNo', 'Question') -ne 'Yes') { return }
        Stop-Servers -KeepMySql
    }
    # Am Ende der Kette laeuft dbimport - deshalb schon jetzt fragen und nicht erst
    # nach einem halbstuendigen Build
    if (-not (Confirm-DbStart 'db.reasonUpdate')) {
        $lblUpdInfo.ForeColor = 'DarkRed'; $lblUpdInfo.Text = T 'db.notStartedUpdate'
        return
    }
    $script:Busy = $true; Update-Buttons
    $script:OpLogTarget = $updLog
    Set-TabsLocked $true
    $ok = $false
    try {
        $git = Find-AcGit
        if ($Pull) {
            Write-AcLog (T 'upd.stepRemoveSql') 'STEP'
            Remove-AcAllModuleSqlLinks $script:P
            # Nur angehakte Repositories holen. Ist die Liste noch leer (kein
            # Update-Check gelaufen), werden alle aktualisiert.
            $wanted = @(Get-CheckedRepoNames)
            $selective = ($lvRepos.Items.Count -gt 0)
            if ($selective -and $wanted.Count -eq 0) {
                # Alles abgewaehlt: nichts holen, aber auch nicht stillschweigend
                Write-AcLog (T 'upd.nothingSelected') 'WARN'
            }
            $skipped = @()
            foreach ($r in (Get-AcGitRepos $script:P)) {
                if ($selective -and ($wanted -notcontains $r.Name)) { $skipped += $r.Name; continue }
                Write-AcLog (T 'upd.stepPull' @($r.Name)) 'STEP'
                Invoke-AcProcess -FilePath $git -ArgumentList 'pull --ff-only' -WorkingDirectory $r.Path | Out-Null
            }
            if ($skipped.Count -gt 0) { Write-AcLog (T 'upd.skipped' @(($skipped -join ', '))) 'WARN' }
        }
        # Submodule der Module sicherstellen (Lua-Engines u.a. brauchen sie zum Bauen)
        Update-AcAllSubmodules $script:P | Out-Null
        # Ordnername gegen Repositorynamen pruefen - nach einer Umbenennung des
        # Projekts stimmen sonst die Include-Pfade im CMake des Moduls nicht
        foreach ($mm in (Get-AcMisnamedModules $script:P)) {
            $ask = T 'mod.renameAsk' @($mm.Folder, $mm.Expected, "`r`n")
            if ([Windows.Forms.MessageBox]::Show($ask, (T 'tab.modules'), 'YesNo', 'Warning') -eq 'Yes') {
                try { Rename-AcModuleFolder $script:P $mm.Folder $mm.Expected | Out-Null }
                catch { Write-AcLog $_.Exception.Message 'WARN' }
            } else {
                Write-AcLog (T 'mod.renameSkipped' @($mm.Folder, $mm.Expected)) 'WARN'
            }
        }
        # Eluna ohne Lua-Unterstuetzung im Core laeuft unweigerlich in "lua.h not found"
        # Playerbot-Module auf einem Core ohne Playerbots koennen nicht bauen
        if ($script:S.Variant -ne 'playerbots') {
            $pb = @(Get-AcPlayerbotDependentModules $script:P)
            if ($pb.Count -gt 0) {
                $ask = T 'mod.needPlayerbots' @(($pb -join ', '), "`r`n")
                if ([Windows.Forms.MessageBox]::Show($ask, (T 'tab.modules'), 'YesNo', 'Warning') -ne 'Yes') {
                    Write-AcLog (T 'mod.needPlayerbotsAbort' @(($pb -join ', '))) 'WARN'
                    $script:Busy = $false; Set-TabsLocked $false; Reset-Title; Update-Buttons
                    return
                }
                Write-AcLog (T 'mod.needPlayerbotsWarn' @(($pb -join ', '))) 'WARN'
            }
        }
        Write-AcLog (T 'upd.stepSql') 'STEP'
        Sync-AcAllModuleSql $script:P | Out-Null
        Write-AcLog (T 'upd.stepCmake') 'STEP'
        Invoke-AcConfigure $script:P $script:S
        Write-AcLog (T 'upd.stepBuild') 'STEP'
        Invoke-AcBuild $script:P $script:S
        Write-AcLog (T 'upd.stepDb') 'STEP'
        Set-Status $lblMy 'svc.mysql' 'state.starting'
        $st = Start-AcMySql $script:P; if ($st) { $script:MySql = $st }
        Set-Status $lblMy 'svc.mysql' 'state.running'
        Invoke-AcDbImport $script:P
        Save-AcBuiltModules $script:P $script:S
        Write-AcLog (T 'upd.stepDone') 'STEP'
        $ok = $true
    } catch {
        $ErrRecord = $_
        $msg = $_.Exception.Message
        Write-AcLog $msg 'ERROR'
        # die eigentlichen Compilerfehler aus dem MSBuild-Protokoll nachreichen
        $errs = @()
        try { $errs = @(Get-AcBuildErrors $script:P) } catch {}
        # dbimport-Fehler kommen nicht von MSBuild - dann die Datenbank-Protokolle auswerten
        if ($errs.Count -eq 0 -and $msg -match 'dbimport') {
            try { $errs = @(Get-AcDbErrors $script:P) } catch {}
            if ($errs.Count -gt 0) {
                Write-AcLog (T 'upd.errDbHeader') 'ERROR'
                foreach ($e in $errs) { Write-AcLog "   $e" 'ERROR' }
                # Typischer Fall: Ein neu hinzugefuegtes Modul bringt eine updates-Datei mit,
                # aber seine base-Datei wurde nie eingespielt (nur bei leerer Datenbank).
                $culprit = ''
                foreach ($e in $errs) {
                    if ($e -match 'modules[\\/]([A-Za-z0-9._-]+)[\\/]') { $culprit = $Matches[1]; break }
                }
                $missingTable = ($errs -join ' ') -match "Table '.*' doesn't exist|1146"
                $msg = ($errs | Select-Object -First 6) -join "`r`n"
                $msg += "`r`n`r`n" + (T 'upd.errDbLog' @((Join-Path $script:P.Logs 'DBErrors.log')))
                $script:Busy = $false; Set-TabsLocked $false; Reset-Title; Update-Buttons
                if ($culprit -and $missingTable) {
                    $baseFiles = @(Get-AcModuleBaseSqlFiles (Join-Path $script:P.Modules $culprit))
                    if ($baseFiles.Count -gt 0) {
                        $ask = (T 'upd.baseMissing' @($culprit, $baseFiles.Count, "`r`n")) + "`r`n`r`n" + $msg
                        if ([Windows.Forms.MessageBox]::Show($ask, (T 'sql.summaryTitle'), 'YesNo', 'Warning') -eq 'Yes') {
                            try {
                                $script:Busy = $true; Set-TabsLocked $true; Update-Buttons
                                $n = Import-AcModuleBaseSql $script:P (Join-Path $script:P.Modules $culprit)
                                Write-AcLog (T 'upd.baseImported' @($n, $culprit)) 'STEP'
                                Invoke-AcDbImport $script:P $script:S
                                Save-AcBuiltModules $script:P $script:S
                                Write-AcLog (T 'upd.stepDone') 'STEP'
                                $script:Busy = $false; Set-TabsLocked $false; Update-Buttons
                                Refresh-Modules
                                if ($chkAutoStart.Checked) { Start-Servers }
                                return
                            } catch {
                                Write-AcLog $_.Exception.Message 'ERROR'
                                $script:Busy = $false; Set-TabsLocked $false; Update-Buttons
                            }
                        }
                        Refresh-Modules
                        return
                    }
                }
                [Windows.Forms.MessageBox]::Show((T 'upd.failed' @("`n", $msg, "`n`n")), (T 'word.error'), 'OK', 'Error') | Out-Null
                Refresh-Modules
                return
            }
        }
        if ($errs.Count -gt 0) {
            Write-AcLog (T 'upd.errHeader') 'ERROR'
            foreach ($e in $errs) { Write-AcLog "   $e" 'ERROR' }
            $culprits = @(Get-AcModuleFromError $script:P $errs)
            if ($culprits.Count -gt 0) { Write-AcLog (T 'upd.errModule' @(($culprits -join ', '))) 'WARN' }
            # Fehlende Include-Dateien nachschlagen: fehlt sie ueberall, braucht das
            # Modul vermutlich ein Begleitmodul oder ist unvollstaendig
            $miss = @(Get-AcMissingIncludes $script:P $errs)
            foreach ($mi in $miss) {
                if ($mi.FoundIn.Count -gt 0) {
                    Write-AcLog (T 'upd.missingInclude' @($mi.Header, ($mi.FoundIn -join ', '))) 'WARN'
                } else {
                    Write-AcLog (T 'upd.missingIncludeNone' @($mi.Header)) 'WARN'
                }
            }
            $msg = ($errs | Select-Object -First 5) -join "`r`n"
            if ($culprits.Count -gt 0) { $msg += "`r`n`r`n" + (T 'upd.errModule' @(($culprits -join ', '))) }
            foreach ($mi in $miss) {
                if ($mi.FoundIn.Count -eq 0) { $msg += "`r`n`r`n" + (T 'upd.missingIncludeNone' @($mi.Header)) }
            }
            $msg += "`r`n`r`n" + (T 'upd.errLog' @((Join-Path $script:P.Logs 'build-errors.log')))
        }
        # Einzelheiten ins Protokoll, damit die Ursache auffindbar ist
        Show-AcError $ErrRecord 'Update'
    } finally { $script:Busy = $false; Set-TabsLocked $false; Reset-Title; Update-Buttons }
    Refresh-Modules
    if ($ok) {
        Invoke-CheckUpdates -NoFetch     # nur lokaler Stand, kein erneutes git fetch
        if ($chkAutoStart.Checked -and ($wasRunning -or $Pull)) { Start-Servers }
    }
}

$btnCheck.Add_Click({ Invoke-CheckUpdates })
$btnCheckAll.Add_Click({ foreach ($it in $lvRepos.Items) { $it.Checked = $true } })
$btnCheckNone.Add_Click({ foreach ($it in $lvRepos.Items) { $it.Checked = $false } })
$btnUpdate.Add_Click({ Invoke-BuildPipeline -Pull })
$btnRebuild.Add_Click({ Invoke-BuildPipeline })

# ---------------------------------------------------------------------
#  Einstellungen (conf-Editor)
# ---------------------------------------------------------------------
$script:CfgEntries = @()
$script:CfgLoading = $false
function Get-ConfFiles {
    $list = @()
    foreach ($f in @('worldserver.conf', 'authserver.conf', 'dbimport.conf')) { $p = Join-Path $script:P.Configs $f; if (Test-Path $p) { $list += @{ Label = $f; Path = $p } } }
    if (Test-Path $script:P.ModConfigs) { foreach ($f in (Get-ChildItem $script:P.ModConfigs -Filter '*.conf' -File | Sort-Object Name)) { $list += @{ Label = "modules\$($f.Name)"; Path = $f.FullName } } }
    return $list
}
function Load-ConfFiles {
    $cmbFile.Items.Clear()
    foreach ($f in (Get-ConfFiles)) { [void]$cmbFile.Items.Add($f.Label) }
    if ($cmbFile.Items.Count -gt 0) { $cmbFile.SelectedIndex = 0 }
}
function Get-SelectedConfPath { $sel = $cmbFile.SelectedItem; foreach ($f in (Get-ConfFiles)) { if ($f.Label -eq $sel) { return $f.Path } }; return $null }
function Load-ConfGrid {
    $path = Get-SelectedConfPath
    if (-not $path) { return }
    $script:CfgLoading = $true
    $script:CfgEntries = @(Get-AcConfEntries $path)
    $grid.Rows.Clear()
    $filter = $txtFilter.Text.Trim()
    foreach ($e in $script:CfgEntries) {
        if ($filter -and ($e.Key -notlike "*$filter*") -and ($e.Description -notlike "*$filter*")) { continue }
        $idx = $grid.Rows.Add($e.Key, $e.Value)
        $grid.Rows[$idx].Tag = $e
    }
    $script:CfgLoading = $false
    $txtDesc.Text = ''
}
$cmbFile.Add_SelectedIndexChanged({ Load-ConfGrid })
$txtFilter.Add_TextChanged({ Load-ConfGrid })
$btnCfgReload.Add_Click({ Load-ConfGrid })
$grid.Add_SelectionChanged({
    if ($grid.SelectedRows.Count -gt 0 -and $grid.SelectedRows[0].Tag) { $e = $grid.SelectedRows[0].Tag; $txtDesc.Text = "$($e.Key)`r`n`r`n$($e.Description)" }
})
$grid.Add_CellValueChanged({ param($sender, $e) if (-not $script:CfgLoading -and $e.RowIndex -ge 0) { $grid.Rows[$e.RowIndex].Cells[1].Style.BackColor = 'LightYellow' } })
$btnCfgSave.Add_Click({
    $path = Get-SelectedConfPath
    if (-not $path) { return }
    $grid.EndEdit()
    $changed = 0
    foreach ($row in $grid.Rows) {
        $e = $row.Tag; if (-not $e) { continue }
        $new = [string]$row.Cells[1].Value
        if ($new -ne $e.Value) { Set-AcConfValue $path $e.Key $new; $changed++ }
    }
    Load-ConfGrid
    $msg = T 'cfg.saved' @($changed)
    if ($changed -gt 0 -and $script:World -and -not $script:World.Process.HasExited) { $msg += "`n`n" + (T 'cfg.restartHint') }
    [Windows.Forms.MessageBox]::Show($msg, (T 'tab.settings'), 'OK', 'Information') | Out-Null
})

# ---------------------------------------------------------------------
#  Module
# ---------------------------------------------------------------------
function Refresh-Modules {
    $lvMods.Items.Clear()
    $lvMods.Groups.Clear()
    if (-not (Test-Path $script:P.Modules)) { return }

    $grpMod = New-Object Windows.Forms.ListViewGroup((T 'mod.branchModules' @(0)))
    $grpLua = New-Object Windows.Forms.ListViewGroup((T 'mod.branchLua' @(0)))
    [void]$lvMods.Groups.Add($grpMod)
    [void]$lvMods.Groups.Add($grpLua)

    # --- C++-Module ---
    $count = 0
    foreach ($d in (Get-ChildItem $script:P.Modules -Directory | Sort-Object Name)) {
        if ($d.Name -like '_*') { continue }
        $count++
        $modKey = ($d.Name -replace '[-_]', '').ToLower()
        $conf = Get-ChildItem $script:P.ModConfigs -Filter '*.conf' -File -ErrorAction SilentlyContinue | Where-Object { $k = ($_.BaseName -replace '[-_]', '').ToLower(); $modKey.Contains($k) -or $k.Contains(($modKey -replace '^mod', '')) } | Select-Object -First 1
        $sql = Get-AcModuleSqlSummary $d.FullName
        # offen ist nur, was weder automatisch laeuft noch von Hand eingespielt wurde
        $open = @(Get-AcModuleSqlFiles $d.FullName | Where-Object { $_.Status -in @('legacy', 'unknown', 'optional') }).Count
        $built = Test-AcModuleBuilt $script:S $d.Name
        $it = New-Object Windows.Forms.ListViewItem($d.Name)
        [void]$it.SubItems.Add($(if (Test-Path (Join-Path $d.FullName '.git')) { T 'word.yesShort' } else { T 'word.noShort' }))
        [void]$it.SubItems.Add($(if ($conf) { $conf.Name } else { '-' }))
        [void]$it.SubItems.Add($sql)
        [void]$it.SubItems.Add($(if ($built -and -not $script:S.NeedsRebuild) { T 'mod.built' } else { T 'mod.pending' }))
        if (-not $built) { $it.ForeColor = Get-AcColor 'Bad' }
        elseif ($open -gt 0) { $it.ForeColor = Get-AcColor 'Warn' }
        $it.Tag = @{ Kind = 'module'; Name = $d.Name }
        $it.Group = $grpMod
        [void]$lvMods.Items.Add($it)
    }

    # --- Lua-Skriptpakete --- (eine Stoerung hier darf die Modulliste nicht kippen)
    $pkgs = @{}
    try {
        foreach ($s in @(Get-AcLuaScripts $script:P)) {
            if (-not $s) { continue }
            $parts = @([string]$s.Rel -split '\\')
            $pkg = $(if ($parts.Count -gt 1) { [string]$parts[0] } else { T 'lua.loose' })
            if (-not $pkgs.ContainsKey($pkg)) { $pkgs[$pkg] = New-Object Collections.Generic.List[object] }
            $pkgs[$pkg].Add($s)
        }
    } catch {
        # mit Fundstelle protokollieren, sonst ist die Ursache nicht auffindbar
        $at = ''
        try { $at = " (" + (Split-Path $_.InvocationInfo.ScriptName -Leaf) + ":" + $_.InvocationInfo.ScriptLineNumber + " -> " + ([string]$_.InvocationInfo.Line).Trim() + ")" } catch {}
        Write-AcLog ("Refresh-Modules (Lua): " + $_.Exception.Message + $at) 'WARN'
    }
    $luaDir = [string](Get-AcLuaScriptPath $script:P)
    foreach ($pkg in ($pkgs.Keys | Sort-Object)) {
        $items = $pkgs[$pkg]
        $active = @($items | Where-Object { $_.Enabled }).Count
        $it = New-Object Windows.Forms.ListViewItem($pkg)
        $hasGit = $false
        if ($luaDir) { try { $hasGit = (Test-Path -LiteralPath (Join-Path (Join-Path $luaDir $pkg) '.git')) } catch {} }
        [void]$it.SubItems.Add($(if ($hasGit) { T 'word.yesShort' } else { T 'word.noShort' }))
        [void]$it.SubItems.Add('-')
        [void]$it.SubItems.Add((T 'lua.pkgFiles' @($items.Count, $active)))
        [void]$it.SubItems.Add($(if ($active -gt 0) { T 'lua.active' } else { T 'lua.inactive' }))
        if ($active -eq 0) { $it.ForeColor = Get-AcColor 'TextDim' }
        $it.Tag = @{ Kind = 'luapkg'; Name = $pkg }
        $it.Group = $grpLua
        [void]$lvMods.Items.Add($it)
    }

    $grpMod.Header = T 'mod.branchModules' @($count)
    $grpLua.Header = T 'mod.branchLua' @($pkgs.Count)

    $unbuilt = @(Get-AcModuleNames $script:P | Where-Object { -not (Test-AcModuleBuilt $script:S $_) })
    $lblModHint.Text = if ($script:S.NeedsRebuild -or $unbuilt.Count -gt 0) {
        if ($unbuilt.Count -gt 0) { T 'mod.notBuiltHint' @(($unbuilt -join ', ')) } else { T 'mod.rebuildHint' }
    } else { '' }
}


function Get-SelectedModuleName {
    if ($lvMods.SelectedItems.Count -eq 0) { return $null }
    $tag = $lvMods.SelectedItems[0].Tag
    if ($tag -and $tag.Kind -eq 'module') { return [string]$tag.Name }
    return $null
}

function Test-SelectedIsLua {
    if ($lvMods.SelectedItems.Count -eq 0) { return $false }
    $tag = $lvMods.SelectedItems[0].Tag
    return ($tag -and $tag.Kind -eq 'luapkg')
}

function Mark-Rebuild { $script:S.NeedsRebuild = $true; Save-AcSettings $script:P.Root $script:S; Refresh-Modules }

$dragEnter = { param($sender, $e) if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy; $drop.BackColor = 'Honeydew' } }
$dragLeave = { $drop.BackColor = 'WhiteSmoke' }
$dragDrop = {
    param($sender, $e)
    $drop.BackColor = 'WhiteSmoke'
    $script:OpLogTarget = $modLog
    if (-not $e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { return }
    foreach ($f in $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
        try {
            $name = Install-AcModuleFromPath $script:P $f
            Write-AcLog (T 'mod.added' @($name)) 'STEP'
            if (Resolve-LuaPackageInstall $name) { continue }
            Update-AcSubmodules (Join-Path $script:P.Modules $name) | Out-Null
            $sync = Sync-AcModuleSql (Join-Path $script:P.Modules $name) $name
            Mark-Rebuild
            Show-SqlSyncResult $sync
        } catch { Write-AcLog "Fehler: $($_.Exception.Message)" 'ERROR'; [Windows.Forms.MessageBox]::Show($_.Exception.Message, (T 'tab.modules'), 'OK', 'Warning') | Out-Null }
    }
}
foreach ($c in @($drop, $dropLbl)) { $c.Add_DragEnter($dragEnter); $c.Add_DragLeave($dragLeave); $c.Add_DragDrop($dragDrop) }

$btnGitAdd.Add_Click({
    $url = $txtGitUrl.Text.Trim()
    if (-not $url) { return }
    $script:OpLogTarget = $modLog; $script:Busy = $true; Update-Buttons
    try {
        $name = Install-AcModuleFromGit $script:P $url
        Write-AcLog (T 'mod.cloned' @($name)) 'STEP'
        $txtGitUrl.Clear()
        if (Resolve-LuaPackageInstall $name) { return }
        Update-AcSubmodules (Join-Path $script:P.Modules $name) | Out-Null
        $sync = Sync-AcModuleSql (Join-Path $script:P.Modules $name) $name
        Mark-Rebuild
        Show-SqlSyncResult $sync
    } catch { Write-AcLog "Fehler: $($_.Exception.Message)" 'ERROR' }
    finally { $script:Busy = $false; Update-Buttons }
})
$btnModRemove.Add_Click({
    $name = Get-SelectedModuleName
    if (-not $name) { [Windows.Forms.MessageBox]::Show((T 'mod.selectFirst')) | Out-Null; return }
    if ($name -eq 'mod-playerbots' -and $script:S.Variant -eq 'playerbots') { [Windows.Forms.MessageBox]::Show((T 'mod.protected'), (T 'tab.modules'), 'OK', 'Warning') | Out-Null; return }
    if ([Windows.Forms.MessageBox]::Show((T 'mod.removeConfirm' @($name, "`n")), (T 'mod.removeTitle'), 'YesNo', 'Question') -ne 'Yes') { return }
    $script:OpLogTarget = $modLog
    if (Remove-AcDirectoryForce (Join-Path $script:P.Modules $name)) {
        Write-AcLog (T 'mod.removed' @($name)) 'STEP'
        Mark-Rebuild
    } else {
        [Windows.Forms.MessageBox]::Show((T 'mod.removeHint' @($name, (Join-Path $script:P.Modules $name), "`r`n")), (T 'word.error'), 'OK', 'Error') | Out-Null
    }
})
$btnModBuild.Add_Click({ Invoke-BuildPipeline })

# ---------------------------------------------------------------------
#  Modul-Info: was fuegt ein Modul in die Welt ein?
# ---------------------------------------------------------------------
function Show-ModuleInfoDialog {
    param([string]$ModuleName)
    $modPath = Join-Path $script:P.Modules $ModuleName
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'info.dlgTitle' @($ModuleName)
    $dlg.Size = New-Object Drawing.Size(900, 620); $dlg.StartPosition = 'CenterParent'; $dlg.Font = $form.Font
    $txt = New-Object Windows.Forms.TextBox
    $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = 'Both'; $txt.WordWrap = $false
    $txt.Font = New-Object Drawing.Font('Consolas', 9.5)
    $txt.Location = New-Object Drawing.Point(12, 12); $txt.Size = New-Object Drawing.Size(860, 520)
    $txt.Anchor = 'Top,Left,Right,Bottom'
    $txt.Text = T 'info.analyzing'
    $btnCopy = New-Btn (T 'btn.copy') 12 544 200 30; $btnCopy.Anchor = 'Left,Bottom'
    $btnOpenMod = New-Btn (T 'btn.openFolder') 222 544 140 30; $btnOpenMod.Anchor = 'Left,Bottom'
    $btnOpenReadme = New-Btn (T 'info.openReadme') 372 544 170 30; $btnOpenReadme.Anchor = 'Left,Bottom'; $btnOpenReadme.Enabled = $false
    $btnDbc = New-Btn (T 'info.applyDbc') 552 544 200 30; $btnDbc.Anchor = 'Left,Bottom'; $btnDbc.Enabled = $false
    $btnCloseInfo = New-Btn (T 'btn.close') 772 544 100 30; $btnCloseInfo.Anchor = 'Right,Bottom'
    $btnCloseInfo.Add_Click({ $dlg.Close() })
    $btnOpenMod.Add_Click({ Start-Process explorer.exe $modPath })
    $btnOpenReadme.Add_Click({ if ($script:CurrentReadme) { Start-Process $script:CurrentReadme } })
    $btnDbc.Add_Click({
        if (-not (Test-WorldStopped)) { [Windows.Forms.MessageBox]::Show((T 'info.dbcNeedStop'), (T 'word.warning'), 'OK', 'Warning') | Out-Null; return }
        if ([Windows.Forms.MessageBox]::Show((T 'info.dbcConfirm'), (T 'info.headDbc'), 'YesNo', 'Question') -ne 'Yes') { return }
        try {
            $script:OpLogTarget = $modLog
            $r = Install-AcModuleDbc $script:P $modPath
            $msg = T 'info.dbcDone' @($r.Copied.Count)
            if ($r.Backup) { $msg += "`r`n`r`n" + (T 'info.dbcBackup' @($r.Backup)) }
            $msg += "`r`n`r`n" + (T 'info.dbcClientHint')
            [Windows.Forms.MessageBox]::Show($msg, (T 'info.headDbc'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
    })
    $btnCopy.Add_Click({
        try { [Windows.Forms.Clipboard]::SetText($txt.Text); [Windows.Forms.MessageBox]::Show((T 'info.copied')) | Out-Null } catch {}
    })
    $dlg.Controls.AddRange(@($txt, $btnCopy, $btnOpenMod, $btnOpenReadme, $btnDbc, $btnCloseInfo))
    $dlg.Add_Shown({
        $dlg.Cursor = 'WaitCursor'; Invoke-AcDoEvents
        try {
            $info = Get-AcModuleInfo $modPath $script:P
            $txt.Text = Format-AcModuleInfo $info
            if ($info.ReadmePath) {
                $script:CurrentReadme = $info.ReadmePath
                $btnOpenReadme.Enabled = $true
            }
            if ($info.DbcFiles.Count -gt 0) { $btnDbc.Enabled = $true }
        }
        catch { $txt.Text = $_.Exception.Message }
        finally { $dlg.Cursor = 'Default' }
        $txt.SelectionStart = 0; $txt.SelectionLength = 0
    })
    [void]$dlg.ShowDialog($form)
}

$btnModInfo.Add_Click({
    $sel = Get-SelectedModuleName
    if (-not $sel) {
        if (Test-SelectedIsLua) { Show-LuaDialog; return }
        [Windows.Forms.MessageBox]::Show((T 'mod.selectFirst')) | Out-Null; return
    }
    Show-ModuleInfoDialog $sel
})
$lvMods.Add_DoubleClick({
    # Doppelklick oeffnet die Konfiguration des Moduls - die Info liegt auf dem Knopf
    $sel = Get-SelectedModuleName
    if ($sel) { Show-ModuleConfigDialog $sel }
    elseif (Test-SelectedIsLua) { Show-LuaDialog }
})


# ---------------------------------------------------------------------
#  Charakter-Tab aufbauen
# ---------------------------------------------------------------------
$tabChar = New-Object Windows.Forms.TabPage
$tabChar.Text = 'Characters'; $tabChar.Padding = New-Object Windows.Forms.Padding(8)
# anhaengen statt einfuegen (TabPages.Insert haengt die Seite nicht zuverlaessig ein),
# danach den Info-Tab wieder ans Ende schieben
$tabs.TabPages.Add($tabChar)
$tabs.TabPages.Remove($tabInfo)
$tabs.TabPages.Add($tabInfo)

$btnCharReload = New-Btn 'Reload list' 12 10 150 30
$chkShowBots = New-Object Windows.Forms.CheckBox
$chkShowBots.Location = New-Object Drawing.Point(172, 14); $chkShowBots.Size = New-Object Drawing.Size(230, 24)
$lblCharSearch = New-Lbl 'Search:' 410 16 60 $true
$txtCharSearch = New-Object Windows.Forms.TextBox
$txtCharSearch.Location = New-Object Drawing.Point(470, 12); $txtCharSearch.Size = New-Object Drawing.Size(200, 26)
$lblCharWarn = New-Lbl '' 12 96 900 $false; $lblCharWarn.ForeColor = 'DarkRed'

$lvChars = New-Object Windows.Forms.ListView
$lvChars.View = 'Details'; $lvChars.FullRowSelect = $true; $lvChars.GridLines = $true; $lvChars.HideSelection = $false
$lvChars.Location = New-Object Drawing.Point(12, 70); $lvChars.Size = New-Object Drawing.Size(400, 400)
foreach ($c in @(@('chr.colGuid', 70), @('chr.colName', 150), @('chr.colLevel', 55), @('chr.colClass', 110), @('chr.colRace', 100), @('chr.colAccount', 150), @('chr.colOnline', 70))) {
    [void]$lvChars.Columns.Add((T $c[0]), $c[1])
}

$lblCharHead = New-Lbl '' 430 70 500 $true
$lblCharHead.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblXpWarn = New-Lbl '' 430 118 500 $false; $lblXpWarn.ForeColor = 'DarkOrange'

# Ausruestungsplaetze wie in der Armory: links / rechts / unten
$script:SlotTip = New-Object Windows.Forms.ToolTip
$script:SlotTip.AutoPopDelay = 20000; $script:SlotTip.InitialDelay = 300; $script:SlotTip.ReshowDelay = 100
$script:SlotButtons = @()
$slotLayout = @(
    @{ Slot = 0;  Col = 0; Row = 0 }, @{ Slot = 1;  Col = 0; Row = 1 }, @{ Slot = 2;  Col = 0; Row = 2 }
    @{ Slot = 14; Col = 0; Row = 3 }, @{ Slot = 4;  Col = 0; Row = 4 }, @{ Slot = 3;  Col = 0; Row = 5 }
    @{ Slot = 18; Col = 0; Row = 6 }, @{ Slot = 8;  Col = 0; Row = 7 }, @{ Slot = 15; Col = 0; Row = 8 }
    @{ Slot = 16; Col = 0; Row = 9 }
    @{ Slot = 9;  Col = 1; Row = 0 }, @{ Slot = 5;  Col = 1; Row = 1 }, @{ Slot = 6;  Col = 1; Row = 2 }
    @{ Slot = 7;  Col = 1; Row = 3 }, @{ Slot = 10; Col = 1; Row = 4 }, @{ Slot = 11; Col = 1; Row = 5 }
    @{ Slot = 12; Col = 1; Row = 6 }, @{ Slot = 13; Col = 1; Row = 7 }, @{ Slot = 17; Col = 1; Row = 8 }
)
foreach ($sl in $slotLayout) {
    $def = $script:AcEquipSlots | Where-Object { $_.Slot -eq $sl.Slot } | Select-Object -First 1
    $b = New-Object Windows.Forms.Button
    $b.Size = New-Object Drawing.Size(180, 24)
    $b.TextAlign = 'MiddleLeft'; $b.FlatStyle = 'System'
    $b.Text = (T $def.Key) + ': ' + (T 'chr.empty')
    $b.Tag = @{ Slot = $def.Slot; Inv = $def.Inv; Item = $null }
    $b.Add_Click({ Show-ItemPickerDialog $this.Tag }.GetNewClosure())
    $script:SlotButtons += @{ Slot = $def.Slot; Key = $def.Key; Inv = $def.Inv; Button = $b; Col = $sl.Col; Row = $sl.Row }
    $tabChar.Controls.Add($b)
}

$lblCharVals = New-Lbl '' 430 400 500 $true
$gridChar = New-Object Windows.Forms.DataGridView
$gridChar.Location = New-Object Drawing.Point(430, 424); $gridChar.Size = New-Object Drawing.Size(500, 200)
$gridChar.AllowUserToAddRows = $false; $gridChar.AllowUserToDeleteRows = $false; $gridChar.RowHeadersVisible = $false
$gridChar.SelectionMode = 'FullRowSelect'; $gridChar.MultiSelect = $false; $gridChar.AutoSizeColumnsMode = 'Fill'
[void]$gridChar.Columns.Add('Field', 'Setting'); [void]$gridChar.Columns.Add('Value', 'Value')
$gridChar.Columns[0].ReadOnly = $true; $gridChar.Columns[0].FillWeight = 55; $gridChar.Columns[1].FillWeight = 45
$btnAutoEquip = New-Btn 'Auto-equip...' 700 66 220 28
$btnCharExport = New-Btn 'Export character...' 12 560 160 30
$btnCharImport = New-Btn 'Import character...' 180 560 160 30
$btnCharSave = New-Btn 'Save values' 12 600 200 34
$btnCharSave.Tag = 'primary'
$btnCharSave.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $btnCharSave.Tag = 'primary'

$tabChar.Controls.AddRange(@($btnCharReload, $chkShowBots, $lblCharSearch, $txtCharSearch, $lblCharWarn,
                             $lvChars, $lblCharHead, $lblXpWarn, $lblCharVals, $gridChar,
                             $btnAutoEquip, $btnCharExport, $btnCharImport, $btnCharSave))

$layoutChar = {
    $w = $tabChar.ClientSize.Width; $h = $tabChar.ClientSize.Height
    $listW = [Math]::Max(320, [int]($w * 0.34))
    $lvChars.Location = New-Object Drawing.Point(12, 120)
    $lvChars.Size = New-Object Drawing.Size($listW, ($h - 212))
    # Spalten an die Listenbreite anpassen, damit kein waagerechter Balken noetig ist
    if ($lvChars.Columns.Count -ge 6) {
        $free = $listW - 24
        $wid = @(0.13, 0.30, 0.10, 0.23, 0.24)
        for ($i = 0; $i -lt 5; $i++) { $lvChars.Columns[$i].Width = [int]($free * $wid[$i]) }
        $lvChars.Columns[5].Width = 0
    }
    $btnCharExport.Location = New-Object Drawing.Point(12, ($h - 80))
    $btnCharImport.Location = New-Object Drawing.Point(180, ($h - 80))
    $btnCharSave.Location = New-Object Drawing.Point(12, ($h - 42))
    $lblCharWarn.Location = New-Object Drawing.Point(12, 96)
    $lblCharWarn.Size = New-Object Drawing.Size(($w - 24), 20)

    $rx = $listW + 24
    $rw = [Math]::Max(320, $w - $rx - 12)
    $lblCharHead.Location = New-Object Drawing.Point($rx, 120); $lblCharHead.Size = New-Object Drawing.Size($rw, 26)
    $lblXpWarn.Location = New-Object Drawing.Point($rx, 146); $lblXpWarn.Size = New-Object Drawing.Size($rw, 18)

    # Ausruestung fuellt die volle Breite: zwei gleich breite Spalten
    $rowH = 26
    $top = 170
    $gap = 12
    $bw = [int](($rw - $gap) / 2)
    foreach ($s in $script:SlotButtons) {
        $bx = $rx + $s.Col * ($bw + $gap)
        $by = $top + $s.Row * $rowH
        $s.Button.Location = New-Object Drawing.Point($bx, $by)
        $s.Button.Size = New-Object Drawing.Size($bw, ($rowH - 3))
    }
    # Auto-Equip im freien Feld des Rasters (rechte Spalte, letzte Zeile)
    $btnAutoEquip.Location = New-Object Drawing.Point(($rx + $bw + $gap), ($top + 9 * $rowH))
    $btnAutoEquip.Size = New-Object Drawing.Size($bw, ($rowH - 3))

    $gridTop = $top + (10 * $rowH) + 26
    $lblCharVals.Location = New-Object Drawing.Point($rx, ($gridTop - 22)); $lblCharVals.Size = New-Object Drawing.Size($rw, 20)
    $gridChar.Location = New-Object Drawing.Point($rx, $gridTop)
    $gridChar.Size = New-Object Drawing.Size($rw, [Math]::Max(140, $h - $gridTop - 12))
}
$tabChar.Add_Resize($layoutChar)

$btnCharReload.Add_Click({ Refresh-CharList })
$chkShowBots.Add_CheckedChanged({ Refresh-CharList })
$txtCharSearch.Add_TextChanged({ Refresh-CharList })
$lvChars.Add_SelectedIndexChanged({
    if ($lvChars.SelectedItems.Count -gt 0) { Show-CharacterDetails $lvChars.SelectedItems[0].Tag }
})
function Show-RolePicker {
    # Kleiner Dialog fuer die Rollenwahl - der Vorschlag richtet sich nach der Klasse
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'chr.autoTitle'; $dlg.Size = New-Object Drawing.Size(380, 170)
    $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false; $dlg.Font = $form.Font
    $lbl = New-Lbl (T 'chr.role') 16 22 90 $true
    $cmb = New-Object Windows.Forms.ComboBox
    $cmb.DropDownStyle = 'DropDownList'; $cmb.Location = New-Object Drawing.Point(110, 18); $cmb.Size = New-Object Drawing.Size(230, 26)
    foreach ($r in $script:AcRoleKeys) { [void]$cmb.Items.Add((T ('role.' + $r))) }
    $idx = 1
    if ($script:SuggestedRole) { $i = $script:AcRoleKeys.IndexOf($script:SuggestedRole); if ($i -ge 0) { $idx = $i } }
    $cmb.SelectedIndex = $idx
    $ok = New-Btn 'OK' 110 74 110 32; $ok.DialogResult = 'OK'; $ok.Tag = 'primary'
    $no = New-Btn (T 'btn.cancel') 230 74 110 32; $no.DialogResult = 'Cancel'
    $dlg.Controls.AddRange(@($lbl, $cmb, $ok, $no)); $dlg.AcceptButton = $ok; $dlg.CancelButton = $no
    Update-AcTheme $dlg
    if ($dlg.ShowDialog($form) -ne 'OK') { return $null }
    return $script:AcRoleKeys[$cmb.SelectedIndex]
}

$btnAutoEquip.Add_Click({
    if (-not $script:CurrentChar) { [Windows.Forms.MessageBox]::Show((T 'chr.noSelection')) | Out-Null; return }
    if (-not (Test-WorldStopped)) { [Windows.Forms.MessageBox]::Show((T 'chr.itemNeedStop'), (T 'word.warning'), 'OK', 'Warning') | Out-Null; return }
    if ($script:DbBusy) { return }
    $role = Show-RolePicker
    if (-not $role) { return }
    $lvl = [int]$script:CurrentChar.level
    $ask = (T 'chr.autoConfirm' @($script:CurrentChar.name, $lvl, (T ('role.' + $role)), "`r`n")) +
           "`r`n`r`n" + (T 'chr.autoIlvlNote' @((Get-AcMaxItemLevel $lvl)))
    if ([Windows.Forms.MessageBox]::Show($ask, (T 'chr.autoTitle'), 'YesNo', 'Warning') -ne 'Yes') { return }
    if (-not (Confirm-DbStart 'db.reasonChars')) { return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.autoWorking')
        if (-not (Test-AcCharacterEditable $script:P ([int]$script:CurrentChar.guid))) { throw (T 'chr.onlineBlocked') }
        $plan = @(Get-AcAutoEquipPlan $script:P ([int]$script:CurrentChar.class) $lvl $role)
        if ($plan.Count -eq 0) { throw (T 'chr.autoNothing') }
        # Vorschau: was wuerde angelegt?
        $preview = New-Object Text.StringBuilder
        foreach ($p in $plan) {
            if ($p.Clear) { [void]$preview.AppendLine((T $p.Key) + ": " + (T 'chr.empty')) }
            else { [void]$preview.AppendLine((T $p.Key) + ": " + $p.Item.name + "  (" + (T 'chr.itemColIlvl') + " " + $p.Item.ItemLevel + ")") }
        }
        Set-CharBusy $false
        if ([Windows.Forms.MessageBox]::Show((T 'chr.autoPreview' @("`r`n")) + "`r`n`r`n" + $preview.ToString(), (T 'chr.autoTitle'), 'OKCancel', 'Information') -ne 'OK') { return }
        Set-CharBusy $true (T 'chr.autoWorking')
        $n = Invoke-AcAutoEquip $script:P ([int]$script:CurrentChar.guid) $plan
        Set-CharBusy $false
        Show-CharacterDetails $script:CurrentChar
        [Windows.Forms.MessageBox]::Show((T 'chr.autoDone' @($n)), (T 'chr.autoTitle'), 'OK', 'Information') | Out-Null
    } catch {
        Show-AcError $_
    } finally { Set-CharBusy $false }
})


$btnCharExport.Add_Click({
    if (-not $script:CurrentChar) { [Windows.Forms.MessageBox]::Show((T 'chr.noSelection')) | Out-Null; return }
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json'
    $dlg.FileName = ("character-" + $script:CurrentChar.name + ".json")
    if ($dlg.ShowDialog() -ne 'OK') { return }
    if (-not (Confirm-DbStart 'db.reasonChars')) { return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.loading')
        $r = Export-AcCharacter $script:P ([int]$script:CurrentChar.guid) $dlg.FileName
        Set-CharBusy $false
        [Windows.Forms.MessageBox]::Show((T 'chr.exportDone2' @($r.Name, $r.Items, $r.Bag, $r.Spells, $r.Achievements, $r.Quests, "`r`n")), (T 'tab.chars'), 'OK', 'Information') | Out-Null
    } catch {
        Show-AcError $_
    } finally { Set-CharBusy $false }
})

$btnCharImport.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    # Der Worldserver vergibt Item-GUIDs aus einem eigenen Zaehler. Laeuft er
    # waehrend des Imports, entstehen doppelte GUIDs - deshalb vorher stoppen.
    if (-not (Test-WorldStopped)) {
        $r = [Windows.Forms.MessageBox]::Show((T 'chr.importServerRunning' @("`r`n")), (T 'chr.import'), 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
        try {
            $tabs.SelectedTab = $tabServer
            Stop-Servers -KeepMySql
        } catch {
            Show-AcError $_
            return
        }
        if (-not (Test-WorldStopped)) {
            [Windows.Forms.MessageBox]::Show((T 'chr.importStopFailed'), (T 'word.error'), 'OK', 'Error') | Out-Null
            return
        }
        $tabs.SelectedTab = $tabChar
    }
    if (-not (Confirm-DbStart 'db.reasonChars')) { return }
    try {
        Ensure-CharDb
        $doc = Read-AcCharacterFile $dlg.FileName
        $charFields = @{}
        if ($doc.character -is [hashtable]) { foreach ($k in $doc.character.Keys) { $charFields[[string]$k] = [string]$doc.character[$k] } }
        else { foreach ($p in $doc.character.PSObject.Properties) { $charFields[[string]$p.Name] = [string]$p.Value } }
        $srcName = [string]$charFields['name']
        $accounts = @(Get-AcAccounts $script:P (Get-AcBotAccountPrefix $script:P))
        if ($accounts.Count -eq 0) { [Windows.Forms.MessageBox]::Show((T 'chr.importNoAccount'), (T 'word.error'), 'OK', 'Error') | Out-Null; return }

        # Dialog: neu anlegen oder vorhandenen Charakter aktualisieren
        $srcRace = 0; [void][int]::TryParse($charFields['race'], [ref]$srcRace)
        $srcClass = 0; [void][int]::TryParse($charFields['class'], [ref]$srcClass)
        $matching = @($script:CharList | Where-Object { [int]$_.race -eq $srcRace -and [int]$_.class -eq $srcClass })

        $d2 = New-Object Windows.Forms.Form
        $d2.Text = T 'chr.import'; $d2.Size = New-Object Drawing.Size(560, 340)
        $d2.StartPosition = 'CenterParent'; $d2.FormBorderStyle = 'FixedDialog'
        $d2.MinimizeBox = $false; $d2.MaximizeBox = $false; $d2.Font = $form.Font
        $lblInfo = New-Lbl (T 'chr.importInfo2' @($srcName, [string]$charFields['level'], (Get-AcRaceName $srcRace), (Get-AcClassName $srcClass), @($doc.equipment).Count)) 16 14 520 $false
        $lblInfo.Size = New-Object Drawing.Size(520, 36)

        $rbNew = New-Object Windows.Forms.RadioButton
        $rbNew.Text = T 'chr.importModeNew'; $rbNew.Location = New-Object Drawing.Point(16, 58); $rbNew.Size = New-Object Drawing.Size(520, 24); $rbNew.Checked = $true
        $lblAcc = New-Lbl (T 'chr.importAccount') 36 90 120 $true
        $cmbAcc = New-Object Windows.Forms.ComboBox
        # tippbar: bei vielen Konten schneller als scrollen
        $cmbAcc.DropDownStyle = 'DropDown'; $cmbAcc.AutoCompleteMode = 'SuggestAppend'; $cmbAcc.AutoCompleteSource = 'ListItems'
        $cmbAcc.Location = New-Object Drawing.Point(170, 86); $cmbAcc.Size = New-Object Drawing.Size(350, 26)
        foreach ($a in $accounts) {
            $suffix = $(if ($a.Characters -gt 0) { "  (" + (T 'chr.accountChars' @($a.Characters)) + ")" } else { '' })
            [void]$cmbAcc.Items.Add($a.Name + $suffix)
        }
        $cmbAcc.SelectedIndex = 0
        $lblNm = New-Lbl (T 'chr.importName') 36 124 120 $true
        $txtNm = New-Object Windows.Forms.TextBox
        $txtNm.Location = New-Object Drawing.Point(170, 120); $txtNm.Size = New-Object Drawing.Size(350, 26); $txtNm.Text = $srcName

        $rbUpd = New-Object Windows.Forms.RadioButton
        $rbUpd.Text = T 'chr.importModeUpdate'; $rbUpd.Location = New-Object Drawing.Point(16, 158); $rbUpd.Size = New-Object Drawing.Size(520, 24)
        $rbUpd.Enabled = ($matching.Count -gt 0)
        $lblTgt = New-Lbl (T 'chr.importTarget') 36 190 120 $true
        $cmbTgt = New-Object Windows.Forms.ComboBox
        $cmbTgt.DropDownStyle = 'DropDownList'; $cmbTgt.Location = New-Object Drawing.Point(170, 186); $cmbTgt.Size = New-Object Drawing.Size(350, 26)
        foreach ($c in $matching) { [void]$cmbTgt.Items.Add("$($c.name)  (" + (T 'chr.colLevel') + " $($c.level), GUID $($c.guid))") }
        if ($matching.Count -gt 0) { $cmbTgt.SelectedIndex = 0 }
        $lblKeep = New-Lbl (T 'chr.importKeeps') 36 216 490 $false
        $lblKeep.Size = New-Object Drawing.Size(490, 34); $lblKeep.ForeColor = Get-AcColor 'TextDim'

        $ok2 = New-Btn 'OK' 280 262 130 32; $ok2.DialogResult = 'OK'; $ok2.Tag = 'primary'
        $no2 = New-Btn (T 'btn.cancel') 420 262 110 32; $no2.DialogResult = 'Cancel'
        $d2.Controls.AddRange(@($lblInfo, $rbNew, $lblAcc, $cmbAcc, $lblNm, $txtNm, $rbUpd, $lblTgt, $cmbTgt, $lblKeep, $ok2, $no2))
        $d2.AcceptButton = $ok2; $d2.CancelButton = $no2

        $syncMode = {
            foreach ($c in @($lblAcc, $cmbAcc, $lblNm, $txtNm)) { $c.Enabled = $rbNew.Checked }
            foreach ($c in @($lblTgt, $cmbTgt)) { $c.Enabled = $rbUpd.Checked }
        }
        $rbNew.Add_CheckedChanged($syncMode); $rbUpd.Add_CheckedChanged($syncMode)
        & $syncMode
        Update-AcTheme $d2
        if ($d2.ShowDialog($form) -ne 'OK') { return }

        if ($rbUpd.Checked) {
            $tgt = $matching[$cmbTgt.SelectedIndex]
            $ask = T 'chr.updateConfirm' @($tgt.name, $srcName, "`r`n")
            if ([Windows.Forms.MessageBox]::Show($ask, (T 'chr.import'), 'YesNo', 'Warning') -ne 'Yes') { return }
            if (-not (Test-AcCharacterEditable $script:P ([int]$tgt.guid))) { throw (T 'chr.onlineBlocked') }
            Set-CharBusy $true (T 'chr.loading')
            $res = Update-AcCharacterFromFile $script:P $doc ([int]$tgt.guid)
            Set-CharBusy $false
            Refresh-CharList
            $msg = T 'chr.updateDone' @($tgt.name, $res.Items, "`r`n")
            $msg += "`r`n" + (T 'chr.transferSummary' @($res.Bag, $res.Mailed, $res.Achievements, $res.Quests))
            if ($res.Mailed -gt 0) { $msg += "`r`n" + (T 'chr.mailedHint' @($res.Mailed)) }
            [Windows.Forms.MessageBox]::Show($msg, (T 'tab.chars'), 'OK', 'Information') | Out-Null
        } else {
            $typed = $cmbAcc.Text.Trim()
            $target = $accounts | Where-Object { $_.Name -eq (($typed -split '  \(')[0]).Trim() } | Select-Object -First 1
            if (-not $target -and $cmbAcc.SelectedIndex -ge 0) { $target = $accounts[$cmbAcc.SelectedIndex] }
            if (-not $target) { [Windows.Forms.MessageBox]::Show((T 'chr.accountUnknown' @($typed)), (T 'word.error'), 'OK', 'Error') | Out-Null; return }
            $newName = $txtNm.Text.Trim()
            if (-not $newName) { return }
            Set-CharBusy $true (T 'chr.loading')
            $res = Import-AcCharacter $script:P $doc $target.Id $newName
            Set-CharBusy $false
            Refresh-CharList
            $msg = T 'chr.importDone' @($newName, $target.Name, $res.Items, "`r`n")
            $msg += "`r`n" + (T 'chr.transferSummary' @($res.Bag, $res.Mailed, $res.Achievements, $res.Quests))
            if ($res.Mailed -gt 0) { $msg += "`r`n" + (T 'chr.mailedHint' @($res.Mailed)) }
            [Windows.Forms.MessageBox]::Show($msg, (T 'tab.chars'), 'OK', 'Information') | Out-Null
        }
    } catch {
        Show-AcError $_
    } finally { Set-CharBusy $false }
})

$btnCharSave.Add_Click({
    if (-not $script:CurrentChar) { [Windows.Forms.MessageBox]::Show((T 'chr.noSelection')) | Out-Null; return }
    $gridChar.EndEdit()
    if ($script:DbBusy) { return }
    $vals = @{}
    foreach ($row in $gridChar.Rows) {
        $tag = $row.Tag; if (-not $tag) { continue }
        $new = [string]$row.Cells[1].Value
        if ($new -ne $tag.Original) { $vals[$tag.Col] = $new }
    }
    if ($vals.Count -eq 0) { return }
    $n = 0; $ok = $false
    if (-not (Confirm-DbStart 'db.reasonChars')) { return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.loading')
        if (-not (Test-AcCharacterEditable $script:P ([int]$script:CurrentChar.guid))) { throw (T 'chr.onlineBlocked') }
        $n = Set-AcCharacterValues $script:P ([int]$script:CurrentChar.guid) $vals
        $ok = $true
    } catch { Show-AcError $_ }
    finally { Set-CharBusy $false }
    if ($ok) {
        Show-CharacterDetails $script:CurrentChar
        Refresh-CharList
        [Windows.Forms.MessageBox]::Show((T 'chr.saved' @($n)), (T 'tab.chars'), 'OK', 'Information') | Out-Null
    }
})


# ---------------------------------------------------------------------
#  Modul-Konfiguration (eigene .conf je Modul)
# ---------------------------------------------------------------------
function Get-AcModuleConfPath {
    param([string]$ModuleName)
    if (-not (Test-Path $script:P.ModConfigs)) { return $null }
    $modKey = ($ModuleName -replace '[-_]', '').ToLower()
    $hit = Get-ChildItem $script:P.ModConfigs -Filter '*.conf' -File -ErrorAction SilentlyContinue |
           Where-Object { $k = ($_.BaseName -replace '[-_]', '').ToLower(); $modKey.Contains($k) -or $k.Contains(($modKey -replace '^mod', '')) } |
           Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Show-ModuleConfigDialog {
    param([string]$ModuleName)
    $path = Get-AcModuleConfPath $ModuleName
    if (-not $path) { [Windows.Forms.MessageBox]::Show((T 'mod.cfgNone'), (T 'tab.modules'), 'OK', 'Information') | Out-Null; return }

    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'mod.cfgTitle' @((Split-Path $path -Leaf))
    $dlg.Size = New-Object Drawing.Size(900, 640); $dlg.StartPosition = 'CenterParent'; $dlg.Font = $form.Font

    $lblSearch = New-Lbl (T 'cfg.search') 12 16 60 $true
    $txtSearch = New-Object Windows.Forms.TextBox
    $txtSearch.Location = New-Object Drawing.Point(76, 12); $txtSearch.Size = New-Object Drawing.Size(240, 26)
    $g = New-Object Windows.Forms.DataGridView
    $g.Location = New-Object Drawing.Point(12, 46); $g.Size = New-Object Drawing.Size(860, 330); $g.Anchor = 'Top,Left,Right,Bottom'
    $g.AllowUserToAddRows = $false; $g.AllowUserToDeleteRows = $false; $g.RowHeadersVisible = $false
    $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false; $g.AutoSizeColumnsMode = 'Fill'
    [void]$g.Columns.Add('Key', (T 'cfg.colKey')); [void]$g.Columns.Add('Value', (T 'cfg.colValue'))
    $g.Columns[0].ReadOnly = $true; $g.Columns[0].FillWeight = 50; $g.Columns[1].FillWeight = 50
    $txtD = New-Object Windows.Forms.TextBox
    $txtD.Multiline = $true; $txtD.ReadOnly = $true; $txtD.ScrollBars = 'Vertical'; $txtD.Font = New-Object Drawing.Font('Consolas', 9)
    $txtD.Location = New-Object Drawing.Point(12, 386); $txtD.Size = New-Object Drawing.Size(860, 130); $txtD.Anchor = 'Left,Right,Bottom'
    $txtSearch.Size = New-Object Drawing.Size(400, 26)
    $btnSaveCfg = New-Btn (T 'cfg.save') 642 526 110 30; $btnSaveCfg.Anchor = 'Right,Bottom'
    $btnCloseCfg = New-Btn (T 'btn.close') 762 526 110 30; $btnCloseCfg.Anchor = 'Right,Bottom'
    $btnCloseCfg.Add_Click({ $dlg.Close() })
    $dlg.Controls.AddRange(@($lblSearch, $txtSearch, $g, $txtD, $btnSaveCfg, $btnCloseCfg))

    $entries = @()
    $loading = $false
    $fill = {
        $loading = $true
        $entries = @(Get-AcConfEntries $path)
        $g.Rows.Clear()
        $f = $txtSearch.Text.Trim()
        foreach ($e in $entries) {
            if ($f -and ($e.Key -notlike "*$f*") -and ($e.Description -notlike "*$f*")) { continue }
            $i = $g.Rows.Add($e.Key, $e.Value)
            $g.Rows[$i].Tag = $e
        }
        $loading = $false
        $txtD.Text = ''
    }
    & $fill
    $txtSearch.Add_TextChanged({ & $fill })
    $g.Add_SelectionChanged({
        if ($g.SelectedRows.Count -gt 0 -and $g.SelectedRows[0].Tag) {
            $e = $g.SelectedRows[0].Tag
            $txtD.Text = "$($e.Key)`r`n`r`n$($e.Description)"
        }
    })
    $btnSaveCfg.Add_Click({
        $g.EndEdit()
        $changed = 0
        foreach ($row in $g.Rows) {
            $e = $row.Tag; if (-not $e) { continue }
            $new = [string]$row.Cells[1].Value
            if ($new -ne $e.Value) { Set-AcConfValue $path $e.Key $new; $changed++ }
        }
        & $fill
        $msg = T 'cfg.saved' @($changed)
        if ($changed -gt 0) { $msg += "`r`n`r`n" + (T 'cfg.restartHint') }
        [Windows.Forms.MessageBox]::Show($msg, (T 'tab.settings'), 'OK', 'Information') | Out-Null
    })
    [void]$dlg.ShowDialog($form)
    Load-ConfFiles
}


# ---------------------------------------------------------------------
#  Lua-Skripte (Eluna)
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
#  Lua-Skripte verwalten
# ---------------------------------------------------------------------
function Show-LuaDialog {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'lua.title'; $dlg.Size = New-Object Drawing.Size(1180, 740)
    $dlg.MinimumSize = New-Object Drawing.Size(820, 560)
    $dlg.StartPosition = 'CenterParent'; $dlg.Font = $form.Font
    # ---------------------------------------------------------------------
    #  Tab "Lua-Skripte"
    # ---------------------------------------------------------------------

    # Aufbau von unten nach oben angedockt - so rutscht nichts aus dem Fenster
    $lblState = New-Object Windows.Forms.Label
    $lblState.Dock = 'Top'; $lblState.Height = 46; $lblState.Padding = New-Object Windows.Forms.Padding(4, 6, 4, 0)
    $lblState.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)

    $tv = New-Object Windows.Forms.TreeView
    $tv.CheckBoxes = $true; $tv.HideSelection = $false; $tv.ShowLines = $true
    $tv.Dock = 'Fill'; $tv.ItemHeight = 22

    # Knopfleiste: ordnet sich selbst an und bricht bei Bedarf um
    $pnlBtns = New-Object Windows.Forms.FlowLayoutPanel
    $pnlBtns.Dock = 'Bottom'; $pnlBtns.WrapContents = $true
    # waechst mit, sobald die Knoepfe in eine zweite Zeile umbrechen
    $pnlBtns.AutoSize = $true; $pnlBtns.AutoSizeMode = 'GrowAndShrink'
    $pnlBtns.MinimumSize = New-Object Drawing.Size(0, 44)
    $pnlBtns.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6)

    $btnApply2 = New-Btn (T 'lua.applyState') 0 0 150 30; $btnApply2.Tag = 'primary'
    $btnReload = New-Btn (T 'lua.reload') 0 0 140 30
    $btnUpdLua = New-Btn (T 'lua.updateRepos') 0 0 150 30
    $btnLuaSql = New-Btn (T 'lua.sqlButton') 0 0 165 30
    $btnOpen2  = New-Btn (T 'btn.openFolder') 0 0 125 30
    $btnAddon  = New-Btn (T 'lua.disableAddon') 0 0 205 30
    $btnEluna  = New-Btn (T 'lua.installEluna') 0 0 140 30
    foreach ($b in @($btnApply2, $btnReload, $btnUpdLua, $btnLuaSql, $btnAddon, $btnOpen2, $btnEluna)) {
        $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 6)
        $pnlBtns.Controls.Add($b)
    }

    $drop = New-Object Windows.Forms.Panel
    $drop.Dock = 'Bottom'; $drop.Height = 52; $drop.BorderStyle = 'FixedSingle'; $drop.AllowDrop = $true
    $dropLbl2 = New-Object Windows.Forms.Label
    $dropLbl2.Text = T 'lua.dropHere'; $dropLbl2.Dock = 'Fill'; $dropLbl2.TextAlign = 'MiddleCenter'
    $dropLbl2.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold); $dropLbl2.AllowDrop = $true
    $drop.Controls.Add($dropLbl2)

    # Zeile fuer die Git-Adresse
    $pnlUrl = New-Object Windows.Forms.Panel
    $pnlUrl.Dock = 'Bottom'; $pnlUrl.Height = 40
    $lblUrl = New-Lbl (T 'lua.gitUrl') 8 10 110 $true
    $txtUrl = New-Object Windows.Forms.TextBox
    $txtUrl.Location = New-Object Drawing.Point(122, 8); $txtUrl.Anchor = 'Top,Left,Right'
    $btnGitLua = New-Btn (T 'lua.gitAdd') 0 6 200 28; $btnGitLua.Anchor = 'Top,Right'
    $pnlUrl.Controls.AddRange(@($lblUrl, $txtUrl, $btnGitLua))
    $layUrl = {
        $w = $pnlUrl.ClientSize.Width
        $btnGitLua.Location = New-Object Drawing.Point(($w - 208), 6)
        $txtUrl.Size = New-Object Drawing.Size(([Math]::Max(80, $w - 122 - 216)), 26)
    }
    $pnlUrl.Add_Resize($layUrl)

    # Zeile fuer die Lua-Version
    $pnlVer = New-Object Windows.Forms.Panel
    $pnlVer.Dock = 'Bottom'; $pnlVer.Height = 34
    $lblVer = New-Lbl (T 'lua.version') 8 8 110 $true
    $cmbVer = New-Object Windows.Forms.ComboBox
    $cmbVer.DropDownStyle = 'DropDownList'; $cmbVer.Location = New-Object Drawing.Point(122, 5); $cmbVer.Size = New-Object Drawing.Size(140, 26)
    foreach ($v in @('lua52', 'lua53', 'lua54', 'luajit')) { [void]$cmbVer.Items.Add($v) }
    $cmbVer.SelectedItem = $(if ($script:S.LuaVersion) { [string]$script:S.LuaVersion } else { 'lua52' })
    $lblVerHint = New-Lbl (T 'lua.versionHint') 272 9 400 $false
    $lblVerHint.ForeColor = Get-AcColor 'TextDim'; $lblVerHint.Anchor = 'Top,Left,Right'
    $pnlVer.Controls.AddRange(@($lblVer, $cmbVer, $lblVerHint))
    $layVer = { $lblVerHint.Size = New-Object Drawing.Size(([Math]::Max(120, $pnlVer.ClientSize.Width - 280)), 20) }
    $pnlVer.Add_Resize($layVer)

    # Reihenfolge beachten: Fuellelement zuerst, dann die angedockten Zeilen
    $dlg.Controls.Add($tv)
    $dlg.Controls.Add($lblState)
    $dlg.Controls.Add($pnlVer)
    $dlg.Controls.Add($pnlUrl)
    $dlg.Controls.Add($drop)
    $dlg.Controls.Add($pnlBtns)

    $script:RefreshLua = {
        $tv.Nodes.Clear()
        $elunaName = Get-AcElunaModuleName $script:P
        $built = Test-AcElunaInstalled $script:P $script:S
        $dir = Get-AcLuaScriptPath $script:P
        # Keine Vorab-Pruefung der Lua-Bibliothek mehr: mod-ale holt seine Lua-Quellen
        # beim CMake-Lauf selbst in den Build-Ordner, im Quellordner liegt nichts.
        if (-not $elunaName) {
            $lblState.ForeColor = Get-AcColor 'Bad'
            $lblState.Text = T 'lua.noEluna'
            $btnEluna.Enabled = $true
        } elseif (-not $built) {
            $lblState.ForeColor = Get-AcColor 'Warn'
            $lblState.Text = T 'lua.elunaNotBuilt' @($elunaName)
            $btnEluna.Enabled = $false
        } else {
            $lblState.ForeColor = Get-AcColor 'Good'
            $lblState.Text = (T 'lua.elunaReady' @($elunaName)) + "   -   $dir"
            $btnEluna.Enabled = $false
        }
        if ($lblState.Text -notmatch [regex]::Escape($dir)) { $lblState.Text += "   ($dir)" }
        # Client-Addon-Dateien im Serverordner melden
        $addons = @(Get-AcClientAddonScripts $script:P | Where-Object { $_.Enabled })
        $btnAddon.Visible = ($addons.Count -gt 0)
        if ($addons.Count -gt 0) {
            $lblState.ForeColor = Get-AcColor 'Warn'
            $lblState.Text += "   -   " + (T 'lua.addonFound' @($addons.Count))
        }
        $script:LuaTreeLoading = $true
        $groups = @{}
        foreach ($s in (Get-AcLuaScripts $script:P)) {
            # erste Pfadebene = Paket; lose Dateien landen unter "."
            $parts = @($s.Rel -split '\\')
            $pkg = $(if ($parts.Count -gt 1) { $parts[0] } else { T 'lua.loose' })
            if (-not $groups.ContainsKey($pkg)) { $groups[$pkg] = New-Object Collections.Generic.List[object] }
            $groups[$pkg].Add($s)
        }
        foreach ($pkg in ($groups.Keys | Sort-Object)) {
            $items = $groups[$pkg]
            $active = @($items | Where-Object { $_.Enabled }).Count
            $node = New-Object Windows.Forms.TreeNode((T 'lua.pkgNode' @($pkg, $items.Count, $active)))
            $node.Tag = 'group'
            $node.NodeFont = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
            foreach ($s in ($items | Sort-Object Rel)) {
                $sub = Split-Path $s.Rel -Parent
                $sub = $(if ($sub -and ($sub -ne $pkg)) { ($sub -replace ('^' + [regex]::Escape($pkg) + '\\?'), '') } else { '' })
                $label = $s.Name
                if ($sub) { $label = "$sub\$($s.Name)" }
                $label += "   ($($s.SizeKb) KB)"
                if (-not $s.Enabled) { $label += "   [" + (T 'lua.inactive') + "]" }
                $child = New-Object Windows.Forms.TreeNode($label)
                $child.Tag = $s
                $child.Checked = $s.Enabled
                if (-not $s.Enabled) { $child.ForeColor = Get-AcColor 'TextDim' }
                [void]$node.Nodes.Add($child)
            }
            $node.Checked = ($active -eq $items.Count)
            [void]$tv.Nodes.Add($node)
        }
        $tv.ExpandAll()
        if ($tv.Nodes.Count -gt 0) { $tv.Nodes[0].EnsureVisible() }
        $script:LuaTreeLoading = $false
    }
    & $script:RefreshLua

    $dragEnter2 = { param($sender, $e) if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy } }
    $dragDrop2 = {
        param($sender, $e)
        if (-not $e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { return }
        $script:OpLogTarget = $modLog
        foreach ($f in $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
            try { Install-AcLuaScript $script:P $f | Out-Null }
            catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, (T 'word.error'), 'OK', 'Warning') | Out-Null }
        }
        & $script:RefreshLua
    }
    foreach ($c in @($drop, $dropLbl2)) { $c.Add_DragEnter($dragEnter2); $c.Add_DragDrop($dragDrop2) }

    $cmbVer.Add_SelectedIndexChanged({
        $v = [string]$cmbVer.SelectedItem
        if ($v -eq [string]$script:S.LuaVersion) { return }
        $script:S.LuaVersion = $v
        Save-AcSettings $script:P.Root $script:S
        Mark-Rebuild
        [Windows.Forms.MessageBox]::Show((T 'lua.versionChanged' @($v)), (T 'lua.title'), 'OK', 'Information') | Out-Null
    })

    $tv.Add_AfterCheck({
        param($sender, $e)
        if ($script:LuaTreeLoading) { return }
        # Haken am Paket setzt alle enthaltenen Dateien
        if ($e.Node.Tag -eq 'group') {
            $script:LuaTreeLoading = $true
            foreach ($c in $e.Node.Nodes) { $c.Checked = $e.Node.Checked }
            $script:LuaTreeLoading = $false
        }
    })

    $btnApply2.Add_Click({
        $n = 0
        foreach ($node in $tv.Nodes) {
            foreach ($child in $node.Nodes) {
                $s = $child.Tag
                if (-not $s) { continue }
                if ($child.Checked -ne $s.Enabled) { Set-AcLuaScriptEnabled $s.Full $child.Checked; $n++ }
            }
        }
        & $script:RefreshLua
        if ($n -gt 0) { [Windows.Forms.MessageBox]::Show((T 'lua.stateChanged' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null }
    })
    $btnReload.Add_Click({
        try { Send-WorldCommand 'reload eluna'; [Windows.Forms.MessageBox]::Show((T 'lua.reloaded'), (T 'lua.title'), 'OK', 'Information') | Out-Null }
        catch { [Windows.Forms.MessageBox]::Show((T 'srv.notRunning'), (T 'word.warning'), 'OK', 'Warning') | Out-Null }
    })
    function Import-LuaRepoSql {
        param($Plan)
        $list = ($Plan | ForEach-Object { "   $($_.Rel)  ->  $($_.Name)" }) -join "`r`n"
        $ask = (T 'lua.sqlAsk' @($Plan.Count, "`r`n")) + "`r`n`r`n" + $list
        if ([Windows.Forms.MessageBox]::Show($ask, (T 'lua.title'), 'YesNo', 'Question') -ne 'Yes') { return }
        if (-not (Confirm-DbStart 'db.reasonGeneric')) { return }
        try {
            Ensure-CharDb
            $dlg.Cursor = 'WaitCursor'; Invoke-AcDoEvents
            $n = Import-AcLuaSqlPlan $script:P $Plan
            [Windows.Forms.MessageBox]::Show((T 'sql.imported' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
        finally { $dlg.Cursor = 'Default' }
    }

    $btnGitLua.Add_Click({
        $url = $txtUrl.Text.Trim()
        if (-not $url) { return }
        try {
            $script:OpLogTarget = $modLog
            $dlg.Cursor = 'WaitCursor'; Invoke-AcDoEvents
            $res = Install-AcLuaScriptFromGit $script:P $url
            $txtUrl.Clear()
            & $script:RefreshLua
            $msg = T 'lua.repoAddedMsg' @($res.Name, $res.LuaCount, "`r`n")
            [Windows.Forms.MessageBox]::Show($msg, (T 'lua.title'), 'OK', 'Information') | Out-Null
            # Mitgelieferte SQL-Dateien wie bei Modulen anbieten
            $plan = @(Get-AcLuaSqlPlan $script:P $res.Path)
            if ($plan.Count -gt 0) { Import-LuaRepoSql $plan }
        } catch { Show-AcError $_ }
        finally { $dlg.Cursor = 'Default' }
    })
    $btnAddon.Add_Click({
        $addons = @(Get-AcClientAddonScripts $script:P | Where-Object { $_.Enabled })
        if ($addons.Count -eq 0) { return }
        $list = ($addons | ForEach-Object { "   $($_.Rel)" }) -join "`r`n"
        $ask = (T 'lua.addonAsk' @($addons.Count, "`r`n")) + "`r`n`r`n" + $list
        if ([Windows.Forms.MessageBox]::Show($ask, (T 'lua.title'), 'YesNo', 'Question') -ne 'Yes') { return }
        try {
            $script:OpLogTarget = $modLog
            $n = Disable-AcClientAddonScripts $script:P
            & $script:RefreshLua
            [Windows.Forms.MessageBox]::Show((T 'lua.addonDone' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
    })

    $btnLuaSql.Add_Click({
        $plan = @(Get-AcAllLuaSqlPlan $script:P)
        if ($plan.Count -eq 0) { [Windows.Forms.MessageBox]::Show((T 'lua.noSql'), (T 'lua.title'), 'OK', 'Information') | Out-Null; return }
        Import-LuaRepoSql $plan
    })
    $btnUpdLua.Add_Click({
        try {
            $script:OpLogTarget = $modLog
            $dlg.Cursor = 'WaitCursor'; Invoke-AcDoEvents
            $n = Update-AcLuaScriptRepos $script:P
            & $script:RefreshLua
            [Windows.Forms.MessageBox]::Show((T 'lua.reposUpdated' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
        finally { $dlg.Cursor = 'Default' }
    })
    $btnOpen2.Add_Click({
        $dir = Get-AcLuaScriptPath $script:P
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Start-Process explorer.exe $dir
    })
    $btnEluna.Add_Click({
        # Zwei Engines zur Wahl - die Skripte sind NICHT untereinander austauschbar
        $choice = [Windows.Forms.MessageBox]::Show((T 'lua.engineChoice' @("`r`n")), (T 'lua.installEluna'), 'YesNoCancel', 'Question')
        if ($choice -eq 'Cancel') { return }
        $repo = $(if ($choice -eq 'Yes') { $script:AcLuaEngines[0].Url } else { $script:AcLuaEngines[1].Url })
        try {
            $script:OpLogTarget = $modLog
            $name = Install-AcModuleFromGit $script:P $repo
            Write-AcLog (T 'mod.cloned' @($name)) 'STEP'
            Sync-AcModuleSql (Join-Path $script:P.Modules $name) $name | Out-Null
            Mark-Rebuild
            & $script:RefreshLua
            [Windows.Forms.MessageBox]::Show((T 'lua.elunaAdded' @($name)), (T 'lua.title'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
    })



    $btnClose3 = New-Btn (T 'btn.close') 0 0 95 30
    $btnClose3.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 6)
    $btnClose3.Add_Click({ $dlg.Close() })
    $pnlBtns.Controls.Add($btnClose3)
    Update-AcTheme $dlg
    $dlg.Add_Shown({ & $layUrl; & $layVer; & $script:RefreshLua })
    [void]$dlg.ShowDialog($form)
    Refresh-Modules
}


$btnLua.Add_Click({ Show-LuaDialog })


# ---------------------------------------------------------------------
#  Lua-Paket statt C++-Modul erkannt
# ---------------------------------------------------------------------
function Install-LuaEngineIfMissing {
    <#
      Prueft, ob eine Lua-Engine installiert ist, und bietet sie sonst an.
      Geholt wird immer der aktuelle Stand des Standard-Branches von GitHub.
    #>
    if (Get-AcElunaModuleName $script:P) { return $true }
    $choice = [Windows.Forms.MessageBox]::Show((T 'lua.engineMissing' @("`r`n")), (T 'lua.installEluna'), 'YesNoCancel', 'Question')
    if ($choice -eq 'Cancel') { return $false }
    $repo = $(if ($choice -eq 'Yes') { $script:AcLuaEngines[0].Url } else { $script:AcLuaEngines[1].Url })
    try {
        $script:OpLogTarget = $modLog
        $name = Install-AcModuleFromGit $script:P $repo
        Update-AcSubmodules (Join-Path $script:P.Modules $name) | Out-Null
        Sync-AcModuleSql (Join-Path $script:P.Modules $name) $name | Out-Null
        Write-AcLog (T 'mod.cloned' @($name)) 'STEP'
        Mark-Rebuild
        return $true
    } catch {
        Show-AcError $_
        return $false
    }
}

function Resolve-LuaPackageInstall {
    <#
      Wird nach dem Hinzufuegen eines "Moduls" aufgerufen: Enthaelt es nur
      Lua-Dateien, ist es ein Skriptpaket und gehoert in den Skriptordner.
      Rueckgabe: $true, wenn es als Skriptpaket behandelt wurde.
    #>
    param([string]$Name)
    $path = Join-Path $script:P.Modules $Name
    if (-not (Test-AcIsLuaScriptRepo $path)) { return $false }
    if ([Windows.Forms.MessageBox]::Show((T 'lua.detected' @($Name, "`r`n")), (T 'lua.title'), 'YesNo', 'Question') -ne 'Yes') { return $false }
    try {
        $script:OpLogTarget = $modLog
        $dst = Move-AcModuleToLuaScripts $script:P $Name
        Install-LuaEngineIfMissing | Out-Null
        Refresh-Modules
        # mitgelieferte SQL gleich anbieten
        $plan = @(Get-AcLuaSqlPlan $script:P $dst)
        if ($plan.Count -gt 0) {
            $list = ($plan | ForEach-Object { "   $($_.Rel)  ->  $($_.Name)" }) -join "`r`n"
            $ask = (T 'lua.sqlAsk' @($plan.Count, "`r`n")) + "`r`n`r`n" + $list
            if ([Windows.Forms.MessageBox]::Show($ask, (T 'lua.title'), 'YesNo', 'Question') -eq 'Yes') {
                if (Confirm-DbStart 'db.reasonGeneric') {
                    Ensure-CharDb
                    $n = Import-AcLuaSqlPlan $script:P $plan
                    [Windows.Forms.MessageBox]::Show((T 'sql.imported' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null
                }
            }
        }
        [Windows.Forms.MessageBox]::Show((T 'lua.movedMsg' @($Name, "`r`n")), (T 'lua.title'), 'OK', 'Information') | Out-Null
        return $true
    } catch {
        Show-AcError $_
        return $false
    }
}

$btnModExport.Add_Click({
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json'
    $dlg.FileName = "modules-$(Get-Date -Format 'yyyy-MM-dd').json"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $script:OpLogTarget = $modLog
        $r = Export-AcModuleList $script:P $script:S $dlg.FileName
        [Windows.Forms.MessageBox]::Show((T 'mod.exportDone' @($r.Modules, $r.Lua, $dlg.FileName, "`r`n")), (T 'tab.modules'), 'OK', 'Information') | Out-Null
    } catch { Show-AcError $_ }
})

$btnModImport.Add_Click({
    if ($script:Busy) { return }
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON (*.json)|*.json'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $list = Read-AcModuleList $dlg.FileName
        if ($list.Modules.Count -eq 0 -and $list.LuaScripts.Count -eq 0) { [Windows.Forms.MessageBox]::Show((T 'mod.importEmpty'), (T 'tab.modules'), 'OK', 'Warning') | Out-Null; return }
        $names = ($list.Modules | ForEach-Object { "   $($_.Name)" }) -join "`r`n"
        if ($list.LuaScripts.Count -gt 0) {
            $names += "`r`n" + (T 'mod.importLuaHead' @($list.LuaScripts.Count)) + "`r`n"
            $names += ($list.LuaScripts | ForEach-Object { "   $($_.Name)" }) -join "`r`n"
        }
        $ask = T 'mod.importAsk' @($list.Modules.Count, "`r`n")
        # Variante der Liste mit der eigenen vergleichen
        if ($list.Variant -and ($list.Variant -ne [string]$script:S.Variant)) {
            $ask += "`r`n`r`n" + (T 'mod.importVariant' @($list.Variant, [string]$script:S.Variant))
        }
        $ask += "`r`n`r`n" + $names
        if ([Windows.Forms.MessageBox]::Show($ask, (T 'mod.import'), 'YesNo', 'Question') -ne 'Yes') { return }
        # Fester Stand aus der Liste oder aktueller Branch?
        $withCommits = @($list.Modules + $list.LuaScripts | Where-Object { $_.Commit })
        $useCommit = $false
        if ($withCommits.Count -gt 0) {
            $r = [Windows.Forms.MessageBox]::Show((T 'mod.importCommitAsk' @($withCommits.Count, "`r`n")), (T 'mod.import'), 'YesNoCancel', 'Question')
            if ($r -eq 'Cancel') { return }
            $useCommit = ($r -eq 'Yes')
        }
        $script:Busy = $true; Set-TabsLocked $true; Update-Buttons
        $script:OpLogTarget = $modLog
        $res = Import-AcModuleList $script:P $list.Modules -UseCommit:$useCommit
        $luaRes = $null
        if ($list.LuaScripts.Count -gt 0) { $luaRes = Import-AcLuaScriptList $script:P $list.LuaScripts -UseCommit:$useCommit }
        $script:Busy = $false; Set-TabsLocked $false; Reset-Title; Update-Buttons
        if ($res.Installed.Count -gt 0) { Mark-Rebuild }
        Refresh-Modules

        $msg = T 'mod.importDone' @($res.Installed.Count, $res.Skipped.Count, $res.Failed.Count, "`r`n")
        $msg += "`r`n" + $(if ($useCommit) { T 'mod.importUsedCommit' } else { T 'mod.importUsedLatest' })
        if ($luaRes) { $msg += "`r`n" + (T 'mod.importLuaDone' @($luaRes.Installed.Count, $luaRes.Skipped.Count, $luaRes.Failed.Count)) }
        if ($res.Failed.Count -gt 0) { $msg += "`r`n`r`n" + (T 'mod.importFailed' @(($res.Failed -join ', '))) }
        # SQL, die nicht automatisch eingebunden werden kann, gleich hier melden -
        # nicht erst beim Kompilieren im Protokoll
        if ($res.Manual.Count -gt 0) {
            $lines = ($res.Manual | ForEach-Object { "   $($_.Module): " + (T 'mod.importManualLine' @($_.Optional, $_.Unknown)) }) -join "`r`n"
            $msg += "`r`n`r`n" + (T 'mod.importManual' @("`r`n")) + "`r`n" + $lines
        }
        [Windows.Forms.MessageBox]::Show($msg, (T 'tab.modules'), 'OK', 'Information') | Out-Null

        # SQL der neu geholten Lua-Skripte anbieten
        if ($luaRes -and $luaRes.SqlPlan.Count -gt 0) {
            $list2 = ($luaRes.SqlPlan | ForEach-Object { "   $($_.Rel)  ->  $($_.Name)" }) -join "`r`n"
            $ask2 = (T 'lua.sqlAsk' @($luaRes.SqlPlan.Count, "`r`n")) + "`r`n`r`n" + $list2
            if ([Windows.Forms.MessageBox]::Show($ask2, (T 'lua.title'), 'YesNo', 'Question') -eq 'Yes') {
                if (Confirm-DbStart 'db.reasonGeneric') {
                    try {
                        Ensure-CharDb
                        $n = Import-AcLuaSqlPlan $script:P $luaRes.SqlPlan
                        [Windows.Forms.MessageBox]::Show((T 'sql.imported' @($n)), (T 'lua.title'), 'OK', 'Information') | Out-Null
                    } catch { Show-AcError $_ }
                }
            }
        }
    } catch {
        $script:Busy = $false; Set-TabsLocked $false; Update-Buttons
        Show-AcError $_
    }
})

$btnModCfg.Add_Click({
    $sel = Get-SelectedModuleName
    if (-not $sel) {
        if (Test-SelectedIsLua) { Show-LuaDialog; return }
        [Windows.Forms.MessageBox]::Show((T 'mod.selectFirst')) | Out-Null; return
    }
    Show-ModuleConfigDialog $sel
})

# ---------------------------------------------------------------------
#  Charakter-Editor
# ---------------------------------------------------------------------
$script:CurrentChar = $null
$script:CharList = @()

function Test-WorldStopped {
    if ($script:World -and -not $script:World.Process.HasExited) { return $false }
    return (-not (Test-AcWorldRunning $script:P))
}

$script:DbBusy = $false
$script:DbAsking = $false     # verhindert mehrere Rueckfragen gleichzeitig
$script:DbApproved = $false   # Zustimmung zum Start, gilt bis MySQL wieder gestoppt wird

function Set-CharBusy {
    param([bool]$On, [string]$Text = '')
    $script:DbBusy = $On
    $tabChar.Cursor = $(if ($On) { 'WaitCursor' } else { 'Default' })
    foreach ($c in @($btnCharReload, $chkShowBots, $txtCharSearch, $lvChars, $gridChar, $btnCharSave)) { $c.Enabled = -not $On }
    foreach ($s in $script:SlotButtons) { $s.Button.Enabled = -not $On }
    if ($Text) { $lblCharWarn.ForeColor = 'DarkSlateGray'; $lblCharWarn.Text = $Text }
    elseif (-not $On) { $lblCharWarn.ForeColor = 'DarkRed'; $lblCharWarn.Text = $(if (Test-WorldStopped) { '' } else { T 'chr.serverRunning' }) }
    if (-not $On) { Update-Buttons }
    Invoke-AcDoEvents
}

function Confirm-DbStart {
    <#
      Laeuft MySQL nicht, wird vorher gefragt - Tabs wie Charaktere oder GM-Befehle
      brauchen die Datenbank, sollen sie aber nicht unbemerkt im Hintergrund starten.
      Rueckgabe: $true, wenn die Datenbank laeuft bzw. gestartet werden darf.
    #>
    param([string]$ReasonKey = 'db.reasonGeneric')
    if (Test-AcMySqlAlive $script:P) { return $true }
    # Zustimmung gilt bis die Datenbank wieder gestoppt wird - sonst wuerde jede
    # Folgefunktion (Liste laden, Details anzeigen ...) erneut nachfragen.
    if ($script:DbApproved) { return $true }
    if ($script:DbAsking) { return $false }   # nur eine Rueckfrage gleichzeitig
    $script:DbAsking = $true
    try {
        $msg = (T $ReasonKey) + "`r`n`r`n" + (T 'db.askStart')
        $r = [Windows.Forms.MessageBox]::Show($msg, (T 'db.askTitle'), 'YesNo', 'Question')
        if ($r -eq 'Yes') { $script:DbApproved = $true; return $true }
        return $false
    } finally { $script:DbAsking = $false }
}

function Ensure-CharDb {
    if (-not (Test-AcMySqlAlive $script:P)) {
        $wasBusy = $script:DbBusy
        Set-Status $lblMy 'svc.mysql' 'state.starting'
        Set-CharBusy $true (T 'chr.dbNotRunning')
        try {
            $st = Start-AcMySql $script:P
            if ($st) { $script:MySql = $st }
            Set-Status $lblMy 'svc.mysql' 'state.running'
        } finally {
            # Sperre nur zuruecknehmen, wenn sie hier gesetzt wurde - sonst bleibt der
            # Tab eingefroren, weil die Folgefunktionen bei "beschaeftigt" sofort abbrechen
            if (-not $wasBusy) { Set-CharBusy $false }
        }
    }
}

function Refresh-CharList {
    if ($script:DbBusy) { return }
    if (-not (Confirm-DbStart 'db.reasonChars')) { $lblCharWarn.ForeColor = 'DarkRed'; $lblCharWarn.Text = T 'db.notStarted'; return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.loading')
        $script:OpLogTarget = $console
        try { Clear-AcStaleOnlineFlags $script:P | Out-Null } catch {}
        $script:CharList = @(Get-AcCharacters $script:P -IncludeBots:$chkShowBots.Checked)
    } catch {
        Set-CharBusy $false
        Show-AcError $_
        return
    }
    $filter = $txtCharSearch.Text.Trim()
    $lvChars.Items.Clear()
    foreach ($c in $script:CharList) {
        if ($filter -and ([string]$c.name) -notlike "*$filter*" -and ([string]$c.username) -notlike "*$filter*" -and ([string]$c.guid) -ne $filter) { continue }
        $it = New-Object Windows.Forms.ListViewItem([string]$c.guid)
        [void]$it.SubItems.Add([string]$c.name)
        [void]$it.SubItems.Add([string]$c.level)
        [void]$it.SubItems.Add((Get-AcClassName ([int]$c.class)))
        [void]$it.SubItems.Add((Get-AcRaceName ([int]$c.race)))
        [void]$it.SubItems.Add([string]$c.username)
        [void]$it.SubItems.Add($(if ([int]$c.online -eq 1) { T 'chr.online' } else { T 'chr.offline' }))
        if ([int]$c.online -eq 1) { $it.ForeColor = 'DarkRed' }
        $it.Tag = $c
        [void]$lvChars.Items.Add($it)
    }
    Set-CharBusy $false
}

function Show-CharacterDetails {
    param($Char)
    if ($script:DbBusy) { return }
    $script:CurrentChar = $Char
    $gridChar.Rows.Clear()
    foreach ($s in $script:SlotButtons) { $s.Button.Text = (T $s.Key) + ": " + (T 'chr.empty'); $s.Button.ForeColor = 'DimGray'; $s.Button.Tag = @{ Slot = $s.Slot; Inv = $s.Inv; Item = $null }; $script:SlotTip.SetToolTip($s.Button, '') }
    $lblXpWarn.Text = ''
    if (-not $Char) { $lblCharHead.Text = ''; return }
    if (-not (Confirm-DbStart 'db.reasonChars')) { return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.loading')
        $full = Get-AcCharacter $script:P ([int]$Char.guid)
        if (-not $full) { return }
        $script:CurrentChar = $full
        $lblCharHead.Text = "$($full.name)   -   " + (T 'chr.level') + " $($full.level) " + (Get-AcRaceName ([int]$full.race)) + " " + (Get-AcClassName ([int]$full.class)) + "   (GUID $($full.guid))"
        # Warnung, wenn dieser Charakter keine Erfahrung sammeln kann
        $xpWarn = @()
        if (Test-AcXpBlocked $full) { $xpWarn += (T 'chr.xpFlagSet') }
        $maxLvl = Get-AcMaxPlayerLevel $script:P
        if ([int]$full.level -ge $maxLvl) { $xpWarn += (T 'chr.xpMaxLevel' @($maxLvl)) }
        $lblXpWarn.Text = ($xpWarn -join '  ')
        # Rollenvorschlag anhand der Klasse (wird im Auto-Equip-Dialog vorausgewaehlt)
        $script:SuggestedRole = $script:AcClassDefaultRole[[int]$full.class]
        foreach ($f in (Get-AcCharacterFields)) {
            $i = $gridChar.Rows.Add((T $f.Key), [string]$full.($f.Col))
            $gridChar.Rows[$i].Tag = @{ Col = $f.Col; Original = [string]$full.($f.Col) }
        }
        foreach ($eq in (Get-AcCharacterEquipment $script:P ([int]$full.guid))) {
            $btn = ($script:SlotButtons | Where-Object { $_.Slot -eq $eq.Slot } | Select-Object -First 1).Button
            if (-not $btn) { continue }
            $btn.Tag = @{ Slot = $eq.Slot; Inv = $eq.Inv; Item = $eq.Item }
            if ($eq.Item) {
                $q = 1; [void][int]::TryParse([string]$eq.Item.Quality, [ref]$q)
                $btn.Text = (T $eq.Key) + ": " + $eq.Item.name
                $btn.ForeColor = Get-AcQualityColor $q
                try {
                    $tip = "$($eq.Item.name)  (ID $($eq.Item.itemEntry), " + (T 'chr.itemColIlvl') + " $($eq.Item.ItemLevel))`r`n" + (Get-AcItemStatText $eq.Item 20)
                    $script:SlotTip.SetToolTip($btn, $tip)
                } catch {}

            }
        }
    } catch { Show-AcError $_ }
    finally { Set-CharBusy $false }
}

function Show-ItemPickerDialog {
    param($SlotInfo)
    if (-not $script:CurrentChar) { return }
    if (-not (Test-WorldStopped)) { [Windows.Forms.MessageBox]::Show((T 'chr.itemNeedStop'), (T 'word.warning'), 'OK', 'Warning') | Out-Null; return }

    $slotKey = ($script:AcEquipSlots | Where-Object { $_.Slot -eq $SlotInfo.Slot }).Key
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'chr.itemDlgTitle' @((T $slotKey))
    $dlg.Size = New-Object Drawing.Size(1120, 680); $dlg.StartPosition = 'CenterParent'; $dlg.Font = $form.Font
    $lblS = New-Lbl (T 'chr.itemSearch') 12 16 110 $true
    $txtS = New-Object Windows.Forms.TextBox
    $txtS.Location = New-Object Drawing.Point(126, 12); $txtS.Size = New-Object Drawing.Size(260, 26)
    $chkFit = New-Object Windows.Forms.CheckBox
    $chkFit.Text = T 'chr.itemOnlyUsable'; $chkFit.Location = New-Object Drawing.Point(400, 14); $chkFit.Size = New-Object Drawing.Size(420, 24); $chkFit.Checked = $true
    $lblWarnFit = New-Lbl '' 126 40 700 $false; $lblWarnFit.ForeColor = 'DarkRed'
    $lvI = New-Object Windows.Forms.ListView
    $lvI.View = 'Details'; $lvI.FullRowSelect = $true; $lvI.GridLines = $true
    $lvI.Location = New-Object Drawing.Point(12, 64); $lvI.Size = New-Object Drawing.Size(1080, 430); $lvI.Anchor = 'Top,Left,Right,Bottom'
    [void]$lvI.Columns.Add((T 'chr.itemColEntry'), 70); [void]$lvI.Columns.Add((T 'chr.itemColName'), 280)
    [void]$lvI.Columns.Add((T 'chr.itemColIlvl'), 80); [void]$lvI.Columns.Add((T 'chr.itemColReq'), 80)
    [void]$lvI.Columns.Add((T 'chr.itemColStats'), 480)
    $txtIStats = New-Object Windows.Forms.TextBox
    $txtIStats.Multiline = $true; $txtIStats.ReadOnly = $true; $txtIStats.ScrollBars = 'Vertical'
    $txtIStats.Location = New-Object Drawing.Point(12, 500); $txtIStats.Size = New-Object Drawing.Size(1080, 70)
    $txtIStats.Anchor = 'Left,Right,Bottom'; $txtIStats.Font = New-Object Drawing.Font('Consolas', 9)
    $lvI.Add_SelectedIndexChanged({
        if ($lvI.SelectedItems.Count -eq 0) { $txtIStats.Text = ''; return }
        $i = $lvI.SelectedItems[0].Tag
        $txtIStats.Text = "$($i.name)  (ID $($i.entry), " + (T 'chr.itemColIlvl') + " $($i.ItemLevel))`r`n" + (Get-AcItemStatText $i 20)
    })
    $btnApply = New-Btn (T 'chr.itemApply') 712 580 130 30; $btnApply.Anchor = 'Right,Bottom'
    $btnClear = New-Btn (T 'chr.itemClear') 852 580 130 30; $btnClear.Anchor = 'Right,Bottom'
    $btnCancel = New-Btn (T 'btn.cancel') 992 580 100 30; $btnCancel.Anchor = 'Right,Bottom'
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.Controls.AddRange(@($lblS, $txtS, $chkFit, $lblWarnFit, $lvI, $txtIStats, $btnApply, $btnClear, $btnCancel))

    $load = {
        $lvI.Items.Clear()
        $lblWarnFit.Text = $(if ($chkFit.Checked) { '' } else { T 'chr.itemNoFilterWarn' })
        $dlg.Cursor = 'WaitCursor'; Invoke-AcDoEvents
        try {
            $cls = 0; $lvl = 0
            if ($chkFit.Checked) { $cls = [int]$script:CurrentChar.class; $lvl = [int]$script:CurrentChar.level }
            foreach ($i in (Get-AcItemsForSlot $script:P $SlotInfo.Inv $cls $lvl $txtS.Text.Trim() ([int]$SlotInfo.Slot))) {
                $it = New-Object Windows.Forms.ListViewItem([string]$i.entry)
                [void]$it.SubItems.Add([string]$i.name)
                [void]$it.SubItems.Add([string]$i.ItemLevel)
                [void]$it.SubItems.Add([string]$i.RequiredLevel)
                [void]$it.SubItems.Add((Get-AcItemStatText $i 6))
                $q = 1; [void][int]::TryParse([string]$i.Quality, [ref]$q)
                $it.ForeColor = Get-AcQualityColor $q
                $it.Tag = $i
                [void]$lvI.Items.Add($it)
            }
        } catch { Show-AcError $_ }
        finally { $dlg.Cursor = 'Default' }
    }
    $dlg.Add_Shown({ & $load })
    $txtS.Add_KeyDown({ param($s2, $e2) if ($e2.KeyCode -eq 'Return') { $e2.SuppressKeyPress = $true; & $load } })
    $chkFit.Add_CheckedChanged({ & $load })
    $apply = {
        param([int]$Entry)
        try {
            if (-not (Confirm-DbStart 'db.reasonChars')) { return }
            Ensure-CharDb
            Set-AcCharacterItem $script:P ([int]$script:CurrentChar.guid) ([int]$SlotInfo.Slot) $Entry
            $script:OpLogTarget = $modLog
            Write-AcLog (T 'chr.itemChanged')
            $dlg.Close()
            Show-CharacterDetails $script:CurrentChar
        } catch { Show-AcError $_ }
    }
    $btnApply.Add_Click({ if ($lvI.SelectedItems.Count -gt 0) { & $apply ([int]$lvI.SelectedItems[0].Tag.entry) } })
    $lvI.Add_DoubleClick({ if ($lvI.SelectedItems.Count -gt 0) { & $apply ([int]$lvI.SelectedItems[0].Tag.entry) } })
    $btnClear.Add_Click({ & $apply 0 })
    [void]$dlg.ShowDialog($form)
}


# ---------------------------------------------------------------------
#  Tab "GM-Befehle": Befehlsliste des aktuell gebauten Servers
# ---------------------------------------------------------------------
$tabGm = New-Object Windows.Forms.TabPage
$tabGm.Text = 'GM commands'; $tabGm.Padding = New-Object Windows.Forms.Padding(8)
$tabs.TabPages.Add($tabGm)
$tabs.TabPages.Remove($tabInfo)
$tabs.TabPages.Add($tabInfo)

$btnGmReload = New-Btn 'Reload list' 12 10 150 30
$lblGmSearch = New-Lbl 'Search:' 172 16 60 $true
$txtGmSearch = New-Object Windows.Forms.TextBox
$txtGmSearch.Location = New-Object Drawing.Point(232, 12); $txtGmSearch.Size = New-Object Drawing.Size(240, 26)
$lblGmLevel = New-Lbl 'Security level:' 490 16 90 $true
$cmbGmLevel = New-Object Windows.Forms.ComboBox
$cmbGmLevel.DropDownStyle = 'DropDownList'; $cmbGmLevel.Location = New-Object Drawing.Point(580, 12); $cmbGmLevel.Size = New-Object Drawing.Size(180, 26)
$lblGmCount = New-Lbl '' 780 16 200 $false

$lvGm = New-Object Windows.Forms.ListView
$lvGm.View = 'Details'; $lvGm.FullRowSelect = $true; $lvGm.GridLines = $true; $lvGm.HideSelection = $false
$lvGm.Location = New-Object Drawing.Point(12, 48); $lvGm.Size = New-Object Drawing.Size(900, 380)
foreach ($c in @(@('gm.colCommand', 280), @('gm.colSecurity', 140), @('gm.colHelp', 460))) {
    [void]$lvGm.Columns.Add((T $c[0]), $c[1])
}

$txtGmHelp = New-Object Windows.Forms.TextBox
$txtGmHelp.Multiline = $true; $txtGmHelp.ReadOnly = $true; $txtGmHelp.ScrollBars = 'Vertical'
$txtGmHelp.Font = New-Object Drawing.Font('Consolas', 9)
$txtGmHelp.Location = New-Object Drawing.Point(12, 436); $txtGmHelp.Size = New-Object Drawing.Size(900, 120)

$btnGmCopy = New-Btn 'Copy command' 12 566 180 32
$btnGmCopy.Tag = 'primary'
$btnGmCopy.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $btnGmCopy.Tag = 'primary'
$btnGmSend = New-Btn 'Send to server' 202 566 180 32
$lblGmHint = New-Lbl '' 392 574 520 $false; $lblGmHint.ForeColor = 'DimGray'

$tabGm.Controls.AddRange(@($btnGmReload, $lblGmSearch, $txtGmSearch, $lblGmLevel, $cmbGmLevel, $lblGmCount,
                           $lvGm, $txtGmHelp, $btnGmCopy, $btnGmSend, $lblGmHint))

$layoutGm = {
    $w = $tabGm.ClientSize.Width; $h = $tabGm.ClientSize.Height
    $helpH = 120
    $lvGm.Location = New-Object Drawing.Point(12, 48)
    $lvGm.Size = New-Object Drawing.Size(($w - 24), [Math]::Max(120, $h - 48 - $helpH - 60))
    $txtGmHelp.Location = New-Object Drawing.Point(12, ($h - $helpH - 48))
    $txtGmHelp.Size = New-Object Drawing.Size(($w - 24), $helpH)
    $btnGmCopy.Location = New-Object Drawing.Point(12, ($h - 40))
    $btnGmSend.Location = New-Object Drawing.Point(202, ($h - 40))
    $lblGmHint.Location = New-Object Drawing.Point(392, ($h - 32)); $lblGmHint.Width = [Math]::Max(200, $w - 404)
    $lblGmCount.Location = New-Object Drawing.Point(([Math]::Max(780, $w - 220)), 16)
}
$tabGm.Add_Resize($layoutGm)

$script:GmCommands = @()

function Fill-GmList {
    $lvGm.Items.Clear()
    $filter = $txtGmSearch.Text.Trim()
    $maxLvl = 99
    if ($cmbGmLevel.SelectedIndex -gt 0) { $maxLvl = $cmbGmLevel.SelectedIndex - 1 }
    $shown = 0
    foreach ($c in $script:GmCommands) {
        if ($maxLvl -ne 99 -and $c.Security -ne $maxLvl) { continue }
        if ($filter -and ($c.Name -notlike "*$filter*") -and ($c.Help -notlike "*$filter*")) { continue }
        $it = New-Object Windows.Forms.ListViewItem($c.Command)
        [void]$it.SubItems.Add((Get-AcSecurityName $c.Security))
        $short = $c.Help
        if ($short.Length -gt 150) { $short = $short.Substring(0, 150) + ' ...' }
        [void]$it.SubItems.Add($short)
        switch ($c.Security) {
            0 { $it.ForeColor = 'DarkGreen' }
            3 { $it.ForeColor = 'Firebrick' }
            4 { $it.ForeColor = 'DimGray' }
        }
        $it.Tag = $c
        [void]$lvGm.Items.Add($it)
        $shown++
    }
    $lblGmCount.Text = T 'gm.count' @($shown, $script:GmCommands.Count)
}

function Refresh-GmCommands {
    if ($script:DbBusy) { return }
    if (-not (Confirm-DbStart 'db.reasonGm')) { $lblGmHint.ForeColor = 'DarkRed'; $lblGmHint.Text = T 'db.notStarted'; return }
    try {
        Ensure-CharDb
        Set-CharBusy $true (T 'chr.loading')
        $script:GmCommands = @(Get-AcGmCommands $script:P)
    } catch {
        Set-CharBusy $false
        Show-AcError $_
        return
    } finally { Set-CharBusy $false }
    Fill-GmList
}

function Copy-GmCommand {
    if ($lvGm.SelectedItems.Count -eq 0) { return }
    $cmd = [string]$lvGm.SelectedItems[0].Tag.Command
    try { [Windows.Forms.Clipboard]::SetText($cmd); $lblGmHint.ForeColor = 'DarkGreen'; $lblGmHint.Text = T 'gm.copied' @($cmd) } catch {}
}

$btnGmReload.Add_Click({ Refresh-GmCommands })
$txtGmSearch.Add_TextChanged({ Fill-GmList })
$cmbGmLevel.Add_SelectedIndexChanged({ Fill-GmList })
$btnGmCopy.Add_Click({ Copy-GmCommand })
$lvGm.Add_DoubleClick({ Copy-GmCommand })
$lvGm.Add_SelectedIndexChanged({
    if ($lvGm.SelectedItems.Count -eq 0) { $txtGmHelp.Text = ''; return }
    $c = $lvGm.SelectedItems[0].Tag
    # Hilfetext lesbar umbrechen (die Rohdaten sind eine lange Zeile)
    $help = $c.Help -replace '\s(Syntax:|Beispiel:|Example:)', "`r`n`r`n`$1"
    $txtGmHelp.Text = $c.Command + "   [" + (Get-AcSecurityName $c.Security) + "]`r`n`r`n" + $help
    $btnGmSend.Enabled = [bool]($script:World -and -not $script:World.Process.HasExited)
})
$btnGmSend.Add_Click({
    if ($lvGm.SelectedItems.Count -eq 0) { return }
    $cmd = [string]$lvGm.SelectedItems[0].Tag.Name
    try {
        Send-WorldCommand $cmd
        $tabs.SelectedTab = $tabServer
    } catch { Show-AcError $_ }
})

# ---------------------------------------------------------------------
#  Sprache: alle festen Beschriftungen setzen (auch beim Umschalten)
# ---------------------------------------------------------------------
function Set-AcText {
    # setzt .Text nur, wenn das Steuerelement wirklich existiert - so kippt die
    # Sprachumschaltung nicht, wenn ein Element in eine andere Ansicht gewandert ist
    param($Control, [string]$Text)
    if ($null -eq $Control) { return }
    try { $Control.Text = $Text } catch {}
}

$applyTexts = {
    $tabServer.Text = T 'tab.server'; $tabUpdate.Text = T 'tab.update'; $tabCfg.Text = T 'tab.settings'
    $tabMod.Text = T 'tab.modules'; $tabInfo.Text = T 'tab.info'
    if ($script:UpdateAvailable) { $tabUpdate.Text = T 'tab.updateAvailable' }
    # Server
    foreach ($pair in @(@($lblMy, 'svc.mysql'), @($lblAu, 'svc.auth'), @($lblWo, 'svc.world'))) {
        Set-Status $pair[0] $pair[1] (Get-StatusKey $pair[0])
    }
    $btnStartAll.Text = T 'srv.start'; $btnStopAll.Text = T 'srv.stop'; $btnRestart.Text = T 'srv.restart'
    $chkAutoRestart.Text = T 'srv.autoRestart'; $lblCmd.Text = T 'srv.consoleLabel'
    $btnStopDb.Text = T 'srv.stopDb'
    $btnSend.Text = T 'srv.send'; $btnAccount.Text = T 'srv.account'
    # Update
    $btnCheck.Text = T 'upd.check'; $btnCheckAll.Text = T 'upd.all'; $btnCheckNone.Text = T 'upd.none'; $btnUpdate.Text = T 'upd.update'; $btnRebuild.Text = T 'upd.rebuild'
    $chkAutoStart.Text = T 'upd.autoStart'
    foreach ($i in 0..4) {
        $lvRepos.Columns[$i].Text = (T (@('upd.colRepo', 'upd.colBranch', 'upd.colLocal', 'upd.colRemote', 'upd.colBehind')[$i]))
    }
    # Einstellungen
    $lblCfgFile.Text = T 'cfg.file'; $lblCfgSearch.Text = T 'cfg.search'
    $btnCfgSave.Text = T 'cfg.save'; $btnCfgReload.Text = T 'cfg.reload'
    $grid.Columns[0].HeaderText = T 'cfg.colKey'; $grid.Columns[1].HeaderText = T 'cfg.colValue'
    $lblLang.Text = T 'lang.label'; $btnResetBots.Text = T 'bots.reset'
    $lblTheme.Text = T 'theme.label'
    $lblCpu.Text = T 'cpu.label'
    $selCpu = $cmbCpu.SelectedIndex
    $cmbCpu.Items.Clear()
    foreach ($k in @('full', 'balanced', 'background')) { [void]$cmbCpu.Items.Add((T ('ins.cpu.' + $k))) }
    $cmbCpu.SelectedIndex = $(if ($selCpu -ge 0) { $selCpu } else { [Math]::Max(0, @('full', 'balanced', 'background').IndexOf([string]$script:S.BuildProfile)) })
    $selT = $cmbTheme.SelectedIndex
    $cmbTheme.Items.Clear()
    [void]$cmbTheme.Items.Add((T 'theme.light')); [void]$cmbTheme.Items.Add((T 'theme.dark'))
    $cmbTheme.SelectedIndex = $(if ($selT -ge 0) { $selT } elseif ($script:S.Theme -eq 'dark') { 1 } else { 0 })
    # Module

    foreach ($i in 0..4) {
        $lvMods.Columns[$i].Text = (T (@('mod.colModule', 'mod.colGit', 'mod.colConfig', 'mod.colSql', 'mod.colBuilt')[$i]))
    }
    $dropLbl.Text = T 'mod.dropHere' @("`r`n")
    $lblGitUrl.Text = T 'mod.gitUrlLabel'; $btnGitAdd.Text = T 'mod.gitAdd'
    $btnModInfo.Text = T 'mod.info'; $btnModSql.Text = T 'mod.sqlCheck'; $btnModCfg.Text = T 'mod.configure'; $btnLua.Text = T 'lua.button'
    $btnModExport.Text = T 'mod.export'; $btnModImport.Text = T 'mod.import'
    $btnModRemove.Text = T 'mod.remove'; $btnModBuild.Text = T 'mod.rebuild'
    # Charaktere
    if ($tabs.TabPages.Contains($tabChar)) { $tabChar.Text = T 'tab.chars' }
    $btnCharReload.Text = T 'chr.reload'; $chkShowBots.Text = T 'chr.showBots'
    $lblCharSearch.Text = T 'chr.search'; $btnCharSave.Text = T 'chr.save'
    $lblCharVals.Text = T 'chr.values'
    $btnAutoEquip.Text = T 'chr.autoEquip'
    $btnCharExport.Text = T 'chr.export'; $btnCharImport.Text = T 'chr.import'
    $gridChar.Columns[0].HeaderText = T 'cfg.colKey'; $gridChar.Columns[1].HeaderText = T 'cfg.colValue'
    foreach ($i in 0..6) {
        $lvChars.Columns[$i].Text = (T (@('chr.colGuid', 'chr.colName', 'chr.colLevel', 'chr.colClass', 'chr.colRace', 'chr.colAccount', 'chr.colOnline')[$i]))
    }
    foreach ($s in $script:SlotButtons) {
        $item = $null; if ($s.Button.Tag) { $item = $s.Button.Tag.Item }
        $s.Button.Text = (T $s.Key) + ': ' + $(if ($item) { $item.name } else { T 'chr.empty' })
    }
    if (-not (Test-WorldStopped)) { $lblCharWarn.Text = T 'chr.serverRunning' }
    # GM-Befehle
    if ($tabs.TabPages.Contains($tabGm)) { $tabGm.Text = T 'tab.gm' }
    $btnGmReload.Text = T 'chr.reload'; $lblGmSearch.Text = T 'chr.search'
    $lblGmLevel.Text = T 'gm.level'; $btnGmCopy.Text = T 'gm.copy'; $btnGmSend.Text = T 'gm.send'
    foreach ($i in 0..2) { $lvGm.Columns[$i].Text = (T (@('gm.colCommand', 'gm.colSecurity', 'gm.colHelp')[$i])) }
    $sel = $cmbGmLevel.SelectedIndex
    $cmbGmLevel.Items.Clear()
    [void]$cmbGmLevel.Items.Add((T 'gm.allLevels'))
    foreach ($lvl in 0..4) { [void]$cmbGmLevel.Items.Add((Get-AcSecurityName $lvl)) }
    $cmbGmLevel.SelectedIndex = $(if ($sel -ge 0) { $sel } else { 0 })
    if ($script:GmCommands.Count -gt 0) { Fill-GmList }
    # Info
    $lblRealmAddr.Text = T 'inf.realmAddress'; $btnRealmAddr.Text = T 'inf.setAddress'
    & $fillInfoTab
    Reset-Title
}

function Get-PlayerbotsConf { $c = Join-Path $script:P.ModConfigs 'playerbots.conf'; if (Test-Path $c) { return $c }; return $null }

$btnResetBots.Add_Click({
    $conf = Get-PlayerbotsConf
    if (-not $conf) { [Windows.Forms.MessageBox]::Show((T 'bots.noConf'), (T 'word.error'), 'OK', 'Error') | Out-Null; return }
    if ([Windows.Forms.MessageBox]::Show((T 'bots.confirm' @("`r`n")), (T 'bots.reset'), 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        Set-AcConfValue $conf 'AiPlayerbot.DeleteRandomBotAccounts' '1'
        $script:S.ResetBotsPending = $true
        Save-AcSettings $script:P.Root $script:S
        $script:OpLogTarget = $console
        Write-AcLog (T 'bots.armed') 'STEP'
        Load-ConfGrid
        [Windows.Forms.MessageBox]::Show((T 'bots.armedMsg'), (T 'bots.reset'), 'OK', 'Information') | Out-Null
    } catch { Show-AcError $_ }
})

$script:BotResetRestart = $false

function Complete-BotReset {
    # Das Modul loescht die Bots und verlangt danach ausdruecklich einen Neustart -
    # erst der zweite Start legt die Bots neu an. Also: Schalter sofort zuruecknehmen
    # und einen Neustart vormerken. Ohne Neustart stuerzt der Server ab.
    if (-not $script:S.ResetBotsPending) { return }
    $conf = Get-PlayerbotsConf
    if ($conf) { try { Set-AcConfValue $conf 'AiPlayerbot.DeleteRandomBotAccounts' '0' } catch {} }
    $script:S.ResetBotsPending = $false
    Save-AcSettings $script:P.Root $script:S
    $script:BotResetRestart = $true
    Add-ConsoleLine $console (T 'bots.done') 'LightGreen'
    Add-ConsoleLine $console (T 'bots.restartPending') 'LightGreen'
}

function Invoke-BotResetRestart {
    if (-not $script:BotResetRestart) { return }
    $script:BotResetRestart = $false
    Add-ConsoleLine $console (T 'bots.restarting') 'LightGreen'
    Stop-Servers -KeepMySql
    Start-Servers
}

$cmbCpu.Add_SelectedIndexChanged({
    $key = @('full', 'balanced', 'background')[$cmbCpu.SelectedIndex]
    if ($key -eq [string]$script:S.BuildProfile) { return }
    $script:S.BuildProfile = $key
    Save-AcSettings $script:P.Root $script:S
})

$cmbTheme.Add_SelectedIndexChanged({
    $name = @('light', 'dark')[$cmbTheme.SelectedIndex]
    if ($name -eq $script:AcThemeName) { return }
    $script:S.Theme = $name
    Save-AcSettings $script:P.Root $script:S
    Update-AcTheme $form $name
    Refresh-Modules
    if ($script:CurrentChar) { Show-CharacterDetails $script:CurrentChar }
    if ($script:GmCommands.Count -gt 0) { Fill-GmList }
})

$cmbLang.Add_SelectedIndexChanged({
    $code = @('de', 'en')[$cmbLang.SelectedIndex]
    if ($code -eq $script:AcLanguage) { return }
    Set-AcLanguage $code
    $script:S.Language = $code
    Save-AcSettings $script:P.Root $script:S
    & $applyTexts
    Load-ConfFiles; Refresh-Modules
    if ($lblUpdInfo.Text) { $lblUpdInfo.Text = T 'upd.notChecked' }
})


function Show-SqlSyncResult {
    param($Sync)
    if (-not $Sync -or $Sync.Total -eq 0) { return }
    $nl = "`r`n"
    $msg = (T 'sql.summaryFound' @($Sync.Module, $Sync.Total)) + $nl + $nl
    $msg += (T 'sql.summaryAuto' @($Sync.Auto)) + $nl
    $msg += (T 'sql.summaryLinked' @($Sync.Linked)) + $nl
    if ($Sync.Optional -gt 0) { $msg += (T 'sql.summaryOptional' @($Sync.Optional)) + $nl }
    if ($Sync.Unknown -gt 0)  { $msg += (T 'sql.summaryUnknown' @($Sync.Unknown)) + $nl }
    $msg += $nl + (T 'sql.summaryFooter')
    if ($Sync.Optional -gt 0 -or $Sync.Unknown -gt 0) { $msg += $nl + (T 'sql.summaryHint') }
    [Windows.Forms.MessageBox]::Show($msg, (T 'sql.summaryTitle'), 'OK', 'Information') | Out-Null
}

function Show-ModuleSqlDialog {
    param([string]$ModuleName)
    $modPath = Join-Path $script:P.Modules $ModuleName
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = T 'sql.dlgTitle' @($ModuleName)
    $dlg.Size = New-Object Drawing.Size(860, 540); $dlg.StartPosition = 'CenterParent'; $dlg.Font = $form.Font
    $info = New-Object Windows.Forms.Label
    $info.Location = New-Object Drawing.Point(12, 10); $info.Size = New-Object Drawing.Size(820, 54)
    $info.Text = T 'sql.dlgInfo' @([Environment]::NewLine)
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.CheckBoxes = $true
    $lv.Location = New-Object Drawing.Point(12, 70); $lv.Size = New-Object Drawing.Size(820, 340); $lv.Anchor = 'Top,Left,Right,Bottom'
    [void]$lv.Columns.Add((T 'sql.colFile'), 430); [void]$lv.Columns.Add((T 'sql.colStatus'), 130); [void]$lv.Columns.Add((T 'sql.colDb'), 230)
    $cmbDb = New-Object Windows.Forms.ComboBox
    $cmbDb.DropDownStyle = 'DropDownList'; $cmbDb.Location = New-Object Drawing.Point(12, 424); $cmbDb.Size = New-Object Drawing.Size(200, 26); $cmbDb.Anchor = 'Left,Bottom'
    $dbChoices = @((T 'sql.targetFromColumn'), 'acore_world', 'acore_characters', 'acore_auth')
    if ($script:S.Variant -eq 'playerbots') { $dbChoices += 'acore_playerbots' }
    foreach ($x in $dbChoices) { [void]$cmbDb.Items.Add($x) }
    $cmbDb.SelectedIndex = 0
    $btnImport = New-Btn (T 'sql.importSelected') 222 422 220 30; $btnImport.Anchor = 'Left,Bottom'
    $btnResync = New-Btn (T 'sql.relink') 452 422 150 30; $btnResync.Anchor = 'Left,Bottom'
    $btnOpen = New-Btn (T 'btn.openFolder') 612 422 120 30; $btnOpen.Anchor = 'Left,Bottom'
    $btnClose2 = New-Btn (T 'btn.close') 742 422 90 30; $btnClose2.Anchor = 'Right,Bottom'; $btnClose2.Add_Click({ $dlg.Close() })
    $dlg.Controls.AddRange(@($info, $lv, $cmbDb, $btnImport, $btnResync, $btnOpen, $btnClose2))

    $fill = {
        $lv.Items.Clear()
        foreach ($f in (Get-AcModuleSqlFiles $modPath | Sort-Object Status, Rel)) {
            $it = New-Object Windows.Forms.ListViewItem($f.Rel)
            $label = switch ($f.Status) { 'auto' { T 'sql.auto' } 'linked' { T 'sql.linked' } 'handled' { T 'sql.handled' } 'legacy' { T 'sql.legacy' } 'optional' { T 'sql.optional' } default { T 'sql.unknown' } }
            [void]$it.SubItems.Add($label)
            $dbName = if ($f.Db) { $script:AcSqlDatabase[$f.Db] } else { '?' }
            [void]$it.SubItems.Add($dbName)
            if ($f.Status -eq 'legacy' -or $f.Status -eq 'unknown') { $it.ForeColor = Get-AcColor 'Bad' }
            if ($f.Status -eq 'auto' -or $f.Status -eq 'linked' -or $f.Status -eq 'handled') { $it.ForeColor = Get-AcColor 'Good' }
            $it.Tag = $f
            [void]$lv.Items.Add($it)
        }
    }
    & $fill

    $btnResync.Add_Click({
        $script:OpLogTarget = $modLog
        try { $s = Sync-AcModuleSql $modPath $ModuleName; & $fill; Refresh-Modules; Show-SqlSyncResult $s }
        catch { Show-AcError $_ }
    })
    $btnOpen.Add_Click({ Start-Process explorer.exe $modPath })
    $btnImport.Add_Click({
        $sel = @($lv.CheckedItems)
        if ($sel.Count -eq 0) { [Windows.Forms.MessageBox]::Show((T 'sql.checkFirst')) | Out-Null; return }
        $auto = @($sel | Where-Object { $_.Tag.Status -eq 'auto' -or $_.Tag.Status -eq 'linked' })
        $warn = T 'sql.importConfirm'
        if ($auto.Count -gt 0) {
            $warn += [Environment]::NewLine + [Environment]::NewLine + (T 'sql.importWarnAuto' @($auto.Count))
        }
        if ([Windows.Forms.MessageBox]::Show($warn, (T 'sql.importTitle'), 'YesNo', 'Warning') -ne 'Yes') { return }
        $script:OpLogTarget = $modLog
        try {
            $st = Start-AcMySql $script:P; if ($st) { $script:MySql = $st; Set-Status $lblMy 'svc.mysql' 'state.running' }
            $okCount = 0
            $doneRel = @()
            foreach ($it in $sel) {
                $db = if ($cmbDb.SelectedIndex -gt 0) { $cmbDb.SelectedItem } elseif ($it.Tag.Db) { $script:AcSqlDatabase[$it.Tag.Db] } else { $null }
                if (-not $db) { Write-AcLog (T 'sql.skippedNoDb' @($it.Tag.Rel)) 'WARN'; continue }
                Invoke-AcSqlFile $script:P $it.Tag.Full $db
                $doneRel += [string]$it.Tag.Rel
                $okCount++
            }
            # eingespielte Dateien vermerken, damit sie nicht weiter als offen gelten
            if ($doneRel.Count -gt 0) { Add-AcHandledSql $modPath $doneRel }
            & $fill
            Refresh-Modules
            [Windows.Forms.MessageBox]::Show((T 'sql.imported' @($okCount)), (T 'sql.importTitle'), 'OK', 'Information') | Out-Null
        } catch { Show-AcError $_ }
    })
    [void]$dlg.ShowDialog($form)
}

$btnModSql.Add_Click({
    $sel = Get-SelectedModuleName
    if (-not $sel) {
        if (Test-SelectedIsLua) { Show-LuaDialog; return }
        [Windows.Forms.MessageBox]::Show((T 'mod.selectFirst')) | Out-Null; return
    }
    Show-ModuleSqlDialog $sel
})


# ---------------------------------------------------------------------
#  Info
# ---------------------------------------------------------------------
$fillInfoTab = {
    $nl = [Environment]::NewLine
    $lines = @(
        (T 'inf.managerVersion')  + "   $($script:AcToolsVersion)   ($PSScriptRoot)",
        (T 'inf.serverFolder')    + "   $($script:P.Root)",
        (T 'inf.variant')         + "   $($script:S.Variant)  ($($script:S.CoreUrl) @ $($script:S.CoreBranch))",
        (T 'inf.binaries')        + "   $($script:P.Bin)",
        (T 'inf.configs')         + "   $($script:P.Configs)",
        (T 'inf.clientData')      + "   $($script:P.Data)",
        (T 'inf.logs')            + "   $($script:P.Logs)",
        (T 'inf.mysql')           + "   127.0.0.1:$($script:S.MySqlPort)   $($script:S.DbUser)   (ac-settings.json)",
        (T 'inf.realm')           + "   $($script:S.RealmName)",
        '',
        (T 'inf.body' @($nl))
    )
    $txtInfo.Text = ($lines -join $nl)
}

# ---------------------------------------------------------------------
#  Start / Ende
# ---------------------------------------------------------------------
$tabs.Add_SelectedIndexChanged({
    foreach ($lay in @($layoutServer, $layoutUpdate, $layoutCfg, $layoutMod, $layoutChar, $layoutGm)) { & $lay }
    if ($script:Busy -or $script:DbBusy) { return }
    # Datenbankabhaengige Tabs: bei jedem Oeffnen fragen, solange MySQL nicht laeuft
    if ($tabs.SelectedTab -eq $tabChar) {
        if (Test-AcMySqlAlive $script:P) {
            if ($lvChars.Items.Count -eq 0) { Refresh-CharList }
        } elseif (Confirm-DbStart 'db.reasonChars') {
            if ($tabs.SelectedTab -eq $tabChar) { Refresh-CharList }
        } else { $lblCharWarn.ForeColor = 'DarkRed'; $lblCharWarn.Text = T 'db.notStarted' }
    }
    if ($tabs.SelectedTab -eq $tabGm) {
        if (Test-AcMySqlAlive $script:P) {
            if ($script:GmCommands.Count -eq 0) { Refresh-GmCommands }
        } elseif (Confirm-DbStart 'db.reasonGm') {
            if ($tabs.SelectedTab -eq $tabGm) { Refresh-GmCommands }
        } else { $lblGmHint.ForeColor = 'DarkRed'; $lblGmHint.Text = T 'db.notStarted' }
    }
})
$form.Add_Shown({
    # Jeder Schritt einzeln abgesichert: so sagt eine Stoerung beim Start, WO sie
    # auftrat, statt nur "Argumenttypen stimmen nicht ueberein" zu melden
    $steps = @(
        @{ Name = 'Theme';   Do = { Update-AcTheme $form $script:S.Theme } }
        @{ Name = 'Layout';  Do = { foreach ($lay in @($layoutServer, $layoutUpdate, $layoutCfg, $layoutMod, $layoutChar, $layoutGm)) { & $lay } } }
        @{ Name = 'Texts';   Do = { & $applyTexts } }
        @{ Name = 'Configs'; Do = { Load-ConfFiles } }
        @{ Name = 'Modules'; Do = { Refresh-Modules } }
        @{ Name = 'Buttons'; Do = { Update-Buttons } }
        # Zweiter Durchgang: jetzt haben alle Steuerelemente ein Fensterhandle,
        # erst dann greifen dunkle Bildlaufleisten und Rahmen
        @{ Name = 'Theme2';  Do = { Update-AcTheme $form $script:S.Theme } }
    )
    foreach ($st in $steps) {
        try { & $st.Do } catch { Show-AcError $_ ("Start/" + $st.Name) }
    }
    $timer.Start()
    if (Test-AcMySqlAlive $script:P) { Set-Status $lblMy 'svc.mysql' 'state.running' } else { Set-Status $lblMy 'svc.mysql' 'state.stopped' }
    Update-Buttons
    # Kein automatischer Update-Check beim Start: git fetch fuer jedes Modul kostet Zeit.
    # Geprueft wird nur ueber "Nach Updates suchen" im Update-Tab.
    $lblUpdInfo.Text = T 'upd.notChecked'
})
$form.Add_FormClosing({
    param($sender, $e)
    if ($script:Busy) {
        [Windows.Forms.MessageBox]::Show((T 'exit.busy'), (T 'exit.busyTitle'), 'OK', 'Warning') | Out-Null
        $e.Cancel = $true; return
    }
    $running = ($script:World -and -not $script:World.Process.HasExited)
    if ($running) {
        $r = [Windows.Forms.MessageBox]::Show((T 'exit.running' @("`n")), (T 'exit.title'), 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { $e.Cancel = $true; return }
        if ($r -eq 'Yes') { Stop-Servers }
    }
    # MySQL immer beenden - auch wenn es nur fuer den Charakter-Editor gestartet wurde
    # oder aus einer frueheren Sitzung stammt.
    if (Test-AcMySqlAlive $script:P) {
        Add-ConsoleLine $console (T 'srv.stoppingMysql') 'LightGreen'
        try { Stop-AcMySql $script:P $script:MySql } catch {}
        $script:MySql = $null
        Set-Status $lblMy 'svc.mysql' 'state.stopped'
    }
    $timer.Stop()
    try { Remove-Item (Join-Path $script:P.Root '.manager-pid') -Force -ErrorAction SilentlyContinue } catch {}
    try { $script:AcMutex.ReleaseMutex(); $script:AcMutex.Dispose() } catch {}
})

[void]$form.ShowDialog()
