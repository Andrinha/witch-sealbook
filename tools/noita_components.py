"""What the game knows about components: every component type with its fields, from the modding docs
(tools_modding/component_documentation.txt) plus the fields of sub-objects (config_explosion, ...) as the
game's own entity files use them. The game silently ignores an unknown component or field, so a typo in an
entity file just makes an effect quietly not work: check_entities.py and the offline tests catch it here.

    fields = known_components()             # {"ProjectileComponent": {"lifetime", ...}, ...}
    problems = check_component(fields, "LightComponent", {"radius": 1, "r": 2})
"""
import os
import re
import xml.etree.ElementTree as ET

NOITA = r"C:\Program Files (x86)\Steam\steamapps\common\Noita"
DOCS = os.path.join(NOITA, "tools_modding", "component_documentation.txt")
# the game's data unpacked from data.wak (see ../reference/noita_data)
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reference", "noita_data")
SPECIAL = {"_tags", "_enabled"}  # accepted by every component

_cache = {}


def known_components():
    """{component type: set of field names}; sub-object fields as 'object.field'. None if the docs are missing."""
    if "fields" in _cache:
        return _cache["fields"]
    if not os.path.exists(DOCS):
        _cache["fields"] = None
        return None
    fields, current = {}, None
    for line in open(DOCS, encoding="utf-8", errors="replace"):
        if re.match(r"^[A-Z][A-Za-z0-9_]*Component\s*$", line):
            current = line.strip()
            fields.setdefault(current, set())
        elif current and line.startswith("    "):
            parts = line.split()
            # "type name default ..." - the type may contain spaces ("unsigned int", "std::vector<int>")
            # Long enum type names can run into the member column in Noita's
            # generated docs, e.g. PARTICLE_EMITTER_CUSTOM_STYLE::Enumcustom_style.
            m = (re.match(r"^\s+(\S+::Enum)([A-Za-z_]\w*)\s", line)
                 or re.match(r"^\s+(unsigned int|std::vector<[^>]+>|\S+)\s+(\S+)", line))
            if m and len(parts) >= 2:
                fields[current].add(m.group(2))
    # sub-objects and vector-ish fields as the game's own files write them
    if os.path.isdir(DATA):
        for root, _, files in os.walk(os.path.join(DATA, "data", "entities")):
            for f in files:
                if not f.endswith(".xml"):
                    continue
                try:
                    tree = ET.parse(os.path.join(root, f))
                except ET.ParseError:
                    continue
                for comp in tree.iter():
                    if comp.tag in fields:
                        for child in comp:
                            for attr in child.attrib:
                                fields[comp.tag].add(child.tag + "." + attr)
    _cache["fields"] = fields
    return fields


def check_component(fields, kind, values, where=""):
    """Problems with one component: an unknown type or unknown fields"""
    if fields is None:
        return []
    if kind not in fields:
        return [f"{where}unknown component {kind}"]
    known = fields[kind]
    out = []
    for name in values:
        if name in SPECIAL or name in known:
            continue
        base = name.split(".")[0]  # vec2 / ValueRange / aabb: field.x, field.min, field.max_x
        if base in known:
            continue
        out.append(f"{where}{kind}: unknown field '{name}'")
    return out


def check_entity_xml(text, where=""):
    """Problems with an entity file's text (a mod file or one made by the mod at init)"""
    fields = known_components()
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        return [f"{where}broken XML: {e}"]
    out = []

    def walk(node):
        for child in node:
            if child.tag == "Base" or child.tag == "Entity":
                walk(child)
            elif child.tag.endswith("Component"):
                values = dict(child.attrib)
                for sub in child:  # config_explosion, damage_by_type, gun_config, ...
                    for attr in sub.attrib:
                        values[sub.tag + "." + attr] = sub.attrib[attr]
                out.extend(check_component(fields, child.tag, values, where))
    walk(root)
    return out
