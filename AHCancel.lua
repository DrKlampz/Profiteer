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
      if a.status == "undercut" and a.low then
        local diff = a.unit - a.low
        r.gap:SetText(("|cffff6040+%s (%d%%)|r"):format(H.Money(diff), math.floor(diff / a.low * 100 + 0.5)))
        r.relist:SetText(H.Money(math.max(1, a.low - 1)))
      else
        r.gap:SetText("|cff888888-|r")
        r.relist:SetText("|cff888888-|r")
      end
      r.total:SetText(H.Money(math.floor(a.unit * a.qty + 0.5)))
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
  local listed, underVal = 0, 0
  for _, a in ipairs(auctions) do
    local v = a.unit * a.qty
    listed = listed + v
    if a.status == "undercut" then underVal = underVal + v end
  end
  W.count:SetText(total .. " active auctions in " .. #auctions .. " groups, " .. under .. " groups undercut (compared with your last scan).   Listed value: |cffffd100"
    .. H.Money(math.floor(listed + 0.5)) .. "|r, of which undercut: |cffff6040" .. H.Money(math.floor(underVal + 0.5)) .. "|r")
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

-- columns from the right edge; whatever is left over goes to the item name
local COLS = {
  { key = "qty",    label = "Qty",            w = 50,  j = "RIGHT" },
  { key = "mine",   label = "Your price each", w = 105, j = "RIGHT" },
  { key = "low",    label = "Lowest (scan)",  w = 100, j = "RIGHT" },
  { key = "gap",    label = "You are over by", w = 120, j = "RIGHT" },
  { key = "relist", label = "Undercut price", w = 100, j = "RIGHT" },
  { key = "total",  label = "Total value",    w = 110, j = "RIGHT" },
  { key = "stat",   label = "Status",         w = 70,  j = "RIGHT" },
  { key = "left",   label = "Left",           w = 45,  j = "RIGHT" },
}
local function Layout(w)
  if not (pane and C.heads and rowsList) then return end
  local pos = w - 24 - 6
  for i = #COLS, 1, -1 do
    local col = COLS[i]
    pos = pos - col.w
    col.x = pos
    pos = pos - 8
  end
  local nameW = math.max(120, pos - 22 - 4)
  C.nameHead:ClearAllPoints() C.nameHead:SetPoint("TOPLEFT", pane, "TOPLEFT", 22, -2) C.nameHead:SetWidth(nameW)
  for _, col in ipairs(COLS) do
    local fs = C.heads[col.key]
    fs:ClearAllPoints() fs:SetPoint("TOPLEFT", pane, "TOPLEFT", col.x, -2) fs:SetWidth(col.w)
  end
  for _, r in ipairs(rowsList.rows) do
    r.name:SetWidth(nameW)
    for _, col in ipairs(COLS) do
      local fs = r[col.key]
      fs:ClearAllPoints() fs:SetPoint("LEFT", r, "LEFT", col.x, 0) fs:SetWidth(col.w)
    end
  end
end

function C.Build(parent, w, h)
  pane = CreateFrame("Frame", nil, parent)
  pane:SetSize(w, h)
  pane:Hide()
  C.pane = pane

  C.heads = {}
  for _, col in ipairs(COLS) do
    local fs = H.Text(pane, "GameFontNormalSmall")
    fs:SetText(col.label)
    fs:SetJustifyH(col.j)
    C.heads[col.key] = fs
  end
  C.nameHead = H.Text(pane, "GameFontNormalSmall")
  C.nameHead:SetText("Item")
  C.nameHead:SetJustifyH("LEFT")
  lf = CreateFrame("Frame", nil, pane)
  lf:SetPoint("TOPLEFT", 0, -20)
  lf:SetSize(w - 24, 15 * 20)
  rowsList = H.RowList(lf, MAXROWS, 20, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 2, 0)
    r.name = H.Text(r) r.name:SetPoint("LEFT", 22, 0) r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    for _, col in ipairs(COLS) do
      local fs = H.Text(r)
      fs:SetJustifyH(col.j)
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      r[col.key] = fs
    end
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
  Layout(w)
  if W.count then W.count:SetWidth(math.max(200, w - 220)) W.count:SetJustifyH("LEFT") end
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
