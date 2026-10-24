"""Atelier du quai nord (Nébuleuse 7, baie 07) : briques communes aux objets sculptés du décor.

Même principe que tools/sculpt.py (SDF, marching cubes, allègement, couleurs par sommet), avec en plus ce qu'il
faut à des objets de station plutôt qu'à des personnages :
  - normales exactes du champ de distance (coques lisses, pas de taches de facettes) ;
  - peinture usée : arêtes vives écaillées (le métal nu apparaît, courbure estimée par le laplacien du champ),
    creux encrassés, salissures en bruit 3D basse fréquence, pied des objets plus sale (poussière du quai) ;
  - formes orientées (boîte, cylindre, tore d'axe quelconque), intersections, demi-espaces, tuyaux.
Les objets sont sculptés en mètres, à l'échelle du jeu (1 unité = 1 m), sol à y = 0.
Sortie : assets/decor/bay/<nom>.glb (voir bay_build.py)."""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))

import numpy as np
import trimesh
from skimage import measure

import sculpt
from sculpt import (Shape, Piece, Part, Character, sphere, ellipsoid, capsule, rbox, cyl, torus, mirror_x,
                    smin, smax, hexcol, rot_matrix, simplify_to)

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "decor", "bay"))

# ------------------------------------------------------------------ palette du quai (saturation modérée)
WHITE = "#F4F1EA"       # coque du vaisseau des Passeurs (Jo)
WHITE_D = "#D8D3C8"
ORANGE = "#FF7A2F"
ORANGE_D = "#C85A24"
TEAL = "#3CF2D8"        # lumières des Passeurs
STEEL = "#7E8696"       # métal nu (écaillures, pièces usinées)
STEEL_L = "#A9B0BC"
GUN = "#3A4152"         # métal peint sombre
GUN_D = "#262B38"
NAVY = "#2A3350"        # structure de la station
NAVY_D = "#1B2133"
SLATE = "#4A5368"
YELLOW = "#E2B23C"      # jaune de sécurité, un peu passé
BLACK = "#16181F"
RUBBER = "#1E2026"
GLASS = "#132A36"
GLASS_L = "#5C98A8"
ORVA = "#4E9C8E"        # vert d'eau de la compagnie de fret ORVA
ORVA_D = "#2F6B62"
CREAM = "#A39C8A"
WARM = "#FFD9A0"        # éclairage intérieur (lumineux)


def v(*a):
    return np.array(a, dtype=np.float64)


def nrm(a):
    a = np.asarray(a, dtype=np.float64)
    return a / np.linalg.norm(a)


def frame(zdir, up=(0, 1, 0)):
    """Repère orthonormé (colonnes x, y, z) dont l'axe z suit zdir."""
    z = nrm(zdir)
    x = np.cross(np.asarray(up, dtype=np.float64), z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross(v(1, 0, 0), z)
    x = nrm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def R(rx=0.0, ry=0.0, rz=0.0):
    """Matrice d'orientation (colonnes = axes locaux) à partir d'angles en degrés."""
    return rot_matrix(rx, ry, rz)


# ------------------------------------------------------------------ formes orientées
def obox(c, half, r=0.02, M=None):
    """Boîte arrondie, orientée par M (colonnes = axes locaux)."""
    c = np.asarray(c, dtype=np.float64)
    hb = np.asarray(half, dtype=np.float64) - r
    M = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
    def f(P):
        Q = np.abs((P - c) @ M) - hb
        return np.linalg.norm(np.maximum(Q, 0.0), axis=1) + np.minimum(Q.max(axis=1), 0.0) - r
    m = float(np.linalg.norm(half))
    return Shape(f, c - m, c + m)


def box(c, half, r=0.015):
    """Boîte alignée aux axes, bornes serrées (moins de calcul que obox)."""
    c = np.asarray(c, dtype=np.float64)
    h = np.asarray(half, dtype=np.float64)
    hb = h - r
    def f(P):
        Q = np.abs(P - c) - hb
        return np.linalg.norm(np.maximum(Q, 0.0), axis=1) + np.minimum(Q.max(axis=1), 0.0) - r
    return Shape(f, c - h, c + h)


def ocyl(c, r, h, rr=0.01, M=None):
    """Cylindre d'axe local z (rayon r, demi-longueur h), bords arrondis rr."""
    c = np.asarray(c, dtype=np.float64)
    M = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        d = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - (r - rr), np.abs(Q[:, 2]) - (h - rr)], axis=1)
        return np.minimum(d.max(axis=1), 0.0) + np.linalg.norm(np.maximum(d, 0.0), axis=1) - rr
    m = math.sqrt(r * r + h * h)
    return Shape(f, c - m, c + m)


