#!/usr/bin/env python3
"""Textures des effets (assets/fx/) : bouffée de fumée/feu, étoile d'éclat, éclat de bouche.
Lancement : python3 scripts/fx/make_tex.py  (puis import Godot)."""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "fx")
rng = np.random.default_rng(7)


def value_noise(n, cells):
    g = rng.random((cells + 1, cells + 1))
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    x = np.linspace(0, cells, n, endpoint=False)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i]
    b = g[i][:, i + 1]
    c = g[i + 1][:, i]
    d = g[i + 1][:, i + 1]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(n, base=4, octaves=4):
    out = np.zeros((n, n))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        out += value_noise(n, base * 2 ** o) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, rgba):
    rgba = np.clip(rgba, 0, 1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("écrit", name)


def puff(n=128):
    """Bouffée ronde et bosselée : alpha = densité, rgb = ombrage (lumière venant du haut de l'écran)."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.sqrt(x * x + y * y)
    nz = fbm(n, 2, 3)
    ang = np.arctan2(y, x)
    # bord en lobes doux (cumulus), à peine bruité
    edge = 0.8 + 0.05 * np.sin(ang * 5 + 1.3) + 0.04 * np.sin(ang * 3 - 0.4) + (nz - 0.5) * 0.2
    d = np.clip((edge - r) / 0.3, 0, 1)
    dens = d * d * (3 - 2 * d)
    dens *= 0.8 + 0.3 * nz
    dens = np.clip(dens, 0, 1)
    # ombrage : dôme doux, lumière en haut à gauche
    h = np.sqrt(np.clip(1 - (r / 0.9) ** 2, 0, 1)) + (nz - 0.5) * 0.35
    gy, gx = np.gradient(h)
    light = np.clip(0.62 - gx * 7 - gy * 9 + 0.2 * h, 0.25, 1.0)
    rgb = np.stack([light] * 3, -1)
    save("puff.png", np.dstack([rgb, dens]))


def star(n=128):
    """Étoile à 4 branches + cœur rond (critiques, éclats de bouche)."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.sqrt(x * x + y * y)
    core = np.clip(1 - r / 0.45, 0, 1) ** 2
    ray_h = np.clip(1 - np.abs(y) / (0.06 + 0.05 * (1 - np.abs(x))), 0, 1) * np.clip(1 - np.abs(x), 0, 1) ** 1.5
    ray_v = np.clip(1 - np.abs(x) / (0.06 + 0.05 * (1 - np.abs(y))), 0, 1) * np.clip(1 - np.abs(y), 0, 1) ** 1.5
    a = np.clip(core + ray_h + ray_v, 0, 1)
    save("star.png", np.dstack([np.ones((n, n, 3)), a]))


def muzzle(n=128):
    """Éclat de bouche vu de côté : flamme en pointe vers le haut (axe +y = direction du tir)."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    yy = -y  # haut de l'image = avant
    t = np.clip((yy + 0.6) / 1.6, 0, 1)  # 0 près de la bouche, 1 au bout
    # goutte : ventre rond près de la bouche, pointe vers l'avant
    width = 0.5 * np.sqrt(np.clip(t * 3.0, 0, 1)) * (1 - t) ** 0.9
    body = np.clip(1 - (np.abs(x) / np.maximum(width, 1e-3)) ** 2, 0, 1)
    core = np.clip(1 - np.sqrt(x * x + (yy + 0.25) ** 2) / 0.35, 0, 1) ** 1.5
    a = np.clip(body * (0.55 + 0.45 * (1 - t)) + core, 0, 1)
    save("muzzle.png", np.dstack([np.ones((n, n, 3)), a]))


if __name__ == "__main__":
    puff()
    star()
    muzzle()
