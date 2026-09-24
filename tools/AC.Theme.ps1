# =====================================================================
#  AC.Theme.ps1 - Erscheinungsbild der Oberflaeche
#  Wird von AC.Common.ps1 geladen. Set-AcTheme waehlt die Palette,
#  Update-AcTheme faerbt ein Fenster samt aller Unterelemente ein.
# =====================================================================

$script:AcThemeVersion = '2026-09-06.94'

$script:AcThemes = @{
    light = @{
        Name        = 'light'
        Window      = '#F4F5F7'   # Fensterhintergrund
        Surface     = '#FFFFFF'   # Listen, Eingabefelder
        SurfaceAlt  = '#EDEFF2'   # abwechselnde Zeilen, Kopfzeilen
        Border      = '#D6D9DE'
        Text        = '#1B1F24'
        TextDim     = '#5C6570'
        Accent      = '#2D6CDF'   # Auswahl, Hauptknopf
        AccentText  = '#FFFFFF'
        AccentHover = '#4680E8'
        Button      = '#FFFFFF'
        ButtonHover = '#E8EEFB'
        Good        = '#1E7F3C'
        Warn        = '#B4690E'
        Bad         = '#C0392B'
        Console     = '#12151A'
        ConsoleText = '#DDE1E6'
    }
    dark = @{
        Name        = 'dark'
        Window      = '#1B1F24'
        Surface     = '#22272E'
        SurfaceAlt  = '#2A3038'
        Border      = '#39414B'
        Text        = '#E6E9ED'
        TextDim     = '#98A2AE'
        Accent      = '#3D7EFF'
        AccentText  = '#FFFFFF'
        AccentHover = '#5590FF'
        Button      = '#2A3038'
        ButtonHover = '#343C46'
        Good        = '#4CC77C'
        Warn        = '#E0A32E'
        Bad         = '#F06A5E'
        Console     = '#0E1116'
        ConsoleText = '#DDE1E6'
    }
}

$script:AcTheme = $null

function Get-AcColor {
    param([string]$Key)
    if (-not $script:AcTheme) { Set-AcTheme 'light' }
    return [Drawing.ColorTranslator]::FromHtml($script:AcTheme[$Key])
}

function Set-AcTheme {
    param([string]$Name = 'light')
    if (-not $script:AcThemes.ContainsKey($Name)) { $Name = 'light' }
    $script:AcTheme = $script:AcThemes[$Name]
    $script:AcThemeName = $Name
}

function Get-AcQualityColor {
    <#
      Item-Qualitaetsfarben. Grau und Weiss sind auf hellem Grund unlesbar,
      deshalb wird dort die normale Textfarbe verwendet.
    #>
    param([int]$Quality)
    $hex = @{ 0 = '#9D9D9D'; 1 = '#FFFFFF'; 2 = '#1EAF34'; 3 = '#0070DD'; 4 = '#A335EE'; 5 = '#FF8000'; 6 = '#E6CC80'; 7 = '#E6CC80' }
    if ($Quality -le 1) {
        if ($script:AcThemeName -eq 'dark') { return (Get-AcColor 'TextDim') }
        return (Get-AcColor 'Text')
    }
    if ($Quality -eq 2 -and $script:AcThemeName -eq 'dark') { return [Drawing.ColorTranslator]::FromHtml('#3FD35C') }
    if ($Quality -eq 3 -and $script:AcThemeName -eq 'dark') { return [Drawing.ColorTranslator]::FromHtml('#4E9BFF') }
    if (-not $hex.ContainsKey($Quality)) { return (Get-AcColor 'Text') }
    return [Drawing.ColorTranslator]::FromHtml($hex[$Quality])
}

function Set-AcFlatButton {
    <#
      Flacher Knopf mit Hover-Effekt. $Primary hebt den Hauptknopf farbig hervor.
    #>
    param($Button, [switch]$Primary)
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.UseVisualStyleBackColor = $false
    $Button.Cursor = 'Hand'
    if ($Primary) {
        $Button.BackColor = Get-AcColor 'Accent'
        $Button.ForeColor = Get-AcColor 'AccentText'
        $Button.FlatAppearance.BorderColor = Get-AcColor 'Accent'
        $Button.FlatAppearance.MouseOverBackColor = Get-AcColor 'AccentHover'
    } else {
        $Button.BackColor = Get-AcColor 'Button'
        $Button.ForeColor = Get-AcColor 'Text'
        $Button.FlatAppearance.BorderColor = Get-AcColor 'Border'
        $Button.FlatAppearance.MouseDownBackColor = Get-AcColor 'SurfaceAlt'
        $Button.FlatAppearance.MouseOverBackColor = Get-AcColor 'ButtonHover'
    }
    if (-not $Button.Tag -or -not ($Button.Tag -is [hashtable])) { }
}

