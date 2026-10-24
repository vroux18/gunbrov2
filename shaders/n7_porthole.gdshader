// Nébuleuse 7 — vitre de hublot : la nébuleuse vue à l'infini derrière le mur (panorama du ciel
// échantillonné selon la direction du regard), assombrie au bord, avec un reflet de vitre.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D sky_tex : source_color, filter_linear_mipmap;
uniform float energy = 1.3;
uniform vec3 tint : source_color = vec3(0.85, 0.8, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// regard « à travers » le mur : direction sortante du hublot, inclinée par le point de vue (parallaxe)
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vd = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 d = normalize(-n * 1.1 + (vd - n * dot(vd, n)) * 1.7 + vec3(0.0, 0.12, 0.0));
	vec2 suv = vec2(atan(d.x, -d.z) / 6.28318 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159);
	vec3 c = texture(sky_tex, suv).rgb;
	c = pow(c, vec3(1.25)) * energy * tint;
	float r = length(UV - 0.5) * 2.0;
	c *= mix(1.0, 0.2, smoothstep(0.5, 1.0, r));
	float s = (1.0 - smoothstep(0.0, 0.06, abs((UV.x - 0.5) + (UV.y - 0.5) * 0.7 + 0.18))) * (1.0 - r * 0.6);
	ALBEDO = c + vec3(0.55, 0.62, 0.9) * s * 0.3 + vec3(0.01, 0.012, 0.03);
}
