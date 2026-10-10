extends Node
const Capture = preload("res://tools/viewport_capture.gd")
func _ready() -> void:
 var output := ""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="):
   output = arg.trim_prefix("--out=")
 assert(output.is_absolute_path())
 var viewport := SubViewport.new()
 viewport.size = Vector2i(1440, 1000)
 viewport.use_hdr_2d = true
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
 label.add_theme_font_size_override("font_size", 22)
 label.text = "NE-90｜點遮罩交付檢查\n文件預覽・不是角色或動畫驗收\n\n" + FileAccess.get_file_as_string("res://document.md")
 viewport.add_child(label)
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 assert(Capture.image(viewport).save_png(output) == OK)
 print("DOCUMENT_CAPTURE original=1440x1000 renderer=", RenderingServer.get_current_rendering_method())
 get_tree().quit()

