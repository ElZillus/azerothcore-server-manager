# Benutzerhandbuch (Deutsch)

*German user guide. The English version is the primary documentation: [USAGE.md](USAGE.md).*

Diese Anleitung führt dich vom leeren Windows-PC bis zum laufenden Server, auf dem du dich mit dem WoW-Client (3.3.5a) einloggen kannst. Danach folgt der tägliche Betrieb: starten, stoppen, updaten, Einstellungen ändern, Module installieren.

---

## Teil 0 – Was du brauchst

| | Mindestens | Empfohlen |
|---|---|---|
| Windows | 10 (Version 1809 oder neuer) oder 11, 64-Bit | Windows 11 |
| Freier Speicher | 25 GB | 40 GB (Build-Tools, Quellcode, Client-Daten, MySQL) |
| RAM | 8 GB | 16 GB |
| Internet | ja, ca. 8–10 GB Download | – |
| Zeit | 1–2 Stunden, davon 20–60 min reines Kompilieren | – |
| WoW-Client | Version 3.3.5a (Build 12340) | – |

Du brauchst **kein** Vorwissen zu Git, CMake oder MySQL. Alles wird automatisch installiert.

---

## Teil 1 – Installation

### Schritt 1: Dateien entpacken

1. `AzerothCore-Installer.zip` an einen beliebigen Ort entpacken (z.B. Downloads). Das ist nur das Werkzeug – der Server selbst kommt später in einen Ordner deiner Wahl.
2. Der entpackte Ordner enthält:
   - `Install-AzerothCore.bat` ← das startest du gleich
   - `AzerothCore-Installer.ps1`
   - `tools\` (Manager und Hilfsfunktionen)
   - `README.md`

### Schritt 2: Installer starten

1. Rechtsklick auf `Install-AzerothCore.bat` → **Als Administrator ausführen**.
   Falls du nur doppelklickst, fordert die Datei die Adminrechte selbst an – bestätige den Windows-Dialog mit **Ja**.
2. Erscheint eine blaue Warnung "Der Computer wurde durch Windows geschützt": auf **Weitere Informationen** → **Trotzdem ausführen** klicken. Das passiert bei jeder unsignierten Batch-Datei aus dem Internet.
3. Es öffnet sich das Fenster **AzerothCore 1-Klick-Installer**.

### Schritt 3: Einstellungen im Assistenten

Das Fenster fragt fünf Dinge ab:

**Installationsordner**
Standard ist `C:\AC`. Beibehalten oder über *Durchsuchen…* einen anderen Ordner wählen. Wichtig:
- kurzer Pfad, keine Leerzeichen (also **nicht** `C:\Users\Max\Meine Spiele\Server`) – der Compiler bricht sonst wegen zu langer Pfade ab
- nicht auf einem Netzlaufwerk oder in OneDrive

**Server-Variante**
- *Ohne Playerbots* → offizielles AzerothCore. Schneller gebaut, bekommt Updates zuerst.
- *Mit Playerbots* → Playerbot-Fork + Modul `mod-playerbots`. Bots laufen als Mitspieler durch die Welt, füllen Gruppen und Raids. Build dauert etwa doppelt so lang.

Die Entscheidung ist später nicht mehr umschaltbar, ohne neu zu installieren.

**Realm-Name**
Der Name, den du in der Realm-Liste im Client siehst. Frei wählbar, z.B. `Mein Server`.

**MySQL-Port**
Standard 3306. Der Installer prüft, ob der Port frei ist, und schlägt sonst 3307 vor. Wenn du bereits ein MySQL auf dem PC hast, ist das kein Problem – der Installer bringt sein eigenes portables MySQL mit und stört das andere nicht.

**Client-Daten**
- *Automatisch herunterladen* → fertig extrahierte Karten-Daten (dbc, maps, vmaps, mmaps) von GitHub, ca. 2 GB. Empfohlen.
- *Vorhandenen Datenordner verwenden* → nur, wenn du diese Daten schon irgendwo liegen hast.

Zum Schluss: Haken bei *Desktop-Verknüpfung anlegen* lassen.

### Schritt 4: Installation starten und warten

Auf **Installation starten** klicken. Das Fenster wechselt in die Fortschrittsansicht mit zehn Schritten:

| Schritt | Was passiert | Dauer |
|---|---|---|
| 1 Ordner vorbereiten | Ordnerstruktur und Start-Skripte anlegen | Sekunden |
| 2 Programme installieren | Git, CMake, OpenSSL, VC++-Redist, **Visual Studio 2022 Build Tools** per winget | 10–25 min |
| 3 Boost installieren | Boost-Bibliotheken herunterladen und still installieren | 3–5 min |
| 4 MySQL einrichten | MySQL entpacken, initialisieren, Datenbanken und Benutzer anlegen | 2 min |
| 5 Quellcode herunterladen | `git clone` des Cores (und ggf. mod-playerbots) | 2–5 min |
| 6 CMake konfigurieren | Build-Projekt erzeugen | 1–2 min |
| 7 Server kompilieren | Der große Brocken | **20–60 min** |
| 8 Client-Daten | Download + Entpacken | 5–15 min |
| 9 Datenbanken befüllen | `dbimport` spielt alle SQL-Dateien ein, Realm eintragen | 3–8 min |
| 10 Abschluss | MySQL herunterfahren, Verknüpfung anlegen | Sekunden |

Hinweise während des Wartens:
- Bei Schritt 2 sieht man während der Visual-Studio-Installation minutenlang **keine Ausgabe**. Das ist normal – nicht abbrechen.
- Bei Schritt 7 rauschen Tausende Zeilen mit `.cpp`-Dateinamen durch. Der PC ist währenddessen stark ausgelastet.
- Du kannst den PC in der Zeit normal weiterbenutzen, aber nicht in den Ruhezustand schicken.

### Schritt 5: Wenn etwas schiefgeht

Der Installer bleibt bei einem Fehler stehen und zeigt oben rot **Fehlgeschlagen: <Schritt>**. Unten im Log steht die Ursache (rote Zeilen).

1. Ursache beheben (siehe *Teil 5 – Problemlösung*).
2. **Erneut versuchen** klicken. Alle bereits erledigten Schritte werden übersprungen, es geht genau dort weiter.
3. Wenn du das Fenster geschlossen hast: `Install-AzerothCore.bat` erneut als Admin starten, denselben Ordner wählen, und im Dialog *Installation fortsetzen?* auf **Ja**.

Das komplette Protokoll liegt in `<Ordner>\logs\install.log`.

### Schritt 6: Fertig

Erscheint **Installation abgeschlossen!**, hast du zwei Möglichkeiten:
- **Server-Manager starten** → geht direkt weiter zu Teil 2
- **Schließen** → später über die Desktop-Verknüpfung *AzerothCore Manager* oder `<Ordner>\Start-Manager.bat`

---

## Teil 2 – Erster Start und erster Login

### Schritt 1: Server starten

1. Manager öffnen (Desktop-Verknüpfung oder `Start-Manager.bat`). **Keine** Adminrechte nötig.
2. Tab **Server** → Button **Server starten**.
3. Oben wechseln die drei Status-Anzeigen nacheinander:
   - `MySQL: startet` → `MySQL: läuft`
   - `Authserver: läuft`
   - `Worldserver: startet` → nach 1–3 Minuten `Worldserver: bereit`

Beim allerersten Start dauert der Worldserver länger, weil er die Welt-Datenbank lädt und noch ausstehende Datenbank-Updates einspielt.

Die schwarze Konsole zeigt die Ausgabe aller drei Programme farbig gemischt (`[mysql]` grau, `[auth]` hellblau, Worldserver weiß).

### Schritt 2: Account anlegen

1. Warten bis `Worldserver: bereit`.
2. Button **Account anlegen** (unten rechts).
3. Accountname und Passwort eingeben, Haken *GM-Rechte (Level 3)* setzen, falls es ein Gamemaster sein soll, und mit **Anlegen** bestätigen.
4. In der Konsole erscheint die Bestätigung des Worldservers.

Oder direkt in die Befehlszeile unten tippen:
```
account create spielername passwort
```

### Schritt 3: Client verbinden

1. Im WoW-3.3.5a-Ordner die Datei `realmlist.wtf` mit einem Texteditor öffnen (meist in `Data\enUS\` oder `Data\deDE\`).
2. Inhalt ersetzen durch:
   ```
   set realmlist 127.0.0.1
   ```
3. Speichern. `Wow.exe` starten (nicht den Launcher), einloggen, Realm auswählen, Charakter erstellen.

### Schritt 4: Server sauber beenden

**Immer** über den Manager stoppen, nie das Fenster einfach zumachen oder den Task killen:

- Button **Server sicher stoppen** → der Worldserver bekommt den Befehl `server shutdown 1`, speichert alle Charaktere, fährt herunter. Danach Authserver, dann MySQL. Dauert 5–30 Sekunden.
- Schließt du den Manager mit laufendem Server, fragt er nach: *Ja* = sicher stoppen und beenden.

Warum das wichtig ist: Charakterdaten werden im Speicher gehalten und nur periodisch geschrieben. Ein hartes Beenden kann Fortschritt der letzten Minuten kosten oder Tabellen beschädigen.

---

## Teil 3 – Täglicher Betrieb

### Server-Tab im Überblick

| Element | Funktion |
|---|---|
| Server starten / sicher stoppen / Neu starten | Alle drei Dienste in der richtigen Reihenfolge |
| Worldserver nach Absturz automatisch neu starten | Wenn der Worldserver mit Fehler abbricht, startet er nach 5 s neu |
| Konsole | Live-Ausgabe, farbig nach Herkunft |
| Befehlszeile + Senden | Beliebige Worldserver-Befehle (Enter-Taste geht auch) |
| Account anlegen | Dialog für `account create`, mit optionalem Haken für `account set gmlevel` |

Nützliche Konsolenbefehle (ohne Punkt davor):
```
account create NAME PASSWORT       Account anlegen
account set gmlevel NAME 3 -1      GM-Rechte auf allen Realms
account set password NAME PW PW    Passwort setzen
server shutdown 300                In 5 Minuten herunterfahren (Spieler sehen Countdown)
server shutdown cancel             Abbrechen
reload config                      worldserver.conf neu laden ohne Neustart
announce TEXT                      Nachricht an alle Spieler
```

### Einstellungen ändern (Tab **Einstellungen**)

1. Oben im Dropdown die Datei wählen:
   - `worldserver.conf` – fast alles Spielrelevante (XP-Raten, Drop-Raten, Anzahl Spieler, Startlevel, …)
   - `authserver.conf` – Login-Server, selten nötig
   - `dbimport.conf` – Datenbank-Updater
   - `modules\*.conf` – eine Datei pro installiertem Modul
2. Im Suchfeld tippen, z.B. `Rate.XP` → die Tabelle filtert live. Es wird auch in den Beschreibungen gesucht.
3. Auf den Wert in der rechten Spalte klicken, neuen Wert eintragen, Enter. Die Zelle wird gelb.
4. Unten im grauen Feld steht die Original-Erklärung aus der Datei inklusive Standardwert und erlaubten Werten.
5. **Speichern**. Es werden nur die geänderten Zeilen geschrieben, Kommentare bleiben erhalten.
6. Damit die Änderung wirkt: Server neu starten, oder für viele `worldserver.conf`-Werte reicht `reload config` in der Konsole.

Häufige Werte:

| Einstellung | Bedeutung | Standard |
|---|---|---|
| `Rate.XP.Kill`, `Rate.XP.Quest`, `Rate.XP.Explore` | XP-Multiplikator | 1 |
| `Rate.Drop.Item.*`, `Rate.Drop.Money` | Loot-Multiplikator | 1 |
| `PlayerLimit` | Max. gleichzeitige Spieler | 1000 |
| `StartPlayerLevel`, `StartPlayerMoney` | Startwerte neuer Charaktere | 1 / 0 |
| `GM.LoginState` | GM-Modus beim Login (0 aus, 1 an, 2 wie zuletzt) | 2 |
| `MotdText` | Nachricht des Tages | – |

Bei der Playerbots-Variante steckt alles zu den Bots in `modules\playerbots.conf`, z.B. `AiPlayerbot.MinRandomBots` / `MaxRandomBots` (Anzahl Bots) und `AiPlayerbot.RandomBotAutologin`.

### Server aktualisieren (Tab **Update**)

AzerothCore bekommt fast täglich Commits. Der Manager prüft beim Start automatisch und färbt den Tab-Titel zu **Update (!)**, wenn etwas Neues da ist.

1. Tab **Update** → **Nach Updates suchen**. Die Liste zeigt Core und jedes Git-Modul mit lokalem Stand, Remote-Stand und Anzahl fehlender Commits.
2. Haken *Server nach Update automatisch starten* nach Wunsch – standardmäßig aus, damit du vorher ins Log schauen kannst.
3. **Update Server** klicken. Läuft der Server, fragt der Manager, ob er ihn sicher stoppen darf.
4. Ablauf (alles automatisch, im Log verfolgbar):
   1. Eingebundene Modul-SQL-Kopien entfernen
   2. `git pull` für Core und alle Module
   3. Modul-SQL prüfen und neu einbinden
   4. CMake neu konfigurieren
   5. Kompilieren (10–40 min, nur geänderte Dateien)
   6. `dbimport` spielt neue Datenbank-Updates ein
   7. optional Server starten
5. Titelzeile zeigt währenddessen den aktuellen Schritt. Fertig-Meldung im Log: `=== Fertig ===`.

**Nur neu kompilieren** macht dasselbe ohne `git pull` – nötig nach dem Hinzufügen oder Entfernen von Modulen.

Bei einem Fehler beim Kompilieren steht die Ursache im Update-Log (rote Zeilen, meist ein `error C....`). Das passiert am ehesten, wenn ein Modul nicht zum neuesten Core-Stand passt – dann das Modul selbst updaten oder vorübergehend entfernen.

### Module installieren (Tab **Module**)

Module sind Erweiterungen (NPC-Buffer, AH-Bot, Transmog, Solocraft, …). Übersicht: https://www.azerothcore.org/catalogue.html

**Variante A – per Drag & Drop**
1. Auf GitHub beim Modul auf **Code → Download ZIP**.
2. Die ZIP-Datei aus dem Explorer auf das Feld *Modul hier ablegen* im Manager ziehen. Ein Ordner geht genauso.
3. Der Manager entpackt nach `source\modules\`, entfernt den `-master`-Anhang, prüft ob es überhaupt ein Modul ist, und analysiert die SQL-Dateien (siehe unten).

**Variante B – per Git-URL** (empfohlen, weil dann Updates mitkommen)
1. Auf GitHub die URL kopieren, z.B. `https://github.com/azerothcore/mod-transmog.git`
2. In das Feld *Oder Git-URL* einfügen → **Aus Git hinzufügen**.

