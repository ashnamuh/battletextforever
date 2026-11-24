-- BattleText Forever: options window (/btf), in the shared look (Theme.lua).
-- Tabs down the left: General, then how the text looks (Text, Motion), then
-- one tab per text area (Outgoing, Incoming, Healing, Notifications), then Spells and Colors.
--
-- Layout rules: two columns (12 and COL2); rows 26 apart; a dropdown after a
-- row label starts at DROP_X; a note explaining a card is its last line, full
-- width. A control that does nothing with the other settings as they are is
-- greyed out (enabledIf), and its tooltip still shows.

local ADDON, ns = ...
local BT = ns.BT
local T = ns.Theme
local L = ns.L
local C, Text, Card = T.C, T.Text, T.Card

-- A button grows to fit its text (other languages' words are often longer than the
-- English), never shrinks below the width it was given
local function FitButton(b, width)
    local w = b.GetTextWidth and b:GetTextWidth()
    w = type(w) == "number" and math.ceil(w) + 16 or 0
    b:SetWidth(math.max(width, w))
end
local function FlatButton(parent, text, width, height)
    local b = T.FlatButton(parent, text, width, height)
    FitButton(b, width or 100)
    return b
end

-- Where the control after the label of a switch at swX goes: at x (its usual place),
-- or later when the label is longer, keeping the same right edge (right). The label
-- is cut short only if the control would get narrower than least.
local function AfterLabel(sw, swX, x, right, least)
    local w = sw.label.GetStringWidth and sw.label:GetStringWidth()
    local labelLeft = swX + 38   -- (the switch is 30 wide, its label 8 after it)
    local at = math.max(x, labelLeft + math.ceil(type(w) == "number" and w or 0) + 8)
    if right - at < least then
        at = right - least
        sw.label:SetWidth(at - 8 - labelLeft)
        sw.label:SetWordWrap(false)
    end
    return at, right - at
end

local PAGE_W = T.WINDOW.PAGE_W
local COL2 = 270     -- the second column of a card
local DROP_X = 110   -- where a dropdown starts, after its row label

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end

local function Print(msg) BT.Print(msg) end

-- Greys a control out while enabledIf() says it does nothing
local function DependsOn(widget, enabledIf)
    if enabledIf then AddRefresher(function() widget:SetDisabled(not enabledIf()) end) end
end

-- A note at the bottom of a card, full width
-- How tall a wrapped text is (0 when the game can't say yet)
local function TextHeight(fs)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    return type(h) == "number" and math.ceil(h) or 0
end

local function CardNote(card, text, y)
    return T.Note(card, text, 12, y, PAGE_W - 24)
end

-- A switch bound to a setting. "locked" reads as "Move the text areas", so it's turned round.
local function Setting(parent, text, x, y, key, tip, enabledIf)
    local sw = T.LabeledSwitch(parent, text, x, y)
    sw.key = key
    sw:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetOn(not self:IsOn())
        if key == "locked" then
            BT:SetLocked(not self:IsOn())
        else
            BT.db[key] = self:IsOn()
            BT:ApplySettings()
            if key == "hideBlizzard" and InCombatLockdown() then
                Print(L["the game's own numbers change when this fight ends."])
            end
        end
        BT:RefreshConfig()   -- (other controls may depend on it)
    end)
    if tip then T.Tooltip(sw, text, tip) end
    AddRefresher(function()
        local v = BT.db[key]
        if key == "locked" then v = not v end
        sw:SetOn(v and true or false)
    end)
    DependsOn(sw, enabledIf)
    return sw
end

-- A slider bound to a number setting, over its range in BT.RANGES.
--   o.suffix, o.step, o.fmt  how the value reads   o.zero  what 0 reads as ("Off")
--   o.tip  tooltip   o.enabledIf  greyed out unless it says yes
local function Slider(parent, text, x, y, key, o)
    o = o or {}
    local range = BT.RANGES[key]
    local s = T.Slider(parent, text, x, y, 244,
        function() return BT.db[key] end,
        function(v) BT.db[key] = v BT:ApplyAreas() end,   -- (the areas' sizes; the rest is read as lines come)
        range[1], range[2], o.suffix, o.step, o.fmt, o.zero)
    s.label, s.key = text, key
    if o.tip then T.Tooltip(s, text, o.tip) end
    AddRefresher(s.Refresh)
    DependsOn(s, o.enabledIf)
    return s
end

local function Dropdown(parent, x, y, width, keys, labels, key, choose, tip, enabledIf)
    local d = T.Dropdown(parent, width, keys, labels, function() return BT.db[key] end, function(k)
        choose(k)
        BT:RefreshConfig()
    end)
    d:SetPoint("TOPLEFT", x, y)
    d.key = key
    if tip then T.Tooltip(d, nil, tip) end
    AddRefresher(d.Refresh)
    DependsOn(d, enabledIf)
    return d
end

local function Either(...)
    local keys = { ... }
    return function()
        for _, k in ipairs(keys) do if BT.db[k] then return true end end
        return false
    end
end

-- The two switches the combat tabs share
local function IconsAndNames(card, y, section, what, enabledIf)
    Setting(card, L["Icons"], 12, y, section .. "Icons", L["Shows the spell's icon beside %s."]:format(what), enabledIf)
    Setting(card, L["Names"], COL2, y, section .. "Names", L["Shows the spell's name beside %s."]:format(what), enabledIf)
end

-- A box for the order of a line of yours (key: "outFormat" or "healFormat"), with Reset beside it
local function LineOrder(card, y, key, what, enabledIf)
    T.RowLabel(card, L["Line order"], 12, y - 2)
    local box = T.EditBox(card, 250)
    box:SetPoint("TOPLEFT", DROP_X, y)
    box:SetMaxLetters(60)
    box:SetScript("OnTextChanged", function(self, typed)
        if typed then BT.db[key] = self:GetText() end
    end)
    box:SetScript("OnEditFocusLost", function(self)
        if not BT.db[key]:find("%S") then BT.db[key] = BT.LINE_FORMAT end
        self:SetText(BT.db[key])
    end)
    T.Tooltip(box, L["Line order"], L["How %s are written: move the parts around, or take one out. {icon} is the "
        .. "spell's icon, {name} its name, {damage} the number. Example: {icon} {damage} {name}. The Icons and "
        .. "Names switches still hide theirs."]:format(what))
    local reset = FlatButton(card, L["Reset"], 70)
    reset:SetPoint("LEFT", box, "RIGHT", 8, 0)
    T.Tooltip(reset, nil, L["Back to {icon} {name} {damage}."])
    reset:SetScript("OnClick", function()
        if reset.disabled then return end
        BT.db[key] = BT.LINE_FORMAT
        box:ClearFocus()
        BT:RefreshConfig()
    end)
    T.Disabler(box, { box })
    T.Disabler(reset, { reset })
    AddRefresher(function()
        if not box:HasFocus() then box:SetText(BT.db[key] or BT.LINE_FORMAT) end
        local off = enabledIf and not enabledIf() or false
        box:SetDisabled(off)
        box:EnableKeyboard(not off)   -- (greyed out: can't be typed in)
        if off then box:ClearFocus() end
        reset:SetDisabled(off)
    end)
    return box, reset
end

-- Each area's own text size, opacity and movement. curved: the side areas, whose
-- lines can bow outward. enabledIf/offNote: when the area isn't in use, and why.
local function AreaLook(p, y, prefix, curved, enabledIf, offNote)
    local card = Card(p, L["Appearance"], 0, y, PAGE_W, curved and 142 or 116)
    Slider(card, L["Size"], 12, -30, prefix .. "Size", { suffix = "%", step = 5, enabledIf = enabledIf,
        tip = L["This area's text, as a percent of the text size on the Text tab."] })
    Slider(card, L["Opacity"], COL2, -30, prefix .. "Alpha", { suffix = "%", step = 5, enabledIf = enabledIf,
        tip = L["How see-through this area's text is. 100% is solid."] })
    local keys = {}
    for _, st in ipairs(BT.STYLES) do keys[#keys + 1] = st.key end
    T.RowLabel(card, L["Movement"], 12, -82)
    local style = prefix .. "Style"
    local d = Dropdown(card, DROP_X, -82, 150, keys, function(k) return BT:StyleName(k) end, style,
        function(k) BT.db[style] = k end,
        L["Scroll: lines move up or down the area, one after another. Pop: each one jumps out somewhere in the area "
        .. "and fades. Fountain: thrown up and falling to the side. Horizontal: they slide sideways, away from the "
        .. "middle. Crits that stay in place (Motion tab) stay put whatever this is."], enabledIf)
    local function scrolling()
        return (not enabledIf or enabledIf()) and BT:AreaStyle({ def = { prefix = prefix } }) == "scroll"
    end
    Setting(card, L["Scroll upward"], COL2, -84, prefix .. "ScrollUp",
        L["Lines start at the bottom and move up. Off: they scroll down. Only with Scroll movement."], scrolling)
    if curved then
        Setting(card, L["Curved scrolling"], COL2, -110, prefix .. "Curved",
            L["Lines bow outward as they scroll. Off: straight lines. Only with Scroll movement."], scrolling)
        -- (the side areas: their lines can line up left, centered or right)
        local aligns = {}
        for _, al in ipairs(BT.ALIGNS) do aligns[#aligns + 1] = al.key end
        T.RowLabel(card, L["Alignment"], 12, -110)
        Dropdown(card, DROP_X, -110, 150, aligns, function(k) return BT:AlignName(k) end, prefix .. "Align",
            function(k) BT.db[prefix .. "Align"] = k end,
            L["Which side this area's lines line up on. Crits that stay in place line up on the other side, "
            .. "so they don't sit on top of the rest."], enabledIf)
    end
    if offNote then
        local note = T.Note(card, offNote, 0, 0)
        note:ClearAllPoints()
        note:SetPoint("TOPRIGHT", -12, -10)
        AddRefresher(function() note:SetShown(not enabledIf()) end)
    end
    return d
end

-- Opens the game's color picker on color c ({ r, g, b }): pick(r, g, b) as it changes,
-- cancel() if the player cancels
local function PickColor(c, pick, cancel)
    local picker = ColorPickerFrame
    if not (picker and picker.SetupColorPickerAndShow) then return end
    picker:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3], hasOpacity = false,
        swatchFunc = function() pick(picker:GetColorRGB()) end,
        cancelFunc = cancel,
    })
end

-- A color square that opens the game's color picker (its label works the same)
local function Swatch(parent, text, x, y, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 16)
    b:SetPoint("TOPLEFT", x, y)
    b.fill = T.Fill(b, { 1, 1, 1, 1 }, "ARTWORK")
    T.Border(b, C.edge)
    b.label = Text(parent, text, "GameFontHighlight")
    b.label:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, 1)
    T.ClickableLabel(b, b.label)
    b.key = key
    local function paint()
        local c = BT.TEXT_COLORS[key]
        b.fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    b:SetScript("OnClick", function()
        local before = BT.db.colors[key]
        PickColor(BT.TEXT_COLORS[key], function(r, g, bl)
            BT:SetColor(key, r, g, bl)
            paint()
        end, function()
            if before then BT:SetColor(key, before[1], before[2], before[3]) else BT:SetColor(key) end
            paint()
        end)
    end)
    T.Tooltip(b, text, L["Click to pick a color."])
    AddRefresher(paint)
    return b
