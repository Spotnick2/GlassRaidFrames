-- Hostable click-casting editor. Open(parent) mounts the content in GlassUI or
-- another host. Only the fallback shell owns movement, resizing and scaling.
-- Hosts call RequestClose(callback) before navigating away from a draft.
local GRF = GlassRaidFrames
local CC, E, API, Glass = GRF.ClickCast, GRF.ClickCastEditor, GRF.API, GRF.Glass
local CCO = {}
GRF.ClickCastOptions = CCO
CCO.BindingText, CCO.Ranks = E.BindingText, API.ClickCastRanks
local ROLE_NAMES = { HEALER = "Healer", CASTER = "Caster", MELEE = "Melee", TANK = "Tank" }
-- Existing game assets used by Clique's action catalog on the target client.
local ACTION_ICONS = { target = 132331, togglemenu = 132212, macro = 134332 }
local root, shell, host, state, keyboard
local externalWarnings
local ui = { rows = {}, spells = {}, ranks = {}, fields = {}, roles = {}, tabs = {}, icons = {} }
local recording, armed, mouseDown, previewArmed, refreshing, message
local consumed = {}
local refresh, layout, guard, showRanks, startRecord, selectRow
-- Temporary local material comparison. No shared STYLE or library instance is
-- mutated; baseline snapshots belong only to surfaces created by this editor.
local material = { mode = "reflective", surfaces = {}, panes = {} }

local function paintPane(pane)
    pane:SetColorTexture(0.072, 0.082, 0.10, material.mode == "altstable" and 1 or 0.94)
    pane:SetShown(material.mode ~= "baseline")
end

local function paintShellReflection(g)
    if not g.editorLayers then return end
    local enhanced = material.mode == "reflective"
    local rim, top, reflection = unpack(g.editorLayers)
    -- Only the upper light changes. Keep the accepted bottom-edge alpha,
    -- reflection extent, shell fill and content backing exactly as before.
    rim:SetGradient("VERTICAL", CreateColor(0.55, 0.65, 0.75, 0.035), CreateColor(0.84, 0.88, 0.91, enhanced and 0.52 or 0.48))
    top:SetGradient("HORIZONTAL", CreateColor(0.88, 0.91, 0.93, enhanced and 0.58 or 0.45), CreateColor(0.65, 0.73, 0.8, 0.035))
    reflection:SetGradient("VERTICAL", CreateColor(0.77, 0.81, 0.85, 0), CreateColor(0.77, 0.81, 0.85, enhanced and 0.105 or 0.085))
end

local function materialTint(g, accent)
    g.editorAccent = accent
    local t = g.editorBase.tint
    if material.mode == "baseline" then
        if accent then Glass.SetSurfaceTint(g, 0.12, 0.75, 1, accent == "hover" and 0.3 or 0.25)
        else Glass.SetSurfaceTint(g, t[1], t[2], t[3], GRF.SMOKED) end
    elseif accent or g.editorSelected then
        Glass.SetSurfaceTint(g, 0.06, 0.24, 0.32, 0.88)
    elseif g.editorKind == "shell" then
        if material.mode == "altstable" then Glass.SetSurfaceTint(g, 0.13, 0.16, 0.22, 0.24)
        else Glass.SetSurfaceTint(g, 0.085, 0.095, 0.115, 0.78) end
    elseif g.editorKind == "control" then
        Glass.SetSurfaceTint(g, 0.095, 0.11, 0.135, 0.90)
    else
        Glass.SetSurfaceTint(g, 0.055, 0.07, 0.09, 0.86)
    end
end

local function paintMaterial(g)
    local base, hybrid = g.editorBase, material.mode ~= "baseline"
    -- Restore the undimmed region values before changing their bases, then
    -- reapply the original disabled state through LibGlass's gradient handling.
    Glass.SetSurfaceEnabled(g, true)
    local shellSurface = g.editorKind == "shell"
    local clearShell = shellSurface and material.mode == "altstable"
    g.rim:SetAlpha(hybrid and (shellSurface and 0.12 or 0.22) or base.rim)
    g.dark:SetAlpha(hybrid and (shellSurface and 0.55 or 0.35) or base.dark)
    g.grain:SetAlpha(hybrid and 0 or base.grain)
    g.shadow:SetAlpha(hybrid and (shellSurface and 0.18 or 0.05) or base.shadow)
    Glass.SetWash(g, hybrid and (g.editorKind == "control" and 0.025 or 0) or base.wash)
    if hybrid then Glass.SetEdge(g, shellSurface and 0 or 0.10, shellSurface and 0 or 0.015, 0.12, 3)
    else Glass.SetEdge(g, base.edge, base.edge * base.glow, base.edge * base.bottom, base.glowh) end
    if g.editorBacking then
        g.editorBacking:SetColorTexture(0.03, 0.03, 0.035, hybrid and shellSurface and 0.55 or 0.82)
        g.editorBacking:SetShown(not clearShell)
    end
    for _, layer in ipairs(g.editorLayers or {}) do layer:SetShown(hybrid and not clearShell) end
    if shellSurface then
        -- AltStable's clean/clear shell, independently of the reading panels.
        -- Restore the original geometry when comparing previous treatments.
        local S = Glass.SIZES[clearShell and "thin" or g.size]
        g.rim:SetTexture(Glass.MEDIA .. S.rim); g.dark:SetTexture(Glass.MEDIA .. S.dark)
        if clearShell then
            g.rim:SetAlpha(1); g.dark:SetAlpha(1); g.grain:SetAlpha(0); g.shadow:SetAlpha(0.30)
            Glass.SetWash(g, 0.18); Glass.SetEdge(g, 0, 0, 0)
        end
        g.editorTitleBand:SetShown(clearShell)
    end
    paintShellReflection(g)
    materialTint(g, g.editorAccent)
    Glass.SetSurfaceEnabled(g, g.editorEnabled ~= false)
end

local function shellReflections(f, g)
    local S = Glass.SIZES[g.size]
    -- Existing sliced rim texture supplies rounded geometry. Alpha lives in
    -- the gradient itself on Forever, never in SetAlpha on gradient textures.
    local rim = g.top:CreateTexture(nil, "OVERLAY", nil, 6)
    rim:SetAllPoints(f); rim:SetTexture(Glass.MEDIA .. S.rim)
    rim:SetTextureSliceMargins(S.rimMargin, S.rimMargin, S.rimMargin, S.rimMargin)
    rim:SetTextureSliceMode((Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched) or 0)
    local top = g.top:CreateTexture(nil, "OVERLAY", nil, 7)
    top:SetColorTexture(1, 1, 1, 1)
    top:SetPoint("TOPLEFT", f, "TOPLEFT", S.maskMargin, -1)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.maskMargin, -1); top:SetHeight(1)
    local reflection = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    reflection:SetColorTexture(1, 1, 1, 1); reflection:AddMaskTexture(g.mask)
    reflection:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    reflection:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); reflection:SetHeight(125)
    g.editorLayers = { rim, top, reflection }
    -- SkinTitleBand's white canvas and gradient, clipped by the shell mask.
    -- This editor's title occupies 52 UI units; no content or input frame moves.
    local titleBand = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    titleBand:SetColorTexture(1, 1, 1, 1); titleBand:AddMaskTexture(g.mask)
    titleBand:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBand:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); titleBand:SetHeight(52)
    titleBand:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.05), CreateColor(1, 1, 1, 0.16))
    g.editorTitleBand = titleBand
