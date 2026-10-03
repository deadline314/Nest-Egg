shader_type canvas_item;
render_mode unshaded;
// 衝擊波：環形的折射（把畫面往環外推擠）加上一圈很亮的邊。畫在一個正方形上，progress 0→1 環由中心擴張到邊緣。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 0.2) = 0.03;
uniform float thickness : hint_range(0.01, 0.5) = 0.08;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float glow = 0.7;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float r = mix(0.05, 0.95, 1.0 - pow(1.0 - progress, 2.2));
	float fade = 1.0 - progress;
	float band = exp(-pow((d - r) / thickness, 2.0));
	vec2 dir = p / max(d, 0.0001);
	vec2 offset = dir * band * strength * fade;
	vec3 base = texture(screen_tex, SCREEN_UV - offset).rgb;
	float edge = exp(-pow((d - r) / (thickness * 0.3), 2.0)) * fade * fade;
	float inside = 1.0 - smoothstep(0.9, 1.0, d);
	COLOR = vec4(base + tint.rgb * edge * glow, inside);
}
