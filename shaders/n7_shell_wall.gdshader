// Nébuleuse 7 — murs du hangar (un seul matériau pour tout l'opaque, atlas wall_atlas.png).
// COLOR.rgb teinte, COLOR.a classe (0 peinture, 1/3 métal nu, 2/3 caoutchouc, 1 lumineux) ;
// UV2.x animation (0,25 écran défilant, 0,5 gyrophare, 0,75 voyant clignotant), UV2.y phase.
// L'atlas porte en alpha le masque lumineux des écrans et panneaux rétroéclairés.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/n7_lights.gdshaderinc"

uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 scroll_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float glow_energy = 2.2;
uniform float screen_energy = 1.3;
uniform float albedo_gain = 1.0;

varying vec3 wpos;
varying vec2 anim;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	anim = UV2;
	vcol = COLOR;
}

void fragment() {
	int a = int(anim.x * 4.0 + 0.5);
	vec2 uv = UV;
	if (a == 1) {
		float v = (uv.y - scroll_rect.y) / scroll_rect.w;
		uv.y = scroll_rect.y + fract(v - TIME * 0.025) * scroll_rect.w;
	}
	vec4 t = textureGrad(atlas_tex, uv, dFdx(UV), dFdy(UV));
	int cls = int(vcol.a * 3.0 + 0.5);
	vec3 alb = t.rgb * vcol.rgb * albedo_gain;
	float rough = cls == 1 ? 0.38 : (cls == 2 ? 0.85 : 0.62);
	float metal = cls == 1 ? 0.7 : (cls == 2 ? 0.0 : 0.25);
	vec3 em = vec3(0.0);
	if (cls == 3) {
		float k = 1.0;
		if (a == 2) {
			// gyrophare : éclat quand le faisceau passe face à la caméra
			vec2 q = CAMERA_POSITION_WORLD.xz - wpos.xz;
			float da = mod(atan(q.y, q.x) - (TIME * 3.4 + anim.y * 6.28318) + 3.14159, 6.28318) - 3.14159;
			k = 0.45 + 2.2 * pow(max(cos(da), 0.0), 6.0);
		} else if (a == 3) {
			k = 0.15 + 0.85 * step(0.45, fract(TIME * 0.7 + anim.y * 3.7));
		}
		em = vcol.rgb * t.rgb * glow_energy * k;
		alb *= 0.06;
	} else {
		float fl = a == 1 ? 0.92 + 0.08 * sin(TIME * 23.0 + wpos.z * 3.0) : 1.0;
		em = t.rgb * vcol.rgb * t.a * screen_energy * fl;
	}
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// occlusion simulée des parois : pied du mur, ombre des tuyaux, dessous de la poutre de rive
	if (cls == 0 && abs(nw.y) < 0.5) {
		float y = wpos.y;
		float ao = mix(0.55, 1.0, smoothstep(0.0, 0.9, y));
		ao *= 1.0 - 0.35 * exp(-pow((y - 2.25) / 0.14, 2.0)) - 0.2 * exp(-pow((y - 2.56) / 0.1, 2.0));
		ao *= 1.0 - 0.35 * smoothstep(2.8, 3.0, y) * step(y, 3.02);
		alb *= ao;
	}
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 f0 = mix(vec3(0.04), alb, metal);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = em + n7_lights(wpos, nw, v, alb * (1.0 - metal), f0, rough, TIME);
}
