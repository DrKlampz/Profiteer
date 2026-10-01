local ADDON, CP = ...
local MM = {}
CP.Minimap = MM

-- Standalone minimap button (no library needed). Drag it around the minimap
-- edge; the angle is saved. Left-click toggles the window, right-click starts
-- an AH scan (Auction House must be open).

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local btn

-- Distance from the minimap centre follows the actual minimap size, plus an
-- adjustable margin (/pf minimap radius <n>) so it clears whatever ring art
-- the client draws.
local function Radius()
  local w = Minimap:GetWidth()
  if type(w) ~= "number" or w <= 0 then w = 140 end
  return w / 2 + (CP.db.settings.minimapOffset or 12)
end

local function Place()
  local s = CP.db.settings
  btn:ClearAllPoints()
  if s.minimapFree and s.minimapX then
    btn:SetPoint("CENTER", Minimap, "CENTER", s.minimapX, s.minimapY or 0)
    return
  end
  local a = math.rad(s.minimapAngle or 215)
  local r = Radius()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Drag = slide around the ring. Shift + drag = place it anywhere.
local function DragUpdate()
  local s = CP.db.settings
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  local dx, dy = px / scale - mx, py / scale - my
  if IsShiftKeyDown() then
    s.minimapFree, s.minimapX, s.minimapY = true, dx, dy
  else
    s.minimapFree = false
    s.minimapAngle = math.deg(atan2(dy, dx))
  end
  Place()
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Profiteer", 1, 0.82, 0)
  GameTooltip:AddLine("Left-click: open / close window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: full AH scan (AH must be open)", 1, 1, 1)
  GameTooltip:AddLine("Drag: slide around the ring. Shift+drag: place anywhere.", 0.7, 0.7, 0.7)
  local last = CP.db.lastScan
  if last and last > 0 then
    GameTooltip:AddLine("Last scan: " .. CP.Age(last), 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

local function Create()
  btn = CreateFrame("Button", "ProfiteerMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  local lvl = Minimap:GetFrameLevel()
  if type(lvl) ~= "number" then lvl = 0 end
  btn:SetFrameLevel(lvl + 10)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      CP.Scanner:Start()
    else
      CP.UI.Toggle()
    end
  end)
  btn:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", DragUpdate)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  btn:SetScript("OnEnter", ShowTooltip)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  Place()
  if CP.db.settings.minimapHide then btn:Hide() end
end

-- /pf minimap [radius <n> | reset]
function MM.Command(arg)
  local s = CP.db.settings
  local sub, val = (arg or ""):match("^(%S*)%s*(.-)$")
  if sub == "radius" then
    local v = tonumber(val)
    if v then
      s.minimapOffset = v
      s.minimapFree = false
      if btn then Place() end
      CP:Print("Minimap button margin set to " .. v .. ". Bigger moves it further out.")
    else
      CP:Print("usage: /pf minimap radius 20   (now " .. (s.minimapOffset or 12) .. ")")
    end
  elseif sub == "reset" then
    s.minimapOffset, s.minimapFree, s.minimapX, s.minimapY, s.minimapAngle = 12, false, nil, nil, 215
    if btn then Place(); btn:Show() end
    s.minimapHide = false
    CP:Print("Minimap button reset.")
  else
    MM.Toggle()
  end
end

function MM.Toggle()
  local s = CP.db.settings
  s.minimapHide = not s.minimapHide
  if btn then
    if s.minimapHide then btn:Hide() else btn:Show() end
  end
  CP:Print("Minimap button " .. (s.minimapHide and "hidden" or "shown") .. ".")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  if CP.db then Create() end
end)
