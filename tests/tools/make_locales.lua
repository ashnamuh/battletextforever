-- Keeps the language files in Locales\ up to date with the addon's text.
--
-- Every L["English text"] in the addon's files is a line to translate. This
-- writes each language file with every one of them, in the order the game loads
-- them: translations already in the file are kept, new lines are added as ""
-- (shown in English until someone translates them), and lines the addon no
-- longer has are dropped.
--
--   lua5.1 tests/tools/make_locales.lua          update every Locales\xxXX.lua
--   lua5.1 tests/tools/make_locales.lua deDE     the same, and start deDE.lua
--
-- The tests check that the files are up to date, so run it after changing any text.
-- L[...] may only hold text in quotes (pieces joined with ..), so the lines can be
-- found here without running the addon.

local M = {}
local DIR = (ADDON_DIR or ".") .. "/"
local TOC = "BattleTextForever.toc"

local function ReadFile(path)
    local f = assert(io.open(DIR .. path, "rb"), "can't open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

-- The addon's own files, in the order the game loads them (not the language files)
function M.CodeFiles()
    local files = {}
    for line in ReadFile(TOC):gmatch("[^\r\n]+") do
        local file = line:match("^%s*([^#%s].-)%s*$")
        if file and not file:find("^Locales") then files[#files + 1] = (file:gsub("\\", "/")) end
    end
    return files
end

-- Every L["..."] in one file's source: adds new ones to keys (in order) and seen
local function Scan(src, file, keys, seen)
    local n = #src
    local function lineAt(j) local _, c = src:sub(1, j):gsub("\n", "") return c + 1 end
    local function longEnd(j)   -- j at a long bracket "[[" or "[==["; the index after its end
        local eq = src:match("^%[(=*)%[", j)
        local e = assert(src:find("]" .. eq .. "]", j, true), file .. ": unfinished long string")
        return e + #eq + 2
    end
    local function skipSpace(j)
        while true do
            local s = src:match("^%s+", j)
            if s then j = j + #s end
            if src:sub(j, j + 1) ~= "--" then return j end
            if src:match("^%-%-%[=*%[", j) then
                j = longEnd(j + 2)
            else
                local e = src:find("\n", j, true)
                j = e and e + 1 or n + 1
            end
        end
    end
    local function readString(j)   -- j at a quote; the text and the index after it
        local q, k = src:sub(j, j), j + 1
        while true do
            local c = src:sub(k, k)
            if c == "\\" then k = k + 2
            elseif c == q then break
            elseif c == "" or c == "\n" then error(file .. ":" .. lineAt(j) .. ": unfinished string")
            else k = k + 1 end
        end
        return assert(loadstring("return " .. src:sub(j, k)))(), k + 1
    end
    local i = 1
    while i <= n do
        local c = src:sub(i, i)
        if src:sub(i, i + 1) == "--" then
            i = skipSpace(i)
        elseif c == '"' or c == "'" then
            local _, j = readString(i)
            i = j
        elseif src:match("^%[=*%[", i) then
            i = longEnd(i)
        elseif c == "L" and src:sub(i + 1, i + 1) == "[" and not src:sub(i - 1, i - 1):match("[%w_%.:]") then
            local j, parts = skipSpace(i + 2), {}
            while true do
                local q = src:sub(j, j)
                if q ~= '"' and q ~= "'" then
                    error(file .. ":" .. lineAt(i) .. ": L[...] must hold only text in quotes, so it can be translated")
                end
                local v
                v, j = readString(j)
                parts[#parts + 1] = v
                j = skipSpace(j)
                if src:sub(j, j + 1) == ".." then
                    j = skipSpace(j + 2)
                elseif src:sub(j, j) == "]" then
                    break
                else
                    error(file .. ":" .. lineAt(i) .. ": L[...] must hold only text in quotes, so it can be translated")
                end
            end
            local key = table.concat(parts)
            if not seen[key] then
                seen[key] = file
                keys[#keys + 1] = { key = key, file = file }
            end
            i = j + 1
        else
            local word = src:match("^[%w_]+", i)
            i = i + (word and #word or 1)
        end
    end
end

-- Every line to translate, in order: { key = "English", file = "Core.lua" }
function M.Keys()
    local keys, seen = {}, {}
    for _, file in ipairs(M.CodeFiles()) do Scan(ReadFile(file), file, keys, seen) end
    return keys, seen
end

-- The language files there are: { "koKR", ... }
function M.Locales()
    local list = {}
    for line in ReadFile(TOC):gmatch("[^\r\n]+") do
        local code = line:match("^%s*Locales[\\/](%a%a%a%a)%.lua%s*$")
        if code then list[#list + 1] = code end
    end
    return list
end

-- What a language file says: its text for each English line ("" when not done), in order
function M.Read(code)
    local path = "Locales/" .. code .. ".lua"
    local f = io.open(DIR .. path, "rb")
    if not f then return nil end
    local src = f:read("*a")
    f:close()
    local found, order = {}, {}
    local L = setmetatable({}, { __newindex = function(_, k, v)
        if found[k] == nil then order[#order + 1] = k end
        found[k] = v
    end })
    local chunk = assert(loadstring(src, "@" .. path))
    setfenv(chunk, { GetLocale = function() return code end })
    chunk("BattleTextForever", { L = L })
    return found, order, src
end

local function Quote(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local function Header(code)
    return table.concat({
        "-- BattleText Forever: the addon's text in " .. code .. ".",
        "--",
        "-- To translate, write your text after each \"=\", between the quotes:",
        "--     L[\"Low mana!\"] = \"...\"",
        "-- Leave \"\" where you have nothing yet: that line shows in English.",
        "-- Keep %s and %d as they are (a number or a name goes there), and |cffffd100 ... |r",
        "-- (a color), \\n (a new line) and \\\" (a quote mark).",
        "-- Then send the file on CurseForge or GitHub.",
        "",
        "local ADDON, ns = ...",
        "if GetLocale() ~= \"" .. code .. "\" then return end",
        "local L = ns.L",
        "",
    }, "\n")
end

-- The file as it should be: its header (kept as it is), then every line
function M.Make(code)
    local found, _, src = M.Read(code)
    found = found or {}
    local header = src and src:match("^(.-local L = ns%.L\n\n?)") or Header(code)
    if not header:find("\n\n$") then header = header .. "\n" end
    local out, last = { header }, nil
    for _, k in ipairs((M.Keys())) do
        if k.file ~= last then
            if last then out[#out + 1] = "\n" end
            out[#out + 1] = "-- " .. k.file .. "\n"
            last = k.file
        end
        local v = found[k.key]
        out[#out + 1] = "L[" .. Quote(k.key) .. "] = " .. Quote(type(v) == "string" and v or "") .. "\n"
    end
    return table.concat(out)
end

-- The %s / %d codes in a text, in order ("%%" isn't one)
function M.Codes(s)
    local codes = {}
    for c in s:gsub("%%%%", ""):gmatch("%%[%-%d%.]*%a") do codes[#codes + 1] = c end
    return table.concat(codes, " ")
end

if not MAKE_LOCALES_LIBRARY then
    local codes = M.Locales()
    if arg and arg[1] then
        local have = false
        for _, c in ipairs(codes) do if c == arg[1] then have = true end end
        if not have then
            codes[#codes + 1] = arg[1]
            print("add this line to " .. TOC .. " after Locales\\Locales.lua:  Locales\\" .. arg[1] .. ".lua")
        end
    end
    for _, code in ipairs(codes) do
        local text = M.Make(code)
        local f = assert(io.open(DIR .. "Locales/" .. code .. ".lua", "wb"))
        f:write(text)
        f:close()
        local found = M.Read(code)
        local done, all = 0, #(M.Keys())
        for _, v in pairs(found) do if v ~= "" then done = done + 1 end end
        print(("Locales/%s.lua: %d of %d lines translated"):format(code, done, all))
    end
end

return M
