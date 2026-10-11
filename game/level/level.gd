class_name Level
extends Node2D
## 關卡場景：依 LevelData 建立地形、實體、玩家、鏡頭與 UI，並處理頭目戰、死亡與過關流程。
## 關卡本身不保存進度（交給 GameState），重來時直接重建整個 Level，保證狀態乾淨、不殘留記憶體。

signal retry_requested
signal menu_requested
signal completed
signal critical_save_requested
## 玩家穿過出入口：請 Main 載入目標區域（路徑是 LevelData 的 .tres）。
signal area_requested(level_path: String)

const ENCOUNTER_SNAPSHOT = preload("res://game/level/encounter_snapshot.gd")
const PLAYER_TUNING_PATH := "res://data/player/player_tuning.tres"
const DEATH_SCREEN_DELAY := 1.1
const VICTORY_DELAY := 2.8
const BOSS_SPAWN_DELAY := 0.8
## 進入戰場左界多少像素後觸發頭目戰。
const ARENA_TRIGGER_MARGIN := 40.0
const FALL_LIMIT_MARGIN := 48.0
const BOSS_LIGHTING_ID := &"boss"
## 燈往上幾格內有實心地形就算吊在天花板；立桿與落地燈具離地最遠多少像素（約 4.5 公尺：再高的桿子比例不對，要把燈放低）。
const LAMP_CEILING_REACH := 6
const LAMP_POLE_MAX := 150.0
const BOSS_LIGHTING_FADE := 1.5
## 重生後多久播出「死亡次數的反應」通訊（等轉場揭開、玩家看清楚畫面）。
const RESPAWN_REACTION_DELAY := 1.2
## 第一次登記復原點後，重生時的提示。
const REGISTERED_TOAST := "電話亭已登記：之後死了，會從這裡醒來"

var data: LevelData
var player: Player
var camera: LevelCamera
var hud: Hud
## 玩家死亡後為 true（Main 據此選擇重來的轉場）。
var died := false

var _layout: LevelLayout
var _world: Node2D
var _entities: Node2D
var _bubbles: MapBubbles
var _tokens: AttackTokens
var _pause_menu: PauseMenu
var _inventory: InventoryScreen
var _background: LevelBackground
var _scenery_walls: BackWallGeometry
var _fog: FogLayer
var _lighting: LightingController
var _post: PostProcess
var _light_budget: LightBudget
var _foreground: ForegroundLayer
var _power_grid: PowerGrid
## 資料裡的光影事件加上目前斷電區域的事件（斷電變化時重建）。
var _lighting_event_list: Array[LightingEvent] = []
var _lighting_event_ids: Dictionary[StringName, bool] = {}
## 正在生效中的光影事件（id -> true）。
var _active_lighting_events: Dictionary[StringName, bool] = {}
var _arena_triggered := false
var _death_can_continue := true
var _boss_spawned := false
var _finished := false
var _next_story_trigger := 0
## 持久世界（LevelData.persistent_world）：本輪的世界狀態跨區域與死亡保留。
var _persistent := false
## 穿過哪個出入口進來（空白＝不是穿過出入口進來的）。
var _entry_portal: StringName = &""
## 這次建立是不是從檢查點重生（沒有穿過出入口、且檢查點在這個區域）。
var _from_checkpoint := false
## 本區域這一輪的狀態（GameState.area_state 的參考；非持久世界為空字典）。
var _area: Dictionary = {}
var _resumed_presentation_completed := false
var _resumed_presentation_settled := false
var _resume_presentation_generation := 0
## 生成格鍵 -> 節點（敵人與拾取物；離開或死亡時據此判斷誰被消滅或撿走，節點可能已被釋放，所以不用型別字典）。
var _tracked: Dictionary = {}
var _portals: Dictionary[StringName, Portal] = {}
var _resume: Dictionary = {}
## True only after the entire live scene and resume state have been installed.
var _initialization_complete := false
var _death_entry: Dictionary = {}
var _death_cause: StringName = &""


func configure(p_data: LevelData) -> void:
	data = p_data


func configure_resume(snapshot: Dictionary) -> void:
	_resume = snapshot


func is_initialized() -> bool:
	return _initialization_complete


