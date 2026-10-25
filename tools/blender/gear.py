"""Équipement visible de Jo (loot), sculpté dans Blender (sans interface) : un GLB par objet.

/opt/bpyenv/bin/python tools/blender/gear.py                 tous les objets -> assets/chars3d/gear_<id>.glb
/opt/bpyenv/bin/python tools/blender/gear.py pile aimant     seulement ceux-là
puis  $G --headless --path . --import  et les icônes : tools/item_icons.tscn (voir son en-tête).

Même direction que Jo (tools/blender/jo.py) : formes nettes à chanfreins, aplats francs, une ou deux couleurs
fortes par objet, contour d'encre et rendu BD par le matériau de Jo (aucun matériau en plus : couleurs par
sommet). Coordonnées : celles de Jo (repère du jeu, Jo regarde vers +Z, sa droite en -X), à ses proportions
exactes ; rien n'est ajusté au chargement.

Contrat avec scripts/rig3d.gd (apply_items) : chaque part s'appelle « <cible>__<id> », où <cible> est une part de
Jo (head, torso, arm_l, arm_r, gun, shin_r, shin_l) ; elle a le pivot de cette part (PIV de jo.py) et le rig la
range dedans telle quelle. Les parts « <cible>__<id>_glow » sont blanches : le jeu les teinte à la couleur de
rareté. Une arme (cible gun) remplace le blaster : la poignée est dans le poing, le canon vers -Y au repos, le
dessus vers +Z ; le bout du canon de chaque arme est MUZZLE dans rig3d.gd (BOUT ci-dessous, à recopier).

Zones de tenue (rig3d.gd _gear_zones) : l'objet porté masque la pièce de tenue de sa zone, d'après sa forme :
  tête     monte au-dessus du crâne (casque, serre-tête) -> coiffe et visage ; sinon (visière) -> visage
  torse    devant / autour du cou -> col ; dans le dos (gadget : dépasse en z < -0,15) -> dos (cape, sac)
  bras     posé sur l'épaule (module) -> épaulette ; jambes : descend jusqu'au sol (bottes, patins) -> chaussures
Les gadgets de dos tiennent par un harnais (plaque dorsale et deux sangles par-dessus les épaules) ; les modules
d'épaule par une selle et une sangle autour du haut du bras : rien ne flotte, même sur les tenues amples.

Chaque objet doit se reconnaître seul en icône de 96 px (silhouette d'abord) et rester lisible porté par Jo vue
d'en haut (~55 px). Trois familles : équipement de garde (blanc, gris, orange de signalisation), Nébuleuse 7
(matériel de quai Hélix Fret : bleu acier, orange, rayures) et Cité Néon (rose #FF3CAC, bleu #3C8CFF, nuit).
Budget : 3 200 triangles par objet (le script affiche le compte).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from jo_lib import *  # noqa
from jo import PIV, ROOT, S, INK, WHITE, LGRAY, MGRAY, DGRAY  # noqa

GLOW = "#FFFFFF"
ORANGE = "#FF7A2F"
ORANGE_D = "#D9561C"
NAVY = "#25304C"
STEEL = "#7E8AA2"
STEEL_D = "#5B6780"
# Nébuleuse 7 : livrée Hélix Fret
STEELB = "#4F6D96"
STEELB_D = "#34496B"
CLAW = "#C9D2E0"
# Cité Néon
PINK = "#FF3CAC"
PINK_L = "#FF8ACB"
BLUE = "#3C8CFF"
NIGHT = "#2E2452"
PEARL = "#F4F0FF"
# veste de pilote
LEATHER = "#8B5A3C"
LEATHER_D = "#5E3B28"
FLEECE = "#F1E3C8"
MAG_RED = "#E5484D"

BUDGET = 3200
# bout du canon de chaque arme, dans le repère de la part « gun » (à recopier dans MUZZLE de scripts/rig3d.gd)
BOUT = {}


class Gear(Model):
    def __init__(self, gid):
        super().__init__("gear_" + gid)
        self.gid = gid

    def p(self, target, glow=False, sub=""):
        """Part « cible__id » (ou « cible__id_glow », « cible__id_<sub> ») au pivot de la part cible de Jo."""
        nm = "%s__%s%s%s" % (target, self.gid, "_" + sub if sub else "", "_glow" if glow else "")
        return self.part(nm, PIV[target], None)


def V3(x, y, z):
    return Vector((x, y, z))


def bar(a, b, w, d, col, ref=(1, 0, 0), r=None, nc=1):
    """Barre chanfreinée de a à b : demi-largeur w (selon ref), demi-épaisseur d."""
    rr = r if r is not None else min(w, d) * 0.45
    return loft([S(a, w, d, rr), S(b, w, d, rr)], col, nc=nc, ref=ref)


def rod(pts, r, col, nc=1, ref=(1, 0, 0)):
    """Tube à section octogonale le long des points."""
    return loft([S(p, r, r, r * 0.42) for p in pts], col, nc=nc, ref=ref)


def cyl(c, axis, r, h, col, r2=None, nc=1, ref=None):
    """Cylindre octogonal d'axe `axis` (rayon r, r2 au bout), hauteur h, centré en c."""
    ax = V(axis).normalized()
    c = V(c)
    rr2 = r if r2 is None else r2
    if ref is None:
        ref = (0, 1, 0) if abs(ax.y) < 0.9 else (1, 0, 0)
    return loft([S(c - ax * h * 0.5, r, r, r * 0.42), S(c + ax * h * 0.5, rr2, rr2, rr2 * 0.42)], col, nc=nc, ref=ref)


def ring(c, a, b, h, t, col, seg=20, a0=0.0, a1=360.0):
    """Bande horizontale (coque d'épaisseur t) de hauteur h autour d'une ellipse a, b centrée en c."""
    c = V(c)
    return shell([{"c": c - V3(0, h * 0.5, 0), "a": a, "b": b, "a0": a0, "a1": a1},
                  {"c": c + V3(0, h * 0.5, 0), "a": a, "b": b, "a0": a0, "a1": a1}], t, col, seg=seg)


def helix_rod(c, R, h, turns, wire, col, seg=8):
    """Ressort à boudin d'axe Y."""
    n = int(turns * seg)
    pts = []
    for i in range(n + 1):
        t = i / n
        a = t * turns * math.tau
        pts.append(V3(c[0] + R * math.cos(a), c[1] - h * 0.5 + h * t, c[2] + R * math.sin(a)))
    return loft([{"c": p, "a": wire, "b": wire, "r": wire * 0.4} for p in pts], col, nc=1, ref=(0, 1, 0))


def mirror(g):
    return g.mirror_x()


