#!/usr/bin/env python3
"""Cité Néon — bords du toit et tour voisine : parapets, couvertines, tubes néon, rambardes, câbles, antennes,
façade de la tour voisine (écrans, enseignes, climatiseurs, escalier de secours), passerelle, lanternes.

Écrit dans assets/decor/neon/shell/ :
  neon_atlas.png   2048² : bande proche de la façade (2 x 21,75 m à 84 px/m), planche d'idéogrammes,
                   tuiles (béton, métal, graffitis, climatiseurs, caillebotis, enseignes en drapeau) ;
                   RGB albédo (sRGB), A masque lumineux
  neon_facade.png  2048 x 1024 : carte de la façade entière (reflets), RGB émission, A couverture
  shell_edges.glb  « edges » : tout l'opaque (un matériau, neon_shell.gdshader)
  shell_meta.json  écrans, tubes néon (lumières simulées), cadres de l'atlas
Sommets : COLOR.rgb teinte, COLOR.a classe (0 béton / peint, 1/3 métal, 2/3 caoutchouc, 1 lumineux) ;
UV2.x animation (0 fixe, 0,25 grésille, 0,5 clignote, 0,75 écran n° UV2.y * 4, 1 carte de façade), UV2.y phase.
Lancement : python3 tools/decor/neon_shell_edges.py
"""
import math
import os

import numpy as np

from neon_shell_common import (A_BLINK, A_BUZZ, A_NONE, A_SCREEN, ACID, BARE, BLUE, BRIDGE_W, BRIDGE_X, FLOOR_H,
                               FLOOR_Y0, FX0, FX1, FY0, FY1, GLOW, H, MB, ORANGE, OUT, PAINT, PAR_H, PAR_T, PINK,
                               ROOF_Y, RUBBER, TOWER_X0, TOWER_X1, TOWER_Y, VIOLET, W, X0, X1, Z0, Z1, ZF, ZN, Atlas, Canvas, aniso_noise, blur,
                               blur_noise, catenary, glyph_mask, glyph_text, norm01, save_rgba, smoothstep, srgb,
                               write_glb, write_json)
import neon_shell_facade as FAC

R = np.random.default_rng(909)
ONE = (1.0, 1.0, 1.0)
A_MAP = 1.0
COL = FAC.COL


# ================================================================ atlas
def tile(wm, hm, ppm):
    w, h = int(round(wm * ppm)), int(round(hm * ppm))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return w, h, xx / ppm, yy / ppm


def rgba(rgb, a=None):
    h, w = rgb.shape[:2]
    return np.concatenate([np.clip(rgb, 0, 1), (np.zeros((h, w)) if a is None else a)[..., None]], -1)


