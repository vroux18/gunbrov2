"""Tenues de Jo (apparences, scripts/loot.gd SKINS). Un GLB par apparence : assets/chars3d/tenue_<id>.glb.

Chaque part s'appelle « <cible>__<zone>[_suffixe] » : le rig (scripts/rig3d.gd, _apply_outfit) la range dans la
part cible de Jo (head, torso, arm_l, arm_r...) avec le même pivot, donc les coordonnées ci-dessous sont celles
du modèle de Jo (tools/chars/jo.py : regarde vers +Z, sa droite en -X).

Zones (règle avec l'équipement : un objet porté masque, sur la même part, les pièces de tenue de sa zone) :
  coiffe   couvre-chef, chignons, mèches (masquée par un couvre-chef : casque, serre-tête)
  visage   visière (masquée par tout objet de tête)
  epaule   épaulettes (masquées par un module posé sur l'épaule)
  torse    col, plastron (masqué par un objet de torse devant)
  dos      panneau du sac, cape (masqué par un gadget dans le dos)
  ailes    ailes de la tenue (masquées seulement par un gadget large : petites ailes)
  autres   (sac : dessus du sac ; halo) jamais masquées : posées là où aucun objet ne va
Suffixes : « _glow » lumineux (lumière de l'apparence), « _hair » cheveux (couleur de cheveux de l'apparence),
« _spin » tourne lentement sur lui-même (halo).

Couleurs : celles de Jo, remappées par l'apparence (shaders/skin_remap.gdshaderinc) : SUIT -> combinaison,
ORANGE -> accent, TEAL -> lumière, HAIR -> cheveux. Les neutres sombres (NAVY, DARK, GUN) restent tels quels."""
from sculpt import *

PIV = {"torso": (0, 0.36, 0), "head": (0, 0.62, 0), "arm_l": (0.19, 0.57, 0), "arm_r": (-0.19, 0.57, 0),
       "leg_r": (-0.08, 0.34, 0), "leg_l": (0.08, 0.34, 0)}
SUIT = "#F4F1EA"
SUIT_D = "#D6D1C6"
ORANGE = "#FF7A2F"
ORANGE_D = "#E0601E"
TEAL = "#3CF2D8"
HAIR = "#1C2456"
HAIR_HI = "#4C63C8"
NAVY = "#1E2A4A"
DARK = "#141828"
GUN = "#3A4258"
GUN_L = "#5A6478"


def part(target, zone, suffix="", res=0.005):
    return Part(target + "__" + zone + suffix, pivot=PIV[target], res=res)


def sides():
    return (("r", -1.0), ("l", 1.0))


# ------------------------------------------------------------------ communes : un petit accessoire
def cargo():
    # sac de couchage roulé sanglé sur le haut du sac à réacteurs
    a = part("torso", "sac")
    a.piece(ORANGE, tris=500).add(capsule((-0.15, 0.672, -0.18), (0.15, 0.672, -0.18), 0.064))
    st = a.piece(NAVY, tris=300)
    for x in (-0.075, 0.075):
        st.add(torus((x, 0.672, -0.18), 0.066, 0.01, rot=(0, 0, 90)))
    return [a]


def glacier():
    # cache-oreilles en fourrure blanche, arceau bleu par-dessus la chevelure
    a = part("head", "coiffe")
    band = a.piece(ORANGE, tris=400)
    band.add(torus((0, 0.86, -0.03), 0.272, 0.016, rot=(90, 0, 0)))
    band.sub(rbox((0, 0.62, -0.03), (0.4, 0.24, 0.1), 0.01))
    fur = a.piece(SUIT, tris=700)
    for x in (-0.272, 0.272):
        fur.add(ellipsoid((x, 0.845, -0.02), (0.05, 0.078, 0.078)))
    return [a]


