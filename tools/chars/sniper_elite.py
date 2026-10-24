"""Vigie élite : même Vigie (mêmes pièces, mêmes pivots, même animation scripts/mobs/sniper.gd), lentille
toujours violette, accents lumineux or (lignes, oculaire, antenne), garnitures dorées, crête dorée sur le
casque, pointes dorées aux épaulières, ourlet doré à la capeline (voir sniper.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sniper import build as _build  # noqa: E402


def build():
    return _build(elite=True)
