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
## 受擊退縮的幅度倍率（輕擊小、畏縮大）。
var hurt_scale := 1.0
## 放鬆（沒發現玩家）：武器自然垂下（低持槍），發現後才舉起；動畫器自己平滑過渡。
var relaxed := false
## 受擊方向：+1＝從正面來（身體後仰）、-1＝從背後來（身體前傾）。
var hurt_dir := 1.0
## 死亡時最後一擊的方向（-1＝從背後來，後倒的角色改成向前撲）與力道（0 輕擊～1 重擊：倒得更快、更用力）。
var death_dir := 1.0
var death_force := 0.0

## NPC 動畫（NpcAnimator）：基本姿勢 stand／sit／lean／crouch、工作循環名稱與強度，以及說話、聆聽、揮手。
var npc_pose: StringName = &"stand"
var npc_loop: StringName = &""
var npc_loop_scale := 1.0
var talking := false
var listening := false
var waving := false

## 專屬動作（art/rigs/action_poses.json 的 actions）名稱與播放進度 0~1；空字串＝沒有。敵人資料的 rig_actions 依狀態填入。
var action: StringName = &""
var action_t := 0.0

