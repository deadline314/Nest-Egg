class_name PumpInspector
extends Enemy
## 抽水巡檢器（第三章泵室與夾層，NE-272）：貼地巡檢的排水機，發現玩家就沿地面短距離衝撞。
## 行為：巡邏 → 預兆（衝撞的路線在地上亮起，越亮越近出發）→ 沿亮起的路線衝到底 → 煞停喘息（反擊空檔）→ 巡邏。
## 路線在預兆開始時決定，碰到牆或地面斷掉就停在前面，不會衝下平台；玩家站上上橋或照護步道就不會被撞。
## 應對：看到地上亮線就跳過或往旁邊讓開，也可以舉盾擋；煞停喘息時從背後打。
## 數值：attack_range＝開始預兆的距離、telegraph_time＝地面亮多久、ability_radius＝衝撞距離、
##       ability_speed＝衝撞速度、ability_damage＝衝撞傷害、ability_time＝煞停喘息的秒數。
## 外觀：零件式外觀（資料的 creature_skin）；載入失敗時退回程式繪製的貼地機身。

## 預兆路線往前探地面的間隔（像素）與能爬的落差；玩家要在差不多同一層才會出招。
const PROBE_STEP := 8.0
const PROBE_DROP := 10.0
const SAME_FLOOR := 40.0
const RAM_TIMEOUT := 1.2
const SOURCE_RAM := &"pump_inspector_ram"

var _cooldown := 0.4
var _ram_end_x := 0.0
var _floor_ray := PhysicsRayQueryParameters2D.new()
var _wall_ray := PhysicsRayQueryParameters2D.new()


func _setup_states() -> void:
	fsm.add(&"patrol", _patrol_tick)
	fsm.add(&"windup", _windup_tick, _windup_enter)
	fsm.add(&"ram", _ram_tick, _ram_enter, _ram_exit)
	fsm.add(&"recover", _recover_tick, _recover_enter)
	fsm.start(&"patrol")


## 被打出硬直時取消衝撞（預兆中被打斷也算）。
func _on_stunned() -> void:
	if fsm.is_in(&"windup") or fsm.is_in(&"ram"):
		fsm.transition(&"recover")


func _patrol_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_patrol(data.move_speed)
	var target := _target()
	if _cooldown > 0.0 or target == null or not _token_free():
		return
	if absf(target.global_position.y - global_position.y) > SAME_FLOOR:
		return
	if _can_see_target(data.attack_range, SAME_FLOOR):
		fsm.transition(&"windup")


func _windup_enter() -> void:
	velocity.x = 0.0
	_face_target()
	_ram_end_x = _plan_ram()
	_start_telegraph(data.telegraph_time)
	Sfx.play(&"beep", -10.0)


func _windup_tick(_delta: float) -> void:
	velocity.x = 0.0
	if not is_telegraphing():
		fsm.transition(&"ram")


func _ram_enter() -> void:
	if contact != null:
		contact.damage = maxi(data.contact_damage, data.ability_damage)
		contact.source_id = SOURCE_RAM
	Fx.dust(global_position, 6, 70.0)
	Sfx.play(&"dash", -5.0)


func _ram_exit() -> void:
	if contact != null:
		contact.damage = data.contact_damage
		contact.source_id = data.contact_source_id


## 衝到預兆畫出的終點就停；撞牆、地面斷掉或逾時也停，不會滑出亮線。
func _ram_tick(delta: float) -> void:
	var remaining := (_ram_end_x - global_position.x) * facing
	if remaining <= 1.0 or is_on_wall() or fsm.time_in_state > RAM_TIMEOUT or (is_on_floor() and _is_ledge_ahead()):
		velocity.x = 0.0  # 停在亮線終點：煞停不滑出預兆畫的路線
		fsm.transition(&"recover")
		return
	velocity.x = facing * minf(data.ability_speed, remaining / maxf(delta, 0.0001))
	if int(fsm.time_in_state * 30.0) % 3 == 0:
		Fx.dust(global_position, 1, 24.0)


