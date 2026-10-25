"""Équipement visible de Jo (loot). Un GLB par objet : assets/chars3d/gear_<id>.glb.
Chaque part s'appelle « <cible>__<id> » : le rig la range dans la part cible de Jo (head, torso, arm_l, arm_r,
leg_r, leg_l, gun) avec le même pivot, donc les coordonnées ci-dessous sont celles du modèle de Jo
(ancienne Jo, tools/chars/jo.py retiré : Jo regarde vers +Z, sa droite est en -X, sa gauche en +X). Sur la nouvelle Jo
(tools/blender/jo.py), scripts/rig3d.gd GEAR_FIT ajuste chaque cible (tête plus petite, bras et jambes plus longs).
Les parts « *_glow » sont blanches : le jeu les teinte à la couleur de rareté.

Chaque objet doit se reconnaître seul, en icône de 96 px (silhouette d'abord : fer à cheval, pile à barres,
lunette à réticule, blouson à col fourré...) et rester lisible porté par Jo vue d'en haut (~70 px).
Deux familles en plus de l'équipement de garde : Nébuleuse 7 (fret spatial : bleu acier, orange, rayures
de quai Hélix Fret) et Cité Néon (cyberpunk mignon : rose #FF3CAC, bleu #3C8CFF, violet nuit).

python3 tools/sculpt.py gear              tous les objets
GEAR_ONLY=pile,aimant python3 tools/sculpt.py gear   seulement ceux-là"""
import math
import os

from sculpt import *

PIV = {"torso": (0, 0.36, 0), "head": (0, 0.62, 0), "arm_l": (0.19, 0.57, 0), "arm_r": (-0.19, 0.57, 0),
       "leg_r": (-0.08, 0.34, 0), "leg_l": (0.08, 0.34, 0), "gun": (-0.215, 0.33, 0.014)}
W = "#FFFFFF"
NAVY = "#1E2A4A"
STEEL = "#8A94A8"
LIGHT = "#E8ECF2"
ORANGE = "#FF7A2F"
ORANGE_D = "#D9561C"
GUNC = "#3A4258"
GUNL = "#5A6478"
DARK = "#262C40"
# Nébuleuse 7 : livrée Hélix Fret
STEELB = "#4F6D96"
STEELB_D = "#34496B"
CLAW = "#C9D2E0"
# Cité Néon
PINK = "#FF3CAC"
PINK_L = "#FF8ACB"
BLUE = "#3C8CFF"
NIGHT = "#2E2452"
PEARL = "#F4F0FF"
# veste de pilote
LEATHER = "#8B5A3C"
LEATHER_D = "#5E3B28"
FLEECE = "#F1E3C8"
MAG_RED = "#E5484D"


def part(target, gid, glow=False, res=0.005):
    return Part(target + "__" + gid + ("_glow" if glow else ""), pivot=PIV[target], res=res)


def axis_of(rot):
    """Direction de l'axe Y d'une forme tournée de `rot` (cyl, torus) dans le repère du modèle."""
    return rot_matrix(*rot) @ np.array([0.0, 1.0, 0.0])


def helix(pc, c, r, h, turns, wire, seg=12):
    """Ressort à boudin d'axe Y (centre c, rayon r, hauteur h) en petites capsules."""
    n = int(turns * seg)
    pts = []
    for i in range(n + 1):
        t = i / n
        a = t * turns * math.tau
        pts.append((c[0] + r * math.cos(a), c[1] - h * 0.5 + h * t, c[2] + r * math.sin(a)))
    for a, b in zip(pts, pts[1:]):
        pc.add(capsule(a, b, wire))


def shell_band(pc, c, radii, grow, y0, y1):
    """Bande horizontale (y0..y1) posée sur un ellipsoïde : l'ellipsoïde un peu grossi, coupé dessus et dessous."""
    pc.add(ellipsoid(c, tuple(r + grow for r in radii)))
    pc.sub(rbox((c[0], y1 + 0.2, c[2]), (0.5, 0.2, 0.5), 0.0))
    pc.sub(rbox((c[0], y0 - 0.2, c[2]), (0.5, 0.2, 0.5), 0.0))


def tail_bands(pc, pts, r, ts):
    """Rayures sur un pan en capsules (points pts) : courts manchons de rayon r aux abscisses ts (0..1)."""
    P = [np.array(p, dtype=float) for p in pts]
    L = [np.linalg.norm(b - a) for a, b in zip(P, P[1:])]
    tot = sum(L)
    for t in ts:
        d = t * tot
        for i, l in enumerate(L):
            if d <= l or i == len(L) - 1:
                u = (P[i + 1] - P[i]) / l
                m = P[i] + u * min(d, l)
                pc.add(capsule(tuple(m - u * 0.008), tuple(m + u * 0.008), r))
                break
            d -= l


# ------------------------------------------------------------------ tête
def visiere():
    # visée de pilote : bras depuis l'oreille droite, lentille devant l'œil droit
    a = part("head", "visiere")
    a.piece(DARK, tris=300).add(capsule((-0.262, 0.84, 0.02), (-0.2, 0.86, 0.17), 0.014))
    a.piece(STEEL, tris=300).add(cyl((-0.1, 0.845, 0.215), 0.06, 0.016, 0.008, rot=(90, 0, 0)))
    g = part("head", "visiere", glow=True, res=0.004)
    g.piece(W, tris=200).add(cyl((-0.1, 0.845, 0.226), 0.046, 0.006, 0.003, rot=(90, 0, 0)))
    return [a, g]


