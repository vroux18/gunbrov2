#!/usr/bin/env python3
"""Nébuleuse 7 — sol du hangar : plan des tôles, textures et marquages peints.

Écrit dans assets/decor/shell/ :
  deck_layout.json   plan des tôles (grille 48 x 23 cases de 0,758 m), cadres de l'atlas, marquages à poser
  deck_detail.png    1024² tuile de 2 m : R variation d'albédo, G rayures, B écaillage, A rugosité
  deck_detail_n.png  1024² normales de la même tuile (grain, bosses, rayures en creux)
  deck_macro.png     2048x1024, tout le sol sans répétition : R crasse, G usure, B huile, A traces de pneus
  deck_atlas.png     2048² : moitié haute = marquages peints (RGBA), moitié basse = trappes et grilles
                     (RGB albédo, A hauteur ; hauteur < 0,1 = fond lumineux des grilles)
Lancement : python3 tools/decor/shell_floor.py
"""
import math
import os

import numpy as np

from shell_common import (CELL, FONT_RAJ, FONT_RUSSO, GX0, GZ0, H, NX, NZ, OUT, TOP, W, WALL, Canvas,
                          aniso_noise, blur, blur_noise, fbm, height_to_normal, norm01, save_rgba,
                          smoothstep, srgb, write_json)

R = np.random.default_rng(1977)

PLAIN, HATCH, MANHOLE, GRATE_H, GRATE_V, DRAIN, SERVICE, VENT, LIFT = range(9)
KIND_CELLS = {HATCH: (2, 2), MANHOLE: (2, 2), GRATE_H: (2, 1), GRATE_V: (1, 2), DRAIN: (1, 1),
              SERVICE: (2, 1), VENT: (4, 1), LIFT: (4, 4)}
KIND_NAMES = ["plain", "hatch", "manhole", "grate_h", "grate_v", "drain", "service", "vent", "lift"]


# ================================================================ plan des tôles
def cell_x(c):
    return GX0 + c * CELL


def cell_z(r):
    return GZ0 + r * CELL


AISLE_ROWS = (9, 13)    # allée est-ouest : rangées 9..12
AISLE_COLS = (22, 26)   # allée nord-sud : colonnes 22..25 (centre x = W/2)
LIFTS = [(5, 2), (37, 15)]          # monte-charges 4x4 (col, rangée)
ZONES = [(30, 1, 8, 6), (8, 15, 8, 6)]  # zones de chargement peintes (col, rangée, largeur, hauteur)


def build_layout():
    pid = -np.ones((NZ, NX), int)
    panels = []

    def free(x, z, w, h):
        return x >= 0 and z >= 0 and x + w <= NX and z + h <= NZ and (pid[z:z + h, x:x + w] < 0).all()

    def put(x, z, w, h, k=PLAIN):
        pid[z:z + h, x:x + w] = len(panels)
        panels.append([x, z, w, h, k])

    # caniveaux le long des murs ouest et est : tôles étroites, une grille sur trois
    for c in (0, NX - 1):
        n = 0
        for r in range(0, NZ, 2):
            h = min(2, NZ - r)
            put(c, r, 1, h, GRATE_V if (n % 3 == 1 and h == 2) else PLAIN)
            n += 1
    # bande sud au pied du garde-corps
    n = 0
    for c in range(1, NX - 1, 2):
        put(c, NZ - 1, min(2, NX - 1 - c), 1, GRATE_H if n % 4 == 2 else PLAIN)
        n += 1
    # seuil du quai : tôles longues, deux coffrets de service
    c = 1
    n = 0
    while c < NX - 1:
        w = min(4, NX - 1 - c)
        if n in (2, 8) and w >= 2:
            put(c, 0, 2, 1, SERVICE)
            c += 2
        else:
            put(c, 0, w, 1)
            c += w
        n += 1
    # croisement central : une grande tôle (le logo y est peint)
    a0, a1 = AISLE_ROWS
    b0, b1 = AISLE_COLS
    put(b0, a0, b1 - b0, a1 - a0)
    # allée est-ouest : tôles 4x2 en quinconce
    for r, start in ((a0, 1), (a0 + 2, 1)):
        c = start
        first = (r == a0 + 2)
        while c < NX - 1:
            if b0 <= c < b1:
                c = b1
                first = (r == a0 + 2)
                continue
            lim = b0 if c < b0 else NX - 1
            w = 2 if first else 4
            first = False
            w = min(w, lim - c)
            if lim - c - w == 1:
                w += 1
            put(c, r, w, 2)
            c += w
    # allée nord-sud : tôles 2x4 en quinconce
    for c, start in ((b0, 1), (b0 + 2, 1)):
        r = start
        first = (c == b0 + 2)
        while r < NZ - 1:
            if a0 <= r < a1:
                r = a1
                first = (c == b0 + 2)
                continue
            lim = a0 if r < a0 else NZ - 1
            h = 2 if first else 4
            first = False
            h = min(h, lim - r)
            if lim - r - h == 1:
                h += 1
            put(c, r, 2, h)
            r += h
    # monte-charges
    for (c, r) in LIFTS:
        put(c, r, 4, 4, LIFT)
    # grilles longues au bord de l'allée est-ouest
    for c in (4, 15, 30, 41):
        for r in (a0 - 1, a1):
            if free(c, r, 4, 1) and R.random() < 0.75:
                put(c, r, 4, 1, VENT)
    # trappes, regards, coffrets, siphons au hasard dans les champs

    def scatter(kind, count, tries=400):
        w, h = KIND_CELLS[kind]
        done = 0
        for _ in range(tries):
            if done >= count:
                break
            c = int(R.integers(2, NX - 2 - w))
            r = int(R.integers(1, NZ - 1 - h))
            # pas dans les zones de chargement peintes, une case de marge autour
            if any(zc - 1 <= c < zc + zw + 1 and zr - 1 <= r < zr + zh + 1 for zc, zr, zw, zh in ZONES):
                continue
            if free(c - 1, r - 1, w + 2, h + 2):
                put(c, r, w, h, kind)
                done += 1

    scatter(HATCH, 6)
    scatter(MANHOLE, 3)
    scatter(SERVICE, 3)
    scatter(GRATE_H, 4)
    scatter(DRAIN, 7)
    # remplissage : tôles de 2 à 6 cases
    for r in range(NZ):
        for c in range(NX):
            if pid[r, c] >= 0:
                continue
            w = int(R.choice([2, 3, 3, 4, 4, 5, 6]))
            h = int(R.choice([2, 2, 3, 3, 4, 5]))
            ww = 0
            while ww < w and c + ww < NX and pid[r, c + ww] < 0:
                ww += 1
            hh = 1
            while hh < h and r + hh < NZ and (pid[r + hh, c:c + ww] < 0).all():
                hh += 1
            put(c, r, ww, hh)
    # données par tôle : graine, variante (0 d'origine, 1 remplacée, 2 très usée)
    for p in panels:
        p.append(int(R.integers(0, 256)))
        u = R.random()
        p.append(1 if u < 0.13 else (2 if u < 0.27 else 0))
    return pid, panels


