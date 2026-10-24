// Jo de l'invité (mode duo) : mêmes modèles sculptés à couleurs par sommet, autre palette pour se reconnaître.
// Les teintes saturées tournent (orange -> violet, turquoise -> jaune), les blancs prennent une pointe de lilas.
// Mêmes réglages de surface que body_mat() (scripts/rig3d.gd).
shader_type spatial;

uniform float hue_shift = 0.7;
uniform vec3 tint : source_color = vec3(0.93, 0.9, 1.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 c = COLOR.rgb;  // sRGB
	vec3 hsv = rgb2hsv(c);
	float w = smoothstep(0.18, 0.4, hsv.y);
	vec3 shifted = hsv2rgb(vec3(fract(hsv.x + hue_shift), hsv.y, hsv.z));
	c = mix(c * tint, shifted, w);
	ALBEDO = pow(max(c, vec3(0.0)), vec3(2.2));
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	RIM = 0.45;
	RIM_TINT = 0.35;
}
