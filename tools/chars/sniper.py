"""Vigie (code « sniper ») : tireuse d'élite robot de la sécurité de la station.
Silhouette élancée (plus grande et plus fine que le Garde) : longues jambes à genouillères, taille étroite,
buste court, tête ronde à GRANDE lentille-viseur violette (iris, pupille, reflet : un regard, pas une lampe),
télémètre et antenne à pointe violette, capuchon de casque, épaulières et grande cape violets (lisibles du
dessus), très long fusil de
précision à lunette et bobines violettes, tenu à deux mains.
Regarde vers +Z ; sa droite est en -X. Hauteur ~1,3 (Jo : 1,10).

Parts (pivots) : pelvis (racine, hanches) > chest (taille) > head (cou) > head_glow (lentille, pivot au
centre de la lentille) ; chest > cape (col), chest_glow, arm_r/arm_l (épaule) > fore_r/fore_l (coude, avec
la main) ; chest > gun (poignée, canon vers +Z au repos) > gun_glow (lunette, bobines) + muzzle_glow (bout
du canon) ; pelvis > leg_r/leg_l (hanche) > shin_r/shin_l (genou, avec le pied).
Variante élite (build(elite=True), tools/chars/sniper_elite.py) : la lentille reste violette (signature),
accents lumineux et garnitures or, crête dorée sur le casque, pointes dorées aux épaulières, ourlet doré.
"""
import math

import trimesh
from skimage import measure

from sculpt import *
from sculpt import Part as _Part

PLATE = "#C8CEDC"
PLATE_M = "#9AA4B6"
UNDER = "#2D2B5C"   # sous-couche bleu nuit teintée violet (propre à la Vigie)
UNDER_D = "#1C1C3C"
JOINT = "#46467A"
CAPE = "#6A36D6"
CAPE_D = "#43209C"
PAINT = "#7A5CF0"   # peinture violette
VIO_HULL = "#7446E0"  # coque violette : capuchon du casque et épaulières (la signature vue du dessus)
VIO = "#6A5CFF"     # lueur violette (énergie ~1 : rendu proche de #8E6BFF, sans virer au lavande)
VIO_RIM = "#4A2FE0"  # bord de la lentille : plus saturé, reste violet une fois lumineux
VIO_IRIS = "#6E58FF"
PUPIL = "#120A2A"
WHITE = "#FFFFFF"
GOLD = "#FF8410"     # lueur or (rendu proche de #FFA41C)
GOLD_P = "#EE8530"   # or franc, pas jaune pâle
GOLD_D = "#A8661E"

# repères partagés avec scripts/mobs/sniper.gd
HIP_Y = 0.62
HIP_X = 0.08
KNEE_Y = 0.345
ANKLE_Y = 0.09
WAIST = (0.0, 0.69, 0.0)
NECK = (0.0, 1.0, 0.0)
HR = 0.142  # rayon de la tête
HC = (0.0, 1.13, 0.0)  # centre de la tête
SH_X = 0.162
SH_Y = 0.94
EL = (0.176, 0.775, -0.012)  # coude (côté gauche, +X)
HAND = (0.182, 0.6, 0.02)
GRIP = (-0.085, 0.88, 0.17)  # poignée du fusil (main droite), canon vers +Z
FORE_GRIP = 0.33  # main gauche sous le garde-main, à cette distance devant la poignée
MUZZLE_Z = 0.74  # bout du canon devant la poignée
BARREL_Y = 0.058  # axe du canon au-dessus de la poignée
LENS_TILT = 22.0  # la lentille regarde un peu vers le haut (se lit depuis la caméra haute)
TRI = 0.57  # facteur global du budget de triangles (~9 000)


