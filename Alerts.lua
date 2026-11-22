-- BattleText Forever: ability alerts, cooldowns, interrupts, dispels, procs, combo points, spell rules.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, L, IsSecret, Num, Str, Flag = S.BT, S.L, S.IsSecret, S.Num, S.Str, S.Flag
local RANGED_SPELLS, REACTIVE_SPELLS, REACT_GAP, DISPEL_SPELLS, DISPEL_WAIT, SpellName = S.RANGED_SPELLS, S.REACTIVE_SPELLS, S.REACT_GAP, S.DISPEL_SPELLS, S.DISPEL_WAIT, S.SpellName

-- Whether you have an ability of REACTIVE_SPELLS: your class, and the level it's
-- trained at; a talent only when the game says you know it
function BT:HasReactive(e)
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or Str(class) ~= e[3] then return false end
    if e[5] then
        local okLevel, level = pcall(UnitLevel, "player")
        level = okLevel and Num(level) or nil
        return level == nil or level >= e[5]
    end
    return self:KnowsSpell(e[1])
end

-- Whether the game says you know a spell or talent. C_SpellBook's is the supported
-- one; the globals exist only with the game's deprecation fallbacks loaded (a setting)
function BT:KnowsSpell(id)
    local spellBook = C_SpellBook and C_SpellBook.IsSpellKnown
    local checks = {
        spellBook and function(spell) return spellBook(spell, Enum and Enum.SpellBookSpellBank
            and Enum.SpellBookSpellBank.Player or 0) end or false,
        IsPlayerSpell or false, IsSpellKnown or false,
    }
    for _, known in ipairs(checks) do
        local okKnown, yes = false, nil
        if known then okKnown, yes = pcall(known, id) end
        if okKnown and not IsSecret(yes) and yes == true then return true end
    end
    return false
end

-- Something happened that opens an ability of yours ("dodged", "avoided", "parried"
-- as in REACTIVE_SPELLS): "Overpower!" in Notifications
function BT:React(what)
    if self.testing or not self.db.nAlerts then return end   -- (a sample dodge isn't a real one)
    for _, e in ipairs(REACTIVE_SPELLS) do
        if e[4] == what and self:HasReactive(e) and self:InStance(e[6]) and not self:CoolingDown(e) then
            self:Alert(e[1], SpellName(e[1]) or e[2])
        end
    end
end

-- The spell of the stance or form you're in (nil: none, or the game won't say)
function BT:StanceSpell()
    if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
    local ok, index = pcall(GetShapeshiftForm)
    index = ok and Num(index) or nil
    if not index or index == 0 then return nil end
    local ok2, _, _, _, spellId = pcall(GetShapeshiftFormInfo, index)
    return ok2 and Num(spellId) or nil
end

