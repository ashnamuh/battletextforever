-- BattleText Forever: the addon's own text in other languages.
--
-- Every line BattleText writes itself is looked up as L["the English text"].
-- A language file (Locales\koKR.lua and so on) fills in what it has; anything
-- it leaves out, or leaves as "", shows in English.
--
-- Translators: copy Locales\koKR.lua, put your language's code in the
-- GetLocale() check at the top, and write your text after each "=".

local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, english) return english end,
    -- (an empty translation is "not done yet": the English shows instead)
    __newindex = function(t, english, text)
        if type(text) == "string" and text ~= "" then rawset(t, english, text) end
    end,
})
ns.L = L
