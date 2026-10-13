-- IndicatorOptions.lua: the "Indicators" page under Options > AddOns > Glass
-- Raid Frames (#19). Owner's pick: a sub-page like Click-casting (mockup A),
-- not a window of our own.
--
-- Left, the indicators of this class; middle, the selected one's settings and
-- spells; top-right, a static preview tile. Same idiom as the other pages: a
-- canvas subcategory created hidden, built on first show, repainted on every
-- show and after every edit. Every edit goes through GRF.Settings, which
-- saves at once and applies out of combat (GRF.Indicators.Request).

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
local IO = {}
GRF.IndicatorOptions = IO

local page = CreateFrame("Frame", "GlassRaidFramesIndicatorOptions")
page.name = "Indicators"
page:Hide()
local content = CreateFrame("Frame", nil, page)
content:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
content:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

local label = function(...) return GRF.Options.Label(...) end
local button = function(...) return GRF.Options.Button(...) end

local KINDS = { { "icons", "Icons" }, { "icon", "One icon" }, { "square", "Square" } }
local KIND_HELP = {
    icons = "One fixed spot per spell, in list order.",
    icon = "One spot: the first spell present wins (list order = priority).",
    square = "A coloured square: the first spell present wins.",
    debuffs = "Every debuff on the unit, as many as fit.",
}
local GRID = { { "TOPLEFT", "TOP", "TOPRIGHT" }, { "LEFT", "CENTER", "RIGHT" }, { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" } }
local GROWS = { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "UP", "Up" }, { "DOWN", "Down" } }
local PALETTE = { { 1, 0.2, 0.2 }, { 1, 0.6, 0.15 }, { 1, 0.9, 0.2 }, { 0.3, 0.9, 0.35 }, { 0.5, 0.83, 1 },
                  { 0.3, 0.45, 1 }, { 0.75, 0.4, 1 }, { 1, 1, 1 } }
local ACCENT = { 0.5, 0.83, 1 }   -- #7fd4ff, the Glass addons' cyan
local LIST_X, MID_X, PREVIEW_X, TOP_Y = 16, 172, 470, -64
IO.ROWS, IO.SPELL_ROWS = GRF.Indicators.MAX_INDICATORS, GRF.Indicators.MAX_SPELLS

local selectedKey
local ui = {}            -- built widgets
local refreshing = false -- set while syncing controls, so their callbacks don't save

local function list() return GRF.Indicators.Setup() or {} end
local function selected()
    local ind = selectedKey and GRF.Settings.FindIndicator(selectedKey)
    if ind then return ind end
    ind = list()[1]
    selectedKey = ind and ind.key
    return ind
end

-- Every edit: save, apply (out of combat); the page repaints when told
-- (Indicators.onChanged), once.
local function edit(field, value)
    local ind = selected()
    if not ind or refreshing then return end
    GRF.Settings.EditIndicator(ind, field, value)
end

-- A slider step saves at once but applies when the drag pauses (0.1 s), not
-- 60 tiles per step (the tile-size sliders do the same).
local scheduled = false
local function editLater(field, value)
    local ind = selected()
    if not ind or refreshing then return end
    GRF.Settings.EditIndicator(ind, field, value, true)
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.1, function()
        scheduled = false
        GRF.Indicators.Request()
    end)
end

--------------------------------------------------------------------------------
-- Small widgets (our own: no UIDropDownMenu, templates through SafeFrame)
--------------------------------------------------------------------------------

local function checkbox(parent, text, onClick)
    local cb, templated = API.SafeFrame("CheckButton", parent, "UICheckButtonTemplate", "text")
    cb:SetSize(22, 22)
    if not templated then
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    end
    cb.label = label(parent, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

-- A row of toggle buttons, one lit: a radio group without dropdowns.
local function choices(parent, options, width, onPick)
    local group = {}
    for i, o in ipairs(options) do
        local b = button(parent, o[2], width, function() onPick(o[1]) end)
        b.value = o[1]
        b.lit = b:CreateTexture(nil, "OVERLAY")
        b.lit:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 2)
        b.lit:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 2)
        b.lit:SetHeight(2)
        b.lit:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        if i > 1 then b:SetPoint("LEFT", group[i - 1], "RIGHT", 2, 0) end
        group[i] = b
    end
    function group.set(value)
        for _, b in ipairs(group) do b.lit:SetShown(b.value == value) end
    end
    return group
