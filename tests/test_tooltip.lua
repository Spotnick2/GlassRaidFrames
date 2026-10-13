-- The hover tooltip (GlassUnitFrames' #80): every tile shows Blizzard's own
-- unit tooltip (UnitFrame_OnEnter / OnLeave), never on a forbidden tooltip or
-- an empty tile, and an error there never reaches the button.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

party(2)
local GRF = loadAddon()
flush()

local t = childFor("party1")
check(t and t.unit == "party1", "a tile holds party1")
check(t._scripts.OnEnter ~= nil and t._scripts.OnLeave ~= nil, "OnEnter / OnLeave on the tile")

-- Without the client's tooltip (the stub has none): hovering does nothing.
check(pcall(t._scripts.OnEnter, t), "no GameTooltip: hovering is harmless")
check(pcall(t._scripts.OnLeave, t), "and leaving too")

-- With it: Blizzard's own functions, handed the button (they read self.unit).
local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
local forbidden = false
rawset(tip, "IsForbidden", function() return forbidden end)
local entered, left = {}, {}
rawset(_G, "UnitFrame_OnEnter", function(self) entered[#entered + 1] = self end)
rawset(_G, "UnitFrame_OnLeave", function(self) left[#left + 1] = self end)
t._scripts.OnEnter(t)
eq(entered[1], t, "handed the tile itself")
eq(entered[1].unit, "party1", "whose unit Blizzard's code reads")
eq(t.hoverRim:GetAlpha(), 1, "the hover rim still lights")
t._scripts.OnLeave(t)
eq(left[1], t, "hidden on leave")
eq(t.hoverRim:GetAlpha(), 0, "and the rim goes out")

-- Pet tiles get it too (same dressing).
local pet = GRF.Header.petChildren[1]
check(pet and pet._scripts.OnEnter ~= nil, "pet tiles have the hook")

-- A tile with no unit (Blizzard's code would SetUnit(nil)) is left alone.
local empty
for _, c in ipairs(GRF.Header.children) do if not c.unit then empty = c break end end
check(empty ~= nil, "some tile holds no unit")
empty._scripts.OnEnter(empty)
eq(#entered, 1, "no tooltip for an empty tile")

-- A forbidden tooltip is left alone.
forbidden = true
t._scripts.OnEnter(t)
t._scripts.OnLeave(t)
eq(#entered, 1, "forbidden: not shown")
eq(#left, 1, "forbidden: not hidden")
forbidden = false

-- An error in Blizzard's code is recorded, never thrown at the button.
rawset(_G, "UnitFrame_OnEnter", function() error("boom") end)
check(pcall(t._scripts.OnEnter, t), "an error doesn't escape")
check(GRF.paintFailures.tooltip ~= nil, "it's recorded (/grf failures)")
GRF.paintFailures.tooltip = nil

-- Clicks still work: the hooks don't replace the button's own handlers.
eq(t:GetAttribute("*type1"), "target", "left-click still targets")
done("test_tooltip")
