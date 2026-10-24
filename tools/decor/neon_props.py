"""Obstacles et accessoires de la Cité Néon (monde 2 : toit-terrasse d'une tour, la nuit, sous la pluie),
sculptés en SDF avec tools/sculpt.py et les outils des objets de fret de Nébuleuse 7 (tools/decor/props.py :
pièces à usure d'arêtes, occlusion simulée, marquages en quads).

Matières : métal peint usé (gris chauds, bleu-gris, vert-de-gris éteints), plastique (caisses, distributeurs),
néon en petites touches (parts « _glow », sans ombrage ; « _glowlit » : écrans, vitrines, lanternes, moins
forts). Le dessus des objets reste sombre et peu saturé : les tirs roses et bleus des Néons doivent ressortir.
Compagnie de livraison inventée : PAKKU EXPRESS (cube arrondi lancé). Idéogrammes inventés (aucune vraie langue).
Ventilateurs : part « _fan » (axe Y) ou « _fanz » (axe Z) centrée sur le moyeu, tournée par le shader du jeu.
Marquages : planche tools/decor/neon_props_atlas.py (assets/decor/neon/props/decals.png), parts « _decal »,
« _decallit » (lumineux) et « _graf » (graffitis au sol, fondus).
Repère commun : sol à y = 0, emprise centrée sur l'origine, face avant vers +Z (vers la caméra), X = largeur.

Usage : python3 tools/decor/neon_props.py [nom...]   (sans nom : tous) -> assets/decor/neon/props/<nom>.glb
"""
import math
import os
import sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))

import numpy as np  # noqa: E402

import neon_props_atlas as NA  # noqa: E402
import props as PP  # noqa: E402
import sculpt as S  # noqa: E402
from props import BACK, FRONT, LEFT, RIGHT, TOP, box, cyl, diff, inter, torus, union, xform  # noqa: E402
from sculpt import Shape, capsule, ellipsoid, sphere  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "decor", "neon", "props"))

_simplify = PP.simplify


def _simplify_relaxed(verts, faces, goal, sdf=None, tol=0.006):
    """Allègement de props.py (arrêté dès qu'un triangle s'écarte du champ), puis, si le budget reste loin,
    une seconde passe plus tolérante : vu de la caméra de jeu, quelques millimètres ne se voient pas."""
    v, f = _simplify(verts, faces, goal, sdf, tol)
    if len(f) > goal * 1.3 and sdf is not None:
        v, f = _simplify(v, f, goal, sdf, tol * 2.5)
    if len(f) > goal * 3:
        # plaques fines : l'escalier du maillage brut bloque le contrôle d'écart ; allègement quadrique seul
        # (il peut effacer un creux : réservé aux pièces vraiment bloquées, signalées)
        print("  allègement forcé : %d -> %d triangles" % (len(f), goal))
        v, f = S.simplify_to(v, f, goal)
    return v, f


PP.simplify = _simplify_relaxed  # Part._piece_mesh (props.py) l'appelle par son nom de module

# ------------------------------------------------------------------ palette (nuit : sombre, peu saturée)
STEEL = "#3C414C"      # cornières, rails, pieds (acier peint sombre)
STEEL_M = "#6A707C"    # poignées, colliers
BARE = "#9AA0A8"       # métal nu (écaillage)
RUBBER = "#24252A"
FOAM = "#2A2B30"       # isolant des tuyaux
COPPER = "#8A6248"
CONC = "#4C4E55"       # béton du socle
CREAM = "#BDB6A4"
NEON_V = "#8E4CFF"     # violet
NEON_G = "#B6FF3C"     # vert acide
NEON_O = "#FF8A3C"     # orange
NEON_P = "#FF3CAC"     # rose (avec parcimonie : tirs ennemis)
LED_G = "#7CFF9A"


class Decals(PP.Decals):
    """Quads de marquage sur la planche de la Cité Néon ; `kind` : « decal », « decallit » ou « graf »."""

    def __init__(self, name, kind="decal"):
        super().__init__(name)
        self.name = name + "_" + kind

    def _uv(self, key, crop=(0.0, 0.0, 1.0, 1.0)):
        x, y, w, h = NA.R[key]
        s = float(NA.SIZE)
        u0, v0 = (x + 0.5 + crop[0] * (w - 1)) / s, (y + 0.5 + crop[1] * (h - 1)) / s
        u1, v1 = (x + 0.5 + crop[2] * (w - 1)) / s, (y + 0.5 + crop[3] * (h - 1)) / s
        return u0, 1.0 - v0, u1, 1.0 - v1


def P(name, res=0.012, seed=0, tol=0.011, pivot=(0, 0, 0)):
    p = PP.Part(name, pivot=pivot, res=res)
    p.seed = seed
    p.tol = tol
    return p


def M(name, parts, *decals):
    return S.Character(name, parts + [d for d in decals if d is not None and d.V])


def fan(name, hub, R, n=5, axis="y", col="#2E3036", tris=260, pitch=24.0):
    """Hélice de ventilateur (moyeu et n pales vrillées) centrée sur `hub` ; axe Y (dessus) ou Z (face)."""
    f = P(name + ("_fanz" if axis == "z" else "_fan"), res=0.006, tol=0.006, pivot=hub)
    loc = [S.cyl((0, 0, 0), R * 0.2, 0.03, 0.01)]
    L = R * 0.78
    for k in range(n):
        a = 360.0 * k / n
        ar = math.radians(a)
        rm = R * 0.2 + L * 0.5
        loc.append(box((rm * math.cos(ar), 0, -rm * math.sin(ar)), (L * 0.5, 0.008, R * 0.17), 0.006, rot=(pitch, a, 0)))
    sh = xform(union(*loc), hub, (90, 0, 0) if axis == "z" else (0, 0, 0))
    f.piece(col, tris=tris, wear=0.3).add(sh)
    return f


# ------------------------------------------------------------------ socle (dalle de béton sous chaque obstacle)
def socle(name="socle", seed=1):
    """Dalle de béton de 1 m x 1 m (mise à l'échelle de chaque rectangle d'obstacle), chanfreinée, épaufrée."""
    a = P(name, res=0.02, seed=seed, tol=0.008)
    a.piece(CONC, tris=90, wear=1.0).add(box((0, 0.05, 0), (0.5, 0.05, 0.5), 0.025))
    return M(name, [a])


