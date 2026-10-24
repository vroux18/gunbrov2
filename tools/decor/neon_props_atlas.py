"""Planche de marquages des objets de la Cité Néon (assets/decor/neon/props/decals.png) : logo et pochoirs de la
compagnie de livraison inventée PAKKU EXPRESS (cube arrondi lancé, traînée de vitesse), idéogrammes inventés
(aucune vraie langue), grilles d'aération et de ventilateur, avertissements électriques, vitrines des
distributeurs, menu du kiosque, autocollants, graffitis au sol (motifs abstraits). Les objets sculptés
(neon_props.py) y posent des quads fins collés à leurs faces planes.

Usage : python3 tools/decor/neon_props_atlas.py   (aussi appelé par neon_props.py)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "decor", "neon", "props", "decals.png")
FONT = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")
FONT2 = os.path.join(ROOT, "assets", "fonts", "Rajdhani-Bold.ttf")
SIZE = 1024
SS = 2  # suréchantillonnage

CREAM = (206, 200, 184)
INK = (34, 34, 42)
ORANGE = (226, 128, 62)
YELLOW = (206, 160, 52)
BLACK = (24, 24, 30)
PINK = (255, 60, 172)
BLUE = (60, 140, 255)
VIOLET = (142, 76, 255)
GREEN = (182, 255, 60)
TEAL = (60, 220, 200)

# régions (x, y, w, h) en pixels de la planche
R = {
    "pakku": (0, 0, 256, 256),          # logo crème et orange
    "pakku_k": (256, 0, 256, 256),      # logo sombre (sur coques claires)
    "word": (512, 0, 512, 128),         # PAKKU EXPRESS crème
    "word_k": (512, 128, 512, 128),     # PAKKU EXPRESS sombre
    "gly": (0, 256, 512, 128),          # 4 idéogrammes inventés, crème
    "gly_lit": (512, 256, 512, 128),    # 4 idéogrammes, blancs sur fond transparent (enseigne lumineuse)
    "haz": (0, 384, 512, 64),           # bandes de danger
    "line": (0, 448, 512, 64),          # ligne de pochoir (idéogrammes et code)
    "vent": (512, 384, 128, 128),       # grille à lames (opaque)
    "volt": (640, 384, 128, 128),       # triangle d'avertissement électrique
    "fan": (768, 384, 256, 256),        # grille de ventilateur (anneaux et rayons, ajourée)
    "vend": (0, 512, 256, 256),         # vitrine de distributeur (rangées de canettes), lumineuse
    "menu": (256, 512, 256, 256),       # menu du kiosque : bol, idéogrammes, prix, lumineux
    "tag": (512, 512, 256, 128),        # étiquette de livraison PAKKU
    "sticker": (512, 640, 128, 128),    # autocollants (pastille, éclair, œil)
    "scuff": (640, 640, 128, 128),      # tache d'usure sombre
    "drip": (768, 640, 64, 128),        # coulure de rouille / d'eau
    "tape": (832, 640, 128, 32),        # ruban adhésif
    "K-12": (832, 672, 192, 64), "R-07": (832, 736, 192, 64),
    "btn": (768, 800, 64, 128),         # colonne de boutons du distributeur (lumineuse)
    "egout": (832, 800, 128, 128),      # dessus de plaque d'égout (fonte à motifs, couronne d'idéogrammes)
    "graf1": (0, 768, 256, 256), "graf2": (256, 768, 256, 256), "graf3": (512, 768, 256, 256),
    "grate": (768, 928, 128, 64),       # grille d'égout (fentes)
    "gly_v": (896, 928, 64, 64),        # idéogramme seul (lanterne)
    "stripe": (960, 928, 64, 64),       # bande réfléchissante (cônes)
    "dot": (768, 768, 32, 32),          # pastille lumineuse floue
}


def _noise(w, h, seed, scale):
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp = 1.0
    tot = 0.0
    for o in range(4):
        s = max(2, int(scale * (2 ** o)))
        g = rng.random((s, s))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, dtype=np.float64) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def _wear(img, seed, amount=0.38, scale=6):
    """Ronge l'alpha (peinture écaillée) : bruit à plusieurs octaves seuillé."""
    a = np.asarray(img, dtype=np.float64).copy()
    n = _noise(img.width, img.height, seed, scale)
    keep = np.clip((n - amount) / 0.06, 0, 1)
    a[..., 3] *= keep
    a[..., :3] *= (0.88 + 0.12 * _noise(img.width, img.height, seed + 1, scale * 3))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def _canvas(w, h, bg=(0, 0, 0, 0)):
    return Image.new("RGBA", (w * SS, h * SS), bg)


