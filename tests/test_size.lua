-- Resizable tiles, per role: every child, its bar and name, the columns and
-- the container follow; out of combat only; the options' sliders drive it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

UIParent._width, UIParent._height = 1365, 768
party(2)
GlassRaidFramesCharDB = { role = "HEALER" }
local GRF = loadAddon()
local H = GRF.Header
local function child(i) return H.children[i] end
local function gridPoint() local p = H.container._points; return p[#p] end

-- Default: Cell's look.
eq(child(1):GetWidth(), 82, "default width (Cell's look)")
eq(child(1):GetHeight(), 58, "default height")
eq(child(1).health._height, GRF.Frames.BarHeight(child(1)), "the health bar fills the tile above the power bar")
eq(child(1).health._height + child(1).power._height + 1, 58 - 2 * GRF.Glass.Inset("small"), "health + power + gap fill the tile")
eq(child(1).nameText._font[2], GRF.Frames.NameSize(58) + GRF.Glass.FONTS[GRF.Glass.fontKey].bump, "the name scales with it")
local gw, gh = H.Size()
eq(H.container._width, gw, "the container is the grid's size")
eq(gw, 8 * 82 + 7 * H.GAP, "8 columns")
eq(gh, 5 * 58 + 4 * H.GAP, "5 rows")

-- /grf size: every tile, bar, name, column and the container follow; the
-- grid keeps its centre.
local before = gridPoint()
SlashCmdList.GLASSRAIDFRAMES("size 100 40")
eq(GRF.Profile().size.w, 100, "saved in the role's profile (w)")
eq(GRF.Profile().size.h, 40, "(h)")
for _, i in ipairs({ 1, 17, 40 }) do
    eq(child(i):GetWidth(), 100, "child " .. i .. " is resized (w)")
    eq(child(i):GetHeight(), 40, "child " .. i .. " is resized (h)")
end
eq(child(1).health._height + child(1).power._height + 1, 40 - 2 * GRF.Glass.Inset("small"), "the bars follow")
eq(child(1).nameText._font[2], GRF.Frames.NameSize(40) + GRF.Glass.FONTS[GRF.Glass.fontKey].bump, "the name follows")
local hp = H.headers[3]._points[#H.headers[3]._points]
eq(hp[4], 2 * (100 + H.GAP), "column 3 moves over by the new width")
eq(H.container._width, 8 * 100 + 7 * H.GAP, "the container follows")
local after = gridPoint()
eq(after[4], before[4], "the grid keeps its centre (x)")
eq(after[5], before[5], "(y)")
check(chatHas("100 x 40"), "/grf size says the new size")

-- Out-of-range sizes are clamped; a malformed save falls back.
SlashCmdList.GLASSRAIDFRAMES("size 999 5")
eq(child(1):GetWidth(), H.MAX_W, "width is clamped to the maximum")
eq(child(1):GetHeight(), H.MIN_H, "height to the minimum")
GRF.Profile().size = { w = "big", h = 50 }
H.ApplySize()
eq(child(1):GetWidth(), H.DEFAULT_W, "a malformed width falls back to the default")
eq(child(1):GetHeight(), 50, "the valid height is kept")

-- Per role: each role has its own size; switching follows.
SlashCmdList.GLASSRAIDFRAMES("size 90 45")
GRF.Settings.SetRole("caster")
eq(child(1):GetWidth(), H.DEFAULT_W, "the caster role has its own (default) size")
SlashCmdList.GLASSRAIDFRAMES("size 60 30")
GRF.Settings.SetRole("healer")
eq(child(1):GetWidth(), 90, "back to healer: its size returns")
eq(GRF.db.profiles.CASTER.size.w, 60, "the caster's is kept")

-- Reset.
SlashCmdList.GLASSRAIDFRAMES("size reset")
eq(GRF.Profile().size, nil, "reset forgets the role's size")
eq(child(1):GetWidth(), H.DEFAULT_W, "and goes back to the default")

-- In combat: the size change waits; nothing protected is touched.
WoW.combat = true
WoW.blocked = {}
SlashCmdList.GLASSRAIDFRAMES("size 70 50")
eq(child(1):GetWidth(), H.DEFAULT_W, "no resize in combat")
eq(#WoW.blocked, 0, "and nothing protected touched")
check(not H.ApplySize(), "a direct resize is refused in combat")
eq(#WoW.blocked, 0, "without touching the protected tiles")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(child(1):GetWidth(), 70, "resized when combat ends")

-- An unlocked mover follows the new grid size.
GRF.Movers.Unlock()
SlashCmdList.GLASSRAIDFRAMES("size 80 40")
local mv = GRF.Movers._test.mover()
eq(mv._width, select(1, H.Size()), "the mover takes the new grid size")
GRF.Movers.Lock()

-- The options' sliders: dragging saves; refreshing the panel doesn't.
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local ws, hs = O.controls.width, O.controls.height
eq(ws._value, 80, "the width slider shows the role's width")
local saves = 0
local realSet = GRF.Settings.SetSize
GRF.Settings.SetSize = function(...) saves = saves + 1; return realSet(...) end
O.panel._scripts.OnShow(O.panel)
eq(saves, 0, "opening the panel doesn't save a size")
GRF.Settings.SetSize = realSet
-- A drag is many value changes: one resize once it pauses (code review).
local applies = 0
local realApply = H.ApplySize
H.ApplySize = function(...) applies = applies + 1; return realApply(...) end
for v = 81, 110 do ws:SetValue(v) end
eq(child(1):GetWidth(), 80, "nothing resizes mid-drag")
WoW.flushTimers()
eq(child(1):GetWidth(), 110, "the drag's last value applies once it pauses")
eq(applies, 1, "one resize for the whole drag")
H.ApplySize = realApply
hs:SetValue(48)
WoW.flushTimers()
eq(child(1):GetHeight(), 48, "the height slider too")
eq(child(1):GetWidth(), 110, "keeping the width")

-- A role switch while a slider resize is pending: the drag was saved to the
-- role that made it, and the other role keeps its own (Codex review).
GRF.db.profiles.HEALER.size = { w = 90, h = 48 }
GRF.db.profiles.CASTER.size = { w = 70, h = 40 }
H.ApplySize()
ws:SetValue(120)                       -- healer drag, resize pending
GRF.Settings.SetRole("caster")
WoW.flushTimers()
eq(GRF.db.profiles.HEALER.size.w, 120, "the drag was saved to the healer")
eq(GRF.db.profiles.CASTER.size.w, 70, "the caster keeps its own width")
eq(child(1):GetWidth(), 70, "and the grid shows the caster's")
GRF.Settings.SetRole("healer")
eq(child(1):GetWidth(), 120, "back to healer: the dragged width")

-- A Default size while a slider resize is pending wins.
ws:SetValue(130)
local defaultButton
for _, f in ipairs(WoW.frames) do
    if f._type == "Button" and f._text == "Default size" then defaultButton = f end
end
defaultButton._scripts.OnClick(defaultButton)
WoW.flushTimers()
eq(GRF.Profile().size, nil, "Default size isn't undone by the pending drag")
eq(child(1):GetWidth(), H.DEFAULT_W, "the grid shows the default")
ws:SetValue(110); hs:SetValue(48); WoW.flushTimers()

-- Each group header takes the new width: it centres its first child on its
-- OWN width (SecureGroupHeaders.lua:202), so a stale one shifts the column.
for g = 1, 8 do eq(H.headers[g]._width, 110, "header " .. g .. " takes the tile width") end

-- In combat a slider drag is silent (it used to print on every tick).
newChat()
WoW.combat = true
for v = 90, 100 do ws:SetValue(v) end
WoW.flushTimers()
local spam = 0
for _, line in ipairs(newChat()) do if line:find("combat ends") then spam = spam + 1 end end
eq(spam, 0, "no chat line per slider tick in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(child(1):GetWidth(), 100, "applied when combat ends")

-- A role still on its side default is re-placed from the new grid size (the
-- side default hugs the screen's left edge); a saved spot keeps its centre.
GRF.Settings.SetRole("melee")
eq(GRF.Profile().pos, nil, "melee has no saved position")
SlashCmdList.GLASSRAIDFRAMES("size 120 50")
local mp = gridPoint()
eq(mp[4], select(1, H.DefaultPosition("MELEE")), "the side default is recomputed for the wider grid")
check(mp[4] - select(1, H.Size()) / 2 >= -1365 / 2, "and the grid stays on screen")

-- One tile's relayout failing doesn't stop the resize.
child(5).relayout = function() error("boom") end
SlashCmdList.GLASSRAIDFRAMES("size 90 50")
eq(child(40):GetWidth(), 90, "the other tiles still resize")
eq(H.container._width, 8 * 90 + 7 * H.GAP, "and the container")
check(GRF.paintFailures.relayout, "the failure is recorded")
GRF.paintFailures.relayout = nil
child(5).relayout = GRF.Frames.Layout

-- /grf size with one number sets the width; nonsense says how.
SlashCmdList.GLASSRAIDFRAMES("size 95")
eq(child(1):GetWidth(), 95, "one number: the width")
eq(child(1):GetHeight(), 50, "the height is kept")
newChat()
SlashCmdList.GLASSRAIDFRAMES("size 80x60")
check(newChat()[1]:find("usage"), "malformed input prints the usage")

eq(next(GRF.paintFailures), nil, "no failures")
done("test_size")
