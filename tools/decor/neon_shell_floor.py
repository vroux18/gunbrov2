#!/usr/bin/env python3
"""Cité Néon — sol du toit-terrasse : plan des dalles, textures, marquages.

Écrit dans assets/decor/neon/shell/ :
  roof_layout.json  plan (31 x 15 dalles de béton de 1,19 m, zones d'étanchéité bitume), cadres d'atlas, marquages
  roof_detail.png   1024² tuile de 2 m : R variation d'albédo, G fissures, B relief (granulats), A rugosité
  roof_macro.png    2048x1024, tout le toit sans répétition : R eau (flaques), G crasse, B traînées de pluie,
                    A taches d'huile
  roof_atlas.png    2048² : moitié haute = marquages peints (RGBA), moitié basse = pièces du sol
                    (RGB albédo, A hauteur ; hauteur < 0,1 = fond lumineux)
Lancement : python3 tools/decor/neon_shell_floor.py
"""
import math
import os

import numpy as np
from PIL import Image

from neon_shell_common import (CX, CZ, FONT_RAJ, FONT_RUSSO, H, MH, MW, MX0, MXW, MZ0, MZH, NX, NZ, OUT, TOP, W,
                               X0, X1, Z0, Z1, ZN, Atlas, Canvas, aniso_noise, blur, blur_noise, draw_glyphs, fbm,
                               glyph_text, norm01, save_rgba, smoothstep, srgb, write_json)

R = np.random.default_rng(2047)

SLAB, MEMB, DRAIN, HATCH, SKY, GRATE, PLATE, CHAN_V, CHAN_H = range(9)
KIND_CELLS = {DRAIN: (1, 1), HATCH: (2, 2), SKY: (2, 1), GRATE: (1, 2), PLATE: (1, 1), CHAN_V: (1, 2), CHAN_H: (2, 1)}
# zones d'étanchéité en bitume (col, rangée, largeur, hauteur), en plus de la bande périphérique
MEMB_ZONES = [(3, 9, 6, 4), (22, 1, 6, 3), (12, 1, 3, 2)]
HELI = (W * 0.5, (Z0 + Z1) * 0.5, 4.1)    # aire d'atterrissage des taxis : centre x, z, rayon


def cx_(c):
    return X0 + c * CX


def cz_(r):
    return Z0 + r * CZ


# ================================================================ plan des dalles
def build_layout():
    pid = -np.ones((NZ, NX), int)
    panels = []

    def free(x, z, w, h):
        return x >= 0 and z >= 0 and x + w <= NX and z + h <= NZ and (pid[z:z + h, x:x + w] < 0).all()

    def put(x, z, w, h, k=SLAB, zone=0):
        pid[z:z + h, x:x + w] = len(panels)
        panels.append([x, z, w, h, k, zone])

    memb = np.zeros((NZ, NX), bool)
    memb[0, :] = memb[-1, :] = True
    memb[:, 0] = memb[:, -1] = True
    for (c, r, w, h) in MEMB_ZONES:
        memb[r:r + h, c:c + w] = True
    # caniveaux à fente le long des parapets ouest / est, siphons aux coins et au milieu des bords
    for c in (0, NX - 1):
        for r in (1, 5, 9):
            put(c, r, 1, 2, CHAN_V, 1)
        for r in (3, 12):
            put(c, r, 1, 1, DRAIN, 1)
    for r in (0, NZ - 1):
        for c in (6, 19):
            put(c, r, 2, 1, CHAN_H, 1)
        for c in (11, 25):
            put(c, r, 1, 1, DRAIN, 1)
    for (c, r) in ((0, 0), (NX - 1, 0), (0, NZ - 1), (NX - 1, NZ - 1)):
        put(c, r, 1, 1, DRAIN, 1)
    # pièces dans le champ (jamais sous l'aire d'atterrissage)
    hx, hz, hr = HELI

    def near_heli(c, r, w, h):
        x0, z0, x1, z1 = cx_(c), cz_(r), cx_(c + w), cz_(r + h)
        qx, qz = min(max(hx, x0), x1), min(max(hz, z0), z1)
        return math.hypot(qx - hx, qz - hz) < hr + 0.6

    fixed = [(HATCH, 9, 4), (HATCH, 25, 10), (SKY, 4, 5), (SKY, 26, 6), (SKY, 18, 12), (GRATE, 12, 9),
             (GRATE, 27, 2), (GRATE, 6, 11), (PLATE, 21, 4), (PLATE, 8, 2), (PLATE, 14, 6), (DRAIN, 10, 10),
             (DRAIN, 21, 11), (DRAIN, 24, 5), (DRAIN, 7, 7), (DRAIN, 15, 3), (SKY, 12, 13), (SKY, 28, 9),
             (GRATE, 2, 4), (PLATE, 23, 13), (DRAIN, 3, 12), (DRAIN, 28, 12)]
    for k, c, r in fixed:
        w, h = KIND_CELLS[k]
        if free(c, r, w, h) and not near_heli(c, r, w, h):
            put(c, r, w, h, k, 1 if memb[r, c] else 0)
    # remplissage : une dalle par case (béton) ; bitume par zones
    for r in range(NZ):
        for c in range(NX):
            if pid[r, c] >= 0:
                continue
            if memb[r, c]:
                put(c, r, 1, 1, MEMB, 1)
                continue
            # dalles de tailles mêlées : 1 x 1, 2 x 1, 1 x 2, 2 x 2
            u = R.random()
            w, h = (1, 1) if u < 0.5 else ((2, 1) if u < 0.7 else ((1, 2) if u < 0.85 else (2, 2)))
            while (w > 1 or h > 1) and not (free(c, r, w, h) and not memb[r:r + h, c:c + w].any()):
                w, h = (1, h) if w > 1 else (w, 1)
            put(c, r, w, h, SLAB, 0)
    # données par pièce : graine, variante (0 d'origine, 1 refaite, 2 fissurée, 3 écornée)
    for p in panels:
        p.append(int(R.integers(0, 256)))
        u = R.random()
        p.append(1 if u < 0.1 else (2 if u < 0.24 else (3 if u < 0.34 else 0)))
    return pid, panels, memb


