-- The glass look (#37) and body (#38): LibGlass r6's clean preset by default,
-- classic on request, and a clear or smoked body, built once at load from the
-- saved choice (GRF.Glass forwards to that instance). Each boot below is a
-- fresh load, as after /reload.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function boot(db)
    GlassRaidFrames = nil
    dofile("tests/wow_stubs.lua")
    party(1)
    return loadAddon({ db = db })
end

local function tile() return childFor("party1") end

-- Default: clean, clear. The tiles are built thin, and the hover / target rims
-- copy the thin rim (not the classic one over it).
local GRF = boot(nil)
eq(GRF.look, "clean", "clean by default")
eq(GRF.body, "clear", "clear by default")
check(GRF.Glass.STYLE.thinRim == true, "the instance in use is LibGlass's clean preset")
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
eq(GRF.look, "clean", "nothing rebuilt before /reload")
SlashCmdList.GLASSRAIDFRAMES("look clean")
eq(GRF.db.look, nil, "/grf look clean: back to the default")
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
check(look and #look == 2 and body and #body == 2, "two radio rows")
check(look[1]._checked and look[1].value == "clean", "the look radio shows clean")
look[2]._scripts.OnClick(look[2])
eq(GRF.db.look, "classic", "clicking Classic saves it")
check(look[2]._checked and not look[1]._checked, "and the radios follow")
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

-- A junk saved look falls back to the default.
GRF = boot({ look = "shiny" })
eq(GRF.look, "clean", "a junk saved look is the default")
done("test_look")
