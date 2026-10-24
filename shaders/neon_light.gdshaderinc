// Cité Néon — éclairage simulé et réflexions du toit mouillé (sol, marquages, parapets).
// Tout passe en EMISSION : aucune lumière dynamique, aucun passage de rendu en plus.
// - tubes néon des parapets : lumières linéaires (diffus + reflets allongés dans l'eau) ;
// - façade de la tour voisine (plan z = facade_z) : réflexion tracée analytiquement dans sa carte d'émission
//   (floue selon la rugosité, par les mips), écrans géants animés quand la surface est un miroir ;
// - au-dessus de la façade : le ciel (panorama), lune comprise ;
// - lueur de la façade et des écrans sur le nord du toit.

#include "res://shaders/neon_screen.gdshaderinc"

uniform sampler2D facade_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D sky_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 facade_rect = vec4(-5.25, -8.0, 48.0, 24.0);   // x0, y0, largeur, hauteur (m)
uniform float facade_z = 0.0;
uniform float facade_gain = 3.2;
uniform float sky_gain = 0.4;
// tubes néon : extrémités, couleur * énergie, w = grésillement (0 stable, > 0 phase)
uniform vec3 strip_a[8];
uniform vec3 strip_b[8];
uniform vec4 strip_col[8];
uniform float strip_energy = 1.0;
uniform float strip_range = 1.6;
uniform float facade_glow = 0.55;

float nl_hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// grésillement d'un néon : presque toujours allumé, quelques battements brefs
float nl_buzz(float ph, float t) {
	if (ph <= 0.0) {
		return 1.0;
	}
	float s = floor(t * 9.0 + ph * 17.0);
	float r = nl_hash(s + ph * 31.0);
	float off = step(0.93, r);
	float slow = step(0.82, fract(t * 0.07 + ph));
	return mix(1.0, 0.18, max(off, slow * step(0.5, nl_hash(s * 0.37 + ph))));
}

vec3 nl_sky(vec3 d, float lod) {
	vec2 suv = vec2(atan(d.x, -d.z) / 6.28318 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159);
	return textureLod(sky_tex, suv, lod).rgb * sky_gain;
}

// façade : (x, y) du plan -> émission (réflexions) ; lod pour le flou
vec3 nl_facade(vec2 xy, float lod, float t) {
	vec2 uv = (xy - facade_rect.xy) / facade_rect.zw;
	uv.y = 1.0 - uv.y;
	vec3 c = textureLod(facade_tex, uv, lod).rgb * facade_gain;
	if (lod < 2.5) {
		// écrans animés, nets dans les flaques
		vec4 sc = ns_screens(xy, t);
		c = mix(c, sc.rgb * facade_gain, sc.a * (1.0 - lod / 2.5));
	}
	return c;
}

// distance entre un rayon (o, d) et un segment (a, b) ; s = abscisse sur le rayon
float nl_ray_seg(vec3 o, vec3 d, vec3 a, vec3 b, out float s) {
	vec3 u = b - a;
	float L = length(u);
	u /= L;
	vec3 w0 = o - a;
	float bb = dot(d, u);
	float dd = dot(d, w0);
	float e = dot(u, w0);
	float den = 1.0 - bb * bb;
	float sc = den > 1e-4 ? (bb * e - dd) / den : 0.0;
	sc = max(sc, 0.0);
	float tc = clamp(dot(o + d * sc - a, u), 0.0, L);
	vec3 p = a + u * tc;
	sc = max(dot(p - o, d), 0.0);
	s = sc;
	return length(o + d * sc - p);
}

