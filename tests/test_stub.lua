-- The harness's own model of the client, checked so the tests that lean on
-- it mean something: protected methods and secure APIs refused to insecure
-- code in combat, addon handlers running insecurely whoever fires them,
-- secrets by execution context, the combat order, and names in two parts.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The lockdown is on inside a PLAYER_REGEN_DISABLED handler and off inside
-- PLAYER_REGEN_ENABLED's (the client's order).
local seen = {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event) seen[event] = InCombatLockdown() end)
WoW.enterCombat()
eq(seen.PLAYER_REGEN_DISABLED, true, "the lockdown is on when PLAYER_REGEN_DISABLED arrives")
WoW.leaveCombat()
eq(seen.PLAYER_REGEN_ENABLED, false, "and off when PLAYER_REGEN_ENABLED does")

-- Every protected method: refused to insecure code on a protected frame in
-- combat, applied otherwise, and applied for the client's own code.
local secure = CreateFrame("Button", "StubSecure", UIParent, "SecureFrameTemplate")
local plainFrame = CreateFrame("Frame", "StubPlain", UIParent)
local ARGS = { SetPoint = { "CENTER", UIParent, "CENTER", 0, 0 }, SetAllPoints = { UIParent }, ClearPoint = { "CENTER" },
    SetWidth = { 10 }, SetHeight = { 10 }, SetSize = { 10, 10 }, SetScale = { 2 }, SetFrameStrata = { "HIGH" },
    SetFrameLevel = { 5 }, SetFixedFrameStrata = { true }, SetFixedFrameLevel = { true }, SetToplevel = { true },
    SetHitRectInsets = { 1, 1, 1, 1 }, SetClampedToScreen = { true }, EnableMouse = { true }, EnableMouseWheel = { true },
    EnableKeyboard = { true }, SetID = { 3 }, RegisterForClicks = { "AnyUp" }, SetEnabled = { true },
    ClearAttribute = { "x" }, SetParent = { UIParent }, SetShown = { true } }
