@echo off
:: Get the folder of this script
set SCRIPT_DIR=%~dp0

:: Run the PowerShell GUI backup script and wait
start "" /min powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File "%SCRIPT_DIR%main.ps1"

