# Changelog

The manager shows its version in the title bar and in the Info tab.

## 2026-09-06.88 – .94
* Per-repository selection for updates: only repositories with pending commits
  are ticked, individual ones can be held back
* Build failures look up missing include files across the source tree
* `USE <database>` lines inside module SQL are neutralised on manual import
* Every error dialog now writes type, file, line, command and call stack to
  `manager.log`

## 2026-09-06.84 – .87
* Dark theme completed: title bar, window frame, scrollbars, list headers and
  the tab strip
* Character tab layout reworked; the module config dialog lost its redundant
  character picker

## 2026-09-06.54 – .83
* Character export and import, including inventory, achievements, reputation
  and completed quests; bag overflow is delivered by mail
* Lua script packages: install from Git, ZIP or folder, engine installation,
  SQL import, client addon detection
* Module list export and import with optional commit pinning
* Single instance per server folder
* Many fixes around PowerShell 5.1 list handling in the database layer

## 2026-09-06.16
* Downloads send the referer header some providers require, and the reachability
  probe now fetches real bytes instead of using HEAD — this removes the repeated
  403 errors while looking for a working MySQL mirror

## 2026-09-06.15
* Output of external tools is decoded per line, trying UTF-8 first and falling
  back to the OEM code page, so German MSBuild messages are no longer garbled

## 2026-09-06.14
* Download addresses are probed quietly before use; only the chosen one is logged

## 2026-09-06.12 – .13
* The installer updates an already cloned source tree before building and logs
  the exact commit it builds
* A single **Create account** button with an optional GM tick replaces the two
  separate account buttons

## 2026-09-06.11
* **English is the default language** in both installer and manager; a language
  chosen in the installer is carried over and kept
* Missing fallback language is English as well, so no mixed-language output
* Translation audit: four log keys were missing, the remaining hardcoded German
  strings (window title, module columns, folder picker, status message) now go
  through the language table

## 2026-09-06.09 – .10
* Removed the stats note from the character tab
* "Start server automatically after the update" is off by default

## 2026-09-06.06
* Account dialog restyled and given a cancel button

## 2026-09-06.04 – .05
* Character tab rebuilt: the 3D-view note and the auto-equip strip are gone,
  slots are narrower and arranged in two columns, the values grid is roughly
  twice as tall, and auto-equip sits in the free slot cell with the role asked
  in a small dialog

## 2026-09-06.03
* The update tab gives the repository list about two thirds of the space; the
  splitter position is remembered

## 2026-09-06.02
* The installer now copies **all** scripts into `<folder>\tools` and verifies
  they arrived — previously a hardcoded list left newer files behind

## 2026-09-06.01
* Reworked interface: flat controls, accent colour, owner-drawn tabs, styled
  grids and lists, **light and dark theme** switchable in the Settings tab
* Item quality colours adapt to the active theme

## 2026-09-05.38 – .39
* `winget` is no longer required: Git, CMake, OpenSSL, the VC++ redistributable
  and the Build Tools are downloaded directly if it is missing or a package fails
* Git, CMake and OpenSSL are installed portably into the server folder
* The generated helper script is now called `Resume-Installation.bat`

## 2026-09-05.37
* Auto-equip: item level is now capped per character level, items without a
  level requirement are restricted, test and developer items are filtered out
* The same filter applies to the manual item picker when "matching class and
  level" is ticked

## 2026-09-05.35 – .36
* Stale `online` flags left behind by a crashed world server are ignored and
  reset; an externally started world server is now detected
* The database start prompt is no longer shown twice

## 2026-09-05.33 – .34
* Character editor shows item stats in the picker and as slot tooltips
* Auto-equip by role with preview
* Database start is confirmed every time a database-dependent tab is opened;
  the update chain asks up front instead of after the build

## 2026-09-05.27 – .32
* New GM commands tab (list from `acore_world.command`, copy or send)
* dbimport failures show the failing SQL statement; missing module `base` SQL
  is detected and can be applied automatically
* Update check no longer runs at startup
* Faster MySQL status check, other tabs locked during an update

## 2026-09-05.20 – .26
* Random bot reset with automatic restart, `RELOAD` privilege granted
* Post-install cleanup of downloads, extraction leftovers and empty folders
* All log and installer messages moved into the language table

## 2026-09-05.06 – .19
* Character editor, module configuration dialog, module info view
* Module SQL handling: legacy layouts linked, module name in copied file names,
  duplicate content skipped, playerbots database recognised
* DBC files bundled with a module can be applied with a backup
* Global exception handler, separate stop button for the database
* German and English interface, switchable at runtime

## 2026-09-05.01 – .05
* First working installer and manager
