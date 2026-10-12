extends PatternBoss
## 第二章頭目「阿勇」（二樓帳房，NE-265）：收帳人的頭，用鐵棍近身對決。
## 核心機制「利息」：被他打中就疊一層（BossMark），每層讓下一擊更痛；踩亮著的「結帳」地墊或 6 秒沒受擊才清掉。
## 招式、階段、地墊與劇情接點都在 data/bosses/yong.json；這個腳本只管劇本的兩條路：
##   血量到 25%：他退到終端前，戰鬥安全暫停，由故事端播選擇（ch2_t_s12_choice，寫 yong_link_choice）。
##   斷連（cut）：玩家去主隔離箱按住 1.5 秒（受擊中斷）→ 寫連結解除旗標 → 血條改成「制伏進度」。
##   保留（keep）：打到底他真正倒下並復原一次（故事端的 ch2_t_s12_keep_revival）→ 第二階段較慢較重 →
##                 再打到門檻，鷺關上維修暫停閂（ch2_t_s12_keep_pause）→ 血條改成「制伏進度」。
##   制伏：打斷棍柄鎖扣（橙色）→ 他棄棍改用短拳 → 進度打完後，趁短拳撲空的空檔按住互動拔出儲能匣 → 啟動 ch2_yong_down。
## 全程不會被打死（HealthComponent.floor_health 停在門檻）；死亡重試依旗標從正確的階段開始，不會重播選擇或第二次復原。
## 外觀暫用骨架 yong 與現有動作（角色組交付專屬動作後只改資料，NE-265 票上列了需要的姿勢）。

const CUT := "cut"
const KEEP := "keep"
const PARLEY_SPEED := 140.0
const PARLEY_MAX_TIME := 3.5
const DOWNED_TIME := 1.4
## 鐵棍的畫法（暫代，角色組交付武器圖後拿掉）：從前手沿前臂方向的長度。
const BATON_LENGTH := 24.0

var _hooks: Dictionary = {}
var _box: BossHoldPoint
var _pull: BossHoldPoint
var _lock_hits := 0
var _disarmed := false
var _exhaust_hinted := false
var _busy := false
## 目前的劇情階段：fight（第一階段）、parley（暫停）、cut_box（等隔離箱）、keep_first（保留路第一階段）、
## revived（復原後）、subdue（制伏中）、done（制伏完成）。
var stage := "fight"


func _setup_states() -> void:
	super._setup_states()
	_hooks = pattern.hooks
	if GameState.get_flag(StringName(_hook("gone_flag")), false) == true:
		# 已經制伏過（重新進關卡）：不再出現。
		queue_free()
		return
	fsm.add(&"parley", _parley_tick, _parley_enter)
	fsm.add(&"downed", _downed_tick, _downed_enter)
	fsm.add(&"subdued", _subdued_tick, _subdued_enter)
	for part in hurtbox.parts:
		if part.part_id == &"baton_lock":
			part.hit_received.connect(_on_lock_hit)
	health.health_changed.connect(_on_route_health)
	EventBus.player_died.connect(_on_player_died)
	_build_hold_points()
	_restore_route()


func _hook(key: String, fallback: Variant = "") -> Variant:
	return _hooks.get(key, fallback)


func _flag(key: String) -> Variant:
	return GameState.get_flag(StringName(str(_hook(key))), null)


func _hp_at(ratio: float) -> int:
	return clampi(ceili(health.max_health * ratio), 1, health.max_health)


## 第一階段結束的血量（25%）：資料第一個階段的 until。
func _choice_hp() -> int:
	var list := pattern.phase_list()
	return _hp_at(float(list[0]["until"]) if list.size() > 1 else 0.25)


# ---------------------------------------------------------------------------
# 劇情階段與重試
# ---------------------------------------------------------------------------

## 依旗標決定從哪裡開始（死亡重試、讀檔）：選過就不再選；斷連成功不會回到保留；保留路的復原只發生一次。
func _restore_route() -> void:
	var choice := str(_flag("choice_flag")) if _flag("choice_flag") != null else "unset"
	var isolated: bool = _flag("isolated_flag") == true
	var revived: bool = _flag("revived_flag") == true
	if choice == CUT and isolated:
		_set_health_silent(_choice_hp())
		_enter_subdue("subdue", false)
	elif choice == CUT:
		_set_health_silent(_choice_hp())
		_start_cut(false)
	elif choice == KEEP and revived and isolated:
		_set_health_silent(_hp_at(float(_hook("latch_ratio", 0.35))))
		_enter_subdue("subdue_revived", false)
	elif choice == KEEP and revived:
		_set_health_silent(_hp_at(float(_hook("revive_ratio", 0.6))))
		_start_revived(false)
	elif choice == KEEP:
		_set_health_silent(_choice_hp())
		_start_keep(false)
	else:
		stage = "fight"
		health.floor_health = _choice_hp()