def xcyl(c, r, h, rr=0.01):
    """Cylindre d'axe X."""
    return ocyl(c, r, h, rr, frame((1, 0, 0)))


def zcyl(c, r, h, rr=0.01):
    """Cylindre d'axe Z."""
    return ocyl(c, r, h, rr, np.eye(3))


def ycyl(c, r, h, rr=0.01):
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = P - c
        d = np.stack([np.linalg.norm(Q[:, [0, 2]], axis=1) - (r - rr), np.abs(Q[:, 1]) - (h - rr)], axis=1)
        return np.minimum(d.max(axis=1), 0.0) + np.linalg.norm(np.maximum(d, 0.0), axis=1) - rr
    return Shape(f, c - v(r, h, r), c + v(r, h, r))


def otorus(c, R0, r, M=None):
    """Tore dans le plan local xy (axe local z)."""
    c = np.asarray(c, dtype=np.float64)
    M = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        q = np.stack([np.linalg.norm(Q[:, [0, 1]], axis=1) - R0, Q[:, 2]], axis=1)
        return np.linalg.norm(q, axis=1) - r
    m = R0 + r
    return Shape(f, c - m, c + m)


def oellip(c, radii, M=None):
    c = np.asarray(c, dtype=np.float64)
    rr = np.asarray(radii, dtype=np.float64)
    M = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
    def f(P):
        Q = (P - c) @ M
        k0 = np.linalg.norm(Q / rr, axis=1)
        k1 = np.linalg.norm(Q / (rr * rr), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    m = rr.max()
    return Shape(f, c - m, c + m)


def ellip(c, radii):
    """Ellipsoïde aligné, bornes serrées."""
    c = np.asarray(c, dtype=np.float64)
    rr = np.asarray(radii, dtype=np.float64)
    s = ellipsoid(c, rr)
    return Shape(s.fn, c - rr, c + rr)


def tube(points, r, k=0.0):
    """Tuyau : chaîne de capsules (r constant ou liste de rayons), union douce k aux coudes."""
    pts = [np.asarray(p, dtype=np.float64) for p in points]
    rs = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    segs = [capsule(pts[i], pts[i + 1], rs[i], rs[i + 1]) for i in range(len(pts) - 1)]
    def f(P):
        d = segs[0](P)
        for s in segs[1:]:
            d = smin(d, s(P), k)
        return d
    lo = np.min([s.lo for s in segs], axis=0) - k * 0.3
    hi = np.max([s.hi for s in segs], axis=0) + k * 0.3
    return Shape(f, lo, hi)


def bezier(p0, p1, p2, p3, n=10):
    """Points d'une courbe de Bézier cubique (tuyaux souples)."""
    P = [np.asarray(p, dtype=np.float64) for p in (p0, p1, p2, p3)]
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 3) * P[0] + 3 * ((1 - t) ** 2) * t * P[1] + 3 * (1 - t) * t * t * P[2] + t ** 3 * P[3])
    return out


def union(shapes, k=0.0):
    def f(P):
        d = shapes[0](P)
        for s in shapes[1:]:
            d = smin(d, s(P), k)
        return d
    pad = k * 0.3  # l'union douce déborde un peu des formes
    return Shape(f, np.min([s.lo for s in shapes], axis=0) - pad, np.max([s.hi for s in shapes], axis=0) + pad)


def inter(a, b, k=0.0):
    """Intersection (douce si k > 0) ; boîte englobante commune."""
    return Shape(lambda P: smax(a(P), b(P), k), np.maximum(a.lo, b.lo), np.minimum(a.hi, b.hi))


def diff(a, b, k=0.0):
    return Shape(lambda P: smax(a(P), -b(P), k), a.lo, a.hi)


def offset(a, d):
    """Forme gonflée de d (dégonflée si d < 0)."""
    return Shape(lambda P: a(P) - d, a.lo - max(d, 0), a.hi + max(d, 0))


def shell(a, t):
    """Coque d'épaisseur t autour de la surface de a (vers l'intérieur)."""
    return Shape(lambda P: np.maximum(a(P), -a(P) - t), a.lo, a.hi)


