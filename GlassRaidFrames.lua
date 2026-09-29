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
    for _, role in ipairs(Role.ROLES) do
        if type(db.profiles[role]) ~= "table" then db.profiles[role] = {} end
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

--------------------------------------------------------------------------------
-- Role and profile (#7)
--------------------------------------------------------------------------------

-- The current role's settings (created by ensureDefaults).
function GRF.Profile()
    return GRF.db and GRF.role and GRF.db.profiles[GRF.role] or nil
end

-- Tell other addons where the grid is and for which role. GlassUnitFrames
-- listens (its #35) and makes room; neither addon depends on the other.
-- EventRegistry is usable on 70009 (probe item 9).
GRF.LAYOUT_EVENT = "GlassRaidFrames.LayoutChanged"
function GRF.Announce()
    if not GRF.role then return end
    local l, b, w, h = GRF.Header.Rect()
    if not l then return end   -- no grid (not built, or it failed): nothing to announce
    API.TriggerEvent(GRF.LAYOUT_EVENT, GRF.role, l, b, w, h)
end

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
end

-- Work out the role again (talents may have changed, or the manual pick);
-- re-apply only when it changed. Chat only for a real respec: talents
-- changing a role that talents gave before. Settling at login (class or
-- remembered role, then the first talent answer) stays quiet.
local function evaluateRole(quiet)
    local previousSource = GRF.roleSource
    local role, source = Role.Get(GRF.char.role, GRF.char.talentRole)
    if source == "talents" then GRF.char.talentRole = role end
    GRF.roleSource = source
    if role == GRF.role then return end
    local respec = source == "talents" and (previousSource == "talents" or previousSource == "remembered")
    GRF.role = role
    if respec and not quiet then say("role: " .. role:lower() .. " (talents)") end
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

-- "auto" or a role; false for anything else.
function Settings.SetRole(pick)
    pick = type(pick) == "string" and pick:upper() or ""
    if pick == "AUTO" then pick = "auto" end
    if pick ~= "auto" and not Role.VALID[pick] then return false end
    GRF.char.role = pick
    evaluateRole(true)
    return true
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

-- Pets for the current role (the pet row under the grid).
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
        say(key .. ": " .. err)
    end
    for _, line in ipairs(GRF.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say("no failures recorded") end
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
    elseif cmd == "solo" then
        Settings.SetShowSolo(not GRF.db.showSolo)
        say("show frames when solo: " .. (GRF.db.showSolo and "on" or "off"))
    elseif cmd == "blizzard" then
        Settings.SetHideBlizzard(not GRF.db.hideBlizzard)
        say(GRF.db.hideBlizzard and "Blizzard's party/raid frames: hidden"
            or "Blizzard's party/raid frames: shown after /reload")
    elseif cmd == "options" or cmd == "config" then
        if not (GRF.Options and GRF.Options.Open()) then say("Game Menu > Options > AddOns > Glass Raid Frames") end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GRF.MEASURED_ON_BUILD)
    else
        say("/grf options - the settings (Options > AddOns)")
        say("/grf role [auto|healer|caster|melee|tank] - settings follow your role; " .. roleLine())
        say("/grf unlock | lock - move the group frames for this role (out of combat)")
        say("/grf reset - this role's default position")
        say("/grf size <width> <height> | reset - this role's tile size")
        say("/grf solo - show your own frame when not in a group")
        say("/grf pets - show or hide pets (this role)")
        say("/grf blizzard - toggle hiding Blizzard's party/raid frames")
        say("/grf failures - what failed to build or register")
        say("/grf version - client build vs the measured one")
    end
end

SLASH_GLASSRAIDFRAMES1 = "/grf"
SlashCmdList.GLASSRAIDFRAMES = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GRF.db, GRF.char = ensureDefaults()
        evaluateRole(true)
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
        -- arg1 = isInitialLogin: warn at a real login, never on /reload.
        if arg1 and API.ClientBuild() ~= GRF.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " is newer than the one this addon was measured on ("
                .. GRF.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        GRF.Movers.OnCombat()   -- unlock mode ends: the grid can't move in combat
    elseif event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdown() then return end   -- trust the lockdown state, not the event
        runPending()
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })

GRF._test = { runPending = runPending, pending = function() return pending, order end }