func _set_health_silent(value: int) -> void:
	health.current = clampi(value, 1, health.max_health)
	_apply_phase(pattern.phase_for(_health_ratio(), phase_set), false)


## 血量到 25%：資料的 choice 事件。選過了（重試）就直接接那條路，不再暫停。
func _on_phase_event(event: StringName) -> bool:
	if event != &"choice" or stage != "fight":
		return false
	var choice := str(_flag("choice_flag")) if _flag("choice_flag") != null else "unset"
	if choice == CUT:
		_start_cut(true)
	elif choice == KEEP:
		_start_keep(true)
	else:
		fsm.transition(&"parley")
	return true


func _parley_enter() -> void:
	stage = "parley"
	velocity.x = 0.0
	_telegraph_left = 0.0
	# 增援也停手（暫停前他退到終端的這一小段），暫停中整個世界由過場凍結。
	for ref in _summons:
		var minion := ref.get_ref() as Enemy
		if minion != null and not minion.is_dying():
			minion.stun(PARLEY_MAX_TIME + 0.5)


## 退到終端前護住機器，到了（或太久到不了）就播選擇說明。
func _parley_tick(_delta: float) -> void:
	if _busy:
		velocity.x = 0.0
		return
	var goal := float(_hook("terminal_tile", 56)) * 16.0 + 8.0
	var gap := goal - global_position.x
	if absf(gap) > 6.0 and fsm.time_in_state < PARLEY_MAX_TIME and not is_on_wall():
		facing = 1 if gap > 0.0 else -1
		velocity.x = signf(gap) * PARLEY_SPEED
		return
	velocity.x = 0.0
	_face_target()
	_play_choice()


func _play_choice() -> void:
	_busy = true
	var scene := StringName(str(_hook("choice_scene")))
	var played: bool = await Story.play_and_wait(scene, false)
	if not is_instance_valid(self) or not is_inside_tree() or _dying:
		return
	var choice := str(_flag("choice_flag")) if _flag("choice_flag") != null else "unset"
	if choice != CUT and choice != KEEP and played:
		# 選擇窗被關掉而沒有選（不預設）：再播一次說明。
		played = await Story.play_and_wait(scene, false)
		if not is_instance_valid(self) or not is_inside_tree() or _dying:
			return
		choice = str(_flag("choice_flag")) if _flag("choice_flag") != null else "unset"
	_busy = false
	if choice == KEEP:
		_start_keep(true)
	elif choice == CUT:
		_start_cut(true)
	else:
		push_error("[YongBoss] 選擇場景 %s 沒有寫入 %s（場景不存在或沒有選），改走斷連路，避免戰鬥卡住" % [scene, _hook("choice_flag")])
		_start_cut(true)


## 斷連路：等玩家操作主隔離箱；他照常追擊。箱子完成前血量停在 25%（打他不會先把之後的制伏進度打光）。
func _start_cut(perform: bool) -> void:
	stage = "cut_box"
	health.floor_health = _choice_hp()
	if _box != null:
		_box.enabled = true
	if perform:
		EventBus.toast_requested.emit(str(_hook("box_hint")))
		fsm.transition(&"idle")


func _on_box_completed() -> void:
	GameState.set_flag(StringName(str(_hook("isolated_flag"))), true)
	GameState.set_flag(StringName(str(_hook("revoked_flag"))), true)
	EventBus.toast_requested.emit(str(_hook("box_done_toast")))
	_enter_subdue("subdue", true)


## 保留路第一階段：打到底他會真正倒下一次（血量停在 1，交給 downed）。
func _start_keep(perform: bool) -> void:
	stage = "keep_first"
	health.floor_health = 1
	if perform:
		fsm.transition(&"idle")


func _start_revived(perform: bool) -> void:
	stage = "revived"
	health.floor_health = _hp_at(float(_hook("latch_ratio", 0.35)))
	use_phase_set("revived", perform)
	if perform:
		EventBus.boss_started.emit(data.display_name, health.max_health)
		EventBus.boss_health_changed.emit(health.current, health.max_health)


## 血量碰到這個階段的門檻時接下一步（保留路倒下、鷺關上暫停閂、制伏進度打完）。
func _on_route_health(current: int, _maximum: int) -> void:
	if _dying or not _awake or _busy:
		return
	if stage == "keep_first" and current <= 1:
		fsm.transition(&"downed")
	elif stage == "revived" and current <= health.floor_health:
		_play_latch()
	elif stage == "subdue" and current <= 1 and not _disarmed and not _exhaust_hinted:
		_exhaust_hinted = true
		EventBus.toast_requested.emit("先打斷棍柄的鎖扣")


