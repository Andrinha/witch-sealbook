# Light spell audit

The saved wiki descriptions and redraws in `../reference/wha-wiki/` were compared
with the mod's ten Light pages. They cite manga chapters but are secondary
references; this is not a direct check of every manga panel. The ancient beacon
comes from the anime, and the carousel has no descriptive wiki article.

| Spell | Reference and resulting behavior |
| --- | --- |
| Floatglow Lamp, Ch. 28 | The effect is never shown. The wiki reads its columns and level planes as a suspended beam, but a column of light did not look like the lamp it is named after. It now lights the same contraption and floating ball as the Volume 12 seal below, as the lantern witches carry (Agott's in the wiki's picture): it lights at the book, flies after its caster and hangs beside their head, 12–16 pixels to the side it is on. It eases towards its place at up to 360 pixels a second, slides along terrain instead of passing through it, and reappears beside a caster more than 260 pixels away. Another cast renews the one lantern. It has no body and no bracket. This is an interpretation, replacing a generic damaging carrier. |
| Wall-Anchored Floatglow Lamp | The Volume 12 seal produces a floating ball. The mod now draws the contraption around it, following the manga panels: a shallow tray lined with the seal's page, a conical top with holes that floats above the light on a chain, and dotted rings of glow around the ball. The top lifts off the tray as the seal lights and settles back as it goes out. Its tray is a thing in the world: a small physics body (`files/entities/floatglow_tray.xml`, `metal_prop`). A wall within 8–16 pixels of the tray holds it still on a bracket arm and wall plate. Without a wall, or once that wall is dug away, the tray is let go for good: it falls, rolls and can be pushed or kicked like any prop, and the top and the light float over it wherever it lies. The seal's light still deals no damage. The tray goes when the seal runs out, and the lamp goes out if its tray is destroyed. |
| Light Beam | The wiki describes light pointing upward from the seal (Ch. 9). For the requested Noita controls, the beam now points toward the mouse at cast time. Terrain stops it; there is no damage or blindness. Recasting a nearby beam redirects the existing source. |
| Glowstone Path | Stones emit light when stepped on (Ch. 1, 9, 83). The placed ground markers remain dim until a creature's feet touch them, then shine and fade. This places virtual stones on existing terrain without changing the terrain material. |
| Bird of Light Beacon | A flying bird entertains, signals and distracts (Ch. 11). The harmless flying decoy remains, now drawn as a body, head, feathered wings and tail with a luminous trail. |
| Ancient Light Beacon | Its presumed column effect and unknown signs come from the anime's primer. The seal uses explicit vector strokes following the redraw: eight alternating square/diamond crests with center dots, forked links, eight triangles and forked outer signs, and a central oval with two circles and opposing curls. This preserves details lost by automatic skeleton tracing. A long illuminated beam is marked as interpreted and points toward the mouse for the requested Noita controls. Local fog visibility follows its lit path; this is an illumination mechanic requested for the Noita adaptation. |
| Light Tracer | Ch. 46 describes threads connecting all fragments of one broken object. Automatic treasure finding was removed. See the explicit Noita adaptation below. |
| Flowers of Light | Ch. 58 shows glowing flowers and a seal with pentagonal partitions and unknown signs. Its page now follows the redraw using vector strokes, including the square/diamond light crest, five paired curls and radial lines. It is recognized as a whole; the unknown signs no longer become purification. Four separated flowers unfold, shimmer and shed slow motes. |
| Valance Leech of Light | Ch. 78 describes a decorative light sculpture, used to demonstrate knowledge of the sigil. Enemy pursuit, latching, blindness and draining were unsupported. The species is a lattice of tentacles, so the sculpture now shows open net cells and terminal suckers, undulating in place without harming creatures. |
| Carousel of Lights | A listed seal and redraw exist, but its wiki link is a red link, with no confirmed effect description. Orbiting lights remain an interpretation, with flowing trails and no fire damage or blindness. |

