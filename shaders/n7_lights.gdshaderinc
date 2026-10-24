// Nébuleuse 7 — éclairage simulé partagé par le sol, les marquages et les murs du hangar :
// plafonniers en grille (flaques au sol, reflets doux sur le métal), appliques murales, gyrophares tournants.
// Tout est ajouté en EMISSION : aucune lumière dynamique, aucun passage de rendu en plus.

uniform vec4 ceil_grid = vec4(3.75, 7.5, 7.6, 8.5);   // x0, pas en x, z0, pas en z
uniform vec2 ceil_count = vec2(5.0, 2.0);
uniform float ceil_h = 4.5;
uniform vec3 ceil_col : source_color = vec3(0.78, 0.84, 1.0);
uniform float ceil_energy = 2.4;
uniform vec4 lamp_grid = vec4(0.9, 36.6, 2.95, 3.0);  // x ouest, x est, z0, pas en z
uniform float lamp_count = 7.0;
uniform float lamp_h = 2.8;
uniform vec3 lamp_col_w : source_color = vec3(0.7, 0.62, 1.0);
uniform vec3 lamp_col_e : source_color = vec3(1.0, 0.72, 0.45);
uniform float lamp_energy = 0.8;
uniform vec4 beacons[4];   // xyz, phase
uniform vec3 beacon_col : source_color = vec3(1.0, 0.42, 0.08);
uniform float beacon_energy = 2.2;
uniform float arena_w = 37.5;

float n7_att(float d, float r) {
	float x = clamp(1.0 - (d * d) / (r * r), 0.0, 1.0);
	return x * x;
}

// lumière ponctuelle simplifiée : diffus de Lambert + GGX (visibilité approchée)
vec3 n7_point(vec3 lp, float r, float cone, vec3 wp, vec3 n, vec3 v, vec3 dif, vec3 f0, float rough) {
	vec3 L = lp - wp;
	float d = length(L);
	L /= max(d, 1e-3);
	float att = n7_att(d, r) * smoothstep(cone, cone + 0.3, L.y);
	float ndl = max(dot(n, L), 0.0);
	vec3 h = normalize(L + v);
	float ndh = max(dot(n, h), 0.0);
	float a = max(rough * rough, 0.03);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (3.14159 * dd * dd);
	vec3 F = f0 + (1.0 - f0) * pow(1.0 - max(dot(v, h), 0.0), 5.0);
	return att * (dif * ndl + D * F * 0.25 * ndl);
}

vec3 n7_lights(vec3 wp, vec3 n, vec3 v, vec3 dif, vec3 f0, float rough, float tm) {
	vec3 acc = vec3(0.0);
	// plafonniers : les quatre plus proches
	vec2 gi = floor((wp.xz - ceil_grid.xz) / ceil_grid.yw);
	for (int a = 0; a < 2; a++) {
		for (int b = 0; b < 2; b++) {
			vec2 ij = gi + vec2(float(a), float(b));
			if (ij.x < 0.0 || ij.y < 0.0 || ij.x > ceil_count.x - 1.0 || ij.y > ceil_count.y - 1.0) {
				continue;
			}
			vec3 lp = vec3(ceil_grid.x + ij.x * ceil_grid.y, ceil_h, ceil_grid.z + ij.y * ceil_grid.w);
			acc += ceil_col * ceil_energy * n7_point(lp, 8.0, 0.6, wp, n, v, dif, f0, rough);
		}
	}
	// appliques du mur le plus proche : les deux plus proches
	bool west = wp.x < arena_w * 0.5;
	float lx = west ? lamp_grid.x : lamp_grid.y;
	vec3 lcol = (west ? lamp_col_w : lamp_col_e) * lamp_energy;
	float k0 = floor((wp.z - lamp_grid.z) / lamp_grid.w);
	for (int k = 0; k < 2; k++) {
		float kk = k0 + float(k);
		if (kk < 0.0 || kk > lamp_count - 1.0) {
			continue;
		}
		vec3 lp = vec3(lx, lamp_h, lamp_grid.z + kk * lamp_grid.w);
		acc += lcol * n7_point(lp, 4.2, 0.2, wp, n, v, dif, f0, rough);
	}
	// gyrophares : un faisceau qui tourne, une lueur à la base
	for (int i = 0; i < 4; i++) {
		vec4 b = beacons[i];
		if (b.y <= 0.0) {
			continue;
		}
		vec3 L = b.xyz - wp;
		float d = length(L);
		if (d > 7.0) {
			continue;
		}
		L /= d;
		vec2 q = wp.xz - b.xz;
		float ang = atan(q.y, q.x);
		float da = mod(ang - (tm * 3.4 + b.w) + 3.14159, 6.28318) - 3.14159;
		float beam = pow(max(cos(da), 0.0), 18.0) * 1.4 + 0.08;
		float ndl = max(dot(n, L), 0.0);
		acc += beacon_col * beacon_energy * beam * n7_att(d, 7.0) * ndl * (dif + f0 * 0.5);
	}
	return acc;
}

// Soleil et lumières de Godot, avec un gain propre au matériau : le sol prend moins de soleil pour que
// les flaques des plafonniers se lisent (Lambert + GGX, ombres comprises dans ATTENUATION).
uniform float sun_gain = 1.0;

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR * sun_gain / 3.14159;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, h), 0.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.03);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float fr = 0.06 + 0.94 * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	SPECULAR_LIGHT += a2 / (3.14159 * dd * dd) * fr * 0.25 * ndl * ATTENUATION * LIGHT_COLOR * sun_gain;
}
