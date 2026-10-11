local ADDON, CP = ...
-- Profiteer inside the auction house window.
-- The game's Buy / Sell / Auctions tabs are replaced by Profiteer's own: Shopping, Selling, Cancelling, Crafts and Ledger.
-- A panel covers the AH body and holds Profiteer's window; the game's own frames underneath are left untouched
-- (Options: "Keep the game's own tabs" adds ours after the game's instead of replacing them).
local AHTab = {}
CP.AHTab = AHTab

local KEYS = { { "game", "Auction House" }, { "shopping", "Shopping" }, { "selling", "Selling" }, { "cancelling", "Cancelling" }, { "crafts", "Crafts" }, { "ledger", "Ledger" } }
local tabs, host, hostBg
local embedded = false
local current

local function Blizz() return { _G.AuctionHouseFrameBuyTab, _G.AuctionHouseFrameSellTab, _G.AuctionHouseFrameAuctionsTab } end

-- the game's own pages (browse, sell, auctions ...) are put away while one of ours is showing,
-- otherwise parts of them (the sell item button, Create Auction, Buyout Mode) poke through
local GAME_PAGES = { "BrowseResultsFrame", "CategoriesList", "SearchBar", "ItemBuyFrame", "CommoditiesBuyFrame", "ItemSellFrame",
  "CommoditiesSellFrame", "ItemSellList", "CommoditiesSellList", "AuctionsFrame", "WoWTokenResults", "WoWTokenSellFrame", "BuyDialog" }
local function PutAwayGamePages()
  local AH = _G.AuctionHouseFrame
  if not AH then return end
  for _, k in ipairs(GAME_PAGES) do
    local f = AH[k]
    if f and f.Hide and f.IsShown and f:IsShown() then pcall(f.Hide, f) end
  end
end

-- our tabs are drawn flat and hang from the bottom edge of the window, in the window's colors
local function TabColors()
  local a = (CP.AH and CP.AH.Accent and CP.AH.Accent()) or { 0.85, 0.65, 0.2 }
  local r, g, b = 0.07, 0.07, 0.09
  local L = CP.WinLook
  if L and L.On and L.On("ah") then
    local e = L.Effective("ah")
    if e and e.bgColor then r, g, b = e.bgColor[1], e.bgColor[2], e.bgColor[3] end
  end
  return a, r, g, b
end

local function StyleTab(t, on)
  if not t.pfTab then return end
  local a, r, g, b = TabColors()
  local k = t.pfTab
  if on then
    k.bg:SetColorTexture(math.min(1, r * 1.5 + 0.03), math.min(1, g * 1.5 + 0.03), math.min(1, b * 1.5 + 0.04), 1)
    k.top:SetColorTexture(a[1], a[2], a[3], 1)
    k.top:Show()
    if t.Text then t.Text:SetTextColor(1, 0.82, 0.2) end
  else
    k.bg:SetColorTexture(r * 0.8, g * 0.8, b * 0.8, 0.95)
    k.top:Hide()
    if t.Text then t.Text:SetTextColor(0.72, 0.72, 0.75) end
  end
  k.edge:SetColorTexture(a[1], a[2], a[3], on and 0.9 or 0.45)
end

local function InitTab(t)
  t.lookNoSkin = true
  for _, rg in ipairs({ t:GetRegions() }) do
    if rg.GetObjectType and rg:GetObjectType() == "Texture" then rg:SetAlpha(0) rg:Hide() end
  end
  for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
    local tx = t[fn] and t[fn](t)
    if tx then tx:SetAlpha(0) end
  end
  t:SetHeight(26)
  local k = {}
  k.bg = t:CreateTexture(nil, "BACKGROUND")
  k.bg:SetAllPoints()
  k.edge = t:CreateTexture(nil, "BORDER")
  k.edge:SetPoint("BOTTOMLEFT") k.edge:SetPoint("BOTTOMRIGHT") k.edge:SetHeight(1)
  k.l = t:CreateTexture(nil, "BORDER") k.l:SetPoint("TOPLEFT") k.l:SetPoint("BOTTOMLEFT") k.l:SetWidth(1)
  k.r = t:CreateTexture(nil, "BORDER") k.r:SetPoint("TOPRIGHT") k.r:SetPoint("BOTTOMRIGHT") k.r:SetWidth(1)
  k.top = t:CreateTexture(nil, "ARTWORK")
  k.top:SetPoint("TOPLEFT") k.top:SetPoint("TOPRIGHT") k.top:SetHeight(2)
  k.hl = t:CreateTexture(nil, "HIGHLIGHT") k.hl:SetAllPoints() k.hl:SetColorTexture(1, 1, 1, 0.08)
  t.pfTab = k
  -- the side lines follow the bottom line's color
  hooksecurefunc(k.edge, "SetColorTexture", function(_, r2, g2, b2, a2) k.l:SetColorTexture(r2, g2, b2, a2) k.r:SetColorTexture(r2, g2, b2, a2) end)
  -- the game's template puts its own art back when the tab is shown or its label changes
  t:HookScript("OnShow", function() for _, rg in ipairs({ t:GetRegions() }) do
    if rg ~= k.bg and rg ~= k.edge and rg ~= k.l and rg ~= k.r and rg ~= k.top and rg ~= k.hl and rg.GetObjectType and rg:GetObjectType() == "Texture" then rg:SetAlpha(0) end
  end end)
end

local function SetSelected(t, on)
  if not t then return end
  if t.pfTab then StyleTab(t, on) return end
  if on then if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, t) end
  else if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, t) end end