def layout_cells(pid, panels):
    cells = []
    for r in range(NZ):
        row = []
        for c in range(NX):
            x, z, w, h, k, zone, seed, var = panels[pid[r, c]]
            if k == MEMB:
                # bitume : bord seulement contre le béton
                fl = 0
                for bit, (dc, dr) in ((1, (-1, 0)), (2, (0, -1)), (4, (1, 0)), (8, (0, 1))):
                    cc, rr = c + dc, r + dr
                    if 0 <= cc < NX and 0 <= rr < NZ and panels[pid[rr, cc]][4] == SLAB:
                        fl |= bit
            else:
                fl = (1 if c == x else 0) | (2 if r == z else 0) | (4 if c == x + w - 1 else 0) | (8 if r == z + h - 1 else 0)
            row.append([seed, fl | (k << 4), (c - x) | ((r - z) << 4), var | (zone << 4)])
        cells.append(row)
    return cells


# ================================================================ tuile de détail (béton)
def make_detail():
    N = 1024  # 2 m -> 512 px/m
    print("tuile de détail")
    mott = blur_noise(N, N, 70, 11) * 0.5 + blur_noise(N, N, 18, 12) * 0.35 + blur_noise(N, N, 2.0, 13) * 0.3
    # granulats : petites taches claires et sombres
    agg = blur_noise(N, N, 1.6, 14)
    agg_l = smoothstep(1.6, 2.4, agg)
    agg_d = smoothstep(1.8, 2.6, -agg)
    pores = smoothstep(2.6, 3.2, blur_noise(N, N, 1.1, 15))
    albvar = np.clip(0.5 + mott * 0.13 + agg_l * 0.22 - agg_d * 0.18 - pores * 0.35, 0, 1)
    # fissures : lignes brisées ramifiées (raccordables)
    cv = Canvas(N, N, 2)
    for i in range(14):
        x, y = R.uniform(0, N), R.uniform(0, N)
        a = R.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for k in range(int(R.integers(8, 22))):
            a += R.normal(0, 0.45)
            st = R.uniform(8, 26)
            x, y = x + math.cos(a) * st, y + math.sin(a) * st
            pts.append((x, y))
        wd = R.uniform(0.8, 2.0)
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                cv.line([(px + ox, py + oy) for px, py in pts], wd, int(R.uniform(150, 255)))
                # branches fines
        for b in range(3):
            j = int(R.integers(1, len(pts)))
            bx, by = pts[j]
            ba = R.uniform(0, 2 * math.pi)
            bp = [(bx, by)]
            for k in range(6):
                ba += R.normal(0, 0.5)
                bx, by = bx + math.cos(ba) * 10, by + math.sin(ba) * 10
                bp.append((bx, by))
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    cv.line([(px + ox, py + oy) for px, py in bp], 0.7, 120)
    cracks = cv.array()
    hgt = np.clip(0.55 + blur_noise(N, N, 30, 21) * 0.08 + agg * 0.06 + agg_l * 0.2 - pores * 0.4 - cracks * 0.5, 0, 1)
    rough = np.clip(0.5 + blur_noise(N, N, 40, 18) * 0.18 + aniso_noise(N, N, 80, 6, 19) * 0.06 + agg_l * 0.1, 0, 1)
    det = np.stack([albvar, cracks, hgt, rough], -1)
    save_rgba(os.path.join(OUT, "roof_detail.png"), det)


# ================================================================ carte du toit
MPX = MW / MXW


def to_px(x, z):
    return (x - MX0) * MPX, (z - MZ0) * MPX


