class_name ConsumableData
extends Resource
## 消耗品定義（醫療針、護盾電池…）。新增消耗品只需在 data/consumables/ 建立新的 .tres。

const USE_TEXT := {
	"zh": {
		"out": "沒有%s", "health_full": "生命已滿", "guard_full": "格擋值已滿", "both_full": "生命與格擋值已滿",
		"healed": "%s回復 %d 格生命", "guard_restored": "%s回復格擋值", "both_restored": "%s回復 %d 格生命與格擋值",
	},
	"ja": {
		"out": "%sを持っていません", "health_full": "ライフは満タンです", "guard_full": "ガード値は満タンです",
		"both_full": "ライフとガード値は満タンです", "healed": "%sでライフを%d回復",
		"guard_restored": "%sでガード値を回復", "both_restored": "%sでライフを%d回復し、ガード値も回復",
	},
	"en": {
		"out": "No %s carried", "health_full": "Health is full", "guard_full": "Guard is full", "both_full": "Health and guard are full",
		"healed": "%s restored %d health", "guard_restored": "%s restored guard", "both_restored": "%s restored %d health and refilled guard",
	},
}


@export var id: StringName = &"item"
@export var display_name: String = "道具"
## 一句話說明效果（拾取提示、背包說明）。
@export_multiline var description: String = ""
@export var localized_names: Dictionary[String, String] = {}
@export var localized_descriptions: Dictionary[String, String] = {}
@export var color: Color = Color.WHITE
## 背包與 HUD 的排列順序（小的在前）。
@export var order: int = 0
## 攜帶上限。
@export var max_carry: int = 3
## 補給點的售價（信用點）；0 代表不販售。
@export var price: int = 0
@export_group("Effect")
## 回復的生命格數。
@export var heal_amount: int = 0
## 格擋值立即充滿並解除破防。
@export var restores_guard: bool = false
## 是否為快速使用鍵（{use_item}）使用的道具。
@export var quick_use: bool = false
@export_group("Art")
## 背包像素圖示的檔名（art/items/icons/<icon>.png）。
@export var icon: String = ""


func display_name_for(language: String) -> String:
	return StoryLocale.optional_text(localized_names, language, display_name)


func description_for(language: String) -> String:
	return StoryLocale.optional_text(localized_descriptions, language, description)


func unavailable_text(language: String, has_stock: bool) -> String:
	var text: Dictionary = USE_TEXT.get(language, USE_TEXT[StoryLocale.SOURCE_LANGUAGE])
	if not has_stock:
		return text["out"] % display_name_for(language)
	if heal_amount > 0 and restores_guard:
		return text["both_full"]
	return text["health_full"] if heal_amount > 0 else text["guard_full"]


func used_text(language: String, healed: int, guard_restored: bool) -> String:
	var text: Dictionary = USE_TEXT.get(language, USE_TEXT[StoryLocale.SOURCE_LANGUAGE])
	var item_name := display_name_for(language)
	if healed > 0:
		var key := "both_restored" if guard_restored else "healed"
		return text[key] % [item_name, healed]
	return text["guard_restored"] % item_name


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("消耗品缺少 id")
	if max_carry <= 0:
		problems.append("%s 的攜帶上限必須大於 0" % id)
	if heal_amount <= 0 and not restores_guard:
		problems.append("%s 沒有任何效果" % id)
	return problems
