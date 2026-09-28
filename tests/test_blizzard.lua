-- Hiding Blizzard's party and raid frames (FOREVER-PROBE item 6).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The four frames, protected on Forever (measured), shown under UIParent.
for _, name in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" }) do
    local f = CreateFrame("Frame", name, UIParent, "SecureFrameTemplate")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
end

party(1)
local GRF = loadAddon()
local B = GRF.Blizzard
local hidden = B.hiddenParent

for _, name in ipairs(B.FRAMES) do
    local f = rawget(_G, name)
    eq(f:GetParent(), hidden, name .. " is reparented away")
    check(not f._shown, name .. " is hidden")
    check(f._silenced, name .. " stops listening to events")
end
check(B.active, "Blizzard.active records the hide")

-- Edit Mode reparents a frame: never repaired inside that call (it would
-- taint secret reads), only on a timer, and not while Edit Mode is open.
local pf = rawget(_G, "PartyFrame")
WoW.SetEditMode(true)
pf:SetParent(UIParent)
eq(pf:GetParent(), UIParent, "not repaired synchronously inside Edit Mode's SetParent")
WoW.flushTimers()
eq(pf:GetParent(), UIParent, "not repaired while Edit Mode is open")
WoW.SetEditMode(false)
for _ = 1, 3 do WoW.flushTimers() end
eq(pf:GetParent(), hidden, "repaired once Edit Mode closes")

-- Outside Edit Mode too, never inside the caller's SetParent.
pf:SetParent(UIParent)
eq(pf:GetParent(), UIParent, "never repaired synchronously, even outside Edit Mode")
WoW.flushTimers()
eq(pf:GetParent(), hidden, "repaired on the next timer")

-- Combat starts before the deferred repair runs: the protected frame waits
-- for the combat queue.
pf:SetParent(UIParent)
WoW.combat = true
for _ = 1, 3 do WoW.flushTimers() end
eq(pf:GetParent(), UIParent, "a protected frame waits out combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(pf:GetParent(), hidden, "and is repaired when combat ends")

-- A frame this client lacks is skipped, not an error.
eq(B.HideFrame("NoSuchBlizzardFrame"), false, "a missing frame is skipped")

-- The raid manager (leader tools: ready check, world markers) stays (code review).
local mgr = rawget(_G, "CompactRaidFrameManager")
eq(mgr:GetParent(), UIParent, "the raid manager side panel is left alone")
check(not mgr._silenced, "and keeps its events")

-- /grf blizzard turns it off for the next session.
SlashCmdList.GLASSRAIDFRAMES("blizzard")
eq(GRF.db.hideBlizzard, false, "the setting is saved off")
check(chatHas("after /reload"), "and says it takes a /reload")

-- Toggled on then off again in combat: the queued hide re-checks the
-- setting when combat ends, so nothing is hidden (code review).
WoW.reset()
for _, name in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" }) do
    CreateFrame("Frame", name, UIParent, "SecureFrameTemplate")
end
party(1)
GRF = loadAddon({ db = { hideBlizzard = false } })
eq(rawget(_G, "PartyFrame"):GetParent(), UIParent, "hideBlizzard off: nothing hidden at login")
WoW.combat = true
SlashCmdList.GLASSRAIDFRAMES("blizzard")
SlashCmdList.GLASSRAIDFRAMES("blizzard")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GRF.db.hideBlizzard, false, "the setting ends off")
eq(rawget(_G, "PartyFrame"):GetParent(), UIParent, "and the queued hide did nothing")

done("test_blizzard")
