-- Movers.lua: unlock mode (/grf unlock|lock|reset) for the group grid.
--
-- One plain, insecure mover covering the whole grid, anchored TO the
-- container, never the reverse (a frame a protected frame anchors to becomes
-- protected). Dragging moves the mover; the container follows through
-- Header.SetPosition, out of combat only. Nothing starts the client's own drag
-- on a protected frame. Unlocking is refused in combat, and combat locks.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Glass, Header = GRF.API, GRF.Glass, GRF.Header
local Movers = {}
GRF.Movers = Movers

local mover

local function round(v) return math.floor(v + 0.5) end

-- The mover's centre as an offset from UIParent's centre (both in UIParent space).
local function moverOffset()
    local mx, my = mover:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (mx and ux) then return nil end
    return round(mx - ux), round(my - uy)
end

local function follow(save)
    local x, y = moverOffset()
    if x then Header.SetPosition(x, y, save) end
end

local function reattach()
    mover:ClearAllPoints()
    mover:SetAllPoints(Header.container)
end

local function build()
    mover = CreateFrame("Frame", "GlassRaidFramesMover", UIParent)
    mover:SetSize(Header.Size())      -- an explicit rect: a drag's re-anchoring can't collapse it
    mover:SetDontSavePosition(true)   -- our saved position is the only one
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(mover)
    fill:SetColorTexture(0.5, 0.83, 1, 0.18)
    local label = Glass.Font(mover, 12, "CENTER")
    label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    label:SetText("Glass Raid Frames\ndrag to move, right-click to lock")
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self.dragging = true
        self:StartMoving()
    end)
    mover:SetScript("OnUpdate", function(self)
        if self.dragging then follow(false) end
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = false
        follow(true)
        reattach()
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Movers.Lock() end
    end)
    mover:Hide()
end

function Movers.Unlock()
    if not Header.container then return false end
    if InCombatLockdown() then
        API.Print("can't unlock in combat")
        return false
    end
    if not mover then build() end
    reattach()
    mover:Show()
    return true
end

function Movers.Lock()
    if not mover then return end
    if mover.dragging then
        mover:StopMovingOrSizing()
        mover.dragging = false
        -- The grid already followed the drag: keep and save where it is.
        -- (Combat locks on PLAYER_REGEN_DISABLED, before lockdown applies.)
        follow(true)
        reattach()
    end
    mover:Hide()
end

function Movers.IsUnlocked()
    return mover ~= nil and mover:IsShown()
end

-- Back to the default spot, forgetting the saved one. Out of combat.
function Movers.Reset()
    if InCombatLockdown() then return false end
    if GRF.db then GRF.db.pos = nil end
    return Header.SetPosition(Header.DEFAULT_POS.x, Header.DEFAULT_POS.y, false)
end

-- Combat starting mid-drag: stop, and stay where the last out-of-combat
-- position put the grid.
function Movers.OnCombat()
    Movers.Lock()
end

Movers._test = { mover = function() return mover end }
