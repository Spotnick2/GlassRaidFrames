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

eq(subs[2] and subs[2].name, "Indicators", "the page sits under Glass Raid Frames, after Click-casting")
eq(subs[2].parent, GRF.Options.category, "(its parent)")
check(not T.page._shown, "created hidden (OnShow always fires)")
T.page:Show()
check(ui.rows, "built on show")

-- The list: this class's indicators, the first selected.
eq(ui.rows[1].text._text, "My heals", "my heals listed first")
check(ui.rows[3].text._text:find("Debuffs") and ui.rows[3].text._text:find("built%-in"), "the debuff row marked built-in")
check(not ui.rows[4]._shown, "no more rows than indicators")
eq(ui.name._text, "My heals", "the selection's name in the box")
check(ui.shared._text:find("Priest"), "says the setup is shared by the class")

-- Settings reach the data and the tiles.
click(ui.mine); ui.mine._checked = false; click(ui.mine)
eq(find("myheals").mine, false, "Only mine off")
eq(slots(p1, "myheals").s1.filter, "HELPFUL", "and the tiles follow")
ui.mine._checked = true; click(ui.mine)
eq(slots(p1, "myheals").s1.filter, "HELPFUL|PLAYER", "back on")
click(ui.anchors[7])   -- bottom-left
eq(find("myheals").anchor, "BOTTOMLEFT", "the anchor grid moves it")
check(ui.anchors[7].lit._shown and not ui.anchors[3].lit._shown, "the grid lights the new corner")
ui.size:SetValue(16)
eq(find("myheals").size, 16, "the size slider")
eq(slots(p1, "myheals").s1.frame._width, 16, "(on the tiles)")
ui.x:SetValue(5); ui.y:SetValue(-6)
eq(find("myheals").x .. "," .. find("myheals").y, "5,-6", "the offset sliders")
click(ui.grow[3])
eq(find("myheals").grow, "UP", "grow direction")
ui.timer._checked = true; click(ui.timer)
eq(find("myheals").timer, true, "timer text")
ui.swipe._checked = false; click(ui.swipe)
eq(find("myheals").swipe, false, "swipe")
ui.name:SetText("  Heals  ")
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
eq(find("received").size, 20, "saved at once in combat")
check(ui.status._text:find("combat ends"), "the page says it waits for combat")
eq(#WoW.blocked, 0, "nothing touched in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(ui.status._text, "", "repainted when it lands")
eq(slots(p1, "received").s1.frame._width, 20, "and the tiles follow")

-- The preview draws every enabled indicator.
check(#ui.preview.boxes >= 3, "the preview draws the indicators")

-- Reset.
click(ui.reset)
eq(find("myheals").name, "My heals", "back to the class defaults")
eq(ui.rows[1].text._text, "My heals", "and the list follows")

eq(next(GRF.paintFailures), nil, "nothing failed")
done("test_indicator_options")
