-- ClickCast.lua: click-casting and hover keys (#3), one binding list per
-- character and per role (GlassRaidFramesCharDB.profiles[role].bindings).
--
-- A binding row: { key = "SHIFT-R" } or { mouse = "shift-1" }, plus
-- { spell = <spell ID>, pinned = true|nil }. Spells are stored by ID, never by
-- name (localized clients); names are resolved from the ID at apply time.
--
-- What the design rests on (docs/FOREVER-PROBE.md):
-- - MOUSE rows are attributes on the 40 header children ("shift-type1" =
--   "spell"): measured to cast on the clicked unit, in combat. Modifier
--   prefixes in Blizzard's alt-ctrl-shift- order (SecureTemplates.lua:82).
-- - A pinned rank is its own spell ID: a numeric `spell` attribute keeps the
--   rank (measured: rank 1 cast with rank 3 known). Unpinned rows use the
--   bare name, which casts the highest rank known.
-- - KEY rows: one hidden SecureActionButtonTemplate per key (a modifier held
--   on a key binding does NOT select modified attributes: measured), bound
--   with SetOverrideBindingClick. Its macro casts only on a hovered GROUP
--   MEMBER (the owner's rule: never a stranger under the cursor; measured,
--   test B) and otherwise clicks the key's own action button, so the key keeps
--   its normal job. The fallback is the exact complement of the cast's
--   condition (Codex: [nohelp], not [harm]). Macros stay under 255 characters
--   (an 848-character one never reached its end: measured).
-- - Resurrection spells (by ID) aim at DEAD members instead.
-- - Everything protected happens out of combat, through the addon's one combat
--   queue, in ONE reconciliation that only changes what differs, so our own
--   binding changes (UPDATE_BINDINGS) can't loop.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
local ClickCast = {}
GRF.ClickCast = ClickCast

ClickCast.MAX_MACRO = 255
ClickCast.MODIFIERS = { "alt", "ctrl", "shift" }   -- Blizzard's prefix order

-- Resurrection spells, every Vanilla rank (plus Revive): aimed at the dead.
ClickCast.REZ = {}
for _, id in ipairs({ 2006, 2010, 10880, 10881, 20770,      -- Resurrection
                      7328, 10322, 10324, 20772, 20773,     -- Redemption
                      2008, 20609, 20610, 20776, 20777,     -- Ancestral Spirit
                      20484, 20739, 20742, 20747, 20748,    -- Rebirth
                      50769 }) do                            -- Revive
    ClickCast.REZ[id] = true
end

-- The action bars whose buttons a key can fall back to, found at runtime by
-- each button's own commandName (Blizzard_ActionBar/Shared/ActionBar.lua:37).
ClickCast.BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
                   "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }

--------------------------------------------------------------------------------
-- Pure helpers
--------------------------------------------------------------------------------

-- "shift-1" / "alt-ctrl-2": the attribute prefix and the button number, or nil.
function ClickCast.ParseMouse(bind)
    if type(bind) ~= "string" then return nil end
    local mods, button = bind:match("^(.-)(%d)$")
    button = tonumber(button)
    if not button or button < 1 or button > 5 then return nil end
    return mods, button
end

-- Canonical mouse binding from modifier states and a button number.
function ClickCast.MouseBind(alt, ctrl, shift, button)
    return (alt and "alt-" or "") .. (ctrl and "ctrl-" or "") .. (shift and "shift-" or "") .. button
end

-- Canonical key binding ("ALT-CTRL-SHIFT-R"), as WoW names bindings.
function ClickCast.KeyBind(alt, ctrl, shift, key)
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

-- Which modifier a binding uses, e.g. for the SELFCAST warning.
function ClickCast.UsesModifier(row, mod)
    mod = mod:lower()
    if row.mouse then return (row.mouse:find(mod .. "-", 1, true)) ~= nil end
    if row.key then return (row.key:lower():find(mod .. "-", 1, true)) ~= nil end
    return false
end

--------------------------------------------------------------------------------
-- Resolving a row (client data: all through pcall)
--------------------------------------------------------------------------------

-- What a spell attribute gets: the pinned rank's ID, or the bare localized
-- name (the highest rank known). nil when the client doesn't know the spell.
function ClickCast.AttributeValue(row)
    local name = row.spell and API.SpellName(row.spell)
    if not name then return nil end
    if row.pinned then return row.spell end
    return name
end

-- What a /cast line gets: "Name(Rank n)" for a pinned rank (both localized,
-- from the ID), else the bare name.
function ClickCast.CastText(row)
    local name = row.spell and API.SpellName(row.spell)
    if not name then return nil end
    if row.pinned then
        local sub = API.SpellSubtext(row.spell)
        if sub then return name .. "(" .. sub .. ")" end
    end
    return name
end

-- commandName -> action button frame name, from the live bars.
local function actionButtons()
    local map = {}
    for _, barName in ipairs(ClickCast.BARS) do
        local bar = rawget(_G, barName)
        local list = type(bar) == "table" and bar.actionButtons
        if type(list) == "table" then
            for _, b in ipairs(list) do
                local cmd, name = b.commandName, b.GetName and b:GetName()
                if type(cmd) == "string" and type(name) == "string" then map[cmd] = name end
            end
        end
    end
    return map
end
ClickCast.ActionButtons = actionButtons

-- The frame a key falls back to: nil (unbound: no fallback), a frame name, or
-- false plus the command when the key does something we can't click (then we
-- leave the key alone rather than take its command away).
-- An unbound MODIFIED key (SHIFT-R) falls back, as the client does, to the
-- plain key's binding (R): an action button there is clicked; anything else
-- is simply not reproduced (the options say so). Returns: frame name, or nil,
-- or false plus the command when the key's OWN binding is a non-action one.
function ClickCast.Fallback(key, buttons)
    buttons = buttons or actionButtons()
    local ok, action = pcall(GetBindingAction, key)   -- the base binding, not our override
    if ok and type(action) == "string" and action ~= "" then
        local frame = buttons[action]
        if frame then return frame end
        return false, action
    end
    local plain = key:match("^[%u]+%-(.+)$") and key:gsub("^ALT%-", ""):gsub("^CTRL%-", ""):gsub("^SHIFT%-", "")
    if plain and plain ~= key then
        local okP, plainAction = pcall(GetBindingAction, plain)
        if okP and type(plainAction) == "string" and plainAction ~= "" then
            local frame = buttons[plainAction]
            if frame then return frame end
            return nil, nil, plainAction   -- the plain key's command is lost off-frame
        end
    end
    return nil
