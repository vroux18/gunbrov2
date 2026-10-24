"""Équipement du quai nord (baie 07, compagnie de fret ORVA). Tous les objets regardent vers +Z (le quai, la
caméra), sol à y = 0. Les tuyaux qui vont jusqu'au vaisseau suivent la disposition de hangar_bay.gd.
  bay_pump    : pompe à carburant ORVA (armoire, cadran, enrouleur, pistolet, gyrophare) + tuyau jusqu'à la
                trappe de carburant de la Pie ;
  bay_power   : groupe de parc « énergie sol » sur roues + câble jusqu'à la prise du nez ;
  bay_console : pupitre (l'écran animé est posé par hangar_bay.gd), bay_console2 : pupitre double ;
  bay_rack_a / bay_rack_b : râteliers à caisses ; bay_pallet_a/b/c : palettes chargées ; bay_container ;
  bay_flood   : projecteur sur trépied ; bay_beacon : balise de l'aire (clignote) ;
  bay_gas     : cage à bouteilles de gaz ; bay_drums : fûts."""
import math

from bay_lib import *

# positions (repère du monde, m) reprises de hangar_bay.gd
SHIP = v(18.95, 0.0, 1.86)
PUMP = v(13.6, 0.0, 0.95)
POWER = v(24.4, 0.0, 1.3)
FUEL_PORT = SHIP + v(-1.3, 0.76, 1.04)
NOSE_PLUG = SHIP + v(2.0, 0.86, 0.93)


def pump():
    p = BPart("pump", res=0.014, seed=11.0)
    p.stain((0, 0.0, 0.3), 0.5, 0.5, "#141414")
    p.piece(GUN, tris=60, wear=0.7).add(box((0, 0.05, 0), (0.42, 0.05, 0.3), 0.015))
    cab = p.piece(ORVA_D, tris=200, res=0.018, wear=0.7)
    cab.add(box((0, 0.68, 0), (0.36, 0.6, 0.25), 0.05))
    cab.sub(box((0, 0.85, 0.27), (0.29, 0.3, 0.04), 0.02))
    pan = p.piece(CREAM, tris=80, wear=0.6)
    pan.add(box((0, 0.85, 0.235), (0.27, 0.28, 0.02), 0.012))
    dk = p.piece(BLACK, tris=80, wear=0.0)
    dk.add(box((0, 0.99, 0.255), (0.18, 0.075, 0.01), 0.006))
    dk.add(zcyl((0.12, 0.72, 0.255), 0.07, 0.01, 0.004))
    p.piece(YELLOW, tris=60, wear=0.9).add(box((0, 1.25, 0), (0.37, 0.035, 0.26), 0.012))
    p.piece(GUN_D, tris=80, wear=0.5).add(box((0.41, 0.82, 0.05), (0.05, 0.13, 0.08), 0.015))
    p.piece(BLACK, tris=60, wear=0.0).add(capsule((0.44, 0.94, 0.07), (0.47, 0.72, 0.13), 0.025))
    reel = p.piece(RUBBER, tris=160, wear=0.0)
    reel.add(otorus((-0.43, 0.62, 0.0), 0.16, 0.05, frame((1, 0, 0))))
    p.piece(STEEL, tris=60, wear=0.2).add(xcyl((-0.42, 0.62, 0), 0.08, 0.05, 0.015))
    # tuyau : du pied de la pompe, couché au sol, remonte jusqu'à la trappe de la Pie
    end = FUEL_PORT - PUMP + v(0, 0, 0.07)
    pts = bezier((0.08, 0.2, 0.28), (0.15, 0.03, 0.9), (1.2, 0.04, 1.8), (2.4, 0.045, 2.05), 7)
    pts += bezier((2.4, 0.045, 2.05), (3.4, 0.05, 2.3), (end[0] - 0.1, 0.1, end[2] + 0.4), end + v(0, 0, 0.12), 6)[1:]
    hose = p.piece(RUBBER, tris=260, res=0.012, wear=0.0, dirt=1.4)
    hose.add(tube(pts, 0.042, 0.02))
    cpl = p.piece(ORANGE_D, tris=60, res=0.01, wear=0.6)
    cpl.add(zcyl(end + v(0, 0, 0.06), 0.058, 0.05, 0.015))
    g = BPart("pump_glow", res=0.006)
    g.piece("#7A4A22", tris=40).add(box((0, 0.99, 0.262), (0.16, 0.055, 0.004), 0.002))
    g.piece("#1E7F75", tris=40).add(box((-0.18, 0.62, 0.262), (0.035, 0.02, 0.004), 0.002))
    b = BPart("pump_blink", res=0.008)
    b.piece("#FFB060", tris=60).add(ycyl((0.22, 1.32, 0), 0.05, 0.04, 0.02))
    return Prop("bay_pump", [p, g, b])


