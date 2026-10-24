"""Cité Néon — façade de la tour voisine (au nord du toit) : plan des enseignes, peinture à toute résolution.

Une seule description (FACADE) sert à deux images :
  - la bande proche, vue directement (84 px/m, dans neon_atlas.png, deux bandes de 21,75 m) ;
  - la carte de la façade entière pour les reflets (neon_facade.png, 2048 x 1024 pour 48 x 24 m) :
    RGB émission (sRGB), A couverture (0 = ciel au-dessus du toit voisin).
Les écrans géants sont dessinés par le shader (neon_screen.gdshaderinc) ; ici, seulement leur teinte moyenne.
"""
import math

import numpy as np
from PIL import Image

from neon_shell_common import (ACID, BLUE, FLOOR_H, FLOOR_Y0, FX0, FX1, FY0, FY1, ORANGE, PINK, ROOF_Y, TOWER_X0,
                               TOWER_X1, TOWER_Y, VIOLET, W,
                               Canvas, blur, blur_noise, draw_glyphs, glyph_text, norm01, smoothstep, srgb)

GLYPHS = draw_glyphs(64)

# bande proche (vue directe)
NEAR_X0, NEAR_XM, NEAR_X1 = -3.0, 18.75, 40.5
NEAR_Y0, NEAR_Y1 = -5.6, 3.2
NEAR_PPM = 84

# écrans : x0, y0, x1, y1, mode (0 publicité, 1 colonne), graine, luminosité
SCREENS = [
    (14.5, -2.6, 23.5, 2.4, 0, 1.0, 1.0),
    (26.0, -4.5, 27.6, 3.0, 1, 4.0, 0.9),
    (1.5, 5.0, 10.5, 10.0, 0, 7.0, 0.9),
    (12.0, 18.0, 26.0, 26.0, 0, 2.5, 0.85),
]
# enseignes à plat : x0, y0, x1, y1, couleur, idéogrammes (nombre), graine, animation (0 fixe, 1 grésille, 2 clignote)
BOARDS = [
    (3.2, 1.45, 9.0, 2.75, "pink", 5, 11, 1),
    (28.4, -1.45, 32.6, -0.25, "blue", 4, 12, 0),
    (12.95, -1.7, 14.15, 0.3, "acid", 2, 13, 2),
    (36.3, -3.2, 37.1, 0.2, "orange", 3, 14, 1),
    (33.2, 2.3, 34.6, 2.85, "pink", 2, 15, 2),
    (-2.6, -1.3, 0.6, -0.3, "violet", 3, 16, 0),
    (16.0, 5.2, 22.0, 6.5, "blue", 5, 17, 0),
    (34.0, 9.0, 39.5, 10.2, "acid", 4, 18, 1),
    (-4.5, 6.0, 0.5, 7.2, "orange", 4, 19, 0),
    (38.5, 4.6, 42.0, 5.6, "pink", 3, 20, 2),
]
# enseignes en drapeau (perpendiculaires à la façade) : x, y0, y1, saillie, couleur, graine
BLADES = [
    (1.8, -3.6, 2.6, 0.85, "orange", 21),
    (24.6, -4.0, 2.2, 0.95, "violet", 22),
    (13.5, 3.8, 11.5, 1.1, "pink", 23),
    (28.4, 15.0, 31.0, 1.2, "acid", 25),
    (40.2, -4.5, 2.4, 0.8, "blue", 24),
]
# grande enseigne sur le toit voisin : idéogrammes alternés rose / bleu
ROOF_SIGN = (7.0, 13.5, 31.0, 15.6)
# couronne de la tour
CROWN = (11.0, TOWER_Y + 0.8, 27.0, TOWER_Y + 3.6)
# porte de la passerelle, escalier de secours
DOOR = (33.25, -0.05, 34.55, 2.2)
FIRE_ESC = (9.6, 12.8)

COL = {"pink": PINK, "blue": BLUE, "violet": VIOLET, "acid": ACID, "orange": ORANGE}