end

-- The key's macro, or nil plus a reason.
function ClickCast.KeyMacro(row, buttons)
    local cast = ClickCast.CastText(row)
    if not cast then return nil, "spell unknown" end
    local rez = ClickCast.REZ[row.spell]
    local alive, notAlive = rez and "dead" or "nodead", rez and "nodead" or "dead"
    local text = "/cast [@mouseover,help," .. alive .. ",party][@mouseover,help," .. alive .. ",raid] " .. cast
    local fallback, command, lostPlain = ClickCast.Fallback(row.key, buttons)
    if fallback == false then return nil, "key is bound to " .. command .. ", not an action button" end
    if lostPlain then ClickCast.notes[row] = "off a frame it no longer does " .. lostPlain end
    if fallback then
        text = text .. "\n/click [@mouseover,noparty,noraid][@mouseover,noexists][@mouseover,nohelp][@mouseover,"
            .. notAlive .. "] " .. fallback
    end
    if #text > ClickCast.MAX_MACRO then return nil, "too long for a macro (" .. #text .. " characters)" end
    return text
end

--------------------------------------------------------------------------------
-- The desired state and the one reconciliation
--------------------------------------------------------------------------------

-- The current role's rows (per character).
function ClickCast.Rows(role)
    local char = GRF.char
    role = role or GRF.role
    if not (char and role) then return {} end
    char.profiles = char.profiles or {}
    char.profiles[role] = char.profiles[role] or {}
    local prof = char.profiles[role]
    if type(prof.bindings) ~= "table" then prof.bindings = {} end
    return prof.bindings
end

-- Desired state for `rows`: mouse attributes { attr = value } and key macros
-- { KEY = text }, plus per-row problems { [row] = reason } for the options.
function ClickCast.Desired(rows)
    local attrs, keys, problems = {}, {}, {}
    local buttons = actionButtons()
    for _, row in ipairs(rows) do
        -- A row for a spell this character hasn't learned (a respec, another
        -- character's list) stays saved but isn't installed: the click or key
        -- keeps its normal job, and the row says why (Codex review).
        local learned = row.spell ~= nil and API.SpellKnown(row.spell)
        if row.spell and not learned and API.SpellName(row.spell) then
            problems[row] = "not learned on this character"
        elseif row.mouse then
            local mods, button = ClickCast.ParseMouse(row.mouse)
            local value = mods and ClickCast.AttributeValue(row)
            if value then
                attrs[mods .. "type" .. button] = "spell"
                attrs[mods .. "spell" .. button] = value
            else
                problems[row] = mods and "spell unknown" or "bad binding"
            end
        elseif type(row.key) == "string" and row.key ~= "" then
            local text, why = ClickCast.KeyMacro(row, buttons)
            if text then keys[row.key] = text else problems[row] = why end
        end
    end
    return attrs, keys, problems
end

local installedAttrs, installedKeys = {}, {}
local keyButtons = {}   -- KEY -> hidden secure button
local owner              -- the override bindings' owner (one frame, cleared as a whole)
ClickCast.problems = {}
ClickCast.notes = {}     -- [row] = a non-blocking remark for the options
ClickCast.pending = false
ClickCast.onApplied = nil   -- set by the options page: repaint after each Apply

