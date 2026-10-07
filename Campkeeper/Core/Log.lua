local _, ns = ...

-- Ring buffer of diagnostic records (unknown benefits, dropped messages, API errors).
-- Lives in memory until the database is ready, then in CampkeeperDB.global.debugLog so testers
-- can send the SavedVariables file.
local Log = { MAX = 200 }
ns.Log = Log

local buf = { first = 1, count = 0 }

local function now()
  return GetServerTime and GetServerTime() or 0
end

-- Move the buffer into persistent storage, keeping records logged before it was attached.
function Log:Attach(storage)
  local pending = self:Entries()
  wipe(storage)
  storage.first, storage.count = 1, 0
  buf = storage
  for _, e in ipairs(pending) do self:Add(e.cat, e.msg, e.t) end
end

function Log:Add(category, message, t)
  local e = { t = t or now(), cat = tostring(category), msg = tostring(message) }
  if buf.count < self.MAX then
    buf[(buf.first + buf.count - 1) % self.MAX + 1] = e
    buf.count = buf.count + 1
  else
    buf[buf.first] = e
    buf.first = buf.first % self.MAX + 1
  end
  return e
end

-- Records oldest first.
function Log:Entries()
  local out = {}
  for i = 0, buf.count - 1 do out[#out + 1] = buf[(buf.first + i - 1) % self.MAX + 1] end
  return out
end

function Log:Count()
  return buf.count
end

function Log:Clear()
  for i = 1, self.MAX do buf[i] = nil end
  buf.first, buf.count = 1, 0
end

-- ns.log("category", "format %s", ...) — formatting errors never escape.
function ns.log(category, fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  return Log:Add(category, ok and msg or tostring(fmt))
end
