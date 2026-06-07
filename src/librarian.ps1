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
$DefaultSteamAppId = "4197610"
$GameProcessName = "Librarian"
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

function Write-Muted {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkGray
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
        launchMode = "steam"
        steamAppId = $DefaultSteamAppId
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
    return $null -ne (Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue)
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

function Read-InteractiveChoice {
    param(
        [string]$Title,
        [array]$Items,
        [scriptblock]$RenderItem,
        [string]$HelpText = "Use Up/Down, Enter to select, Esc to go back.",
        [scriptblock]$RenderHeader = $null,
        [switch]$AllowCancel
    )

    if ($Items.Count -eq 0) {
        return $null
    }

    function Write-ChoiceRow {
        param(
            [int]$Index,
            [bool]$IsSelected
        )

        $item = $Items[$Index]
        $label = & $RenderItem $item $Index
        $isDisabled = $item.PSObject.Properties.Name.Contains("Disabled") -and $item.Disabled
        $availableWidth = [Math]::Max(20, [Console]::WindowWidth - 1)
        $text = if ($IsSelected) { " > {0}" -f $label } else { "   {0}" -f $label }
        if ($text.Length -gt $availableWidth) {
            $text = $text.Substring(0, $availableWidth)
        }
        $text = $text.PadRight($availableWidth)

        if ($IsSelected) {
            Write-Host $text -ForegroundColor Black -BackgroundColor Cyan
        } elseif ($isDisabled) {
            Write-Host $text -ForegroundColor DarkGray
        } else {
            Write-Host $text -ForegroundColor White
        }
    }

    $selected = 0
    while (
        $selected -lt $Items.Count -and
        $Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and
        $Items[$selected].Disabled
    ) {
        $selected++
    }
    if ($selected -ge $Items.Count) {
        $selected = 0
    }
    [Console]::CursorVisible = $false
    Clear-Host
    Show-Header
    if ($null -ne $RenderHeader) {
        & $RenderHeader
        Write-Host ""
    }
    Write-Host $Title -ForegroundColor Cyan
    Write-Muted $HelpText
    Write-Host ""
    $itemsTop = [Console]::CursorTop
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-ChoiceRow -Index $i -IsSelected ($i -eq $selected)
    }

    while ($true) {
        $key = [Console]::ReadKey($true)
        $previous = $selected
        switch ($key.Key) {
            "UpArrow" {
                do {
                    if ($selected -le 0) {
                        $selected = $Items.Count - 1
                    } else {
                        $selected--
                    }
                    $isDisabled = $Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and $Items[$selected].Disabled
                } while ($isDisabled -and $selected -ne $previous)
            }
            "DownArrow" {
                do {
                    if ($selected -ge ($Items.Count - 1)) {
                        $selected = 0
                    } else {
                        $selected++
                    }
                    $isDisabled = $Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and $Items[$selected].Disabled
                } while ($isDisabled -and $selected -ne $previous)
            }
            "Home" {
                $selected = 0
                while (
                    $selected -lt $Items.Count -and
                    $Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and
                    $Items[$selected].Disabled
                ) {
                    $selected++
                }
                if ($selected -ge $Items.Count) {
                    $selected = $previous
                }
            }
            "End" {
                $selected = $Items.Count - 1
                while (
                    $selected -ge 0 -and
                    $Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and
                    $Items[$selected].Disabled
                ) {
                    $selected--
                }
                if ($selected -lt 0) {
                    $selected = $previous
                }
            }
            "Enter" {
                if ($Items[$selected].PSObject.Properties.Name.Contains("Disabled") -and $Items[$selected].Disabled) {
                    break
                }
                [Console]::CursorVisible = $true
                return $Items[$selected]
            }
            "Escape" {
                if ($AllowCancel) {
                    [Console]::CursorVisible = $true
                    return $null
                }
            }
        }

        if ($previous -ne $selected) {
            [Console]::SetCursorPosition(0, $itemsTop + $previous)
            Write-ChoiceRow -Index $previous -IsSelected $false
            [Console]::SetCursorPosition(0, $itemsTop + $selected)
            Write-ChoiceRow -Index $selected -IsSelected $true
            [Console]::SetCursorPosition(0, $itemsTop + $Items.Count)
        }
    }
}

