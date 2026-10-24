"""Relais — pont central (plateforme ronde de Jo) : dalles en secteurs à joints creux, anneaux lumineux
incrustés, lèvre arrondie, socle sombre à bandeau lumineux, marches à l'avant, bornes lumineuses et
rambarde sur l'arrière. Dessus du pont à y = 0, centre en (0, 0, 0) ; l'avant (vers la caméra) est +Z."""
import math
import sys

import numpy as np
import trimesh

from relais_common import *

R_IN = 1.15
RINGS = [(1.25, 2.35, 8), (2.45, 3.55, 12)]
R_LIP = (3.65, 4.35)
R_BASE = 4.3
POSTS = [math.radians(a) for a in (192, 222, 252, 288, 318, 348)]  # bornes (arrière ; angle depuis +X vers +Z)
R_POST = 4.02


def deck():
    parts = []
    body = part("deck", res=0.02, ao=0.5)
    # socle sombre sous les dalles (visible dans les joints), chanfreiné dessous
    base = body.piece(NAVY, tris=418, res=0.03)
    base.add(cyl((0, -0.29, 0), R_BASE, 0.24, 0.06))
    base.add(cyl((0, -0.5, 0), R_BASE - 0.35, 0.06, 0.04), k=0.12)
    # bandeau de flanc : métal bleu en relief, interrompu par des nervures
    band = body.piece(STEEL, tris=511, res=0.02)
    band.add(ring((0, -0.27, 0), R_BASE + 0.02, 0.05, 0.09, 0.03))
    ribs = body.piece(STEEL_D, tris=325, res=0.02)
    for k in range(24):
        a = 2 * math.pi * (k + 0.5) / 24
        ribs.add(rbox((math.cos(a) * (R_BASE + 0.06), -0.27, math.sin(a) * (R_BASE + 0.06)), (0.06, 0.15, 0.08), 0.025, rot=(0, -math.degrees(a), 0)))
    # lèvre extérieure, légèrement relevée, à gorge pour le liseré lumineux
    lip = body.piece(STEEL, tris=604, res=0.015)
    lip.add(ring((0, -0.01, 0), 0.5 * sum(R_LIP), 0.5 * (R_LIP[1] - R_LIP[0]), 0.05, 0.03))
    lip.sub(ring((0, 0.04, 0), R_LIP[0] + 0.16, 0.035, 0.03, 0.01), k=0.01)
    # marches à l'avant (vers la caméra), en arc
    steps = body.piece(STEEL_D, tris=232, res=0.02)
    steps.add(arc_ring((0, -0.2, 0), R_BASE + 0.32, 0.3, 0.1, math.radians(55), math.radians(125), 0.04))
    steps.add(arc_ring((0, -0.4, 0), R_BASE + 0.8, 0.3, 0.1, math.radians(60), math.radians(120), 0.04))
    parts.append(body)
    # dalles et médaillon : maillages directs à chanfrein net (des dalles plates sculptées en SDF puis
    # allégées gardent des normales de biseau étirées sur toute la dalle : reflets en triangles)
    tiles = []
    tiles.append(tile_mesh(0.0, R_IN, 0.0, 2 * math.pi, DECK_L))
    for i, (r0, r1, n) in enumerate(RINGS):
        for k in range(n):
            col = DECK if (k + i) % 2 == 0 else DECK_L
            a0 = 2 * math.pi * k / n + 0.025 / r0
            a1 = 2 * math.pi * (k + 1) / n - 0.025 / r0
            tiles.append(tile_mesh(r0, r1, a0, a1, col))
    parts.append(MeshPart("deck_tiles", trimesh.util.concatenate(tiles)))
    # lueurs : anneaux incrustés dans les joints, liseré de la lèvre, têtes des bornes, bandeau du flanc
    glow = part("deck_glow", res=0.012)
    g = glow.piece(TEAL, tris=651)
    for r in (R_IN + 0.05, RINGS[0][1] + 0.05):
        g.add(ring((0, -0.045, 0), r, 0.018, 0.012, 0.006))
    g.add(ring((0, 0.03, 0), R_LIP[0] + 0.16, 0.022, 0.012, 0.008))
    g.add(ring((0, 0.0, 0), 0.78, 0.02, 0.006, 0.004))
    parts.append(glow)
    side = part("deck_side_glow", res=0.02)
    side.piece(ORANGE, tris=418).add(ring((0, -0.27, 0), R_BASE + 0.045, 0.03, 0.025, 0.012))
    parts.append(side)
    return parts


class MeshPart:
    """Part déjà maillée (pas de SDF), exportée telle quelle par sculpt.Character."""
    def __init__(self, name, tm, parent=None):
        self.name = name
        self.tm = tm
        self.parent = parent
        self.pivot = np.zeros(3)

    def mesh(self):
        return self.tm


