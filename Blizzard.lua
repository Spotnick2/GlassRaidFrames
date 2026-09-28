-- Blizzard.lua: hide Blizzard's own party and raid frames.
--
-- Measured in the probe (FOREVER-PROBE item 6): all four exist and are
-- protected; reparenting them out of combat works and Edit Mode does not
-- bring them back. PartyFrame is the classic-style party display,
-- CompactPartyFrame the raid-style one ("Use Raid-Style Party Frames"), so
-- both go whichever the option picks.
--
-- The recipe is GlassUnitFrames' (measured on its unit frames): unregister the
-- frame's events so it stops updating, hide it, reparent it to a hidden frame.
-- Edit Mode calls SetParent on these frames; reparenting back INSIDE that call
-- runs in Blizzard's secure execution and taints secret-value reads for the
-- session (EllesmereUI's finding), so the repair is deferred to a timer, waits
-- while Edit Mode is open, and waits for combat to end if the frame is
-- protected. Hiding is one-way for a session: turning it off needs a /reload.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local Blizzard = {}
GRF.Blizzard = Blizzard

Blizzard.FRAMES = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" }
Blizzard.active = false   -- true once anything was hidden this session

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
Blizzard.hiddenParent = hiddenParent

local hooked, pending = {}, {}

local function editModeOpen()
    local em = rawget(_G, "EditModeManagerFrame")
    return em ~= nil and em:IsShown()
end

-- Run `fn` on `frame` once it is safe: never while Edit Mode is open (retry
-- every 0.25 s), never on a protected frame in combat (queued under `key`,
-- silent). Every retry re-checks both.
local function whenSafe(key, frame, fn)
    if editModeOpen() then
        C_Timer.After(0.25, function() whenSafe(key, frame, fn) end)
    elseif InCombatLockdown() and frame:IsProtected() then
        GRF.WhenOutOfCombat(key, function() whenSafe(key, frame, fn) end, false)
    else
        fn()
    end
end

-- Put `frame` back under the hidden parent, when it is safe to.
function Blizzard.Reparent(frame)
    pending[frame] = nil
    if frame:GetParent() == hiddenParent then return end
    pending[frame] = true
    whenSafe("blizzard:" .. tostring(frame:GetName()), frame, function()
        pending[frame] = nil
        if frame:GetParent() ~= hiddenParent then frame:SetParent(hiddenParent) end
    end)
end

-- Hide one Blizzard frame by global name. Out of combat.
function Blizzard.HideFrame(name)
    local frame = rawget(_G, name)   -- a Blizzard global may not exist on this client
    if not frame or hooked[frame] then return false end
    hooked[frame] = true
    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetParent(hiddenParent)
    -- Edit Mode (or anything else) reparenting it: undo that on a timer, never
    -- synchronously inside the caller's SetParent.
    hooksecurefunc(frame, "SetParent", function(self, parent)
        if parent ~= hiddenParent and not pending[self] then
            pending[self] = true
            C_Timer.After(0, function() Blizzard.Reparent(self) end)
        end
    end)
    Blizzard.active = true
    return true
end

function Blizzard.HideAll()
    for _, name in ipairs(Blizzard.FRAMES) do Blizzard.HideFrame(name) end
end
