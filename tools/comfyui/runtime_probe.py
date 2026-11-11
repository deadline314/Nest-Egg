"""Identify the actual PyTorch accelerator; never fall back to CPU generation."""
from __future__ import annotations

import argparse
import contextlib
import json
import sys


def inspect_runtime(torch) -> dict:
    hip = getattr(torch.version, "hip", None)
    if torch.cuda.is_available():
        backend = "rocm" if hip else "cuda"
        device = "cuda"
        api = torch.cuda
    elif getattr(torch, "xpu", None) is not None and torch.xpu.is_available():
        backend, device, api = "xpu", "xpu", torch.xpu
    else:
        raise RuntimeError(
            f"No usable GPU in {sys.executable}: torch={torch.__version__}, "
            f"HIP={hip}, CUDA={getattr(torch.version, 'cuda', None)}. "
            "Install the matching GPU runtime and driver; CPU fallback is disabled."
        )
    return {"python": sys.executable, "python_version": sys.version.split()[0],
            "torch": torch.__version__, "hip": hip,
            "cuda": getattr(torch.version, "cuda", None), "backend": backend,
            "device": device, "name": api.get_device_name(0)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise", action="store_true", help="Run and check a real GPU tensor kernel")
    args = parser.parse_args()
    try:
        with contextlib.redirect_stdout(sys.stderr):
            import torch
            result = inspect_runtime(torch)
            if args.exercise:
                values = torch.arange(16, device=result["device"], dtype=torch.float32)
                actual = values.square().sum().item()
                if actual != 1240.0:
                    raise RuntimeError(f"GPU tensor result {actual} != 1240.0")
                result["tensor_sum_of_squares"] = actual
        print(json.dumps(result, ensure_ascii=True))
        return 0
    except Exception as error:
        print(json.dumps({"python": sys.executable, "error": f"{type(error).__name__}: {error}"}, ensure_ascii=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
