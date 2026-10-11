extends "res://tools/cinematic_safe_area_capture.gd"
## ST-21 辦公接待廊的正式過場截圖：全景交代、隔著玻璃的室內鏡頭、凜的反應鏡頭與中段的選擇，各截一張。
## 每段單獨播（先設好該段成立的進度），到指定台詞時截圖。用法：
## godot --path . res://tools/ch3_office_capture.tscn -- --out=<絕對路徑資料夾>

## 場景 → 播之前要成立的旗標。
const PROGRESS := {
	&"ch3_t_c18_box": [],
	&"ch3_t_c19_watch": [&"ch3_petition_receipt_taken"],
	&"ch3_t_c20_trade": [&"ch3_petition_receipt_taken", &"ye_handwriting_seen"],
	&"ch3_t_c20_middle": [&"ch3_petition_receipt_taken", &"ye_handwriting_seen", &"ch3_trade_half_heard"],
	&"ch3_t_c20_rest": [&"ch3_petition_receipt_taken", &"ye_handwriting_seen", &"ch3_trade_half_heard", &"sq7_ye_name_seen"],
}


func _init() -> void:
	level_path = "res://data/levels/ch3_office_hall.tres"
	story_file = "res://data/story/ch3_clearwater.json"
	shot_prefix = "ST-21"
	id_prefix = "ch3_t_"
	shots = {
		&"ch3_t_c18_box": ["取件格的回執寫著：風控接待收件，月報17查核件。", "他叫我別上來，自己卻在這裡。"],
		&"ch3_t_c19_watch": ["葉把透明傘掛在桌旁，停筆，把手背翻向自己，補了一行字才翻開檔案。"],
		&"ch3_t_c20_trade": ["資料在天穹保管，交付人是你。這一點沒有改。", "她不知道那份資料是我交的，妳別把這個拿到她面前。"],
		&"ch3_t_c20_middle": ["原來那份資料是他親手交出去的。"],
		&"ch3_t_c20_rest": ["她手背上記著要記得的人，說到我卻只說樣本。", "回覆只能走收件人，不替你撤。"],
	}


func _prepare(id: StringName) -> void:
	for flag: StringName in [&"ch3_petition_receipt_taken", &"ye_handwriting_seen", &"ch3_trade_half_heard", &"sq7_ye_name_seen"]:
		GameState.set_flag(flag, PROGRESS.get(id, []).has(flag))
