-- Execute the editor's real UI handlers; no casting APIs exist in this preview.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
local spells = { [2060] = { "Greater Heal", "Rank 1" }, [10963] = { "Greater Heal", "Rank 2" }, [139] = { "Renew", "Rank 1" } }
local book = { 2060, 10963, 139 }
for i = 1, 30 do spells[90000 + i] = { "Spell " .. i, "" }; book[#book + 1] = 90000 + i end
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return spells[id] and spells[id][1] end,
    GetSpellSubtext = function(id) return spells[id] and spells[id][2] end,
    GetSpellTexture = function() return 1 end,
    GetSpellInfo = function(text)
        for id, spell in pairs(spells) do if text == spell[1] .. "(" .. spell[2] .. ")" then return { spellID = id } end end
    end,
})
Enum.SpellBookSpellBank = { Player = 0 }; Enum.SpellBookItemType = { Spell = 1, FutureSpell = 2 }
rawset(_G, "C_SpellBook", {
    IsSpellKnown = function(id) return spells[id] ~= nil end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
    GetSpellBookItemInfo = function(i) local id = book[i]; return { spellID = id, name = spells[id][1], itemType = 1 } end,
})
Enum.ClickBindingType = { Interaction = 1, Spell = 2, Macro = 3, PetAction = 4 }
Enum.ClickBindingInteraction = { Target = 1, OpenContextMenu = 2 }
rawset(_G, "C_ClickBindings", { GetProfileInfo = function() return { { type = 2, button = "LeftButton", modifiers = 1 } } end })
rawset(_G, "GetStringFromModifiers", function() return "SHIFT" end)
local cvars = { enableMouseoverCast = "1" }
rawset(_G, "C_CVar", { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v end })
local cursor
rawset(_G, "GetCursorInfo", function() if cursor then return "spell", 1, "spell", cursor end end)
rawset(_G, "ClearCursor", function() cursor = nil end)
rawset(_G, "IsControlKeyDown", function() return WoW.ctrl == true end)
rawset(_G, "GetBindingAction", function() return "" end)
rawset(_G, "ClearOverrideBindings", function() end)
rawset(_G, "GetModifiedClick", function() return "ALT" end)
local subpages = {}
Settings.RegisterCanvasLayoutSubcategory = function(_, _, name) subpages[name] = true end
GlassRaidFramesCharDB = { role = "HEALER", profiles = { HEALER = { bindings = { { mouse = "ctrl-1", spell = 10963, pinned = true } } } } }
local GRF = loadAddon()
local CCO, E = GRF.ClickCastOptions, GRF.ClickCastEditor
local T, saved = CCO._test, E.Copy(GlassRaidFramesCharDB)
local function click(b) b._scripts.OnClick(b, "LeftButton") end
local function key(k, hold)
    local r = T.keyboard(); r._scripts.OnKeyDown(r, k)
    if not hold then r._scripts.OnKeyUp(r, k) end
end
local function text(box, s) box:SetText(s); box._scripts.OnTextChanged(box, true) end
local function spell(id) for _, r in ipairs(T.ui.spells) do if r.group and r.group.spell == id and r._shown then return r end end end
check(not subpages["Click-casting"], "obsolete subpage removed")
check(subpages.Indicators, "Indicators registration retained")
GRF.Options._test.panel:Show()
WoW.combat = true
click(GRF.Options._test.controls.clickcast)
local u, root = T.ui, T.root()
check(not T.keyboard():IsShown() and not T.keyboard()._keyboardEnabled, "first combat open has no keyboard listener")
key("1"); key("ESCAPE")
check(root:IsShown(), "combat key callbacks do not close or capture")
CCO.RequestClose()
check(not root:IsShown(), "mouse close remains usable in combat")
WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED")
click(GRF.Options._test.controls.clickcast)
check(root and root:IsShown(), "main settings button opens editor")
click(GRF.Options._test.controls.clickcast)
check(root:IsShown(), "settings entry keeps an already-open editor visible")
check(E.Equal(saved, GlassRaidFramesCharDB), "opening preserves SavedVariables")
key("6")
check(T.keyboard()._propagateKeyboard, "opening does not consume gameplay keys")
check(not T.recording(), "opening never records")
check(u.warningText:find("SHIFT%-LeftButton"), "Blizzard binding conflict remains visible")
check(u.warningText:find("Target Unit Frame"), "missing Blizzard target binding remains visible")
eq(u.rows[1].note._text, "Default · Applies with modifiers unless overridden", "implicit defaults are labeled")

