"""Run the 11-element composite spell test on its own.

From the mod folder: python tests/complex_spells.py  (needs: pip install lupa)
"""
import run_tests


if __name__ == "__main__":
    raise SystemExit(0 if run_tests.test_complex_spells(run_tests.load_mod()) else 1)