# ------------------------------------------------------------------ climatiseurs
def clim_l(name, hull, seed=0, code="K-12"):
    """Gros groupe de climatisation de toit (2,2 x 1,3 m) : caisson sur rails, deux ventilateurs sur le
    dessus (hélices qui tournent sous leur grille), lames d'aération, trappe de service, tuyaux isolés."""
    Wd, D, H = 2.2, 1.3, 0.8
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.016, seed=seed, tol=0.012)
    dc = Decals(name)
    yb, yt = 0.1, 0.76
    body = a.piece(hull, tris=520, res=0.018, wear=0.9)
    body.add(box((0, (yb + yt) * 0.5, 0), (wx - 0.04, (yt - yb) * 0.5, dz - 0.04), 0.035))
    fx = [-0.53, 0.53]
    for x in fx:
        body.sub(S.cyl((x, yt, 0.0), 0.39, 0.13, 0.012), k=0.01)
    # trappe de service (rainure) côté droit de la face avant
    body.sub(diff(box((0.78, 0.43, dz - 0.04), (0.24, 0.22, 0.012), 0.01), box((0.78, 0.43, dz - 0.04), (0.225, 0.205, 0.05), 0.01)), k=0.003)
    # fond sombre des puits de ventilateur, buses
    dk = a.piece("#17181D", tris=60, res=0.014, grime=0.0)
    for x in fx:
        dk.add(S.cyl((x, yt - 0.12, 0.0), 0.385, 0.012, 0.005))
    sh = a.piece(STEEL, tris=220, res=0.01, wear=0.6)
    for x in fx:
        sh.add(torus((x, yt + 0.004, 0.0), 0.405, 0.022))
    # cornières, rails
    for sx in (-1, 1):
        for sz in (-1, 1):
            sh.add(box((sx * (wx - 0.05), (yb + yt) * 0.5 + 0.005, sz * (dz - 0.05)), (0.05, (yt - yb) * 0.5 + 0.01, 0.05), 0.016))
    rl = a.piece(STEEL, tris=60, res=0.016, wear=0.8)
    for sz in (-1, 1):
        rl.add(box((0, 0.05, sz * (dz - 0.18)), (wx - 0.01, 0.05, 0.07), 0.012))
    # poignée de la trappe, vis
    hd = a.piece(STEEL_M, tris=40, res=0.008, wear=0.5)
    hd.add(capsule((0.62, 0.43, dz - 0.02), (0.62, 0.53, dz - 0.02), 0.014))
    # tuyaux : sortie sur le flanc droit, descente au sol, coude vers l'avant
    tp = a.piece(FOAM, tris=150, res=0.01, grime=0.5)
    for k, z in enumerate((-0.12, 0.06)):
        r = 0.04 - k * 0.008
        tp.add(capsule((wx - 0.02, 0.5, z), (wx + 0.02, 0.5, z), r))
        tp.add(capsule((wx + 0.02, 0.5, z), (wx + 0.02, r, z), r), k=0.02)
        tp.add(capsule((wx + 0.02, r, z), (wx + 0.02, r, dz - 0.04), r), k=0.02)
    cu = a.piece(COPPER, tris=40, res=0.006, wear=0.3)
    for z in (-0.12, 0.06):
        cu.add(S.cyl((wx - 0.03, 0.5, z), 0.03, 0.04, 0.008, rot=(0, 0, 90)))
    # hélices
    fans = [fan(name + "%d" % i, (x, yt - 0.06, 0.0), 0.34, 5, "y", col="#767C86", tris=160) for i, x in enumerate(fx)]
    for i, f in enumerate(fans):
        f.name = name + "_fan%d" % i  # un nom par hélice (le jeu reconnaît « _fan »)
    # grilles, lames, marquages
    for x in fx:
        dc.quad("fan", (x, yt + 0.028, 0.0), 0.82, 0.82, TOP, off=0.0)
    for x in (-0.62, -0.05):
        dc.quad("vent", (x, 0.43, dz - 0.04), 0.5, 0.42, FRONT)
        dc.quad("drip", (x + 0.1, 0.2, dz - 0.04), 0.18, 0.2, FRONT, off=0.008)
    dc.quad("vent", (-wx + 0.04, 0.43, -0.25), 0.5, 0.42, LEFT)
    dc.quad("vent", (-wx + 0.04, 0.43, 0.3), 0.5, 0.42, LEFT)
    dc.quad("volt", (0.86, 0.56, dz - 0.04), 0.1, 0.1, FRONT, off=0.008)
    dc.quad(code, (0.78, 0.33, dz - 0.04), 0.24, 0.08, FRONT, off=0.008)
    dc.quad("line", (0.0, yt, -0.5), 0.9, 0.11, TOP)
    dc.quad("scuff", (0.25, yt, 0.42), 0.5, 0.3, TOP, off=0.002)
    g = P(name + "_glow", res=0.004)
    g.piece(LED_G, tris=30).add(sphere((0.98, 0.6, dz - 0.03), 0.012))
    return M(name, [a, g] + fans, dc)


def clim_m(name, hull, seed=0, code="R-07"):
    """Climatiseur moyen (1,2 x 0,85 m) : ventilateur en façade derrière sa grille, lames sur le dessus,
    pieds en équerre, tuyaux sur le flanc."""
    Wd, D, H = 1.2, 0.85, 0.74
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.014, seed=seed, tol=0.012)
    dc = Decals(name)
    yb, yt = 0.1, H
    body = a.piece(hull, tris=380, res=0.016, wear=0.9)
    body.add(box((0, (yb + yt) * 0.5, 0), (wx - 0.02, (yt - yb) * 0.5, dz - 0.02), 0.045))
    fcx, fcy = -0.18, 0.42
    body.sub(S.cyl((fcx, fcy, dz - 0.02), 0.27, 0.11, 0.012, rot=(90, 0, 0)), k=0.01)
    dk = a.piece("#17181D", tris=40, res=0.012, grime=0.0)
    dk.add(S.cyl((fcx, fcy, dz - 0.125), 0.265, 0.012, 0.005, rot=(90, 0, 0)))
    sh = a.piece(STEEL, tris=120, res=0.008, wear=0.6)
    sh.add(torus((fcx, fcy, dz - 0.018), 0.28, 0.02, rot=(90, 0, 0)))
    ft = a.piece(STEEL, tris=60, res=0.014, wear=0.8)
    for sx in (-1, 1):
        ft.add(box((sx * (wx - 0.12), 0.05, 0), (0.05, 0.05, dz - 0.03), 0.012))
    tp = a.piece(FOAM, tris=90, res=0.01, grime=0.5)
    for k, z in enumerate((-0.15, 0.0)):
        r = 0.035 - k * 0.006
        tp.add(capsule((wx - 0.02, 0.3, z), (wx + 0.03, 0.3, z), r))
        tp.add(capsule((wx + 0.03, 0.3, z), (wx + 0.03, r, z + 0.02), r), k=0.02)
    f = fan(name, (fcx, fcy, dz - 0.075), 0.245, 4, "z", col="#767C86", tris=130)
    dc.quad("fan", (fcx, fcy, dz - 0.02), 0.56, 0.56, FRONT, off=0.012)
    dc.quad("vent", (0.36, 0.5, dz - 0.02), 0.28, 0.3, FRONT)
    dc.quad(code, (0.36, 0.25, dz - 0.02), 0.22, 0.073, FRONT)
    dc.quad("vent", (-0.2, yt, -0.1), 0.6, 0.45, TOP, spin=90)
    dc.quad("vent", (0.3, yt, -0.1), 0.25, 0.45, TOP, spin=90)
    dc.quad("sticker", (0.32, yt, 0.24), 0.14, 0.14, TOP, crop=(0, 0, 0.5, 0.5))
    dc.quad("drip", (fcx, 0.13, dz - 0.02), 0.3, 0.12, FRONT, off=0.008)
    g = P(name + "_glow", res=0.004)
    g.piece(NEON_O, tris=30).add(sphere((0.5, 0.65, dz - 0.012), 0.01))
    return M(name, [a, g, f], dc)


