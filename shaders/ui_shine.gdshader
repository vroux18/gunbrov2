shader_type canvas_item;
// Reflet d'interface : une bande claire oblique balaie le nœud toutes les `period` secondes.
// Ne touche que les pixels clairs (lettres, face du bouton) : les contours sombres restent nets.

uniform float span = 300.0;     // largeur du nœud en px
uniform float period = 2.6;     // secondes entre deux passages
uniform float strength = 0.55;
uniform float band = 0.10;      // demi-largeur de la bande, en fraction de `span`
uniform float offset = 0.0;     // déphasage (plusieurs nœuds qui ne brillent pas en même temps)

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float x = (lp.x + lp.y * 0.45) / span;
	float ph = fract(TIME / period + offset) * 2.4 - 0.6;
	float b = smoothstep(band, 0.0, abs(x - ph));
	float lum = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), b * strength * smoothstep(0.12, 0.45, lum));
}
