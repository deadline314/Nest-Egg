class_name JanusBoss
extends PatternBoss
## 第三章頭目「守門人 JANUS」（M5c 門禁大廳，NE-271）：約六十歲的用盡者被外接的門禁工作架困住，工作架一直把拒絕通行當命令。
## 玩家只打得動工作架的外部部件（盾架、掃描臂鎖、背上的通訊器）；人物本身是保護區，子彈與近戰打到他都會被擋下、沒有傷害。
## 血條是「門禁裝置穩定度」，歸零後工作架停住，要到他背後拔維修插銷才算停機（啟動機關頻道，門禁大廳寫入停機旗標）。
##
## 核心機制「遺忘迴圈」：有效部件受擊時，守門人有時忘了流程，下一招重複上一招（頭上出現問號、機臺顯示程式重播）；
## 重播一樣有完整預兆，連續重播不超過 replay_max 次。
## 招式（資料 data/bosses/janus.json 的 custom_kinds，這個類別實作）：
##   shield_bash  抬盾 1.0 秒、地上畫出前方扇區，往前推撞；撲空（閃開或格擋）時盾鎖露出，有效盾擊撲空 crack_misses 次後盾架裂開
##   scan_sweep   掃描臂 0.8 秒畫出一條水平線（低線跳過、高線蹲過）再往外掃；蓄力時近戰打橙色臂鎖會中斷，繞到背後也能用子彈打斷
##   call_backup  背上的通訊器閃 0.8 秒後叫來一台巡檢器（最多 max_backup 台、含頭目同屏最多 max_alive 個）；打壞通訊器就不再增援
## 工作架很重，轉身要 turn_delay 秒：撲空或被打斷後繞到背後，就是打通訊器與臂鎖的空檔。
## 盾裂、通訊器壞、剩餘穩定度存在故事旗標（重試、死亡與續玩都保留，不重抽已破的部件）；持久世界的損血不另外套用。
## 外觀：人物用既有的守門人骨架（art/characters/janus）；外接工作架目前是程式繪製的暫代（角色美術交付後換成零件圖，只改資料）。

const CONFIG_KEY := "gatekeeper"
const SHIELD := &"shield"
const SHIELD_LOCK := &"shield_lock"
const ARM_LOCK := &"arm_lock"
const COMM := &"comm"
## 工作架停住後，玩家要站在插銷多近才拔得到。
const PIN_REACH := Vector2(30.0, 40.0)
const FADE_TIME := 1.2
const QUESTION_TIME := 1.6

## 從 janus.json 的 gatekeeper 段讀的設定（缺欄位時用這裡的預設）。
const DEFAULTS := {
	"wake_flag": "ch3_janus_intro_seen", "disabled_flag": "ch3_janus_disabled",
	"misses_flag": "ch3_janus_shield_misses", "comm_flag": "ch3_janus_comm_broken",
	"stability_flag": "ch3_janus_device_stability", "lost_flag": "ch3_janus_lost_once",
	"bark_sorry": "ch3_c11_bark_sorry", "bark_repeat": "ch3_c11_bark_repeat", "defeat_hint": "ch3_c11_defeat_hint",
	"turn_delay": 0.8, "replay_chance": 0.3, "replay_max": 2, "seed": 271,
	"crack_misses": 3, "comm_hits": 6, "pin_offset": [-12.0, -22.0],
}

static var _config_cache: Dictionary = {}

var config: Dictionary = {}
var shield_misses := 0
var shield_cracked := false
var comm_broken := false
var halted := false
var pin_pulled := false

var _rng := RandomNumberGenerator.new()
var _replay_pending := false
var _replay_chain := 0
var _replaying := false
var _rolled_this_move := false
var _question_left := 0.0
var _turn_wait := 0.0
var _comm_hits := 0
var _whiff := false
var _bash_effective := false
var _bash_from := 0.0
## 這次盾擊碰到玩家了（打中或被格擋）：停下，不推進玩家身體裡。
var _bash_contact := false
var _scan_extent := 0.0
var _scan_height := 0.0
var _backups: Array[WeakRef] = []
var _strike: BossStrikeArea
var _pin_prompt: WorldPrompt
var _hinted_block := false
var _restoring := true
var _comm_exposed := false
var _last_stability := -1


