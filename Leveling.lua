local ADDON, CP = ...

-- Level up: for a profession you have, which craft is the cheapest way to gain a skill point.
-- Only crafts that are orange for you (a skill point is certain) are put first; yellow ones come after
-- and are marked "not certain". Green and grey crafts are never suggested: they may give nothing.
-- Cost counts only what you would still have to buy (what is already in your bags and bank is free),
-- minus what the finished item sells for, using the prices from your auction house scan.
-- Open it with Alt+right-click on the minimap button, or /pf level.
local V = {}
CP.Leveling = V

local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local function Store(prof, skill, max, diff, byName)
  local d = CP.db
  if not (d and CP.charKey) then return end
  d.leveling = d.leveling or {}
  d.leveling[CP.charKey] = d.leveling[CP.charKey] or {}
  d.leveling[CP.charKey][prof] = { skill = skill, max = max, diff = diff, byName = byName, time = time() }
  V.cur = prof
  if V.frame and V.frame:IsShown() then V.Refresh() end
end

local function CaptureModern()
  local T = C_TradeSkillUI
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
  local prof, skill, max
  if T.GetBaseProfessionInfo then
    local i = T.GetBaseProfessionInfo()
    if i then prof, skill, max = i.professionName, i.skillLevel, i.maxSkillLevel end
  end
  if not prof or prof == "" then return end
  local ids = T.GetAllRecipeIDs()
  if not ids or #ids == 0 then return end
  local diff, byName, n = {}, {}, 0
  for _, rid in ipairs(ids) do
    local info = T.GetRecipeInfo(rid)
    if info and info.learned then
      local rd = info.relativeDifficulty
      if type(rd) == "number" then
        diff[rid] = rd
        if info.name then byName[info.name] = rd end
        n = n + 1
      end
    end
  end
  if n > 0 then Store(prof, skill, max, diff, byName) end
end

local function CaptureLegacy()
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local prof, rank, max = GetTradeSkillLine()
  local n = GetNumTradeSkills()
  if not prof or prof == "UNKNOWN" or not n or n == 0 then return end
  local byName, any = {}, false
  for i = 1, n do
    local name, kind = GetTradeSkillInfo(i)
    if name and DIFF[kind] then byName[name] = DIFF[kind] any = true end
  end
  if any then Store(prof, rank, max, {}, byName) end
end

local pending = false
local function Capture()
  pending = false
  if not CP.db or not CP.charKey then return end
  local ok, err = true, nil
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
    ok, err = pcall(CaptureModern)
  elseif GetNumTradeSkills then
    ok, err = pcall(CaptureLegacy)
  end
  if not ok then CP.RecordError("leveling capture", err) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "SKILL_LINES_CHANGED" }) do CP.Register(ev, e) end
ev:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  CP.After(0.8, Capture)
end)

