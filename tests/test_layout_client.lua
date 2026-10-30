-- The group layout (#69) on Blizzard's own header code: Forever's
-- SecureGroupHeaders.lua lays the cells out and sizes the headers, and the
-- layout's model (what it announces) must agree with it, for every roster.
-- It needs the wow-ui-source checkout ($env:WOW_UI_SOURCE, else
-- ..\wow-ui-source); CI has none and sets WOW_UI_SOURCE_OPTIONAL=1.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local root = os.getenv("WOW_UI_SOURCE") or "../wow-ui-source"
local file = root .. "/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua"
if not WoW.useClientHeaders(file) then
    if os.getenv("WOW_UI_SOURCE_OPTIONAL") == "1" then
        io.write("test_layout_client: SKIPPED (no wow-ui-source checkout)\n")
        return
    end
    check(false, "the client's header code isn't at " .. file .. " (set WOW_UI_SOURCE)")
    done("test_layout_client")
end

UIParent._width, UIParent._height = 1920, 1080
GlassRaidFramesCharDB = { role = "HEALER" }
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST", player = true })
local GRF = loadAddon({ layout = true, db = { showSolo = true } })
local Lay = GRF.Layout
local L = Lay._test.L

local function roster()
    WoW.layoutHeaders()
    WoW.fire("GROUP_ROSTER_UPDATE")
    WoW.flushTimers()
end

-- What the header shows, by its own code.
local function shown(list)
    local units = {}
    for _, c in ipairs(list) do
        if c._shown and c:GetAttribute("unit") then units[#units + 1] = c:GetAttribute("unit") end
    end
    return #units, units
end

-- Every shown cell anchored only by the applied set's points, at most two.
local function anchorsOk()
    for i, c in ipairs(L.cells) do
        if c._shown then
            if #c._points > 2 then return false, "cell " .. i .. " has " .. #c._points .. " anchors" end
            for _, p in ipairs(c._points) do
                if p[1] ~= L.set.point and p[1] ~= L.set.columnAnchorPoint then
                    return false, "cell " .. i .. " keeps a " .. p[1] .. " anchor under the " .. L.set.name
                end
            end
        end
    end
    return true
end

-- The model agrees with the header's own size, and the anchors hold.
local function agrees(label, wantN)
    local n = shown(L.cells)
    if wantN then eq(n, wantN, label .. ": cells shown") end
    local w, h = Lay.HeaderSize(L.set, n, L.cellW, L.cellH)
    check(math.abs(L.grid._width - w) < 0.01 and math.abs(L.grid._height - h) < 0.01,
        string.format("%s: the header is %sx%s, the model %sx%s", label, L.grid._width, L.grid._height, w, h))
    local ok, why = anchorsOk()
    check(ok, label .. ": " .. tostring(why))
end

-- Built by the client's code: 40 cells each, named by it.
eq(#L.cells .. " " .. #L.petCells, "40 40", "the client's code precreated 40 cells and 40 pet cells")
eq(L.cells[1]._name, "GlassRaidFramesGridUnitButton1", "named by the client's code")
agrees("solo, show-solo on", 1)
eq(L.cells[1]:GetNumPoints(), 1, "after precreation, the shown cell has its point only")

-- A party: the row, in INDEX order (party pets sit under their owners).
for size = 1, 4 do
    party(size)
    roster()
    eq(L.set.name, "row", "a party of " .. (size + 1) .. ": the row")
    agrees("a party of " .. (size + 1), size + 1)
end
local _, units = shown(L.cells)
eq(table.concat(units, ","), "player,party1,party2,party3,party4", "the player, then party1..4")

-- Raids of every tier: the row up to 5, columns of 5 above, 80 wide from 21.
for _, n in ipairs({ 2, 5, 6, 10, 11, 20, 21, 25, 40 }) do
    raid(n)
    roster()
    eq(L.set.name, n > 5 and "columns" or "row", "a raid of " .. n .. ": the " .. (n > 5 and "columns" or "row"))
    eq(L.cellW, n >= 21 and 80 or 96, "a raid of " .. n .. ": the cell width")
    agrees("a raid of " .. n, n)
end
eq(L.grid._width, 8 * 80 + 7 * 6, "40: 8 columns of 80")

-- Groups with holes: grouped by subgroup, the list stays compact.
WoW.raid = {}
for i = 1, 10 do
    local u = "raid" .. i
    WoW.SetUnit(u, { name = "Raider " .. i, class = "WARRIOR", player = true })
    WoW.raid[u] = { index = i, subgroup = i <= 5 and 1 or 3 }
end
roster()
agrees("groups 1 and 3", 10)
eq(L.grid._width, 96 + 6 + 96, "groups 1 and 3: two columns, no gap for group 2")

-- Raid pets: columns of 10 on the grid's right; the model's union counts them.
GRF.Settings.SetShowPets(true)
raid(12)
for i = 1, 12 do WoW.SetUnit("raidpet" .. i, { name = "Pet " .. i }) end
roster()
eq(shown(L.petCells), 12, "12 raid pets shown")
local pw, ph = Lay.HeaderSize(Lay.PETS, 12, 64, 28)
check(L.pets._width == pw and L.pets._height == ph, "the pet header's size: " .. L.pets._width .. "x" .. L.pets._height)
local s = GRF.LayoutState()
eq(s.w, L.grid._width + 6 + pw, "the union is the grid, the gap and the pets' own width")
for i = 1, 12 do WoW.units["raidpet" .. i] = nil end

-- In combat the client re-lists everyone under the set it has: a raid that
-- falls back to a party keeps the columns, and still lists the party. With
-- show-solo off, which would list a party too (GlassUI#30).
GRF.Settings.SetShowSolo(false)
raid(6)
roster()
WoW.enterCombat()
WoW.raid = nil
for i = 1, 6 do WoW.units["raid" .. i] = nil end
for i = 1, 4 do WoW.units["party" .. i] = nil end
party(1)
roster()
eq(L.set.name, "columns", "in combat the columns stay")
local n
n, units = shown(L.cells)
eq(table.concat(units, ","), "player,party1", "and the party is still listed (showParty kept on)")
raid(2)
roster()
n, units = shown(L.cells)
eq(table.concat(units, ","), "raid1,raid2", "converted in combat: the raid is listed")
eq(#WoW.blocked, 0, "nothing blocked")
WoW.leaveCombat()
eq(L.set.name, "row", "after combat: the row")
agrees("after combat", 2)

-- Back and forth: the batch clears the old set's anchors every time.
for _, n2 in ipairs({ 7, 3, 12, 1 }) do
    raid(n2)
    roster()
    agrees("swap to a raid of " .. n2, n2)
end

check(next(GRF.paintFailures) == nil, "no failures recorded")
done("test_layout_client")