def make_macro(pid, panels, memb):
    print("carte du toit")
    h, w = MH, MW
    zz, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    X = MX0 + (xx + 0.5) / MPX
    Z = MZ0 + (zz + 0.5) / MPX
    # relief de la toiture : pentes douces vers les siphons, cuvettes de bruit
    relief = fbm(h, w, 160, 4, 301) * 0.55 + blur_noise(h, w, 40, 302) * 0.18
    drains = []
    for p in panels:
        x, z, ww, hh, k = p[:5]
        if k == DRAIN:
            drains.append((cx_(x + 0.5), cz_(z + 0.5)))
    sink = np.zeros((h, w), np.float32)
    for (dx, dz) in drains:
        d = np.sqrt((X - dx) ** 2 + (Z - dz) ** 2)
        sink = np.maximum(sink, np.exp(-(d / 1.6) ** 2) * 1.2 + np.exp(-(d / 0.6) ** 2) * 0.6)
    # le pied des parapets retient l'eau (relevés d'étanchéité)
    de = np.minimum.reduce([X - X0, X1 - X, Z - Z0, Z1 - Z])
    edge = np.exp(-(np.clip(de, 0, None) / 0.45) ** 2)
    relief = relief - sink * 0.9 - edge * 0.75 * (0.4 + 0.6 * norm01(blur_noise(h, w, 50, 303)))
    # aire d'atterrissage : légèrement bombée (sèche au centre, flaques sur le pourtour)
    hx, hz, hr = HELI
    dh = np.sqrt((X - hx) ** 2 + (Z - hz) ** 2)
    relief = relief + np.exp(-(dh / (hr * 0.8)) ** 2) * 0.7
    water = smoothstep(-0.95, -1.45, relief)
    # contour des flaques irrégulier
    water *= smoothstep(-0.6, 0.4, blur_noise(h, w, 6, 304) + water * 2.2)
    # film d'eau peu profond autour des flaques (plus lisse, pas plus sombre)
    film = smoothstep(-0.45, -0.95, relief) * (0.22 + 0.12 * norm01(blur_noise(h, w, 20, 308)))
    water = np.maximum(water, film)
    # flaques isolées en plus dans le champ (dalles affaissées)
    for i in range(18):
        x, z = R.uniform(X0 + 1, X1 - 1), R.uniform(Z0 + 1, Z1 - 1)
        if math.hypot(x - hx, z - hz) < hr * 0.7:
            continue
        rx, rz = R.uniform(0.4, 1.4), R.uniform(0.3, 1.0)
        a = R.uniform(0, math.pi)
        u = ((X - x) * math.cos(a) + (Z - z) * math.sin(a)) / rx
        v = (-(X - x) * math.sin(a) + (Z - z) * math.cos(a)) / rz
        blob = 1 - np.sqrt(u * u + v * v)
        water = np.maximum(water, smoothstep(-0.1, 0.5, blob + blur_noise(h, w, 8, 400 + i) * 0.25) * R.uniform(0.5, 1.0))
    water = blur(water, 1.2)
    # crasse : pied des parapets, auréoles sèches autour des flaques, coulures de suie
    ring = np.clip(blur(water, 10) - water, 0, 1)
    grime = np.clip(edge * 0.6 + ring * 2.0 + norm01(fbm(h, w, 90, 4, 305)) * 0.35 - 0.12, 0, 1)
    soot = np.zeros((h, w), np.float32)
    for i in range(18):
        x, z = R.uniform(X0, X1), R.uniform(Z0, Z1)
        a = R.uniform(0, math.pi)
        L = R.uniform(1.5, 4.0)
        u = ((X - x) * math.cos(a) + (Z - z) * math.sin(a))
        v = (-(X - x) * math.sin(a) + (Z - z) * math.cos(a))
        s = np.exp(-(v / R.uniform(0.15, 0.45)) ** 2) * smoothstep(0, 0.4, u) * smoothstep(L, L * 0.5, u)
        soot = np.maximum(soot, s * R.uniform(0.3, 0.7))
    grime = np.clip(grime + soot * (0.6 + 0.4 * norm01(blur_noise(h, w, 5, 306))), 0, 1)
    # traînées de pluie : ruissellements qui descendent le relief vers les flaques et les siphons
    print("  traînées")
    rel = blur(relief, 4)
    gz, gx = np.gradient(rel)
    cv = Canvas(w, h, 2)
    for i in range(520):
        x, z = R.uniform(0, w), R.uniform(0, h)
        pts = [(x, z)]
        wd = R.uniform(1.0, 2.6)
        for k in range(160):
            ix, iz = int(min(max(x, 0), w - 1)), int(min(max(z, 0), h - 1))
            vx, vz = -gx[iz, ix], -gz[iz, ix]
            ln = math.hypot(vx, vz) + 1e-6
            jx, jz = R.normal(0, 0.35), R.normal(0, 0.35)
            x += (vx / ln + jx) * 2.2
            z += (vz / ln + jz) * 2.2
            pts.append((x, z))
            if water[int(min(max(z, 0), h - 1)), int(min(max(x, 0), w - 1))] > 0.6:
                break
        if len(pts) > 6:
            cv.line(pts, wd, int(R.uniform(110, 255)))
    trails = blur(cv.array(), 0.6)
    trails *= 0.6 + 0.4 * norm01(blur_noise(h, w, 20, 307))
    # taches d'huile (reflets irisés sur l'eau)
    oil = np.zeros((h, w), np.float32)
    for i in range(7):
        x, z = R.uniform(X0 + 2, X1 - 2), R.uniform(Z0 + 1.5, Z1 - 1.5)
        r = R.uniform(0.3, 0.8)
        d = np.sqrt((X - x) ** 2 + ((Z - z) * R.uniform(0.7, 1.4)) ** 2) / r
        oil = np.maximum(oil, smoothstep(1.0, 0.3, d + blur_noise(h, w, 4, 500 + i) * 0.25) * R.uniform(0.5, 1.0))
    mac = np.stack([water, grime, trails, oil], -1)
    save_rgba(os.path.join(OUT, "roof_macro.png"), mac)
    return water


# ================================================================ pièces du sol (albédo + hauteur)
IPX = 160  # px par mètre
IRON = srgb("#2a2d33")
IRON_D = srgb("#17191e")
GALV = srgb("#6b7079")
GALV_D = srgb("#3b4048")
CONC = srgb("#4a4e57")


