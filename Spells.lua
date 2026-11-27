-- BattleText Forever: the spell lists, seals and your buffs.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, IsSecret, Num, Str, Flag, IsEnglish = S.BT, S.IsSecret, S.Num, S.Str, S.Flag, S.IsEnglish
local SameHealSchool = S.SameHealSchool

---------------------------------------------------------------------------
-- What you do to other units
--
-- The game hides the text of its combat log lines from addons when it likes:
-- the line arrives as a "|K...|k" token, which can be shown but not read. So
-- your hits are read from UNIT_COMBAT on the unit they land on (your target,
-- a mob with a nameplate, a party member): the amount, crit and school are
-- there, but not who did it, nor with which spell.
--
-- Everything that arrives in one frame (hidden lines, your casts, hits) is
-- kept in order in self.seq and worked out together once the frame is over
-- (ResolveFrame): what comes before and after a hit says what it was.
---------------------------------------------------------------------------
local CREDIT_TIME = 1.2   -- a hit can follow its combat log line by this long (a swing lands with its animation)
local LINE_WITH_HIT = 0.15  -- a line this close before a hit is its own (spells, ticks, procs, heals: in its frame or just ahead)
local SWING_RECENT = 6      -- PLAYER_SWING this recent: your swings are vouched for by it, not by their lines
-- An extra attack (Windfury) lands this soon after the blow that gave it. GitHub #25 (1.29.0, a
-- shaman's log): Stormstrike and a swing together, the swing's hit 0.4s later, Windfury's two
-- hits 0.36s and 0.94s after that one. Until 1.29.1 it was 0.8, and the second was left out.
local EXTRA_TIME = 1.1
local EXTRA_HITS = 2        -- and a blow gives at most this many
local TICK_SLACK = 0.25   -- a tick can be this far off its beat
local TICK_CLOSE = 0.15   -- and once it has ticked, the next is about this close to its beat (against a spell landing)
local DOT_TIME = 45       -- a damage-over-time spell is forgotten this long after its cast
local UNNAMED_KEEP = 8    -- an unnamed hit of yours is kept this long (OnUnnamedBeat)
local BEAT_LEAST, BEAT_MOST = 1.5, 3.5   -- the periods an unknown tick's beat can have
local FLAG_NOTES = { GLANCING = "glancing", BLOCK = "blocked", BLOCK_REDUCED = "blocked", ABSORB = "absorbed",
    RESIST = "resisted" }

