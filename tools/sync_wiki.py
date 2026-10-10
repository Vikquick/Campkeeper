"""Publish docs/wiki/*.md to the GitHub wiki of the repository.

    python tools/sync_wiki.py --dry-run   # show what would change, push nothing
    python tools/sync_wiki.py             # commit and push the changes

The wiki is a separate git repository (<repo>.wiki.git). GitHub creates it only after
the first page is saved in the web interface: open the Wiki tab once, save any page,
then run this script. Pages missing from docs/wiki/ are left untouched in the wiki.
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGES = ROOT / "docs" / "wiki"


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=True, capture_output=True).stdout


def wiki_url():
    origin = git("remote", "get-url", "origin", cwd=ROOT).strip()
    return origin[:-4] + ".wiki.git" if origin.endswith(".git") else origin + ".wiki.git"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="do not commit or push")
    args = ap.parse_args(argv)
    url = wiki_url()
    head = git("rev-parse", "--short", "HEAD", cwd=ROOT).strip()
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        clone = Path(tmp) / "wiki"
        try:
            git("clone", "--quiet", url, str(clone), cwd=ROOT)
        except subprocess.CalledProcessError as e:
            print(f"error: cannot clone {url}\n{e.stderr.strip()}\n"
                  "Create the first wiki page on GitHub (Wiki tab -> Create the first page), then retry.",
                  file=sys.stderr)
            return 1
        for page in sorted(PAGES.glob("*.md")):
            shutil.copyfile(page, clone / page.name)
        git("add", "--all", cwd=clone)
        status = git("status", "--porcelain", cwd=clone)
        if not status.strip():
            print("wiki is up to date")
            return 0
        print(status, end="")
        if args.dry_run:
            print("dry run: nothing pushed")
            return 0
        git("commit", "--quiet", "-m", f"Sync from docs/wiki at {head}", cwd=clone)
        git("push", "--quiet", cwd=clone)
        print(f"pushed to {url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
