#!/usr/bin/env python3
"""Cité Néon — ciel de nuit (panorama équirectangulaire 2048 x 1024) : voûte violette, nuages éclairés en rose
par la ville, lune voilée au nord, skyline lointaine aux fenêtres allumées, brume rose sous l'horizon.

Convention (celle de Godot et des shaders) : u = atan(d.x, -d.z) / 2π + 0,5 (nord au centre), v = acos(d.y) / π.
Écrit assets/decor/neon/shell/neon_sky.png. Lancement : python3 tools/decor/neon_shell_sky.py
"""
import math
import os

import numpy as np
from PIL import Image

from neon_shell_common import OUT, PINK, VIOLET, BLUE, ORANGE, blur, blur_noise, fbm, norm01, smoothstep, srgb

R = np.random.default_rng(88)
PW, PH = 2048, 1024
MOON_AZ, MOON_EL, MOON_R = math.radians(-38.0), math.radians(48.0), math.radians(1.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    jj, ii = np.mgrid[0:PH, 0:PW].astype(np.float32)
    u = (ii + 0.5) / PW
    v = (jj + 0.5) / PH
    az = (u - 0.5) * 2 * math.pi          # 0 = nord (-z)
    el = (0.5 - v) * math.pi              # élévation
    d = np.stack([np.cos(el) * np.sin(az), np.sin(el), -np.cos(el) * np.cos(az)], -1)
    # voûte : indigo au zénith, violet puis magenta près de l'horizon (pollution lumineuse)
    hz = np.clip(1 - el / (math.pi * 0.5), 0, 1)
    sky = srgb("#07051a") ** 2.2 * (1 - hz[..., None]) + (srgb("#2a0f4a") ** 2.2) * hz[..., None] ** 1.5
    sky += (srgb("#c03a8a") ** 2.2) * (smoothstep(0.55, 1.0, hz) ** 3)[..., None] * 0.55
    # nuages : bancs étirés, dessous éclairé rose / orange par la ville, plus denses vers l'horizon
    print("nuages")
    n = fbm(PH, PW, 26, 5, 801)
    n2 = blur_noise(PH, PW, 6, 802)
    stretch = blur(n, (2.0, 14.0), True)
    cl = smoothstep(-0.15, 0.9, stretch * 0.8 + n * 0.4 + n2 * 0.15 + (hz - 0.6) * 0.9)
    cl *= smoothstep(-0.05, 0.1, el)
    under = smoothstep(0.3, 1.0, hz)
    ccol = (srgb("#3a1a55") ** 2.2) * (1 - under[..., None]) + (srgb("#b04a8a") ** 2.2) * under[..., None]
    ccol = ccol * (0.6 + 0.6 * norm01(blur_noise(PH, PW, 18, 803)))[..., None]
    # lune voilée : disque, halo large, nuages devant
    md = np.array([math.cos(MOON_EL) * math.sin(MOON_AZ), math.sin(MOON_EL), -math.cos(MOON_EL) * math.cos(MOON_AZ)])
    ang = np.arccos(np.clip((d * md).sum(-1), -1, 1))
    disc = smoothstep(MOON_R * 1.04, MOON_R * 0.96, ang)
    # mers lunaires
    lu = (az - MOON_AZ) / MOON_R
    lv = (el - MOON_EL) / MOON_R
    maria = norm01(blur_noise(PH, PW, 3, 804)) * 0.35
    moon = srgb("#f2e6ff") ** 2.2 * (1.25 - maria[..., None]) * disc[..., None] * 1.2
    halo = np.exp(-(ang / (MOON_R * 2.5)) ** 2) * 0.3 + np.exp(-(ang / (MOON_R * 9)) ** 2) * 0.07
    sky = sky + (srgb("#d8b8ff") ** 2.2) * halo[..., None]
    sky = sky + moon
    # nuages par-dessus (la lune les éclaire par en dessous)
    cl_m = cl * (0.7 + 0.3 * smoothstep(MOON_R * 0.5, MOON_R * 4, ang))
    lit = np.exp(-(ang / (MOON_R * 6)) ** 2)[..., None] * (srgb("#e0c8ff") ** 2.2) * 0.6
    sky = sky * (1 - cl_m[..., None] * 0.85) + (ccol + lit) * cl_m[..., None] * 0.8
    # skyline lointaine : silhouettes de tours au-dessus de l'horizon, fenêtres, feux rouges, enseignes
    print("skyline")
    col_px = np.zeros(PW, np.float32)
    x = 0
    while x < PW:
        wd = int(R.integers(10, 46))
        hgt = R.uniform(0.004, 0.05) * (1.6 if R.random() < 0.12 else 1.0)
        col_px[x:x + wd] = hgt
        x += wd + int(R.integers(0, 6))
    col_px2 = np.zeros(PW, np.float32)
    x = 0
    while x < PW:
        wd = int(R.integers(16, 60))
        col_px2[x:x + wd] = R.uniform(0.002, 0.025)
        x += wd + int(R.integers(0, 10))
    top1 = 0.5 - col_px[None, :]
    top2 = 0.5 - col_px2[None, :]
    bld1 = v > top1
    bld2 = v > top2
    far = srgb("#2a1240") ** 2.2
    near = srgb("#120a1e") ** 2.2
    sky = np.where(bld1[..., None], far * (0.8 + 0.4 * (v - top1)[..., None] * 20), sky)
    sky = np.where(bld2[..., None], near, sky)
    win = (np.mod(ii, 3) == 0) & (np.mod(jj, 3) == 0) & (blur_noise(PH, PW, 0.6, 805) > 1.2)
    wc = np.where((blur_noise(PH, PW, 4, 806) > 0)[..., None], srgb("#ffc890") ** 2.2, srgb("#a8c0ff") ** 2.2)
    sky = np.where((win & bld1 & (v < 0.5))[..., None], sky + wc * 0.6, sky)
    for k in range(40):
        x = int(R.integers(0, PW))
        y = int((0.5 - col_px[x]) * PH) - 1
        if 0 < y < PH:
            sky[y - 1:y + 1, x:x + 2] += srgb("#ff3040") ** 2.2 * 1.5
    for k in range(26):
        x = int(R.integers(0, PW - 20))
        y = int((0.5 - col_px[x] * R.uniform(0.3, 0.9)) * PH)
        c = [PINK, BLUE, VIOLET, ORANGE][k % 4] ** 2.2
        sky[y:y + int(R.integers(1, 3)), x:x + int(R.integers(4, 14))] += c * 1.2
    # sous l'horizon : brume rose de la ville, scintillements
    below = smoothstep(0.5, 0.56, v)
    haze = (srgb("#3a1648") ** 2.2) * (1 - smoothstep(0.5, 1.0, v))[..., None] + srgb("#120818") ** 2.2 * smoothstep(0.5, 1.0, v)[..., None]
    dots = (blur_noise(PH, PW, 0.7, 807) > 2.3) & (v > 0.52)
    haze = haze + dots[..., None] * (srgb("#ffb0d8") ** 2.2) * 0.5
    sky = sky * (1 - below[..., None]) + haze * below[..., None]
    # faisceaux de projecteurs
    for (a0, sp) in ((-0.9, 0.12), (1.3, -0.08), (2.6, 0.1)):
        bx = (az - a0 - (el * sp)) / 0.012
        beam = np.exp(-bx ** 2) * smoothstep(0.0, 0.05, el) * (1 - smoothstep(0.1, 0.9, el))
        sky += (srgb("#b8a0ff") ** 2.2) * beam[..., None] * 0.12
    img = np.clip(sky, 0, 1) ** (1 / 2.2)
    path = os.path.join(OUT, "neon_sky.png")
    Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path, optimize=True)
    print("  ->", path.split("assets/")[-1], PW, "x", PH)


if __name__ == "__main__":
    main()