# ------------------------------------------------------------------ tête (pivot du cou)
def casque_garde():
    """Casque de garde : coque blanche facettée qui enveloppe le crâne et les cheveux, ouverte sur le visage,
    visière sombre en casquette, crête orange de l'avant à la nuque, oreillettes ; filet lumineux sous la visière
    et sur les oreillettes."""
    g = Gear("casque_garde")
    a, gl = g.p("head"), g.p("head", True)
    dome = [(1.098, 0.118, 0.142, -0.014), (1.15, 0.116, 0.138, -0.014), (1.205, 0.1, 0.12, -0.014),
            (1.245, 0.07, 0.084, -0.012), (1.267, 0.032, 0.04, -0.012)]
    a.add(loft([S((0, y, z), aa, bb, min(aa, bb) * 0.55) for (y, aa, bb, z) in dome], WHITE, nc=2))
    # jupe : nuque et tempes, ouverte devant sur le visage
    a.add(shell([{"c": (0, 0.985, -0.034), "a": 0.112, "b": 0.136, "a0": 90 + 78, "a1": 450 - 78},
                 {"c": (0, 1.04, -0.022), "a": 0.118, "b": 0.142, "a0": 90 + 60, "a1": 450 - 60},
                 {"c": (0, 1.104, -0.014), "a": 0.118, "b": 0.142, "a0": 90 + 40, "a1": 450 - 40}], 0.012, WHITE,
                inner=LGRAY, seg=24))
    a.geo.paint(lambda c, n: c.y < 1.0 and c.z < -0.05, LGRAY)  # bord de nuque
    # visière en casquette, sombre, qui avance sur le front
    a.add(shell([{"c": (0, 1.088, 0.0), "a": 0.124, "b": 0.142, "a0": 38, "a1": 142},
                 {"c": (0, 1.108, 0.004), "a": 0.124, "b": 0.15, "a0": 34, "a1": 146}], 0.012, DGRAY, seg=14))
    # crête orange
    a.add(loft([S((0, 1.2, 0.112), 0.016, 0.014, 0.006), S((0, 1.258, 0.06), 0.017, 0.016, 0.006),
                S((0, 1.274, -0.012), 0.017, 0.016, 0.006), S((0, 1.252, -0.09), 0.016, 0.015, 0.006),
                S((0, 1.19, -0.14), 0.014, 0.013, 0.005)], ORANGE, nc=1))
    for sx in (-1, 1):
        a.add(cyl((sx * 0.124, 1.05, -0.01), (1, 0, 0), 0.034, 0.016, DGRAY))
        a.add(box((sx * 0.112, 1.16, -0.02), (0.008, 0.03, 0.05), 0.004, LGRAY))  # aération
        gl.add(disc((sx * 0.1325, 1.05, -0.01), (sx, 0, 0), 0.016, 0.024, 0.004, GLOW, seg=12))
    gl.add(shell([{"c": (0, 1.078, 0.0), "a": 0.122, "b": 0.14, "a0": 46, "a1": 134},
                  {"c": (0, 1.084, 0.0), "a": 0.122, "b": 0.14, "a0": 46, "a1": 134}], 0.008, GLOW, seg=10))
    return g


def casque_docker():
    """Casque de docker (N7) : coque de chantier orange à nervure centrale, large rebord plus long devant,
    bandeau Hélix bleu acier à filet clair, lampe frontale lumineuse. Les yeux restent dégagés."""
    g = Gear("casque_docker")
    a, gl = g.p("head"), g.p("head", True)
    dome = [(1.1, 0.116, 0.128, -0.004), (1.16, 0.114, 0.126, -0.006), (1.215, 0.096, 0.108, -0.008),
            (1.255, 0.062, 0.072, -0.01), (1.276, 0.022, 0.026, -0.01)]
    a.add(loft([S((0, y, z), aa, bb, min(aa, bb) * 0.5) for (y, aa, bb, z) in dome], ORANGE, nc=2))
    a.add(loft([S((0, 1.235, 0.11), 0.014, 0.012, 0.005), S((0, 1.282, 0.04), 0.016, 0.014, 0.005),
                S((0, 1.284, -0.05), 0.016, 0.014, 0.005), S((0, 1.235, -0.125), 0.014, 0.012, 0.005)], ORANGE_D, nc=1))
    # rebord : dalle chanfreinée, plus longue devant
    a.add(loft([S((0, 1.088, 0.022), 0.148, 0.166, 0.11), S((0, 1.104, 0.022), 0.15, 0.168, 0.11)], ORANGE_D, nc=2))
    a.add(ring((0, 1.127, -0.004), 0.119, 0.131, 0.026, 0.006, STEELB, seg=24))
    a.add(ring((0, 1.127, -0.004), 0.123, 0.135, 0.007, 0.004, WHITE, seg=24))
    # lampe frontale
    a.add(box((0, 1.17, 0.124), (0.03, 0.022, 0.016), 0.006, DGRAY, up=(0, 1, -0.35)))
    gl.add(disc((0, 1.172, 0.142), (0, 0.3, 1), 0.0, 0.019, 0.006, GLOW, seg=12))
    for sx in (-1, 1):  # deux voyants sur le bandeau, à l'arrière
        gl.add(box((sx * 0.06, 1.127, -0.136), (0.014, 0.006, 0.004), 0.002, GLOW))
    return g


def visiere():
    """Visière de pilote : bandeau sombre qui passe devant les yeux d'une tempe à l'autre, verre lumineux,
    oreillette orange à droite avec antenne courte."""
    g = Gear("visiere")
    a, gl = g.p("head"), g.p("head", True)
    a.add(shell([{"c": (0, 1.03, 0.0), "a": 0.096, "b": 0.108, "a0": 8, "a1": 172},
                 {"c": (0, 1.078, 0.0), "a": 0.096, "b": 0.108, "a0": 8, "a1": 172}], 0.01, DGRAY, seg=16))
    for sx in (-1, 1):
        a.add(cyl((sx * 0.108, 1.054, 0.0), (1, 0, 0), 0.028, 0.032, ORANGE if sx < 0 else DGRAY))
    a.add(rod([(-0.118, 1.07, -0.01), (-0.128, 1.15, -0.03)], 0.004, DGRAY))
    gl.add(shell([{"c": (0, 1.04, 0.0), "a": 0.1, "b": 0.113, "a0": 40, "a1": 140},
                  {"c": (0, 1.07, 0.0), "a": 0.1, "b": 0.113, "a0": 40, "a1": 140}], 0.006, GLOW, seg=10))
    gl.add(box((-0.128, 1.152, -0.03), (0.007, 0.007, 0.007), 0.003, GLOW))
    return g


def oreilles_chat():
    """Serre-tête néon (Cité Néon) : arceau rose qui passe sur le sommet du crâne d'une oreille à l'autre, tube
    néon lumineux sur sa crête, écouteurs bleu nuit à anneau lumineux, micro rose devant la bouche."""
    g = Gear("oreilles_chat")
    a, gl = g.p("head"), g.p("head", True)
    pts, pts2 = [], []
    for i in range(11):
        th = math.radians(-82 + 164 * i / 10)
        pts.append((0.114 * math.sin(th), 1.068 + 0.166 * math.cos(th), 0.004))
        pts2.append((0.124 * math.sin(th), 1.068 + 0.176 * math.cos(th), 0.004))
    a.add(loft([S(p, 0.017, 0.007, 0.004) for p in pts], PINK, nc=1, ref=(0, 0, 1)))
    gl.add(loft([S(p, 0.005, 0.005, 0.002) for p in pts2[1:-1]], GLOW, nc=1, ref=(0, 0, 1)))
    for sx in (-1, 1):
        a.add(box((sx * 0.112, 1.05, 0.002), (0.018, 0.034, 0.03), 0.01, NIGHT))
        a.add(box((sx * 0.131, 1.05, 0.002), (0.004, 0.022, 0.02), 0.003, BLUE))
        gl.add(disc((sx * 0.1315, 1.05, 0.002), (sx, 0, 0), 0.022, 0.03, 0.006, GLOW, seg=12))
    a.add(rod([(-0.112, 1.03, 0.025), (-0.09, 1.0, 0.075), (-0.045, 0.988, 0.105)], 0.0045, NIGHT))
    a.add(box((-0.04, 0.988, 0.108), (0.008, 0.006, 0.006), 0.003, PINK))
    return g


