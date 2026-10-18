local ADDON, CP = ...

-- Learned-recipe tracker. Every time a profession window opens, every recipe it lists is saved by name for
-- this character, as learned or not learned (this includes enchants, which have no crafted item). A recipe
-- item's tooltip (a Recipe, Pattern, Formula, Plans...) then lists which of your characters already know it,
-- which could still learn it, and which don't have that profession.

local L = {}
CP.Learned = L

local function Norm(s)
  s = tostring(s or ""):lower()
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- "Recipe: Elixir of Fortitude" -> "elixir of fortitude"
local function BaseName(itemName)
  return Norm(itemName:match("^[^:]+:%s*(.+)$") or itemName)
end

-- Called by the recipe capture: names = { [normalized recipe name] = true (learned) / false }
function L.Note(prof, names)
  if not CP.db or not CP.charKey or not prof or prof == "" then return end
  CP.db.rnames = CP.db.rnames or {}
  local mine = CP.db.rnames[CP.charKey]
  if not mine then mine = {}; CP.db.rnames[CP.charKey] = mine end
  mine[prof] = names
end
L.Norm = Norm

-- a recipe learned from a looted item shows up without the profession window being opened
local function MarkLearned(recipeID)
  if not (CP.db and CP.charKey and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return end
  local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
  if not ok or type(info) ~= "table" or not info.name then return end
  local key = Norm(info.name)
  local mine = CP.db.rnames and CP.db.rnames[CP.charKey]
  if not mine then return end
  local hit = false
  for _, names in pairs(mine) do
    if names[key] ~= nil then names[key] = true hit = true end
  end
  if not hit then
    -- not in any saved list: add it under the profession the game names, if it names one
    local prof
    if C_TradeSkillUI.GetTradeSkillLineForRecipe and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
      local ok2, line = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
      if ok2 and line then
        local ok3, p = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
        if ok3 and type(p) == "table" then prof = p.professionName end
      end
    end
    if prof and mine[prof] then mine[prof][key] = true end
  end
end

local ev = CreateFrame("Frame")
CP.Register(ev, "NEW_RECIPE_LEARNED")
ev:SetScript("OnEvent", function(_, event, rid)
  if event == "NEW_RECIPE_LEARNED" and rid then
    CP.After(0.5, function() local ok, err = pcall(MarkLearned, rid) if not ok then CP.RecordError("recipe learned", err) end end)
  end
end)

local function ClassColor(ck)
  local c = CP.db.chars and CP.db.chars[ck]
  local col = c and c.class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[c.class]
  if col then return col.r, col.g, col.b end
  return 1, 1, 1
end

-- what one character knows about this recipe: "knows", "needs", or nil (no such profession)
local function Status(ck, prof, key)
  local d = CP.db
  local names = d.rnames and d.rnames[ck] and d.rnames[ck][prof]
  if names then
    if names[key] == true then return "knows" end
    return "needs"
  end
  -- older saves (before names were kept): the learned list only
  local list = d.recipes and d.recipes[ck] and d.recipes[ck][prof]
  if list then
    for _, r in ipairs(list) do
      if Norm(r.rname) == key or Norm(r.name) == key then return "knows" end
    end
    return "needs"
  end
  if d.unlearned and d.unlearned[ck] and d.unlearned[ck][prof] then return "needs" end
  return nil
end

function L.Tip(tip, id)
  local d = CP.db
  if not d or d.settings.recipeTips == false or not id then return end
  if not (C_Item and C_Item.GetItemInfoInstant) then return end
  local _, _, sub, _, _, class = C_Item.GetItemInfoInstant(id)
  local recipeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
  if class ~= recipeClass or not sub then return end
  local name = CP.RealItemName(id)
  if not name then return end
  local key = BaseName(name)

  local keys = {}
  for ck in pairs(d.chars or {}) do keys[#keys + 1] = ck end
  table.sort(keys, function(a, b)
    if a == CP.charKey then return true elseif b == CP.charKey then return false end
    return CP.ShortName(a):lower() < CP.ShortName(b):lower()
  end)

  local knows, needs, lacks = {}, {}, {}
  for _, ck in ipairs(keys) do
    local s = Status(ck, sub, key)
    if s == "knows" then knows[#knows + 1] = ck
    elseif s == "needs" then needs[#needs + 1] = ck
    else lacks[#lacks + 1] = ck end
  end
  if #knows == 0 and #needs == 0 and #lacks == 0 then return end

  tip:AddLine(" ")
  tip:AddLine("Recipe tracker (" .. sub .. ")", 0.2, 1, 0.6)
  for _, ck in ipairs(knows) do
    local r, g, b = ClassColor(ck)
    tip:AddDoubleLine(CP.ShortName(ck), "Already knows it", r, g, b, 0.4, 1, 0.4)
  end
  for _, ck in ipairs(needs) do
    local r, g, b = ClassColor(ck)
    tip:AddDoubleLine(CP.ShortName(ck), "Can learn it", r, g, b, 1, 0.82, 0.1)
  end
  if #lacks > 0 then
    local t = {}
    for _, ck in ipairs(lacks) do t[#t + 1] = CP.ShortName(ck) end
    tip:AddLine("No " .. sub .. " recorded: " .. table.concat(t, ", "), 0.6, 0.6, 0.6, true)
  end
  if #needs == 0 and #knows > 0 then
    tip:AddLine("Nobody else needs this one.", 0.6, 0.6, 0.6)
  end
end

-- how many characters have recorded recipe names, for /pf recipes
function L.Summary()
  local lines = {}
  local d = CP.db
  for ck, profs in pairs(d.rnames or {}) do
    local parts = {}
    for prof, names in pairs(profs) do
      local k, n = 0, 0
      for _, v in pairs(names) do n = n + 1 if v then k = k + 1 end end
      parts[#parts + 1] = ("%s %d/%d"):format(prof, k, n)
    end
    table.sort(parts)
    lines[#lines + 1] = CP.ShortName(ck) .. ": " .. table.concat(parts, ", ")
  end
  table.sort(lines)
  return lines
end
