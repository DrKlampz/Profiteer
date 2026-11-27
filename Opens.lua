local ADDON, CP = ...

-- What an item gives when you open or decipher it (clams, crates, lockboxes, mage scrolls and the like).
-- Nobody publishes odds for most of these, so Profiteer learns them from your own openings: each time something comes
-- out of a bag item, the result is remembered, and the item's tooltip shows how often each thing showed up.
local O = {}
CP.Opens = O

local function Trace(msg) if CP.Issue then pcall(CP.Issue, "note", "opens trace", msg) end end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Store()
  if not (CP.db and CP.db.settings) then return nil end
  if (CP.db.opensV or 0) < 2 then CP.db.opens = {} CP.db.opensV = 2 end   -- the first version read the chat and miscounted: start clean
  CP.db.opens = CP.db.opens or {}
  return CP.db.opens
end

-- record one opening of item `id` that produced `got` = { [itemId] = qty } and maybe money
function O.Record(id, got, coin)
  local s = Store()
  if not s or not id then return end
  local r = s[id]
  if not r then r = { n = 0, coin = 0, items = {} } s[id] = r end
  r.n = r.n + 1
  if coin then r.coin = (r.coin or 0) + 1 end
  if not coin and next(got or {}) == nil then r.none = (r.none or 0) + 1 end
  for gid, qty in pairs(got or {}) do
    local it = r.items[gid]
    if not it then it = { c = 0, q = 0 } r.items[gid] = it end
    it.c = it.c + 1
    it.q = it.q + qty
  end
end

------------------------------------------------------------------------
-- which bag item was just used
------------------------------------------------------------------------
local lastUse   -- { id, time }
if hooksecurefunc then
  local function Used(bag, slot)
    local link
    if C_Container and C_Container.GetContainerItemLink then link = C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then link = GetContainerItemLink(bag, slot) end
    if link and not Secret(link) then
      local id = tonumber(tostring(link):match("item:(%d+)"))
      if id then lastUse = { id = id, time = GetTime() } end
    end
  end
  if C_Container and C_Container.UseContainerItem then pcall(hooksecurefunc, C_Container, "UseContainerItem", Used)
  elseif UseContainerItem then pcall(hooksecurefunc, "UseContainerItem", Used) end
end

------------------------------------------------------------------------
-- 1) things that open into a loot window (clams, crates, lockboxes, bags of goods)
------------------------------------------------------------------------
local counted = false
local function LootWindow()
  if counted then return end
  if not (lastUse and GetTime() - lastUse.time < 6) then return end
  if not GetLootSourceInfo then return end
  local ok, guid = pcall(GetLootSourceInfo, 1)
  if not ok or type(guid) ~= "string" or Secret(guid) or not guid:find("^Item") then return end
  counted = true
  local got, coin = {}, false
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local ltype = GetLootSlotType and GetLootSlotType(i)
    if ltype == 2 then
      coin = true
    else
      local link = GetLootSlotLink and GetLootSlotLink(i)
      local _, _, qty = GetLootSlotInfo(i)
      local gid = link and not Secret(link) and tonumber(tostring(link):match("item:(%d+)"))
      if gid then got[gid] = (got[gid] or 0) + (tonumber(qty) or 1) end
    end
  end
  O.Record(lastUse.id, got, coin)
end

------------------------------------------------------------------------
-- 2) things that turn into another item when a spell is cast on them (a mage deciphering a scroll). What came out is
-- read from the bags: what was there when the cast started against what is there a moment after it finished.
------------------------------------------------------------------------
local DECIPHER = { ["Comprehend Scroll"] = true }
local pending   -- { guid, id, before }

local function BagCounts()
  local out = {}
  local nslots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getinfo = C_Container and C_Container.GetContainerItemInfo
  if not nslots then return out end
  for bag = 0, 5 do
    for slot = 1, (nslots(bag) or 0) do
      local gid, qty
      if getinfo then
        local info = getinfo(bag, slot)
        if info and not Secret(info.itemID) then gid, qty = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        if link and not Secret(link) then gid, qty = tonumber(tostring(link):match("item:(%d+)")), count end
      end
      if gid then out[gid] = (out[gid] or 0) + (tonumber(qty) or 1) end
    end
  end
  return out
end

local function SpellName(spellID)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
  if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

-- an item in the bags by its name (a cast on an item names its target)
local function ItemByName(name)
  local nslots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getinfo = C_Container and C_Container.GetContainerItemInfo
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not (nslots and getinfo and fn) then return nil end
  for bag = 0, 5 do
    for slot = 1, (nslots(bag) or 0) do
      local info = getinfo(bag, slot)
      if info and info.itemID and not Secret(info.itemID) then
        local nm = fn(info.itemID)
        if nm == name then return info.itemID end
      end
    end
  end
end