-- Whether you're in one of these stances (none listed, or yours unknown: yes)
function BT:InStance(stances)
    if not stances then return true end
    local now = self:StanceSpell()
    if not now then return true end
    for _, id in ipairs(stances) do
        if id == now then return true end
    end
    local name = SpellName(now)   -- (another rank's ID: by its name)
    for _, id in ipairs(stances) do
        if name and name == SpellName(id) then return true end
    end
    return false
end

local CooldownOf   -- (below, with the cooldowns ready)
-- A reactive spell still on its own cooldown (Overpower's 5 seconds): it can't be used, so no
-- alert (CurseForge, Quarnok: "sometimes I'm getting procs when the button is not available").
-- The global cooldown doesn't count. Asked by name, so it's the rank you know.
function BT:CoolingDown(e)
    local cd = CooldownOf(SpellName(e[1]) or e[2])
    return cd ~= nil and cd.active == true and cd.gcd ~= true
end

-- "<name>!" in Notifications, once per REACT_GAP for each name
function BT:Alert(id, name)
    -- (one hidden on the Spells tab isn't announced; one with its own color has it)
    local rule = self:SpellRule(name)
    if rule and rule.hide then return end
    local now = GetTime()
    self.reactAt = self.reactAt or {}
    if self.reactAt[name] and now - self.reactAt[name] < REACT_GAP then return end
    self.reactAt[name] = now
    local icon = self.db.nIcons and self:IconText(id) or ""
    self:Notify(icon .. name .. "!", (rule and rule.color) or self.TEXT_COLORS.alert, { crit = true })
end

---------------------------------------------------------------------------
-- Cooldowns ready (Notifications): "<icon>Kick ready" when a spell of yours
-- comes off its cooldown. On Forever, C_Spell.GetSpellCooldown never hides
-- isActive, isEnabled and isOnGCD (its start and length can be hidden in a
-- fight), so whether a cooldown is running can always be asked.
---------------------------------------------------------------------------
local COOLDOWN_SHORTEST = 8    -- seconds: a shorter cooldown isn't announced (when the game says how long)
local COOLDOWN_LONGEST = 600   -- nor a longer one (Hearthstone)
local COOLDOWN_WATCH = 1       -- a cast's cooldown must show up within this
local COOLDOWN_LOOK = 0.25     -- seconds between looks while one is running
local COOLDOWN_SLACK = 0.5     -- a hidden length is timed from your cast: this much early still counts

local function Bool(v) if IsSecret(v) or type(v) ~= "boolean" then return nil end return v end

-- A spell's cooldown, as { active, enabled, gcd, length } (each nil when the game hides it)
function CooldownOf(id)   -- (the local declared above)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
    return { active = Bool(info.isActive), enabled = Bool(info.isEnabled), gcd = Bool(info.isOnGCD),
        length = Num(info.duration) }
end

-- Your cast: its cooldown is looked for in the moment after it (and at the game's cooldown updates)
-- Shoot, Auto Shot and Throw repeat on their own: their "cooldown" is the weapon's speed, and
-- in a fight the game hides its length, so "Shoot ready" came after every wand shot
-- (CurseForge, 1.21.5). They're never announced, nor is any spell the game says repeats.
function BT:RepeatsOnItsOwn(id)
    if RANGED_SPELLS[id] then return true end
    if C_Spell and C_Spell.IsAutoRepeatSpell then
        local ok, auto = pcall(C_Spell.IsAutoRepeatSpell, id)
        if ok and not IsSecret(auto) and auto == true then return true end
    end
    return false
end

function BT:WatchCooldown(spellId)
    local id = Num(spellId)
    if not id or not self.db.nCooldowns then return end
    if self:RepeatsOnItsOwn(id) then return end
    self.cdCast = self.cdCast or {}
    self.cdCast[id] = GetTime()
    if C_Timer and C_Timer.After then C_Timer.After(0.1, function() BT:LookCooldowns(false) end) end
end

-- update: answering SPELL_UPDATE_COOLDOWN, the only time the game's isOnGCD can be believed
function BT:LookCooldowns(update)
    local now = GetTime()
    self.cooling = self.cooling or {}
    for id, at in pairs(self.cdCast or {}) do
        local cd = CooldownOf(id)
        if not cd or now - at > COOLDOWN_WATCH then
            self.cdCast[id] = nil
        elseif cd.enabled == false then
            -- Held until something ends (Stealth: it starts when you come out)
            self.cdCast[id], self.cooling[id] = nil, { at = now }
        elseif cd.active and (cd.gcd == false or (cd.gcd == nil and cd.length and cd.length > 2)) then
            self.cdCast[id] = nil
            if not cd.length or (cd.length >= COOLDOWN_SHORTEST and cd.length <= COOLDOWN_LONGEST) then
                self.cooling[id] = { at = now, seen = true, from = at, hidden = not cd.length }
            end
        elseif cd.active == false or (update and cd.gcd == true) then
            self.cdCast[id] = nil   -- no cooldown of its own (or only the global one)
        end
    end
    for id, c in pairs(self.cooling) do
        local cd = CooldownOf(id)
        if not cd or now - c.at > COOLDOWN_LONGEST + 5 then
            self.cooling[id] = nil
        elseif cd.enabled ~= false and cd.active and cd.gcd ~= true then
            if not c.seen then
                c.seen, c.at, c.from = true, now, now   -- a held one has started
                c.hidden = not cd.length
                if cd.length and (cd.length < COOLDOWN_SHORTEST or cd.length > COOLDOWN_LONGEST) then
                    self.cooling[id] = nil
                end
            end
        elseif c.seen and cd.enabled ~= false then
            self.cooling[id] = nil
            -- (its length was hidden: one that was over sooner than COOLDOWN_SHORTEST was a short one)
            if not (c.hidden and c.from and now - c.from < COOLDOWN_SHORTEST - COOLDOWN_SLACK) then
                self:CooldownReady(id)
            end
        end
    end
    -- While one is running, look again in a moment (the game doesn't always say when one ends)
    if next(self.cooling) and not self.cdLooking and C_Timer and C_Timer.After then
        self.cdLooking = true
        C_Timer.After(COOLDOWN_LOOK, function()
            BT.cdLooking = nil
            BT:LookCooldowns(false)
        end)
    end
end

function BT:CooldownReady(id)
    if not self.db.nCooldowns then return end
    local name = SpellName(id)
    if not name then return end
    local rule = self:SpellRule(name)
    if rule and rule.hide then return end
    local icon = self.db.nIcons and self:IconText(id) or ""
    self:Notify(icon .. L["%s ready"]:format(name), (rule and rule.color) or self.TEXT_COLORS.alert)
end

---------------------------------------------------------------------------
-- Interrupts (Notifications): "Interrupted Frostbolt" when you (or your pet)
-- stop an enemy's cast. UNIT_SPELLCAST_INTERRUPTED says who did it
-- (interruptedBy, a GUID). When the game hides that, a cast of one of
-- INTERRUPT_SPELLS just before your target's cast stopped is taken for it.
---------------------------------------------------------------------------
local INTERRUPT_SPELLS = {
    { 6552, "Pummel" }, { 72, "Shield Bash" }, { 1766, "Kick" }, { 8042, "Earth Shock" },
    { 2139, "Counterspell" }, { 16979, "Feral Charge" }, { 15487, "Silence" },
}
local INTERRUPT_TIME = 0.5   -- seconds between your interrupt and the cast it stopped

function BT:IsInterruptSpell(name)
    if not self.interruptNames then
        self.interruptNames = {}
        for _, e in ipairs(INTERRUPT_SPELLS) do
            self.interruptNames[e[2]] = e[1]
            local here = SpellName(e[1])
            if here then self.interruptNames[here] = e[1] end
        end
    end
    return name ~= nil and self.interruptNames[name] ~= nil
end

-- Your cast: remembered for a moment if it can interrupt
function BT:NoteInterruptCast(spellId)
    local id = Num(spellId)
    local name = id and SpellName(id)
    if name and self:IsInterruptSpell(name) then self.kick = { id = id, at = GetTime() } end
end

function BT:OnInterrupted(unit, castGUID, spellId, interruptedBy)
    if not self.db.nInterrupts then return end
    unit = Str(unit)
    if not unit or Flag(UnitIsUnit, unit, "player") or Flag(UnitIsUnit, unit, "pet") then return end
    if not Flag(UnitCanAttack, "player", unit) then return end
    local now = GetTime()
    local by = Str(interruptedBy)
    local pet = false
    if by and by ~= "" then
        local me, myPet = Str(UnitGUID and UnitGUID("player")), Str(UnitGUID and UnitGUID("pet"))
        pet = myPet ~= nil and by == myPet
        if by ~= me and not pet then return end   -- someone else's
    else
        -- The game hides who: only your target, just after an interrupt of yours
        local k = self.kick
        if not (k and now - k.at <= INTERRUPT_TIME and Flag(UnitIsUnit, unit, "target")) then return end
    end
    -- The event comes once for each name the unit has (target, nameplate3): show it once
    local key = Str(castGUID) or "?"
    self.interrupted = self.interrupted or {}
    for k, at in pairs(self.interrupted) do
        if now - at > 1 then self.interrupted[k] = nil end
    end
    if self.interrupted[key] then return end
    self.interrupted[key] = now
    local kick = self.kick
    self.kick = nil
    local id = Num(spellId)
    local name = id and SpellName(id)
    local icon = self.db.nIcons and self:IconText(id or (kick and kick.id)) or ""
    local text = (pet and self:PetLabel() or "") .. (name and L["Interrupted %s"]:format(name) or L["Interrupted!"])
    self:Notify(icon .. text, self.TEXT_COLORS.alert, { crit = true })
end

-- Dispels (Notifications). The Combat Log's line names what came off:
-- "Your Cleanse cleansed X's Corruption." It arrives only when "Dispels" is
-- ticked in the Combat Log's Message Types; until one has, a cast of a spell in
-- DISPEL_SPELLS shows by itself (DispelCast).
function BT:ShowDispel(info, mine, pet)
    if not (mine or pet) then return false end
    if mine then self.dispelLineAt = GetTime() end
    local what = info.extraSpell
    if not what then return false end
    if not self.db.nDispels then return true end
    local rule = self:SpellRule(info.spell)
    if rule and rule.hide then return true end
    local word = info.stolen and L["Stole %s"] or (info.aura == "BUFF" and not info.toMe) and L["Purged %s"]
        or L["Dispelled %s"]
    local icon = self.db.nIcons and self:IconText(info.extraSpellId or what) or ""
    self:Notify(icon .. (pet and self:PetLabel() or "") .. word:format(what), self.TEXT_COLORS.dispel)
    return true
end

-- DISPEL_SPELLS by name (English, and the game's language)
function BT:IsDispelSpell(id, name)
    if not self.dispelNames then
        self.dispelNames, self.dispelIds = {}, {}
        for _, e in ipairs(DISPEL_SPELLS) do
            self.dispelIds[e[1]] = true
            self.dispelNames[e[2]] = true
            local translated = SpellName(e[1])
            if translated then self.dispelNames[translated] = true end
        end
    end
    return (id and self.dispelIds[id]) or (name and self.dispelNames[name]) or false
end

-- A cast of a dispel spell: if no dispel line of yours has arrived within
-- DISPEL_WAIT, the cast shows on its own ("Cleanse"). Once a line has arrived since
-- logging in, the lines are on, and a cast with no line took nothing off.
function BT:DispelCast(id, name)
    if not self.db.nDispels or self.dispelLineAt then return end
    local at = GetTime()
    local function show()
        if self.dispelLineAt and self.dispelLineAt >= at - 0.1 then return end
        if not self.db.nDispels then return end
        local rule = self:SpellRule(name)
        if rule and rule.hide then return end
        local icon = self.db.nIcons and self:IconText(id or name) or ""
        self:Notify(icon .. name, self.TEXT_COLORS.dispel)
    end
    if C_Timer and C_Timer.After then C_Timer.After(DISPEL_WAIT, show) else show() end
end

-- The "usable" ones of REACTIVE_SPELLS (Execute, Hammer of Wrath): an alert when the game
-- starts saying one can be cast on your enemy target. Only once the game has been seen to
-- say no with power to spare (otherwise its answer doesn't depend on the target's health,
-- and an alert would mean nothing). Not enough rage or mana keeps it waiting: the alert
-- comes when it can really be pressed.
function BT:CheckUsable(newTarget)
    local usable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not self.db.nAlerts or not usable then return end
    -- Nothing to look at without an ability of this kind (most classes and levels). Asked on
    -- every change to your target's health: the class is asked once, not for each spell.
    local okClass, _, class = pcall(UnitClass, "player")
    class = okClass and Str(class) or nil
    local any = false
    for _, e in ipairs(REACTIVE_SPELLS) do
        if e[4] == "usable" and e[3] == class and self:HasReactive(e) then any = true break end
    end
    if not any then return end
    -- The game sends SPELL_UPDATE_USABLE in bursts (crafting, bags changing): look once, at the
    -- end of the frame, at how things stand by then
    if newTarget then self.usableNewTarget = true end
    if not (C_Timer and C_Timer.After) then return self:LookUsable(newTarget) end
    if self.usablePending then return end
    self.usablePending = true
    C_Timer.After(0, function()
        local fresh = BT.usableNewTarget
        BT.usablePending, BT.usableNewTarget = nil, nil
        BT:LookUsable(fresh)
    end)
end

function BT:LookUsable(newTarget)
    local usable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    self.usableNow, self.usableLearned = self.usableNow or {}, self.usableLearned or {}
    local enemy = Flag(UnitCanAttack, "player", "target") and not Flag(UnitIsDeadOrGhost, "target")
    for _, e in ipairs(REACTIVE_SPELLS) do
        if e[4] == "usable" and self:HasReactive(e) then
            local name = SpellName(e[1]) or e[2]
            if newTarget or not enemy then self.usableNow[name] = nil end
            local ok, yes, noPower = pcall(usable, name)
            if enemy and ok and not IsSecret(yes) and not IsSecret(noPower) then
                yes, noPower = yes == true or yes == 1, noPower == true or noPower == 1
                if yes then
                    if not self.usableNow[name] and self.usableLearned[name] then self:Alert(e[1], name) end
                    self.usableNow[name] = true
                elseif not noPower then
                    self.usableLearned[name] = true
                    self.usableNow[name] = nil
                end
            end
        end
    end
end

-- A spell button lights up, or a proc shows its overlay (Clearcasting): "<name>!".
-- glow: the button lighting up, which a proc's own overlay has already said.
function BT:OnSpellOverlay(spellId, glow)
    if not self.db.nAlerts then return end
    local id = Num(spellId)
    local name = id and SpellName(id)
    if not name then return end
    local now = GetTime()
    if glow and self.overlayAt and now - self.overlayAt < 0.2 then return end
    if not glow then self.overlayAt = now end
    self:Alert(id, name)
end

-- Procs that put a buff on you, for those the game doesn't light up: { spell ID (0: not known
-- yet), English name }. Forever's Missile Barrage (Arcane talent: a free, fast Arcane Missiles)
-- and Revelation (a weapon enchant: the next spell's crit chance doubled), and the mage's others.
-- Third: the one class it comes to (none: any class; Revelation is a weapon enchant).
local PROC_BUFFS = {
    { 0, "Missile Barrage", "MAGE" }, { 0, "Revelation" }, { 0, "Hot Streak", "MAGE" }, { 0, "Fingers of Frost", "MAGE" },
    { 0, "Brain Freeze", "MAGE" }, { 16870, "Clearcasting" },
}
-- Your class's procs, each with the names to ask for (English, and the game's own), made once
-- (UNIT_AURA comes often: it used to make a table for each proc of every class each time)
function BT:ProcList()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and Str(class) or nil
    if self.procList and self.procListClass == class then return self.procList end
    local list = {}
    for _, e in ipairs(PROC_BUFFS) do
        if not e[3] or not class or e[3] == class then
            local names = { e[2] }
            local own = e[1] > 0 and SpellName(e[1])
            if own and own ~= e[2] then names[2] = own end
            list[#list + 1] = { id = e[1], key = e[2], names = names }
        end
    end
    self.procList, self.procListClass = list, class
    return list
end
-- Your buffs change: "<name>!" for a proc that has just come up. In a fight the game hides most
-- of your buffs (SecretWhenUnitAuraRestricted), and C_UnitAuras.GetAuraDataBySpellName answers
-- only for a buff it doesn't hide (RequiresNonSecretAura): so in a fight only the procs the game
-- leaves readable can show. Not yet seen in game: which ones those are on Forever.
function BT:CheckProcs()
    if not (self.db.nAlerts and self.db.enabled) then return end
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not byName then return end
    self.procsOn = self.procsOn or {}
    -- (in a fight a hidden buff and no buff both come back as nothing: only a buff seen counts.
    -- The first look after a fight only takes note: a proc from the fight isn't new by then)
    local fighting = Flag(InCombatLockdown)
    local quiet = not fighting and self.procsFought
    self.procsFought = fighting or nil
    for _, p in ipairs(self:ProcList()) do
        local on, known = false, false
        for _, name in ipairs(p.names) do
            local ok, a = pcall(byName, "player", name, "HELPFUL")
            if ok and not IsSecret(a) then
                if type(a) == "table" and not IsSecret(a.name) then
                    on, known = true, true
                    local id = not IsSecret(a.spellId) and Num(a.spellId)
                    if not self.procsOn[p.key] and not quiet then
                        local shown = Str(a.name) or name
                        self:Alert(id or (p.id > 0 and p.id) or shown, shown)
                        if self.db.debug then self:Record(("PROC %s (%s)"):format(shown, tostring(id))) end
                    end
                    break
                elseif a == nil and not fighting then
                    known = true
                end
            end
        end
        if known then self.procsOn[p.key] = on end
    end
end

-- Combo points: "2 CP" as they go up, "5 CP: Finish it!" at the most you can have
local function ComboPoints()
    local kind = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
    local n, most
    if UnitPower then
        local ok, v = pcall(UnitPower, "player", kind)
        n = ok and Num(v) or nil
    end
    if n == nil and GetComboPoints then
        local ok, v = pcall(GetComboPoints, "player", "target")
        n = ok and Num(v) or nil
    end
    if UnitPowerMax then
        local ok, v = pcall(UnitPowerMax, "player", kind)
        most = ok and Num(v) or nil
    end
    return n, (most and most > 0) and most or 5
end

-- A new target: the points on it (back to one that still has some) aren't a gain
function BT:QuietComboPoints()
    local n = ComboPoints()
    if n ~= nil then self.combo = n end
end

function BT:OnComboPoints()
    local n, most = ComboPoints()
    if n == nil then return end
    local was = self.combo or 0
    self.combo = n
    if not self.db.nCombo or n <= was then return end
    if n >= most then
        self:Notify(L["%d CP: Finish it!"]:format(n), self.TEXT_COLORS.combo, { crit = true })
    else
        self:Notify(L["%d CP"]:format(n), self.TEXT_COLORS.combo)
    end
end

-- Your choices for a spell on the Spells tab (hide it, or a color of your own), by the
-- name it shows with, whatever its case
function BT:SpellRule(name)
    if type(name) ~= "string" then return nil end
    local by = self.rulesByName
    if not by then
        by = {}
        for _, r in ipairs(self.db.spellRules) do
            if type(r) == "table" and type(r.name) == "string" then by[r.name:lower()] = r end
        end
        self.rulesByName = by
    end
    return by[name:lower()]
end

-- Adds a spell to the Spells tab's list. Returns the rule, or nil and why not.
function BT:AddSpellRule(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, L["type a spell's name first"] end
    if #name > 60 then return nil, L["that name is too long"] end
    if self:SpellRule(name) then return nil, L["%s is already on the list"]:format(name) end
    local rule = { name = name, hide = false }
    table.insert(self.db.spellRules, rule)
    self.rulesByName = nil
    return rule
end

function BT:RemoveSpellRule(i)
    table.remove(self.db.spellRules, i)
    self.rulesByName = nil
end

function BT:SetSpellRule(rule, field, value)
    rule[field] = value
    self.rulesByName = nil
end

-- Shared with the files loaded after this one
S.INTERRUPT_SPELLS = INTERRUPT_SPELLS
