# User guide

Step by step from an empty Windows PC to a running server, and then through daily operation.
*Diese Anleitung gibt es auch auf [Deutsch](USAGE.de.md).*

---

## Part 0 – What you need

| | Minimum | Recommended |
|---|---|---|
| Windows | 10 (version 1809 or newer) or 11, 64-bit | Windows 11 |
| Free disk space | 25 GB | 40 GB (build tools, source, client data, MySQL) |
| RAM | 8 GB | 16 GB |
| Internet | yes, roughly 8–10 GB of downloads | – |
| Time | 1–2 hours, of which 20–60 minutes is compiling | – |
| WoW client | version 3.3.5a (build 12340) | – |

No prior knowledge of Git, CMake or MySQL is required. Everything is installed for you.

---

## Part 1 – Installation

### Step 1: Unpack

1. Unpack the download anywhere you like. This is only the tool — the server itself goes into a folder of your choosing later.
2. The folder contains:
   - `Install-AzerothCore.bat` ← this is what you start
   - `AzerothCore-Installer.ps1`
   - `tools\` (manager and shared functions)
   - `README.md`

### Step 2: Start the installer

1. Right-click `Install-AzerothCore.bat` → **Run as administrator**.
   A plain double-click also works — the file requests the rights itself, confirm the Windows prompt with **Yes**.
2. If a blue "Windows protected your PC" notice appears: **More info** → **Run anyway**. This happens with any unsigned batch file from the internet.
3. The **AzerothCore One-Click Installer** window opens.

### Step 3: Settings in the wizard

The window asks for five things:

**Installation folder**
`C:\AC` by default. Keep it or pick another one via *Browse…*. Important:
- short path, no spaces (so **not** `C:\Users\Max\My Games\Server`) — otherwise the compiler fails on path length
- not on a network drive and not inside OneDrive

**Server variant**
- *Without playerbots* → official AzerothCore. Faster to build, receives upstream changes first.
- *With playerbots* → playerbot fork plus the `mod-playerbots` module. Bots roam the world as fellow players, fill groups and raids. The build takes roughly twice as long.

This choice cannot be switched later without reinstalling.

**Realm name**
The name shown in the realm list in the client. Anything you like, e.g. `My Server`.

**MySQL port**
3306 by default. The installer checks whether the port is free and suggests 3307 otherwise. An existing MySQL on the machine is no problem — the installer brings its own portable instance and leaves yours alone.

**Client data**
- *Download automatically* → prebuilt map data (dbc, maps, vmaps, mmaps) from GitHub, about 2 GB. Recommended.
- *Use an existing data folder* → only if you already have this data somewhere.

Finally, leave *Create a desktop shortcut* ticked.

### Step 4: Start and wait

Press **Start installation**. The window switches to the progress view with ten steps:

| Step | What happens | Duration |
|---|---|---|
| 1 Preparing folders | Folder structure and launcher scripts | seconds |
| 2 Installing programs | Git, CMake, OpenSSL, VC++ redist, **Visual Studio 2022 Build Tools** | 10–25 min |
| 3 Installing Boost | Download and silent install | 3–5 min |
| 4 Setting up MySQL | Unpack, initialise, create databases and users | 2 min |
| 5 Downloading source | `git clone` of the core (and mod-playerbots) | 2–5 min |
| 6 Configuring CMake | Generate the build project | 1–2 min |
| 7 Building the server | The long part | **20–60 min** |
| 8 Client data | Download and extract | 5–15 min |
| 9 Populating databases | `dbimport` applies all SQL, realm registered | 3–8 min |
| 10 Finishing up | Shut down MySQL, create shortcut, clean up | seconds |

While you wait:
- During step 2 the Visual Studio installation produces **no output for several minutes**. That is normal — do not abort.
- During step 7 thousands of `.cpp` file names scroll past. The machine is under heavy load.
- You can keep using the PC, but do not let it sleep.

**Where things come from:** the installer prefers `winget` and falls back to direct downloads from the original sources if `winget` is missing or a package fails. Git, CMake and OpenSSL then land inside the server folder (`deps\`); only the Visual Studio Build Tools are always installed system-wide.

### Step 5: When something goes wrong

The installer stops and shows **Failed: \<step\>** in red. The cause is in the log below (red lines).

1. Fix the cause (see *Part 5 – Troubleshooting*).
2. Press **Try again**. Completed steps are skipped, it resumes exactly where it stopped.
3. If you closed the window: run `Install-AzerothCore.bat` as administrator again, choose the same folder, and answer **Yes** to *Resume installation?*.

The full log is in `<folder>\logs\install.log`.

### Step 6: Done

Once **Installation complete!** appears you can either press **Open server manager** or close the window and start it later from the desktop shortcut or `<folder>\Start-Manager.bat`.

---

## Part 2 – First start and first login

### Step 1: Start the server

1. Open the manager (desktop shortcut or `Start-Manager.bat`). **No** administrator rights needed.
2. Tab **Server** → **Start server**.
3. The three status labels change in turn:
   - `MySQL: starting` → `MySQL: running`
   - `Auth server: running`
   - `World server: starting` → after 1–3 minutes `World server: ready`

The very first start takes longer because the world database is loaded and pending database updates are applied.

The black console shows the output of all three programs in colour (`[mysql]` grey, `[auth]` light blue, world server white).

### Step 2: Create an account

1. Wait for `World server: ready`.
2. Press **Create account** (bottom right).
3. Enter a name and password, tick *GM rights (level 3)* if the account should be a game master, and confirm with **Create**.
4. The world server confirms it in the console.

Or type directly into the command line:
```
account create playername password
```

### Step 3: Connect the client

1. Open `realmlist.wtf` in your WoW 3.3.5a folder with a text editor (usually in `Data\enUS\` or `Data\deDE\`).
2. Replace the contents with:
   ```
   set realmlist 127.0.0.1
   ```
3. Save. Start `Wow.exe` (not the launcher), log in, pick the realm, create a character.

### Step 4: Shut the server down properly

**Always** stop through the manager, never by closing the window or killing the task:

- **Stop server safely** sends `server shutdown 1` to the world server, which saves all characters and shuts down. Then the auth server, then MySQL. Takes 5–30 seconds.
- If you close the manager with the server running, it asks: *Yes* = stop safely and quit.

Why this matters: character data is held in memory and only written periodically. A hard kill can cost the last few minutes of progress or damage tables.

---

## Part 3 – Daily operation

### Server tab

| Element | Function |
|---|---|
| Start server / Stop server safely / Restart | All three services in the correct order |
| Stop database | Shuts down MySQL alone when no server is running |
| Restart world server automatically after a crash | Restarts 5 s after an abnormal exit |
| Console | Live output, coloured by source |
| Command line + Send | Any world server command (Enter works too) |
| Create account | Dialog for `account create`, with an optional tick for `account set gmlevel` |

Useful console commands (without a leading dot):
```
account create NAME PASSWORD       create an account
account set gmlevel NAME 3 -1      GM rights on all realms
account set password NAME PW PW    set a password
server shutdown 300                shut down in 5 minutes (players see a countdown)
server shutdown cancel             abort it
reload config                      reload worldserver.conf without a restart
announce TEXT                      message to all players
```

### Changing settings (**Settings** tab)

1. Pick the file in the dropdown:
   - `worldserver.conf` – almost everything gameplay related (XP rates, drop rates, player cap, starting level, …)
   - `authserver.conf` – login server, rarely needed
   - `dbimport.conf` – database updater
   - `modules\*.conf` – one file per installed module
2. Type in the search box, e.g. `Rate.XP` — the table filters live and searches the descriptions too.
3. Click the value in the right column, type the new value, press Enter. The cell turns yellow.
4. The grey box below shows the original comment from the file, including the default and allowed values.
5. **Save**. Only changed lines are written; comments and ordering are preserved.
6. To make it take effect: restart the server, or for many `worldserver.conf` values `reload config` in the console.

Common values:

| Setting | Meaning | Default |
|---|---|---|
| `Rate.XP.Kill`, `Rate.XP.Quest`, `Rate.XP.Explore` | XP multiplier | 1 |
| `Rate.Drop.Item.*`, `Rate.Drop.Money` | Loot multiplier | 1 |
| `PlayerLimit` | Max concurrent players | 1000 |
| `StartPlayerLevel`, `StartPlayerMoney` | Starting values for new characters | 1 / 0 |
| `GM.LoginState` | GM mode on login (0 off, 1 on, 2 as before) | 2 |
| `MotdText` | Message of the day | – |

With the playerbots variant everything about the bots lives in `modules\playerbots.conf`, e.g. `AiPlayerbot.MinRandomBots` / `MaxRandomBots` (number of bots) and `AiPlayerbot.RandomBotAutologin`.

The language switch, the light/dark theme switch and **Reset random bots** are at the bottom of this tab. The reset sets `AiPlayerbot.DeleteRandomBotAccounts`, and the manager reverts that setting and restarts the server once the bots have been deleted — without that restart the module leaves the server in a broken state.

### Updating (**Update** tab)

AzerothCore receives commits almost daily. Nothing is checked at startup — a `git fetch` per module costs a network round trip, and with a dozen modules that is noticeable.

1. **Check for updates**. The list shows the core and every Git module with local state, remote state and how many commits are missing.
2. Tick *Start server automatically after the update* if you want that — it is off by default, so you can check the log before the server comes up.
3. Press **Update server**. If the server is running, the manager asks whether it may stop it safely.
4. The chain, all automatic and visible in the log:
   1. Remove linked module SQL copies
   2. `git pull` for the core and all modules
   3. Check and link module SQL
   4. Configure CMake
   5. Build (10–40 min, only changed files)
   6. `dbimport` applies new database updates
   7. Optionally start the server
5. All other tabs are locked while this runs.

**Rebuild only** does the same without `git pull` — needed after adding or removing modules.

If the build fails, the compiler errors are pulled out of the MSBuild log, printed in red and shown in the dialog, and the offending module is named. Full logs: `logs\build.log` and `logs\build-errors.log`.

### Configuring modules (**Modules** tab → *Configure module…*)

Every module brings its own `.conf`. Select the module, press *Configure module…* and you get exactly that file with search, description text and a save button.

Some modules need a character GUID. For the **AH bot** you first create a normal character that will run the auction trading, then enter its GUID in the configuration. The *Pick character…* button does this for you: select the row in the table, press the button, choose a character — the manager inserts the GUID, name or account name depending on the field name.

After changes: restart the server, or `reload config` in the console (does not work for every module setting).

### Installing modules

Module catalogue: https://www.azerothcore.org/catalogue.html

**Drag & drop:** on GitHub press **Code → Download ZIP**, then drag the ZIP onto the *Drop module here* area. A folder works too. The manager unpacks into `source\modules\`, strips the `-master` suffix, verifies it actually looks like a module and analyses its SQL.

**Git URL:** paste the URL, e.g. `https://github.com/azerothcore/mod-transmog.git`, and press *Add from Git*. Preferred, because updates come along automatically.

