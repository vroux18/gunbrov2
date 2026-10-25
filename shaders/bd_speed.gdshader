// Traits de vitesse BD derrière Jo pendant sa ruée (scripts/fx/bd_fx.gd) : quelques traits blancs cernés d'encre,
// de longueurs inégales, qui s'effilent vers l'arrière. UV.x : 0 contre Jo, 1 au bout de la traînée.
// `seed` change 12 fois par seconde (animation « en deux », comme Jo).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform float alpha = 1.0;
uniform float seed = 0.0;
uniform float lanes = 6.0;
uniform vec3 core : source_color = vec3(1.0, 0.98, 0.92);
uniform vec3 ink : source_color = vec3(0.03, 0.02, 0.06);

float hash(float n) {
	return fract(sin(n * 91.345 + seed * 47.13) * 43758.5453);
}

void fragment() {
	float lane = floor(UV.y * lanes);
	float fy = abs(fract(UV.y * lanes) - 0.5);
	float on = step(0.35, hash(lane));  // une voie sur trois reste vide
	float start = hash(lane + 7.0) * 0.35;
	float len = 0.35 + hash(lane + 13.0) * 0.6;
	float u = (UV.x - start) / len;
	float inside = step(0.0, u) * step(u, 1.0);
	// trait qui s'effile : épais près de Jo, pointu au bout
	float w = 0.3 * (1.0 - u * 0.85);
	float body = 1.0 - step(w, fy);
	float c = 1.0 - step(w * 0.55, fy);
	// les voies du bord sont plus courtes et plus pâles
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	float a = body * inside * on * smoothstep(0.0, 0.25, edge);
	ALBEDO = mix(ink, core, c);
	ALPHA = a * alpha * (1.0 - u * 0.6);
}
