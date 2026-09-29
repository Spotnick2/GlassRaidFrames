-- The group frames: 8 headers x 5 precreated children, what they show, and
-- how they follow the roster (in combat too).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.atlases["roleicon-tiny-tank"] = true
WoW.atlases["roleicon-tiny-healer"] = true

party(2)
local GRF = loadAddon()
local H = GRF.Header
flush()

-- Build: 8 headers, 40 children, all dressed, nothing failed.
eq(#H.headers, 8, "one header per raid group")
eq(#H.children, 40, "every child precreated")
eq(next(GRF.paintFailures), nil, "nothing failed to build or paint")
for g, h in ipairs(H.headers) do
    eq(h:GetAttribute("groupFilter"), tostring(g), "header " .. g .. " filters its group")
    eq(h:GetAttribute("template"), "GlassRaidFramesUnitTemplate", "header " .. g .. " uses the XML template")
    eq(h:GetAttribute("initialConfigFunction"), nil, "no restricted snippet on header " .. g)
    eq(h:GetAttribute("startingIndex"), 1, "startingIndex restored after precreation")
end
check(H.headers[1]:GetAttribute("showParty") and H.headers[1]:GetAttribute("showPlayer"),
    "header 1 carries the party and the player")
check(not H.headers[2]:GetAttribute("showParty"), "the other headers are raid-only")
eq(H.children[1]:GetWidth(), H.DEFAULT_W, "the child size is the default (Cell's look)")
eq(H.children[1]:GetHeight(), H.DEFAULT_H, "(height)")

-- Every child: target/menu on every modifier (no fallback from shift-type1
-- to type1, probe item 2), the up edge only, and an insecure body.
local c1 = H.children[1]
eq(c1:GetAttribute("*type1"), "target", "any-modifier left click targets")
eq(c1:GetAttribute("*type2"), "togglemenu", "any-modifier right click opens the menu")
eq(c1:GetAttribute("type1"), nil, "no unmodified-only binding")
eq(c1._clicks and c1._clicks[1], "AnyUp", "unit buttons take the up edge only")
check(c1.body and not c1.body._protected, "the visuals live on an insecure body")

-- Party: the player and party1-2 in header 1's column, the rest empty.
local me, p1 = childFor("player"), childFor("party1")
check(me and p1 and childFor("party2"), "party members have frames")
eq(me:GetParent(), H.headers[1], "the party is in header 1")
eq(me.nameText._text, "Karuzo", "the first name is painted (as Cell shows it)")
eq(p1.health._value, 100, "health painted")
eq(p1.health._max, 150, "max health painted")
check(p1.health._color and math.abs(p1.health._color[1] - 0.53) < 1e-6, "the bar takes the class colour")

-- The name is centred in the tile both ways, as Cell draws it; Dead/Offline
-- sits small in the top-right corner.
local np1, np2 = p1.nameText._points[1], p1.nameText._points[2]
eq(np1[1] .. "/" .. np1[3] .. "/" .. np1[5], "LEFT/LEFT/0", "the name spans the tile, vertically centred")
eq(np2[1] .. "/" .. np2[3] .. "/" .. np2[5], "RIGHT/RIGHT/0", "(both sides)")
eq(p1.statusText._points[1][1], "TOPRIGHT", "the status sits top-right")
check(WoW.methodsCalled["FontString:SetJustifyH"], "the name is justified (centred by Glass.Font's argument)")

-- A secret name (grouped, ForeverUI's note) can't be split: it goes whole.
WoW.secretFields = { name = true }
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()
check(WoW.IsSecret(p1.nameText._text), "a secret name reaches the client whole")
eq(next(GRF.paintFailures), nil, "without a failure")
WoW.secretFields = {}
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()

-- The power bar along the bottom: coloured by power type, secret-safe.
eq(me.power._value, 500, "power painted")
eq(me.power._max, 500, "max power painted")
eq(me.power._color[3], GRF.Frames.POWER.MANA[3], "mana is blue")
WoW.units.party1.powerToken = "RAGE"
WoW.fire("UNIT_DISPLAYPOWER", "party1"); flush()
eq(p1.power._color[1], GRF.Frames.POWER.RAGE[1], "rage is red")
WoW.secretFields = { power = true, maxPower = true }
WoW.fire("UNIT_POWER_UPDATE", "party1"); flush()
check(WoW.IsSecret(p1.power._value), "secret power goes straight to the bar")
eq(next(GRF.paintFailures), nil, "without a failure")
WoW.secretFields = {}

-- Hover: the white glass rim shows while the mouse is on the tile.
eq(p1.hoverRim._alpha, 0, "no hover rim at rest")
p1._scripts.OnEnter(p1)
eq(p1.hoverRim._alpha, 1, "the hover rim shows on mouse-over")
p1._scripts.OnLeave(p1)
eq(p1.hoverRim._alpha, 0, "and goes on leave")

-- Target: the tinted rim on your target's tile only.
WoW.units.target = WoW.units.party1
WoW.fire("PLAYER_TARGET_CHANGED"); flush()
eq(p1.targetRim._alpha, 1, "your target's tile shows the target rim")
eq(me.targetRim._alpha, 0, "the others don't")
WoW.secretFields = { targetIsUnit = true }
local realIsUnit = UnitIsUnit
rawset(_G, "UnitIsUnit", function(a, b) return WoW.Secret("isUnit") end)
WoW.rangeTruth = WoW.rangeTruth or {}
WoW.fire("PLAYER_TARGET_CHANGED"); flush()
check(p1.targetRim._alphaFromBoolean, "a secret 'is my target' goes through SetAlphaFromBoolean")
eq(next(GRF.paintFailures), nil, "without a failure")
rawset(_G, "UnitIsUnit", realIsUnit)
WoW.secretFields = {}
WoW.units.target = nil
WoW.fire("PLAYER_TARGET_CHANGED"); flush()
eq(p1.targetRim._alpha, 0, "no target: no rim")

-- Offline and dead.
WoW.units.party1.connected = false
WoW.fire("UNIT_CONNECTION", "party1"); flush()
eq(p1.statusText._text, "Offline", "offline says so")
eq(p1.health._color[1], GRF.Frames.OFFLINE[1], "offline is grey")
WoW.units.party1.connected = true
WoW.units.party1.dead = true
WoW.fire("UNIT_HEALTH", "party1"); flush()
eq(p1.statusText._text, "Dead", "dead says so")
eq(p1.health._value, 0, "a dead bar is empty")
WoW.units.party1.dead = false
WoW.fire("UNIT_HEALTH", "party1"); flush()
eq(p1.statusText._text, "", "alive again clears the status")

-- Secret health (the partner's max health is secret, measured): no failure,
-- the secrets reach the bar untouched.
WoW.secretFields = { health = true, maxHealth = true }
WoW.fire("UNIT_HEALTH", "party1"); flush()
check(WoW.IsSecret(p1.health._value) and WoW.IsSecret(p1.health._max), "secret health goes straight to the bar")
eq(next(GRF.paintFailures), nil, "secret health paints without failure")
WoW.secretFields = {}

-- Range: secret, handed to SetAlphaFromBoolean on the body; you never fade.
WoW.units.party1.inRange = false
WoW.tick(0.3)
check(p1.body._alphaFromBoolean, "range goes through SetAlphaFromBoolean")
eq(p1.body._alpha, GRF.Frames.OUT_OF_RANGE_ALPHA, "out of range fades")
WoW.units.party1.inRange = true
WoW.tick(0.3)
eq(p1.body._alpha, 1, "back in range is opaque")
eq(me.body._alpha, 1, "your own frame never fades")
eq(p1._alpha, nil, "the secure button itself is never faded")

-- Indicators: leader, raid mark (sprite cell), role (tanks and healers only).
WoW.units.player.leader = true
WoW.units.party1.raidTarget = 3
WoW.units.party1.role = "TANK"
WoW.units.party2.role = "DAMAGER"
WoW.fire("PARTY_LEADER_CHANGED"); flush()
check(me.indicators.leader._shown, "the leader icon shows")
check(p1.indicators.mark._shown and p1.indicators.mark._raidIndex == 3, "the raid mark shows its sprite cell")
check(p1.indicators.role._shown and p1.indicators.role._atlas == "roleicon-tiny-tank", "a tank shows its role")
check(not childFor("party2").indicators.role._shown, "a DAMAGER (Forever's default) shows no role icon")
WoW.secretFields = { raidTarget = true }
WoW.fire("RAID_TARGET_UPDATE"); flush()
check(p1.indicators.mark._shown and WoW.IsSecret(p1.indicators.mark._raidIndex), "a secret mark index goes to the client")
WoW.secretFields = {}

-- Debuff row: one container per child, group declared before the unit.
local dc = p1.debuffs
check(dc and dc._groups and dc._groups.grf_debuffs, "each tile has a debuff row")
eq(dc._groups.grf_debuffs.filter, "HARMFUL", "the row shows debuffs")
local seq = table.concat(dc._seq, ",")
check(seq:find("^AddAuraGroup,SetUnit,UpdateAllAuras"), "AddAuraGroup before SetUnit (" .. seq .. ")")
eq(dc._modelUnit, "party1", "the row follows its tile's unit")
-- The client builds aura buttons with initializeFrame: they never take the mouse.
local ab = CreateFrame("Button", nil, dc)
dc._groups.grf_debuffs.spec.initializeFrame(ab)
eq(ab._mouse, nil, "no scripts on aura buttons")
check(WoW.methodsCalled["Button:EnableMouse"], "aura buttons are made click-through")

-- Conversion to a raid IN COMBAT: the header reassigns, the frames follow,
-- nothing protected is touched.
WoW.combat = true
WoW.blocked = {}
raid(12)
WoW.layoutHeaders()
WoW.fire("GROUP_ROSTER_UPDATE"); flush()
eq(#WoW.blocked, 0, "a combat conversion touches nothing protected (" .. table.concat(WoW.blocked, ", ") .. ")")
local r7 = childFor("raid7")
check(r7 and r7:GetParent() == H.headers[2], "raid7 (group 2) sits in header 2")
eq(r7.nameText._text, "Raider", "its name is painted in combat")
eq(r7.debuffs._modelUnit, "raid7", "its debuff row moved to the new unit in combat")
eq(childFor("party1"), nil, "party tokens are gone in the raid")
eq(GRF.Engine._test.framesByUnit.party1[p1], nil, "the engine forgot the old unit")

-- A roster update where nobody changed person refreshes indicators only:
-- no health repaint, so no bar snaps across the grid (code review).
flush()
WoW.fire("GROUP_ROSTER_UPDATE")
local d = GRF.Engine._test.dirty()[r7]
check(d and d.indicators, "a roster update refreshes indicators")
check(not d.health and not r7.snap, "but doesn't repaint or snap the bar of an unchanged person")
flush()

-- A token that stays on its frame but changes person: repainted on roster.
WoW.units.raid7.name = "Someone Else"
WoW.units.raid7.guid = "GUID-someone-else"
WoW.fire("GROUP_ROSTER_UPDATE"); flush()
eq(r7.nameText._text, "Someone", "a reused token repaints its name")
WoW.combat = false

done("test_frames")