def power():
    p = BPart("power", res=0.016, seed=12.0)
    body = p.piece(ORVA, tris=220, wear=0.7)
    body.add(box((0, 0.5, 0), (0.55, 0.3, 0.36), 0.06))
    body.sub(box((0, 0.5, 0.38), (0.4, 0.18, 0.04), 0.02))
    p.piece(CREAM, tris=50, wear=0.6).add(box((0, 0.5, 0.345), (0.38, 0.16, 0.015), 0.01))
    p.piece(GUN_D, tris=60, wear=0.3).add(box((0.18, 0.55, 0.36), (0.12, 0.07, 0.01), 0.005))
    frm = p.piece(GUN, tris=140, wear=0.6)
    frm.add(box((0, 0.2, 0), (0.6, 0.04, 0.4), 0.015))
    frm.add(capsule((-0.6, 0.22, 0), (-0.95, 0.12, 0), 0.03))
    frm.add(torus((-0.97, 0.12, 0), 0.06, 0.02))
    p.piece(YELLOW, tris=60, wear=0.9).add(box((0, 0.82, 0), (0.56, 0.025, 0.37), 0.01))
    wh = p.piece(RUBBER, tris=200, wear=0.0, dirt=1.5)
    for wx in (-0.38, 0.38):
        for wz in (-0.4, 0.4):
            wh.add(zcyl((wx, 0.12, wz), 0.12, 0.05, 0.03))
    for i in range(3):  # ouïes
        p.piece(GUN_D, tris=30, wear=0.0).add(box((-0.56, 0.45 + i * 0.08, 0), (0.01, 0.02, 0.25), 0.005))
    end = NOSE_PLUG - POWER
    pts = bezier((-0.5, 0.35, 0.36), (-0.6, 0.03, 0.8), (-1.6, 0.03, 1.4), (-2.4, 0.035, 1.4), 6)
    pts += bezier((-2.4, 0.035, 1.4), (-3.0, 0.04, 1.4), (end[0] + 0.1, 0.1, end[2] + 0.35), end + v(0, 0, 0.08), 5)[1:]
    cab = p.piece("#2A2A30", tris=200, res=0.012, wear=0.0, dirt=1.3)
    cab.add(tube(pts, 0.03, 0.015))
    p.piece(YELLOW, tris=40, res=0.01, wear=0.5).add(zcyl(end + v(0, 0, 0.05), 0.045, 0.045, 0.012))
    g = BPart("power_glow", res=0.006)
    g.piece("#1E7F75", tris=40).add(box((0.13, 0.57, 0.372), (0.04, 0.02, 0.004), 0.002))
    g.piece("#7A4A22", tris=40).add(box((0.25, 0.57, 0.372), (0.03, 0.02, 0.004), 0.002))
    return Prop("bay_power", [p, g])


def console(double=False):
    name = "bay_console2" if double else "bay_console"
    p = BPart("console", res=0.014, seed=13.0 + double)
    hw = 0.8 if double else 0.36
    ped = p.piece(NAVY, tris=160, res=0.018, wear=0.7)
    ped.add(box((0, 0.42, 0), (hw, 0.42, 0.24), 0.04))
    ped.sub(box((0, 0.05, 0.26), (hw - 0.05, 0.06, 0.06), 0.02))
    p.piece(ORVA, tris=40, wear=0.7).add(box((0, 0.62, 0.236), (hw, 0.035, 0.012), 0.008))
    desk = p.piece(SLATE, tris=80, wear=0.8)
    desk.add(obox((0, 0.86, 0.08), (hw + 0.04, 0.035, 0.27), 0.015, R(25, 0, 0)))
    hs = (-0.42, 0.42) if double else (0.0,)
    for hx in hs:
        p.prim_box(GUN_D, (hx, 0.9, 0.15), (0.26, 0.012, 0.1), R(25, 0, 0))
    hou = p.piece(NAVY_D, tris=160, res=0.014, wear=0.6)
    for hx in hs:
        hou.add(obox((hx, 1.12, -0.12), (0.37, 0.22, 0.05), 0.025, R(-20, 0, 0)))
        hou.sub(obox((hx, 1.12, -0.07), (0.33, 0.18, 0.02), 0.01, R(-20, 0, 0)))
    g = BPart("console_glow", res=0.006)
    tg = g.piece("#1E8F84", tris=60)
    og = g.piece("#9A5020", tris=60)
    for hx in hs:
        for i in range(3):
            (tg if i != 1 else og).add(sphere((hx + 0.12 + i * 0.05, 0.93, 0.05), 0.014))
    return Prop(name, [p, g])


