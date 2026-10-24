"""Objets de fret de Nébuleuse 7 (obstacles et accessoires du hangar), sculptés en SDF avec tools/sculpt.py.

Compagnie de fret : HÉLIX FRET (HXF ; logo : hexagone contenant une double hélice à barreaux, le même que
sur le sol de l'arène et le quai ; sous-titre « TRANSIT NÉBULEUSE 7 »), pochoirs crème.
Les marquages (logo, pochoirs, étiquettes, bandes de danger) sont des quads collés aux faces planes, texturés
par la planche tools/decor/atlas.py (assets/decor/props/decals.png) : part « <nom>_decal » de chaque GLB.
Repère commun : sol à y = 0, emprise centrée sur l'origine, face avant (marquages) vers +Z, X = largeur.
Les dimensions sont réelles (mètres du jeu) : le décor combine plusieurs tailles plutôt que d'étirer un modèle.

Matières : peinture mate peu saturée, variations de teinte basse fréquence, écaillage au métal nu sur les
arêtes vives (détectées dans le champ de distance), salissure près du sol, occlusion simulée.

Usage : python3 tools/decor/props.py [nom...]   (sans nom : tous) -> assets/decor/props/<nom>.glb
"""
import math
import os
import sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))

import numpy as np  # noqa: E402
import trimesh  # noqa: E402
from skimage import measure  # noqa: E402

import atlas as AT  # noqa: E402
import sculpt as S  # noqa: E402
from sculpt import Shape, capsule, ellipsoid, hexcol, rot_matrix, sphere  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "decor", "props"))

# ------------------------------------------------------------------ palette (peu saturée : les personnages ressortent)
HULLS = {
    "ardoise": "#66708A",   # bleu ardoise
    "sable": "#AA9874",     # gris sable chaud
    "olive": "#7E8864",     # olive gris
    "petrole": "#5A7E82",   # bleu pétrole
    "brique": "#9E6858",    # rouge brique éteint
}
STEEL = "#50566A"       # coins, montants (acier peint sombre)
STEEL_M = "#7A808C"     # poignées, boucles
BARE = "#B4B8BE"        # métal nu (écaillage)
WEB = "#2E3138"         # sangles
CREAM = "#C9C1AB"       # pochoirs, étiquettes
INK = "#2B2E36"         # texte des étiquettes
ORANGE = "#D8743A"      # accent ponctuel
YELLOW = "#C99A34"      # bandes de danger
BLACK = "#1B1C20"
RUBBER = "#2A2C31"
CARDBOARD = "#9C8A6C"
TAPE = "#9A8964"
DIM = 0.8               # palette écrite « à l'œil », assombrie pour la lumière du hangar (voir Part.piece)


# ------------------------------------------------------------------ formes (boîtes englobantes serrées)
def _tight(s, c, half, rot):
    R = rot_matrix(*rot)
    h = np.asarray(half, dtype=np.float64)
    corners = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]) * h
    w = corners @ R.T + np.asarray(c, dtype=np.float64)
    s.lo, s.hi = w.min(axis=0), w.max(axis=0)
    return s


def box(c, half, r=0.02, rot=(0, 0, 0)):
    return _tight(S.rbox(c, half, min(r, min(half) * 0.98), rot), c, half, rot)


def cyl(c, r, h, rr=0.01, rot=(0, 0, 0)):
    return _tight(S.cyl(c, r, h, min(rr, r * 0.98, h * 0.98), rot), c, (r, h, r), rot)


def torus(c, R0, r, rot=(0, 0, 0)):
    return _tight(S.torus(c, R0, r, rot), c, (R0 + r, r, R0 + r), rot)


def union(*ss):
    return Shape(lambda P: np.min([s(P) for s in ss], axis=0), np.min([s.lo for s in ss], axis=0), np.max([s.hi for s in ss], axis=0))


