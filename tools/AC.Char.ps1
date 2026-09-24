# =====================================================================
#  AC.Char.ps1 - Datenbankzugriff fuer den Charakter-Editor
#  Wird von AC.Common.ps1 geladen.
# =====================================================================

$script:AcCharVersion = '2026-09-06.94'

# --- Ausruestungsplaetze (Slot-Nummer wie in character_inventory, bag = 0) ---
#     Inv = passende InventoryType-Werte aus item_template
$script:AcEquipSlots = @(
    @{ Slot = 0;  Key = 'slot.head';     Inv = @(1) }
    @{ Slot = 1;  Key = 'slot.neck';     Inv = @(2) }
    @{ Slot = 2;  Key = 'slot.shoulder'; Inv = @(3) }
    @{ Slot = 3;  Key = 'slot.shirt';    Inv = @(4) }
    @{ Slot = 4;  Key = 'slot.chest';    Inv = @(5, 20) }
    @{ Slot = 5;  Key = 'slot.waist';    Inv = @(6) }
    @{ Slot = 6;  Key = 'slot.legs';     Inv = @(7) }
    @{ Slot = 7;  Key = 'slot.feet';     Inv = @(8) }
    @{ Slot = 8;  Key = 'slot.wrist';    Inv = @(9) }
    @{ Slot = 9;  Key = 'slot.hands';    Inv = @(10) }
    @{ Slot = 10; Key = 'slot.finger1';  Inv = @(11) }
    @{ Slot = 11; Key = 'slot.finger2';  Inv = @(11) }
    @{ Slot = 12; Key = 'slot.trinket1'; Inv = @(12) }
    @{ Slot = 13; Key = 'slot.trinket2'; Inv = @(12) }
    @{ Slot = 14; Key = 'slot.back';     Inv = @(16) }
    @{ Slot = 15; Key = 'slot.mainhand'; Inv = @(13, 17, 21) }
    @{ Slot = 16; Key = 'slot.offhand';  Inv = @(13, 14, 22, 23) }
    @{ Slot = 17; Key = 'slot.ranged';   Inv = @(15, 25, 26) }
    @{ Slot = 18; Key = 'slot.tabard';   Inv = @(19) }
)

$script:AcQualityColor = @{
    0 = '#9D9D9D'; 1 = '#FFFFFF'; 2 = '#1EFF00'; 3 = '#0070DD'
    4 = '#A335EE'; 5 = '#FF8000'; 6 = '#E6CC80'; 7 = '#E6CC80'
}

$script:AcClassNames = @{
    de = @{ 1 = 'Krieger'; 2 = 'Paladin'; 3 = 'Jaeger'; 4 = 'Schurke'; 5 = 'Priester'; 6 = 'Todesritter'; 7 = 'Schamane'; 8 = 'Magier'; 9 = 'Hexenmeister'; 11 = 'Druide' }
    en = @{ 1 = 'Warrior'; 2 = 'Paladin'; 3 = 'Hunter'; 4 = 'Rogue'; 5 = 'Priest'; 6 = 'Death Knight'; 7 = 'Shaman'; 8 = 'Mage'; 9 = 'Warlock'; 11 = 'Druid' }
}
$script:AcRaceNames = @{
    de = @{ 1 = 'Mensch'; 2 = 'Ork'; 3 = 'Zwerg'; 4 = 'Nachtelf'; 5 = 'Untoter'; 6 = 'Tauren'; 7 = 'Gnom'; 8 = 'Troll'; 10 = 'Blutelf'; 11 = 'Draenei' }
    en = @{ 1 = 'Human'; 2 = 'Orc'; 3 = 'Dwarf'; 4 = 'Night Elf'; 5 = 'Undead'; 6 = 'Tauren'; 7 = 'Gnome'; 8 = 'Troll'; 10 = 'Blood Elf'; 11 = 'Draenei' }
}

function Get-AcClassName { param([int]$Id) $t = $script:AcClassNames[$script:AcLanguage]; if (-not $t) { $t = $script:AcClassNames['en'] }; if ($t.ContainsKey($Id)) { return $t[$Id] }; return "Klasse $Id" }
function Get-AcRaceName  { param([int]$Id) $t = $script:AcRaceNames[$script:AcLanguage];  if (-not $t) { $t = $script:AcRaceNames['en'] };  if ($t.ContainsKey($Id)) { return $t[$Id] }; return "Rasse $Id" }
function Get-AcClassMask { param([int]$Id) return [int][Math]::Pow(2, $Id - 1) }

# --- SQL-Hilfsfunktionen ---------------------------------------------
function ConvertTo-AcSqlString {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace '\\', '\\\\' -replace "'", "''")
}