end

-- the host's background follows the window look of the auction house, when one is switched on
-- the auction house's title keeps one fixed, stock gold whatever the window look says
function AHTab.Title()
  local AH = _G.AuctionHouseFrame
  local fs = AH and ((AH.TitleContainer and AH.TitleContainer.TitleText) or AH.TitleText)
  if not (fs and fs.SetTextColor) then return end
  fs:SetTextColor(1, 0.82, 0.2)
  -- and one fixed name: the game retitles the window for each of its pages, so keep putting ours back
  if not fs.pfTitle then
    fs.pfTitle = true
    hooksecurefunc(fs, "SetText", function(self, t)
      if self.pfSetting or t == "Auction House" then return end
      self.pfSetting = true
      self:SetText("Auction House")
      self:SetTextColor(1, 0.82, 0.2)
      self.pfSetting = nil
    end)
  end
  if fs.GetText and fs:GetText() ~= "Auction House" then fs.pfSetting = true fs:SetText("Auction House") fs.pfSetting = nil end
end

function AHTab.Restyle()
  AHTab.Title()
  for k, t in pairs(tabs or {}) do StyleTab(t, current == k or (k == "game" and not current and AuctionHouseFrame and AuctionHouseFrame:IsShown() and not (host and host:IsShown()))) end
  if not hostBg then return end
  local r, g, b, a = 0.05, 0.05, 0.07, 1
  local L = CP.WinLook
  if L and L.On and L.On("ah") then
    local e = L.Effective("ah")
    if e and e.bgColor then r, g, b = e.bgColor[1], e.bgColor[2], e.bgColor[3] a = math.max(0.85, tonumber(e.alpha) or 1) end
  end
  hostBg:SetColorTexture(r, g, b, a)
end

