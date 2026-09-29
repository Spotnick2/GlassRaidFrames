-- Click-casting and hover keys (#3): the binding list turned into header
-- attributes and override bindings, per role, reconciled out of combat.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Spells by ID (the client's localized names; the addon never stores names).
local SPELLS = {
    [2061] = { "Flash Heal", "Rank 1" }, [2060] = { "Greater Heal", "Rank 1" },
    [10963] = { "Greater Heal", "Rank 2" }, [139] = { "Renew", "Rank 1" },
    [2006] = { "Resurrection", "Rank 1" }, [17] = { "Power Word: Shield", "Rank 1" },
}
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] end,
    GetSpellSubtext = function(id) return SPELLS[id] and SPELLS[id][2] end,
})
-- Base key bindings (what the player bound) and our overrides.
local BASE = { ["1"] = "ACTIONBUTTON1", ["3"] = "ACTIONBUTTON3", ["SHIFT-R"] = nil, W = "MOVEFORWARD" }
rawset(_G, "GetBindingAction", function(key, checkOverride) return BASE[key] end)
local overrides, clears = {}, 0
rawset(_G, "SetOverrideBindingClick", function(owner, _, key, name) overrides[key] = name end)
rawset(_G, "ClearOverrideBindings", function() overrides = {}; clears = clears + 1 end)
local selfCast = "ALT"
rawset(_G, "GetModifiedClick", function(what) return what == "SELFCAST" and selfCast or nil end)
-- The main action bar's buttons, as Blizzard's ActionBar.lua builds them.
local bar = { actionButtons = {} }
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.commandName = "ACTIONBUTTON" .. i
    bar.actionButtons[i] = b
end
rawset(_G, "MainActionBar", bar)

party(2)
GlassRaidFramesCharDB = { role = "HEALER" }
local GRF = loadAddon()
local CC = GRF.ClickCast

-- Pure helpers.
eq(CC.MouseBind(true, true, true, 1), "alt-ctrl-shift-1", "mouse binds in Blizzard's prefix order")
eq(CC.KeyBind(false, true, true, "R"), "CTRL-SHIFT-R", "key binds as WoW names them")
local mods, button = CC.ParseMouse("ctrl-shift-2")
eq(mods, "ctrl-shift-", "a mouse bind's attribute prefix")
eq(button, 2, "and button")
eq(CC.ParseMouse("shift-9"), nil, "only buttons 1-5")

-- Macc's binds: mouse + keys, one pinned rank, one rez.
CC.Set("shift-1", true, 2061)                -- Flash Heal, highest rank
CC.Set("ctrl-1", true, 10963, true)           -- Greater Heal rank 2, pinned
CC.Set("1", false, 17)                        -- key 1: PW:Shield (bar slot 1 fallback)
CC.Set("3", false, 10963, true)               -- key 3: Greater Heal rank 2
CC.Set("SHIFT-R", false, 2006)                -- Shift-R: Resurrection (no bar binding)
flush()

-- Mouse rows: attributes on EVERY header child.
local c = GRF.Header.children[1]
eq(c:GetAttribute("shift-type1"), "spell", "shift-left casts a spell")
eq(c:GetAttribute("shift-spell1"), "Flash Heal", "unpinned: the bare name (highest rank)")
eq(c:GetAttribute("ctrl-spell1"), 10963, "pinned: the rank's own spell ID (measured to keep the rank)")
eq(GRF.Header.children[40]:GetAttribute("ctrl-spell1"), 10963, "on every child")
eq(c:GetAttribute("*type1"), "target", "the plain click still targets")

-- Key rows: one secure button each, bound, with the group-only macro.
local kb = CC._test.keyButtons
check(kb["1"] and kb["1"]._template == "SecureActionButtonTemplate", "key 1 has its own secure button")
eq(overrides["1"], kb["1"]:GetName(), "key 1 is bound to it")
local m1 = kb["1"]:GetAttribute("macrotext")
check(m1:find("/cast [@mouseover,help,nodead,party][@mouseover,help,nodead,raid] Power Word: Shield", 1, true),
    "only a living group member under the cursor gets the spell")
check(m1:find("/click [@mouseover,noparty,noraid][@mouseover,noexists][@mouseover,nohelp][@mouseover,dead] ActionButton1", 1, true),
    "anything else: the key's own action button (the exact complement)")