func _ready() -> void:
	_layout = LevelBuilder.parse(data)
	if not _layout.is_valid():
		push_error("[Level] 關卡資料無效，返回主選單。")
		menu_requested.emit.call_deferred()
		return

	# Direct resume callers must obey the same strict identity boundary as RunSave.
	if not _resume.is_empty():
		var membership := ENCOUNTER_SNAPSHOT.prepare(_resume, data, _layout)
		if membership.has("error"):
			push_warning("[Level] %s；返回主選單，未套用遭遇狀態。" % membership["error"])
			process_mode = Node.PROCESS_MODE_DISABLED
			menu_requested.emit.call_deferred()
			return
	_persistent = data.persistent_world
	if _resume.get("dead", false):
		died = true
		_finished = true
		_death_entry = _resume.get("death_entry", {})
		_death_cause = StringName(_resume.get("death_cause", "unknown"))
		_death_can_continue = _resume.get("can_continue", true)
	elif _resume.get("ending", false):
		_finished = true
	GameState.current_level_path = data.resource_path
	_entry_portal = GameState.take_pending_portal()
	_from_checkpoint = _entry_portal == &"" and GameState.checkpoint_applies(data.resource_path)
	if _persistent:
		_area = GameState.area_state(data.id)
	elif not _resume.is_empty():
		_area = _resume.get("area", {"consumed": {}, "damage": {}, "world": {}})
	# 成長進度（信用點、改裝）：從檢查點重生就還原成檢查點當下，否則還原成進入關卡時；要在玩家（武器欄）建立之前。
	# 持久世界不回溯：成長一直往前累積（死亡只扣信用點）。
	if not _persistent and _resume.is_empty():
		Progression.restore(GameState.checkpoint_progress if _from_checkpoint else GameState.level_start_progress)
	# 環境光：沒被光源照到的東西會被壓暗；發光的東西用自發光材質不受影響（見 LightKit.mark_emissive）。
	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	add_child(ambient)

	_background = LevelBackground.new()
	if data.environment != null:
		_background.backdrop = data.environment.backdrop
		_background.sky = data.environment.sky
	add_child(_background)
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	var back_wall := BackWall.new()
	_world.add_child(back_wall)
	back_wall.setup(_layout, hash(data.id), data.environment)
	_scenery_walls = back_wall.geometry

	var scenery_start := _world.get_child_count()
	_spawn_decor()
	_lower_scenery(scenery_start, WorldLayers.DECOR)
	# 牆上的影子畫在背牆與牆面裝飾之上、擺設與角色之下。
	var wall_shadows := WallShadows.new()
	wall_shadows.name = "WallShadows"
	wall_shadows.setup(_scenery_walls.support_rects)
	_world.add_child(wall_shadows)
	scenery_start = _world.get_child_count()
	_spawn_props()
	_lower_scenery(scenery_start, WorldLayers.PROPS)

	var terrain := Terrain.new()
	terrain.name = "Terrain"
	terrain.z_index = WorldLayers.TERRAIN
	_world.add_child(terrain)
	terrain.wall_geometry = back_wall.geometry
	terrain.build(_layout, data.environment, data.load_regions())
	if not _layout.ghost_rects.is_empty():
		var ghosts := GhostPlatforms.new()
		ghosts.name = "GhostPlatforms"
		_world.add_child(ghosts)
		ghosts.build(_layout)

	_entities = Node2D.new()
	_entities.name = "Entities"
	_world.add_child(_entities)
	_entities.child_entered_tree.connect(_send_behind_characters)

	var projectiles := Node2D.new()
	projectiles.name = "Projectiles"
	projectiles.z_index = 4
	_world.add_child(projectiles)
	ProjectilePool.bind_container(projectiles)

	var fx := Node2D.new()
	fx.name = "Fx"
	fx.z_index = 6
	_world.add_child(fx)
	Fx.bind_container(fx)

	_spawn_atmosphere()
	_foreground = ForegroundLayer.new()
	_foreground.ground_y = _layout.ground_y
	_foreground.rain = data.rain
	_foreground.covered_columns = _layout.covered_columns
	_foreground.tile_size = _layout.tile_size
	add_child(_foreground)

	hud = Hud.new()
	add_child(hud)

	_power_grid = PowerGrid.new()
	_power_grid.name = "PowerGrid"
	_power_grid.tile_size = _layout.tile_size
	add_child(_power_grid)
	_power_grid.zone_changed.connect(func(_zone: StringName, _powered: bool) -> void: _rebuild_lighting_events())

	_spawn_static_entities()
	_spawn_cinematic_entries()
	_spawn_player()
	# 從檢查點重生：還原被打破的箱子、開關、閘門與電力（要在光影設定之前，事件才會正確）。
	WorldState.restore(get_tree(), _resume.get("world", {}) if not _resume.is_empty() else (_area.get("world", {}) if _persistent else GameState.checkpoint_world))
	_rebuild_lighting_events()

	for problem in data.validate_lighting():
		push_error("[Level] %s" % problem)
	# 背景音樂先知道進入了哪一關，之後光影區段的宣告（zone_changed）才會選出曲目。
	Music.enter_level(data.id)
	tree_exiting.connect(Music.leave_level)
	_post = PostProcess.new()
	add_child(_post)
	_lighting = LightingController.new()
	add_child(_lighting)
	_lighting.setup(data.lighting_zones, _layout.tile_size, player, ambient, _background, _fog, data.fog_color, _post)
	# 從檢查點重生時若正好在事件範圍內，直接套用，不從區段光影漸變。
	_update_lighting_events(0.0)
	_lighting.snap()
	_light_budget = LightBudget.new()
	add_child(_light_budget)

	camera = LevelCamera.new()
	add_child(camera)
	camera.set_bounds(Rect2(Vector2.ZERO, _layout.pixel_size()))
	camera.target = player
	camera.snap_to_target()
	# 恢復arena會鎖camera；須在玩家與鏡頭完成初始化後領回runtime。
	if not _restore_run_entities():
		process_mode = Node.PROCESS_MODE_DISABLED
		menu_requested.emit.call_deferred()
		return

	_tokens = AttackTokens.new(data.attack_caps)
	AttackTokens.active = _tokens
	tree_exiting.connect(func() -> void:
		if AttackTokens.active == _tokens:
			AttackTokens.active = null)

	_bubbles = MapBubbles.new()
	_bubbles.anchor_resolver = _bubble_anchor
	add_child(_bubbles)
	Story.set_bubble_host(_bubbles)

	_pause_menu = PauseMenu.new()
	_pause_menu.chapter = data.chapter
	add_child(_pause_menu)
	_pause_menu.retry_requested.connect(_request_retry)
	_pause_menu.menu_requested.connect(_request_menu)

	_inventory = InventoryScreen.new()
	_inventory.configure(player)
	add_child(_inventory)

	EventBus.player_died.connect(_on_player_died)
	# 遊戲中以準星取代系統游標；離開關卡時還原。
	UiKit.set_cursor_visible(false)
	tree_exiting.connect(UiKit.set_cursor_visible.bind(true))
	EventBus.boss_defeated.connect(_on_boss_defeated)
	if not data.channel_scenes.is_empty():
		EventBus.mechanism_toggled.connect(_on_channel_toggled)  # 關卡釋放時自動斷線
	# 玩家在這個區域的時候，背景預載鄰居與接下來的過場舞台（下次進場不用當場解碼貼圖）。
	_initialization_complete = true
	if _arena_triggered and not _boss_spawned and not _resume.get("ending", false) and not _resume.get("dead", false):
		_resume_pending_boss.call_deferred()
	AssetPrefetch.warm_neighbors.call_deferred(data)
	if _resume.get("dead", false):
		_resume_death.call_deferred()
	elif _resume.get("cinematic", "") != "":
		_resume_cinematic.call_deferred()
	elif _resume.get("ending", false):
		_resume_ending.call_deferred()
	else:
		_begin_intro.call_deferred()
		_begin_death_reactions.call_deferred()


func _process(delta: float) -> void:
	if _initialization_complete and not _finished and is_instance_valid(player) and not player.is_dead():
		GameState.run_time += delta


func _physics_process(_delta: float) -> void:
	if not _initialization_complete or _layout == null or not is_instance_valid(player):
		return
	_check_story_triggers()
	_update_lighting_events()
	if _arena_triggered or _layout.arena_x < 0.0:
		return
	if player.global_position.x > _layout.arena_x + ARENA_TRIGGER_MARGIN:
		_start_boss_fight()


# ---------------------------------------------------------------------------
# 劇情
# ---------------------------------------------------------------------------

## 開場：從關卡開頭進入時播放開場過場，接著顯示章節標題（從檢查點重生時略過）。
func _begin_intro() -> void:
	if _from_checkpoint or not is_inside_tree():
		return
	if data.intro_scene != &"" and not Story.was_seen(data.intro_scene):
		if not await _play_flow_scene(data.intro_scene):
			return
		if not is_inside_tree():
			return
	if _entry_portal != &"":
		# 穿過出入口進來：只標示區域名稱，不重播章節標題。
		if data.announce_area and not data.display_name.is_empty():
			EventBus.toast_requested.emit(data.display_name)
	elif data.show_chapter_card and _resume.is_empty():
		var info := Story.chapter_info(data.chapter)
		_show_chapter_card(str(info.get("title", data.display_name)), str(info.get("subtitle", "")), false)
	if _finished:
		return
	if data.complete_after_intro:
		_finished = true
		_close_menus()
		await _run_ending()
	elif data.after_intro_portal != &"":
		var portal: Portal = _portals.get(data.after_intro_portal)
		if portal == null:
			push_error("[Level] %s 的 after_intro_portal「%s」在地圖上找不到" % [data.id, data.after_intro_portal])
		else:
			portal.try_use()


## 氣泡的講者在地圖上的位置：凜是玩家，其餘是 speaker 對得上的場景人物；找不到回傳 null（該段改用通訊）。
func _bubble_anchor(speaker_id: String) -> Node2D:
	if speaker_id == "rin":
		return player if is_instance_valid(player) else null
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		var npc := node as NpcActor
		if npc != null and npc.data != null and (npc.data.speaker == speaker_id or String(npc.data.id) == speaker_id):
			return npc
	return null


## 死亡重生後：累計死亡達到次數時，播出這一章設定的反應通訊（見 StoryReactions）。只改措辭，不影響流程與難度。
func _begin_death_reactions() -> void:
	if not GameState.consume_respawn() or not is_inside_tree():
		return
	await get_tree().create_timer(RESPAWN_REACTION_DELAY, false).timeout
	if not is_inside_tree():
		return
	if GameState.consume_checkpoint_notice():
		EventBus.toast_requested.emit(REGISTERED_TOAST)
	Story.play_respawn_reactions(data.chapter)


