shader_type spatial;
// Écran-panneau de L'Enseigne (boss du monde 2) : matrice de DEL 40 x 26 peinte en code.
// Pub qui défile (idéogrammes inventés), visage pixelisé (ricanement, colère, grimace), alerte, spirale,
// mort (neige, fissure, extinction). Repère de l'écran donné par les uniformes (part screen_glow,
// pivot au centre du panneau) ; face avant : visage et pub, face arrière : pub seule.
render_mode unshaded, cull_back;

uniform vec3 ax_x = vec3(1.0, 0.0, 0.0);
uniform vec3 ax_y = vec3(0.0, 0.966, -0.259);
uniform vec3 ax_n = vec3(0.0, 0.259, 0.966);
uniform vec2 half_size = vec2(0.74, 0.49);
uniform float clock = 0.0;
uniform float face = 0.0;    // 0 pub, 1 visage
uniform float mood = 0.0;    // 0 ricanement, 1 colère
uniform float ouch = 0.0;    // grimace (coup encaissé)
uniform float alert = 0.0;   // préparation de la spirale
uniform float spiral = 0.0;
uniform float spin = 0.0;    // angle de la spirale affichée
uniform float flash = 0.0;
uniform float glitch = 0.0;
uniform float noise = 0.0;   // neige (mort)
uniform float crack = 0.0;   // fissure 0..1
uniform float off = 0.0;     // extinction
uniform float energy = 1.0;
uniform float look = 0.0;    // regard (-1..1)
uniform float blink = 0.0;
uniform float ad_seed = 0.0; // change de pub

varying vec3 lp;

const float GW = 40.0;
const float GH = 26.0;

vec3 lin(vec3 c) { return c * c; }

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	lp = VERTEX;
}

// Idéogramme inventé 5 x 5 : traits tirés d'un hachage (barres, montants partiels, diagonales).
float glyph(float id, vec2 g) {
	if (g.x < 0.0 || g.y < 0.0 || g.x > 4.0 || g.y > 4.0) return 0.0;
	float h = h21(vec2(id, 7.13));
	float h2 = h21(vec2(id, 3.71));
	float h3 = h21(vec2(id, 1.93));
	float on = 0.0;
	// colonne vertébrale toujours présente (montant ou barre), puis traits tirés au sort
	float vert = step(0.5, fract(h * 31.0));
	if (vert > 0.5 && g.x == 2.0) on = 1.0;
	if (vert < 0.5 && g.y == 2.0) on = 1.0;
	if (vert < 0.5 && g.x == 1.0 + 2.0 * step(0.5, h2) && g.y >= 2.0) on = 1.0;
	if (vert > 0.5 && g.y == 3.0 && fract(h3 * 3.0) > 0.4) on = 1.0;
	if (g.y == 4.0 && h > 0.3) on = 1.0;
	if (g.y == 2.0 && fract(h * 7.0) > 0.3) on = 1.0;
	if (g.y == 0.0 && fract(h * 13.0) > 0.55) on = 1.0;
	if (g.x == 0.0 && fract(h2 * 5.0) > 0.4 && g.y >= floor(fract(h2 * 11.0) * 3.0)) on = 1.0;
	if (g.x == 2.0 && fract(h2 * 3.0) > 0.35 && g.y <= 2.0 + floor(fract(h2 * 17.0) * 3.0)) on = 1.0;
	if (g.x == 4.0 && fract(h3 * 5.0) > 0.5 && g.y >= floor(fract(h3 * 7.0) * 3.0)) on = 1.0;
	if (fract(h3 * 11.0) > 0.72 && g.x == g.y) on = 1.0;
	if (fract(h3 * 19.0) > 0.72 && g.x == 4.0 - g.y && g.y < 3.0) on = 1.0;
	return on;
}