function Set-AcTabControlStyle {
    <#
      WinForms zeichnet Registerkarten im Stil aelterer Windows-Versionen.
      Mit OwnerDraw werden sie flach und in den Themenfarben gezeichnet.
    #>
    param($Tabs)
    if ($Tabs.Tag -eq 'themed') { $Tabs.Invalidate(); return }
    $Tabs.DrawMode = 'OwnerDrawFixed'
    $Tabs.SizeMode = 'Fixed'
    # Kartenbreite an die Anzahl der Registerkarten anpassen, damit keine
    # abgeschnitten wird und die Pfeile zum Blaettern erscheinen
    $count = [Math]::Max(1, $Tabs.TabPages.Count)
    $fit = [int](($Tabs.ClientSize.Width - 8) / $count)
    # keine Obergrenze: die Karten fuellen den Streifen vollstaendig, dadurch
    # bleibt rechts keine Flaeche in der hellen Systemfarbe uebrig
    $wTab = [Math]::Max(96, $fit)
    $Tabs.ItemSize = New-Object Drawing.Size($wTab, 34)
    $Tabs.Padding = New-Object Drawing.Point(0, 0)
    $Tabs.Appearance = 'Normal'
    $Tabs.Add_DrawItem({
        param($sender, $e)
        try {
        $page = $sender.TabPages[$e.Index]
        $sel = ($e.Index -eq $sender.SelectedIndex)
        $rect = $e.Bounds
        $bg = if ($sel) { Get-AcColor 'Surface' } else { Get-AcColor 'Window' }
        $fg = if ($sel) { Get-AcColor 'Text' } else { Get-AcColor 'TextDim' }
        $brush = New-Object Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
        if ($sel) {
            # farbige Linie unter der aktiven Karte
            $accent = New-Object Drawing.SolidBrush((Get-AcColor 'Accent'))
            $e.Graphics.FillRectangle($accent, (New-Object Drawing.Rectangle($rect.X, ($rect.Bottom - 3), $rect.Width, 3)))
            $accent.Dispose()
        }
        # Rest des Streifens rechts neben der letzten Karte fuellen - dort zeichnet
        # WinForms sonst in der Systemfarbe. Bewusst nur dort, damit keine bereits
        # gezeichnete Karte uebermalt wird.
        if ($e.Index -eq ($sender.TabPages.Count - 1)) {
            $restX = $rect.Right
            $restW = $sender.Width - $restX
            if ($restW -gt 0) {
                $restRect = New-Object Drawing.Rectangle([int]$restX, 0, [int]$restW, [int]($sender.ItemSize.Height + 4))
                $bgRest = New-Object Drawing.SolidBrush((Get-AcColor 'Window'))
                $e.Graphics.FillRectangle($bgRest, $restRect)
                $bgRest.Dispose()
            }
        }
        $fmt = New-Object Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $tb = New-Object Drawing.SolidBrush($fg)
        $font = New-Object Drawing.Font('Segoe UI', 9.5, $(if ($sel) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }))
        $e.Graphics.DrawString($page.Text, $font, $tb, ([Drawing.RectangleF]$rect), $fmt)
        $font.Dispose(); $tb.Dispose(); $fmt.Dispose()
        } catch { }
    })
    $Tabs.Add_Resize({
        $c = [Math]::Max(1, $this.TabPages.Count)
        $f = [int](($this.ClientSize.Width - 8) / $c)
        $w = [Math]::Max(96, $f)
        if ($this.ItemSize.Width -ne $w) { $this.ItemSize = New-Object Drawing.Size($w, 34) }
    })
    $Tabs.Tag = 'themed'
    $Tabs.Invalidate()
}