**Danach in beiden Fällen:**
1. Unten erscheint rot: *Module wurden geändert. Bitte "Neu kompilieren" ausführen.* Die Spalte *Kompiliert* zeigt *ausstehend*.
2. Optional weitere Module hinzufügen – Kompilieren lohnt sich gesammelt.
3. **Neu kompilieren (Module übernehmen)** → gleicher Ablauf wie beim Update, nur ohne Pull.
4. Nach dem Build liegt die Konfigurationsdatei des Moduls unter *Einstellungen → modules\…conf*. Viele Module müssen dort erst mit `…Enable = 1` eingeschaltet werden.

**Modul entfernen:** Modul in der Liste markieren → **Modul entfernen** → **Neu kompilieren**. Die Datenbank-Tabellen des Moduls bleiben stehen; das stört nicht.

### Modul-SQL verstehen (Spalte *SQL-Dateien*)

Viele Module bringen SQL-Dateien mit (neue NPCs, Items, Tabellen). AzerothCore spielt die nur dann automatisch ein, wenn sie in einem bestimmten Ordner liegen. Der Manager kümmert sich darum und zeigt in der Modul-Liste, was Sache ist:

| Anzeige | Bedeutung | Was du tun musst |
|---|---|---|
| `keine` | Modul hat kein SQL | nichts |
| `3 automatisch` | liegen schon im richtigen Ordner | nichts |
| `2 eingebunden` | lagen im alten Layout, der Manager hat Kopien im richtigen Ordner angelegt | nichts |
| `1 optional` | Zusatzinhalte, die der Autor bewusst nicht automatisch einspielt | bei Bedarf manuell importieren |
| `1 unklar` (rot) | Ziel-Datenbank nicht erkennbar | manuell zuordnen |