def ardoise():
    # antenne radio montée sur le sac, voyant au bout
    a = part("torso", "sac")
    a.piece(GUN, tris=200).add(rbox((-0.07, 0.628, -0.2), (0.03, 0.022, 0.03), 0.01))
    a.piece(GUN_L, tris=250).add(capsule((-0.07, 0.63, -0.2), (-0.11, 1.06, -0.28), 0.013, 0.008))
    g = part("torso", "sac", "_glow")
    g.piece(TEAL, tris=200).add(sphere((-0.112, 1.075, -0.283), 0.032))
    return [a, g]


def menthe():
    # barrette en feuille sur le côté gauche de la chevelure, nervure lumineuse
    a = part("head", "coiffe")
    a.piece(ORANGE, tris=400).add(ellipsoid((0.17, 1.03, 0.04), (0.035, 0.016, 0.085), rot=(-20, 30, -38)))
    a.piece(ORANGE, tris=300).add(ellipsoid((0.2, 1.0, -0.06), (0.03, 0.014, 0.07), rot=(10, -25, -45)))
    g = part("head", "coiffe", "_glow", res=0.004)
    g.piece(TEAL, tris=120).add(capsule((0.17, 1.048, -0.025), (0.17, 1.045, 0.1), 0.005))
    return [a, g]


# ------------------------------------------------------------------ rares
def corail():
    # deux chignons hauts (cheveux), chouchous corail, étoiles lumineuses piquées dedans
    h = part("head", "coiffe", "_hair")
    buns = h.piece(HAIR, tris=1000)
    for x in (-0.135, 0.135):
        buns.add(sphere((x, 1.075, -0.085), 0.088))
        buns.paint(torus((x, 1.1, -0.085), 0.055, 0.014, rot=(0, 0, x * -150)), HAIR_HI)
    a = part("head", "coiffe")
    sc = a.piece(ORANGE, tris=500)
    for x in (-0.135, 0.135):
        sc.add(torus((x * 0.94, 1.02, -0.08), 0.068, 0.02, rot=(0, 0, x * -110)))
    g = part("head", "coiffe", "_glow", res=0.004)
    st = g.piece(TEAL, tris=200)
    for x in (-0.135, 0.135):
        st.add(rbox((x * 1.25, 1.12, -0.02), (0.022, 0.022, 0.008), 0.006, rot=(0, 0, 45)))
    return [h, a, g]


def lagon():
    # bob de plage à large bord, bandeau, fleur lumineuse
    a = part("head", "coiffe")
    crown = a.piece(SUIT, tris=900)
    crown.add(ellipsoid((0, 0.995, -0.02), (0.258, 0.165, 0.262)))
    crown.add(ellipsoid((0, 0.945, -0.015), (0.37, 0.022, 0.365)), k=0.04)
    crown.sub(rbox((0, 0.7, 0), (0.5, 0.22, 0.5), 0.01))
    a.piece(ORANGE, tris=500).add(cyl((0, 0.982, -0.02), 0.262, 0.024, 0.01))
    g = part("head", "coiffe", "_glow", res=0.004)
    fl = g.piece(TEAL, tris=300)
    for i in range(5):
        ang = math.radians(90 + i * 72)
        fl.add(sphere((0.2 + 0.024 * math.cos(ang) * 0.4, 0.99 + 0.024 * math.sin(ang), 0.15 + 0.024 * math.cos(ang)), 0.016))
    return [a, g]