end

-- Developer-only, session-only comparison; repaint decoration without refresh,
-- rebuilding frames, changing focus, stopping capture or touching draft state.
function CCO.SetMaterialPreview(mode)
    if mode ~= "baseline" and mode ~= "hybrid" and mode ~= "reflective" and mode ~= "altstable" then return false end
    material.mode = mode
    for _, g in ipairs(material.surfaces) do paintMaterial(g) end
    for _, pane in ipairs(material.panes) do paintPane(pane) end
    return true
end

local function at(f, parent, x, y, w, h)
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); f:SetSize(w, h)
end
local function font(parent, text, size)
    local f = Glass.Font(parent, size or 13)
    f:SetTextColor(0.91, 0.94, 1); f:SetText(text)
    return f
end
local function surface(f, small, kind)
    local g = Glass.Apply(f, small and "small" or "large")
    local tint = Glass.STYLE.tint
    Glass.SetSurfaceTint(g, tint[1], tint[2], tint[3], GRF.SMOKED)
    -- Like GlassChat, omit the wash on reading panels. Forever ignores
    -- SetAlpha on this gradient; the setter also preserves disabled dimming.
    Glass.SetWash(g, small and 0.06 or 0)
    if not small then
        -- GlassQuestTracker's reading backing: below the material, above its
        -- shadow, clipped to the same mask. Keep live frames out of the text.
        local backing = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        backing:SetAllPoints(f); backing:AddMaskTexture(g.mask)
        backing:SetColorTexture(0.03, 0.03, 0.035, 0.82)
        g.editorBacking = backing
    end
    g.editorKind = kind or (small and "control" or "panel")
    g.editorBase = { tint = { tint[1], tint[2], tint[3] }, rim = g.rim:GetAlpha(), dark = g.dark:GetAlpha(),
        grain = g.grain:GetAlpha(), shadow = g.shadow:GetAlpha(), wash = small and 0.06 or 0,
        edge = Glass.STYLE.edge, glow = Glass.EDGE.glow, bottom = Glass.EDGE.bottom, glowh = Glass.EDGE.glowh }
    if kind == "shell" then shellReflections(f, g) end
    material.surfaces[#material.surfaces + 1] = g
    paintMaterial(g)
    f.glass = g
    return g
end
local function tooltip(f, text)
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:SetOwner(f, "ANCHOR_RIGHT"); tip:SetText(text, 0.91, 0.94, 1, 1, true); tip:Show() end
end
local function hideTooltip()
    local tip = rawget(_G, "GameTooltip")
    if tip then tip:Hide() end
end
local function stopCapture() recording, armed, mouseDown, previewArmed = nil, nil, nil, nil end
local function syncKeyboard()
    if not keyboard then return end
    consumed = {}
    if InCombatLockdown() then
        -- An ordinary child can hide in combat. Do not call restricted
        -- keyboard setters, even when the editor was first opened in combat.
        keyboard:Hide()
    else
        if not keyboard.initialized then keyboard:EnableKeyboard(true); keyboard.initialized = true end
        keyboard:SetPropagateKeyboardInput(true); keyboard:Show()
    end
end
local function clearFocus() for _, field in ipairs(ui.fields) do field:ClearFocus() end end
local function hasFocus()
    local getFocus = rawget(_G, "GetCurrentKeyBoardFocus")
    if getFocus and getFocus() then return true end
    for _, field in ipairs(ui.fields) do if field:HasFocus() then return true end end
    return false
end
local function sizeMacro()
    if not ui.macroMeasure then return end
    local text = ui.macroText:GetText() or ""
    ui.macroMeasure:SetWidth(math.max(40, ui.macroText:GetWidth() - 20))
    ui.macroMeasure:SetText(text)
    local height = ui.macroMeasure:GetStringHeight()
    if type(height) ~= "number" or height <= 0 then
        local _, lines = text:gsub("\n", "")
        height = (lines + math.ceil(#text / 40) + 1) * 16
    end
    height = math.max(ui.macroScroll:GetHeight(), height + 20)
    ui.macroText:SetHeight(height); ui.macroScroll.child:SetHeight(height)
end
local function button(parent, text, fn, hint)
    local b = CreateFrame("Button", nil, parent)
    surface(b, true)
    b.text = font(b.glass.top, text)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0); b.text:SetJustifyH("CENTER")
    b:SetScript("OnSizeChanged", function(self, w) self.text:SetWidth(math.max(1, w - 12)) end)
    b:SetScript("OnClick", function(self, mouse)
        if not self:IsEnabled() then return end
        stopCapture(); clearFocus(); hideTooltip(); message = nil; fn(self, mouse)
    end)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then materialTint(self.glass, "hover") end
        if hint then tooltip(self, hint) end
    end)
    b:SetScript("OnLeave", function(self)
        materialTint(self.glass); hideTooltip()
    end)
    return b
end
local function enable(b, enabled)
    b.glass.editorEnabled = enabled and true or false
    b:SetEnabled(enabled); Glass.SetSurfaceEnabled(b.glass, enabled); b.text:SetAlpha(enabled and 1 or 0.45)
end
local function edit(parent, hint, changed, multiline)
    local box = CreateFrame("EditBox", nil, parent)
    surface(box, true); box:SetAutoFocus(false); box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(10, 10, 7, 7); box:SetMultiLine(multiline == true); box:SetText("")
    box.placeholder = font(box.glass.top, hint, 12)
    box.placeholder:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    box.placeholder:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    box.placeholder:SetTextColor(0.55, 0.67, 0.8)
    box:SetScript("OnEditFocusGained", function()
        stopCapture(); materialTint(box.glass, "focus")
        if refresh then refresh() end
    end)
    box:SetScript("OnEditFocusLost", function()
        materialTint(box.glass)
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not multiline then box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
    box:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown((self:GetText() or "") == "")
        if not refreshing then stopCapture(); changed(self:GetText() or "") end
    end)
    box:SetScript("OnEnter", function(self) tooltip(self, hint) end); box:SetScript("OnLeave", hideTooltip)
    ui.fields[#ui.fields + 1] = box
    return box
end
local function scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    s.child = CreateFrame("Frame", nil, s); s.child:SetSize(1, 1); s:SetScrollChild(s.child)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        stopCapture()
        local range = math.max(0, self.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 36)))
    end)
    s:HookScript("OnVerticalScroll", stopCapture)
    s:HookScript("OnScrollRangeChanged", function(self, _, range)
        if self.ScrollBar then self.ScrollBar:SetShown((range or 0) > 0) end
    end)
    return s