def layout_cells(pid, panels):
    cells = []
    for r in range(NZ):
        row = []
        for c in range(NX):
            x, z, w, h, k, seed, var = panels[pid[r, c]]
            fl = (1 if c == x else 0) | (2 if r == z else 0) | (4 if c == x + w - 1 else 0) | (8 if r == z + h - 1 else 0)
            row.append([seed, fl | (k << 4), (c - x) | ((r - z) << 4), var])
        cells.append(row)
    return cells


# ================================================================ tuile de détail
def make_detail():
    N = 1024  # 2 m -> 512 px/m
    print("tuile de détail")
    mott = blur_noise(N, N, 60, 11) * 0.55 + blur_noise(N, N, 14, 12) * 0.3 + blur_noise(N, N, 1.2, 13) * 0.25
    roll = aniso_noise(N, N, 3, 90, 14) * 0.25   # traces de rouleau de peinture
    albvar = np.clip(0.5 + (mott + roll) * 0.16, 0, 1)
    # rayures : traits fins, surtout dans le sens de circulation
    cv = Canvas(N, N, 2)
    for i in range(420):
        ang = (R.normal(0, 0.35) if R.random() < 0.7 else R.uniform(0, math.pi))
        ln = R.uniform(15, 260) * (1.6 if R.random() < 0.1 else 1.0)
        x0, y0 = R.uniform(0, N), R.uniform(0, N)
        bend = R.normal(0, 0.15)
        pts = []
        for t in np.linspace(0, 1, 8):
            a = ang + bend * t
            pts.append((x0 + math.cos(a) * ln * t, y0 + math.sin(a) * ln * t))
        val = int(R.uniform(70, 255))
        wd = R.uniform(0.5, 1.4)
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                cv.line([(px + ox, py + oy) for px, py in pts], wd, val)
    scr = cv.array()
    # rayures en arc (pivotement de roues)
    cv2 = Canvas(N, N, 2)
    for i in range(26):
        cx, cy = R.uniform(0, N), R.uniform(0, N)
        rad = R.uniform(60, 300)
        a0 = R.uniform(0, 2 * math.pi)
        span = R.uniform(0.3, 1.2)
        for k in range(int(R.integers(2, 6))):
            rr = rad + k * R.uniform(2, 5)
            pts = [(cx + math.cos(a0 + span * t) * rr, cy + math.sin(a0 + span * t) * rr) for t in np.linspace(0, 1, 24)]
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    cv2.line([(px + ox, py + oy) for px, py in pts], 0.6, int(R.uniform(60, 160)))
    scr = np.clip(scr + cv2.array(), 0, 1)
    chips = norm01(blur_noise(N, N, 5, 15) * 0.6 + blur_noise(N, N, 22, 16) * 0.8 + blur_noise(N, N, 1.5, 17) * 0.25)
    rough = np.clip(0.5 + blur_noise(N, N, 35, 18) * 0.18 + aniso_noise(N, N, 70, 8, 19) * 0.08, 0, 1)
    det = np.stack([albvar, scr, chips, rough], -1)
    save_rgba(os.path.join(OUT, "deck_detail.png"), det)
    # hauteur : bosses douces, grain, rayures en creux, petites piqûres
    hm = blur_noise(N, N, 40, 21) * 0.5 + blur_noise(N, N, 9, 22) * 0.12 + blur_noise(N, N, 1.0, 23) * 0.05
    pits = (blur_noise(N, N, 1.6, 24) > 2.6).astype(np.float32)
    hm = hm - scr * 0.35 - blur(pits, 1.0, True) * 0.6
    nm = height_to_normal(hm, 1.6)
    save_rgba(os.path.join(OUT, "deck_detail_n.png"), nm)


# ================================================================ crasse, usure, huile (tout le sol)
MW, MH = 2048, 1024
MPX = MW / W            # px par mètre
MZ0 = TOP               # le haut de l'image est au bord du quai


def bezier(p0, p1, p2, n=40):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * np.array(p0) + 2 * (1 - t) * t * np.array(p1) + t * t * np.array(p2)


def dist_to_polyline(xx, zz, pts, ends=False):
    """Distance à une polyligne ; avec ends=True, rend aussi un facteur qui s'éteint au-delà des extrémités."""
    best = np.full(xx.shape, 1e9)
    endf = np.ones(xx.shape)
    n = len(pts) - 1
    for i, (a, b) in enumerate(zip(pts[:-1], pts[1:])):
        ab = b - a
        L2 = float(ab @ ab) + 1e-9
        tr = ((xx - a[0]) * ab[0] + (zz - a[1]) * ab[1]) / L2
        t = np.clip(tr, 0, 1)
        dx = xx - (a[0] + t * ab[0])
        dz = zz - (a[1] + t * ab[1])
        d = np.sqrt(dx * dx + dz * dz)
        closer = d < best
        best = np.where(closer, d, best)
        if ends:
            L = math.sqrt(L2)
            out = np.zeros(xx.shape)
            if i == 0:
                out = np.maximum(out, -tr * L)
            if i == n - 1:
                out = np.maximum(out, (tr - 1) * L)
            endf = np.where(closer, np.exp(-(np.clip(out, 0, None) / 0.15) ** 2), endf)
    return (best, endf) if ends else best