def _down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


# ------------------------------------------------------------------ idéogrammes inventés
def _component(rng, x0, y0, w, h, n):
    """Traits d'un composant d'idéogramme dans la case (x0, y0, w, h) (unités du carré) : barres courtes,
    montants, petit cadre, obliques tombantes, points."""
    out = []
    gx = lambda i: x0 + w * (0.1 + 0.8 * i / 2.0)
    gy = lambda j: y0 + h * (0.1 + 0.8 * j / 2.0)
    for _ in range(n):
        k = rng.choice(["h", "h", "v", "box", "fall", "dot", "hv"])
        a = int(rng.integers(0, 3))
        if k == "h":
            out.append([(gx(0), gy(a)), (gx(2), gy(a))])
        elif k == "v":
            j0 = int(rng.integers(0, 2))
            out.append([(gx(a), gy(j0)), (gx(a), gy(2))])
        elif k == "box":
            out.append([(gx(0), gy(0.6)), (gx(2), gy(0.6)), (gx(2), gy(2)), (gx(0), gy(2)), (gx(0), gy(0.6))])
        elif k == "fall":
            s = 1 if rng.random() < 0.5 else -1
            out.append([(gx(1), gy(1)), (gx(1 + s), gy(2))])
        elif k == "hv":
            out.append([(gx(0), gy(a)), (gx(2), gy(a)), (gx(2), gy(min(2, a + 1.5)))])
        else:
            out.append([(gx(a), gy(0)), (gx(a) + w * 0.06, gy(0) + h * 0.08)])
    return out


def glyph(d, x, y, s, seed, col, wgt=0.11):
    """Un idéogramme inventé dans le carré (x, y, s) : deux composants (gauche-droite, haut-bas ou cadre
    et intérieur) de traits courts, épaisseur constante. Aucune vraie écriture."""
    rng = np.random.default_rng(seed)
    w = max(2, int(s * wgt))
    lay = rng.choice(["lr", "lr", "tb", "frame"])
    strokes = []
    if lay == "lr":
        sp = rng.uniform(0.32, 0.42)
        strokes += _component(rng, 0.0, 0.0, sp, 1.0, int(rng.integers(2, 4)))
        strokes += _component(rng, sp, 0.0, 1.0 - sp, 1.0, int(rng.integers(3, 5)))
    elif lay == "tb":
        sp = rng.uniform(0.35, 0.45)
        strokes += _component(rng, 0.0, 0.0, 1.0, sp, int(rng.integers(2, 3)))
        strokes += _component(rng, 0.0, sp, 1.0, 1.0 - sp, int(rng.integers(3, 5)))
    else:
        strokes.append([(0.12, 0.92), (0.12, 0.1), (0.88, 0.1), (0.88, 0.92)])
        strokes += _component(rng, 0.22, 0.2, 0.56, 0.7, int(rng.integers(2, 4)))
    m = 0.08
    for pts in strokes:
        pts = [(x + s * (m + (1 - 2 * m) * px), y + s * (m + (1 - 2 * m) * py)) for px, py in pts]
        d.line(pts, fill=col, width=w, joint="curve")
        for p in (pts[0], pts[-1]):
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=col)


def glyph_row(w, h, seeds, col, wgt=0.11):
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    n = len(seeds)
    s = min(h * SS * 0.86, w * SS / n * 0.9)
    gap = (w * SS - n * s) / (n + 1)
    for i, sd in enumerate(seeds):
        glyph(d, gap + i * (s + gap), (h * SS - s) / 2, s, sd, col + (255,), wgt)
    return _down(im, w, h)


