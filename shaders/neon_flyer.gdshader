// Cité Néon — drones-taxis qui traversent : trajectoires rectilignes en boucle, entièrement animées ici.
// Transformée d'instance = milieu de la trajectoire et cap (le maillage avance vers son -z local) ;
// INSTANCE_CUSTOM = vitesse (m/s), longueur (m), phase 0..1, teinte 0..1.
// COLOR du maillage : rgb couleur, a = 1 lumineux.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 body_tints[4];
uniform float glow = 3.0;

varying vec4 vcol;
varying float vtint;
varying vec3 vnrm;

void vertex() {
	vec4 prm = INSTANCE_CUSTOM;
	float len = prm.y;
	float s = mod(TIME * prm.x + prm.z * len, len) - len * 0.5;
	vec3 v = VERTEX;
	float roll = sin(TIME * 0.9 + prm.z * 9.0) * 0.08;
	v.y += v.x * roll + sin(TIME * 1.3 + prm.z * 20.0) * 0.2;
	v.z -= s;
	VERTEX = v;
	vcol = COLOR;
	vtint = prm.w;
	vnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 c = vcol.rgb;
	if (vcol.a > 0.5) {
		ALBEDO = c * glow;
	} else {
		int k = clamp(int(vtint * 4.0), 0, 3);
		// carrosserie jaune du maillage remplacée par la teinte de la flotte ; ombrée par le haut
		vec3 base = (c.r > 0.5 && c.g > 0.5 && c.b < 0.4) ? body_tints[k] : c;
		ALBEDO = base * (0.3 + 0.35 * max(normalize(vnrm).y, 0.0)) + vec3(0.06, 0.02, 0.08);
	}
}