def make_macro(pid, panels):
    print("carte de crasse et d'usure")
    jj, ii = np.meshgrid(np.arange(MW), np.arange(MH))
    xx = (jj + 0.5) / MPX
    zz = MZ0 + (ii + 0.5) / MPX
    # case et tôle de chaque pixel
    cc = np.clip(((xx - GX0) / CELL).astype(int), 0, NX - 1)
    rr = np.clip(((zz - GZ0) / CELL).astype(int), 0, NZ - 1)
    pp = pid[rr, cc]
    p_arr = np.array(panels)
    p_seed = p_arr[:, 5][pp] / 255.0
    p_var = p_arr[:, 6][pp]
    p_kind = p_arr[:, 4][pp]
    # --- crasse : fond irrégulier, accumulations aux murs et aux coins, plus forte sur certaines tôles
    n1 = fbm(MH, MW, 60, 5, 101)
    dirt = 0.16 + n1 * 0.10
    dwall = np.minimum.reduce([xx - WALL, (W - WALL) - xx, (H - WALL) - zz])
    edge_n = norm01(blur_noise(MH, MW, 12, 102)) * 0.6 + 0.4
    dirt += 0.55 * np.exp(-np.clip(dwall, 0, None) / 0.55) * edge_n
    dirt += 0.22 * np.exp(-np.clip(zz - TOP, 0, None) / 0.4) * edge_n
    for cx, cz in ((WALL, TOP), (W - WALL, TOP), (WALL, H - WALL), (W - WALL, H - WALL)):
        d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
        dirt += 0.35 * np.exp(-d / 1.6) * edge_n
    dirt *= 0.75 + 0.5 * p_seed
    dirt = np.where(p_var == 1, dirt * 0.55, dirt)
    # traînées sales autour des grilles et des siphons (l'eau de lavage y converge)
    for (x, z, w, h, k, seed, var) in panels:
        if k in (GRATE_H, GRATE_V, DRAIN, VENT):
            cx, cz = cell_x(x + w * 0.5), cell_z(z + h * 0.5)
            d = np.sqrt(((xx - cx) / (w * CELL * 0.5 + 0.5)) ** 2 + ((zz - cz) / (h * CELL * 0.5 + 0.5)) ** 2)
            dirt += 0.35 * np.exp(-d * d * 1.2) * edge_n
    # --- usure : chemins de circulation (chariots), autour des monte-charges et des trappes
    paths = [
        [(1.0, 12.24), (36.5, 12.24)],
        [(18.75, TOP), (18.75, H - WALL)],
        list(map(tuple, bezier((18.0, 7.0), (22.5, 6.5), (26.5, 7.0)))),
        list(map(tuple, bezier((16.0, 12.0), (12.5, 16.0), (10.0, 17.5)))),
        list(map(tuple, bezier((12.0, 12.0), (7.5, 11.5), (5.9, 8.5)))),
        list(map(tuple, bezier((24.0, 12.6), (29.5, 13.0), (30.1, 15.5)))),
        list(map(tuple, bezier((20.0, 5.0), (24.0, 4.5), (28.0, 5.5)))),
    ]
    widths = [1.35, 1.25, 0.9, 0.9, 0.85, 0.85, 0.7]
    wear = np.zeros((MH, MW))
    tracks = np.zeros((MH, MW))
    wn = norm01(blur_noise(MH, MW, 6, 103))
    tn = blur_noise(MH, MW, 22, 104)
    for pts, wd in zip(paths, widths):
        pts = np.array(pts, dtype=float)
        d, endf = dist_to_polyline(xx, zz, pts, True)
        wear += np.exp(-(d / wd) ** 2) * (0.55 + 0.45 * wn)
        # deux bandes de roues de chaque côté du chemin, pneus sombres par intermittence
        for off in (0.38, 0.62):
            band = np.exp(-((d - off) / 0.07) ** 2) * endf
            tracks += band * np.clip(0.3 + tn * 0.45, 0, 1) * 0.5
    for (c, r) in LIFTS:
        cx, cz = cell_x(c + 2), cell_z(r + 2)
        d = np.maximum(np.abs(xx - cx), np.abs(zz - cz))
        wear += 0.5 * np.exp(-((d - 1.6) / 0.8) ** 2) * (0.5 + 0.5 * wn)
    for (x, z, w, h, k, seed, var) in panels:
        if k in (HATCH, MANHOLE):
            cx, cz = cell_x(x + w * 0.5), cell_z(z + h * 0.5)
            d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
            wear += 0.35 * np.exp(-((d - 0.9) / 0.4) ** 2) * wn
    wear += np.where(p_var == 2, 0.3, 0.0) * (0.4 + 0.6 * wn)
    wear = np.clip(wear * 0.8, 0, 1)
    # traces de dérapage en arc près des virages
    for i in range(14):
        cx, cz = R.uniform(5, 33), R.uniform(TOP + 2, H - 3)
        rad = R.uniform(1.5, 4.0)
        a0 = R.uniform(0, 2 * math.pi)
        arc = np.array([(cx + math.cos(a0 + t) * rad, cz + math.sin(a0 + t) * rad) for t in np.linspace(0, R.uniform(0.4, 1.0), 18)])
        d, endf = dist_to_polyline(xx, zz, arc, True)
        tracks += endf * np.exp(-(d / 0.06) ** 2) * R.uniform(0.25, 0.55) * np.clip(0.4 + tn * 0.5, 0, 1)
    tracks = np.clip(tracks, 0, 1)
    # --- huile : taches avec bord plus sombre, gouttes satellites, quelques coulures
    oil = np.zeros((MH, MW))
    on = blur_noise(MH, MW, 5, 105)
    spots = []
    for (c, r) in LIFTS:
        spots += [(cell_x(c + R.uniform(0, 4)), cell_z(r + R.uniform(-0.5, 4.5)), R.uniform(0.25, 0.6)) for _ in range(3)]
    spots += [(R.uniform(1.5, 36), R.uniform(TOP + 0.5, H - 1.0), R.uniform(0.12, 0.5)) for _ in range(16)]
    spots += [(R.uniform(1.0, 2.2) if R.random() < 0.5 else R.uniform(35.3, 36.5), R.uniform(TOP + 1, H - 1.5), R.uniform(0.2, 0.45)) for _ in range(6)]
    for (cx, cz, rad) in spots:
        d = np.sqrt((xx - cx) ** 2 + ((zz - cz) * R.uniform(0.7, 1.3)) ** 2) / rad + on * 0.25
        body = smoothstep(1.0, 0.75, d)
        rim = np.exp(-((d - 0.92) / 0.06) ** 2) * 0.35
        oil = np.maximum(oil, body * R.uniform(0.45, 0.85) + rim)
        for k in range(int(R.integers(2, 7))):
            a = R.uniform(0, 2 * math.pi)
            dd = rad * R.uniform(1.2, 2.2)
            sr = rad * R.uniform(0.06, 0.16)
            d2 = np.sqrt((xx - cx - math.cos(a) * dd) ** 2 + (zz - cz - math.sin(a) * dd) ** 2) / sr
            oil = np.maximum(oil, smoothstep(1.0, 0.6, d2) * 0.6)
    oil = np.clip(oil, 0, 1)
    # traces de brûlure de tirs, discrètes (dans la crasse)
    for i in range(7):
        cx, cz = R.uniform(4, 34), R.uniform(TOP + 2, H - 2)
        d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2) / R.uniform(0.3, 0.6) + on * 0.2
        dirt += smoothstep(1.0, 0.2, d) * 0.35
    dirt = np.clip(dirt, 0, 1)
    macro = np.stack([dirt, wear, oil, tracks], -1)
    save_rgba(os.path.join(OUT, "deck_macro.png"), macro)


# ================================================================ atlas : trappes et grilles (moitié basse)
IPX = 256  # px par mètre
STEEL = srgb("#3a414f")
STEEL_D = srgb("#262b35")
STEEL_L = srgb("#4b5262")
YELLOW = srgb("#c99a32")
WHITE = srgb("#c6cad0")
BLACKP = srgb("#17191e")


def tread(xx, zz, pitch=0.055):
    """Tôle larmée : losanges en relief, orientés en damier."""
    gx, gz = xx / pitch, zz / pitch
    i, j = np.floor(gx), np.floor(gz)
    fx, fz = gx - i - 0.5, gz - j - 0.5
    o = (np.mod(i + j, 2) == 0)
    u = np.where(o, fx + fz, fx - fz) / math.sqrt(2)
    v = np.where(o, fx - fz, fx + fz) / math.sqrt(2)
    s = 1 - (u / 0.40) ** 2 - (v / 0.11) ** 2
    return np.sqrt(np.clip(s, 0, 1))


def dome(xx, zz, cx, cz, r):
    d2 = ((xx - cx) ** 2 + (zz - cz) ** 2) / (r * r)
    return np.sqrt(np.clip(1 - d2, 0, 1))


