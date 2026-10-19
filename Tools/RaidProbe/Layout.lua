-- RaidProbe, the group layout (#69; the plan is Glass UI's docs/GROUP-LAYOUT.md):
-- what the build rests on, measured on 70450 first.     /fp steps raid layout
--   M1 one SecureGroupHeader with the plan's row and column attribute sets
--      (chosen by member count, GlassUI#30), swapped out of combat in one
--      _ignore batch with every child's anchors cleared, its bottom centre on
--      the baseline, and a roster change in combat that reflows it with
--      nothing blocked; and whether a column anchor child 1 keeps when two
--      columns become one (in combat, nothing may clear it) stretches it;
--   M2 the raid-pet header anchored to the grid's right edge: does it follow
--      the grid's own resize in combat?
--   M3 the baseline (152/1080 of UIParent's height) against the action bars;
--   M4 five party-pet buttons under their owners, in a container behind a
--      "[group:raid] hide; show" visibility driver, in combat too.
-- The same module as RaidProbe.lua (ForeverProbe returns it again by name).
-- Cells show their unit token, never a name: the log is meant to be shared.
-- Blocked actions are the host's baseline's lines (ForeverProbe.lua), read
-- after the /reload.

local _, NS = ...
local Probe = ForeverProbe:Module("RaidProbe", { api = 1, cmd = "raid" })

local function say(msg) Probe:Say(tostring(msg)) end
local function show(v) return Probe.Show(v, true) end

local LAYOUT = {
    W = 96, H = 60, PET_W = 64, PET_H = 28, PARTY_PET_H = 30, GAP = 6,
    BASE = 152 / 1080, PARTY_LIFT = 68, DRIVER = "[group:raid] hide; show",
    -- Half the widest HUD: 8 columns of 80 and 4 pet columns of 64, gaps of 6.
    HALF = (8 * 80 + 7 * 6 + 6 + 4 * 64 + 3 * 6) / 2,
}
-- Every attribute either set states, so a swap leaves nothing of the other
-- (a key a set leaves out is cleared).
LAYOUT.KEYS = { "showRaid", "showParty", "showPlayer", "showSolo", "groupBy", "groupingOrder", "point",
    "xOffset", "yOffset", "unitsPerColumn", "maxColumns", "columnAnchorPoint", "columnSpacing" }
-- The two sets of the amended plan (GlassUI#30), chosen by member count out
-- of combat: the row up to 5, party or raid; columns above. Both keep the
-- other kind's attributes on, so a group that changes kind in combat still
-- lists everyone (RAID is checked first: SecureGroupHeaders.lua:258-283).
-- showSolo is the player's setting; the probe has it on.
LAYOUT.COLUMNS = { name = "columns", showRaid = true, showParty = true, showPlayer = true, showSolo = true,
    groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8", point = "TOP", xOffset = 0, yOffset = -6,
    unitsPerColumn = 5, maxColumns = 8, columnAnchorPoint = "LEFT", columnSpacing = 6 }
LAYOUT.ROW = { name = "row", showRaid = true, showParty = true, showPlayer = true, showSolo = true,
    point = "LEFT", xOffset = 6, yOffset = 0, unitsPerColumn = 5, maxColumns = 8, columnAnchorPoint = "BOTTOM",
    columnSpacing = 6 }
LAYOUT.ROW_MAX = 5
LAYOUT.PETS = { name = "pets", showRaid = true, point = "TOP", xOffset = 0, yOffset = -4, unitsPerColumn = 10,
    maxColumns = 4, columnAnchorPoint = "LEFT", columnSpacing = 6 }
LAYOUT.PARTY_PETS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
LAYOUT.OWNER = { pet = "player", partypet1 = "party1", partypet2 = "party2", partypet3 = "party3",
    partypet4 = "party4" }
-- What may sit under the HUD (M3): Blizzard's bars, which GlassActionBars
-- skins in place, and its own Utility bar.
LAYOUT.BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBar5", "MultiBar6",
    "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "GlassActionBarsUtilityFrame" }

local LP = { cells = {}, petCells = {}, partyPets = {} }

--------------------------------------------------------------------------------
-- Geometry, in UIParent units
--------------------------------------------------------------------------------

local issecret = rawget(_G, "issecretvalue")
local function num(v)
    if issecret and issecret(v) then return nil end
    if type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function box(f)
    if not f then return nil end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok then return nil end
    l, b, w, h = num(l), num(b), num(w), num(h)
    if not (l and b and w and h) then return nil end
    local okS, s = pcall(function() return f:GetEffectiveScale() / UIParent:GetEffectiveScale() end)
    s = okS and num(s) or 1
    return { l = l * s, b = b * s, w = w * s, h = h * s, r = (l + w) * s, t = (b + h) * s, x = (l + w / 2) * s }
end

local function boxText(bx)
    if not bx then return "no rect" end
    return string.format("l=%.1f b=%.1f w=%.1f h=%.1f", bx.l, bx.b, bx.w, bx.h)
end

local function near(a, b) return a and b and math.abs(a - b) < 0.5 end

-- The size the client's configureChildren gives a header showing n cells of
-- w x h with this set (SecureGroupHeaders.lua:143-255), and its columns and
-- the cells per column. No cells: the header's minimum size.
local function expectSize(set, n, w, h)
    local vertical = set.point == "TOP" or set.point == "BOTTOM"
    if n == 0 then
        if vertical then return w, 0.1, 0, 0 end
        return 0.1, h, 0, 0
    end
    local per, cols = set.unitsPerColumn, 1
    if per and n > per then cols = math.min(math.ceil(n / per), set.maxColumns or 1) else per = n end
    local gap = vertical and math.abs(set.yOffset or 0) or math.abs(set.xOffset or 0)
    local cw, ch
    if vertical then cw, ch = w, per * h + (per - 1) * gap else cw, ch = per * w + (per - 1) * gap, h end
    if cols > 1 then
        local ca = set.columnAnchorPoint
        if ca == "LEFT" or ca == "RIGHT" then cw = cw + (cols - 1) * (cw + set.columnSpacing)
        else ch = ch + (cols - 1) * (ch + set.columnSpacing) end
    end
    return cw, ch, cols, per
end

-- How many cells the client lists for this set now (GetGroupHeaderType),
-- capped by what the set can show.
local function wantCells(set)
    local n
    if IsInRaid() and set.showRaid then
        n = GetNumGroupMembers()
    elseif IsInGroup() and set.showParty then
        n = GetNumSubgroupMembers() + (set.showPlayer and 1 or 0)
    elseif set.showSolo then
        n = GetNumSubgroupMembers() + 1
    else
        n = 0
    end
    return math.min(n, set.unitsPerColumn * set.maxColumns)
end

local function cellsOf(list)
    local s = { n = 0, units = {}, maxPoints = 0, cols = 0, rows = 0 }
    local lefts, tops = {}, {}
    for _, c in ipairs(list) do
        if c:IsShown() then
            s.n = s.n + 1
            s.units[#s.units + 1] = tostring(c:GetAttribute("unit"))
            s.maxPoints = math.max(s.maxPoints, c:GetNumPoints())
            local bx = box(c)
            if bx then
                lefts[math.floor(bx.l + 0.5)] = true
                tops[math.floor(bx.t + 0.5)] = true
            end
        end
    end
    for _ in pairs(lefts) do s.cols = s.cols + 1 end
    for _ in pairs(tops) do s.rows = s.rows + 1 end
    return s
end

-- The row's bottom is 68 raw UIParent units above the baseline; only the
-- baseline is a fraction of the height.
local function baseFor(set)
    return UIParent:GetHeight() * LAYOUT.BASE + (set == LAYOUT.ROW and LAYOUT.PARTY_LIFT or 0)
end

-- The set for the group as it is now, by member count. LP.force stands in
-- for a raid of more than 5 (the beta can't gather one).
local function wanted()
    return LP.force or ((GetNumGroupMembers() > LAYOUT.ROW_MAX) and LAYOUT.COLUMNS or LAYOUT.ROW)
end

--------------------------------------------------------------------------------
-- The frames (out of combat)
--------------------------------------------------------------------------------

function RaidProbe_LayoutAttribute(self, name, value)
    if name == "unit" and self.label then self.label:SetText(value and tostring(value) or "") end
end

-- Bottom centre on the baseline (the header grows upward from it).
local function placeGrid()
    LP.base = baseFor(LP.set)
    LP.grid:ClearAllPoints()
    LP.grid:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", UIParent:GetWidth() / 2, LP.base)
end

local function setAll(h, set)
    for _, k in ipairs(LAYOUT.KEYS) do h:SetAttribute(k, set[k]) end
end

-- The party-pet holder has one owner, its driver (GlassUI#31): re-registered
-- out of combat whenever the set changes. "hide" under the columns, whose
-- cells aren't in party order; the raid condition under the row.
local function holderDriver()
    if not LP.holder then return true end
    local values = LP.set == LAYOUT.COLUMNS and "hide" or LAYOUT.DRIVER
    local ok, err = pcall(RegisterStateDriver, LP.holder, "visibility", values)
    LP.driver, LP.driverOk = values, ok
    if not ok then say("layout: visibility driver \"" .. values .. "\" threw: " .. tostring(err)) end
    return ok
end

-- One refresh by re-setting one attribute to the value it already has.
-- Whether that alone fires OnAttributeChanged (counted on the grid) and
-- re-lays the header is measured; if it doesn't, a changing attribute does
-- it, and that is logged.
local function relay(h, list)
    local before = LP.pointChanges
    h:SetAttribute("point", h:GetAttribute("point"))
    local fired = LP.pointChanges > before
    local first = list[1]
    local relaid = not first or not first:IsShown() or first:GetNumPoints() > 0
    if not relaid then
        LP.refreshes = LP.refreshes + 1
        h:SetAttribute("rpRefresh", LP.refreshes)
    end
    return fired, relaid
end

-- The plan's orientation batch: _ignore on, the complete set, every child's
-- anchors cleared (or not: the swap experiment), _ignore off, then the
-- refresh.
local function applySet(set, clear)
    local g = LP.grid
    g:SetAttribute("_ignore", "attributeChanges")
    setAll(g, set)
    if clear then for _, c in ipairs(LP.cells) do c:ClearAllPoints() end end
    g:SetAttribute("_ignore", nil)
    LP.set = set
    placeGrid()
    holderDriver()
    local fired, relaid = relay(g, LP.cells)
    say(string.format("layout: %s set applied (anchors %s); the same-value refresh fired=%s re-laid=%s",
        set.name, clear and "cleared" or "kept", show(fired), show(relaid)))
    return fired, relaid
end

-- Laying out n cells in several columns gives child 1 the column anchor too
-- (SecureGroupHeaders.lua:203-205), and the one-column pass back on the real
-- roster sets only the point (:202), so a shown child 1 would keep it. The
-- count is logged, then every child's anchors are cleared and re-laid.
local function precreate(h, n)
    h:SetAttribute("startingIndex", 1 - n)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    local list = {}
    while h:GetAttribute("child" .. (#list + 1)) do list[#list + 1] = h:GetAttribute("child" .. (#list + 1)) end
    local stale = list[1] and list[1]:GetNumPoints() or 0
    for _, c in ipairs(list) do c:ClearAllPoints() end
    relay(h, list)
    return list, stale
end

local function build()
    if LP.grid then return true end
    if InCombatLockdown() then say("out of combat only") return false end
    LP.pointChanges, LP.refreshes = 0, 0
    local grid = CreateFrame("Frame", "RaidProbeLayoutGrid", UIParent, "SecureGroupHeaderTemplate")
    grid:SetAttribute("template", "RaidProbeLayoutCellTemplate")
    grid:SetAttribute("templateType", "Button")
    grid:HookScript("OnAttributeChanged", function(_, name)
        if name == "point" then LP.pointChanges = LP.pointChanges + 1 end
    end)
    LP.grid = grid
    LP.set = wanted()
    setAll(grid, LP.set)
    placeGrid()
    local staleGrid, stalePets
    LP.cells, staleGrid = precreate(grid, 40)

    local pets = CreateFrame("Frame", "RaidProbeLayoutPets", UIParent, "SecureGroupPetHeaderTemplate")
    pets:SetAttribute("template", "RaidProbeLayoutPetTemplate")
    pets:SetAttribute("templateType", "Button")
    setAll(pets, LAYOUT.PETS)
    -- One secure frame to another: the client's own resize of the grid in
    -- combat should carry the pets along (M2).
    pets:SetPoint("TOPLEFT", grid, "TOPRIGHT", LAYOUT.GAP, 0)
    LP.pets = pets
    LP.petCells, stalePets = precreate(pets, 40)

    local holder = CreateFrame("Frame", "RaidProbeLayoutPartyPets", UIParent)
    LP.holder = holder
    for k, unit in ipairs(LAYOUT.PARTY_PETS) do
        local b = CreateFrame("Button", "RaidProbeLayoutPartyPet" .. k, holder, "RaidProbeLayoutPetTemplate")
        b:SetSize(LAYOUT.W, LAYOUT.PARTY_PET_H)
        b:SetAttribute("unit", unit)
        if b.label then b.label:SetText(unit) end
        -- Under the row's k-th cell: player, then party1..4, the order the
        -- client lists a party in (no groupBy, no sort: GetGroupRosterInfo's).
        b:SetPoint("TOP", LP.cells[k], "BOTTOM", 0, -LAYOUT.GAP)
        b.unit = unit
        RegisterUnitWatch(b)
        LP.partyPets[k] = b
    end
    local ok = holderDriver()
    say(string.format("layout built: %d grid cells, %d raid-pet cells, %d party-pet buttons; visibility driver %s %s;"
        .. " child 1's anchors after precreation (then cleared): grid %d, pets %d",
        #LP.cells, #LP.petCells, #LP.partyPets, show(LP.driver), ok and "registered" or "threw", staleGrid, stalePets))
    return #LP.cells == 40 and #LP.petCells == 40 and #LP.partyPets == 5 and ok,
        "cells=" .. #LP.cells, "pets=" .. #LP.petCells, "partyPets=" .. #LP.partyPets, "driver=" .. show(ok)
end

-- Out of combat, the set that matches the group (as the build will do on
-- GROUP_ROSTER_UPDATE and after combat). In combat nothing of ours moves.
local function sync()
    if not LP.grid or InCombatLockdown() then return end
    local want = wanted()
    if want ~= LP.set then applySet(want, true) else placeGrid() end
end

--------------------------------------------------------------------------------
-- What is on screen, and the checks
--------------------------------------------------------------------------------

local function state()
    local s = { set = LP.set and LP.set.name, raid = IsInRaid(), group = IsInGroup(),
        members = GetNumGroupMembers(), combat = InCombatLockdown() == true }
    s.grid, s.pets = box(LP.grid), box(LP.pets)
    s.cells, s.petCells = cellsOf(LP.cells), cellsOf(LP.petCells)
    s.holder = LP.holder:IsShown()
    s.driverValues = LP.driver
    local ok, v = pcall(SecureCmdOptionParse, LP.driver or LAYOUT.DRIVER)
    s.driver = ok and v or "threw"
    s.partyPets = {}
    for k, b in ipairs(LP.partyPets) do
        local p = { unit = b.unit, exists = UnitExists(b.unit) == true, shown = b:IsShown(), visible = b:IsVisible() }
        local cell, bb = LP.cells[k], box(b)
        local cb = box(cell)
        p.owner = cell:GetAttribute("unit")
        p.under = p.owner == LAYOUT.OWNER[b.unit] and bb ~= nil and cb ~= nil
            and near(bb.t, cb.b - LAYOUT.GAP) and near(bb.x, cb.x)
        s.partyPets[k] = p
    end
    return s
end

local function line(s)
    local pp = {}
    for _, p in ipairs(s.partyPets) do
        pp[#pp + 1] = string.format("%s:%s%s%s", p.unit, p.exists and "pet" or "-", p.visible and ",visible" or "",
            p.visible and (p.under and ",under " or ",NOT under ") .. tostring(p.owner) or "")
    end
    return string.format("set=%s raid=%s members=%s combat=%s | grid %s cells=%d [%s] cols=%d rows=%d maxPoints=%d"
        .. " | pets %s cells=%d | partyPets holder=%s driver=%s (%s) %s",
        tostring(s.set), show(s.raid), show(s.members), show(s.combat), boxText(s.grid), s.cells.n,
        table.concat(s.cells.units, ","), s.cells.cols, s.cells.rows, s.cells.maxPoints, boxText(s.pets),
        s.petCells.n, show(s.holder), show(s.driver), show(s.driverValues), table.concat(pp, " "))
end

-- The grid against what the client's own layout gives the applied set: as
-- many cells as the roster lists, the size, columns and rows, at most two
-- anchors a cell, and its bottom centre on the baseline.
local function gridHolds(s)
    local set, probs = LP.set, {}
    local n = s.cells.n
    local want = wantCells(set)
    if n ~= want then probs[#probs + 1] = string.format("%d cells shown, the roster lists %d", n, want) end
    local w, h, cols, per = expectSize(set, n, LAYOUT.W, LAYOUT.H)
    if not s.grid then
        probs[#probs + 1] = "no grid rect"
    else
        if not (near(s.grid.w, w) and near(s.grid.h, h)) then
            probs[#probs + 1] = string.format("size %.1fx%.1f, want %.1fx%.1f", s.grid.w, s.grid.h, w, h)
        end
        if not near(s.grid.b, LP.base) then
            probs[#probs + 1] = string.format("bottom %.1f, baseline %.1f", s.grid.b, LP.base)
        end
        if not near(s.grid.x, UIParent:GetWidth() / 2) then
            probs[#probs + 1] = string.format("centre %.1f, want %.1f", s.grid.x, UIParent:GetWidth() / 2)
        end
    end
    if n > 0 then
        local vertical = set.point == "TOP" or set.point == "BOTTOM"
        local wantCols, wantRows = cols, per
        if not vertical then wantCols, wantRows = per, cols end
        if s.cells.cols ~= wantCols or s.cells.rows ~= wantRows then
            probs[#probs + 1] = string.format("%d columns x %d rows, want %d x %d", s.cells.cols, s.cells.rows,
                wantCols, wantRows)
        end
        if s.cells.maxPoints > 2 then probs[#probs + 1] = "a cell has " .. s.cells.maxPoints .. " anchors" end
    end
    return #probs == 0, table.concat(probs, "; ")
end

-- M2: the raid-pet header's top-left stays 6 right of the grid's top-right.
local function petsFollow(s)
    if not (s.grid and s.pets) then return false, "no pets or grid rect" end
    local dx, dy = s.pets.l - (s.grid.r + LAYOUT.GAP), s.pets.t - s.grid.t
    if near(dx, 0) and near(dy, 0) then return true, "" end
    return false, string.format("pets off the grid's edge by %.1f,%.1f", dx, dy)
end

-- M4: the holder shown exactly while the row is applied out of a raid; a
-- pet that exists shown there, under its owner's cell.
local function partyPetsHold(s)
    local probs, wantShown = {}, LP.set == LAYOUT.ROW and not s.raid
    if s.holder ~= wantShown then
        probs[#probs + 1] = string.format("holder shown=%s in a raid=%s under the %s", show(s.holder), show(s.raid),
            tostring(s.set))
    end
    for _, p in ipairs(s.partyPets) do
        if wantShown and p.exists and not p.visible then probs[#probs + 1] = p.unit .. " exists but isn't shown" end
        if p.visible and p.exists and not p.under then probs[#probs + 1] = p.unit .. " isn't under " .. LAYOUT.OWNER[p.unit] end
    end
    return #probs == 0, table.concat(probs, "; ")
end

-- A step's check. opts.roster: "solo", "party" or "raid", the group the step
-- asked for; opts.combat: must be (true) or not be (false) in combat;
-- opts.pets: M2; opts.partyPets: M4; opts.resized: the grid's size changed
-- since combat began (else the in-combat check proved nothing).
-- What the step asked for: solo, a party (not a raid) or a raid. Without it
-- a step would pass on the roster it was meant to change.
local ROSTER = {
    solo = function(s) return not s.group end,
    party = function(s) return s.group and not s.raid end,
    raid = function(s) return s.raid end,
}
local function rosterOf(s) return s.raid and "raid" or s.group and "party" or "solo" end

local function check(opts)
    return function()
        if not LP.grid then return false, "not built: /fp raid layout" end
        local s = state()
        say("layout: " .. line(s))
        local probs = {}
        local function need(ok, why) if not ok then probs[#probs + 1] = why end end
        if opts.combat ~= nil then need(s.combat == opts.combat, opts.combat and "not in combat" or "in combat") end
        if opts.roster then
            need(ROSTER[opts.roster](s), "the group is " .. rosterOf(s) .. ", the step wants " .. opts.roster)
        end
        need(gridHolds(s))
        if opts.pets then need(petsFollow(s)) end
        if opts.partyPets then need(partyPetsHold(s)) end
        if opts.resized then
            local b = LP.before and LP.before.grid
            need(b and s.grid and not (near(b.w, s.grid.w) and near(b.h, s.grid.h)),
                "the grid kept its size since combat began (" .. boxText(b) .. ")")
        end
        return #probs == 0, table.concat(probs, "; "), line(s)
    end
end

-- M3: UIParent at the owner's scale, every bar that sits under the HUD's
-- widest footprint, and the baseline's clearance over the highest.
local function bars()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local base, cx = H * LAYOUT.BASE, W / 2
    local function cvar(name)
        local ok, v = pcall(C_CVar.GetCVar, name)
        return ok and show(v) or "threw"
    end
    local okP, pw, ph = pcall(GetPhysicalScreenSize)
    say(string.format("M3: UIParent %.1fx%.1f scale=%s effective=%s physical=%sx%s uiScale=%s useUiScale=%s"
        .. " baseline=%.1f (party grid bottom %.1f)", W, H, show(UIParent:GetScale()),
        show(UIParent:GetEffectiveScale()), okP and show(pw) or "?", okP and show(ph) or "?", cvar("uiScale"),
        cvar("useUiScale"), base, base + LAYOUT.PARTY_LIFT))
    local top, by
    for _, name in ipairs(LAYOUT.BARS) do
        local f = rawget(_G, name)
        if type(f) == "table" and f.GetRect then
            local bx, visible = box(f), f:IsVisible()
            say(string.format("M3: %s visible=%s %s", name, show(visible), boxText(bx)))
            if visible and bx and bx.r > cx - LAYOUT.HALF and bx.l < cx + LAYOUT.HALF and bx.b < H / 3
                and (not top or bx.t > top) then
                top, by = bx.t, name
            end
        else
            say("M3: " .. name .. " absent")
        end
    end
    if not top then return false, "no visible bar under the HUD", string.format("baseline %.1f", base) end
    return base >= top, string.format("baseline %.1f, highest bar %s top %.1f, clearance %.1f", base, by, top,
        base - top)
end

-- M1's anchor clear: the other set and back without it (stale anchors?),
-- then back with it. Passes when the cleared swap holds.
local function swap()
    if not LP.grid then return false, "not built: /fp raid layout" end
    if InCombatLockdown() then say("out of combat only") return false end
    local home = LP.set
    applySet(home == LAYOUT.COLUMNS and LAYOUT.ROW or LAYOUT.COLUMNS, false)
    applySet(home, false)
    local kept = state()
    local keptOk, keptWhy = gridHolds(kept)
    say("layout: back without the clear: " .. (keptOk and "held" or keptWhy) .. " | " .. line(kept))
    applySet(home, true)
    local cleared = state()
    local ok, why = gridHolds(cleared)
    say("layout: back with the clear: " .. (ok and "held" or why))
    return ok, why, "without the clear: " .. (keptOk and "held" or keptWhy), "cells=" .. cleared.cells.n
end

-- A raid of 6 falling to 5 in combat under the columns: two columns become
-- one, and nothing may clear child 1's column anchor until combat ends. Out
-- of combat on the party's row: two rows (unitsPerColumn 1), back to one
-- without the clear, child 1's size read, then again after one more pass
-- (the header sizes itself from child 1). Passes when the cell keeps its
-- size; the set is applied cleanly after.
local function collapse()
    if not LP.grid then return false, "not built: /fp raid layout" end
    if InCombatLockdown() then say("out of combat only") return false end
    if cellsOf(LP.cells).n < 2 then return false, "needs two cells shown (a party of 2)" end
    local g, first, per = LP.grid, LP.cells[1], LP.set.unitsPerColumn
    g:SetAttribute("unitsPerColumn", 1)
    local split = first:GetNumPoints()
    g:SetAttribute("unitsPerColumn", per)
    local points, cell, grid = first:GetNumPoints(), box(first), box(g)
    relay(g, LP.cells)
    local cell2, grid2 = box(first), box(g)
    local kept = cell and cell2 and near(cell.w, LAYOUT.W) and near(cell.h, LAYOUT.H) and near(cell2.w, LAYOUT.W)
        and near(cell2.h, LAYOUT.H)
    local detail = string.format("child 1: %d anchors in two rows, %d back in one; cell %s, grid %s; after one more"
        .. " pass cell %s, grid %s", split, points, boxText(cell), boxText(grid), boxText(cell2), boxText(grid2))
    say("layout: stale column anchor: " .. detail)
    applySet(LP.set, true)
    return kept == true, detail
end

--------------------------------------------------------------------------------
-- The procedure
--------------------------------------------------------------------------------

local function synced()
    if InCombatLockdown() then return false, "still in combat" end
    local want = wanted()
    if LP.set ~= want then return false, "the " .. want.name .. " set isn't applied yet" end
    return true, want.name
end

-- The columns, as a raid of more than 5 gets them, so the in-combat roster
-- changes run on that set too.
local function force()
    if InCombatLockdown() then say("out of combat only") return false end
    LP.force = LAYOUT.COLUMNS
    sync()
    return check({ combat = false, pets = true })()
end

-- After combat: the forced set goes, and the group's own set applies.
local function released()
    if InCombatLockdown() then return false, "still in combat" end
    if LP.force then
        LP.force = nil
        sync()
    end
    return synced()
end

Probe:Steps("layout", {
    rev = 4,
    title = "Group layout (#69): one header, the pet header, the baseline, the party pets",
    { text = "GlassRaidFrames must be off for this (its grid would sit on the probe's). If it's on, turn it off in the "
        .. "AddOns list and /reload: the panel comes back here. Then Next.",
      check = function()
          local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "GlassRaidFrames")
          return ok and not loaded, "GlassRaidFrames loaded=" .. show(loaded)
      end },
    { text = "Out of combat: building the probe's grid (40 cells), raid-pet header (40) and five party-pet buttons.",
      auto = true, run = build },
    { text = "Solo, out of combat: one cell (yours) centred above the bars, your pet's bar under it if you have one. "
        .. "Then Next. Already in a group? Skip.",
      check = check({ roster = "solo", combat = false, partyPets = true }), screenshot = "layout solo" },
    { text = "Form a PARTY with one other player (not a raid), out of combat. If either of you has a pet, call it. "
        .. "Then Next.",
      check = check({ roster = "party", combat = false, partyPets = true }), screenshot = "layout party" },
    { text = "Out of combat: two rows and back to one without clearing the anchors, as a raid of 6 falling to 5 in "
        .. "combat does. Does the first cell stretch?", auto = true, run = collapse },
    { text = "Measuring the baseline against your action bars.", auto = true, run = bars, screenshot = "layout bars" },
    { text = "Do the grid and the pet bars sit clear above your action bars, with room to spare?", ask = true },
    { text = "Convert the party to a RAID, out of combat. Then Next. Expect the same row (5 or fewer), the party-pet "
        .. "bars gone and any pet in the raid-pet column to the right.",
      check = check({ roster = "raid", combat = false, pets = true, partyPets = true }),
      screenshot = "layout small raid" },
    { text = "Out of combat: swapping orientation without clearing the cells' anchors, then with it.",
      auto = true, run = swap },
    { text = "Out of combat: switching to the columns, as a raid of more than 5 gets them (a column of 2 here).",
      auto = true, run = force, screenshot = "layout columns" },
    { text = "Start combat (a training dummy or a mob) and stay in it.", event = "PLAYER_REGEN_DISABLED" },
    { text = "In combat: the other player LEAVES the raid. Next once they're gone.",
      check = check({ roster = "solo", combat = true, pets = true, partyPets = true, resized = true }),
      screenshot = "layout left" },
    { text = "Still in combat: invite them back (a party now). Next once they've joined. Can't invite in combat? "
        .. "Skip, and say so in the note.",
      check = check({ roster = "party", combat = true, pets = true, partyPets = true }),
      screenshot = "layout rejoined" },
    { text = "Leave combat and wait: the probe drops the columns and applies the row.", wait = released,
      timeout = 180, check = check({ roster = "party", combat = false, partyPets = true }),
      screenshot = "layout row after combat" },
    { text = "In the party: start combat again and stay in it.", event = "PLAYER_REGEN_DISABLED" },
    { text = "In combat: convert the party to a RAID. Next once converted. Not allowed in combat? Skip, and say so "
        .. "in the note.",
      check = check({ roster = "raid", combat = true, pets = true, partyPets = true }),
      screenshot = "layout raid in combat" },
    { text = "Leave combat and wait: the row stays (5 or fewer).", wait = synced, timeout = 180,
      check = check({ roster = "raid", combat = false, pets = true, partyPets = true }) },
    { text = "Type /reload (or press Reload now) so the log reaches the disk. Then turn GlassRaidFrames back on.",
      reload = true },
})

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if not LP.grid then return end
    if event == "PLAYER_REGEN_DISABLED" then
        LP.before = state()   -- what the in-combat roster change is measured against
    else
        sync()
    end
    -- After the header's own update and ours: the roster's, in combat too.
    C_Timer.After(0.3, function() say("layout " .. event .. ": " .. line(state())) end)
end)
Probe:RegisterEvents(ev, { "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })

Probe:Command("layout", function(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args == "bars" then bars() return end
    if args == "swap" then swap() return end
    if args == "collapse" then collapse() return end
    if not LP.grid then build() return end
    say("layout: " .. line(state()))
end, "[bars|swap|collapse] #69's grid, raid-pet header and party pets (again: report); bars: the baseline (M3); "
    .. "swap: the orientation batch without and with the anchor clear; collapse: two rows back to one, uncleared")

-- Seam for tests/test_probe.lua.
NS._layout = { LAYOUT = LAYOUT, LP = LP, expectSize = expectSize, wantCells = wantCells, build = build,
    state = state, check = check, applySet = applySet, sync = sync, swap = swap, bars = bars, force = force,
    released = released, precreate = precreate, collapse = collapse }