def casque_garde():
    a = part("head", "casque_garde", res=0.006)
    dome = a.piece(LIGHT, tris=1500)
    # assez ample pour couvrir la mèche turquoise qui gonfle sur le crâne (les lunettes sont masquées)
    dome.add(ellipsoid((0, 0.91, -0.03), (0.276, 0.24, 0.268)))
    dome.add(ellipsoid((0, 0.985, 0.12), (0.215, 0.095, 0.15)), k=0.05)  # avancée sur la frange
    dome.sub(rbox((0, 0.765, 0.21), (0.19, 0.13, 0.14), 0.07), k=0.02)
    dome.sub(ellipsoid((0, 0.885, -0.03), (0.254, 0.218, 0.246)))
    a.piece(NAVY, tris=300).add(rbox((0, 1.13, -0.02), (0.035, 0.04, 0.17), 0.03))
    g = part("head", "casque_garde", glow=True)
    g.piece(W, tris=300).add(torus((0, 0.905, 0.175), 0.13, 0.012, rot=(90, 0, 0)))
    return [a, g]


def casque_docker():
    """Casque de chantier de quai (N7) : coque orange à arête, bandeau Hélix bleu acier, visière avant,
    lampe frontale lumineuse. Posé plus haut que le casque de garde : les yeux restent dégagés."""
    a = part("head", "casque_docker", res=0.005)
    dome = a.piece(ORANGE, tris=1500)
    dome.add(ellipsoid((0, 0.955, -0.03), (0.268, 0.215, 0.262)))
    dome.sub(rbox((0, 0.76, 0.0), (0.4, 0.17, 0.4), 0.0))
    a.piece(ORANGE_D, tris=400).add(rbox((0, 1.15, -0.03), (0.034, 0.04, 0.218), 0.03))  # arête centrale
    # bandeau Hélix et filet réfléchissant : volumes à part (une peinture s'effrange une fois allégée)
    shell_band(a.piece(STEELB, tris=600), (0, 0.955, -0.03), (0.268, 0.215, 0.262), 0.004, 0.936, 0.976)
    shell_band(a.piece(LIGHT, tris=400), (0, 0.955, -0.03), (0.268, 0.215, 0.262), 0.007, 0.952, 0.961)
    brim = a.piece(ORANGE_D, tris=700)
    brim.add(ellipsoid((0, 0.932, 0.025), (0.284, 0.016, 0.3)))  # rebord, visière plus longue devant
    lamp = a.piece(GUNC, tris=300)
    lamp.add(cyl((0, 1.03, 0.252), 0.046, 0.024, 0.01, rot=(78, 0, 0)))
    g = part("head", "casque_docker", glow=True, res=0.004)
    g.piece(W, tris=200).add(cyl((0, 1.035, 0.276), 0.034, 0.006, 0.003, rot=(78, 0, 0)))
    return [a, g]


def oreilles_chat():
    """Casque audio à oreilles de chat (Cité Néon) : arceau bleu nuit, écouteurs roses, oreilles dressées
    à intérieur lumineux, anneau lumineux sur chaque écouteur."""
    a = part("head", "oreilles_chat", res=0.0045)
    band = a.piece(NIGHT, tris=600)
    band.add(torus((0, 0.84, -0.04), 0.296, 0.02, rot=(90, 0, 0)))
    band.sub(rbox((0, 0.64, -0.04), (0.4, 0.22, 0.2), 0.0))
    cups = a.piece(PINK, tris=900)
    plates = a.piece(BLUE, tris=300)
    for sx in (-1.0, 1.0):
        cups.add(cyl((sx * 0.285, 0.83, -0.01), 0.078, 0.034, 0.016, rot=(0, 0, 90)))
        plates.add(cyl((sx * 0.322, 0.83, -0.01), 0.046, 0.006, 0.004, rot=(0, 0, 90)))
    ears = a.piece(PINK, tris=700)
    for sx in (-1.0, 1.0):
        ears.add(capsule((sx * 0.165, 1.075, -0.04), (sx * 0.245, 1.215, -0.04), 0.06, 0.012))
    ears.sub(rbox((0, 1.15, 0.04), (0.4, 0.2, 0.04), 0.0))
    ears.sub(rbox((0, 1.15, -0.12), (0.4, 0.2, 0.04), 0.0))
    g = part("head", "oreilles_chat", glow=True, res=0.004)
    gp = g.piece(W, tris=500)
    for sx in (-1.0, 1.0):
        gp.add(capsule((sx * 0.178, 1.09, -0.002), (sx * 0.232, 1.188, -0.002), 0.034, 0.008))
        gp.add(torus((sx * 0.322, 0.83, -0.01), 0.058, 0.009, rot=(0, 0, 90)))
    gp.sub(rbox((0, 1.15, 0.046), (0.4, 0.2, 0.04), 0.0))
    gp.sub(rbox((0, 1.15, -0.05), (0.4, 0.2, 0.04), 0.0))
    return [a, g]


