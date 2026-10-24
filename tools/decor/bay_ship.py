"""La Pie : navette de fret des Passeurs (le vaisseau de Jo et de son équipe), posée baie 07.
Trapue et ronde : coque blanche usée, bandeau orange qui remonte vers le nez, ventre acier, verrière fumée
en bulle, deux nacelles de réacteurs à l'arrière (tuyères turquoise), quatre jambes de train à vérins,
soute latérale ouverte (côté caméra, +Z) avec rampe posée au sol, intérieur éclairé chaud, caisses à bord,
écusson des Passeurs (disque orange, chevron blanc) sur le flanc.
Repère : nez vers +X, flanc de la soute vers +Z (sud, la caméra), sol à y = 0, origine au centre.
La soute est centrée en x = -0,2. Encombrement : x -2,95..2,95 ; z -1,25..1,95 (rampe) ; hauteur 2,1."""
import math

from bay_lib import *

A_RAMP = math.radians(31.0)
DOOR_X = -0.2


def hull():
    core = box((0, 1.15, 0), (2.1, 0.62, 1.02), 0.5)
    nose = ellip((1.85, 1.06, 0), (1.08, 0.57, 0.98))
    cabin = ellip((1.2, 1.62, 0), (1.05, 0.36, 0.78))
    tailb = ellip((-1.85, 1.3, 0), (0.6, 0.48, 0.9))
    h = union([core, nose], 0.4)
    h = union([h, cabin], 0.32)
    h = union([h, tailb], 0.2)
    return inter(h, halfspace((0, 0.52, 0), (0, -1, 0)), 0.08)  # ventre plat


def band_cut(top=True):
    """Ligne de séparation blanc / orange : horizontale, puis qui remonte vers le nez."""
    def f(P):
        y0 = 0.9 + 0.2 * np.clip((P[:, 0] - 0.7) / 2.0, 0.0, 1.0) ** 1.5
        d = P[:, 1] - y0
        return -d if top else d
    return Shape(f, v(-60, -60, -60), v(60, 60, 60))


