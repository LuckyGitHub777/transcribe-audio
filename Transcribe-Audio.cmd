@echo off
setlocal
set "ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%installer\Install-Transcribe-Audio.ps1" -Launch
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo.
  echo Transcribe Audio could not finish setup or transcription.
  echo The setup log is stored under %%LOCALAPPDATA%%\Transcribe Audio\logs.
  echo.
  pause
)
exit /b %RC%
