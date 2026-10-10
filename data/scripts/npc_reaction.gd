class_name NpcReaction
extends Resource
## 場景人物的短反應（NE-240）：玩家走近時人物不開口、不鎖操作，只用身體做一個 1～3 秒的反應（抬頭點頭、揮開手、揉後頸…）。
## 條件和 NpcTalk 同一套（談過幾次、死亡次數、旗標、看過的劇情、持有物），由 NpcData.pick_reaction 挑：符合條件的最後一個勝出，
## 所以清單越後面越優先（例如「初見」放前面、「凜死過之後」放後面）。手勢名稱是 art/rigs/npc_animations.json 的 gestures。

## 做哪個手勢或小動作（gestures 的名稱）。
@export var gesture: StringName = &""
## 最多談過幾次才用（-1 = 不限；0 = 還沒說過話＝初見）。
@export var max_talks: int = -1
## 至少談過幾次才用（1 = 回訪）。
@export var min_talks: int = 0
## 本輪累計死亡至少幾次才用（人物對凜死過的反應）。
@export var min_deaths: int = 0
## 這個劇情場景在本輪播過之後才用（空白 = 不限）。
@export var after_scene: StringName = &""
@export var requires_flag: StringName = &""
@export var unless_flag: StringName = &""
@export var requires_item: StringName = &""
## 只做一次（存在人物的狀態裡，讀檔、死亡後不重做）；否則每次走近都可以做（有冷卻）。
@export var once: bool = false


func matches(talk_count: int, seen_scene: Callable, deaths := 0, flag_reader: Callable = Callable(), item_reader: Callable = Callable()) -> bool:
	if talk_count < min_talks or (max_talks >= 0 and talk_count > max_talks) or deaths < min_deaths:
		return false
	if after_scene != &"" and (not seen_scene.is_valid() or not bool(seen_scene.call(after_scene))):
		return false
	if requires_flag != &"" and (not flag_reader.is_valid() or not bool(flag_reader.call(requires_flag))):
		return false
	if unless_flag != &"" and flag_reader.is_valid() and bool(flag_reader.call(unless_flag)):
		return false
	if requires_item != &"" and (not item_reader.is_valid() or not bool(item_reader.call(requires_item))):
		return false
	return true


func validate(owner_id: StringName, gestures: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if gesture == &"":
		problems.append("人物 %s 有一個反應沒有指定手勢" % owner_id)
	elif not gestures.is_empty() and not gestures.has(String(gesture)):
		problems.append("人物 %s 的反應手勢「%s」不存在（art/rigs/npc_animations.json 的 gestures）" % [owner_id, gesture])
	if min_talks < 0 or min_deaths < 0 or max_talks < -1:
		problems.append("人物 %s 的反應「%s」次數條件不能為負" % [owner_id, gesture])
	if max_talks >= 0 and max_talks < min_talks:
		problems.append("人物 %s 的反應「%s」max_talks 小於 min_talks，永遠不會發生" % [owner_id, gesture])
	return problems