def make_atlas():
    print("atlas des bords")
    at = Atlas(2048, 2048, 8)
    sa, sb = FAC.near_strips()
    at.put("near_a", sa)
    at.put("near_b", sb)
    # planche d'idéogrammes 8 x 8 (64 px)
    g = np.zeros((512, 512), np.float32)
    for i, st in enumerate(FAC.GLYPHS):
        r, c = i // 8, i % 8
        g[r * 64:(r + 1) * 64, c * 64:(c + 1) * 64] = glyph_mask(st, 64, 0.1)
    at.put("glyphs", np.stack([g, g, g, np.ones_like(g)], -1))
    # béton du parapet (2 m x 0,6 m, raccordable en u) : taches, coulures, éclats
    w, h, xx, yy = tile(2.0, 0.6, 160)
    n = blur_noise(h, w, 30, 11) * 0.5 + blur_noise(h, w, 4, 12) * 0.3 + blur_noise(h, w, 1, 13) * 0.2
    img = np.ones((h, w, 3)) * srgb("#3d3f48") * (0.85 + 0.15 * n[..., None])
    streak = blur(blur_noise(h, w, 1, 14), (h * 0.3, 1.5), True)
    streak = streak / (streak.std() + 1e-6)
    img *= (1 + np.clip(streak, -2, 2) * 0.08)[..., None]
    foot = smoothstep(0.3, 0.6, yy / 0.6)
    img *= (1 - foot * 0.45)[..., None]
    pores = blur_noise(h, w, 1.0, 15) > 2.4
    img = np.where(pores[..., None], img * 0.5, img)
    joint = np.abs(np.mod(xx, 2.0)) < 0.008
    img = np.where(joint[..., None], img * 0.3, img)
    at.put("conc", rgba(img))
    # couvertine métallique (pliée, joints tous les 2 m)
    w, h, xx, yy = tile(2.0, 0.2, 160)
    img = np.ones((h, w, 3)) * srgb("#7a808c") * (0.8 + 0.2 * norm01(aniso_noise(h, w, 2, 40, 21)))[..., None]
    img = np.where((np.abs(xx - 1.0) < 0.01)[..., None], img * 0.5, img)
    at.put("coping", rgba(img))
    # métal sombre, caoutchouc, blanc (teinté par la couleur de sommet)
    at.put("dark", rgba(np.ones((24, 24, 3)) * srgb("#26272e")))
    at.put("steel", rgba(np.ones((24, 24, 3)) * srgb("#8a8f99")))
    at.put("white", rgba(np.ones((24, 24, 3)), np.ones((24, 24))))
    at.put("black", rgba(np.ones((24, 24, 3)) * 0.02))
    # graffitis du parapet (3 m x 0,5 m) : bulles, flèches, tags abstraits, sans texte
    for k in range(4):
        w, h, xx, yy = tile(3.0, 0.5, 110)
        base = np.ones((h, w, 3)) * srgb("#3d3f48")
        cv, cv2 = Canvas(w, h, 2), Canvas(w, h, 2)
        rng = np.random.default_rng(300 + k)
        cols = [PINK, BLUE * 0.8 + 0.2, ACID * 0.8, VIOLET, ORANGE]
        c1, c2 = cols[k % 5], cols[(k + 2) % 5]
        for b in range(int(rng.integers(3, 6))):
            x, y = rng.uniform(0.1, 0.9) * w, rng.uniform(0.35, 0.65) * h
            r = rng.uniform(0.25, 0.42) * h
            cv.ellipse(x, y, r * rng.uniform(1.0, 1.8), r)
            cv2.ellipse(x, y, r * 0.8 * rng.uniform(1.0, 1.6), r * 0.72)
        pts = [(rng.uniform(0, w), rng.uniform(0.2, 0.8) * h) for _ in range(5)]
        cv.line(sorted(pts), h * 0.08)
        out = np.clip(cv.array() - cv2.array() * 0.9, 0, 1)
        fill = cv2.array()
        img = base * (1 - fill[..., None]) + c1 * 0.7 * fill[..., None]
        img = img * (1 - out[..., None]) + np.array([0.92, 0.92, 0.95]) * out[..., None]
        drip = smoothstep(0.5, 1.0, norm01(blur(blur_noise(h, w, 1, 310 + k), (8, 0.8), True))) * fill
        img = img * (1 - drip[..., None] * 0.3)
        wear = smoothstep(0.25, 0.45, norm01(blur_noise(h, w, 3, 320 + k) + blur_noise(h, w, 12, 330 + k)))
        img = base * (1 - wear[..., None]) + img * wear[..., None]
        at.put("graf%d" % k, rgba(img))
    # climatiseur : façade à grille ronde, ouïes latérales
    w, h, xx, yy = tile(0.9, 0.7, 120)
    img = np.ones((h, w, 3)) * srgb("#9aa0a8")
    cx, cy = 0.33, 0.35
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    fan = d < 0.27
    rings = np.abs(np.mod(d / 0.03, 1.0) - 0.5) < 0.2
    img = np.where(fan[..., None], np.where(rings[..., None], srgb("#c8ccd2"), srgb("#1a1b20")), img)
    img = np.where((d < 0.05)[..., None], srgb("#5a5e66"), img)
    louv = (xx > 0.68) & (xx < 0.85) & (np.mod(yy / 0.05, 1.0) < 0.4) & (yy > 0.1) & (yy < 0.6)
    img = np.where(louv[..., None], img * 0.4, img)
    rust = smoothstep(0.6, 0.95, norm01(blur_noise(h, w, 4, 40)) + yy * 0.4)
    img = img * (1 - rust[..., None] * 0.4) + srgb("#5a3826") * rust[..., None] * 0.4
    at.put("ac_front", rgba(img * 0.7))
    w, h, xx, yy = tile(0.5, 0.7, 120)
    img = np.ones((h, w, 3)) * srgb("#8a9098") * 0.7
    img = np.where((np.mod(yy / 0.04, 1.0) < 0.45)[..., None], img * 0.45, img)
    at.put("ac_side", rgba(img))
    # caillebotis de l'escalier de secours (0,5 m)
    w, h, xx, yy = tile(0.5, 0.5, 128)
    gx = np.abs(np.mod(xx / 0.05, 1.0) - 0.5) > 0.38
    gy = np.abs(np.mod(yy / 0.1, 1.0) - 0.5) > 0.4
    img = np.where((gx | gy)[..., None], srgb("#3a3a42"), srgb("#08080b"))
    rust = smoothstep(0.55, 0.9, norm01(blur_noise(h, w, 6, 41)))
    img = img * (1 - rust[..., None] * 0.5) + srgb("#4a2a1c") * rust[..., None] * 0.5 * (gx | gy)[..., None]
    at.put("grate", rgba(img))
    # tablier de la passerelle (tôle larmée, 1 m)
    w, h, xx, yy = tile(1.0, 1.0, 96)
    ph = np.mod(xx / 0.06 + np.floor(yy / 0.06) * 0.5, 1.0)
    bump = (np.abs(ph - 0.5) < 0.18) & (np.abs(np.mod(yy / 0.06, 1.0) - 0.5) < 0.12)
    img = np.ones((h, w, 3)) * srgb("#4a4d55") * np.where(bump[..., None], 1.3, 1.0)
    at.put("deck", rgba(img))
    # enseignes en drapeau : deux faces, idéogrammes empilés
    for (x, ya, yb, sp, cn, sd) in FAC.BLADES:
        hm = yb - ya
        w, h, xx, yy = tile(sp, hm, 64)
        c = COL[cn]
        img = np.ones((h, w, 3)) * srgb("#100c16")
        a = np.zeros((h, w))
        cv = Canvas(w, h, 3)
        n = max(2, int(hm / (sp * 0.95)))
        gh = min(sp * 0.68 * 64, h / n / 1.2)
        rng = np.random.default_rng(sd)
        glyph_text(cv, w * 0.5 - gh * 0.5, (h - n * gh * 1.18) * 0.5, gh, FAC.GLYPHS, list(rng.integers(0, 64, n)), vertical=True)
        gm = cv.array()
        brd = (xx < 0.04) | (xx > sp - 0.04) | (yy < 0.04) | (yy > hm - 0.04)
        img = np.where(brd[..., None], c, img)
        a = np.where(brd, 1.0, a)
        img = img * (1 - gm[..., None]) + (c * 0.7 + 0.3) * gm[..., None]
        a = np.maximum(a, gm)
        at.put("blade%d" % sd, rgba(img, a))
    # dessous de la passerelle et enseigne de la porte réutilisent la bande proche
    print("  régions :", len(at.reg))
    save_rgba(os.path.join(OUT, "neon_atlas.png"), at.img)
    return at


