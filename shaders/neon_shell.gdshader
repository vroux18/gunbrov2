// Cité Néon — bords du toit et tour voisine (un seul matériau, atlas neon_atlas.png).
// COLOR.rgb teinte, COLOR.a classe (0 béton / peint, 1/3 métal, 2/3 caoutchouc, 1 lumineux) ;
// UV2.x animation (0 fixe, 0,25 grésille, 0,5 clignote, 0,75 écran n° UV2.y * 4, 1 carte de façade), UV2.y phase.
// L'atlas porte en alpha le masque lumineux (fenêtres, enseignes). Tout est mouillé : reflets néon (neon_light).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/neon_light.gdshaderinc"

uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float glow_energy = 2.4;
uniform float window_energy = 0.8;
uniform float map_energy = 1.0;
uniform float wet_refl = 0.12;

varying vec3 wpos;
varying vec2 anim;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	anim = UV2;
	vcol = COLOR;
}

float blink(float ph, float t) {
	return 0.08 + 0.92 * step(0.4, fract(t * 0.55 + ph * 3.7));
}

void fragment() {
	float t = TIME;
	int a = int(anim.x * 4.0 + 0.5);
	int cls = int(vcol.a * 3.0 + 0.5);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 alb;
	vec3 em = vec3(0.0);
	float rough = cls == 1 ? 0.3 : (cls == 2 ? 0.6 : 0.5);
	float metal = cls == 1 ? 0.6 : 0.0;
	float k = 1.0;
	if (a == 1) {
		k = nl_buzz(anim.y, t);
	} else if (a == 2) {
		k = blink(anim.y, t);
	}
	if (a == 4) {
		// carte de la façade (loin de la bande proche), étages répétés plus bas
		vec2 xy = wpos.xy;
		vec3 mc;
		if (anim.y > 0.1) {
			// notre tour : fenêtres procédurales (étage 3,4 m, travée 2,4 m), allumées au hasard
			float hx = anim.y > 0.4 ? wpos.z : wpos.x;
			vec2 g = vec2(hx / 2.4, (wpos.y - 0.9) / 3.4);
			vec2 c = floor(g);
			vec2 f = fract(g);
			float r = fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
			float win = step(0.08, f.x) * step(f.x, 0.92) * step(0.3, f.y) * step(f.y, 0.88) * step(0.04, abs(f.x - 0.5));
			vec3 lit = r < 0.35 ? vec3(0.4, 0.22, 0.1) : (r < 0.5 ? vec3(0.2, 0.26, 0.4) : (r < 0.54 ? vec3(0.4, 0.04, 0.22) : vec3(0.012, 0.012, 0.025)));
			mc = mix(vec3(0.02, 0.018, 0.03), lit, win);
		} else {
			float fy0 = facade_rect.y;
			if (xy.y < fy0 + 3.4) {
				xy.y = fy0 + 3.4 + mod(xy.y - fy0 - 3.4, 6.8);
			}
			vec2 uv = (xy - facade_rect.xy) / facade_rect.zw;
			uv.y = 1.0 - uv.y;
			mc = texture(facade_tex, uv).rgb;
		}
		alb = mc * 0.25;
		em = mc * facade_gain * 0.55 * map_energy;
		// plus bas, la brume de la rue noie la façade
		float fog = smoothstep(-4.0, -30.0, wpos.y);
		em = mix(em, vec3(0.16, 0.05, 0.22), fog * 0.7);
		alb *= 1.0 - fog;
		rough = 0.4;
	} else if (a == 3) {
		int si = int(anim.y * 4.0);
		vec3 sc = ns_screen(si, UV, t);
		// trame de pixels et léger vignetage
		vec4 r = ns_rect[si];
		vec2 px = UV * (r.zw - r.xy) * 22.0;
		vec2 g = abs(fract(px) - 0.5);
		float grid = 0.78 + 0.22 * (1.0 - smoothstep(0.38, 0.5, max(g.x, g.y)));
		float vig = 1.0 - 0.35 * pow(length(UV - 0.5) * 1.4, 3.0);
		em = sc * grid * vig * 1.35;
		alb = vec3(0.01);
		rough = 0.15;
	} else {
		vec4 tx = textureGrad(atlas_tex, UV, dFdx(UV), dFdy(UV));
		alb = tx.rgb * vcol.rgb;
		if (cls == 3) {
			em = vcol.rgb * tx.rgb * glow_energy * k;
			alb *= 0.05;
		} else {
			em = tx.rgb * vcol.rgb * tx.a * window_energy * k;
			alb *= 1.0 - tx.a * 0.8;
		}
	}
	// pied des parapets plus sombre (occlusion simulée)
	if (cls == 0 && wpos.y > -0.1 && wpos.y < 0.6 && abs(nw.y) < 0.5) {
		alb *= mix(0.55, 1.0, smoothstep(0.0, 0.35, wpos.y));
	}
	vec3 f0 = mix(vec3(0.04), alb, metal);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	if (a != 4 && a != 3) {
		float fres = 0.04 + 0.96 * pow(1.0 - max(dot(nw, v), 0.0), 5.0);
		em += nl_lights(wpos, nw, v, alb * (1.0 - metal), 1.0 - rough, rough, t) * 0.8;
		if (wpos.y > -1.0) {
			em += nl_reflect(wpos, nw, v, max(rough, 0.25), t) * (wet_refl + fres) * (cls == 3 ? 0.0 : 1.0);
		}
	}
	EMISSION = em;
}