# ------------------------------------------------------------------ réservoirs d'eau
def reservoir_haut(name="reservoir_haut", seed=0):
    """Grand réservoir d'eau sur pieds (contre le bord nord) : cuve cerclée, toit conique et trappe,
    pieds contreventés, échelle, jauge de niveau lumineuse, sortie d'eau."""
    a = P(name, res=0.02, seed=seed, tol=0.014)
    dc = Decals(name)
    R, y0, y1 = 0.92, 0.78, 1.95
    hull = "#62748A"
    tk = a.piece(hull, tris=520, res=0.022, wear=0.7)
    tk.add(S.cyl((0, (y0 + y1) * 0.5, 0), R, (y1 - y0) * 0.5, 0.06))
    tk.add(capsule((0, y1 - 0.02, 0), (0, y1 + 0.3, 0), R - 0.03, 0.12), k=0.06)
    hp = a.piece(STEEL, tris=260, res=0.014, wear=0.8)
    for y in (y0 + 0.12, (y0 + y1) * 0.5, y1 - 0.1):
        hp.add(torus((0, y, 0), R + 0.002, 0.022))
    # trappe et évent sur le toit
    hp.add(box((0.0, y1 + 0.33, 0.0), (0.16, 0.035, 0.16), 0.02, rot=(0, 0, 0)))
    hp.add(S.cyl((-0.3, y1 + 0.2, -0.2), 0.05, 0.12, 0.01))
    # châssis : quatre pieds, cadre, contreventements
    st = a.piece(STEEL, tris=360, res=0.014, wear=0.8)
    L = 0.8
    for sx in (-1, 1):
        for sz in (-1, 1):
            st.add(box((sx * L, 0.4, sz * L), (0.05, 0.4, 0.05), 0.012))
            st.add(box((sx * L, 0.02, sz * L), (0.1, 0.02, 0.1), 0.01))
    for s in (-1, 1):
        st.add(box((s * L, y0 - 0.04, 0), (0.05, 0.04, L + 0.05), 0.01))
        st.add(box((0, y0 - 0.04, s * L), (L + 0.05, 0.04, 0.05), 0.01))
        st.add(capsule((s * L, 0.12, -L), (s * L, y0 - 0.1, L), 0.018))
        st.add(capsule((-L, 0.12, s * L), (L, y0 - 0.1, s * L), 0.018))
    # échelle sur la face avant
    lad = a.piece(STEEL_M, tris=200, res=0.01, wear=0.5)
    zl = R + 0.06
    for x in (-0.18, 0.18):
        lad.add(capsule((x, 0.04, zl + 0.02), (x, y1 + 0.12, zl - 0.02), 0.016))
    for k in range(9):
        y = 0.25 + k * 0.2
        lad.add(capsule((-0.18, y, zl + 0.02 - 0.04 * y / y1), (0.18, y, zl + 0.02 - 0.04 * y / y1), 0.011))
    # sortie d'eau et vanne
    pp = a.piece("#4A5462", tris=120, res=0.012, wear=0.6)
    pp.add(capsule((0.5, y0 + 0.05, 0.5), (0.5, 0.08, 0.5), 0.045))
    pp.add(capsule((0.5, 0.08, 0.5), (0.5, 0.08, L + 0.1), 0.045), k=0.03)
    vv = a.piece("#8A4A42", tris=60, res=0.008, wear=0.5)
    vv.add(torus((0.5, 0.35, 0.56), 0.06, 0.012, rot=(90, 0, 0)))
    # jauge de niveau (tube lumineux bleu pâle)
    jg = a.piece(STEEL_M, tris=40, res=0.008, wear=0.4)
    for y in (y0 + 0.1, y1 - 0.1):
        jg.add(box((-0.55, y, R * 0.72 + 0.04), (0.035, 0.02, 0.035), 0.008))
    g = P(name + "_glowlit", res=0.006)
    g.piece("#8CC8FF", tris=40).add(capsule((-0.55, y0 + 0.12, R * 0.72 + 0.06), (-0.55, y0 + 0.7, R * 0.72 + 0.06), 0.016))
    g2 = P(name + "_glow", res=0.004)
    g2.piece("#FF5A4A", tris=30).add(sphere((0.0, y1 + 0.38, 0.0), 0.025))
    rr = R + 0.004
    dc.cyl("gly", rr, 1.42, 0.3, 28.0, 1.2, n=6)
    dc.cyl("drip", rr, 1.0, 0.4, -30.0, 0.25, n=2)
    dc.cyl("drip", rr, 1.05, 0.4, 70.0, 0.25, n=2)
    dc.cyl("sticker", rr, 1.1, 0.16, -60.0, 0.16, n=1, crop=(0.5, 0.5, 1, 1))
    return M(name, [a, g, g2], dc)


def reservoir(name, hull, seed=0):
    """Réservoir d'eau trapu sur quatre pieds (Ø 1,3 m, 0,85 m) : cuve cerclée à dôme, trappe, sortie à
    vanne, jauge, coulures."""
    a = P(name, res=0.016, seed=seed, tol=0.012)
    dc = Decals(name)
    R, y0, y1 = 0.62, 0.2, 0.66
    tk = a.piece(hull, tris=480, res=0.016, wear=0.7)
    tk.add(S.cyl((0, (y0 + y1) * 0.5, 0), R, (y1 - y0) * 0.5, 0.05))
    tk.add(ellipsoid((0, y1 - 0.02, 0), (R - 0.03, 0.12, R - 0.03)), k=0.06)
    hp = a.piece(STEEL, tris=240, res=0.012, wear=0.8)
    for y in (y0 + 0.07, y1 - 0.06):
        hp.add(torus((0, y, 0), R + 0.002, 0.02))
    hp.add(S.cyl((0.0, y1 + 0.13, 0.0), 0.15, 0.025, 0.012))
    lg = a.piece(STEEL, tris=160, res=0.012, wear=0.8)
    for k in range(4):
        ang = math.radians(45 + k * 90)
        x, z = math.cos(ang) * R * 0.78, math.sin(ang) * R * 0.78
        lg.add(S.cyl((x, 0.11, z), 0.04, 0.11, 0.01))
        lg.add(S.cyl((x, 0.012, z), 0.075, 0.012, 0.006))
    pp = a.piece("#4A5462", tris=100, res=0.01, wear=0.6)
    pp.add(capsule((0.2, 0.26, R - 0.05), (0.2, 0.26, R + 0.04), 0.035))
    pp.add(capsule((0.2, 0.26, R + 0.04), (0.2, 0.035, R + 0.04), 0.035), k=0.02)
    vv = a.piece("#8A4A42", tris=60, res=0.006, wear=0.5)
    vv.add(torus((0.2, 0.26, R + 0.08), 0.05, 0.011, rot=(90, 0, 0)))
    rr = R + 0.004
    dc.cyl("line", rr, 0.42, 0.08, -20.0, 0.62, n=4)
    dc.cyl("drip", rr, 0.33, 0.24, 40.0, 0.2, n=2)
    dc.cyl("drip", rr, 0.33, 0.24, -110.0, 0.2, n=2)
    return M(name, [a], dc)