## 保留路：真正倒下（不是普通擊敗），播復原，回來時是第二階段。
func _downed_enter() -> void:
	velocity.x = 0.0
	_telegraph_left = 0.0
	hurtbox.enabled = false
	if contact != null:
		contact.active = false
	Feel.play(&"boss_phase_shift")
	Fx.burst(_center(), Palette.DANGER, 20, 200.0, 0.5)
	if mark != null:
		mark.stop()


func _downed_tick(_delta: float) -> void:
	velocity.x = 0.0
	if _busy or fsm.time_in_state < DOWNED_TIME:
		return
	_play_revival()


func _play_revival() -> void:
	_busy = true
	var scene := StringName(str(_hook("revival_scene")))
	await Story.play_and_wait(scene, true)
	if not is_instance_valid(self) or not is_inside_tree() or _dying:
		return
	if _flag("revived_flag") != true:
		push_error("[YongBoss] 復原場景 %s 沒有寫入 %s，由頭目補寫，避免重試時再復原一次" % [scene, _hook("revived_flag")])
		GameState.set_flag(StringName(str(_hook("revived_flag"))), true)
	_busy = false
	hurtbox.enabled = true
	if contact != null:
		contact.active = true
	health.floor_health = 0
	health.current = _hp_at(float(_hook("revive_ratio", 0.6)))
	if mark != null:
		mark.start()
	_start_revived(true)


## 保留路：鷺關上維修暫停閂（故事端的短演出，寫入讀取停止的旗標），之後才改成制伏進度。
func _play_latch() -> void:
	_busy = true
	var scene := StringName(str(_hook("latch_scene")))
	await Story.play_and_wait(scene, true)
	if not is_instance_valid(self) or not is_inside_tree() or _dying:
		return
	if _flag("isolated_flag") != true:
		push_error("[YongBoss] 暫停閂場景 %s 沒有寫入 %s，由頭目補寫" % [scene, _hook("isolated_flag")])
		GameState.set_flag(StringName(str(_hook("isolated_flag"))), true)
	_busy = false
	_enter_subdue("subdue_revived", true)


## 制伏中：血條改成「制伏進度」，棍柄鎖扣打開（橙色）。
func _enter_subdue(set_name: String, perform: bool) -> void:
	stage = "subdue"
	if _box != null:
		_box.enabled = false
	health.floor_health = 1
	_lock_hits = 0
	_disarmed = false
	set_tag("subdue", true)
	use_phase_set(set_name, perform)
	if _awake:
		EventBus.boss_started.emit(str(_hook("subdue_name", data.display_name)), health.max_health)
		EventBus.boss_health_changed.emit(health.current, health.max_health)


func _on_lock_hit(_info: DamageInfo) -> void:
	if stage != "subdue" or _disarmed:
		return
	_lock_hits += 1
	Fx.sparks(_lock_point(), Palette.WARNING, 6, 160.0, 0.2)
	if _lock_hits >= int(_hook("lock_hits", 3)):
		_disarm()


## 鎖扣斷了：棍子掉地，改用短拳；之後趁撲空拔匣。
func _disarm() -> void:
	_disarmed = true
	set_tag("subdue", false)
	Sfx.play(&"block", -2.0)
	Fx.sparks(_lock_point(), Palette.WARNING, 14, 220.0, 0.35)
	use_phase_set("disarmed_revived" if phase_set == "subdue_revived" else "disarmed", true)


func is_disarmed() -> bool:
	return _disarmed


## 拔匣的時機：棍子已經掉了、制伏進度打完，而且他正在短拳撲空或被格擋後的空檔。
func can_pull_cell() -> bool:
	if stage != "subdue" or not _disarmed or health.current > 1:
		return false
	return fsm.is_in(&"yanked") or (fsm.is_in(&"recover") and last_slam_result() != &"hit")


func _on_pull_completed() -> void:
	fsm.transition(&"subdued")


func _subdued_enter() -> void:
	stage = "done"
	velocity.x = 0.0
	_telegraph_left = 0.0
	hurtbox.enabled = false
	if contact != null:
		contact.active = false
	if mark != null:
		mark.stop()
	if _pull != null:
		_pull.enabled = false
	Fx.burst(_center(), Palette.WHITE, 18, 160.0, 0.4)
	Feel.play(&"boss_death")
	EventBus.boss_bar_closed.emit()
	EventBus.toast_requested.emit("制伏了——儲能匣拔出來，裝甲停了")
	var channel := StringName(str(_hook("done_channel")))
	if channel != &"":
		EventBus.mechanism_toggled.emit(channel, true)


