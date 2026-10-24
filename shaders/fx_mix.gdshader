// Particules opaques à fondu (fumée) : bouffée ombrée (rgb de la texture = relief), voir fx_particle.gdshaderinc.
// La couleur de départ peut être chaude (fumée qui sort du feu) : elle refroidit vers la couleur de fin.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/fx_particle.gdshaderinc"

uniform float shade = 0.75;  // force du relief

void fragment() {
	vec4 t = texture(tex, UV);
	float s = mix(1.0, t.r * 1.5, shade);
	ALBEDO = v_col.rgb * s * energy;
	ALPHA = clamp(t.a * v_col.a, 0.0, 1.0);
}