def inter(a, b):
    return Shape(lambda P: np.maximum(a(P), b(P)), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def diff(a, b):
    return Shape(lambda P: np.maximum(a(P), -b(P)), a.lo, a.hi)


def xform(s, c, rot):
    """Forme `s` (définie dans son repère) posée en c avec la rotation rot (degrés)."""
    c = np.asarray(c, dtype=np.float64)
    R = rot_matrix(*rot)
    corners = np.array([[x, y, z] for x in (s.lo[0], s.hi[0]) for y in (s.lo[1], s.hi[1]) for z in (s.lo[2], s.hi[2])])
    w = corners @ R.T + c
    return Shape(lambda P: s.fn((P - c) @ R), w.min(axis=0), w.max(axis=0))


# faces d'un objet : rotation qui amène le plan XY (normale +Z) d'un marquage sur la face
FRONT, BACK, TOP, RIGHT, LEFT = (0, 0, 0), (0, 180, 0), (-90, 0, 0), (0, 90, 0), (0, -90, 0)


# ------------------------------------------------------------------ bruit, matières
def vnoise(P, f, seed=0):
    Q = P * f + seed * 7.31
    i = np.floor(Q)
    t = Q - i
    u = t * t * (3 - 2 * t)
    acc = np.zeros(len(P))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                n = np.sin((i[:, 0] + dx) * 127.1 + (i[:, 1] + dy) * 311.7 + (i[:, 2] + dz) * 74.7 + seed * 13.3) * 43758.5453
                acc += w * (n - np.floor(n))
    return acc


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def simplify(verts, faces, goal, sdf=None, tol=0.006):
    """Allègement jusqu'au budget : sommets soudés d'abord (marching cubes en duplique, ce qui bloque
    fast_simplification sur les boîtes), passes d'au plus ~2x, ressoudure entre passes. Une passe qui
    éloigne un triangle de la surface (centre à plus de `tol` du champ) est annulée : on s'arrête là."""
    import fast_simplification
    tm = trimesh.Trimesh(verts, faces, process=True)
    tm.update_faces(tm.nondegenerate_faces())
    tm.remove_unreferenced_vertices()
    v, f = tm.vertices.astype(np.float32), tm.faces.astype(np.int32)
    keep = 0.5
    for _ in range(40):
        if len(f) <= goal * 1.05 or keep > 0.93:
            break
        step = max(goal / len(f), keep)
        v2, f2 = fast_simplification.simplify(v, f, target_reduction=1.0 - step)
        t2 = trimesh.Trimesh(v2, f2, process=True)
        t2.update_faces(t2.nondegenerate_faces())
        t2.remove_unreferenced_vertices()
        bad = len(t2.faces) > len(f) * 0.97
        if not bad and sdf is not None:
            err = np.abs(sdf(t2.triangles_center.astype(np.float64)))
            bad = np.percentile(err, 98) > tol or err.max() > tol * 3
        if bad:
            keep = 1.0 - (1.0 - keep) * 0.5  # pas plus petit
            continue
        v, f = t2.vertices.astype(np.float32), t2.faces.astype(np.int32)
    return v, f


class Piece(S.Piece):
    def __init__(self, color, tris, res, wear, grime, bare):
        super().__init__(color, tris, res)
        self.wear = wear
        self.grime = grime
        self.bare = hexcol(bare)


class Part(S.Part):
    """sculpt.Part avec normales exactes (gradient du champ), occlusion simulée, salissure près du sol et
    écaillage des arêtes. L'écaillage n'est pas peint aux sommets (trop peu nombreux sur les faces planes
    allégées) : l'alpha des couleurs par sommet porte un facteur d'arête que le shader du jeu
    (hangar_props.gd, prop_mat) découpe avec un bruit fin, en éclats nets de métal nu. Sommets dédoublés
    par triangle : les triangles des faces planes ont un facteur nul, l'arête ne bave pas sur la face.
    Les parts « *_glow » gardent leur couleur pure (rendues lumineuses)."""
    seed = 0
    tol = 0.011

    def piece(self, color, tris=600, res=None, wear=0.0, grime=1.0, bare=BARE):
        pc = Piece(color, tris, res, wear, grime, bare)
        if "_glow" not in self.name:
            # la lumière du hangar (soleil, ambiance bleue, tonemap) éclaircit beaucoup : palette assombrie
            # d'un facteur commun, teintes et saturations gardées
            pc.color = (pc.color * DIM).astype(np.float32)
        self.pieces.append(pc)
        return pc

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
            # tolérance : au moins l'erreur du maillage brut (marching cubes) aux centres des triangles
            base = np.percentile(np.abs(pc.sdf(verts[faces].mean(axis=1))), 98)
            verts, faces = simplify(verts, faces, pc.tris, pc.sdf, max(self.tol, res * 0.6, base * 1.6))
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        F = np.asarray(tm.faces)
        e = 1e-3
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V).astype(np.float64)
        tri_e = np.zeros(len(F))
        if "_glow" not in self.name:
            sd = self.seed
            # peinture : légère variation basse fréquence (le grain fin est dans le shader)
            col = col * (1.0 + pc.grime * 0.08 * (vnoise(V, 2.5, sd) - 0.5))[:, None]
            # arête vive : courbure convexe du triangle estimée par l'écart de ses normales (exactes) rapporté à
            # l'écart de ses sommets, ~1/rayon d'arrondi ; les faces planes et les congés creux restent à zéro
            if pc.wear > 0:
                kap = np.zeros(len(F))
                for i, j in ((0, 1), (1, 2), (2, 0)):
                    dv = V[F[:, i]] - V[F[:, j]]
                    dn = N[F[:, i]] - N[F[:, j]]
                    kap = np.maximum(kap, np.einsum("fc,fc->f", dn, dv) / np.maximum(np.einsum("fc,fc->f", dv, dv), 1e-8))
                tri_e = smooth(5.0, 16.0, kap) * pc.wear
        cc = col[F]  # couleur par coin de triangle
        # normale et occlusion de chaque coin prises un peu rentrées dans son triangle (3 cm au plus) : un
        # grand triangle de face plane dont un sommet touche un congé reste plat et clair, sans traînée
        Pc = V[F]
        cen = Pc.mean(axis=1, keepdims=True)
        pull = cen - Pc
        ln = np.linalg.norm(pull, axis=2, keepdims=True)
        Pc = (Pc + pull * np.minimum(0.4, 0.03 / np.maximum(ln, 1e-6))).reshape(-1, 3)
        Ncr = np.stack([pc.sdf(Pc + np.eye(3)[i] * e) - pc.sdf(Pc - np.eye(3)[i] * e) for i in range(3)], axis=1)
        Ncr /= np.maximum(np.linalg.norm(Ncr, axis=1), 1e-12)[:, None]
        if "_glow" not in self.name:
            occ = np.ones(len(Pc))
            for dist, w in ((0.02, 0.5), (0.07, 0.6)):
                dd = self.sdf(Pc + Ncr * dist)
                occ *= np.clip(0.6 + 0.4 * dd / dist, 0.72, 1.0) ** w
            # salissure au ras du sol, léger dégradé vertical
            y = Pc[:, 1]
            dirt = 1.0 - pc.grime * 0.12 * (1 - smooth(0.0, 0.2, y))
            grad = 0.94 + 0.06 * smooth(0.0, 0.8, y)
            cc = cc * (occ * dirt * grad).reshape(-1, 3)[:, :, None]
        ce = np.repeat(tri_e[:, None], 3, axis=1)
        # couleurs écrites telles quelles (sRGB) : le rendu Compatibility les prend brutes
        Vc = V[F].reshape(-1, 3)
        Nc = Ncr
        rgba = np.concatenate([np.clip(cc, 0, 1).reshape(-1, 3), ce.reshape(-1, 1)], axis=1)
        if "_glow" in self.name:
            rgba[:, 3] = 1.0
        return Vc, Nc, rgba

    def mesh(self):
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        V = np.concatenate([o[0] for o in out]) - self.pivot
        N = np.concatenate([o[1] for o in out])
        C = np.concatenate([o[2] for o in out])
        tm = trimesh.Trimesh(V, np.arange(len(V)).reshape(-1, 3), process=False)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(np.clip(C, 0, 1) * 255).round().astype(np.uint8))
        tm.vertex_normals = N
        return tm


def P(name, res=0.012, seed=0, tol=0.011):
    p = Part(name, res=res)
    p.seed = seed
    p.tol = tol
    return p


