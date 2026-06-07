@echo off
mode con: cols=65 >nul 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0librarian.ps1" %*
