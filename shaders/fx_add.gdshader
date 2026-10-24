// Particules additives (éclairs, étincelles, braises, feu) : voir fx_particle.gdshaderinc.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/fx_particle.gdshaderinc"

uniform float streak = 1.0;  // 0 : texture déjà dessinée en long (flamme de bouche), pas de profil de traînée

void fragment() {
	vec2 uv = UV;
	float tf = 1.0;
	if (v_str * streak > 0.5) {
		// étirée : profil rond en travers, tête vive (haut de la quad) et queue qui s'efface
		uv.y = 0.5 + (UV.y - 0.5) * 0.55;
		tf = smoothstep(1.0, 0.12, UV.y);
	}
	vec4 t = texture(tex, uv);
	ALBEDO = v_col.rgb * t.rgb * energy;
	ALPHA = t.a * v_col.a * tf;
}
