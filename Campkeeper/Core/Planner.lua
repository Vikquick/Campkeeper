local _, ns = ...

-- Camp planner: who places what. Pure function of its input.
--   input  { members = { { name, class, professions = { [professionKey] = skill } } },
--            fireTier = 1|2|3 (or slots = 3|5|10), role = "leveling"|"dungeon"|"craft" }
--   result { fire = { member, tier }?, objects = { { member, key, tier, weight } }, slots }
-- Every camping item shares one 1-hour cooldown, so each member places at most one thing; the
-- fire goes to the capable member least needed for anything else. Objects whose class buff someone in the group already provides are skipped;
-- the rest are ranked by the role's weights and each family gets the highest tier still
-- available among unassigned members. Ties break by name, so equal input gives equal output.
local Planner = { ROLES = { "leveling", "dungeon", "craft" } }
ns.Planner = Planner

local function skillOf(member, profession)
  return member.professions and member.professions[profession] or 0
end

-- Unassigned member with the highest skill that reaches `need` (ties by name).
local function bestMember(members, used, profession, need)
  local best
  for _, m in ipairs(members) do
    local s = skillOf(m, profession)
    if not used[m.name] and s >= need then
      if not best or s > skillOf(best, profession) or (s == skillOf(best, profession) and m.name < best.name) then
        best = m
      end
    end
  end
  return best
end

local function providedBuffs(members)
  local provided = {}
  for key, buff in pairs(ns.Catalog:ClassBuffs()) do
    for _, class in ipairs(buff.classes) do
      for _, m in ipairs(members) do
        if m.class == class then provided[key] = true end
      end
    end
  end
  return provided
end

local function covered(family, provided)
  for _, buff in ipairs(ns.Catalog:Get(family.objects[1]).exclusiveWith or {}) do
    if provided[buff] then return true end
  end
  return false
end

function Planner:Plan(input)
  local members = {}
  for _, m in ipairs(input.members or {}) do members[#members + 1] = m end
  table.sort(members, function(a, b) return a.name < b.name end)
  local role = input.role or "leveling"
  local used, result = {}, { objects = {} }

  local tierBySlots = { [3] = 1, [5] = 2, [10] = 3 }
  local fire = ns.Catalog:Fire(input.fireTier or tierBySlots[input.slots] or 1)
  result.slots = fire.slots

  local provided = providedBuffs(members)
  local families = {}
  for key, family in pairs(ns.Catalog:Families()) do
    local weight = family.weights[role] or 0
    if weight > 0 and not covered(family, provided) then
      families[#families + 1] = { key = key, family = family, weight = weight }
    end
  end
  table.sort(families, function(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    return a.key < b.key
  end)

  -- The fire goes to the capable member who is least needed elsewhere: the one whose best
  -- other object weighs least (ties: higher Cooking, then name).
  local function otherValue(m)
    local best = 0
    for _, f in ipairs(families) do
      local t1 = ns.Catalog:Get(f.family.objects[1])
      if skillOf(m, f.family.profession) >= t1.skill and f.weight > best then best = f.weight end
    end
    return best
  end
  local placer
  for _, m in ipairs(members) do
    if skillOf(m, "cooking") >= fire.skill then
      if not placer then placer = m
      else
        local a, b = otherValue(m), otherValue(placer)
        local ca, cb = skillOf(m, "cooking"), skillOf(placer, "cooking")
        if a < b or (a == b and ca > cb) then placer = m end
      end
    end
  end
  if placer then
    used[placer.name] = true
    result.fire = { member = placer.name, tier = fire.tier }
  end

  for _, f in ipairs(families) do
    if #result.objects >= result.slots then break end
    local chain = f.family.objects
    for i = #chain, 1, -1 do -- highest tier first
      local o = ns.Catalog:Get(chain[i])
      local m = bestMember(members, used, f.family.profession, o.skill)
      if m then
        used[m.name] = true
        result.objects[#result.objects + 1] = { member = m.name, key = o.key, tier = o.tier, weight = f.weight }
        break
      end
    end
  end
  return result
end

-- Chat lines for the plan (each under 255 bytes, ASCII separators only).
function Planner:ChatLines(plan)
  local L = ns.L
  local parts = {}
  if plan.fire then
    parts[#parts + 1] = ("%s - %s"):format(ns.Catalog:Name("fire" .. plan.fire.tier), plan.fire.member)
  end
  for _, o in ipairs(plan.objects) do
    parts[#parts + 1] = ("%s (T%d) - %s"):format(ns.Catalog:Name(o.key), o.tier, o.member)
  end
  local lines, line = {}, L["Camp plan:"]
  for _, p in ipairs(parts) do
    local candidate = line .. " " .. p .. ";"
    if #candidate > 250 then
      lines[#lines + 1] = line
      line = p .. ";"
    else
      line = candidate
    end
  end
  lines[#lines + 1] = line
  return lines
end
