local ADDON, CP = ...
local S = {}
CP.Scanner = S

-- Full Auction House scan using C_AuctionHouse.ReplicateItems: the client
-- asks the server for every listing at once (Blizzard limits this to roughly
-- once per 15 minutes), then we read them out a slice per frame so the game
-- never hitches.
--
-- Stored per item: min (lowest unit buyout), ref (median of the lowest 3 unit
-- buyouts, resistant to a single lowball), qty (units listed with a buyout),
-- n (listing count), time. Recipe items additionally get history + sales
-- tracking (see History.lua).

local CHUNK = 600            -- auctions read per frame
local WAIT_LIMIT = 90        -- seconds to wait for the server's reply
local COOLDOWN = 15 * 60     -- Blizzard's full-scan throttle, approximately

local st = { running = false }
local frame = CreateFrame("Frame")
local ahOpen = false

local function AHOpen()
  if ahOpen then return true end
  return AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

local function Status(text)
  if CP.UI and CP.UI.SetStatus then CP.UI.SetStatus(text) end
end

function S:IsRunning() return st.running end
function S.IsAHOpen() return AHOpen() and true or false end

function S:Abort(reason)
  if not st.running then return end
  st.running = false
  CP:Print("Scan stopped: " .. reason)
  Status("Scan stopped: " .. reason)
end

-- Items whose listings we track in detail: anything used by a captured recipe
local function TrackedSet()
  local set = {}
  for _, profs in pairs(CP.db.recipes) do
    for _, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        set[r.id] = true
        for _, g in ipairs(r.reagents) do
          for _, id in ipairs(g.ids or { g.id }) do set[id] = true end
        end
      end
    end
  end
  return set
end

local function Finish()
  local now = time()
  local prices = {}
  local priced = 0

  for id, a in pairs(st.acc) do
    local p = a.prices
    table.sort(p)
    local entry = { qty = a.qty, n = #p, time = now, min = p[1], ref = (#p >= 3) and p[2] or p[1] }
    prices[id] = entry
    priced = priced + 1
  end
  -- tracked items with no listings right now still get an (empty) entry
  for id in pairs(st.set) do
    if not prices[id] then prices[id] = { qty = 0, n = 0, time = now } end
  end
  CP.db.prices = prices

  local tracked, recorded = 0, 0
  for id in pairs(st.set) do
    tracked = tracked + 1
    local a = st.acc[id]
    local ok, err = pcall(CP.History.Record, id, prices[id], a and a.sigs, now)
    if ok then recorded = recorded + 1 else CP.RecordError("history", err) end
  end

  CP.db.lastScan = now
  st.running = false
  CP:Print(("Scan complete: %d auctions, %d items priced, %d recipe items tracked."):format(st.n or 0, priced, tracked))
  if tracked == 0 then
    CP:Print("No recipes were known during this scan, so no history was kept. Open your profession windows, then scan again.")
  end
  CP:Refresh()
end

local function ProcessAuction(i)
  local C = C_AuctionHouse
  local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = C.GetReplicateItemInfo(i)
  if not id or not buyout or buyout <= 0 or not count or count <= 0 then return end

  -- The scan reports each auction's buyout as the TOTAL for its stack (confirmed
  -- against the live AH). /pf unit unit switches to per-unit if a client differs.
  local total = buyout
  if CP.db.settings.replicateUnit == "unit" then total = buyout * count end
  local unit = math.floor(total / count * 100 + 0.5) / 100   -- keep fractions of a copper

  local a = st.acc[id]
  if not a then a = { prices = {}, qty = 0, sigs = {} }; st.acc[id] = a end
  a.prices[#a.prices + 1] = unit
  a.qty = a.qty + count

  if st.set[id] then
    local sig = count .. "x" .. total
    -- time-left band: 0 short .. 3 very long  ->  1 .. 4
    local tl = (C.GetReplicateItemTimeLeft and C.GetReplicateItemTimeLeft(i) or 2) + 1
    local e = a.sigs[sig]
    if not e then
      a.sigs[sig] = { c = 1, units = count, tl = tl }
    else
      e.c = e.c + 1
      if tl < e.tl then e.tl = tl end
    end
  end
end

function S:Start(force)
  if st.running then CP:Print("A scan is already running."); return end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems) then
    CP:Print("This client has no full-scan API. Type /pf debug for details.")
    return
  end
  if not AHOpen() then CP:Print("Open the Auction House first."); return end

  -- Blizzard ignores full-scan requests made too soon after the last one, which would leave
  -- the window waiting for a reply that never comes. Say so instead of sending a doomed request.
  local since = time() - (CP.db.lastScan or 0)
  if not force and CP.db.lastScan and CP.db.lastScan > 0 and since < COOLDOWN then
    local msg = ("Last full scan finished %dm ago. Blizzard limits full scans to about one per 15 minutes; try again in ~%dm. (/pf scan force tries anyway.)")
      :format(math.floor(since / 60), math.ceil((COOLDOWN - since) / 60))
    CP:Print(msg)
    Status(msg)
    return
  end
  CP.db.lastReplicate = time()

  st = { running = true, state = "waiting", t = 0, acc = {}, set = TrackedSet(), n = 0 }
  Status("Requesting all auctions from the server...")
  C_AuctionHouse.ReplicateItems()
end

CP.Register(frame, "REPLICATE_ITEM_LIST_UPDATE")
CP.Register(frame, "AUCTION_HOUSE_SHOW")
CP.Register(frame, "AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", CP.Safe("scanner", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    -- fully automatic: refresh prices whenever the AH opens and data is stale
    if CP.db and CP.db.settings.autoScan and time() - (CP.db.lastScan or 0) > COOLDOWN then
      CP.After(1.5, function() if AHOpen() then S:Start() end end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    if st.running and st.state == "waiting" then
      st.state = "processing"
      st.n = C_AuctionHouse.GetNumReplicateItems() or 0
      st.pi = 0
    end
  end
end))

local function Tick(elapsed)
  if not st.running then return end

  if st.state == "waiting" then
    st.t = st.t + elapsed
    if st.t > WAIT_LIMIT then S:Abort("no reply from the server (full scans are throttled; try again in a few minutes).") end
    return
  end

  if st.state == "processing" then
    if st.n == 0 then S:Abort("the server returned no auctions."); return end
    local last = math.min(st.n - 1, st.pi + CHUNK - 1)
    for i = st.pi, last do ProcessAuction(i) end
    st.pi = last + 1
    Status(("Reading auctions: %d / %d"):format(math.min(st.pi, st.n), st.n))
    if st.pi >= st.n then Finish() end
  end
end

frame:SetScript("OnUpdate", function(_, elapsed)
  if not st.running then return end
  local ok, err = pcall(Tick, elapsed)
  if not ok then
    CP.RecordError("scan", err)
    S:Abort("an error occurred (see /pf errors).")
  end
end)
