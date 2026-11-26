shader_type canvas_item;
render_mode unshaded;

// A single world-aligned sheet ends at the shop jamb.
void fragment() {
	vec2 grid = vec2(UV.x * 33.0 + UV.y * 4.0, UV.y * 13.0 - TIME * 12.0);
	vec2 cell = floor(grid);
	vec2 point = fract(grid);
	float offset = fract(sin(dot(cell, vec2(17.7, 69.4))) * 151.9);
	float width = 1.0 - smoothstep(0.018, 0.048, abs(point.x - offset));
	float length = smoothstep(0.1, 0.38, point.y) * (1.0 - smoothstep(0.52, 0.94, point.y));
	float edge = smoothstep(0.0, 0.07, UV.y) * (1.0 - smoothstep(0.76, 1.0, UV.y));
	COLOR = vec4(0.49, 0.64, 0.69, width * length * edge * mix(0.08, 0.31, offset));
}
