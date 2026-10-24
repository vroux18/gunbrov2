"""Pirate (code « hacker ») : robot pirate informatique du gang des Néons.
Sweat à capuche violet à capuche pointue tombant dans le dos (passepoil vert acide autour de l'ouverture,
ligne verte sur le dessus : lisible du dessus), tête-écran sombre à grosses lunettes rondes vert acide et
sourire en pixels, sac à dos serveur à antenne, avant-bras de robot clairs, ordinateur au poignet gauche,
pantalon cargo, baskets épaisses. Il projette un écran holographique (holo_glow) devant lui pour pirater.
Regarde vers +Z ; sa droite est en -X. Hauteur ~1,15 antenne comprise, largeur ~0,6 (Jo : 1,10).

Parts (pivots) : pelvis (racine, hanches) > torso (taille) > head (cou) > head_glow (lunettes, pixels),
hood (nuque) > hood_glow (passepoil, ligne) ; torso > chest_glow (bouts des cordons, voyants et antenne
du sac), arm_r/arm_l (épaule) > fore_r/fore_l (coude, avec la main) ; fore_l > wrist_glow (écran du
poignet) ; torso > holo_glow (écran et clavier holographiques, pivot au centre de l'écran, placé par le
script) ; pelvis > leg_r/leg_l (hanche) > shin_r/shin_l (genou, avec la basket).
Variante élite (build(elite=True), tools/chars/hacker_elite.py) : lunettes et hologramme toujours vert
acide (signature), passepoil, montures, fermeture et garnitures or, et une parabole dorée sur le sac.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import *  # noqa: E402,F403
from sniper import union, inter, grow, side, slab, add, shell  # noqa: E402
from roller import Part, scaled, fin  # noqa: E402  (normales lisses, lumières sans ombrage)

HOOD = "#5D4C98"     # sweat violet (complémentaire du vert acide)
HOOD_D = "#3C3068"
HOOD_L = "#7564B0"
PANTS = "#272338"
PANTS_D = "#1A1727"
SHELL = "#E6E3EE"    # avant-bras et baskets
SHELL_M = "#ADA7C0"
DARK = "#1E1B2C"
JOINT = "#3E3A58"
FACE = "#0E0C18"
ACID = "#B6FF3C"     # lueur vert acide (énergie ~1)
ACID_RIM = "#7FD01E"
ACID_P = "#8FD62A"   # peinture verte (lacets), sans luire
HOLO_DIM = "#2E4A10"  # fond de l'hologramme (mélange additif : vert translucide)
HOLO_MID = "#5E8F1E"
WHITE = "#FFFFFF"
GOLD = "#FFB347"
GOLD_P = "#E8A53A"
GOLD_D = "#A8661E"

# repères partagés avec scripts/mobs/hacker.gd
HIP_Y = 0.5
HIP_X = 0.076
KNEE_Y = 0.285
ANKLE_Y = 0.078
WAIST = (0.0, 0.56, 0.0)
NECK = (0.0, 0.8, 0.0)
HC = (0.0, 0.935, 0.02)  # centre de la tête
HR = 0.118
HOOD_P = (0.0, 0.87, -0.07)  # pivot de la capuche (nuque)
SH = (0.152, 0.752, -0.012)  # épaule gauche (+X)
EL = (0.205, 0.632, -0.025)
HAND = (0.222, 0.512, 0.012)
HOLO = (0.0, 0.76, 0.3)  # centre de l'écran holographique (pose de piratage)
HOLO_TILT = -48.0
TRI = 0.72


def build(elite=False):
    q = 0.92 if elite else 1.0

    def T(n):
        return max(50, int(n * q * TRI))

    trim = GOLD_P if elite else HOOD_D
    pipe = GOLD if elite else ACID  # passepoil de la capuche
    rim = GOLD_P if elite else JOINT  # montures des lunettes
    parts = []

    # ================================================================== bassin (racine)
    pelvis = Part("pelvis", pivot=(0, HIP_Y, 0), res=0.0045)
    pv = pelvis.piece(PANTS, tris=T(320))
    pv.add(ellipsoid((0, 0.525, -0.004), (0.122, 0.072, 0.09)))
    pv.add(ellipsoid((0, 0.565, 0.0), (0.1, 0.045, 0.08)), k=0.03)
    pelvis.piece(trim if elite else DARK, tris=T(160)).add(cyl((0, 0.57, 0), 0.106, 0.014, 0.007))  # ceinture
    parts.append(pelvis)

    # ================================================================== buste : sweat (pivot à la taille)
    torso = Part("torso", pivot=WAIST, parent="pelvis", res=0.0045)
    body_sh = union([
        ellipsoid((0, 0.675, -0.01), (0.14, 0.125, 0.105)),
        ellipsoid((0, 0.75, -0.015), (0.158, 0.058, 0.1)),
        capsule((0, 0.58, 0), (0, 0.63, 0), 0.105),
    ], k=0.04)
    sw = torso.piece(HOOD, tris=T(560))
    sw.add(body_sh)
    sw.add(cyl((0, 0.795, -0.005), 0.05, 0.03, 0.012), k=0.015)  # cou
    sw.paint(slab((0, 0, 0.1), (1, 0, 0), 0.0035), HOOD_D)  # fermeture
    sw.paint(inter(rbox((0, 0.625, 0.1), (0.085, 0.04, 0.05), 0.02), side((0, 0, 0.05), (0, 0, 1))), HOOD_D)  # poche kangourou
    torso.piece(HOOD_D, tris=T(240)).add(torus((0, 0.585, 0), 0.112, 0.022))  # bord-côte
    # cordons de la capuche
    cords = torso.piece(SHELL_M, tris=T(120), res=0.0032)
    for sx in (-1, 1):
        cords.add(capsule((sx * 0.032, 0.79, 0.085), (sx * 0.04, 0.71, 0.112), 0.0055))
    if elite:
        torso.piece(GOLD_P, tris=T(120), res=0.003).add(rbox((0, 0.72, 0.112), (0.012, 0.018, 0.006), 0.004))  # tirette
    # sac à dos serveur
    bag = torso.piece(DARK, tris=T(360))
    bag_sh = rbox((0, 0.69, -0.135), (0.095, 0.1, 0.048), 0.032)
    bag.add(bag_sh)
    bag.paint(slab((0, 0.69, -0.18), (0, 1, 0), 0.006), JOINT)  # nervures
    bag.paint(slab((0, 0.65, -0.18), (0, 1, 0), 0.006), JOINT)
    straps = torso.piece(PANTS_D, tris=T(200))
    for sx in (-1, 1):
        straps.add(inter(grow(body_sh, 0.008), slab((sx * 0.085, 0, 0), (1, 0, 0), 0.016)))
    straps.sub(side((0, 0.6, 0), (0, -1, 0)))
    ant = torso.piece(JOINT, tris=T(140), res=0.0035)
    ant.add(capsule((0.062, 0.78, -0.15), (0.09, 1.02, -0.2), 0.009, 0.006))
    ant.add(cyl((0.062, 0.785, -0.15), 0.02, 0.012, 0.005), k=0.006)
    if elite:
        # parabole dorée sur le sac (silhouette d'élite)
        dish = torso.piece(GOLD_P, tris=T(420), res=0.0035)
        dc = np.array((-0.05, 0.84, -0.17))
        dn = np.array((-0.35, 0.8, -0.5))
        dn = dn / np.linalg.norm(dn)
        bowl = sphere((dc - dn * 0.1).tolist(), 0.13)
        dish.add(inter(shell(bowl, 0.006, -0.006), side((dc - dn * 0.035).tolist(), dn)))
        dish.add(capsule((-0.03, 0.77, -0.16), (dc - dn * 0.03).tolist(), 0.012), k=0.006)
        dish.add(capsule(dc.tolist(), (dc + dn * 0.07).tolist(), 0.006), k=0.0)
    parts.append(torso)

    cg = Part("chest_glow", pivot=WAIST, parent="torso", res=0.003)
    leds = cg.piece(ACID, tris=T(160))
    for sx in (-1, 1):
        leds.add(capsule((sx * 0.04, 0.712, 0.112), (sx * 0.041, 0.698, 0.116), 0.009))  # bouts des cordons
    for dx in (-0.05, -0.025):
        leds.add(sphere((dx, 0.74, -0.18), 0.009))  # voyants du sac
    leds.add(sphere((0.09, 1.025, -0.2), 0.017))  # bout de l'antenne
    if elite:
        leds.add(sphere((-0.05 + 0.35 * 0.07 * -1.0, 0.84 + 0.8 * 0.07, -0.17 - 0.5 * 0.07), 0.014))
    parts.append(cg)

    # ================================================================== tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="torso", res=0.0038)
    head_sh = union([
        ellipsoid(HC, (HR * 1.06, HR * 0.94, HR)),
        ellipsoid(add(HC, (0, -0.04, 0.015)), (HR * 0.9, HR * 0.62, HR * 0.86)),
    ], k=0.04)
    hd = head.piece(JOINT, tris=T(400))
    hd.add(head_sh)
    fz = HC[2] + HR * 0.86
    face_sh = rbox((0, HC[1] - 0.01, fz), (HR * 0.86, HR * 0.62, 0.05), 0.045)
    hd.sub(face_sh, k=0.01)
    face = head.piece(FACE, tris=T(240))
    face.add(inter(grow(head_sh, -0.006), grow(face_sh, 0.003)))
    # lunettes rondes : montures épaisses et sangle
    gog = head.piece(rim, tris=T(360), res=0.0032)
    for sx in (-1, 1):
        gc = (sx * 0.05, HC[1] + 0.008, fz + 0.012)
        gog.add(cyl(gc, 0.042, 0.018, 0.01, rot=(90, 0, 0)))
        gog.sub(cyl(add(gc, (0, 0, 0.02)), 0.031, 0.016, 0.004, rot=(90, 0, 0)), k=0.004)
    gog.add(capsule((-0.012, HC[1] + 0.008, fz + 0.022), (0.012, HC[1] + 0.008, fz + 0.022), 0.008), k=0.006)  # pont
    head.piece(DARK, tris=T(200)).add(inter(torus(add(HC, (0, 0.008, 0)), HR * 1.02, 0.014), side(add(HC, (0, 0, 0.04)), (0, 0, -1))))  # sangle
    parts.append(head)

    hg = Part("head_glow", pivot=NECK, parent="head", res=0.0026)
    lens = hg.piece(ACID_RIM, tris=T(240))
    for sx in (-1, 1):
        gc = (sx * 0.05, HC[1] + 0.008, fz + 0.016)
        lens.add(ellipsoid(gc, (0.033, 0.033, 0.012)))
        lens.paint(ellipsoid(add(gc, (0, 0, 0.006)), (0.024, 0.024, 0.012)), ACID)
    pup = hg.piece(FACE, tris=T(80))
    for sx in (-1, 1):
        pup.add(ellipsoid((sx * 0.048, HC[1] + 0.004, fz + 0.026), (0.011, 0.013, 0.006)))
    glint = hg.piece(WHITE, tris=T(60))
    for sx in (-1, 1):
        glint.add(sphere((sx * 0.05 + 0.014, HC[1] + 0.022, fz + 0.026), 0.006))
    # sourire en coin, en pixels
    px = hg.piece(ACID, tris=T(120))
    for i, (dx, dy) in enumerate(((-0.03, 0.0), (-0.015, -0.009), (0.0, -0.012), (0.015, -0.009), (0.028, 0.004))):
        px.add(rbox((dx, HC[1] - 0.058 + dy, fz + 0.005), (0.0062, 0.0062, 0.006), 0.002))
    parts.append(hg)

    # capuche (pivot à la nuque) : coque autour de la tête, pointe tombant dans le dos
    hood = Part("hood", pivot=HOOD_P, parent="head", res=0.0042)
    outer = union([
        grow(head_sh, 0.03),
        capsule(add(HC, (0, 0.06, -0.06)), add(HC, (0, -0.01, -0.23)), 0.08, 0.012),
        ellipsoid(add(HC, (0, -0.1, -0.06)), (0.13, 0.06, 0.1)),
    ], k=0.05)
    opening = ellipsoid((0, HC[1] - 0.008, HC[2] + 0.13), (0.118, 0.124, 0.13))
    hh = hood.piece(HOOD, tris=T(820))
    hh.add(outer)
    hh.sub(grow(head_sh, 0.012), k=0.01)
    hh.sub(opening, k=0.015)
    hh.sub(side((0, HC[1] - 0.115, 0), (0, -1, 0.35)), k=0.02)  # bas de la capuche : dégage le cou devant
    hh.paint(inter(grow(head_sh, 0.03), side(add(HC, (0, 0, 0.05)), (0, 0, 1))), HOOD_L)  # bord clair autour du visage
    hh.paint(grow(head_sh, 0.03), HOOD_D)  # doublure
    parts.append(hood)

    hog = Part("hood_glow", pivot=HOOD_P, parent="hood", res=0.003)
    pp = hog.piece(pipe, tris=T(320))
    # passepoil : anneau à l'ouverture de la capuche
    pp.add(inter(shell(opening, 0.008, -0.002), grow(outer, 0.005)))
    pp.sub(grow(head_sh, 0.02))
    pp.sub(side((0, HC[1] - 0.105, 0), (0, -1, 0.35)), k=0.01)
    # ligne verte du front à la pointe (vue de dessus)
    line = hog.piece(ACID, tris=T(220))
    line.add(inter(grow(outer, 0.004), slab((0, 0, 0), (1, 0, 0), 0.008)))
    line.sub(grow(outer, -0.012))
    line.sub(side((0, HC[1] + 0.02, 0), (0, -1, 0.5)), k=0.004)
    line.sub(opening, k=0.004)
    parts.append(hog)

    # ================================================================== bras (épaule) + avant-bras (coude)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        sh_p = (sx * SH[0], SH[1], SH[2])
        el = (sx * EL[0], EL[1], EL[2])
        hd_p = (sx * HAND[0], HAND[1], HAND[2])
        arm = Part("arm_" + nm, pivot=sh_p, parent="torso", res=0.0042)
        slv = arm.piece(HOOD, tris=T(260))
        slv.add(capsule(add(sh_p, (sx * 0.004, -0.01, 0)), el, 0.047, 0.043))
        parts.append(arm)
        fore = Part("fore_" + nm, pivot=el, parent="arm_" + nm, res=0.0042)
        cuff = fore.piece(HOOD, tris=T(180))
        cuff.add(capsule(el, add(el, ((hd_p[0] - el[0]) * 0.35, (hd_p[1] - el[1]) * 0.35, (hd_p[2] - el[2]) * 0.35)), 0.043, 0.042))
        fore.piece(HOOD_D, tris=T(110)).add(cyl(add(el, ((hd_p[0] - el[0]) * 0.36, (hd_p[1] - el[1]) * 0.36, (hd_p[2] - el[2]) * 0.36)), 0.043, 0.012, 0.006, rot=(0, 0, sx * 8)))
        fa = fore.piece(SHELL, tris=T(200))
        fa.add(capsule(add(el, (0, -0.03, 0)), add(hd_p, (0, 0.03, 0)), 0.03, 0.032))
        # main : paume et trois doigts (pour taper)
        hand = fore.piece(DARK, tris=T(300), res=0.0035)
        hand.add(ellipsoid(add(hd_p, (0, -0.012, 0.004)), (0.03, 0.032, 0.026)))
        for i, dz in enumerate((-0.013, 0.004, 0.02)):
            hand.add(capsule(add(hd_p, (0, -0.03, dz)), add(hd_p, (sx * 0.004, -0.062, dz + 0.004)), 0.0085, 0.0075), k=0.008)
        hand.add(capsule(add(hd_p, (-sx * 0.015, -0.01, 0.022)), add(hd_p, (-sx * 0.02, -0.036, 0.04)), 0.009), k=0.008)
        if nm == "l":
            # ordinateur de poignet : boîtier sombre, écran sur le dessus (côté extérieur)
            wc = fore.piece(DARK, tris=T(200))
            wc.add(rbox(add(hd_p, (0.004, 0.048, 0.0)), (0.036, 0.024, 0.04), 0.01))
            fore.piece(trim if elite else JOINT, tris=T(80)).add(cyl(add(hd_p, (0, 0.022, 0)), 0.035, 0.007, 0.003))
        parts.append(fore)
    wg = Part("wrist_glow", pivot=(HAND[0], HAND[1], HAND[2]), parent="fore_l", res=0.0025)
    wgs = wg.piece(ACID, tris=T(100))
    wgs.add(rbox((HAND[0] + 0.04, HAND[1] + 0.048, HAND[2]), (0.004, 0.016, 0.03), 0.003))
    wgs.paint(slab((0, HAND[1] + 0.052, 0), (0, 1, 0), 0.002), HOLO_MID)
    parts.append(wg)

    # ================================================================== hologramme (écran + clavier)
    holo = Part("holo_glow", pivot=HOLO, parent="torso", res=0.0028)
    R = rot_matrix(HOLO_TILT, 0, 0)
    up = R @ np.array([0.0, 1.0, 0.0])
    fw = R @ np.array([0.0, 0.0, 1.0])
    hc = np.asarray(HOLO)
    panel = rbox(HOLO, (0.16, 0.1, 0.003), 0.006, rot=(HOLO_TILT, 0, 0))
    fill = holo.piece(HOLO_DIM, tris=T(120))
    fill.add(panel)
    frame = holo.piece(ACID, tris=T(220))
    frame.add(inter(shell(rbox(HOLO, (0.16, 0.1, 0.02), 0.012, rot=(HOLO_TILT, 0, 0)), 0.0, -0.007), grow(panel, 0.0015)))
    # lignes de « code » (longueurs variées) et un cadenas ouvert stylisé
    code = holo.piece(ACID, tris=T(320))
    lens_ = (0.09, 0.06, 0.11, 0.04, 0.08, 0.07)
    for i, ln in enumerate(lens_):
        y = 0.068 - i * 0.024
        c0 = hc + up * y + fw * 0.002 + np.array([-0.13 + ln * 0.6, 0, 0])
        code.add(rbox(c0.tolist(), (ln * 0.6, 0.0045, 0.0035), 0.002, rot=(HOLO_TILT, 0, 0)))
    lock_c = hc + up * 0.005 + fw * 0.002 + np.array([0.095, 0, 0])
    code.add(rbox((lock_c - up * 0.012).tolist(), (0.022, 0.017, 0.004), 0.004, rot=(HOLO_TILT, 0, 0)))
    code.add(inter(torus((lock_c + up * 0.012 + np.array([0.008, 0, 0])).tolist(), 0.014, 0.0035, rot=(HOLO_TILT + 90, 0, 0)),
                   side((lock_c + up * 0.012).tolist(), up)))
    # clavier flottant sous l'écran, presque à plat
    kc = hc + np.array((0.0, -0.08, -0.1))  # sous l'écran, côté pirate
    kb = rbox(kc.tolist(), (0.12, 0.003, 0.045), 0.005, rot=(-8, 0, 0))
    holo.piece(HOLO_DIM, tris=T(80)).add(kb)
    keys = holo.piece(HOLO_MID, tris=T(320))
    for row in range(3):
        for col in range(7):
            p0 = kc + np.array([-0.09 + col * 0.03, 0.004, -0.028 + row * 0.028])
            keys.add(rbox(p0.tolist(), (0.011, 0.002, 0.009), 0.002, rot=(-8, 0, 0)))
    parts.append(holo)

    # ================================================================== jambes (hanche) + tibias (genou, basket)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        hip = (sx * HIP_X, HIP_Y, 0.0)
        kn = (sx * (HIP_X + 0.006), KNEE_Y, 0.008)
        an = (sx * (HIP_X + 0.008), ANKLE_Y, -0.004)
        leg = Part("leg_" + nm, pivot=hip, parent="pelvis", res=0.0042)
        lp = leg.piece(PANTS, tris=T(260))
        lp.add(capsule(hip, kn, 0.068, 0.058))
        pocket = leg.piece(PANTS_D, tris=T(140))
        pocket.add(rbox(add(hip, (sx * 0.054, -0.1, 0.004)), (0.016, 0.04, 0.034), 0.012))
        parts.append(leg)
        shin = Part("shin_" + nm, pivot=kn, parent="leg_" + nm, res=0.0042)
        sp = shin.piece(PANTS, tris=T(240))
        sp.add(capsule(kn, add(an, (0, 0.025, 0)), 0.057, 0.05))
        shin.piece(PANTS_D, tris=T(90)).add(ellipsoid(add(kn, (0, -0.012, 0.048)), (0.036, 0.042, 0.016), rot=(-8, 0, 0)))  # pièce au genou
        shin.piece(PANTS_D, tris=T(110)).add(torus(add(an, (0, 0.045, 0)), 0.05, 0.013))  # revers
        # basket épaisse
        shoe_sh = rbox((an[0], 0.05, 0.032), (0.05, 0.044, 0.088), 0.038, rot=(-4, 0, 0))
        sh = shin.piece(SHELL, tris=T(380))
        sh.add(shoe_sh)
        sh.add(cyl((an[0], 0.085, -0.008), 0.044, 0.025, 0.012), k=0.02)
        sh.paint(slab((an[0], 0.012, 0), (0, 1, 0), 0.013), SHELL_M)  # semelle
        sh.paint(inter(grow(shoe_sh, 0.003), rbox((an[0], 0.088, 0.05), (0.024, 0.02, 0.05), 0.006)), ACID_P)  # lacets
        sh.paint(slab((an[0], 0.06, 0.04), (1, 0, -0.25), 0.006), HOOD)  # virgule violette
        parts.append(shin)
    return Character("hacker_elite" if elite else "hacker", parts)
