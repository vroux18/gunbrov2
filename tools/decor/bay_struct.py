"""Structure du quai nord : module de mur nord à baie vitrée, travée de garde-corps, bornes du sas, panneau.
  bay_wall : module de 3 m (x -1,5..1,5), face vers +Z (le quai), au sol z 0..0,5 : socle à grilles, gaines,
             poteau en I à manchon de danger et platine boulonnée, appui, meneau, poutre haute ; vitre à part
             (bay_wall_pane, transparente : la nébuleuse se voit au travers).
  bay_rail : travée de garde-corps de 1,5 m (x 0..1,5) : montant à platine, lisse jaune, sous-lisse.
             La plinthe à bandes est une bande texturée posée par hangar_bay.gd.
  bay_gate : borne du passage vers le sas (de part et d'autre de l'interruption du garde-corps).
  bay_sign : caisson de signalisation (le texte BAIE 07 est un Label3D posé devant)."""
from bay_lib import *


def wall():
    """Peu de triangles : le mur n'apparaît qu'en haut de l'écran (et au-delà des barres du HUD)."""
    p = BPart("wall", res=0.02, seed=5.0)
    p.stain((0, 0.0, 0.45), 0.6, 0.35, "#15171C")
    base = p.piece(NAVY, tris=90, wear=0.6)
    base.add(box((0, 0.2, 0.26), (1.5, 0.2, 0.2), 0.03))
    for x in (-0.75, 0.75):
        base.sub(box((x, 0.2, 0.47), (0.36, 0.09, 0.03), 0.01))
    for x in (-0.75, 0.75):
        for i in range(4):
            p.prim_box(NAVY_D, (x - 0.24 + i * 0.16, 0.2, 0.445), (0.025, 0.085, 0.012))
    p.prim_box(SLATE, (0, 0.44, 0.24), (1.5, 0.04, 0.15))
    p.prim_box(NAVY, (0, 1.86, 0.14), (0.045, 1.4, 0.05))
    p.prim_box(NAVY, (0, 3.34, 0.25), (1.5, 0.12, 0.22))
    # poteau en I
    p.prim_box(NAVY, (-1.5, 1.75, 0.46), (0.17, 1.75, 0.03))
    p.prim_box(NAVY, (-1.5, 1.75, 0.27), (0.035, 1.75, 0.17))
    p.prim_box(NAVY, (-1.5, 1.75, 0.08), (0.17, 1.75, 0.03))
    foot = p.piece(GUN, tris=70, res=0.014, wear=0.7)
    foot.add(box((-1.5, 0.04, 0.3), (0.27, 0.04, 0.24), 0.012))
    for bx in (-0.2, 0.2):
        for bz in (0.12, 0.48):
            foot.add(ycyl((-1.5 + bx, 0.09, bz), 0.025, 0.015, 0.006))
    # manchon de danger du poteau : jaune, bandes noires obliques
    p.prim_box(YELLOW, (-1.5, 0.62, 0.49), (0.18, 0.14, 0.012))
    for i in range(3):
        p.prim_box(BLACK, (-1.62 + i * 0.12, 0.62, 0.5), (0.025, 0.13, 0.006), R(0, 0, 40))
    # gaines le long du socle (raccord bout à bout d'un module à l'autre)
    p.prim_cyl(GUN_D, (-1.5, 0.5, 0.43), (1.5, 0.5, 0.43), 0.04, 8)
    p.prim_cyl(YELLOW, (-1.5, 0.6, 0.41), (1.5, 0.6, 0.41), 0.026, 6)
    for x in (-0.75, 0.75):
        p.prim_box(STEEL, (x, 0.55, 0.43), (0.03, 0.1, 0.055))
    return [Prop("bay_wall", [p])]  # la vitre (quad transparent) est posée par hangar_bay.gd


def rail():
    p = BPart("rail", res=0.012, seed=2.0)
    post = p.piece(GUN, tris=56, wear=0.7)
    post.add(box((0, 0.48, 0), (0.035, 0.46, 0.035), 0.015))
    post.add(ycyl((0, 0.02, 0), 0.075, 0.02, 0.008))
    p.piece(YELLOW, tris=32, wear=0.9).add(sphere((0, 0.93, 0), 0.046))
    p.prim_cyl(YELLOW, (0, 0.93, 0), (1.5, 0.93, 0), 0.032, 10)
    p.prim_cyl(GUN_D, (0, 0.52, 0), (1.5, 0.52, 0), 0.02, 6)
    return Prop("bay_rail", [p])


def gate():
    p = BPart("gate", res=0.012, seed=4.0)
    p.piece(GUN, tris=160, wear=0.6).add(ycyl((0, 0.32, 0), 0.12, 0.32, 0.04))
    p.piece(YELLOW, tris=80, wear=0.8).add(ycyl((0, 0.36, 0), 0.125, 0.06, 0.01))
    p.piece(GUN_D, tris=60, wear=0.3).add(ycyl((0, 0.67, 0), 0.1, 0.03, 0.02))
    g = BPart("gate_glow", res=0.01)
    g.piece(TEAL, tris=60).add(ycyl((0, 0.6, 0), 0.105, 0.03, 0.01))
    return Prop("bay_gate", [p, g])


def sign():
    p = BPart("sign", res=0.01, seed=6.0)
    p.prim_box(NAVY_D, (0, 0, 0), (0.62, 0.2, 0.03))
    for y in (-0.215, 0.215):
        p.prim_box(ORANGE_D, (0, y, 0.012), (0.66, 0.025, 0.035))
    for x in (-0.635, 0.635):
        p.prim_box(ORANGE_D, (x, 0, 0.012), (0.025, 0.19, 0.035))
    return Prop("bay_sign", [p])


def build():
    return wall() + [rail(), gate(), sign()]
