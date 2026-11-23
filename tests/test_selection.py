"""The Sign of Selection: no seal of its own makes the flying book (grimoire.lua expansion_levitation alone);
drawn, it turns its seal on the witch herself - a field round the caster, whatever the signs vote.

python tests/test_selection.py
"""
import unittest

from harness import load_reader, load_cast
from run_tests import seal_tree


def seal(lua, sigils, signs=()):
    return lua.eval("compile_spell")(seal_tree(lua, sigils, list(signs)))


class Selection(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()

    def spell(self, sigils, signs=()):
        result = seal(self.lua, sigils, signs)
        if isinstance(result, tuple):
            self.assertIsNone(result[0], result[1])
        return result

    def test_alone_makes_no_book(self):
        """a lone Selection sigil: a field of light round the caster, not the flying book"""
        spell = self.spell(["selection"])
        self.assertEqual("light", spell["element"])
        self.assertEqual("field", spell["form"])
        self.assertIsNone(spell["manifest"])
        self.assertIsNone(spell["named"])

    def test_it_turns_the_element_on_the_witch(self):
        """whatever the signs vote, the spell works on the witch herself: a field round her"""
        spell = self.spell(["selection", "fire"])
        self.assertEqual("fire", spell["element"])
        self.assertEqual("field", spell["form"])
        self.assertIsNone(spell["manifest"])
        columns = self.spell(["selection", "fire"], [("column", False), ("column", False)])
        self.assertEqual("field", columns["form"])
        # signs of flight only work on what flies: on the field they are left out
        self.assertEqual({}, dict(columns["behaviors"]))

    def test_the_flying_book_needs_its_own_drawing(self):
        """the Seal of Expansion and Levitation's recipe alone casts the flying book, as its own page"""
        recipe = [("column", False)] * 8 + [("expansion", False)] * 4 + [("stability", False)] * 4
        spell = self.spell(["selection"], recipe)
        self.assertEqual("expansion_levitation", spell["named"])
        self.assertEqual("book", spell["manifest"])
        data = self.lua.eval("seal_page_data")(spell)
        self.assertIn("manifest=book", data)
        self.assertIn("named=expansion_levitation", data)

    def test_a_partial_seal_is_no_book(self):
        """selection with signs it is not known from: still on the witch, no flying book"""
        spell = self.spell(["selection"], [("stability", False), ("stability", False)])
        self.assertIsNone(spell["manifest"])
        self.assertEqual("field", spell["form"])


class Casts(unittest.TestCase):
    def test_alone_casts_a_field_not_a_book(self):
        lua = load_cast()
        G = lua.globals()
        G.shots = lua.table()
        book = G.make_book("element=light;form=field;precision=1;stability=1")
        controls, holder = G.make_controls(1, 0, 100, 0)
        made = G.spellbook_use(book, holder, controls, 100)
        files = [str(f) for f in list(G.shots.values()) + list((made or {}).values())]
        self.assertTrue(files)
        for f in files:
            self.assertNotIn("manifest:book", f)


if __name__ == "__main__":
    unittest.main(verbosity=2)
