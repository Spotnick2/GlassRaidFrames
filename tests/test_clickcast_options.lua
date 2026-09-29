-- The Click-casting options page: registered under Glass Raid Frames, shows
-- the current role's rows, captures new bindings, takes spells dragged from
-- the spellbook, cycles ranks, removes, and warns about Blizzard's side.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local SPELLS = { [2060] = { "Greater Heal", "Rank 1" }, [10963] = { "Greater Heal", "Rank 2" },
                 [10964] = { "Greater Heal", "Rank 3" }, [139] = { "Renew", "Rank 1" } }
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] end,
    GetSpellSubtext = function(id) return SPELLS[id] and SPELLS[id][2] end,
    GetSpellTexture = function(id) return SPELLS[id] and 1000 + id end,
})
-- The spellbook holds every rank as its own item (measured).
local BOOK = { 139, 2060, 10963, 10964 }
rawset(_G, "C_SpellBook", {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
    GetSpellBookItemInfo = function(i) local id = BOOK[i]; return id and { spellID = id, name = SPELLS[id][1] } end,
})
Enum.SpellBookSpellBank = { Player = 0 }
Enum.ClickBindingType = { None = 0, Interaction = 1, Spell = 2, Macro = 3, PetAction = 4 }
Enum.ClickBindingInteraction = { Target = 1, OpenContextMenu = 2 }
local profile = { { type = 1, actionID = 2, button = "RightButton", modifiers = 0 },
                  { type = 2, actionID = 17, button = "LeftButton", modifiers = 1 } }   -- no Target!
rawset(_G, "C_ClickBindings", { GetProfileInfo = function() return profile end })
rawset(_G, "GetStringFromModifiers", function(m) return m == 1 and "SHIFT" or "" end)
local cvars = { enableMouseoverCast = "1" }
rawset(_G, "C_CVar", { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v; return true end })
local cursor
rawset(_G, "GetCursorInfo", function() if cursor then return "spell", 5, "spell", cursor end end)
rawset(_G, "ClearCursor", function() cursor = nil end)
rawset(_G, "IsControlKeyDown", function() return WoW.ctrl == true end)
rawset(_G, "GetBindingAction", function() return nil end)
rawset(_G, "SetOverrideBindingClick", function() end)
rawset(_G, "ClearOverrideBindings", function() end)
rawset(_G, "GetModifiedClick", function() return "ALT" end)
local sub
Settings.RegisterCanvasLayoutSubcategory = function(parent, frame, name)
    sub = { parent = parent, frame = frame, name = name }
    return sub
end

party(1)
GlassRaidFramesCharDB = { role = "HEALER" }
local GRF = loadAddon()
local T = GRF.ClickCastOptions._test

-- Registered under the main page.
check(sub and sub.parent == GRF.Options.category, "the Click-casting page sits under Glass Raid Frames")
eq(sub.name, "Click-casting", "named Click-casting")
check(not T.page._shown, "created hidden (OnShow always fires)")
T.page:Show()
local capture = T.capture()
check(capture, "built on show")

-- Blizzard's side is shown: its Mouseover Cast (heals strangers, measured),
-- its own spell binding on Shift-Left, and its unbound Target click.
check(T.mouseoverWarn()._shown, "Mouseover Cast being on is flagged")
local bt = T.blizzList()._text
check(bt:find("SHIFT%-LeftButton"), "Blizzard's own Shift-Left spell binding is listed")
check(bt:find("Target Unit Frame"), "its unbound Target click is flagged")

-- Capture a key: press Shift + 3 → a key row, waiting for a spell.
capture._scripts.OnClick(capture, "LeftButton")          -- start listening
check(capture.listening, "listening after a click")
WoW.shift = true
capture._scripts.OnKeyDown(capture, "LSHIFT")             -- a modifier alone isn't a binding
check(capture.listening, "a bare modifier doesn't end the capture")
capture._scripts.OnKeyDown(capture, "3")
WoW.shift = false
local rowsData = GRF.ClickCast.Rows()
eq(rowsData[1] and rowsData[1].key, "SHIFT-3", "Shift+3 becomes a key binding")
local r1 = T.rows[1]
check(r1._shown and r1.spell._text:find("drag a spell"), "the new row asks for a spell")

-- Capture a click: Ctrl + right click on the capture button.
capture._scripts.OnClick(capture, "LeftButton")
WoW.ctrl = true
capture._scripts.OnClick(capture, "RightButton")
WoW.ctrl = false
eq(rowsData[2] and rowsData[2].mouse, "ctrl-2", "Ctrl + right click becomes a mouse binding")

-- Escape cancels.
capture._scripts.OnClick(capture, "LeftButton")
capture._scripts.OnKeyDown(capture, "ESCAPE")
check(not capture.listening, "Escape cancels")
eq(#rowsData, 2, "without adding a row")

-- Drag Greater Heal (top rank, as the spellbook UI hands it) onto row 1.
cursor = 10964
r1.slot._scripts.OnReceiveDrag(r1.slot)
eq(rowsData[1].spell, 10964, "the dropped spell is stored by ID")
eq(cursor, nil, "and the cursor is cleared")
eq(r1.spell._text, "Greater Heal", "the row shows it")
eq(r1.rank._text, "highest rank", "unpinned: highest rank")
check(r1.rank._shown, "a rank button when there are several ranks")

-- Cycle ranks: highest → Rank 1 → Rank 2 → Rank 3 → highest.
r1.rank._scripts.OnClick(r1.rank)
eq(rowsData[1].spell, 2060, "first click pins rank 1 (by its own ID)")
check(rowsData[1].pinned, "pinned")
eq(r1.rank._text, "Rank 1", "the button shows the rank")
r1.rank._scripts.OnClick(r1.rank)
eq(rowsData[1].spell, 10963, "then rank 2")
r1.rank._scripts.OnClick(r1.rank)
r1.rank._scripts.OnClick(r1.rank)
eq(rowsData[1].pinned, nil, "past the last rank: back to highest")
eq(rowsData[1].spell, 10964, "on the top rank's ID")

-- A single-rank spell has no rank button.
local r2 = T.rows[2]
cursor = 139
r2.slot._scripts.OnClick(r2.slot)
check(not r2.rank._shown, "Renew (one rank) shows no rank button")
-- Its binding applied to the frames.
flush()
eq(GRF.Header.children[1]:GetAttribute("ctrl-spell2"), "Renew", "the new click binding is live on the frames")

-- Remove.
r2.remove._scripts.OnClick(r2.remove)
eq(#rowsData, 1, "Remove deletes the row")
check(not T.rows[2]._shown, "and its line")
flush()
eq(GRF.Header.children[1]:GetAttribute("ctrl-spell2"), nil, "and unbinds it")

-- Turning Blizzard's Mouseover Cast off from the warning.
local offButton
for _, f in ipairs(WoW.frames) do
    if f._type == "Button" and f._text == "Turn it off" then offButton = f end
end
offButton._scripts.OnClick(offButton)
eq(cvars.enableMouseoverCast, "0", "the button turns Mouseover Cast off")
check(not T.mouseoverWarn()._shown, "and the warning goes")

-- In combat: capture is refused; edits wait (pending).
WoW.combat = true
capture._scripts.OnClick(capture, "LeftButton")
check(not capture.listening, "no capture in combat")
WoW.combat = false

eq(next(GRF.paintFailures), nil, "no failures")
done("test_clickcast_options")
