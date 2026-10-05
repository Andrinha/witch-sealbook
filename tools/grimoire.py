"""The wiki's seals (Independent Witch Hat Atelier Wiki, Spells) for the book: every spell with its seal as strokes on a
book page, what it is called and what it does in the game. make_grimoire.py writes them into files/grimoire.lua (the
book's pages of the wiki's spells, and the seals the book recognizes as a whole); tests/wiki_spells.py checks each one
and writes the sheet to compare them in the game.

A seal is either
  - a recipe: the symbols of the book's vocabulary laid out as on the wiki's redraw (positions in the ring's units:
    the center is 0, 0, the radius 1, y down; angles in degrees, 0 - right, 90 - down), or
  - traced from the wiki's redraw when its signs aren't in the vocabulary: the book recognizes such a seal only as
    a whole.
"""
import math
import os

WIKI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reference", "wha-wiki")


# ---------------------------------------------------------------- recipe language

def sig(key, x=0.0, y=0.0, size=0.45, rot=0.0):
    """a center symbol (sigil) at x, y, its larger side 'size', turned by 'rot' degrees"""
    return ("sigil", key, x, y, size, rot)


def sgn(key, ang, dist=0.7, size=0.25, face="in", turn=0.0):
    """a sign on the circle at angle 'ang', facing the center ('in'), away from it ('out') or turned 'turn' degrees"""
    x, y = dist * math.cos(math.radians(ang)), dist * math.sin(math.radians(ang))
    point = ang + 180 if face == "in" else ang
    return ("sign", key, x, y, size, point + turn)


def at(key, x, y, size, point):
    """a sign at x, y pointing to 'point' degrees (where its tip - the side it faces the center with - points)"""
    return ("sign", key, x, y, size, point)


def around(key, angles, dist=0.7, size=0.25, face="in", turn=0.0):
    return [sgn(key, a, dist, size, face, turn) for a in angles]


def frame(key, size=1.2, rot=0.0, x=0.0, y=0.0):
    return ("frame", key, x, y, size, rot)


def layer(r):
    """another ring, concentric: a layer of the seal"""
    return ("layer", r)


def sub(x, y, r, *symbols):
    """a small seal inside the seal: its own circle and symbols (in its own ring's units)"""
    return ("sub", x, y, r, list(symbols))


def link(x, y, r, *symbols):
    """a small seal outside, joined to the ring by a line"""
    return ("link", x, y, r, list(symbols))


def glaive(ang):
    return ("glaive", ang)


def band(n=26, r_in=0.8):
    """a band of small marks between the ring and an inner ring (Windowway)"""
    return ("band", n, r_in)


def raw(*pts):
    """a free line (the big crossing arcs of the Glowstone Path)"""
    return ("raw", list(pts))


