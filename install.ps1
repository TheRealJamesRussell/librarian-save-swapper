param(
    [string]$SourceRoot = "",
    [string]$RepositoryRawBase = "https://raw.githubusercontent.com/TheRealJamesRussell/librarian-save-swapper/main"
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\librarian-save-swapper"
$AppDataDir = Join-Path $env:APPDATA "librarian-save-swapper"
$AppPathsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\librarian.exe"

function Copy-FromLocalSource {
    param([string]$Root)

    $srcDir = Join-Path $Root "src"
    Copy-Item -LiteralPath (Join-Path $srcDir "librarian.ps1") -Destination (Join-Path $InstallDir "librarian.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $srcDir "librarian.cmd") -Destination (Join-Path $InstallDir "librarian.cmd") -Force
    Copy-Item -LiteralPath (Join-Path $Root "uninstall.ps1") -Destination (Join-Path $InstallDir "uninstall.ps1") -Force
    if (Test-Path -LiteralPath (Join-Path $Root "README.md")) {
        Copy-Item -LiteralPath (Join-Path $Root "README.md") -Destination (Join-Path $InstallDir "README-installed.txt") -Force
    }
}

function Copy-FromRemoteSource {
    param([string]$BaseUrl)

    $base = $BaseUrl.TrimEnd("/")
    Invoke-WebRequest -Uri "$base/src/librarian.ps1" -OutFile (Join-Path $InstallDir "librarian.ps1") -UseBasicParsing
    Invoke-WebRequest -Uri "$base/src/librarian.cmd" -OutFile (Join-Path $InstallDir "librarian.cmd") -UseBasicParsing
    Invoke-WebRequest -Uri "$base/uninstall.ps1" -OutFile (Join-Path $InstallDir "uninstall.ps1") -UseBasicParsing
    Invoke-WebRequest -Uri "$base/README.md" -OutFile (Join-Path $InstallDir "README-installed.txt") -UseBasicParsing
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $AppDataDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppDataDir "profiles") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppDataDir "backups") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppDataDir "archives") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppDataDir "logs") -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = $PSScriptRoot
}

if (-not [string]::IsNullOrWhiteSpace($SourceRoot) -and (Test-Path -LiteralPath (Join-Path $SourceRoot "src\librarian.ps1"))) {
    Copy-FromLocalSource -Root $SourceRoot
} elseif (-not [string]::IsNullOrWhiteSpace($RepositoryRawBase)) {
    Copy-FromRemoteSource -BaseUrl $RepositoryRawBase
} else {
    throw "Could not find local source files. Re-run from the repo folder or pass -RepositoryRawBase with a raw GitHub URL."
}

$configPath = Join-Path $AppDataDir "config.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    $defaultConfig = [ordered]@{
        version = 1
        gameExePath = "C:\Program Files (x86)\Steam\steamapps\common\Librarian Tidy Up the Arcane Library!\Librarian.exe"
        savePath = "%LOCALAPPDATA%\Librarian\Saved\SaveGames"
        lastActiveProfile = $null
        waitForGameExit = $true
        backupBeforeSwitch = $true
    }
    $defaultConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8
}

New-Item -Path $AppPathsKey -Force | Out-Null
Set-Item -Path $AppPathsKey -Value (Join-Path $InstallDir "librarian.cmd")
New-ItemProperty -Path $AppPathsKey -Name "Path" -Value $InstallDir -PropertyType String -Force | Out-Null

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $InstallDir) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $InstallDir } else { "$userPath;$InstallDir" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

Write-Host ""
Write-Host "librarian-save-swapper installed." -ForegroundColor Green
Write-Host "Run it with Win + R, then type: librarian"
Write-Host "Installed to: $InstallDir"
Write-Host "Profiles and backups live in: $AppDataDir"
Write-Host "Uninstall with: powershell -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""

