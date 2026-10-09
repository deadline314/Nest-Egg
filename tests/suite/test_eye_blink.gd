class_name EyeBlinkSuite
extends TestSuite
## NE-221 deterministic log-normal blink timing, state sequence and safe inputs.

const BLINK_SCRIPT = preload("res://game/rig/eye_blink.gd")
const STEP_60 := 1.0 / 60.0
const STEP_120 := 1.0 / 120.0
const OPEN: StringName = &"open"
const HALF: StringName = &"half"
const CLOSED: StringName = &"closed"


func run() -> void:
	_test_reset_and_skin_seeds()
	_test_lognormal_samples()
	_test_talking_frequency()
	_test_blink_sequence_and_duration(STEP_60)
	_test_blink_sequence_and_duration(STEP_120)
	_test_safe_inputs()
	await _test_character_rig_eye_states()


func _new_blink(skin := "rin", config: Dictionary = {}) -> Variant:
	var blink: Variant = BLINK_SCRIPT.new()
	blink.setup(skin, config)
	return blink


func _test_reset_and_skin_seeds() -> void:
	var config := {"median_interval": 0.5, "log_sigma": 0.2, "seed": 91}
	var first := _onsets(_new_blink("rin", config), 12.0, STEP_120, false)
	var repeat: Variant = _new_blink("rin", config)
	var second := _onsets(repeat, 12.0, STEP_120, false)
	repeat.reset()
	var after_reset := _onsets(repeat, 12.0, STEP_120, false)
	var other_skin := _onsets(_new_blink("old_k", config), 12.0, STEP_120, false)
	check(first == second and second == after_reset, "same skin and seed reproduce intervals after reset")
	check(first.size() >= 8 and other_skin.size() >= 8 and first[0] != other_skin[0], "skin identity deterministically desynchronizes blink phase")


func _test_lognormal_samples() -> void:
	var blink: Variant = _new_blink("stats", {"median_interval": 3.5, "log_sigma": 0.35, "seed": 1701})
	var samples := _onsets(blink, 8000.0, STEP_120, false)
	var logs: Array[float] = []
	for sample in samples:
		logs.append(log(sample))
	logs.sort()
	var mean := 0.0
	for value in logs:
		mean += value
	mean /= float(logs.size())
	var variance := 0.0
	for value in logs:
		variance += (value - mean) * (value - mean)
	variance /= float(logs.size())
	var median := exp(logs[int(logs.size() / 2)])
	var m3 := 0.0
	var raw_mean := 0.0
	for value in samples:
		raw_mean += value
	raw_mean /= float(samples.size())
	for value in samples:
		m3 += pow(value - raw_mean, 3.0)
	m3 /= float(samples.size())
	var raw_variance := 0.0
	for value in samples:
		raw_variance += pow(value - raw_mean, 2.0)
	raw_variance /= float(samples.size())
	var skew := m3 / pow(raw_variance, 1.5)
	check(samples.size() >= 700, "log-normal sample has enough intervals (%d)" % samples.size())
	check(absf(median - 3.5) <= 0.18, "sample median is near 3.5 s (%.3f)" % median)
	check(absf(mean - log(3.5)) <= 0.04 and variance > 0.07 and variance < 0.18, "log intervals have normal-shaped spread (mean %.3f, variance %.3f)" % [mean, variance])
	check(skew > 0.45, "raw intervals show the positive skew of a log-normal distribution (%.2f)" % skew)


func _test_talking_frequency() -> void:
	var config := {"median_interval": 3.5, "log_sigma": 0.35, "talking_frequency": 2.0, "seed": 901}
	var idle := _count_onsets(_new_blink("talk_test", config), 45.0, STEP_120, false)
	var talking := _count_onsets(_new_blink("talk_test", config), 45.0, STEP_120, true)
	check(talking > idle, "talking increases blink frequency (%d idle, %d talking)" % [idle, talking])


func _test_blink_sequence_and_duration(step: float) -> void:
	var blink: Variant = _new_blink("sequence", {"median_interval": 0.5, "log_sigma": 0.0, "duration_range": [0.12, 0.15], "seed": 12})
	var previous: StringName = blink.update(0.0, false)
	var transitions: Array[StringName] = []
	var durations: Array[float] = []
	var elapsed := 0.0
	var start_time := -1.0
	for i in int(35.0 / step):
		elapsed += step
		var state: StringName = blink.update(step, false)
		if state != previous:
			transitions.append(state)
			if previous == OPEN and state == HALF:
				start_time = elapsed
			if previous != OPEN and state == OPEN:
				durations.append(elapsed - start_time)
		previous = state
	check(transitions.size() >= 4 and transitions.slice(0, 4) == [HALF, CLOSED, HALF, OPEN], "blink sequence is half → closed → half → open at %.0f Hz" % (1.0 / step))
	check(durations.size() >= 10, "enough blink durations measured at %.0f Hz (%d)" % [1.0 / step, durations.size()])
	for duration in durations:
		check(duration >= 0.12 - 0.00001 and duration <= 0.15 + 0.00001, "blink duration remains 120–150 ms at %.0f Hz (%.4f)" % [1.0 / step, duration])


