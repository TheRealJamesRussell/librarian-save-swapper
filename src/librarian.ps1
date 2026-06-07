param(
    [switch]$SkipMain,
    [switch]$Log,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$LauncherName = "librarian-save-swapper"
$DefaultGameExePath = "C:\Program Files (x86)\Steam\steamapps\common\Librarian Tidy Up the Arcane Library!\Librarian.exe"
$DefaultSavePath = "%LOCALAPPDATA%\Librarian\Saved\SaveGames"
$GameplaySaveFileName = "Sav.sav"
$ProfileVersionRetention = 5
$BackupRetention = 5
$AppRoot = Join-Path $env:APPDATA $LauncherName
$ProfilesRoot = Join-Path $AppRoot "profiles"
$BackupsRoot = Join-Path $AppRoot "backups"
$LogsRoot = Join-Path $AppRoot "logs"
$ConfigPath = Join-Path $AppRoot "config.json"
$LogPath = Join-Path $LogsRoot "launcher.log"
$VerboseLog = $Log -or ($RemainingArgs -contains "--log")

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Log {
    param([string]$Message)
    New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $Message"
}

function Write-DebugLog {
    param([string]$Message)
    if ($VerboseLog) {
        Write-Log "DEBUG: $Message"
    }
}

function Expand-LauncherPath {
    param([string]$Path)
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath((Expand-LauncherPath $Path))
}

function Ensure-Directories {
    foreach ($dir in @($AppRoot, $ProfilesRoot, $BackupsRoot, $LogsRoot)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-DefaultConfig {
    [ordered]@{
        version = 1
        gameExePath = $DefaultGameExePath
        savePath = $DefaultSavePath
        lastActiveProfile = $null
        waitForGameExit = $true
        backupBeforeSwitch = $true
    }
}

function Save-Config {
    param([object]$Config)
    $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Load-Config {
    Ensure-Directories
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $config = Get-DefaultConfig
        Save-Config $config
        Write-DebugLog "Created default config at '$ConfigPath'."
        return [pscustomobject]$config
    }

    Write-DebugLog "Loading config from '$ConfigPath'."
    $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $defaults = Get-DefaultConfig
    foreach ($key in $defaults.Keys) {
        if (-not $loaded.PSObject.Properties.Name.Contains($key)) {
            $loaded | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key]
        }
    }
    return $loaded
}

function Test-DirectoryHasFiles {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    return $null -ne (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-Profiles {
    if (-not (Test-Path -LiteralPath $ProfilesRoot)) {
        return ,@()
    }
    return ,@(Get-ChildItem -LiteralPath $ProfilesRoot -Directory | Sort-Object Name)
}

function Test-GameRunning {
    return $null -ne (Get-Process -Name "Librarian" -ErrorAction SilentlyContinue)
}

function Test-SteamRunning {
    return $null -ne (Get-Process -Name "steam" -ErrorAction SilentlyContinue)
}

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$DefaultValue = ""
    )

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
            $value = Read-Host $Prompt
        } else {
            $value = Read-Host "$Prompt [$DefaultValue]"
            if ([string]::IsNullOrWhiteSpace($value)) {
                $value = $DefaultValue
            }
        }

        $value = $value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
}

function Test-SafeProfileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0
}

function Test-SafeSavePath {
    param([string]$SavePath)

    $fullPath = Get-FullPath $SavePath
    $normalized = $fullPath.TrimEnd("\")
    $segments = $normalized -split "\\"
    if ($segments.Count -lt 3) {
        return $false
    }

    $leaf = $segments[$segments.Count - 1]
    $parent = $segments[$segments.Count - 2]
    $grandparent = $segments[$segments.Count - 3]
    return ($leaf -eq "SaveGames" -and $parent -eq "Saved" -and $grandparent -eq "Librarian")
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }

    $items = Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

function Clear-DirectoryContents {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return
    }

    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

function New-BackupName {
    param([string]$Reason)
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    return "${stamp}_${Reason}"
}

function New-VersionName {
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    return $stamp
}

function Get-UniqueChildPath {
    param(
        [string]$Parent,
        [string]$BaseName
    )

    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    $candidate = Join-Path $Parent $BaseName
    $suffix = 2
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $Parent ("{0}_{1}" -f $BaseName, $suffix)
        $suffix++
    }

    return $candidate
}

