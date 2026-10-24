// Cité Néon — marquages peints sur le toit (MultiMesh de quads alpha). INSTANCE_CUSTOM = cadre dans l'atlas ;
// COLOR = répétitions u / 32, v / 32, usure en plus, opacité. La peinture s'interrompt aux joints des dalles,
// pâlit sous l'eau, et reflète les néons comme le sol qu'elle recouvre (neon_light).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/neon_roof.gdshaderinc"
#include "res://shaders/neon_light.gdshaderinc"

uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float paint_gain = 0.6;
uniform float refl_wet = 0.1;
uniform float refl_water = 0.55;

varying vec3 wpos;
varying vec4 rect;
varying vec4 prm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rect = INSTANCE_CUSTOM;
	prm = COLOR;
}

void fragment() {
	float t = TIME;
	vec2 rep = max(vec2(1.0), floor(prm.rg * 32.0 + 0.5));
	vec2 u = UV * rep;
	vec2 auv = rect.xy + fract(u) * rect.zw;
	vec4 p = textureGrad(atlas_tex, auv, dFdx(u) * rect.zw, dFdy(u) * rect.zw);
	vec2 f;
	bool inside;
	vec4 cell = nr_cell(wpos.xz, f, inside);
	int fk = nr_byte(cell.g);
	int kind = fk >> 4;
	int flags = inside ? (fk & 15) : 0;
	vec2 sl;
	float d = nr_edges(f * grid.zw, flags, 0.03, sl);
	vec4 mc = nr_macro(wpos.xz);
	float nz = texture(detail_tex, wpos.xz * 0.5).r;
	float wear = (prm.b - 0.5) + (nz - 0.5) * 0.5 + mc.g * 0.4;
	float keep = 1.0 - smoothstep(0.25, 0.55, wear);
	float on_slab = (kind <= 1) ? 1.0 : 0.0;
	float a = p.a * prm.a * keep * smoothstep(0.005, 0.012, d) * on_slab;
	float water = mc.r;
	float deep = smoothstep(0.25, 0.75, water);
	vec3 alb = p.rgb * paint_gain * mix(1.0, 0.35, deep) * (1.0 - mc.b * 0.3);
	alb = mix(alb, vec3(0.06), clamp(mc.g * 0.4, 0.0, 0.6));
	vec2 slope = nr_ripples(wpos.xz, t) * deep;
	vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
	float rough = mix(0.32, 0.035, smoothstep(0.08, 0.5, water));
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = 0.04 + 0.96 * pow(1.0 - max(dot(nw, v), 0.0), 5.0);
	float rk = mix(refl_wet, refl_water, smoothstep(0.08, 0.6, water)) + fres;
	ALBEDO = alb;
	ALPHA = a;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	EMISSION = nl_lights(wpos, nw, v, alb, 1.0 - rough, rough, t) + nl_reflect(wpos, nw, v, rough, t) * rk;
}

uniform float sun_gain = 1.0;

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR * sun_gain / 3.14159;
}
