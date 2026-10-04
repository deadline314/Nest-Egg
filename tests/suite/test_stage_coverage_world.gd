class_name StageCoverageWorldSuite
extends StageSuiteBase
## 畫面情境的完整覆蓋（機關、介面、環境音、音樂）：這些域的每個位置都執行它的情境，驗證實際響出該位置的聲音。
## 慢（每個情境都真的跑完），所以平行執行器把它分給獨立的程序；改了情境資料或動作時一定要跑。

func run() -> void:
	_catalog.load_all()
	await _open_stage()
	await _check_slot_scenes(PackedStringArray(["ENV", "UIS", "AMB", "BGM"]), false)
	await _close_stage()
