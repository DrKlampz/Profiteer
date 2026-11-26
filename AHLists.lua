local ADDON, CP = ...
-- Shopping lists: a few ready-made ones (herbs, ores and bars, ...) and the player's own, saved by name.
local H = CP.AH
local Lists = {}
CP.AHLists = Lists

-- ready-made lists: item ids, each wanted 20 at a time (the How many box and Buy up to still apply)
local BUILTIN = {
  { "Herbs and alchemy", { 2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468, 3371, 3372, 8925, 18256, 7078, 7076, 7080, 7082, 12808, 7068, 7067, 7069, 7070 } },
  { "Ores, stone and bars", { 2770, 2771, 2772, 3858, 10620, 2776, 2775, 7911, 2835, 2836, 2838, 7912, 12365, 2840, 3576, 2841, 3575, 3859, 3577, 2842, 3860, 6037, 12359 } },
  { "Cloth, leather and hides", { 2589, 2592, 4306, 4338, 14047, 2996, 2997, 4305, 4339, 14048, 2934, 2318, 2319, 4234, 4304, 8170, 783, 4232, 4235, 8169, 8171 } },
  { "Gems", { 774, 818, 1210, 1206, 1705, 1529, 3864, 7909, 7910, 12361, 12364, 12363, 12799, 12800 } },
  { "Enchanting materials", { 10940, 11083, 11137, 11176, 16204, 10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725 } },
  { "Mage scrolls (learned, not sold by vendors)", { 213548, 213550, 211800, 213564, 215257, 211954, 211957, 211955, 211956, 211953, 217496, 223171, 220792, 217495 } },
  { "Mage scrolls: unread (decipher with a Comprehension Charm)", { 211786, 211785, 211780, 211787, 211854, 211853, 211784, 211855, 213543, 213544, 213545, 213546, 213547 } },
  { "Fish and cooking", { 6291, 6303, 6289, 6361, 6308, 6359, 13754, 13758, 13760, 769, 731, 1015, 1080, 1081, 2672, 2673, 2674, 2675, 2677, 2886, 2678, 2692, 2287, 3173, 3667, 3712, 3730, 3731, 12037, 12202, 12203, 12204, 12205, 12208 } },
}

local function Known(id)
  if GetItemInfoInstant then local ok, v = pcall(GetItemInfoInstant, id) return ok and v ~= nil end
  return true
end

