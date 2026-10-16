local ADDON_NAME, CP = ...
-- Window customization (see Look.lua). Opens from the minimap button (Alt-click).
if not CP.WinLook then return end
local function Options()
    local L = CP.WinLook
    local st = function() return CP.db.settings end
    local function redo() if CP.UI and CP.UI.Update then CP.UI.Update() end end
    local function mm() if CP.Minimap and CP.Minimap.Apply then CP.Minimap.Apply() end end
    return { sections = {
        { id = "profit", title = "Profit and prices", open = true, rows = {
            { kind = "slider", label = "Auction house cut (%)", min = 0, max = 15, step = 1,
                get = function() return math.floor((st().ahCut or 0.05) * 100 + 0.5) end,
                set = function(v) st().ahCut = v / 100 redo() end },
            L.Choice("Price used for crafts", st, "priceBasis", { { "safe", "Safe (lower of now and 14-day median)" }, { "current", "Current price" } }, redo),
            L.Choice("Scanned buyout means", st, "replicateUnit", { { "total", "The whole stack's price" }, { "unit", "Price per item" } }, redo),
            L.Choice("Hide crafts that make less than", st, "minProfit", { { 0, "Show all" }, { 100, "1 silver" }, { 1000, "10 silver" },
                { 10000, "1 gold" }, { 50000, "5 gold" }, { 100000, "10 gold" } }, redo),
            L.Slider("Hide outputs with fewer listed than", st, "minListed", 1, 20, 1, nil, redo),
            L.Slider("Hide crafts that sell fewer than (per day)", st, "minSales", 0, 20, 1, nil, redo),
            L.Koff("Only crafts I have the materials for", st, "craftableOnly", redo),
            L.Kon("Only recipes a character has learned (hides the rest)", st, "learnedOnly", redo),
            L.Kon("Also list profitable recipes nobody has learned yet", st, "showUnlearned", redo),
            L.Koff("Hide crafts that lose money", st, "hideLosses", redo),
            L.Kon("Limit \"Buy up to\" to the gold I have on this character", st, "limitByGold", function() if CP.UI and CP.UI.Rebuild then CP.UI.Rebuild() end end),
        } },
        { id = "ah", title = "Auction house", open = true, rows = {
            L.Kon("Scan automatically when the auction house opens (if data is stale)", st, "autoScan"),
            L.Choice("Open the auction house on", st, "ahStartTab", { { "game", "Auction House (the game's own search)" }, { "shopping", "Shopping" },
                { "cancelling", "Cancelling" }, { "crafts", "Crafts" }, { "ledger", "Ledger" }, { "last", "Whichever tab I used last" } }),
            L.Kon("Shrink the auction house window to fit Profiteer's tabs (no empty space)", st, "ahShrink", function() if CP.AHTab and CP.AHTab.Fit then CP.AHTab.Fit() end end),
            L.Choice("Size of Profiteer's tabs in the auction house", st, "ahScale", { { 1, "Normal" }, { 1.15, "Larger" }, { 1.25, "Large" }, { 1.4, "Extra large" }, { 1.5, "Huge" } }, function() if CP.AHTab and CP.AHTab.Refit then CP.AHTab.Refit() end end),
            { kind = "slider", label = "Text size in Profiteer's windows", min = 0.8, max = 1.6, step = 0.05, fmt = "%.2f",
                get = function() local e = L.Effective and L.Effective("ah") return (e and tonumber(e.fontScale)) or 1 end,
                set = function(v)
                    for _, id in ipairs({ "main", "ah", "report" }) do
                        local w = L.Get and L.Get(id)
                        if w then w.fontScale = v w.fontOwn = true end
                    end
                    if L.Apply then L.Apply() end
                end },
            L.Koff("Open the Profiteer panel with the auction house", st, "ahAutoOpen"),
            L.Kon("Show Profiteer lines in item tooltips", st, "tooltips"),
            L.Koff("Draw dividing bars between rows (Shopping, Selling, Cancelling and Crafts lists)", st, "rowDividers", function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Choice("Divider color", st, "rowDivMode", { { "accent", "Follow the window border color" }, { "custom", "Pick my own color" } }, function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Color("Divider color (when picking my own)", st, "rowDivColor", { 0.88, 0.69, 0.29 }, function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Slider("Divider opacity", st, "rowDivAlpha", 0.1, 1, 0.05, "%.2f", function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Slider("Divider thickness (pixels)", st, "rowDivSize", 1, 4, 1, nil, function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Slider("Divider indent from the row edges", st, "rowDivInset", 0, 40, 2, nil, function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Koff("Shade every other row", st, "rowStripes", function() if CP.AH then CP.AH.ApplyDividers() end end),
            L.Choice("Selling: undercut by", st, "undercutMode", { { "copper", "A fixed amount of copper" }, { "percent", "A percentage" } }),
            L.Slider("Selling: undercut percentage", st, "undercutPct", 0, 30, 0.5, "%.1f"),
            L.Slider("Selling: undercut copper", st, "undercut", 0, 500, 1),
            L.Choice("Selling: start from", st, "sellBase", { { "low", "The lowest price at the last scan" }, { "ref", "The reference (median) price" } }),
            L.Choice("Selling: round prices down to", st, "sellRound", { { "none", "The copper" }, { "silver", "Whole silver" }, { "tensilver", "Ten silver" } }),
            L.Koff("Selling: never suggest less than the vendor price", st, "sellVendorFloor"),
            L.Choice("Selling: default duration", st, "sellDuration", { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }),
        } },
        { id = "mmap", title = "Minimap", rows = {
            L.K("Show the minimap button", st, "minimapHide", mm, true),
        } },
    } }
end

CP.WinLook.Setup({
    options = Options,
    title = "Profiteer",
    media = "Interface\\AddOns\\Profiteer\\Media\\",
    db = function() return ProfiteerDB end,
    windows = {
        { id = "main", name = "Main window", global = "ProfiteerFrame", strip = "backdrop", hide = { "bgTex" },
          apply = function(frame, _, on)
              if frame and frame.fitScale then
                local fit = frame.fitScale
                if fit > 1 then   -- the auction house window was enlarged: fill it (a look size below 1 still shrinks)
                  frame:SetScale(on and fit * math.min(frame:GetScale(), 1) or fit)
                else
                  frame:SetScale(on and math.min(frame:GetScale(), fit) or fit)
                end
              end
          end },
        { id = "report", name = "Report box", global = "ProfiteerReportFrame", strip = "backdrop" },
        { id = "ah", name = "Auction house", global = "AuctionHouseFrame", strip = "template", defaultOn = true, skinAll = true,
          -- the game's own Browse page (search, categories, results) is left exactly as the game draws it
          skinSkip = function(obj)
            local AH = _G.AuctionHouseFrame
            if not AH then return false end
            local stock = { AH.BrowseResultsFrame, AH.CategoriesList, AH.SearchBar }
            local p, n = obj, 0
            while p and n < 12 do
              for _, f in ipairs(stock) do if p == f then return true end end
              p = p.GetParent and p:GetParent() n = n + 1
            end
            return false
          end,
          hide = { "MoneyFrameBorder", "MoneyFrameInset" },
          apply = function() if CP.AHTab and CP.AHTab.Restyle then CP.AHTab.Restyle() end end },
    },
})
