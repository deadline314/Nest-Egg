extends RefCounted
## HDR 2D readback is linear; PNG viewers expect sRGB. Alpha and dimensions stay intact.
## https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html

static func image(viewport: Viewport) -> Image:
	var result := viewport.get_texture().get_image()
	if viewport.use_hdr_2d:
		result.convert(Image.FORMAT_RGBA8)
		result.linear_to_srgb()
	return result
