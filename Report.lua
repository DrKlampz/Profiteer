local ADDON, CP = ...
local R = {}
CP.Report = R

-- /pf report opens a box with everything needed to diagnose a problem. Press
-- Ctrl+C (the text is pre-selected), then paste it wherever you're getting help.

local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

function R.Lines()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local version, build, _, iface = GetBuildInfo()
  local s = CP.db.settings

  add(("Profiteer %s | client %s (%s) interface %s"):format(CP.version, tostring(version), tostring(build), tostring(iface)))
  local function has(label, ok) add(("  %-40s %s"):format(label, ok and "yes" or "MISSING")) end
  has("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs)
  has("C_TradeSkillUI.GetRecipeSchematic", C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)
  has("C_AuctionHouse.ReplicateItems", C_AuctionHouse and C_AuctionHouse.ReplicateItems)
  has("C_AuctionHouse.GetReplicateItemInfo", C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo)
  has("C_Container", C_Container)
  has("TooltipDataProcessor", TooltipDataProcessor)
  has("AuctionHouseFrame", AuctionHouseFrame)

  add(("Data: %d chars, %d priced items, %d with history, last scan %s"):format(
    Count(CP.db.chars), Count(CP.db.prices), Count(CP.db.history), CP.Age(CP.db.lastScan)))
  local tracked = 0
  do
    local seen = {}
    for _, profs in pairs(CP.db.recipes) do
      for _, recs in pairs(profs) do
        for _, r in ipairs(recs) do
          seen[r.id] = true
          for _, g in ipairs(r.reagents) do for _, id in ipairs(g.ids or { g.id }) do seen[id] = true end end
        end
      end
    end
    tracked = Count(seen)
  end
  add(("Recipe items tracked for history: %d | history entries: %d | sales snapshots: %d"):format(
    tracked, Count(CP.db.history), Count(CP.db.listings)))
  do
    local parts = {}
    for charKey, inv in pairs(CP.db.inventory) do
      parts[#parts + 1] = CP.ShortName(charKey) .. " " .. CP.Age(inv.time)
    end
    add("Bags seen: " .. (#parts > 0 and table.concat(parts, ", ") or "no characters yet"))
  end
  add(("Saved-data loads: %d (created %s). Stuck at 1 after relogging = SavedVariables not restored."):format(
    CP.db.sessions or 0, date and date("%Y-%m-%d %H:%M", CP.db.created or 0) or "?"))
  add(("Settings: cut %s%%, basis %s, unit=%s, autoscan=%s, tooltips=%s"):format(
    s.ahCut * 100, s.priceBasis, s.replicateUnit, tostring(s.autoScan), tostring(s.tooltips)))

  for charKey, profs in pairs(CP.db.recipes) do
    for prof, list in pairs(profs) do add(("Recipes: %s / %s = %d"):format(CP.ShortName(charKey), prof, #list)) end
  end

  -- one sample recipe, raw, to check the reagent data looks sane
  for _, profs in pairs(CP.db.recipes) do
    for prof, list in pairs(profs) do
      local r = list[1]
      if r then
        local parts = {}
        for _, g in ipairs(r.reagents) do parts[#parts + 1] = g.count .. "x{" .. table.concat(g.ids or { g.id }, ",") .. "}" end
        add(("Sample recipe (%s): %s -> item %s x%s from %s"):format(prof, r.name, tostring(r.id), tostring(r.yield), table.concat(parts, " ")))
      end
      break
    end
    break
  end

  -- a couple of stored prices
  local shown = 0
  for id, p in pairs(CP.db.prices) do
    add(("Sample price: item %d min=%s ref=%s listings=%s units=%s"):format(id, tostring(p.min), tostring(p.ref), tostring(p.n), tostring(p.qty)))
    shown = shown + 1
    if shown >= 3 then break end
  end

  -- raw rows from the client's last full scan
  if C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems then
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    add("Raw scan rows held by client: " .. n)
    for i = 0, math.min(n - 1, 4) do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = C_AuctionHouse.GetReplicateItemInfo(i)
      add(("  row %d: item %s count=%s buyout=%s"):format(i, tostring(id), tostring(count), tostring(buyout)))
    end
  end

  if #CP.errors == 0 then
    add("Errors this session: none")
  else
    add("Errors this session:")
    for i, e in ipairs(CP.errors) do add("  " .. i .. ". " .. e) end
  end
  return L
end

-- Opens a copyable text window (scroll with the mouse wheel; text is pre-selected so
-- Ctrl+C copies everything).
function R.Open(title, lines, hint)
  if not R.frame then
    local f = CreateFrame("Frame", "ProfiteerReportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    R.frame = f
    f:SetSize(640, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetDrawLayer("BACKGROUND", 1)
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    table.insert(UISpecialFrames, "ProfiteerReportFrame")

    R.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    R.title:SetPoint("TOP", 0, -16)
    R.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    R.hint:SetPoint("TOP", 0, -38)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 24, -58)
    scroll:SetSize(590, 280)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local cur, max = self:GetVerticalScroll(), self:GetVerticalScrollRange()
      if type(cur) ~= "number" or type(max) ~= "number" then return end
      self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 42)))
    end)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    eb:SetWidth(580)
    eb:SetHeight(280)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(eb)
    R.scroll, R.edit = scroll, eb
  end

  R.title:SetText(title or "Profiteer")
  R.hint:SetText(hint or "Ctrl+C copies everything. Scroll with the mouse wheel.")
  R.edit:SetText(table.concat(lines, "\n"))
  R.edit:SetHeight(math.max(280, #lines * 16 + 24))
  R.scroll:SetVerticalScroll(0)
  R.frame:Show()
  R.edit:SetFocus()
  R.edit:HighlightText()
end

function R.Show()
  R.Open("Profiteer report", R.Lines(), "Press Ctrl+C to copy, then paste it where you're getting help.")
end
