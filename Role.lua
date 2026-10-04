-- Role.lua: which role the player is playing, for settings per role (#7).
--
-- Self-contained on purpose, so GlassUnitFrames can lift it
-- for its own role layouts (its #35): it needs no engine, frames or saved
-- variables, only the client's talent API. The caller passes the manual
-- pick and listens for changes.
--
-- Roles: HEALER, CASTER, MELEE, TANK. Priority:
--   1. the player's manual pick (per character, saved by the caller);
--   2. the talent tree with the most points;
--   3. a class default (a character with no talent points yet).
--
-- Measured on 1.60.1.70009 (docs/FOREVER-PROBE.md, item 9):
-- - Forever has ONE spec per class, always role DAMAGER: C_SpecializationInfo
--   can't tell Holy from Shadow;
-- - the three Vanilla trees are column clusters in ONE trait tree:
--   C_ClassTalents.GetActiveConfigID -> C_Traits.GetConfigInfo(id).treeIDs[1],
--   whose visible nodes sit in three posX ranges (1020-2820, 5020-6820,
--   9080-10880 on priest and paladin), in the talent-tab order, split by gaps
--   of over 2000 units. One priest node sits off the canvas (y 21300).
-- So a tree is found by POSITION, never by a talent's name: that works on
-- every client language (the owner's rule: IDs, never names).

GlassRaidFrames = GlassRaidFrames or {}
local Role = {}
GlassRaidFrames.Role = Role

Role.ROLES = { "HEALER", "CASTER", "MELEE", "TANK" }
Role.VALID = { HEALER = true, CASTER = true, MELEE = true, TANK = true }

-- Per class, the role of each talent tree, in tab order (left to right).
-- Feral druids read MELEE: bear tanks pick TANK by hand.
Role.TREES = {
    PRIEST  = { "HEALER", "HEALER", "CASTER" },   -- Discipline, Holy, Shadow
    PALADIN = { "HEALER", "TANK", "MELEE" },      -- Holy, Protection, Retribution
    DRUID   = { "CASTER", "MELEE", "HEALER" },    -- Balance, Feral, Restoration
    SHAMAN  = { "CASTER", "MELEE", "HEALER" },    -- Elemental, Enhancement, Restoration
    WARRIOR = { "MELEE", "MELEE", "TANK" },       -- Arms, Fury, Protection
    ROGUE   = { "MELEE", "MELEE", "MELEE" },
    MAGE    = { "CASTER", "CASTER", "CASTER" },
    WARLOCK = { "CASTER", "CASTER", "CASTER" },
    HUNTER  = { "CASTER", "CASTER", "CASTER" },   -- ranged: laid out like a caster
}

-- Before any talent point: the owner's healers are the hybrids.
Role.CLASS_DEFAULT = {
    PRIEST = "HEALER", PALADIN = "HEALER", DRUID = "HEALER", SHAMAN = "HEALER",
    WARRIOR = "MELEE", ROGUE = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", HUNTER = "CASTER",
}

Role.GAP = 1000          -- posX gap that separates two trees (measured gaps: over 2000)
Role.MAX_Y = 10000       -- nodes below this are off the canvas (the stray priest node: 21300)

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function playerClass()
    local ok, _, class = pcall(UnitClass, "player")
    if ok then return plain(class) end
    return nil
end

-- Group points (sorted by x) into clusters split by gaps wider than Role.GAP.
-- Pure: nodes = { { x = posX, ranks = n }, ... }. Returns ranks per cluster,
-- left to right.
function Role.ClusterPoints(nodes)
    table.sort(nodes, function(a, b) return a.x < b.x end)
    local sums, lastX = {}, nil
    for _, n in ipairs(nodes) do
        if lastX == nil or n.x - lastX > Role.GAP then sums[#sums + 1] = 0 end
        sums[#sums] = sums[#sums] + n.ranks
        lastX = n.x
    end
    return sums
end

-- Points spent per talent tree, left to right, or nil when the client doesn't
-- answer the way it was measured to (then the role falls back to the class).
function Role.TreePoints()
    local CT, TR = rawget(_G, "C_ClassTalents"), rawget(_G, "C_Traits")
    if not (CT and TR and CT.GetActiveConfigID and TR.GetConfigInfo and TR.GetTreeNodes and TR.GetNodeInfo) then
        return nil
    end
    local ok, configID = pcall(CT.GetActiveConfigID)
    configID = ok and plain(configID)
    if type(configID) ~= "number" then return nil end
    local okC, info = pcall(TR.GetConfigInfo, configID)
    local treeID = okC and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if type(treeID) ~= "number" then return nil end
    local okN, nodeIDs = pcall(TR.GetTreeNodes, treeID)
    if not okN or type(nodeIDs) ~= "table" then return nil end
    local nodes = {}
    for _, nodeID in ipairs(nodeIDs) do
        local okI, node = pcall(TR.GetNodeInfo, configID, nodeID)
        if okI and type(node) == "table" and node.ID and node.ID ~= 0 and node.isVisible ~= false then
            local x, y, r = plain(node.posX), plain(node.posY), plain(node.currentRank)
            if type(x) == "number" and type(y) == "number" and y < Role.MAX_Y then
                nodes[#nodes + 1] = { x = x, ranks = type(r) == "number" and r or 0 }
            end
        end
    end
    local sums = Role.ClusterPoints(nodes)
    if #sums ~= 3 then return nil end   -- not the measured layout: don't guess
    return sums
end

-- The role from talents, or nil (no points, unknown class, unexpected layout).
function Role.FromTalents(class)
    local roles = Role.TREES[class]
    local sums = roles and Role.TreePoints()
    if not sums then return nil end
    local best, bestPoints = nil, 0
    for i, points in ipairs(sums) do
        -- Ties keep the leftmost tree; zero points everywhere means no answer.
        if points > bestPoints then best, bestPoints = i, points end
    end
    return best and roles[best] or nil
end

-- The role in effect and where it came from: "manual", "talents",
-- "remembered" or "class". `manual` is the saved per-character pick ("auto"
-- or nil = none). `remembered` is the last role the talents gave (the caller
-- saves it): the talent API doesn't answer at ADDON_LOADED or during a
-- loading screen, and a talent build doesn't change without a talent event,
-- so the last answer beats the class default.
function Role.Get(manual, remembered)
    if Role.VALID[manual] then return manual, "manual" end
    local class = playerClass()
    local fromTalents = Role.FromTalents(class)
    if fromTalents then return fromTalents, "talents" end
    if Role.VALID[remembered] then return remembered, "remembered" end
    return Role.CLASS_DEFAULT[class] or "CASTER", "class"
end

Role.EVENTS = { "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
                "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD" }

-- Watch the events that can change the talent answer (measured: PLAYER_TALENT_UPDATE
-- fires at login and on /reload; the others are the dump's talent/config
-- events) and call onChange() on any of them; the caller re-evaluates.
-- `register(frame, events)` is the caller's reporting registrar (GlassRaidFrames:
-- API.RegisterEvents); without one, failures are kept in Role.failures.
Role.failures = {}
function Role.Watch(onChange, register)
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() onChange() end)
    if register then
        register(f, Role.EVENTS)
    else
        for _, e in ipairs(Role.EVENTS) do
            local ok, r = pcall(f.RegisterEvent, f, e)
            if not ok or r == false then Role.failures[#Role.failures + 1] = e end
        end
    end
    return f
end
