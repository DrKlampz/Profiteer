local ADDON, CP = ...
-- Plan tab: pick a craft (click it in the Crafts tab), type how many you want to make, and it works out
-- what to buy (in stacks), what to smelt or craft along the way, and what it costs against your gold.
local H = CP.AH
local P = {}
CP.AHPlan = P

local pane, W = nil, {}
local cur, want = nil, 1

local function Name(id) return CP.ItemName and CP.ItemName(id) or ("item " .. tostring(id)) end
local function StackSize(id)
  local n = GetItemInfo and select(8, GetItemInfo(id))
  return (type(n) == "number" and n > 0) and n or nil
end
local function Stacks(id, qty)
  local ss = StackSize(id)
  if not ss or ss <= 1 then return "" end
  local full, rest = math.floor(qty / ss), qty % ss
  if full == 0 then return "" end
  return ("  |cff888888(%d stack%s of %d%s)|r"):format(full, full == 1 and "" or "s", ss, rest > 0 and (" + " .. rest) or "")
end

local function Render()
  if not (W.out and W.title) then return end
  local g = cur
  if not g then
    W.title:SetText("Plan")
    W.out:SetText("Click a craft in the Crafts tab and it shows up here.\n\nThen type how many you want to make and this works out what to buy (in stacks), what to smelt or craft along the way, and what it all costs.")
    return
  end
  local S = CP.AHShopping
  local yield = g.yield or 1
  local crafts = math.max(1, math.ceil(want / yield))
  W.title:SetText(g.name)
  local ok, plan = pcall(S.MakePlanFor, g, crafts)
  if not ok or type(plan) ~= "table" then W.out:SetText("Couldn't work out a plan for this one.") P.plan = nil return end
  P.plan = plan
  local L = {}
  L[#L + 1] = ("You want |cffffffff%d|r %s%s"):format(want, g.name, yield > 1 and ("  |cff888888(%d crafts, each makes %d)|r"):format(crafts, yield) or "")
  L[#L + 1] = ""
  local buys = {}
  for id, qty in pairs(plan.buys) do buys[#buys + 1] = { id = id, qty = qty } end
  table.sort(buys, function(a, b) return a.qty > b.qty end)
  local n = 0
  if #buys > 0 then
    n = n + 1
    L[#L + 1] = ("|cffffd100%d. Buy at the auction house|r"):format(n)
    for _, b in ipairs(buys) do L[#L + 1] = ("      |cffffffff%d|r %s%s"):format(b.qty, Name(b.id), Stacks(b.id, b.qty)) end
  else
    L[#L + 1] = "Nothing to buy: you already have everything."
  end
  for _, id in ipairs(plan.order) do
    local mp = CP:MakePlan(id)
    local from = {}
    for _, i in ipairs(mp and mp.inputs or {}) do from[#from + 1] = Name(i.id) end
    n = n + 1
    L[#L + 1] = ("|cffffd100%d. Make|r |cffffffff%d|r %s  |cff888888from %s|r"):format(n, plan.makes[id], Name(id), table.concat(from, " and "))
    local on = GetItemCount and GetItemCount(id, true) or 0
    if on > 0 then L[#L + 1] = ("      |cff888888your %d on hand are used first|r"):format(on) end
  end
  n = n + 1
  L[#L + 1] = ("|cffffd100%d. Make|r |cffffffff%d|r %s"):format(n, crafts, g.name)
  L[#L + 1] = ""
  local gold = GetMoney and GetMoney() or 0
  local total = math.floor(plan.total or 0)
  local col = total <= gold and "|cff40ff40" or "|cffff6040"
  L[#L + 1] = ("Cost to buy: %s%s|r   You have: %s"):format(col, H.Money(total), H.Money(gold))
  if total > gold then L[#L + 1] = "|cffff6040That is more than you have. Lower the number.|r" end
  W.out:SetText(table.concat(L, "\n"))
end

-- the most you can make with the gold you have, by the cheapest plan (everything you hold is used first)
function P.MaxAffordable(g)
  local S, gold = CP.AHShopping, GetMoney and GetMoney() or 0
  local yield = g.yield or 1
  local okd, d = pcall(CP.BuyDepth, CP, g)
  local cap = (okd and d and d.crafts and d.crafts > 0) and d.crafts * 10 or 500
  cap = math.min(math.max(cap, 200), 5000)
  local function cost(c)
    local ok, plan = pcall(S.MakePlanFor, g, c)
    return ok and type(plan) == "table" and plan.total or nil
  end
  local lo, hi = 0, cap
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    local c = cost(mid)
    if c and c <= gold then lo = mid else hi = mid - 1 end
  end
  return math.max(1, lo) * yield
end

function P.Open(g, n)
  cur = g
  if not n then
    local ok, m = pcall(P.MaxAffordable, g)
    n = ok and m or 1
  end
  want = n or want or 1
  if want < 1 then want = 1 end
  if W.qty then W.qty:SetText(tostring(want)) end
  Render()
  return true
end

function P.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  P.pane = pane
  W.title = H.Text(pane, "GameFontNormalLarge") W.title:SetPoint("TOPLEFT", 4, -2) W.title:SetWidth(w - 20) W.title:SetJustifyH("LEFT")
  local lbl = H.Text(pane, "GameFontNormal") lbl:SetPoint("TOPLEFT", 4, -34) lbl:SetText("How many do you want to make?")
  W.qty = H.Edit(pane, 70, true) W.qty:SetPoint("LEFT", lbl, "RIGHT", 12, 0) W.qty:SetText("1")
  W.qty:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local v = tonumber(self:GetText())
    if v and v >= 1 then want = math.floor(v) Render() end
  end)
  local function Step(d) return function() want = math.max(1, want + d) W.qty:SetText(tostring(want)) Render() end end
  local b1 = H.Button(pane, "-10", 40, 22) b1:SetPoint("LEFT", W.qty, "RIGHT", 10, 0) b1:SetScript("OnClick", Step(-10))
  local b2 = H.Button(pane, "+10", 40, 22) b2:SetPoint("LEFT", b1, "RIGHT", 4, 0) b2:SetScript("OnClick", Step(10))
  local b3 = H.Button(pane, "+100", 46, 22) b3:SetPoint("LEFT", b2, "RIGHT", 4, 0) b3:SetScript("OnClick", Step(100))
  local shop = H.Button(pane, "Shop for these", 130, 24) shop:SetPoint("LEFT", b3, "RIGHT", 16, 0)
  shop:SetScript("OnClick", function()
    local plan, S = P.plan, CP.AHShopping
    if not (plan and cur and S) then return end
    local entries = {}
    for id, qty in pairs(plan.buys) do entries[#entries + 1] = { id = id, want = qty } end
    table.sort(entries, function(a, b) return a.want > b.want end)
    if #entries == 0 then return end
    S.SetList(entries, "Buying for " .. want .. " " .. cur.name, { g = cur, crafts = plan.crafts, plan = plan })
    if CP.AHTab and CP.AHTab.IsReady and CP.AHTab.IsReady() and CP.AH.IsOpen() then CP.AHTab.Go("shopping") else CP.UI.SetTab("shopping") end
  end)
  W.out = H.Text(pane, "GameFontHighlight") W.out:SetPoint("TOPLEFT", 4, -70) W.out:SetWidth(w - 30) W.out:SetJustifyH("LEFT") W.out:SetJustifyV("TOP")
  Render()
  return pane
end

function P.Resize(w, h)
  if pane then pane:SetSize(w, h) end
  if W.out then W.out:SetWidth(w - 30) end
  if W.title then W.title:SetWidth(w - 20) end
end