local function Embed()
  local UI = CP.UI
  UI.Create()
  local f = UI.frame
  if not f then return end
  if embedded then return end
  if f:IsShown() then f:Hide() end
  f.docked = false
  f:SetParent(host)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetFrameStrata(host:GetFrameStrata())
  f:SetFrameLevel(host:GetFrameLevel() + 2)
  f:SetToplevel(false)
  f:SetMovable(false)
  -- shrink to fit if the AH is narrower or shorter than the window; never grow
  -- (the window look's own size setting multiplies on top of this, see LookSetup)
  local function Fit()
    if not embedded then return end
    local hw, hh, fw, fh = host:GetWidth(), host:GetHeight(), f:GetWidth(), f:GetHeight()
    local sc = 1
    local shrink = CP.db.settings.ahShrink ~= false
    if hw and hh and fw and fh and hw > 50 and hh > 50 and fw > 0 and fh > 0 then
      if shrink then sc = math.min(1, (hw - 4) / fw) else sc = math.min(1, (hw - 4) / fw, (hh - 4) / fh) end
    end
    -- no dead space: the auction house window itself is made just tall enough for the tab
    local AH = _G.AuctionHouseFrame
    if AH then
      if shrink and fh and fh > 0 then
        if not AHTab.origH then AHTab.origH = AH:GetHeight() end
        local need = math.ceil(fh * sc + 4 + 26 + 28)
        if AHTab.origH and need < AHTab.origH then pcall(AH.SetHeight, AH, need) end
      elseif AHTab.origH then pcall(AH.SetHeight, AH, AHTab.origH) end
    end
    f.fitScale = sc
    f:SetScale(sc)
    if AHTab.PlaceTabs then CP.After(0.1, AHTab.PlaceTabs) end
    if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end
    if CP.AH and CP.AH.ApplyDividers then CP.AH.ApplyDividers() end
  end
  AHTab.Fit = Fit
  if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0) f:SetBackdropBorderColor(0, 0, 0, 0) end
  if f.bgTex then f.bgTex:Hide() end
  if f.closeBtn then f.closeBtn:Hide() end
  if f.titleFS then f.titleFS:Hide() end
  for _, t in pairs(UI.tabs or {}) do t:Hide() end   -- the AH's bottom tabs do the navigation now
  embedded = true
  Fit()
  f:Show()
  CP.After(0.05, function() Fit() if embedded and f.lookBg then f.lookBg:Hide() end end)
end

local function Unembed()
  if not embedded then return end
  embedded = false
  local f = CP.UI.frame
  if not f then return end
  f:Hide()
  f:SetParent(UIParent)
  f.fitScale = nil
  f:SetScale(1)
  f:SetMovable(true)
  f:SetToplevel(true)
  f:SetFrameStrata("HIGH")
  if f.SetBackdropColor then f:SetBackdropColor(1, 1, 1, 1) f:SetBackdropBorderColor(1, 1, 1, 1) end
  if f.bgTex then f.bgTex:Show() end
  if f.closeBtn then f.closeBtn:Show() end
  if f.titleFS then f.titleFS:Show() end
  for _, t in pairs(CP.UI.tabs or {}) do t:Show() end
  f:ClearAllPoints()
  f:SetPoint("CENTER")
  if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end
end

local function Mark(key)
  for k, t in pairs(tabs or {}) do SetSelected(t, k == key) end
end

function AHTab.Current() return current end
function AHTab.IsReady() return tabs ~= nil and host ~= nil end

function AHTab.Leave()
  if not (embedded or (host and host:IsShown())) then return end
  Unembed()
  if host then host:Hide() end
  current = nil
  Mark(nil)
end

