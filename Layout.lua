-- Layout.lua: the group layout (#69). The plan is Glass UI's
-- docs/GROUP-LAYOUT.md; what it rests on was measured on 70450
-- (docs/FOREVER-PROBE.md item 14).
--
-- One SecureGroupHeaderTemplate for the whole group, sized by it: up to 5
-- members a row, more in columns of 5 (ceil(n/5) of them), the set chosen by
-- member count out of combat. Cells are the role's saved size (96x60 by
-- default), 80/96 as wide at 21 members or more.
-- Pets: in a raid, a raid-only pet header in columns of 10 on the grid's
-- right edge, one column always reserved while pets show; in a party, five
-- fixed buttons under their owners, behind a visibility driver.
-- Placed on a baseline: centred above the action bars (the HUD) or at the
-- side. In combat nothing of ours moves; the client's own reflow does, and
-- the grid, anchored by its bottom, grows upward. Every change waits in the
-- combat queue and is reconciled once after combat.
--
-- Layout.Install puts these functions over Header's at ADDON_LOADED when the
-- layout is on, so every caller keeps calling Header. Header.lua stays the
-- legacy branch (db.groupLayout = false, after /reload).

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Header = GRF.API, GRF.Header
local Layout = {}
GRF.Layout = Layout

Layout.CELL_W, Layout.CELL_H = 96, 60
Layout.TIER = 21                 -- from this many members, cells narrow
Layout.TIER_RATIO = 80 / 96
Layout.GAP = 6
Layout.ROW_MAX = 5               -- up to this many members: the row
Layout.PET_W, Layout.PET_H, Layout.PET_GAP = 64, 28, 4
Layout.PETS_PER_COLUMN, Layout.PET_COLUMNS = 10, 4
Layout.COUNT = 40                -- grid and raid-pet children, precreated
Layout.PARTY_PET_H = 30
Layout.BASE = 152 / 1080         -- the baseline, a fraction of UIParent's height
Layout.ROW_LIFT = 68             -- the row's bottom over the baseline, raw units
Layout.SIDE_MARGIN = 30
Layout.SIDE_BASE = -93           -- the side baseline, from UIParent's middle
Layout.MODES = { hud = true, side = true }
Layout.PARTY_PETS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }

-- The party pets' driver. [group:raid] reads false in combat; a unit test
-- doesn't (runs #238 and #240). Without "show solo", a lone pet would sit
-- under no cell.
Layout.DRIVER = "[@raid1,exists] hide; show"
Layout.DRIVER_NO_SOLO = "[@raid1,exists] hide; [@party1,exists] show; hide"

-- Every attribute a set states, so a swap leaves nothing of the other (a key
-- a set leaves out is cleared). showSolo is the player's setting.
Layout.KEYS = { "showRaid", "showParty", "showPlayer", "showSolo", "groupBy", "groupingOrder", "point",
    "xOffset", "yOffset", "unitsPerColumn", "maxColumns", "columnAnchorPoint", "columnSpacing" }
-- Both sets keep the other kind's attributes on: a group that changes kind in
-- combat still lists everyone (RAID is checked first).
Layout.COLUMNS = { name = "columns", showRaid = true, showParty = true, showPlayer = true,
    groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8", point = "TOP", xOffset = 0, yOffset = -Layout.GAP,
    unitsPerColumn = 5, maxColumns = 8, columnAnchorPoint = "LEFT", columnSpacing = Layout.GAP }
-- No groupBy: a party in INDEX order (player, party1..4) keeps the party
-- pets under their owners.
Layout.ROW = { name = "row", showRaid = true, showParty = true, showPlayer = true,
    point = "LEFT", xOffset = Layout.GAP, yOffset = 0, unitsPerColumn = 5, maxColumns = 8,
    columnAnchorPoint = "BOTTOM", columnSpacing = Layout.GAP }
Layout.PETS = { showRaid = true, point = "TOP", xOffset = 0, yOffset = -Layout.PET_GAP,
    unitsPerColumn = Layout.PETS_PER_COLUMN, maxColumns = Layout.PET_COLUMNS, columnAnchorPoint = "LEFT",
    columnSpacing = Layout.GAP }

-- What is built and applied (nil before the build).
local L = { cells = {}, petCells = {}, partyPets = {} }