function Confirm-Interactive {
    param(
        [string]$Title,
        [string]$ConfirmLabel,
        [string]$CancelLabel = "Cancel",
        [scriptblock]$RenderHeader = $null
    )

    $choices = @(
        [pscustomobject]@{ Value = $false; Label = $CancelLabel },
        [pscustomobject]@{ Value = $true; Label = $ConfirmLabel }
    )

    $choice = Read-InteractiveChoice `
        -Title $Title `
        -Items $choices `
        -RenderHeader $RenderHeader `
        -RenderItem { param($item, $index) $item.Label } `
        -AllowCancel

    return ($null -ne $choice -and $choice.Value)
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

function Get-ProfileLastPlayed {
    param([System.IO.DirectoryInfo]$Profile)

    if ($null -eq $Profile) {
        return $null
    }

    $versions = @(Get-ProfileVersionDirectories -ProfilePath $Profile.FullName)
    if ($versions.Count -eq 0) {
        return $null
    }

    $parsedDate = [datetime]::MinValue
    if ([datetime]::TryParseExact(
            $versions[0].Name,
            "yyyy-MM-dd_HH-mm-ss",
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsedDate
        )) {
        return $parsedDate
    }

    return $versions[0].LastWriteTime
}

function Format-ProfileLastPlayed {
    param([datetime]$LastPlayed)

    if ($LastPlayed -eq [datetime]::MinValue) {
        return ""
    }

    return "<{0}>" -f $LastPlayed.ToString("d MMMM, yyyy HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Limit-DisplayText {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -le $MaxLength) {
        return $Text
    }

    if ($MaxLength -le 3) {
        return $Text.Substring(0, [Math]::Max(0, $MaxLength))
    }

    return "{0}..." -f $Text.Substring(0, $MaxLength - 3)
}

function Format-PlayProfileLabel {
    param([System.IO.DirectoryInfo]$Profile)

    if ($null -eq $Profile) {
        return "Play profile: none"
    }

    $prefix = "Play profile: "
    $longestDateSuffix = " <30 September, 2026 23:59>"
    $maxSelectableLabelLength = 61
    $maxNameLength = $maxSelectableLabelLength - $prefix.Length - $longestDateSuffix.Length
    $profileName = Limit-DisplayText -Text $Profile.Name -MaxLength $maxNameLength

    $lastPlayed = Get-ProfileLastPlayed -Profile $Profile
    if ($null -eq $lastPlayed) {
        return "$prefix$profileName"
    }

    return "$prefix$profileName $(Format-ProfileLastPlayed -LastPlayed $lastPlayed)"
}

function New-ProfileVersionFromSaveFile {
    param(
        [string]$SourceSaveFile,
        [string]$ProfileName
    )

    if (-not (Test-SafeProfileName $ProfileName)) {
        throw "Profile name '$ProfileName' is not safe."
    }

    if (-not (Test-Path -LiteralPath $SourceSaveFile)) {
        throw "Could not find gameplay save file: $SourceSaveFile"
    }

    $profilePath = Join-Path $ProfilesRoot $ProfileName
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null

    $latestProfileSaveFile = Get-LatestProfileSaveFile -ProfilePath $profilePath
    if (-not [string]::IsNullOrWhiteSpace($latestProfileSaveFile)) {
        $sourceHash = Get-SaveHash -Path $SourceSaveFile
        $profileHash = Get-SaveHash -Path $latestProfileSaveFile
        Write-DebugLog "Source hash '$sourceHash'; latest profile hash '$profileHash'."
        if ($sourceHash -eq $profileHash) {
            Write-Log "Skipped saving profile '$ProfileName' because $GameplaySaveFileName is unchanged."
            return $null
        }
    }

    $versionPath = New-UniqueChildDirectory -Parent $profilePath -BaseName (New-VersionName)
    Copy-Item -LiteralPath $SourceSaveFile -Destination (Join-Path $versionPath $GameplaySaveFileName) -Force
    Remove-OldProfileVersions -ProfilePath $profilePath
    Write-DebugLog "Created profile version '$versionPath'."
    Write-Log "Saved gameplay save to profile '$ProfileName' version '$versionPath'."
    return $versionPath
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
    New-ProfileVersionFromSaveFile -SourceSaveFile $activeSaveFile -ProfileName $ProfileName | Out-Null
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

function Resolve-LaunchSettings {
    param([object]$Config)

    if ([string]::IsNullOrWhiteSpace($Config.launchMode)) {
        $Config.launchMode = "steam"
    }

    if ([string]::IsNullOrWhiteSpace($Config.steamAppId)) {
        $Config.steamAppId = $DefaultSteamAppId
    }

    if ($Config.launchMode -eq "direct") {
        Resolve-GameExe -Config $Config | Out-Null
    }

    Save-Config $Config
}

function Start-GameAndWait {
    param([object]$Config)

    if ($Config.launchMode -eq "direct") {
        $gameExe = Resolve-GameExe -Config $Config
        Write-Info "Launching Librarian..."
        $process = Start-Process -FilePath $gameExe -PassThru
        Write-DebugLog "Started direct game process id '$($process.Id)'."
        Write-Log "Launched game process '$($process.Id)' directly."

        if ($Config.waitForGameExit) {
            Write-Info "Waiting for game to close..."
            $process.WaitForExit()
            Write-DebugLog "Game process '$($process.Id)' exited with code '$($process.ExitCode)'."
        }
        return $true
    }

    $steamUrl = "steam://rungameid/$($Config.steamAppId)"
    Write-Info "Launching Librarian through Steam..."
    Write-DebugLog "Launching Steam URL '$steamUrl'."
    Start-Process $steamUrl | Out-Null
    Write-Log "Requested Steam launch for app id '$($Config.steamAppId)'."

    if (-not $Config.waitForGameExit) {
        return $true
    }

    Write-Info "Waiting for game process to start..."
    $process = $null
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        $process = Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $process) {
            break
        }
        Start-Sleep -Seconds 1
    }

    if ($null -eq $process) {
        Write-Warn "Steam launch was requested, but $GameProcessName did not start within 3 minutes."
        Write-Warn "If Steam is updating or waiting for input, run librarian again after the game closes so the active save can be captured."
        Write-Log "Timed out waiting for '$GameProcessName' after Steam launch."
        return $false
    }

    Write-DebugLog "Detected Steam-launched game process id '$($process.Id)'."
    Write-Log "Detected Steam-launched game process '$($process.Id)'."
    Write-Info "Waiting for game to close..."
    $process.WaitForExit()
    Write-DebugLog "Steam-launched game process '$($process.Id)' exited."
    return $true
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
            return $true
        }
    }
    return $false
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
    return $true
}

function Read-NewProfileName {
    param([string]$Prompt = "New profile name")

    do {
        $profileName = Read-RequiredValue $Prompt
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

    return $profileName
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

    $choices = @(
        [pscustomobject]@{ Mode = "update"; Label = "Update $($Config.lastActiveProfile) with the current active save" },
        [pscustomobject]@{ Mode = "new"; Label = "Create a new profile from the current active save" },
        [pscustomobject]@{ Mode = "quit"; Label = "Quit without changing anything" }
    )
    $choice = Read-InteractiveChoice `
        -Title "Choose what to do with the current active save" `
        -Items $choices `
        -RenderItem { param($item, $index) $item.Label }

    switch ($choice.Mode) {
        "update" {
            Write-DebugLog "User chose to update last active profile after hash mismatch."
            Backup-Directory -Source $SavePath -Reason "before-active-mismatch-update" | Out-Null
            Save-ActiveToProfile -SavePath $SavePath -ProfileName $Config.lastActiveProfile
            Save-Config $Config
            Write-Info "Updated '$($Config.lastActiveProfile)' with the current active save."
            return
        }
        "new" {
            Write-DebugLog "User chose to create a new profile after hash mismatch."
            New-ProfileFromCurrentSave -Config $Config -SavePath $SavePath | Out-Null
            return
        }
        "quit" {
            Write-DebugLog "User quit after hash mismatch prompt."
            Write-Info "No profile was changed."
            exit 0
        }
    }
}

