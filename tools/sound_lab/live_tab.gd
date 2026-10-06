class_name SoundLabLiveTab
extends ScrollContainer
## 實驗室分頁二：即時試玩。用遊戲裡真正的查表（角色、武器、命中材質、地面、任何音效）播放，換角色、換武器就能聽到差異；
## 每個按鈕旁顯示實際解析到的音效名稱與來源（檔案或合成音）。

const STEP_INTERVAL := 0.32

var lab: SoundLab
var _result: Label
var _character: OptionButton
var _weapon: OptionButton
var _fire_rate: OptionButton
var _material: OptionButton
var _surface: OptionButton
var _any_sound: OptionButton


func _init(p_lab: SoundLab) -> void:
	lab = p_lab
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	_result = Label.new()
	_result.tooltip_text = "最近一次播放實際解析到的音效或事件，以及它是用檔案還是合成音"
	box.add_child(_result)

	box.add_child(_heading("角色（換角色聽受擊、死亡、開火、預兆、警戒）"))
	_character = _option(box, "角色", _character_ids(), "玩家或任何一種敵人")
	var row := HBoxContainer.new()
	box.add_child(row)
	for kind in CharacterSounds.KINDS:
		row.add_child(_button(kind, func() -> void: play_character(_selected(_character), StringName(kind)), "播放這個角色的「%s」" % kind))

	box.add_child(_heading("武器（換武器聽射擊、換彈、空槍、換槍、近戰）"))
	_weapon = _option(box, "武器", _weapon_ids(), "任何一把玩家武器")
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("射擊 ×1", func() -> void: play_weapon_fire(_selected(_weapon), 1), "播放一發"))
	row.add_child(_button("連發 ×8", func() -> void: play_weapon_fire(_selected(_weapon), 8), "依這把武器的射速連續播放 8 發，聽變體輪播與重疊"))
	_fire_rate = _option(row, "射速倍率", PackedStringArray(["1", "1.25", "1.5", "2"]), "模擬射速加快（超頻、射速升級）：音效跟著加快、音高不變，連發的間隔也跟著縮短")
	row.add_child(_button("換彈整段", func() -> void: play_weapon_reload(_selected(_weapon)), "開始、中段、完成依序播放"))
	row.add_child(_button("空槍", func() -> void: play_weapon_kind(_selected(_weapon), &"empty"), "彈匣空了還扣扳機"))
	row.add_child(_button("換槍", func() -> void: play_weapon_kind(_selected(_weapon), &"equip"), "切換到這把武器"))
	row = HBoxContainer.new()
	box.add_child(row)
	for attack_id: Variant in MeleeData.combo():
		row.add_child(_button("近戰：%s" % attack_id, func() -> void: play_melee(str(attack_id)), "播放這一招的揮擊聲與命中聲"))

	box.add_child(_heading("命中與材質"))
	_material = _option(box, "材質", _material_ids(), "子彈打到的東西")
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("命中這個材質", func() -> void: play_material(_selected(_material)), "播放這個材質的命中聲"))
	for entry: Array in [["擊殺", &"kill_enemy"], ["重擊", &"hit_heavy"], ["一般命中", &"hit_enemy"], ["清場", &"clear_out"]]:
		row.add_child(_button(entry[0], func() -> void: play_named(entry[1]), "播放聲音事件「%s」" % entry[1]))
	row = HBoxContainer.new()
	box.add_child(row)
	for entry: Array in [["格擋", &"block"], ["完美格擋", &"parry"], ["破防", &"guard_break"], ["大爆炸", &"explosion"], ["小爆炸", &"explosion_small"], ["終結技", &"finisher"]]:
		row.add_child(_button(entry[0], func() -> void: play_named(entry[1]), "播放「%s」" % entry[1]))

	box.add_child(_heading("腳步與落地（依地面種類）"))
	_surface = _option(box, "地面", PackedStringArray(Footsteps.surfaces().map(func(s: Variant) -> String: return str(s))), "選擇腳下的地面種類")
	row = HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("走路 ×6", func() -> void: play_footsteps(_selected(_surface), 6), "依走路的節奏播放六步"))
	row.add_child(_button("落地", func() -> void: play_land(_selected(_surface)), "從高處落地"))

	box.add_child(_heading("任何一個音效或聲音事件"))
	var all_names := PackedStringArray(Sfx.sound_ids())
	for event: Variant in Sfx.event_ids():
		all_names.append("事件：" + str(event))
	_any_sound = _option(box, "名稱", all_names, "音效庫與合成音的所有 id，以及聲音事件")
	box.add_child(_button("播放", func() -> void: play_named(StringName(_selected(_any_sound).trim_prefix("事件："))), "播放選中的音效或事件；連按聽變體"))


# ---------------------------------------------------------------------------
# 播放（測試也直接呼叫這些）
# ---------------------------------------------------------------------------