# ------------------------------------------------------------------ kiosque à ramen et son robot cuisinier
def kiosque(name="kiosque", seed=0):
    """Kiosque à ramen (3,7 x 1,7 m, contre le bord nord) : meuble de cuisine et grande marmite au fond,
    panneau de menus lumineux et enseigne à idéogrammes inventés, comptoir avant, auvent étroit à rideaux
    (noren), lanternes ; tenu par un petit robot cuisinier figé, louche levée, écran éteint."""
    a = P(name, res=0.016, seed=seed, tol=0.012)
    dc = Decals(name)
    dl = Decals(name, "decallit")
    wx = 1.82
    zb, zf = -0.84, 0.84
    lac = "#5A2C2C"     # laque rouge éteinte
    wood = "#4A3A30"
    # meuble du fond (cuisine) et panneau arrière
    cb = a.piece(lac, tris=160, res=0.025, wear=0.8)
    cb.add(box((0, 0.46, -0.62), (wx - 0.02, 0.46, 0.22), 0.025))
    cb.add(box((0, 1.5, zb + 0.05), (wx - 0.04, 0.6, 0.05), 0.02))
    # enseigne du haut
    sg = a.piece("#22202A", tris=60, res=0.02, wear=0.3)
    sg.add(box((0, 2.32, zb + 0.07), (1.2, 0.22, 0.06), 0.03))
    tw = a.piece(wood, tris=180, res=0.014, wear=0.0)
    tw.add(box((0, 0.93, -0.62), (wx, 0.025, 0.24), 0.01))           # plan de travail
    tw.add(box((0, 0.94, 0.58), (wx - 0.1, 0.03, 0.24), 0.012))      # dessus du comptoir
    for sx in (-1, 1):
        tw.add(box((sx * (wx - 0.06), 1.1, zf - 0.06), (0.05, 1.1, 0.05), 0.012))   # poteaux avant
        tw.add(box((sx * (wx - 0.06), 2.17, 0.0), (0.04, 0.04, zf - 0.02), 0.01))    # longerons

    # comptoir avant
    ct = a.piece(lac, tris=120, res=0.018, wear=0.8)
    ct.add(box((0, 0.46, 0.6), (wx - 0.14, 0.45, 0.2), 0.025))
    # noren : cinq pans courts de tissu indigo au fond, sous l'enseigne (rien en travers de l'avant : vu de
    # la caméra de jeu, le robot reste visible par-dessus le comptoir)
    nr = a.piece("#28304E", tris=120, res=0.01, grime=0.3)
    zn = zb + 0.13
    for k in range(5):
        x = (k - 2) * 0.66
        nr.add(box((x, 1.99, zn), (0.3, 0.12, 0.018), 0.015))
    # cuisine : grande marmite, bols empilés, cuiseur ; comptoir : bols de ramen servis, bouteilles
    kt = a.piece("#8A8E96", tris=120, res=0.01, wear=0.4)
    kt.add(S.cyl((-0.95, 1.13, -0.62), 0.22, 0.18, 0.03))
    kt.add(torus((-0.95, 1.3, -0.62), 0.22, 0.02))
    kt.add(S.cyl((1.15, 1.06, -0.66), 0.17, 0.1, 0.06))
    bw = a.piece("#C9C0B0", tris=160, res=0.008, wear=0.2)
    for k in range(4):
        bw.add(S.cyl((0.55, 0.98 + k * 0.045, -0.6), 0.09 - k * 0.002, 0.024, 0.012))
    bowls = [(-0.8, 0.62), (0.8, 0.58), (1.4, 0.64)]
    for x, z in bowls:
        bw.add(diff(S.cyl((x, 1.0, z), 0.1, 0.04, 0.03), S.cyl((x, 1.05, z), 0.08, 0.03, 0.01)))
    br = a.piece("#B07A3E", tris=60, res=0.008, grime=0.0)   # bouillon et nouilles
    for x, z in bowls:
        br.add(S.cyl((x, 1.02, z), 0.082, 0.01, 0.005))
    eg = a.piece("#D8CFA8", tris=40, res=0.006, grime=0.0)    # demi-œuf, naruto
    for x, z in bowls:
        eg.add(ellipsoid((x + 0.03, 1.035, z - 0.02), (0.03, 0.012, 0.022)))
    bt = a.piece("#6A2E2A", tris=50, res=0.008, wear=0.2)
    for x in (0.95, 1.05):
        bt.add(capsule((x, 0.99, 0.66), (x, 1.12, 0.66), 0.03, 0.018))
    ch = a.piece("#C8A878", tris=40, res=0.006, grime=0.0)    # baguettes posées
    for x, z in bowls:
        ch.add(capsule((x - 0.13, 0.975, z + 0.12), (x + 0.1, 0.975, z + 0.15), 0.006))
    # lanternes de papier (lumineuses, douces) aux poteaux avant
    ln = P(name + "_glowlit", res=0.008)
    lp = ln.piece("#FF9A5A", tris=80)
    for sx in (-1, 1):
        lp.add(ellipsoid((sx * (wx - 0.06), 1.75, zf + 0.06), (0.11, 0.15, 0.11)))
    lc = a.piece("#2A2428", tris=40, res=0.008)
    for sx in (-1, 1):
        lc.add(S.cyl((sx * (wx - 0.06), 1.92, zf + 0.06), 0.06, 0.02, 0.008))
        lc.add(S.cyl((sx * (wx - 0.06), 1.58, zf + 0.06), 0.06, 0.02, 0.008))
    # néon fin autour de l'enseigne (orange) et liseré violet sous le comptoir
    ng = P(name + "_glow", res=0.005)
    ng.piece(NEON_O, tris=160).add(diff(box((0, 2.32, zb + 0.14), (1.17, 0.19, 0.012), 0.012), box((0, 2.32, zb + 0.14), (1.13, 0.15, 0.05), 0.01)))
    ng.piece(NEON_V, tris=40).add(box((0, 0.88, 0.81), (wx - 0.2, 0.01, 0.01), 0.008))
    # robot cuisinier (figé)
    rb = robot_cuisinier(name, (0.0, 0.0, 0.1))
    # marquages : menus et enseigne lumineux, noren, idéogrammes du comptoir
    dl.quad("menu", (-0.75, 1.5, zb + 0.105), 0.56, 0.56, FRONT, off=0.002)
    dl.quad("menu", (0.75, 1.5, zb + 0.105), 0.56, 0.56, FRONT, off=0.002)
    dl.quad("gly_lit", (0, 2.32, zb + 0.135), 2.0, 0.5, FRONT, off=0.002)
    for k in range(5):
        g4 = (k * 3 + 1) % 4
        dc.quad("gly", ((k - 2) * 0.66, 1.98, zn + 0.02), 0.18, 0.18, FRONT, off=0.002, crop=(g4 / 4.0, 0.0, (g4 + 1) / 4.0, 1.0))
    dc.quad("gly", (0.35, 0.55, 0.805), 1.5, 0.37, FRONT, off=0.003)
    dc.quad("pakku", (-1.3, 0.62, 0.805), 0.3, 0.3, FRONT, off=0.002)
    dc.quad("sticker", (-0.9, 0.35, 0.805), 0.16, 0.16, FRONT, crop=(0.5, 0, 1, 0.5))
    dc.quad("scuff", (0.2, 0.2, 0.805), 0.9, 0.35, FRONT, off=0.0015)
    return M(name, [a, ln, ng] + rb, dc, dl)


def robot_cuisinier(base, at):
    """Petit robot cuisinier figé : corps rond crème, tablier, toque, écran-visage éteint (deux traits de
    veille), bras gauche levant une louche, bras droit tenant un bol ; roule sur un socle."""
    ox, oy, oz = at
    q = lambda x, y, z: (ox + x, oy + y, oz + z)
    a = P(base + "_robot", res=0.008, seed=7, tol=0.008)
    bc = "#BDB8AA"
    body = a.piece(bc, tris=200, wear=0.2)
    body.add(ellipsoid(q(0, 0.72, 0), (0.24, 0.26, 0.21)))
    body.add(S.cyl(q(0, 0.48, 0), 0.15, 0.06, 0.04), k=0.05)
    ap = a.piece("#2E3440", tris=70, res=0.008, grime=0.3)
    ap.add(inter(ellipsoid(q(0, 0.72, 0.015), (0.245, 0.265, 0.215)), box(q(0, 0.64, 0.2), (0.2, 0.2, 0.08), 0.0)))
    bs = a.piece(STEEL, tris=70, wear=0.6)
    bs.add(S.cyl(q(0, 0.2, 0), 0.17, 0.2, 0.05))
    bs.add(S.cyl(q(0, 0.04, 0), 0.2, 0.04, 0.02))
    hd = a.piece(bc, tris=150, wear=0.2)
    hd.add(box(q(0, 1.1, 0), (0.2, 0.15, 0.17), 0.12))
    sc = a.piece("#121318", tris=40, res=0.006)
    sc.add(box(q(0, 1.09, 0.155), (0.15, 0.1, 0.02), 0.06))
    hat = a.piece("#E2DED4", tris=130, res=0.01, wear=0.0)
    hat.add(S.cyl(q(0, 1.29, 0), 0.15, 0.05, 0.02))
    for (x, z) in ((-0.07, 0.04), (0.07, 0.04), (0.0, -0.07), (0.0, 0.03)):
        hat.add(sphere(q(x, 1.4, z), 0.1), k=0.05)
    ar = a.piece(bc, tris=120, wear=0.2)
    ar.add(capsule(q(-0.24, 0.8, 0.02), q(-0.36, 0.95, 0.12), 0.05))
    ar.add(capsule(q(-0.36, 0.95, 0.12), q(-0.36, 1.12, 0.15), 0.045), k=0.02)
    ar.add(capsule(q(0.24, 0.8, 0.02), q(0.33, 0.88, 0.16), 0.05))
    ar.add(capsule(q(0.33, 0.88, 0.16), q(0.26, 0.98, 0.3), 0.045), k=0.02)
    ac = a.piece("#E07A3A", tris=50, res=0.006, wear=0.3)
    for sx in (-1, 1):
        ac.add(S.cyl(q(sx * 0.2, 1.1, 0.0), 0.05, 0.03, 0.01, rot=(0, 0, 90)))   # oreilles orange
    ld = a.piece("#8A8E96", tris=60, res=0.006, wear=0.3)
    ld.add(capsule(q(-0.36, 1.12, 0.15), q(-0.36, 1.35, 0.2), 0.012))
    # cuilleron de la louche et bol : demi-sphères creuses
    ld.add(inter(diff(sphere(q(-0.36, 1.4, 0.26), 0.06), sphere(q(-0.36, 1.41, 0.26), 0.05)), box(q(-0.36, 1.37, 0.26), (0.07, 0.03, 0.07), 0.0)))
    bw = a.piece("#C9C0B0", tris=50, res=0.006, wear=0.2)
    bw.add(inter(diff(sphere(q(0.24, 1.07, 0.38), 0.09), sphere(q(0.24, 1.09, 0.38), 0.078)), box(q(0.24, 1.025, 0.38), (0.1, 0.045, 0.1), 0.0)))
    g = P(base + "_robot_glowlit", res=0.004)
    gp = g.piece("#4A6A9A", tris=30)
    for sx in (-1, 1):
        gp.add(capsule(q(sx * 0.055, 1.1, 0.178), q(sx * 0.025, 1.1, 0.178), 0.009))
    return [a, g]


