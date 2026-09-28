-- RaidProbe: the throwaway measurement addon for GlassRaidFrames, milestone 0.
-- It answers the questions the plan leaves open before any real frame code
-- is written. Every line it prints also goes to RaidProbeDB.log (SavedVariables),
-- so a full client exit leaves the whole session on disk for review.
--
-- What it measures (the numbers match the plan's probe items):
--   1. manual party1-4/raid1-40 buttons vs SecureGroupHeaderTemplate, through
--      roster changes in and out of combat          /rprobe build, /rprobe header
--   2. click-cast attribute forms on SecureUnitButtonTemplate  (click the tiles)
--   3. the dispel box: a secure button over an AuraContainer   (the corner box)
--   4. C_UnitAuras.AddAuraSound                               /rprobe aurasound
--   5. secrecy of group-unit values, range                    /rprobe secrets
--   6. hiding Blizzard's compact frames                       /rprobe hide
--   7. the cost of 45 tiles x 2 containers                    /rprobe fps
--
-- Every client call that may be missing or throw goes through try(), so one
-- refusal cannot stop the rest of the probe.

local ADDON = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local SOUND = MEDIA .. "dispel.ogg"
local MAX_LOG = 3000

local P = {}                 -- probe state
local tiles = {}             -- unit -> tile (manual build)
local order = {}             -- tiles in build order
local applyMode              -- defined with the events, used by build()

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

local function stamp()
    local t = GetTime and GetTime() or 0
    return string.format("%.1f%s", t, InCombatLockdown() and " C" or "")
end

local function say(msg)
    msg = tostring(msg)
    print("|cff7fd4ffRaidProbe|r " .. msg)
    if type(RaidProbeDB) == "table" and type(RaidProbeDB.log) == "table" then
        local log = RaidProbeDB.log
        log[#log + 1] = stamp() .. " " .. msg
        if #log > MAX_LOG then table.remove(log, 1) end
    end
end

-- Describe a value without ever operating on a secret one.
local function show(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if v == nil then return "nil" end
    return tostring(v)
end

local function try(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then say("|cffff6060FAIL|r " .. label .. ": " .. tostring(a)) end
    return ok, a, b, c, d
end

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
local function applyBindings(b, unit)
    local id = testSpell()
    local name = id and spellName(id)
    b:SetAttribute("unit", unit)
    b:SetAttribute("type1", "target")
    b:SetAttribute("type2", "togglemenu")
    if not name then return end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
    local ranked = (ok and type(sub) == "string" and sub ~= "") and (name .. "(" .. sub .. ")") or name
    b:SetAttribute("shift-type1", "spell"); b:SetAttribute("shift-spell1", name)       -- bare name
    b:SetAttribute("ctrl-type1", "spell");  b:SetAttribute("ctrl-spell1", id)          -- numeric ID
    b:SetAttribute("alt-type1", "spell");   b:SetAttribute("alt-spell1", ranked)       -- rank-qualified
    b:SetAttribute("shift-type2", "macro")                                              -- macro fallback
    b:SetAttribute("shift-macrotext2", "/cast [@" .. unit .. "] " .. name)
    b:SetAttribute("*type3", "spell");      b:SetAttribute("*spell3", name)            -- wildcard
end

local BINDING_HELP = {
    "left: target | right: menu",
    "shift-left: spell by name | ctrl-left: spell by ID | alt-left: spell 'Name(Rank n)'",
    "shift-right: /cast macro | middle (any modifier): *spell3 wildcard",
    "corner box: left/right/middle = cure slot 1/2/3",
}

-- What the secure handler resolved for this click, read back insecurely.
local function postClick(self, mouse)
    local get = SecureButton_GetModifiedAttribute
    local kind = get and get(self, "type", mouse)
    local what = kind == "spell" and get(self, "spell", mouse)
        or kind == "macro" and get(self, "macrotext", mouse) or ""
    say(string.format("click %s %s%s%s%s -> %s %s", show(self:GetAttribute("unit")),
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
    box:SetAttribute("unit", unit)
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
    try("box SetUnit", c.SetUnit, c, unit)
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
    P.party:SetPoint("LEFT", UIParent, "LEFT", 40, 60)
    P.raid = CreateFrame("Frame", "RaidProbeRaid", UIParent)
    P.raid:SetSize(8 * (TILE_W + GAP), 5 * (TILE_H + GAP))
    P.raid:SetPoint("LEFT", UIParent, "LEFT", 140, 60)
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
    say("header child unit -> " .. show(value))
    -- A header moves tokens between its children, in combat too, so a child's
    -- aura container must follow: does SetUnit work on a secure child in combat?
    if self.rowContainer and value then
        local ok, err = pcall(self.rowContainer.SetUnit, self.rowContainer, value)
        local okU, errU = pcall(self.rowContainer.UpdateAllAuras, self.rowContainer)
        say("  container SetUnit " .. show(value) .. ": " .. (ok and "ok" or tostring(err))
            .. ", UpdateAllAuras: " .. (okU and "ok" or tostring(errU)))
    end
end

local function headerReport()
    local h = P.header
    if not h then say("no header: /rprobe header") return end
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
    h:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
    P.header = h
    -- Precreate all 40 children out of combat (Cell's trick): a child the
    -- header would otherwise create mid-combat could not be configured.
    h:SetAttribute("startingIndex", -39)
    local shown = try("header Show", h.Show, h)
    h:SetAttribute("startingIndex", 1)
    local n = 0
    while h:GetAttribute("child" .. (n + 1)) do
        n = n + 1
        local child = h:GetAttribute("child" .. n)
        child:HookScript("PostClick", postClick)
        buildDebuffRow(child, child:GetAttribute("unit") or "player")
    end
    say("header created (shown call ok=" .. show(shown) .. "), " .. n .. " children precreated, each with a debuff row")
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
local function hoverKeys()
    if InCombatLockdown() then say("out of combat only") return end
    P.hover = not P.hover
    local name = spellName(testSpell() or 0)
    for _, t in ipairs(order) do
        t:SetAttribute("type-key8", name and "spell" or nil)
        t:SetAttribute("spell-key8", name)
        if not t.hoverHooked then
            t:HookScript("OnEnter", function(self)
                if not P.hover then return end
                local okB, err = pcall(SetOverrideBindingClick, self, true, HOVER_KEY, self:GetName(), "key8")
                say("OnEnter bind " .. HOVER_KEY .. " -> " .. self.unit .. ": " .. (okB and "ok" or tostring(err)))
            end)
            t:HookScript("OnLeave", function(self)
                if not P.hover then return end
                local okC, err = pcall(ClearOverrideBindings, self)
                if not okC then say("OnLeave clear: " .. tostring(err)) end
            end)
            t.hoverHooked = true
        end
    end
    say("hover keys " .. (P.hover and "on" or "off") .. ": hover a tile and press " .. HOVER_KEY
        .. " (casts " .. show(name) .. "), out of combat, then in combat")
end

-- c. A permanent binding: key "9" -> a hidden secure action button whose
-- macro casts on the mouseover unit, rank-qualified if the client allows.
local PERM_KEY = "9"
local function permKey()
    if InCombatLockdown() then say("out of combat only") return end
    if P.perm then
        ClearOverrideBindings(P.perm)
        P.perm = nil
        say("permanent key " .. PERM_KEY .. " released")
        return
    end
    local id = testSpell()
    local name = id and spellName(id)
    if not name then say("no test spell: /rprobe spell <id>") return end
    local b = CreateFrame("Button", "RaidProbeMouseoverKey", UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")   -- both edges: the template acts on one (measured)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/cast [@mouseover,help,nodead] " .. name)
    b:SetScript("PostClick", function() say("perm key " .. PERM_KEY .. " clicked (mouseover=" .. show(UnitExists("mouseover")) .. ")") end)
    local ok, err = pcall(SetOverrideBindingClick, b, true, PERM_KEY, b:GetName())
    say("permanent key " .. PERM_KEY .. " -> /cast [@mouseover,help,nodead] " .. name .. ": " .. (ok and "ok" or tostring(err)))
    P.perm = b
end

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
        if type(RaidProbeDB) ~= "table" then RaidProbeDB = {} end
        RaidProbeDB.log = RaidProbeDB.log or {}
        RaidProbeDB.sessions = (RaidProbeDB.sessions or 0) + 1
        say("session " .. RaidProbeDB.sessions .. ", build " .. table.concat({ GetBuildInfo() }, " ", 1, 2)
            .. ", log " .. #RaidProbeDB.log .. " lines. /rprobe help")
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
        say(string.format("cast sent: target=%s spell=%s", show(a2), show(a4)))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        say("cast succeeded: spell=" .. show(a3))
    elseif event == "UNIT_SPELLCAST_FAILED" then
        say("cast failed: spell=" .. show(a3))
    elseif event == "UNIT_AURA" then
        if P.watch and tiles[a1] then
            local okF, full = pcall(function() return a2 and a2.isFullUpdate end)
            say(string.format("UNIT_AURA %s payload %s", a1,
                okF and ("readable full=" .. show(full)) or "secret"))
        end
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        if P.watch then say(string.format("UNIT_IN_RANGE_UPDATE %s -> %s", show(a1), show(a2))) end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        say(string.format("|cffff6060%s|r %s %s", event, show(a1), show(a2)))
    elseif event == "PLAYER_REGEN_DISABLED" then
        say("combat starts")
    elseif event == "PLAYER_REGEN_ENABLED" then
        say("combat ends")
        applyMode()
        C_Timer.After(0.3, rosterLog)
    end
end)
for _, e in ipairs({ "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE",
    "UNIT_CONNECTION", "UNIT_AURA", "UNIT_IN_RANGE_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    local ok, r = pcall(ev.RegisterEvent, ev, e)
    if not ok or r == false then print("RaidProbe could not register " .. e .. ": " .. tostring(r)) end
end
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }) do
    local ok, r = pcall(ev.RegisterUnitEvent, ev, e, "player")
    if not ok or r == false then print("RaidProbe could not register " .. e .. ": " .. tostring(r)) end
end

--------------------------------------------------------------------------------
-- /rprobe
--------------------------------------------------------------------------------

local HELP = {
    "build - 5 party + 40 raid secure tiles, click bindings, dispel box, debuff row",
    "header - a SecureGroupHeaderTemplate with no initialConfigFunction (again: list children)",
    "secrets - secrecy of group-unit values, range, roster (run in and out of combat)",
    "auras [unit] - read debuffs out of combat (HARMFUL vs HARMFUL|RAID)",
    "watch - toggle UNIT_AURA payload and range event logging",
    "spell <id> - the test spell for the tile bindings (rebinds out of combat)",
    "clear - remove shift-type1/shift-spell1 from every tile (does shift-left fall back?)",
    "sound - play the addon's ogg and a sound kit",
    "aurasound [spellID|clear] - try C_UnitAuras.AddAuraSound shapes on every group unit",
    "hide - hide Blizzard's compact party/raid frames by reparenting",
    "fps - 5 s frame-time sample",
    "mocast [on|off] - the client's mouseover cast: support and CVars",
    "hoverkeys - toggle: hovering a tile binds key 8 to cast the test spell on it",
    "permkey - toggle: key 9 always casts the test spell on @mouseover",
    "enums - dump the enums the dispel box relies on",
    "log clear - empty RaidProbeDB.log",
}

SLASH_RAIDPROBE1 = "/rprobe"
SlashCmdList.RAIDPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "build" then build()
    elseif cmd == "header" then header()
    elseif cmd == "secrets" then secrets()
    elseif cmd == "auras" then auras(arg)
    elseif cmd == "watch" then P.watch = not P.watch; say("watch " .. (P.watch and "on" or "off"))
    elseif cmd == "spell" then
        if InCombatLockdown() then say("out of combat only") return end
        P.spell = tonumber(arg)
        say("test spell: " .. show(P.spell) .. " " .. show(P.spell and spellName(P.spell)))
        for unit, t in pairs(tiles) do applyBindings(t, unit) end
    elseif cmd == "clear" then
        if InCombatLockdown() then say("out of combat only") return end
        for _, t in pairs(tiles) do t:SetAttribute("shift-type1", nil); t:SetAttribute("shift-spell1", nil) end
        say("cleared shift-type1/shift-spell1")
    elseif cmd == "sound" then sound()
    elseif cmd == "aurasound" then auraSound(arg)
    elseif cmd == "hide" then hide()
    elseif cmd == "fps" then fps()
    elseif cmd == "mocast" then mouseoverCast(arg)
    elseif cmd == "hoverkeys" then hoverKeys()
    elseif cmd == "permkey" then permKey()
    elseif cmd == "enums" then
        enumKeys("Enum.CustomAuraButtonDispelTypeTextureStyle", Enum.CustomAuraButtonDispelTypeTextureStyle)
        enumKeys("Enum.UnitAuraSoundTrigger", Enum.UnitAuraSoundTrigger)
        enumKeys("Enum.LuaCurveType", Enum.LuaCurveType)
    elseif cmd == "log" and arg == "clear" then
        RaidProbeDB.log = {}
        say("log cleared")
    else
        for _, line in ipairs(HELP) do say("/rprobe " .. line) end
    end
end