check(kb["3"]:GetAttribute("macrotext"):find("Greater Heal(Rank 2)", 1, true), "a pinned rank in a macro: Name(localized rank)")
local mr = kb["SHIFT-R"]:GetAttribute("macrotext")
check(mr:find("[@mouseover,help,dead,party][@mouseover,help,dead,raid] Resurrection", 1, true), "a rez aims at DEAD members")
check(not mr:find("/click", 1, true), "an unbound key has no fallback line")
for key, b in pairs(kb) do
    check(#b:GetAttribute("macrotext") <= CC.MAX_MACRO, key .. "'s macro fits a macro")
end

-- A key bound to something that isn't an action button is left alone.
CC.Set("W", false, 139)
flush()
eq(overrides.W, nil, "a key bound to MOVEFORWARD is not taken over")
local wrow
for _, r in ipairs(CC.Rows()) do if r.key == "W" then wrow = r end end
check(table.concat(CC.Warnings(wrow), ";"):find("MOVEFORWARD"), "and the options say why")
CC.Remove(wrow)
flush()

-- The reconciliation converges: our own override change fires
-- UPDATE_BINDINGS, and nothing is redone when nothing differs.
local before = clears
WoW.fire("UPDATE_BINDINGS"); flush()
WoW.fire("SPELLS_CHANGED"); flush()
eq(clears, before, "no rebinding when nothing changed (no UPDATE_BINDINGS loop)")

-- Warnings: a click on the Self Cast modifier casts on you (measured).
local arow = CC.Set("alt-2", true, 139)
flush()
check(table.concat(CC.Warnings(arow), ";"):find("Self Cast"), "an Alt click warns about the Self Cast key")
local keyAlt = CC.Set("ALT-R", false, 2006)
flush()
check(not table.concat(CC.Warnings(keyAlt), ";"):find("Self Cast"), "an Alt KEY doesn't (measured fine)")
local plain = CC.Set("1", true, 2061)
flush()
check(table.concat(CC.Warnings(plain), ";"):find("target"), "binding the plain left click warns it replaces target")
CC.Remove(plain); CC.Remove(arow); CC.Remove(keyAlt)
flush()
eq(c:GetAttribute("type1"), nil, "a removed mouse row's attribute is cleared")
eq(c:GetAttribute("alt-type2"), nil, "every removed one")
eq(overrides["ALT-R"], nil, "a removed key is unbound")

-- In combat: the installed bindings stay; the change waits, marked pending.
WoW.combat = true
WoW.blocked = {}
CC.Set("shift-2", true, 139)
check(CC.pending, "a change in combat is pending")
eq(c:GetAttribute("shift-spell2"), nil, "and not applied yet")
eq(#WoW.blocked, 0, "nothing protected was touched in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(c:GetAttribute("shift-spell2"), "Renew", "applied when combat ends")
check(not CC.pending, "no longer pending")

-- Bindings are per role and per character: another role has its own list.
GRF.Settings.SetRole("caster")
flush()
eq(c:GetAttribute("shift-spell1"), nil, "the caster role has none of the healer's clicks")
eq(overrides["1"], nil, "nor its keys")
GRF.Settings.SetRole("healer")
flush()
eq(c:GetAttribute("shift-spell1"), "Flash Heal", "back to healer: they return")
eq(overrides["1"], kb["1"]:GetName(), "keys too")
check(GlassRaidFramesCharDB.profiles.HEALER.bindings[1] ~= nil, "stored per character, per role")
eq(GlassRaidFramesDB.profiles.HEALER.bindings, nil, "never in the account-wide layout profiles")

-- An unknown spell (not learned on this character) is skipped and reported.
local ghost = CC.Set("shift-3", true, 99999)
flush()
eq(c:GetAttribute("shift-spell3"), nil, "an unknown spell isn't bound")
check(table.concat(CC.Warnings(ghost), ";"):find("unknown"), "and says so")

-- A macro over 255 characters never reaches its end (measured): refused.
SPELLS[4242] = { string.rep("Very Long Localized Spell Name ", 5), "Rank 9" }
local long = CC.Set("3", false, 4242, true)
flush()
eq(overrides["3"], nil, "a key whose macro wouldn't fit isn't bound")
check(table.concat(CC.Warnings(long), ";"):find("too long"), "and the options say why")

eq(next(GRF.paintFailures), nil, "no failures")
done("test_clickcast")