# ------------------------------------------------------------------ torse (pivot des hanches)
VEST = [  # y, a, b, z : coque de vêtement autour du torse, en rectangle arrondi comme le torse de Jo et des tenues,
    # assez ample pour les plus épaisses (doudoune polaire, scaphandre, armure méca)
    (0.6, 0.16, 0.132, 0.006), (0.66, 0.158, 0.126, 0.006), (0.73, 0.157, 0.126, 0.008), (0.8, 0.164, 0.126, 0.01),
    (0.86, 0.176, 0.118, 0.006), (0.9, 0.166, 0.106, 0.0), (0.93, 0.12, 0.086, -0.006)]


def prof(a, b, r, nc, front=None):
    """Contour (x, z) en rectangle arrondi ; front : seulement l'avant, jusqu'à z = front * b sur les côtés."""
    pts = ring2d(a, b, r, nc)
    if front is None:
        return pts
    k = nc + 1
    return [(a, front * b)] + pts[:2 * k] + [(-a, front * b)]


def rshell(secs, t, col, nc=2, front=None, inner=None):
    """Coque d'épaisseur t le long de sections horizontales {y, a, b, z, r?, col?} en rectangle arrondi (rebords
    en haut et en bas) ; front : coque ouverte derrière (plaque de poitrine)."""
    g = Geo()
    base = hexcol(col)
    inn = hexcol(inner) if inner else base
    O, I = [], []
    for s in secs:
        r = s.get("r", min(s["a"], s["b"]) * 0.62)
        for dst, (aa, bb, rr) in ((O, (s["a"], s["b"], r)), (I, (s["a"] - t, s["b"] - t, max(r - t, 0.002)))):
            idx = []
            for (x, z) in prof(aa, bb, rr, nc, front):
                g.v.append(V3(x, s["y"], s["z"] + z))
                idx.append(len(g.v) - 1)
            dst.append(idx)
    m = len(O[0])
    closed = front is None
    js = range(m) if closed else range(m - 1)
    for i in range(len(secs) - 1):
        c = hexcol(secs[i]["col"]) if "col" in secs[i] else base
        for j in js:
            j2 = (j + 1) % m
            g.f.append((O[i][j], O[i][j2], O[i + 1][j2], O[i + 1][j]))
            g.col.append(c)
            g.f.append((I[i][j], I[i + 1][j], I[i + 1][j2], I[i][j2]))
            g.col.append(inn)
        if not closed:
            for j in (0, m - 1):
                g.f.append((O[i][j], O[i + 1][j], I[i + 1][j], I[i][j]))
                g.col.append(c)
    for i in (0, len(secs) - 1):
        c = hexcol(secs[min(i, len(secs) - 2)].get("col", col))
        for j in js:
            j2 = (j + 1) % m
            g.f.append((O[i][j], I[i][j], I[i][j2], O[i][j2]))
            g.col.append(c)
    return g


def vest_secs(grow=0.0, ys=None):
    rows = VEST if ys is None else [(y,) + tuple(vest_at(y)) for y in ys]
    return [{"y": y, "a": aa + grow, "b": bb + grow, "z": z} for (y, aa, bb, z) in rows]


def vest_shell(col, thick=0.014):
    return rshell(vest_secs(), thick, col, nc=2)


def band(y, h, grow, t, col):
    """Bande horizontale posée sur la coque VEST (hauteur h autour de y)."""
    return rshell(vest_secs(grow, (y - h * 0.5, y + h * 0.5)), t, col, nc=2)


def vest_at(y):
    """(a, b, z) de la coque VEST à la hauteur y (interpolation linéaire)."""
    for (y0, a0, b0, z0), (y1, a1, b1, z1) in zip(VEST, VEST[1:]):
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            return a0 + (a1 - a0) * t, b0 + (b1 - b0) * t, z0 + (z1 - z0) * t
    return VEST[-1][1:]


def on_vest(x, y, out=0.008):
    """Point de la face avant de la coque VEST (x, y), décollé de `out`."""
    aa, bb, z = vest_at(y)
    r = min(aa, bb) * 0.62
    ax = abs(x)
    if ax <= aa - r:
        return V3(x, y, z + bb + out)
    d = min(ax - (aa - r), r)
    return V3(x, y, z + bb - r + math.sqrt(max(0.0, r * r - d * d)) + out)


def veste():
    """Veste de pilote : blouson de cuir brun court, glissière, bord-côtes et poignets foncés, gros col fourré
    crème rabattu, manches jusqu'au coude ; insigne d'ailes lumineux sur le cœur."""
    g = Gear("veste")
    a, gl = g.p("torso"), g.p("torso", True)
    a.add(vest_shell(LEATHER))
    a.add(band(0.614, 0.03, 0.004, 0.012, LEATHER_D))
    a.add(loft([S(on_vest(0, y, 0.004), 0.004, 0.003, 0.0015) for y in (0.6, 0.66, 0.73, 0.8, 0.86, 0.9)], INK, nc=1))
    for sx in (-1, 1):  # poches passepoilées en biais
        a.add(loft([S(on_vest(sx * 0.06, 0.66, 0.004), 0.003, 0.003, 0.001),
                    S(on_vest(sx * 0.11, 0.7, 0.004), 0.003, 0.003, 0.001)], INK, nc=1))
    # col fourré : couronne épaisse, plus haute derrière, ouverte devant en revers
    a.add(shell([{"c": (0, 0.905, -0.006), "a": 0.136, "b": 0.11, "a0": 90 + 30, "a1": 450 - 30},
                 {"c": (0, 0.94, -0.012), "a": 0.118, "b": 0.098, "a0": 90 + 40, "a1": 450 - 40},
                 {"c": (0, 0.97, -0.02), "a": 0.098, "b": 0.086, "a0": 90 + 60, "a1": 450 - 60}], 0.022, FLEECE, seg=18))
    for sx in (-1, 1):
        a.add(loft([S(on_vest(sx * 0.03, 0.9, 0.01), 0.022, 0.006, 0.004), S(on_vest(sx * 0.05, 0.8, 0.008), 0.016, 0.005, 0.003)],
                   FLEECE, nc=1, ref=(1, 0, 0)))
    # manches : du haut de l'épaule au coude, poignet foncé
    for side, sx in (("r", -1), ("l", 1)):
        s = g.p("arm_" + side)
        s.add(ell((sx * 0.148, 0.892, -0.002), 0.058, 0.05, 0.058, LEATHER, n=5, nc=2))
        secs = [S((sx * 0.152, 0.89, -0.002), 0.06, 0.062), S((sx * 0.165, 0.825, -0.004), 0.058, 0.06),
                S((sx * 0.172, 0.765, -0.008), 0.054, 0.056), S((sx * 0.174, 0.742, -0.008), 0.056, 0.058, col=LEATHER_D),
                S((sx * 0.175, 0.718, -0.007), 0.054, 0.056)]
        s.add(loft(secs, LEATHER, nc=2))
    # insigne d'ailes sur le cœur (gauche de Jo, +X)
    c = on_vest(0.075, 0.83, 0.006)
    gl.add(box(c, (0.008, 0.008, 0.003), 0.003, GLOW))
    for sx in (-1, 1):
        w = box(c + V3(sx * 0.026, 0.004, -0.002), (0.02, 0.005, 0.003), 0.002, GLOW)
        rot(w, c, (0, 0, 1), sx * 14)
        gl.add(w)
        w2 = box(c + V3(sx * 0.02, -0.007, -0.002), (0.014, 0.004, 0.003), 0.002, GLOW)
        rot(w2, c, (0, 0, 1), sx * 6)
        gl.add(w2)
    return g


