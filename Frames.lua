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

-- Power colours by the client's power token (plain; Blizzard's defaults).
Frames.POWER = { MANA = { 0.25, 0.55, 1 }, RAGE = { 0.95, 0.2, 0.2 }, ENERGY = { 1, 0.85, 0.15 },
                 FOCUS = { 1, 0.5, 0.25 } }
-- The glass versions of Cell's hover and target borders: a second rim over the
-- tile's own, white on hover, tinted on your target.
Frames.HOVER = { 1, 1, 1, 0.9 }
-- Incoming heals: GlassUnitFrames' colour.
Frames.HEAL = { 0.35, 0.95, 0.55, 0.45 }
Frames.TARGET = { 1, 0.35, 0.5, 1 }
Frames.OFFLINE = { 0.45, 0.45, 0.45 }
Frames.FALLBACK = { 0.35, 0.8, 0.45 }   -- no readable class
Frames.PET = { 0.3, 0.85, 0.4 }         -- pets: one colour, as Blizzard's frames (their creature class misleads)

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
-- The hover tooltip: Blizzard's own unit tooltip (UnitFrame_OnEnter reads
-- self.unit, which Engine.SetUnit keeps, anchors it the default way and keeps
-- it updated), GlassUnitFrames' #80. Never on a forbidden tooltip; both looked
-- up when used, and an error there never reaches the button.
local function tooltipEnter(self)
    local tt, fn = rawget(_G, "GameTooltip"), rawget(_G, "UnitFrame_OnEnter")
    if not (tt and fn and self.unit) or tt:IsForbidden() then return end
    local ok, err = pcall(fn, self)
    if not ok then API.Fail("tooltip", err) end
end
local function tooltipLeave(self)
    local tt, fn = rawget(_G, "GameTooltip"), rawget(_G, "UnitFrame_OnLeave")
    if not (tt and fn) or tt:IsForbidden() then return end
    pcall(fn, self)
end
-- A tile hidden while hovered (the header drops its member, in combat too):
-- the client doesn't promise an OnLeave, so the tooltip state goes here (#78
-- F5), and only a tooltip this tile OWNS is faded: UnitFrame_OnLeave fades
-- whatever is showing, which may be another frame's.
local function tooltipHide(self)
    self.UpdateTooltip = nil
    local tt = rawget(_G, "GameTooltip")
    if not tt or tt:IsForbidden() then return end
    local ok, owned = pcall(tt.IsOwned, tt, self)
    if ok and owned == true then tooltipLeave(self) end
end

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

    -- Incoming heals (GlassUnitFrames' recipe): a translucent bar with the
    -- health bar's FULL width, starting at the health fill's moving edge and
    -- clipped at the bar's end (a bar squeezed into the missing part would
    -- understate heals). The client does all the arithmetic on the secrets.
    local calc = API.NewHealCalculator()
    if calc then
        local clip = CreateFrame("Frame", nil, hp)
        clip:SetAllPoints(hp)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(hp:GetFrameLevel() + 3)
        local pred = CreateFrame("StatusBar", nil, clip)
        pred:SetFrameLevel(clip:GetFrameLevel())
        pred:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
        pred:SetStatusBarColor(Frames.HEAL[1], Frames.HEAL[2], Frames.HEAL[3])
        pred:SetAlpha(Frames.HEAL[4])
        pred:SetMinMaxValues(0, 1)
        pred:SetValue(0)
        pred:GetStatusBarTexture():AddMaskTexture(Glass.Mask(pred, "bar_mask", 8, 0, hp))
        pred:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        b.healCalc, b.healPred = calc, pred
    end

    -- The power bar along the bottom, as Cell's (a thin glass bar; secret
    -- values go straight to it). The health bar gives up that height.
    local pw = Glass.Bar(body, Frames.PowerHeight(b))
    pw:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", inset, inset)
    pw:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -inset, inset)
    pw:SetFrameLevel(Glass.ContentLevel(body))
    b.power = pw

    -- Dead/Offline: small, in the top-right corner (the bottom edge belongs to
    -- the debuff row, the middle to the name). It shares the corner with "My
    -- heals", on a frame above every indicator: a disconnected player keeps
    -- their auras, and "Offline" must not hide under your Renew.
    local over = CreateFrame("Frame", nil, body)
    over:SetAllPoints(body)
    over:SetFrameLevel(body:GetFrameLevel() + 200)   -- over Indicators' stacked bands
    local status = Glass.Font(over, 9, "RIGHT")
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

    -- Hover and target: a second rim, same slices as the glass's own, above it
    -- (its resolved size: thin_small on the clean look).
    local S = Glass.SIZES[g.size] or Glass.SIZES.small
    local function rim(color, sub)
        local t = g.top:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetTexture(Glass.MEDIA .. S.rim)
        t:SetAllPoints(g.top)
        t:SetTextureSliceMargins(S.rimMargin, S.rimMargin, S.rimMargin, S.rimMargin)
        local modes = Enum and Enum.UITextureSliceMode
        t:SetTextureSliceMode((modes and modes.Stretched) or 0)
        t:SetBlendMode("ADD")
        t:SetVertexColor(color[1], color[2], color[3], color[4])
        t:SetAlpha(0)
        return t
    end
    b.targetRim = rim(Frames.TARGET, 6)
    b.hoverRim = rim(Frames.HOVER, 7)
    -- Insecure hooks on the secure button: fine in combat (no protected call).
    b:HookScript("OnEnter", function(self) self.hoverRim:SetAlpha(1); tooltipEnter(self) end)
    b:HookScript("OnLeave", function(self) self.hoverRim:SetAlpha(0); tooltipLeave(self) end)
    -- Hidden while hovered: the rim and the tooltip go too (the secure wrap
    -- clears the hover keys on OnHide for the same reason).
    b:HookScript("OnHide", function(self) self.hoverRim:SetAlpha(0); tooltipHide(self) end)

    if GRF.Indicators then GRF.Indicators.Attach(b) end
    b.relayout = Frames.Layout
    Frames.Layout(b)
