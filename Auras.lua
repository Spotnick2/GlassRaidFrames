-- Auras.lua: a row of debuff icons along each tile's bottom edge, drawn by
-- Blizzard's managed aura container (CustomAuraContainerTemplate from
-- Blizzard_AuraContainer). The client picks and draws the auras, so their
-- data (secret in combat for the whole group) never reaches Lua.
--
-- Rules measured in GlassUnitFrames and the probe (FOREVER-PROBE item 1):
-- - declare the aura group BEFORE SetUnit (binding first leaves UNIT_AURA
--   unregistered), then UpdateAllAuras;
-- - a header child's unit changes in combat: SetUnit + UpdateAllAuras on the
--   new unit works there;
-- - nothing is anchored TO a container (refused: UntrustedLayoutScriptExecution);
-- - the buttons are styled only in initializeFrame, never scripted, and do
--   not take the mouse, so a click on an icon still reaches the tile.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Glass = GRF.API, GRF.Glass
local Auras = {}
GRF.Auras = Auras

Auras.ICON, Auras.GAP, Auras.MAX = 12, 2, 3

-- Call obj:method(...); a missing method or a throw is recorded, never raised.
local function try(key, obj, method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then
        API.Fail(key, "missing method " .. method)
        return false
    end
    local ok, err = pcall(fn, obj, ...)
    if not ok then API.Fail(key, err) end
    return ok
end

local function styleButton(button)
    button:EnableMouse(false)
    button:SetSize(Auras.ICON, Auras.ICON)
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(button)
    back:SetColorTexture(0, 0, 0, 0.6)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    try("aura icon", button, "SetIcon", icon)
end

local loaded = false
local function ensureLoaded()
    if loaded then return end
    loaded = true
    local ok, why = API.LoadBlizzardAddOn("Blizzard_AuraContainer")
    if not ok then API.Fail("aura load", why) end   -- keep going: the type may exist anyway
end

-- The row on tile `b` (its insecure body), built out of combat.
function Auras.Attach(b)
    ensureLoaded()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b.body, "CustomAuraContainerTemplate")
    if not ok or not c then
        API.Fail("aura container", c)
        return
    end
    local inset = Glass.Inset("small")
    c:SetSize(Auras.MAX * Auras.ICON + (Auras.MAX - 1) * Auras.GAP, Auras.ICON)
    c:SetPoint("BOTTOMLEFT", b.body, "BOTTOMLEFT", inset + 1, inset + 1)
    c:SetFrameLevel(b.body:GetFrameLevel() + 12)   -- over the glass rim (+10)
    local added = try("aura group", c, "AddAuraGroup", "grf_debuffs", "HARMFUL", {
        maxFrameCount = Auras.MAX,
        initializeFrame = styleButton,
        candidateFilters = {},
        layout = { elementWidth = Auras.ICON, elementHeight = Auras.ICON,
                   elementSpacing = Auras.GAP, lineSpacing = Auras.GAP },
    })
    if not added then
        c:Hide()
        return
    end
    b.debuffs = c
    local previous = b.onUnitChanged
    function b:onUnitChanged(unit)
        if previous then previous(self, unit) end
        Auras.SetUnit(self, unit)
    end
end

function Auras.SetUnit(b, unit)
    local c = b.debuffs
    if not (c and unit) then return end
    try("aura unit", c, "SetUnit", unit)
    try("aura refresh", c, "UpdateAllAuras")
end
