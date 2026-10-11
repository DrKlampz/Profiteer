local ADDON, CP = ...
-- Profiteer inside the auction house window.
-- The game's Buy / Sell / Auctions tabs are replaced by Profiteer's own: Shopping, Selling, Cancelling, Crafts and Ledger.
-- A panel covers the AH body and holds Profiteer's window; the game's own frames underneath are left untouched
-- (Options: "Keep the game's own tabs" adds ours after the game's instead of replacing them).
local AHTab = {}
CP.AHTab = AHTab

local KEYS = { { "shopping", "Shopping" }, { "selling", "Selling" }, { "cancelling", "Cancelling" }, { "crafts", "Crafts" }, { "ledger", "Ledger" } }
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

local function SetSelected(t, on)
  if not t then return end
  if on then if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, t) end
  else if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, t) end end
end

-- the host's background follows the window look of the auction house, when one is switched on
function AHTab.Restyle()
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
    if hw and hh and fw and fh and hw > 50 and hh > 50 and fw > 0 and fh > 0 then sc = math.min(1, (hw - 4) / fw, (hh - 4) / fh) end
    f.fitScale = sc
    f:SetScale(sc)
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
  Mark(key)
  CP.UI.SetTab(key)
  return true
end

function AHTab.Select() return AHTab.Go(current or "shopping") end

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
    local tw = (t.Text and t.Text.GetStringWidth and t.Text:GetStringWidth()) or 60
    if t.Text and t.Text.SetWidth then t.Text:SetWidth(tw + 12) if t.Text.SetWordWrap then t.Text:SetWordWrap(false) end end
    local tabW = math.max(112, math.floor(tw * 1.25 + 50))
    t:SetWidth(tabW)
    if t.Text and t.Text.SetWidth then
      if t.Text.GetNumPoints and t.Text:GetNumPoints() > 1 then
        t.Text:ClearAllPoints()
        t.Text:SetPoint("CENTER", t, "CENTER", 0, -3)
      end
      t.Text:SetWidth(tabW - 16)
      t:HookScript("OnShow", function() t:SetWidth(tabW) t.Text:SetWidth(tabW - 16) end)
    end
    if i == 1 then
      if keep then
        t:SetPoint("LEFT", last, "RIGHT", -15, 0)
      else
        local p, rel, relp, x, y = buy:GetPoint(1)
        t:SetPoint(p, rel, relp, x, y)
      end
    else
      t:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    end
    t:SetScript("OnClick", function() AHTab.Go(k[1]) end)
    SetSelected(t, false)
    made[k[1]] = t
    prev = t
  end
  tabs = made

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
  CP.After(0.2, CP.Safe("ah-tab-create", function()
    Create()
    if CP.UI.ahButton then CP.UI.ahButton:Hide() end
    if tabs and not CP.db.settings.keepGameTabs and not current then AHTab.Go("shopping") end
  end))
end))
