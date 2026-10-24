"""Briques communes du décor du Relais (base des Passeurs), sculpté comme les personnages (tools/sculpt.py).

Unités : celles de la scène du Relais (Jo y mesure environ 2,5 : modèle de 1,05 mis à l'échelle 2,4).
Chaque script tools/decor/relais_*.py décrit un ou plusieurs objets ; `export(nom, parts)` écrit
assets/decor/relais/<nom>.glb. Les parts dont le nom contient « _glow » sont rendues lumineuses en jeu
(scripts/decor/relais.gd). Le décor statique est ensuite fusionné en un seul maillage au montage.

Usage : python3 tools/decor/relais_<groupe>.py [objet ...]   (sans argument : tous les objets du groupe)
"""
import math
import os
import sys

import numpy as np
import trimesh
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))
import sculpt  # noqa: E402
from sculpt import *  # noqa: E402,F401,F403
from sculpt import Shape, Part as _Part, simplify_to, rot_matrix, _local  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "decor", "relais"))

# palette du Relais : coques claires et chaudes de la flotte des Passeurs, métal bleu nuit, accents de Jo
HULL = "#E9E6DE"      # coque blanche cassée (comme la combinaison de Jo)
HULL_D = "#C9C5BA"    # coque, partie basse
STEEL = "#3A4672"     # métal bleu
STEEL_D = "#26305A"   # métal bleu sombre
NAVY = "#1A2142"      # structure sombre
NAVY_D = "#11162E"    # creux, rainures
DECK = "#28315A"      # dalles du pont
DECK_L = "#2F3A66"    # dalles claires
ORANGE = "#FF7A2F"
TEAL = "#3CF2D8"
GOLD = "#FFB347"
VIOLET = "#8E6BFF"
WHITE = "#FFFFFF"
RUBBER = "#1C2033"


