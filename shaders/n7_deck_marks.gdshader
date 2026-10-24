// Nébuleuse 7 — marquages peints au sol (un MultiMesh de quads alpha, remplace les Decal absents en
// Compatibility). INSTANCE_CUSTOM = cadre dans l'atlas ; COLOR = répétitions u / 32, v / 32, usure en plus,
// opacité. La peinture s'interrompt aux joints des tôles, épouse les rivets, s'use là où l'on passe.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/n7_deck.gdshaderinc"
#include "res://shaders/n7_lights.gdshaderinc"

uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 macro_rect = vec4(0.0, 3.90625, 37.5, 18.75);
uniform float paint_gain = 0.55;

varying vec3 wpos;
varying vec4 rect;
varying vec4 prm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rect = INSTANCE_CUSTOM;
	prm = COLOR;
}

void fragment() {
	vec2 rep = max(vec2(1.0), floor(prm.rg * 32.0 + 0.5));
	vec2 u = UV * rep;
	vec2 auv = rect.xy + fract(u) * rect.zw;
	vec4 p = textureGrad(atlas_tex, auv, dFdx(u) * rect.zw, dFdy(u) * rect.zw);
	vec2 f;
	bool inside;
	vec4 cell = n7_cell(wpos.xz, f, inside);
	int flags = inside ? (n7_byte(cell.g) & 15) : 0;
	int kind = n7_byte(cell.g) >> 4;
	vec3 nrm;
	float riv, riv_ao;
	float d = n7_edges(f * grid.z, flags, inside && (kind == 0 || kind == 8), nrm, riv, riv_ao);
	vec4 mc = texture(macro_tex, (wpos.xz - macro_rect.xy) / macro_rect.zw);
	float nz = texture(detail_tex, wpos.xz * 0.5).b;
	float wear = mc.g * 0.75 + (prm.b - 0.5) + riv * 0.5 + (1.0 - smoothstep(0.0, 0.03, d)) * 0.4;
	float keep = 1.0 - smoothstep(0.42, 0.7, wear + (nz - 0.5) * 0.6);
	float a = p.a * prm.a * keep * smoothstep(0.006, 0.011, d);
	vec3 alb = p.rgb * paint_gain;
	alb = mix(alb, vec3(0.12, 0.11, 0.1), clamp(mc.r * 0.55, 0.0, 0.8));
	alb *= (1.0 - mc.b * 0.6) * (1.0 - mc.a * 0.5) * riv_ao;
	ALBEDO = alb;
	ALPHA = a;
	ROUGHNESS = mix(0.58, 0.25, mc.b);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	if (a > 0.0) {
		// hors de la peinture (alpha nul, le pixel garde le sol) : rien à éclairer
		vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
		EMISSION = n7_lights(wpos, nrm, v, alb, vec3(0.04), 0.58, TIME);
	}
}