def arc_pts(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


D4 = [45, 135, 225, 315]
C4 = [0, 90, 180, 270]
C8 = [i * 45 for i in range(8)]
C6 = [i * 60 for i in range(6)]


class Spell:
    def __init__(self, key, name, en, page, image, category, symbols=None, traced=None, expect=None, manifest=None,
                 effect="", status="works", forbidden=False, crop=None, ring=None, note="", cast=None, trace_size=None,
                 book=None, whole_only=False, middle=None):
        self.key, self.name, self.en, self.page, self.image, self.category = key, name, en, page, image, category
        self.symbols = symbols  # a recipe
        self.whole_only = whole_only  # its overlapping lines must be recognized as one drawing
        # a whole seal whose sigil may be changed for another: (the sigil in its middle, how far the sigil reaches as
        # a share of the drawing's reach). Drawn with another sigil it is the page of its manifest with that sigil,
        # or, when there is none, casts the same in that sigil's element (seal_canon.lua middle_sigil)
        self.middle = middle
        self.traced = traced    # or: trace the wiki's image
        self.crop = crop        # (left, top, right, bottom) of the image to trace
        self.ring = ring        # traced: the ring (cx, cy, r) in the image's pixels, if it can't be found
        self.trace_size = trace_size  # traced: the bigger side of the image as traced (a fine drawing needs more)
        self.book = book        # the smallest book the seal fits in (books.lua), if not by how intricate it is
        self.expect = expect or {}
        self.manifest = manifest
        self.effect = effect
        self.status = status    # works | interpreted (the wiki shows no seal, or its effect is the mod's reading) | whole
        self.forbidden = forbidden
        self.note = note
        # what the seal casts, over what its page reads as ({"element": .., "b+": {behavior: weight}}): for the seals whose
        # meaning the book's reading of their signs doesn't get
        self.cast = cast or {}


def S(*a, **k):
    return Spell(*a, **k)


FIRE, LIGHT, WATER, EARTH, WIND, TIME, CRYSTAL, ILLUSION, SCULPT, SPACE, MIXED, NICHE, FORBIDDEN = (
    "Fire", "Light", "Water", "Earth", "Wind", "Time", "Crystalize", "Illusion", "Sculpting", "Spatial", "Mixed",
    "Niche", "Forbidden")

def spiraling_flame_seal():
    """Clean vector strokes in the wiki redraw's 450px coordinates.

    Generic templates change the fire triangle and the closed wind loops. Image
    skeleton tracing also drops the arrow's short branches, so draw these explicitly.
    """
    from shapes import arc, curve

    def stroke(pts):
        return raw(*[((x - 225) / 209, (y - 225) / 209) for x, y in pts])

    wind = curve((104, 220), (90, 200), (82, 171), (84, 140), (97, 112), (108, 103))
    loop = arc(119, 114, 16, -135, 225, n=48)
    return [
        stroke([(225, 277), (173, 365), (282, 365), (225, 277)]),
        stroke([(173, 305), (209, 328)]), stroke([(282, 305), (241, 328)]),
        stroke([(225, 354), (225, 395)]),
        stroke([(227, 48), (225, 217)]), stroke([(206, 68), (227, 48), (247, 67)]),
        stroke([(225, 167), (208, 195), (225, 221), (242, 195), (225, 167)]),
        stroke(wind), stroke(loop),
        stroke([(448 - x, 318 - y) for x, y in wind]),
        stroke([(448 - x, 318 - y) for x, y in loop]),
        stroke([(70, 282), (101, 335)]), stroke([(85, 308), (128, 282)]),
        stroke([(384, 282), (353, 335)]), stroke([(369, 308), (326, 282)]),
    ]


def ancient_light_beacon_seal():
    """The anime primer's seal, following its 1600px wiki redraw.

    Skeleton tracing loses the crest dots and forked arms and flattens the loops.
    Preserve these unknown symbols as explicit strokes, without generic stand-ins.
    """
    from shapes import circle, curve

    def stroke(pts, turn=0):
        a = math.radians(turn)
        return raw(*[((x - 800) * math.cos(a) / 728 - (y - 800) * math.sin(a) / 728,
                      (x - 800) * math.sin(a) / 728 + (y - 800) * math.cos(a) / 728) for x, y in pts])

    out = []
    for turn in range(0, 360, 45):
        # Rotating both outlines alternates square and diamond on the inner ring.
        out += [stroke([(719, 373), (881, 373), (881, 536), (719, 536), (719, 373)], turn),
                stroke([(800, 373), (881, 455), (800, 536), (719, 455), (800, 373)], turn),
                stroke([(800, 455)], turn)]
        # Forked links between adjacent crests, including the outward branch.
        out += [stroke(curve((881, 455), (927, 452), (951, 436), (966, 407)), turn),
                stroke(curve((966, 407), (951, 446), (960, 479), (983, 501)), turn)]
        out += [stroke([(713, 160), (887, 160), (800, 319), (713, 160)], turn),
                stroke([(534, 177), (619, 370)], turn),
                stroke(curve((479, 243), (535, 298), (576, 314), (603, 309),
                             (624, 287), (626, 267), (619, 186)), turn)]
    # Unknown central sigil: two circles in a tall oval, with opposing curls.
    out += [stroke(circle(800, 800, 61, ry=123)),
            stroke(circle(800, 723, 44)), stroke(circle(800, 877, 44)),
            stroke(curve((640, 744), (637, 720), (649, 696), (675, 687), (698, 697),
                         (713, 720), (706, 757), (689, 804), (677, 852), (676, 904),
                         (688, 949), (712, 978), (747, 986), (778, 974), (800, 949), (807, 922))),
            stroke(curve((791, 678), (800, 645), (827, 621), (859, 615), (889, 628),
                         (911, 660), (923, 707), (925, 754), (915, 801), (896, 849),
                         (888, 884), (901, 908), (928, 915), (952, 900), (962, 878), (958, 858)))]
    return out


# The flower seals' middle: the sigil stands inside the pentagon. Its lines reach at most this share of the drawing's
# own reach (the stems end at 0.876 of the radius, the pentagon's corners are at 0.343): seal_canon.lua reads what lies
# within it as the sigil, whatever the drawing's size and place in its ring.
FLOWER_MIDDLE = 0.348


def flower_seal(*middle):
    """The wiki redraw of Flowers of Light without its sigil: pentagonal partitions and unknown curls, and
    'middle' - the sigil - inside the pentagon. The seal blooms in whatever element its sigil is.

    These unknown signs must not be replaced by purification or a flower frame.
    Coordinates follow the 1600px redraw, with its ring at (800, 800), r=728.
    """
    from shapes import curve

    def stroke(pts):
        return raw(*[((x - 800) / 728, (y - 800) / 728) for x, y in pts])

    vertices = [(800, 550), (1038, 725), (948, 998), (652, 998), (562, 725)]
    tips = [(800, 200), (1370, 615), (1150, 1285), (450, 1285), (230, 615)]
    out = [stroke(vertices + vertices[:1])]
    out += [stroke([a, b]) for a, b in zip(vertices, tips)]
    curls = curve((645, 1208), (642, 1175), (665, 1125), (720, 1105),
                  (775, 1125), (800, 1185), (825, 1125), (880, 1105),
                  (935, 1125), (958, 1175), (955, 1208))
    for i in range(5):
        a = math.radians(i * 72)
        def rotate(pts):
            return [(800 + (x - 800) * math.cos(a) - (y - 800) * math.sin(a),
                     800 + (x - 800) * math.sin(a) + (y - 800) * math.cos(a)) for x, y in pts]
        out += [stroke(rotate(curls)), stroke(rotate([(800, 1185), (800, 1438)]))]
    return out + list(middle)


def flowers_of_light_seal():
    """The wiki redraw: the flower seal with a light crest in its middle."""
    def stroke(pts):
        return raw(*[((x - 800) / 728, (y - 800) / 728) for x, y in pts])

    crest = [stroke([(704, 704), (896, 704), (896, 896), (704, 896), (704, 704)]),
             stroke([(800, 704), (896, 800), (800, 896), (704, 800), (800, 704)])]
    crest += [stroke(pts) for pts in [[(800, 634), (800, 704)], [(800, 896), (800, 966)],
                                      [(634, 800), (704, 800)], [(896, 800), (966, 800)], [(800, 800)]]]
    return flower_seal(*crest)


def water_rose_seal():
    """The wiki redraw: the water sigil in a Flower Sigil, an unknown sign in each of its five fields.

    The Flower frame of the book's vocabulary has longer lines and a smaller pentagon, and the unknown signs are
    not coils on those lines: each is two long arcs that cross, with two shorter arcs that meet in a point towards
    the center. Coordinates follow the 2000px redraw, with its ring at (999, 999), r=909.
    """
    from shapes import curve

    def stroke(pts, turn=0):
        a = math.radians(turn)
        return raw(*[((x - 999) * math.cos(a) / 909 - (y - 999) * math.sin(a) / 909,
                      (x - 999) * math.sin(a) / 909 + (y - 999) * math.cos(a) / 909) for x, y in pts])

    def mirror(pts):
        return [(1998 - x, y) for x, y in pts]

    inner = curve((999, 1401), (972, 1428), (935, 1453), (885, 1471), (832, 1475))
    outer = curve((892, 1403), (908, 1438), (947, 1485), (999, 1522), (1059, 1551), (1120, 1565), (1184, 1569))
    corners = [(999 + 364 * math.cos(math.radians(72 * i - 90)), 999 + 364 * math.sin(math.radians(72 * i - 90)))
               for i in range(5)]
    # the water sigil as the redraw has it: wider than the book's own, its drops a drop and a drop turned over
    out = [stroke(curve((825, 912), (808, 960), (794, 1002), (788, 1037), (797, 1065), (825, 1078),
                        (853, 1065), (862, 1037), (857, 1002), (841, 960), (825, 912))),
           stroke(curve((1039, 900), (1030, 872), (996, 849), (962, 872), (952, 907), (960, 942), (985, 984),
                        (1011, 1012), (1038, 1054), (1046, 1090), (1039, 1124), (1002, 1145), (966, 1124), (959, 1096))),
           stroke(curve((1174, 1087), (1158, 1044), (1143, 1002), (1136, 960), (1148, 932), (1173, 918),
                        (1199, 932), (1211, 960), (1203, 1002), (1188, 1044), (1174, 1087))),
           stroke(corners + corners[:1])]
    for i in range(5):
        # the line from a corner, and the sign in the field opposite that corner
        out += [stroke([(999, 635), (999, 231)], 72 * i)]
        out += [stroke(pts, 72 * i) for pts in (inner, mirror(inner), outer, mirror(outer))]
    return out


def doorknob_seal():
    """The wiki redraw: a band of lightning between two rings, a square with a key in its corner.

    Skeleton tracing breaks the band's zigzags where they run along the rings and loses the forked signs.
    Coordinates follow the 2000px redraw, with its ring at (1000, 1000), r=941; the inner ring is r=790.
    """
    from shapes import curve

    def stroke(pts, turn=0):
        a = math.radians(turn)
        return raw(*[((x - 1000) * math.cos(a) / 941 - (y - 1000) * math.sin(a) / 941,
                      (x - 1000) * math.sin(a) / 941 + (y - 1000) * math.cos(a) / 941) for x, y in pts])

    out = [layer(790 / 941)]
    for turn in range(0, 360, 90):
        # the band: two zigzags and two slanting lines from the ring to the inner ring in every quarter
        out += [stroke(pts, turn) for pts in ([(600, 145), (880, 128), (668, 208), (950, 212)], [(335, 340), (650, 292)],
                                             [(130, 660), (302, 465), (208, 670), (360, 537)], [(65, 985), (247, 748)])]
        # a chevron on every side of the square, pointing at it
        out += [stroke([(842, 445), (1000, 603), (1158, 445)], turn)]
    # three forked signs on the diagonals: two lines crossing, a tick into the crossing, an arc between them
    for turn in (0, 90, 180):
        out += [stroke([(1210, 650), (1640, 542)], turn), stroke([(1330, 775), (1470, 375)], turn),
                stroke([(1270, 712), (1385, 605)], turn),
                stroke(curve((1440, 455), (1450, 500), (1482, 537), (1530, 551), (1578, 558)), turn)]
    # ... and on the fourth a line into the square; the key at the opposite corner
    out += [stroke([(790, 790), (1210, 790), (1210, 1210), (790, 1210), (790, 790)]),
            stroke([(655, 655), (940, 940)]),
            stroke([(1355, 1110), (1110, 1110), (1110, 1355)])]
    return out


def scalewolf_curse_seal():
    """The wiki redraw: a ring of teeth around an arch over three dots and a comb with forked feet.

    The redraw's rings and teeth are filled, and tracing gives their outlines in pieces. Coordinates follow the
    430px redraw: its outer ring at (213, 215), r=185, the inner one r=150.
    """
    from shapes import arc

    def stroke(pts):
        return raw(*[((x - 213) / 185, (y - 215) / 185) for x, y in pts])

    def at(r, deg):
        return (213 + r * math.cos(math.radians(deg)), 215 + r * math.sin(math.radians(deg)))

    out = [layer(150 / 185)]
    # sixteen teeth on the inner ring: the four great ones pierce the outer ring, the others touch it
    for i in range(16):
        a = i * 22.5
        tip, half = (215, 12.5) if i % 4 == 0 else (185, 5.5)
        out.append(stroke([at(150, a - half), at(tip, a), at(150, a + half), at(150, a - half)]))
    out += [stroke([(103, 221)] + arc(212, 210, 109, 180, 360, n=40) + [(321, 221)]),
            stroke([(211, 143)]), stroke([(175, 190)]), stroke([(246, 190)]),
            stroke([(136, 263), (136, 230), (290, 230), (290, 263)]),
            stroke([(187, 230), (187, 263)]), stroke([(238, 230), (238, 263)])]
    out += [stroke([(x - 21, 283), (x, 263), (x + 20, 283)]) for x in (136, 187, 238, 290)]
    return out


def wash_spring_seal():
    """The wiki redraw: two pinwheels of hooks joined through a ring that holds an S, brackets and unknown signs.

    Skeleton tracing joins the hooks of the pinwheels into stars and loses the signs at the sides.
    Coordinates follow the 2000px redraw, with its ring at (1000, 1000), r=910.
    """
    from shapes import arc, circle, curve

    def stroke(pts):
        return raw(*[((x - 1000) / 910, (y - 1000) / 910) for x, y in pts])

    def flip_x(pts):
        return [(2000 - x, y) for x, y in pts]

    def flip_y(pts):
        return [(x, 2000 - y) for x, y in pts]

    # the upper pinwheel: the first hook comes from the ring, the fifth goes down to the ring in the middle
    hooks = [
        curve((1039, 114), (993, 151), (957, 201), (939, 259), (943, 301), (961, 326), (989, 339), (1018, 330),
              (1039, 309), (1041, 280), (1029, 255)),
        curve((1257, 239), (1207, 234), (1150, 241), (1100, 262), (1064, 294), (1051, 330), (1064, 359), (1093, 374),
              (1121, 373), (1143, 355), (1151, 332)),
        curve((1325, 484), (1293, 444), (1250, 409), (1200, 386), (1150, 384), (1114, 401), (1100, 434), (1111, 462),
              (1136, 481), (1164, 484), (1184, 471)),
        curve((1201, 705), (1207, 651), (1200, 601), (1179, 551), (1150, 516), (1114, 498), (1082, 507), (1064, 537),
              (1068, 569), (1086, 591), (1111, 596)),
        curve((950, 766), (1000, 723), (1039, 673), (1057, 623), (1054, 580), (1036, 555), (1007, 544), (975, 551),
              (956, 576), (956, 609), (968, 629)),
        curve((737, 646), (793, 651), (850, 644), (896, 623), (932, 591), (943, 555), (929, 523), (900, 509),
              (868, 512), (846, 530), (844, 553)),
        curve((670, 401), (707, 444), (757, 480), (807, 501), (850, 500), (882, 480), (893, 448), (882, 416),
              (857, 398), (829, 400), (813, 412)),
        curve((793, 184), (789, 230), (796, 280), (818, 330), (854, 369), (893, 387), (921, 376), (934, 344),
              (925, 312), (907, 294), (889, 289)),
    ]
    out = [stroke(h) for h in hooks]
    # the lower pinwheel is the upper one moved down: its first hook comes from the ring in the middle
    out += [stroke([(x, y + 1118) for x, y in h]) for h in hooks]
    # the ring in the middle, a small one in it and the S between them, its ends running out to the ring
    out += [stroke(circle(1000, 1000, 230)), stroke(circle(1000, 1000, 58)),
            stroke(arc(1000, 1000, 147, 224, 105, n=24) + [(1047, 1224)]),
            stroke(arc(1000, 1000, 147, 44, -75, n=24) + [(953, 776)])]
    # at either side two brackets with a point towards the middle, three diamonds with crossed ends and two Ts
    side = [[(490, 575), (625, 710), (625, 1290), (490, 1425)], [(448, 610), (567, 728), (567, 1272), (448, 1390)],
            [(625, 930), (715, 1000), (625, 1070)],
            [(497, 938), (372, 1068), (300, 1000), (372, 930), (497, 1060)]]
    upper = [[(215, 795), (335, 912), (270, 977), (205, 912), (322, 798)],
             [(512, 373), (575, 436)], [(617, 398), (537, 474)]]
    side += upper + [flip_y(pts) for pts in upper]
    out += [stroke(pts) for pts in side] + [stroke(flip_x(pts)) for pts in side]
    return out


SPELLS = [
    # ------------------------------------------------------------ fire
    S("pyreball", "Pyreball", "Pyreball Seal", "Pyreball Seal", "Pyreball_Seal_Redraw.png", FIRE,
      [sig("fire", 0, 0.02, 0.5)] + around("levitation", D4, 0.66, 0.3),
      expect={"element": "fire", "form": "levitation", "floats": True, "behaviors": {"float"}}, manifest="pyreball",
      effect="A ball of flame hangs at the cursor like a bonfire: it gives light, sets fire to and burns whoever is near, and burns for a long time."),
    S("spiraling_flame", "Spiraling Flame", "Spiraling Flame", "Spiraling Flame", "Spiraling_Flame_Redraw.png", FIRE,
      spiraling_flame_seal(), whole_only=True, book="quire", manifest="spiraling_flame",
      expect={"element": "fire", "manifest": "spiraling_flame"},
      cast={"element": "fire", "form": "column", "force": 0.63, "range": 0.58, "lifetime": 0.17,
            "tilt": 0, "push_x": 0, "push_y": 0, "directed": True,
            "b+": {"thrust": 2, "whirl": 1, "aim": 1}},
      effect="Hold the cast: living fire sprays out in three widening spiral strands. Turning the aim steers only the new flame; what is already loosed flies on and fades by itself, however near the witch aims. The fire lights its path and sets alight whatever burns; walls and water stop it. It ends when the witch lets go or puts the book away."),
    S("snugstone", "Snugstone", "Snugstone Spell", "Snugstone Spell", "Snugstone_Seal_Redraw.png", FIRE,
      traced=True, manifest="warmth",
      effect="Gentle warmth without fire around the witch: ice and snow melt, clothes dry, frost does no harm; it lasts a long time."),
    S("phantasmal_fireball", "Phantasmal Fireball", "Phantasmal Fireball", "Phantasmal Fireball", "Phantasmal_Fireball_Redraw.png", FIRE,
      traced=True, manifest="phantasm",
      effect="A cold blue flame lights up over the witch: it gives light and scares beasts but does not burn; it follows the witch."),
    S("flame_shot", "Flame Shot", "Flame Shot Seal", "Flame Shot Seal", "Flameshot_Seal_Redraw.png", FIRE,
      [sig("fire", 0, 0.46, 0.44), at("column", 0, -0.36, 0.82, -90)]
      + [at("regions", -0.55, -0.62 + 0.16 * i, 0.18, -90) for i in range(5)]
      + [at("regions", 0.55, -0.62 + 0.16 * i, 0.18, -90) for i in range(5)],
      # The ten small region signs can be ambiguous individually; recognize the complete seal too.
      expect={"element": "fire", "form": "column", "behaviors": {"thrust"}}, manifest="flame_shot", whole_only=True,
      effect="A long beam of flame strikes far ahead - the column sign across the whole seal and the regions signs stretch it out."),
    S("flame_burst", "Flame Burst", "Flame Burst Spell", "Flame Burst Spell", "65_5_Flame_Burst_Spell.png", FIRE,
      [sig("fire", 0, 0.02, 0.44)] + around("column", C4, 0.7, 0.24) + around("pull", D4, 0.7, 0.26),
      expect={"element": "fire", "form": "column", "behaviors": {"thrust", "pull"}}, manifest="flame_burst", status="interpreted",
      note="The manga shows the seal only in part (a scroll); here - fire, alternating columns and pulling, as the wiki describes it.",
      effect="A small ring of fire opens at the book. A compressed jet of flame shoots forward and expands into a larger fiery blast at the target or against whatever it hits."),
    S("ring_of_fire", "Ring of Fire", "Ring of Fire", "Ring of Fire", "Ring_of_Fire_Redraw.png", FIRE,
      [sig("fire", 0, 0.05, 0.5), sgn("dispersion", 205, 0.62, 0.3), sgn("dispersion", 322, 0.62, 0.3), sgn("dispersion", 80, 0.6, 0.3)],
      expect={"element": "fire", "form": "dispersion"}, manifest="ring_of_fire",
      effect="A wide ring of fire spreads out from the seal, setting fire to everything around the witch."),
    S("snowfending", "Snowfending", "Snowfending", "Snowfending", "Snowfending_Seal_Redraw.png", FIRE,
      traced=True, manifest="snowfend",
      effect="A warm dome rises over the target: snow and ice melt, falling drops evaporate, no fire needed."),
    # ------------------------------------------------------------ light
    S("floatglow", "Floatglow Lamp", "Floatglow Lamp Seal (Ch. 28)", "Floatglow Lamp Seal", "Floatglow_lamp_spell_redraw.png", LIGHT,
      [sig("light", 0, 0, 0.3)] + around("column", D4, 0.62, 0.2) + around("stability", C4, 0.62, 0.3),
      expect={"element": "light", "behaviors": {"still"}}, manifest="floatglow", status="interpreted",
      note="The Chapter 28 seal's effect is not shown. It lights the manga's Floatglow Lamp as the lantern witches carry: a ball of light between the tray and the floating top.",
      effect="A lantern with a floating ball of warm light flies after its caster for a long time without burning or damaging creatures. Casting again renews it."),
    S("floatglow_anchored", "Wall-Anchored Floatglow Lamp", "Wall-Anchored Floatglow Lamp", "Floatglow Lamp Seal", "Wall_Anchored_Floatglow_Lamp_Redraw.png", LIGHT,
      [sig("light", 0, 0, 0.46)] + around("levitation", C4, 0.66, 0.26) + around("convergence", D4, 0.66, 0.2),
      expect={"element": "beam", "form": "levitation"}, manifest="lamp",
      effect="A lamp with a floating ball of warm light is set at the cursor for a long time. A wall beside it holds its tray on a bracket; without one the tray falls and can be pushed about, the light floating over it. The light does not burn or damage creatures."),
    S("light_beam", "Light Beam", "Light Beam", "Light Beam", "Light_Beam_Redraw.png", LIGHT,
      [sig("light", 0, 0, 0.44)] + around("column", C4, 0.76, 0.26),
      expect={"element": "light", "form": "column", "behaviors": {"thrust"}}, manifest="light_beam",
      effect="A bright beam reaches from the book the way the witch aims and stops at the first wall. It gives light and does no harm."),
    S("glowstone_path", "Glowstone Path", "Glowstone Path Seal", "Glowstone Path Seal", "Glowstone_Path_Seal_Redraw.png", LIGHT,
      traced=True, manifest="glowpath",
      effect="Stones on the ground ahead remain dim until stepped on, then shine and gradually fade. The placed path lasts a long time."),
    S("bird_of_light", "Bird of Light Beacon", "Bird of Light Beacon", "Bird of Light Beacon", "Bird_of_Light_Beacon_Spell_Redraw.png", LIGHT,
      [sig("light", 0, 0, 0.42), at("regions", 0, -0.58, 0.26, -90), sgn("dispersion", 90, 0.6, 0.26),
       sig("bird", -0.6, 0.0, 0.46, -90), sig("bird", 0.6, 0.0, 0.46, 90)],
      expect={"element": "light", "shape": "bird"}, manifest="light_bird",
      effect="A bird of light flies up from the seal and circles around: enemies are distracted by it until it fades."),
    S("ancient_light_beacon", "Ancient Light Beacon", "Ancient Light Beacon", "Ancient Light Beacon", "Ancient_Light_Beacon_Redraw.png", LIGHT,
      ancient_light_beacon_seal(), whole_only=True, manifest="beacon_pillar", status="interpreted",
      cast={"element": "light", "form": "burst", "b": {}},
      note="This is an ancient seal from the anime's primer, with unknown signs. Its pillar effect is presumed, not shown in the manga.",
      effect="A long beacon beam reaches from the book the way the witch aims and stops at the first wall. It lights its whole path and bares the dark along it."),
    S("light_tracer", "Light Tracer", "Light Tracer", "Light Tracer", "Light_Tracer_Redraw.png", LIGHT,
      [layer(0.9), frame("weave", 1.4, 180), sig("light", 0, 0.05, 0.44), at("link", 0, -0.66, 0.24, 90)],
      expect={"element": "light", "manifest": "ribbon"}, manifest="tracer", status="interpreted",
      note="In the manga the threads connect fragments of one broken object. Noita adaptation: mark items, physics props or enemies as a linked set. Explicit fragment groups take precedence.",
      effect="Mark items, loose things such as carts, or enemies within reach. Threads of light join every pair of the marked that are near enough to each other. Each cast renews them all for a while. While a book is in hand, rays also join the witch to each of them; put the book away and only those rays go out."),
    S("flowers_of_light", "Flowers of Light", "Flowers of Light", "Flowers of Light", "Flowers_of_Light_Redraw.png", LIGHT,
      flowers_of_light_seal(), whole_only=True, middle=("light", FLOWER_MIDDLE), manifest="bloom",
      cast={"element": "light", "form": "burst", "b": {}},
      expect={"element": "light", "manifest": "bloom"},
      effect="Glowing flowers bloom at the cursor and light up the place for a long time. With another sigil in its middle the seal blooms in that element: a rose of water, flowers of fire, of sand."),
    S("leech_of_light", "Valance Leech of Light", "Valance Leech of Light", "Valance Leech of Light", "Valance_Leech_of_Light_Redraw.png", LIGHT,
      [sig("light", 0, 0.12, 0.4), sig("leech", 0, -0.5, 0.46)] + [sgn("column", a, 0.66, 0.2, "out") for a in (200, 340, 160, 20, 90)],
      expect={"element": "light", "shape": "leech"}, manifest="light_leech",
      effect="A decorative, gently undulating sculpture of a valance leech glows at the cursor. It neither attacks nor drains creatures."),
    S("carousel", "Carousel of Lights", "Carousel of Lights", "Carousel of Lights", "Carousel_of_Lights_Redraw.png", LIGHT,
      [sig("light", 0, 0, 0.34)] + around("column", C4, 0.74, 0.26) + around("levitation", D4, 0.6, 0.26)
      + around("crosshair", [a + 22 for a in D4], 0.82, 0.14) + [sgn("windsign", a, 0.4, 0.2, "in", 90) for a in C4],
      expect={"element": "light"}, manifest="carousel", status="interpreted",
      note="The wiki lists this seal and has a redraw, but no spell article or confirmed effect. Orbiting illumination is the mod's interpretation; burning damage is not substantiated.",
      effect="Soft lights circle the witch with flowing trails, illuminating the surroundings without fire or contact damage."),
    # ------------------------------------------------------------ water
    S("watershot", "Watershot", "Watershot Seal", "Watershot Seal", "Watershot_Seal_Redraw.png", WATER,
      [sig("water", 0, -0.02, 0.56)] + around("column", [0, 45, 135, 180, 225, 270, 315], 0.72, 0.16) + [sgn("column", 90, 0.6, 0.3)],
      expect={"element": "water", "form": "column", "behaviors": {"thrust"}}, manifest="water_pour",
      effect="Water pours from the book for as long as you hold fire, and it never runs dry. It pours towards the cursor, harder the further away the cursor is."),
    S("water_rose", "Water Rose", "Water Rose", "Water Rose", "Water_Rose_Redraw.png", WATER,
      water_rose_seal(), whole_only=True, manifest="water_rose", cast={"element": "water", "form": "burst", "b": {}},
      expect={"element": "water", "manifest": "water_rose"},
      effect="A rose of water grows from the nearest surface by the cursor: a stem, two leaves, then the flower opens petal by petal. It is real water that stands still - you can wade through it - and drips while it stands; when the spell ends it falls as water."),
    S("water_dragon", "Water Dragon", "Water Dragon", "Qifrey's Water Dragon", "Water_Dragon_Spell_Redraw.png", WATER,
      traced=True, manifest="dragon_water",
      effect="A huge dragon of water writhes in the air, lunges at enemies and at the end bursts into a water lily."),
    S("rainbringer", "Rainbringer", "Rainbringer Seal", "Rainbringer Seal", "Rainbringer_Redraw.png", WATER,
      [frame("rain", 1.35), sig("water", 0, 0, 0.5)],
      expect={"element": "water", "form": "rain"},
      effect="A cloud gathers over the target and it rains. The rounder the ring, the gentler the rain."),
    S("wand_of_water", "Wand of Water", "Wand of Water (Archives)", "Wand of Water", "Wand_of_Water_Redraw_(Archives).png", WATER,
      [frame("holding", 1.0, 0, 0, 0.06), sig("water", 0, 0.06, 0.4), sgn("column", 270, 0.66, 0.2),
       at("column", -0.3, -0.62, 0.2, 0), at("column", 0.3, -0.62, 0.2, 180), sgn("pointing", 90, 0.74, 0.3)],
      expect={"element": "water", "manifest": "wand"},
      effect="A pen of water follows the cursor and draws lines of water in the air."),
    S("water_bolt", "Water Bolt Volley", "Water Bolt (Ch. 24)", "Water Bolt", "Water_bolt_spell_redraw.png", WATER,
      [sig("water", 0, 0.6, 0.44, 90)] + [at("pierce", x, y, 0.72, 90) for x, y in ((-0.58, 0.06), (-0.3, -0.06), (0, -0.2), (0.3, -0.06), (0.58, 0.06))]
      + [at("regions", x, y, 0.16, 90) for x, y in ((-0.28, -0.62), (0.28, -0.62), (-0.8, -0.18), (0.8, -0.18))],
      expect={"element": "water", "behaviors": {"pierce"}},
      effect="Five water bolts pierce enemies through; the regions signs face one way and lead them aside."),
    S("water_bolt_27", "Great Water Bolt", "Water Bolt (Ch. 27/83)", "Water Bolt", "Water_Bolt_Seal_Redraw_(Ch_27).png", WATER,
      [layer(0.82), sig("water", 0, -0.12, 0.42)] + [at("sights", 0, -0.82, 0.34, 90), at("sights", -0.64, -0.64, 0.34, 45), at("sights", 0.64, -0.64, 0.34, 135)]
      + [sgn("convergence", 250, 0.6, 0.16), sgn("convergence", 290, 0.6, 0.16)]
      + [sgn("strengthen", 180, 0.62, 0.22), sgn("strengthen", 0, 0.62, 0.22)]
      + [at("pierce", 0, 0.52, 0.44, 90), sgn("regions", 130, 0.62, 0.16), sgn("regions", 50, 0.62, 0.16)],
      expect={"element": "ice", "behaviors": {"aim", "strong"}},
      cast={"element": "ice", "form": "column", "b+": {"aim": 1, "pierce": 1, "strong": 1}},
       effect="One heavy ice bolt flies straight to the aim point and pierces the enemy."),
    S("water_bolt_archives", "Threefold Water Bolt", "Water Bolt (Archives)", "Water Bolt", "Water_Bolt_Seal_Redraw_(3).png", WATER,
      [layer(0.82), sig("water", 0, -0.12, 0.42)] + [at("sights", 0, -0.82, 0.34, 90), at("sights", -0.64, -0.64, 0.34, 45), at("sights", 0.64, -0.64, 0.34, 135)]
      + [sgn("convergence", 250, 0.6, 0.16), sgn("convergence", 290, 0.6, 0.16)]
      + [sgn("strengthen", 180, 0.62, 0.22), sgn("strengthen", 0, 0.62, 0.22)]
      + [at("pierce", -0.28, 0.5, 0.44, 90), at("pierce", 0, 0.52, 0.44, 90), at("pierce", 0.28, 0.5, 0.44, 90),
         sgn("regions", 140, 0.66, 0.16), sgn("regions", 40, 0.66, 0.16)],
      expect={"element": "ice", "behaviors": {"aim", "pierce"}},
      cast={"element": "ice", "form": "column", "b+": {"aim": 1, "pierce": 3, "strong": 1}},
       effect="Three ice bolts fly to the aim point."),
    S("rising_platform", "Rising Platform of Water", "Rising Platform of Water", "Rising Platform of Water", "Rising_Platform_of_Water_Redraw.png", WATER,
      [sig("water", 0, 0, 0.56)] + [sgn("levitation", a, 0.7, 0.3, "in", 75) for a in (275, 5, 95, 185)] + around("column", D4, 0.66, 0.16, "out"),
      expect={"element": "water"}, manifest="geyser",
      effect="A column of water bursts up under the witch and lifts them - you can climb onto a ledge."),
    S("everflow", "Everflow", "Everflow", "Ever-Flowing Icepack", "Everflow_Redraw.png", WATER,
      [sig("water", 0, -0.4, 0.46), sgn("column", 90, 0.6, 0.14)],
      expect={"element": "water"}, manifest="disc",
      effect="A thin disc of water sets at the cursor - you can stand on it, it slowly spins."),
    S("torrential_flow", "Torrential Flow", "Torrential Flow", "Ever-Flowing Icepack", "Torrential_Flow_Seal_Redraw.png", WATER,
      [sig("water", 0, 0, 0.5)] + [sgn("column", a, 0.72, 0.18, "in", 35) for a in range(0, 360, 36)],
      expect={"element": "water", "behaviors": {"spin"}}, manifest="whirlpool",
      effect="Water twists into a whirlpool at the target: it spins and drags enemies in."),
    S("water_horse", "Water Horse", "Water Horse", "Water Horse", "Water_Horse_Spell_Redraw.png", WATER,
      [sig("water", 0, 0.12, 0.34), sig("horse", 0, -0.46, 0.46), at("column", -0.6, -0.6, 0.22, 0), at("column", 0.6, -0.6, 0.22, 180),
       at("mimicry", -0.66, 0.12, 0.44, -90), at("mimicry", 0.66, 0.12, 0.44, -90), at("regions", -0.2, 0.66, 0.14, -90), at("regions", 0.2, 0.66, 0.14, -90)],
      expect={"element": "water", "shape": "horse"},
      effect="A horse of water gallops over the ground where the witch aims and knocks enemies off their feet."),
    S("water_orb", "Water Orb", "Water Orb", "Water Orb", "Water_Orb_Seal_Redraw.png", WATER,
      [sig("water", 0, 0, 0.44, 180), sgn("column", 180, 0.74, 0.3), sgn("column", 0, 0.74, 0.3)] + around("orb", D4, 0.66, 0.26),
      expect={"element": "water", "behaviors": {"contain"}},
      cast={"floats": True},
       effect="An invisible orb at the cursor collects the liquid around into itself and holds it; after a while it bursts, pouring it all out."),
    S("purify", "Purify", "Purify", "Purify", "Purify_Seal_Redraw.png", WATER,
      [sig("water", 0, 0, 0.48), sgn("refuse", 180, 0.78, 0.24, "out"), sgn("refuse", 0, 0.78, 0.24, "out")]
      + [sgn("purify", a, 0.66, 0.2) for a in (225, 250, 275, 300, 325, 45, 70, 95, 120, 145)],
      expect={"element": "water", "behaviors": {"purify"}}, manifest="purify",
      effect="A wave of purification spreads from you: acid, poison, toxic sludge, slime, blood and foul water around turn into clean water. It adds no water of its own."),
    S("sourcewater", "Sourcewater Strike", "Sourcewater Strike", "Sourcewater Strike", "Saltwater_Bolt_Seal_Redraw.png", WATER,
      [sig("water", 0, 0, 0.34), at("gathering", 0.04, -0.4, 0.62, 0), at("gathering", 0.04, 0.4, 0.62, 0),
       at("regions", -0.74, 0, 0.2, 0), at("regions", 0.8, 0, 0.2, 0), at("pierce", -0.12, -0.76, 0.4, 0), at("pierce", -0.12, 0.76, 0.4, 0)],
      expect={"element": "water", "behaviors": {"gather", "pierce"}},
      effect="The witch draws in water from all around and strikes with two heavy streams."),
    S("water_cage", "Water Cage", "Water Cage", "Water Cage", "Water_cage_spell_redraw.png", WATER,
      [sig("water", 0, 0, 0.4)] + around("crush", D4, 0.66, 0.24, "out") + around("regions", C4, 0.72, 0.16)
      + [link(1.55, 0, 0.42, at("pull", 0, 0, 0.9, 180))],
      expect={"element": "water"}, manifest="water_cage",
      effect="A sphere of water forms round the enemy at the cursor and stands in the air. Whoever is in it or comes up to it is pulled inside by the small seal and sealed there: it floats, cannot move, is soaked and chokes, until the sphere bursts."),
    S("raincleaver", "Raincleaver", "Raincleaver", "Raincleaver Spell", "Raincleaver_Redraw_Rotated.jpg", WATER,
      [sig("sword", 0, 0, 0.5)] + [sub(0.62 * math.cos(math.radians(a)), 0.62 * math.sin(math.radians(a)), 0.26, sig("water", 0, 0, 0.9)) for a in C4],
      expect={"manifest": "blade"}, status="interpreted",
      note="In the manga - a sword of many tiny linked seals; here - the sword sigil and four small water seals.",
      effect="The witch cleaves the air with a blade of water: it cuts enemies and parts the liquid in its way."),
    S("rising_wave", "Rising Wave", "Rising Wave", "Rising Wave", "Rising_Wave_Seal.png", WATER,
      [sig("water", 0, 0, 0.46)] + around("column", [270 + 30 * i for i in range(-2, 3)], 0.78, 0.18) + around("regions", [285 + 30 * i for i in range(-2, 2)], 0.78, 0.14)
      + around("levitation", [120, 60], 0.6, 0.24),
      expect={"element": "water"}, manifest="wave_ride", status="interpreted",
      note="The manga's panels show the seal only in part: columns and regions alternating along the edge.",
      effect="A wave rises under the witch and carries them forward and up."),
    S("giant_water_puppet", "Giant Water Puppet of Diversion", "Giant Water Puppet of Diversion", "Giant Water Puppet of Diversion",
      "Giant_Water_Puppet_of_Diversion.png", WATER,
      [frame("dancing", 1.25), sig("water", 0, 0, 0.36)],
      expect={"element": "water", "manifest": "puppet"}, status="interpreted",
      note="The seal is not shown; modeled on the Flying Puppet of Diversion, but with water.",
      effect="A big puppet of water darts about at the target - enemies rush at it."),
    # ------------------------------------------------------------ earth
    S("wall_breaker", "Wall Breaker", "Wall Breaker Seal", "Wall Breaker Seal", "Wall_Breaker_Redraw.png", EARTH,
      [sig("earth", 0, 0, 0.8), sgn("column", 180, 0.74, 0.32), sgn("column", 0, 0.74, 0.32),
       sgn("crush", 270, 0.64, 0.3), sgn("crush", 90, 0.64, 0.3)],
      expect={"element": "earth", "form": "column", "behaviors": {"crush"}},
      effect="The projectile drills through rock and earth, turning stone and soil into sand."),
    S("integration", "Integration", "Integration", "Integration", "Integration_Redraw.png", EARTH,
      [sig("earth", 0, 0, 0.65), sgn("crush", 270, 0.66, 0.24, "out"), sgn("crush", 90, 0.66, 0.24, "out")]
      + [sgn("crush", a, 0.66, 0.2, "out") for a in D4],
      expect={"element": "earth", "behaviors": {"build"}}, manifest="integration",
      effect="Loose sand and earth at the cursor come back together into stone, and snow into packed snow. It turns what lies there and makes no stone of its own."),
    S("wall_bend", "Wall Bend", "Wall Bend", "Wall Bend", "Wall_Bend_Seal_Redraw.png", EARTH,
      traced=True, manifest="stone_wall",
      effect="The ground in front of the witch is drawn up into a wall of brickwork that bends back over them - cover from projectiles and from above. It rises only out of ground: in the air or over a drop nothing comes."),
    S("boulder_stretch", "Boulder Stretch Rope", "Boulder Stretch Rope", "Boulder Stretch Rope", "Boulder_Stretch_Rope_Redraw.png", EARTH,
      [frame("weave", 1.35, 180), sig("earth", 0, 0.04, 0.71)],
      expect={"element": "earth", "manifest": "ribbon"},
      effect="Stone by the witch stretches into a flexible ribbon towards the cursor - a bridge over a chasm."),
    S("sand_cage", "Sand Cage", "Sand Cage", "Sand Cage", "Sand_Cage_Redraw.png", EARTH,
      traced=True, manifest="sand_cage",
      effect="Thick panels of sand wind up around the enemy at the cursor to a point over its head and harden - a cage."),
    S("earth_lift", "Earth Lift", "Earth Lift (Ch. 96)", "Earth Lift", "Earth_Lift_Redraw_Ch.96.png", EARTH,
      [sig("earth", 0, 0.05, 0.66), sgn("column", 270, 0.66, 0.2), sgn("stability", 220, 0.62, 0.26, "in", 90), sgn("stability", 320, 0.62, 0.26, "in", 90),
       sgn("column", 150, 0.72, 0.22), sgn("column", 30, 0.72, 0.22), sgn("stability", 90, 0.66, 0.26)],
      expect={"element": "earth", "behaviors": {"still"}}, manifest="lift",
      effect="The ground under the witch rises as a pillar platform."),
    # ------------------------------------------------------------ wind
    S("sylph_shoes", "Sylph Shoes", "Sylph Shoes Seal", "Sylph Shoes Seal", "Sylph_Shoes_Spell_Redraw.png", WIND,
      [sig("underfoot", 0, 0, 0.62)] + around("convergence", [i * 45 for i in range(8)], 0.84, 0.14) + around("levitation", [22.5 + i * 45 for i in range(8)], 0.84, 0.16),
      expect={"manifest": "sylph"},
      effect="The witch floats: levitation does not run out, falls are soft; a whirl of wind at their feet."),
    S("pegasus_carriage", "Pegasus Carriage", "Pegasus Carriage Spell", "Pegasus Carriage Spell", "Pegasus_Carriage_Seal_WHA_BTS_Pt_10.jpeg", WIND,
      traced=True, manifest="pegasus", status="whole",
      effect="Long steady flight: the witch flies without losing height while the spell lasts."),
    S("skysoaring", "Skysoaring", "Skysoaring Seal", "Skysoaring Seal", "Skysoaring_Seal_Redraw.png", WIND,
      [sig("wind", 0, 0.38, 0.5), at("levitation", 0, -0.4, 0.72, 90)],
      expect={"element": "wind", "form": "levitation"}, manifest="skysoar",
      effect="A gust of wind throws the witch towards the aim point - a dash, or a leap over a chasm."),
    S("flying_puppet", "Flying Puppet of Diversion", "Flying Puppet of Diversion", "Flying Puppet of Diversion", "Flying_Puppet_of_Diversion_Redraw.png", WIND,
      [frame("dancing", 1.3), sig("wind", 0, 0, 0.36)],
      expect={"element": "wind", "manifest": "puppet"},
      effect="A cloak puppet darts about in the air at the target: enemies chase it, light items around fly up."),
    S("grasping_wind", "Grasping Wind", "Grasping Wind", "Grasping Wind", "Grasping_Wind_Redraw.png", WIND,
      [sig("wind", 0, 0, 0.5)] + around("pull", D4, 0.72, 0.3),
      expect={"element": "wind", "behaviors": {"pull"}}, cast={"form": "field"},  # a whirl round the witch, not a splash
      effect="A whirlwind draws items, gold and enemies to the witch. The angled pulling signs twist it into a funnel."),
    S("river_ferry", "River Ferry", "River Ferry Seal", "River Ferry Seal", "River_Ferry_Seal_Redraw.png", WIND,
      [sig("wind", 0, 0, 0.3)] + around("levitation", [270, 330, 30, 90, 150, 210], 0.72, 0.3) + around("stability", [300, 0, 60, 120, 180, 240], 0.78, 0.16),
      expect={"element": "wind", "behaviors": {"float"}}, manifest="gale",
      effect="A long steady wind blows towards the aim point and pushes enemies, items and liquids."),
    S("wind_wall", "Wind Wall", "Wind Wall", "Wind Wall", "Wind_Wall_Redraw.png", WIND,
      traced=True, manifest="wind_wall",
      effect="A ring of wind rises around the witch: it knocks projectiles away and keeps enemies out."),
    S("bubble_carriage", "Bubble Carriage", "Bubble Carriage Seal", "Bubble Carriage Seal", "Bubble_Carriage_Redraw.png", WIND,
      [sig("aeriforms", 0, 0, 0.6)] + around("column", [i * 15 for i in range(24)], 0.86, 0.1) + around("regions", [7.5 + i * 15 for i in range(24)], 0.86, 0.08, "out"),
      expect={"element": "air", "manifest": "bubble"},
      effect="A bubble of air around the witch: you can breathe underwater, liquid draws back."),
    S("wayward_whorlwind", "Wayward Whorlwind", "Wayward Whorlwind", "Wayward Whorlwind", "Wayward_Whorlwind_Redraw.png", WIND,
      traced=True, manifest="whirlwind",
      effect="A whirlwind wanders around, sweeping up items and enemies."),
    # ------------------------------------------------------------ time
    # (The Repetition Seal's page was removed. The Sigil of Repetition stays in the dictionary: the Capture Pennant
    # is built on it, and a seal of one's own with it still repeats the last seal cast.)
    S("capture_pennant", "Capture Pennant", "Capture Pennants", "Capture Pennant Spell", "Capture_Pennants_Spell_Redraw.png", TIME,
      [layer(0.84), sig("repetition", 0, 0, 0.5)] + [at("sights", 0.78 * math.cos(math.radians(a)), 0.78 * math.sin(math.radians(a)), 0.34, a + 180) for a in D4]
      + [sgn("entwine", 270, 0.86, 0.22), sgn("entwine", 90, 0.86, 0.22), sgn("strengthen", 180, 0.8, 0.22), sgn("strengthen", 0, 0.8, 0.22)],
      expect={"behaviors": {"aim", "bind"}}, manifest="capture",
      effect="A white ribbon flies to the enemy at the cursor, wraps around it and holds it in place."),
    S("magic_cookpot", "Magic Cookpot", "Magic Cookpot", "Magic Cookpot", "Magic_Cookpot_Seal_Redraw.png", TIME,
      traced=True, manifest="cookpot",
      effect="The flask in hand \"freezes in time\": its contents do not run low however much you pour, while the spell lasts."),
    S("washbarrel", "Washbarrel", "Washbarrel Seal", "Washbarrel Seal", "Washbarrel_Seal_Redraw_Ch83.png", TIME,
      traced=True, manifest="washbarrel",
      effect="The witch spins in a whirl of water: stains, poison, slime and fire wash away - all \"good as new\"."),
    S("spell_of_reduction", "Spell of Reduction", "Spell of Reduction", "Spell of Reduction", "Spell_of_Reduction_Redraw.png", TIME,
      traced=True, manifest="reduction",
      effect="Enemies at the cursor shrink: they become small and weak for a while."),
    S("counterclock", "Counterclock", "Counterclock", "Counterclock", "Counterclock_Redraw.png", TIME,
      traced=True, manifest="counterclock", status="whole",
      effect="Time runs back for the witch's things: the charges of the spells in their wands are restored."),
    S("leech_counterclock", "Valance Leech Counterclock", "Valance Leech Counterclock", "Valance Leech Counterclock",
      "Valance_Leech_Counterclock_Spell_Redraw.png", TIME,
      traced=True, manifest="counterclock_creatures", status="whole",
      effect="Time runs back for the creatures at the cursor: the transformed return to their former shape, enemies' wounds open again."),
    S("time_stop", "Time Stop", "Time Stop", "Time Stop", "Time_Stop_Spell_Redraw.png", TIME,
      traced=True, manifest="time_stop", status="whole",
      effect="Time stops at the cursor: enemies and projectiles inside freeze for a few seconds."),
    S("warmth_retention", "Warmth-Retention", "Warmth-Retention Seal (Archives)", "Warmth-Retention Seal", "Warmth-Retention_Seal_Redraw.png", TIME,
      traced=True, manifest="warmth_zone", status="whole",
      effect="Steady warmth stays at the cursor: it keeps anything from freezing and slowly melts ice."),
    # ------------------------------------------------------------ crystal
    S("crystal_ribbon", "Crystal Ribbon", "Crystal Ribbon", "Crystal Ribbon", "Anime_S1E11_Crystal_Ribbon.png", CRYSTAL,
      [frame("weave", 1.35, 180), sig("crystal", 0, 0.04, 0.46)],
      expect={"element": "crystal", "manifest": "ribbon"}, status="interpreted",
      note="The seal is not shown; the wiki: it works like the Boulder Stretch Rope, but with crystal.",
      effect="A sparkling ribbon of crystal stretches from the witch to the cursor - a bridge that shimmers like a rainbow."),
    S("crystal_shard", "Crystal Shard", "Crystal Shard", "Crystal Shard", "Crystal_Shard_Seal_Redraw.png", CRYSTAL,
      [sig("crystal", 0, 0, 0.44)] + around("column", C4, 0.62, 0.22, "out"),
      expect={"element": "crystal", "form": "dispersion"},
      effect="Huge crystals burst out of the seal in every direction, piercing enemies."),
    S("icy_road", "Icy Road", "Icy Road", "Icy Road", "Icy_Road_Seal_Redraw.png", CRYSTAL,
      [sig("crystal", 0, 0, 0.66)] + around("column", [i * 45 for i in range(8)], 0.82, 0.14, "out") + around("diamond", [22.5 + i * 45 for i in range(8)], 0.68, 0.14),
      expect={"element": "crystal"}, manifest="ice_road",
      effect="The air ahead of the witch freezes: an icy road lays itself from their feet to the cursor, water in the way freezes."),
    # ------------------------------------------------------------ illusion
    S("mirror_cloak", "Mirror Cloak of Borrowshade", "Mirror Cloak of Borrowshade", "Mirror Cloak Spell", "Mirror_Cloak_of_Borrowshade_Seal_Redraw.png", ILLUSION,
      traced=True, manifest="disguise", status="whole",
      effect="The witch takes the guise of the nearest beast: they look like it, and enemies of its kind take them for one of their own and do not attack. Only their look changes - they move and cast as themselves."),
    S("borrowshade", "Borrowshade", "Borrowshade", "Borrowshade", "Borrowshade_Seal_Redraw.png", ILLUSION,
      [sig("concealment", 0, 0, 0.6)] + around("envelop", D4, 0.72, 0.3),
      expect={"manifest": "shadow"},
      effect="The witch wraps up in shadow and becomes invisible to enemies."),
    S("makeover_mask", "Makeover Mask", "Makeover Mask Spell", "Makeover Mask Spell", "Makeover_Mask_Spell_Redraw.png", ILLUSION,
      [sig("concealment", 0, 0, 0.72), sgn("regions", 180, 0.82, 0.16), sgn("regions", 0, 0.82, 0.16), sgn("detection", 270, 0.8, 0.14, "in", 90),
       sgn("purify", 90, 0.8, 0.16)],
      expect={"manifest": "shadow"}, manifest="makeover",
      effect="The witch shines: stains and dirt vanish, sparkles all around; for a short while enemies cannot see them."),
    S("looking_glass", "Looking Glass", "Looking Glass", "Looking Glass", "Looking_Glass_Spell.png", ILLUSION,
      [sig("light", 0, 0, 0.36)] + around("detection", D4, 0.66, 0.22) + around("projection", C4, 0.7, 0.22),
      expect={"element": "light"}, manifest="scry", status="interpreted",
      note="The seal on the glass is only partly visible; here - light, detection and projection.",
      effect="Your sight flies ahead: for a couple of seconds you see what lies far towards the aim point, and the dark there lifts."),
    # ------------------------------------------------------------ sculpting
    S("smokesculpting", "Smokesculpting", "Smokesculpting Seal", "Smokesculpting Seal", "Smokesculpting_seal_redraw.png", SCULPT,
      traced=True, manifest="smoke_copies",
      effect="Smoke copies of the enemies rise beside them - the enemies get confused and strike at them."),
    S("illusion_cloak", "Beldaruit's Illusion Cloak", "Beldaruit's Illusion Cloak", "Beldaruit's Illusion Cloak Spell", "Beldaruit's_Illusion_Cloak_Spell_Redraw.png", SCULPT,
      traced=True, manifest="smoke_cloak",
      effect="A cloak and cap of smoke settle on the witch; the smoke hides them - enemies see the witch less well."),
    S("smokesculpture", "Smokesculpture", "Smokesculpture", "Smokesculpture", "36_32_Beldaruit_Smokesculpture.png", SCULPT,
      [sig("smoke", 0, 0, 0.5)] + around("mimicry", C4, 0.7, 0.3),
      expect={"element": "smoke", "behaviors": {"mimic"}}, manifest="smoke_clone", status="interpreted",
      note="The general smokesculpture seal is not shown; here - smoke and mimicry signs.",
      effect="A double of smoke rises beside the witch and copies their moves; enemies strike at the double."),
    S("sprite_winged", "Sprite-Winged Smokesculpture", "Sprite-Winged Smokesculpture", "Smokesculpture", "Volume_13_Coco_Illustration.jpg", SCULPT,
      [sig("smoke", 0, 0, 0.5)] + around("mimicry", C4, 0.7, 0.3) + around("levitation", D4, 0.7, 0.26),
      expect={"element": "smoke"}, manifest="smoke_fairy", status="interpreted",
      note="The seal is not shown; a smokesculpture with levitation.",
      effect="A small winged sprite of smoke flutters around the witch and distracts enemies."),
    S("dragon_smokesculpture", "Dragon Smokesculpture", "Dragon Smokesculpture", "Dragon Smokesculpture", "Beldaruit's_smoke_sculpture_spell_.png", SCULPT,
      [sig("smoke", 0, 0.42, 0.34), sig("dragon", 0, -0.2, 0.6)] + around("levitation", [200, 340], 0.72, 0.24),
      expect={"element": "smoke", "shape": "dragon"}, status="interpreted",
      note="The seal is only partly visible; here - smoke and the decorative dragon sigil.",
      effect="A dragon of smoke flies roaring over enemies and frightens them."),
    S("watersculpture", "Watersculpture", "Watersculpture", "Watersculpture", "32_14_Flipperfoal_Watersculpture.png", SCULPT,
      [sig("water", 0, 0.34, 0.34), sig("horse", 0, -0.3, 0.52)],
      expect={"element": "water", "shape": "horse"}, status="interpreted",
      note="There is no general watersculpture seal: water and a creature's decorative sigil.",
      cast={"element": "water"},
       effect="A foal of water gallops over the ground and knocks enemies down."),
    S("flying_watersculptures", "Flying Watersculptures", "Flying Watersculptures", "Flying Watersculptures", "62_9_Agott_Watersculptures_(Cropped).png", SCULPT,
      [sig("water", 0, 0, 0.36), sig("fish", -0.5, -0.4, 0.34), sig("bird", 0.5, -0.4, 0.34), sgn("purify", 150, 0.62, 0.2), sgn("purify", 30, 0.62, 0.2)],
      expect={"element": "water", "shape": "fish"}, status="interpreted",
      note="The seal on the cauldron is not visible; water, fish and bird over the Purify seal.",
      effect="A flock of fish and birds of water flies to the enemies at the cursor and drenches them."),
    S("torchstag", "Torchstag", "Torchstag Spell", "Torchstag Spell", "62.5_10_Torchstag_Spell_(2).png", SCULPT,
      [sig("fire", 0, 0.38, 0.36), sig("torchstag", 0, -0.28, 0.6)] + around("mimicry", [180, 0], 0.72, 0.3),
      expect={"element": "fire", "shape": "torchstag"}, status="interpreted",
      note="The partially visible seal is reconstructed with fire, the actual decorative torchstag sigil and mimicry.",
      effect="Fiery stags rush over the ground towards the aim point, setting fire to everything in their way."),
    # ------------------------------------------------------------ spatial
    S("windowway", "Windowway", "Windowway Seal", "Windowway Seal", "Windowway_Spell_Redraw_Ch._28.png", SPACE,
      [layer(0.8), band(28, 0.8), layer(0.72)],
      expect={"manifest": "portal"},
      effect="The first cast sets a window at the cursor, the second its pair; step into one and you come out of the other."),
    S("handheld_windowway", "Handheld Windowway", "Handheld Windowway", "Handheld Windowway", "Handheld_Windowway_Redraw.png", SPACE,
      traced=True, manifest="portal_small", ring=(999, 999, 910),  # the outermost of its three rings
      effect="A pair of small windows: projectiles that fly into one come out of the other."),
    S("doorknob", "Doorknob Doorway", "Doorknob Seal", "Doorknob-Determined Destination Doorway", "Doorknob_Seal_Redraw.png", SPACE,
      doorknob_seal(), whole_only=True, manifest="doorknob",
      cast={"element": "light", "form": "burst", "directed": False, "b": {}},
      effect="The first time, the doorknob remembers the place. After that every cast opens a door there - and the witch steps back to it."),
    # ------------------------------------------------------------ mixed
    S("wash_spring", "Wash Spring", "Wash Spring", "Wash Spring", "Wash_Spring_Seal_Redraw.png", MIXED,
      wash_spring_seal(), whole_only=True, manifest="wash_spring", cast={"element": "light", "form": "burst", "b": {}},
      effect="Everything around shines: water is purified, poison and toxic sludge become water, stains wash off the witch."),
    S("serpents_bed", "Serpent's Bed of Sand", "Serpent's Bed of Sand", "Serpent's Bed of Sand", "Serpent's_Bed_of_Sand_Redraw.jpg", MIXED,
      traced=True, manifest="sand_cloud", status="whole",
      effect="A great soft cloud of sand heaps up at the cursor out of sand drawn from the ground: you can stand and lie on it, it grows back where it is dug or blown away, and a beast that settles on it falls asleep."),
    S("vapor_bubble", "Vapor Bubble", "Vapor Bubble Spell", "Vapor Bubble Spell", "Vapor_Bubble_Redraw.png", MIXED,
      [layer(0.52), sig("water", 0, 0, 0.36), sig("wind", -0.76, 0, 0.3, 90), sig("wind", 0.76, 0, 0.3, 90)]
      + [sgn("column", a, 0.84, 0.14) for a in (270, 90, 215, 325, 145, 35)] + around("cooling", [242, 298, 62, 118], 0.82, 0.16)
      + [sgn("gathering", 270, 0.5, 0.3), sgn("gathering", 90, 0.5, 0.3)],
      expect={"element": "storm", "behaviors": {"gather", "cool"}}, manifest="vapor",
      effect="A ball of clean fresh water gathers out of the air and grows at the cursor - then falls."),
    S("rainflinger", "Rainflinger", "Rainflinger", "Rainflinger", "Rainflinger_Drying_Redraw.png", MIXED,
      [sig("wind", 0, 0, 0.8, 90), sig("fire", 0, -0.68, 0.28), sig("fire", 0, 0.68, 0.28, 180), sgn("crosshair", 180, 0.82, 0.3), sgn("crosshair", 0, 0.82, 0.3)],
      expect={"element": "firestorm", "behaviors": {"homing"}}, manifest="dry",
      effect="A warm wind dries everything at the target: water evaporates, the witch dries off and warms up."),
    S("waterflinger", "Waterflinger", "Waterflinger", "Waterflinger", "Waterflinger_Redraw.png", MIXED,
      [sig("water", 0, 0, 0.5), sig("fire", 0, -0.66, 0.26, 180), sig("fire", 0, 0.68, 0.26), sgn("crosshair", 180, 0.72, 0.3), sgn("crosshair", 0, 0.72, 0.3)],
      expect={"element": "steam", "behaviors": {"homing"}}, manifest="boil",
      effect="The liquid at the target boils and goes off as steam - it drains flooded passages."),
    S("floating_drops", "Floating Drops", "Floating Drops", "Floating Drops", "Floating_Drops_Redraw.png", MIXED,
      [sig("wind", 0, 0, 0.4), sig("water", -0.56, 0, 0.3, 90), sig("water", 0.56, 0, 0.3, -90)]
      + [s for a in (240, 300, 60, 120) for s in (sgn("regions", a - 8, 0.8, 0.12), sgn("regions", a + 8, 0.8, 0.12, "out"))],
      expect={"element": "storm", "form": "ring"},
      effect="Drops of water circle the witch: they put out fire and cool."),
    S("frozen_path", "Frozen Path", "Frozen Path", "Frozen Path", "Frozen_Path_Redraw.png", MIXED,
      [sig("water", 0, -0.1, 0.36), sgn("convergence", 270, 0.58, 0.2), sig("crystal", 0, 0.62, 0.3),
       at("column", -0.4, 0.02, 1.3, -90), at("column", 0.4, 0.02, 1.3, -90), sgn("column", 180, 0.82, 0.24), sgn("column", 0, 0.82, 0.24)],
      expect={"element": "ice"}, manifest="ice_road",
      effect="Water and air in the witch's way freeze into a road of ice - farther than the Icy Road's."),
    S("rushing_wave", "Rushing Wave", "Rushing Wave", "Rushing Wave", "Rushing_Wave_Redraw.png", MIXED,
      traced=True, manifest="wave",
      effect="A big wave of water rolls over the ground towards the aim point and sweeps enemies away."),
    S("sasaran_cloak", "Sasaran's Cloak", "Sasaran's Cloak Spell", "Sasaran's Cloak Spell", "Sasaran's_Cloak_Spell_Redraw.png", MIXED,
      traced=True, manifest="remote_cloak", status="whole",
      effect="A shadow cloak flies after the cursor; the book's next seals fly out of it, not from the witch's hands."),
    S("beastwarding", "Beastwarding", "Beastwarding Seal", "Beastwarding Seal", "Beastwarding_Seal_Redraw.png", MIXED,
      traced=True, manifest="beastward",
      effect="Pillars of light rise around the witch: beasts keep their distance and are pushed out of the circle."),
    S("fish_guidance", "Fish Guidance", "Fish Guidance", "Fish Guidance", "Fish_Guidance.png", MIXED,
      traced=True, manifest="guidance_fish",
      effect="A guidance mark is set at the cursor; fish of water fly to it and drench the enemies around."),
    S("pouch_guidance", "Pouch Guidance", "Pouch Guidance", "Pouch Guidance", "Pouch_Guidance_Redraw.png", MIXED,
      traced=True, manifest="guidance_items",
      effect="A guidance mark at the cursor: gold and small items around creep towards it."),
    S("sewer_grate", "Sewer Grate", "Sewer Grate", "Sewer Grate", "54_17_Sewer_Grate.png", MIXED,
      [sig("purification", 0, -0.1, 0.5), sig("water", 0, 0.5, 0.3)] + around("refuse", [150, 30], 0.72, 0.24, "out") + around("column", [210, 330], 0.72, 0.2),
      expect={"element": "water", "behaviors": {"purify"}}, status="interpreted", manifest="purify",
      note="The seal on the grate is small; the purification sigil, water, refuse signs.",
      effect="Dirty and poisonous liquid around is purified into water. It adds no water of its own."),
    S("boilfire_dragon", "Boilfire Dragon", "Boilfire Dragon", "Boilfire Dragon", "Boilfire_Dragon.png", MIXED,
      [sig("water", 0, 0.34, 0.34), sig("dragon", 0, -0.24, 0.6)] + around("expansion", [200, 340], 0.72, 0.24)
      + [link(1.5, 0.1, 0.42, sig("fire", 0, 0.05, 0.5), sgn("dispersion", 270, 0.66, 0.3), sgn("dispersion", 30, 0.66, 0.3), sgn("dispersion", 150, 0.66, 0.3))],
      expect={"element": "water", "shape": "dragon"}, manifest="dragon_steam", status="interpreted",
      note="Ring of Fire and Water Dragon merged: linked seals.",
      effect="A dragon of boiling water: it scalds everyone in its way with steam."),
    # ------------------------------------------------------------ niche
    S("forbidden_glow", "Forbidden Glow", "Forbidden Glow", "Forbidden Glow", "Forbidden_Glow_Redraw.png", NICHE,
      [sig("flicker", 0, 0, 0.32)] + around("column", C8, 0.74, 0.18),
      expect={"element": "flicker"},
      effect="Colorful fireworks of flickering lights."),
    S("forbidden_flames", "Forbidden Flames", "Forbidden Flames", "Forbidden Flames", "Forbidden_Flame_Seal_Redraw.png", NICHE,
      traced=True, manifest="forbidden_fire",
      effect="A small but unquenchable violet flame - it burns longer than ordinary fire."),
    S("billow_cluster", "Billow Cluster", "Billow Cluster", "Billow Cluster", "Billow_Cluster_Spell_Redraw.png", NICHE,
      [sig("billow", 0, 0, 0.5)] + around("collection", C4, 0.7, 0.3),
      expect={"manifest": "cloud", "behaviors": {"gather"}},
      effect="Powders and liquids around gather into a fluffy cloud at the cursor; you can stand on it."),
    S("sand_bridge", "Sand Bridge", "Sand Bridge", "Sand Bridge", "Sand_Bridge_Seal_Redraw.png", NICHE,
      [layer(0.56), sig("sand", 0, 0, 0.5), sig("bridging", -0.8, 0, 0.26, -90), sig("bridging", 0.8, 0, 0.26, 90)]
      + around("solidify", [255, 285, 75, 105], 0.8, 0.18) + around("immobility", [270, 90], 0.8, 0.16)
      + around("strengthen", D4, 0.78, 0.16) + around("column", [200, 340, 20, 160], 0.84, 0.12),
      expect={"element": "sand", "manifest": "bridge"},
      effect="An arched bridge of sand rises towards the aim point and hardens - you can walk across it."),
    S("mirror", "Mirror Spell", "Mirror Spell", "Mirror Spell", "Mirror_Spell_Redraw.png", NICHE,
      traced=True, manifest="mirror",
      effect="A mirror sphere around the witch: enemy projectiles are reflected back."),
    S("pouch_of_calling", "Pouch of Calling", "Pouch of Calling (Ch. 34)", "Pouch of Calling Seal", "Pouch_of_Calling_Redraw_Ch34.png", NICHE,
      [sig("calling", 0, 0, 0.78)] + around("convergence", D4, 0.72, 0.18),
      expect={"manifest": "lure"},
      effect="A pouch at the cursor runs about and calls out - enemies come running to it."),
    S("light_reducing", "Light-Reducing Spell", "Light-Reducing Spell", "Light-Reducing Spell", "Light_Reducing_Spell_Redraw.png", NICHE,
      traced=True, manifest="shade",
      effect="The witch's eyes are shielded: blindness and flashes do not affect them."),
    S("expansion_levitation", "Seal of Expansion and Levitation", "Seal of Expansion and Levitation", "Seal of Expansion and Levitation",
      "Seal_of_Expansion_and_Levitation_Redraw.png", NICHE,
      [sig("selection", 0, 0, 0.46)] + around("expansion", D4, 0.62, 0.42) + around("stability", C4, 0.8, 0.24)
      + around("column", [a + s for a in C4 for s in (-18, 18)], 0.84, 0.1),
      expect={"manifest": "book"},
      effect="The book grows and floats under the witch's feet - you can fly on it."),
    S("tracking", "Tracking Spell", "Tracking Spell", "Tracking Spell", "Tracking_Spell_Redraw.jpg", NICHE,
      traced=True, manifest="tracking",
      effect="Marks at the edge of sight point to the nearest chest, wand and orb."),
    S("garmentglimpse", "Garmentglimpse Glasses", "Garmentglimpse Glasses", "Garmentglimpse Glasses", "Garmentglimpse_Glasses_Redraw.png", NICHE,
      traced=True, manifest="xray",
      effect="The witch sees through walls: the dark around them lifts."),
    S("lockwax", "Lockwax", "Lockwax", "Lockwax", "Lockwax_Redraw.png", NICHE,
      traced=True, manifest="lockwax",
      effect="The enemy at the cursor is sealed with lockwax: it freezes and cannot attack."),
    S("glowing_owlcat", "Glowing Owlcat", "Glowing Owlcat", "Glowing Owlcat", "Glowing_Owlcat_Redraw.png", NICHE,
      [sig("owlcat", 0, 0.05, 0.92)],
      expect={"shape": "owlcat"},
      cast={"element": "light", "shape": "owlcat"},
       effect="A glowing owlcat flies after the witch, lights the way and pecks at enemies."),
    S("amplification", "Amplification Scroll", "Amplification Scroll", "Amplification Scroll", "Amplification_Scroll_Redraw.png", NICHE,
      traced=True, manifest="amplify",
      effect="The book's next three seals are twice as strong."),
    S("advanced_beastwarding", "Advanced Beastwarding", "Advanced Beastwarding", "Advanced Beastwarding", "Advanced_Beastwarding_Redraw.png", NICHE,
      traced=True, manifest="beastward_strong",
      effect="Like Beastwarding, but stronger and longer."),
    S("smoke_cloud", "Smoke Cloud", "Smoke Cloud", "Smoke Cloud", "Smoke_Cloud_Seal_Redraw.png", NICHE,
      [sig("smoke", 0, 0, 0.44)] + around("column", C8, 0.66, 0.16, "out"),
      expect={"element": "smoke", "form": "dispersion"},
      effect="A huge cloud of smoke spreads out from the witch: enemies inside go blind."),
    S("rainwarding", "Rainwarding", "Rainwarding Spell", "Rainwarding Spell", "Rain_Guard_Redraw.png", NICHE,
      [frame("rainward", 1.4)] + around("regions", C4, 0.84, 0.14) + around("cooling", D4, 0.78, 0.14),
      expect={"manifest": "umbrella"}, manifest="umbrella", whole_only=True,
      effect="A clear dome opens over the witch: liquids and projectiles from above do not get through."),
    S("loop_chalice", "Loop Chalice", "Loop Chalice", "Loop Chalice", "Loop_chalice_spell_redraw.png", NICHE,
      traced=True, manifest="chalice",
      effect="The liquid around rises and twists into a cone in the air, then flows back down."),
    S("spike", "Spike", "Spike", "Spike", "27_16_Sasaran_Spike.jpg", NICHE,
      [sig("earth", 0, 0, 0.63)] + around("pointing", C8, 0.7, 0.2, "out") + around("column", D4, 0.7, 0.16, "out"),
      expect={"element": "earth"}, manifest="spikes", status="interpreted",
      note="The seal is not shown; earth, pointing signs and inverted columns.",
      effect="Stone spikes burst out of the ground at the target and fly off in every direction."),
    S("wallwarding", "Wallwarding", "Wallwarding Seal", "Wallwarding Seal", "Wallwarding_Effect.png", NICHE,
      [sig("earth", 0, 0, 0.63)] + around("pull", C8, 0.7, 0.2, "out"),
      expect={"element": "earth", "behaviors": {"push"}}, manifest="wallward", status="interpreted",
      note="The seal is not shown; earth and inverted pulling - the walls part.",
      effect="The walls around the witch part - a roomy hollow is carved out around them."),
    S("flowers_of_sand", "Flowers of Sand", "Flowers of Sand", "Flowers of Sand", "24_14_Flowers_of_Sand_(2).png", NICHE,
      flower_seal(sig("sand", 0, 0, 0.38)), whole_only=True, middle=("sand", FLOWER_MIDDLE), manifest="bloom",
      cast={"element": "sand", "form": "burst", "b": {}},
      expect={"element": "sand", "manifest": "bloom"}, status="interpreted",
      note="The seal is not shown: the Flowers of Light seal with the sand sigil in place of the light crest.",
      effect="Hard flowers of sand grow at the cursor - you can stand on them."),
    S("playland_of_sand", "Playland of Sand", "Playland of Sand", "Playland of Sand", "Playland_of_Sand.png", NICHE,
      [sig("sand", 0, 0.1, 0.4), sig("bridging", 0, -0.46, 0.36)] + around("column", [200, 340], 0.72, 0.2)
      + [link(1.5, 0.0, 0.4, frame("flower", 1.9), sig("sand", 0, 0, 0.3))],
      expect={"element": "sand"}, manifest="sandcastle", status="interpreted",
      note="The Sand Bridge and Flowers of Sand seals, linked (Beldaruit joined his apprentices' spells).",
      effect="A sandcastle with towers and arches grows at the cursor."),
    S("sealchair", "Sealchair", "Sealchair Spell", "Sealchair Spell", "Sealchair_Glyph.jpg", NICHE,
      [sig("earth", 0, 0, 0.51), frame("dancing", 1.3)] + around("levitation", D4, 0.86, 0.14),
      expect={"manifest": "chair"}, manifest="chair", status="interpreted",
      note="The seal is too small to read; earth and dancing puppets - the chair walks by itself.",
      effect="The witch sits in a walking stone chair: it carries them over the ground."),
    S("snow_walking", "Snow-walking Spell", "Snow-walking Spell", "Snow-walking Spell", "Snow-walking_Spell.png", NICHE,
      [sig("wind", 0, 0, 0.44)] + around("stability", C4, 0.7, 0.28) + around("levitation", D4, 0.7, 0.2, "out"),
      expect={"element": "wind", "behaviors": {"still"}}, manifest="walk_liquid", status="interpreted",
      note="The seal is not shown; wind, level planes and inverted levitation.",
      effect="The witch walks on snow and water without sinking."),
    S("levitation_spell", "Levitation Spell", "Levitation Spell", "Levitation Spell", "Levitation_Spell_Cropped.png", NICHE,
      [sig("wind", 0, 0, 0.5)] + around("levitation", C8, 0.74, 0.2),
      expect={"element": "wind", "form": "levitation"}, manifest="levitate", status="interpreted",
      note="The seal is partly visible; wind and levitation signs.",
      effect="The witch rises smoothly and floats."),
    S("lightning_spell", "Lightning Spell", "Lightning Spell", "Lightning Spell", "Lightning_Spell_Cropped.png", NICHE,
      [sig("lightning", 0, 0, 0.5)] + around("column", C4, 0.74, 0.26),
      expect={"element": "thunder", "form": "column"}, status="interpreted",
      note="The seal is not shown; the lightning sigil (unofficial) and columns.",
      effect="A lightning strike where you aim."),
    S("replication", "Replication Magic", "Replication Magic", "Replication Magic", "Replication_Magic.png", NICHE,
      [sig("earth", 0, 0, 0.63)] + around("mimicry", [200, 340], 0.7, 0.3) + around("column", [270], 0.7, 0.3, "out") + around("gathering", [90], 0.66, 0.26),
      expect={"element": "earth"}, manifest="stone_arm", status="interpreted",
      note="The seal is not shown; stone repeats itself - an arm of stone grows.",
      effect="A stone arm grows out of the rock at the cursor, reaching towards the aim point."),
    S("mist_basin", "Mist Basin", "Mist Basin", "Mist Basin", "89_15_Mist_Basin.png", NICHE,
      [sig("water", 0, 0, 0.4), sig("wind", 0, 0.5, 0.26)] + around("dispersion", [200, 340], 0.7, 0.26),
      expect={"element": "storm"}, manifest="mist", status="interpreted",
      note="The seal is not shown; water, wind and dispersion.",
      effect="Thick mist covers everything around - enemies lose sight of the witch."),
    # ------------------------------------------------------------ forbidden
    S("petrification", "Petrification", "Petrification", "Petrification", "Petrification_Seal_WHA_BTS_Pt_10.jpeg", FORBIDDEN,
      traced=True, manifest="petrify", forbidden=True, status="whole", crop=(0, 0, 2476, 2414), trace_size=1600, book="tome",
      note="The anime's seal (the copyright line under it cut off), traced finely: it fills a Great Tome's page.",
      effect="Forbidden magic: a grey aura grows slowly from the target and turns everything inside it to stone - rock, "
             "water, creatures, and the witch too if they don't get away in time. The Knights Moralis come for it."),
    S("dragons_labyrinth", "Dragon's Labyrinth", "Seal of the Dragon's Labyrinth", "Seal of the Dragon's Labyrinth", "Illusory_labyrinth_spell_redraw_complete.png", FORBIDDEN,
      traced=True, manifest="labyrinth", forbidden=True, status="whole",
      effect="Forbidden magic: space at the target closes on itself - whoever leaves over the edge comes back from the other side."),
    S("memory_erasure", "Memory Erasure", "Memory Erasure", "Memory Erasure", "Memory_Erasure_Spell_Ininia2.jpg", FORBIDDEN,
      [sig("obliviation", 0, -0.1, 0.5)] + [glaive(a) for a in (60, 90, 120)] + around("diamond", [200, 230, 260, 280, 310, 340], 0.82, 0.08),
      expect={"manifest": "oblivion"}, forbidden=True, status="interpreted",
      note="The obliviation sigil and glaives along the edge, as on the Knights Moralis' seals.",
      effect="Enemies around forget the witch and stop attacking. Allowed to the Knights Moralis only."),
    S("healingcraft", "Healingcraft", "Healingcraft", "Healingcraft", "Anime_S1E09_Healingcraft.png", FORBIDDEN,
      [sig("water", 0, 0.05, 0.4)] + [glaive(a) for a in (45, 135, 225, 315)] + around("convergence", C4, 0.7, 0.2) + around("purify", D4, 0.7, 0.2),
      expect={"element": "ice"}, manifest="heal", forbidden=True, status="interpreted",
      note="No healingcraft seals survive; water, purification, convergence and glaives - magic on the body.",
      effect="Forbidden magic: the witch's wounds close. The Knights Moralis come for it."),
    S("golem", "Golem", "Golem", "Golem", "Golem_Cropped.png", FORBIDDEN,
      [sig("earth", 0, 0.1, 0.6), sig("horse", 0, -0.46, 0.4)] + [glaive(a) for a in (80, 100)] + around("strengthen", [200, 340], 0.7, 0.24),
      expect={"element": "earth"}, manifest="golem", forbidden=True, status="interpreted",
      note="The golem's seal is not shown; earth, a creature sigil and glaives.",
      effect="Forbidden magic: the ground's own stones stand up as a golem of brickwork. It walks after the witch and brings its fist down on every enemy that comes near; enemies turn on it. It falls apart when it is broken or the spell ends."),
    S("scalewolf_curse", "Scalewolf Curse", "Scalewolf Curse", "Scalewolf Curse", "Scalewolf_Curse_Redraw.png", FORBIDDEN,
      scalewolf_curse_seal(), whole_only=True, manifest="wolf_curse", forbidden=True, status="whole",
      effect="Forbidden magic: the enemy at the cursor turns into a wolf."),
    S("anti_scalewolf", "Anti Scalewolf Curse", "Anti Scalewolf Curse", "Anti Scalewolf Curse", "Anti_Scalewolf_Spell.png", FORBIDDEN,
      [sig("water", 0, 0.1, 0.4)] + [glaive(a) for a in (250, 290)] + around("crush", [200, 340], 0.7, 0.24, "out") + around("convergence", [150, 30], 0.7, 0.2),
      expect={"element": "ice"}, manifest="unpolymorph", forbidden=True, status="interpreted",
      note="The seal is not shown.",
      effect="Forbidden magic: transformed creatures nearby return to their own shape."),
    S("slime_rendering", "Slime Rendering", "Slime Rendering Seal", "Slime Rendering Seal", "63_3_Slime_Rendering_Seal.png", FORBIDDEN,
      [sig("water", 0, 0.05, 0.4), sig("earth", 0, -0.5, 0.3)] + [glaive(a) for a in (30, 90, 150, 210, 330)] + around("crush", [200, 340], 0.7, 0.22),
      expect={"element": "mud"}, manifest="slime", forbidden=True, status="interpreted",
      note="The seal is seen only on a body; glaives along the edge - magic on the body.",
      effect="Forbidden magic: the enemy at the cursor melts into slime."),
]

BY_KEY = {s.key: s for s in SPELLS}
