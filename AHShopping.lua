local ADDON, CP = ...
-- Shopping pane: a list of items to buy (usually the materials for a craft), live AH results for the
-- selected one, and a two-click buy (the game needs a click to start and a click to confirm).
local H = CP.AH
local S = {}
CP.AHShopping = S

local ROWS = 15
local list = {}            -- { { id=, want= } }
local sel = 1
local pane
local state = { results = {}, kind = nil, pending = false }
local W = {}

local function Name(id) return CP.ItemName and CP.ItemName(id) or ("item " .. tostring(id)) end
local function Have(id) return GetItemCount and GetItemCount(id) or 0 end
local function Need(e) return math.max(0, (e.want or 1) - Have(e.id)) end

local function SetStatus(t) if W.status then W.status:SetText(t or "") end end

------------------------------------------------------------------------
-- search
------------------------------------------------------------------------
local function Cancel()
  if state.buying and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
  state.buying, state.confirm, state.total = nil, nil, nil
end

local function Draw() if S.Draw then S.Draw() end end

function S.Search()
  local e = list[sel]
  Cancel()
  state.results, state.kind = {}, nil
  Draw()
  if not e then return end
  if not (C_AuctionHouse and H.IsOpen()) then SetStatus("Open the auction house to search.") return end
  if not H.Ready() then state.pending = true SetStatus("Waiting for the auction house...") return end
  state.pending = false
  state.searchId = e.id
  SetStatus("Searching for " .. Name(e.id) .. "...")
  local key = C_AuctionHouse.MakeItemKey(e.id)
  local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, key, sorts, true)
  if not ok then CP.RecordError("shopping search", err) SetStatus("The search failed. See /pf errors.") end
end

