local _, ns = ...

local Util = {}
ns.Util = Util

function Util.isSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

local function anySecret(n, ...)
  for i = 1, n do
    if Util.isSecret((select(i, ...))) then return true end
  end
  return false
end

local function finish(tag, ok, ...)
  if not ok then
    ns.log("api", "%s: %s", tag, tostring((...)))
    return nil
  end
  if anySecret(select("#", ...), ...) then
    ns.log("api", "%s: secret value", tag)
    return nil
  end
  return ...
end

-- Call a client API without letting errors or secret values reach the caller.
-- Returns nothing (nil) on failure and records why in the debug log under `tag`.
function Util.safeCall(tag, fn, ...)
  if type(fn) ~= "function" then
    ns.log("api", "%s: not available", tag)
    return nil
  end
  return finish(tag, pcall(fn, ...))
end

-- Lowercase ASCII and UTF-8 Cyrillic (string.lower only knows ASCII); folds ё into е.
function Util.lower(s)
  -- explicit byte range: string.lower and %u follow the C locale and can mangle UTF-8 bytes
  s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
  s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end) -- А-П
  s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end) -- Р-Я
  s = s:gsub("\208\129", "\208\181"):gsub("\209\145", "\208\181") -- Ё, ё -> е
  return s
end

-- Strip |c...|r colour codes and |T...|t textures, trim, lowercase — for name matching.
function Util.normalize(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  return Util.lower(strtrim(text))
end

-- Thin client wrapper used by Core modules; tests replace individual entries.
ns.api = {
  now = function() return GetTime() end,
  serverTime = function() return GetServerTime() end,
  inCombat = function()
    return Util.safeCall("InCombatLockdown", InCombatLockdown) == true
  end,
}
