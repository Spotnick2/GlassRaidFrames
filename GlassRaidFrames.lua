-- GlassRaidFrames.lua: bootstrap, saved settings, combat-deferred actions and
-- the /grf command.

local ADDON = ...
GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
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
    return db
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

local function runPending()
    local run, keys = pending, order
    pending, order = {}, {}
    if run.build then run.build() end
    for _, key in ipairs(keys) do
        if key ~= "build" then run[key]() end
    end
end

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

local function slash(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "unlock" then
        GRF.Movers.Unlock()
    elseif cmd == "lock" then
        GRF.Movers.Lock()
    elseif cmd == "reset" then
        whenOutOfCombat("reset", function() GRF.Movers.Reset() end)
    elseif cmd == "solo" then
        GRF.db.showSolo = not GRF.db.showSolo
        whenOutOfCombat("solo", function() GRF.Header.SetShowSolo(GRF.db.showSolo) end)
        say("show frames when solo: " .. (GRF.db.showSolo and "on" or "off"))
    elseif cmd == "blizzard" then
        GRF.db.hideBlizzard = not GRF.db.hideBlizzard
        if GRF.db.hideBlizzard then
            whenOutOfCombat("blizzard", GRF.Blizzard.HideAll)
            say("Blizzard's party/raid frames: hidden")
        else
            say("Blizzard's party/raid frames: shown after /reload")
        end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GRF.MEASURED_ON_BUILD)
    else
        say("/grf unlock | lock - move the group frames (out of combat)")
        say("/grf reset - back to the default position")
        say("/grf solo - show your own frame when not in a group")
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
        GRF.db = ensureDefaults()
        -- Secure frames can't be built under lockdown. Loading normally runs
        -- before it applies, but don't bet the whole addon on that.
        whenOutOfCombat("build", function()
            GRF.Header.Build(GRF.Frames.Setup)
            if GRF.db.hideBlizzard then GRF.Blizzard.HideAll() end
        end, "frames will appear when combat ends")
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
