// Cité Néon — plan des dalles du toit (partagé par le sol et les marquages peints).
// layout_tex : une case = un texel RGBA8 : R graine, G bords (bits O N E S) + type << 4,
// B position de la case dans la pièce (x | z << 4), A variante | zone << 4.
// Types : 0 dalle de béton, 1 bitume, 2 siphon, 3 trappe, 4 lanterneau, 5 grille, 6 plaque, 7-8 caniveau à fente.

uniform sampler2D layout_tex : filter_nearest, repeat_disable;
uniform vec4 grid = vec4(0.32, 3.62, 1.189, 1.196);   // origine x, z, taille de case x, z
uniform vec2 grid_n = vec2(31.0, 15.0);
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 macro_rect = vec4(0.0, 3.3, 37.5, 18.75);
uniform vec3 heli = vec3(18.75, 12.59, 4.1);

vec4 nr_cell(vec2 p, out vec2 f, out bool inside) {
	vec2 g = (p - grid.xy) / grid.zw;
	vec2 c = floor(g);
	f = g - c;
	inside = c.x >= 0.0 && c.y >= 0.0 && c.x < grid_n.x && c.y < grid_n.y;
	ivec2 ci = ivec2(clamp(c, vec2(0.0), grid_n - 1.0));
	return texelFetch(layout_tex, ci, 0);
}

int nr_byte(float v) {
	return int(v * 255.0 + 0.5);
}

// distance au joint le plus proche (m) et pente du chanfrein
float nr_edges(vec2 pc, int flags, float chamfer, out vec2 slope) {
	float big = 100.0;
	float dW = (flags & 1) != 0 ? pc.x : big;
	float dN = (flags & 2) != 0 ? pc.y : big;
	float dE = (flags & 4) != 0 ? grid.z - pc.x : big;
	float dS = (flags & 8) != 0 ? grid.w - pc.y : big;
	float d = min(min(dW, dE), min(dN, dS));
	vec2 g = d == dW ? vec2(1.0, 0.0) : (d == dE ? vec2(-1.0, 0.0) : (d == dN ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
	slope = -g * (1.0 - smoothstep(0.004, chamfer, d)) * 0.9;
	return d;
}

vec4 nr_macro(vec2 p) {
	return texture(macro_tex, (p - macro_rect.xy) / macro_rect.zw);
}

// gouttes de pluie dans l'eau : anneaux qui s'élargissent (pente xz du relief)
vec2 nr_ripples(vec2 p, float t) {
	vec2 acc = vec2(0.0);
	for (int l = 0; l < 2; l++) {
		float s = l == 0 ? 0.45 : 0.31;
		vec2 q = p / s + float(l) * 17.3;
		vec2 c = floor(q);
		float h = fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
		float h2 = fract(sin(dot(c, vec2(269.5, 183.3))) * 43758.5453);
		vec2 ctr = c + 0.25 + 0.5 * vec2(h, h2);
		float ph = fract(t * (0.9 + 0.5 * h) + h2);
		vec2 dv = (q - ctr);
		float d = length(dv);
		float r = ph * 0.55;
		float w = 0.045;
		float ring = (d - r) / w;
		float a = exp(-ring * ring) * (1.0 - ph) * (1.0 - ph);
		float wave = sin(ring * 3.14159) * a;
		acc += dv / max(d, 1e-3) * wave * 0.045;
	}
	return acc;
}