# ================================================================ géométrie
def near_uv(at, x, y):
    """UV de la bande proche au point (x, y) de la façade."""
    if x < FAC.NEAR_XM:
        name, xa, xb = "near_a", FAC.NEAR_X0, FAC.NEAR_XM
    else:
        name, xa, xb = "near_b", FAC.NEAR_XM, FAC.NEAR_X1
    u0, v0, u1, v1 = at.uv(name)
    fu = (x - xa) / (xb - xa)
    fv = (FAC.NEAR_Y1 - y) / (FAC.NEAR_Y1 - FAC.NEAR_Y0)
    return u0 + (u1 - u0) * fu, v0 + (v1 - v0) * fv


def near_rect_uv(at, xa, ya, xb, yb):
    ua, va = near_uv(at, xa + 1e-3, yb)
    ub, vb = near_uv(at, xb - 1e-3, ya)
    return (ua, va, ub, vb)


def build_parapets(mb, at, strips):
    conc = at.uv("conc")
    cop = at.uv("coping")
    dark = at.uv("dark")
    steel = at.uv("steel")
    white = at.uv("white")
    gaps = [(BRIDGE_X - BRIDGE_W * 0.5 - 0.05, BRIDGE_X + BRIDGE_W * 0.5 + 0.05)]
    # parapets : ouest, est, sud, nord (avec l'ouverture de la passerelle)
    segs = [("W", (0.0, 0.0, ZN), (PAR_T, PAR_H, H)), ("E", (W - PAR_T, 0.0, ZN), (W, PAR_H, H)),
            ("S", (PAR_T, 0.0, H - PAR_T), (W - PAR_T, PAR_H, H))]
    xa = PAR_T
    for (ga, gb) in gaps:
        segs.append(("N", (xa, 0.0, ZN), (ga, PAR_H, ZN + PAR_T)))
        xa = gb
    segs.append(("N", (xa, 0.0, ZN), (W - PAR_T, PAR_H, ZN + PAR_T)))
    for side, lo, hi in segs:
        mb.box(lo, hi, conc, ONE, PAINT, "xXzZ", tile=2.0)
        # couvertine (débord de 3 cm) avec goutte d'eau
        lo2 = (lo[0] - (0.03 if side != "E" else 0.03), PAR_H, lo[2] - 0.03)
        hi2 = (hi[0] + 0.03, PAR_H + 0.05, hi[2] + 0.03)
        mb.box(lo2, hi2, cop, (0.85, 0.87, 0.92), BARE, "xXyYzZ", tile=2.0)
    # bouts des ouvertures de la passerelle : poteaux et chaîne
    for (ga, gb) in gaps:
        for x in (ga - 0.04, gb + 0.04):
            mb.cyl((x, 0.0, ZN + PAR_T * 0.5), (x, 1.05, ZN + PAR_T * 0.5), 0.035, steel, srgb("#c9a640"), BARE, 8, caps=True)
        mb.tube(catenary((ga, 0.85, ZN + PAR_T * 0.5), (gb, 0.85, ZN + PAR_T * 0.5), 0.12, 8), 0.012, dark, srgb("#d0b040"), BARE, 4)
    # graffitis sur les faces intérieures
    gspots = [("W", 6.0, 0), ("W", 15.5, 2), ("E", 9.0, 1), ("E", 18.0, 3), ("S", 7.5, 1), ("S", 22.0, 0),
              ("S", 31.0, 2), ("N", 5.5, 3), ("N", 27.5, 1)]
    for side, p, k in gspots:
        uv = at.uv("graf%d" % k)
        y = 0.25
        if side == "W":
            mb.quad((PAR_T + 0.002, y, p), (0, 0, -1), (0, 1, 0), 1.5, 0.22, uv, ONE, PAINT)
        elif side == "E":
            mb.quad((W - PAR_T - 0.002, y, p), (0, 0, 1), (0, 1, 0), 1.5, 0.22, uv, ONE, PAINT)
        elif side == "S":
            mb.quad((p, y, H - PAR_T - 0.002), (1, 0, 0), (0, 1, 0), 1.5, 0.22, uv, ONE, PAINT)
        else:
            mb.quad((p, y, ZN + PAR_T + 0.002), (-1, 0, 0), (0, 1, 0), 1.5, 0.22, uv, ONE, PAINT, normal=(0, 0, 1))
    # tubes néon sous la couvertine (face intérieure) : les mêmes segments éclairent le sol (shell_meta.json)
    for (a, b, cn, ph) in strips:
        c = COL[cn]
        a, b = np.array(a), np.array(b)
        mb.cyl(a, b, 0.014, white, c * (0.35 if cn == "dead" else 1.0), GLOW, 6, anim=(A_BUZZ if ph > 0 else A_NONE, ph))
        # supports
        L = np.linalg.norm(b - a)
        for t in np.linspace(0.0, 1.0, max(2, int(L / 1.2) + 1)):
            p = a + (b - a) * t
            n = np.array([1.0 if p[0] < W * 0.5 else -1.0, 0.0, 0.0]) if abs(b[2] - a[2]) > 0.1 else np.array([0.0, 0.0, -1.0 if p[2] > H * 0.5 else 1.0])
            mb.box(p - n * 0.035 - (0.012, 0.012, 0.012), p - n * 0.0 + (0.012, 0.03, 0.012), dark, ONE, BARE, "xXyYzZ")


