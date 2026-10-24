"""Videur élite : même structure que le Videur (tools/chars/bouncer.py), crête punk dorée, clous dorés sur
les épaules, monture des lunettes, boutons, médaillon et manchettes or."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_bouncer_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "bouncer.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
