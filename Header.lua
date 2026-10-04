-- Header.lua: the group layout, built on SecureGroupHeaderTemplate (probe
-- item 1: it follows joins, leaves and party->raid conversion in combat).
--
-- Eight headers, one per raid group (groupFilter 1..8), side by side in one
-- container, as EllesmereUI's separated mode (it ships on Forever). Header 1
-- also shows the party and the player, so the client itself switches between
-- the party column and the raid grid, in combat too: there is no mode code.
--
-- No initialConfigFunction (restricted snippets are broken on Forever): the
-- child template (GlassRaidFrames.xml) carries the size, and every child is
-- PRECREATED out of combat (startingIndex = -4, Cell's and Ellesmere's trick)
-- so Frames.Setup can dress all 40 before any fight. A child's unit changes in
-- combat; its OnAttributeChanged hook moves it in the engine.
--
-- The container is protected (it parents secure frames): it moves only out of
-- combat, through Header.SetPosition.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Engine = GRF.API, GRF.Engine
local Header = {}
GRF.Header = Header

Header.GROUPS = 8
Header.PER_GROUP = 5
-- The default tile, Cell's look (the owner's 66x46 at Cell's own scale,
-- measured side by side). Must match GlassRaidFrames.xml. A role can resize
-- (profiles[role].size), within Header.MIN/MAX.
Header.DEFAULT_W, Header.DEFAULT_H = 82, 58
Header.MIN_W, Header.MAX_W = 50, 160
Header.MIN_H, Header.MAX_H = 36, 100   -- under 36 the 12px debuff row covers the name
Header.GAP = 4
Header.TEMPLATE = "GlassRaidFramesUnitTemplate"

Header.headers = {}
Header.children = {}