# ------------------------------------------------------------------ marquages (quads sur la planche atlas.py)
class Decals:
    """Quads de marquage collés aux faces planes, exportés en part « <nom>_decal » (UV dans decals.png).
    Face : rotation (degrés) qui amène le plan XY (normale +Z, haut du marquage = +Y) sur la face."""

    def __init__(self, name):
        self.name = name + "_decal"
        self.parent = None
        self.pivot = np.zeros(3)
        self.V, self.UV, self.F, self.N = [], [], [], []

    def _uv(self, key, crop=(0.0, 0.0, 1.0, 1.0)):
        x, y, w, h = AT.R[key]
        s = float(AT.SIZE)
        u0, v0 = (x + 0.5 + crop[0] * (w - 1)) / s, (y + 0.5 + crop[1] * (h - 1)) / s
        u1, v1 = (x + 0.5 + crop[2] * (w - 1)) / s, (y + 0.5 + crop[3] * (h - 1)) / s
        # trimesh écrit les UV à l'envers (origine en bas à gauche) : on retourne v
        return u0, 1.0 - v0, u1, 1.0 - v1

    def _add(self, P4, UV4, n):
        b = len(self.V)
        self.V += list(P4)
        self.UV += list(UV4)
        self.N += [n] * 4
        self.F += [(b, b + 1, b + 2), (b, b + 2, b + 3)]

    def quad(self, key, c, w, h, face, off=0.006, crop=(0.0, 0.0, 1.0, 1.0), spin=0.0):
        R = rot_matrix(*face)
        cs, sn = math.cos(math.radians(spin)), math.sin(math.radians(spin))
        loc = np.array([[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]])
        loc = loc @ np.array([[cs, sn], [-sn, cs]])
        L = np.concatenate([loc, np.full((4, 1), off)], axis=1)
        Pw = L @ R.T + np.asarray(c, dtype=np.float64)
        u0, v0, u1, v1 = self._uv(key, crop)
        self._add(Pw, [(u0, v1), (u1, v1), (u1, v0), (u0, v0)], R @ np.array([0.0, 0, 1]))

    def strip(self, key, c, length, h, face, tile, off=0.002):
        """Bande répétée (ex. danger) : quads successifs d'une période `tile` (m), le dernier rogné."""
        x = -length / 2
        R = rot_matrix(*face)
        ax = R @ np.array([1.0, 0, 0])
        while x < length / 2 - 1e-4:
            seg = min(tile, length / 2 - x)
            self.quad(key, np.asarray(c) + ax * (x + seg / 2), seg, h, face, off, crop=(0.0, 0.0, seg / tile, 1.0))
            x += seg

    def cyl(self, key, r, y, h, ang, arc, n=4, crop=(0.0, 0.0, 1.0, 1.0)):
        """Marquage sur un fût d'axe Y (rayon r), centré à l'angle `ang` (degrés, 0 = +Z, 90 = +X), largeur `arc` (m)."""
        a0 = math.radians(ang) - arc / r / 2
        da = arc / r / n
        for i in range(n):
            t0, t1 = a0 + i * da, a0 + (i + 1) * da
            p = [(math.sin(t0) * r, y - h / 2, math.cos(t0) * r), (math.sin(t1) * r, y - h / 2, math.cos(t1) * r),
                 (math.sin(t1) * r, y + h / 2, math.cos(t1) * r), (math.sin(t0) * r, y + h / 2, math.cos(t0) * r)]
            cu0 = crop[0] + (crop[2] - crop[0]) * i / n
            cu1 = crop[0] + (crop[2] - crop[0]) * (i + 1) / n
            u0, v0, u1, v1 = self._uv(key, (cu0, crop[1], cu1, crop[3]))
            tm = (t0 + t1) / 2
            self._add(np.array(p), [(u0, v1), (u1, v1), (u1, v0), (u0, v0)], np.array([math.sin(tm), 0, math.cos(tm)]))

    def mesh(self):
        V = np.array(self.V, dtype=np.float64)
        tm = trimesh.Trimesh(V, np.array(self.F), process=False)
        tm.visual = trimesh.visual.TextureVisuals(uv=np.array(self.UV), material=trimesh.visual.material.PBRMaterial(baseColorFactor=[255, 255, 255, 255]))
        tm.vertex_normals = np.array(self.N)
        return tm


def M(name, parts, dc=None):
    return S.Character(name, parts + ([dc] if dc is not None and dc.V else []))


# ------------------------------------------------------------------ caisse de fret renforcée
def crate(name, Wd, H, D, hull, seed=0, straps=2, code="N7", word=True, handles=True, tag="tag", latches=False,
          logo_key="logo", tris=270):
    """Caisse renforcée : coque à panneaux en creux, couvercle à joint et panneau central, cornières d'angle
    en acier, patins, sangles et boucles, poignées encastrées ; marquages HÉLIX FRET (logo et code sur le couvercle,
    la face la plus vue par la caméra de jeu ; pochoir et étiquette de fret devant, flèches sur les flancs)."""
    wx, dz = Wd * 0.5, D * 0.5
    y0 = 0.05                  # dessous de la coque (patins dessous)
    yc = (y0 + H) * 0.5
    hh = (H - y0) * 0.5
    bx, bz = wx - 0.02, dz - 0.02   # demi-tailles de la coque
    rd = 0.016                      # profondeur des panneaux en creux
    a = P(name, seed=seed, tol=0.008)  # tolérance serrée : les marquages collent aux panneaux
    dc = Decals(name)
    body = a.piece(hull, tris=tris, res=0.015 if Wd * D > 0.8 else None, wear=0.9)
    body.add(box((0, yc, 0), (bx, hh, bz), 0.03))
    m = 0.085  # cadre autour des panneaux
    ph = hh - m
    py = yc - 0.012
    if ph > 0.05:
        body.sub(box((0, py, bz), (bx - m, ph, rd), 0.014), k=0.008)
        body.sub(box((0, py, -bz), (bx - m, ph, rd), 0.014), k=0.008)
        body.sub(box((bx, py, 0), (rd, ph, bz - m), 0.014), k=0.008)
        body.sub(box((-bx, py, 0), (rd, ph, bz - m), 0.014), k=0.008)
    # joint du couvercle et panneau central du couvercle
    yl = H - min(0.1, H * 0.2)
    groove = diff(box((0, yl, 0), (bx + 0.02, 0.009, bz + 0.02), 0.004), box((0, yl, 0), (bx - 0.035, 1.0, bz - 0.035), 0.004))
    body.sub(groove, k=0.004)
    lt = 0.012
    body.sub(box((0, H, 0), (bx - 0.1, lt, bz - 0.1), 0.02), k=0.008)
    ytop = H - lt                    # surface du panneau du couvercle
    zp = bz - rd                     # surface des panneaux avant / arrière
    xp = bx - rd                     # surface des panneaux de flanc
    # cornières d'angle (acier sombre)
    st = a.piece(STEEL, tris=int(tris * 0.18), res=0.01, wear=0.45)
    for sx in (-1, 1):
        for sz in (-1, 1):
            st.add(box((sx * (wx - 0.035), yc + 0.006, sz * (dz - 0.035)), (0.05, hh + 0.012, 0.05), 0.02))
    # patins
    sk = a.piece(RUBBER, tris=36, res=0.016, grime=0.6)
    for sz in (-1, 1):
        sk.add(box((0, 0.03, sz * (dz - 0.14)), (wx - 0.1, 0.03, 0.06), 0.015))

    # sangles par-dessus le couvercle, boucle à l'avant
    xs = [] if straps == 0 else ([wx * 0.42] if straps == 1 else [-Wd * 0.3, Wd * 0.3])
    if xs:
        sg = a.piece(WEB, tris=55 * len(xs), grime=0.7)
        bk = a.piece(STEEL_M, tris=24 * len(xs), res=0.008, wear=0.6)
        for x in xs:
            sg.add(box((x, H + 0.004, 0), (0.034, 0.009, bz + 0.012), 0.005))
            sg.add(box((x, yc + 0.02, bz + 0.004), (0.034, hh - 0.005, 0.009), 0.005))
            sg.add(box((x, yc + 0.02, -bz - 0.004), (0.034, hh - 0.005, 0.009), 0.005))
            bk.add(box((x, H * 0.6, bz + 0.016), (0.046, 0.034, 0.01), 0.007))
    # poignées encastrées sur les flancs
    hy = py + ph * 0.45
    if handles and ph > 0.08:
        hl = min(0.11, (bz - m) * 0.6)
        for sx in (-1, 1):
            body.sub(box((sx * (bx - rd), hy, 0), (0.035, 0.035, hl + 0.025), 0.014), k=0.006)
        hd = a.piece(STEEL_M, tris=36, res=0.008, wear=0.5)
        for sx in (-1, 1):
            hd.add(capsule((sx * (bx - rd - 0.018), hy + 0.012, -hl), (sx * (bx - rd - 0.018), hy + 0.012, hl), 0.012))
    # loquets (caisse longue)
    if latches:
        lk = a.piece(STEEL_M, tris=40, res=0.008, wear=0.6)
        for x in (-wx * 0.62, wx * 0.62):
            lk.add(box((x, yl, bz + 0.006), (0.04, 0.034, 0.014), 0.01))

    # marquages du couvercle : logo, code de lot
    Dl = min(0.26, Wd * 0.34, D * 0.45)
    lx = 0.0 if straps != 1 else -wx * 0.22
    if code:
        ch = min(0.085, D * 0.12)
        dc.quad(logo_key, (lx, ytop, -D * 0.06), Dl, Dl, TOP)
        dc.quad(code, (lx, ytop, bz - 0.11 - ch * 0.5), ch * 256 / 96, ch, TOP)
    else:
        dc.quad(logo_key, (lx, ytop, 0.0), Dl, Dl, TOP)
    if ph > 0.05:
        inner = bx - m
        half = (Wd * 0.3 - 0.06) if straps == 2 else (inner if straps == 0 else inner)
        # avant : pochoir HÉLIX FRET, étiquette de fret, usure
        if word:
            ww = min(0.36, 2 * half * 0.86)
            dc.quad("word", (0, py + ph - ww / 8 - 0.025, zp), ww, ww / 4, FRONT)
        lw = min(0.17, inner * 0.7)
        lab_x = (half - lw / 2 - 0.01) if word else (-inner + lw / 2 + 0.03)
        if straps == 1:
            lab_x = -inner + lw / 2 + 0.03
        dc.quad(tag, (lab_x, py - ph + lw / 4 + 0.03, zp), lw, lw / 2, FRONT)
        sc = min(ph * 1.2, 0.3)
        dc.quad("scuff", (-lab_x * 0.6, py - ph + sc * 0.4, zp), min(sc * 1.4, inner * 1.4), sc * 0.8, FRONT, off=0.0015)
        # arrière : pochoir, flèches « haut »
        if word:
            dc.quad("word", (0, py + ph * 0.3, -zp), ww, ww / 4, BACK)
        au = min(0.12, ph * 0.7)
        dc.quad("up", (inner * 0.5 if straps != 1 else -inner * 0.5, py - ph * 0.4, -zp), au, au, BACK)
        # flancs : flèches, ligne de pochoir
        sdz = bz - m
        dc.quad("up", (xp, py - ph + au / 2 + 0.03, -sdz * 0.45), au, au, RIGHT)
        lw2 = min(0.42, 2 * sdz * 0.9)
        if lw2 > 0.2:
            dc.quad("line", (-xp, py - ph + 0.05, 0), lw2, lw2 / 8, LEFT)
    return M(name, [a], dc)


