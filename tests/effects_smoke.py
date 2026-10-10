"""Smoke test of the seals' magic: every way of manifesting (manifest.lua) and every page of the wiki's grimoire is
cast in a small fake world (a caster, three enemies, a flask, a wand, a chest, an enemy projectile, flat ground) and
its effects run for a few seconds of frames, with the Noita API stubbed. Also the things of the world: sheets, flasks,
the books for sale, dropped by a boss, lying at the start, picked up. Catches Lua errors, calls to missing files,
unknown materials and unknown component fields - what would otherwise only show up in the game.

    python tests/effects_smoke.py            (needs: pip install lupa)
    python tests/effects_smoke.py -v         (lists what every seal made)
"""
import sys

from harness import FIELDS, MATERIALS, WORLD_FILES, bare_world, load_reader
import noita_components as NC  # tools/, on the path with harness

FRAMES = 240


def main():
    verbose = "-v" in sys.argv
    # the mod as init.lua loads it, with the carriers made
    lua = bare_world(WORLD_FILES + ["files/carriers.lua", "files/ink.lua", "files/sheets.lua"])
    lua.execute("carriers_create() sheets_create() ink_create_flasks()")

    failures = []
    report = []

    def run(label, code, frames=FRAMES):
        lua.execute("W.errors = {}; W.added = {}; W.made = {}; W.prints = {}; make_world()")
        ok = True
        try:
            lua.execute(code)
        except Exception as e:  # a Lua error in the cast itself
            failures.append(f"{label}: {e}")
            return
        lua.execute(f"simulate( {frames} )")
        errors = list(lua.eval("W.errors").values())
        seen = set()
        for msg in errors:
            key = str(msg).split("\n")[0]
            if key not in seen:
                seen.add(key)
                failures.append(f"{label}: {msg}")
                ok = False
        # every component the magic added: known type, known fields, real materials
        for item in lua.eval("W.added").values():
            kind, values = item[1], item[2]
            keys = list(values.keys()) if hasattr(values, "keys") else []
            for problem in NC.check_component(FIELDS, kind, keys, label + ": "):
                if problem not in failures:
                    failures.append(problem)
                    ok = False
            if kind == "MagicConvertMaterialComponent":
                for field in ("from_material_array", "to_material_array", "from_material", "to_material"):
                    for m in str(values[field] or "").split(","):
                        if m and not m.lstrip("-").isdigit() and m not in MATERIALS:
                            failures.append(f"{label}: conversion with unknown material {m}")
                            ok = False
        if verbose:
            made_files = sorted(set(str(f) for f in lua.eval("W.made").values()))
            prints = list(lua.eval("W.prints").values())
            report.append(f"{'ok ' if ok else 'ERR'} {label:34s} particles={lua.eval('W.particles')} made={made_files[:4]} {prints[:1]}")
        lua.execute("W.particles = 0")

    ctx = ('local ctx = {{ shooter = PLAYER, spell = parse_spell_data( "{data}" ), x = 0, y = GROUND - 8, aim_x = 0.99, aim_y = -0.13,'
           ' tx = 150, ty = -20, frame = W.frame, strokes = nil, power = 1.4 }} ')
    manifests = sorted(lua.eval("MANIFESTS").keys())
    for key in manifests:
        run(f"manifest {key}", ctx.format(data=f"element=water;form=burst;manifest={key};shape=dragon") +
            f'return MANIFESTS["{key}"]( ctx, 0, GROUND - 8 )')
    for shape in ("dragon", "horse", "bird", "fish", "owlcat", "leech"):
        for element in ("water", "fire", "light", "smoke"):
            run(f"sculpture {shape} {element}", ctx.format(data=f"element={element};form=burst;shape={shape}") + "return MANIFESTS.sculpture( ctx )")
    # every page of the grimoire as the book casts it, and the forms of every element with every behavior
    for entry in lua.eval("GRIMOIRE").values():
        # as the book casts a page of its grimoire: a flawless drawing of it
        run(f"wiki {entry['key']}", f'return cast_spell( PLAYER, parse_spell_data( seal_page_data( {{ named = "{entry['key']}", precision = 1, '
            'stability = 1 } ) ), 0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, { { { x = 20, y = 90 }, { x = 160, y = 90 } } } )')
    # sheets with seals: found in the world, in a chest, in Hell, for sale in a Holy Mountain; picked up
    run("sheet found", "return { sheet_spawn_found( 0, GROUND - 8 ) }", frames=30)
    run("sheet in Hell", "return { sheet_spawn_found( 0, GROUND - 8, true ) }", frames=30)
    for seed in range(6):  # sheets and flasks of ink for sale, on sale too
        run(f"shop item {seed}", f"SetRandomSeed( {seed}, 7 ) return {{ sheet_shop_item( 0, GROUND - 8, {'true' if seed % 2 else 'false'} ) }}", frames=30)
    run("sheet picked up", 'local e = sheet_spawn_found( 0, GROUND - 8 ) dofile( "mods/witch_notebook/files/sheet_pickup.lua" ) '
        'item_pickup( e, PLAYER, "" ) return { GlobalsGetValue( SHEET_PENDING_VAR, "" ) }', frames=10)
    # a flask or a book for sale stands as its picture; bought, it is the thing itself in the witch's hands
    run("flask bought", 'local e = shop_stand( ink_flask_entity( "azure" ), 0, GROUND - 8, ink_shop_image( "azure" ), INK_SHOP_W, '
        'INK_SHOP_H, "Flask of Azure Ink", "" ) shop_stand_set( e, "witch_shop_ink", "azure" ) '
        'dofile( "mods/witch_notebook/files/shop_stand_pickup.lua" ) item_pickup( e, PLAYER, "" ) return W.made', frames=10)
    run("book bought", 'W.flags = {} local e = book_shop_item( "quire", 0, GROUND - 8, 2, false ) '
        'dofile( "mods/witch_notebook/files/shop_stand_pickup.lua" ) item_pickup( e, PLAYER, "" ) '
        'assert( book_owned( "quire" ), "the bought quire is not theirs" ) return W.made', frames=10)
    for ink in [ink["key"] for ink in lua.eval("INKS").values() if ink["key"] != "ink"]:
        run(f"flask of {ink}", f'return {{ EntityLoad( ink_flask_entity( "{ink}" ), 0, GROUND - 8 ) }}', frames=10)
    # the books: for sale in a Holy Mountain, left by a boss, lying beside the witch at the start, picked up
    for key in ("quire", "tome"):  # the Spellbook every run starts with isn't sold
        for cheap in ("false", "true"):
            run(f"book for sale {key} {cheap}", f'return {{ book_shop_item( "{key}", 0, GROUND - 8, 4, {cheap} ) }}', frames=30)
    run("boss leaves a tome", 'W.flags = {} local boss = EntityCreateNew( "boss" ) book_boss_drop( boss ) book_boss_drop( boss ) '
        'return W.made', frames=10)
    run("books at the start", 'W.flags = {} local get = ModSettingGet ModSettingGet = function() return true end '
        'books_spawn_for_testing( PLAYER ) ModSettingGet = get return W.made', frames=10)
    run("book picked up", 'W.flags = {} local e = EntityLoad( BOOKS.tome.entity, 0, GROUND - 8 ) '
        'dofile( "mods/witch_notebook/files/book_pickup.lua" ) item_pickup( e, PLAYER, "" ) return { tostring( book_owned( "tome" ) ) }',
        frames=10)
    # the inks: every dyed ink on a projectile, a wave, a sculpture and a few ways of manifesting (blood also boils over)
    inks = [ink["key"] for ink in lua.eval("INKS").values() if ink["key"] != "ink"]
    for ink in inks:
        for data in ("element=fire;form=column;force=0.5", "element=water;form=dispersion", "element=light;form=burst;shape=dragon",
                     "element=light;form=burst;manifest=carousel", "element=earth;form=burst;manifest=stone_wall",
                     "element=light;form=burst;manifest=petrify;forbidden=true"):
            for frame in (0, 1, 2):
                run(f"ink {ink} {data.split(';')[-1]} #{frame}", f'return cast_spell( PLAYER, parse_spell_data( "{data};precision=0.9;stability=1;ink={ink}:1" ), '
                    f'0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame + {frame * 97}, {{ {{ {{ x = 20, y = 90 }}, {{ x = 160, y = 90 }} }} }} )', frames=90)
    behaviors = [b["key"] for b in lua.eval("DICTIONARY_BEHAVIORS").values()]
    for element in sorted(lua.eval("DICTIONARY_LOOKS").keys()) + ["vacuum", "beam", "thunder", "shockwave"]:
        for form in ("column", "levitation", "dispersion", "burst", "rain", "ring"):
            b = ",".join(f"{k}:1" for k in behaviors if k != "pierce") + ",pierce:2"
            run(f"form {element} {form}", f'return cast_spell( PLAYER, parse_spell_data( "element={element};form={form};force=0.5;b={b}" ), '
                '0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, nil )', frames=120)
    # every resonance (resonances.lua) in each form, with a few of the elements it takes, as the Test Book has them
    reader = load_reader()
    reader.execute('dofile_once( "mods/witch_notebook/files/sigils.lua" ) dofile_once( "mods/witch_notebook/files/test_book.lua" )')
    by_part = {}
    for p in reader.eval("TestBook.pages()").values():
        if p["key"].startswith("test:res/"):
            by_part.setdefault(p["title"], []).append(p)
    for title, pages in sorted(by_part.items()):
        for p in pages[:: max(1, len(pages) // 3)]:
            run(f"resonance {p['name']}", f'return cast_spell( PLAYER, parse_spell_data( "{p["spell"]}" ), 0, GROUND - 8, 0.99, -0.13, '
                '60, -20, W.frame, nil )', frames=120)
    # the book in hand: a click casts the active page; the Repetition Seal repeats it
    run("spellbook_use", 'GlobalsSetValue( "witch_notebook.active_spell", "element=fire;form=column;b=thrust:1" ) '
        'local book = EntityCreateNew( "book" ) EntityAddComponent2( book, "VariableStorageComponent", { name = "witch_notebook_next_cast", value_int = 0 } ) '
        'spellbook_use( book, PLAYER, EntityGetFirstComponent( PLAYER, "ControlsComponent" ), W.frame ) '
        'GlobalsSetValue( "witch_notebook.active_spell", "element=light;form=burst;manifest=repeat" ) '
        'return spellbook_use( book, PLAYER, EntityGetFirstComponent( PLAYER, "ControlsComponent" ), W.frame + 100 )')

    if verbose:
        print("\n".join(report))
    for f in failures[:80]:
        print("FAIL", f)
    print(f"{len(failures)} problems; {len(manifests)} manifests, {len(list(lua.eval('GRIMOIRE').values()))} wiki seals")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
