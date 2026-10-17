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
-- A navigation guard may save over the very row being selected.
local function savedWidget(row)
    for _, r in ipairs(u.rows) do if r.data == row and r:IsShown() then return r end end
    error("saved row is not visible")
end
text(u.spellSearch, "")
local source = GRF.ClickCast.Commit("HEALER", { key = "ALT-F1", spell = 139 })
local replaced = GRF.ClickCast.Commit("HEALER", { key = "ALT-F2", spell = 10963 })
click(savedWidget(source)); click(u.record)
WoW.alt = true; key("F2"); WoW.alt = false
click(u.resolve); click(u.modal.buttons[1])
click(savedWidget(replaced))
check(u.modal:IsShown(), "row navigation guards the pending replacement")
click(u.modal.buttons[1])
local replacement = E.Conflict(E.Rows("HEALER"), { key = "ALT-F2" })
check(replacement and replacement ~= replaced and replacement.spell == 139, "guard saves approved replacement")
eq(T.state().original, replacement, "navigation selects current saved assignment, not deleted row")
click(u.record); WoW.alt = true; key("F3"); WoW.alt = false
click(u.save)
check(T.state().original.key == "ALT-F3" and not T.state():Dirty(), "destination remains editable after guarded replacement")
local editedReplacement = T.state().original
click(u.cancel)
eq(T.state().draft.key, "ALT-F3", "Cancel restores a saved destination after replacement navigation")

-- A transient icon picker belongs to the draft that opened it.
local macroA = GRF.ClickCast.Commit("HEALER", { key = "CTRL-F1", action = "macro", name = "A", macrotext = "/cast [@mouseover] Renew" })
local macroB = GRF.ClickCast.Commit("HEALER", { key = "CTRL-F2", action = "macro", name = "B", macrotext = "/cast [@mouseover] Renew" })
click(savedWidget(macroA)); click(u.macroIcon)
check(u.iconList:IsShown(), "macro icon picker opens")
local staleIcon = u.icons[2]
click(savedWidget(macroB))
check(not u.iconList:IsShown(), "row navigation dismisses the previous icon picker")
click(staleIcon)
check(not T.state():Dirty() and T.state().draft.icon == nil, "stale icon callback cannot edit the next binding")
click(u.macroIcon); click(u.icons[2])
eq(T.state().draft.icon, u.icons[2].texture, "current draft can still choose an icon")
click(u.cancel); click(u.macroIcon); click(savedWidget(editedReplacement))
check(not u.iconList:IsShown(), "spell selection dismisses the icon picker")
click(savedWidget(macroA)); click(u.macroIcon); click(u.roles.CASTER)
check(not u.iconList:IsShown() and T.state().role == "CASTER", "profile navigation dismisses the icon picker")
click(staleIcon)
check(T.state().draft == nil, "stale picker cannot create a draft in another profile")
click(u.roles.HEALER); click(savedWidget(macroA)); click(u.macroIcon); click(u.tabs.spell)
check(not u.iconList:IsShown(), "action navigation dismisses the icon picker")
click(u.cancel); click(u.macroIcon); CCO.RequestClose(); CCO.Open()
check(not u.iconList:IsShown(), "closing and reopening cannot retain an old icon picker")
-- Material comparison repaints only this editor's decoration. Keep an active
-- draft/capture, focus, scroll offsets and unrelated consumers intact.
local sharedStyle = E.Copy(GRF.Glass.STYLE)
local foreign = GRF.Glass.Apply(CreateFrame("Frame", nil, UIParent), "small")
local otherGlass = LibStub("LibGlass-1.0"):New()
local other = otherGlass.Apply(CreateFrame("Frame", nil, UIParent), "large")
local foreignTint, foreignRim = E.Copy(foreign.tint._color), foreign.rim:GetAlpha()
local otherTint, otherRim = E.Copy(other.tint._color), other.rim:GetAlpha()
click(u.add); key("F10"); click(u.tabs.macro)
text(u.macroText, "/cast [@mouseover] Renew"); u.macroText:SetFocus()
local draft, originalState = E.Copy(T.state().draft), T.state()
local savedMaterial = E.Copy(GlassRaidFramesCharDB)
u.table:SetVerticalScroll(52); u.browser:SetVerticalScroll(34)
local material = T.material
local paneHeight = material.panes[1]:GetHeight()
check(CCO.SetMaterialPreview("baseline"), "baseline comparison available without reopening")
check(u.macroText:HasFocus(), "material switch retains text focus")
check(not material.panes[1]:IsShown(), "baseline removes new content backing")
local shellGlass = T.shell().glass
eq(shellGlass.rim:GetAlpha(), shellGlass.editorBase.rim, "baseline restores original rim")
check(not shellGlass.reflect.rim:IsShown(), "baseline hides added reflections")
u.macroText:ClearFocus(); click(u.record)
check(T.recording(), "recording before comparison")
check(CCO.SetMaterialPreview("hybrid"), "hybrid comparison available")
check(T.recording(), "material switch does not stop recording")
eq(T.state(), originalState, "comparison does not replace editor state")
check(E.Equal(T.state().draft, draft), "comparison preserves changed draft")
check(E.Equal(GlassRaidFramesCharDB, savedMaterial), "comparison never writes SavedVariables")
eq(u.table:GetVerticalScroll(), 52, "material switch retains table scroll")
eq(u.browser:GetVerticalScroll(), 34, "material switch retains browser scroll")
check(material.panes[1]:IsShown() and shellGlass.reflect.rim:IsShown(), "hybrid restores panes and directional rim")
local acceptedTint = E.Copy(shellGlass.tint._color)
local acceptedBacking = E.Copy(material.panes[1]._color)
local acceptedControl = E.Copy(u.add.glass.tint._color)
local acceptedTop = shellGlass.reflect.top._gradient[2].a
local acceptedBottom = shellGlass.reflect.rim._gradient[2].a
check(CCO.SetMaterialPreview("reflective"), "outer reflection comparison available")
check(E.Equal(shellGlass.tint._color, acceptedTint), "reflection refinement preserves accepted shell fill")
check(E.Equal(material.panes[1]._color, acceptedBacking), "reflection refinement preserves content backing")
check(E.Equal(u.add.glass.tint._color, acceptedControl), "reflection refinement preserves control state")
eq(shellGlass.reflect.rim._gradient[2].a, acceptedBottom, "reflection refinement preserves quiet bottom edge")
check(shellGlass.reflect.top._gradient[2].a > acceptedTop, "upper-left highlight strengthens")
-- The accepted treatment is LibGlass's Reflect, repainted unchanged after hybrid.
for _, k in ipairs({ "rim", "top", "header" }) do
    local r = shellGlass.reflect[k]
    check(r._gradient[2].a == r.glassStops[2][4] and r._gradient[3].a == r.glassStops[3][4],
        "reflective paints Reflect's own " .. k .. " gradient")