# ------------------------------------------------------------------ caisse bâchée
def tarp(name, hull="#56645F", seed=3):
    """Charge bâchée sur palette : bâche bombée et plissée sur des colis, trois sangles à cliquet, œillets,
    palette composite, étiquette et logo imprimé délavé."""
    Wd, D = 1.2, 1.0
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, seed=seed)
    dc = Decals(name)
    pal = a.piece("#474E5C", tris=110, res=0.014, wear=0.35)
    pal.add(box((0, 0.105, 0), (wx - 0.01, 0.018, dz - 0.01), 0.008))
    for sz in (-1, 0, 1):
        pal.add(box((0, 0.045, sz * (dz - 0.07)), (wx - 0.03, 0.045, 0.06), 0.01))
    # bâche : volume arrondi, bosses des colis dessous, plis
    tp = a.piece(hull, tris=420, res=0.014, wear=0.0)
    tp.add(box((0, 0.42, 0), (wx - 0.03, 0.3, dz - 0.03), 0.09))
    tp.add(ellipsoid((-0.22, 0.62, -0.1), (0.36, 0.14, 0.32)), k=0.08)
    tp.add(ellipsoid((0.25, 0.6, 0.12), (0.3, 0.15, 0.3)), k=0.08)
    for (x0, z0, x1, z1) in ((-0.5, 0.4, -0.15, 0.1), (0.1, -0.48, 0.35, -0.05), (0.55, 0.15, 0.2, 0.38),
                             (-0.56, -0.25, -0.25, -0.46)):
        tp.add(capsule((x0, 0.69, z0), (x1, 0.68, z1), 0.035), k=0.05)  # plis en relief (pas de creux noirs)
    for (x, z) in ((-0.5, 0.5), (0.5, 0.5), (0.0, -0.5), (0.58, -0.2), (-0.58, 0.15)):
        tp.sub(capsule((x, 0.62, z * 1.05), (x * 1.02, 0.25, z * 1.06), 0.02), k=0.04)
    tp.add(box((0, 0.15, 0), (wx - 0.01, 0.03, dz - 0.01), 0.025), k=0.03)
    # œillets sur l'ourlet
    oe = a.piece(STEEL, tris=40, res=0.006, wear=0.0)
    for x in (-0.19, 0.19):
        oe.add(torus((x, 0.165, dz - 0.004), 0.016, 0.006, rot=(90, 0, 0)))
    # sangles et cliquets
    sg = a.piece("#2E3138", tris=180, res=0.006, grime=0.6)
    bk = a.piece(STEEL_M, tris=40, res=0.008, wear=0.7)
    for x in (-0.38, 0.0, 0.38):
        # sangle collée à la bâche : coque mince autour de son champ, limitée à une bande en x
        band = Shape(lambda Q, x=x: np.maximum(np.abs(tp.sdf(Q) - 0.004) - 0.006, np.maximum(np.abs(Q[:, 0] - x) - 0.03, 0.16 - Q[:, 1])),
                     np.array([x - 0.05, 0.12, -dz - 0.05]), np.array([x + 0.05, 0.85, dz + 0.05]))
        sg.add(band)
        bk.add(box((x, 0.36, dz - 0.01), (0.042, 0.05, 0.016), 0.008))
    dc.quad("tag", (0.19, 0.44, dz - 0.03), 0.17, 0.085, FRONT, off=0.004)
    dc.quad("logo", (-0.19, 0.44, dz - 0.03), 0.2, 0.2, FRONT, off=0.004)
    return M(name, [a], dc)


