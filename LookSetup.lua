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
            L.Koff("Hide crafts that lose money", st, "hideLosses", redo),
            L.Kon("Limit \"Buy up to\" to the gold I have on this character", st, "limitByGold", function() if CP.UI and CP.UI.Rebuild then CP.UI.Rebuild() end end),
        } },
        { id = "ah", title = "Auction house", open = true, rows = {
            L.Kon("Scan automatically when the auction house opens (if data is stale)", st, "autoScan"),
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
            L.Koff("Selling: post through the game's own Sell tab (switches on by itself if the game blocks add-ons from posting)", st, "postBlocked"),
            L.Koff("Keep the game's own Buy / Sell / Auctions tabs (Profiteer's tabs go after them; reopen the auction house)", st, "keepGameTabs"),
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
          apply = function(frame, _, on) if frame and frame.fitScale then frame:SetScale(on and (frame:GetScale() * frame.fitScale) or frame.fitScale) end end },
        { id = "report", name = "Report box", global = "ProfiteerReportFrame", strip = "backdrop" },
        { id = "ah", name = "Auction house", global = "AuctionHouseFrame", strip = "template", defaultOn = true,
          hide = { "MoneyFrameBorder", "MoneyFrameInset" },
          title = function(f) return (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText end,
          apply = function() if CP.AHTab and CP.AHTab.Restyle then CP.AHTab.Restyle() end end },
    },
})
