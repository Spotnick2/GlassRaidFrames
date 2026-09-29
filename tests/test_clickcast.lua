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
-- Learned spells (C_SpellBook.IsSpellKnown). A name alone proves nothing.
local LEARNED = { [2061] = true, [2060] = true, [10963] = true, [139] = true, [2006] = true, [17] = true }
rawset(_G, "C_SpellBook", { IsSpellKnown = function(id) return LEARNED[id] == true end })
Enum.SpellBookSpellBank = { Player = 0 }
-- Base key bindings (what the player bound) and our overrides.
local BASE = { ["1"] = "ACTIONBUTTON1", ["3"] = "ACTIONBUTTON3", ["SHIFT-R"] = nil, W = "MOVEFORWARD" }
rawset(_G, "GetBindingAction", function(key, checkOverride) return BASE[key] end)
local overrides, clears = {}, 0
local refuse = {}
rawset(_G, "SetOverrideBindingClick", function(owner, _, key, name)
    if refuse[key] then error("refused " .. key) end
    overrides[key] = name
end)
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

-- A spell the client names but this character hasn't learned is saved,
-- not installed, and flagged (Codex review: GetSpellName answers for
-- unlearned spells too).
SPELLS[25314] = { "Greater Heal", "Rank 4" }
local unlearned = CC.Set("shift-5", true, 25314, true)
flush()
eq(c:GetAttribute("shift-spell5"), nil, "an unlearned spell is not installed")
check(table.concat(CC.Warnings(unlearned), ";"):find("not learned"), "the row says it isn't learned")
check(#CC.Rows() > 0 and unlearned.spell == 25314, "the row itself is kept")
-- A respec: a bound, learned spell is lost; SPELLS_CHANGED clears it.
local lost = CC.Set("shift-4", true, 139)
flush()
eq(c:GetAttribute("shift-spell4"), "Renew", "bound while learned")
LEARNED[139] = nil
WoW.fire("SPELLS_CHANGED"); flush()
eq(c:GetAttribute("shift-spell4"), nil, "unlearned by a respec: the stale click is cleared")
check(table.concat(CC.Warnings(lost), ";"):find("not learned"), "and flagged")
LEARNED[139] = true
CC.Remove(lost); CC.Remove(unlearned); flush()

-- A macro over 255 characters never reaches its end (measured): refused.
SPELLS[4242] = { string.rep("Very Long Localized Spell Name ", 5), "Rank 9" }
LEARNED[4242] = true
local long = CC.Set("3", false, 4242, true)
flush()
eq(overrides["3"], nil, "a key whose macro wouldn't fit isn't bound")
check(table.concat(CC.Warnings(long), ";"):find("too long"), "and the options say why")

-- Capturing a binding that already exists keeps its spell (code review:
-- re-pressing Shift-R used to erase the rez).
local rez
for _, r in ipairs(CC.Rows()) do if r.key == "SHIFT-R" then rez = r end end
local again = CC.Set("SHIFT-R", false, nil)
eq(again, rez, "re-capturing returns the existing row")
eq(rez.spell, 2006, "and keeps its spell")
flush()
check(overrides["SHIFT-R"] ~= nil, "the rez key stays bound")

-- An unbound modified key falls back like the client does, to the plain
-- key: an action button there is clicked; any other command is only noted.
BASE.R = "ACTIONBUTTON5"
CC.Request(); flush()
check(kb["SHIFT-R"]:GetAttribute("macrotext"):find("ActionButton5", 1, true), "Shift-R falls back to what R does (bar slot 5)")
BASE.R = "REPLY"
CC.Request(); flush()
check(not kb["SHIFT-R"]:GetAttribute("macrotext"):find("/click", 1, true), "R bound to REPLY: no /click line")
check(overrides["SHIFT-R"] ~= nil, "the rez key is still bound")
check(table.concat(CC.Warnings(rez), ";"):find("REPLY"), "and the options say REPLY is lost off-frame")
BASE.R = nil

-- A key the client refuses isn't recorded as installed: retried later.
refuse["F"] = true
local frow = CC.Set("F", false, 139)
flush()
eq(overrides.F, nil, "a refused key isn't bound")
check(table.concat(CC.Warnings(frow), ";"):find("refused"), "and says so")
refuse["F"] = nil
WoW.fire("SPELLS_CHANGED"); flush()
check(overrides.F ~= nil, "the next reconciliation retries it")
GRF.paintFailures["bind F"] = nil
CC.Remove(frow); flush()

-- A role change in combat marks the bindings pending at once (the old
-- role's stay installed until combat ends).
WoW.combat = true
CC.pending = false
GRF.Settings.SetRole("caster")
check(CC.pending, "a role change in combat is pending for click-casting")
check(overrides["1"] ~= nil, "the healer keys stay installed meanwhile")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(overrides["1"], nil, "switched when combat ends")
GRF.Settings.SetRole("healer"); flush()

eq(next(GRF.paintFailures), nil, "no failures")
done("test_clickcast")