class Part(_Part):
    """Normales exactes du champ de distance (lisses malgré l'allègement), comme tools/chars/drone.py,
    avec l'allègement itératif de sculpt.simplify_to."""

    def _piece_mesh(self, pc):
        res = pc.res or self.res
        lo, hi = pc.bounds()
        n = np.ceil((hi - lo) / res).astype(int) + 1
        xs = [np.linspace(lo[i], lo[i] + (n[i] - 1) * res, n[i]) for i in range(3)]
        G = np.stack(np.meshgrid(*xs, indexing="ij"), axis=-1).reshape(-1, 3)
        vol = pc.sdf(G).reshape(n)
        if vol.min() > 0 or vol.max() < 0:
            return None
        verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(res,) * 3)
        verts = verts + lo
        # miettes de quelques triangles (champ presque nul au ras d'une soustraction) : elles bloquent
        # l'allègement, on les retire
        raw = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        comps = raw.split(only_watertight=False)
        if len(comps) > 1:
            raw = trimesh.util.concatenate([cm for cm in comps if len(cm.faces) >= 40])
            verts, faces = np.asarray(raw.vertices), np.asarray(raw.faces)
        if len(faces) > pc.tris:
            verts, faces = simplify_to(verts, faces, pc.tris)
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = 1e-3
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V)
        occ = np.ones(len(V))
        for dist, w in ((0.02, 0.5), (0.05, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.8, 1.0) ** w
        y = V[:, 1]
        grad = 0.92 + 0.08 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        c = np.clip(col * (occ * grad)[:, None], 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm, N

    def mesh(self):
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        tm = trimesh.util.concatenate([o[0] for o in out])
        normals = np.concatenate([o[1] for o in out])
        tm.apply_translation(-self.pivot)
        tm.vertex_normals = normals
        return tm


# ------------------------------------------------------------------ outils de forme
def union(shapes, k=0.0):
    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = smin(d, s(P), k)
        return d
    return Shape(f, np.min([s.lo for s in shapes], axis=0) - k, np.max([s.hi for s in shapes], axis=0) + k)


def inter(a, b):
    return Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def grow(a, d):
    return Shape(lambda P: a(P) - d, a.lo - max(d, 0.0), a.hi + max(d, 0.0))


def shell(sh, out, inn):
    return Shape(lambda P: np.maximum(sh(P) - out, inn - sh(P)), sh.lo - out, sh.hi + out)


def side(c, n):
    """Demi-espace du côté de la normale n (à soustraire pour couper ce côté)."""
    c = np.asarray(c, dtype=np.float64)
    n = np.asarray(n, dtype=np.float64)
    n = n / np.linalg.norm(n)
    return Shape(lambda P: -((P - c) @ n), c - 2, c + 2)


def slab(c, n, h):
    """Tranche d'épaisseur 2h autour du plan (c, n)."""
    c = np.asarray(c, dtype=np.float64)
    n = np.asarray(n, dtype=np.float64)
    n = n / np.linalg.norm(n)
    return Shape(lambda P: np.abs((P - c) @ n) - h, c - 2, c + 2)


def add(a, b):
    return (np.asarray(a, dtype=np.float64) + np.asarray(b, dtype=np.float64)).tolist()


def build(elite=False):
    q = 0.93 if elite else 1.0  # l'élite a plus d'ornements : même budget total

    def T(n):
        return max(50, int(n * q * TRI))

    glow2 = GOLD if elite else VIO  # lumières secondaires (lignes, oculaire, antenne)
    trim = GOLD_P if elite else PLATE_M
    parts = []

    # ================================================================== bassin (racine, pivot aux hanches)
    pelvis = Part("pelvis", pivot=(0, HIP_Y, 0), res=0.005)
    pel = pelvis.piece(UNDER, tris=T(420))
    pel.add(ellipsoid((0, 0.625, -0.005), (0.122, 0.072, 0.088)))
    pel.add(ellipsoid((0, 0.675, 0.0), (0.082, 0.05, 0.066)), k=0.03)
    for sx in (-1, 1):
        pel.add(sphere((sx * HIP_X, HIP_Y - 0.01, 0), 0.064), k=0.03)
    # plaques de hanche claires (jupette courte)
    hp = pelvis.piece(PLATE_M, tris=T(360))
    for sx in (-1, 1):
        hp.add(ellipsoid((sx * 0.112, 0.62, 0.005), (0.052, 0.068, 0.078), rot=(0, 0, sx * 14)))
    hp.add(rbox((0, 0.625, 0.074), (0.058, 0.046, 0.026), 0.022, rot=(-8, 0, 0)), k=0.01)
    pelvis.piece(trim, tris=T(200)).add(cyl((0, 0.66, 0), 0.1, 0.014, 0.008))  # ceinture
    parts.append(pelvis)

    # ================================================================== buste (pivot à la taille)
    chest = Part("chest", pivot=WAIST, parent="pelvis", res=0.005)
    chest_sh = union([
        ellipsoid((0, 0.85, 0.0), (0.138, 0.12, 0.102)),
        ellipsoid((0, 0.915, -0.008), (0.155, 0.062, 0.1)),
        ellipsoid((0, 0.87, 0.04), (0.102, 0.086, 0.077)),
    ], k=0.04)
    waist = chest.piece(UNDER, tris=T(260))
    waist.add(capsule((0, 0.69, 0), (0, 0.78, 0), 0.064, 0.078))
    waist.add(cyl((0, 0.985, 0), 0.044, 0.03, 0.012), k=0.02)  # cou
    chest.piece(PLATE_M, tris=T(420)).add(chest_sh)
    plate = chest.piece(PLATE, tris=T(520))
    plate.add(grow(chest_sh, 0.01))
    plate.sub(side((0, 0, -0.02), (0, 0, -1)), k=0.02)
    plate.sub(side((0, 0.775, 0), (0, -1, 0.3)), k=0.01)
    plate.sub(slab((0, 0, 0), (1, 0, 0), 0.008), k=0.004)  # rainure (ligne de lumière dans chest_glow)
    # épaulières rondes, fixées au buste
    pads = chest.piece(VIO_HULL, tris=T(420))
    for sx in (-1, 1):
        pads.add(ellipsoid((sx * 0.186, 0.965, -0.005), (0.08, 0.052, 0.082), rot=(0, 0, -sx * 22)))
    chest.piece(trim, tris=T(260)).add(union([ellipsoid((sx * 0.205, 0.936, -0.005), (0.064, 0.034, 0.072), rot=(0, 0, -sx * 34)) for sx in (-1, 1)]))
    if elite:
        spk = chest.piece(GOLD_P, tris=T(280))
        for sx in (-1, 1):
            spk.add(capsule((sx * 0.21, 0.995, -0.01), (sx * 0.295, 1.045, -0.03), 0.024, 0.006))
            spk.add(capsule((sx * 0.215, 0.99, -0.05), (sx * 0.285, 1.025, -0.1), 0.018, 0.005))
    chest.piece(UNDER_D, tris=T(160)).add(rbox((0, 0.84, -0.107), (0.052, 0.07, 0.03), 0.025))  # batterie dorsale
    parts.append(chest)

    cg = Part("chest_glow", pivot=WAIST, parent="chest", res=0.0035)
    line = cg.piece(glow2, tris=T(180))
    line.add(inter(grow(chest_sh, 0.006), slab((0, 0, 0), (1, 0, 0), 0.005)))
    line.sub(side((0, 0, -0.02), (0, 0, -1)), k=0.01)
    line.sub(side((0, 0.79, 0), (0, -1, 0)), k=0.006)
    line.add(rbox((0, 0.905, 0.117), (0.024, 0.024, 0.012), 0.009, rot=(0, 0, 45)), k=0.004)  # écusson
    cg.piece(glow2, tris=T(80)).add(rbox((0, 0.84, -0.139), (0.032, 0.045, 0.006), 0.005))  # voyant dorsal
    parts.append(cg)

    # capeline courte (pivot au col, flotte en marche)
    cape = Part("cape", pivot=(0, 0.99, -0.02), parent="chest", res=0.005)
    # (grande : elle couvre le dos et se lit du dessus)
    cone = capsule((0, 1.0, -0.01), (0, 0.63, -0.085), 0.15, 0.285)
    flat = Shape(lambda P, f=cone: f(P * np.array((1.0, 1.0, 1.45)) + np.array((0, 0, -0.01 * 0.45))) / 1.2,
                 cone.lo, cone.hi)
    cp = cape.piece(CAPE, tris=T(640))
    cp.add(shell(flat, 0.0, -0.015))
    cp.sub(side((0, 0, -0.03), (0, 0, 1)), k=0.02)  # ouverte devant
    cp.sub(side((0, 0.99, 0), (0, 1, 0)), k=0.015)
    cp.sub(side((0, 0.64, 0), (0, -1, -0.35)), k=0.015)
    cp.add(torus((0, 0.995, -0.005), 0.088, 0.019), k=0.01)  # col roulé
    hem = cape.piece(GOLD_P if elite else CAPE_D, tris=T(260))  # ourlet (pièce à part : bord net)
    hem.add(shell(flat, 0.003, -0.018))
    hem.sub(side((0, 0, -0.03), (0, 0, 1)), k=0.02)
    hem.sub(side((0, 0.695, -0.1), (0, 1, 0.35)), k=0.004)
    hem.sub(side((0, 0.64, 0), (0, -1, -0.35)), k=0.015)
    parts.append(cape)

    # ================================================================== tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="chest", res=0.004)
    head_sh = union([
        ellipsoid(HC, (HR, HR * 0.97, HR * 0.98)),
        ellipsoid(add(HC, (0, -0.05, 0.012)), (HR * 0.82, HR * 0.58, HR * 0.86)),
    ], k=0.04)
    td = math.radians(LENS_TILT)
    eye_dir = np.array([0.0, math.sin(td), math.cos(td)])
    up = np.array([0.0, math.cos(td), -math.sin(td)])
    ec = np.asarray(HC) + eye_dir * (HR * 0.83)  # centre de la face de la lentille
    rx = 90 - LENS_TILT
    LR = 0.086  # rayon du fût de la lentille
    helm = head.piece(PLATE, tris=T(680))
    helm.add(head_sh)
    helm.sub(cyl((ec - eye_dir * 0.01).tolist(), LR - 0.002, 0.05, 0.01, rot=(rx, 0, 0)), k=0.01)
    # capuchon violet : dessus et arrière du casque (la face claire autour de la lentille reste lisible)
    hood = head.piece(VIO_HULL, tris=T(460))
    hood.add(grow(head_sh, 0.011))  # assez épais : le casque clair ne transperce pas après allègement
    hood.sub(side(add(HC, (0, 0.028, 0)), (0, -1, 0.62)), k=0.006)
    hood.sub(cyl((ec - eye_dir * 0.01).tolist(), LR + 0.012, 0.06, 0.01, rot=(rx, 0, 0)), k=0.01)
    # dessous de la tête et joues plus foncés
    jaw = head.piece(PLATE_M, tris=T(280))
    jaw.add(grow(head_sh, 0.006))
    jaw.sub(side(add(HC, (0, -0.06, 0)), (0, 1, 0.55)), k=0.006)
    jaw.sub(cyl((ec - eye_dir * 0.01).tolist(), LR + 0.006, 0.06, 0.01, rot=(rx, 0, 0)), k=0.01)
    # crête peinte (violette, vue de dessus) ; l'élite a une vraie crête dorée
    if elite:
        crest = head.piece(GOLD_P, tris=T(380), res=0.0035)
        # lame dorée du front à la nuque, découpée en trois pointes
        crest.add(inter(slab((0, 0, 0), (1, 0, 0), 0.01), sphere(add(HC, (0, 0.0, -0.02)), HR + 0.06)))
        crest.sub(sphere(HC, HR * 0.85))
        crest.sub(side(HC, (0, -1, 1.1)), k=0.006)
        crest.sub(side(add(HC, (0, -0.01, 0)), (0, -1, -0.45)), k=0.006)
        for ang in (-8.0, -52.0):
            a = math.radians(ang)
            crest.sub(sphere(add(HC, (0, (HR + 0.08) * math.cos(a), -0.02 + (HR + 0.08) * math.sin(a))), 0.036), k=0.003)
    else:
        # nervure claire du front à la nuque (sur le capuchon violet)
        rib = head.piece(PLATE, tris=T(220), res=0.0035)
        rib.add(torus(HC, HR * 0.985 + 0.011, 0.017, rot=(0, 0, 90)))
        rib.sub(sphere(HC, HR * 0.8))
        rib.sub(side(HC, (0, -1, 0.75)), k=0.01)
        rib.sub(side(add(HC, (0, -0.03, 0)), (0, -1, -0.6)), k=0.01)
    # fût de la lentille : court cylindre sombre qui dépasse de la face (un viseur, pas un œil plat)
    bez = head.piece(UNDER, tris=T(440), res=0.003)
    bez.add(cyl((ec - eye_dir * 0.012).tolist(), LR, 0.028, 0.013, rot=(rx, 0, 0)))
    bez.sub(cyl((ec + eye_dir * 0.022).tolist(), LR - 0.018, 0.03, 0.006, rot=(rx, 0, 0)), k=0.006)
    bez.add(torus((ec + eye_dir * 0.014).tolist(), LR - 0.009, 0.012, rot=(rx, 0, 0)), k=0.004)
    # pare-soleil : arc au-dessus de la lentille (air concentré, pas d'oreilles)
    shade = head.piece(trim if elite else JOINT, tris=T(200), res=0.0035)
    arc = torus((ec + eye_dir * 0.016).tolist(), LR + 0.004, 0.014, rot=(rx, 0, 0))
    shade.add(inter(arc, side((ec + up * 0.03).tolist(), -up)))
    # oreillettes ; télémètre à droite (-X), antenne à gauche (+X)
    ears = head.piece(UNDER, tris=T(220))
    for sx in (-1, 1):
        ears.add(cyl(add(HC, (sx * HR * 0.97, -0.005, -0.012)), 0.05, 0.02, 0.01, rot=(0, 0, 90)))
    rgf = head.piece(PLATE_M, tris=T(220), res=0.0035)
    rgf.add(rbox(add(HC, (-HR - 0.022, 0.018, 0.03)), (0.017, 0.03, 0.064), 0.014))
    rgf.add(cyl(add(HC, (-HR - 0.022, 0.018, 0.092)), 0.019, 0.012, 0.005, rot=(90, 0, 0)), k=0.006)
    ant = head.piece(UNDER_D, tris=T(110), res=0.0035)
    a0 = add(HC, (HR * 0.97 + 0.012, 0.035, -0.04))
    a1 = add(HC, (HR + 0.035, 0.225, -0.095))
    ant.add(capsule(a0, a1, 0.01, 0.0065))
    ant.add(cyl(a0, 0.022, 0.012, 0.005, rot=(0, 0, 80)), k=0.006)
    parts.append(head)

    # lentille-viseur (pivot au centre : elle pulse en place)
    hg = Part("head_glow", pivot=(ec + eye_dir * 0.01).tolist(), parent="head", res=0.0028)
    lens = hg.piece(VIO_RIM, tris=T(340))
    lens.add(ellipsoid((ec + eye_dir * 0.004).tolist(), (LR - 0.016, 0.028, LR - 0.016), rot=(rx, 0, 0)))
    lens.paint(cyl((ec + eye_dir * 0.03).tolist(), LR - 0.034, 0.03, 0.0, rot=(rx, 0, 0)), VIO_IRIS)
    lens.paint(torus((ec + eye_dir * 0.026).tolist(), 0.034, 0.004, rot=(rx, 0, 0)), VIO_RIM)  # bague de mise au point
    pup = hg.piece(PUPIL, tris=T(100))
    pup.add(ellipsoid((ec + eye_dir * 0.028).tolist(), (0.025, 0.009, 0.025), rot=(rx, 0, 0)))
    gl = hg.piece(WHITE, tris=T(80))
    gl.add(ellipsoid((ec + eye_dir * 0.028 + up * 0.034 + np.array([0.028, 0, 0])).tolist(), (0.015, 0.006, 0.01), rot=(rx, 0, -35)))
    gl.add(sphere((ec + eye_dir * 0.024 - up * 0.032 - np.array([0.03, 0, 0])).tolist(), 0.006))
    tip = hg.piece(GOLD if elite else VIO_RIM, tris=T(90))
    tip.add(sphere(a1, 0.02))
    tip.add(cyl(add(HC, (-HR - 0.022, 0.018, 0.104)), 0.013, 0.004, 0.002, rot=(90, 0, 0)))  # télémètre
    parts.append(hg)

    # ================================================================== bras (épaule) + avant-bras (coude)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        sh_p = (sx * SH_X, SH_Y, 0.0)
        el = (sx * EL[0], EL[1], EL[2])
        hd = (sx * HAND[0], HAND[1], HAND[2])
        arm = Part("arm_" + nm, pivot=sh_p, parent="chest", res=0.0045)
        arm.piece(UNDER, tris=T(150)).add(capsule(sh_p, el, 0.04, 0.034))
        sl = arm.piece(PLATE_M, tris=T(180))
        sl.add(capsule(add(sh_p, (sx * 0.003, -0.05, 0)), add(el, (0, 0.045, 0)), 0.047, 0.041))
        parts.append(arm)
        fore = Part("fore_" + nm, pivot=el, parent="arm_" + nm, res=0.0045)
        fore.piece(JOINT, tris=T(80)).add(sphere(el, 0.037))
        fore.piece(UNDER, tris=T(110)).add(capsule(el, hd, 0.033, 0.03))
        br = fore.piece(PLATE, tris=T(190))
        br.add(capsule(add(el, (0, -0.042, 0.003)), add(hd, (0, 0.045, 0)), 0.04, 0.045))
        fore.piece(trim, tris=T(80)).add(cyl(add(hd, (0, 0.045, 0)), 0.047, 0.009, 0.004))
        fore.piece(JOINT, tris=T(150)).add(ellipsoid(add(hd, (0, -0.022, 0.005)), (0.036, 0.044, 0.038)))
        parts.append(fore)

    # ================================================================== fusil de précision (poignée, canon +Z)
    gx, gy, gz = GRIP
    by = gy + BARREL_Y
    gun = Part("gun", pivot=GRIP, parent="chest", res=0.004)
    dark = gun.piece(UNDER, tris=T(460))
    dark.add(rbox((gx, gy - 0.005, gz - 0.005), (0.019, 0.048, 0.024), 0.013, rot=(-18, 0, 0)))  # poignée
    dark.add(rbox((gx, by, gz + 0.03), (0.028, 0.036, 0.15), 0.016), k=0.01)  # boîtier
    dark.add(rbox((gx, by - 0.06, gz + 0.08), (0.016, 0.034, 0.03), 0.011, rot=(12, 0, 0)), k=0.006)  # chargeur
    dark.add(capsule((gx, by + 0.004, gz + 0.38), (gx, by + 0.004, gz + MUZZLE_Z - 0.04), 0.0155))  # canon
    # frein de bouche
    brake = gun.piece(UNDER_D, tris=T(170))
    brake.add(cyl((gx, by + 0.004, gz + MUZZLE_Z - 0.028), 0.026, 0.03, 0.009, rot=(90, 0, 0)))
    brake.sub(rbox((gx, by + 0.004, gz + MUZZLE_Z - 0.028), (0.04, 0.007, 0.011), 0.003), k=0.002)
    # garde-main et crosse squelette clairs
    light = gun.piece(PLATE, tris=T(600))
    light.add(rbox((gx, by - 0.004, gz + 0.27), (0.027, 0.031, 0.125), 0.018))
    stock = union([
        rbox((gx, by - 0.005, gz - 0.2), (0.021, 0.034, 0.1), 0.015),
        rbox((gx, by - 0.04, gz - 0.27), (0.019, 0.056, 0.042), 0.015),
    ], k=0.03)
    light.add(stock, k=0.01)
    light.sub(rbox((gx, by - 0.04, gz - 0.175), (0.04, 0.017, 0.045), 0.012), k=0.006)  # trou du pouce
    gun.piece(UNDER_D, tris=T(80)).add(rbox((gx, by - 0.04, gz - 0.317), (0.022, 0.06, 0.01), 0.008))  # plaque de couche
    gun.piece(trim if elite else PLATE_M, tris=T(120)).add(rbox((gx, by + 0.03, gz - 0.2), (0.014, 0.012, 0.07), 0.008))  # appui-joue
    # bagues sombres des bobines (lumière dans gun_glow)
    coils = gun.piece(JOINT, tris=T(220))
    for i in range(3):
        coils.add(cyl((gx, by + 0.004, gz + 0.45 + i * 0.07), 0.025, 0.014, 0.006, rot=(90, 0, 0)))
    # lunette : tube sombre sur deux colliers, cloches avant et arrière
    sy = by + 0.078
    sc = gun.piece(JOINT, tris=T(380))
    sc.add(capsule((gx, sy, gz - 0.07), (gx, sy, gz + 0.16), 0.024))
    sc.add(cyl((gx, sy, gz + 0.178), 0.036, 0.036, 0.011, rot=(90, 0, 0)), k=0.02)
    sc.add(cyl((gx, sy, gz - 0.088), 0.03, 0.026, 0.009, rot=(90, 0, 0)), k=0.015)
    sc.add(cyl((gx - 0.027, sy, gz + 0.04), 0.013, 0.013, 0.004, rot=(0, 0, 90)), k=0.006)  # molette
    sc.sub(cyl((gx, sy, gz + 0.215), 0.029, 0.01, 0.003, rot=(90, 0, 0)), k=0.003)
    rings = gun.piece(UNDER_D, tris=T(120))
    for dz in (-0.02, 0.11):
        rings.add(rbox((gx, (by + sy) * 0.5, gz + dz), (0.014, 0.045, 0.014), 0.006))
    parts.append(gun)
    gg = Part("gun_glow", pivot=GRIP, parent="gun", res=0.003)
    gl1 = gg.piece(VIO, tris=T(240))
    gl1.add(cyl((gx, sy, gz + 0.2), 0.03, 0.004, 0.002, rot=(90, 0, 0)))  # lentille avant
    for i in range(3):
        gl1.add(cyl((gx, by + 0.004, gz + 0.45 + i * 0.07), 0.028, 0.006, 0.003, rot=(90, 0, 0)))  # bobines
    gl2 = gg.piece(glow2, tris=T(160))
    gl2.add(cyl((gx, sy, gz - 0.112), 0.02, 0.003, 0.002, rot=(90, 0, 0)))  # oculaire
    for sx in (-1, 1):
        gl2.add(rbox((gx + sx * 0.0275, by - 0.004, gz + 0.27), (0.003, 0.008, 0.09), 0.0025))  # lignes du garde-main
    parts.append(gg)
    mz = (gx, by + 0.004, gz + MUZZLE_Z)
    mg = Part("muzzle_glow", pivot=mz, parent="gun", res=0.0025)
    mg.piece(VIO, tris=T(90)).add(cyl(add(mz, (0, 0, -0.006)), 0.015, 0.005, 0.002, rot=(90, 0, 0)))
    parts.append(mg)

    # ================================================================== jambes (hanche) + tibias (genou)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        hx = sx * HIP_X
        hip = (hx, HIP_Y, 0.0)
        kn = (sx * (HIP_X + 0.004), KNEE_Y, 0.0)
        an = (sx * (HIP_X + 0.006), ANKLE_Y, -0.005)
        leg = Part("leg_" + nm, pivot=hip, parent="pelvis", res=0.0045)
        th = capsule(hip, kn, 0.062, 0.047)
        leg.piece(UNDER, tris=T(200)).add(th)
        tp = leg.piece(PLATE, tris=T(270))
        tp.add(grow(th, 0.013))
        tp.sub(side((0, 0, -0.01), (0, 0, -1)), k=0.012)
        tp.sub(side((0, 0.4, 0), (0, -1, 0)), k=0.01)
        tp.sub(side((0, 0.6, 0), (0, 1, 0)), k=0.01)
        parts.append(leg)
        shin = Part("shin_" + nm, pivot=kn, parent="leg_" + nm, res=0.0045)
        shin.piece(JOINT, tris=T(90)).add(sphere(kn, 0.047))
        sh = capsule(kn, an, 0.043, 0.035)
        shin.piece(UNDER, tris=T(170)).add(sh)
        sp = shin.piece(PLATE_M, tris=T(230))
        sp.add(grow(sh, 0.013))
        sp.sub(side((0, 0, 0.0), (0, 0, -1)), k=0.012)
        sp.sub(side((0, 0.15, 0), (0, -1, 0)), k=0.01)
        shin.piece(PLATE, tris=T(120)).add(ellipsoid(add(kn, (0, 0.004, 0.04)), (0.038, 0.04, 0.026)))  # genouillère
        # pied : botte arrondie, talon relevé
        boot = shin.piece(UNDER, tris=T(280))
        boot.add(rbox((an[0], 0.048, 0.035), (0.05, 0.046, 0.094), 0.038, rot=(-4, 0, 0)))
        boot.add(cyl((an[0], 0.095, -0.005), 0.042, 0.022, 0.01), k=0.015)
        shin.piece(trim if elite else PLATE_M, tris=T(120)).add(rbox((an[0], 0.012, 0.035), (0.053, 0.012, 0.099), 0.01))
        shin.piece(PLATE, tris=T(110)).add(ellipsoid((an[0], 0.064, 0.108), (0.04, 0.029, 0.034)))  # coque d'orteil
        parts.append(shin)
    return Character("sniper_elite" if elite else "sniper", parts)