Reference pages: [Floatglow Lamp Seal](https://witchhatatelier.telepedia.net/wiki/Floatglow_Lamp_Seal),
[Light Beam](https://witchhatatelier.telepedia.net/wiki/Light_Beam),
[Glowstone Path Seal](https://witchhatatelier.telepedia.net/wiki/Glowstone_Path_Seal),
[Bird of Light Beacon](https://witchhatatelier.telepedia.net/wiki/Bird_of_Light_Beacon),
[Ancient Light Beacon](https://witchhatatelier.telepedia.net/wiki/Ancient_Light_Beacon),
[Light Tracer](https://witchhatatelier.telepedia.net/wiki/Light_Tracer),
[Flowers of Light](https://witchhatatelier.telepedia.net/wiki/Flowers_of_Light),
[Valance Leech of Light](https://witchhatatelier.telepedia.net/wiki/Valance_Leech_of_Light).
The [spell list](https://witchhatatelier.telepedia.net/wiki/Spells) was also checked
online: Carousel of Lights still links to a missing article on 2026-09-30.

## Light Tracer in Noita

Noita has no general provenance system for pieces of broken objects. Cast on a
loose wand, potion, pickup, physics prop or enemy within 18 pixels of the cursor
(450-pixel casting reach) to mark it. Subsequent casts add targets to the same
caster's linked set. Every pair of marked targets within 450 pixels receives one
thread, independently of the first selection. When the caster's active item has
the `witch_spellbook` tag (any of the mod's three books), the caster also connects
to every marked target within 450 pixels. Switching to another item or empty
hands hides only the caster's rays; target-to-target connections remain.
Unmarked targets are never automatically chosen.
Each cast renews the entire set's display for a base 25 seconds (1500 frames), subject to spell modifiers;
marking alone does not move or change the selected item. Physics props include
ordinary and explosive boxes, crates, barrels, carts and stones. Tagged props
and `item_physics` objects such as chests are selectable; untagged objects are
also recognized through `PhysicsBodyComponent` or `PhysicsBody2Component`.
The current biome minecart uses `kill_entity_after_initialized=1`, so it leaves
only Box2D bodies. The fallback queries dynamic bodies near the cursor and creates
a marker that follows `PhysicsBodyIDGetWorldCenter`, converted from Box2D units
with `PhysicsPosToGamePos`. The marker is reused on recast, removed when the body
disappears, and attached to the tracer for cleanup on expiry. This avoids altering
the vanilla cart's physics or XML. Carried bodies are excluded from fallback selection.
The `enemy` tag allows marking enemies without
damaging, slowing or changing their AI. The caster cannot mark themself. Items
in inventories are excluded from new selections; a `mortal` tag alone is not
sufficient. Out-of-range casts show
a message rather than silently clamping the cursor to a different position.

For actual related fragments, add the `witch_light_fragment` entity tag and a
`witch_fragment_group` string VariableStorageComponent with the same identifier
to every fragment. These explicit groups take precedence over caster-created
sets and do not mix with one another. Threads follow an item's root entity if
it is picked up and follow moving enemies. Losing the original source chooses
another surviving target as the effect's anchor, preserving remaining links.
The display ends when no targets remain or its duration expires. Every eligible
pair is kept, including targets beyond the former twelve-link limit. Particle
spacing adapts to the number of connections, with samples shifting across frames
to keep large sets cheaper to render.

Light Beam and Ancient Light Beacon use the direction from the book to the
mouse when cast; another cast redirects a nearby source without stacking it.
This direction control is a Noita adaptation. The ancient beacon remains an
interpreted effect. Each beam clips its core and outer glow against terrain,
and local illumination offsets rotate with its lit path. Floatglow no longer
uses a column: both lamps show a ball of light and light up without a sound.
Only the beams keep the `misc/beam_from_sky_hit` strike when they appear.
A column lamp saved before this change finishes as a column.

## Compatibility and verification

All ten Light manifestations illuminate and open local fog visibility around
their active sources. The masks use the vanilla torch mechanism:
`SpriteComponent.fog_of_war_hole` and `data/particles/fog_of_war_hole_128.xml`.
Their radius and offsets follow each `LightComponent`, so moving birds,
cursor lamps, the lit section of beams and pressed glowstones reveal their own
surroundings. Light Tracer also illuminates its marked endpoints.
Masks disappear with the source and are hidden when that light's radius is zero.
`LightComponent.update_properties` is enabled so changing stone and beam
radii actually update in the game. This is local active visibility, not a
permanent exploration record or a spell's documented manga property.

Named pages saved before the manifestation changes receive the corrected Light
manifestation before ink and misfire processing. Unnamed seals and the separate
Tracking and Guidance spells keep their existing mechanics. Recasting nearby
lamps, flowers and sculptures or the same carousel renews the existing display.
Water, fire and sand flowers retain their separate manifestation behavior.

- `tests/test_light_spells.py`: harmless effects, saved pages, lifetime,
  aimed beams and terrain occlusion, redirection and blocked fog masks,
  pressure activation/fading, book-controlled rays, all-pairs links and repeated selection,
  enemy marking/motion, surviving target destruction, 120 links among sixteen targets,
  untagged carts, bare physics bodies, marker movement/cleanup and 25-second renewal/expiry,
  fragment groups, pickup/destruction, renewal, all ten perfect seals and sixteen
  copies of the corrected flower page, fog masks for all ten sources, ceiling
  clipping, moving sources, remote fragment lights and pressure-controlled fog.
- `tests/effects_smoke.py`: all manifestations and 127 grimoire pages, including
  validation of component fields, materials, files and Lua runtime errors.
- Existing fire, spiral, casting, inks, behavior and sheet checks provide
  regressions for the shared casting and manifestation code.
- `tests/render_light_spells.py` exports `tests/output/light_spells.png`, individual
  GIFs and `flowers_of_light_seal.png` from actual Lua particle calls. Particle
  glow, live illumination and enemy AI still need an in-game visual check.
- `tests/render_floatglow.py` exports `tests/output/floatglow_lamps.png`: both
  lamps lighting up, shining and going out, with their sprites, at six times
  scale. The sprites come from `tools/make_gfx.py`. How the game lights these
  non-emissive sprites and layers them with the particles needs an in-game check.
  So does the tray's physics: the offline world has no Box2D, so the tests only
  check that the tray is created static, released with `PhysicsSetStatic`,
  followed when it moves, found again by its saved key after a reload, and
  removed with its lamp. Its fall, weight and kicks are untested.