func _setup_states() -> void:
	config = _load_config(data.id)
	_rng.seed = int(config["seed"])
	super._setup_states()
	fsm.add(&"halted", _halted_tick)
	_strike = BossStrikeArea.new()
	_strike.name = "Strike"
	add_child(_strike)
	_strike.setup(Combat.Team.ENEMY, &"janus_shield_bash")
	_strike.struck.connect(func(_result: Hurtbox.Result) -> void: _bash_contact = true)
	for id: StringName in _parts_by_id:
		_parts_by_id[id].hit_received.connect(_on_janus_part_hit.bind(id))
	EventBus.player_died.connect(_on_player_died)
	health.health_changed.connect(_on_stability_changed)
	_restore_from_flags()
	_restoring = false


static func _load_config(id: StringName) -> Dictionary:
	var key := String(id)
	if _config_cache.has(key):
		return _config_cache[key]
	var merged := DEFAULTS.duplicate(true)
	var path := BossPattern.DIR % key
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var section: Variant = (parsed as Dictionary).get(CONFIG_KEY, {}) if parsed is Dictionary else {}
	if section is Dictionary:
		for field: String in section:
			if merged.has(field) and typeof(section[field]) in [typeof(merged[field]), TYPE_FLOAT, TYPE_INT]:
				merged[field] = section[field]
			else:
				push_error("[JanusBoss] %s 的 %s.%s 不認得或型別不對，改用預設" % [path, CONFIG_KEY, field])
	else:
		push_error("[JanusBoss] %s 的 %s 不是物件，全部用預設" % [path, CONFIG_KEY])
	_config_cache[key] = merged
	return merged


## 讀回故事旗標：已停機就不再出現；盾裂、通訊器壞、剩餘穩定度照舊；穩定度 0 但還沒拔插銷就直接停住等拔。
func _restore_from_flags() -> void:
	if GameState.has_flag(_flag("disabled_flag")):
		queue_free()
		return
	shield_misses = clampi(int(GameState.get_flag(_flag("misses_flag"), 0)), 0, int(config["crack_misses"]))
	shield_cracked = shield_misses >= int(config["crack_misses"])
	comm_broken = GameState.has_flag(_flag("comm_flag"))
	var stability: Variant = GameState.get_flag(_flag("stability_flag"), null)
	if stability != null:
		var percent := clampi(int(stability), 0, 100)
		health.current = ceili(health.max_health * percent / 100.0)
		if percent == 0:
			health.is_dead = true
			_halt.call_deferred(false)
		else:
			_apply_phase(pattern.phase_for(_health_ratio()), false)
	_refresh_parts()


## 剩餘穩定度（百分比）寫進故事旗標；每跨過一成才要求存檔，不每發子彈都存。
func _on_stability_changed(current: int, maximum: int) -> void:
	if _restoring:
		return
	var percent := ceili(100.0 * current / float(maxi(1, maximum)))
	GameState.set_flag(_flag("stability_flag"), percent, _last_stability < 0 or percent / 10 != _last_stability / 10)
	_last_stability = percent


func _flag(key: String) -> StringName:
	return StringName(str(config[key]))


## 持久世界的損血不用：剩餘穩定度只存在故事旗標，免得重複扣。
func restore_lost_health(_lost: int) -> void:
	pass


func _implements_kind(kind: StringName) -> bool:
	return kind in [&"shield_bash", &"scan_sweep", &"call_backup"]


# ---------------------------------------------------------------------------
# 醒來、轉身、遺忘迴圈
# ---------------------------------------------------------------------------

## 登場劇情（C10）看過、玩家走進大廳才醒；第一次輸給他之後，再見到時播一次敗北提示。
func _dormant_tick(delta: float) -> void:
	if halted:
		return
	if GameState.has_flag(_flag("wake_flag")):
		super._dormant_tick(delta)


func _wake() -> void:
	if _awake or halted:
		return
	super._wake()
	if GameState.has_flag(_flag("lost_flag")):
		Story.play(_flag("defeat_hint"))


