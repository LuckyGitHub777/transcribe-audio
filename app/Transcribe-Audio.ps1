#requires -Version 5.1
<#
.SYNOPSIS
    Low-friction local transcription for Windows.
.DESCRIPTION
    Transcribe Audio finds recent local media from deterministic Windows locations,
    keeps [0] as the newest item nearest the prompt, transcribes locally with
    OpenAI Whisper, safely publishes a text transcript, and opens it when done.
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Path,
    [ValidateSet('Quality','Maximum','Fast')][string]$Profile,
    [string]$Language,
    [int]$RecentCount = 0,
    [string]$Model,
    [switch]$NoOpen,
    [switch]$CopyToClipboard,
    [switch]$Diagnostics,
    [switch]$Doctor,
    [switch]$Config,
    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StateRoot { Join-Path $env:LOCALAPPDATA 'Transcribe Audio' }
function Get-ConfigPath { Join-Path (Get-StateRoot) 'config.json' }
function Get-VocabularyPath { Join-Path (Get-StateRoot) 'Vocabulary.txt' }

function Write-Banner {
    Write-Host ''
    Write-Host '  Transcribe Audio' -ForegroundColor Cyan
    Write-Host '  Local transcription' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-SupportedExtensions {
    @('.m4a','.wav','.mp3','.aac','.flac','.ogg','.opus','.wma','.mp4','.mov','.mkv','.webm','.3gp')
}

function Initialize-UserState {
    $state = Get-StateRoot
    if (-not (Test-Path -LiteralPath $state -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $state | Out-Null
    }
    $configPath = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        @{
            profile = 'Quality'
            language = 'en'
            configVersion = 4
            recentCount = 13
            openTranscript = $true
            copyToClipboard = $false
            customSources = @()
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8
    }
    $vocab = Get-VocabularyPath
    if (-not (Test-Path -LiteralPath $vocab -PathType Leaf)) {
        @(
            '# Optional recognition hints, one term per line.'
            '# Keep private names and project vocabulary here, not in the public repository.'
            '# Example:'
            '# yttrium iron garnet'
        ) | Set-Content -LiteralPath $vocab -Encoding UTF8
    }
}

function Get-UserConfig {
    Initialize-UserState
    try { return (Get-Content -LiteralPath (Get-ConfigPath) -Raw | ConvertFrom-Json) }
    catch { throw "Configuration is invalid: $(Get-ConfigPath)" }
}

function Resolve-Settings {
    $cfg = Get-UserConfig
    $effectiveProfile = if ($Profile) { $Profile } elseif ($cfg.profile) { [string]$cfg.profile } else { 'Quality' }
    $effectiveLanguage = if ($Language) { $Language } elseif ($cfg.language) { [string]$cfg.language } else { 'en' }
    $effectiveCount = if ($RecentCount -gt 0) { $RecentCount } elseif ($cfg.recentCount) { [int]$cfg.recentCount } else { 13 }
    if ($effectiveCount -lt 1 -or $effectiveCount -gt 50) { throw 'RecentCount must be between 1 and 50.' }
    [pscustomobject]@{
        Profile = $effectiveProfile
        Language = $effectiveLanguage
        RecentCount = $effectiveCount
        OpenTranscript = if ($NoOpen) { $false } elseif ($null -ne $cfg.openTranscript) { [bool]$cfg.openTranscript } else { $true }
        CopyToClipboard = if ($CopyToClipboard) { $true } elseif ($null -ne $cfg.copyToClipboard) { [bool]$cfg.copyToClipboard } else { $false }
        CustomSources = @($cfg.customSources)
    }
}

function Add-SourceCandidate {
    param([System.Collections.ArrayList]$List,[string]$Label,[string]$CandidatePath)
    if ([string]::IsNullOrWhiteSpace($CandidatePath)) { return }
    if (-not (Test-Path -LiteralPath $CandidatePath -PathType Container)) { return }
    $resolved = (Resolve-Path -LiteralPath $CandidatePath).Path
    foreach ($existing in $List) { if ($existing.Path -ieq $resolved) { return } }
    [void]$List.Add([pscustomobject]@{Label=$Label;Path=$resolved})
}

function Get-SourceFolders {
    param([object]$Settings)
    $sources = New-Object System.Collections.ArrayList
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $desktop = [Environment]::GetFolderPath('Desktop')
    $music = [Environment]::GetFolderPath('MyMusic')
    Add-SourceCandidate $sources 'Sound Recorder' (Join-Path $documents 'Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe!App\Sound Recordings')
    Add-SourceCandidate $sources 'Sound Recorder' (Join-Path $documents 'Sound Recordings')
    Add-SourceCandidate $sources 'Downloads' (Join-Path $env:USERPROFILE 'Downloads')
    Add-SourceCandidate $sources 'Desktop' $desktop
    Add-SourceCandidate $sources 'Music' $music
    if ($env:OneDrive) {
        Add-SourceCandidate $sources 'OneDrive' (Join-Path $env:OneDrive 'Documents\Sound Recordings')
        Add-SourceCandidate $sources 'OneDrive' (Join-Path $env:OneDrive 'Downloads')
    }
    foreach ($custom in @($Settings.CustomSources)) {
        if ($null -ne $custom -and -not [string]::IsNullOrWhiteSpace([string]$custom)) {
            Add-SourceCandidate $sources 'Custom' ([string]$custom)
        }
    }
    @($sources)
}

function Get-RecentMediaFiles {
    param([int]$Limit,[string]$OnlyFolder,[object]$Settings)
    $extensions = Get-SupportedExtensions
    $seen = @{}
    $items = @()
    $sources = if ($OnlyFolder) { @([pscustomobject]@{Label='Selected folder';Path=$OnlyFolder}) } else { @(Get-SourceFolders -Settings $Settings) }
    foreach ($source in $sources) {
        $files = Get-ChildItem -LiteralPath $source.Path -File -ErrorAction SilentlyContinue | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
        foreach ($file in $files) {
            $key=$file.FullName.ToLowerInvariant(); if ($seen.ContainsKey($key)) { continue }; $seen[$key]=$true
            $items += [pscustomobject]@{File=$file;Source=$source.Label}
        }
    }
    @($items | Sort-Object {$_.File.LastWriteTime} -Descending | Select-Object -First $Limit)
}

function Show-RecentMediaFiles {
    param([object[]]$Items,[object]$Settings)
    $labels = @($Items | ForEach-Object {$_.Source} | Select-Object -Unique)
    Write-Host 'Recent files' -ForegroundColor Cyan
    if ($labels.Count -gt 0) { Write-Host ('  ' + ($labels -join ' | ')) -ForegroundColor DarkGray }
    Write-Host ''
    for ($i=$Items.Count-1; $i -ge 0; $i--) {
        $item=$Items[$i]; $file=$item.File
        $stamp=$file.LastWriteTime.ToString('MMM dd  h:mm tt')
        $source=if ($item.Source -eq 'Sound Recorder') { '' } else { "  [$($item.Source)]" }
        $marker=if ($i -eq 0) { '  <- newest' } else { '' }
        Write-Host ('[{0,2}] {1}  {2}{3}{4}' -f $i,$stamp,$file.Name,$source,$marker)
    }
    Write-Host ''
}

function Select-FromList {
    param([object[]]$Items)
    $raw=Read-Host 'Select [Enter = 0], or paste a full file path'
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Items[0].File }
    $choice=0
    if ([int]::TryParse($raw,[ref]$choice)) {
        if ($choice -lt 0 -or $choice -ge $Items.Count) { throw "Selection must be between 0 and $($Items.Count-1)." }
        return $Items[$choice].File
    }
    $candidate=$raw.Trim().Trim('"')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $file=Get-Item -LiteralPath $candidate
        if ((Get-SupportedExtensions) -notcontains $file.Extension.ToLowerInvariant()) { throw "Unsupported file type '$($file.Extension)'." }
        return $file
    }
    throw 'Press Enter for the newest item, enter a list number, or paste a valid media-file path.'
}

