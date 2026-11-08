local ADDON, CP = ...
-- A sound whenever the game says one of your auctions sold. Pick which one with Ctrl+right-click on the
-- minimap button (or /pf sound). Ctrl+click on the minimap button switches it on or off.
local K = {}
CP.Kaching = K
local MEDIA = "Interface\\AddOns\\Profiteer\\Media\\"

-- files in the Media folder, then sounds built into the game
local LIST = {
    { key = "mine",     name = "Cash Register", files = { "cash_register.ogg", "kaching.mp3" } },
    { key = "money",    name = "Money", files = { "money.ogg", "money.mp3" } },
    { key = "iceyay",   name = "Ice Cube - Yay Yayee", files = { "iceyay.ogg", "iceyay.mp3" } },
    { key = "yeahboy",  name = "Yeah Boyyy", files = { "yeahboy.ogg", "yeahboy.mp3" } },
    { key = "sonic",    name = "Sonic Coin", files = { "soniccoin.ogg", "soniccoin.mp3" } },
        { key = "mine6",    name = "Your own sound (save as Media\\mysound.mp3)", files = { "mysound.mp3" } },
    { key = "register", name = "Profiteer: cash register", files = { "register_synth.ogg" } },
    { key = "soft",     name = "Profiteer: soft register ding",   files = { "register_soft.ogg" } },
    { key = "bell",     name = "Profiteer: bell ding",            files = { "bell_ding.ogg" } },
    { key = "clink",    name = "Profiteer: single coin clink",    files = { "coin_clink.ogg" } },
    { key = "jingle",   name = "Profiteer: coins jingling",       files = { "coin_jingle.ogg" } },
    { key = "pour",     name = "Profiteer: pile of coins", files = { "coin_pour.ogg" } },
    { key = "vendor",   name = "Game: vendor coins",   kit = "LOOT_WINDOW_COIN_SELL", id = 891 },
    { key = "ah",       name = "Game: auction house bell", kit = "AUCTION_WINDOW_OPEN", id = 5274 },
    { key = "quest",    name = "Game: quest complete", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
    { key = "level",    name = "Game: level up",       kit = "LEVELUP", id = 888 },
}
K.List = LIST

local function S() return CP.db and CP.db.settings or {} end
function K.Enabled() return S().kaching ~= false end
local function Find(key) for _, e in ipairs(LIST) do if e.key == key then return e end end return LIST[2] end
local OLD = { mine2 = "money", mine3 = "iceyay", mine4 = "yeahboy", mine5 = "sonic" }   -- names from an earlier version
function K.Current()
    local s = S()
    if s.kachingSound and OLD[s.kachingSound] then s.kachingSound = OLD[s.kachingSound] end
    return Find(s.kachingSound or "mine")
end

function K.PlayEntry(e)
    if e.files then
        for _, f in ipairs(e.files) do
            local ok, will = pcall(PlaySoundFile, MEDIA .. f, "Master")
            if ok and will then return true, f end
        end
        return false
    end
    local id = (SOUNDKIT and SOUNDKIT[e.kit]) or e.id
    local ok = pcall(PlaySound, id, "Master")
    return ok
end

function K.Play()
    local e = K.Current()
    if not K.PlayEntry(e) then
        K.PlayEntry(Find("vendor"))                               -- missing file: use the game's coin sound
        if CP.Issue then CP.Issue("warn", "sale sound", "could not play " .. tostring(e.name) .. "; used the vendor coin sound") end
    end
end

function K.Toggle()
    local s = S()
    s.kaching = not K.Enabled()
    CP:Print("Sale sound " .. (s.kaching and "on" or "off") .. ".")
    if s.kaching then K.Play() end
end

---------------------------------------------------------------------------
-- Picker window
---------------------------------------------------------------------------
local win
local function Refresh()
    if not win then return end
    local cur = K.Current().key
    for _, row in ipairs(win.rows) do
        row.check:SetShown(row.entry.key == cur)
        row.text:SetTextColor(row.entry.key == cur and 1 or 0.9, row.entry.key == cur and 0.82 or 0.9, row.entry.key == cur and 0 or 0.9)
    end
    win.enable:SetChecked(K.Enabled())
end

local function Build()
    win = CreateFrame("Frame", "ProfiteerSoundPicker", UIParent, "BackdropTemplate")
    win:SetSize(380, 56 + #LIST * 24 + 40)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true) win:EnableMouse(true) win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
        win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        win:SetBackdropColor(0.07, 0.07, 0.09, 0.97)
        win:SetBackdropBorderColor(0.88, 0.69, 0.29, 0.9)
    end
    tinsert(UISpecialFrames, "ProfiteerSoundPicker")
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Sale sound")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local enable = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", 10, -34)
    local label = enable.Text or enable.text or (enable.GetName and enable:GetName() and _G[enable:GetName() .. "Text"])
    if not label then
        label = enable:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", enable, "RIGHT", 2, 0)
    end
    label:SetText("Play a sound when an auction sells")
    enable:SetScript("OnClick", function(self) S().kaching = self:GetChecked() and true or false end)
    win.enable = enable
    win.rows = {}
    for i, e in ipairs(LIST) do
        local b = CreateFrame("Button", nil, win)
        b:SetSize(352, 22)
        b:SetPoint("TOPLEFT", 14, -62 - (i - 1) * 24)
        local hl = b:CreateTexture(nil, "HIGHLIGHT") hl:SetAllPoints() hl:SetColorTexture(1, 1, 1, 0.08)
        b.check = b:CreateFontString(nil, "OVERLAY", "GameFontNormal") b.check:SetPoint("LEFT", 4, 0) b.check:SetText(">")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", 22, 0) b.text:SetText(e.name)
        b.entry = e
        b:SetScript("OnClick", function()
            S().kachingSound = e.key
            S().kaching = true
            if not K.PlayEntry(e) and e.files then CP:Print("That sound file isn't in the Media folder yet.") end
            Refresh()
        end)
        win.rows[i] = b
    end
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetText("Click a sound to hear it and pick it.")
end

function K.Picker()
    if not win then
        local ok, err = pcall(Build)
        if not ok then
            win = nil
            CP:Print("The sound picker failed to open: " .. tostring(err))
            if CP.Issue then CP.Issue("lua", "sound picker", err) end
            return
        end
    end
    if win:IsShown() then win:Hide() return end
    win:Show()
    Refresh()
end

function K.Command(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        S().kaching = (arg == "on")
        CP:Print("Sale sound " .. arg .. ".")
    elseif arg == "test" then
        local e = K.Current()
        local ok, f = K.PlayEntry(e)
        if ok then CP:Print("Played: " .. e.name .. (f and (" (" .. f .. ")") or ""))
        else CP:Print("Could not play " .. e.name .. ": the file is missing from the Media folder or the game refused it.") end
    else
        K.Picker()
    end
end

---------------------------------------------------------------------------
-- Sale detection. Three ways, because clients differ and the game may hide chat text from add-ons:
--  1. the game's "A buyer has been found for your auction of ..." system message
--  2. any system message that mentions both "auction" and a sale word (logged, so it can be tuned)
--  3. your own auction list showing an auction as sold (checked whenever the game updates it)
---------------------------------------------------------------------------
local prefix, suffix
local function Parse()
    local tmpl = _G.ERR_AUCTION_SOLD_S or "A buyer has been found for your auction of %s."
    local a, b = tmpl:find("%s", 1, true)
    if a then prefix, suffix = tmpl:sub(1, a - 1), tmpl:sub(b + 1) else prefix, suffix = tmpl, "" end
end

local lastAt = 0
local function Sale(why)
    local now = GetTime()
    if now - lastAt < 3 then return end              -- one sound per sale, whichever trigger saw it first
    lastAt = now
    K.lastTrigger = why
    if CP.Issue then CP.Issue("warn", "sale sound", "played because of: " .. why) end
    K.Play()
end

local function Trace(msg) if CP.Issue then CP.Issue("warn", "sale sound trace", msg) end end

-- owned auctions that are sold: ids we have already announced
local announced, primed = {}, false
local function CheckOwned()
    local sold, n = {}, 0
    local C = C_AuctionHouse
    if C and C.GetOwnedAuctions then
        local ok, list = pcall(C.GetOwnedAuctions)
        if ok and type(list) == "table" then
            local SOLD = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
            for _, a in ipairs(list) do
                if type(a) == "table" and a.status == SOLD and a.auctionID then sold[a.auctionID] = true n = n + 1 end
            end
        end
    elseif GetNumAuctionItems then
        local ok, count = pcall(GetNumAuctionItems, "owner")
        if ok and type(count) == "number" then
            for i = 1, count do
                local ok2, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, saleStatus = pcall(GetAuctionItemInfo, "owner", i)
                if ok2 and saleStatus == 1 then sold["legacy" .. i] = true n = n + 1 end
            end
        end
    end
    local fresh = 0
    for id in pairs(sold) do if not announced[id] then announced[id] = true fresh = fresh + 1 end end
    if primed and fresh > 0 and K.Enabled() then Sale("your auction list shows " .. fresh .. " sold") end
    primed = true                                      -- the first look only records what was already sold
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("OWNED_AUCTIONS_UPDATED")
pcall(f.RegisterEvent, f, "AUCTION_OWNED_LIST_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then
        if not K.Enabled() then return end
        if type(msg) ~= "string" then return end
        if issecretvalue and issecretvalue(msg) then Trace("a system message arrived with its text hidden by the game") return end
        if not prefix then Parse() end
        if msg:sub(1, #prefix) == prefix and (suffix == "" or msg:sub(-#suffix) == suffix) then Sale("the sold message") return end
        local low = msg:lower()
        if low:find("auction", 1, true) then
            Trace("auction message: " .. msg:sub(1, 160))
            if low:find("sold", 1, true) or low:find("buyer", 1, true) or low:find("sale", 1, true) then Sale("a sale message: " .. msg:sub(1, 60)) end
        end
    elseif event == "OWNED_AUCTIONS_UPDATED" or event == "AUCTION_OWNED_LIST_UPDATE" then
        if K.Enabled() then pcall(CheckOwned) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        primed = false                                 -- re-learn what was already sold after a login or reload
    end
end)