func _test_safe_inputs() -> void:
	var baseline: Variant = _new_blink("bad_config")
	var invalid: Variant = _new_blink("bad_config", {
		"seed": "4", "median_interval": NAN, "log_sigma": -1.0,
		"duration_range": [0.2, 0.1], "talking_frequency": INF,
	})
	var wrong_types: Variant = _new_blink("bad_config", {
		"median_interval": "3.5", "log_sigma": [], "duration_range": "0.12–0.15", "talking_frequency": false,
	})
	var same := true
	for i in 1200:
		var a: StringName = baseline.update(STEP_120, false)
		var b: StringName = invalid.update(STEP_120, false)
		var c: StringName = wrong_types.update(STEP_120, false)
		same = same and a == b and a == c
	check(same, "invalid config values and types warn and independently use deterministic defaults")
	var d: Variant = _new_blink("delta")
	check(d.update(0.0, false) == OPEN and d.update(-1.0, false) == OPEN and d.update(NAN, false) == OPEN and d.update(INF, false) == OPEN, "zero, negative and non-finite deltas do not advance the timer")
	var open_after_spike := false
	for i in 1200:
		if d.update(STEP_120, false) == CLOSED:
			open_after_spike = d.update(5.0, false) == OPEN
			break
	check(open_after_spike, "a large delta aborts a blink open without an unbounded catch-up loop")
	var disabled: Variant = _new_blink("disabled", {"median_interval": 0.5, "log_sigma": 0.0})
	var saw_closed := false
	for i in 800:
		if disabled.update(STEP_120, false) == CLOSED:
			saw_closed = true
			break
	check(saw_closed and disabled.update(STEP_120, false, true) == OPEN and disabled.update(100.0, false, true) == OPEN, "disabled state opens immediately and safely pauses timing")
	var resume := false
	for i in 600:
		if disabled.update(STEP_120, false) != OPEN:
			resume = true
			break
	check(resume, "timing resumes after disabled state ends")