local function sane(v) return type(v) == "number" and v == v and v > -10000 and v < 10000 end

local function clamp(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return nil end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function profile(role)
    return GRF.db and role and GRF.db.profiles[role] or nil
end

local function members()
    local ok, n = pcall(GetNumGroupMembers)
    if not ok or API.IsSecret(n) or type(n) ~= "number" then return 0 end
    return n
end

local function showSolo() return GRF.db and GRF.db.showSolo == true end

local function petsOn()
    local prof = profile(GRF.role)
    return prof ~= nil and prof.showPets == true
end

--------------------------------------------------------------------------------
-- Settings read
--------------------------------------------------------------------------------

function Layout.DefaultMode(role) return role == "HEALER" and "hud" or "side" end

-- "hud" (centred above the action bars) or "side", per role.
function Layout.ModeOf(role)
    local prof = profile(role)
    local m = prof and prof.layout
    if Layout.MODES[m] then return m end
    return Layout.DefaultMode(role)
end

-- The role's saved cell (its size at up to 20 members), validated.
function Layout.TileSize()
    local prof = profile(GRF.role)
    local s = prof and prof.size
    local w = type(s) == "table" and clamp(s.w, Header.MIN_W, Header.MAX_W)
    local h = type(s) == "table" and clamp(s.h, Header.MIN_H, Header.MAX_H)
    return w or Layout.CELL_W, h or Layout.CELL_H
end

-- The cell for the group as it is: narrower from 21 members.
function Layout.CellSize()
    local w, h = Layout.TileSize()
    if members() >= Layout.TIER then w = math.floor(w * Layout.TIER_RATIO + 0.5) end
    return w, h
end

-- The set for the group as it is, by member count.
function Layout.WantSet()
    return members() > Layout.ROW_MAX and Layout.COLUMNS or Layout.ROW
end

--------------------------------------------------------------------------------
-- Geometry, in UIParent units from its bottom-left
--------------------------------------------------------------------------------

-- The size the client's configureChildren gives a header showing n cells of
-- w x h with this set (SecureGroupHeaders.lua:133-258; measured identical,
-- run #238). No cells: the header's minimum size.
function Layout.HeaderSize(set, n, w, h)
    local vertical = set.point == "TOP" or set.point == "BOTTOM"
    if n <= 0 then
        if vertical then return w, 0.1 end
        return 0.1, h
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
    return cw, ch
end

local function units(list)
    local n = 0
    for _, c in ipairs(list) do if c:GetAttribute("unit") ~= nil then n = n + 1 end end
    return n
end

-- The baseline's anchor point for a mode: x is the union's centre (hud) or
-- left edge (side), y the baseline.
local function defaultAnchor(mode)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if mode == "hud" then return W / 2, H * Layout.BASE end
    return Layout.SIDE_MARGIN, H / 2 + Layout.SIDE_BASE
end

-- A drag in progress, else the role's save for the mode, else the default.
local function anchorFor(mode)
    if L.live then return L.live[1], L.live[2] end
    local prof = profile(GRF.role)
    local p = prof and type(prof.layoutPos) == "table" and prof.layoutPos[mode]
    if type(p) == "table" and sane(p.x) and sane(p.y) then return p.x, p.y end
    return defaultAnchor(mode)
end

-- Where everything goes for the applied set and the roster as the headers
-- list it now: the grid's rectangle and the union with the pets.
local function geometry()
    local set, cw, ch = L.set, L.cellW, L.cellH
    local n = units(L.cells)
    local gw, gh = Layout.HeaderSize(set, n, cw, ch)
    local mode = Layout.ModeOf(GRF.role)
    local ax, ay = anchorFor(mode)
    local gy = ay + (set == Layout.ROW and Layout.ROW_LIFT or 0)
    local raid = IsInRaid() == true
    local pets = petsOn()
    -- One pet column always kept in a raid (a first pet in combat lands in
    -- room already left), more as the pets need them.
    local petCols, petRows = 0, 0
    if pets and raid and n > 0 then
        local np = units(L.petCells)
        petCols = math.max(1, math.min(Layout.PET_COLUMNS, math.ceil(np / Layout.PETS_PER_COLUMN)))
        petRows = math.min(np, Layout.PETS_PER_COLUMN)
    end
    local block = petCols > 0 and (Layout.GAP + petCols * Layout.PET_W + (petCols - 1) * Layout.GAP) or 0
    local gl = mode == "hud" and ax - (gw + block) / 2 or ax
    local top = gy + gh
    local b = gy
    if petRows > 0 then b = math.min(b, top - (petRows * Layout.PET_H + (petRows - 1) * Layout.PET_GAP)) end
    -- The party's pet row under the cells.
    if pets and set == Layout.ROW and not raid and n > 0 then b = gy - Layout.GAP - Layout.PARTY_PET_H end
    local s = { mode = mode, ax = ax, ay = ay, gridL = gl, gridB = gy, gridW = gw, gridH = gh,
        l = gl, b = b, w = gw + block, h = top - b, top = top, base = ay }
    if n == 0 then s.w, s.h = 0, 0 end   -- nothing shown: other addons keep their own places
    return s
end

--------------------------------------------------------------------------------
-- Applying (out of combat)
--------------------------------------------------------------------------------

-- Re-setting an attribute to the value it has re-lays the header (measured,
-- run #238).
local function relay(h) h:SetAttribute("point", h:GetAttribute("point")) end

local function setAll(h, set)
    for _, k in ipairs(Layout.KEYS) do
        local v = set[k]
        if k == "showSolo" then v = showSolo() end
        h:SetAttribute(k, v)
    end
end

-- The orientation batch: _ignore on, the complete set, every child's anchors
-- cleared (the client clears only the unused ones, and a shown cell would
-- keep its old anchor beside the new), _ignore off, one refresh.
local function applySet(set)
    local g = L.grid
    g:SetAttribute("_ignore", "attributeChanges")
    setAll(g, set)
    for _, c in ipairs(L.cells) do c:ClearAllPoints() end
    g:SetAttribute("_ignore", nil)
    L.set = set
    relay(g)
end

-- Resize tiles; one tile's relayout failing never stops the rest.
local function resizeAll(list, w, h)
    for _, child in ipairs(list) do
        child:SetSize(w, h)
        if child.relayout then
            local ok, err = pcall(child.relayout, child)
            if not ok then API.Fail("relayout", err) end
        end
    end
end

-- The raid-pet header shown with the role's pets; the party pets' driver for
-- the set (the driver alone owns the holder: a Hide() would fight it).
local function applyPets()
    local on = petsOn()
    if L.pets and L.pets:IsShown() ~= on then
        L.pets:SetShown(on)
        -- Hidden, the header stops updating its children: release their
        -- units; shown, re-sync from what it assigned.
        for _, child in ipairs(L.petCells) do
            Header.UnitChanged(child, "unit", on and child:GetAttribute("unit") or nil)
        end
    end
    if not L.holder then return end
    -- The same for the party pets' fixed tokens: nothing paints them while off.
    if L.partyOn ~= on then
        L.partyOn = on
        for _, b in ipairs(L.partyPets) do Header.UnitChanged(b, "unit", on and b:GetAttribute("unit") or nil) end
    end
    local want = "hide"
    if on and L.set == Layout.ROW then want = showSolo() and Layout.DRIVER or Layout.DRIVER_NO_SOLO end
    if want == L.driver then return end
    local ok, err = pcall(RegisterStateDriver, L.holder, "visibility", want)
    if ok then L.driver = want else API.Fail("party pets", err) end
end

-- The grid on its anchor, and the insecure box (the mover's target) on the
-- union.
local function place()
    local s = geometry()
    local g = L.grid
    g:ClearAllPoints()
    if s.mode == "hud" then
        g:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", s.gridL + s.gridW / 2, s.gridB)
    else
        g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.gridL, s.gridB)
    end
    L.state = s
    local bw, bh = Layout.Size()
    L.box:ClearAllPoints()
    L.box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.l, s.b)
    L.box:SetSize(bw, bh)
end

-- Everything for the role and the group as they are now. Out of combat.
-- Doesn't announce: the callers do, once (as Header's functions).
function Layout.Apply()
    if not L.grid or InCombatLockdown() then return false end
    local set = Layout.WantSet()
    local cw, ch = Layout.CellSize()
    local resized = cw ~= L.cellW or ch ~= L.cellH
    if resized then
        L.cellW, L.cellH = cw, ch
        resizeAll(L.cells, cw, ch)
        resizeAll(L.partyPets, cw, Layout.PARTY_PET_H)
    end
    -- A new size re-lays too: the header sizes itself from child 1.
    if set ~= L.set or resized then applySet(set) end
    if L.grid:GetAttribute("showSolo") ~= showSolo() then L.grid:SetAttribute("showSolo", showSolo()) end
    applyPets()
    place()
    return true
end

-- Apply and tell other addons (the layout's own triggers).
function Layout.Refresh()
    if Layout.Apply() and GRF.Announce then GRF.Announce() end
end

--------------------------------------------------------------------------------
-- Building (out of combat, the build step of the combat queue)
--------------------------------------------------------------------------------

-- Laying out n cells in several columns gives child 1 the column anchor too,
-- and the one-column pass back to the real roster keeps it (run #238): every
-- child's anchors are cleared and the header re-laid.
local function precreate(h, n)
    h:SetAttribute("startingIndex", 1 - n)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    local i = 1
    while h:GetAttribute("child" .. i) do
        h:GetAttribute("child" .. i):ClearAllPoints()
        i = i + 1
    end
    relay(h)
end

local function buildPets(setup)
    local h = CreateFrame("Frame", "GlassRaidFramesRaidPets", UIParent, "SecureGroupPetHeaderTemplate")
    h:SetAttribute("template", Header.TEMPLATE)
    h:SetAttribute("templateType", "Button")
    setAll(h, Layout.PETS)
    h:SetAttribute("showSolo", nil)
    -- One secure frame to another: the grid's own resize in combat carries
    -- the pets along (M2, run #238).
    h:SetPoint("TOPLEFT", L.grid, "TOPRIGHT", Layout.GAP, 0)
    precreate(h, Layout.COUNT)
    Header.Collect(h, L.petCells, setup, true)
    resizeAll(L.petCells, Layout.PET_W, Layout.PET_H)
    relay(h)
    L.pets = h
end

-- Five fixed buttons, each under its owner's cell: the client lists a party
-- as the player, then party1..4 (the row has no groupBy).
local function buildPartyPets(setup)
    local holder = CreateFrame("Frame", "GlassRaidFramesPartyPets", UIParent)
    L.holder = holder
    for k, unit in ipairs(Layout.PARTY_PETS) do
        local b = CreateFrame("Button", "GlassRaidFramesPartyPet" .. k, holder, Header.TEMPLATE)
        b:SetAttribute("unit", unit)
        b.isPet = true
        b:SetPoint("TOP", L.cells[k], "BOTTOM", 0, -Layout.GAP)
        RegisterUnitWatch(b)
        L.partyPets[k] = b
        Header.Dress(b, setup)
    end
end

function Layout.Build(setup)
    if L.grid then return end
    local g = CreateFrame("Frame", "GlassRaidFramesGrid", UIParent, "SecureGroupHeaderTemplate")
    g:SetAttribute("template", Header.TEMPLATE)
    g:SetAttribute("templateType", "Button")
    L.grid = g
    L.set = Layout.WantSet()
    setAll(g, L.set)
    g:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", UIParent:GetWidth() / 2, UIParent:GetHeight() * Layout.BASE)
    precreate(g, Layout.COUNT)
    Header.Collect(g, L.cells, setup)
    L.box = CreateFrame("Frame", "GlassRaidFramesLayoutBox", UIParent)
    Header.container = L.box
    -- The pets must not cost the grid.
    local okP, errP = pcall(buildPets, setup)
    if not okP then API.Fail("pet header", errP) end
    local okH, errH = pcall(buildPartyPets, setup)
    if not okH then API.Fail("party pets", errH) end
    if #L.cells < Layout.COUNT then
        API.Fail("header", "precreated " .. #L.cells .. " of " .. Layout.COUNT .. " children")
    end
    if okP and #L.petCells < Layout.COUNT then
        API.Fail("pet header", "precreated " .. #L.petCells .. " of " .. Layout.COUNT .. " pet tiles")
    end
    Layout.Apply()
end

--------------------------------------------------------------------------------
-- Header's functions, for the layout
--------------------------------------------------------------------------------

Layout.ApplySize = Layout.Apply
Layout.ApplyPets = Layout.Apply

function Layout.SetShowSolo()
    if not L.grid or InCombatLockdown() then return false end
    Layout.Refresh()   -- the attribute, the driver and the union follow db.showSolo
    return true
end

-- The block a mover covers (never empty: a hidden grid still gets a handle).
function Layout.Size()
    local s = L.state
    if not s then return Layout.CELL_W, Layout.CELL_H end
    return math.max(s.w, L.cellW or Layout.CELL_W), math.max(s.h, L.cellH or Layout.CELL_H)
end

-- The union's centre as an offset from UIParent's centre, for an anchor.
local function centreFor(ax, ay)
    local s = L.state
    local bw, bh = Layout.Size()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    return s.l + (ax - s.ax) + bw / 2 - W / 2, s.b + (ay - s.ay) + bh / 2 - H / 2
end

function Layout.PositionOf()
    if not L.state then return 0, 0 end
    return centreFor(L.state.ax, L.state.ay)
end

function Layout.DefaultPosition()
    if not L.state then return 0, 0 end
    return centreFor(defaultAnchor(L.state.mode))
end

-- A mover's centre (x, y, from UIParent's centre) moves the baseline: kept
-- while dragging (save = false), saved for the role's mode (save = true).
-- With save = nil, it re-places from the role's own saves: that's what
-- every other caller means by "put it where it belongs".
function Layout.SetPosition(x, y, save)
    if not L.grid or InCombatLockdown() then return false end
    if save == nil then
        L.live = nil
        place()
        return true
    end
    local cx, cy = centreFor(L.state.ax, L.state.ay)
    local ax, ay = L.state.ax + (x - cx), L.state.ay + (y - cy)
    if save then
        L.live = nil
        local prof = profile(GRF.role)
        if prof then
            if type(prof.layoutPos) ~= "table" then prof.layoutPos = {} end
            prof.layoutPos[L.state.mode] = { x = ax, y = ay }
        end
    else
        L.live = { ax, ay }
    end
    place()
    if save and GRF.Announce then GRF.Announce() end
    return true
end

-- Reset: the layout's own save goes; pos and petPos stay set aside.
function Layout.ForgetPosition(prof)
    prof.layoutPos = nil
    L.live = nil
end

-- The pets follow the grid: no mover of their own.
function Layout.PetsMovable() return false end

function Layout.Rect()
    local s = L.state
    if not s then return nil end
    return s.l, s.b, s.w, s.h
end

-- What other addons read (GlassUnitFrames' link): a fresh table, or nil
-- before the build. UIParent units from its bottom-left.
function Layout.State()
    local s = L.state
    if not (s and GRF.role) then return nil end
    return { role = GRF.role, l = s.l, b = s.b, w = s.w, h = s.h, top = s.top, base = s.base, mode = s.mode }
end

-- Every tile click-casting and the indicators reach: grid, raid pets, party pets.
function Layout.AllChildren()
    local all = {}
    for _, list in ipairs({ L.cells, L.petCells, L.partyPets }) do
        for _, c in ipairs(list) do all[#all + 1] = c end
    end
    return all
end

local INSTALLED = { "Build", "ApplySize", "ApplyPets", "SetShowSolo", "PositionOf", "DefaultPosition",
    "SetPosition", "Rect", "AllChildren", "TileSize", "Size", "PetsMovable", "ForgetPosition" }

-- At ADDON_LOADED, before the build, when the layout is on.
function Layout.Install()
    for _, k in ipairs(INSTALLED) do Header[k] = Layout[k] end
    Header.DEFAULT_W, Header.DEFAULT_H = Layout.CELL_W, Layout.CELL_H
    Header.children, Header.petChildren = L.cells, L.petCells
end

--------------------------------------------------------------------------------
-- Triggers: the roster, pets, the screen. One refresh a frame, after the
-- headers' own updates; in combat it waits for the queue.
--------------------------------------------------------------------------------

local scheduled = false
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function()
    if not (GRF.layoutOn and L.grid) or scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        GRF.WhenOutOfCombat("layout", Layout.Refresh, false)
    end)
end)
API.RegisterEvents(watcher, { "GROUP_ROSTER_UPDATE", "UNIT_PET", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" })

Layout._test = { L = L, geometry = geometry, watcher = watcher, applySet = applySet }
