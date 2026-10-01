local ADDON, CP = ...

-- Adds AH price info to item tooltips for every item Profiteer has scanned.

local function AddInfo(tip, id)
  if not CP.db or not CP.db.settings.tooltips or not id then return end
  local p = CP.db.prices[id]
  local vendor = CP.db.vendor[id]
  if not p and not vendor then return end

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

  if vendor then
    tip:AddDoubleLine("Vendor buy price", CP.Money(vendor), 1, 1, 1, 1, 1, 1)
  end
end

-- Tooltip code must never throw (it would break every item tooltip), and
-- must tolerate values the client declines to reveal.
local function Safe(tip, id)
  if issecretvalue and issecretvalue(id) then return end
  local ok, err = pcall(AddInfo, tip, id)
  if not ok then CP.RecordError("tooltip", err) end
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