local function ReadCommodity(id)
  local out = {}
  local n = C_AuctionHouse.GetNumCommoditySearchResults(id) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    if r then out[#out + 1] = { price = r.unitPrice, qty = r.quantity, mine = (r.numOwnerItems or 0) > 0 } end
  end
  return out
end

local function ReadItems(key)
  local out = {}
  local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
  for i = 1, n do
    local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    if r and r.buyoutAmount then
      out[#out + 1] = { price = r.buyoutAmount, qty = r.quantity or 1, auctionID = r.auctionID, link = r.itemLink, mine = r.containsOwnerItem }
    end
  end
  return out
end

------------------------------------------------------------------------
-- the list
------------------------------------------------------------------------
function S.SetList(entries, title)
  list = {}
  for _, e in ipairs(entries) do list[#list + 1] = { id = e.id, want = e.want } end
  sel = 1
  S.title = title
  if W.list then W.list.offset = 0 end
  Draw()
  if H.IsOpen() then S.Search() end
end

function S.Add(id, want)
  for _, e in ipairs(list) do if e.id == id then e.want = (e.want or 0) + (want or 1) Draw() return end end
  list[#list + 1] = { id = id, want = want or 1 }
  sel = #list
  Draw()
  S.Search()
end

local function MatsOf(g)
  -- what to buy for a craft: the AH materials, as many crafts as the gold allows
  local out = {}
  local d = CP:BuyDepth(g)
  if d and d.crafts and d.crafts > 0 then
    for _, sl in ipairs(d.mats) do
      if not sl.flat and sl.units > 0 then out[#out + 1] = { id = sl.id, want = sl.units } end
    end
  else
    for _, rg in ipairs(g.reagents or {}) do
      local _, src, id = CP:SlotCost(rg)
      id = id or rg.id
      if src ~= "vendor" and id then out[#out + 1] = { id = id, want = rg.count } end
    end
  end
  return out, d
end

function S.ForCraft(g)
  local mats, d = MatsOf(g)
  if #mats == 0 then CP:Print("Nothing to buy at the auction house for " .. g.name .. " (vendor items or no price data).") return false end
  S.SetList(mats, "Materials for " .. g.name .. (d and d.crafts and d.crafts > 0 and (" (" .. d.crafts .. " crafts)") or ""))
  return true
end

function S.ForOutput(g)
  S.SetList({ { id = g.id, want = 1 } }, g.name)
  return true
end

function S.ForList(results, label)
  local sum, order = {}, {}
  for _, g in ipairs(results) do
    for _, m in ipairs((MatsOf(g))) do
      if not sum[m.id] then sum[m.id] = 0 order[#order + 1] = m.id end
      sum[m.id] = sum[m.id] + m.want
    end
  end
  local entries = {}
  for _, id in ipairs(order) do entries[#entries + 1] = { id = id, want = sum[id] } end
  if #entries == 0 then CP:Print("Nothing to buy for " .. label .. ".") return false end
  S.SetList(entries, "Materials for " .. label)
  return true
end

------------------------------------------------------------------------
-- buying
------------------------------------------------------------------------
local function WantQty()
  local n = tonumber(W.qty and W.qty:GetText()) or 0
  return math.max(0, math.floor(n))
end

local function BuyClick()
  local e = list[sel]
  if not e then return end
  if state.kind == "commodity" then
    local n = WantQty()
    if n <= 0 then SetStatus("Enter how many to buy.") return end
    if state.confirm and state.buying and state.buying.n == n then
      local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, e.id, n)
      if not ok then CP.RecordError("confirm purchase", err) end
      state.confirm = false
      SetStatus("Buying...")
      Draw()
    else
      Cancel()
      local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, e.id, n)
      if not ok then CP.RecordError("start purchase", err) SetStatus("Could not start the purchase.") return end
      state.buying = { id = e.id, n = n }
      SetStatus("Getting the price...")
    end
  elseif state.kind == "item" then
    local r = state.results[state.pick or 1]
    if not r then SetStatus("Pick a listing first.") return end
    local ok, err = pcall(C_AuctionHouse.PlaceBid, r.auctionID, r.price)
    if not ok then CP.RecordError("buyout", err) SetStatus("Could not buy that listing.") return end
    SetStatus("Buying...")
    CP.After(1.0, function() S.Search() end)
  else
    SetStatus("Nothing to buy yet.")
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local GOLD = { 1, 0.82, 0 }
local function Accent()
  local L = CP.WinLook
  if L and L.On and L.On("main") then local e = L.Effective("main") if e and e.edgeColor then return e.edgeColor end end
  return { 0.85, 0.65, 0.2 }
end

local function QualityColor(id)
  local q
  if C_Item and C_Item.GetItemQualityByID then local ok, v = pcall(C_Item.GetItemQualityByID, id) if ok then q = v end end
  if not q and GetItemInfo then q = select(3, GetItemInfo(id)) end
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function Panel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(w, h)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.02, 0.02, 0.04, 0.55)
    local a = Accent()
    f:SetBackdropBorderColor(a[1], a[2], a[3], 0.55)
  end
  return f
end

function S.Draw()
  if not pane then return end
  local e = list[sel]
  local acc = Accent()
  W.accentLine:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
  W.lp:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.55)
  W.rp:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.55)
  W.ab:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.55)
  W.title:SetText(S.title or "Shopping list")
  do
    local sum, known = 0, 0
    for _, it in ipairs(list) do
      if it.estCost and it.estFor == math.max(0, (it.want or 1) - Have(it.id)) then sum = sum + it.estCost known = known + 1 end
    end
    local txt = #list > 0 and (#list .. (#list == 1 and " item" or " items")) or ""
    if #list > 1 and known == #list then txt = txt .. "   |cffffd100all together: " .. H.Money(sum) .. "|r" end
    W.count:SetText(txt)
  end
  -- left list
  W.list.n = #list
  local maxOff = math.max(0, #list - ROWS)
  if W.list.offset > maxOff then W.list.offset = maxOff end
  for i, r in ipairs(W.list.rows) do
    local idx = i + W.list.offset
    local it = list[idx]
    r.idx = idx
    if it then
      r.icon:SetTexture(H.Icon(it.id))
      r.name:SetText(Name(it.id))
      r.name:SetTextColor(QualityColor(it.id))
      local have, want = Have(it.id), it.want or 1
      local need = math.max(0, want - have)
      r.need:SetText(need == 0 and "|cff40ff40done|r" or ("|cffffd100" .. need .. "|r |cff888888to buy|r"))
      r.bar:SetWidth(math.max(0.01, math.min(1, have / math.max(1, want))) * (r:GetWidth() > 0 and r:GetWidth() or 240))
      r.bar:SetShown(have > 0)
      r.stripe:SetShown(idx % 2 == 0)
      r.sel:SetShown(idx == sel)
      r:Show()
    else
      r:Hide()
    end
  end
  W.empty:SetShown(#list == 0)
  W.rp:SetShown(#list > 0)
  W.ab:SetShown(#list > 0)
  if not e then return end

  -- hero header
  W.heroIcon:SetTexture(H.Icon(e.id))
  W.heroName:SetText(Name(e.id))
  W.heroName:SetTextColor(QualityColor(e.id))
  local have, want = Have(e.id), e.want or 1
  W.heroSub:SetText(("You have |cffffd100%d|r of |cffffd100%d|r"):format(have, want))
  W.heroBar:SetMinMaxValues(0, math.max(1, want))
  W.heroBar:SetValue(math.min(have, want))
  local scan = CP.db.prices[e.id]
  local res = state.results or {}
  if res[1] and scan and scan.ref and scan.ref > 0 then
    local pct = (res[1].price / scan.ref - 1) * 100
    local col = pct <= -1 and "|cff40ff40" or (pct >= 5 and "|cffff6040" or "|cffffd100")
    W.heroMkt:SetText(("Cheapest now %s  %s%+.0f%%|r |cff888888vs usual %s|r"):format(H.Money(res[1].price), col, pct, H.Money(scan.ref)))
  else
    W.heroMkt:SetText(scan and scan.ref and ("|cff888888usual price " .. H.Money(scan.ref) .. "|r") or "")
  end

  W.res.n = #res
  local maxR = math.max(0, #res - (ROWS - 2))
  if W.res.offset > maxR then W.res.offset = maxR end
  local want = (state.kind == "commodity") and WantQty() or 0
  local cumQ, cumC = 0, 0
  for i = 1, W.res.offset do cumQ = cumQ + (res[i].qty or 0) cumC = cumC + (res[i].qty or 0) * res[i].price end
  for i, r in ipairs(W.res.rows) do
    local idx = i + W.res.offset
    local x = res[idx]
    if x then
      local before = cumQ
      cumQ = cumQ + (x.qty or 0)
      cumC = cumC + (x.qty or 0) * x.price
      r.price:SetText(H.Money(x.price))
      r.qty:SetText(tostring(x.qty or 1))
      r.cumq:SetText(tostring(cumQ))
      r.cumc:SetText(H.Money(cumC))
      local picked = state.kind == "item" and (state.pick or 1) == idx
      local covered = state.kind == "commodity" and want > 0 and before < want
      r.sel:SetShown(picked)
      r.cover:SetShown(covered)
      r.stripe:SetShown(idx % 2 == 0)
      r.name:SetText(x.mine and "|cff40c0ffyours|r" or (idx == 1 and "|cff40ff40cheapest|r" or ""))
      r.idx = idx
      r:Show()
    else
      r:Hide()
    end
  end
  -- buy button + total
  if state.kind == "commodity" then
    local n = WantQty()
    local cost, left = 0, n
    for _, x in ipairs(res) do
      if left <= 0 then break end
      local take = math.min(left, x.qty)
      cost = cost + take * x.price
      left = left - take
    end
    if n == 0 then W.total:SetText("")
    elseif left > 0 then W.total:SetText("|cffff6040Only " .. (n - left) .. " listed|r")
    else
      W.total:SetText("|cff888888This item:|r " .. H.Money(cost) .. "\n|cff888888for " .. n .. "|r")
      local it = list[sel]
      if it then it.estCost, it.estFor = cost, n end
    end
    W.buy:SetText((state.confirm and state.total) and ("Confirm  " .. H.Money(state.total)) or ("Buy " .. n))
    W.buy:SetEnabled(n > 0 and #res > 0 and H.IsOpen())
    W.qty:Show() W.qtyLabel:Show()
  elseif state.kind == "item" then
    local x = res[state.pick or 1]
    W.total:SetText(x and ("Buyout " .. H.Money(x.price)) or "")
    W.buy:SetText("Buy this listing")
    W.buy:SetEnabled(x ~= nil and H.IsOpen())
    W.qty:Hide() W.qtyLabel:Hide()
  else
    W.total:SetText("")
    W.buy:SetText("Buy")
    W.buy:Disable()
  end
end

function S.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  S.pane = pane

  local leftW = 262
  local listH = ROWS * 20 + 8
  local barH = 50

  -- header strip
  W.title = H.Text(pane, "GameFontNormalLarge")
  W.title:SetPoint("TOPLEFT", 4, -2)
  W.title:SetWidth(w - 300)
  W.title:SetJustifyH("LEFT")
  W.count = H.Text(pane, "GameFontDisableSmall")
  W.count:SetPoint("TOPRIGHT", -176, -8)
  W.listsBtn = H.Button(pane, "Lists  v", 78, 20)
  W.listsBtn:SetPoint("TOPRIGHT", -88, -2)
  W.listsBtn:SetScript("OnClick", function(self)
    CP.AHLists.Open(self, function(entries, name) S.SetList(entries, name) end)
  end)
  W.saveBtn = H.Button(pane, "Save list", 78, 20)
  W.saveBtn:SetPoint("TOPRIGHT", -6, -2)
  W.saveBtn:SetScript("OnClick", function(self)
    if #list == 0 then SetStatus("Nothing on the list to save.") return end
    CP.AHLists.AskSave(self, function() return list end, S.title and tostring(S.title):gsub("^Materials for ", "") or "My list",
      function(name) S.title = name SetStatus("Saved the list as " .. name .. ".") Draw() end)
  end)
  W.accentLine = pane:CreateTexture(nil, "ARTWORK")
  W.accentLine:SetPoint("TOPLEFT", 0, -24)
  W.accentLine:SetPoint("TOPRIGHT", 0, -24)
  W.accentLine:SetHeight(2)

  -- left panel: the list
  W.lp = Panel(pane, leftW, ROWS * 20 + 12)
  W.lp:SetPoint("TOPLEFT", 0, -32)
  local lf = CreateFrame("Frame", nil, W.lp)
  lf:SetPoint("TOPLEFT", 4, -4)
  lf:SetSize(leftW - 8, ROWS * 20)
  W.list = H.RowList(lf, ROWS, 20, function(r, i)
    r.stripe = r:CreateTexture(nil, "BACKGROUND") r.stripe:SetAllPoints() r.stripe:SetColorTexture(1, 1, 1, 0.035)
    r.bar = r:CreateTexture(nil, "BACKGROUND", nil, 1) r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT") r.bar:SetColorTexture(0.2, 0.7, 0.25, 0.22)
    r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(18, 18) r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = H.Text(r, "GameFontHighlightSmall") r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0) r.name:SetWidth(140) r.name:SetJustifyH("LEFT")
    r.need = H.Text(r) r.need:SetPoint("RIGHT", -6, 0) r.need:SetJustifyH("RIGHT")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, btn)
      if not (self.idx and list[self.idx]) then return end
      if btn == "RightButton" then
        table.remove(list, self.idx)
        if sel > #list then sel = #list end
        if sel < 1 then sel = 1 end
        S.Draw() S.Search() return
      end
      sel = self.idx S.Draw() S.Search()
    end)
  end)
  W.list.refresh = S.Draw

  -- add / clear under the list
  local add = H.Edit(pane, 150)
  add:SetPoint("TOPLEFT", W.lp, "BOTTOMLEFT", 8, -8)
  local addBtn = H.Button(pane, "Add", 50, 22)
  addBtn:SetPoint("LEFT", add, "RIGHT", 6, 0)
  local clear = H.Button(pane, "Clear", 50, 22)
  clear:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
  local function DoAdd()
    local t = add:GetText() or ""
    local id = tonumber(t) or tonumber(t:match("item:(%d+)"))
    if not id and GetItemInfoInstant and t ~= "" then local ok, v = pcall(GetItemInfoInstant, t) if ok then id = v end end
    if not id and t ~= "" then
      local lower = t:lower()
      for iid, n in pairs(CP.db.names or {}) do if n:lower() == lower then id = iid break end end
    end
    if not id and t ~= "" then
      -- part of a name: add every known item that matches (up to 15)
      local lower, found = t:lower(), {}
      for iid, n in pairs(CP.db.names or {}) do
        if type(n) == "string" and n:lower():find(lower, 1, true) then found[#found + 1] = iid end
      end
      table.sort(found, function(a, b) return (CP.db.names[a] or "") < (CP.db.names[b] or "") end)
      if #found > 0 then
        add:SetText("")
        for i = 1, math.min(15, #found) do
          local dup = false
          for _, e in ipairs(list) do if e.id == found[i] then dup = true break end end
          if not dup then list[#list + 1] = { id = found[i], want = 20 } end
        end
        sel = math.max(1, math.min(sel, #list))
        Draw() S.Search()
        SetStatus(#found .. " item(s) match \"" .. t .. "\"" .. (#found > 15 and ", added the first 15." or "."))
        return
      end
    end
    if id then add:SetText("") S.Add(id, 1) else SetStatus("No known item matches that. Try an ID, an item link, or part of a name.") end
  end
  addBtn:SetScript("OnClick", DoAdd)
  add:SetScript("OnEnterPressed", function(self) self:ClearFocus() DoAdd() end)
  clear:SetScript("OnClick", function() list = {} sel = 1 S.title = nil Cancel() state.results = {} S.Draw() end)
  local hint = H.Text(pane, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", add, "BOTTOMLEFT", -2, -5)
  hint:SetText("Add by ID, link or part of a name. Right-click a row to remove it.")

  -- empty state
  W.empty = CreateFrame("Frame", nil, pane)
  W.empty:SetPoint("TOPLEFT", leftW + 16, -40)
  W.empty:SetPoint("BOTTOMRIGHT", 0, 0)
  local eIcon = W.empty:CreateTexture(nil, "ARTWORK") eIcon:SetSize(64, 64) eIcon:SetPoint("TOP", 0, -60) eIcon:SetTexture(134400)
  eIcon:SetDesaturated(true) eIcon:SetAlpha(0.6)
  local eT = H.Text(W.empty, "GameFontNormalLarge") eT:SetPoint("TOP", eIcon, "BOTTOM", 0, -14) eT:SetText("Nothing on your list yet")
  local eS = H.Text(W.empty, "GameFontHighlight") eS:SetPoint("TOP", eT, "BOTTOM", 0, -10) eS:SetWidth(380) eS:SetJustifyH("CENTER")
  eS:SetText("Open the Crafts tab and click a craft: its materials land here, sized to the gold you have.\nOr pick a ready-made list (herbs, ores, bars...) from Lists, or add items by name.")

  -- right panel: item hero + results
  local rx = leftW + 12
  W.rp = Panel(pane, w - rx, listH + 30)
  W.rp:SetPoint("TOPLEFT", rx, -32)
  W.heroIcon = W.rp:CreateTexture(nil, "ARTWORK") W.heroIcon:SetSize(40, 40) W.heroIcon:SetPoint("TOPLEFT", 12, -10)
  W.heroIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  W.heroName = H.Text(W.rp, "GameFontNormalHuge") W.heroName:SetPoint("TOPLEFT", W.heroIcon, "TOPRIGHT", 10, -1) W.heroName:SetWidth(w - rx - 80) W.heroName:SetJustifyH("LEFT")
  W.heroSub = H.Text(W.rp, "GameFontHighlightSmall") W.heroSub:SetPoint("TOPLEFT", W.heroName, "BOTTOMLEFT", 0, -4)
  W.heroBar = CreateFrame("StatusBar", nil, W.rp)
  W.heroBar:SetSize(160, 8)
  W.heroBar:SetPoint("LEFT", W.heroSub, "RIGHT", 10, 0)
  W.heroBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  W.heroBar:SetStatusBarColor(0.25, 0.75, 0.3, 0.9)
  local hbBg = W.heroBar:CreateTexture(nil, "BACKGROUND") hbBg:SetAllPoints() hbBg:SetColorTexture(1, 1, 1, 0.12)
  W.heroMkt = H.Text(W.rp, "GameFontHighlightSmall") W.heroMkt:SetPoint("TOPLEFT", W.heroIcon, "BOTTOMLEFT", 0, -6)

  local hdr = { { "Price each", 8, 120 }, { "Listed", 130, 56 }, { "Total so far", 196, 70 }, { "Cost so far", 276, 130 } }
  for _, c in ipairs(hdr) do
    local fs = H.Text(W.rp, "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", c[2] + 6, -82)
    fs:SetText(c[1])
  end
  local ln = W.rp:CreateTexture(nil, "ARTWORK") ln:SetPoint("TOPLEFT", 6, -96) ln:SetPoint("TOPRIGHT", -6, -96) ln:SetHeight(1) ln:SetColorTexture(1, 1, 1, 0.15)
  local rf = CreateFrame("Frame", nil, W.rp)
  rf:SetPoint("TOPLEFT", 6, -98)
  rf:SetSize(w - rx - 12, (ROWS - 5) * 20)
  W.res = H.RowList(rf, ROWS - 5, 20, function(r)
    r.stripe = r:CreateTexture(nil, "BACKGROUND") r.stripe:SetAllPoints() r.stripe:SetColorTexture(1, 1, 1, 0.035)
    r.cover = r:CreateTexture(nil, "BACKGROUND", nil, 1) r.cover:SetAllPoints() r.cover:SetColorTexture(1, 0.82, 0, 0.12)
    r.price = H.Text(r) r.price:SetPoint("LEFT", 8, 0) r.price:SetWidth(120) r.price:SetJustifyH("LEFT")
    r.qty = H.Text(r) r.qty:SetPoint("LEFT", 130, 0) r.qty:SetWidth(56) r.qty:SetJustifyH("LEFT")
    r.cumq = H.Text(r) r.cumq:SetPoint("LEFT", 196, 0) r.cumq:SetWidth(70) r.cumq:SetJustifyH("LEFT")
    r.cumc = H.Text(r) r.cumc:SetPoint("LEFT", 276, 0) r.cumc:SetWidth(130) r.cumc:SetJustifyH("LEFT")
    r.name = H.Text(r) r.name:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnClick", function(self) if state.kind == "item" then state.pick = self.idx S.Draw() end end)
  end)
  W.res.refresh = S.Draw

  -- action bar along the bottom
  W.ab = Panel(pane, w - rx, barH)
  W.ab:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  W.qtyLabel = H.Text(W.ab, "GameFontNormalSmall") W.qtyLabel:SetPoint("TOPLEFT", 14, -6) W.qtyLabel:SetText("How many")
  W.qty = H.Edit(W.ab, 64, true)
  W.qty:SetPoint("BOTTOMLEFT", 18, 7)
  W.qty:SetScript("OnTextChanged", function(self, user) if user then Cancel() S.Draw() end end)
  W.buy = H.Button(W.ab, "Buy", 150, 34)
  W.buy:SetPoint("LEFT", W.qty, "RIGHT", 14, 0)
  local fnt = W.buy:GetFontString() if fnt and fnt.SetFontObject then fnt:SetFontObject("GameFontNormalLarge") end
  W.buy:SetScript("OnClick", BuyClick)
  local refresh = H.Button(W.ab, "Refresh", 80, 24)
  refresh:SetPoint("LEFT", W.buy, "RIGHT", 8, 0)
  refresh:SetScript("OnClick", function() S.Search() end)
  W.total = H.Text(W.ab, "GameFontHighlight")
  W.total:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
  W.total:SetPoint("RIGHT", W.ab, "RIGHT", -6, 0)
  W.total:SetJustifyH("LEFT")
  if W.total.SetWordWrap then W.total:SetWordWrap(true) end
  W.status = H.Text(pane, "GameFontHighlightSmall")
  W.status:SetPoint("BOTTOMLEFT", W.ab, "TOPLEFT", 6, 4)
  W.status:SetWidth(w - rx - 12)
  W.status:SetJustifyH("LEFT")

  pane:SetScript("OnShow", function()
    local e = list[sel]
    if e then
      W.qty:SetText(tostring(Need(e) > 0 and Need(e) or (e.want or 1)))
      S.Search()
    end
    S.Draw()
  end)
  return pane
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", CP.Safe("shopping-event", function(_, event, a, b)
  if not pane or not pane:IsShown() then return end
  local e = list[sel]
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if not e or a ~= e.id then return end
    state.kind = "commodity"
    state.results = ReadCommodity(e.id)
    if C_AuctionHouse.HasFullCommoditySearchResults and not C_AuctionHouse.HasFullCommoditySearchResults(e.id) and #state.results < 150 then
      pcall(C_AuctionHouse.RequestMoreCommoditySearchResults, e.id)
    end
    SetStatus(#state.results == 0 and "Nobody is selling this right now." or "")
    S.Draw()
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if not e then return end
    state.kind = "item"
    local key = a
    state.results = ReadItems(key)
    state.pick = state.pick and math.min(state.pick, math.max(1, #state.results)) or 1
    SetStatus(#state.results == 0 and "Nobody is selling this right now." or "Pick a listing, then Buy.")
    S.Draw()
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if state.buying then
      state.total = b
      state.confirm = true
      SetStatus("Price is " .. H.Money(a) .. " each. Click again to confirm.")
      S.Draw()
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    SetStatus("Those items are no longer available at that price.")
    Cancel()
    S.Search()
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    SetStatus("Bought.")
    Cancel()
    CP.After(0.5, function() S.Search() end)
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    SetStatus("The purchase failed.")
    Cancel()
    S.Draw()
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if state.pending then S.Search() end
  elseif event == "BAG_UPDATE_DELAYED" then
    S.Draw()
  end
end))
