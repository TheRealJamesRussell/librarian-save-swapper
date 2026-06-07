Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\librarian-save-swapper"
$AppDataDir = Join-Path $env:APPDATA "librarian-save-swapper"
$AppPathsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\librarian.exe"

if (Test-Path -LiteralPath $AppPathsKey) {
    Remove-Item -LiteralPath $AppPathsKey -Recurse -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $parts = @($userPath -split ";" | Where-Object { $_ -and ($_ -ne $InstallDir) })
    [Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "User")
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}

Write-Host "Removed launcher files and Win + R registration." -ForegroundColor Green
Write-Host ""

if (Test-Path -LiteralPath $AppDataDir) {
    Write-Host "Managed profiles and backups were kept at:"
    Write-Host $AppDataDir
    Write-Host ""
    $answer = Read-Host "Delete managed profiles, backups, logs, and config too? Type DELETE to confirm"
    if ($answer -eq "DELETE") {
        Get-ChildItem -LiteralPath $AppDataDir -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
        Write-Host "Deleted launcher-managed data." -ForegroundColor Yellow
        Write-Host "Left the empty data folder in place so Windows does not show a missing-location popup."
    } else {
        Write-Host "Kept launcher-managed data."
    }
}

