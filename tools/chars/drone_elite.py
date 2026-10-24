"""Sentinelle élite : même drone, accent lumineux or (#FFB347), crête dorsale, ailerons à double pointe,
cornes sur les antennes, anneau de propulsion à six nacelles (voir drone.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drone import build as _build  # noqa: E402


def build():
    return _build(elite=True)
