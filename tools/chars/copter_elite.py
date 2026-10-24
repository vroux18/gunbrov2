"""Gyro élite : même structure que le Gyro (tools/chars/copter.py), casquette de capitaine à insigne or,
écusson, liserés, canon et antennes dorés."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("char_copter_base", os.path.join(os.path.dirname(os.path.abspath(__file__)), "copter.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def build():
    return _base.build(elite=True)
