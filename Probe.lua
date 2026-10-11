local ADDON_NAME, CP = ...
-- Temporary: records how this client's auction house window is built, so the Profiteer tab can be made to fit it.
-- Written to ProfiteerDB.probe the next time the UI reloads or you log out.
local function Names(t, filter)
  local out = {}
  for k, v in pairs(t) do
    if not filter or filter(k, v) then out[#out + 1] = tostring(k) .. ":" .. type(v) end
  end
  table.sort(out)
  return out
end
local function Kids(f, depth, out, path)
  if depth > 3 or not f or not f.GetChildren then return end
  for i, c in ipairs({ f:GetChildren() }) do
    local n = c.GetName and c:GetName() or nil
    local key = n or ("#" .. i)
    local info = key .. " [" .. (c.GetObjectType and c:GetObjectType() or "?") .. "]"
      .. (c.IsShown and (c:IsShown() and " shown" or " hidden") or "")
      .. (c.GetWidth and string.format(" %dx%d", c:GetWidth() or 0, c:GetHeight() or 0) or "")
    out[#out + 1] = path .. info
    Kids(c, depth + 1, out, path .. "  ")
  end
end
local function Dump()
  local p = {}
  p.time = date and date("%Y-%m-%d %H:%M:%S") or "?"
  p.tocVersion = select(4, GetBuildInfo())
  p.AH = AuctionHouseFrame and { type = AuctionHouseFrame:GetObjectType(), name = AuctionHouseFrame:GetName() } or "none"
  if AuctionHouseFrame then
    p.keys = Names(AuctionHouseFrame, function(k, v) return type(v) == "table" or type(v) == "function" end)
    p.frameKeys = Names(AuctionHouseFrame, function(k, v) return type(v) == "table" and type(v.GetObjectType) == "function" end)
    p.children = {}
    Kids(AuctionHouseFrame, 0, p.children, "")
    p.tabs = {}
    for _, key in ipairs({ "Tabs", "tabs", "TabSystem", "BuyTab", "SellTab", "AuctionsTab" }) do
      local t = AuctionHouseFrame[key]
      if t then p.tabs[key] = type(t) == "table" and Names(t) or type(t) end
    end
    p.numTabs = AuctionHouseFrame.numTabs
    p.selected = AuctionHouseFrame.selectedTab
    p.tabNames = {}
    for i = 1, 8 do
      local t = _G["AuctionHouseFrameTab" .. i]
      if t then p.tabNames[#p.tabNames + 1] = i .. ": " .. tostring(t:GetText()) .. " " .. tostring(t:GetObjectType()) end
    end
  end
  p.mode = AuctionHouseFrameDisplayMode and Names(AuctionHouseFrameDisplayMode) or "none"
  p.api = {}
  if C_AuctionHouse then for k, v in pairs(C_AuctionHouse) do p.api[#p.api + 1] = k end table.sort(p.api) end
  p.events = {}
  p.globalsAH = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and (k:find("^AuctionHouse") or k:find("^AuctionFrame") or k:find("^AUCTION_")) and type(v) ~= "function" then
      p.globalsAH[#p.globalsAH + 1] = k .. ":" .. type(v)
    end
  end
  table.sort(p.globalsAH)
  if #p.globalsAH > 400 then for i = #p.globalsAH, 401, -1 do p.globalsAH[i] = nil end end
  local gt = {}
  for _, fn in ipairs({ "GetAuctionItemInfo", "GetNumAuctionItems", "QueryAuctionItems", "PlaceAuctionBid", "StartAuction", "GetMoney" }) do gt[fn] = type(_G[fn]) end
  p.legacyAPI = gt
  CP.db.probe = p
end
local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function()
  if not CP.db then return end
  if C_Timer and C_Timer.After then C_Timer.After(1.5, function() pcall(Dump) end) else pcall(Dump) end
end)
