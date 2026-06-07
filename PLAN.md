# PLAN.md

## Project Name

`librarygame-launcher`

## High-Level Goal

Build a small Windows launcher for the Steam game:

`Librarian: Tidy Up the Arcane Library!`

The launcher should let the user manage multiple local save profiles even though the game itself does not officially support multiple save slots.

The desired user experience is:

1. User presses `Win + R`.
2. User types `librarygame`.
3. A small terminal/CMD-style menu appears.
4. The menu lists available save profiles.
5. User selects one save profile with keyboard controls or a number prompt.
6. The launcher swaps that profile into the game’s active save folder.
7. The launcher starts the game.
8. The launcher safely handles backing up the previous active save state.

The project should be a full Git-controlled repo, suitable for open source publication on GitHub.

It should include:

- Source code for the launcher.
- Installer script.
- Uninstaller script.
- README.
- MIT license.
- Clear documentation.
- Safety-first save handling.
- Support for installing `librarygame` as a `Win + R` command.

---

## Target Platform

Windows only.

Primary expected environment:

- Windows 10 or Windows 11.
- Steam-installed copy of `Librarian: Tidy Up the Arcane Library!`.
- Game executable likely located at:

```text
C:\Program Files (x86)\Steam\steamapps\common\Librarian Tidy Up the Arcane Library!\Librarian.exe
```

Expected save folder, based on current research:

```text
%LOCALAPPDATA%\Librarian\Saved\SaveGames
```

Expanded example:

```text
C:\Users\<User>\AppData\Local\Librarian\Saved\SaveGames
```

The launcher must not hardcode the username. Use environment variables.

---

## Important Unknowns

The project must account for uncertainty around how the game saves.

Unknown:

- Does the game save only on close?
- Does it save actively during gameplay?
- Does it save on level completion?
- Does it save periodically?
- Does Steam Cloud sync this save folder?
- Does Steam Cloud restore/overwrite local files after the launcher swaps them?

Because of this, the first version should be conservative.

The launcher should assume that save files can change while the game is running.

The launcher should avoid deleting save files unless it has first created a backup.

---

## Core Concept

The launcher will maintain a separate save-profile storage directory outside the game’s active save directory.

Example launcher-managed directory:

```text
%APPDATA%\librarygame-launcher\
```

Inside it:

```text
%APPDATA%\librarygame-launcher\
├── config.json
├── backups\
├── profiles\
│   ├── Main Playthrough\
│   ├── Speedrun Attempt\
│   └── Anti-Magic Master\
└── logs\
```

The game itself will continue using:

```text
%LOCALAPPDATA%\Librarian\Saved\SaveGames
```

The launcher swaps files between:

```text
%APPDATA%\librarygame-launcher\profiles\<ProfileName>\
```

and:

```text
%LOCALAPPDATA%\Librarian\Saved\SaveGames
```

---

## Desired Runtime Flow

When the user runs:

```text
librarygame
```

The launcher should:

1. Detect the game executable.
2. Detect the active save directory.
3. Detect existing managed profiles.
4. Show a simple terminal menu.
5. Let the user choose a profile.
6. Back up the current active save folder.
7. Save the current active save folder into the previously active profile, if known.
8. Replace the active game save folder with the selected profile.
9. Launch the game.
10. Optionally wait for the game process to exit.
11. After the game exits, copy the active save folder back into the selected profile.

---

## Save Handling Strategy

The safest strategy is:

### Before Launch

1. Confirm the game is not already running.
2. Create a timestamped backup of the current active `SaveGames` folder.

Example:

```text
%APPDATA%\librarygame-launcher\backups\2026-06-07_14-32-10_before-switch\
```

3. If the launcher knows which profile was active last, copy the current active save folder into that profile before switching away from it.

Example:

```text
SaveGames -> profiles\Main Playthrough
```

4. Clear or replace the active `SaveGames` folder.
5. Copy the selected profile into the active `SaveGames` folder.

Example:

```text
profiles\Speedrun Attempt -> SaveGames
```

6. Launch the game executable.

### While Game Is Running

The launcher can either:

- Exit immediately after launching the game.
- Or stay open and wait for the game process to exit.

Preferred first implementation:

- Keep the launcher open.
- Wait for the game process to exit.
- Then copy the active save folder back into the selected profile.

