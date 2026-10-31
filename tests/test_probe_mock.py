from pathlib import Path
import json, os, subprocess, sys, tempfile
ROOT=Path(__file__).resolve().parents[1]
probe=ROOT/'app'/'transcribe_audio_probe.py'
with tempfile.TemporaryDirectory() as td:
    t=Path(td)
    (t/'torch.py').write_text('''\nclass _Cuda:\n    @staticmethod\n    def is_available(): return True\n    @staticmethod\n    def get_device_name(i): return "Mock GPU"\n    @staticmethod\n    def get_device_properties(i):\n        return type("P",(),{"total_memory":10*1073741824})()\ncuda=_Cuda()\n''',encoding='utf-8')
    (t/'whisper.py').write_text('''\n__version__="20250625"\ndef available_models(): return ["turbo","medium"]\n''',encoding='utf-8')
    env=os.environ.copy();env['PYTHONPATH']=str(t)
    r=subprocess.run([sys.executable,str(probe)],text=True,capture_output=True,env=env)
    assert r.returncode==0,(r.stdout,r.stderr)
    data=json.loads(r.stdout)
    assert data['ok'] is True
    assert data['cuda'] is True
    assert data['gpu']=='Mock GPU'
    assert data['vram_gb']==10.0
    assert data['whisper']=='20250625'
print('transcribe-audio v1.0.0 runtime probe mock PASS')
