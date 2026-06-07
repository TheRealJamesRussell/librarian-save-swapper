# 📚🔮 Librarian: Save Swapper

Unofficial launcher and save swapper for `Librarian: Tidy Up the Arcane Library!`.

As of June 2026, the game does not support multiple saves. It uses one active save folder. This launcher lets you pick a managed save profile and swaps that profile's gameplay save into the active save folder before starting the game.

## Features

- 💾 Allows multiple named save profiles.

- 🕘 Keeps the latest 5 gameplay-save versions for each profile.

- 🪶 Adds extremely low to no performance overhead.

## Prerequisites

- Windows 10 or Windows 11. See [OS Support](#os-support).

- Steam Cloud disabled for this game. See [Steam Cloud Warning](#steam-cloud-warning).

## Install

The simplest way to install this is to open PowerShell and paste this command:

```powershell
irm https://raw.githubusercontent.com/TheRealJamesRussell/librarian-save-swapper/main/install.ps1 | iex
```

A packaged release is not available yet. Use the PowerShell install command above for now.

## Use

1. Press `Win + R`.
2. Type `librarian`.

The first run will create launcher folders and ask what to do if it finds existing active saves but no managed profile yet.

Menus support arrow-key navigation. Use `Up` and `Down` to highlight an option, press `Enter` to choose it, and press `Esc` to go back.

## UI Rules

- Use arrow keys to move, `Enter` to choose, and `Esc` to return to the previous menu.
- Do not use shortcut letters or number-key selection in menus.
- Keep disabled menu items visible in gray, but do not allow them to be selected.
- Keep the main menu stable: show `Play profile: <name>` for the primary profile and `Pick Other Profile` for profile switching.
- Enable `Pick Other Profile` only when at least one other profile exists.
- Only ask for typed input when the user is naming or renaming a profile.

The launcher starts the game through Steam by default using Steam App ID `4197610`, so Steam playtime and Steam overlay behavior should work normally.

Main actions:

- Capture current save: save the current active save into a new profile or an existing profile.
- Start new playthrough: back up the current save, remove only active `Sav.sav`, launch the game, and save the new `Sav.sav` into a new profile after the game exits.
- Restore profile version: restore one of a selected profile's timestamped versions.

For troubleshooting, run:

```text
librarian --log
```

This prints the log path and writes extra diagnostics to:

```text
%APPDATA%\librarian-save-swapper\logs\launcher.log
```

## OS Support

Windows 10 and Windows 11 are supported.

macOS and Linux are not supported right now because the launcher depends on Windows save paths, PowerShell, and Windows `Win + R` command registration. If you want support for another operating system, open an issue and we can discuss what that version should look like.

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

The uninstaller removes the `librarian` command and installed launcher files. It keeps profiles and backups by default. See file locations below.

## Cloud Save Alternative

One practical alternative is to sync the managed profile folder yourself with a cloud-drive app. For example, you can use Google Drive for desktop to sync:

```text
%APPDATA%\librarian-save-swapper\profiles
```

That keeps the launcher-managed profile versions in your Google Drive while leaving the game's active save folder local. Avoid syncing the active game save folder directly while the game is running.

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

Safety backups:

```text
%APPDATA%\librarian-save-swapper\backups
```

The launcher keeps only the newest five safety backups. Older backup folders are removed automatically.

Deleted profiles are moved to the Recycle Bin, not to a separate archive folder. Restore them from the Recycle Bin if needed, or empty the Recycle Bin to remove them permanently.

## License

Licensed under the MIT License.
