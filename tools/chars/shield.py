"""Rempart (code « shield ») : porte-bouclier lourd et trapu de la sécurité de la station.
Il tient à deux mains, devant lui, un grand bouclier d'énergie bombé (arc de cylindre incliné vers l'arrière,
lisible depuis la caméra haute) : cadre métallique, surface de tuiles hexagonales ambre lumineuses, émetteur
central. Il faut le contourner : le dos est vulnérable, avec un gros module générateur à cœur lumineux,
cheminées et bande de danger, bien lisible du dessus. Casque rond à visière rouge qui dépasse du bouclier,
grosses épaulières à liseré orange, jambes courtes et trapues.
Regarde vers +Z ; sa droite est en -X. Pieds à y = 0. Hauteur ~1,2, largeur ~0,9 bouclier compris.

Parts : torso (pivot aux hanches), back_glow (cœur et cheminées du générateur), head (pivot au cou) + head_glow
(visière), arm_r / arm_l (épaule, avec épaulière, avant-bras et main), leg_r / leg_l (hanche) + shin_r / shin_l
(genou, avec le pied), shield (pivot au bas du bouclier, enfant du torse) + shield_glow (tuiles et émetteur).
Variante élite (build(elite=True), tools/chars/shield_elite.py) : accents or, cadre doré à pointes,
cornes de casque, épaulières à pointes."""
import math

import trimesh
from skimage import measure

from sculpt import *
from sculpt import Part as _Part

SHELL = "#C8CEDC"
SHELL_D = "#9AA4B6"
METAL = "#2C3350"
METAL_L = "#454E70"
METAL_D = "#1C2238"
ORANGE = "#FF7A2F"
RED = "#EE3F5C"
HAZ = "#FFC83A"
EYE = "#E80E2C"
GOLD = "#FFB347"
GOLD_D = "#D98A1E"
# tuiles lumineuses (multipliées par l'énergie du matériau : couleurs saturées, sinon elles blanchissent)
HEX_MID = "#F45000"
HEX_CORE = "#FFB040"
CORE = "#FF3C10"

# ------------------------------------------------------------------ repères (partagés avec scripts/mobs/shield.gd)
HIP = (0.0, 0.43, -0.07)
NECK = (0.0, 0.93, -0.03)
SHOULDER_X = 0.31
SHOULDER = (0.31, 0.83, -0.08)  # épaule gauche (+X) ; la droite est symétrique
KNEE = (0.17, 0.235, -0.05)
# bouclier : arc de cylindre vertical de rayon RS, incliné de TILT vers l'arrière autour de son bord bas avant B
SB = np.array([0.0, 0.075, 0.43])
RS = 0.68
HALF_ANG = 37.0
SH_H = 0.9
TILT = 11.0
GRIP_S = 0.2  # demi-écart des poignées (abscisse curviligne)
GRIP_V = 0.5  # hauteur des poignées sur le bouclier


