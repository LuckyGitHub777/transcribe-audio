from pathlib import Path
import os
import subprocess
import sys
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / 'app' / 'transcribe_audio_engine.py'


def run_case(device='cpu', transcript_text='Hello world', with_vocab=False):
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        cuda_flag = 'True' if device == 'cuda' else 'False'
        fp16_flag = 'True' if device == 'cuda' else 'False'
        (d / 'torch.py').write_text(
            f"CUDA = {cuda_flag}\n"
            "class _Cuda:\n"
            "    @staticmethod\n"
            "    def is_available(): return CUDA\n"
            "cuda = _Cuda()\n",
            encoding='utf-8',
        )
        whisper_code = f'''\
_MODELS = {{'turbo': 'https://example.invalid/turbo.pt'}}
class M:
    def transcribe(self, *args, **kwargs):
        assert kwargs.get('fp16') is {fp16_flag}
        return {{'text': {transcript_text!r}}}
def available_models(): return ['turbo', 'small', 'small.en', 'large-v3']
def load_model(name, device=None):
    assert name == 'turbo'
    assert device == {device!r}
    return M()
'''
        (d / 'whisper.py').write_text(textwrap.dedent(whisper_code), encoding='utf-8')
        inp = d / 'sample.m4a'
        inp.write_bytes(b'fake')
        out = d / 'out.txt'
        cmd = [
            sys.executable, str(ENGINE), '--input', str(inp), '--output', str(out),
            '--model', 'turbo', '--profile', 'Quality', '--language', 'en', '--device', device,
        ]
        if with_vocab:
            vocab = d / 'Vocabulary.txt'
            vocab.write_text('# comment\nExample Term 7\nYIG\n', encoding='utf-8')
            cmd += ['--vocabulary', str(vocab)]
        env = os.environ.copy()
        env['PYTHONPATH'] = str(d)
        cp = subprocess.run(cmd, capture_output=True, text=True, env=env)
        return cp, out.read_text(encoding='utf-8') if out.exists() else None


for device in ('cpu', 'cuda'):
    cp, text = run_case(device=device, with_vocab=True)
    assert cp.returncode == 0, (device, cp.stdout, cp.stderr)
    assert text == 'Hello world\n'
    assert 'Preparing transcription engine...' in cp.stdout
    assert 'Engine ready.' in cp.stdout
    assert 'Transcribing...' in cp.stdout
    assert 'Finalizing transcript...' in cp.stdout

cp, text = run_case(device='cpu', transcript_text='')
assert cp.returncode == 22, (cp.stdout, cp.stderr)
assert text is None
assert 'empty transcript' in cp.stderr.lower()

print('transcribe-audio v1.0.0 mock engine UAT PASS')
