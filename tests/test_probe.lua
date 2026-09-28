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

done("test_probe")
