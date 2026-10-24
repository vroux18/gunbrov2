"""Garde du Portique : soldat robot de la faction, tireur à distance (ennemi de base).
Casque rond à large visière rouge lumineuse (yeux clairs froncés) et crête, armure claire sur sous-couche
bleu nuit, bande rouge de faction sur le torse, grosses épaulières, fusil blaster anguleux tenu à deux mains.
Regarde vers +Z ; sa droite est en -X. Hauteur totale environ 1,2 (Jo : 1,05).

build(elite=True) donne la variante élite (accents lumineux or, épaulières dorées, plumet et cape courte) :
voir tools/chars/trooper_elite.py. Mêmes pièces et mêmes pivots pour les deux.

Technique : les plaques d'armure sont des coques (surface de base gonflée, creusée, bornée par des plans)
pour que leurs bords tombent franchement sur la sous-couche au lieu de l'effleurer (bords nets, pas de
moucheture au maillage allégé).
"""
from sculpt import *

PLATE = "#AFB9CF"   # armure claire (un cran sous #C8CEDC : vue du dessus, elle ne doit pas lire blanc)
PLATE_M = "#8490AB"  # armure moyenne
UNDER = "#2C3350"   # sous-couche sombre
UNDER_D = "#1C2136"  # creux, grilles, semelles
GLOVE = "#4A5370"
ORANGE = "#FF7A2F"
RED = "#FF1E14"   # lueur rouge franc : sans bleu, elle ne vire pas au rose quand elle pulse
EYE = "#FFE4DC"  # yeux dans la visière (lumineux)
GOLD = "#FF8410"  # lueur or (énergie ~1 : rendu proche de #FFA41C)
EYE_GOLD = "#FFF1D0"
GOLD_P = "#EE8530"  # or « matière » (épaulières, ornements éclairés) : or franc, pas jaune pâle
GOLD_D = "#B05A12"
CAPE = "#8A2440"

TRI = 0.71  # facteur global du budget de triangles (≤ 12 000)
SCALE = 1.06  # le garde est sculpté à l'échelle de Jo puis agrandi (hauteur finale ~1,2)

# repères partagés avec scripts/mobs/trooper.gd (avant SCALE)
HIP_Y = 0.37
TORSO_PIVOT = (0, 0.39, 0)
NECK = (0, 0.715, 0)
SHOULDER_X = 0.215
SHOULDER_Y = 0.64
HAND = (-0.235, 0.355, 0.02)  # main droite (pivot de l'arme)
GUN_Z = 0.075  # axe du fusil : devant la main au repos (au-dessus quand il vise)
HC = (0, 0.905, 0)  # centre du casque
VISOR_TILT = 3.5  # l'avant de la visière remonte : elle se lit depuis la caméra haute
VISOR_AXIS = 0.5  # distance derrière le centre du casque de l'axe des plans de la visière


_tri = TRI


def T(n):
    return max(60, int(n * _tri))


# ------------------------------------------------------------------ outils de forme
def union(shapes, k=0.0):
    def f(P):
        d = shapes[0].fn(P)
        for s in shapes[1:]:
            d = smin(d, s.fn(P), k)
        return d
    lo = np.min([s.lo for s in shapes], axis=0)
    hi = np.max([s.hi for s in shapes], axis=0)
    return Shape(f, lo, hi)


def shell(sh, out, inn):
    """Coque entre la surface de `sh` gonflée de `out` et gonflée de `inn` (inn < out)."""
    return Shape(lambda P: np.maximum(sh.fn(P) - out, inn - sh.fn(P)), sh.lo - out, sh.hi + out)


def offset(sh, d):
    """Forme pleine gonflée de d (ses faces de coupe restent cachées à l'intérieur du volume de base)."""
    return Shape(lambda P: sh.fn(P) - d, sh.lo - d, sh.hi + d)