local function same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function keyButton(key)
    local b = keyButtons[key]
    if not b then
        local n = 0
        for _ in pairs(keyButtons) do n = n + 1 end
        b = CreateFrame("Button", "GlassRaidFramesKey" .. (n + 1), UIParent, "SecureActionButtonTemplate")
        -- Both edges: this template acts on the one ActionButtonUseKeyDown
        -- picks (measured one cast per press, porting guide).
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        keyButtons[key] = b
    end
    return b
end

-- Bring the frames and bindings to the desired state. Out of combat only
-- (queued through GRF.WhenOutOfCombat); changes nothing when already there.
function ClickCast.Apply()
    if InCombatLockdown() then return false end
    ClickCast.pending = false
    ClickCast.notes = {}
    local attrs, keys, problems = ClickCast.Desired(ClickCast.Rows())
    ClickCast.problems = problems
    -- Group and pet tiles alike: mouse bindings work on a pet's tile too.
    local children = GRF.Header and GRF.Header.AllChildren() or {}

    -- No children yet (the grid isn't built): nothing to record as installed,
    -- or the attributes would never reach them. The build applies again.
    if #children > 0 and not same(attrs, installedAttrs) then
        for _, child in ipairs(children) do
            for attr in pairs(installedAttrs) do
                if attrs[attr] == nil then child:SetAttribute(attr, nil) end
            end
            for attr, value in pairs(attrs) do child:SetAttribute(attr, value) end
        end
        installedAttrs = attrs
    end

    if not same(keys, installedKeys) then
        owner = owner or CreateFrame("Frame", "GlassRaidFramesKeyOwner", UIParent)
        ClearOverrideBindings(owner)
        local bound = {}
        for key, text in pairs(keys) do
            local b = keyButton(key)
            b:SetAttribute("macrotext", text)
            local ok, err = pcall(SetOverrideBindingClick, owner, true, key, b:GetName())
            if ok then
                bound[key] = text
            else
                -- Not recorded as installed, so the next reconciliation retries it.
                API.Fail("bind " .. key, err)
                for _, row in ipairs(ClickCast.Rows()) do
                    if row.key == key then problems[row] = "the client refused this key" end
                end
            end
        end
        installedKeys = bound
    end
    if ClickCast.onApplied then pcall(ClickCast.onApplied) end
    return true
end

-- Ask for a reconciliation: now, or when combat ends (the installed bindings
-- keep working until then; the options show it as pending). The open editor
-- repaints either way, so it always shows the current role's rows (Codex
-- review: a role change in combat left the old role's rows editable).
function ClickCast.Request()
    if InCombatLockdown() then ClickCast.pending = true end
    GRF.WhenOutOfCombat("clickcast", ClickCast.Apply, false)
    if ClickCast.pending and ClickCast.onApplied then pcall(ClickCast.onApplied) end
end

-- Anything that can change a spell's name/rank or a key's base binding.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function() ClickCast.Request() end)
API.RegisterEvents(watcher, { "SPELLS_CHANGED", "UPDATE_BINDINGS" })

--------------------------------------------------------------------------------
-- Editing (the options call these; each re-applies)
--------------------------------------------------------------------------------

-- Add or replace the row for a binding; returns the row. With no spell (a
-- freshly captured binding), an existing row is returned untouched: capturing
-- a binding twice must never erase its spell.
function ClickCast.Set(bind, isMouse, spell, pinned)
    local rows = ClickCast.Rows()
    for _, row in ipairs(rows) do
        if (isMouse and row.mouse == bind) or (not isMouse and row.key == bind) then
            if spell == nil then return row end
            row.spell, row.pinned = spell, pinned or nil
            ClickCast.Request()
            return row
        end
    end
    local row = isMouse and { mouse = bind } or { key = bind }
    row.spell, row.pinned = spell, pinned or nil
    rows[#rows + 1] = row
    ClickCast.Request()
    return row
end

function ClickCast.Remove(row)
    local rows = ClickCast.Rows()
    for i, r in ipairs(rows) do
        if r == row then table.remove(rows, i) break end
    end
    ClickCast.Request()
end

-- Warnings about a row, for the options (clicks under the SELFCAST modifier
-- go to you: measured; Alt on a KEY is fine: measured).
function ClickCast.Warnings(row)
    local out = {}
    if ClickCast.problems[row] then out[#out + 1] = ClickCast.problems[row] end
    if ClickCast.notes[row] then out[#out + 1] = ClickCast.notes[row] end
    if row.mouse then
        local ok, mod = pcall(GetModifiedClick, "SELFCAST")
        if ok and type(mod) == "string" and mod ~= "NONE" and ClickCast.UsesModifier(row, mod) then
            out[#out + 1] = mod:lower() .. " is your Self Cast key: this click casts on you"
        end
        if row.mouse == "1" or row.mouse == "2" then
            out[#out + 1] = "replaces the plain " .. (row.mouse == "1" and "target" or "menu") .. " click"
        end
    end
    return out
end

ClickCast._test = { installed = function() return installedAttrs, installedKeys end, keyButtons = keyButtons,
                    owner = function() return owner end, watcher = watcher }