func play_character(id: String, kind: StringName) -> StringName:
	var attack_category := &"ranged"
	var path := "res://data/enemies/%s.tres" % id
	if ResourceLoader.exists(path):
		attack_category = (load(path) as EnemyData).attack_category
	var name := CharacterSounds.name_for(StringName(id), kind, {"attack_category": attack_category})
	_report("角色 %s ／ %s" % [id, kind], name)
	if name != &"":
		Sfx.play_named(name)
	return name


## 選中的射速倍率（沒有選項時 1）。
func fire_rate() -> float:
	return _selected(_fire_rate).to_float() if _fire_rate != null and not _selected(_fire_rate).is_empty() else 1.0


func play_weapon_fire(id: String, shots: int) -> StringName:
	var weapon := _load_weapon(id)
	if weapon == null:
		return &""
	_report("武器 %s 射擊" % id, weapon.fire_sound)
	var rate := fire_rate()
	for i in shots:
		Sfx.play(weapon.fire_sound, -6.0, 0.06, 0, 1.0, rate)
		if shots > 1:
			await get_tree().create_timer(maxf(0.03, weapon.fire_interval / rate)).timeout
	return weapon.fire_sound


func play_weapon_kind(id: String, kind: StringName) -> StringName:
	var name := WeaponSounds.name_for(StringName(id), kind)
	_report("武器 %s ／ %s" % [id, kind], name)
	if name != &"":
		Sfx.play_named(name)
	return name


## 依這把武器的換彈聲音時間軸（資料：reload_cues）播放整段；段數與時間點和遊戲裡一致。
func play_weapon_reload(id: String) -> void:
	var weapon := _load_weapon(id)
	var time := weapon.reload_time if weapon != null else 1.5
	var elapsed := 0.0
	for cue in ReloadCues.for_weapon(StringName(id)):
		var wait := maxf(0.0, cue.at * time - elapsed)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		elapsed += wait
		var name := ReloadCues.sound_of(StringName(id), cue)
		_report("武器 %s 換彈 %.0f%%" % [id, cue.at * 100.0], name)
		if name != &"":
			Sfx.play_named(name, cue.volume_db)


func play_melee(attack_id: String) -> void:
	var sounds: Dictionary = MeleeData.attack(attack_id)["sounds"]
	_report("近戰 %s" % attack_id, StringName(str(sounds["swing"])))
	Sfx.play_named(StringName(str(sounds["swing"])))
	await get_tree().create_timer(0.14).timeout
	Sfx.play_named(StringName(str(sounds["hit"])))


func play_material(material: String) -> StringName:
	var event := HitFeedback.sound_event(StringName(material))
	_report("材質 %s" % material, event)
	if event != &"":
		Sfx.play_event(event)
	return event


func play_named(id: StringName) -> void:
	_report("聲音", id)
	Sfx.play_named(id)


func play_footsteps(surface: String, count: int) -> void:
	_report("腳步 %s" % surface, Footsteps.name_for(StringName(surface), &"step"))
	for i in count:
		Footsteps.play(StringName(surface), &"step", -14.0)
		await get_tree().create_timer(STEP_INTERVAL).timeout


func play_land(surface: String) -> void:
	_report("落地 %s" % surface, Footsteps.name_for(StringName(surface), &"land"))
	Footsteps.play(StringName(surface), &"land", -8.0)


func _report(label: String, name: StringName) -> void:
	var source := ""
	if name == &"":
		source = "（這個動作刻意不發聲或找不到）"
	elif Sfx.has_event(name):
		source = "（聲音事件）"
	else:
		source = "（%s）" % {&"file": "音效檔", &"synth": "合成音", &"missing": "未定義"}.get(Sfx.source_of(name), "")
	_result.text = "%s → %s %s" % [label, name, source]


# ---------------------------------------------------------------------------
# 介面
# ---------------------------------------------------------------------------

func _load_weapon(id: String) -> WeaponData:
	var path := "res://data/weapons/%s.tres" % id
	return load(path) as WeaponData if ResourceLoader.exists(path) else null


func _character_ids() -> PackedStringArray:
	var ids := PackedStringArray(["player"])
	ids.append_array(_file_ids("res://data/enemies"))
	return ids


func _weapon_ids() -> PackedStringArray:
	return _file_ids("res://data/weapons")


func _material_ids() -> PackedStringArray:
	var ids := PackedStringArray(HitFeedback.material_ids())
	ids.append_array(PackedStringArray(["ricochet", "weak"]))
	return ids


func _file_ids(dir: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			ids.append(file.trim_suffix(".tres"))
	ids.sort()
	return ids


func _selected(option: OptionButton) -> String:
	return option.get_item_text(option.selected) if option.item_count > 0 else ""


func _option(parent: Control, title: String, items: PackedStringArray, tip: String) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	row.add_child(label)
	var option := OptionButton.new()
	option.tooltip_text = tip
	option.custom_minimum_size = Vector2(260, 0) if items.size() > 4 else Vector2(80, 0)
	for item in items:
		option.add_item(item)
	row.add_child(option)
	parent.add_child(row)
	return option


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Palette.CYAN)
	return label
