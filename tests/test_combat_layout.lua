-- Combat lockdown with the group layout (#69) on: building, moving and every
-- setting wait for combat to end; roster changes, pets, a role change,
-- click-cast toggles and a spellbook change in combat touch nothing
-- protected, in either order of the roster event and the header's own update.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Click-casting rows need spells, learned ones, a base binding and a bar.
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return id == 139 and "Renew" or id == 2061 and "Flash Heal" or nil end,
    GetSpellSubtext = function() return "Rank 1" end,
    IsSpellHarmful = function() return false end, IsSpellHelpful = function() return true end,
})
rawset(_G, "C_SpellBook", { IsSpellKnown = function(id) return id == 139 or id == 2061 end })
Enum.SpellBookSpellBank = { Player = 0 }
rawset(_G, "GetBindingAction", function(key) return key == "1" and "ACTIONBUTTON1" or nil end)
rawset(_G, "GetModifiedClick", function() return "NONE" end)
local bar = { actionButtons = {} }
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.commandName = "ACTIONBUTTON" .. i
    bar.actionButtons[i] = b
end
rawset(_G, "MainActionBar", bar)
UIParent._width, UIParent._height = 1920, 1080
GlassRaidFramesCharDB = { role = "HEALER", profiles = { HEALER = { bindings = {
    { key = "1", spell = 139 }, { mouse = "shift-1", spell = 2061 } } } } }

-- ADDON_LOADED under lockdown (a /reload in combat): the build waits.
party(2)
WoW.combat = true
local GRF = loadAddon({ layout = true })
eq(GRF.Header.container, nil, "no frames are built under lockdown")
eq(#WoW.blocked, 0, "nothing protected was touched")
WoW.leaveCombat()
WoW.flushTimers(); flush()
eq(#GRF.Header.children, 40, "combat ends: the grid is built")
check(childFor("party2") and childFor("party2").nameText._text == "Member", "and painted")
local L = GRF.Layout._test.L
eq(L.set, GRF.Layout.ROW, "a party: the row")

-- In combat: members leave, the group converts to a raid, pets come and go;
-- the header does it, in both orders of the roster event and its own update.
local function roster(eventFirst, ...)
    if eventFirst then WoW.fire("GROUP_ROSTER_UPDATE"); WoW.layoutHeaders()
    else WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE") end
    for _, u in ipairs({ ... }) do WoW.fire("UNIT_PET", u) end
    WoW.flushTimers(); flush()
end
WoW.enterCombat()
WoW.blocked = {}
WoW.SetUnit("party2", nil)
roster(false)
eq(childFor("party2"), nil, "a member leaving in combat loses their cell")
raid(7)
WoW.SetUnit("raidpet3", { name = "Imp", class = "WARLOCK" })
roster(true, "raid3")
check(childFor("raid6") ~= nil, "raid members appear in combat")
eq(L.set, GRF.Layout.ROW, "the set stays until combat ends (both sets list everyone)")
WoW.SetUnit("raidpet3", nil)
roster(false, "raid3")
WoW.fireAllRegistered(); flush(); WoW.tick(0.3)
eq(#WoW.blocked, 0, "no protected frame touched by any event in combat (" .. table.concat(WoW.blocked, ", ") .. ")")

-- Nothing of ours moves or changes in combat: every setting waits.
check(not GRF.Header.SetPosition(10, 10, false), "the grid refuses to move in combat")
check(not GRF.Movers.Unlock(), "unlock is refused in combat")
local okP = GRF.Settings.Preview(10)
check(not okP, "no preview in combat")
GRF.Settings.Preview(nil)                        -- "End preview" in combat: nothing to end, nothing protected
GRF.Settings.SetLayoutMode("side")
GRF.Settings.SetShowSolo(true)
GRF.Settings.SetShowPets(true)
GRF.Settings.SetSize(90, 50)
SlashCmdList.GLASSRAIDFRAMES("reset")
GRF.Settings.SetRole("tank")                     -- a role change in combat
eq(GRF.role, "TANK", "the role is known at once")
GRF.Settings.SetClickCastOthers(false)
GRF.Settings.SetKeysAnywhere(true)
WoW.fire("SPELLS_CHANGED")
WoW.fire("UPDATE_BINDINGS")
check(GRF.ClickCast.pending, "click-casting waits for combat to end")
check(GRF.Indicators.pending, "so do the indicators")
WoW.flushTimers(); flush()
eq(#WoW.blocked, 0, "the settings touched nothing protected in combat (" .. table.concat(WoW.blocked, ", ") .. ")")
eq(L.set, GRF.Layout.ROW, "the set didn't change in combat")
eq(L.cells[1]._width, 96, "nor the cells")

-- After combat: everything applies, once, with nothing blocked.
WoW.leaveCombat()
WoW.flushTimers(); flush()
eq(#WoW.blocked, 0, "nothing blocked after combat either")
eq(L.set, GRF.Layout.COLUMNS, "a raid of 7: the columns")
-- The settings asked in combat belonged to the healer (the role then); the
-- tank's own profile shows now (a setting never lands on a later role).
eq(GRF.db.profiles.HEALER.size.w, 90, "the size was saved for the healer, who asked")
eq(GRF.db.profiles.HEALER.layout, "side", "so was the layout")
eq(GRF.db.profiles.HEALER.showPets, true, "and the pets")
eq(L.cells[1]._width, 96, "the tank's cells are at its own default")
check(not L.pets:IsShown(), "the tank's pets are off")
check(not GRF.ClickCast.pending and not GRF.Indicators.pending, "click-casting and indicators reconciled")
eq(GRF.ClickCast.Anywhere("TANK"), true, "keys anywhere for the tank")

done("test_combat_layout")
