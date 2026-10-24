"""L'Enseigne : mécha géant, mascotte publicitaire de la Cité Néon déchue (boss du monde 2).

Torse en grand panneau publicitaire à deux faces (écrans animés par shader : pub qui défile, visage
pixelisé, alerte, spirale ; voir scripts/mobs/boss2.gd), bordé d'un tube néon rose devant et bleu derrière,
barres lumineuses sur le dessus. Tête : une enseigne au néon (cadre rose, idéogrammes
inventés bleus, ampoules de marquise), portée par un mât. Bras : deux projecteurs de scène sur étrier
(volets, lentille rose à droite, bleue à gauche). Jambes courtes et trapues, gros pieds à embouts dorés.
Carrosserie sombre prune, touches d'or. Robot, jamais animal.
Regarde vers +Z ; sa droite est en -X. Hauteur ~3,25 (3,3 avec l'antenne), largeur ~3,15 (Jo : 1,1).

Hiérarchie :
  base (bassin) ─ leg_r ─ shin_r, leg_l ─ shin_l, base_glow
       └ upper (tourelle de taille : tourne pendant la spirale) ─ screen_glow, bezel_glow,
               head (mât + enseigne) ─ head_glow,
               arm_r ─ proj_r ─ proj_r_glow, arm_l ─ proj_l ─ proj_l_glow
"""
from sculpt import *

CASE = "#272139"  # carrosserie sombre prune
CASE_L = "#433A63"  # plaques en relief
CASE_D = "#161325"  # métal très sombre
STEEL = "#8F8AAE"  # pièces mécaniques claires (rotules, étrier)
GOLD = "#FFE07A"
GOLD_D = "#E8B040"
PINK = "#FF3CAC"
PINK_L = "#FF9AD6"
BLUE = "#3C8CFF"
BLUE_L = "#9CC4FF"
WARM = "#FFE2A8"  # ampoules
BLACK = "#0E0C18"
SCREEN = "#FFFFFF"  # l'écran est peint par le shader


# ------------------------------------------------------------------ aides géométriques (comme boss.py)
def v(*a):
    return np.array(a, dtype=np.float64)


def nrm(a):
    a = np.asarray(a, dtype=np.float64)
    return a / np.linalg.norm(a)


