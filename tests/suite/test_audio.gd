class_name AudioSuite
extends EnemySuiteBase
## 音效庫與聲音設定表（NE-156）：檔案優先、缺檔退回合成音、變體輪播、武器與角色查表、資料檢查。
## 缺檔測試用的路徑與 id 含 test_audio_missing，執行器會忽略它的錯誤輸出。

const FIXTURES := "res://tests/fixtures/audio/"
const SOURCE_DIRS: PackedStringArray = ["res://game", "res://ui", "res://autoload", "res://core"]
const MANIFEST_PATH := "res://assets_src/audio/manifest.json"
const LICENSES_PATH := "res://assets_src/audio/LICENSES.json"


func run() -> void:
	_test_shipped_data()
	_test_licenses()
	_test_bank_loading()
	_test_bank_validation()
	await _test_sfx_uses_files()
	_test_profile_table()
	_test_profile_validation()
	_test_weapon_sounds()
	_test_character_sounds()
	_test_loadout_switch_signal()
	_test_gun_sounds()
	_test_impact_and_character_sounds()
	await _test_hurt_voice_cooldown()
	_test_world_sounds()
	_test_footstep_data()
	await _test_footsteps_in_play()
	await _test_zone_signal_and_terrain_surface()
	_test_crossfade_player()
	await _test_ambience()
	_test_ambience_bus()
	_test_numbering_and_catalog()
	_test_placement_doc()
	_test_source_counts()


func _fixture_bank(file: String) -> SoundBank:
	var bank := SoundBank.new()
	bank.load_bank(FIXTURES + file, true)
	return bank


func _test_shipped_data() -> void:
	var errors: PackedStringArray = Sfx.bank().validate()
	check(errors.is_empty(), "sound bank data has no errors: %s" % ", ".join(errors))
	errors = WeaponSounds.validate()
	check(errors.is_empty(), "weapon sounds data has no errors: %s" % ", ".join(errors))
	errors = CharacterSounds.validate()
	check(errors.is_empty(), "character sounds data has no errors: %s" % ", ".join(errors))
	var sound_re := RegEx.create_from_string("Sfx\\.play\\(&\"([a-z0-9_]+)\"")
	for dir in SOURCE_DIRS:
		for path in _gd_files(dir):
			for m in sound_re.search_all(FileAccess.get_file_as_string(path)):
				var id := m.get_string(1)
				if id.begins_with("test_"):
					continue
				check(Sfx.has_sound(StringName(id)), "%s plays unknown sound %s" % [path, id])
	for file in DirAccess.get_files_at("res://data/weapons"):
		if file.ends_with(".tres"):
			var weapon := load("res://data/weapons/" + file) as WeaponData
			check(Sfx.has_sound(weapon.fire_sound), "weapon %s fire_sound exists: %s" % [weapon.id, weapon.fire_sound])


## 授權：素材目錄只收 CC0；遊戲內每一個音訊檔都查得到出處；音效庫的 pack 都在授權登記裡。
func _test_licenses() -> void:
	var manifest := _read_source_json(MANIFEST_PATH)
	var packs: Array = manifest.get("packs", [])
	check(not packs.is_empty(), "audio source manifest lists packs")
	var manifest_ids: Dictionary = {}
	for pack: Dictionary in packs:
		manifest_ids[str(pack.get("id", ""))] = true
		var label := "manifest pack %s" % pack.get("id", "?")
		check(str(pack.get("license", "")).begins_with("CC0"), "%s is CC0 (%s)" % [label, pack.get("license", "")])
		check(not str(pack.get("page", "")).is_empty() and not str(pack.get("author", "")).is_empty() and pack.get("download") != null, "%s records author, page and download" % label)
	check(manifest_ids.size() == packs.size(), "manifest pack ids are unique")
	var registry := _read_source_json(LICENSES_PATH)
	for pack_id: String in registry.keys():
		check(manifest_ids.has(pack_id), "registered pack %s exists in the manifest" % pack_id)
		check(str((registry[pack_id] as Dictionary).get("license", "")).begins_with("CC0"), "registered pack %s is CC0" % pack_id)
	var known := PackedStringArray(registry.keys())
	var bank_errors: PackedStringArray = Sfx.bank().validate(known)
	check(bank_errors.is_empty(), "every sound bank entry names a registered license pack: %s" % ", ".join(bank_errors))
	var referenced: Dictionary = {}
	for id: Variant in Sfx.bank().ids():
		for file in Sfx.bank().files_of(StringName(str(id))):
			referenced[file] = true
	var music := AudioData.read_root("res://data/audio/music.json", "AudioSuite", PackedStringArray()) if ResourceLoader.exists("res://data/audio/music.json") else {}
	for track: Variant in (music.get("tracks", {}) as Dictionary).values():
		referenced[str((track as Dictionary).get("file", ""))] = true
	for path in _audio_files("res://audio"):
		check(referenced.has(path), "audio file is used by the sound bank or music list: %s" % path)
	for path in referenced.keys():
		check(ResourceLoader.exists(path), "referenced audio file exists: %s" % path)


