class_name LightQuality
extends RefCounted
## 光影品質三檔（高／中／低）：光源預算、陰影、後製顆粒與色差、體積光、法線貼圖。
## 玩家在設定選單選擇，存在設定檔；各系統用這裡的查詢函式，不直接判斷檔位。

enum Tier { LOW, MEDIUM, HIGH }

const DEFAULT_TIER := Tier.HIGH
const NAMES: Dictionary[int, String] = {Tier.LOW: "低", Tier.MEDIUM: "中", Tier.HIGH: "高"}
## 設定選單與 tooltip 用的一句說明。
const DESCRIPTIONS: Dictionary[int, String] = {
	Tier.LOW: "只留基本光源與一組陰影，關閉體積光、法線貼圖、顆粒與色差；效能最好",
	Tier.MEDIUM: "光源與陰影減半、光錐細節減半，關閉顆粒與色差；效能與畫面折衷",
	Tier.HIGH: "全部光影效果，設計的完整畫面",
}
const SETTINGS: Dictionary[int, Dictionary] = {
	Tier.LOW: {"max_lights": 8, "shadow_lights": 1, "shadow_filter": Light2D.SHADOW_FILTER_NONE, "post_effects": 0.0, "volumetrics": false, "shaft_detail": 0.0, "normal_maps": false},
	Tier.MEDIUM: {"max_lights": 14, "shadow_lights": 2, "shadow_filter": Light2D.SHADOW_FILTER_PCF5, "post_effects": 0.0, "volumetrics": true, "shaft_detail": 0.5, "normal_maps": true},
	Tier.HIGH: {"max_lights": 24, "shadow_lights": 4, "shadow_filter": Light2D.SHADOW_FILTER_PCF5, "post_effects": 1.0, "volumetrics": true, "shaft_detail": 1.0, "normal_maps": true},
}


static func tier() -> int:
	return Settings.get_light_quality()


static func max_lights() -> int:
	return SETTINGS[tier()]["max_lights"]


static func shadow_lights() -> int:
	return SETTINGS[tier()]["shadow_lights"]


static func shadow_filter() -> Light2D.ShadowFilter:
	return SETTINGS[tier()]["shadow_filter"]


## 後製顆粒與色差的倍率（0 = 關閉）。
static func post_effects() -> float:
	return SETTINGS[tier()]["post_effects"]


static func volumetrics() -> bool:
	return SETTINGS[tier()]["volumetrics"]


## 光錐（LightShaft）的細緻度：1 = 有變化的那一格就重畫，0.5 = 每秒最多重畫 30 次，0 = 不畫。
## 光錐是體積光裡最貴的一項（BG-16 實測：關掉省約 20% 每影格時間）。
static func shaft_detail() -> float:
	return SETTINGS[tier()]["shaft_detail"]


static func normal_maps() -> bool:
	return SETTINGS[tier()]["normal_maps"]