end

function BT:RefreshConfig()
    if not self.config then return end
    for _, fn in ipairs(refreshers) do fn() end
end

---------------------------------------------------------------------------
-- "Are you sure?": a small window in the same look, over the options
---------------------------------------------------------------------------
function BT:Confirm(text, yesLabel, onYes)
    local f = self.confirmWindow
    if not f then
        f = CreateFrame("Frame", "BattleTextForeverConfirm", UIParent)
        f:SetSize(380, 130)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "BattleTextForeverConfirm")   -- Escape is Cancel
        T.Fill(f, C.win)
        T.Border(f, C.edge)
        f.text = Text(f, "", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetWidth(348)
        f.text:SetWordWrap(true)
        f.text:SetJustifyH("LEFT")
        f.no = FlatButton(f, L["Cancel"], 100)
        f.no:SetPoint("BOTTOMRIGHT", -16, 14)
        f.no:SetScript("OnClick", function() f:Hide() end)
        f.yes = FlatButton(f, "", 120)
        f.yes:SetPoint("RIGHT", f.no, "LEFT", -8, 0)
        self.confirmWindow = f
    end
    f.text:SetText(text)
    f.yes:SetText(yesLabel)
    FitButton(f.yes, 120)
    f.yes:SetScript("OnClick", function()
        f:Hide()
        onYes()
    end)
    f:Show()
    return f
end

-- "Reset all" (the button and /btf resetall) asks first
function BT:ConfirmResetAll()
    local what = self:OwnSettings() and L["this character's settings back to how they started"]
        or L["every setting back to how it started"]
    self:Confirm((L["Put %s? Colors, places and your Spells list too."]):format(what),
        L["Reset all"], function()
            BT:ResetAll()
            Print(L["every setting is back to how it started."])
        end)
end

---------------------------------------------------------------------------
-- The pages. refs collects the widgets the window keeps a name for.
---------------------------------------------------------------------------
local function BuildGeneral(p, refs)
    local card = Card(p, L["Basics"], 0, 0, PAGE_W, 176)
    Setting(card, L["Show BattleText"], 12, -30, "enabled",
        L["Turns all of BattleText's text on or off (also /btf on and /btf off)."])
    Setting(card, L["Move the text areas"], COL2, -30, "locked",
        L["Shows a box for each text area. Drag the boxes where you want them, then turn this off. "
        .. "Closing the options locks them again."])
    Setting(card, L["Hide the game's own numbers"], 12, -56, "hideBlizzard",
        L["Turns off the game's floating combat text so numbers aren't shown twice (and its \"+XP\" while Experience "
        .. "is on in Notifications: the game has no setting for that alone, so all of its pop-up text in the world "
        .. "goes with it). Turn it off to bring them back. "
        .. "During a fight, the change waits until the fight ends."])
    Setting(card, L["Minimap button"], COL2, -56, "minimap",
        L["The BattleText button on the minimap: left-click opens the options, right-click shows sample text."])
    Setting(card, L["Remind me to click Start"], 12, -82, "startReminder",
        L["If BattleText couldn't start by itself, a line in chat after your first fight says to click Start BattleText."])
    Setting(card, L["Login message"], 12, -108, "loginMessage",
        L["\"BattleText Forever loaded. Type /btf for options.\" in chat when you log in or /reload."])
    local own = T.LabeledSwitch(card, L["Settings for this character only"], COL2, -82)
    own:SetScript("OnClick", function(self)
        self:SetOn(not self:IsOn())
        BT:SetOwnSettings(self:IsOn())
    end)
    T.Tooltip(own, L["Settings for this character only"],
        L["On: this character has its own settings. The first time, they start as a copy of the shared ones. "
        .. "Off: it uses the settings every character shares, and keeps its own for when you turn this back on."])
    AddRefresher(function() own:SetOn(BT:OwnSettings()) end)
    refs.ownSwitch = own
    local sample = FlatButton(card, L["Show sample text"], 140)
    sample:SetPoint("TOPLEFT", 12, -140)
    sample:SetScript("OnClick", function() BT:Test() end)
    T.Tooltip(sample, nil, L["A few sample lines in every area, to see the look and where the areas are."])
    local reset = FlatButton(card, L["Reset positions"], 120)
    reset:SetPoint("LEFT", sample, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        BT:Confirm(L["Move all four text areas back to where they started?"], L["Reset positions"],
            function() BT:ResetPositions() end)
    end)
    local resetAll = FlatButton(card, L["Reset all"], 90)
    resetAll:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    resetAll:SetScript("OnClick", function() BT:ConfirmResetAll() end)
    T.Tooltip(resetAll, nil, L["Every setting back to how it started: options, colors, places and the Spells list "
        .. "(also /btf resetall). With \"Settings for this character only\" on, just this character's."])
    refs.sampleButton, refs.resetButton, refs.resetAllButton = sample, reset, resetAll

    local know = Card(p, L["Good to know"], 0, -186, PAGE_W, 124)
    local text = Text(know, L["Your hits are read from the unit you hit: your target, and the mobs attacking you or your "
        .. "pet. Turn on enemy nameplates for the ones you aren't targeting.\n\n"
        .. "The game doesn't say whose hit it was: alone, your pet's hits show as yours.\n\n"
        .. "BattleText turns on the game's combat lines when you log in. They name the ticks of your bleeds and "
        .. "leave other people's hits out. If a Start BattleText button shows, click it once."], "GameFontHighlightSmall", C.muted)
    text:SetPoint("TOPLEFT", 12, -34)
    text:SetWidth(PAGE_W - 24)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")

    -- Longer text (other languages) makes the card taller, and the next one moves down
    local knowH = math.max(124, 34 + TextHeight(text) + 10)
    know:SetHeight(knowH)
    local share = Card(p, L["Share settings"], 0, -(196 + knowH), PAGE_W, 90)
    local export = FlatButton(share, L["Export"], 90)
    export:SetPoint("TOPLEFT", 12, -28)
    export:SetScript("OnClick", function() BT:OpenShareWindow("export") end)
    local import = FlatButton(share, L["Import"], 90)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function() BT:OpenShareWindow("import") end)
    local shareText = L["Export: your settings as a line of text to copy. Import: paste someone else's to use them "
        .. "(your text areas stay where they are unless you choose)."]
    local note = CardNote(share, shareText, -58)
    local shareH = math.max(90, 58 + TextHeight(note) + 8)
    if 196 + knowH + shareH > T.WINDOW.BODY_H then
        -- No room left on the page: the note goes on the buttons' tooltips instead
        note:Hide()
        shareH = 64
        T.Tooltip(export, nil, shareText)
        T.Tooltip(import, nil, shareText)
    end
    share:SetHeight(shareH)
    refs.shareCard, refs.shareNote, refs.knowCard = share, note, know
    refs.exportButton, refs.importButton = export, import
