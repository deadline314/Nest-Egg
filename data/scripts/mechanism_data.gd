class_name MechanismData
extends Resource
## 環境機關定義（升降梯、閘門、開關、電力開關）。新增一個機關只需建立 .tres 並在關卡的 legend 對應字元。
## 開關與閘門以 channel 連動：同一個 channel 的開關切換時，閘門跟著開關。

enum Kind {
	## 上下往返的單向平台。
	LIFT,
	## 擋路的閘門；所屬 channel 的開關啟動時打開。
	GATE,
	## 互動後切換 channel 的開關。
	SWITCH,
	## 電力開關：切斷或恢復一段範圍（欄）的電力。斷電的區域熄燈，雷射柵欄、砲台與升降梯停擺。
	POWER_SWITCH,
	## 水坑（以死解謎）：站上坑底的踏板，水在幾秒內漲滿並淹死玩家；channel 的閘門隨之打開，水位與閘門在死後保留，
	## 漲滿的水面上會浮起一排貨櫃讓人走過去。size_tiles 是坑的內部寬×深（格），原點是踏板所在格的底邊中點（坑底正中）。
	FLOOD_PIT,
}

@export var id: StringName = &"mechanism"
@export var kind: Kind = Kind.SWITCH
@export var display_name: String = "機關"
## 靠近時顯示的一句提示（可用 {interact}）。
@export var hint: String = ""
@export var color: Color = Color(1.0, 0.76, 0.29, 1.0)
## 開關與閘門的連動頻道（也用於電力開關的區域 id）。
@export var channel: StringName = &""
## 大小（格）：閘門是寬×高，升降梯是寬×1。
@export var size_tiles := Vector2i(1, 4)
@export_group("Lift")
## 升降梯往上移動的格數。
@export var travel_tiles: int = 6
@export var speed: float = 50.0
## 兩端停留秒數。
@export var wait_time: float = 1.2
@export_group("Flood")
## 從踏板被踩下到水漲滿的秒數。
@export var rise_time: float = 2.4
@export_group("Power")
## 電力開關控制的範圍（從開關所在欄往左右各幾欄）。
@export var power_range_tiles := Vector2i(24, 24)
## 斷電時套用的光影；空白則用 blackout。
@export var blackout_profile: LightingProfile


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("機關缺少 id")
	match kind:
		Kind.GATE, Kind.SWITCH:
			if channel == &"":
				problems.append("%s 是閘門或開關，必須指定 channel" % id)
		Kind.POWER_SWITCH:
			if channel == &"":
				problems.append("%s 是電力開關，必須指定 channel（電力區域 id）" % id)
			if power_range_tiles.x < 0 or power_range_tiles.y < 0 or power_range_tiles.x + power_range_tiles.y < 1:
				problems.append("%s 的電力範圍必須大於 0" % id)
		Kind.FLOOD_PIT:
			if channel == &"":
				problems.append("%s 是水坑，必須指定 channel（漲水後要打開的閘門頻道）" % id)
			if size_tiles.x < 3 or size_tiles.y < 3:
				problems.append("%s 的水坑太小（%dx%d 格，至少 3x3）" % [id, size_tiles.x, size_tiles.y])
			if rise_time <= 0.0:
				problems.append("%s 的 rise_time 必須大於 0" % id)
		Kind.LIFT:
			if travel_tiles < 1 or speed <= 0.0:
				problems.append("%s 的升降梯行程與速度必須大於 0" % id)
	if size_tiles.x < 1 or size_tiles.y < 1:
		problems.append("%s 的大小必須至少 1×1 格" % id)
	return problems
