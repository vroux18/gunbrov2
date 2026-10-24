"""Pirate élite : même Pirate (mêmes pièces, mêmes pivots, même animation scripts/mobs/hacker.gd), lunettes et
hologramme toujours vert acide, passepoil de capuche, montures, tirette et garnitures or, parabole dorée sur
le sac à dos (voir hacker.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacker import build as _build  # noqa: E402


def build():
    return _build(elite=True)