# ------------------------------------------------------------------ torse
def plastron():
    a = part("torso", "plastron")
    a.piece(STEEL, tris=600).add(rbox((0, 0.495, 0.112), (0.13, 0.085, 0.036), 0.03))
    a.piece(DARK, tris=200).add(rbox((0, 0.44, 0.146), (0.05, 0.02, 0.008), 0.008))
    g = part("torso", "plastron", glow=True)
    gg = g.piece(W, tris=200)
    gg.add(rbox((0, 0.548, 0.146), (0.11, 0.008, 0.006), 0.004))
    return [a, g]


SHELL_C = (0, 0.47, 0.0)
SHELL_R = (0.18, 0.165, 0.158)  # assez bombée devant pour couvrir la plaque orange et son voyant


def _shell(pc, grow=0.0):
    """Coque de vêtement fermée autour du torse de Jo (creuse, ouverte au cou et en bas)."""
    pc.add(ellipsoid(SHELL_C, tuple(r + grow for r in SHELL_R)))
    pc.add(ellipsoid((0, 0.395, 0.0), (0.165 + grow, 0.06, 0.14 + grow)), k=0.04)
    pc.add(ellipsoid((0, 0.56, -0.005), (0.172 + grow, 0.07, 0.14 + grow)), k=0.04)
    pc.sub(ellipsoid((0, 0.47, 0.0), (0.166, 0.153, 0.14)))
    pc.sub(ellipsoid((0, 0.56, -0.005), (0.157, 0.062, 0.125)))
    pc.sub(rbox((0, 0.25, 0.0), (0.3, 0.1, 0.3), 0.0))  # ourlet à la ceinture
    pc.sub(cyl((0, 0.64, 0.0), 0.086, 0.05, 0.0))  # encolure


def veste():
    """Blouson d'aviateur : cuir brun fermé par une glissière, col fourré crème à revers, poches en biais,
    bord-côtes et poignets de cuir foncé, insigne d'ailes lumineux sur le cœur."""
    out = []
    a = part("torso", "veste", res=0.0045)
    _shell(a.piece(LEATHER, tris=1800))
    rib = a.piece(LEATHER_D, tris=600)
    shell_band(rib, (0, 0.395, 0.0), (0.165, 0.06, 0.14), 0.006, 0.345, 0.372)
    rib.sub(ellipsoid((0, 0.395, 0.0), (0.15, 0.1, 0.125)))
    trim = a.piece(DARK, tris=400)
    zip_pts = [(0, 0.355, 0.142), (0, 0.42, 0.158), (0, 0.5, 0.161), (0, 0.575, 0.142)]
    for p0, p1 in zip(zip_pts, zip_pts[1:]):
        trim.add(capsule(p0, p1, 0.0055))
    for sx in (-1.0, 1.0):  # poches passepoilées en biais
        trim.add(capsule((sx * 0.06, 0.4, 0.152), (sx * 0.115, 0.43, 0.128), 0.006))
    collar = a.piece(FLEECE, tris=1200)
    # col fourré relevé derrière et sur les côtés, ouvert devant ; revers en bandes qui dessinent un V
    collar.add(torus((0, 0.615, -0.015), 0.106, 0.034, rot=(-8, 0, 0)))
    collar.sub(rbox((0, 0.62, 0.16), (0.07, 0.08, 0.08), 0.02))
    for sx in (-1.0, 1.0):
        collar.add(ellipsoid((sx * 0.052, 0.57, 0.148), (0.02, 0.062, 0.011), rot=(-24, 0, sx * 32)), k=0.01)
    collar.sub(cyl((0, 0.66, 0.0), 0.07, 0.06, 0.0))
    out.append(a)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        s = part("arm_" + side, "veste", res=0.0045)
        s.piece(LEATHER, tris=500).add(capsule((sx * 0.2, 0.555, 0), (sx * 0.213, 0.43, 0.008), 0.061, 0.056))
        s.piece(LEATHER_D, tris=300).add(cyl((sx * 0.214, 0.418, 0.008), 0.058, 0.016, 0.008))
        out.append(s)
    g = part("torso", "veste", glow=True, res=0.003)
    gp = g.piece(W, tris=500)
    # insigne d'ailes sur le cœur (gauche de Jo, +X), posé sur la coque
    cx, cy, cz = 0.085, 0.5, 0.15
    gp.add(sphere((cx, cy, cz + 0.004), 0.012))
    for sx in (-1.0, 1.0):
        gp.add(ellipsoid((cx + sx * 0.03, cy + 0.005, cz - 0.004), (0.028, 0.009, 0.007), rot=(0, sx * -22, sx * 12)))
        gp.add(ellipsoid((cx + sx * 0.025, cy - 0.009, cz - 0.003), (0.019, 0.007, 0.006), rot=(0, sx * -22, sx * 4)))
    out.append(g)
    return out


