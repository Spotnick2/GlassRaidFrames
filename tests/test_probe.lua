-- RaidProbe, a ForeverProbe module (#44): loaded on the host, driven through
-- /fp raid, its lines in the console and RaidProbeDB.log, never in chat.
-- Then its hover-key toggle (Codex review of PR #5): turning the mode off
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
rawset(_G, "UnitGroupRolesAssigned", function() return "NONE" end)   -- captured by the secrets table at load

WoW.SetUnit("player", { name = "Karuzo", class = "PRIEST", player = true })
local FP = loadForeverProbe()
local function rprobe(s) SlashCmdList.FOREVERPROBE("raid " .. s) end
-- Its SavedVariables from an earlier session (the client sets them before ADDON_LOADED).
rawset(_G, "RaidProbeDB", { log = { "1.0 an earlier session's line" }, sessions = 2 })
local ns = {}
assert(loadfile("Tools/RaidProbe/RaidProbe.lua"))("RaidProbe", ns)
assert(loadfile("Tools/RaidProbe/Layout.lua"))("RaidProbe", ns)
local T = ns._test
check(rawget(_G, "RaidProbe_test") == nil, "the test seam stays off _G")
check(rawget(SlashCmdList, "RAIDPROBE") == nil, "no /rprobe any more: /fp raid")
eq(FP.byCmd.raid, T.Probe, "/fp raid is RaidProbe")
WoW.fire("ADDON_LOADED", "RaidProbe")
eq(type(RaidProbeDB.log), "table", "the probe keeps its log in saved variables")
check(T.Probe.log == RaidProbeDB.log, "its ForeverProbe log is RaidProbeDB.log, bound at ADDON_LOADED")
eq(RaidProbeDB.sessions, 3, "it counts its loads")
local function consoleHas(pattern)
    for _, l in ipairs(FP.lines) do
        if l.m == "RaidProbe" and l.text:find(pattern) then return true end
    end
    return false
end
local function logHas(pattern)
    for _, l in ipairs(RaidProbeDB.log) do if l:find(pattern) then return true end end
    return false
end
check(consoleHas("session 3, build"), "the load line reaches the console")
check(logHas("session 3, build"), "and the saved log")
check(logHas("an earlier session's line"), "the earlier session's lines are kept")
check(not consoleHas("EARLY"), "the host was ready before RaidProbe's ADDON_LOADED")
check(not chatHas("session"), "nothing in chat")
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
-- A failed call is the host's Try line: "label: ERROR msg" or "label: MISSING".
local function failures()
    local n = 0
    for _, l in ipairs(FP.lines) do
        if l.m == "RaidProbe" and (l.text:find(": ERROR", 1, true) or l.text:find(": MISSING", 1, true)) then n = n + 1 end
    end
    return n
end
local before = failures()
for _, cmd in ipairs({ "ind", "ind party1", "ind reconf", "ind reconf", "ind src", "ind src party1", "ind state", "ind cost", "ind ids" }) do
    local ok, err = pcall(rprobe, cmd)
    check(ok, "/fp raid " .. cmd .. " runs: " .. tostring(err))
end
eq(failures() - before, 0, "no probe call failed")
eq(#T.P.indContainers, 8, "the panel has its 8 test containers")
eq(T.P.indUnit, "party1", "ind <unit> rebinds the panel")
check(consoleHas("RAID_IN_COMBAT=out"), "src reports which filters keep each aura")
check(consoleHas("cost: 40 tiles"), "cost reports its build")
check(consoleHas("state 6: slot 1 shown="), "state reports each stacked slot")
check(consoleHas("state 1: .* shown, .* hidden, .* unknown"), "state reports each row group")
check(logHas("cost: 40 tiles"), "the lines are saved too")

-- Codex review of #20: a secret shown state is unknown, never "hidden".
local hots = T.P.indByKey.RP_IND_HOTS
local frames = { { IsShown = function() return WoW.Secret("shown") end },
                 { IsShown = function() return WoW.Secret("shown") end },
                 { IsShown = function() return false end } }
hots.GetAuraGroupFrameCount = function() return #frames end
hots.GetAuraGroupFrame = function(_, _, i) return frames[i] end
rprobe("ind state")
check(consoleHas("state 1: 3 buttons: 0 shown, 1 hidden, 2 unknown"), "secret reads count as unknown, a plain false as hidden")
hots.GetAuraGroupFrameCount, hots.GetAuraGroupFrame = nil, nil

-- The button look the client would apply (initializeFrame).
local button = CreateFrame("Button", nil, UIParent)
T.indButton(16, 30, { 1, 0, 0 }, UIParent)(button)
T.indButton(16)(button)
eq(failures() - before, 0, "the probe button initialiser runs cleanly")

-- A throwing call is reported, not raised: the host's Try contract.
rprobe("ind")   -- the panel exists; make one of its calls throw
local realSetUnit = T.P.indContainers[1].SetUnit
T.P.indContainers[1].SetUnit = function() error("boom") end
rprobe("ind party2")
T.P.indContainers[1].SetUnit = realSetUnit
check(failures() > before, "a throwing client call is logged as ERROR")

-- The command list, and clearing the log in place.
newChat()
rprobe("")
check(consoleHas("/fp raid <command>:") and consoleHas("  ind %- "), "/fp raid alone lists the commands")
local log = RaidProbeDB.log
rprobe("log clear")
check(RaidProbeDB.log == log, "log clear keeps the bound table")
eq(#log, 1, "and empties it in place, then logs the clear")
check(logHas("log cleared") and consoleHas("log cleared"), "the line after a clear is in both")
check(#WoW.chat == 0, "nothing reached chat")

-- worldkey (#63): a check passes only on a press that reached the key's
-- button, under lockdown for the combat steps (Codex P2 on #64: no press,
-- or none in combat, used to pass the fallback step).
C_Spell.IsSpellHarmful = function(id) return id == 589 end
C_Spell.IsSpellHelpful = function(id) return id == 2050 end
local realName = C_Spell.GetSpellName
C_Spell.GetSpellName = function(id) return (id == 589 or id == 594) and "Shadow Word: Pain" or realName(id) end
rawset(_G, "C_SpellBook", { IsSpellKnown = function(id) return id == 589 or id == 2050 end })
check(T.worldSetup(), "worldkey binds a harmful and a helpful key")
local fallback = T.worldCheck("harm", "other", true)
check(not fallback(), "no press: the in-combat fallback step fails")
local harmKey = _G["RaidProbeWorldKeyharm"]
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
check(not fallback(), "a press out of combat: still fails")
WoW.combat = true
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
check(fallback(), "a press in combat with nothing cast: passes")
check(not fallback(), "and the next step starts from zero presses")
-- Run #188 (rev 2 failed both): the bare name casts the highest rank (594),
-- and the owner's own heal came after it. Any cast of the step counts, at
-- any rank, and a failed one too (out of range: the macro chose the spell).
local cast = T.worldCheck("harm", "spell", true)
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-1", 594)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo Mistwalker", "guid-2", 2050)
check(cast(), "a press in combat that sent the key's spell at another rank, then a heal: passes")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "guid-3", 594)
check(cast(), "a failed cast of the key's spell: the macro still chose it")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo Mistwalker", "guid-4", 2050)
check(not cast(), "another spell only: the key's spell wasn't chosen")
check(fallback() == false, "and an empty step still fails")
WoW.combat = false
local outside = T.worldCheck("harm", "spell")
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.combat = true
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-5", 594)
WoW.combat = false
check(outside(), "an out-of-combat step accepts any cast")
WoW.combat = true
harmKey:GetScript("PostClick")(harmKey, "LeftButton", false)
WoW.combat = false
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Elder Mottled Boar", "guid-6", 594)
WoW.combat = true
check(not cast(), "an in-combat step ignores a cast sent outside combat")
WoW.combat = false

-- The group layout (#69): Layout.lua joins the same module.
local L = ns._layout
check(L and FP.byCmd.raid == T.Probe, "Layout.lua is part of RaidProbe")
rprobe("")
check(consoleHas("  layout %- "), "/fp raid lists layout")
local A = L.LAYOUT

-- The size the client's configureChildren gives the plan's sets
-- (SecureGroupHeaders.lua:143-255): ceil(n/5) columns in a raid, a row in a party.
local function size(set, n, cw, ch)
    local w, h, cols, per = L.expectSize(set, n, cw or A.W, ch or A.H)
    return string.format("%gx%g %s/%s", w, h, tostring(cols), tostring(per))
end
eq(size(A.COLUMNS, 2), "96x126 1/2", "a 2-player raid: one column of 2")
eq(size(A.COLUMNS, 5), "96x324 1/5", "5: one column of 5")
eq(size(A.COLUMNS, 10), "198x324 2/5", "10: 2 columns")
eq(size(A.COLUMNS, 11), "300x324 3/5", "11: 3 columns")
eq(size(A.COLUMNS, 40), "810x324 8/5", "40: 8 columns")
eq(size(A.COLUMNS, 0), "96x0.1 0/0", "no cells: the header's minimum (a raid set)")
eq(size(A.ROW, 1), "96x60 1/1", "solo: one cell")
eq(size(A.ROW, 5), "504x60 1/5", "a party of 5: one row")
eq(size(A.ROW, 10), "504x126 2/5", "a raid of 10 in the party set: rows of 5 stacked")
eq(size(A.ROW, 0), "0.1x60 0/0", "no cells: the header's minimum (the party set)")
eq(size(A.PETS, 12, A.PET_W, A.PET_H), "134x316 2/10", "12 raid pets: columns of 10")

-- What the client lists for each set (both keep the other kind's attributes
-- on: GlassUI#30).
local group = { raid = false, inGroup = false, members = 0, sub = 0 }
WoW.raid = nil
rawset(_G, "IsInGroup", function() return group.inGroup end)
rawset(_G, "GetNumGroupMembers", function() return group.members end)
rawset(_G, "GetNumSubgroupMembers", function() return group.sub end)
eq(L.wantCells(A.ROW), 1, "solo: the row shows you")
eq(L.wantCells(A.COLUMNS), 1, "solo: the columns show you too")
group.inGroup, group.members, group.sub = true, 2, 1
eq(L.wantCells(A.ROW), 2, "a party of 2")
eq(L.wantCells(A.COLUMNS), 2, "and a party (a raid fallen back to one in combat)")
-- showSolo is the player's setting: off, showParty still lists the party.
local noSolo = setmetatable({ showSolo = false }, { __index = A.COLUMNS })
eq(L.wantCells(noSolo), 2, "the columns list a party with show-solo off")

-- The build: 40 cells, 40 raid pets, five party pets under the first five
-- cells, the pet header on the grid's right edge, the driver registered.
local drivers = {}
rawset(_G, "RegisterStateDriver", function(f, state, values) drivers[#drivers + 1] = { f, state, values } end)
rawset(_G, "SecureCmdOptionParse", function() return "show" end)
UIParent._width, UIParent._height = 1920, 1080
check(L.build(), "the layout builds out of combat")
local LP = L.LP
eq(#LP.cells .. " " .. #LP.petCells .. " " .. #LP.partyPets, "40 40 5", "40 cells, 40 pet cells, 5 party pets")
eq(drivers[1] and drivers[1][1], LP.holder, "the visibility driver is on the party-pet holder")
eq(drivers[1] and drivers[1][3], "[group:raid] hide; show", "with the plan's condition")
local pp, cp = { LP.pets:GetPoint(1) }, { LP.partyPets[2]:GetPoint(1) }
check(pp[1] == "TOPLEFT" and pp[2] == LP.grid and pp[3] == "TOPRIGHT" and pp[4] == 6, "pets on the grid's right edge, 6 apart")
check(cp[1] == "TOP" and cp[2] == LP.cells[2] and cp[3] == "BOTTOM" and cp[5] == -6, "partypet1 under the second cell")
check(WoW.unitWatch[LP.partyPets[5]], "party pets are unit-watched")
eq(LP.set, A.ROW, "built with 2 members: the row")
eq(LP.grid:GetAttribute("point"), "LEFT", "the row's point")
eq(LP.grid:GetAttribute("showParty"), true, "and it lists a party")
local gp = { LP.grid:GetPoint(1) }
check(gp[1] == "BOTTOM" and math.abs(gp[5] - (152 + 68)) < 0.01 and gp[4] == 960, "bottom centre at baseline + 68")

-- Precreation (Codex P2 on #70): the client's pass over 40 cells gives child 1
-- the column anchor too, and the one-column pass back keeps it. A header
-- that anchors child 1 as the client does (SecureGroupHeaders.lua:201-205),
-- showing a party of 2 once startingIndex is back to 1.
local function fakeHeader()
    local h = { attrs = { point = "LEFT", columnAnchorPoint = "BOTTOM", unitsPerColumn = 5 }, kids = {} }
    local function anchor(c, p, ...)
        for i = #c._points, 1, -1 do if c._points[i][1] == p then table.remove(c._points, i) end end
        c:SetPoint(p, ...)
    end
    function h:GetAttribute(k) return self.attrs[k] end
    function h:SetAttribute(k, v) self.attrs[k] = v if self.shown then self:layout() end end
    function h:Show() self.shown = true self:layout() end
    function h:layout()
        local start = self.attrs.startingIndex or 1
        local n = start <= 0 and 1 - start or 2
        for i = 1, math.max(n, #self.kids) do
            local c = self.kids[i]
            if not c then
                c = CreateFrame("Button", nil, UIParent)
                self.kids[i], self.attrs["child" .. i] = c, c
            end
            if i > n then
                c:Hide()
                c:ClearAllPoints()
            elseif i == 1 then
                c:Show()
                anchor(c, self.attrs.point, self, self.attrs.point, 0, 0)
                if n > self.attrs.unitsPerColumn then
                    anchor(c, self.attrs.columnAnchorPoint, self, self.attrs.columnAnchorPoint, 0, 0)
                end
            else
                c:Show()
                anchor(c, self.attrs.point, self.kids[i - 1], "RIGHT", 6, 0)
            end
        end
    end
    return h
end
local kids, stale = L.precreate(fakeHeader(), 40)
eq(#kids .. " " .. stale, "40 2", "precreation leaves child 1 with two anchors (logged)")
eq(kids[1]:GetNumPoints(), 1, "cleared and re-laid: child 1 has its point only")
eq(kids[2]:GetNumPoints(), 1, "and child 2 its own")

-- The batch: the complete set (no party key left over), _ignore off after,
-- anchors cleared or kept.
for _, c in ipairs(LP.cells) do c._points = { { "LEFT" } } end
L.applySet(A.COLUMNS, false)
eq(LP.cells[3]:GetNumPoints(), 1, "the swap experiment keeps the anchors")
L.applySet(A.COLUMNS, true)
eq(drivers[#drivers][1] == LP.holder and drivers[#drivers][3], "hide", "the columns re-register the holder's driver as hide")
eq(LP.cells[3]:GetNumPoints(), 0, "the batch clears them")
eq(LP.grid:GetAttribute("_ignore"), nil, "_ignore is off after the batch")
eq(LP.grid:GetAttribute("groupBy"), "GROUP", "the columns group by subgroup")
eq(LP.grid:GetAttribute("yOffset"), -6, "the columns' yOffset")
gp = { LP.grid:GetPoint(1) }
check(math.abs(gp[5] - 152) < 0.01, "the columns' bottom on the baseline")

-- The grid check, on a party of 2 laid out by hand (the stub has no layout).
L.applySet(A.ROW, true)
eq(drivers[#drivers][3], "[group:raid] hide; show", "the row gives it the raid condition back")
eq(LP.grid:GetAttribute("groupBy"), nil, "the row clears groupBy (INDEX order: pets under owners)")
eq(LP.grid:GetAttribute("groupingOrder"), nil, "and groupingOrder")
local function place(f, x, y, w, h) f._center, f._width, f._height = { x, y }, w, h end
place(LP.grid, 960, 220 + 30, 198, 60)
for i, c in ipairs(LP.cells) do c._shown = i <= 2; c._points = i <= 2 and { { "LEFT" } } or {} end
LP.cells[1]._attrs.unit, LP.cells[2]._attrs.unit = "player", "party1"
place(LP.cells[1], 960 - 51, 250, 96, 60)
place(LP.cells[2], 960 + 51, 250, 96, 60)
local ok, why = L.check({ combat = false })()
check(ok, "a party of 2 in one row holds: " .. tostring(why))
place(LP.cells[2], 960 - 51, 250 - 66, 96, 60)
ok, why = L.check({ combat = false })()
check(not ok and why:find("1 columns x 2 rows, want 2 x 1"), "a cell left under the first fails: " .. tostring(why))
place(LP.cells[2], 960 + 51, 250, 96, 60)
place(LP.grid, 960, 250 + 10, 198, 60)
ok, why = L.check({ combat = false })()
check(not ok and why:find("bottom"), "a grid off the baseline fails: " .. tostring(why))
place(LP.grid, 960, 250, 198, 60)
ok, why = L.check({ combat = true })()
check(not ok and why:find("not in combat"), "an in-combat step out of combat fails")
group.sub = 2
ok, why = L.check({ combat = false })()
check(not ok and why:find("2 cells shown, the roster lists 3"), "a missing cell fails: " .. tostring(why))
group.sub = 1
-- Each step's roster (Codex P2 on #70): Next before the change can't pass.
ok, why = L.check({ combat = false, roster = "party" })()
check(ok, "the party step in a party holds: " .. tostring(why))
ok, why = L.check({ combat = false, roster = "raid" })()
check(not ok and why:find("the group is party, the step wants raid"), "a conversion step in an unchanged party fails: "
    .. tostring(why))
group.inGroup = false
ok, why = L.check({ roster = "party" })()
check(why:find("the group is solo, the step wants party"), "a rejoin step still alone fails: " .. tostring(why))
ok, why = L.check({ roster = "solo" })()
check(not why:find("the step wants"), "the solo step alone holds: " .. tostring(why))
group.inGroup = true

-- M2 and M4 on the same hand layout.
place(LP.pets, 960 + 99 + 6 + 32, 280 - 0.05, 64, 0.1)
ok, why = L.check({ combat = false, pets = true })()
check(ok, "pets on the grid's top-right hold: " .. tostring(why))
place(LP.pets, 960 + 99 + 6 + 32, 300, 64, 0.1)
ok = L.check({ combat = false, pets = true })()
check(not ok, "pets left behind fail")
WoW.units.pet = { name = "Wolf" }
LP.partyPets[1]._shown = false
ok, why = L.check({ combat = false, partyPets = true })()
check(not ok and why:find("pet exists but isn't shown"), "a pet not shown in a party fails: " .. tostring(why))
LP.partyPets[1]._shown = true
place(LP.partyPets[1], 960 - 51, 220 - 6 - 15, 96, 30)
ok, why = L.check({ combat = false, partyPets = true })()
check(ok, "the pet under its owner holds: " .. tostring(why))
place(LP.partyPets[1], 960 + 51, 220 - 6 - 15, 96, 30)
ok, why = L.check({ combat = false, partyPets = true })()
check(not ok and why:find("pet isn't under player"), "a pet under the wrong cell fails: " .. tostring(why))
-- Under the columns the holder must be hidden (its driver says hide).
L.applySet(A.COLUMNS, true)
ok, why = L.check({ partyPets = true })()
check(not ok and why:find("holder shown=true"), "a holder shown under the columns fails: " .. tostring(why))
LP.holder._shown = false
ok, why = L.check({ partyPets = true })()
check(not why:find("holder"), "hidden under the columns holds: " .. tostring(why))
LP.holder._shown = true
L.applySet(A.ROW, true)
WoW.units.pet = nil

-- Two rows back to one without the clear (a raid of 6 falling to 5 in combat):
-- passes while the first cell keeps its size, and leaves the set applied.
for i, c in ipairs(LP.cells) do c._points = i <= 2 and { { "LEFT" } } or {} end
ok, why = L.collapse()
check(ok, "collapse: a first cell that keeps its size holds: " .. tostring(why))
eq(LP.grid:GetAttribute("unitsPerColumn"), 5, "and the row's unitsPerColumn is back")
eq(LP.cells[1]:GetNumPoints(), 0, "and the set re-applied with the clear (no stale anchor left)")
place(LP.cells[1], 960 - 51, 250, 198, 60)
ok, why = L.collapse()
check(not ok and why:find("w=198"), "a stretched first cell fails: " .. tostring(why))
place(LP.cells[1], 960 - 51, 250, 96, 60)
LP.cells[2]._shown = false
ok, why = L.collapse()
check(not ok and why:find("needs two cells"), "collapse needs a party of 2: " .. tostring(why))
LP.cells[2]._shown = true

-- Out of combat, the set follows the member count; in combat it waits.
-- A raid of 5 or fewer keeps the row (GlassUI#30); 6 get the columns.
WoW.raid = { player = { index = 1, subgroup = 1 } }
L.sync()
eq(LP.set, A.ROW, "a raid of 2: still the row")
group.members = 6
WoW.combat = true
L.sync()
eq(LP.set, A.ROW, "in combat the set waits")
WoW.combat = false
L.sync()
eq(LP.set, A.COLUMNS, "out of combat, 6 members get the columns")
group.members = 2
L.sync()
eq(LP.set, A.ROW, "back to 2: the row")
-- The forced columns (a raid of 6+ the beta can't gather), released after combat.
L.force()
eq(LP.set, A.COLUMNS, "forced: the columns with 2 members")
WoW.combat = true
check(not L.released(), "released only out of combat")
eq(LP.set, A.COLUMNS, "and the columns stay meanwhile")
WoW.combat = false
check(L.released(), "after combat: released")
eq(LP.set, A.ROW, "and the row applies")
eq(LP.force, nil, "the force is gone")
WoW.raid = nil

-- The candidate driver (GlassUI#35): a plain frame behind [@raid1,exists],
-- judged by the frame and by the parse. The driver itself is the client's.
rawset(_G, "SecureCmdOptionParse", function(v)
    if v == A.CANDIDATE then return UnitExists("raid1") and "hide" or "show" end
    return "show"
end)
check(L.buildCandidate(), "the candidate builds out of combat")
eq(drivers[#drivers][1] == LP.candidate and drivers[#drivers][3], "[@raid1,exists] hide; show",
    "its driver is the unit test")
LP.candidate._shown = true
ok, why = L.candidateHolds({ roster = "party", combat = false })()
check(ok, "a party: shown holds: " .. tostring(why))
WoW.raid = { player = { index = 1, subgroup = 1 } }
WoW.units.raid1 = { name = "Me" }
WoW.combat = true
ok, why = L.candidateHolds({ roster = "raid", combat = true })()
check(not ok and why:find("shown=true in a raid=true"), "a raid in combat, still shown, fails: " .. tostring(why))
LP.candidate._shown = false
ok, why = L.candidateHolds({ roster = "raid", combat = true })()
check(ok, "hidden in a raid in combat holds: " .. tostring(why))
ok, why = L.candidateHolds({ roster = "party", combat = true })()
check(not ok and why:find("the step wants party"), "the step's roster is required: " .. tostring(why))
WoW.units.raid1 = nil
ok, why = L.candidateHolds({ roster = "raid" })()
check(not ok and why:find("parses show"), "a parse that disagrees fails: " .. tostring(why))
WoW.raid, WoW.combat = nil, false

-- The shipped layout's check (grid): Glass Raid Frames stood in for by a
-- table with what the check reads (LayoutState, Layout._test.L, Profile).
local GC = L.G
ok, why = L.gridCheck({})()
check(not ok and why:find("not loaded"), "no Glass Raid Frames: the check fails: " .. tostring(why))
local function frame() return CreateFrame("Button", nil, UIParent) end
local fake = { cells = {}, petCells = {}, partyPets = { frame() } }
for i = 1, 3 do fake.cells[i] = frame() end
fake.grid, fake.pets, fake.holder = frame(), frame(), frame()
fake.set = { name = "row" }
fake.cellW, fake.cellH = 96, 60
local prof = { showPets = false }
local state = { mode = "hud", l = 960 - 99, b = 220, w = 198, h = 60, top = 280, base = 152 }
local grf = { layoutOn = true, role = "HEALER", Profile = function() return prof end,
    LayoutState = function() return state end,
    Layout = { _test = { L = fake }, HeaderSize = function(_, n) return n * 96 + (n - 1) * 6, 60 end } }
rawset(_G, "GlassRaidFrames", grf)
place(fake.grid, 960, 250, 198, 60)
fake.cells[1]._attrs.unit, fake.cells[2]._attrs.unit = "player", "party1"
place(fake.cells[1], 960 - 51, 250, 96, 60)
place(fake.cells[2], 960 + 51, 250, 96, 60)
fake.cells[1]._points, fake.cells[2]._points, fake.cells[3]._points = { { "LEFT" } }, { { "LEFT" } }, {}
fake.cells[3]._shown = false
fake.holder._shown = false
group.inGroup, group.sub, group.members = true, 1, 2
ok, why = L.gridCheck({ roster = "party", combat = false })()
check(ok, "a party of 2 on its baseline, centred, as announced: holds: " .. tostring(why))
ok, why = L.gridCheck({ roster = "raid" })()
check(not ok and why:find("the step wants raid"), "the step's roster is required: " .. tostring(why))
state.top = 300
ok, why = L.gridCheck({ combat = false })()
check(not ok and why:find("state top"), "a grid that isn't where it's announced fails: " .. tostring(why))
state.top = 280
place(fake.grid, 960, 250, 198, 70)
ok, why = L.gridCheck({ combat = false })()
check(not ok and why:find("formula"), "a grid of another size than the client's formula fails: " .. tostring(why))
place(fake.grid, 960, 250, 198, 60)
-- In combat: compared with where combat began, not with the state.
WoW.combat = true
L.gridEv._scripts.OnEvent(L.gridEv, "PLAYER_REGEN_DISABLED")
state.top = 999
ok, why = L.gridCheck({ combat = true, held = true })()
check(ok, "in combat, held where it began: holds (the state isn't refreshed in combat): " .. tostring(why))
place(fake.grid, 960, 260, 198, 60)
ok, why = L.gridCheck({ combat = true, held = true })()
check(not ok and why:find("bottom moved"), "a grid whose bottom moved in combat fails: " .. tostring(why))
place(fake.grid, 960, 250, 198, 60)
GC.inCombat = 1
ok, why = L.gridCheck({ combat = true })()
check(not ok and why:find("in combat"), "an announcement in combat fails: " .. tostring(why))
GC.inCombat = 0
WoW.combat = false
state.top = 280
ok, why = L.gridCheck({ after = true })()
check(not ok and why:find("nothing announced after combat"), "nothing announced after combat fails: " .. tostring(why))
GC.announced = GC.atCombat + 1
ok = L.gridCheck({ after = true })()
check(ok, "announced after combat: holds")
-- Pets: the column reserved in a raid's announced width.
prof.showPets = true
WoW.raid = { player = { index = 1, subgroup = 1 } }
fake.set = { name = "row" }
ok, why = L.gridCheck({ pets = true })()
check(not ok and why:find("reserved"), "a raid's pet column not in the announced width fails: " .. tostring(why))
state.w, state.l = 198 + 70, 960 - 134
ok, why = L.gridCheck({ pets = true })()
check(ok, "reserved: holds: " .. tostring(why))
WoW.raid = nil
-- A blocked action on Glass Raid Frames fails every later check.
L.gridEv._scripts.OnEvent(L.gridEv, "ADDON_ACTION_BLOCKED", "GlassRaidFrames", "Frame:Show()")
L.gridEv._scripts.OnEvent(L.gridEv, "ADDON_ACTION_BLOCKED", "OtherAddon", "OtherFrame:Hide()")
ok, why = L.gridCheck({})()
check(not ok and why:find("blocked: ADDON_ACTION_BLOCKED Frame:Show") and not why:find("Other"),
    "an action blocked on Glass Raid Frames fails (others' don't count): " .. tostring(why))
GC.blocked = {}
-- The legacy grid after /grf layout off.
grf.layoutOn = false
state.mode = "legacy"
ok = L.legacyCheck()
check(not ok, "layout off without the eight headers: not the legacy grid")
rawset(_G, "GlassRaidFramesGroup8", frame())
ok, why = L.legacyCheck()
check(ok, "layout off, eight headers, announced as legacy: holds: " .. tostring(why))
-- The glide procedure's steps drive Glass Raid Frames' own settings.
local previewing, modes, mode = nil, {}, "hud"
grf.Settings = {
    Preview = function(n) previewing = n; return true end,
    SetLayoutMode = function(m) modes[#modes + 1] = m; mode = m; return true end,
}
grf.Layout.Previewing = function() return previewing end
grf.Layout.ModeOf = function() return mode end
check(L.previewAt(40)(), "a preview of 40 holds when it shows")
eq(previewing, 40, "asked for 40")
grf.Settings.Preview = function() return false, "not in combat" end
check(not L.previewAt(10)(), "a refused preview fails")
grf.Settings.Preview = function(n) previewing = n; return true end
check(L.previewAt(nil)() and previewing == nil, "ending it holds when it ended")
L.switchMode("side")()
L.switchMode(nil)()
eq(table.concat(modes, ","), "side,hud", "the mode goes to the side and back to what it was")
GC.blocked, GC.inCombat = {}, 0
check(L.cleanRun(), "a run with nothing blocked is clean")
GC.inCombat = 1
check(not L.cleanRun(), "an announcement in combat isn't")
GC.inCombat = 0
rawset(_G, "GlassRaidFrames", nil)
rawset(_G, "GlassRaidFramesGroup8", nil)
check(#WoW.chat == 0, "the layout probe wrote nothing to chat")

done("test_probe")
