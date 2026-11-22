-- BattleText Forever: the text areas and the lines moving through them.
-- (Split from Core.lua in 1.33.0. Core.lua's shared locals come through ns.S, below.)

local ADDON, ns = ...
local S = ns.S
local BT, T, L, DEFAULTS, AREA_WIDTH, MAX_DELAY = S.BT, S.T, S.L, S.DEFAULTS, S.AREA_WIDTH, S.MAX_DELAY
local MERGE_WINDOW, IsSecret, Num, Str, Flag = S.MERGE_WINDOW, S.IsSecret, S.Num, S.Str, S.Flag

---------------------------------------------------------------------------
-- Scroll areas and the lines moving through them
---------------------------------------------------------------------------
-- Fonts other addons share through LibSharedMedia (UI packs like ElvUI or EllesmereUI often
-- do): added to the list after BattleText's own, by the name they're shared under
function BT:AddSharedFonts()
    local lib = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not lib then return end
    if not self.sharedFontsHooked and lib.RegisterCallback then
        self.sharedFontsHooked = true
        pcall(lib.RegisterCallback, self, "LibSharedMedia_Registered", function(_, kind)
            if kind == "font" or kind == "sound" then BT:AddSharedFonts() end
        end)
    end
    self:AddSharedSounds(lib)
    local ok, names = pcall(lib.List, lib, "font")
    if not ok or type(names) ~= "table" then return end
    local have = {}
    for _, f in ipairs(self.FONTS) do have[f.name] = true end
    for _, name in ipairs(names) do
        if type(name) == "string" and not have[name] then
            local okPath, path = pcall(lib.Fetch, lib, "font", name, true)
            if okPath and type(path) == "string" and path ~= "" then
                self.FONTS[#self.FONTS + 1] = { name = name, path = path, shared = true }
                have[name] = true
                for _, d in ipairs({ self.config and self.config.fontDropdown, self.config and self.config.critFontDropdown }) do
                    if d and d.keys then d.keys[#d.keys + 1] = name end
                end
            end
        end
    end
end

-- Sounds other addons share through LibSharedMedia: added to the crit and kill sound lists,
-- keyed "lsm:<name>" and played from their file
function BT:AddSharedSounds(lib)
    local ok, names = pcall(lib.List, lib, "sound")
    if not ok or type(names) ~= "table" then return end
    local have = {}
    for _, s in ipairs(self.SOUNDS) do have[s.key] = true end
    for _, name in ipairs(names) do
        local key = type(name) == "string" and ("lsm:" .. name)
        if key and not have[key] and name ~= "None" then
            local okPath, file = pcall(lib.Fetch, lib, "sound", name, true)
            if okPath and (type(file) == "string" and file ~= "" or type(file) == "number") then
                self.SOUNDS[#self.SOUNDS + 1] = { key = key, name = name, file = file, shared = true }
                have[key] = true
                local d = self.config and self.config.critSoundDropdown
                if d and d.keys then d.keys[#d.keys + 1] = key end   -- (the kill sound list shares it)
            end
        end
    end
end

-- The file for a line's font. crit: a crit's, which can have a font of its own (db.critFont)
function BT:FontPath(crit)
    local name = self.db.font
    if crit and type(self.db.critFont) == "string" and self.db.critFont ~= "" then name = self.db.critFont end
    -- (kept by name until the list changes: every new line asks)
    local cache = self.fontPathCache
    if not cache or cache.count ~= #self.FONTS then
        cache = { count = #self.FONTS, paths = {} }
        self.fontPathCache = cache
    end
    local path = cache.paths[name]
    if path then return path end
    for _, f in ipairs(self.FONTS) do
        if f.name == name and f.path then path = f.path break end
    end
    path = path or Str(STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    cache.paths[name] = path
    return path
end

-- The font flags for a line: crits have their own outline
function BT:OutlineFlags(crit)
    local flags = crit and self.db.critOutline or self.db.outline
    for _, o in ipairs(self.OUTLINES) do
        if o.flags == flags then return flags end
    end
    return "OUTLINE"
end

function BT:BuildAreas()
    self.areas = {}
    for key, def in pairs(self.AREAS) do
        local a = CreateFrame("Frame", "BattleTextForever" .. def.label, UIParent)
        a:SetFrameStrata("HIGH")
        a.key, a.def = key, def
        a.active, a.pool, a.recent = {}, {}, {}

        -- Shown while unlocked: a box to drag, with the header bar along its top
        local mover = CreateFrame("Frame", nil, a)
        mover:SetAllPoints()
        T.Panel(mover, 0.6)
        mover.header = CreateFrame("Frame", nil, mover)
        mover.header:SetPoint("TOPLEFT")
        mover.header:SetPoint("TOPRIGHT")
        mover.header:SetHeight(18)
        T.HeaderStrip(mover.header, def.title)
        mover.header:FitLogo(18)
        mover.label = mover.header.text
        mover:EnableMouse(true)
        mover:RegisterForDrag("LeftButton")
        a:SetMovable(true)
        a:SetClampedToScreen(true)
        mover:SetScript("OnDragStart", function() a:StartMoving() end)
        mover:SetScript("OnDragStop", function()
            a:StopMovingOrSizing()
            BT:SaveAreaPosition(a)
        end)
        mover:Hide()
        a.mover = mover
        self.areas[key] = a
    end
    self:ApplyAreas()

    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function() BT:Animate(GetTime()) end)
    self.driver = driver
end

-- An area's own setting: "Size" or "Alpha" (db.outSize, db.healAlpha...)
function BT:AreaSetting(a, what)
    return self.db[a.def.prefix .. what]
end

function BT:StyleName(key)
    for _, s in ipairs(self.STYLES) do
        if s.key == key then return s.name end
    end
    return self.STYLES[1].name
end

-- Which side an area's lines line up on: its setting, else the area's own
function BT:AreaJustify(a)
    local align = self:AreaSetting(a, "Align")
    for _, al in ipairs(self.ALIGNS) do
        if al.key == align then return align end
    end
    return a.def.justify
end

function BT:AlignName(key)
    for _, al in ipairs(self.ALIGNS) do
        if al.key == key then return al.name end
    end
    return key
end

-- How an area's lines move: a key of BT.STYLES
function BT:AreaStyle(a)
    local style = self:AreaSetting(a, "Style")
    for _, s in ipairs(self.STYLES) do
        if s.key == style then return style end
    end
    return "scroll"
end

function BT:AreaHeight(a)
    if a.def.short then return math.floor(self.db.height * 0.45) end
    if a.def.heightScale then return math.floor(self.db.height * a.def.heightScale) end
    return self.db.height
end

-- Seconds a line takes to cross an area
function BT:ScrollTime(a)
    if a.def.short then return math.max(1.5, self.db.scrollTime * 0.7) end
    return self.db.scrollTime
end

-- Size, place and (un)lock the areas from the settings
function BT:ApplyAreas()
    if not self.areas then return end
    for key, a in pairs(self.areas) do
        local pos = self.db.areas[key]
        a:SetSize(a.def.dir == 0 and 220 or 150, self:AreaHeight(a))
        a:ClearAllPoints()
        a:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
        a.mover:SetShown(not self.db.locked)
    end
    if self.manaSign then self:CheckLowMana() end   -- (the line, the area or the switch may have changed)
end

function BT:SaveAreaPosition(a)
    local cx, cy = a:GetCenter()
    local ux, uy = UIParent:GetCenter()
    cx, cy, ux, uy = Num(cx), Num(cy), Num(ux), Num(uy)
    if not (cx and cy and ux and uy) then return end
    local pos = self.db.areas[a.key]
    pos.x, pos.y = math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
end

function BT:ResetPositions()
    for key, pos in pairs(DEFAULTS.areas) do
        self.db.areas[key].x, self.db.areas[key].y = pos.x, pos.y
    end
    self:ApplyAreas()
end

local function AcquireLine(a)
    local o = table.remove(a.pool)
    if not o then
        o = CreateFrame("Frame", nil, a)
        o:SetSize(10, 10)
        o.text = o:CreateFontString(nil, "OVERLAY")
    end
    return o
end

local function ReleaseLine(a, o)
    o:Hide()
    local r = o.key and a.recent[o.key]
    if r and r.line == o then a.recent[o.key] = nil end   -- nothing can be added to it any more
    o.key = nil
    a.pool[#a.pool + 1] = o
end

-- The kinds of text, and the area each shows in to start with (Layout tab)
BT.ROUTES = {
    { key = "OutDamage", name = L["Your hits"], usual = "outgoing" },
    { key = "OutMisses", name = L["Your misses"], usual = "outgoing" },
    { key = "OutHeals", name = L["Heals you do"], usual = "heal" },
    { key = "InDamage", name = L["Damage you take"], usual = "incoming" },
    { key = "InMisses", name = L["Attacks you avoid"], usual = "incoming" },
    { key = "InHeals", name = L["Heals you get"], usual = "heal" },
    { key = "InPower", name = L["Power gains"], usual = "incoming" },
    { key = "Notify", name = L["Notifications"], usual = "notify" },
}

-- The area a kind of text shows in ("OutDamage", "Notify"... as in BT.ROUTES)
function BT:Area(kind)
    local area = self.db["route" .. kind]
    if area and self.AREAS[area] then return area end
    for _, r in ipairs(self.ROUTES) do
        if r.key == kind then return r.usual end
    end
    return "notify"
end

-- Whether any kind of text shows in an area
function BT:AreaUsed(areaKey)
    for _, r in ipairs(self.ROUTES) do
        if self:Area(r.key) == areaKey then return true end
    end
    return false
end

-- Where a heal goes (areaKey: "outgoing" for yours, "incoming" for one on you)
function BT:HealArea(areaKey)
    if self.db.healArea == false then return areaKey end   -- (the old setting, before it moves: tests)
    return self:Area(areaKey == "outgoing" and "OutHeals" or "InHeals")
end

-- " on Name" for a heal of yours on someone else, when the game lets the name
-- be read (it can hide it). Never for your pet or yourself.
function BT:HealedName(unit)
    if not self.db.healWho or not unit or unit == "pet" then return "" end
    if Flag(UnitIsUnit, unit, "player") or Flag(UnitIsUnit, unit, "pet") then return "" end
    local ok, name = pcall(UnitName, unit)
    name = ok and Str(name)
    if not name or name == "" then return "" end
    return " |cffc9f7cc" .. name .. "|r"
end

-- The unit a combat line's GUID belongs to (your target, a party member...), when the game says
function BT:UnitFromGUID(guid)
    if type(guid) ~= "string" or guid == "" or not UnitTokenFromGUID then return nil end
    local ok, unit = pcall(UnitTokenFromGUID, guid)
    return ok and Str(unit) or nil
end

-- Whether a crit for n stands out as one: "Smallest crit" (minCrit) makes a smaller one a
-- normal line. A number the game hides keeps the crit's look (it can't be compared).
function BT:BigCrit(crit, n)
    if not crit then return false end
    local least, read = self.db.minCrit or 0, Num(n)
    return not (least > 0 and read ~= nil and read < least)
end

-- Whether a heal of n is big enough to show (a hidden amount always is)
function BT:HealShown(n)
    return type(n) ~= "number" or n >= (self.db.minHeal or 0)
end

-- Puts a line of text into an area.
--   color = { r, g, b }
--   opts.crit    bigger, and sticky if that's turned on
--   opts.key     lines with the same key that arrive together add up (needs opts.amount)
--   opts.format  how to write a merged line: function(total, count) -> text
--   opts.window  seconds a line of ticks or area hits keeps adding up (more than other hits)
--   opts.amount  the number, read: with "Size by hit", a big one shows bigger
--   opts.secret  a value the addon can't read; the game itself writes it after the
--                text (and opts.after follows it). With opts.key, hidden hits that arrive
--                together share a line too: they can't be added up, so it shows the last
--                hit and how many there were.
function BT:Emit(areaKey, text, color, opts)
    local a = self.areas and self.areas[areaKey]
    if not a or not (self.db.enabled or self.testing) then return end
    opts = opts or {}
    local now = GetTime()
    -- "Smallest crit": a small one is a normal line (and can add up with the hits beside it)
    if opts.crit and not self:BigCrit(true, opts.amount) then opts.crit = false end

    -- Add to a line that just started, instead of a new one
    local hidden = IsSecret(opts.secret)
    if opts.key and (opts.amount or hidden) and self.db.merge and not opts.crit then
        local r = a.recent[opts.key]
        if r and r.hidden ~= hidden then r = nil end   -- (a hidden hit and a read one don't mix)
        local window = math.max(MERGE_WINDOW, opts.window or 0)
        -- A longer window adds to a line until it's most of the way across
        local young = r and (window > MERGE_WINDOW and now - r.line.start < r.line.duration * 0.6
            or window <= MERGE_WINDOW and now - r.born < 1)
        if young and r.line.key == opts.key and now - r.time <= window then
            r.count, r.time = r.count + 1, now
            if hidden then
                r.line.text:SetFormattedText("%s%s%s", text, opts.secret,
                    (opts.after or "") .. " |cffb0b0b0(" .. L["%s hits"]:format(r.count) .. ")|r")
            else
                r.total = r.total + opts.amount
                r.line.text:SetText(opts.format(r.total, r.count))
            end
            return r.line
        end
    end

    local o = AcquireLine(a)
    local size = self.db.fontSize * (self:AreaSetting(a, "Size") or 100) / 100
    if opts.crit then size = size * self.db.critScale / 100 end
    -- Size by hit: against the area's usual hit, a bigger one grows (up to half again), a smaller one shrinks
    if self.db.sizeByHit and type(opts.amount) == "number" and opts.amount > 0 then
        local usual = a.usualHit
        if usual then size = size * math.min(1.5, math.max(0.75, (opts.amount / usual) ^ 0.3)) end
        a.usualHit = usual and (usual * 0.9 + opts.amount * 0.1) or opts.amount
    end
    size = math.floor(size + 0.5)
    local flags = self:OutlineFlags(opts.crit)
    local shadow = flags == "SHADOW"
    if shadow then flags = "" end
    -- A line from the pool often has this font already: setting it again is wasted work
    local path = self:FontPath(opts.crit)
    if o.fontPath ~= path or o.fontSize ~= size or o.fontFlags ~= flags then
        if not o.text:SetFont(path, size, flags) and STANDARD_TEXT_FONT then
            o.text:SetFont(STANDARD_TEXT_FONT, size, flags)
        end
        o.fontPath, o.fontSize, o.fontFlags = path, size, flags
    end
    if shadow then
        local d = math.max(1, math.floor(size / 12 + 0.5))
        o.text:SetShadowColor(0, 0, 0, 1)
        o.text:SetShadowOffset(d, -d)
    else
        o.text:SetShadowOffset(0, 0)
    end
    if hidden then   -- (never compare a secret, even with nil: that throws)
        o.text:SetFormattedText("%s%s%s", text, opts.secret, opts.after or "")
    else
        o.text:SetText(text)
    end
    o.text:SetTextColor(color[1], color[2], color[3])
    o.size = size
    o.sticky = opts.crit and self.db.sticky or false
    o.key, o.style = nil, nil
    -- Scrolling lines grow away from the middle of the screen. A crit that holds
    -- grows the other way, so it never sits on top of them.
    local justify = self:AreaJustify(a)
    local anchor = justify
    if o.sticky and a.def.dir ~= 0 then
        anchor = (justify == "LEFT" and "RIGHT") or (justify == "RIGHT" and "LEFT") or "CENTER"
    end
    if o.anchor ~= anchor then
        o.anchor = anchor
        o.text:ClearAllPoints()
        o.text:SetPoint(anchor, o, anchor, 0, 0)
        o.text:SetJustifyH(anchor)
    end

    if o.sticky then
        o.start, o.duration = now, 1.7
        -- The lowest free place among the crits still holding
        local taken, oldest = {}, nil
        for _, other in ipairs(a.active) do
            if other.sticky and now - other.start < other.duration then
                taken[other.slot] = true
                if not oldest or other.start < oldest.start then oldest = other end
            end
        end
        local slot = 0
        while taken[slot] do slot = slot + 1 end
        -- As many as fit in the area: past that, the oldest crit makes way (a burst of area
        -- crits used to stack out of the area and over the next one)
        local most = math.max(1, math.floor(self:AreaHeight(a) / (size + 4)))
        if slot >= most and oldest then
            slot = oldest.slot
            oldest.duration = now - oldest.start
        end
        o.slot = slot
        o.boxW = self:LineWidth(o, size)
    elseif self:AreaStyle(a) ~= "scroll" then
        -- Each line its own place, so none waits for room
        local style, h = self:AreaStyle(a), self:AreaHeight(a)
        local duration = self:ScrollTime(a)
        local count = (a.styleCount or 0) + 1
        a.styleCount = count
        o.style = style
        -- Center areas send lines both ways in turn; the side ones away from the middle
        o.side = a.def.dir ~= 0 and a.def.dir or (count % 2 == 0 and 1 or -1)
        if style == "pop" then
            duration = math.max(1.2, duration * 0.6)
            o.px = (math.random() - 0.5) * (a.def.dir == 0 and 120 or 50)
            o.py = -h * (0.25 + math.random() * 0.45)
            o.boxW = self:LineWidth(o, size)
            if self.db.popApart then o.px, o.py = self:FreeSpot(a, o, now) end
        elseif style == "fountain" then
            o.spread = 0.6 + math.random() * 0.6
        else
            local lanes = math.max(1, math.floor(h * 0.7 / (size + 4)))
            o.lane = count % lanes
        end
        o.start, o.duration = now, duration
    else
        local duration = self:ScrollTime(a)
        local speed = self:AreaHeight(a) / duration
        -- Keep a line's height between this one and the one before
        local start = now
        if a.lastStart then
            start = math.max(now, a.lastStart + (math.max(size, a.lastSize) + 2) / speed)
        end
        -- Crowded: rather than keep this line waiting, the lines ahead of it move along
        local over = (start - now) - MAX_DELAY
        if over > 0 then
            for _, other in ipairs(a.active) do
                if not other.sticky then other.start = other.start - over end
            end
            start = start - over
        end
        a.lastStart, a.lastSize = start, size
        o.start, o.duration = start, duration
    end
    -- (Animate moves it by its one point from now on: SetPoint on the same point replaces it)
    o:ClearAllPoints()
    o.curScale, o.curAlpha = nil, 0
    o:SetAlpha(0)
    o:Show()
    a.active[#a.active + 1] = o
    if self.driver then self.driver:Show() end   -- (it rests while nothing is moving)
    -- Only a plain scrolling line can be added to later (a crit keeps its own number)
    if opts.key and (opts.amount or hidden) and not opts.crit then
        o.key = opts.key
        a.recent[opts.key] = { line = o, time = now, born = now, total = opts.amount or 0, count = 1, hidden = hidden }
    end
    return o
end

-- How wide a line's text is. A number the game hides can't be measured: then a guess.
function BT:LineWidth(o, size)
    local ok, w = pcall(o.text.GetStringWidth, o.text)
    if ok and not IsSecret(w) and type(w) == "number" and w > 0 then return w end
    return size * 3
end

-- A line's box at a place in its area: left, right, top, bottom (y up from the area's top, so
-- negative), with a little room round it. Pop lines all drift up at the same pace, so where
-- they started is enough to tell whether two of them cover each other.
local function LineBox(o, x, y)
    local w, half = o.boxW or o.size * 3, o.size / 2 + 2
    local left = (o.anchor == "LEFT" and x) or (o.anchor == "RIGHT" and x - w) or x - w / 2
    return left - 4, left + w + 4, y + half, y - half
end

local function Overlaps(l1, r1, t1, b1, l2, r2, t2, b2)
    return l1 < r2 and l2 < r1 and b1 < t2 and b2 < t1
end

-- Keep Pop numbers apart: the line's own random spot if nothing's there, else the free spot
-- nearest to it. Spots inside Pop's usual band come first; then the rest of the area, and a
-- little wider. With no room anywhere it keeps its own spot.
local FREE_SPOT_CHECKS = 120
function BT:FreeSpot(a, o, now)
    local h = self:AreaHeight(a)
    local taken = {}
    for _, other in ipairs(a.active) do
        if now - other.start < other.duration then
            if other.style == "pop" then
                taken[#taken + 1] = { LineBox(other, other.px, other.py) }
            elseif other.sticky then
                -- (a crit that holds, where Animate puts it; it doesn't drift, so a little room below it)
                local x, y = 0, other.size + other.slot * (other.size + 4)
                if a.def.dir ~= 0 then x, y = -a.def.dir * 14, -h / 2 + other.slot * (other.size + 4) end
                local l, r, t, b = LineBox(other, x, y)
                taken[#taken + 1] = { l, r, t, b - 20 }
            end
        end
    end
    local function free(x, y)
        local l, r, t, b = LineBox(o, x, y)
        for _, box in ipairs(taken) do
            if Overlaps(l, r, t, b, box[1], box[2], box[3], box[4]) then return false end
        end
        return true
    end
    self.freeSpotChecks = 1
    if free(o.px, o.py) then return o.px, o.py end
    -- The places nearest the random one first, and the first free one wins. Checked at most
    -- FREE_SPOT_CHECKS times: in a busy fight every place was checked against every line (thousands
    -- of checks for one line); past that it stays where it landed.
    -- The grid of places is made once for the area (and its height), and reused: it used to be
    -- about 900 new tables and a new sort function for each line that needed a place
    local wide = a.def.dir == 0 and 60 or 25
    local grid = a.spotGrid
    if not grid or grid.h ~= h then
        grid = { h = h, xs = {}, ys = {}, out = {}, cost = {}, order = {} }
        for y = -h * 0.05, -h * 0.95, -6 do
            for x = -(wide + 60), wide + 60, 10 do
                local n = #grid.xs + 1
                grid.xs[n], grid.ys[n] = x, y
                grid.out[n] = (y > -h * 0.25 or y < -h * 0.70 or math.abs(x) > wide) and 1e6 or 0
            end
        end
        local cost = grid.cost
        grid.less = function(i, j)
            if cost[i] ~= cost[j] then return cost[i] < cost[j] end
            return i < j
        end
        a.spotGrid = grid
    end
    local xs, ys, cost, order = grid.xs, grid.ys, grid.cost, grid.order
    for i = 1, #xs do
        cost[i] = (xs[i] - o.px) ^ 2 + (ys[i] - o.py) ^ 2 + grid.out[i]
        order[i] = i
    end
    table.sort(order, grid.less)
    for k = 1, math.min(#order, FREE_SPOT_CHECKS) do
        self.freeSpotChecks = self.freeSpotChecks + 1
        local i = order[k]
        if free(xs[i], ys[i]) then return xs[i], ys[i] end
    end
    return o.px, o.py
end

-- Moves every line to where it belongs at time `now`
function BT:Animate(now)
    if not self.areas then return end
    local moving = false
    for _, a in pairs(self.areas) do
        local n = #a.active
        -- (an area's settings, read once a frame rather than for each line)
        local h = n > 0 and self:AreaHeight(a) or 0
        local fade = n > 0 and (self:AreaSetting(a, "Alpha") or 100) / 100 or 1
        local scrollUp = n > 0 and self:AreaSetting(a, "ScrollUp")
        local curved = n > 0 and a.def.dir ~= 0 and self:AreaSetting(a, "Curved")
        if n > 0 then moving = true end
        for i = n, 1, -1 do
            local o = a.active[i]
            local t = now - o.start
            if t >= o.duration then
                table.remove(a.active, i)
                ReleaseLine(a, o)
            elseif t >= 0 then
                local p = t / o.duration
                local x, y, alpha, scale = 0, 0, 1, 1
                if o.sticky then
                    if a.def.dir == 0 then
                        y = o.size + o.slot * (o.size + 4)        -- above the notifications
                    else
                        x = -a.def.dir * 14                       -- beside the scrolling lines
                        y = -h / 2 + o.slot * (o.size + 4)
                    end
                    if t < 0.15 then scale = 1 + 0.7 * (1 - t / 0.15) end
                    if t > o.duration - 0.4 then alpha = (o.duration - t) / 0.4 end
                elseif o.style == "pop" then
                    -- Jumps out where it landed, drifts up a little and fades
                    if t < 0.12 then scale = 1 + 0.6 * (1 - t / 0.12) end
                    x, y = o.px, o.py + 20 * p
                    if p > 0.6 then alpha = (1 - p) / 0.4 end
                elseif o.style == "fountain" then
                    -- Thrown up from the middle of the area, falling away to its side
                    x = o.side * (a.def.dir == 0 and 110 or 90) * o.spread * p
                    y = -h * 0.55 + h * (1.6 * p - 2 * p * p)
                    if p < 0.06 then alpha = p / 0.06 elseif p > 0.7 then alpha = (1 - p) / 0.3 end
                elseif o.style == "horizontal" then
                    -- Its own lane near the top, sliding away from the middle
                    x = o.side * 140 * p
                    y = -h * 0.15 - o.lane * (o.size + 4)
                    if p < 0.08 then alpha = p / 0.08 elseif p > 0.75 then alpha = (1 - p) / 0.25 end
                else
                    y = scrollUp and -(1 - p) * h or -p * h
                    if curved then
                        x = a.def.dir * AREA_WIDTH * (1 - (2 * p - 1) ^ 2)
                    end
                    if p < 0.08 then alpha = p / 0.08 elseif p > 0.75 then alpha = (1 - p) / 0.25 end
                end
                -- Only what changed goes to the game: the scale only grows in a crit's first moment,
                -- and the alpha only changes as a line fades in and out
                if o.curScale ~= scale then
                    o.curScale = scale
                    o:SetScale(scale)
                end
                o:SetPoint(o.anchor, a, "TOP", x / scale, y / scale)
                alpha = alpha * fade
                if o.curAlpha ~= alpha then
                    o.curAlpha = alpha
                    o:SetAlpha(alpha)
                end
            end
        end
    end
    -- Nothing on screen: rest until the next line (Emit wakes it)
    if not moving and self.driver then self.driver:Hide() end
end
