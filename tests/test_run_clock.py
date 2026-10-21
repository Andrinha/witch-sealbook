"""The run's clock (run_clock.lua): frames since the run began, going on across Save & Quit - GameGetFrameNum() starts
from 0 again with every session. What the world keeps of when is counted by it: after a game is loaded an effect ends
when it was to, the books cast once the quill of water is done, the Knights Moralis come again, the book's recharge bar
shows. Times kept by an older version (frame numbers far ahead of the clock) are let go.

Run with python tests/test_run_clock.py.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import world_runtime  # noqa: E402

BOOK = r'''
GlobalsSetValue( "witch_notebook.active_spell", "element=fire;form=column" )
BOOK = EntityCreateNew( "book" )
EntityAddComponent2( BOOK, "VariableStorageComponent", { name = "witch_notebook_next_cast", value_int = 0 } )
function click() return spellbook_use( BOOK, PLAYER, EntityGetFirstComponent( PLAYER, "ControlsComponent" ), run_frame() ) end
'''


def world():
    lua = world_runtime()
    lua.execute("run_clock_update()")
    return lua, lua.globals()


def step(lua, n):
    """n frames as the game runs them: the world, then the clock looked after (init.lua: before the next one)"""
    lua.execute(f"for _ = 1, {n} do simulate( 1 ) run_clock_update() end")


def reload(lua, frame=3):
    """Save & Quit, then Continue: the world and the run's globals as they were saved, the frame count from the start"""
    lua.execute(f"W.frame = {frame} run_clock_update()")


def skip(lua, n):
    """n frames go by with nothing in the world to update"""
    lua.execute(f"W.frame = W.frame + {n} run_clock_update()")


class RunClock(unittest.TestCase):
    def test_the_clock_goes_on(self):
        lua, G = world()
        self.assertEqual(G.W.frame, G.run_frame())
        step(lua, 300)
        before = G.run_frame()
        reload(lua)
        self.assertEqual(before + 1, G.run_frame())
        step(lua, 50)
        self.assertEqual(before + 51, G.run_frame())
        reload(lua, 0)  # saved and loaded again, sooner than the last session began
        self.assertEqual(before + 52, G.run_frame())
        skip(lua, 10)  # the same session: the frame count goes on, so does the clock
        self.assertEqual(before + 62, G.run_frame())

    def test_an_effect_ends_when_it_was_to(self):
        lua, G = world()
        e = lua.eval('effect_spawn( "zone", "boil", 40, GROUND - 8, { frames = 300, r = 20, owner = PLAYER } )')
        step(lua, 100)
        reload(lua)  # after an hour of play the frame count would have been far ahead of a new session's
        step(lua, 190)
        self.assertTrue(G.EntityGetIsAlive(e))
        step(lua, 20)
        self.assertFalse(G.EntityGetIsAlive(e))

    def test_an_effect_from_an_older_version(self):
        # born by the frame count of a session long gone: its time starts again, it doesn't last that session's length
        lua, G = world()
        e = lua.eval('effect_spawn( "zone", "boil", 40, GROUND - 8, { frames = 120, r = 20, owner = PLAYER } )')
        lua.execute(f"effect_set( {e}, 'born', run_frame() + 200000 )")
        step(lua, 125)
        self.assertFalse(G.EntityGetIsAlive(e))

    def test_the_books_cast_after_the_quill(self):
        # saved while the quill of water drew: loaded, the books cast again once its time is over
        lua, G = world()
        lua.execute(BOOK)
        lua.execute('GlobalsSetValue( "witch_notebook.busy_until", tostring( run_frame() + 600 ) )')
        step(lua, 100)
        reload(lua)
        skip(lua, 480)
        self.assertIsNone(G.click())
        skip(lua, 30)
        self.assertIsNotNone(G.click())
        # a quill's while counted by an older version, far ahead: over
        lua.execute('GlobalsSetValue( "witch_notebook.busy_until", tostring( run_frame() + 300000 ) )')
        skip(lua, 200)
        self.assertIsNotNone(G.click())

    def test_the_knights_come_again(self):
        lua, G = world()
        cast = 'cast_spell( PLAYER, parse_spell_data( "element=fire;form=column;forbidden=true" ), 0, GROUND - 8, 1, 0, 60, GROUND - 8, run_frame(), nil )'
        knights = 'local n = 0 for _, e in pairs( W.entities ) do if e.alive and e.name == "witch_knights_come" then n = n + 1 end end return n'
        lua.execute(cast)
        self.assertEqual(1, lua.execute(knights))
        skip(lua, 3000)
        reload(lua)
        skip(lua, 4000)
        lua.execute(cast)  # 7000 frames since: not yet
        self.assertEqual(1, lua.execute(knights))
        skip(lua, 300)
        lua.execute(cast)
        self.assertEqual(2, lua.execute(knights))
        # their next coming set by an older version, far ahead: they come
        lua.execute('GlobalsSetValue( "witch_notebook.knights_next", tostring( run_frame() + 500000 ) )')
        lua.execute(cast)
        self.assertEqual(3, lua.execute(knights))


if __name__ == "__main__":
    unittest.main()
