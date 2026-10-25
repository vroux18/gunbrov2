// Fond BD derrière Jo au Relais (scripts/decor/relais.gd) : éclat de couverture de bande dessinée, face caméra.
// Étoile à pointes cernée d'encre, rayons alternés qui tournent lentement, trame de points (plus gros vers le
// bord), le tout décalé d'un cran cyan / magenta comme une impression mal calée. Discret : opacité réglable.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform vec3 col_a : source_color = vec3(1.0, 0.24, 0.42);
uniform vec3 col_b : source_color = vec3(1.0, 0.48, 0.3);
uniform vec3 dot_col : source_color = vec3(0.42, 0.06, 0.32);
uniform vec3 ink : source_color = vec3(0.03, 0.02, 0.06);
uniform vec3 offset_col : source_color = vec3(0.2, 0.85, 1.0);
uniform float opacity = 0.7;
uniform float spikes = 15.0;
uniform float spin = 0.0;
uniform float dots = 26.0;

void vertex() {
	// face caméra, en gardant l'échelle du nœud
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
}

// rayon de l'étoile dans la direction `a` (pointes en dents de scie)
float star(float a, float k) {
	float f = fract(a / 6.2831853 * spikes + k);
	return 0.72 + 0.24 * (1.0 - abs(f * 2.0 - 1.0));
}

float shape(vec2 p, float k) {
	float a = atan(p.y, p.x);
	return length(p) / star(a, k);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float a = atan(p.y, p.x) + spin;
	float r = length(p);
	float s = shape(p, 0.0);
	// cran de couleur décalé (cyan) qui dépasse en bas à gauche
	float s2 = shape(p + vec2(0.045, 0.035), 0.0);
	float inside = 1.0 - step(1.0, s);
	float inside2 = 1.0 - step(1.0, s2);
	float rim = step(0.9, s) * inside;
	// rayons alternés
	float ray = step(0.5, fract(a / 6.2831853 * spikes * 0.5));
	vec3 c = mix(col_a, col_b, ray * 0.55);
	// trame : grille tournée à 45°, points plus gros vers le bord
	vec2 g = vec2(p.x + p.y, p.y - p.x) * 0.7071 * dots;
	float dr = 0.12 + 0.3 * smoothstep(0.15, 0.85, s);
	float d = 1.0 - step(dr, length(fract(g) - 0.5));
	c = mix(c, dot_col, d * 0.75);
	c = mix(c, ink, rim);
	// cœur clair derrière le buste
	c = mix(c, vec3(1.0, 0.85, 0.75), (1.0 - smoothstep(0.0, 0.45, r)) * 0.35);
	float al = inside;
	vec3 outc = c;
	if (inside < 0.5 && inside2 > 0.5) {
		outc = offset_col;
		al = 0.8;
	}
	ALBEDO = outc;
	ALPHA = al * opacity;
}
