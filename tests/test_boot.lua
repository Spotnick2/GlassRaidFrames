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
local timers = #WoW.timers
WoW.fire("PLAYER_REGEN_ENABLED")   -- still locked: the event alone is not trusted
eq(#ran, 0, "an early PLAYER_REGEN_ENABLED under lockdown runs nothing")
eq(#WoW.timers, timers + 1, "but arms one retry (#78 F3)")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(#WoW.timers, timers + 1, "one retry, however many events")
WoW.flushTimers()
eq(#ran, 0, "still locked when it fires: nothing runs")
eq(#WoW.timers, 1, "and it re-arms")
WoW.combat = false
WoW.flushTimers()
eq(table.concat(ran, ","), "build,a2,b", "unlocked: build first, then in order, newest function per key")
eq(#WoW.timers, 0, "and the retry stops")
ran = {}
WoW.fire("PLAYER_REGEN_ENABLED")
eq(#ran, 0, "the queue empties once run")
GRF.WhenOutOfCombat("now", function() ran[#ran + 1] = "now" end)
eq(ran[1], "now", "out of combat an action runs at once")

-- One queued action throwing is recorded; the rest still run (code review).
ran = {}
WoW.combat = true
GRF.WhenOutOfCombat("boom", function() error("kaboom") end, false)
GRF.WhenOutOfCombat("after", function() ran[#ran + 1] = "after" end, false)
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(ran[1], "after", "an action after a failing one still runs")
check(GRF.paintFailures["queued boom"] and GRF.paintFailures["queued boom"]:find("kaboom"),
    "the failure is recorded")
check(chatHas("this fight: 1 failure"), "and said once after the fight (#78 F4)")
GRF.paintFailures["queued boom"] = nil

-- The client refusing a protected call blames an addon (ADDON_ACTION_BLOCKED
-- / FORBIDDEN): ours are counted by function and recorded for /grf failures,
-- with one line after the fight; a quiet fight says nothing (#78 F4).
newChat()
WoW.enterCombat(); WoW.leaveCombat()
eq(#newChat(), 0, "a quiet fight says nothing")
WoW.enterCombat()
WoW.fire("ADDON_ACTION_BLOCKED", "GlassRaidFrames", "SetPoint")
WoW.fire("ADDON_ACTION_BLOCKED", "GlassRaidFrames", "SetPoint")
WoW.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName")
eq(GRF.blocked.SetPoint, 2, "blocked calls are counted by function")
eq(GRF.blocked.CastSpellByName, nil, "another addon's aren't ours")
check(GRF.paintFailures["blocked SetPoint"] ~= nil, "and recorded for /grf failures")
check(not chatHas("this fight: 2"), "nothing said during the fight")
WoW.leaveCombat()
check(chatHas("this fight: 2 protected actions refused %(/grf failures%)"), "one line after the fight")
newChat()
SlashCmdList.GLASSRAIDFRAMES("failures")
check(chatHas("blocked SetPoint %(x2%): refused by the client in combat"), "/grf failures shows the count")
GRF.paintFailures["blocked SetPoint"] = nil

-- /grf
newChat()
SlashCmdList.GLASSRAIDFRAMES("")
check(#newChat() >= 2, "/grf prints help")
SlashCmdList.GLASSRAIDFRAMES("failures")
local lines = newChat()
check(lines[1] and lines[1]:find("no failures"), "/grf failures reports none")
SlashCmdList.GLASSRAIDFRAMES("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70338", 1, true), "/grf version names the measured build")

done("test_boot")