def gilet_fret():
    """Gilet de fret (N7) : gilet de manutention bleu acier matelassé, deux bandes orange à filet clair, col
    montant, glissière, poches de poitrine à rabat orange d'où dépassent des cellules d'énergie lumineuses."""
    g = Gear("gilet_fret")
    a, gl = g.p("torso"), g.p("torso", True)
    a.add(vest_shell(STEELB, thick=0.018))
    for y in (0.7, 0.775):
        a.add(band(y, 0.028, 0.004, 0.012, ORANGE))
        a.add(band(y, 0.008, 0.008, 0.008, WHITE))
    a.add(ring((0, 0.94, -0.012), 0.104, 0.086, 0.035, 0.016, STEELB_D, seg=18))  # col montant
    a.add(loft([S(on_vest(0, y, 0.006), 0.0045, 0.003, 0.0015) for y in (0.6, 0.66, 0.73, 0.8, 0.86, 0.9)], STEELB_D, nc=1))
    for sx in (-1, 1):
        p = on_vest(sx * 0.07, 0.835, 0.01)
        a.add(box(p, (0.034, 0.03, 0.014), 0.006, STEELB_D))
        a.add(box(p + V3(0, 0.03, 0.006), (0.036, 0.008, 0.012), 0.004, ORANGE))
        for dx in (-0.016, 0.0, 0.016):
            gl.add(box(p + V3(dx, 0.046, -0.002), (0.0065, 0.014, 0.0065), 0.003, GLOW))
    return g


def plastron():
    """Plastron cargo (garde) : plaque de poitrine acier à facettes, bord blanc, arête centrale sombre, chevron orange,
    sangles noires autour de la taille et par-dessus les épaules ; filet lumineux en haut de la plaque."""
    g = Gear("plastron")
    a, gl = g.p("torso"), g.p("torso", True)
    secs = [{"y": 0.68, "a": 0.15, "b": 0.13, "z": 0.006, "r": 0.06}, {"y": 0.74, "a": 0.16, "b": 0.136, "z": 0.008, "r": 0.06},
            {"y": 0.81, "a": 0.172, "b": 0.138, "z": 0.01, "r": 0.06}, {"y": 0.87, "a": 0.17, "b": 0.126, "z": 0.006, "r": 0.06},
            {"y": 0.905, "a": 0.13, "b": 0.11, "z": 0.0, "r": 0.05}]
    pl = rshell(secs, 0.022, STEEL, nc=1, front=-0.2, inner=DGRAY)
    pl.paint(lambda c, n: c.y < 0.71, STEEL_D)
    pl.paint(lambda c, n: c.y > 0.875, WHITE)
    a.add(pl)
    a.add(loft([S((0, 0.69, 0.138), 0.012, 0.008, 0.004), S((0, 0.77, 0.146), 0.012, 0.008, 0.004),
                S((0, 0.86, 0.134), 0.012, 0.008, 0.004)], DGRAY, nc=1))
    for sx in (-1, 1):
        a.add(loft([S((sx * 0.02, 0.745, 0.146), 0.006, 0.004, 0.002), S((sx * 0.085, 0.79, 0.15), 0.006, 0.004, 0.002)], ORANGE, nc=1))
        a.add(strip([(sx * 0.1, 0.885, 0.085), (sx * 0.1, 0.935, 0.0), (sx * 0.095, 0.89, -0.09), (sx * 0.09, 0.8, -0.1)],
                    0.024, 0.006, INK, side=(1, 0, 0)))
    a.add(band(0.66, 0.02, -0.028, 0.008, INK))  # sangle de taille, au ras du torse de Jo
    gl.add(rshell([{"y": 0.886, "a": 0.17, "b": 0.128, "z": 0.008, "r": 0.06}, {"y": 0.892, "a": 0.168, "b": 0.126, "z": 0.008, "r": 0.06}],
                  0.008, GLOW, nc=1, front=0.4))
    return g


def echarpe():
    """Écharpe fétiche (Cité Néon) : grosse écharpe rose à rayures bleues enroulée autour du cou, nouée sur le
    côté gauche, deux pans rayés qui tombent sur la poitrine en s'écartant ; franges lumineuses au bout des pans."""
    g = Gear("echarpe")
    a, gl = g.p("torso"), g.p("torso", True)
    # tour de cou : gros boudin plat en rectangle arrondi, rayé en travers
    wrap = rshell([{"y": 0.888, "a": 0.112, "b": 0.1, "z": 0.006}, {"y": 0.918, "a": 0.106, "b": 0.096, "z": 0.002},
                   {"y": 0.952, "a": 0.094, "b": 0.086, "z": -0.004}], 0.034, PINK, nc=3)
    wrap.paint(lambda c, n: int((math.degrees(math.atan2(c.z, c.x)) + 375) / 22.5) % 2 == 0 and n.y < 0.7 and n.y > -0.7, BLUE)
    a.add(wrap)
    a.add(ell((0.05, 0.878, 0.106), 0.032, 0.028, 0.026, PINK, n=4, nc=1))  # nœud
    # deux pans sur la poitrine, rayés, qui s'écartent en tombant
    tails = [([(0.05, 0.872, 0.11), (0.06, 0.83, 0.118), (0.07, 0.79, 0.12), (0.08, 0.75, 0.12), (0.09, 0.71, 0.118),
               (0.098, 0.675, 0.116)], 0.05),
             ([(0.052, 0.87, 0.112), (0.035, 0.83, 0.124), (0.022, 0.79, 0.126), (0.012, 0.755, 0.126), (0.006, 0.725, 0.124)], 0.046)]
    for pts, w in tails:
        secs = [S(p, w * (0.42 + 0.03 * i), 0.007, 0.003, col=(BLUE if i % 2 == 1 else PINK)) for i, p in enumerate(pts)]
        a.add(loft(secs, PINK, nc=1, ref=(1, 0, 0)))
    for pts, w in tails:
        tip = V(pts[-1])
        for k in (-1, 0, 1):
            gl.add(bar(tip + V3(k * w * 0.36, -0.002, 0.0), tip + V3(k * w * 0.4, -0.028, 0.002), 0.005, 0.0045, GLOW))
    return g


# ------------------------------------------------------------------ dos : gadgets sur harnais
def harness(a, plate=DGRAY, strap=INK, y=0.8):
    """Plaque dorsale collée au dos et deux sangles par-dessus les épaules (le gadget ne flotte pas)."""
    a.add(box((0, y, -0.1), (0.072, 0.07, 0.019), 0.008, plate))
    for sx in (-1, 1):
        a.add(strip([(sx * 0.055, y + 0.06, -0.106), (sx * 0.085, 0.915, -0.05), (sx * 0.09, 0.938, 0.012),
                     (sx * 0.09, 0.9, 0.082), (sx * 0.082, 0.8, 0.104)], 0.024, 0.007, strap, side=(1, 0, 0)))


