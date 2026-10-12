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
local gameQ   -- the rest of a multi-item batch while the game's own form is borrowed
local gameMode, gameFrame, savedPoints   -- the game's own sell form shown inside this pane
local nativeSellMode
local gamePostInfo
local gamePosting
local CapturePostDebug
local TracePostDebug
local TraceNativePostState
local EndNativeSellObservation
local postAPIHookStatus = {}
local postThrottleOverlay
local postThrottleWatchPending
local postButtonOriginalOnClick
local postClickBlocked
local forbidden        -- set when the game says an add-on may not call a function
local queue            -- { id, sizes = {..}, price, dur, done, total }
local DURATIONS = { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }

local function S() return CP.db.settings end
local function SetStatus(t) if W.status then W.status:SetText(t or "") end end
local function DurIdx() return math.max(1, math.min(3, tonumber(S().sellDuration) or 2)) end
local function PostThrottleReady()
  if not (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) then return true end
  local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
  return ok and ready == true
end
local function UpdatePostThrottleGuard()
  if not postThrottleOverlay then return end
  if (not gameMode and not nativeSellMode) or gamePosting then
    postThrottleOverlay:Hide()
    return
  end
  if nativeSellMode and gameFrame then
    local button = gameFrame.PostButton
    local allowed
    local reason
    if type(gameFrame.CanPostItem) == "function" then
      local ok, value, why = pcall(gameFrame.CanPostItem, gameFrame)
      if ok then allowed, reason = value, why end
    end
    local ready = PostThrottleReady()
    if button then
      if not ready and button.IsEnabled and button:IsEnabled() then
        button.pfThrottleDisabledByProfiteer = true
        if button.Disable then button:Disable() end
        if TracePostDebug then
          TracePostDebug("Native throttle guard blocked Create", "ready=" .. tostring(ready),
            "canPost=" .. tostring(allowed), "reason=" .. tostring(reason))
        end
      elseif ready and button.pfThrottleDisabledByProfiteer and allowed == true then
        button.pfThrottleDisabledByProfiteer = false
        if button.Enable then button:Enable() end
        if TracePostDebug then TracePostDebug("Native throttle guard released Create") end
      end
    end
    if ready and not (button and button.pfThrottleDisabledByProfiteer) then
      postThrottleOverlay:Hide()
    else
      postThrottleOverlay:Show()
    end
    return
  end
  if PostThrottleReady() then postThrottleOverlay:Hide() else postThrottleOverlay:Show() end
end
local function WatchPostThrottle()
  if (not gameMode and not nativeSellMode) or not postThrottleOverlay or postThrottleWatchPending then return end
  postThrottleWatchPending = true
  C_Timer.After(0.25, function()
    postThrottleWatchPending = false
    if (not gameMode and not nativeSellMode) or not postThrottleOverlay then return end
    UpdatePostThrottleGuard()
    if postThrottleOverlay:IsShown() then WatchPostThrottle() end
  end)
end
local function AttachPostThrottleGuard(frame)
  local button = frame and frame.PostButton
  if not button then return end
  if not frame.pfNativeThrottleClickHooked and button.HookScript then
    frame.pfNativeThrottleClickHooked = true
    button:HookScript("PreClick", function()
      if not nativeSellMode or gameFrame ~= frame then return end
      gamePosting = true
      CP.db.postDebug = { trace = {}, traceStarted = GetTime and GetTime() or time() }
      local function Value(control, methodName)
        local method = control and control[methodName]
        if type(method) ~= "function" then return nil end
        local ok, value = pcall(method, control)
        if ok then return value end
      end
      TracePostDebug("Native pre-click values",
        "prefilledQuantity=" .. tostring(gamePostInfo.qty),
        "formQuantity=" .. tostring(Value(frame.QuantityInput, "GetQuantity")),
        "prefilledPrice=" .. tostring(gamePostInfo.price),
        "formPrice=" .. tostring(Value(frame.PriceInput, "GetAmount")),
        "prefilledDuration=" .. tostring(gamePostInfo.dur),
        "formDuration=" .. tostring(Value(frame.Duration, "GetDuration")),
        "throttledReady=" .. tostring(PostThrottleReady()))
      TracePostDebug("POST_BUTTON_PRECLICK")
      TraceNativePostState("Native form before Create")
      TracePostDebug("Post API hooks", "PostItem=" .. tostring(postAPIHookStatus.PostItem),
        "PostCommodity=" .. tostring(postAPIHookStatus.PostCommodity))
      CapturePostDebug("POST_BUTTON_CLICK")
      local submitted = gamePostInfo
      C_Timer.After(30, function()
        if not (nativeSellMode and gamePosting and gamePostInfo == submitted) then return end
        TracePostDebug("POST_RESULT_TIMEOUT")
        CapturePostDebug("POST_RESULT_TIMEOUT")
        EndNativeSellObservation()
        CP:Print("No auction result was received from the native Sell page. Type /pf postdebug for details.")
      end)
    end)
  end
  local parent = button:GetParent()
  if not postThrottleOverlay then
    postThrottleOverlay = CreateFrame("Frame", nil, parent)
    postThrottleOverlay:EnableMouse(true)
    local function ExplainThrottleWait()
      SetStatus("Auction House is processing requests. Wait for the Create button to unlock.")
    end
    postThrottleOverlay:SetScript("OnMouseDown", ExplainThrottleWait)
    postThrottleOverlay:SetScript("OnMouseUp", ExplainThrottleWait)
    local shade = postThrottleOverlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.12, 0.12, 0.14, 0.9)
    local label = postThrottleOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("Please wait...")
  elseif postThrottleOverlay:GetParent() ~= parent then
    postThrottleOverlay:SetParent(parent)
  end
  postThrottleOverlay:ClearAllPoints()
  postThrottleOverlay:SetAllPoints(button)
  postThrottleOverlay:SetFrameStrata(button:GetFrameStrata())
  postThrottleOverlay:SetFrameLevel(button:GetFrameLevel() + 5)
  UpdatePostThrottleGuard()
  WatchPostThrottle()
