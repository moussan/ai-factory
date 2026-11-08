@echo off
rem Double-click to launch. Pass-through args work, e.g.  Start-MSADKit.cmd -Azure
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MS-AD-Kit.ps1" %*
if errorlevel 1 pause
