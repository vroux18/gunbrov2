"""Relais — textures peintes en code : sol de la station (dalles à joints, bandes de guidage) et toile de
nébuleuse vue par la grande baie (violet et bleu, plus lumineuse à gauche derrière le portail, sombre et
calme à droite sous le menu).

Usage : python3 tools/decor/relais_textures.py  -> assets/decor/relais/floor.png, nebula.png"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from relais_common import OUT  # noqa: E402


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def value_noise(shape, cells, rng, periodic=True):
    """Bruit de valeur lissé (bicubique simple), périodique."""
    h, w = shape
    g = rng.random((cells[0] + 1, cells[1] + 1)).astype(np.float32)
    if periodic:
        g[-1, :] = g[0, :]
        g[:, -1] = g[:, 0]
    ys = np.linspace(0, cells[0], h, endpoint=False)
    xs = np.linspace(0, cells[1], w, endpoint=False)
    yi = ys.astype(int); xi = xs.astype(int)
    fy = ys - yi; fx = xs - xi
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[yi][:, xi]; b = g[yi][:, xi + 1]; c = g[yi + 1][:, xi]; d = g[yi + 1][:, xi + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(shape, base, octaves, rng, gain=0.5):
    out = np.zeros(shape, dtype=np.float32)
    amp = 1.0; tot = 0.0
    for o in range(octaves):
        c = (base[0] * 2 ** o, base[1] * 2 ** o)
        out += amp * value_noise(shape, c, rng)
        tot += amp; amp *= gain
    return out / tot


def floor():
    """Tuile de 4 x 4 unités (512 px) : quatre dalles de 2 x 2 à joints sombres, une dalle à grille d'aération,
    légères variations de teinte. Plaquée en répétition sur le sol autour du pont."""
    n = 512
    rng = np.random.default_rng(3)
    base = hexrgb("#1D2548")
    img = np.tile(base, (n, n, 1))
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # variation douce
    v = fbm((n, n), (4, 4), 4, rng)
    img *= (0.9 + 0.2 * v)[..., None]
    # dalles : 2 x 2, teinte légèrement différente chacune
    for i in range(2):
        for j in range(2):
            k = [1.0, 1.06, 0.95, 1.03][i * 2 + j]
            img[i * 256:(i + 1) * 256, j * 256:(j + 1) * 256] *= k
    # joints (sombres) et biseau clair au bord des dalles
    m = np.minimum(np.minimum(xx % 256, 255 - xx % 256), np.minimum(yy % 256, 255 - yy % 256))
    img[m < 3] = hexrgb("#0C1024")
    edge = (m >= 3) & (m < 6)
    img[edge] = img[edge] * 1.25
    # grille d'aération sur une dalle
    g = (xx > 40) & (xx < 216) & (yy > 296) & (yy < 472)
    slot = ((yy.astype(int) - 296) % 16) < 7
    img[g & slot] = hexrgb("#10152E")
    # rivets
    for cx, cy in ((20, 20), (236, 20), (20, 236), (236, 236)):
        for ox in (0, 256):
            for oy in (0, 256):
                d = np.hypot(xx - cx - ox, yy - cy - oy)
                img[d < 4] = hexrgb("#3A4672")
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "floor.png"))


def nebula():
    """Toile 2048 x 1024 : nébuleuse violette et bleue, filaments, étoiles. Coordonnée u : gauche -> droite
    vue de la baie ; plus lumineuse dans le tiers gauche (derrière le portail), sombre à droite."""
    h, w = 1024, 2048
    rng = np.random.default_rng(11)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    vv = yy / h
    n1 = fbm((h, w), (4, 8), 6, rng, 0.55)
    n2 = fbm((h, w), (3, 6), 5, rng, 0.5)
    n3 = fbm((h, w), (8, 16), 4, rng, 0.6)
    # masse principale : bande diagonale qui monte vers la gauche
    band = np.exp(-((vv - (0.62 - 0.35 * (0.5 - u))) / 0.26) ** 2)
    dens = np.clip((n1 - 0.33) * 2.0, 0, 1) ** 0.8 * band
    # filaments clairs
    fil = np.clip(1.0 - np.abs(n3 - 0.5) * 5.0, 0, 1) ** 3 * dens
    # éclairage : fort à gauche, s'éteint à droite (sous le menu)
    light = np.clip(1.3 - u * 1.05, 0.14, 1.0) ** 1.3
    violet = hexrgb("#6A3CC8")
    blue = hexrgb("#2B5BD8")
    teal = hexrgb("#3CF2D8")
    pink = hexrgb("#D04CB8")
    mixc = np.clip(n2 * 1.6 - 0.3, 0, 1)[..., None]
    col = violet[None, None] * (1 - mixc) + blue[None, None] * mixc
    col = col * (dens * light)[..., None] * 1.25
    col += teal[None, None] * (fil * light * 0.35)[..., None]
    col += pink[None, None] * (np.clip(n3 - 0.62, 0, 1) * 2.5 * dens * light)[..., None]
    # fond spatial
    col += hexrgb("#070A1C")[None, None]
    # étoiles
    for count, size, b in ((2200, 1, 0.55), (260, 2, 0.9), (40, 3, 1.0)):
        sx = rng.integers(0, w, count); sy = rng.integers(0, h, count)
        for x, y in zip(sx, sy):
            k = b * (0.4 + 0.6 * rng.random()) * (0.45 + 0.55 * light[y, x])
            col[max(0, y - size // 2):y + (size + 1) // 2, max(0, x - size // 2):x + (size + 1) // 2] += k
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "nebula.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    floor()
    nebula()
    print("textures ->", OUT)