# ------------------------------------------------------------------ PAKKU EXPRESS
def pakku(w, col, col2):
    """Logo PAKKU EXPRESS : cube arrondi vu de trois quarts (colis), trois traits de vitesse à gauche."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    cx, cy, r = s * 0.58, s * 0.52, s * 0.3
    top = [(cx, cy - r), (cx + r * 0.87, cy - r * 0.5), (cx, cy), (cx - r * 0.87, cy - r * 0.5)]
    left = [(cx - r * 0.87, cy - r * 0.5), (cx, cy), (cx, cy + r), (cx - r * 0.87, cy + r * 0.5)]
    right = [(cx, cy), (cx + r * 0.87, cy - r * 0.5), (cx + r * 0.87, cy + r * 0.5), (cx, cy + r)]
    d.polygon(top, fill=col + (255,))
    d.polygon(left, fill=col2 + (255,))
    d.polygon(right, fill=col + (255,))
    lw = int(s * 0.035)
    d.line(top + [top[0]], fill=col2 + (255,), width=lw, joint="curve")
    d.line([(cx, cy), (cx, cy + r)], fill=col2 + (255,), width=lw)
    # ruban sur le dessus
    d.line([(cx - r * 0.43, cy - r * 0.75), (cx + r * 0.43, cy - r * 0.25)], fill=col2 + (255,), width=lw)
    # traits de vitesse
    for k, ln in enumerate((0.34, 0.26, 0.18)):
        y = cy - r * 0.2 + k * r * 0.42
        x1 = cx - r * 1.08
        d.rounded_rectangle((x1 - s * ln, y - s * 0.025, x1, y + s * 0.025), radius=int(s * 0.025), fill=col2 + (255,))
    # contour arrondi (pastille)
    d.arc((s * 0.06, s * 0.06, s * 0.94, s * 0.94), 200, 520, fill=col + (255,), width=int(s * 0.03))
    return _down(im, w, w)


def text_img(txt, w, h, col, font=FONT, fill=0.78):
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    size = int(h * SS * fill)
    f = ImageFont.truetype(font, size)
    while True:
        bb = d.textbbox((0, 0), txt, font=f)
        if bb[2] - bb[0] <= w * SS * 0.94 or size < 8:
            break
        size = int(size * 0.94)
        f = ImageFont.truetype(font, size)
    bb = d.textbbox((0, 0), txt, font=f)
    x = (w * SS - (bb[2] - bb[0])) * 0.5 - bb[0]
    y = (h * SS - (bb[3] - bb[1])) * 0.5 - bb[1]
    d.text((x, y), txt, font=f, fill=col + (255,))
    return _down(im, w, h)


def tag(w, h, seed=5):
    """Étiquette de livraison : carte crème, bande rose éteint, code-barres, idéogrammes, petit logo."""
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    S = SS
    rng = np.random.default_rng(seed)
    d.rounded_rectangle((2 * S, 2 * S, (w - 2) * S, (h - 2) * S), radius=6 * S, fill=(214, 208, 192, 255))
    d.rounded_rectangle((2 * S, 2 * S, 34 * S, (h - 2) * S), radius=6 * S, fill=(196, 74, 128, 255))
    x = 46 * S
    bx = x
    while bx < (w - 14) * S:
        bw = int(rng.integers(1, 4)) * S * 2
        d.rectangle((bx, 66 * S, bx + bw, (h - 12) * S), fill=INK + (255,))
        bx += bw + int(rng.integers(1, 3)) * S * 2
    f = ImageFont.truetype(FONT2, 26 * S)
    d.text((x, 8 * S), "PAKKU  9-K12", font=f, fill=INK + (255,))
    for i in range(5):
        glyph(d, x + i * 30 * S, 38 * S, 24 * S, 300 + i, INK + (255,), 0.13)
    return _wear(_down(im, w, h), seed + 50, amount=0.1, scale=5)


# ------------------------------------------------------------------ technique
def hazard(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), YELLOW + (255,))
    d = ImageDraw.Draw(im)
    per = w * SS / 8
    for k in range(-2, 10):
        x = k * per
        d.polygon([(x, h * SS), (x + per * 0.5, h * SS), (x + per * 0.5 + h * SS, 0), (x + h * SS, 0)], fill=BLACK + (255,))
    return _down(im, w, h)


def vent(w):
    """Grille à lames : cadre gris sombre, fentes noires, liseré clair sous chaque lame (lumière)."""
    im = Image.new("RGBA", (w * SS, w * SS), (66, 70, 80, 255))
    d = ImageDraw.Draw(im)
    s = w * SS
    n = 7
    for k in range(n):
        y = s * (0.08 + k * 0.84 / n)
        d.rectangle((s * 0.06, y, s * 0.94, y + s * 0.07), fill=(14, 15, 20, 255))
        d.rectangle((s * 0.06, y + s * 0.07, s * 0.94, y + s * 0.085), fill=(104, 110, 122, 255))
    return _down(im, w, w)


def volt(w):
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    tri = [(s * 0.5, s * 0.08), (s * 0.95, s * 0.88), (s * 0.05, s * 0.88)]
    d.polygon(tri, fill=YELLOW + (255,))
    d.line(tri + [tri[0]], fill=BLACK + (255,), width=int(s * 0.05), joint="curve")
    c = s * 0.5
    bolt = [(c + s * 0.06, s * 0.3), (c - s * 0.12, c + s * 0.12), (c, c + s * 0.12), (c - s * 0.06, s * 0.8),
            (c + s * 0.13, c + s * 0.0), (c + s * 0.01, c + s * 0.0)]
    d.polygon(bolt, fill=BLACK + (255,))
    return _down(im, w, w)


def fan_guard(w):
    """Grille de ventilateur vue de dessus : anneaux concentriques, rayons, moyeu ; le reste transparent
    (les pales tournent dessous)."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    c = s / 2
    col = (40, 42, 48, 255)
    for k in range(1, 8):
        r = s * 0.48 * k / 7
        d.ellipse((c - r, c - r, c + r, c + r), outline=col, width=int(s * (0.012 if k < 7 else 0.03)))
    for k in range(8):
        a = k * math.pi / 4
        d.line([(c, c), (c + math.cos(a) * s * 0.48, c + math.sin(a) * s * 0.48)], fill=col, width=int(s * 0.016))
    r = s * 0.1
    d.ellipse((c - r, c - r, c + r, c + r), fill=(54, 56, 62, 255))
    d.ellipse((c - r * 0.45, c - r * 0.45, c + r * 0.45, c + r * 0.45), fill=(90, 94, 102, 255))
    return _down(im, w, w)


