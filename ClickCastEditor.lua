-- UI-independent draft/transaction model shared by standard and Quick Bind.
-- Never mutate saved rows until an explicit successful commit.
local GRF = GlassRaidFrames
local CC, API = GRF.ClickCast, GRF.API
local E = {}
GRF.ClickCastEditor = E
local MOUSE = { "Left click", "Right click", "Middle click", "Mouse 4", "Mouse 5" }
local ACTIONS = { target = "Target unit", togglemenu = "Open unit menu", macro = "Macro" }
E.MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true }
E.MOUSE_BUTTONS = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }

function E.Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = E.Copy(v) end
    return out
end

function E.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not E.Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function E.Rows(role)
    local profiles = GRF.char and GRF.char.profiles
    return profiles and profiles[role] and profiles[role].bindings or {}
end

-- Existing strings and recorded inputs share the same normalization. A keyboard
-- BUTTONn alias occupies the same physical input as its mouse counterpart.
function E.Input(row)
    local mouse = row.mouse ~= nil
    local bind = row.mouse or row.key
    if type(bind) ~= "string" or bind == "" or (row.mouse and row.key) then return nil end
    local rest, mods = bind:upper(), {}
    while true do
        local mod, tail = rest:match("^(ALT)%-(.*)$")
        if not mod then mod, tail = rest:match("^(CTRL)%-(.*)$") end
        if not mod then mod, tail = rest:match("^(SHIFT)%-(.*)$") end
        if not mod then break end
        mods[mod], rest = true, tail
    end
    local number = mouse and tonumber(rest) or tonumber(rest:match("^BUTTON([1-5])$"))
    if number then
        if number < 1 or number > 5 or number % 1 ~= 0 then return nil end
        return "mouse", CC.MouseBind(mods.ALT, mods.CTRL, mods.SHIFT, number)
    end
    if mouse or rest == "" or rest == "ESCAPE" or E.MODIFIER_KEYS[rest]
        or rest == "ALT" or rest == "CTRL" or rest == "SHIFT"
        or rest:find("%s") or rest:find("MOUSEWHEEL", 1, true) then return nil end
    return "key", CC.KeyBind(mods.ALT, mods.CTRL, mods.SHIFT, rest)
end

function E.InputID(row)
    local kind, bind = E.Input(row)
    return kind and kind .. ":" .. bind
end

