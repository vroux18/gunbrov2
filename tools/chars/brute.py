"""Colosse : gros robot marcheur blindé de la faction du Portique (tank lent qui charge).
Silhouette en « frigo arrondi » voûté : épaules massives, petite tête enfoncée dans un col, bras longs
terminés par deux poings-masses, jambes courtes et trapues. Réacteur orange sur le torse, réacteur dorsal
et cheminées lumineuses dans le dos (lisibles en vue haute), yeux rouges, bandes de danger aux poignets
et au bord des épaulières, bandes rouges de la faction sur le dessus des épaules.
Regarde vers +Z ; sa droite est en -X. Hauteur ~1,78 (Jo ~1,05).

Parts : torso (pivot hanches), core_glow (réacteur ventral, pivot en son centre pour pulser),
back_glow (réacteur dorsal, évents, cheminées), head + head_glow (yeux), arm_r/arm_l (épaule)
+ fore_r/fore_l (coude, avec le poing), leg_r/leg_l (hanche) + shin_r/shin_l (genou, avec le pied).
Variante élite (build(elite=True), tools/chars/brute_elite.py) : accents lumineux or, cornes de casque,
plaques et pointes dorées."""
from sculpt import *

SHELL = "#C8CEDC"  # coque claire
SHELL_D = "#9AA4B6"  # coque moyenne
METAL = "#2C3350"  # métal sombre
METAL_D = "#1C2238"
CORE = "#FF7A2F"  # réacteur
EYE = "#FF4D6D"
RED = "#EE3F5C"  # peinture de faction (rappel des yeux)
HAZ = "#FFC83A"  # jaune des bandes de danger
GOLD = "#FFB347"
GOLD_D = "#E39233"


# ------------------------------------------------------------------ pièce robuste
class RPart(Part):
    """Part dont la décimation est vérifiée : sur certaines grilles l'allègement extrême échoue
    (il s'arrête à quelques milliers de triangles). On allège alors en plusieurs passes, puis on
    relance avec une résolution très légèrement différente si besoin."""
    def _piece_mesh(self, pc):
        import fast_simplification as fs
        orig = fs.simplify

        def simplify(v, f, target_reduction=0.0, **kw):
            goal = max(int(round(len(f) * (1.0 - target_reduction))), 4)
            rng = np.random.default_rng(7)
            for _ in range(12):
                if len(f) <= goal * 1.05:
                    break
                step = max(goal / len(f), 0.3)  # au plus ~3x par passe
                v2, f2 = orig(v, f, target_reduction=1.0 - step, **kw)
                if len(f2) > len(f) * 0.9:  # bloqué : on secoue imperceptiblement les sommets
                    v = (v + rng.normal(0.0, 2e-5, v.shape)).astype(np.float32)
                    continue
                v, f = v2, f2
            return v, f
        fs.simplify = simplify
        try:
            base = pc.res or self.res
            for i in range(5):
                pc.res = base * (1.0 - 0.031 * i)
                tm = Part._piece_mesh(self, pc)
                if tm is None or len(tm.faces) <= pc.tris * 1.15:
                    break
            return tm
        finally:
            fs.simplify = orig


# ------------------------------------------------------------------ formes maison
BIG = 50.0


def inter(a, b):
    """Intersection de deux formes."""
    return Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def grow(a, d):
    """Forme gonflée (d > 0) ou rétrécie (d < 0)."""
    return Shape(lambda P: a(P) - d, a.lo - max(d, 0.0), a.hi + max(d, 0.0))


def union(shapes, k=0.0):
    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = smin(d, s(P), k)
        return d
    return Shape(f, np.min([s.lo for s in shapes], axis=0) - k, np.max([s.hi for s in shapes], axis=0) + k)


