"""Le Portique : gardien mécanique du portail volé (monde 1, Nébuleuse 7).

Gros corps rond sur quatre pattes d'araignée trapues, grand œil cyclope magenta sous un sourcil en V,
deux nacelles-canons magenta aux épaules (trois bouches chacune : les salves de trois), réacteur orange sur
le dos, et surtout l'ANNEAU DU PORTAIL porté au-dessus du dos, incliné vers l'arrière : cadre fixe sur
pylônes, anneau intérieur rotatif à tube magenta lumineux, voile de portail qui s'ouvre pendant l'attaque.
Regarde vers +Z ; sa droite est en -X. Hauteur totale 3,2 (Jo : 1,1) ; emprise au sol 3,2 x 3,2 (griffes comprises).

Hiérarchie :
  base (bassin, hanches) ─ leg_xx ─ shin_xx           (fl, fr, bl, br : avant/arrière, gauche +X / droite -X)
       └ hull (coque, tourne avec aim_yaw) ─ hull_glow, eye_glow, lid,
                cannon_r ─ cannon_r_glow, cannon_l ─ cannon_l_glow,
                arch (cadre + pylônes) ─ arch_glow, ring ─ ring_glow, portal_glow
"""
from sculpt import *

PLATE = "#9AA4B6"
PLATE_L = "#C8CEDC"
METAL = "#2C3350"
METAL_D = "#1C2238"
RED = "#FF2414"     # lueur rouge (bouches des canons, antenne) : sans bleu, elle ne vire pas au rose
MAG = "#E81EAE"     # lueur magenta (œil, anneau, portail) : saturé, la lueur l'éclaircit
MAG_L = "#FF6ED6"
MAG_P = "#D42C9E"   # nacelles-canons magenta : la signature du Portique vue du dessus, avec l'anneau
MAG_PD = "#8E1A6C"
ORANGE = "#FF7A2F"
ORANGE_G = "#FF5A14"  # cœur du réacteur (plus saturé : il est lumineux)
YELLOW = "#FFC83A"
BLACK = "#191B26"
DARK = "#10131F"
WHITE = "#FFFFFF"

# ------------------------------------------------------------------ petites aides géométriques
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
    """Boîte arrondie orientée par la matrice M (colonnes = axes locaux)."""
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


def otorus(c, R0, r, M):
    """Tore dans le plan local xy (axe local z)."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        q = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - R0, Q[:, 2]], axis=1)
        return np.linalg.norm(q, axis=1) - r
    m = R0 + r
    return Shape(f, c - m, c + m)


def inter(a, b, k=0.0):
    """Intersection (douce si k > 0) ; boîte englobante commune."""
    return Shape(lambda P: smax(a(P), b(P), k), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


_simplify = fast_simplification.simplify


def _simplify_iter(V, F, target_reduction=0.0, **kw):
    """Décimation répétée : une passe unique s'arrête tôt sur les faces planes obliques (boîtes tournées)."""
    target = max(8, int(round(len(F) * (1.0 - target_reduction))))
    for _ in range(20):
        if len(F) <= target * 1.05:
            break
        n0 = len(F)
        V, F = _simplify(np.asarray(V, dtype=np.float32), np.asarray(F, dtype=np.int32), target_reduction=1.0 - target / len(F), **kw)
        if len(F) >= n0:
            break
    return V, F


class BPart(Part):
    """Part dont la décimation va jusqu'au budget demandé."""
    def mesh(self):
        fast_simplification.simplify = _simplify_iter
        try:
            return Part.mesh(self)
        finally:
            fast_simplification.simplify = _simplify


def halfspace(p0, n):
    """Demi-espace des points du côté opposé à n (distance signée au plan)."""
    p0 = np.asarray(p0, dtype=np.float64)
    n = nrm(n)
    return Shape(lambda P: (P - p0) @ n, p0 - 50, p0 + 50)


