local ADDON, CP = ...
local H = {}
CP.History = H

-- Per-item price history plus a sales-rate estimate.
--
-- Every scan of a tracked item stores a snapshot (lowest price, reference
-- price, units listed, listing count). We also keep the previous scan's
-- listings as a multiset of "stackSize x buyout". Listings that vanished
-- between two scans were either sold, cancelled or expired. Every listing
-- carries a time-left bracket, so we can estimate how likely it is that a
-- vanished one simply expired and count the rest as sold. Cancellations can't
-- be told apart from sales, so treat the rate as a rough (slightly high)
-- estimate that improves with more scans.

local MAX_ENTRIES = 30
local KEEP = 30 * 86400      -- drop snapshots older than this
local MIN_GAP = 600          -- ignore re-scans within 10 minutes of the last one
local MAX_DT = 86400         -- only compare scans at most a day apart
local WINDOW = 14 * 86400    -- stats look at the last two weeks

-- GetAuctionItemTimeLeft brackets, in seconds remaining (lo, hi)
local BRACKET = {
  [1] = { 0, 1800 },
  [2] = { 1800, 7200 },
  [3] = { 7200, 43200 },
  [4] = { 43200, 172800 },
}

local function SoldWeight(tl, dt)
  local b = BRACKET[tl] or BRACKET[3]
  local expired = (dt - b[1]) / (b[2] - b[1])
  if expired < 0 then expired = 0 elseif expired > 1 then expired = 1 end
  return 1 - expired
end

function H.Record(id, entry, sigs, now)
  local db = CP.db
  local base = db.listings[id]
  if base and now - base.t < MIN_GAP then return end

  local snap = { t = now, min = entry.min, ref = entry.ref, qty = entry.qty, n = entry.n }

  if base then
    local dt = now - base.t
    if dt <= MAX_DT then
      local sold = 0
      for sig, prev in pairs(base.sigs) do
        local cur = (sigs and sigs[sig] and sigs[sig].c) or 0
        local gone = prev.c - cur
        if gone > 0 then
          sold = sold + gone * prev.units * SoldWeight(prev.tl, dt)
        end
      end
      snap.sold = math.floor(sold * 10 + 0.5) / 10
      snap.dt = dt
    end
  end

  local list = db.history[id]
  if not list then list = {}; db.history[id] = list end
  list[#list + 1] = snap
  while #list > MAX_ENTRIES or (#list > 1 and now - list[1].t > KEEP) do
    table.remove(list, 1)
  end

  db.listings[id] = { t = now, sigs = sigs or {} }
end

local function Median(t)
  local n = #t
  if n == 0 then return nil end
  table.sort(t)
  if n % 2 == 1 then return t[(n + 1) / 2] end
  return (t[n / 2] + t[n / 2 + 1]) / 2
end

-- Returns nil with no data, otherwise:
--   median   median reference price over the window
--   samples  number of scans behind it
--   perDay   estimated units sold per day (nil until enough observed time)
function H.Stats(id)
  local list = CP.db and CP.db.history[id]
  if not list or #list == 0 then return nil end
  local now = time()
  local refs, sold, dt = {}, 0, 0
  for i = #list, 1, -1 do
    local s = list[i]
    if now - s.t > WINDOW then break end
    if s.ref then refs[#refs + 1] = s.ref end
    if s.sold and s.dt then
      sold = sold + s.sold
      dt = dt + s.dt
    end
  end
  local stats = { samples = #refs, median = Median(refs) }
  if dt >= 6 * 3600 then stats.perDay = sold / dt * 86400 end
  return stats
end