func _on_player_died(_cause: StringName) -> void:
	if _awake and not halted and is_inside_tree():
		GameState.set_flag(_flag("lost_flag"), true)


## 工作架很重：玩家跑到背後要 turn_delay 秒才轉過來；預兆與出招中不轉（招式方向在預兆開始就決定）。
func _face_target() -> void:
	var target := _target()
	if target == null or halted:
		return
	var side := 1 if target.global_position.x >= global_position.x else -1
	if side == facing:
		_turn_wait = 0.0
		return
	if fsm.is_in(&"windup") or fsm.is_in(&"act") or fsm.is_in(&"yanked"):
		return
	_turn_wait += get_physics_process_delta_time()
	if _turn_wait >= float(config["turn_delay"]) or fsm.is_in(&"intro"):
		facing = side
		_turn_wait = 0.0


func is_target_in_front() -> bool:
	var target := _target()
	return target != null and signf(target.global_position.x - global_position.x) == float(facing)


## 遺忘迴圈：有重播等著就重複上一招（同樣完整預兆），連續不超過 replay_max 次；否則照攻擊習慣選。
func choose_move() -> StringName:
	_rolled_this_move = false
	if _replay_pending and _last_move != &"" and _replay_chain < int(config["replay_max"]) \
			and (current_phase()["moves"] as Array).has(_last_move) and _move_usable(_last_move):
		_replay_pending = false
		_replay_chain += 1
		_replaying = true
		_question_left = QUESTION_TIME
		if not Story.was_seen(_flag("bark_repeat")):
			Story.play(_flag("bark_repeat"))
		return _last_move
	_replay_pending = false
	_replay_chain = 0
	_replaying = false
	return super.choose_move()


func is_replaying() -> bool:
	return _replaying


func replay_pending() -> bool:
	return _replay_pending


## 有效部件受擊：每一招最多擲一次（約三成）決定下一招要不要重播；通訊器另外累計耐久。
func _on_janus_part_hit(_info: DamageInfo, id: StringName) -> void:
	if halted:
		return
	if not _rolled_this_move and not _replay_pending and _last_move != &"":
		_rolled_this_move = true
		_replay_pending = _rng.randf() < float(config["replay_chance"])
	if id == COMM and not comm_broken:
		_comm_hits += 1
		if _comm_hits >= int(config["comm_hits"]):
			_break_comm()


# ---------------------------------------------------------------------------
# 部件：盾架、盾鎖、掃描臂鎖、通訊器
# ---------------------------------------------------------------------------

## 框架依資料決定的開關之外，守門人自己的規則：盾架裂開前擋子彈、裂開後打得動；盾鎖只在盾擊撲空的硬直露出；
## 通訊器只有玩家在他背後時打得到（正面的子彈會先碰到人物，被擋下），壞了就不在了。
## 格擋回呼只用在「整個擋下」的部位：近戰只會挑沒有格擋回呼的部位（裂開的盾、露出的盾鎖、蓄力中的臂鎖、背後的通訊器）。
func _refresh_parts() -> void:
	super._refresh_parts()
	if _parts_by_id.is_empty():
		return
	_comm_exposed = _player_behind()
	_set_part(SHIELD, shield_cracked, true, Callable() if shield_cracked else _armored_part_guard)
	_set_part(SHIELD_LOCK, _staggered and _whiff, _staggered and _whiff, Callable())
	_set_part(COMM, not comm_broken and _comm_exposed, not comm_broken, Callable() if _comm_exposed else _armored_part_guard)


func _set_part(id: StringName, open: bool, enabled: bool, guard: Callable) -> void:
	var part: Hurtbox = _parts_by_id.get(id)
	if part == null:
		return
	part.enabled = enabled and not halted
	part.guard = guard
	_part_open[id] = open and not halted


## 玩家在工作架背後（面向的反方向）。
func _player_behind() -> bool:
	var target := _target()
	return target != null and signf(target.global_position.x - global_position.x) == -float(facing)


## 臂鎖的打斷：正面射來的子彈有傷害但打不斷（臂鎖正面有護罩），近戰或從背後打才算；其餘照框架的打斷規則。
func _on_part_hit(info: DamageInfo) -> void:
	if info.part == ARM_LOCK and info.is_projectile and _hit_from_front(info):
		return
	super._on_part_hit(info)