func _subdued_tick(_delta: float) -> void:
	velocity.x = 0.0


func is_subdued() -> bool:
	return stage == "done"


## 醒來：已經在制伏中（重試）時，血條直接用「制伏進度」的名字。
func _wake() -> void:
	super._wake()
	if stage == "subdue":
		EventBus.boss_started.emit(str(_hook("subdue_name", data.display_name)), health.max_health)
		EventBus.boss_health_changed.emit(health.current, health.max_health)


func _on_player_died(_cause: StringName) -> void:
	if _awake and stage != "done":
		Story.play(StringName(str(_hook("defeat_scene"))), true)


## 第一次在本場用出連段時，鷺提醒一句（最多一次）。
func choose_move() -> StringName:
	var choice := super.choose_move()
	if choice == &"slam_combo":
		Story.play(StringName(str(_hook("combo_scene"))), true)
	return choice


# ---------------------------------------------------------------------------
# 機關：主隔離箱、拔匣點
# ---------------------------------------------------------------------------

func _build_hold_points() -> void:
	var parent := get_parent() as Node2D
	_box = BossHoldPoint.new()
	_box.name = "YongIsolationBox"
	_box.setup(float(_hook("box_hold", 1.5)), str(_hook("box_prompt")), "box")
	_box.completed.connect(_on_box_completed)
	if parent != null:
		parent.add_child.call_deferred(_box)
		_place_box.call_deferred()
	_pull = BossHoldPoint.new()
	_pull.name = "YongPowerCell"
	_pull.setup(float(_hook("pull_hold", 0.6)), str(_hook("pull_prompt")), "none")
	_pull.follow = self
	_pull.completed.connect(_on_pull_completed)
	add_child(_pull)


func _place_box() -> void:
	if not is_instance_valid(_box) or not _box.is_inside_tree():
		return
	_box.global_position = _floor_at(Vector2(float(_hook("box_tile", 60)) * 16.0 + 8.0, global_position.y - 8.0))


func isolation_box() -> BossHoldPoint:
	return _box


func power_cell() -> BossHoldPoint:
	return _pull


func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(_box) and not _box.is_queued_for_deletion():
		_box.queue_free()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _pull != null:
		# 儲能匣在背上偏中間：正面貼近或繞到背後都拿得到。
		_pull.follow_offset = Vector2(-facing * 4.0, -data.body_size.y * 0.6)
		# 開始按住就是抓住他：空檔不會在按到一半時結束（放開或受擊會中斷）。
		if _pull.enabled and _pull.progress() > 0.0 and fsm.is_in(&"recover"):
			fsm.time_in_state = minf(fsm.time_in_state, maxf(0.0, _recover_time - 0.2))
		var ready := can_pull_cell()
		if ready != _pull.enabled:
			_pull.enabled = ready
			# 拔匣的空檔裡他沒有攻擊性：貼著他按住互動不會被身體碰撞打斷。
			if contact != null and stage == "subdue":
				contact.active = not ready


# ---------------------------------------------------------------------------
# 外觀
# ---------------------------------------------------------------------------

## 倒下（保留路的第一次倒下）與被制伏後跪低；專屬的倒地與跪坐姿勢由角色組交付後改用資料的 poses。
func _rig_state(input: RigInput) -> void:
	super._rig_state(input)
	input.crouching = fsm.is_in(&"subdued") or fsm.is_in(&"downed")


func _lock_point() -> Vector2:
	var hand := anchor_node(&"hand_front")
	return hand.global_position if hand != null else global_position + Vector2(facing * 8.0, -data.body_size.y * 0.55)


## 暫代的鐵棍：從前手沿前臂方向畫一根短棍；蓄力時棍頭發紅（紅＝要打到你）。棍子掉了就不畫。
func _draw_overlay() -> void:
	super._draw_overlay()
	if _disarmed or stage == "done" or fsm.is_in(&"downed"):
		return
	var hand := anchor_node(&"hand_front")
	var forearm := anchor_node(&"arm_front_lower")
	if hand == null or forearm == null:
		return
	var dir := (hand.global_position - forearm.global_position).normalized() if hand.global_position.distance_to(forearm.global_position) > 0.1 else Vector2(facing, 0)
	var from := to_local(hand.global_position)
	var to := from + dir * BATON_LENGTH
	draw_line(from, to, Color(0.12, 0.12, 0.14), 3.0)
	draw_line(from, to, Color(0.5, 0.52, 0.56), 1.0)
	if fsm.is_in(&"windup") and StringName(_move().get("kind", &"")) == &"slam":
		draw_circle(to, 2.5, LightKit.glow(Palette.DANGER, 2.4))
