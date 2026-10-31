#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipRuntime,
    [switch]$ForceCpu,
    [switch]$Launch,
    [switch]$VerboseSetup
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$PackageRoot=Split-Path -Parent $PSScriptRoot
$InstallRoot=Join-Path $env:LOCALAPPDATA 'Programs\Transcribe Audio'
$StateRoot=Join-Path $env:LOCALAPPDATA 'Transcribe Audio'
$RuntimeRoot=Join-Path $StateRoot 'runtime'
$BinRoot=Join-Path $StateRoot 'bin'
$LogRoot=Join-Path $StateRoot 'logs'
$SetupLog=Join-Path $LogRoot ('setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$WhisperVersion='20250625'
$TorchVersion='2.11.0'

function Say([string]$s){Write-Host $s}
function Ok([string]$s){Write-Host ('  [OK] '+$s) -ForegroundColor Green}
function Info([string]$s){Write-Host ('  '+$s) -ForegroundColor DarkGray}
function Warn([string]$s){Write-Host ('  '+$s) -ForegroundColor Yellow}
function Refresh-Path {
    $machine=[Environment]::GetEnvironmentVariable('Path','Machine')
    $user=[Environment]::GetEnvironmentVariable('Path','User')
    $links=Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $env:PATH=@($machine,$user,$links) -join ';'
}
function Find-Python311 {
    $py=Get-Command py.exe -ErrorAction SilentlyContinue
    if($py){
        $probe=& $py.Source -3.11 -c 'import sys; print(sys.executable)' 2>$null
        if($LASTEXITCODE -eq 0 -and $probe){return [string]($probe|Select-Object -First 1)}
    }
    $candidates=@(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
        (Join-Path $env:ProgramFiles 'Python311\python.exe')
    )
    foreach($p in $candidates){if(Test-Path -LiteralPath $p -PathType Leaf){return $p}}
    $null
}
function Ensure-WinGetPackage([string]$Id,[string]$Friendly){
    Refresh-Path
    if(-not(Get-Command winget.exe -ErrorAction SilentlyContinue)){
        throw "Windows Package Manager is needed to install $Friendly automatically."
    }
    Say("Preparing $Friendly...")
    & winget.exe install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements --silent
    if($LASTEXITCODE -ne 0){throw "$Friendly setup did not complete (winget code $LASTEXITCODE)."}
    Refresh-Path
}
function Test-Nvidia {
    Refresh-Path
    if(Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue){return $true}
    try{return [bool](Get-CimInstance Win32_VideoController | Where-Object {$_.Name -match 'NVIDIA'} | Select-Object -First 1)}catch{return $false}
}
function Invoke-QuietProcess {
    param([string]$Title,[string]$FilePath,[string[]]$Arguments)
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
    $outFile=Join-Path $LogRoot ('.setup-out-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $errFile=Join-Path $LogRoot ('.setup-err-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try{
        Say($Title)
        $p=Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $sw=[Diagnostics.Stopwatch]::StartNew()
        while(-not $p.HasExited){
            Write-Progress -Activity $Title -Status ('Elapsed {0:mm\:ss}' -f $sw.Elapsed)
            Start-Sleep -Milliseconds 600
            $p.Refresh()
        }
        $p.WaitForExit();$sw.Stop();Write-Progress -Activity $Title -Completed
        Add-Content -LiteralPath $SetupLog -Value ("`r`n=== $Title ===") -Encoding UTF8
        if(Test-Path $outFile){Get-Content $outFile -ErrorAction SilentlyContinue | Add-Content -LiteralPath $SetupLog -Encoding UTF8}
        if(Test-Path $errFile){Get-Content $errFile -ErrorAction SilentlyContinue | Add-Content -LiteralPath $SetupLog -Encoding UTF8}
        if($VerboseSetup){
            if(Test-Path $outFile){Get-Content $outFile -ErrorAction SilentlyContinue | Write-Host}
            if(Test-Path $errFile){Get-Content $errFile -ErrorAction SilentlyContinue | Write-Host}
        }
        return [int]$p.ExitCode
    }finally{
        Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
    }
}
function Read-RuntimeProbe([string]$PythonExe,[switch]$TorchOnly){
    $probe=Join-Path $InstallRoot 'transcribe_audio_probe.py'
    if(-not(Test-Path -LiteralPath $PythonExe -PathType Leaf) -or -not(Test-Path -LiteralPath $probe -PathType Leaf)){return $null}
    $args=@($probe);if($TorchOnly){$args+='--torch-only'}
    $raw=& $PythonExe @args 2>$null
    if($LASTEXITCODE -ne 0 -or -not $raw){return $null}
    try{return (($raw -join "`n")|ConvertFrom-Json)}catch{return $null}
}
function Test-RuntimeHealthy([object]$Probe){
    if(-not $Probe -or -not $Probe.ok){return $false}
    if([string]$Probe.whisper -ne $WhisperVersion){return $false}
    if(-not([string]$Probe.torch).StartsWith($TorchVersion)){return $false}
    $sv=[string]$Probe.setuptools
    $major=0
    if($sv -ne 'missing'){$null=[int]::TryParse(($sv -split '\.')[0],[ref]$major)}
    if($major -ge 82){return $false}
    return $true
}

$LegacyInstallRoot=Join-Path $env:LOCALAPPDATA 'Programs\GoTranscribe'
$LegacyStateRoot=Join-Path $env:LOCALAPPDATA 'GoTranscribe'
$LegacyBinRoot=Join-Path $LegacyStateRoot 'bin'

function Move-LegacyState {
    if(-not(Test-Path -LiteralPath $LegacyStateRoot -PathType Container)){return $false}
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    foreach($name in @('config.json','Vocabulary.txt')){
        $old=Join-Path $LegacyStateRoot $name
        $new=Join-Path $StateRoot $name
        if((Test-Path -LiteralPath $old -PathType Leaf) -and -not(Test-Path -LiteralPath $new -PathType Leaf)){
            Copy-Item -LiteralPath $old -Destination $new -Force
        }
    }
    $oldRuntime=Join-Path $LegacyStateRoot 'runtime'
    if((Test-Path -LiteralPath $oldRuntime -PathType Container) -and -not(Test-Path -LiteralPath $RuntimeRoot -PathType Container)){
        Move-Item -LiteralPath $oldRuntime -Destination $RuntimeRoot
    }
    return $true
}

function Remove-LegacyInstall {
    $legacyLauncher=Join-Path $LegacyBinRoot 'gotranscribe.cmd'
    if(Test-Path -LiteralPath $legacyLauncher){Remove-Item -LiteralPath $legacyLauncher -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $LegacyInstallRoot){Remove-Item -LiteralPath $LegacyInstallRoot -Recurse -Force -ErrorAction SilentlyContinue}
    $userPath=[Environment]::GetEnvironmentVariable('Path','User')
    if($userPath){
        $parts=@($userPath -split ';' | Where-Object {$_ -and $_ -ine $LegacyBinRoot})
        [Environment]::SetEnvironmentVariable('Path',($parts -join ';'),'User')
    }
    foreach($name in @('config.json','Vocabulary.txt','logs','bin')){
        $old=Join-Path $LegacyStateRoot $name
        if(Test-Path -LiteralPath $old){Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue}
    }
    if(Test-Path -LiteralPath $LegacyStateRoot){
        $left=@(Get-ChildItem -LiteralPath $LegacyStateRoot -Force -ErrorAction SilentlyContinue)
        if($left.Count -eq 0){Remove-Item -LiteralPath $LegacyStateRoot -Force -ErrorAction SilentlyContinue}
    }
}

$LegacyMigrated=Move-LegacyState

Write-Host ''
Write-Host 'Transcribe Audio Setup' -ForegroundColor Cyan
Write-Host 'Local transcription for Windows' -ForegroundColor DarkGray
Write-Host ''
New-Item -ItemType Directory -Force -Path $InstallRoot,$StateRoot,$BinRoot,$LogRoot | Out-Null

foreach($name in @('Transcribe-Audio.ps1','transcribe_audio_engine.py','transcribe_audio_probe.py','VERSION')){
    Copy-Item -LiteralPath (Join-Path $PackageRoot ('app\'+$name)) -Destination (Join-Path $InstallRoot $name) -Force
}
Ok 'Application ready'

$config=Join-Path $StateRoot 'config.json'
if(-not(Test-Path $config)){
    @{configVersion=4;profile='Quality';language='en';recentCount=13;openTranscript=$true;copyToClipboard=$false;customSources=@()} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $config -Encoding UTF8
    Ok 'Preferences ready'
}else{
    $migrated=$false
    try{
        $cfg=Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $version=0
        if($null -ne $cfg.PSObject.Properties['configVersion']){$version=[int]$cfg.configVersion}
        $legacyDefaultCount=$LegacyMigrated -and $null -ne $cfg.PSObject.Properties['recentCount'] -and [int]$cfg.recentCount -eq 8
        if($version -lt 4 -or $legacyDefaultCount){
            if($null -eq $cfg.PSObject.Properties['recentCount'] -or $legacyDefaultCount){
                if($null -eq $cfg.PSObject.Properties['recentCount']){$cfg|Add-Member -NotePropertyName recentCount -NotePropertyValue 13}else{$cfg.recentCount=13}
            }
            if($null -eq $cfg.PSObject.Properties['configVersion']){$cfg|Add-Member -NotePropertyName configVersion -NotePropertyValue 4}else{$cfg.configVersion=4}
            $cfg|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $config -Encoding UTF8
            $migrated=$true
        }
    }catch{Warn 'Preferences could not be upgraded automatically; existing file was left unchanged.'}
    if($migrated){Ok 'Preferences upgraded'}else{Ok 'Preferences preserved'}
}
$vocab=Join-Path $StateRoot 'Vocabulary.txt'
if(-not(Test-Path $vocab)){
    @('# Optional private recognition hints, one term per line.','# This local file is not part of the public repository.') | Set-Content -LiteralPath $vocab -Encoding UTF8
    Ok 'Private vocabulary ready'
}else{Ok 'Private vocabulary preserved'}

$launcher=Join-Path $BinRoot 'transcribe-audio.cmd'
@"
@echo off
setlocal
set "APP=$InstallRoot"
where pwsh.exe >nul 2>&1
if errorlevel 1 goto legacy
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP%\Transcribe-Audio.ps1" %*
exit /b %errorlevel%
:legacy
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%APP%\Transcribe-Audio.ps1" %*
exit /b %errorlevel%
"@ | Set-Content -LiteralPath $launcher -Encoding ASCII

$userPath=[Environment]::GetEnvironmentVariable('Path','User')
$parts=@($userPath -split ';' | Where-Object {$_})
if($parts -notcontains $BinRoot){
    $new=if($userPath){$userPath.TrimEnd(';')+';'+$BinRoot}else{$BinRoot}
    [Environment]::SetEnvironmentVariable('Path',$new,'User')
    Ok 'transcribe-audio command ready'
}else{Ok 'transcribe-audio command ready'}
Refresh-Path

if(-not $SkipRuntime){
    $python=Find-Python311
    if(-not $python){Ensure-WinGetPackage 'Python.Python.3.11' 'Python 3.11';$python=Find-Python311}
    if(-not $python){throw 'Python 3.11 could not be prepared automatically.'}
    Ok 'Python 3.11 ready'

    Refresh-Path
    if(-not(Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)){Ensure-WinGetPackage 'Gyan.FFmpeg' 'FFmpeg'}
    Refresh-Path
    if(-not(Get-Command ffmpeg.exe -ErrorAction SilentlyContinue)){throw 'FFmpeg could not be prepared automatically.'}
    Ok 'FFmpeg ready'

    if(-not(Test-Path (Join-Path $RuntimeRoot 'Scripts\python.exe') -PathType Leaf)){
        Say 'Creating private transcription runtime...'
        & $python -m venv $RuntimeRoot
        if($LASTEXITCODE -ne 0){throw 'Could not create the private transcription runtime.'}
    }
    $rpy=Join-Path $RuntimeRoot 'Scripts\python.exe'
    $probe=Read-RuntimeProbe -PythonExe $rpy
    $healthy=Test-RuntimeHealthy -Probe $probe
    if($healthy -and -not $ForceCpu){
        $compute=if($probe.cuda){'GPU'}else{'CPU'}
        Ok ("Transcription runtime ready ($compute)")
    }else{
        Info 'The transcription runtime needs a one-time repair or update.'
        $common=@('-m','pip','install','--disable-pip-version-check','--no-input','--upgrade','pip','wheel','setuptools<82')
        if((Invoke-QuietProcess -Title 'Preparing Python runtime...' -FilePath $rpy -Arguments $common) -ne 0){throw "Python runtime preparation failed. Setup log: $SetupLog"}

        $wantCuda=(-not $ForceCpu) -and (Test-Nvidia)
        if($wantCuda){
            $gpuArgs=@('-m','pip','install','--disable-pip-version-check','--no-input','--upgrade',("torch==$TorchVersion"),'--index-url','https://download.pytorch.org/whl/cu128')
            if((Invoke-QuietProcess -Title 'Preparing GPU acceleration...' -FilePath $rpy -Arguments $gpuArgs) -ne 0){$wantCuda=$false}
            if($wantCuda){
                $tp=Read-RuntimeProbe -PythonExe $rpy -TorchOnly
                if(-not $tp -or -not $tp.ok -or -not $tp.cuda){$wantCuda=$false}
            }
        }
        if(-not $wantCuda){
            $cpuArgs=@('-m','pip','install','--disable-pip-version-check','--no-input','--upgrade','--force-reinstall',("torch==$TorchVersion"),'--index-url','https://download.pytorch.org/whl/cpu')
            if((Invoke-QuietProcess -Title 'Preparing CPU transcription...' -FilePath $rpy -Arguments $cpuArgs) -ne 0){throw "PyTorch setup failed. Setup log: $SetupLog"}
        }
        $whisperArgs=@('-m','pip','install','--disable-pip-version-check','--no-input','--upgrade',("openai-whisper==$WhisperVersion"))
        if((Invoke-QuietProcess -Title 'Preparing speech recognition...' -FilePath $rpy -Arguments $whisperArgs) -ne 0){throw "Whisper setup failed. Setup log: $SetupLog"}

        $probe=Read-RuntimeProbe -PythonExe $rpy
        if(-not(Test-RuntimeHealthy -Probe $probe)){throw "The transcription runtime could not be verified. Setup log: $SetupLog"}
        $compute=if($probe.cuda){'GPU'}else{'CPU'}
        Ok ("Transcription runtime ready ($compute)")
    }
}

if($LegacyMigrated){Remove-LegacyInstall;Ok 'Previous development installation migrated'}

Write-Host ''
Write-Host 'Transcribe Audio is ready.' -ForegroundColor Green
Info 'Recordings and transcripts stay local. First transcription may download the selected Whisper model.'
Info 'Next time, type: transcribe-audio'

if($Launch){
    Write-Host ''
    Write-Host 'Opening Transcribe Audio...' -ForegroundColor Cyan
    & $launcher
    [Environment]::ExitCode=$LASTEXITCODE
}else{[Environment]::ExitCode=0}