## assets_src/ 有 .gdignore（不匯入），所以不能走 ResourceLoader，直接讀檔。
func _read_source_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(typeof(parsed) == TYPE_DICTIONARY, "%s is a JSON object" % path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _audio_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in ["ogg", "wav", "mp3"]:
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_audio_files(dir.path_join(sub)))
	return result


func _gd_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_gd_files(dir.path_join(sub)))
	return result


func _test_bank_loading() -> void:
	var bank := _fixture_bank("bank_ok.json")
	check(bank.has_files(&"test_audio_one") and bank.variants(&"test_audio_one").size() == 1, "bank loads a single file")
	check(bank.variants(&"test_audio_two").size() == 2, "bank loads every variant")
	check(is_equal_approx(bank.volume_db(&"test_audio_one"), -3.0) and bank.pitch_range(&"test_audio_one") == Vector2(0.9, 1.1), "bank reads volume and pitch range")
	check(bank.pitch_range(&"test_audio_two") == Vector2.ONE and bank.volume_db(&"test_audio_two") == 0.0, "bank defaults: no pitch change, 0 dB")
	check(bank.packs_of(&"test_audio_one") == PackedStringArray(["test_pack"]), "bank keeps the license pack id")
	check(bank.variants(&"test_audio_half").size() == 1 and (bank.failed_files()[&"test_audio_half"] as PackedStringArray).size() == 1, "a missing variant is skipped and recorded, the others still load")
	check(not bank.has_files(&"test_audio_none") and bank.failed_files().has(&"test_audio_none"), "an id with no loadable file reports no files")
	var missing := SoundBank.new()
	missing.load_bank(FIXTURES + "test_audio_missing_bank.json", true)
	check(missing.ids().is_empty() and not missing.has_files(&"hit"), "a missing bank file leaves an empty bank instead of crashing")


func _test_bank_validation() -> void:
	var errors := _fixture_bank("bank_ok.json").validate()
	check(errors.size() == 2, "validation flags the two ids with missing files (%d): %s" % [errors.size(), ", ".join(errors)])
	errors = _fixture_bank("bank_bad.json").validate()
	var text := "\n".join(errors)
	check(text.contains("test_audio_nofiles") and text.contains("非空"), "validation flags an empty file list")
	check(text.contains("test_audio_badext") and text.contains("副檔名"), "validation flags a non-audio extension")
	check(text.contains("test_audio_gone") and text.contains("不存在的檔案"), "validation flags a missing file with its path")
	check(text.contains("test_audio_pitch") and text.contains("pitch"), "validation flags a reversed pitch range")
	check(text.contains("test_audio_field") and text.contains("colour"), "validation flags an unknown field")
	var packs := _fixture_bank("bank_ok.json").validate(PackedStringArray(["only_pack"]))
	check("\n".join(packs).contains("test_pack"), "validation checks the pack id against the license registry")


func _test_sfx_uses_files() -> void:
	Sfx.bank().load_bank(FIXTURES + "bank_ok.json", true)
	Sfx._build_streams()
	check(Sfx.source_of(&"hit") == &"file", "an id in the bank plays from file")
	check(Sfx.source_of(&"explosion") == &"synth", "an id not in the bank keeps the synthesized sound")
	check(Sfx.source_of(&"test_audio_none") == &"synth" or Sfx.source_of(&"test_audio_none") == &"missing", "an id whose files all failed is not served from file")
	check(Sfx.has_sound(&"test_audio_one") and Sfx.source_of(&"test_audio_one") == &"file", "a bank-only id is a valid sound")
	check(not Sfx.has_sound(&"test_audio_none"), "an id with no usable file and no synth is undefined")
	Sfx.stop_all()
	Sfx._last_play_msec.clear()
	var lengths: Dictionary = {}
	for n in 12:
		Sfx._last_play_msec.clear()
		Sfx._voice_end_msec.fill(0)
		check(Sfx._play_voice(&"test_audio_two", 0.0, 1.0, 0), "bank sound plays")
		var index: int = (Sfx._next_voice + Sfx._players.size() - 1) % Sfx._players.size()
		lengths[snappedf(Sfx._players[index].stream.get_length(), 0.01)] = n
	check(lengths.size() == 2, "both variants get played over repeated plays (%d)" % lengths.size())
	var last := -1.0
	var repeated := false
	for n in 20:
		Sfx._last_play_msec.clear()
		Sfx._voice_end_msec.fill(0)
		Sfx._play_voice(&"test_audio_two", 0.0, 1.0, 0)
		var index: int = (Sfx._next_voice + Sfx._players.size() - 1) % Sfx._players.size()
		var length := snappedf(Sfx._players[index].stream.get_length(), 0.01)
		repeated = repeated or is_equal_approx(length, last)
		last = length
	check(not repeated, "the same variant is never played twice in a row")
	Sfx._last_play_msec.clear()
	Sfx._voice_end_msec.fill(0)
	Sfx._play_voice(&"test_audio_one", 0.0, 1.0, 0)
	var one_index: int = (Sfx._next_voice + Sfx._players.size() - 1) % Sfx._players.size()
	check(Sfx._players[one_index].volume_db <= -3.0 + 0.001, "the bank's volume_db is applied (%.2f)" % Sfx._players[one_index].volume_db)
	Sfx.stop_all()
	# 還原真正的音效庫，避免影響之後的套件。
	Sfx.reload_bank(true)
	check(Sfx.source_of(&"test_audio_one") == &"missing", "reloading restores the shipped bank")
	await frames(1)


