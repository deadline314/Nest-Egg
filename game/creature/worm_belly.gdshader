shader_type canvas_item;

varying float belly_roll;
varying vec4 vertex_tint;
varying vec2 scale_uv;

void vertex() {
	// Worm's paired vertices encode the section's roll in their vertical UV.
	bool lower = (VERTEX_ID % 2) == 1;
	belly_roll = lower ? 1.0 - UV.y : UV.y;
	scale_uv = vec2(UV.x, lower ? 1.0 : 0.0);
	// Keep UV intact for CanvasTexture's normal decoding and quality toggle.
	vertex_tint = COLOR;
}

void fragment() {
	vec2 other_uv = vec2(scale_uv.x, 1.0 - scale_uv.y);
	float roll = clamp(belly_roll, 0.0, 1.0);
	// Crossfade intact scales; interpolating mirrored UVs squeezes the texture.
	COLOR = mix(texture(TEXTURE, scale_uv), texture(TEXTURE, other_uv), roll) * vertex_tint;
}
