"""The Repetition sigil (manifest.lua M.repeat, effects/repeat.lua): the seal it is drawn in casts once, as any seal
does, and the sigil brings it again, as many times as it is drawn ('repeats='), each time from where the caster is
and aims at that moment - one sigil, twice in all; two sigils, three times. A Repetition in a small seal inside the
seal or linked to it works the same way on its own small seal, never on the seal around it, so repeats within
repeats stay bounded (a Workshop player's game froze when a repeat cast the whole seal again, 2026-10).

Run with python tests/test_repetition.py.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import world_runtime  # noqa: E402

COUNT_CASTS = '''
fire_casts, light_casts = 0, 0
local cast = cast_spell
function cast_spell( shooter, spell, ... )
    if spell.element == "fire" then fire_casts = fire_casts + 1 end
    if spell.element == "light" then light_casts = light_casts + 1 end
    return cast( shooter, spell, ... )
end
'''

CAST_FROM_BOOK = '''
GlobalsSetValue( "witch_notebook.active_spell", TEST_SPELL )
local book = EntityCreateNew( "book" )
EntityAddComponent2( book, "VariableStorageComponent", { name = "witch_notebook_next_cast", value_int = 0 } )
spellbook_use( book, PLAYER, EntityGetFirstComponent( PLAYER, "ControlsComponent" ), W.frame )
'''


class RepetitionSeal(unittest.TestCase):
    def casts(self, spell, frames=300):
        lua = world_runtime()
        lua.execute(COUNT_CASTS)
        lua.globals().TEST_SPELL = spell
        lua.execute(CAST_FROM_BOOK)
        lua.execute(f"simulate( {frames} )")
        return lua.eval("fire_casts"), lua.eval("light_casts")

    def test_one_sigil_brings_the_seal_once_more(self):
        # the seal's own cast, and the sigil's one repeat of it
        self.assertEqual((2, 0), self.casts("element=fire;form=column;manifest=repeat;repeats=1"))

    def test_two_sigils_bring_the_seal_twice_more(self):
        self.assertEqual((3, 0), self.casts("element=fire;form=column;manifest=repeat;repeats=2"))

    def test_a_page_drawn_before_the_count_was_kept_still_repeats_once(self):
        # an older page keeps no 'repeats': one sigil was drawn to make it, so it comes once more
        self.assertEqual((2, 0), self.casts("element=fire;form=column;manifest=repeat"))

    def test_repetition_linked_to_the_seal_repeats_the_seal_it_is_drawn_in(self):
        self.assertEqual((1, 3),
            self.casts("element=fire;form=column&link:element=light;form=burst;manifest=repeat;repeats=2"))

    def test_repetition_inside_the_seal_repeats_the_seal_it_is_drawn_in(self):
        self.assertEqual((1, 3),
            self.casts("element=fire;form=column&sub:element=light;form=burst;manifest=repeat;repeats=2"))

    def test_repeats_within_repeats_stay_bounded(self):
        spell = ("element=fire;form=column;manifest=repeat;repeats=2"
                 "&link:element=light;form=burst;manifest=repeat;repeats=2")
        self.assertEqual((3, 9), self.casts(spell))


if __name__ == "__main__":
    unittest.main()
