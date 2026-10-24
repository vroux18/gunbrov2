#!/usr/bin/env python3
"""Nébuleuse 7 — murs ouest / est et garde-corps sud du hangar.

Écrit dans assets/decor/shell/ :
  wall_atlas.png   2048² : RGB albédo (sRGB), A masque lumineux (écrans, panneaux rétroéclairés, voyants)
  shell_walls.glb  deux maillages : « walls » (tout l'opaque, un seul matériau) et « glass » (hublots)
Sommets : COLOR.rgb teinte, COLOR.a classe (0 peinture, 1/3 métal nu, 2/3 caoutchouc, 1 lumineux) ;
UV2.x animation (0 aucune, 0,25 écran défilant, 0,5 gyrophare, 0,75 voyant clignotant), UV2.y phase.
Lancement : python3 tools/decor/shell_walls.py
"""
import math
import os

import numpy as np

from shell_common import (FONT_RAJ, FONT_RUSSO, H, OUT, TOP, W, WALL, Canvas, aniso_noise, blur, blur_noise,
                          norm01, save_rgba, smoothstep, srgb, write_glb, write_json)

R = np.random.default_rng(707)

XF = WALL - 0.22          # plan des panneaux, en retrait de la limite de jeu
HW = 3.0                  # haut des panneaux
RIB0, RIBS = 1.45, 3.0    # premier pilier, pas des piliers
NRIB = 7
BAYS_W = ["port", "screen", "sign", "door", "port", "console"]
BAYS_E = ["screen", "port", "console", "door", "sign", "port"]
PAINT, BARE, RUBBER, GLOW = 0.0, 1 / 3, 2 / 3, 1.0
A_NONE, A_SCROLL, A_BEACON, A_BLINK = 0.0, 0.25, 0.5, 0.75

# ================================================================ atlas
PX = 200  # px par mètre
AT = 2048
ATH = 1536  # hauteur de l'atlas (le bas serait vide)
atlas = np.zeros((ATH, AT, 4), np.float32)
REG = {}
_cur = [8, 8, 0]  # x, y, hauteur de l'étagère


def region(name, wpx, hpx):
    x, y, sh = _cur
    if x + wpx + 8 > AT:
        x, y, sh = 8, y + sh + 8, 0
    if y + hpx + 8 > ATH:
        raise RuntimeError("atlas des murs plein : " + name)
    REG[name] = (x, y, wpx, hpx)
    _cur[0], _cur[1], _cur[2] = x + wpx + 8, y, max(sh, hpx)
    return x, y


def put(name, rgb, a=None):
    h, w = rgb.shape[:2]
    x, y = region(name, w, h)
    atlas[y:y + h, x:x + w, :3] = np.clip(rgb, 0, 1)
    atlas[y:y + h, x:x + w, 3] = 0.0 if a is None else np.clip(a, 0, 1)
    # bordure dupliquée contre les fuites au filtrage
    atlas[y - 3:y, x:x + w] = atlas[y:y + 1, x:x + w]
    atlas[y + h:y + h + 3, x:x + w] = atlas[y + h - 1:y + h, x:x + w]
    atlas[y - 3:y + h + 3, x - 3:x] = atlas[y - 3:y + h + 3, x:x + 1]
    atlas[y - 3:y + h + 3, x + w:x + w + 3] = atlas[y - 3:y + h + 3, x + w - 1:x + w]


def uvr(name, sub=None):
    """Cadre UV (u0, v0, u1, v1) d'une région, ou d'une sous-partie (fractions x0, y0, x1, y1)."""
    x, y, w, h = REG[name]
    if sub is not None:
        x0, y0, x1, y1 = sub
        return ((x + x0 * w) / AT, (y + y0 * h) / ATH, (x + x1 * w) / AT, (y + y1 * h) / ATH)
    return (x / AT, y / ATH, (x + w) / AT, (y + h) / ATH)


def grid_m(wm, hm):
    w, h = int(round(wm * PX)), int(round(hm * PX))
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    return w, h, (jj + 0.5) / PX, (ii + 0.5) / PX


def grime(w, h, seed, bottom=0.35):
    """Salissures : bruit, coulures verticales, encrassement du bas."""
    n = blur_noise(h, w, 18, seed) * 0.5 + blur_noise(h, w, 3, seed + 1) * 0.25
    streak = aniso_noise(h, w, 1.5, 40, seed + 2)
    yy = np.linspace(0, 1, h)[:, None]
    g = 0.5 + n * 0.12 + streak * 0.06 - (smoothstep(1 - bottom, 1.0, yy) * 0.25 if bottom > 0 else 0.0)
    return np.clip(g, 0, 1)


def shade_box(img, x0, y0, x1, y1, depth=1.0, light=0.18, dark=0.3, bw=3):
    """Faux relief d'un cadre : arête haute claire, arête basse sombre."""
    x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
    img[y0:y0 + bw, x0:x1] *= 1 + light * depth
    img[y1 - bw:y1, x0:x1] *= 1 - dark * depth
    img[y0:y1, x0:x0 + bw] *= 1 + light * 0.5 * depth
    img[y0:y1, x1 - bw:x1] *= 1 - dark * 0.5 * depth


def text_mask(w, h, items, ss=2):
    cv = Canvas(w, h, ss)
    for it in items:
        x, y, s, size = it[:4]
        font = it[4] if len(it) > 4 else FONT_RUSSO
        cv.text(x, y, s, size, font=font, spacing=size * 0.06)
    return cv.array()


def bolts(img, pts, r=3, col=1.25):
    h, w = img.shape[:2]
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    for (x, y) in pts:
        d = np.sqrt((jj - x) ** 2 + (ii - y) ** 2)
        m = smoothstep(r, r - 1.2, d)
        sh = smoothstep(r + 1.5, r, d) * (1 - m)
        img *= (1 - sh[..., None] * 0.35)
        lit = np.clip(1 - ((jj - x + r * 0.4) ** 2 + (ii - y + r * 0.4) ** 2) / (r * r), 0, 1)
        img[:] = img * (1 - m[..., None]) + img * m[..., None] * (col + lit[..., None] * 0.4)


