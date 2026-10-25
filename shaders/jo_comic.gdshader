// Jo en « bande dessinée » (direction Spider-Verse) : aplats des couleurs par sommet, deux paliers de lumière
// nets, trame de points (halftone) en espace écran dans l'ombre, petit reflet net, et sur les bords un décalage
// de couleurs façon impression mal calée (cyan d'un côté, magenta de l'autre). Le contour d'encre est une
// deuxième passe (jo_ink.gdshader, next_pass). Tout est dans le matériau : pas de passe plein écran.
// Un seul matériau partagé par tous les modèles de Jo (tenues comprises) : les tenues ne changent que les
// couleurs par sommet.
shader_type spatial;
// Pas de lumière ambiante : l'aplat éclairé vaut la couleur du vêtement, l'ombre sa teinte froide tramée, quelle
// que soit la scène (partie, Relais, vignettes). Le soleil (lumière directionnelle) donne les deux paliers ; les
// lumières ponctuelles (lumière d'appoint HERO_LAYER, tirs, explosions) ajoutent un éclat par-dessus.
render_mode cull_back, depth_draw_opaque, ambient_light_disabled;

uniform float exposure = 1.0;
uniform float saturation = 1.08;
// palier de lumière (N·L) et largeur de la transition (petite : bord net)
uniform float step_at = 0.08;
uniform float step_soft = 0.025;
// ombre : couleur de la surface multipliée par cette teinte froide (pas du noir)
uniform vec3 shade_col : source_color = vec3(0.48, 0.47, 0.78);
uniform float light_gain = 1.0;
uniform float omni_gain = 0.35;
// les blancs ne crament pas sous la lumière d'appoint
uniform float white_cap = 0.9;
// trame : taille des cellules en pixels (écran de 720 px de haut), points plus sombres que l'ombre
uniform float dot_cell = 4.0;
uniform float dot_size = 0.42;
uniform vec3 dot_col : source_color = vec3(0.30, 0.28, 0.58);
// reflet net
uniform float spec_power = 40.0;
uniform float spec_amt = 0.35;
// bords décalés : cyan à gauche de l'écran, magenta à droite
uniform float chroma = 0.55;
uniform float chroma_width = 0.32;
uniform vec3 chroma_a : source_color = vec3(0.2, 0.85, 1.0);
uniform vec3 chroma_b : source_color = vec3(1.0, 0.2, 0.62);
// voile de coup (rouge) et lueur
uniform vec3 heat_col : source_color = vec3(1.0, 0.1, 0.16);
uniform float heat = 0.0;

// Jo de l'invité en duo : les couleurs franches tournent (rouge -> violet), les blancs prennent une pointe de lilas
uniform float guest = 0.0;
uniform float guest_shift = 0.78;

varying vec3 v_normal_view;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_normal_view = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
}

float halftone(vec2 frag, vec2 vp, float amount) {
	// grille tournée à 45°, cellules de dot_cell px (rapportés à 720 px de haut)
	float cell = dot_cell * vp.y / 720.0;
	vec2 p = frag / cell;
	p = vec2(p.x + p.y, p.y - p.x) * 0.7071;
	vec2 f = fract(p) - 0.5;
	float r = dot_size * sqrt(amount);
	return 1.0 - smoothstep(r - 0.08, r + 0.08, length(f));
}

void fragment() {
	vec3 cs = COLOR.rgb;
	if (guest > 0.5) {
		vec3 hsv = rgb2hsv(cs);
		cs = mix(cs * vec3(0.93, 0.9, 1.0), hsv2rgb(vec3(fract(hsv.x + guest_shift), hsv.y, hsv.z)), smoothstep(0.18, 0.4, hsv.y));
	}
	vec3 base = OUTPUT_IS_SRGB ? cs : srgb_to_linear(cs);
	float l0 = dot(base, vec3(0.299, 0.587, 0.114));
	base = max(mix(vec3(l0), base, saturation), vec3(0.0)) * exposure;
	base *= mix(1.0, white_cap, smoothstep(0.6, 0.95, dot(base, vec3(0.299, 0.587, 0.114))));
	ALBEDO = base;
	// décalage de couleurs sur les bords
	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = smoothstep(1.0 - chroma_width, 1.0, fr);
	vec3 ch = mix(chroma_a, chroma_b, step(0.0, v_normal_view.x));
	EMISSION = ch * edge * chroma * (0.35 + 0.65 * l0) + heat_col * heat;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(step_at - step_soft, step_at + step_soft, ndl) * ATTENUATION;
	vec3 lc = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		// ombre : teinte froide + trame de points d'autant plus dense que la surface tourne le dos
		float dark = clamp(-ndl * 1.4 + 0.25, 0.0, 1.0) * (1.0 - lit);
		float dots = halftone(FRAGCOORD.xy, VIEWPORT_SIZE, dark);
		vec3 sh = mix(shade_col, dot_col, dots);
		// teinte du soleil sans son intensité : l'aplat éclairé garde la couleur du vêtement
		vec3 lcn = LIGHT_COLOR / max(max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)), 1e-3);
		DIFFUSE_LIGHT += mix(sh, lcn * light_gain, lit);
	} else {
		DIFFUSE_LIGHT += lc * lit * omni_gain;
	}
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), spec_power);
	s = step(0.5, s);
	SPECULAR_LIGHT += lc * s * spec_amt * ATTENUATION;
}
