// Cité Néon — brume colorée basse : quads additifs, bords fondus, nappes qui dérivent (bruit de valeur).
// UV 0..1 sur le quad ; COLOR (sommets du quad, ou matériau) teinte.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.7, 0.2, 0.6);
uniform float energy = 0.35;
uniform vec2 scale = vec2(4.0, 2.0);
uniform vec2 flow = vec2(0.03, 0.01);
uniform float edge = 0.25;
uniform float seed = 0.0;
// fondu vertical (quads debout) : 1 = le haut du quad s'efface
uniform float rise = 0.0;

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

void fragment() {
	vec2 p = UV * scale + seed * 13.1;
	float t = TIME;
	float n = vn(p + flow * t * 10.0) * 0.6 + vn(p * 2.1 - flow.yx * t * 14.0) * 0.4;
	vec2 e = min(UV, 1.0 - UV) / edge;
	float fade = clamp(min(e.x, e.y), 0.0, 1.0);
	fade *= fade;
	fade *= mix(1.0, UV.y * UV.y, rise);
	float k = smoothstep(0.25, 0.85, n) * fade;
	ALBEDO = tint * energy * k;
}