func _test_profile_table() -> void:
	var table := SoundProfileTable.new(FIXTURES + "profiles_ok.json", "AudioSuite", PackedStringArray(["hurt", "death", "telegraph"]))
	var has_name := Sfx.has_named
	check(table.resolve(&"base", &"hurt", {}, has_name) == &"hit", "profile returns its own value")
	check(table.resolve(&"child", &"hurt", {}, has_name) == &"hit", "extends passes down unspecified actions")
	check(table.resolve(&"child", &"death", {}, has_name) == &"", "an empty string silences the action even if the parent has a sound")
	check(table.resolve(&"grandchild", &"hurt", {}, has_name) == &"hit", "extends chains through more than one level")
	check(table.resolve(&"nobody", &"death", {}, has_name) == &"kill_enemy", "unknown profile falls back to default")
	check(table.resolve(&"nobody", &"hurt", {}, has_name) == &"", "default may be silent")
	check(table.resolve(&"nobody", &"telegraph", {"attack_category": "melee"}, has_name) == &"telegraph_melee", "{key} placeholders are filled from the context")
	check(table.resolve(&"nobody", &"telegraph", {"attack_category": "test_no_such_category"}, has_name) == &"telegraph", "a list falls through to the first name that exists")
	check(table.resolve(&"chain", &"telegraph", {}, has_name) == &"block", "list skips names that do not exist")
	check(table.resolve(&"base", &"test_no_such_action", {}, has_name) == &"", "unknown action is silent")
	check(table.validate(has_name).is_empty(), "valid profile data has no errors: %s" % ", ".join(table.validate(has_name)))
	var broken := SoundProfileTable.new(FIXTURES + "test_audio_missing_profiles.json", "AudioSuite", PackedStringArray(["hurt"]))
	check(broken.resolve(&"x", &"hurt", {}, has_name) == &"", "missing profile file resolves to silence instead of crashing")


func _test_profile_validation() -> void:
	var table := SoundProfileTable.new(FIXTURES + "profiles_bad.json", "AudioSuite", PackedStringArray(["hurt", "death"]))
	var text := "\n".join(table.validate(Sfx.has_named))
	check(text.contains("default 缺少動作「death」"), "validation requires every action in default")
	check(text.contains("引用不存在的聲音"), "validation flags a sound that does not exist")
	check(text.contains("形成迴圈"), "validation flags an extends cycle")
	check(text.contains("extends 不存在的「test_no_such_profile」"), "validation flags a missing extends target")
	check(text.contains("不認得的動作「flying」"), "validation flags an unknown action")
	check(text.contains("要是字串或字串陣列"), "validation flags a wrong value type")
	check(table.resolve(&"a", &"death", {}, Sfx.has_named) == &"", "a cyclic extends chain still resolves without hanging")


func _test_weapon_sounds() -> void:
	for kind in WeaponSounds.KINDS:
		check(WeaponSounds.table().raw_default().has(kind), "weapon sounds default covers %s" % kind)
	check(WeaponSounds.name_for(&"test_no_such_weapon", &"empty") == &"empty", "unknown weapon uses the default empty-click")
	check(WeaponSounds.name_for(&"", &"reload_done") == &"reload_done", "no weapon uses the default")
	WeaponSounds.play(null, &"reload_start", -80.0)
	check(true, "playing with no weapon does not fail")
	for file in DirAccess.get_files_at("res://data/weapons"):
		if file.ends_with(".tres"):
			var weapon := load("res://data/weapons/" + file) as WeaponData
			for kind in ["reload_start", "reload_done", "empty"]:
				check(WeaponSounds.name_for(weapon.id, StringName(kind)) != &"", "weapon %s has a %s sound" % [weapon.id, kind])


func _test_character_sounds() -> void:
	for kind in CharacterSounds.KINDS:
		check(CharacterSounds.table().raw_default().has(kind), "character sounds default covers %s" % kind)
	check(CharacterSounds.name_for(&"test_no_such_enemy", &"death") == &"kill_enemy", "unregistered enemy uses the default death sound")
	check(CharacterSounds.name_for(&"test_no_such_enemy", &"attack") == &"shot_enemy", "unregistered enemy uses the default attack sound")
	check(CharacterSounds.name_for(&"player", &"hurt") == &"hurt", "the player has its own hurt sound")
	for category in ["melee", "ranged", "beam", "charge", "explosive", "support"]:
		check(CharacterSounds.name_for(&"grunt", &"telegraph", {"attack_category": category}) != &"", "telegraph sound exists for %s attacks" % category)
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			var enemy := load("res://data/enemies/" + file) as EnemyData
			check(CharacterSounds.name_for(enemy.id, &"death") != &"", "enemy %s has a death sound" % enemy.id)