function Initialize-AcNativeTheme {
    <#
      Schnittstellen von Windows, mit denen sich systemgezeichnete Teile dunkel
      schalten lassen: Bildlaufleisten (uxtheme), Fensterrahmen und Titelleiste (dwmapi).
    #>
    if ('AcNative' -as [type]) { return }
    try {
        Add-Type -Namespace '' -Name 'AcNative' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetWindowTheme(System.IntPtr hwnd, string pszSubAppName, string pszSubIdList);

[System.Runtime.InteropServices.DllImport("uxtheme.dll", EntryPoint = "#135", SetLastError = true)]
public static extern int SetPreferredAppMode(int appMode);

[System.Runtime.InteropServices.DllImport("uxtheme.dll", EntryPoint = "#133", SetLastError = true)]
public static extern bool AllowDarkModeForWindow(System.IntPtr hwnd, bool allow);

[System.Runtime.InteropServices.DllImport("uxtheme.dll", EntryPoint = "#136")]
public static extern void FlushMenuThemes();

[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
'@
    } catch { }
}

function Set-AcNativeDark {
    <#
      Setzt das dunkle Systemdesign fuer ein Steuerelement. Dadurch werden auch
      Bildlaufleisten dunkel - sie gehoeren zum Steuerelement, nicht zur Oberflaeche.
    #>
    param($Control, [bool]$Dark)
    Initialize-AcNativeTheme
    if (-not ('AcNative' -as [type])) { return }
    try {
        if (-not $Control.IsHandleCreated) { return }
        # Erst erlauben, dann setzen - ohne den ersten Schritt ignoriert Windows
        # das dunkle Design fuer dieses Fenster
        try { [void][AcNative]::AllowDarkModeForWindow($Control.Handle, $Dark) } catch {}
        $theme = $(if ($Dark) { 'DarkMode_Explorer' } else { 'Explorer' })
        [void][AcNative]::SetWindowTheme($Control.Handle, $theme, $null)
    } catch { }
}

function Set-AcAppDarkMode {
    # Fensterweit: 2 = dunkel erzwingen, 3 = dem System folgen
    param([bool]$Dark)
    Initialize-AcNativeTheme
    if (-not ('AcNative' -as [type])) { return }
    try {
        [void][AcNative]::SetPreferredAppMode($(if ($Dark) { 2 } else { 3 }))
        [AcNative]::FlushMenuThemes()
    } catch { }
}

function Set-AcListViewStyle {
    <#
      Spaltenkoepfe zeichnet Windows hell. Mit OwnerDraw malen wir sie selbst;
      Zeilen bleiben in der Standardzeichnung, damit Auswahl und Farben stimmen.
    #>
    param($Control)
    $Control.BackColor = Get-AcColor 'Surface'
    $Control.ForeColor = Get-AcColor 'Text'
    $Control.GridLines = $false
    $Control.FullRowSelect = $true
    $Control.BorderStyle = $(if ($script:AcThemeName -eq 'dark') { 'None' } else { 'FixedSingle' })
    Set-AcNativeDark $Control ($script:AcThemeName -eq 'dark')
    if ($Control.Tag -ne 'lv-themed') {
        $Control.OwnerDraw = $true
        $Control.Add_DrawColumnHeader({
            param($sender, $e)
            try {
                $bg = New-Object Drawing.SolidBrush((Get-AcColor 'SurfaceAlt'))
                $e.Graphics.FillRectangle($bg, $e.Bounds); $bg.Dispose()
                $pen = New-Object Drawing.Pen((Get-AcColor 'Border'))
                $e.Graphics.DrawLine($pen, $e.Bounds.Right - 1, $e.Bounds.Top + 4, $e.Bounds.Right - 1, $e.Bounds.Bottom - 4)
                $e.Graphics.DrawLine($pen, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
                $pen.Dispose()
                $fmt = New-Object Drawing.StringFormat
                $fmt.LineAlignment = 'Center'; $fmt.Trimming = 'EllipsisCharacter'; $fmt.FormatFlags = 'NoWrap'
                $tb = New-Object Drawing.SolidBrush((Get-AcColor 'Text'))
                $r = New-Object Drawing.RectangleF(($e.Bounds.X + 6), $e.Bounds.Y, ($e.Bounds.Width - 10), $e.Bounds.Height)
                $e.Graphics.DrawString($e.Header.Text, $sender.Font, $tb, $r, $fmt)
                $tb.Dispose(); $fmt.Dispose()
            } catch { $e.DrawDefault = $true }
        })
        $Control.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
        $Control.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })
        $Control.Tag = 'lv-themed'
    }
    $Control.Invalidate()
}

