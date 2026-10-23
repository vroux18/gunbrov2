"""Atelier de sculpture des personnages de Passeurs.

Chaque personnage est décrit en champs de distance signée (SDF) : sphères, capsules, boîtes arrondies,
fondues entre elles (union douce). Chaque pièce animée (tête, torse, bras, jambes, arme...) est sculptée
séparément autour de son pivot, transformée en maillage (marching cubes), allégée, colorée par sommet
(couleur de la forme la plus proche, occlusion ambiante simulée, léger dégradé vertical), puis exportée en
un seul GLB hiérarchisé. Godot anime ensuite ces pièces en code (scripts/rig3d.gd).

Usage : python3 tools/sculpt.py <personnage> [<personnage>...]   (voir tools/chars/*.py)
"""
import math
import os
import sys
import importlib.util

import numpy as np
from skimage import measure
import trimesh
import fast_simplification

# ------------------------------------------------------------------ maths
def rot_matrix(rx=0.0, ry=0.0, rz=0.0):
    """Matrice de rotation (degrés), ordre X puis Y puis Z appliqué au point."""
    a, b, c = map(math.radians, (rx, ry, rz))
    X = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    Y = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    Z = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return Z @ Y @ X


def hexcol(h):
    h = h.lstrip('#')
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float32) / 255.0


# ------------------------------------------------------------------ formes
class Shape:
    """Une forme SDF : distance(P) pour P (N,3) dans le repère du personnage ; boîte englobante."""
    def __init__(self, fn, lo, hi):
        self.fn = fn
        self.lo = np.array(lo, dtype=np.float64)
        self.hi = np.array(hi, dtype=np.float64)

    def __call__(self, P):
        return self.fn(P)


def _local(P, center, R):
    Q = P - np.asarray(center, dtype=np.float64)
    if R is not None:
        Q = Q @ R  # inverse de la rotation (R orthonormée) appliqué aux points : Q·R = Rᵀ·q
    return Q


def sphere(c, r):
    c = np.asarray(c, dtype=np.float64)
    return Shape(lambda P: np.linalg.norm(P - c, axis=1) - r, c - r, c + r)


