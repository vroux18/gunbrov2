"""Atelier Blender des modèles de Jo (et de ses tenues) : formes nettes et graphiques, export GLB par parts.

Lancé par Blender en Python (sans interface) : /opt/bpyenv/bin/python tools/blender/jo.py [noms...]

Coordonnées : celles du jeu (Godot) — Y en haut, Jo regarde vers +Z, sa droite est en -X. La conversion vers
Blender (Z en haut) est faite à l'export : on n'écrit jamais de coordonnées Blender à la main.

Briques :
  loft(sections)   tube à section en rectangle arrondi / chanfreiné (torse, manches, jambes, chaussures, capuche,
                   mèches) : chaque section {c: centre, a: demi-largeur, b: demi-profondeur, r: arrondi, col: couleur
                   de la bande qui part de cette section}. nc = segments par coin (1 : chanfrein net, 2-3 : arrondi).
  ell(c, rx, ry, rz) volume ellipsoïdal facetté (tête, poings, chignons), box(c, h, r) boîte chanfreinée,
  torus(c, n, R, r) anneau (logo, bagues), disc(c, n, R0, R1, t) rondelle plate (motifs posés sur un vêtement).
Chaque brique a une couleur (par face) : aplats francs, pas d'occlusion cuite (le shader de Jo fait l'ombre).

Parts : Model.part(nom, pivot, parent) ; les noms et pivots sont le contrat du rig (scripts/rig3d.gd).
Normales : arêtes vives au-delà de SHARP degrés (look graphique), et une normale lissée par position, encodée
(octaèdre) dans UV (seul jeu de coordonnées), que le contour d'encre (shaders/jo_ink.gdshader) utilise pour ne pas
se fendre aux arêtes.
Couleurs : attribut de couleur par coin, en valeurs sRGB écrites telles quelles (le shader les lit en sRGB).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

SHARP = 32.0


def hexcol(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0, 1.0)


def V(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


# ------------------------------------------------------------------ géométrie (repère du jeu)
class Geo:
    """Sommets + faces + couleur par face, en coordonnées du jeu."""
    def __init__(self):
        self.v = []
        self.f = []
        self.col = []

    def extend(self, g):
        base = len(self.v)
        self.v += g.v
        self.f += [tuple(i + base for i in f) for f in g.f]
        self.col += g.col
        return self

    def paint(self, pred, color):
        """Recolore les faces dont le centre vérifie pred(centre, normale)."""
        c = hexcol(color)
        for i, f in enumerate(self.f):
            pts = [self.v[j] for j in f]
            ctr = sum(pts, Vector()) / len(pts)
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            n = n.normalized() if n.length > 1e-12 else Vector((0, 1, 0))
            if pred(ctr, n):
                self.col[i] = c
        return self

    def xform(self, fn):
        self.v = [V(fn(p)) for p in self.v]
        return self

    def mirror_x(self):
        g = Geo()
        g.v = [Vector((-p.x, p.y, p.z)) for p in self.v]
        g.f = [tuple(reversed(f)) for f in self.f]
        g.col = list(self.col)
        return g


def ring2d(a, b, r, nc):
    r = max(1e-4, min(r, a - 1e-4, b - 1e-4))
    pts = []
    for cx, cy, a0 in ((a - r, b - r, 0), (-(a - r), b - r, 90), (-(a - r), -(b - r), 180), (a - r, -(b - r), 270)):
        for i in range(nc + 1):
            ang = math.radians(a0 + 90.0 * i / nc)
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def loft(sections, color="#FFFFFF", nc=2, ref=(1, 0, 0), caps=(True, True)):
    """Tube passant par les sections (voir l'en-tête). ref : direction de la largeur (a)."""
    g = Geo()
    base_col = hexcol(color)
    cs = [V(s["c"]) for s in sections]
    n = len(sections)
    rings = []
    R = V(ref).normalized()
    for i, s in enumerate(sections):
        if n == 1:
            t = Vector((0, 1, 0))
        elif i == 0:
            t = cs[1] - cs[0]
        elif i == n - 1:
            t = cs[-1] - cs[-2]
        else:
            t = (cs[i + 1] - cs[i]).normalized() + (cs[i] - cs[i - 1]).normalized()
        t = V(s["t"]).normalized() if "t" in s else t.normalized()
        rr = V(s["ref"]).normalized() if "ref" in s else R
        u = (rr - t * rr.dot(t))
        u = u.normalized() if u.length > 1e-6 else Vector((1, 0, 0))
        w = u.cross(t)  # profondeur (b) : vers +Z pour un tube qui monte
        pts = ring2d(s["a"], s["b"], s.get("r", min(s["a"], s["b"]) * 0.5), s.get("nc", nc))
        idx = []
        for (x, y) in pts:
            g.v.append(cs[i] + u * x + w * y)
            idx.append(len(g.v) - 1)
        rings.append(idx)
    m = len(rings[0])
    for i in range(n - 1):
        c = hexcol(sections[i]["col"]) if "col" in sections[i] else base_col
        for j in range(m):
            a, b = rings[i][j], rings[i][(j + 1) % m]
            c2, d = rings[i + 1][(j + 1) % m], rings[i + 1][j]
            g.f.append((a, b, c2, d))
            g.col.append(c)
    if caps[0]:
        g.f.append(tuple(reversed(rings[0])))
        g.col.append(hexcol(sections[0]["col"]) if "col" in sections[0] else base_col)
    if caps[1]:
        g.f.append(tuple(rings[-1]))
        g.col.append(hexcol(sections[-2]["col"]) if "col" in sections[-2] else base_col)
    return g


def smooth(sections, k=2):
    """Sections intermédiaires (spline de Catmull-Rom sur centre, tailles, arrondi) : silhouettes plus souples.
    La couleur d'une bande (col) reste celle de la section d'origine qui l'ouvre."""
    n = len(sections)
    if n < 3 or k <= 1:
        return sections
    def get(i):
        return sections[max(0, min(n - 1, i))]
    def cr(p0, p1, p2, p3, t):
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
    out = []
    for i in range(n - 1):
        s0, s1, s2, s3 = get(i - 1), get(i), get(i + 1), get(i + 2)
        for j in range(k):
            t = j / k
            if j == 0:
                out.append(dict(s1))
                continue
            d = {}
            d["c"] = cr(V(s0["c"]), V(s1["c"]), V(s2["c"]), V(s3["c"]), t)
            for key in ("a", "b"):
                d[key] = max(1e-4, cr(s0[key], s1[key], s2[key], s3[key], t))
            r1 = s1.get("r", min(s1["a"], s1["b"]) * 0.5)
            r2 = s2.get("r", min(s2["a"], s2["b"]) * 0.5)
            d["r"] = r1 + (r2 - r1) * t
            if "col" in s1:
                d["col"] = s1["col"]
            if "nc" in s1:
                d["nc"] = s1["nc"]
            out.append(d)
    out.append(dict(sections[-1]))
    return out


def ell(c, rx, ry, rz, color="#FFFFFF", n=7, nc=2, ref=(1, 0, 0), up=(0, 1, 0), squash=None):
    """Volume ellipsoïdal facetté : n tranches le long de `up`."""
    c = V(c)
    up = V(up).normalized()
    secs = []
    for i in range(n + 1):
        th = -math.pi / 2 + math.pi * i / n
        k = max(math.cos(th), 0.06)
        y = math.sin(th) * ry
        a, b = rx * k, rz * k
        secs.append({"c": c + up * y, "a": a, "b": b, "r": min(a, b) * 0.62, "t": up})
    return loft(secs, color, nc=nc, ref=ref)


def box(c, h, r=0.01, color="#FFFFFF", nc=1, up=(0, 1, 0), ref=(1, 0, 0)):
    """Boîte chanfreinée : demi-tailles h = (largeur, hauteur le long de up, profondeur)."""
    c = V(c)
    up = V(up).normalized()
    secs = [
        {"c": c - up * h[1], "a": h[0] - r, "b": h[2] - r, "r": max(0.0, min(h[0], h[2]) - r) * 0.5, "t": up},
        {"c": c - up * (h[1] - r), "a": h[0], "b": h[2], "r": r, "t": up},
        {"c": c + up * (h[1] - r), "a": h[0], "b": h[2], "r": r, "t": up},
        {"c": c + up * h[1], "a": h[0] - r, "b": h[2] - r, "r": max(0.0, min(h[0], h[2]) - r) * 0.5, "t": up},
    ]
    return loft(secs, color, nc=nc, ref=ref)


def _frame(nrm):
    n = V(nrm).normalized()
    a = Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))
    u = a.cross(n).normalized()
    w = n.cross(u)
    return n, u, w


