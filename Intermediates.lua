local ADDON, CP = ...

-- Intermediate materials: a bar can be bought, or smelted from ore; a bolt of cloth can be
-- bought, or made from cloth. Every recipe that uses one of these is costed both ways (the
-- cheaper way counts), and clicking a craft searches the AH for the raw materials too.
--
-- Plans come from two places: recipes your characters have captured (any craft whose
-- output is used as a reagent), and the built-in list below for the common smelting and
-- bolt recipes. Built-in entries carry the expected English item name; if the game says the
-- item with that ID is called something else, the entry is ignored rather than trusted.

local STATIC = {
  -- [output] = { name, yield, { {inputID, count, inputName}, ... } }
  [2840]  = { "Copper Bar",        1, { { 2770,  1, "Copper Ore" } } },
  [3576]  = { "Tin Bar",           1, { { 2771,  1, "Tin Ore" } } },
  [2841]  = { "Bronze Bar",        2, { { 2840,  1, "Copper Bar" }, { 3576, 1, "Tin Bar" } } },
  [3575]  = { "Iron Bar",          1, { { 2772,  1, "Iron Ore" } } },
  [3859]  = { "Steel Bar",         1, { { 3575,  1, "Iron Bar" }, { 3857, 1, "Coal" } } },
  [2842]  = { "Silver Bar",        1, { { 2775,  1, "Silver Ore" } } },
  [3577]  = { "Gold Bar",          1, { { 2776,  1, "Gold Ore" } } },
  [3860]  = { "Mithril Bar",       1, { { 3858,  1, "Mithril Ore" } } },
  [6037]  = { "Truesilver Bar",    1, { { 7911,  1, "Truesilver Ore" } } },
  [12359] = { "Thorium Bar",       1, { { 10620, 1, "Thorium Ore" } } },
  [23445] = { "Fel Iron Bar",      1, { { 23424, 2, "Fel Iron Ore" } } },
  [23446] = { "Adamantite Bar",    1, { { 23425, 2, "Adamantite Ore" } } },
  [23447] = { "Eternium Bar",      1, { { 23427, 2, "Eternium Ore" } } },
  [23449] = { "Khorium Bar",       1, { { 23426, 2, "Khorium Ore" } } },
  [2996]  = { "Bolt of Linen Cloth",     1, { { 2589,  2, "Linen Cloth" } } },
  [2997]  = { "Bolt of Woolen Cloth",    1, { { 2592,  3, "Wool Cloth" } } },
  [4305]  = { "Bolt of Silk Cloth",      1, { { 4306,  4, "Silk Cloth" } } },
  [4339]  = { "Bolt of Mageweave",       1, { { 4338,  5, "Mageweave Cloth" } } },
  [14048] = { "Bolt of Runecloth",       1, { { 14047, 4, "Runecloth" } } },
  [21840] = { "Bolt of Netherweave",     1, { { 21877, 5, "Netherweave Cloth" } } },
}

local function NameOK(id, expected)
  local real = CP.RealItemName and CP.RealItemName(id)
  return not real or real == expected
end

-- Index of captured recipes by output item (rebuilt whenever results are built)
local captured = {}
function CP:IndexMakers()
  captured = {}
  local used = {}
  for _, profs in pairs(self.db.recipes or {}) do
    for _, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        for _, rg in ipairs(r.reagents or {}) do
          for _, id in ipairs(rg.ids or { rg.id }) do used[id] = true end
        end
      end
    end
  end
  for _, profs in pairs(self.db.recipes or {}) do
    for _, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        if used[r.id] and not captured[r.id] and r.reagents and #r.reagents > 0 then
          local inputs = {}
          for _, rg in ipairs(r.reagents) do
            inputs[#inputs + 1] = { id = (rg.ids and rg.ids[1]) or rg.id, count = rg.count }
          end
          captured[r.id] = { yield = (r.yield and r.yield > 0) and r.yield or 1, inputs = inputs }
        end
      end
    end
  end
end

-- { yield = n, inputs = { {id=, count=}, ... } } or nil
function CP:MakePlan(id)
  local c = captured[id]
  if c then return c end
  local s = STATIC[id]
  if not s or not NameOK(id, s[1]) then return nil end
  local inputs = {}
  for _, i in ipairs(s[3]) do
    if not NameOK(i[1], i[3]) then return nil end
    inputs[#inputs + 1] = { id = i[1], count = i[2] }
  end
  return { yield = s[2], inputs = inputs }
end

-- Raw materials (things with no plan of their own) needed for one of `id`, in order.
function CP:RawMaterials(id, mult, out, seen, depth)
  out, seen, depth = out or {}, seen or {}, depth or 0
  mult = mult or 1
  local plan = depth < 4 and not seen[id] and self:MakePlan(id)
  if not plan then
    out[#out + 1] = { id = id, count = mult }
    return out
  end
  seen[id] = true
  for _, i in ipairs(plan.inputs) do
    self:RawMaterials(i.id, mult * i.count / plan.yield, out, seen, depth + 1)
  end
  seen[id] = nil
  return out
end