func _show_chapter_card(title: String, subtitle: String, block: bool, hold := 2.2) -> ChapterCard:
	var card := ChapterCard.new()
	card.title = title
	card.subtitle = subtitle
	card.block = block
	card.hold = hold
	add_child(card)
	return card


## 機關頻道啟動時播放對應的場景（LevelData.channel_scenes）。
func _on_channel_toggled(channel: StringName, active: bool) -> void:
	if active and data.channel_scenes.has(channel):
		Story.play(data.channel_scenes[channel])


## 資料裡的光影事件加上斷電區域的事件；電力變化或還原檢查點後重建。
func _rebuild_lighting_events() -> void:
	_lighting_event_list.clear()
	_lighting_event_list.append_array(data.lighting_events)
	_lighting_event_list.append_array(_power_grid.blackout_events())
	_lighting_event_ids.clear()
	for event in _lighting_event_list:
		if event != null:
			_lighting_event_ids[event.id] = true


## 玩家進入／離開光影事件範圍（停電走廊、斷電區域…）時請求或結束覆蓋。fade_override >= 0 時用它當淡入時間。
func _update_lighting_events(fade_override := -1.0) -> void:
	var tile := player.global_position.x / float(_layout.tile_size)
	for event in _lighting_event_list:
		if event == null or event.profile == null:
			continue
		var inside := event.contains_tile(tile)
		if inside and not _active_lighting_events.has(event.id):
			_active_lighting_events[event.id] = true
			EventBus.lighting_override_requested.emit(event.id, event.profile, event.fade_in if fade_override < 0.0 else maxf(0.01, fade_override))
		elif not inside and _active_lighting_events.has(event.id):
			_active_lighting_events.erase(event.id)
			EventBus.lighting_override_cleared.emit(event.id, event.fade_out)
	# 事件本身消失了（電力恢復）：結束仍在生效的覆蓋。
	if _has_stale_active_event():
		for id in _active_lighting_events.keys():
			if not _lighting_event_ids.has(id):
				_active_lighting_events.erase(id)
				EventBus.lighting_override_cleared.emit(id, PowerGrid.BLACKOUT_FADE_OUT)


func _has_stale_active_event() -> bool:
	for id in _active_lighting_events:
		if not _lighting_event_ids.has(id):
			return true
	return false


## 玩家越過 & 觸發點時播放對應的通訊（每輪只播一次，重生後不重播）。
func _check_story_triggers() -> void:
	while _next_story_trigger < _layout.story_triggers.size():
		var trigger: Dictionary = _layout.story_triggers[_next_story_trigger]
		if player.global_position.x < trigger["x"]:
			return
		Story.play(trigger["scene"])
		_next_story_trigger += 1


# ---------------------------------------------------------------------------
# 建立實體
# ---------------------------------------------------------------------------

func _spawn_static_entities() -> void:
	for cells in _layout.spike_rects:
		var spikes := Spikes.new()
		spikes.setup(_layout.cells_to_pixels(cells))
		_entities.add_child(spikes)
	for i in _layout.laser_rects.size():
		var fence := LaserFence.new()
		fence.setup(_layout.cells_to_pixels(_layout.laser_rects[i]), i * 0.7)
		_entities.add_child(fence)
	for pos in _layout.checkpoints:
		var checkpoint := Checkpoint.new()
		checkpoint.position = pos
		_entities.add_child(checkpoint)
	for pos in _layout.health_pickups:
		var key := "health@%d,%d" % [int(pos.x), int(pos.y)]
		if _area.get("consumed", {}).has(key):
			continue
		var pickup := HealthPickup.new()
		pickup.position = pos
		_entities.add_child(pickup)
		_tracked[key] = pickup
	# 每個光影區段亮著的燈依序輪到供電狀況訂的狀態（穩定、接觸不良、快壞了）。
	var lit_lamps_by_zone := {}
	var buzzing: Array[Lamp] = []
	for i in _layout.lamps.size():
		var lamp := Lamp.new()
		lamp.position = _layout.lamps[i] + Vector2(0, 2)
		# 風格由所在區段決定；沒有區段時維持霓虹三原色交錯。
		var tile := int(lamp.position.x / _layout.tile_size)
		lamp.floor_y = _layout.floor_below(tile, int(lamp.position.y / _layout.tile_size))
		lamp.ceiling_y = _lamp_ceiling(tile, int(lamp.position.y / _layout.tile_size))
		var profile := data.profile_at_tile(tile)
		if profile != null and profile.lamp_style != null:
			lamp.flipped = i % 2 == 1
			lamp.apply_style(profile.lamp_style, hash(Vector2i(tile, int(lamp.position.y))), _lamp_supports(lamp, _scenery_walls), i)
		else:
			lamp.color = [Palette.CYAN, Palette.MAGENTA, Palette.NEON_YELLOW][i % 3]
			var supports := _lamp_supports(lamp, _scenery_walls)
			lamp.use_fixture(LampFixtures.pick(PackedStringArray(), supports, i, 0), supports)
		var lamp_row := int(lamp.position.y / _layout.tile_size)
		lamp.settle(func(x: float) -> float: return _layout.floor_below(int(x / _layout.tile_size), lamp_row))
		if profile != null and profile.lamp_style != null and not lamp.dead:
			var lit: int = lit_lamps_by_zone.get(profile.id, 0)
			lit_lamps_by_zone[profile.id] = lit + 1
			lamp.use_flicker(LampFlicker.state_for(profile.lamp_style.supply_id(), lit), hash(Vector2i(tile, lamp_row)))
			if LampFlicker.buzz(lamp.flicker_state) > 0.0:
				buzzing.append(lamp)
		_world.add_child(lamp)
	if not buzzing.is_empty():
		var buzz := LampBuzz.new()
		buzz.name = "LampBuzz"
		buzz.setup(buzzing)
		_world.add_child(buzz)
	for hint in _layout.hints:
		var sign := HintSign.new()
		sign.text = str(hint["text"])
		sign.position = hint["position"]
		_entities.add_child(sign)
	for spawn in _layout.spawns:
		var resource: Resource = spawn["resource"]
		var key := _spawn_key(spawn)
		var trackable := resource is EnemyData or resource is WeaponData or resource is ConsumableData or resource is StoryItemData or resource is CreditPileData
		if trackable and _area.get("consumed", {}).has(key):
			continue  # 本輪已經被消滅或撿走
		var node := _create_prop(spawn) if _is_prop_resource(resource) else _create_entity(resource)
		if node != null:
			node.position = spawn["position"]
			_entities.add_child(node)
			if node is Vehicle:
				(node as Vehicle).fall_limit_y = _fall_limit()
			if node is Portal:
				_portals[(resource as PortalData).id] = node
				node.used.connect(_on_portal_used)
			if trackable:
				_tracked[key] = node
				var lost: int = int(_area.get("damage", {}).get(key, 0))
				if lost > 0 and node is Enemy:
					(node as Enemy).restore_lost_health(lost)


## 不是角色的實體（看板、檢查點、出入口、開關、拾取物…）排在所有角色零件之下；已經有自己圖層的不動。
func _send_behind_characters(node: Node) -> void:
	var item := node as CanvasItem
	if item != null and item.z_index == 0 and not WorldLayers.is_character(node):
		item.z_index = WorldLayers.ENTITY_BEHIND


