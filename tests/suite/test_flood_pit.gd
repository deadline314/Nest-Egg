class_name FloodPitSuite
extends TestSuite
## 水坑（ST-8，第一章水位謎的以死解謎）：資料檢查、踩下踏板後閘門打開並漲水、頭頂被淹過就溺斃（死因 flood）、
## 漲滿後貨櫃浮橋撐得住人、水位與閘門在死後保留（持久世界）、重複觸發不重複作用。

const MAP_PATH := "res://tests/fixtures/flood_map.json"
const PIT_PATH := "res://data/props/ch1_flood_pit.tres"
const GATE_PATH := "res://data/props/ch1_gate_c.tres"
const MECHANISMS: Array[String] = [
	"res://data/props/ch1_switch_a.tres", "res://data/props/ch1_gate_a.tres", "res://data/props/ch1_switch_b.tres",
	"res://data/props/ch1_gate_b.tres", "res://data/props/ch1_gate_c.tres", "res://data/props/ch1_gate_watchdog.tres", PIT_PATH,
]
const TILE := 16.0
## 坑內部：欄 18～28（中心欄 23），列 17～22；坑底第 23 列。
const PIT_CENTER_X := 23.5 * TILE
const PIT_FLOOR_Y := 23.0 * TILE
const PIT_TOP_Y := 17.0 * TILE


func run() -> void:
	_test_data()
	await _test_trigger_and_drown()
	await _test_raft_holds()
	await _test_persists_after_death()


func _level_data(id: StringName) -> LevelData:
	var data := LevelData.new()
	data.id = id
	data.height = 24
	data.layout_path = MAP_PATH
	data.persistent_world = true
	data.rain = false
	data.legend = {"W": load(PIT_PATH), "s": load(GATE_PATH)}
	return data


func _find_pit(level: Level) -> FloodPit:
	for node in level._entities.get_children():
		if node is FloodPit:
			return node
	return null


func _find_gate(level: Level) -> Gate:
	for node in level._entities.get_children():
		if node is Gate:
			return node
	return null


func _test_data() -> void:
	for path in MECHANISMS:
		var data := load(path) as MechanismData
		check(data != null and data.validate().is_empty(), "chapter 1 mechanism is valid: %s %s" % [path, data.validate() if data != null else "missing"])
	var pit := load(PIT_PATH) as MechanismData
	check(pit.kind == MechanismData.Kind.FLOOD_PIT and pit.channel == load(GATE_PATH).channel, "the pit opens the gate on its own channel")
	check(pit.size_tiles.y * float(TILE) > 5.5 * TILE, "the pit is deeper than the jump height: the plate is the only way out")
	var bad := MechanismData.new()
	bad.id = &"test_bad_pit"
	bad.kind = MechanismData.Kind.FLOOD_PIT
	bad.size_tiles = Vector2i(2, 2)
	bad.rise_time = 0.0
	check(bad.validate().size() >= 3, "an invalid pit is reported (channel, size, rise time): %s" % [bad.validate()])


## 踩下踏板：閘門打開、水漲滿、站在坑底的玩家溺斃，死因是 flood。
func _test_trigger_and_drown() -> void:
	var level := await start_level(_level_data(&"test_flood_a"))
	var pit := _find_pit(level)
	var gate := _find_gate(level)
	check(pit != null and gate != null, "the pit and its gate are built")
	if pit == null or gate == null:
		await end_level(level)
		return
	check(not pit.triggered and not gate.is_open, "dry pit, closed gate at the start")
	var causes: Array[StringName] = []
	var listener := func(cause: StringName) -> void: causes.append(cause)
	EventBus.player_died.connect(listener)
	level.player.global_position = Vector2(PIT_CENTER_X, PIT_FLOOR_Y)
	level.player.velocity = Vector2.ZERO
	await physics_frames(8)
	check(pit.triggered, "stepping on the plate triggers the flood")
	check(gate.is_open, "the gate on the channel opens as soon as the plate is pressed")
	for i in 60 * 4:
		if level.player.is_dead():
			break
		await physics_frames(1)
	check(level.player.is_dead() and causes.has(&"flood"), "the player drowns in the rising water (%s)" % [causes])
	check(DefeatCodex.has_card(&"flood"), "drowning has a codex card that explains the puzzle")
	var toasts: Array[String] = []
	var on_toast := func(text: String) -> void: toasts.append(text)
	EventBus.toast_requested.connect(on_toast)
	pit.trigger()
	check(toasts.is_empty(), "triggering twice does nothing")
	EventBus.toast_requested.disconnect(on_toast)
	EventBus.player_died.disconnect(listener)
	await end_level(level)


## 漲滿後水面上的貨櫃撐得住人：站在浮橋上，頭在水面以上，不會溺斃，也不會掉進坑裡。
func _test_raft_holds() -> void:
	var level := await start_level(_level_data(&"test_flood_b"))
	var pit := _find_pit(level)
	pit.restore_state(true)
	check(pit.is_flooded(), "a restored pit is already full")
	level.player.global_position = Vector2(PIT_CENTER_X, PIT_TOP_Y - 30.0)
	level.player.velocity = Vector2.ZERO
	await physics_frames(40)
	check(not level.player.is_dead(), "the raft keeps the player above the water")
	check(level.player.global_position.y < PIT_TOP_Y + 4.0, "the player stands on the raft at the pit's top (y=%.1f)" % level.player.global_position.y)
	await end_level(level)


## 持久世界：死亡後回來，水已經漲滿、閘門保持打開。
func _test_persists_after_death() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := await spawn_level(_level_data(&"test_flood_c"))
	level.player.global_position = Vector2(PIT_CENTER_X, PIT_FLOOR_Y)
	await physics_frames(8)
	level._apply_death_to_world()
	await end_level(level)
	var again := await spawn_level(_level_data(&"test_flood_c"))
	var pit := _find_pit(again)
	var gate := _find_gate(again)
	check(pit.is_flooded() and pit.triggered, "the pit is already full after dying")
	check(gate.is_open, "the gate stays open after dying")
	again.player.global_position = Vector2(PIT_CENTER_X, PIT_TOP_Y - 30.0)
	await physics_frames(40)
	check(not again.player.is_dead(), "the player can cross the flooded pit on the raft")
	await end_level(again)
