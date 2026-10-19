-- Movers.lua: unlock mode (/grf unlock|lock|reset) for the group grid and
-- the pets.
--
-- One plain, insecure mover per block, anchored TO its
-- container, never the reverse (a frame a protected frame anchors to becomes
-- protected). Dragging moves the mover; the container follows through
-- Header.SetPosition, out of combat only. Nothing starts the client's own drag
-- on a protected frame. Unlocking is refused in combat, and combat locks.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Glass, Header = GRF.API, GRF.Glass, GRF.Header
local Movers = {}
GRF.Movers = Movers

-- One mover per movable block: the grid, and the pets (their own block since
-- #13's follow-up). spec = { name, label, target(), size(), set(x, y, save),
-- shown() }.
local movers = {}

local function round(v) return math.floor(v + 0.5) end

-- The mover's centre as an offset from UIParent's centre (both in UIParent space).
local function moverOffset(m)
    local mx, my = m:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (mx and ux) then return nil end
    return round(mx - ux), round(my - uy)
end

local function follow(m, save)
    local x, y = moverOffset(m)
    if x then m.spec.set(x, y, save) end
end

local function reattach(m)
    m:ClearAllPoints()
    m:SetSize(m.spec.size())   -- the block's size may have changed (resize)
    m:SetAllPoints(m.spec.target())
end

local function build(spec)
    local m = CreateFrame("Frame", spec.name, UIParent)
    m.spec = spec
    m:SetSize(spec.size())         -- an explicit rect: a drag's re-anchoring can't collapse it
    m:SetDontSavePosition(true)    -- our saved position is the only one
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    local fill = m:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(m)
    fill:SetColorTexture(0.5, 0.83, 1, 0.18)
    local label = Glass.Font(m, 12, "CENTER")
    label:SetPoint("CENTER", m, "CENTER", 0, 0)
    label:SetText(spec.label .. "\ndrag to move, right-click to lock")
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self.dragging = true
        self:StartMoving()
    end)
    m:SetScript("OnUpdate", function(self)
        if self.dragging then follow(self, false) end
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = false
        follow(self, true)
        reattach(self)
    end)
    m:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Movers.Lock() end
    end)
    m:Hide()
    return m
end

local SPECS = {
    { key = "grid", name = "GlassRaidFramesMover", label = "Glass Raid Frames",
      target = function() return Header.container end, size = function() return Header.Size() end,
      set = function(x, y, save) Header.SetPosition(x, y, save) end,
      shown = function() return true end },
    { key = "pets", name = "GlassRaidFramesPetMover", label = "Pets",
      target = function() return Header.petContainer end, size = function() return Header.PetSize() end,
      set = function(x, y, save) Header.SetPetPosition(x, y, save) end,
      shown = function() return Header.PetsMovable() end },
}

function Movers.Unlock()
    if not Header.container then return false end
    if InCombatLockdown() then
        API.Print("can't unlock in combat")
        return false
    end
    for _, spec in ipairs(SPECS) do
        local m = movers[spec.key]
        if spec.target() and spec.shown() then
            m = m or build(spec)
            movers[spec.key] = m
            reattach(m)
            m:Show()
        elseif m then
            m:Hide()
        end
    end
    return true
end

function Movers.Lock()
    for _, m in pairs(movers) do
        if m.dragging then
            m:StopMovingOrSizing()
            m.dragging = false
            -- The block already followed the drag: keep and save where it is.
            -- (Combat locks on PLAYER_REGEN_DISABLED, before lockdown applies.)
            follow(m, true)
            reattach(m)
        end
        m:Hide()
    end
end

function Movers.IsUnlocked()
    local m = movers.grid
    return m ~= nil and m:IsShown()
end

-- Forget `role`'s saved spots (default: the current role) for the grid and
-- the pets and, if that role is the one shown, move both back. Out of combat.
function Movers.Reset(role)
    if InCombatLockdown() then return false end
    role = role or GRF.role
    local prof = GRF.db and GRF.db.profiles and GRF.db.profiles[role]
    if prof then Header.ForgetPosition(prof) end
    if role ~= GRF.role then return true end   -- another role: nothing on screen moves
    local ok = Header.SetPosition(Header.DefaultPosition(role))
    Header.PlacePets()
    if ok and GRF.Announce then GRF.Announce() end
    return ok
end

-- Combat starting mid-drag: stop, and stay where the last out-of-combat
-- position put the block.
function Movers.OnCombat()
    Movers.Lock()
end

Movers._test = { mover = function() return movers.grid end, petMover = function() return movers.pets end }
