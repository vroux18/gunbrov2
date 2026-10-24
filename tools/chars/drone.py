"""Sentinelle (code « drone ») : petit drone flottant de la faction du Portique, en essaim, qui fonce au contact.
Coque ronde claire en deux tons, ceinture de métal sombre, GROS œil unique lumineux incliné vers le haut
(lisible depuis la caméra haute de 56°), sourcil de visière, deux antennes à boules orange, ailerons latéraux,
dérive arrière orange (sens du drone vu du dessus), bague de propulsion flottante à nacelles qui tourne autour
du corps, tuyère lumineuse dessous.
Regarde vers +Z ; sa droite est en -X. Pas de pieds : le corps flotte, centre à y = 0,5.
Variante élite (build(elite=True)) : accent lumineux or, double dérive en crête, ailerons à double pointe,
cornes d'antenne, anneau à six nacelles. Même structure de pièces."""
import math

import fast_simplification
import trimesh
from skimage import measure

from sculpt import *
from sculpt import Part as _Part

HULL_L = "#C8CEDC"   # coque claire (dessus)
HULL = "#9AA4B6"     # coque (dessous)
METAL = "#2C3350"    # métal sombre
METAL_L = "#454E70"  # métal sombre éclairci (détails)
ORANGE = "#FF7A2F"
RED = "#FF4D6D"
RED_IRIS = "#FF1A3C"  # iris : #FF4D6D poussé (la lueur ×3 le délave vers le rose)
RED_RIM = "#A8001A"  # bord de l'œil (plus saturé : reste rouge une fois lumineux)
GOLD = "#FFB347"
GOLD_RIM = "#F08A10"
PUPIL = "#1A0610"
PUPIL_E = "#2A1404"
WHITE = "#FFFFFF"

C = np.array([0.0, 0.5, 0.0])  # centre du corps


class Part(_Part):
    """Pièce de sculpt.Part dont les normales sont celles, exactes, du champ de distance (gradient) plutôt
    que celles du maillage allégé : coque lisse sans taches de facettes, silhouettes inchangées. L'occlusion
    ambiante simulée est calculée le long de ces normales (même formule que sculpt.py), donc sans taches."""

    def _piece_mesh(self, pc):
        res = pc.res or self.res
        lo, hi = pc.bounds()
        n = np.ceil((hi - lo) / res).astype(int) + 1
        xs = [np.linspace(lo[i], lo[i] + (n[i] - 1) * res, n[i]) for i in range(3)]
        G = np.stack(np.meshgrid(*xs, indexing="ij"), axis=-1).reshape(-1, 3)
        vol = pc.sdf(G).reshape(n)
        if vol.min() > 0 or vol.max() < 0:
            return None
        verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(res,) * 3)
        verts = verts + lo
        if len(faces) > pc.tris:
            verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), target_reduction=1.0 - pc.tris / len(faces))
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = 1e-3
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V)
        occ = np.ones(len(V))
        for dist, w in ((0.025, 0.5), (0.06, 0.5)):
            dd = self.sdf(V + N * dist)
            occ *= np.clip(0.62 + 0.38 * dd / dist, 0.8, 1.0) ** w
        y = V[:, 1]
        grad = 0.92 + 0.08 * np.clip((y - y.min()) / max(y.max() - y.min(), 1e-6), 0, 1)
        c = np.clip(col * (occ * grad)[:, None], 0, 1)
        rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
        tm.visual = trimesh.visual.ColorVisuals(tm, vertex_colors=(rgba * 255).astype(np.uint8))
        return tm, N

    def mesh(self):
        out = [x for x in (self._piece_mesh(pc) for pc in self.pieces) if x is not None]
        tm = trimesh.util.concatenate([o[0] for o in out])
        normals = np.concatenate([o[1] for o in out])
        tm.apply_translation(-self.pivot)
        tm.vertex_normals = normals
        return tm


def at(x, y, z):
    return (C + np.array([x, y, z])).tolist()


