"""Load WoW addon code into Lua 5.1 (lupa) with the mocked client from wowmock.lua.

    env = WowEnv(locale="ruRU")
    env.load_toc("Campkeeper/Campkeeper.toc")       # every file, like the client
    env.load_files("Campkeeper", ["Core/Util.lua"])  # or a chosen subset
    env.login()                                      # ADDON_LOADED + PLAYER_LOGIN
    env.lua.eval("...")                              # inspect Lua state
"""
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import toc  # noqa: E402

MOCK = (Path(__file__).with_name("wowmock.lua")).read_text(encoding="utf-8")

_RUN_CHUNK = """
return function(src, chunkname, addonName, ns)
  local f, err = loadstring(src, chunkname)
  if not f then error(err, 0) end
  return f(addonName, ns)
end
"""


class LuaErrors(AssertionError):
    pass


class WowEnv:
    def __init__(self, locale="enUS", addon="Campkeeper"):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True, encoding="utf-8")
        self.lua.execute(MOCK)
        self.lua.globals().Mock.locale = locale
        self.addon = addon
        self.ns = self.lua.table()
        self._run = self.lua.execute(_RUN_CHUNK)

    @property
    def g(self):
        return self.lua.globals()

    @property
    def mock(self):
        return self.lua.globals().Mock

    def run_file(self, path: Path):
        src = Path(path).read_text(encoding="utf-8-sig")
        rel = Path(path).resolve().relative_to(ROOT).as_posix()
        self._run(src, "@" + rel, self.addon, self.ns)

    def load_files(self, addon_dir, files):
        base = ROOT / addon_dir
        for f in files:
            self.run_file(base / f)

    def load_toc(self, toc_path="Campkeeper/Campkeeper.toc"):
        lua_files, missing = toc.load_order(ROOT / toc_path)
        if missing:
            raise FileNotFoundError(f"missing files (run tools/fetch_libs.py?): {missing}")
        for f in lua_files:
            self.run_file(f)

    def fire(self, event, *args):
        self.mock.Fire(event, *args)

    def advance(self, seconds):
        self.mock.Advance(seconds)

    def login(self):
        self.fire("ADDON_LOADED", self.addon)
        self.mock.loggedIn = True
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD", True, False)
        self.advance(0)

    def errors(self):
        return list(self.mock.errors.values())

    def assert_no_errors(self):
        errs = self.errors()
        if errs:
            raise LuaErrors("Lua errors:\n" + "\n".join(errs))

    def chat(self):
        return list(self.mock.chat.values())