function Save-CurrentSave {
    param(
        [object]$Config,
        [string]$SavePath
    )

    $choices = @(
        [pscustomobject]@{ Label = "Create new profile from current save"; Mode = "new" },
        [pscustomobject]@{ Label = "Update existing profile with current save"; Mode = "update" },
        [pscustomobject]@{ Label = "Cancel"; Mode = "cancel" }
    )

    $choice = Read-InteractiveChoice `
        -Title "Capture current save" `
        -Items $choices `
        -RenderItem { param($item, $index) $item.Label } `
        -AllowCancel

    if ($null -eq $choice -or $choice.Mode -eq "cancel") {
        return $false
    }

    if ($choice.Mode -eq "new") {
        return (New-ProfileFromCurrentSave -Config $Config -SavePath $SavePath)
    }

    $profile = Choose-Profile -Prompt "Choose a profile to update"
    if ($null -eq $profile) {
        return $false
    }
    Backup-Directory -Source $SavePath -Reason "before-manual-profile-backup" | Out-Null
    Save-ActiveToProfile -SavePath $SavePath -ProfileName $profile.Name
    $Config.lastActiveProfile = $profile.Name
    Save-Config $Config
    Write-Info "Saved current active save into '$($profile.Name)'."
    return $true
}

function Choose-Profile {
    param([string]$Prompt)

    $profiles = @(Get-Profiles)
    if ($profiles.Count -eq 0) {
        Write-Warn "No profiles found."
        return $null
    }

    return Read-InteractiveChoice `
        -Title $Prompt `
        -Items $profiles `
        -RenderItem { param($item, $index) $item.Name } `
        -AllowCancel
}