def crate(pc_body, pc_band, c, half, rot=0.0, band=True):
    M = R(0, rot, 0)
    pc_body.add(obox(c, half, 0.03, M))
    if band:
        pc_band.add(obox(c, (half[0] * 0.18, half[1] + 0.006, half[2] + 0.006), 0.01, M))


def rack(seed):
    rg = np.random.default_rng(seed)
    p = BPart("rack", res=0.016, seed=float(seed))
    for x in (-1.4, 0.0, 1.4):
        for z in (0.1, 0.75):
            p.prim_box(SLATE, (x, 0.78, z), (0.035, 0.78, 0.035))
        p.prim_box(SLATE, (x, 0.4, 0.425), (0.015, 0.02, 0.32))
        p.prim_box(SLATE, (x, 1.2, 0.425), (0.015, 0.02, 0.32))
    for y in (0.14, 0.86):
        for z in (0.1, 0.75):
            p.prim_box(ORVA_D, (0, y, z), (1.42, 0.045, 0.028))
        p.prim_box(GUN_D, (0, y + 0.05, 0.425), (1.38, 0.012, 0.33))
    cols = [ORVA, CREAM, SLATE, ORVA_D, CREAM, "#8C6A4A"]
    bodies = {c: p.piece(c, tris=110, res=0.02, wear=0.8) for c in set(cols)}
    band = p.piece(BLACK, tris=120, res=0.012, wear=0.0)
    for y0 in (0.2, 0.92):
        x = -1.3
        while x < 1.2:
            w = rg.uniform(0.22, 0.4)
            h = rg.uniform(0.18, 0.3) if y0 > 0.5 else rg.uniform(0.2, 0.32)
            d = rg.uniform(0.22, 0.3)
            if x + 2 * w > 1.35:
                break
            col = cols[rg.integers(len(cols))]
            crate(bodies[col], band, (x + w, y0 + h, 0.42 + rg.uniform(-0.04, 0.04)), (w, h, d), rg.uniform(-6, 6), rg.random() < 0.6)
            if rg.random() < 0.35 and y0 > 0.5:
                crate(bodies[cols[rg.integers(len(cols))]], band, (x + w, y0 + 2 * h + 0.14, 0.42), (w * 0.7, 0.14, d * 0.8), rg.uniform(-10, 10), False)
            x += 2 * w + rg.uniform(0.04, 0.12)
    return Prop("bay_rack_" + "ab"[seed % 2], [p])


def pallet(name, layout):
    p = BPart("pallet", res=0.018, seed=float(len(name)))
    pal = p.piece(GUN_D, tris=90, wear=0.6)
    pal.add(box((0, 0.06, 0), (0.6, 0.06, 0.5), 0.015))
    for x in (-0.4, 0.0, 0.4):
        pal.sub(box((x, 0.04, 0.6), (0.12, 0.035, 0.7), 0.01))
    bodies = {}
    band = p.piece(BLACK, tris=100, res=0.012, wear=0.0)
    lab = p.piece(CREAM, tris=60, res=0.01, wear=0.3)
    for (col, c, half, rot) in layout:
        if col not in bodies:
            bodies[col] = p.piece(col, tris=120, res=0.02, wear=0.9)
        crate(bodies[col], band, c, half, rot)
        lab.add(obox((c[0] + half[0] * 0.45, c[1] + half[1] * 0.2, c[2] + half[2] + 0.004), (0.08, 0.05, 0.006), 0.004, R(0, rot, 0)))
    return Prop(name, [p])


def container():
    p = BPart("container", res=0.02, seed=21.0)
    b = p.piece(ORVA, tris=260, wear=0.9)
    b.add(box((0, 0.48, 0), (0.62, 0.45, 0.48), 0.04))
    rib = p.piece(ORVA_D, tris=200, res=0.016, wear=0.9)
    for x in (-0.45, -0.15, 0.15, 0.45):
        rib.add(box((x, 0.48, 0), (0.03, 0.42, 0.5), 0.012))
    p.piece(GUN, tris=120, wear=0.7).add(box((0, 0.95, 0), (0.64, 0.025, 0.5), 0.012))
    cn = p.piece(GUN_D, tris=160, wear=0.4)
    for x in (-0.6, 0.6):
        for z in (-0.46, 0.46):
            cn.add(box((x, 0.48, z), (0.05, 0.47, 0.05), 0.015))
    p.piece(CREAM, tris=40, res=0.01, wear=0.3).add(box((0.3, 0.6, 0.495), (0.12, 0.08, 0.006), 0.004))
    p.piece(YELLOW, tris=60, res=0.012, wear=0.8).add(box((-0.3, 0.972, 0), (0.18, 0.006, 0.3), 0.004))
    return Prop("bay_container", [p])