def gilet_fret():
    """Gilet de manutention Hélix Fret (N7) : bleu acier, deux bandes orange à filet argent, glissière,
    poches de poitrine à rabat orange d'où dépassent des cellules d'énergie lumineuses."""
    a = part("torso", "gilet_fret", res=0.0045)
    _shell(a.piece(STEELB, tris=1800))
    for y in (0.425, 0.505):
        shell_band(a.piece(ORANGE, tris=500), SHELL_C, SHELL_R, 0.004, y - 0.018, y + 0.018)
        shell_band(a.piece(LIGHT, tris=300), SHELL_C, SHELL_R, 0.007, y - 0.0045, y + 0.0045)
    trim = a.piece(STEELB_D, tris=500)
    for sx in (-1.0, 1.0):  # bordure du col en V
        trim.add(capsule((sx * 0.07, 0.625, 0.07), (0.0, 0.565, 0.153), 0.008))
    zip_pts = [(0, 0.355, 0.142), (0, 0.42, 0.158), (0, 0.5, 0.161), (0, 0.575, 0.142)]
    for p0, p1 in zip(zip_pts, zip_pts[1:]):
        trim.add(capsule(p0, p1, 0.0065))
    pockets = a.piece(STEELB_D, tris=500)
    flaps = a.piece(ORANGE, tris=300)
    for sx in (-1.0, 1.0):
        pockets.add(rbox((sx * 0.072, 0.565, 0.13), (0.036, 0.032, 0.02), 0.01, rot=(-20, 0, 0)))
        flaps.add(rbox((sx * 0.072, 0.592, 0.142), (0.038, 0.009, 0.02), 0.006, rot=(-20, 0, 0)))
    g = part("torso", "gilet_fret", glow=True, res=0.0035)
    gp = g.piece(W, tris=400)
    for sx in (-1.0, 1.0):
        for dx in (-0.017, 0.0, 0.017):
            gp.add(capsule((sx * 0.072 + dx, 0.595, 0.136), (sx * 0.072 + dx, 0.625, 0.128), 0.0085))
    return [a, g]


def echarpe():
    """Écharpe fétiche (Cité Néon) : grosse écharpe rose rayée de bleu, nouée devant, un pan sur la poitrine,
    l'autre qui flotte au vent derrière le sac ; franges lumineuses au bout des pans."""
    a = part("torso", "echarpe", res=0.0045)
    wrap = a.piece(PINK, tris=1200)
    wrap.add(torus((0, 0.606, -0.004), 0.097, 0.04, rot=(10, 0, 0)))
    knot = a.piece(BLUE, tris=300)
    knot.add(ellipsoid((0.055, 0.585, 0.12), (0.04, 0.034, 0.028)))
    tails = a.piece(PINK, tris=1400)
    stripes = a.piece(BLUE, tris=900)
    # pan avant : tombe sur la poitrine, un peu de biais (devant la plaque orange)
    front = [(0.06, 0.57, 0.15), (0.075, 0.5, 0.17), (0.07, 0.43, 0.172)]
    for p0, p1 in zip(front, front[1:]):
        tails.add(capsule(p0, p1, 0.026), k=0.02)
    tail_bands(stripes, front, 0.0285, (0.3, 0.6, 0.86))
    # pan arrière : passe au-dessus du sac et ondule au vent
    back = [(0.0, 0.62, -0.09), (0.03, 0.66, -0.2), (0.075, 0.64, -0.3), (0.115, 0.665, -0.39)]
    for p0, p1 in zip(back, back[1:]):
        tails.add(capsule(p0, p1, 0.028), k=0.02)
    tail_bands(stripes, back, 0.0305, (0.3, 0.52, 0.74, 0.94))
    g = part("torso", "echarpe", glow=True, res=0.0035)
    gp = g.piece(W, tris=500)
    for dx in (-0.016, 0.0, 0.016):
        gp.add(capsule((0.07 + dx, 0.41, 0.173), (0.07 + dx * 1.3, 0.385, 0.175), 0.006))
    for dy in (-0.018, 0.0, 0.018):
        gp.add(capsule((0.12, 0.665 + dy, -0.405), (0.128, 0.668 + dy * 1.3, -0.43), 0.006))
    return [a, g]


# ------------------------------------------------------------------ jambes
def legs(gid, col, y_band):
    out = []
    for side, sx in (("r", -1.0), ("l", 1.0)):
        a = part("leg_" + side, gid)
        g = part("leg_" + side, gid, glow=True)
        if gid == "bottes":
            a.piece(col, tris=600).add(rbox((sx * 0.085, 0.075, 0.03), (0.078, 0.07, 0.11), 0.05))
            g.piece(W, tris=200).add(cyl((sx * 0.085, y_band, 0.03), 0.082, 0.012, 0.005))
        out += [a, g]
    return out


def jambieres():
    """Jambières de garde : coque de tibia bleu acier en trois lames qui se chevauchent, genouillère bleu nuit
    en pointe (profil en losange) coiffée d'une arête claire, sangles derrière ; filet lumineux vertical.
    (Ni boule blanche ni point : l'ancienne version, deux ovales clairs à point lumineux, faisait des yeux.)"""
    out = []
    for side, sx in (("r", -1.0), ("l", 1.0)):
        x = sx * 0.084
        a = part("leg_" + side, "jambieres", res=0.004)
        shin = a.piece("#41557C", tris=1000)
        for yc, k in ((0.255, 1.0), (0.205, 0.97), (0.155, 0.93)):
            shin.add(ellipsoid((x, yc, 0.012), (0.074 * k, 0.034, 0.075 * k)))
            shin.add(ellipsoid((x, yc - 0.012, 0.012), (0.07 * k, 0.03, 0.071 * k)))
        shin.sub(ellipsoid((x, 0.205, 0.0), (0.061, 0.14, 0.063)))
        shin.sub(rbox((x, 0.2, -0.065), (0.1, 0.2, 0.05), 0.0))  # ouverte derrière
        straps = a.piece(NAVY, tris=300)
        for y in (0.175, 0.24):
            straps.add(cyl((x, y, 0.0), 0.065, 0.008, 0.004))
        knee = a.piece(NAVY, tris=500)
        knee.add(rbox((x, 0.305, 0.05), (0.05, 0.036, 0.036), 0.012, rot=(45, 0, 0)))
        a.piece(STEEL, tris=300).add(capsule((x, 0.33, 0.06), (x, 0.305, 0.1), 0.009))
        g = part("leg_" + side, "jambieres", glow=True, res=0.0035)
        g.piece(W, tris=200).add(capsule((x, 0.262, 0.086), (x, 0.15, 0.084), 0.0055))
        out += [a, g]
    return out


