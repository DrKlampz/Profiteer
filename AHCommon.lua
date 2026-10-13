local ADDON, CP = ...
-- Small helpers shared by the auction house panes (Shopping, Selling, Cancelling).
local H = {}
CP.AH = H

function H.Icon(id)
  if C_Item and C_Item.GetItemIconByID then local ok, v = pcall(C_Item.GetItemIconByID, id) if ok and v then return v end end
  if GetItemIcon then local v = GetItemIcon(id) if v then return v end end
  return 134400
end

function H.IsOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false end

function H.Ready()
  if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then return C_AuctionHouse.IsThrottledMessageSystemReady() end
  return true
end

function H.Button(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 100, h or 24)
  b:SetText(label)
  return b
end

function H.Edit(parent, w, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 80, 20)
  e:SetAutoFocus(false)
  e:SetMaxLetters(40)
  if numeric then e:SetNumeric(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

function H.Text(parent, template, size)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
  return fs
end

-- "1g 30s 5c", "1g30s", "45s", "12c" or a plain number of gold ("1.5")
function H.ParseMoney(text)
  text = tostring(text or ""):lower():gsub("%s+", "")
  if text == "" then return nil end
  local g = tonumber(text:match("([%d%.]+)g")) or 0
  local s = tonumber(text:match("([%d%.]+)s")) or 0
  local c = tonumber(text:match("([%d%.]+)c")) or 0
  if g == 0 and s == 0 and c == 0 then
    local plain = tonumber(text)
    if plain then return math.floor(plain * 10000 + 0.5) end
    return nil
  end
  return math.floor(g * 10000 + s * 100 + c + 0.5)
end

function H.Money(c) return CP.Money(c and math.floor(c + 0.5) or 0) end

-- the list rows every pane uses: a scrollable stack of buttons
function H.Accent()
  local L = CP.WinLook
  if L and L.On and L.On("main") then local e = L.Effective("main") if e and e.edgeColor then return e.edgeColor end end
  return { 0.85, 0.65, 0.2 }
end

function H.Panel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(w, h)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.02, 0.02, 0.04, 0.55)
    local a = H.Accent()
    f:SetBackdropBorderColor(a[1], a[2], a[3], 0.55)
  end
  return f
end

-- thin bars between list rows (Options: Auction house > row dividers)
local dividers = {}
local function Px()
  local _, h = 0, 0
  if GetPhysicalScreenSize then _, h = GetPhysicalScreenSize() end
  if not h or h <= 0 then return 1 end
  return 768 / h
end
function H.AddDivider(row, index)
  local d = row:CreateTexture(nil, "ARTWORK")
  d:SetTexture("Interface\\Buttons\\WHITE8X8")
  if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(true) end
  if d.SetTexelSnappingBias then d:SetTexelSnappingBias(0) end
  local z = row:CreateTexture(nil, "BACKGROUND")
  z:SetTexture("Interface\\Buttons\\WHITE8X8")
  z:SetAllPoints(row)
  d.row, d.stripe, d.index = row, z, index or 0
  dividers[#dividers + 1] = d
  row:HookScript("OnShow", function() H.ApplyDivider(d) end)
  H.ApplyDivider(d)
end
function H.ApplyDivider(d)
  local s = CP.db and CP.db.settings or {}
  local on = s.rowDividers and true or false
  local c = s.rowDivMode == "custom" and type(s.rowDivColor) == "table" and s.rowDivColor or H.Accent()
  local inset = tonumber(s.rowDivInset) or 0
  local n = math.max(1, math.min(4, math.floor(tonumber(s.rowDivSize) or 1)))
  local scale = d:GetEffectiveScale()
  if not scale or scale <= 0 then scale = 1 end
  local row = d.row
  d:ClearAllPoints()
  d:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", inset, 0)
  d:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, 0)
  d:SetHeight(n * Px() / scale)
  d:SetVertexColor(c[1], c[2], c[3], tonumber(s.rowDivAlpha) or 0.35)
  d:SetShown(on)
  d.stripe:SetVertexColor(1, 1, 1, 0.045)
  d.stripe:SetShown(s.rowStripes and d.index % 2 == 0 or false)
end
function H.ApplyDividers()
  for _, d in ipairs(dividers) do H.ApplyDivider(d) end
end

-- after a list scrolls, the row under the mouse changed: drop the old tooltip and show the new row's
function H.Rehover(rows)
  if GameTooltip then GameTooltip:Hide() end
  for _, r in ipairs(rows) do
    if r:IsShown() and r:IsMouseOver() then
      local f = r:GetScript("OnEnter")
      if f then pcall(f, r) end
      break
    end
  end
end

function H.RowList(parent, rows, rowH, make)
  local L = { rows = {}, offset = 0, n = 0, vis = rows }
  for i = 1, rows do
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(rowH)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * rowH)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * rowH)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.07)
    r.hl:Hide()
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(1, 0.82, 0, 0.16)
    r.sel:Hide()
    r:SetScript("OnEnter", function(self) self.hl:Show() end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() end)
    make(r, i)
    H.AddDivider(r, i)
    L.rows[i] = r
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    local max = math.max(0, L.n - L.vis)
    L.offset = math.max(0, math.min(max, L.offset - delta * 3))
    if L.refresh then L.refresh() end
    H.Rehover(L.rows)
  end)
  return L
end
