"""Construit les objets sculptés du quai nord : python3 tools/decor/bay_build.py ship wall rail ...
Chaque nom renvoie à tools/decor/bay_<nom>.py, dont build() rend un Prop ou une liste de Props.
Sortie : assets/decor/bay/<prop>.glb. Ensuite : godot --headless --path . --import"""
import importlib.util
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bay_lib  # noqa: E402  (installe sculpt dans le chemin)


def run(name):
    spec = importlib.util.spec_from_file_location("bay_" + name, os.path.join(HERE, "bay_" + name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    res = mod.build()
    total = 0
    for pr in (res if isinstance(res, (list, tuple)) else [res]):
        t0 = time.time()
        pr.export()
        print(f"  ({time.time() - t0:.1f} s)")


if __name__ == "__main__":
    for n in sys.argv[1:]:
        run(n)
