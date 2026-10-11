local ADDON, CP = ...
-- Selling pane: pick something from your bags, see the lowest price from your last scan, post it.
local H = CP.AH
local Sl = {}
CP.AHSelling = Sl

local ROWS = 15
local pane, listf
local W = {}
local items = {}       -- aggregated bag contents
local sel
local DURATIONS = { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }
local durIdx = 2

local function SetStatus(t) if W.status then W.status:SetText(t or "") end end

local function ScanBags()
  items = {}
  local by = {}
  local nslots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getinfo = C_Container and C_Container.GetContainerItemInfo
  for bag = 0, 4 do
    for slot = 1, (nslots and nslots(bag) or 0) do
      local info = getinfo and getinfo(bag, slot)
      if info and info.itemID and not info.isBound then
        local e = by[info.itemID]
        if not e then
          e = { id = info.itemID, count = 0, bag = bag, slot = slot, link = info.hyperlink, icon = info.iconFileID }
          by[info.itemID] = e
          items[#items + 1] = e
        end
        e.count = e.count + (info.stackCount or 1)
      end
    end
  end
  for _, e in ipairs(items) do
    local p = CP.db.prices[e.id]
    e.unit = p and (p.ref or p.min)
    e.worth = e.unit and e.unit * e.count or 0
  end
  table.sort(items, function(a, b) if a.worth ~= b.worth then return a.worth > b.worth end return a.id < b.id end)
end

local function Selected() for _, e in ipairs(items) do if e.id == sel then return e end end end

local function Commodity(e)
  local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(e.bag, e.slot)
  if not loc then return false end
  local ok, key = pcall(C_AuctionHouse.GetItemKeyFromItem, loc)
  if ok and key and C_AuctionHouse.GetItemCommodityStatus then
    local ok2, st = pcall(C_AuctionHouse.GetItemCommodityStatus, key)
    if ok2 then return st == (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2), loc end
  end
  return (e.count or 1) > 1, loc
end

local function Suggest(e)
  local p = CP.db.prices[e.id]
  if not p or not p.min then return nil end
  local cut = CP.db.settings.undercut or 1
  return math.max(1, p.min - cut)
end

function Sl.Draw()
  if not pane then return end
  listf.n = #items
  local maxOff = math.max(0, #items - ROWS)
  if listf.offset > maxOff then listf.offset = maxOff end
  for i, r in ipairs(listf.rows) do
    local e = items[i + listf.offset]
    if e then
      r.e = e
      r.icon:SetTexture(e.icon or H.Icon(e.id))
      r.name:SetText(e.link or CP.ItemName(e.id))
      r.count:SetText("x" .. e.count)
      r.worth:SetText(e.unit and H.Money(e.worth) or "|cff888888?|r")
      r.sel:SetShown(e.id == sel)
      r:Show()
    else
      r:Hide()
    end
  end
  local acc = H.Accent()
  W.accentLine:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
  W.lp:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.55)
  W.rp:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.55)
  local e = Selected()
  if not e then
    W.icon:SetTexture(134400) W.icon:SetDesaturated(true)
    W.head:SetText("Pick something from your bags")
    W.low:SetText("") W.dep:SetText("") W.post:Disable()
    return
  end
  W.icon:SetTexture(e.icon or H.Icon(e.id)) W.icon:SetDesaturated(false)
  W.head:SetText(e.link or CP.ItemName(e.id))
  local p = CP.db.prices[e.id]
  W.low:SetText("Lowest at the last scan: " .. (p and p.min and H.Money(p.min) or "no data") ..
    (p and p.ref and ("   reference " .. H.Money(p.ref)) or ""))
  W.dur:SetText(DURATIONS[durIdx][2])
  local qty = math.max(1, math.min(e.count, tonumber(W.qty:GetText()) or e.count))
  local price = H.ParseMoney(W.price:GetText())
  local isC = Commodity(e)
  if price then
    W.dep:SetText("You get about " .. H.Money(math.floor(price * qty * (1 - (CP.db.settings.ahCut or 0.05)))) .. " after the cut for " .. qty)
  else
    W.dep:SetText("Enter a price each, like 1g 30s")
  end
  W.post:SetEnabled(price ~= nil and price > 0 and H.IsOpen())
end

local function Pick(e)
  sel = e.id
  W.qty:SetText(tostring(e.count))
  local s = Suggest(e)
  W.price:SetText(s and (function(c) local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100 return (g > 0 and (g .. "g ") or "") .. (sv > 0 and (sv .. "s ") or "") .. (cp > 0 and (cp .. "c") or "") end)(s) or "")
  SetStatus(s and "Suggested: one copper under the lowest price from your last scan." or "No scan data for this item. Type a price.")
  Sl.Draw()
end