def frame(zdir, up=(0, 1, 0)):
    """Repère orthonormé (colonnes x, y, z) dont l'axe z suit zdir."""
    z = nrm(zdir)
    x = np.cross(np.asarray(up, dtype=np.float64), z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross(v(1, 0, 0), z)
    x = nrm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def obox(c, half, r, M):
    c = np.asarray(c, dtype=np.float64)
    hb = np.asarray(half, dtype=np.float64) - r
    def f(P):
        Q = np.abs((P - c) @ M) - hb
        return np.linalg.norm(np.maximum(Q, 0.0), axis=1) + np.minimum(Q.max(axis=1), 0.0) - r
    m = float(np.linalg.norm(half))
    return Shape(f, c - m, c + m)


def oellip(c, radii, M):
    c = np.asarray(c, dtype=np.float64)
    rr = np.asarray(radii, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        k0 = np.linalg.norm(Q / rr, axis=1)
        k1 = np.linalg.norm(Q / (rr * rr), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    m = rr.max()
    return Shape(f, c - m, c + m)


def ocyl(c, r, h, rr, M):
    """Cylindre d'axe local z (rayon r, demi-longueur h)."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        d = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - (r - rr), np.abs(Q[:, 2]) - (h - rr)], axis=1)
        return np.minimum(d.max(axis=1), 0.0) + np.linalg.norm(np.maximum(d, 0.0), axis=1) - rr
    m = math.sqrt(r * r + h * h)
    return Shape(f, c - m, c + m)


def ocone(c, r0, r1, h, rr, M):
    """Tronc de cône d'axe local z : rayon r0 en z = -h, r1 en z = +h (approché, arrondi rr)."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        k = np.clip((Q[:, 2] + h) / (2 * h), 0.0, 1.0)
        rad = r0 + (r1 - r0) * k
        d = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - (rad - rr), np.abs(Q[:, 2]) - (h - rr)], axis=1)
        return (np.minimum(d.max(axis=1), 0.0) + np.linalg.norm(np.maximum(d, 0.0), axis=1) - rr) * 0.9
    m = math.sqrt(max(r0, r1) ** 2 + h * h)
    return Shape(f, c - m, c + m)


def otorus(c, R0, r, M):
    """Tore dans le plan local xy (axe local z)."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        q = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - R0, Q[:, 2]], axis=1)
        return np.linalg.norm(q, axis=1) - r
    m = R0 + r
    return Shape(f, c - m, c + m)


def rtube(c, hw, hh, cr, tr, M):
    """Tube (rayon tr) qui suit un rectangle arrondi (demi-tailles hw, hh, coins cr) du plan local xy."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        qx = np.abs(Q[:, 0]) - (hw - cr)
        qy = np.abs(Q[:, 1]) - (hh - cr)
        d2 = np.linalg.norm(np.stack([np.maximum(qx, 0), np.maximum(qy, 0)], axis=1), axis=1) + np.minimum(np.maximum(qx, qy), 0) - cr
        return np.sqrt(d2 * d2 + Q[:, 2] ** 2) - tr
    m = math.sqrt(hw * hw + hh * hh) + tr
    return Shape(f, c - m, c + m)


def inter(a, b, k=0.0):
    return Shape(lambda P: smax(a(P), b(P), k), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def halfspace(p0, n):
    p0 = np.asarray(p0, dtype=np.float64)
    n = nrm(n)
    return Shape(lambda P: (P - p0) @ n, p0 - 50, p0 + 50)


def cut(s, p0, n, k=0.0):
    """Garde la partie de s située du côté -n du plan (p0, n)."""
    return inter(s, halfspace(p0, n), k)


class Slab(Part):
    """Part faite de dalles plates exactes (pas de SDF) : l'écran, peint par un shader, n'a besoin que de
    quelques triangles. slab(centre, demi-tailles, repère M) ajoute une boîte orientée."""
    def __init__(self, *a, **kw):
        Part.__init__(self, *a, **kw)
        self.slabs = []

    def slab(self, c, half, M):
        self.slabs.append((np.asarray(c, dtype=np.float64), np.asarray(half, dtype=np.float64), M))

    def mesh(self):
        ms = []
        for c, half, M in self.slabs:
            T = np.eye(4)
            T[:3, :3] = M
            T[:3, 3] = c
            ms.append(trimesh.creation.box(extents=half * 2.0, transform=T))
        tm = trimesh.util.concatenate(ms)
        rgba = np.tile(np.array([255, 255, 255, 255], dtype=np.uint8), (len(tm.vertices), 1))
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=rgba)
        tm.apply_translation(-self.pivot)
        return tm


def rrect_path(c, hw, hh, cr, M, n_corner=6):
    """Points d'un rectangle arrondi (plan local xy du repère M), dans l'ordre."""
    pts = []
    for qx, qy, a0 in ((1, 1, 0.0), (-1, 1, 90.0), (-1, -1, 180.0), (1, -1, 270.0)):
        cx, cy = qx * (hw - cr), qy * (hh - cr)
        for i in range(n_corner + 1):
            a = math.radians(a0 + 90.0 * i / n_corner)
            pts.append(np.asarray(c) + M[:, 0] * (cx + cr * math.cos(a)) + M[:, 1] * (cy + cr * math.sin(a)))
    return pts


def sweep(pts, r, color, sides=8, closed=True, seg=0.05):
    """Tube exact (sans SDF) le long d'une polyligne, couleur unie : néons et cadres fins, très légers."""
    P = []
    for i in range(len(pts) - (0 if closed else 1)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n = max(1, int(math.ceil(np.linalg.norm(b - a) / seg)))
        for k in range(n):
            P.append(a + (b - a) * (k / n))
    if not closed:
        P.append(pts[-1])
    P = np.array(P)
    N = len(P)
    V = []
    for i in range(N):
        t = P[(i + 1) % N] - P[i - 1] if closed else P[min(i + 1, N - 1)] - P[max(i - 1, 0)]
        F = frame(t)
        for s in range(sides):
            a = s * math.tau / sides
            V.append(P[i] + (F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)) * r)
    F_ = []
    rings = N if closed else N - 1
    for i in range(rings):
        j = (i + 1) % N
        for s in range(sides):
            s2 = (s + 1) % sides
            a, b, c2, d = i * sides + s, i * sides + s2, j * sides + s2, j * sides + s
            F_ += [[a, b, c2], [a, c2, d]]
    tm = trimesh.Trimesh(vertices=np.array(V), faces=np.array(F_), process=True)
    trimesh.repair.fix_normals(tm)
    col = np.append(hexcol(color), 1.0)
    tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=np.tile((col * 255).astype(np.uint8), (len(tm.vertices), 1)))
    return tm


