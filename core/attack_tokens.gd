class_name AttackTokens
extends RefCounted
## 攻擊令牌（ST-11）：同時「主動攻擊」的敵人有上限（業界慣例：近戰同時 2、遠程同時 2，其餘的繞行或等待），
## 玩家才讀得懂每一次攻擊、不會被一群怪同時圍毆。上限放在 data/combat/attack_tokens.json，區域可以用 LevelData.attack_caps 覆蓋（前期區域更少）。
##
## 用法：敵人的行為在決定「要不要開始攻擊」時問 Enemy._attack_ready()（冷卻到了而且有令牌）；
## 開始預兆時 Enemy._start_telegraph 自動領取令牌；預兆加上 hold_margin 秒後自動歸還，敵人死亡、離開場景也會歸還，
## 所以被擊暈、卡住的敵人不會一直占著令牌。沒有關卡（例如單獨測試敵人）時不限制。

const CONFIG_PATH := "res://data/combat/attack_tokens.json"
const DEFAULT_HOLD_MARGIN := 1.0
const DEFAULT_GROUPS := {"melee": {"categories": ["melee", "charge"], "max": 2}, "ranged": {"categories": ["ranged", "explosive", "beam"], "max": 2}}

## 目前這個關卡使用的令牌（Level 建立時指定，離開時清除）。
static var active: AttackTokens

var hold_margin := DEFAULT_HOLD_MARGIN
## 群組 -> 上限；類別 -> 群組。
var _caps: Dictionary = {}
var _group_of: Dictionary = {}
## 敵人的 instance id -> {group, until（毫秒）}。
var _holders: Dictionary = {}


## overrides：群組 -> 上限（LevelData.attack_caps），沒列出的群組用設定檔的值。
func _init(overrides: Dictionary = {}) -> void:
	var config := _load_config()
	hold_margin = maxf(0.0, float(config.get("hold_margin", DEFAULT_HOLD_MARGIN)))
	var groups: Dictionary = config.get("groups", DEFAULT_GROUPS)
	for group: String in groups:
		var entry: Variant = groups[group]
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("[AttackTokens] 群組 %s 不是物件（%s），已略過" % [group, CONFIG_PATH])
			continue
		_caps[StringName(group)] = maxi(1, int((entry as Dictionary).get("max", 2)))
		for category: Variant in (entry as Dictionary).get("categories", []):
			_group_of[StringName(str(category))] = StringName(group)
	for group: Variant in overrides:
		if _caps.has(StringName(str(group))):
			_caps[StringName(str(group))] = maxi(1, int(overrides[group]))
		else:
			push_error("[AttackTokens] 區域覆蓋的群組「%s」不存在（有：%s）" % [group, _caps.keys()])


static func _load_config() -> Dictionary:
	var json: JSON = load(CONFIG_PATH) as JSON if ResourceLoader.exists(CONFIG_PATH) else null
	if json == null or typeof(json.data) != TYPE_DICTIONARY:
		push_error("[AttackTokens] 讀不到設定 %s，使用內建預設" % CONFIG_PATH)
		return {}
	return json.data


func group_of(category: StringName) -> StringName:
	return _group_of.get(category, &"")


func cap_of(group: StringName) -> int:
	return int(_caps.get(group, 0))


## 目前占著令牌的敵人數（逾時的不算）。
func held(group: StringName) -> int:
	_purge()
	var count := 0
	for id: int in _holders:
		if (_holders[id] as Dictionary)["group"] == group:
			count += 1
	return count


## 這個敵人現在能不能開始攻擊（已經持有令牌的、不受限類別的都能）。
func allows(enemy_id: int, category: StringName) -> bool:
	var group := group_of(category)
	if group == &"" or _holders.has(enemy_id):
		return true
	return held(group) < cap_of(group)


## 領取令牌，保留 seconds 秒加上 hold_margin。回傳是否領到（不受限類別視為領到但不占名額）。
func claim(enemy_id: int, category: StringName, seconds: float) -> bool:
	var group := group_of(category)
	if group == &"":
		return true
	if not _holders.has(enemy_id) and held(group) >= cap_of(group):
		return false
	_holders[enemy_id] = {"group": group, "until": Time.get_ticks_msec() + int((seconds + hold_margin) * 1000.0)}
	return true


func release(enemy_id: int) -> void:
	_holders.erase(enemy_id)


func _purge() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _holders.keys():
		if int((_holders[id] as Dictionary)["until"]) <= now:
			_holders.erase(id)


# ---------------------------------------------------------------------------
# 敵人用的靜態入口（沒有關卡時不限制）
# ---------------------------------------------------------------------------

static func enemy_allows(enemy: Object, category: StringName) -> bool:
	return active == null or active.allows(enemy.get_instance_id(), category)


static func enemy_claim(enemy: Object, category: StringName, seconds: float) -> void:
	if active != null:
		active.claim(enemy.get_instance_id(), category, seconds)


static func enemy_release(enemy: Object) -> void:
	if active != null:
		active.release(enemy.get_instance_id())
