class_name MeleeModule
extends Node
## 近戰攻擊模組（NE-277）：自己管招式的播放（前搖、出招、收招、可取消點）、連段、判定與命中回饋。
## 招式全部是資料（MeleeSet：預設那組 data/feel/melee.json，近戰武器各一份 data/melee/<id>.json）；
## 新增一把近戰武器只加資料，不改這裡。
##
## 和主角的約定（host）：模組只讀寫主角的位置、面向、準星、速度、架式值與裝備，判定透過主角的受擊框查詢；
## 主角的槍械、瞄準與手臂程式不知道招式的細節，只問「現在能不能動、能不能取消、該播哪個姿勢」。
## 終結技（打破防的敵人）是主角自己的動作：沒拿近戰武器時按近戰鍵，模組先問主角有沒有可以終結的目標。

enum Phase { NONE, WINDUP, ACTIVE, RECOVERY }

## 近戰的兩個按鍵：近戰鍵一律是近戰；射擊鍵只有拿著近戰武器時是近戰。
const ACTIONS: Array[StringName] = [&"melee", &"shoot"]
## 揮擊跟著準星時，離水平方向最多偏幾度（弧度）。
const AIM_LIMIT := 1.2
## 動作進度上三段的分界（角色姿勢依它播放）：前搖 0～0.4、出招 0.4～0.7、收招 0.7～1。
const POSE_ACTIVE_FROM := 0.4
const POSE_RECOVERY_FROM := 0.7

var host: Player
var commands: MeleeCommandInput
var cooldown_left := 0.0
var phase := Phase.NONE
var time := 0.0
var attack: Dictionary = {}
var chain: Array = []
var paid_tail := "" # 付費尾招的身分在連段開始時決定，不因即時修改而重算。
## 這一段連段用的招式組：沒拿近戰武器是預設近戰，拿著近戰武器是那把武器的組；中途換武器就從第一招重新開始。
var set_in_use: MeleeSet = MeleeData.default_set()
## 這一揮的命中回饋（頓幀、命中聲）是否已經播過；持續判定的招式只在第一個命中時播一次。
var feedback_done := false
var weapon_id: StringName = &""
var swing_facing := 1
var swing_direction := Vector2.RIGHT
var index := -1
var landed := false
var hit_ids: Dictionary = {}
var buffer_left := 0.0
var combo_left := 0.0
var visual_left := 0.0
## 多段判定（MeleeMove.hits）：目前開到第幾段（-1＝還沒開始）、這一段是否已經播過命中聲。
var hit_window := -1
var _window_sound_done := false
## 按住招式（MeleeSet.hold）：這一招是不是按住招式、模式（charge 蓄力／sustain 持續／repeat 重複）、
## 蓄滿了沒有、持續模式下一次判定的時間。
var hold_mode := ""
var charged := false
var _sustain_tick := 0.0


func _init(p_host: Player = null) -> void:
	name = "Melee"
	host = p_host
	commands = MeleeCommandInput.new()
	commands.player = p_host
	add_child(commands)


# ---------------------------------------------------------------------------
# 狀態查詢（主角、外觀、HUD 用）
# ---------------------------------------------------------------------------

func is_active() -> bool:
	return phase != Phase.NONE


## 命中後收招只要等 cancel_after 秒就能取消（接下一招、衝刺、射擊）；揮空要吃滿收招。
func is_cancellable() -> bool:
	if phase == Phase.NONE:
		return true
	return phase == Phase.RECOVERY and landed and time >= float(attack["cancel_after"])


func is_locked() -> bool:
	return not is_cancellable()


## 近戰期間的移動倍率（前搖與收招比較慢，出招時往前衝）。
func move_scale() -> float:
	return 1.0 if phase == Phase.NONE else float(attack["move_scale"])


func is_swinging() -> bool:
	return visual_left > 0.0


