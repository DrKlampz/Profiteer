local ADDON, CP = ...
-- Cancelling pane: your own auctions, compared with the last price scan, with a one-click cancel.
local H = CP.AH
local C = {}
CP.AHCancel = C

local MAXROWS = 40
local pane, rowsList, lf
local W = {}
local auctions = {}

local function SetStatus(t) if W.status then W.status:SetText(t or "") end end
local function ItemId(key) return key and key.itemID end

local function TimeLeft(a)
  local s = a.timeLeftSeconds
  if type(s) == "number" then
    if s >= 3600 then return string.format("%dh", math.floor(s / 3600)) end
    return string.format("%dm", math.floor(s / 60))
  end
  local band = a.timeLeft
  local names = { [0] = "<30m", [1] = "<2h", [2] = "<12h", [3] = "<48h" }
  return names[band] or "?"
end

local function IsCommodity(a)
  local key = a.itemKey
  if key and C_AuctionHouse.GetItemCommodityStatus then
    local ok, st = pcall(C_AuctionHouse.GetItemCommodityStatus, key)
    if ok then return st == (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2) end
  end
  return (a.quantity or 1) > 1
end

local function Read()
  auctions = {}
  local groups = {}
  if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
  local n = C_AuctionHouse.GetNumOwnedAuctions() or 0
  local activeStatus = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active or 0
  for i = 1, n do
    local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
    if a and (a.status == nil or a.status == activeStatus) and a.buyoutAmount then
      local id = ItemId(a.itemKey)
      local unit = IsCommodity(a) and a.buyoutAmount or (a.buyoutAmount / math.max(1, a.quantity or 1))
      local p = id and CP.db.prices[id]
      local low = p and p.min
      local status
      if not low then status = "no scan"
      elseif unit > low * 1.0005 + 0 then status = "undercut"
      else status = "lowest" end
      local gkey = tostring(id) .. ":" .. tostring(math.floor(unit + 0.5)) .. ":" .. status
      local g = groups[gkey]
      local secs = type(a.timeLeftSeconds) == "number" and a.timeLeftSeconds or ((a.timeLeft or 0) * 1000)
      if not g then
        g = { id = id, ids = {}, qty = 0, count = 0, unit = unit, low = low, status = status, left = TimeLeft(a), secs = secs, link = a.itemLink }
        groups[gkey] = g
        auctions[#auctions + 1] = g
      end
      g.ids[#g.ids + 1] = a.auctionID
      g.auctionID = g.ids[1]
      g.count = g.count + 1
      g.qty = g.qty + (a.quantity or 1)
      if secs < g.secs then g.secs = secs g.left = TimeLeft(a) end
    end
  end
  table.sort(auctions, function(x, y)
    if (x.status == "undercut") ~= (y.status == "undercut") then return x.status == "undercut" end
    return (x.id or 0) < (y.id or 0)
  end)
end

function C.Draw()
  if not pane then return end
  rowsList.n = #auctions
  local maxOff = math.max(0, #auctions - rowsList.vis)
  if rowsList.offset > maxOff then rowsList.offset = maxOff end
  local under = 0
  for _, a in ipairs(auctions) do if a.status == "undercut" then under = under + 1 end end
  for i, r in ipairs(rowsList.rows) do
    local a = auctions[i + rowsList.offset]
    if a and i <= rowsList.vis then
      r.a = a
      r.icon:SetTexture(H.Icon(a.id or 0))
      r.name:SetText((a.link or (a.id and CP.ItemName(a.id)) or "?") .. (a.count > 1 and ("  |cff9d9d9dx" .. a.count .. " auctions|r") or ""))
      r.qty:SetText(tostring(a.qty))
      r.mine:SetText(H.Money(a.unit))
      r.low:SetText(a.low and H.Money(a.low) or "|cff888888-|r")
      local col = a.status == "undercut" and "|cffff6040" or (a.status == "lowest" and "|cff40ff40" or "|cff888888")
      r.stat:SetText(col .. a.status .. "|r")
      r.left:SetText(a.left)
      r:Show()
    else
      r:Hide()
    end
  end
  W.next:SetEnabled(under > 0 and H.IsOpen())
  local total = 0
  for _, a in ipairs(auctions) do total = total + a.count end
  W.count:SetText(total .. " active auctions in " .. #auctions .. " groups, " .. under .. " groups undercut (compared with your last scan)")
end

function C.Refresh()
  if not (C_AuctionHouse and H.IsOpen()) then SetStatus("Open the auction house first.") return end
  if C_AuctionHouse.QueryOwnedAuctions then
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    pcall(C_AuctionHouse.QueryOwnedAuctions, sorts)
  end
  Read()
  C.Draw()
end

local function CancelOne(a)
  if not a then return end
  if C_AuctionHouse.CanCancelAuction and not C_AuctionHouse.CanCancelAuction(a.auctionID) then SetStatus("That auction can't be cancelled.") return end
  local ok, err = pcall(C_AuctionHouse.CancelAuction, a.auctionID)
  if not ok then CP.RecordError("cancel auction", err) SetStatus("Could not cancel.") return end
  SetStatus("Cancelling...")
end

function C.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  C.pane = pane

  local dx = math.max(0, w - 24 - 690)
  local cols = { { "Item", 22, 260 }, { "Qty", 290 + dx, 40 }, { "Your price each", 340 + dx, 110 }, { "Lowest (scan)", 460 + dx, 100 }, { "Status", 570 + dx, 70 }, { "Left", 645 + dx, 40 } }
  for _, c in ipairs(cols) do
    local fs = H.Text(pane, "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", c[2], -2)
    fs:SetText(c[1])
  end
  lf = CreateFrame("Frame", nil, pane)
  lf:SetPoint("TOPLEFT", 0, -20)
  lf:SetSize(w - 24, 15 * 20)
  rowsList = H.RowList(lf, MAXROWS, 20, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 2, 0)
    r.name = H.Text(r) r.name:SetPoint("LEFT", 22, 0) r.name:SetWidth(260 + dx) r.name:SetJustifyH("LEFT")
    r.qty = H.Text(r) r.qty:SetPoint("LEFT", 290 + dx, 0) r.qty:SetWidth(40) r.qty:SetJustifyH("LEFT")
    r.mine = H.Text(r) r.mine:SetPoint("LEFT", 340 + dx, 0) r.mine:SetWidth(110) r.mine:SetJustifyH("LEFT")
    r.low = H.Text(r) r.low:SetPoint("LEFT", 460 + dx, 0) r.low:SetWidth(100) r.low:SetJustifyH("LEFT")
    r.stat = H.Text(r) r.stat:SetPoint("LEFT", 570 + dx, 0) r.stat:SetWidth(70) r.stat:SetJustifyH("LEFT")
    r.left = H.Text(r) r.left:SetPoint("LEFT", 645 + dx, 0) r.left:SetWidth(40) r.left:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self) if self.a then CancelOne(self.a) end end)
    r:SetScript("OnEnter", function(self)
      self.hl:Show()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine((self.a and self.a.count or 1) > 1 and ("Click to cancel one of these " .. self.a.count .. " auctions") or "Click to cancel this auction", 1, 0.82, 0)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
  end)
  rowsList.refresh = C.Draw

  W.count = H.Text(pane)
  W.count:SetPoint("BOTTOMLEFT", 4, 34)
  W.status = H.Text(pane)
  W.status:SetPoint("BOTTOMLEFT", 4, 14)
  W.next = H.Button(pane, "Cancel next undercut", 170, 24)
  W.next:SetPoint("BOTTOMRIGHT", -8, 8)
  W.next:SetScript("OnClick", function()
    for _, a in ipairs(auctions) do if a.status == "undercut" then CancelOne(a) return end end
  end)
  local refresh = H.Button(pane, "Refresh", 80, 24)
  refresh:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
  refresh:SetScript("OnClick", C.Refresh)
  pane:SetScript("OnShow", C.Refresh)
  C.Resize(w, h)
  return pane
end

-- as many rows as the pane is tall, so the list fills the window
function C.Resize(w, h)
  if not (pane and rowsList) then return end
  pane:SetSize(w, h)
  rowsList.vis = math.max(5, math.min(MAXROWS, math.floor((h - 70) / 20)))
  lf:SetSize(w - 24, rowsList.vis * 20)
  C.Draw()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", CP.Safe("cancel-event", function(_, event)
  if not pane or not pane:IsShown() then return end
  if event == "AUCTION_CANCELED" then SetStatus("Cancelled.") if C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end end
  Read()
  C.Draw()
end))
