# Transcribe Audio

**Turn recordings into transcripts with almost no friction.**

Transcribe Audio is a local-first Windows utility for turning audio and video recordings into text transcripts. It finds recent recordings, keeps the newest item at `[0]` nearest the prompt, uses GPU acceleration when available, saves the transcript safely beside the source, and opens it automatically.

## Quick start

1. Download and extract the Windows release.
2. Run `Transcribe-Audio.cmd`.
3. Press **Enter** to transcribe `[0]`, the newest recording.

After setup, run `transcribe-audio` from any PowerShell or Windows Terminal location.

```text
Transcribe Audio
Local transcription

Recent files
  Sound Recorder | Downloads

[12] ...
 ...
[ 1] Recording 87.m4a
[ 0] Interview.m4a  <- newest

Select [Enter = 0], or paste a full file path:
```

## What it searches

Transcribe Audio checks supported media directly inside standard Windows locations that exist for the current user:

- Sound Recorder
- Downloads
- Desktop
- Music
- detected OneDrive recording/download locations
- locally configured custom folders

The current Terminal folder does **not** silently change the default search set.

## Supported media

`.m4a`, `.wav`, `.mp3`, `.aac`, `.flac`, `.ogg`, `.opus`, `.wma`, `.mp4`, `.mov`, `.mkv`, `.webm`, `.3gp`

## Output

Completed transcripts are saved as:

```text
<source folder>\transcripts\<recording-name>.txt
```

Existing transcripts are archived before replacement. Source media is never intentionally modified.

Automated transcription can contain errors. Verify important names, numbers, dates, and quotations against the source audio when accuracy matters.

## Privacy

Audio and transcripts are processed locally. Transcribe Audio includes no telemetry or media-upload feature. Setup and first model use may access the internet to acquire required runtime components and model files.

Private preferences and recognition vocabulary live under `%LOCALAPPDATA%\Transcribe Audio` and are not part of the repository.

## Setup and performance

Transcribe Audio is Windows-first. Setup prepares Python 3.11, FFmpeg, Whisper, and PyTorch when they are not already ready. Compatible NVIDIA CUDA hardware is used automatically; CPU transcription remains available and is slower.

The launcher does not permanently change the machine's PowerShell execution policy. It starts a child PowerShell process for setup and execution.

Optional troubleshooting:

```text
transcribe-audio -Doctor
transcribe-audio -Diagnostics
transcribe-audio -Version
```

## Uninstall

Run `Uninstall-Transcribe-Audio.cmd`.

Normal uninstall removes the application, launcher, runtime, and logs while preserving private preferences and vocabulary for a future reinstall. User-created transcripts are never removed. To remove local preferences and vocabulary too, run the uninstaller with `-RemoveUserData`.

## Development

Run the lightweight validation suite:

```text
python tests/static_validate.py
python tests/test_engine_mock.py
python tests/test_probe_mock.py
```

The repository intentionally stays small: application code, installer, tests, essential documentation, and CI.