def pile():
    """Pile de secours : grosse batterie sombre debout sur le dos, capot orange et deux bornes dessus, trois
    barres de charge lumineuses derrière."""
    g = Gear("pile")
    a, gl = g.p("torso"), g.p("torso", True)
    harness(a)
    a.add(box((0, 0.795, -0.143), (0.068, 0.11, 0.036), 0.012, DGRAY, nc=2))
    a.add(box((0, 0.9, -0.143), (0.07, 0.016, 0.038), 0.006, ORANGE))
    a.add(box((0, 0.69, -0.143), (0.07, 0.01, 0.038), 0.005, MGRAY))
    a.add(cyl((-0.032, 0.928, -0.143), (0, 1, 0), 0.013, 0.024, MAG_RED))
    a.add(cyl((0.032, 0.928, -0.143), (0, 1, 0), 0.013, 0.024, INK))
    for sx in (-1, 1):
        a.add(box((sx * 0.07, 0.79, -0.143), (0.006, 0.06, 0.02), 0.003, MGRAY))
    for y in (0.735, 0.785, 0.835):
        gl.add(box((0, y, -0.18), (0.046, 0.016, 0.003), 0.003, GLOW))
    gl.add(box((0, 0.905, -0.182), (0.03, 0.005, 0.003), 0.002, GLOW))
    return g


def aimant():
    """Aimant à ferraille : gros fer à cheval rouge dressé sur le dos, pôles d'acier lumineux en haut."""
    g = Gear("aimant")
    a, gl = g.p("torso"), g.p("torso", True)
    harness(a)
    c = (0, 0.79, -0.15)
    a.add(disc(c, (0, 0, 1), 0.034, 0.088, 0.052, MAG_RED, seg=10, arc=(180, 360)))
    for sx in (-1, 1):
        a.add(box((sx * 0.061, 0.845, -0.15), (0.027, 0.055, 0.026), 0.006, MAG_RED))
        a.add(box((sx * 0.061, 0.905, -0.15), (0.0275, 0.006, 0.0265), 0.003, WHITE))
    a.add(box((0, 0.718, -0.121), (0.03, 0.02, 0.02), 0.006, DGRAY))
    for sx in (-1, 1):
        gl.add(box((sx * 0.061, 0.933, -0.15), (0.027, 0.022, 0.026), 0.006, GLOW))
    return g


def reservoir():
    """Réservoir à plasma (N7) : deux bouteilles bleu acier sanglées sur le dos, robinets orange reliés par un
    tube, hublots de plasma lumineux."""
    g = Gear("reservoir")
    a, gl = g.p("torso"), g.p("torso", True)
    harness(a)
    for sx in (-1, 1):
        x = sx * 0.05
        a.add(loft([S((x, 0.655, -0.145), 0.02, 0.02, 0.008), S((x, 0.675, -0.145), 0.042, 0.042, 0.018),
                    S((x, 0.895, -0.145), 0.042, 0.042, 0.018), S((x, 0.918, -0.145), 0.022, 0.022, 0.009)], STEELB, nc=2,
                   ref=(1, 0, 0)))
        a.add(cyl((x, 0.932, -0.145), (0, 1, 0), 0.014, 0.022, ORANGE))
        gl.add(box((x, 0.785, -0.188), (0.012, 0.075, 0.003), 0.003, GLOW))
    a.add(rod([(-0.05, 0.94, -0.145), (-0.03, 0.968, -0.145), (0.03, 0.968, -0.145), (0.05, 0.94, -0.145)], 0.008, MGRAY))
    for y in (0.715, 0.855):
        a.add(box((0, y, -0.145), (0.098, 0.011, 0.047), 0.004, INK))
    return g


def ailes():
    """Petites ailes (Cité Néon) : deux ailes mécaniques en éventail sur le dos, lames nacre à bout rose ou bleu,
    longeron néon lumineux sur le bord d'attaque."""
    g = Gear("ailes")
    a, gl = g.p("torso"), g.p("torso", True)
    harness(a, plate=NIGHT)
    a.add(box((0, 0.83, -0.13), (0.05, 0.032, 0.024), 0.01, NIGHT))
    N = V3(0, 0.12, 1).normalized()
    for sx in (-1, 1):
        root = V3(sx * 0.045, 0.84, -0.14)
        a.add(cyl(root, (1, 0, 0), 0.024, 0.03, NIGHT))
        for i, (ang, L, w) in enumerate(((52, 0.29, 0.034), (28, 0.26, 0.032), (6, 0.21, 0.03), (-16, 0.15, 0.026))):
            ar = math.radians(ang)
            d = V3(sx * math.cos(ar), math.sin(ar), -0.3).normalized()
            wd = N.cross(d).normalized()
            tip_col = PINK if i % 2 == 0 else BLUE
            secs = [S(root + d * 0.01, w * 0.6, 0.006, 0.003), S(root + d * L * 0.55, w, 0.006, 0.003),
                    S(root + d * L * 0.8, w * 0.85, 0.006, 0.003, col=tip_col), S(root + d * L, w * 0.12, 0.004, 0.002)]
            bl = loft(secs, PEARL, nc=1, ref=wd)
            a.add(bl)
            if i == 0:
                up = wd * (w * 0.75) * (1 if wd.y > 0 else -1)
                gl.add(loft([S(root + d * 0.03 + up, 0.0045, 0.0045, 0.002), S(root + d * L * 0.9 + up * 0.5, 0.0035, 0.0035, 0.0015)],
                            GLOW, nc=1, ref=N))
    return g


# ------------------------------------------------------------------ épaule gauche : modules sur selle
def saddle(g, col=DGRAY, strap=INK):
    """Selle posée sur le haut de l'épaule gauche, tenue par une sangle autour du haut du bras : part à part
    « arm_l__<id>_selle » (les icônes la cachent ; en jeu elle tient le module)."""
    a = g.p("arm_l", sub="selle")
    sd = box((0.168, 0.938, -0.004), (0.046, 0.009, 0.044), 0.006, col, nc=1)
    rot(sd, (0.168, 0.938, -0.004), (0, 0, 1), -16)
    a.add(sd)
    a.add(ring((0.168, 0.832, -0.006), 0.05, 0.052, 0.018, 0.008, strap, seg=14))
    a.add(strip([(0.208, 0.928, -0.004), (0.222, 0.88, -0.005), (0.218, 0.835, -0.006)], 0.016, 0.006, strap, side=(0, 0, 1)))


def module_canon():
    """Module double canon : tourelle compacte blanche à bande orange sur l'épaule gauche, deux canons sombres
    pointés vers l'avant ; bouches lumineuses."""
    g = Gear("module_canon")
    a, gl = g.p("arm_l"), g.p("arm_l", True)
    saddle(g)
    a.add(cyl((0.175, 0.954, -0.004), (0, 1, 0), 0.026, 0.014, DGRAY))
    a.add(box((0.178, 0.988, -0.006), (0.036, 0.028, 0.056), 0.01, WHITE, nc=2))
    a.add(box((0.178, 0.988, -0.036), (0.0375, 0.0295, 0.01), 0.004, ORANGE))
    for dx in (-0.017, 0.017):
        a.add(cyl((0.178 + dx, 0.99, 0.09), (0, 0, 1), 0.012, 0.08, DGRAY))
        a.add(cyl((0.178 + dx, 0.99, 0.124), (0, 0, 1), 0.015, 0.014, MGRAY))
        gl.add(disc((0.178 + dx, 0.99, 0.132), (0, 0, 1), 0.0, 0.009, 0.003, GLOW, seg=10))
    gl.add(box((0.2155, 0.995, 0.0), (0.002, 0.008, 0.032), 0.001, GLOW))
    return g