def ellipsoid(c, radii, rot=(0, 0, 0)):
    """Ellipsoïde (distance approchée de Quilez, bonne près de la surface)."""
    c = np.asarray(c, dtype=np.float64)
    rr = np.asarray(radii, dtype=np.float64)
    R = rot_matrix(*rot)
    def f(P):
        Q = _local(P, c, R)
        k0 = np.linalg.norm(Q / rr, axis=1)
        k1 = np.linalg.norm(Q / (rr * rr), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    m = rr.max()
    return Shape(f, c - m, c + m)


def capsule(a, b, r1, r2=None):
    """Capsule ou cône arrondi de a (rayon r1) à b (rayon r2)."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    if r2 is None:
        r2 = r1
    ba = b - a
    l2 = float(ba @ ba)
    def f(P):
        pa = P - a
        h = np.clip((pa @ ba) / max(l2, 1e-12), 0.0, 1.0)
        d = np.linalg.norm(pa - h[:, None] * ba, axis=1)
        return d - (r1 + (r2 - r1) * h)
    m = max(r1, r2)
    return Shape(f, np.minimum(a, b) - m, np.maximum(a, b) + m)


def rbox(c, half, r=0.02, rot=(0, 0, 0)):
    """Boîte à coins arrondis (demi-tailles `half`, rayon d'arrondi r)."""
    c = np.asarray(c, dtype=np.float64)
    hb = np.asarray(half, dtype=np.float64) - r
    R = rot_matrix(*rot)
    def f(P):
        Q = np.abs(_local(P, c, R)) - hb
        out = np.linalg.norm(np.maximum(Q, 0.0), axis=1)
        inside = np.minimum(Q.max(axis=1), 0.0)
        return out + inside - r
    m = float(np.linalg.norm(half))
    return Shape(f, c - m, c + m)


def cyl(c, r, h, rr=0.01, rot=(0, 0, 0)):
    """Cylindre d'axe Y (rayon r, demi-hauteur h), bords arrondis rr."""
    c = np.asarray(c, dtype=np.float64)
    R = rot_matrix(*rot)
    def f(P):
        Q = _local(P, c, R)
        d = np.stack([np.linalg.norm(Q[:, [0, 2]], axis=1) - (r - rr), np.abs(Q[:, 1]) - (h - rr)], axis=1)
        return np.minimum(d.max(axis=1), 0.0) + np.linalg.norm(np.maximum(d, 0.0), axis=1) - rr
    m = math.sqrt(r * r + h * h)
    return Shape(f, c - m, c + m)


def torus(c, R0, r, rot=(0, 0, 0)):
    c = np.asarray(c, dtype=np.float64)
    Rm = rot_matrix(*rot)
    def f(P):
        Q = _local(P, c, Rm)
        q = np.stack([np.linalg.norm(Q[:, [0, 2]], axis=1) - R0, Q[:, 1]], axis=1)
        return np.linalg.norm(q, axis=1) - r
    m = R0 + r
    return Shape(f, c - m, c + m)


def mirror_x(s):
    """Même forme, symétrique par rapport au plan x = 0."""
    def f(P):
        Q = P.copy()
        Q[:, 0] = -Q[:, 0]
        return s.fn(Q)
    lo = s.lo.copy(); hi = s.hi.copy()
    lo[0], hi[0] = -s.hi[0], -s.lo[0]
    return Shape(f, lo, hi)


# ------------------------------------------------------------------ pièces
def smin(a, b, k):
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


class Piece:
    """Volume d'une seule couleur (avec peintures éventuelles) : union douce, soustraction."""
    def __init__(self, color, tris=800, res=None):
        self.color = hexcol(color) if isinstance(color, str) else color
        self.tris = tris
        self.res = res
        self.ops = []

    def add(self, shape, k=0.0):
        self.ops.append(("add", shape, k))
        return self

    def sub(self, shape, k=0.0):
        self.ops.append(("sub", shape, k))
        return self

    def paint(self, shape, color):
        self.ops.append(("paint", shape, hexcol(color)))
        return self

    def sdf(self, P):
        d = None
        for op in self.ops:
            if op[0] == "add":
                ds = op[1](P)
                d = ds if d is None else smin(d, ds, op[2])
            elif op[0] == "sub":
                d = smax(d, -op[1](P), op[2])
        return d

    def colors(self, P):
        col = np.tile(self.color, (len(P), 1)).astype(np.float32)
        for op in self.ops:
            if op[0] == "paint":
                col[op[1](P) < 0.0] = op[2]
        return col

    def bounds(self):
        lo = np.min([o[1].lo for o in self.ops if o[0] == "add"], axis=0)
        hi = np.max([o[1].hi for o in self.ops if o[0] == "add"], axis=0)
        pad = 0.03 + max([o[2] for o in self.ops if o[0] != "paint"] + [0.0])
        return lo - pad, hi + pad


class Part:
    """Pièce animée : plusieurs volumes de couleur, fusionnés en un seul maillage (un appel de dessin)
    dont les arêtes de couleur restent nettes. pivot : articulation (repère du personnage) ; parent : pièce parente.
    """
    def __init__(self, name, pivot=(0, 0, 0), parent=None, res=0.007):
        self.name = name
        self.pivot = np.asarray(pivot, dtype=np.float64)
        self.parent = parent
        self.res = res
        self.pieces = []

    def piece(self, color, tris=800, res=None):
        pc = Piece(color, tris, res)
        self.pieces.append(pc)
        return pc

    def sdf(self, P):
        d = None
        for pc in self.pieces:
            ds = pc.sdf(P)
            d = ds if d is None else np.minimum(d, ds)
        return d

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
            verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), target_reduction=1.0 - pc.tris / len(faces))
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        N = np.asarray(tm.vertex_normals, dtype=np.float64)
        col = pc.colors(V)
        # occlusion ambiante simulée avec tous les volumes de la pièce (contact cheveux / visage, plis)
        occ = np.ones(len(V))
        for dist, w in ((0.025, 0.5), (0.06, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.8, 1.0) ** w
        y = V[:, 1]
        grad = 0.92 + 0.08 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        c = np.clip(col * (occ * grad)[:, None], 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm

    def mesh(self):
        ms = [m for m in (self._piece_mesh(pc) for pc in self.pieces) if m is not None]
        tm = trimesh.util.concatenate(ms)
        tm.apply_translation(-self.pivot)
        return tm


class Character:
    def __init__(self, name, parts):
        self.name = name
        self.parts = parts

    def export(self, path):
        scene = trimesh.Scene()
        by_name = {p.name: p for p in self.parts}
        # les racines d'abord, puis les enfants (le parent doit exister dans le graphe)
        done = set()
        order = []
        while len(order) < len(self.parts):
            for p in self.parts:
                if p.name in done:
                    continue
                if p.parent is None or p.parent in done:
                    order.append(p)
                    done.add(p.name)
        total = 0
        for p in order:
            tm = p.mesh()
            total += len(tm.faces)
            parent_pivot = by_name[p.parent].pivot if p.parent else np.zeros(3)
            T = np.eye(4)
            T[:3, 3] = p.pivot - parent_pivot
            scene.add_geometry(tm, node_name=p.name, geom_name=p.name + "_mesh", parent_node_name=p.parent if p.parent else None, transform=T)
            print(f"  {p.name:10s} {len(tm.faces):6d} triangles")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.export(path)
        print(f"{self.name} : {total} triangles -> {path}")


def run(name):
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("char_" + name, os.path.join(here, "chars", name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["sculpt"] = sys.modules[__name__]
    spec.loader.exec_module(mod)
    ch = mod.build()
    out = os.path.join(here, "..", "assets", "chars3d", name + ".glb")
    ch.export(os.path.normpath(out))


if __name__ == "__main__":
    for n in sys.argv[1:]:
        run(n)