def dome(xx, zz, cx, cz, r):
    d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2) / r
    return np.sqrt(np.clip(1 - d * d, 0, 1))


def tread(xx, zz, pitch=0.05):
    """Tôle larmée : petits reliefs allongés alternés."""
    i = np.floor(xx / pitch)
    j = np.floor(zz / pitch)
    fx = np.mod(xx, pitch) / pitch - 0.5
    fz = np.mod(zz, pitch) / pitch - 0.5
    alt = np.mod(i + j, 2) == 0
    u = np.where(alt, fx * 0.7 + fz * 0.7, fx * 0.7 - fz * 0.7)
    v = np.where(alt, -fx * 0.7 + fz * 0.7, fx * 0.7 + fz * 0.7)
    return np.sqrt(np.clip(1 - (u / 0.42) ** 2 - (v / 0.12) ** 2, 0, 1))


def paint_insert(kind, wm, hm, seed):
    pw, ph = int(round(wm * IPX)), int(round(hm * IPX))
    zz, xx = np.mgrid[0:ph, 0:pw].astype(np.float32)
    xx = (xx + 0.5) / IPX
    zz = (zz + 0.5) / IPX
    nf = blur_noise(ph, pw, 3, seed) * 0.5 + blur_noise(ph, pw, 14, seed + 1) * 0.5
    hgt = np.full((ph, pw), 0.75, np.float32)
    alb = np.ones((ph, pw, 3), np.float32) * CONC
    edge = np.minimum.reduce([xx, zz, wm - xx, hm - zz])
    if kind == DRAIN:
        cx, cz = wm * 0.5, hm * 0.5
        d = np.sqrt((xx - cx) ** 2 + (zz - cz) ** 2)
        # collerette de bitume, bride de serrage, crapaudine en dôme à fentes
        coll = d < 0.5
        alb = np.where(coll[..., None], srgb("#1c1d22") * (0.9 + 0.2 * nf[..., None]), alb)
        hgt = np.where(coll, 0.7 - (0.5 - d) * 0.25, hgt)
        flange = (d > 0.2) & (d < 0.3)
        hgt = np.where(flange, 0.78, hgt)
        alb = np.where(flange[..., None], IRON * 1.1, alb)
        a = np.arctan2(zz - cz, xx - cx)
        for k in range(8):
            ba = k * math.pi / 4 + math.pi / 8
            bx, bz = cx + math.cos(ba) * 0.25, cz + math.sin(ba) * 0.25
            b = dome(xx, zz, bx, bz, 0.016)
            hgt = np.maximum(hgt, np.where(b > 0, 0.8 + b * 0.1, 0))
            alb = np.where((b > 0)[..., None], IRON * 1.6, alb)
        domm = d < 0.2
        slot = (np.abs(np.mod(a * 12 / (2 * math.pi), 1.0) - 0.5) < 0.22) & (d > 0.05) & (d < 0.18)
        ringc = np.abs(np.mod(d / 0.065, 1.0) - 0.5) < 0.15
        hole = slot & ~ringc
        hgt = np.where(domm, np.where(hole, 0.05, 0.82 + 0.12 * np.sqrt(np.clip(1 - (d / 0.2) ** 2, 0, 1))), hgt)
        alb = np.where(domm[..., None], np.where(hole[..., None], srgb("#050608"), IRON * (1.0 + 0.4 * nf[..., None])), alb)
    elif kind == HATCH:
        ins = 0.1
        curb = (edge < ins)
        lid = edge > ins + 0.015
        groove = ~curb & ~lid
        tr = tread(xx, zz)
        hgt = np.where(curb, 0.92, np.where(lid, 0.8 + tr * 0.1, 0.25))
        alb = np.where(curb[..., None], GALV_D * (1 + 0.2 * nf[..., None]), alb)
        alb = np.where(lid[..., None], GALV * (0.75 + 0.3 * tr[..., None]) * (0.9 + 0.15 * nf[..., None]), alb)
        alb = np.where(groove[..., None], IRON_D * 0.5, alb)
        # bande de danger sur le pourtour du couvercle
        band = lid & (edge < ins + 0.13)
        st = np.mod((xx + zz) / 0.12, 1.0) < 0.5
        alb = np.where((band & st)[..., None], srgb("#a8892e") * 0.8, alb)
        alb = np.where((band & ~st)[..., None], srgb("#1a1b1f"), alb)
        # poignée et charnières
        hx0, hx1 = wm * 0.5 - 0.16, wm * 0.5 + 0.16
        pocket = (xx > hx0) & (xx < hx1) & (zz > hm - 0.42) & (zz < hm - 0.3)
        hgt = np.where(pocket, 0.35, hgt)
        alb = np.where(pocket[..., None], IRON_D, alb)
        bar = pocket & (np.abs(zz - (hm - 0.36)) < 0.012) & (xx > hx0 + 0.03) & (xx < hx1 - 0.03)
        hgt = np.where(bar, 0.85, hgt)
        alb = np.where(bar[..., None], GALV * 1.3, alb)
        for hx in (wm * 0.25, wm * 0.75):
            hin = (np.abs(xx - hx) < 0.1) & (zz > ins - 0.02) & (zz < ins + 0.08)
            hgt = np.where(hin, 0.97, hgt)
            alb = np.where(hin[..., None], GALV_D * 1.4, alb)
    elif kind == SKY:
        # lanterneau : costière, verrière en 2 x 4 carreaux armés, lumière chaude de l'intérieur
        ins = 0.09
        curb = edge < ins
        hgt = np.where(curb, 0.95, hgt)
        alb = np.where(curb[..., None], GALV_D * (1 + 0.2 * nf[..., None]), alb)
        gx = np.mod((xx - ins) / ((wm - 2 * ins) / 4), 1.0)
        gz = np.mod((zz - ins) / ((hm - 2 * ins) / 2), 1.0)
        mull = (np.minimum(gx, 1 - gx) < 0.035) | (np.minimum(gz, 1 - gz) < 0.06)
        glass = ~curb & ~mull
        hgt = np.where(~curb, np.where(mull, 0.85, 0.04), hgt)
        alb = np.where((~curb & mull)[..., None], IRON * 1.2, alb)
        # verre armé : treillis fin, lueur plus forte au centre
        wire = (np.abs(np.mod(xx / 0.025, 1.0) - 0.5) < 0.08) | (np.abs(np.mod(zz / 0.025, 1.0) - 0.5) < 0.08)
        warm = srgb("#ffb070") * (0.75 + 0.25 * np.exp(-(((xx - wm / 2) / wm) ** 2 + ((zz - hm / 2) / hm) ** 2) * 3))[..., None]
        gcol = np.where(wire[..., None], warm * 0.55, warm)
        alb = np.where(glass[..., None], gcol * (0.85 + 0.15 * nf[..., None]), alb)
        # crasse sur le verre
        dirt = smoothstep(0.2, 0.9, norm01(blur_noise(ph, pw, 12, seed + 3)))
        alb = np.where(glass[..., None], alb * (1 - dirt[..., None] * 0.45), alb)
    elif kind in (GRATE, CHAN_V, CHAN_H):
        if kind == GRATE:
            fr = 0.07
            frame = edge < fr
            hgt = np.where(frame, 0.9, hgt)
            alb = np.where(frame[..., None], GALV_D * 1.1, alb)
            ph_ = np.mod(xx / 0.06, 1.0)
            bars = np.sqrt(np.clip(1 - ((ph_ - 0.5) / 0.3) ** 2, 0, 1))
            inner = ~frame
            hb = np.where(bars > 0.05, 0.6 + bars * 0.25, 0.03)
            hgt = np.where(inner, hb, hgt)
            alb = np.where(inner[..., None], np.where((bars > 0.05)[..., None], GALV * (0.6 + 0.4 * bars[..., None]), srgb("#090a0d")), alb)
            # traverse au milieu
            mid = inner & (np.abs(zz - hm * 0.5) < 0.025)
            hgt = np.where(mid, 0.88, hgt)
            alb = np.where(mid[..., None], GALV_D * 1.2, alb)
        else:
            along = zz if kind == CHAN_V else xx
            across = xx if kind == CHAN_V else zz
            ac = (wm if kind == CHAN_V else hm) * 0.5
            ch = np.abs(across - ac) < 0.11
            lip = (np.abs(across - ac) >= 0.11) & (np.abs(across - ac) < 0.14)
            alb = np.where(np.abs(across - ac)[..., None] < 0.4, srgb("#1c1d22") * (0.9 + 0.2 * nf[..., None]), alb)
            hgt = np.where(lip, 0.8, hgt)
            alb = np.where(lip[..., None], GALV_D, alb)
            slots = np.abs(np.mod(along / 0.045, 1.0) - 0.5) < 0.28
            hgt = np.where(ch, np.where(slots, 0.04, 0.72), hgt)
            alb = np.where(ch[..., None], np.where(slots[..., None], srgb("#060709"), IRON * 1.2), alb)
    elif kind == PLATE:
        ins = 0.06
        plate = edge > ins
        tr = tread(xx, zz, 0.045)
        hgt = np.where(plate, 0.8 + tr * 0.1, 0.3)
        alb = np.where(plate[..., None], IRON * (1.1 + 0.4 * tr[..., None]) * (0.9 + 0.2 * nf[..., None]), IRON_D)
        for cx in (ins + 0.06, wm - ins - 0.06):
            for cz in (ins + 0.06, hm - ins - 0.06):
                b = dome(xx, zz, cx, cz, 0.02)
                hgt = np.where(b > 0, 0.85 + b * 0.1, hgt)
                alb = np.where((b > 0)[..., None], GALV, alb)
        # rouille aux bords
        rust = smoothstep(0.55, 0.95, norm01(blur_noise(ph, pw, 6, seed + 4)) + smoothstep(0.25, 0.06, edge) * 0.4)
        alb = alb * (1 - rust[..., None] * 0.5) + srgb("#5a3420")[None, None, :] * rust[..., None] * 0.5
    # usure : arêtes hautes plus claires, creux plus sombres
    hi = smoothstep(0.85, 1.0, hgt)
    alb = alb * (1 + hi[..., None] * 0.25)
    alb = alb * (0.94 + 0.06 * np.clip(nf, -2, 2)[..., None])
    return np.clip(alb, 0, 1), np.clip(hgt, 0, 1)


