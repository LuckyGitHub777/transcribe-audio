@echo off
setlocal
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%installer\Uninstall-Transcribe-Audio.ps1" %*
exit /b %errorlevel%
