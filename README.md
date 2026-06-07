# librarian-save-swapper

A small Windows save-profile launcher for `Librarian: Tidy Up the Arcane Library!`.

The game uses one active save folder. This launcher keeps separate profile folders, swaps the selected profile's `Sav.sav` into the active save folder, starts the game, waits for it to close, and then copies the updated `Sav.sav` back into that profile.

## Install

From this repo folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

For a GitHub-hosted install, use:

```powershell
irm https://raw.githubusercontent.com/TheRealJamesRussell/librarian-save-swapper/main/install.ps1 | iex
```

`irm` is `Invoke-RestMethod`, and `iex` is `Invoke-Expression`.

## Use

1. Press `Win + R`.
2. Type `librarian`.
3. Pick a profile number, or choose an action from the menu.

The first run will create launcher folders and ask what to do if it finds existing active saves but no managed profile yet.

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

Game save folder:

```text
%LOCALAPPDATA%\Librarian\Saved\SaveGames
```

Per-profile gameplay file:

```text
Sav.sav
```

The launcher leaves `SystemSetting.sav` in the active save folder so graphics/audio/control settings stay global instead of moving between profiles.

## Safety

The launcher is designed to be conservative:

- It refuses to swap profiles while `Librarian.exe` appears to be running.
- It backs up the full active save folder before switching profiles.
- It keeps the latest five timestamped `Sav.sav` versions per profile.
- It archives profiles instead of permanently deleting them.
- It swaps only `Sav.sav` between profiles.
- It keeps profiles and backups when uninstalling unless you explicitly type `DELETE`.

## Steam Cloud Warning

Steam Cloud may overwrite local files after the launcher swaps saves. For safest profile switching, disable Steam Cloud manually for this game in Steam if the option is available:

1. Open Steam.
2. Right-click the game.
3. Open `Properties`.
4. Open `General`.
5. Turn off Steam Cloud for this game.

This launcher does not automatically edit Steam Cloud settings.

## Recover From A Backup

Run `librarian`, choose `R`, and select a backup to restore. The launcher creates another backup before restoring.

You can also manually inspect backups here:

```text
%APPDATA%\librarian-save-swapper\backups
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\librarian-save-swapper\uninstall.ps1"
```

The uninstaller removes the `librarian` command and installed launcher files. It keeps profiles and backups by default.

## Known Limitations

- Windows only.
- Steam Cloud behavior is not controlled by the launcher.
- The game save behavior is not fully known, so the launcher waits for the game process to exit before saving the selected profile.
- The first version uses a simple number-based terminal menu.

## License

Licensed under the MIT License.

