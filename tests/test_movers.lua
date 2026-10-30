-- Unlock mode: the insecure mover drags the protected container, out of
-- combat only, and the position is saved and validated.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

party(1)
UIParent._center = { 512, 384 }
local GRF = loadAddon({ db = { pos = { x = "bad", y = 5 } } })
local H, M = GRF.Header, GRF.Movers
local c = H.container

-- A malformed save falls back to the default.
local p = c._points[#c._points]
eq(p[1], "CENTER", "the grid is placed by its centre")
local dx, dy = H.DefaultPosition(GRF.role)
eq(p[4], dx, "a malformed save falls back to the role's default x")
eq(p[5], dy, "and y")

check(M.Unlock(), "unlock out of combat")
local mv = M._test.mover()
check(mv._shown and not mv._protected, "an insecure mover shows")
local anchor = mv._points[#mv._points]
eq(anchor[1], "ALL", "the mover is anchored to the container")
eq(anchor[2], c, "(never the other way round)")
eq(#c._points, 1, "the container keeps one anchor")

-- Drag: the mover moves, the container follows, the position is saved.
mv._scripts.OnDragStart(mv)
mv._center = { 612, 434 }
mv._scripts.OnUpdate(mv)
p = c._points[#c._points]
eq(p[4], 100, "the container follows the drag (x)")
eq(p[5], 50, "(y)")
mv._scripts.OnDragStop(mv)
eq(GRF.Profile().pos.x, 100, "the position is saved (x)")
eq(GRF.Profile().pos.y, 50, "(y)")
eq(mv._points[#mv._points][2], c, "the mover re-anchors to the container")

-- Combat locks; unlocking is refused in combat.
WoW.enterCombat()
check(not M.IsUnlocked(), "combat locks")
check(not M.Unlock(), "and unlocking is refused in combat")
WoW.combat = false

local announced = {}
rawset(_G, "EventRegistry", { TriggerEvent = function(_, event, ...) announced[#announced + 1] = { event, ... } end })
UIParent._width, UIParent._height = 1024, 768

-- Combat starting mid-drag keeps and SAVES the spot the grid followed to
-- (PLAYER_REGEN_DISABLED fires before lockdown; code review).
M.Unlock()
mv._scripts.OnDragStart(mv)
mv._center = { 312, 184 }
mv._scripts.OnUpdate(mv)
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.combat = true
check(not M.IsUnlocked(), "combat mid-drag locks")
eq(GRF.Profile().pos.x, -200, "the dragged-to position is saved (x)")
eq(GRF.Profile().pos.y, -200, "(y)")
check(#announced > 0 and announced[#announced][1] == GRF.LAYOUT_EVENT, "and announces it (code review)")
WoW.combat = false
eq(mv._width, select(1, H.Size()), "the mover has an explicit size")
check(WoW.methodsCalled["Frame:SetDontSavePosition"], "the client doesn't save the mover's position")

-- Right-click locks; reset forgets the saved spot.
M.Unlock()
mv._scripts.OnMouseUp(mv, "RightButton")
check(not M.IsUnlocked(), "right-click locks")
SlashCmdList.GLASSRAIDFRAMES("reset")
eq(GRF.Profile().pos, nil, "reset forgets the role's saved position")
p = c._points[#c._points]
eq(p[4], select(1, H.DefaultPosition(GRF.role)), "and puts the grid back (x)")

-- A position saved before roles existed becomes the current role's (migration).
WoW.reset()
UIParent._center = { 512, 384 }
party(1)
GRF = loadAddon({ db = { pos = { x = -40, y = 20 } } })
p = GRF.Header.container._points[#GRF.Header.container._points]
eq(p[4], -40, "an old saved position is restored (x)")
eq(p[5], 20, "(y)")

done("test_movers")
