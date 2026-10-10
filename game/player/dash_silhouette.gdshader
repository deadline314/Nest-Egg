shader_type canvas_item;
render_mode unshaded, blend_mix;

// COLOR.a already includes source alpha, shared texture alpha and the slot fade.
// No screen readback, lighting, normal or glow is needed by this silhouette.
void fragment() {
	COLOR = vec4(vec3(0.035), COLOR.a);
}