## 把剛生成的靜態場景節點（還在預設圖層的）排到所有角色零件之下；已經有自己圖層的（前景道具）不動。
func _lower_scenery(from_child: int, z: int) -> void:
	for i in range(from_child, _world.get_child_count()):
		var node := _world.get_child(i) as CanvasItem
		if node != null and node.z_index == 0:
			node.z_index = z


## 招牌、看板、排氣孔等裝飾（畫在地形與角色之後方）。
func _spawn_decor() -> void:
	for entry in _layout.decor:
		if entry["kind"] in ["neon_sign", "neon_sign_h", "billboard"] and not _scenery_walls.covers(ScenerySupport.decor_rect(entry, data)):
			push_warning("[Level] %s 裝飾 %s 格 %s 沒有完整牆面支撐，已略過" % [data.id, entry["kind"], entry["cell"]])
			continue
		var cell: Vector2i = entry["cell"]
		var position: Vector2 = entry["position"]
		var hash_value := absi(cell.x * 73856093 ^ cell.y * 19349663)
		var zone_profile := data.profile_at_tile(cell.x)
		var palette: PackedColorArray = zone_profile.neon_colors if zone_profile != null and not zone_profile.neon_colors.is_empty() else PackedColorArray(Palette.NEON_COLORS)
		var neon: Color = palette[hash_value % palette.size()]
		var neon_intensity := zone_profile.neon_energy if zone_profile != null else 1.0
		match str(entry["kind"]):
			"neon_sign", "neon_sign_h":
				var sign := NeonSign.new()
				sign.vertical = entry["kind"] == "neon_sign"
				sign.text = data.sign_texts[hash_value % data.sign_texts.size()] if not data.sign_texts.is_empty() else "OPEN"
				sign.color = neon
				sign.intensity = neon_intensity
				sign.position = position
				sign.floor_y = _layout.floor_below(cell.x, cell.y)
				_world.add_child(sign)
			"billboard":
				var board := HoloBillboard.new()
				board.position = position
				board.color = neon
				board.ads = data.billboard_ads
				_world.add_child(board)
			"steam_vent":
				var vent := SteamVent.new()
				vent.position = position + Vector2(_layout.tile_size * 0.5, _layout.tile_size)
				_world.add_child(vent)
			_:
				var prop := PropLibrary.find_in(StringName(str(entry["kind"])), _prop_dirs())
				if prop == null:
					push_warning("[Level] 未知的裝飾種類：%s" % entry["kind"])
				else:
					_place_prop(prop, position + Vector2(0.0, _layout.tile_size - prop.size.y), false)


## 地圖 JSON 的 props 清單（見 LevelData.load_props）：以道具資料的 id 擺放。
func _spawn_props() -> void:
	var dirs := _prop_dirs()
	var entries := data.load_props()
	for entry in entries:
		var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
		if prop == null:
			continue
		var placed := PropPlacement.resolve(entry, prop, _layout)
		if placed.is_empty():
			push_warning("[Level] 道具 %s 第 %d 欄下方沒有地表，已略過" % [prop.id, int(entry["x"])])
			continue
		var rect: Rect2 = placed["rect"]
		var issue := ScenerySupport.check_prop(entry, prop, rect, _layout, _scenery_walls, entries, dirs)
		if not issue.is_empty():
			push_warning("[Level] %s 道具 %s 第 %d 欄支撐無效（%s），已略過" % [data.id, prop.id, int(entry["x"]), issue])
			continue
		_place_prop(prop, rect.position, bool(placed["flip"]))


func _place_prop(prop: PropData, top_left: Vector2, flip: bool) -> void:
	var node := PropNode.new()
	node.setup(prop, top_left, flip)
	_world.add_child(node)


func _prop_dirs() -> PackedStringArray:
	return data.environment.prop_dirs() if data.environment != null else PackedStringArray([PropLibrary.DEFAULT_DIR])


## 雨與霧（畫在角色前方，低透明度）。
func _spawn_atmosphere() -> void:
	_fog = FogLayer.new()
	_fog.z_index = 7
	_fog.ground_y = _layout.ground_y
	_fog.layout = _layout
	_fog.color = data.fog_color
	_world.add_child(_fog)
	if data.rain:
		var rain := RainLayer.new()
		rain.z_index = 8
		rain.tile_size = _layout.tile_size
		rain.surface_heights = _layout.surface_heights
		_world.add_child(rain)


## 依資源型別建立對應實體；未知型別記錄警告並略過。
func _create_entity(resource: Resource) -> Node2D:
	if resource is EnemyData:
		return _create_enemy(resource as EnemyData)
	if resource is WeaponData:
		var pickup := WeaponPickup.new()
		pickup.configure(resource as WeaponData)
		return pickup
	if resource is ConsumableData:
		var item := ConsumablePickup.new()
		item.configure(resource as ConsumableData)
		return item
	if resource is StoryItemData:
		var collectible := resource as StoryItemData
		# 已收集的不再出現（收集跟著本輪進度）。
		if StoryItems.owns(collectible.id):
			return null
		var pickup := CollectiblePickup.new()
		pickup.configure(collectible)
		return pickup
	if resource is ChaseData:
		var curtain := LightCurtain.new()
		curtain.configure(resource as ChaseData, _layout.tile_size, _layout.pixel_size().y)
		return curtain
	if resource is VehicleData:
		var vehicle := Vehicle.new()
		vehicle.configure(resource as VehicleData)
		return vehicle
	push_warning("[Level] 不支援的 legend 資源：%s" % resource)
	return null


func _spawn_cinematic_entries() -> void:
	for entry in data.cinematic_entries:
		if entry == null or entry.cell.x < 0 or entry.cell.y < 0 or entry.cell.x >= _layout.width or entry.cell.y >= _layout.height:
			push_error("[Level] %s 的電影入口位置無效，已略過。" % data.id)
			continue
		var entrance := CinematicEntrance.new()
		entrance.configure(entry)
		entrance.position = _layout.cell_to_feet(entry.cell.x, entry.cell.y)
		_entities.add_child(entrance)


static func _is_prop_resource(resource: Resource) -> bool:
	return resource is BreakableData or resource is MechanismData or resource is CreditPileData \
			or resource is ShopData or resource is NpcData or resource is PortalData


## 生成物在本區域裡固定的鍵（資源 id 加格座標）；地圖資料改版後對不上的鍵會被忽略。
func _spawn_key(spawn: Dictionary) -> String:
	var cell: Vector2i = spawn["cell"]
	var res: Resource = spawn["resource"]
	var res_id := str(res.get(&"id")) if res.get(&"id") != null else res.get_class()
	return "%s@%d,%d" % [res_id, cell.x, cell.y]


