"""Mortier (code « mortar ») : petit robot d'artillerie de la sécurité de la station.
Châssis trapu en galet arrondi (dessus vert citron, ventre sombre, plaques claires sur les flancs, pare-chocs à
bandes de danger), petite tête-capteur à l'avant (visière sombre, deux grands yeux vert citron, casquette
vert citron), quatre pattes courtes et écartées à semelles rondes, et sur le dos une tourelle qui porte un GROS
tube de mortier trapu (bague de danger, bouche évasée vert citron).
Regarde vers +Z ; sa droite est en -X. Largeur ~0,85 (pattes comprises), hauteur ~0,85 (tube couché).

Parts (pivots) : body (racine, centre du châssis) > head (cou) > head_glow (yeux) ; body > body_glow
(voyants), tube (tourillons ; axe du tube vers +Y au repos, le script le couche ou le lève autour de X)
> muzzle_glow (bouche) ; body > leg_fr, leg_fl, leg_br, leg_bl (hanches).
Variante élite (build(elite=True), tools/chars/mortar_elite.py) : bouche toujours vert citron (signature),
yeux et voyants or, plaques dorées (or franc, loin du vert), couronne de pointes dorées autour de la tourelle, cornes sur la tête.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import *  # noqa: E402,F403
from sniper import Part, union, inter, grow, side, slab, add  # noqa: E402  (pièces à normales lisses, outils)

HULL = "#C8CEDC"
HULL_M = "#9AA4B6"
METAL = "#2C3350"
METAL_D = "#1C2238"
JOINT = "#454E70"
HAZ = "#FFC83A"   # plaques jaunes
HAZ_D = "#E0A21E"
LIME = "#7AD03A"  # lueur vert citron (énergie ~1 : rendu proche de #9BE15D, sans virer au jaune)
LIME_RIM = "#4E9E1C"
LIME_HULL = "#86C83A"  # coque vert citron : le dessus du châssis (la signature vue du dessus, tube couché ou levé)
LIME_HULL_D = "#5E9A22"
PUPIL = "#0C1A08"
WHITE = "#FFFFFF"
GOLD = "#FF8410"     # lueur or (rendu proche de #FFA41C)
GOLD_P = "#EE8530"   # or franc des élites : loin du vert du châssis
GOLD_D = "#B05A12"

# repères partagés avec scripts/mobs/mortar.gd
BC = (0.0, 0.34, 0.0)  # centre du châssis (pivot racine)
TRUN = (0.0, 0.6, -0.075)  # tourillons du tube
TUBE_L = 0.3  # des tourillons à la bouche
NECK = (0.0, 0.36, 0.2)
HIPS = {"fr": (-1, 1), "fl": (1, 1), "br": (-1, -1), "bl": (1, -1)}
HIP_X, HIP_Y, HIP_Z = 0.2, 0.27, 0.16
FOOT_X, FOOT_Z = 0.33, 0.225
TRI = 0.84


def helix(c, n, pitch, frac=0.5):
    """Bandes obliques enroulées autour de l'axe Y passant par c (n bandes par tour)."""
    c = np.asarray(c, dtype=np.float64)

    def f(P):
        Q = P - c
        th = np.arctan2(Q[:, 2], Q[:, 0])
        r = np.maximum(np.linalg.norm(Q[:, [0, 2]], axis=1), 1e-3)
        u = th * n / (2 * np.pi) + Q[:, 1] / pitch
        fr = u - np.floor(u)
        grad = np.sqrt((n / (2 * np.pi * r)) ** 2 + (1.0 / pitch) ** 2)
        return (np.abs(fr - 0.5) - frac * 0.5) / grad
    return Shape(f, c - 5, c + 5)


def onsurf(sh, p, out=0.0):
    """Point p ramené sur la surface de sh (pas de Newton le long du gradient), puis décalé de `out`."""
    q = np.asarray(p, dtype=np.float64)[None, :]
    e = 1e-4
    for _ in range(12):
        d = sh(q)
        g = np.stack([sh(q + np.eye(3)[i] * e) - sh(q - np.eye(3)[i] * e) for i in range(3)], axis=1) / (2 * e)
        g /= np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
        q = q - d[:, None] * g
    return (q[0] + g[0] * out).tolist()