# ================================================================ marquages peints
MPXM = 160
WHITE = srgb("#d9dbe0")
YEL = srgb("#d8b23a")
BLK = srgb("#15161a")
CYANP = srgb("#5fd6cf")
PINKP = srgb("#d64f9a")


def mk(wm, hm):
    return Canvas(int(round(wm * MPXM)), int(round(hm * MPXM)), 2)


def worn(mask, seed, amount=0.3):
    h, w = mask.shape
    e = norm01(blur_noise(h, w, 2.0, seed) * 0.5 + blur_noise(h, w, 9, seed + 1) * 0.8 + blur_noise(h, w, 36, seed + 2) * 0.7)
    keep = smoothstep(amount - 0.1, amount + 0.12, e)
    return mask * keep


def mark_rgba(layers, seed, amount=0.3):
    h, w = layers[0][0].shape
    a = np.zeros((h, w))
    col = np.zeros((h, w, 3))
    for m, c in layers:
        col = col * (1 - m[..., None]) + c[None, None, :] * m[..., None]
        a = np.maximum(a, m)
    base = layers[0][1]
    aa = np.clip(a[..., None], 0, 1)
    col = np.where(aa > 0.01, col / np.maximum(aa, 1e-3) * aa + base * (1 - aa), base)
    a = worn(a, seed, amount)
    col = col * (0.9 + 0.06 * blur_noise(h, w, 8, seed + 7)[..., None])
    return np.concatenate([np.clip(col, 0, 1), a[..., None]], -1)