def below(y0, tilt=0.0):
    """Demi-espace y < y0 (plan incliné de `tilt` degrés autour de X)."""
    nv = np.array([0.0, math.cos(math.radians(tilt)), -math.sin(math.radians(tilt))])
    return Shape(lambda P: (P - np.array([0.0, y0, 0.0])) @ nv, np.full(3, -BIG), np.full(3, BIG))


def above(y0, tilt=0.0):
    b = below(y0, tilt)
    return Shape(lambda P: -b(P), b.lo, b.hi)


def helix_stripes(c, rot, n, pitch, frac=0.5):
    """Champ de bandes obliques enroulées autour de l'axe Y local (n bandes par tour)."""
    c = np.asarray(c, dtype=np.float64)
    R = rot_matrix(*rot)

    def f(P):
        Q = (P - c) @ R
        th = np.arctan2(Q[:, 2], Q[:, 0])
        r = np.maximum(np.linalg.norm(Q[:, [0, 2]], axis=1), 1e-3)
        u = th * n / (2 * np.pi) + Q[:, 1] / pitch
        fr = u - np.floor(u)
        grad = np.sqrt((n / (2 * np.pi * r)) ** 2 + (1.0 / pitch) ** 2)
        return (np.abs(fr - 0.5) - frac * 0.5) / grad
    return Shape(f, c - BIG, c + BIG)


def plane_stripes(dirv, period, frac=0.5, offset=0.0):
    """Bandes planes parallèles, perpendiculaires à dirv."""
    nv = np.asarray(dirv, dtype=np.float64)
    nv = nv / np.linalg.norm(nv)

    def f(P):
        u = (P @ nv) / period + offset
        fr = u - np.floor(u)
        return (np.abs(fr - 0.5) - frac * 0.5) * period
    return Shape(f, np.full(3, -BIG), np.full(3, BIG))


def hazard_ring(part, c, r, h, rot, n, pitch, rr=0.012, tris=(170, 230), res=0.0049, base=HAZ):
    """Bague jaune à bandes sombres obliques (bandes de danger)."""
    hole = cyl(c, r - 0.03, h + 0.05, 0.0, rot)  # bague creuse : rien de caché à l'intérieur
    part.piece(base, tris=tris[0], res=res).add(cyl(c, r, h, rr, rot)).sub(hole)
    dark = inter(cyl(c, r + 0.006, h + 0.002, rr, rot), helix_stripes(c, rot, n, pitch))
    part.piece(METAL_D, tris=tris[1], res=res).add(dark).sub(hole)


def hazard_plate(part, shape, dirv, period, tris=(130, 200), res=0.0069, base=HAZ):
    """Plaque jaune à bandes sombres planes."""
    part.piece(base, tris=tris[0], res=res).add(shape)
    part.piece(METAL_D, tris=tris[1], res=res).add(inter(grow(shape, 0.006), plane_stripes(dirv, period)))


