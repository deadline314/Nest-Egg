shader_type canvas_item;
// 全螢幕轉場：progress 0 = 完全看得到畫面，1 = 完全蓋住。
// 蓋住與揭開共用同一個式子；flip 讓掃描線在揭開時繼續往同一個方向前進。
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform int kind = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flip = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 accent : source_color = vec4(0.21, 0.88, 1.0, 1.0);
uniform float time_s = 0.0;
uniform float aspect = 1.7778;
uniform float seed = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 7.31) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec4 base = textureLod(screen_tex, SCREEN_UV, 0.0);
	vec4 col = base;
	float p = progress;

	if (kind == 0 || kind == 1) {
		// 淡入淡出（黑或白）
		col = mix(base, tint, p);
	} else if (kind == 2) {
		// 光圈：圓形從 center 縮小。
		vec2 d = (uv - center) * vec2(aspect, 1.0);
		vec2 far = max(center, vec2(1.0) - center) * vec2(aspect, 1.0);
		float r = (1.0 - p) * length(far);
		float dist = length(d);
		float m = smoothstep(r, r + 0.012, dist);
		col = mix(base, tint, m);
		float ring = smoothstep(0.012, 0.0, abs(dist - r)) * step(0.001, p) * step(p, 0.999);
		col.rgb += accent.rgb * ring * 0.6;
	} else if (kind == 3) {
		// 掃描線：亮線掃過，線左邊是蓋住的部分。
		float x = mix(uv.x, 1.0 - uv.x, flip);
		float edge = p * 1.04 - 0.02;
		float covered = step(x, edge);
		col = mix(base, tint, covered);
		float line = smoothstep(0.012, 0.0, abs(x - edge)) * step(0.001, p) * step(p, 0.999);
		float halo = smoothstep(0.08, 0.0, abs(x - edge)) * 0.25 * step(0.001, p) * step(p, 0.999);
		col.rgb += accent.rgb * (line * 1.4 + halo);
		// 蓋住的部分有淡淡的橫向掃描紋。
		col.rgb += covered * accent.rgb * 0.03 * step(0.5, fract(uv.y * 90.0));
	} else if (kind == 4) {
		// 雜訊溶解：橫向切片位移、色散、數位方塊逐漸蓋住。
		float strength = sin(clamp(p, 0.0, 1.0) * 3.14159);
		float row = floor(uv.y * 48.0);
		float tick = floor(time_s * 24.0);
		float slice = (hash(vec2(row, tick)) - 0.5) * 0.35 * strength;
		float jitter = step(0.82, hash(vec2(row * 1.7, tick + 3.0)));
		float off = slice * (0.4 + jitter * 2.0);
		float r = textureLod(screen_tex, SCREEN_UV + vec2(off * 1.3, 0.0), 0.0).r;
		float g = textureLod(screen_tex, SCREEN_UV + vec2(off, 0.0), 0.0).g;
		float b = textureLod(screen_tex, SCREEN_UV + vec2(off * 0.7, 0.0), 0.0).b;
		col = vec4(r, g, b, 1.0);
		vec2 block = floor(uv * vec2(64.0, 36.0));
		float h = hash(block);
		float covered = step(h, p * 1.15 - 0.1);
		vec3 noise = mix(tint.rgb, accent.rgb, step(0.93, hash(block + tick)));
		noise = mix(noise, vec3(1.0, 0.18, 0.53), step(0.97, hash(block - tick)));
		col.rgb = mix(col.rgb, noise, covered);
		col.rgb += (1.0 - covered) * strength * 0.06 * step(0.5, fract(uv.y * 120.0));
	} else if (kind == 5) {
		// 電梯門：左右兩扇金屬門往中間關上。
		float half_open = 0.5 * p;
		float left_edge = half_open;
		float right_edge = 1.0 - half_open;
		bool in_left = uv.x < left_edge;
		bool in_right = uv.x > right_edge;
		if (in_left || in_right) {
			float t = in_left ? uv.x / max(left_edge, 0.001) : (1.0 - uv.x) / max(half_open, 0.001);
			vec3 metal = vec3(0.07, 0.09, 0.11) + 0.05 * sin(uv.y * 3.0 + t * 2.0) + 0.03 * step(0.5, fract(uv.x * 40.0));
			float edge_line = smoothstep(0.02, 0.0, abs(uv.x - (in_left ? left_edge : right_edge)));
			metal += accent.rgb * edge_line * 0.9;
			col = vec4(metal, 1.0);
		}
		// 門縫透出的光
		float seam = smoothstep(0.02, 0.0, abs(uv.x - 0.5)) * step(0.995, p);
		col.rgb += accent.rgb * seam * 0.6;
	} else {
		// 百葉：橫向葉片依序闔上。
		float bars = 14.0;
		float t = fract(uv.y * bars);
		float local = clamp(p * 1.25 - floor(uv.y * bars) / bars * 0.25, 0.0, 1.0);
		float covered = step(t, local);
		col = mix(base, tint, covered);
		float edge = smoothstep(0.08, 0.0, abs(t - local)) * step(0.001, local) * step(local, 0.999);
		col.rgb += accent.rgb * edge * 0.35;
	}
	COLOR = vec4(col.rgb, 1.0);
}