def torus(c, nrm, R, r, color="#FFFFFF", seg=28, rs=6):
    n, u, w = _frame(nrm)
    c = V(c)
    g = Geo()
    for i in range(seg):
        a = 2 * math.pi * i / seg
        d = u * math.cos(a) + w * math.sin(a)
        for j in range(rs):
            b = 2 * math.pi * j / rs
            g.v.append(c + d * (R + r * math.cos(b)) + n * (r * math.sin(b)))
    col = hexcol(color)
    for i in range(seg):
        for j in range(rs):
            a = i * rs + j
            b = ((i + 1) % seg) * rs + j
            cc = ((i + 1) % seg) * rs + (j + 1) % rs
            d = i * rs + (j + 1) % rs
            g.f.append((a, b, cc, d))
            g.col.append(col)
    return g


def disc(c, nrm, R0, R1, t, color="#FFFFFF", seg=32, arc=(0.0, 360.0)):
    """Rondelle plate (anneau plein si R0 = 0) d'épaisseur t, posée selon la normale nrm. arc : portion en degrés."""
    n, u, w = _frame(nrm)
    c = V(c)
    g = Geo()
    full = abs(arc[1] - arc[0]) >= 359.9
    cnt = seg if full else seg + 1
    for k, off in enumerate((-t * 0.5, t * 0.5)):
        for i in range(cnt):
            a = math.radians(arc[0] + (arc[1] - arc[0]) * i / seg)
            d = u * math.cos(a) + w * math.sin(a)
            g.v.append(c + n * off + d * max(R0, 1e-4))
            g.v.append(c + n * off + d * R1)
    col = hexcol(color)
    def vi(k, i, outer):
        return k * cnt * 2 + i * 2 + (1 if outer else 0)
    rng = range(seg) if full else range(cnt - 1)
    for i in rng:
        i2 = (i + 1) % cnt
        g.f.append((vi(1, i, False), vi(1, i, True), vi(1, i2, True), vi(1, i2, False)))  # dessus
        g.f.append((vi(0, i2, False), vi(0, i2, True), vi(0, i, True), vi(0, i, False)))  # dessous
        g.f.append((vi(0, i, True), vi(0, i2, True), vi(1, i2, True), vi(1, i, True)))  # bord extérieur
        g.f.append((vi(1, i, False), vi(1, i2, False), vi(0, i2, False), vi(0, i, False)))  # bord intérieur
        g.col += [col] * 4
    if not full:
        for i in (0, cnt - 1):
            q = (vi(0, i, False), vi(0, i, True), vi(1, i, True), vi(1, i, False))
            g.f.append(q if i else tuple(reversed(q)))
            g.col.append(col)
    return g