def cut(s, p0, n, k=0.0):
    """Garde la partie de s située du côté -n du plan (p0, n)."""
    return inter(s, halfspace(p0, n), k)


# ------------------------------------------------------------------ mesures
HULL_C = v(0, 1.32, 0)
HULL_R = v(0.95, 0.62, 0.9)
EYE_TILT = 18.0  # l'œil regarde un peu vers le haut (caméra haute)
EYE_DIR = v(0, math.sin(math.radians(EYE_TILT)), math.cos(math.radians(EYE_TILT)))
EYE_UP = v(0, math.cos(math.radians(EYE_TILT)), -math.sin(math.radians(EYE_TILT)))
EYE_M = np.stack([v(1, 0, 0), EYE_UP, EYE_DIR], axis=1)


def hull_surface(d):
    d = nrm(d)
    t = 1.0 / math.sqrt(float(np.sum((d / HULL_R) ** 2)))
    return HULL_C + d * t


EYE_C = hull_surface(v(0, 0.3, 1.0)) - EYE_DIR * 0.03
EYE_R = 0.28

RING_C = v(0, 2.56, -0.36)
RING_TILT = 58.0  # 0 = debout face à l'avant, 90 = couché à plat
_tr = math.radians(RING_TILT)
RING_N = v(0, math.sin(_tr), math.cos(_tr))
RING_U = v(0, math.cos(_tr), -math.sin(_tr))  # « haut » dans le plan de l'anneau (vers l'arrière)
RING_X = v(1, 0, 0)
RING_M = np.stack([RING_X, RING_U, RING_N], axis=1)
RING_R = 0.86
RING_IN = 0.67
RC = v(0, 1.96, -0.3)  # cœur du réacteur dorsal


def ring_pt(theta, R):
    return RING_C + R * (math.cos(theta) * RING_X + math.sin(theta) * RING_U)


def ring_frame(theta):
    tang = -math.sin(theta) * RING_X + math.cos(theta) * RING_U
    return tang, frame(tang, RING_N)


