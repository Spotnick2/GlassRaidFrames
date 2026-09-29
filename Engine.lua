-- Engine.lua: decides WHO gets painted and WHEN. Owns nothing visual:
-- painters are registered per channel by Frames.lua.
--
-- Adapted from GlassUnitFrames' engine for header children, whose unit
-- changes (in combat too) as the roster moves:
-- - frames are mapped by their CURRENT unit; Engine.SetUnit moves a frame
--   when its header reassigns it, and repaints it in full;
-- - one event frame receives the unit events (RegisterEvent: tokens move
--   between frames, so per-token RegisterUnitEvent would need re-registering
--   on every roster change) and looks the unit up in the map;
-- - events mark channels dirty; one flush on the next rendered frame paints
--   each (frame, channel) once. Dedupe is by channel, never by comparing
--   values: those may be secret;
-- - one shared ticker refreshes range (UNIT_IN_RANGE_UPDATE was not
--   delivered in the probe, and UnitInRange is secret: FOREVER-PROBE item 5).

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
local Engine = {}
GRF.Engine = Engine

Engine.CHANNEL_EVENTS = {
    name       = { "UNIT_NAME_UPDATE" },
    health     = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" },
    power      = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" },
    indicators = {},   -- group-wide events only (below)
}
Engine.ORDER = { "name", "health", "power", "indicators", "target", "range" }
Engine.RANGE_INTERVAL = 0.25

local painters = {}
local framesByUnit = {}      -- unit -> { frame = true }
local frames = {}            -- every registered frame, in order
local eventChannels = {}     -- event -> { channel, ... }
local dirty = {}             -- frame -> { channel = true }

for channel, events in pairs(Engine.CHANNEL_EVENTS) do
    for _, e in ipairs(events) do
        eventChannels[e] = eventChannels[e] or {}
        table.insert(eventChannels[e], channel)
    end
end

function Engine.SetPainter(channel, fn)
    painters[channel] = fn
end

-- A painter that throws must not take the rest of the flush with it: record
-- the first error per channel and carry on.
local function paint(frame, channel)
    local fn = painters[channel]
    if not fn or not frame.unit then return end
    local ok, err = pcall(fn, frame, frame.unit)
    if not ok then API.Fail("painter " .. channel, err) end
end

-- One flush per rendered frame. Hidden (idle) until something is dirty.
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    local batch = dirty
    dirty = {}
    for frame, chans in pairs(batch) do
        for _, channel in ipairs(Engine.ORDER) do
            if chans[channel] then paint(frame, channel) end
        end
        frame.snap = nil
    end
end)

function Engine.MarkDirty(frame, channel)
    dirty[frame] = dirty[frame] or {}
    dirty[frame][channel] = true
    flusher:Show()
end

-- Who a unit is: its GUID when plain, else nil (unknown: repaint in full).
local function personOf(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or API.IsSecret(guid) then return nil end
    return guid
end

-- Every channel, snapping bars: the unit may be a different person now.
function Engine.FullRepaint(frame)
    frame.guid = personOf(frame.unit)
    frame.snap = true
    for _, channel in ipairs(Engine.ORDER) do Engine.MarkDirty(frame, channel) end
end

function Engine.RepaintChannel(channel)
    for _, frame in ipairs(frames) do
        if frame.unit then Engine.MarkDirty(frame, channel) end
    end
end

function Engine.RepaintAll()
    for _, frame in ipairs(frames) do
        if frame.unit then Engine.FullRepaint(frame) end
    end
end

-- The header moved `frame` to `unit` (nil: no unit, the child is hidden).
-- Plain Lua on our own tables: safe in combat.
function Engine.SetUnit(frame, unit)
    local old = frame.unit
    if old and framesByUnit[old] then framesByUnit[old][frame] = nil end
    frame.unit = unit
    if unit then
        framesByUnit[unit] = framesByUnit[unit] or {}
        framesByUnit[unit][frame] = true
        Engine.FullRepaint(frame)
    end
end

function Engine.Register(frame)
    table.insert(frames, frame)
end

local function onEvent(_, event, unit)
    local chans = eventChannels[event]
    if chans then
        local set = unit and framesByUnit[unit]
        if not set then return end
        for frame in pairs(set) do
            for _, channel in ipairs(chans) do Engine.MarkDirty(frame, channel) end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- A token can stay on its frame but mean someone else now: that frame
        -- repaints in full (bars snap). The others only refresh what a roster
        -- change can move (leader, assist, role, mark): no bar churn.
        for _, frame in ipairs(frames) do
            if frame.unit then
                local guid = personOf(frame.unit)
                if guid == nil or guid ~= frame.guid then
                    Engine.FullRepaint(frame)
                else
                    Engine.MarkDirty(frame, "indicators")
                end
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        Engine.RepaintChannel("target")
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED"
        or event == "PLAYER_ROLES_ASSIGNED" then
        Engine.RepaintChannel("indicators")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Engine.RepaintAll()
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", onEvent)
do
    local list = {}
    for e in pairs(eventChannels) do list[#list + 1] = e end
    table.sort(list)
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_TARGET_CHANGED",
                         "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }) do
        list[#list + 1] = e
    end
    API.RegisterEvents(events, list)
end

-- Range: one ticker for every shown frame with a unit.
local ticker = CreateFrame("Frame")
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < Engine.RANGE_INTERVAL then return end
    self.elapsed = 0
    for _, frame in ipairs(frames) do
        if frame.unit and frame:IsVisible() then paint(frame, "range") end
    end
end)

Engine._test = { dirty = function() return dirty end, flusher = flusher, events = events,
                 ticker = ticker, framesByUnit = framesByUnit, frames = frames }