def stripes(dirv, period, frac=0.5):
    nv = np.asarray(dirv, dtype=np.float64)
    nv = nv / np.linalg.norm(nv)

    def f(P):
        u = (P @ nv) / period
        fr = u - np.floor(u)
        return (np.abs(fr - 0.5) - frac * 0.5) * period
    return Shape(f, np.full(3, -5.0), np.full(3, 5.0))


def build(elite=False):
    q = 0.84 if elite else 1.0

    def T(n):
        return max(50, int(n * q * TRI))

    plate_col = GOLD_P if elite else HULL
    glow2 = GOLD if elite else LIME  # yeux et voyants (la bouche reste vert citron)
    rim2 = GOLD_D if elite else LIME_RIM
    trim = GOLD_P if elite else HULL_M
    parts = []
    tx, ty, tz = TRUN

    # ================================================================== châssis (racine)
    body = Part("body", pivot=BC, res=0.006)
    shell_sh = union([
        rbox((0, 0.37, -0.01), (0.265, 0.12, 0.27), 0.115),
        ellipsoid((0, 0.4, -0.01), (0.28, 0.14, 0.285)),
    ], k=0.05)
    belly = body.piece(METAL, tris=T(380))
    belly.add(ellipsoid((0, 0.28, -0.01), (0.235, 0.1, 0.245)))
    belly.add(cyl((0, 0.31, -0.01), 0.262, 0.035, 0.02), k=0.03)
    top = body.piece(LIME_HULL, tris=T(1000))
    top.add(shell_sh)
    top.sub(side((0, 0.315, 0), (0, -1, 0)), k=0.01)
    # plaques claires (or pour l'élite) sur les flancs (épousent la coque), deux rivets chacune
    pl = body.piece(plate_col, tris=T(500), res=0.005)
    riv = body.piece(METAL_D, tris=T(120), res=0.004)
    for sx in (-1, 1):
        pl.add(inter(grow(shell_sh, 0.01), rbox((sx * 0.27, 0.425, -0.02), (0.08, 0.068, 0.17), 0.04)))
        for zz in (-0.13, 0.09):
            riv.add(sphere(onsurf(shell_sh, (sx * 0.3, 0.43, zz), 0.008), 0.014))
    # pare-chocs avant à bandes de danger (sous la tête)
    bump_sh = capsule((-0.17, 0.27, 0.235), (0.17, 0.27, 0.235), 0.04)
    body.piece(GOLD_P if elite else HAZ, tris=T(220), res=0.005).add(bump_sh)
    body.piece(METAL_D, tris=T(420), res=0.0035).add(inter(grow(bump_sh, 0.007), stripes((1, 1, 0), 0.07)))
    # tourelle : bague sombre, joues qui portent les tourillons
    tur = body.piece(METAL, tris=T(420))
    tur.add(cyl((tx, 0.5, tz), 0.19, 0.04, 0.025))
    tur.add(torus((tx, 0.535, tz), 0.18, 0.025), k=0.01)
    cheeks = body.piece(HULL_M, tris=T(320))
    for sx in (-1, 1):
        cheeks.add(rbox((sx * 0.163, ty - 0.025, tz), (0.028, 0.08, 0.08), 0.024))
    pins = body.piece(JOINT, tris=T(140))
    for sx in (-1, 1):
        pins.add(cyl((sx * 0.196, ty, tz), 0.036, 0.012, 0.006, rot=(0, 0, 90)))
    lamp = body.piece(METAL, tris=T(140), res=0.004)
    for sx in (-1, 1):
        lamp.add(ellipsoid(onsurf(shell_sh, (sx * 0.13, 0.6, 0.17), -0.006), (0.042, 0.014, 0.042), rot=(35, 0, 0)))  # socles des lampes
    # dos : grille d'aération
    gr = body.piece(METAL_D, tris=T(160))
    gr.add(inter(grow(shell_sh, 0.006), rbox((0, 0.4, -0.29), (0.09, 0.04, 0.05), 0.03)))
    if elite:
        # couronne de pointes dorées autour de la tourelle
        crown = body.piece(GOLD_P, tris=T(520), res=0.004)
        for i in range(8):
            a = 2 * math.pi * (i + 0.5) / 8
            ca, sa = math.cos(a), math.sin(a)
            p0 = (tx + 0.19 * ca, 0.52, tz + 0.19 * sa)
            p1 = (tx + 0.26 * ca, 0.6, tz + 0.26 * sa)
            crown.add(capsule(p0, p1, 0.026, 0.006))
        crown.add(cyl((tx, 0.52, tz), 0.203, 0.012, 0.006), k=0.01)
    parts.append(body)

    bg = Part("body_glow", pivot=BC, parent="body", res=0.0035)
    leds = bg.piece(glow2, tris=T(160))
    grill = inter(grow(shell_sh, 0.006), rbox((0, 0.4, -0.29), (0.09, 0.04, 0.05), 0.03))
    for dx in (-0.045, 0.0, 0.045):
        leds.add(sphere(onsurf(grill, (dx, 0.4, -0.35), 0.002), 0.013))  # voyants dorsaux
    for sx in (-1, 1):
        for zz in (0.1, 0.15):
            leds.add(sphere(onsurf(shell_sh, (sx * 0.35, 0.43, zz), 0.002), 0.011))  # feux latéraux
        leds.add(ellipsoid(onsurf(shell_sh, (sx * 0.13, 0.6, 0.17), -0.002), (0.03, 0.02, 0.03), rot=(35, 0, 0)))  # lampes du dessus
    parts.append(bg)

    # ================================================================== tête-capteur (pivot au cou)
    head = Part("head", pivot=NECK, parent="body", res=0.004)
    tilt = (-20, 0, 0)  # la face regarde un peu vers le haut (lisible depuis la caméra haute)
    hc = (0, 0.4, 0.262)
    pod = head.piece(METAL, tris=T(380))
    pod.add(rbox(hc, (0.155, 0.08, 0.075), 0.06, rot=tilt))
    pod.add(cyl((0, 0.37, 0.215), 0.06, 0.04, 0.02), k=0.02)  # cou
    # visière de casquette claire au-dessus des yeux (sourcils)
    cap = head.piece(LIME_HULL, tris=T(300))
    cap_sh = ellipsoid((0, 0.472, 0.3), (0.162, 0.03, 0.078), rot=(-16, 0, 0))
    cap.add(cap_sh)
    capst = head.piece(plate_col, tris=T(140), res=0.0035)
    capst.add(inter(grow(cap_sh, 0.004), slab((0, 0, 0), (1, 0, 0), 0.024)))
    # visière : fond sombre où se logent les yeux
    R = rot_matrix(*tilt)
    fwd = R @ np.array([0.0, 0.0, 1.0])
    upv = R @ np.array([0.0, 1.0, 0.0])
    face = np.asarray(hc) + fwd * 0.075
    vis = head.piece(METAL_D, tris=T(240))
    vis.add(rbox((face - fwd * 0.01).tolist(), (0.13, 0.055, 0.016), 0.014, rot=tilt))
    ears = head.piece(trim, tris=T(160))
    for sx in (-1, 1):
        ears.add(cyl((sx * 0.158, 0.4, 0.255), 0.04, 0.014, 0.007, rot=(0, 0, 90)))
    if elite:
        horns = head.piece(GOLD_P, tris=T(300), res=0.0035)
        for sx in (-1, 1):
            horns.add(capsule((sx * 0.12, 0.48, 0.24), (sx * 0.2, 0.57, 0.2), 0.026, 0.008))
    parts.append(head)

    hg = Part("head_glow", pivot=NECK, parent="head", res=0.0028)
    eyes = hg.piece(rim2, tris=T(260))
    pup = hg.piece(PUPIL, tris=T(120))
    glint = hg.piece(WHITE, tris=T(80))
    for sx in (-1, 1):
        ec = face + np.array([sx * 0.062, 0, 0]) + upv * 0.004
        eyes.add(ellipsoid(ec.tolist(), (0.042, 0.042, 0.016), rot=tilt))
        eyes.paint(ellipsoid((ec + fwd * 0.01).tolist(), (0.031, 0.031, 0.02), rot=tilt), glow2)
        pup.add(ellipsoid((ec + fwd * 0.012 - upv * 0.004).tolist(), (0.016, 0.017, 0.008), rot=tilt))
        glint.add(sphere((ec + fwd * 0.014 + upv * 0.016 + np.array([0.012, 0, 0])).tolist(), 0.0075))
    parts.append(hg)

    # ================================================================== tube de mortier (tourillons, axe +Y)
    tube = Part("tube", pivot=TRUN, parent="body", res=0.0045)
    my = ty + TUBE_L
    TR = 0.112  # rayon du tube (gros et trapu)
    brl = tube.piece(METAL, tris=T(420))
    brl.add(capsule((tx, ty - 0.07, tz), (tx, my - 0.03, tz), TR - 0.006, TR))
    bore_sh = cyl((tx, my, tz), TR - 0.03, 0.1, 0.004)  # âme
    brl.sub(bore_sh, k=0.006)
    breech = tube.piece(HULL_M, tris=T(300))
    breech.add(ellipsoid((tx, ty - 0.075, tz), (TR + 0.014, 0.085, TR + 0.014)))
    breech.add(cyl((tx, ty, tz), TR + 0.016, 0.05, 0.022), k=0.02)  # manchon des tourillons
    sl = tube.piece(LIME_HULL, tris=T(300))
    sl.add(cyl((tx, ty + 0.105, tz), TR + 0.01, 0.045, 0.022))  # frette claire
    hz = tube.piece(plate_col, tris=T(220))
    hz.add(cyl((tx, my - 0.075, tz), TR + 0.008, 0.03, 0.01))
    hz.sub(bore_sh, k=0.004)
    hzs = tube.piece(METAL_D, tris=T(280), res=0.0035)
    hzs.add(inter(cyl((tx, my - 0.075, tz), TR + 0.012, 0.032, 0.01), helix((tx, 0, tz), 14, 0.5)))
    hzs.sub(cyl((tx, my, tz), TR - 0.01, 0.12, 0.004))
    mouth = tube.piece(METAL_D, tris=T(320))
    mouth.add(cyl((tx, my - 0.02, tz), TR + 0.032, 0.028, 0.015))
    mouth.add(torus((tx, my, tz), TR + 0.012, 0.02), k=0.01)
    mouth.sub(bore_sh, k=0.006)
    parts.append(tube)

    mg = Part("muzzle_glow", pivot=(tx, my, tz), parent="tube", res=0.003)
    bore = mg.piece(LIME, tris=T(170))
    bore.add(cyl((tx, my - 0.06, tz), TR - 0.028, 0.008, 0.003))  # fond de l'âme
    bore.add(torus((tx, my - 0.03, tz), TR - 0.028, 0.006), k=0.004)  # anneau de chargement
    mg.piece(LIME_RIM, tris=T(150)).add(cyl((tx, my - 0.047, tz), TR + 0.006, 0.007, 0.003))  # fente lumineuse sous la bouche
    parts.append(mg)

    # ================================================================== pattes (hanches)
    for nm, (sx, sz) in HIPS.items():
        hip = (sx * HIP_X, HIP_Y, sz * HIP_Z)
        foot = (sx * FOOT_X, 0.05, sz * FOOT_Z)
        knee = add(hip, ((foot[0] - hip[0]) * 0.75, -0.1, (foot[2] - hip[2]) * 0.7))
        leg = Part("leg_" + nm, pivot=hip, parent="body", res=0.0045)
        leg.piece(JOINT, tris=T(80)).add(sphere(hip, 0.066))
        lg = leg.piece(METAL, tris=T(170))
        lg.add(capsule(hip, knee, 0.058, 0.054))
        lg.add(capsule(knee, foot, 0.054, 0.05), k=0.02)
        guard = leg.piece(HULL_M, tris=T(150))
        guard.add(ellipsoid(add(knee, (sx * 0.014, 0.01, sz * 0.008)), (0.068, 0.06, 0.066)))
        leg.piece(plate_col, tris=T(80)).add(cyl(add(foot, (0, 0.034, 0)), 0.06, 0.013, 0.006))  # bague de cheville
        pad = leg.piece(METAL_D, tris=T(150))
        pad.add(cyl((foot[0], 0.026, foot[2]), 0.086, 0.026, 0.015))
        leg.piece(HULL, tris=T(100)).add(ellipsoid((foot[0], 0.042, foot[2] + 0.045), (0.07, 0.032, 0.05)))  # coque d'orteil
        parts.append(leg)
    return Character("mortar_elite" if elite else "mortar", parts)