func _test_loadout_switch_signal() -> void:
	var loadout := Loadout.new()
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	var rifle := load("res://data/weapons/rifle.tres") as WeaponData
	loadout.reset(pistol)
	var switches := [0]
	loadout.weapon_switched.connect(func() -> void: switches[0] += 1)
	loadout.equip(rifle)
	check(switches[0] == 1, "picking up a new weapon emits weapon_switched")
	loadout.equip(rifle)
	check(switches[0] == 1, "re-picking the same weapon does not emit weapon_switched")
	loadout.cycle(1)
	check(switches[0] == 2, "cycling weapons emits weapon_switched")
	loadout.select(loadout.active_slot)
	check(switches[0] == 2, "selecting the current weapon does not emit weapon_switched")


## 槍械與近戰（NE-157）：每把武器的射擊聲是錄音素材、有變體、彼此不共用檔案；換彈與空槍依武器類型不同；近戰出手與命中是錄音素材。
func _test_gun_sounds() -> void:
	var owners: Dictionary = {}
	var reload_ids: Dictionary = {}
	for file in DirAccess.get_files_at("res://data/weapons"):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("res://data/weapons/" + file) as WeaponData
		check(Sfx.source_of(weapon.fire_sound) == &"file", "weapon %s fire sound %s plays from files" % [weapon.id, weapon.fire_sound])
		check(Sfx.bank().variants(weapon.fire_sound).size() >= 2, "weapon %s fire sound has at least two variants" % weapon.id)
		for stream: AudioStream in Sfx.bank().variants(weapon.fire_sound):
			check(stream.get_length() <= 2.0, "weapon %s fire variant is short enough to overlap in a firefight (%.2fs)" % [weapon.id, stream.get_length()])
		for path in Sfx.bank().files_of(weapon.fire_sound):
			check(not owners.has(path) or owners[path] == weapon.fire_sound, "fire sound files are not shared between weapons: %s" % path)
			owners[path] = weapon.fire_sound
		for kind in ["reload_start", "reload_mid", "reload_done", "empty"]:
			var id := WeaponSounds.name_for(weapon.id, StringName(kind))
			check(Sfx.source_of(id) == &"file", "weapon %s %s plays from files (%s)" % [weapon.id, kind, id])
			if kind == "reload_start":
				reload_ids[id] = true
	check(reload_ids.size() >= 5, "reload sounds differ by weapon family (%d)" % reload_ids.size())
	check(CharacterSounds.name_for(&"sniper", &"attack") != CharacterSounds.name_for(&"grunt", &"attack"), "the sniper's shot differs from a grunt's")
	check(Sfx.source_of(CharacterSounds.name_for(&"grunt", &"attack")) == &"file", "enemy shots play from files")
	check(Sfx.source_of(&"shot_enemy") == &"file" and not Sfx.bank().files_of(&"shot_enemy").is_empty() and owners.has(Sfx.bank().files_of(&"shot_enemy")[0]) == false, "enemy shots do not reuse a player weapon's files")
	for id in MeleeData.combo():
		var sounds: Dictionary = MeleeData.attack(str(id))["sounds"]
		check(Sfx.source_of(StringName(sounds["swing"])) == &"file" and Sfx.source_of(StringName(sounds["hit"])) == &"file", "melee %s swing and hit play from files" % id)
	check(Sfx.source_of(&"finisher") == &"file", "the finisher plays from files")
	var master := AudioServer.get_bus_index(&"Master")
	var limiters := 0
	for i in AudioServer.get_bus_effect_count(master):
		limiters += 1 if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter else 0
	check(limiters == 1, "the master bus has exactly one hard limiter against clipping (%d)" % limiters)


