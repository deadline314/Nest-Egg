extends Node2D
const CAPTURE = preload("res://tools/viewport_capture.gd")
var textures: Array[Texture2D] = []
var out := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	assert(out.is_absolute_path())
	get_tree().root.content_scale_size = Vector2i(1280,720)
	get_tree().root.size = Vector2i(1280,720)
	get_viewport().use_hdr_2d = true
	RenderingServer.set_default_clear_color(Color("19232e"))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for file in ["reference.png","outputs/NE90_reference_roundtrip_S0_0.png","outputs/NE90_reference_roundtrip_S1_0.png"]:
		textures.append(ImageTexture.create_from_image(Image.load_from_file("res://.godot/ne90-reference-rgba/"+file)))
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(CAPTURE.image(get_viewport()).save_png(out)==OK)
	get_tree().quit()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(48,60),"NE-90 / Qwen reference alpha contract",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color.WHITE)
	draw_string(font,Vector2(48,102),"Actual installed LoadImage / JoinImageWithAlpha / SaveImage; no diffusion model loaded",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	var headings := ["Source RGBA", "Before: RGB only", "After: joined RGBA"]
	var captions := ["alpha 0..255 / 16 x 16", "alpha lost: all 255", "alpha restored: 0..255"]
	for i in textures.size():
		var x := 70.0+i*410
		draw_string(font,Vector2(x,178),headings[i],HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color.WHITE)
		draw_rect(Rect2(x,200,240,240),Color("101010"))
		draw_texture_rect(textures[i],Rect2(x,200,240,240),false)
		draw_string(font,Vector2(x,484),captions[i],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	draw_string(font,Vector2(48,548),"Nearest-neighbor diagnostic display x15; the source and saved outputs remain 16 x 16.",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	draw_string(font,Vector2(48,590),"RGB is byte-equal. Float join + PNG save changes some alpha bytes by 1; recorded, not hidden.",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
	draw_string(font,Vector2(48,632),"This verifies the reference path. It does not accept generated alpha, anatomy, parts or animation.",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