# ------------------------------------------------------------------ conteneur de matières dangereuses
def hazmat(name, seed=5):
    """Conteneur scellé : coque claire épaisse, bande jaune et noire, losanges de danger, vanne à volant,
    évent, voyant ambre."""
    Wd, H, D = 0.9, 0.75, 0.7
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, seed=seed, res=0.016, tol=0.014)
    dc = Decals(name)
    body = a.piece("#8E918A", tris=360, res=0.016, wear=0.9)
    body.add(box((0, H * 0.5 + 0.02, 0), (wx - 0.02, H * 0.5 - 0.02, dz - 0.02), 0.06))
    # semelle et couvercle sombres
    ft = a.piece(STEEL, tris=120, res=0.014, wear=0.9)
    ft.add(box((0, 0.035, 0), (wx - 0.005, 0.035, dz - 0.005), 0.02))
    ft.add(box((0, H - 0.01, 0), (wx - 0.06, 0.025, dz - 0.06), 0.02))
    # bande en relief (les chevrons sont des marquages)
    yb, hb = 0.2, 0.06
    band = diff(box((0, yb, 0), (wx - 0.006, hb, dz - 0.006), 0.05), box((0, yb, 0), (wx - 0.04, 1.0, dz - 0.04), 0.03))
    a.piece(YELLOW, tris=100, res=0.01, wear=0.5).add(band)
    hz = hb * 1.7
    tile = hz * 8
    dc.strip("haz", (0, yb, dz - 0.006), 2 * (wx - 0.056), hz, FRONT, tile)
    dc.strip("haz", (0, yb, -dz + 0.006), 2 * (wx - 0.056), hz, BACK, tile)
    dc.strip("haz", (wx - 0.006, yb, 0), 2 * (dz - 0.056), hz, RIGHT, tile)
    dc.strip("haz", (-wx + 0.006, yb, 0), 2 * (dz - 0.056), hz, LEFT, tile)
    # marquages : losanges, pochoir sombre, étiquette
    dc.quad("diamond", (0.2, 0.46, dz - 0.02), 0.17, 0.17, FRONT)
    dc.quad("word_k", (-0.12, 0.49, dz - 0.02), 0.3, 0.075, FRONT)
    dc.quad("tag2", (-0.12, 0.4, dz - 0.02), 0.14, 0.07, FRONT)
    dc.quad("diamond", (-0.2, H + 0.015, 0.1), 0.16, 0.16, TOP)
    dc.quad("diamond", (wx - 0.02, 0.48, 0.0), 0.16, 0.16, RIGHT)
    dc.quad("vent", (-wx + 0.02, 0.5, 0.0), 0.16, 0.16, LEFT)
    # vanne à volant, évent
    vv = a.piece(STEEL_M, tris=130, res=0.008, wear=0.6)
    vv.add(cyl((0.15, H + 0.04, -0.08), 0.05, 0.04, 0.01))
    vv.add(torus((0.15, H + 0.09, -0.08), 0.07, 0.012))
    vv.add(capsule((0.08, H + 0.09, -0.08), (0.22, H + 0.09, -0.08), 0.008))
    vv.add(cyl((-0.22, H + 0.025, -0.15), 0.04, 0.025, 0.008))
    g = P(name + "_glow", res=0.004)
    g.piece("#FFB347", tris=40).add(sphere((wx - 0.1, 0.64, dz - 0.012), 0.014))
    return M(name, [a, g], dc)


# ------------------------------------------------------------------ fût / cellule d'énergie
def cell(name, hull="#56636E", seed=7, glow="#A8E060"):
    """Cellule d'énergie cylindrique : fût cerclé, fenêtres de jauge lumineuses graduées, capot à poignée,
    voyant de charge, bande orange, code."""
    R, H = 0.28, 0.8
    a = P(name, seed=seed, res=0.014, tol=0.014)
    dc = Decals(name)
    body = a.piece(hull, tris=240, wear=0.9)
    body.add(cyl((0, H * 0.5, 0), R - 0.01, H * 0.5 - 0.02, 0.03))
    for ang in (0.0, 180.0):
        r = math.radians(ang)
        cx, cz = math.sin(r) * (R - 0.01), math.cos(r) * (R - 0.01)
        body.sub(box((cx, 0.4, cz), (0.045, 0.2, 0.04), 0.02, rot=(0, ang, 0)), k=0.008)
    hp = a.piece(STEEL, tris=100, wear=1.0)
    for y in (0.06, 0.73):
        hp.add(cyl((0, y, 0), R, 0.035, 0.015))
    # capot, poignée
    cp = a.piece(STEEL_M, tris=80, res=0.008, wear=0.6)
    cp.add(cyl((0, H - 0.005, 0), R * 0.7, 0.03, 0.02))
    cp.add(capsule((-0.1, H + 0.06, 0), (0.1, H + 0.06, 0), 0.014))
    cp.add(capsule((-0.1, H + 0.06, 0), (-0.12, H + 0.01, 0), 0.012))
    cp.add(capsule((0.1, H + 0.06, 0), (0.12, H + 0.01, 0), 0.012))
    a.piece(ORANGE, tris=48, res=0.008, wear=0.6).add(cyl((0, 0.655, 0), R - 0.004, 0.016, 0.004))
    rr = R - 0.008
    dc.cyl("E-7", rr, 0.5, 0.075, 90.0, 0.2)
    dc.cyl("E-7", rr, 0.5, 0.075, -90.0, 0.2)
    for ang in (0.0, 180.0):
        dc.cyl("gauge", rr, 0.4, 0.34, ang + 17.0, 0.06, n=1)
    dc.cyl("logo", rr, 0.3, 0.1, 90.0, 0.1, n=2)
    g = P(name + "_glow", res=0.005)
    gp = g.piece(glow, tris=60)
    for ang in (0.0, 180.0):
        r = math.radians(ang)
        cx, cz = math.sin(r) * (R - 0.035), math.cos(r) * (R - 0.035)
        gp.add(box((cx, 0.36, cz), (0.03, 0.15, 0.02), 0.012, rot=(0, ang, 0)))
    g.piece("#FF9A3C", tris=40).add(sphere((0.12, H + 0.022, 0.12), 0.013))
    return M(name, [a, g], dc)


