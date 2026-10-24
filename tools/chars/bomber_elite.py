"""Pétard élite : même structure que le Pétard (tools/chars/bomber.py), couronne de pointes dorées sur la boule,
poignées, moyeux et crête dorés, griffes dorées autour du voyant."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_bomber_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "bomber.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
