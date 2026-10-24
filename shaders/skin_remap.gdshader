// Corps de Jo avec une apparence : même rendu que Rig3D.body_mat (rugosité, reflet, liseré), couleurs remappées.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/skin_remap.gdshaderinc"

void vertex() {
	COLOR.rgb = skin_remap(COLOR.rgb, VERTEX, TIME);
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = skin_to_linear(COLOR.rgb);  // comme vertex_color_is_srgb de Rig3D.body_mat
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	RIM = 0.45;
	RIM_TINT = 0.35;
}
