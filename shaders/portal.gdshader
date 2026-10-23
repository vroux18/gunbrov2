// Disque de portail : tourbillon de lumière (Relais).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 col_a : source_color = vec4(0.235, 0.949, 0.847, 1.0);
uniform vec4 col_b : source_color = vec4(0.55, 0.25, 0.95, 1.0);
uniform float energy = 1.4;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float swirl = a + r * 4.0 - TIME * 1.6;
	// bruit échantillonné sur un cercle : pas de couture à l'angle ±PI
	vec2 q = vec2(cos(swirl), sin(swirl));
	float n = noise(q * 2.2 + vec2(r * 6.0 - TIME * 0.7, 0.0)) * 0.6 + noise(q * 5.0 + vec2(0.0, r * 12.0)) * 0.4;
	float edge = smoothstep(1.0, 0.82, r);
	float center = smoothstep(0.9, 0.0, r);
	vec3 c = mix(col_b.rgb, col_a.rgb, n) * (0.35 + n * 0.9) + col_a.rgb * pow(1.0 - r, 3.0) * 1.5;
	ALBEDO = c * energy;
	ALPHA = edge * (0.35 + 0.65 * n) * (0.4 + 0.6 * center);
}
