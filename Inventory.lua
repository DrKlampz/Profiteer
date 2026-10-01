local ADDON, CP = ...

-- Tracks bag + bank contents per character (so the results can show what you
-- can craft right now) and remembers vendor prices for reagents.

local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
  return 0
end

local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.hyperlink, info.stackCount, info.itemID end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
    return link, count
  end
end

local function CountBags(bags)
  local out = {}
  for _, bag in ipairs(bags) do
    for slot = 1, NumSlots(bag) do
      local link, count, id = SlotInfo(bag, slot)
      id = id or CP.ItemID(link)
      if id then out[id] = (out[id] or 0) + (count or 1) end
    end
  end
  return out
end

local function Store(kind, counts)
  if not CP.db or not CP.charKey then return end
  local inv = CP.db.inventory[CP.charKey]
  if not inv then inv = { bags = {}, bank = {} }; CP.db.inventory[CP.charKey] = inv end
  inv[kind] = counts
  inv.time = time()
end

-- Equipped bag slots (backpack + bags, plus a reagent bag where one exists)
local bagList = {}
local numBags = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
for b = 0, numBags do bagList[#bagList + 1] = b end

-- Bank: main bank slots plus bank bags
local bankList = { -1 }
local first = numBags + 1
for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bankList[#bankList + 1] = b end

local bankOpen = false
local pending = false

local function Rescan()
  pending = false
  Store("bags", CountBags(bagList))
  if bankOpen then Store("bank", CountBags(bankList)) end
  CP:Refresh()
end

local function QueueRescan()
  if pending then return end
  pending = true
  CP.After(1.0, Rescan)
end

local function MerchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local t = C_MerchantFrame.GetItemInfo(i)
    if t then return t.price, t.stackCount, t.numAvailable, t.hasExtendedCost end
    return nil
  end
  if GetMerchantItemInfo then
    local _, _, price, qty, numAvailable, _, extCost = GetMerchantItemInfo(i)
    return price, qty, numAvailable, extCost
  end
end

local function ScanVendor()
  if not CP.db or not GetMerchantNumItems then return end
  for i = 1, GetMerchantNumItems() do
    local price, qty, numAvailable, extCost = MerchantInfo(i)
    local id = CP.ItemID(GetMerchantItemLink(i))
    -- only unlimited-stock, gold-only items are useful as a reagent price
    if id and price and price > 0 and not extCost and numAvailable == -1 then
      CP.db.vendor[id] = math.ceil(price / math.max(qty or 1, 1))
    end
  end
end

local f = CreateFrame("Frame")
CP.Register(f, "PLAYER_LOGIN")
CP.Register(f, "BAG_UPDATE_DELAYED")
CP.Register(f, "BAG_UPDATE")
CP.Register(f, "BANKFRAME_OPENED")
CP.Register(f, "BANKFRAME_CLOSED")
CP.Register(f, "MERCHANT_SHOW")
f:SetScript("OnEvent", CP.Safe("inventory", function(_, event)
  if event == "PLAYER_LOGIN" then
    CP.After(3, Rescan)
  elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
    QueueRescan()
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    QueueRescan()
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "MERCHANT_SHOW" then
    ScanVendor()
  end
end))
