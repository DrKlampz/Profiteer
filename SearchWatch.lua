-- SearchWatch: when the auction house's own search seems stuck ("Searching..." that never ends), this writes down why.
-- It only watches and records (read it with /issues profiteer); it never sends or cancels anything.
local _, CP = ...
local pending
local counts = {}

local function Who()
  local ok, stack = pcall(debugstack, 3, 10, 0)
  if ok and type(stack) == "string" then return stack:match("AddOns[\\/]([^\\/]+)[\\/]") or "game" end
  return "unknown"
end

local function QueueReady()
  if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
    local ok, r = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and tostring(r) or "error"
  end
  return "n/a"
end

local function Summary()
  local parts = {}
  for ev, n in pairs(counts) do parts[#parts + 1] = ("%s x%d"):format((ev:gsub("^AUCTION_HOUSE_", "")), n) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function Begin(name)
  local who = Who()
  counts = {}
  local my = { name = name, who = who, t = GetTime() }
  pending = my
  C_Timer.After(12, function()
    if pending ~= my then return end
    pending = nil
    local scan = CP.Scanner and CP.Scanner.IsRunning and CP.Scanner:IsRunning()
    local live = CP.Live and CP.Live.running
    if CP.Issue then
      CP.Issue("warn", "search stuck", ("%s from %s got no answer in 12 s. queueReady=%s, full scan running=%s, live prices running=%s, events: %s")
        :format(name, who, QueueReady(), tostring(scan and true or false), tostring(live and true or false), Summary() ~= "" and Summary() or "none"))
    end
  end)
end

if C_AuctionHouse then
  for _, name in ipairs({ "SendSellSearchQuery", "SendSearchQuery", "SendBrowseQuery" }) do
    if type(C_AuctionHouse[name]) == "function" then pcall(hooksecurefunc, C_AuctionHouse, name, function() pcall(Begin, name) end) end
  end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_CLOSED" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev)
  if not pending then return end
  counts[ev] = (counts[ev] or 0) + 1
  if ev == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    local n = C_AuctionHouse and C_AuctionHouse.GetNumBrowseResults and C_AuctionHouse.GetNumBrowseResults()
    if CP.Issue then CP.Issue("warn", "browse answer", ("%s from %s answered with %s results (queueReady=%s)"):format(pending.name, pending.who, tostring(n), QueueReady())) end
    pending = nil
  elseif ev == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if CP.Issue then CP.Issue("warn", "browse failed", ("%s from %s: the game reported a browse failure (queueReady=%s)"):format(pending.name, pending.who, QueueReady())) end
    pending = nil
  elseif ev == "ITEM_SEARCH_RESULTS_UPDATED" or ev == "COMMODITY_SEARCH_RESULTS_UPDATED" or ev == "AUCTION_HOUSE_CLOSED" then pending = nil end
end)
