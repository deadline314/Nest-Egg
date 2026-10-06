class_name HdPortrait
extends Control
## 角色高解析立繪（NE-215）：把角色骨架在獨立的子視窗裡以高倍率畫出來（零件貼圖是原圖解析度，不是像素放大），
## 用平滑濾鏡顯示，並播放待機動作（呼吸、眨眼、重心）。與遊戲內的角色共用同一份骨架與貼圖，所以外觀永遠一致、不另外佔貼圖記憶體。
## 子視窗只在可見時更新（背包關閉或換頁時不耗效能）。

## 子視窗的解析度相對於顯示大小的倍率（顯示在 4K 螢幕上仍然清晰）。
const RENDER_SCALE := 2.0
## 角色在顯示範圍內佔的高度比例（頭頂與腳底各留一點邊）。
const FILL := 0.92
## 骨架單位到畫面像素的倍率（骨架的站立高度約 RIG_HEIGHT 單位）。
const RIG_HEIGHT := 58.0

var character := "rin"
## 面向（1＝右、-1＝左）。
var facing := 1

var _viewport: SubViewport
var _holder: Node2D
var _rig: CharacterRig
var _input := RigInput.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input.on_floor = true
	_input.two_handed = false
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.handle_input_locally = false
	add_child(_viewport)
	# 子視窗的畫面以平滑濾鏡縮放到控制項大小（子視窗解析度是顯示的 RENDER_SCALE 倍）。
	var view := TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	view.texture = _viewport.get_texture()
	add_child(view)
	_holder = Node2D.new()
	_viewport.add_child(_holder)
	_rig = CharacterRig.new()
	_holder.add_child(_rig)
	if not _rig.setup(character, "npc"):
		push_error("[HdPortrait] 找不到角色骨架「%s」，立繪不顯示。" % character)
		_rig.queue_free()
		_rig = null
		return
	_rig.set_weapon("")
	_input.facing = facing
	resized.connect(_layout)
	_layout()


## 子視窗大小與角色的縮放、位置：腳底在下緣中央，高度佔 FILL。
func _layout() -> void:
	if _viewport == null:
		return
	var pixels := Vector2i((size * RENDER_SCALE).round())
	_viewport.size = Vector2i(maxi(2, pixels.x), maxi(2, pixels.y))
	var unit := float(_viewport.size.y) * FILL / RIG_HEIGHT
	_holder.scale = Vector2.ONE * unit
	_holder.position = Vector2(float(_viewport.size.x) * 0.5, float(_viewport.size.y) * (1.0 + FILL) * 0.5)


func _process(delta: float) -> void:
	if _rig != null and is_visible_in_tree():
		_rig.animate(delta, _input)