## 受擊與角色（NE-158）：材質、跳彈、弱點、格擋、爆炸、敵人與玩家的受擊與死亡都是錄音素材，且機械、人形、生物彼此不同。
func _test_impact_and_character_sounds() -> void:
	var material_files: Dictionary = {}
	for material in HitFeedback.material_ids():
		var def: Dictionary = HitFeedback._data["materials"][material]
		var sound := StringName(str(def["sound"]))
		_check_event_from_files(sound, "material %s" % material)
		for layer: Dictionary in Sfx._events[String(sound)]["layers"]:
			for name: String in layer["sounds"]:
				for path in Sfx.bank().files_of(StringName(name)):
					check(not material_files.has(path) or material_files[path] == material, "material sounds do not share files between materials: %s" % path)
					material_files[path] = material
	for key in ["ricochet", "weak"]:
		_check_event_from_files(StringName(str(HitFeedback._data[key]["sound"])), key)
	for event in [&"hit_enemy", &"hit_heavy", &"kill_enemy", &"death_humanoid", &"death_machine", &"death_creature"]:
		_check_event_from_files(event, "event %s" % event)
	for sound in [&"block", &"parry", &"guard_break", &"explosion", &"explosion_small", &"hurt", &"kill", &"hit"]:
		check(Sfx.source_of(sound) == &"file", "%s plays from files" % sound)
	var death := {}
	var hurt := {}
	for id in [&"grunt", &"turret", &"shock_hound", &"drone", &"sniper", &"warden"]:
		death[id] = CharacterSounds.name_for(id, &"death")
		hurt[id] = CharacterSounds.name_for(id, &"hurt")
		check(hurt[id] != &"" and Sfx.source_of(hurt[id]) == &"file", "%s has a recorded hurt sound (%s)" % [id, hurt[id]])
		check(death[id] != &"" and Sfx.has_event(death[id]), "%s has a death event (%s)" % [id, death[id]])
	check(death[&"grunt"] != death[&"turret"] and death[&"turret"] != death[&"shock_hound"] and death[&"grunt"] != death[&"shock_hound"], "humanoid, machine and creature deaths differ")
	check(death[&"drone"] == death[&"turret"] and hurt[&"drone"] == hurt[&"warden"], "drones and bosses of the machine family share its voice")
	check(hurt[&"sniper"] == hurt[&"grunt"], "humanoids share the humanoid hurt voice")
	check(CharacterSounds.name_for(&"player", &"hurt") != hurt[&"grunt"], "the player's hurt voice differs from the enemies'")
	check(CharacterSounds.name_for(&"player", &"death") == &"death_player" and Sfx.source_of(&"death_player") == &"file", "the player has a recorded death sound")
	check(CharacterSounds.name_for(&"test_no_such_enemy", &"death") == &"kill_enemy", "an unregistered enemy still dies with a sound")
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			var enemy := load("res://data/enemies/" + file) as EnemyData
			check(CharacterSounds.table().has_profile(enemy.id), "enemy %s has a sound profile" % enemy.id)


func _check_event_from_files(event: StringName, label: String) -> void:
	check(Sfx.has_event(event), "%s exists" % label)
	for layer: Dictionary in Sfx._events.get(String(event), {}).get("layers", []):
		for name: String in layer["sounds"]:
			check(Sfx.source_of(StringName(name)) == &"file", "%s layer sound %s plays from files" % [label, name])


## 連發打中同一隻敵人，受擊叫聲不會每發都響。
func _test_hurt_voice_cooldown() -> void:
	await open_level(10.0)
	var enemy := spawn(GRUNT_PATH, 20.0)
	await physics_frames(2)
	Sfx._last_play_msec.erase(&"hurt_humanoid")
	enemy.hurtbox.receive(hit(1))
	var first: int = Sfx._last_play_msec.get(&"hurt_humanoid", -1)
	check(first >= 0, "the first hit makes the enemy cry out")
	await physics_frames(4)
	enemy.hurtbox.receive(hit(1))
	check(Sfx._last_play_msec.get(&"hurt_humanoid", -1) == first, "a second hit right after does not repeat the cry")
	enemy._hurt_voice_left = 0.0
	await physics_frames(2)
	Sfx._last_play_msec.erase(&"hurt_humanoid")
	enemy.hurtbox.receive(hit(1))
	check(Sfx._last_play_msec.has(&"hurt_humanoid"), "after the cooldown the enemy can cry out again")
	await end_level(level)


## 機關、拾取、電話亭、介面、移動、環境（NE-159）：都是錄音素材；電話撥號音維持標準 DTMF 合成音。
func _test_world_sounds() -> void:
	for id in [&"jump", &"land", &"dash", &"switch", &"gate", &"power_down", &"power_up", &"emp", &"overclock", &"ability_ready", &"pickup",
			&"crate_break", &"glass_break", &"telegraph", &"beep", &"alarm", &"laser_flash", &"flame", &"ignite", &"spin", &"vent", &"growl",
			&"zap", &"rattle", &"chomp", &"thunder", &"phone_pickup", &"phone_hangup", &"phone_ring", &"phone_voice",
			&"ui_move", &"ui_confirm", &"ui_cancel", &"ui_error"]:
		check(Sfx.source_of(id) == &"file", "%s plays from files" % id)
	for id in [&"phone_dial", &"phone_dial2", &"phone_dial3"]:
		check(Sfx.source_of(id) == &"synth", "%s keeps the standard DTMF tones" % id)
	for id in [&"ui_move", &"ui_confirm", &"ui_cancel", &"ui_error", &"telegraph", &"beep"]:
		for stream: AudioStream in Sfx.bank().variants(id):
			check(stream.get_length() <= 1.0, "interface sound %s is short (%.2fs)" % [id, stream.get_length()])
	check(Sfx.source_of(&"ui_cancel") != &"missing" and Sfx.source_of(&"ui_error") != &"missing", "closing and error sounds are defined")
	for id in Sfx.bank().ids():
		if str(id).begins_with("amb_"):
			check(bool(Sfx.bank().def(StringName(str(id))).get("loop", false)), "ambience %s is marked as a loop" % id)


