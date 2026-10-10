shader_type canvas_item;
render_mode unshaded;
// Explicit scene clock: Godot TIME continues while SceneTree is paused.
uniform float motion_time = 0.0;
uniform vec4 flow_region;
uniform vec4 flow_surface;
uniform float water_gain = 1.0;

float inside_rect(vec2 p, vec4 r) {
	return step(r.x, p.x) * step(r.y, p.y) * step(p.x, r.x + r.z) * step(p.y, r.y + r.w);
}

varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// Sprite2D flip_h already maps UV into source texture coordinates.
	vec2 p = UV;
	float flow = inside_rect(p, flow_region);
	vec2 q = (p - flow_region.xy) / max(flow_region.zw, vec2(0.0001));
	// Thin highlights travel down existing water, never beyond its alpha.
	float streak = pow(0.5 + 0.5 * sin(6.283185 * (q.y * 6.0 - motion_time * 1.7) + q.x * 5.0), 6.0);
	float ends = smoothstep(0.0, 0.12, q.y) * (1.0 - smoothstep(0.85, 1.0, q.y));
	vec2 s = (p - flow_surface.xy) / max(flow_surface.zw, vec2(0.0001));
	float age = fract(motion_time * 0.9);
	float ring = 1.0 - smoothstep(0.025, 0.075, abs(length((s - vec2(0.5)) * vec2(1.0, 2.4)) - age * 0.46));
	float surface = inside_rect(p, flow_surface) * ring * (1.0 - age);
	base.rgb *= 1.0 - flow * ends * 0.16 + flow * ends * streak * 0.22 + surface * 0.14;
	base.rgb *= mix(1.0, water_gain, max(flow, inside_rect(p, flow_surface)));
	COLOR = base * sprite_tint;
}