func _create_prop(spawn: Dictionary) -> Node2D:
	var resource: Resource = spawn["resource"]
	var cell: Vector2i = spawn["cell"]
	if resource is PortalData:
		var portal := Portal.new()
		portal.configure(resource as PortalData, cell)
		return portal
	if resource is BreakableData:
		for problem in (resource as BreakableData).validate():
			push_error("[Level] %s" % problem)
		var breakable := Breakable.new()
		breakable.configure(resource as BreakableData, cell, _layout.tile_size)
		breakable.broken.connect(_on_breakable_broken)
		return breakable
	if resource is NpcData:
		var npc := NpcActor.new()
		npc.configure(resource as NpcData, cell)
		return npc
	if resource is ShopData:
		var shop := resource as ShopData
		for problem in shop.validate():
			push_error("[Level] %s" % problem)
		var station := ShopStation.new()
		station.configure(shop, cell)
		return station
	if resource is CreditPileData:
		var pile := resource as CreditPileData
		for problem in pile.validate():
			push_error("[Level] %s" % problem)
		var credits := CreditPickup.new()
		credits.configure_pile(pile, cell)
		return credits
	if resource is MechanismData:
		var mechanism := resource as MechanismData
		for problem in mechanism.validate():
			push_error("[Level] %s" % problem)
		match mechanism.kind:
			MechanismData.Kind.LIFT:
				var lift := Lift.new()
				lift.configure(mechanism, cell, _layout.tile_size)
				return lift
			MechanismData.Kind.GATE:
				var gate := Gate.new()
				gate.configure(mechanism, cell, _layout.tile_size)
				return gate
			MechanismData.Kind.SWITCH:
				var channel_switch := ChannelSwitch.new()
				channel_switch.configure(mechanism, cell)
				return channel_switch
			MechanismData.Kind.POWER_SWITCH:
				var power_switch := PowerSwitch.new()
				power_switch.configure(mechanism, cell)
				return power_switch
			MechanismData.Kind.FLOOD_PIT:
				var pit := FloodPit.new()
				pit.configure(mechanism, cell, _layout.tile_size)
				return pit
			MechanismData.Kind.ENCOUNTER:
				var zone := EncounterZone.new()
				zone.configure(mechanism, cell, _layout.tile_size)
				zone.spawner = _spawn_reinforcement
				return zone
	return null


## 鎖場遭遇的增援：在指定位置生成一個敵人（閃一下警示光），回傳敵人；資料壞掉回傳 null。
func _spawn_reinforcement(enemy_data: EnemyData, world_position: Vector2) -> Enemy:
	var enemy := _create_enemy(enemy_data)
	if enemy == null:
		return null
	enemy.position = world_position
	_entities.add_child(enemy)
	Fx.flash_light(world_position + Vector2(0, -24), Palette.DANGER, 120.0, 1.5, 0.4)
	return enemy


## 破壞後生成掉落物（依位置固定的隨機結果）。
func _on_breakable_broken(breakable: Breakable) -> void:
	var position := breakable.world_center()
	if breakable.data.credit_drop > 0:
		var credits := CreditPickup.new()
		credits.value = breakable.data.credit_drop
		credits.position = position
		_entities.add_child.call_deferred(credits)
	var drop := breakable.roll_drop()
	var item: Node2D = null
	if drop["resource"] != null:
		item = _create_entity(drop["resource"])
	elif drop["health"]:
		item = HealthPickup.new()
	if item == null:
		return
	item.position = position
	_entities.add_child.call_deferred(item)


func _create_enemy(enemy_data: EnemyData) -> Enemy:
	for problem in enemy_data.validate():
		push_error("[Level] %s" % problem)
	if enemy_data.behavior == null:
		return null
	var instance: Object = enemy_data.behavior.new()
	var enemy := instance as Enemy
	if enemy == null:
		push_error("[Level] %s 的 behavior 沒有繼承 Enemy" % enemy_data.id)
		if instance is Node:
			(instance as Node).free()
		return null
	enemy.configure(enemy_data)
	return enemy


func _spawn_player() -> void:
	var tuning: PlayerTuning = load(PLAYER_TUNING_PATH) as PlayerTuning if ResourceLoader.exists(PLAYER_TUNING_PATH) else null
	if tuning == null:
		push_error("[Level] 無法載入玩家參數：%s" % PLAYER_TUNING_PATH)
	player = Player.new()
	player.configure(tuning, GameState.difficulty.player_max_health, _resume.get("loadout", GameState.checkpoint_loadout))
	player.position = _entry_position()
	player.fall_limit_y = _fall_limit()
	_entities.add_child(player)
	if not _resume.is_empty():
		var saved_position := RunSaveCodec.vector(_resume.get("position"), Vector2(-1, -1))
		player.position = _entry_position() if saved_position == Vector2(-1, -1) else _safe_resume_position(saved_position)
		player.facing = -1 if _resume.get("facing") == -1 else 1
		player.aim_dir = RunSaveCodec.vector(_resume.get("aim_dir"), Vector2(player.facing, 0))
		AimInput.restore_direction(player.aim_dir)
		player.velocity = RunSaveCodec.vector(_resume.get("velocity"))
		player.is_crouching = _resume.get("crouching", false)
		player.guard = clampf(float(_resume.get("guard", player.guard)), 0, player.tuning.guard_max)
		if not _resume.get("dead", false):
			player.health.current = clampi(int(_resume.get("health", player.health.current)), 1, player.health.max_health)
			player.health.health_changed.emit(player.health.current, player.health.max_health)
		else:
			# 此時 Level 尚未接 player_died；只恢復死者姿勢，不再次結算。
			player.health.kill(DamageInfo.create(0, Combat.Team.ENEMY, StringName(_resume.get("death_cause", "unknown"))))
	if GameState.respawn_pending and _from_checkpoint:
		player.play_respawn_fx()
	# 穿過出入口時帶著上一個區域的生命值（不會因為換個房間就補滿）。
	if GameState.carried_health > 0 and _entry_portal != &"" and player.health != null:
		player.health.current = clampi(GameState.carried_health, 1, player.health.max_health)
		player.health.health_changed.emit(player.health.current, player.health.max_health)
	GameState.carried_health = -1
	var entry: Portal = _portals.get(_entry_portal)
	if entry != null:
		entry.disarm()


## 玩家出現的位置：穿過的出入口 > 這個區域的檢查點 > 起點 P。出入口找不到時記錄具體位置並退回起點。
func _entry_position() -> Vector2:
	if _entry_portal != &"":
		for spawn in _layout.spawns:
			var resource: Resource = spawn["resource"]
			if resource is PortalData and (resource as PortalData).id == _entry_portal:
				return spawn["position"]
		push_error("[Level] %s 沒有出入口「%s」（%s），改用起點" % [data.id, _entry_portal, data.layout_path])
	elif _from_checkpoint:
		return _checked_checkpoint_position()
	return _layout.player_start


## 復原點的位置：欄位遺失（舊檔、零向量）或落在地圖外時，記錄具體位置並退回最近的電話亭，沒有電話亭就退回起點，不讓玩家出現在牆裡。
func _checked_checkpoint_position() -> Vector2:
	var saved := GameState.checkpoint_position
	var bounds := Rect2(Vector2.ZERO, _layout.pixel_size())
	if saved != Vector2.ZERO and _resume_position_valid(saved):
		return saved
	push_error("[Level] %s 的復原點位置無效（%s，地圖範圍 %s），改用最近的電話亭或起點" % [data.id, saved, bounds])
	if _layout.checkpoints.is_empty():
		return _layout.player_start
	var best := _layout.checkpoints[0]
	for pos in _layout.checkpoints:
		if absf(pos.x - saved.x) < absf(best.x - saved.x):
			best = pos
	return best


func _fall_limit() -> float:
	return _layout.pixel_size().y + FALL_LIMIT_MARGIN


# ---------------------------------------------------------------------------
# 頭目戰
# ---------------------------------------------------------------------------