# ------------------------------------------------------------------ palette chargée de colis
def pallet(name, seed=9, variant=0):
    """Palette composite chargée de colis cartonnés : rubans adhésifs, étiquettes, cerclage."""
    Wd, D = 1.2, 0.95
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, seed=seed)
    dc = Decals(name)
    pal = a.piece("#474E5C", tris=200, res=0.012, wear=0.35)
    for k in range(5):
        x = -wx + 0.08 + k * (Wd - 0.16) / 4
        pal.add(box((x, 0.12, 0), (0.06, 0.014, dz - 0.005), 0.006))
    # longerons entaillés (passages de fourche)
    for sz in (-1, 0, 1):
        pal.add(box((0, 0.054, sz * (dz - 0.06)), (wx - 0.005, 0.052, 0.055), 0.008))
    for sx in (-1, 1):
        pal.sub(box((sx * wx * 0.5, 0.0, 0), (wx * 0.28, 0.07, dz + 0.1), 0.012), k=0.006)
    # colis : (x, étage, z), demi-tailles
    boxes = [((-0.3, 0, -0.22), (0.28, 0.17, 0.23)), ((0.29, 0, -0.22), (0.29, 0.21, 0.23)),
             ((-0.33, 0, 0.23), (0.25, 0.2, 0.22)), ((0.25, 0, 0.24), (0.33, 0.15, 0.21)),
             ((-0.28, 1, -0.15), (0.22, 0.12, 0.2)), ((0.22, 1, 0.18), (0.2, 0.11, 0.16))]
    if variant:
        boxes = [((0.0, 0, -0.22), (0.57, 0.19, 0.23)), ((-0.3, 0, 0.24), (0.28, 0.21, 0.21)),
                 ((0.3, 0, 0.24), (0.28, 0.16, 0.21)), ((0.2, 1, -0.2), (0.26, 0.12, 0.2))]
    y_top = 0.134
    cb = a.piece(CARDBOARD, tris=260, res=0.014, wear=0.0)
    tops = {}
    for i, ((x, lvl, z), (hx, hy, hz)) in enumerate(boxes):
        base = y_top
        if lvl:
            under = [tops[j] for j, ((x2, l2, z2), (hx2, _, hz2)) in enumerate(boxes) if l2 == 0 and abs(x - x2) < hx2 and abs(z - z2) < hz2]
            base = (min(under) if under else y_top) - 0.002
        tops[i] = base + 2 * hy
        cb.add(box((x, base + hy, z), (hx - 0.01, hy - 0.002, hz - 0.01), 0.012))
        top = base + 2 * hy - 0.002
        # ruban : sur le dessus et descendant sur l'avant
        dc.quad("tape", (x, top, z), 2 * (hx - 0.03), 0.06, TOP, off=0.0015, spin=0)
        dc.quad("tape", (x, top - 0.05, z + hz - 0.01), 0.06, 0.1, FRONT, off=0.0015, spin=90)
        if i % 2 == 0 and lvl == 0 or i == 4:
            dc.quad("tag" if i % 4 == 0 else "tag2", (x - hx * 0.45, base + hy, z + hz - 0.01), 0.12, 0.06, FRONT)
    # cerclage
    ce = a.piece("#3A3D44", tris=80, grime=0.5)
    ht = max(tops[j] for j in range(len(boxes)) if boxes[j][0][1] == 0)
    for x in (-0.15, 0.32):
        ce.add(inter(diff(box((x, (y_top + ht) * 0.5, 0), (0.012, (ht - y_top) * 0.5 + 0.004, dz - 0.004), 0.01),
                          box((x, (y_top + ht) * 0.5, 0), (0.02, (ht - y_top) * 0.5 - 0.004, dz - 0.016), 0.01)),
                     box((x, (y_top + ht) * 0.5 + 0.01, 0), (0.02, (ht - y_top) * 0.5 + 0.004, dz + 0.1), 0.0)))
    return M(name, [a], dc)


# ------------------------------------------------------------------ bobine de câble
def spool(name, seed=11):
    """Bobine de câble couchée : flasques acier ajourés, câble enroulé en spires, bout de câble au sol."""
    R, Wd = 0.4, 0.56
    a = P(name, seed=seed)
    dc = Decals(name)
    fl = a.piece("#5A6676", tris=300, wear=0.4)
    for sx in (-1, 1):
        x = sx * (Wd * 0.5 - 0.025)
        fl.add(cyl((x, R, 0), R, 0.022, 0.012, rot=(0, 0, 90)))
        for k in range(4):
            ang = k * math.pi * 0.5 + math.pi * 0.25
            fl.sub(cyl((x, R + math.sin(ang) * R * 0.6, math.cos(ang) * R * 0.6), 0.06, 0.05, 0.01, rot=(0, 0, 90)), k=0.01)
    hub = a.piece(STEEL, tris=120, wear=0.8)
    hub.add(cyl((0, R, 0), 0.085, Wd * 0.5 + 0.01, 0.015, rot=(0, 0, 90)))
    hub.sub(cyl((0, R, 0), 0.04, Wd * 0.5 + 0.05, 0.005, rot=(0, 0, 90)))
    cb = a.piece("#33363E", tris=450, grime=0.5)
    rc = R - 0.06
    cb.add(cyl((0, R, 0), rc - 0.02, Wd * 0.5 - 0.05, 0.03, rot=(0, 0, 90)))
    for k in range(7):
        x = -Wd * 0.5 + 0.075 + k * (Wd - 0.15) / 6
        cb.add(torus((x, R, 0), rc - 0.02, 0.022, rot=(0, 0, 90)), k=0.012)
    cb.add(capsule((0.12, R + rc - 0.01, 0.05), (0.14, 0.4, rc + 0.05), 0.022), k=0.01)
    cb.add(capsule((0.14, 0.4, rc + 0.05), (0.18, 0.022, R + 0.1), 0.022), k=0.02)
    cb.add(capsule((0.18, 0.022, R + 0.1), (0.5, 0.022, R + 0.22), 0.022), k=0.02)
    a.piece(ORANGE, tris=60, res=0.006, wear=0.5).add(cyl((0.5, 0.022, R + 0.22), 0.03, 0.04, 0.01, rot=(0, 70, 90)))
    xf = Wd * 0.5 - 0.003
    dc.quad("logo_o", (xf, R + 0.24, 0), 0.13, 0.13, RIGHT)
    dc.quad("logo_o", (-xf, R + 0.24, 0), 0.13, 0.13, LEFT)
    dc.quad("N7-4", (xf, R - 0.24, 0), 0.2, 0.075, RIGHT)
    return M(name, [a], dc)