end

local SLIDER_W = 150
local function slider(parent, text, min, max, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(SLIDER_W, 14)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(5)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s.title = label(parent, text, "GameFontHighlightSmall")
    s.title:SetPoint("RIGHT", s, "LEFT", -6, 0)
    s.value = label(parent, "", "GameFontHighlightSmall")
    s.value:SetPoint("LEFT", s, "RIGHT", 6, 0)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        self.value:SetText(tostring(v))
        if not refreshing then onChange(v) end
    end)
    return s
end

local function editBox(parent, width, numeric)
    local e, templated = API.SafeFrame("EditBox", parent, "InputBoxTemplate", "Left")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlight")
    if numeric then e:SetNumeric(true) end
    if not templated then
        local bg = e:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(e)
        bg:SetColorTexture(0, 0, 0, 0.5)
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); IO.Refresh() end)
    return e
end

--------------------------------------------------------------------------------
-- The indicator list
--------------------------------------------------------------------------------

local function listRow(i)
    local b = CreateFrame("Button", nil, content)
    b:SetSize(140, 20)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", LIST_X, TOP_Y - (i - 1) * 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.text = label(b, "")
    b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.text:SetWidth(128)
    b:SetScript("OnClick", function(self)
        if self.key then
            if ui.name:HasFocus() then ui.name:ClearFocus() end   -- commits the draft to its own indicator
            selectedKey = self.key
            IO.Refresh()
        end
    end)
    return b
end

local function paintList()
    local all = list()
    for i = 1, IO.ROWS do
        local r = ui.rows[i]
        local ind = all[i]
        r.key = ind and ind.key
        r:SetShown(ind ~= nil)
        if ind then
            local name = ind.name .. (ind.builtin and " |cff808080(built-in)|r" or "")
            r.text:SetText(name)
            r.text:SetTextColor(ind.enabled and 1 or 0.5, ind.enabled and 1 or 0.5, ind.enabled and 1 or 0.5)
            local sel = ind.key == selectedKey
            r.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], sel and 0.25 or 0)
        end
    end
end

--------------------------------------------------------------------------------
-- The preview: one glass tile at the current role's size, every enabled
-- indicator drawn with sample icons, the selected one outlined.
--------------------------------------------------------------------------------

local SAMPLE_DEBUFF = "Interface\\Icons\\Spell_Shadow_ShadowWordPain"   -- a sample debuff icon
local PREVIEW_SCALE = 1.6

local function previewBox(i)
    local p = ui.preview
    local t = p.boxes[i]
    if not t then
        t = p.overlay:CreateTexture(nil, "ARTWORK")
        t.edge = p.overlay:CreateTexture(nil, "BORDER")
        p.boxes[i] = t
    end
    return t
end

local function paintPreview()
    local p = ui.preview
    local tw, th = GRF.Header.TileSize()
    p:SetSize(tw * PREVIEW_SCALE, th * PREVIEW_SCALE)
    for _, t in ipairs(p.boxes) do t:Hide(); t.edge:Hide() end
    local n = 0
    for _, ind in ipairs(list()) do
        if ind.enabled and GRF.Indicators.Supported(ind) then
            -- Placed as the tiles place them (Indicators.lua styleSlot and
            -- updateDebuffs), in tile units, then scaled.
            local gap = GRF.Indicators.GAP
            local s = ind.size * PREVIEW_SCALE
            local count, step = 1, ind.size + gap
            local point, rel, dx, dy, ox, oy = ind.anchor, ind.anchor, 0, 0, ind.x, ind.y
            if ind.kind == "icons" then
                count = #ind.spells
                local g = GRF.Indicators.GROW[ind.grow]
                dx, dy = g[1] * step, g[2] * step
            elseif ind.kind == "debuffs" then
                -- The row's container is max icons wide, at the anchor; the
                -- icons flow from its left, or its right on a right anchor.
                count = ind.max
                local width = ind.max * ind.size + (ind.max - 1) * gap
                local fromRight = ind.anchor:find("RIGHT") ~= nil
                local v = ind.anchor:find("TOP") and "TOP" or (ind.anchor:find("BOTTOM") and "BOTTOM" or "")
                -- The row's edge sits on the tile's anchor point: a centred
                -- row's left edge half its width left of that point.
                point = v .. (fromRight and "RIGHT" or "LEFT")
                if not fromRight and not ind.anchor:find("LEFT") then ox = ox - width / 2 end
                dx = (fromRight and -1 or 1) * step
            end
            for j = 1, count do
                n = n + 1
                local t = previewBox(n)
                t:SetSize(s, s)
                t:ClearAllPoints()
                t:SetPoint(point, p, rel, (ox + (j - 1) * dx) * PREVIEW_SCALE, (oy + (j - 1) * dy) * PREVIEW_SCALE)
                if ind.kind == "square" then
                    t:SetColorTexture(ind.color[1], ind.color[2], ind.color[3], 1)
                elseif ind.kind == "debuffs" then
                    t:SetTexture(SAMPLE_DEBUFF)
                else
                    local id = ind.kind == "icons" and ind.spells[j] or ind.spells[1]
                    t:SetTexture(id and API.SpellTexture(id) or nil)
                end
                t:Show()
                if ind.key == selectedKey then
                    t.edge:SetPoint("TOPLEFT", t, "TOPLEFT", -2, 2)
                    t.edge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -2)
                    t.edge:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
                    t.edge:Show()
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Spells
--------------------------------------------------------------------------------