def flood():
    p = BPart("flood", res=0.012, seed=31.0)
    leg = p.piece(GUN_D, tris=120, wear=0.5)
    for a in range(3):
        t = a * 2 * math.pi / 3 + 0.5
        leg.add(capsule((0, 0.5, 0), (math.cos(t) * 0.32, 0.02, math.sin(t) * 0.32), 0.02))
    leg.add(capsule((0, 0.45, 0), (0, 0.66, 0), 0.03))
    yoke = p.piece(YELLOW, tris=100, wear=0.8)
    yoke.add(box((0, 0.68, 0), (0.2, 0.02, 0.04), 0.01))
    for x in (-0.19, 0.19):
        yoke.add(box((x, 0.8, 0), (0.02, 0.13, 0.04), 0.01))
    d = nrm(v(0, -math.sin(math.radians(25)), math.cos(math.radians(25))))
    c = v(0, 0.86, 0.0)
    M = frame(d)
    head = p.piece(GUN, tris=200, wear=0.6)
    head.add(ocyl(c, 0.16, 0.12, 0.04, M))
    head.sub(ocyl(c + d * 0.13, 0.13, 0.03, 0.01, M))
    for i in range(3):
        head.add(ocyl(c - d * (0.13 + i * 0.035), 0.13 - i * 0.02, 0.01, 0.005, M))
    p.piece(STEEL, tris=40, wear=0.0).add(xcyl((0, 0.86, 0), 0.03, 0.2, 0.01))
    g = BPart("flood_glow", res=0.008)
    g.piece("#E8DCC0", tris=60).add(ocyl(c + d * 0.1, 0.13, 0.01, 0.004, M))
    return Prop("bay_flood", [p, g])


def beacon():
    p = BPart("beacon", res=0.008, seed=41.0)
    p.piece(GUN_D, tris=40, wear=0.5).add(ycyl((0, 0.015, 0), 0.075, 0.015, 0.006))
    b = BPart("beacon_blink", res=0.008)
    b.piece("#FFB868", tris=50).add(inter(sphere((0, 0.03, 0), 0.05), halfspace((0, 0.03, 0), (0, -1, 0))))
    return Prop("bay_beacon", [p, b])


def gas():
    p = BPart("gas", res=0.016, seed=51.0)
    for x in (-0.7, 0.7):
        p.prim_box(SLATE, (x, 0.6, 0.1), (0.03, 0.6, 0.03))
        p.prim_box(SLATE, (x, 0.6, 0.55), (0.03, 0.6, 0.03))
    for y in (0.05, 0.75):
        p.prim_box(SLATE, (0, y, 0.55), (0.72, 0.025, 0.02))
        p.prim_box(SLATE, (0, y, 0.1), (0.72, 0.025, 0.02))
    cols = [ORVA, CREAM, ORVA, SLATE, CREAM]
    bodies = {c: p.piece(c, tris=120, res=0.016, wear=0.7) for c in set(cols)}
    tops = p.piece(GUN_D, tris=120, res=0.012, wear=0.3)
    for i, c in enumerate(cols):
        x = -0.52 + i * 0.26
        bodies[c].add(capsule((x, 0.12, 0.32), (x, 0.92, 0.32), 0.11))
        tops.add(ycyl((x, 1.06, 0.32), 0.035, 0.04, 0.01))
    p.prim_cyl(STEEL, (-0.7, 0.62, 0.48), (0.7, 0.62, 0.48), 0.012, 6)
    return Prop("bay_gas", [p])


def drums():
    p = BPart("drums", res=0.016, seed=61.0)
    b = p.piece(ORVA_D, tris=300, wear=0.8)
    r = p.piece(GUN, tris=200, res=0.012, wear=0.6)
    t = p.piece(GUN_D, tris=60, res=0.012, wear=0.2)
    for (x, z) in ((0, 0), (0.58, 0.12), (0.25, 0.55)):
        b.add(ycyl((x, 0.43, z), 0.28, 0.43, 0.03))
        for y in (0.28, 0.6):
            r.add(ycyl((x, y, z), 0.288, 0.015, 0.008))
        t.add(ycyl((x + 0.12, 0.87, z), 0.04, 0.015, 0.006))
    return Prop("bay_drums", [p])