-- open one of Profiteer's tabs inside the AH
function AHTab.Go(key)
  if not (tabs and host and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
  key = key or current or "shopping"
  for _, t in ipairs(Blizz()) do SetSelected(t, false) end
  AHTab.Restyle()
  PutAwayGamePages()
  host:Show()
  Embed()
  current = key
  if CP.db and CP.db.settings then CP.db.settings.ahLastTab = key end
  Mark(key)
  CP.UI.SetTab(key)
  return true
end

-- tint the game's own Browse page with the window look so it matches the rest (its art is grey, so a multiply recolors it)
function AHTab.StyleGame()
  -- the game's Browse page stays as the game draws it; undo any tint an earlier version left behind
  local AH = _G.AuctionHouseFrame
  if not AH then return end
  local function walk(f, depth)
    if not f or depth > 5 then return end
    if f.GetRegions then
      for _, t in ipairs({ f:GetRegions() }) do
        if t.pfTinted and t.SetVertexColor then pcall(t.SetVertexColor, t, 1, 1, 1) t.pfTinted = nil end
      end
    end
    if f.GetChildren then for _, c in ipairs({ f:GetChildren() }) do walk(c, depth + 1) end end
  end
  for _, k in ipairs({ "CategoriesList", "BrowseResultsFrame", "SearchBar" }) do if AH[k] then walk(AH[k], 0) end end
end

-- the game's own Browse page, for searching the auction house the usual way
function AHTab.Game()
  if not (tabs and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
  AHTab.Leave()
  AHTab.Size()
  local AH = AuctionHouseFrame
  local modes = _G.AuctionHouseFrameDisplayMode
  local done = false
  if AH.SetDisplayMode and modes and modes.Buy then done = pcall(AH.SetDisplayMode, AH, modes.Buy) end
  if not done and _G.AuctionHouseFrameBuyTab then pcall(_G.AuctionHouseFrameBuyTab.Click, _G.AuctionHouseFrameBuyTab) end
  for _, k in ipairs({ "BrowseResultsFrame", "CategoriesList", "SearchBar" }) do
    local f = AH[k]
    if f and f.Show then pcall(f.Show, f) end
  end
  Mark("game")
  AHTab.Title()
  if CP.db and CP.db.settings then CP.db.settings.ahLastTab = "game" end
  if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end
  CP.After(0.1, function() if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end AHTab.StyleGame() end)
  CP.After(0.6, function() if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end AHTab.StyleGame() end)
end

-- one window size for every tab (the game's own page included), so nothing bounces when you switch:
-- the height Profiteer's tabs need, fitted to the width of the auction house
function AHTab.Size()
  local AH = _G.AuctionHouseFrame
  if not (AH and CP.UI and CP.UI.Create) then return end
  if CP.db.settings.ahShrink == false then
    if AHTab.origH then pcall(AH.SetHeight, AH, AHTab.origH) end
    return
  end
  CP.UI.Create()
  local f = CP.UI.frame
  if not f then return end
  local fw, fh = f:GetWidth(), f:GetHeight()
  if not (fw and fh and fw > 0 and fh > 0) then return end
  if not AHTab.origH then AHTab.origH = AH:GetHeight() end
  local hw = (AH:GetWidth() or 0) - 8
  local sc = math.min(1, (hw - 4) / fw)
  local need = math.ceil(fh * sc + 4 + 26 + 28)
  if AHTab.origH and need < AHTab.origH then pcall(AH.SetHeight, AH, need) end
end

-- the tab the auction house opens on (Options: "Open the auction house on")
function AHTab.Start()
  local st = CP.db.settings
  local pick = st.ahStartTab or "game"
  if pick == "last" then pick = st.ahLastTab or "game" end
  if pick == "game" then AHTab.Game() else AHTab.Go(pick) end
end

function AHTab.Select() return AHTab.Go(current or "shopping") end

-- the game's own page (categories list, results and their scroll arrows) can hang lower than the window's edge:
-- the tabs go below whichever is lowest, so they never cover the up and down arrows
local function PlaceTabs()
  if not tabs or CP.db.settings.keepGameTabs then return end
  local AH = _G.AuctionHouseFrame
  local first = tabs[KEYS[1][1]]
  if not (AH and first and AH:GetBottom()) then return end
  local base = AH:GetBottom()
  local low = base
  for _, f in ipairs({ AH.BrowseResultsFrame, AH.CategoriesList, AH.SearchBar }) do
    local b = f and f.GetBottom and f:GetBottom()
    if b and b < low then low = b end
  end
  local es, ae = AH:GetEffectiveScale(), AH:GetEffectiveScale()
  local drop = math.max(0, base - low)
  first:ClearAllPoints()
  first:SetPoint("TOPLEFT", AH, "BOTTOMLEFT", 14, 1 - drop)
end
AHTab.PlaceTabs = PlaceTabs

local function Create()
  if tabs or not AuctionHouseFrame then return end
  local buy = _G.AuctionHouseFrameBuyTab
  local last = _G.AuctionHouseFrameAuctionsTab
  if not (buy and last) then return end

  host = CreateFrame("Frame", "ProfiteerAHHost", AuctionHouseFrame)
  host:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -26)
  host:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 28)
  host:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 400)
  host:EnableMouse(true)
  hostBg = host:CreateTexture(nil, "BACKGROUND")
  hostBg:SetAllPoints()
  host:Hide()
  AHTab.Restyle()

  local keep = CP.db.settings.keepGameTabs and true or false
  local made = {}
  local prev
  for i, k in ipairs(KEYS) do
    local ok, t = pcall(CreateFrame, "Button", "AuctionHouseFrameProfiteerTab" .. k[1], AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
    if not ok or not t then ok, t = pcall(CreateFrame, "Button", "AuctionHouseFrameProfiteerTab" .. k[1], AuctionHouseFrame, "PanelTopTabButtonTemplate") end
    if not ok or not t then CP:Print("Could not create the Profiteer tabs in the auction house.") return end
    t:SetText(k[2])
    InitTab(t)
    local tw = (t.Text and t.Text.GetStringWidth and t.Text:GetStringWidth()) or 60
    if t.Text and t.Text.SetWidth then t.Text:SetWidth(tw + 12) if t.Text.SetWordWrap then t.Text:SetWordWrap(false) end end
    local tabW = math.max(112, math.floor(tw * 1.25 + 50))
    t:SetWidth(tabW)
    if t.Text and t.Text.SetWidth then
      if t.Text.GetNumPoints and t.Text:GetNumPoints() > 1 then
        t.Text:ClearAllPoints()
        t.Text:SetPoint("CENTER", t, "CENTER", 0, 0)
      end
      t.Text:SetWidth(tabW - 16)
      t:HookScript("OnShow", function() t:SetWidth(tabW) t.Text:SetWidth(tabW - 16) end)
    end
    if i == 1 then
      if keep then
        t:SetPoint("TOPLEFT", last, "TOPRIGHT", 6, 0)
      else
        t:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 14, 1)
      end
    else
      t:SetPoint("TOPLEFT", prev, "TOPRIGHT", 3, 0)
    end
    if k[1] == "game" then t.lookNoSkin = true end   -- the game's own page keeps a plain tab
    t:SetScript("OnClick", function() if k[1] == "game" then AHTab.Game() else AHTab.Go(k[1]) end end)
    SetSelected(t, false)
    made[k[1]] = t
    prev = t
  end
  tabs = made
  CP.After(0.2, PlaceTabs)
  AuctionHouseFrame:HookScript("OnShow", function() CP.After(0.2, PlaceTabs) end)

  if not keep then
    for _, bt in ipairs(Blizz()) do if bt then bt:Hide() end end
  else
    for _, bt in ipairs(Blizz()) do if bt and bt.HookScript then bt:HookScript("OnClick", AHTab.Leave) end end
  end
  AuctionHouseFrame:HookScript("OnHide", AHTab.Leave)
  if CP.UI.ahButton then CP.UI.ahButton:Hide() end
  if CP.WinLook then CP.WinLook.Attach("ah", AuctionHouseFrame) end
end

local ev = CreateFrame("Frame")
CP.Register(ev, "AUCTION_HOUSE_SHOW")
ev:SetScript("OnEvent", CP.Safe("ah-tab", function()
  if not CP.db then return end
  AHTab.Size()
  CP.After(0.2, CP.Safe("ah-tab-create", function()
    Create()
    if CP.UI.ahButton then CP.UI.ahButton:Hide() end
    if tabs and not CP.db.settings.keepGameTabs and not current then AHTab.Start() end
  end))
end))
