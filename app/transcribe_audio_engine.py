#!/usr/bin/env python3
"""Internal OpenAI Whisper engine for Transcribe Audio."""
from __future__ import annotations
import argparse, os, sys
from pathlib import Path
from typing import Optional

def _cache_path_for_model(whisper_module, model_name: str) -> Optional[Path]:
    url = getattr(whisper_module, '_MODELS', {}).get(model_name)
    if not url: return None
    root = Path(os.getenv('XDG_CACHE_HOME', str(Path.home()/'.cache'))) / 'whisper'
    return root / os.path.basename(url)

def _read_prompt(path: Optional[str]) -> Optional[str]:
    if not path: return None
    p=Path(path)
    if not p.is_file(): return None
    terms=[]
    for line in p.read_text(encoding='utf-8-sig').splitlines():
        term=line.strip()
        if term and not term.startswith('#'): terms.append(term)
    if not terms: return None
    return ('Vocabulary and proper nouns that may appear: '+', '.join(terms)+'.')[:1800]

def _args():
    p=argparse.ArgumentParser(add_help=False)
    p.add_argument('--input',required=True);p.add_argument('--output',required=True);p.add_argument('--model',required=True)
    p.add_argument('--profile',choices=('Quality','Maximum','Fast'),required=True);p.add_argument('--language',default='en')
    p.add_argument('--device',choices=('cuda','cpu'),required=True);p.add_argument('--vocabulary')
    return p.parse_args()

def main()->int:
    a=_args()
    try:
        import torch, whisper
    except Exception as exc:
        print(f'Transcribe Audio engine unavailable: {exc}',file=sys.stderr,flush=True);return 20
    if a.device=='cuda' and not torch.cuda.is_available():
        print('CUDA was selected but is not available to PyTorch.',file=sys.stderr,flush=True);return 21
    inp=Path(a.input);out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
    cached_path=_cache_path_for_model(whisper,a.model);cached=bool(cached_path and cached_path.is_file() and cached_path.stat().st_size>0)
    if cached: print('Loading transcription engine...',flush=True)
    else:
        print('Preparing transcription engine...',flush=True)
        print('First use only. The model is downloaded once and reused on later runs.',flush=True)
    model=whisper.load_model(a.model,device=a.device)
    print('Engine ready.',flush=True);print('Transcribing...',flush=True)
    prompt=_read_prompt(a.vocabulary)
    if a.profile=='Fast':
        temperature=0.0;beam_size=1;word_timestamps=False;hallucination=None
    else:
        temperature=(0.0,0.2,0.4,0.6,0.8,1.0);beam_size=5;word_timestamps=True;hallucination=2.0
    language=None if a.language.lower()=='auto' else a.language
    result=model.transcribe(str(inp),task='transcribe',language=language,verbose=False,temperature=temperature,
        beam_size=beam_size,best_of=5,initial_prompt=prompt,word_timestamps=word_timestamps,
        hallucination_silence_threshold=hallucination,fp16=(a.device=='cuda'))
    text=str(result.get('text','')).strip()
    if not text:
        print('Whisper returned an empty transcript.',file=sys.stderr,flush=True);return 22
    out.write_text(text+'\n',encoding='utf-8')
    print('Finalizing transcript...',flush=True);return 0

if __name__=='__main__': raise SystemExit(main())
