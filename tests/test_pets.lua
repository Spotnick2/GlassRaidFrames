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
local anchor = pets._points[#pets._points]
eq(anchor[2], H.container, "it hangs under the grid")
eq(anchor[3], "BOTTOMLEFT", "(below it)")

-- Off by default: the header is hidden.
check(not pets._shown, "pets are off by default")

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

-- Shorter tiles, following resizes; the header one tile tall (point LEFT).
eq(mine:GetHeight(), H.PetHeight(), "pet tiles are shorter")
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

-- Raid: raid pets.
WoW.SetUnit("partypet1", nil)
raid(6)
WoW.SetUnit("raidpet3", { name = "Imp", class = "WARLOCK", health = 100, maxHealth = 100 })
WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); flush()
check(petFor("raidpet3"), "a raid pet gets a tile")
eq(petFor("partypet1"), nil, "party pets are gone in a raid")

-- In combat the toggle waits; nothing protected is touched.
WoW.combat = true
WoW.blocked = {}
SlashCmdList.GLASSRAIDFRAMES("pets")
check(pets._shown, "the pet row stays until combat ends")
eq(#WoW.blocked, 0, "nothing protected touched")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not pets._shown, "hidden when combat ends")

-- The options checkbox.
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local cb = O.controls.pets
eq(cb:GetChecked(), false, "the checkbox shows the role's setting")
cb:SetChecked(true); cb._scripts.OnClick(cb)
check(pets._shown, "ticking it shows pets")

eq(next(GRF.paintFailures), nil, "no failures")
done("test_pets")
