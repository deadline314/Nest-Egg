extends StrikeEnemy
## 押運手（第二章市集，NE-266）：收帳人的押車小弟，拿短棍貼地突進。
## 行為：看到玩家就靠近，在一段距離外壓低身子蓄力（地上畫出突進的判定範圍、棍頭發紅），然後往前衝一段並揮棍。
## 應對：判定在腰到胸的高度，跳起來越過或衝刺（無敵）穿過；撲空後收招很長，是輸出空檔。數值都在 EnemyData.strike。
## 外觀：暫用收帳人打手的骨架，短棍用程式畫；角色組交付專屬外觀後只改資料（NE-266 票上列了姿勢與尺寸）。

const BATON_LENGTH := 16.0
## 突進時離玩家多近就停（像素，從身體前緣算）。
const STOP_GAP := 10.0


func _strike_enter() -> void:
	super._strike_enter()
	Fx.dust(global_position, 6, 80.0)
	Sfx.play(&"dash", -8.0)


## 突進只到貼近玩家為止，不衝進玩家身上（身體接觸不是這一招的判定）。
func _strike_tick(delta: float) -> void:
	super._strike_tick(delta)
	var target := _target()
	if target != null and fsm.is_in(&"strike") and signf(target.global_position.x - global_position.x) == float(facing) \
			and absf(target.global_position.x - global_position.x) <= data.body_size.x * 0.5 + STOP_GAP:
		velocity.x = 0.0


func _rig_state(input: RigInput) -> void:
	super._rig_state(input)
	input.crouching = fsm.is_in(&"windup")


## 短棍：前手握著，蓄力時棍頭發紅、突進時拉一道殘影。
func _draw_weapon() -> void:
	var from := _hand_point()
	var dir := _hand_dir()
	var tip := from + dir * BATON_LENGTH
	draw_line(from, tip, Color(0.12, 0.12, 0.14), 3.0)
	draw_line(from, tip, Color(0.55, 0.56, 0.6), 1.0)
	if fsm.is_in(&"windup"):
		draw_circle(tip, 2.0, LightKit.glow(Palette.DANGER, 1.4 + clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)))
	elif fsm.is_in(&"strike"):
		draw_line(tip, tip - Vector2(facing * 14.0, 0.0), Color(LightKit.glow(Palette.DANGER, 1.4), 0.5), 2.0)
	elif fsm.is_in(&"recover"):
		# 撲空後喘氣：棍頭垂到地上（輸出空檔）。
		draw_circle(tip, 1.5, Color(0.55, 0.56, 0.6))
