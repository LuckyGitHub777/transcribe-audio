$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:RUNNER_TEMP 'transcribe-audio-real-smoke'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$wav = Join-Path $work 'speech.wav'
$out = Join-Path $work 'transcript.txt'

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $synth.SetOutputToWaveFile($wav)
    $synth.Speak('Testing one two three. This is a transcription test for Transcribe Audio.')
}
finally {
    $synth.Dispose()
}

& python (Join-Path $root 'app/transcribe_audio_engine.py') `
    --input $wav `
    --output $out `
    --model tiny.en `
    --profile Fast `
    --language en `
    --device cpu

if ($LASTEXITCODE -ne 0) { throw "Transcription engine exited with code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath $out -PathType Leaf)) { throw 'Transcript file was not created.' }

$text = (Get-Content -LiteralPath $out -Raw).Trim()
if ($text.Length -lt 20) { throw "Transcript was unexpectedly short: '$text'" }
$lower = $text.ToLowerInvariant()
if ($lower -notmatch 'test') { throw "Transcript did not contain expected test language: '$text'" }
if ($lower -notmatch 'transcrib') { throw "Transcript did not contain expected transcription language: '$text'" }

Write-Host 'Real Whisper transcription smoke test PASS'
Write-Host "Transcript: $text"
