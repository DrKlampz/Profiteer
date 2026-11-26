-- Live prices: asks the auction house about each item on its own (the same search the
-- Shopping tab uses) instead of waiting for a full scan. Fast, and exact right now.
local _, CP = ...
CP.Live = CP.Live or {}
local L = CP.Live
local H = CP.AH

local MAXITEMS = 100     -- most items fetched in one go
local TIMEOUT = 6        -- seconds to wait for one item before skipping it

local q, qi, cur, token, done, failed = nil, 0, nil, 0, 0, 0
local updated, tries, failedNames = 0, {}, {}
L.last = nil     -- { time, updated, failed } of the last run, shown under the list
L.running = false

local function Status(t) if CP.UI and CP.UI.SetStatus then CP.UI.SetStatus(t) end end

local function Finish(msg)
  L.running = false
  cur = nil
  token = token + 1
  if L.button then L.button:SetText("Live prices") end
  L.last = { time = time(), updated = updated, failed = failed, total = L.total }
  if failed > 0 and CP.Issue then
    CP.Issue("warn", "live prices", ("updated %d, no answer for %d: %s"):format(updated, failed, table.concat(failedNames, ", ")))
  end
  -- redraw first: the redraw rewrites the status line under the list, so the result has to be written after it
  CP:Refresh()
  Status(msg)
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
  if L.running then updated = updated + 1 end
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
  if L.running then updated = updated + 1 end
end

local Next

local function Advance()
  done = done + 1
  cur = nil
  CP.After(0.15, Next)
end

