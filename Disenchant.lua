local ADDON, CP = ...

-- Disenchant odds on item tooltips: what you can expect to get, and roughly what it is worth.
-- The odds are the commonly published Classic figures, so treat them as close estimates, not exact rolls.
local DE = {}
CP.Disenchant = DE

-- { highest item level, dust id, dust name, dust min, dust max, essence id, essence name, ess min, ess max, shard id, shard name }
local BRACKETS = {
  { 15, 10940, "Strange Dust", 1, 3, 10938, "Lesser Magic Essence", 1, 2 },
  { 20, 10940, "Strange Dust", 2, 5, 10939, "Greater Magic Essence", 1, 2, 10978, "Small Glimmering Shard" },
  { 25, 10940, "Strange Dust", 2, 5, 10998, "Lesser Astral Essence", 1, 2, 10978, "Small Glimmering Shard" },
  { 30, 11083, "Soul Dust", 1, 3, 11082, "Greater Astral Essence", 1, 2, 11084, "Large Glimmering Shard" },
  { 35, 11083, "Soul Dust", 2, 5, 11134, "Lesser Mystic Essence", 1, 2, 11138, "Small Glowing Shard" },
  { 40, 11137, "Vision Dust", 1, 3, 11135, "Greater Mystic Essence", 1, 2, 11139, "Large Glowing Shard" },
  { 45, 11137, "Vision Dust", 2, 5, 11174, "Lesser Nether Essence", 1, 2, 11177, "Small Radiant Shard" },
  { 50, 11176, "Dream Dust", 1, 3, 11175, "Greater Nether Essence", 1, 2, 11178, "Large Radiant Shard" },
  { 55, 11176, "Dream Dust", 2, 5, 16202, "Lesser Eternal Essence", 1, 2, 14343, "Small Brilliant Shard" },
  { 60, 16204, "Illusion Dust", 1, 3, 16203, "Greater Eternal Essence", 1, 2, 14344, "Large Brilliant Shard" },
  { 65, 16204, "Illusion Dust", 2, 5, 16203, "Greater Eternal Essence", 2, 3, 14344, "Large Brilliant Shard" },
}
local NEXUS = 20725   -- Nexus Crystal

-- list of { chance 0-1, item id, name, min, max } for one item
function DE.Outcomes(quality, ilvl, isWeapon)
  if not quality or not ilvl or quality < 2 or quality > 4 or ilvl < 5 then return nil end
  local b
  for _, row in ipairs(BRACKETS) do if ilvl <= row[1] then b = row break end end
  if not b then return nil end
  local out = {}
  local shard = b[10] and { 1, b[10], b[11], 1, 1 } or nil
  if quality == 2 then
    local dust, ess = isWeapon and 0.20 or 0.75, isWeapon and 0.75 or 0.20
    out[#out + 1] = { dust, b[2], b[3], b[4], b[5] }
    out[#out + 1] = { ess, b[6], b[7], b[8], b[9] }
    if shard then
      shard[1] = 0.05
      out[#out + 1] = shard
    else
      out[1][1] = dust + 0.05
    end
  elseif quality == 3 then
    if shard then out[#out + 1] = shard else return nil end
  else
    if ilvl < 40 then return nil end
    out[#out + 1] = { 1, NEXUS, "Nexus Crystal", 1, 2 }
  end
  return out
end

local function Price(id)
  local p = CP.db and CP.db.prices and CP.db.prices[id]
  if not p then return nil end
  return p.min or p.ref
end

function DE.Tip(tip, id)
  if not CP.db or not CP.db.settings or CP.db.settings.deTips == false then return end
  if not GetItemInfo then return end
  local _, _, quality, ilvl, _, _, _, _, _, _, _, classID = GetItemInfo(id)
  if not quality or not classID or (classID ~= 2 and classID ~= 4) then return end
  if classID == 4 then   -- cloaks, trinkets and the like give armor results; shirts and tabards cannot be disenchanted
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
    if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" or equipLoc == "" or equipLoc == "INVTYPE_BAG" then return end
  end
  local out = DE.Outcomes(quality, ilvl, classID == 2)
  if not out then return end
  tip:AddLine(" ")
  tip:AddLine("Disenchant odds", 0.7, 0.5, 1)
  local total, known = 0, false
  for _, o in ipairs(out) do
    if o[1] > 0 then
      local qty = (o[4] == o[5]) and tostring(o[4]) or (o[4] .. "-" .. o[5])
      tip:AddDoubleLine(o[3] .. " x" .. qty, string.format("%d%%", math.floor(o[1] * 100 + 0.5)), 1, 1, 1, 0.8, 0.8, 0.8)
      local pr = Price(o[2])
      if pr then total = total + o[1] * pr * (o[4] + o[5]) / 2 known = true end
    end
  end
  if known then tip:AddDoubleLine("Expected value", CP.Money(total), 1, 1, 1, 1, 1, 1) end
end