def side(c, n):
    """Demi-espace du côté de la normale n (à soustraire pour couper ce côté)."""
    c = np.asarray(c, dtype=np.float64)
    n = np.asarray(n, dtype=np.float64)
    n = n / np.linalg.norm(n)
    return Shape(lambda P: -((P - c) @ n), c - 1, c + 1)


def tilted(angle_deg, c=HC):
    """Normale dans le plan YZ : 0° = haut (+Y), 90° = avant (+Z)."""
    a = math.radians(angle_deg)
    return side(c, (0.0, math.cos(a), math.sin(a)))


def visor_band(pc, half_front):
    """Borne une coque de casque à une bande frontale : deux plans qui pivotent autour d'un axe placé
    derrière la tête, si bien que la bande est haute de 2 x half_front devant et s'affine sur les côtés."""
    axis = (0.0, HC[1], HC[2] - VISOR_AXIS)
    a = math.atan(half_front / (VISOR_AXIS + 0.205))
    t = math.radians(VISOR_TILT)
    up, lo = t + a, t - a
    pc.sub(side(axis, (0, math.cos(up), -math.sin(up))), k=0.008)   # au-dessus de la bande
    pc.sub(side(axis, (0, -math.cos(lo), math.sin(lo))), k=0.008)   # en dessous
    pc.sub(side((0, 0, -0.03), (0, 0, -1)), k=0.03)  # arrière


def ridge(pc, front_deg, back_deg):
    """Arête du front (front_deg en avant du sommet) à la nuque (back_deg en arrière)."""
    pc.sub(tilted(front_deg + 90), k=0.008)
    pc.sub(tilted(-back_deg - 90), k=0.008)


def scale_parts(parts, k):
    """Agrandit uniformément le personnage (formes et pivots), sans changer la finesse du maillage."""
    def scaled(sh):
        return Shape(lambda P, f=sh.fn: f(P / k) * k, sh.lo * k, sh.hi * k)
    for part in parts:
        part.pivot = part.pivot * k
        for pc in part.pieces:
            pc.ops = [(op[0], scaled(op[1])) + tuple(op[2:]) for op in pc.ops]


