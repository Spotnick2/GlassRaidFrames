-- Indicators.lua: buffs and debuffs on each tile (#19), drawn by Blizzard's
-- managed aura container (CustomAuraContainerTemplate from
-- Blizzard_AuraContainer). The client picks and draws the auras, so their
-- data (secret in combat for the whole group) never reaches Lua.
--
-- The setup is account-wide, per class (GlassRaidFramesDB.indicators[class]),
-- seeded from IndicatorDefaults.lua. Kinds:
-- - icons:   one fixed spot per spell (Renew always in the corner, Shield next
--            to it). One aura SLOT per spell: 1 button each. A collapsing row
--            would be a GROUP, 10 buttons per tile (#21);
-- - icon:    one spot showing the first spell present in list order (slots
--            stacked, the earlier spell on a higher frame level);
-- - square:  the same, a coloured square instead of the icon;
-- - debuffs: the built-in row of every debuff (a group, as the tile always had).
--
-- What the probe measured (docs/FOREVER-PROBE.md item 10):
-- - only mine = the PLAYER filter token; specific spells = includeSpellIDs
--   with every rank. Vanilla HoTs don't carry RAID_IN_COMBAT, so a spell
--   list is required;
-- - a debuff on a group member can't be matched by ID unless the spell is
--   NeverSecret (Weakened Soul is ContextuallySecret): such an indicator is
--   reported unsupported and not built;
-- - slots and their filters, enable state and size change live out of
--   combat; the buttons are locked (and their shown state secret) otherwise.
-- And the rules from the first debuff row: declare groups and slots BEFORE
-- SetUnit, then UpdateAllAuras; a header child's unit changes in combat
-- (SetUnit + UpdateAllAuras works there); nothing is anchored TO a container;
-- the buttons are styled only from initializeFrame and our own regions, never
-- scripted, and don't take the mouse, so clicks still reach the tile.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Glass, D = GRF.API, GRF.Glass, GRF.IndicatorDefaults
local Ind = {}
GRF.Indicators = Ind

Ind.KINDS = { icons = true, icon = true, square = true, debuffs = true }
Ind.ANCHORS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
                BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
Ind.GROW = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
Ind.GAP = 2
Ind.LEVEL = 12          -- over the glass rim (+10), as the debuff row always was
Ind.BAND = 10           -- frame levels per stacked slot: covers its cooldown and texts
Ind.MAX_SPELLS = 12
Ind.MIN_SIZE, Ind.MAX_SIZE = 6, 32
Ind.MAX_DEBUFFS = 10
Ind.OFFSET = 200        -- |x|, |y| bound

-- Call obj:method(...); a missing method or a throw is recorded, never raised.
local function try(key, obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then
        API.Fail(key, "missing method " .. method)
        return false
    end
    local ok, err = pcall(fn, obj, ...)
    if not ok then API.Fail(key, err) end
    return ok, err
end

local loaded = false
local function ensureLoaded()
    if loaded then return end
    loaded = true
    local ok, why = API.LoadBlizzardAddOn("Blizzard_AuraContainer")
    if not ok then API.Fail("aura load", why) end   -- keep going: the type may exist anyway
end

--------------------------------------------------------------------------------
-- The saved setup
--------------------------------------------------------------------------------

local function num(v, lo, hi, default)
    if type(v) ~= "number" or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end

-- Fix one saved indicator in place; false = drop it. Saved data may come from
-- an older version or a hand edit: nothing may be trusted to have survived.
local function valid(ind, seen)
    if type(ind) ~= "table" or type(ind.key) ~= "string" or ind.key == "" or seen[ind.key] then return false end
    if not Ind.KINDS[ind.kind] then return false end
    if (ind.kind == "debuffs") ~= (ind.builtin == true) then return false end
    seen[ind.key] = true
    if type(ind.name) ~= "string" or ind.name == "" then ind.name = ind.key end
    ind.enabled = ind.enabled ~= false
    if not Ind.ANCHORS[ind.anchor] then ind.anchor = "TOPLEFT" end
    ind.x = num(ind.x, -Ind.OFFSET, Ind.OFFSET, 0)
    ind.y = num(ind.y, -Ind.OFFSET, Ind.OFFSET, 0)
    ind.size = math.floor(num(ind.size, Ind.MIN_SIZE, Ind.MAX_SIZE, 12))
    if ind.kind == "debuffs" then
        if ind.filter ~= "dispellable" then ind.filter = "all" end
        ind.max = math.floor(num(ind.max, 1, Ind.MAX_DEBUFFS, 3))
        return true
    end
    if ind.aura ~= "HARMFUL" then ind.aura = "HELPFUL" end
    ind.mine = ind.mine == true
    if not Ind.GROW[ind.grow] then ind.grow = "LEFT" end
    ind.swipe = ind.swipe ~= false
    ind.timer = ind.timer == true
    if type(ind.color) ~= "table" then ind.color = { 1, 0.2, 0.2 } end
    for i = 1, 3 do ind.color[i] = num(ind.color[i], 0, 1, 1) end
    local spells, used = {}, {}
    for _, id in ipairs(type(ind.spells) == "table" and ind.spells or {}) do
        if type(id) == "number" and id > 0 and id == math.floor(id) and not used[id] and #spells < Ind.MAX_SPELLS then
            spells[#spells + 1], used[id] = id, true
        end
    end
    ind.spells = spells   -- an emptied list stays empty (it simply shows nothing)
    return true
end

local function playerClass()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and type(class) == "string" and not API.IsSecret(class) then return class end
    return nil
end

local checked = {}   -- class -> true once validated this session
local classless      -- the shared defaults, unsaved, while the class is unknown

-- The current class's indicator list (seeded from the defaults the first
-- time this class logs in, validated once per session). Before the saved
-- variables exist or while the class can't be read: the class-less defaults
-- (the debuff row never depends on it), not saved.
function Ind.Setup()
    local db, class = GRF.db, playerClass()
    if not (db and class) then
        classless = classless or D.For(nil)
        return classless
    end
    if type(db.indicators) ~= "table" then db.indicators = {} end
    local entry = db.indicators[class]
    if type(entry) ~= "table" or type(entry.list) ~= "table" then
        entry = { version = 1, list = D.For(class) }
        db.indicators[class] = entry
    end
    if not checked[class] then
        local kept, seen, hasDebuffs = {}, {}, false
        for _, ind in ipairs(entry.list) do
            if valid(ind, seen) then
                kept[#kept + 1] = ind
                hasDebuffs = hasDebuffs or ind.kind == "debuffs"
            end
        end
        if not hasDebuffs then kept[#kept + 1] = D.Debuffs() end   -- the built-in row can't be lost
        entry.list, checked[class] = kept, true
    end
    return entry.list
end

-- Back to the class defaults.
function Ind.Reset()
    local class = playerClass()
    if not (GRF.db and class) then return false end
    if type(GRF.db.indicators) ~= "table" then GRF.db.indicators = {} end
    GRF.db.indicators[class] = { version = 1, list = D.For(class) }
    Ind.Request()
    return true
end

--------------------------------------------------------------------------------
-- What an indicator matches
--------------------------------------------------------------------------------

-- Every rank to match for a stored spell: the built-in family, else the ranks
-- this character has learned (spellbook, by the client's own name), plus the
-- stored ID itself.
function Ind.Family(id)
    local fam = D.FAMILIES[id]
    if fam then return fam end
    local out, seen = { id }, { [id] = true }
    for _, r in ipairs(API.Ranks(id)) do
        if not seen[r] then out[#out + 1], seen[r] = r, true end
    end
    return out
end

local function idSet(id)
    local set = {}
    for _, r in ipairs(Ind.Family(id)) do set[r] = true end
    return set
end

local function neverSecret(id)
    local S = rawget(_G, "C_Secrets")
    local level = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret
    if not (S and S.GetSpellAuraSecrecy and level) then return false end
    local ok, v = pcall(S.GetSpellAuraSecrecy, id)
    return ok and not API.IsSecret(v) and v == level
end

-- Can this indicator be built on this client? (false, why) when not.
function Ind.Supported(ind)
    if ind.kind == "debuffs" then return true end
    if #ind.spells == 0 then return false, "no spells" end
    if ind.aura == "HARMFUL" then
        for _, id in ipairs(ind.spells) do
            if not neverSecret(id) then
                return false, "debuffs on group members can't be tracked by spell on this client"
            end
        end
    end
    return true
end

function Ind.Filter(ind)
    if ind.kind == "debuffs" then return ind.filter == "dispellable" and "HARMFUL|RAID" or "HARMFUL" end
    return ind.aura .. (ind.mine and "|PLAYER" or "")
end

--------------------------------------------------------------------------------
-- Buttons: every region made once in initializeFrame (the client locks the
-- button afterwards), then only sized, placed, coloured and toggled.
--------------------------------------------------------------------------------

local function fontFile()
    local f = Glass.FONTS[Glass.fontKey] or Glass.FONTS.arial
    return f.file
end

local function makeRegions(ab, square)
    ab:EnableMouse(false)
    local r = {}
    r.back = ab:CreateTexture(nil, "BACKGROUND")
    r.back:SetAllPoints(ab)
    r.back:SetColorTexture(0, 0, 0, 0.8)
    r.art = ab:CreateTexture(nil, "ARTWORK")
    r.art:SetPoint("TOPLEFT", ab, "TOPLEFT", 1, -1)
    r.art:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -1, 1)
    if square then
        r.art:SetColorTexture(1, 1, 1, 1)
    else
        r.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        try("aura icon", ab, "SetIcon", r.art)
    end
    local okCd, cd = pcall(CreateFrame, "Cooldown", nil, ab, "CooldownFrameTemplate")
    if okCd and cd then
        cd:SetAllPoints(ab)
        pcall(cd.SetReverse, cd, true)
        pcall(cd.SetHideCountdownNumbers, cd, true)
        try("aura swipe", ab, "SetDurationCooldown", cd)
        r.cd = cd
    end
    local top = CreateFrame("Frame", nil, ab)
    top:SetAllPoints(ab)
    top:SetFrameLevel(ab:GetFrameLevel() + 5)
    r.timer = top:CreateFontString(nil, "OVERLAY")
    r.timer:SetPoint("CENTER", ab, "CENTER", 0, 0)
    r.timer:SetFont(fontFile(), 8, "OUTLINE")
    try("aura timer", ab, "SetDurationText", r.timer, {})
    r.count = top:CreateFontString(nil, "OVERLAY")
    r.count:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", 1, -1)
    r.count:SetFont(fontFile(), 8, "OUTLINE")
    try("aura stacks", ab, "SetApplicationCount", r.count, {})
    ab.grf = r
end

-- Size, place, stack and colour slot button i of entry e on tile b.
local function styleSlot(b, e, i, ab)
    local ind, r = e.ind, ab and ab.grf
    if not r then return end
    local s = ind.size
    ab:SetSize(s, s)
    local dx, dy = 0, 0
    if ind.kind == "icons" then
        local g = Ind.GROW[ind.grow]
        dx, dy = g[1] * (i - 1) * (s + Ind.GAP), g[2] * (i - 1) * (s + Ind.GAP)
    end
    ab:ClearAllPoints()
    ab:SetPoint(ind.anchor, b.body, ind.anchor, ind.x + dx, ind.y + dy)
    local base = b.body:GetFrameLevel() + Ind.LEVEL
    if ind.kind == "icons" then
        ab:SetFrameLevel(base + 1)
    else
        ab:SetFrameLevel(base + (#ind.spells - i + 1) * Ind.BAND)   -- the first spell on top
    end
    if r.cd then pcall(r.cd.SetDrawSwipe, r.cd, ind.swipe) end
    r.timer:SetShown(ind.timer)
    local fs = math.max(6, math.floor(s * 0.6 + 0.5))
    r.timer:SetFont(fontFile(), fs, "OUTLINE")
    r.count:SetFont(fontFile(), fs, "OUTLINE")
    if ind.kind == "square" then r.art:SetVertexColor(ind.color[1], ind.color[2], ind.color[3], 1) end
end

local function styleDebuffButton(ab, size)
    ab:SetSize(size, size)
end

--------------------------------------------------------------------------------
-- Per tile: one container per indicator, kept per key; a deleted indicator's
-- container goes to a pool and is reused by the next one of its kind, so
-- edits never pile up new containers.
--------------------------------------------------------------------------------

local function bind(e, unit)
    if not unit then return end
    try("aura unit", e.c, "SetUnit", unit)
    try("aura refresh", e.c, "UpdateAllAuras")
end

local function newContainer(b, kind)
    ensureLoaded()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b.body, "CustomAuraContainerTemplate")
    if not ok or not c then
        API.Fail("aura container", c)
        return nil
    end
    c:SetFrameLevel(b.body:GetFrameLevel() + Ind.LEVEL)
    local e = { c = c, kind = kind, slots = 0, buttons = {}, sig = {} }
    if kind == "debuffs" then
        local added = try("aura group", c, "AddAuraGroup", "grf_debuffs", "HARMFUL", {
            maxFrameCount = 3,
            initializeFrame = function(ab)
                makeRegions(ab, false)
                styleDebuffButton(ab, e.ind and e.ind.size or 12)
                ab.grf.timer:Hide()   -- the row has no timer setting (the first buttons come before e.ind)
            end,
            candidateFilters = {},
            layout = { elementWidth = 12, elementHeight = 12, elementSpacing = Ind.GAP, lineSpacing = Ind.GAP },
        })
        if not added then
            c:Hide()
            return nil
        end
        e.filter, e.max, e.size = "HARMFUL", 3, 12
    else
        c:SetAllPoints(b.body)   -- the slots are placed by hand; the container just holds them
    end
    return e
end

-- Make entry e's container show indicator ind (e.ind is already ind).
local function updateSlots(b, e)
    local ind = e.ind
    local filter = Ind.Filter(ind)
    for i, id in ipairs(ind.spells) do
        local key = "s" .. i
        local sig = filter .. ":" .. table.concat(Ind.Family(id), ",")   -- a newly learned rank counts
        if i > e.slots then
            local slotIndex = i
            local added = try("aura slot", e.c, "AddAuraSlot", key, filter, {
                candidateFilters = { includeSpellIDs = idSet(id) },
                initializeFrame = function(ab)
                    makeRegions(ab, e.kind == "square")
                    e.buttons[slotIndex] = ab
                    styleSlot(b, e, slotIndex, ab)
                end,
            })
            if not added then return end
            e.slots, e.sig[i] = i, sig
        else
            if e.sig[i] ~= sig then
                try("aura slot filter", e.c, "SetAuraSlotFilterString", key, filter)
                try("aura slot spells", e.c, "SetAuraSlotCandidateFilters", key, { includeSpellIDs = idSet(id) })
                e.sig[i] = sig
            end
            if e.off and e.off[i] then
                try("aura slot on", e.c, "SetAuraSlotEnabled", key, true)
                e.off[i] = nil
            end
            styleSlot(b, e, i, e.buttons[i])
        end
    end
    -- Slots past the list (spells removed) stay, switched off, for reuse.
    for i = #ind.spells + 1, e.slots do
        e.off = e.off or {}
        if not e.off[i] then
            try("aura slot off", e.c, "SetAuraSlotEnabled", "s" .. i, false)
            e.off[i] = true
        end
    end
end

local function updateDebuffs(b, e)
    local ind, c = e.ind, e.c
    local filter = Ind.Filter(ind)
    if e.filter ~= filter then
        try("aura group filter", c, "SetAuraGroupFilterString", "grf_debuffs", filter)
        e.filter = filter
    end
    if e.max ~= ind.max then
        try("aura group max", c, "SetAuraGroupMaxFrameCount", "grf_debuffs", ind.max)
        e.max = ind.max
    end
    local s = ind.size
    if e.size ~= s then
        try("aura group layout", c, "SetAuraGroupLayout", "grf_debuffs",
            { elementWidth = s, elementHeight = s, elementSpacing = Ind.GAP, lineSpacing = Ind.GAP })
        local okN, n = pcall(c.GetAuraGroupFrameCount, c, "grf_debuffs")
        for i = 1, (okN and type(n) == "number") and n or 0 do
            local okF, ab = pcall(c.GetAuraGroupFrame, c, "grf_debuffs", i)
            if okF and ab then styleDebuffButton(ab, s) end
        end
        e.size = s
    end
    c:ClearAllPoints()
    c:SetSize(ind.max * s + (ind.max - 1) * Ind.GAP, s)
    c:SetPoint(ind.anchor, b.body, ind.anchor, ind.x, ind.y)
    -- The row grows away from its corner (the default is rightward from TOPLEFT).
    try("aura flow anchor", c, "SetFlowLayoutAnchorPoint", ind.anchor)
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    if dir then
        try("aura flow growth", c, "SetFlowLayoutGrowthDirection",
            ind.anchor:find("RIGHT") and dir.Left or dir.Right, ind.anchor:find("BOTTOM") and dir.Up or dir.Down)
    end
end

local function retire(st, key, e)
    if e.kind == "debuffs" then
        try("aura group off", e.c, "SetAuraGroupEnabled", "grf_debuffs", false)
    else
        for i = 1, e.slots do
            e.off = e.off or {}
            if not e.off[i] then
                try("aura slot off", e.c, "SetAuraSlotEnabled", "s" .. i, false)
                e.off[i] = true
            end
        end
    end
    e.c:Hide()
    st.byKey[key] = nil
    st.pool[e.kind] = st.pool[e.kind] or {}
    table.insert(st.pool[e.kind], e)
end

local function acquire(b, st, ind)
    local pool = st.pool[ind.kind]
    local e = pool and table.remove(pool)
    if e then
        e.c:Show()
        if e.kind == "debuffs" then try("aura group on", e.c, "SetAuraGroupEnabled", "grf_debuffs", true) end
    else
        e = newContainer(b, ind.kind)
        if not e then return nil end
    end
    e.fresh = true   -- (re)bound once its slots exist: a pooled one missed unit changes
    st.byKey[ind.key] = e
    return e
end

-- Bring tile b in line with the saved setup. Out of combat.
local function sync(b)
    local st = b.grfInd
    if not st then return end
    local want = {}
    for _, ind in ipairs(Ind.Setup() or {}) do
        if ind.enabled and (not b.isPet or ind.kind == "debuffs") and Ind.Supported(ind) then
            want[ind.key] = ind
        end
    end
    for key, e in pairs(st.byKey) do
        if not want[key] or want[key].kind ~= e.kind then retire(st, key, e) end
    end
    local unit = b:GetAttribute("unit")
    for key, ind in pairs(want) do
        local ok, err = pcall(function()
            local e = st.byKey[key] or acquire(b, st, ind)
            if not e then return end
            e.ind = ind
            if e.kind == "debuffs" then updateDebuffs(b, e) else updateSlots(b, e) end
            -- A new or reused container gets its unit after its slots and groups exist.
            if e.fresh then
                e.fresh = nil
                bind(e, unit)
            end
        end)
        if not ok then API.Fail("indicator " .. key, err) end
    end
end

-- Tile b (its insecure body), built out of combat by Frames.Setup.
function Ind.Attach(b)
    b.grfInd = { byKey = {}, pool = {} }
    local previous = b.onUnitChanged
    function b:onUnitChanged(unit)
        if previous then previous(self, unit) end
        for _, e in pairs(self.grfInd.byKey) do bind(e, unit) end
    end
    sync(b)
end

-- Every tile in line with the saved setup; one failing tile costs no other.
function Ind.Apply()
    if InCombatLockdown() then return false end
    for _, b in ipairs(GRF.Header.AllChildren()) do
        local ok, err = pcall(sync, b)
        if not ok then API.Fail("indicators", err) end
    end
    return true
end

-- Apply now, or when combat ends (the queued call reads the setup then).
function Ind.Request()
    GRF.WhenOutOfCombat("indicators", Ind.Apply, false)
end

-- New ranks learned (or lost): user-added spells expand to learned ranks.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function()
    API.ResetRanks()
    if GRF.Header and GRF.Header.container then Ind.Request() end
end)
-- PLAYER_ENTERING_WORLD: the class is surely known by then, if it wasn't at the build.
API.RegisterEvents(watcher, { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" })

Ind._test = { valid = valid, sync = sync, checked = checked }
