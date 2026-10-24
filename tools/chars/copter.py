"""Gyro (code « copter ») : petit drone de police de la Cité Néon, mignon, qui tourne autour de Jo en
balayant le sol de son projecteur.
Coque en galet bleu police (#3C8CFF) à ceinture blanche et ventre bleu nuit, frimousse d'écran sombre à deux
grands yeux lumineux, rampe de gyrophares rouge et bleu sur le dessus, insigne inventé (écusson blanc à
étoile bleue) sur le capot, quatre rotors carénés blancs aux coins (vus du dessus : un « X » qui ne ressemble
ni à la Sentinelle ronde ni au Pétard roulant), gros projecteur sur cardan sous le ventre, petit canon double
sous le nez, antenne à l'arrière.
Regarde vers +Z ; sa droite est en -X. Corps centré à y = 0,9 (il vole) ; ~0,75 de large rotors compris,
~0,49 de haut du projecteur au gyrophare (de y = 0,62 à 1,12).

Parts (pivots) : body (racine, centre du corps) > face_glow (yeux), siren_r_glow (rouge, à droite),
siren_b_glow (bleu, à gauche), rotor_fr, rotor_fl, rotor_br, rotor_bl (moyeux ; pales dans le plan XZ,
tournent autour de Y), lamp (cardan sous le ventre, tourne autour de Y) > lamp_glow (lentille),
gun (support sous le nez) > muzzle_glow (bouches).
Variante élite (build(elite=True), tools/chars/copter_elite.py) : casquette de capitaine à visière et
insigne or (détail de silhouette), écusson, liserés des carénages et antennes dorés, deux antennes.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import *  # noqa: E402,F403
from sniper import Part, union, inter, grow, side, slab, add  # noqa: E402  (pièces à normales lisses, outils)

BLUE = "#3C8CFF"     # bleu police, couleur signature
BLUE_D = "#2A64C8"   # bleu ombré (flancs bas)
WHITE = "#EEF2FA"
WHITE_D = "#C8CEDC"
NAVY = "#1C2238"
NAVY_M = "#2C3350"
JOINT = "#454E70"
GLASS = "#0D1226"    # écran de la frimousse
EYE = "#BFE6FF"      # yeux : blanc bleuté (énergie ~1)
RED = "#FF1030"      # gyrophare rouge (saturé : reste rouge une fois lumineux)
SIREN_B = "#2A6BFF"  # gyrophare bleu (plus saturé que la coque : reste bleu une fois lumineux)
LENS = "#D8ECFF"     # lentille du projecteur
MUZZLE = "#5AA8FF"
GOLD = "#FFB347"
GOLD_D = "#C9842A"

BIG = 50.0
C = (0.0, 0.9, 0.0)  # centre du corps
ROTOR_X = 0.245
ROTOR_Z = 0.17
ROTOR_Y = 0.935
DUCT_R = 0.1  # rayon intérieur du carénage
LAMP_P = (0.0, 0.775, -0.01)  # pivot du cardan du projecteur
GUN_P = (0.0, 0.82, 0.135)  # support du canon
TRI = 0.66  # facteur global du budget de triangles (~7 000)


def at(x, y, z):
    return [C[0] + x, C[1] + y, C[2] + z]


def prism_y(f2, c):
    """Prisme vertical (axe Y) de section f2(u, v) (u selon X, v selon Z, autour de c)."""
    return Shape(lambda P: f2(P[:, 0] - c[0], P[:, 2] - c[2]), np.full(3, -BIG), np.full(3, BIG))


def box2(u, v, hu, hv, r):
    qu = np.abs(u) - (hu - r)
    qv = np.abs(v) - (hv - r)
    return np.hypot(np.maximum(qu, 0), np.maximum(qv, 0)) + np.minimum(np.maximum(qu, qv), 0) - r


def star2(u, v, r, n=5, m=2.6):
    """Étoile à n branches (Quilez), pointe vers +v."""
    an = math.pi / n
    en = math.pi / m
    acs = np.array([math.cos(an), math.sin(an)])
    ecs = np.array([math.cos(en), math.sin(en)])
    x = np.abs(u)
    y = v
    bn = np.mod(np.arctan2(x, y), 2 * an) - an
    L = np.hypot(x, y)
    px = L * np.cos(bn) - r * acs[0]
    py = L * np.abs(np.sin(bn)) - r * acs[1]
    h = np.clip(-(px * ecs[0] + py * ecs[1]), 0.0, r * acs[1] / ecs[1])
    px = px + ecs[0] * h
    py = py + ecs[1] * h
    return np.hypot(px, py) * np.sign(px)


def shield2(u, v, s):
    """Écusson : haut plat (vers -v), pointe arrondie vers +v."""
    top = box2(u, v + 0.25 * s, 0.82 * s, 0.55 * s, 0.18 * s)
    c, sn = math.cos(math.pi / 4), math.sin(math.pi / 4)
    ru = (u * c - (v - 0.15 * s) * sn)
    rv = (u * sn + (v - 0.15 * s) * c)
    tip = box2(ru, rv, 0.6 * s, 0.6 * s, 0.15 * s)
    k = 0.12 * s
    h = np.clip(0.5 + 0.5 * (tip - top) / k, 0, 1)
    return tip * (1 - h) + top * h - k * h * (1 - h)


def build(elite=False):
    name = "copter_elite" if elite else "copter"
    q = 0.9 if elite else 1.0  # l'élite porte une casquette : même budget total

    def T(n):
        return max(50, int(n * q * TRI))

    TRIM = GOLD if elite else WHITE  # liserés des carénages
    BADGE = GOLD if elite else WHITE
    parts = []

    # ================================================================== corps (racine, pivot au centre)
    body = Part("body", pivot=C, res=0.0045)
    pod = union([
        ellipsoid(at(0, 0.0, 0.0), (0.155, 0.118, 0.178)),
        rbox(at(0, -0.01, -0.01), (0.14, 0.085, 0.15), 0.08),
        ellipsoid(at(0, 0.045, -0.02), (0.13, 0.08, 0.14)),
    ], k=0.04)
    pod_top = body.piece(BLUE, tris=T(900))
    pod_top.add(pod)
    pod_top.sub(side(at(0, -0.012, 0), (0, -1, 0)), k=0.004)
    # écran de la frimousse creusé dans le nez (incliné vers le haut : se lit de la caméra haute)
    face_c = at(0, 0.015, 0.155)
    face = rbox(face_c, (0.092, 0.064, 0.036), 0.03, rot=(-28, 0, 0))
    pod_top.sub(grow(face, 0.008), k=0.01)
    # ceinture blanche (livrée de police) et ventre bleu nuit
    belt = body.piece(WHITE, tris=T(520))
    belt.add(inter(grow(pod, 0.006), slab(at(0, -0.022, 0), (0, 1, 0), 0.024)))
    belt.sub(grow(face, 0.012), k=0.01)
    belly = body.piece(NAVY_M, tris=T(420))
    belly.add(inter(grow(pod, -0.002), side(at(0, -0.04, 0), (0, -1, 0))))
    body.piece(GLASS, tris=T(260)).add(face)
    # cerclage de l'écran
    body.piece(NAVY, tris=T(260)).add(inter(grow(face, 0.012), side((np.array(face_c) + np.array([0, 0, -0.01])).tolist(), (0, 0.47, 0.88))))
    # insigne sur le capot : écusson et étoile (pointe vers l'avant)
    bc = at(0, 0.11, 0.03)
    badge = body.piece(BADGE, tris=T(300), res=0.0032)
    badge.add(inter(grow(pod, 0.005), prism_y(lambda u, v: shield2(u, v, 0.062), bc)))
    star = body.piece(GOLD_D if elite else BLUE_D, tris=T(260), res=0.0028)
    star.add(inter(grow(pod, 0.008), prism_y(lambda u, v: star2(u, v + 0.005, 0.032), bc)))
    # rampe de gyrophares (support sombre, capots des lampes)
    bar_c = at(0, 0.122, -0.075)
    bar = body.piece(NAVY_M, tris=T(320))
    bar.add(rbox(bar_c, (0.135, 0.024, 0.04), 0.02))
    bar.add(rbox(add(bar_c, (0, -0.022, 0)), (0.07, 0.022, 0.03), 0.015), k=0.02)
    body.piece(GOLD if elite else WHITE_D, tris=T(160)).add(rbox(add(bar_c, (0, 0.006, 0)), (0.022, 0.026, 0.036), 0.012))
    # bras vers les carénages
    arms = body.piece(NAVY_M, tris=T(420))
    for sx in (-1, 1):
        for sz in (-1, 1):
            arms.add(capsule(at(sx * 0.09, 0.0, sz * 0.07), [sx * ROTOR_X * 0.8, ROTOR_Y - 0.005, sz * ROTOR_Z * 0.8], 0.032, 0.022))
    # carénages : anneaux blancs, lèvre intérieure sombre, croisillon sous l'hélice
    duct = body.piece(WHITE, tris=T(900))
    lip = body.piece(NAVY, tris=T(520))
    trim = body.piece(TRIM if elite else BLUE, tris=T(380), res=0.0035)
    for sx in (-1, 1):
        for sz in (-1, 1):
            dc = [sx * ROTOR_X, ROTOR_Y, sz * ROTOR_Z]
            ring = cyl(dc, DUCT_R + 0.03, 0.026, 0.014)
            duct.add(ring)
            duct.sub(cyl(dc, DUCT_R + 0.004, 0.06, 0.0))
            lip.add(cyl(dc, DUCT_R + 0.008, 0.02, 0.006))
            lip.sub(cyl(dc, DUCT_R - 0.004, 0.06, 0.0))
            lip.add(capsule(add(dc, (-0.09, -0.018, 0)), add(dc, (0.09, -0.018, 0)), 0.008))
            lip.add(capsule(add(dc, (0, -0.018, -0.09)), add(dc, (0, -0.018, 0.09)), 0.008))
            lip.add(cyl(add(dc, (0, -0.012, 0)), 0.02, 0.012, 0.005))
            # liseré sur le dessus du carénage (vu du dessus)
            trim.add(inter(torus(add(dc, (0, 0.026, 0)), DUCT_R + 0.017, 0.007), side(add(dc, (0, 0.02, 0)), (0, 1, 0))))
    # antenne(s) à l'arrière
    ant = body.piece(NAVY_M, tris=T(200))
    tips = body.piece(GOLD if elite else RED, tris=T(120))
    xs = (-0.05, 0.05) if elite else (0.06,)
    for x in xs:
        ant.add(capsule(at(x, 0.07, -0.14), at(x * 1.4, 0.2, -0.22), 0.009, 0.006))
        tips.add(sphere(at(x * 1.4, 0.2, -0.22), 0.016))
    # feux de position latéraux (petits capots) et anneau du cardan sous le ventre
    body.piece(NAVY, tris=T(200)).add(cyl(at(0, -0.105, -0.01), 0.052, 0.014, 0.007))
    if elite:
        # casquette de capitaine sur le dessus du crâne : calotte, bandeau doré, visière, insigne or
        cap_c = at(0, 0.13, 0.04)
        crown = union([
            ellipsoid(add(cap_c, (0, 0.035, -0.005)), (0.105, 0.04, 0.1)),
            cyl(add(cap_c, (0, 0.005, 0)), 0.088, 0.026, 0.012),
        ], k=0.02)
        body.piece(NAVY, tris=T(420)).add(crown)
        body.piece(GOLD, tris=T(240)).add(cyl(add(cap_c, (0, 0.006, 0)), 0.091, 0.012, 0.005))
        visor = inter(ellipsoid(add(cap_c, (0, -0.012, 0.07)), (0.09, 0.016, 0.07), rot=(-12, 0, 0)), side(add(cap_c, (0, 0, 0.04)), (0, 0, 1)))
        body.piece(GLASS, tris=T(200)).add(visor)
        body.piece(GOLD, tris=T(220), res=0.003).add(inter(grow(crown, 0.005), prism_y(lambda u, v: star2(u, -(v - 0.0), 0.024), add(cap_c, (0, 0, 0.085)))))
    parts.append(body)

    # yeux : deux pilules lumineuses dans l'écran
    fg = Part("face_glow", pivot=face_c, parent="body", res=0.0025)
    eyes = fg.piece(EYE, tris=T(260))
    fd = np.array([0.0, math.sin(math.radians(28)), math.cos(math.radians(28))])
    for sx in (-1, 1):
        ec = np.array(face_c) + np.array([sx * 0.042, 0.004, 0]) + fd * 0.034
        eyes.add(ellipsoid(ec.tolist(), (0.025, 0.033, 0.009), rot=(-28, 0, sx * 6)))
    parts.append(fg)

    # gyrophares (deux parts : clignotent en alternance)
    for nm, sx, col in (("siren_r_glow", -1, RED), ("siren_b_glow", 1, SIREN_B)):
        lc = add(bar_c, (sx * 0.08, 0.02, 0))
        sp = Part(nm, pivot=lc, parent="body", res=0.003)
        dome = sp.piece(col, tris=T(240))
        dome.add(inter(ellipsoid(lc, (0.058, 0.048, 0.044)), side(add(lc, (0, -0.004, 0)), (0, 1, 0))))
        parts.append(sp)

    # hélices (moyeu + trois pales vrillées), une part par rotor
    for nm, sx, sz in (("rotor_fr", -1, 1), ("rotor_fl", 1, 1), ("rotor_br", -1, -1), ("rotor_bl", 1, -1)):
        dc = [sx * ROTOR_X, ROTOR_Y, sz * ROTOR_Z]
        rp = Part(nm, pivot=dc, parent="body", res=0.0035)
        blades = rp.piece(NAVY_M, tris=T(220))
        blades.add(cyl(add(dc, (0, 0.002, 0)), 0.022, 0.014, 0.008))
        for k in range(3):
            a = k * 120.0 + (0 if sx * sz > 0 else 60.0)
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            bcx = [dc[0] + ca * 0.055, dc[1], dc[2] + sa * 0.055]
            blades.add(rbox(bcx, (0.05, 0.004, 0.017), 0.004, rot=(sx * 14, -a, 0)), k=0.006)
        tipc = rp.piece(WHITE_D, tris=T(90))
        for k in range(3):
            a = k * 120.0 + (0 if sx * sz > 0 else 60.0)
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            tipc.add(rbox([dc[0] + ca * 0.088, dc[1], dc[2] + sa * 0.088], (0.011, 0.0055, 0.018), 0.004, rot=(sx * 14, -a, 0)))
        parts.append(rp)

    # projecteur : cardan en U sous le ventre, gros phare incliné vers l'avant et le bas
    lamp = Part("lamp", pivot=LAMP_P, parent="body", res=0.0035)
    L_AX = (128.0, 0, 0)  # axe du phare : Y local basculé de 128° -> regarde vers le bas-avant (ld)
    ld = np.array([0.0, -math.cos(math.radians(52)), math.sin(math.radians(52))])  # direction du faisceau
    lc = np.array([0.0, 0.715, 0.0])
    yoke = lamp.piece(NAVY_M, tris=T(360))
    yoke.add(cyl(add(LAMP_P, (0, 0.005, 0)), 0.036, 0.012, 0.006))
    for sx in (-1, 1):
        yoke.add(capsule(add(LAMP_P, (sx * 0.02, 0, 0)), [sx * 0.085, 0.745, 0.0], 0.012), k=0.01)
        yoke.add(capsule([sx * 0.085, 0.745, 0.0], [sx * 0.085, 0.715, 0.0], 0.012), k=0.01)
        yoke.add(cyl([sx * 0.082, 0.715, 0.0], 0.018, 0.008, 0.004, rot=(0, 0, 90)))
    house = lamp.piece(WHITE, tris=T(520))
    hs = cyl(lc.tolist(), 0.07, 0.055, 0.02, rot=L_AX)
    house.add(hs)
    house.add(sphere((lc - ld * 0.03).tolist(), 0.06), k=0.02)
    house.sub(cyl((lc + ld * 0.055).tolist(), 0.056, 0.02, 0.006, rot=L_AX), k=0.004)
    rim = lamp.piece(GOLD if elite else NAVY, tris=T(300))
    rim.add(inter(torus((lc + ld * 0.05).tolist(), 0.064, 0.011, rot=L_AX), side((lc + ld * 0.035).tolist(), ld)))
    # ailettes de refroidissement à l'arrière du phare
    fins = lamp.piece(NAVY_M, tris=T(200))
    for k in (0, 1, 2):
        fins.add(inter(slab((lc - ld * (0.05 + 0.017 * k)).tolist(), ld, 0.0045), cyl((lc - ld * 0.05).tolist(), 0.05 - 0.007 * k, 0.04, 0.01, rot=L_AX)))
    parts.append(lamp)
    lg = Part("lamp_glow", pivot=(lc + ld * 0.05).tolist(), parent="lamp", res=0.003)
    lens = lg.piece(LENS, tris=T(200))
    lens.add(cyl((lc + ld * 0.046).tolist(), 0.054, 0.008, 0.006, rot=L_AX))
    parts.append(lg)

    # canon double sous le nez
    gun = Part("gun", pivot=GUN_P, parent="body", res=0.003)
    gb = gun.piece(NAVY_M, tris=T(360))
    gb.add(ellipsoid(add(GUN_P, (0, -0.012, 0.0)), (0.045, 0.03, 0.045)))
    gb.add(rbox(add(GUN_P, (0, -0.02, 0.045)), (0.04, 0.018, 0.03), 0.014), k=0.012)
    br = gun.piece(WHITE_D if not elite else GOLD, tris=T(260))
    for sx in (-1, 1):
        br.add(cyl(add(GUN_P, (sx * 0.02, -0.022, 0.1)), 0.011, 0.04, 0.005, rot=(90, 0, 0)))
        br.sub(cyl(add(GUN_P, (sx * 0.02, -0.022, 0.14)), 0.006, 0.012, 0.0, rot=(90, 0, 0)))
    gun.piece(NAVY, tris=T(120)).add(cyl(add(GUN_P, (0, -0.022, 0.075)), 0.034, 0.007, 0.004, rot=(90, 0, 0)))
    parts.append(gun)
    mg = Part("muzzle_glow", pivot=add(GUN_P, (0, -0.022, 0.14)), parent="gun", res=0.0025)
    mz = mg.piece(MUZZLE, tris=T(90))
    for sx in (-1, 1):
        mz.add(cyl(add(GUN_P, (sx * 0.02, -0.022, 0.134)), 0.0065, 0.006, 0.002, rot=(90, 0, 0)))
    parts.append(mg)
    return Character(name, parts)