end

local function BuildText(p, refs)
    local card = Card(p, L["Font and outline"], 0, 0, PAGE_W, 154)
    local fontKeys, outlineKeys, outlineNames = {}, {}, {}
    for _, name in ipairs(BT:FontNames()) do fontKeys[#fontKeys + 1] = name end
    for _, o in ipairs(BT.OUTLINES) do
        outlineKeys[#outlineKeys + 1] = o.flags
        outlineNames[o.flags] = o.name
    end
    local function outlineName(flags) return outlineNames[flags] or outlineNames.OUTLINE end
    local outlineTip = L["None, a thin or thick dark edge round the letters, or a drop shadow instead. "
        .. "Picking one shows a sample line."]

    T.RowLabel(card, L["Font"], 12, -30)
    refs.fontDropdown = Dropdown(card, DROP_X, -30, 220, fontKeys, function(k) k = BT:FontShown(k) return k == "Default" and L["Default"] or k end, "font",
        function(name) BT:SetFont(name) end, L["The letters of every line. Picking one shows a sample line in it. "
        .. "Fonts your other addons share (through LibSharedMedia, like many UI packs) are at the end of the list. "
        .. "On a Russian, Korean or Chinese game, only the fonts that have its letters are listed."])
    refs.fontDropdown.menuScroll = 20 * 12   -- twelve rows, then it scrolls
    T.RowLabel(card, L["Outline"], 12, -60)
    refs.outlineDropdown = Dropdown(card, DROP_X, -60, 220, outlineKeys, outlineName, "outline",
        function(flags) BT:SetOutline("outline", flags) end, L["Normal lines: %s"]:format(outlineTip))
    T.RowLabel(card, L["Crit font"], 12, -90)
    local critFontKeys = { "" }
    for _, k in ipairs(fontKeys) do critFontKeys[#critFontKeys + 1] = k end
    refs.critFontDropdown = Dropdown(card, DROP_X, -90, 220, critFontKeys, function(k)
            if k == "" then return L["Same as other lines"] end
            k = BT:FontShown(k)
            return k == "Default" and L["Default"] or k
        end, "critFont", function(name) BT:SetCritFont(name) end,
        L["A font of their own for crits, so they stand out from the rest. Picking one shows a crit in it."])
    refs.critFontDropdown.menuScroll = 20 * 12
    T.RowLabel(card, L["Crit outline"], 12, -120)
    refs.critOutlineDropdown = Dropdown(card, DROP_X, -120, 220, outlineKeys, outlineName, "critOutline",
        function(flags) BT:SetOutline("critOutline", flags) end, L["Crits: %s"]:format(outlineTip))

    local size = Card(p, L["Size"], 0, -164, PAGE_W, 190)
    Slider(size, L["Text size"], 12, -30, "fontSize",
        { tip = L["The size of normal lines. Each area can make its own bigger or smaller (Appearance, on its tab)."] })
    Slider(size, L["Crit size"], COL2, -30, "critScale", { suffix = "%", step = 10,
        tip = L["Crits, as a percent of the text size."] })
    Setting(size, L["Short numbers"], 12, -82, "shortNumbers",
        L["Big numbers in short: 12,345 shows as 12.3k, 1,234,567 as 1.2m. Below 10,000 they stay as they are."])
    Setting(size, L["Size by hit"], COL2, -82, "sizeByHit",
        L["Each area compares a number with its recent ones: a bigger hit or heal shows bigger (up to 1.5 times), "
        .. "a smaller one smaller (down to three quarters). A number the game hides keeps the usual size."])
    Setting(size, L["Icon zoom"], 12, -108, "iconZoom",
        L["Crops the thin border round spell and item icons, so the picture fills its square and looks bigger."])
    Slider(size, L["Smallest crit"], 12, -134, "minCrit", { step = 10, zero = L["Off"],
        tip = L["A crit for less than this shows as a normal line: normal size, no crit outline, it doesn't hold "
            .. "in place and it plays no crit sound, so only the big ones stand out. A number the game hides "
            .. "still shows as a crit. Off: every crit stands out."] })
end

local function BuildMotion(p)
    local card = Card(p, L["Motion"], 0, 0, PAGE_W, 196)
    Setting(card, L["Crits stay in place"], 12, -30, "sticky",
        L["Critical hits jump out and stay in place for a moment instead of moving with the rest, "
        .. "whatever the area's movement."])
    Setting(card, L["Add up rapid hits"], COL2, -30, "merge",
        L["Hits from the same spell that land together are shown as one line, like \"Swipe 150 (x3)\". When the game "
            .. "hides the amounts, the line shows the latest hit and how many landed, like \"Swipe 50 (3 hits)\"."])
    Slider(card, L["Time on screen"], 12, -64, "scrollTime", { suffix = L[" sec"], step = 0.5, fmt = "%.1f",
        tip = L["How long a line takes to cross its area. Notifications move a little faster, and Pop lines "
            .. "stay a little over half as long."] })
    Slider(card, L["Area height"], COL2, -64, "height", { suffix = L[" px"], step = 10,
        tip = L["How tall the Outgoing and Incoming areas are: how far their lines travel. The Healing area is "
            .. "60% of it and Notifications 45%."] })
    Slider(card, L["Ticks and area hits add up for"], 12, -116, "tickMerge", { suffix = L[" sec"], step = 0.5,
        fmt = "%.1f", zero = L["Off"], enabledIf = function() return BT.db.merge end,
        tip = L["Ticks of your bleeds and DoTs, and the hits of an area spell, keep adding up on one line for this "
            .. "long. Off: as quickly as other hits. Needs Add up rapid hits."] })
    Setting(card, L["Keep Pop numbers apart"], COL2, -120, "popApart",
        L["With Pop movement, a number that would land on top of one still showing moves to the nearest "
        .. "free spot instead, so every number stays readable."])
    CardNote(card, L["How each area's lines move (Scroll, Pop, Fountain or Horizontal), which way, and whether they "
        .. "curve, is under Appearance on that area's own tab."], -156)
end

local function BuildOutgoing(p)
    local card = Card(p, L["What you do"], 0, 0, PAGE_W, 228)
    local damage = function() return BT.db.outDamage end
    Setting(card, L["Damage"], 12, -30, "outDamage", L["Your hits on mobs: spells, abilities and swings."])
    Setting(card, L["Misses"], COL2, -30, "outMisses",
        L["Your attacks that miss, or are dodged, parried, fully blocked or resisted."])
    Setting(card, L["Auto attacks"], 12, -56, "outSwings",
        L["Your white swings, your ranged attacks (Auto Shot, Shoot, Throw) and their misses. Off: only your "
        .. "spells and abilities. Without the game's combat "
        .. "lines, a physical hit BattleText can't name counts as a swing."], Either("outDamage", "outMisses"))
    Setting(card, L["Pet"], COL2, -56, "outPet",
        L["Your pet's hits and heals, marked with its name, and a hunter's hawks (Summon Hawk), marked (Hawk). This only works when the game lets BattleText read its combat "
        .. "lines; when it doesn't, your pet's hits can't be told from yours and show with them."])
    Setting(card, L["Damage shields"], 12, -82, "outShields",
        L["What your damage shields do to whoever hits you: buffs like Thorns, Lightning Shield and Retribution Aura "
        .. "(named as soon as they hit), and gear that stings back. Off: hidden."], damage)
    Setting(card, L["Name seal hits"], COL2, -82, "outSeals",
        L["Paladins: the Holy hit of Seal of Righteousness, Seal of Command or Seal of Fury that lands with your swing shows the "
        .. "seal's name and icon. Off: it shows as a plain number."], damage)
    IconsAndNames(card, -108, "out", L["your hits and misses"], Either("outDamage", "outMisses"))
    Slider(card, L["Hide hits below"], 12, -142, "minDamage", { step = 5, zero = L["Off"], enabledIf = damage,
        tip = L["Your hits (and your pet's) for less than this aren't shown. A hit whose number the game hides "
            .. "always shows, unless it's gear that always does the same (Cursed Murloc Eye's 2 Shadow)."] })
    Setting(card, L["DoTs and area spells"], COL2, -142, "outTicks",
        L["The ticks of your damage-over-time spells (Corruption, Rend, Moonfire...) and of spells that keep hitting "
        .. "everything in an area (Consecration, Blizzard, Rain of Fire, totems...). Off: hidden. A spell's own "
        .. "first hit still shows. To hide one spell only, use the Spells tab."], damage)
    LineOrder(card, -192, "outFormat", L["your hits and misses"], Either("outDamage", "outMisses"))
    AreaLook(p, -238, "out", true, function() return BT:AreaUsed("outgoing") end, L["Nothing shows here (Layout tab)"])
end

-- Every sound list shares one list of keys (sounds other addons share are added to it later)
local soundKeys
local function SoundKeys()
    if not soundKeys then
        soundKeys = {}
        for _, s in ipairs(BT.SOUNDS) do soundKeys[#soundKeys + 1] = s.key end
    end
    return soundKeys
end
local function SoundName(k) return BT:SoundName(k) end
local PICK_TIP = L["Picking a sound plays it. If this game doesn't have it, chat says so. Sounds your other addons share "
    .. "(through LibSharedMedia) are at the end of the list."]

local function BuildIncoming(p, refs)
    local card = Card(p, L["What happens to you"], 0, 0, PAGE_W, 142)
    Setting(card, L["Damage"], 12, -30, "inDamage", L["The damage you take."])
    Setting(card, L["Avoids"], COL2, -30, "inMisses", L["Attacks you dodge, parry, block or resist, and ones that miss you."])
    Setting(card, L["Power gains"], 12, -56, "inPower", L["Mana, rage and energy you gain."])
    Setting(card, L["Show blocked"], COL2, -56, "inBlocked",
        L["A grey \"(blocked)\" after a hit you partly blocked with your shield. The game doesn't say how much "
        .. "was blocked, so only when it lets BattleText read its combat lines does the amount show "
        .. "(\"(150 blocked)\")."], function() return BT.db.inDamage end)
    IconsAndNames(card, -82, "in", L["what hits you or what you avoid (only when the game says which spell)"],
        Either("inDamage", "inMisses"))
    Setting(card, L["Damage schools"], 12, -108, "inSchools",
        L["A magic hit on you in its school's color, with the school's name after the number (\"-120 Shadow\" in "
        .. "purple), so you know when to use a Shadow Ward or a resistance potion. Physical hits stay in the "
        .. "damage color."], function() return BT.db.inDamage end)
    local warn = Card(p, L["Warnings"], 0, -152, PAGE_W, 106)
    local lowHealth = Setting(warn, L["Low health"], 12, -32, "warnHealth",
        L["\"Low health!\" and a sound when your health drops to 35%. It warns again once you've healed back up. "
        .. "The game hides your health from addons, so this goes by its own warning, the red screen edges: it can't "
        .. "warn if you've turned those off in the game's options, or while the map is open in a fight. "
        .. "Pick the sound in the list beside it."])
    local dx, dw = AfterLabel(lowHealth, 12, 130, 256, 80)
    refs.lowHealthDropdown = Dropdown(warn, dx, -30, dw, SoundKeys(), SoundName, "lowHealthSound",
        function(k) BT:SetAlertSound("lowHealth", k) end, PICK_TIP, function() return BT.db.warnHealth end)
    local lowMana = Setting(warn, L["Low mana"], COL2, -32, "warnMana",
        L["\"Low mana!\" and a sound when your mana drops to the line below. It warns again once your mana is 10% "
        .. "above it. Pick the sound in the list beside it. If the game hides your mana from addons (it does for "
        .. "some players), BattleText can't tell when it drops, so instead a steady \"Low mana\" shows above the "
        .. "notifications while you're under the line, with no sound."])
    dx, dw = AfterLabel(lowMana, COL2, COL2 + 118, COL2 + 244, 80)
    refs.lowManaDropdown = Dropdown(warn, dx, -30, dw, SoundKeys(), SoundName, "lowManaSound",
        function(k) BT:SetAlertSound("lowMana", k) end, PICK_TIP, function() return BT.db.warnMana end)
    refs.lowHealthDropdown.menuScroll, refs.lowManaDropdown.menuScroll = 20 * 12, 20 * 12
    T.Note(warn, L["Low health goes by the game's red screen edges, at 35% health."], 12, -62, COL2 - 36)
    Slider(warn, L["Low mana at"], COL2, -66, "lowManaAt", { suffix = "%", step = 5,
        enabledIf = function() return BT.db.warnMana end,
        tip = L["How low your mana goes before \"Low mana!\"."] })
    AreaLook(p, -268, "in", true, function() return BT:AreaUsed("incoming") end, L["Nothing shows here (Layout tab)"])
end

local function BuildHealing(p)
    local card = Card(p, L["Heals"], 0, 0, PAGE_W, 228)
    local anyHeals = Either("inHeals", "outHeals")
    Setting(card, L["Heals you get"], 12, -30, "inHeals", L["Heals on you, yours and other people's."])
    Setting(card, L["Heals you do"], COL2, -30, "outHeals", L["Your heals on others (and your pet's)."])
    Setting(card, L["Show overhealing"], 12, -56, "healOver",
        L["The grey \"(40 over)\" after a heal. Only when the game lets BattleText read its combat lines."], anyHeals)
    T.Note(card, L["Which area heals show in: Layout tab."], COL2, -58, PAGE_W - COL2 - 12)
    IconsAndNames(card, -82, "heal", "heals", anyHeals)
    Setting(card, L["Show who you healed"], 12, -108, "healWho",
        L["The name of the player you healed, after the number. Only when the game lets BattleText read it."],
        function() return BT.db.outHeals end)
    Setting(card, L["Unnamed heals on you"], COL2, -108, "inOtherHeals",
        L["Heals on you the game doesn't name: other players' heals, food, and small passive heals like Thrill of "
        .. "Adventure. The game often hides their number, so \"Hide heals below\" can't catch them: turn this off "
        .. "to hide them. Your own heals keep their name and still show."],
        function() return BT.db.inHeals end)
    Slider(card, L["Hide heals below"], 12, -142, "minHeal", { step = 5, zero = L["Off"], enabledIf = anyHeals,
        tip = L["Heals for less than this aren't shown. A heal whose number the game hides always shows "
            .. "(turn off \"Unnamed heals on you\" for other people's)."] })
    LineOrder(card, -192, "healFormat", L["your heals"], function() return BT.db.outHeals end)
    AreaLook(p, -238, "heal", false, function() return BT:AreaUsed("heal") end, L["Nothing shows here (Layout tab)"])
end

local function BuildNotifications(p, refs)
    local card = Card(p, L["Show"], 0, 0, PAGE_W, 284)
    Setting(card, L["Combat"], 12, -30, "nCombat", L["+Combat and -Combat as you enter and leave a fight."])
    Setting(card, L["Killing blows"], COL2, -30, "nKill",
        L["\"Killing blow!\" when your hit kills. Only when the game lets BattleText read its combat lines "
        .. "(it often hides them)."])
    Setting(card, L["Experience"], 12, -56, "nXP", L["The experience you gain, like \"+103 XP\". With \"Hide the game's own numbers\" on, the game's "
        .. "own \"+XP\" goes, and with it all of the game's pop-up text in the world."])
    Setting(card, L["Reputation"], COL2, -56, "nRep", L["Reputation you gain or lose with a faction."])
    Setting(card, L["Honor"], 12, -82, "nHonor", L["Honor you gain."])
    Setting(card, L["Loot"], COL2, -82, "nLoot", L["Items you loot, with how many."])
    Setting(card, L["Money"], 12, -108, "nMoney", L["Money you loot or get."])
    Setting(card, L["Skill ups"], COL2, -108, "nSkill", L["A skill going up, like First Aid or a weapon skill."])
    Setting(card, L["Seals"], 12, -134, "nSeals",
        L["Paladins: a line when a seal goes on or comes off. In a fight the game hides your buffs, so a seal "
        .. "coming off is worked out: a new seal replaces it, or its 30 seconds run out. Judgement leaves it on."])
    Setting(card, L["Buffs"], COL2, -134, "nBuffs",
        L["A line when a buff goes on or comes off. The game hides your buffs during a fight: there, a buff you put on "
        .. "yourself (Slice and Dice, Evasion...) shows as you cast it, and the rest of what changed shows when the fight "
        .. "ends. Not shown: food and drink, and buffs with no time limit (mounts, auras, stances)."])
    Setting(card, L["Ability alerts"], 12, -160, "nAlerts",
        L["A line when an ability you can use only just then opens up: \"Overpower!\" when your target dodges you, "
        .. "\"Revenge!\" when you dodge, parry or block (warriors), \"Riposte!\" or \"Counterattack!\" when you "
        .. "parry (rogues and hunters with the talent), \"Execute!\" and \"Hammer of Wrath!\" when your target is "
        .. "low enough, and procs and spells the game lights up on your action bars (like Clearcasting). "
        .. "Revenge only in Defensive Stance, and none while the ability is on cooldown. To turn one off, "
        .. "add it on the Spells tab and hide it."])
    Setting(card, L["Combo points"], COL2, -160, "nCombo",
        L["Rogues and cat druids: \"2 CP\" as your combo points go up, and \"5 CP: Finish it!\" when you have "
        .. "them all."])
    Setting(card, L["Dispels"], 12, -186, "nDispels",
        L["A line when you take something off: \"Dispelled Deadly Poison\" from a friend or yourself, \"Purged ...\" "
        .. "from an enemy, \"Stole ...\" with Spellsteal. Needs one box in the Combat Log: right-click its tab, "
        .. "Settings, Message Types, Auras, tick Dispels. Without it, only the spell you cast shows (\"Cleanse\")."])

    -- (the extras share the card, so the page still fits with Dispels)
    local extras = card
    Setting(extras, L["Fight summary"], COL2, -186, "nSummary",
        L["When a fight ends: your damage, damage per second and healing, like \"4,820 damage (127 DPS) in 38s\". "
        .. "Only counts numbers the game lets BattleText read. Type /btf last for that fight spell by spell."])
    Setting(extras, L["Cooldowns ready"], 12, -212, "nCooldowns",
        L["A line when a spell of yours comes off its cooldown, like \"Kick ready\". Only cooldowns of 8 seconds "
        .. "or more, up to 10 minutes. Hide one you don't want on the Spells tab."])
    Setting(extras, L["Interrupts"], COL2, -212, "nInterrupts",
        L["\"Interrupted Frostbolt\" when you or your pet stop an enemy's cast. If the game hides who stopped it, "
        .. "BattleText goes by your interrupt (Kick, Pummel, Counterspell...) landing just as your target's cast stopped."])
    Setting(extras, L["Icons"], 12, -264, "nIcons",
        L["Shows the icon beside loot, skill ups, seals, buffs, ability alerts, cooldowns, interrupts and dispels."],
        Either("nLoot", "nSkill", "nSeals", "nBuffs", "nAlerts", "nDispels", "nCooldowns", "nInterrupts"))
    local soundKeys, soundName, pickTip = SoundKeys(), SoundName, PICK_TIP
    local critSound = Setting(extras, L["Crit sound"], 12, -238, "soundCrit", L["A sound when you crit. Pick it in the list beside it."])
    local dx, dw = AfterLabel(critSound, 12, 130, 256, 80)
    refs.critSoundDropdown = Dropdown(extras, dx, -236, dw, soundKeys, soundName, "critSound",
        function(k) BT:SetAlertSound("crit", k) end, pickTip)
    local killSound = Setting(extras, L["Kill sound"], COL2, -238, "soundKill",
        L["A sound on your killing blows (only when the game lets BattleText read its combat lines). "
        .. "Pick it in the list beside it."])
    dx, dw = AfterLabel(killSound, COL2, COL2 + 118, COL2 + 244, 80)
    refs.killSoundDropdown = Dropdown(extras, dx, -236, dw, soundKeys, soundName, "killSound",
        function(k) BT:SetAlertSound("kill", k) end, pickTip)
    refs.critSoundDropdown.menuScroll, refs.killSoundDropdown.menuScroll = 20 * 12, 20 * 12
    AreaLook(p, -294, "n", false, function() return BT:AreaUsed("notify") end, L["Nothing shows here (Layout tab)"])
end

-- Which area each kind of text shows in. Areas are named for where they start on screen.
local function BuildLayout(p, refs)
    local ROW = 28
    local card = Card(p, L["Where each kind of text shows"], 0, 0, PAGE_W, 40 + #BT.ROUTES * ROW + 52)
    local areaKeys = { "outgoing", "incoming", "heal", "notify" }
    local plateKeys = { "outgoing", "incoming", "heal", "notify", "plates" }
    local areaNames = { outgoing = L["Outgoing (right)"], incoming = L["Incoming (left)"], heal = L["Healing (bottom)"],
        notify = L["Notifications (top)"], plates = L["Enemy nameplates"] }
    refs.routeDropdowns = {}
    for i, r in ipairs(BT.ROUTES) do
        local y = -30 - (i - 1) * ROW
        T.RowLabel(card, r.name, 12, y)
        local key = "route" .. r.key
        local tip = L["%s: the text area it shows in. Each area keeps its own look (Appearance, on its tab)."]:format(r.name)
        if r.plates then
            tip = tip .. " " .. L["Enemy nameplates: over the nameplate of the mob it landed on, or in Outgoing when "
                .. "that mob has none on screen. They take Outgoing's size and opacity."]
        end
        refs.routeDropdowns[r.key] = Dropdown(card, 200, y, 220, r.plates and plateKeys or areaKeys,
            function(k) return areaNames[k] or k end, key, function(k) BT.db[key] = k end, tip)
    end
    CardNote(card, L["Areas are named for where they start; move them anywhere with \"Move the text areas\" "
        .. "(General tab). Each area keeps its own size, opacity, movement and alignment."], -40 - #BT.ROUTES * ROW)

    -- Where lines over nameplates start, for nameplates of other addons that sit higher or wider
    local onPlates = function() return BT:Area("OutDamage") == "plates" or BT:Area("OutMisses") == "plates" end
    local plates = Card(p, L["Enemy nameplates"], 0, -(50 + #BT.ROUTES * ROW + 52), PAGE_W, 74)
    Slider(plates, L["Left and right"], 12, -30, "plateX", { suffix = L[" px"], enabledIf = onPlates,
        tip = L["Moves the lines over nameplates sideways. Less than 0: to the left."] })
    Slider(plates, L["Up and down"], COL2, -30, "plateY", { suffix = L[" px"], enabledIf = onPlates,
        tip = L["How far above the top of the nameplate the lines start. Raise it if your nameplates "
            .. "(from another addon) show more above the bar."] })
end

local function BuildColors(p)
    local rows = math.ceil(#BT.COLOR_CHOICES / 2)
    local card = Card(p, L["Colors"], 0, 0, PAGE_W, 40 + rows * 26 + 66)
    for i, choice in ipairs(BT.COLOR_CHOICES) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        Swatch(card, choice[2], col == 0 and 12 or COL2, -30 - row * 26, choice[1])
    end
    local reset = FlatButton(card, L["Reset colors"], 120)
    reset:SetPoint("TOPLEFT", 12, -36 - rows * 26)
    reset:SetScript("OnClick", function()
        BT:Confirm(L["Put every text color back to how it started?"], L["Reset colors"], function()
            wipe(BT.db.colors)
            BT:ApplyColors()
            BT:RefreshConfig()
        end)
    end)
    CardNote(card, L["Spells that do Holy, Fire, Nature, Frost, Shadow or Arcane damage keep their school's color."],
        -72 - rows * 26)
end

-- Spells you hide or recolor: type a name and Add; each one on the list has Hide,
-- a color square (right-click: its usual color again) and Remove
local RULE_ROW = 28
local function BuildSpells(p, refs)
    local card = Card(p, L["Add a spell"], 0, 0, PAGE_W, 92)
    T.RowLabel(card, L["Spell"], 12, -32)
    local box = T.EditBox(card, 220)
    box:SetPoint("TOPLEFT", DROP_X, -30)
    box:SetMaxLetters(60)
    local add = FlatButton(card, L["Add"], 80)
    add:SetPoint("LEFT", box, "RIGHT", 8, 0)
    T.Tooltip(add, nil, L["Puts the spell on the list below. Then hide it, or give it a color of its own."])
    CardNote(card, L["Type the name as it shows on your hits and heals, like Ferocious Bite. It works on what you do, "
        .. "and your pet."], -62)
    refs.spellBox, refs.spellAdd = box, add

    local listH = T.WINDOW.BODY_H - 102
    local list = Card(p, L["Your spells"], 0, -102, PAGE_W, listH)
    local holder = CreateFrame("Frame", nil, list)
    holder:SetPoint("TOPLEFT", 12, -30)
    holder:SetPoint("BOTTOMRIGHT", -6, 10)
    local viewH = listH - 40
    local scroll = T.ScrollArea(holder, viewH)
    local empty = Text(list, L["Nothing on the list yet."], "GameFontHighlightSmall", C.muted)
    empty:SetPoint("TOPLEFT", 12, -34)
    local rows = {}
    refs.spellRows = rows

    local render
    local function Row(i)
        local row = CreateFrame("Frame", nil, scroll.child)
        row:SetSize(PAGE_W - 40, RULE_ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_ROW)
        row.name = Text(row, "", "GameFontHighlight")
        row.name:SetPoint("LEFT", 2, 0)
        row.name:SetWidth(170)
        row.name:SetJustifyH("LEFT")
        row.hide = T.LabeledSwitch(row, L["Hide"], 180, -4)
        row.hide:SetScript("OnClick", function(self)
            BT:SetSpellRule(row.rule, "hide", not self:IsOn())
            self:SetOn(row.rule.hide)
            row.swatch:SetAlpha(row.rule.hide and 0.4 or 1)
        end)
        T.Tooltip(row.hide, L["Hide"], L["Its hits, heals and misses aren't shown. They still count in the fight summary."])
        local sw = CreateFrame("Button", nil, row)
        sw:SetSize(30, 16)
        sw:SetPoint("LEFT", (AfterLabel(row.hide, 180, 270, 330, 0)), 0)
        sw.fill = T.Fill(sw, { 1, 1, 1, 1 }, "ARTWORK")
        T.Border(sw, C.edge)
        sw.label = Text(row, L["Color"], "GameFontHighlight")
        sw.label:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        T.ClickableLabel(sw, sw.label)
        sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        sw:SetScript("OnClick", function(_, button)
            local rule = row.rule
            if button == "RightButton" then
                BT:SetSpellRule(rule, "color", nil)
                render()
                return
            end
            local before = rule.color
            PickColor(rule.color or BT.TEXT_COLORS.spell, function(r, g, bl)
                BT:SetSpellRule(rule, "color", { r, g, bl })
                render()
            end, function()
                BT:SetSpellRule(rule, "color", before)
                render()
            end)
        end)
        T.Tooltip(sw, L["Color"], L["Click to pick this spell's own color. Right-click: its usual color again."])
        row.swatch = sw
        row.remove = FlatButton(row, L["Remove"], 70)
        row.remove:SetPoint("RIGHT", -4, 0)
        -- (the label stops short of Remove: "Usual color" ran under it, more so in other languages)
        sw.label:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
        sw.label:SetJustifyH("LEFT")
        sw.label:SetWordWrap(false)
        row.remove:SetScript("OnClick", function()
            for j, r in ipairs(BT.db.spellRules) do
                if r == row.rule then BT:RemoveSpellRule(j) break end
            end
            render()
        end)
        rows[i] = row
        return row
    end

    function render()
        local rules = BT.db.spellRules
        for i, rule in ipairs(rules) do
            local row = rows[i] or Row(i)
            row.rule = rule
            row.name:SetText(rule.name)
            row.hide:SetOn(rule.hide == true)
            local c = rule.color or BT.TEXT_COLORS.spell
            row.swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
            row.swatch:SetAlpha(rule.hide and 0.4 or 1)
            row.swatch.label:SetText(rule.color and L["Color"] or L["Usual color"])
            row:Show()
        end
        for i = #rules + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#rules == 0)
        scroll:SetContent(PAGE_W - 40, math.max(1, #rules) * RULE_ROW, true)
    end
    local function addIt()
        local rule, why = BT:AddSpellRule(box:GetText())
        if not rule then
            Print(why .. ".")
            return
        end
        box:SetText("")
        box:ClearFocus()
        render()
    end
    add:SetScript("OnClick", addIt)
    box:SetScript("OnEnterPressed", addIt)
    AddRefresher(render)
end

-- Tab icons are the game's own icon files
local TABS = {
    { key = "general",  label = L["General"],       icon = "Interface\\Icons\\INV_Misc_Gear_01",                build = BuildGeneral },
    { key = "text",     label = L["Text"],          icon = "Interface\\Icons\\INV_Misc_Note_01",                build = BuildText },
    { key = "scroll",   label = L["Motion"],        icon = "Interface\\Icons\\INV_Misc_Spyglass_03",            build = BuildMotion },
    { key = "outgoing", label = L["Outgoing"],      icon = "Interface\\Icons\\INV_Sword_04",                    build = BuildOutgoing },
    { key = "incoming", label = L["Incoming"],      icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", build = BuildIncoming },
    { key = "healing",  label = L["Healing"],       icon = "Interface\\Icons\\Spell_Holy_Heal",                 build = BuildHealing },
    { key = "notify",   label = L["Notifications"], icon = "Interface\\Icons\\INV_Misc_Bag_08",                 build = BuildNotifications },
    { key = "layout",   label = L["Layout"],        icon = "Interface\\Icons\\INV_Misc_Map_01",                 build = BuildLayout },
    { key = "spells",   label = L["Spells"],        icon = "Interface\\Icons\\INV_Misc_Book_09",                build = BuildSpells },
    { key = "colors",   label = L["Colors"],        icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",         build = BuildColors },
}
BT.CONFIG_TABS = TABS

function BT:BuildConfig()
    local refs = {}
    local tabs = {}
    for _, t in ipairs(TABS) do
        tabs[#tabs + 1] = { key = t.key, label = t.label, icon = t.icon, build = function(body) t.build(body, refs) end }
    end
    local win = T.Window({
        name = "BattleTextForeverOptions",
        tabs = tabs,
        hint = L["/btf to open  -  /btf test for sample text"],
        version = function()
            local get = C_AddOns and C_AddOns.GetAddOnMetadata
            local v = get and get(ADDON, "Version")
            if type(v) == "string" and not v:find("@", 1, true) then return (v:gsub("^v", "")) end
        end,
        -- Closing the window is the end of moving things about: the text areas lock
        -- again (and "Move the text areas" is off the next time it opens)
        onHide = function()
            if not BT.db.locked then BT:SetLocked(true) end
        end,
    })
    for k, v in pairs(refs) do win[k] = v end
    self.config = win
end

function BT:OpenConfig()
    if not self.config then self:BuildConfig() end
    if self.config:IsShown() then
        self.config:Hide()
    else
        self:RefreshConfig()
        self.config:Show()
    end
end

---------------------------------------------------------------------------
-- A window with a box of text: /btf copy (the lines recorded by /btf debug,
-- since chat can't be copied) and Share settings
---------------------------------------------------------------------------
local COPY_W, COPY_H, COPY_HEADER = 640, 380, 40

-- A window in the shared look with a header bar (logo, f.title, X); Escape closes it
local function Popup(name, w, h)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:Hide()
    table.insert(UISpecialFrames, name)
    T.Fill(f, C.win)
    T.Border(f, C.edge)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(COPY_HEADER)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    T.HeaderGradient(hbg)
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture(T.LOGO)
    f.title = Text(header, "", "GameFontNormal", C.title)
    f.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    local close = FlatButton(header, "X", 24, 24)
    close:SetPoint("RIGHT", -8, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.header, f.close = header, close
    return f
end

local function TextWindow()
    local f = Popup("BattleTextForeverCopy", COPY_W, COPY_H)
    local header, close = f.header, f.close
    -- Share settings' Import: takes what's in the box, and whether to take their area positions too
    f.action = FlatButton(header, L["Import"], 80, 24)
    f.action:SetPoint("RIGHT", close, "LEFT", -8, 0)
    f.action:Hide()
    f.positions = T.LabeledSwitch(header, L["Positions too"], 0, 0)
    f.positions:ClearAllPoints()
    f.positions:SetPoint("RIGHT", f.action, "LEFT", -112, 0)
    f.positions:SetScript("OnClick", function(self) self:SetOn(not self:IsOn()) end)
    T.Tooltip(f.positions, L["Positions too"],
        L["Also move your text areas to where they were on their screen. Off: yours stay where they are."])
    f.positions:Hide()
    f.positions.label:Hide()

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 12, -(COPY_HEADER + 10))
    box:SetPoint("BOTTOMRIGHT", -12, 12)
    T.Fill(box, C.field)
    T.Border(box, C.fieldEdge)
    local scroll = T.ScrollArea(box, COPY_H - COPY_HEADER - 22)
    local edit = CreateFrame("EditBox", nil, scroll.child)
    edit:SetPoint("TOPLEFT", 6, -6)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(0)   -- (no limit: a pasted settings line is a few thousand letters)
    edit:SetWidth(COPY_W - 60)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.edit, f.scroll = edit, scroll
    return f
end

-- Shows the window with this title and text (rows: about how many lines it takes)
function BT:ShowTextWindow(title, text, rows, action)
    local f = self.copyWindow or TextWindow()
    self.copyWindow = f
    f.title:SetText(title)
    f.edit:SetText(text)
    local height = math.max(rows, 4) * 28 + 12
    f.edit:SetHeight(height)
    f.scroll:SetContent(COPY_W - 48, height)
    f.action:SetShown(action ~= nil)
    f.action:SetScript("OnClick", action)
    f.positions:SetShown(action ~= nil)
    f.positions.label:SetShown(action ~= nil)
    f.positions:SetOn(false)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return f
end

function BT:OpenCopyWindow()
    local text = L["Nothing recorded yet. Type /btf debug, fight for a moment, then /btf copy."]
    local count = 1
    if self.recorded and #self.recorded > 0 then
        -- A hidden value can't be joined into the text (issue #23): it's left as a note
        local lines = {}
        for i, line in ipairs(self.recorded) do
            lines[i] = self.Str(line) or L["(a line with a hidden value)"]
        end
        -- "|" doubled, so the links show as text instead of turning into links
        text = (table.concat(lines, "\n"):gsub("|", "||"))
        count = #self.recorded
    end
    -- Long lines wrap, so leave room for about two rows each
    self:ShowTextWindow(L["Combat lines: press Ctrl+C to copy, then paste into your report"], text, count)
end

-- /btf report: from what /btf debug recorded, only the lines that look wrong, each kind with how
-- many times it happened and one example (the lines around it). One report covers a whole play
-- session, so many problems can be fixed in one go instead of one log each. In English, like
-- the rest of the debug output.
local REPORT_AROUND = 1.5   -- seconds of lines kept around an example
local REPORT_KINDS = {
    { key = "castPlain", title = "Casts of yours whose hit was shown with no name" },
    { key = "noSource", title = "Heals on you with no source" },
    { key = "waited", title = "Hits that waited for a seal, shield or gear, and nothing came" },
    { key = "noLine", title = "Hits turned away for want of a line of yours" },
}
local function ReportLine(line)
    local t = tonumber(line:sub(1, 7))
    return t, line:sub(10)
end
-- Lines from i outwards, while within REPORT_AROUND of line i's time (times wrap at 1000)
local function Around(list, i)
    local t0 = ReportLine(list[i]) or 0
    local function near(j)
        local t = ReportLine(list[j])
        if not t then return false end
        local d = math.abs(t - t0)
        return math.min(d, 1000 - d) <= REPORT_AROUND
    end
    local a, b = i, i
    while a > 1 and near(a - 1) and i - a < 20 do a = a - 1 end
    while b < #list and near(b + 1) and b - i < 20 do b = b + 1 end
    local out = {}
    for j = a, b do out[#out + 1] = list[j] end
    return out
end
function BT:BuildReport(list)
    list = list or self.recorded or {}
    local found = {}
    local function add(key, i, what)
        local f = found[key]
        if not f then
            f = { count = 0, what = {}, order = {} }
            found[key] = f
        end
        f.count = f.count + 1
        if not f.example then f.example = i end
        if what then
            if not f.what[what] then f.what[what] = 0 f.order[#f.order + 1] = what end
            f.what[what] = f.what[what] + 1
        end
    end
    for i, line in ipairs(list) do
        local t, text = ReportLine(line)
        if t and text then
            if text:find("player heal: no cast of yours with it", 1, true) then
                add("noSource", i)
            elseif text:find(": nothing came for it: shown$") then
                add("waited", i)
            elseif text:find(": no line of yours with it$") or text:find(": no heal of yours with it$") then
                add("noLine", i)
            else
                local name = text:match("^CAST %d+ (.+)$")
                if name then
                    -- A hit at the same moment shown plain, and nothing named after the cast nearby
                    local plain, named = false, false
                    for _, other in ipairs(Around(list, i)) do
                        local ot, otext = ReportLine(other)
                        if ot and otext:find("^  %S+ .-: cast of " .. name:gsub("%p", "%%%0") .. "$") then named = true end
                        if ot and math.abs(ot - t) < 0.02 and otext:find("^  %S+ .-: shown$") then plain = true end
                    end
                    if plain and not named then add("castPlain", i, name) end
                end
            end
        end
    end
    local first, lastT = list[1] and ReportLine(list[1]), list[#list] and ReportLine(list[#list])
    local out = {}
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local okV, v = pcall(function() return get and get(ADDON, "Version") end)
    out[#out + 1] = ("BattleText report%s: %d lines recorded"):format(
        (okV and type(v) == "string" and not v:find("@", 1, true)) and (" " .. v) or "", #list)
    if first and lastT then
        local span = lastT - first
        if span < 0 then span = span + 1000 end
        out[#out + 1] = ("(over %d seconds or more)"):format(math.floor(span + 0.5))
    end
    local any = false
    for _, kind in ipairs(REPORT_KINDS) do
        local f = found[kind.key]
        if f then
            any = true
            out[#out + 1] = ""
            out[#out + 1] = ("== %s: %d =="):format(kind.title, f.count)
            if #f.order > 0 then
                local names = {}
                for _, what in ipairs(f.order) do names[#names + 1] = ("%s x%d"):format(what, f.what[what]) end
                out[#out + 1] = table.concat(names, ", ")
            end
            out[#out + 1] = "Example:"
            for _, line in ipairs(Around(list, f.example)) do out[#out + 1] = line end
        end
    end
    if not any then
        out[#out + 1] = ""
        out[#out + 1] = "Nothing that looks wrong."
    end
    return out
end

function BT:OpenReport()
    if not (self.recorded and #self.recorded > 0) then
        self:OpenCopyWindow()   -- (says how to record first)
        return
    end
    local lines = self:BuildReport()
    for i, line in ipairs(lines) do lines[i] = self.Str(line) or "(a line with a hidden value)" end
    self:ShowTextWindow(L["Report: press Ctrl+C to copy, then paste into your report"],
        (table.concat(lines, "\n"):gsub("|", "||")), #lines)
end

-- mode: "export" (your settings, to copy) or "import" (paste, then click Import)
function BT:OpenShareWindow(mode)
    if mode == "export" then
        self:ShowTextWindow(L["Your settings: press Ctrl+C to copy, then share them"], self:ExportSettings(), 8)
        return
    end
    local f
    f = self:ShowTextWindow(L["Paste settings with Ctrl+V, then click Import"], "", 8, function()
        local t, count = BT:ReadSettings(f.edit:GetText())
        if not t then
            BT.Print(L["couldn't import: %s."]:format(count))
            return
        end
        local whose = BT:OwnSettings() and L["this character's own settings"] or L["the settings every character shares"]
        local positions = f.positions:IsOn()
        BT:Confirm((L["Replace %s with these (%d settings)?%s"]):format(whose, count,
            positions and L[" Your text areas move to their places too."] or ""), L["Import"], function()
            BT:TakeSettings(t, positions)
            BT.Print(L["settings imported."])
            f:Hide()
        end)
    end)
end

---------------------------------------------------------------------------
-- /btf last: the last fight, spell by spell
---------------------------------------------------------------------------
local LAST_W, LAST_H, LAST_ROW = 620, 420, 20
-- The columns after the spell's name: heading, the row's field, where its right edge is
local LAST_COLUMNS = {
    { L["Hits"], "hits", 340 }, { L["Crits"], "crits", 395 }, { L["Total"], "total", 470 },
    { L["Share"], "share", 520 }, { L["Biggest"], "biggest", 578 },
}

function BT:OpenLastFight()
    local f = self.lastWindow
    if not f then
        f = Popup("BattleTextForeverLast", LAST_W, LAST_H)
        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("TOPLEFT", 12, -(COPY_HEADER + 10))
        box:SetPoint("BOTTOMRIGHT", -12, 12)
        T.Fill(box, C.field)
        T.Border(box, C.fieldEdge)
        f.scroll = T.ScrollArea(box, LAST_H - COPY_HEADER - 22)
        f.rows = {}
        self.lastWindow = f
    end
    local child = f.scroll.child
    local function cell(row, i, justify)
        row.cells[i] = row.cells[i] or Text(child, "", "GameFontHighlightSmall")
        local fs = row.cells[i]
        fs:SetJustifyH(justify)
        return fs
    end
    local list = {}
    local rows, fight = self:FightBreakdown()
    if fight then
        f.title:SetText(L["Last fight: %s"]:format(self:FightLine(fight)))
        local kind
        for _, s in ipairs(rows) do
            if s.heal ~= kind then
                kind = s.heal
                list[#list + 1] = { heading = kind and L["Healing"] or L["Damage"] }
            end
            list[#list + 1] = s
        end
        if #rows == 0 then list[1] = { note = L["No numbers the game let BattleText read."] } end
    else
        f.title:SetText(L["Last fight"])
        list[1] = { note = L["No fight yet. Fight something, then type /btf last again."] }
    end
    for i, item in ipairs(list) do
        local row = f.rows[i] or { cells = {} }
        f.rows[i] = row
        local y = -6 - (i - 1) * LAST_ROW
        local first = cell(row, 1, "LEFT")
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", 6, y)
        first:SetWidth(260)
        first:Show()
        if item.heading then
            first:SetText(item.heading)
            first:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        else
            first:SetText(item.note or (item.icon .. item.name))
            local c = item.note and C.muted or { 1, 1, 1 }
            first:SetTextColor(c[1], c[2], c[3])
        end
        for j, col in ipairs(LAST_COLUMNS) do
            local fs = cell(row, j + 1, "RIGHT")
            fs:ClearAllPoints()
            fs:SetPoint("TOPRIGHT", child, "TOPLEFT", col[3], y)
            if item.heading then
                fs:SetText(col[1])
                fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            elseif item.note then
                fs:SetText("")
            else
                local v = item[col[2]]
                fs:SetText(col[2] == "share" and (v .. "%") or BT.Commas(v))
                fs:SetTextColor(1, 1, 1)
            end
            fs:Show()
        end
        row.item = item
    end
    for i = #list + 1, #f.rows do
        for _, fs in pairs(f.rows[i].cells) do fs:Hide() end
        f.rows[i].item = nil
    end
    f.scroll:SetContent(LAST_W - 48, #list * LAST_ROW + 12)
    f.shown = list
    f:Show()
    return f
end
