#!/usr/bin/env python3
"""Machine-readable runtime probe for Transcribe Audio."""
from __future__ import annotations
import argparse
import json
import sys
from importlib import metadata


def version_of(name: str) -> str:
    try:
        return metadata.version(name)
    except metadata.PackageNotFoundError:
        return "missing"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--torch-only", action="store_true")
    args = p.parse_args()
    try:
        import torch
    except Exception as exc:
        print(json.dumps({"ok": False, "stage": "torch", "error": str(exc)}))
        return 21

    data = {
        "ok": True,
        "python": sys.version.split()[0],
        "torch": version_of("torch"),
        "setuptools": version_of("setuptools"),
        "cuda": bool(torch.cuda.is_available()),
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "CPU",
        "vram_gb": round(torch.cuda.get_device_properties(0).total_memory / 1073741824, 1)
        if torch.cuda.is_available() else 0,
    }
    if not args.torch_only:
        try:
            import whisper
        except Exception as exc:
            data.update({"ok": False, "stage": "whisper", "error": str(exc), "whisper": "missing"})
            print(json.dumps(data))
            return 22
        data["whisper"] = getattr(whisper, "__version__", version_of("openai-whisper"))
        try:
            data["models"] = whisper.available_models()
        except Exception:
            data["models"] = []
    print(json.dumps(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
