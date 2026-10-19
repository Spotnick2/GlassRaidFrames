-- Follow Glass UI (#67, Glass UI's docs/SUITE.md, API 1): built with LibGlass's
-- Pearl preset only when Glass UI's Theme says so and the winning LibGlass is
-- r11 or newer; anything else is the local look exactly as before, and the
-- saved look and body are never touched. Each boot is a fresh load, as after
-- /reload. On r11 (the pin) Pearl is LibGlass's own; an older copy is modelled
-- by lowering the MINOR. Against an older checkout, Pearl is faked as clean
-- marked with r11's inst.preset, and the MINOR raised.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local reports, themeCalls

-- A Glass UI speaking API 1, with Theme answering `answer` (a function's
-- results, or a value) and Report recording each state it was handed.
local function glassUI(answer)
    return { Suite = {
        API = 1,
        Ready = function() return true end,
        Theme = function(addon)
            themeCalls[#themeCalls + 1] = addon
            if type(answer) == "function" then return answer() end
            return answer
        end,
        Report = function(addon, state) reports[#reports + 1] = { addon = addon, state = state } end,
    } }
end

local function pearl() return { name = "pearl", preset = "pearl" } end

-- LibGlass at `minor`; `newFails` makes the Pearl build throw. pearlBuilt
-- counts New's Pearl calls.
-- LibStub outlives a boot (the reloaded copy isn't newer, so it's skipped):
-- restoreLib puts the real New and MINOR back before the next one.
local pearlBuilt, restoreLib
local function libGlass(minor, newFails)
    return function()
        local lib, realMinor = LibStub:GetLibrary("LibGlass-1.0")
        local realNew = lib.New
        if not restoreLib then
            restoreLib = function()
                lib.New, LibStub.minors["LibGlass-1.0"] = realNew, realMinor
                restoreLib = nil
            end
        end
        if minor then LibStub.minors["LibGlass-1.0"] = minor end
        -- The real New checks its own MINOR finished loading: it sees the real one.
        local function new(self, opts)
            local raised = LibStub.minors["LibGlass-1.0"]
            LibStub.minors["LibGlass-1.0"] = realMinor
            local ok, inst = pcall(realNew, self, opts)
            LibStub.minors["LibGlass-1.0"] = raised
            if not ok then error(inst, 0) end
            return inst
        end
        lib.New = function(self, opts)
            if opts and opts.preset == "pearl" then
                pearlBuilt = pearlBuilt + 1
                if newFails then error("LibGlass-1.0: did not finish loading") end
                if realMinor >= 11 then return new(self, opts) end   -- r11 builds the real Pearl
                local inst = new(self, { preset = "clean" })
                inst.preset = "pearl"
                return inst
            end
            return new(self, opts)
        end
    end
end

local function boot(ui, db, minor, newFails, layout)
    if restoreLib then restoreLib() end
    GlassRaidFrames = nil
    dofile("tests/wow_stubs.lua")
    party(1)
    reports, themeCalls, pearlBuilt = {}, {}, 0
    rawset(_G, "GlassUI", ui)   -- nil: no Glass UI this boot
    return loadAddon({ db = db, beforeLoaded = libGlass(minor, newFails), layout = layout })
end

-- The saved appearance a player might have: classic and smoked.
local function saved() return { look = "classic", glassBody = "smoked" } end
local function localLook(GRF, what)
    eq(GRF.following, nil, what .. ": not following")
    eq(GRF.look, "classic", what .. ": the saved classic look is built")
    eq(GRF.body, "smoked", what .. ": with the saved smoked body")
    check(not GRF.Glass.STYLE.thinRim and GRF.Glass.STYLE.bodyAlpha == GRF.SMOKED, what .. ": in the instance in use")
    eq(GRF.db.look, "classic", what .. ": the saved look untouched")
    eq(GRF.db.glassBody, "smoked", what .. ": the saved body untouched")
    eq(GRF.paintFailures.build, nil, what .. ": the build didn't fail")
end

-- Glass UI absent, or not speaking API 1 exactly: never asked, never told.
local GRF = boot(nil, saved(), 11)
localLook(GRF, "no Glass UI")
eq(GRF.SuiteStatus(), nil, "no Glass UI: nothing to say")
local absent = {
    ["Glass UI not a table"] = "GlassUI",
    ["no Suite (the released Glass UI)"] = {},
    ["Suite not a table"] = { Suite = true },
    ["API 2"] = (function() local g = glassUI(pearl()); g.Suite.API = 2; return g end)(),
    ["API \"1\""] = (function() local g = glassUI(pearl()); g.Suite.API = "1"; return g end)(),
    ["Theme not a function"] = (function() local g = glassUI(pearl()); g.Suite.Theme = "pearl"; return g end)(),
    ["Report not a function"] = (function() local g = glassUI(pearl()); g.Suite.Report = nil; return g end)(),
}
for what, ui in pairs(absent) do
    GRF = boot(ui, saved(), 11)
    localLook(GRF, what)
    eq(#themeCalls, 0, what .. ": Theme never asked")
    eq(#reports, 0, what .. ": nothing reported")
    eq(pearlBuilt, 0, what .. ": Pearl never built")
end

-- Speaking the API but not saying Pearl: the local look, reported as such.
local notPearl = {
    ["Theme throwing"] = function() error("boom") end,
    ["\"not-ready\""] = function() return nil, "not-ready" end,
    ["\"not-following\""] = function() return nil, "not-following" end,
    ["junk: a string"] = "pearl",
    ["junk: another preset"] = { name = "x", preset = "shiny" },
    ["junk: a throwing table"] = function() return setmetatable({}, { __index = function() error("no") end }) end,
}
for what, answer in pairs(notPearl) do
    GRF = boot(glassUI(answer), saved(), 11)
    localLook(GRF, what)
    eq(themeCalls[1], "GlassRaidFrames", what .. ": asked by folder name")
    eq(#reports, 1, what .. ": reported once")
    local r = reports[1] and reports[1].state or {}
    eq(r.api, 1, what .. ": api 1")
    eq(r.built, nil, what .. ": built the local look")
    eq(r.reason, nil, what .. ": no failure (it wasn't told Pearl)")
    eq(GRF.SuiteStatus(), nil, what .. ": nothing to say")
end

-- Told Pearl, with an older LibGlass winning: the local look, and why.
GRF = boot(glassUI(pearl()), saved(), 10)
localLook(GRF, "LibGlass r10")
eq(pearlBuilt, 0, "an older LibGlass is never asked for Pearl")
eq(reports[1].state.reason, "library-too-old", "reported: library too old")
eq(reports[1].state.minor, 10, "with the MINOR it saw")
eq(GRF.SuiteStatus(), "own look: library-too-old", "the status says why")
newChat()
SlashCmdList.GLASSRAIDFRAMES("look")
check(chatHas("now classic; own look: library%-too%-old"), "/grf look says so")
check(GRF.Settings.SetBody("clear"), "the local look stays settable")
GRF.Settings.SetBody("smoked")
-- A newer copy arriving after the build changes nothing this session.
local inUse = GRF.Glass.STYLE
libGlass(11)()
GRF.Settings.SetClickCastOthers(true)
eq(GRF.following, nil, "a newer LibGlass after the build: still the local look")
check(GRF.Glass.STYLE == inUse, "the same instance")
eq(pearlBuilt, 0, "and no Pearl build")
eq(reports[#reports].state.reason, "library-too-old", "the report still says what was built")

-- r11 whose New throws: the local look, and why.
GRF = boot(glassUI(pearl()), saved(), 11, true)
localLook(GRF, "New throwing")
eq(pearlBuilt, 1, "Pearl was attempted")
eq(reports[1].state.reason, "build-failed", "reported: build failed")
eq(GRF.SuiteStatus(), "own look: build-failed", "the status says why")

-- Following: Pearl built, the look and body suspended but kept.
GRF = boot(glassUI(pearl()), saved(), 11)
eq(GRF.following, "pearl", "following Glass UI")
eq(GRF.Glass.preset, "pearl", "the instance in use is Pearl")
eq(GRF.paintFailures.build, nil, "the build didn't fail")
eq(tostring(childFor("party1").glass ~= nil), "true", "the tiles were built on it")
local r = reports[1].state
eq(#reports, 1, "reported once at load")
eq(reports[1].addon, "GlassRaidFrames", "as GlassRaidFrames")
eq(r.api, 1, "api 1")
eq(r.built, "pearl", "built Pearl")
eq(r.reason, nil, "no failure")
eq(r.minor, 11, "LibGlass's MINOR")
eq(type(r.options), "function", "an options opener")
eq(r.clickCast and r.clickCast.others, true, "click-casting on other frames: the setting, on")
-- The group layout (#69): off in these tests (the harness's default).
eq(r.layout and tostring(r.layout.on) .. " " .. r.layout.mode, "false legacy", "the layout: what this session applied")
local opened = 0
local realOpen = GRF.ClickCastOptions.Open
GRF.ClickCastOptions.Open = function(parent) opened = opened + 1; eq(parent, nil, "the editor opens standalone") end
r.clickCast.open()
eq(opened, 1, "clickCast.open opens the editor")
GRF.ClickCastOptions.Open = realOpen
check(not GRF.Settings.SetLook("clean"), "the look is refused while following")
check(not GRF.Settings.SetBody("clear"), "and the body")
eq(GRF.db.look, "classic", "the saved look kept")
eq(GRF.db.glassBody, "smoked", "the saved body kept")
newChat()
SlashCmdList.GLASSRAIDFRAMES("look clean")
SlashCmdList.GLASSRAIDFRAMES("body clear")
local lines = newChat()
eq(#lines, 2, "two answers")
eq(lines[1], lines[2], "the same one")
check(lines[1] and lines[1]:find("Look: following Glass UI (Pearl), set in Glass UI", 1, true), "/grf look and body: set in Glass UI")
eq(GRF.db.look, "classic", "the slash command wrote nothing")
eq(GRF.db.glassBody, "smoked", "the body neither")
SlashCmdList.GLASSRAIDFRAMES("help")
check(chatHas("/grf look, /grf body %- Look: following Glass UI"), "help says so too")
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
eq(O.controls.suiteNote and O.controls.suiteNote:GetText(), "Look: following Glass UI (Pearl), set in Glass UI", "the options page says so")
-- Off, and seen to be off (in game the label and the radio art stayed bright).
for _, group in ipairs({ O.controls.look, O.controls.body }) do
    for _, rb in ipairs(group) do
        eq(rb._enabled, false, "radio " .. rb.value .. " off")
        eq(rb._alpha, 0.5, "radio " .. rb.value .. " dimmed")
        eq(rb.label._textColor and rb.label._textColor[1], 0.5, "radio " .. rb.value .. "'s label grey")
    end
end
eq(O.controls.names[1]._alpha, nil, "the Names radios stay bright")
eq(O.controls.glassUI, nil, "no Glass UI button: this Suite can't open its settings")
O.controls.look[1]._scripts.OnClick(O.controls.look[1])
eq(GRF.db.look, "classic", "a click on a radio writes nothing")
-- The click-cast setting changes: reported again, with the new value.
GRF.Settings.SetClickCastOthers(false)
eq(#reports, 2, "reported again when the click-cast setting changes")
eq(reports[2].state.clickCast.others, false, "others = false is the setting")
eq(reports[2].state.built, "pearl", "the same build")

-- Not following any more, after a /reload: the local look and its keys.
GRF = boot(glassUI(function() return nil, "not-following" end), saved(), 11)
localLook(GRF, "following turned off")
check(GRF.Glass.preset ~= "pearl", "not Pearl")   -- r11 names every instance's preset; r10 none

-- A failure on the options page and the radios stay on.
GRF = boot(glassUI(pearl()), saved(), 10)
O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
eq(O.controls.suiteNote and O.controls.suiteNote:GetText(), "own look: library-too-old", "the page says why")
check(O.controls.look[1]._enabled ~= false, "the radios stay on")
eq(O.controls.look[1]._alpha, nil, "and bright")
eq(O.controls.look[1].label._textColor, nil, "their labels too")
O.controls.look[1]._scripts.OnClick(O.controls.look[1])
eq(GRF.db.look, nil, "and still save")

-- Glass UI's settings, one click away, when its Suite has the optional Open
-- (following or not: it's also where Follow is turned on).
for _, following in ipairs({ true, false }) do
    local ui = glassUI(following and pearl() or function() return nil, "not-following" end)
    local openCalls = 0
    ui.Suite.Open = function(...) openCalls = openCalls + 1; eq(select("#", ...), 0, "Open takes no arguments") end
    GRF = boot(ui, saved(), 11)
    O = GRF.Options._test
    O.panel._scripts.OnShow(O.panel)
    local b = O.controls.glassUI
    local what = following and "following" or "not following"
    check(b ~= nil, what .. ": a Glass UI settings button")
    eq(b and b:GetText(), "Glass UI settings", what .. ": named so")
    if b then b._scripts.OnClick(b) end
    eq(openCalls, 1, what .. ": the click opens Glass UI's settings")
end
local ui = glassUI(pearl())
ui.Suite.Open = function() error("boom") end
GRF = boot(ui, saved(), 11)
O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
check(pcall(O.controls.glassUI._scripts.OnClick, O.controls.glassUI), "an Open that throws stays Glass UI's problem")
GRF = boot(nil, saved(), 11)
O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
eq(O.controls.glassUI, nil, "no Glass UI: no button")
GRF = boot({ Suite = { API = 2, Theme = pearl, Report = function() end, Open = function() end } }, saved(), 11)
O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
eq(O.controls.glassUI, nil, "a Suite that isn't API 1: no button")

-- The group layout's mode at startup is the role's, once the role is known
-- (Codex P2 on #72: the first report went out with no role, as "side").
GlassRaidFramesCharDB = { role = "HEALER" }
GRF = boot(glassUI(pearl()), saved(), 11, nil, true)
eq(#reports, 1, "layout on: reported once at load")
local lay = reports[1].state.layout
eq(lay and tostring(lay.on) .. " " .. lay.mode, "true hud", "a healer: the HUD, from the first report")
GlassRaidFramesCharDB = { role = "CASTER" }
GRF = boot(glassUI(pearl()), { profiles = { CASTER = { layout = "hud" } } }, 11, nil, true)
eq(reports[1].state.layout.mode, "hud", "a caster saved to the HUD: the HUD")
GlassRaidFramesCharDB = { role = "CASTER" }
GRF = boot(glassUI(pearl()), saved(), 11, nil, true)
eq(reports[1].state.layout.mode, "side", "a caster by default: the side")
GRF.Settings.SetRole("HEALER")
eq(reports[#reports].state.layout.mode, "hud", "a role change reports the new role's mode")
GlassRaidFramesCharDB = nil

done("test_suite")