def sentinelle():
    # casque de garde robot : coque à oreilles (antennes), visière lumineuse sur le front, épaulières plates
    a = part("head", "coiffe", res=0.006)
    dome = a.piece(SUIT, tris=800)
    dome.add(ellipsoid((0, 0.915, -0.03), (0.274, 0.238, 0.266)))
    dome.add(ellipsoid((0, 0.99, 0.11), (0.215, 0.1, 0.155)), k=0.05)
    dome.sub(rbox((0, 0.78, 0.22), (0.185, 0.145, 0.15), 0.07), k=0.02)
    a.piece(ORANGE, tris=200).add(rbox((0, 1.13, -0.03), (0.045, 0.04, 0.2), 0.035))
    ears = a.piece(ORANGE, tris=400)
    for x in (-0.282, 0.282):
        ears.add(rbox((x, 0.86, -0.02), (0.034, 0.072, 0.072), 0.028))
        ears.add(capsule((x * 1.02, 0.91, -0.05), (x * 1.12, 1.13, -0.17), 0.024, 0.012), k=0.02)
    v = part("head", "visage", "_glow", res=0.004)
    vb = v.piece(TEAL, tris=300)
    vb.add(ellipsoid((0, 0.975, 0.11), (0.224, 0.036, 0.164)))
    vb.sub(rbox((0, 0.975, -0.05), (0.4, 0.1, 0.2), 0.01))
    eg = part("head", "coiffe", "_glow", res=0.004)
    e = eg.piece(TEAL, tris=150)
    for x in (-0.318, 0.318):
        e.add(cyl((x, 0.86, -0.02), 0.03, 0.006, 0.003, rot=(0, 0, 90)))
    out = [a, v, eg]
    for side, sx in sides():
        s = part("arm_" + side, "epaule")
        s.piece(ORANGE, tris=300).add(rbox((sx * 0.245, 0.652, 0), (0.1, 0.03, 0.104), 0.026, rot=(0, 0, sx * -16)))
        s.piece(SUIT_D, tris=100).add(rbox((sx * 0.25, 0.672, 0), (0.07, 0.012, 0.106), 0.008, rot=(0, 0, sx * -16)))
        out.append(s)
    return out


def agrume():
    # casquette jaune visière en avant, bouton lumineux, queue de cheval qui sort à l'arrière
    a = part("head", "coiffe")
    cap = a.piece(ORANGE, tris=900)
    cap.add(ellipsoid((0, 0.945, -0.01), (0.252, 0.192, 0.272)))
    cap.sub(rbox((0, 0.7, 0), (0.5, 0.22, 0.5), 0.01))
    cap.paint(ellipsoid((0, 1.03, 0.2), (0.15, 0.1, 0.1)), SUIT)
    a.piece(ORANGE_D, tris=400).add(ellipsoid((0, 0.95, 0.29), (0.175, 0.016, 0.15), rot=(14, 0, 0)))
    h = part("head", "coiffe", "_hair")
    tail = h.piece(HAIR, tris=700)
    pts = [(0, 0.97, -0.25), (0, 0.93, -0.34), (0, 0.84, -0.38), (0, 0.74, -0.36)]
    rr = [0.058, 0.052, 0.042, 0.03]
    for (p0, p1), r0, r1 in zip(zip(pts, pts[1:]), rr, rr[1:]):
        tail.add(capsule(p0, p1, r0, r1), k=0.03)
    tail.paint(capsule((0, 0.95, -0.33), (0, 0.85, -0.4), 0.02), HAIR_HI)
    g = part("head", "coiffe", "_glow", res=0.004)
    g.piece(TEAL, tris=150).add(sphere((0, 1.137, -0.01), 0.024))
    g.piece(TEAL, tris=150).add(torus((0, 0.955, -0.27), 0.05, 0.014, rot=(70, 0, 0)))
    return [a, h, g]


def lavande():
    # capuche souple à pointe tombante, bordure violette, cordons lumineux ; pèlerine sur les épaules
    a = part("head", "coiffe", res=0.006)
    hood = a.piece(ORANGE_D, tris=1100)
    hood.add(ellipsoid((0, 0.9, -0.045), (0.292, 0.262, 0.29)))
    hood.add(capsule((0, 0.98, -0.25), (0, 0.76, -0.37), 0.08, 0.026), k=0.06)
    hood.sub(ellipsoid((0, 0.84, 0.235), (0.205, 0.22, 0.15)), k=0.02)
    a.piece(SUIT, tris=450).add(torus((0, 0.845, 0.165), 0.198, 0.022, rot=(76, 0, 0)))
    g = part("head", "coiffe", "_glow", res=0.004)
    cords = g.piece(TEAL, tris=200)
    for x in (-0.07, 0.07):
        cords.add(capsule((x, 0.67, 0.17), (x * 1.1, 0.585, 0.19), 0.008))
        cords.add(sphere((x * 1.1, 0.578, 0.19), 0.014))
    c = part("torso", "torse", res=0.006)
    cape = c.piece(SUIT_D, tris=700)
    cape.add(ellipsoid((0, 0.6, -0.03), (0.255, 0.085, 0.205)))
    cape.sub(ellipsoid((0, 0.61, 0.02), (0.11, 0.2, 0.11)))
    cape.sub(rbox((0, 0.46, 0), (0.4, 0.07, 0.4), 0.01))
    c.piece(ORANGE, tris=300).add(torus((0, 0.535, -0.03), 0.22, 0.012, rot=(0, 0, 0)))
    return [a, g, c]


