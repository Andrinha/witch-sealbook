"""Writes files/sheet_list.lua: the wiki's seals ranked into tiers for the sheets found in the world (sheets.lua,
sheets_create). The mod makes the same list at init and puts it over this file (ModTextFileSetContent); the file on disk
is the same list, for the scripts that spawn sheets should the virtual file not reach them.
Run it after changing the grimoire or the seals' tiers (SHEET_TIER); tests/run_tests.py checks the file is up to date.

Usage (from the mod folder):  python tools/make_sheet_list.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(MOD, "tests"))
import run_tests as R  # noqa: E402


def sheet_list_source():
    lua = R.load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    lua.execute("sheets_create()")
    return lua.globals().virtual["mods/witch_notebook/files/sheet_list.lua"]


def main():
    path = os.path.join(MOD, "files", "sheet_list.lua")
    open(path, "w", encoding="utf-8", newline="\n").write(sheet_list_source())
    print("written", path)


if __name__ == "__main__":
    main()
