"""Planche de marquages des objets de fret (assets/decor/props/decals.png) : logo et pochoirs de la compagnie
VEKTA, codes de lot, étiquettes de fret, bandes de danger. Les objets sculptés (props.py) y posent des quads
fins collés à leurs faces planes : un marquage net coûte deux triangles au lieu de centaines de sommets.
Pochoirs usés : l'alpha est rongé par un bruit, comme une peinture écaillée.

Usage : python3 tools/decor/atlas.py   (aussi appelé par props.py)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "decor", "props", "decals.png")
FONT = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")
FONT2 = os.path.join(ROOT, "assets", "fonts", "Rajdhani-Bold.ttf")
SIZE = 1024
SS = 2  # suréchantillonnage

CREAM = (214, 206, 186)
INK = (40, 42, 50)
ORANGE = (222, 120, 58)
YELLOW = (214, 166, 52)
BLACK = (26, 27, 31)
CARD = (206, 199, 180)

# régions (x, y, w, h) en pixels de la planche
R = {
    "logo": (0, 0, 256, 256),
    "logo_o": (256, 0, 256, 256),
    "word": (512, 0, 512, 128),
    "word_k": (512, 128, 512, 128),
    "tag": (0, 256, 256, 128),
    "tag2": (256, 256, 256, 128),
    "haz": (512, 256, 512, 64),
    "diamond": (512, 320, 128, 128),
    "up": (640, 320, 128, 128),
    "acces": (768, 320, 256, 128),
    "N7": (0, 448, 256, 96), "07": (256, 448, 256, 96), "A3": (512, 448, 256, 96), "N7-4": (768, 448, 256, 96),
    "R-12": (0, 544, 256, 96), "F-9": (256, 544, 256, 96), "73": (512, 544, 256, 96), "E-7": (768, 544, 256, 96),
    "VK-3": (0, 640, 256, 96),
    "line": (256, 640, 512, 64),
    "gauge": (768, 640, 64, 256),
    "scuff": (832, 640, 192, 192),
    "tape": (0, 736, 128, 32),
    "tread": (0, 768, 256, 256),
    "vent": (256, 768, 128, 128),
}
CODES = ["N7", "07", "A3", "N7-4", "R-12", "F-9", "73", "E-7", "VK-3"]


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
    # légère variation de valeur dans la peinture
    a[..., :3] *= (0.88 + 0.12 * _noise(img.width, img.height, seed + 1, scale * 3))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def _canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def _down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def logo(col, w=256):
    """Anneau orbital ouvert à droite, traversé d'un chevron et d'un trait de vitesse."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    c = s * 0.5
    r = s * 0.4
    t = s * 0.085
    d.arc((c - r, c - r, c + r, c + r), 38, 322, fill=col + (255,), width=int(t))
    # chevron
    ch = [(c - s * 0.12, c - s * 0.2), (c + s * 0.14, c), (c - s * 0.12, c + s * 0.2)]
    d.line(ch, fill=col + (255,), width=int(t * 1.05), joint="curve")
    # traits de vitesse
    d.line([(c - s * 0.46, c), (c - s * 0.02, c)], fill=col + (255,), width=int(t * 0.6))
    d.line([(c + s * 0.14, c), (c + s * 0.48, c)], fill=col + (255,), width=int(t * 1.05))
    return _down(im, w, w)


def text_img(txt, w, h, col, font=FONT, fill=0.78, spacing=0):
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


