// Cité Néon — éclaboussures de pluie sur le toit : anneaux qui s'ouvrent et gouttelettes, posés au hasard
// autour du point visé (positions repliées), renouvelés à chaque cycle. Seulement entre les parapets.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;

uniform vec2 box = vec2(26.0, 20.0);
uniform vec4 roof = vec4(0.36, 3.66, 37.14, 21.52);   // x0, z0, x1, z1
uniform float period = 0.55;
uniform float size = 0.22;
uniform vec3 tint : source_color = vec3(0.7, 0.75, 1.0);
uniform float alpha = 0.3;

varying float vage;
varying float valive;

vec3 h3(float n) {
	return fract(sin(vec3(n * 12.9898, n * 78.233, n * 37.719)) * 43758.5453);
}

void vertex() {
	// point du sol visé par la caméra
	vec3 cpos = INV_VIEW_MATRIX[3].xyz;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 aim = cpos + fwd * (cpos.y / max(-fwd.y, 0.2));
	float id = float(INSTANCE_ID);
	vec3 s = h3(id + 0.71);
	float ph = TIME / period + s.z;
	float cyc = floor(ph);
	vage = fract(ph);
	vec3 r = h3(id * 1.37 + cyc * 7.13);
	vec2 p = r.xy * box;
	p = aim.xz + mod(p - aim.xz + box * 0.5, box) - box * 0.5;
	valive = step(roof.x, p.x) * step(p.x, roof.z) * step(roof.y, p.y) * step(p.y, roof.w);
	float sz = size * (0.6 + 0.8 * r.z);
	VERTEX = vec3(p.x, 0.012, p.y) + vec3(VERTEX.x, 0.0, VERTEX.z) * sz * valive;
}

void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float rad = 0.2 + vage * 0.8;
	float ring = exp(-pow((d - rad) / 0.05, 2.0)) * (1.0 - vage) * (1.0 - vage);
	// gouttelettes projetées
	float a = atan(q.y, q.x);
	float drops = step(0.82, fract(a * 1.59 + 0.3)) * exp(-pow((d - rad * 0.75) / 0.06, 2.0)) * (1.0 - vage) * step(vage, 0.5);
	float k = (ring + drops * 1.5) * valive;
	ALBEDO = tint * alpha * k;
}
