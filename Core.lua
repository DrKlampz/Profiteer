local ADDON, CP = ...
_G.Profiteer = CP

CP.version = "0.6.1"

------------------------------------------------------------------------
-- Saved variables (account-wide, so every alt sees the same data)
------------------------------------------------------------------------
local DEFAULTS = {
  recipes = {},    -- [charKey][profession] = { recipe, ... }
  prices = {},     -- [itemID] = { min, ref, qty, n, time }
  vendor = {},     -- [itemID] = copper price per unit (seen at a vendor)
  names = {},      -- [itemID] = item name
  inventory = {},  -- [charKey] = { bags = {[id]=n}, bank = {[id]=n}, time }
  chars = {},      -- [charKey] = { class, seen }
  history = {},    -- [itemID] = { snapshot, ... }  (see History.lua)
  listings = {},   -- [itemID] = { t, sigs }  last scan's listings, for sales tracking
  lastScan = 0,
  sessions = 0,    -- how many times this file has been loaded (persistence check)
  settings = {
    ahCut = 0.05,          -- AH cut on a sale
    minProfit = 0,         -- copper
    minListed = 3,         -- hide outputs with fewer units listed than this (one listing isn't a market)
    craftableOnly = false,
    sortKey = "ratio",
    sortDesc = true,
    minimapHide = false,
    minimapAngle = 215,
    minimapOffset = 12,    -- pixels beyond the minimap edge
    minimapFree = false,   -- true after a Shift+drag (free placement)
    ahAutoOpen = false,    -- open the Profiteer panel automatically with the AH
    tracked = {},          -- [prof:itemID] = true, crafts pinned to the top
    priceBasis = "safe",   -- "safe" = min(current, 14-day median), or "current"
    minSales = 0,          -- hide crafts estimated to sell fewer than this per day
    tooltips = true,
    autoScan = true,       -- scan when the AH opens (if data is older than 15 min)
    replicateUnit = "total",-- "total": scanned buyout is the whole stack's price; "unit": per unit
  },
}

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function CP:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Profiteer:|r " .. tostring(msg))
end

function CP.ItemID(link)
  if not link or type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

function CP.ItemName(id)
  local n = CP.db and CP.db.names[id]
  if n then return n end
  if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
  return n or ("item " .. id)
end

function CP.ShortName(charKey)
  return (charKey:match("^(.-)%-") or charKey)
end

function CP.Money(copper)
  if not copper then return "|cff888888--|r" end
  local neg = copper < 0
  local c = math.abs(math.floor(copper + 0.5))
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local cc = c % 100
  local t = ""
  if g > 0 then t = t .. g .. "|cffffd700g|r " end
  if g > 0 or s > 0 then t = t .. s .. "|cffc7c7cfs|r " end
  t = t .. cc .. "|cffeda55fc|r"
  if neg then t = "|cffff4040-|r" .. t end
  return t
end

-- Money as plain text (no colour codes), for copyable windows
function CP.MoneyPlain(copper)
  if not copper then return "?" end
  local neg = copper < 0
  local c = math.abs(math.floor(copper + 0.5))
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local cc = c % 100
  local t = ""
  if g > 0 then t = g .. "g " end
  if g > 0 or s > 0 then t = t .. s .. "s " end
  t = t .. cc .. "c"
  return (neg and "-" or "") .. t
end

function CP.Age(t)
  if not t or t == 0 then return "never" end
  local d = time() - t
  if d < 90 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- Register an event without dying if this client doesn't know it
function CP.Register(frame, event)
  return pcall(frame.RegisterEvent, frame, event)
end

-- Error capture: a failing handler never spams the default error popup;
-- it is stored for /pf errors so it can be pasted for debugging.
CP.errors = {}
function CP.RecordError(label, err)
  table.insert(CP.errors, 1, label .. ": " .. tostring(err))
  while #CP.errors > 10 do table.remove(CP.errors) end
  if not CP.errorAnnounced then
    CP.errorAnnounced = true
    CP:Print("Something failed in " .. label .. ". Type /pf errors to see details.")
  end
end

function CP.Safe(label, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then CP.RecordError(label, err) end
  end
end

-- Tiny timer (doesn't rely on C_Timer)
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function(_, elapsed)
  for i = #timers, 1, -1 do
    local t = timers[i]
    t.left = t.left - elapsed
    if t.left <= 0 then
      table.remove(timers, i)
      local ok, err = pcall(t.fn)
      if not ok then CP.RecordError("timer", err) end
    end
  end
end)
function CP.After(delay, fn)
  timers[#timers + 1] = { left = delay, fn = fn }
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local f = CreateFrame("Frame")
CP.Register(f, "ADDON_LOADED")
CP.Register(f, "PLAYER_LOGIN")
f:SetScript("OnEvent", CP.Safe("init", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    ProfiteerDB = ProfiteerDB or {}
    CopyDefaults(ProfiteerDB, DEFAULTS)
    CP.db = ProfiteerDB
    CP.db.sessions = (CP.db.sessions or 0) + 1
    CP.db.created = CP.db.created or time()
    -- schema 2: earlier versions read scanned prices as per-unit when they are
    -- per-stack totals, so stored prices, history and sales data are wrong.
    if (CP.db.schema or 0) < 2 then
      CP.db.settings.replicateUnit = "total"
      CP.db.prices, CP.db.history, CP.db.listings = {}, {}, {}
      CP.db.lastScan, CP.db.lastReplicate = 0, 0
      CP.db.schema = 2
      CP.migrated = true
    end
    -- schema 3: a single listing is not a market price, so the default filter is 3 units
    if (CP.db.schema or 0) < 3 then
      if CP.db.settings.minListed == 1 then CP.db.settings.minListed = 3 end
      CP.db.schema = 3
    end
  elseif event == "PLAYER_LOGIN" then
    CP.charKey = UnitName("player") .. "-" .. GetRealmName()
    local _, class = UnitClass("player")
    CP.db.chars[CP.charKey] = { class = class, seen = time() }
    if CP.migrated then
      CP:Print("Earlier versions misread AH prices, so old price data was cleared. Open the Auction House to rescan.")
    end
  end
end))

------------------------------------------------------------------------
-- Diagnostics
------------------------------------------------------------------------
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function Debug(arg)
  if arg == "rows" then
    if not (C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems) then CP:Print("No replicate API."); return end
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    CP:Print("Replicate rows held by the client: " .. n .. " (run a scan first)")
    for i = 0, math.min(n - 1, 5) do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = C_AuctionHouse.GetReplicateItemInfo(i)
      CP:Print(("  [%d] item %s count=%s buyout=%s"):format(i, tostring(id), tostring(count), tostring(buyout)))
    end
    CP:Print("Buyout is the stack's total price; Profiteer divides by count to get the per-unit price.")
    return
  end

  local version, build, _, iface = GetBuildInfo()
  CP:Print(("Profiteer %s | client %s (%s) interface %s"):format(CP.version, tostring(version), tostring(build), tostring(iface)))
  local function has(label, ok) CP:Print(("  %-34s %s"):format(label, ok and "yes" or "MISSING")) end
  has("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs)
  has("C_TradeSkillUI.GetRecipeSchematic", C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)
  has("C_AuctionHouse.ReplicateItems", C_AuctionHouse and C_AuctionHouse.ReplicateItems)
  has("C_AuctionHouse.GetReplicateItemInfo", C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo)
  has("C_Container", C_Container)
  has("TooltipDataProcessor", TooltipDataProcessor)
  has("AuctionHouseFrame", AuctionHouseFrame)
  CP:Print(("Data: %d characters, %d priced items, %d items with history, last scan %s"):format(
    Count(CP.db.chars), Count(CP.db.prices), Count(CP.db.history), CP.Age(CP.db.lastScan)))
  CP:Print(("Saved data loaded %d time(s) since %s. If this stays at 1 after relogging, the client isn't restoring SavedVariables."):format(
    CP.db.sessions or 0, date and date("%Y-%m-%d %H:%M", CP.db.created) or "?"))
  CP:Print("/pf debug rows prints raw AH scan rows. /pf errors lists captured errors.")
end

------------------------------------------------------------------------
-- /pf why <craft>: shows exactly how one craft's numbers are built
------------------------------------------------------------------------
local function Explain(query)
  query = (query or ""):lower()
  if query == "" then CP:Print("usage: /pf why <craft name>   e.g. /pf why bolt of linen cloth"); return end

  local best, bestChar, bestProf
  for charKey, profs in pairs(CP.db.recipes) do
    for prof, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        local name = r.name:lower()
        if name == query then best, bestChar, bestProf = r, charKey, prof; break end
        if not best and name:find(query, 1, true) then best, bestChar, bestProf = r, charKey, prof end
      end
      if best and best.name:lower() == query then break end
    end
    if best and best.name:lower() == query then break end
  end
  if not best then CP:Print("No captured recipe matches '" .. query .. "'. Try /pf chars.") return end

  local L = {}
  local function add(s) L[#L + 1] = s end
  local M = CP.MoneyPlain
  local p = CP.db.prices[best.id]
  add(("%s (item %d), makes %s, known by %s (%s)"):format(best.name, best.id, tostring(best.yield), CP.ShortName(bestChar), bestProf))
  add(("  sells: lowest %s | reference %s | %s units in %s listings | price used %s"):format(
    p and p.min and M(p.min) or "none", p and p.ref and M(p.ref) or "none", tostring(p and p.qty or 0), tostring(p and p.n or 0),
    CP:SellPrice(best.id) and M(CP:SellPrice(best.id)) or "none"))
  local total = 0
  for _, rg in ipairs(best.reagents) do
    local ids = rg.ids or { rg.id }
    add(("  reagent: %dx, %d item option(s)"):format(rg.count, #ids))
    for _, id in ipairs(ids) do
      local ip = CP.db.prices[id]
      add(("    item %d %s: AH lowest %s | ref %s | %s units in %s listings | vendor %s"):format(
        id, CP.ItemName(id), ip and ip.min and M(ip.min) or "none", ip and ip.ref and M(ip.ref) or "none",
        tostring(ip and ip.qty or 0), tostring(ip and ip.n or 0), CP.db.vendor[id] and M(CP.db.vendor[id]) or "none"))
    end
    local c, src, id = CP:SlotCost(rg)
    if c then total = total + c * rg.count end
    add(("    -> counted: %s at %s each (%s)"):format(CP.ItemName(id), c and M(c) or "no price", src or "no price"))
  end
  add("  total material cost: " .. M(total))
  CP.Report.Open("Why: " .. best.name, L, "Ctrl+C copies this. Scroll with the mouse wheel.")
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local function PrintHelp()
  local s = CP.db.settings
  CP:Print("commands:")
  CP:Print("  /pf                  toggle the results window")
  CP:Print("  /pf scan             full AH scan (AH must be open; limited to about one per 15 min, /pf scan force overrides)")
  CP:Print("  /pf top              print the top 10 crafts to chat")
  CP:Print("  /pf chars            every character Profiteer knows, with recipes and bag age")
  CP:Print("  /pf forget <name>    remove a deleted or unwanted character's data")
  CP:Print("  /pf cut <percent>    AH cut (now " .. (s.ahCut * 100) .. "%)")
  CP:Print("  /pf minprofit <gold> hide crafts below this profit")
  CP:Print("  /pf minlisted <n>    hide outputs with fewer than n units listed (now " .. s.minListed .. ")")
  CP:Print("  /pf minsales <n>     hide crafts estimated to sell fewer than n per day")
  CP:Print("  /pf basis safe|current  price basis for sales (now " .. s.priceBasis .. ")")
  CP:Print("  /pf autoscan on|off  scan automatically when the AH opens (now " .. (s.autoScan and "on" or "off") .. ")")
  CP:Print("  /pf unit total|unit  is a scanned buyout the whole stack's price (normal) or per unit? (now " .. s.replicateUnit .. ")")
  CP:Print("  /pf tooltip          toggle AH info on item tooltips")
  CP:Print("  /pf ahopen on|off    open the Profiteer panel automatically with the AH (now " .. (s.ahAutoOpen and "on" or "off") .. ")")
  CP:Print("  /pf ahbutton         reset the AH window button to its default spot (drag it to move it)")
  CP:Print("  /pf minimap          show / hide the minimap button")
  CP:Print("  /pf minimap radius <n>  push the button further out (now " .. (s.minimapOffset or 12) .. ")   /pf minimap reset")
  CP:Print("  /pf shop [tracked]   send the materials for the top 10 (or your tracked) crafts to the AH search")
  CP:Print("  /pf track <craft>    pin / unpin a craft at the top of the list (or right-click its row)")
  CP:Print("  /pf missing          list the crafts left out for lack of prices, and why")
  CP:Print("  /pf why <craft>      show how one craft's cost and price were worked out")
  CP:Print("  /pf report           copyable diagnostic report (use this when something's wrong)")
  CP:Print("  /pf debug [rows]     client/API diagnostics   /pf errors   captured errors")
  CP:Print("  /pf reset prices     wipe price data and history")
end

SLASH_PROFITEER1 = "/profiteer"
SLASH_PROFITEER2 = "/pf"
SlashCmdList["PROFITEER"] = function(msg)
  if not CP.db then return end
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  arg = arg:lower()
  local s = CP.db.settings

  if cmd == "" then
    CP.UI.Toggle()
  elseif cmd == "scan" then
    CP.Scanner:Start(arg == "force")
  elseif cmd == "top" then
    local results = CP:BuildResults()
    local lines = {}
    if #results == 0 then
      lines[1] = "No results yet. Capture recipes and scan the AH first."
    else
      local n = math.min(25, #results)
      lines[1] = ("Top %d of %d crafts, sorted by %s:"):format(n, #results, s.sortKey)
      lines[2] = ""
      for i = 1, n do
        local g = results[i]
        local who = {}
        for _, k in ipairs(g.chars) do who[#who + 1] = CP.ShortName(k) end
        lines[#lines + 1] = ("%d. %s | %s | cost %s | sells %s net | profit %s | ROI %d%% | listed %d | sold/day %s"):format(
          i, g.name, table.concat(who, ", "), CP.MoneyPlain(g.cost), CP.MoneyPlain(g.revenue),
          CP.MoneyPlain(g.profit), math.floor(g.ratio * 100 + 0.5), g.listed,
          g.perDay and ("%.1f"):format(g.perDay) or "?")
      end
    end
    CP.Report.Open("Top crafts", lines, "Ctrl+C copies the list. Scroll with the mouse wheel.")
  elseif cmd == "chars" then
    -- every character Profiteer has seen, with what it knows about each
    local seen = {}
    for k in pairs(CP.db.chars) do seen[k] = true end
    for k in pairs(CP.db.recipes) do seen[k] = true end
    local lines = {}
    for charKey in pairs(seen) do
      local parts = {}
      for prof, list in pairs(CP.db.recipes[charKey] or {}) do parts[#parts + 1] = prof .. " " .. #list end
      table.sort(parts)
      local inv = CP.db.inventory[charKey]
      lines[#lines + 1] = ("%s: %s | bags seen %s"):format(CP.ShortName(charKey),
        #parts > 0 and table.concat(parts, ", ") or "no recipes yet (open its profession windows)",
        inv and CP.Age(inv.time) or "never")
    end
    table.sort(lines)
    if #lines == 0 then lines[1] = "No characters yet." end
    CP.Report.Open("Characters", lines, "Ctrl+C copies the list. Scroll with the mouse wheel.")
  elseif cmd == "shop" then
    CP.Shop.Command(arg)
  elseif cmd == "track" then
    CP.Shop.TrackByName(msg:match("^%S*%s*(.-)$"))
  elseif cmd == "forget" then
    local target, removed = arg, 0
    if target == "" then CP:Print("usage: /pf forget <character name>") else
      for _, tbl in ipairs({ CP.db.recipes, CP.db.inventory, CP.db.chars }) do
        for k in pairs(tbl) do
          if CP.ShortName(k):lower() == target then tbl[k] = nil; removed = removed + 1 end
        end
      end
      CP:Print(removed > 0 and ("Removed " .. target .. " from Profiteer.") or ("No saved data for " .. target .. "."))
      CP:Refresh()
    end
  elseif cmd == "cut" then
    local v = tonumber(arg)
    if v and v >= 0 and v < 100 then s.ahCut = v / 100; CP:Print("AH cut set to " .. v .. "%"); CP:Refresh()
    else CP:Print("usage: /pf cut 5") end
  elseif cmd == "minprofit" then
    local v = tonumber(arg)
    if v then s.minProfit = v * 10000; CP:Print("Min profit set to " .. v .. "g"); CP:Refresh()
    else CP:Print("usage: /pf minprofit 2") end
  elseif cmd == "minlisted" then
    local v = tonumber(arg)
    if v then s.minListed = v; CP:Print("Min listings set to " .. v); CP:Refresh()
    else CP:Print("usage: /pf minlisted 3") end
  elseif cmd == "minsales" then
    local v = tonumber(arg)
    if v then s.minSales = v; CP:Print("Min sales/day set to " .. v .. " (unknown rates always shown)"); CP:Refresh()
    else CP:Print("usage: /pf minsales 2") end
  elseif cmd == "basis" then
    if arg == "safe" or arg == "current" then s.priceBasis = arg; CP:Print("Price basis: " .. arg); CP:Refresh()
    else CP:Print("usage: /pf basis safe|current (now " .. s.priceBasis .. ")") end
  elseif cmd == "autoscan" then
    if arg == "on" or arg == "off" then s.autoScan = (arg == "on"); CP:Print("Auto-scan " .. arg)
    else CP:Print("usage: /pf autoscan on|off") end
  elseif cmd == "unit" then
    if arg == "unit" or arg == "total" then s.replicateUnit = arg; CP:Print("Scanned buyout treated as " .. (arg == "unit" and "per unit" or "the stack's total") .. ". Rescan to apply.")
    else CP:Print("usage: /pf unit total|unit (now " .. s.replicateUnit .. ")") end
  elseif cmd == "tooltip" then
    s.tooltips = not s.tooltips
    CP:Print("Item tooltips " .. (s.tooltips and "on" or "off") .. ".")
  elseif cmd == "ahopen" then
    if arg == "on" or arg == "off" then s.ahAutoOpen = (arg == "on"); CP:Print("Open with the AH: " .. arg)
    else CP:Print("usage: /pf ahopen on|off (now " .. (s.ahAutoOpen and "on" or "off") .. ")") end
  elseif cmd == "ahbutton" then
    CP.UI.ResetAHButton()
    CP:Print("AH button moved back to its default spot. Drag it to place it elsewhere.")
  elseif cmd == "minimap" then
    CP.Minimap.Command(arg)
  elseif cmd == "debug" then
    Debug(arg)
  elseif cmd == "report" then
    CP.Report.Show()
  elseif cmd == "missing" then
    CP:BuildResults()
    local list = CP.skippedList or {}
    local lines = {}
    if #list == 0 then
      lines[1] = "Every captured craft has prices."
    else
      lines[1] = #list .. " craft(s) left out of the ranking for lack of prices:"
      lines[2] = ""
      for _, l in ipairs(list) do lines[#lines + 1] = l end
    end
    CP.Report.Open("Crafts left out", lines, "Ctrl+C copies the list. Scroll with the mouse wheel.")
  elseif cmd == "why" then
    Explain(msg:match("^%S*%s*(.-)$"))
  elseif cmd == "errors" then
    if #CP.errors == 0 then CP:Print("No errors captured this session.") end
    for i, e in ipairs(CP.errors) do CP:Print(i .. ". " .. e) end
  elseif cmd == "reset" and arg == "prices" then
    CP.db.prices = {}
    CP.db.history = {}
    CP.db.listings = {}
    CP.db.lastScan = 0
    CP:Print("Price data and history cleared.")
    CP:Refresh()
  else
    PrintHelp()
  end
end
