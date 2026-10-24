// Apparences de Jo (scripts/loot.gd) : remappage des couleurs par sommet de jo.glb (tools/chars/jo.py).
// Les couleurs du GLB (sRGB) sont la teinte de base multipliée par l'occlusion et le dégradé vertical de
// sculpt.py : on reconnaît chaque famille à sa teinte et sa saturation (qui ne bougent pas), et on garde le
// rapport de luminosité. Trois familles : combinaison blanche (#F4F1EA, #D6D1C6), orange (#FF7A2F,
// #E0601E), turquoise (#3CF2D8). Peau, cheveux, bleu nuit et métal ne sont pas touchés.
// Fait dans vertex() : les poids s'interpolent proprement aux limites de couleur, rien au pixel.

uniform vec3 suit = vec3(0.957, 0.945, 0.918);   // sRGB
uniform vec3 accent = vec3(1.0, 0.478, 0.184);
uniform vec3 lit_col = vec3(0.235, 0.949, 0.847);
uniform float suit_on = 1.0;  // 0 sur la tête : les reflets blancs des yeux restent blancs
uniform float rainbow = 0.0;  // 1 : la lumière fait le tour des teintes

vec3 skin_hsv2rgb(float h, float s, float v) {
	vec3 k = clamp(abs(fract(vec3(h) + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

float skin_band(float h, float a, float b, float soft) {
	return smoothstep(a - soft, a + soft, h) * (1.0 - smoothstep(b - soft, b + soft, h));
}

vec3 skin_remap(vec3 c, vec3 pos, float t) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float d = mx - mn;
	float sat = d / max(mx, 1e-4);
	float hue = 0.0;  // degrés
	if (d > 1e-4) {
		if (mx == c.r) {
			hue = 60.0 * mod((c.g - c.b) / d, 6.0);
		} else if (mx == c.g) {
			hue = 60.0 * ((c.b - c.r) / d + 2.0);
		} else {
			hue = 60.0 * ((c.r - c.g) / d + 4.0);
		}
	}
	float w_suit = (1.0 - smoothstep(0.10, 0.16, sat)) * smoothstep(0.36, 0.48, mx) * suit_on;
	float w_acc = smoothstep(0.58, 0.68, sat) * skin_band(hue, 12.0, 38.0, 4.0);
	float w_lit = smoothstep(0.45, 0.55, sat) * skin_band(hue, 150.0, 195.0, 6.0);
	vec3 lit = lit_col;
	if (rainbow > 0.5) {
		lit = skin_hsv2rgb(fract(t * 0.18 + pos.y * 0.9 + pos.x * 0.6), 0.75, 1.0);
	}
	vec3 o = c;
	o = mix(o, suit * (mx / 0.957), w_suit);
	o = mix(o, accent * mx, w_acc);
	o = mix(o, lit * (mx / 0.949), w_lit);
	return clamp(o, 0.0, 1.0);
}

vec3 skin_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}