def bump(hgt, base, b):
    """Relief ponctuel (vis, rivets) : ne touche que là où la bosse existe."""
    return np.where(b > 0, np.maximum(hgt, base + b), hgt)


def bolt_ring(xx, zz, cx, cz, rad, n, r, a0=0.0):
    out = np.zeros_like(xx)
    for k in range(n):
        a = a0 + 2 * math.pi * k / n
        out = np.maximum(out, dome(xx, zz, cx + math.cos(a) * rad, cz + math.sin(a) * rad, r))
    return out


def text_mask(wpx, hpx, items):
    cv = Canvas(wpx, hpx, 2)
    for (x, y, s, size, font) in items:
        cv.text(x, y, s, size, font=font)
    return cv.array()


def paint_insert(kind, wm, hm, seed):
    """Rend une pièce (wm x hm mètres) : albédo sRGB (h, w, 3) et hauteur (h, w) ; 0,75 = niveau du pont."""
    pw, ph = int(round(wm * IPX)), int(round(hm * IPX))
    jj, ii = np.meshgrid(np.arange(pw), np.arange(ph))
    xx = (jj + 0.5) / IPX
    zz = (ii + 0.5) / IPX
    rg = np.random.default_rng(seed)
    n_f = blur_noise(ph, pw, 2.0, seed) * 0.5 + blur_noise(ph, pw, 14, seed + 1)
    hgt = np.full((ph, pw), 0.75)
    alb = np.ones((ph, pw, 3)) * STEEL
    edge = np.minimum.reduce([xx, zz, wm - xx, hm - zz])

    def grate(x0, z0, x1, z1, along_x, period=0.05, bar=0.03):
        """Grille à barreaux : fond lumineux (hauteur ~0) entre les barreaux arrondis."""
        nonlocal hgt, alb
        inside = (xx > x0) & (xx < x1) & (zz > z0) & (zz < z1)
        t = (zz if along_x else xx)
        ph_ = np.mod(t, period) / period
        prof = np.clip(1 - ((ph_ - 0.5) / (bar / period * 0.5)) ** 2, 0, 1)
        bars = np.sqrt(prof)
        # fond : lueur plus forte au centre de la grille
        cxm, czm = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        rad = np.sqrt(((xx - cxm) / ((x1 - x0) * 0.5)) ** 2 + ((zz - czm) / ((z1 - z0) * 0.5)) ** 2)
        floor_h = np.clip(rad * 0.07, 0, 0.09)
        hb = np.where(bars > 0.02, 0.6 + bars * 0.25, floor_h)
        hgt = np.where(inside, hb, hgt)
        col_bar = STEEL_D[None, None, :] * (0.85 + 0.35 * bars[..., None]) + 0.03 * n_f[..., None]
        col_floor = np.array([0.05, 0.055, 0.08])[None, None, :]
        c = np.where((bars > 0.02)[..., None], col_bar, col_floor)
        alb = np.where(inside[..., None], c, alb)
        # traverses
        return inside

    if kind in (GRATE_H, GRATE_V, VENT):
        along_x = (kind == GRATE_V) if kind != VENT else False
        fr = 0.06
        # cadre surélevé avec quatre vis
        hgt = np.where(edge < fr, 0.8, hgt)
        alb = np.where((edge < fr)[..., None], STEEL_D * 1.15, alb)
        if kind == VENT:
            # trois sections, lamelles dans le sens long
            secs = 3
            for s in range(secs):
                x0 = fr + s * (wm - 2 * fr) / secs + (0.02 if s > 0 else 0)
                x1 = fr + (s + 1) * (wm - 2 * fr) / secs - (0.02 if s < secs - 1 else 0)
                grate(x0, fr, x1, hm - fr, True, 0.045, 0.027)
        else:
            if kind == GRATE_H:
                grate(fr, fr, wm * 0.5 - 0.015, hm - fr, False)
                grate(wm * 0.5 + 0.015, fr, wm - fr, hm - fr, False)
            else:
                grate(fr, fr, wm - fr, hm * 0.5 - 0.015, True)
                grate(fr, hm * 0.5 + 0.015, wm - fr, hm - fr, True)
        for cx in (fr * 0.5, wm - fr * 0.5):
            for cz in (fr * 0.5, hm - fr * 0.5):
                b = dome(xx, zz, cx, cz, 0.017)
                hgt = bump(hgt, 0.8, b * 0.15)
    elif kind == DRAIN:
        cx, cz = wm * 0.5, hm * 0.5
        d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
        ring = (d > 0.28) & (d < 0.33)
        hgt = np.where(ring, 0.82, hgt)
        alb = np.where(ring[..., None], STEEL_D * 1.2, alb)
        inside = d <= 0.28
        a = np.arctan2(zz - cz, xx - cx)
        rad_slot = np.abs(np.mod(a * 16 / (2 * math.pi), 1.0) - 0.5) < 0.27
        conc = np.abs(np.mod(d / 0.07, 1.0) - 0.5) < 0.2
        slot = inside & rad_slot & (d > 0.05) & ~conc
        hgt = np.where(inside, np.where(slot, np.clip(d * 0.25, 0, 0.08), 0.6), hgt)
        alb = np.where(inside[..., None], np.where(slot[..., None], np.array([0.05, 0.055, 0.08]), STEEL_D * 1.05), alb)
        hgt = bump(hgt, 0.75, 0.15 * bolt_ring(xx, zz, cx, cz, 0.355, 6, 0.016, 0.3))
    elif kind in (HATCH, MANHOLE, SERVICE):
        lid_col = STEEL_L if kind != SERVICE else STEEL
        if kind == HATCH:
            ins = 0.08
            lid = (edge > ins + 0.012)
            groove = (edge > ins) & ~lid
            tr = tread(xx, zz)
            hgt = np.where(lid, 0.77 + tr * 0.12, hgt)
            hgt = np.where(groove, 0.2, hgt)
            alb = np.where(lid[..., None], lid_col * (0.9 + 0.35 * tr[..., None]), alb)
            alb = np.where(groove[..., None], STEEL_D * 0.4, alb)
            # poignée encastrée et charnières
            hx0, hx1, hz0, hz1 = wm * 0.5 - 0.13, wm * 0.5 + 0.13, hm - ins - 0.16, hm - ins - 0.08
            pocket = (xx > hx0) & (xx < hx1) & (zz > hz0) & (zz < hz1)
            barh = pocket & (np.abs(zz - (hz0 + hz1) * 0.5) < 0.012) & (xx > hx0 + 0.03) & (xx < hx1 - 0.03)
            hgt = np.where(pocket, np.where(barh, 0.7, 0.35), hgt)
            alb = np.where(pocket[..., None], np.where(barh[..., None], STEEL_L * 1.3, STEEL_D * 0.5), alb)
            for hx in (wm * 0.25, wm * 0.75):
                hin = (np.abs(xx - hx) < 0.09) & (zz > ins - 0.03) & (zz < ins + 0.06)
                hgt = np.where(hin, 0.92, hgt)
                alb = np.where(hin[..., None], STEEL_D * 1.3, alb)
            for cx in (0.04, wm - 0.04):
                for cz in (0.04, hm - 0.04):
                    hgt = bump(hgt, 0.75, dome(xx, zz, cx, cz, 0.018) * 0.17)
            tm = text_mask(pw, ph, [(pw * 0.5, ph * 0.42, "7-B", 0.30 * IPX, FONT_RUSSO), (pw * 0.5, ph * 0.62, "ACCÈS", 0.12 * IPX, FONT_RUSSO)])
            tm *= smoothstep(0.25, 0.55, norm01(n_f))
            alb = alb * (1 - tm[..., None] * 0.85) + YELLOW * tm[..., None] * 0.85
        elif kind == MANHOLE:
            cx, cz = wm * 0.5, hm * 0.5
            d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
            lid = d < 0.6
            groove = (d >= 0.6) & (d < 0.615)
            tr = tread(xx - cx, zz - cz, 0.06)
            inner = d < 0.47
            hgt = np.where(lid, np.where(inner, 0.78 + tr * 0.1, 0.8), hgt)
            hgt = np.where(groove, 0.2, hgt)
            alb = np.where(lid[..., None], lid_col * np.where(inner[..., None], 0.9 + 0.3 * tr[..., None], 1.05), alb)
            alb = np.where(groove[..., None], STEEL_D * 0.4, alb)
            hgt = bump(hgt, 0.8, 0.14 * bolt_ring(xx, zz, cx, cz, 0.535, 12, 0.019))
            # deux encoches de levage
            for sx in (-1, 1):
                sl = (np.abs(xx - (cx + sx * 0.38)) < 0.045) & (np.abs(zz - cz) < 0.014)
                hgt = np.where(sl, 0.3, hgt)
                alb = np.where(sl[..., None], STEEL_D * 0.4, alb)
            # « N7 » en relief au centre
            ring_c = (d > 0.17) & (d < 0.2)
            tm = text_mask(pw, ph, [(pw * 0.5, ph * 0.5, "N7", 0.2 * IPX, FONT_RUSSO)])
            plate = d < 0.17
            hgt = np.where(plate, 0.8 + tm * 0.12, hgt)
            hgt = np.where(ring_c, 0.92, hgt)
            alb = np.where((plate | ring_c)[..., None], lid_col * (1.0 + 0.4 * tm[..., None]), alb)
            for c2x in (0.05, wm - 0.05):
                for c2z in (0.05, hm - 0.05):
                    hgt = bump(hgt, 0.75, dome(xx, zz, c2x, c2z, 0.018) * 0.17)
        else:  # SERVICE : coffret à capots ronds
            ins = 0.07
            cover = (edge > ins + 0.01)
            groove = (edge > ins) & ~cover
            hgt = np.where(groove, 0.25, hgt)
            alb = np.where(groove[..., None], STEEL_D * 0.4, alb)
            hgt = np.where(cover, 0.78, hgt)
            for k in range(3):
                cx = wm * (0.22 + 0.22 * k)
                cz = hm * 0.48
                d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
                cap = d < 0.085
                hgt = np.where(cap, 0.86 + 0.06 * np.sqrt(np.clip(1 - (d / 0.085) ** 2, 0, 1)), hgt)
                hgt = np.where(d < 0.03, 0.5, hgt)
                alb = np.where(cap[..., None], STEEL_D * 1.25, alb)
                alb = np.where((d < 0.03)[..., None], STEEL_D * 0.4, alb)
            lab = (xx > wm * 0.78) & (xx < wm * 0.93) & (zz > hm * 0.25) & (zz < hm * 0.75)
            stripes = np.mod((xx + zz) / 0.035, 1.0) < 0.5
            alb = np.where(lab[..., None], np.where(stripes[..., None], YELLOW * 0.9, BLACKP), alb)
            tm = text_mask(pw, ph, [(pw * 0.44, ph * 0.84, "380 V  -  PRISE QUAI", 0.07 * IPX, FONT_RAJ)])
            alb = alb * (1 - tm[..., None] * 0.7) + WHITE * tm[..., None] * 0.7
            for cx in (0.035, wm - 0.035):
                for cz in (0.035, hm - 0.035):
                    hgt = bump(hgt, 0.75, dome(xx, zz, cx, cz, 0.016) * 0.16)
    elif kind == LIFT:
        band = 0.17
        stripes = np.mod((xx + zz) / 0.16, 1.0) < 0.5
        b = edge < band
        hz = np.where(stripes[..., None], YELLOW, BLACKP)
        wearb = smoothstep(0.35, 0.65, norm01(n_f + blur_noise(ph, pw, 30, seed + 5)))
        hz = hz * (1 - wearb[..., None] * 0.6) + STEEL[None, None, :] * wearb[..., None] * 0.6
        alb = np.where(b[..., None], hz, alb)
        gap = (edge >= band) & (edge < band + 0.022)
        hgt = np.where(gap, 0.05, hgt)
        alb = np.where(gap[..., None], np.array([0.03, 0.032, 0.04]), alb)
        plat = edge >= band + 0.022
        tr = tread(xx, zz, 0.07)
        seam = np.abs(xx - wm * 0.5) < 0.008
        hgt = np.where(plat, np.where(seam, 0.3, 0.77 + tr * 0.1), hgt)
        alb = np.where(plat[..., None], STEEL_L * (0.88 + 0.32 * tr[..., None]), alb)
        alb = np.where((plat & seam)[..., None], STEEL_D * 0.4, alb)
        for cx in (band + 0.2, wm - band - 0.2):
            for cz in (band + 0.2, hm - band - 0.2):
                d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
                sock = d < 0.07
                hgt = np.where(sock, np.where(d < 0.03, 0.95, 0.4), hgt)
                alb = np.where(sock[..., None], np.where((d < 0.03)[..., None], STEEL_L * 1.4, STEEL_D * 0.5), alb)
        tm = text_mask(pw, ph, [(pw * 0.5, ph * 0.3, "MONTE-CHARGE", 0.17 * IPX, FONT_RUSSO),
                                (pw * 0.5, ph * 0.72, "40 T", 0.36 * IPX, FONT_RUSSO)])
        tm *= smoothstep(0.2, 0.6, norm01(n_f + blur_noise(ph, pw, 20, seed + 9)))
        alb = alb * (1 - tm[..., None] * 0.6) + WHITE * tm[..., None] * 0.6
    # usure : arêtes hautes plus claires (métal nu), crasse dans les creux
    hi = smoothstep(0.85, 1.0, hgt)
    alb = alb * (1 + hi[..., None] * 0.35)
    lo = smoothstep(0.5, 0.2, hgt) * (hgt > 0.12)
    alb = alb * (1 - lo[..., None] * 0.3)
    alb = alb * (0.93 + 0.07 * np.clip(n_f, -2, 2)[..., None] * 0.5)
    return np.clip(alb, 0, 1), np.clip(hgt, 0, 1)


