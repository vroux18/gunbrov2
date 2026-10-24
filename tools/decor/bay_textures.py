"""Textures du quai nord : python3 tools/decor/bay_textures.py
  bay_grime.png : salissures raccordables (multipliées à la couleur par sommet, projection triplanaire) ;
  bay_floor.png : pont du quai peint (plaques d'acier, joints, rivets, aire de posé de la baie 07, marquages
                  BAIE 07 et logo HÉLIX FRET, allée piétonne, traces de pneus et d'huile)."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "decor", "bay")
FONT = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")
rng = np.random.default_rng(7)


def tile_noise(size, cells, seed):
    """Bruit de valeur raccordable (grille périodique), dans [0, 1]."""
    r = np.random.default_rng(seed)
    g = r.random((cells, cells))
    x = np.arange(size) * cells / size
    i0 = np.floor(x).astype(int)
    f = x - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def tile_fbm(size, base, seed, oct=5):
    out = np.zeros((size, size))
    a, tot = 1.0, 0.0
    for i in range(oct):
        out += a * tile_noise(size, base * 2 ** i, seed + i)
        tot += a
        a *= 0.5
    return out / tot


def grime():
    S = 512
    n = tile_fbm(S, 4, 11)
    m = tile_fbm(S, 16, 31, 4)
    g = 1.0 - 0.32 * np.clip((n - 0.45) * 2.2, 0, 1) - 0.08 * (m - 0.5)
    # rayures fines (raccordables : tracées modulo la taille)
    img = Image.fromarray(np.uint8(np.clip(g, 0, 1) * 255), "L")
    d = ImageDraw.Draw(img)
    for _ in range(60):
        x, y = rng.random(2) * S
        a = rng.normal(0.0, 0.5) + (0 if rng.random() < 0.6 else math.pi / 2)
        L = rng.uniform(8, 50)
        c = int(rng.uniform(205, 235))
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                d.line([(x + ox, y + oy), (x + ox + math.cos(a) * L, y + oy + math.sin(a) * L)], fill=c, width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    arr = np.asarray(img, dtype=np.float32) / 255.0
    rgb = np.stack([arr * 0.99, arr * 0.985, arr], axis=-1)
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255), "RGB").save(os.path.join(OUT, "bay_grime.png"))


def kick():
    """Plinthe du garde-corps : bandes obliques jaune passé / noir, peinture écaillée, raccordable en x."""
    Wd, Hd = 256, 64
    yy, xx = np.mgrid[0:Hd, 0:Wd].astype(np.float32)
    band = ((xx + yy) / 32.0) % 2.0 < 1.0
    yel = np.array([186, 150, 60], np.float32) / 255
    blk = np.array([28, 28, 32], np.float32) / 255
    img = np.where(band[..., None], yel, blk)
    n = tile_fbm(256, 8, 77)[:Hd, :]
    chip = (n > 0.66)[..., None]
    img = np.where(chip, np.array([96, 100, 112], np.float32) / 255, img)
    img *= (0.85 + 0.2 * tile_fbm(256, 4, 78)[:Hd, :])[..., None]
    img[:3] *= 0.6
    img[-3:] *= 0.5
    Image.fromarray(np.uint8(np.clip(img, 0, 1) * 255), "RGB").save(os.path.join(OUT, "bay_kick.png"))


def nebula():
    """Toile de fond derrière les baies du mur nord : bande du panorama assets/env/space.jpg (nébuleuse violette
    et turquoise), un peu assombrie (le quai reste plus sombre que l'aire de jeu)."""
    im = Image.open(os.path.join(ROOT, "assets", "env", "space.jpg")).convert("RGB")
    band = im.crop((300, 420, 4096, 1320)).resize((2048, 486), Image.LANCZOS)
    arr = np.asarray(band, dtype=np.float32) / 255.0
    arr = np.clip(arr * 0.95, 0, 1)
    Image.fromarray(np.uint8(arr * 255), "RGB").save(os.path.join(OUT, "bay_nebula.jpg"), quality=88)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    grime()
    kick()
    nebula()
    import bay_floor
    bay_floor.paint(OUT)
