-- The Indicators page (#19): registered after Click-casting, every control
-- saves through GRF.Settings and reaches the tiles (out of combat).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local NAMES = { [139] = "Renew", [17] = "Power Word: Shield", [10060] = "Power Infusion", [6346] = "Fear Ward",
                [1022] = "Blessing of Protection", [6940] = "Blessing of Sacrifice", [29166] = "Innervate",
                [467] = "Thorns", [774] = "Rejuvenation", [8936] = "Regrowth", [2061] = "Flash Heal" }
rawset(_G, "C_Spell", { GetSpellName = function(id) return NAMES[id] end,
                        GetSpellTexture = function(id) return NAMES[id] and 100000 + id or nil end })
local cursor
rawset(_G, "GetCursorInfo", function() if cursor then return "spell", 1, nil, cursor end end)
rawset(_G, "ClearCursor", function() cursor = nil end)
local subs = {}
Settings.RegisterCanvasLayoutSubcategory = function(parent, frame, name)
    subs[#subs + 1] = { parent = parent, frame = frame, name = name }
    return subs[#subs]
end

party(2)
local GRF = loadAddon()
flush()
local Ind, T = GRF.Indicators, GRF.IndicatorOptions._test
local ui = T.ui
local function find(key) return GRF.Settings.FindIndicator(key) end
local function click(b, ...) b._scripts.OnClick(b, ...) end
local function slots(b, key) return b.grfInd.byKey[key] and b.grfInd.byKey[key].c._slots or {} end
local p1 = childFor("party1")

eq(subs[1] and subs[1].name, "Indicators", "Indicators remains under Glass Raid Frames")
eq(subs[1].parent, GRF.Options.category, "(its parent)")
check(not T.page._shown, "created hidden (OnShow always fires)")
T.page:Show()
check(ui.rows, "built on show")

-- The list: this class's indicators, the first selected.
eq(ui.rows[1].text._text, "My heals", "my heals listed first")
check(ui.rows[3].text._text:find("Debuffs") and ui.rows[3].text._text:find("built%-in"), "the debuff row marked built-in")
check(not ui.rows[4]._shown, "no more rows than indicators")
eq(ui.name._text, "My heals", "the selection's name in the box")
check(ui.shared._text:find(UnitClass("player"), 1, true), "says the setup is shared by the class (its localized name)")

-- Settings reach the data and the tiles.
click(ui.mine); ui.mine._checked = false; click(ui.mine)
eq(find("myheals").mine, false, "Only mine off")
eq(slots(p1, "myheals").s1.filter, "HELPFUL", "and the tiles follow")
ui.mine._checked = true; click(ui.mine)
eq(slots(p1, "myheals").s1.filter, "HELPFUL|PLAYER", "back on")
click(ui.anchors[7])   -- bottom-left
eq(find("myheals").anchor, "BOTTOMLEFT", "the anchor grid moves it")
check(ui.anchors[7].lit._shown and not ui.anchors[3].lit._shown, "the grid lights the new corner")
ui.size:SetValue(15)
ui.size:SetValue(16)
eq(find("myheals").size, 16, "the size slider saves at once")
eq(slots(p1, "myheals").s1.frame._width, 12, "but the tiles wait for the drag to pause")
eq(#WoW.timers, 1, "one apply scheduled for the whole drag")
WoW.flushTimers()
eq(slots(p1, "myheals").s1.frame._width, 16, "then the tiles follow")
ui.x:SetValue(5); ui.y:SetValue(-6)
WoW.flushTimers()
eq(find("myheals").x .. "," .. find("myheals").y, "5,-6", "the offset sliders")
click(ui.grow[3])
eq(find("myheals").grow, "UP", "grow direction")
ui.timer._checked = true; click(ui.timer)
eq(find("myheals").timer, true, "timer text")
ui.timer._checked = true
ui.swipe._checked = false; click(ui.swipe)
eq(find("myheals").swipe, false, "swipe")
ui.name:SetFocus()
ui.name:SetText("  Heals  ")
click(ui.timer)   -- a repaint while typing keeps the text being typed
eq(ui.name._text, "  Heals  ", "a rename being typed survives a repaint")
ui.name._scripts.OnEnterPressed(ui.name)
eq(find("myheals").name, "Heals", "renamed (trimmed)")
eq(ui.rows[1].text._text, "Heals", "the list follows")
ui.enabled._checked = false; click(ui.enabled)
eq(find("myheals").enabled, false, "disabled")
eq(p1.grfInd.byKey.myheals, nil, "the tiles drop it")
ui.enabled._checked = true; click(ui.enabled)

-- Spells: listed, reordered, removed, added by ID or by drag.
eq(ui.spellRows[1].name._text, "Renew", "spell rows")
eq(ui.spellRows[2].id._text, "17", "with their IDs")
click(ui.spellRows[2].up)
eq(table.concat(find("myheals").spells, ","), "17,139", "moved up")
eq(slots(p1, "myheals").s1.spec.candidateFilters.includeSpellIDs[17], true, "the first spot now tracks Shield")
click(ui.spellRows[1].remove)
eq(table.concat(find("myheals").spells, ","), "139", "removed")
ui.idBox:SetText("99999")
ui.idBox._scripts.OnTextChanged(ui.idBox)
check(ui.idName._text:find("unknown spell"), "an unknown ID says so")
check(ui.idAdd._enabled == false, "and can't be added")
click(ui.idAdd)   -- even if clicked anyway
check(ui.addNote._text:find("unknown spell"), "an unknown spell is refused by the setting too")
eq(#find("myheals").spells, 1, "(nothing added)")
ui.idBox:SetText("17")
ui.idBox._scripts.OnTextChanged(ui.idBox)
eq(ui.idName._text, "Power Word: Shield", "a known ID previews its name")
click(ui.idAdd)
eq(table.concat(find("myheals").spells, ","), "139,17", "added by ID")
ui.idBox:SetText("17"); click(ui.idAdd)
check(ui.addNote._text:find("already listed"), "a duplicate is refused")
cursor = 2061
ui.drop._scripts.OnReceiveDrag(ui.drop)
eq(find("myheals").spells[3], 2061, "added by dragging from the spellbook")
eq(cursor, nil, "the cursor is cleared")
click(ui.spellRows[3].remove)

-- Kinds: switching rebuilds the indicator as the new kind.
click(ui.kind[3])   -- square
eq(find("myheals").kind, "square", "kind switched")
eq(p1.grfInd.byKey.myheals.kind, "square", "the tiles rebuild it as a square")
check(ui.color._shown, "a square has a colour")
click(ui.color)
check(find("myheals").color[2] > 0.5, "the swatch cycles the palette")
click(ui.kind[1])
check(not ui.color._shown, "icons have no colour")

-- Debuffs: an aura polarity the client can't match by spell is flagged.
click(ui.aura[2])
eq(find("myheals").aura, "HARMFUL", "debuffs picked")
check(ui.help._text:find("can't be tracked"), "the page explains it can't be shown")
eq(p1.grfInd.byKey.myheals, nil, "and it isn't built")
click(ui.aura[1])

-- The built-in debuff row: its own options, can't be deleted or renamed.
click(ui.rows[3])
eq(ui.debuffs._shown, true, "the debuff row's options")
eq(ui.spells._shown, false, "instead of spells")
check(ui.delete._enabled == false and ui.name._enabled == false, "built-in: no delete, no rename")
eq(GRF.Settings.RemoveIndicator(find("debuffs")), false, "the setting refuses to delete the built-in row")
check(find("debuffs"), "(still there)")
click(ui.filter[2])
eq(find("debuffs").filter, "dispellable", "only dispellable")
eq(p1.grfInd.byKey.debuffs.c._groups.grf_debuffs.filter, "HARMFUL|RAID", "(on the tiles)")
ui.max:SetValue(5)
WoW.flushTimers()
eq(find("debuffs").max, 5, "how many")

-- Add, reorder, delete (two clicks).
click(ui.add)
local new = find("custom1")
check(new and ui.name._text == "New indicator", "a new indicator, selected")
eq(ui.rows[4].text._text, "New indicator", "listed")
click(ui.up)
eq(GRF.Indicators.Setup()[3].key, "custom1", "moved up")
cursor = 10060
ui.drop._scripts.OnClick(ui.drop)
eq(p1.grfInd.byKey.custom1 and p1.grfInd.byKey.custom1.kind, "icons", "with a spell it appears on the tiles")
click(ui.delete)
check(find("custom1"), "one click only arms Delete")
eq(ui.delete._text, "Sure?", "and asks")
click(ui.delete)
eq(find("custom1"), nil, "the second deletes")
eq(p1.grfInd.byKey.custom1, nil, "and the tiles drop it")

-- In combat edits save, show as pending, and land when combat ends.
click(ui.rows[2])
WoW.combat = true
WoW.blocked = {}
ui.size:SetValue(20)
WoW.flushTimers()
eq(find("received").size, 20, "saved at once in combat")
check(ui.status._text:find("combat ends"), "the page says it waits for combat")
eq(#WoW.blocked, 0, "nothing touched in combat")
WoW.leaveCombat()
eq(ui.status._text, "", "repainted when it lands")
eq(slots(p1, "received").s1.frame._width, 20, "and the tiles follow")

-- The preview draws every enabled indicator.
check(#ui.preview.boxes >= 3, "the preview draws the indicators")

-- Review of PR #23 ----------------------------------------------------------
-- Delete armed for one indicator doesn't carry over to it after visiting another.
click(ui.add)
click(ui.delete)
eq(ui.delete._text, "Sure?", "armed")
click(ui.rows[1])
click(ui.rows[#GRF.Indicators.Setup()])
eq(ui.delete._text, "Delete", "coming back shows Delete")
click(ui.delete)
check(find("custom1"), "and one click doesn't delete: it arms again")
click(ui.delete)
eq(find("custom1"), nil, "the confirming click deletes")

-- Another rank of a listed spell is refused (it would match the same aura).
click(ui.rows[1])
ui.idBox:SetText("25315"); NAMES[25315] = "Renew"
click(ui.idAdd)
check(ui.addNote._text:find("another rank"), "another rank of Renew is refused")

-- The cap note goes once a spell is removed.
local heals = find("myheals")
for _, id in ipairs({ 10060, 6346, 1022, 6940, 29166, 467 }) do GRF.Settings.AddIndicatorSpell(heals, id) end
GRF.Indicators.Request()
check(ui.addNote._text:find("Up to"), "a full list says so")
click(ui.spellRows[8].remove)
eq(ui.addNote._text, "", "and stops saying so below the cap")

-- A failing repaint doesn't leave the controls dead.
local realPreview = ui.preview.SetSize
ui.preview.SetSize = function() error("boom") end
GRF.IndicatorOptions.Refresh()
ui.preview.SetSize = realPreview
check(GRF.paintFailures["indicators page"], "the failed repaint is recorded")
GRF.paintFailures["indicators page"] = nil
click(ui.anchors[1])
eq(find("myheals").anchor, "TOPLEFT", "and the controls still save")

-- The preview places icons as the tiles do: tile spacing, scaled; a centred
-- debuff row is centred.
GRF.Settings.EditIndicator(heals, "grow", "LEFT")
local b1, b2 = ui.preview.boxes[1], ui.preview.boxes[2]
eq(b2._points[1][4] - b1._points[1][4], (heals.size + GRF.Indicators.GAP) * -1.6, "icons spaced like the tiles (scaled)")
GRF.Settings.EditIndicator(find("debuffs"), "anchor", "BOTTOM")
local first
for _, t in ipairs(ui.preview.boxes) do
    if t._shown and t._file == "Interface\\Icons\\Spell_Shadow_ShadowWordPain" then first = first or t end
end
eq(first._points[1][1], "BOTTOMLEFT", "a bottom-centre row is laid from its left edge")
check(first._points[1][4] < 0, "starting left of centre (the row is centred)")
GRF.Settings.EditIndicator(find("debuffs"), "anchor", "BOTTOMLEFT")

-- A rename draft belongs to the indicator it was started on (Codex review).
click(ui.rows[1])
ui.name:SetFocus()
ui.name:SetText("Draft for my heals")
click(ui.rows[2])   -- selecting another indicator commits the draft to its owner
eq(find("myheals").name, "Draft for my heals", "the draft lands on the indicator it was typed for")
eq(find("received").name, "Received", "not on the newly selected one")
eq(ui.name._text, "Received", "the box now shows the new selection")
click(ui.rows[1])
ui.name:SetFocus()
ui.name:SetText("Typed before Add")
click(ui.add)   -- Add changes the selection without touching the box
eq(find("myheals").name, "Typed before Add", "the draft still lands on its own indicator")
eq(find("custom1").name, "New indicator", "the new one keeps its name")
eq(ui.name._text, "New indicator", "and the box shows it")
click(ui.delete); click(ui.delete)
ui.name:SetFocus()
ui.name.owner = find("debuffs")   -- a draft owned by the built-in row (rename refused)
ui.name:SetText("Hacked")
ui.name:ClearFocus()
eq(find("debuffs").name, "Debuffs", "the built-in row is never renamed")
GRF.Settings.EditIndicator(find("myheals"), "name", "Heals")

-- Any rank of a known family is that family: an unlearned higher Thorns rank
-- still matches every Thorns (Codex review).
NAMES[9910] = "Thorns"
click(ui.add)
local thorns = find("custom1")
ui.idBox:SetText("9910"); click(ui.idAdd)
eq(thorns.spells[1], 467, "stored by its family's first rank")
eq(#GRF.Indicators.Family(9910), 6, "a known rank resolves to its whole family")
check(slots(p1, "custom1").s1.spec.candidateFilters.includeSpellIDs[467], "the slot matches rank 1 too")
click(ui.delete); click(ui.delete)

-- A centred debuff row is centred on the tile (Codex review): its left edge
-- half the row's width left of the tile's anchor point.
GRF.Settings.EditIndicator(find("debuffs"), "anchor", "BOTTOM")
local deb = find("debuffs")
local row = {}
for _, t in ipairs(ui.preview.boxes) do
    if t._shown and t._file == "Interface\\Icons\\Spell_Shadow_ShadowWordPain" then row[#row + 1] = t end
end
local pt = row[1]._points[1]
eq(pt[1] .. ">" .. pt[3], "BOTTOMLEFT>BOTTOM", "laid from its left edge, relative to the tile's bottom centre")
local width = deb.max * deb.size + (deb.max - 1) * GRF.Indicators.GAP
eq(pt[4], (deb.x - width / 2) * 1.6, "half the row's width left of centre")
GRF.Settings.EditIndicator(deb, "anchor", "BOTTOMLEFT")

-- A /grf ind change in combat shows on the open page at once.
WoW.combat = true
SlashCmdList.GLASSRAIDFRAMES("ind received off")
check(ui.rows[2].text._text and ui.status._text:find("combat ends"), "the open page shows it pending")
WoW.leaveCombat()
SlashCmdList.GLASSRAIDFRAMES("ind received on")

-- Reset while renaming drops the draft, on the first row and on another
-- (Codex review: a key-owned draft renamed the new default).
for _, row in ipairs({ 1, 2 }) do
    click(ui.rows[row])
    local key = GRF.Indicators.Setup()[row].key
    ui.name:SetFocus()
    ui.name:SetText("Pending rename")
    click(ui.reset)
    check(find(key).name ~= "Pending rename", "reset with a draft on row " .. row .. " keeps the default name")
    ui.name:SetFocus(); ui.name:ClearFocus()   -- a later focus loss renames nothing either
    check(find(key).name ~= "Pending rename", "(and later too, row " .. row .. ")")
end
-- /grf ind reset from chat while a draft is open: the old table is gone, the draft is dropped.
click(ui.rows[2])
ui.name:SetFocus()
ui.name:SetText("Chat reset draft")
SlashCmdList.GLASSRAIDFRAMES("ind reset")
ui.name:ClearFocus()
eq(find("received").name, "Received", "a draft for a replaced indicator is dropped")

-- Reset.
click(ui.reset)
eq(find("myheals").name, "My heals", "back to the class defaults")
eq(ui.rows[1].text._text, "My heals", "and the list follows")

eq(next(GRF.paintFailures), nil, "nothing failed")
done("test_indicator_options")
