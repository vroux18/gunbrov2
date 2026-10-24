extends RefCounted
## Projectile simulé (dessiné en 3D par view3d.gd) : simple objet de données, déplacé et testé par l'arène.
## Aucun nœud par tir : même une salve en éventail ne crée que des objets légers.

var position := Vector2.ZERO
var vel := Vector2.ZERO
var dmg := 10.0
var life := 1.2
var hero_shot := true
var pierce := 0
var bounce := 0
var hop := 0  # rebonds vers l'ennemi suivant (Ricochet II)
var radius := 5.0
var color := Color("#3CF2D8")
var elem := 0  # bits : 1 feu, 2 givre, 4 foudre
var src := 0  # 0 Jo, 1 machine, 2 drone d'Essaim orageux (arc de foudre à chaque coup)
var crit := false
var look := 0  # rendu : 1 feu, 2 givre, 4 foudre (élément affiché par ce tir)
var hits: Array = []  # ennemis déjà traversés (perforant)