def halfspace(p0, n):
    """Demi-espace des points du côté opposé à n."""
    p0 = np.asarray(p0, dtype=np.float64)
    n = nrm(n)
    return Shape(lambda P: (P - p0) @ n, p0 - 60, p0 + 60)


def slab(axis, lo, hi):
    """Tranche lo <= P[axis] <= hi (infinie dans les deux autres axes)."""
    def f(P):
        return np.maximum(lo - P[:, axis], P[:, axis] - hi)
    L = v(-60, -60, -60); H = v(60, 60, 60)
    L[axis] = lo; H[axis] = hi
    return Shape(f, L, H)


def moved(s, t=(0, 0, 0), M=None):
    """Forme déplacée (translation t, rotation M appliquée à la forme)."""
    t = np.asarray(t, dtype=np.float64)
    M = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
    def f(P):
        return s((P - t) @ M)
    corners = np.array([[x, y, z] for x in (s.lo[0], s.hi[0]) for y in (s.lo[1], s.hi[1]) for z in (s.lo[2], s.hi[2])])
    W = corners @ M.T + t
    return Shape(f, W.min(axis=0), W.max(axis=0))


# ------------------------------------------------------------------ bruit 3D (salissures)
def _hash3(ix, iy, iz):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(P):
    Pi = np.floor(P).astype(np.int64)
    f = P - Pi
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(P))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out += w * _hash3(Pi[:, 0] + dx, Pi[:, 1] + dy, Pi[:, 2] + dz)
    return out


def fbm(P, oct=3):
    a, s, tot, out = 1.0, 1.0, 0.0, np.zeros(len(P))
    for i in range(oct):
        out += a * vnoise(P * s + i * 17.3)
        tot += a
        a *= 0.5
        s *= 2.03
    return out / tot


# ------------------------------------------------------------------ allègement
def decimate(verts, faces, goal):
    """Allège jusqu'au budget en une passe (rarement deux). Les passes successives de sculpt.simplify_to,
    secouées quand elles calent, effondrent les objets à plusieurs volumes (fûts, caisses) : pas ici."""
    import fast_simplification
    V = np.asarray(verts, dtype=np.float32)
    F = np.asarray(faces, dtype=np.int32)
    for _ in range(4):
        if len(F) <= goal * 1.05:
            break
        V2, F2 = fast_simplification.simplify(V, F, target_reduction=1.0 - goal / len(F))
        if len(F2) >= len(F) * 0.97:
            break
        V, F = V2, F2
    return V, F


