// Anneau au sol (visible à travers le décor) (télégraphes d'attaque, onde de choc, sas) : épaisseur et remplissage paramétrables.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.4, 1.0);
uniform float energy = 1.6;
uniform float width = 0.12;
uniform float fill = 0.15;
uniform float progress = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float ring = smoothstep(1.0 - width, 1.0 - width * 0.5, r) * smoothstep(1.0, 1.0 - width * 0.3, r);
	float inner = step(r, progress) * fill;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(ring + inner, 0.0, 1.0) * color.a;
}
