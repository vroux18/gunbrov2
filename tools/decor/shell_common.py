"""Nébuleuse 7 — outils communs des textures et maillages de la coque du hangar (tools/decor/).

Dimensions de l'arène (arena.gd, 64 px = 1 m), bruits périodiques, dessin anti-crénelé, écriture PNG et GLB.
"""
import json
import os
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "decor", "shell")
FONT_RUSSO = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")
FONT_RAJ = os.path.join(ROOT, "assets", "fonts", "Rajdhani-Bold.ttf")

# arène (m)
K = 1.0 / 64.0
W = 2400 * K
H = 1400 * K
WALL = 36 * K
TOP = 250 * K
# grille des tôles du sol : 48 cases entre les murs ouest et est, 23 rangées du quai au mur sud
NX, NZ = 48, 23
CELL = (W - 2 * WALL) / NX
GX0, GZ0 = WALL, TOP


def srgb(h, a=None):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return np.array(c if a is None else c + [a], dtype=np.float32)


def norm01(a):
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / (hi - lo + 1e-9)


def blur_noise(h, w, sigma, seed):
    """Bruit gaussien filtré, périodique (FFT), moyenne nulle, écart-type 1. sigma en pixels."""
    r = np.random.default_rng(seed)
    wn = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    out = np.real(np.fft.ifft2(np.fft.fft2(wn) * g))
    return (out - out.mean()) / (out.std() + 1e-9)


def aniso_noise(h, w, sx, sy, seed):
    """Bruit périodique étiré (sx le long des colonnes, sy le long des lignes)."""
    r = np.random.default_rng(seed)
    wn = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(wn) * g))
    return (out - out.mean()) / (out.std() + 1e-9)


def fbm(h, w, sigma, octaves, seed, gain=0.5):
    s = np.zeros((h, w))
    a, tot = 1.0, 0.0
    for o in range(octaves):
        s += a * blur_noise(h, w, max(sigma / (2 ** o), 0.5), seed + 31 * o)
        tot += a
        a *= gain
    return s / tot


def blur(a, sigma, wrap=False):
    return ndimage.gaussian_filter(a, sigma, mode="wrap" if wrap else "nearest")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Canvas:
    """Masque en niveaux de gris dessiné au double de la résolution puis réduit (anti-crénelage)."""

    def __init__(self, w, h, ss=2):
        self.ss = ss
        self.w, self.h = w, h
        self.img = Image.new("L", (w * ss, h * ss), 0)
        self.d = ImageDraw.Draw(self.img)

    def S(self, v):
        return v * self.ss

    def line(self, pts, width, fill=255):
        self.d.line([(x * self.ss, y * self.ss) for x, y in pts], fill=fill, width=max(1, int(round(width * self.ss))), joint="curve")

    def poly(self, pts, fill=255):
        self.d.polygon([(x * self.ss, y * self.ss) for x, y in pts], fill=fill)

    def rect(self, x0, y0, x1, y1, fill=255):
        self.d.rectangle([x0 * self.ss, y0 * self.ss, x1 * self.ss - 1, y1 * self.ss - 1], fill=fill)

    def rrect(self, x0, y0, x1, y1, r, fill=255):
        self.d.rounded_rectangle([x0 * self.ss, y0 * self.ss, x1 * self.ss - 1, y1 * self.ss - 1], radius=r * self.ss, fill=fill)

    def ellipse(self, cx, cy, rx, ry, fill=255, width=0):
        box = [(cx - rx) * self.ss, (cy - ry) * self.ss, (cx + rx) * self.ss, (cy + ry) * self.ss]
        if width > 0:
            self.d.ellipse(box, outline=fill, width=max(1, int(round(width * self.ss))))
        else:
            self.d.ellipse(box, fill=fill)

    def text(self, x, y, s, size, font=FONT_RUSSO, fill=255, anchor="mm", spacing=0.0, maxw=None):
        f = ImageFont.truetype(font, int(size * self.ss))
        if maxw is None:
            maxw = self.w * 0.94
        # réduit le corps jusqu'à tenir dans la largeur
        while size > 4:
            tw = self.d.textlength(s, font=f) + spacing * self.ss * (len(s) - 1)
            if tw <= maxw * self.ss:
                break
            size *= 0.95
            spacing *= 0.95
            f = ImageFont.truetype(font, int(size * self.ss))
        if spacing == 0.0:
            self.d.text((x * self.ss, y * self.ss), s, font=f, fill=fill, anchor=anchor)
            return
        # espacement des lettres (pochoir)
        widths = [self.d.textlength(ch, font=f) for ch in s]
        tot = sum(widths) + spacing * self.ss * (len(s) - 1)
        cx = x * self.ss - tot * 0.5 if anchor[0] == "m" else x * self.ss
        for ch, wd in zip(s, widths):
            self.d.text((cx, y * self.ss), ch, font=f, fill=fill, anchor="l" + anchor[1])
            cx += wd + spacing * self.ss

    def array(self):
        im = self.img.resize((self.w, self.h), Image.LANCZOS) if self.ss > 1 else self.img
        return np.asarray(im, dtype=np.float32) / 255.0


