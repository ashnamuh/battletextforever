-- BattleText Forever: scrolling combat text for World of Warcraft: Forever.
-- Numbers come from the UNIT_COMBAT event (what happens to a unit: you, your
-- target, the mobs around you), and from the game's combat log lines whenever
-- the game lets an addon read them (see Parse.lua).

local ADDON, ns = ...
local BT = {}
ns.BT = BT
-- The locals the other files share (Display.lua, Attribution.lua...): see the end of each file
local S = {}
ns.S = S
local Parser = ns.Parser
-- The look is the shared one of severd8's Forever addons (Theme.lua, loaded first)
local T = ns.Theme
-- The addon's own text in the player's language (Locales\Locales.lua): L["English"]
local L = ns.L

BT.ICON = T.LOGO
BT.LOGO_TEXT = "|T" .. BT.ICON .. ":0|t"
local function Print(msg) print(T.CHAT_PREFIX .. ": " .. msg) end
BT.Print = Print

-- Text colors
BT.TEXT_COLORS = {
    melee     = { 1.00, 1.00, 1.00 },
    spell     = { 1.00, 0.86, 0.35 },
    heal      = { 0.30, 1.00, 0.35 },
    miss      = { 0.80, 0.80, 0.80 },
    inDamage  = { 1.00, 0.25, 0.25 },
    inAvoid   = { 0.55, 0.80, 1.00 },
    power     = { 0.45, 0.65, 1.00 },
    notify    = { 1.00, 0.85, 0.40 },
    combat    = { 1.00, 0.45, 0.20 },
    xp        = { 0.75, 0.50, 1.00 },
    loot      = { 1.00, 1.00, 1.00 },
    seal      = { 1.00, 0.92, 0.55 },
    buff      = { 0.55, 0.85, 1.00 },
    alert     = { 1.00, 1.00, 0.20 },
    combo     = { 1.00, 0.60, 0.20 },
    dispel    = { 0.60, 1.00, 0.85 },
    lowHealth = { 1.00, 0.20, 0.20 },
    lowMana   = { 0.35, 0.60, 1.00 },
}
-- What they start as; db.colors holds the ones you've changed (ApplyColors)
BT.DEFAULT_COLORS = {}
for k, c in pairs(BT.TEXT_COLORS) do BT.DEFAULT_COLORS[k] = { c[1], c[2], c[3] } end
-- The colors you can change, in the order the options list them
-- (by area: outgoing, incoming, heals, notifications; two columns, read across)
BT.COLOR_CHOICES = {
    { "melee", L["Your hits"] }, { "spell", L["Your spells"] },
    { "miss", L["Your misses"] }, { "inDamage", L["Damage you take"] },
    { "inAvoid", L["Attacks you avoid"] }, { "power", L["Power gains"] },
    { "heal", L["Heals"] }, { "notify", L["Notifications"] },
    { "combat", L["+Combat and killing blows"] }, { "xp", L["Experience"] },
    { "loot", L["Loot"] }, { "seal", L["Seals"] },
    { "buff", L["Buffs"] }, { "alert", L["Ability alerts"] },
    { "combo", L["Combo points"] }, { "dispel", L["Dispels"] },
    { "lowHealth", L["Low health"] }, { "lowMana", L["Low mana"] },
}
-- Spell damage is tinted by its school (the game's own words for them)
local SCHOOL_KEYS = {
    { "STRING_SCHOOL_HOLY", "Holy", { 1.00, 0.92, 0.55 } },
    { "STRING_SCHOOL_FIRE", "Fire", { 1.00, 0.50, 0.10 } },
    { "STRING_SCHOOL_NATURE", "Nature", { 0.40, 1.00, 0.40 } },
    { "STRING_SCHOOL_FROST", "Frost", { 0.50, 0.90, 1.00 } },
    { "STRING_SCHOOL_SHADOW", "Shadow", { 0.72, 0.55, 1.00 } },
    { "STRING_SCHOOL_ARCANE", "Arcane", { 1.00, 0.55, 1.00 } },
}

-- The same schools as UNIT_COMBAT numbers them: 2 Holy, 4 Fire, 8 Nature...
local MASK_COLORS = {}
for i, school in ipairs(SCHOOL_KEYS) do MASK_COLORS[2 ^ i] = school[3] end

-- A hit's school is a spell's: the same, or one of the two a mixed spell is (Frostfire Bolt is
-- Fire and Frost, 20: the game may give its hit as either)
local function InSchool(mask, school)
    if mask == nil or school == nil then return false end
    if mask == school then return true end
    if MASK_COLORS[school] or not MASK_COLORS[mask] then return false end   -- (a mix holds single schools)
    return math.floor(school / mask) % 2 == 1
end

local DEFAULTS = {
    enabled = true,
    locked = true,
    font = "Default",
    fontSize = 20,
    critScale = 150,          -- crits, as a percent of the text size
    scrollTime = 3,           -- seconds a line takes to cross its area
    height = 240,             -- how far a line travels
    outline = "OUTLINE",      -- the outline round normal lines (one of BT.OUTLINES)
    critOutline = "OUTLINE",  -- and round crits
    critFont = "",            -- crits' own font (one of BT.FONTS' names); "": the same as other lines
    sticky = true,            -- crits pop and hold in place
    popApart = false,         -- Pop lines that would land on one another move to the nearest free spot
    iconZoom = false,         -- crop icons' edges so their art fills the square
    sizeByHit = false,        -- a big hit shows bigger than the hits before it, a small one smaller
    -- Spell (and skill) icons and names, per section of the options
    outIcons = true, outNames = true,      -- your hits and misses
    inIcons = true, inNames = true,        -- what happens to you
    healIcons = true, healNames = true,    -- heals, yours and on you
    nIcons = true,                         -- notifications: loot and skill ups
    merge = true,             -- rapid hits of one spell add up on one line
    tickMerge = 0,            -- seconds ticks and area hits keep adding up (0: as quick as other hits)
    minDamage = 0,            -- hide your hits below this
    minCrit = 0,              -- a crit for less than this shows as a normal line (0: every crit stands out)
    -- Which area each kind of text shows in (BT.ROUTES; any key of BT.AREAS)
    routeOutDamage = "outgoing", routeOutMisses = "outgoing", routeOutHeals = "heal",
    routeInDamage = "incoming", routeInMisses = "incoming", routeInHeals = "heal", routeInPower = "incoming",
    routeNotify = "notify",
    healOver = true,          -- show overhealing after a heal, when the game says
    minHeal = 0,              -- hide heals below this
    healWho = true,           -- "on <name>" after a heal you do, when the game says who
    shortNumbers = false,     -- 12,345 as 12.3k
    colors = {},              -- text colors you've changed, by BT.TEXT_COLORS key
    -- Each area's text size (percent of the text size) and opacity (percent)
    outSize = 100, outAlpha = 100, inSize = 100, inAlpha = 100,
    healSize = 100, healAlpha = 100, nSize = 100, nAlpha = 100,
    -- Each area's scrolling: up instead of down, and (the side areas) bowing outward
    outScrollUp = false, inScrollUp = false, healScrollUp = false, nScrollUp = false,
    outCurved = true, inCurved = true,
    -- The side areas' text: which side its lines line up on (one of BT.ALIGNS)
    outAlign = "LEFT", inAlign = "RIGHT",
    -- Each area's way of moving its lines (one of BT.STYLES)
    outStyle = "scroll", inStyle = "scroll", healStyle = "scroll", nStyle = "scroll",
    outDamage = true, outHeals = true, outMisses = true, outPet = true, outShields = true,
    outSeals = true,          -- name a seal's hit beside your swing
    outSwings = true,         -- your auto attacks (white swings)
    outTicks = true,          -- the ticks of your DoTs and lingering area spells (Consecration, Blizzard...)
    shieldAmounts = {},       -- learned: what each damage shield of yours hits for (by its name)
    inDamage = true, inHeals = true, inMisses = true, inPower = false,
    inOtherHeals = true,      -- heals on you the game doesn't name (other players', food, passives)
    inBlocked = true,         -- "(blocked)" after a hit on you that you partly blocked
    inSchools = true,         -- a magic hit on you in its school's color, with the school's name ("-120 Shadow")
    nCombat = true, nKill = true, nXP = true, nRep = true, nHonor = true,
    nLoot = true, nMoney = false, nSkill = true, nSeals = true,
    nBuffs = false,           -- a line when a buff goes on or comes off (out of a fight only)
    nSummary = true,          -- at the end of a fight: your damage, DPS and healing
    nAlerts = true,           -- "Overpower!" when an ability you can use only just then opens up
    nCombo = true,            -- "3 CP", and "5 CP: Finish it!" (rogues and cat druids)
    nDispels = true,          -- "Dispelled Corruption" when you take something off (Cleanse, Purge...)
    nCooldowns = true,        -- "Kick ready" when a spell of yours comes off its cooldown
    nInterrupts = true,       -- "Interrupted Frostbolt" when you stop an enemy's cast
    spellRules = {},          -- spells you hide or recolor (Spells tab): { { name =, hide =, color = { r, g, b } } }
    soundCrit = false,        -- a sound when you crit
    soundKill = false,        -- a sound on a killing blow
    critSound = "UI_PROFESSION_CRAFTING_RESULT_CRIT",   -- which ones (keys of BT.SOUNDS)
    killSound = "UI_RAID_BOSS_DEFEATED",
    warnHealth = false,       -- "Low health!" and a sound as you drop to 35% health
    warnMana = false,         -- "Low mana!" and a sound as your mana drops to lowManaAt
    lowManaAt = 35,           -- percent
    lowHealthSound = "RAID_WARNING",
    lowManaSound = "READY_CHECK",
    hideBlizzard = false,
    minimap = true,
    startReminder = true,   -- a line in chat after logging in, while Start hasn't been clicked
    loginMessage = true,    -- "BattleText Forever loaded. Type /btf for options." in chat at login
    minimapAngle = 215,
    debug = false,
    areas = {
        incoming = { x = -230, y = 20 },
        outgoing = { x = 230, y = 20 },
        notify = { x = 0, y = 170 },
        heal = { x = 0, y = -190 },
    },
}
BT.DEFAULTS = DEFAULTS

