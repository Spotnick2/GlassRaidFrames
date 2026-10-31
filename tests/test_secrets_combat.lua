-- A raid of 40 in combat with every identity value secret (what the 70532
-- API docs say can be: UnitName, UnitClass, UnitGUID, roles, leader and
-- assistant, the raid mark, UnitIsUnit): every event fires, every painter
-- runs, and nothing throws, nothing protected is touched, and the tiles show
-- the secret names whole (#78 F1, H4). Then the secrets lift and the names
-- come back plain.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

UIParent._width, UIParent._height = 1920, 1080
GlassRaidFramesCharDB = { role = "HEALER" }
raid(40)
for i = 1, 40 do
    local u = WoW.units["raid" .. i]
    u.name = "Raider Surname" .. i
    u.role = (i % 5 == 0) and "HEALER" or (i % 7 == 0) and "TANK" or "DAMAGER"
    u.leader, u.assistant = i == 1, i == 2
    u.raidTarget = (i % 8) + 1
    u.class = ({ "WARRIOR", "PRIEST", "MAGE", "DRUID" })[(i % 4) + 1]
    if i % 3 == 0 then WoW.SetUnit("raidpet" .. i, { name = "Pet " .. i, class = "HUNTER", player = false }) end
end
WoW.SetUnit("target", WoW.units.raid5)
local GRF = loadAddon({ layout = true, db = { profiles = { HEALER = { showPets = true } } } })
WoW.flushTimers(); flush()
local L = GRF.Layout._test.L
eq(L.set, GRF.Layout.COLUMNS, "a raid of 40: the columns")
check(childFor("raid40") ~= nil, "every raider has a cell")
eq(childFor("raid7").nameText._text, "Raider", "plain: the first name")

-- The pull: the identity values go secret, the roster churns, everything fires.
WoW.enterCombat()
WoW.blocked = {}
WoW.secretFields = { name = true, class = true, guid = true, role = true, leader = true, assistant = true,
                     raidTarget = true, isUnit = true }
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.layoutHeaders(); WoW.flushTimers(); flush()
WoW.SetUnit("raid40", nil); WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); WoW.flushTimers(); flush()
WoW.fireAllRegistered(); flush(); WoW.tick(0.3); flush()
local keys = {}
for k in pairs(GRF.paintFailures) do keys[#keys + 1] = k end
eq(#keys, 0, "no painter failed on a secret value (" .. table.concat(keys, ", ") .. ")")
eq(#WoW.blocked, 0, "nothing protected touched (" .. table.concat(WoW.blocked, ", ") .. ")")
local shown, secret = 0, 0
for _, c in ipairs(GRF.Header.AllChildren()) do
    if c.unit and c:IsShown() then
        shown = shown + 1
        if WoW.IsSecret(c.nameText._text) then secret = secret + 1 end
    end
end
check(shown >= 39, "the raid is shown (" .. shown .. ")")
eq(secret, shown, "every shown tile got its secret name whole")
-- The full style in combat: both returns formatted by the client, never
-- joined in Lua (Codex on #80).
GRF.Settings.SetNameStyle("full"); flush()
local formatted = 0
for _, c in ipairs(GRF.Header.AllChildren()) do
    local t = c.unit and c:IsShown() and c.nameText._text
    if type(t) == "table" and t.secretFormat == "%s%s%s" and WoW.IsSecret(t.args[1]) and WoW.IsSecret(t.args[3]) then
        formatted = formatted + 1
    end
end
eq(formatted, shown, "full style: every shown tile got first name and surname through SetFormattedText")
GRF.Settings.SetNameStyle("first"); flush()
eq(childFor("raid1").indicators.leader._shown, false, "a secret leader flag: no icon, no guess")
check(childFor("raid7").health._color ~= nil, "a secret class: the fallback colour, no throw")

-- The fight ends and the secrets lift: plain names again, nothing pending failed.
WoW.leaveCombat()
WoW.secretFields = {}
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.layoutHeaders(); WoW.flushTimers(); flush()
eq(childFor("raid7").nameText._text, "Raider", "plain again")
eq(childFor("raid1").indicators.leader._shown, true, "the leader icon is back")
eq(next(GRF.paintFailures), nil, "still no failure")

done("test_secrets_combat")
