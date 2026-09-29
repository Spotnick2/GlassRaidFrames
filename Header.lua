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
Header.TILE_W, Header.TILE_H = 76, 38   -- must match GlassRaidFrames.xml
Header.GAP = 4
Header.TEMPLATE = "GlassRaidFramesUnitTemplate"

Header.headers = {}
Header.children = {}

-- Default positions per role (#7): the healer's grid in the lower middle,
-- between GlassUnitFrames' player and target frames; the others on the left
-- side, so the Cooldown Manager keeps the centre. UIParent is 768 units tall
-- at the default scale; the grid stays above y = -250, clear of the action
-- bars. The side's x comes from UIParent's actual width (screen aspect).
Header.HEALER_POS = { x = 0, y = -120 }
Header.SIDE_Y = 60
Header.SIDE_MARGIN = 30

function Header.Size()
    local w = Header.GROUPS * Header.TILE_W + (Header.GROUPS - 1) * Header.GAP
    local h = Header.PER_GROUP * Header.TILE_H + (Header.PER_GROUP - 1) * Header.GAP
    return w, h
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
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", (group - 1) * (Header.TILE_W + Header.GAP), 0)
    -- Precreate every child (a header only makes children while shown).
    h:SetAttribute("startingIndex", 1 - Header.PER_GROUP)
    h:Show()
    h:SetAttribute("startingIndex", 1)
    return h
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
        local i = 1
        while h do
            local child = h:GetAttribute("child" .. i)
            if not child then break end
            table.insert(Header.children, child)
            local ok, err = pcall(setup, child)
            if not ok then API.Fail("setup", err) end
            child:HookScript("OnAttributeChanged", childUnitChanged)
            Engine.Register(child)
            -- The header may have assigned a unit before our hook existed.
            childUnitChanged(child, "unit", child:GetAttribute("unit"))
            i = i + 1
        end
    end
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

Header._test = { childUnitChanged = childUnitChanged, rescaler = rescaler }
