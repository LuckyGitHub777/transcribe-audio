#requires -Version 5.1
[CmdletBinding()]
param([switch]$RemoveUserData)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$InstallRoot=Join-Path $env:LOCALAPPDATA 'Programs\Transcribe Audio'
$StateRoot=Join-Path $env:LOCALAPPDATA 'Transcribe Audio'
$RuntimeRoot=Join-Path $StateRoot 'runtime'
$BinRoot=Join-Path $StateRoot 'bin'
$LogRoot=Join-Path $StateRoot 'logs'

$LegacyInstallRoot=Join-Path $env:LOCALAPPDATA 'Programs\GoTranscribe'
$LegacyStateRoot=Join-Path $env:LOCALAPPDATA 'GoTranscribe'
$LegacyBinRoot=Join-Path $LegacyStateRoot 'bin'

if(Test-Path $InstallRoot){Remove-Item $InstallRoot -Recurse -Force}
if(Test-Path $LegacyInstallRoot){Remove-Item $LegacyInstallRoot -Recurse -Force -ErrorAction SilentlyContinue}

$userPath=[Environment]::GetEnvironmentVariable('Path','User')
if($userPath){
    $parts=@($userPath -split ';' | Where-Object {$_ -and $_ -ine $BinRoot -and $_ -ine $LegacyBinRoot})
    [Environment]::SetEnvironmentVariable('Path',($parts -join ';'),'User')
}

foreach($path in @($BinRoot,$RuntimeRoot,$LogRoot,$LegacyBinRoot,(Join-Path $LegacyStateRoot 'runtime'),(Join-Path $LegacyStateRoot 'logs'))){
    if(Test-Path $path){Remove-Item $path -Recurse -Force}
}

if($RemoveUserData){
    if(Test-Path $StateRoot){Remove-Item $StateRoot -Recurse -Force}
    Write-Host 'Transcribe Audio and local preferences/vocabulary removed.' -ForegroundColor Green
}else{
    Write-Host 'Transcribe Audio removed. Private preferences and vocabulary were preserved.' -ForegroundColor Green
}
Write-Host 'Runtime/cache removed.' -ForegroundColor Green
Write-Host 'Your transcripts were not removed.' -ForegroundColor Green
