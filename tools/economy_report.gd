extends Node
## 經濟對帳報表：godot --headless --path . res://tools/economy_report.tscn
## 印出第一章可得的總金額與必要花費的比例（見 core/economy_report.gd）。


func _ready() -> void:
	print(EconomyReport.summary(EconomyReport.ch1_paths()))
	get_tree().quit()
