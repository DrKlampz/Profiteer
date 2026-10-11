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
function S.Draw()
  if not pane then return end
  local e = list[sel]
  W.title:SetText(S.title or (#list > 0 and "Shopping list" or "Shopping list is empty. Click a craft in the Crafts tab, or add an item."))
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
      local need = Need(it)
      r.need:SetText(need == 0 and "|cff40ff40have|r" or ("need " .. need))
      r.sel:SetShown(idx == sel)
      r:Show()
    else
      r:Hide()
    end
  end
  -- right: results
  if not e then
    W.head:SetText("")
    for _, r in ipairs(W.res.rows) do r:Hide() end
    W.total:SetText("")
    W.buy:Disable()
    return
  end
  W.head:SetText(Name(e.id) .. "   |cff888888you have " .. Have(e.id) .. ", want " .. (e.want or 1) .. "|r")
  local res = state.results or {}
  W.res.n = #res
  local maxR = math.max(0, #res - ROWS)
  if W.res.offset > maxR then W.res.offset = maxR end
  local cumQ, cumC = 0, 0
  for i = 1, W.res.offset do cumQ = cumQ + (res[i].qty or 0) cumC = cumC + (res[i].qty or 0) * res[i].price end
  for i, r in ipairs(W.res.rows) do
    local idx = i + W.res.offset
    local x = res[idx]
    if x then
      cumQ = cumQ + (x.qty or 0)
      cumC = cumC + (x.qty or 0) * x.price
      r.price:SetText(H.Money(x.price) .. (state.kind == "item" and "" or ""))
      r.qty:SetText(tostring(x.qty or 1))
      r.cumq:SetText(tostring(cumQ))
      r.cumc:SetText(H.Money(cumC))
      r.sel:SetShown(state.kind == "item" and (state.pick or 1) == idx)
      r.name:SetText(x.mine and "|cff40c0ffyours|r" or "")
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
    if left > 0 then W.total:SetText("Only " .. (n - left) .. " listed.") else W.total:SetText("About " .. H.Money(cost) .. " for " .. n) end
    if state.confirm and state.total then
      W.buy:SetText("Confirm " .. H.Money(state.total))
    else
      W.buy:SetText("Buy " .. n)
    end
    W.buy:SetEnabled(n > 0 and #res > 0 and H.IsOpen())
    W.qty:Show()
  elseif state.kind == "item" then
    local x = res[state.pick or 1]
    W.total:SetText(x and ("Buyout " .. H.Money(x.price)) or "")
    W.buy:SetText("Buy this listing")
    W.buy:SetEnabled(x ~= nil and H.IsOpen())
    W.qty:Hide()
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

  local leftW = 250
  W.title = H.Text(pane, "GameFontNormal")
  W.title:SetPoint("TOPLEFT", 4, -2)
  W.title:SetWidth(leftW)
  W.title:SetJustifyH("LEFT")

  local lf = CreateFrame("Frame", nil, pane)
  lf:SetPoint("TOPLEFT", 0, -22)
  lf:SetSize(leftW, ROWS * 20)
  W.list = H.RowList(lf, ROWS, 20, function(r, i)
    r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 2, 0)
    r.name = H.Text(r) r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0) r.name:SetWidth(150) r.name:SetJustifyH("LEFT")
    r.need = H.Text(r) r.need:SetPoint("RIGHT", -4, 0) r.need:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self, btn)
      if not (self.idx and list[self.idx]) then return end
      if btn == "RightButton" then table.remove(list, self.idx) if sel > #list then sel = #list end if sel < 1 then sel = 1 end S.Draw() S.Search() return end
      sel = self.idx S.Draw() S.Search()
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end)
  W.list.refresh = S.Draw

  local hint = H.Text(pane, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", lf, "BOTTOMLEFT", 2, -4)
  hint:SetText("Click to search. Right-click to remove.")

  local add = H.Edit(pane, 150)
  add:SetPoint("BOTTOMLEFT", 8, 4)
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
    if id then add:SetText("") S.Add(id, 1) else SetStatus("Type an item ID, paste an item link, or an exact item name.") end
  end
  addBtn:SetScript("OnClick", DoAdd)
  add:SetScript("OnEnterPressed", function(self) self:ClearFocus() DoAdd() end)
  clear:SetScript("OnClick", function() list = {} sel = 1 S.title = nil Cancel() state.results = {} S.Draw() end)

  -- right side
  local rx = leftW + 20
  W.head = H.Text(pane, "GameFontNormal")
  W.head:SetPoint("TOPLEFT", rx, -2)
  W.head:SetWidth(w - rx)
  W.head:SetJustifyH("LEFT")

  local hdr = { { "Price each", 0, 120 }, { "Listed", 130, 60 }, { "Total so far", 200, 80 }, { "Cost so far", 290, 130 } }
  for _, c in ipairs(hdr) do
    local fs = H.Text(pane, "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", rx + c[2], -22)
    fs:SetText(c[1])
  end
  local rf = CreateFrame("Frame", nil, pane)
  rf:SetPoint("TOPLEFT", rx, -38)
  rf:SetSize(w - rx - 8, (ROWS - 1) * 20)
  W.res = H.RowList(rf, ROWS - 1, 20, function(r)
    r.price = H.Text(r) r.price:SetPoint("LEFT", 0, 0) r.price:SetWidth(120) r.price:SetJustifyH("LEFT")
    r.qty = H.Text(r) r.qty:SetPoint("LEFT", 130, 0) r.qty:SetWidth(60) r.qty:SetJustifyH("LEFT")
    r.cumq = H.Text(r) r.cumq:SetPoint("LEFT", 200, 0) r.cumq:SetWidth(80) r.cumq:SetJustifyH("LEFT")
    r.cumc = H.Text(r) r.cumc:SetPoint("LEFT", 290, 0) r.cumc:SetWidth(130) r.cumc:SetJustifyH("LEFT")
    r.name = H.Text(r) r.name:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnClick", function(self) if state.kind == "item" then state.pick = self.idx S.Draw() end end)
  end)
  W.res.refresh = S.Draw

  W.qty = H.Edit(pane, 60, true)
  W.qty:SetPoint("BOTTOMLEFT", rx + 4, 4)
  W.qty:SetScript("OnTextChanged", function(self, user) if user then Cancel() S.Draw() end end)
  local ql = H.Text(pane) ql:SetPoint("BOTTOMLEFT", W.qty, "TOPLEFT", -4, 2) ql:SetText("How many")
  W.buy = H.Button(pane, "Buy", 170, 24)
  W.buy:SetPoint("LEFT", W.qty, "RIGHT", 10, 0)
  W.buy:SetScript("OnClick", BuyClick)
  local refresh = H.Button(pane, "Refresh", 80, 24)
  refresh:SetPoint("LEFT", W.buy, "RIGHT", 6, 0)
  refresh:SetScript("OnClick", function() S.Search() end)
  W.total = H.Text(pane)
  W.total:SetPoint("LEFT", refresh, "RIGHT", 12, 0)
  W.status = H.Text(pane, "GameFontHighlightSmall")
  W.status:SetPoint("BOTTOMLEFT", W.qty, "TOPLEFT", 60, 4)
  W.status:SetWidth(w - rx - 80)
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
