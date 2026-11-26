shader_type canvas_item;

// The cutout retains soft source pixels beyond the closed contour.
void fragment() {
	COLOR.a = smoothstep(0.22, 0.83, COLOR.a);
}