function New-UniqueChildDirectory {
    param(
        [string]$Parent,
        [string]$BaseName
    )

    $path = Get-UniqueChildPath -Parent $Parent -BaseName $BaseName
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Backup-Directory {
    param(
        [string]$Source,
        [string]$Reason
    )

    $backupPath = New-UniqueChildDirectory -Parent $BackupsRoot -BaseName (New-BackupName $Reason)
    Copy-DirectoryContents -Source $Source -Destination $backupPath
    Write-Log "Backed up '$Source' to '$backupPath'."
    Remove-OldBackups
    return $backupPath
}

function Remove-OldBackups {
    $backups = @(Get-ChildItem -LiteralPath $BackupsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($backups.Count -le $BackupRetention) {
        return
    }

    $backups | Select-Object -Skip $BackupRetention | ForEach-Object {
        Write-Log "Pruned old backup '$($_.FullName)'."
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Get-SaveHash {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-ProfileVersionDirectories {
    param([string]$ProfilePath)

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return
    }

    Get-ChildItem -LiteralPath $ProfilePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $GameplaySaveFileName) } |
        Sort-Object Name -Descending
}

function Get-LatestProfileSaveFile {
    param([string]$ProfilePath)

    $versions = @(Get-ProfileVersionDirectories -ProfilePath $ProfilePath)
    if ($versions.Count -gt 0) {
        return Join-Path $versions[0].FullName $GameplaySaveFileName
    }

    $legacySaveFile = Join-Path $ProfilePath $GameplaySaveFileName
    if (Test-Path -LiteralPath $legacySaveFile) {
        return $legacySaveFile
    }

    return $null
}

function Remove-OldProfileVersions {
    param([string]$ProfilePath)

    $versions = @(Get-ProfileVersionDirectories -ProfilePath $ProfilePath)
    if ($versions.Count -le $ProfileVersionRetention) {
        return
    }

    $versions | Select-Object -Skip $ProfileVersionRetention | ForEach-Object {
        Write-Log "Pruned old profile version '$($_.FullName)'."
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Save-ActiveToProfile {
    param(
        [string]$SavePath,
        [string]$ProfileName
    )

    if (-not (Test-SafeProfileName $ProfileName)) {
        throw "Profile name '$ProfileName' is not safe."
    }

    $profilePath = Join-Path $ProfilesRoot $ProfileName
    $activeSaveFile = Join-Path $SavePath $GameplaySaveFileName
    Write-DebugLog "Saving active save '$activeSaveFile' into profile '$ProfileName'."
    if (-not (Test-Path -LiteralPath $activeSaveFile)) {
        throw "Could not find gameplay save file: $activeSaveFile"
    }

    $latestProfileSaveFile = Get-LatestProfileSaveFile -ProfilePath $profilePath
    if (-not [string]::IsNullOrWhiteSpace($latestProfileSaveFile)) {
        $activeHash = Get-SaveHash -Path $activeSaveFile
        $profileHash = Get-SaveHash -Path $latestProfileSaveFile
        Write-DebugLog "Active hash '$activeHash'; latest profile hash '$profileHash'."
        if ($activeHash -eq $profileHash) {
            Write-Log "Skipped saving profile '$ProfileName' because active $GameplaySaveFileName is unchanged."
            return
        }
    }

    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
    $versionPath = New-UniqueChildDirectory -Parent $profilePath -BaseName (New-VersionName)
    Copy-Item -LiteralPath $activeSaveFile -Destination (Join-Path $versionPath $GameplaySaveFileName) -Force
    Remove-OldProfileVersions -ProfilePath $profilePath
    Write-DebugLog "Created profile version '$versionPath'."
    Write-Log "Saved active gameplay save to profile '$ProfileName' version '$versionPath'."
}

function Load-ProfileToActive {
    param(
        [string]$SavePath,
        [string]$ProfileName
    )

    if (-not (Test-SafeSavePath $SavePath)) {
        throw "Refusing to clear unexpected save path: $SavePath"
    }

    $profilePath = Join-Path $ProfilesRoot $ProfileName
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Profile '$ProfileName' does not exist."
    }

    $profileSaveFile = Get-LatestProfileSaveFile -ProfilePath $profilePath
    if ([string]::IsNullOrWhiteSpace($profileSaveFile)) {
        throw "Profile '$ProfileName' does not contain $GameplaySaveFileName."
    }

    Write-DebugLog "Loading latest profile save '$profileSaveFile' into '$SavePath'."
    New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
    Copy-Item -LiteralPath $profileSaveFile -Destination (Join-Path $SavePath $GameplaySaveFileName) -Force
    Write-Log "Loaded profile '$ProfileName' gameplay save into active save folder."
}

function Resolve-GameExe {
    param([object]$Config)

    $gameExe = Get-FullPath $Config.gameExePath
    if (Test-Path -LiteralPath $gameExe) {
        return $gameExe
    }

    Write-Warn "Could not find the game executable at:"
    Write-Host $gameExe
    $entered = Read-RequiredValue "Paste the full path to Librarian.exe, or type Q to quit"
    if ($entered -eq "Q") {
        exit 0
    }

    $enteredPath = Get-FullPath $entered.Trim('"')
    if (-not (Test-Path -LiteralPath $enteredPath)) {
        throw "That file does not exist: $enteredPath"
    }

    $Config.gameExePath = $enteredPath
    Save-Config $Config
    return $enteredPath
}

function Resolve-SavePath {
    param([object]$Config)

    $savePath = Get-FullPath $Config.savePath
    Write-DebugLog "Resolved save path '$savePath'."
    if (-not (Test-SafeSavePath $savePath)) {
        throw "Configured save path is not the expected Librarian\Saved\SaveGames folder: $savePath"
    }

    if (-not (Test-Path -LiteralPath $savePath)) {
        Write-Warn "Save folder does not exist yet:"
        Write-Host $savePath
        $answer = Read-Host "Create it now? [Y/N]"
        if ($answer -notmatch "^[Yy]$") {
            throw "Save folder is missing. Launch the game once or create the folder before switching profiles."
        }
        New-Item -ItemType Directory -Path $savePath -Force | Out-Null
        Write-Log "Created save folder '$savePath'."
    }

    return $savePath
}

function Initialize-FirstProfile {
    param(
        [object]$Config,
        [string]$SavePath
    )

    $profiles = Get-Profiles
    if ($profiles.Count -gt 0) {
        return
    }

    if (Test-DirectoryHasFiles $SavePath) {
        Write-Info "Found existing active save files, but no managed profiles yet."
        $answer = Read-Host "Create a profile from the current save? [Y/N]"
        if ($answer -match "^[Yy]$") {
            do {
                $profileName = Read-RequiredValue "Profile name" "Main Playthrough"
                if (-not (Test-SafeProfileName $profileName)) {
                    Write-Warn "Use a normal folder-safe profile name."
                }
            } while (-not (Test-SafeProfileName $profileName))

            New-Item -ItemType Directory -Path (Join-Path $ProfilesRoot $profileName) -Force | Out-Null
            Save-ActiveToProfile -SavePath $SavePath -ProfileName $profileName
            $Config.lastActiveProfile = $profileName
            Save-Config $Config
            Write-Info "Created profile '$profileName'."
        }
    }
}

function New-ProfileFromCurrentSave {
    param(
        [object]$Config,
        [string]$SavePath
    )

    do {
        $profileName = Read-RequiredValue "New profile name"
        if (-not (Test-SafeProfileName $profileName)) {
            Write-Warn "Use a normal folder-safe profile name."
            continue
        }
        $profilePath = Join-Path $ProfilesRoot $profileName
        if (Test-Path -LiteralPath $profilePath) {
            Write-Warn "That profile already exists."
            $profileName = ""
        }
    } while (-not (Test-SafeProfileName $profileName))

    New-Item -ItemType Directory -Path (Join-Path $ProfilesRoot $profileName) -Force | Out-Null
    Backup-Directory -Source $SavePath -Reason "before-new-profile" | Out-Null
    Save-ActiveToProfile -SavePath $SavePath -ProfileName $profileName
    $Config.lastActiveProfile = $profileName
    Save-Config $Config
    Write-Info "Created profile '$profileName' from the current save."
}

function Resolve-ActiveSaveMismatch {
    param(
        [object]$Config,
        [string]$SavePath
    )

    if ([string]::IsNullOrWhiteSpace($Config.lastActiveProfile)) {
        Write-DebugLog "No last active profile configured; skipping active save mismatch check."
        return
    }

    $activeSaveFile = Join-Path $SavePath $GameplaySaveFileName
    if (-not (Test-Path -LiteralPath $activeSaveFile)) {
        Write-DebugLog "Active save file missing; skipping mismatch check: '$activeSaveFile'."
        return
    }

    $lastProfilePath = Join-Path $ProfilesRoot $Config.lastActiveProfile
    if (-not (Test-Path -LiteralPath $lastProfilePath)) {
        Write-DebugLog "Last active profile path missing; skipping mismatch check: '$lastProfilePath'."
        return
    }

    $latestProfileSaveFile = Get-LatestProfileSaveFile -ProfilePath $lastProfilePath
    if ([string]::IsNullOrWhiteSpace($latestProfileSaveFile)) {
        Write-DebugLog "Last active profile has no save file; skipping mismatch check."
        return
    }

    $activeHash = Get-SaveHash -Path $activeSaveFile
    $profileHash = Get-SaveHash -Path $latestProfileSaveFile
    Write-DebugLog "Mismatch check active hash '$activeHash'; profile '$($Config.lastActiveProfile)' hash '$profileHash'."
    if ($activeHash -eq $profileHash) {
        return
    }

    Write-Host ""
    Write-Warn "The active game save differs from the last active profile: $($Config.lastActiveProfile)"
    Write-Host "This usually means the game was played outside this launcher."
    Write-Host ""
    Write-Host "Choose what to do with the current active save:"
    Write-Host "  [U] Update $($Config.lastActiveProfile) with the current active save"
    Write-Host "  [N] Create a new profile from the current active save"
    Write-Host "  [Q] Quit without changing anything"

    while ($true) {
        $choice = Read-Host "Choose"
        switch -Regex ($choice) {
            "^[Uu]$" {
                Write-DebugLog "User chose to update last active profile after hash mismatch."
                Backup-Directory -Source $SavePath -Reason "before-active-mismatch-update" | Out-Null
                Save-ActiveToProfile -SavePath $SavePath -ProfileName $Config.lastActiveProfile
                Save-Config $Config
                Write-Info "Updated '$($Config.lastActiveProfile)' with the current active save."
                return
            }
            "^[Nn]$" {
                Write-DebugLog "User chose to create a new profile after hash mismatch."
                New-ProfileFromCurrentSave -Config $Config -SavePath $SavePath
                return
            }
            "^[Qq]$" {
                Write-DebugLog "User quit after hash mismatch prompt."
                Write-Info "No profile was changed."
                exit 0
            }
            default {
                Write-Warn "Choose U, N, or Q."
            }
        }
    }
}

function Backup-CurrentSave {
    param([string]$SavePath)
    $backupPath = Backup-Directory -Source $SavePath -Reason "manual"
    Write-Info "Backup created:"
    Write-Host $backupPath
}

function Choose-Profile {
    param([string]$Prompt)

    $profiles = @(Get-Profiles)
    if ($profiles.Count -eq 0) {
        Write-Warn "No profiles found."
        return $null
    }

    Write-Host ""
    Write-Host "Profiles:"
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $profiles[$i].Name)
    }

    $choice = Read-Host $Prompt
    if ($choice -match "^[Qq]$") {
        return $null
    }

    $parsedChoice = 0
    if (-not [int]::TryParse($choice, [ref]$parsedChoice)) {
        Write-Warn "Invalid choice."
        return $null
    }

    $index = $parsedChoice - 1
    if ($index -lt 0 -or $index -ge $profiles.Count) {
        Write-Warn "Invalid choice."
        return $null
    }

    return $profiles[$index]
}

function Rename-Profile {
    param([object]$Config)

    $profile = Choose-Profile -Prompt "Choose a profile number to rename, or Q to cancel"
    if ($null -eq $profile) {
        return
    }

    do {
        $newName = Read-RequiredValue "New profile name"
        if (-not (Test-SafeProfileName $newName)) {
            Write-Warn "Use a normal folder-safe profile name."
            continue
        }
        $newPath = Join-Path $ProfilesRoot $newName
        if (Test-Path -LiteralPath $newPath) {
            Write-Warn "That profile already exists."
            $newName = ""
        }
    } while (-not (Test-SafeProfileName $newName))

    Rename-Item -LiteralPath $profile.FullName -NewName $newName
    if ($Config.lastActiveProfile -eq $profile.Name) {
        $Config.lastActiveProfile = $newName
        Save-Config $Config
    }
    Write-Log "Renamed profile '$($profile.Name)' to '$newName'."
    Write-Info "Renamed profile to '$newName'."
}

function Move-DirectoryToRecycleBin {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

function Delete-Profile {
    param([object]$Config)

    $profile = Choose-Profile -Prompt "Choose a profile number to delete, or Q to cancel"
    if ($null -eq $profile) {
        return
    }

    Write-Warn "This moves the profile to the Windows Recycle Bin."
    Write-Warn "You can restore it from there, or empty the Recycle Bin to remove it permanently."
    $confirm = Read-Host "Type DELETE to continue"
    if ($confirm -ne "DELETE") {
        Write-Info "Delete cancelled."
        return
    }

    Move-DirectoryToRecycleBin -Path $profile.FullName
    if ($Config.lastActiveProfile -eq $profile.Name) {
        $Config.lastActiveProfile = $null
        Save-Config $Config
    }
    Write-Log "Moved profile '$($profile.Name)' to the Windows Recycle Bin."
    Write-Info "Moved profile '$($profile.Name)' to the Windows Recycle Bin."
}

function Restore-FromBackup {
    param([string]$SavePath)

    $backups = @(Get-ChildItem -LiteralPath $BackupsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Warn "No backups found."
        return
    }

    Write-Host ""
    Write-Host "Backups:"
    for ($i = 0; $i -lt $backups.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $backups[$i].Name)
    }
    $choice = Read-Host "Choose a backup number, or Q to cancel"
    if ($choice -match "^[Qq]$") {
        return
    }
    $parsedChoice = 0
    if (-not [int]::TryParse($choice, [ref]$parsedChoice)) {
        Write-Warn "Invalid choice."
        return
    }

    $index = $parsedChoice - 1
    if ($index -lt 0 -or $index -ge $backups.Count) {
        Write-Warn "Invalid choice."
        return
    }

    $confirm = Read-Host "Restore this backup to the active save folder? This creates a backup first. Type RESTORE to continue"
    if ($confirm -ne "RESTORE") {
        Write-Info "Restore cancelled."
        return
    }

    Backup-Directory -Source $SavePath -Reason "before-restore" | Out-Null
    Clear-DirectoryContents -Path $SavePath
    Copy-DirectoryContents -Source $backups[$index].FullName -Destination $SavePath
    Write-Log "Restored backup '$($backups[$index].FullName)' to '$SavePath'."
    Write-Info "Backup restored."
}

function Start-SelectedProfile {
    param(
        [object]$Config,
        [string]$SavePath,
        [string]$GameExe,
        [string]$ProfileName
    )

    if (Test-GameRunning) {
        Write-Warn "The game appears to be running. Close it before switching save profiles."
        return
    }

    Write-Info "Backing up current save..."
    Write-DebugLog "Starting profile '$ProfileName' with game exe '$GameExe' and save path '$SavePath'."
    Backup-Directory -Source $SavePath -Reason "before-switch" | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($Config.lastActiveProfile)) {
        $lastProfilePath = Join-Path $ProfilesRoot $Config.lastActiveProfile
        if (Test-Path -LiteralPath $lastProfilePath) {
            Write-Info "Saving current active state to $($Config.lastActiveProfile)..."
            Save-ActiveToProfile -SavePath $SavePath -ProfileName $Config.lastActiveProfile
        }
    }

    Write-Info "Loading $ProfileName..."
    Load-ProfileToActive -SavePath $SavePath -ProfileName $ProfileName
    $Config.lastActiveProfile = $ProfileName
    Save-Config $Config

    Write-Info "Launching Librarian..."
    $process = Start-Process -FilePath $GameExe -PassThru
    Write-DebugLog "Started game process id '$($process.Id)'."
    Write-Log "Launched game process '$($process.Id)' with profile '$ProfileName'."

    if ($Config.waitForGameExit) {
        Write-Info "Waiting for game to close..."
        $process.WaitForExit()
        Write-DebugLog "Game process '$($process.Id)' exited with code '$($process.ExitCode)'."
        Write-Info "Game closed. Saving updated progress to $ProfileName..."
        Save-ActiveToProfile -SavePath $SavePath -ProfileName $ProfileName
        Save-Config $Config
        Write-Info "Done."
    }
}

