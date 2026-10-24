// Personnages sculptés (tools/sculpt.py) : couleurs par sommet (occlusion déjà cuite dedans), ombrage
// stylisé à rampe douce (ombre / demi-teinte / pleine lumière, transitions adoucies), ombre propre teintée
// de bleu nébuleuse, reflet spéculaire net sur les coques, liseré de lumière coloré par l'environnement
// (ciel violet en haut, rebond du sol en bas) et par les lumières ponctuelles (tirs, explosions).
// Le contour est une deuxième passe (character_outline.gdshader, next_pass).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0);
// paliers de la rampe (N·L) : ombre -> demi-teinte -> lumière, et douceur des transitions
uniform float ramp_mid = 0.0;
uniform float ramp_high = 0.42;
uniform float ramp_soft = 0.12;
uniform float half_tone = 0.62;
// les blancs ne crament pas : la coque claire garde sa teinte gris bleuté
uniform float white_cap = 0.8;
// côté ombre : la lumière du soleil n'y arrive pas, une lueur froide (nébuleuse) la remplace
uniform vec3 shade_col : source_color = vec3(0.36, 0.34, 0.62);
uniform float shade_amt = 0.32;
uniform float light_gain = 0.86;
// reflet net (Blinn-Phong seuillé)
uniform float spec_power = 48.0;
uniform float spec_cut = 0.42;
uniform float spec_amt = 0.42;
// liseré : ciel de la nébuleuse en haut, rebond chaud du sol en bas
uniform vec3 rim_sky : source_color = vec3(0.62, 0.5, 1.0);
uniform vec3 rim_floor : source_color = vec3(0.95, 0.62, 0.42);
uniform float rim_amt = 0.6;
uniform float rim_width = 0.58;
// lueur ajoutée (le Pétard qui chauffe)
uniform vec3 heat_col : source_color = vec3(1.0, 0.1, 0.16);
uniform float heat = 0.0;

varying vec3 w_normal;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// couleurs par sommet en sRGB (même règle que vertex_color_is_srgb : rien à convertir si la sortie l'est)
	vec3 base = (OUTPUT_IS_SRGB ? COLOR.rgb : srgb_to_linear(COLOR.rgb)) * tint.rgb;
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	base *= mix(1.0, white_cap, smoothstep(0.4, 0.9, luma));
	ALBEDO = base;
	// liseré d'environnement : fresnel serré, teinté selon l'orientation (haut : ciel, bas : sol)
	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, fr);
	rim *= rim;
	float up = clamp(w_normal.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 rc = mix(rim_floor * 0.55, rim_sky, smoothstep(0.25, 0.75, up));
	// le liseré prend un peu la couleur de la surface (pas un halo blanc uniforme)
	EMISSION = rc * rim * rim_amt * mix(vec3(0.35), base * 1.6 + vec3(0.12), 0.6) + heat_col * heat;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// rampe douce à trois paliers
	float r1 = smoothstep(ramp_mid - ramp_soft, ramp_mid + ramp_soft, ndl);
	float r2 = smoothstep(ramp_high - ramp_soft, ramp_high + ramp_soft, ndl);
	float ramp = r1 * half_tone + r2 * (1.0 - half_tone);
	float lit = ramp * ATTENUATION;
	vec3 lc = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		// côté ombre : lueur froide plutôt que du noir
		vec3 d = mix(shade_col * shade_amt, vec3(light_gain), lit);
		DIFFUSE_LIGHT += lc * d;
	} else {
		DIFFUSE_LIGHT += lc * lit;
		// lumières ponctuelles (tirs, explosions) : elles soulignent aussi le bord
		float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		DIFFUSE_LIGHT += lc * ATTENUATION * smoothstep(0.5, 1.0, fr) * clamp(ndl + 0.6, 0.0, 1.0) * 1.5;
	}
	// reflet net
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), spec_power);
	s = smoothstep(spec_cut - 0.08, spec_cut + 0.08, s);
	SPECULAR_LIGHT += lc * s * spec_amt * ATTENUATION;
}
