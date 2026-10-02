class_name RigInput
extends RefCounted
## 每影格餵給角色動畫器的狀態（由擁有者重複使用同一個實例，不會每影格配置記憶體）。

var velocity := Vector2.ZERO
var on_floor := true
## 世界座標的瞄準方向（單位向量）。
var aim_dir := Vector2.RIGHT
var facing := 1
var run_speed := 150.0
var crouching := false
var blocking := false
var dashing := false
var staggered := false
var dead := false
## 0~1，開槍瞬間設為 1，動畫器自行衰減。
var recoil := 0.0
## 是否雙手持槍（後手扶護木）；false 時後手自然擺動或持盾。
var two_handed := true
## 後手向前舉盾（鎮暴員）。
var shield_forward := false
## 本影格受到攻擊（觸發一次退縮動作）。
var hurt := false
