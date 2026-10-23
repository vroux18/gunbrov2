# Passeurs

Twin-stick à vagues pour téléphone, en paysage. Les Passeurs, équipage du Relais (une station de transit entre les univers), traversent les mondes pour récupérer les dix éclats du Cœur volés par le Collectionneur. Chaque monde est un biome d'un genre différent ; le premier est **Nébuleuse 7**, un hangar de space opera.

- **APK Android** (dernière version de test) : https://github.com/vroux18/gunbrov2/releases/latest/download/Passeurs.apk
- **Version web** (iPhone : ouvrir dans Safari, Partager > Sur l'écran d'accueil) : https://vroux18.github.io/gunbrov2/

Godot 4.7 (GDScript, rendu Compatibility, tout dessiné en code, aucun asset). Compilé par GitHub Actions à chaque push (`.github/workflows/build.yml`) : robot testeur, export APK (clé de test fixe `tools/debug.keystore`, les versions s'installent l'une sur l'autre), export web sur GitHub Pages.

## La boucle (V0)

- Deux sticks flottants : gauche déplace, droit vise et tire. Droit lâché = tir automatique sur l'ennemi le plus proche. Clavier ZQSD / flèches sur la version web.
- Une partie = 10 salles dans le même biome. Chaque salle = 3 à 4 vagues ; salle 10 = boss (Le Portique) qui lâche l'éclat.
- **Énergie** : chaque ennemi tué remplit la barre. Pleine = choix d'un pouvoir parmi 3, tirés de l'**arsenal** de 8 pouvoirs que le joueur compose dans le Relais (16 au catalogue : tourelle, cadence, dégâts, vitesse, tir double, rebond, perforant, soin, bouclier, aimant, détonation, drone allié, ralenti, critique, portée, vampirisme). Les pouvoirs ne durent qu'une partie.
- **Loot** : un coffre en fin de salle, un objet par élite, un objet garanti meilleur au boss. Six emplacements (arme, module, tête, torse, jambes, gadget), quatre raretés. Le loot reste entre les parties et s'équipe dans la **Loge**.
- **Portails** : entre deux salles, trois portes (Combat, Élite, Trésor) changent la salle suivante.
- Mort = retour au Relais, le loot reste, les pouvoirs partent.

## Fichiers

| Fichier | Rôle |
|---|---|
| `scripts/main.gd` | Écrans (Relais, Loge, Arsenal), partie, overlays (pouvoir, objet, portails, pause, fin) |
| `scripts/arena.gd` | Carte, obstacles, caméra, vagues, projectiles, ramassages, coffre, tourelles, drones |
| `scripts/hero.gd` | Jo : stats (base × objets × pouvoirs), déplacement, tir, dessin |
| `scripts/enemy.gd` | Sentinelle, Garde, Colosse, Le Portique ; élites |
| `scripts/data.gd` | Catalogues : pouvoirs, objets, ennemis, plan des salles |
| `scripts/save.gd` | Profil (`user://passeurs.json`) : inventaire, équipement, arsenal, éclats, tickets |
| `scripts/joystick.gd`, `hud.gd`, `ui.gd`, `sfx.gd`, `bullet.gd` | Contrôles, HUD, fabrique d'UI, sons synthétisés, projectiles |
| `scripts/bot.gd` | Robot testeur du CI (`-- --autoplay`) |

## Lancer en local

```
godot --path .                                  # jeu
godot --headless --path . --quit-after 120      # vérification des scripts
godot --headless --path . --fixed-fps 30 --quit-after 9000 -- --autoplay   # robot testeur
```

## Hors V0

Fissures en plein combat (ennemis du monde voisin), le Collectionneur, mondes 2 à 10, trois autres Passeurs, patchwork visible du loot sur le héros, boutique, build iOS natif (attend le compte Apple Developer Ulixen).
