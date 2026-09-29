-- Frames.lua: one glass tile per header child, and its painters.
--
-- The secure button (the header's child) is never styled or faded itself:
-- every visual lives on `body`, an insecure child frame covering it, so
-- painting and range fading never touch a protected frame in combat.
--
-- What the probe measured (docs/FOREVER-PROBE.md, item 5) decides how each
-- value is used:
-- - health and the partner's max health are SECRET: straight to the bar;
-- - dead, connected, name, class, leader, role and roster are plain, even in
--   combat, but still read through plain() so a secret reads as "unknown";
-- - UnitInRange is secret even out of combat: straight to SetAlphaFromBoolean;
-- - the raid mark index may be secret: SetSpriteSheetCell picks the cell.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Glass, Engine = GRF.API, GRF.Glass, GRF.Engine
local Frames = {}
GRF.Frames = Frames

Frames.OUT_OF_RANGE_ALPHA = 0.4
Frames.OFFLINE = { 0.45, 0.45, 0.45 }
Frames.FALLBACK = { 0.35, 0.8, 0.45 }   -- no readable class

-- Roles come back on Forever, but everyone is DAMAGER unless assigned
-- (measured): only tanks and healers get an icon, so it means something.
Frames.ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer" }

-- fn(...) if it returns a plain value, else nil (secret or a throw = unknown).
local function plain(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end
Frames.plain = plain

local function icon(parent, size, sub)
    local t = parent:CreateTexture(nil, "OVERLAY", nil, sub or 7)
    t:SetSize(size, size)
    t:Hide()
    return t
end

-- Dress one header child, out of combat. `b` is the secure button.
function Frames.Setup(b)
    b:RegisterForClicks(API.UnitButtonClicks())
    -- Wildcards: the secure template never falls back from "shift-type1" to
    -- "type1" (probe item 2), so an unbound modified click still targets.
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "togglemenu")

    local body = CreateFrame("Frame", nil, b)
    body:SetAllPoints(b)
    b.body = body

    local g = Glass.Apply(body, "small")
    b.glass = g
    local inset = Glass.Inset("small")

    local hp = Glass.Bar(body, Frames.BarHeight(b))
    hp:SetPoint("TOPLEFT", body, "TOPLEFT", inset, -inset)
    hp:SetPoint("TOPRIGHT", body, "TOPRIGHT", -inset, -inset)
    hp:SetFrameLevel(Glass.ContentLevel(body))
    b.health = hp

    -- Dead/Offline: small, in the top-right corner (the bottom edge belongs to
    -- the debuff row, the middle to the name).
    local status = Glass.Font(g.top, 9, "RIGHT")
    status:SetPoint("TOPRIGHT", body, "TOPRIGHT", -inset - 3, -inset - 3)
    b.statusText = status

    -- The name, centred in the tile both ways, as Cell draws it (owner's
    -- side-by-side screenshots).
    local name = Glass.Font(g.top, 10, "CENTER")
    name:SetPoint("LEFT", body, "LEFT", inset + 3, 0)
    name:SetPoint("RIGHT", body, "RIGHT", -inset - 3, 0)
    b.nameText = name

    local ind = {}
    ind.leader = icon(g.top, 10)
    ind.leader:SetPoint("CENTER", body, "TOPLEFT", 8, 0)
    ind.mark = icon(g.top, 12)
    ind.mark:SetPoint("CENTER", body, "TOP", 0, 0)
    ind.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    ind.role = icon(g.top, 10)
    ind.role:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -inset - 1, inset + 1)
    b.indicators = ind

    if GRF.Auras then GRF.Auras.Attach(b) end
    b.relayout = Frames.Layout
    Frames.Layout(b)
end

function Frames.BarHeight(b)
    return b:GetHeight() - 2 * Glass.Inset("small")
end

-- The name grows with the tile, taking the room Cell's does (its glyphs span
-- about 30% of the frame's height): 16 at the default 58, 9 to 22.
function Frames.NameSize(h)
    return math.max(9, math.min(22, math.floor(h * 0.28 + 0.5)))
end