def amortisseurs():
    """Amortisseurs de soute (N7) : sur l'extérieur de chaque jambe, un gros ressort orange entre deux
    colliers bleu acier, tige de piston au centre ; voyant lumineux sur chaque collier."""
    out = []
    for side, sx in (("r", -1.0), ("l", 1.0)):
        x = sx * 0.158
        a = part("leg_" + side, "amortisseurs", res=0.0035)
        cuffs = a.piece(STEELB, tris=700)
        for y in (0.115, 0.3):
            cuffs.add(cyl((sx * 0.084, y, 0.0), 0.07, 0.016, 0.008))
            cuffs.add(rbox((x - sx * 0.02, y, 0.0), (0.028, 0.016, 0.026), 0.01))
        rod = a.piece(GUNL, tris=200)
        rod.add(capsule((x, 0.12, 0.0), (x, 0.295, 0.0), 0.009))
        spring = a.piece(ORANGE, tris=1400)
        helix(spring, (x, 0.207, 0.0), 0.031, 0.155, 4.5, 0.009)
        g = part("leg_" + side, "amortisseurs", glow=True, res=0.003)
        gp = g.piece(W, tris=150)
        for y in (0.115, 0.3):
            gp.add(rbox((x + sx * 0.008, y, 0.0), (0.004, 0.008, 0.016), 0.003))
        out += [a, g]
    return out


def patins():
    """Patins néon (Cité Néon) : bottine rose à revers bleu, platine, quatre roues lumineuses de chaque côté
    du pied (sur le sol, pas dessous), butée avant."""
    out = []
    for side, sx in (("r", -1.0), ("l", 1.0)):
        x = sx * 0.085
        a = part("leg_" + side, "patins", res=0.004)
        boot = a.piece(PINK, tris=800)
        boot.add(rbox((x, 0.082, 0.026), (0.077, 0.074, 0.11), 0.05))
        boot.paint(rbox((x, 0.082, 0.14), (0.02, 0.06, 0.03), 0.0), PEARL)  # languette
        a.piece(BLUE, tris=300).add(cyl((x, 0.148, 0.0), 0.072, 0.016, 0.008))
        a.piece(GUNC, tris=300).add(rbox((x, 0.03, 0.028), (0.05, 0.014, 0.11), 0.008))
        hubs = a.piece(DARK, tris=400)
        for wx in (-1.0, 1.0):
            for wz in (-0.055, 0.105):
                hubs.add(cyl((x + wx * 0.083, 0.032, wz), 0.013, 0.013, 0.004, rot=(0, 0, 90)))
        a.piece(BLUE, tris=200).add(sphere((x, 0.03, 0.155), 0.026))
        g = part("leg_" + side, "patins", glow=True, res=0.0035)
        gp = g.piece(W, tris=600)
        for wx in (-1.0, 1.0):
            for wz in (-0.055, 0.105):
                gp.add(cyl((x + wx * 0.077, 0.032, wz), 0.032, 0.011, 0.006, rot=(0, 0, 90)))
        out += [a, g]
    return out


# ------------------------------------------------------------------ dos (gadgets)
# posés sur le panneau arrière du sac (z = -0.235), entre les deux réacteurs ; ils dépassent du haut du sac
# (y = 0.61) pour se voir d'en haut.
def pile():
    """Pile de secours : batterie rectangulaire sombre à borne, capot orange, trois barres de charge."""
    a = part("torso", "pile", res=0.004)
    case = a.piece(DARK, tris=600)
    case.add(rbox((0, 0.53, -0.275), (0.066, 0.105, 0.032), 0.018))
    case.paint(rbox((0, 0.62, -0.275), (0.1, 0.016, 0.1), 0.0), ORANGE)
    a.piece(STEEL, tris=200).add(cyl((0, 0.643, -0.275), 0.026, 0.014, 0.005))
    a.piece(GUNL, tris=300).add(rbox((0, 0.5, -0.252), (0.05, 0.05, 0.02), 0.01))  # fixation
    g = part("torso", "pile", glow=True, res=0.0035)
    gp = g.piece(W, tris=300)
    for y in (0.455, 0.51, 0.565):
        gp.add(rbox((0, y, -0.306), (0.046, 0.019, 0.004), 0.004))
    return [a, g]


