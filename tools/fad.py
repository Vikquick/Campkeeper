"""Offline tools for ForeverApiDump SavedVariables.

  python tools/fad.py json   <ForeverApiDump.lua> -o dump.json
  python tools/fad.py report <ForeverApiDump.lua> -o reference.md
  python tools/fad.py diff   <forever.lua> <retail.lua> -o diff.md
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# SavedVariables (Lua table literal) parser
# ---------------------------------------------------------------------------

_TOKEN = re.compile(
    r"""
    (?P<ws>\s+|--[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.|\\\n)*")
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)|-?inf|nan|-nan)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<sym>[{}\[\]=,;])
    """,
    re.VERBOSE | re.DOTALL,
)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
            "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(body):
    i = 0
    raw = bytearray()
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            raw += ch.encode("utf-8")
            i += 1
            continue
        nxt = body[i + 1]
        if nxt.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1:])
            raw.append(int(m.group()))
            i += 1 + len(m.group())
        else:
            raw += _ESCAPES.get(nxt, nxt).encode("utf-8")
            i += 2
    return raw.decode("utf-8", errors="replace")


def _tokens(text):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"unexpected input at {pos}: {text[pos:pos + 40]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind != "ws":
            yield kind, m.group()


class _Parser:
    def __init__(self, text):
        self.toks = list(_tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, expected=None):
        tok = self.peek()
        if expected is not None and tok[1] != expected:
            raise ValueError(f"expected {expected!r}, got {tok!r} at token {self.i}")
        self.i += 1
        return tok

    def value(self):
        kind, text = self.take()
        if kind == "str":
            return _unescape(text[1:-1])
        if kind == "num":
            if "inf" in text or "nan" in text:
                return float(text)
            return int(text, 0) if re.fullmatch(r"-?(0[xX][0-9a-fA-F]+|\d+)", text) else float(text)
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[text]
        if text == "{":
            return self.table()
        raise ValueError(f"unexpected token {text!r}")

    def table(self):
        result, array = {}, []
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            elif self.peek()[0] == "name" and self.toks[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                result[key] = self.value()
            else:
                array.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        for n, v in enumerate(array, 1):
            result[n] = v
        # Pure 1..n integer keys become a list
        if result and all(isinstance(k, int) for k in result) and sorted(result) == list(range(1, len(result) + 1)):
            return [result[k] for k in range(1, len(result) + 1)]
        return result

    def chunk(self):
        out = {}
        while self.peek()[0] is not None:
            name = self.take()[1]
            self.take("=")
            out[name] = self.value()
        return out


def load_saved_variables(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    return _Parser(text).chunk()


def load_dump(path):
    db = load_saved_variables(path).get("ForeverApiDumpDB") or {}
    dump = db.get("dump")
    if not dump:
        sys.exit(f"{path}: no dump found — run /fad dump and /reload in game")
    dump["events_seen"] = db.get("events") or {}
    return dump


# ---------------------------------------------------------------------------
# API documentation model
# ---------------------------------------------------------------------------

_STD_KEYS = {"Name", "Type", "Arguments", "Returns", "Payload", "Documentation",
             "LiteralName", "Fields", "Nilable", "Default", "InnerType", "Mixin",
             "System", "Namespace", "Functions", "Events", "Tables", "Callbacks",
             "EnumValue", "MinValue", "MaxValue", "NumValues", "StrideIndex"}


def _as_list(v):
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(v, key=str)]
    return []


def _systems(dump):
    return [s for s in _as_list(dump.get("apidocs")) if isinstance(s, dict)]


def _param(p):
    t = p.get("Type", "?")
    if p.get("InnerType"):
        t = f"{t}<{p['InnerType']}>"
    s = f"{p.get('Name', '?')}: {t}"
    if p.get("Nilable"):
        s += "?"
    if "Default" in p:
        s += f" = {p['Default']}"
    return s


def _extra_flags(item):
    """Non-standard fields, e.g. Midnight's secret-value annotations."""
    return {k: v for k, v in item.items() if k not in _STD_KEYS and not isinstance(v, (dict, list))}


def api_index(dump):
    """{qualified name: {'kind', 'signature', 'flags', 'system'}}"""
    index = {}
    for sys_ in _systems(dump):
        ns = sys_.get("Namespace")
        for fn in _as_list(sys_.get("Functions")):
            name = f"{ns}.{fn.get('Name')}" if ns else fn.get("Name")
            args = ", ".join(_param(a) for a in _as_list(fn.get("Arguments")))
            rets = ", ".join(_param(r) for r in _as_list(fn.get("Returns")))
            index[name] = {"kind": "function", "system": sys_.get("Name"),
                           "signature": f"{name}({args})" + (f" -> {rets}" if rets else ""),
                           "flags": _extra_flags(fn)}
        for ev in _as_list(sys_.get("Events")):
            lit = ev.get("LiteralName") or ev.get("Name")
            payload = ", ".join(_param(a) for a in _as_list(ev.get("Payload")))
            index[lit] = {"kind": "event", "system": sys_.get("Name"),
                          "signature": f"{lit}({payload})", "flags": _extra_flags(ev)}
    return index