## 部位判定沒有骨頭時，位置依面向左右翻（資料的 offset 以面向右為準）。
func _update_hurt_parts() -> void:
	super._update_hurt_parts()
	for entry in _parts:
		if entry["bone"] == &"":
			var offset: Vector2 = entry["offset"]
			hurtbox.move_part(entry["box"], Vector2(offset.x * facing, offset.y))


func _crack_shield() -> void:
	shield_cracked = true
	Fx.sparks(_part_point(SHIELD), Palette.WARNING, 14, 200.0, 0.4, Vector2(facing, -0.5), 1.4)
	Sfx.play(&"block", 0.0, 0.0, 0, 0.7)
	Feel.shake_strength(4.0, 0.25)
	EventBus.toast_requested.emit("盾架裂開了——正面也打得動了")
	_refresh_parts()


func _break_comm() -> void:
	comm_broken = true
	GameState.set_flag(_flag("comm_flag"), true)
	Fx.sparks(_part_point(COMM), Palette.CYAN, 16, 220.0, 0.45, Vector2(-facing, -0.6), 1.6)
	Fx.flash_light(_part_point(COMM), Palette.CYAN, 90.0, 1.5, 0.25)
	Sfx.play(&"explosion_small", -4.0)
	EventBus.toast_requested.emit("通訊器壞了，不會再叫增援")
	if fsm.is_in(&"windup") and StringName(_move().get("kind", &"")) == &"call_backup":
		fsm.transition(&"recover")
	_refresh_parts()


func _part_point(id: StringName) -> Vector2:
	var part: Hurtbox = _parts_by_id.get(id)
	return part.center() if part != null else _center()


## 人物是保護區：子彈與近戰打到他只會被擋下（灰色火花），第一次附一句提示。
func _on_blocked(info: DamageInfo) -> void:
	_armor_hinted = true  # 框架的「裝甲擋下」提示換成守門人自己的
	super._on_blocked(info)
	var at := info.contact_point if info.contact_point.is_finite() else _center()
	Fx.sparks(at, Color(0.7, 0.72, 0.76), 3, 90.0, 0.15, Vector2(-facing, -0.3))
	if not _hinted_block:
		_hinted_block = true
		EventBus.toast_requested.emit("人物是保護區——只打橙色的外部部件")


# ---------------------------------------------------------------------------
# 招式
# ---------------------------------------------------------------------------

func _custom_move_usable(id: StringName, kind: StringName) -> bool:
	var target := _target()
	if target == null:
		return false
	var params: Dictionary = pattern.moves[id].get("params", {})
	var dx := absf(target.global_position.x - global_position.x)
	var dy := absf(target.global_position.y - global_position.y)
	match kind:
		&"shield_bash":
			return is_target_in_front() and dy < 48.0 and dx <= float(params.get("front_range", 140.0))
		&"scan_sweep":
			return is_target_in_front() and dy < 72.0 and dx <= float(params.get("reach", 170.0)) * 1.15
		&"call_backup":
			return not comm_broken and _living_backups() < int(params.get("max_backup", 2)) \
					and _living_backups() + 1 < int(params.get("max_alive", 3))
	return false


func _custom_windup_enter(kind: StringName) -> void:
	match kind:
		&"shield_bash":
			_bash_effective = is_target_in_front()
			Sfx.play(&"block", -6.0, 0.0, 0, 0.8)
		&"scan_sweep":
			_scan_height = _param("height", 8.0)
			_scan_extent = 0.0
			Sfx.play(&"beep", -8.0)
		&"call_backup":
			Sfx.play(&"beep", -6.0, 0.0, 0, 1.3)