end

-- The power bar's height: thin, growing a little with the tile (3 to 6).
function Frames.PowerHeight(b)
    return math.max(3, math.min(6, math.floor(b:GetHeight() * 0.08 + 0.5)))
end

-- The health bar takes the rest, above the power bar and a 1-unit gap.
function Frames.BarHeight(b)
    return b:GetHeight() - 2 * Glass.Inset("small") - Frames.PowerHeight(b) - 1
end

-- The name grows with the tile, taking the room Cell's does (its glyphs span
-- about 30% of the frame's height): 16 at the default 58, 9 to 22. The group
-- layout's is 15 at its 60 (GROUP-LAYOUT.md: Layout.Install sets the ratio).
Frames.NAME_RATIO = 0.28
function Frames.NameSize(h)
    return math.max(9, math.min(22, math.floor(h * Frames.NAME_RATIO + 0.5)))
end

-- The name a tile shows: the first name, as Cell does ("Draku"). Forever's
-- characters have surnames, and a surname only gets a centred name cut to
-- "Morph...". A secret name (grouped, ForeverUI's note) can't be split in Lua:
-- it goes to the client whole.
function Frames.ShortName(full)
    if API.IsSecret(full) or type(full) ~= "string" then return full end
    return full:match("^(%S+)") or full
end

-- The name display (#18): "first" (the default, above), "initial" (first
-- name + surname initial: "Karuzo M.") or "full" (cut short by the tile).
-- A nickname, keyed by GUID, wins over every style, a secret name included.
-- A secret name can't be split: every style shows it whole.
Frames.NAME_STYLES = { first = true, initial = true, full = true }

-- The first character, whole when it takes several bytes (UTF-8: localized
-- clients' surnames).
local function firstChar(s) return s:match("^[%z\1-\127\194-\244][\128-\191]*") end

function Frames.DisplayName(full, style, nick)
    if nick then return nick end
    if style ~= "initial" and style ~= "full" then return Frames.ShortName(full) end
    if API.IsSecret(full) or type(full) ~= "string" or style == "full" then return full end
    local first, rest = full:match("^(%S+)%s+(%S.*)$")
    local c = rest and firstChar(rest)
    if not c then return Frames.ShortName(full) end
    return first .. " " .. c .. "."
end

-- The client's surname separator when it exposes it (a compiled-in constant,
-- not in the dump or FrameXML), else the space the measured names show.
local function separator()
    local C = rawget(_G, "Constants")
    local t = type(C) == "table" and rawget(C, "CharacterNameSeparatorConsts")
    local sep = type(t) == "table" and rawget(t, "CHARACTERNAME_SURNAME_SEPARATOR")
    return type(sep) == "string" and sep or " "
end

-- The unit's full name, what GetUnitName(u, false) gives, built here from
-- UnitName's two returns (the first name, then the surname where a realm
-- would be). Blizzard's own GetUnitName is Lua on Forever
-- (NameUtil.FormatUnitNameForDisplay) and truth-tests and concatenates those
-- returns, so a SECRET surname threw inside our painter and the tile kept
-- the previous person's name (#78 F1). Either part secret: the first return,
-- unchanged (the client renders a secret; Lua can neither join nor split
-- it). nil when the read fails, so SetText(nil) clears a stale name.
function Frames.FullName(u)
    local ok, first, surname = pcall(UnitName, u)
    if not ok then return nil end
    if API.IsSecret(first) or API.IsSecret(surname) then return first end
    if type(first) ~= "string" then return nil end
    if type(surname) == "string" and surname ~= "" then return first .. separator() .. surname end
    return first
