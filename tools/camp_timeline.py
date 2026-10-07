"""Readable timeline of a /fad camp probe log.

  python tools/camp_timeline.py out/camp-log.json [--events] [--tooltips]
"""

import argparse
import json


def where(e):
    p = e.get("pos") or {}
    x, y = p.get("x"), p.get("y")
    xy = f"{x * 100:.2f},{y * 100:.2f}" if isinstance(x, (int, float)) and isinstance(y, (int, float)) else "?"
    return f"{e['clock']} [{p.get('mapID')} {xy}]"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--events", action="store_true", help="include generic events")
    ap.add_argument("--tooltips", action="store_true", help="include tooltips")
    args = ap.parse_args()
    log = json.load(open(args.log, encoding="utf-8"))

    for e in log:
        k = e["kind"]
        if k == "mark":
            print(where(e), "##### MARK", e.get("note"))
        elif k == "cast":
            print(where(e), "CAST", e.get("event"), e.get("spellID"), e.get("name"))
        elif k.startswith("aura"):
            print(where(e), k.upper(), e.get("spellId"), e.get("name"), "dur", e.get("duration"),
                  "exp", e.get("expirationTime"), "src", e.get("sourceUnit"), "pts", e.get("points"),
                  "id", e.get("auraInstanceID"))
            if e.get("tooltip"):
                print("      TT:", e["tooltip"])
        elif k in ("vignette_added", "vignette_removed", "soft_interact"):
            print(where(e), k.upper(), {x: y for x, y in e.items() if x not in ("pos", "kind", "t", "clock")})
        elif k == "tooltip" and args.tooltips:
            print(where(e), "TOOLTIP", e.get("type"), e.get("id"), e.get("guid"), e.get("lines"))
        elif k == "event" and args.events:
            print(where(e), "EVENT", e.get("event"), e.get("n"), e.get("args"))
        elif k in ("probe_start", "probe_stop"):
            print(where(e), k, {x: y for x, y in e.items() if x not in ("pos", "kind", "t", "clock")})


if __name__ == "__main__":
    main()