Afterwards a red note appears: modules changed, run **Rebuild**. Add several modules first if you want — one build covers them all. After the build the module's configuration file appears under *Settings → modules\…conf*; many modules have to be switched on there with `…Enable = 1`.

**Removing:** select the module → *Remove module* → **Rebuild**. The module's database tables stay behind, which is harmless.

**Module info** shows what a module adds: NPC, object and item IDs with the ready-made `.npc add` command, the GM commands it registers, its configuration keys, bundled DBC files and the full README.

### Understanding module SQL (the *SQL files* column)

AzerothCore only imports module SQL automatically when it lives in `modules\<module>\data\sql\db-world` (or `db-characters`, `db-auth`). Many modules still use older layouts such as `sql\world\base`, and some ship no SQL at all. The manager checks this when a module is added and before every build:

| Display | Meaning | What you do |
|---|---|---|
| `none` | module has no SQL | nothing |
| `3 automatic` | already in the right folder | nothing |
| `2 linked` | legacy layout, the manager created copies in the right folder | nothing |
| `1 optional` | extra content the author deliberately does not apply | import manually if wanted |
| `1 unclear` (red) | target database not recognisable | assign manually |

For the last two: select the module → **Check / link SQL files…**, tick the files, optionally pick the target database, then *Import selected now*. Rule of thumb: items, NPCs, quests and spells → `acore_world`; anything stored per character → `acore_characters`; accounts → `acore_auth`.