-- Pets (#13): a SecureGroupPetHeaderTemplate (measured working in game,
-- 2026-09-29) in its own container: by default in the column right after the
-- LAST group column in use (owner's call: dynamic, but always a column of its
-- own; a party's pets sit next to the party), anchored to the grid so it
-- follows it, re-placed out of combat on roster changes; once moved
-- (unlock mode has a second mover), its own saved spot per role
-- (profiles[role].petPos). The header picks pet/partypetN/raidpetN itself
-- (SecureGroupHeaders.lua GetPetUnit), in and out of combat.
Header.PET_COUNT = 20      -- precreated; more pets than this in a raid don't show
Header.PETS_PER_COLUMN = 5
Header.PET_HEIGHT = 0.6    -- of the tile height
Header.petChildren = {}

-- Default positions per role (#7): the healer's grid in the lower middle,
-- between GlassUnitFrames' player and target frames; the others on the left
-- side, so the Cooldown Manager keeps the centre. UIParent is 768 units tall
-- at the default scale; the grid stays above y = -250, clear of the action
-- bars. The side's x comes from UIParent's actual width (screen aspect).
Header.HEALER_POS = { x = 0, y = -120 }
Header.SIDE_Y = 60
Header.SIDE_MARGIN = 30

local function clamp(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return nil end
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

-- The current role's tile size, validated (a bad save falls back).
function Header.TileSize()
    local prof = GRF.Profile and GRF.Profile()
    local s = prof and prof.size
    local w = type(s) == "table" and clamp(s.w, Header.MIN_W, Header.MAX_W)
    local h = type(s) == "table" and clamp(s.h, Header.MIN_H, Header.MAX_H)
    return w or Header.DEFAULT_W, h or Header.DEFAULT_H
end

-- The whole grid (8 columns of 5).
function Header.Size()
    local tw, th = Header.TileSize()
    local w = Header.GROUPS * tw + (Header.GROUPS - 1) * Header.GAP
    local h = Header.PER_GROUP * th + (Header.PER_GROUP - 1) * Header.GAP
    return w, h
end

-- Resize a list of tiles; one tile's relayout failing never stops the rest.
local function resizeAll(list, w, h)
    for _, child in ipairs(list) do
        child:SetSize(w, h)
        if child.relayout then
            local ok, err = pcall(child.relayout, child)
            if not ok then API.Fail("relayout", err) end
        end
    end
end

-- Resize every tile to the current role's size, out of combat. The header
-- chains each child to the previous one (SecureGroupHeaders.lua:211), so a
-- column re-flows by itself; only the columns' offsets and the container are
-- ours. Keeps the grid's centre where it was.
function Header.ApplySize()
    local c = Header.container
    if not c or InCombatLockdown() then return false end
    local tw, th = Header.TileSize()
    local ph = Header.PetHeight()
    resizeAll(Header.children, tw, th)
    resizeAll(Header.petChildren, tw, ph)
    local pets = Header.petHeader
    if pets then
        -- point TOP: child1 centres on the header's width (the same
        -- stale-size trap as the group headers).
        pets:SetSize(tw, ph)
        if Header.petContainer then Header.petContainer:SetSize(Header.PetSize()) end
    end
    for group, h in pairs(Header.headers) do
        -- The header centres its first child on its OWN width (child1's TOP on
        -- the header's TOP, SecureGroupHeaders.lua:202) and only sets that
        -- width in its own layout pass: set it now, or every column sits half
        -- the width change to the side until the next roster update.
        h:SetWidth(tw)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", c, "TOPLEFT", (group - 1) * (tw + Header.GAP), 0)
    end
    c:SetSize(Header.Size())
    -- The default pet column's offset is counted in tile widths: re-place it.
    Header.PlacePets()
    return true
end

local function sane(v) return type(v) == "number" and v == v and v > -2000 and v < 2000 end

function Header.DefaultPosition(role)
    if role == "HEALER" then return Header.HEALER_POS.x, Header.HEALER_POS.y end
    local w = UIParent:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = 1024 end
    local gridW = Header.Size()
    return math.floor(-w / 2 + gridW / 2 + Header.SIDE_MARGIN), Header.SIDE_Y
end

-- The current role's saved position, validated: a malformed save falls back
-- to the role's default.
function Header.PositionOf()
    local prof = GRF.Profile and GRF.Profile()
    local p = prof and prof.pos
    if type(p) == "table" and sane(p.x) and sane(p.y) then return p.x, p.y end
    return Header.DefaultPosition(GRF.role)
end

-- CENTER of the container on CENTER of UIParent, offset (x, y); `save` stores
-- it in the current role's profile. Out of combat.
function Header.SetPosition(x, y, save)
    local c = Header.container
    if not c or InCombatLockdown() then return false end
    c:ClearAllPoints()
    c:SetPoint("CENTER", UIParent, "CENTER", x, y)
    local prof = save and GRF.Profile and GRF.Profile()
    if prof then prof.pos = { x = x, y = y } end
    -- Saved means settled (drag stop, combat mid-drag, reset): tell other
    -- addons. Live drag updates (save = false) don't spam them.
    if save and GRF.Announce then GRF.Announce() end
    return true
end

-- Where the grid is now, for other addons (GlassUnitFrames makes room):
-- left, bottom, width, height in UIParent units, or nil.
function Header.Rect()
    local c = Header.container
    if not c then return nil end
    local ok, l, b, w, h = pcall(c.GetRect, c)
    if not ok or type(l) ~= "number" then return nil end
    -- Pets shown: the union, so another addon making room leaves them room too.
    local pc = Header.petContainer
    if pc and Header.PetsShown() then
        local okP, pl, pb, pw, ph = pcall(pc.GetRect, pc)
        if okP and type(pl) == "number" then
            local r, t = math.max(l + w, pl + pw), math.max(b + h, pb + ph)
            l, b = math.min(l, pl), math.min(b, pb)
            w, h = r - l, t - b
        end
    end
    return l, b, w, h
end

local function childUnitChanged(child, name, value)
    if name ~= "unit" then return end
    -- Our own tables and insecure regions only: fine in combat.
    Engine.SetUnit(child, value)
    if child.onUnitChanged then child:onUnitChanged(value) end
end

local function newHeader(group, parent)
    local h = CreateFrame("Frame", "GlassRaidFramesGroup" .. group, parent, "SecureGroupHeaderTemplate")
    h:SetAttribute("template", Header.TEMPLATE)
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("groupFilter", tostring(group))
    h:SetAttribute("showRaid", true)
    if group == 1 then
        -- The party column: the player and party1-4 in a party, group 1 in a raid.
        h:SetAttribute("showParty", true)
        h:SetAttribute("showPlayer", true)
        h:SetAttribute("showSolo", GRF.db and GRF.db.showSolo == true)
    end
    h:SetAttribute("point", "TOP")
    h:SetAttribute("yOffset", -Header.GAP)
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("maxColumns", 1)
    h:SetAttribute("unitsPerColumn", Header.PER_GROUP)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)   -- the column offset is ApplySize's (one formula)
    -- Precreate every child (a header only makes children while shown).
    h:SetAttribute("startingIndex", 1 - Header.PER_GROUP)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    return h
end

function Header.PetHeight()
    local _, th = Header.TileSize()
    -- Never under the tile minimum: below it the debuff row covers the name.
    return math.max(Header.MIN_H, math.floor(th * Header.PET_HEIGHT + 0.5))
end

-- The pet block: columns of 5, as many as PET_COUNT needs.
function Header.PetSize()
    local tw = Header.TileSize()
    local cols = math.ceil(Header.PET_COUNT / Header.PETS_PER_COLUMN)
    local rows = Header.PETS_PER_COLUMN
    return cols * tw + (cols - 1) * Header.GAP, rows * Header.PetHeight() + (rows - 1) * Header.GAP
end

-- The pets' saved spot for the current role, or nil (then: beside the grid).
function Header.PetPositionOf()
    local prof = GRF.Profile and GRF.Profile()
    local p = prof and prof.petPos
    if type(p) == "table" and sane(p.x) and sane(p.y) then return p.x, p.y end
    return nil
end

-- The last group column with anyone in it (1 in a party or solo).
function Header.LastColumn()
    for g = Header.GROUPS, 2, -1 do
        local h = Header.headers[g]
        local child = h and h:GetAttribute("child1")
        if child and child:GetAttribute("unit") then return g end
    end
    return 1
end

-- Place the pet block: its saved spot, or the column after the last group
-- in use (anchored to the grid, so it follows it). Out of combat (the
-- container is protected).
function Header.PlacePets()
    local pc = Header.petContainer
    if not pc or InCombatLockdown() then return false end
    pc:ClearAllPoints()
    local x, y = Header.PetPositionOf()
    if x then
        pc:SetPoint("CENTER", UIParent, "CENTER", x, y)
    else
        local tw = Header.TileSize()
        pc:SetPoint("TOPLEFT", Header.container, "TOPLEFT", Header.LastColumn() * (tw + Header.GAP), 0)
    end
    return true
end

-- Move the pet block to (x, y) (CENTER on UIParent's centre); `save` stores it
-- in the current role's profile. Out of combat.
function Header.SetPetPosition(x, y, save)
    local pc = Header.petContainer
    if not pc or InCombatLockdown() then return false end
    pc:ClearAllPoints()
    pc:SetPoint("CENTER", UIParent, "CENTER", x, y)
    local prof = save and GRF.Profile and GRF.Profile()
    if prof then prof.petPos = { x = x, y = y } end
    -- Saved means settled: the announced rectangle includes the pets.
    if save and GRF.Announce then GRF.Announce() end
    return true
end

-- Every tile, group and pet (click-casting binds them all).
function Header.AllChildren()
    local all = {}
    for _, c in ipairs(Header.children) do all[#all + 1] = c end
    for _, c in ipairs(Header.petChildren) do all[#all + 1] = c end
    return all
end

local function dress(child, setup)
    local ok, err = pcall(setup, child)
    if not ok then API.Fail("setup", err) end
    child:HookScript("OnAttributeChanged", childUnitChanged)
    Engine.Register(child)
    -- The header may have assigned a unit before our hook existed.
    childUnitChanged(child, "unit", child:GetAttribute("unit"))
end

-- Collect a header's precreated children into `list`, dressing each. Pet
-- tiles are flagged before dressing (they get only the debuff row): a
-- precreated child has no unit yet to tell.
local function collect(h, list, setup, isPet)
    local i = 1
    while h do
        local child = h:GetAttribute("child" .. i)
        if not child then break end
        child.isPet = isPet or nil
        table.insert(list, child)
        dress(child, setup)
        i = i + 1
    end
end

local function newPetHeader(parent, setup)
    local h = CreateFrame("Frame", "GlassRaidFramesPets", parent, "SecureGroupPetHeaderTemplate")
    -- Columns of 5 going right: a ninth "group" of pets.
    h:SetAttribute("template", Header.TEMPLATE)
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("showRaid", true)
    h:SetAttribute("showParty", true)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("showSolo", GRF.db and GRF.db.showSolo == true)   -- like the party column
    h:SetAttribute("point", "TOP")
    h:SetAttribute("yOffset", -Header.GAP)
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("unitsPerColumn", Header.PETS_PER_COLUMN)
    h:SetAttribute("maxColumns", math.ceil(Header.PET_COUNT / Header.PETS_PER_COLUMN))
    h:SetAttribute("columnAnchorPoint", "LEFT")
    h:SetAttribute("columnSpacing", Header.GAP)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    h:SetAttribute("startingIndex", 1 - Header.PET_COUNT)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    collect(h, Header.petChildren, setup, true)
    return h
end

-- Pets shown or hidden for the current role (profiles[role].showPets), and
-- placed. Out of combat: hiding or moving a secure header is protected.
function Header.ApplyPets()
    local h = Header.petHeader
    if not h or InCombatLockdown() then return false end
    local prof = GRF.Profile and GRF.Profile()
    local show = prof and prof.showPets == true
    h:SetShown(show)
    -- A hidden header stops updating its children: release their units so the
    -- engine doesn't keep painting hidden tiles for stale tokens; shown again,
    -- re-sync from what the header assigned.
    for _, child in ipairs(Header.petChildren) do
        childUnitChanged(child, "unit", show and child:GetAttribute("unit") or nil)
    end
    Header.PlacePets()
    return true
end

function Header.PetsShown()
    return Header.petHeader ~= nil and Header.petHeader:IsShown()
end

-- Build once, out of combat (the build step of the combat queue).
function Header.Build(setup)
    if Header.container then return end
    local c = CreateFrame("Frame", "GlassRaidFramesContainer", UIParent)
    c:SetSize(Header.Size())
    Header.container = c
    Header.SetPosition(Header.PositionOf())
    for group = 1, Header.GROUPS do
        -- One header failing to build must not cost the other groups.
        local okH, h = pcall(newHeader, group, c)
        if not okH or not h then
            API.Fail("header " .. group, h)
            h = nil
        end
        Header.headers[group] = h
        collect(h, Header.children, setup)
    end
    local pc = CreateFrame("Frame", "GlassRaidFramesPetContainer", UIParent)
    Header.petContainer = pc
    local okP, pets = pcall(newPetHeader, pc, setup)
    if okP and pets then
        Header.petHeader = pets
        if #Header.petChildren < Header.PET_COUNT then
            API.Fail("pet header", "precreated " .. #Header.petChildren .. " of " .. Header.PET_COUNT .. " pet tiles")
        end
        Header.ApplyPets()
    else
        API.Fail("pet header", pets)
    end
    Header.ApplySize()   -- the role's own size, if it isn't the template's
    if #Header.children < Header.GROUPS * Header.PER_GROUP then
        API.Fail("header", "precreated " .. #Header.children .. " of "
            .. Header.GROUPS * Header.PER_GROUP .. " children")
    end
end

-- showSolo on the party header. Out of combat (an attribute).
function Header.SetShowSolo(on)
    local h = Header.headers[1]
    if not h or InCombatLockdown() then return false end
    h:SetAttribute("showSolo", on == true)
    -- Your pet follows your own tile: no lone pet under an empty grid.
    if Header.petHeader then Header.petHeader:SetAttribute("showSolo", on == true) end
    return true
end

-- The side default depends on UIParent's width: re-place an unsaved role's
-- grid when the UI scale or resolution changes (out of combat).
local rescaler = CreateFrame("Frame")
rescaler:SetScript("OnEvent", function()
    if not Header.container then return end
    local prof = GRF.Profile and GRF.Profile()
    if prof and prof.pos then return end   -- a saved spot stays where it was put
    GRF.WhenOutOfCombat("rescale", function()
        -- Not saved (it's still the default), but it moved: tell other addons.
        if Header.SetPosition(Header.PositionOf()) and GRF.Announce then GRF.Announce() end
    end, false)
end)
API.RegisterEvents(rescaler, { "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" })

-- The pet column follows the roster (the last group in use changes). The
-- headers reassign their children on the same event, so wait a frame, and
-- out of combat (a protected re-anchor).
local rosterWatch = CreateFrame("Frame")
rosterWatch:SetScript("OnEvent", function()
    C_Timer.After(0, function()
        GRF.WhenOutOfCombat("placepets", function()
            if Header.PlacePets() and Header.PetsShown() and GRF.Announce then GRF.Announce() end
        end, false)
    end)
end)
API.RegisterEvents(rosterWatch, { "GROUP_ROSTER_UPDATE" })

Header._test = { childUnitChanged = childUnitChanged, rescaler = rescaler, rosterWatch = rosterWatch }
