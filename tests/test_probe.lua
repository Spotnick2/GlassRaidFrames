-- RaidProbe, a ForeverProbe module (#44): loaded on the host, driven through
-- /fp raid, its lines in the console and RaidProbeDB.log, never in chat.
-- Then its hover-key toggle (Codex review of PR #5): turning the mode off
-- must release a key a hovered tile still holds, and leaving a tile must
-- clean up whether or not the mode is still on.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Override bindings, as the client keeps them: key -> owning frame.
local bound = {}
rawset(_G, "SetOverrideBindingClick", function(owner, _, key) bound[key] = owner end)
rawset(_G, "ClearOverrideBindings", function(owner)
    for key, o in pairs(bound) do if o == owner then bound[key] = nil end end
end)
-- The rest of what the probe touches on these paths (all in the 70009 dump).
rawset(_G, "GetTime", function() return 0 end)
rawset(_G, "C_Spell", { GetSpellName = function(id) return id == 2050 and "Lesser Heal" or nil end })
rawset(_G, "UnitGroupRolesAssigned", function() return "NONE" end)   -- captured by the secrets table at load

WoW.SetUnit("player", { name = "Karuzo", class = "PRIEST", player = true })
local FP = loadForeverProbe()
local function rprobe(s) SlashCmdList.FOREVERPROBE("raid " .. s) end
-- Its SavedVariables from an earlier session (the client sets them before ADDON_LOADED).
rawset(_G, "RaidProbeDB", { log = { "1.0 an earlier session's line" }, sessions = 2 })
local ns = {}
assert(loadfile("Tools/RaidProbe/RaidProbe.lua"))("RaidProbe", ns)
local T = ns._test
check(rawget(_G, "RaidProbe_test") == nil, "the test seam stays off _G")
check(rawget(SlashCmdList, "RAIDPROBE") == nil, "no /rprobe any more: /fp raid")
eq(FP.byCmd.raid, T.Probe, "/fp raid is RaidProbe")
WoW.fire("ADDON_LOADED", "RaidProbe")
eq(type(RaidProbeDB.log), "table", "the probe keeps its log in saved variables")
check(T.Probe.log == RaidProbeDB.log, "its ForeverProbe log is RaidProbeDB.log, bound at ADDON_LOADED")
eq(RaidProbeDB.sessions, 3, "it counts its loads")
local function consoleHas(pattern)
    for _, l in ipairs(FP.lines) do
        if l.m == "RaidProbe" and l.text:find(pattern) then return true end
    end
    return false
end
local function logHas(pattern)
    for _, l in ipairs(RaidProbeDB.log) do if l:find(pattern) then return true end end
    return false
end
check(consoleHas("session 3, build"), "the load line reaches the console")
check(logHas("session 3, build"), "and the saved log")
check(logHas("an earlier session's line"), "the earlier session's lines are kept")
check(not consoleHas("EARLY"), "the host was ready before RaidProbe's ADDON_LOADED")
check(not chatHas("session"), "nothing in chat")
local key = T.HOVER_KEY

local tile = CreateFrame("Button", "RaidProbe_party1", UIParent, "SecureUnitButtonTemplate")
tile.unit = "party1"
table.insert(T.order, tile)

local function enter() tile._scripts.OnEnter(tile) end
local function leave() tile._scripts.OnLeave(tile) end

-- On, hover: the key belongs to the tile.
T.hoverKeys()
check(T.P.hover, "hover keys on")
eq(tile:GetAttribute("spell-key8"), "Lesser Heal", "the tile casts the test spell on the virtual key8 button")
enter()
eq(bound[key], tile, "hovering binds the key to the tile")

-- Codex's sequence: turn the mode off while still hovering, then leave.
T.hoverKeys()
check(not T.P.hover, "hover keys off")
eq(bound[key], nil, "turning the mode off releases the key the hovered tile held")
leave()
eq(bound[key], nil, "leaving afterwards keeps it released")

-- Normal use: on, hover, leave.
T.hoverKeys()
enter()
eq(bound[key], tile, "hovering binds again once the mode is back on")
leave()
eq(bound[key], nil, "leaving releases the key")

-- Off: hovering binds nothing.
T.hoverKeys()
enter()
eq(bound[key], nil, "with the mode off, hovering binds nothing")

-- In combat the toggle is refused and changes nothing.
T.hoverKeys()
enter()
WoW.combat = true
T.hoverKeys()
check(T.P.hover, "the toggle is refused in combat")
eq(bound[key], tile, "and the key stays where it was")
WoW.combat = false

WoW.combat = false
leave()
T.hoverKeys()

-- The indicator probe (#19): every subcommand runs offline without touching an
-- unstubbed global or failing a call (the client parts are stubbed here).
rawset(_G, "C_Secrets", { GetSpellAuraSecrecy = function() return 0 end })
rawset(_G, "C_UnitAuras", {
    GetAuraDataByIndex = function(unit, i, filter)
        if i > 1 then return nil end
        return { name = "Renew", spellId = 139, sourceUnit = "player", duration = 15, auraInstanceID = 7 }
    end,
    IsAuraFilteredOutByInstanceID = function(unit, id, filter) return filter:find("RAID", 1, true) ~= nil end,
})
C_Spell.GetSpellSubtext = function() return "Rank 1" end
rawset(_G, "AnchorUtil", { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 } })
rawset(_G, "debugprofilestop", function() return 0 end)
-- A failed call is the host's Try line: "label: ERROR msg" or "label: MISSING".
local function failures()
    local n = 0
    for _, l in ipairs(FP.lines) do
        if l.m == "RaidProbe" and (l.text:find(": ERROR", 1, true) or l.text:find(": MISSING", 1, true)) then n = n + 1 end
    end
    return n
end
local before = failures()
for _, cmd in ipairs({ "ind", "ind party1", "ind reconf", "ind reconf", "ind src", "ind src party1", "ind state", "ind cost", "ind ids" }) do
    local ok, err = pcall(rprobe, cmd)
    check(ok, "/fp raid " .. cmd .. " runs: " .. tostring(err))
end
eq(failures() - before, 0, "no probe call failed")
eq(#T.P.indContainers, 8, "the panel has its 8 test containers")
eq(T.P.indUnit, "party1", "ind <unit> rebinds the panel")
check(consoleHas("RAID_IN_COMBAT=out"), "src reports which filters keep each aura")
check(consoleHas("cost: 40 tiles"), "cost reports its build")
check(consoleHas("state 6: slot 1 shown="), "state reports each stacked slot")
check(consoleHas("state 1: .* shown, .* hidden, .* unknown"), "state reports each row group")
check(logHas("cost: 40 tiles"), "the lines are saved too")

-- Codex review of #20: a secret shown state is unknown, never "hidden".
local hots = T.P.indByKey.RP_IND_HOTS
local frames = { { IsShown = function() return WoW.Secret("shown") end },
                 { IsShown = function() return WoW.Secret("shown") end },
                 { IsShown = function() return false end } }
hots.GetAuraGroupFrameCount = function() return #frames end
hots.GetAuraGroupFrame = function(_, _, i) return frames[i] end
rprobe("ind state")
check(consoleHas("state 1: 3 buttons: 0 shown, 1 hidden, 2 unknown"), "secret reads count as unknown, a plain false as hidden")
hots.GetAuraGroupFrameCount, hots.GetAuraGroupFrame = nil, nil

-- The button look the client would apply (initializeFrame).
local button = CreateFrame("Button", nil, UIParent)
T.indButton(16, 30, { 1, 0, 0 }, UIParent)(button)
T.indButton(16)(button)
eq(failures() - before, 0, "the probe button initialiser runs cleanly")

-- A throwing call is reported, not raised: the host's Try contract.
rprobe("ind")   -- the panel exists; make one of its calls throw
local realSetUnit = T.P.indContainers[1].SetUnit
T.P.indContainers[1].SetUnit = function() error("boom") end
rprobe("ind party2")
T.P.indContainers[1].SetUnit = realSetUnit
check(failures() > before, "a throwing client call is logged as ERROR")

-- The command list, and clearing the log in place.
newChat()
rprobe("")
check(consoleHas("/fp raid <command>:") and consoleHas("  ind %- "), "/fp raid alone lists the commands")
local log = RaidProbeDB.log
rprobe("log clear")
check(RaidProbeDB.log == log, "log clear keeps the bound table")
eq(#log, 1, "and empties it in place, then logs the clear")
check(logHas("log cleared") and consoleHas("log cleared"), "the line after a clear is in both")
check(#WoW.chat == 0, "nothing reached chat")

-- worldkey (#63): a check passes only on a press that reached the key's
-- button, under lockdown for the combat steps (Codex P2 on #64: no press,
-- or none in combat, used to pass the fallback step).
C_Spell.IsSpellHarmful = function(id) return id == 589 end
C_Spell.IsSpellHelpful = function(id) return id == 2050 end
local realName = C_Spell.GetSpellName
C_Spell.GetSpellName = function(id) return (id == 589 or id == 594) and "Shadow Word: Pain" or realName(id) end
rawset(_G, "C_SpellBook", { IsSpellKnown = function(id) return id == 589 or id == 2050 end })
check(T.worldSetup(), "worldkey binds a harmful and a helpful key")
local fallback = T.worldCheck("harm", "other", true)
check(not fallback(), "no press: the in-combat fallback step fails")
local harmKey = _G["RaidProbeWorldKeyharm"]
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
check(not fallback(), "a press out of combat: still fails")
WoW.combat = true
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
check(fallback(), "a press in combat with nothing cast: passes")
check(not fallback(), "and the next step starts from zero presses")
-- Run #188 (rev 2 failed both): the bare name casts the highest rank (594),
-- and the owner's own heal came after it. Any cast of the step counts, at
-- any rank, and a failed one too (out of range: the macro chose the spell).
local cast = T.worldCheck("harm", "spell", true)
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-1", 594)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo Mistwalker", "guid-2", 2050)
check(cast(), "a press in combat that sent the key's spell at another rank, then a heal: passes")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "guid-3", 594)
check(cast(), "a failed cast of the key's spell: the macro still chose it")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo Mistwalker", "guid-4", 2050)
check(not cast(), "another spell only: the key's spell wasn't chosen")
check(fallback() == false, "and an empty step still fails")
WoW.combat = false
local outside = T.worldCheck("harm", "spell")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.combat = true
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-5", 594)
WoW.combat = false
check(outside(), "an out-of-combat step accepts any cast")
WoW.combat = true
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.combat = false
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-6", 594)
WoW.combat = true
check(not cast(), "an in-combat step ignores a cast sent outside combat")
WoW.combat = false

done("test_probe")
