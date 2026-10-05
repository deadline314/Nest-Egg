class_name Level
extends Node2D
## 關卡場景：依 LevelData 建立地形、實體、玩家、鏡頭與 UI，並處理頭目戰、死亡與過關流程。
## 關卡本身不保存進度（交給 GameState），重來時直接重建整個 Level，保證狀態乾淨、不殘留記憶體。

signal retry_requested
signal menu_requested
signal completed
## 玩家穿過出入口：請 Main 載入目標區域（路徑是 LevelData 的 .tres）。
signal area_requested(level_path: String)

const PLAYER_TUNING_PATH := "res://data/player/player_tuning.tres"
const DEATH_SCREEN_DELAY := 1.1
const VICTORY_DELAY := 2.8
const BOSS_SPAWN_DELAY := 0.8
## 進入戰場左界多少像素後觸發頭目戰。
const ARENA_TRIGGER_MARGIN := 40.0
const FALL_LIMIT_MARGIN := 48.0
const BOSS_LIGHTING_ID := &"boss"
const BOSS_LIGHTING_FADE := 1.5
## 重生後多久播出「死亡次數的反應」通訊（等轉場揭開、玩家看清楚畫面）。
const RESPAWN_REACTION_DELAY := 1.2

var data: LevelData
var player: Player
var camera: LevelCamera
var hud: Hud
## 玩家死亡後為 true（Main 據此選擇重來的轉場）。
var died := false

var _layout: LevelLayout
var _world: Node2D
var _entities: Node2D
var _pause_menu: PauseMenu
var _inventory: InventoryScreen
var _background: LevelBackground
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
## 生成格鍵 -> 節點（敵人與拾取物；離開或死亡時據此判斷誰被消滅或撿走，節點可能已被釋放，所以不用型別字典）。
var _tracked: Dictionary = {}
var _portals: Dictionary[StringName, Portal] = {}


func configure(p_data: LevelData) -> void:
	data = p_data


func _ready() -> void:
	_layout = LevelBuilder.parse(data)
	if not _layout.is_valid():
		push_error("[Level] 關卡資料無效，返回主選單。")
		menu_requested.emit.call_deferred()
		return

	_persistent = data.persistent_world
	GameState.current_level_path = data.resource_path
	_entry_portal = GameState.take_pending_portal()
	_from_checkpoint = _entry_portal == &"" and GameState.checkpoint_applies(data.resource_path)
	if _persistent:
		_area = GameState.area_state(data.id)
	# 成長進度（信用點、改裝）：從檢查點重生就還原成檢查點當下，否則還原成進入關卡時；要在玩家（武器欄）建立之前。
	# 持久世界不回溯：成長一直往前累積（死亡只扣信用點）。
	if not _persistent:
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

	var scenery_start := _world.get_child_count()
	_spawn_decor()
	_lower_scenery(scenery_start, WorldLayers.DECOR)
	scenery_start = _world.get_child_count()
	_spawn_props()
	_lower_scenery(scenery_start, WorldLayers.PROPS)

	var terrain := Terrain.new()
	terrain.name = "Terrain"
	terrain.z_index = WorldLayers.TERRAIN
	_world.add_child(terrain)
	terrain.build(_layout, data.environment, data.load_regions())
	if not _layout.ghost_rects.is_empty():
		var ghosts := GhostPlatforms.new()
		ghosts.name = "GhostPlatforms"
		_world.add_child(ghosts)
		ghosts.build(_layout)

	_entities = Node2D.new()
	_entities.name = "Entities"
	_world.add_child(_entities)

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
	add_child(_foreground)

	hud = Hud.new()
	add_child(hud)

	_power_grid = PowerGrid.new()
	_power_grid.name = "PowerGrid"
	_power_grid.tile_size = _layout.tile_size
	add_child(_power_grid)
	_power_grid.zone_changed.connect(func(_zone: StringName, _powered: bool) -> void: _rebuild_lighting_events())

	_spawn_static_entities()
	_spawn_player()
	# 從檢查點重生：還原被打破的箱子、開關、閘門與電力（要在光影設定之前，事件才會正確）。
	WorldState.restore(get_tree(), _area.get("world", {}) if _persistent else GameState.checkpoint_world)
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
	AssetPrefetch.warm_neighbors.call_deferred(data)
	_begin_intro.call_deferred()
	_begin_death_reactions.call_deferred()


func _process(delta: float) -> void:
	if not _finished and is_instance_valid(player) and not player.is_dead():
		GameState.run_time += delta


func _physics_process(_delta: float) -> void:
	if _layout == null or not is_instance_valid(player):
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
		await Story.play_and_wait(data.intro_scene)
		if not is_inside_tree():
			return
	if _entry_portal != &"":
		# 穿過出入口進來：只標示區域名稱，不重播章節標題。
		if data.announce_area and not data.display_name.is_empty():
			EventBus.toast_requested.emit(data.display_name)
	elif data.show_chapter_card:
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