def star(c, nrm, R, r, t, color="#FFFFFF", n=5, spin=0.0):
    """Étoile plate à n branches (rayons R / r), épaisseur t, posée selon la normale nrm."""
    nn, u, w = _frame(nrm)
    c = V(c)
    g = Geo()
    pts = []
    for i in range(2 * n):
        a = math.radians(spin) + math.pi * i / n + math.pi / 2
        rr = R if i % 2 == 0 else r
        pts.append(u * math.cos(a) * rr + w * math.sin(a) * rr)
    for k, off in enumerate((-t * 0.5, t * 0.5)):
        g.v.append(c + nn * off)
        for p in pts:
            g.v.append(c + nn * off + p)
    m = len(pts)
    col = hexcol(color)
    for i in range(m):
        j = (i + 1) % m
        g.f.append((0, 1 + j, 1 + i))  # dessous
        g.f.append((m + 1, m + 2 + i, m + 2 + j))  # dessus
        g.f.append((1 + i, 1 + j, m + 2 + j, m + 2 + i))
        g.col += [col] * 3
    return g


def strip(points, width, thick, color="#FFFFFF", side=(1, 0, 0), widths=None, nc=1):
    """Bande plate (écharpe, sangle, mèche plate) le long d'une ligne de points ; `side` : sens de la largeur."""
    secs = []
    for i, p in enumerate(points):
        wv = widths[i] if widths else width
        secs.append({"c": p, "a": wv * 0.5, "b": thick * 0.5, "r": thick * 0.45})
    return loft(secs, color, nc=nc, ref=side)