function Rename-Profile {
    param([object]$Config)

    $profile = Choose-Profile -Prompt "Choose a profile to rename"
    if ($null -eq $profile) {
        return $false
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
    return $false
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

    $profile = Choose-Profile -Prompt "Choose a profile to delete"
    if ($null -eq $profile) {
        return $false
    }

    $confirm = Confirm-Interactive `
        -Title "Delete profile?" `
        -ConfirmLabel "Move '$($profile.Name)' to the Recycle Bin" `
        -RenderHeader {
            Write-Warn "This moves the profile to the Recycle Bin."
            Write-Muted "You can restore it from there, or empty the Recycle Bin to remove it permanently."
        }
    if (-not $confirm) {
        return $false
    }

    Move-DirectoryToRecycleBin -Path $profile.FullName
    if ($Config.lastActiveProfile -eq $profile.Name) {
        $Config.lastActiveProfile = $null
        Save-Config $Config
    }
    Write-Log "Moved profile '$($profile.Name)' to the Recycle Bin."
    Write-Info "Moved profile '$($profile.Name)' to the Recycle Bin."
    return $true
}

function Restore-ProfileVersion {
    param(
        [object]$Config,
        [string]$SavePath
    )

    $profile = Choose-Profile -Prompt "Choose a profile to restore from"
    if ($null -eq $profile) {
        return $false
    }

    $versions = @(Get-ProfileVersionDirectories -ProfilePath $profile.FullName)
    if ($versions.Count -eq 0) {
        Write-Warn "That profile has no saved versions."
        return $true
    }

    $selectedVersion = Read-InteractiveChoice `
        -Title "Restore profile version" `
        -Items $versions `
        -RenderHeader { Write-Host "Profile: $($profile.Name)" -ForegroundColor Yellow } `
        -RenderItem { param($item, $index) $item.Name } `
        -AllowCancel

    if ($null -eq $selectedVersion) {
        return $false
    }

    $confirm = Confirm-Interactive `
        -Title "Restore this version?" `
        -ConfirmLabel "Restore $($profile.Name) version $($selectedVersion.Name)" `
        -RenderHeader {
            Write-Warn "The active save will be backed up first."
        }
    if (-not $confirm) {
        return $false
    }

    Backup-Directory -Source $SavePath -Reason "before-restore" | Out-Null
    $selectedSaveFile = Join-Path $selectedVersion.FullName $GameplaySaveFileName
    New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
    Copy-Item -LiteralPath $selectedSaveFile -Destination (Join-Path $SavePath $GameplaySaveFileName) -Force
    New-ProfileVersionFromSaveFile -SourceSaveFile $selectedSaveFile -ProfileName $profile.Name | Out-Null
    $Config.lastActiveProfile = $profile.Name
    Save-Config $Config
    Write-Log "Restored profile '$($profile.Name)' version '$($selectedVersion.Name)' to active save folder."
    Write-Info "Restored '$($profile.Name)' version '$($selectedVersion.Name)'."
    return $true
}

function Start-SelectedProfile {
    param(
        [object]$Config,
        [string]$SavePath,
        [string]$ProfileName
    )

    if (Test-GameRunning) {
        Write-Warn "The game appears to be running. Close it before switching save profiles."
        return $false
    }

    Write-Info "Backing up current save..."
    Write-DebugLog "Starting profile '$ProfileName' with launch mode '$($Config.launchMode)' and save path '$SavePath'."
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

    $gameClosed = Start-GameAndWait -Config $Config
    if ($Config.waitForGameExit -and $gameClosed) {
        Write-Info "Game closed. Saving updated progress to $ProfileName..."
        Save-ActiveToProfile -SavePath $SavePath -ProfileName $ProfileName
        Save-Config $Config
        Write-Info "Done."
    }
    return $true
}

function Start-NewPlaythrough {
    param(
        [object]$Config,
        [string]$SavePath
    )

    if (Test-GameRunning) {
        Write-Warn "The game appears to be running. Close it before starting a new playthrough."
        return $false
    }

    $profileName = Read-NewProfileName -Prompt "New playthrough profile name"
    $activeSaveFile = Join-Path $SavePath $GameplaySaveFileName

    $confirm = Confirm-Interactive `
        -Title "Start new playthrough?" `
        -ConfirmLabel "Back up current save and start new playthrough" `
        -RenderHeader {
            Write-Warn "This starts the game without an existing $GameplaySaveFileName."
            Write-Muted "The current active save is backed up first."
        }
    if (-not $confirm) {
        return $false
    }

    Backup-Directory -Source $SavePath -Reason "before-new-playthrough" | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($Config.lastActiveProfile)) {
        $lastProfilePath = Join-Path $ProfilesRoot $Config.lastActiveProfile
        if ((Test-Path -LiteralPath $lastProfilePath) -and (Test-Path -LiteralPath $activeSaveFile)) {
            Write-Info "Saving current active state to $($Config.lastActiveProfile)..."
            Save-ActiveToProfile -SavePath $SavePath -ProfileName $Config.lastActiveProfile
        }
    }

    New-Item -ItemType Directory -Path (Join-Path $ProfilesRoot $profileName) -Force | Out-Null
    if (Test-Path -LiteralPath $activeSaveFile) {
        Remove-Item -LiteralPath $activeSaveFile -Force
        Write-Log "Removed active $GameplaySaveFileName before starting new playthrough '$profileName'."
    }

    $Config.lastActiveProfile = $profileName
    Save-Config $Config

    $gameClosed = Start-GameAndWait -Config $Config
    if ($Config.waitForGameExit -and $gameClosed) {
        if (Test-Path -LiteralPath $activeSaveFile) {
            Write-Info "Game closed. Saving new playthrough to $profileName..."
            Save-ActiveToProfile -SavePath $SavePath -ProfileName $profileName
            Save-Config $Config
            Write-Info "Done."
        } else {
            Write-Warn "Game closed, but no $GameplaySaveFileName was found."
            Write-Warn "Launch the game and create a save before using this profile."
            Write-Log "No $GameplaySaveFileName found after new playthrough '$profileName' exited."
        }
    }
    return $true
}

