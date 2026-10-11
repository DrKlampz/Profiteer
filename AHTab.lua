local ADDON_NAME, CP = ...
-- A "Profiteer" tab on the auction house window (next to Buy / Sell / Auctions).
-- Stage 1: the craft ranking and ledger live inside the AH. The panel covers the AH body, so the game's own
-- Buy / Sell / Auctions frames underneath stay exactly as they are.
local AHTab = {}
CP.AHTab = AHTab

local tab, host
local embedded = false
local wasStyle

local function Names() return { _G.AuctionHouseFrameBuyTab, _G.AuctionHouseFrameSellTab, _G.AuctionHouseFrameAuctionsTab } end

local function SetSelected(t, on)
  if not t then return end
  if on then
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, t) end
  else
    if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, t) end
  end
end

local function Embed()
  local UI = CP.UI
  UI.Create()
  local f = UI.frame
  if not f then return end
  if f:IsShown() then f:Hide() end
  f.docked = false
  f:SetParent(host)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetFrameStrata(host:GetFrameStrata())
  f:SetFrameLevel(host:GetFrameLevel() + 2)
  f:SetToplevel(false)
  f:SetMovable(false)
  f:SetScale(1)
  if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0) f:SetBackdropBorderColor(0, 0, 0, 0) end
  if f.bgTex then f.bgTex:Hide() end
  if f.closeBtn then f.closeBtn:Hide() end
  embedded = true
  f:Show()
  -- the look system may have put its own background behind the window; the AH provides one
  CP.After(0.05, function() if embedded and f.lookBg then f.lookBg:Hide() end end)
end

local function Unembed()
  if not embedded then return end
  embedded = false
  local f = CP.UI.frame
  if not f then return end
  f:Hide()
  f:SetParent(UIParent)
  f:SetMovable(true)
  f:SetToplevel(true)
  f:SetFrameStrata("HIGH")
  if f.SetBackdropColor then f:SetBackdropColor(1, 1, 1, 1) f:SetBackdropBorderColor(1, 1, 1, 1) end
  if f.bgTex then f.bgTex:Show() end
  if f.closeBtn then f.closeBtn:Show() end
  f:ClearAllPoints()
  f:SetPoint("CENTER")
  if CP.WinLook and CP.WinLook.Apply then CP.WinLook.Apply() end
end

function AHTab.Leave()
  if not embedded and not (host and host:IsShown()) then return end
  Unembed()
  if host then host:Hide() end
  SetSelected(tab, false)
end

function AHTab.Select()
  if not (tab and host and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
  for _, t in ipairs(Names()) do SetSelected(t, false) end
  SetSelected(tab, true)
  host:Show()
  Embed()
end

local function Create()
  if tab or not AuctionHouseFrame then return end
  local after = _G.AuctionHouseFrameAuctionsTab or AuctionHouseFrame.AuctionsTab
  if not after then return end

  host = CreateFrame("Frame", "ProfiteerAHHost", AuctionHouseFrame)
  host:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -26)
  host:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 28)
  host:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 40)
  host:EnableMouse(true)
  local bg = host:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.07, 1)
  host:Hide()

  local ok, t = pcall(CreateFrame, "Button", "AuctionHouseFrameProfiteerTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
  if not ok or not t then
    ok, t = pcall(CreateFrame, "Button", "AuctionHouseFrameProfiteerTab", AuctionHouseFrame, "PanelTopTabButtonTemplate")
  end
  if not ok or not t then CP:Print("Could not create the Profiteer tab in the auction house.") return end
  tab = t
  tab:SetPoint("LEFT", after, "RIGHT", -15, 0)
  tab:SetText("Profiteer")
  if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
  tab:SetScript("OnClick", function() AHTab.Select() end)
  tab:HookScript("OnShow", function() end)
  SetSelected(tab, false)

  for _, bt in ipairs(Names()) do
    if bt and bt.HookScript then bt:HookScript("OnClick", AHTab.Leave) end
  end
  AuctionHouseFrame:HookScript("OnHide", AHTab.Leave)
  if CP.UI.ahButton then CP.UI.ahButton:Hide() end
end

local ev = CreateFrame("Frame")
CP.Register(ev, "AUCTION_HOUSE_SHOW")
ev:SetScript("OnEvent", CP.Safe("ah-tab", function()
  if not CP.db then return end
  CP.After(0.2, CP.Safe("ah-tab-create", function()
    Create()
    if CP.UI.ahButton then CP.UI.ahButton:Hide() end
  end))
end))
