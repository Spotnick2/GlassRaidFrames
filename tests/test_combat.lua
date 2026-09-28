-- Combat lockdown: building, moving and toggling wait for combat to end;
-- roster changes in combat touch nothing protected.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- ADDON_LOADED under lockdown (a /reload in combat): the build waits.
party(2)
WoW.combat = true
local GRF = loadAddon()
eq(GRF.Header.container, nil, "no frames are built under lockdown")
check(chatHas("frames will appear when combat ends"), "and it says so")
eq(#WoW.blocked, 0, "nothing protected was touched")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
flush()
eq(#GRF.Header.children, 40, "combat ends: the frames are built")
check(childFor("party2") and childFor("party2").nameText._text == "Member 2", "and painted")

-- In combat: members leave and join, the group converts; the header does it.
WoW.combat = true
WoW.blocked = {}
WoW.SetUnit("party2", nil)
WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); flush()
eq(childFor("party2"), nil, "a member leaving in combat loses their frame")
raid(7)
WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); flush()
check(childFor("raid6") ~= nil, "raid members appear in combat")
WoW.fireAllRegistered(); flush(); WoW.tick(0.3)
eq(#WoW.blocked, 0, "no protected frame touched by any event in combat ("
    .. table.concat(WoW.blocked, ", ") .. ")")

-- The container itself refuses to move in combat (a protected frame).
check(not GRF.Header.SetPosition(10, 10, true), "the grid refuses to move in combat")
eq(#WoW.blocked, 0, "without touching the protected container")

-- Unlock, reset and the solo toggle wait for combat.
check(not GRF.Movers.Unlock(), "unlock is refused in combat")
SlashCmdList.GLASSRAIDFRAMES("reset")
SlashCmdList.GLASSRAIDFRAMES("solo")
eq(GRF.Header.headers[1]:GetAttribute("showSolo"), false, "showSolo waits for combat to end")
eq(#WoW.blocked, 0, "the slash commands touched nothing protected in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GRF.Header.headers[1]:GetAttribute("showSolo"), true, "and applies after")

-- One header failing to build doesn't cost the other groups or the Blizzard
-- hide (code review): the failure is recorded, the rest is built.
WoW.reset()
party(1)
local realCreate = CreateFrame
rawset(_G, "CreateFrame", function(ftype, name, ...)
    if name == "GlassRaidFramesGroup3" then error("refused") end
    return realCreate(ftype, name, ...)
end)
local pf = realCreate("Frame", "PartyFrame", UIParent, "SecureFrameTemplate")
GRF = loadAddon()
rawset(_G, "CreateFrame", realCreate)
eq(GRF.Header.headers[3], nil, "the failing group has no header")
check(GRF.Header.headers[4] ~= nil, "the groups after it are built")
eq(#GRF.Header.children, 35, "35 of 40 children exist")
check(GRF.paintFailures["header 3"], "the failure is recorded")
eq(pf:GetParent(), GRF.Blizzard.hiddenParent, "Blizzard's frames are still hidden")

done("test_combat")