Für die letzten beiden Fälle: Modul markieren → **SQL-Dateien prüfen / einbinden…**:
1. Die Liste zeigt jede Datei mit Status und Ziel-Datenbank.
2. Dateien ankreuzen, die du importieren willst.
3. Links im Dropdown ggf. die Ziel-Datenbank vorgeben (bei *unklar*). Faustregel: Items, NPCs, Quests, Spells → `acore_world`; alles was pro Charakter gespeichert wird → `acore_characters`; Accounts → `acore_auth`.
4. **Markierte jetzt importieren**. Der Manager startet MySQL bei Bedarf selbst.

Die README des Moduls auf GitHub sagt meist, welche optionalen SQL-Dateien wozu dienen.

Eingespielt werden *automatische* und *eingebundene* Dateien beim nächsten **Neu kompilieren** / **Update Server** durch `dbimport`. Das musst du nicht anstoßen.

### Module konfigurieren (Tab **Module** → *Modul konfigurieren…*)

Jedes Modul bringt seine eigene `.conf` mit. Modul markieren → *Modul konfigurieren…* öffnet genau diese Datei mit Suchfeld, Beschreibungstext und Speichern-Knopf – dasselbe wie im Einstellungen-Tab, nur direkt am Modul.

Manche Module brauchen eine Charakter-GUID. Beim **AH-Bot** legst du dafür zuerst einen normalen Charakter an (der später den Auktionshandel führt), und trägst dessen GUID in die Konfiguration ein. Dafür gibt es im Dialog den Knopf *Charakter auswählen…*: Zeile in der Tabelle markieren, Knopf drücken, Charakter aus der Liste wählen – der Manager setzt je nach Feldname automatisch GUID, Name oder Accountnamen ein. Die GUID findest du sonst nur per Datenbankabfrage.

