"""Cité Néon — outils communs de la coque du toit (tools/decor/neon_shell_*.py).

Dimensions du toit et de la façade voisine (partagées avec scripts/decor/neon_shell.gd et les shaders neon_*),
idéogrammes inventés, constructeur de maillages (repère monde, un seul matériau à atlas).
Les bruits, le dessin anti-crénelé et l'écriture PNG / GLB viennent de shell_common.py (monde 1).
"""
import math
import os

import numpy as np

from shell_common import (FONT_RAJ, FONT_RUSSO, H, K, ROOT, TOP, W, WALL, Canvas, aniso_noise, blur, blur_noise,
                          fbm, height_to_normal, norm01, save_rgba, smoothstep, srgb, write_glb, write_json)

OUT = os.path.join(ROOT, "assets", "decor", "neon", "shell")

# ---------------------------------------------------------------- toit (m)
PAR_T = 0.32            # épaisseur des parapets
PAR_H = 0.5             # hauteur des parapets (sous la couvertine)
ZN = 3.3                # face nord du toit (le vide entre le toit et la tour voisine au-delà)
X0, X1 = PAR_T, W - PAR_T          # faces intérieures des parapets ouest / est
Z0, Z1 = ZN + PAR_T, H - PAR_T     # faces intérieures des parapets nord / sud
NX, NZ = 31, 15                    # dalles du toit
CX, CZ = (X1 - X0) / NX, (Z1 - Z0) / NZ
# carte unique du toit (flaques, crasse, traînées, huile)
MW, MH = 2048, 1024
MX0, MZ0, MXW, MZH = 0.0, ZN, W, W * MH / MW
# passerelle vers la tour voisine (x du milieu, largeur)
BRIDGE_X, BRIDGE_W = 33.9, 1.3

# ---------------------------------------------------------------- tour voisine, au nord
ZF = 0.0                # plan de la façade
FX0, FX1 = -5.25, W + 5.25         # carte de la façade (réflexions) : 48 m x 48 m
FY0, FY1 = -8.0, 40.0
FLOOR_H = 3.4           # hauteur d'étage
FLOOR_Y0 = 0.9          # niveau d'une dalle (bandeau) de la tour voisine
BAY_W = 2.4             # travée de fenêtre
ROOF_Y = 12.8           # toit du socle de la tour voisine
TOWER_X0, TOWER_X1, TOWER_Y = 9.0, 29.0, 34.0   # la tour elle-même, au-dessus du socle

# palette (brief Cité Néon)
PINK = srgb("#FF3CAC")
BLUE = srgb("#3C8CFF")
VIOLET = srgb("#8E4CFF")
ACID = srgb("#B6FF3C")
ORANGE = srgb("#FF8A3C")
NEONS = {"pink": PINK, "blue": BLUE, "violet": VIOLET, "acid": ACID, "orange": ORANGE}

# classes de sommets (COLOR.a) : 0 peint / béton, 1/3 métal, 2/3 caoutchouc, 1 lumineux
PAINT, BARE, RUBBER, GLOW = 0.0, 1 / 3, 2 / 3, 1.0
# animations (UV2.x) : 0 fixe, 0,25 grésille, 0,5 clignote, 0,75 écran
A_NONE, A_BUZZ, A_BLINK, A_SCREEN = 0.0, 0.25, 0.5, 0.75