vec3 pal(float k) {
	k = mod(k, 3.0);
	if (k < 1.0) return lin(vec3(1.0, 0.235, 0.675));
	if (k < 2.0) return lin(vec3(0.235, 0.55, 1.0));
	return lin(vec3(1.0, 0.75, 0.3));
}

// Pub : fond dégradé à rayures, deux grands idéogrammes, cœur qui bat, bandeau défilant, chevrons.
vec3 ad(vec2 c, float seed) {
	vec3 col = mix(lin(vec3(0.3, 0.12, 0.5)), lin(vec3(0.1, 0.2, 0.55)), c.y / GH) * 0.75;
	float stripe = step(0.5, fract((c.x + c.y - clock * 5.0) / 8.0));
	col += lin(vec3(1.0, 0.235, 0.675)) * 0.12 * stripe;
	float slot = floor(clock / 2.4) + seed * 17.0;
	// grands idéogrammes (x2) en haut
	vec2 g1 = floor((c - vec2(17.0, 13.0)) / 2.0);
	vec2 g2 = floor((c - vec2(29.0, 13.0)) / 2.0);
	float big1 = glyph(slot * 3.0 + 1.0, g1);
	float big2 = glyph(slot * 3.0 + 2.0, g2);
	col = mix(col, pal(slot), big1);
	col = mix(col, pal(slot + 1.0), big2);
	// cœur pixel qui bat, à gauche
	vec2 hc = c - vec2(7.5, 17.5);
	float beat = 1.0 + 0.18 * step(0.5, fract(clock * 1.6));
	hc /= beat;
	float heart = step(pow(hc.x * hc.x / 22.0 + hc.y * hc.y / 22.0 - 1.0, 3.0) - hc.x * hc.x * hc.y / 110.0, 0.0);
	col = mix(col, lin(vec3(1.0, 0.3, 0.7)), heart);
	// bandeau sombre défilant
	if (c.y >= 3.0 && c.y <= 9.0) {
		col = lin(vec3(0.06, 0.04, 0.12));
		float xs = c.x + floor(clock * 9.0);
		float gid = floor(xs / 6.0);
		vec2 g = vec2(mod(xs, 6.0), c.y - 4.0);
		float on = glyph(gid + seed * 31.0, g);
		col = mix(col, pal(gid), on);
	}
	// chevrons dorés en bas
	if (c.y < 2.0) {
		float ch = step(0.5, fract((c.x + c.y * (c.y < 1.0 ? -1.0 : 1.0) * 0.0 - clock * 6.0) / 4.0));
		col = mix(lin(vec3(0.05, 0.03, 0.1)), lin(vec3(1.0, 0.72, 0.28)), ch * 0.85);
	}
	return col;
}