# ------------------------------------------------------------------ distributeurs lumineux
def distributeur(name, shell, neon, seed=0):
    """Distributeur de boissons trapu (0,9 x 0,85 x 0,7 m) : coque arrondie, vitrine lumineuse en retrait
    sous une petite visière, colonne de boutons, fente à jetons, trappe de retrait, liseré néon en haut."""
    Wd, H, D = 0.9, 0.84, 0.7
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.012, seed=seed, tol=0.01)
    dc = Decals(name)
    dl = Decals(name, "decallit")
    sh = a.piece(shell, tris=420, res=0.014, wear=0.6)
    sh.add(box((0, H * 0.5 + 0.02, 0), (wx, H * 0.5 - 0.02, dz), 0.07))
    sh.sub(box((-0.08, 0.53, dz), (0.29, 0.21, 0.05), 0.03), k=0.01)        # vitrine
    sh.sub(box((-0.08, 0.16, dz), (0.25, 0.07, 0.07), 0.03), k=0.01)        # trappe de retrait
    sh.sub(box((0.32, 0.5, dz), (0.07, 0.2, 0.025), 0.02), k=0.008)         # colonne de boutons
    dk = a.piece("#141519", tris=40, res=0.012)
    dk.add(box((-0.08, 0.16, dz - 0.06), (0.24, 0.06, 0.012), 0.01))
    vz = a.piece(STEEL, tris=100, res=0.01, wear=0.5)
    vz.add(box((-0.08, 0.77, dz + 0.04), (0.33, 0.012, 0.06), 0.008, rot=(-14, 0, 0)))   # visière
    vz.add(box((0.32, 0.24, dz - 0.004), (0.05, 0.035, 0.012), 0.008))                   # fente à jetons
    ft = a.piece(RUBBER, tris=40, res=0.012)
    for sx in (-1, 1):
        ft.add(box((sx * (wx - 0.12), 0.012, 0), (0.07, 0.012, dz - 0.08), 0.008))
    g = P(name + "_glow", res=0.005)
    g.piece(neon, tris=80).add(box((0, H - 0.005, dz - 0.04), (wx - 0.1, 0.012, 0.012), 0.01))
    dl.quad("vend", (-0.08, 0.53, dz - 0.05), 0.56, 0.4, FRONT, off=0.024, crop=(0, 0.04, 1, 0.76))
    dl.quad("btn", (0.32, 0.5, dz - 0.025), 0.11, 0.38, FRONT, off=0.014)
    dc.quad("gly", (0.0, 0.5, -dz), 0.66, 0.17, BACK)
    dc.quad("sticker", (wx, 0.6, 0.12), 0.18, 0.18, RIGHT, crop=(0, 0, 0.5, 0.5))
    dc.quad("sticker", (-wx, 0.4, -0.1), 0.16, 0.16, LEFT, crop=(0.5, 0.5, 1, 1))
    dc.quad("line", (0.0, H, -0.12), 0.7, 0.087, TOP)
    dc.quad("scuff", (0.15, H, 0.12), 0.5, 0.3, TOP, off=0.002)
    return M(name, [a, g], dc, dl)


# ------------------------------------------------------------------ caisses de livraison PAKKU EXPRESS
def caisse(name, Wd, H, D, col, seed=0, lid=True, logo="pakku"):
    """Bac de livraison en plastique PAKKU EXPRESS : flancs nervurés, poignées ajourées, couvercle à deux
    battants ; logo sur le couvercle, nom sur la face avant, étiquette sur le flanc."""
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.012, seed=seed, tol=0.008)
    dc = Decals(name)
    yl = H - 0.035 if lid else H
    body = a.piece(col, tris=300, res=0.012, wear=0.35)
    body.add(box((0, yl * 0.5, 0), (wx - 0.012, yl * 0.5, dz - 0.012), 0.03))
    body.add(box((0, yl - 0.03, 0), (wx, 0.03, dz), 0.02), k=0.01)         # rebord
    for sx in (-1, 1):
        body.sub(box((sx * wx, yl - 0.12, 0), (0.03, 0.03, min(0.09, dz * 0.35)), 0.025), k=0.006)
    n = max(2, int(Wd / 0.2))
    for k in range(n):
        x = -wx + (k + 0.5) * Wd / n
        for sz in (-1, 1):
            body.sub(box((x, yl * 0.42, sz * (dz - 0.012)), (0.012, yl * 0.3, 0.01), 0.006), k=0.004)
    tops = [yl]
    if lid:
        ld = a.piece("#30323A", tris=120, res=0.012, wear=0.4)
        ld.add(box((0, H - 0.018, 0), (wx + 0.004, 0.018, dz + 0.004), 0.012))
        ld.sub(box((0, H, 0), (wx + 0.1, 0.006, 0.006), 0.003))
        tops = [H]
    top = tops[0]
    lw = min(Wd * 0.38, D * 0.6, 0.26)
    dc.quad(logo, (-wx * 0.38, top, 0.0), lw, lw, TOP, off=0.002)
    dc.quad("tape" if not lid else "sticker", (wx * 0.45, top, -dz * 0.3), 0.12 if lid else Wd * 0.4, 0.12 if lid else 0.04, TOP,
            crop=(0.5, 0, 1, 0.5) if lid else (0, 0, 1, 1))
    ww = min(Wd * 0.7, 0.5)
    dc.quad("word", (0, yl * 0.78, dz), ww, ww / 4, FRONT, off=0.004)
    dc.quad("tag", (0.0, yl * 0.45, -dz), min(0.2, Wd * 0.4), min(0.1, Wd * 0.2), BACK, off=0.004)
    return M(name, [a], dc)


def carton(name, Wd, H, D, seed=0):
    """Colis en carton PAKKU : ruban sombre à liseré rose, étiquette, logo."""
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.012, seed=seed, tol=0.008)
    dc = Decals(name)
    a.piece("#756450", tris=90, res=0.014, wear=0.0).add(box((0, H * 0.5, 0), (wx, H * 0.5, dz), 0.012))
    dc.quad("tape", (0, H, 0), Wd + 0.004, 0.07, TOP, off=0.002)
    dc.quad("tape", (0, H - 0.06, dz), 0.07, 0.12, FRONT, off=0.002, spin=90)
    dc.quad("tag", (-wx * 0.4, H * 0.45, dz), 0.2, 0.1, FRONT, off=0.003)
    dc.quad("pakku_k", (wx * 0.5, H, dz * 0.4), 0.14, 0.14, TOP, off=0.003)
    return M(name, [a], dc)


