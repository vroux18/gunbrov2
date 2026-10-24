// Écran holographique du Relais : cadre lumineux, lignes de balayage, contenu dessiné en code
// (kind 0 : courbes et barres de diagnostic ; 1 : schéma tournant d'une pièce ; 2 : fiche d'équipement).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(0.235, 0.949, 0.847, 1.0);
uniform vec4 col2 : source_color = vec4(1.0, 0.478, 0.184, 1.0);
uniform float energy = 1.0;
uniform int kind = 0;
uniform float seed = 0.0;

float box(vec2 p, vec2 a, vec2 b) {
	vec2 s = step(a, p) * step(p, b);
	return s.x * s.y;
}

float line(float d, float w) {
	return smoothstep(w, 0.0, abs(d));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed * 10.0;
	vec2 c = uv - 0.5;
	// cadre arrondi et coins plus vifs
	vec2 q = abs(c) - vec2(0.47, 0.45);
	float frame = line(max(q.x, q.y), 0.012);
	float corner = step(0.38, abs(c.x)) * step(0.34, abs(c.y)) * frame * 1.5;
	float inside = step(max(q.x, q.y), 0.0);
	float a = frame * 0.9 + corner;
	vec3 rgb = col.rgb;
	if (kind == 0) {
		// courbe qui défile
		float y = 0.62 + 0.12 * sin(uv.x * 18.0 - t * 2.0) * sin(uv.x * 5.0 + t * 0.7);
		a += line(uv.y - y, 0.012) * inside * step(0.08, uv.x) * step(uv.x, 0.92);
		// barres
		float bx = floor((uv.x - 0.08) / 0.07);
		float h = 0.1 + 0.18 * (0.5 + 0.5 * sin(bx * 1.7 + t * 1.3 + seed));
		float bars = box(uv, vec2(0.08, 0.12), vec2(0.92, 0.12 + h)) * step(0.2, fract((uv.x - 0.08) / 0.07));
		a += bars * 0.55;
		rgb = mix(col.rgb, col2.rgb, bars * step(0.25, h));
	} else if (kind == 1) {
		// schéma : cercle denté qui tourne et réticule
		vec2 p = c * vec2(1.6, 1.0);
		float r = length(p);
		float ang = atan(p.y, p.x) + t * 0.8;
		float teeth = step(0.5, fract(ang * 12.0 / 6.2832));
		a += line(r - 0.28 - 0.03 * teeth, 0.01) * 1.2;
		a += line(r - 0.15, 0.008);
		a += line(p.x, 0.004) * step(r, 0.36) * 0.5 + line(p.y, 0.004) * step(r, 0.36) * 0.5;
		float blip = line(r - fract(t * 0.5) * 0.4, 0.01) * 0.6;
		a += blip;
	} else {
		// fiche : silhouette de casque, lignes de texte, jauge orange
		vec2 p = (uv - vec2(0.28, 0.55)) * vec2(1.7, 1.0);
		float hel = line(length(p) - 0.18, 0.012) * step(-0.02, p.y);
		a += hel * 1.2;
		for (int i = 0; i < 4; i++) {
			float yy = 0.72 - float(i) * 0.12;
			float len = 0.18 + 0.2 * fract(sin(float(i) * 12.9 + seed) * 43758.0);
			a += box(uv, vec2(0.52, yy - 0.012), vec2(0.52 + len, yy + 0.012)) * 0.7;
		}
		float g = box(uv, vec2(0.12, 0.14), vec2(0.12 + 0.76 * (0.6 + 0.3 * sin(t * 0.6)), 0.2));
		a += g;
		rgb = mix(col.rgb, col2.rgb, g);
	}
	// fond voilé, lignes de balayage, scintillement
	a += inside * 0.1;
	float scan = 0.75 + 0.25 * sin(uv.y * 260.0 - t * 6.0);
	float flick = 0.92 + 0.08 * sin(t * 37.0) * sin(t * 11.0);
	ALBEDO = rgb * energy;
	ALPHA = clamp(a * scan * flick, 0.0, 1.0);
}
