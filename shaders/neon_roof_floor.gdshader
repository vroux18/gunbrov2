// Cité Néon — sol du toit-terrasse sous la pluie, un seul quad.
// Dalles de béton (joints remplis d'eau, chanfreins, fissures, écornures), zones de bitume (lés soudés,
// granulés), pièces prises dans l'atlas (siphons, trappes, lanterneaux, grilles, caniveaux), carte unique
// de flaques / crasse / traînées / huile, gouttes dans l'eau, reflets des néons et de la façade (neon_light).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/neon_roof.gdshaderinc"
#include "res://shaders/neon_light.gdshaderinc"

uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 ins_rect[9];
uniform vec2 ins_cells[9];
uniform float detail_m = 2.0;
uniform vec3 conc_a : source_color = vec3(0.33, 0.345, 0.37);
uniform vec3 conc_b : source_color = vec3(0.4, 0.4, 0.4);
uniform vec3 memb_col : source_color = vec3(0.2, 0.2, 0.215);
uniform vec3 dirt_col : source_color = vec3(0.09, 0.085, 0.085);
uniform float wet_dark = 0.62;
uniform float refl_wet = 0.06;
uniform float refl_water = 0.42;
uniform vec3 sky_glow : source_color = vec3(1.0, 0.75, 0.5);
uniform float sky_energy = 1.6;
uniform vec3 pad_col : source_color = vec3(0.6, 1.0, 0.35);
uniform float ripple_k = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void fragment() {
	float t = TIME;
	vec2 f;
	bool inside;
	vec4 cell = nr_cell(wpos.xz, f, inside);
	int seed = nr_byte(cell.r);
	int fk = nr_byte(cell.g);
	int flags = fk & 15;
	int kind = fk >> 4;
	int oxy = nr_byte(cell.b);
	int vz = nr_byte(cell.a);
	int variant = vz & 15;
	if (!inside) {
		flags = 0;
		kind = 1;
		variant = 0;
	}
	float fs = float(seed);
	vec2 pc = f * grid.zw;
	vec2 slope;
	bool slab = kind == 0;
	float d = nr_edges(pc, flags, slab ? 0.03 : 0.012, slope);
	// détail : tuile tournée et décalée par dalle
	int rq = seed & 3;
	mat2 rot = rq == 0 ? mat2(vec2(1.0, 0.0), vec2(0.0, 1.0)) : (rq == 1 ? mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0)) : (rq == 2 ? mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0)) : mat2(vec2(0.0, -1.0), vec2(1.0, 0.0))));
	float dm = slab ? detail_m : detail_m * 0.6;
	vec2 duv = rot * (wpos.xz / dm) + vec2(hash1(fs), hash1(fs + 7.0));
	vec2 ddx = rot * (dFdx(wpos.xz) / dm);
	vec2 ddy = rot * (dFdy(wpos.xz) / dm);
	vec4 dt = textureGrad(detail_tex, duv, ddx, ddy);
	// relief du détail (différences finies sur la hauteur)
	float e = 1.0 / 1024.0;
	float hx = textureGrad(detail_tex, duv + vec2(e, 0.0), ddx, ddy).b - dt.b;
	float hz = textureGrad(detail_tex, duv + vec2(0.0, e), ddx, ddy).b - dt.b;
	vec2 dslope = transpose(rot) * vec2(hx, hz) * 3.0;
	vec4 mc = nr_macro(wpos.xz);
	float h1 = hash1(fs + 3.0);
	vec3 alb;
	float rough;
	float metal = 0.0;
	float emis_k = 0.0;
	vec3 emis_c = vec3(0.0);
	float joint = 1.0;
	float water_add = 0.0;
	if (slab) {
		// béton : teinte par dalle, dalles refaites plus claires, fissures, coins écornés
		vec3 base = variant == 1 ? conc_b : conc_a;
		alb = base * (0.66 + 0.5 * h1) * (0.62 + 0.76 * dt.r);
		float crack = variant == 2 ? dt.g * 0.8 : dt.g * 0.08;
		alb *= 1.0 - crack * 0.6;
		water_add += crack * 0.5;
		rough = 0.55 + (dt.a - 0.5) * 0.3;
		if (variant == 3) {
			// écornure au coin choisi par la graine
			vec2 cq = vec2((seed & 16) != 0 ? grid.z - pc.x : pc.x, (seed & 32) != 0 ? grid.w - pc.y : pc.y);
			float chip = 1.0 - smoothstep(0.16, 0.2, cq.x + cq.y + (dt.b - 0.5) * 0.08);
			alb = mix(alb, alb * 0.45, chip);
			rough = mix(rough, 0.8, chip);
			water_add += chip * 0.7;
		}
		// joints : creux sombre plein d'eau
		joint = smoothstep(0.004, 0.009, d);
		water_add += (1.0 - smoothstep(0.004, 0.014, d)) * 0.9;
		alb *= mix(0.15, 1.0, joint);
		alb *= mix(0.78, 1.0, smoothstep(0.005, 0.04, d));
	} else {
		// bitume : lés de 1 m soudés (bourrelet), granulés minéraux, reprises
		alb = memb_col * (0.8 + 0.3 * dt.r) * (0.85 + 0.2 * h1);
		float zone = float(vz >> 4);
		float lap = fract((wpos.z + zone * 0.37) / 1.0);
		float bead = exp(-pow((lap - 0.06) / 0.012, 2.0));
		slope += vec2(0.0, -1.0) * bead * 0.6 * sign(lap - 0.06);
		alb *= 1.0 - bead * 0.35;
		float gran = smoothstep(0.55, 0.8, dt.b);
		alb += vec3(0.04, 0.04, 0.045) * gran;
		rough = 0.7 + gran * 0.1;
		water_add += bead * 0.25;
		// bord contre le béton : solin sombre
		joint = smoothstep(0.006, 0.02, d);
		alb *= mix(0.3, 1.0, joint);
	}
	vec2 sl = slope + dslope * (slab ? 0.6 : 0.9);
	// pièces de l'atlas
	if (kind >= 2 && inside) {
		vec4 r = ins_rect[kind];
		vec2 sc = ins_cells[kind];
		vec2 lp = (vec2(float(oxy & 15), float(oxy >> 4)) + f) / sc;
		vec2 auv = r.xy + lp * r.zw;
		vec2 adx = dFdx(wpos.xz) / (sc * grid.zw) * r.zw;
		vec2 ady = dFdy(wpos.xz) / (sc * grid.zw) * r.zw;
		vec4 at = textureGrad(atlas_tex, auv, adx, ady);
		float ea = 1.0 / 2048.0;
		float hx0 = textureGrad(atlas_tex, auv - vec2(ea, 0.0), adx, ady).a;
		float hx1 = textureGrad(atlas_tex, auv + vec2(ea, 0.0), adx, ady).a;
		float hz0 = textureGrad(atlas_tex, auv - vec2(0.0, ea), adx, ady).a;
		float hz1 = textureGrad(atlas_tex, auv + vec2(0.0, ea), adx, ady).a;
		float k = 0.025 * (r.z / (sc.x * grid.z)) / (2.0 * ea);
		sl = clamp(vec2(hx1 - hx0, hz1 - hz0) * k, vec2(-3.0), vec2(3.0)) + dslope * 0.15;
		alb = at.rgb * (0.9 + 0.2 * dt.r);
		float lvl = at.a;
		rough = mix(0.5, 0.35, smoothstep(0.8, 0.95, lvl));
		metal = kind == 4 ? 0.0 : mix(0.2, 0.6, smoothstep(0.75, 0.9, lvl));
		joint = 1.0;
		if (kind == 4) {
			// lanterneau : verre armé éclairé de l'intérieur
			float g = 1.0 - smoothstep(0.03, 0.2, lvl);
			emis_c = at.rgb * sky_glow * sky_energy * g * (0.9 + 0.1 * sin(t * 1.3 + fs));
			alb *= mix(1.0, 0.25, g);
			rough = mix(rough, 0.08, g);
		}
		water_add += (1.0 - smoothstep(0.1, 0.5, lvl)) * 0.6;
	}
	// carte du toit : eau, crasse, traînées, huile
	float water = clamp(mc.r + water_add * 0.5, 0.0, 1.0);
	alb = mix(alb, dirt_col, clamp(mc.g * 0.55, 0.0, 0.8));
	rough = mix(rough, 0.82, mc.g * 0.4);
	float trail = mc.b;
	alb *= 1.0 - trail * 0.35;
	// tout est mouillé : albédo assombri, rugosité baissée ; l'eau lisse le relief
	alb *= wet_dark;
	rough = mix(rough, 0.32, 0.45);
	rough = mix(rough, 0.18, trail * 0.8);
	float deep = smoothstep(0.25, 0.75, water);
	alb = mix(alb, alb * 0.5, deep);
	rough = mix(rough, 0.035, smoothstep(0.08, 0.5, water));
	metal *= 1.0 - deep;
	sl *= 1.0 - deep * 0.92;
	sl += nr_ripples(wpos.xz, t) * deep * ripple_k;
	// aire d'atterrissage : feux de balisage encastrés qui tournent
	vec2 hq = wpos.xz - heli.xy;
	float hd = length(hq);
	float ha = atan(hq.y, hq.x);
	float nlamp = 24.0;
	float ai = floor(ha / 6.28318 * nlamp + 0.5);
	vec2 lc = heli.xy + vec2(cos(ai / nlamp * 6.28318), sin(ai / nlamp * 6.28318)) * (heli.z + 0.32);
	float ld = length(wpos.xz - lc);
	float chase = 0.35 + 0.65 * pow(fract(ai / nlamp - t * 0.35), 6.0);
	float lamp = 1.0 - smoothstep(0.035, 0.05, ld);
	float ring = 1.0 - smoothstep(0.05, 0.065, ld);
	alb = mix(alb, vec3(0.05), ring);
	emis_c += pad_col * lamp * chase * 2.2;
	emis_c += pad_col * exp(-ld * ld / 0.04) * chase * 0.05;
	vec3 nw = normalize(vec3(-sl.x, 1.0, -sl.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float ndv = max(dot(nw, v), 0.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
	float rk = mix(refl_wet, refl_water, smoothstep(0.08, 0.6, water)) + fres;
	rk *= mix(1.0, 0.25, 1.0 - joint);
	vec3 refl = nl_reflect(wpos, nw, v, rough, t);
	// huile sur l'eau : reflet irisé
	float oil = mc.a * smoothstep(0.1, 0.4, water);
	vec3 iri = 0.5 + 0.5 * cos(6.28318 * (mc.a * 2.3 + dt.r * 0.6 + vec3(0.0, 0.33, 0.67)));
	refl *= mix(vec3(1.0), iri * 1.6, oil * 0.8);
	rough = clamp(rough, 0.03, 0.95);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 dif = alb * (1.0 - metal);
	EMISSION = nl_lights(wpos, nw, v, dif, 1.0 - rough * 0.8, rough, t) + refl * rk + emis_c;
}

// Lune (soleil de Godot) avec un gain propre : le sol prend peu de lumière directe, ombres comprises.
// Pas de reflet spéculaire ici : les reflets du ciel et de la lune sont dans nl_reflect.
uniform float sun_gain = 1.0;

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR * sun_gain / 3.14159;
}
