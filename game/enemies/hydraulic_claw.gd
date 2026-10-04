extends StrikeEnemy
## 液壓鉗（低位猛夾）
## 行為：發現玩家後慢慢逼近，張開巨大的液壓鉗貼地蓄力（預兆很長，地上顯示低矮的判定範圍），然後猛地夾合。
## 應對：判定只在腳邊的低矮範圍，預兆時往上跳過去最安全；也可以衝刺穿過去或拉開距離；蓄力時打到牠的衝擊夠大會被打斷；
##       夾空後液壓缸洩壓，收招很長，是最好的輸出空檔。

const JAW_LENGTH := 18.0
const OPEN_ANGLE := 0.85


func _strike_enter() -> void:
	super._strike_enter()
	Fx.dust(global_position + Vector2(facing * float(spec["reach"]) * 0.5, 0.0), 6, 70.0)


func _rig_state(input: RigInput) -> void:
	super._rig_state(input)
	input.crouching = fsm.is_in(&"windup")


## 兩片鉗口：預兆時慢慢張開，出招瞬間夾合，收招保持閉合。
func _draw_weapon() -> void:
	var open := 0.15
	if fsm.is_in(&"windup"):
		open = lerpf(0.15, OPEN_ANGLE, clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0))
	elif fsm.is_in(&"strike"):
		open = lerpf(OPEN_ANGLE, 0.0, clampf(fsm.time_in_state / maxf(0.01, float(spec["active"])) * 3.0, 0.0, 1.0))
	elif fsm.is_in(&"recover"):
		open = 0.0
	var from := _hand_point()
	var dir := _hand_dir()
	var color := LightKit.glow(Palette.DANGER if fsm.is_in(&"windup") or fsm.is_in(&"strike") else Palette.WARNING, 1.2 + (1.2 if fsm.is_in(&"strike") else 0.0))
	draw_line(from, from + dir * 7.0, Palette.TERRAIN_TOP, 3.0)
	var base := from + dir * 7.0
	draw_line(base, base + dir.rotated(-open) * JAW_LENGTH, color, 2.5)
	draw_line(base, base + dir.rotated(open) * JAW_LENGTH, color, 2.5)