Nach Änderungen: Server neu starten, oder in der Konsole `reload config` (wirkt nicht bei allen Modul-Einstellungen).

### Charaktere bearbeiten (Tab **Charaktere**)

Zeigt alle Charaktere echter Accounts. Zufallsbots werden ausgeblendet – erkannt am Account-Präfix aus `playerbots.conf` (`AiPlayerbot.RandomBotAccountPrefix`, Standard `rndbot`). Deine eigenen Zweitcharaktere bleiben sichtbar, auch wenn sie als Alt-Bot mitlaufen. Mit dem Haken *Bot-Accounts mitanzeigen* siehst du alles.

Rechts erscheint der gewählte Charakter mit seinen 19 Ausrüstungsplätzen (Item-Namen in Qualitätsfarben) und darunter eine Tabelle mit allen änderbaren Werten: Name, Stufe, Erfahrung, Geld, Leben, Mana/Wut/Energie/Runenmacht, Aussehen, Ehre, Arenapunkte, Position und `at_login`-Flags.

**Ausrüstung ändern:** Auf einen Platz klicken → Item-Auswahl. Die Liste kommt direkt aus `item_template` deiner Weltdatenbank und ist auf den Platz gefiltert. Der Haken *Nur Items, die diese Klasse anlegen kann* bildet die Kompetenzprüfung des Servers nach: Rüstungsart (Stoff/Leder/Kette/Platte, Kette und Platte erst ab Stufe 40), Schilde, Klassenrelikte wie Idole und Totems, erlaubte Waffentypen sowie beidhändiges Kämpfen für die Schildhand. Ohne diesen Haken siehst du alles – dann kann aber ein Item dabei sein, das der Server beim nächsten Login ablehnt, wodurch der Platz leer bleibt. *Anlegen* setzt das Item, *Platz leeren* entfernt es. Der Manager legt dabei die nötige Zeile in `item_instance` an, verknüpft sie in `character_inventory` und aktualisiert den `equipmentCache`, damit das Item auch in der Charakterauswahl erscheint.