local function Post()
  local e = Selected()
  if not e then return end
  local price = H.ParseMoney(W.price:GetText())
  if not price or price <= 0 then SetStatus("Enter a price.") return end
  local qty = math.max(1, math.min(e.count, tonumber(W.qty:GetText()) or e.count))
  local isC, loc = Commodity(e)
  if not loc then SetStatus("Could not find the item in your bags.") return end
  local dur = DURATIONS[durIdx][1]
  local ok, err
  if isC then
    ok, err = pcall(C_AuctionHouse.PostCommodity, loc, dur, qty, price)
  else
    ok, err = pcall(C_AuctionHouse.PostItem, loc, dur, 1, nil, price)
  end
  if not ok then CP.RecordError("post auction", err) SetStatus("Could not post. See /pf errors.") return end
  SetStatus("Posting...")
end

function Sl.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  Sl.pane = pane
  local leftW = 290

  local ph = ROWS * 20 + 30
  W.accentLine = pane:CreateTexture(nil, "ARTWORK")
  W.lp = H.Panel(pane, leftW + 8, ph)
  W.lp:SetPoint("TOPLEFT", 0, -6)
  W.rp = H.Panel(pane, w - leftW - 12, ph)
  W.rp:SetPoint("TOPRIGHT", 0, -6)
  W.accentLine:SetPoint("TOPLEFT", 0, -3)
  W.accentLine:SetPoint("TOPRIGHT", 0, -3)
  W.accentLine:SetHeight(2)
  local t = H.Text(W.lp, "GameFontNormal")
  t:SetPoint("TOPLEFT", 8, -8)
  t:SetText("Your bags (not soulbound)")
  local lf = CreateFrame("Frame", nil, pane)
  lf:SetPoint("TOPLEFT", 4, -32)
  lf:SetSize(leftW, ROWS * 20)
  listf = H.RowList(lf, ROWS, 20, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 2, 0)
    r.name = H.Text(r) r.name:SetPoint("LEFT", 22, 0) r.name:SetWidth(150) r.name:SetJustifyH("LEFT")
    r.count = H.Text(r) r.count:SetPoint("LEFT", 176, 0) r.count:SetWidth(40) r.count:SetJustifyH("LEFT")
    r.worth = H.Text(r) r.worth:SetPoint("RIGHT", -4, 0) r.worth:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self) if self.e then Pick(self.e) end end)
  end)
  listf.refresh = Sl.Draw

  local rx = leftW + 28
  local rp = W.rp
  W.icon = rp:CreateTexture(nil, "ARTWORK")
  W.icon:SetSize(40, 40)
  W.icon:SetPoint("TOPLEFT", rx - 12 + 0, -10)
  W.iconBorder = rp:CreateTexture(nil, "OVERLAY")
  W.iconBorder:SetAllPoints(W.icon)
  W.head = H.Text(rp, "GameFontNormalLarge")
  W.head:SetPoint("TOPLEFT", rx + 34, -12)
  W.head:SetWidth(w - rx - 44)
  W.head:SetJustifyH("LEFT")
  W.low = H.Text(rp)
  W.low:SetPoint("TOPLEFT", rx + 34, -34)

  local function Label(txt, y)
    local fs = H.Text(rp, "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", rx, y)
    fs:SetText(txt)
    return fs
  end
  Label("Price each (like 1g 30s 5c)", -66)
  W.price = H.Edit(pane, 150)
  W.price:SetPoint("TOPLEFT", rx + 4, -84)
  W.price:SetMaxLetters(24)
  W.price:SetScript("OnTextChanged", function(_, user) if user then Sl.Draw() end end)
  local lowest = H.Button(pane, "Undercut lowest", 120, 22)
  lowest:SetPoint("LEFT", W.price, "RIGHT", 10, 0)
  lowest:SetScript("OnClick", function() local e = Selected() if e then Pick(e) end end)

  Label("How many", -120)
  W.qty = H.Edit(pane, 70, true)
  W.qty:SetPoint("TOPLEFT", rx + 4, -138)
  W.qty:SetScript("OnTextChanged", function(_, user) if user then Sl.Draw() end end)

  Label("Duration", -170)
  W.dur = H.Button(pane, "24 hours", 120, 22)
  W.dur:SetPoint("TOPLEFT", rx, -188)
  W.dur:SetScript("OnClick", function() durIdx = durIdx % #DURATIONS + 1 Sl.Draw() end)

  W.dep = H.Text(rp)
  W.dep:SetPoint("TOPLEFT", rx, -224)
  W.status = H.Text(rp)
  W.status:SetPoint("TOPLEFT", rx, -246)
  W.status:SetWidth(w - rx - 8)
  W.status:SetJustifyH("LEFT")

  W.post = H.Button(pane, "Post auction", 160, 28)
  W.post:SetPoint("BOTTOMRIGHT", -8, 8)
  W.post:SetScript("OnClick", Post)
  local refresh = H.Button(pane, "Refresh bags", 100, 24)
  refresh:SetPoint("RIGHT", W.post, "LEFT", -6, 0)
  refresh:SetScript("OnClick", function() ScanBags() Sl.Draw() end)

  pane:SetScript("OnShow", function() ScanBags() Sl.Draw() end)
  return pane
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", CP.Safe("selling-event", function(_, event)
  if not pane or not pane:IsShown() then return end
  if event == "AUCTION_HOUSE_AUCTION_CREATED" then SetStatus("Posted.") end
  ScanBags()
  Sl.Draw()
end))
