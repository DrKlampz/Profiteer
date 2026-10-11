local ADDON_NAME, CP = ...
-- Window customization (see Look.lua). Opens from the minimap button (Alt-click).
if not CP.WinLook then return end
CP.WinLook.Setup({
    title = "Profiteer",
    media = "Interface\\AddOns\\Profiteer\\Media\\",
    db = function() return ProfiteerDB end,
    windows = {
        { id = "main", name = "Main window", global = "ProfiteerFrame", strip = "backdrop", hide = { "bgTex" } },
        { id = "report", name = "Report box", global = "ProfiteerReportFrame", strip = "backdrop" },
    },
})