def tag(w, h, variant=0, seed=0):
    """Étiquette de fret : carte crème, code-barres, lignes de texte, bande orange, petit logo."""
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    S = SS
    rng = np.random.default_rng(seed)
    d.rounded_rectangle((2 * S, 2 * S, (w - 2) * S, (h - 2) * S), radius=6 * S, fill=CARD + (255,))
    if variant == 0:
        d.rectangle((2 * S, 2 * S, 30 * S, (h - 2) * S), fill=ORANGE + (255,))
        d.rounded_rectangle((2 * S, 2 * S, 30 * S, (h - 2) * S), radius=6 * S, fill=ORANGE + (255,))
        x = 42 * S
        bx = x
        while bx < (w - 14) * S:
            bw = int(rng.integers(1, 4)) * S * 2
            d.rectangle((bx, 60 * S, bx + bw, (h - 14) * S), fill=INK + (255,))
            bx += bw + int(rng.integers(1, 3)) * S * 2
        f = ImageFont.truetype(FONT2, 26 * S)
        d.text((x, 10 * S), "VEKTA  N7 > 04", font=f, fill=INK + (255,))
        f2 = ImageFont.truetype(FONT2, 18 * S)
        d.text((x, 36 * S), "LOT 2291-B   48 KG", font=f2, fill=INK + (255,))
    else:
        f = ImageFont.truetype(FONT2, 30 * S)
        d.text((14 * S, 8 * S), "TRI 04", font=f, fill=INK + (255,))
        # flèches « haut »
        for k in range(2):
            ax = (w - 70 + k * 30) * S
            d.polygon([(ax, 20 * S), (ax + 12 * S, 38 * S), (ax - 12 * S, 38 * S)], fill=INK + (255,))
            d.rectangle((ax - 4 * S, 38 * S, ax + 4 * S, 60 * S), fill=INK + (255,))
        d.rectangle((14 * S, 70 * S, (w - 14) * S, 76 * S), fill=INK + (255,))
        f2 = ImageFont.truetype(FONT2, 20 * S)
        d.text((14 * S, 84 * S), "NE PAS GERBER  x2", font=f2, fill=INK + (255,))
        d.rectangle(((w - 40) * S, 84 * S, (w - 14) * S, (h - 12) * S), fill=ORANGE + (255,))
    img = _down(im, w, h)
    return _wear(img, seed + 50, amount=0.12, scale=5)


def hazard(w, h):
    """Bandes jaunes et noires en diagonale, raccordables bout à bout (période entière dans la largeur)."""
    im = Image.new("RGBA", (w * SS, h * SS), YELLOW + (255,))
    d = ImageDraw.Draw(im)
    per = w * SS / 8
    for k in range(-2, 10):
        x = k * per
        d.polygon([(x, h * SS), (x + per * 0.5, h * SS), (x + per * 0.5 + h * SS, 0), (x + h * SS, 0)], fill=BLACK + (255,))
    return _down(im, w, h)


def diamond(w):
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    c = s / 2
    pts = [(c, s * 0.04), (s * 0.96, c), (c, s * 0.96), (s * 0.04, c)]
    d.polygon(pts, fill=YELLOW + (255,))
    pin = [(c, s * 0.12), (s * 0.88, c), (c, s * 0.88), (s * 0.12, c)]
    d.line(pin + [pin[0]], fill=BLACK + (255,), width=int(s * 0.035))
    # éclair (énergie)
    bolt = [(c + s * 0.04, s * 0.26), (c - s * 0.12, c + s * 0.03), (c - s * 0.0, c + s * 0.03), (c - s * 0.06, s * 0.74),
            (c + s * 0.13, c - s * 0.05), (c + s * 0.01, c - s * 0.05)]
    d.polygon(bolt, fill=BLACK + (255,))
    return _down(im, w, w)


def up_arrows(w):
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    for k in (-1, 1):
        ax = s * 0.5 + k * s * 0.2
        d.polygon([(ax, s * 0.12), (ax + s * 0.16, s * 0.4), (ax - s * 0.16, s * 0.4)], fill=CREAM + (255,))
        d.rectangle((ax - s * 0.06, s * 0.4, ax + s * 0.06, s * 0.72), fill=CREAM + (255,))
    d.rectangle((s * 0.1, s * 0.8, s * 0.9, s * 0.88), fill=CREAM + (255,))
    return _down(im, w, w)


def gauge(w, h):
    """Graduations de jauge (cellules d'énergie)."""
    im = _canvas(w, h)
    d = ImageDraw.Draw(im)
    for k in range(11):
        y = (8 + k * (h - 16) / 10) * SS
        ln = 0.9 if k % 5 == 0 else 0.5
        d.rectangle((w * SS * (1 - ln) * 0.5, y - SS * 1.5, w * SS * (1 + ln) * 0.5, y + SS * 1.5), fill=CREAM + (255,))
    return _down(im, w, h)