# ------------------------------------------------------------------ antenne parabolique
def parabole(name="parabole", seed=0):
    """Antenne parabolique sur châssis lesté (1,35 m) : rails croisés, quatre blocs de béton, mât, rotule,
    réflecteur tourné vers le ciel (et la caméra), bras et tête de réception à voyant."""
    a = P(name, res=0.012, seed=seed, tol=0.01)
    dc = Decals(name)
    st = a.piece(STEEL, tris=160, res=0.014, wear=0.8)
    st.add(box((0, 0.05, 0), (0.62, 0.035, 0.05), 0.01, rot=(0, 45, 0)))
    st.add(box((0, 0.05, 0), (0.62, 0.035, 0.05), 0.01, rot=(0, -45, 0)))
    st.add(S.cyl((0, 0.18, -0.06), 0.045, 0.14, 0.01))
    st.add(box((0, 0.31, -0.06), (0.07, 0.05, 0.06), 0.02))
    bl = a.piece(CONC, tris=200, res=0.016, wear=1.0)
    for sx in (-1, 1):
        for sz in (-1, 1):
            bl.add(box((sx * 0.48, 0.07, sz * 0.48), (0.17, 0.07, 0.17), 0.025, rot=(0, 45, 0)))
    # réflecteur : calotte mince, axe incliné vers le haut et le sud (+Z)
    Rs, rad, t = 0.9, 0.52, 0.014
    def cap(P):
        Q = P.copy()
        return np.maximum(np.abs(np.linalg.norm(Q - np.array([0.0, Rs, 0.0]), axis=1) - Rs) - t, np.sqrt(Q[:, 0] ** 2 + Q[:, 2] ** 2) - rad)
    dish_loc = Shape(cap, np.array([-rad, -0.02, -rad]), np.array([rad, 0.2, rad]))
    tilt = 42.0
    dc_c = (0.0, 0.34, -0.04)
    dish = xform(dish_loc, dc_c, (tilt, 0, 0))
    a.piece("#5C616A", tris=420, res=0.01, wear=0.4).add(dish)
    # bras et tête de réception (foyer)
    ax = np.array([0.0, math.cos(math.radians(tilt)), math.sin(math.radians(tilt))])
    foc = np.array(dc_c) + ax * 0.42
    rim = np.array(dc_c) + np.array([0.0, -math.sin(math.radians(tilt)), math.cos(math.radians(tilt))]) * 0.44 + ax * 0.13
    arm = a.piece(STEEL_M, tris=100, res=0.008, wear=0.4)
    arm.add(capsule(tuple(rim), tuple(foc), 0.014))
    arm.add(box(tuple(foc), (0.04, 0.05, 0.04), 0.015, rot=(tilt, 0, 0)))
    cb = a.piece(RUBBER, tris=60, res=0.008)
    cb.add(capsule(tuple(rim), (0.05, 0.03, -0.3), 0.01))
    cb.add(capsule((0.05, 0.03, -0.3), (0.5, 0.012, -0.55), 0.01), k=0.02)
    g = P(name + "_glow", res=0.004)
    g.piece(NEON_G, tris=30).add(sphere(tuple(foc + np.array([0.0, 0.05, 0.03])), 0.012))
    # marquage peint sur le réflecteur (côté visible)
    dcen = np.array(dc_c) + ax * 0.06
    dc.quad("pakku_k", tuple(dcen + np.array([0.0, 0.0, 0.0])), 0.32, 0.32, (tilt - 90.0, 0.0, 0.0), off=0.01)
    return M(name, [a, g], dc)


# ------------------------------------------------------------------ tas de câbles et de gaines
def ribbed_torus(c, R0, r, n, amp):
    """Gaine annelée enroulée : tore dont le rayon de section ondule le long de la gaine."""
    c = np.asarray(c, dtype=np.float64)
    def f(P):
        Q = P - c
        ang = np.arctan2(Q[:, 2], Q[:, 0])
        q = np.stack([np.linalg.norm(Q[:, [0, 2]], axis=1) - R0, Q[:, 1]], axis=1)
        return np.linalg.norm(q, axis=1) - (r + amp * np.cos(ang * n))
    m = R0 + r + amp
    return Shape(f, c - m, c + m)


def tas_cables(name="tas_cables", seed=0):
    """Tas de câbles et de gaines (1,5 x 0,9 m) : couronnes de câble noir empilées, gaine annelée orange
    éteint, touret couché, câbles qui serpentent, colliers."""
    a = P(name, res=0.012, seed=seed, tol=0.01)
    dc = Decals(name)
    cb = a.piece("#25262B", tris=380, res=0.012, grime=0.4)
    for k, (x, z, y, R0) in enumerate(((-0.42, -0.1, 0.035, 0.3), (-0.4, -0.08, 0.1, 0.27), (-0.44, -0.12, 0.16, 0.24))):
        cb.add(torus((x, y, z), R0, 0.035), k=0.015)
    cb.add(capsule((-0.2, 0.2, 0.1), (0.1, 0.1, 0.32), 0.03), k=0.02)
    cb.add(capsule((0.1, 0.1, 0.32), (0.55, 0.03, 0.36), 0.03), k=0.02)
    gn = a.piece("#9A5A36", tris=600, res=0.01, wear=0.2)
    gn.add(ribbed_torus((0.32, 0.045, -0.12), 0.3, 0.04, 36, 0.008))
    gn.add(ribbed_torus((0.34, 0.12, -0.14), 0.26, 0.036, 30, 0.008))
    g2 = a.piece("#5A606C", tris=260, res=0.01, wear=0.2)
    g2.add(ribbed_torus((0.33, 0.19, -0.1), 0.2, 0.032, 24, 0.007))
    # touret couché, câble vert-de-gris enroulé
    tr = a.piece("#4A4038", tris=160, res=0.012, wear=0.6)
    for sx in (-1, 1):
        tr.add(S.cyl((-0.25 + sx * 0.13, 0.22, 0.32), 0.21, 0.015, 0.008, rot=(0, 0, 90)))
    tr.add(S.cyl((-0.25, 0.22, 0.32), 0.07, 0.15, 0.01, rot=(0, 0, 90)))
    cg = a.piece("#3E5650", tris=140, res=0.01, grime=0.4)
    cg.add(S.cyl((-0.25, 0.22, 0.32), 0.16, 0.12, 0.04, rot=(0, 0, 90)))
    cl = a.piece(STEEL_M, tris=60, res=0.006, wear=0.4)
    for x, z in ((-0.42, 0.2), (-0.12, -0.38)):
        cl.add(torus((x, 0.17, z), 0.045, 0.01, rot=(0, 0, 90)))
    dc.quad("tag", (-0.25 + 0.145, 0.22, 0.32), 0.14, 0.07, RIGHT, off=0.002)
    return M(name, [a], dc)


