// Balises du quai nord (baie 07) : lueur à la couleur des sommets qui clignote en chenillard le long de x.
// Utilisable en MultiMesh : la phase vient de la position de l'instance dans le monde.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform float energy = 2.4;
uniform float speed = 0.55;   // tours par seconde
uniform float spread = 0.09;  // décalage de phase par mètre (chenillard)
uniform float duty = 0.22;    // part du cycle allumée
uniform float floor_level = 0.12;  // lueur résiduelle éteinte

varying float v_phase;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_phase = o.x * spread + o.z * 0.031;
}

void fragment() {
	float p = fract(TIME * speed - v_phase);
	float on = smoothstep(0.0, 0.04, p) * (1.0 - smoothstep(duty, duty + 0.12, p));
	ALBEDO = srgb_to_linear(COLOR.rgb) * energy * mix(floor_level, 1.0, on);
}
