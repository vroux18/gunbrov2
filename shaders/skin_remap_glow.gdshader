// Pièces lumineuses de Jo (verres, voyants, filet du blaster) avec une apparence : sans ombrage, comme
// Rig3D.glow_mat ; seule la lumière turquoise change (les lumières blanches de l'équipement restent).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

#include "res://shaders/skin_remap.gdshaderinc"

uniform vec3 tint = vec3(1.0);  // albedo_color du matériau d'origine, énergie comprise

void vertex() {
	COLOR.rgb = skin_remap(COLOR.rgb, VERTEX, TIME);
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = skin_to_linear(COLOR.rgb);  // comme vertex_color_is_srgb de Rig3D.body_mat
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
}
