from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

required = [
    '.gitattributes', 'README.md', 'LICENSE', 'SECURITY.md', 'CHANGELOG.md', 'VERSION',
    'Transcribe-Audio.cmd', 'Uninstall-Transcribe-Audio.cmd',
    'app/Transcribe-Audio.ps1', 'app/transcribe_audio_engine.py', 'app/transcribe_audio_probe.py', 'app/VERSION',
    'installer/Install-Transcribe-Audio.ps1', 'installer/Uninstall-Transcribe-Audio.ps1',
    'tests/static_validate.py', 'tests/test_engine_mock.py', 'tests/test_probe_mock.py',
    '.github/workflows/validate.yml',
]
for item in required:
    assert (ROOT / item).is_file(), item

for forbidden_path in [
    'docs', 'MANIFEST.json', 'SHA256SUMS.txt', 'LICENSE-DECISION.md',
    'GoTranscribe.cmd', 'Uninstall-GoTranscribe.cmd', 'app/GoTranscribe.ps1',
    'app/gotranscribe_engine.py', 'app/gotranscribe_probe.py',
    'installer/Install-GoTranscribe.ps1', 'installer/Uninstall-GoTranscribe.ps1',
]:
    assert not (ROOT / forbidden_path).exists(), f'public repo bloat/legacy path: {forbidden_path}'

assert not any('__pycache__' in p.parts for p in ROOT.rglob('*'))
assert not any(p.suffix.lower() in {'.pyc', '.pyo'} for p in ROOT.rglob('*') if p.is_file())

version = (ROOT / 'VERSION').read_text(encoding='utf-8').strip()
assert version == '1.0.0'
assert (ROOT / 'app/VERSION').read_text(encoding='utf-8').strip() == version
readme = (ROOT / 'README.md').read_text(encoding='utf-8')
assert readme.startswith('# Transcribe Audio\n')
assert 'Transcribe-Audio.cmd' in readme
assert 'transcribe-audio' in readme
assert 'GoTranscribe' not in readme
assert 'gotranscribe' not in readme.lower()

ps = (ROOT / 'app/Transcribe-Audio.ps1').read_text(encoding='utf-8')
assert 'Transcribe Audio' in ps
assert "recentCount = 13" in ps
assert "else { 13 }" in ps
assert "'Current folder'" not in ps
assert 'Select [Enter = 0]' in ps
assert 'GPU busy' in ps
assert 'Publish-Transcript' in ps
assert 'clipboard copy failed' in ps
assert 'Try-OpenTranscript' in ps and 'Transcript is safe' in ps
assert 'transcribe_audio_probe.py' in ps
assert 'transcribe_audio_engine.py' in ps
assert 'python -c' not in ps.lower()
assert 'GoTranscribe' not in ps
assert 'gotranscribe' not in ps.lower()

installer = (ROOT / 'installer/Install-Transcribe-Audio.ps1').read_text(encoding='utf-8')
for token in [
    "recentCount=13", 'configVersion=4', 'Preferences upgraded',
    'Python.Python.3.11', 'Gyan.FFmpeg', 'openai-whisper==$WhisperVersion',
    'torch==$TorchVersion', 'whl/cu128', 'whl/cpu', 'setuptools<82',
    'Read-RuntimeProbe', 'Test-RuntimeHealthy', '[switch]$Launch',
    "'transcribe-audio.cmd'", "'Transcribe-Audio.ps1'", 'Move-LegacyState',
]:
    assert token in installer, token
assert 'recentCount=8' not in installer
assert 'pip install --upgrade pip setuptools wheel' not in installer
# Legacy name may appear only here for silent migration of development installs.

uninstaller = (ROOT / 'installer/Uninstall-Transcribe-Audio.ps1').read_text(encoding='utf-8')
for token in ["'runtime'", "'logs'", 'RemoveUserData', 'Your transcripts were not removed.', 'Transcribe Audio']:
    assert token in uninstaller, token

front = (ROOT / 'Transcribe-Audio.cmd').read_text(encoding='utf-8', errors='ignore')
assert '-Launch' in front
assert 'Install-Transcribe-Audio.ps1' in front

all_text = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore')
    for p in ROOT.rglob('*')
    if p.is_file() and '.git' not in p.parts and p.name != 'static_validate.py'
)
for forbidden in ['Lucky777', 'Bob Lazar.m4a', 'BN7_James-Wolff', 'RC2-UAT-INCIDENT']:
    assert forbidden not in all_text, forbidden

# User-facing/public narrative files must have the converged identity only.
for rel in ['README.md','CHANGELOG.md','SECURITY.md','Transcribe-Audio.cmd','app/Transcribe-Audio.ps1']:
    text=(ROOT/rel).read_text(encoding='utf-8',errors='ignore')
    assert 'GoTranscribe' not in text, rel
    assert 'gotranscribe' not in text.lower(), rel

print('transcribe-audio v1.0.0 repo/static validation PASS')
