class_name CharacterSounds
extends RefCounted
## 角色的聲音：受擊（hurt）、死亡（death）、攻擊（attack）、攻擊預兆（telegraph）、警戒（alert）。
## 資料：data/audio/character_sounds.json，以角色 id（player、每種敵人、NPC）查表；
## 沒登記的角色退回 default，所以新增敵人不用先寫聲音。profile 可以用 extends 共用一組（例如 machine、humanoid）。
## 名稱裡的 {attack_category} 等欄位由呼叫端的 ctx 代入。

const PATH := "res://data/audio/character_sounds.json"
const KINDS: PackedStringArray = ["hurt", "death", "attack", "telegraph", "alert"]

static var _table: SoundProfileTable


static func table() -> SoundProfileTable:
	if _table == null:
		_table = SoundProfileTable.new(PATH, "CharacterSounds", KINDS)
	return _table


static func reload_data(fresh := false) -> void:
	table().reload(fresh)


static func play(character_id: StringName, kind: StringName, volume_db := 0.0, ctx: Dictionary = {}) -> void:
	var name := name_for(character_id, kind, ctx)
	if name != &"":
		Sfx.play_named(name, volume_db)


static func name_for(character_id: StringName, kind: StringName, ctx: Dictionary = {}) -> StringName:
	return table().resolve(character_id, kind, ctx, Sfx.has_named)


static func validate() -> PackedStringArray:
	return table().validate(Sfx.has_named)
