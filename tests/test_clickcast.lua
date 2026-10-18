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
-- Keys are never bound permanently any more: only a hovered tile binds them.
local permanent = 0
rawset(_G, "SetOverrideBindingClick", function() permanent = permanent + 1 end)
local clears = 0
rawset(_G, "ClearOverrideBindings", function() clears = clears + 1 end)
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
-- Frames another addon registered in ClickCastFrames before we loaded (#61),
-- one of them switched off.
local earlyOn = CreateFrame("Button", "EarlyUF_player", UIParent, "SecureUnitButtonTemplate")
earlyOn:SetAttribute("unit", "player")
local earlyOff = CreateFrame("Button", "EarlyUF_party1", UIParent, "SecureUnitButtonTemplate")
earlyOff:SetAttribute("unit", "party1")
rawset(_G, "ClickCastFrames", { [earlyOn] = true, [earlyOff] = false })
GlassRaidFramesCharDB = { role = "HEALER" }
local GRF = loadAddon()
local CC = GRF.ClickCast

-- What hovering a tile binds: its OnEnter wrap run the way the restricted
-- environment runs it (control = the header's handle, self = the tile's;
-- RestrictedFrames.lua: SetBindingClick, ClearBindings, RunFor).
local function run(body, env)
    local f = assert(loadstring(body))
    setfenv(f, env)
    f()
end
-- Who the restricted UnitPlayerOrPetInParty/InRaid call a group member.
local inGroup = {}
local function hoverBinds(child)
    child = child or GRF.Header.children[1]
    local bound = {}
    local w = child._wraps and child._wraps.OnEnter
    if not w then return bound end
    local handle = {
        GetAttribute = function(_, k) return child:GetAttribute(k) end,
        SetBindingClick = function(_, priority, key, name)
            check(priority == true, "a hover key binds with priority")
            bound[key] = name
        end,
        ClearBindings = function() for k in pairs(bound) do bound[k] = nil end end,
    }
    local control = {
        GetAttribute = function(_, k) return w.header:GetAttribute(k) end,
        -- RestrictedFrames.lua HANDLE:RunFor: a non-string body is an error.
        RunFor = function(_, other, body)
            if type(body) ~= "string" then error("Invalid function body") end
            run(body, { self = other })
        end,
    }
    -- The restricted environment's functions the snippet uses
    -- (RestrictedEnvironment.lua: strmatch, rawtype... and the macro
    -- conditionals UnitPlayerOrPetInParty/InRaid). `type` is the managed
    -- environment's own.
    run(w.pre, { self = handle, control = control, type = type, strmatch = string.match,
                 UnitPlayerOrPetInParty = function(u) return inGroup[u] == "party" end,
                 UnitPlayerOrPetInRaid = function(u) return inGroup[u] == "raid" end })
    return bound, handle
end

-- Before any key row (a fresh character): hovering a tile binds nothing,
-- and doesn't throw (Codex P2 on #49: RunFor refuses a nil body).
local okH, errH = pcall(hoverBinds)
check(okH, "hovering with no key rows runs: " .. tostring(errH))
eq(next((okH and errH) or {}), nil, "and binds nothing")
-- A mouse-only profile: same.
CC.Set("shift-1", true, 2061)
flush()
okH, errH = pcall(hoverBinds)
check(okH, "hovering with mouse rows only runs: " .. tostring(errH))
eq(next((okH and errH) or {}), nil, "and binds no key")

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

-- Key rows: one secure button each, bound only while a GROUP tile is hovered
-- ([party]/[raid] read false in combat, measured: they can't keep strangers out).
local kb = CC._test.keyButtons
check(kb["1"] and kb["1"]._template == "SecureActionButtonTemplate", "key 1 has its own secure button")
eq(permanent, 0, "no key is bound permanently: off a tile it keeps its normal job")
local overrides, tile = hoverBinds()
eq(overrides["1"], kb["1"]:GetName(), "hovering a tile binds key 1 to it")
eq(overrides["SHIFT-R"], kb["SHIFT-R"]:GetName(), "and every other key")
tile:ClearBindings()
eq(GRF.Header.children[1]._wraps.OnLeave.pre, "self:ClearBindings()", "leaving the tile clears them")
eq(GRF.Header.children[1]._wraps.OnHide.pre, "self:ClearBindings()", "so does a tile hidden under the cursor")
eq(hoverBinds(childFor("party2"))["1"], kb["1"]:GetName(), "every group tile")
eq(GRF.Header.children[40]:GetAttribute(CC.HOVER_ATTR), true, "an empty tile is switched on too")
eq(next((hoverBinds(GRF.Header.children[40]))), nil, "but binds nothing until it shows someone")
check(GRF.Header.petChildren[1]._wraps, "pet tiles too (owner: pets heal like players)")
eq(CC._test.keyHeader()._template, "SecureHandlerBaseTemplate", "the wraps run against a secure handler")
local m1 = kb["1"]:GetAttribute("macrotext")
check(m1:find("/cast [@mouseover,help,nodead] Power Word: Shield", 1, true),
    "a living member under the cursor gets the spell")
check(not m1:find("party", 1, true), "no [party]/[raid] check (false in combat)")
check(m1:find("/click [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead] ActionButton1", 1, true),
    "anything else: the key's own action button (the exact complement)")
check(kb["3"]:GetAttribute("macrotext"):find("Greater Heal(Rank 2)", 1, true), "a pinned rank in a macro: Name(localized rank)")
local mr = kb["SHIFT-R"]:GetAttribute("macrotext")
check(mr:find("/cast [@mouseover,help,dead] Resurrection", 1, true), "a rez aims at DEAD members")
check(not mr:find("/click", 1, true), "an unbound key has no fallback line")
for key, b in pairs(kb) do
    check(#b:GetAttribute("macrotext") <= CC.MAX_MACRO, key .. "'s macro fits a macro")
end

-- A key bound to something that isn't an action button is left alone.
CC.Set("W", false, 139)
flush()
eq(hoverBinds()["W"], nil, "a key bound to MOVEFORWARD is not taken over")
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
eq(hoverBinds()["ALT-R"], nil, "a removed key is unbound")

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
eq(hoverBinds()["1"], nil, "nor its keys")
GRF.Settings.SetRole("healer")
flush()
eq(c:GetAttribute("shift-spell1"), "Flash Heal", "back to healer: they return")
eq(hoverBinds()["1"], kb["1"]:GetName(), "keys too")
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
eq(hoverBinds()["3"], nil, "a key whose macro wouldn't fit isn't bound")
check(table.concat(CC.Warnings(long), ";"):find("too long"), "and the options say why")

-- Capturing a binding that already exists keeps its spell (code review:
-- re-pressing Shift-R used to erase the rez).
local rez
for _, r in ipairs(CC.Rows()) do if r.key == "SHIFT-R" then rez = r end end
local again = CC.Set("SHIFT-R", false, nil)
eq(again, rez, "re-capturing returns the existing row")
eq(rez.spell, 2006, "and keeps its spell")
flush()
check(hoverBinds()["SHIFT-R"] ~= nil, "the rez key stays bound")

-- An unbound modified key falls back like the client does, to the plain
-- key: an action button there is clicked; any other command is only noted.
BASE.R = "ACTIONBUTTON5"
CC.Request(); flush()
check(kb["SHIFT-R"]:GetAttribute("macrotext"):find("ActionButton5", 1, true), "Shift-R falls back to what R does (bar slot 5)")
BASE.R = "REPLY"
CC.Request(); flush()
check(not kb["SHIFT-R"]:GetAttribute("macrotext"):find("/click", 1, true), "R bound to REPLY: no /click line")
check(hoverBinds()["SHIFT-R"] ~= nil, "the rez key is still bound")
check(table.concat(CC.Warnings(rez), ";"):find("REPLY"), "and the options say REPLY is lost off-frame")
BASE.R = nil

-- Every hover binds and clears, so UPDATE_BINDINGS fires all through combat:
-- it re-checks quietly, never raising "pending" (the options banner).
WoW.combat = true
CC.pending = false
WoW.fire("UPDATE_BINDINGS")
check(not CC.pending, "a hover's UPDATE_BINDINGS in combat isn't a pending change")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(#WoW.blocked, 0, "nothing protected was touched")
-- A key list change drops keys a hovered tile still holds (out of combat).
local before2 = clears
local frow = CC.Set("F", false, 139)
flush()
check(clears > before2, "a key list change clears the tiles' current bindings")
eq(hoverBinds()["F"], kb["F"]:GetName(), "and the next hover binds the new key")
CC.Remove(frow); flush()

-- A role change in combat marks the bindings pending at once (the old
-- role's stay installed until combat ends).
WoW.combat = true
CC.pending = false
GRF.Settings.SetRole("caster")
check(CC.pending, "a role change in combat is pending for click-casting")
check(hoverBinds()["1"] ~= nil, "the healer keys stay installed meanwhile")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(hoverBinds()["1"], nil, "switched when combat ends")
GRF.Settings.SetRole("healer"); flush()

-- Any unit frame (#61): Blizzard's, and every frame in Clique's
-- ClickCastFrames table, get the same rows.
local pf, tf, petf = PlayerFrame, TargetFrame, PetFrame
eq(tf:GetAttribute("shift-spell1"), "Flash Heal", "Blizzard's target frame: shift-click casts")
eq(pf:GetAttribute("ctrl-spell1"), 10963, "the player frame: the pinned rank")
eq(petf:GetAttribute("shift-type1"), "spell", "the pet frame: mouse rows too")
eq(type(ClickCastFrames), "table", "a ClickCastFrames table exists for other addons")
eq(earlyOn:GetAttribute("shift-type1"), "spell", "a frame registered before we loaded carries the rows")
eq(earlyOff:GetAttribute("shift-type1"), nil, "one registered as false doesn't")
eq(rawget(ClickCastFrames, earlyOff), nil, "its entry moved behind the table, false included")
ClickCastFrames[earlyOff] = true
WoW.flushTimers()
eq(earlyOff:GetAttribute("shift-type1"), "spell", "false -> true is seen (Codex P2 on #62)")
-- Another addon's frame, with its own shift-click, registered after load.
local other = CreateFrame("Button", "OtherUF_focus", UIParent, "SecureUnitButtonTemplate")
other:SetAttribute("unit", "focus")
other:SetAttribute("shift-type1", "focus")
ClickCastFrames[other] = true
eq(other:GetAttribute("shift-type1"), "focus", "nothing changes in the registering call")
WoW.flushTimers()
eq(other:GetAttribute("shift-type1"), "spell", "the next frame, it carries the rows")
eq(other:GetAttribute("shift-spell1"), "Flash Heal", "with the spell")
local shiftRow
for _, r in ipairs(CC.Rows()) do if r.mouse == "shift-1" then shiftRow = r end end
CC.Remove(shiftRow); flush()
eq(other:GetAttribute("shift-type1"), "focus", "a removed row gives the frame its own click back")
eq(other:GetAttribute("shift-spell1"), nil, "and leaves nothing of ours")
eq(tf:GetAttribute("shift-type1"), nil, "Blizzard's frame too")
CC.Set("shift-1", true, 2061); flush()
eq(other:GetAttribute("shift-type1"), "spell", "re-added")

-- Hover keys there: for you, a group member, or a pet of either (owner:
-- pets heal like players, on every frame).
eq(hoverBinds(pf)["1"], kb["1"]:GetName(), "the player frame binds the keys")
eq(next((hoverBinds(tf))), nil, "a target frame showing a stranger binds nothing")
inGroup.target = "party"
eq(hoverBinds(tf)["1"], kb["1"]:GetName(), "a party member on the target frame: bound")
inGroup.target = "raid"
eq(hoverBinds(tf)["1"], kb["1"]:GetName(), "a raid member: bound")
inGroup.focus = "party"
eq(hoverBinds(other)["SHIFT-R"], kb["SHIFT-R"]:GetName(), "a registered frame showing a member: bound")
eq(hoverBinds(petf)["1"], kb["1"]:GetName(), "your pet frame binds, solo too (by name)")
local petTile = GRF.Header.petChildren[1]
petTile:SetAttribute("unit", "partypet2")
eq(hoverBinds(petTile)["1"], kb["1"]:GetName(), "a party pet's tile binds (by name)")
petTile:SetAttribute("unit", "raidpet12")
eq(hoverBinds(petTile)["1"], kb["1"]:GetName(), "a raid pet's too")
petTile:SetAttribute("unit", nil)
inGroup.target = nil
eq(next((hoverBinds(tf))), nil, "a stranger's pet on the target frame: nothing (UnitPlayerOrPetInParty false)")
inGroup.target = "party"   -- a group pet as target: UnitPlayerOrPetInParty counts it
eq(hoverBinds(tf)["1"], kb["1"]:GetName(), "a group pet on the target frame: bound")
check(tf._wraps.OnLeave and tf._wraps.OnHide, "leaving or hiding a frame clears its keys")

-- Off: every other frame gets its own clicks back, our tiles keep theirs.
local beforeOff = clears
GRF.Settings.SetClickCastOthers(false); flush()
eq(GRF.db.clickCastOthers, false, "off is saved, account-wide")
eq(tf:GetAttribute("shift-type1"), nil, "Blizzard's frame: back to its own")
eq(other:GetAttribute("shift-type1"), "focus", "the other addon's: its own shift-click back")
eq(tf:GetAttribute(CC.HOVER_ATTR), nil, "hover keys switched off there (still wrapped: never unwrapped)")
eq(next((hoverBinds(tf))), nil, "so a hover binds nothing")
check(clears > beforeOff, "and a frame hovered right now drops its keys")
eq(childFor("party1"):GetAttribute("shift-type1"), "spell", "our tiles keep the rows")
eq(hoverBinds(childFor("party1"))["1"], kb["1"]:GetName(), "and the keys")
GRF.Settings.SetClickCastOthers(true); flush()
eq(GRF.db.clickCastOthers, nil, "on is the default: not saved")
eq(tf:GetAttribute("shift-type1"), "spell", "back on")
eq(hoverBinds(tf)["1"], kb["1"]:GetName(), "with the keys")

-- A frame registered in combat waits for combat to end, touching nothing.
local late = CreateFrame("Button", "OtherUF_target", UIParent, "SecureUnitButtonTemplate")
late:SetAttribute("unit", "target")
WoW.combat = true
ClickCastFrames[late] = true
WoW.flushTimers()
eq(late:GetAttribute("shift-type1"), nil, "in combat: not yet")
eq(#WoW.blocked, 0, "and nothing protected was touched")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(late:GetAttribute("shift-type1"), "spell", "when combat ends, it carries the rows")
-- Unregistering: the frame gets its own clicks back on the next frame.
ClickCastFrames[late] = false
eq(ClickCastFrames[late], nil, "read back: unregistered")
WoW.flushTimers()
eq(late:GetAttribute("shift-type1"), nil, "unregistered: back to its own")
ClickCastFrames[late] = true
WoW.flushTimers()
eq(late:GetAttribute("shift-type1"), "spell", "and true again is seen, with no other event")
check(ClickCastFrames[late], "read back through the table")

eq(next(GRF.paintFailures), nil, "no failures")
done("test_clickcast")
