"""Pont du quai nord peint à la main (en code) : assets/decor/bay/bay_floor.png.
L'image couvre tout le quai : x de 0 à W = 37,5 m (gauche -> droite), z de 0 (mur nord, en haut) à TOP = 3,906 m
(garde-corps, en bas). Lue depuis la caméra de jeu (plein sud, en surplomb), le haut de l'image est au fond.
Les positions reprennent la disposition de scripts/decor/hangar_bay.gd (vaisseau, pompes, aire de posé)."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FONT = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")

WM, TM = 37.5, 250.0 / 64.0
WPX, HPX = 4096, 428
SX, SZ = WPX / WM, HPX / TM
CX = WM * 0.5
SHIP_X = CX + 0.2
PAD = (14.6, 0.5, 23.3, 3.22)  # aire de posé : x0, z0, x1, z1
WALK_Z = 3.36  # allée piétonne le long du garde-corps
rng = np.random.default_rng(1977)


def px(x, z):
    return (x * SX, z * SZ)


def noise(scale_m, seed, oct=4):
    """Bruit fractal (somme d'octaves de bruit de valeur agrandi en bicubique), dans [0, 1]."""
    r = np.random.default_rng(seed)
    out = np.zeros((HPX, WPX), dtype=np.float32)
    a, tot = 1.0, 0.0
    for i in range(oct):
        cw = max(2, int(WM / scale_m * 2 ** i))
        ch = max(2, int(TM / scale_m * 2 ** i))
        g = (r.random((ch, cw)) * 255).astype(np.uint8)
        up = np.asarray(Image.fromarray(g, "L").resize((WPX, HPX), Image.BICUBIC), dtype=np.float32) / 255.0
        out += a * up
        tot += a
        a *= 0.5
    return out / tot


def layer():
    return Image.new("RGBA", (WPX, HPX), (0, 0, 0, 0))


def comp(base, lay, wear=None):
    """Pose un calque peint sur le fond ; wear (0..1) efface la peinture par endroits."""
    L = np.asarray(lay, dtype=np.float32) / 255.0
    a = L[..., 3:4]
    if wear is not None:
        a = a * wear[..., None]
    return base * (1 - a) + L[..., :3] * a


def wear_mask(seed, amount=0.35, scale=0.5):
    n = noise(scale, seed, 5)
    fine = noise(0.04, seed + 9, 2)
    return np.clip(1.0 - np.clip((n * 0.7 + fine * 0.5 - (1.0 - amount)) * 4.0, 0, 1), 0, 1)


def stencil_text(d, xy, text, size, fill, anchor="mm", bridges=True):
    font = ImageFont.truetype(FONT, int(size))
    d.text(xy, text, font=font, fill=fill, anchor=anchor)
    if bridges:
        # ponts de pochoir : fines coupures verticales dans les lettres
        bb = d.textbbox(xy, text, font=font, anchor=anchor)
        return bb
    return None


def paint(out_dir):
    base = np.zeros((HPX, WPX, 3), dtype=np.float32)
    # ---- plaques d'acier : 1,5 m x 1,3 m, teinte propre à chaque plaque
    steel = np.array([44, 50, 66], dtype=np.float32) / 255.0
    pw, ph = 1.5, TM / 3.0
    for i in range(int(math.ceil(WM / pw)) + 1):
        for j in range(3):
            x0, z0 = i * pw - (0.75 if j == 1 else 0.0), j * ph
            k = 1.0 + rng.normal(0, 0.035)
            tint = steel * k * np.array([1.0, 1.0, 1.0 + rng.normal(0, 0.015)])
            a0, b0 = px(max(x0, 0), z0)
            a1, b1 = px(min(x0 + pw, WM), z0 + ph)
            base[int(b0):int(math.ceil(b1)), int(a0):int(math.ceil(a1))] = tint
    # aire de posé : acier plus clair et plus usé
    a0, b0 = px(PAD[0], PAD[1]); a1, b1 = px(PAD[2], PAD[3])
    base[int(b0):int(b1), int(a0):int(a1)] *= np.array([1.08, 1.08, 1.06])
    # allée : tôle larmée (losanges en relief)
    yy, xx = np.mgrid[0:HPX, 0:WPX].astype(np.float32)
    zw = yy / SZ
    xw = xx / SX
    walk = (zw > WALK_Z + 0.04)
    u = (xw * 22.0) % 1.0
    vv = (zw * 22.0 + np.floor(xw * 22.0) * 0.5) % 1.0
    dia = np.clip(1.0 - (np.abs(u - 0.5) * 2.6 + np.abs(vv - 0.5) * 1.3), 0, 1)
    base[walk] *= (0.92 + 0.22 * dia[walk])[:, None]
    # ---- salissures larges, taches, éraflures
    g = noise(1.2, 3, 5)
    base *= (0.86 + 0.24 * g)[..., None]
    f = noise(0.08, 4, 3)
    base *= (0.95 + 0.1 * f)[..., None]
    img = Image.fromarray(np.uint8(np.clip(base, 0, 1) * 255), "RGB")
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(900):
        x, y = rng.random() * WPX, rng.random() * HPX
        a = rng.normal(0, 0.35) + (math.pi / 2 if rng.random() < 0.25 else 0)
        L = rng.uniform(6, 40)
        c = int(rng.uniform(70, 110))
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=(c, c + 4, c + 12, 70), width=1)
    base = np.asarray(img, dtype=np.float32) / 255.0
    # ---- joints des plaques, rivets
    lay = layer()
    d = ImageDraw.Draw(lay)
    for i in range(int(math.ceil(WM / pw)) + 2):
        for j in range(3):
            x0, z0 = i * pw - (0.75 if j == 1 else 0.0), j * ph
            a0, b0 = px(x0, z0)
            a1, b1 = px(x0 + pw, z0 + ph)
            d.rectangle([a0, b0, a1, b1], outline=(14, 16, 24, 230), width=3)
            d.line([(a0 + 3, b0 + 3), (a1 - 3, b0 + 3)], fill=(92, 100, 122, 110), width=1)
            for (bx, bz) in ((x0 + 0.08, z0 + 0.08), (x0 + pw - 0.08, z0 + 0.08), (x0 + 0.08, z0 + ph - 0.08), (x0 + pw - 0.08, z0 + ph - 0.08), (x0 + pw * 0.5, z0 + 0.08), (x0 + pw * 0.5, z0 + ph - 0.08)):
                cx, cz = px(bx, bz)
                d.ellipse([cx - 3, cz - 3, cx + 3, cz + 3], fill=(22, 24, 32, 230))
                d.ellipse([cx - 2, cz - 2.5, cx + 1, cz], fill=(120, 128, 146, 160))
    base = comp(base, lay)
    # ---- grilles d'évacuation
    lay = layer()
    d = ImageDraw.Draw(lay)
    for gx, gz in ((5.2, 3.0), (8.0, 1.25), (27.4, 1.25), (36.0, 3.0)):
        a0, b0 = px(gx - 0.35, gz - 0.18); a1, b1 = px(gx + 0.35, gz + 0.18)
        d.rectangle([a0, b0, a1, b1], fill=(18, 20, 28, 255), outline=(80, 86, 104, 255), width=2)
        for k in range(9):
            xk = a0 + 6 + k * (a1 - a0 - 12) / 8
            d.line([(xk, b0 + 4), (xk, b1 - 4)], fill=(58, 62, 78, 255), width=2)
    base = comp(base, lay)
    # ---- brûlures des réacteurs sur l'aire, huile sous les pompes, traces de pneus
    lay = layer()
    d = ImageDraw.Draw(lay)
    for ez in (1.86 - 0.82, 1.86 + 0.82):
        for r, al in ((1.1, 40), (0.75, 60), (0.45, 80)):
            cx, cz = px(SHIP_X - 3.3, ez)
            d.ellipse([cx - r * SX * 1.3, cz - r * SZ * 0.8, cx + r * SX * 0.6, cz + r * SZ * 0.8], fill=(8, 8, 10, al))
    for ox, oz, r in ((13.6, 1.2, 0.5), (14.2, 1.6, 0.3), (24.6, 1.1, 0.45), (8.8, 2.4, 0.35), (30.5, 1.6, 0.4)):
        for k in range(6):
            cx, cz = px(ox + rng.normal(0, r * 0.5), oz + rng.normal(0, r * 0.3))
            rr = r * rng.uniform(0.25, 0.6) * SX
            d.ellipse([cx - rr, cz - rr * 0.7, cx + rr, cz + rr * 0.7], fill=(10, 12, 14, int(rng.uniform(40, 90))))
    # traces de pneus du chariot de fret, qui tournent vers l'aire
    for side in (-0.12, 0.12):
        pts = []
        for k in range(60):
            t = k / 59
            x = 36.0 - t * 11.5
            z = 1.4 + side + 0.9 * math.sin(t * math.pi * 0.9)
            pts.append(px(x, z))
        d.line(pts, fill=(12, 13, 18, 70), width=9)
    lay = lay.filter(ImageFilter.GaussianBlur(3))
    base = comp(base, lay)
    # ---- peintures : bordure de l'aire en bandes de danger, équerres d'angle, allée, flèches
    lay = layer()
    d = ImageDraw.Draw(lay)
    Y = (196, 160, 62, 255)
    K = (24, 24, 28, 255)
    bw = 0.2
    a0, b0 = px(PAD[0], PAD[1]); a1, b1 = px(PAD[2], PAD[3])
    bwp = bw * SX
    d.rectangle([a0, b0, a1, b1], outline=Y, width=int(bwp))
    # bandes noires obliques sur la bordure
    step = 0.32 * SX
    k = a0 - HPX
    while k < a1 + HPX:
        d.line([(k, b1 + 40), (k + (b1 - b0) + 80, b0 - 40)], fill=K, width=int(step * 0.45))
        k += step
    # on ne garde les bandes noires que sur la bordure : masque
    m = Image.new("L", (WPX, HPX), 0)
    md = ImageDraw.Draw(m)
    md.rectangle([a0, b0, a1, b1], outline=255, width=int(bwp))
    la = np.asarray(lay, dtype=np.float32)
    la[..., 3] *= np.asarray(m, dtype=np.float32) / 255.0
    lay = Image.fromarray(np.uint8(la), "RGBA")
    d = ImageDraw.Draw(lay)
    # équerres blanches et repère central de posé
    Wc = (206, 200, 184, 235)
    for (cx, cz, sx, sz) in ((PAD[0] + 0.45, PAD[1] + 0.45, 1, 1), (PAD[2] - 0.45, PAD[1] + 0.45, -1, 1), (PAD[0] + 0.45, PAD[3] - 0.45, 1, -1), (PAD[2] - 0.45, PAD[3] - 0.45, -1, -1)):
        p0 = px(cx, cz)
        d.line([p0, px(cx + sx * 0.7, cz)], fill=Wc, width=7)
        d.line([p0, px(cx, cz + sz * 0.5)], fill=Wc, width=7)
    # allée piétonne : lignes jaunes, pointillés
    z0 = WALK_Z
    d.line([px(0.6, z0), px(PAD[0] - 0.2, z0)], fill=Y, width=6)
    d.line([px(PAD[2] + 0.2, z0), px(WM - 0.6, z0)], fill=Y, width=6)
    x = PAD[0]
    while x < PAD[2]:
        d.line([px(x, z0 + 0.08), px(x + 0.35, z0 + 0.08)], fill=Y, width=5)
        x += 0.6
    # chevrons vers le sas (passage dans le garde-corps)
    for s in (-1, 1):
        for k in range(3):
            xc = CX + s * (2.3 + k * 0.45)
            zc = WALK_Z + 0.27
            pa = px(xc + s * 0.16, zc - 0.14)
            pb = px(xc - s * 0.08, zc)
            pc = px(xc + s * 0.16, zc + 0.14)
            d.line([pa, pb, pc], fill=Y, width=8, joint="curve")
    base = comp(base, lay, wear_mask(21, 0.4))
    # ---- inscriptions au pochoir : BAIE 07, 07, consignes
    lay = layer()
    d = ImageDraw.Draw(lay)
    cream = (150, 146, 134, 180)
    stencil_text(d, px(11.4, 2.75), "BAIE 07", 0.95 * SZ, cream)
    stencil_text(d, px(11.4, 1.78), "QUAI NORD  -  FRET LÉGER", 0.2 * SZ, (186, 180, 164, 200))
    stencil_text(d, px(25.6, 2.55), "07", 1.5 * SZ, cream)
    # consignes
    small = (196, 168, 80, 220)
    stencil_text(d, px(13.25, 0.48), "CARBURANT", 0.16 * SZ, small)
    stencil_text(d, px(24.4, 0.48), "ÉNERGIE SOL", 0.16 * SZ, small)
    stencil_text(d, px(19.25, 0.34), "AIRE DE POSÉ  07  -  MAX 40 T", 0.15 * SZ, (190, 184, 168, 190))
    stencil_text(d, px(2.6, 3.15), "ZONE DE STOCKAGE", 0.16 * SZ, small)
    stencil_text(d, px(30.4, 3.12), "NE PAS STATIONNER", 0.16 * SZ, small)
    base = comp(base, lay, wear_mask(33, 0.3, 0.35))
    # ---- logo de la compagnie de fret HÉLIX FRET (HXF) : hexagone, double hélice, même dessin que le sol
    # de l'arène (tools/decor/shell_floor.py) ; blanc cassé et orange passés (le quai reste sombre)
    lay = layer()
    d = ImageDraw.Draw(lay)
    lc = (176, 172, 160, 215)
    hc = (190, 120, 52, 225)
    cx, cz = 33.3, 1.72
    rr = 0.56
    hexa = [px(cx + rr * math.cos(math.pi / 6 + k * math.pi / 3), cz + rr * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    d.line(hexa + [hexa[0]], fill=lc, width=int(0.065 * SZ), joint="curve")
    for ph0 in (0.0, math.pi):
        pts = [px(cx + rr * 0.55 * math.sin(t * 2.2 * math.pi + ph0), cz - rr * 0.75 + t * rr * 1.5) for t in np.linspace(0, 1, 40)]
        d.line(pts, fill=hc, width=int(0.055 * SZ), joint="curve")
    for k in range(5):
        zk = cz - rr * 0.6 + k * rr * 0.3
        t = (zk - (cz - rr * 0.75)) / (rr * 1.5)
        xa = rr * 0.55 * math.sin(t * 2.2 * math.pi)
        d.line([px(cx - abs(xa), zk), px(cx + abs(xa), zk)], fill=hc, width=int(0.022 * SZ))
    stencil_text(d, px(cx, 2.68), "HÉLIX FRET", 0.34 * SZ, lc, bridges=False)
    sub = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Rajdhani-Bold.ttf"), int(0.15 * SZ))
    d.text(px(cx, 3.0), "TRANSIT  NÉBULEUSE 7", font=sub, fill=lc, anchor="mm")
    base = comp(base, lay, wear_mask(47, 0.18, 0.3))
    # ---- assombrissement au pied du mur (le quai reste plus sombre que l'aire de jeu)
    zz = np.linspace(0, TM, HPX)[:, None]
    shade = 0.78 + 0.22 * np.clip(zz / 1.2, 0, 1)
    base *= shade[..., None]
    img = Image.fromarray(np.uint8(np.clip(base, 0, 1) * 255), "RGB")
    img.save(os.path.join(out_dir, "bay_floor.png"))
    print("bay_floor.png", img.size)


if __name__ == "__main__":
    paint(os.path.join(ROOT, "assets", "decor", "bay"))
