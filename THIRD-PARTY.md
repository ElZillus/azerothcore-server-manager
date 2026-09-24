# Third-party software and data

This repository contains **only** the PowerShell scripts and this documentation.
No third-party code, binaries or game data are bundled or redistributed here.

Everything below is downloaded from its original source **on the user's machine
at install time**, at the user's request.

## Downloaded and installed by the installer

| Component | Source | Licence | Installed to |
|---|---|---|---|
| AzerothCore | github.com/azerothcore/azerothcore-wotlk | AGPL-3.0 | `<folder>\source` |
| AzerothCore Playerbot fork + mod-playerbots | github.com/mod-playerbots | AGPL-3.0 / GPL-2.0 | `<folder>\source` |
| MySQL Community Server | dev.mysql.com (or `winget Oracle.MySQL`) | GPL-2.0 with FOSS exception | `<folder>\mysql` (portable) |
| Boost | sourceforge.net/projects/boost | Boost Software License 1.0 | `<folder>\deps` |
| OpenSSL (Shining Light, or FireDaemon as fallback) | `winget` | Apache-2.0 | system-wide |
| CMake | `winget Kitware.CMake` | BSD-3-Clause | system-wide |
| Git | `winget Git.Git` | GPL-2.0 | system-wide |
| Visual Studio 2022 Build Tools | `winget Microsoft.VisualStudio.2022.BuildTools` | Microsoft EULA | system-wide |
| VC++ Redistributable | `winget Microsoft.VCRedist.2015+.x64` | Microsoft EULA | system-wide |

Note on the OpenSSL fallback: if the Shining Light package is unavailable,
the installer falls back to **FireDaemon OpenSSL**, which is free for personal
use but may require a licence for commercial use. If that matters to you,
install OpenSSL yourself before running the installer.

## Client data

Step 8 downloads prebuilt client data (`dbc`, `maps`, `vmaps`, `mmaps`) from
`github.com/wowgaming/client-data`. These files are **extracted from the World
of Warcraft client and remain the property of Blizzard Entertainment.**

* This project does not host, mirror or redistribute them.
* A legally obtained World of Warcraft 3.3.5a client is required to use them.
* You may instead point the installer at a data folder you extracted yourself.

## Modules

Modules installed through the manager are downloaded from the repositories the
user chooses. Their licences are their own; check each module's repository.

## Trademarks

World of Warcraft and Blizzard Entertainment are trademarks or registered
trademarks of Blizzard Entertainment, Inc. This project is not affiliated with,
endorsed by, or sponsored by Blizzard Entertainment.