# ------------------------------------------------------------------ servante d'atelier (caisse à outils sur roulettes)
def toolcart(name, seed=13):
    """Servante à tiroirs sur roulettes : caisson rouge éteint, tiroirs et poignées alu, plateau à outils,
    barre de poussée, quatre roulettes pivotantes."""
    Wd, H, D = 0.72, 0.82, 0.46
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, seed=seed)
    dc = Decals(name)
    y0 = 0.14
    body = a.piece("#86605A", tris=320, wear=0.8)
    body.add(box((0, (y0 + H - 0.08) * 0.5, 0), (wx, (H - 0.08 - y0) * 0.5, dz), 0.03))
    ys = [0.2, 0.32, 0.44, 0.56]
    for y in ys + [0.68]:
        body.sub(box((0, y, dz), (wx - 0.04, 0.006, 0.01), 0.003))
    hd = a.piece("#8E949E", tris=120, res=0.007, wear=0.2)
    for y in ys:
        hd.add(box((0, y + 0.06, dz + 0.008), (wx - 0.12, 0.009, 0.01), 0.006))
    tr = a.piece(STEEL, tris=120, wear=1.0)
    tr.add(diff(box((0, H - 0.04, 0), (wx + 0.01, 0.04, dz + 0.01), 0.015), box((0, H, 0), (wx - 0.02, 0.05, dz - 0.02), 0.01)))
    tl = a.piece("#8E949E", tris=120, res=0.007, wear=0.3)
    tl.add(capsule((-0.25, H - 0.035, -0.08), (0.05, H - 0.035, 0.06), 0.011))
    tl.add(torus((-0.27, H - 0.035, -0.09), 0.028, 0.009))
    tl.add(capsule((0.1, H - 0.035, -0.12), (0.28, H - 0.035, -0.1), 0.009))
    a.piece(ORANGE, tris=60, res=0.007, wear=0.3).add(capsule((0.13, H - 0.032, 0.08), (0.24, H - 0.032, 0.11), 0.016))
    hb = a.piece("#8E949E", tris=120, res=0.007, wear=0.2)
    hb.add(capsule((-wx - 0.05, H - 0.1, -0.16), (-wx - 0.05, H - 0.1, 0.16), 0.016))
    for z in (-0.16, 0.16):
        hb.add(capsule((-wx - 0.05, H - 0.1, z), (-wx, H - 0.14, z), 0.014))
    ch = a.piece(STEEL, tris=40, wear=0.8)
    ch.add(box((0, y0 - 0.01, 0), (wx - 0.01, 0.018, dz - 0.01), 0.01))
    wh = a.piece(RUBBER, tris=140, res=0.008, grime=0.4)
    fk = a.piece("#7A808A", tris=80, res=0.008, wear=0.4)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (wx - 0.07), sz * (dz - 0.07)
            wh.add(cyl((x, 0.045, z + 0.015), 0.045, 0.018, 0.012, rot=(0, 0, 90)))
            fk.add(box((x, 0.09, z), (0.03, 0.035, 0.025), 0.01))
    dc.quad("word", (wx, 0.5, 0), 0.3, 0.075, RIGHT)
    dc.quad("tag2", (-wx * 0.6, 0.26, dz), 0.12, 0.06, FRONT)
    for y in ys:
        dc.quad("line", (wx * 0.55, y + 0.06, dz), 0.16, 0.02, FRONT)
    return M(name, [a], dc)


# ------------------------------------------------------------------ petit robot de manutention garé
def robot(name, seed=15):
    """Robot de manutention mignon, garé et éteint : châssis rond sur deux grosses roues, fourches baissées,
    tête-écran inclinée vers le bas (yeux éteints), oreilles orange, antenne à voyant de veille."""
    a = P(name, seed=seed, res=0.008)
    dc = Decals(name)
    body_c = "#D2C292"   # jaune industriel éteint
    body = a.piece(body_c, tris=400, wear=0.25)
    body.add(box((0, 0.3, -0.04), (0.24, 0.17, 0.2), 0.1))
    body.add(ellipsoid((0, 0.45, -0.06), (0.2, 0.06, 0.17)), k=0.05)
    body.sub(box((0, 0.3, 0.18), (0.14, 0.07, 0.02), 0.03), k=0.01)  # baie avant
    dk = a.piece("#454A57", tris=160, wear=0.8)
    dk.add(box((0, 0.15, -0.04), (0.2, 0.05, 0.18), 0.04))
    dk.add(cyl((0, 0.47, -0.06), 0.06, 0.04, 0.015))  # cou
    wh = a.piece(RUBBER, tris=220, grime=0.4)
    for sx in (-1, 1):
        wh.add(cyl((sx * 0.25, 0.13, -0.02), 0.13, 0.04, 0.03, rot=(0, 0, 90)))
    hub = a.piece("#7A808A", tris=100, res=0.007, wear=0.4)
    for sx in (-1, 1):
        hub.add(cyl((sx * 0.292, 0.13, -0.02), 0.06, 0.01, 0.006, rot=(0, 0, 90)))
    fk = a.piece(STEEL, tris=160, wear=0.5)
    fk.add(box((0, 0.16, 0.2), (0.17, 0.08, 0.02), 0.015))
    for sx in (-1, 1):
        fk.add(box((sx * 0.1, 0.02, 0.34), (0.03, 0.012, 0.15), 0.008))
    hd = a.piece(body_c, tris=320, wear=0.2)
    hc = np.array([0.0, 0.6, -0.02])
    hd.add(box(tuple(hc), (0.17, 0.11, 0.12), 0.08, rot=(18, 0, 0)))
    scr = a.piece("#161924", tris=160, res=0.006)
    scr.add(box(tuple(hc + np.array([0, -0.035, 0.115])), (0.13, 0.07, 0.02), 0.05, rot=(18, 0, 0)))
    ey = a.piece("#262C3C", tris=80, res=0.004)
    for sx in (-1, 1):
        ey.add(ellipsoid(tuple(hc + np.array([sx * 0.05, -0.04, 0.132])), (0.022, 0.008, 0.008), rot=(18, 0, 0)))
    ea = a.piece(ORANGE, tris=100, res=0.007, wear=0.5)
    for sx in (-1, 1):
        ea.add(cyl(tuple(hc + np.array([sx * 0.175, 0.0, 0.0])), 0.04, 0.02, 0.01, rot=(0, 0, 90)))
    an = a.piece("#30343F", tris=50, res=0.005)
    an.add(capsule(tuple(hc + np.array([0.08, 0.1, -0.05])), tuple(hc + np.array([0.11, 0.2, -0.08])), 0.007))
    dc.quad("HX-3", (0.24, 0.3, -0.04), 0.14, 0.05, RIGHT)
    dc.quad("HX-3", (-0.24, 0.3, -0.04), 0.14, 0.05, LEFT)
    dc.quad("haz", (0, 0.2, 0.22), 0.3, 0.0375, FRONT, crop=(0, 0, 0.75, 1))
    g = P(name + "_glow", res=0.004)
    g.piece("#FF5A4A", tris=40).add(sphere(tuple(hc + np.array([0.11, 0.21, -0.08])), 0.014))
    return M(name, [a, g], dc)