-- "Default" is the game's own font for your language. The next four come with
-- the game; the rest are in this addon's Fonts folder (each under its own
-- open licence, in Fonts/Licenses).
-- cyr: the font has Russian (Cyrillic) letters. cyrPath: the game's own Cyrillic copy of
-- that font (every client has them: Blizzard_Fonts_Shared's "russian" members). A font
-- without the letters shows Russian names blank, so on a Russian game only the fonts that
-- have them are offered; on Korean and Chinese games, only Default (none of these have the
-- letters). Checked with fontTools (2026-11-23): 64 of 64 Cyrillic capitals and small
-- letters, or none.
local FONT_DIR = "Interface\\AddOns\\BattleTextForever\\Fonts\\"
BT.FONTS = {
    { name = "Default" },
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF", cyrPath = "Fonts\\FRIZQT___CYR.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF", cyr = true },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF", cyrPath = "Fonts\\MORPHEUS_CYR.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF", cyrPath = "Fonts\\SKURRI_CYR.TTF" },
    { name = "Anton", path = FONT_DIR .. "Anton-Regular.ttf" },
    { name = "Archivo Black", path = FONT_DIR .. "ArchivoBlack-Regular.ttf" },
    { name = "Bangers", path = FONT_DIR .. "Bangers-Regular.ttf" },
    { name = "Barlow Condensed", path = FONT_DIR .. "BarlowCondensed-Bold.ttf" },
    { name = "Bebas Neue", path = FONT_DIR .. "BebasNeue-Regular.ttf" },
    { name = "Cinzel Decorative", path = FONT_DIR .. "CinzelDecorative-Bold.ttf" },
    { name = "Fira Sans", path = FONT_DIR .. "FiraSans-Bold.ttf", cyr = true },
    { name = "Lato", path = FONT_DIR .. "Lato-Bold.ttf", cyr = true },
    { name = "Luckiest Guy", path = FONT_DIR .. "LuckiestGuy-Regular.ttf" },
    { name = "Metamorphous", path = FONT_DIR .. "Metamorphous-Regular.ttf" },
    { name = "New Rocker", path = FONT_DIR .. "NewRocker-Regular.ttf" },
    { name = "Permanent Marker", path = FONT_DIR .. "PermanentMarker-Regular.ttf" },
    { name = "Poppins", path = FONT_DIR .. "Poppins-Bold.ttf" },
    { name = "Press Start 2P", path = FONT_DIR .. "PressStart2P-Regular.ttf", cyr = true },
    { name = "PT Sans Narrow", path = FONT_DIR .. "PTSansNarrow-Bold.ttf", cyr = true },
    { name = "Rajdhani", path = FONT_DIR .. "Rajdhani-Bold.ttf" },
    { name = "Russo One", path = FONT_DIR .. "RussoOne-Regular.ttf", cyr = true },
    { name = "Ubuntu", path = FONT_DIR .. "Ubuntu-Bold.ttf", cyr = true },
}