def cellule():
    """Cellule de visée : lunette de tir sombre sur l'épaule gauche (tube, objectif évasé, tourelles orange),
    réticule holographique lumineux (cercle, croix, point) projeté devant."""
    g = Gear("cellule")
    a, gl = g.p("arm_l"), g.p("arm_l", True)
    saddle(g)
    x, y = 0.178, 0.99
    for z in (-0.03, 0.03):
        a.add(box((x, 0.958, z), (0.016, 0.018, 0.008), 0.004, MGRAY))
    a.add(loft([S((x, y, -0.085), 0.024, 0.024, 0.01), S((x, y, -0.07), 0.026, 0.026, 0.011), S((x, y, 0.05), 0.026, 0.026, 0.011),
                S((x, y, 0.075), 0.036, 0.036, 0.015), S((x, y, 0.11), 0.036, 0.036, 0.015)], DGRAY, nc=1, ref=(1, 0, 0)))
    a.add(box((x, y + 0.03, 0.0), (0.014, 0.008, 0.014), 0.004, ORANGE))
    a.add(box((x + 0.03, y, 0.0), (0.008, 0.014, 0.014), 0.004, ORANGE))
    gl.add(disc((x, y, 0.112), (0, 0, 1), 0.0, 0.03, 0.004, GLOW, seg=12))
    rz = 0.19
    gl.add(torus((x, y, rz), (0, 0, 1), 0.044, 0.0045, GLOW, seg=20, rs=4))
    gl.add(box((x, y, rz), (0.0032, 0.032, 0.0032), 0.0015, GLOW))
    gl.add(box((x, y, rz), (0.032, 0.0032, 0.0032), 0.0015, GLOW))
    return g


def pince():
    """Pince de fret (N7) : petit bras articulé bleu acier qui se dresse de l'épaule gauche, articulations
    orange, pince à trois doigts tournée vers l'avant ; anneau lumineux au poignet."""
    g = Gear("pince")
    a, gl = g.p("arm_l"), g.p("arm_l", True)
    saddle(g, col=STEELB_D)
    base, elbow, wrist = V3(0.18, 0.955, -0.03), V3(0.205, 1.065, -0.07), V3(0.205, 1.085, 0.04)
    a.add(cyl(base, (0, 1, 0), 0.026, 0.016, ORANGE))
    a.add(bar(base, elbow, 0.016, 0.014, STEELB))
    a.add(bar(elbow, wrist, 0.014, 0.013, STEELB))
    a.add(cyl(elbow, (1, 0, 0), 0.022, 0.036, ORANGE))
    a.add(cyl(wrist + V3(0, 0, 0.008), (0, 0, 1), 0.022, 0.016, ORANGE))
    w = wrist + V3(0, 0, 0.018)
    for ang in (90, 210, 330):
        d = V3(math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0.0)
        k = w + d * 0.028 + V3(0, 0, 0.03)
        tip = w + d * 0.012 + V3(0, 0, 0.066)
        a.add(bar(w + d * 0.01, k, 0.007, 0.006, CLAW, ref=V3(-d.y, d.x, 0)))
        a.add(loft([S(k, 0.007, 0.006, 0.002), S(tip, 0.003, 0.003, 0.001)], CLAW, nc=1, ref=V3(-d.y, d.x, 0)))
    gl.add(torus(wrist, (0, 0, 1), 0.022, 0.005, GLOW, seg=14, rs=4))
    return g


def antenne():
    """Antenne pirate (Cité Néon) : mât bleu nuit sur l'épaule gauche, parabole nacrée à bord rose tournée vers
    le ciel et l'avant, source bleue à boule lumineuse ; fouet d'antenne à pointe lumineuse."""
    g = Gear("antenne")
    a, gl = g.p("arm_l", False), g.p("arm_l", True)
    saddle(g, col=NIGHT)
    top = V3(0.215, 1.07, -0.04)
    a.add(rod([(0.178, 0.945, -0.02), (0.198, 1.01, -0.03), top], 0.008, NIGHT))
    n = V3(0.15, 0.85, 0.6).normalized()
    c = top + n * 0.012
    dish = shell([{"c": (0, 0.0, 0), "a": 0.016, "b": 0.016, "a0": 0, "a1": 360},
                  {"c": (0, 0.02, 0), "a": 0.058, "b": 0.058, "a0": 0, "a1": 360},
                  {"c": (0, 0.034, 0), "a": 0.082, "b": 0.082, "a0": 0, "a1": 360}], 0.007, PEARL, seg=14)
    rim = torus((0, 0.034, 0), (0, 1, 0), 0.082, 0.008, PINK, seg=14, rs=4)
    feed = rod([(0, 0.0, 0), (0, 0.08, 0)], 0.005, BLUE)
    ball = ell((0, 0.09, 0), 0.013, 0.013, 0.013, GLOW, n=4, nc=1)
    # repère : Y local -> n
    from mathutils import Matrix
    up = Vector((0, 1, 0))
    R = up.rotation_difference(n).to_matrix()
    for geo in (dish, rim, feed, ball):
        geo.v = [c + R @ v for v in geo.v]
    a.add(dish)
    a.add(rim)
    a.add(feed)
    gl.add(ball)
    a.add(rod([(0.2, 0.95, -0.06), (0.205, 1.17, -0.1)], 0.0035, NIGHT))
    gl.add(ell((0.205, 1.178, -0.101), 0.009, 0.009, 0.009, GLOW, n=4, nc=1))
    return g


# ------------------------------------------------------------------ armes (pivot du poing droit)
GP = Vector(PIV["gun"])


def L(x, y, z):
    return GP + V3(x, y, z)


def blaster_garde():
    """Blaster de garde : pistolet trapu blanc sur carcasse sombre, bande orange, frein de bouche ; filets
    lumineux sur les flancs et bouche lumineuse."""
    g = Gear("blaster_garde")
    a, gl = g.p("gun"), g.p("gun", True)
    a.add(box(L(0, -0.004, 0.014), (0.017, 0.027, 0.022), 0.007, DGRAY))
    a.add(box(L(0, -0.07, 0.066), (0.03, 0.092, 0.032), 0.011, WHITE, nc=2))
    a.add(box(L(0, -0.055, 0.028), (0.025, 0.07, 0.014), 0.006, DGRAY))
    a.add(box(L(0, -0.11, 0.066), (0.0315, 0.02, 0.0335), 0.008, ORANGE))
    a.add(box(L(0, -0.04, 0.102), (0.011, 0.045, 0.007), 0.003, INK))
    a.add(cyl(L(0, -0.185, 0.064), (0, 1, 0), 0.016, 0.05, DGRAY))
    a.add(box(L(0, -0.225, 0.064), (0.026, 0.02, 0.022), 0.007, MGRAY))
    a.add(box(L(0, -0.225, 0.064), (0.0265, 0.006, 0.012), 0.002, INK))
    for sx in (-1, 1):
        gl.add(box(L(sx * 0.0312, -0.06, 0.07), (0.002, 0.045, 0.008), 0.001, GLOW))
    gl.add(disc(L(0, -0.246, 0.064), (0, -1, 0), 0.0, 0.011, 0.004, GLOW, seg=12))
    BOUT["blaster_garde"] = (0, -0.25, 0.064)
    return g


