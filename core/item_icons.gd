class_name ItemIcons
extends RefCounted
## 背包用的像素圖示載入（快取在 RigLibrary，同一張只載入一次）。
## 圖示放在 art/items/icons/<id>.png；缺檔時記錄具體路徑並改用同尺寸的替代圖，位置不會跑掉。
## 以同名 PNG 覆蓋即可換成正式美術。

const ICON_DIR := "res://art/items/icons"
const ICON_SIZE := Vector2i(32, 32)


## 消耗品與劇情道具的圖示（32×32）。
static func item(icon: String) -> Texture2D:
	var file := icon if not icon.is_empty() else "unset"
	return RigLibrary.texture(ICON_DIR.path_join(file + ".png"), ICON_SIZE)
