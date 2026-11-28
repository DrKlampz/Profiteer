local ADDON, CP = ...
local UI = {}
CP.UI = UI

local MAXROWS, ROW_H, GAP = 40, 20, 4
local ROWS = 16   -- rows showing right now: grows with the window (UI.SetHeight)
local BASE_H = 470
local COLS = {
  { key = "name",     label = "Item",        w = 142, align = "LEFT",  sortable = true },
  { key = "prof",     label = "Profession",  w = 78,  align = "LEFT",  sortable = true },
  { key = "crafters", label = "Crafters",    w = 70,  align = "LEFT",  sortable = true },
  { key = "avgcost",  label = "Cost avg",    w = 85,  align = "RIGHT", sortable = true },
  { key = "costnow",  label = "Cost now",    w = 120,  align = "RIGHT", sortable = true },
  { key = "avgsell",  label = "Sells avg",   w = 85,  align = "RIGHT", sortable = true },
  { key = "sellnow",  label = "Sells now",   w = 120,  align = "RIGHT", sortable = true },
  { key = "profit",   label = "Profit",      w = 85,  align = "RIGHT", sortable = true },
  { key = "profitnow", label = "Profit now", w = 85,  align = "RIGHT", sortable = true },
  { key = "ratio",    label = "ROI",         w = 50,  align = "RIGHT", sortable = true },
  { key = "listed",   label = "Listed",      w = 45,  align = "RIGHT", sortable = true },
  { key = "perday",   label = "Sold/day",    w = 60,  align = "RIGHT", sortable = true },
  { key = "make",     label = "Can make",    w = 64,  align = "RIGHT", sortable = true },
  { key = "depth",    label = "Buy up to",   w = 82,  align = "RIGHT", sortable = true },
  { key = "depthprofit", label = "Profit if bought", w = 105, align = "RIGHT", sortable = true },
}
local TOTAL_W = 0
for _, c in ipairs(COLS) do TOTAL_W = TOTAL_W + c.w + GAP end
UI.baseW = TOTAL_W + 62

-- column widths grow when the window is wider than the table needs (the extra goes to the text columns)
local curTW = TOTAL_W
local colX, colW = {}, {}
local SHARE = { name = 0.4, prof = 0.15, crafters = 0.3, depth = 0.15 }
local function LayoutCols(extra)
  extra = math.max(0, extra or 0)
  local x = 0
  for _, c in ipairs(COLS) do
    local w = c.w + math.floor(extra * (SHARE[c.key] or 0))
    colX[c.key], colW[c.key] = x, w
    x = x + w + GAP
  end
  curTW = x
end
LayoutCols(0)
local function PaneW() return curTW + 12 end

-- Quotron-style price tick: an arrow and the percent today's price is above or below the average.
-- upIsGood: true for what you sell (a higher price is good), false for what you buy (a lower price is good).
local TICK = "|TInterface\\AddOns\\Profiteer\\Media\\Tick_%s:11:11:0:0|t"
local function Tick(now, avg, upIsGood)
  if not now or not avg or avg <= 0 then return "" end
  local pct = (now / avg - 1) * 100
  if math.abs(pct) < 1 then return "  " .. TICK:format("flat") .. " |cff999999" .. "0%|r" end
  local up = pct > 0
  local good = (up == upIsGood)
  local shown = math.abs(pct)
  local txt = shown >= 100 and ("%d%%"):format(math.floor(shown + 0.5)) or (shown >= 10 and ("%d%%"):format(math.floor(shown + 0.5)) or ("%.1f%%"):format(shown))
  return "  " .. TICK:format(up and "up" or "down") .. (good and " |cff40ff40" or " |cffff5050") .. txt .. "|r"
end

-- big counts shortened so they fit their columns (57227 -> 57k)
local function Compact(n)
  if type(n) ~= "number" then return tostring(n) end
  if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
  if n >= 10000 then return ("%dk"):format(math.floor(n / 1000 + 0.5)) end
  return tostring(math.floor(n + 0.5))
end
-- today's lowest price is far above the average: a spike, not a price to count on
local function Spiking(g) return g.liveSell and g.avgSell and g.avgSell > 0 and g.liveSell > g.avgSell * 1.5 end