func _test_character_rig_eye_states() -> void:
	var rig := _rig_with_eye_states("rin", _valid_eye_config())
	var sprite_id: int = rig._eye_part.get_instance_id() if rig._eye_part != null else 0
	var head_bone_id: int = rig.bone(&"head").get_instance_id() if rig.has_bone(&"head") else 0
	check(rig.is_valid() and rig._eye_blink != null and rig._eye_part != null, "runtime eye_states config binds to the existing head sprite")
	if rig._eye_part != null:
		var part := rig._eye_part
		var original_position := part.position
		var original_rotation := part.rotation
		var original_scale := part.scale
		var original_offset := part.offset
		var original_parent := part.get_parent()
		var normal_texture := part.texture as CanvasTexture
		check(normal_texture != null and normal_texture.normal_texture != null and normal_texture.normal_texture.get_size() == part.texture.get_size(), "head states use LitTextures with a matching normal map")
		var input := RigInput.new()
		input.facing = -1
		var transitions: Array[StringName] = []
		var previous: StringName = rig._eye_state
		for i in 100:
			rig.animate(STEP_60, input)
			if rig._eye_state != previous:
				transitions.append(rig._eye_state)
			previous = rig._eye_state
			var expected: Texture2D = rig._eye_open_texture
			if rig._eye_state == HALF:
				expected = rig._eye_half_texture
			elif rig._eye_state == CLOSED:
				expected = rig._eye_closed_texture
			check(part.texture == expected, "runtime %s state keeps the selected texture in the original head slot" % rig._eye_state)
		check(transitions.size() >= 4 and transitions.slice(0, 4) == [HALF, CLOSED, HALF, OPEN], "CharacterRig animates all eye states in order")
		check(part.get_instance_id() == sprite_id and part.get_parent() == original_parent and original_parent == rig.bone(&"head"), "eye updates preserve the original head node and bone attachment")
		check(rig.bone(&"head").get_instance_id() == head_bone_id and part.position == original_position and is_equal_approx(part.rotation, original_rotation) and part.scale == original_scale and part.offset == original_offset, "eye updates preserve head bone, pivot, transform, and texture canvas")
		check(part.material == rig._light_material, "eye texture changes retain the shared character-light shader")
		# A manually paused tree must not advance the eye timer; normal pause also stops the owners from calling animate.
		var until_blink: float = rig._eye_blink._time_to_next
		runner.get_tree().paused = true
		rig.animate(STEP_60, input)
		runner.get_tree().paused = false
		check(is_equal_approx(rig._eye_blink._time_to_next, until_blink), "paused scene time does not advance the eye timer")
		# Force a visible state, then verify death opens it and freezes the remaining interval until revival.
		for i in 100:
			rig.animate(STEP_60, input)
			if rig._eye_state == CLOSED:
				break
		var remaining: float = rig._eye_blink._time_to_next
		input.dead = true
		rig.animate(STEP_60, input)
		check(rig._eye_state == OPEN and part.texture == rig._eye_open_texture, "dead state immediately restores the original open eyes")
		check(is_equal_approx(rig._eye_blink._time_to_next, remaining), "dead state safely pauses the blink schedule")
		input.dead = false
		rig.animate(STEP_60, input)
		check(rig._eye_blink != null and rig._eye_state == OPEN, "living state resumes with open eyes")
	_free_rig(rig)

	var missing_part := _rig_with_eye_states("rin", {"part": "missing_head", "half_texture": "head", "closed_texture": "head"})
	check(missing_part.is_valid() and missing_part._eye_blink == null and _head_texture_unchanged(missing_part), "missing eye part safely preserves the original head")
	_free_rig(missing_part)
	var missing_texture := _rig_with_eye_states("rin", {"part": "head", "half_texture": "no_such_eye", "closed_texture": "head"})
	check(missing_texture.is_valid() and missing_texture._eye_blink == null and _head_texture_unchanged(missing_texture), "missing eye texture safely preserves the original head")
	_free_rig(missing_texture)
	var wrong_size := _rig_with_eye_states("rin", {"part": "head", "half_texture": "pelvis", "closed_texture": "head"})
	check(wrong_size.is_valid() and wrong_size._eye_blink == null and _head_texture_unchanged(wrong_size), "wrong-size eye texture safely preserves the original head")
	_free_rig(wrong_size)
	var missing_file_config := _valid_eye_config()
	var damaged_skin := RigLibrary.character("rin").duplicate(true)
	var head_def: Dictionary = damaged_skin["textures"]["head"].duplicate(true)
	head_def["file"] = "parts/eye_state_file_missing.png"
	damaged_skin["textures"]["test_missing_file"] = head_def
	missing_file_config["half_texture"] = "test_missing_file"
	var missing_file := _rig_with_eye_states("rin", missing_file_config, damaged_skin["textures"])
	check(missing_file.is_valid() and missing_file._eye_blink == null and _head_texture_unchanged(missing_file), "missing eye source file safely preserves the original head")
	_free_rig(missing_file)
	var invalid_timing_config := _valid_eye_config()
	invalid_timing_config["timing"] = {"median_interval": NAN, "duration_range": [0.2, 0.1], "talking_frequency": "fast"}
	var invalid_timing := _rig_with_eye_states("rin", invalid_timing_config)
	check(invalid_timing.is_valid() and invalid_timing._eye_blink != null and invalid_timing._eye_state == OPEN, "non-finite timing values use EyeBlink safe defaults without losing the original head")
	_free_rig(invalid_timing)
	var no_config := _rig_with_eye_states("rin", null)
	check(no_config.is_valid() and no_config._eye_blink == null and _head_texture_unchanged(no_config), "characters without runtime eye_states keep their original head")
	_free_rig(no_config)

	var mei := _rig_with_eye_states("mei", _valid_eye_config())
	var glow_material := mei._eye_glow.material as CanvasItemMaterial if mei._eye_glow != null else null
	check(mei._eye_glow != null and glow_material != null and glow_material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and mei._eye_glow.texture.get_size() == mei._eye_part.texture.get_size(), "existing head glow slot remains additive and matches the eye canvas")
	var glow_before: Texture2D = mei._eye_glow.texture if mei._eye_glow != null else null
	mei.animate(STEP_60, RigInput.new())
	for i in 100:
		mei.animate(STEP_60, RigInput.new())
	check(mei._eye_glow == null or mei._eye_glow.texture == glow_before, "eye state changes never replace the character glow with a diffuse texture")
	_free_rig(mei)

	var other := _rig_with_eye_states("old_k", _valid_eye_config())
	var rin_again := _rig_with_eye_states("rin", _valid_eye_config())
	check(other._eye_blink != rin_again._eye_blink, "each CharacterRig owns an independent EyeBlink instance")
	var other_onsets: Array[int] = []
	var rin_onsets: Array[int] = []
	var other_previous: StringName = other._eye_state
	var rin_previous: StringName = rin_again._eye_state
	for i in 480:
		other.animate(STEP_60, RigInput.new())
		rin_again.animate(STEP_60, RigInput.new())
		if other_previous == OPEN and other._eye_state == HALF:
			other_onsets.append(i)
		if rin_previous == OPEN and rin_again._eye_state == HALF:
			rin_onsets.append(i)
		other_previous = other._eye_state
		rin_previous = rin_again._eye_state
	check(not other_onsets.is_empty() and not rin_onsets.is_empty() and other_onsets != rin_onsets, "different character skins do not synchronize their runtime blink phase")
	_free_rig(other)
	_free_rig(rin_again)

	var idle := _rig_with_eye_states("rin", _valid_eye_config())
	var talking := _rig_with_eye_states("rin", _valid_eye_config())
	var idle_count := 0
	var talking_count := 0
	var idle_previous: StringName = idle._eye_state
	var talk_previous: StringName = talking._eye_state
	var idle_input := RigInput.new()
	var talk_input := RigInput.new()
	talk_input.talking = true
	for i in 720:
		idle.animate(STEP_60, idle_input)
		talking.animate(STEP_60, talk_input)
		if idle_previous == OPEN and idle._eye_state == HALF:
			idle_count += 1
		if talk_previous == OPEN and talking._eye_state == HALF:
			talking_count += 1
		idle_previous = idle._eye_state
		talk_previous = talking._eye_state
	check(talking_count > idle_count, "talking input increases CharacterRig blink frequency (%d idle, %d talking)" % [idle_count, talking_count])
	_free_rig(idle)
	_free_rig(talking)


