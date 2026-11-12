extends ScenarioBase
## 近戰武器聲音的原生驗證（NE-261）。
##
## 用法（原生，有音效裝置）：
##   godot --path . res://tools/melee_sound_probe.tscn -- --out=<絕對資料夾>
## 在測試場地真的打一輪，把聲音錄下來：先錄對照（安靜、手槍空射三發、手槍打在敵人身上三發、走幾步），再對五把近戰武器各錄
##   拿在手上的待機聲 → 整套連段揮空（含延伸招）→ 整套連段打在敵人身上 → 換回手槍（待機聲要停）。
## 延伸招要技巧升級才打得出來：錄音期間暫時當作已經擁有，結束時還原，不寫入存檔。
## 輸出：
##   melee-master.wav  主匯流排（玩家實際聽到的混音，含環境音），給人聽
##   melee-sfx.wav     只有音效匯流排，用來量每一段的音量
##   melee-index.json  每一段的起訖時間（秒）與這一段實際播了哪些聲音（照順序）
## 再用 python tools/audio/melee_sound_report.py <資料夾> 畫波形並比較音量。

const WEAPONS: PackedStringArray = ["blade", "dagger", "glaive", "maul", "whip"]
const MAX_STEPS := 6

var _segments: Array[Dictionary] = []
var _start_usec := 0
var _clock
var _failures := 0
var _granted: Dictionary = {}
var _content
var _culling_before := true
var _culling_overridden := false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=").replace("\\", "/")
	if not out_dir.is_absolute_path() or AudioServer.get_driver_name().strip_edges().is_empty() or AudioServer.get_driver_name().to_lower() == "dummy":
		push_error("[MeleeSoundProbe] 需要實際非Dummy音訊driver與 --out=<絕對資料夾>（headless僅音訊，不是原生畫面驗收）")
		get_tree().quit(2)
		return
	print("NE261_GAME_RUNTIME " + JSON.stringify({"display":DisplayServer.get_name(),"audio_driver":AudioServer.get_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),"rendering_device_null":RenderingServer.get_rendering_device()==null}))
	var mkdir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if mkdir_error != OK or not DirAccess.dir_exists_absolute(out_dir):
		push_error("[MeleeSoundProbe] mkdir path=%s error=%s directory_exists=%s" % [out_dir,error_string(mkdir_error),DirAccess.dir_exists_absolute(out_dir)])
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("--parser-only"):
		get_tree().quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	# Dummy rendering cannot publish VisibleOnScreenEnabler2D visibility.
	# Match the existing smoke precondition only in this headless fixture.
	_culling_before=Enemy.activation_culling_enabled
	if DisplayServer.get_name()=="headless":
		Enemy.activation_culling_enabled=false
		_culling_overridden=true
	Story.auto_skip = true
	# 不套用暗的光影設定：那一份有閃電，雷聲會混進錄音。
	await open_arena("", 12.0)
	level.hud.visible = false
	player.health.setup(999, 0.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	Sfx.sound_played.connect(_heard)
	_content=preload("res://tools/audio/melee_sound_content.gd").new()
	add_child(_content)
	_clock = preload("res://tools/audio/melee_pcm_clock.gd").new()
	add_child(_clock)
	if not _clock.attach():
		await _abort_clock()
		return
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	await _arm(pistol)
	await settle(30)
	if not await _clock.start():
		await _abort_clock()
		return
	_start_usec = Time.get_ticks_usec()

	_begin("ref", "silence")
	await _seconds(1.0)
	_begin("ref", "pistol")
	for shot in 3:
		Input.action_press(&"shoot")
		await settle(3)
		Input.action_release(&"shoot")
		await _seconds(0.45)
	var dummy := _target(pistol)
	await settle(20)
	_begin("ref", "pistol_hit")
	for shot in 3:
		Input.action_press(&"shoot")
		await settle(3)
		Input.action_release(&"shoot")
		await _seconds(0.45)
	_content.close()
	await clear_enemies()
	_begin("ref", "walk")
	Input.action_press(&"move_right")
	await _seconds(1.2)
	Input.action_release(&"move_right")
	await _seconds(0.4)

	for weapon_id: String in WEAPONS:
		var weapon := load("res://data/weapons/melee/melee_%s.tres" % weapon_id) as WeaponData
		_grant_extension(weapon)
		await clear_enemies()
		await _arm(weapon)
		_begin(weapon_id, "idle")
		await _seconds(1.6)
		var hum := player.find_child("MeleeHum", true, false)
		var moves := MeleeData.set_of(weapon)
		var idle: StringName = moves.call(&"idle_sound") if moves.has_method(&"idle_sound") else &""
		if hum == null or hum.call(&"sounding") != idle:
			push_error("[MeleeSoundProbe] %s 拿在手上沒有響待機聲" % weapon.id)
			_failures += 1
		_begin(weapon_id, "combo_miss")
		await _combo()
		await _seconds(0.5)
		await _arm(weapon)
		_target(weapon)
		await settle(20)
		_begin(weapon_id, "combo_hit")
		await _combo()
		await _seconds(0.5)
		_begin(weapon_id, "holster")
		await clear_enemies()
		await _arm(pistol)
		await _seconds(0.6)
		if hum != null and hum.call(&"sounding") != &"":
			push_error("[MeleeSoundProbe] %s 收起來之後待機聲還在響" % weapon.id)
			_failures += 1
		_content.close()
	_begin("ref", "end")
	await _seconds(0.3)
	_content.close()
	_segments.pop_back()

	var sample_end: Dictionary = _clock.stop()
	var pcm_index: Dictionary = await _clock.save(out_dir, sample_end)
	_failures += _clock.problems.size()
	_failures += _content.problems.size()
	pcm_index["cleanup"] = _clock.cleanup()
	for base_id: StringName in _granted:
		Progression._upgrades[base_id] = _granted[base_id]
	for index in _segments.size():
		var next: Dictionary = _segments[index + 1]["bus_start_frames"] if index + 1 < _segments.size() else sample_end["frames"]
		_segments[index]["bus_end_frames"] = next
		_segments[index]["start"] = float(_segments[index]["bus_start_frames"]["SFX"]) / pcm_index["mix_rate"]
		_segments[index]["end"] = float(next["SFX"]) / pcm_index["mix_rate"]
	var writer := FileAccess.open(out_dir.path_join("melee-index.json"), FileAccess.WRITE)
	if writer == null:
		push_error("[MeleeSoundProbe] index open path=%s error=%s" % [out_dir.path_join("melee-index.json"),error_string(FileAccess.get_open_error())])
		_failures += 1
	else:
		writer.store_string(JSON.stringify({"content_contract":"ne261-actual-actions-v1","headless_activation_culling_disabled":_culling_overridden,"content_problems":_content.problems,"segments": _segments, "sfx_bus_db": AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS)),
			"master_db": AudioServer.get_bus_volume_db(0), "sample_clock": pcm_index, "runtime": {"audio_driver":AudioServer.get_driver_name(),"display":DisplayServer.get_name()}, "scope": "Published weapon combo/extension recording; does not cover the five added hold modes or human listening. Headless recording is not native visual acceptance."}, "\t"))
		writer.flush()
		var write_error := writer.get_error()
		writer.close()
		if write_error != OK:
			push_error("[MeleeSoundProbe] index write path=%s error=%s" % [out_dir.path_join("melee-index.json"),error_string(write_error)])
			_failures += 1
	for segment: Dictionary in _segments:
		print("MELEE_SOUND:%s/%s %s" % [segment["weapon"], segment["part"], ", ".join(PackedStringArray(segment["sounds"]))])
	print("MELEE_SOUND_PROBE failures ", _failures)
	await finish()
	_restore_culling()
	get_tree().quit(1 if _failures > 0 else 0)