def build_rails(mb, at):
    steel = at.uv("steel")
    dark = at.uv("dark")
    rc = srgb("#9298a4")
    yt, ym = 1.05, 0.78
    runs = [((PAR_T * 0.4, ZN + 0.15), (PAR_T * 0.4, H - 0.15)), ((W - PAR_T * 0.4, ZN + 0.15), (W - PAR_T * 0.4, H - 0.15)),
            ((0.15, H - PAR_T * 0.4), (W - 0.15, H - PAR_T * 0.4))]
    ga, gb = BRIDGE_X - BRIDGE_W * 0.5 - 0.1, BRIDGE_X + BRIDGE_W * 0.5 + 0.1
    runs += [((0.15, ZN + PAR_T * 0.6), (ga, ZN + PAR_T * 0.6)), ((gb, ZN + PAR_T * 0.6), (W - 0.15, ZN + PAR_T * 0.6))]
    for (a, b) in runs:
        a3 = np.array([a[0], 0, a[1]])
        b3 = np.array([b[0], 0, b[1]])
        L = np.linalg.norm(b3 - a3)
        n = max(1, int(round(L / 1.8)))
        for i in range(n + 1):
            p = a3 + (b3 - a3) * i / n
            mb.cyl(p + (0, PAR_H + 0.05, 0), p + (0, yt, 0), 0.022, steel, rc, BARE, 6)
        for (y, r) in ((yt, 0.026), (ym, 0.014)):
            mb.cyl(a3 + (0, y, 0), b3 + (0, y, 0), r, steel, rc, BARE, 6)


def build_antennas(mb, at):
    steel = at.uv("steel")
    dark = at.uv("dark")
    white = at.uv("white")
    red = srgb("#ff2a3a")
    for (x, z, hgt, ph) in ((0.16, ZN + 0.16, 2.6, 0.1), (W - 0.16, ZN + 0.16, 2.2, 0.55), (0.16, H - 0.16, 1.9, 0.8), (W - 0.16, H - 0.16, 2.8, 0.3)):
        mb.box((x - 0.12, PAR_H + 0.05, z - 0.12), (x + 0.12, PAR_H + 0.09, z + 0.12), dark, ONE, BARE, "xXyYzZ")
        mb.cyl((x, PAR_H + 0.09, z), (x, PAR_H + hgt, z), 0.035, steel, srgb("#7a808c"), BARE, 6, r2=0.018)
        for k, y in enumerate(np.linspace(PAR_H + 0.6, PAR_H + hgt - 0.3, 3)):
            ln = 0.3 - k * 0.07
            mb.cyl((x - ln, y, z), (x + ln, y, z), 0.008, steel, srgb("#7a808c"), BARE, 4)
            mb.cyl((x, y, z - ln), (x, y, z + ln), 0.008, steel, srgb("#7a808c"), BARE, 4)
        mb.sphere((x, PAR_H + hgt + 0.04, z), 0.045, white, red, GLOW, 6, 4, anim=(A_BLINK, ph))
    # parabole au coin sud-est, haubans
    cx, cz = W - 0.2, H - 1.6
    mb.cyl((cx, PAR_H + 0.05, cz), (cx, PAR_H + 0.6, cz), 0.03, steel, srgb("#7a808c"), BARE, 6)
    c = np.array([cx - 0.15, PAR_H + 0.85, cz])
    nrm = np.array([-0.5, 0.75, 0.3])
    nrm /= np.linalg.norm(nrm)
    t = np.cross(nrm, (0, 1, 0))
    t /= np.linalg.norm(t)
    s = np.cross(nrm, t)
    for i in range(14):
        a0, a1 = 2 * math.pi * i / 14, 2 * math.pi * (i + 1) / 14
        p0 = c + (t * math.cos(a0) + s * math.sin(a0)) * 0.42
        p1 = c + (t * math.cos(a1) + s * math.sin(a1)) * 0.42
        mb.tri([c - nrm * 0.1, p0, p1], [nrm, nrm, nrm], [steel[:2]] * 3, srgb("#c9ccd2"), BARE)
    mb.cyl(c, c + nrm * 0.35, 0.012, steel, srgb("#7a808c"), BARE, 4)