**Wichtige Regeln, die der Manager erzwingt:**
- Ein **eingeloggter** Charakter wird nicht angefasst – der Server würde die Änderungen beim Ausloggen überschreiben.
- **Ausrüstung** lässt sich nur bei **gestopptem Worldserver** ändern, weil der laufende Server eigene Item-IDs vergibt und es sonst zu doppelten IDs kommt. Werte wie Stufe oder Geld dürfen auch bei laufendem Server geändert werden, solange der Charakter offline ist.

**Was sich nicht ändern lässt und warum:** Stärke, Beweglichkeit, Ausdauer und ähnliche Attribute stehen nicht in der Datenbank. Der Server berechnet sie beim Einloggen aus Stufe, Klasse, Talenten und Ausrüstung neu. Ebenso wird die maximale Lebens- und Manamenge berechnet – die Felder *Leben* und *Mana* sind die aktuellen Werte beim Ausloggen. Wer echte Attributänderungen will, braucht ein Server-Modul oder Items mit den passenden Werten.

### Server im LAN oder Internet freigeben (Tab **Info**)

Standardmäßig ist der Server nur vom eigenen PC erreichbar. Für andere:

1. Tab **Info** → Feld *Realm-Adresse* → LAN-IP deines PCs eintragen (z.B. `192.168.178.20`, herausfinden mit `ipconfig`) bzw. öffentliche IP / DynDNS-Name für Internet → **Setzen**.
2. Worldserver neu starten.
3. Windows-Firewall: eingehende Regeln für `authserver.exe` und `worldserver.exe` erlauben (Windows fragt beim ersten Start meist selbst).
4. Für Internet zusätzlich im Router die Ports **3724** (TCP, Login) und **8085** (TCP, Welt) auf deinen PC weiterleiten.
5. Mitspieler tragen in ihrer `realmlist.wtf` deine IP ein.