CONC = srgb("#26232e")
CONC_D = srgb("#16141c")
FRAME = srgb("#1d1c24")


def floors():
    """Niveaux des bandeaux (centre) entre FY0 et le toit."""
    out = []
    k = -6
    while True:
        y = FLOOR_Y0 + k * FLOOR_H
        if y > TOWER_Y - 1.0:
            break
        if y > FY0 - FLOOR_H:
            out.append(y)
        k += 1
    return out


def window_state(bx, fl):
    """État d'une fenêtre (travée, étage), stable : 0 sombre, 1 chaude, 2 bureau froid, 3 néon intérieur, 4 rideau."""
    h = math.sin(bx * 12.9898 + fl * 78.233) * 43758.5453
    u = h - math.floor(h)
    return 0 if u < 0.32 else (1 if u < 0.62 else (2 if u < 0.76 else (3 if u < 0.86 else 4)))


def paint(ppm, x0, x1, y0, y1, ss=2):
    """Peint la façade sur [x0, x1] x [y0, y1] à ppm px/m. Rend (albédo RGB, masque d'émission, couverture)."""
    w = int(round((x1 - x0) * ppm))
    h = int(round((y1 - y0) * ppm))
    jj, ii = np.mgrid[0:h, 0:w].astype(np.float32)
    X = x0 + (ii + 0.5) / ppm
    Y = y1 - (jj + 0.5) / ppm
    seed = int(ppm * 7 + x0 * 3)
    nz = blur_noise(h, w, max(1.0, ppm * 0.4), seed) * 0.5 + blur_noise(h, w, max(1.0, ppm * 2.5), seed + 1) * 0.5
    alb = np.ones((h, w, 3), np.float32) * CONC * (0.85 + 0.12 * nz[..., None])
    em = np.zeros((h, w), np.float32)
    cover = ((Y < ROOF_Y + 0.6) | ((X > TOWER_X0) & (X < TOWER_X1) & (Y < TOWER_Y + 0.6))).astype(np.float32)
    tower = (X > TOWER_X0) & (X < TOWER_X1)

    def px(x):
        return (x - x0) * ppm

    def py(y):
        return (y1 - y) * ppm

    def rect(xa, ya, xb, yb):
        return (X >= xa) & (X < xb) & (Y >= ya) & (Y < yb)

    # joints des panneaux de béton (verticaux tous les 4,8 m)
    vj = np.abs(np.mod(X + 1.2, 4.8) - 2.4) > 2.39
    alb = np.where(vj[..., None], CONC_D, alb)
    # coulures de pluie : traînées verticales sombres et claires
    streak = blur_noise(h, w, 1, seed + 2)
    streak = blur(streak, (max(1.0, ppm * 0.9), max(0.5, ppm * 0.02)))
    streak = streak / (streak.std() + 1e-6)
    alb *= (1.0 + np.clip(streak, -2, 2)[..., None] * 0.07)
    fl_list = floors()
    # fenêtres
    for fi, fy in enumerate(fl_list):
        wy0, wy1 = fy + 0.375 + 0.25, fy + FLOOR_H - 0.375 - 0.2
        if wy0 > y1 or wy1 < y0 or wy1 > TOWER_Y:
            continue
        up = wy1 > ROOF_Y
        for bi in range(int(math.floor((x0 - 1.2) / 2.4)) - 1, int(math.ceil((x1 + 1.2) / 2.4)) + 1):
            bx = bi * 2.4 + 1.2
            xa, xb = bx - 1.0, bx + 1.0
            if xb < x0 or xa > x1 or (up and (xa < TOWER_X0 + 0.2 or xb > TOWER_X1 - 0.2)):
                continue
            m = rect(xa, wy0, xb, wy1)
            if not m.any():
                continue
            st = window_state(bi, fi)
            u = (X - xa) / 2.0
            v = (Y - wy0) / (wy1 - wy0)
            if st == 0:
                c = srgb("#0c0d16") * (0.7 + 0.6 * v[..., None]) + srgb("#2a1a40") * 0.25 * (1 - v[..., None])
                e = 0.0 * u
            elif st == 1:
                c = srgb("#ffb46a") * (0.55 + 0.45 * v[..., None])
                blinds = (np.mod(Y / 0.07, 1.0) < 0.45) & (v > 0.55 - 0.3 * math.sin(bi * 3.1 + fi))
                c = np.where(blinds[..., None], c * 0.45, c)
                e = 0.55 + 0.25 * v
            elif st == 2:
                c = srgb("#a9c8ff") * (0.5 + 0.3 * v[..., None])
                bar = np.abs(v - 0.86) < 0.04
                c = np.where(bar[..., None], srgb("#e8f2ff"), c)
                e = 0.45 + 0.4 * bar
            elif st == 3:
                cc = COL["pink"] if (bi + fi) % 2 else COL["violet"]
                c = cc * (0.35 + 0.65 * (1 - np.abs(u - 0.5) * 1.6)[..., None])
                e = 0.7 + 0.0 * u
            else:
                fold = 0.6 + 0.4 * np.sin(u * 40.0)
                c = srgb("#d88a5a") * fold[..., None] * 0.7
                e = 0.32 + 0.0 * u
            # silhouettes (meubles, plantes) dans les fenêtres allumées
            if st in (1, 2, 4) and (bi * 7 + fi) % 3 == 0:
                sil = (np.abs(u - 0.3) < 0.12) & (v < 0.45)
                plant = ((u - 0.75) ** 2 * 4 + (v - 0.35) ** 2 * 6) < 0.05
                c = np.where((sil | plant)[..., None], c * 0.18, c)
            alb = np.where(m[..., None], c, alb)
            em = np.where(m, e, em)
            # cadre et meneau
            fr = m & ((np.abs(u - 0.5) < 0.012) | (u < 0.025) | (u > 0.975) | (v < 0.03) | (v > 0.97))
            alb = np.where(fr[..., None], FRAME, alb)
            em = np.where(fr, 0.0, em)
            # appui de fenêtre et coulure en dessous
            sill = (X > xa - 0.06) & (X < xb + 0.06) & (Y > wy0 - 0.06) & (Y < wy0)
            alb = np.where(sill[..., None], srgb("#3a3742"), alb)
            drip = (X > xa) & (X < xb) & (Y < wy0 - 0.06) & (Y > wy0 - 1.2)
            dk = smoothstep(wy0 - 1.2, wy0 - 0.06, Y) * (0.5 + 0.5 * norm01(np.sin(X * 23.0) + nz))
            alb = np.where(drip[..., None], alb * (1 - dk[..., None] * 0.35), alb)
    # bandeaux d'étage : béton plus clair, larmier sombre, ligne de LED bleue sous certains
    for fi, fy in enumerate(fl_list):
        xl, xr = (TOWER_X0, TOWER_X1) if fy > ROOF_Y else (-1e3, 1e3)
        m = rect(xl, fy - 0.375, xr, fy + 0.375)
        alb = np.where(m[..., None], srgb("#2e2b36") * (0.9 + 0.12 * nz[..., None]), alb)
        lip = rect(xl, fy - 0.375, xr, fy - 0.33)
        alb = np.where(lip[..., None], srgb("#0d0c12"), alb)
        if fi % 3 == 1:
            led = rect(xl, fy - 0.33, xr, fy - 0.305)
            alb = np.where(led[..., None], BLUE * 0.9, alb)
            em = np.where(led, 1.0, em)
    # toit voisin : acrotère, puis ciel
    m = rect(-1e3, ROOF_Y, 1e3, ROOF_Y + 0.6)
    alb = np.where(m[..., None], srgb("#1e1c26"), alb)
    em = np.where(m, 0.0, em)
    # halos des enseignes sur le béton (dessinés avant les enseignes)
    halo = np.zeros((h, w, 3), np.float32)
    for (xa, ya, xb, yb, cn, n, sd, an) in BOARDS:
        cx, cy = (xa + xb) * 0.5, (ya + yb) * 0.5
        rx, ry = (xb - xa) * 0.5 + 0.9, (yb - ya) * 0.5 + 0.9
        dd = np.maximum(np.abs(X - cx) - (xb - xa) * 0.5, 0) ** 2 + np.maximum(np.abs(Y - cy) - (yb - ya) * 0.5, 0) ** 2
        halo += COL[cn][None, None, :] * np.exp(-dd / 0.5)[..., None] * 0.35
    for (x, ya, yb, sp, cn, sd) in BLADES:
        dd = (X - x) ** 2 + np.maximum(np.abs(Y - (ya + yb) * 0.5) - (yb - ya) * 0.5, 0) ** 2
        halo += COL[cn][None, None, :] * np.exp(-dd / 0.6)[..., None] * 0.45
    for (xa, ya, xb, yb, mo, sd, br) in SCREENS:
        dd = np.maximum(np.abs(X - (xa + xb) * 0.5) - (xb - xa) * 0.5, 0) ** 2 + np.maximum(np.abs(Y - (ya + yb) * 0.5) - (yb - ya) * 0.5, 0) ** 2
        halo += (VIOLET * 0.6 + PINK * 0.4)[None, None, :] * np.exp(-dd / 1.2)[..., None] * 0.3
    hl = np.clip(halo.max(-1), 0, 1)
    alb = alb + halo * 0.35
    em = np.maximum(em, hl * 0.45 * (1 - (em > 0.3)))
    # enseignes à plat : caisson sombre, tube au pourtour, idéogrammes lumineux
    for (xa, ya, xb, yb, cn, n, sd, an) in BOARDS:
        m = rect(xa, ya, xb, yb)
        if not m.any():
            continue
        c = COL[cn]
        alb = np.where(m[..., None], srgb("#120e18"), alb)
        em = np.where(m, 0.0, em)
        bw = 0.05
        brd = m & ~rect(xa + bw, ya + bw, xb - bw, yb - bw)
        alb = np.where(brd[..., None], c, alb)
        em = np.where(brd, 1.0, em)
        cv = Canvas(w, h, ss)
        gh = (yb - ya) * 0.62 * ppm
        rng = np.random.default_rng(sd)
        ids = list(rng.integers(0, 64, n))
        vert = (yb - ya) > (xb - xa) * 1.2
        if vert:
            gh = (xb - xa) * 0.7 * ppm
            tot = n * gh * 1.18
            glyph_text(cv, px((xa + xb) * 0.5) - gh * 0.5, py((ya + yb) * 0.5) - tot * 0.5, gh, GLYPHS, ids, vertical=True)
        else:
            tot = n * gh * 1.18
            glyph_text(cv, px((xa + xb) * 0.5) - tot * 0.5 + gh * 0.09, py((ya + yb) * 0.5) - gh * 0.5, gh, GLYPHS, ids)
        g = cv.array()
        core = np.clip(g * 1.0, 0, 1)
        alb = alb * (1 - core[..., None]) + (c * 0.6 + 0.4)[None, None, :] * core[..., None] * 0.6 + c[None, None, :] * core[..., None] * 0.4
        em = np.maximum(em, core)
    # écrans : caisson et teinte moyenne (le shader dessine le contenu)
    for (xa, ya, xb, yb, mo, sd, br) in SCREENS:
        m = rect(xa - 0.15, ya - 0.15, xb + 0.15, yb + 0.15)
        alb = np.where(m[..., None], srgb("#0e0d14"), alb)
        em = np.where(m, 0.0, em)
        s = rect(xa, ya, xb, yb)
        tint = (VIOLET * 0.5 + PINK * 0.3 + BLUE * 0.2)
        u = (X - xa) / (xb - xa)
        alb = np.where(s[..., None], tint * (0.4 + 0.3 * np.sin(u * 9.0 + sd)[..., None]), alb)
        em = np.where(s, 0.8 * br, em)
    # enseignes en drapeau : tranche lumineuse (vue de face)
    for (x, ya, yb, sp, cn, sd) in BLADES:
        m = rect(x - 0.06, ya, x + 0.06, yb)
        alb = np.where(m[..., None], COL[cn], alb)
        em = np.where(m, 1.0, em)
    # grande enseigne du toit voisin : échafaudage et idéogrammes
    xa, ya, xb, yb = ROOF_SIGN
    sc = rect(xa, ROOF_Y + 0.6, xb, ya + 0.15)
    pole = sc & (np.abs(np.mod(X - xa, 2.0) - 1.0) > 0.94)
    alb = np.where(pole[..., None], srgb("#1a1820"), alb)
    cover = np.where(pole, 1.0, cover)
    n = 8
    gh = (yb - ya)
    cv = Canvas(w, h, ss)
    cv2 = Canvas(w, h, ss)
    step = (xb - xa) / n
    rng = np.random.default_rng(31)
    for k in range(n):
        gx = xa + k * step + (step - gh) * 0.5
        glyph_text(cv if k % 2 == 0 else cv2, px(gx), py(yb), gh * ppm, GLYPHS, [int(rng.integers(0, 64))], width=0.1)
    g1, g2 = cv.array(), cv2.array()
    for g, c in ((g1, PINK), (g2, BLUE)):
        alb = alb * (1 - g[..., None]) + c[None, None, :] * g[..., None]
        em = np.maximum(em, g)
        cover = np.maximum(cover, g)
    # tour : arêtes lumineuses, couronne d'idéogrammes
    for xe in (TOWER_X0, TOWER_X1):
        m = rect(xe - 0.08, ROOF_Y + 0.6, xe + 0.08, TOWER_Y + 0.6)
        alb = np.where(m[..., None], VIOLET, alb)
        em = np.where(m, 1.0, em)
    m = rect(TOWER_X0, TOWER_Y, TOWER_X1, TOWER_Y + 0.6)
    alb = np.where(m[..., None], srgb("#1e1c26"), alb)
    xa, ya, xb, yb = CROWN
    n = 6
    gh = (yb - ya)
    cv = Canvas(w, h, ss)
    step = (xb - xa) / n
    rng = np.random.default_rng(37)
    for k in range(n):
        gx = xa + k * step + (step - gh) * 0.5
        glyph_text(cv, px(gx), py(yb), gh * ppm, GLYPHS, [int(rng.integers(0, 64))], width=0.1)
    g = cv.array()
    alb = alb * (1 - g[..., None]) + ORANGE[None, None, :] * g[..., None]
    em = np.maximum(em, g)
    cover = np.maximum(cover, g)
    # porte de la passerelle (sas éclairé)
    xa, ya, xb, yb = DOOR
    m = rect(xa, ya, xb, yb)
    alb = np.where(m[..., None], srgb("#ffd2a0") * 0.8, alb)
    em = np.where(m, 0.75, em)
    fr = m & ~rect(xa + 0.08, ya, xb - 0.08, yb - 0.08)
    alb = np.where(fr[..., None], FRAME, alb)
    em = np.where(fr, 0.0, em)
    return np.clip(alb, 0, 1), np.clip(em, 0, 1), cover


def near_strips():
    """Les deux bandes proches (RGBA : albédo, masque d'émission)."""
    out = []
    for (xa, xb) in ((NEAR_X0, NEAR_XM), (NEAR_XM, NEAR_X1)):
        a, e, c = paint(NEAR_PPM, xa, xb, NEAR_Y0, NEAR_Y1, 2)
        out.append(np.concatenate([a, e[..., None]], -1))
    return out


def facade_map(path):
    """Carte de la façade pour les reflets : RGB émission (sRGB), A couverture."""
    ppm = 2048 / (FX1 - FX0)
    a, e, c = paint(ppm, FX0, FX1, FY0, FY1, 1)
    lin = a ** 2.2
    em = lin * (e[..., None] * 1.0 + 0.035)
    rgb = np.clip(em, 0, 1) ** (1 / 2.2)
    rgba = np.concatenate([rgb, c[..., None]], -1)
    Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)
    print("  ->", path.split("assets/")[-1], rgba.shape[1], "x", rgba.shape[0])
