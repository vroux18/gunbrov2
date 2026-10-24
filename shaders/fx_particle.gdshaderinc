// Particule analytique en MultiMesh (scripts/fx/fx_pool.gd) : le CPU écrit une instance à l'émission,
// la carte calcule mouvement, taille, couleur et fondu à partir de l'âge. Données d'instance :
//   colonne 0 = position de départ, colonne 1 = vitesse, colonne 2 = (t0, vie, gravité),
//   origine = (taille début, taille fin, frein), COLOR = couleur de départ (× 4),
//   CUSTOM = (couleur de fin × 4, param) ; param > 0 : étirement le long de la vitesse (s), < 0 : graine de rotation.
uniform float fx_time = 0.0;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float energy = 1.0;
uniform float fade_in = 0.0;   // part de la vie pour apparaître
uniform float fade_pow = 1.0;  // courbe de disparition
uniform float rise = 0.0;      // poussée vers le haut (fumée), m/s²
uniform float spin = 3.0;      // vitesse de rotation max (rad/s)

varying vec4 v_col;
varying float v_x;
varying float v_str;  // 1 : particule étirée (traînée, étincelle)

void vertex() {
	vec3 p0 = MODEL_MATRIX[0].xyz;
	vec3 v0 = MODEL_MATRIX[1].xyz;
	vec3 c2 = MODEL_MATRIX[2].xyz;
	vec3 c3 = MODEL_MATRIX[3].xyz;
	float age = fx_time - c2.x;
	if (age < 0.0 || age >= c2.y) {
		VERTEX = vec3(0.0);
		v_col = vec4(0.0);
		v_x = 1.0;
		v_str = 0.0;
	} else {
		float x = age / c2.y;
		float k = c3.z;
		float ek = exp(-k * age);
		float f = k > 0.001 ? (1.0 - ek) / k : age;
		vec3 pos = p0 + v0 * f;
		pos.y += (rise - c2.z) * 0.5 * age * age;
		vec3 vel = v0 * ek + vec3(0.0, (rise - c2.z) * age, 0.0);
		float e = 1.0 - (1.0 - x) * (1.0 - x);
		float size = mix(c3.x, c3.y, e);
		vec3 vc = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
		float prm = INSTANCE_CUSTOM.w;
		vec2 q = VERTEX.xy;
		v_str = prm > 0.0 ? 1.0 : 0.0;
		if (prm > 0.0) {
			vec3 tail = (VIEW_MATRIX * vec4(pos - vel * prm, 1.0)).xyz;
			vec2 d = vc.xy - tail.xy;
			float L = length(d);
			vec2 ax = L > 1e-4 ? d / L : vec2(0.0, 1.0);
			vec2 side = vec2(-ax.y, ax.x);
			vec3 mid = (vc + tail) * 0.5;
			VERTEX = mid + vec3(side * q.x * size + ax * q.y * (L + size), 0.0);
		} else {
			float a = -prm * 6.2832 + age * (fract(-prm * 13.71) - 0.5) * 2.0 * spin;
			float ca = cos(a);
			float sa = sin(a);
			VERTEX = vc + vec3(ca * q.x - sa * q.y, sa * q.x + ca * q.y, 0.0) * size;
		}
		vec3 c = mix(COLOR.rgb, INSTANCE_CUSTOM.rgb, x) * 4.0;
		float fi = fade_in > 0.0 ? clamp(x / fade_in, 0.0, 1.0) : 1.0;
		v_col = vec4(c, COLOR.a * fi * pow(1.0 - x, fade_pow));
		v_x = x;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}