end
local function icon(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(24, 24); t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    return t
end
local function modal(title, choices)
    stopCapture(); clearFocus(); ui.modal:Show(); ui.modal.title:SetText(title)
    for i, b in ipairs(ui.modal.buttons) do
        local choice = choices[i]
        b:SetShown(choice ~= nil)
        if choice then b.text:SetText(choice[1]); enable(b, choice[3] ~= false); b.callback = choice[2] end
    end
end
guard = function(fn)
    stopCapture()
    if #state.staged > 0 then
        modal("Quick Bind has unapplied changes.", {
            { "Apply changes", function()
                local ok, why = state:ApplyQuick()
                if ok then ui.modal:Hide(); fn() else message = why; refresh() end
            end, not InCombatLockdown() },
            { "Discard", function() state:DiscardQuick(); ui.modal:Hide(); fn() end },
            { "Keep editing", function() ui.modal:Hide(); refresh() end },
        })
    elseif state:Dirty() then
        local valid = state:Validity()
        modal("Save changes before leaving this binding?", {
            { "Save", function()
                local ok, why = state:Save()
                if ok then ui.modal:Hide(); fn() else message = why; refresh() end
            end, valid and not InCombatLockdown() },
            { "Discard", function() state:Select(nil); ui.modal:Hide(); fn() end },
            { "Keep editing", function() ui.modal:Hide(); refresh() end },
        })
    else state:DiscardQuick(); fn() end
end
startRecord = function()
    if InCombatLockdown() then message = "Recording paused in combat; your draft is kept."; refresh(); return end
    stopCapture(); clearFocus()
    if not state.draft then state:NewDraft() end
    ui.rankList:Hide(); recording = true; refresh()
end
selectRow = function(row, focus)
    local function focusField()
        if focus == "input" then startRecord()
        elseif focus == "rank" then showRanks()
        elseif focus == "action" then
            local action = state.draft and state.draft.action
            if action == "macro" then ui.macroText:SetFocus()
            elseif action == nil or action == "spell" then ui.spellSearch:SetFocus() end
        end
    end
    if row == state.original then focusField(); return end
    guard(function()
        state:DiscardQuick()
        -- Saving in the guard can replace/remove the requested destination.
        -- Prefer its saved identity, then resolve the input against the new list.
        local destination
        for _, saved in ipairs(E.Rows(state.role)) do if saved == row then destination = saved; break end end
        destination = destination or E.Conflict(E.Rows(state.role), row)
        if destination then state:Select(destination)
        elseif row.default then state:NewDraft(); state.draft = { mouse = row.mouse, action = row.action }
        else state:Select(nil) end
        ui.rankList:Hide(); message = nil; refresh(); if state.draft then focusField() end
    end)
end
local function capture(kind, bind)
    if InCombatLockdown() or hasFocus() or ui.modal:IsShown() then stopCapture(); return end
    if recording then
        state:SetInput(kind, bind); stopCapture(); message = "Input recorded. Choose an action, then save."
    elseif armed and state.quick then
        local row = { spell = armed.spell }; row[kind] = bind; stopCapture()
        local ok, why, conflict = state:Stage(row)
        if not ok and conflict then
            modal(E.BindingText(row) .. " is assigned to " .. E.ActionText(conflict)
                .. (conflict.default and " (default). Replace this behavior?" or "."), {
                { "Replace assignment", function()
                    local staged, err = state:Stage(row, conflict)
                    message = staged and ("Staged " .. E.BindingText(row) .. " → " .. E.ActionText(row)) or err
                    ui.modal:Hide(); refresh()
                end },
                { "Another input", function() ui.modal:Hide(); refresh() end },
            })
        else message = ok and ("Staged " .. E.BindingText(row) .. " → " .. E.ActionText(row)) or why end
    elseif previewArmed then
        local input = {}; input[kind] = bind
        ui.previewResult:SetText(E.BindingText(input) .. " → " .. E.Preview(state.role, input))
    end
    refresh()
end
local function keyDown(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(true)
    if consumed[key] then self:SetPropagateKeyboardInput(false); return end
    if hasFocus() then return end
    if key == "ESCAPE" then
        consumed[key] = true
        if ui.modal:IsShown() then ui.modal:Hide()
        elseif recording or armed or previewArmed then stopCapture(); message = "Capture stopped. Pending changes are kept."
        elseif state.quick then state.quick = false; message = "Quick Bind stopped. Apply or discard staged changes."
        else CCO.RequestClose() end
        refresh(); self:SetPropagateKeyboardInput(false); return
    end
    if ui.modal:IsShown() or E.MODIFIER_KEYS[key] then return end
    if recording or armed or previewArmed then
        local kind, bind = E.Input({ key = CC.KeyBind(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), key) })
        if kind then capture(kind, bind); consumed[key] = true; self:SetPropagateKeyboardInput(false) end
    end
end
local function mouseCapture(self, mouse)
    if not mouseDown or mouseDown.frame ~= self or mouseDown.button ~= mouse then return end
    mouseDown = nil
    local n = E.MOUSE_BUTTONS[mouse]
    if n then capture("mouse", CC.MouseBind(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), n)) end
end
local function chooseSpell(group)
    if state.quick or #state.staged > 0 then return end
    if state.draft then state:Choose("spell", group.spell) else ui.browseSpell = group end
    ui.rankList:Hide(); refresh()
end
local function bindingRow(i)
    local r = CreateFrame("Button", nil, ui.table.child)
    r.selection = r:CreateTexture(nil, "BACKGROUND"); r.selection:SetAllPoints(r); r.selection:SetColorTexture(0.12, 0.75, 1, 0.15)
    local line = r:CreateTexture(nil, "BACKGROUND"); line:SetColorTexture(0.6, 0.8, 1, 0.12)
    line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0); line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0); line:SetHeight(1)
    r.input = button(r, "", function() if not r.staged then selectRow(r.data, "input") end end,
        "Record a different input. Default target/menu clicks also apply with modifiers unless overridden.")
    r.action = CreateFrame("Button", nil, r); r.icon = icon(r.action); r.icon:SetPoint("LEFT", r.action, "LEFT", 3, 0)
    r.name = font(r.action, ""); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.action, "RIGHT", -2, 0)
    r.rank = button(r, "", function() if not r.staged then selectRow(r.data, "rank") end end, "Choose Highest learned or pin a learned rank.")
    r.note = font(r, "", 10); r.note:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 8, 2)
    r:SetScript("OnClick", function() stopCapture(); if not r.staged then selectRow(r.data) end end)
    r.action:SetScript("OnClick", function() stopCapture(); if not r.staged then selectRow(r.data, "action") end end)
    local function enter(self)
        r.selection:Show()
        tooltip(self, E.BindingText(r.data) .. "\n" .. E.ActionText(r.data) .. "\n" .. E.RankText(r.data)
            .. (r.warning and ("\n" .. r.warning) or "")
            .. (r.data.default and "\nImplicit default. Saving an assignment replaces this click." or "\nClick input, action, or rank to edit."))
    end
    local function leave() r.selection:SetShown(r.data == state.original or r.staged); hideTooltip() end
    r:SetScript("OnEnter", enter); r:SetScript("OnLeave", leave)
    r.action:SetScript("OnEnter", enter); r.action:SetScript("OnLeave", leave)
    ui.rows[i] = r
    return r