def fusil_impulsion():
    """Fusil à impulsion : long fusil blanc à crosse sombre le long de l'avant-bras, canon gainé de trois bobines
    lumineuses, rail orange ; bouche lumineuse."""
    g = Gear("fusil_impulsion")
    a, gl = g.p("gun"), g.p("gun", True)
    a.add(box(L(0, -0.004, 0.014), (0.016, 0.027, 0.021), 0.007, DGRAY))
    a.add(box(L(0, 0.065, 0.062), (0.015, 0.06, 0.02), 0.007, DGRAY))  # crosse
    a.add(box(L(0, -0.085, 0.062), (0.027, 0.11, 0.03), 0.01, WHITE, nc=2))
    a.add(box(L(0, -0.07, 0.03), (0.022, 0.07, 0.012), 0.005, LGRAY))
    a.add(box(L(0, -0.085, 0.096), (0.009, 0.08, 0.006), 0.003, ORANGE))
    a.add(cyl(L(0, -0.26, 0.062), (0, 1, 0), 0.017, 0.15, DGRAY))
    a.add(cyl(L(0, -0.336, 0.062), (0, 1, 0), 0.021, 0.016, MGRAY))
    for y in (-0.225, -0.262, -0.299):
        gl.add(disc(L(0, y, 0.062), (0, 1, 0), 0.016, 0.026, 0.01, GLOW, seg=12))
    gl.add(disc(L(0, -0.345, 0.062), (0, -1, 0), 0.0, 0.012, 0.004, GLOW, seg=12))
    BOUT["fusil_impulsion"] = (0, -0.35, 0.062)
    return g


def riveteuse():
    """Riveteuse (N7) : outil de quai trapu bleu acier, chargeur à tambour orange, bande de quai à rayures,
    buse épaisse ; rivet lumineux au bout et voyant de charge."""
    g = Gear("riveteuse")
    a, gl = g.p("gun"), g.p("gun", True)
    a.add(box(L(0, -0.004, 0.014), (0.018, 0.027, 0.022), 0.007, STEELB_D))
    a.add(box(L(0, -0.075, 0.07), (0.04, 0.09, 0.044), 0.014, STEELB, nc=2))
    a.add(box(L(0, -0.14, 0.07), (0.0415, 0.022, 0.0455), 0.008, ORANGE))
    for k in (-1, 1):
        st = box(L(0, -0.14 + k * 0.011, 0.07), (0.0425, 0.004, 0.0465), 0.002, INK)
        rot(st, L(0, -0.14 + k * 0.011, 0.07), (1, 0, 0), 30)
        a.add(st)
    a.add(cyl(L(0, -0.06, 0.13), (1, 0, 0), 0.04, 0.05, ORANGE))
    a.add(cyl(L(0, -0.06, 0.13), (1, 0, 0), 0.018, 0.054, DGRAY))
    a.add(cyl(L(0, -0.2, 0.07), (0, 1, 0), 0.028, 0.08, MGRAY, r2=0.02))
    a.add(cyl(L(0, -0.243, 0.07), (0, 1, 0), 0.026, 0.012, DGRAY))
    gl.add(loft([S(L(0, -0.249, 0.07), 0.012, 0.012, 0.005), S(L(0, -0.262, 0.07), 0.016, 0.016, 0.007)], GLOW, nc=1))
    gl.add(box(L(0, -0.02, 0.1145), (0.016, 0.016, 0.003), 0.003, GLOW))
    BOUT["riveteuse"] = (0, -0.265, 0.07)
    return g


def pistolet_neon():
    """Pistolet à rayons (Cité Néon) : pistolet rétro rose à corps en œuf facetté, ailerons bleus, canon bleu nuit
    à bagues, pavillon bleu évasé ; bulle lumineuse sur le dessus et bouche lumineuse."""
    g = Gear("pistolet_neon")
    a, gl = g.p("gun"), g.p("gun", True)
    a.add(box(L(0, -0.004, 0.014), (0.016, 0.027, 0.021), 0.007, NIGHT))
    a.add(ell(L(0, -0.065, 0.068), 0.032, 0.072, 0.04, PINK, n=6, nc=1))
    for ang in (0, 120, 240):  # ailerons en flèche à l'arrière, autour de l'axe du canon
        fin = loft([S(L(0, -0.01, 0.068 + 0.026), 0.026, 0.0035, 0.0015), S(L(0, 0.03, 0.068 + 0.064), 0.008, 0.003, 0.001)],
                   BLUE, nc=1, ref=(0, 1, 0))
        rot(fin, L(0, 0.0, 0.068), (0, 1, 0), ang)
        a.add(fin)
    a.add(cyl(L(0, -0.165, 0.068), (0, 1, 0), 0.014, 0.08, NIGHT))
    for y in (-0.15, -0.18):
        a.add(cyl(L(0, y, 0.068), (0, 1, 0), 0.018, 0.008, PINK_L))
    a.add(loft([S(L(0, -0.2, 0.068), 0.016, 0.016, 0.007), S(L(0, -0.24, 0.068), 0.038, 0.038, 0.016),
                S(L(0, -0.25, 0.068), 0.039, 0.039, 0.016)], BLUE, nc=1))
    gl.add(ell(L(0, -0.06, 0.108), 0.02, 0.026, 0.018, GLOW, n=4, nc=1))
    gl.add(disc(L(0, -0.251, 0.068), (0, -1, 0), 0.0, 0.026, 0.003, GLOW, seg=12))
    BOUT["pistolet_neon"] = (0, -0.26, 0.068)
    return g


# ------------------------------------------------------------------ jambes (pivot du genou)
def boot_geo(sx, upper, sole, toe, cuff, top=0.27, shaft=1.0):
    """Botte qui enveloppe la basket de Jo : semelle épaisse, pied, tige jusqu'à `top`, revers `cuff`."""
    x = sx * 0.077
    out = Geo()
    sz = [(-0.078, 0.036, 0.018), (-0.064, 0.052, 0.022), (0.0, 0.056, 0.022), (0.078, 0.058, 0.022), (0.132, 0.05, 0.02),
          (0.164, 0.03, 0.014)]
    out.extend(loft([S((x, 0.022, z), a, b, min(a, b) * 0.7) for z, a, b in sz], sole, nc=1, ref=(1, 0, 0)))
    uz = [(-0.072, 0.05, 0.05, 0.088), (-0.058, 0.054, 0.058, 0.092), (0.0, 0.056, 0.06, 0.09), (0.06, 0.056, 0.046, 0.074),
          (0.118, 0.05, 0.032, 0.062), (0.152, 0.034, 0.018, 0.052)]
    ss = []
    for i, (z, a, b, yc) in enumerate(uz):
        s = S((x, yc, z), a, b, min(a, b) * 0.5)
        if i >= 3:
            s["col"] = toe
        ss.append(s)
    out.extend(loft(ss, upper, nc=1))
    ys = [(0.1, 0.053, 0.062, -0.012), (0.19, 0.049 * shaft, 0.054 * shaft, -0.008), (top, 0.047 * shaft, 0.051 * shaft, -0.006)]
    out.extend(loft([S((x, y, z), a, b, min(a, b) * 0.5) for (y, a, b, z) in ys], upper, nc=1))
    out.extend(loft([S((x, top - 0.016, -0.006), 0.053 * shaft, 0.057 * shaft, 0.026), S((x, top + 0.012, -0.006), 0.053 * shaft, 0.057 * shaft, 0.026)],
                    cuff, nc=1))
    return out