def make_marks(glyphs):
    out = {}
    # aire d'atterrissage : cercle épais, H, graduations
    cv = Canvas(1024, 1024, 2)
    w = cv.w
    c = w * 0.5
    cv.ellipse(c, c, w * 0.485, w * 0.485, width=w * 0.03)
    cv2 = Canvas(1024, 1024, 2)
    for k in range(36):
        a = k * 2 * math.pi / 36
        r0, r1 = w * 0.425, w * 0.455 if k % 3 else w * 0.47
        cv2.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], w * 0.006)
    # H (signe universel d'hélistation)
    hw, hh, t = w * 0.2, w * 0.3, w * 0.055
    cv.rect(c - hw, c - hh, c - hw + t, c + hh)
    cv.rect(c + hw - t, c - hh, c + hw, c + hh)
    cv.rect(c - hw, c - t * 0.5, c + hw, c + t * 0.5)
    out["heli"] = (mark_rgba([(cv.array(), WHITE), (cv2.array(), YEL)], 601, 0.33), (8.4, 8.4))
    # chiffres de toit
    for s in ("47", "12"):
        cv = mk(1.6, 1.1)
        cv.text(cv.w * 0.5, cv.h * 0.55, s, cv.h * 0.95, spacing=cv.h * 0.05)
        out["num" + s] = (mark_rgba([(cv.array(), WHITE)], 610 + int(s), 0.32), (1.6, 1.1))
    # bande de danger jaune et noire (1 m, raccordable en u)
    cv = mk(1.0, 0.24)
    ww, hh_ = cv.w, cv.h
    jj, ii = np.meshgrid(np.arange(ww), np.arange(hh_))
    st = (np.mod((jj + ii) / (MPXM * 0.2), 1.0) < 0.5).astype(np.float32)
    out["stripe"] = (mark_rgba([(np.ones((hh_, ww), np.float32), BLK), (st, YEL)], 620, 0.26), (1.0, 0.24))
    # trait et tirets
    cv = mk(1.0, 0.08)
    cv.rect(0, 0, cv.w, cv.h)
    out["line"] = (mark_rgba([(cv.array(), WHITE)], 621, 0.28), (1.0, 0.08))
    cv = mk(1.0, 0.08)
    cv.rect(0, 0, cv.w * 0.55, cv.h)
    out["dash"] = (mark_rgba([(cv.array(), WHITE)], 622, 0.28), (1.0, 0.08))
    cv = mk(1.0, 0.08)
    cv.rect(0, 0, cv.w, cv.h)
    out["line_y"] = (mark_rgba([(cv.array(), YEL)], 623, 0.28), (1.0, 0.08))
    # chemin piéton : pavés peints (1 m, raccordable)
    cv = mk(1.0, 0.6)
    cv.rrect(cv.w * 0.06, cv.h * 0.08, cv.w * 0.94, cv.h * 0.92, cv.h * 0.12)
    out["walk"] = (mark_rgba([(cv.array(), srgb("#4b5a64"))], 624, 0.24), (1.0, 0.6))
    # flèche d'approche
    cv = mk(1.4, 0.7)
    cv.rect(cv.w * 0.05, cv.h * 0.38, cv.w * 0.6, cv.h * 0.62)
    cv.poly([(cv.w * 0.55, cv.h * 0.08), (cv.w * 0.97, cv.h * 0.5), (cv.w * 0.55, cv.h * 0.92)])
    out["arrow"] = (mark_rgba([(cv.array(), WHITE)], 625, 0.3), (1.4, 0.7))
    # chevrons
    cv = mk(1.2, 0.5)
    for k in range(3):
        x0 = cv.w * (0.06 + 0.3 * k)
        cv.poly([(x0, 0), (x0 + cv.w * 0.16, 0), (x0 + cv.w * 0.34, cv.h * 0.5), (x0 + cv.w * 0.16, cv.h), (x0, cv.h), (x0 + cv.w * 0.18, cv.h * 0.5)])
    out["chevrons"] = (mark_rgba([(cv.array(), YEL)], 626, 0.3), (1.2, 0.5))
    # pochoirs en idéogrammes inventés (consignes de toit)
    for i in range(5):
        n = int(R.integers(3, 6))
        cv = mk(0.42 * n * 1.18, 0.5)
        glyph_text(cv, cv.h * 0.1, cv.h * 0.1, cv.h * 0.8, glyphs, list(R.integers(0, len(glyphs), n)), width=0.14)
        col = YEL if i % 2 == 0 else WHITE
        out["sten%d" % i] = (mark_rgba([(cv.array(), col)], 630 + i, 0.32), (0.42 * n * 1.18, 0.5))
    # cadre d'apparition : crochets aux coins et cercle pointillé
    cv = mk(2.6, 2.6)
    w = cv.w
    t, L = w * 0.035, w * 0.2
    for (x0, y0, sx, sy) in ((0, 0, 1, 1), (w, 0, -1, 1), (0, w, 1, -1), (w, w, -1, -1)):
        cv.rect(min(x0, x0 + sx * L), min(y0, y0 + sy * t), max(x0, x0 + sx * L), max(y0, y0 + sy * t))
        cv.rect(min(x0, x0 + sx * t), min(y0, y0 + sy * L), max(x0, x0 + sx * t), max(y0, y0 + sy * L))
    out["pad"] = (mark_rgba([(cv.array(), CYANP)], 640, 0.3), (2.6, 2.6))
    # graffitis au sol : formes abstraites (bulles, éclairs, étoile), sans texte
    for i, col in enumerate((PINKP, CYANP, srgb("#9a6be0"))):
        cv = mk(2.0, 1.2)
        ww, hh_ = cv.w, cv.h
        cv2 = mk(2.0, 1.2)
        rng = np.random.default_rng(650 + i)
        for k in range(5):
            x, y = rng.uniform(0.15, 0.85) * ww, rng.uniform(0.25, 0.75) * hh_
            r = rng.uniform(0.12, 0.24) * hh_
            cv.ellipse(x, y, r * 1.3, r)
            cv2.ellipse(x, y, r * 0.95, r * 0.65)
        pts = [(ww * 0.1, hh_ * 0.8), (ww * 0.4, hh_ * 0.2), (ww * 0.5, hh_ * 0.55), (ww * 0.9, hh_ * 0.15)]
        cv.line(pts, hh_ * 0.07)
        outline = np.clip(cv.array() - cv2.array() * 0.85, 0, 1)
        fill = cv2.array()
        out["graf%d" % i] = (mark_rgba([(outline, srgb("#e8e8ee")), (fill, col)], 650 + i, 0.36), (2.0, 1.2))
    return out


