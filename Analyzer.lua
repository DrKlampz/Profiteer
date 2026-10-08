local ADDON, CP = ...

-- Cost of buying an item as-is: cheapest of AH lowest buyout and a known vendor price.
function CP:DirectCost(id)
  local p = self.db.prices[id]
  local ah = p and p.min
  -- A single lowball listing can't supply a real craft run. If the cheapest listing is
  -- less than half the next-cheapest price, cost the reagent at the reference price.
  if ah and p.ref and ah < p.ref * 0.5 then ah = p.ref end
  local v = self.db.vendor[id]
  if ah and v then
    if v <= ah then return v, "vendor" end
    return ah, "AH"
  end
  if v then return v, "vendor" end
  if ah then return ah, "AH" end
  return nil
end

-- Cost of making one of an item from its materials (bar from ore, bolt from cloth ...),
-- each material costed the cheapest way. nil if any material has no price.
function CP:MakeCost(id, depth, seen)
  depth, seen = depth or 0, seen or {}
  if depth >= 4 or seen[id] then return nil end
  local plan = self:MakePlan(id)
  if not plan then return nil end
  seen[id] = true
  local total = 0
  for _, i in ipairs(plan.inputs) do
    local c = self:ReagentCost(i.id, depth + 1, seen)
    if not c then seen[id] = nil return nil end
    total = total + c * i.count
  end
  seen[id] = nil
  return total / plan.yield
end

-- Reagent cost: the cheaper of buying it and making it from its materials.
-- Returns cost, source ("AH", "vendor" or "made"), as before.
function CP:ReagentCost(id, depth, seen)
  local c, src = self:DirectCost(id)
  local made = self:MakeCost(id, depth, seen)
  if made and (not c or made < c) then return made, "made" end
  return c, src
end

-- Price we expect to sell an item at. "safe" (default) uses the lower of the
-- current reference price and the two-week median, so a temporary spike can't
-- inflate a craft's profit. "current" uses today's reference price only.
function CP:SellPrice(id)
  local p = self.db.prices[id]
  local cur = p and p.ref
  if not cur then return nil end
  if self.db.settings.priceBasis == "current" then return cur end
  local st = CP.History.Stats(id)
  if st and st.median and st.samples >= 3 then return math.min(cur, st.median) end
  return cur
end

-- A reagent slot may accept several items (e.g. quality tiers): cost it with
-- the cheapest option. Returns cost per unit, source, and the item chosen.
function CP:SlotCost(rg)
  local best, bestSrc, bestID
  for _, id in ipairs(rg.ids or { rg.id }) do
    local c, src = self:ReagentCost(id)
    if c and (not best or c < best) then best, bestSrc, bestID = c, src, id end
  end
  return best, bestSrc, bestID or rg.id
end

function CP:Have(charKey, id)
  local inv = self.db.inventory[charKey]
  if not inv then return 0 end
  return (inv.bags and inv.bags[id] or 0) + (inv.bank and inv.bank[id] or 0)
end

function CP:HaveSlot(charKey, rg)
  local n = 0
  for _, id in ipairs(rg.ids or { rg.id }) do n = n + self:Have(charKey, id) end
  return n
end

function CP:CanMake(charKey, reagents)
  local best
  for _, rg in ipairs(reagents) do
    local n = math.floor(self:HaveSlot(charKey, rg) / rg.count)
    if not best or n < best then best = n end
  end
  return best or 0
end

local SORTERS = {
  name   = function(g) return g.name:lower() end,
  cost   = function(g) return g.cost end,
  revenue = function(g) return g.revenue end,
  profit = function(g) return g.profit end,
  ratio  = function(g) return g.ratio end,
  listed = function(g) return g.listed end,
  make   = function(g) return g.best end,
  perday = function(g) return g.perDay or -1 end,
}

-- Vendor sell price of an item if the client already knows it
local function VendorSell(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(fn, id)
  if ok and type(sell) == "number" and sell > 0 then return sell end
  return nil
end

-- Returns results (sorted, filtered), skippedCount, totalDistinctCrafts
function CP:BuildResults()
  local db, s = self.db, self.db.settings
  self:IndexMakers()

  -- Group identical crafts known by several characters into one row
  local groups, order = {}, {}
  for charKey, profs in pairs(db.recipes) do
    for prof, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        local key = prof .. ":" .. r.id
        local g = groups[key]
        if not g then
          g = { key = key, prof = prof, id = r.id, name = r.name, yield = r.yield,
                reagents = r.reagents, chars = {}, make = {}, diffs = {} }
          groups[key] = g
          order[#order + 1] = g
        end
        g.chars[#g.chars + 1] = charKey
        g.diffs[charKey] = r.diff
      end
    end
  end

  local results, skipped = {}, 0
  self.skippedList = {}
  for _, g in ipairs(order) do
    local p = db.prices[g.id]
    local sell = self:SellPrice(g.id)
    local cost, missing, missingName = 0, false, nil
    for _, rg in ipairs(g.reagents) do
      local c, _, cid = self:SlotCost(rg)
      if not c then missing = true; missingName = CP.ItemName(cid or rg.id); break end
      cost = cost + c * rg.count
    end

    if not sell or missing or cost <= 0 then
      skipped = skipped + 1
      local why
      if not sell then
        why = (p and (p.n or 0) == 0) and "nothing listed on the AH for the finished item" or "finished item not seen in a scan"
      elseif missing then
        why = "no price for reagent " .. tostring(missingName)
      else
        why = "material cost works out to zero"
      end
      local extra = ""
      if not missing and cost > 0 then
        extra = " | materials " .. CP.MoneyPlain(cost)
        if g.yield and g.yield > 1 then extra = extra .. " (makes " .. g.yield .. ")" end
      end
      local vs = VendorSell(g.id)
      if vs then extra = extra .. " | vendor sell " .. CP.MoneyPlain(vs) .. " each" end
      self.skippedList[#self.skippedList + 1] = g.name .. " (" .. g.prof .. "): " .. why .. extra
    else
      g.cost = cost
      g.sell = sell
      g.revenue = sell * g.yield * (1 - s.ahCut)
      g.profit = g.revenue - cost
      g.ratio = g.profit / cost
      g.listed = p.qty or 0
      local st = CP.History.Stats(g.id)
      g.perDay = st and st.perDay

      g.best = 0
      for _, charKey in ipairs(g.chars) do
        local n = self:CanMake(charKey, g.reagents)
        g.make[charKey] = n
        if n > g.best then g.best = n end
      end

      g.tracked = (s.tracked and s.tracked[g.key]) and true or false
      local keep = g.profit >= s.minProfit
        and g.listed >= s.minListed
        and (not s.craftableOnly or g.best > 0)
        and (s.minSales <= 0 or not g.perDay or g.perDay >= s.minSales)
      if keep or g.tracked then results[#results + 1] = g end
    end
  end

  table.sort(self.skippedList)
  local keyFn = SORTERS[s.sortKey] or SORTERS.ratio
  local desc = s.sortDesc
  table.sort(results, function(a, b)
    if a.tracked ~= b.tracked then return a.tracked end   -- tracked crafts pinned on top
    local x, y = keyFn(a), keyFn(b)
    if x == y then return a.name < b.name end
    if desc then return x > y end
    return x < y
  end)

  return results, skipped, #order
end

function CP:Refresh()
  if self.UI and self.UI.Rebuild then self.UI.Rebuild() end
end
