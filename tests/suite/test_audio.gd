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


func _test_source_counts() -> void:
	var counts: Dictionary = Sfx.source_counts()
	check(int(counts["file"]) + int(counts["synth"]) + int(counts.get("missing", 0)) == Sfx.sound_ids().size(), "source counts add up to the number of sounds")
	check(int(counts["synth"]) > 0 or int(counts["file"]) > 0, "at least one sound source exists")