def build_cables(mb, at):
    """Gaines électriques le long des parapets, câbles qui pendent entre les antennes et sur le vide."""
    dark = at.uv("dark")
    cols = [srgb("#1a1a20"), srgb("#2a2420"), srgb("#3a2a30")]
    # gaine posée au pied du parapet ouest et est (côté intérieur), colliers
    for x in (PAR_T + 0.05, W - PAR_T - 0.05):
        for (za, zb) in ((ZN + PAR_T + 0.3, 11.0), (11.6, H - PAR_T - 0.3)):
            mb.cyl((x, 0.05, za), (x, 0.05, zb), 0.035, dark, srgb("#2a2c33"), RUBBER, 6)
            for z in np.arange(za + 0.4, zb, 1.5):
                mb.box((x - 0.045, 0.0, z - 0.03), (x + 0.045, 0.09, z + 0.03), dark, ONE, BARE, "xXYzZ")
    # câbles en chaînette à l'extérieur (sur le vide), d'un poteau de rambarde à l'autre
    for x in (-0.05, W + 0.05):
        z = ZN + 0.3
        while z < H - 2.0:
            L = R.uniform(2.5, 4.5)
            mb.tube(catenary((x, 0.9, z), (x, 0.9, min(z + L, H - 0.3)), R.uniform(0.25, 0.6), 9), 0.012, dark, cols[int(R.integers(0, 3))], RUBBER, 4)
            z += L * R.uniform(0.6, 1.0)
    z = H + 0.05
    x = 0.4
    while x < W - 2.0:
        L = R.uniform(3.0, 5.0)
        mb.tube(catenary((x, 0.95, z), (min(x + L, W - 0.3), 0.95, z), R.uniform(0.3, 0.7), 9), 0.012, dark, cols[int(R.integers(0, 3))], RUBBER, 4)
        x += L * R.uniform(0.5, 0.9)


def build_tower_below(mb, at):
    """Notre tour sous le toit : bandeau de rive, ligne néon, puis la façade (carte) qui plonge."""
    dark = at.uv("dark")
    white = at.uv("white")
    for (a, b, n, axis) in (((0, 0, H), (W, 0, H), (0, 0, 1), "x"), ((0, 0, ZN), (0, 0, H), (-1, 0, 0), "z"),
                            ((W, 0, ZN), (W, 0, H), (1, 0, 0), "z"), ((0, 0, ZN), (W, 0, ZN), (0, 0, -1), "x")):
        a, b, n = np.array(a, float), np.array(b, float), np.array(n, float)
        c = (a + b) * 0.5
        L = np.linalg.norm(b - a)
        r = (b - a) / L
        # bandeau sombre (sous la couvertine), ligne néon violette, puis façade
        mb.quad(c + n * 0.0 + (0, -0.35, 0), r, (0, 1, 0), L * 0.5, 0.35, dark, ONE, PAINT, normal=n)
        mb.quad(c + n * 0.03 + (0, -0.6, 0), r, (0, 1, 0), L * 0.5, 0.025, white, VIOLET * 0.9, GLOW, normal=n, anim=(A_BUZZ, 0.37))
        mb.quad(c + n * 0.01 + (0, -0.66, 0), r, (0, 1, 0), L * 0.5, 0.04, dark, ONE, BARE, normal=n)
        # façade (carte de la tour voisine, décalée) jusqu'à 40 m plus bas
        n_seg = max(1, int(L / 6.0))
        for i in range(n_seg):
            ca = a + (b - a) * (i + 0.5) / n_seg
            mb.quad(ca + (0, -20.7, 0), r, (0, 1, 0), L * 0.5 / n_seg, 20.0, (0, 0, 1, 1), (0.8, 0.8, 0.9), PAINT, normal=n,
                    anim=(A_MAP, 0.5 if axis == "z" else 0.25))