MySQL selbst bleibt immer auf `127.0.0.1` und ist von außen nicht erreichbar.

---

## Teil 4 – Ordner, Backup, Wartung

### Was wo liegt

```
C:\AC\
├─ Start-Manager.bat                Manager starten
├─ Resume-Installation.bat  Installation fortsetzen / reparieren
├─ ac-settings.json                 Variante, Ports, Datenbank-Passwörter
├─ source\                          Quellcode (Git-Repository)
│  └─ modules\                      alle Module, je ein Ordner
├─ build\bin\RelWithDebInfo\        worldserver.exe, authserver.exe, dbimport.exe
│  └─ configs\                      worldserver.conf, authserver.conf, dbimport.conf
│     └─ modules\                   eine .conf pro Modul
├─ data\                            dbc, maps, vmaps, mmaps
├─ mysql\
│  └─ data\                         ← DIE DATENBANK: Accounts, Charaktere, Welt
├─ deps\                            Boost, Downloads (kann nach der Installation weg, ~5 GB)
├─ logs\                            install.log, manager.log, Server.log, DBErrors.log
└─ tools\                           die Skripte
```

### Backup

Bei **gestopptem Server** reichen zwei Ordner: `mysql\data\` (alle Spielstände) und `build\bin\RelWithDebInfo\configs\` (deine Einstellungen). Einfach kopieren. Wiederherstellen = zurückkopieren, ebenfalls bei gestopptem Server.

Für ein Backup im laufenden Betrieb: MySQL-Dump über die Kommandozeile
```
C:\AC\mysql\bin\mysqldump.exe --defaults-extra-file=C:\AC\mysql\client.cnf --databases acore_auth acore_characters acore_world > backup.sql
```

### Passwörter

Der Installer erzeugt zufällige Passwörter für MySQL-`root` und den Datenbankbenutzer `acore`. Beide stehen im Klartext in `ac-settings.json` (und `mysql\client.cnf`). Du brauchst sie nur, wenn du mit einem externen Tool wie HeidiSQL oder Keira3 in die Datenbank willst: Host `127.0.0.1`, Port aus der Datei, Benutzer `acore`, Passwort `DbPassword`.

### Speicherplatz freigeben

Nach erfolgreicher Installation kann `deps\downloads\` gelöscht werden (Boost-Installer, MySQL-ZIP, Client-Daten-ZIP). `deps\boost_*` muss bleiben, das braucht jeder spätere Build.

---

## Teil 5 – Problemlösung

**Ich habe eine neue Version der Skripte bekommen – wohin damit?**
Der Manager läuft aus `<Ordner>\tools\` (z.B. `C:\AC\tools\`), nicht aus dem Download-Ordner. Neue `.ps1`-Dateien also dorthin kopieren und den Manager neu starten. Die Versionsnummer steht in der Titelleiste des Managers und im Tab *Info*. Alternativ `Resume-Installation.bat` aus dem neuen Download-Ordner starten: der Vorbereitungsschritt kopiert die Werkzeuge bei jedem Lauf frisch.

**"winget wurde nicht gefunden"**
Windows ist zu alt oder der *App-Installer* fehlt. Microsoft Store öffnen → nach *App Installer* suchen → installieren (oder Windows-Update ausführen). Danach *Resume-Installation.bat*.

**Schritt 2 hängt ewig ohne Ausgabe**
Visual Studio Build Tools installieren im Hintergrund mehrere GB. Im Task-Manager sieht man `setup.exe` / `vs_installer` arbeiten. 30 Minuten sind bei langsamer Leitung normal.

**"OpenSSL … wurde nicht gefunden und konnte nicht über winget installiert werden"**
Microsoft benennt die winget-Pakete gelegentlich um; der Installer probiert mehrere Namen durch. Klappt keiner: https://slproweb.com/products/Win32OpenSSL.html öffnen, **Win64 OpenSSL v3.x.x** herunterladen – ausdrücklich **nicht** die *Light*-Variante, die enthält keine Header und keine `.lib`-Dateien – installieren, dabei *The OpenSSL binaries (/bin) directory* wählen. Dann im Installer **Erneut versuchen**.
Ist OpenSSL installiert, wird aber trotzdem nicht gefunden: Umgebungsvariable `OPENSSL_ROOT_DIR` auf den Installationsordner setzen (der Ordner mit `include\` und `lib\`) und den Installer neu starten.

**Hinweis "AzerothCore ist auf die OpenSSL-3.x-Reihe ausgelegt"**
winget liefert inzwischen auch OpenSSL 4.x aus. Der Installer wählt automatisch die neueste 3.x-Version, wenn es eine gibt. Steht nur 4.x zur Verfügung, wird sie genommen und du bekommst diesen Hinweis – bricht CMake oder das Kompilieren später mit OpenSSL-Fehlern ab, installiere eine 3.x von slproweb.com und trage den Pfad in `ac-settings.json` unter `OpenSslRoot` ein.

**"MySQL konnte weder heruntergeladen noch über winget installiert werden"**
Oracles Download-Server blockt gelegentlich automatisierte Downloads (Fehler 403). Der Installer probiert nacheinander: aktuelle Version von der Downloadseite ermitteln → Download → winget (`Oracle.MySQL`) → manuelles Archiv. Für den manuellen Weg: https://dev.mysql.com/downloads/mysql/8.4.html öffnen, **Windows (x86, 64-bit), ZIP Archive** (~250 MB, nicht die Debug-Variante) herunterladen – unten auf *No thanks, just start my download* klicken, kein Konto nötig – und die Datei unverändert nach `<Ordner>\deps\downloads\` legen. Dann **Erneut versuchen**; der Installer erkennt das Archiv am Namen.

**"Visual Studio 2022 (C++-Werkzeuge) wurde nicht gefunden" nach Schritt 2**
Die winget-Installation ist fehlgeschlagen oder wurde blockiert. Manuell: https://visualstudio.microsoft.com/de/downloads/ → *Build Tools für Visual Studio 2022* → im Installer die Workload **Desktopentwicklung mit C++** wählen. Dann Installer erneut ausführen.

**Kompilieren bricht mit `error C1083` / `LNK1104` / "Pfad zu lang" ab**
Ordnerpfad zu lang oder mit Leerzeichen. Neu mit `C:\AC` installieren.

**Kompilieren bricht mit `error C2xxx` in einem Modul ab**
Das Modul passt nicht zum aktuellen Core-Stand. Modul entfernen → Neu kompilieren. Auf GitHub beim Modul nach Issues/Forks mit Fix schauen.

**Port 3306 belegt**
Anderes MySQL/MariaDB/XAMPP läuft. Im Installer einfach 3307 nehmen.

**Worldserver bleibt bei "startet" hängen / beendet sich sofort**
In der Konsole nach oben scrollen, die erste rote oder `ERROR`-Zeile lesen. Typisch:
- `Unable to connect to database` → MySQL läuft nicht (Status oben prüfen) oder Passwort in `worldserver.conf` weicht von `ac-settings.json` ab
- `Map file '...' does not exist` / `vmaps` / `mmaps` → Client-Daten fehlen; prüfen ob `data\maps` usw. gefüllt sind, sonst Installer erneut ausführen (Schritt 8 wird nachgeholt)
- `Your database structure is not up to date` → `Nur neu kompilieren` ausführen, das ruft `dbimport` auf
- `Applying of file '...sql' failed` → eine SQL-Datei (meist von einem Modul) ist fehlerhaft; Datei und Fehler stehen in `logs\DBErrors.log`

**Client: "Verbindung zum Server kann nicht hergestellt werden"**
1. Steht `Worldserver: bereit`?
2. `realmlist.wtf` wirklich gespeichert und richtige Sprachversion (`enUS`/`deDE`)?
3. Bei LAN: Realm-Adresse (Tab Info) auf die LAN-IP gesetzt und Firewall offen?

**Client: Realm-Liste ist leer**
Realm-Adresse zeigt auf eine IP, die der Client nicht erreicht. Für den eigenen PC muss dort `127.0.0.1` stehen.

**Manager: "Der Server läuft und muss gestoppt werden" beim Update, aber nichts läuft**
Ein Worldserver-Prozess hängt noch aus einer früheren Sitzung. Task-Manager → `worldserver.exe` beenden → nochmal.

**Ich habe Einstellungen zerschossen**
Die Original-Vorlage liegt daneben als `.conf.dist`. Datei löschen, `Nur neu kompilieren` → der Manager legt sie aus der Vorlage neu an und trägt Datenbank + Pfade wieder ein.

**Alles kaputt, ich will von vorne anfangen, aber Charaktere behalten**
1. Server stoppen. `mysql\data\` woanders hin kopieren.
2. Ordner `C:\AC` löschen, neu installieren.
3. Server einmal starten (damit die Datenbanken existieren) und wieder stoppen.
4. Kopierte `mysql\data\` zurückkopieren – **aber** `ac-settings.json` und `mysql\client.cnf` müssen zum alten Root-Passwort passen. Einfacher: nur die drei Datenbanken per `mysqldump` sichern (siehe Backup) und in die neue Installation einspielen.

---

## Kurzreferenz

| Ich will … | … also |
|---|---|
| spielen | Manager → Server starten → warten auf *bereit* → Client |
| aufhören | Manager → Server sicher stoppen |
| einen Account | Manager → Account anlegen |
| XP-Rate ändern | Einstellungen → worldserver.conf → `Rate.XP` → Speichern → `reload config` |
| updaten | Update → Nach Updates suchen → Update Server |
| ein Modul | Module → ZIP reinziehen oder Git-URL → Neu kompilieren → Modul konfigurieren… |
| einen Charakter bearbeiten | Charaktere → auswählen → Werte ändern oder Ausrüstungsplatz anklicken |
| Sprache oder Design umstellen | Einstellungen → unten *Sprache / Language* bzw. *Design* (Standard ist Englisch/Hell) |
| Freunde einladen | Info → Realm-Adresse → Firewall/Router-Ports 3724 + 8085 |
| Backup | Server stoppen → `mysql\data` + `configs` kopieren |
