# 📚🔮 Librarian: Save Swapper

Unnoficial Launcher & Save Swapper for `Librarian: Tidy Up the Arcane Library!`.

As of June 2026 the game does not support multiple saves. It uses one active save folder. This launcher allows you to pick and swap the selected save into the active save folder before starting the game. 

## Features
emoji Allows multiple named saves.
emoiji Keeps 5 backups of each saves.
emoji Extremely low to no performance overhead.

## Prerequisites
- Windows. This script only supports Windows for now if you use another OS (be it linux or mac). Open a Issue and we can chat on getting support. 
- turn off cloud sync for the game (see instructions lower down)

## Install
Simplest way to install this is to open powershell and paste this command.
```powershell
irm https://raw.githubusercontent.com/TheRealJamesRussell/librarian-save-swapper/main/install.ps1 | iex
```

Or Download the latesr release "here" and run "this".

## To use

1. Press `Win + R`.
2. Type `librarian`.

The first run will create launcher folders and ask what to do if it finds existing active saves but no managed profile yet.

## Steam Cloud Warning

Steam Cloud may overwrite local files after the launcher swaps saves. For safest profile switching, disable Steam Cloud manually for this game in Steam if the option is available:

1. Open Steam.
2. Right-click the game.
3. Open `Properties`.
4. Open `General`.
5. Turn off Steam Cloud for this game.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\librarian-save-swapper\uninstall.ps1"
```

The uninstaller removes the `librarian` command and installed launcher files. It keeps profiles and backups by default. Check file locations below 

## Where Files Go
Installed launcher files:
```text
%LOCALAPPDATA%\Programs\librarian-save-swapper
```

Profiles, backups, config, and logs:
```text
%APPDATA%\librarian-save-swapper
```

Managed profiles:
```text
%APPDATA%\librarian-save-swapper\profiles
```

Each profile keeps the newest five timestamped gameplay-save versions:
```text
%APPDATA%\librarian-save-swapper\profiles\<ProfileName>\2026-06-07_14-32-10\Sav.sav
```

Archived profiles:
```text
%APPDATA%\librarian-save-swapper\archives
```

Backups:
```text
%APPDATA%\librarian-save-swapper\backups
```

## License
Licensed under the MIT License.

