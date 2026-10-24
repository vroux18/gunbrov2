"""Patineur élite : même Patineur (mêmes pièces, mêmes pivots, même animation scripts/mobs/roller.gd), crête
et roues toujours roses, clous, coudières, liserés et écusson or, deux propulseurs dorés dans le dos qui
crachent du rose pendant l'élan (voir roller.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roller import build as _build  # noqa: E402


def build():
    return _build(elite=True)
