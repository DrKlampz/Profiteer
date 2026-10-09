local ADDON, CP = ...
local UI = {}
CP.UI = UI

local ROWS, ROW_H, GAP = 16, 20, 4
local COLS = {
  { key = "name",     label = "Item",        w = 170, align = "LEFT",  sortable = true },
  { key = "crafters", label = "Crafters",    w = 110, align = "LEFT" },
  { key = "cost",     label = "Cost",        w = 85,  align = "RIGHT", sortable = true },
  { key = "revenue",  label = "Sells (net)", w = 85,  align = "RIGHT", sortable = true },
  { key = "profit",   label = "Profit",      w = 85,  align = "RIGHT", sortable = true },
  { key = "ratio",    label = "ROI",         w = 50,  align = "RIGHT", sortable = true },
  { key = "listed",   label = "Listed",      w = 45,  align = "RIGHT", sortable = true },
  { key = "perday",   label = "Sold/day",    w = 52,  align = "RIGHT", sortable = true },
  { key = "make",     label = "Can make",    w = 55,  align = "RIGHT", sortable = true },
}
local TOTAL_W = 0
for _, c in ipairs(COLS) do TOTAL_W = TOTAL_W + c.w + GAP end

local rows = {}
UI.offset = 0

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function ShowTooltip(self)
  local g = self.data
  if not g then return end
  local left, screen = self:GetLeft(), UIParent:GetWidth()
  local onRight = type(left) == "number" and type(screen) == "number" and left > screen / 2
  GameTooltip:SetOwner(self, onRight and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  GameTooltip:AddLine(g.name, 1, 1, 1)
  GameTooltip:AddLine(g.prof, 0.6, 0.8, 1)
  if g.unpriced then GameTooltip:AddLine("Not ranked: " .. (g.why or "no price data"), 1, 0.6, 0.3, true) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Reagents", 1, 0.82, 0)
  for _, rg in ipairs(g.reagents) do
    local c, src, id = CP:SlotCost(rg)
    GameTooltip:AddDoubleLine(rg.count .. "x " .. CP.ItemName(id),
      CP.Money(c and c * rg.count) .. " |cff888888(" .. (src == "made" and "from raw materials" or src or "?") .. ")|r", 1, 1, 1, 1, 1, 1)
    if CP:MakePlan(id) then
      local parts = {}
      for _, raw in ipairs(CP:RawMaterials(id)) do
        local rc = CP:DirectCost(raw.id)
        local cnt = raw.count * rg.count
        cnt = (cnt == math.floor(cnt)) and cnt or tonumber(string.format("%.1f", cnt))
        parts[#parts + 1] = cnt .. "x " .. CP.ItemName(raw.id) .. (rc and (" " .. CP.Money(rc * cnt)) or " (no price)")
      end
      local direct, made = CP:DirectCost(id), CP:MakeCost(id)
      local note = ""
      if made and direct then
        note = made < direct and "  |cff55ff55cheaper than the bar|r" or "  |cff888888bar is cheaper|r"
      end
      GameTooltip:AddLine("   or buy " .. table.concat(parts, ", ") .. note, 0.7, 0.7, 0.7, true)
    end
  end
  GameTooltip:AddLine(" ")
  local p = CP.db.prices[g.id]
  GameTooltip:AddDoubleLine("AH lowest", CP.Money(p and p.min), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("AH reference", CP.Money(p and p.ref), 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Listings / units", ((p and p.n) or 0) .. " / " .. ((p and p.qty) or 0), 1, 1, 1, 1, 1, 1)
  local st = CP.History.Stats(g.id)
  if st and st.median then
    GameTooltip:AddDoubleLine("Market median (" .. st.samples .. " scans)", CP.Money(st.median), 1, 1, 1, 1, 1, 1)
  end
  if st and st.perDay then
    GameTooltip:AddDoubleLine("Est. sales/day", string.format("%.1f", st.perDay), 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Sell price used", g.sell and CP.Money(g.sell) or "none", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Price data", CP.Age(p and p.time), 1, 1, 1, 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Can craft", 1, 0.82, 0)
  for _, charKey in ipairs(g.chars) do
    local inv = CP.db.inventory[charKey]
    local seen = inv and inv.time and ("  |cff888888(bags seen " .. CP.Age(inv.time) .. ")|r") or "  |cff888888(bags not seen yet)|r"
    GameTooltip:AddDoubleLine(CP.ShortName(charKey), "can make " .. (g.make[charKey] or 0) .. seen, 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: search the AH for the materials", 0.6, 0.8, 0.6)
  GameTooltip:AddLine("Shift-click: search for the finished item", 0.6, 0.8, 0.6)
  GameTooltip:AddLine("Right-click: " .. (g.tracked and "stop tracking" or "track (pin to top)"), 0.6, 0.8, 0.6)
  GameTooltip:Show()
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function CreateRow(i)
  local row = CreateFrame("Button", nil, UI.frame)
  row:SetHeight(ROW_H)
  row:SetWidth(TOTAL_W)
  row:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", 22, -70 - (i - 1) * ROW_H)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.12)
  row.cols = {}
  local x = 0
  for _, c in ipairs(COLS) do
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(c.w)
    fs:SetHeight(ROW_H)
    fs:SetJustifyH(c.align)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    row.cols[c.key] = fs
    x = x + c.w + GAP
  end
  row:SetScript("OnEnter", ShowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    local g = self.data
    if not g then return end
    if button == "RightButton" then
      CP.Shop.Track(g)
    elseif IsShiftKeyDown() then
      CP.Shop.ForOutput(g)
    else
      CP.Shop.ForCraft(g)
    end
  end)
  return row
end

local function CraftersText(g)
  local names = {}
  for _, k in ipairs(g.chars) do names[#names + 1] = CP.ShortName(k) end
  if #names <= 2 then return table.concat(names, ", ") end
  return names[1] .. ", " .. names[2] .. " +" .. (#names - 2)
end

local function MaxOffset()
  return math.max(0, #(UI.results or {}) - ROWS)
end

function UI.Update()
  if not UI.frame or not UI.frame:IsShown() then return end
  local res = UI.results or {}
  local maxOff = MaxOffset()
  if UI.offset > maxOff then UI.offset = maxOff end
  if UI.offset < 0 then UI.offset = 0 end
  if UI.slider then
    UI.slider:SetMinMaxValues(0, maxOff)
    UI.updatingSlider = true
    UI.slider:SetValue(UI.offset)
    UI.updatingSlider = false
  end

  for i = 1, ROWS do
    local row = rows[i]
    local g = res[i + UI.offset]
    row.data = g
    if g and g.unpriced then
      row.cols.name:SetText((g.tracked and "|cffffd100*|r " or "") .. "|cff9d9d9d" .. g.name .. "|r")
      row.cols.crafters:SetText(CraftersText(g))
      row.cols.cost:SetText(g.cost and CP.Money(g.cost) or "|cff888888?|r")
      row.cols.revenue:SetText("|cff888888-|r")
      row.cols.profit:SetText("|cff888888-|r")
      row.cols.ratio:SetText("|cff888888-|r")
      row.cols.listed:SetText("|cff8888880|r")
      row.cols.perday:SetText("|cff888888?|r")
      row.cols.make:SetText(g.best > 0 and ("|cff40ff40" .. g.best .. "|r") or "|cff888888-|r")
      row:Show()
    elseif g then
      local profitColor = g.profit > 0 and "|cff40ff40" or "|cffff4040"
      row.cols.name:SetText((g.tracked and "|cffffd100*|r " or "") .. g.name)
      row.cols.crafters:SetText(CraftersText(g))
      row.cols.cost:SetText(CP.Money(g.cost))
      row.cols.revenue:SetText(CP.Money(g.revenue))
      row.cols.profit:SetText(CP.Money(g.profit))
      row.cols.ratio:SetText(profitColor .. math.floor(g.ratio * 100 + 0.5) .. "%|r")
      row.cols.listed:SetText(g.listed < 10 and ("|cffffa040" .. g.listed .. "|r") or g.listed)
      row.cols.perday:SetText(g.perDay and string.format("%.1f", g.perDay) or "|cff888888?|r")
      row.cols.make:SetText(g.best > 0 and ("|cff40ff40" .. g.best .. "|r") or "|cff888888-|r")
      row:Show()
    else
      row:Hide()
    end
  end
end

function UI.SetStatus(text)
  if UI.status then UI.status:SetText(text or "") end
end

function UI.Rebuild()
  if not CP.db then return end
  local results, skipped, total = CP:BuildResults()
  UI.nPriced = #results
  local all = {}
  for _, g in ipairs(results) do all[#all + 1] = g end
  for _, g in ipairs(CP.unpriced or {}) do all[#all + 1] = g end
  results = all
  UI.results = all
  if UI.frame and UI.frame:IsShown() then
    UI.Update()
    if not CP.Scanner:IsRunning() then
      UI.SetStatus(("%d priced, %d more with no AH price (grey, at the bottom) of %d crafts. Last scan: %s")
        :format(UI.nPriced or 0, #results - (UI.nPriced or 0), total, CP.Age(CP.db.lastScan)))
    end
  end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local function HeaderClick(self)
  local s = CP.db.settings
  local key = self.key
  if s.sortKey == key then
    s.sortDesc = not s.sortDesc
  else
    s.sortKey = key
    s.sortDesc = (key ~= "name")
  end
  UI.Rebuild()
end

function UI.Create()
  if UI.frame then return end

  local f = CreateFrame("Frame", "ProfiteerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  UI.frame = f
  f.docked = false
  f:SetSize(TOTAL_W + 62, 470)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  -- solid dark panel so world text (nameplates, guild tags) can't show through the rows
  local bgTex = f:CreateTexture(nil, "BACKGROUND")
  bgTex:SetDrawLayer("BACKGROUND", 1)
  bgTex:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
  bgTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  bgTex:SetColorTexture(0.04, 0.04, 0.06, 0.96)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- remember where the user put it (offset from screen's bottom-left)
    local l, b = self:GetLeft(), self:GetBottom()
    if type(l) == "number" and type(b) == "number" and CP.db then
      CP.db.settings.winX, CP.db.settings.winY = l, b
    end
  end)
  f:SetScript("OnShow", UI.Rebuild)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    UI.offset = math.max(0, math.min(MaxOffset(), UI.offset - delta * 3))
    UI.Update()
  end)
  f:Hide()
  table.insert(UISpecialFrames, "ProfiteerFrame")

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText("Profiteer")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Column headers
  local x = 0
  for _, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(c.w, 18)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + x, -48)
    local fs = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH(c.align)
    fs:SetText(c.label)
    if c.sortable then
      h.key = c.key
      h:SetScript("OnClick", HeaderClick)
    end
    x = x + c.w + GAP
  end

  -- Rows
  for i = 1, ROWS do rows[i] = CreateRow(i) end

  -- Scrollbar (plain slider, no template needed)
  local slider = CreateFrame("Slider", nil, f)
  slider:SetOrientation("VERTICAL")
  slider:SetSize(16, ROWS * ROW_H)
  slider:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + TOTAL_W + 6, -70)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  local bg = slider:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local thumb = slider:GetThumbTexture()
  if thumb then thumb:SetSize(16, 24) end
  slider:SetScript("OnValueChanged", function(_, value)
    if UI.updatingSlider then return end
    UI.offset = math.floor(value + 0.5)
    UI.Update()
  end)
  UI.slider = slider

  -- Bottom controls
  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(110, 24)
  scan:SetPoint("BOTTOMLEFT", 22, 44)
  scan:SetText("Scan AH")
  scan:SetScript("OnClick", function() CP.Scanner:Start() end)

  local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(90, 24)
  refresh:SetPoint("LEFT", scan, "RIGHT", 6, 0)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", UI.Rebuild)

  local cb = CreateFrame("CheckButton", "ProfiteerOnlyCraftable", f, "UICheckButtonTemplate")
  cb:SetPoint("LEFT", refresh, "RIGHT", 16, 0)
  local cbText = _G["ProfiteerOnlyCraftableText"] or cb.Text
  if cbText then pcall(function() cbText:SetText("Craftable now only") end) end
  cb:SetScript("OnClick", function(self)
    CP.db.settings.craftableOnly = self:GetChecked() and true or false
    UI.Rebuild()
  end)
  UI.onlyCraftable = cb

  local shopTop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  shopTop:SetSize(110, 24)
  shopTop:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 44)
  shopTop:SetText("Shop top 10")
  shopTop:SetScript("OnClick", function() CP.Shop.Command("") end)

  local shopTracked = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  shopTracked:SetSize(110, 24)
  shopTracked:SetPoint("RIGHT", shopTop, "LEFT", -6, 0)
  shopTracked:SetText("Shop tracked")
  shopTracked:SetScript("OnClick", function() CP.Shop.Command("tracked") end)

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 24, 22)
  status:SetWidth(TOTAL_W)
  status:SetJustifyH("LEFT")
  UI.status = status
end

function UI.Toggle()
  UI.Create()
  if UI.frame:IsShown() then
    UI.frame:Hide()
  else
    UI.onlyCraftable:SetChecked(CP.db.settings.craftableOnly)
    UI.frame:Show()
  end
end

------------------------------------------------------------------------
-- Auction House integration
------------------------------------------------------------------------
-- A "Profiteer" button on the AH window opens the ranking right over the AH,
-- like a tab. Close it (X or the button again) to get the AH back. Drag the
-- button to reposition it. /pf ahopen on = open automatically with the AH.

local function Num(v, default) if type(v) == "number" then return v end return default end

local function Dock()
  -- Open BESIDE the AH (never over it) unless the user has moved the window.
  local ah = AuctionHouseFrame
  local f = UI.frame
  if not f then return false end
  local st = CP.db and CP.db.settings or {}
  f:ClearAllPoints()
  if type(st.winX) == "number" and type(st.winY) == "number" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", st.winX, st.winY)
  elseif ah then
    f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
  else
    f:SetPoint("CENTER")
  end
  f:SetFrameStrata("HIGH")
  f.docked = true
  return true
end

local function Undock()
  local f = UI.frame
  if not f then return end
  f.docked = false
  f:ClearAllPoints()
  f:SetPoint("CENTER")
end

function UI.ResetWindow()
  if CP.db then CP.db.settings.winX, CP.db.settings.winY = nil, nil end
  if UI.frame and UI.frame:IsShown() then Dock() end
end

function UI.ShowDocked()
  UI.Create()
  if UI.frame:IsShown() then UI.frame:Hide() end
  if not Dock() then Undock() end
  UI.onlyCraftable:SetChecked(CP.db.settings.craftableOnly)
  UI.frame:Show()
end

local function PlaceAHButton()
  local s = CP.db.settings
  local b = UI.ahButton
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", s.ahBtnX or -44, s.ahBtnY or -3)
end

local function CreateAHButton()
  if UI.ahButton or not AuctionHouseFrame then return end
  local b = CreateFrame("Button", "ProfiteerAHButton", AuctionHouseFrame, "UIPanelButtonTemplate")
  b:SetSize(96, 22)
  b:SetText("Profiteer")
  b:SetFrameLevel(Num(AuctionHouseFrame:GetFrameLevel(), 0) + 20)
  b:RegisterForDrag("LeftButton", "RightButton")
  b:SetFrameStrata("DIALOG")
  b:SetScript("OnClick", function()
    if UI.frame and UI.frame:IsShown() and UI.frame.docked then
      UI.frame:Hide()
    else
      UI.ShowDocked()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    local cx, cy = GetCursorPosition()
    local sc = self:GetEffectiveScale()
    local r, t = self:GetRight(), self:GetTop()
    if type(cx) ~= "number" or type(r) ~= "number" or type(sc) ~= "number" or sc == 0 then return end
    self.dragDX, self.dragDY = r - cx / sc, t - cy / sc
    self:SetScript("OnUpdate", function(me)
      local ah = AuctionHouseFrame
      local x, y = GetCursorPosition()
      local s2 = me:GetEffectiveScale()
      local ar, at = ah:GetRight(), ah:GetTop()
      if type(ar) ~= "number" or type(at) ~= "number" then return end
      -- offset of button's top-right from the AH's top-right, following the cursor
      CP.db.settings.ahBtnX = (x / s2 + me.dragDX) - ar
      CP.db.settings.ahBtnY = (y / s2 + me.dragDY) - at
      PlaceAHButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Profiteer", 1, 0.82, 0)
    GameTooltip:AddLine("Craft profits and price info. Drag to move this button; drag the Profiteer window by its frame.", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.ahButton = b
  PlaceAHButton()
end

function UI.ResetAHButton()
  CP.db.settings.ahBtnX, CP.db.settings.ahBtnY = nil, nil
  if UI.ahButton then PlaceAHButton() end
end

local ahFrame = CreateFrame("Frame")
CP.Register(ahFrame, "AUCTION_HOUSE_SHOW")
CP.Register(ahFrame, "AUCTION_HOUSE_CLOSED")
ahFrame:SetScript("OnEvent", CP.Safe("ah-integration", function(_, event)
  if not CP.db then return end
  if event == "AUCTION_HOUSE_SHOW" then
    CreateAHButton()
    if CP.db.settings.ahAutoOpen then CP.After(0.3, UI.ShowDocked) end
  elseif UI.frame and UI.frame.docked then
    UI.frame:Hide()
    Undock()
  end
end))