def aimant():
    """Aimant à ferraille : gros fer à cheval rouge dressé sur le sac, pointes d'acier lumineuses."""
    a = part("torso", "aimant", res=0.0045)
    c = (0.0, 0.535, -0.29)
    body = a.piece(MAG_RED, tris=1000)
    body.add(torus(c, 0.072, 0.03, rot=(90, 0, 0)))
    body.sub(rbox((0, c[1] + 0.1, c[2]), (0.2, 0.1, 0.1), 0.0))
    for sx in (-1.0, 1.0):
        body.add(cyl((sx * 0.072, c[1] + 0.055, c[2]), 0.03, 0.055, 0.004))
    a.piece(GUNL, tris=300).add(rbox((0, 0.49, -0.252), (0.04, 0.03, 0.022), 0.01))
    g = part("torso", "aimant", glow=True, res=0.004)
    gp = g.piece(W, tris=300)
    for sx in (-1.0, 1.0):
        gp.add(cyl((sx * 0.072, c[1] + 0.13, c[2]), 0.031, 0.02, 0.006))
    return [a, g]


def reservoir():
    """Réservoir à plasma (N7) : deux bouteilles bleu acier sanglées, robinets orange reliés par un tube,
    hublot de plasma lumineux sur chaque bouteille."""
    a = part("torso", "reservoir", res=0.0045)
    tanks = a.piece(STEELB, tris=1000)
    for sx in (-1.0, 1.0):
        tanks.add(capsule((sx * 0.056, 0.43, -0.29), (sx * 0.056, 0.62, -0.29), 0.046))
    straps = a.piece(DARK, tris=300)
    for y in (0.47, 0.585):
        straps.add(rbox((0, y, -0.29), (0.108, 0.011, 0.05), 0.006))
    caps = a.piece(ORANGE, tris=400)
    for sx in (-1.0, 1.0):
        caps.add(cyl((sx * 0.056, 0.675, -0.29), 0.022, 0.014, 0.005))
    a.piece(GUNL, tris=300).add(torus((0, 0.69, -0.29), 0.056, 0.009, rot=(90, 0, 0))).sub(
        rbox((0, 0.64, -0.29), (0.1, 0.05, 0.05), 0.0))
    g = part("torso", "reservoir", glow=True, res=0.0035)
    gp = g.piece(W, tris=300)
    for sx in (-1.0, 1.0):
        gp.add(capsule((sx * 0.056, 0.49, -0.335), (sx * 0.056, 0.565, -0.335), 0.011))
    return [a, g]


def ailes():
    """Petites ailes (Cité Néon) : deux ailes mécaniques en éventail sur le sac, plumes nacre, rose et bleu,
    longeron néon lumineux sur le bord d'attaque."""
    a = part("torso", "ailes", res=0.004)
    hub = a.piece(NIGHT, tris=300)
    hub.add(rbox((0, 0.565, -0.255), (0.07, 0.03, 0.022), 0.012))
    feathers = a.piece(PEARL, tris=1600)
    glow_pts = []
    for sx in (-1.0, 1.0):
        root = np.array([sx * 0.06, 0.57, -0.272])
        for i, (ang, L) in enumerate(((40, 0.3), (20, 0.28), (0, 0.24), (-20, 0.19))):
            ar = math.radians(ang)
            d = np.array([sx * math.cos(ar), math.sin(ar), -0.12])
            d /= np.linalg.norm(d)
            cen = root + d * L * 0.5
            rot = (0, sx * 7, sx * ang)
            feathers.add(ellipsoid(tuple(cen), (L * 0.5, 0.042, 0.011), rot=rot))
            col = PINK if i % 2 == 1 else BLUE
            feathers.paint(sphere(tuple(root + d * L * 0.88), L * 0.16), col)
            if i == 0:
                glow_pts.append((root, d, L))
        hub.add(sphere(tuple(root), 0.024))
    g = part("torso", "ailes", glow=True, res=0.0035)
    gp = g.piece(W, tris=300)
    for root, d, L in glow_pts:
        up = np.array([0.0, 0.026, 0.0])
        gp.add(capsule(tuple(root + d * 0.03 + up), tuple(root + d * L * 0.93 + up * 0.4), 0.006))
    return [a, g]


# ------------------------------------------------------------------ épaule gauche (module)
# posés sur l'épaulière orange (centre (0.222, 0.598, 0), rayons 0.094 / 0.07 / 0.09)
def module_canon():
    a = part("arm_l", "module_canon")
    g = part("arm_l", "module_canon", glow=True)
    a.piece(GUNC, tris=500).add(rbox((0.235, 0.69, 0.02), (0.04, 0.035, 0.07), 0.025))
    a.piece(GUNL, tris=300).add(cyl((0.235, 0.69, 0.1), 0.02, 0.04, 0.006, rot=(90, 0, 0)))
    g.piece(W, tris=100).add(cyl((0.235, 0.69, 0.14), 0.014, 0.006, 0.002, rot=(90, 0, 0)))
    return [a, g]