local function Entries(ids, want)
  local out = {}
  for _, id in ipairs(ids) do
    if Known(id) then
      out[#out + 1] = { id = id, want = want or 20 }
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
  end
  return out
end

-- consumables: built from every craft the add-on knows about (all professions, plus the recipes your characters
-- captured), keeping the ones the game classes as consumables, grouped by kind and ordered by the skill they need
local KIND = { [1] = "Potions", [2] = "Elixirs", [3] = "Flasks", [4] = "Scrolls", [5] = "Food and drink", [7] = "Bandages" }
local KIND_ORDER = { "Potions", "Elixirs", "Flasks", "Scrolls", "Food and drink", "Bandages", "Other" }
local PROF_ORDER = { "Alchemy", "Cooking", "First Aid", "Engineering", "Blacksmithing", "Enchanting", "Leatherworking", "Tailoring", "Jewelcrafting", "Inscription", "Mining", "Smelting", "Poisons", "Other crafts" }
local consumableCache, consumableCount
-- one name per profession: the game and the saved recipes spell some differently ("FirstAid" and "First Aid")
local function CanonProf(prof)
  local key = tostring(prof or ""):gsub("%s+", ""):lower()
  for _, name in ipairs(PROF_ORDER) do
    if (name:gsub("%s+", ""):lower()) == key then return name end
  end
  return prof
end

local function ItemClass(id)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, _, _, _, _, _, classID, subID = pcall(fn, id)
  if ok then return classID, subID end
end

local function Consumables()
  local total = 0
  for _, profs in pairs(CP.db and CP.db.recipes or {}) do
    for _, list in pairs(profs) do total = total + #list end
  end
  if consumableCache and consumableCount == total then return consumableCache end
  local best = {}   -- item id -> { lowest skill that crafts it, the profession }
  local function note(id, skill, prof)
    if not id or id == 0 then return end
    prof = CanonProf(prof)
    local b = best[id]
    if not b then best[id] = { skill = skill or 0, prof = prof }
    elseif (skill or 0) < b.skill then b.skill, b.prof = skill or 0, prof end
  end
  for prof, crafts in pairs(CP.AllCrafts or {}) do
    for _, c in ipairs(crafts) do note(c[2], c[3], prof) end
  end
  for _, profs in pairs(CP.db and CP.db.recipes or {}) do
    for prof, list in pairs(profs) do
      for _, r in ipairs(list) do note(r.id, nil, prof) end
    end
  end
  local consumableClass = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
  local buckets = {}   -- "Prof|Kind" -> { prof, kind, items }
  for id, b in pairs(best) do
    local cls, sub = ItemClass(id)
    if cls == consumableClass then
      local prof = b.prof or "Other crafts"
      local kind = KIND[sub or 0] or "Other"
      local key = prof .. "|" .. kind
      local bk = buckets[key]
      if not bk then bk = { prof = prof, kind = kind, items = {} } buckets[key] = bk end
      bk.items[#bk.items + 1] = { id = id, skill = b.skill }
    end
  end
  local function Rank(list, v) for i, x in ipairs(list) do if x == v then return i end end return #list + 1 end
  local sorted = {}
  for _, bk in pairs(buckets) do sorted[#sorted + 1] = bk end
  table.sort(sorted, function(x, y)
    local px, py = Rank(PROF_ORDER, x.prof), Rank(PROF_ORDER, y.prof)
    if px ~= py then return px < py end
    if px > #PROF_ORDER and x.prof ~= y.prof then return x.prof < y.prof end
    return Rank(KIND_ORDER, x.kind) < Rank(KIND_ORDER, y.kind)
  end)
  local out = {}
  for _, bk in ipairs(sorted) do
    table.sort(bk.items, function(x, y) if x.skill ~= y.skill then return x.skill < y.skill end return x.id < y.id end)
    local ids = {}
    for _, e in ipairs(bk.items) do ids[#ids + 1] = e.id end
    out[#out + 1] = { bk.prof .. ": " .. bk.kind, ids }
  end
  consumableCache, consumableCount = out, total
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
local menu, catcher, box
local function Close() if menu then menu:Hide() end if catcher then catcher:Hide() end end
local function Closeall() Close() if box then box:Hide() end end
-- the pop-ups belong to the pane that opened them, so they go away with it (closing the auction house, changing tab)
local function Adopt(frame, anchor)
  local pane = anchor and anchor:GetParent()
  if not pane then return end
  frame:SetParent(pane)
  if not pane.pfListsHooked then
    pane.pfListsHooked = true
    pane:HookScript("OnHide", Closeall)
  end
end

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
  Adopt(menu, anchor)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetParent(menu:GetParent() or UIParent)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu.filter:SetText("")
  Lists.Fill()
  catcher:Show()
  menu:Show()
end

-- The menu is grouped: your own lists, the ready-made ones, then one folded group per profession for the consumables.
-- Click a group's heading to open or fold it; typing in the search box opens everything that matches.
local collapsed = {}      -- group title -> true when folded (professions start folded)
local function Folded(title, q)
  if q ~= "" then return false end
  local c = collapsed[title]
  if c == nil then return title ~= "Your lists" and title ~= "Ready-made" end
  return c
end

function Lists.Fill()
  local q = (menu.filter:GetText() or ""):lower()
  local groups, byTitle = {}, {}
  local function group(title)
    local g = byTitle[title]
    if not g then g = { title = title, items = {} } byTitle[title] = g groups[#groups + 1] = g end
    return g
  end
  local function match(name) return q == "" or name:lower():find(q, 1, true) end
  local names = {}
  for n in pairs(Mine()) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  for _, n in ipairs(names) do if match(n) then local g = group("Your lists") g.items[#g.items + 1] = { name = n, label = n, kind = "mine", entries = Mine()[n] } end end
  for _, b in ipairs(BUILTIN) do if match(b[1]) then local g = group("Ready-made") g.items[#g.items + 1] = { name = b[1], label = b[1], kind = "built", entries = Entries(b[2]) } end end
  for _, b in ipairs(Consumables()) do
    if match(b[1]) then
      local prof, kind = b[1]:match("^(.-): (.+)$")
      local g = group(prof or "Other")
      g.items[#g.items + 1] = { name = b[1], label = kind or b[1], kind = "built", entries = Entries(b[2]) }
    end
  end
  local flat = {}
  for _, g in ipairs(groups) do
    local fold = Folded(g.title, q)
    flat[#flat + 1] = { header = true, title = g.title, count = #g.items, fold = fold }
    if not fold then for _, it in ipairs(g.items) do flat[#flat + 1] = it end end
  end
  for i = 1, math.max(#flat, #menu.rows) do
    local it, r = flat[i], Row(i)
    if it and it.header then
      r.fs:SetText(("|cffffd100%s %s|r |cff888888(%d)|r"):format(it.fold and "+" or "-", it.title, it.count))
      r:SetScript("OnClick", function() collapsed[it.title] = not it.fold Lists.Fill() end)
      r:Show()
    elseif it then
      r.fs:SetText("    " .. (it.kind == "mine" and "|cffffd100" or "") .. it.label .. (it.kind == "mine" and "|r  |cff888888(" .. #it.entries .. ")|r" or ""))
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
  menu:SetHeight(30 + math.max(1, #flat) * 20 + 22)
end

------------------------------------------------------------------------
-- save box
------------------------------------------------------------------------
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
  Adopt(box, anchor)
  box:SetFrameStrata("FULLSCREEN_DIALOG")
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  box.msg:SetText("")
  box.edit:SetText(defaultName or "")
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
end
