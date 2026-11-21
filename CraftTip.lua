local ADDON, CP = ...

-- Tooltip for an item you can craft: what it is made from, what each material costs (vendor or
-- auction house, whichever is how you would buy it), and what the finished item sells for at the
-- auction house and to a vendor. Uses the recipes Profiteer captured from your professions.
local T = {}
CP.CraftTip = T

local index, indexAt = nil, 0

-- output item id -> recipe (a recipe a character knows wins over one it could still learn)
local function Index()
  if index and GetTime() - indexAt < 20 then return index end
  index, indexAt = {}, GetTime()
  local d = CP.db
  if not d then return index end
  local function add(tbl, known)
    for _, profs in pairs(tbl or {}) do
      for prof, list in pairs(profs) do
        for _, r in ipairs(list) do
          if r.id and not (index[r.id] and index[r.id].known and not known) then
            index[r.id] = { r = r, prof = prof, known = known }
          end
        end
      end
    end
  end
  add(d.unlearned, false)
  add(d.recipes, true)
  return index
end

local function Src(id)
  local c, src = CP:ReagentCost(id)
  return c, src
end

function T.Tip(tip, id)
  local d = CP.db
  if not d or d.settings.tooltips == false or d.settings.craftTips == false or not id then return end
  local e = Index()[id]
  if not e then return end
  local r = e.r
  local cut = tonumber(d.settings.ahCut) or 0.05

  tip:AddLine(" ")
  tip:AddLine(("Crafted with %s%s"):format(e.prof, r.yield and r.yield ~= 1 and (" (makes " .. r.yield .. ")") or ""), 0.2, 1, 0.6)

  local total, complete = 0, true
  for _, rg in ipairs(r.reagents) do
    local unit, src, rid = CP:SlotCost(rg)
    local name = CP.ItemName(rid or rg.id)
    local left = ("  %dx %s"):format(rg.count, name)
    if unit then
      local how = (src == "vendor" and "vendor") or (src == "made" and "made from raw") or "AH"
      tip:AddDoubleLine(left, ("%s each |cff888888(%s)|r  =  %s"):format(CP.Money(unit), how, CP.Money(unit * rg.count)), 1, 1, 1, 1, 1, 1)
      total = total + unit * rg.count
    else
      tip:AddDoubleLine(left, "|cff888888no price|r", 1, 1, 1, 1, 1, 1)
      complete = false
    end
  end
  if complete then
    local per = total / (r.yield or 1)
    tip:AddDoubleLine("Materials" .. ((r.yield or 1) ~= 1 and " (each)" or ""), CP.Money(per), 1, 0.82, 0, 1, 1, 1)
  else
    tip:AddDoubleLine("Materials", "|cff888888some have no price|r", 1, 0.82, 0, 1, 1, 1)
  end

  local p = d.prices[id]
  if p and p.min then
    tip:AddDoubleLine("Sells at the AH", CP.Money(p.min) .. "  |cff888888(" .. CP.Money(math.floor(p.min * (1 - cut) + 0.5)) .. " after the cut)|r", 1, 1, 1, 1, 1, 1)
  else
    tip:AddDoubleLine("Sells at the AH", "|cff888888none listed|r", 1, 1, 1, 1, 1, 1)
  end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local sell = fn and select(11, fn(id))
  if type(sell) == "number" and sell > 0 then
    tip:AddDoubleLine("Sells to a vendor", CP.Money(sell), 1, 1, 1, 1, 1, 1)
  end
  if d.vendor[id] then
    tip:AddDoubleLine("Vendor sells it for", CP.Money(d.vendor[id]), 1, 1, 1, 1, 1, 1)
  end
  if complete and p and p.min then
    local gain = p.min * (1 - cut) * (r.yield or 1) - total
    tip:AddDoubleLine("Profit per craft at the AH", CP.Money(gain), 1, 1, 1, 1, 1, 1)
  end
end
