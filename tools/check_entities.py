"""Checks the mod's entity files against the game's component docs: unknown components and fields are
silently ignored by the game, so a typo just makes an effect not happen. The entities the mod builds at
init (carriers, effects) are checked by the offline tests (tests/run_tests.py).

Usage (from the mod folder):  python tools/check_entities.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noita_components import check_entity_xml, known_components  # noqa: E402

MOD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def main():
    if known_components() is None:
        print("component docs not found - nothing to check against")
        return 0
    problems = []
    count = 0
    for root, _, files in os.walk(os.path.join(MOD, "files")):
        for f in files:
            if f.endswith(".xml") and f != "materials.xml":
                path = os.path.join(root, f)
                text = open(path, encoding="utf-8").read()
                if "{{" in text:  # a template filled at init: the tests check the filled copies
                    continue
                count += 1
                problems += check_entity_xml(text, os.path.relpath(path, MOD) + ": ")
    for p in problems:
        print(p)
    print(f"{count} entity files, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
