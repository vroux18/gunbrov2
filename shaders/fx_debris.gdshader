// Débris en MultiMesh (scripts/fx/fx_pool.gd) : éclats de coque lancés, qui tournent, rebondissent une fois au sol
// et rétrécissent en fin de vie. Données d'instance : colonne 0 = départ, colonne 1 = vitesse,
// colonne 2 = (t0, vie, gravité), origine = (taille, allongement, frein), COLOR = teinte,
// CUSTOM = (axe de rotation × vitesse, chaleur : lueur orange au départ).
shader_type spatial;
render_mode cull_back, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float fx_time = 0.0;
uniform float ground = 0.03;

varying float v_hot;
varying vec4 v_col;

vec3 rot(vec3 v, vec3 ax, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}

void vertex() {
	vec3 p0 = MODEL_MATRIX[0].xyz;
	vec3 v0 = MODEL_MATRIX[1].xyz;
	vec3 c2 = MODEL_MATRIX[2].xyz;
	vec3 c3 = MODEL_MATRIX[3].xyz;
	float age = fx_time - c2.x;
	if (age < 0.0 || age >= c2.y) {
		VERTEX = vec3(0.0);
		NORMAL = vec3(0.0, 0.0, 1.0);
		v_hot = 0.0;
		v_col = vec4(0.0);
	} else {
		float g = max(c2.z, 0.01);
		float sz = c3.x;
		float fl = ground + sz * 0.35;
		// vol balistique, un rebond amorti, puis posé
		float tl = (v0.y + sqrt(max(v0.y * v0.y + 2.0 * g * (p0.y - fl), 0.0))) / g;
		float y;
		float ts = age;
		if (age < tl) {
			y = p0.y + v0.y * age - 0.5 * g * age * age;
		} else {
			float vb = 0.32 * abs(v0.y - g * tl);
			float t2 = age - tl;
			float tb = 2.0 * vb / g;
			y = fl + (t2 < tb ? vb * t2 - 0.5 * g * t2 * t2 : 0.0);
			ts = tl + min(t2, tb) * 0.8 + min(t2, tb + 0.15) * 0.2;
		}
		float k = c3.z;
		float f = k > 0.001 ? (1.0 - exp(-k * ts)) / k : ts;
		vec3 pos = vec3(p0.x + v0.x * f, y, p0.z + v0.z * f);
		vec3 sp = INSTANCE_CUSTOM.xyz;
		float spd = length(sp);
		vec3 ax = spd > 0.001 ? sp / spd : vec3(0.0, 1.0, 0.0);
		float ang = spd * ts;
		float x = age / c2.y;
		float shrink = 1.0 - smoothstep(0.7, 1.0, x);
		vec3 lv = VERTEX * vec3(sz, sz * c3.y, sz) * shrink;
		vec3 wv = pos + rot(lv, ax, ang);
		VERTEX = (VIEW_MATRIX * vec4(wv, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(rot(NORMAL, ax, ang), 0.0)).xyz);
		v_hot = INSTANCE_CUSTOM.w * max(0.0, 1.0 - age * 2.5);
		v_col = COLOR;
	}
}

void fragment() {
	ALBEDO = v_col.rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	EMISSION = vec3(1.0, 0.45, 0.15) * v_hot * 2.5;
}
