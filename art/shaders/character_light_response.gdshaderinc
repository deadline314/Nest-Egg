// Shared reflective response for ordinary parts and the surviving dissolve base.
uniform float fill = 1.0;
uniform float light_cap : hint_range(0.05, 4.0) = 0.5;

vec4 character_light_response(vec3 albedo, vec3 normal, vec3 direction, vec4 color, float energy) {
	float n_dot_l = max(0.0, dot(normal, direction));
	vec3 lit = color.rgb * energy * albedo * n_dot_l / max(fill, 0.0001);
	float peak = max(lit.r, max(lit.g, lit.b));
	float keep = peak > 0.0001 ? light_cap * tanh(peak / light_cap) / peak : 1.0;
	return vec4(lit * keep, color.a);
}

// Rigid sprites keep the published normal response. Actual mesh owners opt in once at setup.
instance uniform bool mesh_normal_basis = false;

vec3 character_mesh_normal(vec3 encoded, vec2 position, vec2 sampled_uv) {
	if (!mesh_normal_basis) { return encoded; }
	vec2 dx = dFdx(position);
	vec2 dy = dFdy(position);
	vec2 ux = dFdx(sampled_uv);
	vec2 uy = dFdy(sampled_uv);
	float det = ux.x * uy.y - ux.y * uy.x;
	if (abs(det) <= 0.000001) { return encoded; }
	vec2 tangent = (dx * uy.y - dy * ux.y) / det;
	vec2 bitangent = (dy * ux.x - dx * uy.x) / det;
	if (dot(tangent, tangent) <= 0.000001 || dot(bitangent, bitangent) <= 0.000001) { return encoded; }
	vec2 xy = encoded.xy * vec2(2.0, -2.0) - vec2(1.0, -1.0);
	xy = normalize(tangent) * xy.x + normalize(bitangent) * xy.y;
	// Preserve original NORMAL_MAP Z; Godot decodes only XY, then applies item/canvas axes.
	return vec3(xy * vec2(0.5, -0.5) + vec2(0.5), encoded.z);
}