# ------------------------------------------------------------------ épiques
def nebuleuse():
    # casque de pilote spatial : coque ronde, crête rose, grande visière relevée ; ailerons de réacteur
    a = part("head", "coiffe", res=0.006)
    dome = a.piece(SUIT, tris=800)
    dome.add(ellipsoid((0, 0.905, -0.03), (0.27, 0.245, 0.27)))
    dome.sub(rbox((0, 0.78, 0.22), (0.19, 0.15, 0.15), 0.08), k=0.02)
    dome.paint(cyl((0, 0.84, -0.03), 0.4, 0.03, 0.01), SUIT_D)
    a.piece(ORANGE, tris=300).add(capsule((0, 1.16, 0.08), (0, 1.13, -0.26), 0.03, 0.02))
    a.piece(GUN_L, tris=150).add(cyl((0.24, 0.86, -0.04), 0.07, 0.03, 0.012, rot=(0, 0, 90)))
    a.piece(GUN_L, tris=150).add(cyl((-0.24, 0.86, -0.04), 0.07, 0.03, 0.012, rot=(0, 0, 90)))
    v = part("head", "visage", "_glow", res=0.004)
    vb = v.piece(TEAL, tris=300)
    vb.add(ellipsoid((0, 1.0, -0.02), (0.282, 0.075, 0.282), rot=(-12, 0, 0)))
    vb.sub(rbox((0, 1.0, -0.2), (0.4, 0.2, 0.3), 0.01))
    d = part("torso", "ailes", res=0.005)
    fins = d.piece(ORANGE, tris=400)
    for sx in (-1.0, 1.0):
        fins.add(rbox((sx * 0.27, 0.56, -0.22), (0.11, 0.016, 0.06), 0.012, rot=(0, sx * -20, sx * 24)))
    d.piece(GUN, tris=200).add(cyl((-0.15, 0.37, -0.2), 0.056, 0.035, 0.012))
    d.piece(GUN, tris=200).add(cyl((0.15, 0.37, -0.2), 0.056, 0.035, 0.012))
    dg = part("torso", "ailes", "_glow", res=0.004)
    tips = dg.piece(TEAL, tris=200)
    for sx in (-1.0, 1.0):
        tips.add(sphere((sx * 0.37, 0.6, -0.255), 0.02))
    return [a, v, d, dg]


