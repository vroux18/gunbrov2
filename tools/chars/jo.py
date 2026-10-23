"""Jo, Passeuse : combinaison blanche et orange, carré court bleu nuit à mèche turquoise,
lunettes de pilote sur le front, sac à réacteurs, blaster arrondi.
Regarde vers +Z ; sa droite est en -X. Hauteur totale environ 1,05."""
from sculpt import *

SKIN = "#F5BE98"
SUIT = "#F4F1EA"
SUIT_D = "#D6D1C6"
ORANGE = "#FF7A2F"
NAVY = "#1E2A4A"
HAIR = "#28346A"
TEAL = "#3CF2D8"
DARK = "#141828"
GUN = "#3A4258"
GUN_L = "#5A6478"
WHITE = "#FFFFFF"
BLUSH = "#F49088"
MOUTH = "#9A4A48"


def build():
    parts = []
    # ---------------- torse (pivot aux hanches)
    torso = Part("torso", pivot=(0, 0.36, 0), res=0.006)
    body = torso.piece(SUIT, tris=1800)
    body.add(ellipsoid((0, 0.47, 0), (0.165, 0.155, 0.128)))
    body.add(ellipsoid((0, 0.375, 0), (0.145, 0.07, 0.115)), k=0.05)
    body.add(ellipsoid((0, 0.56, -0.005), (0.155, 0.06, 0.118)), k=0.05)
    body.add(cyl((0, 0.612, 0), 0.08, 0.03, 0.02), k=0.02)
    torso.piece(ORANGE, tris=500).add(rbox((0, 0.49, 0.1), (0.092, 0.068, 0.04), 0.03))
    torso.piece(TEAL, tris=120).add(rbox((0, 0.51, 0.138), (0.03, 0.016, 0.008), 0.006))
    torso.piece(NAVY, tris=500).add(cyl((0, 0.37, 0), 0.152, 0.028, 0.014))
    torso.piece(GUN_L, tris=150).add(rbox((0, 0.37, 0.15), (0.036, 0.03, 0.014), 0.01))
    # sac à réacteurs dans le dos (-Z)
    pack = torso.piece(SUIT, tris=700)
    pack.add(rbox((0, 0.5, -0.15), (0.118, 0.11, 0.06), 0.045))
    torso.piece(ORANGE, tris=300).add(rbox((0, 0.555, -0.155), (0.122, 0.022, 0.064), 0.014))
    noz = torso.piece(GUN, tris=300)
    for x in (-0.062, 0.062):
        noz.add(cyl((x, 0.395, -0.165), 0.036, 0.034, 0.012))
    parts.append(torso)
    glow = Part("torso_glow", pivot=(0, 0.36, 0), parent="torso", res=0.005)
    g = glow.piece(TEAL, tris=160)
    for x in (-0.062, 0.062):
        g.add(cyl((x, 0.358, -0.165), 0.026, 0.01, 0.004))
    parts.append(glow)
    # ---------------- tête (pivot au cou)
    head = Part("head", pivot=(0, 0.62, 0), parent="torso", res=0.005)
    skin = head.piece(SKIN, tris=1600)
    skin.add(sphere((0, 0.85, 0.0), 0.212))
    skin.add(ellipsoid((0, 0.785, 0.045), (0.165, 0.125, 0.15)), k=0.06)
    skin.add(ellipsoid((0, 0.66, 0.0), (0.06, 0.05, 0.06)), k=0.04)  # cou
    # cheveux : calotte qui dégage le visage, frange en vague, mèches sur les côtés
    hair = head.piece(HAIR, tris=2200)
    hair.add(ellipsoid((0, 0.895, -0.03), (0.236, 0.205, 0.228)))
    hair.add(ellipsoid((0.2, 0.79, -0.035), (0.062, 0.13, 0.12), rot=(0, 0, 8)), k=0.03)
    hair.add(ellipsoid((-0.2, 0.79, -0.035), (0.062, 0.13, 0.12), rot=(0, 0, -8)), k=0.03)
    hair.sub(rbox((0, 0.775, 0.2), (0.182, 0.125, 0.13), 0.07), k=0.025)
    hair.add(ellipsoid((0.065, 0.99, 0.155), (0.165, 0.062, 0.095), rot=(22, 0, -16)), k=0.03)
    hair.add(ellipsoid((-0.12, 0.965, 0.15), (0.085, 0.052, 0.075), rot=(26, 0, 22)), k=0.03)
    hair.add(ellipsoid((0.0, 0.84, -0.2), (0.15, 0.12, 0.06)), k=0.04)
    hair.paint(ellipsoid((0.11, 1.005, 0.165), (0.055, 0.03, 0.07), rot=(22, 0, -16)), TEAL)
    # yeux, reflets, joues, bouche
    eyes = head.piece(DARK, tris=500, res=0.004)
    for x in (-0.074, 0.074):
        eyes.add(ellipsoid((x, 0.838, 0.186), (0.041, 0.057, 0.022)))
    glints = head.piece(WHITE, tris=200, res=0.003)
    for x in (-0.074, 0.074):
        glints.add(sphere((x + 0.015, 0.86, 0.203), 0.014))
        glints.add(sphere((x - 0.01, 0.82, 0.204), 0.007))
    blush = head.piece(BLUSH, tris=200, res=0.004)
    for x in (-0.11, 0.11):
        blush.add(ellipsoid((x, 0.782, 0.168), (0.03, 0.016, 0.02)))
    head.piece(MOUTH, tris=120, res=0.003).add(capsule((-0.02, 0.765, 0.198), (0.02, 0.765, 0.198), 0.008))
    # lunettes relevées : sangle, montures orange
    strap = head.piece(NAVY, tris=500)
    strap.add(torus((0, 0.945, -0.012), 0.226, 0.016, rot=(-16, 0, 0)))
    frames = head.piece(ORANGE, tris=500)
    for x in (-0.072, 0.072):
        frames.add(cyl((x, 1.0, 0.205), 0.064, 0.03, 0.014, rot=(58, 0, 0)))
    frames.add(rbox((-0.262, 0.83, 0.02), (0.026, 0.05, 0.045), 0.02))  # oreillette
    parts.append(head)
    lens = Part("head_glow", pivot=(0, 0.62, 0), parent="head", res=0.004)
    lp = lens.piece(TEAL, tris=260)
    for x in (-0.072, 0.072):
        lp.add(cyl((x, 1.012, 0.226), 0.046, 0.008, 0.004, rot=(58, 0, 0)))
    lp.add(capsule((-0.275, 0.8, 0.04), (-0.17, 0.765, 0.15), 0.008))
    parts.append(lens)
    # ---------------- bras (pivot à l'épaule ; au repos le bras pend vers -Y)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        arm = Part("arm_" + side, pivot=(sx * 0.19, 0.57, 0), parent="torso", res=0.006)
        arm.piece(SUIT, tris=500).add(capsule((sx * 0.2, 0.56, 0), (sx * 0.214, 0.37, 0.01), 0.05, 0.044))
        arm.piece(ORANGE, tris=400).add(ellipsoid((sx * 0.205, 0.588, 0), (0.077, 0.062, 0.077)))
        arm.piece(NAVY, tris=200).add(cyl((sx * 0.213, 0.395, 0.009), 0.05, 0.016, 0.006))
        arm.piece(ORANGE, tris=400).add(sphere((sx * 0.215, 0.33, 0.014), 0.058))
        parts.append(arm)
    # ---------------- blaster (enfant du bras droit ; au repos le canon pointe vers -Y comme le bras)
    gun = Part("gun", pivot=(-0.215, 0.33, 0.014), parent="arm_r", res=0.005)
    gun.piece(GUN, tris=500).add(rbox((-0.215, 0.275, 0.062), (0.036, 0.092, 0.05), 0.026))
    gun.piece(GUN_L, tris=300).add(cyl((-0.215, 0.196, 0.077), 0.028, 0.048, 0.01))
    gun.piece(ORANGE, tris=200).add(rbox((-0.215, 0.31, 0.112), (0.021, 0.03, 0.02), 0.01))
    parts.append(gun)
    gglow = Part("gun_glow", pivot=(-0.215, 0.33, 0.014), parent="gun", res=0.004)
    gg = gglow.piece(TEAL, tris=200)
    gg.add(cyl((-0.215, 0.145, 0.077), 0.02, 0.01, 0.004))
    gg.add(rbox((-0.252, 0.275, 0.062), (0.004, 0.05, 0.022), 0.003))
    parts.append(gglow)
    # ---------------- jambes (pivot à la hanche)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        leg = Part("leg_" + side, pivot=(sx * 0.08, 0.34, 0), parent="torso", res=0.006)
        leg.piece(SUIT_D, tris=500).add(capsule((sx * 0.08, 0.32, 0), (sx * 0.085, 0.12, 0.0), 0.062, 0.055))
        leg.piece(ORANGE, tris=200).add(cyl((sx * 0.085, 0.128, 0.0), 0.066, 0.014, 0.006))
        leg.piece(NAVY, tris=600).add(rbox((sx * 0.085, 0.06, 0.028), (0.068, 0.055, 0.1), 0.045))
        leg.piece(ORANGE, tris=300).add(rbox((sx * 0.085, 0.014, 0.028), (0.074, 0.014, 0.106), 0.012))
        parts.append(leg)
    return Character("jo", parts)
