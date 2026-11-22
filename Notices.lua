-- BattleText Forever: notifications, experience and loot, the Start button.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, T, L, Print, IsSecret, Num = S.BT, S.T, S.L, S.Print, S.IsSecret, S.Num
local Str, IsEnglish, Commas, PERIODIC_SPELLS, NEXT_SWING_SPELLS, SHIELD_SPELLS = S.Str, S.IsEnglish, S.Commas, S.PERIODIC_SPELLS, S.NEXT_SWING_SPELLS, S.SHIELD_SPELLS
local SEAL_SPELLS, JUDGEMENT, SELF_BUFFS, FLIGHT_SPELLS, HAWK_SPELL, RANGED_SPELLS = S.SEAL_SPELLS, S.JUDGEMENT, S.SELF_BUFFS, S.FLIGHT_SPELLS, S.HAWK_SPELL, S.RANGED_SPELLS
local ATTACK_SPELL, THROWN_ITEMS, AREA_SPELLS, REACTIVE_SPELLS, DISPEL_SPELLS, HEAL_OR_HARM = S.ATTACK_SPELL, S.THROWN_ITEMS, S.AREA_SPELLS, S.REACTIVE_SPELLS, S.DISPEL_SPELLS, S.HEAL_OR_HARM
local LIGHTS_VIGIL, PRAYER_OF_MENDING, LIFE_TAP, INTERRUPT_SPELLS, POISON_SPELLS, TOUCH_OF_THE_GRAVE = S.LIGHTS_VIGIL, S.PRAYER_OF_MENDING, S.LIFE_TAP, S.INTERRUPT_SPELLS, S.POISON_SPELLS, S.TOUCH_OF_THE_GRAVE

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
function BT:Notify(text, color, opts)
    self:Emit(self:Area("Notify"), text, color or self.TEXT_COLORS.notify, opts)
end

function BT:OnXP()
    local xp, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
    if not xp or not max then return end
    local last, lastMax = self.lastXP, self.lastXPMax
    self.lastXP, self.lastXPMax = xp, max
    if not last or not self.db.nXP then return end
    local gained = xp - last
    if gained < 0 and lastMax then gained = (lastMax - last) + xp end   -- levelled up
    if gained > 0 then self:Notify(L["+%s XP"]:format(Commas(gained)), self.TEXT_COLORS.xp) end
end

