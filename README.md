# librarygame-launcher

A small Windows save-profile launcher for `Librarian: Tidy Up the Arcane Library!`.

The game uses one active save folder. This launcher keeps separate profile folders, swaps the selected profile into the active save folder, starts the game, waits for it to close, and then copies the updated save back into that profile.

## Install

From this repo folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

For a GitHub-hosted release, use the raw `install.ps1` URL:

```powershell
irm https://raw.githubusercontent.com/<owner>/librarygame-launcher/main/install.ps1 | iex
```

`irm` is `Invoke-RestMethod`, and `iex` is `Invoke-Expression`.

## Use

1. Press `Win + R`.
2. Type `librarygame`.
3. Pick a profile number, or choose an action from the menu.

The first run will create launcher folders and ask what to do if it finds existing active saves but no managed profile yet.

## Where Files Go

Installed launcher files:

```text
%LOCALAPPDATA%\Programs\librarygame-launcher
```

Profiles, backups, config, and logs:

```text
%APPDATA%\librarygame-launcher
```

Managed profiles:

```text
%APPDATA%\librarygame-launcher\profiles
```

Archived profiles:

```text
%APPDATA%\librarygame-launcher\archives
```

Backups:

```text
%APPDATA%\librarygame-launcher\backups
```

Game save folder:

```text
%LOCALAPPDATA%\Librarian\Saved\SaveGames
```

## Safety

The launcher is designed to be conservative:

- It refuses to swap profiles while `Librarian.exe` appears to be running.
- It backs up the active save folder before switching profiles.
- It backs up a managed profile before overwriting it.
- It archives profiles instead of permanently deleting them.
- It only clears the expected `Librarian\Saved\SaveGames` folder.
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

Run `librarygame`, choose `R`, and select a backup to restore. The launcher creates another backup before restoring.

You can also manually inspect backups here:

```text
%APPDATA%\librarygame-launcher\backups
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\librarygame-launcher\uninstall.ps1"
```

The uninstaller removes the `librarygame` command and installed launcher files. It keeps profiles and backups by default.

## Known Limitations

- Windows only.
- Steam Cloud behavior is not controlled by the launcher.
- The game save behavior is not fully known, so the launcher waits for the game process to exit before saving the selected profile.
- The first version uses a simple number-based terminal menu.

## License

Licensed under the MIT License.