end
eq(shellGlass.reflect.header:GetHeight(), 125, "header reflection ends above the content at 138")
check(T.recording() and E.Equal(T.state().draft, draft), "reflection comparison preserves recording and draft")
local acceptedReflection = E.Copy(shellGlass.reflect.header._gradient)
check(CCO.SetMaterialPreview("altstable"), "AltStable comparison available")
check(E.Equal(shellGlass.tint._color, { 0.13, 0.16, 0.22, 0.24 }), "clear shell uses AltStable tint independently of content")
check(not shellGlass.editorBacking:IsShown(), "clear shell has no stacked reading backing")
eq(shellGlass.rim:GetAlpha(), 1, "clear shell keeps full-strength rim")
eq(shellGlass.wash.glassPeak, 0.18, "clear shell restores material wash")
check(shellGlass.editorTitleBand:IsShown() and #shellGlass.editorTitleBand._masks == 1, "title gradient is shown and masked")
eq(shellGlass.editorTitleBand._gradient[2].a, 0.05, "title gradient bottom matches AltStable")
eq(shellGlass.editorTitleBand._gradient[3].a, 0.16, "title gradient top matches AltStable")
eq(material.panes[1]._color[4], 1, "reading surface stays opaque under clear shell")
check(E.Equal(u.add.glass.tint._color, acceptedControl), "clear shell leaves controls unchanged")
check(T.recording() and E.Equal(T.state().draft, draft), "clear comparison preserves draft and recording")
CCO.SetMaterialPreview("reflective")
check(E.Equal(shellGlass.reflect.header._gradient, acceptedReflection), "accepted reflection restores exactly")
check(E.Equal(shellGlass.tint._color, acceptedTint) and E.Equal(material.panes[1]._color, acceptedBacking), "accepted shell and content fills restore exactly")
check(shellGlass.editorBacking:IsShown() and not shellGlass.editorTitleBand:IsShown(), "accepted backing and title layers restore")
CCO.SetMaterialPreview("hybrid")
eq(shellGlass.reflect.top._gradient[2].a, acceptedTop, "accepted upper highlight restores exactly")
check(E.Equal(GRF.Glass.STYLE, sharedStyle), "comparison leaves GRF shared material settings unchanged")
check(E.Equal(foreign.tint._color, foreignTint) and foreign.rim:GetAlpha() == foreignRim, "other GRF surfaces unchanged")
check(E.Equal(other.tint._color, otherTint) and other.rim:GetAlpha() == otherRim, "separate library consumer unchanged")
check(not CCO.SetMaterialPreview("unknown"), "comparison rejects invalid preset")
check(T.recording(), "invalid preset leaves capture alone")
key("ESCAPE"); click(u.cancel)
text(u.tableSearch, "nothing matches")
eq(material.panes[1]:GetHeight(), paneHeight, "content backing does not follow filtered rows")
check(not u.delete:IsEnabled(), "fixture has a disabled control")
local disabledTextAlpha = u.delete.text:GetAlpha()
CCO.SetMaterialPreview("baseline"); CCO.SetMaterialPreview("hybrid")
check(not u.delete:IsEnabled(), "comparison does not enable a disabled button")
eq(u.delete.text:GetAlpha(), disabledTextAlpha, "disabled text opacity unchanged")
check(u.delete.glass.wash._gradient[3].a < u.add.glass.wash._gradient[3].a, "disabled wash remains dimmed through gradient")
CCO.Open(dock)
eq(material.panes[1]:GetHeight(), 450, "backing resizes with hosted editor")
eq(material.panes[1]:GetObjectType(), "Texture", "backing cannot intercept input")
eq(next(GRF.paintFailures), nil, "no reported failures")
done("test_clickcast_options")