class Part(_Part):
    """Part dont les normales sont celles, exactes, du champ de distance (comme tools/chars/drone.py) :
    surfaces lisses sans taches de facettes après allègement. Occlusion simulée le long de ces normales."""

    def _surface(self, pc, res):
        lo, hi = pc.bounds()
        # grille décalée d'une fraction de maille : des faces planes posées pile sur la grille donnent des
        # zéros exacts, donc des trous dans le maillage, que l'allègement ne sait plus réduire
        lo = lo - res * 0.371
        n = np.ceil((hi - lo) / res).astype(int) + 1
        xs = [np.linspace(lo[i], lo[i] + (n[i] - 1) * res, n[i]) for i in range(3)]
        # évaluation par tranches en X : mémoire bornée même pour les grandes pièces de décor
        vol = np.empty(tuple(n), dtype=np.float32)
        YZ = np.stack(np.meshgrid(xs[1], xs[2], indexing="ij"), axis=-1).reshape(-1, 2)
        step = max(1, 400000 // len(YZ))
        for i0 in range(0, n[0], step):
            xi = xs[0][i0:i0 + step]
            G = np.concatenate([np.repeat(xi, len(YZ))[:, None], np.tile(YZ, (len(xi), 1))], axis=1)
            vol[i0:i0 + len(xi)] = pc.sdf(G).reshape(len(xi), n[1], n[2])
        if vol.min() > 0 or vol.max() < 0:
            return None
        verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(res,) * 3)
        verts = verts + lo
        if len(faces) > pc.tris:
            verts, faces = simplify_to(verts, faces, pc.tris)
        return verts, faces

    def _piece_mesh(self, pc):
        res = pc.res or self.res
        # certaines tailles de maille donnent des triangles en lame que l'allègement ne réduit plus :
        # on retente avec une maille un peu différente et on garde le meilleur résultat
        best = None
        for f in (1.0, 1.13, 0.89, 1.27):
            r = self._surface(pc, res * f)
            if r is None:
                return None
            if best is None or len(r[1]) < len(best[1]):
                best = r
            if len(best[1]) <= pc.tris * 1.3:
                break
        verts, faces = best
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = res * 0.25
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V)
        occ = np.ones(len(V))
        s = self.ao_scale
        for dist, w in ((0.025 * s, 0.5), (0.06 * s, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.78, 1.0) ** w
        y = V[:, 1]
        grad = 0.9 + 0.1 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        if "_glow" in self.name:
            occ[:] = 1.0
            grad[:] = 1.0
        c = np.clip(col * (occ * grad)[:, None], 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm, N

    ao_scale = 1.0

    def piece(self, color, tris=800, res=None):
        pc = FastPiece(color, tris, res)
        self.pieces.append(pc)
        return pc

    def mesh(self):
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        tm = trimesh.util.concatenate([o[0] for o in out])
        normals = np.concatenate([o[1] for o in out])
        tm.apply_translation(-self.pivot)
        tm.vertex_normals = normals
        return tm


class FastPiece(sculpt.Piece):
    """Piece dont chaque opération n'est évaluée que dans sa boîte englobante (élargie) : ailleurs, la
    distance à la boîte sert de minorant. Indispensable pour les pièces de décor faites de dizaines de
    formes réparties sur plusieurs mètres."""

    def sdf(self, P):
        d = None
        for op in self.ops:
            if op[0] == "paint":
                continue
            sh, k = op[1], op[2]
            m = 0.06 + 2.0 * k
            lo = sh.lo - m
            hi = sh.hi + m
            inside = np.all((P >= lo) & (P <= hi), axis=1)
            q = np.maximum(np.maximum(lo - P, P - hi), 0.0)
            ds = np.linalg.norm(q, axis=1) + m
            if inside.any():
                ds[inside] = sh(P[inside])
            if op[0] == "add":
                d = ds if d is None else smin(d, ds, k)
            else:
                # soustraction : sans effet hors de sa boîte
                if inside.any():
                    d[inside] = smax(d[inside], -ds[inside], k)
        return d


def part(name, pivot=(0, 0, 0), parent=None, res=0.02, ao=1.0):
    p = Part(name, pivot=pivot, parent=parent, res=res)
    p.ao_scale = ao
    return p


def export(name, parts):
    path = os.path.join(OUT, name + ".glb")
    sculpt.Character(name, parts).export(path)


def run(builders, argv):
    """builders : {nom: fonction() -> liste de parts}. Exporte ceux demandés (tous par défaut)."""
    names = argv[1:] or list(builders.keys())
    for n in names:
        export(n, builders[n]())


# ------------------------------------------------------------------ formes en plus
def _tight(shape, c, half, rot):
    """Remplace la boîte englobante (cube dans sculpt.py) par celle, serrée, d'une boîte tournée."""
    R = rot_matrix(*rot)
    ext = np.abs(R) @ np.asarray(half, dtype=np.float64)
    c = np.asarray(c, dtype=np.float64)
    shape.lo = c - ext
    shape.hi = c + ext
    return shape


def cyl(c, r, h, rr=0.01, rot=(0, 0, 0)):
    """Cylindre d'axe Y (sculpt.cyl) à boîte englobante serrée."""
    return _tight(sculpt.cyl(c, r, h, rr, rot), c, (r, h, r), rot)


def rbox(c, half, r=0.02, rot=(0, 0, 0)):
    """Boîte arrondie (sculpt.rbox) à boîte englobante serrée."""
    return _tight(sculpt.rbox(c, half, r, rot), c, half, rot)


def torus(c, R0, r, rot=(0, 0, 0)):
    return _tight(sculpt.torus(c, R0, r, rot), c, (R0 + r, r, R0 + r), rot)


def ellipsoid(c, radii, rot=(0, 0, 0)):
    return _tight(sculpt.ellipsoid(c, radii, rot), c, radii, rot)


def sector(c, r0, r1, a0, a1, h, rr=0.02):
    """Dalle en secteur d'anneau, d'axe Y : rayons r0..r1, angles a0..a1 (radians, depuis +X vers +Z),
    demi-épaisseur h, arêtes arrondies rr. Distance approchée (bonne près de la surface)."""
    c = np.asarray(c, dtype=np.float64)
    am = 0.5 * (a0 + a1)
    ah = 0.5 * (a1 - a0)
    def f(P):
        Q = P - c
        r = np.linalg.norm(Q[:, [0, 2]], axis=1)
        a = np.arctan2(Q[:, 2], Q[:, 0]) - am
        a = (a + math.pi) % (2 * math.pi) - math.pi
        # distance aux bords radiaux : arc de rayon r
        d_ang = (np.abs(a) - ah) * r
        d_rad = np.abs(r - 0.5 * (r0 + r1)) - 0.5 * (r1 - r0)
        d_y = np.abs(Q[:, 1]) - h
        d = np.stack([d_ang + rr, d_rad + rr, d_y + rr], axis=1)
        out = np.linalg.norm(np.maximum(d, 0.0), axis=1)
        return out + np.minimum(d.max(axis=1), 0.0) - rr
    return Shape(f, *_arc_bounds(c, r0, r1, a0, a1, h))


def ring(c, R0, half_w, h, rr=0.02, rot=(0, 0, 0)):
    """Anneau plat d'axe Y (rayon moyen R0, demi-largeur radiale half_w, demi-hauteur h), arêtes arrondies."""
    c = np.asarray(c, dtype=np.float64)
    Rm = rot_matrix(*rot)
    def f(P):
        Q = _local(P, c, Rm)
        q = np.stack([np.abs(np.linalg.norm(Q[:, [0, 2]], axis=1) - R0) - (half_w - rr), np.abs(Q[:, 1]) - (h - rr)], axis=1)
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rr
    return _tight(Shape(f, c, c), c, (R0 + half_w, h, R0 + half_w), rot)


def arc_ring(c, R0, half_w, h, a0, a1, rr=0.02, rot=(0, 0, 0)):
    """Portion d'anneau plat (angles a0..a1 dans le plan XZ local), extrémités arrondies."""
    c = np.asarray(c, dtype=np.float64)
    Rm = rot_matrix(*rot)
    am = 0.5 * (a0 + a1)
    ah = 0.5 * (a1 - a0)
    def f(P):
        Q = _local(P, c, Rm)
        r = np.linalg.norm(Q[:, [0, 2]], axis=1)
        a = np.arctan2(Q[:, 2], Q[:, 0]) - am
        a = (a + math.pi) % (2 * math.pi) - math.pi
        d_ang = (np.abs(a) - ah) * R0
        d = np.stack([np.abs(r - R0) - (half_w - rr), np.abs(Q[:, 1]) - (h - rr), d_ang], axis=1)
        return np.linalg.norm(np.maximum(d, 0.0), axis=1) + np.minimum(d.max(axis=1), 0.0) - rr
    if rot == (0, 0, 0):
        return Shape(f, *_arc_bounds(c, R0 - half_w, R0 + half_w, a0, a1, h))
    m = R0 + half_w + h
    return Shape(f, c - m, c + m)


def _arc_bounds(c, r0, r1, a0, a1, h):
    """Boîte englobante d'un secteur d'anneau d'axe Y."""
    angs = list(np.linspace(a0, a1, 33))
    pts = [(r * math.cos(a), r * math.sin(a)) for a in angs for r in (r0, r1)]
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    lo = c + np.array([min(xs), -h, min(zs)])
    hi = c + np.array([max(xs), h, max(zs)])
    return lo, hi


def union(*shapes):
    """Union franche de formes (une seule Shape)."""
    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = np.minimum(d, s(P))
        return d
    lo = np.min([s.lo for s in shapes], axis=0)
    hi = np.max([s.hi for s in shapes], axis=0)
    return Shape(f, lo, hi)


def translate(s, off):
    off = np.asarray(off, dtype=np.float64)
    return Shape(lambda P: s.fn(P - off), s.lo + off, s.hi + off)


def crystal(c, r, h, sides=6, twist=0.0, seed=0):
    """Cristal facetté (maillage direct, pas de SDF) : prisme pointu aux deux bouts, facettes légèrement
    irrégulières. Rend un trimesh déjà coloré en blanc (teinté par le matériau en jeu)."""
    rng = np.random.default_rng(seed)
    c = np.asarray(c, dtype=np.float64)
    pts = [c + [0, h, 0], c + [0, -h * 0.55, 0]]
    for k in range(sides):
        a = 2 * math.pi * k / sides + twist
        rr = r * (0.85 + 0.3 * rng.random())
        pts.append(c + [rr * math.cos(a), h * 0.32 + 0.05 * rng.standard_normal() * h, rr * math.sin(a)])
        a2 = a + math.pi / sides
        pts.append(c + [r * 0.8 * math.cos(a2), -h * 0.05, r * 0.8 * math.sin(a2)])
    tm = trimesh.convex.convex_hull(np.array(pts))
    tm.unmerge_vertices()  # facettes franches
    return tm
