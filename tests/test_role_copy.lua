-- Talents switching the role (#84): points add up per role, and landing on a
-- role with no click-cast bindings offers to copy the old role's, once.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The measured canvas (FOREVER-PROBE item 9), as in test_role.lua.
local COLUMNS = { { 1020, 1620, 2220, 2820 }, { 5020, 5620, 6220, 6820 }, { 9080, 9680, 10280, 10880 } }
local ranks = { 0, 0, 0 }

local function nodes()
    local list, info = {}, {}
    local id = 100
    for tree, xs in ipairs(COLUMNS) do
        for i, x in ipairs(xs) do
            id = id + 1
            list[#list + 1] = id
            info[id] = { ID = id, posX = x, posY = 2130 + 600 * i, isVisible = true,
                         currentRank = (i == 1) and ranks[tree] or 0 }
        end
    end
    return list, info
end
rawset(_G, "C_ClassTalents", { GetActiveConfigID = function() return 88388 end })
rawset(_G, "C_Traits", {
    GetConfigInfo = function(id) return { ID = id, treeIDs = { 1114 } } end,
    GetTreeNodes = function() return (nodes()) end,
    GetNodeInfo = function(_, nodeID) local _, info = nodes(); return info[nodeID] end,
})

-- Pure: the trees of one role add up; ties go to the leftmost role.
dofile("Role.lua")
local Role = GlassRaidFrames.Role
local PRIEST, WARRIOR = Role.TREES.PRIEST, Role.TREES.WARRIOR
eq(Role.FromPoints(PRIEST, { 3, 3, 5 }), "HEALER", "Discipline + Holy (6) beat Shadow (5)")
eq(Role.FromPoints(PRIEST, { 0, 0, 5 }), "CASTER", "Shadow alone: caster")
eq(Role.FromPoints(PRIEST, { 2, 1, 3 }), "HEALER", "a tie goes to the leftmost role")
eq(Role.FromPoints(PRIEST, { 0, 0, 0 }), nil, "no points: no answer")
eq(Role.FromPoints(WARRIOR, { 6, 6, 10 }), "MELEE", "Arms + Fury (12) beat Protection (10)")
eq(Role.FromPoints(Role.TREES.PALADIN, { 1, 5, 2 }), "TANK", "one role per tree: the biggest tree")

-- A leveling priest: healer bindings, then points that used to flip it.
WoW.reset()
local SPELLS = { [2050] = { "Lesser Heal", "Rank 1" }, [2053] = { "Lesser Heal", "Rank 3" },
                 [17] = { "Power Word: Shield", "Rank 1" }, [139] = { "Renew", "Rank 1" } }
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] end,
    GetSpellSubtext = function(id) return SPELLS[id] and SPELLS[id][2] end,
    IsSpellHarmful = function() return false end,
    IsSpellHelpful = function() return true end,
})
rawset(_G, "C_SpellBook", { IsSpellKnown = function(id) return SPELLS[id] ~= nil end })
Enum.SpellBookSpellBank = { Player = 0 }
rawset(_G, "GetBindingAction", function() return nil end)
party(1)
ranks = { 3, 0, 0 }
GlassRaidFramesCharDB = { role = "auto", talentRole = "HEALER", profiles = { HEALER = { bindings = {
    { key = "3", spell = 2050 }, { key = "1", spell = 17 }, { mouse = "ctrl-1", spell = 139, action = "spell" },
} } } }
local GRF = loadAddon()
local CCO = GRF.ClickCastOptions
eq(GRF.role, "HEALER", "Discipline points: healer")
ranks = { 3, 2, 4 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "4 in Shadow no longer beat 3 + 2 in Discipline and Holy (#84)")
check(CCO._test.notice() == nil, "no role change, no notice")