def _fmt_flags(flags):
    return " `" + ", ".join(f"{k}={v}" for k, v in sorted(flags.items())) + "`" if flags else ""


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_json(args):
    dump = load_dump(args.dump)
    Path(args.output).write_text(json.dumps(dump, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"wrote {args.output}")


def _meta_line(dump):
    m = dump.get("meta", {})
    return f"{m.get('version')} build {m.get('build')}, interface {m.get('interface')}, locale {m.get('locale')}"


def cmd_report(args):
    dump = load_dump(args.dump)
    lines = [f"# API reference — {_meta_line(dump)}", ""]
    for note in _as_list(dump.get("notes")):
        lines.append(f"> {note}")
    for sys_ in sorted(_systems(dump), key=lambda s: str(s.get("Namespace") or s.get("Name"))):
        ns = sys_.get("Namespace")
        lines += ["", f"## {ns or sys_.get('Name')}"]
        for item in sorted(api_index({"apidocs": [sys_]}).values(), key=lambda v: (v["kind"], v["signature"])):
            lines.append(f"- {item['kind'][0].upper()} `{item['signature']}`{_fmt_flags(item['flags'])}")

    documented = api_index(dump)
    undocumented = sorted(
        f"{ns}.{m}" for ns, members in (dump.get("namespaces") or {}).items()
        for m, t in members.items() if t == "function"
        and f"{ns}.{m}" not in documented)
    lines += ["", f"## Undocumented C_ functions ({len(undocumented)})", ""]
    lines += [f"- `{n}`" for n in undocumented]

    seen = dump.get("events_seen") or {}
    if seen:
        lines += ["", f"## Events observed in play ({len(seen)})", ""]
        for ev in sorted(seen):
            e = seen[ev]
            lines.append(f"- `{ev}` x{e.get('count')} args: {', '.join(_as_list(e.get('args'))) or '-'}")

    Path(args.output).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")


def _set_diff(title, a, b, name_a, name_b, lines, limit=None):
    only_a, only_b = sorted(a - b), sorted(b - a)
    lines += ["", f"## {title}", "", f"{name_a} only: {len(only_a)}, {name_b} only: {len(only_b)}, common: {len(a & b)}"]
    for label, items in ((name_a, only_a), (name_b, only_b)):
        if items:
            lines += ["", f"### Only in {label}", ""]
            shown = items if limit is None else items[:limit]
            lines += [f"- `{x}`" for x in shown]
            if len(shown) < len(items):
                lines.append(f"- … and {len(items) - len(shown)} more")


def _enum_keys(dump):
    out = set()
    for name, members in (dump.get("enums") or {}).items():
        out.add(f"Enum.{name}")
        if isinstance(members, dict):
            out.update(f"Enum.{name}.{k}" for k in members)
    return out


def _cvar_names(dump):
    return {c.get("command") for c in _as_list(dump.get("cvars")) if isinstance(c, dict) and c.get("command")}


def cmd_diff(args):
    a, b = load_dump(args.a), load_dump(args.b)
    na, nb = args.name_a, args.name_b
    lines = [f"# {na} vs {nb}", "", f"- {na}: {_meta_line(a)}", f"- {nb}: {_meta_line(b)}"]

    ga, gb = a.get("globals") or {}, b.get("globals") or {}
    _set_diff("Global functions", {k for k, t in ga.items() if t == "function"},
              {k for k, t in gb.items() if t == "function"}, na, nb, lines, args.limit)
    _set_diff("C_ namespaces", set(a.get("namespaces") or {}), set(b.get("namespaces") or {}), na, nb, lines)

    def members(d):
        return {f"{ns}.{m}" for ns, ms in (d.get("namespaces") or {}).items() for m in ms}
    _set_diff("C_ namespace members", members(a), members(b), na, nb, lines, args.limit)

    ia, ib = api_index(a), api_index(b)
    _set_diff("Documented events", {k for k, v in ia.items() if v["kind"] == "event"},
              {k for k, v in ib.items() if v["kind"] == "event"}, na, nb, lines, args.limit)

    changed = [k for k in sorted(set(ia) & set(ib))
               if (ia[k]["signature"], ia[k]["flags"]) != (ib[k]["signature"], ib[k]["flags"])]
    lines += ["", f"## Changed signatures or flags ({len(changed)})", ""]
    for k in changed:
        lines += [f"- {na}: `{ia[k]['signature']}`{_fmt_flags(ia[k]['flags'])}",
                  f"  {nb}: `{ib[k]['signature']}`{_fmt_flags(ib[k]['flags'])}"]

    _set_diff("Enums", _enum_keys(a), _enum_keys(b), na, nb, lines, args.limit)
    _set_diff("CVars and console commands", _cvar_names(a), _cvar_names(b), na, nb, lines, args.limit)

    Path(args.output).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    j = sub.add_parser("json", help="convert SavedVariables to JSON")
    j.add_argument("dump")
    j.add_argument("-o", "--output", default="dump.json")
    j.set_defaults(func=cmd_json)

    r = sub.add_parser("report", help="markdown API reference")
    r.add_argument("dump")
    r.add_argument("-o", "--output", default="reference.md")
    r.set_defaults(func=cmd_report)

    d = sub.add_parser("diff", help="compare two dumps")
    d.add_argument("a")
    d.add_argument("b")
    d.add_argument("-o", "--output", default="diff.md")
    d.add_argument("--name-a", default="Forever")
    d.add_argument("--name-b", default="Retail")
    d.add_argument("--limit", type=int, default=None, help="max items per list")
    d.set_defaults(func=cmd_diff)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
