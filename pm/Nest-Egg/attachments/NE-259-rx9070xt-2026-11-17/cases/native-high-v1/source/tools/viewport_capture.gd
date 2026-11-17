extends RefCounted
## HDR 2D readback is linear; PNG viewers expect sRGB. Alpha and dimensions stay intact.
## https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html

static func image(viewport: Viewport) -> Image:
	return encode(viewport.get_texture().get_image(), viewport.use_hdr_2d)


## Convert while pixels are still floating point. Quantizing linear dark values
## first loses most of their sRGB steps and creates false contour bands.
static func encode(source: Image, hdr: bool) -> Image:
	if not hdr:
		return source
	var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			result.set_pixel(x, y, source.get_pixel(x, y).linear_to_srgb())
	return result
