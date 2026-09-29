-- Settings per role (#7): the role source (manual > talents > class), the
-- per-role positions, the announcement for GlassUnitFrames, and the options
-- panel. The trait tree is stubbed with the layout measured in game
-- (FOREVER-PROBE item 9).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The measured canvas: three column clusters, a priest's stray node off it.
local COLUMNS = { { 1020, 1620, 2220, 2820 }, { 5020, 5620, 6220, 6820 }, { 9080, 9680, 10280, 10880 } }
local ranks = { 0, 0, 0 }            -- points per tree, spread over its first node
local stray = true
local traitsAvailable = true

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
    if stray then
        list[#list + 1] = 999
        info[999] = { ID = 999, posX = 9280, posY = 21300, isVisible = true, currentRank = 5 }   -- must not count
    end
    return list, info
end

rawset(_G, "C_ClassTalents", { GetActiveConfigID = function() return traitsAvailable and 88388 or nil end })
rawset(_G, "C_Traits", {
    GetConfigInfo = function(id) return { ID = id, treeIDs = { 1114 } } end,
    GetTreeNodes = function() return (nodes()) end,
    GetNodeInfo = function(_, nodeID) local _, info = nodes(); return info[nodeID] end,
})
local announced = {}
rawset(_G, "EventRegistry", { TriggerEvent = function(_, event, ...) announced[#announced + 1] = { event, ... } end })

UIParent._width, UIParent._height = 1365, 768   -- a 16:9 screen at the default scale
party(1)                                          -- the player is a PRIEST
local GRF = loadAddon()
local Role, H = GRF.Role, GRF.Header

-- Pure clustering: split at gaps over Role.GAP.
local sums = Role.ClusterPoints({ { x = 5020, ranks = 2 }, { x = 1020, ranks = 1 }, { x = 1620, ranks = 3 },
                                  { x = 9080, ranks = 5 }, { x = 5620, ranks = 0 } })
eq(table.concat(sums, ","), "4,2,5", "three clusters, left to right")

-- No points yet: the class default.
eq(GRF.role, "HEALER", "a priest with no points is a healer (class default)")
eq(GRF.roleSource, "class", "and says where it came from")
eq(GRF.char.role, "auto", "the per-character pick starts on auto")

-- Where things go: healer in the lower middle; the others on the left side,
-- from the screen's actual width.
local c = H.container
local function at() local p = c._points[#c._points]; return p[4], p[5] end
local x, y = at()
eq(x, H.HEALER_POS.x, "the healer grid sits in the middle (x)")
eq(y, H.HEALER_POS.y, "(y)")
local sx = H.DefaultPosition("CASTER")
eq(sx, math.floor(-1365 / 2 + select(1, H.Size()) / 2 + H.SIDE_MARGIN), "the side position follows the screen width")

-- Shadow points: the talents make it a caster; the grid moves to the side and says so.
ranks = { 1, 2, 5 }
announced = {}
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "CASTER", "the most points in Shadow: caster")
eq(GRF.roleSource, "talents", "from the talents")
x = at()
eq(x, sx, "the grid moved to the side")
check(chatHas("role: caster %(talents%)"), "the change is announced in chat")
eq(announced[#announced][1], GRF.LAYOUT_EVENT, "other addons hear about it")
eq(announced[#announced][2], "CASTER", "with the role")

-- The stray off-canvas node (5 ranks at x 9280, y 21300) doesn't count:
-- Holy leads 4 to 3 only without it.
ranks = { 0, 4, 3 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "the off-canvas node is ignored")

-- A layout that isn't three trees: don't guess, use the class.
local saved = COLUMNS
COLUMNS = { { 1020, 1620 }, { 5020, 5620 } }
ranks = { 0, 9, 0 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.roleSource, "class", "an unexpected layout falls back to the class")
COLUMNS = saved
traitsAvailable = false
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.roleSource, "class", "no trait config: the class")
traitsAvailable = true

-- Positions are per role: a drag in one role never moves another's.
ranks = { 0, 6, 0 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "HEALER", "back to healer")
UIParent._center = { 682, 384 }
GRF.Movers.Unlock()
local mv = GRF.Movers._test.mover()
mv._scripts.OnDragStart(mv); mv._center = { 682, 300 }; mv._scripts.OnUpdate(mv); mv._scripts.OnDragStop(mv)
eq(GRF.db.profiles.HEALER.pos.y, -84, "the healer drag is saved in the healer profile")
eq(GRF.db.profiles.CASTER.pos, nil, "the caster profile is untouched")
ranks = { 0, 0, 9 }
WoW.fire("PLAYER_TALENT_UPDATE")
x, y = at()
eq(x, sx, "the caster layout keeps its own spot")
ranks = { 0, 9, 0 }
WoW.fire("PLAYER_TALENT_UPDATE")
x, y = at()
eq(y, -84, "and the healer's comes back")

-- The manual pick wins over the talents; auto hands back to them.
SlashCmdList.GLASSRAIDFRAMES("role tank")
eq(GRF.role, "TANK", "a manual pick wins")
eq(GRF.char.role, "TANK", "and is saved per character")
eq(GRF.roleSource, "manual", "from the pick")
SlashCmdList.GLASSRAIDFRAMES("role nonsense")
eq(GRF.char.role, "TANK", "an unknown role is refused")
SlashCmdList.GLASSRAIDFRAMES("role auto")
eq(GRF.role, "HEALER", "auto goes back to the talents")

-- A role change in combat waits; nothing protected is touched.
WoW.combat = true
WoW.blocked = {}
ranks = { 0, 0, 9 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "CASTER", "the role changes in combat")
x, y = at()
eq(y, -84, "but the grid doesn't move in combat")
eq(#WoW.blocked, 0, "and nothing protected was touched")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
x = at()
eq(x, sx, "it moves when combat ends")

-- Paladin: Protection points make a tank.
WoW.units.player.class = "PALADIN"
ranks = { 1, 7, 2 }
WoW.fire("PLAYER_TALENT_UPDATE")
eq(GRF.role, "TANK", "a Protection paladin is a tank")

-- A bad saved pick is reset to auto.
WoW.reset()
UIParent._width = 1365
party(1)
GlassRaidFramesCharDB = { role = "WIZARD" }
GRF = loadAddon()
eq(GRF.char.role, "auto", "an unknown saved pick becomes auto")

-- The options panel: registered under AddOns, built on show, wired to Settings.
eq(WoW.settings.addon and WoW.settings.addon.name, "Glass Raid Frames", "registered under Options > AddOns")
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local tank
for _, rb in ipairs(O.controls.role) do if rb.value == "TANK" then tank = rb end end
check(tank, "the panel offers the tank role")
tank._scripts.OnClick(tank)
eq(GRF.char.role, "TANK", "picking a role in the panel sets it")
check(tank:GetChecked(), "and the panel shows it")
local solo = O.controls.solo
solo:SetChecked(true); solo._scripts.OnClick(solo)
eq(GRF.db.showSolo, true, "the solo checkbox saves")
eq(GRF.Header.headers[1]:GetAttribute("showSolo"), true, "and applies")
-- Unlock closes the Settings window WITHOUT going back to the Game Menu:
-- plain Close() takes that path, which calls the protected SpellStopCasting
-- and got ADDON_ACTION_FORBIDDEN blamed on us in game.
local closedWith = "not called"
local sp = CreateFrame("Frame", "SettingsPanel", UIParent)
rawset(sp, "Close", function(_, skip) closedWith = skip end)
O.unlock._scripts.OnClick(O.unlock)
eq(closedWith, true, "Unlock closes Settings with skipTransitionBackToOpeningPanel")
check(GRF.Movers.IsUnlocked(), "and unlocks")
GRF.Movers.Lock()
eq(next(GRF.paintFailures), nil, "no failures")

done("test_role")