// Visage : yeux carrés, pupilles, sourcils, joues, bouche (ricanement, dents serrées ou grimace).
vec3 face_col(vec2 c) {
	vec3 bg = mix(lin(vec3(0.3, 0.1, 0.48)), lin(vec3(0.55, 0.06, 0.25)), mood);
	bg *= 0.75 + 0.25 * step(0.5, fract(c.y * 0.5));
	vec3 col = bg;
	vec3 skin = lin(vec3(1.0, 0.86, 0.96));
	vec3 pink = lin(vec3(1.0, 0.235, 0.675));
	vec3 blue = lin(vec3(0.235, 0.55, 1.0));
	vec3 dark = lin(vec3(0.06, 0.02, 0.1));
	for (int e = 0; e < 2; e++) {
		float ex = e == 0 ? 12.0 : 27.0;
		float sgn = e == 0 ? -1.0 : 1.0;
		vec2 d = c - vec2(ex, 15.0);
		if (ouch > 0.5) {
			// yeux en chevrons > <
			float a = abs(d.y);
			float on = step(abs(d.x * -sgn - (a - 2.0)), 0.6) * step(a, 3.0);
			col = mix(col, skin, on);
		} else {
			float hh = 3.5 * (1.0 - blink) + 0.5;
			float brow = 19.0 - 1.5 * mood + mood * 0.6 * (d.x * sgn);
			float lid = mix(17.0, brow - 1.0, mood);  // paupière mi-close : air narquois
			float inside = step(abs(d.x), 3.0) * step(abs(d.y), hh) * step(c.y, lid);
			float corner = step(2.5, abs(d.x)) * step(hh - 0.5, abs(d.y));
			inside *= 1.0 - corner;
			col = mix(col, skin, inside);
			vec2 pd = d - vec2(look * 1.4, -0.5 - mood * 0.5);
			float pup = step(abs(pd.x), 1.0) * step(abs(pd.y), 1.5) * inside;
			col = mix(col, dark, pup);
			// reflet
			float hl = step(abs(d.x - 1.5 - look), 0.5) * step(abs(d.y - 2.0), 0.5) * inside * (1.0 - mood);
			col = mix(col, vec3(1.0), hl);
			// sourcil en V (colère) ou paupière plate
			float bon = step(abs(c.y - brow), 0.6) * step(abs(d.x), 3.6) * mood;
			bon += step(abs(c.y - 18.0), 0.5) * step(abs(d.x), 3.5) * (1.0 - mood) * (1.0 - blink);
			col = mix(col, pink, bon);
		}
		// joues bleues
		vec2 ck = c - vec2(ex + sgn * 2.0, 9.5);
		float cheek = step(abs(ck.x), 1.5) * step(abs(ck.y), 0.6) * (1.0 - mood);
		col = mix(col, blue, cheek * 0.9);
	}
	float x = c.x - 19.5;
	if (ouch > 0.5) {
		// bouche en zigzag
		float zy = 6.0 + (mod(floor(c.x), 4.0) < 2.0 ? mod(floor(c.x), 2.0) : 1.0 - mod(floor(c.x), 2.0));
		float on = step(abs(c.y - zy), 0.6) * step(abs(x), 7.0);
		col = mix(col, skin, on);
	} else if (mood < 0.5) {
		// ricanement : large sourire en croissant, dents en haut
		float yt = 8.0 + 0.012 * x * x;
		float yb = 3.2 + 0.035 * x * x;
		float inm = step(c.y, yt) * step(yb, c.y) * step(abs(x), 10.0);
		float rim = step(abs(c.y - yt), 0.6) * step(abs(x), 10.5) + step(abs(c.y - yb), 0.6) * step(abs(x), 10.0);
		col = mix(col, dark, inm);
		float teeth = inm * step(yt - 1.6, c.y) * step(0.5, mod(floor(c.x), 3.0));
		col = mix(col, skin, teeth);
		col = mix(col, pink, clamp(rim, 0.0, 1.0) * (1.0 - teeth));
	} else {
		// colère : dents serrées
		float outer = step(abs(x), 8.0) * step(3.0, c.y) * step(c.y, 8.0);
		float inner = step(abs(x), 7.0) * step(4.0, c.y) * step(c.y, 7.0);
		col = mix(col, pink, outer);
		vec3 tc = mix(skin, lin(vec3(0.7, 0.55, 0.75)), step(mod(c.x, 2.0), 0.5));
		tc = mix(tc, dark, step(abs(c.y - 5.0), 0.5));
		col = mix(col, tc, inner);
	}
	return col;
}