## 目前這一招的動作進度 0~1（前搖 0~0.4、出招 0.4~0.7、收招 0.7~1），不在近戰中回傳 -1；角色揮砍動作依它播放。
func pose_progress() -> float:
	match phase:
		Phase.WINDUP:
			return clampf(time / maxf(0.001, float(attack["windup"])), 0.0, 1.0) * POSE_ACTIVE_FROM
		Phase.ACTIVE:
			var active := maxf(0.001, float(attack["active"]))
			if hold_mode == "sustain" and time > active:
				# 持續中：鞭子在出招段來回甩（loop），戰戟停在出招段的 hold_at（把戟頭頂在前面）。
				var spec := set_in_use.hold()
				if bool(spec.get("loop", false)):
					return POSE_ACTIVE_FROM + pingpong(time / active, 1.0) * (POSE_RECOVERY_FROM - POSE_ACTIVE_FROM)
				return clampf(float(spec.get("hold_at", POSE_RECOVERY_FROM)), POSE_ACTIVE_FROM, POSE_RECOVERY_FROM)
			return POSE_ACTIVE_FROM + clampf(time / active, 0.0, 1.0) * (POSE_RECOVERY_FROM - POSE_ACTIVE_FROM)
		Phase.RECOVERY:
			return POSE_RECOVERY_FROM + clampf(time / maxf(0.001, float(attack["recovery"])), 0.0, 1.0) * (1.0 - POSE_RECOVERY_FROM)
	return -1.0


## 目前這一招的動作名稱（資料的 pose：slash 斜斬、overhead 劈砍、thrust 刺擊、sweep 橫掃）。
func pose() -> String:
	return str(attack.get("pose", "slash")) if phase != Phase.NONE else ""


## 這一招現在的身體動作（骨盆前後、上下、胸口轉角）；不在近戰中是零。
func body_now() -> Vector3:
	return MeleeMove.body_at(attack, pose_progress()) if phase != Phase.NONE else Vector3.ZERO


## 這一招現在的武器路徑 (握把方向, 握把離肩膀的距離, 武器傾角)；沒有路徑或不在近戰中回傳空陣列。方向是朝右空間，已經加上這一揮的瞄準偏轉。
func path_now() -> PackedFloat32Array:
	if phase == Phase.NONE:
		return PackedFloat32Array()
	var sample := MeleeMove.path_at(attack, pose_progress())
	if not sample.is_empty() and bool(attack["aim_follow"]):
		sample[0] += Vector2(swing_direction.x * swing_facing, swing_direction.y).angle()
	return sample


## 這一招要不要雙手握。
func two_handed_now() -> bool:
	return phase != Phase.NONE and MeleeMove.hands(attack) == 2


## 揮擊的方向：預設朝面向水平揮；aim_follow 的招式（長柄的刺擊、鞭）跟著準星，但限制在水平上下約 70 度內。
func direction(def: Dictionary) -> Vector2:
	if phase != Phase.NONE:
		return swing_direction
	return aim_direction(def)


func aim_direction(def: Dictionary) -> Vector2:
	if not bool(def["aim_follow"]):
		return Vector2(host.facing, 0.0)
	var angle := clampf(Vector2(host.aim_dir.x * host.facing, host.aim_dir.y).angle(), -AIM_LIMIT, AIM_LIMIT)
	return Vector2(cos(angle) * host.facing, sin(angle))


## 這一招的特效顏色（軌跡的 color，沒寫用青色）。
static func color_of(def: Dictionary) -> Color:
	var trail: Variant = def.get("trail")
	return Color.from_string(str((trail as Dictionary).get("color", "")), Palette.CYAN) if typeof(trail) == TYPE_DICTIONARY else Palette.CYAN


## 這一招的出手聲與命中聲（資料缺漏時用內建預設）。
static func sounds_of(def: Dictionary) -> Dictionary:
	var sounds: Variant = def.get("sounds")
	var result := {"swing": "melee_swing", "hit": "melee_hit"}
	if typeof(sounds) == TYPE_DICTIONARY:
		result.merge(sounds as Dictionary, true)
	return result


# ---------------------------------------------------------------------------
# 輸入與出招
# ---------------------------------------------------------------------------

