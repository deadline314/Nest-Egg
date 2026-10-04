class_name SoundLabReloadEditor
extends VBoxContainer
## 換彈聲音時間軸編輯器：在畫面舞台下方，看這把武器的換彈動畫有幾段聲音、各落在哪裡、各有多長，
## 可以新增、刪除、拖動、換聲音與音量，或一鍵套用「三段／兩段／一段」；修改立刻生效（下一次換彈就用新的，
## 按「在畫面換彈」立刻在真實動畫上試），預覽差異、驗證通過才寫回 data/audio/weapon_sounds.json（先備份），也能放棄修改還原。
## 整段動畫只想用一個聲音時，留一段、時間點 0、聲音指定成那個音效即可。

const KIND_LABELS := {"reload_start": "開始", "reload_mid": "中段", "reload_done": "完成", "empty": "空槍", "equip": "換槍"}
const CUSTOM := "指定音效"
const MAX_ROWS := ReloadCues.MAX_CUES

var lab: SoundLab
## 寫回的資料檔（測試時指到複本）。
var data_path := WeaponSounds.PATH
var weapon_id := ""
## 正在編輯的時間軸（跟資料檔同一種格式：at、kind 或 sound、volume_db）。
var cues: Array = []
var dirty := false
var view: SoundLabTimelineView
var _weapon_option: OptionButton
var _info: Label
var _warning: Label
var _rows: VBoxContainer
var _duration := 1.0
var _building := false


func _init(p_lab: SoundLab) -> void:
	lab = p_lab


func _ready() -> void:
	var head := HBoxContainer.new()
	add_child(head)
	head.add_child(_label("換彈聲音時間軸"))
	_weapon_option = OptionButton.new()
	_weapon_option.tooltip_text = "要編輯哪一把武器的換彈聲音；有彈匣的武器才有換彈"
	for id in _reloadable_weapons():
		_weapon_option.add_item(id)
	_weapon_option.item_selected.connect(func(i: int) -> void: set_weapon(_weapon_option.get_item_text(i)))
	head.add_child(_weapon_option)
	_info = Label.new()
	_info.tooltip_text = "這把武器的換彈長度，以及資料是不是還沒存"
	head.add_child(_info)
	view = SoundLabTimelineView.new()
	view.cue_dragged.connect(_on_cue_dragged)
	view.cue_picked.connect(func(_i: int) -> void: pass)
	add_child(view)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.tooltip_text = "時間軸的提醒：聲音比動畫長或短、資料有錯誤等"
	add_child(_warning)
	_rows = VBoxContainer.new()
	add_child(_rows)
	var actions := HBoxContainer.new()
	add_child(actions)
	actions.add_child(_button("＋ 新增一段", _add_cue, "在時間軸中間新增一段聲音"))
	actions.add_child(_button("三段（原本）", func() -> void: _apply_preset(ReloadCues.FALLBACK), "開始、中段、完成三段"))
	actions.add_child(_button("兩段", func() -> void: _apply_preset([{"at": 0.0, "kind": "reload_start", "volume_db": -4.0}, {"at": 0.7, "kind": "reload_done", "volume_db": -3.0}]), "開始與完成兩段"))
	actions.add_child(_button("一段", func() -> void: _apply_preset([{"at": 0.0, "kind": "reload_start", "volume_db": -3.0}]), "整段只用一個聲音：只在換彈開始播一次，之後把它的聲音改成適合整段的音效"))
	actions.add_child(_button("無聲", func() -> void: _apply_preset([]), "換彈不發聲"))
	var io := HBoxContainer.new()
	add_child(io)
	io.add_child(_button("▶ 在畫面換彈", play_in_stage, "在上面的畫面讓玩家用這把武器換彈，聲音依這份時間軸播出"))
	io.add_child(_button("預覽差異", func() -> void: save(true), "列出和資料檔不同的地方，不寫入"))
	io.add_child(_button("儲存", func() -> void: save(false), "驗證通過後寫回 weapon_sounds.json（先備份成 .bak）"))
	io.add_child(_button("放棄修改", revert, "還原成資料檔裡的設定"))
	if _weapon_option.item_count > 0:
		set_weapon(_weapon_option.get_item_text(0))


func _process(_delta: float) -> void:
	var stage := lab.stage() if lab != null else null
	var value := -1.0
	if stage != null and stage.is_ready() and stage.arena.player.loadout.is_reloading() and stage.arena.player.loadout.active_weapon().id == StringName(weapon_id):
		value = stage.arena.player.loadout.reload_progress()
	view.set_progress(value)


func _reloadable_weapons() -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(LabArena.WEAPON_DIR):
		if file.ends_with(".tres"):
			var weapon := load(LabArena.WEAPON_DIR + file) as WeaponData
			if weapon != null and weapon.has_magazine():
				out.append(weapon.id)
	out.sort()
	return out