# ------------------------------------------------------------------ boîtiers électriques
def boitier(name, hull, Wd=0.9, H=0.82, D=0.5, seed=0, leds=(LED_G, LED_G, NEON_O)):
    """Armoire électrique de toit sur socle : deux portes à joints, poignées, petit toit pare-pluie,
    grilles, avertissement électrique, rangée de voyants, écran, gaines qui plongent dans le sol."""
    wx, dz = Wd * 0.5, D * 0.5
    a = P(name, res=0.012, seed=seed, tol=0.01)
    dc = Decals(name)
    yb = 0.07
    body = a.piece(hull, tris=320, res=0.014, wear=0.9)
    body.add(box((0, (yb + H - 0.05) * 0.5, 0), (wx - 0.02, (H - 0.05 - yb) * 0.5, dz - 0.03), 0.02))
    # joints des portes
    body.sub(box((0, 0.42, dz - 0.03), (0.006, 0.3, 0.012), 0.003))
    body.sub(diff(box((0, 0.42, dz - 0.03), (wx - 0.05, 0.31, 0.01), 0.006), box((0, 0.42, dz - 0.03), (wx - 0.062, 0.298, 0.05), 0.006)), k=0.002)
    rf = a.piece(STEEL, tris=80, res=0.012, wear=0.8)
    rf.add(box((0, H - 0.03, 0.01), (wx, 0.03, dz - 0.0), 0.012))
    rf.add(box((0, yb * 0.5, 0), (wx - 0.04, yb * 0.5, dz - 0.05), 0.01))
    hd = a.piece(STEEL_M, tris=60, res=0.006, wear=0.4)
    for sx in (-1, 1):
        hd.add(capsule((sx * 0.06, 0.38, dz - 0.012), (sx * 0.06, 0.48, dz - 0.012), 0.012))
    gn = a.piece("#3A3E46", tris=80, res=0.01, wear=0.4)
    gn.add(capsule((-wx * 0.5, 0.14, -dz + 0.05), (-wx * 0.5, 0.0, -dz + 0.05), 0.035))
    gn.add(capsule((wx * 0.4, 0.14, -dz + 0.05), (wx * 0.4, 0.0, -dz + 0.05), 0.03))
    g = P(name + "_glow", res=0.004)
    for k, c in enumerate(leds):
        g.piece(c, tris=24).add(sphere((wx - 0.1 - k * 0.05, H - 0.14, dz - 0.018), 0.011))
    dl = Decals(name, "decallit")
    dl.quad("btn", (-wx + 0.14, H - 0.15, dz - 0.016), 0.04, 0.08, FRONT, off=0.002, crop=(0, 0.3, 1, 0.5), spin=90)
    dc.quad("volt", (-wx * 0.5, 0.56, dz - 0.03), 0.13, 0.13, FRONT, off=0.006)
    dc.quad("vent", (wx * 0.5, 0.22, dz - 0.03), 0.22, 0.14, FRONT, off=0.006)
    dc.quad("vent", (-wx * 0.5, 0.22, dz - 0.03), 0.22, 0.14, FRONT, off=0.006)
    dc.quad("haz", (0, 0.1, dz - 0.03), Wd - 0.12, 0.04, FRONT, off=0.006, crop=(0, 0, 0.9, 1))
    dc.quad("sticker", (wx * 0.45, 0.6, dz - 0.03), 0.12, 0.12, FRONT, off=0.006, crop=(0.5, 0, 1, 0.5))
    dc.quad("line", (0, H, 0.0), Wd * 0.7, Wd * 0.7 / 8, TOP, off=0.002)
    return M(name, [a, g], dc, dl)


# ------------------------------------------------------------------ accessoires non bloquants
class FlatPart:
    """Part plate construite directement (pas de champ : une dalle de 4 mm échappe aux marching cubes)."""

    def __init__(self, name, V, F):
        self.name, self.parent, self.pivot = name, None, np.zeros(3)
        self.V, self.F = V, F

    def mesh(self):
        tm = S.trimesh.Trimesh(self.V, self.F, process=False)
        tm.visual = S.trimesh.visual.ColorVisuals(tm, vertex_colors=np.tile([16, 18, 24, 255], (len(self.V), 1)).astype(np.uint8))
        tm.vertex_normals = np.tile([0.0, 1.0, 0.0], (len(self.V), 1))
        return tm


def flaque(name, pts, k=0.12, n=56):
    """Flaque (sol mouillé) : contour d'une union douce de disques (x, z, r), relevé en étoile depuis le
    premier disque (le plus grand creux de rive est comblé), éventail plat à 3 mm du sol, rendu par le shader
    de flaque du jeu (miroir sombre, ronds de pluie)."""
    def sdf(x, z):
        d = None
        for (px, pz, r) in pts:
            dd = np.sqrt((x - px) ** 2 + (z - pz) ** 2) - r
            d = dd if d is None else S.smin(d, dd, k)
        return d
    cx, cz = pts[0][0], pts[0][1]
    rs = np.linspace(0.0, 2.5, 600)
    ring = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, z = cx + np.cos(a) * rs, cz + np.sin(a) * rs
        inside = np.nonzero(sdf(x, z) < 0)[0]
        r = rs[inside.max()] if len(inside) else 0.05
        ring.append((cx + math.cos(a) * r, 0.003, cz + math.sin(a) * r))
    V = np.array([(cx, 0.003, cz)] + ring)
    F = np.array([(0, 1 + (i + 1) % n, 1 + i) for i in range(n)])
    return S.Character(name, [FlatPart(name + "_puddle", V, F)])


def egout(name="egout", seed=0):
    """Plaque d'égout en fonte (Ø 0,8 m) : cadre à arête usée, plaque plate dont le motif (couronne
    d'idéogrammes, quadrillage de plots, anneaux, trous de levage) est un marquage."""
    a = P(name, res=0.01, seed=seed, tol=0.006)
    dc = Decals(name)
    pl = a.piece("#33353C", tris=60, res=0.012, wear=0.0)
    pl.add(S.cyl((0, 0.008, 0), 0.405, 0.008, 0.003))
    fr = a.piece("#3A3C44", tris=140, res=0.008, wear=0.9)
    fr.add(diff(S.cyl((0, 0.01, 0), 0.47, 0.01, 0.006), S.cyl((0, 0.01, 0), 0.405, 0.05, 0.002)))
    dc.quad("egout", (0, 0.0165, 0.0), 0.8, 0.8, TOP, off=0.0)
    return M(name, [a], dc)


def pot(name, seed=0, H=0.42, tall=True):
    """Bac à plante en plastique (0,45 m) : bac à rebord, terre, plante en plastique à feuilles longues."""
    a = P(name, res=0.01, seed=seed, tol=0.008)
    w = 0.22
    pt = a.piece("#3C4250", tris=120, wear=0.3)
    pt.add(box((0, H * 0.5, 0), (w, H * 0.5, w), 0.04))
    pt.add(box((0, H - 0.025, 0), (w + 0.02, 0.025, w + 0.02), 0.015), k=0.01)
    pt.sub(box((0, H, 0), (w - 0.02, 0.03, w - 0.02), 0.02))
    a.piece("#2A2420", tris=40, grime=0.0).add(box((0, H - 0.03, 0), (w - 0.02, 0.01, w - 0.02), 0.01))
    lf = a.piece("#3E5A3C", tris=300, res=0.008, wear=0.0)
    rng = np.random.default_rng(seed)
    n = 9 if tall else 6
    for k in range(n):
        ang = k * 2 * math.pi / n + rng.uniform(-0.2, 0.2)
        up = rng.uniform(0.25, 0.48) if tall else rng.uniform(0.15, 0.25)
        out = rng.uniform(0.2, 0.32)
        b = (0.0, H - 0.02, 0.0)
        m = (math.cos(ang) * out * 0.5, H + up * 0.9, math.sin(ang) * out * 0.5)
        e = (math.cos(ang) * out, H + up * 0.7, math.sin(ang) * out)
        lf.add(capsule(b, m, 0.012, 0.03), k=0.01)
        lf.add(capsule(m, e, 0.03, 0.008), k=0.02)
    return M(name, [a])


def cone(name="cone", seed=0):
    """Cône de chantier (0,5 m) : base carrée lestée, cône orange éteint, bandes réfléchissantes."""
    a = P(name, res=0.006, seed=seed, tol=0.006)
    dc = Decals(name)
    a.piece(RUBBER, tris=80, res=0.008, grime=0.6).add(box((0, 0.015, 0), (0.17, 0.015, 0.17), 0.02))
    a.piece("#B0583A", tris=220, wear=0.3).add(capsule((0, 0.03, 0), (0, 0.5, 0), 0.12, 0.018))
    for y, r in ((0.3, 0.06), (0.18, 0.083)):
        dc.cyl("stripe", r + 0.004 + (0.0 if y > 0.2 else 0.0), y, 0.05, 0.0, 2 * math.pi * r * 0.98, n=8)
    return M(name, [a], dc)