func _lock_boss_arena() -> void:
	_arena_triggered = true
	if data.boss_lighting != null:
		EventBus.lighting_override_requested.emit(BOSS_LIGHTING_ID, data.boss_lighting, BOSS_LIGHTING_FADE)
	if not data.lock_boss_arena:
		return
	var tile := float(_layout.tile_size)
	# 關上身後的閘門並鎖住鏡頭左界。
	var gate := StaticBody2D.new()
	gate.collision_layer = Layers.WORLD
	var shape := RectangleShape2D.new()
	shape.size = Vector2(tile, _layout.pixel_size().y)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = shape
	shape_node.position = Vector2(_layout.arena_x - tile * 0.5, _layout.pixel_size().y * 0.5)
	gate.add_child(shape_node)
	_world.add_child(gate)
	var gate_visual := _GateVisual.new()
	gate_visual.position = Vector2(_layout.arena_x - tile, 0)
	gate_visual.size = Vector2(tile, _layout.pixel_size().y)
	_world.add_child(gate_visual)
	camera.lock_left(_layout.arena_x)


func _start_boss_fight() -> void:
	_lock_boss_arena()
	if data.lock_boss_arena:
		Feel.play(&"boss_arena_lock")
	EventBus.toast_requested.emit("警告：偵測到大型反應")
	if _layout.boss_spawn.is_empty():
		push_warning("[Level] 有戰場標記 B 但沒有頭目")
		return
	await get_tree().create_timer(BOSS_SPAWN_DELAY, false).timeout
	if not is_inside_tree():
		return
	if not await _play_flow_scene(data.boss_scene):
		return
	if is_inside_tree() and not _finished:
		_spawn_boss()


func _spawn_boss() -> void:
	if not is_inside_tree() or _layout.boss_spawn.is_empty():
		return
	var boss := _create_enemy(_layout.boss_spawn["resource"])
	if boss == null:
		return
	_boss_spawned = true
	boss.position = _layout.boss_spawn["position"]
	# 場地範圍：從戰場左界到關卡右緣（機動型頭目與場地機關用）。
	if boss.has_method(&"set_arena"):
		boss.call(&"set_arena", Rect2(_layout.arena_x, 0.0, _layout.pixel_size().x - _layout.arena_x - _layout.tile_size, _layout.pixel_size().y))
	_entities.add_child(boss)
	Fx.flash_light(boss.position + Vector2(0, -24), Palette.DANGER, 220.0, 2.5, 0.8)


# ---------------------------------------------------------------------------
# 流程
# ---------------------------------------------------------------------------

func _on_player_died(cause: StringName) -> void:
	if _finished:
		return
	_finished = true
	died = true
	_close_menus()
	var card := DefeatCodex.unlock(cause)
	var can_continue := GameState.register_death()
	_death_can_continue = can_continue
	# 特殊的死亡場景（第一次死亡的診間）：不扣復原費（劇情必死）、不經過死亡畫面，直接播完再重生。
	var scene_entry := Story.death_scene_entry(data.chapter, cause) if can_continue else {}
	_death_entry = scene_entry
	_death_cause = cause
	_apply_death_to_world(not bool(scene_entry.get("free", false)))
	# 同一份快照先落死亡計數、世界與扣款；黑幕前必須保存。
	critical_save_requested.emit()
	await get_tree().create_timer(DEATH_SCREEN_DELAY, false).timeout
	if not is_inside_tree():
		return
	if not scene_entry.is_empty():
		await _run_death_scene(scene_entry)
		return
	var screen := DeathScreen.new()
	screen.sequence = Story.death_sequence(data.chapter)
	screen.setup(card, can_continue)
	screen.retry_requested.connect(_request_retry)
	screen.menu_requested.connect(_request_menu)
	add_child(screen)


## 死亡後、重生前的特殊過場（見 StoryReactions 的 death_scenes）。播完（含按 Esc 跳過）才登記復原點，然後重生。
## once = false：是否再播由資料的旗標決定，過場中途退出就會從頭再播。
func _run_death_scene(entry: Dictionary) -> void:
	if not await _play_flow_scene(StringName(str(entry.get("scene", ""))), false):
		return
	if not is_inside_tree():
		return
	if bool(entry.get("register_checkpoint", false)) and _register_nearest_checkpoint():
		GameState.checkpoint_notice_pending = true
	_request_retry()


## 本輪還沒有復原點時，登記離死亡位置最近的電話亭，之後從那裡醒來。已經有復原點就不動。
## 這個區域沒有電話亭時記錄錯誤並回傳 false（重生退回區域起點，不崩潰）。
func _register_nearest_checkpoint() -> bool:
	if GameState.has_checkpoint:
		return false
	if _layout == null or _layout.checkpoints.is_empty():
		push_error("[Level] %s 沒有電話亭可登記復原點（%s），重生會退回區域起點" % [data.id, data.layout_path])
		return false
	var from := player.global_position if is_instance_valid(player) else _layout.player_start
	var best := _layout.checkpoints[0]
	for pos in _layout.checkpoints:
		if absf(pos.x - from.x) < absf(best.x - from.x):
			best = pos
	var snapshot := player.checkpoint_snapshot() if is_instance_valid(player) else GameState.checkpoint_loadout
	GameState.set_checkpoint(best, snapshot, {}, Progression.snapshot())
	return true


func _on_boss_defeated() -> void:
	EventBus.lighting_override_cleared.emit(BOSS_LIGHTING_ID, BOSS_LIGHTING_FADE * 2.0)
	if _finished:
		return
	_finished = true
	_close_menus()
	await get_tree().create_timer(VICTORY_DELAY, false).timeout
	if not is_inside_tree():
		return
	await _run_ending()


## 結尾：結尾過場、章末卡、帶走裝備，然後通關（頭目戰勝利與「進場後結束」的區域共用）。
func _run_ending() -> void:
	if not is_inside_tree():
		return
	if not await _play_flow_scene(data.outro_scene):
		return
	if not is_inside_tree():
		return
	var info := Story.chapter_info(data.chapter)
	if info.has("end_title"):
		var card := _show_chapter_card(str(info["end_title"]), str(info.get("teaser", "")), true, 2.8)
		await card.finished
	if is_inside_tree():
		if is_instance_valid(player):
			GameState.carry_over(player.checkpoint_snapshot())
		completed.emit()


## 死亡或過關時關閉並鎖住背包與暫停選單，避免和結算畫面同時出現。
func _close_menus() -> void:
	_pause_menu.allowed = false
	_inventory.allowed = false
	_inventory.close()
	for node in get_tree().get_nodes_in_group(ShopScreen.OVERLAY_GROUP):
		(node as InventoryScreen).allowed = false
		(node as InventoryScreen).close()


func _request_retry() -> void:
	# 持久世界從暫停選單重來：先存下目前的世界（死亡時已經存過，不重複覆蓋以免抵銷頭目回復）。
	if not died:
		_save_area_state(0.0)
	retry_requested.emit()


# ---------------------------------------------------------------------------
# 區域與持久世界
# ---------------------------------------------------------------------------

## 玩家走進／按下出入口：存下這個區域的狀態，請 Main 載入目標區域。
func _on_portal_used(portal: Portal) -> void:
	if _finished or not is_instance_valid(player) or player.is_dead():
		return
	var target := portal.data.target_level
	if not ResourceLoader.exists(target) or not (load(target) is LevelData):
		push_error("[Level] %s 的出入口「%s」目標不是可載入的區域：%s" % [data.id, portal.data.id, target])
		EventBus.toast_requested.emit(portal.data.locked_text)
		return
	_finished = true
	_close_menus()
	_save_area_state(0.0)
	if _persistent:
		GameState.checkpoint_loadout = player.checkpoint_snapshot()
	GameState.pending_portal = portal.data.target_portal
	GameState.carried_health = player.health.current if player.health != null else -1
	area_requested.emit(target)


