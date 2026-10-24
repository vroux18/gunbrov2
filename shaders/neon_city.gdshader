// Cité Néon — la ville en contrebas (vue par-dessus les parapets) : façades à fenêtres allumées au hasard,
// enseignes, toits sombres, avenues où la circulation file, brume rose qui monte de la rue.
// COLOR.r graine, COLOR.g teinte, COLOR.a classe (0 façade, 1/3 toit, 2/3 avenue, 1 enseigne) ; UV en mètres.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 haze_col : source_color = vec3(0.36, 0.12, 0.42);
uniform vec3 haze_low : source_color = vec3(0.62, 0.2, 0.5);
uniform float roof_y = 0.0;
uniform float street_y = -48.0;
uniform float energy = 1.0;

varying vec3 wpos;
varying vec4 vcol;
varying vec2 anim;

const vec3 C_PINK = vec3(1.0, 0.045, 0.42);
const vec3 C_BLUE = vec3(0.045, 0.26, 1.0);
const vec3 C_VIOLET = vec3(0.27, 0.07, 1.0);
const vec3 C_ACID = vec3(0.47, 1.0, 0.045);
const vec3 C_ORANGE = vec3(1.0, 0.25, 0.045);

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
	anim = UV2;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 pal(float k) {
	int i = int(mod(floor(k * 5.0), 5.0));
	return i == 0 ? C_PINK : (i == 1 ? C_BLUE : (i == 2 ? C_VIOLET : (i == 3 ? C_ACID : C_ORANGE)));
}

void fragment() {
	float t = TIME;
	int cls = int(vcol.a * 3.0 + 0.5);
	float seed = vcol.r;
	vec3 col;
	if (cls == 0) {
		// façade : grille de fenêtres (étage 3,2 m, travée 1,7 m), allumées au hasard
		vec2 g = vec2(UV.x / 1.7, UV.y / 3.2);
		vec2 c = floor(g);
		vec2 f = fract(g);
		float r = h21(c + seed * 91.0);
		vec2 fw = fwidth(g);
		float aa = smoothstep(0.15, 0.45, max(fw.x, fw.y));
		vec2 wx = smoothstep(vec2(0.12, 0.22) - fw, vec2(0.12, 0.22) + fw, f) * (1.0 - smoothstep(vec2(0.88, 0.86) - fw, vec2(0.88, 0.86) + fw, f));
		float win = mix(wx.x * wx.y, 0.42, aa);
		vec3 lit = r < 0.38 ? vec3(1.0, 0.62, 0.32) : (r < 0.52 ? vec3(0.62, 0.75, 1.0) : (r < 0.58 ? pal(seed + r) : vec3(0.0)));
		float lk = 0.35 + 0.65 * h21(c * 1.7 + seed);
		lit = mix(lit, vec3(0.5, 0.36, 0.3) * 0.45, aa);
		col = vec3(0.025, 0.022, 0.04) * (0.8 + 0.4 * seed);
		col = mix(col, lit * lk * 0.9 + vec3(0.01, 0.01, 0.02), win);
		// bandeaux d'étage
		col *= 1.0 - 0.5 * step(0.94, f.y) * (1.0 - aa);
	} else if (cls == 1) {
		// toits : bitume sombre, quelques lueurs de lanterneaux
		vec2 p = wpos.xz;
		float n = h21(floor(p * 0.7) + seed * 13.0);
		col = vec3(0.03, 0.028, 0.04) * (0.7 + 0.6 * n);
		if (wpos.y < street_y + 0.5) {
			// sol de la ville : vitrines et halos entre les immeubles
			vec2 q = floor(p / 3.0);
			float s = h21(q);
			col = vec3(0.02, 0.012, 0.03) + pal(s) * step(0.86, s) * 0.5;
		}
	} else if (cls == 2) {
		// avenue : chaussée, files de phares (blancs à l'aller, rouges au retour)
		float v = UV.y;
		float lane = floor(v * 4.0);
		float dir = lane < 2.0 ? 1.0 : -1.0;
		float spd = 9.0 + lane * 2.0;
		float u = UV.x * 0.25 + dir * t * spd * 0.25 + lane * 3.7;
		float cell = floor(u);
		float fu = fract(u);
		float car = step(0.55, h21(vec2(cell, lane + seed * 7.0)));
		float head = exp(-pow((fu - 0.5) * 9.0, 2.0)) * car;
		vec3 lc = dir > 0.0 ? vec3(1.0, 0.9, 0.75) : vec3(1.0, 0.12, 0.08);
		float inlane = 1.0 - smoothstep(0.08, 0.2, abs(fract(v * 4.0) - 0.5));
		col = vec3(0.025, 0.02, 0.035) + lc * head * inlane * 2.2;
		// marquage central et lueur des trottoirs
		col += vec3(0.5, 0.45, 0.3) * (1.0 - smoothstep(0.004, 0.012, abs(v - 0.5))) * step(0.5, fract(UV.x * 0.2)) * 0.3;
		col += vec3(0.6, 0.15, 0.45) * (exp(-v * 10.0) + exp(-(1.0 - v) * 10.0)) * 0.35;
	} else {
		// enseigne / feu
		vec3 c = vcol.b > 0.5 ? pal(vcol.g) : vec3(1.0, 0.1, 0.12);
		float k = 1.0;
		if (anim.x > 0.4) {
			k = 0.1 + 0.9 * step(0.5, fract(t * 0.6 + anim.y * 5.0));
		} else if (anim.x > 0.1) {
			k = 0.25 + 0.75 * step(0.08, fract(t * 1.7 + anim.y * 9.0));
		}
		col = c * 1.8 * k;
	}
	// brume : plus on descend, plus la ville se noie dans le rose
	float depth = clamp((roof_y - wpos.y) / (roof_y - street_y), 0.0, 1.0);
	float hz = smoothstep(0.05, 1.0, depth);
	vec3 hc = mix(haze_col, haze_low, depth);
	col = mix(col, hc, hz * 0.6) + hc * hz * 0.08;
	ALBEDO = col * energy;
}