# ---------------------------------------------------------------- idéogrammes inventés
def _component(rng, x0, y0, x1, y1):
    """Un élément d'idéogramme dans la boîte (x0, y0, x1, y1) : barres, cadre, croix, obliques, point."""
    S = []
    w, h = x1 - x0, y1 - y0
    k = rng.integers(0, 7)
    if k == 0:  # barres empilées
        n = rng.integers(2, 4)
        for i in range(n):
            y = y0 + h * (i + 0.5) / n
            m = w * (0.12 if i == n - 1 else rng.uniform(0.0, 0.2))
            S.append(((x0 + m, y), (x1 - m, y)))
    elif k == 1:  # cadre (parfois avec barre)
        S += [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x0, y0), (x0, y1)), ((x0, y1), (x1, y1))]
        if rng.random() < 0.6:
            S.append(((x0, y0 + h * 0.5), (x1, y0 + h * 0.5)))
    elif k == 2:  # croix
        cx = x0 + w * rng.uniform(0.4, 0.6)
        S += [((x0, y0 + h * 0.35), (x1, y0 + h * 0.35)), ((cx, y0), (cx, y1))]
        if rng.random() < 0.5:
            S.append(((x0 + w * 0.2, y1), (x1 - w * 0.2, y1)))
    elif k == 3:  # deux obliques (jambes)
        cx = x0 + w * 0.5
        S += [((cx, y0 + h * 0.2), (x0, y1)), ((cx, y0 + h * 0.2), (x1, y1))]
        S.append(((x0 + w * 0.15, y0), (x1 - w * 0.15, y0)))
    elif k == 4:  # crochet
        S += [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x1 - w * 0.25, y1 - h * 0.15))]
        S.append(((x0 + w * 0.2, y0 + h * 0.35), (x0 + w * 0.2, y1)))
    elif k == 5:  # colonne et ticks
        cx = x0 + w * 0.5
        S.append(((cx, y0), (cx, y1)))
        S.append(((x0, y0 + h * 0.3), (cx, y0 + h * 0.15)))
        S.append(((cx, y0 + h * 0.55), (x1, y0 + h * 0.4)))
        S.append(((x0 + w * 0.1, y1), (x1 - w * 0.1, y1)))
    else:  # trois points et une barre
        for i in range(3):
            px = x0 + w * (0.2 + 0.3 * i)
            S.append(((px, y0 + h * 0.15), (px + w * 0.06, y0 + h * 0.35)))
        S.append(((x0, y0 + h * 0.65), (x1, y0 + h * 0.65)))
        S.append(((x0 + w * 0.5, y0 + h * 0.65), (x0 + w * 0.5, y1)))
    return S


def glyph_strokes(rng):
    """Un idéogramme inventé : un ou deux éléments (gauche / droite, haut / bas, enveloppe). Aucun vrai signe."""
    a, b = 0.1, 0.9
    split = rng.choice([0, 0, 1, 1, 2, 3])
    if split == 0:
        m = rng.uniform(0.38, 0.48)
        return _component(rng, a, a, m, b) + _component(rng, m + 0.1, a, b, b)
    if split == 1:
        m = rng.uniform(0.38, 0.5)
        return _component(rng, a, a, b, m) + _component(rng, a, m + 0.1, b, b)
    if split == 2:  # enveloppe : toit et côté, élément dedans
        S = [((a, a + 0.08), (b, a + 0.08)), ((a + 0.12, a + 0.08), (a, b))]
        return S + _component(rng, a + 0.3, a + 0.3, b, b)
    return _component(rng, a, a, b, b) + ([((0.5, 0.0), (0.5, a + 0.02))] if rng.random() < 0.5 else [])


def draw_glyphs(n, seed=4242):
    """n idéogrammes d'au moins cinq traits (les signes trop simples ressembleraient à de vrais caractères)."""
    rng = np.random.default_rng(seed)
    out = []
    while len(out) < n:
        g = glyph_strokes(rng)
        if len(g) >= 5:
            out.append(g)
    return out


def glyph_mask(strokes, px, width=0.09, ss=3):
    cv = Canvas(px, px, ss)
    for (a, b) in strokes:
        cv.line([(a[0] * px, a[1] * px), (b[0] * px, b[1] * px)], width * px)
        for p in (a, b):
            cv.ellipse(p[0] * px, p[1] * px, width * px * 0.5, width * px * 0.5)
    return cv.array()


def glyph_text(cv, x, y, h, glyphs, ids, width=0.09, gap=0.18, vertical=False):
    """Écrit une suite d'idéogrammes sur un Canvas (x, y = coin haut gauche, h = corps en px)."""
    for k, gi in enumerate(ids):
        ox = x + (0 if vertical else k * h * (1 + gap))
        oy = y + (k * h * (1 + gap) if vertical else 0)
        for (a, b) in glyphs[gi % len(glyphs)]:
            cv.line([(ox + a[0] * h, oy + a[1] * h), (ox + b[0] * h, oy + b[1] * h)], width * h)
            for p in (a, b):
                cv.ellipse(ox + p[0] * h, oy + p[1] * h, width * h * 0.5, width * h * 0.5)


