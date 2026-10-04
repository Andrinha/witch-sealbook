"""Read the real visible SpriteComponents from the mock world for previews/tests."""
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Sprite:
    path: str
    x: float
    y: float
    alpha: float = 1
    additive: bool = False
    component: int = 0
    scale: float = 1
    scale_y: float = 1


def sprites(lua, layer="body"):
    world = lua.globals().W
    result = []
    for entity in world.entities.values():
        if not entity.alive or not entity.tags["witch_fluid_fire_visual"]:
            continue
        for cid in entity.comps.values():
            component = world.comps[cid]
            if not component or component.type != "SpriteComponent" or not component.enabled:
                continue
            values = component["values"]
            if values.visible is False:
                continue
            if layer is not None and bool(values.additive) != (layer == "glow"):
                continue
            offset = values.transform_offset
            x, y = (offset[1], offset[2]) if offset else (0, 0)
            result.append(Sprite(values.image_file, entity.x + x, entity.y + y,
                                 values.alpha if values.alpha is not None else 1,
                                 bool(values.additive), cid,
                                 values.special_scale_x if values.has_special_scale else 1,
                                 values.special_scale_y if values.has_special_scale else 1))
    # Native z indices draw all bodies before the additive layer.
    return sorted(result, key=lambda s: s.additive)


@lru_cache(maxsize=128)
def texture(path):
    with Image.open(ROOT / path.removeprefix("mods/witch_notebook/")) as source:
        return source.convert("RGBA")


def draw_sprites(canvas, samples, offset_x=0, offset_y=0, scale=1):
    """Approximate native source-alpha blending; no extra bloom hides seams."""
    for sample in samples:
        image = texture(sample.path)
        if sample.scale != 1 or sample.scale_y != 1:
            width = max(1, round(image.width * sample.scale))
            height = max(1, round(image.height * sample.scale_y))
            image = image.resize((width, height), Image.Resampling.BILINEAR)
        if scale != 1:
            image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.NEAREST)
        alpha = image.getchannel("A").point(lambda a: round(a * sample.alpha))
        x, y = round(sample.x * scale + offset_x - image.width / 2), round(sample.y * scale + offset_y - image.height / 2)
        left, top = max(0, x), max(0, y)
        right, bottom = min(canvas.width, x + image.width), min(canvas.height, y + image.height)
        if left >= right or top >= bottom:
            continue
        if sample.additive:
            emission = Image.new("RGB", image.size)
            emission.paste(image.convert("RGB"), (0, 0), alpha)
            patch = emission.crop((left - x, top - y, right - x, bottom - y))
            canvas.paste(ImageChops.add(canvas.crop((left, top, right, bottom)), patch), (left, top))
        else:
            canvas.paste(image.convert("RGB"), (x, y), alpha)
    return canvas
