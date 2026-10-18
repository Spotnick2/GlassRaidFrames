-- The glass look (#37, #67) and body (#38): LibGlass r11's Pearl by default
-- (clean, saying so, on an older copy), clean or classic on request, and a
-- clear or smoked body, built once at load from the saved choice (GRF.Glass
-- forwards to that instance). Each boot below is a fresh load, as after
-- /reload. The pin is r11; an older checkout takes the fallback path.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function boot(db)
    GlassRaidFrames = nil
    dofile("tests/wow_stubs.lua")
    party(1)
    return loadAddon({ db = db })
end

local function tile() return childFor("party1") end

-- Default: Pearl, clear. The tiles are built thin (Pearl is clean's rims), and
-- the hover / target rims copy the thin rim (not the classic one over it).
local GRF = boot(nil)
local R11 = select(2, LibStub:GetLibrary("LibGlass-1.0")) >= 11
if R11 then
    eq(GRF.look, "pearl", "Pearl by default")
    eq(GRF.Glass.preset, "pearl", "the instance in use is LibGlass's Pearl")
    eq(GRF.lookFallback, nil, "no fallback")
    eq(GRF.SuiteStatus(), nil, "nothing to say")
else
    eq(GRF.look, "clean", "an older LibGlass: Pearl falls back to clean")
    check(GRF.lookFallback, "and the fallback is flagged")
    eq(GRF.SuiteStatus(), "Pearl needs LibGlass r11 or newer: Clean in use", "and said")
end
check(chatHas("look: Pearl needs") ~= R11, "the fallback is said at load, only then")
eq(GRF.body, "clear", "clear by default")
check(GRF.Glass.STYLE.thinRim == true, "the instance in use has clean's thin rims")
local t = tile()
eq(t.glass.size, "thin_small", "tiles are built thin")
local thin = GRF.Glass.MEDIA .. GRF.Glass.SIZES.thin_small.rim
eq(t.hoverRim._file, thin, "the hover rim follows the thin rim")
eq(t.targetRim._file, thin, "and the target rim")
eq(GRF.db.look, nil, "the default isn't saved")
eq(GRF.paintFailures.build, nil, "the build didn't fail")

-- The setting: saved, junk refused, the slash command, and the options radios.
check(GRF.Settings.SetLook("classic"), "classic accepted")
eq(GRF.db.look, "classic", "classic saved")
check(not GRF.Settings.SetLook("shiny"), "junk refused")
eq(GRF.db.look, "classic", "and the saved choice kept")
eq(GRF.look, R11 and "pearl" or "clean", "nothing rebuilt before /reload")
SlashCmdList.GLASSRAIDFRAMES("look clean")
eq(GRF.db.look, "clean", "/grf look clean: saved (no longer the default)")
SlashCmdList.GLASSRAIDFRAMES("look pearl")
eq(GRF.db.look, nil, "/grf look pearl: back to the default")
newChat()
SlashCmdList.GLASSRAIDFRAMES("look")
check(chatHas("look pearl|clean|classic"), "/grf look lists the three")
check(chatHas("after /reload"), "it says it takes a /reload")
SlashCmdList.GLASSRAIDFRAMES("body smoked")
eq(GRF.db.glassBody, "smoked", "/grf body smoked saved")
check(not GRF.Settings.SetBody("murky"), "a junk body refused")
eq(GRF.db.glassBody, "smoked", "and the saved body kept")
check(GRF.Settings.SetBody("clear"), "clear accepted")
eq(GRF.db.glassBody, nil, "clear isn't saved")

local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local look, body = O.controls.look, O.controls.body
check(look and #look == 3 and body and #body == 2, "two radio rows: three looks, two bodies")
eq(look[1].value .. " " .. look[2].value .. " " .. look[3].value, "pearl clean classic", "Pearl, Clean, Classic")
check(look[1]._checked, "the look radio shows Pearl (the default)")
eq(O.controls.suiteNote and O.controls.suiteNote:GetText(), not R11 and GRF.PEARL_FALLBACK or nil, "the fallback note, only on an older LibGlass")
look[3]._scripts.OnClick(look[3])
eq(GRF.db.look, "classic", "clicking Classic saves it")
check(look[3]._checked and not look[1]._checked, "and the radios follow")
look[2]._scripts.OnClick(look[2])
eq(GRF.db.look, "clean", "clicking Clean saves it")
look[3]._scripts.OnClick(look[3])
body[2]._scripts.OnClick(body[2])
eq(GRF.db.glassBody, "smoked", "clicking Smoked saves it")

-- After a reload: classic rims, the smoked body, the saved knob reaching the
-- instance every file uses.
GRF = boot({ look = "classic", glassBody = "smoked" })
eq(GRF.look, "classic", "classic after /reload")
eq(GRF.body, "smoked", "smoked after /reload")
check(not GRF.Glass.STYLE.thinRim, "classic rims")
eq(GRF.Glass.STYLE.bodyAlpha, GRF.SMOKED, "the smoked body opacity")
t = tile()
eq(t.glass.size, "small", "tiles built with the classic rim")
eq(t.hoverRim._file, GRF.Glass.MEDIA .. GRF.Glass.SIZES.small.rim, "the hover rim is the classic one")

-- Clean and smoked together: one instance with both.
GRF = boot({ glassBody = "smoked" })
check(GRF.Glass.STYLE.thinRim == true and GRF.Glass.STYLE.bodyAlpha == GRF.SMOKED, "clean + smoked in one instance")
eq(tile().glass.size, "thin_small", "still thin")

-- A saved clean is kept (no migration), and builds clean, no fallback.
GRF = boot({ look = "clean" })
eq(GRF.look, "clean", "a saved clean is kept")
eq(GRF.db.look, "clean", "and stays saved")
eq(GRF.lookFallback, nil, "chosen, not a fallback")
eq(GRF.SuiteStatus(), nil, "nothing to say")
if R11 then eq(GRF.Glass.preset, "clean", "the clean instance") end

-- A junk saved look falls back to the default.
GRF = boot({ look = "shiny" })
eq(GRF.look, R11 and "pearl" or "clean", "a junk saved look is the default")

-- A Pearl build that throws, on r11: clean, flagged and said.
if R11 then
    local lib = LibStub("LibGlass-1.0")
    local realNew = lib.New
    local function throwingPearl(db)
        GlassRaidFrames = nil
        dofile("tests/wow_stubs.lua")
        party(1)
        lib.New = function(self, opts)
            if opts and opts.preset == "pearl" then error("boom") end
            return realNew(self, opts)
        end
        local g = loadAddon({ db = db })
        lib.New = realNew
        return g
    end
    GRF = throwingPearl({})
    eq(GRF.look, "clean", "a throwing Pearl build: clean")
    check(GRF.lookFallback, "flagged")
    eq(GRF.SuiteStatus(), GRF.PEARL_FALLBACK, "the status says so")
    check(chatHas("look: Pearl needs LibGlass r11 or newer: Clean in use"), "and said at load")
    eq(GRF.paintFailures.build, nil, "the tiles still built")
    eq(GRF.db.look, nil, "nothing saved")
    -- The file's own default build fell back too; a saved clean reuses that
    -- instance, and isn't a fallback.
    GRF = throwingPearl({ look = "clean" })
    eq(GRF.look, "clean", "a saved clean")
    eq(GRF.lookFallback, nil, "isn't flagged, though the load-time Pearl fell back")
    eq(GRF.SuiteStatus(), nil, "and nothing is said")
end
done("test_look")