def neon():
    # casque audio à grosses coques, visière néon sur les yeux, crête punk, col montant à liseré
    h = part("head", "coiffe", "_hair")
    crest = h.piece(HAIR, tris=700)
    pts = [(0, 1.1, 0.13), (0, 1.17, 0.02), (0, 1.16, -0.1), (0, 1.09, -0.21)]
    for p0, p1 in zip(pts, pts[1:]):
        crest.add(capsule(p0, p1, 0.04), k=0.03)
    crest.add(ellipsoid((0, 1.06, -0.04), (0.06, 0.07, 0.18)), k=0.04)
    crest.paint(capsule((0, 1.21, 0.0), (0, 1.2, -0.12), 0.03), HAIR_HI)
    a = part("head", "coiffe")
    a.piece(GUN, tris=350).add(torus((0, 0.865, -0.03), 0.272, 0.017, rot=(90, 0, 0)))
    a.pieces[-1].sub(rbox((0, 0.62, -0.03), (0.4, 0.24, 0.1), 0.01))
    cups = a.piece(ORANGE, tris=600)
    for x in (-0.272, 0.272):
        cups.add(cyl((x, 0.85, -0.02), 0.088, 0.036, 0.016, rot=(0, 0, 90)))
    g = part("head", "coiffe", "_glow", res=0.004)
    rings = g.piece(TEAL, tris=300)
    for x in (-0.31, 0.31):
        rings.add(torus((x, 0.85, -0.02), 0.06, 0.009, rot=(0, 0, 90)))
    v = part("head", "visage", "_glow", res=0.004)
    vb = v.piece(TEAL, tris=300)
    vb.add(ellipsoid((0, 0.845, 0.0), (0.228, 0.042, 0.228)))
    vb.sub(rbox((0, 0.845, -0.06), (0.4, 0.1, 0.17), 0.01))
    c = part("torso", "torse")
    col = c.piece(ORANGE, tris=500)
    col.add(cyl((0, 0.625, -0.02), 0.125, 0.045, 0.02))
    col.sub(cyl((0, 0.63, -0.0), 0.088, 0.1, 0.01))
    col.sub(rbox((0, 0.66, 0.15), (0.06, 0.05, 0.06), 0.01))
    cg = part("torso", "torse", "_glow", res=0.004)
    cg.piece(TEAL, tris=200).add(torus((0, 0.67, -0.02), 0.115, 0.007))
    return [h, a, g, v, c, cg]


def braise():
    # chevelure en flammes (cheveux), pointes lumineuses ; grosses épaulières blindées à évents
    h = part("head", "coiffe", "_hair")
    fl = h.piece(HAIR, tris=1000)
    for (x0, y0, z0), (x1, y1, z1), r in (((0, 1.07, 0.06), (0, 1.27, -0.12), 0.07),
                                          ((-0.11, 1.05, -0.02), (-0.17, 1.2, -0.2), 0.052),
                                          ((0.11, 1.05, -0.02), (0.17, 1.2, -0.2), 0.052),
                                          ((0, 1.02, -0.16), (0, 1.12, -0.32), 0.05)):
        fl.add(capsule((x0, y0, z0), (x1, y1, z1), r, r * 0.22), k=0.04)
    fl.paint(capsule((0, 1.15, -0.02), (0, 1.26, -0.12), 0.03), HAIR_HI)
    g = part("head", "coiffe", "_glow", res=0.004)
    tips = g.piece(TEAL, tris=250)
    for p in ((0, 1.275, -0.125), (-0.172, 1.205, -0.205), (0.172, 1.205, -0.205), (0, 1.125, -0.325)):
        tips.add(sphere(p, 0.018))
    out = [h, g]
    for side, sx in sides():
        s = part("arm_" + side, "epaule", res=0.006)
        pad = s.piece(ORANGE, tris=600)
        pad.add(ellipsoid((sx * 0.245, 0.63, 0), (0.125, 0.085, 0.118)))
        pad.add(rbox((sx * 0.25, 0.7, 0), (0.035, 0.03, 0.09), 0.015), k=0.02)
        pad.paint(torus((sx * 0.245, 0.62, 0), 0.115, 0.016, rot=(0, 0, sx * -18)), DARK)
        sg = part("arm_" + side, "epaule", "_glow", res=0.004)
        sg.piece(TEAL, tris=200).add(rbox((sx * 0.335, 0.62, 0), (0.008, 0.012, 0.06), 0.004, rot=(0, 0, sx * -30)))
        out += [s, sg]
    return out


