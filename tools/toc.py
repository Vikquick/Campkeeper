"""Resolve the load order of a WoW addon .toc, following embeds/lib XML files.

    python tools/toc.py Campkeeper/Campkeeper.toc          # list Lua files in load order
    python tools/toc.py Campkeeper/Campkeeper.toc --check  # exit 1 if any referenced file is missing
"""
import argparse
import re
import sys
from pathlib import Path

_XML_REF = re.compile(r'<(Script|Include)\s+file\s*=\s*"([^"]+)"', re.IGNORECASE)
_XML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)


def _resolve(base: Path, ref: str) -> Path:
    return base / ref.replace("\\", "/")


def toc_entries(toc_path: Path):
    """File entries of a .toc (directives and comments skipped)."""
    for line in toc_path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line


def load_order(toc_path: Path):
    """Return (lua_files, missing) where lua_files is the ordered list the client would execute."""
    toc_path = Path(toc_path)
    lua, missing = [], []

    def visit(path: Path):
        if not path.is_file():
            missing.append(path)
            return
        if path.suffix.lower() == ".xml":
            text = _XML_COMMENT.sub("", path.read_text(encoding="utf-8-sig"))
            for _kind, ref in _XML_REF.findall(text):
                visit(_resolve(path.parent, ref))
        else:
            lua.append(path)

    for entry in toc_entries(toc_path):
        visit(_resolve(toc_path.parent, entry))
    return lua, missing


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("toc")
    ap.add_argument("--check", action="store_true", help="only report missing files")
    args = ap.parse_args(argv)
    lua, missing = load_order(Path(args.toc))
    if not args.check:
        for p in lua:
            print(p)
    for p in missing:
        print(f"missing: {p}", file=sys.stderr)
    if args.check and not missing:
        print(f"ok: {len(lua)} Lua files")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
