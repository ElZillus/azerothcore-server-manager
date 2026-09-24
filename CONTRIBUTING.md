# Contributing

## Reporting a problem

Please include:

* the **manager version** from the title bar (e.g. `2026-09-05.37`)
* the **server variant** (with or without playerbots)
* the relevant part of `<folder>\logs\manager.log` or `logs\install.log`
* for build failures: `logs\build-errors.log`
* for database failures: `logs\DBErrors.log`

Please do not paste `ac-settings.json` — it contains your database passwords in
plain text.

## Working on the scripts

* Everything is PowerShell 5.1 (the version shipped with Windows), WinForms for
  the GUI. No external modules, no compiled parts.
* The files must stay **ASCII with CRLF line endings**. PowerShell 5.1 reads
  files without a BOM as ANSI, so non-ASCII characters break the UI.
* **Every user-facing string goes into `tools/AC.Lang.ps1`**, in both the `de`
  and `en` block, and is used via `T 'key'`. Placeholders are `{0}`, `{1}`, …
  and are filled with `T 'key' @(value)`.
* Layout is done in explicit `$layout*` script blocks per tab, not with WinForms
  anchoring — anchors are computed from the size a tab page had before it was
  shown, which produces controls outside the visible area.
* Long-running work must keep the UI responsive: use `Invoke-AcCaptureUi` for
  external processes and `Invoke-AcDoEvents` in wait loops.

## Safety rules that should not be relaxed

These exist because breaking them corrupts player data:

* never write to a character that is logged in
* never change equipment while a world server from this folder is running
  (it assigns item GUIDs from its own counter)
* stop the world server with `server shutdown`, never by killing the process,
  unless it stopped responding