def grate(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), (38, 40, 46, 255))
    d = ImageDraw.Draw(im)
    for k in range(9):
        x = (6 + k * (w - 12) / 9) * SS
        d.rounded_rectangle((x + 2 * SS, 8 * SS, x + (w - 12) / 9 * SS - 3 * SS, (h - 8) * SS), radius=3 * SS, fill=(8, 9, 12, 255))
    return _down(im, w, h)


def stripe(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), (210, 214, 218, 255))
    return _wear(_down(im, w, h), 61, 0.18, 7)


# ------------------------------------------------------------------ lumineux : vitrine, menu, boutons
def vend(w, seed=7):
    """Vitrine de distributeur : fond blanc bleuté, quatre rangées de canettes et bouteilles aux couleurs
    douces, étiquettes de prix ; rendu lumineux (l'ensemble reste clair mais peu saturé)."""
    im = Image.new("RGBA", (w * SS, w * SS), (200, 214, 230, 255))
    d = ImageDraw.Draw(im)
    s = w * SS
    rng = np.random.default_rng(seed)
    cols = [(222, 120, 150), (120, 170, 220), (160, 210, 120), (230, 180, 100), (170, 140, 220), (230, 230, 236), (120, 200, 190)]
    rows = 4
    for r in range(rows):
        y0 = s * (0.05 + r * 0.235)
        d.rectangle((0, y0 + s * 0.17, s, y0 + s * 0.2), fill=(150, 160, 178, 255))
        n = 6
        for k in range(n):
            x0 = s * (0.04 + k * 0.155)
            c = cols[int(rng.integers(0, len(cols)))]
            if rng.random() < 0.5:
                d.rounded_rectangle((x0, y0 + s * 0.03, x0 + s * 0.11, y0 + s * 0.17), radius=int(s * 0.02), fill=c + (255,))
                d.rectangle((x0, y0 + s * 0.08, x0 + s * 0.11, y0 + s * 0.11), fill=(250, 250, 250, 255))
            else:
                d.rounded_rectangle((x0 + s * 0.025, y0, x0 + s * 0.085, y0 + s * 0.04), radius=int(s * 0.01), fill=c + (255,))
                d.rounded_rectangle((x0 + s * 0.01, y0 + s * 0.035, x0 + s * 0.1, y0 + s * 0.17), radius=int(s * 0.03), fill=c + (255,))
            d.rectangle((x0 + s * 0.02, y0 + s * 0.18, x0 + s * 0.09, y0 + s * 0.195), fill=(60, 64, 80, 255))
    # reflet diagonal sur la vitre
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.polygon([(s * 0.55, 0), (s * 0.75, 0), (s * 0.25, s), (s * 0.05, s)], fill=(255, 255, 255, 60))
    im.alpha_composite(ov)
    return _down(im, w, w)