def build_facade(mb, at):
    """Tour voisine : mur (bande proche nette + carte), caissons d'écrans et d'enseignes, drapeaux, climatiseurs,
    descentes d'eau, escalier de secours, passerelle, porte, guirlandes de lanternes."""
    dark = at.uv("dark")
    steel = at.uv("steel")
    white = at.uv("white")
    black = at.uv("black")
    nz = (0, 0, 1)
    # mur : bande proche (deux quads), carte au-dessus et en dessous
    for (xa, xb, name) in ((FAC.NEAR_X0, FAC.NEAR_XM, "near_a"), (FAC.NEAR_XM, FAC.NEAR_X1, "near_b")):
        mb.quad(((xa + xb) * 0.5, (FAC.NEAR_Y0 + FAC.NEAR_Y1) * 0.5, ZF), (1, 0, 0), (0, 1, 0), (xb - xa) * 0.5,
                (FAC.NEAR_Y1 - FAC.NEAR_Y0) * 0.5, at.uv(name), ONE, PAINT, normal=nz)
    for (ya, yb) in ((FAC.NEAR_Y1, ROOF_Y + 0.6), (-40.0, FAC.NEAR_Y0)):
        for (xa, xb) in ((FX0 - 6, FAC.NEAR_X0), (FAC.NEAR_X0, FAC.NEAR_X1), (FAC.NEAR_X1, FX1 + 6)):
            mb.quad(((xa + xb) * 0.5, (ya + yb) * 0.5, ZF), (1, 0, 0), (0, 1, 0), (xb - xa) * 0.5, (yb - ya) * 0.5,
                    (0, 0, 1, 1), ONE, PAINT, normal=nz, anim=(A_MAP, 0.0))
    mb.quad(((TOWER_X0 + TOWER_X1) * 0.5, (ROOF_Y + TOWER_Y) * 0.5 + 0.6, ZF), (1, 0, 0), (0, 1, 0), (TOWER_X1 - TOWER_X0) * 0.5,
            (TOWER_Y - ROOF_Y) * 0.5, (0, 0, 1, 1), ONE, PAINT, normal=nz, anim=(A_MAP, 0.0))
    for (xa, xb) in ((FX0 - 6, FAC.NEAR_X0), (FAC.NEAR_X1, FX1 + 6)):
        mb.quad(((xa + xb) * 0.5, (FAC.NEAR_Y0 + FAC.NEAR_Y1) * 0.5, ZF), (1, 0, 0), (0, 1, 0), (xb - xa) * 0.5,
                (FAC.NEAR_Y1 - FAC.NEAR_Y0) * 0.5, (0, 0, 1, 1), ONE, PAINT, normal=nz, anim=(A_MAP, 0.0))
    # écrans géants : caisson, cadre, dalle animée
    for i, (xa, ya, xb, yb, mo, sd, br) in enumerate(FAC.SCREENS):
        if yb > FAC.NEAR_Y1 + 0.5:
            continue
        d = 0.32
        mb.box((xa - 0.15, ya - 0.15, ZF), (xb + 0.15, yb + 0.15, ZF + d), dark, srgb("#2a2a34"), BARE, "xXyYZ" if False else "xXyY")
        fr = 0.15
        for (lo, hi) in (((xa - fr, ya - fr), (xb + fr, ya)), ((xa - fr, yb), (xb + fr, yb + fr)), ((xa - fr, ya), (xa, yb)), ((xb, ya), (xb + fr, yb))):
            mb.box((lo[0], lo[1], ZF + d - 0.02), (hi[0], hi[1], ZF + d + 0.03), dark, srgb("#3a3a46"), BARE, "xXyYZ")
        mb.quad(((xa + xb) * 0.5, (ya + yb) * 0.5, ZF + d), (1, 0, 0), (0, 1, 0), (xb - xa) * 0.5, (yb - ya) * 0.5,
                (0, 0, 1, 1), ONE, GLOW, normal=nz, anim=(A_SCREEN, i * 0.25 + 0.01))
        # projecteurs sur le haut du caisson
        for x in np.linspace(xa + 0.6, xb - 0.6, max(2, int((xb - xa) / 2.5))):
            mb.box((x - 0.07, yb + 0.15, ZF + d - 0.05), (x + 0.07, yb + 0.25, ZF + d + 0.18), dark, ONE, BARE, "xXyYzZ")
    # enseignes à plat : caisson de 12 cm, face avant = bande proche (même dessin), grésillement
    for k, (xa, ya, xb, yb, cn, n, sd, an) in enumerate(FAC.BOARDS):
        if ya > FAC.NEAR_Y1 or yb < FAC.NEAR_Y0 or xa < FAC.NEAR_X0 or xb > FAC.NEAR_X1:
            continue
        d = 0.12
        mb.box((xa, ya, ZF), (xb, yb, ZF + d), dark, srgb("#1a1720"), BARE, "xXyY")
        anim = (A_BUZZ, 0.13 + k * 0.17) if an == 1 else ((A_BLINK, 0.21 + k * 0.11) if an == 2 else (A_NONE, 0.0))
        mb.quad(((xa + xb) * 0.5, (ya + yb) * 0.5, ZF + d), (1, 0, 0), (0, 1, 0), (xb - xa) * 0.5, (yb - ya) * 0.5,
                near_rect_uv(at, xa, ya, xb, yb), ONE, PAINT, normal=nz, anim=anim)
    # enseignes en drapeau
    for (x, ya, yb, sp, cn, sd) in FAC.BLADES:
        if ya > FAC.NEAR_Y1:
            continue
        t = 0.07
        uv = at.uv("blade%d" % sd)
        c = COL[cn]
        z0, z1 = ZF + 0.25, ZF + 0.25 + sp
        zc, ym = (z0 + z1) * 0.5, (ya + yb) * 0.5
        mb.quad((x - t, ym, zc), (0, 0, 1), (0, 1, 0), sp * 0.5, (yb - ya) * 0.5, uv, ONE, PAINT, normal=(-1, 0, 0), anim=(A_BUZZ, sd * 0.07))
        u0, v0, u1, v1 = uv
        mb.quad((x + t, ym, zc), (0, 0, -1), (0, 1, 0), sp * 0.5, (yb - ya) * 0.5, (u1, v0, u0, v1), ONE, PAINT, normal=(1, 0, 0), anim=(A_BUZZ, sd * 0.07))
        mb.box((x - t, ya, z1), (x + t, yb, z1 + 0.03), white, c, GLOW, "XxZ", anim=(A_BUZZ, sd * 0.07))
        mb.box((x - t, yb, z0), (x + t, yb + 0.03, z1), dark, ONE, BARE, "Yxx")
        for y in (ya + 0.4, yb - 0.4):
            mb.cyl((x, y, ZF), (x, y, z0), 0.025, steel, srgb("#55585f"), BARE, 6)
    # climatiseurs sur les bandeaux, descentes d'eau
    acs = [(-1.8, -2.3), (0.4, 1.0), (7.6, -2.3), (12.95, 1.0), (24.0, 1.0), (29.6, -2.3), (35.6, 1.0), (38.6, -2.3), (5.2, -5.7), (31.4, -5.7)]
    for (x, y) in acs:
        z1 = ZF + 0.55
        mb.box((x - 0.45, y, ZF + 0.05), (x + 0.45, y + 0.7, z1), at.uv("ac_side"), (0.9, 0.9, 0.95), BARE, "xXyY",
               uvs={"Y": at.uv("steel"), "y": at.uv("dark")})
        mb.quad((x, y + 0.35, z1), (1, 0, 0), (0, 1, 0), 0.45, 0.35, at.uv("ac_front"), ONE, BARE, normal=nz)
        for dx in (-0.3, 0.3):
            mb.box((x + dx - 0.03, y - 0.08, ZF), (x + dx + 0.03, y, z1), dark, ONE, BARE, "xXyYZ")
        # condensats : petit tuyau qui descend
        mb.cyl((x + 0.38, y, z1 - 0.1), (x + 0.38, y - 1.4, z1 - 0.1), 0.012, dark, srgb("#2a2c33"), RUBBER, 4)
    for x in (-0.6, 8.2, 25.6, 32.2, 39.4):
        mb.cyl((x, -12.0, ZF + 0.12), (x, ROOF_Y, ZF + 0.12), 0.06, steel, srgb("#4c4f58"), BARE, 6)
        for y in np.arange(-5.0, 4.0, 1.7):
            mb.box((x - 0.07, y, ZF), (x + 0.07, y + 0.05, ZF + 0.16), dark, ONE, BARE, "xXyYZ")
    build_fire_escape(mb, at)
    build_bridge(mb, at)
    build_lanterns(mb, at)


