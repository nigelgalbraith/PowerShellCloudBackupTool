@echo off
:: Stop commands being printed in the console

set SCRIPT_DIR=%~dp0
:: Get the folder where this BAT file is located

powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%SCRIPT_DIR%app\main.ps1"
:: Run the PowerShell script from the app folder and hide the console window