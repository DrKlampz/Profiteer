-- Roster: the "Characters" window. Lists every character this add-on has saved something about, lets you
-- delete one, and notices characters that are gone from your character list (deleted) and removes them.
-- The same file ships in each add-on that keeps per-character data. Shift-click the minimap button.
local _, ns = ...
local CP = ns

local function IsSecret(v) return _G.issecretvalue and _G.issecretvalue(v) end

-- cfg = {
--   addon   = "Baggie",
--   db      = function() return the saved-variables table end,
--   current = function() return this character's key end,
--   short   = function(key) return the character's name end,
--   tables  = { function(db) return map[charKey] end, ... },        every place a character is stored
--   nested  = { function(db) return map[day][charKey] end, ... },   (optional) stored under another key first
--   info    = function(key, db) return "short text", classFilename end,   (optional)
--   print   = function(msg),
--   after   = function() end,   called when something was removed (refresh your windows)
-- }
function ns.NewRoster(cfg)
    local R = { missing = {}, verified = false }
    local frame, rows = nil, {}

    local function db() return cfg.db() or {} end
    local function auto() local d = db() return d.rosterAuto ~= false end

    -- Some servers give characters a first and last name: UnitName hands the last name back in the slot
    -- where retail puts the realm. Remember each character's full name when it logs in.
    local rawShort = cfg.short
    local function short(key)
        local d = db()
        local n = d.rosterNames and d.rosterNames[key]
        return n or rawShort(key)
    end

    local function FullName()
        local first, second = UnitName("player")
        if type(first) ~= "string" or IsSecret(first) then return nil end
        if type(second) == "string" and second ~= "" and not IsSecret(second) and not first:find(" ", 1, true) then
            local realm = _G.GetRealmName and _G.GetRealmName()
            local nrealm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
            if second ~= realm and second ~= nrealm then return first .. " " .. second end
        end
        return first
    end

    local function Squash(s) return (tostring(s or ""):gsub("[%s%-']", ""):lower()) end

    -- fill in other characters' full names from the Postage list, when that add-on is loaded
    function R.Remember()
        local dbt = cfg.db()
        if not dbt then return end
        dbt.rosterNames = dbt.rosterNames or {}
        local cur = cfg.current and cfg.current()
        local me = FullName()
        if cur and me then dbt.rosterNames[cur] = me end
        dbt.rosterClass = dbt.rosterClass or {}
        local _, myClass = UnitClass("player")
        if cur and type(myClass) == "string" and not IsSecret(myClass) then dbt.rosterClass[cur] = myClass end
        -- other characters' classes from the add-ons that already recorded them
        local PF = _G.ProfiteerDB
        for _, key in ipairs(R.Keys()) do
            if not dbt.rosterClass[key] then
                local c = PF and type(PF.chars) == "table" and PF.chars[key]
                if type(c) == "table" and type(c.class) == "string" then dbt.rosterClass[key] = c.class end
            end
        end
        local P = _G.PostageDB
        if P and type(P.alts) == "table" then
            for _, key in ipairs(R.Keys()) do
                if not dbt.rosterClass[key] then
                    local first, realm = key:match("^(.-)%-([^%-]*)$")
                    for _, c in pairs(P.alts) do
                        if first and type(c) == "table" and type(c.class) == "string" and type(c.name) == "string"
                           and (c.name == first or c.name:sub(1, #first + 1) == first .. " ")
                           and Squash(c.realm) == Squash(realm) then dbt.rosterClass[key] = c.class break end
                    end
                end
            end
            for _, key in ipairs(R.Keys()) do
                if not dbt.rosterNames[key] then
                    local first, realm = key:match("^(.-)%-([^%-]*)$")
                    if first then
                        for _, c in pairs(P.alts) do
                            if type(c) == "table" and type(c.name) == "string" and c.name:find(" ", 1, true)
                               and c.name:sub(1, #first + 1) == first .. " " and Squash(c.realm) == Squash(realm) then
                                dbt.rosterNames[key] = c.name
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- every character key this add-on knows
    local function Keys()
        local d, seen, out = db(), {}, {}
        local function add(k) if type(k) == "string" and not seen[k] then seen[k] = true out[#out + 1] = k end end
        for _, get in ipairs(cfg.tables) do
            local ok, t = pcall(get, d)
            if ok and type(t) == "table" then for k in pairs(t) do add(k) end end
        end
        for _, get in ipairs(cfg.nested or {}) do
            local ok, t = pcall(get, d)
            if ok and type(t) == "table" then
                for _, day in pairs(t) do if type(day) == "table" then for k in pairs(day) do add(k) end end end
            end
        end
        local cur = cfg.current and cfg.current()
        if cur then add(cur) end
        table.sort(out, function(a, b) return short(a):lower() < short(b):lower() end)
        return out
    end
    R.Keys = Keys

    function R.Forget(key)
        local d, n = db(), 0
        for _, get in ipairs(cfg.tables) do
            local ok, t = pcall(get, d)
            if ok and type(t) == "table" and t[key] ~= nil then t[key] = nil n = n + 1 end
        end
        for _, get in ipairs(cfg.nested or {}) do
            local ok, t = pcall(get, d)
            if ok and type(t) == "table" then
                for _, day in pairs(t) do if type(day) == "table" and day[key] ~= nil then day[key] = nil n = n + 1 end end
            end
        end
        R.missing[key] = nil
        if cfg.after then pcall(cfg.after) end
        return n
    end

    -- the names on the character-select list (nil when the game won't tell us)
    local function ListNames()
        if not (_G.GetNumCharacters and _G.GetCharacterInfo) then return nil end
        local ok, n = pcall(_G.GetNumCharacters)
        if not ok or IsSecret(n) then return nil end
        n = tonumber(n)
        if not n or n < 1 then return nil end
        local names = {}
        for i = 1, n do
            local ok2, name = pcall(_G.GetCharacterInfo, i)
            if ok2 and type(name) == "string" and name ~= "" and not IsSecret(name) then names[#names + 1] = name:lower() end
        end
        return #names > 0 and names or nil
    end

    -- a saved name matches a listed one if they are the same, or one is the first part of the other
    -- (some servers hand out two-part names); when in doubt the character counts as still there
    local function Listed(names, stored)
        stored = stored:lower()
        for _, nm in ipairs(names) do
            if nm == stored then return true end
            if stored:sub(1, #nm + 1) == nm .. " " then return true end
            if nm:sub(1, #stored + 1) == stored .. " " then return true end
        end
        return false
    end

    -- Compare the saved characters with the character list. Only trusted when your own character is on the
    -- list, which proves the list is readable and in the format we expect.
    function R.Detect(quiet)
        R.missing, R.verified = {}, false
        local names = ListNames()
        local cur = cfg.current and cfg.current()
        if not names or not cur or not Listed(names, short(cur)) then return 0 end
        R.verified = true
        local gone = {}
        for _, k in ipairs(Keys()) do
            if k ~= cur and not Listed(names, short(k)) then R.missing[k] = true gone[#gone + 1] = k end
        end
        if auto() and #gone > 0 then
            local list = {}
            for _, k in ipairs(gone) do list[#list + 1] = short(k) R.Forget(k) end
            if not quiet and cfg.print then
                cfg.print("removed " .. table.concat(list, ", ") .. " (no longer on your character list).")
            end
            R.missing = {}
        end
        if R.Refresh then R.Refresh() end
        return #gone
    end

    ----------------------------------------------------------------------
    -- window
    ----------------------------------------------------------------------
    local function Build()
        local f = CreateFrame("Frame", "Roster" .. cfg.addon .. "Frame", UIParent, "BackdropTemplate")
        f:SetSize(380, 140)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        f:Hide()
        if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, f:GetName()) end

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.title:SetText(cfg.addon .. ": characters")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        f.help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.help:SetPoint("TOPLEFT", 14, -36)
        f.help:SetWidth(350)
        f.help:SetJustifyH("LEFT")
        f.help:SetText("Everything " .. cfg.addon .. " saved about each character. Delete one you no longer play.")

        f.auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        f.auto:SetSize(24, 24)
        f.auto:SetScript("OnClick", function(self) db().rosterAuto = self:GetChecked() and true or false R.Detect(true) R.Refresh() end)
        f.autoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.autoText:SetPoint("LEFT", f.auto, "RIGHT", 2, 0)
        f.autoText:SetText("Remove characters that were deleted, automatically")

        f.check = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.check:SetSize(110, 22)
        f.check:SetText("Check now")
        f.check:SetScript("OnClick", function()
            local n = R.Detect(false)
            if not R.verified and cfg.print then
                cfg.print("couldn't read your character list from in game. Delete characters by hand here, or check again from the character select screen.")
            elseif n == 0 and cfg.print then cfg.print("every saved character is still on your character list.") end
            R.Refresh()
        end)
        f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        return f
    end

    local function Row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, frame)
        r:SetSize(352, 22)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetWidth(120)
        r.name:SetJustifyH("LEFT")
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("LEFT", 124, 0)
        r.info:SetWidth(150)
        r.info:SetJustifyH("LEFT")
        r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.del:SetSize(70, 20)
        r.del:SetPoint("RIGHT", 0, 0)
        r.del:SetText("Delete")
        r.del:SetScript("OnClick", function(self)
            local key = r.key
            if not key then return end
            if r.armed then
                r.armed = nil
                local n = R.Forget(key)
                if cfg.print then cfg.print("removed " .. short(key) .. " (" .. n .. " record" .. (n == 1 and "" or "s") .. ").") end
                R.Refresh()
            else
                r.armed = true
                self:SetText("Sure?")
                if _G.C_Timer then _G.C_Timer.After(3, function() if r.armed then r.armed = nil self:SetText("Delete") end end) end
            end
        end)
        rows[i] = r
        return r
    end

    function R.Refresh()
        if not frame or not frame:IsShown() then return end
        local keys, cur, d = Keys(), cfg.current and cfg.current(), db()
        local y = -62
        for i, k in ipairs(keys) do
            local r = Row(i)
            r.key, r.armed = k, nil
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 14, y)
            y = y - 24
            local info, class = "", nil
            if cfg.info then local ok, a, b = pcall(cfg.info, k, d) if ok then info, class = a or "", b end end
            class = (d.rosterClass and d.rosterClass[k]) or class
            local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
            r.name:SetText(short(k))
            if c then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(1, 0.82, 0) end
            if k == cur then info = "|cff55ff55this character|r" .. (info ~= "" and ("  " .. info) or "")
            elseif R.missing[k] then info = "|cffff5555not on your character list|r" end
            r.info:SetText(info)
            r.del:SetText("Delete")
            r.del:SetEnabled(k ~= cur)
            r:Show()
        end
        for i = #keys + 1, #rows do rows[i]:Hide() rows[i].key = nil end
        if #keys == 0 then
            frame.status:SetText("No characters saved yet.")
            frame.status:ClearAllPoints()
            frame.status:SetPoint("TOPLEFT", 14, -62)
            y = y - 20
        else
            frame.status:SetText(R.verified and "Compared with your character list." or "Your character list couldn't be read from in game, so deleted characters can't be spotted automatically.")
            frame.status:ClearAllPoints()
            frame.status:SetPoint("TOPLEFT", 14, y - 4)
            frame.status:SetWidth(352)
            frame.status:SetJustifyH("LEFT")
            y = y - 30
        end
        frame.auto:ClearAllPoints()
        frame.auto:SetPoint("TOPLEFT", 10, y)
        frame.auto:SetChecked(auto())
        frame.check:ClearAllPoints()
        frame.check:SetPoint("TOPLEFT", 14, y - 28)
        frame:SetHeight(-y + 62)
    end

    function R.Open()
        pcall(R.Remember)
        frame = frame or Build()
        frame:Show()
        R.Detect(true)
        R.Refresh()
    end
    function R.Toggle()
        if frame and frame:IsShown() then frame:Hide() else R.Open() end
    end

    -- look for deleted characters at login and whenever the character list changes
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    pcall(ev.RegisterEvent, ev, "CHARACTER_LIST_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            pcall(R.Remember)
            if _G.C_Timer then _G.C_Timer.After(8, function() pcall(R.Remember) pcall(R.Detect, false) end) end
        else
            pcall(R.Detect, false)
        end
    end)

    return R
end

CP.Roster = ns.NewRoster({
  addon = "Profiteer",
  db = function() return CP.db end,
  current = function() return CP.charKey end,
  short = function(k) return CP.ShortName(k) end,
  tables = {
    function(d) return d.recipes end, function(d) return d.unlearned end, function(d) return d.inventory end,
    function(d) return d.chars end, function(d) return d.myAuctions end, function(d) return d.mailGold end,
    function(d) return d.ledgerChars end,
  },
  nested = { function(d) return d.worth end, function(d) return d.ledgerDC end },
  info = function(k, d)
    local c = d.chars and d.chars[k]
    local n = 0
    for _, list in pairs(d.recipes and d.recipes[k] or {}) do n = n + #list end
    return (n > 0 and (n .. " recipes") or "no recipes yet"), c and c.class
  end,
  print = function(m) CP:Print(m) end,
  after = function() CP:Refresh() end,
})