def build_fire_escape(mb, at):
    xa, xb = FAC.FIRE_ESC
    gr = at.uv("grate")
    dark = at.uv("dark")
    col = srgb("#5a4a48")
    dep = 1.15
    levels = [FLOOR_Y0 + k * FLOOR_H + 0.375 for k in (-3, -2, -1, 0, 1)]
    for i, y in enumerate(levels):
        # palier en caillebotis, garde-corps
        mb.box((xa, y - 0.05, ZF), (xb, y, ZF + dep), gr, ONE, BARE, "yYxXZ", tile=0.5)
        for (p, q) in (((xa, ZF + dep), (xb, ZF + dep)), ((xa, ZF), (xa, ZF + dep)), ((xb, ZF), (xb, ZF + dep))):
            mb.cyl((p[0], y + 0.95, p[1]), (q[0], y + 0.95, q[1]), 0.02, dark, col, BARE, 5)
            mb.cyl((p[0], y + 0.5, p[1]), (q[0], y + 0.5, q[1]), 0.012, dark, col, BARE, 4)
        for x in np.linspace(xa, xb, 4):
            mb.cyl((x, y, ZF + dep), (x, y + 0.95, ZF + dep), 0.016, dark, col, BARE, 4)
        # volée vers le palier du dessus : limons et marches
        if i < len(levels) - 1:
            y2 = levels[i + 1]
            left = i % 2 == 0
            sx0, sx1 = (xa + 0.15, xb - 0.6) if left else (xb - 0.15, xa + 0.6)
            zc = ZF + dep * 0.5
            n = 14
            for k in range(n):
                t0 = k / n
                x = sx0 + (sx1 - sx0) * t0
                yy = y + (y2 - y) * t0
                mb.box((min(x, x + (sx1 - sx0) / n) - 0.01, yy, zc - 0.42), (max(x, x + (sx1 - sx0) / n) + 0.01, yy + 0.04, zc + 0.42), gr, ONE, BARE, "yYxXzZ")
            for dz in (-0.45, 0.45):
                mb.cyl((sx0, y + 0.02, zc + dz), (sx1, y2 + 0.02, zc + dz), 0.03, dark, col, BARE, 5)
                mb.cyl((sx0, y + 0.9, zc + dz), (sx1, y2 + 0.9, zc + dz), 0.015, dark, col, BARE, 4)