end

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

local function MaxStackSize(id)
  local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
  if type(size) ~= "number" then size = GetItemInfo and select(8, GetItemInfo(id)) end
  return tonumber(size) or 1
end

local function Commodity(e)
  local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(e.bag, e.slot)
  if not loc then return false end
  local ok, key = pcall(C_AuctionHouse.GetItemKeyFromItem, loc)
  if ok and key and C_AuctionHouse.GetItemCommodityStatus then
    local ok2, st = pcall(C_AuctionHouse.GetItemCommodityStatus, key)
    if ok2 then return st == (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2), loc end
  end
  return (e.count or 1) > 1 and MaxStackSize(e.id) > 1, loc
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

-- fallback when Profiteer's direct post API is unavailable: embed the game's Sell form in this pane
gameMode, gameFrame, savedPoints = false, nil, nil

local cbOwner, cbPoints, pbOwner, pbPoints
-- the form's own gray panel and frame art are faded while it sits in our pane (our dark pane is the background); put back afterwards
local faded = {}
local function FadeFormArt(f)
  local function Fade(o)
    if o and o.SetAlpha and faded[o] == nil then faded[o] = o:GetAlpha() or 1 o:SetAlpha(0) end
  end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then Fade(r) end
  end
  Fade(f.NineSlice) Fade(f.Background) Fade(f.Bg) Fade(f.Inset) Fade(f.TopBorder)
  for _, c in ipairs({ f:GetChildren() }) do
    local n = c.GetName and c:GetName() or ""
    if c ~= f.PostButton and (n:find("Inset") or n:find("Border") or n:find("NineSlice") or c == f.NineSlice) then Fade(c) end
  end
end
local function RestoreFormArt()
  for o, a in pairs(faded) do pcall(o.SetAlpha, o, a) faded[o] = nil end
end
-- the game re-opens its own sell form now and then; while one of our tabs is up (and we are not borrowing it) it goes straight back
function Sl.KeepGameFormAway()
  local AH = _G.AuctionHouseFrame
  if not (AH and CP.AHTab and CP.AHTab.Current and CP.AHTab.Current()) then return end
  -- the game's own lists (its auctions / prices on the right) never belong behind our pane, even while its form is borrowed
  for _, k in ipairs({ "ItemSellList", "CommoditiesSellList", "ItemBuyFrame", "CommoditiesBuyFrame", "AuctionsFrame" }) do
    local f = AH[k]
    if f and f.IsShown and f:IsShown() then pcall(f.Hide, f) end
  end
  if gameMode then return end
  for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local f = AH[k]
    if f and f.IsShown and f:IsShown() then pcall(f.Hide, f) end
  end
end
function Sl.FromGameSell()
  if not gameMode then return end
  gameMode = false
  gamePostInfo = nil
  gamePosting = false
  if postThrottleOverlay then postThrottleOverlay:Hide() end
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
  RestoreFormArt()
  if CP.After then CP.After(0.05, Sl.KeepGameFormAway) CP.After(0.4, Sl.KeepGameFormAway) end
  if W.ov then W.ov:Show() end
  if W.back then W.back:Hide() end
  Sl.Draw()
end