-- How thick the outline round the letters is: the game's font flags
BT.OUTLINES = {
    { name = L["None"], flags = "" },
    { name = L["Thin"], flags = "OUTLINE" },
    { name = L["Thick"], flags = "THICKOUTLINE" },
    { name = L["Shadow"], flags = "SHADOW" },   -- no outline: a drop shadow
}

-- Which side the lines in an area line up on
BT.ALIGNS = {
    { key = "LEFT", name = L["Left"] }, { key = "CENTER", name = L["Center"] }, { key = "RIGHT", name = L["Right"] },
}

-- How the lines in an area move
BT.STYLES = {
    { key = "scroll", name = L["Scroll"] },           -- up or down the area, one after another
    { key = "pop", name = L["Pop"] },                 -- jump out somewhere in the area and fade
    { key = "fountain", name = L["Fountain"] },       -- thrown up and falling to one side
    { key = "horizontal", name = L["Horizontal"] },   -- slide sideways, away from the middle
}

-- Scroll areas. dir: which way a curved line bows (-1 left, 1 right, 0 none).
BT.AREAS = {
    incoming = { label = "Incoming", title = L["Incoming"], dir = -1, justify = "RIGHT", prefix = "in" },
    outgoing = { label = "Outgoing", title = L["Outgoing"], dir = 1, justify = "LEFT", prefix = "out" },
    notify   = { label = "Notifications", title = L["Notifications"], dir = 0, justify = "CENTER", short = true, prefix = "n" },
    heal     = { label = "Healing", title = L["Healing"], dir = 0, justify = "CENTER", heightScale = 0.6, prefix = "heal" },
}
local AREA_WIDTH = 60        -- how far a curved line bows out
local MAX_DELAY = 1.2        -- a line never waits longer than this for room
local MERGE_WINDOW = 0.5

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function Num(v) if IsSecret(v) or type(v) ~= "number" then return nil end return v end
local function Str(v) if IsSecret(v) or type(v) ~= "string" then return nil end return v end
BT.IsSecret, BT.Num, BT.Str = IsSecret, Num, Str
-- An amount as text for the debug lines: a hidden one says so (tostring of a secret is
-- a secret string, and one of those in BT.recorded broke /btf copy: issue #23)
local function AmountText(v) if IsSecret(v) then return "(hidden amount)" end return tostring(v) end
BT.AmountText = AmountText

-- A yes-or-no question for the game, answered with a plain true or false
-- (false when the game hides the answer, or doesn't have the function)
local function Flag(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    return ok and not IsSecret(v) and (v == true or v == 1)
end

-- Whether a unit's target is `who` ("player" or "pet"). On an addon-restricted map (dungeons,
-- raids, PvP) the game hides every comparison of a compound token ("nameplate3target"); then the
-- threat table answers instead: a mob you (or your pet) are tanking is after you.
local function TargetIs(unit, who)
    if not UnitIsUnit then return false end
    local ok, v = pcall(UnitIsUnit, unit .. "target", who)
    if ok and not IsSecret(v) then return v == true end
    if not ok or not UnitThreatSituation then return false end
    local okThreat, status = pcall(UnitThreatSituation, who, unit)
    status = okThreat and Num(status) or nil
    return status ~= nil and status >= 2
end
local function TargetsYou(unit) return TargetIs(unit, "player") end
-- Whether a unit is your pet's target. Hidden on those maps too ("pettarget" is compound): then
-- a unit that has your pet on its threat table is one your pet is fighting.
local function PetsTarget(unit)
    if not UnitIsUnit then return false end
    local ok, v = pcall(UnitIsUnit, unit, "pettarget")
    if ok and not IsSecret(v) then return v == true end
    if not ok or not UnitThreatSituation then return false end
    local okThreat, status = pcall(UnitThreatSituation, "pet", unit)
    return okThreat and Num(status) ~= nil
end
BT.TargetIs = TargetIs

-- The game's language is English (the spell lists' names are English)
local function IsEnglish()
    return not GetLocale or GetLocale() == "enUS" or GetLocale() == "enGB"
end

local function FillDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = type(v) == "table" and FillDefaults({}, v) or v
        elseif type(v) == "table" and type(t[k]) == "table" then
            FillDefaults(t[k], v)
        end
    end
    return t
end

-- Settings that were renamed: an old one becomes the new ones it was split into
local SPLIT_SETTINGS = {
    icons = { "outIcons", "inIcons", "healIcons", "nIcons" },
    spellNames = { "outNames", "inNames", "healNames" },
    scrollUp = { "outScrollUp", "inScrollUp", "healScrollUp", "nScrollUp" },   -- (one for all areas until 1.8.0)
    curved = { "outCurved", "inCurved" },
}
function BT:MoveOldSettings(db)
    -- "Own area for heals" off (until 1.16.0): heals went with damage
    if db.healArea == false then
        db.routeOutHeals = db.routeOutHeals or "outgoing"
        db.routeInHeals = db.routeInHeals or "incoming"
    end
    db.healArea = nil
    for old, new in pairs(SPLIT_SETTINGS) do
        if db[old] ~= nil then
            for _, key in ipairs(new) do
                if db[key] == nil then db[key] = db[old] end
            end
            db[old] = nil
        end
    end
end

local function Commas(n)
    -- "Short numbers": 12.3k, 1.2m
    if BT.db and BT.db.shortNumbers and type(n) == "number" and n >= 10000 then
        local v, unit = n / 1000, "k"
        if n >= 1000000 then v, unit = n / 1000000, "m" end
        return (("%.1f"):format(v):gsub("%.0$", "")) .. unit
    end
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and Str(s) then return s end
    end
    return tostring(n)
end
BT.Commas = Commas

-- Shared with the files loaded after this one
S.BT, S.T, S.L, S.DEFAULTS, S.AREA_WIDTH, S.MAX_DELAY = BT, T, L, DEFAULTS, AREA_WIDTH, MAX_DELAY
S.MERGE_WINDOW, S.IsSecret, S.Num, S.Str, S.Flag, S.Print = MERGE_WINDOW, IsSecret, Num, Str, Flag, Print
S.SCHOOL_KEYS, S.Commas, S.IsEnglish, S.Parser, S.MASK_COLORS, S.InSchool = SCHOOL_KEYS, Commas, IsEnglish, Parser, MASK_COLORS, InSchool
S.AmountText, S.TargetIs, S.TargetsYou, S.PetsTarget, S.FillDefaults = AmountText, TargetIs, TargetsYou, PetsTarget, FillDefaults