## 打完整套連段（含延伸招）：每一段等上一段收招再按，和玩家連按一樣。
func _combo() -> void:
	var last := -1
	for step in MAX_STEPS:
		player._melee_cooldown_left = 0.0
		player.guard = 100.0
		player._guard_lockout_left = 0.0
		player.loadout.refill_all()
		if not player._try_melee():
			break
		if player._melee_index <= last:
			# 連段已經打完，這一下是新的一輪：收掉，不讓它出聲。
			player._interrupt_melee()
			break
		last = player._melee_index
		var limit := 300
		while player._melee_phase != Player.MeleePhase.NONE and limit > 0:
			await get_tree().physics_frame
			limit -= 1
	if last < 0:
		push_error("[MeleeSoundProbe] 連段一段都沒有打出來")
		_failures += 1


## 一個打不死、不會動的敵人，站在這把武器打得到的地方（槍是 4 格外）。
func _target(weapon: WeaponData) -> Enemy:
	var tiles := maxf(1.6, weapon.melee_length * 0.75 / 16.0) if weapon.is_melee() else 4.0
	var foe := spawn_enemy("res://data/enemies/sweeper.tres", 12.0 + tiles)
	foe.data = foe.data.duplicate()
	foe.data.detect_range = 0.0
	foe.data.attack_range = 0.0
	foe.data.move_speed = 0.0
	foe.health.setup(9999, 0.0)
	return foe


func _arm(weapon: WeaponData) -> void:
	player._interrupt_melee()
	player.loadout.reset(weapon)
	player.loadout.refill_all()
	player._melee_cooldown_left = 0.0
	player._melee_combo_left = 0.0
	place_player(12.0)
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	await settle(20)


## 暫時當作已經買了這把武器的延伸招（只改記憶體裡的資料，結束時還原）。
func _grant_extension(weapon: WeaponData) -> void:
	var upgrade := MeleeData.set_of(weapon).extension_upgrade()
	var base := WeaponTuning.base_of(weapon)
	if upgrade.is_empty() or base == null or Progression.has_upgrade(weapon, upgrade):
		return
	var owned: Array = Progression._upgrades.get(base.id, [])
	if not _granted.has(base.id):
		_granted[base.id] = owned.duplicate()
	var extended := owned.duplicate()
	extended.append(upgrade)
	Progression._upgrades[base.id] = extended


func _begin(weapon: String, part: String) -> void:
	_content.close()
	_segments.append({"weapon": weapon, "part": part, "wall_seconds_diagnostic_only": _now(), "bus_start_frames": _clock.mark(), "sounds": []})
	_content.begin(_segments[-1],player,_clock)


func _heard(id: StringName) -> void:
	if not _segments.is_empty():
		(_segments[_segments.size() - 1]["sounds"] as Array).append(String(id))


func _now() -> float:
	return float(Time.get_ticks_usec() - _start_usec) / 1000000.0


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration, false).timeout



func _abort_clock() -> void:
	_clock.cleanup()
	await finish()
	_restore_culling()
	get_tree().quit(1)


func _restore_culling() -> void:
	if _culling_overridden:
		Enemy.activation_culling_enabled=_culling_before
		_culling_overridden=false
		print("NE261_CULLING_RESTORED " + str(Enemy.activation_culling_enabled==_culling_before))


func _exit_tree() -> void:
	_restore_culling()
