from pathlib import Path
root = Path(__file__).resolve().parent
original = (root / 'original-256-prefetch.gd.txt').read_bytes()
assert original.count(b'const MAX_REQUESTS_PER_CALL := 256') == 1
b = original.replace(b'const MAX_REQUESTS_PER_CALL := 256', b'const MAX_REQUESTS_PER_CALL := 512')
(root / 'candidate-512-prefetch.gd.txt').write_bytes(b)
start = b.index(b'\twanted.append_array(scene_texture_paths(data.intro_scene))')
end = b.index('# 只留'.encode('utf-8'), start)
assert end > start
c = b[:start] + b'\t# Idle areas retain neighbors only; active CutscenePlayer owns its stage.\n\t' + b[end:]
(root / 'candidate-512-no-stage-pin-prefetch.gd.txt').write_bytes(c)
anchor = b'\t# Idle areas retain neighbors only; active CutscenePlayer owns its stage.\n'
assert c.count(anchor) == 1
d = c.replace(anchor, b'\t# Do not pin a neighboring sky that the current theme never uses.\n\tvar current := level_texture_paths(data)\n\tvar retained := PackedStringArray()\n\tfor path: String in wanted:\n\t\tif not path.begins_with("res://art/environment/backdrop/") or current.has(path):\n\t\t\tretained.append(path)\n\twanted = retained\n' + anchor)
(root / 'candidate-512-no-stage-or-unused-backdrop-prefetch.gd.txt').write_bytes(d)
assert d.count(b'\tvar current := level_texture_paths(data)\n') == 1
e = d.replace(b'\tvar current := level_texture_paths(data)\n', b'\tvar current := PackedStringArray()\n\tif data.environment != null:\n\t\tfor layer: BackdropLayer in data.environment.backdrop:\n\t\t\tif layer != null:\n\t\t\t\t_add_with_variants(current, layer.texture)\n\t\tif data.environment.sky != null:\n\t\t\t_add_with_variants(current, data.environment.sky.texture)\n')
(root / 'candidate-512-theme-backdrop-only-prefetch.gd.txt').write_bytes(e)
print('Saved A/B/C/D/E source variants; root core untouched')
