"""Patineur (code « roller ») : petit robot punk du gang des Néons, monté sur rollers.
Silhouette ramassée de gamin des rues : grosse tête casquée à crête iroquoise rose néon (lisible du dessus),
face-écran sombre à deux yeux roses, écouteurs, blouson sombre clouté à col hérissé, écusson rose dans le
dos, épaulières claires, coudières et grosses genouillères roses, short, rollers montants à trois roues roses.
Regarde vers +Z ; sa droite est en -X. Hauteur ~0,95 crête comprise, largeur ~0,55 bras compris
(Jo : 1,10).

Parts (pivots) : pelvis (racine, hanches) > torso (taille) > head (cou) > head_glow (yeux, bouche),
crest_glow (crête) ; torso > chest_glow (écusson dorsal, voyant), arm_r/arm_l (épaule) > fore_r/fore_l
(coude, avec la main) ; pelvis > leg_r/leg_l (hanche) > shin_r/shin_l (genou) > skate_r/skate_l
(cheville, le roller) > wheels_glow_r/l (roues). trail_glow (racine à part, au sol) et trail_up_glow (dans le dos, enfant de torso) : traînée de vitesse,
masquée hors élan.
Variante élite (build(elite=True), tools/chars/roller_elite.py) : crête et roues toujours roses
(signature), clous, coudières, liserés et écusson or, et deux propulseurs dorés dans le dos (jets_glow).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trimesh  # noqa: E402
from skimage import measure  # noqa: E402

from sculpt import *  # noqa: E402,F403
from sculpt import Part as _Part, Piece as _Piece  # noqa: E402
from sniper import union, inter, grow, side, slab, add, shell  # noqa: E402

SHELL = "#EFEAF6"    # coque claire légèrement lilas (casque, épaulières, protège-tibias, rollers)
SHELL_M = "#BDB3D2"
DARK = "#2C2442"     # blouson et sous-couche violet nuit
DARK_D = "#1A1529"
JOINT = "#463C68"
FACE = "#120D1F"     # écran du visage
PINK_P = "#EE3A9E"   # peinture rose (genouillères, liserés) : même famille que la lueur, sans luire
PINK_D = "#A9246F"
PINK = "#FF3CAC"     # lueur rose néon (énergie ~1)
PINK_HOT = "#FF7AC6"
STUD = "#D9DDEA"
WHITE = "#FFFFFF"
GOLD = "#FFB347"
GOLD_P = "#E8A53A"
GOLD_D = "#A8661E"

# repères partagés avec scripts/mobs/roller.gd
HIP_Y = 0.4
HIP_X = 0.072
KNEE_Y = 0.262
ANKLE_Y = 0.13
WAIST = (0.0, 0.45, 0.0)
NECK = (0.0, 0.598, -0.005)
HC = (0.0, 0.732, 0.008)  # centre de la tête
HR = 0.152  # rayon de la tête
SH = (0.128, 0.565, -0.005)  # épaule gauche (+X)
EL = (0.19, 0.478, -0.018)
HAND = (0.212, 0.392, 0.012)
WHEEL_R = 0.033
TRAIL_UP = (0.0, 0.56, -0.07)  # départ de la traînée haute (entre les épaules, dans le dos)
TRI = 0.5


class Part(_Part):
    """Normales exactes du champ de distance (lisses malgré l'allègement), miettes retirées, lumières sans
    occlusion ni dégradé (comme tools/chars/shield.py)."""

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
        raw = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        comps = raw.split(only_watertight=False)
        if len(comps) > 1:
            keep = [cm for cm in comps if len(cm.faces) >= 40]
            raw = trimesh.util.concatenate(keep if keep else comps)
            verts, faces = np.asarray(raw.vertices), np.asarray(raw.faces)
        if len(faces) > pc.tris:
            verts, faces = simplify_to(verts, faces, pc.tris)
        tm = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
        trimesh.repair.fix_normals(tm)
        V = np.asarray(tm.vertices, dtype=np.float64)
        e = 1e-3
        N = np.stack([pc.sdf(V + np.eye(3)[i] * e) - pc.sdf(V - np.eye(3)[i] * e) for i in range(3)], axis=1)
        N /= np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]
        col = pc.colors(V)
        glow = "_glow" in self.name
        occ = np.ones(len(V))
        grad = np.ones(len(V))
        if not glow:
            for dist, w in ((0.02, 0.5), (0.05, 0.5)):
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

    def fade_piece(self, color, z0, z1, tris=200, res=None):
        """Volume dont la couleur s'éteint de z0 (pleine) à z1 (noire) : rendu en mélange additif, le noir
        est transparent (traînées)."""
        pc = FadePiece(color, z0, z1, tris, res)
        self.pieces.append(pc)
        return pc


class FadePiece(_Piece):
    def __init__(self, color, z0, z1, tris=200, res=None):
        super().__init__(color, tris, res)
        self.z0 = z0
        self.z1 = z1

    def colors(self, P):
        col = super().colors(P)
        k = np.clip((P[:, 2] - self.z1) / (self.z0 - self.z1), 0.0, 1.0) ** 1.4
        return col * k[:, None]


def scaled(s, c, k):
    """Forme `s` étirée de k = (kx, ky, kz) autour du point c (distance corrigée, approchée)."""
    c = np.asarray(c, dtype=np.float64)
    k = np.asarray(k, dtype=np.float64)
    m = float(k.min())
    lo = c + (s.lo - c) * k
    hi = c + (s.hi - c) * k
    return Shape(lambda P: s((P - c) / k + c) * m, np.minimum(lo, hi), np.maximum(lo, hi))


def fin(a, b, r1, r2, flat):
    """Pointe aplatie latéralement (épaisseur x réduite de `flat`) de a (rayon r1) à b (rayon r2)."""
    cap = capsule(a, b, r1, r2)
    mid = (np.asarray(a) + np.asarray(b)) * 0.5
    return scaled(cap, mid, (flat, 1.0, 1.0))


def on_head(theta, out=0.0, x=0.0):
    """Point sur la sphère de la tête, dans le plan médian : theta = angle depuis le sommet (+ vers l'avant)."""
    r = HR + out
    return (x, HC[1] + r * math.cos(theta), HC[2] + r * math.sin(theta))


def build(elite=False):
    q = 0.9 if elite else 1.0

    def T(n):
        return max(50, int(n * q * TRI))

    trim = GOLD_P if elite else PINK_P  # liserés, coudières
    stud = GOLD_P if elite else STUD
    glow2 = GOLD if elite else PINK  # écusson dorsal
    parts = []

    # ================================================================== bassin (racine, pivot aux hanches)
    pelvis = Part("pelvis", pivot=(0, HIP_Y, 0), res=0.0045)
    sh_sh = union([
        ellipsoid((0, 0.415, -0.004), (0.118, 0.07, 0.088)),
        ellipsoid((0, 0.455, 0.0), (0.098, 0.05, 0.078)),
    ], k=0.03)
    pelvis.piece(DARK, tris=T(300)).add(sh_sh)  # short
    belt = pelvis.piece(DARK_D, tris=T(160))
    belt.add(cyl((0, 0.46, 0), 0.104, 0.016, 0.008))
    pelvis.piece(stud, tris=T(110), res=0.0035).add(rbox((0, 0.46, 0.1), (0.024, 0.017, 0.012), 0.007))  # boucle
    parts.append(pelvis)

    # ================================================================== buste (pivot à la taille)
    torso = Part("torso", pivot=WAIST, parent="pelvis", res=0.0045)
    jacket_sh = union([
        ellipsoid((0, 0.525, -0.006), (0.122, 0.088, 0.088)),
        ellipsoid((0, 0.565, -0.01), (0.135, 0.05, 0.088)),
        capsule((0, 0.46, 0), (0, 0.5, 0), 0.085),
    ], k=0.035)
    jk = torso.piece(DARK, tris=T(420))
    jk.add(jacket_sh)
    # devant : plastron clair entre les pans ouverts du blouson
    plate = torso.piece(SHELL, tris=T(260))
    plate.add(inter(grow(jacket_sh, 0.006), ellipsoid((0, 0.515, 0.09), (0.05, 0.08, 0.06))))
    # col hérissé : anneau clouté et pointes vers l'arrière
    collar = torso.piece(DARK_D, tris=T(220))
    collar.add(torus((0, 0.585, -0.008), 0.072, 0.022))
    spk = torso.piece(stud, tris=T(360), res=0.0035)
    for i in range(5):
        a = math.radians(-60 + i * 30)  # autour de la nuque (0 = plein arrière)
        cx, cz = 0.072 * math.sin(a), -0.008 - 0.072 * math.cos(a)
        spk.add(capsule((cx, 0.592, cz), (cx * 1.55, 0.618, cz * 1.5 - 0.012), 0.012, 0.003))
    # épaulières claires cloutées
    pads = torso.piece(SHELL, tris=T(320))
    studs = torso.piece(stud, tris=T(200), res=0.0032)
    for sx in (-1, 1):
        pad_sh = ellipsoid((sx * 0.13, 0.575, -0.008), (0.058, 0.04, 0.062), rot=(0, 0, -sx * 24))
        pads.add(pad_sh)
        for dz in (-0.03, 0.0, 0.03):
            studs.add(sphere((sx * 0.148, 0.605, -0.008 + dz), 0.0085))
    if elite:
        # deux fusées dorées dans le dos, inclinées vers l'extérieur, nez au-dessus des épaules
        jets = torso.piece(GOLD_P, tris=T(420))
        for sx in (-1, 1):
            jets.add(capsule((sx * 0.06, 0.64, -0.135), (sx * 0.08, 0.47, -0.14), 0.04, 0.042))
            jets.add(capsule((sx * 0.055, 0.66, -0.135), (sx * 0.05, 0.73, -0.13), 0.036, 0.008), k=0.02)  # nez
            jets.add(fin((sx * 0.12, 0.5, -0.14), (sx * 0.15, 0.45, -0.145), 0.022, 0.006, 0.4), k=0.01)  # aileron
        jets.add(rbox((0, 0.55, -0.1), (0.07, 0.045, 0.025), 0.015), k=0.02)  # harnais
        noz = torso.piece(DARK_D, tris=T(180))
        for sx in (-1, 1):
            noz.add(cyl((sx * 0.082, 0.455, -0.14), 0.036, 0.02, 0.008, rot=(0, 0, -sx * 7)))
            noz.add(torus((sx * 0.063, 0.6, -0.137), 0.04, 0.007), k=0.0)  # bague
    parts.append(torso)

    cg = Part("chest_glow", pivot=WAIST, parent="torso", res=0.003)
    patch = cg.piece(glow2, tris=T(150))
    if elite:
        # voyant doré entre les propulseurs (l'écusson est caché par eux)
        patch.add(rbox((0, 0.54, -0.11), (0.03, 0.012, 0.006), 0.005))
    else:
        # écusson dorsal : éclair abstrait (lisible de dos et du dessus)
        patch.add(inter(grow(jacket_sh, 0.004), rbox((0.012, 0.545, -0.1), (0.014, 0.034, 0.05), 0.004, rot=(0, 0, -22))))
        patch.add(inter(grow(jacket_sh, 0.004), rbox((-0.012, 0.505, -0.1), (0.014, 0.034, 0.05), 0.004, rot=(0, 0, -22))))
    cg.piece(PINK, tris=T(60)).add(sphere((0, 0.548, 0.098), 0.011))  # voyant de poitrine
    parts.append(cg)

    if elite:
        jg = Part("jets_glow", pivot=(0, 0.445, -0.14), parent="torso", res=0.003)
        fl = jg.piece(PINK_HOT, tris=T(180))
        for sx in (-1, 1):
            fl.add(capsule((sx * 0.083, 0.44, -0.14), (sx * 0.088, 0.37, -0.14), 0.027, 0.006))
        parts.append(jg)

    # ================================================================== tête (pivot au cou)
    head = Part("head", pivot=NECK, parent="torso", res=0.0038)
    head_sh = union([
        ellipsoid(HC, (HR * 1.02, HR * 0.97, HR)),
        ellipsoid(add(HC, (0, -0.06, 0.02)), (HR * 0.86, HR * 0.6, HR * 0.86)),
    ], k=0.04)
    face_box = rbox(add(HC, (0, -0.022, HR * 0.8)), (HR * 0.78, HR * 0.5, HR * 0.5), 0.05)
    helm = head.piece(SHELL, tris=T(620))
    helm.add(head_sh)
    helm.sub(face_box, k=0.012)
    helm.add(cyl((0, 0.6, -0.005), 0.046, 0.025, 0.01), k=0.01)  # cou
    # bande rose sur les côtés du casque, sous la crête
    band = head.piece(trim, tris=T(240), res=0.0032)
    band.add(inter(grow(head_sh, 0.004), slab(add(HC, (0, 0.012, 0)), (0, 1, -0.35), 0.012)))
    band.sub(face_box, k=0.01)
    band.sub(side(HC, (0, 0, 1)), k=0.0)  # seulement sur l'arrière
    # visage : écran sombre en retrait dans l'ouverture du casque
    face = head.piece(FACE, tris=T(260))
    face.add(inter(grow(head_sh, -0.008), grow(face_box, 0.004)))
    # écouteurs (punk : casque audio)
    ears = head.piece(DARK, tris=T(240))
    ring = head.piece(trim, tris=T(160), res=0.003)
    for sx in (-1, 1):
        ec = add(HC, (sx * HR * 0.98, -0.012, -0.004))
        ears.add(cyl(ec, 0.052, 0.022, 0.012, rot=(0, 0, 90)))
        ring.add(torus(add(ec, (sx * 0.02, 0, 0)), 0.034, 0.008, rot=(0, 0, 90)))
    if elite:
        # liseré doré au bord de l'ouverture du visage
        rim = head.piece(GOLD_P, tris=T(220), res=0.003)
        rim.add(inter(shell(face_box, 0.012, 0.002), grow(head_sh, 0.006)))
    parts.append(head)

    hg = Part("head_glow", pivot=NECK, parent="head", res=0.0026)
    eyes = hg.piece(PINK, tris=T(200))
    fz = HC[2] + HR * 0.86
    for sx in (-1, 1):
        ec = (sx * 0.048, HC[1] - 0.004, fz)
        eyes.add(ellipsoid(ec, (0.028, 0.038, 0.014), rot=(-14, 0, sx * 8)))
    # sourire en arc (moitié basse d'un tore)
    smile = torus((0, HC[1] - 0.05, fz - 0.004), 0.022, 0.0055, rot=(90, 0, 0))
    eyes.add(inter(smile, side((0, HC[1] - 0.05, 0), (0, -1, 0))))
    glint = hg.piece(WHITE, tris=T(60))
    for sx in (-1, 1):
        glint.add(sphere((sx * 0.048 + 0.008, HC[1] + 0.013, fz + 0.01), 0.0065))
    parts.append(hg)

    # crête iroquoise : pointes aplaties du front à la nuque, plus hautes au milieu
    crg = Part("crest_glow", pivot=on_head(0.0), parent="head", res=0.0028)
    crest = crg.piece(PINK, tris=T(520))
    spikes = [(0.78, 0.06, 0.028), (0.4, 0.095, 0.032), (0.02, 0.112, 0.034), (-0.38, 0.105, 0.033),
              (-0.78, 0.085, 0.03), (-1.16, 0.06, 0.026)]
    for th, ln, r in spikes:
        base = on_head(th, -0.02)
        tip = on_head(th - 0.18, ln)  # chaque pointe est couchée vers l'arrière
        crest.add(fin(base, tip, r * 1.1, 0.005, 0.72), k=0.018)
    crest.add(inter(scaled(torus(HC, HR * 1.0, 0.022, rot=(0, 0, 90)), HC, (0.45, 1, 1)),
                    side(add(HC, (0, 0.01, 0)), (0, 1, -0.45))), k=0.015)  # racine continue, du front à la nuque
    crest.paint(sphere(add(HC, (0, 0, 0)), HR + 0.05), PINK_D)  # racine plus sombre
    parts.append(crg)

    # ================================================================== bras (épaule) + avant-bras (coude)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        sh_p = (sx * SH[0], SH[1], SH[2])
        el = (sx * EL[0], EL[1], EL[2])
        hd = (sx * HAND[0], HAND[1], HAND[2])
        arm = Part("arm_" + nm, pivot=sh_p, parent="torso", res=0.004)
        arm.piece(DARK, tris=T(170)).add(capsule(sh_p, el, 0.038, 0.032))  # manche du blouson
        arm.piece(DARK_D, tris=T(90)).add(cyl(add(el, (-sx * 0.008, 0.03, 0.002)), 0.035, 0.008, 0.004, rot=(0, 0, sx * 32)))
        parts.append(arm)
        fore = Part("fore_" + nm, pivot=el, parent="arm_" + nm, res=0.004)
        fore.piece(JOINT, tris=T(70)).add(sphere(el, 0.03))
        fa = fore.piece(SHELL, tris=T(180))
        fa.add(capsule(add(el, (0, -0.02, 0.0)), add(hd, (0, 0.035, 0)), 0.03, 0.035))
        # coudière ronde
        fore.piece(trim, tris=T(150)).add(ellipsoid(add(el, (sx * 0.006, -0.002, -0.022)), (0.034, 0.036, 0.026)))
        # gant : moufle sombre et pouce
        glove = fore.piece(DARK_D, tris=T(200))
        glove.add(ellipsoid(add(hd, (0, -0.012, 0.004)), (0.036, 0.04, 0.034)))
        glove.add(capsule(add(hd, (-sx * 0.022, 0.0, 0.02)), add(hd, (-sx * 0.03, -0.022, 0.03)), 0.012), k=0.01)
        fore.piece(trim, tris=T(70)).add(cyl(add(hd, (0, 0.03, 0)), 0.036, 0.008, 0.004))  # poignet
        parts.append(fore)

    # ================================================================== jambes (hanche) + tibias (genou, roller)
    for nm, sx in (("r", -1.0), ("l", 1.0)):
        hx = sx * HIP_X
        hip = (hx, HIP_Y, 0.0)
        kn = (sx * (HIP_X + 0.006), KNEE_Y, 0.004)
        an = (sx * (HIP_X + 0.008), ANKLE_Y, -0.006)
        leg = Part("leg_" + nm, pivot=hip, parent="pelvis", res=0.004)
        leg.piece(DARK, tris=T(160)).add(capsule(hip, add(hip, (sx * 0.006, -0.07, 0.002)), 0.058, 0.052))  # jambe du short
        leg.piece(JOINT, tris=T(110)).add(capsule(add(hip, (0, -0.05, 0)), kn, 0.034, 0.03))
        leg.piece(trim, tris=T(80)).add(cyl(add(hip, (sx * 0.006, -0.085, 0.002)), 0.053, 0.008, 0.004))  # ourlet
        parts.append(leg)
        shin = Part("shin_" + nm, pivot=kn, parent="leg_" + nm, res=0.004)
        shin.piece(JOINT, tris=T(110)).add(capsule(kn, add(an, (0, 0.03, 0)), 0.03, 0.028))
        # genouillère : grosse coque rose (signature, vue de face et de dessus)
        kp = shin.piece(PINK_P, tris=T(220))
        kp_sh = ellipsoid(add(kn, (0, 0.008, 0.03)), (0.046, 0.05, 0.034), rot=(-10, 0, 0))
        kp.add(kp_sh)
        kp.paint(slab(add(kn, (0, 0.008, 0)), (0, 1, 0.2), 0.006), PINK_D)
        shin.piece(DARK_D, tris=T(80)).add(cyl(add(kn, (0, -0.002, -0.004)), 0.036, 0.012, 0.006))  # sangle
        parts.append(shin)
        # roller montant (pivot à la cheville : reste à plat) : botte claire, languette rose, platine sombre
        sk = Part("skate_" + nm, pivot=an, parent="shin_" + nm, res=0.004)
        boot_sh = union([
            rbox((an[0], 0.085, 0.02), (0.044, 0.04, 0.078), 0.036, rot=(-3, 0, 0)),
            capsule((an[0], 0.09, -0.012), (an[0], 0.175, -0.016), 0.044, 0.04),
        ], k=0.03)
        boot = sk.piece(SHELL, tris=T(380))
        boot.add(boot_sh)
        boot.paint(slab((an[0], 0.055, 0), (0, 1, 0), 0.008), SHELL_M)  # semelle
        tongue = sk.piece(trim, tris=T(150), res=0.0032)
        tongue.add(inter(grow(boot_sh, 0.005), rbox((an[0], 0.13, 0.04), (0.024, 0.06, 0.05), 0.012)))
        sk.piece(DARK_D, tris=T(90)).add(torus((an[0], 0.2, -0.016), 0.038, 0.009))  # haut de tige
        frame = sk.piece(DARK, tris=T(220))
        frame.add(rbox((an[0], 0.048, 0.02), (0.014, 0.018, 0.096), 0.01))
        for wz in (-0.052, 0.02, 0.092):
            frame.add(cyl((an[0], WHEEL_R, wz), 0.01, 0.022, 0.004, rot=(0, 0, 90)))  # moyeux
        frame.add(rbox((an[0], 0.035, 0.13), (0.02, 0.022, 0.012), 0.01, rot=(20, 0, 0)), k=0.01)  # butée avant
        parts.append(sk)
        wg = Part("wheels_glow_" + nm, pivot=an, parent="skate_" + nm, res=0.0028)
        wh = wg.piece(PINK, tris=T(240))
        for wz in (-0.052, 0.02, 0.092):
            wh.add(cyl((an[0], WHEEL_R, wz), WHEEL_R, 0.0125, 0.008, rot=(0, 0, 90)))
        wh.sub(cyl((an[0], WHEEL_R, -0.052), 0.012, 0.03, 0.002, rot=(0, 0, 90)))
        wh.sub(cyl((an[0], WHEEL_R, 0.02), 0.012, 0.03, 0.002, rot=(0, 0, 90)))
        wh.sub(cyl((an[0], WHEEL_R, 0.092), 0.012, 0.03, 0.002, rot=(0, 0, 90)))
        parts.append(wg)

    # ================================================================== traînée de vitesse (au sol, derrière)
    tr = Part("trail_glow", pivot=(0, 0, 0), res=0.006)
    streak = tr.fade_piece(PINK, -0.06, -0.62, tris=T(160))
    for sx in (-1, 1):
        streak.add(capsule((sx * 0.08, 0.03, -0.08), (sx * 0.085, 0.03, -0.6), 0.024, 0.006))
    parts.append(tr)
    # traînée haute : part des épaules (le script la garde à l'horizontale quel que soit le buste)
    tu = Part("trail_up_glow", pivot=TRAIL_UP, parent="torso", res=0.006)
    su = tu.fade_piece(PINK, TRAIL_UP[2] - 0.02, TRAIL_UP[2] - 0.5, tris=T(120))
    for sx in (-1, 1):
        su.add(capsule((sx * 0.15, TRAIL_UP[1], TRAIL_UP[2] - 0.03), (sx * 0.17, TRAIL_UP[1] - 0.02, TRAIL_UP[2] - 0.48), 0.016, 0.004))
    su.add(capsule((0, TRAIL_UP[1] + 0.22, TRAIL_UP[2] - 0.08), (0, TRAIL_UP[1] + 0.18, TRAIL_UP[2] - 0.5), 0.02, 0.004))
    parts.append(tu)
    return Character("roller_elite" if elite else "roller", parts)
