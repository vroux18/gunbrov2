// Projectile : capsule émissive (cœur blanc, bord teinté), couleur d'instance du MultiMesh.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform float energy = 3.2;

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 core = mix(vec3(1.0), COLOR.rgb, smoothstep(0.15, 0.75, rim));
	ALBEDO = core * energy;
}