This is safer because if the game saves on close, the launcher captures the final state.

### After Game Closes

1. Copy the active `SaveGames` folder back into the selected profile.
2. Write/update `config.json` with the last active profile.
3. Create a small log entry.

Example:

```json
{
  "lastActiveProfile": "Speedrun Attempt",
  "gameExePath": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Librarian Tidy Up the Arcane Library!\\Librarian.exe",
  "savePath": "%LOCALAPPDATA%\\Librarian\\Saved\\SaveGames"
}
```

---

## Profile Operations

The launcher menu should support at least:

```text
Library Game Save Launcher

Available profiles:

1. Main Playthrough
2. Speedrun Attempt
3. Anti-Magic Master

Actions:

N. Create new profile from current save
R. Rename profile
D. Delete profile
B. Backup current active save
Q. Quit

Choose a profile or action:
```

For first release, deletion can be omitted or made very cautious.

If delete is implemented:

- Never permanently delete immediately.
- Move the profile to a trash/archive folder.
- Or require explicit typed confirmation.

---

## Keyboard UI

A simple number-based menu is enough.

Do not overcomplicate the first version with a full TUI dependency unless desired.

Acceptable first version:

```text
[1] Main Playthrough
[2] Speedrun Attempt
[3] Anti-Magic Master
[N] New profile from current save
[Q] Quit
```

Later versions may add arrow-key navigation.

If arrow-key navigation is desired, consider using:

- PowerShell native input handling.
- A small compiled C# app.
- A Node.js CLI package.
- A Rust crate.
- A Go terminal UI package.

But for reliability and install simplicity, a PowerShell-first version may be best.

---

## Suggested Implementation Options

### Option A: PowerShell Launcher

Pros:

- Easy to install with `irm ... | iex`.
- Easy to inspect.
- Native Windows environment.
- Simple filesystem handling.
- Good fit for open source utility.

Cons:

- Some users may have script execution policy restrictions.
- Direct `Win + R` aliases prefer `.exe` targets, so installer may need a `.cmd` wrapper or registry trick.

### Option B: Small Compiled .NET Console App

Pros:

- Produces a clean `.exe`.
- Best for `Win + R` aliases.
- Easier to distribute.
- Better terminal menu possible.

Cons:

- Requires build tooling during development.
- Installer needs to download release artifact.

### Option C: Rust or Go CLI

Pros:

- Single binary.
- Nice distribution.
- Good performance.
- Clean installer.

Cons:

- More setup for development.
- More complexity than needed for first version.

### Recommended First Version

Use PowerShell for the first version, with a `.cmd` wrapper installed into a stable folder.

Example install location:

```text
%LOCALAPPDATA%\Programs\librarygame-launcher\
```

Files:

```text
%LOCALAPPDATA%\Programs\librarygame-launcher\
├── librarygame.cmd
├── librarygame.ps1
├── uninstall.ps1
└── README-installed.txt
```

The `librarygame.cmd` file launches the PowerShell script:

```bat
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0librarygame.ps1"
```

The installer registers `librarygame` as a `Win + R` command using the Windows App Paths registry key.

---

## Win + R Command Installation