func _custom_act_enter(kind: StringName) -> void:
	match kind:
		&"shield_bash":
			_bash_from = global_position.x
			_bash_contact = false
			_strike.source_id = &"janus_shield_bash"
			_strike.arm(int(_param("damage", 2)), Vector2(14, 40), Vector2(facing * (data.body_size.x * 0.5 + 6.0), -22))
			velocity.x = facing * _param("speed", 320.0) * _speed()
			Fx.dust(global_position, 8, 90.0)
			Sfx.play(&"dash", -4.0)
		&"scan_sweep":
			_scan_extent = 0.0
			_strike.source_id = &"janus_scan"
			_strike.arm(int(_param("damage", 1)), Vector2(1, 6), _scan_center(0.0))
			Sfx.play(&"zap", -6.0)
		&"call_backup":
			_call_backup()


func _custom_act_tick(kind: StringName, delta: float) -> void:
	match kind:
		&"shield_bash":
			_bash_tick(delta)
		&"scan_sweep":
			_scan_tick()
		_:
			fsm.transition(&"recover")


## 盾擊：往前推 distance 像素（撞牆或逾時就停）。沒打中玩家（閃開或格擋）就是撲空：盾鎖露出硬直，
## 有效盾擊（預兆開始時玩家在正面）的撲空次數存進旗標，滿 crack_misses 次盾架裂開。
func _bash_tick(delta: float) -> void:
	var travelled := absf(global_position.x - _bash_from)
	var distance := _param("distance", 80.0)
	_strike.reshape(Vector2(14, 40), Vector2(facing * (data.body_size.x * 0.5 + 6.0), -22))
	if travelled < distance and not _bash_contact and not is_on_wall() and fsm.time_in_state < 1.0:
		velocity.x = facing * minf(_param("speed", 320.0) * _speed(), (distance - travelled) / maxf(delta, 0.0001))
		return
	velocity.x = 0.0
	var landed := _strike.landed()
	_strike.disarm()
	if landed:
		fsm.transition(&"recover")
		return
	if _bash_effective and not shield_cracked:
		shield_misses = mini(shield_misses + 1, int(config["crack_misses"]))
		GameState.set_flag(_flag("misses_flag"), shield_misses)
		if shield_misses >= int(config["crack_misses"]):
			_crack_shield()
	_whiff = true
	Fx.sparks(_part_point(SHIELD_LOCK), Palette.WARNING, 6, 120.0, 0.25, Vector2(0, -1))
	fsm.transition(&"yanked")


## 掃描：一條固定高度的線從臂端往外延伸到 reach（sweep_time 秒），碰到牆就停。
func _scan_tick() -> void:
	var sweep := maxf(0.05, _param("sweep_time", 0.35) / _speed())
	var t := clampf(fsm.time_in_state / sweep, 0.0, 1.0)
	_scan_extent = _param("reach", 170.0) * t
	_strike.reshape(Vector2(maxf(1.0, _scan_extent), 6.0), _scan_center(_scan_extent))
	if fsm.time_in_state >= sweep + 0.08:
		_strike.disarm()
		fsm.transition(&"recover")


## 掃描線的判定中心（本地座標）：從身體前緣往外 extent，高度是離地 _scan_height。
func _scan_center(extent: float) -> Vector2:
	return Vector2(facing * (data.body_size.x * 0.5 + extent * 0.5), -_scan_height)


func _call_backup() -> void:
	var params := _params()
	var path := str(params.get("enemy", ""))
	var enemy_data := load(path) as EnemyData if ResourceLoader.exists(path) else null
	if enemy_data == null or enemy_data.behavior == null:
		push_error("[JanusBoss] %s 的增援資料讀不到：%s" % [data.id, path])
		return
	var offsets: Array = params.get("spawn_offsets", [-280.0, 280.0])
	var target := _target()
	# 從離玩家遠的那一側進場，不在玩家身上生成。
	var best := 0.0
	for offset: Variant in offsets:
		var x := _anchor.x + float(offset)
		if target == null or absf(x - target.global_position.x) > absf(_anchor.x + best - target.global_position.x) or best == 0.0:
			best = float(offset)
	var enemy := enemy_data.behavior.new() as Enemy
	if enemy == null:
		push_error("[JanusBoss] %s 的增援 behavior 不是 Enemy：%s" % [data.id, path])
		return
	enemy.configure(enemy_data)
	enemy.position = _floor_at(Vector2(_anchor.x + best, global_position.y - 8.0))
	get_parent().add_child(enemy)
	_backups.append(weakref(enemy))
	Fx.flash_light(enemy.global_position + Vector2(0, -16), Palette.WARNING, 110.0, 1.4, 0.35)
	Fx.flash_light(_part_point(COMM), Palette.WARNING, 70.0, 1.6, 0.2)


