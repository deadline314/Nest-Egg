class_name WeaponSounds
extends RefCounted
## 武器的操作聲：換彈（開始、中段、完成）、空槍、換槍。射擊聲維持每把武器的 fire_sound。
## 資料：data/audio/weapon_sounds.json，以武器 id 查表，沒寫的退回 default。

const PATH := "res://data/audio/weapon_sounds.json"
const KINDS: PackedStringArray = ["reload_start", "reload_mid", "reload_done", "empty", "equip"]

static var _table: SoundProfileTable


static func table() -> SoundProfileTable:
	if _table == null:
		_table = SoundProfileTable.new(PATH, "WeaponSounds", KINDS)
	return _table


static func reload(fresh := false) -> void:
	table().reload(fresh)


## 播放某把武器的某個動作聲；weapon 為空時用 default。
static func play(weapon: WeaponData, kind: StringName, volume_db := 0.0) -> void:
	var name := name_for(weapon.id if weapon != null else &"", kind)
	if name != &"":
		Sfx.play_named(name, volume_db)


static func name_for(weapon_id: StringName, kind: StringName) -> StringName:
	return table().resolve(weapon_id, kind, {}, Sfx.has_named)


static func validate() -> PackedStringArray:
	return table().validate(Sfx.has_named)
