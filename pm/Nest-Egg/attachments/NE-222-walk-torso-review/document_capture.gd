extends Node
const Capture = preload("res://tools/viewport_capture.gd")
func _ready() -> void:
 var doc := FileAccess.get_file_as_string("res://design/12-cast-redraw/RIG_QUALITY.md")
 var marker := "## 補記（2026-10-10，步行軀幹與定稿保留）"
 var at := doc.find(marker)
 assert(at >= 0)
 var viewport := SubViewport.new()
 viewport.size = Vector2i(1440, 1000)
 viewport.transparent_bg = false
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(viewport)
 var background := ColorRect.new()
 background.color = Color("18212c")
 background.size = Vector2(1440, 1000)
 viewport.add_child(background)
 var label := Label.new()
 label.position = Vector2(48, 44)
 label.size = Vector2(1344, 900)
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.add_theme_font_override("font", load("res://art/fonts/NotoSansTC-Regular-subset.ttf"))
 label.add_theme_font_size_override("font_size", 26)
 label.text = "NE-222｜步行軀幹與定稿保留\n文件預覽・不是遊戲驗收截圖\n\n" + doc.substr(at)
 viewport.add_child(label)
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 var output := "res://pm/Nest-Egg/images/NE-222-walk-torso-requirement.png"
 assert(Capture.image(viewport).save_png(output) == OK)
 print("DOCUMENT_CAPTURE original=1440x1000 source=design/12-cast-redraw/RIG_QUALITY.md")
 get_tree().quit()
