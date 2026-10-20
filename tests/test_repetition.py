"""The Repetition sigil in a small seal inside a seal or linked to it (effects/repeat.lua): the seal is cast again three
times, without that Repetition - repeated with it, each cast repeated the seal three times more and the game froze (a
Workshop player, 2026-10).

Run with python tests/test_repetition.py.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import world_runtime  # noqa: E402

COUNT_CASTS = '''
fire_casts = 0
local cast = cast_spell
function cast_spell( shooter, spell, ... )
    if spell.element == "fire" then fire_casts = fire_casts + 1 end
    return cast( shooter, spell, ... )
end
'''

CAST_FROM_BOOK = '''
GlobalsSetValue( "witch_notebook.active_spell", TEST_SPELL )
local book = EntityCreateNew( "book" )
EntityAddComponent2( book, "VariableStorageComponent", { name = "witch_notebook_next_cast", value_int = 0 } )
spellbook_use( book, PLAYER, EntityGetFirstComponent( PLAYER, "ControlsComponent" ), W.frame )
'''


class RepetitionInASmallSeal(unittest.TestCase):
    def casts(self, spell, frames=300):
        lua = world_runtime()
        lua.execute(COUNT_CASTS)
        lua.globals().TEST_SPELL = spell
        lua.execute(CAST_FROM_BOOK)
        lua.execute(f"simulate( {frames} )")
        return lua.eval("fire_casts")

    def test_linked_repetition_repeats_the_seal_three_times(self):
        self.assertEqual(4, self.casts("element=fire;form=column&link:element=light;form=burst;manifest=repeat"))

    def test_repetition_inside_repeats_the_seal_three_times(self):
        self.assertEqual(4, self.casts("element=fire;form=column&sub:element=light;form=burst;manifest=repeat"))

    def test_two_repetitions_still_end(self):
        spell = "element=fire;form=column&link:element=light;form=burst;manifest=repeat&link:element=light;form=burst;manifest=repeat"
        self.assertLessEqual(self.casts(spell), 7)


if __name__ == "__main__":
    unittest.main()