Use the per-user registry key:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\librarygame.exe
```

Because App Paths expects executable-style names, we can either:

1. Point it to a real `.exe`.
2. Point it to a `.cmd` file if Windows accepts it reliably.
3. Create a tiny `librarygame.exe` shim.
4. Add the install folder to the user's PATH.

Recommended practical approach for v1:

- Install `librarygame.cmd`.
- Add install directory to the user's PATH.
- Optionally also create an App Paths entry.

Better long-term approach:

- Ship a real `librarygame.exe` launcher or shim.

Existing working pattern from current machine:

The user previously created an App Paths alias pointing directly to:

```text
C:\Program Files (x86)\Steam\steamapps\common\Librarian Tidy Up the Arcane Library!\Librarian.exe
```

under:

```text
HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\librarygame.exe
```

This worked for launching the game directly.

For the new launcher, replace that target with the launcher executable or wrapper.

---

## Installer Requirements

The project should support a one-line install command like:

```powershell
irm https://raw.githubusercontent.com/<owner>/librarygame-launcher/main/install.ps1 | iex
```

or:

```powershell
iwr https://raw.githubusercontent.com/<owner>/librarygame-launcher/main/install.ps1 -UseBasicParsing | iex
```

The user specifically mentioned `irn | iex`, but the correct PowerShell alias is usually:

```powershell
irm | iex
```

where:

- `irm` means `Invoke-RestMethod`
- `iex` means `Invoke-Expression`

The README can mention both the friendly version and the full command.

Installer should:

1. Create install directory:

```text
%LOCALAPPDATA%\Programs\librarygame-launcher
```

2. Download/copy launcher files.
3. Create app data directory:

```text
%APPDATA%\librarygame-launcher
```

4. Create default config if missing.
5. Detect game executable if possible.
6. Detect save folder if possible.
7. Register `librarygame` command.
8. Print success message.
9. Explain how to uninstall.

The installer should not overwrite existing user profiles.

---

## Uninstaller Requirements

Include an uninstaller script.

Example:

```powershell
%LOCALAPPDATA%\Programs\librarygame-launcher\uninstall.ps1
```

The uninstaller should:

1. Remove the `librarygame` Run command registration.
2. Remove installed launcher files.
3. Ask whether to keep or delete managed save profiles.
4. Default to keeping save profiles.
5. Never delete game saves without explicit confirmation.

Uninstaller should preserve by default:

```text
%APPDATA%\librarygame-launcher\profiles
%APPDATA%\librarygame-launcher\backups
```

Optional cleanup:

```text
%APPDATA%\librarygame-launcher
```

only if user explicitly confirms.

---

## Steam Cloud Sync

The user asked whether the launcher can turn off Steam Cloud Sync.

This needs careful handling.

The launcher should not casually modify global Steam settings.

Steam Cloud behavior can be game-specific and may depend on Steam internals, app manifests, user config, and Steam client state.

Possible approaches:

### Preferred Approach

Document that the user should disable Steam Cloud manually for this game in Steam:

1. Open Steam.
2. Right-click the game.
3. Properties.
4. General.
5. Toggle Steam Cloud off for this game, if available.

### Programmatic Approach

Investigate only if needed.

Possible Steam files involved may include:

```text
C:\Program Files (x86)\Steam\userdata\<SteamUserId>\<AppId>\
C:\Program Files (x86)\Steam\steamapps\appmanifest_<AppId>.acf
C:\Program Files (x86)\Steam\config\
```

But this should be treated as risky because Steam may overwrite config files, and changing them while Steam is running may not persist.

The launcher may eventually include a detection warning:

```text
Steam Cloud may be enabled for this game.
Please disable Steam Cloud for safest profile switching.
```

Do not implement automatic Steam Cloud disabling in v1 unless thoroughly researched.

If implemented later, require explicit confirmation and back up any Steam config file before changing it.

---

## Safety Rules

The launcher must follow these rules:

1. Never delete active saves without creating a timestamped backup.
2. Never overwrite a managed profile without backing it up first.
3. Never swap saves while the game is running.
4. Always check if `Librarian.exe` is already running.
5. Always use absolute paths after resolving environment variables.
6. Always log major actions.
7. Use copy-then-verify-then-replace where practical.
8. Default to preserving user data.
9. If uncertain, stop and ask the user rather than guessing destructively.

---

## Game Running Detection

Before swapping saves, check whether the game process is running.

Possible process name:

```text
Librarian
```

PowerShell example:

```powershell
Get-Process -Name "Librarian" -ErrorAction SilentlyContinue
```

If running, show:

```text
The game appears to be running.
Close the game before switching save profiles.
```

Then exit or offer to launch without switching.

---

## File Copy Strategy

For profile switching:

1. Backup current `SaveGames`.
2. Save current active state into last active profile, if known.
3. Empty active `SaveGames`.
4. Copy selected profile into active `SaveGames`.

Use robust PowerShell copy commands.

Avoid fragile string-based path handling.

Use:

```powershell
Join-Path
Resolve-Path
Copy-Item
New-Item
Remove-Item
```

When clearing `SaveGames`, be careful:

- Only clear contents inside the exact expected save directory.
- Never recursively delete a computed path unless it has been validated.
- Validate that the path ends with:

```text
Librarian\Saved\SaveGames
```

or matches configured path exactly.

---

## Initial Setup Flow

When the launcher runs for the first time:

1. If no config exists, create config.
2. If game exe is not found at the default path, ask the user to paste the full path.
3. If save path does not exist, offer to create it or launch game once first.
4. If there are active saves but no profiles, offer:

```text
Found existing active save files.
Create profile from current save?
Name: Main Playthrough
```

5. Create `Main Playthrough` profile from active save.
6. Set `lastActiveProfile` to `Main Playthrough`.

---

## Config Format

Use JSON.

Example:

```json
{
  "version": 1,
  "gameExePath": "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Librarian Tidy Up the Arcane Library!\\Librarian.exe",
  "savePath": "%LOCALAPPDATA%\\Librarian\\Saved\\SaveGames",
  "lastActiveProfile": "Main Playthrough",
  "waitForGameExit": true,
  "backupBeforeSwitch": true
}
```

When reading config, expand environment variables.

---

## README Requirements

README should include:

1. What the tool does.
2. Why it exists.
3. Install command.
4. Uninstall command.
5. How to use `Win + R -> librarygame`.
6. Where profiles are stored.
7. Where backups are stored.
8. How to recover from a backup.
9. Steam Cloud warning.
10. Known limitations.
11. License info.

README should be written for regular Windows users, not only developers.

---

## Repository Structure

Suggested repo structure:

```text
librarygame-launcher/
├── README.md
├── LICENSE
├── PLAN.md
├── install.ps1
├── uninstall.ps1
├── src/
│   ├── librarygame.ps1
│   └── librarygame.cmd
└── docs/
    ├── steam-cloud.md
    └── save-behavior.md