# ------------------------------------------------------------------ modèle par parts
def shell(sections, thick, color="#FFFFFF", inner=None, seg=20, caps=True):
    """Coque ouverte d'épaisseur `thick` (capuche, cape, jupe, col) : chaque section est un arc d'ellipse
    {c, a: rayon en X, b: rayon en Z, a0, a1: angles en degrés (0 = +X, 90 = +Z devant, 270 = dos), col?}.
    Arc complet (a1 - a0 >= 360) : tube fermé (jupe). `inner` : couleur de la face intérieure (doublure)."""
    g = Geo()
    n = len(sections)
    full = all(abs(s["a1"] - s["a0"]) >= 359.9 for s in sections)
    cnt = seg if full else seg + 1
    base = hexcol(color)
    inn = hexcol(inner) if inner else base
    rings = []
    for s in sections:
        c = V(s["c"])
        out_i, in_i = [], []
        for i in range(cnt):
            th = math.radians(s["a0"] + (s["a1"] - s["a0"]) * i / seg)
            d = Vector((math.cos(th), 0.0, math.sin(th)))
            wv = 1.0
            if "wave" in s:  # plis : rayon modulé le long de l'arc (amplitude, nombre de plis sur 360°)
                wv += s["wave"][0] * math.sin(th * s["wave"][1])
            p = c + Vector((d.x * s["a"] * wv, 0.0, d.z * s["b"] * wv))
            nrm = Vector((d.x / max(s["a"], 1e-4), 0.0, d.z / max(s["b"], 1e-4))).normalized()
            g.v.append(p + nrm * thick * 0.5)
            out_i.append(len(g.v) - 1)
            g.v.append(p - nrm * thick * 0.5)
            in_i.append(len(g.v) - 1)
        rings.append((out_i, in_i))
    rng = range(cnt) if full else range(cnt - 1)
    for k in range(n - 1):
        c = hexcol(sections[k]["col"]) if "col" in sections[k] else base
        ci = hexcol(sections[k]["coli"]) if "coli" in sections[k] else inn
        o0, i0 = rings[k]
        o1, i1 = rings[k + 1]
        for i in rng:
            j = (i + 1) % cnt
            g.f.append((o0[i], o1[i], o1[j], o0[j]))
            g.col.append(c)
            g.f.append((i0[j], i1[j], i1[i], i0[i]))
            g.col.append(ci)
        if not full:
            for i, flip in ((0, False), (cnt - 1, True)):
                q = (o0[i], i0[i], i1[i], o1[i])
                g.f.append(tuple(reversed(q)) if flip else q)
                g.col.append(c)
    if caps:
        for k, flip in ((0, True), (n - 1, False)):
            o, ii = rings[k]
            c = hexcol(sections[min(k, n - 2)].get("col", color))
            for i in rng:
                j = (i + 1) % cnt
                q = (o[i], o[j], ii[j], ii[i])
                g.f.append(tuple(reversed(q)) if flip else q)
                g.col.append(c)
    return g


def rot(g, center, axis, deg):
    """Tourne la géométrie autour d'un axe passant par center."""
    from mathutils import Matrix
    M = Matrix.Rotation(math.radians(deg), 3, V(axis).normalized())
    c = V(center)
    g.v = [c + M @ (p - c) for p in g.v]
    return g


