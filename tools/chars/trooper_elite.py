"""Garde d'élite du Portique : même garde que tools/chars/trooper.py (mêmes pièces, mêmes pivots, même
animation scripts/mobs/trooper.gd), accents lumineux or au lieu du rouge, épaulières et garnitures dorées,
plumet pourpre sur le casque et cape courte dans le dos."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_trooper_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "trooper.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