func _living_backups() -> int:
	var count := 0
	for ref in _backups:
		var enemy := ref.get_ref() as Enemy
		if enemy != null and enemy.is_inside_tree() and not enemy.is_dying():
			count += 1
	return count


## 打斷（臂鎖）與撲空的硬直：第一次被打斷時他會道歉一次。
func _yanked_enter() -> void:
	if _interrupted and not Story.was_seen(_flag("bark_sorry")):
		Story.play(_flag("bark_sorry"))
	_strike.disarm()
	super._yanked_enter()


func _yanked_exit() -> void:
	_whiff = false
	super._yanked_exit()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _dying or pattern == null:
		return
	_question_left = maxf(0.0, _question_left - delta)
	if _comm_exposed != _player_behind():
		_refresh_parts()
	if _strike != null and _strike.is_armed() and not fsm.is_in(&"act"):
		_strike.disarm()


# ---------------------------------------------------------------------------
# 停機：穩定度歸零 → 工作架停住 → 拔維修插銷
# ---------------------------------------------------------------------------

## 穩定度歸零不是死亡：人物活著，工作架停住等玩家拔插銷；不掉錢（停機報酬一百由劇情的停機回執結算）。
func _on_died(_info: DamageInfo) -> void:
	_halt(true)


func _halt(perform: bool) -> void:
	if halted or not is_inside_tree():
		return
	halted = true
	velocity = Vector2.ZERO
	AttackTokens.enemy_release(self)
	if _strike != null:
		_strike.disarm()
	if contact != null:
		contact.active = false
	_telegraph_left = 0.0
	GameState.set_flag(_flag("stability_flag"), 0)
	if fsm.current == &"":
		fsm.start(&"halted")
	else:
		fsm.transition(&"halted")
	_refresh_parts()
	_pin_prompt = WorldPrompt.new()
	_pin_prompt.text = "{interact} 拔維修插銷"
	_pin_prompt.radius = PIN_REACH.x + 8.0
	# 提示放在他頭頂上方：插銷就在背後，放在插銷旁會和站在那裡的主角重疊、被擠到旁邊。
	_pin_prompt.offset = Vector2(0, -data.body_size.y - 22.0)
	_pin_prompt.reach_check = pin_reachable
	add_child(_pin_prompt)
	if perform:
		EventBus.boss_health_changed.emit(0, health.max_health)
		Fx.sparks(_center(), Palette.CYAN, 12, 160.0, 0.4, Vector2(0, -1))
		Sfx.play(&"gate", -4.0)
		EventBus.toast_requested.emit("工作架停住了——到他背後拔維修插銷")


func _halted_tick(_delta: float) -> void:
	velocity.x = 0.0
	if pin_pulled or get_tree().paused or GameplayLock.is_locked():
		return
	if Input.is_action_just_pressed(&"interact") and pin_reachable():
		pull_pin()


## 玩家在插銷旁邊（工作架背後）而且活著。
func pin_reachable() -> bool:
	if not halted or pin_pulled:
		return false
	var player := _target() as Player
	if player == null or player.is_dead():
		return false
	var offset := player.global_position - (global_position + _pin_local())
	return absf(offset.x) <= PIN_REACH.x and absf(offset.y) <= PIN_REACH.y


func _pin_local() -> Vector2:
	var at: Array = config["pin_offset"]
	return Vector2(float(at[0]) * facing, float(at[1]))


