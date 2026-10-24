// Disques additifs orientés en MultiMesh (scripts/fx/fx_pool.gd) : ondes au sol, ondes hexagonales du bouclier,
// lueurs au sol, sceaux d'apparition. Données d'instance :
//   colonne 0 = centre, colonne 1 = normale du disque, colonne 2 = (t0, vie, style),
//   origine = (taille début, taille fin, épaisseur), COLOR = couleur (× 4), CUSTOM = (remplissage, rotation, graine, -).
// Styles : 0 onde, 1 onde hexagonale, 2 lueur pleine, 3 sceau d'apparition.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float fx_time = 0.0;
uniform float energy = 1.6;

varying vec4 v_col;
varying vec4 v_prm;  // x = âge relatif, y = style, z = épaisseur, w = remplissage
varying float v_rot;

void vertex() {
	vec3 c = MODEL_MATRIX[0].xyz;
	vec3 n = normalize(MODEL_MATRIX[1].xyz);
	vec3 c2 = MODEL_MATRIX[2].xyz;
	vec3 c3 = MODEL_MATRIX[3].xyz;
	float age = fx_time - c2.x;
	if (age < 0.0 || age >= c2.y) {
		VERTEX = vec3(0.0);
		v_col = vec4(0.0);
		v_prm = vec4(1.0);
		v_rot = 0.0;
	} else {
		float x = age / c2.y;
		float e = 1.0 - pow(1.0 - x, 3.0);
		float size = mix(c3.x, c3.y, e);
		vec3 tg = abs(n.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n));
		vec3 bt = cross(n, tg);
		vec3 w = c + (tg * VERTEX.x + bt * VERTEX.y) * size;
		VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
		v_col = vec4(COLOR.rgb * 4.0, COLOR.a);
		v_prm = vec4(x, c2.z, c3.z, INSTANCE_CUSTOM.x);
		v_rot = INSTANCE_CUSTOM.z * 6.2832 + INSTANCE_CUSTOM.y * age;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

float hexd(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float x = v_prm.x;
	int style = int(v_prm.y + 0.5);
	float w = v_prm.z;
	float a = 0.0;
	if (style == 0) {
		float ring = smoothstep(1.0 - w, 1.0 - w * 0.45, r) * smoothstep(1.0, 1.0 - w * 0.3, r);
		a = ring + v_prm.w * pow(r, 3.0);
		a *= 1.0 - x * x;
	} else if (style == 1) {
		// grille hexagonale révélée par un front qui s'élargit
		vec2 g = p * 5.0;
		vec2 rr = vec2(1.0, 1.7320508);
		vec2 h = rr * 0.5;
		vec2 ga = mod(g, rr) - h;
		vec2 gb = mod(g - h, rr) - h;
		vec2 gv = dot(ga, ga) < dot(gb, gb) ? ga : gb;
		float edge = smoothstep(0.36, 0.48, hexd(gv));
		float front = exp(-pow((r - (0.25 + 0.75 * sqrt(x))) / 0.18, 2.0));
		float core = exp(-r * r * 9.0) * (1.0 - x);
		a = (edge * (0.25 + front) * smoothstep(1.0, 0.7, r) + front * 0.35 + core) * (1.0 - x);
	} else if (style == 2) {
		a = pow(1.0 - r, 2.0) * (1.0 - x);
	} else {
		float ang = atan(p.y, p.x) + v_rot;
		float seg = smoothstep(0.35, 0.45, abs(fract(ang / 6.2832 * 10.0) - 0.5));
		float outer = smoothstep(0.78, 0.84, r) * smoothstep(0.98, 0.92, r) * (0.35 + 0.65 * seg);
		float inner = smoothstep(0.52, 0.56, r) * smoothstep(0.64, 0.6, r);
		float glow = pow(1.0 - r, 1.5) * 0.35;
		a = (outer + inner * 0.8 + glow) * min(1.0, x * 8.0) * (1.0 - x * x);
	}
	ALBEDO = v_col.rgb * energy;
	ALPHA = clamp(a * v_col.a, 0.0, 1.0);
}