------------------------------------------------------------------------
-- the ranking
------------------------------------------------------------------------
local function Rows(prof)
  local lv = CP.db.leveling and CP.db.leveling[CP.charKey] and CP.db.leveling[CP.charKey][prof]
  local recs = CP.db.recipes and CP.db.recipes[CP.charKey] and CP.db.recipes[CP.charKey][prof]
  if not (lv and recs) then return nil end
  local cut = CP.db.settings.ahCut or 0.05
  local out, noprice = {}, 0
  for _, r in ipairs(recs) do
    local d = (r.rid and lv.diff[r.rid]) or (r.rname and lv.byName[r.rname])
    if d == 0 or d == 1 then
      local pay, full, can, ok = 0, 0, nil, true
      for _, rg in ipairs(r.reagents) do
        local unit = CP:SlotCost(rg)
        if not unit then ok = false break end
        full = full + unit * rg.count
        local missing = math.max(0, rg.count - CP:HaveSlot(CP.charKey, rg))
        pay = pay + unit * missing
        local n = math.floor(CP:HaveSlot(CP.charKey, rg) / rg.count)
        if not can or n < can then can = n end
      end
      if ok then
        local sell = CP:SellPrice(r.id)
        local back = sell and sell * (r.yield or 1) * (1 - cut) or 0
        out[#out + 1] = { name = r.name, diff = d, pay = pay, full = full, net = full - back, back = sell and back or nil, can = can or 0 }
      else
        noprice = noprice + 1
      end
    end
  end
  table.sort(out, function(a, b)
    if a.diff ~= b.diff then return a.diff < b.diff end
    return a.net < b.net
  end)
  return out, noprice, lv
end
V.Rows = Rows

------------------------------------------------------------------------
-- window
------------------------------------------------------------------------
local ROWS = 12
local COLORS = { [0] = "|cffff8040", [1] = "|cffffff00" }

local function Professions()
  local t = CP.db.leveling and CP.db.leveling[CP.charKey]
  local out = {}
  if t then for p in pairs(t) do out[#out + 1] = p end end
  table.sort(out)
  return out
end

function V.Refresh()
  local f = V.frame
  if not f then return end
  local profs = Professions()
  if #profs == 0 then
    f.head:SetText("Open one of your profession windows once so Profiteer can see which crafts still give you skill points.")
    f.prof:SetText("")
    for i = 1, ROWS do f.rows[i]:Hide() end
    f.pick:SetText("")
    return
  end
  local found
  for _, p in ipairs(profs) do if p == V.cur then found = true end end
  if not found then V.cur = profs[1] end
  local rows, noprice, lv = Rows(V.cur)
  f.prof:SetText(("%s  %s/%s"):format(V.cur, tostring(lv and lv.skill or "?"), tostring(lv and lv.max or "?")))
  if not rows then
    f.head:SetText("Open the " .. V.cur .. " window again to capture its recipes.")
    for i = 1, ROWS do f.rows[i]:Hide() end
    return
  end
  if #rows == 0 then
    f.head:SetText("Nothing here gives a skill point right now (everything is green or grey, or has no price). Learn a new recipe, or scan the auction house for prices.")
    f.pick:SetText("")
  else
    local b = rows[1]
    f.head:SetText(("Cheapest %s: |cffffffff%s|r  -  you pay %s, net %s per craft"):format(
      b.diff == 0 and "sure skill point" or "likely skill point", b.name, CP.Money(b.pay), CP.Money(b.net)))
    local n = math.max(1, b.can)
    f.pick:SetText(b.diff == 0 and "Orange: every craft gives a skill point. Open the window again after crafting; the list re-ranks."
      or "Yellow: a skill point is likely but not certain. No orange craft has a price yet.")
  end
  for i = 1, ROWS do
    local r, row = rows[i], f.rows[i]
    if r then
      row.name:SetText((COLORS[r.diff] or "") .. r.name .. "|r" .. (r.diff == 1 and "  (not certain)" or ""))
      row.pay:SetText(CP.Money(r.pay))
      row.net:SetText(CP.Money(r.net))
      row.can:SetText(tostring(r.can))
      row:Show()
    else
      row:Hide()
    end
  end
  f.note:SetText(noprice > 0 and (noprice .. " craft(s) left out: a material has no price. Scan the auction house.") or "")
end

local function Create()
  local f = CreateFrame("Frame", "ProfiteerLevelFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  V.frame = f
  if CP.WinLook then CP.WinLook.Attach("level", f) end
  f:SetSize(560, 400)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetDrawLayer("BACKGROUND", 1)
  bg:SetPoint("TOPLEFT", 8, -8)
  bg:SetPoint("BOTTOMRIGHT", -8, 8)
  bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(UISpecialFrames, "ProfiteerLevelFrame")

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Level up")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  f.closeBtn = close

  f.prof = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.prof:SetPoint("TOPLEFT", 24, -44)
  local nextB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  nextB:SetSize(110, 22)
  nextB:SetPoint("TOPRIGHT", -40, -40)
  nextB:SetText("Next profession")
  nextB:SetScript("OnClick", function()
    local p = Professions()
    for i, name in ipairs(p) do if name == V.cur then V.cur = p[i % #p + 1] break end end
    V.Refresh()
  end)

  f.head = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.head:SetPoint("TOPLEFT", 24, -70)
  f.head:SetWidth(510)
  f.head:SetJustifyH("LEFT")
  f.pick = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.pick:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -6)
  f.pick:SetWidth(510)
  f.pick:SetJustifyH("LEFT")

  local function Head(text, x, w, just)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, -130)
    fs:SetWidth(w)
    fs:SetJustifyH(just or "LEFT")
    fs:SetText(text)
  end
  Head("Craft", 24, 270)
  Head("You pay", 300, 80, "RIGHT")
  Head("Net cost", 385, 80, "RIGHT")
  Head("You can make", 470, 70, "RIGHT")

  f.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(520, 18)
    row:SetPoint("TOPLEFT", 24, -146 - (i - 1) * 18)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(270)
    row.name:SetJustifyH("LEFT")
    row.pay = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.pay:SetPoint("LEFT", 276, 0)
    row.pay:SetWidth(80)
    row.pay:SetJustifyH("RIGHT")
    row.net = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.net:SetPoint("LEFT", 361, 0)
    row.net:SetWidth(80)
    row.net:SetJustifyH("RIGHT")
    row.can = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.can:SetPoint("LEFT", 446, 0)
    row.can:SetWidth(70)
    row.can:SetJustifyH("RIGHT")
    f.rows[i] = row
  end
  f.note = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.note:SetPoint("BOTTOMLEFT", 24, 18)
  f.note:SetWidth(510)
  f.note:SetJustifyH("LEFT")
  f:HookScript("OnShow", V.Refresh)
end

function V.Toggle()
  if not V.frame then Create() end
  if V.frame:IsShown() then V.frame:Hide() else V.frame:Show() end
end

-- a button on the game's profession window
local btnDone
local function AddButton()
  if btnDone then return end
  local parent = _G.TradeSkillFrame or _G.ProfessionsFrame
  if not parent then return end
  btnDone = true
  local b = CreateFrame("Button", "ProfiteerLevelButton", parent, "UIPanelButtonTemplate")
  b:SetSize(80, 20)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -30)
  b:SetText("Level up")
  b:SetScript("OnClick", function() V.Toggle() end)
end
local bf = CreateFrame("Frame")
CP.Register(bf, "TRADE_SKILL_SHOW")
CP.Register(bf, "ADDON_LOADED")
bf:SetScript("OnEvent", function() pcall(AddButton) end)