Automatic and linked files are applied by `dbimport` on the next rebuild or update — you do not have to trigger that.

**A common failure:** when a module is added to an existing database, its `base` SQL is skipped (AzerothCore only runs `base` files on an empty database) while its `updates` SQL still runs and fails on the missing table. The manager detects this, offers to apply the base files and retries the import.

### Bundled DBC files

If a module ships `.dbc` files they must replace the ones in `data\dbc`. The module info window lists them and offers **Apply DBC files**, which copies them across after backing up the originals to `data\dbc-backup-<timestamp>\`. The server must be stopped.

Note that some DBC changes must also be present in the **client** (as a `patch-x.MPQ` in its `Data` folder), otherwise the client displays different values. The module's README says whether that is needed.

### Editing characters (**Characters** tab)

Shows all characters on real accounts. Random bots are hidden, identified by the account prefix from `playerbots.conf` (`AiPlayerbot.RandomBotAccountPrefix`, default `rndbot`). Your own alts stay visible even if they run as alt bots. Tick *Include bot accounts* to see everything.

The right side shows the selected character with its 19 equipment slots (item names in quality colours, full stats on hover) and a table of every editable value: name, level, experience, money, health, mana/rage/energy/runic power, appearance, honor, arena points, position, `at_login` and `playerFlags`.

**Changing equipment:** click a slot → item picker. The list comes straight from `item_template` in your world database, filtered to the slot. The tick *Only items matching class and level* reproduces the server's own checks: armor type (cloth/leather/mail/plate, with mail and plate only from level 40), shields, class relics such as idols and totems, allowed weapon types, dual wield for the off hand — plus a level-appropriate item level range that keeps test and developer items out. Without the tick you see everything, but the server may refuse such an item at login and leave the slot empty.

**Auto-equip** sits in the free cell of the slot grid. It asks for a role (tank, melee, ranged, caster, healer, preselected from the class) and picks the best available item per slot. You get a preview of all slots before anything is written. The choice is based on stat weights, not on talents, set bonuses or enchants — good enough for a test character, not a real BiS list. The weights live in `tools/AC.Char.ps1` under `$script:AcRoleWeights` if you want to adjust them.

**Rules the manager enforces:**
- A **logged-in** character is never touched — the server would overwrite the changes on logout.
- **Equipment** can only be changed while the **world server is stopped**, because a running server hands out item GUIDs from its own counter and duplicates would result. Values such as level or money may be changed while the server runs, as long as the character is offline.

Stale `online` flags left behind by a crashed server are detected and reset, since no world server is running in that case.

**What cannot be changed and why:** strength, agility, stamina and similar attributes are not stored in the database. The server recomputes them at login from level, class, talents and gear. Maximum health and mana are derived as well — the *Health* and *Mana* fields are the current values at logout.

### GM commands tab

The command list of the currently built server, read from `acore_world.command` — including commands added by your modules. Search by name or description, filter by security level, copy a command to the clipboard (button or double-click), or send it straight to the running server.

### Opening the server to LAN or internet (**Info** tab)

By default the server is only reachable from the same PC. For others:

1. **Info** tab → *Realm address* → enter your LAN IP (e.g. `192.168.178.20`, find it with `ipconfig`) or your public IP / DynDNS name → **Apply**.
2. Restart the world server.
3. Windows firewall: allow inbound connections for `authserver.exe` and `worldserver.exe` (Windows usually asks on first start).
4. For internet access, forward ports **3724** (TCP, login) and **8085** (TCP, world) to your PC in the router.
5. Other players put your address into their `realmlist.wtf`.

MySQL always stays on `127.0.0.1` and is not reachable from outside.

---

## Part 4 – Folders, backup, maintenance

### What lives where

```
C:\AC\
├─ Start-Manager.bat                start the manager
├─ Resume-Installation.bat  resume / repair the installation
├─ ac-settings.json                 variant, ports, database passwords
├─ source\                          source code (git repository)
│  └─ modules\                      all modules, one folder each
├─ build\bin\RelWithDebInfo\        worldserver.exe, authserver.exe, dbimport.exe
│  └─ configs\                      worldserver.conf, authserver.conf, dbimport.conf
│     └─ modules\                   one .conf per module
├─ data\                            dbc, maps, vmaps, mmaps
├─ mysql\
│  └─ data\                         THE DATABASE: accounts, characters, world
├─ deps\                            Boost, plus portable Git/CMake/OpenSSL if used
├─ logs\                            install.log, manager.log, build.log, DBErrors.log
└─ tools\                           the scripts
```

### Backup

With the **server stopped**, two folders are enough: `mysql\data\` (all saved games) and `build\bin\RelWithDebInfo\configs\` (your settings). Copy them somewhere safe; restoring means copying them back, again with the server stopped.

For a backup while the server runs, use a MySQL dump:
```
C:\AC\mysql\bin\mysqldump.exe --defaults-extra-file=C:\AC\mysql\client.cnf --databases acore_auth acore_characters acore_world > backup.sql
```

### Passwords

The installer generates random passwords for the MySQL `root` user and the `acore` database user. Both are stored in plain text in `ac-settings.json` (and `mysql\client.cnf`). You only need them if you want to open the database with an external tool such as HeidiSQL or Keira3: host `127.0.0.1`, port from the file, user `acore`, password `DbPassword`.

Never publish `ac-settings.json` — it is excluded from the repository by `.gitignore` for exactly that reason.

### Freeing disk space

After a successful installation the installer already removes `deps\downloads\` (Boost installer, MySQL ZIP, client data ZIP), extraction leftovers and empty folders. `deps\boost_*` must stay — every future build needs it.

---

## Part 5 – Troubleshooting

**I received updated scripts — where do they go?**
The manager runs from `<folder>\tools\` (e.g. `C:\AC\tools\`), not from the download folder. Copy the new `.ps1` files there and restart the manager. The version is shown in the title bar and on the *Info* tab. Alternatively run `Resume-Installation.bat` from the new download folder: the preparation step refreshes the tools on every run.

**"winget was not found"**
Not fatal any more — the installer downloads the required programs directly instead. If you would rather have `winget`, install *App Installer* from the Microsoft Store or run Windows Update.

**Step 2 hangs with no output**
The Visual Studio Build Tools install several GB in the background. Task Manager shows `setup.exe` / `vs_installer` working. 30 minutes is normal on a slow connection.

**"OpenSSL … was not found and could not be installed"**
Open https://slproweb.com/products/Win32OpenSSL.html, download **Win64 OpenSSL v3.x.x** — explicitly **not** the *Light* variant, which contains no headers and no `.lib` files — install it, then press **Try again**. If OpenSSL is installed but not detected, set the environment variable `OPENSSL_ROOT_DIR` to the folder containing `include\` and `lib\` and restart the installer.

**"MySQL could neither be downloaded nor installed"**
Oracle's servers sometimes block automated downloads (error 403). Open https://dev.mysql.com/downloads/mysql/8.4.html, download **Windows (x86, 64-bit), ZIP Archive** (~250 MB, not the debug variant; click *No thanks, just start my download*, no account needed) and drop the file unchanged into `<folder>\deps\downloads\`. Then **Try again** — the installer recognises the archive by its name.

**"Visual Studio 2022 (C++ tools) was not found" after step 2**
Install manually from https://visualstudio.microsoft.com/downloads/ → *Build Tools for Visual Studio 2022* → workload **Desktop development with C++**. Then run the installer again.

**Build fails with `error C1083` / `LNK1104` / path too long**
The folder path is too long or contains spaces. Reinstall into `C:\AC`.

**Build fails with `error C2xxx` in a module**
The module does not match the current core. The manager names it in the error dialog. Remove the module and rebuild, or look for a fixed fork or an open issue in its repository.

**Port 3306 in use**
Another MySQL/MariaDB/XAMPP is running. Pick 3307 in the installer. The bundled MySQL is deliberately not registered as a Windows service so it cannot interfere with an existing installation.

**World server hangs on "starting" or exits immediately**
Scroll up in the console to the first red or `ERROR` line. Typical causes:
- `Unable to connect to database` → MySQL is not running, or the password in `worldserver.conf` differs from `ac-settings.json`
- `Map file '...' does not exist` / `vmaps` / `mmaps` → client data missing; check that `data\maps` and friends are populated, otherwise run the installer again (step 8 is repeated)
- `Your database structure is not up to date` → run *Rebuild only*, which calls `dbimport`
- `Applying of file '...sql' failed` → a SQL file, usually from a module, is broken; the file and the error are in `logs\DBErrors.log`

**Client: "Unable to connect"**
1. Does it say `World server: ready`?
2. Is `realmlist.wtf` saved, and in the right language folder (`enUS`/`deDE`)?
3. On LAN: is the realm address set to the LAN IP and the firewall open?

**Client: realm list is empty**
The realm address points at an IP the client cannot reach. For the same PC it must be `127.0.0.1`.

**Manager says the server is running but nothing is**
A world server process is left over from an earlier session. End `worldserver.exe` in Task Manager and try again.

**I broke a configuration file**
The original template sits next to it as `.conf.dist`. Delete the file and run *Rebuild only* — the manager recreates it from the template and fills in database and paths again.

**Start over but keep characters**
1. Stop the server. Copy `mysql\data\` somewhere else.
2. Delete `C:\AC`, reinstall.
3. Start the server once so the databases exist, then stop it.
4. Copy the saved `mysql\data\` back — **but** `ac-settings.json` and `mysql\client.cnf` must match the old root password. Cleaner: dump only the three databases with `mysqldump` (see Backup) and import them into the new installation.

---

## Quick reference

| I want to … | … so |
|---|---|
| play | Manager → Start server → wait for *ready* → client |
| stop | Manager → Stop server safely |
| create an account | Manager → Create account |
| change the XP rate | Settings → worldserver.conf → `Rate.XP` → Save → `reload config` |
| update | Update → Check for updates → Update server |
| add a module | Modules → drop a ZIP or paste a Git URL → Rebuild → Configure module… |
| edit a character | Characters → select → change values or click an equipment slot |
| invite friends | Info → realm address → open ports 3724 + 8085 |
| switch language or theme | Settings → *Language* / *Theme* at the bottom |
| back up | stop the server → copy `mysql\data` and `configs` |