def cellule():
    """Cellule de visée : grosse lunette de tir sur l'épaule (tube, objectif évasé, tourelles de réglage),
    réticule holographique lumineux (cercle et croix) projeté devant."""
    a = part("arm_l", "cellule", res=0.0035)
    y, x = 0.726, 0.245
    a.piece(GUNL, tris=300).add(rbox((x, 0.682, 0.0), (0.034, 0.02, 0.05), 0.008))  # embase
    tube = a.piece(GUNC, tris=900)
    tube.add(cyl((x, y, 0.0), 0.029, 0.095, 0.008, rot=(90, 0, 0)))
    tube.add(capsule((x, y, 0.075), (x, y, 0.12), 0.034, 0.048), k=0.012)  # objectif
    tube.add(capsule((x, y, -0.075), (x, y, -0.108), 0.031, 0.04), k=0.012)  # oculaire
    tube.sub(cyl((x, y, 0.132), 0.038, 0.014, 0.0, rot=(90, 0, 0)))
    knobs = a.piece(ORANGE, tris=300)
    knobs.add(cyl((x, y + 0.038, 0.0), 0.018, 0.014, 0.005))
    knobs.add(cyl((x + 0.038, y, 0.0), 0.018, 0.014, 0.005, rot=(0, 0, 90)))
    g = part("arm_l", "cellule", glow=True, res=0.003)
    gp = g.piece(W, tris=600)
    gp.add(cyl((x, y, 0.121), 0.036, 0.004, 0.002, rot=(90, 0, 0)))  # lentille
    rz = 0.2
    gp.add(torus((x, y, rz), 0.056, 0.0055, rot=(90, 0, 0)))
    gp.add(rbox((x, y, rz), (0.0035, 0.04, 0.0035), 0.002))
    gp.add(rbox((x, y, rz), (0.04, 0.0035, 0.0035), 0.002))
    return [a, g]


def pince():
    """Pince de fret (N7) : petit bras articulé bleu acier qui se dresse de l'épaule, coudes orange,
    pince à trois doigts tournée vers l'avant, voyants lumineux au poignet."""
    a = part("arm_l", "pince", res=0.004)
    base, elbow, wrist = (0.27, 0.675, -0.025), (0.33, 0.79, -0.05), (0.33, 0.805, 0.06)
    arm = a.piece(STEELB, tris=600)
    arm.add(capsule(base, elbow, 0.019))
    arm.add(capsule(elbow, wrist, 0.017))
    joints = a.piece(ORANGE, tris=500)
    joints.add(cyl(base, 0.03, 0.013, 0.006))
    joints.add(sphere(elbow, 0.029))
    joints.add(cyl((wrist[0], wrist[1], wrist[2] + 0.006), 0.027, 0.012, 0.005, rot=(90, 0, 0)))
    fingers = a.piece(CLAW, tris=700)
    w = np.array(wrist) + np.array([0, 0, 0.018])
    for ang in (90, 210, 330):
        d = np.array([math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0.0])
        k = w + d * 0.034 + np.array([0, 0, 0.03])
        tip = w + d * 0.016 + np.array([0, 0, 0.068])
        fingers.add(capsule(tuple(w + d * 0.012), tuple(k), 0.0095))
        fingers.add(capsule(tuple(k), tuple(tip), 0.009, 0.005))
    g = part("arm_l", "pince", glow=True, res=0.0035)
    g.piece(W, tris=200).add(torus((wrist[0], wrist[1], wrist[2] - 0.006), 0.026, 0.006, rot=(90, 0, 0)))
    return [a, g]


def antenne():
    """Antenne pirate (Cité Néon) : parabole nacrée à bord rose sur un mât, tournée vers le ciel et l'avant,
    source bleue, boule lumineuse au bout."""
    a = part("arm_l", "antenne", res=0.004)
    rot = (32, 0, -28)
    n = axis_of(rot)
    c = np.array([0.31, 0.77, -0.035])
    a.piece(NIGHT, tris=300).add(capsule((0.27, 0.665, -0.02), tuple(c - n * 0.02), 0.012))
    a.piece(NIGHT, tris=200).add(cyl((0.27, 0.668, -0.02), 0.026, 0.01, 0.004))
    dish = a.piece(PEARL, tris=900)
    dish.add(cyl(tuple(c), 0.074, 0.012, 0.006, rot=rot))
    dish.sub(sphere(tuple(c + n * 0.215), 0.21))
    a.piece(PINK, tris=500).add(torus(tuple(c + n * 0.006), 0.074, 0.01, rot=rot))
    a.piece(BLUE, tris=200).add(capsule(tuple(c), tuple(c + n * 0.075), 0.006))
    g = part("arm_l", "antenne", glow=True, res=0.003)
    g.piece(W, tris=200).add(sphere(tuple(c + n * 0.085), 0.015))
    return [a, g]


# ------------------------------------------------------------------ armes
def gun(gid):
    # même convention que le blaster de Jo : canon vers -Y au repos, poignée dans le gant
    a = part("gun", gid)
    g = part("gun", gid, glow=True, res=0.004)
    if gid == "blaster_garde":
        a.piece(GUNC, tris=600).add(rbox((-0.215, 0.26, 0.064), (0.04, 0.11, 0.055), 0.02))
        a.piece("#9AA4B6", tris=300).add(rbox((-0.215, 0.29, 0.122), (0.03, 0.05, 0.014), 0.01))
        a.piece(GUNL, tris=300).add(cyl((-0.215, 0.14, 0.074), 0.026, 0.05, 0.008))
        g.piece(W, tris=150).add(cyl((-0.215, 0.087, 0.074), 0.019, 0.008, 0.003))
        g.piece(W, tris=100).add(rbox((-0.257, 0.25, 0.064), (0.004, 0.06, 0.02), 0.003))
    else:
        a.piece(GUNC, tris=700).add(rbox((-0.215, 0.24, 0.064), (0.034, 0.14, 0.046), 0.022))
        a.piece(GUNL, tris=300).add(cyl((-0.215, 0.085, 0.07), 0.022, 0.04, 0.008))
        a.piece(ORANGE, tris=200).add(rbox((-0.215, 0.33, 0.04), (0.024, 0.03, 0.04), 0.015))
        gg = g.piece(W, tris=400)
        for y in (0.16, 0.21, 0.26):
            gg.add(torus((-0.215, y, 0.064), 0.05, 0.008))
        gg.add(cyl((-0.215, 0.042, 0.07), 0.016, 0.008, 0.003))
    return [a, g]