function Resolve-SelectedInput {
    param([string]$RequestedPath,[object]$Settings)
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $clean=$RequestedPath.Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $clean)) { throw "Input path not found: $clean" }
        $resolved=Get-Item -LiteralPath $clean
        if ($resolved.PSIsContainer) {
            $items=@(Get-RecentMediaFiles -Limit $Settings.RecentCount -OnlyFolder $resolved.FullName -Settings $Settings)
            if ($items.Count -eq 0) { throw "No supported media files were found in: $($resolved.FullName)" }
            Show-RecentMediaFiles -Items $items -Settings $Settings
            return Select-FromList -Items $items
        }
        if ((Get-SupportedExtensions) -notcontains $resolved.Extension.ToLowerInvariant()) { throw "Unsupported file type '$($resolved.Extension)'." }
        return $resolved
    }
    $items=@(Get-RecentMediaFiles -Limit $Settings.RecentCount -Settings $Settings)
    if ($items.Count -eq 0) { throw 'No recent supported media files were found. Paste a full file path or add a custom source in config.' }
    Show-RecentMediaFiles -Items $items -Settings $Settings
    Select-FromList -Items $items
}

function Get-EnvironmentCandidates {
    $c=@()
    if ($env:TRANSCRIBE_AUDIO_ENV) { $c += $env:TRANSCRIBE_AUDIO_ENV }
    $c += @(
        (Join-Path (Get-StateRoot) 'runtime'),
        (Join-Path $PSScriptRoot '.venv'),
        'C:\envs\whisper-gpu',
        (Join-Path $env:USERPROFILE '.transcribe-audio\venv')
    )
    $seen=@{}; foreach($x in $c){ if([string]::IsNullOrWhiteSpace($x)){continue};$k=$x.ToLowerInvariant();if($seen.ContainsKey($k)){continue};$seen[$k]=$true;$x }
}