def build():
    parts = []
    # ================================================================ bassin (racine) : couronne des hanches
    base = BPart("base", pivot=(0, 1.0, 0), res=0.016)
    b = base.piece(METAL, tris=260)
    b.add(cyl((0, 0.98, 0), 0.66, 0.12, 0.08))
    b.add(ellipsoid((0, 0.9, 0), (0.5, 0.16, 0.5)), k=0.08)
    base.piece(METAL_D, tris=120).add(cyl((0, 0.74, 0), 0.24, 0.08, 0.05))
    base.piece(ORANGE, tris=120, res=0.012).add(torus((0, 0.98, 0), 0.665, 0.03))
    parts.append(base)

    # ================================================================ coque
    hull = BPart("hull", pivot=(0, 1.15, 0), parent="base", res=0.016)
    main = hull.piece(PLATE, tris=2000)
    main.add(ellipsoid(HULL_C, HULL_R))
    main.add(ellipsoid(HULL_C + v(0, -0.05, -0.12), (0.9, 0.55, 0.85)), k=0.05)
    main.sub(ocyl(EYE_C + EYE_DIR * 0.02, EYE_R + 0.07, 0.16, 0.02, EYE_M), k=0.04)  # orbite
    # calotte claire sur le dessus
    cap = hull.piece(PLATE_L, tris=1900, res=0.013)
    cap.add(cut(ellipsoid(HULL_C + v(0, 0.01, 0), HULL_R + 0.05), (0, 1.56, 0), (0, -1, 0), 0.025))
    cap.sub(ocyl(EYE_C + EYE_DIR * 0.02, EYE_R + 0.1, 0.2, 0.02, EYE_M), k=0.03)
    # ventre sombre
    hull.piece(METAL, tris=300).add(ellipsoid((0, 1.05, 0), (0.8, 0.3, 0.76)))
    # ceinture
    belt = hull.piece(METAL_D, tris=360)
    belt.add(inter(ellipsoid(HULL_C, HULL_R + 0.045), Shape(lambda P: np.abs(P[:, 1] - 1.2) - 0.045, (-2, 1.0, -2), (2, 1.3, 2)), 0.02))
    # mâchoire : bande jaune à rayures noires sous l'œil
    JY = 1.02
    jaw_full = ellipsoid(HULL_C + v(0, 0, 0.01), HULL_R + v(0.045, 0.045, 0.05))
    jaw_slab = Shape(lambda P: np.maximum(np.abs(P[:, 1] - JY) - 0.08, 0.25 - P[:, 2]), (-2, 0.8, 0.2), (2, 1.2, 2))
    hull.piece(YELLOW, tris=420, res=0.01).add(inter(jaw_full, jaw_slab, 0.025))
    js = math.sqrt(1.0 - ((JY - HULL_C[1]) / HULL_R[1]) ** 2)
    for ang in range(-60, 61, 12):
        a = math.radians(ang)
        p = HULL_C + v(HULL_R[0] * js * math.sin(a), JY - HULL_C[1], HULL_R[2] * js * math.cos(a))
        n = nrm((p - HULL_C) / (HULL_R ** 2))
        Mr = frame(n) @ rot_matrix(0, 0, 35)
        hull.piece(BLACK, tris=40, res=0.008).add(obox(p + n * 0.045, (0.03, 0.078, 0.022), 0.014, Mr))
    # orbite : fond sombre et bourrelet
    hull.piece(METAL_D, tris=160, res=0.01).add(ocyl(EYE_C - EYE_DIR * 0.07, EYE_R + 0.06, 0.04, 0.02, EYE_M))
    hull.piece(METAL, tris=360, res=0.01).add(otorus(EYE_C + EYE_DIR * 0.01, EYE_R + 0.065, 0.055, EYE_M))
    # pupille (fente sombre) devant l'iris lumineux
    hull.piece(DARK, tris=120, res=0.006).add(oellip(EYE_C + EYE_DIR * 0.045, (0.075, 0.14, 0.028), EYE_M))
    # réacteur dorsal : collier et cage autour du cœur orange
    hull.piece(METAL_D, tris=240, res=0.012).add(cyl(RC, 0.3, 0.07, 0.04))
    cage = hull.piece(METAL, tris=260, res=0.009)
    for a in (0.0, 90.0):
        cage.add(cut(torus(RC + v(0, 0.02, 0), 0.2, 0.026, rot=(90, a, 0)), RC + v(0, 0.02, 0), (0, -1, 0)))
    cage.add(torus(RC + v(0, 0.05, 0), 0.25, 0.028))
    # tuyère arrière
    BACK = hull_surface(v(0, -0.12, -1.0))
    MB = frame(v(0, 0, -1))
    hull.piece(METAL_D, tris=200, res=0.012).add(ocyl(BACK + v(0, 0, -0.02), 0.22, 0.08, 0.04, MB)).sub(ocyl(BACK + v(0, 0, -0.1), 0.15, 0.07, 0.02, MB), k=0.02)
    hull.piece(METAL, tris=200, res=0.01).add(otorus(BACK + v(0, 0, -0.08), 0.2, 0.035, MB))
    # antenne (petite, de travers : touche mignonne)
    hull.piece(METAL, tris=100, res=0.008).add(capsule((0.5, 1.84, 0.3), (0.66, 2.24, 0.34), 0.025, 0.018))
    hull.piece(METAL_D, tris=80, res=0.01).add(cyl((0.5, 1.86, 0.3), 0.07, 0.03, 0.02))
    # rivets autour de la mâchoire
    rv = hull.piece(METAL, tris=150, res=0.007)
    for s in (-1, 1):
        for k in range(3):
            rv.add(sphere(hull_surface(v(s * 0.86, 0.12 - k * 0.14, 0.52)), 0.028))
    parts.append(hull)

    hg = BPart("hull_glow", pivot=(0, 1.15, 0), parent="hull", res=0.009)
    hgo = hg.piece(ORANGE_G, tris=260)
    hgo.add(ellipsoid(RC + v(0, 0.06, 0), (0.19, 0.14, 0.19)))
    hgo.add(ocyl(BACK + v(0, 0, -0.02), 0.15, 0.03, 0.01, MB))
    hg.piece(RED, tris=60, res=0.007).add(sphere((0.67, 2.27, 0.34), 0.055))
    parts.append(hg)

    # ================================================================ œil
    eg = BPart("eye_glow", pivot=tuple(EYE_C), parent="hull", res=0.007)
    iris = eg.piece(MAG, tris=380)
    iris.add(oellip(EYE_C - EYE_DIR * 0.04, (EYE_R, EYE_R, 0.08), EYE_M))
    iris.paint(oellip(EYE_C, (0.11, 0.11, 0.3), EYE_M), MAG_L)
    eg.piece(WHITE, tris=60, res=0.005).add(sphere(EYE_C + EYE_DIR * 0.07 + EYE_UP * 0.12 + v(0.1, 0, 0), 0.042))
    parts.append(eg)

    # sourcil en V (paupière blindée), s'abaisse pendant le « tell »
    lid = BPart("lid", pivot=tuple(EYE_C), parent="hull", res=0.009)
    lp = lid.piece(METAL, tris=360)
    for s in (-1, 1):
        Mb = EYE_M @ rot_matrix(0, 0, s * 20)
        lp.add(obox(EYE_C + EYE_UP * 0.27 + EYE_DIR * 0.08 + v(s * 0.19, 0, 0), (0.21, 0.07, 0.085), 0.05, Mb), k=0.05)
    lpl = lid.piece(PLATE_L, tris=160, res=0.008)
    for s in (-1, 1):
        Mb = EYE_M @ rot_matrix(0, 0, s * 20)
        lpl.add(obox(EYE_C + EYE_UP * 0.3 + EYE_DIR * 0.165 + v(s * 0.2, 0, 0), (0.17, 0.03, 0.015), 0.012, Mb), k=0.02)
    parts.append(lid)

    # ================================================================ nacelles-canons d'épaule
    MZ = frame(v(0, 0, 1))
    for side, sx in (("r", -1.0), ("l", 1.0)):
        pv = v(sx * 0.86, 1.62, 0.02)
        cn = BPart("cannon_" + side, pivot=tuple(pv), parent="hull", res=0.013)
        cn.piece(METAL_D, tris=140).add(sphere(pv, 0.18))
        px = sx * 1.12
        PY = 1.68
        pod = cn.piece(MAG_P, tris=450)
        pod.add(capsule((px, PY, -0.32), (px, PY, 0.24), 0.28, 0.26))
        pod.sub(ocyl((px, PY, -0.04), 0.4, 0.016, 0.006, MZ), k=0.004)
        cn.piece(MAG_PD, tris=100, res=0.012).add(ocyl((px, PY, -0.04), 0.275, 0.024, 0.012, MZ))
        cn.piece(PLATE_L, tris=200, res=0.01).add(inter(capsule((px, PY + 0.01, -0.36), (px, PY + 0.01, 0.28), 0.292, 0.272),
                                                      Shape(lambda P, px=px: np.abs(P[:, 0] - px) - 0.045, (-2, 0, -2), (2, 3, 2)), 0.01))
        # évents latéraux
        ve = cn.piece(METAL_D, tris=72, res=0.01)
        for k in range(3):
            ve.add(rbox((px + sx * 0.265, PY - 0.04, -0.2 + k * 0.1), (0.03, 0.1, 0.028), 0.016))
        # manchon à trois bouches
        sh = cn.piece(METAL, tris=250, res=0.011)
        sh.add(ocyl((px, PY - 0.02, 0.5), 0.19, 0.12, 0.045, MZ))
        holes = [(0.0, 0.08), (-0.074, -0.044), (0.074, -0.044)]
        for hx, hy in holes:
            sh.sub(ocyl((px + hx, PY - 0.02 + hy, 0.62), 0.05, 0.06, 0.01, MZ), k=0.01)
        cn.piece(METAL_D, tris=130, res=0.01).add(otorus((px, PY - 0.02, 0.6), 0.185, 0.032, MZ))
        parts.append(cn)
        cg = BPart("cannon_" + side + "_glow", pivot=tuple(pv), parent="cannon_" + side, res=0.006)
        g = cg.piece(RED, tris=120)
        for hx, hy in holes:
            g.add(ocyl((px + hx, PY - 0.02 + hy, 0.575), 0.045, 0.01, 0.004, MZ))
        g.add(rbox((px + sx * 0.275, PY + 0.13, 0.06), (0.012, 0.025, 0.08), 0.01))
        parts.append(cg)

    # ================================================================ arche du portail (cadre fixe + pylônes)
    arch = BPart("arch", pivot=tuple(RING_C), parent="hull", res=0.012)
    arch.piece(METAL, tris=900, res=0.012).add(otorus(RING_C, RING_R, 0.105, RING_M))
    py = arch.piece(METAL_D, tris=300, res=0.012)
    slv = arch.piece(PLATE, tris=200, res=0.011)
    for s in (-1, 1):
        top = ring_pt(0.0 if s > 0 else math.pi, RING_R)
        a = v(s * 0.52, 1.8, -0.3)
        py.add(capsule(a, top + v(0, -0.04, 0), 0.1, 0.075))
        slv.add(capsule(a + (top - a) * 0.3, a + (top - a) * 0.62, 0.115))
    # pinces : claires sur les côtés et à l'arrière, jaune rayée à l'avant
    for i, th in enumerate((0.0, 0.5 * math.pi, math.pi, 1.5 * math.pi)):
        p = ring_pt(th, RING_R)
        tang, M = ring_frame(th)
        col = YELLOW if i == 3 else PLATE_L
        arch.piece(col, tris=110, res=0.01).add(obox(p, (0.165, 0.165, 0.1), 0.055, M))
    parts.append(arch)
    ag = BPart("arch_glow", pivot=tuple(RING_C), parent="arch", res=0.006)
    agp = ag.piece(MAG, tris=120)
    for th in (0.0, 0.5 * math.pi, math.pi):
        p = ring_pt(th, RING_R)
        tang, M = ring_frame(th)
        agp.add(obox(p + RING_N * 0.1, (0.07, 0.022, 0.03), 0.015, M))
    parts.append(ag)

    # ================================================================ anneau rotatif + tube lumineux
    ring = BPart("ring", pivot=tuple(RING_C), parent="arch", res=0.009)
    for k in range(8):
        th = k * math.pi / 4 + math.pi / 8
        p = ring_pt(th, RING_IN)
        tang, M = ring_frame(th)
        col = PLATE_L if k % 2 == 0 else METAL_D
        ring.piece(col, tris=70).add(obox(p, (0.115, 0.115, 0.07), 0.042, M))
        if k % 2 == 0:
            ring.piece(YELLOW, tris=40, res=0.007).add(obox(p + RING_N * 0.105, (0.05, 0.05, 0.02), 0.015, M))
    parts.append(ring)
    rg = BPart("ring_glow", pivot=tuple(RING_C), parent="ring", res=0.01)
    rg.piece(MAG, tris=700).add(otorus(RING_C, RING_IN, 0.078, RING_M))
    parts.append(rg)

    # voile du portail (caché au repos, s'ouvre pendant l'anneau)
    po = BPart("portal_glow", pivot=tuple(RING_C), parent="ring", res=0.012)
    po.piece(MAG, tris=150).add(oellip(RING_C, (0.6, 0.6, 0.018), RING_M))
    sw = po.piece(MAG_L, tris=220, res=0.01)
    for arm in range(3):
        for j in range(7):
            rr = 0.08 + j * 0.075
            th = arm * 2 * math.pi / 3 + j * 0.42
            p = RING_C + rr * (math.cos(th) * RING_X + math.sin(th) * RING_U) + RING_N * 0.012
            sw.add(oellip(p, (0.05 + j * 0.006, 0.05 + j * 0.006, 0.012), RING_M), k=0.05)
    parts.append(po)

    # ================================================================ pattes
    for name, ang in (("fl", 45.0), ("fr", -45.0), ("bl", 135.0), ("br", -135.0)):
        a = math.radians(ang)
        d = v(math.sin(a), 0, math.cos(a))
        side = nrm(np.cross(v(0, 1, 0), d))
        H = d * 0.6 + v(0, 0.98, 0)
        K = d * 1.36 + v(0, 1.42, 0)
        A = d * 1.62 + v(0, 0.34, 0)
        F = d * 1.66 + v(0, 0.11, 0)
        leg = BPart("leg_" + name, pivot=tuple(H), parent="base", res=0.013)
        leg.piece(METAL_D, tris=90).add(sphere(H, 0.21))
        leg.piece(PLATE, tris=260).add(capsule(H, K, 0.2, 0.17))
        L = nrm(K - H)
        N = np.cross(L, side)
        N = N if N[1] > 0 else -N
        Mp = np.stack([nrm(np.cross(N, L)), N, L], axis=1)
        mid = (H + K) * 0.5
        pc = mid + N * 0.15 + L * 0.05
        leg.piece(YELLOW, tris=150, res=0.014).add(obox(pc, (0.17, 0.05, 0.3), 0.045, Mp))
        rs = rot_matrix(0, 37, 0)
        for k in (-1.5, -0.5, 0.5, 1.5):
            leg.piece(BLACK, tris=30, res=0.008).add(obox(pc + L * (k * 0.13) + N * 0.05, (0.15, 0.02, 0.032), 0.014, Mp @ rs))
        parts.append(leg)

        shin = BPart("shin_" + name, pivot=tuple(K), parent="leg_" + name, res=0.013)
        shin.piece(METAL_D, tris=120).add(sphere(K, 0.2))
        kd = nrm(d + v(0, 0.6, 0))
        shin.piece(ORANGE, tris=100, res=0.01).add(ocyl(K + kd * 0.17, 0.11, 0.04, 0.025, frame(kd)))
        S = nrm(A - K)
        shin.piece(PLATE_L, tris=300).add(capsule(K + S * 0.12, A - S * 0.06, 0.2, 0.14))
        shin.piece(METAL, tris=110, res=0.01).add(otorus(K + (A - K) * 0.62, 0.155, 0.04, frame(S)))
        shin.piece(METAL, tris=110, res=0.01).add(otorus(K + (A - K) * 0.74, 0.145, 0.04, frame(S)))
        shin.piece(METAL_D, tris=80).add(sphere(A, 0.14))
        shin.piece(METAL_D, tris=170).add(cyl(F, 0.32, 0.11, 0.065))
        shin.piece(PLATE, tris=160).add(ellipsoid(F + v(0, 0.1, 0) + d * 0.02, (0.25, 0.1, 0.25)))
        # griffes : trois orteils arrondis vers l'extérieur
        cl = shin.piece(METAL, tris=120, res=0.01)
        for o in (-0.55, 0.0, 0.55):
            dd = nrm(d * math.cos(o) + side * math.sin(o))
            cl.add(capsule(F + dd * 0.24 + v(0, 0.02, 0), F + dd * 0.39, 0.075, 0.055))
        parts.append(shin)
    return Character("boss", parts)
