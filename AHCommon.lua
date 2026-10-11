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

-- thin bars between list rows (Options: "Draw dividing bars between rows")
local dividers = {}
function H.AddDivider(row)
  local d = row:CreateTexture(nil, "ARTWORK")
  d:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  d:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  d:SetHeight(1)
  dividers[#dividers + 1] = d
  H.ApplyDividers()
end
function H.ApplyDividers()
  local on = CP.db and CP.db.settings and CP.db.settings.rowDividers and true or false
  local a = H.Accent()
  for _, d in ipairs(dividers) do
    d:SetColorTexture(a[1], a[2], a[3], 0.35)
    d:SetShown(on)
  end
end

function H.RowList(parent, rows, rowH, make)
  local L = { rows = {}, offset = 0, n = 0 }
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
    H.AddDivider(r)
    L.rows[i] = r
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    local max = math.max(0, L.n - rows)
    L.offset = math.max(0, math.min(max, L.offset - delta * 3))
    if L.refresh then L.refresh() end
  end)
  return L
end