func _test_footstep_data() -> void:
	var terrain_ids := PackedStringArray()
	for file in DirAccess.get_files_at("res://data/environment/materials"):
		if file.ends_with(".tres"):
			terrain_ids.append(file.trim_suffix(".tres"))
	var errors := Footsteps.validate(terrain_ids)
	check(errors.is_empty(), "footstep data covers every terrain material: %s" % ", ".join(errors))
	check(Footsteps.surface_for_material(&"steel_plate") == &"metal" and Footsteps.surface_for_material(&"concrete") == &"concrete" and Footsteps.surface_for_material(&"asphalt") == &"wet", "terrain materials map to metal, concrete and wet surfaces")
	check(Footsteps.surface_for_material(&"") == &"concrete" and Footsteps.surface_for_material(&"test_no_such_material") == &"concrete", "no material or an unknown one uses the default surface")
	var steps := {}
	for surface in Footsteps.surfaces():
		var step := Footsteps.name_for(surface, &"step")
		var land := Footsteps.name_for(surface, &"land")
		check(Sfx.source_of(step) == &"file" and Sfx.source_of(land) == &"file", "surface %s step and land play from files (%s, %s)" % [surface, step, land])
		steps[step] = true
	check(steps.size() == Footsteps.surfaces().size(), "every surface has its own footstep sound")


## 走路會有腳步聲：依距離計步、停下或在空中沒有、蹲著比較輕。
func _test_footsteps_in_play() -> void:
	await open_level(10.0)
	var player := level.player
	await physics_frames(10)
	var base := Footsteps.played_count
	Input.action_press(&"move_right")
	await physics_frames(60)
	Input.action_release(&"move_right")
	var walked := Footsteps.played_count - base
	check(walked >= 3 and walked <= 12, "walking for a second makes a handful of footsteps (%d)" % walked)
	await physics_frames(40)
	base = Footsteps.played_count
	await physics_frames(30)
	check(Footsteps.played_count == base, "standing still makes no footsteps")
	player.global_position.y -= 120.0
	player.velocity = Vector2(120.0, 0.0)
	base = Footsteps.played_count
	await physics_frames(6)
	check(Footsteps.played_count == base, "no footsteps while in the air")
	await physics_frames(60)
	await end_level(level)


## 進入關卡時宣告所在區段、離開時宣告空 id；腳下材質查得到。
func _test_zone_signal_and_terrain_surface() -> void:
	var zones: Array[StringName] = []
	var listener := func(id: StringName) -> void: zones.append(id)
	EventBus.zone_changed.connect(listener)
	var data := load("res://data/levels/level_01.tres") as LevelData
	var lvl := await start_level(data)
	await frames(3)
	check(not zones.is_empty() and zones[0] == &"rooftop", "entering level 1 announces its first lighting zone (%s)" % [zones])
	var terrain := lvl.get_tree().get_first_node_in_group(&"terrain") as Terrain
	check(terrain != null, "the terrain registers itself for footstep lookups")
	if terrain != null:
		var material := terrain.material_id_at(lvl.player.global_position + Vector2(0.0, 4.0))
		check(material != &"" and Footsteps.surface_for_material(material) != &"", "the terrain under the player's feet has a material (%s)" % material)
		var outside := terrain.material_id_at(Vector2(-5000.0, 0.0))
		check(Footsteps.surface_for_material(outside) != &"", "a position outside the map still resolves to a surface (%s)" % outside)
	await end_level(lvl)
	await frames(2)
	check(zones.back() == &"", "leaving the level announces an empty zone")
	EventBus.zone_changed.disconnect(listener)


func _test_crossfade_player() -> void:
	var fader := CrossfadePlayer.new(&"Ambience")
	runner.add_child(fader)
	var a := Sfx.bank().variants(&"amb_wind")[0] as AudioStream
	var b := Sfx.bank().variants(&"amb_rain")[0] as AudioStream
	check(fader.play(a, -6.0, 0.5, 0.5, true), "the first stream starts")
	check(not fader.play(a, -6.0, 0.5, 0.5, true), "playing the same stream again does not restart it")
	check(fader.current_stream() == a and fader.is_playing(), "the player reports what is playing")
	check(fader.play(b, -3.0, 0.5, 0.5, true), "a different stream starts a crossfade")
	check(fader.voices_playing() == 2, "both streams play during the crossfade")
	for i in 40:
		fader._process(0.1)
	check(fader.voices_playing() == 1, "the old stream stops once it has faded out")
	check(is_equal_approx(fader._players[fader._active].volume_db, -3.0), "the new stream reaches its target volume")
	var looped := CrossfadePlayer._prepared(a, true)
	check(looped != a and bool(looped.get("loop")) and not bool(a.get("loop")), "looping uses a copy and leaves the shared stream untouched")
	check(CrossfadePlayer._prepared(a, false) == a, "no loop leaves the stream as it is")
	fader.stop(0.2)
	for i in 10:
		fader._process(0.1)
	check(not fader.is_playing() and fader.voices_playing() == 0 and fader.current_stream() == null, "stop fades everything out")
	check(not fader.play(null), "a missing stream is ignored")
	fader.queue_free()


