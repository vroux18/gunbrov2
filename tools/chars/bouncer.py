"""Videur (code « bouncer ») : gros robot videur de boîte de nuit, de la bande des Néons.
Silhouette de videur en costume (pas de robot de chantier) : veste violet nuit aux épaules carrées, taille
plus étroite, chemise blanche en V, revers satinés, cravate noire, grosse chaîne dorée à médaillon, pochette
orange ; petite tête chromée arrondie, lunettes noires enveloppantes (reflet rose néon), joues roses, petit
sourire en coin, oreillette à fil spiralé ; gros poings chromés à poings américains néon orange (#FF8A3C),
manchettes blanches ; jambes courtes, chaussures vernies.
Regarde vers +Z ; sa droite est en -X. ~1,5 de large (poings compris), ~1,6 de haut.

Parts (pivots) : torso (racine, hanches) > chain (cou : la chaîne ballotte), head (cou) > shades (lunettes,
s'envolent à la mort) > shades_glow (reflet) ; torso > arm_r/arm_l (épaule) > fore_r/fore_l (coude, avec le
poing) > knuck_r_glow / knuck_l_glow (poings américains) ; torso > leg_r/leg_l (hanche) > shin_r/shin_l
(genou, avec la chaussure).
Variante élite (build(elite=True), tools/chars/bouncer_elite.py) : crête punk dorée sur le crâne et clous
dorés sur les épaules (détails de silhouette), monture des lunettes, boutons, médaillon et manchettes or.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import *  # noqa: E402,F403
from sniper import Part, union, inter, grow, side, slab, add  # noqa: E402  (pièces à normales lisses, outils)

SUIT = "#3F3870"     # veste violet nuit (se détache du sol sombre)
SUIT_D = "#2C2752"   # pantalon, dessous des manches
LAPEL = "#1B1830"    # revers satinés
SHIRT = "#EEF2FA"
TIE = "#14151F"
CHROME = "#C8CEDC"
CHROME_M = "#9AA4B6"
METAL = "#2C3350"
METAL_D = "#1C2238"
LENS = "#0A0B14"
SHOE = "#15161F"
SHOE_L = "#3A3D52"
CHAIN = "#FFC94A"    # or jaune de la chaîne
CHAIN_D = "#C98A22"
ORANGE = "#FF8A3C"   # poings américains (lueur, énergie ~1)
POCKET = "#FF8A3C"
BLUSH = "#FF7FB0"
PINK = "#FF3CAC"
GOLD = "#FFB347"
GOLD_D = "#C9842A"

HIP = (0.0, 0.5, 0.0)
NECK = (0.0, 1.22, 0.03)
HC = (0.0, 1.405, 0.05)  # centre de la tête
SH_X = 0.5
SH_Y = 1.06
TRI = 0.83  # facteur global du budget de triangles (~13 000)


def bnd(s, lo, hi):
    """Même forme, boîte englobante resserrée (celles de rbox/ellipsoïde tournés sont très larges)."""
    return Shape(s.fn, np.asarray(lo, dtype=np.float64), np.asarray(hi, dtype=np.float64))


def skin(sh, out, inn=0.03):
    """Pellicule autour de la surface (de -inn à +out) : peintures et pièces posées, sans volume caché que
    l'allègement abîmerait."""
    return Shape(lambda P: (lambda d: np.maximum(d - out, -(d + inn)))(sh(P)), sh.lo - max(out, 0.0), sh.hi + max(out, 0.0))


def bead_path(body_sdf, n, s0, s1, fx, fy, off):
    """Points d'une chaîne posée sur la surface avant du corps : (x, y) = (fx(s), fy(s)), z trouvé sur la
    surface (premier passage du champ de distance en venant de l'avant), décalés de `off`."""
    pts = []
    zs = np.linspace(0.6, -0.1, 400)
    for s in np.linspace(s0, s1, n):
        x, y = fx(s), fy(s)
        P = np.stack([np.full_like(zs, x), np.full_like(zs, y), zs], axis=1)
        d = body_sdf(P)
        i = int(np.argmax(d < 0.0))
        pts.append([x, y, zs[max(i - 1, 0)] + off])
    return pts


