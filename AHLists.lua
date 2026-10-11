local ADDON, CP = ...
-- Shopping lists: a few ready-made ones (herbs, ores and bars, ...) and the player's own, saved by name.
local H = CP.AH
local Lists = {}
CP.AHLists = Lists

-- ready-made lists: item ids, each wanted 20 at a time (the How many box and Buy up to still apply)
local BUILTIN = {
  { "Herbs", { 2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468 } },
  { "Ores and stone", { 2770, 2771, 2772, 3858, 10620, 2776, 2775, 7911, 2835, 2836, 2838, 7912, 12365 } },
  { "Bars", { 2840, 3576, 2841, 3575, 3859, 3577, 2842, 3860, 6037, 12359 } },
  { "Leather and hides", { 2934, 2318, 2319, 4234, 4304, 8170, 783, 4232, 4235, 8169, 8171 } },
  { "Cloth and bolts", { 2589, 2592, 4306, 4338, 14047, 2996, 2997, 4305, 4339, 14048 } },
  { "Gems", { 774, 818, 1210, 1206, 1705, 1529, 3864, 7909, 7910, 12361, 12364, 12363, 12799, 12800 } },
  { "Enchanting materials", { 10940, 11083, 11137, 11176, 16204, 10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725 } },
  { "Elemental reagents", { 7078, 7076, 7080, 7082, 12808, 7068, 7067, 7069, 7070 } },
  { "Fish", { 6291, 6303, 6289, 6361, 6308, 6359, 13754, 13758, 13760 } },
}

local function Known(id)
  if GetItemInfoInstant then local ok, v = pcall(GetItemInfoInstant, id) return ok and v ~= nil end
  return true
end

local function Entries(ids, want)
  local out = {}
  for _, id in ipairs(ids) do
    if Known(id) then out[#out + 1] = { id = id, want = want or 20 } end
  end
  return out
end

local function Mine()
  CP.db.shopLists = CP.db.shopLists or {}
  return CP.db.shopLists
end

function Lists.Save(name, entries)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false, "Give the list a name." end
  if #entries == 0 then return false, "The list is empty." end
  local copy = {}
  for _, e in ipairs(entries) do copy[#copy + 1] = { id = e.id, want = e.want or 1 } end
  Mine()[name] = copy
  return true, name
end

function Lists.Delete(name) Mine()[name] = nil end

------------------------------------------------------------------------
-- the menu
------------------------------------------------------------------------
local menu, catcher
local function Close() if menu then menu:Hide() end if catcher then catcher:Hide() end end

local function Row(i)
  local r = menu.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, menu)
  r:SetHeight(20)
  r:SetPoint("TOPLEFT", 6, -30 - (i - 1) * 20)
  r:SetPoint("TOPRIGHT", -6, -30 - (i - 1) * 20)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT") r.hl:SetAllPoints() r.hl:SetColorTexture(1, 1, 1, 0.10)
  r.fs = H.Text(r, "GameFontHighlightSmall") r.fs:SetPoint("LEFT", 6, 0) r.fs:SetPoint("RIGHT", -6, 0) r.fs:SetJustifyH("LEFT")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  menu.rows[i] = r
  return r
end

function Lists.Open(anchor, onPick)
  if not menu then
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetScript("OnClick", Close)
    catcher:Hide()
    menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetWidth(250)
    menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    menu:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    menu:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    menu.rows = {}
    menu.title = H.Text(menu, "GameFontNormal") menu.title:SetPoint("TOPLEFT", 10, -9) menu.title:SetText("Shopping lists")
    menu.filter = H.Edit(menu, 90)
    menu.filter:SetPoint("TOPRIGHT", -10, -5)
    menu.filter:SetScript("OnTextChanged", function(self, user) if user then Lists.Fill() end end)
    menu.foot = H.Text(menu, "GameFontDisableSmall") menu.foot:SetPoint("BOTTOMLEFT", 10, 6)
    menu.foot:SetText("Right-click one of yours to delete it.")
    menu:Hide()
  end
  menu.onPick = onPick
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu.filter:SetText("")
  Lists.Fill()
  catcher:Show()
  menu:Show()
end

function Lists.Fill()
  local q = (menu.filter:GetText() or ""):lower()
  local items = {}
  local function add(name, kind, entries) if q == "" or name:lower():find(q, 1, true) then items[#items + 1] = { name = name, kind = kind, entries = entries } end end
  local names = {}
  for n in pairs(Mine()) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  for _, n in ipairs(names) do add(n, "mine", Mine()[n]) end
  for _, b in ipairs(BUILTIN) do add(b[1], "built", Entries(b[2])) end
  for i = 1, math.max(#items, #menu.rows) do
    local it, r = items[i], Row(i)
    if it then
      r.fs:SetText((it.kind == "mine" and "|cffffd100" or "") .. it.name .. (it.kind == "mine" and "|r  |cff888888(" .. #it.entries .. ")|r" or ""))
      r:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" and it.kind == "mine" then
          Lists.Delete(it.name)
          Lists.Fill()
          return
        end
        Close()
        if menu.onPick then menu.onPick(it.entries, it.name) end
      end)
      r:Show()
    else
      r:Hide()
    end
  end
  menu:SetHeight(30 + math.max(1, #items) * 20 + 22)
end

------------------------------------------------------------------------
-- save box
------------------------------------------------------------------------
local box
function Lists.AskSave(anchor, getEntries, defaultName, onSaved)
  if not box then
    box = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetSize(250, 74)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    box:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    local t = H.Text(box, "GameFontNormal") t:SetPoint("TOPLEFT", 10, -9) t:SetText("Save this list as")
    box.edit = H.Edit(box, 150)
    box.edit:SetMaxLetters(30)
    box.edit:SetPoint("TOPLEFT", 14, -30)
    box.ok = H.Button(box, "Save", 60, 22)
    box.ok:SetPoint("LEFT", box.edit, "RIGHT", 8, 0)
    box.msg = H.Text(box, "GameFontDisableSmall") box.msg:SetPoint("BOTTOMLEFT", 10, 6)
    local function Do()
      local ok, res = Lists.Save(box.edit:GetText(), box.getEntries())
      if ok then box:Hide() if box.onSaved then box.onSaved(res) end else box.msg:SetText(res) end
    end
    box.ok:SetScript("OnClick", Do)
    box.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() Do() end)
    box.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() box:Hide() end)
    box:Hide()
  end
  box.getEntries, box.onSaved = getEntries, onSaved
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  box.msg:SetText("")
  box.edit:SetText(defaultName or "")
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
end
