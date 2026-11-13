shader_type canvas_item;

varying float belly_roll;
varying vec4 vertex_tint;
varying vec2 scale_uv;
varying vec2 body_position;

void vertex() {
	// Worm's paired vertices encode the section's roll in their vertical UV.
	bool lower = (VERTEX_ID % 2) == 1;
	belly_roll = lower ? 1.0 - UV.y : UV.y;
	scale_uv = vec2(UV.x, lower ? 1.0 : 0.0);
	// Keep UV intact for CanvasTexture's normal decoding and quality toggle.
	vertex_tint = COLOR;
	body_position = VERTEX;
}

void fragment() {
	vec2 other_uv = vec2(scale_uv.x, 1.0 - scale_uv.y);
	float roll = clamp(belly_roll, 0.0, 1.0);
	// Crossfade intact scales; interpolating mirrored UVs squeezes the texture.
	COLOR = mix(texture(TEXTURE, scale_uv), texture(TEXTURE, other_uv), roll) * vertex_tint;
	// Match both albedo samples; the second source is vertically reflected.
	vec2 a_xy = texture(NORMAL_TEXTURE, scale_uv).rg * vec2(2.0, -2.0) - vec2(1.0, -1.0);
	vec2 b_xy = texture(NORMAL_TEXTURE, other_uv).rg * vec2(2.0, -2.0) - vec2(1.0, -1.0);
	// Match default CanvasTexture decoding: reconstruct Z from XY, not authored blue.
	vec3 a = vec3(a_xy, sqrt(max(0.0, 1.0 - dot(a_xy, a_xy))));
	vec3 b = vec3(b_xy, sqrt(max(0.0, 1.0 - dot(b_xy, b_xy))));
	b.y = -b.y;
	vec3 blended = mix(a, b, roll);
	vec3 n = dot(blended, blended) > 0.000001 ? normalize(blended) : vec3(0.0, 0.0, 1.0);
	// Polygon2D's item transform is world-aligned. The engine does not rotate
	// normals for each curved strip section, so recover its actual texture axes.
	vec2 dx = dFdx(body_position);
	vec2 dy = dFdy(body_position);
	vec2 ux = dFdx(scale_uv);
	vec2 uy = dFdy(scale_uv);
	float det = ux.x * uy.y - ux.y * uy.x;
	if (abs(det) > 0.000001) {
		vec2 tangent = (dx * uy.y - dy * ux.y) / det;
		vec2 bitangent = (dy * ux.x - dx * uy.x) / det;
		if (dot(tangent, tangent) > 0.000001 && dot(bitangent, bitangent) > 0.000001) {
			vec2 planar = normalize(tangent) * n.x + normalize(bitangent) * n.y;
			// NORMAL_MAP is encoded in the 3D convention; Godot flips its Y once.
			n.xy = planar;
		} else {
			n = vec3(0.0, 0.0, 1.0);
		}
	} else {
		n = vec3(0.0, 0.0, 1.0);
	}
	// NORMAL_MAP Z is used directly by Godot; only XY uses encoded/green-flipped storage.
	NORMAL_MAP = vec3(n.xy * vec2(0.5, -0.5) + vec2(0.5), n.z);
}