## 拔插銷：工作架斷電、閘門退開（機關頻道），守門人慢慢淡出、由櫃檯旁坐著的他接手（劇情 C12）。
func pull_pin() -> void:
	if pin_pulled or not halted:
		return
	pin_pulled = true
	if _pin_prompt != null:
		_pin_prompt.queue_free()
	Fx.sparks(global_position + _pin_local(), Palette.CYAN, 10, 140.0, 0.3, Vector2(-facing, -0.4))
	Sfx.play(&"gate", -2.0)
	Feel.play(&"boss_death")
	EventBus.boss_bar_closed.emit()
	EventBus.mechanism_toggled.emit(pattern.gate_channel, true)
	if not pattern.unlock_text.is_empty():
		EventBus.toast_requested.emit(pattern.unlock_text)
	var tween := create_tween()
	tween.tween_interval(0.4)
	tween.tween_property(self, ^"modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)


# ---------------------------------------------------------------------------
# 畫面：外接工作架（暫代）與預兆
# ---------------------------------------------------------------------------

func _draw_custom() -> void:
	var f := float(facing)
	var steel := Color(0.36, 0.39, 0.45)
	var dark := Color(0.13, 0.14, 0.17)
	var power := 0.0 if halted else 1.0
	# 支撐架：背後一根立柱與兩道箍帶（人物在裡面）。
	draw_line(Vector2(-f * 13.0, 0), Vector2(-f * 13.0, -62), dark, 3.0)
	draw_line(Vector2(-f * 13.0, -62), Vector2(f * 4.0, -62), dark, 2.0)
	for y: float in [-44.0, -24.0]:
		draw_line(Vector2(-f * 13.0, y), Vector2(f * 8.0, y), Color(steel, 0.85), 1.5)
	# 通訊器（背後）：箱子、天線與狀態燈；呼叫預兆時閃橙色，壞了就黑掉冒火花。
	var comm := _part_offset(COMM)
	if comm_broken:
		draw_rect(Rect2(comm + Vector2(-5, -7), Vector2(10, 14)), dark)
		draw_line(comm + Vector2(0, -7), comm + Vector2(-f * 5.0, -13), dark, 1.0)
	else:
		draw_rect(Rect2(comm + Vector2(-5, -7), Vector2(10, 14)), steel.darkened(0.2))
		draw_line(comm + Vector2(0, -7), comm + Vector2(0, -16), steel, 1.0)
		var calling := fsm.is_in(&"windup") and StringName(_move().get("kind", &"")) == &"call_backup"
		var blink := calling and int(_anim_time * 10.0) % 2 == 0
		var lamp := LightKit.glow(Palette.WARNING, 1.8) if blink else LightKit.glow(Palette.CYAN, 1.2 * power)
		draw_circle(comm + Vector2(0, -16), 1.6, lamp)
	# 維修插銷：停住後亮起提示色。
	var pin := _pin_local()
	draw_rect(Rect2(pin + Vector2(-2, -3), Vector2(4, 6)), LightKit.glow(Palette.CYAN, 2.0) if halted and not pin_pulled else steel)
	# 掃描臂：肩上往前伸的臂與發射頭；臂鎖在肩上。
	var arm := _part_offset(ARM_LOCK)
	var tip := arm + Vector2(f * 22.0, -2.0)
	draw_line(arm, tip, steel, 3.0)
	draw_rect(Rect2(tip + Vector2(-3, -3), Vector2(6, 6)), steel.lightened(0.15))
	draw_rect(Rect2(arm + Vector2(-4, -3), Vector2(8, 6)), _part_color(ARM_LOCK, dark))
	# 盾架（前方）：完整時是鋼板加警示邊，裂開後有裂痕、顏色變暗。
	var shield := _part_offset(SHIELD)
	var plate := Rect2(shield + Vector2(-4, -17), Vector2(8, 34))
	draw_rect(plate, steel.darkened(0.35) if shield_cracked else steel)
	draw_rect(plate, Color(0.9, 0.7, 0.2, 0.9), false, 1.0)
	if shield_cracked:
		draw_polyline(PackedVector2Array([shield + Vector2(-3, -14), shield + Vector2(1, -6), shield + Vector2(-2, 2), shield + Vector2(3, 12)]), dark, 1.0)
	draw_rect(Rect2(_part_offset(SHIELD_LOCK) + Vector2(-3, -3), Vector2(6, 6)), _part_color(SHIELD_LOCK, dark))
	_draw_telegraphs()
	if _question_left > 0.0 or (_replaying and (fsm.is_in(&"windup") or fsm.is_in(&"act"))):
		_draw_replay_mark()


## 打得到的部件：部件本身變亮加一圈細的脈動外框，不畫發光圓點（肩上的臂鎖就在臉旁邊，泛光下圓點會把臉蓋白）。
func _draw_open_parts() -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 10.0)
	for entry in _parts:
		var box := entry["box"] as Hurtbox
		if not is_part_open(box.part_id):
			continue
		var size: Vector2 = entry["size"]
		var rect := Rect2(box.shape_offset() - size * 0.5, size).grow(1.0 + pulse)
		draw_rect(rect, Color(LightKit.glow(Palette.WARNING, 1.3), 0.35 + 0.4 * pulse), false, 1.0)


