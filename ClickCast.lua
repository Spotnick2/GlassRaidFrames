-- ClickCast.lua: click-casting and hover keys (#3), one binding list per
-- character and per role (GlassRaidFramesCharDB.profiles[role].bindings).
--
-- A binding row: { key = "SHIFT-R" } or { mouse = "shift-1" }, plus
-- { spell = <spell ID>, pinned = true|nil }. Spells are stored by ID, never by
-- name (localized clients); names are resolved from the ID at apply time.
-- Unit/macro rows instead set action = target|togglemenu|macro; macros carry
-- macrotext and optional display-only name/icon. Old spell rows need no migration.
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
--   ONLY WHILE A GROUP TILE IS HOVERED: a secure OnEnter wrap on each group
--   child runs SetBindingClick (the tile owns the binding), OnLeave/OnHide
--   clear it (Cell's and Clique's design). Our tiles only ever show group
--   members, so the owner's rule (never a stranger under the cursor) holds in
--   combat too. A [party]/[raid] macro check can't do it: both read false in
--   combat, for a member (measured on 70425, /fp steps raid hoverkeycombat).
--   Secure snippets run on 70425 (Execute, state drivers, OnEnter wraps with
--   SetBindingClick, in combat: /fp steps raid snippets), though early builds
--   threw. Off a tile the key keeps its normal job. On a tile, the macro casts
--   on the living member (a rez: the dead one) and otherwise clicks the key's
--   own action button: the exact complement (Codex: [nohelp], not [harm]).
--   Macros stay under 255 characters (an 848-character one never reached its
--   end: measured).
-- - Resurrection spells (by ID) aim at DEAD members instead.
-- - ANY UNIT FRAME (#61): unless db.clickCastOthers is false, the same rows
--   reach Blizzard's unit frames and every frame registered in Clique's
--   ClickCastFrames table (GlassUnitFrames, DinoUF, SUF, oUF...). A frame's
--   own value of an attribute we take is saved and put back when the row or
--   the frame goes. Hover keys get the same wraps, gated per frame by a
--   grf-hover attribute (never unwrapped: SecureHandlerUnwrapScript pops the
--   outermost wrap, which may be another addon's). A target or focus frame
--   can show a stranger, so the snippet binds only for you or a group member:
--   player/partyN/raidN by name, any other token through the restricted
--   UnitPlayerOrPetInParty/InRaid (/fp steps raid ufgate). Never pets.
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

-- Blizzard's unit frames (SecureUnitButtonTemplate, Blizzard_UnitFrame). Its
-- party frames aren't here: Blizzard.lua hides them for our tiles.
ClickCast.BLIZZARD = { "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" }

-- Clique's registry: other addons set ClickCastFrames[frame] = true (false or
-- nil = leave it). Created plain when absent, so registrants and Clique alike
-- can read it; new keys are watched to reach frames built later. A table that
-- already has a metatable belongs to another click-caster: left alone.
local registry = rawget(_G, "ClickCastFrames")
if registry == nil then
    registry = {}
    rawset(_G, "ClickCastFrames", registry)
end
if type(registry) ~= "table" or getmetatable(registry) ~= nil then
    registry = {}
else
    local queued = false
    setmetatable(registry, { __newindex = function(t, frame, on)
        rawset(t, frame, on)
        -- Addons register frames in bursts: one quiet reconciliation next frame.
        if queued then return end
        queued = true
        C_Timer.After(0, function()
            queued = false
            if GRF.WhenOutOfCombat then GRF.WhenOutOfCombat("clickcast", ClickCast.Apply, false) end
        end)
    end })
end

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
        if type(sub) == "string" and sub ~= "" then return name .. "(" .. sub .. ")" end
        if API.SpellTextID(name) == row.spell then return name end
        return nil, "Pinned spell text unavailable; choose a learned rank or Highest."
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
    if row.action == "macro" then
        local fallback, command = ClickCast.Fallback(row.key, buttons)
        if fallback == false then return nil, "key is bound to " .. command .. ", not an action button" end
        if type(row.macrotext) ~= "string" or not row.macrotext:find("%S") then return nil, "enter macro text" end
        if #row.macrotext > ClickCast.MAX_MACRO then return nil, "macro exceeds 255 bytes" end
        return row.macrotext
    end
    local cast, castError = ClickCast.CastText(row)
    if not cast then return nil, castError or "spell unknown" end
    local rez = ClickCast.REZ[row.spell]
    local alive, notAlive = rez and "dead" or "nodead", rez and "nodead" or "dead"
    -- Bound only while a group tile is hovered, so no [party]/[raid] check.
    local text = "/cast [@mouseover,help," .. alive .. "] " .. cast
    local fallback, command, lostPlain = ClickCast.Fallback(row.key, buttons)
    if fallback == false then return nil, "key is bound to " .. command .. ", not an action button" end
    if lostPlain then ClickCast.notes[row] = "on a frame it no longer does " .. lostPlain end
    if fallback then
        text = text .. "\n/click [@mouseover,noexists][@mouseover,nohelp][@mouseover," .. notAlive .. "] " .. fallback
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
-- { KEY = text|{type, unit} }, plus per-row problems for the options.
function ClickCast.Desired(rows)
    local attrs, keys, problems = {}, {}, {}
    local buttons = actionButtons()
    for _, row in ipairs(rows) do
        local action = row.action or "spell"
        -- A row for a spell this character hasn't learned (a respec, another
        -- character's list) stays saved but isn't installed: the click or key
        -- keeps its normal job, and the row says why (Codex review).
        local learned = row.spell ~= nil and API.SpellKnown(row.spell)
        if action == "target" or action == "togglemenu" or action == "macro" then
            local valid = action ~= "macro" or (type(row.macrotext) == "string"
                and row.macrotext:find("%S") and #row.macrotext <= ClickCast.MAX_MACRO)
            if not valid then
                problems[row] = "enter macro text (maximum 255 bytes)"
            elseif row.mouse then
                local mods, button = ClickCast.ParseMouse(row.mouse)
                if mods then
                    attrs[mods .. "type" .. button] = action
                    if action == "macro" then attrs[mods .. "macrotext" .. button] = row.macrotext end
                else problems[row] = "bad binding" end
            elseif type(row.key) == "string" and row.key ~= "" then
                local fallback, command = ClickCast.Fallback(row.key, buttons)
                if fallback == false then problems[row] = "key is bound to " .. command .. ", not an action button"
                elseif action == "macro" then keys[row.key] = row.macrotext
                else keys[row.key] = { type = action, unit = "mouseover" } end
            end
        elseif action ~= "spell" then
            problems[row] = "unsupported saved action"
        elseif row.spell and not learned and API.SpellName(row.spell) then
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
local keyHeader          -- the secure handler whose snippets bind the keys on hover
local weak = { __mode = "k" }
local wrapped = setmetatable({}, weak)    -- frames already wrapped (never unwrapped)
local applied = setmetatable({}, weak)    -- frame -> the attribute set it carries
local original = setmetatable({}, weak)   -- frame -> { attr = its own value, or NONE }
local hovering = setmetatable({}, weak)   -- frames whose grf-hover is on
local NONE, EMPTY = {}, {}

-- What a hovered frame runs (as itself): if it shows you or a group member,
-- bind every key to its button. The unit is read at OnEnter, in combat too.
ClickCast.KEYS_ATTR = "grf-hoverkeys"
ClickCast.HOVER_ATTR = "grf-hover"
local ENTER = [[
    if not self:GetAttribute("]] .. ClickCast.HOVER_ATTR .. [[") then return end
    local u = self:GetAttribute("unit")
    if type(u) ~= "string" or strmatch(u, "pet%d*$") then return end
    if u == "player" or strmatch(u, "^party%d+$") or strmatch(u, "^raid%d+$")
        or UnitPlayerOrPetInParty(u) or UnitPlayerOrPetInRaid(u) then
        control:RunFor(self, control:GetAttribute("]] .. ClickCast.KEYS_ATTR .. [["))
    end
]]
local LEAVE = "self:ClearBindings()"

-- Whether the rows reach other addons' and Blizzard's frames (#61), account-wide.
function ClickCast.Everywhere()
    return not (GRF.db and GRF.db.clickCastOthers == false)
end

-- A frame we may set attributes on: a live, unforbidden widget.
local function usable(f)
    if type(f) ~= "table" or type(f.SetAttribute) ~= "function" or type(f.GetAttribute) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(function() return f.IsForbidden and f:IsForbidden() end)
    return ok and not forbidden
end

-- Every frame the rows reach, and whether it binds the hover keys: our group
-- tiles, our pet tiles (mouse only), then Blizzard's and registered frames.
function ClickCast.Targets()
    local list, keys, seen = {}, {}, {}
    local function add(f, withKeys)
        if seen[f] or not usable(f) then return end
        seen[f] = true
        list[#list + 1] = f
        keys[f] = withKeys
    end
    local Header = GRF.Header
    for _, c in ipairs(Header and Header.children or {}) do add(c, true) end
    for _, c in ipairs(Header and Header.petChildren or {}) do add(c, false) end
    if ClickCast.Everywhere() then
        for _, name in ipairs(ClickCast.BLIZZARD) do add(rawget(_G, name), true) end
        for f, on in pairs(registry) do
            if on then add(f, true) end
        end
    end
    return list, keys
end

-- Give a frame the attribute set `want`, keeping its own values to put back.
local function carry(f, want)
    local had = applied[f] or EMPTY
    if had == want then return end
    local own = original[f] or {}
    original[f] = own
    for attr in pairs(had) do
        if want[attr] == nil then
            local v = own[attr]
            own[attr] = nil
            if v == NONE then v = nil end
            f:SetAttribute(attr, v)
        end
    end
    for attr, value in pairs(want) do
        if own[attr] == nil then
            local v = f:GetAttribute(attr)
            if v == nil then v = NONE end
            own[attr] = v
        end
        f:SetAttribute(attr, value)
    end
    applied[f] = want ~= EMPTY and want or nil
end
ClickCast.problems = {}
ClickCast.notes = {}     -- [row] = a non-blocking remark for the options
ClickCast.pending = false
ClickCast.onApplied = nil   -- set by the options page: repaint after each Apply

local function same(a, b)
    for k, v in pairs(a) do
        if type(v) == "table" then
            if type(b[k]) ~= "table" or not same(v, b[k]) then return false end
        elseif b[k] ~= v then return false end
    end
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
    if not same(attrs, installedAttrs) then installedAttrs = attrs end
    local frames, withKeys = ClickCast.Targets()
    local inSet = {}
    for _, f in ipairs(frames) do inSet[f] = true end

    -- Mouse rows: every frame carries the installed set (a frame registered
    -- since gets it now); a frame that left the set gets its own values back.
    -- One frame's failure (another addon's widget) never costs the rest.
    for f in pairs(applied) do
        if not inSet[f] then
            local ok, err = pcall(carry, f, EMPTY)
            if not ok then API.Fail("clickcast frame", err) end
        end
    end
    for _, f in ipairs(frames) do
        local ok, err = pcall(carry, f, installedAttrs)
        if not ok then API.Fail("clickcast frame", err) end
    end

    -- Hover keys: each frame that takes them is wrapped once and switched on
    -- by its grf-hover attribute (pets: off, keys aim at members); the key
    -- list lives in one header attribute the wraps read.
    if not keyHeader and next(withKeys) then
        keyHeader = CreateFrame("Frame", "GlassRaidFramesKeyHeader", UIParent, "SecureHandlerBaseTemplate")
        -- RunFor refuses a non-string body: with no key rows (a mouse-only
        -- profile) a hover must still find one (Codex P2 on #49).
        keyHeader:SetAttribute(ClickCast.KEYS_ATTR, "")
    end
    for f in pairs(hovering) do
        if not (inSet[f] and withKeys[f]) then
            pcall(f.SetAttribute, f, ClickCast.HOVER_ATTR, nil)
            pcall(ClearOverrideBindings, f)
            hovering[f] = nil
        end
    end
    for _, f in ipairs(frames) do
        if withKeys[f] and not hovering[f] then
            local ok, err = pcall(function()
                if not wrapped[f] then
                    SecureHandlerWrapScript(f, "OnEnter", keyHeader, ENTER)
                    SecureHandlerWrapScript(f, "OnLeave", keyHeader, LEAVE)
                    SecureHandlerWrapScript(f, "OnHide", keyHeader, LEAVE)
                    wrapped[f] = true
                end
                f:SetAttribute(ClickCast.HOVER_ATTR, true)
            end)
            if ok then hovering[f] = true else API.Fail("hover keys", err) end
        end
    end
    if keyHeader and not same(keys, installedKeys) then
        local lines = {}
        for key, text in pairs(keys) do
            local b = keyButton(key)
            b:SetAttribute("macrotext", type(text) == "string" and text or nil)
            b:SetAttribute("unit", type(text) == "table" and text.unit or nil)
            b:SetAttribute("type", type(text) == "table" and text.type or "macro")
            lines[#lines + 1] = string.format("self:SetBindingClick(true, %q, %q)", key, b:GetName())
        end
        table.sort(lines)
        keyHeader:SetAttribute(ClickCast.KEYS_ATTR, table.concat(lines, "\n"))
        -- A frame hovered right now still holds the old keys: drop them (the
        -- next OnEnter binds the new ones).
        for f in pairs(hovering) do pcall(ClearOverrideBindings, f) end
        installedKeys = keys
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
-- UPDATE_BINDINGS also fires on every hover (the tiles bind and clear their
-- keys), so it re-checks quietly: no "pending" banner, no repaint; Apply
-- changes nothing when nothing differs.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" then
        GRF.WhenOutOfCombat("clickcast", ClickCast.Apply, false)
    else
        if API.ResetClickCastCatalog then API.ResetClickCastCatalog() end
        ClickCast.Request()
    end
end)
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
            row.action, row.macrotext, row.name, row.icon = nil, nil, nil, nil
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
        if (not row.action or row.action == "spell" or row.action == "macro")
            and ok and type(mod) == "string" and mod ~= "NONE" and ClickCast.UsesModifier(row, mod) then
            out[#out + 1] = mod:lower() .. " is your Self Cast key: spell casts from this click may target you"
        end
        if row.mouse == "1" or row.mouse == "2" then
            out[#out + 1] = "replaces the plain " .. (row.mouse == "1" and "target" or "menu") .. " click"
        end
    end
    return out
end

ClickCast._test = { installed = function() return installedAttrs, installedKeys end, keyButtons = keyButtons,
                    registry = function() return registry end, ENTER = ENTER,
                    keyHeader = function() return keyHeader end, watcher = watcher }