func _test_ambience_bus() -> void:
	var bus := AudioServer.get_bus_index(&"Ambience")
	check(bus >= 0, "the Ambience bus exists")
	var listed := false
	for entry in Settings.AUDIO_BUSES:
		listed = listed or entry["bus"] == &"Ambience"
	check(listed, "the settings menu lists an ambience volume slider")
	var previous := Settings.get_volume(&"Ambience")
	Settings.set_volume(&"Ambience", 0.5)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)), "the ambience slider drives the Ambience bus")
	Settings.set_volume(&"Ambience", previous)


func _test_ambience() -> void:
	check(Ambience.validate().is_empty(), "ambience data has no errors: %s" % ", ".join(Ambience.validate()))
	for file in DirAccess.get_files_at("res://data/lighting"):
		if file.ends_with(".tres"):
			var profile := load("res://data/lighting/" + file) as LightingProfile
			check(Ambience._profiles.has(String(profile.id)), "lighting profile %s has an ambience entry" % profile.id)
	check(Ambience.layers_for(&"rooftop").size() == 2, "the rooftop zone has two ambience layers")
	check(Ambience.layers_for(&"test_no_such_zone").is_empty(), "an unknown zone falls back to the default (silence)")
	Ambience.set_zone(&"shaft")
	await frames(2)
	check(Ambience.playing_layers() == 3, "the shaft zone starts three ambience layers (%d)" % Ambience.playing_layers())
	Ambience.set_zone(&"rooftop")
	await frames(2)
	check(Ambience.current_zone() == &"rooftop" and Ambience.playing_layers() >= 2, "changing zones keeps the matching layers playing")
	Ambience.set_zone(&"")
	for i in Ambience.MAX_LAYERS:
		Ambience.layer_player(i)._process(10.0)
	check(Ambience.playing_layers() == 0, "leaving a level fades the ambience out and stops it")
	Ambience.stop_all(0.0)


## 編號體系（NE-163）：素材與位置各自的編號格式、素材目錄與位置登記完整、每個遊戲內的聲音都有位置。
func _test_numbering_and_catalog() -> void:
	var catalog := AudioCatalog.new()
	check(catalog.load_all(), "the asset catalog and slot registry load")
	var errors := catalog.validate()
	check(errors.is_empty(), "catalog and slot data have no errors: %s" % ", ".join(errors.slice(0, 5)))
	var asset_re := RegEx.create_from_string(AudioCatalog.ASSET_ID_PATTERN)
	var slot_re := RegEx.create_from_string(AudioCatalog.SLOT_ID_PATTERN)
	var category_counts: Dictionary = {}
	for id: String in catalog.assets.keys():
		check(slot_re.search(id) == null, "asset id %s cannot be mistaken for a slot id" % id)
		category_counts[id.split("-")[0]] = true
	check(category_counts.size() >= 10, "assets are spread over several categories (%d)" % category_counts.size())
	for slot: Dictionary in catalog.slots:
		check(asset_re.search(str(slot["id"])) == null, "slot id %s cannot be mistaken for an asset id" % slot["id"])
	var targets: Dictionary = {}
	for slot: Dictionary in catalog.slots:
		targets[str(slot["target"])] = slot
		if slot["kind"] == "music":
			check(not Music.track_def(StringName(str(slot["target"]))).is_empty(), "music slot %s names an existing track (%s)" % [slot["id"], slot["target"]])
		else:
			check(Sfx.has_sound(StringName(str(slot["target"]))), "sound slot %s names an existing sound (%s)" % [slot["id"], slot["target"]])
	var fallback_only := ["empty", "reload_start", "reload_mid", "reload_done"]
	for id in Sfx.sound_ids():
		if not fallback_only.has(id) and Sfx.source_of(StringName(id)) == &"file":
			check(targets.has(id), "every sound played from files has a slot: %s" % id)
	for id in Music.track_ids():
		check(targets.has(id), "every music track has a slot: %s" % id)
	for slot: Dictionary in catalog.slots:
		if slot["kind"] == "sfx" and Sfx.source_of(StringName(str(slot["target"]))) == &"file":
			check(not (slot["current"] as Array).is_empty(), "slot %s lists the assets it currently uses" % slot["id"])
	var found := catalog.search("gun-0031")
	check(found.has("GUN-0031"), "searching by asset id finds it")
	check(catalog.search("firearm", "GUN").all(func(id: String) -> bool: return id.begins_with("GUN-")), "searching can be limited to one category")
	check(catalog.search("zzzz no such asset").is_empty(), "a search with no match returns nothing")
	check(catalog.load_preview("GUN-9999") == null, "a missing preview returns null instead of failing")
	if catalog.has_preview("GUN-0031"):
		var preview := catalog.load_preview("GUN-0031")
		check(preview != null and preview.get_length() > 0.1, "a preview file loads and has sound")


