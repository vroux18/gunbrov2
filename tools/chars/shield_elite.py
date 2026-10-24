"""Rempart élite : même structure que le Rempart (tools/chars/shield.py), accents or, cadre doré à pointes,
cornes de casque, épaulières à pointes, plastron doré."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_shield_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "shield.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