## 死亡重生後：累計死亡達到次數時，播出這一章設定的反應通訊（見 StoryReactions）。只改措辭，不影響流程與難度。
func _begin_death_reactions() -> void:
	if not GameState.consume_respawn() or not is_inside_tree():
		return
	await get_tree().create_timer(RESPAWN_REACTION_DELAY, false).timeout
	if is_inside_tree():
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
		var pickup := HealthPickup.new()
		pickup.position = pos
		_entities.add_child(pickup)
	for i in _layout.lamps.size():
		var lamp := Lamp.new()
		lamp.position = _layout.lamps[i] + Vector2(0, 2)
		# 風格由所在區段決定；沒有區段時維持霓虹三原色交錯。
		var tile := int(lamp.position.x / _layout.tile_size)
		lamp.floor_y = _layout.floor_below(tile, int(lamp.position.y / _layout.tile_size))
		var profile := data.profile_at_tile(tile)
		if profile != null and profile.lamp_style != null:
			lamp.apply_style(profile.lamp_style, hash(Vector2i(tile, int(lamp.position.y))))
		else:
			lamp.color = [Palette.CYAN, Palette.MAGENTA, Palette.NEON_YELLOW][i % 3]
		_world.add_child(lamp)
	for hint in _layout.hints:
		var sign := HintSign.new()
		sign.text = str(hint["text"])
		sign.position = hint["position"]
		_entities.add_child(sign)
	for spawn in _layout.spawns:
		var resource: Resource = spawn["resource"]
		var key := _spawn_key(spawn)
		var trackable := _persistent and (resource is EnemyData or resource is WeaponData or resource is ConsumableData)
		if trackable and (_area["consumed"] as Dictionary).has(key):
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
				var lost: int = int((_area["damage"] as Dictionary).get(key, 0))
				if lost > 0 and node is Enemy:
					(node as Enemy).restore_lost_health(lost)


## 招牌、看板、排氣孔等裝飾（畫在地形與角色之後方）。
## 把剛生成的靜態場景節點（還在預設圖層的）排到所有角色零件之下；已經有自己圖層的（前景道具）不動。
func _lower_scenery(from_child: int, z: int) -> void:
	for i in range(from_child, _world.get_child_count()):
		var node := _world.get_child(i) as CanvasItem
		if node != null and node.z_index == 0:
			node.z_index = z


func _spawn_decor() -> void:
	for entry in _layout.decor:
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
	for entry in data.load_props():
		var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
		if prop == null:
			continue
		var placed := PropPlacement.resolve(entry, prop, _layout)
		if placed.is_empty():
			push_warning("[Level] 道具 %s 第 %d 欄下方沒有地表，已略過" % [prop.id, int(entry["x"])])
			continue
		var rect: Rect2 = placed["rect"]
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
	return null


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
	player.configure(tuning, GameState.difficulty.player_max_health, GameState.checkpoint_loadout)
	player.position = _entry_position()
	player.fall_limit_y = _fall_limit()
	_entities.add_child(player)
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
		return GameState.checkpoint_position
	return _layout.player_start


func _fall_limit() -> float:
	return _layout.pixel_size().y + FALL_LIMIT_MARGIN


# ---------------------------------------------------------------------------
# 頭目戰
# ---------------------------------------------------------------------------

func _start_boss_fight() -> void:
	_arena_triggered = true
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
	if data.boss_lighting != null:
		EventBus.lighting_override_requested.emit(BOSS_LIGHTING_ID, data.boss_lighting, BOSS_LIGHTING_FADE)
	Feel.play(&"boss_arena_lock")
	EventBus.toast_requested.emit("警告：偵測到大型反應")
	if _layout.boss_spawn.is_empty():
		push_warning("[Level] 有戰場標記 B 但沒有頭目")
		return
	await get_tree().create_timer(BOSS_SPAWN_DELAY, false).timeout
	if not is_inside_tree():
		return
	await Story.play_and_wait(data.boss_scene)
	if is_inside_tree():
		_spawn_boss()


func _spawn_boss() -> void:
	if not is_inside_tree() or _layout.boss_spawn.is_empty():
		return
	var boss := _create_enemy(_layout.boss_spawn["resource"])
	if boss == null:
		return
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
	_apply_death_to_world()
	await get_tree().create_timer(DEATH_SCREEN_DELAY, false).timeout
	if not is_inside_tree():
		return
	var screen := DeathScreen.new()
	screen.setup(card, can_continue)
	screen.retry_requested.connect(_request_retry)
	screen.menu_requested.connect(_request_menu)
	add_child(screen)


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
	await Story.play_and_wait(data.outro_scene)
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
func _apply_death_to_world() -> void:
	if not _persistent:
		return
	_save_area_state(data.death_boss_recovery)
	if is_instance_valid(player):
		GameState.checkpoint_loadout = player.checkpoint_snapshot()
	var lost := Progression.lose_credits_fraction(data.death_credit_penalty)
	if lost > 0:
		EventBus.toast_requested.emit("信用點 -%d" % lost)


func _request_menu() -> void:
	menu_requested.emit()


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