func _test_placement_doc() -> void:
	var catalog := AudioCatalog.new()
	catalog.load_all()
	var slot_ids: Array = catalog.slots.map(func(s: Dictionary) -> String: return str(s["id"]))
	var shipped := PlacementDoc.new()
	check(shipped.load_doc(), "the shipped placement list loads")
	var errors := shipped.validate(catalog.assets, slot_ids)
	check(errors.is_empty(), "the shipped placement list matches the registry: %s" % ", ".join(errors.slice(0, 5)))
	check(shipped.slot_ids().size() == slot_ids.size(), "every slot has exactly one row (%d / %d)" % [shipped.slot_ids().size(), slot_ids.size()])
	# 在複本上測試寫入，不動真正的文件。
	var copy_path := "user://test_audio_placements.md"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PlacementDoc.PATH), ProjectSettings.globalize_path(copy_path))
	var doc := PlacementDoc.new()
	check(doc.load_doc(copy_path), "a copy of the list loads")
	var before := FileAccess.get_file_as_string(copy_path).split("\n")
	var first_slot := str(slot_ids[0])
	check(doc.planned(first_slot).is_empty() and not doc.is_manual(first_slot), "a fresh row has no plan and is not marked manual")
	check(doc.set_planned(first_slot, PackedStringArray(["GUN-0001", "GUN-0002"])), "writing a plan succeeds")
	check(doc.planned(first_slot) == PackedStringArray(["GUN-0001", "GUN-0002"]), "the plan reads back")
	check(doc.set_manual(first_slot, true) and doc.is_manual(first_slot), "marking a row as placed by hand works")
	var after := FileAccess.get_file_as_string(copy_path).split("\n")
	var changed := 0
	for i in before.size():
		changed += 1 if before[i] != after[i] else 0
	check(before.size() == after.size() and changed == 1, "only the edited row changes in the file (%d lines)" % changed)
	var reread := PlacementDoc.new()
	reread.load_doc(copy_path)
	check(reread.planned(first_slot) == PackedStringArray(["GUN-0001", "GUN-0002"]) and reread.is_manual(first_slot), "a fresh load sees the written values")
	check(reread.current(first_slot) == doc.current(first_slot), "the current-assets column is untouched")
	check(not doc.set_planned("P-XXX-999", PackedStringArray(["GUN-0001"])), "an unknown slot cannot be written")
	check(not doc.has_changed_on_disk(), "no change is reported right after our own write")
	# 外部編輯：直接改檔案的另一列，實驗室應該偵測到、重載，而且我們的寫入不會蓋掉它。
	var other_slot := str(slot_ids[1])
	var text := FileAccess.get_file_as_string(copy_path)
	var edited := PlacementDoc.new()
	edited.load_doc(copy_path)
	var row_text := "| %s |" % other_slot
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].begins_with(row_text):
			var cells := PlacementDoc._split(lines[i])
			cells[PlacementDoc.COL_PLANNED] = "IMP-0005"
			lines[i] = "| " + " | ".join(cells) + " |"
	OS.delay_msec(1100)  # 修改時間的解析度是秒
	var file := FileAccess.open(copy_path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	check(doc.has_changed_on_disk(), "an edit made elsewhere is detected")
	check(doc.set_planned(first_slot, PackedStringArray(["GUN-0003"])), "writing after an outside edit still works")
	var merged := PlacementDoc.new()
	merged.load_doc(copy_path)
	check(merged.planned(other_slot) == PackedStringArray(["IMP-0005"]) and merged.planned(first_slot) == PackedStringArray(["GUN-0003"]), "an outside edit and our write are both kept")
	# 看不出編號的文字要被檢查指出來。
	doc.set_planned(first_slot, PackedStringArray())
	var raw := PlacementDoc.new()
	raw.load_doc(copy_path)
	raw._lines[raw._rows[first_slot]] = raw._lines[raw._rows[first_slot]].replace("|  | [x]", "| 隨便一個 | [x]")
	check("\n".join(raw.validate(catalog.assets, slot_ids)).contains("看不出素材編號"), "free text without an asset id is flagged")
	raw._lines[raw._rows[first_slot]] = raw._lines[raw._rows[first_slot]].replace("| 隨便一個 |", "| GUN-9998 |")
	check("\n".join(raw.validate(catalog.assets, slot_ids)).contains("不存在的素材"), "an asset id that is not in the catalog is flagged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_path))
	check(not PlacementDoc.new().load_doc("user://test_audio_no_such_placements.md"), "a missing list file does not crash")


func _test_source_counts() -> void:
	var counts: Dictionary = Sfx.source_counts()
	check(int(counts["file"]) + int(counts["synth"]) + int(counts.get("missing", 0)) == Sfx.sound_ids().size(), "source counts add up to the number of sounds")
	check(int(counts["synth"]) > 0 or int(counts["file"]) > 0, "at least one sound source exists")