for _, name in ipairs(WoW.PROTECTED_METHODS) do
    local args = ARGS[name] or {}
    WoW.combat, WoW.blocked = true, {}
    secure[name](secure, unpack(args))
    eq(WoW.blocked[1], "StubSecure:" .. name, name .. ": an insecure call on a protected frame in combat is recorded")
    WoW.blocked = {}
    plainFrame[name](plainFrame, unpack(args))
    eq(#WoW.blocked, 0, name .. ": a plain frame is fine in combat")
    WoW.secureCode = true
    secure[name](secure, unpack(args))
    WoW.secureCode = false
    eq(#WoW.blocked, 0, name .. ": the client's own code is fine in combat")
    WoW.combat = false
    secure[name](secure, unpack(args))
    eq(#WoW.blocked, 0, name .. ": and out of combat")
end
-- The measured exception: SetAttribute does nothing in combat.
WoW.combat, WoW.blocked = true, {}
secure:SetAttribute("type1", "target")
eq(WoW.blocked[1], "StubSecure:SetAttribute", "SetAttribute on a protected frame in combat is recorded")
eq(secure:GetAttribute("type1"), nil, "and not applied")
WoW.combat = false
secure:SetAttribute("type1", "target")
eq(secure:GetAttribute("type1"), "target", "out of combat it applies")
-- A blocked Show leaves the frame as it was.
secure:Hide()
WoW.combat, WoW.blocked = true, {}
secure:Show()
check(not secure:IsShown(), "a blocked Show leaves the frame hidden")
WoW.combat = false
-- Not protected: alpha, and the movers' calls (not flagged in the docs).
WoW.combat, WoW.blocked = true, {}
secure:SetAlpha(0.5); secure:SetMovable(true); secure:RegisterForDrag("LeftButton")
eq(#WoW.blocked, 0, "SetAlpha, SetMovable and RegisterForDrag aren't protected")
WoW.combat = false

-- Secure APIs: refused to insecure code in combat whatever the target frame.
local holder = CreateFrame("Frame")
WoW.combat, WoW.blocked = true, {}
RegisterStateDriver(holder, "visibility", "show")
RegisterUnitWatch(holder)
SetOverrideBindingClick(holder, true, "7", "StubSecure")
ClearOverrideBindings(holder)
eq(table.concat(WoW.blocked, ","), "RegisterStateDriver,RegisterUnitWatch,SetOverrideBindingClick,ClearOverrideBindings",
    "the state-driver, unit-watch and override-binding APIs are refused in combat")
eq(WoW.stateDrivers[holder], nil, "and the driver isn't installed")
WoW.secureCode, WoW.blocked = true, {}
RegisterStateDriver(holder, "visibility", "show")
SetOverrideBindingClick(holder, true, "7", "StubSecure")
WoW.secureCode = false
eq(#WoW.blocked, 0, "the client's own secure code may call them in combat")
check(WoW.stateDrivers[holder] ~= nil, "and the driver is installed")
WoW.combat = false
-- The SecureHandler API errors in combat for anyone, as the client's does.
local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
WoW.combat, WoW.blocked = true, {}
local ok, err = pcall(SecureHandlerWrapScript, secure, "OnEnter", header, "return")
check(not ok and tostring(err):find("Cannot use SecureHandlers API during combat"), "SecureHandlerWrapScript errors in combat")
WoW.secureCode = true
local okS = pcall(SecureHandlerExecute, header, "return")
WoW.secureCode = false
check(not okS, "even for secure code")
eq(#WoW.blocked, 2, "and both are recorded")
WoW.combat = false
SecureHandlerWrapScript(secure, "OnEnter", header, "return")
check(secure._wraps.OnEnter ~= nil, "out of combat the wrap is recorded")

-- Addon handlers run insecurely, whoever fires them: a hook that touches a
-- protected frame is blocked in combat even when the client's secure code
-- fired it.
local hooked = CreateFrame("Button", "StubHooked", UIParent, "SecureFrameTemplate")
local inHook
hooked:HookScript("OnAttributeChanged", function(self, k)
    if k == "unit" then inHook = WoW.secureCode; secure:SetPoint("CENTER") end
end)
WoW.combat, WoW.blocked = true, {}
WoW.secureCode = true   -- as the client's header code, setting the unit
hooked._attrs.unit = "raid1"
hooked._scripts.OnAttributeChanged(hooked, "unit", "raid1")
WoW.secureCode = false
eq(inHook, false, "the hook ran as insecure code")
eq(WoW.blocked[1], "StubSecure:SetPoint", "and its protected touch was recorded")
WoW.combat = false
-- A SetScript handler too, and an error in it restores the flag.
local thrower = CreateFrame("Frame")
thrower:SetScript("OnEvent", function() error("boom") end)
WoW.secureCode = true
local okT = pcall(thrower._scripts.OnEvent, thrower, "X")
check(not okT and WoW.secureCode == true, "an erroring handler restores the flag")
WoW.secureCode = false

-- Secrets by execution context: the addon gets a secret, the client's own
-- code the plain value (a model: the real client lets its code read them).
WoW.SetUnit("party1", { name = "Karuzo Elegia" })
WoW.SetUnit("party2", { name = "Kaleid" })
WoW.secretFields.name = true
local first, sur = UnitName("party1")
check(issecretvalue(first) and issecretvalue(sur), "UnitName: both parts secret for the addon")
local f2, s2 = UnitName("party2")
check(issecretvalue(f2) and s2 == nil, "a unit without a surname: a secret first name, nil surname")
WoW.secureCode = true
first, sur = UnitName("party1")
WoW.secureCode = false
eq(first .. "|" .. sur, "Karuzo|Elegia", "the client's own code reads the plain parts")
check(issecretvalue(GetUnitName("party1")), "GetUnitName: the full name, secret whole")
WoW.secretFields.name = nil
eq(GetUnitName("party1"), "Karuzo Elegia", "plain: first and surname joined")
eq(GetUnitName("party2"), "Kaleid", "plain, no surname")
eq(select(2, UnitName("party1")), "Elegia", "UnitName's second return is the surname")

-- The header model fires OnHide/OnShow when it hides or shows a child, so a
-- hook on them runs (insecurely).
WoW.reset()
party(1)
local GRF = loadAddon()
local child = childFor("party1")
local hid, hidSecure = 0, nil
child:HookScript("OnHide", function() hid = hid + 1; hidSecure = WoW.secureCode end)
WoW.enterCombat()
WoW.SetUnit("party1", nil)
WoW.layoutHeaders()
eq(hid, 1, "a child hidden by the header fires OnHide")
eq(hidSecure, false, "with the hook running insecurely")
WoW.leaveCombat()

done("test_stub")