local function spellRow(i)
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(290, 20)
    r:SetPoint("TOPLEFT", ui.spellsTitle, "BOTTOMLEFT", 0, -4 - (i - 1) * 21)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name = label(r, "")
    r.name:SetWidth(150)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.id = label(r, "", "GameFontDisableSmall")
    r.id:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
    r.remove = button(r, "X", 22, function()
        GRF.Settings.RemoveIndicatorSpell(selected(), i)
        IO.Refresh()
    end)
    r.remove:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.down = button(r, "v", 22, function()
        GRF.Settings.MoveIndicatorSpell(selected(), i, 1)
        IO.Refresh()
    end)
    r.down:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
    r.up = button(r, "^", 22, function()
        GRF.Settings.MoveIndicatorSpell(selected(), i, -1)
        IO.Refresh()
    end)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    return r
end

-- A spell dragged from the spellbook (GetCursorInfo's 4th return is its ID).
local function takeCursorSpell()
    local kind, _, _, spellID = GetCursorInfo()
    if kind ~= "spell" or type(spellID) ~= "number" then return end
    ClearCursor()
    local ok, why = GRF.Settings.AddIndicatorSpell(selected(), spellID)
    ui.addNote:SetText(ok and "" or ("|cffff8040" .. why .. "|r"))
    IO.Refresh()
end

local function addTyped()
    local id = tonumber(ui.idBox:GetText())
    local ok, why = GRF.Settings.AddIndicatorSpell(selected(), id)
    if ok then ui.idBox:SetText("") end
    ui.addNote:SetText(ok and "" or ("|cffff8040" .. tostring(why) .. "|r"))
    IO.Refresh()
end

-- The typed ID's icon and name, as you type.
local function previewTyped()
    local id = tonumber(ui.idBox:GetText())
    local name = id and API.SpellName(id)
    ui.idIcon:SetTexture(name and API.SpellTexture(id) or nil)
    ui.idName:SetText(name or (id and "|cffff8040unknown spell|r" or ""))
    ui.idAdd:SetEnabled(name ~= nil)
end

local function paintSpells(ind)
    local slotted = ind.kind ~= "debuffs"
    ui.spells:SetShown(slotted)
    ui.debuffs:SetShown(not slotted)
    if not slotted then return end
    local ordered = ind.kind ~= "icons" or #ind.spells > 1
    ui.spellsTitle:SetText(ind.kind == "icons" and "Spells (one spot each, in this order)"
        or "Spells (the first one present shows)")
    for i = 1, IO.SPELL_ROWS do
        local r = ui.spellRows[i]
        local id = ind.spells[i]
        r:SetShown(id ~= nil)
        if id then
            r.icon:SetTexture(API.SpellTexture(id))
            r.name:SetText(API.SpellName(id) or "|cffff8040unknown|r")
            r.id:SetText(tostring(id))
            r.up:SetEnabled(ordered and i > 1)
            r.down:SetEnabled(ordered and i < #ind.spells)
        end
    end
    local full = #ind.spells >= GRF.Indicators.MAX_SPELLS
    ui.drop:SetEnabled(not full)
    ui.idBox:SetEnabled(not full)
    local capNote = "Up to " .. GRF.Indicators.MAX_SPELLS .. " spells."
    if full then ui.addNote:SetText(capNote)
    elseif ui.addNote:GetText() == capNote then ui.addNote:SetText("") end
    previewTyped()
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local paint   -- the repaint body, below

function IO.Refresh()
    if not page.built then return end
    refreshing = true
    local ok, err = pcall(paint)
    refreshing = false   -- always: a stuck flag would make every control ignore clicks
    if not ok then API.Fail("indicators page", err) end
end

paint = function()
    local ind = selected()
    local okC, className = pcall(UnitClass, "player")   -- the client's own, localized
    className = (okC and type(className) == "string" and not API.IsSecret(className)) and className or "?"
    ui.shared:SetText("Shared by all your characters of this class (" .. className .. ").")
    ui.status:SetText(GRF.Indicators.pending and "|cffffd040Changes apply when combat ends.|r" or "")
    paintList()
    ui.add:SetEnabled(#list() < GRF.Indicators.MAX_INDICATORS)
    ui.settings:SetShown(ind ~= nil)
    if ind then
        -- Keep a rename being typed on its own indicator; when the selection
        -- moved on (a row click, Add, a reset), commit the draft to its owner
        -- first (ClearFocus fires OnEditFocusLost), then show the new name.
        if ui.name:HasFocus() and ui.name.owner ~= ind then ui.name:ClearFocus() end
        if not ui.name:HasFocus() then ui.name:SetText(ind.name) end
        ui.name:SetEnabled(not ind.builtin)
        ui.delete:SetEnabled(not ind.builtin)
        if ui.delete.armed ~= ind.key then
            ui.delete.armed = nil   -- armed for another indicator: start over
            ui.delete:SetText("Delete")
        end
        ui.enabled:SetChecked(ind.enabled)
        local slotted = ind.kind ~= "debuffs"
        for _, w in ipairs(ui.slotOnly) do w:SetShown(slotted) end
        if slotted then
            ui.mine:SetChecked(ind.mine)
            ui.aura.set(ind.aura)
            ui.kind.set(ind.kind)
            ui.grow.set(ind.grow)
            for _, b in ipairs(ui.grow) do b:SetShown(ind.kind == "icons") end
            ui.growLabel:SetShown(ind.kind == "icons")
            ui.swipe:SetChecked(ind.swipe)
            ui.timer:SetChecked(ind.timer)
            ui.color:SetShown(ind.kind == "square")
            ui.colorLabel:SetShown(ind.kind == "square")
            ui.colorSwatch:SetColorTexture(ind.color[1], ind.color[2], ind.color[3], 1)
        else
            ui.filter.set(ind.filter)
            ui.max:SetValue(ind.max)
        end
        local ok, why = GRF.Indicators.Supported(ind)
        ui.help:SetText(KIND_HELP[ind.kind] .. ((not ok and why ~= "no spells") and ("\n|cffff8040" .. why .. "|r") or ""))
        for _, cell in ipairs(ui.anchors) do cell.lit:SetShown(cell.anchor == ind.anchor) end
        ui.x:SetValue(ind.x)
        ui.y:SetValue(ind.y)
        ui.size:SetValue(ind.size)
        ui.x.value:SetText(tostring(ind.x)); ui.y.value:SetText(tostring(ind.y)); ui.size.value:SetText(tostring(ind.size))
        paintSpells(ind)
    end
    paintPreview()
end

local function build()
    local S = GRF.Settings
    local title = label(content, "Indicators", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    ui.shared = label(content, "", "GameFontHighlightSmall")
    ui.shared:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    ui.status = label(content, "", "GameFontNormalSmall")
    ui.status:SetPoint("LEFT", ui.shared, "RIGHT", 12, 0)

    -- The list and its buttons.
    ui.rows = {}
    for i = 1, IO.ROWS do ui.rows[i] = listRow(i) end
    local listBottom = TOP_Y - IO.ROWS * 22 - 4
    ui.add = button(content, "Add", 68, function()
        local ind = S.AddIndicator()
        if ind then selectedKey = ind.key end
        IO.Refresh()
    end)
    ui.add:SetPoint("TOPLEFT", content, "TOPLEFT", LIST_X, listBottom)
    -- Delete takes two clicks (no popup: StaticPopup is shared UI).
    ui.delete = button(content, "Delete", 68, function(self)
        local ind = selected()
        if not ind or ind.builtin then return end
        if self.armed ~= ind.key then
            self.armed = ind.key
            self:SetText("Sure?")
            return
        end
        self.armed = nil
        S.RemoveIndicator(ind)
        selectedKey = nil
        IO.Refresh()
    end)
    ui.delete:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
    ui.up = button(content, "Up", 68, function() S.MoveIndicator(selected(), -1); IO.Refresh() end)
    ui.up:SetPoint("TOPLEFT", ui.add, "BOTTOMLEFT", 0, -4)
    ui.down = button(content, "Down", 68, function() S.MoveIndicator(selected(), 1); IO.Refresh() end)
    ui.down:SetPoint("LEFT", ui.up, "RIGHT", 4, 0)
    ui.reset = button(content, "Reset to class defaults", 140, function()
        -- A reset starts over: a rename being typed is dropped, not saved.
        ui.name.owner = nil
        if ui.name:HasFocus() then ui.name:ClearFocus() end
        S.ResetIndicators()
        selectedKey = nil
        IO.Refresh()
    end)
    ui.reset:SetPoint("TOPLEFT", ui.up, "BOTTOMLEFT", 0, -12)

    -- Settings of the selected indicator.
    local set = CreateFrame("Frame", nil, content)
    set:SetPoint("TOPLEFT", content, "TOPLEFT", MID_X, TOP_Y)
    set:SetSize(290, 232)   -- the spells (or the debuff options) start below, at TOP_Y - 240
    ui.settings = set
    ui.slotOnly = {}
    local function slotOnly(w) ui.slotOnly[#ui.slotOnly + 1] = w; return w end

    ui.name = editBox(set, 140, false)
    ui.name:SetPoint("TOPLEFT", set, "TOPLEFT", 4, 0)
    -- Saved on Enter or when the box loses focus (clicking elsewhere).
    -- The draft belongs to the indicator TABLE it was started on, whatever is
    -- selected when it saves, and only while that indicator is still in the
    -- setup: a reset reuses the keys on new tables, so a key would rename the
    -- new default (Codex reviews of #23).
    local function stillListed(ind)
        for _, other in ipairs(list()) do
            if other == ind then return true end
        end
        return false
    end
    local function saveName(self)
        local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local ind = self.owner
        self.owner = nil
        if ind and stillListed(ind) and not ind.builtin and text ~= "" and text ~= ind.name then
            GRF.Settings.EditIndicator(ind, "name", text)
        end
    end
    ui.name:SetScript("OnEditFocusGained", function(self) self.owner = selected() end)
    ui.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ui.name:SetScript("OnEditFocusLost", function(self) saveName(self); IO.Refresh() end)
    ui.enabled = checkbox(set, "Enabled", function(on) edit("enabled", on) end)
    ui.enabled:SetPoint("LEFT", ui.name, "RIGHT", 10, 0)

    ui.mine = slotOnly(checkbox(set, "Only mine", function(on) edit("mine", on) end))
    ui.mine:SetPoint("TOPLEFT", set, "TOPLEFT", 0, -24)
    ui.aura = choices(set, { { "HELPFUL", "Buffs" }, { "HARMFUL", "Debuffs" } }, 66, function(v) edit("aura", v) end)
    ui.aura[1]:SetPoint("LEFT", ui.mine.label, "RIGHT", 12, 0)
    for _, b in ipairs(ui.aura) do slotOnly(b) end
    ui.kind = choices(set, KINDS, 80, function(v) edit("kind", v) end)
    ui.kind[1]:SetPoint("TOPLEFT", set, "TOPLEFT", 2, -50)
    for _, b in ipairs(ui.kind) do slotOnly(b) end

    ui.help = label(set, "", "GameFontHighlightSmall")
    ui.help:SetWidth(286)
    ui.help:SetPoint("TOPLEFT", set, "TOPLEFT", 2, -76)

    -- Position: a 3x3 anchor grid, then offsets and size.
    local posLabel = label(set, "Position", "GameFontNormalSmall")
    posLabel:SetPoint("TOPLEFT", set, "TOPLEFT", 2, -104)
    ui.anchors = {}
    for r = 1, 3 do
        for c = 1, 3 do
            local cell = CreateFrame("Button", nil, set)
            cell:SetSize(14, 14)
            cell:SetPoint("TOPLEFT", posLabel, "BOTTOMLEFT", (c - 1) * 16, -4 - (r - 1) * 16)
            local bg = cell:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(cell)
            bg:SetColorTexture(0.25, 0.25, 0.3, 0.9)
            cell.lit = cell:CreateTexture(nil, "ARTWORK")
            cell.lit:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
            cell.lit:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
            cell.lit:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            cell.anchor = GRID[r][c]
            cell:SetScript("OnClick", function(self) edit("anchor", self.anchor) end)
            ui.anchors[#ui.anchors + 1] = cell
        end
    end
    ui.x = slider(set, "X", -40, 40, function(v) editLater("x", v) end)
    ui.x:SetPoint("TOPLEFT", set, "TOPLEFT", 90, -122)
    ui.y = slider(set, "Y", -40, 40, function(v) editLater("y", v) end)
    ui.y:SetPoint("TOPLEFT", ui.x, "BOTTOMLEFT", 0, -10)
    ui.size = slider(set, "Size", GRF.Indicators.MIN_SIZE, GRF.Indicators.MAX_SIZE, function(v) editLater("size", v) end)
    ui.size:SetPoint("TOPLEFT", ui.y, "BOTTOMLEFT", 0, -10)

    ui.growLabel = slotOnly(label(set, "Grow", "GameFontHighlightSmall"))
    ui.growLabel:SetPoint("TOPLEFT", set, "TOPLEFT", 2, -184)
    ui.grow = choices(set, GROWS, 50, function(v) edit("grow", v) end)
    ui.grow[1]:SetPoint("LEFT", ui.growLabel, "RIGHT", 8, 0)
    for _, b in ipairs(ui.grow) do slotOnly(b) end
    ui.swipe = slotOnly(checkbox(set, "Cooldown swipe", function(on) edit("swipe", on) end))
    ui.swipe:SetPoint("TOPLEFT", set, "TOPLEFT", 0, -206)
    ui.timer = slotOnly(checkbox(set, "Timer text", function(on) edit("timer", on) end))
    ui.timer:SetPoint("LEFT", ui.swipe.label, "RIGHT", 12, 0)
    slotOnly(ui.swipe.label); slotOnly(ui.timer.label); slotOnly(ui.mine.label)
    ui.colorLabel = slotOnly(label(set, "Colour", "GameFontHighlightSmall"))
    ui.colorLabel:SetPoint("LEFT", ui.timer.label, "RIGHT", 12, 0)
    -- Click cycles a small palette (no colour picker: one more shared UI).
    ui.color = slotOnly(CreateFrame("Button", nil, set))
    ui.color:SetSize(16, 16)
    ui.color:SetPoint("LEFT", ui.colorLabel, "RIGHT", 6, 0)
    ui.colorSwatch = ui.color:CreateTexture(nil, "ARTWORK")
    ui.colorSwatch:SetAllPoints(ui.color)
    ui.color:SetScript("OnClick", function()
        local ind = selected()
        local cur, n = ind.color, 1
        for i, c in ipairs(PALETTE) do
            if math.abs(c[1] - cur[1]) < 0.01 and math.abs(c[2] - cur[2]) < 0.01 and math.abs(c[3] - cur[3]) < 0.01 then n = i % #PALETTE + 1 end
        end
        local c = PALETTE[n]
        edit("color", { c[1], c[2], c[3] })
    end)

    -- The debuff row's own options, in the spells' place.
    ui.debuffs = CreateFrame("Frame", nil, content)
    ui.debuffs:SetPoint("TOPLEFT", content, "TOPLEFT", MID_X, TOP_Y - 240)
    ui.debuffs:SetSize(290, 60)
    local dl = label(ui.debuffs, "Show", "GameFontNormalSmall")
    dl:SetPoint("TOPLEFT", ui.debuffs, "TOPLEFT", 2, 0)
    ui.filter = choices(ui.debuffs, { { "all", "Every debuff" }, { "dispellable", "Only ones I can dispel" } }, 140,
        function(v) edit("filter", v) end)
    ui.filter[1]:SetPoint("TOPLEFT", dl, "BOTTOMLEFT", 0, -4)
    ui.max = slider(ui.debuffs, "How many", 1, GRF.Indicators.MAX_DEBUFFS, function(v) editLater("max", v) end)
    ui.max:SetPoint("TOPLEFT", ui.filter[1], "BOTTOMLEFT", 60, -10)

    -- Spells.
    ui.spells = CreateFrame("Frame", nil, content)
    ui.spells:SetPoint("TOPLEFT", content, "TOPLEFT", MID_X, TOP_Y - 240)
    ui.spells:SetSize(440, 230)
    ui.spellsTitle = label(ui.spells, "", "GameFontNormalSmall")
    ui.spellsTitle:SetPoint("TOPLEFT", ui.spells, "TOPLEFT", 2, 0)
    ui.spellRows = {}
    for i = 1, IO.SPELL_ROWS do
        local r = spellRow(i)
        r:SetParent(ui.spells)
        ui.spellRows[i] = r
    end
    local addY = -4 - IO.SPELL_ROWS * 21 - 4
    ui.drop = CreateFrame("Button", nil, ui.spells)
    ui.drop:SetSize(150, 22)
    ui.drop:SetPoint("TOPLEFT", ui.spellsTitle, "BOTTOMLEFT", 0, addY)
    local dropBg = ui.drop:CreateTexture(nil, "BACKGROUND")
    dropBg:SetAllPoints(ui.drop)
    dropBg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
    local dropText = label(ui.drop, "Drop a spell here", "GameFontHighlightSmall")
    dropText:SetPoint("CENTER", ui.drop, "CENTER", 0, 0)
    ui.drop:RegisterForClicks("LeftButtonUp")
    ui.drop:SetScript("OnReceiveDrag", takeCursorSpell)
    ui.drop:SetScript("OnClick", takeCursorSpell)
    local orId = label(ui.spells, "or ID", "GameFontHighlightSmall")
    orId:SetPoint("LEFT", ui.drop, "RIGHT", 8, 0)
    ui.idBox = editBox(ui.spells, 60, true)
    ui.idBox:SetPoint("LEFT", orId, "RIGHT", 8, 0)
    ui.idBox:SetScript("OnTextChanged", previewTyped)
    ui.idBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); addTyped() end)
    ui.idIcon = ui.spells:CreateTexture(nil, "ARTWORK")
    ui.idIcon:SetSize(18, 18)
    ui.idIcon:SetPoint("LEFT", ui.idBox, "RIGHT", 6, 0)
    ui.idName = label(ui.spells, "", "GameFontHighlightSmall")
    ui.idName:SetWidth(100)
    ui.idName:SetPoint("LEFT", ui.idIcon, "RIGHT", 4, 0)
    ui.idAdd = button(ui.spells, "Add", 50, addTyped)
    ui.idAdd:SetPoint("LEFT", ui.idName, "RIGHT", 4, 0)
    ui.addNote = label(ui.spells, "", "GameFontHighlightSmall")
    ui.addNote:SetPoint("TOPLEFT", ui.drop, "BOTTOMLEFT", 0, -4)

    -- The preview tile.
    local p = CreateFrame("Frame", nil, content)
    p:SetPoint("TOPLEFT", content, "TOPLEFT", PREVIEW_X, TOP_Y)
    GRF.Glass.Apply(p, "small")
    p.overlay = CreateFrame("Frame", nil, p)
    p.overlay:SetAllPoints(p)
    p.overlay:SetFrameLevel(p:GetFrameLevel() + 12)
    local okG, guid = pcall(UnitGUID, "player")
    local okN, me = pcall(GRF.Frames.NameFor, "player", (okG and not API.IsSecret(guid)) and guid or nil)
    p.name = label(p.overlay, "", "GameFontHighlightLarge")
    if okN and not API.IsSecret(me) then p.name:SetText(me) end
    p.name:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.boxes = {}
    ui.preview = p
    local pl = label(content, "Preview", "GameFontNormalSmall")
    pl:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, 4)
end

page:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        build()
    end
    IO.Refresh()
end)

-- Registered by Options.lua, after Click-casting (in order).
function IO.Register(parent)
    if not (parent and Settings and Settings.RegisterCanvasLayoutSubcategory) then
        API.Fail("indicators page", "no parent category or no Settings subcategory API")
        return
    end
    local ok, err = pcall(Settings.RegisterCanvasLayoutSubcategory, parent, page, page.name)
    if not ok then API.Fail("indicators page", err) end
end

-- Repaint on every change: applied, or deferred in combat.
GRF.Indicators.onChanged = function() if page:IsShown() then IO.Refresh() end end

IO._test = { page = page, ui = ui, select = function(key) selectedKey = key end }
