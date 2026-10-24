// Cité Néon — écrans géants de la tour voisine : contenu animé (publicités en idéogrammes inventés, mascotte
// robot, égaliseur, bandeau défilant). Partagé par la façade (vue directe) et le toit (reflets dans les flaques).
// Les écrans sont des rectangles du plan de la façade (x, y en m).

uniform sampler2D glyph_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 glyph_rect = vec4(0.0, 0.0, 0.25, 0.25);  // planche 8 x 8 dans l'atlas
uniform vec4 ns_rect[4];   // x0, y0, x1, y1
uniform vec4 ns_mode[4];   // x mode (0 publicité, 1 colonne défilante), y graine, z luminosité

const vec3 NS_PINK = vec3(1.0, 0.045, 0.42);
const vec3 NS_BLUE = vec3(0.045, 0.26, 1.0);
const vec3 NS_VIOLET = vec3(0.27, 0.07, 1.0);
const vec3 NS_ACID = vec3(0.47, 1.0, 0.045);
const vec3 NS_ORANGE = vec3(1.0, 0.25, 0.045);
const vec3 NS_CYAN = vec3(0.045, 0.85, 0.7);

float ns_h(float n) {
	return fract(sin(n * 91.345 + 7.13) * 47453.5453);
}

vec3 ns_pal(float k) {
	int i = int(mod(floor(k), 5.0));
	return i == 0 ? NS_PINK : (i == 1 ? NS_BLUE : (i == 2 ? NS_VIOLET : (i == 3 ? NS_ACID : NS_ORANGE)));
}

// masque d'un idéogramme (id 0..63) en uv 0..1 (y vers le haut)
float ns_glyph(float id, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	float i = mod(floor(id), 64.0);
	vec2 cell = vec2(mod(i, 8.0), floor(i / 8.0));
	vec2 g = (cell + vec2(uv.x, 1.0 - uv.y)) / 8.0;
	return textureLod(glyph_tex, glyph_rect.xy + g * glyph_rect.zw, 0.0).r;
}

// ligne d'idéogrammes : uv dans la bande, n signes visibles, décalage (défilement)
float ns_line(vec2 uv, float n, float off, float seed) {
	float x = uv.x * n + off;
	float k = floor(x);
	vec2 g = vec2(fract(x) * 1.25 - 0.12, uv.y * 1.1 - 0.05);
	return ns_glyph(ns_h(k + seed) * 64.0, g);
}

vec3 ns_ad(vec2 uv, float aspect, float seed, float t) {
	float sc_t = t / 7.0 + seed;
	float scene = mod(floor(sc_t), 3.0);
	float ph = fract(sc_t);
	vec2 p = vec2(uv.x * aspect, uv.y);
	// fond : nappes lentes violettes et bleues
	float b = sin(p.x * 2.1 + t * 0.6 + seed) * 0.5 + sin(p.y * 3.3 - t * 0.4) * 0.5;
	vec3 col = mix(vec3(0.03, 0.01, 0.09), NS_VIOLET * 0.35, smoothstep(-0.6, 1.0, b));
	vec3 accent = ns_pal(seed * 3.0 + floor(sc_t));
	if (scene < 0.5) {
		// deux grands signes qui pulsent, halo
		vec2 c = vec2(aspect * 0.5, 0.56);
		float s = 0.62;
		float g1 = ns_glyph(floor(sc_t) * 7.0 + seed, (p - c + vec2(s * 1.02, s * 0.5)) / s);
		float g2 = ns_glyph(floor(sc_t) * 7.0 + seed + 3.0, (p - c + vec2(-0.02, s * 0.5)) / s);
		float g = max(g1, g2);
		float pulse = 0.75 + 0.25 * sin(t * 5.0);
		col += accent * g * 2.2 * pulse;
		col += accent * 0.25 * exp(-length((p - c) * vec2(0.8, 1.6)) * 2.0);
	} else if (scene < 1.5) {
		// mascotte : tête de robot ronde, yeux qui clignent, rayures qui défilent
		float st = step(0.5, fract((p.x + p.y) * 3.0 - t * 0.8));
		col = mix(col, NS_ORANGE * 0.35, st * 0.6);
		vec2 c = vec2(aspect * 0.5, 0.5);
		vec2 q = (p - c) / vec2(0.62, 0.42);
		float head = length(max(abs(q) - vec2(0.55, 0.45), 0.0)) - 0.35;
		col = mix(col, vec3(0.02, 0.02, 0.05), step(head, 0.0));
		col += NS_CYAN * 1.8 * (1.0 - smoothstep(0.0, 0.06, abs(head)));
		float blink = step(0.08, fract(t * 0.45 + seed));
		for (int e = -1; e <= 1; e += 2) {
			vec2 eq = q - vec2(float(e) * 0.42, 0.12);
			eq.y /= max(blink, 0.1);
			col += NS_CYAN * 2.4 * (1.0 - smoothstep(0.17, 0.21, length(eq)));
		}
		float m = abs(length(q - vec2(0.0, 0.05)) - 0.42);
		col += NS_PINK * 1.6 * (1.0 - smoothstep(0.03, 0.06, m)) * step(q.y, -0.2);
	} else {
		// égaliseur et bandeau d'idéogrammes
		float nb = 18.0;
		float k = floor(uv.x * nb);
		float lv = 0.25 + 0.6 * abs(sin(t * (2.0 + ns_h(k) * 3.0) + k));
		float bar = step(uv.y * 1.25, lv) * step(0.18, fract(uv.x * nb)) * step(0.1, fract(uv.y * 20.0));
		col += mix(NS_ACID, NS_BLUE, uv.y) * bar * 1.5;
		col += accent * 1.8 * ns_line(vec2(uv.x, (uv.y - 0.82) / 0.15), 7.0, floor(sc_t) * 3.0, seed);
	}
	// bandeau défilant en bas
	if (uv.y < 0.14) {
		col = vec3(0.02, 0.01, 0.05) + accent * 1.6 * ns_line(vec2(uv.x, uv.y / 0.14), 9.0, t * 1.4, seed + 11.0);
	}
	// transition : balayage blanc bref entre deux scènes
	col += vec3(0.8, 0.7, 1.0) * (1.0 - smoothstep(0.0, 0.03, abs(ph - uv.x * 0.04))) * step(ph, 0.06);
	return col;
}