function Update-AcThemeControl {
    # Ein einzelnes Steuerelement einfaerben (rekursiv ueber die Kinder)
    param($Control)
    $t = $Control.GetType().Name
    switch ($t) {
        'Form'          { $Control.BackColor = Get-AcColor 'Window'; $Control.ForeColor = Get-AcColor 'Text' }
        'TabControl'    {
            $Control.BackColor = Get-AcColor 'Window'
            # Im dunklen Design das Systemdesign abschalten: sonst zeichnet Windows
            # helle Raender um die Karten und um den Seitenbereich
            Initialize-AcNativeTheme
            if (('AcNative' -as [type]) -and $Control.IsHandleCreated) {
                try {
                    if ($script:AcThemeName -eq 'dark') { [void][AcNative]::SetWindowTheme($Control.Handle, '', '') }
                    else { [void][AcNative]::SetWindowTheme($Control.Handle, $null, $null) }
                } catch {}
            }
            Set-AcTabControlStyle $Control
        }
        'TabPage'       { $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text' }
        'Panel'         { if ($Control.BorderStyle -ne 'None' -and $script:AcThemeName -eq 'light') { $Control.BorderStyle = 'FixedSingle' }
                          elseif ($script:AcThemeName -eq 'dark') { $Control.BorderStyle = 'None' }
                          $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text' }
        'Label'         { $Control.BackColor = [Drawing.Color]::Transparent
                          if (-not $Control.Tag -or $Control.Tag -ne 'keepcolor') { if ($Control.ForeColor -eq [Drawing.Color]::Empty) { $Control.ForeColor = Get-AcColor 'Text' } } }
        'CheckBox'      { $Control.BackColor = [Drawing.Color]::Transparent; $Control.ForeColor = Get-AcColor 'Text'; $Control.FlatStyle = 'Flat' }
        'RadioButton'   { $Control.BackColor = [Drawing.Color]::Transparent; $Control.ForeColor = Get-AcColor 'Text'; $Control.FlatStyle = 'Flat' }
        'Button'        { if ($Control.Tag -eq 'primary') { Set-AcFlatButton $Control -Primary } else { Set-AcFlatButton $Control } }
        'TextBox'       { $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text'
                          if ($Control.Multiline -and $Control.ReadOnly) { $Control.BackColor = Get-AcColor 'SurfaceAlt' }
                          # im dunklen Design zeichnet Windows den Rahmen hell - deshalb ohne
                          $Control.BorderStyle = $(if ($script:AcThemeName -eq 'dark') { 'None' } else { 'FixedSingle' })
                          Set-AcNativeDark $Control ($script:AcThemeName -eq 'dark') }
        'ComboBox'      { $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text'; $Control.FlatStyle = 'Flat' }
        'NumericUpDown' { $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text'
                          $Control.BorderStyle = $(if ($script:AcThemeName -eq 'dark') { 'None' } else { 'FixedSingle' }) }
        'ListView'      { Set-AcListViewStyle $Control }
        'DataGridView'  {
            $Control.BackgroundColor = Get-AcColor 'Surface'
            $Control.BorderStyle = 'None'
            $Control.EnableHeadersVisualStyles = $false
            $Control.GridColor = Get-AcColor 'Border'
            $Control.CellBorderStyle = 'SingleHorizontal'
            $Control.ColumnHeadersBorderStyle = 'None'
            $Control.ColumnHeadersHeightSizeMode = 'DisableResizing'
            $Control.ColumnHeadersHeight = 30
            $Control.RowHeadersVisible = $false
            $Control.ColumnHeadersDefaultCellStyle.BackColor = Get-AcColor 'SurfaceAlt'
            $Control.ColumnHeadersDefaultCellStyle.ForeColor = Get-AcColor 'Text'
            $Control.ColumnHeadersDefaultCellStyle.SelectionBackColor = Get-AcColor 'SurfaceAlt'
            $Control.ColumnHeadersDefaultCellStyle.SelectionForeColor = Get-AcColor 'Text'
            $Control.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
            $Control.ColumnHeadersDefaultCellStyle.Padding = New-Object Windows.Forms.Padding(6, 0, 0, 0)
            $Control.DefaultCellStyle.BackColor = Get-AcColor 'Surface'
            $Control.DefaultCellStyle.ForeColor = Get-AcColor 'Text'
            $Control.DefaultCellStyle.SelectionBackColor = Get-AcColor 'Accent'
            $Control.DefaultCellStyle.SelectionForeColor = Get-AcColor 'AccentText'
            $Control.DefaultCellStyle.Padding = New-Object Windows.Forms.Padding(6, 2, 2, 2)
            $Control.AlternatingRowsDefaultCellStyle.BackColor = Get-AcColor 'SurfaceAlt'
            $Control.RowTemplate.Height = 26
            Set-AcNativeDark $Control ($script:AcThemeName -eq 'dark')
        }
        'RichTextBox'   { $Control.BackColor = Get-AcColor 'Console'; $Control.ForeColor = Get-AcColor 'ConsoleText'; $Control.BorderStyle = 'None'
                          Set-AcNativeDark $Control ($script:AcThemeName -eq 'dark') }
        'Splitter'      { $Control.BackColor = Get-AcColor 'Border' }
        'GroupBox'      { $Control.BackColor = [Drawing.Color]::Transparent; $Control.ForeColor = Get-AcColor 'Text' }
        'FlowLayoutPanel' { $Control.BackColor = Get-AcColor 'Surface' }
        'TreeView'      { $Control.BackColor = Get-AcColor 'Surface'; $Control.ForeColor = Get-AcColor 'Text'
                          $Control.LineColor = Get-AcColor 'Border'
                          $Control.BorderStyle = $(if ($script:AcThemeName -eq 'dark') { 'None' } else { 'FixedSingle' }) }
        'ProgressBar'   { }
        default         { }
    }
    foreach ($child in $Control.Controls) { Update-AcThemeControl $child }
}



function Set-AcWindowDarkMode {
    <#
      Titelleiste, Fensterrahmen und Rahmenfarbe zeichnet Windows selbst.
      20 = dunkler Modus (ab Windows 10 2004), 19 = derselbe Wert davor,
      34 = Rahmenfarbe, 35 = Titelleistenfarbe (ab Windows 11).
    #>
    param($Form, [bool]$Dark)
    Initialize-AcNativeTheme
    if (-not $Form -or -not ('AcNative' -as [type])) { return }
    try {
        if (-not $Form.IsHandleCreated) { return }
        try { [void][AcNative]::AllowDarkModeForWindow($Form.Handle, $Dark) } catch {}
        $val = [int]$Dark
        foreach ($attr in @(20, 19)) { [void][AcNative]::DwmSetWindowAttribute($Form.Handle, $attr, [ref]$val, 4) }
        # Farben als BGR; -1 bedeutet "Standard"
        $border = -1; $caption = -1
        if ($Dark) {
            $c = Get-AcColor 'Window'
            $border  = ($c.B -shl 16) -bor ($c.G -shl 8) -bor $c.R
            $caption = $border
        }
        [void][AcNative]::DwmSetWindowAttribute($Form.Handle, 34, [ref]$border, 4)
        [void][AcNative]::DwmSetWindowAttribute($Form.Handle, 35, [ref]$caption, 4)
        $Form.Refresh()
    } catch { }
}

function Update-AcTheme {
    <#
      Faerbt ein komplettes Fenster ein. Nach einem Themenwechsel erneut aufrufen.
    #>
    param($Form, [string]$Name = '')
    if ($Name) { Set-AcTheme $Name }
    if (-not $script:AcTheme) { Set-AcTheme 'light' }
    Set-AcAppDarkMode ($script:AcThemeName -eq 'dark')
    Set-AcWindowDarkMode $Form ($script:AcThemeName -eq 'dark')
    $Form.SuspendLayout()
    try {
        $Form.Font = New-Object Drawing.Font('Segoe UI', 9.5)
        Update-AcThemeControl $Form
    } finally { $Form.ResumeLayout() }
    $Form.Refresh()
    $Form.Refresh()
}