## 每個物理影格的近戰按鍵：按下（含提早按的緩衝）出招或排進下一段；回傳是否吃掉這一格（從沒出招變成出招）。
## 鍵鼠與手把走同一條路（兩個近戰按鍵的規則相同）。
func poll_input() -> bool:
	for action in ACTIONS:
		if action == &"shoot" and not host.holds_melee_weapon():
			continue
		commands.poll(action)
	if commands.remaining() > 0.0:
		if phase == Phase.NONE:
			try_attack()
			return true
		buffer_left = commands.remaining()
	return false


## 拿著近戰武器按住：第一招打完還按著，就接這把武器的按住招式（蓄力、持續或重複）；
## 沒有按住招式的組照舊重複第一招。按住招式自己一條連段，不會跳到第二段以後。
func handle_held() -> void:
	if phase != Phase.NONE or not is_held():
		return
	if not start_hold():
		try_attack(false)


## 兩個近戰按鍵有沒有按著（射擊鍵只在拿著近戰武器時算；丟東西用掉的那一下射擊鍵要先放開才算，NE-254）。
func is_held() -> bool:
	return Input.is_action_pressed(&"melee") or (host.holds_melee_weapon() and Input.is_action_pressed(&"shoot") and not (host.carry != null and host.carry.holds_back_shoot()))


## 出這把武器的按住招式；沒有按住招式、狀態不允許或電量不足回傳 false。
func start_hold() -> bool:
	if host.state != Player.State.NORMAL or host.is_blocking or GameplayLock.is_locked() or host.get_tree().paused or cooldown_left > 0.0:
		return false
	var weapon := host.loadout.active_weapon()
	var next_set := MeleeData.set_of(weapon)
	var spec := next_set.hold()
	if spec.is_empty():
		return false
	var id := str(spec["attack"])
	chain = [id]
	index = -1
	paid_tail = ""
	set_in_use = next_set
	if not start_attack(true):
		return false
	hold_mode = str(spec["mode"])
	return true

## 近戰鍵：附近有破防敵人時發動終結技，否則進入連段斬擊（前搖、出招、收招；預設連段輕、輕、重，近戰武器用自己的連段）。
## 出招中再按會緩衝，收招可取消的時間點到了就接下一段。回傳是否吃掉這次按鍵。
func try_attack(continue_combo := true) -> bool:
	if host.state != Player.State.NORMAL or host.is_blocking or GameplayLock.is_locked() or host.get_tree().paused:
		return false
	if phase != Phase.NONE:
		commands.queue_command()
		buffer_left = commands.remaining()
		return true
	if cooldown_left > 0.0:
		return false
	var armed := host.holds_melee_weapon()
	if not armed:
		host.loadout.cancel_reload()  # 近戰武器的「換彈」是充電，揮擊不取消它
	var target := host._find_finisher_target() if not armed else null
	if target != null:
		commands.consume()
		host._start_finisher(target)
		return true
	return start_attack(continue_combo and combo_left > 0.0)


## 開始一段揮擊；近戰武器每揮消耗電量，電量不足（充電中）揮不出去並回傳 false。
func start_attack(continue_combo: bool) -> bool:
	var weapon := host.loadout.active_weapon()
	var next_set := MeleeData.set_of(weapon)
	if next_set != set_in_use:
		continue_combo = false
	var combo := chain if continue_combo and not chain.is_empty() else next_set.combo(weapon != null and Progression.has_upgrade(weapon, next_set.extension_upgrade()))
	# 尾招不能環回首招；整條招式於首招選定。
	if continue_combo and index >= combo.size() - 1:
		return false
	var next_index := index + 1 if continue_combo and index >= 0 else 0
	var tail_id := paid_tail if continue_combo else next_set.extension_attack()
	var def := next_set.attack(str(combo[next_index]), not tail_id.is_empty() and str(combo[next_index]) == tail_id)
	if def.is_empty():
		end(false)
		return false
	var cost := float(def["guard_cost"])
	if not is_finite(cost) or cost < 0.0 or cost > host.guard or (cost > 0.0 and host._guard_lockout_left > 0.0):
		end(false)
		return false
	if weapon != null and weapon.is_melee() and not _spend_charge(weapon):
		end(false)
		return false
	if host.loadout.active_weapon() != weapon:
		end(false)
		return false
	if cost > 0.0:
		host.guard -= cost
		host._guard_regen_delay_left = float(def["windup"]) + float(def["active"]) + float(def["recovery"]) + host.guard_stats.guard_regen_delay()
		host._emit_guard()
	InputFeel.resolve(&"melee")
	set_in_use = next_set
	chain = combo
	paid_tail = tail_id if combo.has(tail_id) else ""
	index = next_index
	attack = def
	commands.consume()
	weapon_id = weapon.id if weapon != null else &""
	swing_facing = host.facing
	swing_direction = aim_direction(attack)
	phase = Phase.WINDUP
	time = 0.0
	landed = false
	feedback_done = false
	hit_ids.clear()
	hit_window = -1
	_window_sound_done = false
	hold_mode = ""
	charged = false
	_sustain_tick = 0.0
	buffer_left = 0.0
	combo_left = 0.0
	visual_left = float(attack["windup"]) + float(attack["active"]) + 0.04
	return true


