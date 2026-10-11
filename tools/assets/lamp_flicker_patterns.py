"""Checks (and can print a preview of) the lamp flicker patterns in data/environment/lamp_flicker.json (BG-35).

Usage (project root):
  python tools/assets/lamp_flicker_patterns.py            # validate; exit 1 on any problem
  python tools/assets/lamp_flicker_patterns.py --show     # also print each pattern as a row of brightness bars

A pattern is a string of letters, one per step (step_hz steps a second), Quake style: 'a' is off, 'm' is normal brightness,
'z' is about twice as bright. The photosensitivity rule is the same one core/lamp_flicker.gd enforces at load time: in any
window of one second (wrapping around the end of the pattern) the brightness may change by `change_threshold` or more at
most `max_changes_per_second` times.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "environment" / "lamp_flicker.json"
BARS = " ▁▂▃▄▅▆▇█"


def level(letter: str) -> float:
    return (ord(letter) - ord("a")) / 12.0


def worst_window(pattern: str, step_hz: int, threshold: float) -> int:
    """Largest number of brightness changes (>= threshold) inside any one-second window, wrapping around."""
    values = [level(c) for c in pattern]
    n = len(values)
    changed = [abs(values[(i + 1) % n] - values[i]) >= threshold for i in range(n)]
    return max(sum(changed[(start + k) % n] for k in range(step_hz)) for start in range(n))


def problems(data: dict) -> list[str]:
    out: list[str] = []
    step_hz = int(data.get("step_hz", 10))
    limit = int(data.get("max_changes_per_second", 3))
    threshold = float(data.get("change_threshold", 0.2))
    if limit > 3:
        out.append(f"max_changes_per_second is {limit}; the photosensitivity limit is 3")
    states = data.get("states", {})
    for name, state in states.items():
        patterns = state.get("patterns", [])
        if not patterns:
            out.append(f"state '{name}' has no patterns")
        for index, pattern in enumerate(patterns):
            if not pattern or any(not ("a" <= c <= "z") for c in pattern):
                out.append(f"{name}[{index}] must be a non-empty string of lowercase letters")
                continue
            if len(pattern) < step_hz * 2:
                out.append(f"{name}[{index}] is shorter than two seconds ({len(pattern)} steps)")
            worst = worst_window(pattern, step_hz, threshold)
            if worst > limit:
                out.append(f"{name}[{index}] changes brightness {worst} times within one second (limit {limit})")
        calm = state.get("calm", {})
        if float(calm.get("period", 0.0)) < 2.0:
            out.append(f"state '{name}': the calm (reduce flashes) period must be at least 2 seconds")
    for name, supply in data.get("supply", {}).items():
        for entry in supply.get("cycle", []):
            if entry != "stable" and entry not in states:
                out.append(f"supply '{name}' uses the unknown state '{entry}'")
        if not supply.get("cycle"):
            out.append(f"supply '{name}' has an empty cycle")
    return out


def main() -> int:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    if "--show" in sys.argv:
        sys.stdout.reconfigure(encoding="utf-8")
        for name, state in data.get("states", {}).items():
            for index, pattern in enumerate(state.get("patterns", [])):
                row = "".join(BARS[min(len(BARS) - 1, round(level(c) * 6))] for c in pattern)
                print(f"{name}[{index}] {len(pattern) / data.get('step_hz', 10):4.1f}s  {row}")
    found = problems(data)
    for line in found:
        print("FAIL ", line, file=sys.stderr)
    if not found:
        print("lamp flicker patterns OK")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