class BPart(Part):
    """Part qui signale les pièces restées au-dessus de leur budget ; accepte des maillages exacts (tubes)."""
    def __init__(self, *a, **kw):
        Part.__init__(self, *a, **kw)
        self.extra = []

    def _piece_mesh(self, pc):
        tm = Part._piece_mesh(self, pc)
        if tm is not None and len(tm.faces) > pc.tris * 1.2 and os.environ.get("B2_DEBUG"):
            print(f"    ! {self.name} : {len(tm.faces)} > {pc.tris}")
        return tm

    def mesh(self):
        ms = [m for m in (self._piece_mesh(pc) for pc in self.pieces) if m is not None] + list(self.extra)
        tm = trimesh.util.concatenate(ms)
        tm.apply_translation(-self.pivot)
        return tm


# ------------------------------------------------------------------ mesures
TILT = -15.0  # le panneau penche en arrière : l'écran regarde un peu vers la caméra haute
MT = rot_matrix(TILT, 0, 0)
TX, TY, TZ = MT[:, 0], MT[:, 1], MT[:, 2]
TC = v(0, 1.98, -0.02)  # centre du panneau
T_HALF = v(0.9, 0.64, 0.36)
S_HALF = v(0.74, 0.49)  # demi-tailles de l'écran (shader : mêmes valeurs dans boss2.gd)
S_DEPTH = 0.315  # écran : plan à TC ± TZ * S_DEPTH


def tp(x, y, z):
    """Point dans le repère du panneau."""
    return TC + TX * x + TY * y + TZ * z


HTILT = -24.0
MH = rot_matrix(HTILT, 0, 0)
HX, HY, HZ = MH[:, 0], MH[:, 1], MH[:, 2]
HC = v(0, 2.88, -0.17)  # centre de l'enseigne
H_HALF = v(0.6, 0.27, 0.13)


def hp(x, y, z):
    return HC + HX * x + HY * y + HZ * z


# glyphes inventés de l'enseigne : traits (x0, y0, x1, y1) dans une case de -1..1
GLYPHS = [
    [(-0.6, 0.6, 0.6, 0.6), (-0.6, -0.2, 0.6, -0.2), (-0.6, 0.6, -0.6, -0.2), (0.6, 0.6, 0.6, -0.2), (-0.6, 0.6, -0.95, 0.95),
     (-0.35, -0.2, -0.7, -0.9), (0.35, -0.2, 0.7, -0.9), (0.0, 0.2, 0.0, 0.2)],
    [(-0.6, 0.9, -0.6, -0.9), (-0.6, 0.6, 0.7, 0.6), (-0.6, 0.0, 0.25, 0.0), (-0.6, -0.6, 0.7, -0.6), (0.7, 0.0, 0.7, 0.0), (0.7, 0.6, 0.7, 0.85)],
    [(0.0, 0.85, 0.6, 0.25), (0.6, 0.25, 0.0, -0.35), (0.0, -0.35, -0.6, 0.25), (-0.6, 0.25, 0.0, 0.85), (0.0, 0.25, 0.0, 0.25),
     (0.0, -0.35, 0.0, -0.9), (-0.55, -0.7, 0.55, -0.7)],
]