def save_rgba(path, rgba):
    a = np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGBA" if a.shape[2] == 4 else "RGB").save(path, optimize=True)
    print("  ->", os.path.relpath(path, ROOT), a.shape[1], "x", a.shape[0])


def height_to_normal(hm, strength, wrap=True):
    """Carte de normales (convention OpenGL, Y vers le haut de l'image) depuis une carte de hauteur."""
    if wrap:
        dx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * 0.5
        dy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) * 0.5
    else:
        dy, dx = np.gradient(hm)
    nx = -dx * strength
    ny = dy * strength  # lignes de l'image vers le bas = -Y
    nz = np.ones_like(hm)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], -1)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print("  ->", os.path.relpath(path, ROOT))


# ---------------------------------------------------------------- GLB minimal
def write_glb(path, meshes):
    """meshes : liste de (nom, dict(pos, nrm, uv, uv2, col, idx)) ; un nœud et un matériau par maillage."""
    bin_chunks = []
    views, accessors, gl_meshes, nodes, materials = [], [], [], [], []
    off = 0

    def add(arr, comp, typ, target, minmax=False):
        nonlocal off
        data = arr.tobytes()
        pad = (-len(data)) % 4
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        bin_chunks.append(data + b"\0" * pad)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            acc["min"] = [float(v) for v in arr.min(0)]
            acc["max"] = [float(v) for v in arr.max(0)]
        accessors.append(acc)
        off += len(data) + pad
        return len(accessors) - 1

    for i, (name, m) in enumerate(meshes):
        attrs = {
            "POSITION": add(m["pos"].astype(np.float32), 5126, "VEC3", 34962, True),
            "NORMAL": add(m["nrm"].astype(np.float32), 5126, "VEC3", 34962),
            "TEXCOORD_0": add(m["uv"].astype(np.float32), 5126, "VEC2", 34962),
            "TEXCOORD_1": add(m["uv2"].astype(np.float32), 5126, "VEC2", 34962),
            "COLOR_0": add(m["col"].astype(np.float32), 5126, "VEC4", 34962),
        }
        ind = add(m["idx"].astype(np.uint32).reshape(-1), 5125, "SCALAR", 34963)
        materials.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.7}})
        gl_meshes.append({"name": name, "primitives": [{"attributes": attrs, "indices": ind, "material": i}]})
        nodes.append({"name": name, "mesh": i})
    binary = b"".join(bin_chunks)
    gltf = {
        "asset": {"version": "2.0", "generator": "tools/decor/shell_common.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "materials": materials,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(binary), 0x004E4942))
        f.write(binary)
    print("  ->", os.path.relpath(path, ROOT), sum(len(m["idx"]) for _, m in meshes), "triangles")