end

-- What a tile shows for unit `u`, whose plain GUID is `guid` (nil: unknown,
-- so no nickname).
function Frames.NameFor(u, guid)
    local db = GRF.db
    local nicks = db and db.nicknames
    local nick = type(guid) == "string" and nicks and nicks[guid]
    return Frames.DisplayName(Frames.FullName(u), db and db.nameStyle, nick and nick.nick)
end

-- After a resize (Header.ApplySize): the bar follows the tile's height, the
-- name its size. Glass.Font registered the fonts; the same file is re-set at
-- the new size (the material is LibGlass's: not changed here).
function Frames.Layout(b)
    local h = b:GetHeight()
    if type(h) ~= "number" or h <= 0 then return end
    b.health:SetHeight(Frames.BarHeight(b))
    b.power:SetHeight(Frames.PowerHeight(b))
    if b.healPred then
        b.healPred:SetSize(b:GetWidth() - 2 * Glass.Inset("small"), Frames.BarHeight(b))
    end
    local f = Glass.FONTS[Glass.fontKey] or Glass.FONTS.arial
    b.nameText:SetFont(f.file, Frames.NameSize(h) + f.bump, "")
end

--------------------------------------------------------------------------------
-- Painters (unit = the child's current unit; see Engine.SetUnit)
--------------------------------------------------------------------------------

Engine.SetPainter("name", function(b, u)
    if not UnitExists(u) then return end
    -- The full name from UnitName's two returns (Frames.FullName), shown in
    -- the chosen style, or the person's nickname (#18).
    b.nameText:SetText(Frames.NameFor(u, b.guid))
end)

local function classColor(u)
    if plain(UnitIsPlayer, u) == false then return Frames.PET[1], Frames.PET[2], Frames.PET[3] end
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

Engine.SetPainter("heal", function(b, u)
    local pred = b.healPred
    if not (pred and UnitExists(u)) then return end
    if plain(UnitIsConnected, u) == false or plain(UnitIsDeadOrGhost, u) == true then
        pred:SetMinMaxValues(0, 1)
        pred:SetValue(0)
        return
    end
    local incoming, maxHealth = API.IncomingHeals(u, b.healCalc)
    Glass.SetBar(pred, maxHealth, incoming, true)
end)

Engine.SetPainter("power", function(b, u)
    if not UnitExists(u) then return end
    local pw = b.power
    if plain(UnitIsConnected, u) == false or plain(UnitIsDeadOrGhost, u) == true then
        Glass.SetBar(pw, 1, 0, true)
        return
    end
    local ok, _, token = pcall(UnitPowerType, u)
    local c = Frames.POWER[(ok and not API.IsSecret(token)) and token or "MANA"] or Frames.POWER.MANA
    pw:SetStatusBarColor(c[1], c[2], c[3])
    -- Secret values go straight back to the client.
    Glass.SetBar(pw, UnitPowerMax(u), UnitPower(u), b.snap)
end)

-- Your target's tile gets the tinted rim. "Is this my target" can come back
-- secret (ForeverUI's note on grouped units): the client picks the alpha.
Engine.SetPainter("target", function(b, u)
    local rim = b.targetRim
    local ok, isTarget = pcall(UnitIsUnit, u, "target")
    if not ok then rim:SetAlpha(0) return end
    if API.IsSecret(isTarget) then
        rim:SetAlphaFromBoolean(isTarget, 1, 0)
    else
        rim:SetAlpha(isTarget and 1 or 0)
    end
end)

-- UnitInRange is secret even out of combat (measured): hand it to the
-- client. Your own units read "unchecked" (false): you and your own pet never
-- fade (EllesmereUI does the same for your pet; measured here: your pet's tile
-- faded while it stood next to you). Nor does an offline unit (its grey bar
-- already says so).
Engine.SetPainter("range", function(b, u)
    local body = b.body
    if plain(UnitIsUnit, u, "player") == true or plain(UnitIsUnit, u, "pet") == true
        or plain(UnitIsConnected, u) == false
        or not body.SetAlphaFromBoolean then
        body:SetAlpha(1)
        return
    end
    body:SetAlphaFromBoolean(UnitInRange(u), 1, Frames.OUT_OF_RANGE_ALPHA)
end)
