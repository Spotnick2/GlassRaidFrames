-- IndicatorDefaults.lua: data only. The rank families of the spells the
-- defaults track, and each class's default indicators (#19).
--
-- Spells by ID only (owner rule: localized clients): names and icons are
-- resolved at runtime. Every ID here was checked on 70205 with
-- `/fp raid ind ids` (docs/FOREVER-PROBE.md item 10, second run).

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local D = {}
GRF.IndicatorDefaults = D

-- First rank -> every Vanilla rank, lowest first. An aura is matched by its
-- exact ID, so an indicator needs all of them (another priest's Renew may
-- be a rank you haven't learned).
D.FAMILIES = {
    [139]   = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },     -- Renew
    [17]    = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },        -- Power Word: Shield
    [774]   = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },  -- Rejuvenation
    [8936]  = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },              -- Regrowth
    [6788]  = { 6788 },                                                              -- Weakened Soul
    [10060] = { 10060 },                                                             -- Power Infusion
    [6346]  = { 6346 },                                                              -- Fear Ward
    [467]   = { 467, 782, 1075, 8914, 9756, 9910 },                                  -- Thorns
    [1022]  = { 1022, 5599, 10278 },                                                 -- Blessing of Protection
    [6940]  = { 6940, 20729 },                                                       -- Blessing of Sacrifice
    [29166] = { 29166 },                                                             -- Innervate
}

-- The tracked heals, top-right, only mine (other people's heals never show:
-- incoming heals already cover them). One fixed spot per spell (owner's
-- pick: slots cost 1 button, rows 10 per tile; FOREVER-PROBE item 10).
local function myHeals(spells)
    return { key = "myheals", name = "My heals", kind = "icons", aura = "HELPFUL", mine = true,
             enabled = true, anchor = "TOPRIGHT", x = -3, y = -3, size = 12, grow = "LEFT",
             swipe = true, timer = false, spells = spells }
end

-- Buffs others put on the unit, one spot showing the most important present
-- (list order = priority). Below the leader crown, which sits on the top edge.
local RECEIVED = { key = "received", name = "Received", kind = "icon", aura = "HELPFUL", mine = false,
                   enabled = true, anchor = "TOPLEFT", x = 3, y = -7, size = 12,
                   swipe = true, timer = false, spells = { 1022, 10060, 6940, 29166, 6346, 467 } }

-- Every debuff, as the tile always showed (Weakened Soul included: it can't
-- be matched by ID here, but the plain row shows it).
local DEBUFFS = { key = "debuffs", name = "Debuffs", kind = "debuffs", builtin = true, enabled = true,
                  filter = "all", anchor = "BOTTOMLEFT", x = 4, y = 4, size = 12, max = 3 }

D.CLASS = {
    PRIEST = { myHeals({ 139, 17 }) },
    DRUID  = { myHeals({ 774, 8936 }) },
}

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end
D.Copy = copy

-- A fresh copy of a class's defaults: its own indicators, then the shared ones.
function D.For(class)
    local list = {}
    for _, ind in ipairs(D.CLASS[class] or {}) do list[#list + 1] = copy(ind) end
    list[#list + 1] = copy(RECEIVED)
    list[#list + 1] = copy(DEBUFFS)
    return list
end

-- The built-in debuff row, for a setup that lost it.
function D.Debuffs() return copy(DEBUFFS) end