-- no answer for this item (timed out, or the server dropped the request): ask once more at the end, then give up on it
local function NoAnswer(id)
  tries[id] = (tries[id] or 0) + 1
  if tries[id] < 2 then
    q[#q + 1] = id
  else
    failed = failed + 1
    failedNames[#failedNames + 1] = CP.ItemName(id) or tostring(id)
  end
  Advance()
end

Next = function()
  if not L.running or cur then return end        -- not running, or a request is already waiting for its answer
  if not (C_AuctionHouse and H.IsOpen()) then
    Finish("Live prices stopped: the auction house closed. Updated " .. updated .. " items.")
    return
  end
  -- the game answers one search at a time, so a run must not fire searches while another tab (Shopping, Selling,
  -- Cancelling) is using the search results on screen: it waits here and carries on when you are back on Crafts
  do
    local at = CP.AHTab
    local view = at and at.Current and at.Current()
    if view and view ~= "crafts" and view ~= "ledger" then
      Status("Live prices paused while you use another tab. It carries on when you go back to Crafts.")
      if not L.pauseTimer then
        L.pauseTimer = true
        CP.After(1, function() L.pauseTimer = false if L.running and not cur then Next() end end)
      end
      return
    end
  end
  qi = qi + 1
  local id = q[qi]
  if not id then
    Finish(("Live prices: updated %d of %d items%s."):format(updated, L.total or updated, failed > 0 and (", " .. failed .. " got no answer from the auction house (try again in a moment)") or ""))
    return
  end
  if not H.Ready() then qi = qi - 1; L.waiting = true; Status("Live prices: waiting for the auction house...")
    CP.After(1, function() if L.running and L.waiting then Next() end end)     -- do not rely on the ready event alone
    return end
  L.waiting = false
  cur = id
  token = token + 1
  local my = token
  Status(("Live prices: %d / %d  %s"):format(qi, #q, CP.ItemName(id) or tostring(id)))
  local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), sorts, true)
  if not ok then CP.RecordError("live price search", err); NoAnswer(id) return end
  C_Timer.After(TIMEOUT, function()
    if L.running and token == my and cur == id then NoAnswer(id) end
  end)
end

-- ids: list of item ids; builds the queue and starts
function L.Start(ids)
  if L.running then Finish("Live prices cancelled. Updated " .. updated .. " items.") return end
  if not (C_AuctionHouse and H.IsOpen()) then Status("Open the auction house first: live prices need it.") return end
  local seen, list = {}, {}
  for _, id in ipairs(ids) do
    if id and not seen[id] then seen[id] = true; list[#list + 1] = id end
  end
  if #list == 0 then Status("Nothing to look up.") return end
  while #list > MAXITEMS do table.remove(list) end
  q, qi, done, failed, cur = list, 0, 0, 0, nil
  updated, tries, failedNames = 0, {}, {}
  L.total = #list
  L.running = true
  if L.button then L.button:SetText("Stop") end
  Next()
end

-- items to look up, favorites first: the crafts you have starred (the finished item and every reagent), then the
-- auction house's own favorites, then the crafts currently shown. The run is capped, so the order decides what is covered.
function L.VisibleIds()
  local ui = CP.UI
  local out = {}
  local function addCraft(g)
    out[#out + 1] = g.id
    for _, rg in ipairs(g.reagents or {}) do
      for _, id in ipairs(rg.ids or { rg.id }) do out[#out + 1] = id end
    end
  end
  for _, g in ipairs(ui.allResults or ui.results or {}) do
    if g.tracked then addCraft(g) end
  end
  if C_AuctionHouse and C_AuctionHouse.IsFavoriteItem then
    for _, list in pairs(CP.db.shopLists or {}) do
      for _, e in ipairs(list) do
        local ok, fav = pcall(C_AuctionHouse.IsFavoriteItem, C_AuctionHouse.MakeItemKey(e.id))
        if ok and fav then out[#out + 1] = e.id end
      end
    end
  end
  local res = ui.results or {}
  local rows = math.min(#res - (ui.offset or 0), ui.VisibleRows and ui.VisibleRows() or 15)
  for i = 1, rows do
    local g = res[i + (ui.offset or 0)]
    if g then addCraft(g) end
  end
  return out
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", CP.Safe("live-event", function(_, event, a)
  if not L.running then
    if L.RollEvent then L.RollEvent(event, a) end
    return
  end
  if event == "AUCTION_HOUSE_CLOSED" then
    Finish("Live prices stopped: the auction house closed. Updated " .. updated .. " items.")
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- the server threw our request away: ask for this item again later instead of waiting out the timeout
    if cur then local id = cur token = token + 1 NoAnswer(id) end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if L.waiting then Next() end
  elseif cur then
    local id = (event == "COMMODITY_SEARCH_RESULTS_UPDATED") and a or (type(a) == "table" and a.itemID)
    if id ~= cur then return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then ReadCommodity(id) else ReadItems(a) end
    Advance()
  end
end))

------------------------------------------------------------------------
-- Rolling refresh: while the auction house is open and nothing else is using it, keep re-checking the items that
-- matter (the crafts shown, their materials and your saved shopping lists), oldest price first, one every few
-- seconds. It stays out of the way: it pauses while a scan or a Live prices run is going and for a few seconds
-- after you search yourself, and it never asks faster than the game allows.
------------------------------------------------------------------------
local ROLL_EVERY = 3          -- seconds between checks
local ROLL_MIN_AGE = 120      -- do not re-check an item more often than this
local ROLL_TIMEOUT = 6
local ROLL_MAX_ITEMS = 120
local roll = { cur = nil, token = 0, tried = {}, pausedUntil = 0, ours = false, active = false, count = 0 }
L.roll = roll

local function WatchIds()
  local seen, out = {}, {}
  local function add(id) if id and not seen[id] then seen[id] = true; out[#out + 1] = id end end
  local res = (CP.UI and CP.UI.results) or {}
  for i = 1, math.min(#res, 25) do
    local g = res[i]
    if g then
      add(g.id)
      for _, rg in ipairs(g.reagents or {}) do add(rg.id) end
    end
  end
  for _, list in pairs(CP.db.shopLists or {}) do
    for _, e in ipairs(list) do add(e.id) end
  end
  while #out > ROLL_MAX_ITEMS do table.remove(out) end
  return out
end

local function PickOldest()
  local now = time()
  local best, bestT
  for _, id in ipairs(WatchIds()) do
    local e = CP.db.prices[id]
    local t = (e and e.time) or 0
    if (now - t) >= ROLL_MIN_AGE and (now - (roll.tried[id] or 0)) >= ROLL_MIN_AGE then
      if not bestT or t < bestT then best, bestT = id, t end
    end
  end
  return best
end

local function RollOn()
  return CP.db and CP.db.settings and CP.db.settings.rolling ~= false
end

local function Busy()
  if L.running then return true end
  -- a search replaces the results on screen (the Shopping list you are reading or buying from, the price you are
  -- posting at), so the rolling refresh only runs while you are looking at a view that does not depend on them
  local at = CP.AHTab
  local view = at and at.Current and at.Current()
  if view ~= "crafts" and view ~= "ledger" then return true end
  if CP.Scanner and CP.Scanner.IsRunning and CP.Scanner:IsRunning() then return true end
  if GetTime() < roll.pausedUntil then return true end
  return false
end

local function RollTick()
  if not roll.active then return end
  if not (RollOn() and C_AuctionHouse and H.IsOpen()) then roll.active = false return end
  C_Timer.After(ROLL_EVERY, RollTick)
  if roll.cur or Busy() or not H.Ready() then return end
  local id = PickOldest()
  if not id then return end
  roll.tried[id] = time()
  roll.cur = id
  roll.token = roll.token + 1
  local my = roll.token
  local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  roll.ours = true
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), sorts, true)
  roll.ours = false
  if not ok then roll.cur = nil CP.RecordError("rolling refresh search", err) return end
  C_Timer.After(ROLL_TIMEOUT, function() if roll.token == my then roll.cur = nil end end)
end

function L.RollEvent(event, a)
  if event == "AUCTION_HOUSE_CLOSED" then roll.cur = nil roll.active = false return end
  local id = roll.cur
  if not id then return end
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if a ~= id then return end
    ReadCommodity(id)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if not (type(a) == "table" and a.itemID == id) then return end
    ReadItems(a)
  else
    return
  end
  roll.cur = nil
  roll.token = roll.token + 1
  roll.count = roll.count + 1
  -- redraw the lists at most every 20 seconds so rows do not jump around while you read them
  if not roll.redraw then
    roll.redraw = true
    CP.After(20, function() roll.redraw = false if CP.Refresh and H.IsOpen() then CP:Refresh() end end)
  end
end

function L.RollStart()
  if roll.active or not RollOn() then return end
  roll.active = true
  C_Timer.After(ROLL_EVERY, RollTick)
end

-- a search you start yourself pauses the rolling refresh for a moment
if C_AuctionHouse and hooksecurefunc then
  for _, fn in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery" }) do
    if C_AuctionHouse[fn] then
      hooksecurefunc(C_AuctionHouse, fn, function() if not roll.ours and not L.running then roll.pausedUntil = GetTime() + 10 end end)
    end
  end
end

-- Live prices on their own: once per time the auction house is opened, as soon as the Crafts tab is showing and
-- nothing else (a scan, the game's own search) is busy. Starred crafts come first.
local auto = { pending = false, ticks = 0 }
local function AutoTick()
  if not auto.pending then return end
  auto.ticks = auto.ticks + 1
  if not (H.IsOpen() and CP.db and CP.db.settings.autoLive ~= false) or auto.ticks > 120 then auto.pending = false return end
  C_Timer.After(2, AutoTick)
  local at = CP.AHTab
  local view = at and at.Current and at.Current()
  if view ~= "crafts" or L.running then return end
  if CP.Scanner and CP.Scanner.IsRunning and CP.Scanner:IsRunning() then return end
  if not H.Ready() or GetTime() < roll.pausedUntil then return end
  local ids = L.VisibleIds()
  if #ids == 0 then return end
  auto.pending = false
  L.Start(ids)
end

local rev = CreateFrame("Frame")
rev:RegisterEvent("AUCTION_HOUSE_SHOW")
rev:SetScript("OnEvent", CP.Safe("rolling-start", function()
  CP.After(4, L.RollStart)
  if CP.db and CP.db.settings.autoLive ~= false then
    auto.pending, auto.ticks = true, 0
    CP.After(5, AutoTick)
  end
end))
