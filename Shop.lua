local ADDON, CP = ...
local Shop = {}
CP.Shop = Shop

-- Turns a craft into AH searches, and lets you pin ("track") crafts.
--
-- Search order:
--   1. Auctionator's public search API (a Shopping list built from the item names)
--   2. The Auction House's own search bar (one item at a time)
--   3. A copyable window with the names, if neither can be driven on this client

local CALLER = "Profiteer"

-- Always the game's real item name when the client has it; a saved name is only a fallback.
local function ItemNameOrNil(id)
  local n = CP.RealItemName(id)
  if n then return n end
  return CP.db.names[id]
end

-- Names of the materials for one craft (cheapest option per slot)
-- Intermediates are searched both ways: the bar and the ore it is smelted from, so you can
-- buy whichever is cheaper.
function Shop.Materials(g)
  local names, unresolved, seen = {}, 0, {}
  local function add(id)
    if CP.db.vendor[id] then return end   -- a vendor sells it: buy it there, no AH search
    local n = ItemNameOrNil(id)
    if not n then unresolved = unresolved + 1 return end
    if not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  CP:IndexMakers()
  for _, rg in ipairs(g.reagents) do
    local _, src, id = CP:SlotCost(rg)
    id = id or rg.id
    add(id)
    if src ~= "vendor" and CP:MakePlan(id) then
      for _, raw in ipairs(CP:RawMaterials(id)) do add(raw.id) end
    end
  end
  return names, unresolved
end

local function HidePanel()
  local f = CP.UI and CP.UI.frame
  -- stays open by default so you can keep clicking crafts; settings.hideOnSearch restores the old behaviour
  if CP.db.settings.hideOnSearch and f and f.docked and f:IsShown() then f:Hide() end
end

function Shop.Search(terms, label)
  local seen, list = {}, {}
  for _, t in ipairs(terms) do
    if t and not seen[t] then seen[t] = true; list[#list + 1] = t end
  end
  if #list == 0 then CP:Print("Nothing to search for."); return false end

  if not CP.Scanner.IsAHOpen() then
    CP:Print("Open the Auction House first, then try again.")
    return false
  end

  -- 1. Auctionator
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if A then
    for _, fnName in ipairs({ "MultiSearchExact", "MultiSearch" }) do
      if type(A[fnName]) == "function" then
        local ok, err = pcall(A[fnName], CALLER, list)
        if ok then
          CP:Print(("Sent %d item(s) to Auctionator for %s."):format(#list, label))
          HidePanel()
          return true
        end
        CP.RecordError("auctionator " .. fnName, err)
      end
    end
  end

  -- 2. The AH's own search bar (one item at a time)
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if type(bar) == "table" and type(bar.SearchBox) == "table" and type(bar.StartSearch) == "function" then
    if AuctionHouseFrameDisplayMode and AuctionHouseFrame.SetDisplayMode then
      pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
    end
    local ok = pcall(function()
      bar.SearchBox:SetText(list[1])
      bar:StartSearch()
    end)
    if ok then
      if #list > 1 then
        CP:Print(("Searched the AH for %s. The AH search bar takes one item at a time; the rest: %s"):format(
          list[1], table.concat(list, ", ", 2)))
      else
        CP:Print("Searched the AH for " .. list[1] .. ".")
      end
      HidePanel()
      return true
    end
  end

  -- 3. Give up gracefully: the names, ready to paste
  CP:Print("Couldn't drive the AH search on this client. Here are the names to paste:")
  CP.Report.Open("Search for: " .. label, list, "Ctrl+C copies the item names.")
  return false
end

function Shop.ForCraft(g)
  local names, unresolved = Shop.Materials(g)
  if unresolved > 0 then
    CP:Print(("%d material name(s) aren't known yet, so they were left out. Open the profession window again."):format(unresolved))
  end
  -- the finished item goes in too, so the product and its ingredients are searched together
  table.insert(names, 1, ItemNameOrNil(g.id) or g.name)
  return Shop.Search(names, g.name .. " and its materials")
end

function Shop.ForOutput(g)
  return Shop.Search({ ItemNameOrNil(g.id) or g.name }, g.name)
end

function Shop.ForList(list, label)
  local names, unresolved = {}, 0
  for _, g in ipairs(list) do
    local n, u = Shop.Materials(g)
    for _, x in ipairs(n) do names[#names + 1] = x end
    unresolved = unresolved + u
  end
  if unresolved > 0 then
    CP:Print(("%d material name(s) aren't known yet and were left out."):format(unresolved))
  end
  return Shop.Search(names, label)
end

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------
function Shop.Track(g)
  local t = CP.db.settings.tracked
  if t[g.key] then
    t[g.key] = nil
    CP:Print("Stopped tracking " .. g.name .. ".")
  else
    t[g.key] = true
    CP:Print("Tracking " .. g.name .. ": pinned to the top of the list.")
  end
  CP:Refresh()
end

local function FindRecipe(query)
  query = (query or ""):lower()
  local best, bestProf
  for _, profs in pairs(CP.db.recipes) do
    for prof, recs in pairs(profs) do
      for _, r in ipairs(recs) do
        local m = CP.RecipeMatch(r, query)
        if m == 2 then return r, prof end
        if m == 1 and not best then best, bestProf = r, prof end
      end
    end
  end
  return best, bestProf
end

function Shop.TrackByName(query)
  if not query or query == "" then CP:Print("usage: /pf track <craft name>"); return end
  local r, prof = FindRecipe(query)
  if not r then CP:Print("No captured recipe matches '" .. query .. "'. Try /pf chars."); return end
  Shop.Track({ key = prof .. ":" .. r.id, name = r.name })
end

------------------------------------------------------------------------
-- /pf shop [tracked]
------------------------------------------------------------------------
function Shop.Command(arg)
  local results = CP:BuildResults()
  local list = {}
  if arg == "tracked" then
    for _, g in ipairs(results) do if g.tracked then list[#list + 1] = g end end
    if #list == 0 then CP:Print("No tracked crafts with prices yet. Right-click a row (or /pf track <craft>)."); return end
    Shop.ForList(list, "your tracked crafts")
  else
    for i = 1, math.min(10, #results) do list[#list + 1] = results[i] end
    if #list == 0 then CP:Print("No results yet. Scan the AH first."); return end
    Shop.ForList(list, "the top " .. #list .. " crafts")
  end
end
