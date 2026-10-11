class_name GuardPresenter
extends RefCounted
## 格擋的「呈現」介面（NE-239 留給 NE-269 的機械臂臂盾）：判定、時間窗、防禦量全部在 Player，呈現只畫出來，不能改規則。
## 現在的實作是浮在身前的方向光盾（ShieldSurface）；臂盾做好後寫一個新的類別繼承這裡、實作同樣四個呼叫，
## 在 PlayerVisual 把 _shield 換掉即可，主角與敵人的程式都不用動。
##
## 每一格 PlayerVisual 依序呼叫：
##   update(delta, active, broken, aim, arc_degrees)
##       active      Player.is_blocking：這一格真的在擋（按住格擋、能量夠、不在出招鎖定中）。剛按下的那一格就算，展開動畫不影響判定。
##       broken      Player.is_guard_broken()：被打穿後的鎖定期（不能再舉）；由假變真的那一格就是「破盾」。
##       aim         Player.aim_dir：擋的方向（扇形的中心）。
##       arc_degrees PlayerTuning.block_arc_degrees：擋得住的扇形總角度；畫出來的盾面要和它一致，遮不到的方向本來就擋不住。
##   paint_emitter(canvas, wrist, center, guard_ratio)：從後手手腕（shield_wrist_local）連到盾面的部分（光盾是投射線；臂盾是前臂裝甲本身）。
##   paint(canvas, center, guard_ratio, parry_window, window_left, block_flash, parry_flash, flash_scale, motion_scale)
##       guard_ratio  防禦量 0～1（低的時候要看得出快被打穿）。
##       parry_window Player.is_parry_window()：現在擋下就是完美格擋；window_left 是這個窗口還剩幾成（連按時窗口會縮短）。
##       block_flash／parry_flash 一般格擋／完美格擋剛發生後的剩餘秒數（各自要有分得出來的回饋）。
##       flash_scale  Settings.flash_scale()（「減少閃光」時變小）；motion_scale 是畫面震動的設定倍率（「減少動態」時是 0）。
## 事件：一般格擋與完美格擋時 PlayerVisual 會呼叫 notify_impact(來襲方向，相對身體中心)，用來在盾上被打到的位置做記號。
## 下面四個欄位是呈現的狀態（測試與工具會讀）：extension 展開程度 0～1、break_left 破盾演出剩餘秒數、direction 盾面朝向、impact_direction 最後一次被打的方向。

var extension := 0.0
var break_left := 0.0
var direction := Vector2.RIGHT
var impact_direction := Vector2.RIGHT


func update(_delta: float, _active: bool, _broken: bool, _aim: Vector2, _arc_degrees: float) -> void:
	pass


func notify_impact(incoming: Vector2) -> void:
	impact_direction = incoming.normalized() if incoming.is_finite() and incoming.length_squared() > 0.0001 else direction


## 回傳盾面靠手腕那一側的錨點（測試用來量手腕到盾面的距離）。
func paint_emitter(_canvas: CanvasItem, _wrist: Vector2, center: Vector2, _guard_ratio: float) -> Vector2:
	return center


func paint(_canvas: CanvasItem, _center: Vector2, _guard_ratio: float, _parry_window: bool,
		_window_left: float, _block_flash: float, _parry_flash: float, _flash_scale: float, _motion_scale: float) -> void:
	pass