-- Record is a separate activation button; only fresh presses inside the pad count.
click(u.add)
check(T.recording(), "Add enters explicit recording")
eq(T.state().draft.mouse, nil, "activation click is not captured")
u.capture._scripts.OnMouseUp(u.capture, "LeftButton")
eq(T.state().draft.mouse, nil, "release without a press in the area is ignored")
key("LSHIFT"); check(T.recording(), "bare modifier keeps listening")
WoW.ctrl = true; WoW.shift = true; key("1", true); WoW.ctrl = false; WoW.shift = false
eq(T.state().draft.key, "CTRL-SHIFT-1", "modifiers captured canonically")
check(not T.keyboard()._propagateKeyboard, "recorded key does not reach gameplay")
key("1", true)
check(not T.keyboard()._propagateKeyboard, "held recorded key does not repeat into gameplay")
T.keyboard()._scripts.OnKeyUp(T.keyboard(), "1"); check(not T.keyboard()._propagateKeyboard, "recorded key release is swallowed")
key("6"); check(T.keyboard()._propagateKeyboard, "next ordinary key propagates")
eq(#E.Rows("HEALER"), 1, "recording is only a draft")
click(spell(10963)); check(u.save:IsEnabled(), "choosing a spell completes the draft")
click(u.save)
eq(#E.Rows("HEALER"), 2, "Save creates one binding")
local original = T.state().original
check(not original.pinned, "new spell defaults to Highest")

click(u.record); key("ESCAPE")
eq(T.state().draft.key, original.key, "Escape keeps previous input")
check(not T.recording(), "Escape stops recording")
click(u.record); u.spellSearch:SetFocus(); text(u.spellSearch, "Renew"); key("R")
check(not T.recording() and T.keyboard()._propagateKeyboard, "search focus suspends recording")
eq(T.state().draft.key, original.key, "typing does not rebind")
u.spellSearch:ClearFocus(); text(u.spellSearch, "")
click(u.record); click(u.cancel)
eq(T.state().draft.key, original.key, "Cancel click never becomes an input")

click(u.rank); click(u.ranks[3])
check(T.state().draft.pinned, "explicit rank pins draft")
eq(original.pinned, nil, "rank edit leaves active row alone")
click(u.roles.CASTER)
check(u.modal:IsShown(), "profile change guards a dirty draft")
click(u.modal.buttons[3]); eq(T.state().role, "HEALER", "Keep editing retains role")
CCO.RequestClose(); click(u.modal.buttons[1])
check(not root:IsShown(), "Save then close")
check(E.Rows("HEALER")[2].pinned, "guard Save persisted the fixed rank")
CCO.Open()

-- Both creation workflows share drafts; mouse five is supported.
click(u.cancel); T.state():Select(nil); CCO.Refresh()
click(spell(139)); check(u.create:IsShown(), "spell-first has explicit Create binding")
click(u.create); WoW.ctrl = true
u.capture._scripts.OnMouseDown(u.capture, "Button5"); u.capture._scripts.OnMouseUp(u.capture, "Button5"); WoW.ctrl = false
eq(T.state().draft.mouse, "ctrl-5", "mouse five captures in the explicit area")
click(u.save); eq(#E.Rows("HEALER"), 3, "spell-first saved")
click(u.record); WoW.ctrl = true
u.capture._scripts.OnMouseDown(u.capture, "LeftButton"); u.capture._scripts.OnMouseUp(u.capture, "LeftButton"); WoW.ctrl = false
check(u.resolve:IsShown() and not u.save:IsEnabled(), "conflict blocks Save")
click(u.resolve); click(u.modal.buttons[2]); key("ESCAPE"); click(u.cancel)
eq(#E.Rows("HEALER"), 3, "another-input and cancel preserve both saved assignments")

click(u.quick); check(T.state().quick, "Quick Bind explicit mode")
local renew = spell(139)
key("7"); eq(#T.state().staged, 0, "Quick Bind does not capture unarmed")
renew._scripts.OnEnter(renew); key("7")
eq(#T.state().staged, 1, "armed entry stages")
eq(#E.Rows("HEALER"), 3, "staged entry is not live")
renew._scripts.OnEnter(renew); u.browser._scripts.OnMouseWheel(u.browser, -1); key("8")
eq(#T.state().staged, 1, "scroll disarms Quick Bind")
renew._scripts.OnEnter(renew); key("ESCAPE")
eq(#T.state().staged, 1, "Escape retains staged changes")
click(u.apply); eq(#E.Rows("HEALER"), 4, "Apply commits batch")
click(u.quick); renew._scripts.OnEnter(renew); key("8"); click(u.discard)
eq(#E.Rows("HEALER"), 4, "Discard batch leaves saved behavior unchanged")
click(u.quick); renew._scripts.OnEnter(renew)
renew._scripts.OnMouseDown(renew, "LeftButton"); renew._scripts.OnMouseUp(renew, "LeftButton")
check(u.modal:IsShown() and u.modal.title._text:find("Target unit"), "Quick Bind names implicit target before replacing it")
eq(#T.state().staged, 0, "default click is not staged before approval")
click(u.modal.buttons[2]); eq(#T.state().staged, 0, "another input preserves default")
renew._scripts.OnEnter(renew)
renew._scripts.OnMouseDown(renew, "RightButton"); renew._scripts.OnMouseUp(renew, "RightButton")
check(u.modal.title._text:find("Open unit menu"), "Quick Bind names implicit menu")
click(u.modal.buttons[1]); eq(#T.state().staged, 1, "default replacement stages after approval")
click(u.discard)

-- Preview is an ordinary frame and does not invoke a cast, menu, or macro API.
u.preview._scripts.OnEnter(u.preview); key("7")
check(u.previewResult._text:find("Renew"), "preview reports saved spell")
eq(u.preview._template, nil, "preview has no secure template")
eq(next(u.preview._attrs), nil, "preview has no action attributes")
u.preview._scripts.OnLeave(u.preview)
click(u.add); key("9"); click(u.tabs.macro)
text(u.macroName, "My macro"); text(u.macroText, "/cast [@mouseover] Renew")
click(u.tabs.macro)
eq(T.state().draft.macrotext, "/cast [@mouseover] Renew", "clicking selected tab retains macro draft")
u.macroText:SetFocus(); key("X"); check(T.keyboard()._propagateKeyboard, "macro text remains normal input")
u.macroText:ClearFocus(); click(u.save)
local beforePreview = E.Copy(GlassRaidFramesCharDB)
u.preview._scripts.OnEnter(u.preview); key("9")
check(u.previewResult._text:find("My macro"), "macro preview is descriptive")
check(E.Equal(beforePreview, GlassRaidFramesCharDB), "preview cannot save or alter bindings")
u.preview._scripts.OnLeave(u.preview)
text(u.macroText, string.rep("/stopmacro\n", 20))
check(u.macroScroll.child:GetHeight() > u.macroScroll:GetHeight(), "multiline macro content can scroll")
u.macroText._scripts.OnCursorChanged(u.macroText, 0, -300, 1, 16)
check(u.macroScroll:GetVerticalScroll() > 0, "macro cursor scrolls into view")
click(u.cancel)

click(u.record); key("0"); WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED")
check(not u.save:IsEnabled() and not T.recording(), "combat pauses saving and capture")
check(not T.keyboard():IsShown(), "combat hides listener even if last captured key disabled propagation")
key("1"); key("ESCAPE")
check(root:IsShown(), "combat key handling leaves editor and draft alone")
eq(T.state().draft.key, "0", "combat preserves draft")
GRF.Settings.SetRole("caster")
eq(T.state().role, "HEALER", "external active-role change cannot move the draft")
check(u.profile._text:find("Active: Caster"), "active and edited roles distinguished")
WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED"); click(u.cancel)
check(T.keyboard():IsShown() and T.keyboard()._propagateKeyboard, "combat end restores propagating keyboard listener")
eq(#WoW.blocked, 0, "no protected changes in combat")

-- >14 saved rows, independent scrolls, and future host integration.
for i = 1, 25 do E.Rows("HEALER")[#E.Rows("HEALER") + 1] = { key = "F" .. i, spell = 139 } end
CCO.Refresh(); check(#u.rows > 14, "binding table has no old 14-row cap")
u.table:SetVerticalScroll(104); u.browser:SetVerticalScroll(68); CCO.Refresh()
eq(u.table:GetVerticalScroll(), 104, "refresh retains table scroll")
eq(u.browser:GetVerticalScroll(), 68, "browser scroll is independent")
local dock = CreateFrame("Frame", nil, UIParent); dock:SetSize(900, 600)
local content = CCO.Open(dock)
eq(content:GetParent(), dock, "content mounts into a supplied host")
eq(content, root, "docking reuses editor content and state")
check(u.save:GetWidth() > 140 and u.browser:GetHeight() >= 70, "compact layout keeps controls usable")
click(u.browse)
eq(T.state().draft, nil, "Browse returns to action-first creation without a selection")
local closed = false
CCO.RequestClose(function() closed = true end)
check(closed and not root:IsShown(), "host navigation callback runs after close guard")
-- Reconciliation warnings use saved-row identity, not the selected draft copy.
GRF.Settings.SetRole("healer")
local blockedRow = { key = "W", spell = 139 }
E.Rows("HEALER")[#E.Rows("HEALER") + 1] = blockedRow
rawset(_G, "GetBindingAction", function(k) return k == "W" and "MOVEFORWARD" or "" end)
GRF.ClickCast.Request(); CCO.Open(); T.state():Select(blockedRow); CCO.Refresh()
check(u.warningText:find("MOVEFORWARD"), "saved-row installation failure appears in warnings with draft selected")
local found
for _, r in ipairs(u.rows) do if r.data == blockedRow then found = r end end
check(found and found.note._text:find("MOVEFORWARD"), "table identifies uninstalled saved binding")
local clientReads = 0
local originalProfile = C_ClickBindings.GetProfileInfo
C_ClickBindings.GetProfileInfo = function() clientReads = clientReads + 1; return originalProfile() end
text(u.tableSearch, "W"); text(u.tableSearch, ""); text(u.spellSearch, "Renew")
eq(clientReads, 0, "typing search does not reread Blizzard binding profile")
WoW.fire("CVAR_UPDATE")
check(clientReads > 0, "client settings event invalidates warning cache")
eq(next(GRF.paintFailures), nil, "no reported failures")
done("test_clickcast_options")
