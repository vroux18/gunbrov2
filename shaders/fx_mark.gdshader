// Marques d'impact sur le décor (faces des caisses) en MultiMesh (scripts/fx/fx_pool.gd, fx3d.wall_impact) :
// éclat de peinture sombre et irrégulier, plaqué sur la face touchée, cœur chauffé qui rougeoie puis refroidit,
// fondu en fin de vie. Données d'instance : colonne 0 = centre, colonne 1 = normale de la face,
// colonne 2 = (t0, vie, -), origine = (taille, chaleur, -), COLOR = teinte de la tache, CUSTOM = (couleur chaude × 4, graine).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float fx_time = 0.0;
uniform float cool = 2.5;  // vitesse de refroidissement du cœur (1/s)

varying vec4 v_col;
varying vec4 v_hot;  // rgb = couleur chaude, a = chaleur
varying vec3 v_prm;  // x = âge relatif, y = âge (s), z = graine

void vertex() {
	vec3 c = MODEL_MATRIX[0].xyz;
	vec3 n = normalize(MODEL_MATRIX[1].xyz);
	vec3 c2 = MODEL_MATRIX[2].xyz;
	vec3 c3 = MODEL_MATRIX[3].xyz;
	float age = fx_time - c2.x;
	if (age < 0.0 || age >= c2.y) {
		VERTEX = vec3(0.0);
		v_col = vec4(0.0);
		v_hot = vec4(0.0);
		v_prm = vec3(1.0, 0.0, 0.0);
	} else {
		// la marque s'ouvre en un éclair (l'impact), puis ne bouge plus
		float size = c3.x * (0.55 + 0.45 * min(age * 25.0, 1.0));
		vec3 tg = abs(n.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n));
		vec3 bt = cross(n, tg);
		float a = INSTANCE_CUSTOM.w * 6.2832;
		vec2 q = vec2(cos(a) * VERTEX.x - sin(a) * VERTEX.y, sin(a) * VERTEX.x + cos(a) * VERTEX.y);
		vec3 w = c + (tg * q.x + bt * q.y) * size;
		VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
		v_col = COLOR;
		v_hot = vec4(INSTANCE_CUSTOM.rgb * 4.0, c3.y);
		v_prm = vec3(age / c2.y, age, INSTANCE_CUSTOM.w);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float ang = atan(p.y, p.x);
	float sd = v_prm.z * 40.0;
	// bord en étoile : peinture arrachée autour du trou
	float edge = 0.6 + 0.17 * sin(ang * 5.0 + sd) + 0.1 * sin(ang * 9.0 - sd * 1.7) + 0.06 * sin(ang * 13.0 + sd * 0.6);
	float m = smoothstep(edge, edge - 0.22, r);
	float hole = smoothstep(0.3, 0.12, r);
	float heat = v_hot.a * exp(-v_prm.y * cool);
	float fade = 1.0 - smoothstep(0.65, 1.0, v_prm.x);
	vec3 col = mix(v_col.rgb, v_col.rgb * 0.35, hole);
	// cœur chaud : rougeoie dans le trou et sur le bord proche, s'éteint en quelques dixièmes
	float glow = heat * (hole + 0.35 * m * smoothstep(0.7, 0.2, r));
	col = mix(col, v_hot.rgb, clamp(glow, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp((m * 0.8 + hole * 0.2) * v_col.a + glow, 0.0, 1.0) * fade;
}