class Part(_Part):
    """Normales exactes du champ de distance (coque lisse malgré l'allègement), allègement itératif."""

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
        for dist, w in ((0.025, 0.5), (0.06, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.8, 1.0) ** w
        if "_glow" in self.name:
            occ = np.ones(len(V))  # les lumières ne sont pas ombrées
        y = V[:, 1]
        grad = 0.92 + 0.08 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        if "_glow" in self.name:
            grad = np.ones(len(V))
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


BIG = 50.0


def inter(a, b, k=0.0):
    if k <= 0.0:
        return Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))
    return Shape(lambda P: smax(a(P), b(P), k), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def grow(a, d):
    return Shape(lambda P: a(P) - d, a.lo - max(d, 0.0), a.hi + max(d, 0.0))


def union(shapes, k=0.0):
    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = smin(d, s(P), k)
        return d
    return Shape(f, np.min([s.lo for s in shapes], axis=0) - k, np.max([s.hi for s in shapes], axis=0) + k)


def half(c, nv):
    """Demi-espace derrière le plan (côté opposé à la normale nv)."""
    c = np.asarray(c, dtype=np.float64)
    nv = np.asarray(nv, dtype=np.float64)
    nv = nv / np.linalg.norm(nv)
    return Shape(lambda P: (P - c) @ nv, np.full(3, -BIG), np.full(3, BIG))


def plane_stripes(dirv, period, frac=0.5):
    nv = np.asarray(dirv, dtype=np.float64)
    nv = nv / np.linalg.norm(nv)

    def f(P):
        u = (P @ nv) / period
        fr = u - np.floor(u)
        return (np.abs(fr - 0.5) - frac * 0.5) * period
    return Shape(f, np.full(3, -BIG), np.full(3, BIG))


def mx(p, sx):
    return (sx * p[0], p[1], p[2])


# ------------------------------------------------------------------ bouclier (repère local)
_TR = rot_matrix(-TILT, 0, 0)  # le haut du bouclier recule (vers -Z)


def sh_to_model(s, v, r):
    """Point du bouclier (abscisse curviligne s, hauteur v, rayon r) -> repère du personnage."""
    th = s / RS
    q = np.array([r * math.sin(th), v, r * math.cos(th) - RS])
    return SB + _TR @ q


def sh_dir(s, v):
    """Normale avant du bouclier en (s, v) (repère du personnage)."""
    th = s / RS
    return _TR @ np.array([math.sin(th), 0.0, math.cos(th)])


def _sv_r(P):
    Q = (P - SB) @ _TR  # inverse de la rotation
    x, y, z = Q[:, 0], Q[:, 1], Q[:, 2] + RS
    r = np.sqrt(x * x + z * z)
    th = np.arctan2(x, z)
    return th * RS, y, r


def rrect2(s, v, hw, hh, rc):
    """Rectangle arrondi 2D centré (0, hh) dans le plan (s, v)."""
    qx = np.abs(s) - (hw - rc)
    qy = np.abs(v - hh) - (hh - rc)
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - rc


def extrude(d2, r, r0, r1, rr):
    """Extrusion radiale arrondie d'une forme 2D entre les rayons r0 et r1."""
    dr = np.abs(r - 0.5 * (r0 + r1)) - 0.5 * (r1 - r0)
    a = np.maximum(d2 + rr, 0)
    b = np.maximum(dr + rr, 0)
    return np.sqrt(a * a + b * b) + np.minimum(np.maximum(d2 + rr, dr + rr), 0) - rr


W = RS * math.radians(HALF_ANG)  # demi-largeur (curviligne)
BOSS_V = 0.5


def sh_shape(fn2, r0, r1, rr=0.006, box=None):
    """Forme du bouclier : fn2(s, v) donne la distance 2D, extrudée entre r0 et r1.
    box : (s, v, demi-taille) pour borner une petite forme (sinon tout le bouclier)."""
    def f(P):
        s, v, r = _sv_r(P)
        return extrude(fn2(s, v), r, r0, r1, rr)
    if box is None:
        lo = np.array([-0.48, 0.02, 0.03])
        hi = np.array([0.48, 1.06, 0.52])
    else:
        c = sh_to_model(box[0], box[1], RS)
        lo, hi = c - box[2], c + box[2]
    return Shape(f, lo, hi)


def hex_local(s, v, size):
    """Coordonnées dans l'hexagone le plus proche (pavage à pointes en haut, pas `size` entre colonnes)."""
    px = s / size
    py = (v - BOSS_V) / size
    rx, ry = 1.0, math.sqrt(3.0)
    ax = np.mod(px, rx) - 0.5 * rx
    ay = np.mod(py, ry) - 0.5 * ry
    bx = np.mod(px - 0.5 * rx, rx) - 0.5 * rx
    by = np.mod(py - 0.5 * ry, ry) - 0.5 * ry
    use_a = ax * ax + ay * ay < bx * bx + by * by
    qx = np.where(use_a, ax, bx)
    qy = np.where(use_a, ay, by)
    hd = np.maximum(np.abs(qx), np.abs(qx) * 0.5 + np.abs(qy) * math.sqrt(3.0) * 0.5)
    return hd


def build(elite=False):
    name = "shield_elite" if elite else "shield"
    TRIM = GOLD if elite else ORANGE
    FRAME = GOLD_D if elite else SHELL_D
    parts = []

    # ================================================================== torse (pivot aux hanches)
    torso = Part("torso", pivot=HIP, res=0.008)
    pel = torso.piece(METAL, tris=180)
    pel.add(rbox((0, 0.46, -0.07), (0.2, 0.09, 0.15), 0.07))
    for sx in (-1, 1):
        pel.add(sphere((sx * 0.16, 0.43, -0.07), 0.095), k=0.04)
    barrel = union([
        ellipsoid((0, 0.72, -0.07), (0.28, 0.25, 0.225)),
        rbox((0, 0.69, -0.07), (0.265, 0.2, 0.205), 0.13),
    ], k=0.05)
    # haut clair, ventre sombre, plastron clair
    up = torso.piece(SHELL_D, tris=440)
    up.add(inter(barrel, half((0, 0.63, 0), (0, -1, 0))))
    belly = torso.piece(METAL, tris=220)
    belly.add(inter(grow(barrel, -0.01), half((0, 0.65, 0), (0, 1, 0))))
    belly.add(cyl((0, 0.56, -0.07), 0.22, 0.05, 0.03), k=0.04)
    chest_sh = ellipsoid((0, 0.76, 0.03), (0.22, 0.17, 0.16))
    chest = torso.piece(GOLD if elite else SHELL, tris=260, res=0.006)
    chest.add(inter(grow(barrel, 0.012), inter(chest_sh, half((0, 0.63, 0), (0, -1, 0)))))
    # bande orange de jonction (ceinture)
    torso.piece(TRIM, tris=180, res=0.006).add(
        inter(grow(barrel, 0.008), inter(half((0, 0.655, 0), (0, 1, 0)), half((0, 0.625, 0), (0, -1, 0)))))
    # col
    col = torso.piece(METAL, tris=150, res=0.006)
    col.add(torus((0, 0.93, -0.05), 0.12, 0.04))
    col.add(cyl((0, 0.92, -0.05), 0.15, 0.03, 0.02), k=0.02)
    # emboîtures d'épaule
    so = torso.piece(METAL_D, tris=80)
    for sx in (-1, 1):
        so.add(sphere(mx(SHOULDER, sx), 0.1))
    # ---- module générateur dorsal (le point faible) : caisson sombre, cœur lumineux incliné vers le haut,
    # cheminées, ailettes de refroidissement, bande de danger
    pk_c = (0, 0.75, -0.33)
    pack_sh = rbox(pk_c, (0.21, 0.21, 0.11), 0.08, rot=(-10, 0, 0))
    core_dir = np.array([0.0, math.sin(math.radians(35)), -math.cos(math.radians(35))])
    core_c = np.array([0, 0.8, -0.37])
    pack = torso.piece(METAL, tris=320)
    pack.add(pack_sh)
    pack.add(rbox((0, 0.72, -0.24), (0.17, 0.17, 0.05), 0.04), k=0.04)
    pack.sub(cyl((core_c + core_dir * 0.08).tolist(), 0.105, 0.07, 0.02, rot=(-55, 0, 0)), k=0.012)
    for sx in (-1, 1):
        for dz in (0.0, 0.05):
            pack.sub(rbox((sx * 0.215, 0.7, -0.29 - dz), (0.03, 0.12, 0.012), 0.008), k=0.006)
    # bague du cœur
    ring = torso.piece(TRIM, tris=160, res=0.0055)
    ring.add(torus((core_c + core_dir * 0.075).tolist(), 0.105, 0.022, rot=(-55, 0, 0)))
    # bande de danger au bas du module (lisible de dos)
    hz_sh = rbox((0, 0.585, -0.4), (0.19, 0.03, 0.035), 0.02, rot=(-10, 0, 0))
    torso.piece(HAZ if not elite else GOLD, tris=110, res=0.006).add(hz_sh)
    torso.piece(METAL_D, tris=150, res=0.006).add(inter(grow(hz_sh, 0.005), plane_stripes((1, 1, 0), 0.07)))
    # cheminées
    st = torso.piece(METAL_D, tris=160, res=0.006)
    for sx in (-1, 1):
        st.add(cyl((sx * 0.14, 0.97, -0.33), 0.045, 0.06, 0.015, rot=(-14, 0, 0)))
        st.sub(cyl((sx * 0.14, 1.02, -0.345), 0.028, 0.03, 0.006, rot=(-14, 0, 0)))
    if elite:
        sp = torso.piece(GOLD, tris=200, res=0.005)
        for sx in (-1, 1):
            sp.add(capsule((sx * 0.2, 0.9, -0.34), (sx * 0.27, 1.0, -0.4), 0.03, 0.006))
    parts.append(torso)

    back = Part("back_glow", pivot=HIP, parent="torso", res=0.005)
    bg = back.piece(GOLD if elite else CORE, tris=200)
    bg.add(ellipsoid((core_c + core_dir * 0.06).tolist(), (0.085, 0.03, 0.085), rot=(-55, 0, 0)))
    bg.paint(ellipsoid((core_c + core_dir * 0.09).tolist(), (0.045, 0.02, 0.045), rot=(-55, 0, 0)), HEX_CORE)
    for sx in (-1, 1):
        bg.add(cyl((sx * 0.14, 1.005, -0.342), 0.03, 0.01, 0.005, rot=(-14, 0, 0)))
    parts.append(back)

    # ================================================================== tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="torso", res=0.005)
    HC = (0, 1.04, 0.0)
    helm_sh = union([ellipsoid(HC, (0.15, 0.13, 0.15)), ellipsoid((0, 0.995, 0.01), (0.14, 0.08, 0.14))], k=0.03)
    helm = head.piece(SHELL, tris=440)
    helm.add(helm_sh)
    # masque sombre : bande frontale où se loge la visière
    vis_dir = np.array([0, math.sin(math.radians(12)), math.cos(math.radians(12))])
    mask = head.piece(METAL_D, tris=200)
    mask.add(inter(grow(helm_sh, 0.006), inter(rbox((0, 1.03, 0.1), (0.2, 0.045, 0.12), 0.02, rot=(-12, 0, 0)),
                                                half((0, 0, 0.02), (0, 0, -1)))))
    # crête rouge de faction (dessus du casque)
    head.piece(GOLD if elite else RED, tris=140).add(
        inter(grow(helm_sh, 0.008), rbox((0, 1.15, -0.0), (0.035, 0.1, 0.2), 0.01)))
    # oreillettes
    ear = head.piece(METAL, tris=100)
    for sx in (-1, 1):
        ear.add(cyl((sx * 0.148, 1.02, -0.01), 0.05, 0.025, 0.01, rot=(0, 0, 90)))
    if elite:
        horns = head.piece(GOLD, tris=360)
        for sx in (-1, 1):
            horns.add(capsule((sx * 0.13, 1.1, -0.01), (sx * 0.22, 1.17, -0.04), 0.035, 0.024))
            horns.add(capsule((sx * 0.22, 1.17, -0.04), (sx * 0.24, 1.26, 0.0), 0.024, 0.006), k=0.02)
    parts.append(head)
    hg = Part("head_glow", pivot=NECK, parent="head", res=0.003)
    vg = hg.piece(EYE, tris=150)
    # visière : fente lumineuse continue qui épouse l'avant du casque, un peu froncée au centre
    vband = inter(grow(helm_sh, 0.011), rbox((0, 1.035, 0.12), (0.115, 0.017, 0.1), 0.012, rot=(-12, 0, 0)))
    vg.add(inter(vband, half((0, 0, 0.06), (0, 0, -1))))
    vg.sub(rbox((0, 1.06, 0.15), (0.018, 0.02, 0.08), 0.01, rot=(-12, 0, 0)), k=0.01)
    parts.append(hg)

    # ================================================================== bras (épaule) : épaulière, bras, avant-bras, main
    grip_l = sh_to_model(GRIP_S, GRIP_V, RS - 0.085)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        SH = mx(SHOULDER, sx)
        arm = Part("arm_" + side, pivot=SH, parent="torso", res=0.0065)
        EL = (sx * 0.36, 0.63, 0.03)
        HAND = (sx * grip_l[0], grip_l[1], grip_l[2])
        arm.piece(METAL, tris=150).add(capsule(SH, EL, 0.07, 0.062))
        fa = arm.piece(SHELL_D, tris=220)
        fa.add(capsule((EL[0] * 0.9 + HAND[0] * 0.1, EL[1], EL[2] * 0.9 + HAND[2] * 0.1),
                       ((EL[0] * 0.35 + HAND[0] * 0.65), HAND[1] + 0.01, HAND[2] - 0.05), 0.068, 0.085))
        arm.piece(METAL_D, tris=80).add(sphere(EL, 0.082))  # coude (dépasse : pas de surfaces confondues)
        arm.piece(METAL_D, tris=130).add(ellipsoid(HAND, (0.06, 0.07, 0.065)))
        # épaulière : coque bombée et aplatie, inclinée vers l'extérieur, liseré orange
        pd_sh = union([ellipsoid(mx((0.325, 0.885, -0.08), sx), (0.125, 0.085, 0.145), rot=(0, 0, -sx * 22)),
                       ellipsoid(mx((0.305, 0.92, -0.08), sx), (0.085, 0.05, 0.105), rot=(0, 0, -sx * 22))], k=0.04)
        pad = arm.piece(SHELL_D, tris=220)
        pad.add(pd_sh)
        pad.sub(ellipsoid(mx((0.315, 0.8, -0.08), sx), (0.1, 0.06, 0.125), rot=(0, 0, -sx * 22)), k=0.02)
        rim = arm.piece(TRIM, tris=110, res=0.005)
        rim.add(inter(grow(pd_sh, 0.007), Shape(lambda P, sx=sx: np.abs(P[:, 0] * sx - 0.392) - 0.018, np.full(3, -BIG), np.full(3, BIG))))
        if elite:
            spk = arm.piece(GOLD, tris=200, res=0.005)
            for dz in (-0.06, 0.05):
                spk.add(capsule(mx((0.4, 0.94, -0.08 + dz), sx), mx((0.47, 1.03, -0.08 + dz * 1.2), sx), 0.03, 0.006))
        parts.append(arm)

    # ================================================================== jambes (hanche) + tibia (genou, avec le pied)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        HP = (sx * 0.16, 0.43, -0.07)
        KN = mx(KNEE, sx)
        leg = Part("leg_" + side, pivot=HP, parent="torso", res=0.0065)
        leg.piece(METAL, tris=150).add(capsule(HP, KN, 0.095, 0.085))
        parts.append(leg)
        shin = Part("shin_" + side, pivot=KN, parent="leg_" + side, res=0.0065)
        sh = shin.piece(SHELL_D, tris=200)
        sh.add(rbox((sx * 0.175, 0.17, -0.04), (0.095, 0.085, 0.1), 0.07))
        shin.piece(SHELL, tris=110).add(rbox((sx * 0.175, 0.23, 0.035), (0.075, 0.06, 0.04), 0.035, rot=(-15, 0, 0)))
        boot = shin.piece(METAL_D, tris=200)
        boot.add(rbox((sx * 0.18, 0.055, -0.0), (0.105, 0.055, 0.155), 0.045))
        shin.piece(TRIM, tris=100, res=0.0055).add(rbox((sx * 0.18, 0.06, 0.13), (0.1, 0.045, 0.05), 0.04))
        parts.append(shin)

    # ================================================================== bouclier (pivot au bas, au centre)
    shield = Part("shield", pivot=SB.tolist(), parent="torso", res=0.0055)
    inner_w, inner_h, fr = W - 0.04, SH_H * 0.5 - 0.04, 0.045
    # cadre : anneau arrondi qui déborde à l'avant
    frame = shield.piece(FRAME, tris=600, res=0.005)
    frame.add(sh_shape(lambda s, v: np.maximum(rrect2(s, v, W, SH_H * 0.5, 0.1), -rrect2(s, v - 0.04, inner_w, inner_h, 0.065)),
                       RS - 0.05, RS + 0.03, 0.012))
    # arête claire sur le dessus du cadre (lisible de la caméra haute)
    top = shield.piece(SHELL if not elite else GOLD, tris=200, res=0.0045)
    top.add(sh_shape(lambda s, v: np.maximum(np.abs(s) - (W - 0.085), np.abs(v - (SH_H - 0.022)) - 0.026),
                     RS - 0.058, RS + 0.04, 0.02))
    # fond sombre derrière les tuiles
    shield.piece(METAL_D, tris=250).add(sh_shape(lambda s, v: rrect2(s, v - 0.04, inner_w + 0.01, inner_h + 0.01, 0.07),
                                                 RS - 0.045, RS - 0.012, 0.006))
    # émetteur central : bague sombre
    boss = shield.piece(METAL, tris=180, res=0.0045)
    boss.add(sh_shape(lambda s, v: np.maximum(np.sqrt(s * s + (v - BOSS_V) ** 2) - 0.085, 0.05 - np.sqrt(s * s + (v - BOSS_V) ** 2)),
                      RS - 0.03, RS + 0.035, 0.012, box=(0, BOSS_V, 0.12)))
    # équerres sombres vissées aux quatre coins du cadre
    def corners(s, v):
        d = rrect2(s, v, W + 0.006, SH_H * 0.5 + 0.006, 0.1)
        return np.maximum(np.maximum(d, -rrect2(s, v - 0.04, inner_w - 0.01, inner_h - 0.01, 0.06)), -np.minimum(np.abs(s) - (W - 0.13), np.abs(v - SH_H * 0.5) - (SH_H * 0.5 - 0.13)))
    brk = shield.piece(METAL if not elite else GOLD, tris=280, res=0.0045)
    brk.add(sh_shape(corners, RS - 0.056, RS + 0.038, 0.01))
    bolts = shield.piece(METAL_D, tris=100, res=0.0035)
    for s0 in (-1, 1):
        for v0 in (0.035, SH_H - 0.035):
            bolts.add(sphere(sh_to_model(s0 * (W - 0.035), v0, RS + 0.04).tolist(), 0.014))
    # poignées à l'arrière
    grip = shield.piece(METAL, tris=120)
    for sx in (-1, 1):
        a = sh_to_model(sx * GRIP_S, GRIP_V - 0.09, RS - 0.05)
        b = sh_to_model(sx * GRIP_S, GRIP_V + 0.09, RS - 0.05)
        g0 = sh_to_model(sx * GRIP_S, GRIP_V - 0.07, RS - 0.085)
        g1 = sh_to_model(sx * GRIP_S, GRIP_V + 0.07, RS - 0.085)
        grip.add(capsule(a.tolist(), g0.tolist(), 0.016))
        grip.add(capsule(b.tolist(), g1.tolist(), 0.016))
        grip.add(capsule(g0.tolist(), g1.tolist(), 0.02))
    if elite:
        # pointes dorées sur le bord supérieur et aux coins
        spk = shield.piece(GOLD, tris=320, res=0.0045)
        for s0, h in ((-0.33, 0.07), (0.0, 0.1), (0.33, 0.07)):
            a = sh_to_model(s0, SH_H - 0.03, RS - 0.01)
            b = sh_to_model(s0, SH_H + h, RS - 0.01)
            spk.add(capsule(a.tolist(), b.tolist(), 0.03, 0.006))
    parts.append(shield)

    glow = Part("shield_glow", pivot=SB.tolist(), parent="shield", res=0.0042)
    HEX = 0.138

    def tile2(s, v):
        hd = hex_local(s, v, HEX) * HEX
        d = hd - (HEX * 0.5 - 0.011)
        d = np.maximum(d, rrect2(s, v - 0.04, inner_w - 0.004, inner_h - 0.004, 0.06))
        return np.maximum(d, 0.1 - np.sqrt(s * s + (v - BOSS_V) ** 2))

    tiles = glow.piece(HEX_MID, tris=1300)
    tiles.add(sh_shape(tile2, RS - 0.03, RS + 0.006, 0.008))

    lens = glow.piece(HEX_CORE, tris=120)
    lens.add(sh_shape(lambda s, v: np.sqrt(s * s + (v - BOSS_V) ** 2) - 0.055, RS - 0.03, RS + 0.02, 0.014, box=(0, BOSS_V, 0.09)))
    parts.append(glow)

    print("poignée gauche (repère du personnage) :", np.round(grip_l, 4).tolist())
    return Character(name, parts)