def menu(w, seed=9):
    """Menu du kiosque à ramen : panneau sombre chaud, grand bol fumant, colonnes d'idéogrammes, prix."""
    im = Image.new("RGBA", (w * SS, w * SS), (52, 30, 34, 255))
    d = ImageDraw.Draw(im)
    s = w * SS
    d.rounded_rectangle((s * 0.03, s * 0.03, s * 0.97, s * 0.97), radius=int(s * 0.05), outline=(255, 150, 70, 255), width=int(s * 0.02))
    # bol
    cx, cy = s * 0.5, s * 0.42
    d.chord((cx - s * 0.3, cy - s * 0.22, cx + s * 0.3, cy + s * 0.26), 0, 180, fill=(235, 90, 70, 255))
    d.rectangle((cx - s * 0.31, cy - s * 0.0, cx + s * 0.31, cy + s * 0.03), fill=(250, 230, 200, 255))
    d.ellipse((cx - s * 0.1, cy + s * 0.23, cx + s * 0.1, cy + s * 0.27), fill=(235, 90, 70, 255))
    # nouilles et baguettes
    for k in range(3):
        x = cx - s * 0.12 + k * s * 0.08
        d.arc((x - s * 0.05, cy - s * 0.12, x + s * 0.05, cy + s * 0.02), 180, 360, fill=(250, 220, 140, 255), width=int(s * 0.015))
    d.line([(cx + s * 0.05, cy - s * 0.02), (cx + s * 0.32, cy - s * 0.24)], fill=(230, 200, 160, 255), width=int(s * 0.02))
    d.line([(cx + s * 0.1, cy - s * 0.0), (cx + s * 0.36, cy - s * 0.19)], fill=(230, 200, 160, 255), width=int(s * 0.02))
    # vapeur
    for k in range(3):
        x = cx - s * 0.12 + k * s * 0.12
        d.arc((x - s * 0.04, cy - s * 0.36, x + s * 0.04, cy - s * 0.24), 90, 270, fill=(255, 240, 230, 255), width=int(s * 0.014))
        d.arc((x - s * 0.04, cy - s * 0.26, x + s * 0.04, cy - s * 0.14), 270, 450, fill=(255, 240, 230, 255), width=int(s * 0.014))
    # lignes du menu
    for r in range(2):
        y = s * (0.74 + r * 0.11)
        for k in range(3):
            glyph(d, s * (0.08 + k * 0.09), y, s * 0.08, 400 + r * 7 + k, (255, 220, 190, 255), 0.13)
        f = ImageFont.truetype(FONT2, int(s * 0.08))
        d.text((s * 0.66, y - s * 0.005), "%d0" % (5 + r * 3), font=f, fill=(255, 170, 90, 255))
    return _down(im, w, w)


def buttons(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), (40, 42, 52, 255))
    d = ImageDraw.Draw(im)
    s = w * SS
    cols = [(255, 120, 190), (140, 190, 255), (190, 255, 120), (255, 190, 120), (200, 160, 255), (255, 255, 255)]
    for k in range(6):
        y = (10 + k * (h - 20) / 6) * SS
        d.rounded_rectangle((s * 0.2, y, s * 0.8, y + (h - 20) / 6 * SS * 0.62), radius=int(s * 0.1), fill=cols[k] + (255,))
    return _down(im, w, h)


