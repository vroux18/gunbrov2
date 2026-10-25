// Contour d'encre de Jo (deuxième passe de jo_comic.gdshader) : coque inversée gonflée d'une épaisseur
// constante à l'écran (pixels d'un écran de 720 px de haut). La direction de gonflement est la normale lissée
// par position, encodée en octaèdre dans UV par tools/blender/jo_lib.py : le contour ne se fend pas aux
// arêtes vives. Sans UV (équipement sculpté en SDF), la normale du maillage. Ennemis en style BD (rig3d.gd
// comic_mat) : uv_normal faux, la normale du maillage, trait plus épais.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

// épaisseur : `world` mètres, bornée entre min_px et max_px (pixels d'un écran de 720 px de haut) : un trait
// franc en gros plan (Relais, apparences), un filet d'un pixel en jeu, où Jo ne fait que ~55 px de haut
uniform float world = 0.011;
uniform float min_px = 1.1;
uniform float max_px = 3.4;
uniform vec3 ink : source_color = vec3(0.02, 0.02, 0.035);
// normale lissée encodée dans UV (modèles de Jo) ; faux : normale du maillage
uniform bool uv_normal = true;

vec3 oct_decode(vec2 e) {
	e = e * 2.0 - 1.0;
	vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
	float t = max(-n.z, 0.0);
	n.x += n.x >= 0.0 ? -t : t;
	n.y += n.y >= 0.0 ? -t : t;
	return normalize(n);
}

void vertex() {
	vec3 nrm = (uv_normal && (UV.x + UV.y) > 0.0) ? oct_decode(UV) : NORMAL;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 vn = mat3(MODELVIEW_MATRIX) * nrm;
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy * VIEWPORT_SIZE;
	float l = length(dir);
	dir = l > 1e-5 ? dir / l : vec2(0.0);
	float ppm = PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / max(clip.w, 1e-4);
	float w = clamp(world * ppm, min_px * VIEWPORT_SIZE.y / 720.0, max_px * VIEWPORT_SIZE.y / 720.0);
	clip.xy += dir * (2.0 * w / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink;
}
