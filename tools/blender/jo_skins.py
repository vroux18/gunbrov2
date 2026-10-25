"""Apparences de Jo : des TENUES COMPLÈTES (silhouette entière), une par fichier assets/chars3d/<model>.glb.

    /opt/bpyenv/bin/python tools/blender/jo_skins.py                  toutes les tenues
    /opt/bpyenv/bin/python tools/blender/jo_skins.py jo_chevalier     celles-là
puis  $G --headless --import  (Godot), et vérifier : tools/jo_board.tscn (planche face / dos), écran APPARENCES.

PIPELINE POUR AJOUTER UNE APPARENCE (ex. « pirate de l'espace » pour l'id « corail » de scripts/loot.gd) :
 1. Écrire ici une fonction qui construit le modèle ENTIER sur la base de Jo (tools/blender/jo.py) :
        def pirate():
            m = Model("jo_pirate")
            head(m)                       # visage de Jo (toujours)
            ...                           # couvre-chef, haut, manches, bas, chaussures, dos : tout change
            blaster(m, ...)               # arme : même repère (bout du canon fixe, voir MUZZLE de rig3d.gd)
            return m
    et l'ajouter à BUILDS. Les briques de jo.py se réutilisent avec d'autres couleurs et tailles : torso(),
    jacket() (veste sur le gabarit FITTED), arms() (manches, gants), legs() (pantalon / short, chaussures),
    hood(), bangs(), hair_bob(), sneaker(), back_logo() ; et les formes de tools/blender/jo_lib.py : loft (tube à
    sections), smooth, ell, box, shell (coque ouverte : capuche, cape, jupe, bord de chapeau), torus, disc, star,
    ribbon, seam (trait d'encre posé sur une surface).
 2. CONTRAT DES PARTS (indispensable, sinon le rig n'anime pas) : utiliser P(m, nom) qui donne pivot et parent.
      torso, head, hair, arm_r, arm_l, gun, leg_r, leg_l, shin_r, shin_l       (corps, animés par rig3d.gd)
      <part>_glow                                                             (lumineux, enfant de <part>)
      zones que l'équipement porté remplace : coiffe, visage, col, dos, epaule_r, epaule_l, jambe_r, jambe_l
      (ex. P(m, "coiffe") pour un chapeau, P(m, "jambe_r") pour une botte ; un casque porté masque la coiffe)
      pans flottants : chain(m, "dos", [pivots], "torso") -> dos_f1, dos_f2... (cape) ; chain(m, "coiffe", ...)
      (plumet, pointe de chapeau, bandeau) : le rig les couche dans le vent de la course (_jo_flow).
    Hauteur ~1,26, mêmes pivots que jo.py (PIV) : tout ce qui touche une articulation déborde un peu dessus
    (manche sur l'épaule, ourlet sur la hanche) pour cacher les jointures quand le rig tourne les parts.
 3. Style : aplats francs (pas d'occlusion cuite), formes nettes à chanfreins, un ou deux accents forts ; penser
    VUE DE DESSUS (caméra 56°, Jo ~55 px) : le couvre-chef, les épaules et le dos font la silhouette.
    Budget : 24 000 triangles par tenue (le script affiche le compte).
 4. Dans scripts/loot.gd, mettre « "model": "jo_pirate" » à l'apparence (l'id ne change pas : la sauvegarde suit)
    et retirer sa palette provisoire (« hair » ; suit / accent / light restent pour la carte 2D).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jo import *  # noqa

STEEL = "#AEB8CA"
STEEL_D = "#6F7A90"
GOLD = "#F2B33D"
GOLD_D = "#C9861E"
CAPE = "#D9222C"
CAPE_IN = "#7E1220"
PLUME = "#F0262E"

VIOLET = "#3B2A78"
VIOLET_D = "#2A1D5A"
ROBE = "#2B2163"
STARC = "#FFE27A"
LILAC = "#D8CCFF"

NIGHT = "#1E1B2E"
NIGHT_L = "#34304E"
PINK = "#FF3CAC"
CYAN = "#2EE6FF"
HAKAMA = "#2B2446"


# ------------------------------------------------------------------ Chevalière d'or
def chevalier():
    """Chevalière d'or : heaume rond à crête dorée et plumet rouge qui flotte, épaulières bombées à liseré d'or,
    cuirasse claire marquée de l'anneau des Passeurs en or, faltes, gantelets, jambières et solerets, grande
    cape rouge doublée de grenat qui vole derrière elle."""
    m = Model("jo_chevalier")
    head(m)
    bangs(m)
    # heaume
    c = P(m, "coiffe")
    hs = [((0, 0.94, -0.004), 0.094, 0.104), ((0, 0.99, -0.002), 0.104, 0.118), ((0, 1.06, -0.004), 0.108, 0.124),
          ((0, 1.13, -0.008), 0.104, 0.12), ((0, 1.19, -0.012), 0.084, 0.1), ((0, 1.235, -0.014), 0.048, 0.06),
          ((0, 1.252, -0.014), 0.012, 0.016)]
    hg = loft(smooth([S(cc, a, b, min(a, b) * 0.8) for cc, a, b in hs], 2), STEEL, nc=3)
    hg.paint(lambda c, n: 1.05 < c.y < 1.075, GOLD)
    c.add(hg)
    def on(x, y):
        p, n = surface(hg, (x, y, 0.5), (0, 0, -1))
        return p
    sl = on(0, 1.075)
    c.add(box(sl + Vector((0, 0, 0.002)), (0.07, 0.008, 0.006), 0.003, INK))  # fente de la visière
    c.add(box(on(0, 1.03) + Vector((0, 0, 0.002)), (0.006, 0.03, 0.006), 0.003, INK))
    for i in range(3):
        for sx in (-1, 1):
            c.add(ell(on(sx * (0.035 + i * 0.012), 1.0) + Vector((0, 0, 0.001)), 0.004, 0.004, 0.004, INK, n=3, nc=1))
    # crête dorée de l'avant à la nuque
    crest = []
    for i in range(9):
        a = math.radians(-60 + 150 * i / 8)
        crest.append(S((0, 1.07 + 0.19 * math.cos(a) * 0.98, 0.115 * math.sin(a) - 0.008), 0.008, 0.014, 0.004))
    c.add(loft(crest, GOLD, nc=1))
    # plumet : base dorée, plumes rouges en trois maillons qui flottent
    c.add(loft([S((0, 1.25, -0.03), 0.016, 0.016), S((0, 1.275, -0.05), 0.012, 0.012)], GOLD, nc=2))
    pv = [(0, 1.275, -0.05), (0, 1.29, -0.13), (0, 1.25, -0.21), (0, 1.17, -0.26)]
    segs = chain(m, "coiffe", pv[:3], "coiffe")
    for i, sg in enumerate(segs):
        a, b = Vector(pv[i]), Vector(pv[i + 1])
        for k, (dx, w) in enumerate(((0.0, 0.038), (-0.022, 0.03), (0.022, 0.03))):
            sg.add(ell((a + b) * 0.5 + Vector((dx * (1 + i * 0.4), -0.008 * k, 0)), w * (1.0 - 0.15 * i), (b - a).length * 0.62,
                       0.016 + 0.004 * (k == 0), PLUME if k == 0 else "#C8141F", n=5, nc=2, up=(b - a).normalized()))
    # cuirasse
    tg = torso(m, [
        (0.5, 0.06, 0.05, 0.0, INK), (0.525, 0.104, 0.074, 0.0, None), (0.57, 0.112, 0.078, 0.0, None),
        (0.63, 0.104, 0.072, 0.004, GOLD), (0.65, 0.104, 0.073, 0.004, None), (0.72, 0.112, 0.08, 0.01, None),
        (0.8, 0.13, 0.09, 0.016, None), (0.855, 0.14, 0.084, 0.008, None), (0.888, 0.134, 0.072, 0.0, None),
        (0.912, 0.088, 0.058, -0.004, None), (0.93, 0.04, 0.04, -0.004, None)], STEEL)
    t = P(m, "torso")
    p, n = surface(tg, (0, 0.78, 0.5), (0, 0, -1))
    t.add(disc(p + Vector((0, 0, 0.002)), (0, 0, 1), 0.026, 0.04, 0.005, GOLD, seg=32, arc=(110, 380)))
    seam(t, tg, [(0, 0.88, 0), (0, 0.66, 0)], (0, 0, -1), col=STEEL_D, w=0.0022)
    # faltes : jupe de lames évasée
    t.add(shell([{"c": (0, 0.6, 0.0), "a": 0.122, "b": 0.088, "a0": 0, "a1": 360, "col": GOLD},
                 {"c": (0, 0.585, 0.0), "a": 0.13, "b": 0.096, "a0": 0, "a1": 360},
                 {"c": (0, 0.52, 0.0), "a": 0.148, "b": 0.114, "a0": 0, "a1": 360, "col": STEEL_D},
                 {"c": (0, 0.47, 0.0), "a": 0.158, "b": 0.124, "a0": 0, "a1": 360}], 0.012, STEEL, inner=STEEL_D, seg=28))
    # gorgerin
    P(m, "col").add(shell([{"c": (0, 0.885, -0.004), "a": 0.084, "b": 0.07, "a0": 0, "a1": 360},
                           {"c": (0, 0.935, -0.006), "a": 0.058, "b": 0.05, "a0": 0, "a1": 360, "col": GOLD},
                           {"c": (0, 0.945, -0.006), "a": 0.056, "b": 0.049, "a0": 0, "a1": 360}], 0.012, STEEL))
    # épaulières bombées, deux lames, liseré d'or
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        e.add(shell([{"c": (sx * 0.17, 0.95, 0.0), "a": 0.02, "b": 0.02, "a0": 0, "a1": 360},
                     {"c": (sx * 0.17, 0.935, 0.0), "a": 0.06, "b": 0.064, "a0": 0, "a1": 360},
                     {"c": (sx * 0.172, 0.9, 0.0), "a": 0.078, "b": 0.08, "a0": 0, "a1": 360},
                     {"c": (sx * 0.176, 0.865, 0.0), "a": 0.084, "b": 0.084, "a0": 0, "a1": 360, "col": GOLD},
                     {"c": (sx * 0.176, 0.858, 0.0), "a": 0.085, "b": 0.085, "a0": 0, "a1": 360}], 0.014, STEEL, inner=STEEL_D, seg=26))
        e.add(shell([{"c": (sx * 0.178, 0.86, 0.0), "a": 0.07, "b": 0.072, "a0": 0, "a1": 360},
                     {"c": (sx * 0.18, 0.825, 0.0), "a": 0.068, "b": 0.07, "a0": 0, "a1": 360, "col": GOLD},
                     {"c": (sx * 0.18, 0.818, 0.0), "a": 0.068, "b": 0.07, "a0": 0, "a1": 360}], 0.01, STEEL, inner=STEEL_D, seg=24))
    arms(m, STEEL, STEEL, cuff=GOLD, cuff_y=0.575, wide=1.05)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(ell((sx * 0.176, 0.705, -0.02), 0.03, 0.026, 0.024, STEEL_D, n=4))  # coudière
        a.add(loft([S((sx * 0.186, 0.6, 0.026), 0.034, 0.033), S((sx * 0.188, 0.545, 0.044), 0.036, 0.035)], GOLD_D, nc=2))
    # jambes : cuissards, genouillères, grèves, solerets pointus
    legs(m, STEEL_D, None, None, None, knee=STEEL)
    for side, sx in sides():
        l = P(m, "leg_" + side)
        l.add(loft(smooth([S((sx * 0.07, 0.56, 0.006), 0.064, 0.068), S((sx * 0.073, 0.46, 0.01), 0.056, 0.06),
                           S((sx * 0.074, 0.39, 0.01), 0.048, 0.052)], 2), STEEL, nc=2))
        s = P(m, "shin_" + side)
        s.add(loft(smooth([S((sx * 0.075, 0.3, 0.006), 0.046, 0.05), S((sx * 0.075, 0.22, 0.002), 0.044, 0.048),
                           S((sx * 0.076, 0.13, -0.002), 0.038, 0.042)], 2), STEEL, nc=2))
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft([S((x, 0.03, z), a, bb, min(a, bb) * 0.6) for z, a, bb in
                    ((-0.06, 0.034, 0.03), (-0.04, 0.044, 0.042), (0.03, 0.046, 0.036), (0.1, 0.034, 0.022), (0.16, 0.008, 0.008))],
                   STEEL_D, nc=2))
        b.add(loft([S((x, 0.075, -0.02), 0.043, 0.046), S((x, 0.15, -0.006), 0.042, 0.045)], GOLD_D, nc=2))
        b.add(loft([S((x, 0.004, z), a + 0.002, 0.004, 0.003) for z, a in ((-0.06, 0.034), (0.03, 0.046), (0.15, 0.012))], INK, nc=1))
    # cape rouge en trois pans qui flottent (zone dos), attachée sous les épaulières
    pv = [(0, 0.905, -0.075), (0, 0.72, -0.105), (0, 0.52, -0.125), (0, 0.3, -0.14)]
    segs = chain(m, "dos", pv[:3], "torso")
    for i, sg in enumerate(segs):
        a, b = Vector(pv[i]), Vector(pv[i + 1])
        w0, w1 = 0.15 + 0.035 * i, 0.15 + 0.035 * (i + 1)
        wa0, wa1 = 0.03 * i, 0.03 * (i + 1)
        secs = [{"c": (0, a.y, a.z + 0.075 + 0.012 * i), "a": w0, "b": 0.12 + 0.012 * i, "a0": 205, "a1": 335, "col": CAPE, "wave": (wa0, 9)},
                {"c": (0, b.y, b.z + 0.075 + 0.012 * (i + 1)), "a": w1, "b": 0.12 + 0.012 * (i + 1), "a0": 203, "a1": 337, "wave": (wa1, 9)}]
        if i == 2:
            secs.insert(1, {"c": (0, b.y + 0.022, b.z + 0.075 + 0.012 * 2.9), "a": w1 - 0.004, "b": 0.12 + 0.012 * 2.9, "a0": 203, "a1": 337, "col": GOLD, "wave": (wa1 * 0.95, 9)})
        sg.add(shell(secs, 0.01, CAPE, inner=CAPE_IN, seg=18))
    P(m, "dos").add(box((0, 0.9, -0.085), (0.11, 0.014, 0.012), 0.005, GOLD))  # agrafe de la cape
    blaster(m, shell_col=STEEL, stripe=GOLD, metal=STEEL_D, glow="#FFF2B8")
    return m


# ------------------------------------------------------------------ Mage Nébuleuse
def magicienne():
    """Mage Nébuleuse : immense chapeau pointu violet à large bord, bande d'or et étoiles lumineuses, pointe
    cassée qui ballotte ; longue robe nuit semée d'étoiles, ourlet d'or, manches évasées, grand col dressé ;
    cheveux lilas longs dans le dos ; baguette-blaster à cristal."""
    m = Model("jo_magicienne")
    head(m, iris="#5A3AA8")
    hp = hair_bob(m, LILAC, long_side=False)
    # longues mèches en pointes dans le dos
    for k in range(7):
        a = math.radians(196 + k * 24.7)
        x, z = math.cos(a), math.sin(a)
        L = 0.24 + 0.05 * math.sin(k * 1.9) - 0.04 * abs(k - 3) / 3
        pts = [(x * 0.09, 1.04, z * 0.1 - 0.012), (x * 0.1, 0.96, z * 0.1 - 0.03), (x * 0.098, 1.04 - L * 0.7, z * 0.094 - 0.045),
               (x * 0.09, 1.04 - L, z * 0.088 - 0.05)]
        hp.add(loft([S(pts[0], 0.026, 0.014, 0.006), S(pts[1], 0.028, 0.015, 0.006), S(pts[2], 0.02, 0.012, 0.005),
                     S(pts[3], 0.003, 0.003, 0.001)], LILAC, nc=1, ref=(-z, 0, x)))
    # chapeau : bord large, calotte conique, pointe en deux maillons qui ballottent
    c = P(m, "coiffe")
    c.add(shell([{"c": (0, 1.12, 0.0), "a": 0.235, "b": 0.235, "a0": 0, "a1": 360},
                 {"c": (0, 1.15, -0.008), "a": 0.11, "b": 0.115, "a0": 0, "a1": 360}], 0.012, VIOLET, inner=VIOLET_D, seg=36))
    crown = [S((0, 1.14, -0.008), 0.108, 0.114), S((0, 1.2, -0.012), 0.088, 0.094, col=GOLD), S((0, 1.225, -0.014), 0.083, 0.089),
             S((0, 1.29, -0.02), 0.062, 0.066)]
    c.add(loft(smooth(crown, 2), VIOLET, nc=3))
    pv = [(0, 1.29, -0.02), (0, 1.37, -0.045), (0, 1.43, -0.1)]
    segs = chain(m, "coiffe", pv[:2], "coiffe")
    segs[0].add(loft([S(pv[0], 0.062, 0.066), S((0, 1.33, -0.03), 0.05, 0.053), S(pv[1], 0.036, 0.038)], VIOLET, nc=3))
    segs[1].add(loft([S(pv[1], 0.036, 0.038), S((0, 1.405, -0.07), 0.022, 0.023), S(pv[2], 0.004, 0.004)], VIOLET, nc=2))
    c.add(box((0.0, 1.21, 0.1), (0.022, 0.022, 0.006), 0.004, GOLD))  # boucle
    cg = P(m, "coiffe_glow")
    for i, (a, rr) in enumerate(((20, 0.18), (85, 0.2), (150, 0.17), (215, 0.19), (280, 0.18), (330, 0.2))):
        x, z = math.cos(math.radians(a)) * rr, math.sin(math.radians(a)) * rr
        cg.add(star((x, 1.128 + 0.004 * (rr / 0.2), z - 0.008), (0, 1, 0), 0.022, 0.009, 0.004, STARC if i % 2 == 0 else "#9FF6FF", spin=a))
    cg.add(star((0.05, 1.26, 0.055), (0.5, 0.2, 1), 0.016, 0.007, 0.004, STARC))
    cg.add(star((-0.04, 1.32, 0.03), (-0.4, 0.3, 1), 0.012, 0.005, 0.004, "#9FF6FF"))
    # robe longue : buste ajusté, cloche jusqu'aux chevilles
    tg = torso(m, [
        (0.06, 0.24, 0.2, 0.0, GOLD), (0.1, 0.235, 0.195, 0.0, None), (0.25, 0.19, 0.16, 0.0, None),
        (0.42, 0.145, 0.118, 0.0, None), (0.56, 0.11, 0.08, 0.0, None), (0.64, 0.094, 0.066, 0.002, GOLD),
        (0.66, 0.095, 0.067, 0.002, None), (0.74, 0.104, 0.072, 0.008, None), (0.81, 0.122, 0.08, 0.012, None),
        (0.858, 0.134, 0.076, 0.004, None), (0.89, 0.13, 0.068, 0.0, None), (0.915, 0.085, 0.056, -0.004, None),
        (0.932, 0.04, 0.04, -0.004, None)], ROBE, k=2)
    t = P(m, "torso")
    seam(t, tg, [(0, 0.86, 0), (0, 0.66, 0)], (0, 0, -1), col=GOLD, w=0.0028)
    back_logo(t, tg, 0.4, 0.07, GOLD)
    rg = extra(m, "robe_glow", "torso")
    for i in range(14):
        a = i * 2.39996
        y = 0.12 + (i % 7) * 0.05 + 0.02 * (i // 7)
        k = (y - 0.06) / (0.56 - 0.06)
        ra = 0.235 + (0.11 - 0.235) * k
        rb = 0.195 + (0.08 - 0.195) * k
        x, z = math.cos(a) * ra, math.sin(a) * rb
        nrm = Vector((math.cos(a) / ra, 0.25, math.sin(a) / rb)).normalized()
        rg.add(star(Vector((x, y, z)) + nrm * 0.003, nrm, 0.014 if i % 3 else 0.02, 0.006 if i % 3 else 0.008, 0.003,
                    STARC if i % 2 else "#9FF6FF", spin=i * 17))
    # grand col dressé (zone col)
    P(m, "col").add(shell([{"c": (0, 0.9, -0.01), "a": 0.09, "b": 0.075, "a0": 120, "a1": 420},
                           {"c": (0, 0.99, -0.03), "a": 0.12, "b": 0.1, "a0": 130, "a1": 410, "col": GOLD},
                           {"c": (0, 1.0, -0.032), "a": 0.122, "b": 0.102, "a0": 130, "a1": 410}], 0.01, VIOLET, inner=GOLD_D, seg=24))
    # manches évasées
    arms(m, VIOLET, SKIN, wide=1.0, cuff=None)
    for side, sx in sides():
        a = P(m, "arm_" + side)
        a.add(shell([{"c": (sx * 0.18, 0.66, 0.012), "a": 0.034, "b": 0.034, "a0": 0, "a1": 360},
                     {"c": (sx * 0.186, 0.585, 0.034), "a": 0.058, "b": 0.058, "a0": 0, "a1": 360, "col": GOLD},
                     {"c": (sx * 0.188, 0.565, 0.04), "a": 0.066, "b": 0.066, "a0": 0, "a1": 360}], 0.008, VIOLET, inner=VIOLET_D, seg=22))
    legs(m, ROBE, None, None, None)
    for side, sx in sides():
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft(smooth([S((x, 0.03, -0.05), 0.03, 0.03), S((x, 0.035, 0.0), 0.04, 0.034), S((x, 0.03, 0.08), 0.03, 0.022),
                           S((x, 0.05, 0.14), 0.012, 0.012), S((x, 0.085, 0.15), 0.004, 0.004)], 2), VIOLET, nc=2))
        b.add(loft([S((x, 0.004, -0.05), 0.03, 0.004), S((x, 0.004, 0.06), 0.034, 0.004)], GOLD, nc=1))
    # baguette-blaster : corps violet, bagues d'or, cristal lumineux au bout (MUZZLE inchangé)
    g = P(m, "gun")
    o = Vector(PIV["gun"])
    def L(x, y, z):
        return o + Vector((x, y, z))
    g.add(box(L(0, -0.005, 0.014), (0.017, 0.026, 0.022), 0.007, VIOLET_D))
    g.add(loft(smooth([S(L(0, -0.02, 0.05), 0.026, 0.03), S(L(0, -0.09, 0.056), 0.02, 0.022), S(L(0, -0.17, 0.058), 0.016, 0.016),
                       S(L(0, -0.2, 0.058), 0.022, 0.022)], 2), VIOLET, nc=2))
    for y in (-0.05, -0.12, -0.19):
        g.add(torus(L(0, y, 0.057), (0, 1, 0), 0.021, 0.005, GOLD, seg=16, rs=4))
    gg = P(m, "gun_glow")
    gg.add(ell(L(0, -0.215, 0.058), 0.017, 0.018, 0.017, "#B9F6FF", n=4, nc=1))
    gg.add(star(L(0, -0.06, 0.084), (0, 0, 1), 0.016, 0.007, 0.004, STARC))
    return m


# ------------------------------------------------------------------ Ronin Néon
def samourai():
    """Ronin Néon : kabuto nuit à couvre-nuque en lames et croissant rose lumineux, bandeau dont les pans roses
    flottent, demi-masque, veste croisée à liserés néon, grandes plaques d'épaule, ceinture rose, hakama ample,
    tabi, sabre au fourreau en travers du dos (poignée lumineuse), blaster néon."""
    m = Model("jo_samourai")
    head(m, iris="#2A8AA8")
    bangs(m, "#121018")
    c = P(m, "coiffe")
    kb = [S((0, 1.06, -0.008), 0.098, 0.108), S((0, 1.12, -0.01), 0.098, 0.108), S((0, 1.18, -0.014), 0.08, 0.09),
          S((0, 1.225, -0.016), 0.05, 0.058), S((0, 1.243, -0.016), 0.014, 0.016)]
    kg = loft(smooth(kb, 2), NIGHT, nc=3)
    kg.paint(lambda c, n: abs(c.x) < 0.012 and c.y > 1.1, PINK)
    c.add(kg)
    # couvre-nuque : trois lames évasées (sauf devant)
    for i in range(3):
        y = 1.06 - i * 0.03
        c.add(shell([{"c": (0, y + 0.012, -0.012), "a": 0.104 + 0.022 * i, "b": 0.112 + 0.02 * i, "a0": 160, "a1": 380},
                     {"c": (0, y - 0.018, -0.02), "a": 0.122 + 0.024 * i, "b": 0.128 + 0.022 * i, "a0": 160, "a1": 380, "col": PINK if i == 2 else None} if i == 2 else
                     {"c": (0, y - 0.018, -0.02), "a": 0.122 + 0.024 * i, "b": 0.128 + 0.022 * i, "a0": 160, "a1": 380}], 0.01, NIGHT_L if i % 2 else NIGHT, inner=NIGHT, seg=24))
    c.add(shell([{"c": (0, 1.062, -0.008), "a": 0.101, "b": 0.111, "a0": 0, "a1": 360},
                 {"c": (0, 1.078, -0.008), "a": 0.1, "b": 0.11, "a0": 0, "a1": 360}], 0.012, PINK, seg=28))
    cgl = P(m, "coiffe_glow")
    cgl.add(disc((0, 1.2, 0.1), (0, 0.35, 1), 0.105, 0.12, 0.008, PINK, seg=28, arc=(200, 340)))  # croissant
    cgl.add(disc((0, 1.2, 0.1), (0, 0.35, 1), 0.0, 0.016, 0.01, CYAN, seg=12))
    # pans roses du bandeau qui flottent
    pv = [(0, 1.07, -0.12), (0, 1.02, -0.19), (0, 0.95, -0.23), (0, 0.87, -0.25)]
    segs = chain(m, "coiffe", pv[:3], "coiffe")
    for k, sx in ((1.0, 1), (0.85, -1)):
        for i, sg in enumerate(segs):
            a = Vector(pv[i]) + Vector((sx * (0.01 + 0.014 * i), 0, 0))
            b = Vector(pv[i]) + (Vector(pv[i + 1]) - Vector(pv[i])) * k + Vector((sx * (0.01 + 0.014 * (i + 1)), 0, 0))
            ribbon(sg, a, b, 0.024 - 0.002 * i, 0.022 - 0.002 * i - (0.012 if i == 2 else 0.0), 0.005, PINK)
    # demi-masque
    v = P(m, "visage")
    v.add(shell([{"c": (0, 0.955, 0.03), "a": 0.04, "b": 0.05, "a0": 10, "a1": 170},
                 {"c": (0, 0.995, 0.014), "a": 0.068, "b": 0.08, "a0": 8, "a1": 172},
                 {"c": (0, 1.025, 0.008), "a": 0.078, "b": 0.09, "a0": 10, "a1": 170}], 0.008, NIGHT, seg=20))
    vg = P(m, "visage_glow")
    vg.add(loft([S((-0.05, 1.0, 0.075), 0.003, 0.003), S((0.0, 0.99, 0.093), 0.003, 0.003), S((0.05, 1.0, 0.075), 0.003, 0.003)], PINK, nc=1))
    # veste croisée
    tg = jacket(m, NIGHT, 0.56, PINK, HAKAMA, wide=1.08)
    t = P(m, "torso")
    seam(t, tg, [(0.06, 0.92, 0), (0.0, 0.8, 0), (-0.06, 0.66, 0)], (0, 0, -1), col=CYAN, w=0.004)
    seam(t, tg, [(-0.06, 0.92, 0), (-0.02, 0.84, 0)], (0, 0, -1), col=CYAN, w=0.004)
    t.add(loft([S((0, 0.6, 0), 0.118, 0.084), S((0, 0.65, 0), 0.112, 0.08)], PINK, nc=2))  # obi
    t.add(box((0.08, 0.625, 0.07), (0.022, 0.03, 0.008), 0.004, NIGHT_L))
    lg = extra(m, "logo_glow", "torso")
    back_logo(lg, tg, 0.79, 0.07, CYAN)
    # sode : grandes plaques d'épaule
    for side, sx in sides():
        e = P(m, "epaule_" + side)
        for i in range(3):
            y = 0.9 - i * 0.042
            e.add(box((sx * (0.19 + 0.008 * i), y, 0.0), (0.012, 0.024, 0.07 + 0.004 * i), 0.006, NIGHT if i % 2 == 0 else NIGHT_L,
                      up=(sx * 0.35, 1, 0)))
        e.add(box((sx * 0.212, 0.81, 0.0), (0.006, 0.006, 0.08), 0.002, PINK, up=(sx * 0.35, 1, 0)))
        P(m, "epaule_%s_glow" % side).add(box((sx * 0.222, 0.86, 0.0), (0.002, 0.07, 0.004), 0.001, CYAN, up=(sx * 0.35, 1, 0)))
    arms(m, NIGHT, INK, wide=1.15, cuff=PINK, cuff_y=0.57)
    # hakama ample
    legs(m, HAKAMA, None, None, None, wide=1.0)
    for side, sx in sides():
        l = P(m, "leg_" + side)
        l.add(loft(smooth([S((sx * 0.072, 0.6, 0.0), 0.078, 0.084), S((sx * 0.08, 0.45, 0.004), 0.084, 0.09),
                           S((sx * 0.085, 0.36, 0.006), 0.084, 0.088)], 2), HAKAMA, nc=3))
        s = P(m, "shin_" + side)
        s.add(loft(smooth([S((sx * 0.084, 0.37, 0.006), 0.084, 0.088), S((sx * 0.086, 0.24, 0.0), 0.092, 0.094),
                           S((sx * 0.088, 0.13, -0.002), 0.098, 0.1, col=PINK), S((sx * 0.088, 0.12, -0.002), 0.098, 0.1)], 2), HAKAMA, nc=3))
        b = P(m, "jambe_" + side)
        x = sx * 0.077
        b.add(loft(smooth([S((x, 0.11, -0.01), 0.034, 0.036), S((x, 0.04, -0.01), 0.038, 0.05), S((x, 0.034, 0.06), 0.038, 0.034),
                           S((x, 0.03, 0.12), 0.024, 0.02)], 2), INK, nc=2))
        b.add(loft([S((x, 0.006, z), a, 0.006, 0.004) for z, a in ((-0.05, 0.032), (0.04, 0.04), (0.12, 0.022))], PINK, nc=1))
    # sabre au fourreau en travers du dos
    d = P(m, "dos")
    a0, a1 = Vector((-0.16, 0.56, -0.1)), Vector((0.2, 0.98, -0.12))
    d.add(loft([S(a0, 0.014, 0.01, 0.006), S(a0 + (a1 - a0) * 0.72, 0.014, 0.01, 0.006)], NIGHT_L, nc=2, ref=(0, 0, 1)))
    d.add(loft([S(a0 + (a1 - a0) * 0.72, 0.024, 0.024, 0.008), S(a0 + (a1 - a0) * 0.74, 0.024, 0.024, 0.008)], PINK, nc=2))
    dg = P(m, "dos_glow")
    dg.add(loft([S(a0 + (a1 - a0) * 0.745, 0.01, 0.01, 0.004), S(a1, 0.01, 0.01, 0.004)], CYAN, nc=2))
    d.add(loft([S((0.12, 0.9, -0.07), 0.003, 0.008), S((-0.1, 0.62, -0.09), 0.003, 0.008)], PINK, nc=1, ref=(0, 0, 1)))
    blaster(m, shell_col=NIGHT_L, stripe=PINK, metal=INK, glow=CYAN)
    return m


BUILDS = {"jo_chevalier": chevalier, "jo_magicienne": magicienne, "jo_samourai": samourai}


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(BUILDS)
    for nm in names:
        mdl = BUILDS[nm]()
        n = mdl.export(os.path.join(ROOT, "assets", "chars3d", nm + ".glb"))
        if n > 24000:
            print("ATTENTION : %s dépasse 24 000 triangles (%d)" % (nm, n))
