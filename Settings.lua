-- BattleText Forever: settings, sharing them, the minimap button, slash commands and events.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, Parser, T, L, Print, DEFAULTS = S.BT, S.Parser, S.T, S.L, S.Print, S.DEFAULTS
local Num, Str, FillDefaults, MissText, SpellName, ManaNow = S.Num, S.Str, S.FillDefaults, S.MissText, S.SpellName, S.ManaNow

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Your colors over the starting ones, in place (code reads BT.TEXT_COLORS when it shows a line)
function BT:ApplyColors()
    local mine = self.db and self.db.colors or {}
    for k, def in pairs(self.DEFAULT_COLORS) do
        local c = mine[k]
        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
            self.TEXT_COLORS[k] = { c[1], c[2], c[3] }
        else
            self.TEXT_COLORS[k] = { def[1], def[2], def[3] }
        end
    end
end

function BT:SetColor(key, r, g, b)
    if r then self.db.colors[key] = { r, g, b } else self.db.colors[key] = nil end
    self:ApplyColors()
end

function BT:ApplySettings()
    self:ApplyColors()
    self.rulesByName = nil   -- (the spell list may be another one now)
    if not self.built then return end
    self:ApplyAreas()
    self:UpdateStartButton()
    self:UpdateMinimapButton()
    self:ApplyBlizzardText()
    if self.db.enabled then self:KeepLogFlowing() else self:StopLogFlowing() end
end

-- Settings for this character only, or the ones every character shares. Turning
-- it on starts this character from a copy of the shared ones.
local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end

function BT:OwnSettings()
    return BattleTextForeverCharDB ~= nil and BattleTextForeverCharDB.own == true
end

function BT:SetOwnSettings(on)
    if on == self:OwnSettings() then return end
    self:ApplyBlizzardText(true)   -- put the game's numbers back while the settings change hands
    local char = BattleTextForeverCharDB
    if on then
        -- The ones this character had before, if it had its own; else a copy of the shared ones
        local mine = type(char.settings) == "table" and char.settings
        if mine then
            self:MoveOldSettings(mine)
            FillDefaults(mine, DEFAULTS)
        else
            mine = Copy(BattleTextForeverDB)
            mine.savedCVars = nil
        end
        char.settings, char.own = mine, true
        self.db = mine
    else
        char.own = nil
        self.db = BattleTextForeverDB
    end
    self:ApplySettings()
    self:RefreshConfig()
end

