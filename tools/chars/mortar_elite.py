"""Mortier élite : même Mortier (mêmes pièces, mêmes pivots, même animation scripts/mobs/mortar.gd), bouche
toujours vert citron, yeux et voyants or, plaques et garnitures dorées, couronne de pointes dorées autour de
la tourelle, cornes dorées sur la tête (voir mortar.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mortar import build as _build  # noqa: E402


def build():
    return _build(elite=True)