# ------------------------------------------------------------------ échantillonnage en bande étroite
def narrow_band(sdf, lo, n, res, B=8):
    """Champ sur la grille fine (n points par axe, pas res) : évalué finement seulement dans les blocs de B³
    cellules proches de la surface ; ailleurs, la valeur au centre du bloc (le signe suffit au marching cubes)."""
    nb = np.ceil(n / B).astype(int)
    cs = [lo[i] + (np.arange(nb[i]) * B + (B - 1) * 0.5) * res for i in range(3)]
    C = np.stack(np.meshgrid(*cs, indexing="ij"), axis=-1).reshape(-1, 3)
    dc = sdf(C).reshape(nb)
    half = B * res * 0.5 * math.sqrt(3.0)
    active = np.argwhere(np.abs(dc) < half * 1.8 + 2 * res)
    vol = np.repeat(np.repeat(np.repeat(dc.astype(np.float32), B, 0), B, 1), B, 2)
    o = np.stack(np.meshgrid(np.arange(B), np.arange(B), np.arange(B), indexing="ij"), axis=-1).reshape(-1, 3)
    step = max(1, 2000000 // (B ** 3))
    for k in range(0, len(active), step):
        blk = active[k:k + step]
        idx = (blk[:, None, :] * B + o[None, :, :]).reshape(-1, 3)
        P = lo + idx * res
        vol[idx[:, 0], idx[:, 1], idx[:, 2]] = sdf(P).astype(np.float32)
    return vol[:n[0], :n[1], :n[2]]


# ------------------------------------------------------------------ pièces peintes et usées
class BPiece(Piece):
    """Volume d'une couleur ; wear = écaillage des arêtes (0 = neuf), dirt = encrassement."""
    def __init__(self, color, tris=800, res=None, wear=0.5, dirt=1.0, bare=STEEL):
        super().__init__(color, tris, res)
        self.wear = wear
        self.dirt = dirt
        self.bare = hexcol(bare)


class BPart(Part):
    """Part du décor : normales exactes du champ, peinture usée, salissures. Les parts « *_glow » restent
    unies (elles sont rendues lumineuses, sans ombrage)."""
    def __init__(self, name, pivot=(0, 0, 0), parent=None, res=0.02, floor=0.0, seed=0.0):
        super().__init__(name, pivot, parent, res)
        self.floor = floor  # hauteur du sol (pied sale)
        self.seed = seed
        self.stains = []  # (centre, rayon, force, couleur) : suie des tuyères, huile, rouille
        self.prims = []  # maillages directs (tubes droits, lattes) : (trimesh, couleur, axe ou None)

    def prim_box(self, color, c, half, M=None):
        """Boîte à arêtes vives, maillée directement (12 triangles) : lattes, stries, plaques fines."""
        T = np.eye(4)
        T[:3, :3] = np.eye(3) if M is None else np.asarray(M, dtype=np.float64)
        T[:3, 3] = c
        self.prims.append((trimesh.creation.box(extents=2 * np.asarray(half, dtype=np.float64), transform=T), hexcol(color), None))
        return self

    def prim_cyl(self, color, a, b, r, sections=10):
        """Tube droit maillé directement (normales radiales lisses) : gaines, lisses, barres."""
        a = np.asarray(a, dtype=np.float64)
        b = np.asarray(b, dtype=np.float64)
        tm = trimesh.creation.cylinder(radius=r, segment=np.stack([a, b]), sections=sections)
        self.prims.append((tm, hexcol(color), (a, nrm(b - a))))
        return self

    def _prim_meshes(self):
        out = []
        for tm, col, axis in self.prims:
            t = tm.copy()
            t.unmerge_vertices()
            V = np.asarray(t.vertices, dtype=np.float64)
            FN = np.repeat(np.asarray(t.face_normals), 3, axis=0)
            N = FN.copy()
            if axis is not None:
                a, d = axis
                side = np.abs(FN @ d) < 0.5
                R = (V - a) - np.outer((V - a) @ d, d)
                R /= np.maximum(np.linalg.norm(R, axis=1), 1e-9)[:, None]
                N[side] = R[side]
            g = fbm((V + self.seed) * 1.7 + 3.1, 3)
            c = np.clip(col[None, :] * (0.93 + 0.12 * (g - 0.5))[:, None], 0, 1)
            if self.pieces:
                occ = np.ones(len(V))
                for dist, w in ((0.03, 0.5), (0.09, 0.6)):
                    dd = self.sdf(V + N * dist)
                    occ *= np.clip(0.6 + 0.4 * dd / dist, 0.72, 1.0) ** w
                c = c * occ[:, None]
            rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
            t.visual = trimesh.visual.ColorVisuals(t, vertex_colors=(rgba * 255).astype(np.uint8))
            out.append((t, N))
        return out

    def stain(self, c, r, s, color=BLACK):
        self.stains.append((np.asarray(c, dtype=np.float64), r, s, hexcol(color)))
        return self

    def piece(self, color, tris=800, res=None, wear=0.5, dirt=1.0, bare=STEEL):
        pc = BPiece(color, tris, res, wear, dirt, bare)
        self.pieces.append(pc)
        return pc

    def _surface(self, pc, res):
        lo, hi = pc.bounds()
        lo = lo - res * np.array([0.371, 0.293, 0.417])  # grille décalée : pas de faces planes pile sur les nœuds
        n = np.ceil((hi - lo) / res).astype(int) + 1
        if np.prod(n) > 6e7:
            raise RuntimeError(f"{self.name} : grille trop grande {n} (res {res})")
        vol = narrow_band(pc.sdf, lo, n, res)
        if vol.min() > 0 or vol.max() < 0:
            return None
        verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(res,) * 3)
        pre = trimesh.Trimesh(vertices=verts + lo, faces=faces, process=True)
        pre.update_faces(pre.nondegenerate_faces())
        pre.remove_unreferenced_vertices()
        return np.asarray(pre.vertices), np.asarray(pre.faces)

    def _piece_mesh(self, pc):
        res = pc.res or self.res
        # l'allègement cale parfois sur les formes longues et fines : on remaille alors plus grossièrement
        best = None
        for mul in (1.0, 1.5, 2.1):
            sf = self._surface(pc, res * mul)
            if sf is None:
                break
            verts, faces = sf
            n0 = len(faces)
            vol0 = abs(trimesh.Trimesh(verts, faces, process=False).volume)
            goal = pc.tris
            v0, f0 = verts, faces
            while len(f0) > goal:
                verts, faces = decimate(v0, f0, goal)
                vol1 = abs(trimesh.Trimesh(verts, faces, process=False).volume)
                # budget trop maigre pour la forme (plusieurs volumes, plaques fines) : on le relève
                if vol0 < 1e-7 or vol1 / vol0 > 0.8 or goal >= pc.tris * 4:
                    break
                goal *= 2
            if os.environ.get("BAY_VERBOSE"):
                vol1 = abs(trimesh.Trimesh(verts, faces, process=False).volume)
                if vol0 > 1e-6 and abs(vol1 / vol0 - 1) > 0.12:
                    print(f"    ! {self.name} volume {vol0:.4f} -> {vol1:.4f} ({len(faces)} tris)")
            if best is None or len(faces) < len(best[1]):
                best = (verts, faces, n0)
            if len(faces) <= pc.tris * 1.3:
                break
        if best is None:
            return None
        verts, faces, n0 = best
        if os.environ.get("BAY_VERBOSE"):
            print(f"    {self.name}/{'#%02x%02x%02x' % tuple(int(c * 255) for c in pc.color)} {len(faces)} <- {n0} budget {pc.tris}")
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = 1e-3
        # l'allègement décolle les sommets de la surface (coques bosselées) : on les y reprojette
        for _ in range(2):
            d = pc.sdf(V)
            G = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1) / (2 * e)
            gl = np.maximum(np.linalg.norm(G, axis=1), 1e-9)
            step = np.clip(d / gl, -res, res)
            V = V - (G / gl[:, None]) * step[:, None]
        tm.vertices = V
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V).astype(np.float64)
        glow = "_glow" in self.name or "_blink" in self.name
        if not glow:
            # courbure : laplacien du champ (> 0 sur les arêtes vives, < 0 dans les creux)
            h = max(res * 1.2, 0.012)
            d0 = pc.sdf(V)
            lap = -6.0 * d0
            for i in range(3):
                lap = lap + pc.sdf(V + np.eye(3)[i] * h) + pc.sdf(V - np.eye(3)[i] * h)
            lap /= h * h
            Pn = V + self.seed
            n1 = fbm(Pn * 7.0, 3)
            edge = np.clip(lap * 0.03, 0.0, 1.0)
            chip = np.clip((n1 - 0.52) * 4.0, 0.0, 1.0) * edge * pc.wear * 0.75
            col = col * (1 - chip[:, None]) + pc.bare[None, :] * chip[:, None]
            cav = np.clip(-lap * 0.012, 0.0, 0.35) * pc.dirt
            g = fbm(Pn * 1.7 + 3.1, 3)
            grime = (0.93 + 0.12 * (g - 0.5)) - cav
            low = np.clip((V[:, 1] - self.floor) / 0.35, 0.0, 1.0)
            grime *= 1.0 - (1.0 - low) * 0.16 * pc.dirt
            col = col * grime[:, None]
            for sc, sr, ss, scol in self.stains:
                d = np.linalg.norm(V - sc, axis=1) / sr
                w = np.exp(-d * d) * ss * (0.55 + 0.9 * fbm(Pn * 4.0 + 7.7, 2))
                w = np.clip(w, 0.0, 0.9)[:, None]
                col = col * (1 - w) + scol[None, :] * w
            occ = np.ones(len(V))
            for dist, w in ((0.03, 0.5), (0.09, 0.6)):
                dd = self.sdf(V + N * dist)
                occ *= np.clip(0.6 + 0.4 * dd / dist, 0.72, 1.0) ** w
            col = col * occ[:, None]
        c = np.clip(col, 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm, N

    def mesh(self):
        self.pieces = [pc for pc in self.pieces if any(o[0] == "add" for o in pc.ops)]
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        out += self._prim_meshes()
        tm = trimesh.util.concatenate([o[0] for o in out])
        normals = np.concatenate([o[1] for o in out])
        tm.apply_translation(-self.pivot)
        tm.vertex_normals = normals
        return tm


class Prop(Character):
    """Objet du décor : un GLB dans assets/decor/bay/."""
    def export(self, path=None):
        path = path or os.path.join(OUT, self.name + ".glb")
        return super().export(path)
