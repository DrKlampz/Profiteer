local ADDON, CP = ...
-- Selling pane: pick something from your bags, see how the market looks from your last scan,
-- set a price (with an undercut that can be copper or percent), choose stacks and post.
local H = CP.AH
local Sl = {}
CP.AHSelling = Sl

local pane, listf
local W = {}
local items = {}       -- aggregated bag contents
local sel
local filter = ""
local sortMode = "worth"
local gameMode, gameFrame, savedPoints   -- the game's own sell form shown inside this pane
local forbidden        -- set when the game says an add-on may not call a function
local queue            -- { id, sizes = {..}, price, dur, done, total }
local DURATIONS = { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }

local function S() return CP.db.settings end
local function SetStatus(t) if W.status then W.status:SetText(t or "") end end
local function DurIdx() return math.max(1, math.min(3, tonumber(S().sellDuration) or 2)) end

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
          e = { id = info.itemID, count = 0, bag = bag, slot = slot, link = info.hyperlink, icon = info.iconFileID, quality = info.quality }
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
    e.nameLower = (CP.ItemName(e.id) or ""):lower()
  end
end

local function Visible()
  local list = {}
  local f = filter:lower()
  for _, e in ipairs(items) do
    if f == "" or (e.nameLower or ""):find(f, 1, true) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    if sortMode == "name" then return (a.nameLower or "") < (b.nameLower or "") end
    if a.worth ~= b.worth then return a.worth > b.worth end
    return a.id < b.id
  end)
  return list
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

local function VendorPrice(id)
  local sp = GetItemInfo and select(11, GetItemInfo(id))
  return tonumber(sp) or 0
end

local function QualityOf(e)
  local q = e.quality
  if type(q) ~= "number" then q = GetItemInfo and select(3, GetItemInfo(e.id)) end
  if type(q) ~= "number" and C_Item and C_Item.GetItemQualityByID then local ok, v = pcall(C_Item.GetItemQualityByID, e.id) if ok then q = v end end
  if type(q) ~= "number" and e.link then
    local hex = e.link:match("|cff(%x%x%x%x%x%x)")
    if hex then return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 end
  end
  local c = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 0.6, 0.6, 0.6
end

-- the item's name in its quality color; the link from the bag can arrive with an empty name before the game has loaded the item
local function Label(e)
  local name = GetItemInfo and GetItemInfo(e.id)
  if not name or name == "" then name = CP.ItemName(e.id) end
  if (not name or name == "" or name:find("^item:") or name:find("^Item ")) then
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
    if e.link and not e.link:find("%[%]") then return e.link end
    return "|cff9d9d9dItem " .. e.id .. "|r"
  end
  local r, g, b = QualityOf(e)
  return string.format("|cff%02x%02x%02x[%s]|r", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, name)
end

local function MoneyText(c)
  c = math.max(0, math.floor((c or 0) + 0.5))
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = (g > 0 and (g .. "g ") or "") .. (sv > 0 and (sv .. "s ") or "") .. (cp > 0 and (cp .. "c") or "")
  if t == "" then t = "0c" end
  return (t:gsub("%s+$", ""))
end

-- the price the add-on would ask: the scan price you chose, minus your undercut, rounded as you like
local function Suggest(e)
  local p = CP.db.prices[e.id]
  if not p then return nil end
  local base = (S().sellBase == "ref" and p.ref) or p.min or p.ref
  if not base then return nil end
  local price
  if S().undercutMode == "percent" then
    price = base * (1 - (tonumber(S().undercutPct) or 1) / 100)
  else
    price = base - (tonumber(S().undercut) or 1)
  end
  local r = S().sellRound
  if r == "silver" and price >= 100 then price = math.floor(price / 100) * 100
  elseif r == "tensilver" and price >= 1000 then price = math.floor(price / 1000) * 1000 end
  price = math.floor(price)
  if S().sellVendorFloor then price = math.max(price, VendorPrice(e.id)) end
  return math.max(1, price)
end