function Get-WhisperEnvironment {
    $probeScript=Join-Path $PSScriptRoot 'transcribe_audio_probe.py'
    if(-not(Test-Path -LiteralPath $probeScript -PathType Leaf)){throw 'Transcribe Audio runtime probe is missing. Run Transcribe-Audio.cmd from the release package to repair the app.'}
    foreach($root in Get-EnvironmentCandidates){
        $py=Join-Path $root 'Scripts\python.exe'; if(-not(Test-Path -LiteralPath $py -PathType Leaf)){continue}
        $raw=& $py $probeScript 2>$null; if($LASTEXITCODE -ne 0 -or -not $raw){continue}
        try{$p=($raw -join "`n")|ConvertFrom-Json}catch{continue}
        if(-not $p.ok){continue}
        return [pscustomobject]@{Root=$root;PythonExe=$py;Version=[string]$p.whisper;Models=@($p.models);Cuda=[bool]$p.cuda;Gpu=[string]$p.gpu;VramGB=[double]$p.vram_gb;Torch=[string]$p.torch}
    }
    throw 'Transcribe Audio runtime is not ready. Run Transcribe-Audio.cmd from the release package to repair it automatically.'
}

function Add-WinGetLinksToPath {
    $links=Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    if (Test-Path -LiteralPath $links -PathType Container) {
        if (($env:PATH -split ';') -notcontains $links) { $env:PATH="$links;$env:PATH" }
    }
}

function Find-FFmpeg {
    param([object]$Environment)
    $original=$env:PATH
    try{
        Add-WinGetLinksToPath
        $scripts=Join-Path $Environment.Root 'Scripts'; if(Test-Path -LiteralPath $scripts -PathType Container){$env:PATH="$scripts;$env:PATH"}
        [pscustomobject]@{FFmpeg=(Get-Command ffmpeg -ErrorAction SilentlyContinue);FFprobe=(Get-Command ffprobe -ErrorAction SilentlyContinue)}
    }finally{$env:PATH=$original}
}