func _valid_eye_config() -> Dictionary:
	return {
		"part": "head",
		"half_texture": "head",
		"closed_texture": "head",
		"timing": {"median_interval": 0.5, "log_sigma": 0.2, "duration_range": [0.12, 0.15], "talking_frequency": 2.0, "seed": 91},
	}


func _rig_with_eye_states(skin_id: String, eye_states: Variant, texture_overrides: Dictionary = {}) -> CharacterRig:
	var cache_path := RigLibrary.CHARACTER_PATH % skin_id
	var had_cached := RigLibrary._json_cache.has(cache_path)
	var previous: Dictionary = RigLibrary._json_cache.get(cache_path, {})
	var skin := RigLibrary.character(skin_id).duplicate(true)
	var textures: Dictionary = skin.get("textures", {})
	for key: Variant in texture_overrides:
		textures[key] = texture_overrides[key]
	skin["textures"] = textures
	if eye_states == null:
		skin.erase("eye_states")
	else:
		skin["eye_states"] = eye_states
	RigLibrary._json_cache[cache_path] = skin
	var holder := Node2D.new()
	runner.get_tree().root.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	var valid := rig.setup(skin_id)
	check(valid, "CharacterRig setup succeeds for runtime eye-state fixture %s" % skin_id)
	if had_cached:
		RigLibrary._json_cache[cache_path] = previous
	else:
		RigLibrary._json_cache.erase(cache_path)
	return rig


func _head_texture_unchanged(rig: CharacterRig) -> bool:
	if rig == null or rig._eye_part != null:
		return false
	for part in rig._parts:
		if str(part.name) == "head" and part is Sprite2D:
			return (part as Sprite2D).texture != null and (part as Sprite2D).texture.get_size() == Vector2(RigLibrary.vec2(RigLibrary.character(rig.skin_id).get("textures", {}).get("head", {}).get("size")))
	return false


func _free_rig(rig: CharacterRig) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var holder := rig.get_parent()
	if holder != null:
		holder.queue_free()
	else:
		rig.queue_free()


func _onsets(blink, seconds: float, step: float, talking: bool) -> Array[float]:
	var result: Array[float] = []
	var previous: StringName = OPEN
	var elapsed := 0.0
	var last_open := 0.0
	for i in int(seconds / step):
		elapsed += step
		var state: StringName = blink.update(step, talking)
		if previous != OPEN and state == OPEN:
			last_open = elapsed
		elif previous == OPEN and state == HALF:
			result.append(elapsed - last_open)
		previous = state
	return result


func _count_onsets(blink, seconds: float, step: float, talking: bool) -> int:
	return _onsets(blink, seconds, step, talking).size()
