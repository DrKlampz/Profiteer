-- Live prices: asks the auction house about each item on its own (the same search the
-- Shopping tab uses) instead of waiting for a full scan. Fast, and exact right now.
local _, CP = ...
CP.Live = CP.Live or {}
local L = CP.Live
local H = CP.AH

local MAXITEMS = 60      -- most items fetched in one go
local TIMEOUT = 6        -- seconds to wait for one item before skipping it

local q, qi, cur, token, done, failed = nil, 0, nil, 0, 0, 0
L.running = false

local function Status(t) if CP.UI and CP.UI.SetStatus then CP.UI.SetStatus(t) end end

local function Finish(msg)
  L.running = false
  cur = nil
  token = token + 1
  if L.button then L.button:SetText("Live prices") end
  Status(msg)
  CP:Refresh()
end

-- turn search results into the same entry the scanner stores
local function Store(id, units, listings, totalQty)
  table.sort(units)
  local old = CP.db.prices[id]
  local e = { qty = totalQty, n = listings, time = time(), live = true }
  if #units > 0 then
    e.min = units[1]
    e.ref = (#units >= 3) and units[2] or units[1]
  elseif old and old.vendor then
    return
  end
  CP.db.prices[id] = e
end

local function ReadCommodity(id)
  local units, lst, total = {}, 0, 0
  local n = C_AuctionHouse.GetNumCommoditySearchResults(id) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice then
      lst = lst + 1
      total = total + (r.quantity or 1)
      for _ = 1, math.min(3, r.quantity or 1) do
        units[#units + 1] = r.unitPrice
      end
    end
  end
  -- keep only the cheapest three units (results arrive cheapest first)
  while #units > 3 do table.remove(units) end
  Store(id, units, lst, total)
end

local function ReadItems(key)
  local id = key and key.itemID
  if not id then return end
  local units, lst, total = {}, 0, 0
  local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      local c = r.quantity or 1
      lst = lst + 1
      total = total + c
      units[#units + 1] = r.buyoutAmount / c
    end
  end
  table.sort(units)
  while #units > 3 do table.remove(units) end
  Store(id, units, lst, total)
end

local Next

local function Advance()
  done = done + 1
  cur = nil
  CP.After(0.15, Next)
end

Next = function()
  if not L.running then return end
  if not (C_AuctionHouse and H.IsOpen()) then
    Finish("Live prices stopped: the auction house closed. Updated " .. done .. " items.")
    return
  end
  qi = qi + 1
  local id = q[qi]
  if not id then
    Finish(("Live prices: updated %d items%s."):format(done - failed, failed > 0 and (", " .. failed .. " timed out") or ""))
    return
  end
  if not H.Ready() then qi = qi - 1; L.waiting = true; Status("Live prices: waiting for the auction house...") return end
  L.waiting = false
  cur = id
  token = token + 1
  local my = token
  Status(("Live prices: %d / %d  %s"):format(qi, #q, CP.ItemName(id) or tostring(id)))
  local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), sorts, true)
  if not ok then CP.RecordError("live price search", err); failed = failed + 1; Advance() return end
  C_Timer.After(TIMEOUT, function()
    if L.running and token == my and cur == id then failed = failed + 1; Advance() end
  end)
end

-- ids: list of item ids; builds the queue and starts
function L.Start(ids)
  if L.running then Finish("Live prices cancelled. Updated " .. (done - failed) .. " items.") return end
  if not (C_AuctionHouse and H.IsOpen()) then Status("Open the auction house first: live prices need it.") return end
  local seen, list = {}, {}
  for _, id in ipairs(ids) do
    if id and not seen[id] then seen[id] = true; list[#list + 1] = id end
  end
  if #list == 0 then Status("Nothing to look up.") return end
  while #list > MAXITEMS do table.remove(list) end
  q, qi, done, failed, cur = list, 0, 0, 0, nil
  L.running = true
  if L.button then L.button:SetText("Stop") end
  Next()
end

-- items for the crafts currently shown: the finished item and every reagent
function L.VisibleIds()
  local ui = CP.UI
  local out = {}
  local res = ui.results or {}
  local rows = math.min(#res - (ui.offset or 0), ui.VisibleRows and ui.VisibleRows() or 15)
  for i = 1, rows do
    local g = res[i + (ui.offset or 0)]
    if g then
      out[#out + 1] = g.id
      for _, rg in ipairs(g.reagents or {}) do out[#out + 1] = rg.id end
    end
  end
  return out
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_CLOSED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", CP.Safe("live-event", function(_, event, a)
  if not L.running then return end
  if event == "AUCTION_HOUSE_CLOSED" then
    Finish("Live prices stopped: the auction house closed. Updated " .. (done - failed) .. " items.")
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if L.waiting then Next() end
  elseif cur then
    local id = (event == "COMMODITY_SEARCH_RESULTS_UPDATED") and a or (type(a) == "table" and a.itemID)
    if id ~= cur then return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then ReadCommodity(id) else ReadItems(a) end
    Advance()
  end
end))