function Get-PreferredModel {
    param([object]$Environment,[string]$RequestedModel,[string]$SelectedProfile,[string]$SelectedLanguage)
    if($RequestedModel){if($Environment.Models -notcontains $RequestedModel){throw "Model '$RequestedModel' is not available."};return $RequestedModel}
    if($SelectedProfile -eq 'Maximum' -and $Environment.Cuda -and $Environment.Models -contains 'large-v3' -and $Environment.VramGB -ge 11.5){return 'large-v3'}
    if($SelectedProfile -eq 'Fast'){
        if($SelectedLanguage -eq 'en' -and $Environment.Models -contains 'small.en'){return 'small.en'}
        if($Environment.Models -contains 'small'){return 'small'}
    }
    if($Environment.Models -contains 'turbo'){return 'turbo'}
    if($SelectedLanguage -eq 'en' -and $Environment.Models -contains 'medium.en'){return 'medium.en'}
    if($Environment.Models -contains 'medium'){return 'medium'}
    throw 'No suitable Whisper model is available.'
}

function Get-MediaDuration {
    param([System.IO.FileInfo]$InputFile,[object]$FFmpegTools,[object]$Environment)
    if(-not $FFmpegTools.FFprobe){return $null}
    $original=$env:PATH
    try{
        Add-WinGetLinksToPath
        $scripts=Join-Path $Environment.Root 'Scripts';if(Test-Path -LiteralPath $scripts){$env:PATH="$scripts;$env:PATH"}
        $raw=& ffprobe -v error -show_entries format=duration -of 'default=noprint_wrappers=1:nokey=1' $InputFile.FullName 2>$null
        $sec=0.0;if([double]::TryParse(($raw|Select-Object -First 1),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$sec)){return [TimeSpan]::FromSeconds($sec)}
    }catch{return $null}finally{$env:PATH=$original}
    $null
}

function Get-GpuLoad {
    if(-not(Get-Command nvidia-smi -ErrorAction SilentlyContinue)){return $null}
    try{
        $raw=& nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if(-not $raw){return $null}
        $p=$raw -split ','; if($p.Count -lt 3){return $null}
        [pscustomobject]@{Util=[int]$p[0].Trim();Used=[double]$p[1].Trim();Total=[double]$p[2].Trim()}
    }catch{$null}
}

function Get-UniqueArchivePath {
    param([string]$ArchiveDir,[System.IO.FileInfo]$TranscriptFile)
    New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
    Join-Path $ArchiveDir ("{0}.{1}.{2}.txt" -f $TranscriptFile.BaseName,$stamp,[guid]::NewGuid().ToString('N').Substring(0,8))
}