def egout(w):
    """Plaque d'égout vue de dessus : fonte sombre, couronne d'idéogrammes en relief, quadrillage de plots,
    anneaux, deux trous de levage ; le relief est peint plus clair (lisible de loin)."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    c = s / 2
    hi = (118, 120, 130, 255)
    d.ellipse((s * 0.01, s * 0.01, s * 0.99, s * 0.99), fill=(46, 48, 56, 255))
    d.ellipse((s * 0.04, s * 0.04, s * 0.96, s * 0.96), outline=hi, width=int(s * 0.025))
    d.ellipse((s * 0.27, s * 0.27, s * 0.73, s * 0.73), outline=hi, width=int(s * 0.02))
    for k in range(10):
        a = k * 2 * math.pi / 10
        x, y = c + math.cos(a) * s * 0.37, c + math.sin(a) * s * 0.37
        glyph(d, x - s * 0.05, y - s * 0.05, s * 0.1, 950 + k, hi, 0.16)
    for i in range(-3, 4):
        for j in range(-3, 4):
            x, y = c + i * s * 0.055, c + j * s * 0.055
            if (x - c) ** 2 + (y - c) ** 2 < (s * 0.2) ** 2:
                d.rectangle((x - s * 0.014, y - s * 0.014, x + s * 0.014, y + s * 0.014), fill=hi)
    for sx in (-1, 1):
        d.rounded_rectangle((c + sx * s * 0.3 - s * 0.03, c - s * 0.012, c + sx * s * 0.3 + s * 0.03, c + s * 0.012), radius=int(s * 0.01), fill=(10, 10, 14, 255))
    return _wear(_down(im, w, w), 72, 0.08, 6)


def sticker(w):
    """Quatre autocollants : pastille rose à œil, éclair vert, rond violet, carré à idéogramme."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    q = s / 2
    d.ellipse((q * 0.08, q * 0.08, q * 0.92, q * 0.92), fill=(200, 70, 140, 255))
    d.ellipse((q * 0.3, q * 0.38, q * 0.7, q * 0.62), fill=(240, 240, 240, 255))
    d.ellipse((q * 0.43, q * 0.42, q * 0.57, q * 0.58), fill=BLACK + (255,))
    d.rounded_rectangle((q * 1.08, q * 0.1, q * 1.92, q * 0.9), radius=int(q * 0.1), fill=(40, 40, 46, 255))
    d.polygon([(q * 1.55, q * 0.2), (q * 1.3, q * 0.55), (q * 1.48, q * 0.55), (q * 1.4, q * 0.82), (q * 1.7, q * 0.42), (q * 1.52, q * 0.42)], fill=(170, 230, 70, 255))
    d.ellipse((q * 0.1, q * 1.1, q * 0.9, q * 1.9), fill=(120, 80, 200, 255))
    d.ellipse((q * 0.3, q * 1.3, q * 0.7, q * 1.7), outline=(240, 240, 240, 255), width=int(q * 0.06))
    d.rounded_rectangle((q * 1.1, q * 1.1, q * 1.9, q * 1.9), radius=int(q * 0.08), fill=(230, 222, 200, 255))
    glyph(d, q * 1.2, q * 1.2, q * 0.6, 777, BLACK + (255,), 0.13)
    return _wear(_down(im, w, w), 81, 0.16, 5)


