extends RefCounted
## Callers cache shaping until text, font, text size or available width changes.

static func content_width(viewport: Viewport, padding: Vector2) -> float:
	var view := world_rect(viewport)
	return maxf(32.0, minf(160.0, view.size.x * 0.44) - padding.x * 2.0)


static func world_rect(viewport: Viewport) -> Rect2:
	var rect := Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	if is_instance_valid(Story.framing) and Story.framing.get_viewport() == viewport:
		rect = Story.framing.safe_rect()
	return viewport.get_canvas_transform().affine_inverse() * rect


static func paragraph(text: String, font: Font, size: int, width: float) -> TextParagraph:
	var result := TextParagraph.new()
	result.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	result.width = minf(width, maxf(1.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x))
	result.add_string(text, font, size)
	return result
