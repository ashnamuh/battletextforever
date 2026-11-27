-- BattleText Forever: combat log lines read, what happens to you, low health and mana, where your casts go.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, L, Print, SCHOOL_KEYS, IsSecret, Num = S.BT, S.L, S.Print, S.SCHOOL_KEYS, S.IsSecret, S.Num
local Str, Flag, Commas = S.Str, S.Flag, S.Commas

---------------------------------------------------------------------------
-- Turning combat into lines of text
---------------------------------------------------------------------------
function BT:SchoolColor(unit)
    if not self.schools then
        self.schools = {}
        for _, s in ipairs(SCHOOL_KEYS) do
            local word = Str(_G[s[1]]) or s[2]
            self.schools[word:lower()] = s[3]
        end
    end
    return unit and self.schools[unit:lower()]
end

-- The school of a hit on you, for its color and word ("-120 Shadow", in shadow purple; GitHub #33):
-- by the log line's school word, or by UNIT_COMBAT's school mask (never hidden on Forever, only
-- the amount is). A mix of schools goes by its first. Physical (or none, or "Schools" off): nil.
-- spell: the spell's name on the line; one that holds the word already ("Shadow Bolt") skips it.
function BT:IncomingSchool(word, mask, spell)
    if not (self.db and self.db.inSchools) then return nil end
    local color, label
    word = Str(word)
    if word then
        color = self:SchoolColor(word)
        label = color and word or nil
    elseif not IsSecret(mask) and Num(mask) then
        local m = Num(mask)
        for i, s in ipairs(SCHOOL_KEYS) do
            if math.floor(m / 2 ^ i) % 2 == 1 then
                color, label = s[3], Str(_G[s[1]]) or s[2]
                break
            end
        end
    end
    if not color then return nil end
    if spell and spell:lower():find(label:lower(), 1, true) then return color, "" end
    return color, " " .. label
end

-- An icon (a texture's file ID or path) as text, with a space after it. With "Icon zoom" the
-- icon's edge is cropped (8% each side of the usual 64x64 icon), so the art fills its square.
function BT:IconTag(tex)
    if self.db and self.db.iconZoom then return "|T" .. tex .. ":0:0:0:0:64:64:5:59:5:59|t " end
    return "|T" .. tex .. ":0|t "
end

-- A spell's icon as text, by its ID or name
function BT:IconText(spell)
    if not spell then return "" end
    self.iconCache = self.iconCache or {}
    local cached = self.iconCache[spell]
    -- A name the game couldn't place just then (its data not loaded yet) is asked again
    -- a little later, rather than left without an icon until /reload
    local missAt = self.iconMissAt and self.iconMissAt[spell]
    if cached == false and missAt and GetTime() - missAt >= 10 then cached = nil end
    if cached == nil then
        cached = false
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
            if ok and not IsSecret(tex) and tex then cached = Num(tex) or Str(tex) or false end
        end
        self.iconCache[spell] = cached
        if type(spell) == "string" then
            self.iconMissAt = self.iconMissAt or {}
            self.iconMissAt[spell] = (not cached) and GetTime() or nil
        end
    end
    return cached and self:IconTag(cached) or ""
end

-- A spell after a number, on lines about you: " <icon> Fireball", either part
-- left out when it's turned off or unknown
local function SpellAfter(icon, name)
    if name then return " " .. icon .. name end
    if icon ~= "" then return " " .. icon:gsub(" $", "") end
    return ""
end

-- "(3 blocked)" style notes after a number
local function Partials(info, noBlocked)
    local parts = {}
    if info.blocked and not noBlocked then parts[#parts + 1] = L["%s blocked"]:format(Commas(info.blocked)) end
    if info.absorbed then parts[#parts + 1] = L["%s absorbed"]:format(Commas(info.absorbed)) end
    if info.resisted then parts[#parts + 1] = L["%s resisted"]:format(Commas(info.resisted)) end
    if info.glancing then parts[#parts + 1] = BT:HitNote("glancing") end
    if info.crushing then parts[#parts + 1] = BT:HitNote("crushing") end
    if #parts == 0 then return "" end
    return " |cffb0b0b0(" .. table.concat(parts, ", ") .. ")|r"
end

-- The short word for a way of missing: "Dodge", "Parry"
local MISS_TEXT = { MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
    ABSORB = "Absorb", IMMUNE = "Immune", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect",
    MISFIRE = "Misfire" }
-- A translation in Locales wins (GitHub #47: a Korean player still saw one in English), then
-- the game's own word, then the English
local function MissText(missType)
    missType = missType or "MISS"
    if not MISS_TEXT[missType] then missType = "MISS" end
    local words = { MISS = L["Miss"], DODGE = L["Dodge"], PARRY = L["Parry"], BLOCK = L["Block"],
        RESIST = L["Resist"], ABSORB = L["Absorb"], IMMUNE = L["Immune"], EVADE = L["Evade"],
        DEFLECT = L["Deflect"], REFLECT = L["Reflect"], MISFIRE = L["Misfire"] }
    local english = MISS_TEXT[missType]
    if words[missType] ~= english then return words[missType] end
    local game = Str(_G[missType])
    return (game and game ~= "") and game or english
end
BT.MissText = MissText

-- A spell's icon and name as one section of the options shows them
-- (section: "out", "in" or "heal"); either is left out when it's turned off. A spell given an
-- icon on the Spells tab wears that one.
function BT:SpellParts(section, icon, name)
    local db = self.db
    -- (an icon of your own for it, from the Spells tab, even where the game has none)
    local own = name and self:RuleIcon(name)
    if own then icon = own end
    return db[section .. "Icons"] and icon or "", db[section .. "Names"] and name or nil
end

-- The order of a line of yours (Outgoing tab and Healing tab, "Line order"): a pattern like
-- "{icon} {name} {damage}" (CurseForge, xSky7: "{icon} {damage} {name}"). key: "outFormat" (your
-- hits and misses) or "healFormat" (your heals). Returns the text before the number and the text
-- after it: the number is never put in here, so a hidden one is still written by the game between
-- the two (Emit's opts.after). A part that's empty (icons or names off, a swing) leaves no gap.
-- {name} is the spell's name and your pet's mark; {damage} the number (on a miss, "Dodge").
BT.LINE_FORMAT = "{icon} {name} {damage}"
local NUMBER_MARK = "\1"
function BT:LineParts(key, icon, name, pet)
    local format = self.db[key]
    if type(format) ~= "string" or not format:find("%S") then format = BT.LINE_FORMAT end
    local who = ((name or "") .. " " .. (pet or "")):match("^%s*(.-)%s*$")
    local parts = { icon = (icon:gsub(" $", "")), name = who, damage = NUMBER_MARK, amount = NUMBER_MARK }
    -- (a "|" typed in it is a "|", never the start of a color or an icon)
    local text = format:gsub("|", "||"):gsub("{(%a+)}", function(k) return parts[k:lower()] end)
    if not text:find(NUMBER_MARK, 1, true) then text = text .. " " .. NUMBER_MARK end
    local before, after = text:match("^(.-)\1(.*)$")
    after = after:gsub(NUMBER_MARK, "")   -- (the number once only)
    -- (an empty part leaves no double space, and none at the line's ends)
    before = before:gsub("%s+", " "):gsub("^ ", "")
    after = after:gsub("%s+", " "):gsub(" $", "")
    return before, after
end

-- Your pet's name, to mark its hits with ("Pet" when it can't be read). UnitName is
-- SecretWhenUnitNameIdentityRestricted on Forever, so the last name read is kept for the same
-- pet (Tinter on CurseForge: "add your pet's name instead of just (Pet)").
function BT:PetName()
    local okName, name = pcall(UnitName, "pet")
    name = okName and Str(name) or nil
    local okGuid, guid = pcall(UnitGUID, "pet")
    guid = okGuid and Str(guid) or nil
    if name and name ~= "" and name ~= UNKNOWNOBJECT then
        self.petName = { name = name, guid = guid }
        return name
    end
    local kept = self.petName
    if kept and (not guid or not kept.guid or kept.guid == guid) then return kept.name end
    return L["Pet"]
end

-- The mark in front of your pet's hits: "(Fluffy) "
function BT:PetLabel()
    return "(" .. self:PetName() .. ") "
end

-- Your pet's line: the one who did it is your pet (the line's link says who)
function BT:IsPetLine(info)
    if info.fromMe or not info.srcGUID or not UnitGUID then return false end
    local ok, guid = pcall(UnitGUID, "pet")
    guid = ok and Str(guid) or nil
    return guid ~= nil and guid == info.srcGUID
end

-- What happens to you comes from UNIT_COMBAT, unless the combat log is
-- delivering it (the player picked a filter that includes it). fromLog[what]
-- counts the UNIT_COMBAT events since the log last delivered one: after three
-- with nothing from the log, the filter has changed and UNIT_COMBAT takes over.
-- It also stops LOG_STALE seconds after the log's last one: a lone line once (a filter tried
-- and changed back) took the next three hits on you, whenever they came.
local LOG_STALE = 3
function BT:NoteLogIncoming(what)
    self.fromLog = self.fromLog or {}
    self.fromLogAt = self.fromLogAt or {}
    self.fromLog[what], self.fromLogAt[what] = 0, GetTime()
end

function BT:LogCovers(what)
    local n = self.fromLog and self.fromLog[what]
    if not n then return false end
    local at = self.fromLogAt and self.fromLogAt[what]
    if n >= 3 or (at and GetTime() - at > LOG_STALE) then
        self.fromLog[what] = nil
        return false
    end
    self.fromLog[what] = n + 1
    return true
end

function BT:LogDelivers(what)
    if not (self.fromLog and self.fromLog[what] ~= nil) then return false end
    local at = self.fromLogAt and self.fromLogAt[what]
    return not (at and GetTime() - at > LOG_STALE)
end

-- The fight's totals, for the summary when it ends (only numbers the game lets be read)
function BT:CountFight(what, n)
    local f = not self.testing and self.fight   -- (sample text isn't the fight's)
    if f and type(n) == "number" and n > 0 then f[what] = f[what] + n end
end

-- The same, by spell, for /btf last. name: what the hit was named (or "Auto attack",
-- "Unnamed Fire"); heal: a heal; icon: as text, for the window.
function BT:CountSpell(name, n, crit, heal, icon)
    local f = not self.testing and self.fight
    if not f or type(n) ~= "number" or n <= 0 or not name then return end
    f.spells = f.spells or {}
    local key = (heal and "heal:" or "damage:") .. name
    local s = f.spells[key]
    if not s then
        s = { name = name, heal = heal or false, icon = icon or "", hits = 0, crits = 0, total = 0, biggest = 0 }
        f.spells[key] = s
    end
    s.hits, s.total = s.hits + 1, s.total + n
    if crit then s.crits = s.crits + 1 end
    if n > s.biggest then s.biggest = n end
end

-- What to call a hit nothing named, for /btf last: a physical one is a swing, the rest by school
local function UnnamedHit(mask)
    if not mask or mask == 1 then return L["Auto attack"] end
    for i, school in ipairs(SCHOOL_KEYS) do
        if 2 ^ i == mask then return L["Unnamed %s"]:format(Str(_G[school[1]]) or school[2]) end
    end
    return L["Unnamed"]
end

-- The last fight by spell: damage first, then heals, each biggest total first, with each
-- one's share of its kind ("share", a percent). Returns the rows and the fight.
function BT:FightBreakdown(f)
    f = f or self.lastFight
    if not f then return nil end
    local rows = {}
    for _, s in pairs(f.spells or {}) do rows[#rows + 1] = s end
    table.sort(rows, function(a, b)
        if a.heal ~= b.heal then return not a.heal end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    for _, s in ipairs(rows) do
        local all = s.heal and f.heal or f.damage
        s.share = all > 0 and math.floor(s.total * 100 / all + 0.5) or 0
    end
    return rows, f
end

-- "4,820 damage (127 DPS), 1,200 healed in 38s"
function BT:FightLine(f)
    local parts = {}
    if f.damage > 0 then
        parts[#parts + 1] = L["%s damage (%s DPS)"]:format(Commas(f.damage), Commas(math.floor(f.damage / f.secs + 0.5)))
    end
    if f.heal > 0 then parts[#parts + 1] = L["%s healed"]:format(Commas(f.heal)) end
    return L["%s in %ss"]:format(table.concat(parts, ", "), f.secs)
end

function BT:FightSummary()
    local f = self.fight
    self.fight = nil
    if not f or (f.damage == 0 and f.heal == 0) then return end
    f.secs = math.max(1, math.floor(GetTime() - f.start + 0.5))
    self.lastFight = f
    if self.db.nSummary then self:Notify(self:FightLine(f), self.TEXT_COLORS.notify) end
end

-- The game's sounds you can pick for a crit or a killing blow, by their SOUNDKIT
-- name. Forever may not have every one of them: a sound it lacks plays the
-- fallback (FALLBACK_SOUNDS) instead.
BT.SOUNDS = {
    { key = "UI_PROFESSION_CRAFTING_RESULT_CRIT", name = L["Crafting crit"] },
    { key = "UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_MEDIUM", name = L["Impact"] },
    { key = "UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_LOW", name = L["Low impact"] },
    { key = "UI_REFORGING_REFORGE", name = L["Anvil"] },
    { key = "UI_POWER_AURA_GENERIC", name = L["Power up"] },
    { key = "UI_LOSS_OF_CONTROL_START", name = L["Whoosh"] },
    { key = "MAP_PING", name = L["Ping"] },
    { key = "LOOT_WINDOW_COIN_SOUND", name = L["Coins"] },
    { key = "RAID_WARNING", name = L["Raid warning"] },
    { key = "READY_CHECK", name = L["Ready check"] },
    { key = "PVP_THROUGH_QUEUE", name = L["Battle horn"] },
    { key = "UI_BATTLEGROUND_COUNTDOWN_FINISHED", name = L["Countdown end"] },
    { key = "IG_QUEST_LIST_COMPLETE", name = L["Quest complete"] },
    { key = "UI_RAID_BOSS_DEFEATED", name = L["Boss defeated"] },
    { key = "UI_MISSION_SUCCESS_CHEERS", name = L["Cheers"] },
    { key = "UI_CHALLENGES_NEW_RECORD", name = L["New record"] },
    { key = "UI_EPICLOOT_TOAST", name = L["Epic loot"] },
    { key = "UI_LEGENDARY_LOOT_TOAST", name = L["Legendary loot"] },
}
local FALLBACK_SOUNDS = { crit = "MAP_PING", kill = "IG_QUEST_LIST_COMPLETE", lowHealth = "MAP_PING",
    lowMana = "MAP_PING" }

function BT:SoundName(key)
    for _, s in ipairs(self.SOUNDS) do
        if s.key == key then return s.name end
    end
    return self.SOUNDS[1].name
end

-- Plays a sound by its SOUNDKIT name; true if the game has it
local function PlayKit(key)
    -- A sound another addon shares: played from its file
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        if not PlaySoundFile then return false end
        for _, s in ipairs(BT.SOUNDS) do
            if s.key == key and s.file then
                local ok, played = pcall(PlaySoundFile, s.file, "Master")
                return ok and played ~= false and not IsSecret(played)
            end
        end
        return false
    end
    local kit = key and SOUNDKIT and SOUNDKIT[key]
    if not PlaySound or type(kit) ~= "number" or kit == 0 then return false end
    local ok, played = pcall(PlaySound, kit, "Master", true)
    return ok and played ~= false and not IsSecret(played)
end

-- A sound for a crit or a killing blow (never more than one at a time)
function BT:PlayAlert(what)
    if self.testing or not self.db.enabled then return end
    local now = GetTime()
    self.alertAt = self.alertAt or {}
    if self.alertAt[what] and now - self.alertAt[what] < 0.3 then return end
    self.alertAt[what] = now
    if not PlayKit(self.db[what .. "Sound"]) then PlayKit(FALLBACK_SOUNDS[what]) end
end

-- Picking a sound in the options plays it, and says if this game doesn't have it
function BT:SetAlertSound(what, key)
    self.db[what .. "Sound"] = key
    if not PlayKit(key) then
        Print(L["%s isn't in this game's sounds. Pick another: until then, %s plays instead."]:format(
            self:SoundName(key), self:SoundName(FALLBACK_SOUNDS[what])))
    end
end

---------------------------------------------------------------------------
-- Low health and low mana: "Low health!" and a sound as you drop below the line. Once:
-- it warns again only after you've been back above it.
---------------------------------------------------------------------------
-- Your health is hidden from addons (UnitHealth always answers with a secret), so when it
-- can't be read BattleText goes by the game's own low health warning: the red screen edges
-- (LowHealthFrame), which the game shows at 35% health. Mana is read as it is, when it can be.
local LOW_HEALTH = 0.35      -- the game's line (LowHealthFrame.lowHealthPercentStart)
local MANA_BACK = 10         -- mana comes back this many points over the line before it warns again
local WARN_GAP = 5           -- never the same warning twice in this many seconds

local function Dead()
    if not UnitIsDeadOrGhost then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return ok and not IsSecret(dead) and dead and true or false
end

-- true: at or below 35% health. nil: can't tell right now.
function BT:HealthLow()
    if Dead() then return false end
    local okH, hp = pcall(UnitHealth, "player")
    local okM, most = pcall(UnitHealthMax, "player")
    hp, most = okH and Num(hp) or nil, okM and Num(most) or nil
    if hp and most and most > 0 then return hp / most <= LOW_HEALTH end
    -- Hidden: the red screen edges say
    local f = LowHealthFrame
    if type(f) ~= "table" or not f.IsShown then return nil end
    if GetUIPanel then   -- (in a fight they also flash while the map is open, whatever your health)
        local ok, panel = pcall(GetUIPanel, "fullscreen")
        if ok and panel then return nil end
    end
    local ok, shown = pcall(f.IsShown, f)
    if not ok or IsSecret(shown) then return nil end
    return shown and true or false
end

-- Your mana as a percent; nil if you have none or it's hidden
function BT:ManaPercent()
    local kind = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local okN, n = pcall(UnitPower, "player", kind)
    local okM, most = pcall(UnitPowerMax, "player", kind)
    n, most = okN and Num(n) or nil, okM and Num(most) or nil
    if not n or not most or most <= 0 then return nil end
    return n / most * 100
end

function BT:Warn(what)
    local now = GetTime()
    self.warnedAt = self.warnedAt or {}
    if self.warnedAt[what] and now - self.warnedAt[what] < WARN_GAP then return end
    self.warnedAt[what] = now
    local C = self.TEXT_COLORS
    if what == "lowHealth" then
        self:Notify(L["Low health!"], C.lowHealth, { crit = true })
    else
        self:Notify(L["Low mana!"], C.lowMana, { crit = true })
    end
    self:PlayAlert(what)
end

-- The first look (at login) only notes where you are
function BT:CheckLowHealth()
    local low = self:HealthLow()
    if low == nil then return end
    local was = self.healthLow
    self.healthLow = low
    if low and was == false and self.db.warnHealth and self.db.enabled then self:Warn("lowHealth") end
end

function BT:CheckLowMana()
    local pct = Dead() and 100 or self:ManaPercent()
    self:UpdateManaSign(pct == nil)
    if pct == nil then return end
    local line = self.db.lowManaAt
    local was = self.manaLow
    if pct <= line then
        self.manaLow = true
        if was == false and self.db.warnMana and self.db.enabled then self:Warn("lowMana") end
    elseif was == nil or pct >= line + MANA_BACK or pct >= 100 then
        self.manaLow = false
    end
end

-- When the game hides your mana (Forever does for some players: issue #26's debug), BattleText
-- can't tell when it drops below the line, so no "Low mana!" line or sound can be timed. The game
-- still lets an addon hand its hidden mana percent to a curve and show the answer: a steady
-- "Low mana" just above the notifications, see-through above the line (UnitPowerPercent with a
-- step curve: 1 below the line, 0 from it up, given straight to SetAlpha, never read back).
function BT:ManaSignCurve()
    local line = self.db.lowManaAt
    if self.manaCurve and self.manaCurveAt == line then return self.manaCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateCurve)
    if not ok or not curve then return nil end
    if Enum and Enum.LuaCurveType and curve.SetType then pcall(curve.SetType, curve, Enum.LuaCurveType.Step) end
    -- (a step curve takes a point's value from that point up: the line itself still counts as low)
    pcall(curve.AddPoint, curve, 0, 1)
    pcall(curve.AddPoint, curve, line / 100 + 0.001, 0)
    self.manaCurve, self.manaCurveAt = curve, line
    return curve
end

-- hidden: the game hides your mana right now. Shows or hides the sign (nothing to show when mana
-- can be read: then "Low mana!" scrolls by as usual).
function BT:UpdateManaSign(hidden)
    local sign = self.manaSign
    local area = self.areas and self.areas[self:Area("Notify")]
    local kind = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local okM, most = pcall(UnitPowerMax or function() end, "player", kind)
    local show = hidden and area and self.db.warnMana and self.db.enabled   -- (dead: CheckLowMana says not hidden)
        and okM and (Num(most) or 0) > 0 and UnitPowerPercent ~= nil
    local alpha
    if show then
        local curve = self:ManaSignCurve()
        local ok, a = false, nil
        if curve then ok, a = pcall(UnitPowerPercent, "player", kind, false, curve) end
        if ok and a ~= nil then alpha = a else show = false end
    end
    if not show then
        if sign then sign:Hide() end
        return
    end
    if not sign then
        sign = CreateFrame("Frame", nil, UIParent)
        sign:SetSize(10, 10)
        sign:SetFrameStrata("HIGH")
        sign.text = sign:CreateFontString(nil, "OVERLAY")
        sign.text:SetPoint("BOTTOM", sign, "BOTTOM", 0, 0)
        self.manaSign = sign
        if self.db.debug then self:Record("LOW MANA mana hidden: the sign goes by the game's own percent") end
    end
    if sign.area ~= area then
        sign.area = area
        sign:ClearAllPoints()
        sign:SetPoint("BOTTOM", area, "TOP", 0, 6)
    end
    local size = math.floor(self.db.fontSize * self.db.critScale / 100 + 0.5)
    local flags = self:OutlineFlags(true)
    if flags == "SHADOW" then flags = "" end
    -- (this runs on every change to your mana: the font and text are set only when they change)
    local path = self:FontPath(true)
    if sign.fontPath ~= path or sign.fontSize ~= size or sign.fontFlags ~= flags then
        local fontSet = sign.text:SetFont(path, size, flags)
        if not fontSet and STANDARD_TEXT_FONT then fontSet = sign.text:SetFont(STANDARD_TEXT_FONT, size, flags) end
        if not fontSet then return end   -- (no font at all: SetText would be an error)
        sign.fontPath, sign.fontSize, sign.fontFlags = path, size, flags
        -- (the text only after its font: a new font string has none, and SetText on it is an error)
        sign.text:SetText(L["Low mana"])
    end
    local c = self.TEXT_COLORS.lowMana
    if sign.color ~= c then
        sign.color = c
        sign.text:SetTextColor(c[1], c[2], c[3])
    end
    sign:SetAlpha(alpha)   -- (a hidden number: only the game reads it)
    sign:Show()
end

-- The red edges coming and going are what says your health is low, when it's hidden
function BT:HookLowHealth()
    local f = LowHealthFrame
    if self.lowHealthHooked or type(f) ~= "table" or not f.HookScript then return end
    self.lowHealthHooked = true
    f:HookScript("OnShow", function() BT:CheckLowHealth() end)
    f:HookScript("OnHide", function() BT:CheckLowHealth() end)
end

-- One parsed combat log line (see Parser:Parse). Returns true if it's a kind
-- of line BattleText shows (even if a setting hides it), false if not.
function BT:ShowCombat(info)
    local db, C = self.db, self.TEXT_COLORS
    local spellIcon = self:IconText(info.spellId or info.spell)
    if info.melee and info.fromMe and not info.toMe then spellIcon = self:SwingIcon() end
    local section = info.kind == "heal" and "heal" or info.toMe and "in" or "out"
    local icon, name = self:SpellParts(section, spellIcon, info.spell)
    local mine = info.fromMe == true
    local pet = not mine and self:IsPetLine(info)
    local petTag = pet and self:PetLabel() or ""
    -- Your line: the text before its number and after it, in the order you set
    local outPre, outPost = self:LineParts(info.kind == "heal" and "healFormat" or "outFormat", icon, name, petTag)

    if info.kind == "damage" then
        if not info.amount then return false end
        if info.toMe then
            -- Damage you do to yourself is in the log either way; UNIT_COMBAT shows it
            if mine and not self:LogDelivers("damage") then return true end
            if not mine then self:NoteLogIncoming("damage") end
            if db.inDamage then
                local color, school = self:IncomingSchool(info.unit, nil, name)
                local text = "-" .. Commas(info.amount) .. (school or "") .. SpellAfter(icon, name)
                    .. Partials(info, not db.inBlocked)
                self:Emit(self:Area("InDamage"), text, color or C.inDamage,
                    { crit = info.crit or info.crushing, amount = info.amount })
            end
            return true
        elseif (mine or pet) and not info.split then
            self:CountFight("damage", info.amount)
            self:CountSpell(petTag .. (info.spell or L["Auto attack"]), info.amount, info.crit, false,
                spellIcon)
            if pet and not db.outPet then return true end
            if mine and (info.melee or self:IsRangedName(info.spell)) and not db.outSwings then return true end
            if info.periodic and not db.outTicks then return true end
            -- (a readable line of a damage shield of yours: "Damage shields" off hides it too)
            if info.event == "DAMAGE_SHIELD" and not db.outShields then return true end
            if not db.outDamage or info.amount < db.minDamage then return true end
            local rule = self:SpellRule(info.spell)
            if rule and rule.hide then return true end
            if self:BigCrit(info.crit, info.amount) and db.soundCrit then self:PlayAlert("crit") end
            local color = (rule and rule.color) or (info.spell and (self:SchoolColor(info.unit) or C.spell)) or C.melee
            self:Emit(self:Area("OutDamage"), outPre .. Commas(info.amount) .. outPost .. Partials(info), color, {
                crit = info.crit,
                key = (pet and "pet:" or "") .. (info.periodic and "tick:" or "") .. (info.spellId or info.spell or "melee"),
                amount = info.amount,
                window = info.periodic and db.tickMerge or nil,
                guid = info.destGUID,
                format = function(total, count)
                    return outPre .. Commas(total) .. outPost .. " |cffb0b0b0(x" .. count .. ")|r"
                end,
            })
            return true
        end
    elseif info.kind == "heal" then
        if not info.amount then return false end
        local over = (db.healOver and info.overheal) and (" |cffb0b0b0(" .. L["%s over"]:format(Commas(info.overheal)) .. ")|r") or ""
        local nothing = info.amount == 0 and info.overheal   -- all of it was overhealing
        local rule = (mine or pet) and self:SpellRule(info.spell) or nil
        local healColor = rule and rule.color or C.heal
        if info.toMe then
            if mine then
                self:NoteSelfHeal(info.amount, info.overheal)
                self:CountFight("heal", info.amount)
                self:CountSpell(info.spell or L["Unnamed heal"], info.amount, info.crit, true, spellIcon)
            elseif not pet then
                self:NoteLogIncoming("heal")   -- (your pet's heal on you comes with "My actions" + Pet)
            end
            if nothing or not self:HealShown(info.amount) or (rule and rule.hide) then return true end
            if db.inHeals then
                self:Emit(self:HealArea("incoming"), "+" .. Commas(info.amount) .. SpellAfter(icon, name) .. over,
                    healColor, { crit = info.crit, amount = info.amount })
            elseif mine and db.outHeals then
                self:Emit(self:HealArea("outgoing"), outPre .. "+" .. Commas(info.amount) .. outPost .. over, healColor,
                    { crit = info.crit, amount = info.amount })
            end
            return true
        elseif mine or pet then
            self:CountFight("heal", info.amount)
            self:CountSpell(petTag .. (info.spell or L["Unnamed heal"]), info.amount, info.crit, true,
                spellIcon)
            if pet and not db.outPet then return true end
            if rule and rule.hide then return true end
            if db.outHeals and not nothing and self:HealShown(info.amount) then
                -- Who you healed, as on the heals that come without a line (Show who you healed)
                local who = mine and self:HealedName(self:UnitFromGUID(info.destGUID)) or ""
                self:Emit(self:HealArea("outgoing"), outPre .. "+" .. Commas(info.amount) .. outPost .. who .. over, healColor,
                    { crit = info.crit, amount = info.amount })
            end
            return true
        end
    elseif info.kind == "miss" then
        local word = MissText(info.missType)
        if info.toMe then
            if not mine then self:NoteLogIncoming("miss") end
            if db.inMisses and not mine then
                self:Emit(self:Area("InMisses"), word .. SpellAfter(icon, name), C.inAvoid)
            end
            return true
        elseif mine or pet then
            if mine and info.missType == "DODGE" then self:React("dodged") end   -- (Overpower)
            if pet and not db.outPet then return true end
            if mine and (info.melee or self:IsRangedName(info.spell)) and not db.outSwings then return true end
            local rule = self:SpellRule(info.spell)
            if rule and rule.hide then return true end
            if db.outMisses then self:Emit(self:Area("OutMisses"), outPre .. word .. outPost, C.miss, { guid = info.destGUID }) end
            return true
        end
    elseif info.kind == "energize" then
        if not info.amount then return false end
        if info.toMe then
            self:NoteLogIncoming("power")
            self:LifeTapLogged()
            if db.inPower then
                self:Emit(self:Area("InPower"), "+" .. Commas(info.amount) .. (info.unit and (" " .. info.unit) or ""), C.power)
            end
            return true
        end
    elseif info.kind == "dispel" then
        return self:ShowDispel(info, mine, pet)
    elseif info.kind == "kill" then
        if mine then
            if db.soundKill then self:PlayAlert("kill") end
            if db.nKill then self:Notify(L["Killing blow!"], C.combat, { crit = true }) end
            return true
        end
    end
    return false
end

-- Your own heals on yourself come both from the log (with the spell's name) and
-- from UNIT_COMBAT. Each log heal is kept a moment, with its amount, so that the
-- same heal from UNIT_COMBAT isn't shown again, and only that one: someone
-- else's heal landing at the same moment still shows.
function BT:NoteSelfHeal(amount, overheal)
    local list = self.selfHeals or {}
    self.selfHeals = list
    local now = GetTime()
    while list[1] and now - list[1].time > 0.6 do table.remove(list, 1) end
    list[#list + 1] = { time = now, amount = Num(amount), total = (Num(amount) or 0) + (Num(overheal) or 0) }
end

function BT:TakeSelfHeal(n)
    local list = self.selfHeals
    if not list then return false end
    local now = GetTime()
    while list[1] and now - list[1].time > 0.6 do table.remove(list, 1) end
    for i, heal in ipairs(list) do
        -- (an amount the game hides can't be compared: then any of yours just now is it)
        if n == nil or heal.amount == nil or heal.amount == n or heal.total == n then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- A heal you cast that lands on you. UNIT_COMBAT's heal on you has no spell name, but your
-- cast finishes in the same moment (either one first). A helpful spell (not a seal or a buff
-- on yourself) cast while your target isn't a friend (so it lands on you) is kept a moment;
-- a heal on you within HEAL_CAST_TIME of it is that spell's. A heal over time that also heals
-- as it lands (Regrowth) leaves a buff, so it's learned as one (SeenBuffs), but it's a heal.
local HEAL_CAST_TIME = 0.3
function BT:NoteHealCast(id, name)
    -- (the server's own cast of the same name, just after Holy Shock's: the same one)
    local was = self.healCast
    if was and was.name == name and GetTime() - was.at < 0.05 then return end
    self.healCast = nil
    if not (id and name and C_Spell and C_Spell.IsSpellHelpful) then return end
    local ok, helpful = pcall(C_Spell.IsSpellHelpful, id)
    local either = self:HealsOrHarms(name)   -- (Holy Shock: on an enemy it hurts, else it heals you)
    if either and not self:HealGoesToTarget() and Flag(UnitCanAttack, "player", "target") then return end
    if self:IsVigil(name) or self:IsMending(name) then return end   -- (Light's Vigil and Prayer of Mending heal nothing as cast)
    if not either and (not ok or IsSecret(helpful) or helpful ~= true) then return end
    local seals = self:SealLists()
    local hot = (self:SpellLists())[name]
    local healsNow = hot ~= nil and hot.heal and hot.direct
    if seals[name] or (not healsNow and self:IsSelfBuffCast(id, name)) then return end
    if self:HealGoesToTarget() then return end   -- on a friend that isn't you, it went to them
    self.healCast = { id = id, name = name, at = GetTime() }
end

-- Whether you can heal a unit: a vendor, a quest giver or a critter can't be healed (the game casts it on you instead)
local function CanHelp(unit)
    if UnitCanAssist then return Flag(UnitCanAssist, "player", unit) end
    return Flag(UnitExists, unit) and not Flag(UnitCanAttack, "player", unit)
end

-- Who your cast is going to. UNIT_SPELLCAST_SENT names them (by name, as you press the key), so a
-- heal cast with a mouseover macro or a click on a party frame is known to be on that friend, not
-- your target (CurseForge: a priest's Renew, Penance and Prayer of Mending on party members cast
-- that way never showed). The unit is worked out there and then: the mouse has moved on by the
-- time a cast finishes. Your target is looked at first, then the mouse, your focus, you, the group.
local SENT_TIME = 6   -- seconds a cast's destination is kept (the longest cast, with pushback)
local SENT_UNITS = { "target", "mouseover", "focus", "player" }
for i = 1, 4 do SENT_UNITS[#SENT_UNITS + 1] = "party" .. i end
for i = 1, 40 do SENT_UNITS[#SENT_UNITS + 1] = "raid" .. i end
-- A token that still means the same unit when the cast finishes: you, or a party or raid member
local function LastingUnit(unit)
    if unit ~= "mouseover" and unit ~= "focus" then return unit end
    if Flag(UnitIsUnit, unit, "player") then return "player" end
    for i = 5, #SENT_UNITS do
        local u = SENT_UNITS[i]
        if Flag(UnitIsUnit, unit, u) then return u end
    end
    return unit
end
function BT:OnSpellSent(target, spellId)
    local id, name = Num(spellId), nil
    self.sent = nil
    if id and C_Spell and C_Spell.GetSpellName then   -- (SpellName comes further down)
        local ok, n = pcall(C_Spell.GetSpellName, id)
        name = ok and Str(n) or nil
    end
    self:NoteHelpfulCast(id, name)   -- (as the key is pressed: before the heal can land)
    local unit
    local hidden = IsSecret(target)   -- (the game hides the name, or every unit's name it could be)
    local who = Str(target)
    local shape = hidden and "hidden" or nil   -- (what the name looked like, for the debug log)
    if who then
        if who == "" then return end   -- (a spell with no one to go to: as before)
        local plain = who:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local short = (plain:match("^([^%-]+)%-") or plain):lower()
        local isGUID = plain:match("^%a+%-%d+%-") ~= nil
        shape = isGUID and "a GUID" or (plain:find("-", 1, true) and "a name-realm" or "a name")
        for _, u in ipairs(SENT_UNITS) do
            if Flag(UnitExists, u) then
                if isGUID then
                    local ok, g = pcall(UnitGUID, u)
                    if ok and Str(g) == plain then unit = u break end
                else
                    local ok, n, realm = pcall(UnitName, u)
                    if ok and IsSecret(n) then hidden = true end
                    n = ok and Str(n) or nil
                    realm = ok and Str(realm) or nil
                    if n then
                        local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
                        local nShort = (n:match("^([^%-]+)%-") or n):lower()
                        if n == plain or full == plain or nShort == short then unit = u break end
                    end
                end
            end
        end
    end
    local mouse = CanHelp("mouseover") and not Flag(UnitIsUnit, "mouseover", "player")
    local friendTargeted = Flag(UnitExists, "target") and CanHelp("target")
    if not unit then
        -- Not known by its name: in a dungeon the game hides the names (GitHub #29, 1.38.1), and in
        -- the open world a player's SENT names matched no one either (1.38.2: "no name match" on
        -- every cast, even on themselves). A friend under the mouse while your target isn't one is
        -- who a mouseover cast is on ([@mouseover,help] comes first in such a macro). With a friend
        -- targeted, it can't be told: your target, as before.
        if mouse and not friendTargeted then unit = "mouseover" end
    end
    if self.db.debug then
        local why = ""
        if not unit then   -- (why not: for the next log)
            why = " (" .. (hidden and "names hidden" or "no name match") .. ", mouse "
                .. (mouse and "on a friend" or "not on a friend") .. ", target "
                .. (friendTargeted and "a friend" or "not a friend") .. ")"
        end
        self:Record("SENT " .. tostring(id) .. " to " .. tostring(unit or "?") .. why
            .. (shape and (" [sent " .. shape .. "]") or ""))
    end
    if not unit then return end
    local ok, guid = pcall(UnitGUID, unit)
    self.sent = { at = GetTime(), id = id, name = name, unit = LastingUnit(unit), guid = ok and Str(guid) or nil,
        me = Flag(UnitIsUnit, unit, "player"), help = CanHelp(unit) }
end

-- Your cast of this spell, just now: where UNIT_SPELLCAST_SENT said it went (nil: not known).
-- Kept for the frame (CastTo), so everything asked while the cast is worked out gets the same answer.
function BT:CastTo(id, name)
    local s = self.sent
    local now = GetTime()
    if s and now - s.at <= SENT_TIME and ((id and s.id == id) or (name and s.name == name)) then
        self.dest = { at = now, sent = s }
    else
        self.dest = nil
    end
end

-- Who a helpful spell you cast just now went to: "player", or a friend's unit (and what SENT said)
function BT:HelpedUnit()
    local d = self.dest
    if d and d.at == GetTime() then
        local s = d.sent
        if s.me then return "player", s end
        if s.help then return s.unit, s end
        -- (sent to an enemy: as below)
    end
    if not Flag(UnitExists, "target") or Flag(UnitIsUnit, "target", "player") then return "player" end
    if CanHelp("target") then return "target" end
    return "player"
end

-- A helpful spell goes to a friend that isn't you (your target, or the one under the mouse); else it's on you
function BT:HealGoesToTarget()
    return self:HelpedUnit() ~= "player"
end

-- What to know the friend your helpful cast went to by (as UnitKey has it)
function BT:HelpedKey()
    local unit, s = self:HelpedUnit()
    if s and s.guid then return s.guid end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and Str(guid) or nil
    if guid then return guid end
    if unit == "target" or Flag(UnitIsUnit, unit, "target") then return "target" end
    return nil
end

-- A tick of a heal over time you put on yourself (Rejuvenation, Renew): a heal on you on its
-- beat (a whole number of periods since the cast, give or take TICK_SLACK), within SELF_HOT_TIME
-- of the cast. A heal of another magic school isn't it (a paladin's Holy Light); one with no
-- school or Physical may be: the game doesn't always give a heal its spell's school (a player's
-- debug log: Regrowth and Rejuvenation ticks on their beats, left unnamed). The same goes for
-- heals on others (TickFor, AreaFor).
local SELF_HOT_TIME = 25
local function SameHealSchool(school, hotSchool)
    return not school or school == hotSchool or school <= 1
end
function BT:SelfHotFor(at, school)
    local best, bestOff
    for name, hot in pairs(self.selfHots or {}) do
        local since = at - hot.at
        if since > SELF_HOT_TIME then
            self.selfHots[name] = nil
        else
            local beats = math.floor(since / hot.period + 0.5)
            local off = math.abs(since - beats * hot.period)
            if beats >= 1 and off <= 0.25 and SameHealSchool(school, hot.school) and (not best or off < bestOff) then
                best, bestOff = hot, off
            end
        end
    end
    return best
end

-- Thrill of Adventure (a Forever talent, Tyler's tooltip, 1.40.4): "You gain 2% of your maximum
-- Health and Mana over 10 sec each time you deliver the killing blow to a non-trivial enemy.
-- Ineffective in dungeons, raids, and battlegrounds." Its heals come on you with no cast and no
-- name, 2s apart, five in all, the first about 2s after the kill (Tyler's druid logs, 1.40.3:
-- Rake killed at 194.23, heals at 196.26, 198.22, 200.27, 202.32, 204.33; 1.40.4: the first 1.06s
-- and 1.25s after the killing hit, so it's 0.8s at the least). The killing blow
-- can't be read, so the first heal must come THRILL_FIRST after a hit of yours on a mob
-- (NoteFought), the rest on its beat. Not in dungeons, raids and battlegrounds.
local THRILL_FIRST_LEAST, THRILL_FIRST_MOST = 0.8, 2.7
local THRILL_PERIOD, THRILL_SLACK, THRILL_TICKS = 2, 0.35, 5
function BT:ThrillFor(at, school)
    if school and school > 1 then return nil end
    local okIn, inside, kind = pcall(IsInInstance)
    if okIn and not IsSecret(inside) and inside and (kind == "party" or kind == "raid" or kind == "pvp"
            or kind == "arena") then
        return nil
    end
    -- (no spell ID known for it yet: the icon is looked up by its English name)
    local spell = { id = "Thrill of Adventure", name = L["Thrill of Adventure"] }
    local t = self.thrill
    if t and t.ticks < THRILL_TICKS then
        local off = at - t.last - THRILL_PERIOD
        if math.abs(off) <= THRILL_SLACK then
            t.ticks, t.last = t.ticks + 1, at
            return spell
        end
    end
    for _, hitAt in pairs(self.fought or {}) do
        local since = at - hitAt
        if since >= THRILL_FIRST_LEAST and since <= THRILL_FIRST_MOST then
            self.thrill = { ticks = 1, last = at }
            return spell
        end
    end
    return nil
end

function BT:TakeHealCast(at)
    local cast = self.healCast
    if cast and math.abs(cast.at - at) <= HEAL_CAST_TIME then
        self.healCast = nil
        return cast
    end
    return nil
end

-- UNIT_COMBAT for yourself: damage, heals and power you take, with no spell
-- names. Used for whatever the combat log isn't delivering.
-- (Not for a druid: UNIT_COMBAT doesn't say which power, and a druid's changes with the
-- form: mana gained in cat form was called energy.)
-- A Protection paladin's Shield Specialization (Wowhead Forever 20150, 1.60.1): a block gives back
-- 4% of your mana, at most once every 3 seconds. The game sends the mana with no spell, a moment
-- before or after the block, so with the talent a mana gain waits SHIELD_SPEC_WAIT to see a block
-- within SHIELD_SPEC_NEAR of it. (CurseForge: "mana on block?")
-- On Forever the game sends nothing at all for this mana (Tyler's paladin log, 1.41.0: blocks, no
-- UNIT_COMBAT ENERGIZE and no combat log line near any of them), so the block itself shows it,
-- SHIELD_SPEC_LOOK after it (ShieldSpecBlock).
local SHIELD_SPEC = { 20150, "Shield Specialization" }
local SHIELD_SPEC_WAIT, SHIELD_SPEC_NEAR, SHIELD_SPEC_EVERY = 0.2, 0.3, 2.9
local SHIELD_SPEC_LOOK, SHIELD_SPEC_SHARE = 0.4, 0.04

function BT:HasShieldSpec()
    local okClass, _, class = pcall(UnitClass, "player")
    if not okClass or Str(class) ~= "PALADIN" then return false end
    return self.KnowsSpell and self:KnowsSpell(SHIELD_SPEC[1]) or false
end

-- Whether mana that came at `at` was Shield Specialization's: a block of yours close to it, and
-- not within 3 seconds of the last one it gave
function BT:ShieldSpecFor(at)
    local block = self.lastBlock
    if not block or math.abs(block - at) > SHIELD_SPEC_NEAR then return false end
    if self.shieldSpecAt and at - self.shieldSpecAt < SHIELD_SPEC_EVERY then return false end
    self.shieldSpecAt = at
    return true
end

local function PowerName()
    if not UnitPowerType then return nil end
    local okClass, _, class = pcall(UnitClass, "player")
    if not okClass or Str(class) == "DRUID" then return nil end
    local ok, _, token = pcall(UnitPowerType, "player")
    token = ok and Str(token) or nil
    return token and Str(_G[token]) or nil
end

-- " <icon> Shield Specialization" after a mana gain, or nil when a spell rule hides it
function BT:ShieldSpecAfter()
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, SHIELD_SPEC[1])
        name = ok and Str(n) or nil
    end
    name = name or SHIELD_SPEC[2]
    local rule = self:SpellRule(name)
    if rule and rule.hide then return nil end
    return SpellAfter(self:SpellParts("in", self:IconText(SHIELD_SPEC[1]), name))
end

-- A block of yours, with the talent: the mana it gave. The bar's rise when your mana can be read
-- (nothing when it didn't rise: it was full, or rank 1's 50% chance missed). When the game hides
-- your mana, 4% of your most mana, or "+4%" when that's hidden too. The game's own line for it
-- (UNIT_COMBAT ENERGIZE, OnUnitCombat) shows it instead, if one ever comes.
function BT:ShieldSpecBlock(at)
    if not self:HasShieldSpec() then return end
    local ManaNow = S.ManaNow
    local before, most
    if ManaNow then before, most = ManaNow() end
    local recent = self.shieldSpecAt and at - self.shieldSpecAt < SHIELD_SPEC_EVERY
    if self.db.debug then
        self:Record("SHIELD SPEC block: mana " .. (before and (before .. "/" .. tostring(most)) or "hidden")
            .. (recent and " (within 3s of the last)" or ""))
    end
    if recent or not (C_Timer and C_Timer.After) then return end
    C_Timer.After(SHIELD_SPEC_LOOK, function()
        local sent = BT.energizeAt and math.abs(BT.energizeAt - at) <= SHIELD_SPEC_NEAR
        if sent or (BT.shieldSpecAt and at - BT.shieldSpecAt < SHIELD_SPEC_EVERY) then return end
        local now, top
        if ManaNow then now, top = ManaNow() end
        local gain
        if before and now then
            gain = now - before
            -- (the bar can rise a moment before the block's event)
            local rise = BT.manaRise
            if gain <= 0 and rise and rise.at <= at and at - rise.at <= SHIELD_SPEC_NEAR then gain = rise.amount end
            if gain <= 0 then
                if BT.db.debug then BT:Record("SHIELD SPEC: no mana came (full, or the chance missed)", at) end
                return
            end
        end
        BT.shieldSpecAt = at
        local gave = gain or ((top or most) and math.floor((top or most) * SHIELD_SPEC_SHARE))
        if BT.db.debug then
            BT:Record("SHIELD SPEC: +" .. (gave and tostring(gave) or "4%")
                .. (gain and " (the bar rose)" or " (mana hidden: 4% of the most)"), at)
        end
        if not BT.db.inPower or BT:LogCovers("power") then return end
        local after = BT:ShieldSpecAfter()
        if not after then return end
        local power = PowerName()
        power = power and (" " .. power) or ""
        local text = gave and gave > 0 and ("+" .. Commas(gave)) or "+4%"
        BT:Emit(BT:Area("InPower"), text .. power .. after, BT.TEXT_COLORS.power)
    end)
end

function BT:OnUnitCombat(unit, action, flag, amount, school)
    unit = Str(unit)
    if not unit then return end
    if unit ~= "player" then return self:OnUnitHit(unit, action, flag, amount, school) end
    action, flag = Str(action), Str(flag)
    if self.db.debug then
        self:Record("UNIT_COMBAT player " .. tostring(action) .. " " .. tostring(flag) .. " "
            .. (IsSecret(amount) and "(hidden amount)" or tostring(amount))
            .. " school " .. (IsSecret(school) and "(hidden)" or tostring(school)))
    end
    if not action then return end
    if action == "WOUND" and self:GearHurtsYou(school) then
        -- Your own gear's hit on you (Thorncursed Grips: 2 Nature to you with each weapon blow), not
        -- a mob's blow: your shields don't answer it. Until 1.28.4 it counted as one, so the Grips'
        -- own hit on the mob in that moment was named Lightning Shield (GitHub #25, a shaman's log).
        local now = GetTime()
        local g = self.gearSelf
        if g and g.at == now and g.school == Num(school) then g.n = g.n + 1
        else self.gearSelf = { at = now, school = Num(school), n = 1, used = 0 } end
    elseif action == "WOUND" then
        self:ConfirmShield(GetTime())
        self.lastBlow = GetTime()
        self:NoteBlow(GetTime())
        self:BlowLanded(GetTime())
    end
    -- You dodged, parried or blocked (a warrior's Revenge, a rogue's Riposte), a blow you
    -- partly blocked too
    local avoid = action == "WOUND" and flag or action
    if avoid == "DODGE" or avoid == "PARRY" or avoid == "BLOCK" or avoid == "BLOCK_REDUCED" then
        if avoid == "BLOCK" or avoid == "BLOCK_REDUCED" then
            self.lastBlock = GetTime()
            self:ShieldSpecBlock(GetTime())
        end
        self:React("avoided")
        if avoid == "PARRY" then self:React("parried") end
    end
    local db, C = self.db, self.TEXT_COLORS
    local crit = flag == "CRITICAL" or flag == "CRUSHING"
    local secret = IsSecret(amount)
    local n = Num(amount)
    if action == "WOUND" then
        if secret or (n and n > 0) then
            self:Queue({ blow = true })   -- (a blow that landed: see the hit for nothing, below)
            if self:LogCovers("damage") or not db.inDamage then return end
            -- Partly blocked: the game says so (BLOCK_REDUCED) but not by how much
            local note = (flag == "BLOCK_REDUCED" and db.inBlocked) and " |cffb0b0b0(" .. BT:HitNote("blocked") .. ")|r" or ""
            local color, word = self:IncomingSchool(nil, school)
            color, word = color or C.inDamage, word or ""
            if secret then
                self:Emit(self:Area("InDamage"), "-", color, { crit = crit, secret = amount,
                    after = (word .. note) ~= "" and (word .. note) or nil })
            else
                self:Emit(self:Area("InDamage"), "-" .. Commas(n) .. word .. note, color, { crit = crit, amount = n })
            end
        else
            -- No damage: fully absorbed, blocked or resisted, or a plain miss
            if self:LogCovers("miss") or not db.inMisses then return end
            if flag and MISS_TEXT[flag] then
                self:Emit(self:Area("InMisses"), MissText(flag), C.inAvoid)
            else
                -- Some attacks arrive in two parts, one of them for nothing (a mob's special
                -- attack: "WOUND 0" and "WOUND 33" in one frame). That's no miss: it's shown
                -- as one only if no blow landed on you in the same frame (ResolveFrame).
                self:Queue({ nothing = true })
            end
        end
    elseif action == "HEAL" then
        local at = GetTime()
        self:GraveHealLanded(at, Num(school))   -- (Touch of the Grave's hit on the mob comes with it)
        if self:LogCovers("heal") then return end
        -- Your own heals on yourself also come from the combat log, with the
        -- spell's name. Wait a moment to see whether this is one of those.
        -- (Even with "Heals you get" off: a heal of yours still counts in the fight.)
        local function show()
            if BT:TakeSelfHeal(n) then return end   -- the log's line showed it, with the spell's name
            if BT:LogDelivers("heal") then return end   -- the log's line for it arrived meanwhile
            -- Touch of the Grave's (its hit just named), or a heal you cast on yourself just
            -- then (Holy Light): named after it
            -- (Light's Vigil's heal, set off by your Holy Shock: the first heal on you is the Holy Shock's
            -- when you Holy Shocked yourself)
            local cast = BT:GraveHealFor(at) or BT:VigilOnYou(at) or BT:TakeHealCast(at) or BT:SelfHotFor(at, Num(school))
                or BT:SelfAreaFor(at, Num(school)) or BT:ThrillFor(at, Num(school))
            if BT.db.debug then BT:Record("  player heal: " .. (cast and ("named " .. tostring(cast.name)) or "no cast of yours with it"), at) end
            local after, color = "", C.heal
            if cast then
                local rule = BT:SpellRule(cast.name)
                if n and n > 0 then   -- counted before any setting hides it, as everywhere else
                    BT:CountFight("heal", n)
                    BT:CountSpell(cast.name, n, crit, true, BT:IconText(cast.id))
                end
                if not BT.db.inHeals or (rule and rule.hide) then return end
                if rule and rule.color then color = rule.color end
                after = SpellAfter(BT:SpellParts("heal", BT:IconText(cast.id), cast.name))
            elseif not BT.db.inHeals or not BT.db.inOtherHeals then
                return   -- (its number is often hidden, so "Hide heals below" can't catch it)
            end
            if secret then
                BT:Emit(BT:HealArea("incoming"), "+", color, { crit = crit, secret = amount, after = after })
            elseif n and n > 0 and BT:HealShown(n) then
                BT:Emit(BT:HealArea("incoming"), "+" .. Commas(n) .. after, color, { crit = crit, amount = n })
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.25, show) else show() end
    elseif action == "ENERGIZE" then
        self:LifeTapLogged()
        self.energizeAt = GetTime()   -- (a block's Shield Specialization mana is this, then)
        if self:LogCovers("power") or not db.inPower then return end
        local power = PowerName()
        power = power and (" " .. power) or ""
        local at = GetTime()
        local function show()
            local after = power
            if self:ShieldSpecFor(at) then
                local spec = self:ShieldSpecAfter()
                if not spec then return end
                after = power .. spec
            end
            if secret then
                -- The amount goes last, so the game can fill it in
                self:Emit(self:Area("InPower"), "+", C.power, { secret = amount, after = after })
            elseif n and n > 0 then
                self:Emit(self:Area("InPower"), "+" .. Commas(n) .. after, C.power)
            end
        end
        -- (the block can come just after the mana: wait a moment, only with the talent)
        if self:HasShieldSpec() and C_Timer and C_Timer.After then
            C_Timer.After(SHIELD_SPEC_WAIT, show)
        else
            show()
        end
    elseif MISS_TEXT[action] then
        if self:LogCovers("miss") or not db.inMisses then return end
        self:Emit(self:Area("InMisses"), MissText(action), C.inAvoid)
    end
end

-- Shared with the files loaded after this one
S.SameHealSchool, S.SpellAfter, S.MISS_TEXT, S.MissText, S.UnnamedHit, S.HEAL_CAST_TIME = SameHealSchool, SpellAfter, MISS_TEXT, MissText, UnnamedHit, HEAL_CAST_TIME