def build(elite=False):
    name = "bouncer_elite" if elite else "bouncer"
    q = 0.92 if elite else 1.0

    def T(n):
        return max(50, int(n * q * TRI))

    TRIM = GOLD if elite else CHAIN
    parts = []

    # ================================================================== torse (racine, pivot aux hanches)
    torso = Part("torso", pivot=HIP, res=0.007)
    body = union([
        ellipsoid((0, 0.7, 0.02), (0.37, 0.22, 0.29)),
        rbox((0, 0.94, 0.0), (0.45, 0.2, 0.3), 0.17),
        rbox((0, 1.1, -0.02), (0.57, 0.105, 0.28), 0.1),
        ellipsoid((0, 0.99, 0.1), (0.36, 0.17, 0.22)),
    ], k=0.09)
    body = bnd(body, (-0.62, 0.42, -0.36), (0.62, 1.26, 0.38))
    # ouverture en V de la veste (chemise), revers de part et d'autre
    VB = 0.75  # pointe du V
    vk = 0.4
    vnorm = 1.0 / math.sqrt(1 + vk * vk)

    def vfield(P, w=0.0):
        return np.maximum((np.abs(P[:, 0]) - (P[:, 1] - VB) * vk - w) * vnorm, -(P[:, 2] - 0.05))
    vee = Shape(lambda P: vfield(P), np.array([-1, VB, 0.05]), np.array([1, 1.4, 1]))
    lap_band = Shape(lambda P: np.maximum(vfield(P, 0.085), -vfield(P)), np.array([-1, VB, 0.05]), np.array([1, 1.4, 1]))
    jacket = torso.piece(SUIT, tris=T(1500))
    jacket.add(body)
    jacket.sub(inter(grow(body, 0.05), vee), k=0.012)
    # pantalon (bassin) sous la veste
    torso.piece(SUIT_D, tris=T(300)).add(ellipsoid((0, 0.53, 0.0), (0.31, 0.12, 0.23)))
    # ourlet de la veste (un peu plus sombre, vu de face)
    hem = torso.piece(SUIT_D, tris=T(260))
    hem.add(inter(skin(body, 0.006), slab((0, 0.53, 0), (0, 1, 0.12), 0.03)))
    shirt = torso.piece(SHIRT, tris=T(380))
    shirt.add(inter(skin(body, -0.018, 0.06), grow(vee, 0.02)))
    lapel = torso.piece(LAPEL, tris=T(520))
    lapel.add(inter(inter(skin(body, 0.01), lap_band), side((0, 0.84, 0), (0, 1, 0))))
    # col de chemise (deux pointes) et cravate
    col = torso.piece(SHIRT, tris=T(220))
    for sx in (-1, 1):
        col.add(capsule((sx * 0.1, 1.2, 0.17), (sx * 0.055, 1.1, 0.27), 0.03, 0.016), k=0.01)
    tie = torso.piece(TIE, tris=T(240))
    tie.add(inter(skin(body, -0.002, 0.04), union([
        rbox((0, 1.13, 0.27), (0.04, 0.03, 0.2), 0.02),
        Shape(lambda P: np.maximum(np.abs(P[:, 0]) - 0.035 - (1.1 - P[:, 1]) * 0.12, np.abs(P[:, 1] - 0.95) - 0.16), np.array([-0.2, 0.78, -1]), np.array([0.2, 1.12, 1])),
    ])))
    # boutons et pochette
    btn = torso.piece(TRIM, tris=T(120))
    btn.add(sphere((0, 0.72, 0.305), 0.026))
    btn.add(sphere((0, 0.63, 0.29), 0.022))
    pk = torso.piece(POCKET, tris=T(140))
    for dx, h in ((-0.03, 0.05), (0.015, 0.065), (0.055, 0.045)):
        pk.add(ellipsoid((0.27 + dx, 0.99 + h * 0.4, 0.29), (0.024, h * 0.6, 0.02), rot=(0, 0, dx * 300)))
    torso.piece(LAPEL, tris=T(80)).add(inter(skin(body, 0.008), rbox((0.27, 0.975, 0.3), (0.075, 0.012, 0.1), 0.006)))
    # cou (sombre) et col de veste dans la nuque
    neck = torso.piece(METAL, tris=T(160))
    neck.add(cyl((0, 1.2, 0.02), 0.1, 0.06, 0.03))
    torso.piece(LAPEL, tris=T(240)).add(inter(torus((0, 1.18, 0.0), 0.15, 0.04, rot=(-8, 0, 0)), side((0, 0, 0.06), (0, 0, -1))))
    # dos : couture centrale et motif inventé (petit chevron orange cousu)
    back = torso.piece(SUIT_D, tris=T(140))
    back.add(inter(skin(body, 0.004), slab((0, 0, 0), (1, 0, 0), 0.008)))
    back.sub(side((0, 0, -0.05), (0, 0, 1)))
    if elite:
        # clous dorés sur le dessus des épaules carrées (silhouette punk de chef de la sécurité)
        studs = torso.piece(GOLD, tris=T(520))
        for sx in (-1, 1):
            for i, dz in enumerate((-0.15, -0.03, 0.09)):
                bx = sx * (0.42 + 0.03 * (i == 1))
                studs.add(cyl((bx, 1.19, dz), 0.035, 0.02, 0.01))
                studs.add(capsule((bx, 1.2, dz), (bx * 1.06, 1.3, dz * 1.1), 0.03, 0.006), k=0.01)
    parts.append(torso)

    # ================================================================== chaîne dorée (pivot au cou : ballotte)
    chain = Part("chain", pivot=(0, 1.17, 0.12), parent="torso", res=0.004)
    pts = bead_path(body, 19, -1.0, 1.0, lambda s: 0.19 * math.sin(s * 1.35), lambda s: 0.89 + 0.27 * (1 - math.cos(s * 1.35)) / (1 - math.cos(1.35)), 0.012)
    links = chain.piece(CHAIN, tris=T(900))
    for i, pnt in enumerate(pts):
        if abs(i - 9) <= 0:
            continue
        nxt = pts[min(i + 1, len(pts) - 1)]
        prv = pts[max(i - 1, 0)]
        tg = np.array(nxt) - np.array(prv)
        ang = math.degrees(math.atan2(tg[1], tg[0]))
        rr = 0.024 if i % 2 == 0 else 0.019
        links.add(ellipsoid(pnt, (rr * 1.25, rr, rr * 0.75), rot=(0, 0, ang)))
    md = pts[9]
    medal = chain.piece(TRIM, tris=T(320))
    mc = add(md, (0, -0.045, 0.006))
    medal.add(cyl(mc, 0.058, 0.014, 0.008, rot=(80, 0, 0)))
    medal.add(sphere(add(md, (0, 0.012, 0)), 0.022), k=0.008)
    # glyphe inventé en creux sur le médaillon (losange barré)
    medal.sub(rbox(add(mc, (0, 0, 0.018)), (0.022, 0.022, 0.008), 0.004, rot=(80, 0, 45)), k=0.004)
    chain.piece(CHAIN_D, tris=T(120)).add(rbox(add(mc, (0, 0, 0.008)), (0.012, 0.03, 0.008), 0.004, rot=(-10, 0, 0)))
    parts.append(chain)

    # ================================================================== tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="torso", res=0.0045)
    hsh = union([
        rbox(HC, (0.18, 0.162, 0.172), 0.12),
        ellipsoid(add(HC, (0, -0.06, 0.03)), (0.15, 0.1, 0.14)),
    ], k=0.04)
    hsh = bnd(hsh, add(HC, (-0.21, -0.2, -0.2)), add(HC, (0.21, 0.2, 0.22)))
    skull = head.piece(CHROME, tris=T(800))
    skull.add(hsh)
    # menton et joues un peu plus foncés
    jaw = head.piece(CHROME_M, tris=T(260))
    jaw.add(inter(skin(hsh, 0.004), side(add(HC, (0, -0.075, 0)), (0, -1, -0.25))))
    # sourire en coin (sillon sombre)
    mouth = head.piece(METAL_D, tris=T(160), res=0.003)
    mpts = [(-0.052, -0.072), (-0.012, -0.086), (0.03, -0.083), (0.062, -0.062)]

    def mouth2(P):
        x = P[:, 0] - HC[0]
        y = P[:, 1] - HC[1]
        d = None
        for (ax, ay), (bx, by) in zip(mpts[:-1], mpts[1:]):
            vx, vy = bx - ax, by - ay
            h = np.clip(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy), 0, 1)
            e = np.hypot(x - ax - h * vx, y - ay - h * vy) - 0.011
            d = e if d is None else np.minimum(d, e)
        return d
    mouth.add(inter(inter(skin(hsh, 0.005, 0.012), Shape(mouth2, np.full(3, -5.0), np.full(3, 5.0))), side(add(HC, (0, 0, 0.08)), (0, 0, 1))))
    blush = head.piece(BLUSH, tris=T(160))
    for sx in (-1, 1):
        blush.add(inter(skin(hsh, 0.003), ellipsoid(add(HC, (sx * 0.11, -0.04, 0.16)), (0.04, 0.025, 0.06))))
    ears = head.piece(METAL, tris=T(200))
    for sx in (-1, 1):
        ears.add(cyl(add(HC, (sx * 0.18, 0.0, 0.0)), 0.05, 0.022, 0.01, rot=(0, 0, 90)))
    # oreillette (côté droit) et son fil spiralé qui descend dans le col
    ear = head.piece(METAL_D, tris=T(380), res=0.003)
    ear.add(sphere(add(HC, (-0.205, -0.005, 0.02)), 0.026))
    a0 = np.array(add(HC, (-0.205, -0.03, 0.0)))
    a1 = np.array([-0.13, 1.2, -0.06])
    prev = None
    for i in range(29):
        u = i / 28.0
        c = a0 + (a1 - a0) * u
        th = u * 7 * 2 * math.pi
        p_ = c + np.array([math.cos(th) * 0.012, 0, math.sin(th) * 0.012])
        if prev is not None:
            ear.add(capsule(prev.tolist(), p_.tolist(), 0.0045))
        prev = p_
    if elite:
        crest = head.piece(GOLD, tris=T(600), res=0.004)
        for i, (dz, h) in enumerate(((0.1, 0.07), (0.03, 0.11), (-0.05, 0.12), (-0.13, 0.09))):
            base = add(HC, (0, 0.12, dz))
            crest.add(inter(slab((0, 0, 0), (1, 0, 0), 0.024), capsule(base, add(base, (0, h * 1.15, -0.05)), 0.05, 0.012)), k=0.02)
    parts.append(head)

    # lunettes enveloppantes (part à part : elles s'envolent à la mort)
    shades = Part("shades", pivot=add(HC, (0, 0.02, 0.17)), parent="head", res=0.0035)
    yc = HC[1] + 0.012

    def lens2(P):
        """Deux verres ovales (style wayfarer : haut droit), en prisme selon Z."""
        d = None
        for sx in (-1, 1):
            u = (P[:, 0] - sx * 0.082) / 0.088
            v = (P[:, 1] - yc) / 0.058
            e = (np.sqrt(u * u + v * v) - 1.0) * 0.058
            d = e if d is None else np.minimum(d, e)
        return np.maximum(d, P[:, 1] - (yc + 0.04))
    lshell = Shape(lambda P: np.maximum(hsh(P) - 0.017, -(hsh(P) - 0.002)), hsh.lo - 0.02, hsh.hi + 0.02)
    lensh = inter(inter(lshell, Shape(lens2, np.full(3, -5.0), np.full(3, 5.0))), side(add(HC, (0, 0, 0.02)), (0, 0, 1)))
    lensh = bnd(lensh, add(HC, (-0.22, -0.06, 0.0)), add(HC, (0.22, 0.07, 0.22)))
    lens = shades.piece(LENS, tris=T(520))
    lens.add(lensh)
    frame = shades.piece(GOLD if elite else METAL, tris=T(280))
    brow = Shape(lambda P: np.maximum(np.abs(P[:, 1] - (yc + 0.043)) - 0.009, np.abs(P[:, 0]) - 0.172), np.full(3, -5.0), np.full(3, 5.0))
    frame.add(inter(inter(skin(hsh, 0.022, 0.01), brow), side(add(HC, (0, 0, 0.0)), (0, 0, 1))))
    for sx in (-1, 1):  # branches
        frame.add(capsule(add(HC, (sx * 0.195, 0.045, 0.06)), add(HC, (sx * 0.195, 0.04, -0.07)), 0.009))
    parts.append(shades)
    sg = Part("shades_glow", pivot=add(HC, (0, 0.02, 0.17)), parent="shades", res=0.0025)
    refl = sg.piece(PINK, tris=T(180))
    for sx in (-1, 1):
        refl.add(inter(grow(lensh, 0.002), slab(add(HC, (sx * 0.082 - 0.012, yc - HC[1] + 0.008, 0)), (1, 0.9, 0), 0.008)))
    parts.append(sg)

    # ================================================================== bras (épaule) + avant-bras et poing (coude)
    for side_n, sx in (("r", -1.0), ("l", 1.0)):
        SH = (sx * SH_X, SH_Y, -0.02)
        EL = (sx * 0.585, 0.8, 0.0)
        WR = (sx * 0.605, 0.53, 0.04)
        FC = (sx * 0.61, 0.38, 0.06)
        arm = Part("arm_" + side_n, pivot=SH, parent="torso", res=0.006)
        sl = arm.piece(SUIT, tris=T(420))
        sl.add(capsule(SH, EL, 0.15, 0.14))
        parts.append(arm)
        fore = Part("fore_" + side_n, pivot=EL, parent="arm_" + side_n, res=0.006)
        fs = fore.piece(SUIT, tris=T(320))
        fs.add(capsule(EL, add(WR, (0, 0.035, 0)), 0.14, 0.125))
        fore.piece(TRIM if elite else SHIRT, tris=T(200)).add(cyl(add(WR, (0, 0.0, 0)), 0.138, 0.034, 0.016, rot=(-4, 0, sx * 3)))
        fore.piece(TRIM, tris=T(80)).add(sphere(add(WR, (0.0, 0.0, 0.137)), 0.018))  # bouton de manchette
        fist = fore.piece(CHROME, tris=T(700))
        fist.add(rbox(FC, (0.13, 0.12, 0.135), 0.085))
        for i, dx in enumerate((-0.075, -0.025, 0.025, 0.075)):
            fist.add(ellipsoid((FC[0] + dx, FC[1] - 0.015, FC[2] + 0.115), (0.034, 0.05, 0.045)), k=0.02)
        fist.add(ellipsoid((FC[0] - sx * 0.12, FC[1] + 0.01, FC[2] + 0.06), (0.04, 0.06, 0.05), rot=(20, 0, 0)), k=0.03)  # pouce
        fore.piece(CHROME_M, tris=T(140)).add(cyl(add(FC, (0, 0.12, -0.01)), 0.1, 0.02, 0.01))  # poignet
        parts.append(fore)
        kg = Part("knuck_" + side_n + "_glow", pivot=FC, parent="fore_" + side_n, res=0.0035)
        kn = kg.piece(ORANGE, tris=T(380))
        kn.add(capsule((FC[0] - 0.11, FC[1] + 0.03, FC[2] + 0.135), (FC[0] + 0.11, FC[1] + 0.03, FC[2] + 0.135), 0.032))
        for dx in (-0.075, -0.025, 0.025, 0.075):
            kn.add(torus((FC[0] + dx, FC[1] + 0.03, FC[2] + 0.12), 0.036, 0.014), k=0.008)
            kn.add(sphere((FC[0] + dx, FC[1] + 0.035, FC[2] + 0.172), 0.024), k=0.01)
        parts.append(kg)

    # ================================================================== jambes (hanche) + tibia et chaussure (genou)
    for side_n, sx in (("r", -1.0), ("l", 1.0)):
        HP = (sx * 0.19, 0.48, 0.0)
        KN = (sx * 0.205, 0.27, 0.01)
        AN = (sx * 0.21, 0.15, 0.0)
        leg = Part("leg_" + side_n, pivot=HP, parent="torso", res=0.006)
        leg.piece(SUIT_D, tris=T(280)).add(capsule(HP, KN, 0.15, 0.135))
        parts.append(leg)
        shin = Part("shin_" + side_n, pivot=KN, parent="leg_" + side_n, res=0.006)
        shin.piece(SUIT_D, tris=T(260)).add(capsule(KN, AN, 0.135, 0.125))
        shoe_sh = union([
            rbox((sx * 0.21, 0.065, 0.06), (0.125, 0.065, 0.19), 0.06),
            ellipsoid((sx * 0.21, 0.07, 0.17), (0.12, 0.06, 0.1)),
        ], k=0.03)
        shoe = shin.piece(SHOE, tris=T(380))
        shoe.add(shoe_sh)
        shoe.sub(side((0, 0.012, 0), (0, -1, 0)))
        shin.piece(SHOE_L, tris=T(200)).add(inter(grow(shoe_sh, 0.004), slab((0, 0.022, 0), (0, 1, 0), 0.013)))  # semelle
        shin.piece(SUIT_D, tris=T(160)).add(cyl((sx * 0.21, 0.135, 0.0), 0.142, 0.022, 0.012))  # ourlet du pantalon
        parts.append(shin)
    return Character(name, parts)
