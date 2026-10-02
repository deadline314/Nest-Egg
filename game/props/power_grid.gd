class_name PowerGrid
extends Node
## 電力網：記錄哪些區域被電力開關切斷。斷電的區域會熄燈（透過光影事件），
## 區域內的雷射柵欄、砲台與升降梯停擺。關卡建立時加入群組 GROUP，消耗電力的物件用 PowerGrid.is_powered() 查詢。

signal zone_changed(zone_id: StringName, powered: bool)

const GROUP := &"power_grid"
const DEFAULT_BLACKOUT_PATH := "res://data/lighting/blackout.tres"
const BLACKOUT_FADE_IN := 0.8
const BLACKOUT_FADE_OUT := 1.2

var tile_size := 16

## 區域 id -> { "start": int, "end": int, "profile": LightingProfile }（欄，含起點不含終點）。
var _zones: Dictionary[StringName, Dictionary] = {}
var _cut: Dictionary[StringName, bool] = {}
var _events: Dictionary[StringName, LightingEvent] = {}


func _ready() -> void:
	add_to_group(GROUP)


## 登記電力區域。同一個 id 重複登記時以第一次為準。
func register_zone(zone_id: StringName, start_tile: int, end_tile: int, profile: LightingProfile = null) -> void:
	if _zones.has(zone_id):
		return
	_zones[zone_id] = {"start": start_tile, "end": end_tile, "profile": profile}


func has_zone(zone_id: StringName) -> bool:
	return _zones.has(zone_id)


func is_zone_powered(zone_id: StringName) -> bool:
	return not _cut.has(zone_id)


## 切斷或恢復電力。silent = true 時不發訊號（還原檢查點用）。
func set_zone_powered(zone_id: StringName, powered: bool, silent := false) -> void:
	if not _zones.has(zone_id) or is_zone_powered(zone_id) == powered:
		return
	if powered:
		_cut.erase(zone_id)
		_events.erase(zone_id)
	else:
		_cut[zone_id] = true
		_events[zone_id] = _make_event(zone_id)
	if not silent:
		zone_changed.emit(zone_id, powered)


## 該像素 x 位置目前是否有電（不在任何被切斷的區域內）。
func is_powered_at_x(x: float) -> bool:
	var tile := x / float(tile_size)
	for zone_id in _cut:
		var zone := _zones[zone_id]
		if tile >= float(zone["start"]) and tile < float(zone["end"]):
			return false
	return true


## 目前斷電區域對應的光影事件（讓關卡把它們併入事件清單）。
func blackout_events() -> Array[LightingEvent]:
	var result: Array[LightingEvent] = []
	for event in _events.values():
		result.append(event)
	return result


func _make_event(zone_id: StringName) -> LightingEvent:
	var zone := _zones[zone_id]
	var event := LightingEvent.new()
	event.id = StringName("power_%s" % zone_id)
	event.start_tile = zone["start"]
	event.end_tile = zone["end"]
	event.profile = zone["profile"] if zone["profile"] != null else _default_blackout()
	event.fade_in = BLACKOUT_FADE_IN
	event.fade_out = BLACKOUT_FADE_OUT
	return event


static func _default_blackout() -> LightingProfile:
	if ResourceLoader.exists(DEFAULT_BLACKOUT_PATH):
		return load(DEFAULT_BLACKOUT_PATH) as LightingProfile
	push_error("[PowerGrid] 找不到預設的斷電光影：%s" % DEFAULT_BLACKOUT_PATH)
	return LightingProfile.new()


## 找到所在關卡的電力網；沒有電力網（例如單獨測試某個物件）時回傳 null，視為一直有電。
static func of(node: Node) -> PowerGrid:
	return node.get_tree().get_first_node_in_group(GROUP) as PowerGrid if node.is_inside_tree() else null


## 這個物件所在位置有沒有電。沒有電力網時一律有電。
static func is_powered(node: Node2D) -> bool:
	var grid := of(node)
	return grid == null or grid.is_powered_at_x(node.global_position.x)