// réflexion de l'environnement néon dans une surface mouillée. Le point visé dans la façade est calculé hors de
// toute branche : ses dérivées d'écran donnent le bon niveau de mip (pas de scintillement au loin).
vec3 nl_reflect(vec3 wp, vec3 n, vec3 v, float rough, float t) {
	vec3 r = reflect(-v, n);
	r.y = max(r.y, 0.02);
	r = normalize(r);
	float lod0 = rough * 9.0;
	float tt = (facade_z - wp.z) / min(r.z, -0.02);
	vec3 h = wp + r * tt;
	vec2 uv = (h.xy - facade_rect.xy) / facade_rect.zw;
	uv.y = 1.0 - uv.y;
	vec2 gx = dFdx(uv) * 2048.0;
	vec2 gy = dFdy(uv) * 2048.0;
	float lodg = 0.5 * log2(max(max(dot(gx, gx), dot(gy, gy)), 1.0));
	float lod = clamp(max(lodg, lod0 + log2(1.0 + tt * rough * 2.0)), 0.0, 9.0);
	vec2 suv = vec2(atan(r.x, -r.z) / 6.28318 + 0.5, acos(clamp(r.y, -1.0, 1.0)) / 3.14159);
	vec2 sgx = dFdx(suv) * 2048.0;
	vec2 sgy = dFdy(suv) * 2048.0;
	float slod = clamp(max(0.5 * log2(max(max(dot(sgx, sgx), dot(sgy, sgy)), 1.0)), lod0 * 0.7), 0.0, 9.0);
	vec3 sky = textureLod(sky_tex, suv, slod).rgb * sky_gain * mix(1.8, 1.0, smoothstep(0.05, 0.3, rough));
	vec4 fm = textureLod(facade_tex, uv, lod);
	vec3 fc = fm.rgb * facade_gain;
	if (lod < 2.5) {
		vec4 sc = ns_screens(h.xy, t);
		fc = mix(fc, sc.rgb * facade_gain, sc.a * (1.0 - lod / 2.5));
	}
	float on = r.z < -0.02 ? fm.a : 0.0;
	vec3 col = mix(sky, fc, on);
	// reflet flou (béton mouillé) : moins saturé, la couleur reste aux flaques
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(lum) * vec3(0.8, 0.85, 1.0), smoothstep(0.1, 0.45, rough) * 0.65);
	// tubes des parapets : traits lumineux étirés dans l'eau
	for (int i = 0; i < 8; i++) {
		vec4 sc = strip_col[i];
		if (sc.r + sc.g + sc.b <= 0.0) {
			continue;
		}
		float s;
		float d = nl_ray_seg(wp, r, strip_a[i], strip_b[i], s);
		float wdt = 0.018 + rough * rough * s * 1.6;
		col += sc.rgb * strip_energy * exp(-(d * d) / (wdt * wdt)) * (0.035 / wdt) * nl_buzz(sc.a, t);
	}
	return col;
}

// lumière diffuse et brillance des tubes, lueur de la façade sur le nord du toit
vec3 nl_lights(vec3 wp, vec3 n, vec3 v, vec3 dif, float spec_k, float rough, float t) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 sc = strip_col[i];
		if (sc.r + sc.g + sc.b <= 0.0) {
			continue;
		}
		vec3 a = strip_a[i];
		vec3 b = strip_b[i];
		vec3 u = b - a;
		float L = length(u);
		u /= L;
		float tc = clamp(dot(wp - a, u), 0.0, L);
		vec3 q = a + u * tc;
		vec3 l = q - wp;
		float d = length(l);
		l /= max(d, 1e-3);
		// atténuation douce, coupée aux extrémités
		float end = smoothstep(-0.6, 0.3, dot(wp - a, u)) * smoothstep(-0.6, 0.3, L - dot(wp - a, u));
		float att = end / (1.0 + (d / strip_range) * (d / strip_range) * 6.0);
		float ndl = max(dot(n, l), 0.0);
		vec3 hh = normalize(l + v);
		float ndh = max(dot(n, hh), 0.0);
		float aa = max(rough * rough, 0.04);
		float a2 = aa * aa;
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float D = a2 / (3.14159 * dd * dd);
		acc += sc.rgb * strip_energy * nl_buzz(sc.a, t) * att * ndl * (dif + D * spec_k * 0.25);
	}
	// lueur de la façade : moyenne floue de la bande basse, décroît vers le sud
	float dz = wp.z - facade_z;
	if (dz > 0.0) {
		vec3 g = nl_facade(vec2(wp.x, 2.5), 7.0, t) + ns_screen_glow(wp.x, t) * 0.6;
		float k = facade_glow * exp(-dz / 2.6) * max(n.z * 0.4 + n.y * 0.6, 0.0);
		acc += g * k * (dif + spec_k * 0.05);
	}
	return acc;
}