local function Sizes(e)
  local isC = Commodity(e)
  if not isC then
    local n = math.max(1, math.min(e.count, tonumber(W.stacks:GetText()) or 1))
    local t = {}
    for i = 1, n do t[i] = 1 end
    return t, false
  end
  local size = math.max(1, tonumber(W.size:GetText()) or e.count)
  local stacks = math.max(1, tonumber(W.stacks:GetText()) or 1)
  local t, left = {}, e.count
  for i = 1, stacks do
    local q = math.min(size, left)
    if q <= 0 then break end
    t[#t + 1] = q
    left = left - q
  end
  if #t == 0 then t[1] = math.min(size, e.count) end
  return t, true
end

local function Deposit(e, qty, dur)
  local ok, v
  if Commodity(e) then
    if C_AuctionHouse.CalculateCommodityDeposit then ok, v = pcall(C_AuctionHouse.CalculateCommodityDeposit, e.id, dur, qty) end
  else
    local _, loc = Commodity(e)
    if loc and C_AuctionHouse.CalculateItemDeposit then ok, v = pcall(C_AuctionHouse.CalculateItemDeposit, loc, dur, qty) end
  end
  if ok and type(v) == "number" then return v end
  return nil
end

-- what one of this item costs you to craft, from the recipes your characters know (cheapest way)
local function CraftCost(id)
  local best
  for _, profs in pairs(CP.db.recipes or {}) do
    for _, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        if r.id == id and r.reagents then
          local cost, ok = 0, true
          for _, rg in ipairs(r.reagents) do
            local c = CP:SlotCost(rg)
            if not c then ok = false break end
            cost = cost + c * rg.count
          end
          if ok and cost > 0 then
            local per = cost / math.max(1, r.yield or 1)
            if not best or per < best then best = per end
          end
        end
      end
    end
  end
  if not best and CP.MakeCost then best = CP:MakeCost(id) end
  return best
end

local function Verdict(price, p)
  if not (price and p and p.min) then return "|cff888888No scan data to compare with.|r" end
  if price < p.min then return "|cff40ff40Below the lowest price: should sell fast.|r"
  elseif price == p.min then return "|cffffd100Matches the lowest price.|r" end
  local over = (price - p.min) / p.min * 100
  return string.format("|cffff6040%.0f%% above the lowest price: expect to wait.|r", over)
end

local function Stat(box, label, value)
  box.l:SetText(label)
  box.v:SetText(value)
end

function Sl.Draw()
  if not pane then return end
  local vis = Visible()
  listf.n = #vis
  local rowsN = #listf.rows
  local maxOff = math.max(0, #vis - rowsN)
  if listf.offset > maxOff then listf.offset = maxOff end
  for i, r in ipairs(listf.rows) do
    local e = vis[i + listf.offset]
    if e then
      r.e = e
      r.icon:SetTexture(e.icon or H.Icon(e.id))
      local qr, qg, qb = QualityOf(e)
      r.iconEdge:SetColorTexture(qr, qg, qb, 0.9)
      r.name:SetText(Label(e))
      r.count:SetText("x" .. e.count)
      r.worth:SetText(e.unit and H.Money(e.worth) or "|cff888888?|r")
      r.sel:SetShown(e.id == sel)
      r:Show()
    else
      r:Hide()
    end
  end
  W.sortBtn:SetText(sortMode == "name" and "A-Z" or "Value")
  W.listCount:SetText(#vis .. " of " .. #items)
  local acc = H.Accent()
  W.accentLine:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
  for _, p in ipairs({ W.lp, W.rp, W.sum, W.box1, W.box2, W.box3 }) do p:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.5) end

  local e = Selected()
  W.umode:SetText(S().undercutMode == "percent" and "percent" or "copper")
  W.base:SetText(S().sellBase == "ref" and "Reference" or "Lowest")
  W.dur:SetText(DURATIONS[DurIdx()][2])
  if not e then
    W.icon:SetTexture(134400) W.icon:SetDesaturated(true) W.iconEdge:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    W.head:SetText("Pick something from your bags")
    W.sub:SetText("|cff888888Click an item on the left. Prices come from your last scan.|r")
    Stat(W.box1, "Lowest", "-") Stat(W.box2, "Reference", "-") Stat(W.box3, "Vendor", "-")
    W.sumL:SetText("") W.sumR:SetText("") W.verdict:SetText("") W.be:SetText("")
    W.post:Disable()
    return
  end
  W.icon:SetTexture(e.icon or H.Icon(e.id)) W.icon:SetDesaturated(false)
  local qr, qg, qb = QualityOf(e)
  W.iconEdge:SetColorTexture(qr, qg, qb, 0.9)
  W.head:SetText(Label(e))
  local p = CP.db.prices[e.id]
  local vendor = VendorPrice(e.id)
  W.sub:SetText("|cff888888" .. e.count .. " in your bags" .. (p and p.min and ("   |   last scan " .. CP.Age(CP.db.lastScan)) or "") .. "|r")
  Stat(W.box1, "Lowest", p and p.min and H.Money(p.min) or "no data")
  Stat(W.box2, "Reference", p and p.ref and H.Money(p.ref) or "no data")
  Stat(W.box3, "Vendor", vendor > 0 and H.Money(vendor) or "none")

  local isC = Commodity(e)
  W.sizeLabel:SetText(isC and "Stack size" or "Items per auction")
  W.size:SetShown(isC) W.sizeLabel:SetShown(isC) W.all:SetShown(isC)
  local sizes = Sizes(e)
  local total = 0
  for _, q in ipairs(sizes) do total = total + q end
  local price = H.ParseMoney(W.price:GetText())
  local dur = DURATIONS[DurIdx()][1]
  if price and price > 0 then
    local gross = price * total
    local cut = math.floor(gross * (S().ahCut or 0.05))
    local dep = Deposit(e, sizes[1], dur)
    local depTotal = dep and (dep * #sizes) or 0
    local net = gross - cut - depTotal
    W.sumL:SetText("Listing " .. #sizes .. (#sizes == 1 and " auction" or " auctions") .. " of " .. (isC and (sizes[1] .. (#sizes > 1 and " each" or "")) or "1") ..
      "\\nTotal asking price\\nAuction house cut\\nDeposit (back if it sells)\\n|cffffd100You get|r")
    W.sumL:SetText((W.sumL:GetText():gsub("\\n", "\n")))
    W.sumR:SetText("\n" .. H.Money(gross) .. "\n|cffff9060-" .. H.Money(cut) .. "|r\n" ..
      (dep and ("|cffff9060-" .. H.Money(depTotal) .. "|r") or "|cff888888?|r") .. "\n|cffffd100" .. H.Money(net) .. "|r")
    W.verdict:SetText(Verdict(price, p))
    W.post:SetEnabled((not queue or queue.confirm) and H.IsOpen())
  else
    W.sumL:SetText("") W.sumR:SetText("")
    W.verdict:SetText("|cff888888Enter a price each, like 1g 30s.|r")
    W.post:Disable()
  end
  -- how far down the price can go before a sale loses money
  do
    local cost = CraftCost(e.id)
    local cut = S().ahCut or 0.05
    if cost and cost > 0 then
      local be = math.ceil(cost / (1 - cut))
      local lowest = p and p.min
      local lines = { "|cff888888Cost to make|r " .. H.Money(cost) .. "  |cff888888break-even|r " .. H.Money(be) }
      if lowest then
        local room = lowest - be
        if room > 0 then
          lines[#lines + 1] = string.format("|cff40ff40Undercut up to %s (%.0f%%) safely|r", H.Money(room), room / lowest * 100)
        else
          lines[#lines + 1] = "|cffff6040Lowest price is " .. H.Money(-room) .. " under break-even|r"
        end
      end
      if price and price > 0 then
        local gain = math.floor(price * (1 - cut)) - cost
        lines[#lines + 1] = gain >= 0 and ("|cff40ff40At your price: +" .. H.Money(gain) .. " each|r") or ("|cffff6040At your price: -" .. H.Money(-gain) .. " each|r")
      end
      W.be:SetText(table.concat(lines, "\n"))
    else
      W.be:SetText("|cff888888No craft cost known for this item" .. (vendor > 0 and ("  (vendor " .. H.Money(vendor) .. ")") or "") .. "|r")
    end
  end
  local hint = Suggest(e)
  W.sug:SetText(hint and ("|cff888888suggested|r " .. H.Money(hint)) or "|cff888888no suggestion (no scan data)|r")
  W.post:SetText(#sizes > 1 and ("Post " .. #sizes .. " auctions") or "Post auction")
end

local function Pick(e)
  if gameMode and Sl.FromGameSell then Sl.FromGameSell() end
  sel = e.id
  local s = Suggest(e)
  W.price:SetText(s and MoneyText(s) or "")
  W.size:SetText(tostring(e.count))
  W.stacks:SetText("1")
  SetStatus(s and "" or "No scan data for this item. Type a price.")
  Sl.Draw()
end

local function UsePrice(v)
  local e = Selected()
  if not e or not v then return end
  W.price:SetText(MoneyText(math.max(1, math.floor(v))))
  Sl.Draw()
end

-- fallback: the game does not let add-ons post, so its own "Create Auction" form is brought into this pane,
-- filled in with the item, quantity and price; its button is the player's click
gameMode, gameFrame, savedPoints = false, nil, nil

local cbOwner, cbPoints, pbOwner, pbPoints
function Sl.FromGameSell()
  if not gameMode then return end
  gameMode = false
  do
    local AH = _G.AuctionHouseFrame
    if AH then for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do if AH[k] and AH[k].SetAlpha then AH[k]:SetAlpha(1) end end end
  end
  if gameFrame then
    pcall(function()
      gameFrame:Hide()
      gameFrame:SetScale(1)
      if cbOwner and cbPoints then
        cbOwner:ClearAllPoints()
        for _, q in ipairs(cbPoints) do cbOwner:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
      end
      cbOwner, cbPoints = nil, nil
      if pbOwner and pbPoints then
        pbOwner:ClearAllPoints()
        for _, q in ipairs(pbPoints) do pbOwner:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
      end
      pbOwner, pbPoints = nil, nil
      gameFrame:ClearAllPoints()
      for _, q in ipairs(savedPoints or {}) do gameFrame:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
    end)
  end
  gameFrame, savedPoints = nil, nil
  if W.ov then W.ov:Show() end
  if W.back then W.back:Hide() end
  Sl.Draw()
end

function Sl.ToGameSell(info)
  local AH = _G.AuctionHouseFrame
  if not AH then return end
  gameMode = true
  if W.ov then W.ov:Hide() end
  W.back:Show()
  SetStatus("Opening the game's sell form...")
  -- step 1: let the game pick the item, the same way a right-click in the bags does (the form stays invisible until it is placed)
  for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do if AH[k] and AH[k].SetAlpha then AH[k]:SetAlpha(0) end end
  C_Timer.After(0.05, function()
    if not gameMode then return end
    local ok, err = pcall(function()
      if AH.SetPostItem then AH:SetPostItem(info.loc)
      else
        local modes = _G.AuctionHouseFrameDisplayMode
        local mode = modes and (info.isC and modes.CommoditiesSell or modes.ItemSell)
        if AH.SetDisplayMode and mode then AH:SetDisplayMode(mode) end
      end
    end)
    if not ok then CP.RecordError("game sell form", err) SetStatus("Could not open the game's sell form. See /pf errors.") Sl.FromGameSell() return end
    -- whichever sell form the game just opened is the one to bring in
    local f
    for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
      if AH[k] and AH[k].IsShown and AH[k]:IsShown() then f = AH[k] break end
    end
    if not f then
      local modes = _G.AuctionHouseFrameDisplayMode
      local mode = modes and (info.isC and modes.CommoditiesSell or modes.ItemSell)
      if AH.SetDisplayMode and mode then pcall(AH.SetDisplayMode, AH, mode) end
      f = info.isC and AH.CommoditiesSellFrame or AH.ItemSellFrame
    end
    if not f then SetStatus("The game's sell form was not found.") Sl.FromGameSell() return end
    gameFrame = f
    savedPoints = {}
    for i = 1, f:GetNumPoints() do savedPoints[i] = { f:GetPoint(i) } end
    -- step 2: place the form inside this pane and fill it in
    C_Timer.After(0.25, function()
      if not gameMode then return end
      pcall(function()
        -- if the game did not take the item, hand it over directly
        local have = f.GetItem and f:GetItem()
        if not have and f.SetItem then f:SetItem(info.loc) end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", W.rp, "TOPLEFT", 6, -6)
        f:SetFrameLevel((W.rp:GetFrameLevel() or 1) + 60)
        f:Show()
        f:SetAlpha(1)
      end)
      C_Timer.After(0.15, function()
        if not gameMode then return end
        pcall(function()
          if f.PriceInput and f.PriceInput.SetAmount then f.PriceInput:SetAmount(info.price) end
          if f.QuantityInput and f.QuantityInput.SetQuantity then f.QuantityInput:SetQuantity(info.qty) end
          if f.DurationDropDown and f.DurationDropDown.SetSelectedValue then f.DurationDropDown:SetSelectedValue(info.dur) end
        end)
        -- shrink the form until all of it (down to Create Auction and Buyout Mode) fits inside the pane
        pcall(function()
          f:SetScale(1)
          f:ClearAllPoints()
          f:SetPoint("TOPLEFT", W.rp, "TOPLEFT", 6, -6)
          local top, left, right = f:GetTop(), f:GetLeft(), f:GetRight()
          local low = top
          local cb = f.BuyoutModeCheckButton
          if cb and cb.GetNumPoints then
            if not cbPoints then cbPoints = {} for i = 1, cb:GetNumPoints() do cbPoints[i] = { cb:GetPoint(i) } end cbOwner = cb end
            cb:ClearAllPoints()
            cb:SetPoint("BOTTOMLEFT", W.rp, "BOTTOMLEFT", 14, 8)
          end
          local pb = f.PostButton
          if not pb then
            for _, c in ipairs({ f:GetChildren() }) do
              local t = c.GetText and c:GetText()
              if c.GetObjectType and c:GetObjectType() == "Button" and type(t) == "string" and t:lower():find("create") then pb = c break end
            end
          end
          if pb and pb.GetNumPoints then
            if not pbPoints then pbPoints = {} for i = 1, pb:GetNumPoints() do pbPoints[i] = { pb:GetPoint(i) } end pbOwner = pb end
            pb:ClearAllPoints()
            pb:SetPoint("BOTTOMRIGHT", W.rp, "BOTTOMRIGHT", -12, 36)
          end
          for _, k in ipairs({ "TotalPrice", "Deposit" }) do
            local c = f[k]
            if c and c.GetBottom and c:GetBottom() and c:GetBottom() < low then low = c:GetBottom() end
          end
          local needH, needW = (top - low) + 16, math.max(right - left, 1)
          local availH, availW = W.rp:GetHeight() - 12, W.rp:GetWidth() - 12
          local sc = math.min(1, availH / needH, availW / needW)
          if sc < 1 then
            f:SetScale(sc)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", W.rp, "TOPLEFT", 6 / sc, -6 / sc)
          end
        end)
        SetStatus("Press Create Auction in the form.")
      end)
    end)
  end)
end

local function PostNext()
  if not queue then return end
  local e
  ScanBags()
  for _, it in ipairs(items) do if it.id == queue.id then e = it break end end
  if not e then SetStatus("Posted " .. queue.done .. " of " .. queue.total .. ". The rest is gone from your bags.") queue = nil Sl.Draw() return end
  local qty = queue.sizes[queue.done + 1]
  if not qty then queue = nil Sl.Draw() return end
  local isC, loc = Commodity(e)
  if not loc then SetStatus("Could not find the item in your bags.") queue = nil Sl.Draw() return end
  forbidden = nil
  local ok, err
  if not S().postBlocked then
    if queue.confirm then
      -- second click: the game asked for a confirmation of this post
      queue.confirm = nil
      if isC then ok, err = pcall(C_AuctionHouse.ConfirmPostCommodity, loc, queue.dur, math.min(qty, e.count), queue.price)
      else ok, err = pcall(C_AuctionHouse.ConfirmPostItem, loc, queue.dur, 1, nil, queue.price) end
      err = nil
    elseif isC then ok, err = pcall(C_AuctionHouse.PostCommodity, loc, queue.dur, math.min(qty, e.count), queue.price)
    else ok, err = pcall(C_AuctionHouse.PostItem, loc, queue.dur, 1, nil, queue.price) end
    if ok and err == true and not forbidden then
      queue.confirm = true
      SetStatus("The game wants a confirmation. Click the button again.")
      W.post:SetText("Confirm post")
      W.post:Enable()
      return
    end
  end
  if S().postBlocked or forbidden then
    -- the game does not let add-ons post by themselves: hand the item and price to the game's own Sell tab
    S().postBlocked = true
    local maxStack = (C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(e.id)) or select(8, GetItemInfo(e.id)) or 1
    local info = { loc = loc, isC = isC, qty = (isC and maxStack > 1) and math.min(qty, e.count) or 1, price = queue.price, dur = queue.dur }
    queue = nil
    Sl.ToGameSell(info)
    Sl.Draw()
    return
  end
  if not ok then
    CP.RecordError("post auction", err)
    SetStatus("Could not post. See /pf errors.")
    queue = nil
    Sl.Draw()
    return
  end
  SetStatus("Posting " .. (queue.done + 1) .. " of " .. queue.total .. "...")
end

local function Post()
  local e = Selected()
  if not e then return end
  if queue and queue.confirm then PostNext() return end
  if queue then return end
  local price = H.ParseMoney(W.price:GetText())
  if not price or price <= 0 then SetStatus("Enter a price.") return end
  local sizes = Sizes(e)
  queue = { id = e.id, sizes = sizes, price = price, dur = DURATIONS[DurIdx()][1], done = 0, total = #sizes }
  Sl.Draw()
  PostNext()
end

local function Bump(box, delta, min, max)
  local v = tonumber(box:GetText()) or 0
  box:SetText(tostring(math.max(min, math.min(max, v + delta))))
end

function Sl.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  Sl.pane = pane
  local leftW = 290
  local ph = h - 12
  local ROWS = math.max(8, math.floor((ph - 66) / 20))

  W.accentLine = pane:CreateTexture(nil, "ARTWORK")
  W.accentLine:SetPoint("TOPLEFT", 0, -3)
  W.accentLine:SetPoint("TOPRIGHT", 0, -3)
  W.accentLine:SetHeight(2)
  W.lp = H.Panel(pane, leftW + 8, ph)
  W.lp:SetPoint("TOPLEFT", 0, -6)
  W.rp = H.Panel(pane, w - leftW - 12, ph)
  W.rp:SetPoint("TOPRIGHT", 0, -6)

  -- left: your bags
  local t = H.Text(W.lp, "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9)
  t:SetText("Your bags")
  W.listCount = H.Text(W.lp, "GameFontDisableSmall")
  W.listCount:SetPoint("TOPRIGHT", -10, -11)
  local search = H.Edit(pane, leftW - 70)
  search:SetNumeric(false)
  search:SetPoint("TOPLEFT", 14, -34)
  search:SetScript("OnTextChanged", function(self) filter = self:GetText() or "" listf.offset = 0 Sl.Draw() end)
  W.sortBtn = H.Button(pane, "Value", 54, 20)
  W.sortBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
  W.sortBtn:SetScript("OnClick", function() sortMode = sortMode == "worth" and "name" or "worth" Sl.Draw() end)
  local lf = CreateFrame("Frame", nil, pane)
  lf:SetPoint("TOPLEFT", 4, -62)
  lf:SetSize(leftW, ROWS * 20)
  listf = H.RowList(lf, ROWS, 20, function(r, i)
    r.iconEdge = r:CreateTexture(nil, "ARTWORK") r.iconEdge:SetSize(20, 20) r.iconEdge:SetPoint("LEFT", 2, 0)
    r.icon = r:CreateTexture(nil, "OVERLAY") r.icon:SetSize(18, 18) r.icon:SetPoint("LEFT", 3, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = H.Text(r) r.name:SetPoint("LEFT", 28, 0) r.name:SetWidth(138) r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.count = H.Text(r) r.count:SetPoint("LEFT", 170, 0) r.count:SetWidth(36) r.count:SetJustifyH("LEFT")
    r.worth = H.Text(r) r.worth:SetPoint("RIGHT", -6, 0) r.worth:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self) if self.e then Pick(self.e) end end)
    local old = r:GetScript("OnEnter")
    r:SetScript("OnEnter", function(self)
      if old then old(self) end
      if self.e and self.e.link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.e.link)
        GameTooltip:Show()
      end
    end)
    local oldL = r:GetScript("OnLeave")
    r:SetScript("OnLeave", function(self) if oldL then oldL(self) end GameTooltip:Hide() end)
  end)
  listf.refresh = Sl.Draw

  -- right: everything about the selected item. Text sits on an overlay so the panels can't cover it.
  local rx = leftW + 28
  local RW = w - rx - 14
  local ov = CreateFrame("Frame", nil, pane)
  ov:SetAllPoints(pane)
  W.ov = ov

  W.iconEdge = ov:CreateTexture(nil, "ARTWORK")
  W.iconEdge:SetSize(46, 46)
  W.iconEdge:SetPoint("TOPLEFT", rx - 2, -11)
  W.icon = ov:CreateTexture(nil, "OVERLAY")
  W.icon:SetSize(42, 42)
  W.icon:SetPoint("CENTER", W.iconEdge, "CENTER")
  W.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  W.head = H.Text(ov, "GameFontNormalLarge")
  W.head:SetPoint("TOPLEFT", rx + 54, -13)
  W.head:SetWidth(RW - 54)
  W.head:SetJustifyH("LEFT")
  W.sub = H.Text(ov)
  W.sub:SetPoint("TOPLEFT", rx + 54, -37)

  -- three market boxes
  local bw = math.floor((RW - 16) / 3)
  local function MakeBox(i, y)
    local b = H.Panel(ov, bw, 34)
    b:SetPoint("TOPLEFT", ov, "TOPLEFT", rx + (i - 1) * (bw + 8), y)
    b.l = H.Text(b, "GameFontDisableSmall") b.l:SetPoint("TOPLEFT", 8, -4)
    b.v = H.Text(b, "GameFontHighlight") b.v:SetPoint("BOTTOMLEFT", 8, 4)
    return b
  end
  W.box1, W.box2, W.box3 = MakeBox(1, -62), MakeBox(2, -62), MakeBox(3, -62)

  local function Label(txt, x, y)
    local fs = H.Text(ov, "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(txt)
    return fs
  end

  -- price + quick buttons
  Label("Price each  (like 1g 30s 5c)", rx, -102)
  W.price = H.Edit(ov, 130)
  W.price:SetPoint("TOPLEFT", rx + 4, -117)
  W.price:SetMaxLetters(24)
  W.price:SetScript("OnTextChanged", function(_, user) if user then Sl.Draw() end end)
  local bx = rx + 146
  local function Quick(label, width, fn)
    local b = H.Button(ov, label, width, 22)
    b:SetPoint("TOPLEFT", ov, "TOPLEFT", bx, -116)
    bx = bx + width + 4
    b:SetScript("OnClick", fn)
    return b
  end
  Quick("Suggested", 76, function() local e = Selected() if e then UsePrice(Suggest(e)) end end)
  Quick("Match low", 70, function() local e = Selected() local p = e and CP.db.prices[e.id] if p and p.min then UsePrice(p.min) end end)
  Quick("Reference", 70, function() local e = Selected() local p = e and CP.db.prices[e.id] if p and p.ref then UsePrice(p.ref) end end)
  Quick("-5%", 40, function() local v = H.ParseMoney(W.price:GetText()) if v then UsePrice(v * 0.95) end end)
  W.sug = H.Text(ov)
  W.sug:SetPoint("TOPLEFT", rx + 4, -141)

  -- undercut settings, kept between sessions
  Label("Undercut", rx, -158)
  W.umode = H.Button(ov, "copper", 70, 22)
  W.umode:SetPoint("TOPLEFT", rx, -172)
  W.umode:SetScript("OnClick", function()
    S().undercutMode = S().undercutMode == "percent" and "copper" or "percent"
    W.uval:SetText(tostring(S().undercutMode == "percent" and (S().undercutPct or 1) or (S().undercut or 1)))
    local e = Selected() if e then UsePrice(Suggest(e)) end
    Sl.Draw()
  end)
  W.uval = H.Edit(ov, 50)
  W.uval:SetNumeric(false)
  W.uval:SetPoint("LEFT", W.umode, "RIGHT", 10, 0)
  W.uval:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local v = tonumber(self:GetText())
    if not v then return end
    if S().undercutMode == "percent" then S().undercutPct = math.max(0, math.min(90, v)) else S().undercut = math.max(0, v) end
    local e = Selected() if e then UsePrice(Suggest(e)) end
  end)
  Label("Based on", rx + 150, -158)
  W.base = H.Button(ov, "Lowest", 90, 22)
  W.base:SetPoint("TOPLEFT", rx + 146, -172)
  W.base:SetScript("OnClick", function()
    S().sellBase = S().sellBase == "ref" and "low" or "ref"
    local e = Selected() if e then UsePrice(Suggest(e)) end
    Sl.Draw()
  end)
  Label("Duration", rx + 250, -158)
  W.dur = H.Button(ov, "24 hours", 100, 22)
  W.dur:SetPoint("TOPLEFT", rx + 246, -172)
  W.dur:SetScript("OnClick", function() S().sellDuration = DurIdx() % #DURATIONS + 1 Sl.Draw() end)

  -- stacks
  W.sizeLabel = Label("Stack size", rx, -200)
  W.size = H.Edit(ov, 60, true)
  W.size:SetPoint("TOPLEFT", rx + 4, -214)
  W.size:SetScript("OnTextChanged", function(_, user) if user then Sl.Draw() end end)
  Label("Auctions", rx + 90, -200)
  W.stacks = H.Edit(ov, 50, true)
  W.stacks:SetPoint("TOPLEFT", rx + 94, -214)
  W.stacks:SetScript("OnTextChanged", function(_, user) if user then Sl.Draw() end end)
  W.all = H.Button(ov, "Everything", 80, 22)
  W.all:SetPoint("TOPLEFT", rx + 160, -213)
  W.all:SetScript("OnClick", function()
    local e = Selected() if not e then return end
    local size = math.max(1, tonumber(W.size:GetText()) or e.count)
    W.stacks:SetText(tostring(math.ceil(e.count / size)))
    Sl.Draw()
  end)

  -- summary
  W.sum = H.Panel(ov, RW, 86)
  W.sum:SetPoint("TOPLEFT", ov, "TOPLEFT", rx, -240)
  W.sumL = H.Text(W.sum, "GameFontHighlightSmall")
  W.sumL:SetPoint("TOPLEFT", 10, -7)
  W.sumL:SetJustifyH("LEFT")
  W.sumL:SetSpacing(2)
  W.sumR = H.Text(W.sum, "GameFontHighlightSmall")
  W.sumR:SetPoint("TOPRIGHT", -10, -7)
  W.sumR:SetJustifyH("RIGHT")
  W.sumR:SetSpacing(2)
  W.be = H.Text(ov)
  W.be:SetPoint("TOPLEFT", W.sum, "BOTTOMLEFT", 2, -22)
  W.be:SetWidth(RW - 250)
  W.be:SetJustifyV("TOP")
  if W.be.SetWordWrap then W.be:SetWordWrap(false) end
  W.be:SetJustifyH("LEFT")
  W.verdict = H.Text(ov)
  W.verdict:SetPoint("TOPLEFT", W.sum, "BOTTOMLEFT", 2, -5)

  W.status = H.Text(ov)
  W.status:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", -12, 50)
  W.status:SetWidth(190)
  W.status:SetJustifyH("RIGHT")

  W.post = H.Button(ov, "Post auction", 140, 28)
  W.post:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", -12, 6)
  W.post:SetScript("OnClick", Post)
  local fnt = W.post:GetFontString() if fnt and fnt.SetFontObject then fnt:SetFontObject("GameFontNormalLarge") end
  local refresh = H.Button(ov, "Refresh bags", 80, 22)
  refresh:SetPoint("RIGHT", W.post, "LEFT", -6, 0)
  refresh:SetScript("OnClick", function() ScanBags() Sl.Draw() end)

  W.back = H.Button(pane, "Back to prices", 120, 22)
  W.back:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -14, 8)
  W.back:SetFrameLevel((W.rp:GetFrameLevel() or 1) + 200)
  W.back:SetScript("OnClick", Sl.FromGameSell)
  W.back:Hide()

  pane:SetScript("OnHide", function() Sl.FromGameSell() end)
  pane:SetScript("OnShow", function()
    W.uval:SetText(tostring(S().undercutMode == "percent" and (S().undercutPct or 1) or (S().undercut or 1)))
    ScanBags()
    Sl.Draw()
  end)
  return pane
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do ev:RegisterEvent(e) end
pcall(ev.RegisterEvent, ev, "AUCTION_HOUSE_POST_ERROR")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(ev.RegisterEvent, ev, "UI_ERROR_MESSAGE")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:SetScript("OnEvent", CP.Safe("selling-event", function(_, event, a1, a2)
  if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    if a1 == ADDON then
      forbidden = tostring(a2 or "?")
      print("|cffff6060Profiteer: the game blocked " .. tostring(a2 or "an action") .. " (" .. event .. ")|r")
      SetStatus("The game blocked " .. tostring(a2 or "an action") .. ".")
    end
    return
  end
  if not pane or not pane:IsShown() then return end
  if event == "AUCTION_HOUSE_AUCTION_CREATED" and queue then
    queue.done = queue.done + 1
    if queue.done >= queue.total then
      SetStatus("Posted " .. queue.total .. (queue.total == 1 and " auction." or " auctions."))
      queue = nil
    else
      SetStatus("Posted " .. queue.done .. " of " .. queue.total .. "...")
      C_Timer.After(0.4, CP.Safe("selling-next", PostNext))
    end
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    if gameMode then Sl.FromGameSell() end
    SetStatus("Posted.")
  elseif event == "UI_ERROR_MESSAGE" then
    if gameMode then
      CP:Print("Game message " .. tostring(a1) .. ": " .. tostring(a2))
      pcall(function()
        local f = gameFrame
        local it = f and f.GetItem and f:GetItem()
        local link = it and C_Item and C_Item.GetItemLink and C_Item.GetItemLink(it)
        local bag, slot = it and it.GetBagAndSlot and it:GetBagAndSlot()
        CP.db.postDebug = { t = time(), msg = tostring(a2), id = a1, link = link, bag = bag, slot = slot,
          shown = f and (f == _G.AuctionHouseFrame.CommoditiesSellFrame and "commodity" or "item"),
          qty = f and f.QuantityInput and f.QuantityInput.GetQuantity and f.QuantityInput:GetQuantity(),
          price = f and f.PriceInput and f.PriceInput.GetAmount and f.PriceInput:GetAmount(),
          dur = f and f.DurationDropDown and f.DurationDropDown.GetSelectedValue and f.DurationDropDown:GetSelectedValue(),
          bound = it and C_Item and C_Item.IsBound and C_Item.IsBound(it),
          stack = link and select(8, GetItemInfo(link)) }
      end)
    end
    return
  elseif event == "AUCTION_HOUSE_POST_ERROR" and gameMode and gameFrame then
    local it = gameFrame.GetItem and gameFrame:GetItem()
    local q = gameFrame.QuantityInput and gameFrame.QuantityInput.GetQuantity and gameFrame.QuantityInput:GetQuantity()
    local pr = gameFrame.PriceInput and gameFrame.PriceInput.GetAmount and gameFrame.PriceInput:GetAmount()
    CP:Print("The game refused the post (error " .. tostring(a1) .. "). Item set: " .. tostring(it ~= nil) .. ", quantity " .. tostring(q) .. ", price " .. tostring(pr) .. ".")
    SetStatus("The auction house refused the post.")
  elseif event == "AUCTION_HOUSE_POST_ERROR" and queue then
    SetStatus("The auction house refused the post. Stopped after " .. queue.done .. " of " .. queue.total .. ".")
    queue = nil
  end
  if event == "GET_ITEM_INFO_RECEIVED" then Sl.Draw() return end
  if event ~= "AUCTION_HOUSE_POST_ERROR" then ScanBags() end
  Sl.Draw()
end))