def tile_mesh(r0, r1, a0, a1, col, top=0.0, depth=0.08, ch=0.022):
    """Dalle en secteur d'anneau : dessus plat, chanfrein clair, flancs sombres ; facettes franches."""
    c = hexcol(col)
    n = max(3, int(math.ceil((a1 - a0) * r1 / 0.2)))
    full = r0 < 0.05
    def arc(r, y, inset_a):
        return [(r * math.cos(a), y, r * math.sin(a)) for a in np.linspace(a0 + inset_a / max(r, 0.05), a1 - inset_a / max(r, 0.05), n + 1)]
    ia = 0.0 if full else ch
    in_top = arc(r0 + (0 if full else ch), top, ia)
    out_top = arc(r1 - ch, top, ia)
    in_ch = arc(r0, top - ch, 0.0)
    out_ch = arc(r1, top - ch, 0.0)
    in_bot = arc(r0, top - depth, 0.0)
    out_bot = arc(r1, top - depth, 0.0)
    V, F, C = [], [], []
    def quad(p, q, r, t, col):
        b = len(V)
        V.extend([p, q, r, t])
        F.extend([[b, b + 2, b + 1], [b, b + 3, b + 2]])
        C.extend([col] * 2)
    light = np.clip(c * 1.3 + 0.03, 0, 1)
    dark = c * 0.6
    for i in range(n):
        quad(in_top[i], out_top[i], out_top[i + 1], in_top[i + 1], c)
        quad(out_top[i], out_ch[i], out_ch[i + 1], out_top[i + 1], light)
        quad(out_ch[i], out_bot[i], out_bot[i + 1], out_ch[i + 1], dark)
        if not full:
            quad(in_ch[i], in_top[i], in_top[i + 1], in_ch[i + 1], light)
            quad(in_bot[i], in_ch[i], in_ch[i + 1], in_bot[i + 1], dark)
    if not full:
        # bouts radiaux : chanfrein et flanc
        for j, sgn in ((0, 1), (n, -1)):
            if sgn > 0:
                quad(in_ch[j], out_ch[j], out_top[j], in_top[j], light)
                quad(in_bot[j], out_bot[j], out_ch[j], in_ch[j], dark)
            else:
                quad(in_top[j], out_top[j], out_ch[j], in_ch[j], light)
                quad(in_ch[j], out_ch[j], out_bot[j], in_bot[j], dark)
    tm = trimesh.Trimesh(vertices=np.array(V), faces=np.array(F), process=False)
    fc = (np.concatenate([np.array(C), np.ones((len(C), 1))], axis=1) * 255).astype(np.uint8)
    tm.visual = trimesh.visual.ColorVisuals(tm, face_colors=fc)
    return tm  # sens des faces : (r - p) x (q - p) vers l'extérieur pour chaque quad(p, q, r, t)


def borne():
    """Borne lumineuse du bord du pont (posée en jeu aux angles POSTS, rayon R_POST). Pied à y = 0."""
    body = part("borne", res=0.01)
    body.piece(STEEL_D, tris=90).add(cyl((0, 0.04, 0), 0.14, 0.05, 0.03))
    post = body.piece(HULL, tris=150)
    post.add(capsule((0, 0.05, 0), (0, 0.8, 0), 0.085, 0.07))
    post.add(cyl((0, 0.84, 0), 0.085, 0.025, 0.012), k=0.02)
    body.piece(ORANGE, tris=60).add(cyl((0, 0.36, 0), 0.095, 0.03, 0.012))
    body.piece(STEEL_D, tris=60).add(cyl((0, 0.66, 0), 0.09, 0.012, 0.006))
    glow = part("borne_glow", res=0.008)
    glow.piece(TEAL, tris=60).add(ellipsoid((0, 0.89, 0), (0.068, 0.05, 0.068)))
    return [body, glow]


CHORD = 2 * R_POST * math.sin(math.radians(15))


def rail():
    """Rambarde entre deux bornes espacées de 30° : deux lisses de CHORD le long de X, centrées."""
    body = part("rail", res=0.01)
    h = CHORD * 0.5 - 0.06
    top = body.piece(HULL_D, tris=200)
    top.add(capsule((-h, 0.72, 0), (h, 0.72, 0), 0.036))
    low = body.piece(STEEL, tris=200)
    low.add(capsule((-h, 0.46, 0), (h, 0.46, 0), 0.024))
    # barreaux
    bar = body.piece(STEEL_D, tris=160)
    for x in (-0.35, 0.35):
        bar.add(capsule((x, 0.05, 0), (x, 0.72, 0), 0.022))
    return [body]


if __name__ == "__main__":
    run({"deck": deck, "borne": borne, "rail": rail}, sys.argv)