def build():
    parts = []
    # ================================================================ bassin (racine)
    base = BPart("base", pivot=(0, 1.0, 0), res=0.014)
    b = base.piece(CASE_D, tris=500)
    b.add(rbox((0, 1.0, 0), (0.6, 0.2, 0.4), 0.17))
    b.add(rbox((0, 1.04, -0.42), (0.36, 0.19, 0.14), 0.09), k=0.05)  # batterie dorsale
    base.piece(CASE_L, tris=260, res=0.01).add(inter(rbox((0, 1.0, 0), (0.625, 0.22, 0.425), 0.18),
                                                  Shape(lambda P: np.abs(P[:, 1] - 1.1) - 0.035, (-2, 0.9, -2), (2, 1.3, 2)), 0.01))
    # couronne fixe de la tourelle de taille, dents dorées
    base.piece(CASE, tris=220, res=0.012).add(cyl((0, 1.22, 0), 0.44, 0.05, 0.03))
    teeth = base.piece(GOLD_D, tris=240, res=0.008)
    for k in range(16):
        a = k * math.tau / 16
        teeth.add(rbox((0.44 * math.sin(a), 1.22, 0.44 * math.cos(a)), (0.035, 0.035, 0.035), 0.012, rot=(0, math.degrees(a), 0)))
    # rotules de hanche
    for s in (-1, 1):
        base.piece(STEEL, tris=200, res=0.012).add(sphere((s * 0.5, 0.92, 0.0), 0.2))
    # bouchons dorés de la batterie
    for s in (-1, 1):
        base.piece(GOLD, tris=90, res=0.01).add(cyl((s * 0.2, 1.24, -0.42), 0.06, 0.03, 0.015))
    parts.append(base)
    bg = BPart("base_glow", pivot=(0, 1.0, 0), parent="base", res=0.007)
    bg.piece(PINK, tris=120).add(rbox((0, 1.04, -0.565), (0.22, 0.03, 0.012), 0.01))
    bg.piece(BLUE, tris=80).add(rbox((0, 0.97, -0.565), (0.14, 0.022, 0.012), 0.01))
    parts.append(bg)

    # ================================================================ jambes trapues
    for side, sx in (("r", -1.0), ("l", 1.0)):
        H = v(sx * 0.5, 0.92, 0.0)
        K = v(sx * 0.56, 0.56, 0.04)
        A = v(sx * 0.58, 0.3, 0.02)
        leg = BPart("leg_" + side, pivot=tuple(H), parent="base", res=0.013)
        leg.piece(CASE, tris=340).add(capsule(H, K, 0.21, 0.2))
        leg.piece(CASE_L, tris=260, res=0.011).add(oellip(K + v(0, 0.06, 0.13), (0.17, 0.15, 0.09), frame(v(0, 0.2, 1))))
        leg.piece(GOLD, tris=160, res=0.009).add(otorus(H + (K - H) * 0.35, 0.21, 0.03, frame(K - H)))
        parts.append(leg)
        shin = BPart("shin_" + side, pivot=tuple(K), parent="leg_" + side, res=0.013)
        shin.piece(STEEL, tris=160).add(sphere(K, 0.17))
        boot = shin.piece(CASE_L, tris=460, res=0.012)
        boot.add(capsule(K + v(0, -0.05, 0), A, 0.21, 0.27))
        boot.add(rbox(A + v(0, -0.14, 0.1), (0.29, 0.13, 0.4), 0.12), k=0.08)
        shin.piece(CASE_D, tris=200, res=0.012).add(rbox(A + v(0, -0.245, 0.1), (0.31, 0.055, 0.42), 0.05))
        # embout doré et ruban doré en haut de la botte
        shin.piece(GOLD, tris=220, res=0.013).add(cut(oellip(A + v(0, -0.13, 0.34), (0.27, 0.15, 0.2), np.eye(3)), A + v(0, -0.2, 0), (0, -1, 0)))
        shin.piece(GOLD_D, tris=140, res=0.009).add(otorus(K + (A - K) * 0.55, 0.235, 0.035, frame(A - K)))
        # rivets latéraux
        rv = shin.piece(CASE_D, tris=90, res=0.007)
        for k in range(3):
            rv.add(sphere(A + v(sx * 0.29, -0.12, -0.12 + k * 0.14), 0.03))
        parts.append(shin)

    # ================================================================ haut du corps : tourelle + panneau
    up = BPart("upper", pivot=(0, 1.24, 0), parent="base", res=0.014)
    up.piece(CASE_L, tris=260, res=0.012).add(cyl((0, 1.3, 0), 0.36, 0.06, 0.03))
    up.piece(CASE_D, tris=300, res=0.012).add(capsule((0, 1.3, 0), (0, 1.55, -0.02), 0.27))
    frm = up.piece(CASE, tris=1900, res=0.012)
    frm.add(obox(TC, T_HALF, 0.17, MT))
    frm.sub(obox(tp(0, 0, T_HALF[2]), (S_HALF[0] + 0.035, S_HALF[1] + 0.035, 0.055), 0.04, MT), k=0.015)
    frm.sub(obox(tp(0, 0, -T_HALF[2]), (S_HALF[0] + 0.035, S_HALF[1] + 0.035, 0.055), 0.04, MT), k=0.015)
    # flancs en relief, plus clairs, avec bande dorée
    for s in (-1, 1):
        sp_ = up.piece(CASE_L, tris=360, res=0.011)
        sp_.add(obox(tp(s * (T_HALF[0] + 0.01), 0.02, 0), (0.06, 0.5, 0.27), 0.05, MT))
        sp_.sub(obox(tp(s * (T_HALF[0] + 0.07), 0.02, 0), (0.03, 0.42, 0.05), 0.02, MT), k=0.01)
    # dessus : grille d'aération sombre et rail doré avant/arrière (le dessus se voit beaucoup d'en haut)
    tz = up.piece(CASE_D, tris=300, res=0.009)
    for k in range(4):
        x = (-0.66, -0.4, 0.4, 0.66)[k]
        tz.add(obox(tp(x, T_HALF[1] + 0.005, 0.0), (0.07, 0.02, 0.1), 0.015, MT))
    rail = up.piece(GOLD, tris=240, res=0.009)
    for s in (-1, 1):
        rail.add(capsule(tp(-0.74, T_HALF[1] - 0.02, s * 0.3), tp(0.74, T_HALF[1] - 0.02, s * 0.3), 0.028))
    # coins dorés (vis de panneau)
    cb = up.piece(GOLD, tris=200, res=0.008)
    for sz in (-1, 1):
        for sx in (-1, 1):
            for sy in (-1, 1):
                cb.add(ocyl(tp(sx * 0.81, sy * 0.555, sz * (T_HALF[2] - 0.005)), 0.045, 0.02, 0.012, MT))
    # sous le panneau : jupe sombre vers la tourelle
    up.piece(CASE_D, tris=260, res=0.012).add(obox(tp(0, -T_HALF[1] + 0.02, 0), (0.55, 0.08, 0.3), 0.06, MT))
    # cosse et câble dorsaux (dos du panneau, sous l'écran arrière)
    up.piece(CASE_D, tris=200, res=0.012).add(capsule(tp(0.0, -0.62, -0.2), (0, 1.12, -0.5), 0.08))
    parts.append(up)

    # écran (deux faces) : piloté par le shader de boss2.gd ; pivot au centre du panneau
    sc = Slab("screen_glow", pivot=tuple(TC), parent="upper")
    for sz in (-1, 1):
        sc.slab(tp(0, 0, sz * S_DEPTH), (S_HALF[0] + 0.02, S_HALF[1] + 0.02, 0.012), MT)
    parts.append(sc)

    # néons du panneau : tube rose devant, bleu derrière, barres du dessus, flancs
    bz = BPart("bezel_glow", pivot=tuple(TC), parent="upper", res=0.008)
    bz.extra.append(sweep(rrect_path(tp(0, 0, T_HALF[2] - 0.005), S_HALF[0] + 0.07, S_HALF[1] + 0.07, 0.1, MT), 0.026, PINK, sides=6, seg=2.0))
    bz.extra.append(sweep(rrect_path(tp(0, 0, -T_HALF[2] + 0.005), S_HALF[0] + 0.07, S_HALF[1] + 0.07, 0.1, MT), 0.026, BLUE, sides=6, seg=2.0))
    # barres lumineuses sur le dessus (lisibles de la caméra haute) et néons des flancs
    for x0, x1, col in ((-0.74, -0.2, PINK), (0.2, 0.74, BLUE)):
        for z in (-0.13, 0.13):
            bz.extra.append(sweep([tp(x0, T_HALF[1] + 0.012, z), tp(x1, T_HALF[1] + 0.012, z)], 0.022, col, sides=6, closed=False, seg=2.0))
    for s, col in ((-1, PINK), (1, BLUE)):
        bz.extra.append(sweep(rrect_path(tp(s * (T_HALF[0] + 0.055), 0.02, 0), 0.4, 0.05, 0.045, np.stack([TY, TZ, TX], axis=1)), 0.022, col, sides=6, seg=2.0))
    parts.append(bz)

    # ================================================================ tête : mât et enseigne au néon
    MP = v(0, 2.56, -0.19)
    head = BPart("head", pivot=tuple(MP), parent="upper", res=0.011)
    head.piece(CASE_D, tris=200).add(cyl(MP + v(0, 0.02, 0), 0.16, 0.05, 0.03))
    head.piece(GOLD_D, tris=160, res=0.009).add(capsule(MP, hp(0, -H_HALF[1] + 0.02, -0.02), 0.06))
    sg = head.piece(CASE, tris=850, res=0.01)
    sg.add(obox(HC, H_HALF, 0.08, MH))
    sg.sub(obox(hp(0, 0, H_HALF[2]), (H_HALF[0] - 0.06, H_HALF[1] - 0.06, 0.035), 0.03, MH), k=0.01)
    sg.sub(obox(hp(0, 0, -H_HALF[2]), (H_HALF[0] - 0.06, H_HALF[1] - 0.06, 0.035), 0.03, MH), k=0.01)
    for f in (1, -1):
        sg.paint(obox(hp(0, 0, f * (H_HALF[2] - 0.035)), (H_HALF[0] - 0.075, H_HALF[1] - 0.075, 0.012), 0.01, MH), BLACK)
    # cadre doré et équerres
    for f in (1, -1):
        head.extra.append(sweep(rrect_path(hp(0, 0, f * (H_HALF[2] - 0.01)), H_HALF[0] - 0.02, H_HALF[1] - 0.02, 0.07, MH), 0.024, GOLD, sides=6, seg=2.0))
    eq = head.piece(GOLD_D, tris=200, res=0.008)
    for s in (-1, 1):
        eq.add(obox(hp(s * 0.3, -H_HALF[1] - 0.02, -0.02), (0.06, 0.035, 0.05), 0.02, MH))
    # douilles des ampoules de marquise sur le dessus
    sk = head.piece(CASE_D, tris=200, res=0.007)
    for k in range(5):
        sk.add(ocyl(hp(-0.44 + k * 0.22, H_HALF[1] + 0.005, 0.0), 0.037, 0.03, 0.01, MH))
    # antenne de travers (touche mignonne)
    head.piece(STEEL, tris=90, res=0.007).add(capsule(hp(0.52, H_HALF[1] - 0.02, -0.04), hp(0.64, H_HALF[1] + 0.15, -0.06), 0.018, 0.013))
    parts.append(head)
    hg = BPart("head_glow", pivot=tuple(MP), parent="head", res=0.006)
    hg.extra.append(sweep(rrect_path(hp(0, 0, H_HALF[2] - 0.03), H_HALF[0] - 0.1, H_HALF[1] - 0.09, 0.06, MH), 0.021, PINK, sides=6, seg=2.0))
    hg.extra.append(sweep(rrect_path(hp(0, 0, -H_HALF[2] + 0.03), H_HALF[0] - 0.1, H_HALF[1] - 0.09, 0.06, MH), 0.021, PINK, sides=6, seg=2.0))
    # idéogrammes en tubes exacts, sur les deux faces (lisibles à l'endroit de chaque côté)
    for face in (1, -1):
        for gi, strokes in enumerate(GLYPHS):
            cx = -0.32 + gi * 0.32
            for (x0, y0, x1, y1) in strokes:
                s = 0.1
                a = np.array([cx + x0 * s, y0 * s * 1.05])
                b = np.array([cx + x1 * s, y1 * s * 1.05])
                d = b - a
                L = np.linalg.norm(d)
                d = d / L if L > 1e-6 else np.array([1.0, 0.0])
                a, b = a - d * 0.016, b + d * 0.016
                z = face * (H_HALF[2] - 0.035)
                hg.extra.append(sweep([hp(face * a[0], a[1], z), hp(face * b[0], b[1], z)], 0.018, BLUE, sides=6, closed=False, seg=2.0))
    bl = hg.piece(WARM, tris=260, res=0.006)
    for k in range(5):
        bl.add(sphere(hp(-0.44 + k * 0.22, H_HALF[1] + 0.06, 0.0), 0.045))
    hg.piece(PINK, tris=80, res=0.006).add(sphere(hp(0.645, H_HALF[1] + 0.165, -0.06), 0.04))
    parts.append(hg)

    # ================================================================ bras-projecteurs
    for side, sx, lens, lens_l in (("r", -1.0, PINK, PINK_L), ("l", 1.0, BLUE, BLUE_L)):
        S = v(sx * 0.98, 2.12, 0.0)  # épaule
        E = v(sx * 1.1, 1.64, 0.14)  # coude
        D = v(sx * 1.1, 1.04, 0.48)  # centre du tambour
        MZ = np.eye(3)
        arm = BPart("arm_" + side, pivot=tuple(S), parent="upper", res=0.012)
        arm.piece(CASE_L, tris=400).add(sphere(S + v(sx * 0.04, 0.02, 0), 0.28))
        arm.piece(GOLD, tris=180, res=0.009).add(otorus(S + v(sx * 0.17, 0.02, 0), 0.2, 0.03, frame(v(1, 0, 0))))
        arm.piece(CASE_D, tris=300).add(capsule(S + v(sx * 0.06, -0.1, 0), E, 0.15, 0.13))
        rb = arm.piece(CASE, tris=200, res=0.009)
        for k in (0.4, 0.62):
            rb.add(otorus(S + (E - S) * k, 0.145, 0.025, frame(E - S)))
        # haut-parleur d'épaule, tourné vers le haut et l'extérieur (lisible de la caméra haute)
        sd = nrm(v(sx * 1.0, 0.85, 0.2))
        SC = S + v(sx * 0.04, 0.02, 0) + sd * 0.25
        Ms = frame(sd)
        arm.piece(CASE_D, tris=220, res=0.009).add(ocyl(SC, 0.18, 0.05, 0.02, Ms)).sub(ocone(SC + sd * 0.05, 0.06, 0.15, 0.05, 0.01, Ms), k=0.01)
        arm.piece(GOLD, tris=220, res=0.008).add(otorus(SC + sd * 0.045, 0.165, 0.022, Ms))
        arm.piece(STEEL, tris=80, res=0.008).add(sphere(SC + sd * 0.01, 0.055))
        parts.append(arm)

        pj = BPart("proj_" + side, pivot=tuple(E), parent="arm_" + side, res=0.012)
        pj.piece(STEEL, tris=200).add(sphere(E, 0.16))
        Y0 = D + v(0, 0.42, 0)  # barre haute de l'étrier
        pj.piece(CASE_D, tris=220).add(capsule(E, Y0 + v(0, 0.02, -0.04), 0.11))
        yk = pj.piece(STEEL, tris=360, res=0.011)
        yk.add(capsule(Y0 + v(-0.39, 0, 0), Y0 + v(0.39, 0, 0), 0.065))
        for s in (-1, 1):
            yk.add(capsule(Y0 + v(s * 0.39, 0, 0), D + v(s * 0.39, 0, 0), 0.06), k=0.04)
        bolts = pj.piece(GOLD, tris=120, res=0.008)
        for s in (-1, 1):
            bolts.add(ocyl(D + v(s * 0.365, 0, 0), 0.09, 0.04, 0.02, frame(v(1, 0, 0))))
        drum = pj.piece(CASE, tris=560)
        drum.add(ocyl(D, 0.33, 0.27, 0.07, MZ))
        drum.add(ocone(D + v(0, 0, -0.33), 0.2, 0.3, 0.08, 0.04, MZ), k=0.05)
        drum.sub(ocyl(D + v(0, 0, 0.3), 0.27, 0.06, 0.02, MZ), k=0.01)
        # ailettes de refroidissement à l'arrière
        fins = pj.piece(CASE_D, tris=240, res=0.009)
        for k in range(8):
            a = k * math.tau / 8 + math.tau / 16
            Mf = MZ @ rot_matrix(0, 0, math.degrees(a))
            fins.add(obox(D + v(0.31 * math.cos(a), 0.31 * math.sin(a), -0.12), (0.035, 0.02, 0.13), 0.012, Mf))
        # bague dorée de la lentille et volets (haut et bas)
        pj.piece(GOLD, tris=300, res=0.009).add(otorus(D + v(0, 0, 0.27), 0.3, 0.04, MZ))
        flaps = pj.piece(CASE_D, tris=200, res=0.01)
        for sy in (-1, 1):
            Mfl = rot_matrix(sy * -28, 0, 0)
            flaps.add(obox(D + v(0, sy * 0.36, 0.38), (0.26, 0.015, 0.11), 0.012, Mfl))
        pj.piece(GOLD_D, tris=120, res=0.008).add(capsule(D + v(-0.22, 0.33, 0.29), D + v(0.22, 0.33, 0.29), 0.02))
        pj.piece(GOLD_D, tris=120, res=0.008).add(capsule(D + v(-0.22, -0.33, 0.29), D + v(0.22, -0.33, 0.29), 0.02))
        # câble de l'arrière du tambour vers le coude
        pj.piece(BLACK, tris=100, res=0.01).add(capsule(D + v(0, 0.1, -0.4), E + v(0, -0.08, -0.06), 0.04))
        parts.append(pj)

        pg = BPart("proj_" + side + "_glow", pivot=tuple(E), parent="proj_" + side, res=0.007)
        ln = pg.piece(lens, tris=360)
        ln.add(oellip(D + v(0, 0, 0.255), (0.265, 0.265, 0.05), MZ))
        ln.paint(otorus(D + v(0, 0, 0.29), 0.16, 0.025, MZ), lens_l)
        ln.paint(sphere(D + v(0, 0, 0.3), 0.07), lens_l)
        parts.append(pg)
    return Character("boss2", parts)
