local ADDON, CP = ...

-- Captures every recipe you know, per character, whenever a profession window
-- opens. Uses the modern C_TradeSkillUI API (what WoW Forever runs); falls
-- back to the old GetTradeSkill* API if that's all the client has.
--
-- Each recipe: { id = output item, name, yield, reagents = { { ids = {itemID,..}, count } } }
-- A reagent slot can list several item IDs (e.g. quality tiers); the analyzer
-- prices the slot using the cheapest one.

local capturing, pending = false, false
local ignoreUntil = 0

local function Store(prof, list, skipped)
  if #list == 0 then return end
  local mine = CP.db.recipes[CP.charKey]
  if not mine then mine = {}; CP.db.recipes[CP.charKey] = mine end
  local prev = mine[prof]
  mine[prof] = list
  if not prev or #prev ~= #list then
    local extra = skipped > 0 and (" (" .. skipped .. " skipped: no sellable output or item data not loaded)") or ""
    CP:Print(("Captured %d %s recipes for %s%s"):format(#list, prof, CP.ShortName(CP.charKey), extra))
    CP:Refresh()
  end
end

------------------------------------------------------------------------
-- Modern API
------------------------------------------------------------------------
local function ProfessionName()
  local T = C_TradeSkillUI
  local name
  if T.GetBaseProfessionInfo then
    local info = T.GetBaseProfessionInfo()
    name = info and info.professionName
  end
  if (not name or name == "") and T.GetTradeSkillLine then
    local _, n = T.GetTradeSkillLine()
    name = n
  end
  return name
end

local function CaptureModern()
  local T = C_TradeSkillUI
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
  if T.IsNPCCrafting and T.IsNPCCrafting() then return end

  local prof = ProfessionName()
  if not prof or prof == "" then return end

  local ids = T.GetAllRecipeIDs()
  if not ids or #ids == 0 then return end

  local Basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  local list, skipped = {}, 0

  for _, rid in ipairs(ids) do
    local info = T.GetRecipeInfo(rid)
    if info and info.learned then
      local sch = T.GetRecipeSchematic(rid, false)
      local outID = sch and sch.outputItemID
      if outID then
        local reagents = {}
        for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
          -- only mandatory (basic) reagent slots count toward cost
          if Basic == nil or slot.reagentType == nil or slot.reagentType == Basic then
            local opts = {}
            for _, rg in ipairs(slot.reagents or {}) do
              if rg.itemID then opts[#opts + 1] = rg.itemID end
            end
            if #opts > 0 and (slot.quantityRequired or 0) > 0 then
              reagents[#reagents + 1] = { ids = opts, id = opts[1], count = slot.quantityRequired }
            end
          end
        end
        if #reagents > 0 then
          local lo, hi = sch.quantityMin or 1, sch.quantityMax or sch.quantityMin or 1
          -- The recipe's name is not the item's name ("Smelt Copper" makes Copper Bar).
          -- Only the game's real item name is saved as the item's name.
          local itemName = CP.RealItemName(outID)
          if itemName then CP.db.names[outID] = itemName end
          local name = itemName or info.name or ("item " .. outID)
          list[#list + 1] = { id = outID, name = name, rname = info.name, yield = (lo + hi) / 2, reagents = reagents }
        else
          skipped = skipped + 1
        end
      else
        skipped = skipped + 1   -- enchants and other non-item crafts
      end
    end
  end

  Store(prof, list, skipped)
end

------------------------------------------------------------------------
-- Legacy API (old GetTradeSkill* functions)
------------------------------------------------------------------------
local function CaptureLegacy()
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local prof = GetTradeSkillLine()
  local n = GetNumTradeSkills()
  if not prof or prof == "UNKNOWN" or not n or n == 0 then return end

  local collapsed = {}
  for i = n, 1, -1 do
    local name, kind, _, isExpanded = GetTradeSkillInfo(i)
    if kind == "header" and not isExpanded then
      collapsed[#collapsed + 1] = name
      ExpandTradeSkillSubClass(i)
    end
  end

  local list, skipped = {}, 0
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local outID = CP.ItemID(GetTradeSkillItemLink(i))
      if outID then
        local lo, hi = 1, 1
        if GetTradeSkillNumMade then lo, hi = GetTradeSkillNumMade(i) end
        lo = lo or 1; hi = hi or lo
        local reagents, ok = {}, true
        for r = 1, GetTradeSkillNumReagents(i) do
          local rname, _, count = GetTradeSkillReagentInfo(i, r)
          local rid = CP.ItemID(GetTradeSkillReagentItemLink(i, r))
          if rid and rname and count then
            reagents[#reagents + 1] = { ids = { rid }, id = rid, count = count }
            CP.db.names[rid] = rname
          else ok = false end
        end
        if ok and #reagents > 0 then
          local itemName = CP.RealItemName(outID)
          if itemName then CP.db.names[outID] = itemName end
          list[#list + 1] = { id = outID, name = itemName or name, rname = name, yield = (lo + hi) / 2, reagents = reagents }
        else skipped = skipped + 1 end
      end
    end
  end

  for _, hname in ipairs(collapsed) do
    for i = 1, GetNumTradeSkills() do
      local name, kind, _, isExpanded = GetTradeSkillInfo(i)
      if kind == "header" and name == hname and isExpanded then
        CollapseTradeSkillSubClass(i)
        break
      end
    end
  end

  Store(prof, list, skipped)
end

------------------------------------------------------------------------
-- Driver
------------------------------------------------------------------------
local function Capture()
  pending = false
  if capturing or not CP.db or not CP.charKey then return end
  capturing = true
  local ok, err = true, nil
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
    ok, err = pcall(CaptureModern)
  elseif GetNumTradeSkills then
    ok, err = pcall(CaptureLegacy)
  end
  capturing = false
  ignoreUntil = GetTime() + 2
  if not ok then CP.RecordError("recipe capture", err) end
end

local f = CreateFrame("Frame")
CP.Register(f, "TRADE_SKILL_SHOW")
CP.Register(f, "TRADE_SKILL_LIST_UPDATE")
CP.Register(f, "TRADE_SKILL_DATA_SOURCE_CHANGED")
CP.Register(f, "TRADE_SKILL_UPDATE")   -- legacy clients
f:SetScript("OnEvent", function(_, event)
  if capturing then return end
  if event ~= "TRADE_SKILL_SHOW" and GetTime() < ignoreUntil then return end
  if event == "TRADE_SKILL_SHOW" then ignoreUntil = 0 end
  if not pending then
    pending = true
    CP.After(0.6, Capture)
  end
end)
