-- The group layout (#69): one header sized by the group, its pets, the
-- baseline, the announcement. The stub assigns units but lays nothing out:
-- the geometry against the client's own header code is test_layout_client.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

UIParent._width, UIParent._height = 1920, 1080   -- the baseline is 152 there
GlassRaidFramesCharDB = { role = "HEALER" }
local announced = {}
local callbacks = {}
rawset(_G, "EventRegistry", {
    TriggerEvent = function(_, event, ...) announced[#announced + 1] = { event, ... } end,
    RegisterCallback = function(_, event, fn, owner) callbacks[event] = function(...) fn(owner, ...) end end,
})
local GRF = loadAddon({ layout = true })
local H, Lay = GRF.Header, GRF.Layout
local L = Lay._test.L

local function roster()
    WoW.layoutHeaders()
    WoW.fire("GROUP_ROSTER_UPDATE")
    WoW.flushTimers()
    WoW.tick()
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
local function last() return announced[#announced] end

-- On by default, not saved; installed over Header's functions.
check(GRF.layoutOn, "the group layout is on by default")
eq(GRF.db.groupLayout, nil, "on isn't saved")
eq(H.Build, Lay.Build, "Header's functions are the layout's")
eq(H.DEFAULT_W .. "x" .. H.DEFAULT_H, "96x60", "the default cell is 96x60")

-- The build: 40 cells, 40 raid-pet cells, 5 party pets, all dressed.
eq(#L.cells .. " " .. #L.petCells .. " " .. #L.partyPets, "40 40 5", "40 cells, 40 raid pets, 5 party pets")
eq(H.children, L.cells, "Header.children are the grid's")
eq(#H.AllChildren(), 85, "click-casting and indicators reach all 85")
check(L.cells[1].body and L.petCells[1].body and L.partyPets[1].body, "every tile is dressed")
check(L.petCells[1].isPet and L.partyPets[3].isPet and not L.cells[1].isPet, "pet tiles are flagged (the debuff row only)")
eq(L.petCells[1]._width .. "x" .. L.petCells[1]._height, "64x28", "raid-pet cells are 64x28")
eq(L.cells[1]._width .. "x" .. L.cells[1]._height, "96x60", "cells are 96x60")
eq(GRF.Frames.NameSize(60), 15, "names are 15 at the layout's 60")
eq(L.cells[1].nameText._font and L.cells[1].nameText._font[2] - GRF.Frames.NameSize(60), L.petCells[1].nameText._font[2]
    - GRF.Frames.NameSize(28), "set on the tiles at their size")
eq(L.cells[1].nameText._wordWrap, false, "one line (LibGlass's Font): the client shortens a long name")
eq(L.grid:GetAttribute("startingIndex"), 1, "startingIndex restored")
for _, c in ipairs(L.cells) do
    if c:GetNumPoints() > 0 and not c._shown then check(false, "a hidden cell kept an anchor") break end
end
local pp = { L.pets:GetPoint(1) }
check(pp[1] == "TOPLEFT" and pp[2] == L.grid and pp[3] == "TOPRIGHT" and pp[4] == 6, "raid pets on the grid's right edge")
eq(L.pets:GetAttribute("showParty"), nil, "the raid-pet header is raid-only")
local b3 = { L.partyPets[3]:GetPoint(1) }
check(b3[1] == "TOP" and b3[2] == L.cells[3] and b3[3] == "BOTTOM" and b3[5] == -6, "partypet2 under the third cell")
eq(L.partyPets[3]:GetAttribute("unit"), "partypet2", "with its unit")
check(WoW.unitWatch[L.partyPets[5]], "party pets are unit-watched")
eq(WoW.stateDrivers[L.holder] and WoW.stateDrivers[L.holder][2], "hide", "pets off: the holder's driver hides it")
check(not L.pets._shown, "pets off: the raid-pet header is hidden")
check(next(GRF.Engine._test.framesByUnit.pet or {}) == nil, "pets off: nothing paints 'pet'")

-- Solo, show-solo off: the row, nothing shown, nothing for others to avoid.
eq(L.set, Lay.ROW, "solo: the row")
local s = GRF.LayoutState()
eq(s.mode, "hud", "the healer's default is the HUD")
eq(s.w, 0, "nothing shown: width 0 (other addons keep their own places)")

-- A party of 2: one row at baseline + 68, centred.
party(1)
announced = {}
roster()
eq(L.grid:GetAttribute("point"), "LEFT", "the row: point LEFT")
eq(L.grid:GetAttribute("groupBy"), nil, "no groupBy (INDEX order: party pets under owners)")
s = GRF.LayoutState()
check(near(s.base, 152) and near(s.top, 152 + 68 + 60), "bottom at baseline + 68, top 60 above: " .. s.base .. " " .. s.top)
check(near(s.w, 198) and near(s.l, 960 - 99), "198 wide, centred: " .. s.l .. " " .. s.w)
local gp = { L.grid:GetPoint(1) }
check(gp[1] == "BOTTOM" and near(gp[4], 960) and near(gp[5], 220), "the grid's bottom centre on its anchor")
eq(#announced, 1, "the roster change is announced once")
local a = last()
eq(a[1], GRF.LAYOUT_EVENT, "as LayoutChanged")
eq(a[2] .. " " .. a[9], "HEALER hud", "with the role and, last, the mode")
check(near(a[7], s.top) and near(a[8], s.base), "and top and base before it")
check(GRF.LayoutState() ~= GRF.LayoutState(), "LayoutState is a fresh table each time")

-- Pets on: the party's row under the cells; the driver by show-solo.
GRF.Settings.SetShowPets(true)
eq(WoW.stateDrivers[L.holder][2], Lay.DRIVER_NO_SOLO, "the row with pets: no lone pet solo")
check(GRF.Engine._test.framesByUnit.pet and GRF.Engine._test.framesByUnit.pet[L.partyPets[1]],
    "pets on: your pet's button is painted")
s = GRF.LayoutState()
check(near(s.b, 152 + 68 - 36) and near(s.h, 36 + 60), "the union covers the pet row: " .. s.b .. " " .. s.h)
GRF.Settings.SetShowSolo(true)
eq(WoW.stateDrivers[L.holder][2], "[@raid1,exists] hide; show", "show-solo on: the measured driver")
eq(L.grid:GetAttribute("showSolo"), true, "and the header shows you solo")
check(L.pets._shown, "the raid-pet header is shown")

-- A raid of 6: the columns, on the baseline, the holder hidden, one pet
-- column reserved even with no pet.
raid(6)
announced = {}
roster()
eq(L.set, Lay.COLUMNS, "6 members: the columns")
eq(L.grid:GetAttribute("groupBy"), "GROUP", "grouped by subgroup")
eq(L.grid:GetAttribute("point"), "TOP", "point TOP")
eq(L.grid:GetAttribute("_ignore"), nil, "_ignore is off after the batch")
eq(WoW.stateDrivers[L.holder][2], "hide", "the columns: the party pets' driver says hide")
s = GRF.LayoutState()
check(near(s.base, 152) and near(s.top, 152 + 324), "on the baseline, 5 rows: " .. s.top)
check(near(s.w, 198 + 6 + 64) and near(s.l, 960 - 134), "198 of grid + one reserved pet column, centred: " .. s.w)
gp = { L.grid:GetPoint(1) }
check(near(gp[4], 960 - 35), "the grid shifted left by half the pet block: " .. gp[4])
eq(#announced, 1, "announced once")

-- Eleven pets: two pet columns.
for i = 1, 6 do WoW.SetUnit("raidpet" .. i, { name = "Pet " .. i }) end
for i = 7, 11 do WoW.raid["raid" .. i] = { index = i, subgroup = 2 }; WoW.SetUnit("raid" .. i, { name = "R" .. i }) end
for i = 7, 11 do WoW.SetUnit("raidpet" .. i, { name = "Pet " .. i }) end
roster()
s = GRF.LayoutState()
check(near(s.w, 300 + 6 + 64 + 6 + 64), "11 members, 11 pets: 3 columns of cells, 2 of pets: " .. s.w)

-- Pets off: no reserve.
GRF.Settings.SetShowPets(false)
s = GRF.LayoutState()
check(near(s.w, 300), "pets off: the grid alone: " .. s.w)
check(not L.pets._shown, "the raid-pet header hides")

-- 21 members: 80-wide cells.
raid(21)
roster()
eq(L.cells[1]._width, 80, "21 members: cells 80 wide")
eq(L.partyPets[1]._width, 80, "party pets follow the cell width")
s = GRF.LayoutState()
check(near(s.w, 5 * 80 + 4 * 6), "5 columns of 80: " .. s.w)
raid(20)
roster()
eq(L.cells[1]._width, 96, "20: back to 96")

-- A saved size is the 96 cell; the tier scales its width.
GRF.Settings.SetSize(100, 50)
eq(L.cells[1]._width .. "x" .. L.cells[1]._height, "100x50", "the role's size is the cell")
raid(21)
roster()
eq(L.cells[1]._width .. "x" .. L.cells[1]._height, "83x50", "and 80/96 of it from 21")
GRF.Settings.SetSize(nil, nil)

-- In combat nothing of ours moves or is set; after it, once.
raid(6)
roster()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
announced = {}
local before = { L.grid:GetPoint(1) }
WoW.raid = nil
party(2)
roster()
eq(#WoW.blocked, 0, "nothing blocked in combat")
eq(L.set, Lay.COLUMNS, "the set waits for combat to end")
eq(#announced, 0, "nothing announced in combat")
eq(select(4, L.grid:GetPoint(1)), before[4], "the grid didn't move")
GRF.Announce()
eq(#announced, 0, "an announcement in combat waits too")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(L.set, Lay.ROW, "after combat: the row")
check(#announced >= 1, "and announced")
eq(last()[1], GRF.LAYOUT_EVENT, "the complete state")

-- The mover moves the baseline, saved for the role's mode; Reset clears it
-- and leaves the legacy positions set aside.
GRF.Profile().pos = { x = 1, y = 2 }
local x0, y0 = H.PositionOf()
H.SetPosition(x0 + 40, y0 + 10, false)
eq(GRF.Profile().layoutPos, nil, "a drag in progress isn't saved")
H.SetPosition(x0 + 50, y0 + 20, true)
local saved = GRF.Profile().layoutPos and GRF.Profile().layoutPos.hud
check(saved and near(saved.x, 960 + 50) and near(saved.y, 152 + 20), "saved as the HUD's anchor")
local x1, y1 = H.PositionOf()
check(near(x1, x0 + 50) and near(y1, y0 + 20), "the block's centre went where the mover put it")
roster()
x1, y1 = H.PositionOf()
check(near(x1, x0 + 50) and near(y1, y0 + 20), "and stays there through a roster change")
GRF.Movers.Reset()
eq(GRF.Profile().layoutPos, nil, "reset forgets the layout's spot")
eq(GRF.Profile().pos.x, 1, "and keeps the legacy one set aside")
x1, y1 = H.PositionOf()
check(near(x1, x0) and near(y1, y0), "back on the default")
check(not GRF.Movers._test.petMover(), "the pets have no mover of their own")

-- The side: anchored by its bottom-left, so it grows right.
GRF.Settings.SetLayoutMode("side")
eq(GRF.Profile().layout, "side", "the healer's side is saved")
gp = { L.grid:GetPoint(1) }
check(gp[1] == "BOTTOMLEFT" and near(gp[4], 30) and near(gp[5], 540 - 93 + 68), "the side anchor: " .. gp[4] .. " " .. gp[5])
eq(GRF.LayoutState().mode, "side", "announced as side")
-- GlassActionBars' left-edge bars (its #37): the side starts 30 past them.
check(callbacks["GlassActionBars.EdgesChanged"], "listening to GlassActionBars.EdgesChanged")
local edge = { left = 87, right = 1920, width = 1920 }
rawset(_G, "GlassActionBars", { EdgeState = function() return edge end })
announced = {}
callbacks["GlassActionBars.EdgesChanged"](87, 1920, 1920)
WoW.flushTimers()
gp = { L.grid:GetPoint(1) }
check(near(gp[4], 117), "the side starts 30 past GAB's bars: " .. gp[4])
eq(#announced, 1, "and the new place is announced")
for label, bad in pairs({ secret = WoW.Secret("edge"), negative = -5, ["past the middle"] = 1500, text = "87" }) do
    edge.left = bad
    callbacks["GlassActionBars.EdgesChanged"]()
    WoW.flushTimers()
    check(near(select(4, L.grid:GetPoint(1)), 30), "a " .. label .. " edge reads as no bar")
end
rawset(_G, "GlassActionBars", { EdgeState = function() error("boom") end })
callbacks["GlassActionBars.EdgesChanged"]()
WoW.flushTimers()
check(near(select(4, L.grid:GetPoint(1)), 30), "an EdgeState that throws reads as no bar")
edge.left = 87
rawset(_G, "GlassActionBars", { EdgeState = function() return edge end })
local sx, sy = H.PositionOf()
H.SetPosition(sx + 200, sy, true)
callbacks["GlassActionBars.EdgesChanged"]()
WoW.flushTimers()
check(near(select(4, L.grid:GetPoint(1)), 230), "a dragged side position stays where it was put")
GRF.Movers.Reset()
rawset(_G, "GlassActionBars", nil)
GRF.Layout.Refresh()
GRF.Settings.SetLayoutMode("hud")
eq(GRF.Profile().layout, nil, "the role's default isn't saved")
check(not GRF.Settings.SetLayoutMode("middle"), "an unknown mode is refused")

-- Another role: its own mode (caster: the side).
GRF.Settings.SetRole("CASTER")
eq(GRF.LayoutState().mode, "side", "the caster's default is the side")
GRF.Settings.SetRole("HEALER")

-- The tier preview: mock raids where the grid is, announced; the real grid
-- hidden, untouched.
WoW.raid = nil
for i = 1, 40 do WoW.units["raid" .. i] = nil end
party(1)
roster()
GRF.Settings.SetShowPets(true)
announced = {}
check(GRF.Settings.Preview(10), "a preview of 10")
local M, MP = Lay._test.mocks, Lay._test.mockPets
local shownMocks = 0
for _, f in ipairs(M) do if f._shown then shownMocks = shownMocks + 1 end end
eq(shownMocks, 10, "10 mock cells")
eq(M[1]._width .. "x" .. M[1]._height, "96x60", "at the 96 cell")
eq(#MP, 3, "3 mock pets")
eq(L.grid._alpha, 0, "the real grid is hidden")
s = GRF.LayoutState()
check(near(s.w, 198 + 70) and near(s.top, 152 + 324) and near(s.base, 152), "announced: 2 columns and a pet column, on the baseline: " .. s.w)
eq(#announced, 1, "announced once")
local mp = { M[6]:GetPoint(1) }
check(near(mp[4], s.l + 102) and near(mp[5], s.top), "the 6th cell heads the second column")
check(GRF.Settings.Preview(40), "a preview of 40")
eq(M[1]._width, 80, "40: cells 80 wide")
s = GRF.LayoutState()
check(near(s.w, 8 * 80 + 7 * 6 + 2 * 70), "8 columns of 80 and 2 of pets: " .. s.w)
eq(M[1].label._text, "Karuzo", "mock cells have names")
-- A real roster change ends it, and the real state is announced again.
announced = {}
party(2)
roster()
eq(Lay.Previewing(), nil, "a roster change ends the preview")
eq(L.grid._alpha, 1, "the real grid is back")
check(not M[1]:IsVisible() and not MP[1]:IsVisible(), "the mocks are hidden")
check(near(GRF.LayoutState().w, 3 * 96 + 2 * 6), "the real party announced again: " .. GRF.LayoutState().w)
-- Combat ends it, before the lockdown.
GRF.Settings.Preview(20)
WoW.fire("PLAYER_REGEN_DISABLED")
eq(Lay.Previewing(), nil, "combat starting ends the preview")
eq(L.grid._alpha, 1, "and shows the real grid")
WoW.combat = true
local okP, whyP = GRF.Settings.Preview(10)
check(not okP and whyP:find("combat"), "no preview in combat")
WoW.combat = false
check(not GRF.Settings.Preview(30), "only 10, 20 or 40")
SlashCmdList.GLASSRAIDFRAMES("preview 10")
check(chatHas("preview: a raid of 10"), "/grf preview 10")
SlashCmdList.GLASSRAIDFRAMES("preview off")
eq(Lay.Previewing(), nil, "/grf preview off ends it")
GRF.Settings.Preview(10)
local px, py = H.PositionOf()
H.SetPosition(px, py, false)
eq(Lay.Previewing(), nil, "a drag ends the preview")
H.SetPosition(nil, nil, nil)
GRF.Settings.SetShowPets(false)

-- The glide: a body is offset back to where it was, and eased to its tile
-- in 0.3 s (cubic ease-out); a tile that didn't move doesn't glide.
local function rect(f, x, y, w, h) f._center, f._width, f._height = { x, y }, w, h end
local c1, c2 = L.cells[1], L.cells[2]
rect(c1, 500, 300, 96, 60)
rect(c2, 602, 300, 96, 60)
c1._shown, c2._shown = true, true
Lay._test.glideFrom({ [c1] = { 452 - 40, 270 + 10 }, [c2] = { 554, 270 } })
local bp = { c1.body:GetPoint(1) }
check(bp[1] == "TOPLEFT" and bp[2] == c1 and near(bp[4], -40) and near(bp[5], 10), "offset back where it was")
check(Lay._test.gliding()[c1] and not Lay._test.gliding()[c2], "only the tile that moved glides")
check(Lay._test.glider._shown, "the glide runs")
WoW.tick(0.15)
bp = { c1.body:GetPoint(1) }
check(near(bp[4], -40 * 0.125) and near(bp[5], 10 * 0.125), "halfway in time, 7/8 of the way (cubic ease-out): " .. bp[4])
WoW.tick(0.2)
bp = { c1.body:GetPoint(1) }
eq(bp[1], "ALL", "at the end, the body is on its tile again")
check(not Lay._test.glider._shown, "and the glide stops")
-- A roster event reads the visuals before the headers move the tiles.
rect(c1.body, 500, 300, 96, 60)
WoW.fire("GROUP_ROSTER_UPDATE")
check(L.from and L.from[c1] and near(L.from[c1][1], 452), "a roster change captures where the visuals were")
WoW.fire("PLAYER_REGEN_DISABLED")
eq(L.from, nil, "combat drops a capture waiting for its refresh")
WoW.flushTimers()
check(L.placed, "the first placement is behind us")
-- Apply glides from what was captured; the session's first placement snaps.
rect(c1, 500, 300, 96, 60)
L.from = { [c1] = { 452 + 30, 270 } }
Lay.Apply()
check(Lay._test.gliding()[c1], "a layout change glides from where the visuals were")
WoW.tick(1)
L.placed = false
rect(c1.body, 600, 300, 96, 60)
Lay.Apply()
check(not Lay._test.gliding()[c1], "the session's first placement snaps")
check(L.placed, "and the next ones glide")
-- At login: UIParent has its real size by PLAYER_LOGIN, not at ADDON_LOADED
-- where the frames are built (item 16). Nothing is announced before it, and
-- the first placement on it snaps.
L.settled, L.placed = false, false
eq(GRF.LayoutState(), nil, "before PLAYER_LOGIN, no state")
announced = {}
GRF.Announce()
eq(#announced, 0, "and no announcement")
Lay.Apply()   -- the build's own placement, at ADDON_LOADED
rect(c1.body, 700, 300, 96, 60)
WoW.fire("PLAYER_LOGIN")
eq(#announced, 1, "PLAYER_LOGIN places and announces")
check(not Lay._test.gliding()[c1], "that first placement snaps")
check(L.placed, "after it, changes glide")
-- A new screen size is placed, not glided to.
rect(c1.body, 700, 300, 96, 60)
WoW.fire("UI_SCALE_CHANGED")
WoW.flushTimers()
check(not Lay._test.gliding()[c1], "a UI scale change snaps")

-- The switch is saved for the next /reload; nothing rebuilds now.
GRF.Settings.SetGroupLayout(false)
eq(GRF.db.groupLayout, false, "off is saved")
check(GRF.layoutOn, "this session keeps the layout")
SlashCmdList.GLASSRAIDFRAMES("layout")
check(chatHas("off after /reload"), "/grf layout says it changes after /reload")
GRF.Settings.SetGroupLayout(true)
eq(GRF.db.groupLayout, nil, "on again isn't saved")

-- Junk in the saves is dropped.
GRF = loadAddon({ layout = true, db = { groupLayout = "yes", profiles = { HEALER = { layout = "middle", layoutPos = 5 } } } })
eq(GRF.db.groupLayout, nil, "a junk switch reads as on")
eq(GRF.db.profiles.HEALER.layout, nil, "a junk mode is dropped")
eq(GRF.db.profiles.HEALER.layoutPos, nil, "a junk position is dropped")

-- Off: the legacy grid, announced as "legacy".
announced = {}
GRF = loadAddon({ db = { groupLayout = false } })
check(not GRF.layoutOn and GRF.Header.headers[8], "off: the eight-group grid")
local ls = GRF.LayoutState()
eq(ls and ls.mode, "legacy", "announced as legacy")
check(ls and near(ls.top, ls.b + ls.h) and near(ls.base, ls.b), "with top = b + h and base = b")

check(next(GRF.paintFailures) == nil, "no failures recorded")
done("test_layout")