function Show-Menu {
    param(
        [object]$Config,
        [string]$SavePath,
        [string]$GameExe
    )

    while ($true) {
        $profiles = Get-Profiles
        Clear-Host
        Write-Host "LibraryGame Launcher"
        Write-Host ""
        Write-Host "Active profile: $($Config.lastActiveProfile)"
        Write-Host ""
        Write-Host "Profiles:"
        if ($profiles.Count -eq 0) {
            Write-Host "  No profiles yet."
        } else {
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $profiles[$i].Name)
            }
        }
        Write-Host ""
        Write-Host "Actions:"
        Write-Host "  [N] New profile from current save"
        Write-Host "  [E] Rename profile"
        Write-Host "  [D] Delete profile"
        Write-Host "  [B] Backup current save"
        Write-Host "  [R] Restore from backup"
        Write-Host "  [Q] Quit"
        Write-Host ""

        $choice = Read-Host "Choose"
        switch -Regex ($choice) {
            "^[Qq]$" { return }
            "^[Nn]$" { New-ProfileFromCurrentSave -Config $Config -SavePath $SavePath; Pause; continue }
            "^[Ee]$" { Rename-Profile -Config $Config; Pause; continue }
            "^[Dd]$" { Delete-Profile -Config $Config; Pause; continue }
            "^[Bb]$" { Backup-CurrentSave -SavePath $SavePath; Pause; continue }
            "^[Rr]$" { Restore-FromBackup -SavePath $SavePath; Pause; continue }
            "^\d+$" {
                $index = [int]$choice - 1
                if ($index -ge 0 -and $index -lt $profiles.Count) {
                    Start-SelectedProfile -Config $Config -SavePath $SavePath -GameExe $GameExe -ProfileName $profiles[$index].Name
                    Pause
                    continue
                }
                Write-Warn "Invalid profile number."
                Pause
                continue
            }
            default {
                Write-Warn "Invalid choice."
                Pause
            }
        }
    }
}