def legs(g, build):
    """build(sx) -> (géométrie, géométrie lumineuse) pour la jambe droite (sx = -1) ; la gauche en miroir."""
    geo, glo = build(-1.0)
    for side, mir in (("r", False), ("l", True)):
        a = g.p("shin_" + side)
        a.add(mirror(geo) if mir else geo)
        if glo is not None and glo.f:
            gl = g.p("shin_" + side, True)
            gl.add(mirror(glo) if mir else glo)


def bottes():
    """Bottes magnétiques (garde) : bottes montantes bleu nuit à semelle épaisse, coque de pointe blanche, revers
    gris, plaques magnétiques orange sur les flancs ; filet lumineux au milieu des plaques et sur le revers."""
    g = Gear("bottes")

    def build(sx):
        x = sx * 0.077
        geo = boot_geo(sx, NAVY, INK, WHITE, LGRAY, top=0.27)
        glo = Geo()
        for s2 in (-1, 1):
            geo.extend(box((x + s2 * 0.057, 0.078, 0.03), (0.006, 0.026, 0.044), 0.004, ORANGE))
            glo.extend(box((x + s2 * 0.0635, 0.078, 0.03), (0.002, 0.006, 0.034), 0.001, GLOW))
        glo.extend(ring((x, 0.27, -0.006), 0.054, 0.058, 0.006, 0.006, GLOW, seg=14))
        return geo, glo
    legs(g, build)
    return g


def patins():
    """Patins néon (Cité Néon) : bottines roses à revers bleu et languette nacre, platine sombre, quatre roues
    lumineuses (deux de chaque côté du pied, sur le sol), butée bleue devant."""
    g = Gear("patins")

    def build(sx):
        x = sx * 0.077
        geo = boot_geo(sx, PINK, NIGHT, PINK_L, BLUE, top=0.22)
        geo.extend(box((x, 0.115, 0.075), (0.026, 0.04, 0.008), 0.004, PEARL, up=(0, 0.6, 0.8)))
        glo = Geo()
        for z in (-0.04, 0.11):
            geo.extend(bar((x - 0.066, 0.026, z), (x + 0.066, 0.026, z), 0.006, 0.006, DGRAY, ref=(0, 1, 0)))
            for s2 in (-1, 1):
                geo.extend(disc((x + s2 * 0.064, 0.026, z), (1, 0, 0), 0.0, 0.012, 0.02, DGRAY, seg=10))
                glo.extend(disc((x + s2 * 0.064, 0.026, z), (1, 0, 0), 0.012, 0.026, 0.016, GLOW, seg=12))
        geo.extend(box((x, 0.026, 0.172), (0.022, 0.02, 0.014), 0.008, BLUE))
        return geo, glo
    legs(g, build)
    return g


def jambieres():
    """Jambières de garde : coque de tibia blanche en trois lames qui se chevauchent, genouillère sombre en pointe
    à arête orange, sangles noires derrière ; filet lumineux vertical sur le devant."""
    g = Gear("jambieres")

    def build(sx):
        x = sx * 0.075
        geo = Geo()
        for (y0, y1, k, col) in ((0.172, 0.232, 0.97, LGRAY), (0.222, 0.282, 1.0, WHITE), (0.272, 0.33, 1.04, WHITE)):
            geo.extend(shell([{"c": (x, y0, -0.004), "a": 0.046 * k, "b": 0.05 * k, "a0": -40, "a1": 220},
                              {"c": (x, y1, -0.002), "a": 0.053 * k, "b": 0.057 * k, "a0": -40, "a1": 220}], 0.01, col,
                             inner=MGRAY, seg=12))
        for y in (0.205, 0.3):
            geo.extend(ring((x, y, -0.004), 0.042, 0.046, 0.012, 0.006, INK, seg=12))
        kn = box((x, 0.36, 0.05), (0.036, 0.026, 0.026), 0.008, DGRAY)
        rot(kn, (x, 0.36, 0.05), (1, 0, 0), 45)
        geo.extend(kn)
        geo.extend(bar((x, 0.392, 0.064), (x, 0.36, 0.092), 0.007, 0.005, ORANGE, ref=(1, 0, 0)))
        glo = Geo()
        glo.extend(box((x, 0.252, 0.063), (0.0035, 0.07, 0.003), 0.0015, GLOW))
        return geo, glo
    legs(g, build)
    return g


def amortisseurs():
    """Amortisseurs (N7) : sur l'extérieur de chaque jambe, gros ressort orange autour d'une tige de piston entre
    deux colliers bleu acier sanglés au tibia ; voyants lumineux sur les colliers."""
    g = Gear("amortisseurs")

    def build(sx):
        x = sx * 0.075
        xo = x + sx * 0.062
        geo = Geo()
        glo = Geo()
        for y in (0.15, 0.31):
            geo.extend(ring((x, y, -0.003), 0.046, 0.05, 0.022, 0.01, STEELB, seg=12))
            geo.extend(box((xo - sx * 0.008, y, -0.003), (0.022, 0.017, 0.02), 0.006, STEELB_D))
            glo.extend(box((xo + sx * 0.0145, y, -0.003), (0.002, 0.006, 0.012), 0.001, GLOW))
        geo.extend(rod([(xo, 0.165, -0.003), (xo, 0.295, -0.003)], 0.007, MGRAY))
        geo.extend(helix_rod((xo, 0.23, -0.003), 0.019, 0.125, 4.5, 0.0055, ORANGE, seg=8))
        return geo, glo
    legs(g, build)
    return g


BUILDS = {
    "blaster_garde": blaster_garde, "fusil_impulsion": fusil_impulsion, "module_canon": module_canon,
    "cellule": cellule, "visiere": visiere, "casque_garde": casque_garde, "plastron": plastron, "veste": veste,
    "bottes": bottes, "jambieres": jambieres, "pile": pile, "aimant": aimant,
    "riveteuse": riveteuse, "pince": pince, "casque_docker": casque_docker, "gilet_fret": gilet_fret,
    "amortisseurs": amortisseurs, "reservoir": reservoir,
    "pistolet_neon": pistolet_neon, "antenne": antenne, "oreilles_chat": oreilles_chat, "echarpe": echarpe,
    "patins": patins, "ailes": ailes,
}


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(BUILDS)
    over = []
    for nm in names:
        mdl = BUILDS[nm]()
        n = mdl.export(os.path.join(ROOT, "assets", "chars3d", "gear_%s.glb" % nm))
        if n > BUDGET:
            over.append("%s (%d)" % (nm, n))
    for k, v in BOUT.items():
        print("MUZZLE %-16s Vector3(%g, %g, %g)" % (k, v[0], v[1], v[2]))
    if over:
        print("BUDGET DÉPASSÉ : " + ", ".join(over))
        sys.exit(1)
