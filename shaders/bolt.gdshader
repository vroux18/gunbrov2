// Projectile : capsule émissive (cœur blanc, bord teinté), couleur d'instance du MultiMesh.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform float energy = 2.8;

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// cœur blanc teinté, bord franchement coloré : le trait garde sa couleur sous le flou lumineux
	vec3 core = mix(mix(vec3(1.0), COLOR.rgb, 0.25), COLOR.rgb, smoothstep(0.05, 0.55, rim));
	ALBEDO = core * energy;
}