function Publish-Transcript {
    param([string]$TempTranscript,[string]$FinalTranscript,[string]$ArchiveDir)
    $destDir=Split-Path -Parent $FinalTranscript
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $staged=Join-Path $destDir ('.transcribe-audio-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $TempTranscript -Destination $staged -Force
    try{
        if(Test-Path -LiteralPath $FinalTranscript -PathType Leaf){
            $existing=Get-Item -LiteralPath $FinalTranscript
            $archive=Get-UniqueArchivePath -ArchiveDir $ArchiveDir -TranscriptFile $existing
            Copy-Item -LiteralPath $FinalTranscript -Destination $archive
            [IO.File]::Replace($staged,$FinalTranscript,$null)
        }else{[IO.File]::Move($staged,$FinalTranscript)}
    }finally{if(Test-Path -LiteralPath $staged){Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue}}
}

function Try-OpenTranscript {
    param([string]$TranscriptPath)
    try{Invoke-Item -LiteralPath $TranscriptPath -ErrorAction Stop;return $true}catch{}
    try{Start-Process -FilePath 'notepad.exe' -ArgumentList @($TranscriptPath) -ErrorAction Stop;return $true}catch{return $false}
}

function Show-Doctor {
    Write-Host 'System check' -ForegroundColor Cyan
    try{
        $e=Get-WhisperEnvironment
        $t=Find-FFmpeg -Environment $e
        Write-Host '  Runtime   : ready' -ForegroundColor Green
        Write-Host ("  Whisper   : {0}" -f $e.Version)
        Write-Host ("  Compute   : {0}" -f $(if($e.Cuda){"GPU - $($e.Gpu)"}else{'CPU'}))
        Write-Host ("  FFmpeg    : {0}" -f $(if($t.FFmpeg){'ready'}else{'missing'}))
        Write-Host ("  FFprobe   : {0}" -f $(if($t.FFprobe){'ready'}else{'missing'}))
        Write-Host ''
        if($t.FFmpeg){Write-Host 'Transcribe Audio is ready.' -ForegroundColor Green}else{Write-Host 'Run Transcribe-Audio.cmd from the release package to repair missing components.' -ForegroundColor Yellow}
    }catch{Write-Host $_.Exception.Message -ForegroundColor Yellow;Write-Host 'Run Transcribe-Audio.cmd from the release package.' -ForegroundColor DarkGray}
}

function Invoke-TranscribeAudio {
    Write-Banner
    if($Version){$vf=Join-Path $PSScriptRoot 'VERSION';if(Test-Path $vf){Get-Content $vf}else{'1.0.0'};return}
    Initialize-UserState
    if($Config){Start-Process explorer.exe (Get-StateRoot);return}
    if($Doctor){Show-Doctor;return}
    $settings=Resolve-Settings
    $envInfo=Get-WhisperEnvironment
    $tools=Find-FFmpeg -Environment $envInfo
    if(-not $tools.FFmpeg){throw 'FFmpeg is missing. Run Transcribe-Audio.cmd from the release package to repair it automatically.'}
    $engine=Join-Path $PSScriptRoot 'transcribe_audio_engine.py';if(-not(Test-Path -LiteralPath $engine)){throw 'Transcribe Audio engine helper is missing.'}
    $input=Resolve-SelectedInput -RequestedPath $Path -Settings $settings
    $modelName=Get-PreferredModel -Environment $envInfo -RequestedModel $Model -SelectedProfile $settings.Profile -SelectedLanguage $settings.Language
    $duration=Get-MediaDuration -InputFile $input -FFmpegTools $tools -Environment $envInfo
    $device=if($envInfo.Cuda){'cuda'}else{'cpu'}
    Write-Host ''
    Write-Host $input.Name -ForegroundColor White
    $lang=if($settings.Language -eq 'auto'){'Auto language'}elseif($settings.Language -eq 'en'){'English'}else{"Language: $($settings.Language)"}
    $compute=if($envInfo.Cuda){'GPU ready'}else{'CPU'}
    Write-Host ('  ' + (@($settings.Profile,$lang,$compute) -join '  |  ')) -ForegroundColor DarkGray
    if($duration){Write-Host ('  Duration: {0:hh\:mm\:ss}' -f $duration) -ForegroundColor DarkGray}
    if(-not $envInfo.Cuda){Write-Host '  GPU acceleration unavailable. Transcription will take longer.' -ForegroundColor Yellow}
    if($envInfo.Cuda){$load=Get-GpuLoad;if($load -and ($load.Util -ge 60 -or ($load.Total -gt 0 -and ($load.Used/$load.Total) -ge 0.45))){Write-Host '  GPU busy. Another application may slow transcription. Continuing...' -ForegroundColor Yellow}}
    if($Diagnostics){
        Write-Host '';Write-Host 'Diagnostics' -ForegroundColor DarkGray
        Write-Host ("  Source      : {0}" -f $input.FullName) -ForegroundColor DarkGray
        Write-Host ("  Runtime     : {0}" -f $envInfo.Root) -ForegroundColor DarkGray
        Write-Host ("  Model       : {0}" -f $modelName) -ForegroundColor DarkGray
        Write-Host ("  Whisper     : {0}" -f $envInfo.Version) -ForegroundColor DarkGray
        Write-Host ("  Compute     : {0}" -f $(if($envInfo.Cuda){"$($envInfo.Gpu) ($($envInfo.VramGB) GB VRAM)"}else{'CPU'})) -ForegroundColor DarkGray
    }
    Write-Host ''
    $outputDir=Join-Path $input.DirectoryName 'transcripts';$archiveDir=Join-Path $outputDir 'archive';New-Item -ItemType Directory -Force -Path $outputDir|Out-Null
    $final=Join-Path $outputDir ($input.BaseName+'.txt')
    $tempDir=Join-Path ([IO.Path]::GetTempPath()) ('TranscribeAudio-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $tempDir|Out-Null
    $temp=Join-Path $tempDir ($input.BaseName+'.txt')
    $vocab=Get-VocabularyPath
    $sw=[Diagnostics.Stopwatch]::StartNew();$original=$env:PATH
    try{
        Add-WinGetLinksToPath
        $scripts=Join-Path $envInfo.Root 'Scripts';if(Test-Path $scripts){$env:PATH="$scripts;$env:PATH"}
        $args=@($engine,'--input',$input.FullName,'--output',$temp,'--model',$modelName,'--profile',$settings.Profile,'--language',$settings.Language,'--device',$device)
        if(Test-Path -LiteralPath $vocab){$args+=@('--vocabulary',$vocab)}
        & $envInfo.PythonExe @args
        $code=$LASTEXITCODE
        if($code -ne 0){throw "Transcription engine stopped with code $code."}
        if(-not(Test-Path -LiteralPath $temp -PathType Leaf)){throw 'The engine finished without producing a transcript.'}
        if((Get-Item -LiteralPath $temp).Length -eq 0){throw 'The engine produced an empty transcript.'}
        Publish-Transcript -TempTranscript $temp -FinalTranscript $final -ArchiveDir $archiveDir
    }finally{$sw.Stop();$env:PATH=$original;if(Test-Path $tempDir){Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue}}
    Write-Host ''
    Write-Host ('Transcript ready  |  {0:hh\:mm\:ss}' -f $sw.Elapsed) -ForegroundColor Green
    Write-Host ('  {0}' -f ([IO.Path]::GetFileName($final)))
    if($settings.CopyToClipboard){
        try{Get-Content -LiteralPath $final -Raw | Set-Clipboard;Write-Host '  Copied to clipboard' -ForegroundColor DarkGray}catch{Write-Host '  Transcript is safe, but clipboard copy failed.' -ForegroundColor Yellow}
    }
    if($Diagnostics){Write-Host ('  Output: {0}' -f $final) -ForegroundColor DarkGray}
    if($settings.OpenTranscript){
        Write-Host 'Opening transcript...' -ForegroundColor Cyan
        if(-not(Try-OpenTranscript -TranscriptPath $final)){Write-Host '  Transcript is safe, but Windows could not open a text editor.' -ForegroundColor Yellow;Write-Host ('  Saved at: {0}' -f $final) -ForegroundColor DarkGray}
    }
    Write-Host ''
}

$old=$env:PATH
try{Invoke-TranscribeAudio;[Environment]::ExitCode=0}catch{Write-Host '';Write-Host 'Transcribe Audio could not complete.' -ForegroundColor Red;Write-Host ('  '+$_.Exception.Message) -ForegroundColor Yellow;Write-Host '';Write-Host 'Run: transcribe-audio -Doctor' -ForegroundColor DarkGray;Write-Host '';[Environment]::ExitCode=1}finally{$env:PATH=$old}