function Show-Header {
    $shelf = @(
        @(
            @{ Text = "             .--.           "; Color = "DarkYellow" },
            @{ Text = ".---."; Color = "DarkCyan" },
            @{ Text = "        .-."; Color = "DarkGreen" }
        ),
        @(
            @{ Text = "         .---"; Color = "DarkYellow" },
            @{ Text = "|--|"; Color = "Yellow" },
            @{ Text = "   .-.     "; Color = "DarkGray" },
            @{ Text = "| M |"; Color = "DarkCyan" },
            @{ Text = "  .---. "; Color = "DarkMagenta" },
            @{ Text = "|~|"; Color = "Green" },
            @{ Text = "    .--."; Color = "DarkBlue" }
        ),
        @(
            @{ Text = "      .--"; Color = "DarkYellow" },
            @{ Text = "|===|SH|"; Color = "Yellow" },
            @{ Text = "---|_|--.__"; Color = "DarkGray" },
            @{ Text = "| A |"; Color = "DarkCyan" },
            @{ Text = "--|:::| "; Color = "DarkMagenta" },
            @{ Text = "|~|"; Color = "Green" },
            @{ Text = "-==-"; Color = "DarkGray" },
            @{ Text = "|==|"; Color = "DarkBlue" },
            @{ Text = "---."; Color = "DarkGray" }
        ),
        @(
            @{ Text = "      "; Color = "DarkGray" },
            @{ Text = "|%%|SIM|EL|"; Color = "Yellow" },
            @{ Text = "===| |~~"; Color = "DarkGray" },
            @{ Text = "|%%| G |"; Color = "DarkCyan" },
            @{ Text = "--|   |_|"; Color = "DarkMagenta" },
            @{ Text = "~|"; Color = "Green" },
            @{ Text = "TIDY"; Color = "Blue" },
            @{ Text = "|  |___|-."; Color = "DarkBlue" }
        ),
        @(
            @{ Text = "      "; Color = "DarkGray" },
            @{ Text = "|  |   |VI|"; Color = "Yellow" },
            @{ Text = "===| |=="; Color = "DarkGray" },
            @{ Text = "|  | I |"; Color = "DarkCyan" },
            @{ Text = "  |:::|=| "; Color = "DarkMagenta" },
            @{ Text = "|    |"; Color = "Blue" },
            @{ Text = "3K"; Color = "DarkBlue" },
            @{ Text = "|---|=|"; Color = "DarkGray" }
        ),
        @(
            @{ Text = "      "; Color = "DarkGray" },
            @{ Text = "|  |   |NG|"; Color = "Yellow" },
            @{ Text = "   |_|__"; Color = "DarkGray" },
            @{ Text = "|  | C |"; Color = "DarkCyan" },
            @{ Text = "__|   | | "; Color = "DarkMagenta" },
            @{ Text = "|    |"; Color = "Blue" },
            @{ Text = "  |___| |"; Color = "DarkBlue" }
        ),
        @(
            @{ Text = "      "; Color = "DarkGray" },
            @{ Text = "|~~|===|--|"; Color = "Yellow" },
            @{ Text = "===|~|~~"; Color = "DarkGray" },
            @{ Text = "|%%|~~~|"; Color = "DarkCyan" },
            @{ Text = "--|:::|=|"; Color = "DarkMagenta" },
            @{ Text = "~|----|"; Color = "Blue" },
            @{ Text = "==|---|=|"; Color = "DarkBlue" }
        ),
        @(
            @{ Text = "      ^--^---'--^---^-^--^--^---'--^---^-^-^-==-^--^---^-'"; Color = "DarkGray" }
        ),
        @(
            @{ Text = "      .---------------------------------------------------."; Color = "DarkGray" }
        ),
        @(
            @{ Text = "      |"; Color = "DarkGray" },
            @{ Text = "    L I B R A R I A N   S A V E   S W A P P E R    "; Color = "Cyan" },
            @{ Text = "|"; Color = "DarkGray" }
        ),
        @(
            @{ Text = "      '---------------------------------------------------'"; Color = "DarkGray" }
        )
    )

    foreach ($line in $shelf) {
        foreach ($segment in $line) {
            Write-Host $segment.Text -ForegroundColor $segment.Color -NoNewline
        }
        Write-Host ""
    }
    Write-Host ""
}

