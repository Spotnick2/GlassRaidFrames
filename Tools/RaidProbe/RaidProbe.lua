-- RaidProbe: the throwaway measurement addon for GlassRaidFrames, milestone 0.
-- It answers the questions the plan leaves open before any real frame code
-- is written. A ForeverProbe module (#44, ForeverProbe docs/GUIDE.md): its
-- commands are /fp raid <command>, its lines go to the /fp console (never
-- chat) and to RaidProbeDB.log (SavedVariables), so a /reload leaves the whole
-- session on disk for review.
--
-- What it measures (the numbers match the plan's probe items):
--   1. manual party1-4/raid1-40 buttons vs SecureGroupHeaderTemplate, through
--      roster changes in and out of combat          /fp raid build, /fp raid header
--   2. click-cast attribute forms on SecureUnitButtonTemplate  (click the tiles)
--   3. the dispel box: a secure button over an AuraContainer   (the corner box)
--   4. C_UnitAuras.AddAuraSound                               /fp raid aurasound
--   5. secrecy of group-unit values, range                    /fp raid secrets
--   6. hiding Blizzard's compact frames                       /fp raid hide
--   7. the cost of 45 tiles x 2 containers                    /fp raid fps
--   later, #19: buff/debuff indicators                        /fp raid ind ...
--   later, #61: the hover-key member gate on a target frame   /fp steps raid ufgate
--   later, #63: a spell's reaction, always-bound keys on the world  /fp steps raid worldkey
--
-- Every client call that may be missing or throw goes through try(), so one
-- refusal cannot stop the rest of the probe.

local ADDON, NS = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local SOUND = MEDIA .. "dispel.ogg"
local MAX_LOG = 3000

local P = {}                 -- probe state
local tiles = {}             -- unit -> tile (manual build)
local order = {}             -- tiles in build order
local applyMode              -- defined with the events, used by build()

--------------------------------------------------------------------------------
-- Log: the host's helpers (the console stamps time, combat and run). show
-- keeps strings unquoted, as the probe always printed them; try returns
-- pcall's full tuple and logs "label: ERROR msg", or "label: MISSING" for a
-- function the client lacks.
--------------------------------------------------------------------------------

local Probe = ForeverProbe:Module("RaidProbe", { api = 1, cmd = "raid" })

local function say(msg) Probe:Say(tostring(msg)) end
local function show(v) return Probe.Show(v, true) end
local function try(label, fn, ...) return Probe:Try(label, fn, ...) end

--------------------------------------------------------------------------------
-- Class data: a helpful test spell, and the cures (Vanilla spell IDs;
-- Decursive DCR_init.lua lists the same). Ranks in ascending order.
--------------------------------------------------------------------------------

local TEST_SPELL = {
    PRIEST = 2050, PALADIN = 635, DRUID = 774, SHAMAN = 331,
    MAGE = 1459, WARLOCK = 5697, HUNTER = 1130, ROGUE = 1784, WARRIOR = 6673,
}

-- Dispel type -> the index Blizzard's colour curve uses (Decursive DTtoBT).
local TYPE_INDEX = { Magic = 1, Curse = 2, Disease = 3, Poison = 4 }
local TYPE_NAMES = { "Magic", "Curse", "Disease", "Poison" }

-- Per class, the cure slots in priority order. Each slot lists spells best
-- first; the first known one is used. Types are what that slot cures.
local CURES = {
    PRIEST  = { { spells = { 988, 527 }, types = { "Magic" } },
                { spells = { 552, 528 }, types = { "Disease" } } },
    PALADIN = { { spells = { 4987 }, types = { "Magic", "Poison", "Disease" } },
                { spells = { 1152 }, types = { "Poison", "Disease" } } },
    DRUID   = { { spells = { 2782 }, types = { "Curse" } },
                { spells = { 2893, 8946 }, types = { "Poison" } } },
    SHAMAN  = { { spells = { 526 }, types = { "Poison" } },
                { spells = { 2870 }, types = { "Disease" } } },
    MAGE    = { { spells = { 475 }, types = { "Curse" } } },
}

-- Slot colours = which mouse button cures it (1 left, 2 right, 3 middle).
local SLOT_COLORS = { { 1, 0.2, 0.2 }, { 0.25, 0.55, 1 }, { 1, 0.9, 0.2 } }

local function spellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" then return name end
    return nil
end

local function known(id)
    local ok, k = pcall(C_SpellBook.IsSpellKnown, id)
    return ok and k == true
end

-- The cure slots for the player's class, deduplicated by spell: a paladin with
-- Cleanse gets one slot for all three types, Purify is dropped.
local function cureSlots()
    local _, class = UnitClass("player")
    local slots, used, covered = {}, {}, {}
    for _, spec in ipairs(CURES[class] or {}) do
        for _, id in ipairs(spec.spells) do
            if known(id) and not used[id] then
                local types = {}
                for _, t in ipairs(spec.types) do
                    if not covered[t] then types[#types + 1] = t; covered[t] = true end
                end
                if #types > 0 then
                    slots[#slots + 1] = { spell = id, name = spellName(id), types = types }
                    used[id] = true
                end
                break
            end
        end
    end
    if #slots == 0 then
        -- No cure (or a class without one): one slot for every type, no spell,
        -- so the box still lights for testing on any character.
        slots[1] = { types = { "Magic", "Curse", "Disease", "Poison" } }
    end
    return slots
end

--------------------------------------------------------------------------------
-- Click-cast attribute variants (probe item 2)
--------------------------------------------------------------------------------

local function testSpell()
    local _, class = UnitClass("player")
    return P.spell or TEST_SPELL[class]
end

-- Every form of the `spell` attribute we might use, on its own modifier.
-- unit = nil for a header child: the header owns its "unit" attribute.
local function applyBindings(b, unit)
    local id = testSpell()
    local name = id and spellName(id)
    if unit then b:SetAttribute("unit", unit) end
    b:SetAttribute("type1", "target")
    b:SetAttribute("type2", "togglemenu")
    if not name then return end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
    local ranked = (ok and type(sub) == "string" and sub ~= "") and (name .. "(" .. sub .. ")") or name
    b:SetAttribute("shift-type1", "spell"); b:SetAttribute("shift-spell1", name)       -- bare name
    b:SetAttribute("ctrl-type1", "spell");  b:SetAttribute("ctrl-spell1", id)          -- numeric ID
    b:SetAttribute("alt-type1", "spell");   b:SetAttribute("alt-spell1", ranked)       -- rank-qualified
    b:SetAttribute("shift-type2", "macro")                                              -- macro fallback
    -- @mouseover: a header child's unit changes, so none can be baked in.
    b:SetAttribute("shift-macrotext2", "/cast [@mouseover,help,nodead] " .. name)
    b:SetAttribute("*type3", "spell");      b:SetAttribute("*spell3", name)            -- wildcard
    -- Alt is the client's self-cast modifier: does a @mouseover macro escape it?
    b:SetAttribute("alt-type2", "macro")
    b:SetAttribute("alt-macrotext2", "/cast [@mouseover,help,nodead] " .. name)
end

local BINDING_HELP = {
    "left: target | right: menu",
    "shift-left: spell by name | ctrl-left: spell by ID | alt-left: spell 'Name(Rank n)'",
    "shift-right: /cast [@mouseover] macro | middle (any modifier): *spell3 wildcard | alt-right: @mouseover macro",
    "corner box: left/right/middle = cure slot 1/2/3",
}

-- What the secure handler resolved for this click, read back insecurely.
local function postClick(self, mouse)
    local get = SecureButton_GetModifiedAttribute
    local kind = get and get(self, "type", mouse)
    local what = kind == "spell" and get(self, "spell", mouse)
        or kind == "macro" and get(self, "macrotext", mouse) or ""
    local unit = self:GetAttribute("unit")
    if unit == nil and self:GetAttribute("useparent-unit") then unit = "box of " .. tostring(self:GetParent():GetAttribute("unit")) end
    say(string.format("click %s %s%s%s%s -> %s %s", show(unit),
        IsShiftKeyDown() and "shift-" or "", IsControlKeyDown() and "ctrl-" or "",
        IsAltKeyDown() and "alt-" or "", tostring(mouse), show(kind), show(what)))
end

--------------------------------------------------------------------------------
-- Aura containers (probe items 3 and 7)
--------------------------------------------------------------------------------

local function newContainer(parent)
    if not P.auraLoaded then
        local ok, loaded = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        P.auraLoaded = true
        say("Blizzard_AuraContainer load: " .. show(ok) .. " " .. show(loaded))
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not c then
        say("|cffff6060FAIL|r AuraContainer: " .. tostring(c))
        return nil
    end
    return c
end

-- One step colour curve for the box: each dispel type -> its slot's colour,
-- every other type transparent (a step curve carries the last point forward,
-- so each index gets an explicit point).
local function slotCurve(slots)
    local curve = C_CurveUtil.CreateColorCurve()
    if Enum.LuaCurveType and Enum.LuaCurveType.Step then curve:SetType(Enum.LuaCurveType.Step) end
    local colorOf = {}
    for i, slot in ipairs(slots) do
        local c = SLOT_COLORS[i] or SLOT_COLORS[1]
        for _, t in ipairs(slot.types) do colorOf[TYPE_INDEX[t]] = CreateColor(c[1], c[2], c[3], 1) end
    end
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))
    for i = 1, 4 do curve:AddPoint(i, colorOf[i] or CreateColor(0, 0, 0, 0)) end
    curve:AddPoint(5, CreateColor(0, 0, 0, 0))
    return curve
end

local function textureStyle()
    local s = Enum.CustomAuraButtonDispelTypeTextureStyle
    return s and s.PreserveAsset
end

-- The dispel box: our secure button, and behind its hit area an AuraContainer
-- with one slot per cure. Its generated buttons are configured entirely in
-- initializeFrame (they become inaccessible while auras are secret) and never
-- take the mouse, as Decursive does (Dcr_DebuffsFrame.lua:1168).
local function buildBox(tile, unit, slots, curve)
    local box = CreateFrame("Button", nil, tile, "SecureUnitButtonTemplate")
    box:SetSize(14, 14)
    box:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -2, -2)
    box:SetFrameLevel(tile:GetFrameLevel() + 10)
    box:RegisterForClicks("AnyUp")
    if unit then
        box:SetAttribute("unit", unit)
    else
        -- A header child's unit changes in combat, when the box's own "unit"
        -- could not be set: take the parent's (SecureButton_GetUnit).
        box:SetAttribute("useparent-unit", true)
    end
    for i, slot in ipairs(slots) do
        if slot.name then
            box:SetAttribute("type" .. i, "spell")
            box:SetAttribute("spell" .. i, slot.name)
        end
    end
    box:SetScript("PostClick", postClick)
    local frame = box:CreateTexture(nil, "BACKGROUND")
    frame:SetAllPoints(box)
    frame:SetColorTexture(1, 1, 1, 0.12)
    tile.box = box

    local c = newContainer(box)
    if not c then return end
    c:SetAllPoints(box)
    for prio = #slots, 1, -1 do
        local include = {}
        for _, t in ipairs(slots[prio].types) do include[t] = true end
        try("AddAuraSlot " .. prio, c.AddAuraSlot, c, "RP_CURE_" .. prio, "HARMFUL", {
            sortMethod = 0, sortDirection = 0,
            candidateFilters = { includeDispelTypes = include },
            initializeFrame = function(ab)
                ab:EnableMouse(false)
                ab:ClearAllPoints()
                ab:SetPoint("CENTER", box, "CENTER", 0, 0)
                ab:SetSize(12, 12)
                ab:SetFrameLevel(box:GetFrameLevel() + 4 - prio)
                local sq = ab:CreateTexture(nil, "OVERLAY")
                sq:SetAllPoints(ab)
                sq:SetColorTexture(1, 1, 1, 1)
                ab:ClearDispelTypeTextures()
                ab:AddDispelTypeTexture(sq, {
                    showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = false,
                    style = textureStyle(), customDispelColorCurve = curve,
                })
                P.boxInits = (P.boxInits or 0) + 1
            end,
        })
    end
    try("box SetUnit", c.SetUnit, c, unit or tile:GetAttribute("unit") or "player")
    if c.SetEnabled then try("box SetEnabled", c.SetEnabled, c, true) end
    try("box UpdateAllAuras", c.UpdateAllAuras, c)
    tile.boxContainer = c
end

-- A row of up to three debuff icons along the tile's bottom, click-through.
local function buildDebuffRow(tile, unit)
    local c = newContainer(tile)
    if not c then return end
    c:SetSize(3 * 14 + 4, 14)
    c:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 2, 2)
    c:SetFrameLevel(tile:GetFrameLevel() + 5)
    local ok = try("AddAuraGroup debuffs", c.AddAuraGroup, c, "RP_DEBUFFS", "HARMFUL", {
        maxFrameCount = 3,
        candidateFilters = {},
        layout = { elementWidth = 14, elementHeight = 14, elementSpacing = 2, lineSpacing = 2 },
        initializeFrame = function(ab)
            ab:EnableMouse(false)
            ab:SetSize(14, 14)
            local icon = ab:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(ab)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            ab:SetIcon(icon)
            P.rowInits = (P.rowInits or 0) + 1
        end,
    })
    if ok then
        try("row SetUnit", c.SetUnit, c, unit)
        try("row UpdateAllAuras", c.UpdateAllAuras, c)
        tile.rowContainer = c
    end