-- A game sentence like "You receive loot: %sx%d." as a pattern that matches it
local function SentencePattern(fmt)
    local p = fmt:gsub("%%%d*%$?s", "\1"):gsub("%%%d*%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p
end

-- "You receive loot: [Linen Cloth]x2." -> "+2 [Linen Cloth]"
local LOOT_KEYS = { "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }
local LOOT_FALLBACK = { LOOT_ITEM_SELF = "You receive loot: %s", LOOT_ITEM_PUSHED_SELF = "You receive item: %s",
    LOOT_ITEM_CREATED_SELF = "You create: %s" }
function BT:OnLoot(message)
    message = Str(message)
    if not message or not self.db.nLoot then return end
    -- Only your own loot: the line is one of the game's sentences for it
    if not self.lootPatterns then
        self.lootPatterns = {}
        for _, key in ipairs(LOOT_KEYS) do
            local fmt = Str(_G[key]) or LOOT_FALLBACK[key]
            if fmt then self.lootPatterns[#self.lootPatterns + 1] = SentencePattern(fmt) end
        end
    end
    local mine = false
    for _, pattern in ipairs(self.lootPatterns) do
        if message:find(pattern) then mine = true break end
    end
    if not mine then return end
    local link = message:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or message:match("(|Hitem:.-|h.-|h)")
    if not link then return end
    local count = tonumber(message:match("|h|r?x(%d+)")) or 1
    local icon = ""
    local id = tonumber(link:match("|Hitem:(%d+)"))
    if id and self.db.nIcons and C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, id)
        if ok and not IsSecret(tex) and tex then icon = self:IconTag(tex) end
    end
    self:Notify(icon .. "+" .. count .. " " .. link, self.TEXT_COLORS.loot)
end

-- Professions whose spell has another name than the skill (the rest are found by name)
local SKILL_SPELLS = { Herbalism = 2366, Mining = 2575, Fishing = 7620 }

-- A skill-up's icon: the skill's spell, when the game has one ("Your skill in Cooking has increased to 5")
function BT:SkillIcon(message)
    if not self.db.nIcons then return "" end
    -- (the game's sentence can number its parts, as German does: "Eure Fertigkeit '%1$s' hat sich
    -- auf %2$d erhöht.", and a language may put the number first)
    if not self.skillPattern then
        self.skillPattern = SentencePattern(Str(SKILL_RANK_UP) or "Your skill in %s has increased to %d.")
    end
    local ok, a, b = pcall(string.match, message, self.skillPattern)
    if not ok or not a then return "" end
    local skill = tonumber(a) and b or a
    if not skill then return "" end
    return self:IconText(SKILL_SPELLS[skill] or skill)
end

-- /btf check: asks the game about every spell, skill, text and icon BattleText
-- relies on, on any character (the game knows every spell, not only your class's).
-- Prints what's missing or named differently, and keeps the report for /btf copy.
function BT:CheckGameData()
    local report, problems = {}, 0
    local function line(ok, text)
        if not ok then problems = problems + 1 end
        report[#report + 1] = (ok and "ok      " or "PROBLEM ") .. text
    end
    local english = GetLocale ~= nil and IsEnglish()
    local function spell(id, expected, what)
        local ok, name = pcall(C_Spell.GetSpellName, id)
        name = ok and Str(name) or nil
        if not name then
            line(false, ("%s %d (%s): not in this game"):format(what, id, expected))
        elseif english and name ~= expected then
            line(false, ("%s %d: the game calls it %s, BattleText expects %s"):format(what, id, name, expected))
        else
            line(true, ("%s %d: %s"):format(what, id, name))
        end
    end
    for _, e in ipairs(PERIODIC_SPELLS) do spell(e[1], e[2], "tick") end
    for _, e in ipairs(SHIELD_SPELLS) do spell(e[1], e[2], "shield") end
    for _, e in ipairs(SEAL_SPELLS) do spell(e[1], e[2], "seal") end
    for _, e in ipairs(SELF_BUFFS) do spell(e[1], e[2], "buff") end
    for _, e in ipairs(NEXT_SWING_SPELLS) do spell(e[1], e[2], "next swing") end
    for _, e in ipairs(FLIGHT_SPELLS) do spell(e[1], e[2], "flies") end
    spell(HAWK_SPELL[1], HAWK_SPELL[2], "hawk")
    for id, e in pairs(RANGED_SPELLS) do spell(id, e[1], "ranged") end
    line(self:IconText(ATTACK_SPELL) ~= "", "swing icon " .. ATTACK_SPELL .. " (no weapon): "
        .. (self:IconText(ATTACK_SPELL) ~= "" and "found" or "missing"))
    for _, e in ipairs(THROWN_ITEMS) do spell(e[1], e[2], "thrown") end
    for _, e in ipairs(AREA_SPELLS) do spell(e[1], e[2], "keeps hitting") end
    for _, e in ipairs(REACTIVE_SPELLS) do spell(e[1], e[2], "alert") end
    for _, e in ipairs(DISPEL_SPELLS) do spell(e[1], e[2], "dispel") end
    for _, e in ipairs(POISON_SPELLS) do spell(e[1], e[2], "poison") end
    for _, e in ipairs(INTERRUPT_SPELLS) do spell(e[1], e[2], "interrupt") end
    spell(JUDGEMENT[1], JUDGEMENT[2], "seal")
    for _, id in ipairs(TOUCH_OF_THE_GRAVE) do spell(id, TOUCH_OF_THE_GRAVE.name, "racial") end
    for _, e in ipairs(HEAL_OR_HARM) do spell(e[1], e[2], "heal or harm") end
    for _, id in ipairs(LIGHTS_VIGIL) do spell(id, LIGHTS_VIGIL.name, "party heal") end
    for _, id in ipairs(PRAYER_OF_MENDING) do spell(id, PRAYER_OF_MENDING.name, "heals as it jumps") end
    for _, id in ipairs(LIFE_TAP) do spell(id, LIFE_TAP.name, "health into mana") end
    local skillNames = { [2366] = "Herbalism", [2575] = "Mining", [7620] = "Fishing" }
    for skill, id in pairs(SKILL_SPELLS) do spell(id, skillNames[id] or skill, "skill " .. skill) end
    line(Str(SKILL_RANK_UP) ~= nil, "text SKILL_RANK_UP: " .. tostring(Str(SKILL_RANK_UP)))
    local getFile = GetFileIDFromPath
    if getFile then
        local icons = { T.LOGO }
        for _, t in ipairs(self.CONFIG_TABS or {}) do icons[#icons + 1] = t.icon end
        for _, path in ipairs(icons) do
            local ok, id = pcall(getFile, path)
            line(ok and Num(id) ~= nil, "icon " .. path)
        end
    end
    self.recorded = {}
    for _, text in ipairs(report) do self:Record(text) end
    if problems == 0 then
        Print(L["all %d checks passed."]:format(#report))
    else
        Print(L["%d of %d checks found a problem:"]:format(problems, #report))
        for _, text in ipairs(report) do
            if text:find("^PROBLEM") then print("  " .. text:gsub("^PROBLEM ", "")) end
        end
        Print(L["type /btf copy to copy the full report."])
    end
    return problems, report
end

-- Chat lines shown as they are, minus the trailing period
function BT:OnChatNotice(setting, message, color)
    message = Str(message)
    if not message or not self.db[setting] then return end
    local icon = setting == "nSkill" and self:SkillIcon(message) or ""
    self:Notify(icon .. (message:gsub("%.%s*$", "")), color)
end

---------------------------------------------------------------------------
-- Getting the combat log lines flowing
--
-- The game's Combat Log code loads its filter when it loads at login, then turns
-- the lines off because its window is hidden (and again whenever it hides).
-- An addon can't load the filter itself, but it can turn the lines back on, so
-- BattleText does that at login and keeps them coming. If a fight ends and no
-- line came, the filter didn't load: the Start button shows, and its click opens
-- and closes the Combat Log tab, which loads it.
---------------------------------------------------------------------------
-- The Combat Log window. COMBATLOG is set by Blizzard's Combat Log code once
-- it has loaded and put its own show/hide handlers on the window.
-- Before that (Blizzard_CombatLog is load-on-demand), the window is ChatFrame2 all the same
-- (FloatingChatFrame's IsCombatLog), so its OnShow is hooked either way.
function BT:CombatLogFrame()
    return _G.COMBATLOG or _G.ChatFrame2
end

function BT:KeepLogFlowing()
    if not self.db.enabled then return end
    if C_CombatLog and C_CombatLog.SetFilteredEventsEnabled then
        pcall(C_CombatLog.SetFilteredEventsEnabled, true)
    end
end

-- Turned off: leave the lines the way the game has them (on only while its
-- Combat Log window is showing)
function BT:StopLogFlowing()
    local log = self:CombatLogFrame()
    if log and log.IsShown and log:IsShown() then return end
    if C_CombatLog and C_CombatLog.SetFilteredEventsEnabled then
        pcall(C_CombatLog.SetFilteredEventsEnabled, false)
    end
end

function BT:BuildStartButton()
    -- A secure button can't be set up in combat (after a /reload mid-fight)
    if self.startButton then return end
    if InCombatLockdown() then
        self.startPending = true
        return
    end
    local b = CreateFrame("Button", "BattleTextForeverStart", UIParent, "SecureActionButtonTemplate")
    b:SetSize(170, 26)
    b:SetPoint("TOP", UIParent, "TOP", 0, -140)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp", "AnyDown")
    -- Act on the release, whatever "act on key down" is set to: a /click in a macro
    -- only sends the release, so /click BattleTextForeverStart in your own macro works
    b:SetAttribute("useOnKeyDown", false)
    -- The shared header bar: logo, then the words in gold on red
    T.HeaderStrip(b, L["Start BattleText"])
    b:FitLogo(26)
    b.icon, b.label = b.logo, b.text
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Start BattleText"], T.C.gold[1], T.C.gold[2], T.C.gold[3])
        GameTooltip:AddLine(L["BattleText couldn't turn on the game's combat lines by itself. "
            .. "This click opens the Combat Log tab once and switches back, which starts them."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Playing alone, your hits show without it. In a group, BattleText needs those lines to tell "
            .. "your hits from everyone else's."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to hide it until you log in again."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Right-click hides it until the next login: a harmless secure action instead of the macro
    b:SetAttribute("type2", "attribute")
    b:SetAttribute("attribute-name", "btf-hidden")
    b:SetAttribute("attribute-value", true)
    -- Go back to whichever chat tab is selected right now
    b:SetScript("PreClick", function() BT:SetStartMacro() end)
    -- The click has opened and closed the tab; the game turned the lines off
    -- again when it closed, so turn them back on
    b:SetScript("PostClick", function(_, button)
        if button == "RightButton" then
            BT.startHidden = true
            BT:UpdateStartButton()
            return
        end
        BT:KeepLogFlowing()
        BT:CheckStarted()
    end)
    b:Hide()
    self.startButton = b
    self:SetStartMacro()
end

-- The click: open the Combat Log tab, then go back to the tab you were on.
-- If you're already on the Combat Log tab, leave it and come back.
-- Once the lines are flowing it does nothing, so a /click BattleTextForeverStart
-- in a macro you press all the time doesn't flick your chat tabs.
function BT:SetStartMacro()
    local b = self.startButton
    if not b or InCombatLockdown() then return end
    if self.started then
        if b.macro ~= false then
            b.macro = false
            b:SetAttribute("type", nil)
            b:SetAttribute("macrotext", nil)
        end
        return
    end
    local selected
    if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
        local ok, frame = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok then selected = frame end
    end
    selected = selected or _G.SELECTED_DOCK_FRAME
    local macro
    if selected and selected == _G.ChatFrame2 then
        macro = "/click ChatFrame1Tab\n/click ChatFrame2Tab"
    else
        local back = "ChatFrame1Tab"
        if selected and selected.GetName then
            local name = Str(selected:GetName())
            if name and _G[name .. "Tab"] then back = name .. "Tab" end
        end
        macro = "/click ChatFrame2Tab\n/click " .. back
    end
    if b.macro == macro then return end
    b.macro = macro
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macro)
end

-- A click that didn't open the Combat Log: a chat addon (Chattynator and the like)
-- has replaced the game's chat window and keeps its tabs hidden, so the click
-- reaches a tab nobody can see. Say so, once. (Looked at a moment later: the click
-- comes down and up, and only one of them runs the macro.)
function BT:CheckStarted()
    local function check()
        if BT.started or BT.startFailSaid then return end
        -- (the game's Combat Log tab is right there: the click reached it, so a chat addon isn't the
        -- reason; the button stays for another try and nothing is said)
        local tab = _G.ChatFrame2Tab
        if tab and tab.IsVisible and tab:IsVisible() then return end
        BT.startFailSaid = true
        Print(L["the click couldn't open the game's Combat Log tab. A chat addon (like Chattynator) may be "
            .. "hiding it, and there's no real way around that. Alone, your hits still show without it; in a group, "
            .. "other people's hits may show as yours. Right-click the button to hide it."])
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, check) else check() end
end

-- Only needed when BattleText couldn't start the lines itself: shown after a fight
-- that ended with no line (startNeeded), until the Combat Log window has been
-- shown or a line has arrived (or right-clicked away)
function BT:UpdateStartButton()
    if not self.startButton then
        if self.built then self:BuildStartButton() end
        if not self.startButton then return end
    end
    local b = self.startButton
    local show = self.db.enabled and self.startNeeded and not self.started and not self.startHidden or false
    if show == b.wanted then return end
    if InCombatLockdown() then
        self.startPending = true   -- showing or hiding a secure button waits for combat to end
        return
    end
    b.wanted = show
    b:SetShown(show)
end

-- A fight ended and no line came: BattleText couldn't start by itself, so the Start
-- button shows, and (once a session) a line in chat says so
function BT:CheckAutoStart()
    if self.started or not self.db.enabled then return end
    -- "My actions" has lines only for what you do: a fight where you only got hit (a mob caught you
    -- and you ran, or it died to someone else) proves nothing (1.24.2: the button and its chat line
    -- came for a player whose lines were fine)
    if not self.actedInFight then return end
    self.startNeeded = true
    self:UpdateStartButton()
    if not self.startReminded then
        self.startReminded = true
        self:RemindStart()
    end
end

function BT:RemindStart()
    if not (self.db.enabled and self.db.startReminder) or self.started or self.startHidden then return end
    local key = GetBindingKey and Str(GetBindingKey("CLICK BattleTextForeverStart:LeftButton"))
    Print((key and L["click %s at the top of your screen (or press %s). It names your bleed ticks and, in a group, "
            .. "leaves other people's hits out."] or L["click %s at the top of your screen. It names your bleed ticks and, "
            .. "in a group, leaves other people's hits out."]):format("|cffffd100" .. L["Start BattleText"] .. "|r", key))
end

-- When the Combat Log window is shown the game loads its filter (so the lines
-- start); when it hides, the game turns them off, and we turn them back on
function BT:HookCombatLog()
    local log = self:CombatLogFrame()
    if not log or self.hooked then return end
    self.hooked = true
    log:HookScript("OnShow", function()
        BT.started = true
        BT:UpdateStartButton()
    end)
    log:HookScript("OnHide", function() BT:KeepLogFlowing() end)
end