def build_bridge(mb, at):
    """Passerelle du toit à la porte de la tour voisine, tablier en tôle, garde-corps, lumière dessous."""
    x0, x1 = BRIDGE_X - BRIDGE_W * 0.5, BRIDGE_X + BRIDGE_W * 0.5
    deck = at.uv("deck")
    dark = at.uv("dark")
    steel = at.uv("steel")
    white = at.uv("white")
    za, zb = ZF, ZN + PAR_T
    mb.box((x0, -0.06, za), (x1, 0.0, zb), deck, ONE, BARE, "Y", tile=1.0)
    mb.box((x0, -0.3, za), (x1, -0.06, zb), dark, ONE, BARE, "xXy")
    # poutres sous le tablier, lumière acide sur la tranche
    for x in (x0 + 0.05, x1 - 0.05):
        mb.box((x - 0.04, -0.34, za), (x + 0.04, -0.06, zb), dark, ONE, BARE, "xXy")
        mb.box((x - 0.045 if x < BRIDGE_X else x + 0.04, -0.2, za + 0.1), (x - 0.04 if x < BRIDGE_X else x + 0.045, -0.17, zb - 0.1),
               white, ACID * 0.8, GLOW, "xX", anim=(A_BUZZ, 0.61))
    # garde-corps
    for x in (x0, x1):
        for z in np.linspace(za + 0.1, zb - 0.1, 4):
            mb.cyl((x, 0.0, z), (x, 1.0, z), 0.02, steel, srgb("#9298a4"), BARE, 5)
        mb.cyl((x, 1.0, za), (x, 1.0, zb), 0.025, steel, srgb("#9298a4"), BARE, 6)
        mb.cyl((x, 0.55, za), (x, 0.55, zb), 0.012, steel, srgb("#9298a4"), BARE, 4)
    # auvent au-dessus de la porte
    mb.box((x0 - 0.2, 2.35 + 0.6, ZF), (x1 + 0.2, 2.45 + 0.6, ZF + 0.9), dark, srgb("#33303a"), BARE, "xXyYZ")
    mb.box((x0 - 0.2, 2.33 + 0.6, ZF + 0.85), (x1 + 0.2, 2.36 + 0.6, ZF + 0.9), white, PINK, GLOW, "yZ", anim=(A_BUZZ, 0.83))


def build_lanterns(mb, at):
    """Guirlandes de lanternes tendues au-dessus du vide, entre la tour voisine et le parapet nord."""
    dark = at.uv("dark")
    white = at.uv("white")
    lcols = [PINK, ORANGE, PINK, VIOLET * 0.6 + PINK * 0.4]
    runs = [((4.0, 3.2, ZF + 0.1), (6.4, 1.6, ZN + 0.1)), ((15.0, 3.0, ZF + 0.1), (12.8, 1.5, ZN + 0.1)),
            ((24.5, 3.1, ZF + 0.1), (27.0, 1.6, ZN + 0.1)), ((36.4, 3.0, ZF + 0.1), (36.8, 1.4, ZN + 0.1))]
    for k, (a, b) in enumerate(runs):
        pts = catenary(a, b, 0.55, 12)
        mb.tube(pts, 0.008, dark, srgb("#15151a"), RUBBER, 4)
        for i, p in enumerate(pts[1:-1:2]):
            c = lcols[(i + k) % len(lcols)]
            mb.cyl(p, p - np.array([0, 0.06, 0]), 0.004, dark, ONE, BARE, 3)
            mb.sphere(p - np.array([0, 0.17, 0]), 0.1, white, c * 0.9, GLOW, 8, 5, anim=(A_BUZZ, 0.05 + 0.13 * i + k * 0.3), sy=1.25)


def strips_list():
    """Tubes néon des parapets : (a, b, couleur, phase de grésillement) ; « dead » = tube éteint."""
    y = PAR_H - 0.06
    o = 0.03
    out = []
    # ouest (rose) : trois tronçons, un qui grésille
    xw = PAR_T + o
    for (za, zb, ph, c) in ((ZN + 0.9, 9.4, 0.0, "pink"), (9.9, 15.6, 0.41, "pink"), (16.1, H - 0.8, 0.0, "pink")):
        out.append(((xw, y, za), (xw, y, zb), c, ph))
    xe = W - PAR_T - o
    for (za, zb, ph, c) in ((ZN + 0.9, 8.2, 0.0, "blue"), (8.7, 14.3, 0.0, "blue"), (14.8, H - 0.8, 0.73, "blue")):
        out.append(((xe, y, za), (xe, y, zb), c, ph))
    zs = H - PAR_T - o
    for (xa, xb, ph, c) in ((1.2, 18.2, 0.0, "violet"), (19.3, W - 1.2, 0.27, "violet")):
        out.append(((xa, y, zs), (xb, y, zs), c, ph))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    at = make_atlas()
    print("carte de la façade")
    FAC.facade_map(os.path.join(OUT, "neon_facade.png"))
    print("géométrie")
    mb = MB()
    strips = strips_list()
    build_parapets(mb, at, strips)
    n_par = mb.count()
    build_rails(mb, at)
    build_antennas(mb, at)
    build_cables(mb, at)
    n_edge = mb.count()
    mf = MB()
    build_tower_below(mf, at)
    build_facade(mf, at)
    print("  triangles : parapets %d, bords %d, façades %d" % (n_par, n_edge, mf.count()))
    write_glb(os.path.join(OUT, "shell_edges.glb"), [("edges", mb.arrays()), ("facade", mf.arrays())])
    gu = at.uv("glyphs")
    write_json(os.path.join(OUT, "shell_meta.json"), {
        "glyph_rect": [float(gu[0]), float(gu[1]), float(gu[2] - gu[0]), float(gu[3] - gu[1])],
        "screens": [[s[0], s[1], s[2], s[3], s[4], s[5], s[6]] for s in FAC.SCREENS],
        "strips": [[[float(v) for v in a], [float(v) for v in b], [float(v) for v in COL[c]], ph] for (a, b, c, ph) in strips],
        "facade_rect": [FX0, FY0, FX1 - FX0, FY1 - FY0],
        "facade_z": ZF,
        "near": [FAC.NEAR_X0, FAC.NEAR_X1, FAC.NEAR_Y0, FAC.NEAR_Y1],
    })


if __name__ == "__main__":
    main()
