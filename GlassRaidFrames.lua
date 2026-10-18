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

-- Click-casting on other addons' and Blizzard's unit frames (#61): on by
-- default (not saved); off puts their own click actions back.
function Settings.SetClickCastOthers(on)
    if on == false then GRF.db.clickCastOthers = false else GRF.db.clickCastOthers = nil end
    GRF.ClickCast.Request()
end

-- The glass look (#37) and body (#38): saved now, built after /reload
-- (LibGlass builds them into each surface). The defaults aren't saved.
function Settings.SetLook(look)
    if not GRF.LOOKS[look] then return false end
    GRF.db.look = look ~= GRF.DEFAULT_LOOK and look or nil
    return true
end

function Settings.SetBody(body)
    if not GRF.BODIES[body] then return false end
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
    local okN, name = pcall(GetUnitName, "target", false)
    return Settings.SetNickname(guid, nick, okN and name or nil)
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
        say(key .. ": " .. err)
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
    elseif cmd == "names" then
        if not Settings.SetNameStyle(arg) then say("names first|initial|full") end
        say("names: " .. (GRF.db.nameStyle or "first"))
    elseif cmd == "nick" then
        nickCommand((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
    elseif cmd == "look" then
        if Settings.SetLook(arg) then
            say("look " .. arg .. ": takes effect after /reload")
        else
            say("look classic|clean (now " .. GRF.look .. ")")
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
    elseif cmd == "clickcast" then
        GRF.ClickCastOptions.Toggle()
    elseif cmd == "ind" or cmd == "indicators" then
        indicatorsCommand((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GRF.MEASURED_ON_BUILD)
    else
        say("/grf options - the settings (Options > AddOns)")
        say("/grf clickcast - the click-casting editor; /grf clickcast all|ours - on every unit frame, or our tiles only")
        say("/grf role [auto|healer|caster|melee|tank] - settings follow your role; " .. roleLine())
        say("/grf unlock | lock - move the group frames for this role (out of combat)")
        say("/grf reset - this role's default position")
        say("/grf size <width> <height> | reset - this role's tile size")
        say("/grf solo - show your own frame when not in a group")
        say("/grf pets - show or hide pets (this role)")
        say("/grf ind - buff and debuff indicators (per class); /grf ind <n> on|off, /grf ind reset")
        say("/grf names first|initial|full - how names show (all your characters)")
        say("/grf nick <nickname> | clear - your target's nickname; /grf nick lists, /grf nick remove <n>")
        say("/grf look classic|clean - the glass (after /reload); now " .. GRF.look)
        say("/grf body clear|smoked - the glass body (after /reload); now " .. GRF.body)
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
        -- The look first: every surface belongs to its instance (#37, #38).
        GRF.UseLook(GRF.db.look, GRF.db.glassBody)
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
        -- arg1 = isInitialLogin: warn at a real login, never on /reload. Dev
        -- copies only: re-measuring the client is a chore a player can't do.
        if arg1 and API.IsDevBuild() and API.ClientBuild() ~= GRF.MEASURED_ON_BUILD then
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