WALLC = srgb("#2b303b")
WALLC2 = srgb("#333946")
DARK = srgb("#1c1f27")
YEL = srgb("#c99a32")
BLK = srgb("#15171c")
WHT = srgb("#c8ccd2")


def paint_atlas():
    print("atlas des murs")
    # --- panneaux 1,35 m
    pm = 1.35
    for k in range(6):
        w, h, xx, yy = grid_m(pm, pm)
        base = WALLC if k % 2 == 0 else WALLC2
        img = np.ones((h, w, 3)) * base * (0.92 + 0.1 * R.random())
        g = grime(w, h, 900 + k)
        img *= (0.75 + 0.5 * g)[..., None]
        a = np.zeros((h, w))
        b = 10
        # cadre et joint périphérique
        img[:3, :] *= 0.4
        img[-3:, :] *= 0.4
        img[:, :3] *= 0.4
        img[:, -3:] *= 0.4
        shade_box(img, 3, 3, w - 3, h - 3, 1.0)
        if k == 0:  # raidisseurs verticaux
            for x in (w // 3, 2 * w // 3):
                img[b:h - b, x - 5:x + 5] *= 1.12
                img[b:h - b, x + 5:x + 7] *= 0.65
        elif k == 1:  # ouïes d'aération
            for i in range(9):
                y0 = int(h * 0.22 + i * h * 0.065)
                img[y0:y0 + 8, int(w * 0.15):int(w * 0.85)] *= 0.25
                img[y0 + 8:y0 + 11, int(w * 0.15):int(w * 0.85)] *= 1.5
            shade_box(img, w * 0.12, h * 0.18, w * 0.88, h * 0.82, -0.8)
        elif k == 2:  # étiquette, code-barres, autocollant de danger
            tm = text_mask(w, h, [(w * 0.3, h * 0.2, "N7-07", h * 0.1)])
            img = img * (1 - tm[..., None] * 0.7) + WHT * tm[..., None] * 0.7
            for i in range(28):
                x = int(w * 0.55 + i * 3.3)
                if R.random() < 0.6:
                    img[int(h * 0.14):int(h * 0.26), x:x + 2] = WHT * 0.7
            st = (np.mod((xx + yy) / 0.06, 1) < 0.5)
            band = (yy > pm * 0.84) & (yy < pm * 0.94)
            img = np.where(band[..., None], np.where(st[..., None], YEL * 0.9, BLK), img)
        elif k == 3:  # trappe de visite à poignée
            x0, y0, x1, y1 = int(w * 0.2), int(h * 0.3), int(w * 0.8), int(h * 0.8)
            img[y0:y1, x0:x1] *= 1.08
            shade_box(img, x0, y0, x1, y1, 1.0, bw=4)
            img[int(h * 0.52):int(h * 0.58), int(w * 0.44):int(w * 0.56)] = DARK * 0.6
            tm = text_mask(w, h, [(w * 0.5, h * 0.4, "ACCÈS TECHNIQUE", h * 0.045, FONT_RAJ)])
            img = img * (1 - tm[..., None] * 0.6) + YEL * tm[..., None] * 0.6
            bolts(img, [(x0 + 8, y0 + 8), (x1 - 8, y0 + 8), (x0 + 8, y1 - 8), (x1 - 8, y1 - 8)])
        elif k == 4:  # goulottes de câbles
            for i in range(4):
                x0 = int(w * (0.12 + i * 0.2))
                img[b:h - b, x0:x0 + int(w * 0.12)] *= 0.7
                shade_box(img, x0, b, x0 + int(w * 0.12), h - b, -0.6)
        else:  # bande de danger en bas
            st = (np.mod((xx - yy) / 0.08, 1) < 0.5)
            band = yy > pm * 0.82
            hz = np.where(st[..., None], YEL * 0.85, BLK)
            img = np.where(band[..., None], hz * (0.8 + 0.3 * g[..., None]), img)
        pts = [(x, y) for x in (8, w - 8) for y in np.linspace(8, h - 8, 6)]
        bolts(img, pts)
        put("panel%d" % k, img, a)
    # --- plinthe à bandes de danger (1,5 x 0,3 m)
    w, h, xx, yy = grid_m(1.5, 0.3)
    st = (np.mod((xx + yy) / 0.1, 1) < 0.5)
    img = np.where(st[..., None], YEL, BLK) * 1.0
    g = grime(w, h, 950, 0.6)
    img = img * (0.6 + 0.6 * g[..., None])
    chips = norm01(blur_noise(h, w, 2, 951) + blur_noise(h, w, 8, 952)) < 0.25
    img = np.where(chips[..., None], DARK * 1.3, img)
    img[:3] *= 1.4
    img[-4:] *= 0.4
    put("kick", img)
    # --- pilier (face avant 0,3 x 3,0 m) : boulons, base jaune et noire, plaque numérotée
    w, h, xx, yy = grid_m(0.3, 3.0)
    img = np.ones((h, w, 3)) * DARK * 1.1
    g = grime(w, h, 960, 0.2)
    img *= (0.7 + 0.6 * g)[..., None]
    img[:, :4] *= 1.4
    img[:, -4:] *= 0.55
    st = (np.mod((xx + yy) / 0.08, 1) < 0.5)
    base = yy > 3.0 - 0.45
    img = np.where(base[..., None], np.where(st[..., None], YEL * 0.85, BLK) * (0.7 + 0.4 * g[..., None]), img)
    bolts(img, [(x, y) for x in (12, w - 12) for y in np.arange(30, h - 100, 55)], r=3.5)
    # plaque « 07 » rétroéclairée
    y0 = int(h * 0.42)
    img[y0:y0 + 56, 8:w - 8] = DARK * 0.5
    tm = text_mask(w, 56, [(w * 0.5, 30, "07", 40)])
    a = np.zeros((h, w))
    a[y0:y0 + 56] = tm * 0.08
    img[y0:y0 + 56] = img[y0:y0 + 56] * (1 - tm[..., None]) + srgb("#8a8478") * tm[..., None]
    put("rib", img, a)
    # --- côté de pilier, sous-face, métal générique
    w, h, xx, yy = grid_m(0.3, 1.0)
    img = np.ones((h, w, 3)) * DARK * 0.9 * (0.8 + 0.4 * grime(w, h, 961)[..., None])
    put("ribside", img)
    for name, col, s in (("metal", srgb("#9aa2ae"), 962), ("dark", DARK, 963), ("mid", WALLC, 964)):
        w, h = 64, 64
        n = blur_noise(h, w, 6, s) * 0.08 + blur_noise(h, w, 1, s + 1) * 0.04
        img = np.ones((h, w, 3)) * col * (1 + n[..., None])
        put(name, img)
    put("white", np.ones((32, 32, 3)), np.ones((32, 32)))
    # --- poutre de rive (1,5 x 0,35 m) : boulons, liseré lumineux, numéros de baie
    w, h, xx, yy = grid_m(1.5, 0.35)
    img = np.ones((h, w, 3)) * srgb("#252b38") * (0.75 + 0.5 * grime(w, h, 965, 0.1)[..., None])
    img[:4] *= 1.5
    img[-5:] *= 0.5
    a = np.zeros((h, w))
    a[int(h * 0.72):int(h * 0.8), :] = 0.12
    img[int(h * 0.72):int(h * 0.8), :] = srgb("#2e3a5e")
    bolts(img, [(x, h * 0.35) for x in np.arange(15, w, 37)], r=3)
    put("header", img, a)
    # --- dessus du mur (1,5 x 1,5 m vu du ciel) : caillebotis, chemin de câbles
    w, h, xx, yy = grid_m(1.5, 1.5)
    gx = np.mod(xx / 0.05, 1) < 0.25
    gy = np.mod(yy / 0.05, 1) < 0.25
    img = np.ones((h, w, 3)) * 0.05
    img = np.where((gx | gy)[..., None], srgb("#2a303c") * 1.1, img)
    tray = (xx > 0.9) & (xx < 1.3)
    img = np.where(tray[..., None], srgb("#1a1d24") * (0.8 + 0.4 * (np.mod(xx / 0.03, 1) < 0.5))[..., None], img)
    img *= (0.75 + 0.5 * grime(w, h, 966, 0.0))[..., None]
    img[:, :6] = srgb("#3a4152")
    put("roof", img)
    # --- écran : manifeste défilant (1,2 m de large, tuile verticale de 2,4 m)
    w, h, xx, yy = grid_m(1.2, 2.4)
    img = np.ones((h, w, 3)) * srgb("#06121c")
    cv = Canvas(w, h, 2)
    lines = ["HÉLIX FRET  ·  MANIFESTE BAIE 07", "CONT. 07-A114   MINERAI    32 T  OK", "CONT. 07-A115   GLACE      18 T  OK",
             "CONT. 07-B020   PIÈCES     09 T  !", "CONT. 07-B021   VIVRES     06 T  OK", "CONT. 07-C301   GAZ RARE   12 T  OK",
             "CONT. 07-C302   CRISTAUX   04 T  ?", "CONT. 07-D011   MÉDICAL    02 T  OK", "QUAI 07  ·  FENÊTRE 14:20", "DOCK N7 -- RELAIS -- OK"]
    y = 18
    i = 0
    while y < h - 18:
        cv.text(12, y, lines[i % len(lines)], 15, font=FONT_RAJ, anchor="lm", maxw=w - 24)
        y += 26
        i += 1
    tm = cv.array()
    col = np.where((np.mod(np.arange(h) // 26, 4) == 3)[:, None, None], srgb("#ffb35c"), srgb("#7fd6ff"))
    img = img * (1 - tm[..., None]) + col * tm[..., None]
    scan = (np.mod(np.arange(h), 3) == 0)[:, None]
    img *= np.where(scan, 0.8, 1.0)[..., None]
    put("scroll", img, np.clip(0.55 + tm * 0.45, 0, 1))
    # --- écran radar : carte de la nébuleuse
    w, h, xx, yy = grid_m(1.2, 0.7)
    neb = norm01(blur_noise(h, w, 14, 970) + blur_noise(h, w, 4, 971) * 0.4)
    img = srgb("#0a0c22") * (1 - neb[..., None]) + srgb("#6a3fbf") * neb[..., None] * 0.8
    cx, cy = w * 0.55, h * 0.5
    d = np.sqrt((np.arange(w)[None, :] - cx) ** 2 + (np.arange(h)[:, None] - cy) ** 2)
    rings = (np.abs(np.mod(d, 28) - 14) > 13).astype(np.float32)
    img = img + rings[..., None] * srgb("#3c8cff") * 0.5
    tm = text_mask(w, h, [(w * 0.12, h * 0.12, "N7", 18), (w * 0.8, h * 0.85, "SECTEUR 7", 12, FONT_RAJ)])
    img = img * (1 - tm[..., None]) + srgb("#ffc070") * tm[..., None]
    for (px, py) in ((cx, cy), (w * 0.3, h * 0.3), (w * 0.8, h * 0.25)):
        dd = np.sqrt((np.arange(w)[None, :] - px) ** 2 + (np.arange(h)[:, None] - py) ** 2)
        img += smoothstep(5, 2, dd)[..., None] * srgb("#ffb35c")
    put("radar", img, np.ones((h, w)) * 0.85)
    # --- panneau « 07 » rétroéclairé
    w, h, xx, yy = grid_m(0.9, 0.9)
    img = np.ones((h, w, 3)) * srgb("#111521")
    tm = text_mask(w, h, [(w * 0.5, h * 0.44, "07", h * 0.55), (w * 0.5, h * 0.84, "BAIE", h * 0.15)])
    img = img * (1 - tm[..., None]) + srgb("#ffe2b0") * tm[..., None]
    img[:6] = YEL
    img[-6:] = YEL
    a = tm * 0.95
    put("sign07", img, a)
    # --- enseigne HÉLIX FRET
    w, h, xx, yy = grid_m(1.8, 0.45)
    img = np.ones((h, w, 3)) * srgb("#141824")
    tm = text_mask(w, h, [(w * 0.58, h * 0.5, "HÉLIX FRET", h * 0.52)])
    cv = Canvas(w, h, 2)
    r = h * 0.36
    hexa = [(h * 0.55 + r * math.cos(math.pi / 6 + k * math.pi / 3), h * 0.5 + r * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    cv.line(hexa + [hexa[0]], 5)
    hx = cv.array()
    img = img * (1 - tm[..., None]) + WHT * tm[..., None]
    img = img * (1 - hx[..., None]) + srgb("#ff9a40") * hx[..., None]
    put("logo", img, np.clip(tm + hx, 0, 1) * 0.9)
    # --- panneau « SECTEUR N7 · QUAI 07 »
    w, h, xx, yy = grid_m(1.6, 0.32)
    img = np.ones((h, w, 3)) * srgb("#1b4d8f") * 0.8
    tm = text_mask(w, h, [(w * 0.5, h * 0.52, "SECTEUR N7  ·  QUAI 07", h * 0.5, FONT_RAJ)])
    img = img * (1 - tm[..., None]) + WHT * tm[..., None]
    img[:4] = WHT * 0.8
    img[-4:] = WHT * 0.8
    put("secteur", img, np.ones((h, w)) * 0.35 + tm * 0.5)
    # --- porte de sas (2,4 x 2,6 m)
    w, h, xx, yy = grid_m(2.4, 2.6)
    img = np.ones((h, w, 3)) * srgb("#3a4254") * (0.75 + 0.5 * grime(w, h, 980, 0.3)[..., None])
    st = (np.mod((xx + yy) / 0.12, 1) < 0.5)
    fr = np.minimum.reduce([xx, yy, 2.4 - xx]) < 0.14
    img = np.where(fr[..., None], np.where(st[..., None], YEL * 0.9, BLK), img)
    # deux vantaux, joint central, hublots fins, chevrons
    img[:, w // 2 - 2:w // 2 + 2] *= 0.3
    for x0 in (int(w * 0.18), int(w * 0.62)):
        img[int(h * 0.25):int(h * 0.42), x0:x0 + int(w * 0.2)] = srgb("#0c1530")
        shade_box(img, x0, h * 0.25, x0 + w * 0.2, h * 0.42, -1)
    for i in range(6):
        y0 = int(h * 0.5 + i * h * 0.07)
        img[y0:y0 + 6, int(w * 0.2):int(w * 0.8)] *= 0.7
    tm = text_mask(w, h, [(w * 0.5, h * 0.14, "SAS DE FRET  07", h * 0.06)])
    img = img * (1 - tm[..., None] * 0.8) + WHT * tm[..., None] * 0.8
    a = np.zeros((h, w))
    a[int(h * 0.25):int(h * 0.42)] = ((xx[int(h * 0.25):int(h * 0.42)] > 0.43) & (xx[int(h * 0.25):int(h * 0.42)] < 0.91) | (xx[int(h * 0.25):int(h * 0.42)] > 1.49) & (xx[int(h * 0.25):int(h * 0.42)] < 1.97)) * 0.4
    put("door", img, a)
    # --- console murale (1,0 x 0,7 m) : boutons, voyants (masque lumineux), petit écran
    w, h, xx, yy = grid_m(1.0, 0.7)
    img = np.ones((h, w, 3)) * srgb("#2a3040")
    a = np.zeros((h, w))
    img[int(h * 0.12):int(h * 0.5), int(w * 0.08):int(w * 0.55)] = srgb("#0a1a24")
    a[int(h * 0.12):int(h * 0.5), int(w * 0.08):int(w * 0.55)] = 0.6
    tm = text_mask(int(w * 0.47), int(h * 0.38), [(w * 0.235, h * 0.19, "PRESSION  OK", 14, FONT_RAJ)])
    img[int(h * 0.12):int(h * 0.12) + tm.shape[0], int(w * 0.08):int(w * 0.08) + tm.shape[1]] += tm[..., None] * srgb("#7fe0a0")
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    cols = [srgb("#ffb347"), srgb("#7fe0a0"), srgb("#7fd6ff"), srgb("#ffb347")]
    for i in range(4):
        for j in range(3):
            cx, cy = w * (0.64 + 0.09 * i), h * (0.2 + 0.14 * j)
            d = np.sqrt((jj - cx) ** 2 + (ii - cy) ** 2)
            m = smoothstep(6, 4.5, d)
            img = img * (1 - m[..., None]) + cols[(i + j) % 4] * m[..., None]
            a = np.maximum(a, m)
    for i in range(6):
        cx, cy = w * (0.12 + 0.13 * i), h * 0.72
        d = np.sqrt((jj - cx) ** 2 + (ii - cy) ** 2)
        m = smoothstep(11, 9, d)
        img = img * (1 - m[..., None]) + srgb("#4a5266") * m[..., None]
    shade_box(img, 0, 0, w, h, 1.0, bw=5)
    put("console", img, a)
    # --- signalétique : danger dépressurisation (0,5 m)
    w, h, xx, yy = grid_m(0.5, 0.5)
    img = np.ones((h, w, 3)) * YEL
    cv = Canvas(w, h, 2)
    cv.poly([(w * 0.5, h * 0.1), (w * 0.9, h * 0.78), (w * 0.1, h * 0.78)])
    tri = cv.array()
    img = img * (1 - tri[..., None]) + BLK * tri[..., None]
    tm = text_mask(w, h, [(w * 0.5, h * 0.58, "!", h * 0.4), (w * 0.5, h * 0.9, "VIDE", h * 0.13)])
    img = img * (1 - tm[..., None]) + np.where((yy > 0.4)[..., None], BLK, YEL) * tm[..., None]
    put("warn", img)
    # --- câble (caoutchouc) et métal de tuyau
    w, h = 64, 32
    img = np.ones((h, w, 3)) * 0.9 * (1 + blur_noise(h, w, 2, 990)[..., None] * 0.05)
    put("pipe", img)
    print("  régions :", len(REG))
    save_rgba(os.path.join(OUT, "wall_atlas.png"), atlas)


# ================================================================ géométrie
class MB:
    def __init__(self):
        self.P, self.N, self.UV, self.UV2, self.C = [], [], [], [], []
        self.side = 1

    # repère local : n vers l'arène depuis le plan des panneaux, y vers le haut, z le long du mur
    def w(self, p):
        n, y, z = p
        return (XF + n, y, z) if self.side > 0 else (W - XF - n, y, z)

    def wn(self, v):
        return (v[0] * self.side, v[1], v[2])

    def tri(self, ps, ns, uvs, col, cls, anim=(0.0, 0.0), world=False):
        P = [np.array(p if world else self.w(p), float) for p in ps]
        Nn = [np.array(n if world else self.wn(n), float) for n in ns]
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

    def quad(self, c, right, up, hw, hh, uv, col, cls=PAINT, anim=(0.0, 0.0), world=False):
        c, r, u = np.array(c, float), np.array(right, float), np.array(up, float)
        n = np.cross(r, u)
        a, b, cc, d = c - r * hw - u * hh, c + r * hw - u * hh, c + r * hw + u * hh, c - r * hw + u * hh
        u0, v0, u1, v1 = uv
        if self.side < 0 and not world:
            u0, u1 = u1, u0  # le miroir du mur est retournerait les textes
        self.tri([a, b, cc], [n] * 3, [(u0, v1), (u1, v1), (u1, v0)], col, cls, anim, world)
        self.tri([a, cc, d], [n] * 3, [(u0, v1), (u1, v0), (u0, v0)], col, cls, anim, world)

    def box(self, c, size, uv, col, cls=PAINT, faces="fbtudlr", anim=(0.0, 0.0), uvs=None):
        """Boîte en repère local ; faces : f (+n), b (-n), t (+y), u (-y), d (+z), l (-z)."""
        cn, cy, cz = c
        sn, sy, sz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        uvs = uvs or {}
        F = {
            "f": ((cn + sn, cy, cz), (0, 0, -1), (0, 1, 0), sz, sy),
            "b": ((cn - sn, cy, cz), (0, 0, 1), (0, 1, 0), sz, sy),
            "t": ((cn, cy + sy, cz), (0, 0, -1), (-1, 0, 0), sz, sn),
            "u": ((cn, cy - sy, cz), (0, 0, -1), (1, 0, 0), sz, sn),
            "d": ((cn, cy, cz + sz), (1, 0, 0), (0, 1, 0), sn, sy),
            "l": ((cn, cy, cz - sz), (-1, 0, 0), (0, 1, 0), sn, sy),
        }
        for f in faces:
            if f in F:
                p, r, u, a, b = F[f]
                self.quad(p, r, u, a, b, uvs.get(f, uv), col, cls, anim)

    def cyl(self, a, b, r, uv, col, cls=BARE, seg=12, caps=False, anim=(0.0, 0.0)):
        a, b = np.array(a, float), np.array(b, float)
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
            p00, p01 = a + n0 * r, a + n1 * r
            p10, p11 = b + n0 * r, b + n1 * r
            ua, ub = u0 + (u1 - u0) * i / seg, u0 + (u1 - u0) * (i + 1) / seg
            self.tri([p00, p10, p11], [n0, n0, n1], [(ua, v1), (ua, v0), (ub, v0)], col, cls, anim)
            self.tri([p00, p11, p01], [n0, n1, n1], [(ua, v1), (ub, v0), (ub, v1)], col, cls, anim)
            if caps:
                for cc, sg in ((a, -1), (b, 1)):
                    self.tri([cc, cc + n0 * r, cc + n1 * r], [ax * sg] * 3, [(u0, v0)] * 3, col, cls, anim)

    def tube(self, pts, r, uv, col, cls=RUBBER, seg=6):
        for p, q in zip(pts[:-1], pts[1:]):
            self.cyl(p, q, r, uv, col, cls, seg)

    def disc(self, c, normal, r, uv, col, cls=PAINT, seg=20, anim=(0.0, 0.0)):
        c, n = np.array(c, float), np.array(normal, float)
        t = np.cross(n, (0, 1, 0) if abs(n[1]) < 0.9 else (1, 0, 0))
        t /= np.linalg.norm(t)
        s = np.cross(n, t)
        u0, v0, u1, v1 = uv
        cu, cv = (u0 + u1) * 0.5, (v0 + v1) * 0.5
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            p0 = c + (t * math.cos(a0) + s * math.sin(a0)) * r
            p1 = c + (t * math.cos(a1) + s * math.sin(a1)) * r
            self.tri([c, p0, p1], [n] * 3, [(cu, cv), (cu + math.cos(a0) * (u1 - u0) * 0.5, cv - math.sin(a0) * (v1 - v0) * 0.5),
                                             (cu + math.cos(a1) * (u1 - u0) * 0.5, cv - math.sin(a1) * (v1 - v0) * 0.5)], col, cls, anim)

    def ring(self, c, normal, r0, r1, depth, uv, col, cls=BARE, seg=20):
        """Anneau épais (cadre de hublot) : faces avant, intérieure, extérieure."""
        c, n = np.array(c, float), np.array(normal, float)
        t = np.cross(n, (0, 1, 0) if abs(n[1]) < 0.9 else (1, 0, 0))
        t /= np.linalg.norm(t)
        s = np.cross(n, t)
        u0, v0, u1, v1 = uv
        f = c + n * depth
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            d0 = t * math.cos(a0) + s * math.sin(a0)
            d1 = t * math.cos(a1) + s * math.sin(a1)
            self.tri([f + d0 * r0, f + d0 * r1, f + d1 * r1], [n] * 3, [(u0, v0), (u1, v0), (u1, v1)], col, cls)
            self.tri([f + d0 * r0, f + d1 * r1, f + d1 * r0], [n] * 3, [(u0, v0), (u1, v1), (u0, v1)], col, cls)
            self.tri([c + d0 * r1, f + d0 * r1, f + d1 * r1], [d0, d0, d1], [(u0, v0), (u1, v0), (u1, v1)], col, cls)
            self.tri([c + d0 * r1, f + d1 * r1, c + d1 * r1], [d0, d1, d1], [(u0, v0), (u1, v1), (u0, v1)], col, cls)
            self.tri([c + d0 * r0, f + d0 * r0, f + d1 * r0], [-d0, -d0, -d1], [(u0, v0), (u1, v0), (u1, v1)], col, cls)
            self.tri([c + d0 * r0, f + d1 * r0, c + d1 * r0], [-d0, -d1, -d1], [(u0, v0), (u1, v1), (u0, v1)], col, cls)

    def arrays(self):
        """Sommets identiques fusionnés (le GLB est trois fois plus léger)."""
        allv = np.concatenate([np.array(self.P), np.array(self.N), np.array(self.UV), np.array(self.UV2), np.array(self.C)], 1)
        key = np.round(allv, 5)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        u = allv[np.unique(inv.reshape(-1), return_index=True)[1]]
        return {"pos": u[:, 0:3], "nrm": u[:, 3:6], "uv": u[:, 6:8], "uv2": u[:, 8:10], "col": u[:, 10:14],
                "idx": inv.reshape(-1, 3)}


ONE = (1.0, 1.0, 1.0)


def build_side(mb, gl, side, bays):
    mb.side = side
    gl.side = side
    # fond : panneaux sur toute la longueur, deux rangées de 1,35 m
    L = H
    zs = [0.0]
    for k in range(NRIB):
        zr = RIB0 + k * RIBS
        zs += [zr - 0.15, zr + 0.15]
    zs.append(L)
    spans = [(zs[i], zs[i + 1]) for i in range(0, len(zs), 2)]
    for si, (z0, z1) in enumerate(spans):
        bay = bays[si - 1] if 1 <= si <= len(bays) else "end"
        n = max(1, int(round((z1 - z0) / 1.35)))
        wpan = (z1 - z0) / n
        for j in range(n):
            zc = z0 + wpan * (j + 0.5)
            for row, (y0, y1) in enumerate(((0.3, 1.65), (1.65, HW))):
                if bay == "door" and row == 0:
                    continue
                if bay == "door" and row == 1 and y1 <= 2.6:
                    continue
                k = int(R.integers(0, 5)) if row == 1 else int(R.choice([0, 2, 4, 5, 5]))
                inset = 0.0 if (j + row) % 2 == 0 else -0.025
                mb.box((inset - 0.03, (y0 + y1) * 0.5, zc), (0.06, y1 - y0 - 0.01, wpan - 0.01), uvr("panel%d" % k), ONE, PAINT,
                       faces="fdl", uvs={"d": uvr("ribside"), "l": uvr("ribside")})
        # plinthe à bandes de danger, liseré lumineux au-dessus
        mb.box((0.11, 0.15, (z0 + z1) * 0.5), (0.22, 0.3, z1 - z0), uvr("kick"), ONE, PAINT, faces="ft",
               uvs={"t": uvr("dark")})
        acc = srgb("#8c6bff") if side > 0 else srgb("#5c8cff")
        mb.box((0.215, 0.31, (z0 + z1) * 0.5), (0.02, 0.018, z1 - z0 - 0.1), uvr("white"), acc * 0.4, GLOW, faces="ft")
    # piliers (I) : âme, semelle avant, gousset en haut ; lampe et gyrophare
    for k in range(NRIB):
        zr = RIB0 + k * RIBS
        mb.box((0.15, HW * 0.5, zr), (0.3, HW, 0.1), uvr("ribside"), ONE, PAINT, faces="dl")
        mb.box((0.33, HW * 0.5, zr), (0.05, HW, 0.3), uvr("rib"), ONE, PAINT, faces="fdlt",
               uvs={"d": uvr("dark"), "l": uvr("dark"), "t": uvr("dark")})
        mb.box((0.02, HW * 0.5, zr), (0.05, HW, 0.34), uvr("dark"), ONE, PAINT, faces="fdl")
        # pied du pilier
        mb.box((0.2, 0.06, zr), (0.36, 0.12, 0.4), uvr("dark"), (1.2, 1.2, 1.2), PAINT, faces="ftdl")
        if k in (2, 5):
            # gyrophare : socle et dôme orange (le faisceau est simulé dans les shaders)
            mb.box((0.42, HW - 0.1, zr), (0.2, 0.06, 0.2), uvr("dark"), ONE, PAINT, faces="fdltu")
            ph = (0.0 if k == 2 else 2.1) if side > 0 else (4.0 if k == 2 else 1.0)
            mb.cyl((0.44, HW - 0.07, zr), (0.44, HW + 0.1, zr), 0.075, uvr("white"), srgb("#ff7a2f") * 1.2, GLOW, 12, caps=True,
                   anim=(A_BEACON, ph / (2 * math.pi)))
            for j in range(4):
                a = j * math.pi / 2 + math.pi / 4
                p0 = (0.44 + math.cos(a) * 0.085, HW - 0.07, zr + math.sin(a) * 0.085)
                mb.cyl(p0, (p0[0], HW + 0.12, p0[2]), 0.008, uvr("dark"), ONE, PAINT, 5)
    # poutre de rive, dessus du mur, chemin de câbles
    mb.box((0.18, HW + 0.17, L * 0.5), (0.36, 0.34, L), uvr("header"), ONE, PAINT, faces="u",
           uvs={"u": uvr("dark")})
    nseg = int(L / 1.5)
    for i in range(nseg + 1):
        z0 = i * 1.5
        z1 = min(L, z0 + 1.5)
        if z1 - z0 < 0.05:
            continue
        frac = (z1 - z0) / 1.5
        mb.box((0.18, HW + 0.17, (z0 + z1) * 0.5), (0.36, 0.34, z1 - z0), uvr("header", (0, 0, frac, 1)), ONE, PAINT, faces="f")
        mb.box((-0.6, HW + 0.34, (z0 + z1) * 0.5), (1.92, 0.02, z1 - z0), uvr("roof", (0, 0, 1, frac)), ONE, PAINT, faces="t")
    mb.box((-0.6, HW + 0.17, L - 0.01), (1.92, 0.34, 0.02), uvr("dark"), ONE, PAINT, faces="d")
    # appliques sous la poutre (une par baie) : boîtier sombre, face lumineuse
    lamp = srgb("#d6ccff") if side > 0 else srgb("#ffe0b8")
    for k in range(7):
        z = 2.95 + 3.0 * k
        mb.box((0.36, HW - 0.04, z), (0.16, 0.08, 0.55), uvr("dark"), ONE, PAINT, faces="fdlu")
        mb.box((0.36, HW - 0.085, z), (0.12, 0.01, 0.5), uvr("white"), lamp * 1.0, GLOW, faces="u")
    # tuyaux le long du mur : gros jaune, moyen bleu-gris, conduit bas sombre ; colliers aux piliers, brides
    pipes = [(0.17, 2.42, 0.085, srgb("#b08a3a")), (0.13, 2.69, 0.055, srgb("#56647c")), (0.09, 0.55, 0.04, srgb("#2b3140"))]
    for (pn, py, pr, pc) in pipes:
        mb.cyl((pn, py, 0.0), (pn, py, L), pr, uvr("pipe"), pc, BARE, 12)
        for k in range(NRIB):
            zr = RIB0 + k * RIBS
            mb.cyl((pn, py, zr - 0.2), (pn, py, zr - 0.14), pr * 1.35, uvr("dark"), ONE, PAINT, 12, caps=True)
            mb.cyl((pn, py, zr + 0.14), (pn, py, zr + 0.2), pr * 1.35, uvr("dark"), ONE, PAINT, 12, caps=True)
        z = 0.75
        while z < L:
            mb.cyl((pn, py, z), (pn, py, z + 0.05), pr * 1.25, uvr("pipe"), pc * 0.8, BARE, 12, caps=True)
            if pr > 0.07:
                mb.cyl((pn, py, z + 0.3), (pn, py, z + 0.42), pr * 1.04, uvr("pipe"), srgb("#8f8f88"), PAINT, 12)
            z += 1.5
    # faisceaux de câbles entre les piliers (chaînettes)
    for k in range(NRIB - 1):
        za, zb = RIB0 + k * RIBS + 0.16, RIB0 + (k + 1) * RIBS - 0.16
        for ci, (cn, cy, sag, cr, cc) in enumerate(((0.06, 2.93, 0.2, 0.022, srgb("#202228")), (0.1, 2.9, 0.26, 0.018, srgb("#262a30")),
                                                    (0.08, 2.95, 0.32, 0.016, srgb("#c86a2a")))):
            pts = []
            for t in np.linspace(0, 1, 10):
                pts.append((cn, cy - sag * 4 * t * (1 - t), za + (zb - za) * t))
            mb.tube(pts, cr, uvr("dark"), cc, RUBBER, 6)
    # contenu des baies
    for bi, bay in enumerate(bays):
        zc = RIB0 + (bi + 0.5) * RIBS
        if bay == "port":
            for dz in (-0.68, 0.68):
                c = (0.002, 1.95, zc + dz)
                mb.ring(c, (1, 0, 0), 0.4, 0.5, 0.07, uvr("metal"), srgb("#5b6475"), BARE, 24)
                mb.ring((0.07, 1.95, zc + dz), (1, 0, 0), 0.36, 0.42, 0.025, uvr("dark"), ONE, PAINT, 24)
                for b in range(8):
                    a = 2 * math.pi * b / 8 + 0.2
                    mb.cyl((0.07, 1.95 + math.cos(a) * 0.45, zc + dz + math.sin(a) * 0.45), (0.09, 1.95 + math.cos(a) * 0.45, zc + dz + math.sin(a) * 0.45),
                           0.018, uvr("metal"), (1.2, 1.2, 1.2), BARE, 6, caps=True)
                gl.disc((0.01, 1.95, zc + dz), (1, 0, 0), 0.41, (0, 0, 1, 1), ONE, PAINT, 24)
            mb.box((0.03, 1.2, zc), (0.06, 0.12, 1.9), uvr("dark"), ONE, PAINT, faces="ft")
            mb.box((0.04, 1.33, zc), (0.04, 0.08, 0.4), uvr("warn"), ONE, PAINT, faces="f")
        elif bay == "screen":
            mb.box((0.05, 1.95, zc), (0.1, 0.86, 1.36), uvr("dark"), ONE, PAINT, faces="fdltu")
            mb.quad((0.105, 1.95, zc), (0, 0, -1), (0, 1, 0), 0.6, 0.35, uvr("scroll", (0, 0, 1, 0.29)), ONE, PAINT, (A_SCROLL, 0.0))
            mb.box((0.04, 1.42, zc), (0.08, 0.06, 1.0), uvr("metal"), (0.6, 0.6, 0.6), BARE, faces="ftu")
            mb.box((0.03, 2.5 - 0.1, zc + 0.9), (0.04, 0.32, 0.36), uvr("radar", (0.3, 0.1, 0.7, 0.9)), ONE, PAINT, faces="f")
            mb.quad((0.055, 0.95, zc - 0.5), (0, 0, -1), (0, 1, 0), 0.25, 0.25, uvr("warn"), ONE, PAINT)
        elif bay == "sign":
            mb.box((0.05, 1.9, zc - 0.35), (0.08, 0.9, 0.9), uvr("sign07"), ONE, PAINT, faces="fdltu",
                   uvs={k: uvr("dark") for k in "dltu"})
            mb.box((0.04, 2.15, zc + 0.75), (0.06, 0.45, 1.0), uvr("logo", (0.0, 0, 1.0, 1)), ONE, PAINT, faces="fdltu",
                   uvs={k: uvr("dark") for k in "dltu"})
            mb.box((0.04, 1.5, zc + 0.75), (0.05, 0.3, 1.0), uvr("secteur"), ONE, PAINT, faces="fdltu",
                   uvs={k: uvr("dark") for k in "dltu"})
        elif bay == "door":
            mb.quad((0.01, 1.3, zc), (0, 0, -1), (0, 1, 0), 1.2, 1.3, uvr("door"), ONE, PAINT)
            mb.box((0.06, 2.67, zc), (0.12, 0.1, 2.6), uvr("dark"), ONE, PAINT, faces="ftu")
            for dz in (-1.27, 1.27):
                mb.box((0.06, 1.3, zc + dz), (0.12, 2.6, 0.08), uvr("dark"), ONE, PAINT, faces="fdl")
            mb.box((0.1, 2.8, zc), (0.05, 0.08, 1.4), uvr("white"), srgb("#ffb35c") * 1.2, GLOW, faces="fu", anim=(A_BLINK, 0.2 if side > 0 else 0.7))
            mb.box((0.04, 2.36, zc), (0.05, 0.3, 1.5), uvr("secteur"), ONE, PAINT, faces="f")
        elif bay == "console":
            mb.box((0.14, 1.3, zc - 0.3), (0.28, 0.7, 1.0), uvr("console"), ONE, PAINT, faces="fdltu",
                   uvs={k: uvr("mid") for k in "dltu"})
            mb.box((0.06, 0.6, zc - 0.3), (0.12, 0.6, 0.6), uvr("panel4"), ONE, PAINT, faces="fdlt")
            # conduite verticale jusqu'au gros tuyau, vanne à volant orange
            mb.cyl((0.09, 0.3, zc + 0.75), (0.09, 2.42, zc + 0.75), 0.045, uvr("pipe"), srgb("#b08a3a"), BARE, 10)
            mb.box((0.12, 1.25, zc + 0.75), (0.14, 0.22, 0.22), uvr("dark"), ONE, PAINT, faces="fdltu")
            mb.ring((0.2, 1.25, zc + 0.75), (1, 0, 0), 0.11, 0.135, 0.025, uvr("white"), srgb("#e07a2a"), PAINT, 14)
            for j in range(4):
                mb.box((0.29, 1.12 + 0.05 * j, zc - 0.55 + 0.17 * j), (0.02, 0.03, 0.05), uvr("white"),
                       [srgb("#7fe0a0"), srgb("#ffb347"), srgb("#7fd6ff"), srgb("#ffb347")][j], GLOW, faces="f", anim=(A_BLINK, 0.27 * j + 0.1 * side))
    # baies d'extrémité : grille de ventilation, coffret
    for zc in (RIB0 * 0.5, (RIB0 + (NRIB - 1) * RIBS + L) * 0.5):
        mb.box((0.05, 1.0, zc), (0.1, 0.9, 0.9), uvr("panel1"), ONE, PAINT, faces="fdltu", uvs={k: uvr("dark") for k in "dltu"})


def build_south(mb):
    """Garde-corps sud : muret bas à bandes, potelets, deux lisses ; fosse de service en contrebas."""
    mb.side = 1
    z0 = H - WALL
    x0, x1 = WALL, W - WALL

    def wbox(c, size, uv, col, cls=PAINT, faces="fbtudl", uvs=None):
        # boîte en coordonnées monde (x, y, z)
        x, y, z = c
        sx, sy, sz = size
        uvs = uvs or {}
        F = {
            "n": ((x, y, z - sz / 2), (-1, 0, 0), (0, 1, 0), sx / 2, sy / 2),   # face nord (vers l'arène)
            "s": ((x, y, z + sz / 2), (1, 0, 0), (0, 1, 0), sx / 2, sy / 2),
            "t": ((x, y + sy / 2, z), (1, 0, 0), (0, 0, -1), sx / 2, sz / 2),
            "e": ((x + sx / 2, y, z), (0, 0, -1), (0, 1, 0), sz / 2, sy / 2),
            "w": ((x - sx / 2, y, z), (0, 0, 1), (0, 1, 0), sz / 2, sy / 2),
        }
        for f in faces:
            if f in F:
                p, r, u, a, b = F[f]
                mb.quad(p, r, u, a, b, uvs.get(f, uv), col, cls, world=True)

    n = int((x1 - x0) / 1.5)
    seg = (x1 - x0) / n
    for i in range(n):
        xa = x0 + seg * (i + 0.5)
        wbox((xa, 0.11, z0 + 0.14), (seg, 0.22, 0.28), uvr("kick", (0, 0.1, 1, 0.9)), ONE, PAINT, "nt", {"t": uvr("dark")})
        wbox((xa, 0.006, z0 + 0.42), (seg, 0.012, 0.3), uvr("roof", (0, 0, 1, 0.2)), ONE, PAINT, "t")
    acc = srgb("#ff9a40") * 0.45
    wbox(((x0 + x1) / 2, 0.225, z0 + 0.005), (x1 - x0, 0.015, 0.012), uvr("white"), acc * 0.9, GLOW, "nt")
    # potelets et lisses (fins pour ne rien masquer)
    for i in range(n + 1):
        x = x0 + seg * i
        wbox((x, 0.55, z0 + 0.22), (0.05, 0.66, 0.05), uvr("dark"), ONE, PAINT, "nteswt")
    for (y, r, c) in ((0.88, 0.028, srgb("#c99a32")), (0.55, 0.018, srgb("#5b6475"))):
        p0 = np.array((x0, y, z0 + 0.22))
        p1 = np.array((x1, y, z0 + 0.22))
        mb.side = 1
        # tube monde (side = 1, XF décalé) : on passe par cyl en coordonnées locales -> monde
        for xa in np.linspace(x0, x1, 9)[:-1]:
            mb.cyl((xa - XF, y, z0 + 0.22), (xa + (x1 - x0) / 8 - XF, y, z0 + 0.22), r, uvr("pipe"), c, BARE, 10)
    # bord du pont et fosse de service
    wbox(((x0 + x1) / 2, -1.25, H), (W, 2.5, 0.01), uvr("dark"), (0.6, 0.6, 0.6), PAINT, "s")
    wbox((W / 2, -2.5, H + 3.0), (W, 0.01, 6.0), uvr("roof"), (0.5, 0.5, 0.6), PAINT, "t")
    for xs in np.arange(3.0, W, 6.0):
        wbox((xs, -2.48, H + 2.5), (2.0, 0.02, 0.05), uvr("white"), srgb("#5c8cff") * 0.8, GLOW, "t")


def main():
    os.makedirs(OUT, exist_ok=True)
    paint_atlas()
    mb, gl = MB(), MB()
    build_side(mb, gl, 1, BAYS_W)
    build_side(mb, gl, -1, BAYS_E)
    build_south(mb)
    write_glb(os.path.join(OUT, "shell_walls.glb"), [("walls", mb.arrays()), ("glass", gl.arrays())])
    u0, v0, u1, v1 = uvr("scroll")
    write_json(os.path.join(OUT, "wall_meta.json"), {"scroll": [u0, v0, u1 - u0, v1 - v0]})


if __name__ == "__main__":
    main()