end
local function spellRow(i)
    local r = CreateFrame("Button", nil, ui.browser.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); r.bg:SetColorTexture(0.12, 0.75, 1, 0.18)
    r.icon = icon(r); r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name = font(r, ""); r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:RegisterForClicks("AnyUp")
    r:SetScript("OnClick", function() if not state.quick then chooseSpell(r.group) end end)
    r:SetScript("OnEnter", function(self)
        self.bg:Show()
        if state.quick and not InCombatLockdown() and not hasFocus() and not ui.modal:IsShown() then
            stopCapture(); armed = r.group
            ui.banner:SetText("Quick Bind active · " .. r.group.name .. " armed: press a key or click this spell")
        elseif state.quick and hasFocus() then
            tooltip(self, "Finish typing with Enter or Escape, then hover the spell again to bind.")
        else tooltip(self, r.group.name .. "\nSelect this spell, or drag a spell from your spellbook.") end
    end)
    r:SetScript("OnLeave", function(self) stopCapture(); self.bg:Hide(); hideTooltip() end)
    r:SetScript("OnMouseDown", function(self, mouse) if armed == self.group then mouseDown = { frame = self, button = mouse } end end)
    r:SetScript("OnMouseUp", mouseCapture)
    ui.spells[i] = r
    return r
end
showRanks = function()
    local d = state.draft
    if not (d and d.spell) then return end
    stopCapture()
    local ranks, verified = API.ClickCastRanks(d.spell)
    local choices = { { text = "Highest learned", id = ranks[#ranks] or d.spell } }
    for _, id in ipairs(ranks) do
        local sub = API.SpellSubtext(id)
        if sub then choices[#choices + 1] = { text = "Pinned · " .. sub, id = id, pinned = true } end
    end
    if #ranks == 0 then message = "Saved rank unavailable. Choose a learned spell to replace it."
    elseif not verified then message = "Rank family not verified; only this exact learned spell is offered." end
    for i, choice in ipairs(choices) do
        local b = ui.ranks[i]
        if not b then
            b = button(ui.rankList.child, "", function(self)
                if state.draft and not InCombatLockdown() then
                    state.draft.spell, state.draft.pinned = self.choice.id, self.choice.pinned
                    ui.rankList:Hide(); refresh()
                end
            end)
            ui.ranks[i] = b
        end
        b.choice = choice; b.text:SetText(choice.text)
        at(b, ui.rankList.child, 0, (i - 1) * 32, ui.rightWidth - 28, 30)
        enable(b, not InCombatLockdown() and #ranks > 0); b:Show()
    end
    for i = #choices + 1, #ui.ranks do ui.ranks[i]:Hide() end
    ui.rankList.child:SetSize(ui.rightWidth - 28, #choices * 32); ui.rankList:Show(); refresh()
end
local function clientWarnings()
    local out, cv = {}, rawget(_G, "C_CVar")
    if cv and cv.GetCVar then
        local ok, on = pcall(cv.GetCVar, "enableMouseoverCast")
        if ok and on == "1" then out[#out + 1] = "Blizzard Mouseover Cast is on; it can cast on strangers outside GRF." end
    end
    local profile = API.ClickBindingProfile()
    if profile then
        local kinds, interactions, target = Enum and Enum.ClickBindingType or {}, Enum and Enum.ClickBindingInteraction or {}, false
        for _, b in ipairs(profile) do
            if b.type == kinds.Interaction and b.actionID == interactions.Target then target = true end
            if b.type == kinds.Spell or b.type == kinds.Macro or b.type == kinds.PetAction then
                local getMods = rawget(_G, "GetStringFromModifiers")
                local ok, mods = false, ""
                if getMods then ok, mods = pcall(getMods, b.modifiers or 0) end
                out[#out + 1] = "Blizzard also binds " .. (ok and mods ~= "" and (mods .. "-") or "") .. tostring(b.button) .. "; Blizzard acts first."
            end
        end
        if not target then out[#out + 1] = "Blizzard's Target Unit Frame click is unbound; default targeting may not work." end
    end
    return table.concat(out, "\n")
end
local function warnings()
    if externalWarnings == nil then externalWarnings = clientWarnings() end
    local out = { externalWarnings }
    for _, row in ipairs(E.Rows(state.role)) do
        local problem, note = CC.problems[row], CC.notes[row]
        if problem then out[#out + 1] = E.BindingText(row) .. ": " .. problem end
        if note then out[#out + 1] = E.BindingText(row) .. ": " .. note end
    end
    if state.draft then for _, warning in ipairs(CC.Warnings(state.draft)) do out[#out + 1] = warning end end
    return table.concat(out, "\n"):gsub("^\n", "")
end
refresh = function()
    if not root or refreshing then return end
    refreshing = true
    local combat, d = InCombatLockdown(), state.draft
    local action = d and (d.action or "spell") or ui.browseAction or "spell"
    local batch = state.quick or #state.staged > 0
    ui.profile:SetText((ROLE_NAMES[state.role] or state.role) .. " · This character"
        .. (state.role ~= GRF.role and ("   |   Active: " .. (ROLE_NAMES[GRF.role] or "?")) or " · Active"))
    ui.banner:SetText(combat and "Editing paused in combat · Drafts and staged bindings are kept"
        or state.quick and "Quick Bind active · Hover a spell, then press a key or click it · Esc stops capture"
        or #state.staged > 0 and "Quick Bind stopped · Apply or discard staged changes"
        or "Mouse: GRF group and pet frames · Keyboard: while hovering GRF group-member frames")
    ui.quick.text:SetText(state.quick and "Stop Quick Bind" or "Quick Bind"); enable(ui.quick, not combat)
    for role, b in pairs(ui.roles) do
        b.text:SetText((role == state.role and "• " or "") .. ROLE_NAMES[role])
        b.glass.editorSelected = role == state.role; materialTint(b.glass, b.glass.editorAccent)
    end
    ui.input.text:SetText(d and E.BindingText(d) or "Record input"); ui.record.text:SetText(recording and "Recording…" or "Record")
    ui.captureLabel:SetText(recording and "Press a key or click INSIDE this box · Esc cancels" or "Mouse recording area · Click Record to begin")
    ui.captureLabel:SetTextColor(recording and 0.2 or 0.65, recording and 0.9 or 0.75, 1)
    materialTint(ui.capture.glass, recording and "recording" or nil)
    enable(ui.record, d ~= nil and not combat and not batch); enable(ui.input, d ~= nil and not combat and not batch)
    enable(ui.add, not combat and not batch)
    ui.detail:SetText(d and (state.original and "Edit binding" or "New binding") or "Browse actions")
    for kind, b in pairs(ui.tabs) do
        local selected = kind == action or (kind == "unit" and (action == "target" or action == "togglemenu"))
        b.text:SetText((selected and "• " or "") .. b.caption); enable(b, not batch and not combat)
        b.glass.editorSelected = selected; materialTint(b.glass, b.glass.editorAccent)
    end
    ui.unitTarget:SetShown(action == "unit" or action == "target" or action == "togglemenu")
    ui.unitMenu:SetShown(action == "unit" or action == "target" or action == "togglemenu")
    ui.unitTarget.text:SetText((action == "target" and "• " or "") .. "Target unit")
    ui.unitMenu.text:SetText((action == "togglemenu" and "• " or "") .. "Open unit menu")
    enable(ui.unitTarget, not combat); enable(ui.unitMenu, not combat)
    local macro = action == "macro"
    if not macro or not d or ui.iconDraft ~= d then ui.iconList:Hide(); ui.iconDraft = nil end
    ui.macroName:SetShown(macro); ui.macroScroll:SetShown(macro); ui.macroHelp:SetShown(macro); ui.macroIcon:SetShown(macro)
    enable(ui.macroIcon, not combat)
    if macro and d then
        if ui.macroName:GetText() ~= (d.name or "") then ui.macroName:SetText(d.name or "") end
        if ui.macroText:GetText() ~= (d.macrotext or "") then ui.macroText:SetText(d.macrotext or "") end
        sizeMacro()
        ui.macroHelp:SetText("Use [@mouseover] for the hovered frame's unit. Other commands keep normal macro semantics.\n" .. #(d.macrotext or "") .. "/255 bytes · Preview never runs macros.")
    end
    ui.spellSearch:SetShown(action == "spell"); ui.browser:SetShown(action == "spell")
    ui.create:SetShown(not d and action == "spell" and ui.browseSpell ~= nil and not batch)
    enable(ui.create, not combat)
    if ui.browseSpell then ui.create.text:SetText("Create binding: " .. ui.browseSpell.name) end
    ui.rank:SetShown(d ~= nil and action == "spell" and d.spell ~= nil); ui.rank.text:SetText(d and E.RankText(d) or "Highest"); enable(ui.rank, not combat)
    local valid, why, conflict = state:Validity()
    ui.save.text:SetText(state.original and "Save changes" or "Add binding")
    enable(ui.save, valid and not combat and not batch); enable(ui.cancel, d ~= nil and not batch)
    enable(ui.delete, state.original ~= nil and not combat and not batch)
    ui.resolve:SetShown(conflict ~= nil and not batch); ui.conflict = conflict
    ui.apply:SetShown(batch); ui.discard:SetShown(batch); enable(ui.apply, #state.staged > 0 and not combat)
    ui.save:SetShown(not batch); ui.cancel:SetShown(not batch); ui.delete:SetShown(not batch)
    ui.status:SetText(message or (combat and "Changes cannot be saved in combat." or why or ""))
    ui.status:SetTextColor((conflict or combat) and 1 or 0.8, (conflict or combat) and 0.65 or 0.85, (conflict or combat) and 0.2 or 0.95)
    ui.warningText = warnings(); ui.warning.text:SetText(ui.warningText ~= "" and "Warnings" or "Binding help")
    ui.count:SetText(#E.Rows(state.role) .. " saved bindings" .. (#state.staged > 0 and (" · " .. #state.staged .. " staged") or "") .. (CC.pending and " · Active role changes pending combat end" or ""))
    local visible, occupied = {}, {}
    for _, row in ipairs(E.Rows(state.role)) do
        occupied[E.InputID(row) or "invalid"] = true
        if E.Matches(row, ui.tableSearch:GetText()) then visible[#visible + 1] = { row = row } end
    end
    for n, kind in ipairs({ "target", "togglemenu" }) do
        local row = { mouse = tostring(n), action = kind, default = true }
        if not occupied[E.InputID(row)] and E.Matches(row, ui.tableSearch:GetText()) then table.insert(visible, math.min(n, #visible + 1), { row = row }) end
    end
    for _, row in ipairs(state.staged) do visible[#visible + 1] = { row = row, staged = true } end
    if d and not state.original then visible[#visible + 1] = { row = d, staged = true, draft = true } end
    for i, item in ipairs(visible) do
        local r = ui.rows[i] or bindingRow(i)
        r.data, r.staged = item.row, item.staged
        at(r, ui.table.child, 0, (i - 1) * 52, ui.leftWidth - 26, 51)
        local w = r:GetWidth()
        at(r.input, r, 3, 4, w * 0.30, 29); r.input.text:SetWidth(w * 0.30 - 8)
        at(r.action, r, w * 0.30 + 9, 3, w * 0.45 - 10, 32)
        at(r.rank, r, w * 0.75, 4, w * 0.25 - 4, 29); r.rank.text:SetWidth(w * 0.25 - 12)
        r.input.text:SetText(E.BindingText(item.row)); r.name:SetText(E.ActionText(item.row)); r.rank.text:SetText(E.RankText(item.row))
        r.rank.text:SetTextColor(1, item.row.pinned and 0.82 or 0.94, item.row.pinned and 0.2 or 1)
        r.icon:SetTexture(item.row.spell and API.SpellTexture(item.row.spell) or item.row.icon
            or ACTION_ICONS[item.row.action] or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.selection:SetShown(item.row == state.original or item.staged)
        local unavailable = item.row.spell and not API.SpellKnown(item.row.spell)
        r.warning = not item.staged and (CC.problems[item.row] or CC.notes[item.row]) or nil
        r.note:SetText(item.draft and "Draft · Not active" or item.staged and "Staged · Not active"
            or item.row.default and "Default · Applies with modifiers unless overridden"
            or r.warning
            or (item.row == state.original and state:Dirty()) and "Unsaved changes · Saved action remains active"
            or unavailable and "Unavailable · Saved binding retained" or "")
        local warning = unavailable or r.warning
        r.note:SetTextColor(warning and 1 or 0.6, warning and 0.65 or 0.8, warning and 0.2 or 1)
        enable(r.input, not item.staged and not combat and not batch); enable(r.rank, item.row.spell ~= nil and not item.staged and not batch)
        r:Show()
    end
    for i = #visible + 1, #ui.rows do ui.rows[i]:Hide() end
    ui.table.child:SetSize(ui.leftWidth - 26, math.max(1, #visible * 52))
    local query, count = (ui.spellSearch:GetText() or ""):lower(), 0
    local catalog, byID = API.ClickCastCatalog()
    for _, group in ipairs(catalog) do
        if group.name:lower():find(query, 1, true) then
            count = count + 1
            local r = ui.spells[count] or spellRow(count)
            if armed and r.group ~= group then stopCapture() end
            r.group = group
            at(r, ui.browser.child, 0, (count - 1) * 34, ui.rightWidth - 28, 33)
            r.name:SetText(group.name); r.icon:SetTexture(group.icon)
            r.bg:SetShown((d and byID[d.spell] == group) or ui.browseSpell == group); r:Show()
        end
    end
    for i = count + 1, #ui.spells do ui.spells[i]:Hide() end
    ui.browser.child:SetSize(ui.rightWidth - 28, math.max(1, count * 34)); ui.empty:SetShown(count == 0 and action == "spell")
    refreshing = false
end
layout = function(w, h)
    if not root then return end
    w, h = math.max(CCO.MIN_WIDTH, w or 1100), math.max(CCO.MIN_HEIGHT, h or 700)
    local left = math.floor((w - 54) * 0.60)
    local right, rx = w - left - 54, left + 36
    ui.leftWidth, ui.rightWidth = left, right
    at(material.panes[1], root, 12, 138, left + 12, h - 150)
    at(material.panes[2], root, left + 30, 138, right + 14, h - 150)
    at(ui.title, root, 20, 16, w - 70, 28); at(ui.profile, root, 20, 51, w - 200, 22)
    at(ui.divider, root, left + 28, 144, 1, h - 160)
    for i, role in ipairs(GRF.Role.ROLES) do at(ui.roles[role], root, 20 + (i - 1) * 87, 80, 82, 27) end
    at(ui.quick, root, w - 174, 78, 154, 30); at(ui.banner, root, 20, 115, w - 40, 22)
    at(ui.tableSearch, root, 20, 147, left - 150, 32); at(ui.add, root, left - 120, 147, 140, 32)
    at(ui.colInput, root, 25, 190, left * 0.3, 22)
    at(ui.colAction, root, 29 + (left - 26) * 0.3, 190, left * 0.45, 22)
    at(ui.colRank, root, 20 + (left - 26) * 0.75, 190, left * 0.25, 22)
    at(ui.table, root, 20, 216, left - 24, h - 335)
    at(ui.detail, root, rx, 147, right - 86, 25); at(ui.browse, root, rx + right - 80, 145, 80, 28)
    at(ui.input, root, rx, 180, right - 95, 30); at(ui.record, root, rx + right - 88, 180, 88, 30)
    at(ui.capture, root, rx, 215, right, 42); at(ui.captureLabel, ui.capture, 8, 5, right - 16, 32)
    for i, kind in ipairs({ "spell", "unit", "macro" }) do at(ui.tabs[kind], root, rx + (i - 1) * right / 3, 266, right / 3 - 3, 30) end
    at(ui.spellSearch, root, rx, 304, right, 30); at(ui.browser, root, rx, 340, right - 24, math.max(50, h - 529))
    at(ui.empty, root, rx + 8, 351, right - 16, 40)
    at(ui.unitTarget, root, rx, 311, right, 34); at(ui.unitMenu, root, rx, 353, right, 34)
    at(ui.macroName, root, rx, 307, right - 106, 30); at(ui.macroIcon, root, rx + right - 100, 307, 100, 30)
    at(ui.macroScroll, root, rx, 344, right - 24, math.max(50, h - 577))
    ui.macroText:SetWidth(right - 28); ui.macroScroll.child:SetWidth(right - 28); sizeMacro()
    at(ui.macroHelp, root, rx, math.max(400, h - 218), right, math.max(45, h - 149 - math.max(400, h - 218)))
    at(ui.rank, root, rx, h - 179, right, 30); at(ui.create, root, rx, h - 179, right, 30)
    at(ui.status, root, rx, h - 140, right, 57); at(ui.resolve, root, rx, h - 83, right, 28)
    at(ui.delete, root, rx, h - 47, 70, 30); at(ui.cancel, root, rx + 76, h - 47, 75, 30)
    at(ui.save, root, rx + 157, h - 47, right - 157, 30)
    at(ui.apply, root, rx, h - 47, right * 0.6, 30); at(ui.discard, root, rx + right * 0.6 + 8, h - 47, right * 0.4 - 8, 30)
    at(ui.preview, root, 20, h - 107, 176, 58); at(ui.previewTitle, ui.preview, 10, 7, 155, 17); at(ui.previewHealth, ui.preview, 10, 31, 155, 17)
    at(ui.previewResult, root, 210, h - 105, left - 195, 45); at(ui.previewHelp, root, 20, h - 42, left - 140, 19)
    at(ui.warning, root, left - 111, h - 42, 131, 27); at(ui.count, root, 20, h - 20, left - 10, 16)
    at(ui.rankList, root, rx, 304, right - 24, math.max(80, h - 493)); at(ui.iconList, root, rx, 304, right - 24, math.max(80, h - 493))
    ui.modal:SetAllPoints(root); ui.modal.box:SetSize(math.min(w - 40, 560), 190)
    refresh()
end
local function build(parent)
    root = CreateFrame("Frame", "GlassRaidFramesClickCastEditor", parent); root:SetAllPoints(parent)
    root:EnableMouse(true)
    -- Two continuous backings, below all content and independent of row count
    -- and scrolling. Their rounded masks use the library's own pane geometry.
    for i = 1, 2 do
        local pane = root:CreateTexture(nil, "BACKGROUND", nil, -7)
        -- Lighter charcoal and stronger opacity are independent: the reading
        -- area loses its black-card appearance without exposing world labels.
        paintPane(pane)
        local S = Glass.SIZES.thin_small
        pane:AddMaskTexture(Glass.Mask(root, S.mask, S.maskMargin, 0, pane))
        pane:SetShown(material.mode ~= "baseline"); material.panes[i] = pane
    end
    keyboard = CreateFrame("Frame", nil, root); keyboard:SetAllPoints(root); keyboard:Hide()
    state = E.New(GRF.role)
    ui.title, ui.profile, ui.banner = font(root, "Glass Raid Frames / Click-casting", 23), font(root, "", 14), font(root, "", 12)
    ui.divider = root:CreateTexture(nil, "BACKGROUND"); ui.divider:SetColorTexture(0.6, 0.8, 1, 0.18)
    ui.banner:SetTextColor(0.5, 0.82, 1)
    for _, role in ipairs(GRF.Role.ROLES) do
        local pick = role
        ui.roles[pick] = button(root, ROLE_NAMES[pick], function()
            if pick ~= state.role then guard(function() state = E.New(pick); message = nil; ui.rankList:Hide(); refresh() end) end
        end, "Edit " .. ROLE_NAMES[pick] .. " bindings without changing your active role or layout.")
    end
    ui.quick = button(root, "Quick Bind", function()
        if state.quick then state.quick = false; refresh()
        elseif #state.staged > 0 then state.quick = true; refresh()
        else guard(function() state:Select(nil); state:BeginQuick(); ui.browseAction = "spell"; ui.rankList:Hide(); refresh() end) end
    end)
    ui.tableSearch = edit(root, "Search bindings: input, modifier, spell or action name", function() refresh() end)
    ui.tableSearch.placeholder:SetText("Search bindings")
    ui.add = button(root, "+ Add binding", function() guard(function() state:NewDraft(); startRecord() end) end)
    ui.colInput, ui.colAction, ui.colRank = font(root, "INPUT", 12), font(root, "ACTION", 12), font(root, "RANK", 12)
    ui.table, ui.browser = scroll(root), scroll(root)
    ui.detail = font(root, "Browse actions", 18)
    ui.browse = button(root, "Browse", function() guard(function() state:Select(nil); ui.rankList:Hide(); ui.iconList:Hide(); refresh() end) end,
        "Browse actions without selecting a saved binding.")
    ui.input = button(root, "Record input", startRecord); ui.record = button(root, "Record", startRecord)
    ui.capture = CreateFrame("Frame", nil, root); surface(ui.capture, true); ui.capture:EnableMouse(true)
    ui.captureLabel = font(ui.capture.glass.top, "", 12); ui.captureLabel:SetWordWrap(true)
    ui.capture:SetScript("OnMouseDown", function(self, mouse) if recording then mouseDown = { frame = self, button = mouse } end end)
    ui.capture:SetScript("OnMouseUp", mouseCapture); ui.capture:SetScript("OnLeave", function() mouseDown = nil end)
    for _, entry in ipairs({ { "spell", "Spell" }, { "unit", "Unit action" }, { "macro", "Macro" } }) do
        local kind, caption = entry[1], entry[2]
        local b = button(root, caption, function()
            ui.rankList:Hide(); ui.iconList:Hide()
            local current = state.draft and (state.draft.action or "spell") or ui.browseAction or "spell"
            if current == kind or (kind == "unit" and (current == "target" or current == "togglemenu")) then refresh(); return end
            if kind == "unit" then ui.browseAction = kind; if state.draft then state:Choose("target") end
            elseif state.draft or kind == "macro" then state:Choose(kind, kind == "spell" and ui.browseSpell and ui.browseSpell.spell or nil)
            else ui.browseAction = kind end
            refresh()
        end)
        b.caption = caption; ui.tabs[kind] = b
    end
    ui.spellSearch = edit(root, "Search learned spells", function() refresh() end)
    ui.spellSearch.placeholder:SetText("Search learned spells")
    ui.empty = font(root, "No learned spells match. You can also drag a spell from your spellbook.", 12); ui.empty:SetWordWrap(true)
    ui.create = button(root, "Create binding", function() if ui.browseSpell then state:NewDraft(ui.browseSpell.spell); startRecord() end end)
    ui.unitTarget = button(root, "Target unit", function() state:Choose("target"); refresh() end)
    ui.unitMenu = button(root, "Open unit menu", function() state:Choose("togglemenu"); refresh() end)
    ui.macroName = edit(root, "Optional macro display name", function(text) if state.draft then state.draft.name = text; refresh() end end)
    ui.macroScroll = scroll(root)
    ui.macroText = edit(ui.macroScroll.child, "Macro text (255 bytes). Use [@mouseover] for the frame's unit.", function(text)
        if state.draft then state.draft.macrotext = text; refresh() end
        sizeMacro()
    end, true)
    ui.macroMeasure = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.macroMeasure:SetWordWrap(true); ui.macroMeasure:Hide()
    ui.macroText:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local offset, visible = ui.macroScroll:GetVerticalScroll() or 0, ui.macroScroll:GetHeight()
        local cursor = -y
        if cursor < offset then ui.macroScroll:SetVerticalScroll(math.max(0, cursor))
        elseif cursor + height > offset + visible then ui.macroScroll:SetVerticalScroll(cursor + height - visible) end
    end)
    ui.macroText:SetPoint("TOPLEFT", ui.macroScroll.child, "TOPLEFT", 0, 0)
    ui.macroHelp = font(root, "", 12); ui.macroHelp:SetWordWrap(true)
    ui.iconList = scroll(root); ui.iconList:SetFrameLevel(root:GetFrameLevel() + 25); surface(ui.iconList, false); ui.iconList:Hide()
    ui.macroIcon = button(root, "Choose icon", function()
        ui.iconDraft = state.draft
        local icons, seen = { "Interface\\Icons\\INV_Misc_QuestionMark" }, {}
        for _, group in ipairs(API.ClickCastCatalog()) do if group.icon and not seen[group.icon] then seen[group.icon] = true; icons[#icons + 1] = group.icon end end
        local cols = math.max(1, math.floor((ui.rightWidth - 28) / 38))
        for i, texture in ipairs(icons) do
            local b = ui.icons[i]
            if not b then
                b = button(ui.iconList.child, "", function(self)
                    if ui.iconList:IsShown() and state.draft and state.draft == ui.iconDraft
                        and state.draft.action == "macro" then state.draft.icon = self.texture end
                    ui.iconList:Hide(); ui.iconDraft = nil; refresh()
                end)
                b.icon = icon(b.glass.top); b.icon:SetPoint("CENTER", b, "CENTER", 0, 0); ui.icons[i] = b
            end
            b.texture = texture; b.icon:SetTexture(texture)
            at(b, ui.iconList.child, ((i - 1) % cols) * 38, math.floor((i - 1) / cols) * 38, 36, 36); b:Show()
        end
        for i = #icons + 1, #ui.icons do ui.icons[i]:Hide() end
        ui.iconList.child:SetSize(ui.rightWidth - 28, math.ceil(#icons / cols) * 38); ui.iconList:Show()
    end)
    ui.rank = button(root, "Highest", showRanks)
    ui.rankList = scroll(root); ui.rankList:SetFrameLevel(root:GetFrameLevel() + 25); surface(ui.rankList, false); ui.rankList:Hide()
    ui.status = font(root, "", 12); ui.status:SetWordWrap(true)
    ui.resolve = button(root, "Resolve input conflict…", function()
        local conflict = ui.conflict
        if not conflict then return end
        modal("Replace " .. E.ActionText(conflict) .. " on " .. E.BindingText(conflict) .. "?", {
            { "Replace on save", function() state:Replace(conflict); ui.modal:Hide(); refresh() end },
            { "Another input", function() ui.modal:Hide(); startRecord() end },
            { "Keep editing", function() ui.modal:Hide(); refresh() end },
        })
    end)
    ui.save = button(root, "Save changes", function() local _, why = state:Save(); message = why; refresh() end)
    ui.cancel = button(root, "Cancel", function() state:Select(state.original); ui.rankList:Hide(); ui.iconList:Hide(); refresh() end)
    ui.delete = button(root, "Remove", function()
        modal("Remove " .. E.ActionText(state.original) .. " on " .. E.BindingText(state.original) .. "?", {
            { "Remove binding", function()
                local ok, why = CC.Delete(state.role, state.original, state.snapshot)
                if ok then state:Select(nil); ui.modal:Hide() end
                message = why; refresh()
            end, not InCombatLockdown() },
            { "Keep binding", function() ui.modal:Hide(); refresh() end },
        })
    end)
    ui.apply = button(root, "Apply changes", function() local _, why = state:ApplyQuick(); message = why; refresh() end)
    ui.discard = button(root, "Discard", function() state:DiscardQuick(); refresh() end)
    ui.preview = CreateFrame("Frame", nil, root); surface(ui.preview, false); ui.preview:EnableMouse(true)
    ui.previewTitle = font(ui.preview.glass.top, "Try a binding", 13)
    ui.previewHealth = Glass.Bar(ui.preview, 17); ui.previewHealth:SetMinMaxValues(0, 100); ui.previewHealth:SetValue(100); ui.previewHealth:SetStatusBarColor(0.2, 0.8, 0.1)
    ui.previewResult = font(root, "Hover the sample frame and press an input.", 12); ui.previewResult:SetWordWrap(true)
    ui.previewHelp = font(root, "Preview only · Tests saved bindings", 11)
    ui.preview:SetScript("OnEnter", function() if not hasFocus() and not ui.modal:IsShown() then stopCapture(); previewArmed = true end end)
    ui.preview:SetScript("OnLeave", stopCapture)
    ui.preview:SetScript("OnMouseDown", function(self, mouse) if previewArmed then mouseDown = { frame = self, button = mouse } end end)
    ui.preview:SetScript("OnMouseUp", mouseCapture)
    ui.warning = button(root, "Binding help", function()
        modal(ui.warningText ~= "" and ui.warningText or "Mouse bindings apply to GRF group and pet frames. Hover keys apply only to group-member frames. Default target/menu clicks also apply with modifiers unless overridden.", {
            { "Close", function() ui.modal:Hide(); refresh() end },
            { "Mouseover Cast off", function()
                local cv = rawget(_G, "C_CVar"); if cv and cv.SetCVar then pcall(cv.SetCVar, "enableMouseoverCast", "0") end
                ui.modal:Hide(); refresh()
            end, not InCombatLockdown() },
        })
    end)
    ui.count = font(root, "", 10)
    ui.modal = CreateFrame("Frame", nil, root); ui.modal:SetFrameLevel(root:GetFrameLevel() + 100); ui.modal:EnableMouse(true)
    local shade = ui.modal:CreateTexture(nil, "BACKGROUND"); shade:SetAllPoints(ui.modal); shade:SetColorTexture(0, 0, 0, 0.75)
    ui.modal.box = CreateFrame("Frame", nil, ui.modal); surface(ui.modal.box, false); ui.modal.box:SetPoint("CENTER", ui.modal, "CENTER", 0, 0)
    ui.modal.title = font(ui.modal.box.glass.top, "", 14); ui.modal.title:SetWordWrap(true)
    ui.modal.title:SetPoint("TOPLEFT", ui.modal.box, "TOPLEFT", 20, -18); ui.modal.title:SetPoint("BOTTOMRIGHT", ui.modal.box, "BOTTOMRIGHT", -20, 58)
    ui.modal.buttons = {}
    for i = 1, 3 do
        local b = button(ui.modal.box, "", function(self) if self.callback then self.callback() end end)
        b:SetSize(160, 32); b:SetPoint("BOTTOMLEFT", ui.modal.box, "BOTTOMLEFT", 20 + (i - 1) * 174, 16); ui.modal.buttons[i] = b
    end
    ui.modal:Hide()
    keyboard:SetScript("OnKeyDown", keyDown)
    keyboard:SetScript("OnKeyUp", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not consumed[key]); consumed[key] = nil
    end)
    root:SetScript("OnShow", syncKeyboard)
    root:SetScript("OnHide", function()
        stopCapture(); clearFocus(); hideTooltip(); consumed = {}; keyboard:Hide()
        ui.rankList:Hide(); ui.iconList:Hide(); ui.iconDraft = nil
        if not InCombatLockdown() then keyboard:SetPropagateKeyboardInput(true) end
    end)
    root:SetScript("OnSizeChanged", function(_, w, h) layout(w, h) end)
    root:SetScript("OnReceiveDrag", function()
        if InCombatLockdown() or state.quick or #state.staged > 0 or ui.modal:IsShown() then return end
        local kind, _, _, id = GetCursorInfo()
        if kind == "spell" and type(id) == "number" then stopCapture(); state:Choose("spell", id); ClearCursor(); refresh() end
    end)
    ui.capture:SetScript("OnReceiveDrag", root:GetScript("OnReceiveDrag"))
    root:SetScript("OnEvent", function(_, event)
        stopCapture()
        externalWarnings = nil
        if event == "PLAYER_REGEN_DISABLED" then
            ui.rankList:Hide(); ui.iconList:Hide(); ui.modal:Hide(); message = "Editing paused in combat; drafts and staged bindings are kept."
        elseif event == "PLAYER_REGEN_ENABLED" then message = nil end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then syncKeyboard() end
        if root:IsShown() then refresh() end
    end)
    API.RegisterEvents(root, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "CVAR_UPDATE" })
    return root
end
function CCO.Refresh() externalWarnings = nil; if root then refresh() end end
function CCO.RequestClose(callback)
    if not root then if callback then callback() end; return end
    guard(function() stopCapture(); root:Hide(); if shell and host == shell then shell:Hide() end; if callback then callback() end end)
end
local function fitShell()
    if not shell then return end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if w <= 0 then w = 1200 end; if h <= 0 then h = 800 end
    local scale = math.min(1, (w - 24) / 900, (h - 24) / 600)
    shell:SetScale(scale); shell:SetSize(math.min(1100, (w - 24) / scale), math.min(700, (h - 24) / scale))
    shell:SetResizeBounds(900, 600, math.max(900, (w - 24) / scale), math.max(600, (h - 24) / scale))
end
local function standalone()
    if shell then return shell end
    shell = CreateFrame("Frame", "GlassRaidFramesClickCastWindow", UIParent)
    shell:Hide(); shell:SetFrameStrata("DIALOG"); shell:SetClampedToScreen(true)
    shell:SetMovable(true); shell:SetResizable(true); shell:EnableMouse(true); shell:SetPoint("CENTER", UIParent, "CENTER", 0, 0); surface(shell, false, "shell")
    local drag = CreateFrame("Frame", nil, shell)
    drag:SetPoint("TOPLEFT", shell, "TOPLEFT", 12, -8); drag:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -48, -8); drag:SetHeight(34)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton"); drag:SetFrameLevel(shell:GetFrameLevel() + 50)
    drag:SetScript("OnDragStart", function() stopCapture(); shell:StartMoving() end); drag:SetScript("OnDragStop", function() shell:StopMovingOrSizing() end)
    local close = button(shell, "×", function() CCO.RequestClose() end, "Close the click-casting editor")
    close:SetSize(30, 28); close:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -12, -12); close:SetFrameLevel(shell:GetFrameLevel() + 50)
    local resize = button(shell, "↘", function() end, "Drag to resize")
    resize:SetSize(18, 18); resize:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -3, 3); resize:SetFrameLevel(shell:GetFrameLevel() + 50)
    resize:SetScript("OnMouseDown", function() stopCapture(); shell:StartSizing("BOTTOMRIGHT") end); resize:SetScript("OnMouseUp", function() shell:StopMovingOrSizing() end)
    shell:SetScript("OnEvent", fitShell); API.RegisterEvents(shell, { "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }); fitShell()
    CCO._test.close = close
    return shell
end
function CCO.Open(parent)
    local destination = parent or standalone()
    if not root then build(destination) end
    if host ~= destination then
        if shell and destination ~= shell then shell:Hide() end
        root:SetParent(destination); root:ClearAllPoints(); root:SetAllPoints(destination); host = destination
    end
    externalWarnings = nil
    destination:Show(); root:Show(); syncKeyboard(); layout(destination:GetWidth(), destination:GetHeight())
    return root
end
function CCO.Toggle() if root and root:IsVisible() then CCO.RequestClose() else CCO.Open() end end
CCO.MIN_WIDTH, CCO.MIN_HEIGHT = 900, 600
CC.onApplied = function() externalWarnings = nil; if root and root:IsVisible() then refresh() end end
CCO._test = { ui = ui, state = function() return state end, root = function() return root end,
    material = material,
    keyboard = function() return keyboard end,
    recording = function() return recording end, armed = function() return armed end, shell = function() return shell end }
