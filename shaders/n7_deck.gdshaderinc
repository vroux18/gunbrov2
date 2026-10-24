// Nébuleuse 7 — plan des tôles du pont (partagé par le sol et les marquages peints).
// layout_tex : une case = un texel RGBA8 : R graine de la tôle, G bords à joint (bits O N E S) + type << 4,
// B position de la case dans la tôle (x | z << 4), A variante (0 d'origine, 1 remplacée, 2 très usée).

uniform sampler2D layout_tex : filter_nearest, repeat_disable;
uniform vec4 grid = vec4(0.5625, 3.90625, 0.7578125, 0.0);  // origine x, z, taille de case
uniform vec2 grid_n = vec2(48.0, 23.0);

// lit la case sous p (xz monde) ; f = position dans la case (0..1)
vec4 n7_cell(vec2 p, out vec2 f, out bool inside) {
	vec2 g = (p - grid.xy) / grid.z;
	vec2 c = floor(g);
	f = g - c;
	inside = c.x >= 0.0 && c.y >= 0.0 && c.x < grid_n.x && c.y < grid_n.y;
	ivec2 ci = ivec2(clamp(c, vec2(0.0), grid_n - 1.0));
	return texelFetch(layout_tex, ci, 0);
}

int n7_byte(float v) {
	return int(v * 255.0 + 0.5);
}

// joints, chanfreins et rivets d'une case : rend la distance au joint le plus proche (m),
// la normale monde du relief et le masque des rivets (riv) avec leur ombre (riv_ao).
float n7_edges(vec2 pc, int flags, bool rivets, out vec3 nrm, out float riv, out float riv_ao) {
	float c = grid.z;
	float big = 100.0;
	float dW = (flags & 1) != 0 ? pc.x : big;
	float dN = (flags & 2) != 0 ? pc.y : big;
	float dE = (flags & 4) != 0 ? c - pc.x : big;
	float dS = (flags & 8) != 0 ? c - pc.y : big;
	float d = min(min(dW, dE), min(dN, dS));
	vec2 g = d == dW ? vec2(1.0, 0.0) : (d == dE ? vec2(-1.0, 0.0) : (d == dN ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
	g *= (1.0 - smoothstep(0.006, 0.028, d)) * 0.85;
	nrm = normalize(vec3(-g.x, 1.0, -g.y));
	riv = 0.0;
	riv_ao = 1.0;
	if (rivets) {
		float sp = c / 3.0;
		float ins = 0.05;
		float rr = 0.016;
		vec2 best = vec2(big);
		vec2 q;
		if (dW < 0.1) { q = vec2(pc.x - ins, pc.y - (floor(pc.y / sp) + 0.5) * sp); if (dot(q, q) < dot(best, best)) best = q; }
		if (dE < 0.1) { q = vec2(pc.x - (c - ins), pc.y - (floor(pc.y / sp) + 0.5) * sp); if (dot(q, q) < dot(best, best)) best = q; }
		if (dN < 0.1) { q = vec2(pc.x - (floor(pc.x / sp) + 0.5) * sp, pc.y - ins); if (dot(q, q) < dot(best, best)) best = q; }
		if (dS < 0.1) { q = vec2(pc.x - (floor(pc.x / sp) + 0.5) * sp, pc.y - (c - ins)); if (dot(q, q) < dot(best, best)) best = q; }
		float r = length(best) / rr;
		riv = 1.0 - smoothstep(0.8, 1.0, r);
		riv_ao = mix(0.55, 1.0, smoothstep(0.9, 1.6, r));
		if (r < 1.0) {
			vec2 qq = best / rr;
			nrm = normalize(mix(nrm, vec3(qq.x, sqrt(max(1.0 - dot(qq, qq), 0.05)), qq.y), riv));
		}
	}
	return d;
}
