local ADDON, CP = ...

-- Adds AH price info to item tooltips for every item Profiteer has scanned.

local function AddInfo(tip, id)
  if not CP.db or not CP.db.settings.tooltips or not id then return end
  local p = CP.db.prices[id]
  local vendor = CP.db.vendor[id]
  local seen = CP.db.lastSeen and CP.db.lastSeen[id]
  if not p and not vendor and not seen then return end

  tip:AddLine("Profiteer", 0.2, 1, 0.6)

  if p then
    if p.min then
      local listed = (p.n and p.n > 0) and (" |cff888888(" .. p.n .. " listed)|r") or ""
      tip:AddDoubleLine("AH lowest", CP.Money(p.min) .. listed, 1, 1, 1, 1, 1, 1)
    else
      tip:AddDoubleLine("AH lowest", "|cff888888none listed|r", 1, 1, 1, 1, 1, 1)
    end

    local st = CP.History.Stats(id)
    if st and st.median and st.samples >= 2 then
      local trend = ""
      if p.ref and st.median > 0 then
        local pct = math.floor((p.ref - st.median) / st.median * 100 + 0.5)
        if pct > 0 then trend = "  |cff40ff40+" .. pct .. "%|r"
        elseif pct < 0 then trend = "  |cffff4040" .. pct .. "%|r" end
      end
      tip:AddDoubleLine("Market (" .. st.samples .. " scans)", CP.Money(st.median) .. trend, 1, 1, 1, 1, 1, 1)
    end
    if st and st.perDay then
      tip:AddDoubleLine("Est. sales/day", string.format("%.1f", st.perDay), 1, 1, 1, 1, 1, 1)
    end
    tip:AddDoubleLine("Scanned", CP.Age(p.time), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
  end

  -- not listed at the last scan: show the last price it was seen at
  if seen and not (p and p.min) then
    tip:AddDoubleLine("Last seen on AH", CP.Money(seen[1]) .. "  |cff888888" .. CP.Age(seen[3]) .. "|r", 1, 1, 1, 1, 1, 1)
  end

  if vendor then
    tip:AddDoubleLine("Vendor buy price", CP.Money(vendor), 1, 1, 1, 1, 1, 1)
  end

  -- an item a vendor would pay more for than the auction house would (after the AH cut): sell it to the vendor
  if p and p.min and GetItemInfo and CP.db.settings.vendorWarn ~= false then
    local sell = select(11, GetItemInfo(id))
    local cut = tonumber(CP.db.settings.ahCut) or 0.05
    local net = p.min * (1 - cut)
    if type(sell) == "number" and sell > 0 and sell > net then
      tip:AddDoubleLine("|cffff8040Vendor pays more than the AH|r", CP.Money(sell) .. " vs " .. CP.Money(math.floor(net + 0.5)), 1, 1, 1, 1, 1, 1)
    end
  end
end

-- Which of your characters hold this item (bags and bank, from each one's last inventory scan)
local function AddOwned(tip, id)
  if not CP.db or not CP.db.settings.tooltips or not id or not CP.db.inventory then return end
  local rows, total = {}, 0
  for key, inv in pairs(CP.db.inventory) do
    local b, k = (inv.bags and inv.bags[id]) or 0, (inv.bank and inv.bank[id]) or 0
    if b + k > 0 then
      local parts = {}
      if b > 0 then parts[#parts + 1] = b .. " in bags" end
      if k > 0 then parts[#parts + 1] = k .. " in bank" end
      rows[#rows + 1] = { name = tostring(CP.ShortName and CP.ShortName(key) or key), n = b + k, txt = table.concat(parts, ", "), me = key == CP.charKey }
      total = total + b + k
    end
  end
  if #rows == 0 then return end
  table.sort(rows, function(a, c) if a.n ~= c.n then return a.n > c.n end return a.name < c.name end)
  tip:AddDoubleLine("Your characters hold", tostring(total), 0.2, 1, 0.6, 1, 1, 1)
  for _, r in ipairs(rows) do
    tip:AddDoubleLine("  " .. r.name .. (r.me and " (this one)" or ""), r.txt, 0.8, 0.8, 0.8, 1, 1, 1)
  end
end

-- Tooltip code must never throw (it would break every item tooltip), and
-- must tolerate values the client declines to reveal.
local function Safe(tip, id)
  if issecretvalue and issecretvalue(id) then return end
  local ok, err = pcall(AddInfo, tip, id)
  if not ok then CP.RecordError("tooltip", err) end
  local okO, errO = pcall(AddOwned, tip, id)
  if not okO then CP.RecordError("owned tooltip", errO) end
  if CP.Disenchant and CP.db and CP.db.settings and CP.db.settings.tooltips then
    local ok3, err3 = pcall(CP.Disenchant.Tip, tip, id)
    if not ok3 then CP.RecordError("disenchant tooltip", err3) end
  end
  if CP.Opens then
    local ok5, err5 = pcall(CP.Opens.Tip, tip, id)
    if not ok5 then CP.RecordError("opens tooltip", err5) end
  end
  if CP.CraftTip then
    local ok4, err4 = pcall(CP.CraftTip.Tip, tip, id)
    if not ok4 then CP.RecordError("craft tooltip", err4) end
  end
  if CP.Learned then
    local ok2, err2 = pcall(CP.Learned.Tip, tip, id)
    if not ok2 then CP.RecordError("recipe tooltip", err2) end
  end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
   and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
    if data and data.id then Safe(tip, data.id) end
  end)
else
  local function Hook(tip)
    if not tip or not tip.HookScript then return end
    tip:HookScript("OnTooltipSetItem", function(self)
      if self.__profiteerAdded then return end
      local _, link = self:GetItem()
      local id = CP.ItemID(link)
      if id then
        self.__profiteerAdded = true
        Safe(self, id)
      end
    end)
    tip:HookScript("OnTooltipCleared", function(self) self.__profiteerAdded = nil end)
  end
  Hook(GameTooltip)
  Hook(ItemRefTooltip)
  Hook(ShoppingTooltip1)
  Hook(ShoppingTooltip2)
end
