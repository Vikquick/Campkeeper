"""Generate Campkeeper/Data/Catalog.lua from tools/catalog_tiers.json and a client scan.

    python tools/gen_catalog.py            # write the catalog
    python tools/gen_catalog.py --check    # exit 1 if the committed catalog is out of date

The scan comes from the ForeverApiDump addon: `/fad scan camp`, `/reload`, then
`python tools/fad.py json <SavedVariables>\\ForeverApiDump.lua` writes out/scan.json.
Spells are matched to items by name inside the same scan, so the scan locale does not matter.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIERS = ROOT / "tools" / "catalog_tiers.json"
SCAN = ROOT / "out" / "scan.json"
OUT = ROOT / "Campkeeper" / "Data" / "Catalog.lua"

ROLES = ("leveling", "dungeon", "craft")
KINDS = {"buff", "vendor", "rest", "reagent", "station", "gather", "utility", "food"}
# Craft spells read "Изготовить X." / "Create X."; placement ones "Создает…" / "Creates…" — whole word only.
_CRAFT = re.compile(r"(Изготовить|Развести|Create|Craft|Build|Make)\s")
_REPLACES = re.compile(r"на месте|placed over", re.IGNORECASE)
_REQUIRES = re.compile(r"\((\d+)\)\s*$")


class CatalogError(Exception):
    def __init__(self, problems):
        super().__init__("\n".join(problems))
        self.problems = problems


def _spells_by_name(scan):
    by_name = {}
    for sid, s in scan.get("spells", {}).items():
        if s.get("name"):
            by_name.setdefault(s["name"], []).append((int(sid), s))
    for lst in by_name.values():
        lst.sort(key=lambda p: p[0])
    return by_name


def _split_spells(candidates):
    """Split same-named spells into (craft spell ids, placement spells)."""
    craft, place = [], []
    for sid, s in candidates:
        desc = (s.get("description") or "").strip()
        if not desc:
            continue  # auras and visuals share names but have no description
        (craft if _CRAFT.match(desc) else place).append((sid, s))
    return [sid for sid, _ in craft], place


def _resolve_item(owner, item_id, scan, by_name, skill, problems):
    item = scan.get("items", {}).get(str(item_id))
    if not item or not item.get("name"):
        problems.append(f"{owner}: item {item_id} not found in scan")
        return None
    reqs = [l for l in item.get("tooltip") or [] if isinstance(l, str) and _REQUIRES.search(l)
            and ":" in l and not l.split(":", 1)[0].strip().startswith(("Использование", "Use"))]
    if reqs:
        found = int(_REQUIRES.search(reqs[-1]).group(1))
        if found != skill:
            problems.append(f"{owner}: item {item_id} requires skill {found}, table says {skill}")
    spell_name = item.get("spellName") or item["name"]
    craft, place = _split_spells(by_name.get(spell_name, []))
    if not place:
        problems.append(f"{owner}: no placement spell named {spell_name!r} for item {item_id}")
    return {"craft": craft, "place": place}


def build(tiers, scan, previous_order=None):
    """Resolve the table against the scan. Raises CatalogError listing every problem."""
    problems = []
    by_name = _spells_by_name(scan)
    professions = tiers["professions"]
    class_buffs = tiers["classBuffs"]

    fires = []
    for f in tiers["fires"]:
        r = _resolve_item(f"fire T{f['tier']}", f["item"], scan, by_name, f["skill"], problems)
        if r:
            fires.append({"tier": f["tier"], "item": f["item"], "skill": f["skill"], "slots": f["slots"],
                          "burn": f["burn"], "place": r["place"][0][0] if r["place"] else None,
                          "craft": r["craft"][0] if r["craft"] else None})

    objects, families, order = {}, {}, []
    for fam in tiers["families"]:
        if fam["profession"] not in professions:
            problems.append(f"{fam['key']}: unknown profession {fam['profession']}")
        for b in fam["exclusiveWith"]:
            if b not in class_buffs:
                problems.append(f"{fam['key']}: unknown class buff {b}")
        if set(fam["weights"]) != set(ROLES):
            problems.append(f"{fam['key']}: weights must cover {', '.join(ROLES)}")
        t1 = next((o["key"] for o in fam["objects"] if o["tier"] == 1), None)
        keys = []
        for o in fam["objects"]:
            key = o["key"]
            if key in objects:
                problems.append(f"{key}: duplicate object key")
            if o["kind"] not in KINDS:
                problems.append(f"{key}: unknown kind {o['kind']}")
            place, craft = [], []
            for item_id in o["items"]:
                r = _resolve_item(key, item_id, scan, by_name, o["skill"], problems)
                if r:
                    place += [sid for sid, _ in r["place"] if sid not in place]
                    craft += [sid for sid in r["craft"] if sid not in craft]
            replaces = None
            if o["tier"] > 1 and t1:
                descs = [scan["spells"][str(sid)].get("description") or "" for sid in place]
                if any(_REPLACES.search(d) for d in descs):
                    replaces = t1
            # T1 benefits carry over to the objects that replace it
            exclusive = list(fam["exclusiveWith"]) if (o["tier"] == 1 or replaces) else []
            objects[key] = {"family": fam["key"], "profession": fam["profession"], "tier": o["tier"],
                            "skill": o["skill"], "kind": o["kind"], "items": list(o["items"]),
                            "place": place, "craft": craft[0] if craft else None,
                            "replaces": replaces, "exclusiveWith": exclusive}
            keys.append(key)
            order.append(key)
        families[fam["key"]] = {"profession": fam["profession"], "objects": keys, "weights": fam["weights"]}

    if previous_order and order[:len(previous_order)] != list(previous_order):
        moved = next((a for a, b in zip(previous_order, order) if a != b), None)
        problems.append(f"object order changed at {moved!r}: append new objects only (protocol bit order)")

    if problems:
        raise CatalogError(problems)
    return {"auras": tiers["auras"], "professions": professions, "classBuffs": class_buffs,
            "fires": fires, "objects": objects, "families": families, "order": order}


# ---------------------------------------------------------------- Lua output

def _lua(v, indent=""):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    inner = indent + "  "
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(_lua(x) for x in v) + " }" if v else "{}"
        return "{\n" + "".join(f"{inner}{_lua(x, inner)},\n" for x in v) + indent + "}"
    if isinstance(v, dict):
        items = [(k, x) for k, x in sorted(v.items()) if x is not None]
        if not items:
            return "{}"
        def key(k):
            return k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) else f"[{json.dumps(k)}]"
        if all(not isinstance(x, (dict, list)) for _, x in items) and len(items) <= 4:
            return "{ " + ", ".join(f"{key(k)} = {_lua(x)}" for k, x in items) + " }"
        return "{\n" + "".join(f"{inner}{key(k)} = {_lua(x, inner)},\n" for k, x in items) + indent + "}"
    raise TypeError(type(v))


def render(catalog):
    return ("-- Generated by tools/gen_catalog.py from tools/catalog_tiers.json and a client scan.\n"
            "-- Do not edit by hand: change the table and regenerate.\n"
            "local _, ns = ...\n\n"
            f"ns.CatalogData = {_lua(catalog)}\n")


def previous_order(path: Path):
    if not path.is_file():
        return None
    m = re.search(r"\border = \{ (.*?) \}", path.read_text(encoding="utf-8"), re.DOTALL)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tiers", default=str(TIERS))
    ap.add_argument("--scan", default=str(SCAN))
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--check", action="store_true", help="do not write; exit 1 if output differs")
    args = ap.parse_args(argv)
    out = Path(args.out)
    tiers = json.loads(Path(args.tiers).read_text(encoding="utf-8"))
    scan = json.loads(Path(args.scan).read_text(encoding="utf-8"))
    try:
        catalog = build(tiers, scan, previous_order(out))
    except CatalogError as e:
        for p in e.problems:
            print(f"error: {p}", file=sys.stderr)
        return 1
    text = render(catalog)
    if args.check:
        current = out.read_text(encoding="utf-8") if out.is_file() else ""
        if current != text:
            print(f"{out} is out of date; run tools/gen_catalog.py", file=sys.stderr)
            return 1
        print("catalog up to date")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {out} ({len(catalog['objects'])} objects, {len(catalog['fires'])} fires)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