// Alerte : fond qui clignote rose/sombre, bord rayé or, trois points d'exclamation.
vec3 alert_col(vec2 c) {
	float blinkk = step(0.5, fract(clock * 7.0));
	vec3 col = mix(lin(vec3(0.25, 0.02, 0.12)), lin(vec3(1.0, 0.235, 0.675)), blinkk);
	vec3 gold = lin(vec3(1.0, 0.75, 0.3));
	float border = step(c.x, 2.0) + step(GW - 3.0, c.x) + step(c.y, 2.0) + step(GH - 3.0, c.y);
	float haz = step(0.5, fract((c.x + c.y + floor(clock * 10.0)) / 4.0));
	col = mix(col, mix(lin(vec3(0.05, 0.02, 0.08)), gold, haz), clamp(border, 0.0, 1.0));
	for (int k = 0; k < 3; k++) {
		float ex = 10.0 + float(k) * 9.5;
		vec2 d = c - vec2(ex, 0.0);
		float bar = step(abs(d.x), 1.2) * step(10.0, c.y) * step(c.y, 21.0);
		float dot_ = step(abs(d.x), 1.2) * step(5.0, c.y) * step(c.y, 7.0);
		col = mix(col, mix(gold, lin(vec3(0.05, 0.02, 0.08)), blinkk), clamp(bar + dot_, 0.0, 1.0));
	}
	return col;
}

// Spirale : trois bras roses et bleus qui tournent, œil furieux au centre.
vec3 spiral_col(vec2 c) {
	vec2 p = c - vec2(19.5, 12.5);
	float a = atan(p.y, p.x);
	float r = length(p);
	float k = fract(3.0 * a / TAU + r * 0.075 - spin * 3.0 / TAU);
	vec3 col = k < 0.5 ? lin(vec3(1.0, 0.235, 0.675)) : lin(vec3(0.235, 0.55, 1.0));
	col *= 0.55 + 0.45 * step(0.12, abs(fract(k * 2.0) - 0.5));
	float core = step(r, 4.5);
	col = mix(col, lin(vec3(1.0, 0.86, 0.96)), core);
	col = mix(col, lin(vec3(0.06, 0.02, 0.1)), step(r, 2.2));
	return col;
}

void fragment() {
	float side = dot(lp, ax_n);
	float u = dot(lp, ax_x) / half_size.x;
	float v = dot(lp, ax_y) / half_size.y;
	if (side < 0.0) u = -u;
	vec2 g = vec2((u * 0.5 + 0.5) * GW, (v * 0.5 + 0.5) * GH);
	// déchirures horizontales (dégâts, mort)
	float row = floor(g.y);
	float tear = step(0.82, h21(vec2(row, floor(clock * 14.0)))) * (glitch + noise);
	g.x += tear * (h21(vec2(row, floor(clock * 14.0) + 3.0)) - 0.5) * 10.0;
	vec2 c = floor(g);
	vec2 f = fract(g);
	vec3 col;
	if (side >= 0.0) {
		col = mix(ad(c, ad_seed), face_col(c), face);
	} else {
		col = ad(c, ad_seed + 0.5);
	}
	col = mix(col, alert_col(c), alert);
	col = mix(col, spiral_col(c), spiral);
	// neige de la mort
	float sn = h21(c + floor(clock * 24.0) * vec2(1.7, 3.1));
	col = mix(col, lin(vec3(0.9, 0.75, 1.0)) * sn * sn, noise);
	col += vec3(1.0, 0.9, 0.95) * flash * 0.6;
	col *= 1.0 - off;
	// fissure : ligne brisée qui descend du coin haut
	float xc = 23.0 - (GH - c.y) * 0.3 + 2.2 * sin(c.y * 1.3) + step(0.5, fract(c.y * 0.37)) * 1.5;
	float fill = step(GH * (1.0 - crack), c.y);
	float dist = abs(c.x - floor(xc));
	col = mix(col, vec3(0.0), step(dist, 0.5) * fill);
	col = mix(col, lin(vec3(1.0, 0.8, 0.95)) * (1.6 - 1.2 * off), step(0.5, dist) * step(dist, 1.5) * fill * 0.85);
	// grille de DEL et bord sombre
	float cell = max(abs(f.x - 0.5), abs(f.y - 0.5));
	col *= mix(0.5, 1.0, smoothstep(0.5, 0.34, cell));
	float edge = step(abs(u), 1.0) * step(abs(v), 1.0);
	ALBEDO = col * energy * edge + vec3(0.01, 0.005, 0.02);
}
