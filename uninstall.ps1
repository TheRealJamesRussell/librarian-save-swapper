Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\librarygame-launcher"
$AppDataDir = Join-Path $env:APPDATA "librarygame-launcher"
$AppPathsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\librarygame.exe"

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
        Remove-Item -LiteralPath $AppDataDir -Recurse -Force
        Write-Host "Deleted launcher-managed data." -ForegroundColor Yellow
    } else {
        Write-Host "Kept launcher-managed data."
    }
}