## 切到某把武器：讀目前生效的時間軸（沒有自己的就是沿用的那份）。
func set_weapon(id: String) -> void:
	weapon_id = id
	for i in _weapon_option.item_count:
		if _weapon_option.get_item_text(i) == id:
			_weapon_option.select(i)
	var path := LabArena.WEAPON_DIR + id + ".tres"
	var weapon := load(path) as WeaponData if ResourceLoader.exists(path) else null
	_duration = weapon.reload_time if weapon != null and weapon.reload_time > 0.0 else 1.0
	var raw: Variant = WeaponSounds.table().lookup(StringName(id), StringName(ReloadCues.KEY))
	cues = (raw as Array).duplicate(true) if typeof(raw) == TYPE_ARRAY else ReloadCues.FALLBACK.duplicate(true)
	dirty = false
	_rebuild_rows()
	_refresh()


func _rebuild_rows() -> void:
	_building = true
	for child in _rows.get_children():
		child.queue_free()
	for i in cues.size():
		_rows.add_child(_make_row(i))
	_building = false


func _make_row(index: int) -> Control:
	var cue: Dictionary = cues[index]
	var row := HBoxContainer.new()
	row.add_child(_label("%d" % (index + 1)))
	var at := SpinBox.new()
	at.min_value = 0.0
	at.max_value = 100.0
	at.step = 1.0
	at.suffix = "%"
	at.custom_minimum_size = Vector2(80, 0)
	at.value = float(cue.get("at", 0.0)) * 100.0
	at.tooltip_text = "這個聲音落在換彈動畫的哪個位置（0% 開始、100% 完成）"
	at.value_changed.connect(func(v: float) -> void: _edit(index, "at", v / 100.0))
	row.add_child(at)
	var kind := OptionButton.new()
	for key: String in KIND_LABELS.keys():
		kind.add_item(KIND_LABELS[key])
		kind.set_item_metadata(kind.item_count - 1, key)
		kind.set_item_tooltip(kind.item_count - 1, key)
	kind.add_item(CUSTOM)
	kind.set_item_metadata(kind.item_count - 1, "")
	kind.custom_minimum_size = Vector2(96, 0)
	kind.tooltip_text = "播這把武器自己的哪一個操作聲（開始／中段／完成／空槍／換槍，每把武器各有自己的聲音），或改成指定任何一個音效"
	var current_kind := str(cue.get("kind", ""))
	kind.select(kind.item_count - 1 if current_kind.is_empty() else maxi(0, KIND_LABELS.keys().find(current_kind)))
	row.add_child(kind)
	var sound := LineEdit.new()
	sound.custom_minimum_size = Vector2(120, 0)
	sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound.placeholder_text = "音效或聲音事件名稱"
	sound.text = str(cue.get("sound", ""))
	sound.editable = current_kind.is_empty()
	sound.tooltip_text = "選了「指定音效」時，填音效庫裡的名稱（例如 reload_start_heavy）；按 Enter 套用"
	sound.text_submitted.connect(func(t: String) -> void: _edit(index, "sound", t.strip_edges()))
	sound.focus_exited.connect(func() -> void: _edit(index, "sound", sound.text.strip_edges()))
	row.add_child(sound)
	kind.item_selected.connect(func(i: int) -> void:
		var picked := str(kind.get_item_metadata(i))
		sound.editable = picked.is_empty()
		_edit(index, "kind", picked))
	var volume := SpinBox.new()
	volume.min_value = ReloadCues.VOLUME_RANGE.x
	volume.max_value = ReloadCues.VOLUME_RANGE.y
	volume.step = 0.5
	volume.suffix = "dB"
	volume.custom_minimum_size = Vector2(84, 0)
	volume.value = float(cue.get("volume_db", 0.0))
	volume.tooltip_text = "這個聲音的音量（dB），0 是原本大小"
	volume.value_changed.connect(func(v: float) -> void: _edit(index, "volume_db", v))
	row.add_child(volume)
	row.add_child(_button("▶", func() -> void: preview_cue(index), "單獨播這一段的聲音"))
	row.add_child(_button("✕", func() -> void: remove_cue(index), "刪掉這一段"))
	return row


# ---------------------------------------------------------------------------
# 編輯（測試也直接呼叫這些）
# ---------------------------------------------------------------------------

func _edit(index: int, key: String, value: Variant) -> void:
	if _building or index < 0 or index >= cues.size():
		return
	var cue: Dictionary = cues[index]
	match key:
		"kind":
			if str(value).is_empty():
				cue.erase("kind")
				if not cue.has("sound"):
					cue["sound"] = ""
			else:
				cue["kind"] = str(value)
				cue.erase("sound")
		"sound":
			if str(value).is_empty():
				cue.erase("sound")
			else:
				cue["sound"] = str(value)
				cue.erase("kind")
		_:
			cue[key] = value
	_commit()


func add_cue(at := 0.5) -> void:
	if cues.size() >= MAX_ROWS:
		lab.notify("最多 %d 段" % MAX_ROWS)
		return
	cues.append({"at": at, "kind": "reload_mid", "volume_db": -4.0})
	_commit(true)


func _add_cue() -> void:
	add_cue(0.5)


func remove_cue(index: int) -> void:
	if index >= 0 and index < cues.size():
		cues.remove_at(index)
		_commit(true)