def aurore():
    # diadème à gemme, longue queue de cheval haute qui flotte, cape courte à ourlet lumineux (aurore)
    a = part("head", "coiffe", res=0.004)
    ti = a.piece(SUIT, tris=500)
    ti.add(torus((0, 1.0, 0.0), 0.208, 0.011, rot=(-18, 0, 0)))
    ti.sub(rbox((0, 1.0, -0.2), (0.3, 0.2, 0.2), 0.01))
    ti.add(capsule((0, 1.06, 0.2), (0, 1.12, 0.18), 0.022, 0.006), k=0.01)
    g = part("head", "coiffe", "_glow", res=0.004)
    g.piece(TEAL, tris=200).add(ellipsoid((0, 1.07, 0.212), (0.022, 0.03, 0.012)))
    hh = part("head", "coiffe", "_hair")
    tail = hh.piece(HAIR, tris=900)
    pts = [(0, 1.09, -0.14), (0, 1.11, -0.27), (0, 1.0, -0.38), (0.02, 0.84, -0.42), (0.04, 0.7, -0.4)]
    rr = [0.07, 0.066, 0.056, 0.042, 0.022]
    for (p0, p1), r0, r1 in zip(zip(pts, pts[1:]), rr, rr[1:]):
        tail.add(capsule(p0, p1, r0, r1), k=0.035)
    tail.paint(capsule((0, 1.15, -0.25), (0, 1.03, -0.42), 0.025), HAIR_HI)
    tail.paint(torus((0, 1.1, -0.17), 0.072, 0.016, rot=(60, 0, 0)), ORANGE)
    c = part("torso", "dos", res=0.006)
    cape = c.piece(ORANGE, tris=650)
    cape.add(ellipsoid((0, 0.5, -0.12), (0.31, 0.2, 0.235)))
    cape.sub(ellipsoid((0, 0.5, -0.1), (0.29, 0.21, 0.215)))
    cape.sub(rbox((0, 0.5, 0.1), (0.5, 0.4, 0.18), 0.01))
    cape.sub(rbox((0, 0.9, 0), (0.5, 0.25, 0.5), 0.01))
    cape.paint(rbox((0, 0.32, -0.2), (0.5, 0.06, 0.3), 0.01), SUIT)
    cl = c.piece(SUIT, tris=150)
    for sx in (-1.0, 1.0):
        cl.add(sphere((sx * 0.13, 0.63, 0.0), 0.03))
    cg = part("torso", "dos", "_glow", res=0.005)
    hem = cg.piece(TEAL, tris=300)
    hem.add(ellipsoid((0, 0.318, -0.12), (0.318, 0.012, 0.243)))
    hem.sub(ellipsoid((0, 0.318, -0.1), (0.284, 0.05, 0.21)))
    hem.sub(rbox((0, 0.318, 0.1), (0.5, 0.1, 0.18), 0.01))
    return [a, g, hh, c, cg]


# ------------------------------------------------------------------ légendaires
def eclat():
    # couronne d'or à gemmes, ailes de lumière déployées depuis le sac, épaulettes d'apparat
    a = part("head", "coiffe", res=0.004)
    cr = a.piece(SUIT, tris=700)
    cr.add(cyl((0, 1.04, -0.03), 0.178, 0.03, 0.01, rot=(-6, 0, 0)))
    cr.sub(cyl((0, 1.04, -0.03), 0.152, 0.06, 0.01, rot=(-6, 0, 0)))
    for i in range(5):
        ang = math.radians(90 + i * 72)
        x, z = 0.165 * math.cos(ang), -0.03 + 0.165 * math.sin(ang)
        cr.add(capsule((x, 1.06, z), (x * 1.08, 1.17 + (0.03 if i == 0 else 0.0), z * 1.08), 0.022, 0.006), k=0.015)
    g = part("head", "coiffe", "_glow", res=0.004)
    gm = g.piece(TEAL, tris=300)
    for i in range(5):
        ang = math.radians(90 + i * 72)
        gm.add(sphere((0.18 * math.cos(ang), 1.04, -0.03 + 0.18 * math.sin(ang)), 0.017))
    w = part("torso", "ailes", "_glow", res=0.005)
    wg = w.piece(TEAL, tris=800)
    for sx in (-1.0, 1.0):
        for (cx, cy, cz), (rx, ry), ang in (((0.39, 0.84, -0.34), (0.32, 0.05), 38),
                                            ((0.43, 0.64, -0.37), (0.33, 0.045), 12),
                                            ((0.35, 0.46, -0.35), (0.25, 0.038), -16)):
            wg.add(ellipsoid((sx * cx, cy, cz), (rx, ry, 0.014), rot=(0, sx * 14, sx * ang)))
    wr = part("torso", "ailes", res=0.005)
    wr.piece(SUIT, tris=300).add(capsule((-0.13, 0.62, -0.25), (0.13, 0.62, -0.25), 0.03))
    out = [a, g, w, wr]
    for side, sx in sides():
        s = part("arm_" + side, "epaule")
        e = s.piece(SUIT, tris=350)
        e.add(ellipsoid((sx * 0.24, 0.645, 0), (0.105, 0.045, 0.1)))
        e.paint(torus((sx * 0.24, 0.64, 0), 0.098, 0.014), ORANGE)
        out.append(s)
    return out


