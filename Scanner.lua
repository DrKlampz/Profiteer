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
local WAIT_LIMIT = 240        -- seconds to wait for the server's reply
local COOLDOWN = 2 * 3600    -- this server refuses repeat full scans for well over 15 min (observed: >86 min, <7.7 h)

local st = { running = false }
local frame = CreateFrame("Frame")
local ahOpen = false
local PARTIAL_WAIT = 90       -- seconds: a list far smaller than last time is probably still arriving, so keep waiting up to this long

-- the game's throttle chatter during a scan is counted and written as ONE summary line (and only when something went wrong),
-- instead of one issue per event, which used to bury every real issue
local function Trace(ev)
  if not (st.running and st.trace) then return end
  local t = st.trace
  t.counts[ev] = (t.counts[ev] or 0) + 1
  t.order[#t.order + 1] = ev
end
local function FlushTrace(why)
  local t = st.trace
  if not t then return end
  st.trace = nil
  local bad = why or t.counts["AUCTION_HOUSE_BROWSE_FAILURE"] or t.counts["AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"]
  if not bad or not CP.Issue then return end
  local parts = {}
  for ev, n in pairs(t.counts) do parts[#parts + 1] = ("%s x%d"):format((ev:gsub("^AUCTION_HOUSE_", "")), n) end
  table.sort(parts)
  CP.Issue("warn", "scan trace", ("%s%s"):format(why and (why .. "; ") or "", table.concat(parts, ", ")))
end

-- Which add-on (or the game's own auction window) sends each request during a scan? Written into the same summary line.
local SENDERS = { "SendBrowseQuery", "SendSellSearchQuery", "SendSearchQuery", "QueryOwnedAuctions", "RequestMoreBrowseResults",
  "RequestMoreCommoditySearchResults", "ReplicateItems" }
local sendersHooked
local function HookSenders()
  if sendersHooked or not C_AuctionHouse then return end
  sendersHooked = true
  for _, name in ipairs(SENDERS) do
    if type(C_AuctionHouse[name]) == "function" then
      pcall(hooksecurefunc, C_AuctionHouse, name, function()
        if not (st.running and st.trace) then return end
        local who = "unknown"
        local ok, stack = pcall(debugstack, 1, 10, 0)
        if ok and type(stack) == "string" then who = stack:match("AddOns[\\/]([^\\/]+)[\\/]") or "game" end
        Trace(("CALL %s from %s"):format(name, who))
      end)
    end
  end
end
HookSenders()

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
  FlushTrace("stopped: " .. tostring(reason))
  st.running = false
  if CP.db then CP.db.lastAbort = { t = time(), reason = tostring(reason), state = st.state, n = st.n } end
  if CP.Issue then CP.Issue("warn", "scan stopped", tostring(reason) .. " (state " .. tostring(st.state) .. ")") end
  CP:Print("Scan stopped: " .. reason)
  Status("Scan stopped: " .. reason)
end

-- Items whose listings we track in detail: anything used by a captured recipe
local function TrackedSet()
  local set = {}
  for _, src in ipairs({ CP.db.recipes, CP.db.unlearned or {} }) do
  for _, profs in pairs(src) do
    for _, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        set[r.id] = true
        for _, g in ipairs(r.reagents) do
          for _, id in ipairs(g.ids or { g.id }) do set[id] = true end
        end
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
  -- a read much smaller than the last one is probably partial: keep what we knew about everything it did not mention
  local prevN = CP.db.lastN or 0
  if prevN > 0 and (st.n or 0) < prevN * 0.5 then
    for id, e in pairs(CP.db.prices or {}) do prices[id] = e end
    if CP.Issue then CP.Issue("warn", "partial scan", ("read %d auctions, last time %d: kept older prices for items it did not list"):format(st.n or 0, prevN)) end
    FlushTrace("partial list")
  end
  if not (prevN > 0 and (st.n or 0) < prevN * 0.5) then CP.db.lastN = st.n or 0 end
  FlushTrace(nil)

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

  -- remember the last price of everything seen, so an item that is not listed right now (armor, weapons, one-offs)
  -- still shows what it last sold for. Kept apart from CP.db.prices so cost and profit maths never use stale prices.
  local seen = CP.db.lastSeen
  if type(seen) ~= "table" then seen = {}; CP.db.lastSeen = seen end
  for id, a in pairs(st.acc) do
    local e = prices[id]
    if e and e.min then seen[id] = { e.min, e.ref or e.min, now } end
  end
  for id, v in pairs(seen) do
    if type(v) ~= "table" or not v[3] or now - v[3] > 60 * 86400 then seen[id] = nil end
  end

  local tracked, recorded = 0, 0
  for id in pairs(st.set) do
    tracked = tracked + 1
    local a = st.acc[id]
    local ok, err = pcall(CP.History.Record, id, prices[id], a and a.sigs, now)
    if ok then recorded = recorded + 1 else CP.RecordError("history", err) end
  end

  -- the rest of the auction house: keep a few price snapshots per item, so it all has a history
  if CP.db.settings.scanAll ~= false then
    local lite = 0
    for id, a in pairs(st.acc) do
      if not st.set[id] and CP.History.RecordLite then
        if pcall(CP.History.RecordLite, id, prices[id], now) then lite = lite + 1 end
      end
    end
    CP.db.lastLite = lite
  end

  CP.db.lastScan = now
  st.running = false
  CP:Print(("Scan complete: %d auctions, %d items priced, %d recipe items tracked. (server wait %ds, reading %.1fs)"):format(st.n or 0, priced, tracked, st.waited or 0, st.readT or 0))
  if CP.db then CP.db.lastTiming = { waited = st.waited or 0, read = st.readT or 0, n = st.n or 0, t = time() } end
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

-- seconds until a full scan may be requested again: ~15 min after a finished scan or an answered request,
-- and an hour after a request the server never answered: this server refuses repeat scans for much longer than 15 minutes,
-- and asking again too soon may only prolong that
function S.WaitLeft()
  local d = CP.db or {}
  local now = time()
  local left = COOLDOWN - (now - (d.lastScan or 0))
  local req = d.lastReplicate or 0
  if req > 0 then
    local replied = (d.lastReplyAt or 0) >= req
    left = math.max(left, COOLDOWN - (now - req))
  end
  return math.max(0, left)
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
  local left = S.WaitLeft()
  if not force and left > 0 then
    local msg = ("This server limits full scans; try again in ~%dm. (/pf scan force tries anyway.)")
      :format(math.ceil(left / 60))
    CP:Print(msg)
    Status(msg)
    return
  end
  -- (the time of the request is noted when it is actually sent)

  -- the game queues auction requests and drops one made while its queue is busy: wait until it is ready, then send
  st = { running = true, state = "queued", t = 0, acc = {}, set = TrackedSet(), n = 0, trace = { counts = {}, order = {} } }
  Status("Waiting for the auction house to be ready...")
end


-- /pf scantest: ask for the full auction list with none of Profiteer's own logic in the way, and write a
-- timeline of everything the game does about it (events, queue state, how many auctions it holds) into /issues.
function S.RawTest()
  if st.running then CP:Print("A scan is running; wait for it to finish first.") return end
  if not AHOpen() then CP:Print("Open the Auction House first.") return end
  local C = C_AuctionHouse
  local t0 = GetTime()
  local function log(msg)
    if CP.Issue then CP.Issue("warn", "raw scan test", ("%3ds  %s"):format(math.floor(GetTime() - t0), msg)) end
  end
  local function ready() if C.IsThrottledMessageSystemReady then local ok, r = pcall(C.IsThrottledMessageSystemReady) return ok and tostring(r) or "error" end return "n/a" end
  local function num() local ok, n = pcall(C.GetNumReplicateItems) return ok and n or "error" end
  log(("start: queueReady=%s held=%s build=%s"):format(ready(), tostring(num()), tostring(select(2, GetBuildInfo()))))
  local f = CreateFrame("Frame")
  local okAll = pcall(f.RegisterAllEvents, f)
  if not okAll then
    for _, ev in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
      "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
      "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED" }) do pcall(f.RegisterEvent, f, ev) end
  end
  f:SetScript("OnEvent", function(_, ev)
    if ev:find("AUCTION") or ev:find("REPLICATE") then log("event " .. ev) end
  end)
  local ok, err = pcall(C.ReplicateItems)
  log(("ReplicateItems called: ok=%s%s; queueReady now=%s"):format(tostring(ok), ok and "" or (" err=" .. tostring(err)), ready()))
  local n = 0
  local ticker
  ticker = C_Timer.NewTicker(5, function()
    n = n + 1
    local held = num()
    if n % 3 == 0 or (tonumber(held) or 0) > 0 then log(("check: held=%s queueReady=%s open=%s"):format(tostring(held), ready(), tostring(AHOpen()))) end
    if n >= 60 or (tonumber(held) or 0) > 0 and n >= 4 then
      ticker:Cancel()
      f:UnregisterAllEvents()
      log("finished")
      CP:Print("Scan test finished. Type /issues profiteer to read the timeline.")
    end
  end)
  CP:Print("Scan test running for up to 5 minutes. Keep the Auction House open and don't click around in it. Then type /issues profiteer.")
end

CP.Register(frame, "REPLICATE_ITEM_LIST_UPDATE")
CP.Register(frame, "AUCTION_HOUSE_SHOW")
for _, ev in ipairs({ "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
  CP.Register(frame, ev)
end
CP.Register(frame, "AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", CP.Safe("scanner", function(_, event, ...)
  if event:find("^AUCTION_HOUSE_THROTTLED") or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    -- what the game's request queue does while a scan is running (read with /issues)
    Trace(event)
    return
  end
  if event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    -- fully automatic: refresh prices whenever the AH opens and data is stale
    if CP.db and CP.db.settings.autoScan and S.WaitLeft() <= 0 then
      CP.After(1.5, function() if AHOpen() then S:Start() end end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    if CP.db then CP.db.lastReplyAt = time() end
    if st.running and st.state == "waiting" then
      local num = C_AuctionHouse.GetNumReplicateItems() or 0
      local prev = (CP.db and CP.db.lastN) or 0
      -- far fewer auctions than last time: the rest is still arriving (the first slice was mistaken for the whole list),
      -- so keep waiting; the poll in Tick starts the read once the count settles
      if not (num < prev * 0.5 and (st.t or 0) < PARTIAL_WAIT) then
        st.state = "processing" st.waited = st.t
        st.n = num
        st.pi = 0
      end
    end
  end
end))

local function Tick(elapsed)
  if not st.running then return end

  if st.state == "queued" then
    st.t = st.t + elapsed
    st.qt = st.t
    local ready = true
    if C_AuctionHouse.IsThrottledMessageSystemReady then
      local okr, r = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
      ready = (not okr) or r == true
    end
    if ready or st.t > 30 then
      st.state = "waiting" st.t = 0
      if CP.db then CP.db.lastReplicate = time() end
      Status("Requesting all auctions from the server...")
      local okq, err = pcall(C_AuctionHouse.ReplicateItems)
      if not okq then S:Abort("the game refused the request: " .. tostring(err)) end
    end
    return
  end

  if st.state == "waiting" then
    st.t = st.t + elapsed
    if math.floor(st.t) ~= st.shownT then
      st.shownT = math.floor(st.t)
      Status(("Waiting for the server to send the auction list... %ds (gives up after %d)"):format(st.shownT, WAIT_LIMIT))
    end
    -- the reply event can be missed or never sent: also look for the data itself every couple of seconds
    st.poll = (st.poll or 0) + elapsed
    if st.poll > 2 then
      st.poll = 0
      local okn, num = pcall(C_AuctionHouse.GetNumReplicateItems)
      -- the list fills in gradually: only start once the count has stopped growing (same on 3 checks in a row)
      if okn and (num or 0) > 0 then
        if num == st.lastNum then st.steady = (st.steady or 0) + 1 else st.steady = 0 end
        st.lastNum = num
        local prev = (CP.db and CP.db.lastN) or 0
        local tooSmall = num < prev * 0.5 and st.t < PARTIAL_WAIT      -- a first slice, not the whole list: keep waiting
        if st.steady >= 2 and not tooSmall then
          if CP.db then CP.db.lastReplyAt = time() CP.db.polledReply = true end
          st.state = "processing" st.n = num st.pi = 0 st.waited = st.t
          return
        end
      end
    end
    if st.t > WAIT_LIMIT then
      local left = math.ceil(S.WaitLeft() / 60)
      S:Abort("no reply from the server (full scans are throttled; " .. (left > 0 and ("try again in about " .. left .. " min") or "try again in a few minutes") .. ").")
    end
    return
  end

  if st.state == "processing" then
    if st.n == 0 then S:Abort("the server returned no auctions."); return end
    st.readT = (st.readT or 0) + elapsed
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