func _apply_preset(preset: Array) -> void:
	cues = preset.duplicate(true)
	_commit(true)


func _on_cue_dragged(index: int, at: float) -> void:
	if index >= 0 and index < cues.size():
		cues[index]["at"] = at
		_commit(_rows.get_child_count() != cues.size())
		if index < _rows.get_child_count():
			((_rows.get_child(index) as HBoxContainer).get_child(1) as SpinBox).set_value_no_signal(at * 100.0)


## 把目前編輯的時間軸交給遊戲（驗證通過才套用）；rebuild 為 true 時重畫列表。
func _commit(rebuild := false) -> void:
	var errors := ReloadCues.validate_list(cues, Sfx.has_named)
	if errors.is_empty():
		WeaponSounds.table().override(StringName(weapon_id), StringName(ReloadCues.KEY), cues.duplicate(true))
		dirty = true
	if rebuild:
		_rebuild_rows()
	_refresh(errors)


func preview_cue(index: int) -> void:
	if index < 0 or index >= cues.size():
		return
	var cue := ReloadCues.parse([cues[index]])
	if cue.is_empty():
		return
	var name := ReloadCues.sound_of(StringName(weapon_id), cue[0])
	if name == &"":
		lab.notify("第 %d 段沒有聲音（名稱找不到或刻意靜音）" % (index + 1))
		return
	Sfx.play_named(name, cue[0].volume_db)
	lab.notify("第 %d 段：%s（%.2f 秒）" % [index + 1, name, Sfx.sound_length(name)])


## 在畫面舞台讓玩家用這把武器換彈。
func play_in_stage() -> void:
	var stage := lab.stage()
	if stage == null:
		lab.notify("畫面舞台沒有開啟")
		return
	await stage.run_action("reload", {"weapon": weapon_id}, "換彈：%s" % weapon_id)


# ---------------------------------------------------------------------------
# 存檔
# ---------------------------------------------------------------------------

func save(dry_run: bool) -> Dictionary:
	var change := {"path": ["profiles", weapon_id, ReloadCues.KEY], "value": cues.duplicate(true), "ensure": true}
	var result := AudioDataWriter.apply(data_path, [change], dry_run)
	var errors: PackedStringArray = result["errors"]
	if not errors.is_empty():
		lab.notify("不能儲存：%s" % "；".join(errors))
	elif dry_run:
		var diff: PackedStringArray = result["diff"]
		lab.notify("預覽：%s" % ("與資料檔相同，沒有差異" if diff.is_empty() else "；".join(PackedStringArray(Array(diff).map(func(d: String) -> String: return d.substr(0, 160))))))
	else:
		WeaponSounds.reload_data(true)
		dirty = false
		lab.notify("已儲存 %s 的換彈時間軸%s" % [weapon_id, "（備份：%s）" % result["backup"] if not str(result["backup"]).is_empty() else "（沒有變化）"])
		_refresh()
	return result


func revert() -> void:
	WeaponSounds.reload_data(true)
	set_weapon(weapon_id)
	lab.notify("已放棄修改，還原成資料檔的設定")


# ---------------------------------------------------------------------------
# 顯示
# ---------------------------------------------------------------------------

func _refresh(errors := PackedStringArray()) -> void:
	var drawn: Array[Dictionary] = []
	var notes := PackedStringArray()
	var parsed := ReloadCues.parse(cues)
	for i in parsed.size():
		var cue := parsed[i]
		var name := ReloadCues.sound_of(StringName(weapon_id), cue)
		var length := Sfx.sound_length(name) if name != &"" else 0.0
		var label: String = KIND_LABELS.get(String(cue.kind), "") if cue.kind != &"" else String(cue.sound)
		drawn.append({"at": cue.at, "label": "%s %s" % [label, name if cue.kind != &"" else ""], "length": length})
		if name == &"":
			notes.append("第 %d 段找不到聲音，會是靜音" % (i + 1))
		elif cue.at < 0.98 and cue.at * _duration + length > _duration + 0.001:
			notes.append("第 %d 段的聲音（%.2f 秒）超出換彈結尾 %.2f 秒" % [i + 1, length, cue.at * _duration + length - _duration])
	if parsed.size() == 1:
		var only := drawn[0]
		if float(only["length"]) > 0.0 and float(only["length"]) < _duration * 0.5:
			notes.append("整段只用一個聲音，但它只有 %.2f 秒，換彈 %.2f 秒大部分沒有聲音" % [only["length"], _duration])
	if parsed.is_empty():
		notes.append("沒有任何聲音：換彈不發聲")
	view.set_cues(drawn, _duration)
	_info.text = "換彈 %.2f 秒　%s" % [_duration, "（有未儲存的修改）" if dirty else "（與資料檔相同）"]
	var lines := PackedStringArray()
	lines.append_array(errors)
	lines.append_array(notes)
	_warning.text = "\n".join(lines)
	_warning.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.4) if not errors.is_empty() else Color(0.95, 0.75, 0.35))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _button(text: String, action: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button