## 近戰武器的電量（沿用彈匣）：沒有電量限制的武器直接通過；電量不足時喀一聲、不揮擊。
func _spend_charge(weapon: WeaponData) -> bool:
	if not weapon.has_magazine() or host.loadout.consume_ammo():
		return true
	host._dry_fire()
	return false


## 每個物理影格推進近戰三段與模組自己的計時器（主角的計時器階段呼叫）。
func tick(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	_tick_phase(delta)
	visual_left = maxf(0.0, visual_left - delta)


func _tick_phase(delta: float) -> void:
	buffer_left = commands.remaining()
	if phase == Phase.NONE:
		combo_left = maxf(0.0, combo_left - delta)
		if combo_left <= 0.0:
			index = -1
		return
	if host.state in [Player.State.DEAD, Player.State.FINISHER, Player.State.STAGGERED, Player.State.MOUNTED, Player.State.PHONE]:
		end(false)
		return
	time += delta
	match phase:
		Phase.WINDUP:
			if time >= float(attack["windup"]) and not _keep_charging():
				phase = Phase.ACTIVE
				time = 0.0
				_strike()
		Phase.ACTIVE:
			_advance_hit_windows(time - delta)
			if _keep_sustaining(delta):
				return
			if time >= float(attack["active"]):
				phase = Phase.RECOVERY
				time = 0.0
		Phase.RECOVERY:
			if buffer_left > 0.0 and is_cancellable() and index < chain.size() - 1:
				if not start_attack(true):
					end()
			elif time >= float(attack["recovery"]):
				end()


func end(keep_combo := true) -> void:
	var was_active := phase != Phase.NONE
	phase = Phase.NONE
	visual_left = 0.0
	if was_active:
		combo_left = set_in_use.combo_window() if landed or buffer_left > 0.0 else set_in_use.combo_window() * 0.5
		cooldown_left = 0.0
	hold_mode = ""
	charged = false
	if not keep_combo or index >= chain.size() - 1:
		index = -1
		chain.clear()
		paid_tail = ""
		if commands != null:
			commands.clear()
		combo_left = 0.0
		buffer_left = 0.0
		hit_ids.clear()
		attack = {}
		time = 0.0
		landed = false
		feedback_done = false


## 中斷不保留連段；換武器亦不能免費消除尚未承擔的動作時間。
func interrupt(preserve_risk := false) -> void:
	var remaining := 0.0
	if preserve_risk and phase != Phase.NONE:
		remaining = float(attack["recovery"])
		if phase == Phase.WINDUP:
			remaining += maxf(0.0, float(attack["windup"]) - time) + float(attack["active"])
		elif phase == Phase.ACTIVE:
			remaining += maxf(0.0, float(attack["active"]) - time)
		else:
			remaining = maxf(0.0, remaining - time)
	var cooldown := cooldown_left
	end(false)
	cooldown_left = maxf(cooldown, remaining)


# ---------------------------------------------------------------------------
# 判定與命中回饋
# ---------------------------------------------------------------------------

## 出招的瞬間：往前衝、判定一次；同一揮對同一目標只命中一次。有 sweep 的招式在出招區間內每個影格再判定。
func _strike() -> void:
	var def := attack
	host.velocity.x += float(swing_facing) * float(def["advance"])
	if host._visual != null:
		host._visual.notify_melee_swing(def.get("trail", {}), host.facing, direction(def))
	MeleeFx.swing(_chest(), host.global_position, direction(def), float(def["range"]), color_of(def),
			StringName(str(def["impact_fx"])), str((def["trail"] as Dictionary).get("style", "arc")) == "lash")
	_advance_hit_windows(-1.0)
	if not landed:
		var heavy := int(def["stagger"]) >= 3
		Sfx.play_named(StringName(str(sounds_of(def)["swing"])), -10.0 if not heavy else -6.0)


## 蓄力：按住招式的前搖到了還按著就停在舉起的姿勢繼續蓄，放開或蓄滿（hold.max 秒）才出手；蓄滿的那一下用 hold.full_damage。
func _keep_charging() -> bool:
	if hold_mode != "charge":
		return false
	var spec := set_in_use.hold()
	var extra := time - float(attack["windup"])
	if extra >= float(spec.get("max", 0.0)):
		if not charged:
			charged = true
			InputBindings.vibrate(0.15, 0.35, 0.08)
		return false
	return is_held()


## 持續：按住招式的出招到了還按著就一直維持（最多 hold.max 秒），每 hold.interval 秒判定一次（同一個目標每次都能再被打到）；
## 跟著準星的招式（鞭）方向跟著準星轉。回傳 true＝這一格還在持續。
func _keep_sustaining(delta: float) -> bool:
	if hold_mode != "sustain" or time < float(attack["active"]):
		return false
	var spec := set_in_use.hold()
	if not is_held() or time >= float(attack["active"]) + float(spec.get("max", 0.0)):
		return false
	if bool(attack["aim_follow"]):
		swing_direction = aim_direction(attack)
	_sustain_tick -= delta
	if _sustain_tick <= 0.0:
		_sustain_tick = float(spec.get("interval", 0.25))
		hit_ids.clear()
		_window_sound_done = false
		hit_pass()
	visual_left = maxf(visual_left, 0.05)
	return true


## 多段判定：時間到了就開下一段（同一個目標在新的一段可以再被打一次）；有 sweep 的招式在每一段開著的期間每影格判定。
## previous_time 是這一格開始時的出招時間（出招的第一格傳 -1）；一段在這一格開始時還開著，這一格就判定。
## 只有一段、從 0 開始、持續整個出招的招式，結果和搬到新格式之前完全一樣。
func _advance_hit_windows(previous_time: float) -> void:
	var windows := MeleeMove.hits(attack)
	var opened := false
	while hit_window + 1 < windows.size() and time >= float((windows[hit_window + 1] as Dictionary)["at"]) - MeleeMove.EPSILON:
		hit_window += 1
		opened = true
		if hit_window > 0:
			hit_ids.clear()
		_window_sound_done = false
		hit_pass()
	if opened or hit_window < 0 or not bool(attack["sweep"]):
		return
	var window: Dictionary = windows[hit_window]
	if previous_time < float(window["at"]) + float(window["length"]):
		hit_pass()


## 這一瞬間判定範圍內、還沒被這一段打過的目標；命中時給傷害、衝擊與回饋。
func hit_pass() -> void:
	var def := attack
	var knock: Array = def["knockback"]
	var heavy := int(def["stagger"]) >= 3
	var landed_now := false
	# 武器打到的點：揮擊方向上、攻擊距離約四分之三處；每個目標的回饋放在自己受擊範圍內最靠近這一點的位置（NE-268）。
	var strike := _chest() + direction(def) * float(def["range"]) * 0.75
	for target_hurtbox in targets(def):
		var id := target_hurtbox.health.get_instance_id() if target_hurtbox.health != null else target_hurtbox.get_instance_id()
		if hit_ids.has(id):
			continue
		var info := DamageInfo.create(_damage_now(def), Combat.Team.PLAYER, &"melee", Vector2(swing_facing * float(knock[0]), float(knock[1])))
		info.stagger = int(def["stagger"])
		info.impact = float(def["impact"])
		info.attacker = weakref(host)
		info.freeze_attacker = not feedback_done and hit_ids.is_empty()
		info.origin = host.global_position
		var contact := target_hurtbox.closest_point(strike)
		info.contact_point = contact
		var result := target_hurtbox.receive(info)
		if result != Hurtbox.Result.IGNORED:
			hit_ids[id] = true
		if result == Hurtbox.Result.DAMAGED:
			landed = true
			landed_now = true
			EventBus.hit_confirmed.emit(contact, target_hurtbox.health.is_dead)
			EventBus.hit_marker.emit(&"kill" if target_hurtbox.health.is_dead else (&"weak" if info.weak_hit else &"hit"))
			if info.weak_hit or int(def["stagger"]) >= 3:
				EventBus.damage_number.emit(contact, info.amount, &"weak" if info.weak_hit else &"crit", target_hurtbox.health.get_instance_id())
			MeleeFx.hit(contact, direction(def), color_of(def), StringName(str(def["impact_fx"])), heavy)
			HitFeedback.play(target_hurtbox.material_id(), contact, Vector2(-host.facing, -0.2), Palette.CYAN, {"weak": info.weak_hit})
	if landed_now and not feedback_done:
		feedback_done = true
		InputBindings.vibrate(0.25, 0.45 if heavy else 0.2, 0.1)
		# 延後到物理步驟之後：頓幀會停用自己，不能在自己的物理處理中途做。被打到的敵人在 Enemy 裡依受擊層級自己凍結。
		# 頓幀一招只有一次（多段、多目標都不疊加）。
		var ctx := {"targets": [host], "dir": host.aim_dir, "origin": host.global_position}
		if float(def["hitstop"]) > 0.0:
			ctx["freeze"] = float(def["hitstop"])
		Feel.play.call_deferred(StringName(str(def["event"])), ctx)
	if landed_now and not _window_sound_done:
		# 命中聲分層（MeleeFx 的回饋層之一）：低頻的悶擊在下、高頻的切割或撞擊在上；多段攻擊每一段各響一次。
		_window_sound_done = true
		for layer in MeleeMove.hit_layers(def):
			Sfx.play_named(layer, -3.0 if not heavy else 0.0)


## 這一下的傷害：多段攻擊看是第幾段；蓄滿的按住招式用 hold.full_damage。
func _damage_now(def: Dictionary) -> int:
	if charged and hold_mode == "charge":
		return int(set_in_use.hold().get("full_damage", def["damage"]))
	return MeleeMove.hit_damage(def, maxi(0, hit_window))


## 這一招判定範圍裡的受擊框：box 是面前的矩形（可朝準星旋轉），arc 是以身體為圓心的扇形；min_range 內是死角打不到。
func targets(def: Dictionary) -> Array[Hurtbox]:
	var reach := float(def["range"])
	var dir := direction(def)
	var origin := _chest()
	var candidates: Array[Hurtbox]
	var half := PI
	if str(def["shape"]) == "arc":
		candidates = host._query_hurtboxes(origin, Vector2.ZERO, 0.0, reach)
		half = deg_to_rad(float(def["arc_degrees"])) * 0.5
	else:
		var height := float(def["height"]) if float(def["height"]) > 0.0 else Player.BODY_SIZE.y
		candidates = host._query_hurtboxes(origin + dir * reach * 0.5, Vector2(reach, height), dir.angle() if bool(def["aim_follow"]) else 0.0)
	var min_range := float(def["min_range"])
	if min_range <= 0.0 and half >= PI - 0.01:
		return candidates
	var result: Array[Hurtbox] = []
	for target in candidates:
		for box: Hurtbox in [target, target.root()]:
			var offset := box.center() - origin
			if offset.length() >= min_range and absf(dir.angle_to(offset)) <= half:
				result.append(box)  # 部位不在揮擊角度內時退回整體，不會因為選了部位而整個揮空
				break
	return result


## 揮擊的起點：胸口（身高的 55%）。
func _chest() -> Vector2:
	return host.global_position + Vector2(0.0, -Player.BODY_SIZE.y * 0.55)