def surface(g, origin, direction):
    """Point de la surface de g touché par le rayon (origin, direction) : pour poser yeux, motifs, coutures."""
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([tuple(v) for v in g.v], g.f)
    hit = tree.ray_cast(V(origin), V(direction).normalized())
    if hit[0] is None:
        return V(origin), -V(direction).normalized()
    return hit[0], hit[1]


class Part:
    def __init__(self, name, pivot, parent):
        self.name = name
        self.pivot = V(pivot)
        self.parent = parent
        self.geo = Geo()

    def add(self, g):
        self.geo.extend(g)
        return g


class Model:
    def __init__(self, name):
        self.name = name
        self.parts = {}

    def part(self, name, pivot=None, parent=None):
        if name not in self.parts:
            self.parts[name] = Part(name, pivot, parent)
        return self.parts[name]

    def tris(self):
        return sum(sum(len(f) - 2 for f in p.geo.f) for p in self.parts.values())

    def export(self, path):
        _reset()
        objs = {}
        order = []
        done = set()
        parts = [p for p in self.parts.values() if p.geo.f]
        while len(order) < len(parts):
            for p in parts:
                if p.name not in done and (p.parent is None or p.parent in done or p.parent not in self.parts):
                    order.append(p)
                    done.add(p.name)
        total = 0
        for p in order:
            ob = _make_object(p)
            objs[p.name] = ob
            if p.parent and p.parent in objs:
                ob.parent = objs[p.parent]
                par = self.parts[p.parent].pivot
                ob.location = _to_bl(p.pivot - par)
            else:
                ob.location = _to_bl(p.pivot)
            n = sum(len(f) - 2 for f in p.geo.f)
            total += n
            print("  %-12s %6d triangles" % (p.name, n))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_vertex_color="ACTIVE",
                                  export_all_vertex_colors=False, export_materials="NONE", export_normals=True,
                                  export_texcoords=True, export_yup=True, export_apply=False, use_selection=False,
                                  export_animations=False, export_skins=False, export_morph=False)
        print("%s : %d triangles -> %s" % (self.name, total, path))
        return total


def _to_bl(p):
    return Vector((p.x, -p.z, p.y))


def _reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def _oct(n):
    s = abs(n.x) + abs(n.y) + abs(n.z)
    x, y, z = n.x / s, n.y / s, n.z / s
    if z < 0:
        x, y = (1 - abs(y)) * (1 if x >= 0 else -1), (1 - abs(x)) * (1 if y >= 0 else -1)
    return x * 0.5 + 0.5, y * 0.5 + 0.5


def _make_object(p):
    g = p.geo
    verts = [_to_bl(v - p.pivot) for v in g.v]
    me = bpy.data.meshes.new(p.name + "_mesh")
    me.from_pydata([tuple(v) for v in verts], [], g.f)
    me.validate()
    # normales sortantes
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    nf = len(me.polygons)
    # couleur par coin
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    for poly in me.polygons:
        c = g.col[poly.index] if poly.index < len(g.col) else (1, 1, 1, 1)
        for li in poly.loop_indices:
            attr.data[li].color = c
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = 0
    # arêtes vives au-delà de SHARP degrés
    me.set_sharp_from_angle(angle=math.radians(SHARP))
    for poly in me.polygons:
        poly.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(SHARP))
    # normale lissée par position (repère du jeu), encodée dans UV (le V est retourné par l'export glTF)
    acc = {}
    for poly in me.polygons:
        nb = poly.normal
        ng = Vector((nb.x, nb.z, -nb.y))
        for vi in poly.vertices:
            key = tuple(round(c, 5) for c in me.vertices[vi].co)
            acc[key] = acc.get(key, Vector()) + ng * poly.area
    uv2 = me.uv_layers.new(name="Outline")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            key = tuple(round(c, 5) for c in me.vertices[vi].co)
            n = acc[key]
            n = n.normalized() if n.length > 1e-12 else Vector((0, 1, 0))
            u, v = _oct(n)
            uv2.data[li].uv = (u, 1.0 - v)
    ob = bpy.data.objects.new(p.name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob
