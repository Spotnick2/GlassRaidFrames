-- Buff and debuff indicators (#19): the per-class setup, what each indicator
-- asks the aura container for, live edits without new containers, combat
-- deferral, and failure isolation.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

party(2)   -- the player is a priest
local GRF = loadAddon()
local H, Ind = GRF.Header, GRF.Indicators
flush()

local function entries(b) return b.grfInd.byKey end
local function slots(e) return e.c._slots or {} end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function find(key) return GRF.Settings.FindIndicator(key) end
-- Spell names for /grf ind (C_Spell is in the dump).
rawset(_G, "C_Spell", { GetSpellName = function(id) return id == 139 and "Renew" or ("Spell " .. id) end })

-- Seeded once per class, account-wide.
local saved = GRF.db.indicators and GRF.db.indicators.PRIEST
check(saved and saved.list, "the priest setup is saved account-wide, per class")
local keys = {}
for _, ind in ipairs(saved.list) do keys[#keys + 1] = ind.key end
eq(table.concat(keys, ","), "myheals,received,debuffs", "priest defaults: my heals, received, debuffs")

-- My heals: one fixed spot per spell, only mine, every rank.
local p1 = childFor("party1")
local heals = entries(p1).myheals
check(heals and heals.kind == "icons", "my heals built on party1")
local s1, s2 = slots(heals).s1, slots(heals).s2
eq(count(slots(heals)), 2, "one slot per spell (Renew, Shield): 1 button each")
eq(s1.filter, "HELPFUL|PLAYER", "only my Renew")
eq(s2.filter, "HELPFUL|PLAYER", "only my Shield")
local renew = s1.spec.candidateFilters.includeSpellIDs
eq(count(renew), 10, "every Renew rank is matched")
check(renew[139] and renew[25315], "lowest and highest Renew ranks")
check(slots(heals).s2.spec.candidateFilters.includeSpellIDs[10901], "the top Shield rank")
local pt1, pt2 = s1.frame._points[1], s2.frame._points[1]
eq(pt1[1] .. " " .. pt1[4] .. " " .. pt1[5], "TOPRIGHT -3 -3", "Renew in the corner")
eq(pt2[1] .. " " .. pt2[4] .. " " .. pt2[5], "TOPRIGHT -17 -3", "Shield next to it, growing left")
check(pt1[2] == p1.body, "placed on the tile's body, never on the container")
eq(s1.frame._width, 12, "icons sized from the setup")
check(s1.frame.grf and s1.frame.grf.cd and s1.frame._cooldown == s1.frame.grf.cd, "the swipe is the client's")
eq(s1.frame._mouse, false, "aura buttons don't take the mouse")

-- Received: one spot, the first spell present wins (stacked levels).
local rec = entries(p1).received
eq(rec.kind, "icon", "received is a single spot")
eq(slots(rec).s1.filter, "HELPFUL", "anyone's")
local spot = slots(rec).s1.frame._points[1]
for i = 2, 6 do
    local s = slots(rec)["s" .. i]
    check(s.frame:GetFrameLevel() < slots(rec)["s" .. (i - 1)].frame:GetFrameLevel(),
        "spell " .. i .. " sits under spell " .. (i - 1))
    eq(s.frame._points[1][4], spot[4], "same spot " .. i)
end
check(slots(rec).s6.frame:GetFrameLevel() > p1.body:GetFrameLevel() + 10, "every indicator over the glass rim")

-- PLAYER exactly on "mine" indicators, everywhere.
for _, b in ipairs(H.children) do
    for key, e in pairs(entries(b)) do
        local ind = find(key)
        for sk, s in pairs(slots(e)) do
            eq(s.filter:find("|PLAYER", 1, true) ~= nil, ind.mine, key .. "/" .. sk .. ": PLAYER iff mine")
        end
    end
end

-- The debuff row as before: a group, declared before the unit.
local deb = entries(p1).debuffs
eq(deb.c._groups.grf_debuffs.filter, "HARMFUL", "every debuff")
local seq = table.concat(deb.c._seq, ",")
check(seq:find("AddAuraGroup") < seq:find("SetUnit"), "AddAuraGroup before SetUnit (" .. seq .. ")")
eq(deb.c._modelUnit, "party1", "the row follows its tile")
eq(heals.c._modelUnit, "party1", "my heals follow the tile")
local first = deb.c._groups.grf_debuffs.frames[1]   -- built by AddAuraGroup, before e.ind exists
check(first.grf and not first.grf.timer._shown, "debuff buttons show no timer text, the first batch included")
eq(first._mouse, false, "debuff buttons don't take the mouse")

-- Pets: only the debuff row.
local pet = H.petChildren[1]
eq(count(entries(pet)), 1, "a pet tile gets one indicator")
check(entries(pet).debuffs, "(the debuff row)")

-- Weakened Soul by ID can't be matched (ContextuallySecret, measured): the
-- indicator is reported, not built. NeverSecret would build it.
table.insert(saved.list, { key = "ws", name = "Weakened Soul", kind = "square", aura = "HARMFUL", mine = false,
    enabled = true, anchor = "TOPLEFT", x = 3, y = -18, size = 8, spells = { 6788 } })
Ind._test.checked.PRIEST = nil
Ind.Apply()
local ok, why = Ind.Supported(find("ws"))
check(not ok and why:find("can't be tracked"), "Weakened Soul is reported unsupported")
eq(entries(p1).ws, nil, "and not built")
WoW.auraSecrecy[6788] = Enum.SecrecyLevel.NeverSecret
Ind.Apply()
check(entries(p1).ws and slots(entries(p1).ws).s1.filter == "HARMFUL", "a NeverSecret debuff is built")
WoW.auraSecrecy[6788] = nil

-- Edits change the slots in place: no new container, no new key.
local healsC = heals.c
find("myheals").spells = { 139 }
Ind.Apply()
eq(entries(p1).myheals.c, healsC, "same container after removing a spell")
eq(slots(heals).s2.enabled, false, "the removed spell's slot is switched off")
find("myheals").spells = { 139, 17 }
Ind.Apply()
eq(slots(heals).s2.enabled, true, "re-added: the slot comes back on")
eq(count(slots(heals)), 2, "without a new slot")
find("myheals").mine = false
Ind.Apply()
eq(slots(heals).s1.filter, "HELPFUL", "'only mine' off: the filter follows")
find("myheals").mine = true
find("myheals").anchor, find("myheals").size = "BOTTOMRIGHT", 16
Ind.Apply()
eq(slots(heals).s2.frame._points[1][1], "BOTTOMRIGHT", "moved")
eq(slots(heals).s2.frame._points[1][4], -3 - 18, "spaced for the new size")
eq(slots(heals).s1.frame._width, 16, "resized")

-- Disabling parks the container; the next indicator of that kind reuses it.
local recC = rec.c
GRF.Settings.SetIndicatorEnabled("received", false)
eq(entries(p1).received, nil, "a disabled indicator leaves the tile")
check(not recC._shown, "its container hidden")
eq(slots(rec).s1.enabled, false, "its slots off")
table.insert(saved.list, { key = "externals", name = "Externals", kind = "icon", aura = "HELPFUL", mine = false,
    enabled = true, anchor = "LEFT", x = 3, y = 0, size = 12, spells = { 1022 } })
Ind._test.checked.PRIEST = nil
Ind.Apply()
eq(entries(p1).externals.c, recC, "a new indicator reuses the parked container")
check(recC._shown and slots(rec).s1.enabled, "shown and on again")
eq(slots(rec).s2.enabled, false, "its extra slots stay off")
eq(recC._modelUnit, "party1", "re-bound to the tile's unit")

-- In combat nothing is built or resized: the change waits for combat's end.
WoW.combat = true
WoW.blocked = {}
GRF.Settings.SetIndicatorEnabled("received", true)
eq(entries(p1).received, nil, "not applied in combat")
eq(#WoW.blocked, 0, "nothing protected or locked touched in combat")
check(Ind.Apply() == false, "a direct Apply in combat refuses")
eq(entries(p1).received, nil, "(and changes nothing)")
eq(#WoW.blocked, 0, "(nothing touched)")
WoW.leaveCombat()
check(entries(p1).received, "applied when combat ends")

-- A unit change in combat moves every indicator (tokens move between tiles).
WoW.combat = true
raid(12)
WoW.layoutHeaders()
WoW.fire("GROUP_ROSTER_UPDATE"); flush()
local r7 = childFor("raid7")
eq(entries(r7).myheals.c._modelUnit, "raid7", "my heals moved to the new unit in combat")
eq(entries(r7).received.c._modelUnit, "raid7", "received too")
WoW.leaveCombat()

-- One failing tile costs no other.
local broken = H.children[2]
local realBody = broken.body
broken.body = nil
find("myheals").size = 14
Ind.Apply()
broken.body = realBody
check(GRF.paintFailures["indicator myheals"], "the failure is recorded")
eq(slots(entries(H.children[3]).myheals).s1.frame._width, 14, "the next tile still updated")
for k in pairs(GRF.paintFailures) do if k:find("^indicator ") then GRF.paintFailures[k] = nil end end
-- A tile failing outside any one indicator (reading its unit) is isolated too.
broken.GetAttribute = function() error("boom") end
find("myheals").size = 13
Ind.Apply()
broken.GetAttribute = nil
check(GRF.paintFailures.indicators, "a whole-tile failure is recorded")
eq(slots(entries(H.children[3]).myheals).s1.frame._width, 13, "the next tile still updated")
GRF.paintFailures.indicators = nil

-- Saved data is validated once per session: junk dropped, values clamped,
-- the debuff row restored.
GRF.db.indicators.PRIEST = { version = 1, list = {
    { key = "a", kind = "icons", spells = { 139, "x", 139, -4 }, size = 999, anchor = "NOWHERE" },
    { key = "a", kind = "icon", spells = {} },
    { key = "b", kind = "teleport" },
    "junk",
} }
Ind._test.checked.PRIEST = nil
local list = Ind.Setup()
eq(#list, 2, "a duplicate, an unknown kind and junk dropped; the debuff row added")
eq(list[1].size, Ind.MAX_SIZE, "size clamped")
eq(list[1].anchor, "TOPLEFT", "unknown anchor replaced")
eq(table.concat(list[1].spells, ","), "139", "spells deduplicated, junk dropped")
eq(list[2].kind, "debuffs", "the built-in row can't be lost")

-- /grf ind lists, toggles, resets.
newChat()
SlashCmdList.GLASSRAIDFRAMES("ind reset")
check(chatHas("1%. My heals %(icons, topright%): mine: "), "/grf ind lists my heals")
check(chatHas("Received %(one icon"), "and received")
SlashCmdList.GLASSRAIDFRAMES("ind 2 off")
eq(find("received").enabled, false, "/grf ind 2 off")
SlashCmdList.GLASSRAIDFRAMES("ind received on")
eq(find("received").enabled, true, "/grf ind <key> on")

-- Review of PR #22 --------------------------------------------------------
GRF.Settings.ResetIndicators()
WoW.fire("PLAYER_REGEN_ENABLED")
local q1 = H.children[1]
local qh, qr = entries(q1).myheals, entries(q1).received

-- "Offline" stays readable over the heals icons (a disconnected player keeps
-- their auras).
local top = 0
for _, e in pairs(entries(q1)) do
    for _, sl in pairs(slots(e)) do top = math.max(top, sl.frame:GetFrameLevel()) end
end
check(q1.statusText:GetParent():GetFrameLevel() > top, "Dead/Offline draws over every indicator")

-- A raised stacked slot keeps its swipe and texts above it.
local r1 = slots(qr).s1.frame
eq(r1.grf.cd:GetFrameLevel(), r1:GetFrameLevel() + 1, "the swipe sits just above its raised button")
eq(r1.grf.top:GetFrameLevel(), r1:GetFrameLevel() + 5, "the texts above the swipe")

-- Received sits under the leader crown, not over it.
check(slots(qr).s1.frame._points[1][5] <= -7, "received clears the crown on the top edge")

-- Reset validates like a saved setup (fills grow, colour, swipe...).
eq(find("received").grow, "LEFT", "reset setups are validated")
check(type(find("received").color) == "table", "(colour filled)")

-- The debuff row is built from its indicator, not from constants.
local fresh = Ind._test.newContainer(q1, { key = "d2", kind = "debuffs", builtin = true, filter = "dispellable",
    max = 5, size = 16, anchor = "BOTTOMLEFT", x = 4, y = 4 })
local dg = fresh.c._groups.grf_debuffs
eq(dg.spec.maxFrameCount, 5, "the row's max comes from its indicator")
eq(dg.spec.layout.elementWidth, 16, "its size too")
eq(dg.filter, "HARMFUL|RAID", "and its filter")
eq(dg.frames[1]._width, 16, "the first batch of buttons is built at that size")
fresh.c:Hide()

-- A no-op Apply restyles nothing; a change restyles.
local placed = 0
local hs1 = slots(qh).s1.frame
local realSetPoint = hs1.SetPoint
hs1.SetPoint = function(self, ...) placed = placed + 1; return realSetPoint(self, ...) end
Ind.Apply()
eq(placed, 0, "nothing changed: no slot is restyled")
find("myheals").x = -4
Ind.Apply()
check(placed > 0, "a moved indicator is restyled")
hs1.SetPoint = nil

-- An AddAuraSlot that registers the slot and then throws: the next apply
-- adopts the slot instead of re-adding the key (which the client asserts).
local realAdd = qh.c.AddAuraSlot
qh.c.AddAuraSlot = function(self, ...)
    realAdd(self, ...)
    error("late failure")
end
table.insert(find("myheals").spells, 774)
Ind.Apply()
qh.c.AddAuraSlot = nil
check(GRF.paintFailures["aura slot"], "the half-added slot's failure is recorded")
GRF.paintFailures["aura slot"] = nil
Ind.Apply()
eq(GRF.paintFailures["aura slot"], nil, "the next apply doesn't re-add the key")
eq(GRF.paintFailures["indicator myheals"], nil, "(nor fail the indicator)")
eq(qh.slots, 3, "the slot is adopted")
check(slots(qh).s3.spec.candidateFilters.includeSpellIDs[25299], "and given its spell's ranks")
table.remove(find("myheals").spells)

-- /grf ind keeps the key's case.
find("received").key = "Received"
SlashCmdList.GLASSRAIDFRAMES("ind Received off")
eq(find("Received").enabled, false, "a mixed-case key toggles")
find("Received").key, find("Received").enabled = "received", true
Ind.Apply()

-- A spell outside the built-in families matches its learned ranks plus itself
-- (the spellbook isn't stubbed, so none are learned).
eq(table.concat(Ind.Family(12345), ","), "12345", "an unknown spell matches its own ID")
eq(#Ind.Family(139), 10, "a built-in family")

for k, v in pairs(GRF.paintFailures) do io.write("  failure: ", k, ": ", tostring(v), "\n") end
eq(next(GRF.paintFailures), nil, "nothing failed")
done("test_indicators")