def build(elite=False):
    name = "brute_elite" if elite else "brute"
    LIT = GOLD if elite else CORE  # couleur des lumières (réacteurs, cheminées)
    PAINT = GOLD if elite else RED  # peinture d'accent (bandes d'épaule, crête)
    PLATE = GOLD if elite else SHELL  # plaques claires (élite : dorées)
    parts = []
    # ================================================================== torse (pivot aux hanches)
    HIP = (0, 0.52, 0)
    torso = RPart("torso", pivot=HIP, res=0.0089)
    # bassin et taille (métal sombre)
    pel = torso.piece(METAL, tris=320, res=0.0097)
    pel.add(rbox((0, 0.57, -0.01), (0.33, 0.13, 0.25), 0.11))
    for sx in (-1, 1):
        pel.add(sphere((sx * 0.24, 0.52, 0), 0.12), k=0.04)
    # caisse principale : frigo arrondi voûté vers l'avant ; haut clair, ventre sombre
    body = union([
        rbox((0, 1.08, -0.03), (0.47, 0.37, 0.36), 0.25, rot=(9, 0, 0)),
        ellipsoid((0, 1.16, 0.05), (0.5, 0.31, 0.36), rot=(9, 0, 0)),
        ellipsoid((0, 0.84, 0.0), (0.4, 0.2, 0.31)),
    ], k=0.1)
    socket = cyl((0, 1.09, 0.4), 0.15, 0.12, 0.02, rot=(99, 0, 0))  # logement du réacteur
    up = torso.piece(SHELL_D, tris=700, res=0.0107)
    up.add(inter(body, above(0.9, 9)))
    up.sub(socket, k=0.02)
    up.sub(inter(grow(body, 0.02), inter(above(0.885, 9), below(0.915, 9))), k=0.006)  # rainure de jonction
    lo = torso.piece(METAL, tris=400, res=0.0097)
    lo.add(inter(grow(body, -0.012), below(0.93, 9)))
    lo.add(cyl((0, 0.72, -0.01), 0.33, 0.09, 0.05), k=0.05)
    # plastron clair, percé autour du réacteur
    chest = torso.piece(PLATE, tris=450, res=0.0069)
    chest.add(rbox((0, 1.17, 0.3), (0.37, 0.2, 0.1), 0.09, rot=(9, 0, 0)))
    chest.sub(cyl((0, 1.09, 0.4), 0.16, 0.2, 0.02, rot=(99, 0, 0)), k=0.02)
    # bandes de faction sur les côtés du plastron
    stripe = torso.piece(PAINT, tris=220, res=0.0059)
    for sx in (-1, 1):
        stripe.add(inter(grow(rbox((0, 1.17, 0.3), (0.37, 0.2, 0.1), 0.09, rot=(9, 0, 0)), 0.005),
                         rbox((sx * 0.25, 1.17, 0.35), (0.04, 0.3, 0.2), 0.01, rot=(9, 0, 0))))
    # bague du réacteur et fond sombre
    ring = torso.piece(METAL, tris=240, res=0.0059)
    ring.add(torus((0, 1.09, 0.39), 0.13, 0.034, rot=(99, 0, 0)))
    for a in (0, 90, 180, 270):  # quatre griffes de maintien
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        ring.add(sphere((0.13 * ca, 1.09 + 0.13 * sa, 0.405 - 0.02 * sa), 0.03), k=0.01)
    torso.piece(METAL_D, tris=120, res=0.0079).add(cyl((0, 1.09, 0.35), 0.13, 0.04, 0.02, rot=(99, 0, 0)))
    # rivets du plastron
    riv = torso.piece(METAL_D, tris=160, res=0.0044)
    for sx in (-1, 1):
        for y in (1.01, 1.31):
            riv.add(sphere((sx * 0.33, y, 0.395 + 0.15 * (y - 1.17)), 0.021))
    # ceinture : bague de danger autour de la taille (vue de tous les côtés)
    hazard_ring(torso, (0, 0.72, -0.01), 0.345, 0.04, (0, 0, 0), 22, 0.6, tris=(220, 320), base=GOLD if elite else HAZ)
    # col : la tête s'y enfonce
    col = torso.piece(METAL, tris=240, res=0.0069)
    col.add(torus((0, 1.4, 0.1), 0.18, 0.06, rot=(12, 0, 0)))
    col.add(cyl((0, 1.38, 0.09), 0.2, 0.05, 0.03, rot=(12, 0, 0)), k=0.03)
    # emboîtures d'épaule
    so = torso.piece(METAL_D, tris=140, res=0.0097)
    for sx in (-1, 1):
        so.add(sphere((sx * 0.5, 1.32, -0.01), 0.15))
    # dos : sac réacteur, cheminées, bande de danger sur l'arête (vue de dessus)
    pack = torso.piece(METAL, tris=320, res=0.0079)
    pack.add(rbox((0, 1.13, -0.37), (0.33, 0.27, 0.13), 0.1, rot=(-6, 0, 0)))
    pack.sub(cyl((0, 1.1, -0.52), 0.12, 0.08, 0.02, rot=(90, 0, 0)), k=0.015)  # fenêtre du réacteur dorsal
    for sx in (-1, 1):
        pack.sub(rbox((sx * 0.215, 1.1, -0.5), (0.045, 0.15, 0.04), 0.03), k=0.01)  # évents latéraux
    stacks = torso.piece(METAL_D, tris=240, res=0.0059)
    for sx in (-1, 1):
        stacks.add(cyl((sx * 0.19, 1.45, -0.385), 0.08, 0.11, 0.025, rot=(-18, 0, 0)))
        stacks.sub(cyl((sx * 0.19, 1.56, -0.42), 0.052, 0.05, 0.01, rot=(-18, 0, 0)))
    stb = torso.piece(PAINT, tris=180, res=0.0059)
    for sx in (-1, 1):
        stb.add(cyl((sx * 0.19, 1.4, -0.37), 0.088, 0.024, 0.01, rot=(-18, 0, 0)))
    hazard_plate(torso, rbox((0, 1.335, -0.485), (0.27, 0.045, 0.03), 0.02, rot=(-6, 0, 0)), (1, 1, 0), 0.07,
                 base=GOLD if elite else HAZ)
    # évents sur le dessus des épaules, de part et d'autre de la tête (vue de dessus)
    vent = torso.piece(METAL, tris=220, res=0.0059)
    for sx in (-1, 1):
        vent.add(rbox((sx * 0.27, 1.43, -0.1), (0.085, 0.05, 0.13), 0.04, rot=(6, 0, sx * 10)))
        for dz in (-0.07, 0.0, 0.07):
            vent.sub(rbox((sx * 0.27, 1.49, -0.1 + dz), (0.06, 0.04, 0.017), 0.012, rot=(6, 0, sx * 10)), k=0.006)
    prv = torso.piece(SHELL, tris=120, res=0.0044)
    for sx in (-1, 1):
        for y in (0.92, 1.33):
            prv.add(sphere((sx * 0.28, y, -0.495 + 0.06 * (y - 1.13)), 0.022))
    parts.append(torso)

    # réacteur ventral (pivot au centre pour pulser)
    core_glow = RPart("core_glow", pivot=(0, 1.09, 0.38), parent="torso", res=0.0049)
    cg = core_glow.piece(LIT, tris=200)
    cg.add(ellipsoid((0, 1.09, 0.385), (0.105, 0.105, 0.06), rot=(9, 0, 0)))
    parts.append(core_glow)
    # réacteur dorsal + évents + cheminées
    back_glow = RPart("back_glow", pivot=HIP, parent="torso", res=0.0049)
    bg = back_glow.piece(LIT, tris=300)
    bg.add(cyl((0, 1.1, -0.47), 0.1, 0.03, 0.02, rot=(90, 0, 0)))
    for sx in (-1, 1):
        bg.add(rbox((sx * 0.215, 1.1, -0.47), (0.03, 0.13, 0.03), 0.02))
        bg.add(cyl((sx * 0.19, 1.52, -0.405), 0.052, 0.015, 0.008, rot=(-18, 0, 0)))
        for dz in (-0.07, 0.0, 0.07):
            bg.add(rbox((sx * 0.27, 1.445, -0.1 + dz), (0.05, 0.02, 0.009), 0.006, rot=(6, 0, sx * 10)))
    parts.append(back_glow)

    # ================================================================== tête (pivot au cou)
    NECK = (0, 1.4, 0.12)
    head = RPart("head", pivot=NECK, parent="torso", res=0.0049)
    hl = head.piece(SHELL, tris=500)
    hl.add(ellipsoid((0, 1.53, 0.15), (0.2, 0.165, 0.19)))
    hl.add(rbox((0, 1.46, 0.17), (0.18, 0.075, 0.16), 0.07), k=0.05)
    vis = head.piece(METAL_D, tris=260)
    for sx in (-1, 1):
        vis.add(rbox((sx * 0.078, 1.5, 0.293), (0.1, 0.075, 0.06), 0.05, rot=(0, 0, sx * 12)), k=0.02)
    head.piece(METAL, tris=110).add(rbox((0, 1.405, 0.3), (0.09, 0.026, 0.035), 0.018))  # grille de bouche
    ears = head.piece(METAL, tris=150)
    for sx in (-1, 1):
        ears.add(cyl((sx * 0.2, 1.5, 0.15), 0.06, 0.03, 0.012, rot=(0, 0, 90)))
    if elite:
        horns = head.piece(GOLD, tris=520)
        for sx in (-1, 1):
            horns.add(capsule((sx * 0.16, 1.6, 0.13), (sx * 0.29, 1.71, 0.09), 0.05, 0.035))
            horns.add(capsule((sx * 0.29, 1.71, 0.09), (sx * 0.31, 1.85, 0.13), 0.035, 0.012), k=0.03)
        horns.add(ellipsoid((0, 1.685, 0.12), (0.045, 0.06, 0.17)), k=0.02)
    else:
        head.piece(PAINT, tris=180).add(ellipsoid((0, 1.675, 0.1), (0.042, 0.055, 0.16)))  # crête
    parts.append(head)
    head_glow = RPart("head_glow", pivot=NECK, parent="head", res=0.0034)
    eg = head_glow.piece(EYE, tris=200)
    for sx in (-1, 1):
        eg.add(ellipsoid((sx * 0.078, 1.497, 0.348), (0.056, 0.042, 0.02), rot=(0, 0, sx * 12)))
    parts.append(head_glow)

    # ================================================================== bras (pivot à l'épaule) + avant-bras-marteau
    for side, sx in (("r", -1.0), ("l", 1.0)):
        SH = (sx * 0.5, 1.33, -0.01)
        arm = RPart("arm_" + side, pivot=SH, parent="torso", res=0.0079)
        pads = RPart("pad_" + side, pivot=SH, parent="torso", res=0.0079)  # suit le bras à moitié
        tilt = (0, 0, -sx * 16)
        padshape = union([
            ellipsoid((sx * 0.57, 1.42, -0.01), (0.27, 0.19, 0.29), rot=tilt),
            ellipsoid((sx * 0.6, 1.49, -0.01), (0.17, 0.1, 0.2), rot=tilt),
        ], k=0.05)
        pad = pads.piece(SHELL_D if not elite else SHELL, tris=350, res=0.0089)
        pad.add(padshape)
        # bande de faction sur le dessus de l'épaulière (visible de la caméra haute)
        pads.piece(PAINT, tris=170, res=0.0059).add(
            inter(grow(padshape, 0.006), rbox((sx * 0.6, 1.45, -0.01), (0.075, 0.3, 0.4), 0.01, rot=tilt)))
        rim_c = (sx * 0.585, 1.345, -0.01)
        if elite:
            pads.piece(GOLD, tris=200, res=0.0059).add(cyl(rim_c, 0.275, 0.035, 0.015, rot=tilt)).sub(
                cyl(rim_c, 0.245, 0.09, 0.0, rot=tilt))
            studs = pads.piece(GOLD_D, tris=260, res=0.0059)
            for zz in (-0.15, 0.0, 0.15):
                studs.add(capsule((sx * 0.7, 1.52, zz), (sx * 0.8, 1.62, zz * 1.1), 0.04, 0.012))
        else:
            hazard_ring(pads, rim_c, 0.275, 0.035, tilt, 16, 0.5)
        rv = pads.piece(METAL_D, tris=120, res=0.0044)
        for zz in (-0.2, 0.18):
            rv.add(sphere((sx * 0.75, 1.42, zz), 0.02))
        upa = arm.piece(METAL, tris=240, res=0.0079)
        upa.add(capsule((sx * 0.53, 1.3, -0.01), (sx * 0.6, 0.98, 0.03), 0.125, 0.1))
        parts.append(arm)
        parts.append(pads)

        EL = (sx * 0.6, 0.97, 0.03)
        fore = RPart("fore_" + side, pivot=EL, parent="arm_" + side, res=0.0079)
        fa = fore.piece(SHELL_D, tris=340, res=0.0079)
        fa.add(capsule((sx * 0.61, 0.95, 0.04), (sx * 0.635, 0.68, 0.08), 0.13, 0.17))
        fore.piece(METAL, tris=140, res=0.0069).add(torus((sx * 0.612, 0.92, 0.042), 0.125, 0.03, rot=(4, 0, -sx * 5)))  # bague de coude
        # poing-masse : gros moufle arrondi, quatre doigts repliés, pouce côté intérieur
        FC = (sx * 0.635, 0.41, 0.1)
        fist = fore.piece(SHELL, tris=480, res=0.0079)
        fist.add(rbox(FC, (0.205, 0.19, 0.215), 0.14))
        for dx in (-0.135, -0.045, 0.045, 0.135):
            fist.add(ellipsoid((FC[0] + dx, 0.335, 0.255), (0.052, 0.085, 0.075)), k=0.025)
        for dx in (-0.09, 0.0, 0.09):
            fist.sub(rbox((FC[0] + dx, 0.31, 0.32), (0.005, 0.09, 0.06), 0.004), k=0.01)
        fist.add(ellipsoid((FC[0] - sx * 0.2, 0.44, 0.2), (0.06, 0.1, 0.07), rot=(20, 0, 0)), k=0.03)  # pouce
        kn = fore.piece(GOLD if elite else METAL, tris=160, res=0.0059)
        kn.add(capsule((FC[0] - 0.15, 0.43, 0.3), (FC[0] + 0.15, 0.43, 0.3), 0.04))  # poing américain
        for dx in (-0.135, -0.045, 0.045, 0.135):
            kn.add(sphere((FC[0] + dx, 0.43, 0.33), 0.035), k=0.015)
        fore.piece(METAL, tris=160, res=0.0059).add(cyl((FC[0], 0.222, 0.1), 0.15, 0.025, 0.015))  # face de frappe
        if elite:
            fore.piece(GOLD, tris=200, res=0.0059).add(cyl((sx * 0.637, 0.625, 0.085), 0.19, 0.045, 0.015))
        else:
            hazard_ring(fore, (sx * 0.637, 0.625, 0.085), 0.19, 0.045, (0, 0, 0), 12, 0.45)
        parts.append(fore)

    # ================================================================== jambes (pivot hanche) + tibia (genou)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        HP = (sx * 0.24, 0.5, 0.0)
        leg = RPart("leg_" + side, pivot=HP, parent="torso", res=0.0079)
        leg.piece(METAL, tris=220).add(capsule((sx * 0.24, 0.5, 0.0), (sx * 0.27, 0.3, 0.02), 0.14, 0.13))
        parts.append(leg)
        KN = (sx * 0.27, 0.3, 0.02)
        shin = RPart("shin_" + side, pivot=KN, parent="leg_" + side, res=0.0079)
        sh = shin.piece(SHELL_D, tris=240)
        sh.add(rbox((sx * 0.275, 0.21, 0.02), (0.15, 0.12, 0.15), 0.1))
        shin.piece(PLATE, tris=140, res=0.0059).add(rbox((sx * 0.272, 0.3, 0.135), (0.1, 0.085, 0.05), 0.04, rot=(-12, 0, 0)))
        boot = shin.piece(METAL_D, tris=240)
        boot.add(rbox((sx * 0.285, 0.08, 0.06), (0.19, 0.08, 0.25), 0.07))
        shin.piece(SHELL_D, tris=160, res=0.0069).add(rbox((sx * 0.285, 0.085, 0.245), (0.195, 0.07, 0.085), 0.06))  # coque d'orteil
        parts.append(shin)
    return Character(name, parts)
