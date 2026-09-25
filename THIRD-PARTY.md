# Third-party software and data

This repository contains **only** the PowerShell scripts and this documentation.
No third-party code, binaries or game data are bundled or redistributed here.

Everything below is downloaded from its original source **on the user's machine
at install time**, at the user's request. The manager runs these programs as
separate processes and talks to the database through `mysql.exe`; it does not
link against or embed any of their code. That is why the scripts in this
project can carry their own licence (see `LICENSE`) while everything listed
here keeps the terms of its authors.

## Downloaded and installed by the installer

| Component | Source | Licence | Installed to |
|---|---|---|---|
| AzerothCore | github.com/azerothcore/azerothcore-wotlk | AGPL-3.0 | `<folder>\source` |
| AzerothCore Playerbot fork + mod-playerbots | github.com/mod-playerbots | AGPL-3.0 / GPL-2.0 | `<folder>\source` |
| MySQL Community Server | dev.mysql.com, direct download; `winget Oracle.MySQL` as fallback | GPL-2.0 with FOSS exception | `<folder>\mysql` (portable) |
| Boost (prebuilt, MSVC) | sourceforge.net/projects/boost, github.com/userdocs/boost | Boost Software License 1.0 | `<folder>\deps\boost_*` |
| OpenSSL (Shining Light; FireDaemon as fallback) | slproweb.com, `winget`, or direct download | Apache-2.0 | system-wide or `<folder>\deps\openssl` |
| CMake | `winget Kitware.CMake` or GitHub release ZIP | BSD-3-Clause | system-wide or `<folder>\deps\cmake` |
| Git / PortableGit | `winget Git.Git` or GitHub release | GPL-2.0 | system-wide or `<folder>\deps\PortableGit` |
| Visual Studio 2022 Build Tools | `winget` or aka.ms installer | Microsoft EULA | system-wide |
| VC++ Redistributable | `winget` or aka.ms installer | Microsoft EULA | system-wide |

The installer prefers `winget` where available and falls back to a direct
download from the vendor, so it also works on systems without `winget`.

Note on the OpenSSL fallback: if the Shining Light package is unavailable, the
installer can fall back to **FireDaemon OpenSSL**, which is free for personal
use but may require a licence for commercial use. If that matters to you,
install an OpenSSL 3.x package yourself before running the installer and point
`OpenSslRoot` in `ac-settings.json` at it.

## What AGPL-3.0 means for you as an operator

AzerothCore is licensed under AGPL-3.0. Running it — unchanged or modified —
is free. If you **modify the core** and let other people play on that server,
the licence requires you to offer those people the source code of your
modified version. Running an unmodified core raises no such obligation,
because the source is already public.

This project does not change that in either direction: the manager builds and
starts the core, it does not become part of it.

## Lua engines

If you install a Lua engine through the manager, it is fetched from its own
repository and keeps its own licence:

| Component | Source | Licence |
|---|---|---|
| mod-ale (formerly mod-eluna) | github.com/azerothcore/mod-ale | AGPL-3.0 |
| ElunaAzerothCore | github.com/ElunaLuaEngine/ElunaAzerothCore | GPL-3.0 |
| Lua | fetched by the engine's own build | MIT |

## Client data

The installer downloads prebuilt client data (`dbc`, `maps`, `vmaps`, `mmaps`)
from `github.com/wowgaming/client-data`. These files are **extracted from the
World of Warcraft client and remain the property of Blizzard Entertainment.**

* This project does not host, mirror or redistribute them.
* A legally obtained World of Warcraft 3.3.5a client is required to use them.
* You may instead point the installer at a data folder you extracted yourself.

## Modules and Lua script packages

Modules and script packages installed through the manager are downloaded from
the repositories **you** choose. Their licences are their own — check each
repository before redistributing a server built with them. The manager keeps
the `LICENSE` file of every module inside its folder untouched.

## Trademarks

World of Warcraft and Blizzard Entertainment are trademarks or registered
trademarks of Blizzard Entertainment, Inc. This project is not affiliated with,
endorsed by, or sponsored by Blizzard Entertainment.