function Invoke-AcMySqlQuery {
    <#
      Fuehrt ein SELECT aus und liefert PSCustomObjects (Spaltennamen aus der Kopfzeile).
      mysql --batch liefert Tabulator-getrennt und maskiert Tabs/Zeilenumbrueche selbst.
    #>
    param($Paths, [Parameter(Mandatory)][string]$Sql, [string]$Database = 'acore_characters')
    $mysql = Get-AcMySqlExe $Paths 'mysql.exe'
    if (-not (Test-Path $Paths.MySqlCnf)) { throw (T 'log.noDbCreds') }
    $tmp = Join-Path $env:TEMP ("acq_" + [IO.Path]::GetRandomFileName() + '.sql')
    [IO.File]::WriteAllText($tmp, $Sql, (New-Object Text.UTF8Encoding($false)))
    try {
        $qArgs = "--defaults-extra-file=`"$($Paths.MySqlCnf)`" --batch --default-character-set=utf8mb4 $Database -e `"source $(ConvertTo-AcSlashPath $tmp)`""
        $r = Invoke-AcCaptureUi $mysql $qArgs
        if ($r.ExitCode -ne 0) { throw (T 'log.sqlError' @($r.Error)) }
        $lines = @($r.Output -split "`r?`n" | Where-Object { $_ -ne '' })
        if ($lines.Count -lt 2) { return @() }
        $cols = $lines[0] -split "`t"
        $rows = New-Object Collections.Generic.List[object]
        foreach ($line in $lines[1..($lines.Count - 1)]) {
            $vals = $line -split "`t"
            # Objekt Eigenschaft fuer Eigenschaft aufbauen: doppelte oder leere
            # Spaltennamen und Namen, die mit eingebauten Mitgliedern kollidieren,
            # bringen sonst die Umwandlung zum Scheitern
            $o = New-Object psobject
            for ($i = 0; $i -lt $cols.Count; $i++) {
                $name = ([string]$cols[$i]).Trim()
                if (-not $name) { continue }
                $v = if ($i -lt $vals.Count) { [string]$vals[$i] } else { '' }
                # mysql --batch gibt Leerwerte je nach Aufruf als \N oder als NULL aus
                if ($v -eq '\N' -or $v -eq 'NULL') { $v = '' }
                $v = ($v -replace '\\t', "`t" -replace '\\n', "`n")
                try { Add-Member -InputObject $o -MemberType NoteProperty -Name $name -Value $v -Force } catch {}
            }
            $rows.Add($o)
        }
        return $rows
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Invoke-AcMySqlExec {
    param($Paths, [Parameter(Mandatory)][string]$Sql, [string]$Database = 'acore_characters')
    Invoke-AcMySql $Paths $Sql $Database | Out-Null
}

# --- Charaktere -------------------------------------------------------
function Get-AcBotAccountPrefix {
    # Praefix der Zufallsbot-Accounts aus playerbots.conf (Standard: rndbot)
    param($Paths)
    $conf = Join-Path $Paths.ModConfigs 'playerbots.conf'
    if (Test-Path $conf) {
        try {
            foreach ($e in (Get-AcConfEntries $conf)) {
                if ($e.Key -match 'RandomBotAccountPrefix') { if ($e.Value) { return $e.Value } }
            }
        } catch {}
    }
    return 'rndbot'
}

function Get-AcCharacters {
    <#
      Liefert alle Charaktere. Zufallsbots (eigene Bot-Accounts) werden ausgeschlossen,
      Zweitcharaktere echter Accounts - auch wenn sie als Bot mitlaufen - bleiben drin.
    #>
    param($Paths, [switch]$IncludeBots)
    $prefix = ConvertTo-AcSqlString (Get-AcBotAccountPrefix $Paths)
    $where = ''
    if (-not $IncludeBots) { $where = "WHERE a.username NOT LIKE '$prefix%'" }
    $sql = @"
SELECT c.guid, c.name, c.race, c.class, c.gender, c.level, c.money, c.online, c.account, a.username
FROM acore_characters.characters c
LEFT JOIN acore_auth.account a ON a.id = c.account
$where
ORDER BY a.username, c.name;
"@
    return @(Invoke-AcMySqlQuery $Paths $sql 'acore_characters')
}

function Get-AcCharacterFields {
    # Bearbeitbare Spalten der Tabelle characters (Whitelist - alles andere wird nie geschrieben)
    return @(
        @{ Col = 'name';              Key = 'chr.name';        Type = 'text' }
        @{ Col = 'level';             Key = 'chr.level';       Type = 'int'; Min = 1;  Max = 255 }
        @{ Col = 'xp';                Key = 'chr.xp';          Type = 'int' }
        @{ Col = 'money';             Key = 'chr.money';       Type = 'int' }
        @{ Col = 'health';            Key = 'chr.health';      Type = 'int' }
        @{ Col = 'power1';            Key = 'chr.mana';        Type = 'int' }
        @{ Col = 'power2';            Key = 'chr.rage';        Type = 'int' }
        @{ Col = 'power3';            Key = 'chr.focus';       Type = 'int' }
        @{ Col = 'power4';            Key = 'chr.energy';      Type = 'int' }
        @{ Col = 'power7';            Key = 'chr.runicpower';  Type = 'int' }
        @{ Col = 'gender';            Key = 'chr.gender';      Type = 'int'; Min = 0; Max = 1 }
        @{ Col = 'skin';              Key = 'chr.skin';        Type = 'int'; Min = 0; Max = 255 }
        @{ Col = 'face';              Key = 'chr.face';        Type = 'int'; Min = 0; Max = 255 }
        @{ Col = 'hairStyle';         Key = 'chr.hairstyle';   Type = 'int'; Min = 0; Max = 255 }
        @{ Col = 'hairColor';         Key = 'chr.haircolor';   Type = 'int'; Min = 0; Max = 255 }
        @{ Col = 'facialStyle';       Key = 'chr.facialstyle'; Type = 'int'; Min = 0; Max = 255 }
        @{ Col = 'totalKills';        Key = 'chr.kills';       Type = 'int' }
        @{ Col = 'arenaPoints';       Key = 'chr.arenapoints'; Type = 'int' }
        @{ Col = 'totalHonorPoints';  Key = 'chr.honor';       Type = 'int' }
        @{ Col = 'map';               Key = 'chr.map';         Type = 'int' }
        @{ Col = 'zone';              Key = 'chr.zone';        Type = 'int' }
        @{ Col = 'position_x';        Key = 'chr.posx';        Type = 'float' }
        @{ Col = 'position_y';        Key = 'chr.posy';        Type = 'float' }
        @{ Col = 'position_z';        Key = 'chr.posz';        Type = 'float' }
        @{ Col = 'orientation';       Key = 'chr.orientation'; Type = 'float' }
        @{ Col = 'at_login';          Key = 'chr.atlogin';     Type = 'int' }
        @{ Col = 'playerFlags';       Key = 'chr.playerflags'; Type = 'int' }
    )
}


function Test-AcXpBlocked {
    # Bit 0x02000000 in playerFlags schaltet den Erfahrungsgewinn ab
    param($Char)
    if (-not $Char) { return $false }
    $f = 0; [void][int64]::TryParse([string]$Char.playerFlags, [ref]$f)
    return (($f -band 33554432) -ne 0)
}

function Get-AcMaxPlayerLevel {
    param($Paths)
    $conf = Join-Path $Paths.Configs 'worldserver.conf'
    if (Test-Path $conf) {
        try { foreach ($e in (Get-AcConfEntries $conf)) { if ($e.Key -eq 'MaxPlayerLevel') { return [int]$e.Value } } } catch {}
    }
    return 80
}

function Get-AcCharacter {
    param($Paths, [int]$Guid)
    $cols = (Get-AcCharacterFields | ForEach-Object { $_.Col }) -join ', '
    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT guid, race, class, online, account, $cols FROM characters WHERE guid = $Guid;")
    if ($rows.Count -eq 0) { return $null }
    return $rows[0]
}

function Get-AcCharacterEquipment {
    # Alle 19 Ausruestungsplaetze mit Item-Daten (leere Plaetze inklusive)
    param($Paths, [int]$Guid)
    $sql = @"
SELECT ci.slot, ii.guid AS itemGuid, ii.itemEntry, ii.count, ii.durability,
       it.name, it.Quality, it.ItemLevel, it.RequiredLevel, it.InventoryType, it.MaxDurability,
       it.armor, it.dmg_min1, it.dmg_max1, it.delay,
       it.stat_type1, it.stat_value1, it.stat_type2, it.stat_value2, it.stat_type3, it.stat_value3,
       it.stat_type4, it.stat_value4, it.stat_type5, it.stat_value5, it.stat_type6, it.stat_value6,
       it.stat_type7, it.stat_value7, it.stat_type8, it.stat_value8, it.stat_type9, it.stat_value9,
       it.stat_type10, it.stat_value10
FROM character_inventory ci
JOIN item_instance ii ON ii.guid = ci.item
LEFT JOIN acore_world.item_template it ON it.entry = ii.itemEntry
WHERE ci.guid = $Guid AND ci.bag = 0 AND ci.slot < 19;
"@
    $rows = @(Invoke-AcMySqlQuery $Paths $sql)
    $bySlot = @{}
    foreach ($r in $rows) { $bySlot[[int]$r.slot] = $r }
    $result = New-Object Collections.Generic.List[object]
    foreach ($s in $script:AcEquipSlots) {
        $item = $null
        if ($bySlot.ContainsKey($s.Slot)) { $item = $bySlot[$s.Slot] }
        $result.Add([pscustomobject]@{ Slot = $s.Slot; Key = $s.Key; Inv = $s.Inv; Item = $item })
    }
    return $result
}


# --- Kompetenzen (was darf welche Klasse ueberhaupt anlegen?) ---------
#  Der Server prueft das beim Login. Passt es nicht, bleibt der Platz leer,
#  deshalb muss der Editor genauso filtern wie der Server.
#  Ruestung: subclass 1=Stoff 2=Leder 3=Kette 4=Platte 6=Schild
#            7=Bibliothek 8=Idol 9=Totem 10=Siegel
$script:AcClassArmor = @{
    1 = @(1, 2, 3, 4); 2 = @(1, 2, 3, 4); 3 = @(1, 2, 3); 4 = @(1, 2); 5 = @(1)
    6 = @(1, 2, 3, 4); 7 = @(1, 2, 3); 8 = @(1); 9 = @(1); 11 = @(1, 2)
}
# Kette bzw. Platte gibt es erst ab Stufe 40 (Todesritter starten ohnehin auf 55)
$script:AcArmorLevel40 = @{ 3 = @(3); 7 = @(3); 1 = @(4); 2 = @(4) }
$script:AcClassShield  = @(1, 2, 7)
$script:AcClassRelic   = @{ 2 = 7; 11 = 8; 7 = 9; 6 = 10 }
#  Waffen: 0=Axt1H 1=Axt2H 2=Bogen 3=Schusswaffe 4=Streitkolben1H 5=Streitkolben2H
#          6=Stangenwaffe 7=Schwert1H 8=Schwert2H 10=Stab 13=Faustwaffe 15=Dolch
#          16=Wurfwaffe 18=Armbrust 19=Zauberstab 20=Angel
$script:AcClassWeapons = @{
    1  = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 20)
    2  = @(0, 1, 4, 5, 6, 7, 8, 20)
    3  = @(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18, 20)
    4  = @(0, 2, 3, 4, 7, 13, 15, 16, 18, 20)
    5  = @(4, 10, 15, 19, 20)
    6  = @(0, 1, 4, 5, 6, 7, 8, 20)
    7  = @(0, 1, 4, 5, 10, 13, 15, 20)
    8  = @(7, 10, 15, 19, 20)
    9  = @(7, 10, 15, 19, 20)
    11 = @(4, 5, 6, 10, 13, 15, 20)
}
$script:AcDualWield = @(1, 3, 4, 6, 7)   # Klassen, die eine Waffe in der Schildhand fuehren duerfen

function Get-AcProficiencySql {
    <#
      Liefert die WHERE-Bedingung, die genau die Gegenstaende zulaesst, die der
      Server der Klasse auch wirklich anlegen laesst. $Level = 0 heisst "Stufe egal".
    #>
    param([int]$ClassId, [int]$Level = 0, [int]$Slot = -1)
    if ($ClassId -le 0) { return '1' }
    $parts = New-Object Collections.Generic.List[string]

    # Ruestungsteile ohne Kompetenzpruefung: Umhang, Hals, Ring, Schmuck, Hemd, Wappenrock
    $parts.Add("(class = 4 AND (subclass = 0 OR InventoryType IN (2, 4, 11, 12, 16, 19)))")

    # Ruestungsarten der Klasse (Stufe 40 fuer Kette/Platte beachten)
    $armor = @()
    if ($script:AcClassArmor.ContainsKey($ClassId)) { $armor = @($script:AcClassArmor[$ClassId]) }
    if ($Level -gt 0 -and $Level -lt 40 -and $script:AcArmorLevel40.ContainsKey($ClassId)) {
        $late = @($script:AcArmorLevel40[$ClassId])
        $armor = @($armor | Where-Object { $late -notcontains $_ })
    }
    if ($armor.Count -gt 0) { $parts.Add("(class = 4 AND subclass IN ($($armor -join ', ')))") }

    # Schilde und Klassenrelikte
    if ($script:AcClassShield -contains $ClassId) { $parts.Add("(class = 4 AND subclass = 6)") }
    if ($script:AcClassRelic.ContainsKey($ClassId)) { $parts.Add("(class = 4 AND subclass = $($script:AcClassRelic[$ClassId]))") }

    # Waffen
    $weap = @()
    if ($script:AcClassWeapons.ContainsKey($ClassId)) { $weap = @($script:AcClassWeapons[$ClassId]) }
    if ($weap.Count -gt 0) {
        if ($Slot -eq 16 -and ($script:AcDualWield -notcontains $ClassId)) {
            # Schildhand: ohne beidhaendiges Kaempfen nur Schilde und Zusatzgegenstaende
            $parts.Add("(class = 4 AND InventoryType = 23)")
        } else {
            $parts.Add("(class = 2 AND subclass IN ($($weap -join ', ')))")
        }
    }
    # alles andere (z.B. Zusatzgegenstaende der Klasse Verschiedenes)
    $parts.Add("(class NOT IN (2, 4))")
    return '(' + ($parts -join ' OR ') + ')'
}

function Get-AcItemsForSlot {
    <#
      Items, die in einen bestimmten Platz passen. Filter nach Klasse und Stufe optional.
    #>
    param($Paths, [int[]]$InventoryTypes, [int]$ClassId = 0, [int]$MaxLevel = 0, [string]$Search = '', [int]$Slot = -1, [int]$Limit = 300)
    $inv = ($InventoryTypes -join ', ')
    $where = @("InventoryType IN ($inv)")
    if ($ClassId -gt 0) {
        $mask = Get-AcClassMask $ClassId
        $where += "(AllowableClass = -1 OR AllowableClass & $mask)"
        # zusaetzlich die tatsaechlichen Kompetenzen pruefen - AllowableClass allein
        # laesst z.B. Plattenruestung fuer jeden zu
        $where += (Get-AcProficiencySql $ClassId $MaxLevel $Slot)
    }
    if ($MaxLevel -gt 0) {
        $where += "RequiredLevel <= $MaxLevel"
        $where += (Get-AcLevelAppropriateSql $MaxLevel)
    }
    if ($Search) { $where += "name LIKE '%" + (ConvertTo-AcSqlString $Search) + "%'" }
    $sql = @"
SELECT $($script:AcItemColumns)
FROM acore_world.item_template
WHERE $($where -join ' AND ')
ORDER BY ItemLevel DESC, name ASC
LIMIT $Limit;
"@
    return @(Invoke-AcMySqlQuery $Paths $sql 'acore_world')
}

function Test-AcCharacterEditable {
    <#
      Nur Offline-Charaktere bearbeiten. Laeuft gar kein Worldserver, ist eine
      online-Markierung in der Datenbank veraltet (Absturz oder hartes Beenden)
      und darf ignoriert werden.
    #>
    param($Paths, [int]$Guid)
    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT online FROM characters WHERE guid = $Guid;")
    if ($rows.Count -eq 0) { return $false }
    if ([int]$rows[0].online -eq 0) { return $true }
    return (-not (Test-AcWorldRunning $Paths))
}

function Clear-AcStaleOnlineFlags {
    <#
      Setzt zurueckgebliebene online-Markierungen zurueck. Nur aufrufen, wenn
      sicher kein Worldserver laeuft.
    #>
    param($Paths)
    if (Test-AcWorldRunning $Paths) { return 0 }
    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT COUNT(*) AS n FROM characters WHERE online <> 0;")
    $n = 0; if ($rows.Count -gt 0) { [void][int]::TryParse([string]$rows[0].n, [ref]$n) }
    if ($n -gt 0) {
        Invoke-AcMySqlExec $Paths "UPDATE characters SET online = 0 WHERE online <> 0;"
        Write-AcLog (T 'chr.staleCleared' @($n)) 'WARN'
    }
    return $n
}

function Set-AcCharacterValues {
    # Schreibt geaenderte Felder (nur Spalten aus der Whitelist)
    param($Paths, [int]$Guid, [hashtable]$Values)
    $allowed = @{}
    foreach ($f in (Get-AcCharacterFields)) { $allowed[$f.Col] = $f }
    $sets = New-Object Collections.Generic.List[string]
    foreach ($k in $Values.Keys) {
        if (-not $allowed.ContainsKey($k)) { continue }
        $f = $allowed[$k]
        $v = [string]$Values[$k]
        switch ($f.Type) {
            'int'   { if ($v -notmatch '^-?\d+$') { throw "$($f.Col): " + (T 'chr.needInt') }
                      if ($f.ContainsKey('Min') -and [int64]$v -lt $f.Min) { throw "$($f.Col): >= $($f.Min)" }
                      if ($f.ContainsKey('Max') -and [int64]$v -gt $f.Max) { throw "$($f.Col): <= $($f.Max)" }
                      $sets.Add("``$($f.Col)`` = $v") }
            'float' { if ($v -notmatch '^-?\d+(\.\d+)?$') { throw "$($f.Col): " + (T 'chr.needNumber') }
                      $sets.Add("``$($f.Col)`` = $v") }
            default { $sets.Add("``$($f.Col)`` = '" + (ConvertTo-AcSqlString $v) + "'") }
        }
    }
    if ($sets.Count -eq 0) { return 0 }
    Invoke-AcMySqlExec $Paths ("UPDATE characters SET " + ($sets -join ', ') + " WHERE guid = $Guid;")
    return $sets.Count
}

function Update-AcEquipmentCache {
    # characters.equipmentCache bestimmt die Anzeige in der Charakterauswahl
    param($Paths, [int]$Guid)
    $eq = Get-AcCharacterEquipment $Paths $Guid
    $parts = New-Object Collections.Generic.List[string]
    foreach ($s in $eq) {
        $entry = if ($s.Item) { [int]$s.Item.itemEntry } else { 0 }
        $parts.Add("$entry"); $parts.Add('0')
    }
    $cache = ($parts -join ' ') + ' '
    Invoke-AcMySqlExec $Paths "UPDATE characters SET equipmentCache = '$cache' WHERE guid = $Guid;"
}


function Get-AcRequiredItemColumns {
    <#
      Spalten von item_instance, die NOT NULL sind und keinen Standardwert haben.
      Sie muessen beim Einfuegen mitgegeben werden - je nach Core-Version sind das
      unterschiedliche (z.B. 'enchantments'). Zahlen bekommen 0, Text bekommt ''.
      Fuer 'enchantments' wird die uebliche Nullenkette in der passenden Laenge erzeugt.
    #>
    param($Paths)
    if ($script:AcItemColumnCache) { return $script:AcItemColumnCache }
    $sql = @'
SELECT COLUMN_NAME, DATA_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'acore_characters' AND TABLE_NAME = 'item_instance'
  AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL AND EXTRA NOT LIKE '%auto_increment%';
'@
    $rows = @()
    try { $rows = @(Invoke-AcMySqlQuery $Paths $sql 'information_schema') } catch {}
    $list = New-Object Collections.Generic.List[object]
    foreach ($r in $rows) {
        $name = [string]$r.COLUMN_NAME
        $type = ([string]$r.DATA_TYPE).ToLower()
        $value = if ($name -ieq 'enchantments') { "'" + (Get-AcEmptyEnchantments $Paths) + "'" }
                 elseif ($type -match 'int|decimal|float|double|bit') { '0' }
                 else { "''" }
        $list.Add([pscustomobject]@{ Name = $name; Value = $value })
    }
    $script:AcItemColumnCache = $list
    return $list
}

function Get-AcEmptyEnchantments {
    # Laenge aus einem vorhandenen Eintrag uebernehmen, sonst 13 Slots * 3 Werte
    param($Paths)
    $count = 39
    try {
        $rows = @(Invoke-AcMySqlQuery $Paths "SELECT enchantments FROM item_instance WHERE enchantments <> '' LIMIT 1;")
        if ($rows.Count -gt 0) {
            $n = @(([string]$rows[0].enchantments) -split '\s+' | Where-Object { $_ -ne '' }).Count
            if ($n -gt 0) { $count = $n }
        }
    } catch {}
    return ((1..$count | ForEach-Object { '0' }) -join ' ')
}


function New-AcItemInstance {
    <#
      Legt einen Gegenstand in item_instance an und liefert seine GUID.
      Pflichtspalten ohne Standardwert werden aus information_schema ergaenzt.
    #>
    param($Paths, [int]$OwnerGuid, [int]$Entry, [int]$Count = 1)
    $tpl = @(Invoke-AcMySqlQuery $Paths "SELECT entry, MaxDurability FROM acore_world.item_template WHERE entry = $Entry;" 'acore_world')
    if ($tpl.Count -eq 0) { throw ((T 'chr.itemUnknown') + " ($Entry)") }
    $dur = 0; [void][int]::TryParse([string]$tpl[0].MaxDurability, [ref]$dur)
    if ($Count -lt 1) { $Count = 1 }
    # Freie Nummer ermitteln. Es wird nicht nur item_instance beruecksichtigt:
    # Nummern koennen auch in der Post oder in Auktionen stecken, und ein noch
    # laufender Server vergibt parallel eigene. Deshalb zusaetzlich mit Wiederholung.
    $maxSql = @"
SELECT GREATEST(
    IFNULL((SELECT MAX(guid) FROM item_instance), 0),
    IFNULL((SELECT MAX(item_guid) FROM mail_items), 0)
) + 1 AS g;
"@
    $next = @(Invoke-AcMySqlQuery $Paths $maxSql)
    $itemGuid = 0
    if ($next.Count -gt 0) { [void][int]::TryParse([string]$next[0].g, [ref]$itemGuid) }
    if ($itemGuid -le 0) { $itemGuid = 1 }
    $cols = New-Object Collections.Specialized.OrderedDictionary
    $cols['guid'] = "$itemGuid"; $cols['itemEntry'] = "$Entry"; $cols['owner_guid'] = "$OwnerGuid"
    $cols['count'] = "$Count"; $cols['durability'] = "$dur"
    foreach ($c in (Get-AcRequiredItemColumns $Paths)) {
        if (-not $cols.Contains($c.Name)) { $cols[$c.Name] = $c.Value }
    }
    # Bis zu zehn Anlaeufe: ist die Nummer schon vergeben, die naechste nehmen
    for ($try = 0; $try -lt 10; $try++) {
        $cols['guid'] = "$itemGuid"
        $names = ($cols.Keys | ForEach-Object { "``$_``" }) -join ', '
        $vals  = ($cols.Keys | ForEach-Object { [string]$cols[$_] }) -join ', '
        try {
            Invoke-AcMySqlExec $Paths "INSERT INTO item_instance ($names) VALUES ($vals);"
            return $itemGuid
        } catch {
            if ([string]$_.Exception.Message -notmatch 'Duplicate entry|1062') { throw }
            Write-AcLog (T 'chr.itemGuidTaken' @($itemGuid)) 'WARN'
            $itemGuid++
        }
    }
    throw (T 'chr.itemGuidFailed')
}

function Set-AcCharacterItem {
    <#
      Setzt (oder entfernt bei Entry = 0) ein Item in einen Ausruestungsplatz.
      Nur bei gestopptem Worldserver aufrufen - der Server vergibt sonst eigene Item-GUIDs.
    #>
    param($Paths, [int]$Guid, [int]$Slot, [int]$Entry)
    if (-not (Test-AcCharacterEditable $Paths $Guid)) { throw (T 'chr.onlineBlocked') }

    # altes Item im Platz entfernen
    $old = @(Invoke-AcMySqlQuery $Paths "SELECT item FROM character_inventory WHERE guid = $Guid AND bag = 0 AND slot = $Slot;")
    if ($old.Count -gt 0 -and $old[0].item) {
        $oldGuid = [int]$old[0].item
        Invoke-AcMySqlExec $Paths "DELETE FROM character_inventory WHERE guid = $Guid AND bag = 0 AND slot = $Slot;"
        Invoke-AcMySqlExec $Paths "DELETE FROM item_instance WHERE guid = $oldGuid;"
    }
    if ($Entry -gt 0) {
        $itemGuid = New-AcItemInstance $Paths $Guid $Entry 1
        Invoke-AcMySqlExec $Paths "INSERT INTO character_inventory (guid, bag, slot, item) VALUES ($Guid, 0, $Slot, $itemGuid);"
    }
    Update-AcEquipmentCache $Paths $Guid
}

# ---------------------------------------------------------------------
#  GM-Befehle des aktuellen Builds
# ---------------------------------------------------------------------
$script:AcSecurityNames = @{
    de = @{ 0 = 'Spieler'; 1 = 'Moderator'; 2 = 'Gamemaster'; 3 = 'Administrator'; 4 = 'Konsole' }
    en = @{ 0 = 'Player';  1 = 'Moderator'; 2 = 'Game Master'; 3 = 'Administrator'; 4 = 'Console' }
}
function Get-AcSecurityName {
    param([int]$Level)
    $t = $script:AcSecurityNames[$script:AcLanguage]; if (-not $t) { $t = $script:AcSecurityNames['en'] }
    if ($t.ContainsKey($Level)) { return $t[$Level] }
    return "$Level"
}

function Get-AcGmCommands {
    <#
      Liest die Befehlsliste aus acore_world.command. Diese Tabelle wird beim
      dbimport aus dem Quellcode des Cores und der Module befuellt, entspricht
      also genau dem aktuell gebauten Stand.
      Zeilenumbrueche im Hilfetext werden bereits in SQL entfernt - sonst wuerde
      ein Befehl in der Ausgabe ueber mehrere Zeilen zerfallen.
    #>
    param($Paths)
    $sql = @'
SELECT name,
       security,
       TRIM(REPLACE(REPLACE(REPLACE(COALESCE(help, ''), CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ')) AS help
FROM acore_world.command
WHERE name IS NOT NULL AND name <> ''
ORDER BY name;
'@
    $rows = @(Invoke-AcMySqlQuery $Paths $sql 'acore_world')
    $seen = New-Object Collections.Generic.HashSet[string]
    $list = New-Object Collections.Generic.List[object]
    foreach ($r in $rows) {
        $name = ([string]$r.name).Trim()
        # nur echte Befehlszeilen: Name vorhanden, Rechtestufe eine Zahl 0-4
        if (-not $name) { continue }
        $secText = ([string]$r.security).Trim()
        if ($secText -notmatch '^\d+$') { continue }
        $sec = [int]$secText
        if ($sec -lt 0 -or $sec -gt 4) { continue }
        if ($name -match '^[.\s]') { continue }
        if (-not $seen.Add($name)) { continue }
        $help = ([string]$r.help).Trim()
        while ($help -match '  ') { $help = $help -replace '  ', ' ' }
        $list.Add([pscustomobject]@{
            Name     = $name
            Command  = '.' + $name
            Security = $sec
            Help     = $help
        })
    }
    return $list
}

# ---------------------------------------------------------------------
#  Item-Werte, Bewertung und automatische Ausruestung
# ---------------------------------------------------------------------
#  stat_type aus item_template (ItemModType) -> interner Schluessel
$script:AcStatKey = @{
    0 = 'mana'; 1 = 'health'; 3 = 'agi'; 4 = 'str'; 5 = 'int'; 6 = 'spi'; 7 = 'sta'
    12 = 'defense'; 13 = 'dodge'; 14 = 'parry'; 15 = 'blockrating'
    16 = 'hit'; 17 = 'hit'; 18 = 'hit'; 19 = 'crit'; 20 = 'crit'; 21 = 'crit'
    28 = 'haste'; 29 = 'haste'; 30 = 'haste'
    31 = 'hit'; 32 = 'crit'; 33 = 'hit'; 34 = 'crit'; 35 = 'resilience'; 36 = 'haste'
    37 = 'expertise'; 38 = 'ap'; 39 = 'ap'; 41 = 'spellpower'; 42 = 'spellpower'
    43 = 'mp5'; 44 = 'armorpen'; 45 = 'spellpower'; 46 = 'hp5'; 47 = 'spellpen'; 48 = 'blockvalue'
}
$script:AcStatNames = @{
    de = @{ mana='Mana'; health='Leben'; agi='Beweglichkeit'; str='Staerke'; int='Intelligenz'; spi='Willenskraft'; sta='Ausdauer'
            defense='Verteidigung'; dodge='Ausweichen'; parry='Parieren'; blockrating='Blockwertung'; blockvalue='Blockwert'
            hit='Trefferwertung'; crit='Kritische Trefferwertung'; haste='Tempowertung'; resilience='Abhaertung'
            expertise='Waffenkunde'; ap='Angriffskraft'; spellpower='Zaubermacht'; mp5='Mana alle 5s'; hp5='Leben alle 5s'
            armorpen='Ruestungsdurchdringung'; spellpen='Zauberdurchschlag' }
    en = @{ mana='Mana'; health='Health'; agi='Agility'; str='Strength'; int='Intellect'; spi='Spirit'; sta='Stamina'
            defense='Defense'; dodge='Dodge'; parry='Parry'; blockrating='Block rating'; blockvalue='Block value'
            hit='Hit rating'; crit='Crit rating'; haste='Haste rating'; resilience='Resilience'
            expertise='Expertise'; ap='Attack power'; spellpower='Spell power'; mp5='Mana per 5s'; hp5='Health per 5s'
            armorpen='Armor penetration'; spellpen='Spell penetration' }
}
function Get-AcStatName { param([string]$Key)
    $t = $script:AcStatNames[$script:AcLanguage]; if (-not $t) { $t = $script:AcStatNames['en'] }
    if ($t.ContainsKey($Key)) { return $t[$Key] }; return $Key
}

#  Gewichtungen je Rolle. Bewusst grob gehalten - eine echte BiS-Liste haengt an
#  Talenten, Setboni und Verzauberungen, die hier nicht bekannt sind.
$script:AcRoleWeights = @{
    tank   = @{ sta=3.0; armor=0.03; str=1.0; agi=1.5; defense=2.5; dodge=2.0; parry=2.0; blockrating=1.2; blockvalue=0.6; resilience=0.3; expertise=1.5; hit=1.0; ap=0.2; crit=0.4; haste=0.4; dps=3.0 }
    melee  = @{ str=2.0; agi=2.0; sta=0.6; ap=1.0; crit=1.5; hit=1.8; haste=1.4; expertise=1.6; armorpen=1.0; armor=0.005; dps=9.0 }
    ranged = @{ agi=2.5; sta=0.6; ap=1.0; crit=1.5; hit=1.8; haste=1.2; armorpen=0.8; armor=0.005; dps=2.0; rangeddps=10.0 }
    caster = @{ spellpower=2.0; int=1.2; spi=0.5; sta=0.5; crit=1.5; hit=1.8; haste=1.5; mp5=0.5; armor=0.002 }
    healer = @{ spellpower=1.8; int=1.5; spi=1.5; sta=0.5; crit=1.0; haste=1.5; mp5=2.0; armor=0.002 }
}
$script:AcRoleKeys = @('tank', 'melee', 'ranged', 'caster', 'healer')
#  Vorschlag je Klasse (nur die Vorauswahl im Editor)
$script:AcClassDefaultRole = @{ 1='melee'; 2='melee'; 3='ranged'; 4='melee'; 5='caster'; 6='melee'; 7='melee'; 8='caster'; 9='caster'; 11='caster' }

$script:AcItemColumns = @"
entry, name, Quality, ItemLevel, RequiredLevel, InventoryType, class, subclass,
armor, dmg_min1, dmg_max1, delay,
stat_type1, stat_value1, stat_type2, stat_value2, stat_type3, stat_value3, stat_type4, stat_value4,
stat_type5, stat_value5, stat_type6, stat_value6, stat_type7, stat_value7, stat_type8, stat_value8,
stat_type9, stat_value9, stat_type10, stat_value10
"@

function Get-AcItemStatMap {
    # Liefert @{ str = 20; sta = 30; ... } inklusive Ruestung und Waffen-DPS
    param($Item)
    $map = @{}
    for ($i = 1; $i -le 10; $i++) {
        $t = 0; $v = 0
        [void][int]::TryParse([string]$Item."stat_type$i", [ref]$t)
        [void][int]::TryParse([string]$Item."stat_value$i", [ref]$v)
        if ($v -eq 0) { continue }
        if (-not $script:AcStatKey.ContainsKey($t)) { continue }
        $k = $script:AcStatKey[$t]
        if ($map.ContainsKey($k)) { $map[$k] += $v } else { $map[$k] = $v }
    }
    $armor = 0; [void][int]::TryParse([string]$Item.armor, [ref]$armor)
    if ($armor -gt 0) { $map['armor'] = $armor }
    $dmin = 0.0; $dmax = 0.0; $delay = 0
    [void][double]::TryParse(([string]$Item.dmg_min1 -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$dmin)
    [void][double]::TryParse(([string]$Item.dmg_max1 -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$dmax)
    [void][int]::TryParse([string]$Item.delay, [ref]$delay)
    if ($delay -gt 0 -and $dmax -gt 0) {
        $dps = [Math]::Round((($dmin + $dmax) / 2) / ($delay / 1000.0), 1)
        $inv = 0; [void][int]::TryParse([string]$Item.InventoryType, [ref]$inv)
        if ($inv -in @(15, 25, 26)) { $map['rangeddps'] = $dps } else { $map['dps'] = $dps }
    }
    return $map
}

function Get-AcItemStatText {
    # Kurztext fuer Liste und Tooltip
    param($Item, [int]$Max = 8)
    $map = Get-AcItemStatMap $Item
    $parts = New-Object Collections.Generic.List[string]
    foreach ($k in @('dps', 'rangeddps')) { if ($map.ContainsKey($k)) { $parts.Add("$($map[$k]) DPS") } }
    if ($map.ContainsKey('armor')) { $parts.Add((Get-AcStatName 'armor') + " $($map['armor'])") }
    foreach ($k in @('str', 'agi', 'sta', 'int', 'spi', 'spellpower', 'ap', 'crit', 'hit', 'haste', 'expertise', 'defense', 'dodge', 'parry', 'mp5', 'resilience', 'armorpen', 'blockvalue', 'blockrating', 'spellpen', 'hp5', 'mana', 'health')) {
        if ($map.ContainsKey($k)) { $parts.Add("+$($map[$k]) " + (Get-AcStatName $k)) }
        if ($parts.Count -ge $Max) { break }
    }
    return ($parts -join ', ')
}

function Get-AcItemScore {
    # Punktwert eines Items fuer eine Rolle
    param($Item, [hashtable]$Weights)
    $map = Get-AcItemStatMap $Item
    $score = 0.0
    foreach ($k in $map.Keys) {
        if ($Weights.ContainsKey($k)) { $score += ([double]$map[$k]) * [double]$Weights[$k] }
    }
    # leichte Bevorzugung hoeherer Gegenstandsstufe, damit Items ohne Werte nicht gewinnen
    $ilvl = 0; [void][int]::TryParse([string]$Item.ItemLevel, [ref]$ilvl)
    $score += $ilvl * 0.05
    return $score
}


function Get-AcMaxItemLevel {
    <#
      Obergrenze der Gegenstandsstufe fuer eine Charakterstufe. Die Skala springt
      bei 60 und 70 stark, deshalb abschnittsweise:
        bis 60:  Stufe + 10   (Stufe 20 -> 30)
        61-70:   70 + (Stufe-60)*8   (Stufe 70 -> 150)
        71-80:   150 + (Stufe-70)*14 (Stufe 80 -> 290)
    #>
    param([int]$Level)
    if ($Level -le 60) { return ($Level + 10) }
    if ($Level -le 70) { return (70 + ($Level - 60) * 8) }
    return (150 + ($Level - 70) * 14)
}

function Get-AcLevelAppropriateSql {
    <#
      Bedingungen, die unpassende Gegenstaende ausschliessen:
        - Gegenstandsstufe oberhalb der Grenze
        - Gegenstaende ohne Stufenanforderung, die deutlich ueber der Charakterstufe liegen
          (typisch fuer Test-, GM- und Endgame-Objekte)
        - Test- und Entwicklerobjekte am Namen erkannt
    #>
    param([int]$Level)
    $maxIlvl = Get-AcMaxItemLevel $Level
    $parts = @(
        "ItemLevel <= $maxIlvl",
        "(RequiredLevel > 0 OR ItemLevel <= $($Level + 5))",
        "name NOT LIKE '%test%'",
        "name NOT LIKE '%QA %'",
        "name NOT LIKE '%deprecated%'",
        "name NOT LIKE '%(old)%'",
        "name NOT LIKE '%unused%'",
        "name NOT LIKE '%[PH]%'",
        "name NOT LIKE '%monster %'",
        "name NOT LIKE '%NPC %'",
        "name NOT LIKE '%[DEPRECATED]%'",
        "name <> ''"
    )
    return ('(' + ($parts -join ' AND ') + ')')
}

function Get-AcBestItemsForSlot {
    <#
      Kandidaten fuer einen Ausruestungsplatz, nach Punktwert sortiert.
      Beruecksichtigt Klassenkompetenz und Stufe wie der Server.
    #>
    param($Paths, $SlotDef, [int]$ClassId, [int]$Level, [hashtable]$Weights, [int]$Take = 3)
    $inv = ($SlotDef.Inv -join ', ')
    $where = @("InventoryType IN ($inv)", "RequiredLevel <= $Level", "Quality BETWEEN 1 AND 4",
               (Get-AcLevelAppropriateSql $Level))
    if ($ClassId -gt 0) {
        $mask = Get-AcClassMask $ClassId
        $where += "(AllowableClass = -1 OR AllowableClass & $mask)"
        $where += (Get-AcProficiencySql $ClassId $Level $SlotDef.Slot)
    }
    $sql = @"
SELECT $($script:AcItemColumns)
FROM acore_world.item_template
WHERE $($where -join ' AND ')
ORDER BY ItemLevel DESC
LIMIT 120;
"@
    $rows = @(Invoke-AcMySqlQuery $Paths $sql 'acore_world')
    $scored = New-Object Collections.Generic.List[object]
    foreach ($r in $rows) {
        $scored.Add([pscustomobject]@{ Item = $r; Score = (Get-AcItemScore $r $Weights) })
    }
    return @($scored | Sort-Object Score -Descending | Select-Object -First $Take)
}

function Get-AcAutoEquipPlan {
    <#
      Erstellt einen Vorschlag: je Platz das bestbewertete Item.
      Zweihandwaffen leeren die Schildhand, Ringe/Schmuck werden nicht doppelt vergeben.
      Hemd und Wappenrock bleiben unangetastet (rein optisch).
    #>
    param($Paths, [int]$ClassId, [int]$Level, [string]$Role)
    $weights = $script:AcRoleWeights[$Role]; if (-not $weights) { $weights = $script:AcRoleWeights['melee'] }
    $plan = New-Object Collections.Generic.List[object]
    $used = New-Object Collections.Generic.HashSet[string]
    $twoHander = $false
    foreach ($s in $script:AcEquipSlots) {
        if ($s.Slot -in @(3, 18)) { continue }               # Hemd, Wappenrock
        if ($s.Slot -eq 16 -and $twoHander) {
            $plan.Add([pscustomobject]@{ Slot = $s.Slot; Key = $s.Key; Item = $null; Score = 0; Clear = $true })
            continue
        }
        $cands = @(Get-AcBestItemsForSlot $Paths $s $ClassId $Level $weights 4)
        $pick = $null
        foreach ($c in $cands) {
            if ($used.Contains([string]$c.Item.entry)) { continue }   # Ringe/Schmuck nicht doppelt
            $pick = $c; break
        }
        if (-not $pick) { continue }
        [void]$used.Add([string]$pick.Item.entry)
        if ($s.Slot -eq 15) {
            $inv = 0; [void][int]::TryParse([string]$pick.Item.InventoryType, [ref]$inv)
            if ($inv -eq 17) { $twoHander = $true }
        }
        $plan.Add([pscustomobject]@{ Slot = $s.Slot; Key = $s.Key; Item = $pick.Item; Score = $pick.Score; Clear = $false })
    }
    return $plan
}

function Invoke-AcAutoEquip {
    # Setzt einen zuvor erstellten Plan um
    param($Paths, [int]$Guid, $Plan)
    $count = 0
    foreach ($p in $Plan) {
        $entry = 0
        if ($p.Item) { $entry = [int]$p.Item.entry }
        Set-AcCharacterItem $Paths $Guid ([int]$p.Slot) $entry
        $count++
    }
    return $count
}

# ---------------------------------------------------------------------
#  Charaktere exportieren und importieren
#
#  Mitgenommen werden Stammdaten, Ausruestung, erlernte Zauber, Fertigkeiten
#  und Talente. Bewusst NICHT: Taschen- und Bankinhalt, Post, Gilde, Freunde,
#  Erfolge und Quests - die haengen an Dingen, die es auf einem anderen Server
#  nicht gibt, und wuerden beim Import Fehler erzeugen.
# ---------------------------------------------------------------------

$script:AcCharExportVersion = 1

function Get-AcTableColumns {
    param($Paths, [string]$Database, [string]$Table)
    $sql = "SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '$Database' AND TABLE_NAME = '$Table';"
    return @(Invoke-AcMySqlQuery $Paths $sql | ForEach-Object { [string]$_.c })
}


function Export-AcCharacter {
    <#
      Schreibt einen Charakter als JSON-Datei.
    #>
    param($Paths, [int]$Guid, [string]$File)

    function Step-AcExport {
        # fuehrt einen Abschnitt aus und stellt dem Fehler seinen Namen voran
        param([string]$Name, [scriptblock]$Body)
        try { & $Body }
        catch {
            $ii = $_.InvocationInfo
            $at = ''
            try { $at = " (" + (Split-Path $ii.ScriptName -Leaf) + ":" + $ii.ScriptLineNumber + " -> " + ([string]$ii.Line).Trim() + ")" } catch {}
            throw ("[$Name] " + $_.Exception.Message + $at)
        }
    }

    $rows = @(Step-AcExport 'Character' { Invoke-AcMySqlQuery $Paths "SELECT * FROM characters WHERE guid = $Guid;" })
    if ($rows.Count -eq 0) { throw (T 'chr.notFound' @($Guid)) }
    $row = $rows[0]

    # Spalten, die auf dem Zielserver neu vergeben werden
    $skip = @('guid', 'account', 'online', 'totaltime', 'leveltime', 'logout_time', 'is_logout_resting',
              'instance_id', 'instance_mode_mask', 'guildid', 'deleteInfos_Account', 'deleteInfos_Name', 'deleteDate')
    $data = @{}
    foreach ($p in $row.PSObject.Properties) {
        if ($skip -contains $p.Name) { continue }
        $data[[string]$p.Name] = [string]$p.Value
    }

    $equip = @()
    # Abschnitte einzeln, damit Fehler zuzuordnen sind
    $sqlEq = @"
SELECT ci.slot, ii.itemEntry, ii.count, ii.durability, it.name
FROM character_inventory ci
JOIN item_instance ii ON ii.guid = ci.item
LEFT JOIN acore_world.item_template it ON it.entry = ii.itemEntry
WHERE ci.guid = $Guid AND ci.bag = 0 AND ci.slot < 19
ORDER BY ci.slot;
"@
    foreach ($e in @(Step-AcExport 'Equipment' { Invoke-AcMySqlQuery $Paths $sqlEq })) {
        $equip += ,@{ slot = [int]$e.slot; entry = [int]$e.itemEntry; count = [int]$e.count; name = [string]$e.name }
    }

    $spells = @(Step-AcExport 'Spells' { Invoke-AcMySqlQuery $Paths "SELECT spell FROM character_spell WHERE guid = $Guid;" } | ForEach-Object { [int]$_.spell })
    $skills = @()
    foreach ($s in @(Step-AcExport 'Skills' { Invoke-AcMySqlQuery $Paths "SELECT skill, value, max FROM character_skills WHERE guid = $Guid;" })) {
        $skills += ,@{ skill = [int]$s.skill; value = [int]$s.value; max = [int]$s.max }
    }
    $talents = @()
    foreach ($t in @(Step-AcExport 'Talents' { Invoke-AcMySqlQuery $Paths "SELECT spell, specMask FROM character_talent WHERE guid = $Guid;" })) {
        $talents += ,@{ spell = [int]$t.spell; specMask = [int]$t.specMask }
    }

    $inv  = @(Step-AcExport 'Inventory' { Get-AcCharacterInventory $Paths $Guid })
    $prog = Step-AcExport 'Progress' { Get-AcCharacterProgress $Paths $Guid }
    # Einfache Tabelle statt Objekt: Add-Member verweigert Felder als Wert
    # ("Die Argumenttypen stimmen nicht ueberein"), eine Tabelle nimmt sie klaglos.
    # Die Reihenfolge im JSON ist dadurch nicht festgelegt - beim Einlesen wird
    # ohnehin nach Namen zugegriffen.
    # Diagnose: falls hier etwas scheitert, steht im Protokoll, was die Werte sind
    foreach ($pair in @(@('data', $data), @('equip', $equip), @('inv', $inv), @('spells', $spells),
                        @('skills', $skills), @('talents', $talents), @('prog', $prog))) {
        $v = $pair[1]
        $tn = $(if ($null -eq $v) { '<null>' } else { $v.GetType().FullName })
        $cnt = ''
        try { if ($v -is [Array]) { $cnt = " Anzahl=" + $v.Length } } catch {}
        Write-AcLog ("Export-Typ " + $pair[0] + " = " + $tn + $cnt) 'INFO'
    }

    $doc = @{}
    $doc['generator']           = 'AzerothCore Server Manager'
    $doc['format']              = $script:AcCharExportVersion
    $doc['created']             = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $doc['character']           = $data
    foreach ($pair in @(@('equipment', $equip), @('inventory', $inv), @('spells', $spells),
                        @('skills', $skills), @('talents', $talents),
                        @('achievements', $prog.Achievements), @('achievementProgress', $prog.Progress),
                        @('reputation', $prog.Reputation), @('questsDone', $prog.QuestsDone))) {
        $key = [string]$pair[0]
        try {
            $val = $pair[1]
            if ($null -eq $val) { $val = @() }
            $doc[$key] = [object[]]@($val)
        } catch {
            Write-AcLog ("Export-Feld '" + $key + "' konnte nicht uebernommen werden: " + $_.Exception.Message) 'WARN'
            $doc[$key] = @()
        }
    }

    Step-AcExport 'Write' {
        $json = [string]($doc | ConvertTo-Json -Depth 6)
        [IO.File]::WriteAllText([string]$File, $json, (New-Object Text.UTF8Encoding($false)))
    } | Out-Null
    $charName = [string]$data['name']
    Write-AcLog (T 'chr.exported' @($charName, $equip.Count, @($spells).Count, $File))
    return @{ Name = $charName; Items = $equip.Count; Spells = @($spells).Count
              Bag = @($inv).Count; Achievements = @($prog.Achievements).Count; Quests = @($prog.QuestsDone).Count }
}

function Read-AcCharacterFile {
    param([string]$File)
    $raw = Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $raw.character) { throw (T 'chr.importBadFile') }
    return $raw
}

function Get-AcAccounts {
    <#
      Konten fuer die Auswahl beim Import, mit Anzahl der Charaktere. Bot-Konten
      werden ans Ende sortiert - gemeint ist fast immer ein echtes Konto.
    #>
    param($Paths, [string]$BotPrefix = '')
    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT id, username FROM acore_auth.account ORDER BY username LIMIT 2000;" 'acore_auth')
    $counts = @{}
    foreach ($c in @(Invoke-AcMySqlQuery $Paths "SELECT account, COUNT(*) AS n FROM characters GROUP BY account;")) {
        $counts[[int]$c.account] = [int]$c.n
    }
    $list = New-Object Collections.Generic.List[object]
    foreach ($r in $rows) {
        $id = [int]$r.id; $name = [string]$r.username
        $isBot = ($BotPrefix -and $name.ToUpper().StartsWith($BotPrefix.ToUpper()))
        $n = 0; if ($counts.ContainsKey($id)) { $n = $counts[$id] }
        $list.Add([pscustomobject]@{ Id = $id; Name = $name; Characters = $n; IsBot = $isBot })
    }
    return @($list | Sort-Object IsBot, Name)
}

function Test-AcCharacterNameFree {
    param($Paths, [string]$Name)
    $n = ConvertTo-AcSqlString $Name
    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT COUNT(*) AS n FROM characters WHERE name = '$n';")
    return ([int]$rows[0].n -eq 0)
}

function Import-AcCharacter {
    <#
      Legt den Charakter auf dem angegebenen Konto neu an. Die GUID wird neu
      vergeben, ebenso die GUIDs der Ausruestung.
    #>
    param($Paths, $Doc, [int]$AccountId, [string]$NewName)

    if (-not (Test-AcCharacterNameFree $Paths $NewName)) { throw (T 'chr.nameTaken' @($NewName)) }

    $maxRows = @(Invoke-AcMySqlQuery $Paths "SELECT IFNULL(MAX(guid), 0) + 1 AS g FROM characters;")
    $guid = [int]$maxRows[0].g

    # nur Spalten verwenden, die es auf diesem Server wirklich gibt
    $cols = @(Get-AcTableColumns $Paths 'acore_characters' 'characters')
    # Spaltennamen immer in Backticks: die Tabelle enthaelt Namen wie "order",
    # die in SQL reserviert sind und sonst einen Syntaxfehler ausloesen
    $names = New-Object Collections.Generic.List[string]
    $vals  = New-Object Collections.Generic.List[string]
    $names.Add('`guid`');    $vals.Add([string]$guid)
    $names.Add('`account`'); $vals.Add([string]$AccountId)
    $names.Add('`name`');    $vals.Add("'" + (ConvertTo-AcSqlString $NewName) + "'")
    $names.Add('`online`');  $vals.Add('0')
    $charFields = @{}
    if ($Doc.character -is [hashtable]) {
        foreach ($k in $Doc.character.Keys) { $charFields[[string]$k] = [string]$Doc.character[$k] }
    } else {
        foreach ($p in $Doc.character.PSObject.Properties) { $charFields[[string]$p.Name] = [string]$p.Value }
    }
    foreach ($k in $charFields.Keys) {
        if ($k -in @('guid', 'account', 'name', 'online')) { continue }
        if ($cols -notcontains $k) { continue }
        $v = [string]$charFields[$k]
        # Leere Werte auslassen: die Spalte bekommt dann ihren Standardwert.
        # Ein leerer Text in einer Zahlenspalte wuerde sonst abgelehnt.
        if ($v -eq '' -or $v -eq 'NULL') { continue }
        $names.Add('`' + $k + '`')
        $vals.Add("'" + (ConvertTo-AcSqlString $v) + "'")
    }
    # beim ersten Login neu einkleiden lassen, damit der Server die Werte berechnet
    $sql = "INSERT INTO characters (" + ($names -join ', ') + ") VALUES (" + ($vals -join ', ') + ");"
    Invoke-AcMySqlExec $Paths $sql

    foreach ($s in (Expand-AcList $Doc.spells))  { Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_spell (guid, spell, specMask) VALUES ($guid, $([int]$s), 255);" }
    foreach ($s in (Expand-AcList $Doc.skills))  { Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_skills (guid, skill, value, max) VALUES ($guid, $([int]$s.skill), $([int]$s.value), $([int]$s.max));" }
    foreach ($t in (Expand-AcList $Doc.talents)) { Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_talent (guid, spell, specMask) VALUES ($guid, $([int]$t.spell), $([int]$t.specMask));" }

    $items = 0
    foreach ($e in (Expand-AcList $Doc.equipment)) {
        try { Set-AcCharacterItem $Paths $guid ([int]$e.slot) ([int]$e.entry); $items++ }
        catch { Write-AcLog (T 'chr.importItemFailed' @([string]$e.name, $_.Exception.Message)) 'WARN' }
    }
    $prog = Merge-AcCharacterProgress $Paths $guid $Doc
    $bag = Add-AcCharacterInventory $Paths $guid (Expand-AcList $Doc.inventory)
    Write-AcLog (T 'chr.imported' @($NewName, $guid, $items))
    return @{ Guid = $guid; Items = $items; Bag = $bag.Placed; Mailed = $bag.Mailed
              Achievements = $prog.Ach; Quests = $prog.Quests }
}


function Merge-AcBitField {
    <#
      Verschmilzt ein Bitfeld aus der Exportdatei mit dem des Zielcharakters.
      Die Felder sind Listen aus Zahlen (durch Leerzeichen getrennt), jede Zahl
      traegt 32 Marken. Verodert wird Stelle fuer Stelle - so geht nichts
      verloren, was auf einem der beiden Server schon freigeschaltet war.
      Rueckgabe: Anzahl der hinzugekommenen Marken, oder $null bei Problemen.
    #>
    param($Paths, [int]$Guid, [string]$Field, [string]$Incoming)
    $rows = @(Invoke-AcMySqlQuery $Paths ("SELECT ``" + $Field + "`` AS v FROM characters WHERE guid = $Guid;"))
    if ($rows.Count -eq 0) { return $null }
    $cur = ([string]$rows[0].v).Trim()
    $new = $Incoming.Trim()
    if (-not $new) { return $null }
    $a = @($cur -split '\s+' | Where-Object { $_ -match '^\d+$' })
    $b = @($new -split '\s+' | Where-Object { $_ -match '^\d+$' })
    if ($b.Count -eq 0) { return $null }
    $len = [Math]::Max($a.Count, $b.Count)
    $out = New-Object Collections.Generic.List[string]
    $added = 0
    for ($i = 0; $i -lt $len; $i++) {
        $x = 0; $y = 0
        if ($i -lt $a.Count) { $x = [uint32]$a[$i] }
        if ($i -lt $b.Count) { $y = [uint32]$b[$i] }
        $or = [uint32]($x -bor $y)
        # neu hinzugekommene Bits zaehlen: was im Ergebnis steht, aber vorher fehlte
        $diff = [uint32]($or -bxor $x)
        while ($diff -ne 0) {
            if (($diff -band 1) -ne 0) { $added++ }
            $diff = [uint32]($diff -shr 1)
        }
        $out.Add([string]$or)
    }
    $value = ($out -join ' ') + ' '
    Invoke-AcMySqlExec $Paths ("UPDATE characters SET ``" + $Field + "`` = '" + (ConvertTo-AcSqlString $value) + "' WHERE guid = $Guid;")
    return $added
}

function Update-AcCharacterFromFile {
    <#
      Spielt eine Exportdatei auf einen VORHANDENEN Charakter zurueck.
      Ueberschrieben werden nur Stufe, Erfahrung, Geld, Aussehen, Zauber,
      Fertigkeiten, Talente und Ausruestung. Quests, Gilde, Freunde, Post,
      Erfolge, Taschen und Bank bleiben unberuehrt, weil sie in eigenen
      Tabellen liegen, die hier gar nicht angefasst werden.
    #>
    param($Paths, $Doc, [int]$Guid, [switch]$SkipTalents)

    $rows = @(Invoke-AcMySqlQuery $Paths "SELECT race, class, name FROM characters WHERE guid = $Guid;")
    if ($rows.Count -eq 0) { throw (T 'chr.notFound' @($Guid)) }
    $srcRace = 0; $srcClass = 0
    if ($Doc.character -is [hashtable]) {
        [void][int]::TryParse([string]$Doc.character['race'], [ref]$srcRace)
        [void][int]::TryParse([string]$Doc.character['class'], [ref]$srcClass)
    } else {
        [void][int]::TryParse([string]$Doc.character.race, [ref]$srcRace)
        [void][int]::TryParse([string]$Doc.character.class, [ref]$srcClass)
    }
    if ([int]$rows[0].race -ne $srcRace -or [int]$rows[0].class -ne $srcClass) {
        throw (T 'chr.updateMismatch' @((Get-AcRaceName $srcRace), (Get-AcClassName $srcClass),
                                        (Get-AcRaceName ([int]$rows[0].race)), (Get-AcClassName ([int]$rows[0].class))))
    }

    # Werte, die uebernommen werden - Name und Position bleiben beim Zielcharakter
    $fields = @('level', 'xp', 'money', 'skin', 'face', 'hairStyle', 'hairColor', 'facialStyle',
                'health', 'power1', 'power2', 'power3', 'power4', 'power5', 'power6', 'power7',
                'totalKills', 'todayKills', 'yesterdayKills', 'totalHonorPoints', 'arenaPoints',
                'equipmentCache', 'talentGroupsCount', 'activeTalentGroup')
    $cols = @(Get-AcTableColumns $Paths 'acore_characters' 'characters')
    $sets = New-Object Collections.Generic.List[string]
    $charFields = @{}
    if ($Doc.character -is [hashtable]) {
        foreach ($k in $Doc.character.Keys) { $charFields[[string]$k] = [string]$Doc.character[$k] }
    } else {
        foreach ($p in $Doc.character.PSObject.Properties) { $charFields[[string]$p.Name] = [string]$p.Value }
    }
    foreach ($f in $fields) {
        if ($cols -notcontains $f) { continue }
        if (-not $charFields.ContainsKey($f)) { continue }
        $v = [string]$charFields[$f]
        if ($v -eq '' -or $v -eq 'NULL') { continue }
        # Formatzeichenkette statt Verkettung: in doppelten Anfuehrungszeichen ist
        # der Backtick das Fluchtzeichen und wuerde verschluckt
        $sets.Add(('`{0}` = ''{1}''' -f $f, (ConvertTo-AcSqlString $v)))
    }
    if ($sets.Count -gt 0) {
        Invoke-AcMySqlExec $Paths ("UPDATE characters SET " + ($sets -join ', ') + " WHERE guid = $Guid;")
    }

    # Erkundete Gebiete, Flugpunkte und Titel VERSCHMELZEN statt ueberschreiben:
    # es sind Bitfelder, und der Zielcharakter kann Dinge kennen, die in der
    # Datei fehlen. Verodert bleibt beides erhalten.
    foreach ($f in @('exploredZones', 'taxi_path', 'knownTitles')) {
        if ($cols -notcontains $f) { continue }
        if (-not $charFields.ContainsKey($f) -or -not $charFields[$f]) { continue }
        $merged = Merge-AcBitField $Paths $Guid $f ([string]$charFields[$f])
        if ($merged -ne $null) { Write-AcLog (T 'chr.mergedField' @($f, $merged)) }
    }

    # Zauber und Fertigkeiten ergaenzen (nichts wegnehmen)
    foreach ($s in (Expand-AcList $Doc.spells)) { Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_spell (guid, spell, specMask) VALUES ($Guid, $([int]$s), 255);" }
    foreach ($s in (Expand-AcList $Doc.skills)) {
        Invoke-AcMySqlExec $Paths "INSERT INTO character_skills (guid, skill, value, max) VALUES ($Guid, $([int]$s.skill), $([int]$s.value), $([int]$s.max)) ON DUPLICATE KEY UPDATE value = VALUES(value), max = VALUES(max);"
    }
    # Talente ersetzen - eine Mischung aus zwei Skillungen waere unbrauchbar
    if (-not $SkipTalents) {
        Invoke-AcMySqlExec $Paths "DELETE FROM character_talent WHERE guid = $Guid;"
        foreach ($t in (Expand-AcList $Doc.talents)) { Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_talent (guid, spell, specMask) VALUES ($Guid, $([int]$t.spell), $([int]$t.specMask));" }
    }

    # Ausruestung ersetzen: erst alle Plaetze leeren, dann neu setzen
    for ($slot = 0; $slot -lt 19; $slot++) { Set-AcCharacterItem $Paths $Guid $slot 0 }
    $items = 0
    foreach ($e in (Expand-AcList $Doc.equipment)) {
        try { Set-AcCharacterItem $Paths $Guid ([int]$e.slot) ([int]$e.entry); $items++ }
        catch { Write-AcLog (T 'chr.importItemFailed' @([string]$e.name, $_.Exception.Message)) 'WARN' }
    }
    $prog = Merge-AcCharacterProgress $Paths $Guid $Doc
    $bag = Add-AcCharacterInventory $Paths $Guid (Expand-AcList $Doc.inventory)
    Write-AcLog (T 'chr.updatedFromFile' @([string]$rows[0].name, $Guid, $items))
    return @{ Guid = $Guid; Items = $items; Bag = $bag.Placed; Mailed = $bag.Mailed
              Achievements = $prog.Ach; Quests = $prog.Quests }
}

# ---------------------------------------------------------------------
#  Zusaetzliche Daten beim Charaktertransfer
#
#  Verschmolzen werden: Erfolge, Ruf, abgeschlossene Quests.
#  Angehaengt werden: Taschen-Gegenstaende - was nicht mehr hineinpasst,
#  geht per Post an den Charakter, damit nichts verlorengeht.
# ---------------------------------------------------------------------

$script:AcBackpackFirst = 23   # Rucksack: Plaetze 23 bis 38 (16 Stueck)
$script:AcBackpackLast  = 38


function Expand-AcList {
    <#
      Liefert immer ein flaches Feld. Loest dabei Listen auf, die faelschlich in
      einer weiteren Liste stecken (aeltere Exportdateien). Bewusst ohne .NET-Liste
      und vollstaendig abgesichert - hier ist schon zu viel schiefgegangen.
    #>
    param($Value)
    if ($null -eq $Value) { return @() }
    $out = @()
    try {
        foreach ($v in @($Value)) {
            if ($null -eq $v) { continue }
            $isList = $false
            try { $isList = ($v -is [object[]]) } catch {}
            if ($isList) {
                foreach ($inner in $v) { if ($null -ne $inner) { $out += ,$inner } }
            } else {
                $out += ,$v
            }
        }
    } catch {
        $tn = '<unbekannt>'
        try { $tn = $Value.GetType().FullName } catch {}
        Write-AcLog ("Expand-AcList (" + $tn + "): " + $_.Exception.Message) 'WARN'
        try { return @($Value) } catch { return @() }
    }
    return $out
}

function Get-AcCharacterInventory {
    <#
      Alle nicht getragenen Gegenstaende: Rucksack und Inhalt der Taschen.
      Die Spalte heisst in der Abfrage bewusst "amount" statt "count" - "count"
      kollidiert mit der eingebauten Count-Eigenschaft von PowerShell-Objekten.
    #>
    param($Paths, [int]$Guid)
    $sql = @"
SELECT ci.bag AS bagId, ci.slot AS slotId, ii.itemEntry AS entryId, ii.count AS amount, it.name AS itemName
FROM character_inventory ci
JOIN item_instance ii ON ii.guid = ci.item
LEFT JOIN acore_world.item_template it ON it.entry = ii.itemEntry
WHERE ci.guid = $Guid AND NOT (ci.bag = 0 AND ci.slot < 19)
ORDER BY ci.bag, ci.slot;
"@
    # Gleiches Muster wie bei der Ausruestung, das zuverlaessig funktioniert:
    # einfaches Feld, Zahlen ueber Mustervergleich statt [ref]-Umwandlung
    $list = @()
    foreach ($r in @(Invoke-AcMySqlQuery $Paths $sql)) {
        $entryText  = ([string]$r.entryId).Trim()
        $amountText = ([string]$r.amount).Trim()
        if ($entryText -notmatch '^\d+$') { continue }
        $entry = [int]$entryText
        if ($entry -le 0) { continue }
        $amount = 1
        if ($amountText -match '^\d+$') { $amount = [int]$amountText }
        if ($amount -lt 1) { $amount = 1 }
        $list += ,@{ entry = $entry; count = $amount; name = [string]$r.itemName }
    }
    return $list
}

function Get-AcCharacterProgress {
    <#
      Erfolge, Ruf und abgeschlossene Quests. Spalten werden in der Abfrage
      umbenannt, damit keine mit eingebauten Objektnamen kollidiert, und jede
      Zeile wird einzeln gelesen - eine kaputte Zeile darf den Export nicht kippen.
    #>
    param($Paths, [int]$Guid)

    function ConvertTo-AcInt { param($Value, [int]$Default = 0)
        $t = ([string]$Value).Trim()
        if ($t -match '^-?\d+$') { try { return [int]$t } catch { return $Default } }
        return $Default
    }
    function ConvertTo-AcLong { param($Value)
        $t = ([string]$Value).Trim()
        if ($t -match '^-?\d+$') { try { return [long]$t } catch { return [long]0 } }
        return [long]0
    }
    $ach = @()
    foreach ($r in @(Invoke-AcMySqlQuery $Paths "SELECT achievement AS achId, date AS achDate FROM character_achievement WHERE guid = $Guid;")) {
        $ach += ,@{ id = (ConvertTo-AcInt $r.achId); date = (ConvertTo-AcInt $r.achDate) }
    }

    $prg = @()
    foreach ($r in @(Invoke-AcMySqlQuery $Paths "SELECT criteria AS critId, counter AS critCounter, date AS critDate FROM character_achievement_progress WHERE guid = $Guid;")) {
        $prg += ,@{ criteria = (ConvertTo-AcInt $r.critId); counter = (ConvertTo-AcLong $r.critCounter); date = (ConvertTo-AcInt $r.critDate) }
    }

    $rep = @()
    foreach ($r in @(Invoke-AcMySqlQuery $Paths "SELECT faction AS facId, standing AS facStanding, flags AS facFlags FROM character_reputation WHERE guid = $Guid;")) {
        $rep += ,@{ faction = (ConvertTo-AcInt $r.facId); standing = (ConvertTo-AcInt $r.facStanding); flags = (ConvertTo-AcInt $r.facFlags) }
    }

    $quests = @()
    foreach ($r in @(Invoke-AcMySqlQuery $Paths "SELECT quest AS questId FROM character_queststatus_rewarded WHERE guid = $Guid;")) {
        $q = ConvertTo-AcInt $r.questId
        if ($q -gt 0) { $quests += $q }
    }

    $out = @{}
    $out['Achievements'] = $ach
    $out['Progress']     = $prg
    $out['Reputation']   = $rep
    $out['QuestsDone']   = $quests
    return $out
}

function Merge-AcCharacterProgress {
    <#
      Spielt Erfolge, Ruf und abgeschlossene Quests ein, ohne etwas zu entfernen.
      Bei Zaehlern und Rufwerten gewinnt der hoehere Wert.
    #>
    param($Paths, [int]$Guid, $Doc)
    $n = @{ Ach = 0; Rep = 0; Quests = 0 }
    if (-not $Doc) { return $n }
    foreach ($a in (Expand-AcList $Doc.achievements)) {
        Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_achievement (guid, achievement, date) VALUES ($Guid, $([int]$a.id), $([int]$a.date));"
        $n.Ach++
    }
    foreach ($p in (Expand-AcList $Doc.achievementProgress)) {
        Invoke-AcMySqlExec $Paths "INSERT INTO character_achievement_progress (guid, criteria, counter, date) VALUES ($Guid, $([int]$p.criteria), $([long]$p.counter), $([int]$p.date)) ON DUPLICATE KEY UPDATE counter = GREATEST(counter, VALUES(counter));"
    }
    foreach ($r in (Expand-AcList $Doc.reputation)) {
        Invoke-AcMySqlExec $Paths "INSERT INTO character_reputation (guid, faction, standing, flags) VALUES ($Guid, $([int]$r.faction), $([int]$r.standing), $([int]$r.flags)) ON DUPLICATE KEY UPDATE standing = GREATEST(standing, VALUES(standing));"
        $n.Rep++
    }
    foreach ($q in (Expand-AcList $Doc.questsDone)) {
        Invoke-AcMySqlExec $Paths "INSERT IGNORE INTO character_queststatus_rewarded (guid, quest, active) VALUES ($Guid, $([int]$q), 1);"
        $n.Quests++
    }
    return $n
}

function Get-AcFreeBackpackSlots {
    # Freie Plaetze im Rucksack (Taschen selbst werden nicht angefasst)
    param($Paths, [int]$Guid)
    $used = @(Invoke-AcMySqlQuery $Paths "SELECT slot FROM character_inventory WHERE guid = $Guid AND bag = 0 AND slot BETWEEN $($script:AcBackpackFirst) AND $($script:AcBackpackLast);" |
              ForEach-Object { [int]$_.slot })
    $free = @()   # einfaches Feld statt .NET-Liste
    for ($s = $script:AcBackpackFirst; $s -le $script:AcBackpackLast; $s++) {
        if ($used -notcontains $s) { $free.Add($s) }
    }
    return $free
}

function Send-AcItemsByMail {
    <#
      Schickt Gegenstaende per Post an den Charakter - der Weg, wenn die Taschen
      voll sind. Absender ist der Charakter selbst, damit kein fremder Verweis entsteht.
    #>
    param($Paths, [int]$Guid, $Items, [string]$Subject, [string]$Body)
    if (-not $Items -or @($Items).Count -eq 0) { return 0 }
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    $expire = $now + (30 * 24 * 3600)
    $sent = 0
    # Post fasst 12 Gegenstaende je Brief
    $chunks = @()
    $cur = New-Object Collections.Generic.List[object]
    foreach ($i in @($Items)) {
        $cur.Add($i)
        if ($cur.Count -eq 12) { $chunks += ,@($cur); $cur.Clear() }
    }
    if ($cur.Count -gt 0) { $chunks += ,@($cur) }

    foreach ($chunk in $chunks) {
        $subj = ConvertTo-AcSqlString $Subject
        $bdy  = ConvertTo-AcSqlString $Body
        $sql = @"
INSERT INTO mail (messageType, stationery, mailTemplateId, sender, receiver, subject, body,
                  has_items, expire_time, deliver_time, money, cod, checked)
VALUES (0, 41, 0, $Guid, $Guid, '$subj', '$bdy', 1, $expire, $now, 0, 0, 0);
"@
        Invoke-AcMySqlExec $Paths $sql
        $rows = @(Invoke-AcMySqlQuery $Paths "SELECT MAX(id) AS id FROM mail WHERE receiver = $Guid;")
        $mailId = [int]$rows[0].id
        foreach ($it in $chunk) {
            $itemGuid = New-AcItemInstance $Paths $Guid ([int]$it.entry) ([int]$it.count)
            if ($itemGuid -le 0) { continue }
            Invoke-AcMySqlExec $Paths "INSERT INTO mail_items (mail_id, item_guid, receiver) VALUES ($mailId, $itemGuid, $Guid);"
            $sent++
        }
    }
    return $sent
}

function Add-AcCharacterInventory {
    <#
      Legt mitgebrachte Gegenstaende in freie Rucksackplaetze. Was nicht mehr
      hineinpasst, geht per Post an den Charakter.
      Rueckgabe: @{ Placed; Mailed; Failed }
    #>
    param($Paths, [int]$Guid, $Items)
    $free = @(Get-AcFreeBackpackSlots $Paths $Guid)
    $placed = 0; $failed = 0
    $overflow = New-Object Collections.Generic.List[object]
    $idx = 0
    foreach ($it in @($Items)) {
        if ($idx -lt $free.Count) {
            try {
                $itemGuid = New-AcItemInstance $Paths $Guid ([int]$it.entry) ([int]$it.count)
                if ($itemGuid -le 0) { $failed++; continue }
                Invoke-AcMySqlExec $Paths "INSERT INTO character_inventory (guid, bag, slot, item) VALUES ($Guid, 0, $($free[$idx]), $itemGuid);"
                $placed++; $idx++
            } catch { Write-AcLog (T 'chr.importItemFailed' @([string]$it.name, $_.Exception.Message)) 'WARN'; $failed++ }
        } else {
            $overflow.Add($it)
        }
    }
    $mailed = 0
    if ($overflow.Count -gt 0) {
        try { $mailed = Send-AcItemsByMail $Paths $Guid @($overflow) (T 'chr.mailSubject') (T 'chr.mailBody') }
        catch { Write-AcLog (T 'chr.mailFailed' @($_.Exception.Message)) 'WARN'; $failed += $overflow.Count }
    }
    return @{ Placed = $placed; Mailed = $mailed; Failed = $failed }
}