-- what each column means, shown in the tooltip over its heading
local COLHELP = {
  avgcost = "Materials for one craft at their average price over the last two weeks (today's price for items with fewer than 3 scans). Materials you would make from raw ones are averaged the same way.",
  costnow = "Materials for one craft at today's lowest listings. The arrow and percent show how far today's price is from the average: green down-arrow = cheaper than average, red up-arrow = dearer.",
  avgsell = "What one craft sells for after the auction house cut, at the item's average price over the last two weeks (the 14-day median).",
  sellnow = "What one craft sells for after the cut, at today's lowest listing. The arrow and percent show how far today's price is from the average: green up-arrow = above average, red down-arrow = below. A \"!\" means a price spike: more than 50% above average.",
  profit = "Profit the ranking is based on: the cautious sell price (the lower of today's next-lowest price and the average) minus the materials.",
  profitnow = "Profit if you bought the materials and sold at today's lowest listings. Orange when today's price is a spike.",
  ratio = "Profit divided by the materials cost.",
  listed = "Units listed on the auction house (items, not listings).",
  perday = "Estimated items sold per day, from listings that disappear between scans. Counts items, so busy stackable goods read high.",
  make = "How many crafts the characters who know the recipe can make right now from their bags and bank.",
  depth = "How many crafts are worth making before the materials' prices climb past what the result sells for.",
  depthprofit = "The total profit if you buy up to that many crafts' worth of materials, make them all and sell at the price used.",
}
local rows = {}
UI.offset = 0

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function ShowTooltip(self)
  local g = self.data
  if not g then return end
  local left, screen = self:GetLeft(), UIParent:GetWidth()
  local onRight = type(left) == "number" and type(screen) == "number" and left > screen / 2
  local real = CP.AH and CP.AH.ItemTip(self, onRight and "ANCHOR_LEFT" or "ANCHOR_RIGHT", g.id)
  if real then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(g.prof, 0.6, 0.8, 1)
  else
    GameTooltip:AddLine(g.name, 1, 1, 1)
    GameTooltip:AddLine(g.prof, 0.6, 0.8, 1)
  end
  local dup = real and CP.db.settings.tooltips   -- the item tooltip already lists the AH price lines
  if g.unpriced then GameTooltip:AddLine("Not ranked: " .. (g.why or "no price data"), 1, 0.6, 0.3, true) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Reagents", 1, 0.82, 0)
  for _, rg in ipairs(g.reagents) do
    local c, src, id = CP:SlotCost(rg)
    local lv = CP:LiveReagent(id)
    GameTooltip:AddDoubleLine(rg.count .. "x " .. CP.ItemName(id),
      CP.Money(c and c * rg.count) .. (rg.count > 1 and c and (" |cff888888@ " .. CP.Money(c) .. " each|r") or "") .. " |cff888888(" .. (src == "made" and "from raw materials" or src or "?") .. ")|r", 1, 1, 1, 1, 1, 1)
    if lv and c and math.abs(lv - c) >= 1 then
      GameTooltip:AddDoubleLine("   lowest listing now", CP.Money(lv) .. " each", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
    end
    if CP:MakePlan(id) then
      local parts = {}
      for _, raw in ipairs(CP:RawMaterials(id)) do
        local rc = CP:DirectCost(raw.id)
        local cnt = raw.count * rg.count
        cnt = (cnt == math.floor(cnt)) and cnt or tonumber(string.format("%.1f", cnt))
        parts[#parts + 1] = cnt .. "x " .. CP.ItemName(raw.id) .. (rc and (" " .. CP.Money(rc * cnt)) or " (no price)")
      end
      local direct, made = CP:DirectCost(id), CP:MakeCost(id)
      local note = ""
      if made and direct then
        note = made < direct and "  |cff55ff55cheaper than the bar|r" or "  |cff888888bar is cheaper|r"
      end
      GameTooltip:AddLine("   or buy " .. table.concat(parts, ", ") .. note, 0.7, 0.7, 0.7, true)
    end
  end
  GameTooltip:AddLine(" ")
  local p = CP.db.prices[g.id]
  if not dup then GameTooltip:AddDoubleLine("AH lowest", CP.Money(p and p.min), 1, 1, 1, 1, 1, 1) end
  if not dup then GameTooltip:AddDoubleLine("Sells now (lowest listing, net of AH cut)", g.liveSell and CP.Money(math.floor(g.liveSell)) or "none", 1, 1, 1, 1, 1, 1) end
  GameTooltip:AddDoubleLine("AH reference (next-lowest price)", CP.Money(p and p.ref), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Listings / units", ((p and p.n) or 0) .. " / " .. ((p and p.qty) or 0), 1, 1, 1, 1, 1, 1)
  local st = CP.History.Stats(g.id)
  if st and st.median and not dup then
    GameTooltip:AddDoubleLine("Average = 14-day median (" .. st.samples .. " scans)", CP.Money(st.median), 1, 1, 1, 1, 1, 1)
  end
  if st and st.perDay and not dup then
    GameTooltip:AddDoubleLine("Est. sales/day", string.format("%.1f", st.perDay), 1, 1, 1, 1, 1, 1)
    if st.perDay >= 1000 then GameTooltip:AddLine("Counted in items, not listings: stacks that disappear between scans count as sold, so busy stackable goods (ammo, cloth) read very high.", 0.6, 0.6, 0.6, true) end
  end
  if Spiking(g) then
    GameTooltip:AddLine(("Today's lowest price (%s) is far above the average (%s): a spike. Profit uses the cautious price, \"Profit now\" assumes the spike holds."):format(CP.Money(math.floor(g.liveSell)), CP.Money(math.floor(g.avgSell))), 1, 0.5, 0.25, true)
  end
  GameTooltip:AddDoubleLine("Sell price used (lower of reference and 14-day median)", g.sell and CP.Money(g.sell) or "none", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Price data", CP.Age(p and p.time), 1, 1, 1, 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")
  local d = CP:BuyDepth(g)
  if d then
    GameTooltip:AddLine("How much to buy before it stops paying", 1, 0.82, 0)
    if d.crafts == 0 then
      GameTooltip:AddLine("Even the cheapest listings of the materials leave no profit.", 1, 0.5, 0.4, true)
    else
      GameTooltip:AddDoubleLine("Crafts worth making", d.crafts .. (d.crafts > 1 and (" (" .. d.crafts * (g.yield or 1) .. " items)") or ""), 1, 1, 1, 0.4, 1, 0.4)
      for _, sl in ipairs(d.mats) do
        GameTooltip:AddDoubleLine("   " .. CP.ItemName(sl.id), sl.units .. "  up to " .. CP.Money(sl.worst), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("Materials cost", CP.Money(math.floor(d.cost)), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine("Profit from all of it", CP.Money(math.floor(d.profit)), 1, 1, 1, 0.4, 1, 0.4)
    end
    if d.reason == "price" then
      GameTooltip:AddLine("Stops because the next one's materials cost more than it sells for.", 0.7, 0.7, 0.7, true)
    elseif d.reason == "gold" then
      GameTooltip:AddLine("Stops because you only have " .. CP.Money(GetMoney()) .. " on this character. Turn \"Limit by my gold\" off in options to see the profit limit instead.", 1, 0.82, 0.4, true)
    elseif d.reason == "supply" then
      GameTooltip:AddLine("Stops because the AH has no more " .. CP.ItemName(d.limiter) .. " listed.", 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine("Still profitable at the largest quantity checked.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("Based on the last scan, selling price held steady.", 0.5, 0.5, 0.5, true)
    GameTooltip:AddLine(" ")
  end
  GameTooltip:AddLine("Can craft", 1, 0.82, 0)
  if g.notLearned then
    GameTooltip:AddLine("No character has learned this recipe yet.", 0.6, 0.7, 0.9, true)
    local who, seenW = {}, {}
    for _, k in ipairs(g.learnable or {}) do
      local n = CP.ShortName(k)
      if not seenW[n] then seenW[n] = true who[#who + 1] = n end
    end
    if #who > 0 then GameTooltip:AddLine("Could learn it: " .. table.concat(who, ", "), 0.6, 0.7, 0.9, true) end
  end
  for _, charKey in ipairs(g.chars) do
    local inv = CP.db.inventory[charKey]
    local seen = inv and inv.time and ("  |cff888888(bags seen " .. CP.Age(inv.time) .. ")|r") or "  |cff888888(bags not seen yet)|r"
    GameTooltip:AddDoubleLine(CP.ShortName(charKey), "can make " .. (g.make[charKey] or 0) .. seen, 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: search the AH for the materials", 0.6, 0.8, 0.6)
  GameTooltip:AddLine("Shift-click: search for the finished item", 0.6, 0.8, 0.6)
  GameTooltip:AddLine("Right-click: " .. (g.tracked and "stop tracking" or "track (pin to top)"), 0.6, 0.8, 0.6)
  if g.prof and g.chars and #g.chars > 0 then
    GameTooltip:AddLine("Ctrl+right-click: remove " .. tostring(g.prof) .. " from a crafter (if they don't have it)", 0.6, 0.8, 0.6)
  end
  GameTooltip:Show()
end

------------------------------------------------------------------------
-- Remove a profession from a crafter (for characters that dropped it), one crafter at a time
------------------------------------------------------------------------
local function AskNext(prof, keys, n)
  local key = keys[n]
  if not key then return end
  StaticPopup_Show("PROFITEER_REMOVE_CRAFTER",
    ("Remove %s from %s?\nOnly do this if that character no longer has the profession."):format(prof, CP.ShortName(key)),
    nil, { key = key, prof = prof, keys = keys, n = n })
end
StaticPopupDialogs["PROFITEER_REMOVE_CRAFTER"] = {
  text = "%s",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(_, data)
    if not data then return end
    local d = CP.db
    for _, tbl in ipairs({ d.recipes, d.unlearned, d.rnames }) do
      local mine = tbl and tbl[data.key]
      if mine then mine[data.prof] = nil end
    end
    CP:Print(("Removed %s from %s."):format(data.prof, CP.ShortName(data.key)))
    CP:Refresh()
  end,
  OnCancel = function(_, data, reason)
    -- "No" moves on to the next crafter on the row; Escape / closing stops
    if data and reason == "clicked" then AskNext(data.prof, data.keys, data.n + 1) end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}
function UI.AskRemoveCrafter(g)
  if not (g and g.prof and g.chars and #g.chars > 0) then return end
  local keys = {}
  for _, k in ipairs(g.chars) do keys[#keys + 1] = k end
  AskNext(g.prof, keys, 1)
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function CreateRow(i)
  local row = CreateFrame("Button", nil, UI.frame)
  row:SetHeight(ROW_H)
  row:SetWidth(curTW)
  row:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", 22, -70 - (i - 1) * ROW_H)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.12)
  row.cols = {}
  for _, c in ipairs(COLS) do
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", row, "LEFT", colX[c.key], 0)
    fs:SetWidth(colW[c.key])
    fs:SetHeight(ROW_H)
    fs:SetJustifyH(c.align)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    row.cols[c.key] = fs
  end
  if CP.AH and CP.AH.AddDivider then CP.AH.AddDivider(row, i) end
  row:SetScript("OnEnter", ShowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    local g = self.data
    if not g then return end
    if button == "RightButton" and IsControlKeyDown() then
      UI.AskRemoveCrafter(g)
    elseif button == "RightButton" then
      CP.Shop.Track(g)
    elseif IsShiftKeyDown() then
      CP.Shop.ForOutput(g)
    else
      CP.Shop.ForCraft(g)
    end
  end)
  return row
end

-- "Buy up to": how many crafts' worth of materials you can buy before the next craft stops paying
local function DepthText(g)
  if g.depth == nil then
    local ok, d = pcall(CP.BuyDepth, CP, g)
    g.depth = ok and d or false
  end
  local d = g.depth
  if not d then return "|cff888888?|r" end
  if d.crafts == 0 then return "|cffff40400|r" end
  return ((d.reason == "supply" or d.reason == "gold") and "|cffffa040" or "|cff40ff40") .. d.crafts .. (d.reason == "cap" and "+" or "") .. "|r"
end

-- "Profit if bought": what buying up to that many crafts' worth would earn in total
local function DepthProfitText(g)
  local _ = DepthText(g)                    -- makes sure g.depth is worked out
  local d = g.depth
  if not d then return "|cff888888?|r" end
  if d.crafts == 0 then return "|cff888888-|r" end
  local color = (d.reason == "supply" or d.reason == "gold") and "|cffffa040" or "|cff40ff40"
  return color .. CP.Money(math.floor(d.profit)) .. "|r"
end

local function CraftersText(g)
  if g.notLearned then
    local who, seenW = {}, {}
    for _, k in ipairs(g.learnable or {}) do
      local n = CP.ShortName(k)
      if not seenW[n] then seenW[n] = true who[#who + 1] = n end
    end
    return "|cff8899aanot learned" .. (#who > 0 and (": " .. who[1] .. (#who > 1 and " +" .. (#who - 1) or "")) or "") .. "|r"
  end
  local names, seen = {}, {}
  for _, k in ipairs(g.chars) do
    local n = CP.ShortName(k)
    if not seen[n] then seen[n] = true names[#names + 1] = n end      -- one name once, even if the same character is saved twice
  end
  if #names <= 2 then return table.concat(names, ", ") end
  return names[1] .. ", " .. names[2] .. " +" .. (#names - 2)
end

function UI.VisibleRows() return ROWS end

local function MaxOffset()
  return math.max(0, #(UI.results or {}) - ROWS)
end

function UI.Update()
  if not UI.frame or not UI.frame:IsShown() then return end
  if UI.tab ~= "crafts" then return end
  if UI.headers then
    local s = CP.db.settings
    for _, h in ipairs(UI.headers) do
      if h.fs then
        local mark = (h.key and s.sortKey == h.key) and (s.sortDesc and " v" or " ^") or ""
        h.fs:SetText(h.label .. mark)
      end
    end
  end
  local res = UI.results or {}
  local maxOff = MaxOffset()
  if UI.offset > maxOff then UI.offset = maxOff end
  if UI.offset < 0 then UI.offset = 0 end
  if UI.slider then
    UI.slider:SetMinMaxValues(0, maxOff)
    UI.updatingSlider = true
    UI.slider:SetValue(UI.offset)
    UI.updatingSlider = false
  end

  for i = 1, MAXROWS do
    local row = rows[i]
    local g = i <= ROWS and res[i + UI.offset] or nil
    row.data = g
    if g and g.unpriced then
      row.cols.name:SetText((g.tracked and "|cffffd100*|r " or "") .. "|cff9d9d9d" .. g.name .. "|r")
      row.cols.prof:SetText("|cff9d9d9d" .. tostring(g.prof or "") .. "|r")
      row.cols.crafters:SetText(CraftersText(g))
      row.cols.avgcost:SetText(g.avgCost and CP.Money(g.avgCost) or "|cff888888?|r")
      row.cols.costnow:SetText(g.liveCost and CP.Money(g.liveCost) or "|cff888888?|r")
      row.cols.avgsell:SetText(g.avgSell and CP.Money(math.floor(g.avgSell)) or "|cff888888-|r")
      row.cols.sellnow:SetText(g.liveSell and CP.Money(math.floor(g.liveSell)) or "|cff888888-|r")
      row.cols.profit:SetText("|cff888888-|r")
      row.cols.profitnow:SetText("|cff888888-|r")
      row.cols.ratio:SetText("|cff888888-|r")
      row.cols.listed:SetText("|cff8888880|r")
      row.cols.perday:SetText("|cff888888?|r")
      row.cols.make:SetText(g.best > 0 and ("|cff40ff40" .. g.best .. "|r") or "|cff888888-|r")
      row.cols.depth:SetText("|cff888888-|r")
      row.cols.depthprofit:SetText("|cff888888-|r")
      row:Show()
    elseif g then
      local profitColor = g.profit > 0 and "|cff40ff40" or "|cffff4040"
      row.cols.name:SetText((g.tracked and "|cffffd100*|r " or "") .. g.name)
      row.cols.prof:SetText(tostring(g.prof or ""))
      row.cols.crafters:SetText(CraftersText(g))
      local ac, asell = g.avgCost or g.cost, g.avgSell or g.revenue
      row.cols.avgcost:SetText(CP.Money(ac))
      row.cols.costnow:SetText(g.liveCost and (CP.Money(g.liveCost) .. Tick(g.liveCost, ac, false)) or "|cff888888?|r")
      row.cols.avgsell:SetText(CP.Money(math.floor(asell)))
      row.cols.sellnow:SetText(g.liveSell and (CP.Money(math.floor(g.liveSell)) .. Tick(g.liveSell, asell, true) .. (Spiking(g) and " |cffff8040!|r" or "")) or "|cff888888-|r")
      row.cols.profit:SetText(CP.Money(g.profit))
      if g.liveProfit then
        row.cols.profitnow:SetText((Spiking(g) and "|cffffa040" or (g.liveProfit > 0 and "|cff40ff40" or "|cffff4040")) .. CP.Money(math.floor(g.liveProfit)) .. "|r")
      else
        row.cols.profitnow:SetText("|cff888888-|r")
      end
      row.cols.ratio:SetText(profitColor .. math.floor(g.ratio * 100 + 0.5) .. "%|r")
      row.cols.listed:SetText(g.listed < 10 and ("|cffffa040" .. g.listed .. "|r") or Compact(g.listed))
      row.cols.perday:SetText(g.perDay and (g.perDay >= 10000 and Compact(g.perDay) or string.format("%.1f", g.perDay)) or "|cff888888?|r")
      row.cols.make:SetText(g.best > 0 and ("|cff40ff40" .. g.best .. "|r") or "|cff888888-|r")
      row.cols.depth:SetText(DepthText(g))
      row.cols.depthprofit:SetText(DepthProfitText(g))
      row:Show()
    else
      row:Hide()
    end
  end
end

-- what the last Live prices run did, appended to the status line under the list (a redraw rewrites that line)
local function LiveNote()
  if CP.AHSource and CP.AHSource.IsCross and CP.AHSource.IsCross() then return "  |cffff8040Cross-faction auction house.|r" end
  local m = CP.AHSource and CP.AHSource.Mismatch and CP.AHSource.Mismatch()
  if m then return "  |cffff8040Scanned at the other faction's auction house.|r" end
  local l = CP.Live and CP.Live.last
  if not l then return "" end
  return ("  Live prices: %d of %d updated %s%s"):format(l.updated or 0, l.total or 0, CP.Age(l.time),
    (l.failed or 0) > 0 and (", " .. l.failed .. " got no answer") or "")
end

function UI.SetStatus(text)
  if UI.tab and UI.tab ~= "crafts" and UI.tab ~= "ledger" then text = "" end   -- the other tabs have their own status lines
  if UI.status then UI.status:SetText(text or "") end
end

-- Does a craft match the search text? Every word typed must appear (as part of a word) somewhere in the
-- item or recipe name, profession, materials or who can make it. Returns a rank: 3 = name starts with it,
-- 2 = a word in the name starts with it, 1 = found inside the name, 0 = found only elsewhere; nil = no match.
local function Matches(g, q)
  local names = CP.db and CP.db.names or {}
  local words = {}
  for w in q:gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return 1 end
  local function lower(x) return x and tostring(x):lower() end
  local mine = { lower(g.name), lower(g.rname) }
  local other = { lower(g.prof) }
  for _, r in ipairs(g.reagents or {}) do
    other[#other + 1] = lower(r.name)
    for _, id in ipairs(r.ids or { r.id }) do other[#other + 1] = lower(names[id]) end
  end
  for _, ck in ipairs(g.chars or {}) do other[#other + 1] = lower(CP.ShortName(ck)) end
  local rank = 3
  for _, w in ipairs(words) do
    local best
    for _, n in ipairs(mine) do
      local at = n and n:find(w, 1, true)
      if at then
        local r = (at == 1) and 3 or ((n:sub(at - 1, at - 1):match("%W")) and 2 or 1)
        if not best or r > best then best = r end
      end
    end
    if not best then
      for _, n in ipairs(other) do if n and n:find(w, 1, true) then best = 0 break end end
    end
    if not best then return nil end
    if best < rank then rank = best end
  end
  return rank
end

function UI.ApplyFilter()
  local all = UI.allResults or {}
  local q = (UI.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then
    UI.results = all
  else
    local ranked = {}
    for i, g in ipairs(all) do
      local r = Matches(g, q)
      if r then ranked[#ranked + 1] = { g = g, r = r, i = i } end
    end
    -- best name matches first; otherwise keep the usual profit order
    table.sort(ranked, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.i < b.i end)
    local out = {}
    for _, e in ipairs(ranked) do out[#out + 1] = e.g end
    UI.results = out
  end
end

function UI.Rebuild()
  if not CP.db then return end
  local results, skipped, total = CP:BuildResults()
  UI.nPriced = #results
  local all = {}
  for _, g in ipairs(results) do all[#all + 1] = g end
  for _, g in ipairs(CP.unpriced or {}) do all[#all + 1] = g end
  UI.allResults = all
  UI.ApplyFilter()
  if UI.frame and UI.frame:IsShown() then
    UI.Update()
    if not CP.Scanner:IsRunning() then
      local q = (UI.query or ""):gsub("%s", "")
      if q ~= "" then
        UI.SetStatus(("%d of %d crafts match \"%s\". Last scan: %s"):format(#UI.results, #all, UI.query, CP.Age(CP.db.lastScan)) .. LiveNote())
      else
        UI.SetStatus(("%d priced, %d more with no AH price (grey, at the bottom) of %d crafts. Last scan: %s")
          :format(UI.nPriced or 0, #all - (UI.nPriced or 0), total, CP.Age(CP.db.lastScan)) .. LiveNote())
      end
    end
  end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local function HeaderClick(self)
  local s = CP.db.settings
  local key = self.key
  if s.sortKey == key then
    s.sortDesc = not s.sortDesc
  else
    s.sortKey = key
    s.sortDesc = (key ~= "name")
  end
  UI.Rebuild()
end

function UI.Create()
  if UI.frame then return end

  local f = CreateFrame("Frame", "ProfiteerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  UI.frame = f
  if CP.WinLook then CP.WinLook.Attach("main", f) end
  f.docked = false
  f:SetSize(TOTAL_W + 62, BASE_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)   -- clicking raises the window with all its contents above other addon windows
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  -- solid dark panel so world text (nameplates, guild tags) can't show through the rows
  local bgTex = f:CreateTexture(nil, "BACKGROUND")
  bgTex:SetDrawLayer("BACKGROUND", 1)
  bgTex:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
  bgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  bgTex:SetColorTexture(0.04, 0.04, 0.06, 0.96)
  f.bgTex = bgTex
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- remember where the user put it (offset from screen's bottom-left)
    local l, b = self:GetLeft(), self:GetBottom()
    if type(l) == "number" and type(b) == "number" and CP.db then
      CP.db.settings.winX, CP.db.settings.winY = l, b
    end
  end)
  f:SetScript("OnShow", UI.Rebuild)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    UI.offset = math.max(0, math.min(MaxOffset(), UI.offset - delta * 3))
    UI.Update()
    if CP.AH then CP.AH.Rehover(rows) end
  end)
  f:Hide()
  table.insert(UISpecialFrames, "ProfiteerFrame")

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -52, -18)
  title:SetText("Profiteer" .. (CP.mode and ("  |cffffd060" .. CP.mode .. "|r") or ""))
  f.titleFS = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  f.closeBtn = close


  -- Main window navigation tabs.
  local tabs = {}
  local function MakeTab(key, label, x)
    local t = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    t:SetSize(84, 24)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -14)
    t:SetText(label)
    t:SetScript("OnClick", function() UI.SetTab(key) end)
    tabs[key] = t
  end
  MakeTab("crafts", "Crafts", 24)
  MakeTab("plan", "Plan", 110)
  MakeTab("shopping", "Shopping", 196)
  MakeTab("cancelling", "Cancelling", 282)
  MakeTab("ledger", "Ledger", 368)
  UI.tabs = tabs
  -- on its own (minimap button) the window shows only Crafts, Shopping and the Ledger; Plan and Cancelling live in the auction house
  function UI.LayoutTabs()
    local x = 24
    for _, key in ipairs({ "crafts", "shopping", "ledger" }) do
      local t = tabs[key]
      t:ClearAllPoints() t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -14) t:Show()
      x = x + 86
    end
    tabs.plan:Hide() tabs.cancelling:Hide()
  end
  UI.LayoutTabs()

  -- Search box (Crafts tab): part of a craft, material, profession or character name
  local search = CreateFrame("EditBox", "ProfiteerSearch", f, "InputBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -150, 16)   -- left of the Live prices button
  search:SetAutoFocus(false)
  search:SetMaxLetters(40)
  local hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("Search crafts, materials...")
  local function Changed()
    UI.query = search:GetText() or ""
    hint:SetShown(UI.query == "" and not search:HasFocus())
    UI.offset = 0
    UI.ApplyFilter()
    UI.Update()
    local q = UI.query:gsub("%s", "")
    if q ~= "" then
      UI.SetStatus(("%d of %d crafts match \"%s\""):format(#(UI.results or {}), #(UI.allResults or {}), UI.query))
    elseif UI.nPriced then
      UI.SetStatus(("%d priced, %d more with no AH price (grey, at the bottom)"):format(UI.nPriced, #(UI.allResults or {}) - UI.nPriced))
    end
  end
  search:SetScript("OnTextChanged", function(self, user) if user then Changed() end end)
  search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() Changed() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end)
  search:SetScript("OnEditFocusLost", function() hint:SetShown((search:GetText() or "") == "") end)
  UI.search = search

  -- Column headers
  local headers = {}
  for _, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, f)
    h.colKey = c.key
    h:SetSize(colW[c.key], 18)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + colX[c.key], -48)
    headers[#headers + 1] = h
    local fs = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH(c.align)
    fs:SetText(c.label)
    h.fs, h.label = fs, c.label
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    if c.sortable then
      h.key = c.key
      h:SetScript("OnClick", HeaderClick)
      h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click to sort by " .. (self.label or ""), 1, 1, 1)
        GameTooltip:AddLine("Click again to reverse the order.", 0.8, 0.8, 0.8)
        if COLHELP[self.key] then GameTooltip:AddLine(" ") GameTooltip:AddLine(COLHELP[self.key], 0.7, 0.85, 1, true) end
        GameTooltip:Show()
      end)
      h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end

  UI.headers = headers
  -- Rows
  for i = 1, MAXROWS do rows[i] = CreateRow(i) end

  -- Scrollbar (plain slider, no template needed)
  local slider = CreateFrame("Slider", nil, f)
  slider:SetOrientation("VERTICAL")
  slider:SetSize(16, ROWS * ROW_H)
  slider:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + curTW + 6, -70)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  local bg = slider:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local thumb = slider:GetThumbTexture()
  if thumb then thumb:SetSize(16, 24) end
  slider:SetScript("OnValueChanged", function(_, value)
    if UI.updatingSlider then return end
    UI.offset = math.floor(value + 0.5)
    UI.Update()
  end)
  UI.slider = slider

  -- Bottom controls
  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(110, 24)
  scan:SetPoint("BOTTOMLEFT", 22, 44)
  scan:SetText("Scan AH")
  scan:SetScript("OnClick", function() CP.Scanner:Start() end)

  local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(90, 24)
  refresh:SetPoint("LEFT", scan, "RIGHT", 6, 0)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", UI.Rebuild)

  local live = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  live:SetSize(100, 24)
  live:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 12)
  live:SetText("Live prices")
  live:SetScript("OnClick", function() CP.Live.Start(CP.Live.VisibleIds()) end)
  live:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Live prices", 1, 0.82, 0)
    GameTooltip:AddLine("Needs the auction house open. Looks up each item on this page (the crafts shown and their materials) one by one for the exact price right now. Much quicker than a full scan. Click again to stop.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  live:SetScript("OnLeave", function() GameTooltip:Hide() end)
  CP.Live.button = live

  local cb = CreateFrame("CheckButton", "ProfiteerOnlyCraftable", f, "UICheckButtonTemplate")
  cb:SetPoint("LEFT", refresh, "RIGHT", 16, 0)
  local cbText = _G["ProfiteerOnlyCraftableText"] or cb.Text
  if cbText then pcall(function() cbText:SetText("Craftable now only") end) end
  cb:SetScript("OnClick", function(self)
    CP.db.settings.craftableOnly = self:GetChecked() and true or false
    UI.Rebuild()
  end)
  UI.onlyCraftable = cb

  local cb2 = CreateFrame("CheckButton", "ProfiteerShowLosses", f, "UICheckButtonTemplate")
  cb2:SetPoint("LEFT", cb, "RIGHT", 128, 0)
  local cb2Text = _G["ProfiteerShowLossesText"] or cb2.Text
  if cb2Text then pcall(function() cb2Text:SetText("Hide money-losing") end) end
  cb2:SetScript("OnClick", function(self)
    CP.db.settings.hideLosses = self:GetChecked() and true or false
    UI.Rebuild()
  end)
  UI.hideLosses = cb2

  local cb3 = CreateFrame("CheckButton", "ProfiteerShowLearned", f, "UICheckButtonTemplate")
  cb3:SetPoint("LEFT", cb2, "RIGHT", 128, 0)
  local cb3Text = _G["ProfiteerShowLearnedText"] or cb3.Text
  if cb3Text then pcall(function() cb3Text:SetText("Learned recipes only") end) end
  cb3:SetScript("OnClick", function(self)
    CP.db.settings.learnedOnly = self:GetChecked() and true or false
    UI.Rebuild()
  end)
  cb3:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Learned recipes only", 1, 0.82, 0)
    GameTooltip:AddLine("Ticked: only crafts one of your characters has learned.\nUnticked: also shows recipes nobody has learned yet, to see what is worth buying or training.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cb3:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.showLearned = cb3

  local shopTop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  shopTop:SetSize(110, 24)
  shopTop:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 44)
  shopTop:SetText("Shop top 10")
  shopTop:SetScript("OnClick", function() CP.Shop.Command("") end)

  local shopTracked = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  shopTracked:SetSize(110, 24)
  shopTracked:SetPoint("RIGHT", shopTop, "LEFT", -6, 0)
  shopTracked:SetText("Shop tracked")
  shopTracked:SetScript("OnClick", function() CP.Shop.Command("tracked") end)

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 26, 17)
  status:SetWidth(math.max(200, curTW - 380))
  UI.statusFS = status
  status:SetJustifyH("LEFT")
  UI.status = status

  -- everything that belongs to the Crafts tab, so the Ledger tab can hide it
  UI.craftWidgets = { slider, scan, refresh, live, cb, cb2, cb3, shopTop, shopTracked, search }
  for _, h in ipairs(headers) do UI.craftWidgets[#UI.craftWidgets + 1] = h end
  CP.Ledger.BuildPanel(f, PaneW(), BASE_H - 48 - 52)
  UI.panes = {}
  for key, mod in pairs({ plan = CP.AHPlan, shopping = CP.AHShopping, cancelling = CP.AHCancel }) do
    if mod and mod.Build then
      local ok, p = pcall(mod.Build, f, PaneW(), BASE_H - 52 - 12)
      if ok and p then p:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -52) UI.panes[key] = p else CP.RecordError("build " .. key, p) end
    end
  end
  UI.SetTab(UI.tab or "crafts")
end

-- Make the window taller or shorter and let every tab use the room (called by the auction house tab).
function UI.SetHeight(fh)
  local f = UI.frame
  if not f then return end
  fh = math.max(360, math.floor(fh or BASE_H))
  if UI.curH == fh then return end
  UI.curH = fh
  f:SetHeight(fh)
  ROWS = math.max(6, math.min(MAXROWS, math.floor((fh - 70 - 80) / ROW_H)))
  if UI.slider then UI.slider:SetHeight(ROWS * ROW_H) end
  if CP.Ledger.panel and CP.Ledger.resize then CP.Ledger.resize(fh - 48 - 52, PaneW()) end
  for key, mod in pairs({ plan = CP.AHPlan, shopping = CP.AHShopping, cancelling = CP.AHCancel }) do
    if mod and mod.Resize and UI.panes and UI.panes[key] then pcall(mod.Resize, PaneW(), fh - 52 - 12) end
  end
  if UI.tab == "crafts" then UI.Update() end
end

-- Make the window wider or narrower than the table's own width: the columns, scrollbar and panes follow
-- (called by the auction house tab, which shows the content smaller than the window it lives in).
function UI.SetWidth(w)
  local f = UI.frame
  if not f then return end
  w = math.max(UI.baseW, math.floor(w or UI.baseW))
  if UI.curW == w then return end
  UI.curW = w
  f:SetWidth(w)
  LayoutCols(w - UI.baseW)
  for _, r in ipairs(rows) do
    r:SetWidth(curTW)
    for _, c in ipairs(COLS) do
      local fs = r.cols[c.key]
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", r, "LEFT", colX[c.key], 0)
      fs:SetWidth(colW[c.key])
    end
  end
  for _, h in ipairs(UI.headers or {}) do
    local k = h.colKey
    if k then
      h:SetWidth(colW[k])
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + colX[k], -48)
    end
  end
  if UI.slider then UI.slider:ClearAllPoints() UI.slider:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + curTW + 6, -70) end
  if UI.statusFS then UI.statusFS:SetWidth(math.max(200, curTW - 380)) end
  local ph = (UI.curH or BASE_H)
  if CP.Ledger.panel and CP.Ledger.resize then CP.Ledger.resize(ph - 48 - 52, PaneW()) end
  for key, mod in pairs({ plan = CP.AHPlan, shopping = CP.AHShopping, cancelling = CP.AHCancel }) do
    if mod and mod.Resize and UI.panes and UI.panes[key] then pcall(mod.Resize, PaneW(), ph - 52 - 12) end
  end
end

-- Switch between Crafts, Shopping, Cancelling and the Ledger.
function UI.SetTab(key)
  if not UI.frame then return end
  if not (UI.tabs and UI.tabs[key]) then key = "crafts" end
  if (key == "plan" or key == "cancelling") and not (CP.AHTab and CP.AHTab.IsEmbedded and CP.AHTab.IsEmbedded()) then key = "crafts" end
  UI.tab = key
  local crafts = key == "crafts"
  for _, w in ipairs(UI.craftWidgets or {}) do w:SetShown(crafts) end
  for i = 1, #rows do if not crafts then rows[i]:Hide() end end
  if CP.Ledger.panel then CP.Ledger.panel:SetShown(key == "ledger") end
  for k, p in pairs(UI.panes or {}) do p:SetShown(k == key) end
  for k, t in pairs(UI.tabs or {}) do t:SetEnabled(k ~= key) end
  if crafts then
    UI.Update()
    if UI.nPriced then UI.Rebuild() end
  elseif key == "ledger" then
    UI.SetStatus("Gold in and out for all your characters, counted from the day the ledger was installed.")
  else
    UI.SetStatus("")
  end
end

function UI.Toggle()
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() and CP.AHTab and CP.AHTab.IsReady and CP.AHTab.IsReady() then
    if UI.frame and UI.frame:IsShown() then CP.AHTab.Leave() else CP.AHTab.Select() end
    return
  end
  UI.Create()
  if UI.frame:IsShown() then
    UI.frame:Hide()
  else
    UI.onlyCraftable:SetChecked(CP.db.settings.craftableOnly)
    UI.hideLosses:SetChecked(CP.db.settings.hideLosses)
    UI.showLearned:SetChecked(CP.db.settings.learnedOnly ~= false)
    UI.frame:Show()
  end
end

------------------------------------------------------------------------
-- Auction House integration
------------------------------------------------------------------------
-- A "Profiteer" button on the AH window opens the ranking right over the AH,
-- like a tab. Close it (X or the button again) to get the AH back. Drag the
-- button to reposition it. /pf ahopen on = open automatically with the AH.

local function Num(v, default) if type(v) == "number" then return v end return default end

local function Dock()
  -- Open BESIDE the AH (never over it) unless the user has moved the window.
  local ah = AuctionHouseFrame
  local f = UI.frame
  if not f then return false end
  local st = CP.db and CP.db.settings or {}
  f:ClearAllPoints()
  if type(st.winX) == "number" and type(st.winY) == "number" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", st.winX, st.winY)
  elseif ah then
    f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
  else
    f:SetPoint("CENTER")
  end
  f:SetFrameStrata("HIGH")
  f.docked = true
  return true
end

local function Undock()
  local f = UI.frame
  if not f then return end
  f.docked = false
  f:ClearAllPoints()
  f:SetPoint("CENTER")
end

function UI.ResetWindow()
  if CP.db then CP.db.settings.winX, CP.db.settings.winY = nil, nil end
  if UI.frame and UI.frame:IsShown() then Dock() end
end

function UI.ShowDocked()
  UI.Create()
  if UI.frame:IsShown() then UI.frame:Hide() end
  if not Dock() then Undock() end
  UI.onlyCraftable:SetChecked(CP.db.settings.craftableOnly)
  UI.hideLosses:SetChecked(CP.db.settings.hideLosses)
  UI.showLearned:SetChecked(CP.db.settings.learnedOnly ~= false)
  UI.frame:Show()
end

local function PlaceAHButton()
  local s = CP.db.settings
  local b = UI.ahButton
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", s.ahBtnX or -44, s.ahBtnY or -3)
end

local function CreateAHButton()
  if UI.ahButton or not AuctionHouseFrame then return end
  local b = CreateFrame("Button", "ProfiteerAHButton", AuctionHouseFrame, "UIPanelButtonTemplate")
  b:SetSize(96, 22)
  b:SetText("Profiteer")
  b:SetFrameLevel(Num(AuctionHouseFrame:GetFrameLevel(), 0) + 20)
  b:RegisterForDrag("LeftButton", "RightButton")
  b:SetFrameStrata("DIALOG")
  b:SetScript("OnClick", function()
    if CP.AHTab and CP.AHTab.Select then CP.AHTab.Select() return end
    if UI.frame and UI.frame:IsShown() and UI.frame.docked then
      UI.frame:Hide()
    else
      UI.ShowDocked()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    local cx, cy = GetCursorPosition()
    local sc = self:GetEffectiveScale()
    local r, t = self:GetRight(), self:GetTop()
    if type(cx) ~= "number" or type(r) ~= "number" or type(sc) ~= "number" or sc == 0 then return end
    self.dragDX, self.dragDY = r - cx / sc, t - cy / sc
    self:SetScript("OnUpdate", function(me)
      local ah = AuctionHouseFrame
      local x, y = GetCursorPosition()
      local s2 = me:GetEffectiveScale()
      local ar, at = ah:GetRight(), ah:GetTop()
      if type(ar) ~= "number" or type(at) ~= "number" then return end
      -- offset of button's top-right from the AH's top-right, following the cursor
      CP.db.settings.ahBtnX = (x / s2 + me.dragDX) - ar
      CP.db.settings.ahBtnY = (y / s2 + me.dragDY) - at
      PlaceAHButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Profiteer", 1, 0.82, 0)
    GameTooltip:AddLine("Craft profits and price info. Drag to move this button; drag the Profiteer window by its frame.", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.ahButton = b
  PlaceAHButton()
end

function UI.ResetAHButton()
  CP.db.settings.ahBtnX, CP.db.settings.ahBtnY = nil, nil
  if UI.ahButton then PlaceAHButton() end
end

local ahFrame = CreateFrame("Frame")
CP.Register(ahFrame, "AUCTION_HOUSE_SHOW")
CP.Register(ahFrame, "AUCTION_HOUSE_CLOSED")
ahFrame:SetScript("OnEvent", CP.Safe("ah-integration", function(_, event)
  if not CP.db then return end
  if event == "AUCTION_HOUSE_SHOW" then
    CreateAHButton()
    if CP.db.settings.ahAutoOpen then
      -- with the Profiteer tab in the AH, "open with the AH" selects that tab; the floating window is only a fallback
      CP.After(0.6, function()
        if CP.AHTab and CP.AHTab.IsReady and CP.AHTab.IsReady() then if not CP.AHTab.Current() and not CP.AHTab.started then CP.AHTab.Start() end else UI.ShowDocked() end
      end)
    end
  elseif UI.frame and UI.frame.docked then
    UI.frame:Hide()
    Undock()
  end
end))