func _part_color(id: StringName, dark: Color) -> Color:
	if halted:
		return dark
	return LightKit.glow(Palette.WARNING, 1.15) if is_part_open(id) else Color(0.72, 0.42, 0.14)


func _part_offset(id: StringName) -> Vector2:
	for entry in _parts:
		if (entry["box"] as Hurtbox).part_id == id:
			var offset: Vector2 = entry["offset"]
			return Vector2(offset.x * facing, offset.y)
	return Vector2.ZERO


## 預兆：盾擊在地上畫前方扇區、掃描在要掃的高度畫一條水平線（紅＝會打到你）。
func _draw_telegraphs() -> void:
	if not (fsm.is_in(&"windup") or fsm.is_in(&"act")):
		return
	var kind := StringName(_move().get("kind", &""))
	var t := 1.0 - clampf(_telegraph_left / maxf(0.01, telegraph_seconds(_move_id)), 0.0, 1.0) if fsm.is_in(&"windup") else 1.0
	var f := float(facing)
	match kind:
		&"shield_bash":
			if fsm.is_in(&"windup"):
				var reach := _param("distance", 80.0) + data.body_size.x * 0.5 + 14.0
				var fill := Color(LightKit.glow(Palette.DANGER, 0.9 + 1.2 * t), 0.18 + 0.32 * t)
				draw_colored_polygon(_flat_fan(f, reach), fill)
				draw_line(Vector2(f * 6.0, -1.0), Vector2(f * (6.0 + reach * t), -1.0), Color(LightKit.glow(Palette.DANGER, 2.0), 0.6 + 0.3 * t), 1.5)
		&"scan_sweep":
			var y := -_scan_height
			var start := f * (data.body_size.x * 0.5)
			var reach := _param("reach", 170.0)
			if fsm.is_in(&"windup"):
				var color := Color(LightKit.glow(Palette.DANGER, 0.9 + 1.4 * t), 0.3 + 0.5 * t)
				var x := 0.0
				while x < reach:
					draw_line(Vector2(start + f * x, y), Vector2(start + f * minf(reach, x + 6.0), y), color, 1.0)
					x += 10.0
				draw_line(Vector2(start + f * reach, y - 4.0), Vector2(start + f * reach, y + 4.0), color, 1.0)
			else:
				draw_line(Vector2(start, y), Vector2(start + f * _scan_extent, y), LightKit.glow(Palette.DANGER, 3.0), 2.0)


## 地上的扇區（壓扁的半扇形）：從腳前往外 reach，前緣比根部寬，看得出是一整片會被推到的範圍。
func _flat_fan(f: float, reach: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(f * 4.0, -1.0)])
	for i in 11:
		var a := lerpf(-PI * 0.5, PI * 0.5, i / 10.0)
		points.append(Vector2(f * (4.0 + reach * cos(a)), sin(a) * 5.0 - 1.0))
	return points


## 遺忘迴圈的提示：頭上一個問號，工作架的小螢幕顯示「程式重播」。
func _draw_replay_mark() -> void:
	var head := to_local(_head_point()) + Vector2(0, -14)
	var font := ThemeDB.fallback_font
	var color := LightKit.glow(Palette.WARNING, 1.5)
	draw_string(font, head + Vector2(-4, 0), "?", HORIZONTAL_ALIGNMENT_CENTER, 8.0, 14, color)
	var screen := _part_offset(COMM) + Vector2(-float(facing) * 2.0 - 14.0, -24.0)
	draw_string(font, screen, "程式重播", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7, Color(color, 0.9))
