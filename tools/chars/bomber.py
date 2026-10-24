"""Pétard (code « bomber ») : petit kamikaze roulant de la sécurité de la station, qui fonce sur Jo et explose.
Boule de danger jaune en coque de mine : bande de roulement en ruban de danger (chevrons obliques continus noirs),
flancs rivetés, plots de détonateur sombres, qui roule sur elle-même (axe X) entre deux moyeux fixes. Sur les moyeux, un étrier porte une petite tête sombre : GROS œil rouge incliné vers le haut
(lisible depuis la caméra haute), antenne-détonateur à voyant rouge clignotant, ailerons arrière (sens du
Pétard vu du dessus). Deux poignées rouges sur les moyeux.
Regarde vers +Z ; sa droite est en -X. Pieds à y = 0 : la boule touche le sol. Largeur ~0,6, hauteur ~0,67.

Parts : body (moyeux, étrier, tête ; pivot au centre de la boule), ball (la boule qui roule, pivot au centre),
eye_glow (œil, pivot au centre de la lentille), fuse (antenne, pivot à sa base) + fuse_glow (voyant).
Variante élite (build(elite=True), tools/chars/bomber_elite.py) : couronne de pointes dorées sur la boule,
poignées, moyeux et crête dorés, couronne à griffes autour du voyant."""
import math

import trimesh
from skimage import measure

from sculpt import *
from sculpt import Part as _Part

HAZ = "#FFC83A"      # jaune de danger
HAZ_D = "#E9A21E"    # jaune ombré (fond de bande)
STRIPE = "#1C2238"   # bandes sombres
METAL = "#2C3350"
METAL_L = "#454E70"
METAL_D = "#161B2E"
SHELL = "#C8CEDC"
RED = "#E8303A"      # peinture de faction (rouge franc)
EYE_RIM = "#B00A06"  # bord de l'œil (reste rouge une fois lumineux)
EYE_IRIS = "#FF2414"  # iris rouge : ni bleu ni vert, la lueur ne le délave pas en rose
PUPIL = "#1A0610"
WHITE = "#FFFFFF"
LAMP = "#FF1A0A"
ORANGE = "#FF7A2F"
GOLD = "#EE8530"     # or franc des élites (jamais jaune pâle : il doit se détacher du jaune de danger)
GOLD_D = "#C8650E"

R = 0.18                          # rayon de la boule
C = np.array([0.0, 0.192, 0.0])   # centre de la boule (ses reliefs effleurent le sol)
POD = C + np.array([0.0, 0.223, 0.0])  # centre de la tête
SCALE = 1.12  # agrandi (largeur ~0,6, hauteur ~0,67) : il se voyait mal à l'écran