def build(elite=False):
    glow_col = GOLD if elite else RED
    iris_col = GOLD if elite else RED_IRIS
    glow_rim = GOLD_RIM if elite else RED_RIM
    trim = GOLD if elite else ORANGE
    parts = []
    q = 0.85 if elite else 1.0  # l'élite a plus d'ornements : coque un peu plus allégée (budget 6000)

    # ---------------- corps (pivot au centre)
    body = Part("body", pivot=C, res=0.006)
    # coque basse (bol), légèrement en goutte : plus large en haut
    low = body.piece(HULL, tris=int(550 * q))
    low.add(ellipsoid(at(0, 0.0, 0), (0.2, 0.175, 0.195)))
    low.add(ellipsoid(at(0, -0.09, 0), (0.12, 0.1, 0.12)), k=0.06)
    # coque haute : calotte claire légèrement plus grande, coupée sous l'équateur -> ligne de panneau nette
    top = body.piece(HULL_L, tris=int(760 * q))
    top.add(ellipsoid(at(0, 0.005, 0), (0.206, 0.182, 0.201)))
    top.sub(rbox(at(0, -0.2, 0), (0.3, 0.2, 0.3), 0.01))
    # ceinture sombre à l'équateur
    belt = body.piece(METAL, tris=300)
    belt.add(cyl(at(0, -0.005, 0), 0.214, 0.016, 0.008))
    # orbite de l'œil : grand anneau sombre incliné vers le haut (60° : se lit du dessus comme de face)
    eye_dir = np.array([0.0, math.sin(math.radians(32)), math.cos(math.radians(32))])
    rx = 90 - 32
    ec = C + eye_dir * 0.168
    sock = body.piece(METAL, tris=int(700 * q), res=0.004)
    sock.add(torus((ec + eye_dir * 0.006).tolist(), 0.1, 0.022, rot=(rx, 0, 0)))
    # sourcil de visière orange au-dessus de l'œil (un peu froncé : air décidé)
    up = np.array([0, math.cos(math.radians(32)), -math.sin(math.radians(32))])

    def E(u, x, d):
        """Point dans le repère de l'œil : u vers le haut de l'œil, x latéral, d vers l'avant."""
        return (ec + up * u + np.array([x, 0, 0]) + eye_dir * d).tolist()

    brow = body.piece(trim, tris=300, res=0.004)
    for sx in (-1, 1):
        brow.add(capsule(E(0.108, sx * 0.01, 0.014), E(0.132, sx * 0.07, -0.006), 0.019, 0.014), k=0.014)
    # tuyère sous le corps
    noz = body.piece(METAL, tris=140)
    noz.add(cyl(at(0, -0.175, 0), 0.07, 0.03, 0.014))
    noz.add(cyl(at(0, -0.2, 0), 0.055, 0.02, 0.01), k=0.01)
    # dérive arrière : petit aileron vertical orange (indique le sens du drone vu du dessus)
    tail = body.piece(trim, tris=260 if elite else 200, res=0.004)
    tail.add(ellipsoid(at(0, 0.11, -0.165), (0.017, 0.062, 0.075), rot=(-45, 0, 0)))
    if elite:
        tail.add(ellipsoid(at(0, 0.16, -0.12), (0.015, 0.05, 0.07), rot=(-25, 0, 0)), k=0.02)
    # bornes d'antenne
    studs = body.piece(METAL, tris=80, res=0.004)
    for sx in (-1, 1):
        studs.add(sphere(at(sx * 0.1, 0.15, -0.03), 0.026))
    parts.append(body)

    # ---------------- œil (pivot au centre de la lentille : il pulse en place)
    # dôme lumineux, iris plus clair, pupille sombre, reflet blanc : se lit comme un regard, pas une lampe
    eye = Part("eye_glow", pivot=(ec + eye_dir * 0.02).tolist(), parent="body", res=0.004)
    lens = eye.piece(glow_rim, tris=520)
    lens.add(ellipsoid((ec + eye_dir * 0.012).tolist(), (0.088, 0.036, 0.088), rot=(rx, 0, 0)))
    lens.paint(cyl((ec + eye_dir * 0.05).tolist(), 0.064, 0.03, 0.0, rot=(rx, 0, 0)), iris_col)
    pupil = eye.piece(PUPIL_E if elite else PUPIL, tris=120, res=0.003)
    pupil.add(ellipsoid(E(0.0, 0.0, 0.044), (0.032, 0.01, 0.036), rot=(rx, 0, 0)))
    gl = eye.piece(WHITE, tris=80, res=0.003)
    gl.add(ellipsoid(E(0.04, 0.03, 0.044), (0.019, 0.008, 0.015), rot=(rx, 0, -30)))
    gl.add(sphere(E(-0.035, -0.036, 0.038), 0.008))
    parts.append(eye)

    # ---------------- antennes (pivot à la base ; balancent avec la vitesse)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        base = C + np.array([sx * 0.1, 0.15, -0.03])
        tip = C + np.array([sx * 0.16, 0.29, -0.07])
        ant = Part("antenna_" + side, pivot=base.tolist(), parent="body", res=0.004)
        ant.piece(METAL_L, tris=120).add(capsule(base.tolist(), tip.tolist(), 0.011, 0.009))
        ant.piece(trim, tris=160).add(sphere(tip.tolist(), 0.03))
        if elite:
            # petite corne dorée sur la boule
            ant.piece(trim, tris=80).add(capsule(tip.tolist(), (tip + np.array([sx * 0.03, 0.05, -0.02])).tolist(), 0.016, 0.004), k=0.01)
        parts.append(ant)

    # ---------------- ailerons latéraux (pivot à l'attache ; battent et se couchent en vitesse)
    for side, sx in (("r", -1.0), ("l", 1.0)):
        piv = C + np.array([sx * 0.19, 0.01, -0.02])
        fin = Part("fin_" + side, pivot=piv.tolist(), parent="body", res=0.005)
        f = fin.piece(trim, tris=200)
        f.add(ellipsoid(at(sx * 0.225, 0.03, -0.06), (0.022, 0.085, 0.07), rot=(-35, 0, sx * -28)))
        f.add(ellipsoid(at(sx * 0.2, 0.005, -0.02), (0.03, 0.045, 0.05)), k=0.02)
        if elite:
            f.add(ellipsoid(at(sx * 0.235, -0.04, -0.07), (0.018, 0.06, 0.05), rot=(-60, 0, sx * -50)), k=0.015)
        fin.piece(METAL, tris=80).add(sphere(at(sx * 0.197, 0.008, -0.02), 0.034))
        parts.append(fin)

    # ---------------- anneau de propulsion (flotte autour du bas du corps et tourne sur Y)
    ring = Part("ring", pivot=at(0, -0.085, 0), parent="body", res=0.005)
    # bague plate (se lit bien du dessus), arrondie sur les bords
    rg = ring.piece(METAL, tris=500)
    rg.add(cyl(at(0, -0.085, 0), 0.287, 0.012, 0.01))
    rg.sub(cyl(at(0, -0.085, 0), 0.245, 0.05, 0.0), k=0.008)
    pods = ring.piece(trim, tris=240 if not elite else 400)
    n_pods = 6 if elite else 3
    for i in range(n_pods):
        a = 2 * math.pi * i / n_pods + math.pi / 2
        pods.add(ellipsoid(at(0.266 * math.cos(a), -0.085, 0.266 * math.sin(a)), (0.036, 0.026, 0.036)))
    parts.append(ring)
    rglow = Part("ring_glow", pivot=at(0, -0.085, 0), parent="ring", res=0.004)
    rgl = rglow.piece(glow_col, tris=120 if not elite else 180)
    for i in range(n_pods):
        a = 2 * math.pi * i / n_pods + math.pi / 2
        rgl.add(sphere(at(0.266 * math.cos(a), -0.064, 0.266 * math.sin(a)), 0.016))
    parts.append(rglow)

    # ---------------- flamme de la tuyère
    jet = Part("jet_glow", pivot=at(0, -0.2, 0), parent="body", res=0.004)
    jet.piece(glow_col, tris=80).add(ellipsoid(at(0, -0.225, 0), (0.042, 0.02, 0.042)))
    parts.append(jet)

    return Character("drone_elite" if elite else "drone", parts)
