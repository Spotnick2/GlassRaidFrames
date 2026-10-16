dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
local spells = { [2060] = { "Greater Heal", "Rank 1" }, [10963] = { "Greater Heal", "Rank 2" },
    [10964] = { "Greater Heal", "Rank 3" }, [139] = { "Renew", "Rank 1" }, [90001] = { "Greater Heal", "Rank 2" } }
local learned = { [2060] = true, [10963] = true, [139] = true, [90001] = true }
local book = { 2060, 10963, 10964, 139, 90001 }
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return spells[id] and spells[id][1] end,
    GetSpellSubtext = function(id) return spells[id] and spells[id][2] end,
    GetSpellTexture = function() return 1 end,
    GetSpellInfo = function(s)
        for _, id in ipairs(book) do
            if learned[id] and s == spells[id][1] .. "(" .. spells[id][2] .. ")" then return { spellID = id } end
        end
    end,
})
Enum.SpellBookSpellBank = { Player = 0 }
Enum.SpellBookItemType = { Spell = 1, FutureSpell = 2 }
rawset(_G, "C_SpellBook", {
    IsSpellKnown = function(id) return learned[id] == true end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
    GetSpellBookItemInfo = function(i)
        local id = book[i]
        return { spellID = id, name = spells[id][1], itemType = learned[id] and 1 or 2 }
    end,
})
rawset(_G, "GetBindingAction", function(key) return key == "W" and "MOVEFORWARD" or "" end)
rawset(_G, "ClearOverrideBindings", function() end)
rawset(_G, "GetModifiedClick", function() return "ALT" end)
GlassRaidFramesCharDB = { role = "HEALER", profiles = { HEALER = { bindings = {
    { mouse = "ctrl-1", spell = 10963, pinned = true, custom = { keep = true } },
    { key = "1", spell = 139 }, { key = "2", spell = 88888, pinned = true },
} } } }
local GRF = loadAddon()
local E, CC, API = GRF.ClickCastEditor, GRF.ClickCast, GRF.API
local saved = E.Copy(GlassRaidFramesCharDB)
local state = E.New("HEALER")
local rows = E.Rows("HEALER")
state:Select(rows[1])
state:SetInput("mouse", "shift-1")
check(E.Equal(saved, GlassRaidFramesCharDB), "editing never changes SavedVariables")
state:Select(rows[1])
eq(state.draft.mouse, "ctrl-1", "cancel restores input")
check(not state:Dirty(), "unchanged draft")
check(not state:Save(), "unchanged save is refused")
state:SetInput("key", "1")
local ok, _, conflict = state:Save()
check(not ok and conflict == rows[2], "collision needs explicit replacement")
state:Replace(conflict)
check(state:Save(), "explicit replacement commits")
eq(#rows, 2, "replacement removes one conflicting row")
check(rows[1].custom.keep and rows[1].pinned, "unknown fields and pinned ranks survive")
eq(rows[2].spell, 88888, "unavailable legacy entry survives")

local other = E.New("CASTER")
other:NewDraft(139); other:SetInput("key", "1")
check(other:Save(), "same input in another role is independent")
eq(GRF.role, "HEALER", "editing profile never changes active role")

state:Select(rows[1]); state:SetInput("key", "3")
rows[1].spell = 139
check(not state:Save(), "stale draft does not overwrite external edit")
state:Select(rows[1]); state:SetInput("key", "3")
WoW.combat = true
check(not state:Save(), "combat refuses commit")
eq(state.draft.key, "3", "combat preserves draft")
WoW.combat = false
check(state:Save(), "draft saves after combat")
eq(#WoW.blocked, 0, "editor touches no protected frame in combat")

state:Select(nil); state:BeginQuick()
check(state:Stage({ key = "4", spell = 139 }), "quick bind stages")
eq(#rows, 2, "staging is not active")
ok, _, conflict = state:Stage({ key = "4", spell = 10963 })
check(not ok and conflict == state.staged[1], "staged conflicts are detected")
check(state:Stage({ key = "4", spell = 10963 }, conflict), "explicit staged replacement")
check(state:Stage({ mouse = "shift-5", spell = 139 }), "mouse five stages")
check(state:ApplyQuick(), "atomic batch applies")
eq(#rows, 4, "both entries committed")
state:BeginQuick(); state:Stage({ key = "5", spell = 139 }); state:DiscardQuick()
eq(#rows, 4, "discard leaves saved rows alone")
state:BeginQuick(); state:Stage({ key = "5", spell = 139 })
rows[1].custom.changed = true
check(not state:ApplyQuick(), "batch rejects external changes")
eq(#state.staged, 1, "failed apply retains batch")
state:DiscardQuick()

state:BeginQuick(); state:Stage({ key = "5", spell = 139 }); state:Stage({ key = "6", spell = 10963 })
local beforeBatch = E.Copy(rows)
learned[10963] = nil
check(not state:ApplyQuick(), "a spell becoming unavailable blocks the entire batch")
check(E.Equal(beforeBatch, rows), "failed batch has no partial saves")
learned[10963] = true; state:DiscardQuick()

eq(E.InputID({ key = "SHIFT-CTRL-BUTTON4" }), E.InputID({ mouse = "ctrl-shift-4" }), "physical input aliases conflict")
eq(E.BindingText({ key = "CTRL-SHIFT-1" }), "Ctrl + Shift + 1", "readable keyboard labels")
eq(E.BindingText({ mouse = "alt-5" }), "Alt + Mouse 5", "readable extra button")
check(not E.InputID({ key = "ESCAPE" }), "Escape cannot bind")
check(not E.InputID({ mouse = "6" }), "unsupported mouse button rejected")
check(E.Matches({ key = "CTRL-1", spell = 139 }, "control renew"), "search matches modifiers and spell names")

local catalog = API.ClickCastCatalog()
local ranks = API.ClickCastRanks(2060)
eq(#ranks, 2, "only learned validated ranks")
eq(ranks[2], 10963, "spellbook order, not numeric order")
local ambiguous = API.ClickCastRanks(90001)
eq(#ambiguous, 1, "same name alone cannot identify a family")
learned[10964] = true
WoW.fire("SPELLS_CHANGED")
eq(#API.ClickCastRanks(2060), 3, "spell change invalidates catalog")
eq(rows[1].spell, 139, "catalog refresh never rewrites saved rows")
eq(CC.AttributeValue({ spell = 10963, pinned = true }), 10963, "fixed rank remains exact ID")
eq(CC.AttributeValue({ spell = 2060 }), "Greater Heal", "Highest retains established runtime behavior")

check(CC.Commit("HEALER", { mouse = "shift-1", action = "macro", macrotext = "/cast [@mouseover] Renew" }), "custom mouse macro")
eq(GRF.Header.children[1]:GetAttribute("shift-macrotext1"), "/cast [@mouseover] Renew", "macro attribute applied")
local macro = E.Rows("HEALER")[#E.Rows("HEALER")]
check(CC.Commit("HEALER", { mouse = "shift-1", action = "target" }, macro, E.Copy(macro)), "macro becomes target")
eq(GRF.Header.children[1]:GetAttribute("shift-macrotext1"), nil, "obsolete macro attribute removed")
eq(GRF.Header.children[1]:GetAttribute("shift-type1"), "target", "unit action installed")
check(CC.Commit("HEALER", { key = "9", action = "togglemenu" }), "keyboard menu action")
eq(CC._test.keyButtons["9"]:GetAttribute("unit"), "mouseover", "keyboard action addresses hovered member")
local menu = E.Rows("HEALER")[#E.Rows("HEALER")]
check(CC.Commit("HEALER", { key = "9", spell = 139 }, menu, E.Copy(menu)), "keyboard unit action becomes spell")
eq(CC._test.keyButtons["9"]:GetAttribute("unit"), nil, "obsolete keyboard unit cleared")
eq(CC._test.keyButtons["9"]:GetAttribute("type"), "macro", "established spell macro path restored")
eq(CC.CastText({ spell = 90001, pinned = true }), "Greater Heal(Rank 2)", "fixed rank text remains localized")
check(not E.Validate({ key = "W", action = "target" }), "non-action base binding restriction retained")
check(not table.concat(CC.Warnings({ mouse = "alt-1", action = "target" }), ";"):find("Self Cast"), "unit actions have no spell Self Cast warning")
check(not E.Validate({ key = "8", action = "macro", macrotext = string.rep("x", 256) }), "macro limit enforced without truncating")
eq(E.Preview("HEALER", { key = "4" }), "Greater Heal · Highest", "preview describes saved action")
eq(E.Preview("HEALER", { key = "2" }), "Unavailable spell #88888 · Pinned · spell #88888 · Unavailable", "preview retains unknown rank")
eq(E.Preview("CASTER", { mouse = "ctrl-2" }), "Open unit menu · Default", "preview matches wildcard default")
eq(E.Preview("CASTER", { key = "9" }), "Unbound", "preview uses selected profile")
eq(next(GRF.paintFailures), nil, "no failures")
done("test_clickcast_editor")