class Part(_Part):
    """Normales exactes du champ de distance (coque lisse malgré l'allègement), allègement itératif."""

    def _piece_mesh(self, pc):
        res = pc.res or self.res
        lo, hi = pc.bounds()
        n = np.ceil((hi - lo) / res).astype(int) + 1
        xs = [np.linspace(lo[i], lo[i] + (n[i] - 1) * res, n[i]) for i in range(3)]
        G = np.stack(np.meshgrid(*xs, indexing="ij"), axis=-1).reshape(-1, 3)
        vol = pc.sdf(G).reshape(n)
        if vol.min() > 0 or vol.max() < 0:
            return None
        verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(res,) * 3)
        verts = verts + lo
        if len(faces) > pc.tris:
            verts, faces = simplify_to(verts, faces, pc.tris)
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = 1e-3
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V)
        occ = np.ones(len(V))
        for dist, w in ((0.02, 0.5), (0.05, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.8, 1.0) ** w
        y = V[:, 1]
        grad = 0.92 + 0.08 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        c = np.clip(col * (occ * grad)[:, None], 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm, N

    def mesh(self):
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        tm = trimesh.util.concatenate([o[0] for o in out])
        normals = np.concatenate([o[1] for o in out])
        tm.apply_translation(-self.pivot)
        tm.vertex_normals = normals
        return tm


BIG = 50.0


def inter(a, b, k=0.0):
    if k <= 0.0:
        return Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))
    return Shape(lambda P: smax(a(P), b(P), k), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def grow(a, d):
    return Shape(lambda P: a(P) - d, a.lo - max(d, 0.0), a.hi + max(d, 0.0))


def half(c, nv):
    """Demi-espace du côté opposé à la normale nv (forme pleine « derrière » le plan)."""
    c = np.asarray(c, dtype=np.float64)
    nv = np.asarray(nv, dtype=np.float64)
    nv = nv / np.linalg.norm(nv)
    return Shape(lambda P: (P - c) @ nv, np.full(3, -BIG), np.full(3, BIG))


def chevrons(c, n, pitch, frac=0.5):
    """Chevrons enroulés autour de l'axe X (n par tour), en V symétriques par rapport à x = 0."""
    c = np.asarray(c, dtype=np.float64)

    def f(P):
        Q = P - c
        th = np.arctan2(Q[:, 2], Q[:, 1])
        r = np.maximum(np.linalg.norm(Q[:, 1:], axis=1), 1e-3)
        u = th * n / (2 * np.pi) + np.abs(Q[:, 0]) / pitch
        fr = u - np.floor(u)
        g = np.sqrt((n / (2 * np.pi * r)) ** 2 + (1.0 / pitch) ** 2)
        return (np.abs(fr - 0.5) - frac * 0.5) / g
    return Shape(f, c - BIG, c + BIG)


def helix_x(c, n, pitch, frac=0.5):
    """Hachures obliques enroulées autour de l'axe X (n par tour) : ruban de danger."""
    c = np.asarray(c, dtype=np.float64)

    def f(P):
        Q = P - c
        th = np.arctan2(Q[:, 2], Q[:, 1])
        r = np.maximum(np.linalg.norm(Q[:, 1:], axis=1), 1e-3)
        u = th * n / (2 * np.pi) + Q[:, 0] / pitch
        fr = u - np.floor(u)
        g = np.sqrt((n / (2 * np.pi * r)) ** 2 + (1.0 / pitch) ** 2)
        return (np.abs(fr - 0.5) - frac * 0.5) / g
    return Shape(f, c - BIG, c + BIG)


def spokes(c, n, frac):
    """Secteurs angulaires autour de l'axe X (crans de la bande de roulement)."""
    c = np.asarray(c, dtype=np.float64)

    def f(P):
        Q = P - c
        th = np.arctan2(Q[:, 2], Q[:, 1])
        r = np.maximum(np.linalg.norm(Q[:, 1:], axis=1), 1e-3)
        u = th * n / (2 * np.pi)
        fr = u - np.floor(u)
        return (np.abs(fr - 0.5) - frac * 0.5) * (2 * np.pi * r / n)
    return Shape(f, c - BIG, c + BIG)


def scale_parts(parts, k):
    """Réduit uniformément le personnage (formes et pivots), sans changer la finesse du maillage."""
    def scaled(sh):
        return Shape(lambda P, f=sh.fn: f(P / k) * k, sh.lo * k, sh.hi * k)
    for part in parts:
        part.pivot = part.pivot * k
        part.res *= k
        for pc in part.pieces:
            if pc.res:
                pc.res *= k
            pc.ops = [(op[0], scaled(op[1])) + tuple(op[2:]) for op in pc.ops]


def _axis_rot(d):
    """Angles (degrés, ordre X puis Y puis Z de rot_matrix) qui couchent l'axe +Y sur la direction d."""
    d = np.asarray(d, dtype=np.float64)
    d = d / np.linalg.norm(d)
    # +Y -> d : basculer autour de X (vers +Z) puis tourner autour de Y
    rx = math.degrees(math.acos(max(-1.0, min(1.0, d[1]))))
    ry = math.degrees(math.atan2(d[0], d[2]))
    return (rx, ry, 0.0)


def at(p, x, y, z):
    return (np.asarray(p) + np.array([x, y, z])).tolist()


def arc_pts(sx, r, a0, a1, n, z=0.0):
    """Points d'un arc dans le plan XY autour du centre de la boule (angles depuis l'axe X, en degrés)."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append(at(C, sx * r * math.cos(a), r * math.sin(a), z))
    return out


def build(elite=False):
    trim = GOLD if elite else RED
    parts = []

    # ================================================================ corps fixe (pivot au centre de la boule)
    body = Part("body", pivot=C.tolist(), res=0.004)
    # moyeux : gros disques sombres aux pôles de l'axe de roulement, flasque claire, vis centrale
    hub = body.piece(METAL, tris=200)
    for sx in (-1, 1):
        hub.add(cyl(at(C, sx * 0.17, 0, 0), 0.098, 0.03, 0.016, rot=(0, 0, 90)))
        hub.add(cyl(at(C, sx * 0.2, 0, 0), 0.07, 0.02, 0.012, rot=(0, 0, 90)), k=0.012)
    cap = body.piece(SHELL if not elite else GOLD, tris=120)
    for sx in (-1, 1):
        cap.add(cyl(at(C, sx * 0.214, 0, 0), 0.05, 0.012, 0.008, rot=(0, 0, 90)))
    cap.paint(sphere(at(C, -0.25, 0, 0), 0.03), METAL_L).paint(sphere(at(C, 0.25, 0, 0), 0.03), METAL_L)
    bolt = body.piece(METAL_D, tris=80)
    for sx in (-1, 1):
        for i in range(4):
            a = math.radians(45 + 90 * i)
            bolt.add(sphere(at(C, sx * 0.188, 0.078 * math.cos(a), 0.078 * math.sin(a)), 0.011))
    # poignées rouges (ou dorées) qui dépassent des moyeux
    hdl = body.piece(trim, tris=180)
    for sx in (-1, 1):
        tor = torus(at(C, sx * 0.205, 0.0, -0.005), 0.05, 0.015, rot=(90, 0, 0))
        hdl.add(inter(tor, half(at(C, sx * 0.218, 0, 0), (-sx, 0, 0))))
    # étrier : bras courbes qui montent des moyeux à la tête (épousent la boule sans la toucher)
    yoke = body.piece(METAL, tris=160)
    for sx in (-1, 1):
        pts = arc_pts(sx, 0.212, 30, 74, 3, -0.01)
        for a, b in zip(pts[:-1], pts[1:]):
            yoke.add(capsule(a, b, 0.019, 0.017), k=0.01)
        yoke.add(capsule(at(C, sx * 0.178, 0.07, -0.01), at(C, sx * 0.183, 0.11, -0.01), 0.028, 0.02), k=0.012)
    # tête : petite coque claire (coque de la sécurité), jupe sombre posée sur la boule
    pod_sh = ellipsoid(POD.tolist(), (0.125, 0.085, 0.118))
    eye_dir = np.array([0.0, math.sin(math.radians(28)), math.cos(math.radians(28))])
    rx = 90 - 28
    ec = POD + np.array([0, 0.005, 0]) + eye_dir * 0.092  # centre de l'œil (sur la face avant)
    eye_hole = ellipsoid((ec + eye_dir * 0.02).tolist(), (0.072, 0.05, 0.072), rot=(rx, 0, 0))
    pod = body.piece(SHELL, tris=380)
    pod.add(pod_sh)
    pod.sub(half(at(POD, 0, -0.022, 0), (0, 1, 0)), k=0.01)
    pod.sub(eye_hole, k=0.01)
    skirt = body.piece(METAL, tris=200)
    skirt.add(inter(grow(pod_sh, -0.006), half(at(POD, 0, -0.012, 0), (0, 1, 0))))
    skirt.add(ellipsoid(at(POD, 0, -0.04, -0.01), (0.1, 0.055, 0.1)), k=0.025)
    skirt.sub(eye_hole, k=0.01)
    # liseré rouge de faction à la jonction (lisible du dessus, derrière l'œil)
    band = body.piece(trim, tris=150)
    band.add(inter(grow(pod_sh, 0.004), inter(half(at(POD, 0, -0.012, 0), (0, 1, 0)), half(at(POD, 0, -0.03, 0), (0, -1, 0)))))
    band.sub(ellipsoid((ec + eye_dir * 0.02).tolist(), (0.085, 0.07, 0.085), rot=(rx, 0, 0)), k=0.01)
    # orbite de l'œil : anneau sombre
    sock = body.piece(METAL, tris=200, res=0.003)
    sock.add(torus((ec + eye_dir * 0.004).tolist(), 0.066, 0.016, rot=(rx, 0, 0)))
    # sourcils froncés au-dessus de l'œil (air décidé)
    up = np.array([0, math.cos(math.radians(28)), -math.sin(math.radians(28))])

    def E(u, x, d):
        return (ec + up * u + np.array([x, 0, 0]) + eye_dir * d).tolist()
    brow = body.piece(trim, tris=120, res=0.003)
    for sx in (-1, 1):
        brow.add(capsule(E(0.076, sx * 0.008, 0.004), E(0.094, sx * 0.056, -0.012), 0.014, 0.01), k=0.01)
    # évent arrière sombre (le dos se distingue de la face vu du dessus)
    vent = body.piece(METAL, tris=100)
    vent.add(rbox(at(POD, 0, 0.02, -0.112), (0.05, 0.03, 0.02), 0.014, rot=(-35, 0, 0)))
    for dx in (-0.025, 0.0, 0.025):
        vent.sub(rbox(at(POD, dx, 0.028, -0.124), (0.006, 0.022, 0.02), 0.005, rot=(-35, 0, 0)), k=0.004)
    if elite:
        # crête dorée à pointes sur le dessus de la tête, derrière l'antenne
        crest = body.piece(GOLD, tris=160, res=0.003)
        for i, (z, h) in enumerate(((-0.05, 0.075), (-0.085, 0.06), (-0.11, 0.04))):
            crest.add(capsule(at(POD, 0, 0.06, z), at(POD, 0, 0.06 + h, z - 0.03), 0.016, 0.004), k=0.012)
    # embase de l'antenne
    body.piece(METAL_L, tris=60).add(cyl(at(POD, 0, 0.08, -0.03), 0.026, 0.014, 0.008))
    parts.append(body)

    # ================================================================ boule (roule autour de X)
    # coque de mine jaune : au centre, bande de roulement en ruban de danger (chevrons obliques continus, qui
    # défilent d'avant en arrière vu du dessus) bordée de deux joncs sombres ; sur chaque flanc, une couture
    # rivetée et des plots de détonateur sombres (l'élite porte des pointes dorées à la place)
    ball = Part("ball", pivot=C.tolist(), parent="body", res=0.0045)
    bs = sphere(C.tolist(), R)
    hub_hole = [cyl(at(C, sx * 0.19, 0, 0), 0.06, 0.03, 0.0, rot=(0, 0, 90)) for sx in (-1, 1)]
    sh = ball.piece(HAZ, tris=520)
    sh.add(bs)
    for hh in hub_hole:
        sh.sub(hh)
    BW = 0.07  # demi-largeur de la bande
    hatch = ball.piece(STRIPE, tris=640, res=0.0032)
    hatch.add(inter(inter(grow(bs, 0.007), chevrons(C, 11, 0.1, 0.38), k=0.002), cyl(C.tolist(), R + 0.05, BW - 0.002, 0.0, rot=(0, 0, 90))))
    rims = ball.piece(METAL, tris=260)
    for sx in (-1, 1):
        rims.add(inter(grow(bs, 0.011), cyl(at(C, sx * (BW + 0.006), 0, 0), R + 0.05, 0.008, 0.0, rot=(0, 0, 90)), k=0.004))
    # couture rivetée des flancs
    SX = 0.128
    rr = math.sqrt(R * R - SX * SX)
    seam = ball.piece(METAL, tris=420, res=0.003)
    for sx in (-1, 1):
        seam.add(torus(at(C, sx * SX, 0, 0), rr + 0.002, 0.0045, rot=(0, 0, 90)))
        for i in range(10):
            a = 2 * math.pi * (i + 0.5 * (sx > 0)) / 10
            seam.add(sphere(at(C, sx * SX, (rr + 0.004) * math.cos(a), (rr + 0.004) * math.sin(a)), 0.0105), k=0.003)
    beta = math.radians(48)
    if elite:
        # couronne de pointes dorées sur les flancs (elles ne touchent jamais le sol)
        sp = ball.piece(GOLD_D, tris=380, res=0.0035)
        for sx in (-1, 1):
            for i in range(6):
                ph = 2 * math.pi * (i + 0.5 * (sx > 0) + 0.25) / 6
                d = np.array([sx * math.sin(beta), math.cos(beta) * math.cos(ph), math.cos(beta) * math.sin(ph)])
                sp.add(capsule((C + d * 0.165).tolist(), (C + d * 0.232).tolist(), 0.022, 0.004))
    else:
        # plots de détonateur : courts, arrondis, coiffés de rouge (ils ne touchent jamais le sol)
        st = ball.piece(METAL, tris=360, res=0.0035)
        tips = ball.piece(RED, tris=160, res=0.0035)
        for sx in (-1, 1):
            for i in range(5):
                ph = 2 * math.pi * (i + 0.5 * (sx > 0)) / 5
                d = np.array([sx * math.sin(beta), math.cos(beta) * math.cos(ph), math.cos(beta) * math.sin(ph)])
                st.add(capsule((C + d * 0.17).tolist(), (C + d * 0.196).tolist(), 0.019, 0.017))
                st.add(cyl((C + d * 0.172).tolist(), 0.026, 0.006, 0.004, rot=_axis_rot(d)), k=0.006)
                tips.add(sphere((C + d * 0.205).tolist(), 0.0125))
    parts.append(ball)

    # ================================================================ œil
    eye = Part("eye_glow", pivot=(ec + eye_dir * 0.012).tolist(), parent="body", res=0.003)
    lens = eye.piece(EYE_RIM, tris=280)
    lens.add(ellipsoid((ec + eye_dir * 0.006).tolist(), (0.058, 0.026, 0.058), rot=(rx, 0, 0)))
    lens.paint(cyl((ec + eye_dir * 0.03).tolist(), 0.042, 0.02, 0.0, rot=(rx, 0, 0)), EYE_IRIS)
    pupil = eye.piece(PUPIL, tris=70, res=0.0025)
    pupil.add(ellipsoid(E(0.0, 0.0, 0.03), (0.021, 0.007, 0.024), rot=(rx, 0, 0)))
    gl = eye.piece(WHITE, tris=50, res=0.0025)
    gl.add(ellipsoid(E(0.026, 0.02, 0.029), (0.013, 0.006, 0.01), rot=(rx, 0, -30)))
    gl.add(sphere(E(-0.024, -0.024, 0.026), 0.006))
    parts.append(eye)

    # ================================================================ antenne-détonateur
    base = POD + np.array([0, 0.085, -0.03])
    tip = POD + np.array([0, 0.14, -0.045])
    fuse = Part("fuse", pivot=base.tolist(), parent="body", res=0.003)
    fuse.piece(METAL_L, tris=110).add(capsule(base.tolist(), tip.tolist(), 0.009, 0.008))
    ring = fuse.piece(trim, tris=110)
    ring.add(torus(at(base, 0, 0.03, -0.007), 0.018, 0.007, rot=(-12, 0, 0)))
    if elite:
        claw = fuse.piece(GOLD, tris=120)
        for i in range(4):
            a = math.radians(45 + 90 * i)
            o = np.array([math.cos(a), 0, math.sin(a)])
            claw.add(capsule((tip + o * 0.012 - np.array([0, 0.012, 0])).tolist(), (tip + o * 0.034 + np.array([0, 0.03, 0])).tolist(), 0.008, 0.003))
    parts.append(fuse)
    lamp = Part("fuse_glow", pivot=tip.tolist(), parent="fuse", res=0.003)
    lamp.piece(LAMP, tris=120).add(sphere((tip + np.array([0, 0.012, 0])).tolist(), 0.027))
    parts.append(lamp)

    scale_parts(parts, SCALE)
    return Character("bomber_elite" if elite else "bomber", parts)
