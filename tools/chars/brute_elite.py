"""Colosse élite : même structure que le Colosse (tools/chars/brute.py), accents lumineux or,
cornes de casque, épaulières à pointes et plaques dorées."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_brute_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "brute.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
