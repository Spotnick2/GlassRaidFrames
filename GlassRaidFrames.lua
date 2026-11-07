-- GlassRaidFrames.lua: bootstrap, saved settings, the role and its profile,
-- combat-deferred actions, and the /grf command.

local ADDON = ...
GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API, Role = GRF.API, GRF.Role
local say = API.Print

local DEFAULTS = { hideBlizzard = true, showSolo = false }

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
local function ensureDefaults()
    if type(GlassRaidFramesDB) ~= "table" then GlassRaidFramesDB = {} end
    local db = GlassRaidFramesDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    -- The group layout (#69) is on unless switched off; on isn't saved.
    if db.groupLayout ~= false then db.groupLayout = nil end
    -- The name display (#18): a style (the default, first, isn't saved) and
    -- nicknames by GUID, account-wide; junk dropped.
    if db.nameStyle == "first" or not GRF.Frames.NAME_STYLES[db.nameStyle] then db.nameStyle = nil end
    if type(db.nicknames) ~= "table" then db.nicknames = {} end
    for guid, n in pairs(db.nicknames) do
        if type(guid) ~= "string" or type(n) ~= "table" or type(n.nick) ~= "string" or n.nick == "" then
            db.nicknames[guid] = nil
        elseif type(n.name) ~= "string" then
            n.name = nil
        end
    end
    for _, role in ipairs(Role.ROLES) do
        if type(db.profiles[role]) ~= "table" then db.profiles[role] = {} end
        local prof = db.profiles[role]
        if not GRF.Layout.MODES[prof.layout] then prof.layout = nil end
        if type(prof.layoutPos) ~= "table" then prof.layoutPos = nil end
    end
    -- Per character: the manual role pick ("auto" = from talents, then class).
    if type(GlassRaidFramesCharDB) ~= "table" then GlassRaidFramesCharDB = {} end
    local char = GlassRaidFramesCharDB
    if char.role ~= "auto" and not Role.VALID[char.role] then char.role = "auto" end
    if not Role.VALID[char.talentRole] then char.talentRole = nil end
    return db, char
end

-- Anything that touches the secure frames waits for combat to end. The queue
-- is ordered (a repeated key keeps its slot, newest function wins) and the
-- build always runs first: every other action assumes the frames exist.
local pending, order = {}, {}

-- message: text to print when deferred; nil = a default; false = silent.
local function whenOutOfCombat(key, fn, message)
    if InCombatLockdown() then
        if not pending[key] then order[#order + 1] = key end
        pending[key] = fn
        if message ~= false then say(message or "will do that when combat ends") end
        return
    end
    fn()
end
GRF.WhenOutOfCombat = whenOutOfCombat   -- the addon's one combat queue

-- Each action runs on its own: one that throws is recorded and the rest of
-- the queue still runs.
local function runOne(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail("queued " .. key, err) end
end

local function runPending()
    local run, keys = pending, order
    pending, order = {}, {}
    if run.build then runOne("build", run.build) end
    for _, key in ipairs(keys) do
        if key ~= "build" then runOne(key, run[key]) end
    end
end

-- What this fight cost, said once after it: the protected calls the client
-- refused and blamed on us, and the failures recorded, since
-- PLAYER_REGEN_DISABLED (#78 F4). Quiet when nothing happened.
local fightBlocked, fightFailed = 0, 0
local function fightSummary()
    local blocked = GRF.blockedTotal - fightBlocked
    local failed = GRF.failureTotal - fightFailed - blocked   -- a block is recorded as a failure too
    if blocked <= 0 and failed <= 0 then return end
    local parts = {}
    if blocked > 0 then parts[#parts + 1] = blocked .. " protected action" .. (blocked > 1 and "s" or "") .. " refused" end
    if failed > 0 then parts[#parts + 1] = failed .. " failure" .. (failed > 1 and "s" or "") end
    say("this fight: " .. table.concat(parts, ", ") .. " (/grf failures)")
end

-- The lockdown normally ends with PLAYER_REGEN_ENABLED. Should it outlive the
-- event (unmeasured; FOREVER-PROBE item 18.1), one retry re-checks until it
-- is off, never two at once (#78 F3).
local draining = false
local function drain()
    if InCombatLockdown() then
        if draining then return end
        draining = true
        C_Timer.After(0.1, function() draining = false; drain() end)
        return
    end
    runPending()
    fightSummary()
end

--------------------------------------------------------------------------------
-- Role and profile (#7)
--------------------------------------------------------------------------------

-- The current role's settings (created by ensureDefaults).
function GRF.Profile()
    return GRF.db and GRF.role and GRF.db.profiles[GRF.role] or nil
end

-- Where the group frames are, for other addons (GlassUnitFrames places its
-- player and target beside them; neither addon needs the other): a fresh
-- { role, l, b, w, h, top, base, mode } in UIParent units from its
-- bottom-left, or nil before the build. l, b, w, h is the grid with its pets;
-- top is the grid's own top, base the baseline. Mode "hud" or "side" (the
-- group layout, #69), or "legacy" with top = b + h and base = b.
function GRF.LayoutState()
    if GRF.layoutOn then return GRF.Layout.State() end
    local l, b, w, h = GRF.Header.Rect()
    if not (l and GRF.role) then return nil end
    return { role = GRF.role, l = l, b = b, w = w, h = h, top = b + h, base = b, mode = "legacy" }
end

-- The same, as an event (role, l, b, w, h, top, base, mode): never in combat,
-- where nothing of ours moves; once after it instead.
-- EventRegistry is usable on 70009 (probe item 9).
GRF.LAYOUT_EVENT = "GlassRaidFrames.LayoutChanged"
function GRF.Announce()
    if InCombatLockdown() then
        GRF.WhenOutOfCombat("announce", GRF.Announce, false)
        return
    end
    local s = GRF.LayoutState()
    if not s then return end   -- no grid (not built, or it failed): nothing to announce
    API.TriggerEvent(GRF.LAYOUT_EVENT, s.role, s.l, s.b, s.w, s.h, s.top, s.base, s.mode)
end

local reportSuite   -- below: Glass UI's page shows the layout's mode too

-- Move the grid to the current role's position and say so. Out of combat.
local function applyRole()
    -- The bindings follow the role too (they're per role).
    if GRF.ClickCast then GRF.ClickCast.Request() end
    if not GRF.Header.container then return end
    GRF.Header.ApplySize()   -- the size is per role too
    GRF.Header.ApplyPets()   -- and showing pets
    GRF.Header.SetPosition(GRF.Header.PositionOf())
    -- Unlocked: the movers follow the role (the pet mover appears or goes).
    if GRF.Movers.IsUnlocked() then GRF.Movers.Unlock() end
    GRF.Announce()
    reportSuite()   -- the layout's mode is per role
end

-- How many click-cast rows a role has, without creating its profile.
local function bindingCount(role)
    local prof = GRF.char and type(GRF.char.profiles) == "table" and GRF.char.profiles[role]
    local rows = type(prof) == "table" and prof.bindings
    return type(rows) == "table" and #rows or 0
end

-- A role that changed by itself (#84): bindings are per role, so landing on a
-- role with none looks like they were lost. When the role we left has some,
-- say so and offer to copy them (the notice; `/grf clickcast copy <role>`).
-- Returns true when it spoke.
local function offerCopy(from, to)
    local count = bindingCount(from)
    if count == 0 or bindingCount(to) > 0 then return false end
    say("role: " .. to:lower() .. " (was " .. from:lower() .. "), which has no click-cast bindings; "
        .. from:lower() .. " has " .. count .. ". /grf clickcast copy " .. from:lower() .. " copies them.")
    if GRF.ClickCastOptions and GRF.ClickCastOptions.OfferCopy then
        local ok, err = pcall(GRF.ClickCastOptions.OfferCopy, from, to, count)
        if not ok then API.Fail("role notice", err) end
    end
    return true
end

-- Work out the role again (talents may have changed, or the manual pick);
-- re-apply only when it changed. Chat only for a real respec: talents
-- changing a role that talents gave before, or any change that isn't a
-- manual pick and lands on an empty binding list (offerCopy). Settling at
-- login (class or remembered role, then the first talent answer) stays quiet
-- otherwise.
local function evaluateRole(quiet)
    local previousSource, previous = GRF.roleSource, GRF.role
    local role, source = Role.Get(GRF.char.role, GRF.char.talentRole)
    if source == "talents" then GRF.char.talentRole = role end
    GRF.roleSource = source
    if role == previous then return end
    local respec = source == "talents" and (previousSource == "talents" or previousSource == "remembered")
    GRF.role = role
    local offered = previous and source ~= "manual" and offerCopy(previous, role)
    if respec and not quiet and not offered then say("role: " .. role:lower() .. " (talents)") end
    -- The bindings are per role: request them now, so a change in combat
    -- shows as pending while the old role's stay installed.
    if GRF.ClickCast then GRF.ClickCast.Request() end
    whenOutOfCombat("role", applyRole, false)
end

--------------------------------------------------------------------------------
-- Settings: the apply-and-save helpers shared by /grf and the options panel.
--------------------------------------------------------------------------------

local Settings = {}
GRF.Settings = Settings

-- Glass UI's suite (#67): its Suite table when it speaks API 1 (set at
-- ADDON_LOADED), and LibGlass's MINOR at the build attempt.
local suite, suiteMinor

-- What this session built, for Glass UI's page: plain values only, under
-- pcall. Sent after the instance is built, and again whenever the click-cast
-- setting changes (`others` is the setting, not proof of coverage).
function reportSuite()
    if not suite then return end
    pcall(suite.Report, ADDON, {
        api = 1, built = GRF.following, reason = GRF.suiteFailure, minor = suiteMinor,
        options = function() return GRF.Options and GRF.Options.Open() end,
        clickCast = { open = function() GRF.ClickCastOptions.Open() end, others = GRF.ClickCast.Everywhere() },
        -- What this session applied (#69): the layout, and its mode for the role.
        layout = { on = GRF.layoutOn == true, mode = GRF.layoutOn and GRF.Layout.ModeOf(GRF.role) or "legacy" },
    })
end

-- Opens Glass UI's settings, when its Suite offers that (an optional
-- `Suite.Open`, still API 1): a function for the Look section's button, or nil.
function GRF.GlassUIOpener()
    if suite and type(rawget(suite, "Open")) == "function" then
        return function() pcall(suite.Open) end
    end
end

-- "auto" or a role; false for anything else.
function Settings.SetRole(pick)
    pick = type(pick) == "string" and pick:upper() or ""
    if pick == "AUTO" then pick = "auto" end
    if pick ~= "auto" and not Role.VALID[pick] then return false end
    GRF.char.role = pick
    evaluateRole(true)
    return true
end

-- Copy role `from`'s click-cast rows into `to` (default: the current role),
-- once: only into an empty list, and the two stay separate afterwards (#84).
-- Returns the number copied, or false and why.
function Settings.CopyBindings(from, to)
    from = type(from) == "string" and from:upper() or ""
    to = to or GRF.role
    if not (Role.VALID[from] and Role.VALID[to]) or from == to then
        return false, "copy from: healer, caster, melee or tank (not " .. tostring(to):lower() .. ")"
    end
    if bindingCount(from) == 0 then return false, from:lower() .. " has no click-cast bindings" end
    if bindingCount(to) > 0 then
        return false, to:lower() .. " already has click-cast bindings (/grf clickcast edits them)"
    end
    local rows, copy = GRF.ClickCast.Rows(to), GRF.ClickCastEditor.Copy
    for _, row in ipairs(GRF.ClickCast.Rows(from)) do rows[#rows + 1] = copy(row) end
    GRF.ClickCast.Request()
    return #rows
end

-- The group layout (#69), account-wide: on (the default, not saved) or the
-- legacy grid. Takes effect after /reload: the frames are built once.
function Settings.SetGroupLayout(on)
    if on == false then GRF.db.groupLayout = false else GRF.db.groupLayout = nil end
    return true
end

-- The current role's layout: "hud" (centred above the action bars) or "side".
-- The role's default isn't saved.
function Settings.SetLayoutMode(mode)
    local prof = GRF.Profile()
    if not (prof and GRF.Layout.MODES[mode]) then return false end
    prof.layout = mode ~= GRF.Layout.DefaultMode(GRF.role) and mode or nil
    if GRF.layoutOn then
        whenOutOfCombat("layout", function()
            if GRF.Header.ApplySize() then
                if GRF.Movers.IsUnlocked() then GRF.Movers.Unlock() end   -- the mover follows
                GRF.Announce()
            end
        end, false)
    end
    reportSuite()
    return true
end

-- The tier preview (#69): 10, 20 or 40 mock members in place of the grid,
-- announced so GlassUnitFrames follows; nil ends it. Out of combat.
function Settings.Preview(n)
    if not (GRF.layoutOn and GRF.Header.container) then return false, "the group layout is off" end
    if n == nil then return GRF.Layout.EndPreview() end
    if InCombatLockdown() then return false, "not in combat" end
    if not GRF.Layout.PREVIEWS[n] then return false, "a preview of 10, 20 or 40" end
    return GRF.Layout.Preview(n)
end

function Settings.SetShowSolo(on)
    GRF.db.showSolo = on == true
    whenOutOfCombat("solo", function() GRF.Header.SetShowSolo(GRF.db.showSolo) end)
end

function Settings.SetHideBlizzard(on)
    GRF.db.hideBlizzard = on == true
    -- Re-check when it runs: toggled back off in combat, nothing hides.
    if on then whenOutOfCombat("blizzard", function() if GRF.db.hideBlizzard then GRF.Blizzard.HideAll() end end) end
end

-- Click-casting on other addons' and Blizzard's unit frames (#61): on by
-- default (not saved); off puts their own click actions back.
function Settings.SetClickCastOthers(on)
    if on == false then GRF.db.clickCastOthers = false else GRF.db.clickCastOthers = nil end
    GRF.ClickCast.Request()
    reportSuite()   -- Glass UI's page shows this setting (#67)
end

-- The current role's hover keys anywhere under the cursor, or only on a
-- hovered frame (#63). The role's default isn't saved.
function Settings.SetKeysAnywhere(on)
    local prof = GRF.Profile()
    if not prof then return false end
    on = on == true
    if on == GRF.ClickCast.AnywhereDefault(GRF.role) then prof.keysAnywhere = nil else prof.keysAnywhere = on end
    GRF.ClickCast.Request()
    return true
end

-- The glass look (#37) and body (#38): saved now, built after /reload
-- (LibGlass builds them into each surface). The defaults aren't saved.
-- While following Glass UI (#67) they're set there: both refuse and write
-- nothing.
function Settings.SetLook(look)
    if GRF.following or not GRF.LOOKS[look] then return false end
    GRF.db.look = look ~= GRF.DEFAULT_LOOK and look or nil
    return true
end

function Settings.SetBody(body)
    if GRF.following or not GRF.BODIES[body] then return false end
    GRF.db.glassBody = body == "smoked" and "smoked" or nil
    return true
end

-- The name display (#18), account-wide. Plain Lua and a repaint: fine in combat.
function Settings.SetNameStyle(style)
    if not GRF.Frames.NAME_STYLES[style] then return false end
    GRF.db.nameStyle = style ~= "first" and style or nil
    GRF.Engine.RepaintChannel("name")
    return true
end

Settings.NICK_MAX = 24   -- bytes; a tile shows far less

-- A nickname for the person with this plain GUID; "" or nil removes it.
-- `name` (their full name, for the options list) is kept when unknown.
-- Returns true, or false and why.
function Settings.SetNickname(guid, nick, name)
    if type(guid) ~= "string" or API.IsSecret(guid) then return false, "no player to nickname" end
    nick = type(nick) == "string" and nick:gsub("|", ""):match("^%s*(.-)%s*$") or ""
    if #nick > Settings.NICK_MAX then return false, "a nickname is at most " .. Settings.NICK_MAX .. " letters" end
    if nick == "" then
        GRF.db.nicknames[guid] = nil
    else
        local old = GRF.db.nicknames[guid]
        if type(name) ~= "string" or API.IsSecret(name) then name = old and old.name end
        GRF.db.nicknames[guid] = { nick = nick, name = name }
    end
    GRF.Engine.RepaintChannel("name")
    return true
end

-- The same, for your current target (a player).
function Settings.SetTargetNickname(nick)
    local okP, isPlayer = pcall(UnitIsPlayer, "target")
    if not (okP and not API.IsSecret(isPlayer) and isPlayer) then return false, "target a player first" end
    local okG, guid = pcall(UnitGUID, "target")
    if not okG or API.IsSecret(guid) or type(guid) ~= "string" then return false, "can't tell who your target is right now" end
    -- The name is never truth-tested here: a secret one throws on `and`/`or`
    -- (#78 F1). SetNickname keeps the old list name when it's secret or nil;
    -- the first return only (a secret name comes back in two).
    local name = GRF.Frames.FullName("target")
    return Settings.SetNickname(guid, nick, name)
end

-- Every nickname, by name: { guid, name, nick }.
function Settings.Nicknames()
    local list = {}
    for guid, n in pairs(GRF.db.nicknames) do list[#list + 1] = { guid = guid, name = n.name or "?", nick = n.nick } end
    table.sort(list, function(a, b) return a.name < b.name or (a.name == b.name and a.guid < b.guid) end)
    return list
end

-- The current role's tile size; nil for either = back to the default.
-- Save a role's tile size NOW (the role asking, never whichever is current
-- later: Codex review); nil for both = back to the default.
function Settings.SaveSize(role, w, h)
    local prof = GRF.db and role and GRF.db.profiles[role]
    if not prof then return false end
    if w == nil and h == nil then
        prof.size = nil
    else
        local s = type(prof.size) == "table" and prof.size or {}
        prof.size = { w = w or s.w or GRF.Header.DEFAULT_W, h = h or s.h or GRF.Header.DEFAULT_H }
    end
    return true
end

-- Resize the grid to the CURRENT role's saved size. Only layout: it writes
-- nothing, so a late one (a debounced slider, a queued combat change) can't
-- overwrite a newer save or another role's.
function Settings.ApplySize()
    -- Silent when deferred: a slider dragged in combat would print on every tick.
    whenOutOfCombat("size", function()
        if GRF.Header.ApplySize() then
            -- A saved spot keeps its centre (the container is centre-anchored),
            -- but a role still on its default is placed FROM the grid's size
            -- (the side default hugs the screen's left edge): re-place it.
            local prof = GRF.Profile()
            if not (prof and prof.pos) then GRF.Header.SetPosition(GRF.Header.PositionOf()) end
            if GRF.Movers.IsUnlocked() then GRF.Movers.Unlock() end   -- the mover follows the new size
            GRF.Announce()
        end
    end, false)
end

-- The current role's tile size: saved at once, applied out of combat.
function Settings.SetSize(w, h)
    if not Settings.SaveSize(GRF.role, w, h) then return false end
    Settings.ApplySize()
    return true
end

-- Pets for the current role (their own column beside the grid).
function Settings.SetShowPets(on)
    local prof = GRF.Profile()
    if not prof then return false end
    prof.showPets = on == true or nil
    whenOutOfCombat("pets", function()
        GRF.Header.ApplyPets()
        if GRF.Movers.IsUnlocked() then GRF.Movers.Unlock() end   -- the pet mover follows
        GRF.Announce()   -- the rectangle grew or shrank (applyRole announces its own, once placed)
    end)
    return true
end

-- Indicators (#19): account-wide, per class. `which` is a list number or a key.
function Settings.FindIndicator(which)
    local list = GRF.Indicators.Setup() or {}
    local n = tonumber(which)
    if n then return list[n], n end
    which = type(which) == "string" and which:lower() or which
    for i, ind in ipairs(list) do
        if ind.key:lower() == which then return ind, i end
    end
    return nil
end

function Settings.SetIndicatorEnabled(which, on)
    local ind = Settings.FindIndicator(which)
    if not ind then return false end
    ind.enabled = on == true
    GRF.Indicators.Request()
    return true
end

function Settings.ResetIndicators() return GRF.Indicators.Reset() end

-- The Indicators page's edits: each saves at once and applies out of combat.
-- noApply: save only (a slider mid-drag; the caller applies once it pauses).
function Settings.EditIndicator(ind, field, value, noApply)
    ind[field] = value
    if not noApply then GRF.Indicators.Request() end
end

-- A new indicator (icons, my buffs, no spells yet); nil at the cap.
function Settings.AddIndicator()
    local Ind = GRF.Indicators
    local list = Ind.Setup()
    if not list or #list >= Ind.MAX_INDICATORS then return nil end
    local n = 1
    while Settings.FindIndicator("custom" .. n) do n = n + 1 end
    local ind = { key = "custom" .. n, name = "New indicator", kind = "icons", aura = "HELPFUL", mine = true,
                  enabled = true, anchor = "TOP", x = 0, y = -3, size = 12, grow = "RIGHT", swipe = true,
                  timer = false, color = { 1, 0.2, 0.2 }, spells = {} }
    list[#list + 1] = ind
    Ind.Request()
    return ind
end

-- The built-in debuff row can't be removed.
function Settings.RemoveIndicator(ind)
    local list = GRF.Indicators.Setup() or {}
    if ind.builtin then return false end
    for i, other in ipairs(list) do
        if other == ind then
            table.remove(list, i)
            GRF.Indicators.Request()
            return true
        end
    end
    return false
end

local function move(t, i, delta)
    local j = i + delta
    if not (t[i] and t[j]) then return false end
    t[i], t[j] = t[j], t[i]
    return true
end

function Settings.MoveIndicator(ind, delta)
    local _, i = Settings.FindIndicator(ind.key)
    return i ~= nil and move(GRF.Indicators.Setup(), i, delta)   -- list order only: nothing to apply
end

-- A spell by ID: refused when unknown to the client, already listed, or at the cap.
function Settings.AddIndicatorSpell(ind, id)
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or not API.SpellName(id) then return false, "unknown spell" end
    -- Any rank of a listed spell is that spell (both would match the same aura).
    local Ind = GRF.Indicators
    for _, other in ipairs(ind.spells) do
        if other == id then return false, "already listed" end
        for _, r in ipairs(Ind.Family(other)) do
            if r == id then return false, "already listed (another rank)" end
        end
        for _, r in ipairs(Ind.Family(id)) do
            if r == other then return false, "already listed (another rank)" end
        end
    end
    if #ind.spells >= GRF.Indicators.MAX_SPELLS then return false, "list full" end
    ind.spells[#ind.spells + 1] = Ind.Family(id)[1]   -- stored by its family's first rank when known
    GRF.Indicators.Request()
    return true
end

function Settings.RemoveIndicatorSpell(ind, i)
    if not table.remove(ind.spells, i) then return false end
    GRF.Indicators.Request()
    return true
end

function Settings.MoveIndicatorSpell(ind, i, delta)
    if not move(ind.spells, i, delta) then return false end
    GRF.Indicators.Request()
    return true
end

function Settings.Unlock() return GRF.Movers.Unlock() end
-- The reset belongs to the role it was asked for: queued in combat, it must
-- not land on whatever role is current when combat ends (Codex review).
-- One queue slot per role, so resets for two roles don't merge.
function Settings.ResetPosition()
    local role = GRF.role
    whenOutOfCombat("reset:" .. tostring(role), function() GRF.Movers.Reset(role) end)
end

--------------------------------------------------------------------------------
-- /grf
--------------------------------------------------------------------------------

local function failures()
    local any = false
    for key, err in pairs(GRF.paintFailures) do
        any = true
        local d = GRF.failureDetail[key]
        say(key .. (d and d.count > 1 and (" (x" .. d.count .. ")") or "") .. ": " .. err)
    end
    for _, line in ipairs(GRF.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say("no failures recorded") end
end

local KIND_NAMES = { icons = "icons", icon = "one icon", square = "square", debuffs = "debuff row" }

local function indicatorLine(i, ind)
    local Ind = GRF.Indicators
    local what
    if ind.kind == "debuffs" then
        what = (ind.filter == "dispellable" and "debuffs you can dispel" or "every debuff") .. ", up to " .. ind.max
    else
        local names = {}
        for _, id in ipairs(ind.spells) do names[#names + 1] = API.SpellName(id) or ("#" .. id) end
        what = (ind.mine and "mine: " or "anyone's: ") .. (#names > 0 and table.concat(names, ", ") or "no spells")
    end
    local ok, why = Ind.Supported(ind)
    local state = not ind.enabled and "|cff808080off|r" or (ok and "|cff60ff60on|r" or ("|cffff6060" .. why .. "|r"))
    return string.format("%d. %s (%s, %s): %s [%s]", i, ind.name, KIND_NAMES[ind.kind] or ind.kind,
        ind.anchor:lower(), what, state)
end

local function indicatorsCommand(rest)
    local which, onoff = rest:match("^(%S+)%s+(%S+)$")
    onoff = onoff and onoff:lower()
    if rest:lower() == "reset" then
        Settings.ResetIndicators()
        say("indicators back to your class defaults")
    elseif which and (onoff == "on" or onoff == "off") then
        if not Settings.SetIndicatorEnabled(which, onoff == "on") then say("no indicator " .. which) end
    elseif rest ~= "" then
        say("usage: /grf ind | /grf ind <number> on|off | /grf ind reset")
        return
    end
    say("indicators (all your characters of this class):")
    for i, ind in ipairs(GRF.Indicators.Setup() or {}) do say(indicatorLine(i, ind)) end
    if InCombatLockdown() then say("changes show when combat ends") end
end

-- /grf nick: list; <nickname> for your target; clear (your target's);
-- remove <n> (from the list).
local function nickCommand(rest)
    local lower = rest:lower()
    local n = lower:match("^remove%s+(%d+)$")
    if lower == "" then
        local list = Settings.Nicknames()
        if #list == 0 then say("no nicknames (/grf nick <nickname> sets one for your target)") end
        for i, e in ipairs(list) do say(i .. ". " .. e.name .. " -> " .. e.nick) end
        return
    elseif n then
        local e = Settings.Nicknames()[tonumber(n)]
        if not e then say("no nickname " .. n .. " (/grf nick lists them)") return end
        Settings.SetNickname(e.guid, nil)
        say("nickname removed: " .. e.name)
        return
    end
    local ok, why = Settings.SetTargetNickname(lower == "clear" and "" or rest)
    if not ok then say(why) return end
    say(lower == "clear" and "nickname cleared for your target" or ("your target is now shown as " .. (rest:gsub("|", ""))))
end

local function layoutLine()
    local saved = GRF.db.groupLayout ~= false
    local line = "group layout: " .. (GRF.layoutOn and "on" or "off (the eight-group grid)")
    if saved ~= GRF.layoutOn then line = line .. ", " .. (saved and "on" or "off") .. " after /reload" end
    if GRF.layoutOn then
        line = line .. "; " .. tostring(GRF.role):lower() .. ": "
            .. (GRF.Layout.ModeOf(GRF.role) == "hud" and "centred above the action bars" or "at the side")
    end
    return line
end

local function roleLine()
    local pick = GRF.char.role
    return "role: " .. tostring(GRF.role):lower() .. " (" .. tostring(GRF.roleSource)
        .. (pick == "auto" and "" or ", picked by hand") .. ")"
end

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "unlock" then
        Settings.Unlock()
    elseif cmd == "lock" then
        GRF.Movers.Lock()
    elseif cmd == "reset" then
        Settings.ResetPosition()
    elseif cmd == "role" then
        if arg ~= "" and not Settings.SetRole(arg) then say("roles: auto, healer, caster, melee, tank") end
        say(roleLine())
    elseif cmd == "size" then
        local rest = (msg or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        local w, h = rest:match("^(%d+)%s+(%d+)$")
        if not w then w = rest:match("^(%d+)$") end
        if rest:lower() == "reset" then
            Settings.SetSize(nil, nil)
        elseif w then
            Settings.SetSize(tonumber(w), tonumber(h))   -- one number: the width only
        elseif rest ~= "" then
            say("usage: /grf size <width> [<height>] | reset")
        end
        if InCombatLockdown() and rest ~= "" then say("the frames resize when combat ends") end
        local tw, th = GRF.Header.TileSize()
        say("tile size for " .. tostring(GRF.role):lower() .. ": " .. tw .. " x " .. th
            .. "  (/grf size <width> <height>, /grf size reset)")
    elseif cmd == "pets" then
        Settings.SetShowPets(not (GRF.Profile() and GRF.Profile().showPets))
        say("pets for " .. tostring(GRF.role):lower() .. ": " .. ((GRF.Profile() and GRF.Profile().showPets) and "shown" or "hidden"))
    elseif cmd == "layout" then
        if arg == "on" or arg == "off" then
            Settings.SetGroupLayout(arg == "on")
        elseif arg == "hud" or arg == "side" then
            if not GRF.layoutOn then say("the group layout is off (/grf layout on, then /reload)") end
            Settings.SetLayoutMode(arg)
        elseif arg ~= "" then
            say("usage: /grf layout on|off|hud|side")
        end
        say(layoutLine())
    elseif cmd == "preview" then
        local ok, why = Settings.Preview(tonumber(arg))
        if arg == "off" or arg == "" then
            say("preview ended")
        elseif ok then
            say("preview: a raid of " .. arg .. " (/grf preview off, combat or a roster change ends it)")
        else
            say("preview: " .. tostring(why or "usage: /grf preview 10|20|40|off"))
        end
    elseif cmd == "solo" then
        Settings.SetShowSolo(not GRF.db.showSolo)
        say("show frames when solo: " .. (GRF.db.showSolo and "on" or "off"))
    elseif cmd == "blizzard" then
        Settings.SetHideBlizzard(not GRF.db.hideBlizzard)
        say(GRF.db.hideBlizzard and "Blizzard's party/raid frames: hidden"
            or "Blizzard's party/raid frames: shown after /reload")
    elseif cmd == "names" then
        if not Settings.SetNameStyle(arg) then say("names first|initial|full") end
        say("names: " .. (GRF.db.nameStyle or "first"))
    elseif cmd == "nick" then
        nickCommand((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
    elseif GRF.following and (cmd == "look" or cmd == "body") then
        say(GRF.SuiteStatus())   -- set in Glass UI (#67)
    elseif cmd == "look" then
        if Settings.SetLook(arg) then
            say("look " .. arg .. ": takes effect after /reload")
        else
            local failed = GRF.SuiteStatus()
            say("look pearl|clean|classic (now " .. GRF.look .. (failed and "; " .. failed or "") .. ")")
        end
    elseif cmd == "body" then
        if Settings.SetBody(arg) then
            say("glass body " .. arg .. ": takes effect after /reload")
        else
            say("body clear|smoked (now " .. GRF.body .. ")")
        end
    elseif cmd == "options" or cmd == "config" then
        if not (GRF.Options and GRF.Options.Open()) then say("Game Menu > Options > AddOns > Glass Raid Frames") end
    elseif cmd == "clickcast" and (arg == "all" or arg == "ours") then
        Settings.SetClickCastOthers(arg == "all")
        say(arg == "all" and "click-casting: every unit frame" or "click-casting: Glass Raid Frames' tiles only")
    elseif cmd == "clickcast" and arg == "copy" then
        local from = (msg or ""):lower():match("^%s*%S+%s+%S+%s+(%S+)")
        local n, why = Settings.CopyBindings(from)
        if n then
            say("copied " .. n .. " click-cast bindings from " .. from .. " to " .. tostring(GRF.role):lower())
        else
            say(why .. "  (/grf clickcast copy <role>)")
        end
    elseif cmd == "clickcast" then
        GRF.ClickCastOptions.Toggle()
    elseif cmd == "keys" then
        if arg == "anywhere" or arg == "frames" then Settings.SetKeysAnywhere(arg == "anywhere") end
        say("hover keys for " .. tostring(GRF.role):lower() .. ": "
            .. (GRF.ClickCast.Anywhere() and "anywhere under the cursor" or "on frames only")
            .. "  (/grf keys frames|anywhere)")
    elseif cmd == "ind" or cmd == "indicators" then
        indicatorsCommand((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GRF.MEASURED_ON_BUILD)
    else
        say("/grf options - the settings (Options > AddOns)")
        say("/grf clickcast - the click-casting editor; /grf clickcast all|ours - on every unit frame, or our tiles only; /grf clickcast copy <role> - that role's bindings into an empty list")
        say("/grf keys frames|anywhere - this role's hover keys: on frames only, or the world too")
        say("/grf role [auto|healer|caster|melee|tank] - settings follow your role; " .. roleLine())
        say("/grf unlock | lock - move the group frames for this role (out of combat)")
        say("/grf reset - this role's default position")
        say("/grf size <width> <height> | reset - this role's tile size")
        say("/grf layout on|off - one grid sized by the group (after /reload); hud|side - this role's place")
        say("/grf preview 10|20|40|off - how a raid of that size would sit")
        say("/grf solo - show your own frame when not in a group")
        say("/grf pets - show or hide pets (this role)")
        say("/grf ind - buff and debuff indicators (per class); /grf ind <n> on|off, /grf ind reset")
        say("/grf names first|initial|full - how names show (all your characters)")
        say("/grf nick <nickname> | clear - your target's nickname; /grf nick lists, /grf nick remove <n>")
        if GRF.following then
            say("/grf look, /grf body - " .. GRF.SuiteStatus())
        else
            say("/grf look pearl|clean|classic - the glass (after /reload); now " .. GRF.look)
            say("/grf body clear|smoked - the glass body (after /reload); now " .. GRF.body)
        end
        say("/grf blizzard - toggle hiding Blizzard's party/raid frames")
        say("/grf failures - what failed to build or register")
        say("/grf version - client build vs the measured one")
    end
end

SLASH_GLASSRAIDFRAMES1 = "/grf"
SlashCmdList.GLASSRAIDFRAMES = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GRF.db, GRF.char = ensureDefaults()
        -- Which frames to build, decided once (#69): the group layout, or
        -- the legacy grid. Before anything is built.
        GRF.layoutOn = GRF.db.groupLayout ~= false
        if GRF.layoutOn then GRF.Layout.Install() end
        -- The look first: every surface belongs to its instance (#37, #38).
        -- Glass UI's suite theme when following it (#67), else our own.
        suite, suiteMinor = GRF.UseSuite(ADDON)
        if not GRF.following then GRF.UseLook(GRF.db.look, GRF.db.glassBody) end
        if GRF.lookFallback then say("look: " .. GRF.PEARL_FALLBACK) end
        evaluateRole(true)
        -- After the role: the layout's mode is the role's (Codex P2 on #72).
        -- Later role changes report from applyRole, after the build.
        reportSuite()
        -- A position saved before roles existed: every role without one gets
        -- it (the talents aren't read yet, so which role is yours isn't known).
        if type(GRF.db.pos) == "table" then
            for _, role in ipairs(Role.ROLES) do
                local prof = GRF.db.profiles[role]
                if prof.pos == nil then prof.pos = { x = GRF.db.pos.x, y = GRF.db.pos.y } end
            end
            GRF.db.pos = nil
        end
        -- Secure frames can't be built under lockdown. Loading normally runs
        -- before it applies, but don't bet the whole addon on that.
        whenOutOfCombat("build", function()
            -- Hiding Blizzard's frames must not depend on our build succeeding.
            local ok, err = pcall(GRF.Header.Build, GRF.Frames.Setup)
            if not ok then API.Fail("build", err) end
            if GRF.db.hideBlizzard then GRF.Blizzard.HideAll() end
            local okC, errC = pcall(GRF.ClickCast.Apply)
            if not okC then API.Fail("clickcast", errC) end
            GRF.Announce()
        end, "frames will appear when combat ends")
        -- Talents arrive after load (PLAYER_TALENT_UPDATE at login, measured).
        GRF.roleWatcher = Role.Watch(function() evaluateRole(false) end, API.RegisterEvents)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn at a real login, never on /reload. Dev
        -- copies only: re-measuring the client is a chore a player can't do.
        if arg1 and API.IsDevBuild() and API.ClientBuild() ~= GRF.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " is newer than the one this addon was measured on ("
                .. GRF.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The lockdown is already on here (Retail's order; FOREVER-PROBE item
        -- 18.1 measures it on Forever): plain Lua and insecure frames only.
        fightBlocked, fightFailed = GRF.blockedTotal, GRF.failureTotal
        GRF.Movers.OnCombat()   -- unlock mode ends: the grid can't move in combat
    elseif event == "PLAYER_REGEN_ENABLED" then
        drain()   -- trusts the lockdown state, not the event
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- The client refused a protected call and blamed us (arg1 the addon,
        -- arg2 the function). No pcall sees these: recorded for /grf failures
        -- and the post-fight line (#78 F4).
        if arg1 == ADDON then
            local fn = tostring(arg2)
            GRF.blocked[fn] = (GRF.blocked[fn] or 0) + 1
            GRF.blockedTotal = GRF.blockedTotal + 1
            API.Fail((event == "ADDON_ACTION_FORBIDDEN" and "forbidden " or "blocked ") .. fn,
                InCombatLockdown() and "refused by the client in combat" or "refused by the client")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                           "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" })

GRF._test = { runPending = runPending, pending = function() return pending, order end }
