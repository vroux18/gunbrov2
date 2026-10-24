// Brûlures au sol en MultiMesh (cratères d'obus, explosions) : tache sombre bosselée, braises qui refroidissent.
// Données d'instance : colonne 0 = centre, colonne 2 = (t0, vie, -), origine = (taille début, taille fin, braises),
// COLOR = teinte de la tache, CUSTOM = (couleur des braises × 4, graine).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float fx_time = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap;

varying vec4 v_col;
varying vec4 v_emb;
varying vec2 v_prm;  // x = âge relatif, y = braises

void vertex() {
	vec3 c = MODEL_MATRIX[0].xyz;
	vec3 c2 = MODEL_MATRIX[2].xyz;
	vec3 c3 = MODEL_MATRIX[3].xyz;
	float age = fx_time - c2.x;
	if (age < 0.0 || age >= c2.y) {
		VERTEX = vec3(0.0);
		v_col = vec4(0.0);
		v_emb = vec4(0.0);
		v_prm = vec2(1.0, 0.0);
	} else {
		float x = age / c2.y;
		float size = mix(c3.x, c3.y, 1.0 - pow(1.0 - min(x * 6.0, 1.0), 3.0));
		float a = INSTANCE_CUSTOM.w * 6.2832;
		vec2 q = vec2(cos(a) * VERTEX.x - sin(a) * VERTEX.y, sin(a) * VERTEX.x + cos(a) * VERTEX.y);
		vec3 w = c + vec3(q.x, 0.0, q.y) * size;
		VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
		v_col = COLOR;
		v_emb = vec4(INSTANCE_CUSTOM.rgb * 4.0, 1.0);
		v_prm = vec2(x, c3.z);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	float x = v_prm.x;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float fade = 1.0 - smoothstep(0.55, 1.0, x);
	float dens = smoothstep(0.05, 0.6, t.a);
	// braises : anneau chaud irrégulier près du centre, qui s'éteint vite
	float hot = v_prm.y * pow(max(0.0, 1.0 - x * 2.2), 1.5);
	float emb = hot * smoothstep(0.75, 0.2, r) * (0.4 + 0.6 * t.r) * smoothstep(0.3, 0.8, t.a);
	ALBEDO = mix(v_col.rgb * (0.7 + 0.3 * t.r), v_emb.rgb, clamp(emb, 0.0, 1.0));
	ALPHA = clamp(dens * v_col.a * fade + emb * 0.5, 0.0, 1.0);
}
