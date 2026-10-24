// Contour des personnages : coque inversée (faces arrière, gonflées le long de la normale), épaisseur
// constante à l'écran (en pixels d'un écran de 720 px de haut), couleur = celle de la surface, très assombrie.
// Deuxième passe (next_pass) du matériau character.gdshader.
shader_type spatial;
// depth_draw_never : passe transparente, donc ni pré-passe de profondeur ni passe d'ombre (coût divisé par deux)
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform float width = 1.5;
uniform vec3 ink : source_color = vec3(0.035, 0.03, 0.09);
uniform float ink_hue = 0.035;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 vn = mat3(MODELVIEW_MATRIX) * NORMAL;
	// direction de la normale à l'écran, en pixels
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy * VIEWPORT_SIZE;
	float l = length(dir);
	dir = l > 1e-5 ? dir / l : vec2(0.0);
	// pixels (écran de 720 px de haut) -> espace de découpe
	float w = width * VIEWPORT_SIZE.y / 720.0;
	clip.xy += dir * (2.0 * w / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink + (OUTPUT_IS_SRGB ? COLOR.rgb : srgb_to_linear(COLOR.rgb)) * ink_hue;
}