# ------------------------------------------------------------------ accessoires à plat
def hatch(name, seed=17):
    """Trappe de visite au sol : tôle larmée boulonnée dans un cadre, marquage ACCES."""
    a = P(name, seed=seed)
    dc = Decals(name)
    fr = a.piece("#454B5A", tris=120, wear=0.9)
    fr.add(diff(box((0, 0.012, 0), (0.55, 0.012, 0.42), 0.008), box((0, 0.012, 0), (0.49, 0.05, 0.36), 0.004)))
    pl = a.piece("#5A6272", tris=40, wear=0.6)
    pl.add(box((0, 0.008, 0), (0.48, 0.008, 0.35), 0.004))
    bt = a.piece("#7A808A", tris=120, res=0.006, wear=0.4)
    for sx in (-1, 1):
        for sz in (-1, 1):
            bt.add(cyl((sx * 0.52, 0.025, sz * 0.39), 0.014, 0.006, 0.004))
    for i in range(2):
        for j in range(2):
            dc.quad("tread", ((i - 0.5) * 0.48, 0.016, (j - 0.5) * 0.35), 0.48, 0.35, TOP, off=0.0, crop=(0, 0, 1, 0.73))
    dc.quad("acces", (-0.2, 0.0165, 0.24), 0.3, 0.15, TOP, off=0.0)
    return M(name, [a], dc)


def cables(name, seed=19):
    """Faisceau de câbles posé au sol le long d'un mur (3 m) : trois gaines, colliers, boîtier de raccord."""
    a = P(name, seed=seed)
    dc = Decals(name)
    cols = ["#33363E", "#4A5466", "#7E5E44"]
    L = 3.0
    pts = lambda k, t: (-L * 0.5 + t * L, 0.0, 0.05 * math.sin(t * 7.0 + k * 1.3) + (k - 1) * 0.055)
    for k, c in enumerate(cols):
        pc = a.piece(c, tris=140, res=0.01, grime=0.5)
        r = 0.022 if k != 2 else 0.016
        n = 12
        for i in range(n):
            p0 = list(pts(k, i / n))
            p1 = list(pts(k, (i + 1) / n))
            p0[1] = p1[1] = r
            pc.add(capsule(p0, p1, r), k=0.01)
    cl = a.piece(STEEL_M, tris=120, res=0.008, wear=0.5)
    for t in (0.2, 0.5, 0.8):
        x = -L * 0.5 + t * L
        cl.add(box((x, 0.03, 0.0), (0.025, 0.03, 0.12), 0.012))
    bx = a.piece("#4A505C", tris=160, wear=0.9)
    bx.add(box((L * 0.5 + 0.1, 0.09, 0), (0.12, 0.09, 0.16), 0.03))
    dc.quad("haz", (L * 0.5 + 0.1, 0.12, 0.16), 0.18, 0.045, FRONT, crop=(0, 0, 0.5, 1))
    dc.quad("vent", (L * 0.5 + 0.1, 0.18, 0), 0.14, 0.14, TOP)
    g = P(name + "_glow", res=0.004)
    g.piece("#7CFF9A", tris=40).add(sphere((L * 0.5 + 0.17, 0.06, 0.16), 0.012))
    return M(name, [a, g], dc)


def cone(name, seed=21):
    """Plot de balisage : base carrée lestée, cône orange à bande claire."""
    a = P(name, seed=seed, res=0.006)
    a.piece(RUBBER, tris=80, res=0.008, grime=0.6).add(box((0, 0.015, 0), (0.17, 0.015, 0.17), 0.02))
    cn = a.piece(ORANGE, tris=220, wear=0.4)
    cn.add(capsule((0, 0.03, 0), (0, 0.44, 0), 0.11, 0.02))
    a.piece(CREAM, tris=100, res=0.004).add(diff(cyl((0, 0.26, 0), 0.075, 0.03, 0.005), cyl((0, 0.26, 0), 0.05, 0.05, 0.005)))
    return M(name, [a])


# ------------------------------------------------------------------ catalogue
def catalog():
    H = HULLS
    return {
        "caisse_s_a": lambda: crate("caisse_s_a", 0.6, 0.45, 0.6, H["ardoise"], 1, straps=1, code="", word=False, tris=200),
        "caisse_s_b": lambda: crate("caisse_s_b", 0.6, 0.45, 0.6, H["sable"], 2, straps=1, code="", word=False, tag="tag2", tris=200),
        "caisse_s_c": lambda: crate("caisse_s_c", 0.6, 0.45, 0.6, H["brique"], 3, straps=0, code="", word=False, logo_key="logo_o", tris=200),
        "caisse_m_a": lambda: crate("caisse_m_a", 1.0, 0.6, 0.75, H["ardoise"], 4, code="N7"),
        "caisse_m_b": lambda: crate("caisse_m_b", 1.0, 0.6, 0.75, H["olive"], 5, code="07", tag="tag2"),
        "caisse_m_c": lambda: crate("caisse_m_c", 1.0, 0.6, 0.75, H["petrole"], 6, code="A3", logo_key="logo_o"),
        "caisse_l_a": lambda: crate("caisse_l_a", 1.35, 0.7, 0.9, H["sable"], 7, code="N7-4", tris=280),
        "caisse_l_b": lambda: crate("caisse_l_b", 1.35, 0.7, 0.9, H["petrole"], 8, code="R-12", tag="tag2", tris=280),
        "caisse_t_a": lambda: crate("caisse_t_a", 1.0, 0.8, 1.0, H["ardoise"], 9, code="F-9", tag="tag2", tris=280),
        "caisse_t_b": lambda: crate("caisse_t_b", 1.0, 0.8, 1.0, H["brique"], 10, code="73", logo_key="logo_o", tris=280),
        "caisse_longue_a": lambda: crate("caisse_longue_a", 1.35, 0.5, 0.55, H["olive"], 11, straps=0, code="", latches=True, handles=False, tris=340),
        "caisse_longue_b": lambda: crate("caisse_longue_b", 1.35, 0.5, 0.55, H["ardoise"], 12, straps=0, code="", latches=True, handles=False, tag="tag2", tris=340),
        "bachee_a": lambda: tarp("bachee_a", "#66756E", 13),
        "bachee_b": lambda: tarp("bachee_b", "#7A7264", 14),
        "danger": lambda: hazmat("danger", 15),
        "cellule_a": lambda: cell("cellule_a", "#56636E", 16),
        "cellule_b": lambda: cell("cellule_b", "#6E7060", 17),
        "palette_a": lambda: pallet("palette_a", 18, 0),
        "palette_b": lambda: pallet("palette_b", 19, 1),
        "bobine": lambda: spool("bobine", 20),
        "servante": lambda: toolcart("servante", 21),
        "robot": lambda: robot("robot", 22),
        "trappe": lambda: hatch("trappe", 23),
        "cables": lambda: cables("cables", 24),
        "plot": lambda: cone("plot", 25),
    }


def _job(name):
    ch = catalog()[name]()
    ch.export(os.path.join(OUT, name + ".glb"))
    return name


if __name__ == "__main__":
    AT.build()
    AT.build_noise()
    names = sys.argv[1:] or list(catalog().keys())
    with Pool(4) as pool:
        for n in pool.imap_unordered(_job, names):
            pass