# ================================================================ atlas : marquages peints (moitié haute)
MPXM = 192  # px par mètre


def mk(wm, hm):
    return Canvas(int(round(wm * MPXM)), int(round(hm * MPXM)), 2)


def worn(mask, seed, amount=0.28, scuff=0.35):
    """Peinture usée : écaillage, éraflures dans le sens de circulation, bords doux."""
    h, w = mask.shape
    e = norm01(blur_noise(h, w, 2.5, seed) * 0.6 + blur_noise(h, w, 10, seed + 1) * 0.8 + blur_noise(h, w, 40, seed + 2) * 0.6)
    s = norm01(aniso_noise(h, w, 60, 2.0, seed + 3))
    keep = smoothstep(amount - 0.12, amount + 0.12, e) * (1 - smoothstep(1 - scuff * 0.5, 1.0, s) * 0.8)
    return mask * keep


def mark_rgba(layers, seed, amount=0.28):
    """layers : liste de (masque, couleur). Rend RGBA ; la couleur déborde sous l'alpha nul (pas de liseré)."""
    h, w = layers[0][0].shape
    a = np.zeros((h, w))
    col = np.zeros((h, w, 3))
    for m, c in layers:
        col = col * (1 - m[..., None]) + c[None, None, :] * m[..., None]
        a = np.maximum(a, m)
    base = layers[0][1]
    col = np.where(a[..., None] > 0.01, col / np.maximum(a[..., None], 1e-3) * np.clip(a[..., None], 0, 1) + base * (1 - np.clip(a[..., None], 0, 1)), base)
    a = worn(a, seed, amount)
    nv = blur_noise(h, w, 8, seed + 7)
    col = col * (0.9 + 0.06 * nv[..., None])
    return np.concatenate([np.clip(col, 0, 1), a[..., None]], -1)


