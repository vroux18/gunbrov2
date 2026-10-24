// Cité Néon — brume colorée basse : quads additifs (un seul maillage), bords fondus, nappes qui dérivent.
// COLOR = teinte * énergie ; UV 0..1 sur le quad ; UV2 = échelle du bruit ;
// CUSTOM0 = graine, fondu vers le haut (1 pour les quads debout), largeur du fondu des bords.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 flow = vec2(0.03, 0.01);

varying vec4 prm;
varying vec2 scl;

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	prm = CUSTOM0;
	scl = UV2;
}

void fragment() {
	vec2 p = UV * scl + prm.x * 13.1;
	float t = TIME;
	float n = vn(p + flow * t * 10.0) * 0.6 + vn(p * 2.1 - flow.yx * t * 14.0) * 0.4;
	vec2 e = min(UV, 1.0 - UV) / prm.z;
	float fade = clamp(min(e.x, e.y), 0.0, 1.0);
	fade *= fade;
	fade *= mix(1.0, UV.y * UV.y, prm.y);
	float k = smoothstep(0.25, 0.85, n) * fade;
	ALBEDO = COLOR.rgb * k;
}