# ---------------------------------------------------------------- atlas à étagères
class Atlas:
    """Atlas rangé en ligne d'horizon (chaque région se pose au plus haut possible)."""

    def __init__(self, w, h, pad=6):
        self.w, self.h, self.pad = w, h, pad
        self.img = np.zeros((h, w, 4), np.float32)
        self.reg = {}
        self.sky = np.zeros(w, int)

    def _spot(self, ww, hh):
        best = None
        p = self.pad
        for x in range(p, self.w - ww - p + 1, 4):
            y = int(self.sky[x - p:x + ww + p].max()) + p
            if y + hh + p <= self.h and (best is None or y < best[1]):
                best = (x, y)
        return best

    def put(self, name, rgba):
        hh, ww = rgba.shape[:2]
        sp = self._spot(ww, hh)
        if sp is None:
            raise RuntimeError("atlas plein : " + name)
        x, y = sp
        self.img[y:y + hh, x:x + ww] = np.clip(rgba, 0, 1)
        p = min(3, self.pad // 2)
        self.img[y - p:y, x:x + ww] = self.img[y:y + 1, x:x + ww]
        self.img[y + hh:y + hh + p, x:x + ww] = self.img[y + hh - 1:y + hh, x:x + ww]
        self.img[y - p:y + hh + p, x - p:x] = self.img[y - p:y + hh + p, x:x + 1]
        self.img[y - p:y + hh + p, x + ww:x + ww + p] = self.img[y - p:y + hh + p, x + ww - 1:x + ww]
        self.reg[name] = (x, y, ww, hh)
        self.sky[x:x + ww] = y + hh

    def uv(self, name, sub=None):
        """Cadre UV (u0, v0, u1, v1), éventuellement une sous-partie (fractions)."""
        x, y, w, h = self.reg[name]
        u0, v0, u1, v1 = x / self.w, y / self.h, (x + w) / self.w, (y + h) / self.h
        if sub:
            a, b, c, d = sub
            u0, v0, u1, v1 = u0 + (u1 - u0) * a, v0 + (v1 - v0) * b, u0 + (u1 - u0) * c, v0 + (v1 - v0) * d
        # demi-texel de marge
        e = 0.5 / self.w
        return (u0 + e, v0 + e, u1 - e, v1 - e)


# ---------------------------------------------------------------- maillages (repère monde)
class MB:
    """Triangles en repère monde : position, normale, UV (atlas), UV2 (animation, phase), COLOR (teinte, classe)."""

    def __init__(self):
        self.P, self.N, self.UV, self.UV2, self.C = [], [], [], [], []

    def tri(self, ps, ns, uvs, col, cls, anim=(0.0, 0.0)):
        P = [np.array(p, float) for p in ps]
        Nn = [np.array(n, float) for n in ns]
        g = np.cross(P[1] - P[0], P[2] - P[0])
        if np.dot(g, Nn[0] + Nn[1] + Nn[2]) < 0:
            P = [P[0], P[2], P[1]]
            Nn = [Nn[0], Nn[2], Nn[1]]
            uvs = [uvs[0], uvs[2], uvs[1]]
        for i in range(3):
            self.P.append(P[i])
            self.N.append(Nn[i] / (np.linalg.norm(Nn[i]) + 1e-9))
            self.UV.append(uvs[i])
            self.UV2.append(anim)
            self.C.append((col[0], col[1], col[2], cls))

    def quad(self, c, right, up, hw, hh, uv, col, cls=PAINT, anim=(0.0, 0.0), normal=None):
        c, r, u = np.array(c, float), np.array(right, float), np.array(up, float)
        r /= np.linalg.norm(r)
        u /= np.linalg.norm(u)
        n = np.cross(r, u) if normal is None else np.array(normal, float)
        a, b, cc, d = c - r * hw - u * hh, c + r * hw - u * hh, c + r * hw + u * hh, c - r * hw + u * hh
        u0, v0, u1, v1 = uv
        self.tri([a, b, cc], [n] * 3, [(u0, v1), (u1, v1), (u1, v0)], col, cls, anim)
        self.tri([a, cc, d], [n] * 3, [(u0, v1), (u1, v0), (u0, v0)], col, cls, anim)

    def box(self, lo, hi, uv, col, cls=PAINT, faces="xXyYzZ", anim=(0.0, 0.0), uvs=None, tile=None):
        """Boîte alignée (lo, hi coins) ; faces : x (-x), X (+x), y, Y, z, Z. tile : m par répétition d'UV
        (alors l'UV couvre une tuile de `tile` m et la face la répète en coupant le cadre)."""
        lo, hi = np.array(lo, float), np.array(hi, float)
        c = (lo + hi) * 0.5
        s = (hi - lo) * 0.5
        uvs = uvs or {}
        F = {
            "x": ((c[0] - s[0], c[1], c[2]), (0, 0, 1), (0, 1, 0), s[2], s[1]),
            "X": ((c[0] + s[0], c[1], c[2]), (0, 0, -1), (0, 1, 0), s[2], s[1]),
            "y": ((c[0], c[1] - s[1], c[2]), (1, 0, 0), (0, 0, 1), s[0], s[2]),
            "Y": ((c[0], c[1] + s[1], c[2]), (1, 0, 0), (0, 0, -1), s[0], s[2]),
            "z": ((c[0], c[1], c[2] - s[2]), (-1, 0, 0), (0, 1, 0), s[0], s[1]),
            "Z": ((c[0], c[1], c[2] + s[2]), (1, 0, 0), (0, 1, 0), s[0], s[1]),
        }
        for f in faces:
            p, r, u, a, b = F[f]
            if a < 1e-5 or b < 1e-5:
                continue
            if tile:
                self.tiled(p, r, u, a, b, uvs.get(f, uv), col, cls, anim, tile)
            else:
                self.quad(p, r, u, a, b, uvs.get(f, uv), col, cls, anim)

    def tiled(self, c, right, up, hw, hh, uv, col, cls, anim, tile):
        """Face découpée en tuiles de `tile` m le long de right (l'UV se répète sans shader)."""
        c, r, u = np.array(c, float), np.array(right, float), np.array(up, float)
        L = hw * 2
        n = max(1, int(math.ceil(L / tile - 1e-3)))
        u0, v0, u1, v1 = uv
        for i in range(n):
            a = -hw + i * tile
            b = min(hw, a + tile)
            f = (b - a) / tile
            cc = c + r * (a + b) * 0.5
            self.quad(cc, r, u, (b - a) * 0.5, hh, (u0, v0, u0 + (u1 - u0) * f, v1), col, cls, anim)

    def cyl(self, a, b, r, uv, col, cls=BARE, seg=8, caps=False, anim=(0.0, 0.0), r2=None):
        a, b = np.array(a, float), np.array(b, float)
        r2 = r if r2 is None else r2
        ax = b - a
        L = np.linalg.norm(ax)
        ax /= L
        t = np.cross(ax, (0, 1, 0) if abs(ax[1]) < 0.9 else (1, 0, 0))
        t /= np.linalg.norm(t)
        s = np.cross(ax, t)
        u0, v0, u1, v1 = uv
        for i in range(seg):
            a0 = 2 * math.pi * i / seg
            a1 = 2 * math.pi * (i + 1) / seg
            n0 = t * math.cos(a0) + s * math.sin(a0)
            n1 = t * math.cos(a1) + s * math.sin(a1)
            ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
            self.tri([a + n0 * r, b + n0 * r2, b + n1 * r2], [n0, n0, n1], [(ua, v1), (ua, v0), (ub, v0)], col, cls, anim)
            self.tri([a + n0 * r, b + n1 * r2, a + n1 * r], [n0, n1, n1], [(ua, v1), (ub, v0), (ub, v1)], col, cls, anim)
            if caps:
                for cc, rr, sg in ((a, r, -1), (b, r2, 1)):
                    self.tri([cc, cc + n0 * rr, cc + n1 * rr], [ax * sg] * 3, [(u0, v0)] * 3, col, cls, anim)

    def tube(self, pts, r, uv, col, cls=RUBBER, seg=5, anim=(0.0, 0.0)):
        for p, q in zip(pts[:-1], pts[1:]):
            self.cyl(p, q, r, uv, col, cls, seg, anim=anim)

    def sphere(self, c, r, uv, col, cls=PAINT, seg=8, rings=5, anim=(0.0, 0.0), sy=1.0):
        c = np.array(c, float)
        u0, v0, u1, v1 = uv

        def p(i, j):
            th = math.pi * j / rings
            ph = 2 * math.pi * i / seg
            n = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
            return c + n * r * np.array([1, sy, 1]), n

        for j in range(rings):
            for i in range(seg):
                (a, na), (b, nb), (cc, nc), (d, nd) = p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)
                uvq = [(u0, v0), (u1, v0), (u1, v1)]
                if j > 0:
                    self.tri([a, b, cc], [na, nb, nc], uvq, col, cls, anim)
                if j < rings - 1:
                    self.tri([a, cc, d], [na, nc, nd], [(u0, v0), (u1, v1), (u0, v1)], col, cls, anim)

    def count(self):
        return len(self.P) // 3

    def arrays(self):
        """Sommets identiques fusionnés."""
        allv = np.concatenate([np.array(self.P), np.array(self.N), np.array(self.UV), np.array(self.UV2), np.array(self.C)], 1)
        key = np.round(allv, 5)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        u = allv[np.unique(inv.reshape(-1), return_index=True)[1]]
        return {"pos": u[:, 0:3], "nrm": u[:, 3:6], "uv": u[:, 6:8], "uv2": u[:, 8:10], "col": u[:, 10:14],
                "idx": inv.reshape(-1, 3)}


def catenary(a, b, sag, n=10):
    a, b = np.array(a, float), np.array(b, float)
    return [a + (b - a) * t - np.array([0, sag * 4 * t * (1 - t), 0]) for t in np.linspace(0, 1, n)]