## 持久世界：把殺掉的敵人、撿走的東西、機關與受傷的頭目存進本輪狀態。
## boss_recovery：受傷的頭目回復其已損血量的比例（死亡時用）。
func _save_area_state(boss_recovery: float) -> void:
	if not _persistent or _area.is_empty():
		return
	_area["world"] = WorldState.capture(get_tree())
	var consumed: Dictionary = _area["consumed"]
	var damage: Dictionary = _area["damage"]
	for key: String in _tracked:
		var node: Variant = _tracked[key]
		var gone: bool = not is_instance_valid(node) or (node as Node).is_queued_for_deletion()
		if not gone and node is Enemy:
			gone = (node as Enemy).is_dying()
		if gone:
			consumed[key] = true
			damage.erase(key)
		elif node is Enemy and (node as Enemy).data.persists_damage:
			var lost := int(round(float((node as Enemy).lost_health()) * (1.0 - boss_recovery)))
			if lost > 0:
				damage[key] = lost
			else:
				damage.erase(key)


## 死亡時（持久世界）：保留世界、頭目回復一部分，扣信用點、帶走現在的裝備。
func _apply_death_to_world(charge_fee := true) -> void:
	if not _persistent:
		return
	_save_area_state(data.death_boss_recovery)
	# 真續玩暫存一般敵人損血；死亡仍沿資料的 persists_damage 規則回復。
	for key: String in _tracked:
		var node: Variant = _tracked[key]
		if is_instance_valid(node) and node is Enemy and not node.data.persists_damage:
			_area["damage"].erase(key)
	if is_instance_valid(player):
		GameState.checkpoint_loadout = player.checkpoint_snapshot()
	if not charge_fee:
		return
	var lost := Progression.lose_credits_fraction(data.death_credit_penalty, data.death_credit_cap)
	if lost > 0:
		EventBus.toast_requested.emit("信用點 -%d" % lost)


func _request_menu() -> void:
	menu_requested.emit()


## 只在保存事件或退出時捕捉，不每影格複製世界。
func run_snapshot() -> Dictionary:
	if not _initialization_complete or not is_instance_valid(player) or _layout == null:
		return {}
	var enemy_ids: Dictionary = {}
	var enemies := _capture_enemies(enemy_ids)
	var encounters := _capture_encounters(enemy_ids)
	var area := _capture_run_area()
	if _persistent and not died:
		_area.merge(area, true)
	return {"position": [player.position.x, player.position.y], "velocity": [player.velocity.x, player.velocity.y],
		"facing": player.facing, "crouching": player.is_crouching, "guard": player.guard,
		"aim_dir": [player.aim_dir.x, player.aim_dir.y],
		"health": player.health.current, "loadout": player.checkpoint_snapshot(), "world": area["world"],
		"area": area, "dead": died, "death_cause": String(_death_cause), "death_entry": _death_entry,
		"ending": _finished and not died, "arena": _arena_triggered, "boss_pending": _arena_triggered and not _boss_spawned,
		"can_continue": _death_can_continue,
		"loose": _capture_loose(), "enemies": enemies, "encounters": encounters,
		"encounter_members_version": ENCOUNTER_SNAPSHOT.MEMBERS_VERSION}


func _capture_run_area() -> Dictionary:
	var result := {"consumed": _area.get("consumed", {}).duplicate(true), "damage": _area.get("damage", {}).duplicate(true), "world": WorldState.capture(get_tree())}
	for key: String in _tracked:
		var node: Variant = _tracked[key]
		var gone := not is_instance_valid(node) or (node as Node).is_queued_for_deletion()
		if not gone and node is Enemy:
			gone = node.is_dying()
		if gone:
			result["consumed"][key] = true
			result["damage"].erase(key)
		elif node is Enemy:
			# 真續玩保留所有敵人目前損血；死亡重建沿原規則。
			result["damage"][key] = node.lost_health()
	return result


func _safe_resume_position(position: Vector2) -> Vector2:
	if _resume_position_valid(position):
		return position
	push_warning("[RunSave] run/runtime/position %s 在%s越界或受阻，退有效起點" % [position, data.resource_path])
	return _checked_checkpoint_position() if _from_checkpoint else _layout.player_start


func _resume_position_valid(position: Vector2) -> bool:
	var body := Rect2(position - Vector2(Player.BODY_SIZE.x * 0.5, Player.BODY_SIZE.y), Player.BODY_SIZE)
	var valid := position.is_finite() and Rect2(Vector2.ZERO, _layout.pixel_size()).encloses(body)
	if valid:
		for solid in _layout.solid_rects:
			if body.intersects(_layout.cells_to_pixels(solid)):
				valid = false
				break
	return valid


## 已結算的死亡只恢復演出／重試，不再次 register_death 或扣款。
func _resume_death() -> void:
	_finished = true
	died = true
	_death_entry = _resume.get("death_entry", {})
	_death_cause = StringName(_resume.get("death_cause", "unknown"))
	_death_can_continue = _resume.get("can_continue", true)
	_close_menus()
	if not _death_entry.is_empty():
		await _run_death_scene(_death_entry)
	else:
		var screen := DeathScreen.new()
		screen.sequence = Story.death_sequence(data.chapter)
		screen.setup(DefeatCodex.unlock(_death_cause), _death_can_continue)
		screen.retry_requested.connect(_request_retry)
		screen.menu_requested.connect(_request_menu)
		add_child(screen)


## 空白／已完成的舊資料維持原流程；真正入隊後被取消則停止後續結算。
func _play_flow_scene(id: StringName, once := true, context: Dictionary = {}) -> bool:
	var expected := Story.has_scene(id) and (not once or not Story.was_seen(id))
	var completed := await Story.play_and_wait(id, once, context)
	return completed or not expected


func _resume_cinematic() -> void:
	_resume_presentation_generation += 1
	var generation := _resume_presentation_generation
	_resumed_presentation_completed = false
	_resumed_presentation_settled = false
	var scene := StringName(_resume["cinematic"])
	var context := Story.presentation_context(_resume.get("cinematic_context", {}))
	var completed := false
	var resumed_owner := false
	if context.get("framing_source", "") in ["person", "object"]:
		for node in get_tree().get_nodes_in_group(&"stateful"):
			if not node is NpcActor or node.state_key() != context.get("source_id", ""):
				continue
			var source := "person" if node.data.kind == NpcData.Kind.PERSON else "object"
			var index: int = context.get("talk_index", -1)
			if source == context["framing_source"] and node.can_resume_presentation(scene, index):
				resumed_owner = true
				completed = await node.resume_presentation(scene, index)
			break
		if not resumed_owner:
			push_warning("[Level] 續玩來源不符，不發放NPC獎勵：%s / %s" % [context.get("source_id", ""), scene])
	if not resumed_owner:
		completed = await Story.play_and_wait(scene, false, context)
	if generation != _resume_presentation_generation:
		return
	_resumed_presentation_completed = completed
	_resumed_presentation_settled = true
	if not is_inside_tree() or not completed:
		return
	if _resume.get("ending", false) or data.complete_after_intro:
		_finished = true
		_close_menus()
		await _run_ending()