end

--------------------------------------------------------------------------------
-- Manual build (probe items 1, 2, 3, 7)
--------------------------------------------------------------------------------

local TILE_W, TILE_H, GAP = 72, 36, 3

local function slotPoint(i, isRaid)
    if not isRaid then return 0, -(i - 1) * (TILE_H + GAP) end
    local col, row = math.floor((i - 1) / 5), (i - 1) % 5
    return col * (TILE_W + GAP), -row * (TILE_H + GAP)
end

local function paint(tile)
    local u = tile.unit
    if not UnitExists(u) then return end
    try("paint name " .. u, function() tile.name:SetText(GetUnitName(u, false)) end)
    try("paint health " .. u, function()
        tile.hp:SetMinMaxValues(0, UnitHealthMax(u))
        tile.hp:SetValue(UnitHealth(u))
    end)
    local _, class = UnitClass(u)
    if class and not (issecretvalue and issecretvalue(class)) and C_ClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then tile.hp:SetStatusBarColor(c.r, c.g, c.b) end
    end
end

local function buildTile(root, unit, i, isRaid, slots, curve)
    local G = GlassRaidFrames and GlassRaidFrames.Glass
    local b = CreateFrame("Button", "RaidProbe_" .. unit, root, "SecureUnitButtonTemplate")
    b:SetSize(TILE_W, TILE_H)
    local x, y = slotPoint(i, isRaid)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
    b:RegisterForClicks("AnyUp")
    applyBindings(b, unit)
    b:SetScript("PostClick", postClick)
    b.unit = unit

    if G then
        G.Apply(b, "small")
        b.hp = G.Bar(b, TILE_H - 6)
        b.hp:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        b.hp:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)
        b.name = G.Font(b.hp, 10, "LEFT")
    else
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0, 0, 0, 0.5)
        b.hp = CreateFrame("StatusBar", nil, b)
        b.hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b.hp:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
        b.hp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        b.name = b.hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
    b.name:SetPoint("RIGHT", b, "RIGHT", -18, 0)

    local tag = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tag:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    tag:SetText(unit)

    buildBox(b, unit, slots, curve)
    buildDebuffRow(b, unit)
    RegisterUnitWatch(b)
    tiles[unit] = b
    order[#order + 1] = b
    return b
end

local function build()
    if P.built then say("already built") return end
    if InCombatLockdown() then say("out of combat only") return end
    local slots = cureSlots()
    local curve = slotCurve(slots)
    for i, s in ipairs(slots) do
        say(string.format("cure slot %d (%s click): %s -> %s", i, ({ "left", "right", "middle" })[i],
            show(s.name or "none"), table.concat(s.types, "/")))
    end
    local t0 = debugprofilestop()
    P.party = CreateFrame("Frame", "RaidProbeParty", UIParent)
    P.party:SetSize(TILE_W, 5 * (TILE_H + GAP))
    P.party:SetPoint("CENTER", UIParent, "CENTER", 0, 100)   -- clear of the action bars
    P.raid = CreateFrame("Frame", "RaidProbeRaid", UIParent)
    P.raid:SetSize(8 * (TILE_W + GAP), 5 * (TILE_H + GAP))
    P.raid:SetPoint("CENTER", UIParent, "CENTER", 0, 100)    -- only one set shows at a time
    buildTile(P.party, "player", 1, false, slots, curve)
    for i = 1, 4 do buildTile(P.party, "party" .. i, i + 1, false, slots, curve) end
    for i = 1, 40 do buildTile(P.raid, "raid" .. i, i, true, slots, curve) end
    local ms = debugprofilestop() - t0
    P.built = true
    say(string.format("built %d tiles in %.1f ms (glass: %s)", #order, ms,
        show(GlassRaidFrames ~= nil and GlassRaidFrames.Glass ~= nil)))
    for _, line in ipairs(BINDING_HELP) do say(line) end
    for _, t in ipairs(order) do paint(t) end
    applyMode()
end

-- The client's self-cast settings: alt-left cast on the player in combat
-- even with a unit attribute (2026-09-28). "none" unbinds the modifier (a
-- global setting of the player's, so "alt" puts it back).
local function selfCast(arg)
    local okM, mod = pcall(GetModifiedClick, "SELFCAST")
    local okC, auto = pcall(C_CVar.GetCVar, "autoSelfCast")
    say("SELFCAST modifier=" .. (okM and show(mod) or "ERR") .. " autoSelfCast=" .. (okC and show(auto) or "ERR"))
    if arg == "none" or arg == "alt" then
        if InCombatLockdown() then say("out of combat only") return end
        local ok, err = pcall(SetModifiedClick, "SELFCAST", arg == "none" and "NONE" or "ALT")
        if ok then pcall(SaveBindings, GetCurrentBindingSet()) end
        say("SetModifiedClick SELFCAST " .. arg .. ": " .. (ok and "ok" or tostring(err)))
        selfCast()
    end
end

--------------------------------------------------------------------------------
-- SecureGroupHeaderTemplate (probe item 1)
--------------------------------------------------------------------------------

function RaidProbe_HeaderChildAttribute(self, name, value)
    if name ~= "unit" then return end
    if self.label then
        if value and UnitExists(value) then
            pcall(self.label.SetText, self.label, GetUnitName(value, false))
        else
            self.label:SetText(tostring(value))
        end
    end
    -- Only log real changes: every roster update rewrites all 40 children.
    if value == self.rpUnit then return end
    self.rpUnit = value
    say("header child unit -> " .. show(value))
    -- A header moves tokens between its children, in combat too, so a child's
    -- aura container must follow: does SetUnit work on a secure child in combat?
    if self.boxContainer and value then
        local ok, err = pcall(self.boxContainer.SetUnit, self.boxContainer, value)
        pcall(self.boxContainer.UpdateAllAuras, self.boxContainer)
        if not ok then say("  box container SetUnit " .. show(value) .. ": " .. tostring(err)) end
    end
    if self.rowContainer and value then
        local ok, err = pcall(self.rowContainer.SetUnit, self.rowContainer, value)
        local okU, errU = pcall(self.rowContainer.UpdateAllAuras, self.rowContainer)
        say("  container SetUnit " .. show(value) .. ": " .. (ok and "ok" or tostring(err))
            .. ", UpdateAllAuras: " .. (okU and "ok" or tostring(errU)))
    end
end

local function headerReport()
    local h = P.header
    if not h then say("no header: /fp raid header") return end
    local n, shown = 0, 0
    local i = 1
    while true do
        local child = h:GetAttribute("child" .. i)
        if not child then break end
        n = n + 1
        if child:IsShown() or child:GetAttribute("unit") then
            if child:IsShown() then shown = shown + 1 end
            say(string.format("  child%d unit=%s shown=%s", i, show(child:GetAttribute("unit")), show(child:IsShown())))
        end
        i = i + 1
    end
    say(string.format("header: %d children, %d shown, header shown=%s", n, shown, show(h:IsShown())))
end

local function header()
    if P.header then headerReport() return end
    if InCombatLockdown() then say("out of combat only") return end
    local ok, h = pcall(CreateFrame, "Frame", "RaidProbeHeader", UIParent, "SecureGroupHeaderTemplate")
    if not ok then say("|cffff6060FAIL|r header: " .. tostring(h)) return end
    h:SetAttribute("template", "RaidProbeHeaderUnitTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("showSolo", true)
    h:SetAttribute("showParty", true)
    h:SetAttribute("showRaid", true)
    h:SetAttribute("point", "TOP")
    h:SetAttribute("yOffset", -2)
    h:SetAttribute("groupBy", "GROUP")
    h:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("maxColumns", 8)
    h:SetAttribute("unitsPerColumn", 5)
    h:SetAttribute("columnSpacing", 4)
    h:SetAttribute("columnAnchorPoint", "LEFT")
    h:SetPoint("TOPLEFT", UIParent, "CENTER", -300, 200)
    P.header = h
    -- Precreate all 40 children out of combat (Cell's trick): a child the
    -- header would otherwise create mid-combat could not be configured.
    h:SetAttribute("startingIndex", -39)
    local shown = try("header Show", h.Show, h)
    h:SetAttribute("startingIndex", 1)
    P.slots = P.slots or cureSlots()
    P.curve = P.curve or slotCurve(P.slots)
    for i, sl in ipairs(P.slots) do
        say(string.format("cure slot %d (%s click): %s -> %s", i, ({ "left", "right", "middle" })[i],
            show(sl.name or "none"), table.concat(sl.types, "/")))
    end
    local n = 0
    while h:GetAttribute("child" .. (n + 1)) do
        n = n + 1
        local child = h:GetAttribute("child" .. n)
        child:HookScript("PostClick", postClick)
        applyBindings(child, nil)
        P.headerChildren = P.headerChildren or {}
        P.headerChildren[#P.headerChildren + 1] = child
        buildDebuffRow(child, child:GetAttribute("unit") or "player")
        buildBox(child, nil, P.slots, P.curve)
    end
    say("header created (shown call ok=" .. show(shown) .. "), " .. n .. " children precreated, each with a debuff row, a dispel box and the test bindings")
    local id = testSpell()
    local c1 = h:GetAttribute("child1")
    say("test spell " .. show(id) .. ": name=" .. show(c1 and c1:GetAttribute("shift-spell1"))
        .. " id=" .. show(c1 and c1:GetAttribute("ctrl-spell1")) .. " ranked=" .. show(c1 and c1:GetAttribute("alt-spell1")))
    for i = 1, 3 do say(BINDING_HELP[i]) end
    selfCast()
    C_Timer.After(0.5, headerReport)
end

--------------------------------------------------------------------------------
-- Secrets and range (probe item 5)
--------------------------------------------------------------------------------

local PROBES = {
    { "hp", UnitHealth }, { "hpMax", UnitHealthMax },
    { "dead", UnitIsDeadOrGhost }, { "conn", UnitIsConnected },
    { "role", UnitGroupRolesAssigned },
    { "name", function(u) return GetUnitName(u, false) end },
    { "class", function(u) return select(2, UnitClass(u)) end },
    { "guid", UnitGUID },
    { "inRange", function(u) return (UnitInRange(u)) end },
    { "checked", function(u) return select(2, UnitInRange(u)) end },
    { "leader", UnitIsGroupLeader },
    { "mark", GetRaidTargetIndex },
}

local function describe(fn, u)
    local ok, v = pcall(fn, u)
    if not ok then return "ERR" end
    if issecretvalue and issecretvalue(v) then return "S" end
    return tostring(v)
end

local function groupUnits()
    local units = { "player" }
    if IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end end
    end
    return units
end

local function secrets()
    local ok, auras = pcall(C_Secrets.ShouldAurasBeSecret)
    say("ShouldAurasBeSecret=" .. (ok and show(auras) or "ERR") .. "  (S = secret, ERR = threw)")
    for _, u in ipairs(groupUnits()) do
        local parts = {}
        for _, p in ipairs(PROBES) do parts[#parts + 1] = p[1] .. "=" .. describe(p[2], u) end
        say(u .. ": " .. table.concat(parts, " "))
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local okR, name, rank, subgroup = pcall(GetRaidRosterInfo, i)
            say(string.format("  roster %d: ok=%s name=%s rank=%s subgroup=%s", i, show(okR),
                show(name), show(rank), show(subgroup)))
        end
    end
end

--------------------------------------------------------------------------------
-- Out-of-combat aura reads (feeds the sound design)
--------------------------------------------------------------------------------

local function auras(unit)
    unit = (unit and unit ~= "") and unit or "player"
    for _, filter in ipairs({ "HARMFUL", "HARMFUL|RAID" }) do
        local n = 0
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then say(filter .. " #" .. i .. " threw: " .. tostring(a)) break end
            if not a then break end
            n = n + 1
            local okF, line = pcall(function()
                return string.format("%s #%d %s id=%s dispel=%s", filter, i, show(a.name),
                    show(a.spellId), show(a.dispelName))
            end)
            say(okF and line or (filter .. " #" .. i .. ": fields secret"))
        end
        say(string.format("%s on %s: %d", filter, unit, n))
    end
end

--------------------------------------------------------------------------------
-- Sounds (probe item 4)
--------------------------------------------------------------------------------

local function sound()
    local ok, willPlay, handle = pcall(PlaySoundFile, SOUND, "Master")
    say("PlaySoundFile(addon ogg): ok=" .. show(ok) .. " willPlay=" .. show(willPlay) .. " handle=" .. show(handle))
    local okK, playK = pcall(PlaySound, 8959, "Master")   -- SOUNDKIT.RAID_WARNING
    say("PlaySound(8959 raid warning): ok=" .. show(okK) .. " " .. show(playK))
end

local function enumKeys(name, t)
    if type(t) ~= "table" then say(name .. ": absent") return end
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(parts)
    say(name .. ": " .. table.concat(parts, " "))
end

-- Register an aura sound for every group unit, trying the struct shapes we
-- can think of; the errors name what the client expects.
local function auraSound(arg)
    if arg == "clear" then
        for _, h in ipairs(P.soundHandles or {}) do pcall(C_UnitAuras.RemoveAuraSound, h) end
        say("removed " .. #(P.soundHandles or {}) .. " aura sounds")
        P.soundHandles = {}
        return
    end
    enumKeys("Enum.UnitAuraSoundTrigger", Enum.UnitAuraSoundTrigger)
    if type(C_UnitAuras.AddAuraSound) ~= "function" then say("AddAuraSound absent") return end
    local trigger = Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
    local id = tonumber(arg)
    P.soundHandles = P.soundHandles or {}
    local shapes = {
        { "no spellID", { soundFileName = SOUND, outputChannel = "Master" } },
        { "dispelName=Magic", { dispelName = "Magic", soundFileName = SOUND, outputChannel = "Master" } },
        { "dispelType=1", { dispelType = 1, soundFileName = SOUND, outputChannel = "Master" } },
    }
    if id then shapes[#shapes + 1] = { "spellID=" .. id, { spellID = id, soundFileName = SOUND, outputChannel = "Master" } } end
    for _, u in ipairs(groupUnits()) do
        for _, s in ipairs(shapes) do
            local info = { unitToken = u }
            for k, v in pairs(s[2]) do info[k] = v end
            local ok, handle = pcall(C_UnitAuras.AddAuraSound, trigger, info)
            say(string.format("AddAuraSound %s %s: ok=%s -> %s", u, s[1], show(ok), show(handle)))
            if ok and handle then table.insert(P.soundHandles, handle) end
        end
    end
end

--------------------------------------------------------------------------------
-- Blizzard compact frames (probe item 6)
--------------------------------------------------------------------------------

local hidden = CreateFrame("Frame")
hidden:Hide()

local BLIZZARD = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" }

local function editModeOpen()
    local em = rawget(_G, "EditModeManagerFrame")
    return em and em:IsShown()
end

local function reparent(f, name)
    if InCombatLockdown() or editModeOpen() then return end
    if f:GetParent() ~= hidden then
        local ok, err = pcall(f.SetParent, f, hidden)
        say(string.format("reparent %s: %s", name, ok and "ok" or tostring(err)))
    end
end

local function hide()
    if InCombatLockdown() then say("out of combat only") return end
    for _, name in ipairs(BLIZZARD) do
        local f = rawget(_G, name)
        if not f then
            say(name .. ": absent")
        else
            local prot, explicit = f:IsProtected()
            say(string.format("%s: shown=%s protected=%s/%s", name, show(f:IsShown()), show(prot), show(explicit)))
            reparent(f, name)
            if not P.hooked then
                -- Never repair inline: that taints secret reads for the session.
                hooksecurefunc(f, "SetParent", function(self)
                    C_Timer.After(0, function() reparent(self, name) end)
                end)
            end
        end
    end
    P.hooked = true
end

--------------------------------------------------------------------------------
-- Frame time (probe item 7)
--------------------------------------------------------------------------------

local function fps()
    local f = P.fpsFrame or CreateFrame("Frame")
    P.fpsFrame = f
    local total, frames, worst = 0, 0, 0
    f:SetScript("OnUpdate", function(self, elapsed)
        total, frames = total + elapsed, frames + 1
        if elapsed > worst then worst = elapsed end
        if total >= 5 then
            self:SetScript("OnUpdate", nil)
            say(string.format("5 s: %.1f fps average, worst frame %.1f ms, GetFramerate %.1f, tiles %d, box inits %d, row inits %d",
                frames / total, worst * 1000, GetFramerate(), #order, P.boxInits or 0, P.rowInits or 0))
        end
    end)
    say("sampling for 5 s...")
end

--------------------------------------------------------------------------------
-- Keyboard hover-casting (probe item 8). The owner's Cell setup casts with
-- keys 1-8 and shift-R while hovering a frame. Cell does that with restricted
-- snippets (broken here), so three other routes are measured:
--   a. the client's own mouseover cast (Retail's enableMouseoverCast CVar):
--      action-bar keys cast on the hovered unit, frames included;
--   b. an insecure OnEnter/OnLeave setting override bindings on the hovered
--      tile (SetOverrideBindingClick is expected to be refused in combat);
--   c. a permanent override binding to one hidden secure button whose macro
--      casts on @mouseover (works in combat, but owns the key everywhere).
--------------------------------------------------------------------------------

local function cvar(name)
    local ok, v = pcall(C_CVar.GetCVar, name)
    return ok and v or "ERR"
end

local function mouseoverCast(arg)
    local ok, supported = pcall(IsMouseoverCastSupported)
    say("IsMouseoverCastSupported: ok=" .. show(ok) .. " " .. show(supported)
        .. "  enableMouseoverCast=" .. show(cvar("enableMouseoverCast"))
        .. " mouseoverCastModifier=" .. show(cvar("mouseoverCastModifier")))
    if arg == "on" or arg == "off" then
        local okS, err = pcall(C_CVar.SetCVar, "enableMouseoverCast", arg == "on" and "1" or "0")
        say("SetCVar enableMouseoverCast " .. arg .. ": " .. (okS and "ok" or tostring(err))
            .. " -> " .. show(cvar("enableMouseoverCast")))
        say("now hover a tile and press an action-bar key with a helpful spell, in and out of combat")
    end
end

-- b. Hover bindings: key "8" -> click the hovered tile as virtual button "key8".
local HOVER_KEY = "8"
local function clearHover(t)
    if not t.hoverBound then return end
    local okC, err = pcall(ClearOverrideBindings, t)
    if okC then t.hoverBound = nil else say("clear hover binding: " .. tostring(err)) end
end

local function hoverKeys()
    if InCombatLockdown() then say("out of combat only") return end
    P.hover = not P.hover
    local name = spellName(testSpell() or 0)
    for _, t in ipairs(order) do
        t:SetAttribute("type-key8", name and "spell" or nil)
        t:SetAttribute("spell-key8", name)
        -- Turning the mode off releases any key a hovered tile still holds:
        -- OnLeave may never come, and must not be the only cleanup.
        if not P.hover then clearHover(t) end
        if not t.hoverHooked then
            t:HookScript("OnEnter", function(self)
                if not P.hover then return end
                local okB, err = pcall(SetOverrideBindingClick, self, true, HOVER_KEY, self:GetName(), "key8")
                if okB then self.hoverBound = true end
                say("OnEnter bind " .. HOVER_KEY .. " -> " .. self.unit .. ": " .. (okB and "ok" or tostring(err)))
            end)
            -- Cleanup runs whether or not the mode is still on.
            t:HookScript("OnLeave", clearHover)
            t.hoverHooked = true
        end
    end
    say("hover keys " .. (P.hover and "on" or "off") .. ": hover a tile and press " .. HOVER_KEY
        .. " (casts " .. show(name) .. "), out of combat, then in combat")
end

-- c. A permanent binding: key "9" -> a hidden secure action button whose
-- macro casts on the mouseover unit, rank-qualified if the client allows.
local PERM_KEY = "9"
local function permKey(arg)
    if InCombatLockdown() then say("out of combat only") return end
    if P.perm then
        ClearOverrideBindings(P.perm)
        P.perm = nil
        say("permanent key " .. PERM_KEY .. " released")
        return
    end
    local id = testSpell()
    local name = id and spellName(id)
    if not name then say("no test spell: /fp raid spell <id>") return end
    local b = CreateFrame("Button", "RaidProbeMouseoverKey", UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")   -- both edges: the template acts on one (measured)
    b:SetAttribute("type", "macro")
    -- "fallback": without a friendly mouseover, the key does what action
    -- button 9 would (the dedicated-key mode should not eat the key).
    local text = "/cast [@mouseover,help,nodead] " .. name
    if arg == "fallback" then text = text .. "\n/click [@mouseover,noexists][@mouseover,harm][@mouseover,dead] ActionButton9" end
    -- "group": only a group member under the cursor gets the spell (owner's
    -- rule: a stranger hovered in the world must never be healed); anyone else,
    -- or nothing, and the key does its action-bar action on your target.
    if arg == "group" then
        text = "/cast [@mouseover,help,nodead,party][@mouseover,help,nodead,raid] " .. name
            .. "\n/click [@mouseover,noparty,noraid][@mouseover,noexists][@mouseover,nohelp][@mouseover,dead] ActionButton9"
    end
    b:SetAttribute("macrotext", text)
    b:SetScript("PostClick", function()
        local okN, who = pcall(GetUnitName, "mouseover", false)
        local okP, inParty = pcall(UnitInParty, "mouseover")
        local okR, inRaid = pcall(UnitInRaid, "mouseover")
        say(string.format("perm key %s clicked: mouseover=%s (%s) party=%s raid=%s", PERM_KEY,
            show(UnitExists("mouseover")), okN and show(who) or "?", okP and show(inParty) or "?", okR and show(inRaid) or "?"))
    end)
    local ok, err = pcall(SetOverrideBindingClick, b, true, PERM_KEY, b:GetName())
    -- Alt-9 too: does the SELFCAST modifier (Alt) send a key's @mouseover cast
    -- to the player, as it does for clicks? (the owner's druid rezzes on Alt-R)
    local okA, errA = pcall(SetOverrideBindingClick, b, true, "ALT-" .. PERM_KEY, b:GetName())
    say("ALT-" .. PERM_KEY .. " bound too: " .. (okA and "ok" or tostring(errA)))
    say("permanent key " .. PERM_KEY .. " -> " .. (text:gsub("\n", " | ")) .. ": " .. (ok and "ok" or tostring(err)))
    P.perm = b
end

--------------------------------------------------------------------------------
-- Spec and role (probe item 9): the talent-tab API is gone on Forever, and what
-- C_SpecializationInfo returns for Vanilla trees is unmeasured (porting guide).
-- Settings per role (healer/caster/melee/tank) need a role source.
--------------------------------------------------------------------------------

local function spec()
    local S = C_SpecializationInfo or {}
    local function call(label, fn, ...)
        if type(fn) ~= "function" then say(label .. ": absent") return end
        local ok, a, b2, c, d, e, f, g = pcall(fn, ...)
        say(string.format("%s: ok=%s %s %s %s %s %s %s %s", label, show(ok), show(a), show(b2), show(c),
            show(d), show(e), show(f), show(g)))
        return ok and a or nil
    end
    call("IsInitialized", S.IsInitialized)
    call("GetActiveSpecGroup", S.GetActiveSpecGroup)
    local idx = call("GetSpecialization", S.GetSpecialization)
    local _, _, classID = UnitClass("player")
    call("GetNumSpecializationsForClassID(" .. show(classID) .. ")", S.GetNumSpecializationsForClassID, classID)
    for i = 1, 4 do
        local ok, id, name, _, _, role, _, points = pcall(S.GetSpecializationInfo, i)
        say(string.format("  spec %d: ok=%s id=%s name=%s role=%s pointsSpent=%s%s", i, show(ok), show(id),
            show(name), show(role), show(points), i == idx and "  <- active" or ""))
    end
    if rawget(_G, "GetSpecializationRole") then call("GetSpecializationRole(active)", GetSpecializationRole, idx or 1) end
    call("C_ClassTalents.GetActiveConfigID", C_ClassTalents and C_ClassTalents.GetActiveConfigID)
    call("UnitGroupRolesAssigned(player)", UnitGroupRolesAssigned, "player")
    say("EventRegistry: " .. show(type(rawget(_G, "EventRegistry")))
        .. (rawget(_G, "EventRegistry") and (" TriggerEvent=" .. show(type(EventRegistry.TriggerEvent))
        .. " RegisterCallback=" .. show(type(EventRegistry.RegisterCallback))) or ""))
end

-- The Vanilla talent trees live in Retail's trait system here (one spec per
-- class, measured): map how, so "the tree with the most points" can be read.
local function traits()
    if not (rawget(_G, "C_ClassTalents") and rawget(_G, "C_Traits")) then say("C_ClassTalents/C_Traits: absent") return end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not (ok and configID) then say("no active config: " .. show(configID)) return end
    local okC, info = pcall(C_Traits.GetConfigInfo, configID)
    if not (okC and type(info) == "table") then say("GetConfigInfo: " .. show(info)) return end
    say(string.format("config %s: name=%s type=%s trees=%s", show(configID), show(info.name), show(info.type),
        show(info.treeIDs and #info.treeIDs)))
    for _, treeID in ipairs(info.treeIDs or {}) do
        local okT, tree = pcall(C_Traits.GetTreeInfo, configID, treeID)
        say(string.format(" tree %s: title=%s", show(treeID), show(okT and tree and tree.titleText)))
        local okCur, cur = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
        for i, c in ipairs(okCur and cur or {}) do
            say(string.format("  currency %d: id=%s quantity=%s max=%s spent=%s spentInTree=%s", i,
                show(c.traitCurrencyID), show(c.quantity), show(c.maxQuantity), show(c.spent), show(c.spentInTree)))
        end
        local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        nodes = okN and nodes or {}
        -- Group nodes by subtree (Retail puts spec and hero trees there) and
        -- by posX band, in case the three Vanilla trees are side by side.
        local bySub, n = {}, 0
        for _, nodeID in ipairs(nodes) do
            local okI, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
            if okI and node and node.ID and node.ID ~= 0 then
                n = n + 1
                local key = tostring(node.subTreeID) .. "/x" .. tostring(node.posX and math.floor(node.posX / 3000))
                local g = bySub[key] or { nodes = 0, ranks = 0 }
                g.nodes = g.nodes + 1
                g.ranks = g.ranks + (tonumber(node.currentRank) or 0)
                bySub[key] = g
            end
        end
        say(string.format("  %d nodes", n))
        if P.traitNodes then
            -- Every node: position, ranks, and its talent's name, sorted by x then y,
            -- so the three Vanilla trees show up as column ranges.
            local rows = {}
            for _, nodeID in ipairs(nodes) do
                local okI, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if okI and node and node.ID and node.ID ~= 0 then
                    local name = "?"
                    local entry = node.entryIDs and node.entryIDs[1]
                    local okE, e = pcall(C_Traits.GetEntryInfo, configID, entry or 0)
                    if okE and e and e.definitionID then
                        local okD, d = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
                        if okD and d then name = d.overrideName or (d.spellID and spellName(d.spellID)) or ("spell " .. show(d.spellID)) end
                    end
                    rows[#rows + 1] = { x = tonumber(node.posX) or 0, y = tonumber(node.posY) or 0,
                        text = string.format("   x=%s y=%s rank=%s/%s %s", show(node.posX), show(node.posY),
                            show(node.currentRank), show(node.maxRanks), name) }
                end
            end
            table.sort(rows, function(r1, r2) if r1.x ~= r2.x then return r1.x < r2.x end return r1.y < r2.y end)
            for _, r in ipairs(rows) do say(r.text) end
        end
        for key, g in pairs(bySub) do
            local sub = key:match("^(%d+)/")
            local name = ""
            if sub then
                local okS, si = pcall(C_Traits.GetSubTreeInfo, configID, tonumber(sub))
                name = okS and si and show(si.name) or ""
            end
            say(string.format("  group subTree/xBand=%s %s: %d nodes, %d ranks", key, name, g.nodes, g.ranks))
        end
    end
end

--------------------------------------------------------------------------------
-- Milestone 2 checks (Codex review of the click-casting design, 2026-09-29):
--   ranks <spellID>  can a LOWER rank be pinned, and how are lower ranks found?
--   longmacro        does a secure macrotext over 255 characters run to its end?
-- Keys: 0 = numeric spell ID, ALT-0 = "Name(Rank n)", CTRL-0 = the long macro,
-- all cast at your TARGET. The log's "cast sent ... spell=<id>" says which rank.
--------------------------------------------------------------------------------

-- One button per key, no modifier attributes: the first run's ALT-0 / CTRL-0
-- presses all resolved to the plain-0 attributes, so each test now has its
-- own button and binding, and measures only what it should.
local keyButtons = {}

local function keyButton(key, label)
    local b = keyButtons[key]
    if not b then
        b = CreateFrame("Button", "RaidProbeKey_" .. key:gsub("%W", "_"), UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("unit", "target")
        keyButtons[key] = b
    end
    b:SetScript("PostClick", function(_, mouse, down)
        say(string.format("%s pressed (%s, %s): type=%s spell=%s", key, label, tostring(down and "down" or "up"),
            show(b:GetAttribute("type")), show(b:GetAttribute("spell"))))
    end)
    ClearOverrideBindings(b)
    SetOverrideBindingClick(b, true, key, b:GetName())
    return b
end

local function ranks(arg)
    if InCombatLockdown() then say("out of combat only") return end
    local id = tonumber(arg)
    if not id then say("usage: /fp raid ranks <spellID of a LOWER rank you know>") return end
    local okN, name = pcall(C_Spell.GetSpellName, id)
    local okS, sub = pcall(C_Spell.GetSpellSubtext, id)
    local okK, knownIt = pcall(C_SpellBook.IsSpellKnown, id)
    say(string.format("spell %d: name=%s subtext=%s known=%s", id, show(okN and name), show(okS and sub), show(okK and knownIt)))
    if not (okN and type(name) == "string") then return end
    local byID = keyButton("0", "by numeric ID")
    byID:SetAttribute("type", "spell")
    byID:SetAttribute("spell", id)
    local byName = keyButton("ALT-0", "by rank-qualified name")
    byName:SetAttribute("type", "spell")
    byName:SetAttribute("spell", (okS and type(sub) == "string" and sub ~= "") and (name .. "(" .. sub .. ")") or name)
    say("target an enemy and press 0 (by ID " .. id .. "), then ALT-0 (by '" .. show(byName:GetAttribute("spell")) .. "')")
end

local function longMacro()
    if InCombatLockdown() then say("out of combat only") return end
    local id = testSpell()
    local name = id and spellName(id)
    if not name then say("no test spell: /fp raid spell <id>") return end
    local lines = {}
    -- Lines that can never cast ([mod,nomod] is always false), then the real one.
    for i = 1, 14 do lines[#lines + 1] = "/cast [mod,nomod][@player,noexists] " .. name .. " " .. string.rep("x", 4) .. i end
    lines[#lines + 1] = "/cast [@player] " .. name
    local text = table.concat(lines, "\n")
    local b = keyButton("CTRL-0", "long macro")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", text)
    say(string.format("CTRL-0: a %d-character macro whose LAST line casts %s on you. Does it cast?", #text, name))
end

--------------------------------------------------------------------------------
-- The addon's own hover keys (ClickCast.lua), when one casts on you instead of
-- the hovered tile: is our override the key's live binding, and which line of
-- its macro does the client pick for this mouseover? (/fp steps x hoverkey)
--------------------------------------------------------------------------------

-- GlassRaidFrames' KEY -> hidden button, read through its test seam (nil when
-- the addon isn't loaded).
local function grfKeys()
    local grf = rawget(_G, "GlassRaidFrames")
    local cc = type(grf) == "table" and grf.ClickCast
    return type(cc) == "table" and type(cc._test) == "table" and cc._test.keyButtons or nil
end

-- The macro's conditions, one clause each, for the current mouseover.
local CLAUSES = {
    "[@mouseover,exists]", "[@mouseover,help]", "[@mouseover,nodead]", "[@mouseover,party]", "[@mouseover,raid]",
    "[@mouseover,help,nodead,party]", "[@mouseover,help,nodead,raid]",
    -- Run 2: [@mouseover,party] read "no" in combat (yes out of combat) while
    -- UnitInParty("mouseover") was true. What else can tell a group member from
    -- a stranger in combat?
    "[party]", "[raid]", "[group]", "[group:party]", "[@mouseover,group]", "[@mouseover,group:party]",
    "[@party1,exists]", "[@party1,help]", "[@mouseover,noparty]", "[combat]",
}

local function mouseoverReport(label)
    local function q(fn, ...) local ok, v = pcall(fn, ...) return ok and show(v) or "ERR" end
    say(string.format("%s: mouseover exists=%s name=%s isPlayer=%s inParty=%s inRaid=%s canAssist=%s deadOrGhost=%s",
        label, q(UnitExists, "mouseover"), q(GetUnitName, "mouseover", false), q(UnitIsUnit, "mouseover", "player"),
        q(UnitInParty, "mouseover"), q(UnitInRaid, "mouseover"), q(UnitCanAssist, "player", "mouseover"),
        q(UnitIsDeadOrGhost, "mouseover")))
    local parts = {}
    for _, c in ipairs(CLAUSES) do
        local ok, r = pcall(SecureCmdOptionParse, c .. "yes;no")
        parts[#parts + 1] = c .. "=" .. (ok and show(r) or "ERR")
    end
    say("  " .. table.concat(parts, " "))
    local focus = rawget(_G, "GetMouseFoci") and select(2, pcall(GetMouseFoci))
    local f = type(focus) == "table" and focus[1]
    say("  under the cursor: " .. show(f and f.GetName and f:GetName()) .. " unit attr=" .. show(f and f.GetAttribute and f:GetAttribute("unit")))
end

local function hoverKeyState()
    local keys = grfKeys()
    if not keys then say("GlassRaidFrames' key buttons not found (addon not loaded?)") return false end
    local n = 0
    for key, b in pairs(keys) do
        n = n + 1
        local okA, live = pcall(GetBindingAction, key, true)
        local okB, base = pcall(GetBindingAction, key)
        say(string.format("key %s -> %s: live binding=%s base=%s", key, show(b:GetName()), okA and show(live) or "ERR",
            okB and show(base) or "ERR"))
        say("  macrotext: " .. show((b:GetAttribute("macrotext") or ""):gsub("\n", " | ")))
        if not b.raidProbeHooked then
            b:HookScript("PostClick", function(_, mouse, down)
                mouseoverReport("key " .. key .. " pressed (" .. show(mouse) .. ", " .. (down and "down" or "up") .. ")")
            end)
            b.raidProbeHooked = true
        end
    end
    say(string.format("in group=%s raid=%s  SELFCAST=%s autoSelfCast=%s enableMouseoverCast=%s ActionButtonUseKeyDown=%s",
        show(IsInGroup()), show(IsInRaid()), show(select(2, pcall(GetModifiedClick, "SELFCAST"))),
        show(cvar("autoSelfCast")), show(cvar("enableMouseoverCast")), show(cvar("ActionButtonUseKeyDown"))))
    local failures = rawget(_G, "GlassRaidFrames") and GlassRaidFrames.paintFailures
    for k, v in pairs(type(failures) == "table" and failures or {}) do say("  GRF failure " .. show(k) .. ": " .. show(v)) end
    return n
end

Probe:Steps("hoverkey", {
    rev = 2,
    title = "A hover key casts on you",
    { text = "Out of combat, in a group. Reading GlassRaidFrames' hover keys and hooking them.",
      auto = true, run = hoverKeyState, check = function() local k = grfKeys() return k and next(k) ~= nil, "key buttons" end },
    { text = "Hover a group member's tile (not yours) and press your hover key (6) once.",
      event = "UNIT_SPELLCAST_SENT" },
    { text = "Did the heal land on the hovered member?", ask = true },
    { text = "Now hover that member's own character in the world (or their Blizzard party frame) and press 6.",
      event = "UNIT_SPELLCAST_SENT" },
    { text = "Did that heal land on them?", ask = true },
    -- Run 1 (out of combat) worked; the self-casts in the earlier log were all in combat.
    { text = "Pull a mob. Once in combat, hover the member's TILE and press 6 once.", event = "UNIT_SPELLCAST_SENT" },
    { text = "Did that heal land on the hovered member?", ask = true },
    { text = "Still in combat: hover NOTHING (empty ground, no unit) and press 6 once.", event = "UNIT_SPELLCAST_SENT" },
    { text = "Did that cast on you or on your target?", ask = true },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

-- The fix: keys bound only while a group tile is hovered (secure OnEnter
-- wraps). Ask steps: event steps also completed on unrelated casts.
Probe:Steps("hoverkeyfix", {
    rev = 1,
    title = "Hover keys bound on the tile",
    { text = "Out of combat, in a group. Hooking GlassRaidFrames' hover keys.",
      auto = true, run = hoverKeyState, check = function() local k = grfKeys() return k and next(k) ~= nil, "key buttons" end },
    { text = "Hover the member's TILE and press 6. Did the heal land on them?", ask = true },
    { text = "Move OFF the frames (empty ground) and press 6. Did 6 do its usual action-bar action?", ask = true },
    { text = "Pull a mob. In combat, hover the member's TILE and press 6. Did the heal land on them?", ask = true },
    { text = "Still in combat, OFF the frames: press 6. Usual action-bar action?", ask = true },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

-- Run 2 found the failure in combat; this one only collects the conditions
-- there, over a member's tile, a stranger, and nothing.
Probe:Steps("hoverkeycombat", {
    rev = 1,
    title = "Hover-key conditions in combat",
    { text = "Out of combat, in a group. Hooking GlassRaidFrames' hover keys.",
      auto = true, run = hoverKeyState, check = function() local k = grfKeys() return k and next(k) ~= nil, "key buttons" end },
    { text = "Out of combat: hover the member's TILE and press 6 once (the baseline).", event = "UNIT_SPELLCAST_SENT" },
    { text = "Pull a mob. In combat, hover the member's TILE and press 6 once.", event = "UNIT_SPELLCAST_SENT" },
    { text = "Still in combat: hover a friendly player NOT in your group (in the world) and press 6 once. "
        .. "Skip if there is none nearby.", event = "UNIT_SPELLCAST_SENT" },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- Secure snippets again (/fp steps raid snippets). Measured broken on early
-- builds (loadstring_untainted missing), but Clique 5.1.3 turned its Forever
-- kill-switch off and EllesmereUI wraps OnEnter with SetBindingClick on 16001.
-- If they run now, a hover key can be bound only while a tile is hovered
-- (Cell/Clique's design), which needs no [party] check ([party] reads false
-- in combat, measured above).
--------------------------------------------------------------------------------

local SNIP_KEY = "7"

local function snippetsSetup()
    if InCombatLockdown() then say("out of combat only") return false end
    say("loadstring_untainted in _G: " .. show(type(rawget(_G, "loadstring_untainted"))))
    local h = P.snipHeader
    if not h then
        h = CreateFrame("Frame", "RaidProbeSnippetHeader", UIParent, "SecureHandlerStateTemplate")
        P.snipHeader = h
    end
    -- 1. Execute: a plain snippet.
    local okE, errE = pcall(h.Execute, h, [[ self:SetAttribute("exec", "ran") ]])
    say("Execute: " .. (okE and "ok" or tostring(errE)) .. " -> exec=" .. show(h:GetAttribute("exec")))
    -- 2. A state driver and its _onstate- snippet.
    h:SetAttribute("_onstate-probe", [[ self:SetAttribute("seen", newstate) ]])
    local okD, errD = pcall(RegisterStateDriver, h, "probe", "[combat] in; out")
    say("RegisterStateDriver: " .. (okD and "ok" or tostring(errD)))
    C_Timer.After(0.5, function() say("  state driver after 0.5 s: seen=" .. show(h:GetAttribute("seen"))) end)
    -- 3. The hover-key design: OnEnter binds key 7 to the hovered button, OnLeave clears it.
    local b = P.snipButton
    if not b then
        b = CreateFrame("Button", "RaidProbeSnippetButton", UIParent, "SecureActionButtonTemplate")
        b:SetSize(140, 44)
        b:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        b:RegisterForClicks("AnyUp", "AnyDown")
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.4, 0.8, 0.7)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText("hover me, press " .. SNIP_KEY)
        b:SetScript("PostClick", function(_, mouse, down)
            P.snipClicks = (P.snipClicks or 0) + 1
            say(string.format("key %s reached the hovered button (%s, %s), entered=%s, %d so far", SNIP_KEY,
                show(mouse), down and "down" or "up", show(b:GetAttribute("entered")), P.snipClicks))
        end)
        local okW, errW = pcall(h.WrapScript, h, b, "OnEnter", ([[
            self:SetAttribute("entered", (self:GetAttribute("entered") or 0) + 1)
            self:SetBindingClick(true, %q, self, "LeftButton")
        ]]):format(SNIP_KEY))
        say("WrapScript OnEnter: " .. (okW and "ok" or tostring(errW)))
        local okL, errL = pcall(h.WrapScript, h, b, "OnLeave", [[ self:ClearBindings() ]])
        say("WrapScript OnLeave: " .. (okL and "ok" or tostring(errL)))
        P.snipButton = b
    end
    b:Show()
    P.snipClicks = 0
    return okE and h:GetAttribute("exec") == "ran", okD
end

local function snippetsCheck(wantState)
    return function()
        local h = P.snipHeader
        local seen = h and h:GetAttribute("seen")
        local clicks = P.snipClicks or 0
        P.snipClicks = 0
        return clicks > 0 and (not wantState or seen == wantState), "clicks=" .. clicks, "state=" .. show(seen)
    end
end

Probe:Steps("snippets", {
    rev = 1,
    title = "Do secure snippets run on this build?",
    { text = "Out of combat. Setting up a snippet header and a blue 'hover me' box.",
      auto = true, run = snippetsSetup, check = function() return P.snipHeader and P.snipHeader:GetAttribute("exec") == "ran", "Execute ran" end },
    { text = "Hover the blue box and press 7 once, then press Next.", check = snippetsCheck("out") },
    { text = "Move the cursor OFF the box and press 7 once (it should do 7's usual action). Then Next.",
      check = function() local n = P.snipClicks or 0; P.snipClicks = 0 return n == 0, "clicks=" .. n end },
    { text = "Pull a mob. In combat, hover the blue box and press 7 once, then press Next.", check = snippetsCheck("in") },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- The member gate for hover keys on any unit frame (#61, /fp steps raid
-- ufgate). A target or focus frame can show a stranger, so its OnEnter
-- snippet must ask whether the unit is in the group before binding. The
-- restricted environment has UnitPlayerOrPetInParty/InRaid, but [party]
-- reads false in combat (measured above), and these may too. The box is
-- bound to "target" (GlassUnitFrames hides Blizzard's target frame); the
-- snippet records what it saw on the box, then binds key 7 only if the gate
-- passed: the same rule GlassRaidFrames ships.
--------------------------------------------------------------------------------

local GATE_KEY = "7"
local GATE_SNIPPET = ([[
    local u = self:GetAttribute("unit")
    self:SetAttribute("rp-seen", (self:GetAttribute("rp-seen") or 0) + 1)
    self:SetAttribute("rp-party", "threw")
    self:SetAttribute("rp-raid", "threw")
    local party = u and UnitPlayerOrPetInParty(u)
    self:SetAttribute("rp-party", party and "yes" or "no")
    local raid = u and UnitPlayerOrPetInRaid(u)
    self:SetAttribute("rp-raid", raid and "yes" or "no")
    if party or raid then self:SetBindingClick(true, %q, self, "LeftButton") end
]]):format(GATE_KEY)

local function gateSetup()
    if InCombatLockdown() then say("out of combat only") return false end
    if P.gateBox then P.gateBox:Show() return true end
    local h = CreateFrame("Frame", "RaidProbeGateHeader", UIParent, "SecureHandlerBaseTemplate")
    local b = CreateFrame("Button", "RaidProbeGateBox", UIParent, "SecureUnitButtonTemplate")
    b:SetSize(160, 44)
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    b:SetAttribute("unit", "target")
    b:SetAttribute("*type1", "target")
    b:RegisterForClicks("AnyUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.6, 0.3, 0.7)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText("your target: hover, press " .. GATE_KEY)
    -- Key 7 clicks the box with "LeftButton": *type1 targets your own
    -- target again, which is harmless. PostClick counts it.
    b:HookScript("PostClick", function(_, mouse)
        local fighting = InCombatLockdown()
        P.gateClicks = (P.gateClicks or 0) + 1
        if fighting then P.gateCombatClicks = (P.gateCombatClicks or 0) + 1 end
        say(string.format("key %s reached the box (%s): party=%s raid=%s seen=%s combat=%s", GATE_KEY, show(mouse),
            show(b:GetAttribute("rp-party")), show(b:GetAttribute("rp-raid")), show(b:GetAttribute("rp-seen")),
            show(fighting)))
    end)
    local okW, errW = pcall(SecureHandlerWrapScript, b, "OnEnter", h, GATE_SNIPPET)
    say("WrapScript OnEnter: " .. (okW and "ok" or tostring(errW)))
    local okL, errL = pcall(SecureHandlerWrapScript, b, "OnLeave", h, "self:ClearBindings()")
    say("WrapScript OnLeave: " .. (okL and "ok" or tostring(errL)))
    P.gateBox = b
    return okW and okL
end

-- What the last hover saw. want = "yes" / "no" (nil: just record it).
-- inCombat: the step only counts if a press came under lockdown (rev 1 let
-- a 4 s fight end before the presses and still passed).
local function gateCheck(want, inCombat)
    return function()
        local b = P.gateBox
        local party, raid = b and b:GetAttribute("rp-party"), b and b:GetAttribute("rp-raid")
        local clicks, combatClicks = P.gateClicks or 0, P.gateCombatClicks or 0
        P.gateClicks, P.gateCombatClicks = 0, 0
        local member = (party == "yes" or raid == "yes") and "yes" or "no"
        local _, name = try("target name", GetUnitName, "target", false)
        local pass = party ~= "threw" and raid ~= "threw" and party ~= nil
            and (want == nil or member == want) and ((member == "yes") == (clicks > 0))
            and (not inCombat or combatClicks > 0)
        return pass, "party=" .. show(party), "raid=" .. show(raid), "clicks=" .. clicks,
            "in combat=" .. combatClicks, "target=" .. show(name)
    end
end

Probe:Steps("ufgate", {
    rev = 2,
    title = "Hover keys on a target frame: is the unit in my group?",
    { text = "Out of combat, in a party. Setting up a green box bound to your target.",
      auto = true, run = gateSetup, check = function() return P.gateBox ~= nil, "box built" end },
    { text = "Target a PARTY MEMBER. Hover the green box, press 7 once, then Next.", check = gateCheck("yes") },
    { text = "Target YOURSELF. Hover the green box, press 7 once, then Next.", check = gateCheck(nil) },
    { text = "Target a friendly player NOT in your group, or a friendly NPC. Hover the box, press 7, then Next.",
      check = gateCheck("no") },
    { text = "Pull a mob that lives a while (don't attack it). While it hits you, target the PARTY MEMBER, hover the box, press 7 once, then Next.",
      check = gateCheck("yes", true) },
    { text = "Still in combat, target YOURSELF, hover the box, press 7 once, then Next.", check = gateCheck(nil, true) },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- Keys anywhere under the cursor (#63, /fp steps raid worldkey). A DPS role
-- keeps its keys bound all the time, so an enemy hovered in the world takes
-- the spell; the spell's own reaction picks [harm] or [help]. Measures:
-- C_Spell.IsSpellHarmful/IsSpellHelpful on Vanilla rank IDs (the dump lists
-- them; presence is not a contract), and [@mouseover,harm] on a world enemy,
-- in and out of combat. Item B (tests A-D) already showed a key's @mouseover
-- conditions applying to units in the world.
--------------------------------------------------------------------------------

-- First ranks across classes; Dispel Magic and Purge hit friend or foe.
local REACTION_IDS = { 589, 585, 8092, 14914, 139, 2061, 2050, 17, 2006, 527, 586,   -- priest
                       686, 172, 5782,                                                -- warlock
                       8921, 5176, 5185, 774, 1126,                                   -- druid
                       116, 133, 1459,                                                -- mage
                       635, 19750, 853, 19740,                                        -- paladin
                       403, 331, 370,                                                 -- shaman
                       3044, 1752, 78 }                                               -- hunter, rogue, warrior
local WORLD_KEYS = { harm = "7", help = "8" }

-- true/false, or "threw".
local function reaction(id)
    local okH, harmful = pcall(C_Spell.IsSpellHarmful, id)
    local okP, helpful = pcall(C_Spell.IsSpellHelpful, id)
    if not okH then harmful = "threw" end
    if not okP then helpful = "threw" end
    return harmful, helpful
end

local function worldSetup()
    if InCombatLockdown() then say("out of combat only") return false end
    local threw = 0
    P.worldHarm, P.worldHelp = nil, nil
    for _, id in ipairs(REACTION_IDS) do
        local harmful, helpful = reaction(id)
        local learned = known(id)
        say(string.format("reaction %d %s: harmful=%s helpful=%s known=%s", id, show(spellName(id)),
            show(harmful), show(helpful), show(learned)))
        if harmful == "threw" or helpful == "threw" then threw = threw + 1 end
        if learned and harmful == true and helpful ~= true and not P.worldHarm then P.worldHarm = id end
        if learned and helpful == true and harmful ~= true and not P.worldHelp then P.worldHelp = id end
    end
    if not (P.worldHarm and P.worldHelp) then
        say("no learned harmful-only and helpful-only spell from the list on this character")
        return false
    end
    P.worldKeys = P.worldKeys or {}
    for kind, key in pairs(WORLD_KEYS) do
        local id = kind == "harm" and P.worldHarm or P.worldHelp
        local b = P.worldKeys[kind]
        if not b then
            b = CreateFrame("Button", "RaidProbeWorldKey" .. kind, UIParent, "SecureActionButtonTemplate")
            b:RegisterForClicks("AnyUp", "AnyDown")   -- both edges: the template acts on one (measured)
            b:SetAttribute("type", "macro")
            -- The key really reached the button, and in combat or not: a
            -- check can't pass on a press that never happened (Codex P2 on #64).
            b:HookScript("PostClick", function(_, _, down)
                local p, fighting = P.worldPresses[kind], InCombatLockdown()
                p.n = p.n + 1
                if fighting then p.combat = p.combat + 1 end
                say(string.format("key %s reached its button (%s), combat=%s", WORLD_KEYS[kind], down and "down" or "up", show(fighting)))
            end)
            P.worldKeys[kind] = b
        end
        -- The shape GlassRaidFrames ships: the spell on the matching
        -- mouseover, else the key's own bar button on the exact complement.
        local text = string.format("/cast [@mouseover,%s,nodead] %s\n/click [@mouseover,noexists][@mouseover,no%s][@mouseover,dead] ActionButton%s",
            kind, spellName(id), kind, key)
        b:SetAttribute("macrotext", text)
        local ok, err = pcall(SetOverrideBindingClick, b, true, key, b:GetName())
        say(string.format("key %s always bound (%s): %s", key, ok and "ok" or tostring(err), (text:gsub("\n", " | "))))
    end
    P.worldCasts = {}
    P.worldPresses = { harm = { n = 0, combat = 0 }, help = { n = 0, combat = 0 } }
    return threw == 0, "threw=" .. threw, "harm=" .. show(spellName(P.worldHarm)), "help=" .. show(spellName(P.worldHelp))
end

local function worldRelease()
    if InCombatLockdown() then say("out of combat only") return false end
    for _, b in pairs(P.worldKeys or {}) do ClearOverrideBindings(b) end
    say("keys " .. WORLD_KEYS.harm .. " and " .. WORLD_KEYS.help .. " released")
    return true
end

-- The step's presses and casts. The key must have reached its button
-- (under lockdown when inCombat) before anything counts: no press, or a
-- press out of combat, never passes (Codex P2 on #64). want = "spell": the
-- macro chose the key's own spell (in combat when inCombat); "other": it
-- didn't (the bar's action, or nothing). Rev 3 (run #188): any cast of the
-- step counts, not the last (the owner's own casts came after), at any rank
-- (the bare name casts the highest), and a failed one too (out of range:
-- the macro still chose the spell).
local function worldCheck(kind, want, inCombat)
    return function()
        local casts = P.worldCasts or {}
        local presses = P.worldPresses and P.worldPresses[kind] or { n = 0, combat = 0 }
        P.worldCasts = {}
        if P.worldPresses then P.worldPresses[kind] = { n = 0, combat = 0 } end
        local name = spellName(kind == "harm" and P.worldHarm or P.worldHelp)
        local chose, seen = false, {}
        for _, c in ipairs(casts) do
            if name and spellName(c.spell) == name and (c.combat or not inCombat) then chose = true end
            seen[#seen + 1] = string.format("%s%s@%s", show(c.spell), c.failed and "(failed)" or "", show(c.target))
        end
        local pass = (inCombat and presses.combat or presses.n) > 0 and (want == "spell") == chose
        return pass, "presses=" .. presses.n, "in combat=" .. presses.combat, "casts=" .. table.concat(seen, " ")
    end
end

Probe:Steps("worldkey", {
    rev = 3,
    title = "Keys anywhere: the spell's reaction, an enemy hovered in the world",
    { text = "Out of combat. Logging each spell's reaction, then binding 7 (a harmful spell) and 8 (a helpful one) all the time.",
      auto = true, run = worldSetup, check = function() return P.worldHarm ~= nil and P.worldHelp ~= nil, "keys bound" end },
    { text = "Hover an ENEMY in the world (don't target it) and press 7 once. Then Next.",
      check = worldCheck("harm", "spell") },
    { text = "Hover a FRIENDLY character in the world and press 7 once (expect your bar's 7, or nothing). Then Next.",
      check = worldCheck("harm", "other") },
    { text = "Hover a FRIENDLY character in the world and press 8 once. Then Next.",
      check = worldCheck("help", "spell") },
    { text = "Pull a mob that lives a while. In combat, hover an enemy and press 7 once. Then Next.",
      check = worldCheck("harm", "spell", true) },
    { text = "Still in combat, hover NOTHING (empty ground) and press 7 once (expect your bar's 7). Then Next.",
      check = worldCheck("harm", "other", true) },
    { text = "Out of combat now. Releasing keys 7 and 8.", auto = true, run = worldRelease },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- Visibility ownership, as the real Roster.lua will do it: out of combat, the
-- set that doesn't match the group mode is unwatched and hidden (party tokens
-- stay valid inside a raid, so both sets would show). In combat nothing
-- changes; a conversion waits for PLAYER_REGEN_ENABLED.
function applyMode()
    if not P.built or InCombatLockdown() then return end
    local raid = IsInRaid()
    if P.mode == raid then return end
    P.mode = raid
    for _, t in ipairs(order) do
        local wanted = (t.unit:find("^raid") ~= nil) == raid
        if wanted then RegisterUnitWatch(t) else UnregisterUnitWatch(t); t:Hide() end
    end
    say("mode: " .. (raid and "raid" or "party") .. " set watched, the other hidden")
end

local function rosterLog()
    local parts = {}
    for _, t in ipairs(order) do
        if t:IsShown() then parts[#parts + 1] = t.unit end
    end
    say(string.format("roster: raid=%s members=%s shown tiles: %s", show(IsInRaid()), show(GetNumGroupMembers()),
        table.concat(parts, ",")))
    if P.header then headerReport() end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        Probe:Ready()   -- logs EARLY if the host somehow isn't loaded
        if type(RaidProbeDB) ~= "table" then RaidProbeDB = {} end
        if type(RaidProbeDB.log) ~= "table" then RaidProbeDB.log = {} end
        Probe:UseLog(RaidProbeDB.log, MAX_LOG)   -- from here on, lines are saved too
        RaidProbeDB.sessions = (RaidProbeDB.sessions or 0) + 1
        say("session " .. RaidProbeDB.sessions .. ", build " .. table.concat({ GetBuildInfo() }, " ", 1, 2)
            .. ", log " .. #RaidProbeDB.log .. " lines. /fp raid for the commands")
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Identity repaints at once, in combat too; the unit watch decides shown.
        for _, t in ipairs(order) do paint(t) end
        for _, t in ipairs(order) do
            if t.boxContainer then pcall(t.boxContainer.UpdateAllAuras, t.boxContainer) end
            if t.rowContainer then pcall(t.rowContainer.UpdateAllAuras, t.rowContainer) end
        end
        applyMode()
        C_Timer.After(0.3, rosterLog)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_CONNECTION" then
        local t = tiles[a1]
        if t then paint(t) end
    elseif event == "UNIT_SPELLCAST_SENT" then
        P.lastSent = { target = a2, spell = a4, combat = InCombatLockdown() }
        if P.worldCasts then table.insert(P.worldCasts, P.lastSent) end
        say(string.format("cast sent: target=%s spell=%s", show(a2), show(a4)))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        say("cast succeeded: spell=" .. show(a3))
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if P.worldCasts then table.insert(P.worldCasts, { spell = a3, failed = true, combat = InCombatLockdown() }) end
        say("cast failed: spell=" .. show(a3))
    elseif event == "UNIT_AURA" then
        if P.watch and tiles[a1] then
            local okF, full = pcall(function() return a2 and a2.isFullUpdate end)
            say(string.format("UNIT_AURA %s payload %s", a1,
                okF and ("readable full=" .. show(full)) or "secret"))
        end
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        if P.watch then say(string.format("UNIT_IN_RANGE_UPDATE %s -> %s", show(a1), show(a2))) end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        say(string.format("|cff7fd4ff%s|r %s %s", event, show(a1), show(a2)))
    elseif event == "PLAYER_REGEN_DISABLED" then
        say("combat starts")
    elseif event == "PLAYER_REGEN_ENABLED" then
        say("combat ends")
        applyMode()
        C_Timer.After(0.3, rosterLog)
    end
end)
-- Blocked and forbidden actions are the host's baseline's (logged in the
-- same console), so they're no longer registered here.
Probe:RegisterEvents(ev, { "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_AURA", "UNIT_IN_RANGE_UPDATE", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" })
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
    local ok, r = pcall(ev.RegisterUnitEvent, ev, e, "player")
    if not ok or r == false then say("could not register " .. e .. ": " .. show(r)) end
end

--------------------------------------------------------------------------------
-- Indicators (#19): what one tile's aura containers can show, measured with
-- Renew, Power Word: Shield and Weakened Soul (what the owner can cast).
--   /fp raid ind [unit]  a panel of labelled test containers on unit
--   /fp raid ind state   out of combat: which rows are lit, plus src
--   /fp raid ind src [u] out of combat: each aura's id, source, and which
--                       filter strings let it through (no container involved)
--   /fp raid ind reconf  out of combat: change filters, enable, size live
--   /fp raid ind cost    40 tiles x the planned default indicators
--   /fp raid ind ids     names and ranks of the planned default spell IDs
--------------------------------------------------------------------------------

-- Every Vanilla rank, lowest first (to be checked in game with "ind ids").
local FAMILIES = {
    { "Renew", 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },
    { "Power Word: Shield", 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
    { "Weakened Soul", 6788 },
    { "Rejuvenation", 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
    { "Regrowth", 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
    { "Power Infusion", 10060 },
    { "Fear Ward", 6346 },
    { "Thorns", 467, 782, 1075, 8914, 9756, 9910 },
    { "Blessing of Protection", 1022, 5599, 10278 },
    { "Blessing of Sacrifice", 6940, 20729 },
    { "Innervate", 29166 },
}
local RENEW, SHIELD, WEAKENED = FAMILIES[1], FAMILIES[2], FAMILIES[3]

-- {[id] = true} for every rank of the given families.
local function idSet(...)
    local set = {}
    for _, fam in ipairs({ ... }) do
        for i = 2, #fam do set[fam[i]] = true end
    end
    return set
end

local function secrecyName(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    for k, n in pairs(Enum.SecrecyLevel or {}) do if n == v then return k end end
    return show(v)
end

-- The look of every probe button, set once here (the client locks the button
-- after initializeFrame): backing, icon or colour square, swipe, timer text,
-- stack count. `level` stacks slots; nil keeps the client's.
local function indButton(size, level, square, anchorTo)
    return function(ab)
        ab:EnableMouse(false)
        ab:SetSize(size, size)
        if anchorTo then
            ab:ClearAllPoints()
            ab:SetPoint("LEFT", anchorTo, "LEFT", 0, 0)
        end
        if level then ab:SetFrameLevel(level) end
        local back = ab:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(ab)
        back:SetColorTexture(0, 0, 0, 1)
        local art = ab:CreateTexture(nil, "ARTWORK")
        art:SetPoint("TOPLEFT", ab, "TOPLEFT", 1, -1)
        art:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -1, 1)
        if square then
            art:SetColorTexture(square[1], square[2], square[3], 1)
        else
            art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            try("SetIcon", ab.SetIcon, ab, art)
        end
        local okCd, cd = pcall(CreateFrame, "Cooldown", nil, ab, "CooldownFrameTemplate")
        if okCd and cd then
            cd:SetAllPoints(ab)
            pcall(cd.SetReverse, cd, true)
            pcall(cd.SetHideCountdownNumbers, cd, true)
            try("SetDurationCooldown", ab.SetDurationCooldown, ab, cd)
        end
        local top = CreateFrame("Frame", nil, ab)
        top:SetAllPoints(ab)
        top:SetFrameLevel(ab:GetFrameLevel() + 5)
        local timer = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timer:SetPoint("CENTER", ab, "CENTER", 0, 0)
        try("SetDurationText", ab.SetDurationText, ab, timer, {})
        local count = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", 1, -1)
        try("SetApplicationCount", ab.SetApplicationCount, ab, count, {})
        P.indInits = (P.indInits or 0) + 1
    end
end

local IND_ROW, IND_ICON = 24, 16

-- Point the panel's containers at `unit` and redraw (works in combat).
local function indBind(unit)
    P.indUnit = unit
    for _, c in ipairs(P.indContainers or {}) do
        try("ind SetUnit", c.SetUnit, c, unit)
        try("ind UpdateAllAuras", c.UpdateAllAuras, c)
    end
    if P.indTitle then P.indTitle:SetText("RaidProbe indicators on " .. unit) end
    say("indicators now on " .. unit)
end

local function indPanel(unit)
    if P.indPanel then
        indBind(unit)
        return
    end
    if InCombatLockdown() then say("out of combat only (the first time)") return end
    local panel = CreateFrame("Frame", "RaidProbeInd", UIParent)
    panel:SetSize(470, 8 * IND_ROW + 30)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0, 0, 0, 0.6)
    P.indTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    P.indTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    P.indPanel, P.indContainers, P.indByKey, P.indRows = panel, {}, {}, {}

    -- One labelled row: the label on the left, a holder frame (ours) on the
    -- right that buttons and the container anchor to (never to a container).
    local rows = 0
    local function row(label)
        rows = rows + 1
        local y = -24 - (rows - 1) * IND_ROW
        local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, y - 4)
        text:SetText(label)
        local holder = CreateFrame("Frame", nil, panel)
        holder:SetSize(4 * (IND_ICON + 2), IND_ICON)
        holder:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, y)
        return holder
    end
    local function container(key, holder)
        local c = newContainer(panel)
        if not c then return nil end
        c:SetAllPoints(holder)
        c:SetFrameLevel(panel:GetFrameLevel() + 5)
        P.indContainers[#P.indContainers + 1] = c
        P.indByKey[key] = c
        return c
    end
    local function rowGroup(key, label, filter, include, growLeft)
        local holder = row(label)
        local c = container(key, holder)
        if not c then return end
        P.indRows[#P.indRows + 1] = { label = label, c = c, group = key }
        try("AddAuraGroup " .. key, c.AddAuraGroup, c, key, filter, {
            maxFrameCount = 4,
            candidateFilters = include and { includeSpellIDs = include } or {},
            initializeFrame = indButton(IND_ICON),
            layout = { elementWidth = IND_ICON, elementHeight = IND_ICON, elementSpacing = 2, lineSpacing = 2 },
        })
        if growLeft then
            local D = AnchorUtil and AnchorUtil.FlowDirection
            try("SetFlowLayoutAnchorPoint", c.SetFlowLayoutAnchorPoint, c, "TOPRIGHT")
            if D then try("SetFlowLayoutGrowthDirection", c.SetFlowLayoutGrowthDirection, c, D.Left, D.Down) end
        end
    end
    local function rowSlots(key, label, slots)
        local holder = row(label)
        local c = container(key, holder)
        if not c then return end
        local keys = {}
        for i, s in ipairs(slots) do keys[i] = s.key end
        P.indRows[#P.indRows + 1] = { label = label, c = c, slots = keys }
        for i, s in ipairs(slots) do
            -- Slot 1 gets the highest level band: it covers the others.
            local level = panel:GetFrameLevel() + 10 + (#slots - i + 1) * 10
            try("AddAuraSlot " .. s.key, c.AddAuraSlot, c, s.key, s.filter, {
                candidateFilters = { includeSpellIDs = s.include },
                initializeFrame = indButton(IND_ICON, level, s.square, holder),
            })
        end
    end

    rowGroup("RP_IND_HOTS", "1 my HoTs: HELPFUL|PLAYER|RAID_IN_COMBAT, no IDs (grows left)",
        "HELPFUL|PLAYER|RAID_IN_COMBAT", nil, true)
    rowGroup("RP_IND_MINE", "1b all mine: HELPFUL|PLAYER, no IDs", "HELPFUL|PLAYER", nil, false)
    rowSlots("RP_IND_RENEW_MINE", "2 Renew, only mine (slot)",
        { { key = "RP_IND_RENEW_MINE", filter = "HELPFUL|PLAYER", include = idSet(RENEW) } })
    rowSlots("RP_IND_RENEW_ANY", "2b Renew, anyone's (slot)",
        { { key = "RP_IND_RENEW_ANY", filter = "HELPFUL", include = idSet(RENEW) } })
    rowSlots("RP_IND_WS", "3 Weakened Soul by ID (red square)",
        { { key = "RP_IND_WS", filter = "HARMFUL", include = idSet(WEAKENED), square = { 1, 0.15, 0.15 } } })
    rowGroup("RP_IND_ROW", "4 Renew + Shield IDs, mine (row, grows left)", "HELPFUL|PLAYER",
        idSet(RENEW, SHIELD), true)
    rowSlots("RP_IND_STACK", "6 stacked: Shield over Renew (mine)", {
        { key = "RP_IND_STACK_1", filter = "HELPFUL|PLAYER", include = idSet(SHIELD) },
        { key = "RP_IND_STACK_2", filter = "HELPFUL|PLAYER", include = idSet(RENEW) },
    })
    rowGroup("RP_IND_DISPEL", "8 dispellable by me: HARMFUL|RAID", "HARMFUL|RAID", nil, false)

    for _, id in ipairs({ 139, 17, 6788, 10060, 6346, 467 }) do
        local ok, v = pcall(C_Secrets.GetSpellAuraSecrecy, id)
        say(string.format("GetSpellAuraSecrecy(%d %s) = %s", id, show(spellName(id)), ok and secrecyName(v) or ("ERR " .. tostring(v))))
    end
    say(string.format("indicator panel: %d containers, %d buttons initialised", #P.indContainers, P.indInits or 0))
    indBind(unit)
end

-- Out of combat: each aura on `unit`, its source, and which filter strings
-- keep it. Answers items 1, 3 and 8 without any container.
local IND_FILTERS = {
    HELPFUL = { "HELPFUL|PLAYER", "HELPFUL|PLAYER|RAID_IN_COMBAT", "HELPFUL|RAID_IN_COMBAT" },
    HARMFUL = { "HARMFUL|PLAYER", "HARMFUL|RAID", "HARMFUL|RAID_PLAYER_DISPELLABLE" },
}

local function indSources(unit)
    unit = (unit and unit ~= "") and unit or "player"
    for _, kind in ipairs({ "HELPFUL", "HARMFUL" }) do
        local n = 0
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, kind)
            if not ok then say(kind .. " #" .. i .. " threw: " .. tostring(a)) break end
            if not a then break end
            n = n + 1
            local okF, line = pcall(function()
                local keeps = {}
                for _, f in ipairs(IND_FILTERS[kind]) do
                    local okI, out = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, a.auraInstanceID, f)
                    keeps[#keeps + 1] = f:gsub("^%u+|", "") .. "=" .. (not okI and "ERR" or (out and "out" or "IN"))
                end
                return string.format("%s #%d %s id=%s src=%s dur=%s %s", kind, i, show(a.name), show(a.spellId),
                    show(a.sourceUnit), show(a.duration), table.concat(keeps, " "))
            end)
            say(okF and line or (kind .. " #" .. i .. ": fields secret (" .. tostring(line) .. ")"))
        end
        say(string.format("%s on %s: %d", kind, unit, n))
    end
end

-- Which panel rows are lit right now, read from the client's own buttons
-- (out of combat: in combat they are locked and the read is refused).
local function shownOf(frame)
    if not frame then return "none" end
    local ok, v = pcall(frame.IsShown, frame)
    if not ok then return "ERR" end
    return show(v)
end

local function indState()
    if not P.indPanel then say("run /fp raid ind first") return end
    for _, r in ipairs(P.indRows) do
        local parts = {}
        if r.group then
            -- A secret or failed read is unknown, never "hidden" (Codex review
            -- of #20: secret IsShown read as 0 shown made a lit row look empty).
            local okN, n = pcall(r.c.GetAuraGroupFrameCount, r.c, r.group)
            local lit, hidden, unknown = 0, 0, 0
            for i = 1, (okN and type(n) == "number") and n or 0 do
                local okF, f = pcall(r.c.GetAuraGroupFrame, r.c, r.group, i)
                local v = okF and shownOf(f) or "ERR"
                if v == "true" then lit = lit + 1
                elseif v == "false" then hidden = hidden + 1
                else unknown = unknown + 1 end
            end
            parts[1] = string.format("%s buttons: %d shown, %d hidden, %d unknown (secret or unreadable)",
                okN and show(n) or "ERR", lit, hidden, unknown)
        else
            for i, key in ipairs(r.slots) do
                local okF, f = pcall(r.c.GetAuraSlotFrame, r.c, key)
                parts[i] = "slot " .. i .. " shown=" .. (okF and shownOf(f) or "ERR")
            end
        end
        say("state " .. r.label:match("^(%S+)") .. ": " .. table.concat(parts, ", "))
    end
end

-- Out of combat, a toggle: Renew-mine slot -> Shield IDs at 22 px, the
-- anyone slot disabled; again to undo. Logs what each call did.
local function indReconf()
    if not P.indPanel then say("run /fp raid ind first") return end
    P.indReconf = not P.indReconf
    local on = P.indReconf
    local B, C = P.indByKey.RP_IND_RENEW_MINE, P.indByKey.RP_IND_RENEW_ANY
    try("SetAuraSlotCandidateFilters", B.SetAuraSlotCandidateFilters, B, "RP_IND_RENEW_MINE",
        { includeSpellIDs = on and idSet(SHIELD) or idSet(RENEW) })
    local okF, frame = try("GetAuraSlotFrame", B.GetAuraSlotFrame, B, "RP_IND_RENEW_MINE")
    if okF and frame then try("slot SetSize", frame.SetSize, frame, on and 22 or IND_ICON, on and 22 or IND_ICON) end
    try("SetAuraSlotEnabled", C.SetAuraSlotEnabled, C, "RP_IND_RENEW_ANY", not on)
    for _, c in ipairs({ B, C }) do try("UpdateAllAuras", c.UpdateAllAuras, c) end
    say(on and "reconf: row 2 now tracks Shield at 22 px, row 2b disabled (run again to undo)"
           or "reconf undone: row 2 tracks Renew at 16 px, row 2b enabled")
end

-- 40 tiles with the planned defaults: my HoTs row, received row, Weakened
-- Soul slot, debuff row. Run /fp raid fps before and after.
local function indCost()
    if P.indCost then say("already built (/reload to drop)") return end
    if InCombatLockdown() then say("out of combat only") return end
    local units = groupUnits()
    local root = CreateFrame("Frame", "RaidProbeIndCost", UIParent)
    root:SetSize(8 * 62, 5 * 32)
    root:SetPoint("TOP", UIParent, "TOP", 0, -40)
    collectgarbage("collect")
    local kb0, t0, inits0 = collectgarbage("count"), debugprofilestop(), P.indInits or 0
    local received = idSet(FAMILIES[6], FAMILIES[7], FAMILIES[8], FAMILIES[9], FAMILIES[10], FAMILIES[11])
    for i = 1, 40 do
        local tile = CreateFrame("Frame", nil, root)
        tile:SetSize(60, 30)
        tile:SetPoint("TOPLEFT", root, "TOPLEFT", ((i - 1) % 8) * 62, -math.floor((i - 1) / 8) * 32)
        local unit = units[(i - 1) % #units + 1]
        local specs = {
            { "group", "HELPFUL|PLAYER|RAID_IN_COMBAT", nil, "TOPRIGHT" },
            { "group", "HELPFUL", received, "LEFT" },
            { "slot", "HARMFUL", idSet(WEAKENED), "TOPLEFT" },
            { "group", "HARMFUL", nil, "BOTTOMLEFT" },
        }
        for k, s in ipairs(specs) do
            local c = newContainer(tile)
            if c then
                c:SetSize(40, 10)
                c:SetPoint(s[4], tile, s[4], 0, 0)
                local key = "RP_COST_" .. k
                if s[1] == "group" then
                    try("cost group", c.AddAuraGroup, c, key, s[2], {
                        maxFrameCount = 3, candidateFilters = s[3] and { includeSpellIDs = s[3] } or {},
                        initializeFrame = indButton(10),
                        layout = { elementWidth = 10, elementHeight = 10, elementSpacing = 1, lineSpacing = 1 },
                    })
                else
                    try("cost slot", c.AddAuraSlot, c, key, s[2], {
                        candidateFilters = { includeSpellIDs = s[3] },
                        initializeFrame = indButton(10, nil, { 1, 0.15, 0.15 }, tile),
                    })
                end
                try("cost SetUnit", c.SetUnit, c, unit)
                try("cost UpdateAllAuras", c.UpdateAllAuras, c)
            end
        end
    end
    local ms = debugprofilestop() - t0
    collectgarbage("collect")
    P.indCost = root
    say(string.format("cost: 40 tiles x 4 containers in %.1f ms, %d buttons, Lua heap +%.0f KB (now /fp raid fps)",
        ms, (P.indInits or 0) - inits0, collectgarbage("count") - kb0))
end

local function indIds()
    for _, fam in ipairs(FAMILIES) do
        local parts = {}
        for i = 2, #fam do
            local id = fam[i]
            local okS, sub = pcall(C_Spell.GetSpellSubtext, id)
            parts[#parts + 1] = string.format("%d=%s%s", id, show(spellName(id)),
                (okS and type(sub) == "string" and sub ~= "") and (" (" .. sub .. ")") or "")
        end
        say(fam[1] .. ": " .. table.concat(parts, ", "))
    end
end

local function indicators(arg)
    local sub, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if sub == "src" then indSources(rest ~= "" and rest or P.indUnit)
    elseif sub == "state" then
        indState()
        indSources(P.indUnit)
    elseif sub == "reconf" then
        if InCombatLockdown() then say("out of combat only") return end
        indReconf()
    elseif sub == "cost" then indCost()
    elseif sub == "ids" then indIds()
    else indPanel(sub ~= "" and sub or "player") end
end

--------------------------------------------------------------------------------
-- Commands: /fp raid <command> (/fp raid alone lists them)
--------------------------------------------------------------------------------

local function outOfCombat()
    if InCombatLockdown() then say("out of combat only") return false end
    return true
end

local COMMANDS = {
    { "build", build, "5 party + 40 raid secure tiles, click bindings, dispel box, debuff row" },
    { "header", header, "a SecureGroupHeaderTemplate with no initialConfigFunction (again: list children)" },
    { "secrets", secrets, "secrecy of group-unit values, range, roster (run in and out of combat)" },
    { "auras", auras, "[unit] read debuffs out of combat (HARMFUL vs HARMFUL|RAID)" },
    { "watch", function() P.watch = not P.watch; say("watch " .. (P.watch and "on" or "off")) end,
        "toggle UNIT_AURA payload and range event logging" },
    { "spell", function(arg)
        if not outOfCombat() then return end
        P.spell = tonumber(arg)
        say("test spell: " .. show(P.spell) .. " " .. show(P.spell and spellName(P.spell)))
        for unit, t in pairs(tiles) do applyBindings(t, unit) end
        for _, c in ipairs(P.headerChildren or {}) do applyBindings(c, nil) end
    end, "<id> the test spell for the tile bindings (rebinds out of combat)" },
    { "clear", function()
        if not outOfCombat() then return end
        for _, t in pairs(tiles) do t:SetAttribute("shift-type1", nil); t:SetAttribute("shift-spell1", nil) end
        for _, c in ipairs(P.headerChildren or {}) do c:SetAttribute("shift-type1", nil); c:SetAttribute("shift-spell1", nil) end
        say("cleared shift-type1/shift-spell1")
    end, "remove shift-type1/shift-spell1 from every tile (does shift-left fall back?)" },
    { "sound", sound, "play the addon's ogg and a sound kit" },
    { "aurasound", auraSound, "[spellID|clear] try C_UnitAuras.AddAuraSound shapes on every group unit" },
    { "hide", hide, "hide Blizzard's compact party/raid frames by reparenting" },
    { "fps", fps, "5 s frame-time sample" },
    { "spec", spec, "what the spec/talent APIs return (role source for per-role settings)" },
    { "ranks", ranks, "<id> can a lower rank be pinned (keys 0 / ALT-0 at your target), and how are ranks found" },
    { "longmacro", longMacro, "CTRL-0 runs a >255-character macro whose last line casts on you" },
    { "traits", function(arg) P.traitNodes = arg == "nodes"; traits() end,
        "[nodes] how the talent trees are laid out in the trait system (nodes: every talent)" },
    { "selfcast", selfCast, "[none|alt] show the self-cast modifier; none/alt changes it (a global setting)" },
    { "mocast", mouseoverCast, "[on|off] the client's mouseover cast: support and CVars" },
    { "hoverkeys", hoverKeys, "toggle: hovering a tile binds key 8 to cast the test spell on it" },
    { "permkey", permKey,
        "[fallback|group] toggle: key 9 casts on @mouseover (fallback: else action button 9; group: group members only)" },
    { "hoverkey", hoverKeyState, "GlassRaidFrames' hover keys: live binding, macro, and a log line per press" },
    { "enums", function()
        enumKeys("Enum.CustomAuraButtonDispelTypeTextureStyle", Enum.CustomAuraButtonDispelTypeTextureStyle)
        enumKeys("Enum.UnitAuraSoundTrigger", Enum.UnitAuraSoundTrigger)
        enumKeys("Enum.LuaCurveType", Enum.LuaCurveType)
    end, "dump the enums the dispel box relies on" },
    { "ind", indicators, "[unit|state|src [unit]|reconf|cost|ids] indicator test panel (Renew, Shield, Weakened Soul); "
        .. "state: which rows are lit; src: each aura's id, source and filters; reconf: change a slot live; "
        .. "cost: 40 tiles x the default indicators (then /fp raid fps); ids: names and ranks of the default spell IDs" },
    { "log", function(arg)
        if arg ~= "clear" then say("usage: /fp raid log clear") return end
        Probe:ClearLog()   -- empties RaidProbeDB.log in place (the host holds it by reference)
        say("log cleared")
    end, "clear - empty RaidProbeDB.log" },
}
for _, c in ipairs(COMMANDS) do
    local fn = c[2]
    -- The host passes the rest of the line; the probe's functions took it trimmed.
    Probe:Command(c[1], function(args) fn(((args or ""):gsub("^%s+", ""):gsub("%s+$", ""))) end, c[3])
end

-- Seam for tests/test_probe.lua: file-local state and the hover-key toggle.
NS._test = { Probe = Probe, P = P, order = order, hoverKeys = hoverKeys, HOVER_KEY = HOVER_KEY, indButton = indButton,
              worldSetup = worldSetup, worldCheck = worldCheck }
