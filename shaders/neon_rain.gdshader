// Cité Néon — pluie : un MultiMesh de traits (un quad chacun), entièrement animé ici. Chaque goutte tombe
// dans une boîte qui suit le point visé par la caméra (positions repliées), y compris dans le vide autour du toit.
// Aucune donnée par instance : la graine vient de INSTANCE_ID.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;

uniform vec3 box = vec3(30.0, 22.0, 26.0);   // largeur, hauteur, profondeur de la boîte
uniform float y_top = 11.0;
uniform float speed = 13.0;
uniform vec2 wind = vec2(1.2, 0.6);
uniform float drop_len = 0.55;
uniform float drop_w = 0.014;
uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.95);
uniform float alpha = 0.32;

varying float vfade;

vec3 h3(float n) {
	return fract(sin(vec3(n * 12.9898, n * 78.233, n * 37.719)) * 43758.5453);
}

void vertex() {
	// point du sol visé par la caméra
	vec3 cpos = INV_VIEW_MATRIX[3].xyz;
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	vec3 aim = cpos + fwd * (cpos.y / max(-fwd.y, 0.2));
	float id = float(INSTANCE_ID);
	vec3 s = h3(id + 0.37);
	float sp = speed * (0.85 + 0.3 * s.z);
	float fall = TIME * sp;
	vec3 p;
	p.y = y_top - mod(s.y * box.y + fall, box.y);
	float drift = (y_top - p.y) / sp;
	p.xz = s.xz * box.xz + wind * drift;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 ctr = aim;
	p.xz = ctr.xz + mod(p.xz - ctr.xz + box.xz * 0.5, box.xz) - box.xz * 0.5;
	vec3 vel = normalize(vec3(wind.x, -sp, wind.y));
	vec3 vd = normalize(p - cam);
	vec3 side = normalize(cross(vel, vd));
	VERTEX = p + side * VERTEX.x * drop_w / 1.0 + vel * VERTEX.y * drop_len;
	// discrètes près de la caméra, effacées au loin
	float d = length(p - cam);
	vfade = smoothstep(2.0, 5.0, d) * (1.0 - smoothstep(26.0, 40.0, d));
}

void fragment() {
	float a = (1.0 - abs(UV.x - 0.5) * 2.0) * smoothstep(0.0, 0.6, 1.0 - UV.y) * smoothstep(0.0, 0.15, UV.y);
	ALBEDO = tint * alpha * a * vfade;
}
