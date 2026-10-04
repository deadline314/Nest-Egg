class_name ChaseData
extends Resource
## 追逐橋段：一面向前推進的光幕（第二章「回收燈幕」）。放在地圖 legend 的一個字元上，該格就是起點：
## 玩家走過起點後，光幕從身後 lead_tiles 格處出發，以固定速度往右推進 length_tiles 格後停下；追上玩家就是死亡（從檢查點重來）。
## 橋段前後都放檢查點；速度要比玩家的跑速慢（150）很多，才有餘裕跳過障礙。

@export var id: StringName = &"chase"
@export var display_name: String = "追逐"
## 推進速度（像素／秒）。
@export var speed: float = 78.0
## 玩家走過起點時，光幕在他身後幾格。
@export var lead_tiles: int = 18
## 光幕從起點往右推進多少格後停下（橋段終點）。
@export var length_tiles: int = 50
## 光幕主色。
@export var color: Color = Color(1.0, 0.18, 0.12, 1.0)
## 觸發時顯示的一句提示。
@export var hint: String = "回收燈幕逼近——持續前進"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("追逐橋段缺少 id")
	if speed <= 0.0 or speed >= 120.0:
		problems.append("%s: speed 要大於 0 且小於玩家跑速的 80%%（120）" % id)
	if lead_tiles < 6:
		problems.append("%s: lead_tiles 至少 6 格，玩家要有反應時間" % id)
	if length_tiles <= lead_tiles:
		problems.append("%s: length_tiles 必須大於 lead_tiles" % id)
	return problems