function E.BindingText(row)
    local kind, bind = E.Input(row)
    if not kind then return "Record input" end
    local parts = {}
    for _, mod in ipairs(CC.MODIFIERS) do
        local prefix = mod:upper() .. "-"
        if bind:upper():sub(1, #prefix) == prefix then
            parts[#parts + 1] = mod:sub(1, 1):upper() .. mod:sub(2)
            bind = bind:sub(#prefix + 1)
        end
    end
    parts[#parts + 1] = kind == "mouse" and MOUSE[tonumber(bind)] or bind
    return table.concat(parts, " + ")
end

function E.ActionText(row)
    local action = row.action or "spell"
    if action == "spell" then return row.spell and (API.SpellName(row.spell) or ("Unavailable spell #" .. row.spell)) or "Choose an action" end
    if action == "macro" then return row.name and row.name ~= "" and row.name or "Macro" end
    return ACTIONS[action] or "Unsupported saved action"
end

function E.RankText(row)
    if (row.action and row.action ~= "spell") or not row.spell then return "—" end
    if not row.pinned then return "Highest" end
    local sub = API.SpellSubtext(row.spell)
    return "Pinned · " .. ((sub and sub ~= "" and sub) or ("spell #" .. row.spell))
end

function E.Matches(row, query)
    query = (query or ""):lower():gsub("control", "ctrl")
    local text = (E.BindingText(row) .. " " .. E.ActionText(row) .. " " .. (ACTIONS[row.action] or "spell")):lower()
    for word in query:gmatch("%S+") do if not text:find(word, 1, true) then return false end end
    return true
end

function E.Conflict(rows, row, exclude)
    local input = E.InputID(row)
    if not input then return nil end
    for _, other in ipairs(rows) do
        if other ~= exclude and E.InputID(other) == input then return other end
    end
end

function E.Validate(row)
    local kind, bind = E.Input(row)
    if not kind then return false, "Record a supported input." end
    local action = row.action or "spell"
    if action == "spell" then
        if not row.spell then return false, "Choose a spell." end
        if not API.SpellKnown(row.spell) then return false, "This spell or rank is unavailable. Choose a learned spell, or keep the saved binding." end
    elseif action == "macro" then
        if type(row.macrotext) ~= "string" or not row.macrotext:find("%S") then return false, "Enter macro text." end
        if #row.macrotext > CC.MAX_MACRO then return false, "Macro exceeds 255 bytes; shorten it before saving." end
    elseif action ~= "target" and action ~= "togglemenu" then return false, "Unsupported saved action; choose a supported action." end
    if kind == "key" then
        local normalized = E.Copy(row)
        normalized.key, normalized.mouse = bind, nil
        if action == "spell" or action == "macro" then
            local text, why = CC.KeyMacro(normalized)
            if not text then return false, why end
        else
            local fallback, command = CC.Fallback(bind)
            if fallback == false then return false, "Key is bound to " .. command .. "; choose another input." end
        end
    end
    return true
end

local function indexOf(rows, row)
    for i, r in ipairs(rows) do if r == row then return i end end
end

local function notify(role)
    if role == GRF.role then CC.Request()
    elseif CC.onApplied then CC.onApplied() end
end

function CC.Commit(role, draft, original, snapshot, replacement, replacementSnapshot)
    if InCombatLockdown() then return nil, "Editing is paused in combat; your draft is kept." end
    if not GRF.Role.VALID[role] then return nil, "Invalid role." end
    local rows = E.Rows(role)
    if original and (not indexOf(rows, original) or not E.Equal(original, snapshot)) then return nil, "Saved binding changed; cancel and reopen it." end
    local valid, why = E.Validate(draft)
    if not valid then return nil, why end
    local conflict = E.Conflict(rows, draft, original)
    if conflict and (conflict ~= replacement or not E.Equal(conflict, replacementSnapshot)) then
        return nil, "Already assigned to " .. E.ActionText(conflict), conflict
    end
    local committed = E.Copy(draft)
    local kind, bind = E.Input(draft)
    committed.mouse, committed.key = nil, nil
    committed[kind] = bind
    rows = CC.Rows(role)
    local at = original and indexOf(rows, original)
    if at then rows[at] = committed else rows[#rows + 1] = committed end
    if conflict then table.remove(rows, indexOf(rows, conflict)) end
    notify(role)
    return committed
end

function CC.Delete(role, original, snapshot)
    if InCombatLockdown() then return false, "Editing is paused in combat." end
    local rows = E.Rows(role)
    local at = indexOf(rows, original)
    if not at or not E.Equal(original, snapshot) then return false, "Saved binding changed; reopen it." end
    table.remove(rows, at)
    notify(role)
    return true
end

local State = {}
State.__index = State
function E.New(role) return setmetatable({ role = role, staged = {} }, State) end
function State:Select(row)
    self.original, self.snapshot = row, row and E.Copy(row) or nil
    self.draft = row and E.Copy(row) or nil
    self.replacement, self.replacementSnapshot = nil, nil
end
function State:NewDraft(spell)
    self:Select(nil)
    self.draft = { spell = spell }
end
function State:Dirty()
    return self.draft ~= nil and (self.original == nil or not E.Equal(self.draft, self.snapshot))
end
function State:Choose(action, spell)
    if not self.draft then self:NewDraft() end
    local d = self.draft
    d.action = action == "spell" and nil or action
    d.spell, d.pinned, d.macrotext, d.name, d.icon = nil, nil, nil, nil, nil
    if action == "spell" then d.spell = spell end
    if action == "macro" then d.macrotext = "" end
end
function State:SetInput(kind, bind)
    if not self.draft then self:NewDraft() end
    self.draft.key, self.draft.mouse = nil, nil
    self.draft[kind] = bind
    self.replacement, self.replacementSnapshot = nil, nil
end
function State:Validity()
    if not self.draft then return false, "Choose a binding or browse actions." end
    local ok, why = E.Validate(self.draft)
    if not ok then return false, why end
    local conflict = E.Conflict(E.Rows(self.role), self.draft, self.original)
    if conflict and (conflict ~= self.replacement or not E.Equal(conflict, self.replacementSnapshot)) then
        return false, "Already assigned to " .. E.ActionText(conflict), conflict
    end
    return self:Dirty(), self:Dirty() and "" or "No unsaved changes."
end
function State:Replace(conflict)
    self.replacement, self.replacementSnapshot = conflict, E.Copy(conflict)
end
function State:Save()
    local ok, why, conflict = self:Validity()
    if not ok then return false, why, conflict end
    local row, err, other = CC.Commit(self.role, self.draft, self.original, self.snapshot, self.replacement, self.replacementSnapshot)
    if row then self:Select(row) end
    return row ~= nil, err, other
end
function State:BeginQuick()
    self.quickBase, self.staged, self.quick = E.Copy(E.Rows(self.role)), {}, true
end
function State:Stage(row, replace)
    local valid, why = E.Validate(row)
    if not valid then return false, why end
    local conflict = E.Conflict(self.staged, row) or E.Conflict(E.Rows(self.role), row)
    if conflict and conflict ~= replace then return false, "Already assigned to " .. E.ActionText(conflict), conflict end
    local at = conflict and indexOf(self.staged, conflict)
    local item = E.Copy(row)
    if at then self.staged[at] = item else self.staged[#self.staged + 1] = item end
    return true
end
function State:ApplyQuick()
    if InCombatLockdown() then return false, "Editing is paused in combat; staged bindings are kept." end
    if not E.Equal(self.quickBase, E.Rows(self.role)) then return false, "Saved bindings changed. Discard this batch and try again." end
    if #self.staged == 0 then return false, "No staged bindings." end
    -- All validation precedes the first saved mutation.
    for _, row in ipairs(self.staged) do
        local valid, why = E.Validate(row)
        if not valid then return false, why end
    end
    local rows = CC.Rows(self.role)
    for _, row in ipairs(self.staged) do
        local conflict = E.Conflict(rows, row)
        local kind, bind = E.Input(row)
        local copy = E.Copy(row)
        copy.key, copy.mouse = nil, nil
        copy[kind] = bind
        if conflict then rows[indexOf(rows, conflict)] = copy else rows[#rows + 1] = copy end
    end
    self.staged, self.quick, self.quickBase = {}, false, nil
    notify(self.role)
    return true
end
function State:DiscardQuick() self.staged, self.quick, self.quickBase = {}, false, nil end

-- Descriptive only: this path never calls the secure compiler or action APIs.
function E.Preview(role, input)
    local row = E.Conflict(E.Rows(role), input)
    if row then
        local text = E.ActionText(row) .. (row.spell and (" · " .. E.RankText(row)) or "")
        if row.spell and not API.SpellKnown(row.spell) then text = text .. " · Unavailable" end
        return text
    end
    local kind, bind = E.Input(input)
    if kind == "mouse" then
        local _, button = CC.ParseMouse(bind)
        if button == 1 then return "Target unit · Default" end
        if button == 2 then return "Open unit menu · Default" end
    end
    return "Unbound"
end
