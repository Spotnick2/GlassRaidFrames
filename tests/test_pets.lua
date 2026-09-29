-- Pets (#13): a pet header under the grid, off by default, per role; pet
-- tiles are dressed like the rest, sized shorter, and take mouse bindings.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

UIParent._width, UIParent._height = 1365, 768
party(2)
WoW.SetUnit("pet", { name = "Grol", class = "WARRIOR", health = 300, maxHealth = 300 })
WoW.SetUnit("partypet1", { name = "Wolf", class = "WARRIOR", health = 200, maxHealth = 250 })
GlassRaidFramesCharDB = { role = "HEALER" }
local GRF = loadAddon()
local H = GRF.Header

-- Built, precreated, dressed.
local pets = H.petHeader
check(pets and pets._template == "SecureGroupPetHeaderTemplate", "a pet header exists")
eq(#H.petChildren, H.PET_COUNT, "its tiles are precreated")
check(H.petChildren[1].body and H.petChildren[1].health, "pet tiles are dressed like the others")
eq(pets:GetAttribute("startingIndex"), 1, "startingIndex restored")
eq(pets:GetAttribute("initialConfigFunction"), nil, "no restricted snippet")
local pc = H.petContainer
check(pc and pets:GetParent() == pc, "pets have their own container (movable on their own)")
local function petAnchor() return pc._points[#pc._points] end
eq(petAnchor()[2], H.container, "by default anchored to the grid (it follows it)")
eq(petAnchor()[4], 1 * (select(1, H.TileSize()) + H.GAP), "in a party: the column right after the party's")

-- Capacity is exactly the precreated count: no undressed tile 21+ (code review).
eq(pets:GetAttribute("unitsPerColumn") * pets:GetAttribute("maxColumns"), H.PET_COUNT, "the header holds exactly PET_COUNT pets")

-- Off by default: the header is hidden, and its tiles hold no units (a hidden
-- header stops updating them; the engine must not paint stale tokens).
check(not pets._shown, "pets are off by default")
for _, c in ipairs(H.petChildren) do check(c.unit == nil, "a hidden pet tile has no unit in the engine") break end
check(next(GRF.Engine._test.framesByUnit.pet or {}) == nil, "nothing paints 'pet' while pets are hidden")

-- /grf pets turns them on for this role: pets get tiles.
SlashCmdList.GLASSRAIDFRAMES("pets")
check(pets._shown, "shown once turned on")
eq(GRF.Profile().showPets, true, "saved in the role's profile")
WoW.layoutHeaders(); flush()
local function petFor(unit)
    for _, c in ipairs(H.petChildren) do if c:GetAttribute("unit") == unit then return c end end
end
local mine, wolf = petFor("pet"), petFor("partypet1")
check(mine and wolf, "your pet and the party's pets have tiles")
eq(wolf.nameText._text, "Wolf", "a pet's name is painted")
eq(wolf.health._value, 200, "its health too")
eq(wolf.health._color[1], GRF.Frames.PET[1], "pets get the pet colour, not a creature class")
eq(mine.health._color[1], GRF.Frames.PET[1], "(yours too)")

-- Shorter tiles, following resizes; the header one tile tall (point LEFT).
eq(mine:GetHeight(), H.PetHeight(), "pet tiles are shorter")
check(H.PetHeight() >= H.MIN_H, "never under the tile minimum (the debuff row would cover the name)")

-- The announced rectangle covers the pets when shown (another addon makes room).
H.SetPetPosition(600, 0, false)                           -- pets well right of the grid
local gl, gb, gw = H.container:GetRect()
local l, b, w = H.Rect()
check(w and gw and w > gw, "the announced rectangle grows to include the pets")
H.PlacePets()
eq(mine:GetWidth(), select(1, H.TileSize()), "as wide as the others")
SlashCmdList.GLASSRAIDFRAMES("size 100 60")
eq(mine:GetWidth(), 100, "a resize reaches pet tiles")
eq(mine:GetHeight(), H.PetHeight(), "at the pet height")
eq(pets._height, H.PetHeight(), "the pet header is one tile tall (its LEFT anchor centres on it)")

-- Mouse bindings reach pet tiles; hover keys don't target pets ([party]).
rawset(_G, "C_Spell", { GetSpellName = function() return "Renew" end, GetSpellSubtext = function() return "Rank 1" end })
rawset(_G, "C_SpellBook", { IsSpellKnown = function() return true end })
Enum.SpellBookSpellBank = { Player = 0 }
rawset(_G, "GetBindingAction", function() return nil end)
rawset(_G, "SetOverrideBindingClick", function() end)
rawset(_G, "ClearOverrideBindings", function() end)
rawset(_G, "GetModifiedClick", function() return "ALT" end)
GRF.ClickCast.Set("shift-1", true, 139)
flush()
eq(wolf:GetAttribute("shift-spell1"), "Renew", "a mouse binding works on a pet's tile")

-- Per role: the caster role doesn't show pets unless asked.
GRF.Settings.SetRole("caster")
check(not pets._shown, "another role has its own pet setting (off)")
GRF.Settings.SetRole("healer")
check(pets._shown, "back to healer: pets again")

-- Raid: raid pets, in the column after the last group in use (dynamic).
WoW.SetUnit("partypet1", nil)
raid(12)                                                -- groups 1-3
WoW.SetUnit("raidpet3", { name = "Imp", class = "WARLOCK", health = 100, maxHealth = 100 })
WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); WoW.flushTimers(); flush()
check(petFor("raidpet3"), "a raid pet gets a tile")
eq(petFor("partypet1"), nil, "party pets are gone in a raid")
local tw = select(1, H.TileSize())
eq(petAnchor()[4], 3 * (tw + H.GAP), "three groups: pets take column 4")
raid(22)                                                -- groups 1-5
WoW.SetUnit("raidpet3", { name = "Imp", class = "WARLOCK", health = 100, maxHealth = 100 })
WoW.combat = true
WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); WoW.flushTimers(); flush()
eq(petAnchor()[4], 3 * (tw + H.GAP), "a roster change in combat: the pet column waits")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(petAnchor()[4], 5 * (tw + H.GAP), "and moves after the fifth group when combat ends")

-- Moved on their own: a saved spot wins over the dynamic column.
GRF.Movers.Unlock()
local pm = GRF.Movers._test.petMover()
check(pm and pm._shown, "unlock mode has a pets mover")
eq(pm._points[#pm._points][2], pc, "anchored to the pet block")
UIParent._center = { 682, 384 }
pm._scripts.OnDragStart(pm); pm._center = { 900, 300 }; pm._scripts.OnUpdate(pm); pm._scripts.OnDragStop(pm)
eq(GRF.Profile().petPos.x, 218, "the pets' own spot is saved (x)")
eq(GRF.Profile().pos, nil, "without moving the grid's")
eq(petAnchor()[1], "CENTER", "the pets now sit at their own spot")
raid(40); WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); WoW.flushTimers()
eq(petAnchor()[1], "CENTER", "and stay there when the roster changes")
GRF.Movers.Lock()
SlashCmdList.GLASSRAIDFRAMES("reset")
eq(GRF.Profile().petPos, nil, "reset forgets the pets' spot too")
eq(petAnchor()[2], H.container, "and puts them back beside the groups")

-- In combat the toggle waits; nothing protected is touched.
WoW.combat = true
WoW.blocked = {}
SlashCmdList.GLASSRAIDFRAMES("pets")
check(pets._shown, "the pet row stays until combat ends")
eq(#WoW.blocked, 0, "nothing protected touched")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not pets._shown, "hidden when combat ends")

-- Solo: your pet follows "show solo" (no lone pet under an empty grid).
WoW.raid = nil
for i = 1, 40 do WoW.SetUnit("raid" .. i, nil); WoW.SetUnit("raidpet" .. i, nil) end
WoW.SetUnit("party1", nil); WoW.SetUnit("party2", nil)
SlashCmdList.GLASSRAIDFRAMES("pets")                      -- on again
WoW.layoutHeaders(); flush()
eq(petFor("pet"), nil, "solo without 'show solo': no pet tile")
SlashCmdList.GLASSRAIDFRAMES("solo")
WoW.layoutHeaders(); flush()
check(petFor("pet"), "solo with 'show solo': your pet shows")
SlashCmdList.GLASSRAIDFRAMES("solo")
SlashCmdList.GLASSRAIDFRAMES("pets")                      -- off for the checkbox test

-- The options checkbox.
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local cb = O.controls.pets
eq(cb:GetChecked(), false, "the checkbox shows the role's setting")
cb:SetChecked(true); cb._scripts.OnClick(cb)
check(pets._shown, "ticking it shows pets")

eq(next(GRF.paintFailures), nil, "no failures")
done("test_pets")