def scuff(w, seed=3):
    """Tache d'usure sombre (traces de chariot, frottements) : alpha doux."""
    n = _noise(w, w, seed, 5)
    yy, xx = np.mgrid[0:w, 0:w] / (w - 1) - 0.5
    rad = np.clip(1 - np.sqrt(xx ** 2 + yy ** 2) * 2.1, 0, 1)
    a = np.clip((n - 0.45) * 3.0, 0, 1) * rad * 150
    img = np.zeros((w, w, 4))
    img[..., :3] = (22, 22, 26)
    img[..., 3] = a
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def tape(w, h):
    """Ruban adhésif de colis : brun clair, bords un peu plus sombres, semi-opaque."""
    a = np.zeros((h, w, 4))
    a[..., :3] = (176, 156, 112)
    yy = np.abs(np.arange(h) / (h - 1) - 0.5)[:, None]
    a[..., :3] *= (1 - 0.18 * (yy > 0.38))[..., None]
    a[..., 3] = 225
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def tread(w):
    """Tôle larmée (plaques de sol) : losanges en relief clairs sur fond sombre, alpha plein."""
    im = Image.new("RGBA", (w * SS, w * SS), (58, 64, 78, 255))
    d = ImageDraw.Draw(im)
    s = w * SS
    n = 8
    for i in range(n + 1):
        for j in range(n + 1):
            cx, cy = (i + 0.5 * (j % 2)) * s / n, j * s / n
            ang = 0.785 if (i + j) % 2 == 0 else -0.785
            dx, dy = math.cos(ang) * s * 0.035, math.sin(ang) * s * 0.035
            d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=(104, 112, 128, 255), width=int(s * 0.018))
            d.line([(cx - dx, cy - dy + s * 0.006), (cx + dx, cy + dy + s * 0.006)], fill=(36, 40, 50, 255), width=int(s * 0.008))
    img = _down(im, w, w)
    a = np.asarray(img, dtype=np.float64).copy()
    a[..., :3] *= (0.82 + 0.18 * _noise(w, w, 77, 4))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def vent(w):
    """Grille d'aération : fentes sombres dans un cadre."""
    im = _canvas(w, w)
    d = ImageDraw.Draw(im)
    s = w * SS
    d.rounded_rectangle((s * 0.04, s * 0.04, s * 0.96, s * 0.96), radius=int(s * 0.08), fill=(70, 76, 88, 255))
    for k in range(6):
        y = s * (0.16 + k * 0.13)
        d.rounded_rectangle((s * 0.14, y, s * 0.86, y + s * 0.07), radius=int(s * 0.03), fill=(18, 20, 26, 255))
    return _down(im, w, w)


def periodic_noise(n, seed, beta):
    """Bruit raccordable (spectre en 1/f^beta, phases aléatoires), normalisé dans [0, 1]."""
    rng = np.random.default_rng(seed)
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / f ** beta
    spec[0, 0] = 0
    img = np.real(np.fft.ifft2(spec))
    img = (img - img.min()) / (img.max() - img.min())
    # contraste : histogramme étalé autour de 0,5
    return np.clip((img - 0.5) * 1.6 + 0.5, 0, 1)


def build_noise():
    """noise.png : R grain fin (éclats), G moyen (marbrures de peinture), B large (taches de salissure)."""
    n = 256
    rgb = np.stack([periodic_noise(n, 11, 1.1), periodic_noise(n, 12, 1.4), periodic_noise(n, 13, 1.9)], axis=-1)
    out = os.path.join(os.path.dirname(OUT), "noise.png")
    Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(out)
    print("bruit ->", out)


def build():
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    def put(key, img):
        x, y, w, h = R[key]
        atlas.alpha_composite(img.resize((w, h), Image.LANCZOS) if img.size != (w, h) else img, (x, y))

    put("logo", _wear(logo(CREAM), 1, 0.3))
    put("logo_o", _wear(logo(ORANGE), 2, 0.26))
    put("word", _wear(text_img("VEKTA", 512, 128, CREAM, fill=0.82), 3, 0.34, 9))
    put("word_k", _wear(text_img("VEKTA", 512, 128, BLACK, fill=0.82), 4, 0.3, 9))
    put("tag", tag(256, 128, 0, 5))
    put("tag2", tag(256, 128, 1, 6))
    put("haz", _wear(hazard(512, 64), 7, 0.16, 10))
    put("diamond", _wear(diamond(128), 8, 0.14, 5))
    put("up", _wear(up_arrows(128), 9, 0.3, 6))
    put("acces", _wear(text_img("ACCES", 256, 128, YELLOW, fill=0.6), 10, 0.3, 8))
    for i, c in enumerate(CODES):
        put(c, _wear(text_img(c, R[c][2], R[c][3], CREAM, fill=0.84), 20 + i, 0.24, 11))
    put("line", _wear(text_img("FRET ORBITAL  -  NEBULEUSE 7  -  TRI 04", 512, 64, CREAM, font=FONT2, fill=0.7), 40, 0.3, 10))
    put("gauge", gauge(64, 256))
    put("scuff", scuff(192))
    put("tape", tape(128, 32))
    put("tread", tread(256))
    put("vent", vent(128))
    # bords : on étend la couleur sous l'alpha nul (pas de liseré sombre une fois filtré / mipmappé)
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
    build_noise()
