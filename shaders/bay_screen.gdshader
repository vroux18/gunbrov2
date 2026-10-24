// Écrans des consoles du quai nord : petit affichage animé, sobre (lisible sans voler l'attention au jeu).
// mode 0 : manifeste de fret qui défile ; 1 : barres de niveaux ; 2 : radar à balayage ; 3 : courbe de pompe.
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled;

uniform int mode = 0;
uniform vec3 ink : source_color = vec3(0.24, 0.95, 0.85);
uniform vec3 accent : source_color = vec3(1.0, 0.48, 0.18);
uniform vec3 paper : source_color = vec3(0.02, 0.06, 0.08);
uniform float energy = 0.9;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed * 7.3;
	vec3 col = paper;
	float lum = 0.0;
	vec3 acc = vec3(0.0);
	if (mode == 0) {
		// lignes de texte factices qui défilent vers le haut, une ligne surlignée
		float rows = 9.0;
		float y = uv.y * rows + t * 0.6;
		float row = floor(y);
		float fy = fract(y);
		float len = 0.35 + 0.55 * hash(vec2(row, 1.0));
		float cells = floor(uv.x * 22.0);
		float word = step(0.18, hash(vec2(row, cells))) * step(uv.x, len) * step(0.06, uv.x);
		lum = word * step(0.3, fy) * step(fy, 0.7) * 0.8;
		float hi = step(0.92, hash(vec2(row, 3.0)));
		acc = accent * hi * step(0.2, fy) * step(fy, 0.8) * 0.35;
	} else if (mode == 1) {
		float bars = 7.0;
		float b = floor(uv.x * bars);
		float fb = fract(uv.x * bars);
		float h = 0.25 + 0.6 * (0.5 + 0.5 * sin(t * (0.7 + hash(vec2(b, 2.0)) * 1.3) + b * 1.7));
		float inside = step(0.15, fb) * step(fb, 0.85) * step(1.0 - uv.y, h) * step(0.08, 1.0 - uv.y);
		lum = inside * 0.85;
		acc = accent * inside * step(0.8, h) * 0.6;
	} else if (mode == 2) {
		vec2 c = uv - vec2(0.5);
		c.x *= 1.6;
		float r = length(c);
		float a = atan(c.y, c.x);
		float sweep = fract((a / 6.2831853) - t * 0.25);
		lum = (1.0 - smoothstep(0.0, 0.35, sweep)) * 0.7 * step(r, 0.45);
		lum += (step(abs(r - 0.42), 0.01) + step(abs(r - 0.24), 0.008)) * 0.5;
		float blip = step(length(c - vec2(0.18 * sin(seed * 3.0), 0.12)), 0.03);
		acc = accent * blip * (0.5 + 0.5 * sin(t * 4.0));
	} else {
		float x = uv.x * 6.0 - t * 0.8;
		float y = 0.5 + 0.22 * sin(x * 2.1) * sin(x * 0.7 + 1.3);
		lum = (1.0 - smoothstep(0.0, 0.035, abs((1.0 - uv.y) - y))) * 0.9;
		lum += step(fract(uv.x * 6.0), 0.03) * 0.15 + step(fract(uv.y * 4.0), 0.04) * 0.15;
		acc = accent * step(0.9, uv.x) * step(0.1, uv.y) * step(uv.y, 0.25) * (0.5 + 0.5 * step(0.5, fract(t)));
	}
	// lignes de balayage, léger scintillement, vignette
	float scan = 0.82 + 0.18 * sin(uv.y * 160.0);
	float vig = smoothstep(0.0, 0.08, uv.x) * smoothstep(0.0, 0.08, 1.0 - uv.x) * smoothstep(0.0, 0.1, uv.y) * smoothstep(0.0, 0.1, 1.0 - uv.y);
	col = paper + (ink * lum + acc) * scan;
	col *= mix(0.55, 1.0, vig) * (0.96 + 0.04 * sin(t * 31.0));
	ALBEDO = col * energy;
}
