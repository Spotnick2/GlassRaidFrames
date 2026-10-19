-- The group layout (#69): one header sized by the group, its pets, the
-- baseline, the announcement. The stub assigns units but lays nothing out:
-- the geometry against the client's own header code is test_layout_client.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

UIParent._width, UIParent._height = 1920, 1080   -- the baseline is 152 there
GlassRaidFramesCharDB = { role = "HEALER" }
local announced = {}
rawset(_G, "EventRegistry", { TriggerEvent = function(_, event, ...) announced[#announced + 1] = { event, ... } end })
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
GRF.Settings.SetLayoutMode("hud")
eq(GRF.Profile().layout, nil, "the role's default isn't saved")
check(not GRF.Settings.SetLayoutMode("middle"), "an unknown mode is refused")

-- Another role: its own mode (caster: the side).
GRF.Settings.SetRole("CASTER")
eq(GRF.LayoutState().mode, "side", "the caster's default is the side")
GRF.Settings.SetRole("HEALER")

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
