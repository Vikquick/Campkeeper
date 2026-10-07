"""Download the externals listed in .pkgmeta for local development and tests.

BigWigs Packager embeds the same externals at release time; this script only mirrors them
into the working tree (the Libs folders are git-ignored).

    python tools/fetch_libs.py           # fetch missing externals
    python tools/fetch_libs.py --force   # refetch everything

SVN externals are read over plain HTTP (repos.wowace.com serves directory listings), so no
svn client is needed. Git externals are shallow-cloned with git.
"""
import argparse
import html
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_LINK = re.compile(r'<a href="([^"]+)"')
_RETRIES = 5


def parse_externals(text: str):
    """Parse the `externals:` block of a .pkgmeta into {path: {"url": ..., "tag": ...}}.

    Supports the two forms used in this repo: `path: url` and a nested mapping with url/tag.
    """
    externals, in_block, current = {}, False, None
    for raw in text.splitlines():
        line = raw.split(" #", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        key, _, value = line.strip().partition(":")
        value = value.strip()
        if indent == 0:
            in_block, current = key == "externals", None
            continue
        if not in_block:
            continue
        if current is not None and indent > current[1]:
            externals[current[0]][key] = value
            continue
        if value:
            externals[key] = {"url": value}
            current = None
        else:
            externals[key] = {}
            current = (key, indent)
    return externals


def _get(url: str) -> bytes:
    last = None
    for attempt in range(_RETRIES):
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                return resp.read()
        except OSError as exc:  # URLError, timeouts, resets
            last = exc
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed after {_RETRIES} attempts: {last}")


def fetch_svn_http(url: str, dest: Path):
    """Mirror an SVN directory served over HTTP (mod_dav_svn listing) into dest."""
    if not url.endswith("/"):
        url += "/"
    dest.mkdir(parents=True, exist_ok=True)
    listing = _get(url).decode("utf-8", "replace")
    for href in _LINK.findall(listing):
        href = html.unescape(href)
        if href.startswith(("../", "http:", "https:", "/")) or href == "./":
            continue
        name = urllib.parse.unquote(href)
        if href.endswith("/"):
            fetch_svn_http(url + href, dest / name.rstrip("/"))
        else:
            (dest / name).write_bytes(_get(url + href))


def _latest_tag(url: str) -> str:
    out = subprocess.run(["git", "ls-remote", "--tags", "--sort=-v:refname", url],
                         check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        ref = line.split("\t")[1]
        if not ref.endswith("^{}"):
            return ref.removeprefix("refs/tags/")
    raise RuntimeError(f"no tags in {url}")


def fetch_git(url: str, tag: str | None, dest: Path):
    if tag == "latest":
        tag = _latest_tag(url)
    with tempfile.TemporaryDirectory() as tmp:
        cmd = ["git", "-c", "advice.detachedHead=false", "clone", "--quiet", "--depth", "1"]
        if tag:
            cmd += ["--branch", tag]
        subprocess.run(cmd + [url, tmp], check=True)
        shutil.copytree(tmp, dest, ignore=shutil.ignore_patterns(".git", ".github"))
    return tag


def fetch(path: str, spec: dict, force: bool):
    dest = ROOT / path
    if dest.exists():
        if not force:
            print(f"skip  {path} (exists)")
            return
        shutil.rmtree(dest)
    url = spec["url"]
    if url.endswith(".git") or "github.com" in url:
        tag = fetch_git(url, spec.get("tag"), dest)
        print(f"git   {path} <- {url}" + (f" @ {tag}" if tag else ""))
    elif url.startswith(("http://", "https://")):
        try:
            fetch_svn_http(url, dest)
        except Exception:
            shutil.rmtree(dest, ignore_errors=True)
            raise
        print(f"svn   {path} <- {url}")
    else:
        raise RuntimeError(f"unsupported external url for {path}: {url}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="delete and refetch existing externals")
    ap.add_argument("--pkgmeta", default=str(ROOT / ".pkgmeta"))
    args = ap.parse_args(argv)
    externals = parse_externals(Path(args.pkgmeta).read_text(encoding="utf-8"))
    failed = []
    for path, spec in externals.items():
        try:
            fetch(path, spec, args.force)
        except Exception as exc:
            failed.append(path)
            print(f"FAIL  {path}: {exc}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