-- The name a tile shows: the first name, as Cell does ("Draku"). Forever's
-- characters have surnames, and a surname only gets a centred name cut to
-- "Morph...". A secret name (grouped, ForeverUI's note) can't be split in Lua:
-- it goes to the client whole.
function Frames.ShortName(full)
    if API.IsSecret(full) or type(full) ~= "string" then return full end
    return full:match("^(%S+)") or full
end

-- After a resize (Header.ApplySize): the bar follows the tile's height, the
-- name its size. Glass.Font registered the fonts; the same file is re-set at
-- the new size (Glass.lua is the pinned GlassUnitFrames copy: not changed).
function Frames.Layout(b)
    local h = b:GetHeight()
    if type(h) ~= "number" or h <= 0 then return end
    b.health:SetHeight(Frames.BarHeight(b))
    local f = Glass.FONTS[Glass.fontKey] or Glass.FONTS.arial
    b.nameText:SetFont(f.file, Frames.NameSize(h) + f.bump, "")
end

--------------------------------------------------------------------------------
-- Painters (unit = the child's current unit; see Engine.SetUnit)
--------------------------------------------------------------------------------

Engine.SetPainter("name", function(b, u)
    if not UnitExists(u) then return end
    -- GetUnitName(u, false) (UnitName's second return is the surname on
    -- Forever), then the first name for the tile.
    b.nameText:SetText(Frames.ShortName(GetUnitName(u, false)))
end)

local function classColor(u)
    local _, class = UnitClass(u)
    local r, g, bl = API.ClassColor(class)
    if r then return r, g, bl end
    return Frames.FALLBACK[1], Frames.FALLBACK[2], Frames.FALLBACK[3]
end

Engine.SetPainter("health", function(b, u)
    if not UnitExists(u) then return end
    local hp = b.health
    if plain(UnitIsConnected, u) == false then
        Glass.SetBar(hp, 1, 1, true)
        hp:SetStatusBarColor(Frames.OFFLINE[1], Frames.OFFLINE[2], Frames.OFFLINE[3])
        b.statusText:SetText("Offline")
        return
    end
    hp:SetStatusBarColor(classColor(u))
    if plain(UnitIsDeadOrGhost, u) == true then
        Glass.SetBar(hp, 1, 0, true)
        b.statusText:SetText("Dead")
        return
    end
    b.statusText:SetText("")
    -- Secret values go straight back to the client.
    Glass.SetBar(hp, UnitHealthMax(u), UnitHealth(u), b.snap)
end)

Engine.SetPainter("indicators", function(b, u)
    local ind = b.indicators
    if not UnitExists(u) then return end
    if plain(UnitIsGroupLeader, u) == true then
        ind.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        ind.leader:Show()
    elseif plain(UnitIsGroupAssistant, u) == true then
        ind.leader:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
        ind.leader:Show()
    else
        ind.leader:Hide()
    end

    -- The mark index may be secret (GlassUnitFrames measured it on a marked
    -- target): the client picks the 4x4 sprite cell from it. Plain nil = none.
    local okIdx, idx = pcall(GetRaidTargetIndex, u)
    if okIdx and (API.IsSecret(idx) or type(idx) == "number") then
        ind.mark:SetShown(pcall(ind.mark.SetSpriteSheetCell, ind.mark, idx, 4, 4))
    else
        ind.mark:Hide()
    end

    local atlas = Frames.ROLE_ATLAS[plain(UnitGroupRolesAssigned, u)]
    if atlas and API.AtlasExists(atlas) then
        ind.role:SetAtlas(atlas)
        ind.role:Show()
    else
        ind.role:Hide()
    end
end)

-- UnitInRange is secret even out of combat (measured): hand it to the
-- client. Your own unit reads "unchecked" (false), so it never fades, and
-- neither does an offline one (its grey bar already says so).
Engine.SetPainter("range", function(b, u)
    local body = b.body
    if plain(UnitIsUnit, u, "player") == true or plain(UnitIsConnected, u) == false
        or not body.SetAlphaFromBoolean then
        body:SetAlpha(1)
        return
    end
    body:SetAlphaFromBoolean(UnitInRange(u), 1, Frames.OUT_OF_RANGE_ALPHA)
end)