local function Settle(p)
  if pending ~= p then return end
  pending = nil
  local after, got = BagCounts(), {}
  for gid, n in pairs(after) do
    local gain = n - (p.before[gid] or 0)
    if gain > 0 and gid ~= p.id then got[gid] = gain end   -- the scroll itself is what was used up, not something it gave
  end
  local list = {}
  for gid, n in pairs(got) do list[#list + 1] = gid .. "x" .. n end
  Trace(("settled item %s: gained %s"):format(tostring(p.id), #list > 0 and table.concat(list, ", ") or "nothing"))
  O.Record(p.id, got, false)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "LOOT_READY", "LOOT_CLOSED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", CP.Safe and CP.Safe("opens-event", function(_, event, a, b, c, d)
  if not (CP.db and CP.db.settings and CP.db.settings.openTips ~= false) then return end
  if event == "LOOT_OPENED" or event == "LOOT_READY" then
    LootWindow()
  elseif event == "LOOT_CLOSED" then
    counted = false
  elseif event == "UNIT_SPELLCAST_SENT" then
    if a ~= "player" then return end
    local name = SpellName(d)
    if name and not Secret(name) and not DECIPHER[name] and (name:lower():find("scroll", 1, true) or name:lower():find("compre", 1, true)) then
      Trace("saw a cast named " .. name .. " (not one I record)")
    end
    if name and not Secret(name) and DECIPHER[name] then
      local id = (lastUse and GetTime() - lastUse.time < 8) and lastUse.id or nil
      if not id and type(b) == "string" and not Secret(b) then id = ItemByName(b) end
      Trace(("%s cast on %s (item %s)"):format(name, tostring(b), tostring(id)))
      if id then pending = { guid = c, id = id, before = BagCounts() } end
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if a ~= "player" or not pending then return end
    if c ~= pending.guid and b ~= pending.guid then return end
    Trace("cast finished, checking the bags in a moment")
    local p = pending
    C_Timer.After(1.2, function() Settle(p) end)
  end
end) or function() end)

------------------------------------------------------------------------
-- tooltip
------------------------------------------------------------------------
local function LooksOpenable(tip)
  local name = tip.GetName and tip:GetName()
  if not name then return false end
  local want = {}
  if _G.ITEM_OPENABLE then want[#want + 1] = _G.ITEM_OPENABLE end
  want[#want + 1] = "Right Click to Open"
  want[#want + 1] = "can decipher"
  want[#want + 1] = "Locked"
  for i = 2, (tip.NumLines and tip:NumLines() or 0) do
    local fs = _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if t and not Secret(t) then
      for _, w in ipairs(want) do if t:find(w, 1, true) then return true end end
    end
  end
  return false
end

local function ItemName(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local nm, link
  if fn then nm, link = fn(id) end
  return link or nm or ("item " .. id)
end

local function Price(id)
  local p = CP.db and CP.db.prices and CP.db.prices[id]
  return p and (p.min or p.ref)
end

function O.Tip(tip, id)
  if not CP.db or not CP.db.settings or CP.db.settings.openTips == false then return end
  local st = Store()
  local r = st and st[id]
  if not r or r.n == 0 then
    if LooksOpenable(tip) then
      tip:AddLine(" ")
      tip:AddLine("What it gives", 0.7, 0.5, 1)
      tip:AddLine("Nothing recorded yet. The odds fill in from what you get each time you open one.", 0.6, 0.6, 0.6, true)
    end
    return
  end
  local rows = {}
  for gid, it in pairs(r.items) do rows[#rows + 1] = { id = gid, rate = it.c / r.n, avg = it.q / it.c } end
  table.sort(rows, function(x, y) if x.rate ~= y.rate then return x.rate > y.rate end return x.id < y.id end)
  tip:AddLine(" ")
  tip:AddLine("What it gives", 0.7, 0.5, 1)
  local total, known = 0, false
  for i, row in ipairs(rows) do
    if i > 8 then tip:AddLine(("   and %d more"):format(#rows - 8), 0.6, 0.6, 0.6) break end
    local qty = (math.abs(row.avg - math.floor(row.avg + 0.5)) < 0.05) and (" x" .. math.floor(row.avg + 0.5)) or string.format(" x%.1f", row.avg)
    tip:AddDoubleLine(ItemName(row.id) .. (row.avg > 1.05 and qty or ""), string.format("%d%%", math.floor(row.rate * 100 + 0.5)), 1, 1, 1, 0.8, 0.8, 0.8)
    local pr = Price(row.id)
    if pr then total = total + row.rate * row.avg * pr known = true end
  end
  if (r.none or 0) > 0 then
    tip:AddDoubleLine("Nothing (no item)", string.format("%d%%", math.floor(r.none / r.n * 100 + 0.5)), 1, 1, 1, 0.8, 0.8, 0.8)
  end
  if (r.coin or 0) > 0 then
    tip:AddDoubleLine("Money", string.format("%d%%", math.floor(r.coin / r.n * 100 + 0.5)), 1, 1, 1, 0.8, 0.8, 0.8)
  end
  if known then tip:AddDoubleLine("Expected value", CP.Money(math.floor(total + 0.5)), 1, 1, 1, 1, 1, 1) end
  tip:AddLine(("From %d opening%s of yours"):format(r.n, r.n == 1 and "" or "s"), 0.5, 0.5, 0.5)
end
