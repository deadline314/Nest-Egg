from pathlib import Path
import hashlib, sys
root=Path(__file__).resolve().parents[2]
work=Path(__file__).resolve().parent
source=(root/'tools/bg31_main_lifecycle_probe.gd').read_bytes()
(work/'original-bg31-main-probe.gd.txt').write_bytes(source)
text=source.decode('utf-8')
tag=sys.argv[1] if len(sys.argv)>1 else 'E'
prefetch=(work/'candidate-512-theme-backdrop-only-prefetch.gd.txt').read_bytes()
sha=hashlib.sha256(prefetch).hexdigest()
old='31adc870a9594b247c01aed458a83901188e34e2f00a3944c352332f72bef013'
assert text.count(old)==1
text=text.replace(old,sha)
text=text.replace('extends Node\n','extends Node\n# BG32 independent evidence snapshot; BG31 original remains unchanged.\nvar _expected_world := "res://data/levels/ch1_prologue.tres"\n',1)
needle='func _ready() -> void:\n'
assert text.count(needle)==1
text=text.replace(needle,'var _last_wall_usec := 0\nvar _stage_max_frame_ms := 0.0\n\nfunc _process(_delta: float) -> void:\n\tvar now := Time.get_ticks_usec()\n\tif _last_wall_usec > 0: _stage_max_frame_ms = maxf(_stage_max_frame_ms, (now - _last_wall_usec) / 1000.0)\n\t_last_wall_usec = now\n\n'+needle)
assert text.count('_main.FIRST_LEVEL')==2
text=text.replace('_main.FIRST_LEVEL','_expected_world')
needle='\tvar reached := await _wait(func() -> bool: return person.interaction_available() and Story.framing.is_interaction_target(person),\n\t\t"actual walk input reaches the person\'s interaction range: " + label, 20000)'
assert text.count(needle)==1
text=text.replace(needle,'\tvar reached := await _walk_to_person(level, person, label)')
needle='func _find_person(root: Node) -> NpcActor:\n'
assert text.count(needle)==1
text=text.replace(needle,'func _walk_to_person(level: Level, person: NpcActor, label: String) -> bool:\n\tvar deadline := Time.get_ticks_msec() + 20000\n\tvar progressed := Time.get_ticks_msec()\n\tvar previous_x := level.player.position.x\n\twhile Time.get_ticks_msec() < deadline:\n\t\tif person.interaction_available() and Story.framing.is_interaction_target(person):\n\t\t\treturn _check(true, "real movement reaches the actual NPC: " + label)\n\t\tif absf(level.player.position.x - previous_x) > 1.0:\n\t\t\tprogressed = Time.get_ticks_msec()\n\t\t\tprevious_x = level.player.position.x\n\t\telif level.player.is_on_floor() and Time.get_ticks_msec() - progressed > 300:\n\t\t\t_stage("npc-obstacle-jump-input", {"label": label, "player_x": level.player.position.x, "person_x": person.position.x})\n\t\t\t_action(&"jump", true)\n\t\t\tawait get_tree().physics_frame\n\t\t\tawait get_tree().physics_frame\n\t\t\t_action(&"jump", false)\n\t\t\tprogressed = Time.get_ticks_msec()\n\t\tawait get_tree().physics_frame\n\treturn _check(false, "real movement could not reach NPC: " + label)\n\n'+needle)
needle='func _opening() -> bool:\n'
needle_walk='\twhile Time.get_ticks_msec() < deadline:\n\t\tif person.interaction_available()'
assert text.count(needle_walk)==1
text=text.replace(needle_walk,'\twhile Time.get_ticks_msec() < deadline:\n\t\tvar wanted: StringName = &"move_right" if person.position.x > level.player.position.x else &"move_left"\n\t\tvar axis := Input.get_axis(&"move_left", &"move_right")\n\t\tif absf(axis) < 0.1 or (wanted == &"move_right" and axis < 0) or (wanted == &"move_left" and axis > 0):\n\t\t\t_stage("npc-move-reassert", {"axis_before": axis, "wanted": String(wanted), "player_x": level.player.position.x})\n\t\t\t_action(&"move_left", false)\n\t\t\t_action(&"move_right", false)\n\t\t\t_action(wanted, true)\n\t\tvar blocked := false\n\t\tfor i in level.player.get_slide_collision_count():\n\t\t\tblocked = blocked or absf(level.player.get_slide_collision(i).get_normal().x) > 0.5\n\t\tif person.interaction_available()')
text=text.replace('elif level.player.is_on_floor() and Time.get_ticks_msec() - progressed > 300:', 'elif blocked and level.player.is_on_floor() and Time.get_ticks_msec() - progressed > 300:')
text=text.replace('\t\t\treturn _check(true, "real movement reaches the actual NPC: " + label)', '\t\t\t_action(&"move_left", false)\n\t\t\t_action(&"move_right", false)\n\t\t\treturn _check(true, "real movement reaches the actual NPC: " + label)')
text=text.replace('\treturn _check(false, "real movement could not reach NPC: " + label)', '\t_action(&"move_left", false)\n\t_action(&"move_right", false)\n\treturn _check(false, "real movement could not reach NPC: " + label)')
needle_jump='\t\t\t_action(&"jump", true)\n\t\t\tawait get_tree().physics_frame\n\t\t\tawait get_tree().physics_frame\n\t\t\t_action(&"jump", false)'
assert text.count(needle_jump)==1
text=text.replace(needle_jump,'\t\t\t_action(&"jump", true)\n\t\t\tfor tick in 12: await get_tree().physics_frame\n\t\t\t_action(&"jump", false)')
assert text.count(needle)==1
text=text.replace(needle,needle+'\tvar expected_lines := 0\n\tfor entry: Dictionary in StoryRules.entries(Story._scenes[String(INTRO)]):\n\t\tif entry.get("do") == "say": expected_lines += 1\n')
assert text.count('_accept_lines == 3')==1
text=text.replace('_accept_lines == 3','expected_lines > 0 and _accept_lines == expected_lines')
text=text.replace('natural pawnshop opening: three actual complete lines','natural authored prologue: all actual complete lines')
needle='\t\t_saved = store.read()\n'
assert text.count(needle)==1
text=text.replace(needle,needle+'\t\t_expected_world = str(_saved.get("level", ""))\n')
needle='\tif not await _npc_talk(_phase):\n'
assert text.count(needle)==1
text=text.replace(needle,'\tif _phase == "record":\n\t\t# Controlled setup through actual Main area owner; not natural prologue completion.\n\t\t_expected_world = "res://data/levels/ch1_pawnshop.tres"\n\t\tGameState.pending_portal = &""\n\t\t_stage("arranged-pawnshop-route", {"target": _expected_world})\n\t\t_main._on_area_requested(_expected_world)\n\t\tif not await _wait(_world_ready, "real Main controlled route reaches pawnshop"):\n\t\t\tawait _finish()\n\t\t\treturn\n'+needle)
needle='\t_events.append(event)\n'
assert text.count(needle)==1
text=text.replace(needle,'\tevent["since_previous_stage_max_frame_ms"] = _stage_max_frame_ms\n\tif label in ["initial-menu", "menu-settled"]:\n\t\tevent["environment_residency"] = preload("res://tools/texture_route_probe.gd")._loaded()\n\t# Exclude this audit payload readback from subsequent gameplay frame clocks.\n\t_last_wall_usec = Time.get_ticks_usec()\n\t_stage_max_frame_ms = 0.0\n'+needle)
needle='\t_stage("menu-settled", {"label": label, "slot_sha256": FileAccess.get_sha256(_slot)})\n'
assert text.count(needle)==1
text=text.replace(needle,'\tvar drain_deadline := Time.get_ticks_msec() + 30000\n\twhile AssetPrefetch.stats()["queued"] + AssetPrefetch.stats()["inflight"] > 0 and Time.get_ticks_msec() < drain_deadline:\n\t\tawait get_tree().process_frame\n\tif not _check(AssetPrefetch.stats()["queued"] + AssetPrefetch.stats()["inflight"] == 0, "bounded menu prefetch drain before residency snapshot"):\n\t\treturn false\n'+needle)
text=text.replace('BG31','BG32').replace('BG-31','BG-32')
target=Path('C:/NE/bg32-20261117/work/bg32-main-'+tag)
target.mkdir(parents=True,exist_ok=True)
(target/'probe.gd').write_text(text,encoding='utf-8',newline='\n')
(target/'probe.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://work/bg32-main-'+tag+'/probe.gd" id="1"]\n[node name="BG32Main" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8',newline='\n')
(work/('candidate-bg32-main-probe-'+tag+'.gd.txt')).write_text(text,encoding='utf-8',newline='\n')
print('BG32 Main snapshot D source',sha,'original BG31',hashlib.sha256(source).hexdigest())