-- Spells that keep hurting (or healing) after the cast: { first rank's ID, English
-- name, seconds between ticks, school, whether the cast itself also hits, whether
-- it heals }. The ID gives the name in the game's language; every rank shares the name.
local PERIODIC_SPELLS = {
    { 1822, "Rake", 3, 1, true }, { 1079, "Rip", 2, 1 }, { 9005, "Pounce", 3, 1 },
    { 8921, "Moonfire", 3, 64, true }, { 5570, "Insect Swarm", 2, 8 }, { 339, "Entangling Roots", 3, 8 },
    { 772, "Rend", 3, 1 }, { 703, "Garrote", 3, 1 }, { 1943, "Rupture", 2, 1 },
    { 1978, "Serpent Sting", 3, 8 },
    { 172, "Corruption", 3, 32 }, { 348, "Immolate", 3, 4, true }, { 980, "Bane of Agony", 2, 32 },
    { 18265, "Siphon Life", 3, 32 },
    { 589, "Shadow Word: Pain", 3, 32 }, { 2944, "Devouring Plague", 3, 32 }, { 14914, "Holy Fire", 2, 2, true },
    { 8050, "Flame Shock", 3, 4, true },
    { 774, "Rejuvenation", 3, 8, false, true }, { 8936, "Regrowth", 3, 8, true, true }, { 139, "Renew", 3, 2, false, true },
}
-- Damage over time put on by something that flies (a hunter's sting is a shot): its ticks are
-- timed from when it lands, up to STING_FLIGHT after the cast (CurseForge, 1.24.1: Serpent
-- Sting's ticks were off the beat counted from the cast, and showed with no name or icon)
local FLYING_DOTS = { [1978] = true }
-- Damage over time whose ticks the game sends no "My actions" line for, by the first rank's ID:
-- how long it lasts. Rip (GitHub, a ptBR druid's /btf debug: each Rake tick has its hidden line
-- right behind it, Rip's six ticks have none) went unnamed as "no line of yours with it". Its beat
-- vouches for it instead, as many ticks as it has (lasts / period), only within that time.
-- Rake (Tyler's druid log, 1.40.2: its three ticks, 3s apart, came with no line while Thorns'
-- lines kept coming, and showed as plain white hits) is on the list too: on a game where its
-- ticks do have their lines, two ticks named by their lines take it off (BT.tickLines).
local NO_LINE_DOTS = { [1079] = 12, [1822] = 9 }
local LINE_UNSURE_DOTS = { [1822] = true }
local STING_FLIGHT = 1.5
-- Attacks on your next swing, which replace it: { first rank's ID, English name }
local NEXT_SWING_SPELLS = {
    { 6807, "Maul" }, { 78, "Heroic Strike" }, { 845, "Cleave" }, { 2973, "Raptor Strike" },
}
-- Buffs on you that hurt whoever hits you: { first rank's ID, English name, school }
local SHIELD_SPELLS = {
    { 467, "Thorns", 8 }, { 324, "Lightning Shield", 8 }, { 7294, "Retribution Aura", 2 }, { 2947, "Fire Shield", 4 },
}

-- A paladin's seals: { first rank's ID, English name, school of the damage it adds
-- to your swings (none for the seals that don't hurt) }. On Forever Judgement doesn't use
-- up the seal (players' reports): it stays until its time runs out or another replaces it.
local SEAL_SPELLS = {
    { 21084, "Seal of Righteousness", 2 }, { 20375, "Seal of Command", 2 },
    { 21082, "Seal of the Crusader" }, { 20164, "Seal of Justice" }, { 20165, "Seal of Light" },
    { 20166, "Seal of Wisdom" },
    -- Forever's Seal of Fury (Wowhead Forever 1311649, rank 1 at level 10): Holy damage on each
    -- swing, like Seal of Righteousness. Its hits had no name (CurseForge).
    { 1311649, "Seal of Fury", 2 },
}
local JUDGEMENT = { 20271, "Judgement" }
-- Forever's Retribution talent: your swings store your seal, and a swing under another seal
-- sets the stored one off (Holy, with that swing): { spell ID, English name, school }
local UNSEALED_WRATH = { 1310735, "Unsealed Wrath", 2 }
-- Buffs you cast on yourself, for when the game doesn't say so (C_Spell.IsSelfBuff):
-- { first rank's ID, English name }
local SELF_BUFFS = {
    { 5171, "Slice and Dice" }, { 5277, "Evasion" }, { 2983, "Sprint" }, { 13750, "Adrenaline Rush" },
    { 13877, "Blade Flurry" }, { 1719, "Recklessness" }, { 12292, "Sweeping Strikes" }, { 18499, "Berserker Rage" },
    { 871, "Shield Wall" }, { 5217, "Tiger's Fury" }, { 1850, "Dash" }, { 22812, "Barkskin" },
    { 3045, "Rapid Fire" }, { 12042, "Arcane Power" }, { 12043, "Presence of Mind" }, { 11129, "Combustion" },
    { 498, "Divine Protection" }, { 642, "Divine Shield" }, { 20216, "Divine Favor" },
}
local SEAL_TIME = 30   -- how long a seal lasts, in seconds, until a reading of your buffs says (db.sealTimes)
-- Spells that fly to their target, so they land after the cast: { first rank's ID,
-- English name, school, seconds between ticks of what it leaves burning (if it does) }.
-- Fireball and Pyroblast tick from when they land, not from the cast.
local FLIGHT_SPELLS = {
    { 133, "Fireball", 4, 2 }, { 11366, "Pyroblast", 4, 3 }, { 116, "Frostbolt", 16 },
    { 686, "Shadow Bolt", 32 }, { 6353, "Soul Fire", 4 },
    { 5176, "Wrath", 8 }, { 2912, "Starfire", 64 },
    { 403, "Lightning Bolt", 8 }, { 421, "Chain Lightning", 8 },
    { 24275, "Hammer of Wrath", 2 }, { 3044, "Arcane Shot", 64 },
    -- A hunter's Multi-Shot and Aimed Shot are physical shots: without this their hit had no name,
    -- and counted as an auto attack (hidden with "Auto attacks" off) (CurseForge, feuerbanane)
    { 2643, "Multi-Shot", 1 }, { 19434, "Aimed Shot", 1 },
    { 1326079, "Arcane Wrath", 64 },   -- Forever's own (an Arcane mage's long-cast nuke)
    -- Forever's Frostfire Bolt (Wowhead Forever: 1237313): Frostfire (Fire and Frost, 20), and
    -- it leaves the mob burning for 9 seconds (three ticks)
    { 1237313, "Frostfire Bolt", 20, 3 },
}
local FLIGHT_TIME = 2.5   -- the longest a spell can be on its way (about 40 yards)
-- Forever's Summon Hawk (Beast Mastery talent, 1.60.1; every rank has this name): a hawk dives at
-- your target (a physical hit, named like a spell that flies), then keeps attacking it for
-- HAWK_TIME seconds; two can be out at once. Its hits come with no name: on that mob, an
-- unnamed physical hit that isn't your swing is marked (Hawk) (Tinter on CurseForge).
local HAWK_SPELL = { 1293241, "Summon Hawk" }
local HAWK_TIME = 18
local HAWK_MOST = 2
-- Your ranged attacks, by spell ID (wands and bows both cast "Shoot"): { English name, school }.
-- No school: a wand's, which is its own (any but physical). They fly like spells and count as
-- auto attacks (the "Auto attacks" switch hides them too).
local RANGED_SPELLS = {
    [75] = { "Auto Shot", 1 }, [3018] = { "Shoot", 1 }, [7918] = { "Shoot Gun", 1 },
    [7919] = { "Shoot Crossbow", 1 }, [2764] = { "Throw", 1 }, [5019] = { "Shoot" },
}
-- Your swings' icon: the weapon in your main hand (which hand a swing was can't be told),
-- else the game's Attack
local MAIN_HAND, ATTACK_SPELL = 16, 6603
-- Things you throw or set off from your bags (Engineering's explosives): { the item's spell ID,
-- English name, school }. They land on everything where they go off, which needn't be your
-- target, a moment after the throw (or at once, for a Sapper Charge).
local THROWN_ITEMS = {
    { 4054, "Rough Dynamite", 4 }, { 4061, "Coarse Dynamite", 4 }, { 4062, "Heavy Dynamite", 4 },
    { 12419, "Solid Dynamite", 4 }, { 23063, "Dense Dynamite", 4 },
    { 8331, "Ez-Thro Dynamite", 4 }, { 23000, "Ez-Thro Dynamite II", 4 },
    { 4064, "Rough Copper Bomb", 4 }, { 4065, "Large Copper Bomb", 4 }, { 4066, "Small Bronze Bomb", 4 },
    { 4067, "Big Bronze Bomb", 4 }, { 4068, "Iron Grenade", 4 }, { 4069, "Big Iron Bomb", 4 },
    { 12421, "Mithril Frag Bomb", 4 }, { 12543, "Hi-Explosive Bomb", 4 }, { 12562, "The Big One", 4 },
    { 19769, "Thorium Grenade", 4 }, { 19784, "Dark Iron Bomb", 4 }, { 19821, "Arcane Bomb", 64 },
    { 13241, "Goblin Sapper Charge", 4 },
}
local THROW_TIME = 2.5   -- the longest one can take to go off after the throw
-- Spells that keep hitting for a while after the cast, on every mob in the area or on the one
-- you channel at: { first rank's ID, English name, school, longest it lasts in seconds, how }.
-- how: "channel" (on the mobs where you aim it, until you stop channeling), "single" (a channel
-- on your target only), "heal" (a channel that heals), "either" (a channel on your target that
-- heals a friend and hurts an enemy; with neither targeted it heals you), or none (lasts its
-- time, whatever you do).
local AREA_SPELLS = {
    { 5143, "Arcane Missiles", 64, 5, "single" }, { 15407, "Mind Flay", 32, 3, "single" },
    { 689, "Drain Life", 32, 5, "single" }, { 1120, "Drain Soul", 32, 15, "single" },
    { 10, "Blizzard", 16, 8, "channel" }, { 5740, "Rain of Fire", 4, 8, "channel" },
    { 16914, "Hurricane", 8, 10, "channel" }, { 1510, "Volley", 64, 6, "channel" },
    { 1949, "Hellfire", 4, 15, "channel" }, { 740, "Tranquility", 8, 10, "heal" },
    { 1316697, "Wrack", 32, 6, "single" },
    -- A Night Elf priest's Starshards (Wowhead Forever 10797: Arcane, channeled on your target
    -- for 6 seconds); its ticks had no name (CurseForge)
    { 10797, "Starshards", 64, 6, "single" },
    -- Forever's Penance (issue #29: cast as 402174 and 402289 together, its first heal 0.3s later)
    { 402174, "Penance", 2, 3, "either" },
    { 26573, "Consecration", 2, 8 }, { 2120, "Flamestrike", 4, 8 },
    { 8190, "Magma Totem", 4, 20 }, { 1535, "Fire Nova Totem", 4, 6 }, { 3599, "Searing Totem", 4, 55 },
}
-- Forever's Wrack (Affliction talent, 1.60.1): while you channel it, your Corruption, Bane of
-- Agony and Siphon Life on that mob tick twice as fast (first rank's IDs)
local WRACK_ID = 1316697
local WRACK_SPEEDS = { [172] = true, [980] = true, [18265] = true }
local AREA_SLACK = 1   -- what's still on its way when a channel stops (Arcane Missiles) lands this late
-- Abilities you can use only just after something happens: { first rank's ID, English
-- name, class, what opens it, level it's learned at (none: a talent) }. What opens it:
-- "dodged" your target dodged you; "avoided" you dodged, parried or blocked; "parried" you parried;
-- "usable" the game says it can be cast (Execute, Hammer of Wrath: the target is low on health).
local REACTIVE_SPELLS = {
    { 7384, "Overpower", "WARRIOR", "dodged", 12 },
    { 6572, "Revenge", "WARRIOR", "avoided", 14, { 71 } },   -- (only in Defensive Stance)
    { 14251, "Riposte", "ROGUE", "parried" },
    { 19306, "Counterattack", "HUNTER", "parried" },
    { 5308, "Execute", "WARRIOR", "usable", 24 },
    { 24275, "Hammer of Wrath", "PALADIN", "usable", 44 },
}
local REACT_GAP = 1   -- seconds before the same alert shows again
-- REACTIVE_SPELLS' sixth: the stances (by their spell) it can be used in; the alert only shows in
-- one of them. Revenge only: an Arms warrior in Battle Stance got "Revenge!" on every parry
-- (CurseForge, Quarnok). Overpower has none, as warriors often switch to Battle Stance for it.

-- Spells that take something off (first rank's ID, English name). Only for when
-- the Combat Log's dispel lines aren't arriving: then the cast itself shows.
-- Abolish Poison and Abolish Disease aren't here: their cast is a buff, and what
-- they take off comes later.
local DISPEL_SPELLS = {
    { 4987, "Cleanse" }, { 1152, "Purify" }, { 2782, "Remove Curse" }, { 475, "Remove Lesser Curse" },
    { 8946, "Cure Poison" }, { 526, "Cure Poison" }, { 2870, "Cure Disease" }, { 528, "Cure Disease" },
    { 527, "Dispel Magic" }, { 370, "Purge" }, { 19801, "Tranquilizing Shot" },
}
local DISPEL_WAIT = 0.5   -- seconds a cast waits for its dispel line before showing on its own

-- Spells that heal a friend or hurt an enemy, whichever you cast them on: { spell ID, English name }.
-- Forever's Holy Shock (rank 1 is new: 1311606) has a dummy effect: the server casts the heal itself,
-- as a second spell of the same name, and the heal can land a frame after the cast.
local HEAL_OR_HARM = {
    { 1311606, "Holy Shock" }, { 20473, "Holy Shock" }, { 20929, "Holy Shock" }, { 20930, "Holy Shock" },
}
local FRIEND_HEAL_TIME = 0.5   -- seconds after your cast on a friend that its heal may land on them
-- Light's Vigil (Forever's 31-point Holy talent): put on a friend, your next Holy Shock on them also
-- heals them and their party. Its heal has no cast of its own: it comes with that Holy Shock.
local LIGHTS_VIGIL = { 1310911, 1311590, 1311595, name = "Light's Vigil" }
-- Prayer of Mending (33076 as in TBC, 401859 as Season of Discovery's rune; the name is what counts):
-- put on a friend, it heals them when they're hurt, then jumps to another group member, up to
-- MENDING_JUMPS times, waiting up to MENDING_LASTS on each. Its heals come with no cast.
local PRAYER_OF_MENDING = { 33076, 401859, name = "Prayer of Mending" }
local MENDING_LASTS = 30
local MENDING_JUMPS = 5
local VIGIL_LASTS = 30    -- seconds the Vigil waits on its friend for your Holy Shock
local VIGIL_TIME = 0.5    -- seconds after the Holy Shock that the party's heals land
-- Life Tap (warlock): health into mana. The game says nothing of it but the cast (issue #26: no
-- combat log line, no UNIT_COMBAT), so the mana is read off your mana bar (LifeTapCast).
local LIFE_TAP = { 1454, 1455, 1456, 11687, 11688, 11689, name = "Life Tap" }
local LIFE_TAP_TIME = 1.5     -- seconds after the cast that its mana may come in (it comes from the server)
local LIFE_TAP_BEFORE = 0.3   -- or before it: the mana can arrive ahead of the cast's own event
local LIFE_TAP_LOOK = 0.1     -- how often the mana bar is looked at while waiting

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and Str(name) or nil
end

-- The two lists above by spell name, in English and in the game's language.
-- On an English client the ID's name must agree with the list (if this game
-- has given the ID to another spell, it's left out).
function BT:SpellLists()
    if self.periodic then return self.periodic, self.shields end
    local english = IsEnglish()
    local function names(entry)
        local out = { entry[2] }
        local name = SpellName(entry[1])
        if not name and not english then self.listsMissing = true end
        if name and name ~= entry[2] and not english then out[2] = name end
        return out
    end
    self.periodic, self.shields, self.flights = {}, {}, {}
    for _, e in ipairs(PERIODIC_SPELLS) do
        for _, name in ipairs(names(e)) do
            self.periodic[name] = { period = e[3], school = e[4], direct = e[5] or false, heal = e[6] or false,
                wrack = WRACK_SPEEDS[e[1]] or nil, flies = FLYING_DOTS[e[1]] or nil, noLine = NO_LINE_DOTS[e[1]],
                lineUnsure = LINE_UNSURE_DOTS[e[1]] }
        end
    end
    for _, e in ipairs(SHIELD_SPELLS) do
        for _, name in ipairs(names(e)) do self.shields[name] = { school = e[3], id = e[1] } end
    end
    for _, e in ipairs(FLIGHT_SPELLS) do
        for _, name in ipairs(names(e)) do self.flights[name] = { school = e[3], period = e[4] } end
    end
    for _, name in ipairs(names(HAWK_SPELL)) do self.flights[name] = { school = 1, hawk = true } end
    self.thrownItems = {}
    for _, e in ipairs(THROWN_ITEMS) do
        for _, name in ipairs(names(e)) do self.thrownItems[name] = { school = e[3] } end
    end
    self.areaSpells = {}
    for _, e in ipairs(AREA_SPELLS) do
        for _, name in ipairs(names(e)) do
            self.areaSpells[name] = { id = e[1], name = e[2], school = e[3], time = e[4], how = e[5],
                speeds = e[1] == WRACK_ID or nil }
        end
    end
    return self.periodic, self.shields
end

-- The lists are made once, by name. In another language, a spell the game had no name for yet
-- when they were made (at login) would go by its English name only, for the whole session: so
-- they're made again, once, as the first fight starts.
function BT:RemakeSpellLists()
    if not self.listsMissing or self.listsRemade then return end
    self.listsRemade, self.listsMissing = true, nil
    self.periodic, self.seals = nil, nil
    self:SpellLists()
    self:SealLists()
end

-- Names of a list of spell IDs: the English name, and each ID's name in the game's language
local function NameSet(ids, english)
    local out = { [english] = true }
    for _, id in ipairs(ids) do
        local name = SpellName(id)
        if name then out[name] = true end
    end
    return out
end

-- Heals that land as they're cast, on the friend they're cast on: Penance's ticks (each one its
-- own cast, GitHub #29), Holy Shock, and the plain heals of each class (first ranks' IDs). For a
-- heal on a player outside your group (StrangerHeal): only these are sure to have a heal as their
-- line. Not Chain Heal (one line for each player it jumps to), not Regrowth (its heal over time's
-- line can come first), not a buff or a shield.
local DIRECT_HEALS = { 2050, 2054, 2060, 2061, 5185, 635, 19750, 331, 8004 }
local DIRECT_HEALS_ENGLISH = { "Lesser Heal", "Heal", "Greater Heal", "Flash Heal", "Healing Touch", "Holy Light",
    "Flash of Light", "Healing Wave", "Lesser Healing Wave" }
local PENANCE = { 402174, 1240720, 1240723 }
function BT:HealsOnCast(name)
    if not name then return false end
    if not self.directHeals then
        local set = NameSet(PENANCE, "Penance")
        for _, id in ipairs(DIRECT_HEALS) do
            local n = SpellName(id)
            if n then set[n] = true end
        end
        for _, n in ipairs(DIRECT_HEALS_ENGLISH) do set[n] = true end
        self.directHeals = set
    end
    return self.directHeals[name] == true or self:HealsOrHarms(name)
end

-- Holy Shock and the like: a heal on a friend, damage on an enemy (HEAL_OR_HARM)
function BT:HealsOrHarms(name)
    if not name then return false end
    if not self.healOrHarm then
        self.healOrHarm = {}
        for _, e in ipairs(HEAL_OR_HARM) do
            self.healOrHarm[e[2]] = true
            local local_ = SpellName(e[1])
            if local_ then self.healOrHarm[local_] = true end
        end
    end
    return self.healOrHarm[name] == true
end

function BT:IsVigil(name)
    if not name then return false end
    self.vigilNames = self.vigilNames or NameSet(LIGHTS_VIGIL, LIGHTS_VIGIL.name)
    return self.vigilNames[name] == true
end

-- Who a helpful spell you cast just now went to (HelpedUnit), by GUID
local function HelpedGUID()
    local unit, s = BT:HelpedUnit()
    if s and s.guid then return s.guid, unit end
    local ok, guid = pcall(UnitGUID, unit)
    return ok and Str(guid) or nil, unit
end

-- Light's Vigil put on a friend (or on you), and your Holy Shock on them setting it off: the heals
-- that land on them and their party in the next VIGIL_TIME are the Vigil's, one on each, except
-- the first on the one you Holy Shocked (that's Holy Shock's own heal).
function BT:NoteVigilCast(id, name)
    if self:IsVigil(name) then
        if not self:HealGoesToTarget() and Flag(UnitCanAttack, "player", "target") then return end   -- (on an enemy it adds damage, not heals)
        local guid = HelpedGUID()
        self.vigil = { id = id, name = name, at = GetTime(), guid = guid }
        return
    end
    local v = self.vigil
    if not v or not self:HealsOrHarms(name) then return end
    if not self:HealGoesToTarget() and Flag(UnitCanAttack, "player", "target") then return end
    if GetTime() - v.at > VIGIL_LASTS then self.vigil = nil return end
    local guid, unit = HelpedGUID()
    if v.guid and guid and v.guid ~= guid then return end   -- (a Holy Shock on someone else)
    self.vigil = nil
    self.vigilHeal = { id = v.id, name = v.name, at = GetTime(), key = guid or (unit == "target" and "target" or nil),
        onYou = unit == "player", done = {} }
end

function BT:IsMending(name)
    if not name then return false end
    self.mendingNames = self.mendingNames or NameSet(PRAYER_OF_MENDING, PRAYER_OF_MENDING.name)
    return self.mendingNames[name] == true
end

-- Your Prayer of Mending cast: on the friend it went to (or you)
function BT:NoteMendingCast(id, name)
    if not self:IsMending(name) then return end
    self.mending = { id = id, name = name, at = GetTime(), key = self:HealGoesToTarget() and self:HelpedKey() or nil,
        left = MENDING_JUMPS }
end

-- A heal on a group member (a hit from ResolveFrame) that may be your Prayer of Mending's: while it's
-- out, of its school, on the one it's on (the first heal: the friend you cast it on), or after a jump
-- on anyone but the one it last healed. It still needs a line of yours with it (ClaimHit), as
-- anyone's heals land on the group all the time. peek: don't use a jump up.
function BT:MendingFor(h, peek)
    local m = self.mending
    if not m or h.kind ~= "heal" or not h.key then return nil end
    if h.time < m.at or h.time - m.at > MENDING_LASTS then return nil end
    if not SameHealSchool(Num(h.school), 2) then return nil end
    if m.healed == nil and m.key and h.key ~= m.key then return nil end
    if m.healed and h.key == m.healed then return nil end
    if peek then return m end
    m.left, m.at, m.healed = m.left - 1, h.time, h.key
    if m.left <= 0 then self.mending = nil end
    return m
end

-- A heal on someone else (a hit from ResolveFrame) that's Light's Vigil's
function BT:VigilFor(h)
    local v = self.vigilHeal
    if not v or h.kind ~= "heal" or h.time < v.at - 0.05 or h.time - v.at > VIGIL_TIME then return nil end
    local key = h.key or h.unit
    if v.done[key] then return nil end
    if v.key and key == v.key and not v.shock then
        v.shock = true   -- the first heal on the one you Holy Shocked is Holy Shock's
        return nil
    end
    v.done[key] = true
    return v
end

-- A heal on you that's Light's Vigil's
function BT:VigilOnYou(at)
    local v = self.vigilHeal
    if not v or v.done.player or at < v.at - 0.05 or at - v.at > VIGIL_TIME then return nil end
    if v.onYou and not v.shock then
        v.shock = true
        return nil
    end
    v.done.player = true
    return v
end

-- Your cast on a friend: its heal may land a frame after the cast (Holy Shock), and a heal on them
-- in the next FRIEND_HEAL_TIME is still that cast's. A spell the game calls helpful, or one that
-- heals a friend and hurts an enemy. The server's own cast of the same name in that frame is the same one.
function BT:NoteFriendCast(id, name)
    if not self:HealGoesToTarget() then return end
    local now, f = GetTime(), self.friendHeal
    if f and f.name == name and now - f.at < 0.05 then return end
    local helpful = false
    if C_Spell and C_Spell.IsSpellHelpful then
        local ok, h = pcall(C_Spell.IsSpellHelpful, id)
        helpful = ok and not IsSecret(h) and h == true
    end
    if not helpful and not self:HealsOrHarms(name) then return end
    if self:IsVigil(name) or self:IsMending(name) or (self:SealLists())[name] then return end   -- (they heal nothing as cast)
    self.friendHeal = { id = id, name = name, at = now, key = self:HelpedKey() }   -- (as UnitKey has it)
    if not self.friendHeal.key then self.friendHeal = nil end
end

function BT:FriendHealFor(h)
    local f = self.friendHeal
    if not f or h.kind ~= "heal" or not h.key or h.key ~= f.key then return nil end
    if h.time < f.at - 0.05 or h.time - f.at > FRIEND_HEAL_TIME then return nil end
    self.friendHeal = nil
    return f
end

-- Attacks on your next swing, by name (English, and the game's language)
function BT:NextSwing(name)
    if not self.nextSwing then
        self.nextSwing = {}
        for _, e in ipairs(NEXT_SWING_SPELLS) do
            self.nextSwing[e[2]] = true
            local local_ = SpellName(e[1])
            if local_ then self.nextSwing[local_] = true end
        end
    end
    return name ~= nil and self.nextSwing[name] == true
end

-- Buffs you cast on yourself, by name (English, and the game's language)
function BT:SelfBuffList()
    if self.selfBuffs then return self.selfBuffs end
    local english = IsEnglish()
    self.selfBuffs = {}
    for _, e in ipairs(SELF_BUFFS) do
        self.selfBuffs[e[2]] = true
        local own = SpellName(e[1])
        if own and not english then self.selfBuffs[own] = true end
    end
    return self.selfBuffs
end

-- Whether a spell you cast puts a buff on you only: the game's answer, the list
-- above, or what was seen before (a buff of that name showing up as you cast it)
function BT:IsSelfBuffCast(id, name)
    if C_Spell and C_Spell.IsSelfBuff and id then
        local ok, yes = pcall(C_Spell.IsSelfBuff, id)
        if ok and yes == true then return true end
    end
    if self:SelfBuffList()[name] == true then return true end
    -- A learned one may be a buff you can put on others too (Power Word: Fortitude): with a
    -- friend targeted, it went to them
    return (self.db.learnedBuffs and self.db.learnedBuffs[name] == true and not self:HealGoesToTarget()) or false
end

-- The seals by name (English, and the game's language), and Judgement's names
function BT:SealLists()
    if self.seals then return self.seals, self.judgement end
    local english = IsEnglish()
    local function names(id, name)
        local out = { name }
        local own = SpellName(id)
        if not own and not english then self.listsMissing = true end
        if own and own ~= name and not english then out[2] = own end
        return out
    end
    self.seals, self.judgement = {}, {}
    for _, e in ipairs(SEAL_SPELLS) do
        -- (shown by the game's name for it: "Siegel des Befehls" in German, issue #36)
        local shown = (not english and SpellName(e[1])) or e[2]
        for _, name in ipairs(names(e[1], e[2])) do self.seals[name] = { id = e[1], name = shown, school = e[3] } end
    end
    for _, name in ipairs(names(JUDGEMENT[1], JUDGEMENT[2])) do self.judgement[name] = true end
    return self.seals, self.judgement
end

-- The seal you have on (self.seal), and a line when one goes on or comes off.
-- Buffs can be read out of a fight only; in a fight a seal coming off is worked
-- out: a new seal replaces it, or its time runs out. (Judgement leaves it on.)
function BT:SealNotice(seal, on)
    if not self.db.nSeals then return end
    local icon = self.db.nIcons and self:IconText(seal.id) or ""
    self:Notify(icon .. (on and "+" or "-") .. seal.name, self.TEXT_COLORS.seal)
end

-- How long a seal lasts: what your buffs said it lasts, the last time it was read
function BT:SealTime(name)
    local t = self.db.sealTimes and Num(self.db.sealTimes[name])
    return (t and t > 0) and t or SEAL_TIME
end

-- seal.ends: when the game says it runs out (a reading of your buffs), else from now
function BT:SetSeal(seal, quiet)
    local old = self.seal
    local ends = seal.ends or (GetTime() + self:SealTime(seal.name))
    if old and old.name == seal.name then
        old.ends = ends   -- put on again: it lasts from now
    else
        if old and not quiet then self:SealNotice(old, false) end
        self.seal = { id = seal.id, name = seal.name, school = seal.school, ends = ends }
        if not quiet then self:SealNotice(self.seal, true) end
    end
    local mine = self.seal
    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0, ends - GetTime()) + 0.1, function()
            if BT.seal == mine and GetTime() >= mine.ends then BT:LoseSeal() end
        end)
    end
end

function BT:LoseSeal(quiet)
    local old = self.seal
    if not old then return end
    self.seal = nil
    if not quiet then self:SealNotice(old, false) end
end

-- What a reading of your buffs found (out of a fight): the seal on you, or none
function BT:SeenSeal(found)
    local first = not self.sealRead
    self.sealRead = true
    if found then
        -- How long it lasts on this game, for the next time it's cast in a fight
        if found.duration and found.duration > 0 then
            self.db.sealTimes = self.db.sealTimes or {}
            self.db.sealTimes[found.name] = found.duration
        end
        if not self.seal or self.seal.name ~= found.name then
            self:SetSeal(found, first)
        elseif found.ends and found.ends ~= self.seal.ends then
            self:SetSeal(found, true)   -- the game knows when it runs out
        end
    elseif self.seal then
        self:LoseSeal(first)
    end
end

-- Buffs gained and lost. Your buffs can only be read out of a fight, so what
-- changed during one shows when it ends. Left out: seals (they have their own
-- lines), buffs with no time limit (mounts, auras, stances, tracking) and food
-- and drink. Dying drops your buffs: that's not reported.
local QUIET_BUFFS = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
function BT:SeenBuffs(now)
    local before = self.buffsSeen
    self.buffsSeen = now
    -- Your buffs can be read again after a fight: the ones you cast during it
    -- were already shown as they went on, and those that ran out go now
    local fight = self.fightBuffs
    self.fightBuffs = nil
    -- A buff that turns up as you cast a spell of its name is one you put on yourself
    local cast = self.lastCast
    -- (not when a friend was targeted: then it may be a buff for others that you also have)
    if before and cast and not cast.onFriend and GetTime() - cast.at < 3 and now[cast.name] and not before[cast.name] then
        self.db.learnedBuffs = self.db.learnedBuffs or {}
        self.db.learnedBuffs[cast.name] = true
    end
    if not before or not self.db.nBuffs then return end
    if Flag(UnitIsDeadOrGhost, "player") then return end
    local function worth(b) return not QUIET_BUFFS[b.name] and b.duration ~= nil and b.duration > 0 end
    local function line(b, on)
        local icon = ""
        if self.db.nIcons and b.icon then icon = self:IconTag(b.icon) end
        self:Notify(icon .. (on and "+" or "-") .. b.name, self.TEXT_COLORS.buff)
    end
    for name, b in pairs(before) do
        if not now[name] and worth(b) then line(b, false) end
    end
    for name, b in pairs(now) do
        if not before[name] and worth(b) and not (fight and fight[name]) then line(b, true) end
    end
    for name, b in pairs(fight or {}) do
        if not now[name] and not before[name] then
            local icon = self.db.nIcons and self:IconText(b.id) or ""
            self:Notify(icon .. "-" .. name, self.TEXT_COLORS.buff)
        end
    end
end

-- Shared with the files loaded after this one
S.RANGED_SPELLS, S.REACTIVE_SPELLS, S.REACT_GAP, S.DISPEL_SPELLS, S.DISPEL_WAIT, S.SpellName = RANGED_SPELLS, REACTIVE_SPELLS, REACT_GAP, DISPEL_SPELLS, DISPEL_WAIT, SpellName
S.CREDIT_TIME, S.LINE_WITH_HIT, S.SWING_RECENT, S.EXTRA_TIME, S.EXTRA_HITS, S.TICK_SLACK = CREDIT_TIME, LINE_WITH_HIT, SWING_RECENT, EXTRA_TIME, EXTRA_HITS, TICK_SLACK
S.TICK_CLOSE, S.DOT_TIME, S.UNNAMED_KEEP, S.BEAT_LEAST, S.BEAT_MOST, S.FLAG_NOTES = TICK_CLOSE, DOT_TIME, UNNAMED_KEEP, BEAT_LEAST, BEAT_MOST, FLAG_NOTES
S.STING_FLIGHT, S.UNSEALED_WRATH, S.FLIGHT_TIME, S.HAWK_TIME, S.HAWK_MOST, S.MAIN_HAND = STING_FLIGHT, UNSEALED_WRATH, FLIGHT_TIME, HAWK_TIME, HAWK_MOST, MAIN_HAND
S.ATTACK_SPELL, S.THROW_TIME, S.AREA_SLACK, S.VIGIL_TIME, S.LIFE_TAP, S.LIFE_TAP_TIME = ATTACK_SPELL, THROW_TIME, AREA_SLACK, VIGIL_TIME, LIFE_TAP, LIFE_TAP_TIME
S.LIFE_TAP_BEFORE, S.LIFE_TAP_LOOK, S.PERIODIC_SPELLS, S.NEXT_SWING_SPELLS, S.SHIELD_SPELLS, S.SEAL_SPELLS = LIFE_TAP_BEFORE, LIFE_TAP_LOOK, PERIODIC_SPELLS, NEXT_SWING_SPELLS, SHIELD_SPELLS, SEAL_SPELLS
S.JUDGEMENT, S.SELF_BUFFS, S.FLIGHT_SPELLS, S.HAWK_SPELL, S.THROWN_ITEMS, S.AREA_SPELLS = JUDGEMENT, SELF_BUFFS, FLIGHT_SPELLS, HAWK_SPELL, THROWN_ITEMS, AREA_SPELLS
S.HEAL_OR_HARM, S.LIGHTS_VIGIL, S.PRAYER_OF_MENDING = HEAL_OR_HARM, LIGHTS_VIGIL, PRAYER_OF_MENDING
