-- Bootstrap: saved settings, the combat queue, the login build warning and
-- the /grf command.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables (the pre-70009 client lost them) still load.
GlassRaidFramesDB = nil
local GRF = loadAddon()
eq(type(GlassRaidFramesDB), "table", "missing saved variables become a table")
eq(GRF.db, GlassRaidFramesDB, "the addon keeps the saved table")
check(not chatHas("newer than"), "no build warning on the measured build")

-- The combat queue: deferred in combat, ordered, a repeated key keeps its
-- slot with the newest function, the build first, run on PLAYER_REGEN_ENABLED.
local ran = {}
WoW.combat = true
GRF.WhenOutOfCombat("a", function() ran[#ran + 1] = "a1" end, false)
GRF.WhenOutOfCombat("b", function() ran[#ran + 1] = "b" end, false)
GRF.WhenOutOfCombat("a", function() ran[#ran + 1] = "a2" end, false)
GRF.WhenOutOfCombat("build", function() ran[#ran + 1] = "build" end)
check(chatHas("when combat ends"), "a deferred action says so")
eq(#ran, 0, "nothing runs in combat")
WoW.fire("PLAYER_REGEN_ENABLED")   -- still locked: the event alone is not trusted
eq(#ran, 0, "an early PLAYER_REGEN_ENABLED under lockdown runs nothing")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(table.concat(ran, ","), "build,a2,b", "build first, then in order, newest function per key")
ran = {}
WoW.fire("PLAYER_REGEN_ENABLED")
eq(#ran, 0, "the queue empties once run")
GRF.WhenOutOfCombat("now", function() ran[#ran + 1] = "now" end)
eq(ran[1], "now", "out of combat an action runs at once")

-- /grf
newChat()
SlashCmdList.GLASSRAIDFRAMES("")
check(#newChat() >= 2, "/grf prints help")
SlashCmdList.GLASSRAIDFRAMES("failures")
local lines = newChat()
check(lines[1] and lines[1]:find("no failures"), "/grf failures reports none")
SlashCmdList.GLASSRAIDFRAMES("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70009", 1, true), "/grf version names the measured build")

done("test_boot")
