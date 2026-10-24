@abstract
class_name InventoryPage
extends Control
## 背包分頁的基底：標題、分頁 tooltip、重新整理、方向鍵導覽、確認。
## 新增分頁只要繼承它（或 CardListPage）並在 InventoryScreen 的分頁清單加一行。

## 目前選取（或滑鼠指到）的項目的一句說明；背包畫面底部說明列顯示它。
signal hint_changed(text: String)

var context: InventoryContext


func bind(p_context: InventoryContext) -> void:
	context = p_context


@abstract func tab_title() -> String


## 滑鼠移到分頁標籤上顯示的一句說明。
@abstract func tab_tooltip() -> String


## 分頁標籤是否要顯示提醒點（例如有新取得的道具）。
func tab_has_alert() -> bool:
	return false


## 是否在右側顯示信用點與凜的立繪欄；自己就有角色圖的分頁回傳 false。
func shows_side_portrait() -> bool:
	return true


## 重新讀取遊戲資料並更新畫面（開啟背包、切到此分頁、執行動作後呼叫）。
@abstract func refresh() -> void


## 切到此分頁。animate = false 用於開啟背包時（整個畫面已有開啟動畫）。
func page_shown(_animate: bool) -> void:
	refresh()


## 離開此分頁或關閉背包。
func page_hidden() -> void:
	pass


## 方向鍵：x 左右、y 上下。
func navigate(_direction: Vector2i) -> void:
	pass


## Enter／手把確認。
func activate() -> void:
	pass


## 目前選取項目的一句說明（沒有則為空字串）。
func current_hint() -> String:
	return ""


## A nested page view consumes Back before the whole inventory closes.
func handle_back() -> bool:
	return false
