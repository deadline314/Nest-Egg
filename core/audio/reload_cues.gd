class_name ReloadCues
extends RefCounted
## 換彈聲音時間軸：換彈進度（0 到 1）上的一串 cue，每個 cue 指定時間點、聲音與音量。
## 資料：data/audio/weapon_sounds.json 的 profile 欄位 reload_cues（沿用 extends／default），格式見 design/16-audio/DESIGN.md 5.2。
## cue 的聲音有兩種寫法：kind（該武器的 reload_start／reload_mid／reload_done／empty／equip，各武器可以不同）或 sound（直接指名稱）。
## 資料壞掉時記錄一次錯誤並退回內建的三段，換彈不會變成無聲或崩潰。

const KEY := "reload_cues"
const MAX_CUES := 12
const VOLUME_RANGE := Vector2(-40.0, 12.0)

## 一個 cue：at 是換彈進度；kind 與 sound 擇一（都空代表這個 cue 不發聲）。
class Cue:
	extends RefCounted
	var at := 0.0
	var kind: StringName = &""
	var sound: StringName = &""
	var volume_db := 0.0
	var order := 0

	func to_dictionary() -> Dictionary:
		var out := {"at": at}
		if kind != &"":
			out["kind"] = String(kind)
		if sound != &"":
			out["sound"] = String(sound)
		out["volume_db"] = volume_db
		return out

## 內建的三段（資料壞掉時的退路，與 default 資料相同）。
const FALLBACK: Array = [
	{"at": 0.0, "kind": "reload_start", "volume_db": -4.0},
	{"at": 0.55, "kind": "reload_mid", "volume_db": -4.0},
	{"at": 1.0, "kind": "reload_done", "volume_db": -3.0},
]


## 某把武器實際生效的時間軸（已依時間點排序）；找不到或資料壞掉時用內建三段。
static func for_weapon(weapon_id: StringName) -> Array[Cue]:
	var raw: Variant = WeaponSounds.table().lookup(weapon_id, StringName(KEY))
	var errors := validate_list(raw, Sfx.has_named, true)
	if raw == null or not errors.is_empty():
		if raw != null:
			AudioData.report("reload_cues:" + String(weapon_id), "[ReloadCues] %s 的換彈時間軸有問題，改用內建三段：%s" % [weapon_id, "；".join(errors)])
		raw = FALLBACK
	return parse(raw)


## 把設定值轉成排序後的 cue 清單；假設已通過驗證（不合格的項目會被略過）。
static func parse(raw: Variant) -> Array[Cue]:
	var cues: Array[Cue] = []
	if typeof(raw) != TYPE_ARRAY:
		return cues
	for i in (raw as Array).size():
		var entry: Variant = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cue := Cue.new()
		cue.at = clampf(float(entry.get("at", 0.0)), 0.0, 1.0)
		cue.kind = StringName(str(entry.get("kind", "")))
		cue.sound = StringName(str(entry.get("sound", "")))
		cue.volume_db = clampf(float(entry.get("volume_db", 0.0)), VOLUME_RANGE.x, VOLUME_RANGE.y)
		cue.order = i
		cues.append(cue)
	cues.sort_custom(func(a: Cue, b: Cue) -> bool: return a.at < b.at or (a.at == b.at and a.order < b.order))
	return cues


## cue 實際要播的名稱；kind 查該武器的設定，sound 直接用（不存在就不發聲）。
static func sound_of(weapon_id: StringName, cue: Cue) -> StringName:
	if cue.sound != &"":
		return cue.sound if Sfx.has_named(cue.sound) else &""
	if cue.kind != &"":
		return WeaponSounds.name_for(weapon_id, cue.kind)
	return &""


## 資料檢查：回傳錯誤訊息（空 = 沒問題）。null 視為「沒有設定」，合格；has_name 檢查聲音名稱是否存在。
## quiet 為 true 時 sound 不存在不算錯（執行時用：缺的聲音只是不響，不必整份退回預設）。
static func validate_list(value: Variant, has_name: Callable, quiet := false) -> PackedStringArray:
	var errors := PackedStringArray()
	if value == null:
		return errors
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s 要是陣列" % KEY)
		return errors
	var entries: Array = value
	if entries.size() > MAX_CUES:
		errors.append("%s 最多 %d 段（現在 %d 段）" % [KEY, MAX_CUES, entries.size()])
	for i in entries.size():
		var label := "第 %d 段" % (i + 1)
		var entry: Variant = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s 要是字典" % label)
			continue
		var at: Variant = entry.get("at")
		if typeof(at) != TYPE_FLOAT and typeof(at) != TYPE_INT or float(at) < 0.0 or float(at) > 1.0:
			errors.append("%s 的 at 要在 0 到 1 之間（%s）" % [label, at])
		var volume: Variant = entry.get("volume_db", 0.0)
		if typeof(volume) != TYPE_FLOAT and typeof(volume) != TYPE_INT or float(volume) < VOLUME_RANGE.x or float(volume) > VOLUME_RANGE.y:
			errors.append("%s 的 volume_db 要在 %s 到 %s 之間（%s）" % [label, VOLUME_RANGE.x, VOLUME_RANGE.y, volume])
		var kind := str(entry.get("kind", ""))
		var sound := str(entry.get("sound", ""))
		if not kind.is_empty() and not WeaponSounds.KINDS.has(kind):
			errors.append("%s 的 kind「%s」不認得（可用：%s）" % [label, kind, ", ".join(WeaponSounds.KINDS)])
		if not sound.is_empty() and not quiet and not has_name.call(StringName(sound)):
			errors.append("%s 的 sound「%s」不存在" % [label, sound])
		if not kind.is_empty() and not sound.is_empty():
			errors.append("%s 的 kind 與 sound 只能寫一個" % label)
		for key: String in (entry as Dictionary).keys():
			if not ["at", "kind", "sound", "volume_db"].has(key):
				errors.append("%s 有不認得的欄位「%s」" % [label, key])
	return errors


## 檢查資料檔裡每個 profile 的時間軸；錯誤訊息附上 profile 名稱。
static func validate_profiles(table: SoundProfileTable, has_name: Callable) -> PackedStringArray:
	var errors := PackedStringArray()
	var all: Dictionary = {"default": table.raw_default()}
	all.merge(table.raw_profiles())
	for id: String in all.keys():
		var profile: Variant = all[id]
		if typeof(profile) != TYPE_DICTIONARY or not (profile as Dictionary).has(KEY):
			continue
		for message in validate_list((profile as Dictionary)[KEY], has_name):
			errors.append("%s 的「%s」：%s" % [table.path, id, message])
	return errors