local function ToEmbeddedGameSell(info)
  local AH = _G.AuctionHouseFrame
  if not AH then return end
  gameMode = true
  gamePostInfo = info
  if W.ov then W.ov:Hide() end
  W.back:Show()
  SetStatus("Opening the game's sell form...")
  -- step 1: let the game pick the item, the same way a right-click in the bags does (the form stays invisible until it is placed)
  for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do if AH[k] and AH[k].SetAlpha then AH[k]:SetAlpha(0) end end
  C_Timer.After(0.02, function()
    if not gameMode then return end
    local ok, err = pcall(function()
      if AH.SetPostItem then
        -- hand the game an item location it made itself (the same one a drag from the bags gives it)
        local used = false
        local bag, slot = info.loc and info.loc.GetBagAndSlot and info.loc:GetBagAndSlot()
        if bag and slot and C_Container and C_Container.PickupContainerItem and C_Cursor and C_Cursor.GetCursorItem then
          ClearCursor()
          pcall(C_Container.PickupContainerItem, bag, slot)
          local cl = C_Cursor.GetCursorItem()
          if cl then used = pcall(AH.SetPostItem, AH, cl) end
          ClearCursor()
        end
        if not used then AH:SetPostItem(info.loc) end
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
    if TracePostDebug and f.CachePendingPost and not f.pfPostDebugHooked then
      f.pfPostDebugHooked = true
      local ok, err = pcall(hooksecurefunc, f, "CachePendingPost", function(_, ...)
        TracePostDebug("CachePendingPost", ...)
      end)
      if not ok then
        f.pfPostDebugHooked = false
        CP.RecordError("hook pending auction post", err)
      end
    end
    for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame", "ItemSellList", "CommoditiesSellList", "ItemBuyFrame", "CommoditiesBuyFrame" }) do
      local g = AH[k]
      if g and g.HookScript and not g.pfAway then
        g.pfAway = true
        g:HookScript("OnShow", function() if CP.After then CP.After(0, Sl.KeepGameFormAway) end end)
      end
    end
    for _, d in ipairs({ 0, 0.1, 0.3, 0.8 }) do CP.After(d, Sl.KeepGameFormAway) end
    savedPoints = {}
    for i = 1, f:GetNumPoints() do savedPoints[i] = { f:GetPoint(i) } end
    -- step 2: place the form inside this pane, lay it out and fill it in while it is still invisible, then show it once, finished
    local function Layout()
      pcall(function()
        FadeFormArt(f)
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
          if not postThrottleOverlay then
            postThrottleOverlay = CreateFrame("Frame", nil, pb:GetParent())
            postThrottleOverlay:SetFrameStrata(pb:GetFrameStrata())
            postThrottleOverlay:SetFrameLevel(pb:GetFrameLevel() + 5)
            postThrottleOverlay:EnableMouse(true)
            local function ExplainThrottleWait()
              SetStatus("Auction House is processing requests. Wait for the Create button to unlock.")
            end
            postThrottleOverlay:SetScript("OnMouseDown", ExplainThrottleWait)
            postThrottleOverlay:SetScript("OnMouseUp", ExplainThrottleWait)
            local shade = postThrottleOverlay:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints()
            shade:SetColorTexture(0.12, 0.12, 0.14, 0.9)
            local label = postThrottleOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER")
            label:SetText("Please wait...")
          end
          postThrottleOverlay:ClearAllPoints()
          postThrottleOverlay:SetAllPoints(pb)
          postThrottleOverlay:SetFrameStrata(pb:GetFrameStrata())
          postThrottleOverlay:SetFrameLevel(pb:GetFrameLevel() + 5)
          UpdatePostThrottleGuard()
          WatchPostThrottle()
          if not pb.pfHooked then
            pb.pfHooked = true
            postButtonOriginalOnClick = pb:GetScript("OnClick")
            pb:SetScript("OnClick", function(button, ...)
              if postClickBlocked then
                postClickBlocked = false
                return
              end
              if gameMode and not PostThrottleReady() then
                postClickBlocked = true
                CP.db.postDebug = { trace = {}, traceStarted = GetTime and GetTime() or time() }
                TracePostDebug("POST_BLOCKED_THROTTLED")
                CapturePostDebug("POST_BLOCKED_THROTTLED")
                SetStatus("Auction House is processing requests. Wait for the Create button to unlock.")
                UpdatePostThrottleGuard()
                WatchPostThrottle()
                postClickBlocked = false
                return
              end
              if postButtonOriginalOnClick then postButtonOriginalOnClick(button, ...) end
            end)
            pb:HookScript("PreClick", function()
              if gameMode and gameFrame then
                if not PostThrottleReady() then
                  postClickBlocked = true
                  CP.db.postDebug = { trace = {}, traceStarted = GetTime and GetTime() or time() }
                  TracePostDebug("POST_BLOCKED_THROTTLED")
                  CapturePostDebug("POST_BLOCKED_THROTTLED")
                  SetStatus("Auction House is processing requests. Wait for the Create button to unlock.")
                  UpdatePostThrottleGuard()
                  return
                end
                postClickBlocked = false
                gamePosting = true
                CP.db.postDebug = { trace = {}, traceStarted = GetTime and GetTime() or time() }
                TracePostDebug("POST_BUTTON_PRECLICK")
                TraceNativePostState("Native form before PostItem")
                TracePostDebug("Post API hooks", "PostItem=" .. tostring(postAPIHookStatus.PostItem),
                  "PostCommodity=" .. tostring(postAPIHookStatus.PostCommodity))
                TracePostDebug("Pending-post cache hook", tostring(gameFrame and gameFrame.pfPostDebugHooked))
                CapturePostDebug("POST_BUTTON_CLICK")
                local submitted = gamePostInfo
                C_Timer.After(30, function()
                  if not (gameMode and gamePosting and gamePostInfo == submitted) then return end
                  TracePostDebug("POST_RESULT_TIMEOUT")
                  CapturePostDebug("POST_RESULT_TIMEOUT")
                  gameQ = nil
                  Sl.FromGameSell()
                  SetStatus("No auction result received. Returned to Selling; type /pf postdebug for details.")
                end)
              end
            end)
            pb:HookScript("PostClick", function()
              if gameMode and gameFrame then
                TracePostDebug("POST_BUTTON_POSTCLICK")
                TraceNativePostState("Native form after PostItem")
                CapturePostDebug("POST_BUTTON_RESULT")
                if gameFrame.pendingPost == nil then
                  TracePostDebug("POST_API_REJECTED_WITHOUT_PENDING_POST")
                  CapturePostDebug("POST_API_REJECTED")
                  gamePosting = false
                  local submittedInfo = gamePostInfo
                  local attempts = 0
                  local function RestoreRejectedPost()
                    if not gameMode or gamePostInfo ~= submittedInfo then return end
                    attempts = attempts + 1
                    if PostThrottleReady() then
                      local ok, err = pcall(function()
                        if gameFrame.GetItem and gameFrame:GetItem() == nil and gameFrame.SetItem then
                          gameFrame:SetItem(submittedInfo.loc)
                        end
                        if gameFrame.PriceInput and gameFrame.PriceInput.SetAmount then
                          gameFrame.PriceInput:SetAmount(submittedInfo.price)
                        end
                        if gameFrame.QuantityInput and gameFrame.QuantityInput.SetQuantity then
                          gameFrame.QuantityInput:SetQuantity(submittedInfo.qty)
                        end
                        if gameFrame.Duration and gameFrame.Duration.SetDuration then
                          gameFrame.Duration:SetDuration(submittedInfo.dur)
                        end
                      end)
                      if not ok then CP.RecordError("restore rejected auction form", err) end
                      SetStatus("The game did not queue this post. The form is restored; wait for the AH to be ready, then retry.")
                      UpdatePostThrottleGuard()
                      WatchPostThrottle()
                    elseif attempts < 120 then
                      C_Timer.After(0.25, RestoreRejectedPost)
                    else
                      SetStatus("The game did not queue this post. Wait for the AH, then reselect the item.")
                    end
                  end
                  C_Timer.After(0.25, RestoreRejectedPost)
                else
                  SetStatus("Waiting for the auction result...")
                end
              end
            end)
          end
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
      pcall(function()
        -- single items are posted by buyout: without Buyout Mode the price typed in would only be a starting bid
        local bm = f.BuyoutModeCheckButton
        if bm and bm.GetChecked and not info.isC and not bm:GetChecked() and not info.bmSet then
          info.bmSet = true
          if bm.Click then bm:Click() else bm:SetChecked(true) end
        end
      end)
      pcall(function()
        if f.PriceInput and f.PriceInput.SetAmount then f.PriceInput:SetAmount(info.price) end
        if f.QuantityInput and f.QuantityInput.SetQuantity then f.QuantityInput:SetQuantity(info.qty) end
        if f.Duration and f.Duration.SetDuration then f.Duration:SetDuration(info.dur) end
      end)
    end
    C_Timer.After(0.1, function()
      if not gameMode then return end
      pcall(function()
        local have = f.GetItem and f:GetItem()
        if not have and f.SetItem then f:SetItem(info.loc) end
        f:SetFrameLevel((W.rp:GetFrameLevel() or 1) + 60)
        f:SetAlpha(0)
        f:Show()
      end)
      C_Timer.After(0.03, function()
        if not gameMode then return end
        Layout()
        C_Timer.After(0.1, function()
          if not gameMode then return end
          Layout()   -- once more: the form re-lays itself out when its prices arrive
          f:SetAlpha(1)
          if PostThrottleReady() then SetStatus("Press Create Auction in the form.")
          else SetStatus("Auction House is processing requests. Wait for the Create button to unlock.") end
          UpdatePostThrottleGuard()
          WatchPostThrottle()
        end)
      end)
    end)
  end)
end

EndNativeSellObservation = function()
  nativeSellMode = false
  gamePosting = false
  gamePostInfo = nil
  gameFrame = nil
  UpdatePostThrottleGuard()
end

function Sl.ToGameSell(info)
  local AH = _G.AuctionHouseFrame
  local modes = _G.AuctionHouseFrameDisplayMode
  if not (AH and modes and AH.SetDisplayMode) then
    CP:Print("Profiteer could not open the game's native Sell page.")
    return
  end

  if gameMode then Sl.FromGameSell() end
  if CP.AHTab and CP.AHTab.Leave then CP.AHTab.Leave() end
  if CP.AHTab and CP.AHTab.origH then pcall(AH.SetHeight, AH, CP.AHTab.origH) end
  for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
    local sellFrame = AH[key]
    if sellFrame and type(sellFrame.SetItem) == "function" then
      local cleared, clearErr = pcall(sellFrame.SetItem, sellFrame, nil, nil, false)
      if not cleared then
        CP.RecordError("clear native " .. key, clearErr)
        CP:Print("Profiteer could not clear the native Sell forms. See /pf errors.")
        return
      end
    end
  end
  if info.loc and type(info.loc.IsValid) == "function" then
    local valid, isValid = pcall(info.loc.IsValid, info.loc)
    if not valid or not isValid then
      CP:Print("The selected bag item is no longer available. Refresh your bags and try again.")
      return
    end
  end
  local displayMode = info.isC and modes.CommoditiesSell or modes.ItemSell
  local sellTab = _G.AuctionHouseFrameSellTab
  if sellTab and type(sellTab.Click) == "function" then
    local clicked, clickErr = pcall(sellTab.Click, sellTab)
    if not clicked then CP.RecordError("select native auction Sell tab", clickErr) end
  end
  local setMode, modeErr = pcall(AH.SetDisplayMode, AH, displayMode)
  if not setMode then
    CP.RecordError("open native auction sell page", modeErr)
    CP:Print("Profiteer could not switch to the game's Sell page. See /pf errors.")
    return
  end

  local frame = info.isC and AH.CommoditiesSellFrame or AH.ItemSellFrame
  if not frame then
    CP:Print("Profiteer could not find the native Sell form.")
    return
  end

  nativeSellMode = true
  gamePosting = false
  gamePostInfo = info
  gameFrame = frame
  CP.db.postDebug = { trace = {}, traceStarted = GetTime and GetTime() or time() }
  AttachPostThrottleGuard(frame)
  local function ApplyDefaultsAfterManualSelection()
    if not nativeSellMode or gamePostInfo ~= info or info.defaultsApplied then return end
    local selected = frame.GetItem and frame:GetItem()
    if not selected then return end
    if selected.IsValid then
      local ok, valid = pcall(selected.IsValid, selected)
      if not ok or not valid then return end
    end
    local applied, applyErr = pcall(function()
      if frame.PriceInput and frame.PriceInput.SetAmount then
        frame.PriceInput:SetAmount(info.price)
      end
      if frame.QuantityInput and frame.QuantityInput.SetQuantity then
        frame.QuantityInput:SetQuantity(info.qty)
      end
      if frame.Duration and frame.Duration.SetDuration then
        frame.Duration:SetDuration(info.dur)
      end
      local buyout = frame.BuyoutModeCheckButton
      if buyout and buyout.GetChecked and not info.isC and not buyout:GetChecked() then
        if buyout.Click then buyout:Click() else buyout:SetChecked(true) end
      end
    end)
    if not applied then
      CP.RecordError("fill native auction sell form", applyErr)
      CP:Print("The native Sell form has your item, but Profiteer couldn't fill all values. Check the form before posting; see /pf errors.")
      return
    end
    info.defaultsApplied = true
    TraceNativePostState("Native form ready")
    CapturePostDebug("NATIVE_SELL_FORM_READY")
    CP:Print("Profiteer filled the native Sell form. Review the price and settings, then click Create Auction.")
  end
  if frame.SetItem and hooksecurefunc and not frame.pfManualSellSelectionHooked then
    local hooked, hookErr = pcall(hooksecurefunc, frame, "SetItem", function()
      if nativeSellMode and gameFrame == frame then
        C_Timer.After(0.15, ApplyDefaultsAfterManualSelection)
      end
    end)
    if hooked then
      frame.pfManualSellSelectionHooked = true
    else
      CP.RecordError("watch native manual item selection", hookErr)
    end
  end
  TraceNativePostState("Native Sell page opened; awaiting manual item selection")
  CapturePostDebug("NATIVE_SELL_FORM_READY")
  CP:Print("Native Sell is open. Drag the selected item from your bags into the form; Profiteer will fill its price after selection.")
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
  local maxStack = MaxStackSize(e.id)
  local info = { id = e.id, loc = loc, isC = isC,
    qty = (isC and maxStack > 1) and math.min(qty, e.count) or 1,
    price = queue.price, dur = queue.dur }
  gameQ = (queue.total or 1) > 1 and queue or nil
  queue = nil
  Sl.ToGameSell(info)
  Sl.Draw()
  return
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

local function ControlValue(frame, controlName, methodName)
  local control = frame and frame[controlName]
  local method = control and control[methodName]
  if type(method) ~= "function" then return nil end
  local ok, value = pcall(method, control)
  if ok then return value end
end

local function AuctionDuration(frame)
  if frame and type(frame.GetDuration) == "function" then
    local ok, value = pcall(frame.GetDuration, frame)
    if ok then return value end
  end
  return ControlValue(frame, "Duration", "GetDuration")
end

local function DebugArg(value)
  if value == nil then return "nil" end
  if type(value) == "string" then return value:sub(1, 100) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if type(value) == "table" or type(value) == "userdata" then
    if value.GetBagAndSlot then
      local ok, bag, slot = pcall(value.GetBagAndSlot, value)
      if ok and bag then return tostring(value) .. " bag=" .. tostring(bag) .. " slot=" .. tostring(slot) end
    end
  end
  return tostring(value):sub(1, 100)
end

TraceNativePostState = function(label)
  local frame = gameFrame
  if not frame then return end
  local canPost, reason
  if type(frame.CanPostItem) == "function" then
    local ok, allowed, why = pcall(frame.CanPostItem, frame)
    if ok then canPost, reason = allowed, why end
  end
  local item = frame.GetItem and frame:GetItem()
  local itemExists
  if item and item.IsValid then
    local ok, value = pcall(item.IsValid, item)
    if ok then itemExists = value end
  end
  local deposit
  if type(frame.GetDepositAmount) == "function" then
    local ok, value = pcall(frame.GetDepositAmount, frame)
    if ok then deposit = value end
  end
  TracePostDebug(label, "canPost=" .. DebugArg(canPost), "reason=" .. DebugArg(reason),
    "buttonEnabled=" .. DebugArg(ControlValue(frame, "PostButton", "IsEnabled")),
    "itemValid=" .. DebugArg(itemExists), "pendingPost=" .. DebugArg(frame.pendingPost ~= nil),
    "duration=" .. DebugArg(AuctionDuration(frame)), "deposit=" .. DebugArg(deposit),
    "money=" .. DebugArg(GetMoney and GetMoney()),
    "throttledReady=" .. DebugArg(PostThrottleReady()))
end

TracePostDebug = function(label, ...)
  if not (gameMode or nativeSellMode) or not CP.db then return end
  local debug = CP.db.postDebug or {}
  debug.trace = debug.trace or {}
  local values = {}
  for i = 1, select("#", ...) do values[#values + 1] = DebugArg(select(i, ...)) end
  if label == "C_AuctionHouse.PostItem" or label == "C_AuctionHouse.PostCommodity" then
    local frame = gameFrame
    local ready
    if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
      local ok, value = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
      if ok then ready = value end
    end
    values[#values + 1] = "formDuration=" .. DebugArg(ControlValue(frame, "DurationDropDown", "GetSelectedValue"))
    values[#values + 1] = "formDurationValue=" .. DebugArg(ControlValue(frame, "DurationDropDown", "GetValue"))
    values[#values + 1] = "nativeDuration=" .. DebugArg(AuctionDuration(frame))
    values[#values + 1] = "durationLabel=" .. DebugArg(ControlValue(frame, "Duration", "GetText"))
    values[#values + 1] = "throttledReady=" .. DebugArg(ready)
  end
  local elapsed = GetTime and GetTime() - (debug.traceStarted or GetTime()) or 0
  debug.trace[#debug.trace + 1] = ("+%.3fs %s%s"):format(elapsed, tostring(label),
    #values > 0 and (": " .. table.concat(values, " | ")) or "")
  if #debug.trace > 60 then table.remove(debug.trace, 1) end
  CP.db.postDebug = debug
end

CapturePostDebug = function(event, a1, a2)
  local f = gameFrame
  local item
  if f and f.GetItem then
    local ok, value = pcall(f.GetItem, f)
    if ok then item = value end
  end
  local link
  if item and C_Item and C_Item.GetItemLink then
    local ok, value = pcall(C_Item.GetItemLink, item)
    if ok then link = value end
  end
  local bag, slot
  if item and item.GetBagAndSlot then
    local ok, b, s = pcall(item.GetBagAndSlot, item)
    if ok then bag, slot = b, s end
  end
  local old = CP.db.postDebug
  local itemID = CP.ItemID(link) or (queue and queue.id) or (gameQ and gameQ.id) or (gamePostInfo and gamePostInfo.id)
  local sameAttempt = event ~= "POST_BUTTON_CLICK" and old and old.itemID == itemID and old.time and time() - old.time <= 10
  local maxStack
  if itemID then
    local ok, value = pcall(MaxStackSize, itemID)
    if ok then maxStack = value end
  end
  local bound
  if item and C_Item and C_Item.IsBound then
    local ok, value = pcall(C_Item.IsBound, item)
    if ok then bound = value end
  end
  local throttledReady
  if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
    local ok, value = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    if ok then throttledReady = value end
  end
  local pendingPost = f and f.pendingPost ~= nil
  local postButtonEnabled = ControlValue(f, "PostButton", "IsEnabled")
  local durationLabel = ControlValue(f, "Duration", "GetText")
  if not f and sameAttempt then
    pendingPost = old.pendingPost
    postButtonEnabled = old.postButtonEnabled
  end
  if throttledReady == nil and sameAttempt then throttledReady = old.throttledReady end
  local debug = {
    time = time(), event = event,
    message = event == "UI_ERROR_MESSAGE" and tostring(a2)
      or (event == "UI_ERROR_DISPLAY" and tostring(a1)) or nil,
    trace = old and old.trace, traceStarted = old and old.traceStarted,
    uiErrorCode = event == "UI_ERROR_MESSAGE" and tostring(a1) or (sameAttempt and old.uiErrorCode),
    auctionErrorCode = event == "AUCTION_HOUSE_POST_ERROR" and tostring(a1) or (sameAttempt and old.auctionErrorCode),
    itemID = itemID, link = link or (sameAttempt and old.link), bag = bag or (sameAttempt and old.bag), slot = slot or (sameAttempt and old.slot),
    form = f and (f == (_G.AuctionHouseFrame and _G.AuctionHouseFrame.CommoditiesSellFrame) and "commodity" or "item")
      or (gamePostInfo and (gamePostInfo.isC and "commodity" or "item")) or (sameAttempt and old.form) or "not open",
    itemSet = item ~= nil or (sameAttempt and old.itemSet) or false,
    itemAfterClick = event ~= "POST_BUTTON_CLICK" and (item ~= nil or (sameAttempt and old.itemAfterClick) or false)
      or (sameAttempt and old.itemAfterClick),
    pendingPost = pendingPost,
    postButtonEnabled = postButtonEnabled,
    throttledReady = throttledReady,
    submittedQuantity = (event == "POST_BUTTON_CLICK" or event == "POST_API_CALL") and ControlValue(f, "QuantityInput", "GetQuantity")
      or (sameAttempt and old.submittedQuantity),
    submittedPrice = (event == "POST_BUTTON_CLICK" or event == "POST_API_CALL") and ControlValue(f, "PriceInput", "GetAmount")
      or (sameAttempt and old.submittedPrice),
    submittedDuration = (event == "POST_BUTTON_CLICK" or event == "POST_API_CALL") and AuctionDuration(f)
      or (sameAttempt and old.submittedDuration),
    quantity = ControlValue(f, "QuantityInput", "GetQuantity") or (gamePostInfo and gamePostInfo.qty) or (queue and queue.sizes[queue.done + 1]) or (sameAttempt and old.quantity),
    price = ControlValue(f, "PriceInput", "GetAmount") or (gamePostInfo and gamePostInfo.price) or (queue and queue.price) or (sameAttempt and old.price),
    duration = AuctionDuration(f)
      or (gamePostInfo and gamePostInfo.dur) or (queue and queue.dur) or (sameAttempt and old.duration),
    durationLabel = durationLabel or (sameAttempt and old.durationLabel),
    buyoutMode = ControlValue(f, "BuyoutModeCheckButton", "GetChecked"),
    bound = bound ~= nil and bound or (sameAttempt and old.bound),
    maxStack = maxStack, postBlocked = nativeSellMode and true or false,
    requestedForm = gamePostInfo and (gamePostInfo.isC and "commodity" or "item") or nil,
    requestedQuantity = gamePostInfo and gamePostInfo.qty or (queue and queue.sizes[queue.done + 1]),
    source = nativeSellMode and "native game sell page" or (f and "game sell form" or "Profiteer post API"),
  }
  if sameAttempt then
    debug.message = debug.message or old.message
    debug.uiErrorCode = debug.uiErrorCode or old.uiErrorCode
    debug.auctionErrorCode = debug.auctionErrorCode or old.auctionErrorCode
  end
  CP.db.postDebug = debug
  return debug
end

function Sl.PostDebug()
  local d = CP.db and CP.db.postDebug
  if not d then
    CP:Print("No auction post error has been captured yet. Try /pf postdebug after a failed post.")
    return
  end
  local lines = {
    "Profiteer auction post diagnostic",
    "Time: " .. tostring(date and date("%Y-%m-%d %H:%M:%S", d.time or 0) or d.time),
    "Client: " .. tostring(GetBuildInfo and select(1, GetBuildInfo()) or "?"),
    "Event: " .. tostring(d.event),
    "Post result: " .. (d.event == "UI_ERROR_DISPLAY" and "The game displayed an error message."
      or d.event == "UI_ERROR_MESSAGE" and "The game reported an auction error."
      or d.event == "NATIVE_SELL_FORM_READY" and "Native Sell form is ready; no post click was captured."
      or d.event == "POST_RESULT_TIMEOUT" and "No auction result event was received."
      or d.event == "POST_API_REJECTED" and "The native form cleared the item without caching a pending post."
      or d.event == "POST_BUTTON_RESULT" and "Button click completed; awaiting auction response."
      or d.event == "POST_BUTTON_CLICK" and "Button click captured before game processing."
      or "Auction event captured."),
    "Source: " .. tostring(d.source),
    "Error message: " .. tostring(d.message or "none"),
    "UI error code: " .. tostring(d.uiErrorCode or "none"),
    "Auction post error code: " .. tostring(d.auctionErrorCode or "none"),
    "Item: " .. tostring(d.link or d.itemID or "unknown"),
    "Item ID: " .. tostring(d.itemID or "unknown"),
    "Item set in form: " .. tostring(d.itemSet),
    "Item still set after click: " .. tostring(d.itemAfterClick),
    "Game pending-post state: " .. tostring(d.pendingPost),
    "Post button enabled: " .. tostring(d.postButtonEnabled),
    "AH throttled system ready: " .. tostring(d.throttledReady),
    "Values at submit: quantity " .. tostring(d.submittedQuantity or "unknown")
      .. ", price " .. tostring(d.submittedPrice or "unknown")
      .. ", duration " .. tostring(d.submittedDuration or "unknown"),
    "Bag/slot: " .. tostring(d.bag or "?") .. "/" .. tostring(d.slot or "?"),
    "Sell form: " .. tostring(d.form),
    "Quantity: " .. tostring(d.quantity or "unknown"),
    "Price: " .. tostring(d.price or "unknown"),
    "Duration: " .. tostring(d.duration or "unknown"),
    "Duration label: " .. tostring(d.durationLabel or "unknown"),
    "Buyout mode: " .. tostring(d.buyoutMode),
    "Bound: " .. tostring(d.bound),
    "Max stack size: " .. tostring(d.maxStack or "unknown"),
    "Profiteer requested form: " .. tostring(d.requestedForm or "unknown"),
    "Profiteer requested quantity: " .. tostring(d.requestedQuantity or "unknown"),
    "Native Sell handoff: " .. tostring(d.postBlocked),
  }
  lines[#lines + 1] = "Post event/API trace:"
  if d.trace and #d.trace > 0 then
    for _, entry in ipairs(d.trace) do lines[#lines + 1] = entry end
  else
    lines[#lines + 1] = "No trace events were captured."
  end
  CP.Report.Open("Auction post diagnostic", lines, "Ctrl+C copies this report. Paste it when reporting the failed auction.")
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
  W.back:SetScript("OnClick", function() gameQ = nil Sl.FromGameSell() end)
  W.back:Hide()

  pane:SetScript("OnHide", function() gameQ = nil Sl.FromGameSell() end)
  pane:SetScript("OnShow", function()
    W.uval:SetText(tostring(S().undercutMode == "percent" and (S().undercutPct or 1) or (S().undercut or 1)))
    ScanBags()
    Sl.Draw()
  end)
  return pane
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "NEW_AUCTION_UPDATE", "AUCTION_MULTISELL_START",
  "AUCTION_MULTISELL_UPDATE", "AUCTION_MULTISELL_FAILURE", "CHAT_MSG_SYSTEM",
  "AUCTION_HOUSE_CLOSED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterEvent, ev, "AUCTION_HOUSE_POST_ERROR")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
pcall(ev.RegisterEvent, ev, "UI_ERROR_MESSAGE")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
if _G.UIErrorsFrame and type(_G.UIErrorsFrame.AddMessage) == "function" and hooksecurefunc then
  local ok, err = pcall(hooksecurefunc, _G.UIErrorsFrame, "AddMessage", function(_, message)
    if nativeSellMode and gamePosting and type(message) == "string" then
      TracePostDebug("UIErrorsFrame.AddMessage", message)
      CapturePostDebug("UI_ERROR_DISPLAY", message)
      gameQ = nil
      EndNativeSellObservation()
    end
  end)
  if not ok then CP.RecordError("observe native auction error display", err) end
end
for _, apiName in ipairs({ "PostItem", "PostCommodity" }) do
  if C_AuctionHouse and type(C_AuctionHouse[apiName]) == "function" and hooksecurefunc then
    local hookedName = apiName
    local ok, err = pcall(hooksecurefunc, C_AuctionHouse, hookedName, function(location, duration, quantity, bid, buyout)
      if nativeSellMode and not gamePosting then
        gamePosting = true
        TracePostDebug("Native post API returned", hookedName)
        CapturePostDebug("POST_API_CALL")
      end
      TracePostDebug("C_AuctionHouse." .. hookedName, location, duration, quantity, bid, buyout)
    end)
    postAPIHookStatus[apiName] = ok
    if not ok then CP.RecordError("hook auction post API " .. hookedName, err) end
  else
    postAPIHookStatus[apiName] = false
  end
end
ev:SetScript("OnEvent", CP.Safe("selling-event", function(_, event, ...)
  local a1, a2 = ...
  if (gameMode or nativeSellMode) and gamePosting then TracePostDebug("EVENT " .. tostring(event), a1, a2) end
  if event == "AUCTION_HOUSE_CLOSED" then
    nativeSellMode = false
    gamePosting = false
    gamePostInfo = nil
    gameFrame = nil
    UpdatePostThrottleGuard()
    if gameMode then Sl.FromGameSell() end
    return
  end
  if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY"
      or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED"
      or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT"
      or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"
      or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    UpdatePostThrottleGuard()
    if (gameMode or nativeSellMode) and postThrottleOverlay and postThrottleOverlay:IsShown() then WatchPostThrottle() end
    return
  end
  if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    if a1 == ADDON then
      forbidden = tostring(a2 or "?")
      print("|cffff6060Profiteer: the game blocked " .. tostring(a2 or "an action") .. " (" .. event .. ")|r")
      SetStatus("The game blocked " .. tostring(a2 or "an action") .. ".")
    end
    return
  end
  local legacyPostSuccess = event == "CHAT_MSG_SYSTEM"
    and type(ERR_AUCTION_STARTED) == "string" and a1 == ERR_AUCTION_STARTED
  if gameMode and gamePosting and (event == "NEW_AUCTION_UPDATE" or legacyPostSuccess
      or event == "AUCTION_HOUSE_AUCTION_CREATED") then
    CapturePostDebug(event)
    local gq = gameQ
    gameQ = nil
    Sl.FromGameSell()
    SetStatus("Posted.")
    if gq then
      gq.done = gq.done + 1
      if gq.done < gq.total then
        queue = gq
        SetStatus("Posted " .. gq.done .. " of " .. gq.total .. "...")
        C_Timer.After(0.7, CP.Safe("selling-next", PostNext))
      else
        SetStatus("Posted " .. gq.total .. " auctions.")
      end
    end
    return
  elseif event == "AUCTION_MULTISELL_FAILURE" and gameMode and gamePosting then
    CapturePostDebug(event, a1)
    gameQ = nil
    Sl.FromGameSell()
    SetStatus("Auction failed. Profiteer returned to Selling; type /pf postdebug for details.")
    return
  elseif event == "AUCTION_MULTISELL_START" and gameMode and gamePosting then
    CapturePostDebug(event)
  elseif event == "AUCTION_MULTISELL_UPDATE" and gameMode and gamePosting then
    CapturePostDebug(event, a1, a2)
  end
  if nativeSellMode and gamePosting and event == "UI_ERROR_MESSAGE" then
    CapturePostDebug(event, a1, a2)
    CP:Print("Native Sell page message " .. tostring(a1) .. ": " .. tostring(a2)
      .. ". Type /pf postdebug for details.")
    gameQ = nil
    EndNativeSellObservation()
    return
  elseif nativeSellMode and gamePosting and event == "AUCTION_HOUSE_POST_ERROR" then
    CapturePostDebug(event, a1)
    CP:Print("Native Sell page rejected the post (error " .. tostring(a1)
      .. "). Type /pf postdebug for details.")
    gameQ = nil
    EndNativeSellObservation()
    return
  elseif nativeSellMode and gamePosting and event == "AUCTION_MULTISELL_FAILURE" then
    CapturePostDebug(event, a1)
    CP:Print("Native Sell page reported an auction failure. Type /pf postdebug for details.")
    gameQ = nil
    EndNativeSellObservation()
    return
  elseif nativeSellMode and gamePosting and (event == "NEW_AUCTION_UPDATE"
      or legacyPostSuccess or event == "AUCTION_HOUSE_AUCTION_CREATED") then
    CapturePostDebug(event)
    local gq = gameQ
    gameQ = nil
    EndNativeSellObservation()
    if gq then
      gq.done = gq.done + 1
      if gq.done < gq.total then
        queue = gq
        SetStatus("Posted " .. gq.done .. " of " .. gq.total .. "... Select the next auction on the native Sell page.")
        C_Timer.After(0.7, CP.Safe("selling-next", PostNext))
      else
        SetStatus("Posted " .. gq.total .. " auctions.")
      end
    else
      CP:Print("Auction posted from the native Sell page.")
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
    local gq = gameQ
    gameQ = nil
    if gameMode then Sl.FromGameSell() end
    SetStatus("Posted.")
    if gq then
      gq.done = gq.done + 1
      if gq.done < gq.total then
        queue = gq
        SetStatus("Posted " .. gq.done .. " of " .. gq.total .. "...")
        C_Timer.After(0.7, CP.Safe("selling-next", PostNext))
      else SetStatus("Posted " .. gq.total .. " auctions.") end
    end
  elseif event == "UI_ERROR_MESSAGE" then
    if gameMode and gamePosting then
      CP:Print("Game message " .. tostring(a1) .. ": " .. tostring(a2))
      CapturePostDebug(event, a1, a2)
      gameQ = nil
      Sl.FromGameSell()
      SetStatus("Auction failed. Profiteer returned to Selling; type /pf postdebug for details.")
    end
    return
  elseif event == "AUCTION_HOUSE_POST_ERROR" and gameMode and gameFrame then
    CapturePostDebug(event, a1)
    CP:Print("The game refused the post (error " .. tostring(a1) .. "). Type /pf postdebug for details.")
    gameQ = nil
    Sl.FromGameSell()
    SetStatus("Auction failed. Profiteer returned to Selling; type /pf postdebug for details.")
  elseif event == "AUCTION_HOUSE_POST_ERROR" and queue then
    CapturePostDebug(event, a1)
    SetStatus("The auction house refused the post. Stopped after " .. queue.done .. " of " .. queue.total .. ".")
    queue = nil
  end
  if event == "GET_ITEM_INFO_RECEIVED" then Sl.Draw() return end
  if event ~= "AUCTION_HOUSE_POST_ERROR" then ScanBags() end
  Sl.Draw()
end))
