extends StrikeEnemy
## 電鋸臂（貼身連割）
## 行為：發現玩家後衝上來，舉起電鋸臂空轉加速（鋸條越轉越亮、地上顯示整個身高的判定範圍），接著邊往前推進邊連割兩次。
## 應對：預兆時往後拉開或在割下前用衝刺（無敵）穿過去；盾牌擋得住但每次都耗損護盾；完美格擋會讓牠暈眩；
##       收招有一段空檔，是輸出的機會。數值：ability_time＝收招秒數，ability_damage＝每次傷害（見 EnemyData.strike）。

const TOOTH_PITCH := 3.0
const BAR_LENGTH := 22.0
const SPARK_INTERVAL := 0.05

var _spark_left := 0.0


func _strike_tick(delta: float) -> void:
	super._strike_tick(delta)
	_spark_left -= delta
	if _spark_left <= 0.0:
		_spark_left = SPARK_INTERVAL
		var tip := global_position + _hand_point() + _hand_dir() * BAR_LENGTH
		Fx.sparks(tip, Palette.WARNING, 3, 260.0, 0.14, Vector2(facing, -0.4), 0.8, 300.0)


func _rig_state(input: RigInput) -> void:
	super._rig_state(input)
	input.crouching = fsm.is_in(&"windup")


## 鋸條：沿前臂方向的一根長條，鋸齒隨時間滑動；預兆越久越亮，出招最亮。
func _draw_weapon() -> void:
	var rev := 0.35
	if fsm.is_in(&"windup"):
		rev = 0.5 + 0.5 * clampf(fsm.time_in_state / maxf(0.01, data.telegraph_time), 0.0, 1.0)
	elif fsm.is_in(&"strike"):
		rev = 1.0
	elif fsm.is_in(&"recover"):
		rev = 0.2  # 收招時鋸條減速，是靠近輸出的訊號
	var from := _hand_point()
	var dir := _hand_dir()
	var side := Vector2(-dir.y, dir.x)
	var glow := LightKit.glow(Palette.DANGER if rev > 0.6 else Palette.WARNING, 1.0 + 1.6 * rev)
	draw_line(from, from + dir * BAR_LENGTH, Palette.TERRAIN_TOP, 3.0)
	var phase := fmod(_anim_time * (20.0 + 60.0 * rev), TOOTH_PITCH)
	var d := phase
	while d < BAR_LENGTH:
		draw_line(from + dir * d + side * 1.5, from + dir * d + side * 3.2, glow, 1.0)
		draw_line(from + dir * d - side * 1.5, from + dir * d - side * 3.2, glow, 1.0)
		d += TOOTH_PITCH