if (-not $SkipMain) {
    try {
        Ensure-Directories
        Write-Log "Launcher started."
        if ($VerboseLog) {
            Write-Info "Troubleshooting log enabled:"
            Write-Host $LogPath
            Write-DebugLog "Raw arguments: $($RemainingArgs -join ' ')"
            Write-DebugLog "App root '$AppRoot'."
            Write-DebugLog "Profiles root '$ProfilesRoot'."
            Write-DebugLog "Backups root '$BackupsRoot'."
            Write-DebugLog "Config path '$ConfigPath'."
        }

        $config = Load-Config
        $savePath = Resolve-SavePath -Config $config
        Initialize-FirstProfile -Config $config -SavePath $savePath
        Resolve-ActiveSaveMismatch -Config $config -SavePath $savePath
        $gameExe = Resolve-GameExe -Config $config
        Write-DebugLog "Resolved game executable '$gameExe'."
        Write-DebugLog "Last active profile '$($config.lastActiveProfile)'."
        Write-DebugLog "waitForGameExit '$($config.waitForGameExit)'; backupBeforeSwitch '$($config.backupBeforeSwitch)'."

        Write-Warn "Steam Cloud warning: for safest profile switching, disable Steam Cloud for this game in Steam if it is available."
        if (Test-SteamRunning) {
            Write-Warn "Steam appears to be running. If Steam Cloud is enabled, it may sync or restore save files."
        }
        Start-Sleep -Milliseconds 800
        Show-Menu -Config $config -SavePath $savePath -GameExe $gameExe
    } catch {
        Write-Host ""
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Error: $($_.Exception.Message)"
        if ($VerboseLog) {
            Write-Log "Error details: $($_ | Out-String)"
            Write-Info "Troubleshooting log:"
            Write-Host $LogPath
        }
        exit 1
    }
}