func _recover_enter() -> void:
	Fx.sparks(global_position + Vector2(facing * data.body_size.x * 0.5, -4), Palette.WARNING, 5, 110.0, 0.25, Vector2(-facing, -0.4))


func _recover_tick(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, data.ability_speed * 3.0 * delta)
	if fsm.time_in_state >= data.ability_time:
		_face_target()
		_cooldown = _scaled_cooldown(data.attack_cooldown)
		fsm.transition(&"patrol")


## 衝撞的終點：沿面向往前每 PROBE_STEP 探一次，遇到牆或腳下沒有地面（落差大於 PROBE_DROP）就停在前一格。
func _plan_ram() -> float:
	var space := get_world_2d().direct_space_state
	var half := data.body_size.x * 0.5
	var reach := maxf(PROBE_STEP, data.ability_radius)
	var end := global_position.x
	var travelled := PROBE_STEP
	while travelled <= reach:
		var x := global_position.x + facing * travelled
		_wall_ray.from = Vector2(end + facing * half, global_position.y - 6.0)
		_wall_ray.to = Vector2(x + facing * half, global_position.y - 6.0)
		_wall_ray.collision_mask = Layers.SOLID
		if not space.intersect_ray(_wall_ray).is_empty():
			break
		_floor_ray.from = Vector2(x + facing * half, global_position.y - 4.0)
		_floor_ray.to = Vector2(x + facing * half, global_position.y + PROBE_DROP)
		_floor_ray.collision_mask = Layers.WORLD
		if space.intersect_ray(_floor_ray).is_empty():
			break
		end = x
		travelled += PROBE_STEP
	return end


## 預兆：衝撞路線在地上亮起（紅＝會撞到你），越接近出發越亮、越往前延伸；終點有一道短停止線。
func _draw_overlay() -> void:
	if not fsm.is_in(&"windup"):
		return
	var t := 1.0 - clampf(_telegraph_left / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	var start := facing * data.body_size.x * 0.5
	var end := _ram_end_x - global_position.x + facing * data.body_size.x * 0.5
	var lit := lerpf(start, end, minf(1.0, 0.35 + t))
	var strip := Color(LightKit.glow(Palette.DANGER, 1.0 + 1.6 * t), 0.35 + 0.5 * t)
	draw_rect(Rect2(Vector2(minf(start, lit), -2.0), Vector2(absf(lit - start), 2.0)), strip)
	# 箭頭標出方向，每 12 像素一個，沿路線往前爬。
	var phase := fmod(_anim_time * 40.0, 12.0)
	var x := start + facing * phase
	while (lit - x) * facing > 0.0:
		draw_line(Vector2(x, -5.0), Vector2(x + facing * 3.0, -3.0), strip, 1.0)
		draw_line(Vector2(x + facing * 3.0, -3.0), Vector2(x, -1.0), strip, 1.0)
		x += facing * 12.0
	draw_line(Vector2(end, -9.0), Vector2(end, 0.0), Color(LightKit.glow(Palette.DANGER, 2.0), 0.3 + 0.6 * t), 1.5)


## 外觀載入失敗時的程式繪製：低矮的抽水機身、前方吸水嘴與紅色感測眼。
func _draw_body(color: Color) -> void:
	var f := float(facing)
	var w := data.body_size.x
	var h := data.body_size.y
	draw_rect(Rect2(-w * 0.5, -h, w, h - 3.0), color)
	draw_rect(Rect2(-w * 0.5, -h, w, 2.0), color.lightened(0.3))
	draw_rect(Rect2(f * w * 0.5 - (6.0 if f > 0.0 else 0.0), -h * 0.45, 6.0, h * 0.3), color.darkened(0.35))
	for i in 3:
		draw_circle(Vector2(-w * 0.35 + i * w * 0.35, -2.0), 2.0, color.darkened(0.5))
	var eye := LightKit.glow(Palette.DANGER, 3.0 if is_telegraphing() else 1.4)
	draw_circle(Vector2(f * w * 0.3, -h + 4.0), 1.5, eye)