def build():
    H = hull()
    D = box((DOOR_X, 1.08, 1.05), (0.8, 0.46, 0.8), 0.06)  # soute : creusée dans le flanc +Z
    canopy = inter(ellip((1.68, 1.62, 0), (0.76, 0.44, 0.74)), halfspace((1.05, 0, 0), (-1, 0, 0)), 0.05)
    side_win = [ellip((1.9, 1.36, s * 0.98), (0.3, 0.13, 0.5)) for s in (-1, 1)]
    skin = shell(offset(H, 0.04), 0.09)
    grooves = [inter(slab(0, x - 0.012, x + 0.012), skin) for x in (0.78, -1.13)]
    emblem_c = v(1.12, 1.18, 1.0)
    fuel_c = v(-1.3, 0.76, 1.0)

    body = BPart("ship", res=0.02, floor=0.0, seed=3.0)
    # suie derrière les tuyères, crasse autour de la trappe de carburant et sous la soute
    for s in (-1, 1):
        body.stain((-2.75, 1.02, s * 0.84), 0.45, 0.6, "#1A1A1E")
    body.stain(fuel_c, 0.22, 0.45, "#2A2218")
    body.stain((DOOR_X, 0.62, 1.1), 0.5, 0.3, "#30302E")

    white = body.piece(WHITE_D, tris=2600, wear=0.3, dirt=0.6)
    white.add(inter(H, band_cut(True)))
    white.sub(D)
    white.sub(canopy)
    for w in side_win:
        white.sub(w)
    for g in grooves:
        white.sub(g)
    white.sub(zcyl(emblem_c + v(0, 0, 0.03), 0.26, 0.07, 0.0))

    orange = body.piece(ORANGE, tris=900, wear=0.45)
    orange.add(inter(inter(offset(H, 0.006), band_cut(False)), halfspace((0, 0.64, 0), (0, -1, 0))))
    orange.sub(offset(D, 0.006))
    orange.sub(zcyl(fuel_c + v(0, 0, 0.03), 0.13, 0.07, 0.0))
    for g in grooves:
        orange.sub(g)

    belly = body.piece(GUN, tris=500, wear=0.3)
    belly.add(inter(H, halfspace((0, 0.645, 0), (0, 1, 0))))
    belly.sub(D)
    # cerclage de la verrière et montant central
    frame_p = body.piece(GUN_D, tris=500, res=0.014, wear=0.3)
    frame_p.add(inter(shell(offset(H, 0.03), 0.07), diff(offset(canopy, 0.05), canopy)))
    frame_p.add(capsule((1.0, 1.95, 0), (2.35, 1.42, 0), 0.032))
    for w in side_win:
        frame_p.add(inter(shell(offset(H, 0.022), 0.06), diff(offset(w, 0.035), w)))
    # cadre de la soute
    dfr = body.piece(GUN, tris=450, res=0.015, wear=0.7)
    dfr.add(inter(shell(offset(H, 0.03), 0.07), diff(offset(D, 0.07), D)))
    # intérieur de la soute : parois sombres, éclairées chaud en haut du fond, plancher strié, caisses
    hold = body.piece("#3A3C44", tris=420, res=0.02, wear=0.1)
    hold.add(inter(diff(offset(D, 0.06), D), H))
    hold.paint(box((DOOR_X, 1.45, 0.3), (0.8, 0.14, 0.1), 0.0), "#7A6A55")
    ribs = body.piece(GUN_D, tris=120, res=0.012, wear=0.5)
    for i in range(5):
        ribs.add(box((DOOR_X - 0.6 + i * 0.3, 0.625, 0.72), (0.025, 0.02, 0.42), 0.01))
    crates = body.piece(ORANGE_D, tris=130, res=0.02, wear=0.9)
    crates.add(box((DOOR_X - 0.48, 0.86, 0.55), (0.26, 0.24, 0.24), 0.03))
    crates2 = body.piece(HXF, tris=150, res=0.02, wear=0.9)
    crates2.add(box((DOOR_X + 0.12, 0.79, 0.5), (0.3, 0.17, 0.2), 0.03))
    crates2.add(box((DOOR_X + 0.07, 1.06, 0.48), (0.22, 0.1, 0.17), 0.03))
    strap = body.piece(BLACK, tris=60, res=0.01, wear=0.0)
    strap.add(box((DOOR_X - 0.48, 0.86, 0.55), (0.03, 0.255, 0.255), 0.01))
    # rampe : plaque inclinée, stries antidérapantes, bordures jaunes, vérins
    L = 0.93 / math.cos(A_RAMP)
    Mr = frame((0, -math.sin(A_RAMP), math.cos(A_RAMP)))
    hinge = v(DOOR_X, 0.62, 1.03)
    dirv = v(0, -math.sin(A_RAMP), math.cos(A_RAMP))
    upv = Mr[:, 1]
    mid = hinge + dirv * (L * 0.5) - upv * 0.035
    ramp = body.piece(GUN, tris=300, res=0.014, wear=0.9)
    ramp.add(obox(mid, (0.76, 0.035, L * 0.5), 0.015, Mr))
    for i in range(6):
        body.prim_box(GUN_D, hinge + dirv * (0.14 + i * 0.16) + upv * 0.008, (0.62, 0.012, 0.022), Mr)
    rails = body.piece(YELLOW, tris=220, res=0.012, wear=1.0)
    for sx in (-0.73, 0.73):
        rails.add(obox(mid + v(sx, 0, 0) + upv * 0.03, (0.035, 0.035, L * 0.5), 0.012, Mr))
    body.prim_box(BLACK, hinge + dirv * (L - 0.03) - upv * 0.02, (0.76, 0.032, 0.04), Mr)
    for sx in (-0.74, 0.74):
        body.prim_cyl(STEEL_L, (DOOR_X + sx, 0.98, 1.06), (DOOR_X + sx, 0.47, 1.32), 0.022, 8)
    # nacelles des réacteurs
    nac = body.piece(WHITE_D, tris=800, wear=0.5)
    ring = body.piece(ORANGE, tris=300, res=0.015, wear=0.6)
    bell = body.piece(GUN_D, tris=450, res=0.015, wear=0.5, bare=STEEL_L)
    for s in (-1, 1):
        c = v(-2.2, 1.02, s * 0.84)
        nshape = union([xcyl(c, 0.42, 0.58, 0.2), ellip(c + v(0.6, 0, -s * 0.06), (0.48, 0.35, 0.35))], 0.15)
        nac.add(nshape)
        ring.add(inter(offset(nshape, 0.01), slab(0, -1.92, -1.76)))
        b = xcyl(c + v(-0.62, 0, 0), 0.36, 0.11, 0.05)
        bell.add(diff(b, xcyl(c + v(-0.72, 0, 0), 0.27, 0.12, 0.02), 0.02))
        for i in range(3):  # ailettes de refroidissement
            bell.add(obox(c + v(-0.12 - i * 0.16, 0.41, 0), (0.035, 0.03, 0.18), 0.012, frame((0, 0, 1), (s * 0.35, 1, 0))))
    # dérives arrière : ailerons ronds et épais, inclinés vers l'extérieur, bouts orange
    fin = body.piece(WHITE_D, tris=380, res=0.014, wear=0.6)
    tip = body.piece(ORANGE, tris=200, res=0.012, wear=0.7)
    for s in (-1, 1):
        Mf = R(s * 24, 0, -30)
        f = union([oellip((-1.8, 1.86, s * 0.5), (0.36, 0.26, 0.075), Mf), oellip((-1.72, 1.7, s * 0.47), (0.36, 0.1, 0.1), Mf)], 0.06)
        fin.add(f)
        tip.add(inter(offset(f, 0.006), halfspace((0, 2.0, 0), (0, -1, 0))))
    # train d'atterrissage : jambes, vérins chromés, patins
    gear = body.piece(GUN_D, tris=800, res=0.014, wear=0.6)
    chrome = body.piece(STEEL_L, tris=200, res=0.01, wear=0.0)
    pads = body.piece(RUBBER, tris=320, res=0.014, wear=0.0, dirt=1.5)
    for gx in (1.5, -1.45):
        for s in (-1, 1):
            top_ = v(gx, 0.6, s * 0.6)
            foot = v(gx + (0.1 if gx > 0 else -0.1), 0.12, s * 0.82)
            knee = top_ * 0.5 + foot * 0.5 + v(0, 0, s * 0.06)
            gear.add(capsule(top_, knee, 0.075, 0.06), k=0.02)
            chrome.add(capsule(knee, foot + v(0, 0.06, 0), 0.04))
            gear.add(ocyl(knee, 0.075, 0.05, 0.02, frame(foot - top_)))
            gear.add(capsule(top_ + v(-0.25 if gx > 0 else 0.25, 0, 0), knee, 0.035), k=0.01)
            pads.add(ycyl(foot + v(0, -0.07, 0), 0.19, 0.05, 0.03))
            gear.add(ycyl(foot, 0.08, 0.04, 0.02))
    # toit : grilles d'aération, trappe, mât d'antenne
    roof = body.piece(GUN, tris=420, res=0.012, wear=0.6)
    for s in (-1, 1):
        roof.add(box((-0.95, 1.76, s * 0.42), (0.32, 0.03, 0.16), 0.02))
        for i in range(4):
            roof.sub(box((-1.16 + i * 0.14, 1.8, s * 0.42), (0.024, 0.03, 0.12), 0.005))
    roof.add(ycyl((-0.15, 1.78, 0.0), 0.24, 0.025, 0.012))
    body.prim_cyl(STEEL, (0.25, 1.78, -0.52), (0.2, 2.2, -0.6), 0.014, 6)
    roof.add(ycyl((0.25, 1.79, -0.52), 0.05, 0.03, 0.01))
    roof.add(sphere((0.2, 2.2, -0.6), 0.025))
    # écusson des Passeurs sur le flanc : disque orange, chevron blanc
    emb = body.piece(ORANGE, tris=260, res=0.01, wear=0.1)
    emb.add(inter(offset(H, 0.004), zcyl(emblem_c + v(0, 0, 0.03), 0.26, 0.07, 0.0)))
    chev = body.piece(WHITE, tris=160, res=0.008, wear=0.05)
    sk = shell(offset(H, 0.012), 0.03)
    for s in (-1, 1):
        chev.add(inter(sk, obox(emblem_c + v(-0.03, s * 0.065, 0), (0.14, 0.038, 0.3), 0.01, R(0, 0, -s * 40))))
    # trappe de carburant, poignée, propulseurs d'attitude
    misc = body.piece(GUN_D, tris=320, res=0.01, wear=0.7)
    misc.add(inter(shell(offset(H, 0.02), 0.05), zcyl(fuel_c + v(0, 0, 0.03), 0.13, 0.08, 0.0)))
    misc.add(zcyl(fuel_c + v(0, 0, 0.04), 0.055, 0.05, 0.01))
    misc.add(capsule((DOOR_X + 0.98, 0.78, 1.08), (DOOR_X + 0.98, 1.32, 1.08), 0.022))
    misc.add(zcyl((2.0, 0.86, 0.9), 0.06, 0.08, 0.015))  # prise d'énergie sol
    for x, y, zz in ((2.35, 1.42, 0.72), (-1.9, 1.62, 0.8)):
        for s in (-1, 1):
            misc.add(box((x, y, s * zz), (0.07, 0.05, 0.07), 0.015))
    parts = [body]

    glass = BPart("ship_glass", res=0.015, seed=1.0)
    gl = glass.piece(GLASS, tris=600, wear=0.0, dirt=0.2)
    gl.add(inter(offset(H, 0.012), canopy))
    for w in side_win:
        gl.add(inter(offset(H, 0.008), w))
    gl.paint(obox((1.62, 1.78, 0.2), (0.12, 0.3, 0.9), 0.0, R(0, 0, -35)), GLASS_L)
    gl.paint(obox((1.95, 1.62, 0.2), (0.04, 0.3, 0.9), 0.0, R(0, 0, -35)), GLASS_L)
    parts.append(glass)

    glow = BPart("ship_glow", res=0.01)
    tg = glow.piece("#2FC2AE", tris=200)
    core = glow.piece("#1C7F76", tris=160)
    for s in (-1, 1):
        core.add(xcyl((-2.86, 1.02, s * 0.84), 0.28, 0.015, 0.01))  # tuyère au ralenti : cœur sombre, anneau vif
        tg.add(otorus((-2.875, 1.02, s * 0.84), 0.235, 0.03, frame((1, 0, 0))))
        tg.add(ellip((2.9, 0.98, s * 0.4), (0.04, 0.06, 0.12)))  # phares du nez
    wm = glow.piece("#B89268", tris=120)
    wm.add(box((DOOR_X, 1.45, 0.31), (0.7, 0.03, 0.02), 0.01))
    parts.append(glow)

    blink = BPart("ship_blink", res=0.008)
    bl = blink.piece(TEAL, tris=160)
    bl.add(ellip((0.4, 1.82, 0.0), (0.06, 0.05, 0.06)))
    for s in (-1, 1):
        bl.add(sphere((-1.58, 1.4, s * 1.17), 0.035))
    parts.append(blink)
    return Prop("bay_ship", parts)
