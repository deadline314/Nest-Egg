#!/usr/bin/env bash
set -uo pipefail
source /workspace/.nest-egg-env/activate.sh
att=/workspace/Nest-Egg-session5-followup/pm/Nest-Egg/attachments/NE-95-followup
before=/workspace/Nest-Egg-session5-vfx-before
after=/workspace/Nest-Egg-session5-followup
# A B / B A / A B / B A: four before/after runs; no captures, imports or tests in the measured loop.
for spec in before-1 after-1 after-2 before-2 before-3 after-3 after-4 before-4; do
  side=${spec%-*}
  if [ "$side" = before ]; then cd "$before"; else cd "$after"; fi
  out=/workspace/scratch/session5-vfx-followup-no-capture/$spec
  python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 320x180 --rendering-driver vulkan --rendering-method forward_plus res://tools/screenshot.tscn -- --scenario=light_audit --level=level_01 --tile=115 --quality=medium --weapon=launcher --enemies=10 --seconds=14 --no-capture --out="$out" > "$att/$spec.log" 2>&1
  code=$?
  printf '%s exit=%s\n' "$spec" "$code" >> "$att/exit-codes.log"
  if [ "$code" != 0 ]; then exit "$code"; fi
  if find "$out" -type f -name '*.png' -print -quit | rg -q .; then exit 2; fi
done