function Choose-OtherProfile {
    param([array]$Profiles)

    if ($Profiles.Count -eq 0) {
        return $null
    }

    return Read-InteractiveChoice `
        -Title "Pick other profile" `
        -Items $Profiles `
        -RenderItem { param($item, $index) $item.Name } `
        -AllowCancel
}

function Show-Menu {
    param(
        [object]$Config,
        [string]$SavePath
    )

    while ($true) {
        $profiles = @(Get-Profiles)
        $menuItems = @()

        $primaryProfile = $null
        if (-not [string]::IsNullOrWhiteSpace($Config.lastActiveProfile)) {
            $primaryProfile = $profiles | Where-Object { $_.Name -eq $Config.lastActiveProfile } | Select-Object -First 1
        }
        if ($null -eq $primaryProfile -and $profiles.Count -gt 0) {
            $primaryProfile = $profiles[0]
        }

        if ($null -eq $primaryProfile) {
            $menuItems += [pscustomobject]@{
                Kind = "profile"
                Key = ""
                Label = (Format-PlayProfileLabel -Profile $null)
                Profile = $null
                Disabled = $true
            }
        } else {
            $menuItems += [pscustomobject]@{
                Kind = "profile"
                Key = ""
                Label = (Format-PlayProfileLabel -Profile $primaryProfile)
                Profile = $primaryProfile
                Disabled = $false
            }
        }

        $otherProfiles = @($profiles | Where-Object { $null -eq $primaryProfile -or $_.Name -ne $primaryProfile.Name })
        $menuItems += [pscustomobject]@{
            Kind = "action"
            Key = "O"
            Label = "Pick Other Profile"
            Profile = $null
            OtherProfiles = $otherProfiles
            Disabled = ($otherProfiles.Count -eq 0)
        }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "C"; Label = "Capture current save"; Profile = $null }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "S"; Label = "Start new playthrough"; Profile = $null }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "E"; Label = "Rename profile"; Profile = $null }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "D"; Label = "Delete profile"; Profile = $null }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "R"; Label = "Restore profile version"; Profile = $null }
        $menuItems += [pscustomobject]@{ Kind = "action"; Key = "Q"; Label = "Quit"; Profile = $null }

        $selected = Read-InteractiveChoice `
            -Title "Main menu" `
            -Items $menuItems `
            -HelpText "Use Up/Down, Enter to select, Esc to quit." `
            -RenderHeader {
                if ([string]::IsNullOrWhiteSpace($Config.lastActiveProfile)) {
                    Write-Host "Active profile: none" -ForegroundColor DarkGray
                } else {
                    Write-Host "Active profile: $($Config.lastActiveProfile)" -ForegroundColor Yellow
                }
            } `
            -RenderItem {
                param($item, $index)
                $item.Label
            } `
            -AllowCancel

        if ($null -eq $selected) {
            return
        }

        if ($selected.Kind -eq "profile") {
            if ($null -eq $selected.Profile) {
                continue
            }
            $didWork = Start-SelectedProfile -Config $Config -SavePath $SavePath -ProfileName $selected.Profile.Name
            if ($didWork) {
                Pause
            }
            continue
        }

        $didWork = $false
        switch ($selected.Key) {
            "Q" { return }
            "O" {
                $otherProfile = Choose-OtherProfile -Profiles $selected.OtherProfiles
                if ($null -ne $otherProfile) {
                    $didWork = Start-SelectedProfile -Config $Config -SavePath $SavePath -ProfileName $otherProfile.Name
                }
            }
            "C" { $didWork = Save-CurrentSave -Config $Config -SavePath $SavePath }
            "S" { $didWork = Start-NewPlaythrough -Config $Config -SavePath $SavePath }
            "E" { $didWork = Rename-Profile -Config $Config }
            "D" { $didWork = Delete-Profile -Config $Config }
            "R" { $didWork = Restore-ProfileVersion -Config $Config -SavePath $SavePath }
            default {
                Write-Warn "Invalid choice."
                $didWork = $true
            }
        }

        if ($didWork) {
            Pause
        }
        continue
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
        Resolve-LaunchSettings -Config $config
        Write-DebugLog "Launch mode '$($config.launchMode)'; Steam app id '$($config.steamAppId)'."
        Write-DebugLog "Last active profile '$($config.lastActiveProfile)'."
        Write-DebugLog "waitForGameExit '$($config.waitForGameExit)'; backupBeforeSwitch '$($config.backupBeforeSwitch)'."

        Show-Menu -Config $config -SavePath $savePath
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

