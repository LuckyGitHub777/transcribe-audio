# Changelog

## 1.0.0 — 2026-10-31

Initial public release.

- One-action Windows setup through `Transcribe-Audio.cmd`.
- Global daily command: `transcribe-audio`.
- Local transcription with OpenAI Whisper.
- NVIDIA CUDA acceleration when available, with explicit CPU fallback.
- Recent-file discovery across standard Windows recording/import locations.
- Recent list displays `[12]` through `[0]`, with the newest file nearest the prompt.
- First-class M4A support plus common audio and video formats.
- Safe transcript publication, prior-transcript archiving, and automatic opening.
- Private local preferences and recognition vocabulary.
- Quiet setup repair, diagnostics, mock engine tests, and Windows CI validation.
- Minimal privacy-first GitHub Pages landing experience.
- Release-gate real Whisper transcription smoke test using generated Windows speech.
