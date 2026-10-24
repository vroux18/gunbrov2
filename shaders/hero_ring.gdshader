// Anneau de Jo au sol : cercle net à liseré clair, voile intérieur, trois crans qui tournent lentement et
// une flèche orange qui montre la visée. Testé en profondeur : les pieds de Jo passent devant
// (la copie « à travers le décor » est un anneau ground_ring discret).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.235, 0.949, 0.847, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.478, 0.184, 1.0);
uniform float energy = 1.8;
uniform float aim = 0.0;  // angle de visée (atan2(x, z) dans le plan du sol)
uniform float spin = 0.0;  // rotation des crans
uniform float radius = 0.7;  // rayon de l'anneau (UV : bord du quad = 1)


// triangle pointé vers +Y : base en y = b (demi-largeur h), pointe en y = b + l
float _tri(vec2 q, float b, float l, float h) {
	float k = (q.y - b) / l;
	return step(0.0, k) * step(k, 1.0) * step(abs(q.x), h * (1.0 - k));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.x, p.y);
	float aa = fwidth(r) * 1.5;
	// anneau principal et liseré intérieur fin
	float ring = smoothstep(radius - 0.075, radius - 0.075 + aa, r) * (1.0 - smoothstep(radius - aa, radius, r));
	float inner = smoothstep(radius - 0.16, radius - 0.16 + aa, r) * (1.0 - smoothstep(radius - 0.135 - aa, radius - 0.135, r)) * 0.45;
	// voile intérieur très doux
	float veil = (1.0 - smoothstep(0.0, radius, r)) * 0.06;
	// trois crans sur le pourtour, qui tournent
	float seg = fract((a + spin) / (TAU / 3.0));
	float ticks = step(abs(seg - 0.5), 0.07) * smoothstep(radius + 0.02, radius + 0.02 + aa, r) * (1.0 - smoothstep(radius + 0.09 - aa, radius + 0.09, r));
	// flèche de visée : chevron devant l'anneau (repère tourné pour que la visée soit +Y)
	vec2 q = vec2(p.x * cos(aim) - p.y * sin(aim), p.x * sin(aim) + p.y * cos(aim));
	float chevron = _tri(q, radius + 0.05, 0.19, 0.22) * (1.0 - _tri(q + vec2(0.0, 0.085), radius + 0.05, 0.19, 0.22));
	vec3 c = color.rgb * (ring + inner + veil + ticks * 0.8);
	c += accent.rgb * chevron * 0.62;
	ALBEDO = c * energy;
	ALPHA = clamp(ring + inner + veil + ticks + chevron, 0.0, 1.0) * color.a;
}
