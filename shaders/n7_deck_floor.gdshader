// Nébuleuse 7 — tôle de pont du hangar, un seul quad pour tout le sol.
// Plan des tôles lu case par case (joints, chanfreins, rivets calculés ici, nets à toute distance),
// tuile de détail tournée et décalée par tôle (pas de répétition visible), carte unique de crasse /
// usure / huile / pneus sur tout le sol, trappes et grilles prises dans l'atlas, fond lumineux des grilles,
// plafonniers simulés (n7_lights).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/n7_deck.gdshaderinc"
#include "res://shaders/n7_lights.gdshaderinc"

uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 macro_rect = vec4(0.0, 3.90625, 37.5, 18.75);
uniform float detail_m = 2.0;
uniform vec4 ins_rect[9];
uniform vec2 ins_cells[9];
uniform vec3 paint_a : source_color = vec3(0.165, 0.18, 0.215);
uniform vec3 paint_b : source_color = vec3(0.15, 0.185, 0.235);
uniform vec3 bare_col : source_color = vec3(0.34, 0.345, 0.36);
uniform vec3 dirt_col : source_color = vec3(0.12, 0.11, 0.1);
uniform vec3 glow_col : source_color = vec3(0.32, 0.36, 1.0);
uniform float glow_energy = 0.45;
uniform float insert_gain = 0.62;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void fragment() {
	vec2 f;
	bool inside;
	vec4 cell = n7_cell(wpos.xz, f, inside);
	int seed = n7_byte(cell.r);
	int fk = n7_byte(cell.g);
	int flags = fk & 15;
	int kind = fk >> 4;
	int oxy = n7_byte(cell.b);
	int variant = n7_byte(cell.a);
	if (!inside) {
		flags = 0;
		kind = 0;
		variant = 2;
	}
	float fs = float(seed);
	vec2 pc = f * grid.z;
	// joints, chanfreins, rivets
	vec3 nrm;
	float riv, riv_ao;
	bool plain = kind == 0 || kind == 8;
	float d = n7_edges(pc, flags, plain && inside, nrm, riv, riv_ao);
	float seam = smoothstep(0.004, 0.009, d);
	// détail : tuile tournée d'un quart de tour et décalée par tôle
	int rq = seed & 3;
	mat2 rot = rq == 0 ? mat2(vec2(1.0, 0.0), vec2(0.0, 1.0)) : (rq == 1 ? mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0)) : (rq == 2 ? mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0)) : mat2(vec2(0.0, -1.0), vec2(1.0, 0.0))));
	vec2 duv = rot * (wpos.xz / detail_m) + vec2(hash1(fs), hash1(fs + 7.0));
	vec2 dx = rot * (dFdx(wpos.xz) / detail_m);
	vec2 dy = rot * (dFdy(wpos.xz) / detail_m);
	vec4 dt = textureGrad(detail_tex, duv, dx, dy);
	vec3 dn = textureGrad(detail_n, duv, dx, dy).xyz * 2.0 - 1.0;
	vec2 dslope = transpose(rot) * vec2(-dn.x, dn.y);
	vec4 mc = texture(macro_tex, (wpos.xz - macro_rect.xy) / macro_rect.zw);
	// tôle peinte : teinte propre à chaque tôle, écaillage aux bords et là où l'on passe
	float h1 = hash1(fs + 3.0);
	vec3 paint = (variant == 1 ? paint_b : paint_a) * (0.78 + 0.44 * h1);
	paint = mix(paint, paint * vec3(1.08, 1.0, 0.9), step(0.75, hash1(fs + 11.0)));
	paint *= 0.78 + 0.44 * dt.r;
	float edge_w = (1.0 - smoothstep(0.0, 0.05, d)) * 0.35;
	float wear = mc.g * 0.85 + (variant == 2 ? 0.22 : 0.0) + edge_w + riv * 0.6;
	float bare = smoothstep(0.52, 0.6, wear + (dt.b - 0.5) * 0.7);
	vec3 alb = mix(paint, bare_col * (0.85 + 0.3 * dt.r), bare);
	float scr = dt.g * (0.25 + 0.75 * clamp(mc.g + 0.2, 0.0, 1.0));
	alb = mix(alb, bare_col * 1.15, scr * 0.55);
	float rough = mix(0.62, 0.34, bare) + (dt.a - 0.5) * 0.25 - scr * 0.12;
	float metal = mix(0.15, 0.55, max(bare, scr * 0.6));
	vec2 slope = vec2(-nrm.x, -nrm.z) / max(nrm.y, 0.2) + dslope * 0.22;
	float emis = 0.0;
	// trappes, regards, grilles : atlas (albédo + hauteur)
	if (kind > 0 && inside) {
		vec4 r = ins_rect[kind];
		vec2 sc = ins_cells[kind];
		vec2 lp = (vec2(float(oxy & 15), float(oxy >> 4)) + f) / sc;
		vec2 auv = r.xy + lp * r.zw;
		vec2 adx = dFdx(wpos.xz) / (sc * grid.z) * r.zw;
		vec2 ady = dFdy(wpos.xz) / (sc * grid.z) * r.zw;
		vec4 at = textureGrad(atlas_tex, auv, adx, ady);
		float e = 1.0 / 2048.0;
		float hx0 = textureGrad(atlas_tex, auv - vec2(e, 0.0), adx, ady).a;
		float hx1 = textureGrad(atlas_tex, auv + vec2(e, 0.0), adx, ady).a;
		float hz0 = textureGrad(atlas_tex, auv - vec2(0.0, e), adx, ady).a;
		float hz1 = textureGrad(atlas_tex, auv + vec2(0.0, e), adx, ady).a;
		float k = 0.03 * (r.z / (sc.x * grid.z)) / (2.0 * e);
		vec2 hs = vec2(hx1 - hx0, hz1 - hz0) * k;
		slope = slope * 0.3 + clamp(hs, vec2(-3.0), vec2(3.0)) + dslope * 0.12;
		float lvl = at.a;
		vec3 ia = at.rgb * insert_gain * (0.92 + 0.16 * dt.r);
		float hi = smoothstep(0.84, 0.98, lvl);
		alb = mix(ia, bare_col * (0.9 + 0.2 * dt.r), hi * 0.5 * clamp(mc.g + 0.3, 0.0, 1.0));
		rough = mix(0.55, 0.32, hi) + (dt.a - 0.5) * 0.2;
		metal = mix(0.35, 0.8, hi);
		bool glows = kind == 3 || kind == 4 || kind == 5 || kind == 7;
		if (glows) {
			emis = 1.0 - smoothstep(0.04, 0.5, lvl);
			emis *= emis;
			emis *= 0.85 + 0.15 * sin(TIME * (1.3 + h1) + fs);
		}
	}
	// crasse, huile, pneus
	float dirt = mc.r * (variant == 1 ? 0.6 : 1.0);
	float corner = (1.0 - smoothstep(0.0, 0.04, d)) * 0.35;
	alb = mix(alb, dirt_col, clamp(dirt * 0.62 + corner * dirt, 0.0, 0.9));
	rough = mix(rough, 0.88, dirt * 0.7);
	metal *= 1.0 - dirt * 0.6;
	float oil = mc.b;
	alb *= 1.0 - oil * 0.62;
	rough = mix(rough, 0.16, oil);
	metal = mix(metal, 0.1, oil);
	float tire = mc.a;
	alb = mix(alb, vec3(0.03, 0.03, 0.035), tire * 0.7);
	rough = mix(rough, 0.5, tire);
	// joints et ombres des rivets
	alb *= mix(0.06, 1.0, seam) * riv_ao;
	alb *= mix(0.72, 1.0, smoothstep(0.004, 0.05, d));
	vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
	rough = clamp(rough, 0.12, 0.95);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 f0 = mix(vec3(0.04), alb, metal);
	vec3 dif = alb * (1.0 - metal);
	EMISSION = n7_lights(wpos, nw, v, dif, f0, rough, TIME) + glow_col * glow_energy * emis;
}