vec3 ns_column(vec2 uv, float aspect, float seed, float t) {
	float n = 1.0 / aspect;  // signes visibles en hauteur
	float y = uv.y * n - t * 0.9;
	float k = floor(y);
	vec2 g = vec2(uv.x * 1.2 - 0.1, fract(y) * 1.2 - 0.1);
	vec3 c = ns_pal(ns_h(k + seed) * 5.0);
	float on = ns_glyph(ns_h(k * 1.7 + seed) * 64.0, g);
	vec3 col = vec3(0.015, 0.01, 0.05) + c * on * 2.0;
	col += c * 0.12;
	return col;
}

// couleur d'un écran i en uv 0..1 ; trame de pixels et balayage
vec3 ns_screen(int i, vec2 uv, float t) {
	vec4 r = ns_rect[i];
	vec4 m = ns_mode[i];
	float aspect = (r.z - r.x) / max(r.w - r.y, 0.01);
	vec3 col = m.x < 0.5 ? ns_ad(uv, aspect, m.y, t) : ns_column(uv, aspect, m.y, t);
	float flick = 0.94 + 0.06 * sin(t * 37.0 + m.y * 5.0);
	return col * m.z * flick;
}

// émission des écrans au point (x, y) du plan de façade ; a = 1 dans un écran
vec4 ns_screens(vec2 xy, float t) {
	for (int i = 0; i < 4; i++) {
		vec4 r = ns_rect[i];
		if (xy.x > r.x && xy.x < r.z && xy.y > r.y && xy.y < r.w) {
			vec2 uv = (xy - r.xy) / (r.zw - r.xy);
			return vec4(ns_screen(i, uv, t), 1.0);
		}
	}
	return vec4(0.0);
}

// teinte moyenne d'un écran (reflets flous) : couleur de la scène en cours
vec3 ns_screen_avg(int i, float t) {
	vec4 m = ns_mode[i];
	vec3 c = m.x < 0.5 ? ns_pal(m.y * 3.0 + floor(t / 7.0 + m.y)) : ns_pal(floor(t * 0.9));
	return (c * 0.16 + NS_VIOLET * 0.08 + vec3(0.03)) * m.z;
}

// lueur moyenne des écrans bas (0 et 1) vue depuis le toit à l'abscisse x (couleur de la scène en cours)
vec3 ns_screen_glow(float x, float t) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		vec4 r = ns_rect[i];
		vec4 m = ns_mode[i];
		float cx = (r.x + r.z) * 0.5;
		float hw = (r.z - r.x) * 0.5 + 2.0;
		float k = exp(-pow(max(abs(x - cx) - hw + 2.0, 0.0) / 2.5, 2.0));
		vec3 c = m.x < 0.5 ? ns_pal(m.y * 3.0 + floor(t / 7.0 + m.y)) : ns_pal(floor(t * 0.9));
		acc += c * k * m.z * 0.5;
	}
	return acc;
}
