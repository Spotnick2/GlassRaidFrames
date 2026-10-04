-- RaidProbe's hover-key toggle (Codex review of PR #5): turning the mode off
-- must release a key a hovered tile still holds, and leaving a tile must
-- clean up whether or not the mode is still on.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Override bindings, as the client keeps them: key -> owning frame.
local bound = {}
rawset(_G, "SetOverrideBindingClick", function(owner, _, key) bound[key] = owner end)
rawset(_G, "ClearOverrideBindings", function(owner)
    for key, o in pairs(bound) do if o == owner then bound[key] = nil end end
end)
-- The rest of what the probe touches on these paths (all in the 70009 dump).
rawset(_G, "GetTime", function() return 0 end)
rawset(_G, "C_Spell", { GetSpellName = function(id) return id == 2050 and "Lesser Heal" or nil end })
rawset(_G, "RaidProbeDB", { log = {} })
rawset(_G, "UnitGroupRolesAssigned", function() return "NONE" end)   -- captured by the secrets table at load

WoW.SetUnit("player", { name = "Karuzo", class = "PRIEST", player = true })
assert(loadfile("Tools/RaidProbe/RaidProbe.lua"))("RaidProbe", {})
local T = RaidProbe_test
local key = T.HOVER_KEY

local tile = CreateFrame("Button", "RaidProbe_party1", UIParent, "SecureUnitButtonTemplate")
tile.unit = "party1"
table.insert(T.order, tile)

local function enter() tile._scripts.OnEnter(tile) end
local function leave() tile._scripts.OnLeave(tile) end

-- On, hover: the key belongs to the tile.
T.hoverKeys()
check(T.P.hover, "hover keys on")
eq(tile:GetAttribute("spell-key8"), "Lesser Heal", "the tile casts the test spell on the virtual key8 button")
enter()
eq(bound[key], tile, "hovering binds the key to the tile")

-- Codex's sequence: turn the mode off while still hovering, then leave.
T.hoverKeys()
check(not T.P.hover, "hover keys off")
eq(bound[key], nil, "turning the mode off releases the key the hovered tile held")
leave()
eq(bound[key], nil, "leaving afterwards keeps it released")

-- Normal use: on, hover, leave.
T.hoverKeys()
enter()
eq(bound[key], tile, "hovering binds again once the mode is back on")
leave()
eq(bound[key], nil, "leaving releases the key")

-- Off: hovering binds nothing.
T.hoverKeys()
enter()
eq(bound[key], nil, "with the mode off, hovering binds nothing")

-- In combat the toggle is refused and changes nothing.
T.hoverKeys()
enter()
WoW.combat = true
T.hoverKeys()
check(T.P.hover, "the toggle is refused in combat")
eq(bound[key], tile, "and the key stays where it was")
WoW.combat = false

WoW.combat = false
leave()
T.hoverKeys()

-- The indicator probe (#19): every subcommand runs offline without touching an
-- unstubbed global or failing a call (the client parts are stubbed here).
rawset(_G, "C_Secrets", { GetSpellAuraSecrecy = function() return 0 end })
rawset(_G, "C_UnitAuras", {
    GetAuraDataByIndex = function(unit, i, filter)
        if i > 1 then return nil end
        return { name = "Renew", spellId = 139, sourceUnit = "player", duration = 15, auraInstanceID = 7 }
    end,
    IsAuraFilteredOutByInstanceID = function(unit, id, filter) return filter:find("RAID", 1, true) ~= nil end,
})
C_Spell.GetSpellSubtext = function() return "Rank 1" end
rawset(_G, "AnchorUtil", { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 } })
rawset(_G, "debugprofilestop", function() return 0 end)
local function failures()
    local n = 0
    for _, line in ipairs(WoW.chat) do if line:find("FAIL", 1, true) then n = n + 1 end end
    return n
end
local before = failures()
for _, cmd in ipairs({ "ind", "ind party1", "ind reconf", "ind reconf", "ind src", "ind src party1", "ind cost", "ind ids" }) do
    local ok, err = pcall(SlashCmdList.RAIDPROBE, cmd)
    check(ok, "/rprobe " .. cmd .. " runs: " .. tostring(err))
end
eq(failures() - before, 0, "no probe call failed")
eq(#T.P.indContainers, 8, "the panel has its 8 test containers")
eq(T.P.indUnit, "party1", "ind <unit> rebinds the panel")
check(chatHas("RAID_IN_COMBAT=out"), "src reports which filters keep each aura")
check(chatHas("cost: 40 tiles"), "cost reports its build")

-- The button look the client would apply (initializeFrame).
local button = CreateFrame("Button", nil, UIParent)
T.indButton(16, 30, { 1, 0, 0 }, UIParent)(button)
T.indButton(16)(button)
eq(failures() - before, 0, "the probe button initialiser runs cleanly")

done("test_probe")