def prisme():
    # halo prismatique qui tourne au-dessus de la tête, éclats de cristal en ailes, diadème de cristal
    hl = part("head", "halo", "_spin_glow", res=0.004)
    ring = hl.piece(TEAL, tris=700)
    ring.add(torus((0, 1.21, 0), 0.215, 0.014))
    for i in range(6):
        ang = math.radians(i * 60)
        ring.add(rbox((0.215 * math.cos(ang), 1.21, 0.215 * math.sin(ang)), (0.032, 0.032, 0.032), 0.006, rot=(45, ang * 57.3, 45)))
    a = part("head", "coiffe", res=0.004)
    cr = a.piece(SUIT, tris=400)
    for x, h in ((0.0, 0.09), (-0.07, 0.06), (0.07, 0.06)):
        cr.add(rbox((x, 1.07 + h * 0.4, 0.17 - abs(x) * 0.4), (0.018, h, 0.012), 0.006, rot=(-30, 0, x * -200)))
    w = part("torso", "ailes", "_glow", res=0.005)
    sh = w.piece(TEAL, tris=900)
    for sx in (-1.0, 1.0):
        for (cx, cy, cz), s, ang in (((0.36, 0.8, -0.33), 0.12, 32), ((0.46, 0.6, -0.35), 0.1, 8), ((0.36, 0.43, -0.33), 0.08, -16)):
            sh.add(rbox((sx * cx, cy, cz), (s * 1.5, s * 0.36, 0.016), 0.006, rot=(0, sx * 14, sx * ang)))
    wr = part("torso", "ailes", res=0.005)
    wr.piece(SUIT, tris=300).add(capsule((-0.13, 0.62, -0.25), (0.13, 0.62, -0.25), 0.026))
    out = [hl, a, w, wr]
    s = part("arm_r", "epaule")
    s.piece(SUIT, tris=300).add(rbox((-0.25, 0.66, 0), (0.06, 0.02, 0.07), 0.012, rot=(0, 0, 20)))
    sg = part("arm_r", "epaule", "_glow", res=0.004)
    sg.piece(TEAL, tris=200).add(rbox((-0.26, 0.71, 0), (0.016, 0.05, 0.016), 0.005, rot=(10, 30, 20)))
    out += [s, sg]
    return out


def build():
    outfits = {"cargo": cargo(), "glacier": glacier(), "ardoise": ardoise(), "menthe": menthe(),
               "corail": corail(), "lagon": lagon(), "sentinelle": sentinelle(), "agrume": agrume(),
               "lavande": lavande(), "nebuleuse": nebuleuse(), "neon": neon(), "braise": braise(),
               "aurore": aurore(), "eclat": eclat(), "prisme": prisme()}
    only = os.environ.get("TENUES")
    if only:
        outfits = {k: v for k, v in outfits.items() if k in only.split(",")}
    return [Character("tenue_" + k, v) for k, v in outfits.items()]
