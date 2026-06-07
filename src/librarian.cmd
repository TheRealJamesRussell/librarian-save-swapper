@echo off
title Librarian Save Swapper
mode con: cols=65 lines=30 >nul 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0librarian.ps1" %*
