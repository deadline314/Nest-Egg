extends StrikeEnemy
## 電漿鞭（長距離橫掃）
## 行為：保持中距離，抖開電漿鞭蓄力；預兆會在地上畫出這一擊的位置——頭高的一條要蹲下，腳邊的一條要跳起來。
## 應對：看預兆的高度：高的蹲下（或舉盾），低的跳過；衝刺穿過去也行；鞭子很長，但貼身就沒有威脅，欺近牠輸出。
## 每次出招從 strike.bands 清單抽一條（HIGH＝頭高、LOW＝腳邊）；資料決定高度與長度。

const HIGH := 0
const LOW := 1
const SEGMENTS := 14

## 測試與預覽用：>= 0 時固定使用這一條，不抽籤。
var forced_variant := -1
var _variant := HIGH


func _windup_enter() -> void:
	_variant = forced_variant if forced_variant >= 0 else randi() % maxi(1, (spec["bands"] as Array).size())
	super._windup_enter()


func _band() -> Vector2:
	return StrikeSpec.band_of(spec, _variant)


func _strike_enter() -> void:
	super._strike_enter()
	var tip := global_position + Vector2(facing * float(spec["reach"]), -(_band().x + _band().y) * 0.5)
	Fx.flash_light(tip, Palette.CYAN, 70.0, 1.6, 0.15)


## 鞭子：預兆時盤在手邊微微抖動；出招時沿高度帶快速甩出去，尖端最亮，之後很快收回。
func _draw_weapon() -> void:
	var from := _hand_point()
	var band := _band()
	var y := -(band.x + band.y) * 0.5
	var reach := float(spec["reach"])
	var extend := 0.12
	var glow := 1.2
	if fsm.is_in(&"windup"):
		extend = 0.12 + 0.1 * sin(_anim_time * 30.0)
	elif fsm.is_in(&"strike"):
		extend = clampf(fsm.time_in_state / maxf(0.01, float(spec["active"])) * 2.0, 0.0, 1.0)
		glow = 2.4
	elif fsm.is_in(&"recover"):
		extend = maxf(0.12, 1.0 - fsm.time_in_state / 0.25)
		glow = 1.5
	var end := Vector2(facing * (float(spec["reach_from"]) + reach * extend), y)
	var color := LightKit.glow(Palette.CYAN.lerp(Palette.DANGER, 0.4 if fsm.is_in(&"windup") else 0.0), glow)
	var previous := from
	for i in range(1, SEGMENTS + 1):
		var t := float(i) / SEGMENTS
		var point := from.lerp(end, t) + Vector2(0.0, sin(t * PI * 2.0 + _anim_time * 18.0) * 3.0 * (1.0 - t) * (1.0 if not fsm.is_in(&"strike") else 0.3))
		draw_line(previous, point, color, lerpf(2.2, 1.0, t))
		previous = point
