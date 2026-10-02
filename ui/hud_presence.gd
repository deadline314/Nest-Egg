class_name HudPresence
extends RefCounted
## 動態 HUD 的顯示規則：數值變動時彈出、閒置一段時間後淡出、危險狀態常駐。
## 只負責算透明度與彈出縮放，不畫任何東西，可給任何浮動介面共用。

## 閒置時保留的透明度（留一點輪廓，玩家知道它在哪）。
var idle_alpha := 0.12
## 最後一次變動後維持完整顯示的秒數。
var linger := 2.5
var fade_in_speed := 10.0
var fade_out_speed := 1.6

var alpha := 0.0
## 彈出時的額外縮放（1.0 起跳，衰減到 0）。
var pop := 0.0

var _linger_left := 0.0


## 數值有變動：重新開始倒數，從淡出狀態回來時加一點彈跳。
func poke() -> void:
	if alpha < 0.6:
		pop = 1.0
	_linger_left = linger


## hold：危險或使用中，必須常駐。auto_hide 關閉時永遠完整顯示。hidden：完全隱藏（死亡、過場）。
func update(delta: float, hold: bool, auto_hide: bool, hidden := false) -> float:
	_linger_left = maxf(0.0, _linger_left - delta)
	pop = maxf(0.0, pop - delta * 5.0)
	var target := 0.0
	if not hidden:
		target = 1.0 if hold or not auto_hide or _linger_left > 0.0 else idle_alpha
	var speed := fade_in_speed if target > alpha else fade_out_speed
	if hidden:
		speed = fade_in_speed
	alpha = move_toward(alpha, target, delta * speed)
	return alpha


func is_lingering() -> bool:
	return _linger_left > 0.0