def draw_arrow(cv, wpx, hpx):
    s = cv
    shaft = hpx * 0.3
    s.rect(wpx * 0.04, hpx * 0.5 - shaft * 0.5, wpx * 0.62, hpx * 0.5 + shaft * 0.5)
    s.poly([(wpx * 0.58, hpx * 0.08), (wpx * 0.97, hpx * 0.5), (wpx * 0.58, hpx * 0.92)])


def make_marks():
    """Chaque marquage : nom -> image RGBA et taille en mètres. Les bandes se répètent le long de u."""
    out = {}
    Y, Wt, Bk = YELLOW * 1.05, WHITE, BLACKP
    # bande de danger jaune et noire, raccordable en u (1 m)
    cv = mk(1.0, 0.3)
    w, h = cv.w, cv.h
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    st = (np.mod((jj + ii) / (MPXM * 0.25), 1.0) < 0.5).astype(np.float32)
    full = np.ones((h, w), np.float32)
    out["stripe"] = (mark_rgba([(full, Bk), (st, Y)], 501, 0.22), (1.0, 0.3))
    # hachures fines (remplissage de zone), raccordables en u et v (1 m)
    cv = mk(1.0, 1.0)
    w, h = cv.w, cv.h
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    ph = np.mod((jj + ii) / (MPXM * 0.25), 1.0)
    hat = smoothstep(0.0, 0.03, ph) * smoothstep(0.3, 0.27, ph)
    out["hatch"] = (mark_rgba([(hat.astype(np.float32), Y)], 502, 0.3), (1.0, 1.0))
    # trait plein et tirets (1 m, raccordables en u)
    cv = mk(1.0, 0.1)
    cv.rect(0, 0, cv.w, cv.h)
    out["line"] = (mark_rgba([(cv.array(), Wt)], 503, 0.25), (1.0, 0.1))
    cv = mk(1.0, 0.1)
    cv.rect(0, 0, cv.w * 0.6, cv.h)
    out["dash"] = (mark_rgba([(cv.array(), Wt)], 504, 0.25), (1.0, 0.1))
    cv = mk(1.0, 0.1)
    cv.rect(0, 0, cv.w, cv.h)
    out["line_y"] = (mark_rgba([(cv.array(), Y)], 505, 0.25), (1.0, 0.1))
    # flèche de circulation
    cv = mk(1.6, 0.7)
    draw_arrow(cv, cv.w, cv.h)
    out["arrow"] = (mark_rgba([(cv.array(), Wt)], 506, 0.3), (1.6, 0.7))
    # chevrons
    cv = mk(1.2, 0.5)
    for k in range(3):
        x0 = cv.w * (0.06 + 0.3 * k)
        cv.poly([(x0, 0), (x0 + cv.w * 0.16, 0), (x0 + cv.w * 0.34, cv.h * 0.5), (x0 + cv.w * 0.16, cv.h), (x0, cv.h), (x0 + cv.w * 0.18, cv.h * 0.5)])
    out["chevrons"] = (mark_rgba([(cv.array(), Y)], 507, 0.3), (1.2, 0.5))
    # BAIE 07
    cv = mk(3.0, 0.9)
    cv.text(cv.w * 0.5, cv.h * 0.54, "BAIE 07", cv.h * 0.82, spacing=cv.h * 0.05)
    out["baie07"] = (mark_rgba([(cv.array(), Wt)], 508, 0.3), (3.0, 0.9))
    # N7 dans un cercle
    cv = mk(2.0, 2.0)
    cv.ellipse(cv.w * 0.5, cv.h * 0.5, cv.w * 0.47, cv.h * 0.47, width=cv.w * 0.05)
    cv.text(cv.w * 0.5, cv.h * 0.53, "N7", cv.h * 0.5)
    out["n7"] = (mark_rgba([(cv.array(), Wt)], 509, 0.32), (2.0, 2.0))
    # logo de la compagnie de fret : HÉLIX FRET (HXF), hexagone et hélice stylisée
    cv = mk(2.8, 2.8)
    w, h = cv.w, cv.h
    cx, cy, rr = w * 0.5, h * 0.4, w * 0.3
    hexa = [(cx + rr * math.cos(math.pi / 6 + k * math.pi / 3), cy + rr * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    cv.line(hexa + [hexa[0]], w * 0.035)
    cv2 = mk(2.8, 2.8)
    # deux brins d'hélice entrelacés dans l'hexagone
    for ph0 in (0.0, math.pi):
        pts = [(cx + rr * 0.55 * math.sin(t * 2.2 * math.pi + ph0), cy - rr * 0.75 + t * rr * 1.5) for t in np.linspace(0, 1, 40)]
        cv2.line(pts, w * 0.03)
    for k in range(5):
        y = cy - rr * 0.6 + k * rr * 0.3
        t = (y - (cy - rr * 0.75)) / (rr * 1.5)
        xa = rr * 0.55 * math.sin(t * 2.2 * math.pi)
        cv2.line([(cx - abs(xa), y), (cx + abs(xa), y)], w * 0.012)
    cv.text(cx, h * 0.8, "HÉLIX FRET", h * 0.12, spacing=h * 0.01)
    cv.text(cx, h * 0.92, "TRANSIT  NÉBULEUSE 7", h * 0.05, font=FONT_RAJ, spacing=h * 0.008)
    out["logo"] = (mark_rgba([(cv.array(), Wt), (cv2.array(), srgb("#d98a3a"))], 510, 0.3), (2.8, 2.8))
    # cadre de sas d'apparition : équerres aux coins, « SAS »
    cv = mk(2.6, 2.6)
    w, h = cv.w, cv.h
    t, L = w * 0.04, w * 0.24
    for (x0, y0, sx, sy) in ((0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)):
        cv.rect(min(x0, x0 + sx * L), min(y0, y0 + sy * t), max(x0, x0 + sx * L), max(y0, y0 + sy * t))
        cv.rect(min(x0, x0 + sx * t), min(y0, y0 + sy * L), max(x0, x0 + sx * t), max(y0, y0 + sy * L))
    out["sas"] = (mark_rgba([(cv.array(), Y)], 511, 0.3), (2.6, 2.6))
    for i in range(8):
        cv = mk(0.7, 0.24)
        cv.text(cv.w * 0.5, cv.h * 0.55, "SAS %d" % (i + 1), cv.h * 0.8, spacing=cv.h * 0.06)
        out["sas%d" % (i + 1)] = (mark_rgba([(cv.array(), Y)], 520 + i, 0.3), (0.7, 0.24))
    # pochoirs de sécurité
    stencils = {"st_stat": "NE PAS STATIONNER", "st_charge": "ZONE DE CHARGEMENT", "st_max": "CHARGE MAX 40 T",
                "st_man": "ATTENTION MANŒUVRES", "st_voie": "VOIE DE CIRCULATION", "st_quai": "ACCÈS QUAI 07",
                "st_tri": "TRI  -  HÉLIX FRET"}
    for i, (k, s) in enumerate(stencils.items()):
        cv = mk(2.4, 0.3)
        cv.text(cv.w * 0.5, cv.h * 0.55, s, cv.h * 0.78, spacing=cv.h * 0.1)
        out[k] = (mark_rgba([(cv.array(), Y if k in ("st_charge", "st_max", "st_man") else Wt)], 530 + i, 0.33), (2.4, 0.3))
    for i, s in enumerate(("07-A", "07-B", "07-C", "07-D")):
        cv = mk(1.0, 0.42)
        cv.text(cv.w * 0.5, cv.h * 0.55, s, cv.h * 0.85, spacing=cv.h * 0.06)
        out["num" + s[-1]] = (mark_rgba([(cv.array(), Wt)], 540 + i, 0.3), (1.0, 0.42))
    # ligne d'arrêt
    cv = mk(0.3, 1.5)
    cv.rect(0, 0, cv.w, cv.h)
    out["stop"] = (mark_rgba([(cv.array(), Wt)], 550, 0.35), (0.3, 1.5))
    # triangle de danger
    cv = mk(0.6, 0.54)
    w, h = cv.w, cv.h
    cv.poly([(w * 0.5, 0), (w, h), (0, h)])
    cv2 = mk(0.6, 0.54)
    cv2.poly([(w * 0.5, h * 0.2), (w * 0.86, h * 0.9), (w * 0.14, h * 0.9)])
    cv3 = mk(0.6, 0.54)
    cv3.rect(w * 0.46, h * 0.38, w * 0.54, h * 0.7)
    cv3.rect(w * 0.46, h * 0.75, w * 0.54, h * 0.83)
    tri = np.clip(cv.array() - cv2.array() + cv3.array(), 0, 1)
    out["warn"] = (mark_rgba([(cv.array(), Y), (tri, Bk)], 551, 0.25), (0.6, 0.54))
    return out


def pack(items, x0, y0, x1, y1, pad=6):
    """Rangement en étagères : items = {nom: (largeur, hauteur)} -> {nom: (x, y)}."""
    order = sorted(items.items(), key=lambda kv: -kv[1][1])
    pos = {}
    x, y, shelf = x0 + pad, y0 + pad, 0
    for name, (w, h) in order:
        if x + w + pad > x1:
            x = x0 + pad
            y += shelf + pad
            shelf = 0
        if y + h + pad > y1:
            raise RuntimeError("atlas plein : " + name)
        pos[name] = (x, y)
        x += w + pad
        shelf = max(shelf, h)
    return pos


def make_atlas(panels):
    print("atlas du sol")
    A = 2048
    atlas = np.zeros((A, A, 4), np.float32)
    marks = make_marks()
    pos = pack({k: (v[0].shape[1], v[0].shape[0]) for k, v in marks.items()}, 0, 0, A, A // 2, 8)
    mark_rects = {}
    for k, (img, size) in marks.items():
        x, y = pos[k]
        hh, ww = img.shape[:2]
        atlas[y:y + hh, x:x + ww] = img
        mark_rects[k] = {"uv": [x / A, y / A, ww / A, hh / A], "size": list(size)}
    # pièces du sol
    ins = {}
    for k, (cw, ch) in KIND_CELLS.items():
        wm, hm = cw * CELL, ch * CELL
        alb, hgt = paint_insert(k, wm, hm, 600 + k)
        ins[k] = np.concatenate([alb, hgt[..., None]], -1)
    ipos = pack({k: (v.shape[1], v.shape[0]) for k, v in ins.items()}, 0, A // 2, A, A, 10)
    ins_rects = [[0, 0, 0, 0] for _ in range(9)]
    for k, img in ins.items():
        x, y = ipos[k]
        hh, ww = img.shape[:2]
        atlas[y:y + hh, x:x + ww] = img
        # bordure dupliquée (évite les fuites de couleur au filtrage)
        atlas[y - 4:y, x:x + ww] = img[:1]
        atlas[y + hh:y + hh + 4, x:x + ww] = img[-1:]
        atlas[y - 4:y + hh + 4, x - 4:x] = atlas[y - 4:y + hh + 4, x:x + 1]
        atlas[y - 4:y + hh + 4, x + ww:x + ww + 4] = atlas[y - 4:y + hh + 4, x + ww - 1:x + ww]
        ins_rects[k] = [x / A, y / A, ww / A, hh / A]
    # sous les marquages, la couleur transparente reste celle de la peinture (mip propres)
    save_rgba(os.path.join(OUT, "deck_atlas.png"), atlas)
    return mark_rects, ins_rects


# ================================================================ marquages posés au sol
def decals(panels):
    """Chaque marquage : [nom, x, z, longueur (u), largeur (v), angle (deg, u le long de +x à 0), répétitions u, v,
    opacité, usure en plus]."""
    out = []

    def add(name, x, z, su, sv, ang=0.0, ru=1, rv=1, op=1.0, wear=0.0):
        out.append([name, round(x, 3), round(z, 3), round(su, 3), round(sv, 3), ang, ru, rv, op, wear])

    a0, a1 = AISLE_ROWS
    b0, b1 = AISLE_COLS
    za, zb = cell_z(a0), cell_z(a1)
    xa, xb = cell_x(b0), cell_x(b1)
    zc = (za + zb) * 0.5
    xc = (xa + xb) * 0.5
    # bords et axe de l'allée est-ouest, coupés au croisement
    for (x0, x1) in ((cell_x(1) + 0.2, xa - 0.25), (xb + 0.25, cell_x(NX - 1) - 0.2)):
        L = x1 - x0
        for z in (za + 0.12, zb - 0.12):
            add("line", (x0 + x1) * 0.5, z, L, 0.1, 0, round(L), 1, 0.8)
        add("dash", (x0 + x1) * 0.5, zc, L, 0.1, 0, round(L / 1.5), 1, 0.7)
    # bords et axe de l'allée nord-sud
    for (z0, z1) in ((cell_z(1) + 0.3, za - 0.25), (zb + 0.25, cell_z(NZ - 1) - 0.2)):
        L = z1 - z0
        for x in (xa + 0.12, xb - 0.12):
            add("line", x, (z0 + z1) * 0.5, L, 0.1, 90, round(L), 1, 0.8)
        add("dash", xc, (z0 + z1) * 0.5, L, 0.1, 90, round(L / 1.5), 1, 0.7)
    # lignes d'arrêt avant le croisement
    for x in (xa - 0.55, xb + 0.55):
        add("stop", x, zc + (0.76 if x < xc else -0.76), 0.3, 1.4, 0, 1, 1, 0.75)
    for z in (za - 0.55, zb + 0.55):
        add("stop", xc + (-0.76 if z < zc else 0.76), z, 0.3, 1.4, 90, 1, 1, 0.75)
    # flèches : voie nord vers l'ouest, voie sud vers l'est ; allée nord-sud : descente à l'ouest, montée à l'est
    for x in (6.5, 13.0, 25.0, 31.5):
        add("arrow", x, zc - 0.76, 1.4, 0.6, 180, 1, 1, 0.75)
        add("arrow", x + 1.5, zc + 0.76, 1.4, 0.6, 0, 1, 1, 0.75)
    for z in (7.0, 17.6):
        add("arrow", xc - 0.76, z, 1.4, 0.6, -90, 1, 1, 0.75)
        add("arrow", xc + 0.76, z + 1.2, 1.4, 0.6, 90, 1, 1, 0.75)
    # logo au croisement, numéros de baie sur l'allée nord-sud
    add("logo", xc, zc, 2.7, 2.7, 0, 1, 1, 0.9, -0.4)
    add("baie07", xc, 15.6, 2.6, 0.78, 0, 1, 1, 0.85)
    add("baie07", xc, 9.2, 2.6, 0.78, 0, 1, 1, 0.85)
    add("st_quai", xc, 6.35, 2.2, 0.27, 0, 1, 1, 0.8)
    add("st_voie", 9.8, zb + 0.5, 2.2, 0.27, 0, 1, 1, 0.7)
    add("st_voie", 27.8, za - 0.5, 2.2, 0.27, 0, 1, 1, 0.7)
    # grands N7 dans les champs
    add("n7", 13.6, 7.2, 1.9, 1.9, 0, 1, 1, 0.7)
    add("n7", 24.6, 17.3, 1.9, 1.9, 0, 1, 1, 0.7)
    # zones de chargement : hachures, bandes de danger, pochoirs
    for i, (c, r, w, h) in enumerate(ZONES):
        x0, z0, x1, z1 = cell_x(c), cell_z(r), cell_x(c + w), cell_z(r + h)
        cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        sx, sz = x1 - x0, z1 - z0
        add("hatch", cx, cz, sx - 0.5, sz - 0.5, 0, round(sx - 0.5), round(sz - 0.5), 0.45)
        add("stripe", cx, z0 + 0.15, sx, 0.3, 0, round(sx), 1, 0.85)
        add("stripe", cx, z1 - 0.15, sx, 0.3, 180, round(sx), 1, 0.85)
        add("stripe", x0 + 0.15, cz, sz - 0.6, 0.3, 90, round(sz - 0.6), 1, 0.85)
        add("stripe", x1 - 0.15, cz, sz - 0.6, 0.3, -90, round(sz - 0.6), 1, 0.85)
        add("st_charge", cx, z1 + 0.38, 2.4, 0.3, 0, 1, 1, 0.8)
        add("numB" if i == 0 else "numC", x0 + 0.95, z0 + 0.62, 1.0, 0.42, 0, 1, 1, 0.85)
        add("st_stat", cx, z0 - 0.35, 2.2, 0.27, 0, 1, 1, 0.65)
    # monte-charges : pochoirs, chevrons d'approche
    for i, (c, r) in enumerate(LIFTS):
        x0, z0 = cell_x(c), cell_z(r)
        cx = x0 + 2 * CELL
        add("st_max", cx, z0 + 4 * CELL + 0.32, 2.2, 0.27, 0, 1, 1, 0.75)
        add("numA" if i == 0 else "numD", cx, z0 - 0.3, 1.0, 0.42, 0, 1, 1, 0.8)
        add("chevrons", x0 + 4 * CELL + 0.8 if i == 0 else x0 - 0.8, z0 + 2 * CELL, 1.1, 0.46, 180 if i == 0 else 0, 1, 1, 0.7)
    # sas d'apparition (positions de arena.gd)
    pads = [(130, TOP * 64 + 90), (2400 - 130, TOP * 64 + 90), (130, 1400 - 130), (2400 - 130, 1400 - 130),
            (1200, TOP * 64 + 80), (1200, 1400 - 110), (110, (TOP * 64 + 1400) * 0.5), (2400 - 110, (TOP * 64 + 1400) * 0.5)]
    for i, (px, pz) in enumerate(pads):
        x, z = px / 64.0, pz / 64.0
        add("sas", x, z, 2.5, 2.5, 0, 1, 1, 0.7)
        tz = z + 1.45 if z < 15 else z - 1.45
        tx = min(max(x, 1.4), W - 1.4)
        add("sas%d" % (i + 1), tx, tz, 0.62, 0.21, 0, 1, 1, 0.75)
    # lignes de sécurité le long des caniveaux
    L = cell_z(NZ - 1) - cell_z(0)
    for x in (cell_x(1) + 0.06, cell_x(NX - 1) - 0.06):
        add("line_y", x, (cell_z(0) + cell_z(NZ - 1)) * 0.5, L, 0.08, 90, round(L), 1, 0.6)
    # triangles de danger près des grilles de caniveau
    for (x, z, w, h, k, seed, var) in panels:
        if k == GRATE_V and R.random() < 0.5:
            cx = cell_x(x + 0.5)
            add("warn", cx + (0.9 if x == 0 else -0.9), cell_z(z + 1), 0.5, 0.45, 0, 1, 1, 0.6)
    add("st_man", xa - 1.6, za - 0.45, 2.2, 0.27, 0, 1, 1, 0.65)
    add("st_tri", 31.0, zb + 0.55, 2.2, 0.27, 0, 1, 1, 0.65)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    pid, panels = build_layout()
    print("tôles :", len(panels), " pièces :", {KIND_NAMES[k]: sum(1 for p in panels if p[4] == k) for k in range(1, 9)})
    cells = layout_cells(pid, panels)
    make_detail()
    make_macro(pid, panels)
    mark_rects, ins_rects = make_atlas(panels)
    data = {
        "grid": [GX0, GZ0, CELL, NX, NZ],
        "macro": [0.0, TOP, W, MH / MPX],
        "cells": cells,
        "ins_rects": ins_rects,
        "ins_cells": [list(KIND_CELLS.get(k, (1, 1))) for k in range(9)],
        "marks": mark_rects,
        "decals": decals(panels),
    }
    write_json(os.path.join(OUT, "deck_layout.json"), data)


if __name__ == "__main__":
    main()