```

If using compiled app:

```text
librarygame-launcher/
├── README.md
├── LICENSE
├── PLAN.md
├── install.ps1
├── uninstall.ps1
├── src/
│   └── LibraryGameLauncher/
└── docs/
```

---

## MIT License

Add an MIT license.

README should say:

```text
Licensed under the MIT License.
```

---

## First Milestone

Build a minimal working version that:

1. Installs locally.
2. Registers `librarygame`.
3. Opens a terminal menu.
4. Detects current saves.
5. Creates a profile from current saves.
6. Lists profiles.
7. Lets the user select a profile.
8. Backs up current active save.
9. Swaps selected profile into active save folder.
10. Launches the game.
11. Waits for game exit.
12. Copies updated saves back into selected profile.
13. Includes uninstall script.

---

## Second Milestone

Improve polish:

1. Better menu UI.
2. Rename profile.
3. Archive/delete profile.
4. Restore from backup.
5. Detect Steam Cloud risk.
6. Better error messages.
7. GitHub release packaging.
8. Optional compiled `.exe`.

---

## Edge Cases

Handle these:

- Game exe missing.
- Save directory missing.
- No profiles exist.
- Active saves exist but no profile exists.
- Selected profile folder is empty.
- Game is already running.
- Steam is running.
- Steam Cloud overwrites files.
- Copy fails due to permissions.
- Paths contain spaces or punctuation.
- User cancels at prompt.
- Previous launcher run was interrupted.
- Config references a deleted profile.
- Backup folder grows large.

---

## Suggested User-Facing Menu

Example:

```text
LibraryGame Launcher

Active profile: Main Playthrough

Profiles:
  1. Main Playthrough
  2. Speedrun Attempt
  3. Anti-Magic Master

Actions:
  N. New profile from current save
  B. Backup current save
  R. Restore from backup
  Q. Quit

Choose:
```

After selecting profile:

```text
Backing up current save...
Saving current active state to Main Playthrough...
Loading Speedrun Attempt...
Launching Librarian...

Waiting for game to close...
Game closed.
Saving updated progress to Speedrun Attempt...
Done.
```

---

## Notes for the Implementing Agent

Be careful with the user’s saves.

This project is mostly about trust.

The launcher should never make the user feel like their main save is at risk.

Prefer boring, explicit, reversible filesystem operations over clever behavior.

Start with a PowerShell implementation unless there is a strong reason to compile a binary immediately.

Keep the first version simple and reliable.

Do not implement automatic Steam Cloud disabling in the first pass. Add warnings and documentation instead.

Make sure `librarygame` can be run from `Win + R`.

Make sure the uninstaller exists from the beginning.

Make sure the README explains where every file goes.

The end result should feel like:

“I installed a tiny save manager. Now I type `librarygame`, pick a save, and the game opens with that save loaded.”