def neon_pied(name, col, seed=0):
    """Néon portatif sur trépied : tube lumineux vertical dans ses embouts, pied à trois branches, câble."""
    a = P(name, res=0.008, seed=seed, tol=0.006)
    st = a.piece(STEEL, tris=200, wear=0.6)
    for k in range(3):
        ang = math.radians(90 + k * 120)
        st.add(capsule((0, 0.22, 0), (math.cos(ang) * 0.2, 0.01, math.sin(ang) * 0.2), 0.012))
    st.add(capsule((0, 0.2, 0), (0, 0.3, 0), 0.016))
    ec = a.piece("#2A2C32", tris=80, wear=0.3)
    ec.add(S.cyl((0, 0.31, 0), 0.03, 0.02, 0.008))
    ec.add(S.cyl((0, 0.93, 0), 0.03, 0.02, 0.008))
    a.piece(RUBBER, tris=40, res=0.008).add(capsule((0, 0.25, 0), (0.15, 0.01, -0.2), 0.008))
    g = P(name + "_glow", res=0.006)
    g.piece(col, tris=60).add(capsule((0, 0.33, 0), (0, 0.91, 0), 0.022))
    return M(name, [a, g])


def neon_tube(name, col, seed=0):
    """Néon portatif posé contre le parapet (1 m) : tube lumineux incliné, embouts, câble au sol."""
    a = P(name, res=0.008, seed=seed, tol=0.006)
    L = 1.0
    ang = math.radians(28)
    p0 = np.array([0.0, 0.03, 0.0])
    d = np.array([0.0, math.sin(ang), -math.cos(ang)])
    ec = a.piece("#2A2C32", tris=100, wear=0.3)
    ec.add(capsule(tuple(p0), tuple(p0 + d * 0.06), 0.032))
    ec.add(capsule(tuple(p0 + d * (L - 0.06)), tuple(p0 + d * L), 0.032))
    a.piece(RUBBER, tris=40, res=0.008).add(capsule(tuple(p0), (0.25, 0.008, 0.12), 0.008))
    g = P(name + "_glow", res=0.006)
    g.piece(col, tris=60).add(capsule(tuple(p0 + d * 0.06), tuple(p0 + d * (L - 0.06)), 0.02))
    return M(name, [a, g])


def graffiti(name, key, size=1.6):
    """Graffiti au sol (motif abstrait à la bombe) : un quad fondu posé à plat."""
    dg = Decals(name, "graf")
    dg.quad(key, (0, 0.004, 0), size, size, TOP, off=0.0)
    return S.Character(name, [dg])


def cables_sol(name="cables_sol", seed=0):
    """Faisceau de câbles et de gaines posé au sol le long d'un parapet (3 m), colliers, boîtier de raccord."""
    a = P(name, res=0.01, seed=seed, tol=0.008)
    L = 3.0
    cols = ["#25262B", "#5A606C", "#7E5038"]
    for k, c in enumerate(cols):
        pc = a.piece(c, tris=120, res=0.01, grime=0.5)
        r = 0.022 if k != 2 else 0.018
        pts = [(-L * 0.5 + t * L, r, 0.05 * math.sin(t * 7.0 + k * 1.3) + (k - 1) * 0.055) for t in np.linspace(0, 1, 13)]
        for p0, p1 in zip(pts[:-1], pts[1:]):
            pc.add(capsule(p0, p1, r), k=0.01)
    cl = a.piece(STEEL_M, tris=90, res=0.008, wear=0.5)
    for t in (0.2, 0.5, 0.8):
        cl.add(box((-L * 0.5 + t * L, 0.03, 0.0), (0.025, 0.03, 0.12), 0.012))
    bx = a.piece("#4A505C", tris=120, wear=0.9)
    bx.add(box((L * 0.5 + 0.1, 0.09, 0), (0.12, 0.09, 0.16), 0.03))
    g = P(name + "_glow", res=0.004)
    g.piece(LED_G, tris=30).add(sphere((L * 0.5 + 0.17, 0.06, 0.16), 0.012))
    return M(name, [a, g])


# ------------------------------------------------------------------ catalogue
def catalog():
    return {
        "socle": lambda: socle("socle", 1),
        "clim_l_a": lambda: clim_l("clim_l_a", "#727880", 2, "K-12"),
        "clim_l_b": lambda: clim_l("clim_l_b", "#6A7672", 3, "R-07"),
        "clim_m_a": lambda: clim_m("clim_m_a", "#7A7870", 4, "R-07"),
        "clim_m_b": lambda: clim_m("clim_m_b", "#68707E", 5, "K-12"),
        "reservoir_haut": lambda: reservoir_haut("reservoir_haut", 6),
        "reservoir_a": lambda: reservoir("reservoir_a", "#5E6E7E", 7),
        "reservoir_b": lambda: reservoir("reservoir_b", "#7A7264", 8),
        "kiosque": lambda: kiosque("kiosque", 9),
        "distributeur_a": lambda: distributeur("distributeur_a", "#3E4C68", NEON_V, 10),
        "distributeur_b": lambda: distributeur("distributeur_b", "#5A3E58", NEON_G, 11),
        "caisse_m_a": lambda: caisse("caisse_m_a", 0.8, 0.42, 0.6, "#3E6466", 12),
        "caisse_m_b": lambda: caisse("caisse_m_b", 0.8, 0.42, 0.6, "#86703E", 13),
        "caisse_s_a": lambda: caisse("caisse_s_a", 0.6, 0.34, 0.42, "#6E4A5C", 14, lid=False, logo="pakku_k"),
        "caisse_s_b": lambda: caisse("caisse_s_b", 0.6, 0.34, 0.42, "#3E6466", 15, lid=False),
        "carton": lambda: carton("carton", 0.5, 0.34, 0.4, 16),
        "parabole": lambda: parabole("parabole", 17),
        "tas_cables": lambda: tas_cables("tas_cables", 18),
        "boitier_a": lambda: boitier("boitier_a", "#5A645E", seed=19),
        "boitier_b": lambda: boitier("boitier_b", "#5C6270", seed=20, leds=(LED_G, NEON_O, NEON_V)),
        "boitier_s": lambda: boitier("boitier_s", "#5C6270", 0.5, 0.62, 0.36, 21, leds=(LED_G, NEON_O)),
        "flaque_a": lambda: flaque("flaque_a", [(0, 0, 0.45), (0.5, 0.1, 0.35), (-0.4, -0.15, 0.3), (0.15, -0.3, 0.25)]),
        "flaque_b": lambda: flaque("flaque_b", [(0, 0, 0.3), (0.35, 0.15, 0.22), (-0.3, 0.05, 0.2)]),
        "flaque_c": lambda: flaque("flaque_c", [(0, 0, 0.6), (0.7, -0.1, 0.45), (-0.65, 0.2, 0.4), (0.2, 0.45, 0.3), (-0.2, -0.45, 0.35)]),
        "egout": lambda: egout("egout", 22),
        "pot_a": lambda: pot("pot_a", 23),
        "pot_b": lambda: pot("pot_b", 24, 0.36, False),
        "cone": lambda: cone("cone", 25),
        "neon_pied_v": lambda: neon_pied("neon_pied_v", NEON_V, 26),
        "neon_pied_g": lambda: neon_pied("neon_pied_g", NEON_G, 27),
        "neon_tube_o": lambda: neon_tube("neon_tube_o", NEON_O, 28),
        "neon_tube_v": lambda: neon_tube("neon_tube_v", NEON_V, 29),
        "graf_a": lambda: graffiti("graf_a", "graf1", 1.7),
        "graf_b": lambda: graffiti("graf_b", "graf2", 1.5),
        "graf_c": lambda: graffiti("graf_c", "graf3", 1.6),
        "cables_sol": lambda: cables_sol("cables_sol", 30),
    }


def _job(name):
    ch = catalog()[name]()
    ch.export(os.path.join(OUT, name + ".glb"))
    return name


if __name__ == "__main__":
    NA.build()
    names = sys.argv[1:] or list(catalog().keys())
    with Pool(4) as pool:
        for n in pool.imap_unordered(_job, names):
            pass
