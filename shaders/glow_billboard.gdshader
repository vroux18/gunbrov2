// Quad toujours face caméra, additif, teinté par la couleur d'instance (MultiMesh) : halos, particules, flashs.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D tex : source_color, filter_linear;
uniform float energy = 1.6;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec4 c = VIEW_MATRIX * vec4(center, 1.0);
	VERTEX = c.xyz + vec3(VERTEX.x * sx, VERTEX.y * sy, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = COLOR.rgb * tint.rgb * t.rgb * energy;
	ALPHA = t.a * COLOR.a * tint.a;
}