def scuff(w, seed=3):
    n = _noise(w, w, seed, 5)
    yy, xx = np.mgrid[0:w, 0:w] / (w - 1) - 0.5
    rad = np.clip(1 - np.sqrt(xx ** 2 + yy ** 2) * 2.1, 0, 1)
    a = np.clip((n - 0.45) * 3.0, 0, 1) * rad * 150
    img = np.zeros((w, w, 4))
    img[..., :3] = (18, 18, 22)
    img[..., 3] = a
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def drip(w, h, seed=4):
    """Coulures verticales (rouille et crasse) : traînées fines qui s'effilent vers le bas."""
    rng = np.random.default_rng(seed)
    a = np.zeros((h, w))
    yy = np.arange(h)[:, None] / (h - 1)
    xx = np.arange(w)[None, :]
    for k in range(7):
        x0 = rng.uniform(0.1, 0.9) * w
        ln = rng.uniform(0.35, 1.0)
        wd = rng.uniform(1.0, 3.5)
        prof = np.clip(1 - yy / ln, 0, 1) ** 0.7
        a = np.maximum(a, np.exp(-((xx - x0) / wd) ** 2) * prof * rng.uniform(0.5, 0.9))
    img = np.zeros((h, w, 4))
    img[..., :3] = (70, 44, 30)
    img[..., 3] = np.clip(a, 0, 1) * 200
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def tape(w, h):
    a = np.zeros((h, w, 4))
    a[..., :3] = (60, 62, 70)
    yy = np.abs(np.arange(h) / (h - 1) - 0.5)[:, None]
    a[..., :3] *= (1 - 0.25 * (yy > 0.38))[..., None]
    a[..., 3] = 230
    img = Image.fromarray(a.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    for k in range(4):
        x = 8 + k * 30
        d.rectangle((x, 10, x + 16, 21), fill=(196, 74, 128, 230))
    return img


def dot(w):
    yy, xx = np.mgrid[0:w, 0:w] / (w - 1) - 0.5
    r = np.sqrt(xx ** 2 + yy ** 2) * 2
    img = np.zeros((w, w, 4))
    img[..., :3] = 255
    img[..., 3] = np.clip(1 - r, 0, 1) ** 1.5 * 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ graffitis au sol (motifs abstraits)
def _spray(im, seed, amount=0.5):
    """Bord de bombe : alpha adouci et moucheté, gouttelettes autour."""
    a = np.asarray(im, dtype=np.float64).copy()
    al = Image.fromarray(a[..., 3].astype(np.uint8)).filter(ImageFilter.GaussianBlur(3 * SS / 2))
    al = np.asarray(al, dtype=np.float64)
    n = _noise(im.width, im.height, seed, 24)
    al = al * np.clip(0.55 + n * 0.7, 0, 1)
    a[..., 3] = np.clip(al, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def graffiti(w, h, seed, palette):
    """Motif abstrait à la bombe : rubans courbes, cercles, éclats, gouttes ; deux ou trois couleurs, usé
    par le passage (alpha rongé), jamais de texte."""
    rng = np.random.default_rng(seed)
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    S = SS
    W, H = w * S, h * S
    c1, c2 = palette[0], palette[1]
    c3 = palette[2] if len(palette) > 2 else palette[0]

    def stroke(pts, rad, col):
        # trait de bombe : tampons ronds serrés le long du chemin (pas de jointures cassées)
        for (xa, ya), (xb, yb) in zip(pts[:-1], pts[1:]):
            n = max(2, int(math.hypot(xb - xa, yb - ya) / max(rad * 0.3, 1)))
            for t in np.linspace(0, 1, n):
                x, y = xa + (xb - xa) * t, ya + (yb - ya) * t
                d.ellipse((x - rad, y - rad, x + rad, y + rad), fill=col + (255,))

    # ruban principal : grande courbe en S, contour clair puis cœur
    ph = rng.uniform(0, 3)
    pts = [(W * (0.12 + 0.76 * t), H * (0.52 + 0.2 * math.sin(t * math.pi * 1.6 + ph))) for t in np.linspace(0, 1, 30)]
    stroke(pts, H * 0.085, c1)
    stroke(pts, H * 0.04, c2)
    # anneaux et pastilles
    for k in range(int(rng.integers(2, 4))):
        r = H * rng.uniform(0.06, 0.13)
        x, y = W * rng.uniform(0.18, 0.82), H * rng.uniform(0.18, 0.82)
        if k % 2 == 0:
            d.ellipse((x - r, y - r, x + r, y + r), outline=c3 + (255,), width=int(r * 0.4))
        else:
            d.ellipse((x - r, y - r, x + r, y + r), fill=c3 + (255,))
    # flèche abstraite (chevrons) et gouttes qui coulent sous le ruban
    x, y = W * rng.uniform(0.55, 0.75), H * rng.uniform(0.15, 0.25)
    stroke([(x, y), (x + W * 0.08, y + H * 0.07), (x, y + H * 0.14)], H * 0.022, c2)
    stroke([(x + W * 0.07, y), (x + W * 0.15, y + H * 0.07), (x + W * 0.07, y + H * 0.14)], H * 0.022, c2)
    for k in range(4):
        px, py = pts[int(rng.integers(3, 27))]
        stroke([(px, py), (px, py + H * rng.uniform(0.08, 0.18))], H * 0.012, c1)
    # éclaboussures
    for k in range(14):
        r = H * rng.uniform(0.005, 0.014)
        x, y = W * rng.uniform(0.05, 0.95), H * rng.uniform(0.05, 0.95)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(c1 if k % 2 else c3) + (255,))
    img = _spray(im, seed)
    img = _down(img, w, h)
    return _wear(img, seed + 9, amount=0.3, scale=7)


def build():
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    def put(key, img):
        x, y, w, h = R[key]
        atlas.alpha_composite(img.resize((w, h), Image.LANCZOS) if img.size != (w, h) else img, (x, y))

    # contrôle : aucune région ne déborde ni ne chevauche une autre
    occ = np.zeros((SIZE, SIZE), dtype=np.int32)
    for k, (x, y, w, h) in R.items():
        assert x + w <= SIZE and y + h <= SIZE, k
        occ[y:y + h, x:x + w] += 1
    assert occ.max() <= 1, "régions qui se chevauchent"

    put("pakku", _wear(pakku(256, CREAM, ORANGE), 1, 0.18))
    put("pakku_k", _wear(pakku(256, (46, 48, 58), (196, 74, 128)), 2, 0.16))
    put("word", _wear(text_img("PAKKU EXPRESS", 512, 128, CREAM, fill=0.7), 3, 0.24, 11))
    put("word_k", _wear(text_img("PAKKU EXPRESS", 512, 128, (40, 42, 50), fill=0.7), 4, 0.28, 9))
    put("gly", _wear(glyph_row(512, 128, [11, 12, 13, 14], CREAM), 5, 0.22, 9))
    put("gly_lit", glyph_row(512, 128, [21, 22, 23, 24], (255, 255, 255), 0.12))
    put("haz", _wear(hazard(512, 64), 7, 0.18, 10))
    line = _canvas(512, 64)
    ld = ImageDraw.Draw(line)
    for i in range(6):
        glyph(ld, (12 + i * 50) * SS, 10 * SS, 44 * SS, 600 + i, CREAM + (255,), 0.13)
    f = ImageFont.truetype(FONT2, 44 * SS)
    ld.text((330 * SS, 6 * SS), "N-3 / 220", font=f, fill=CREAM + (255,))
    put("line", _wear(_down(line, 512, 64), 8, 0.26, 10))
    put("vent", vent(128))
    put("volt", _wear(volt(128), 9, 0.12, 5))
    put("fan", fan_guard(256))
    put("vend", vend(256))
    put("menu", menu(256))
    put("tag", tag(256, 128))
    put("sticker", sticker(128))
    put("scuff", scuff(128))
    put("drip", drip(64, 128))
    put("tape", tape(128, 32))
    put("K-12", _wear(text_img("K-12", 192, 64, CREAM, fill=0.8), 20, 0.24, 9))
    put("R-07", _wear(text_img("R-07", 192, 64, CREAM, fill=0.8), 21, 0.24, 9))
    put("btn", buttons(64, 128))
    put("egout", egout(128))
    put("graf1", graffiti(256, 256, 31, [(255, 60, 172), (142, 76, 255), (60, 220, 200)]))
    put("graf2", graffiti(256, 256, 32, [(182, 255, 60), (60, 140, 255)]))
    put("graf3", graffiti(256, 256, 33, [(142, 76, 255), (255, 138, 60), (255, 60, 172)]))
    put("grate", grate(128, 64))
    gv = _canvas(64, 64)
    glyph(ImageDraw.Draw(gv), 8 * SS, 8 * SS, 48 * SS, 901, (60, 30, 24, 255), 0.14)
    put("gly_v", _down(gv, 64, 64))
    put("stripe", stripe(64, 64))
    put("dot", dot(32))
    # bords : couleur étendue sous l'alpha nul (pas de liseré sombre une fois filtré / mipmappé)
    a = np.asarray(atlas, dtype=np.float64)
    rgb = a[..., :3]
    al = a[..., 3:4] / 255.0
    blur_rgb = np.asarray(Image.fromarray(np.clip(rgb * al, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), dtype=np.float64)
    blur_a = np.asarray(Image.fromarray((al[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), dtype=np.float64)[..., None] / 255.0
    fill = blur_rgb / np.maximum(blur_a, 1e-3)
    rgb = np.where(al > 0.02, rgb, fill)
    out = np.concatenate([np.clip(rgb, 0, 255), a[..., 3:4]], axis=-1).astype(np.uint8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(out, "RGBA").save(OUT)
    print("planche de marquages ->", OUT)


if __name__ == "__main__":
    build()