def riveteuse():
    """Riveteuse de quai (N7) : corps trapu bleu acier, chargeur à tambour orange sur le dessus, flanc à
    rayures de quai, buse épaisse ; rivet lumineux au bout et voyant de charge."""
    x = -0.215
    a = part("gun", "riveteuse", res=0.004)
    body = a.piece(STEELB, tris=900)
    body.add(rbox((x, 0.262, 0.07), (0.047, 0.098, 0.058), 0.024))
    a.piece(ORANGE, tris=500).add(rbox((x, 0.322, 0.07), (0.05, 0.026, 0.061), 0.022))  # bande de quai
    hz = a.piece(DARK, tris=400)
    for k in range(2):  # rayures sur la bande orange
        hz.add(rbox((x, 0.31 + k * 0.022, 0.07), (0.0515, 0.0045, 0.0625), 0.004))
    drum = a.piece(ORANGE, tris=700)
    drum.add(cyl((x, 0.255, 0.14), 0.045, 0.034, 0.012, rot=(0, 0, 90)))
    a.piece(GUNC, tris=200).add(cyl((x, 0.255, 0.14), 0.02, 0.037, 0.005, rot=(0, 0, 90)))
    nozzle = a.piece(GUNL, tris=500)
    nozzle.add(capsule((x, 0.17, 0.075), (x, 0.1, 0.075), 0.034, 0.024))
    a.piece(DARK, tris=300).add(cyl((x, 0.092, 0.075), 0.03, 0.012, 0.005))
    g = part("gun", "riveteuse", glow=True, res=0.0035)
    gp = g.piece(W, tris=300)
    gp.add(capsule((x, 0.082, 0.075), (x, 0.066, 0.075), 0.012, 0.016))  # tête de rivet
    gp.add(rbox((x, 0.215, 0.129), (0.02, 0.022, 0.004), 0.003))
    return [a, g]


def pistolet_neon():
    """Pistolet à rayons (Cité Néon) : corps rond rose bonbon, canon violet nuit, pavillon bleu évasé au bout,
    bulle lumineuse sur le dessus, ailerons bleus à l'arrière."""
    x = -0.215
    a = part("gun", "pistolet_neon", res=0.004)
    body = a.piece(PINK, tris=900)
    body.add(ellipsoid((x, 0.27, 0.07), (0.046, 0.088, 0.056)))
    a.piece(NIGHT, tris=400).add(capsule((x, 0.2, 0.072), (x, 0.11, 0.072), 0.02))
    a.piece(NIGHT, tris=300).add(torus((x, 0.27, 0.07), 0.046, 0.008), )
    horn = a.piece(BLUE, tris=600)
    horn.add(capsule((x, 0.118, 0.072), (x, 0.072, 0.072), 0.02, 0.046))
    horn.sub(sphere((x, 0.032, 0.072), 0.045))
    fins = a.piece(BLUE, tris=400)
    for sx in (-1.0, 1.0):
        fins.add(rbox((x + sx * 0.045, 0.335, 0.07), (0.022, 0.022, 0.006), 0.006, rot=(0, 90, sx * 35)))
    g = part("gun", "pistolet_neon", glow=True, res=0.0035)
    gp = g.piece(W, tris=500)
    gp.add(sphere((x, 0.275, 0.13), 0.034))
    gp.add(cyl((x, 0.085, 0.072), 0.03, 0.004, 0.002))
    return [a, g]


def build():
    items = {
        "visiere": visiere(), "casque_garde": casque_garde(), "plastron": plastron(), "veste": veste(),
        "bottes": legs("bottes", NAVY, 0.1), "jambieres": jambieres(),
        "pile": pile(), "aimant": aimant(),
        "module_canon": module_canon(), "cellule": cellule(),
        "blaster_garde": gun("blaster_garde"), "fusil_impulsion": gun("fusil_impulsion"),
        # Nébuleuse 7
        "riveteuse": riveteuse(), "pince": pince(), "casque_docker": casque_docker(),
        "gilet_fret": gilet_fret(), "amortisseurs": amortisseurs(), "reservoir": reservoir(),
        # Cité Néon
        "pistolet_neon": pistolet_neon(), "antenne": antenne(), "oreilles_chat": oreilles_chat(),
        "echarpe": echarpe(), "patins": patins(), "ailes": ailes(),
    }
    only = [s for s in os.environ.get("GEAR_ONLY", "").split(",") if s]
    return [Character("gear_" + k, budget(v)) for k, v in items.items() if not only or k in only]


BUDGET = 3200  # triangles par objet au plus (Jo seule en fait ~20 000 ; six objets portés à la fois)


def budget(parts):
    """Ramène la somme des budgets de triangles des volumes d'un objet sous BUDGET (proportionnellement)."""
    total = sum(pc.tris for p in parts for pc in p.pieces)
    if total > BUDGET:
        f = BUDGET / total
        for p in parts:
            for pc in p.pieces:
                pc.tris = max(100, int(pc.tris * f))
    return parts
