class_name ScreenFxScenario
extends ScenarioBase
## 截圖情境（NE-146）：各種全螢幕效果的峰值畫面（受傷、格擋、破防、擊殺、頭目死亡），以及亮場景下最強的一個，檢查不過曝。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=screen_fx

const LIGHTING := "res://data/lighting/neutral.tres"
const KINDS: Array[StringName] = [&"hurt", &"parry", &"guard_break", &"kill", &"boss_death"]


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	await wait(0.4)
	capture("fx_none")
	for kind in KINDS:
		FlashGuard.reset()
		EventBus.screen_pulse.emit(kind)
		await wait(0.03)
		capture("fx_%s" % kind)
		await wait(0.6)
	await finish()
