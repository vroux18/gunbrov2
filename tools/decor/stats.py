"""Triangles par pièce d'un modèle de props.py (réglage des budgets) : python3 tools/decor/stats.py <nom>..."""
import sys

import props

for name in sys.argv[1:]:
    ch = props.catalog()[name]()
    tot = 0
    for part in ch.parts:
        if not hasattr(part, "pieces"):
            print(f"  {part.name:22s} {len(part.F):5d} (marquages)")
            tot += len(part.F)
            continue
        for pc in part.pieces:
            r = part._piece_mesh(pc)
            n = 0 if r is None else len(r[0]) // 3
            tot += n
            col = "#%02X%02X%02X" % tuple(int(c * 255) for c in pc.color)
            print(f"  {part.name:22s} {col}  cible {pc.tris:5d}  -> {n:5d}")
    print(f"{name} : {tot}")