## 取消演出只還原物品／世界暫定資料，不套玩家health、state、位置或死亡原因。
func rollback_presentation_world(runtime: Dictionary) -> void:
	_area = GameState.area_state(data.id) if _persistent else runtime.get("area", {}).duplicate(true)
	WorldState.restore(get_tree(), runtime.get("world", {}))
	if is_instance_valid(player):
		var loadout: Dictionary = runtime.get("loadout", {})
		player.loadout.restore(loadout, player.tuning.default_weapon)
		player.consumables.restore(loadout.get("consumables", {}))


func _resume_ending() -> void:
	_finished = true
	_close_menus()
	await _run_ending()


func _resume_pending_boss() -> void:
	if not _initialization_complete or not is_inside_tree():
		return
	await get_tree().process_frame
	if not _initialization_complete or not is_inside_tree():
		return
	if _resume.get("cinematic", "") != "":
		var generation := _resume_presentation_generation
		while not _resumed_presentation_settled and generation == _resume_presentation_generation and is_inside_tree():
			await get_tree().process_frame
		if generation != _resume_presentation_generation or not _resumed_presentation_completed:
			return
	else:
		if not await _play_flow_scene(data.boss_scene):
			return
	if is_inside_tree() and not _finished and not _boss_spawned:
		_spawn_boss()


func _capture_loose() -> Array:
	var result: Array = []
	for node in _entities.get_children():
		if not node is Pickup or node.is_queued_for_deletion() or _tracked.values().has(node):
			continue
		var entry := {"position": [node.position.x, node.position.y]}
		if node is CreditPickup and node.cell == Vector2i(-1, -1) and not node.collected:
			entry.merge({"kind": "credit", "value": node.value})
		elif node is HealthPickup:
			entry["kind"] = "health"
		elif node is WeaponPickup:
			entry.merge({"kind": "weapon", "resource": node.weapon.resource_path})
		elif node is ConsumablePickup:
			entry.merge({"kind": "consumable", "resource": node.item.resource_path})
		else:
			continue
		result.append(entry)
	return result


func _capture_enemies(enemy_ids: Dictionary = {}) -> Array:
	var result: Array = []
	for node in _entities.get_children():
		if not node is Enemy or node.is_dying() or node.is_queued_for_deletion():
			continue
		var key := ""
		for tracked_key: String in _tracked:
			if is_same(_tracked[tracked_key], node):
				key = tracked_key
				break
		var snapshot_id := "enemy:%d" % result.size()
		enemy_ids[node.get_instance_id()] = snapshot_id
		result.append({"snapshot_id": snapshot_id, "key": key, "resource": node.data.resource_path,
			"position": [node.position.x, node.position.y], "lost": node.lost_health()})
	return result


func _capture_encounters(enemy_ids: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node in _entities.get_children():
		if node is EncounterZone and node.state == &"active":
			result[node.state_key()] = {"reinforce": node.get("_reinforce_index"), "time": node.get("_lock_time"),
				"members": node.capture_members(enemy_ids)}
	return result


func _restore_run_entities() -> bool:
	if _resume.get("arena", false) and _layout.arena_x >= 0.0:
		_lock_boss_arena()
		_boss_spawned = not _resume.get("boss_pending", false)
	for entry: Dictionary in _resume.get("loose", []):
		var node: Node2D
		match entry["kind"]:
			"credit":
				node = CreditPickup.new()
				node.value = entry["value"]
			"health": node = HealthPickup.new()
			"weapon", "consumable": node = _create_entity(load(entry["resource"]))
		if node != null:
			node.position = RunSaveCodec.vector(entry["position"])
			_entities.add_child(node)
	var snapshot_enemies: Dictionary = {}
	for entry: Dictionary in _resume.get("enemies", []):
		var node := _tracked.get(entry["key"]) as Enemy if entry["key"] != "" else null
		if node == null and entry["key"] == "":
			node = _create_enemy(load(entry["resource"]) as EnemyData)
			if node != null:
				_entities.add_child(node)
		if node == null and _resume.has("encounter_members_version"):
			push_warning("[Level] run/runtime/enemies/%s/key：%s 無法還原已識別敵人；返回主選單，原存檔保留。" % [entry["snapshot_id"], entry["key"]])
			return false
		if node != null:
			node.position = RunSaveCodec.vector(entry["position"])
			node.restore_lost_health(entry["lost"])
			if _resume.has("encounter_members_version"):
				snapshot_enemies[entry["snapshot_id"]] = node
			if node.has_method(&"set_arena") and _arena_triggered:
				node.call(&"set_arena", Rect2(_layout.arena_x, 0.0, _layout.pixel_size().x - _layout.arena_x - _layout.tile_size, _layout.pixel_size().y))
	for node in _entities.get_children():
		if not node is EncounterZone or not _resume.get("encounters", {}).has(node.state_key()):
			continue
		var entry: Dictionary = _resume["encounters"][node.state_key()]
		node.state = &"active"
		node.set("_reinforce_index", clampi(entry["reinforce"], 0, node.data.reinforcements.size()))
		node.set("_lock_time", minf(entry["time"], node.data.max_lock_seconds))
		var members: Array[WeakRef] = []
		if _resume.has("encounter_members_version"):
			for snapshot_id: String in entry["members"]:
				var enemy := snapshot_enemies.get(snapshot_id) as Enemy
				if enemy == null:
					# Resource/map creation failure must not masquerade as a defeated member.
					push_warning("[Level] run/runtime/encounters/%s/members：%s 無法還原；返回主選單，原存檔保留。" % [node.state_key(), snapshot_id])
					return false
				members.append(weakref(enemy))
		else:
			# Explicit compatibility for valid older snapshots lacking identities.
			for enemy in _entities.get_children():
				if enemy is Enemy and node.call("_zone_world_rect").has_point(enemy.position):
					members.append(weakref(enemy))
		node.set("_members", members)
		node.set_physics_process(true)
	return true


## 頭目戰閘門外觀。
class _GateVisual:
	extends Node2D

	var size := Vector2(16, 368)
	var _time := 0.0

	func _ready() -> void:
		LightKit.mark_emissive(self)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.TERRAIN_FILL)
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y + 8), Palette.TERRAIN_EDGE, 2.0)
			y += 12.0
		var glow := LightKit.glow(Palette.DANGER, 1.5 + 0.5 * sin(_time * 6.0))
		draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), glow, 2.0)


## 燈頭上最近的天花板底面（世界 y）：往上 LAMP_CEILING_REACH 格內有實心地形才算；沒有回傳 INF。
func _lamp_ceiling(tile: int, row: int) -> float:
	for step in range(1, LAMP_CEILING_REACH + 1):
		if _layout.cell(tile, row - step) == LevelBuilder.SOLID:
			return float((row - step + 1) * _layout.tile_size)
	return INF


## 這盞燈周圍能用的安裝方式：頭上有天花板、背後有牆、腳下不遠處有地面。
func _lamp_supports(lamp: Lamp, walls: BackWallGeometry) -> Dictionary:
	var drop := lamp.floor_y - lamp.position.y
	var on_wall := walls != null and walls.covers(Rect2(lamp.position - Vector2(8.0, 8.0), Vector2(16.0, 16.0)))
	lamp.wall_behind = on_wall
	return {&"ceiling": lamp.ceiling_y != INF, &"wall": on_wall,
		&"pole": lamp.floor_y != INF and drop <= LAMP_POLE_MAX, &"ground": lamp.floor_y != INF and drop <= LAMP_POLE_MAX}