-- Every setting back to how it started (this character's own, when it has them): the
-- options, the areas' places, the colors, the Spells list, and what was learned in fights.
-- The game's own numbers are put back first, as they were before BattleText hid them.
function BT:ResetAll()
    self:ApplyBlizzardText(true)
    local db = self.db
    for k in pairs(db) do db[k] = nil end
    FillDefaults(db, DEFAULTS)
    self.spellSchool, self.schoolSeen = nil, nil   -- (what was learned this session goes too)
    self:ApplySettings()
    if self.RefreshConfig then self:RefreshConfig() end
end

-- Picking a font shows a line in it straight away
function BT:SetFont(name)
    self.db.font = name
    self.testing = true
    self:Emit("notify", name, self.TEXT_COLORS.notify)
    self.testing = false
end

-- Picking a font for crits shows a crit in it
function BT:SetCritFont(name)
    self.db.critFont = name
    self.testing = true
    self:Emit("notify", L["Crit"], self.TEXT_COLORS.notify, { crit = true })
    self.testing = false
end

-- Picking an outline shows a line with it straight away (a crit for the crits' one)
function BT:SetOutline(key, flags)
    self.db[key] = flags
    self.testing = true
    self:Emit("notify", key == "critOutline" and L["Crit"] or L["Normal"], self.TEXT_COLORS.notify,
        { crit = key == "critOutline" })
    self.testing = false
end

---------------------------------------------------------------------------
-- Share settings: the settings as one line of text ("BTF1:{...}") to copy, and
-- read back. Only the settings the options window has go in, never what was
-- learned in fights or where this character's areas are unlocked.
---------------------------------------------------------------------------
local SHARE_PREFIX = "BTF1:"
local NOT_SHARED = { enabled = true, locked = true, debug = true, minimap = true, minimapAngle = true,
    startReminder = true, loginMessage = true, shieldAmounts = true }

local function Serialize(v)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) then return tostring(v) end
        return (("%.4f"):format(v):gsub("0+$", ""))
    elseif t == "boolean" then
        return v and "t" or "f"
    elseif t == "string" then
        return '"' .. v:gsub("[\\\"]", "\\%0") .. '"'
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" and k:match("^[%a_][%w_]*$") or type(k) == "number" and k == math.floor(k) then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        local parts = {}
        for _, k in ipairs(keys) do
            local item = Serialize(v[k])
            if item then parts[#parts + 1] = tostring(k) .. "=" .. item end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return nil
end

-- Reads what Serialize writes, and nothing else (no code is ever run)
local function Deserialize(text)
    local pos = 1
    local function skip() pos = text:find("[^%s]", pos) or #text + 1 end
    local value
    function value(depth)
        if depth > 4 then return nil end
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            skip()
            if text:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                skip()
                local key = text:match("^[%a_][%w_]*", pos) or text:match("^%d+", pos)
                if not key then return nil end
                pos = pos + #key
                skip()
                if text:sub(pos, pos) ~= "=" then return nil end
                pos = pos + 1
                local v = value(depth + 1)
                if v == nil then return nil end
                t[tonumber(key) or key] = v
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == "}" then return t end
                if sep ~= "," then return nil end
            end
        elseif c == '"' then
            local out, i = {}, pos + 1
            while i <= #text do
                local ch = text:sub(i, i)
                if ch == "\\" then
                    out[#out + 1] = text:sub(i + 1, i + 1)
                    i = i + 2
                elseif ch == '"' then
                    pos = i + 1
                    return table.concat(out)
                else
                    out[#out + 1] = ch
                    i = i + 1
                end
            end
            return nil
        elseif c == "t" or c == "f" then
            pos = pos + 1
            return c == "t"
        else
            local num = text:match("^%-?%d+%.?%d*", pos)
            if not num then return nil end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local v = value(0)
    skip()
    if pos <= #text then return nil end
    return v
end
BT.Serialize, BT.Deserialize = Serialize, Deserialize

function BT:ExportSettings()
    local out = {}
    for k in pairs(DEFAULTS) do
        if not NOT_SHARED[k] and self.db[k] ~= nil then out[k] = self.db[k] end
    end
    return SHARE_PREFIX .. Serialize(out)
end

-- The range of every number setting (the options' sliders use the same ones)
BT.RANGES = {
    fontSize = { 10, 40 }, critScale = { 100, 250 }, scrollTime = { 1, 6 }, height = { 100, 500 },
    tickMerge = { 0, 3 }, minDamage = { 0, 500 }, minHeal = { 0, 500 }, minCrit = { 0, 1000 },
    lowManaAt = { 10, 60 },
}
for _, area in pairs(BT.AREAS) do
    BT.RANGES[area.prefix .. "Size"] = { 50, 200 }
    BT.RANGES[area.prefix .. "Alpha"] = { 10, 100 }
end

-- The settings that are one of a list: the list's keys
function BT:Choices(key)
    local list, field
    if key == "font" then list, field = self.FONTS, "name"
    elseif key == "critFont" then
        local keys = { [""] = true }
        for _, f in ipairs(self.FONTS) do keys[f.name] = true end
        return keys
    elseif key == "outline" or key == "critOutline" then list, field = self.OUTLINES, "flags"
    elseif key:match("Sound$") then list, field = self.SOUNDS, "key"
    elseif key:match("Style$") then list, field = self.STYLES, "key"
    elseif key:match("Align$") then list, field = self.ALIGNS, "key"
    elseif key:match("^route") then
        local keys = {}
        for areaKey in pairs(self.AREAS) do keys[areaKey] = true end
        return keys
    else return nil end
    local keys = {}
    for _, item in ipairs(list) do keys[item[field]] = true end
    return keys
end

local function Clamp(v, range) return math.max(range[1], math.min(range[2], v)) end

-- Reads shared settings text into a table of settings BattleText has, each of the right
-- kind and in its range. Returns it and how many, or nil and why not.
function BT:ReadSettings(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, L["that isn't BattleText settings text"] end
    local t = Deserialize(text:sub(#SHARE_PREFIX + 1))
    if type(t) ~= "table" then return nil, L["the text is cut short or changed"] end
    local out, count = {}, 0
    for k, v in pairs(t) do
        local default = DEFAULTS[k]
        if default ~= nil and not NOT_SHARED[k] and type(v) == type(default) then
            local took
            if k == "colors" then
                -- (the colors they changed: the rest are the usual ones)
                took = {}
                for name, c in pairs(v) do
                    if self.TEXT_COLORS[name] and type(c) == "table" and type(c[1]) == "number"
                            and type(c[2]) == "number" and type(c[3]) == "number" then
                        took[name] = { Clamp(c[1], { 0, 1 }), Clamp(c[2], { 0, 1 }), Clamp(c[3], { 0, 1 }) }
                    else
                        took = nil
                        break
                    end
                end
            elseif k == "spellRules" then
                -- (a list of { name =, hide =, color = }: anything else in it is left out)
                took = {}
                for _, r in ipairs(v) do
                    if type(r) == "table" and type(r.name) == "string" and r.name ~= "" and #r.name <= 60 then
                        local c = r.color
                        local color = type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number"
                            and type(c[3]) == "number"
                            and { Clamp(c[1], { 0, 1 }), Clamp(c[2], { 0, 1 }), Clamp(c[3], { 0, 1 }) } or nil
                        took[#took + 1] = { name = r.name, hide = r.hide == true, color = color }
                    end
                end
            elseif k == "areas" then
                for name, pos in pairs(v) do
                    if DEFAULTS.areas[name] and type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
                        took = took or {}
                        took[name] = { x = Clamp(math.floor(pos.x + 0.5), { -2000, 2000 }),
                            y = Clamp(math.floor(pos.y + 0.5), { -2000, 2000 }) }
                    end
                end
            elseif type(v) == "number" then
                local range = self.RANGES[k]
                took = range and Clamp(v, range) or v
            elseif type(v) == "string" then
                local choices = self:Choices(k)
                if not choices or choices[v] then took = v end
            else
                took = v
            end
            if took ~= nil then
                out[k] = took
                count = count + 1
            end
        end
    end
    if count == 0 then return nil, L["there were no settings in it"] end
    return out, count
end

-- Puts read settings (ReadSettings) in place. Where the text areas are on screen
-- only changes with positionsToo: someone else's screen isn't yours.
function BT:TakeSettings(t, positionsToo)
    local db = self.db
    for k, v in pairs(t) do
        if k == "areas" then
            if positionsToo then
                for name, pos in pairs(v) do db.areas[name].x, db.areas[name].y = pos.x, pos.y end
            end
        else
            db[k] = v
        end
    end
    self:ApplySettings()
    if self.RefreshConfig then self:RefreshConfig() end
end

-- Both at once. Returns how many settings, or nil and why not.
function BT:ImportSettings(text, positionsToo)
    local t, count = self:ReadSettings(text)
    if not t then return nil, count end
    self:TakeSettings(t, positionsToo)
    return count
end

function BT:SetLocked(locked)
    self.db.locked = locked
    self:ApplyAreas()
end

-- The game's own floating numbers, so they aren't shown twice. What they were
-- set to is remembered, and put back when the option or BattleText is turned
-- off, and whenever you log out (so nothing is left changed if BattleText is
-- removed).
-- Forever names them with "_v2" (the numbers over the mobs you hit and the units
-- you heal); the older names are kept for a client that still has them. One the
-- game doesn't have reads as nothing and is skipped.
local BLIZZARD_CVARS = {
    "enableFloatingCombatText",
    "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
    "floatingCombatTextCombatLogPeriodicSpells_v2", "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2",
    "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing",
}
-- The game's own "+12 Mana" over your character (CurseForge, feuerbanane on 1.30.0: "I have power
-- gains off but it still shows +mana"). Only with Power gains off: BattleText can't always see
-- a mana gain (on Forever some never reach it, like Life Tap's), so with it on the game's stay.
-- Names from Gethe/wow-ui-source forever, Blizzard_CombatText CombatTextConstants.lua.
local POWER_CVARS = { "floatingCombatTextEnergyGains_v2", "floatingCombatTextPeriodicEnergyGains_v2" }
-- The game's "+XP" that pops up in the world when you gain experience has no setting of its
-- own. It's world text, like the numbers over mobs: "WorldTextScale" made huge draws it too big
-- to be seen (the way players hide it). Only while BattleText shows your XP itself (Notifications
-- -> Experience), as the numbers over mobs are already hidden then.
-- Forever names it "WorldTextScale_v2" (a player's list of the game's settings: there's no
-- plain "WorldTextScale", which is why 1.16.2 didn't hide it); the old name is kept for a
-- client that has it, and a missing one is skipped.
local XP_CVARS, XP_HIDDEN = { "WorldTextScale_v2", "WorldTextScale" }, "1000"
function BT:BlizzardHides()
    local db = self.db
    local hide = {}
    if not (db.enabled and db.hideBlizzard) then return hide end
    for _, cvar in ipairs(BLIZZARD_CVARS) do hide[cvar] = "0" end
    if not db.inPower then
        for _, cvar in ipairs(POWER_CVARS) do hide[cvar] = "0" end
    end
    if db.nXP then
        for _, cvar in ipairs(XP_CVARS) do hide[cvar] = XP_HIDDEN end
    end
    return hide
end

function BT:ApplyBlizzardText(restore)
    if not (GetCVar and SetCVar) then return end
    if InCombatLockdown() and not restore then return end
    local db = self.db
    local hide = restore and {} or self:BlizzardHides()
    -- Put back what's no longer hidden
    if db.savedCVars then
        for cvar, value in pairs(db.savedCVars) do
            if not hide[cvar] then
                pcall(SetCVar, cvar, value)
                db.savedCVars[cvar] = nil
            end
        end
        if next(db.savedCVars) == nil then db.savedCVars = nil end
    end
    for cvar, hidden in pairs(hide) do
        local ok, value = pcall(GetCVar, cvar)
        value = ok and Str(value) or nil
        if value then
            db.savedCVars = db.savedCVars or {}
            if db.savedCVars[cvar] == nil then
                -- The world text already drawn too big to see, with nothing saved: no player picks
                -- that, so BattleText's note of the original was lost (a crash before the settings
                -- were written). Then the game's own default is what to put back. (A "0" is left as
                -- it is: someone may have turned those numbers off themselves.)
                local original = value
                if value == hidden and hidden == XP_HIDDEN and C_CVar and C_CVar.GetCVarDefault then
                    local okDefault, default = pcall(C_CVar.GetCVarDefault, cvar)
                    default = okDefault and Str(default) or nil
                    if default then original = default end
                end
                db.savedCVars[cvar] = original
            end
            if value ~= hidden then pcall(SetCVar, cvar, hidden) end
        end
    end
end

-- A few sample lines, to see the look and place the areas
function BT:Test()
    local C = self.TEXT_COLORS
    local samples = {
        function() self:ShowCombat({ kind = "damage", fromMe = true, melee = true, amount = 27, unit = "Physical" }) end,
        function() self:ShowCombat({ kind = "damage", fromMe = true, spell = "Claw", amount = 50, unit = "Physical" }) end,
        function() self:Emit(self:Area("InDamage"), "-34", C.inDamage) end,
        function() self:ShowCombat({ kind = "damage", fromMe = true, spell = "Moonfire", amount = 112, unit = "Arcane", crit = true }) end,
        function() self:Emit(self:HealArea("incoming"), "+120 Rejuvenation", C.heal) end,
        function() self:ShowCombat({ kind = "heal", fromMe = true, spell = "Healing Touch", amount = 214 }) end,
        function() self:ShowCombat({ kind = "miss", fromMe = true, melee = true, missType = "DODGE" }) end,
        function()
            local color, school = self:IncomingSchool(nil, 32)
            self:Emit(self:Area("InDamage"), "-58" .. (school or ""), color or C.inDamage, { crit = true })
        end,
        function() self:Notify(L["+%s XP"]:format("103"), C.xp) end,
        function() self:ShowCombat({ kind = "damage", fromMe = true, melee = true, amount = 26, unit = "Physical", blocked = 3 }) end,
        function() self:Emit(self:Area("InMisses"), MissText("PARRY"), C.inAvoid) end,
        function() self:Notify(L["Killing blow!"], C.combat, { crit = true }) end,
    }
    -- Shown even while BattleText is turned off, and whatever is ticked in the options
    local LOOKS = { sticky = true, outCurved = true, inCurved = true, outScrollUp = true, inScrollUp = true,
        healScrollUp = true, nScrollUp = true, healArea = true, healOver = true, merge = true,
        shortNumbers = true, healWho = true, sizeByHit = true, outSwings = true, iconZoom = true,
        outIcons = true, outNames = true, inIcons = true, inNames = true, healIcons = true, healNames = true, nIcons = true }
    local function show(fn)
        local saved = self.db
        self.db = setmetatable({}, { __index = function(_, k)
            if k == "minDamage" or k == "minHeal" then return 0 end
            local v = saved[k]
            if type(v) == "boolean" and not LOOKS[k] then return true end
            return v
        end })
        self.testing = true
        local ok, err = pcall(fn)
        self.testing = false
        self.db = saved
        if not ok then error(err, 0) end
    end
    for i, fn in ipairs(samples) do
        if C_Timer and C_Timer.After then
            C_Timer.After((i - 1) * 0.3, function() show(fn) end)
        else
            show(fn)
        end
    end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function BT:PositionMinimapButton()
    local angle = math.rad(self.db.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function BT:BuildMinimapButton()
    local b = CreateFrame("Button", "BattleTextForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture(self.ICON)
    icon:SetPoint("TOPLEFT", 5, -4)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then BT:Test() else BT:OpenConfig() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            BT.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            BT:PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(BT.LOGO_TEXT .. " BattleText Forever")
        GameTooltip:AddLine(L["Left-click: options"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: show sample text"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move this button"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapButton = b
    self:PositionMinimapButton()
end

function BT:UpdateMinimapButton()
    if self.minimapButton then self.minimapButton:SetShown(self.db.minimap) end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
    Print(L["commands:"])
    print("  |cffffd100/btf|r  " .. L["open or close the options"])
    print("  |cffffd100/btf test|r  " .. L["show sample text"])
    print("  |cffffd100/btf lock|r, |cffffd100/btf unlock|r  " .. L["lock or unlock the text areas (unlock to drag them)"])
    print("  |cffffd100/btf reset|r  " .. L["put the text areas back where they started"])
    print("  |cffffd100/btf resetall|r  " .. L["put every setting back to how it started"])
    print("  |cffffd100/btf on|r, |cffffd100/btf off|r  " .. L["turn the text on or off"])
    print("  |cffffd100/btf debug|r  " .. L["record the combat lines the game sends; |cffffd100/btf copy|r shows them (for bug reports)"])
    print("  |cffffd100/btf last|r  " .. L["your last fight, spell by spell"])
    print("  |cffffd100/btf check|r  " .. L["check the spells, texts and icons BattleText uses against this game"])
    print("  |cffffd100/btf gear|r  " .. L["show what BattleText read from your gear (then /btf copy)"])
    print("  |cffffd100/btf export|r, |cffffd100/btf import|r  " .. L["share your settings as text, or take someone else's"])
end

-- Keybinding names (Options > Keybindings > BattleText Forever)
BattleTextForever = BT
_G["BINDING_NAME_CLICK BattleTextForeverStart:LeftButton"] = L["Start BattleText"]
BINDING_NAME_BATTLETEXTFOREVER_OPTIONS = L["Open options"]

SLASH_BATTLETEXTFOREVER1 = "/btf"
SLASH_BATTLETEXTFOREVER2 = "/battletext"
SlashCmdList.BATTLETEXTFOREVER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "config" or cmd == "options" then
        BT:OpenConfig()
    elseif cmd == "test" then
        BT:Test()
    elseif cmd == "lock" or cmd == "unlock" then
        BT:SetLocked(cmd == "lock")
        Print(cmd == "lock" and L["text areas locked."] or L["text areas unlocked. Drag the boxes, then /btf lock."])
    elseif cmd == "reset" then
        BT:ResetPositions()
        Print(L["text areas moved back to where they started."])
    elseif cmd == "resetall" then
        BT:ConfirmResetAll()
    elseif cmd == "on" or cmd == "off" then
        BT.db.enabled = cmd == "on"
        BT:ApplySettings()
        Print(cmd == "on" and L["on."] or L["off."])
    elseif cmd == "debug" then
        BT.db.debug = not BT.db.debug
        if BT.db.debug then BT.recorded = {} end
        Print(BT.db.debug and L["debug on. Fight for a moment, then type /btf copy to see what the game sent."] or L["debug off."])
    elseif cmd == "copy" then
        BT:OpenCopyWindow()
    elseif cmd == "check" then
        BT:CheckGameData()
    elseif cmd == "gear" then
        BT:ReportGear()
    elseif cmd == "last" then
        BT:OpenLastFight()
    elseif cmd == "export" or cmd == "import" then
        BT:OpenShareWindow(cmd)
    else
        Help()
    end
    if BT.RefreshConfig then BT:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
-- Registered one by one, in case this client doesn't have one of them
for _, e in ipairs({ "COMBAT_LOG_MESSAGE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_LOGOUT",
    "PLAYER_XP_UPDATE", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
    pcall(events.RegisterEvent, events, e)
end
pcall(events.RegisterEvent, events, "UNIT_COMBAT")   -- every unit: you, your target, the mobs around you
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SENT", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_CHANNEL_START", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
pcall(events.RegisterEvent, events, "PLAYER_EQUIPMENT_CHANGED")
pcall(events.RegisterUnitEvent, events, "UNIT_INVENTORY_CHANGED", "player")
pcall(events.RegisterEvent, events, "GROUP_ROSTER_UPDATE")   -- (InGroup asks again)
pcall(events.RegisterEvent, events, "PLAYER_SWING")   -- your own auto attacks (vouches for them in a group)
-- Ability alerts that the game's own buttons know about, and combo points
for _, e in ipairs({ "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED", "SPELL_ACTIVATION_OVERLAY_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" }) do
    pcall(events.RegisterEvent, events, e)
end
pcall(events.RegisterUnitEvent, events, "UNIT_HEALTH", "target", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_MAXHEALTH", "player")   -- (low health)
pcall(events.RegisterUnitEvent, events, "UNIT_POWER_UPDATE", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_POWER_FREQUENT", "player")   -- (Life Tap's mana)
pcall(events.RegisterEvent, events, "SPELL_UPDATE_COOLDOWN")        -- Cooldowns ready
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_INTERRUPTED")   -- every unit: casts you stop

-- Events only worth handling while BattleText is turned on
local WHILE_ON = { UNIT_COMBAT = true, UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, PLAYER_SWING = true, SPELL_UPDATE_USABLE = true, UNIT_HEALTH = true,
    SPELL_ACTIVATION_OVERLAY_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, CHAT_MSG_LOOT = true,
    CHAT_MSG_MONEY = true, CHAT_MSG_SKILL = true, CHAT_MSG_COMBAT_FACTION_CHANGE = true, CHAT_MSG_COMBAT_HONOR_GAIN = true,
    SPELL_UPDATE_COOLDOWN = true, UNIT_SPELLCAST_INTERRUPTED = true }

events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        BattleTextForeverDB = BattleTextForeverDB or {}
        BT:MoveOldSettings(BattleTextForeverDB)
        FillDefaults(BattleTextForeverDB, DEFAULTS)
        BattleTextForeverCharDB = BattleTextForeverCharDB or {}
        local char = BattleTextForeverCharDB
        if char.own and type(char.settings) == "table" then
            BT:MoveOldSettings(char.settings)
            FillDefaults(char.settings, DEFAULTS)
            BT.db = char.settings
        else
            char.own = nil
            BT.db = BattleTextForeverDB
        end
        BT:ApplyColors()
        return
    elseif event == "PLAYER_LOGIN" then
        -- /btf debug is for one session's bug report (the record isn't kept): left on, it would
        -- write down every unit's every hit for good
        BT.db.debug = false
        BT:AddSharedFonts()   -- (other addons have loaded by now)
        Parser:Init()
        BT:BuildAreas()
        BT:BuildStartButton()
        BT:BuildMinimapButton()
        BT:HookCombatLog()
        BT:HookLowHealth()
        BT.built = true
        BT:ApplySettings()
        BT:OnXP()
        -- The game turns the lines off whenever the Combat Log window hides
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(3, function() BT:KeepLogFlowing() end)
        end
        if BT.db.loginMessage then print(T.CHAT_PREFIX .. " " .. L["loaded. Type /btf for options."]) end
        return
    end
    if not BT.built then return end
    -- Turned off: the combat is left alone (nothing is worked out, no sounds). What keeps
    -- the addon's own state right for when it's turned back on still runs.
    if not BT.db.enabled and WHILE_ON[event] then return end

    if event == "COMBAT_LOG_MESSAGE" then
        BT:OnCombatLogMessage(a1, a2, a3, a4, a5)
    elseif event == "UNIT_COMBAT" then
        BT:OnUnitCombat(a1, a2, a3, a4, a5)
    elseif event == "UNIT_SPELLCAST_SENT" then
        BT:OnSpellSent(a2, a4)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        BT:OnSpellcast(a3)
        BT:NoteInterruptCast(a3)
        BT:WatchCooldown(a3)
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if BT.cdCast and next(BT.cdCast) then BT:LookCooldowns(true) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        BT:OnInterrupted(a1, a2, a3, a4)
    elseif event == "GROUP_ROSTER_UPDATE" then
        BT.groupAt = nil
    elseif event == "PLAYER_SWING" then
        BT:OnSwing(a1, a2)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local id = Num(a3)
        local name = id and SpellName(id)
        if name then BT:SpellLists() BT:CastTo(id, name) BT:NoteHelpfulCast(id, name) BT:StartArea(name, id) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        BT:StopArea(Num(a3))
    elseif event == "UNIT_AURA" then
        BT:ScanShield()
        BT:CheckProcs()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if a1 == 16 or a1 == 17 then BT.dualWield = nil end   -- (a weapon changed: an off hand swing will say again)
        BT:ScanItemShields()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        BT:RescanGearSoon()
    elseif event == "UNIT_HEALTH" and Str(a1) == "player" or event == "UNIT_MAXHEALTH" then
        BT:CheckLowHealth()
    elseif event == "SPELL_UPDATE_USABLE" or event == "UNIT_HEALTH" then
        BT:CheckUsable()
    elseif event == "PLAYER_TARGET_CHANGED" then
        BT:QuietComboPoints()
        BT:CheckUsable(true)
    elseif event == "SPELL_ACTIVATION_OVERLAY_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        BT:OnSpellOverlay(a1, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    elseif event == "UNIT_POWER_FREQUENT" then
        if Str(a2) == "MANA" then BT:OnMana() end
    elseif event == "UNIT_POWER_UPDATE" then
        local kind = Str(a2)
        if kind == "COMBO_POINTS" then BT:OnComboPoints()
        elseif kind == "MANA" then
            BT:OnMana()
            BT:CheckLowMana()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        BT:RemakeSpellLists()
        BT:ScanShield()      -- last look at your buffs and gear before the fight hides them
        BT:ScanItemShields()
        BT:SetStartMacro()   -- last chance before the fight to note which chat tab you're on
        BT:KeepLogFlowing()   -- (in case something turned the lines off since)
        if BT.db.nCombat then BT:Notify(L["+Combat"], BT.TEXT_COLORS.combat) end
        BT.fight = { start = GetTime(), damage = 0, heal = 0 }
        BT.actedInFight = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        if BT.db.nCombat then BT:Notify(L["-Combat"], BT.TEXT_COLORS.notify) end
        BT:FightSummary()
        BT:ScanShield()   -- your buffs can be read again: what changed during the fight
        BT:ForgetOldDots()
        if BT.startPending then
            BT.startPending = nil
            BT:UpdateStartButton()
        end
        BT:CheckAutoStart()
        BT:SetStartMacro()
        BT:ApplyBlizzardText()
        BT:ScanItemShields()   -- (gear changed in the fight is read now)
    elseif event == "PLAYER_LOGOUT" then
        BT:ApplyBlizzardText(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        BT:ScanShield()
        BT:ScanItemShields()
        BT:HookCombatLog()
        -- Start the lines: the game's Combat Log has loaded its filter by now, and
        -- turned the lines off because its window is hidden
        BT:KeepLogFlowing()
        BT:SetStartMacro()
        BT:UpdateStartButton()
        BT.lastXP = nil
        BT:OnXP()
        BT:CheckLowHealth()
        BT:CheckLowMana()
        BT.manaSeen = ManaNow()
    elseif event == "PLAYER_XP_UPDATE" then
        BT:OnXP()
    elseif event == "CHAT_MSG_LOOT" then
        BT:OnLoot(a1)
    elseif event == "CHAT_MSG_MONEY" then
        BT:OnChatNotice("nMoney", a1, BT.TEXT_COLORS.notify)
    elseif event == "CHAT_MSG_SKILL" then
        BT:OnChatNotice("nSkill", a1, BT.TEXT_COLORS.power)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        BT:OnChatNotice("nRep", a1, BT.TEXT_COLORS.power)
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        BT:OnChatNotice("nHonor", a1, BT.TEXT_COLORS.notify)
    end
end)