# ------------------------------------------------------------------ personnage
def build(elite=False):
    global _tri
    _tri = TRI * (0.97 if elite else 1.0)  # l'élite a plumet et cape : même budget total
    glow = GOLD if elite else RED
    eye_col = EYE_GOLD if elite else EYE
    trim = GOLD_P if elite else PLATE_M
    pad_col = GOLD_P if elite else PLATE
    parts = []
    # ================= torse (pivot aux hanches)
    torso = Part("torso", pivot=TORSO_PIVOT, res=0.006)
    chest_sh = union([
        ellipsoid((0, 0.575, 0.008), (0.185, 0.135, 0.145)),
        ellipsoid((0, 0.66, -0.005), (0.16, 0.06, 0.125)),
        ellipsoid((0, 0.6, 0.06), (0.13, 0.09, 0.1)),
    ], k=0.04)
    torso.piece(PLATE_M, tris=T(650)).add(chest_sh)
    # plaque de poitrine claire (au-dessus de la bande)
    plate = torso.piece(PLATE, tris=T(700))
    plate.add(offset(chest_sh, 0.012))
    plate.sub(side((0, 0.612, 0), (0, -1, 0)), k=0.006)
    plate.sub(side((0, 0, -0.03), (0, 0, -1)), k=0.02)
    under = torso.piece(UNDER, tris=T(380))
    under.add(ellipsoid((0, 0.46, 0), (0.15, 0.085, 0.118)))
    under.add(ellipsoid((0, 0.395, 0), (0.15, 0.06, 0.115)), k=0.03)
    under.add(cyl((0, 0.712, 0), 0.07, 0.03, 0.015), k=0.02)  # cou
    torso.piece(GOLD_P if elite else PLATE, tris=T(300)).add(cyl((0, 0.425, 0), 0.158, 0.026, 0.013))  # ceinture
    torso.piece(ORANGE, tris=T(90)).add(rbox((0, 0.425, 0.158), (0.038, 0.026, 0.012), 0.01))
    # module dorsal (alimentation du fusil) ; l'élite porte une cape à la place
    if not elite:
        torso.piece(PLATE, tris=T(260)).add(rbox((0, 0.575, -0.15), (0.115, 0.095, 0.055), 0.04))
        vents = torso.piece(UNDER_D, tris=T(150))
        for x in (-0.055, 0.055):
            vents.add(cyl((x, 0.5, -0.17), 0.03, 0.03, 0.01))
    # épaulières (fixées au torse : le bras pivote dessous), deux lames superposées
    pads = torso.piece(pad_col, tris=T(900))
    lames = torso.piece(PLATE_M if not elite else GOLD_D, tris=T(600))
    for sx in (-1.0, 1.0):
        pads.add(ellipsoid((sx * 0.232, 0.683, 0.0), (0.1, 0.055, 0.104), rot=(0, 0, -sx * 20)))
        lames.add(ellipsoid((sx * 0.258, 0.638, 0.0), (0.078, 0.045, 0.092), rot=(0, 0, -sx * 32)))
    if elite:
        # cape courte dans le dos, attachée sous les épaulières
        cape = torso.piece(CAPE, tris=T(560))
        # cône évasé vers le bas (tissu), aplati d'avant en arrière, ouvert devant
        cone = capsule((0, 0.68, -0.03), (0, 0.33, -0.075), 0.175, 0.245)
        flat = Shape(lambda P, f=cone.fn: f(P * np.array((1.0, 1.0, 1.35)) + np.array((0, 0, -0.03 * 0.35))) / 1.15, cone.lo, cone.hi)
        cape.add(shell(flat, 0.0, -0.016))
        cape.sub(side((0, 0, -0.085), (0, 0, 1)), k=0.02)
        cape.sub(side((0, 0.672, 0), (0, 1, 0)), k=0.02)
        cape.sub(side((0, 0.35, 0), (0, -1, -0.25)), k=0.02)
        cape.add(cyl((0, 0.672, -0.03), 0.17, 0.012, 0.008), k=0.015)  # col
        torso.piece(GOLD_P, tris=T(140)).add(sphere((-0.15, 0.66, 0.06), 0.03)).add(sphere((0.15, 0.66, 0.06), 0.03))
    parts.append(torso)
    tg = Part("torso_glow", pivot=TORSO_PIVOT, parent="torso", res=0.004)
    band = tg.piece(glow, tris=T(500))
    band.add(offset(chest_sh, 0.02))
    band.sub(side((0, 0.6, 0), (0, 1, 0)), k=0.005)
    band.sub(side((0, 0.562, 0), (0, -1, 0)), k=0.005)
    band.sub(side((0, 0, -0.03), (0, 0, -1)), k=0.02)
    band.add(rbox((0, 0.581, 0.165), (0.03, 0.03, 0.014), 0.012, rot=(0, 0, 45)), k=0.005)  # écusson
    if not elite:
        led = tg.piece(glow, tris=T(100))
        for x in (-0.055, 0.055):
            led.add(cyl((x, 0.478, -0.17), 0.019, 0.006, 0.003))
    parts.append(tg)
    # ================= tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="torso", res=0.005)
    helm_sh = union([sphere(HC, 0.205), ellipsoid((0, 0.835, 0.012), (0.182, 0.11, 0.172))], k=0.05)
    helm = head.piece(PLATE, tris=T(1300))
    helm.add(helm_sh)
    # mentonnière plus foncée
    chin = head.piece(PLATE_M, tris=T(400))
    chin.add(offset(helm_sh, 0.008))
    chin.sub(side((0, 0.79, 0), (0, 1, 0.25)), k=0.005)
    # cadre sombre de la visière : coque bornée par deux plans inclinés (avant relevé)
    frame = head.piece(UNDER, tris=T(600))
    frame.add(shell(sphere(HC, 0.205), 0.013, -0.01))
    visor_band(frame, 0.112)
    grille = head.piece(UNDER_D, tris=T(160))
    for x in (-0.03, 0.0, 0.03):
        grille.add(capsule((x, 0.795, 0.178), (x, 0.77, 0.166), 0.009))
    # crête : arête qui court du front à la nuque
    crest = head.piece(UNDER, tris=T(400))
    crest_sh = torus(HC, 0.199, 0.03, rot=(0, 0, 90))
    crest.add(crest_sh)
    crest.sub(sphere(HC, 0.17))
    ridge(crest, 38, 100)
    if elite:
        # plumet : brosse arrondie au-dessus de la crête
        plume = head.piece(CAPE, tris=T(560))
        plume.add(ellipsoid((0, 1.09, -0.06), (0.04, 0.085, 0.2), rot=(-8, 0, 0)))
        plume.add(ellipsoid((0, 1.0, -0.21), (0.036, 0.08, 0.06), rot=(25, 0, 0)), k=0.05)
    # oreillettes
    ears = head.piece(trim, tris=T(300))
    for sx in (-1.0, 1.0):
        ears.add(cyl((sx * 0.198, 0.85, -0.05), 0.056, 0.03, 0.013, rot=(0, 0, 90)))
    # antenne (côté gauche), pointe orange
    head.piece(UNDER_D, tris=T(120)).add(capsule((0.22, 0.87, -0.07), (0.25, 1.05, -0.12), 0.011))
    head.piece(GOLD_P if elite else ORANGE, tris=T(120)).add(sphere((0.252, 1.06, -0.122), 0.024))
    parts.append(head)
    hg = Part("head_glow", pivot=NECK, parent="head", res=0.0035)
    vis = hg.piece(glow, tris=T(700))
    vis.add(shell(sphere(HC, 0.205), 0.024, 0.0))
    visor_band(vis, 0.088)
    # yeux clairs, légèrement froncés
    eyes = hg.piece(eye_col, tris=T(220), res=0.003)
    for sx in (-1.0, 1.0):
        eyes.add(ellipsoid((sx * 0.07, 0.948, 0.216), (0.035, 0.021, 0.022), rot=(-12, sx * 18, sx * 14)))
    if not elite:
        strip = hg.piece(glow, tris=T(300))
        strip.add(offset(crest_sh, 0.008))
        strip.sub(sphere(HC, 0.2))
        strip.sub(side((0.013, 0, 0), (1, 0, 0)), k=0.004)
        strip.sub(side((-0.013, 0, 0), (-1, 0, 0)), k=0.004)
        ridge(strip, 33, 94)
    parts.append(hg)
    # ================= bras (pivot à l'épaule ; au repos le bras pend vers -Y)
    for side_name, sx in (("r", -1.0), ("l", 1.0)):
        arm = Part("arm_" + side_name, pivot=(sx * SHOULDER_X, SHOULDER_Y, 0), parent="torso", res=0.006)
        hx = sx * 0.235
        arm_sh = capsule((sx * 0.218, 0.635, 0), (hx, 0.42, 0.015), 0.047, 0.042)
        arm.piece(UNDER, tris=T(300)).add(arm_sh)
        guard = arm.piece(PLATE_M, tris=T(260))
        guard.add(offset(arm_sh, 0.016))
        guard.sub(side((0, 0.505, 0), (0, 1, 0)), k=0.006)
        guard.sub(side((0, 0.405, 0), (0, -1, 0)), k=0.006)
        arm.piece(GLOVE, tris=T(260)).add(sphere((hx, 0.355, 0.02), 0.05))
        parts.append(arm)
    # ================= fusil blaster (enfant du bras droit ; au repos le canon pointe vers -Y,
    # le dessus de l'arme vers +Z : il passe vers le haut quand le garde épaule)
    hx, hy, hz = HAND
    gz = hz + GUN_Z
    gun = Part("gun", pivot=HAND, parent="arm_r", res=0.0045)
    body = gun.piece(UNDER, tris=T(500))
    body.add(rbox((hx, hy - 0.06, gz), (0.044, 0.13, 0.05), 0.02))  # carcasse
    body.add(rbox((hx, hy + 0.0, hz + 0.01), (0.024, 0.035, 0.04), 0.014), k=0.012)  # poignée
    body.add(rbox((hx, hy - 0.36, gz + 0.008), (0.02, 0.07, 0.02), 0.009))  # canon
    shell_g = gun.piece(PLATE_M, tris=T(500))
    shell_g.add(rbox((hx, hy - 0.25, gz + 0.006), (0.038, 0.09, 0.04), 0.016))  # garde-main
    shell_g.add(rbox((hx, hy + 0.12, gz - 0.008), (0.032, 0.075, 0.048), 0.022, rot=(-10, 0, 0)))  # crosse
    gun.piece(PLATE, tris=T(250)).add(rbox((hx, hy - 0.07, gz + 0.05), (0.032, 0.1, 0.02), 0.012))  # capot
    gun.piece(ORANGE, tris=T(100)).add(rbox((hx, hy - 0.11, gz - 0.06), (0.02, 0.03, 0.03), 0.012))  # chargeur
    parts.append(gun)
    muzzle = np.array((hx, hy - 0.435, gz + 0.008))
    # pivot choisi pour que rig3d.muzzle_position() (pivot + (0, -0.2, 0.06)) tombe à la bouche du canon
    # (décalage divisé par SCALE : il doit valoir exactement (0, 0.2, -0.06) une fois le garde agrandi)
    gg = Part("gun_glow", pivot=tuple(muzzle + np.array((0, 0.2, -0.06)) / SCALE), parent="gun", res=0.003)
    gp = gg.piece(glow, tris=T(400))
    gp.add(cyl((hx, hy - 0.42, gz + 0.008), 0.026, 0.012, 0.005))
    gp.add(rbox((hx, hy - 0.25, gz + 0.048), (0.012, 0.075, 0.006), 0.004))  # bande de visée (dessus)
    for sx in (-1.0, 1.0):
        gp.add(rbox((hx + sx * 0.041, hy - 0.25, gz + 0.006), (0.006, 0.06, 0.013), 0.004))
    parts.append(gg)
    # ================= jambes (pivot à la hanche)
    for side_name, sx in (("r", -1.0), ("l", 1.0)):
        lx = sx * 0.095
        leg = Part("leg_" + side_name, pivot=(lx, HIP_Y, 0), parent="torso", res=0.006)
        leg_sh = capsule((lx, 0.35, 0), (lx, 0.13, 0.0), 0.06, 0.054)
        leg.piece(UNDER, tris=T(300)).add(leg_sh)
        shin = leg.piece(PLATE, tris=T(560))
        shin.add(offset(leg_sh, 0.017))
        shin.sub(side((0, 0.27, 0), (0, 1, 0.35)), k=0.006)
        shin.sub(side((0, 0, -0.005), (0, 0, -1)), k=0.01)
        shin.sub(side((0, 0.158, 0), (0, -1, 0)), k=0.006)
        shin.add(sphere((lx, 0.272, 0.05), 0.038), k=0.015)  # genouillère
        boot = leg.piece(UNDER, tris=T(400))
        boot.add(rbox((lx, 0.07, 0.03), (0.075, 0.062, 0.106), 0.05))
        boot.add(cyl((lx, 0.135, 0.0), 0.062, 0.02, 0.01), k=0.01)
        leg.piece(PLATE_M, tris=T(200)).add(rbox((lx, 0.016, 0.03), (0.08, 0.016, 0.111), 0.012))
        leg.piece(GOLD if elite else ORANGE, tris=T(80)).add(rbox((lx, 0.09, 0.136), (0.03, 0.012, 0.006), 0.005))
        parts.append(leg)
    scale_parts(parts, SCALE)
    return Character("trooper_elite" if elite else "trooper", parts)