def pack(items, x0, y0, x1, y1, pad=8):
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


def make_atlas(glyphs):
    print("atlas du sol")
    A = 2048
    atlas = np.zeros((A, A, 4), np.float32)
    marks = make_marks(glyphs)
    pos = pack({k: (v[0].shape[1], v[0].shape[0]) for k, v in marks.items()}, 0, 0, A, A * 3 // 4 + 128, 8)
    mark_rects = {}
    for k, (img, size) in marks.items():
        x, y = pos[k]
        hh, ww = img.shape[:2]
        atlas[y:y + hh, x:x + ww] = img
        mark_rects[k] = {"uv": [x / A, y / A, ww / A, hh / A], "size": list(size)}
    ins = {}
    for k, (cw, ch) in KIND_CELLS.items():
        alb, hgt = paint_insert(k, cw * CX, ch * CZ, 700 + k)
        ins[k] = np.concatenate([alb, hgt[..., None]], -1)
    y0 = max(pos[k][1] + marks[k][0].shape[0] for k in marks) + 12
    ipos = pack({k: (v.shape[1], v.shape[0]) for k, v in ins.items()}, 0, y0, A, A, 10)
    ins_rects = [[0, 0, 0, 0] for _ in range(9)]
    for k, img in ins.items():
        x, y = ipos[k]
        hh, ww = img.shape[:2]
        atlas[y:y + hh, x:x + ww] = img
        atlas[y - 4:y, x:x + ww] = img[:1]
        atlas[y + hh:y + hh + 4, x:x + ww] = img[-1:]
        atlas[y - 4:y + hh + 4, x - 4:x] = atlas[y - 4:y + hh + 4, x:x + 1]
        atlas[y - 4:y + hh + 4, x + ww:x + ww + 4] = atlas[y - 4:y + hh + 4, x + ww - 1:x + ww]
        ins_rects[k] = [x / A, y / A, ww / A, hh / A]
    save_rgba(os.path.join(OUT, "roof_atlas.png"), atlas)
    return mark_rects, ins_rects


# ================================================================ marquages posés
def decals():
    """[nom, x, z, longueur (u), largeur (v), angle (deg), répétitions u, v, opacité, usure en plus]."""
    out = []

    def add(name, x, z, su, sv, ang=0.0, ru=1, rv=1, op=1.0, wear=0.0):
        out.append([name, round(x, 3), round(z, 3), round(su, 3), round(sv, 3), ang, ru, rv, op, wear])

    hx, hz, hr = HELI
    add("heli", hx, hz, hr * 2.05, hr * 2.05, 0, 1, 1, 0.85)
    # approche : flèches et chevrons sur l'axe est-ouest de l'aire
    for sx in (-1, 1):
        add("chevrons", hx + sx * (hr + 1.1), hz, 1.1, 0.46, 180 if sx > 0 else 0, 1, 1, 0.65)
    add("num47", hx, hz - hr - 0.95, 1.4, 0.96, 0, 1, 1, 0.8)
    add("num12", hx, hz + hr + 0.95, 1.4, 0.96, 180, 1, 1, 0.75)
    # bandes de danger au bord intérieur de la bande d'étanchéité (pas sur toute la longueur)
    zA, zB = cz_(1) + 0.16, cz_(NZ - 1) - 0.16
    xA, xB = cx_(1) + 0.16, cx_(NX - 1) - 0.16
    for (x0, x1) in ((xA + 1.0, 9.6), (13.5, 23.5), (27.6, xB - 1.0)):
        L = x1 - x0
        add("stripe", (x0 + x1) * 0.5, zB, L, 0.24, 180, round(L), 1, 0.7)
    for (x0, x1) in ((xA + 2.6, 11.0), (16.0, 21.5), (25.4, xB - 2.6)):
        L = x1 - x0
        add("stripe", (x0 + x1) * 0.5, zA, L, 0.24, 0, round(L), 1, 0.7)
    for x, ang in ((xA, 90), (xB, -90)):
        for (z0, z1) in ((zA + 2.4, 10.4), (14.8, zB - 2.4)):
            L = z1 - z0
            add("stripe", x, (z0 + z1) * 0.5, L, 0.24, ang, round(L), 1, 0.7)
    # chemin piéton du lanterneau au portillon de la passerelle
    for (x0, z0, x1, z1) in ((cx_(26) + 1.2, cz_(7) + 0.5, cx_(28) + 0.6, cz_(7) + 0.5),):
        L = abs(x1 - x0)
        add("walk", (x0 + x1) * 0.5, z0, L, 0.6, 0, round(L), 1, 0.7)
    zw = (cz_(1) + cz_(7)) * 0.5
    L = cz_(7) - cz_(1) - 0.6
    add("walk", cx_(28) + 0.9, zw + 0.3, L, 0.6, 90, round(L), 1, 0.7)
    # lignes de sécurité autour des lanterneaux et trappes
    add("line_y", cx_(4) + CX, cz_(5) - 0.25, 2 * CX + 0.5, 0.08, 0, round(2 * CX + 0.5), 1, 0.6)
    add("line_y", cx_(4) + CX, cz_(6) + 0.25, 2 * CX + 0.5, 0.08, 0, round(2 * CX + 0.5), 1, 0.6)
    add("line_y", cx_(26) + CX, cz_(6) - 0.25, 2 * CX + 0.5, 0.08, 0, round(2 * CX + 0.5), 1, 0.6)
    add("line_y", cx_(18) + CX, cz_(13) + 0.25, 2 * CX + 0.5, 0.08, 0, round(2 * CX + 0.5), 1, 0.6)
    # pochoirs
    add("sten0", cx_(9) + CX, cz_(4) - 0.4, 1.9, 0.48, 0, 1, 1, 0.7)
    add("sten1", cx_(25) + CX, cz_(12) + 0.4, 1.4, 0.48, 0, 1, 1, 0.65)
    add("sten2", hx - 2.6, hz + hr + 0.55, 1.7, 0.42, 0, 1, 1, 0.6)
    add("sten3", 6.0, zB - 0.6, 2.0, 0.48, 0, 1, 1, 0.6)
    add("sten4", 31.0, zA + 0.6, 1.5, 0.48, 0, 1, 1, 0.6)
    # tirets d'allée vers l'aire
    for (x0, x1) in ((xA + 1.5, hx - hr - 1.9), (hx + hr + 1.9, xB - 1.5)):
        L = x1 - x0
        add("dash", (x0 + x1) * 0.5, hz, L, 0.08, 0, round(L / 1.2), 1, 0.55)
    # graffitis (près des parapets)
    add("graf0", 3.6, 16.6, 1.9, 1.15, 12, 1, 1, 0.55, 0.05)
    add("graf1", 33.4, 17.8, 1.9, 1.15, -8, 1, 1, 0.5, 0.05)
    add("graf2", 12.4, 19.8, 1.6, 0.95, 4, 1, 1, 0.45, 0.1)
    # sas d'apparition (positions de arena.gd)
    pads = [(130, TOP * 64 + 90), (2400 - 130, TOP * 64 + 90), (130, 1400 - 130), (2400 - 130, 1400 - 130),
            (1200, TOP * 64 + 80), (1200, 1400 - 110), (110, (TOP * 64 + 1400) * 0.5), (2400 - 110, (TOP * 64 + 1400) * 0.5)]
    for (px, pz) in pads:
        add("pad", px / 64.0, pz / 64.0, 2.45, 2.45, 0, 1, 1, 0.55)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    glyphs = draw_glyphs(64)
    pid, panels, memb = build_layout()
    cells = layout_cells(pid, panels)
    make_detail()
    make_macro(pid, panels, memb)
    mark_rects, ins_rects = make_atlas(glyphs)
    write_json(os.path.join(OUT, "roof_layout.json"), {
        "grid": [X0, Z0, CX, CZ, NX, NZ],
        "macro": [MX0, MZ0, MXW, MZH],
        "heli": list(HELI),
        "cells": cells,
        "ins_rects": ins_rects,
        "ins_cells": [[1, 1]] + [list(KIND_CELLS.get(k, (1, 1))) for k in range(1, 9)],
        "marks": mark_rects,
        "decals": decals(),
    })


if __name__ == "__main__":
    main()
