// Cité Néon — parapets, rambardes, antennes du toit : même shader que la tour (neon_shell.gdshaderinc) sans
// la carte de façade ni les écrans, absents de ce maillage. Rendu identique, shader plus court.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#define NS_EDGES
#include "res://shaders/neon_shell.gdshaderinc"