def cones():
    p = BPart("cones", res=0.012, seed=81.0)
    body = p.piece(ORANGE_D, tris=160, wear=0.6)
    band = p.piece(CREAM, tris=100, wear=0.5)
    base = p.piece(BLACK, tris=60, wear=0.0)
    for (x, z) in ((0.0, 0.0), (0.42, 0.18)):
        c = capsule((x, 0.04, z), (x, 0.46, z), 0.12, 0.022)
        body.add(c)
        band.add(inter(offset(c, 0.004), slab(1, 0.22, 0.3)))
        base.add(box((x, 0.02, z), (0.16, 0.02, 0.16), 0.01))
    return Prop("bay_cones", [p])


def cart():
    p = BPart("cart", res=0.014, seed=82.0)
    p.piece(ORVA_D, tris=120, wear=0.8).add(box((0, 0.5, 0), (0.38, 0.36, 0.25), 0.03))
    for i in range(4):
        p.prim_box(GUN_D, (0, 0.28 + i * 0.15, 0.252), (0.34, 0.006, 0.004))
        p.prim_box(STEEL, (0, 0.33 + i * 0.15, 0.258), (0.08, 0.012, 0.008))
    p.piece(GUN, tris=60, wear=0.6).add(box((0, 0.88, 0), (0.4, 0.025, 0.27), 0.01))
    p.prim_cyl(STEEL, (-0.44, 0.86, -0.2), (-0.44, 0.86, 0.2), 0.016, 6)
    p.prim_cyl(STEEL, (-0.36, 0.86, -0.2), (-0.44, 0.86, -0.2), 0.016, 6)
    p.prim_cyl(STEEL, (-0.36, 0.86, 0.2), (-0.44, 0.86, 0.2), 0.016, 6)
    tb = p.piece(ORANGE_D, tris=80, wear=0.8)
    tb.add(box((0.1, 0.98, 0.0), (0.2, 0.08, 0.1), 0.02))
    p.prim_cyl(GUN_D, (0.0, 1.08, 0.0), (0.2, 1.08, 0.0), 0.012, 6)
    wh = p.piece(RUBBER, tris=120, wear=0.0)
    for x in (-0.3, 0.3):
        for z in (-0.18, 0.18):
            wh.add(zcyl((x, 0.06, z), 0.06, 0.025, 0.01))
    return Prop("bay_cart", [p])


def reel():
    p = BPart("reel", res=0.014, seed=83.0)
    d = p.piece(GUN_D, tris=160, wear=0.6)
    for z in (-0.2, 0.2):
        d.add(zcyl((0, 0.36, z), 0.36, 0.02, 0.01))
    cab = p.piece(YELLOW, tris=200, wear=0.2)
    cab.add(zcyl((0, 0.36, 0), 0.27, 0.18, 0.06))
    for i in range(4):
        p.prim_box(BLACK, (0, 0.36, -0.15 + i * 0.1), (0.272, 0.006, 0.006), R(0, 0, i * 45))
    tail = tube(bezier((0.25, 0.4, 0.1), (0.5, 0.2, 0.25), (0.7, 0.03, 0.4), (1.1, 0.03, 0.5), 5), 0.022, 0.01)
    p.piece(YELLOW, tris=80, res=0.01, wear=0.2).add(tail)
    return Prop("bay_reel", [p])


def build():
    pa = pallet("bay_pallet_a", [(ORVA, (-0.28, 0.4, 0.0), (0.28, 0.28, 0.42), 2), (CREAM, (0.3, 0.36, 0.05), (0.26, 0.24, 0.36), -4), (ORVA_D, (-0.2, 0.86, 0.02), (0.22, 0.18, 0.3), 8)])
    pb = pallet("bay_pallet_b", [(CREAM, (0.0, 0.42, 0.0), (0.56, 0.3, 0.45), 1), (ORVA, (0.15, 0.9, 0.05), (0.3, 0.18, 0.3), -9)])
    pc = pallet("bay_pallet_c", [(SLATE, (-0.3, 0.32, -0.1), (0.25, 0.2, 0.3), 3), (ORVA, (0.25, 0.38, 0.0), (0.3, 0.26, 0.42), -2), ("#8C6A4A", (-0.3, 0.32, 0.3), (0.24, 0.2, 0.16), 0)])
    return [pump(), power(), console(), console(True), rack(1), rack(2), pa, pb, pc, container(), flood(), beacon(), gas(), drums(), cones(), cart(), reel()]