-- Shadow takes over: the caster list is empty, so the notice offers a copy.
newChat()
ranks = { 3, 2, 6 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "CASTER", "6 Shadow beat 5: caster")
local notice = CCO._test.notice()
check(notice and notice:IsShown(), "the notice is shown")
eq(notice.from, "HEALER", "from the healer list")
eq(notice.to, "CASTER", "to the caster one")
check(notice.title:GetText():find("Caster %(was Healer%)"), "its title names both roles")
check(notice.text:GetText():find("Healer has 3"), "and how many bindings the old role has")
check(notice.text:GetText():find("anywhere under the cursor"), "and that caster keys work off the frames")
eq(notice.copy.text:GetText(), "Copy Healer's", "the copy button names the role")
local lines = table.concat(newChat(), "\n")
check(lines:find("/grf clickcast copy healer"), "chat names the command")
check(not lines:find("role: caster %(talents%)"), "one chat line, not two")
eq(#GRF.ClickCast.Rows("CASTER"), 0, "nothing is copied before the player chooses")

-- Copy: a deep, one-time copy; editing one list leaves the other.
notice.copy:GetScript("OnClick")(notice.copy, "LeftButton")
check(not notice:IsShown(), "the notice closes")
local healer, caster = GRF.char.profiles.HEALER.bindings, GRF.char.profiles.CASTER.bindings
eq(#caster, 3, "three rows copied")
eq(caster[3].mouse, "ctrl-1", "in order, every field")
check(caster[1] ~= healer[1], "new tables, not shared ones")
caster[1].spell = 2053
eq(healer[1].spell, 2050, "the lists are separate afterwards")
check(chatHas("copied 3 click%-cast bindings from healer to caster"), "the copy is reported")

-- Back to healer: it has bindings, so only the respec line, no notice.
newChat()
ranks = { 3, 5, 6 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "back to healer")
check(not notice:IsShown(), "no notice: the healer list isn't empty")
check(table.concat(newChat(), "\n"):find("role: healer %(talents%)"), "the plain respec line")

-- /grf clickcast copy: only into an empty list, from a role that has rows.
SlashCmdList.GLASSRAIDFRAMES("clickcast copy caster")
eq(#GRF.char.profiles.HEALER.bindings, 3, "a non-empty list isn't overwritten")
check(chatHas("healer already has click%-cast bindings"), "and says why")
SlashCmdList.GLASSRAIDFRAMES("clickcast copy tank")
check(chatHas("tank has no click%-cast bindings"), "an empty source is refused")
SlashCmdList.GLASSRAIDFRAMES("clickcast copy healer")
check(chatHas("not healer"), "copying a role onto itself is refused")

-- A manual pick never offers: the player chose the role.
GRF.Settings.SetRole("tank")
eq(GRF.role, "TANK", "picked by hand")
check(not notice:IsShown(), "no notice for a manual pick")
SlashCmdList.GLASSRAIDFRAMES("clickcast copy healer")
eq(#GRF.char.profiles.TANK.bindings, 3, "the command copies into the current role")

-- Back to auto is a pick too: talents pointing at an empty role say nothing
-- (Codex P2 on #85).
ranks = { 0, 0, 9 }
GRF.char.profiles.CASTER.bindings = {}
newChat()
GRF.Settings.SetRole("auto")
eq(GRF.role, "CASTER", "auto: the talents again (Shadow)")
check(not notice:IsShown(), "no notice for /grf role auto")
eq(#newChat(), 0, "and no chat")

-- A notice outlived by another role change goes, and its buttons do
-- nothing for a role that isn't current (Codex P2 on #85).
ranks = { 0, 9, 0 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "Holy: healer")
ranks = { 0, 0, 9 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "CASTER", "Shadow: caster again")
check(notice:IsShown() and notice.to == "CASTER", "the empty caster list is offered")
ranks = { 0, 9, 0 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "Holy again before answering")
check(not notice:IsShown(), "the stale notice is dismissed")
notice:Show()
notice.copy:GetScript("OnClick")(notice.copy, "LeftButton")
eq(#GRF.char.profiles.CASTER.bindings, 0, "a stale copy button doesn't copy into the inactive role")
check(not notice:IsShown(), "it only closes")

-- "Open editor" opens it on the new role.
GRF.Settings.SetRole("melee")
eq(GRF.role, "MELEE", "melee by hand")
CCO.OfferCopy("HEALER", "MELEE", 3)
notice.open:GetScript("OnClick")(notice.open, "LeftButton")
eq(CCO._test.state().role, "MELEE", "the editor shows the new role's list")
check(not notice:IsShown(), "and the notice closes")

eq(#WoW.blocked, 0, "nothing protected was touched")
check(next(GRF.paintFailures) == nil, "no failures recorded")
done("test_role_copy")
