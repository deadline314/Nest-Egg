#!/usr/bin/env bash
set -uo pipefail
source /workspace/.nest-egg-env/activate.sh
cd /workspace/Nest-Egg-session5-followup
logs=pm/Nest-Egg/attachments/NE-66-followup
images=/workspace/Nest-Egg-session5-followup/pm/Nest-Egg/images/NE-66-session5-followup
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/test_viewport_capture.tscn > "$logs/capture-check.log" 2>&1
printf 'capture-check exit=%s\n' "$?" >> "$logs/exit-codes.log"
for quality in low high; do
  python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/ch1_readability_check.tscn -- --quality="$quality" --capture-prefix=NE-66 --out="$images/ch1-$quality" > "$logs/ch1-$quality.log" 2>&1
  printf 'ch1-%s exit=%s\n' "$quality" "$?" >> "$logs/exit-codes.log"
  python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/readability_check.tscn -- --level=level_02 --quality="$quality" --capture-prefix=NE-66 --out="$images/ch2-$quality" > "$logs/ch2-$quality.log" 2>&1
  printf 'ch2-%s exit=%s\n' "$quality" "$?" >> "$logs/exit-codes.log"
done
python tools/comfyui/gpu_lock.py -- xvfb-run -a "$GODOT" --audio-driver Dummy --path . --resolution 640x360 --rendering-driver vulkan --rendering-method forward_plus res://tools/ch1_readability_check.tscn -- --level=ch1_street --quality=medium --capture-prefix=NE-66 --out="$images/ch1-medium" > "$logs/ch1-medium.log" 2>&1
printf 'ch1-medium exit=%s\n' "$?" >> "$logs/exit-codes.log"
