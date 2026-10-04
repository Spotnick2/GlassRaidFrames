-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method
-- walk, falling back to the documented functions.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSRF_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70205.md"
local f = io.open(DUMP, "r")
if not f then
    io.write("test_methods: SKIPPED (no API dump at " .. DUMP .. ")\n")
    os.exit(0)
end
local widget, documented = {}, {}
for line in f:lines() do
    local wm = line:match("^(%a+:%a+)%s*$")
    if wm then widget[wm] = true end
    local fn = line:match("^([%a_]+)%(")
    if fn then documented[fn] = true end
end
f:close()

-- Exercise everything so every method is recorded.
loadAddon()
WoW.fireAllRegistered()
WoW.tick()
for _, cmd in ipairs({ "", "failures", "version", "role", "role healer", "role auto" }) do SlashCmdList.GLASSRAIDFRAMES(cmd) end
-- The options panel: built on show, every control clicked.
local O = GlassRaidFrames.Options._test
O.panel._scripts.OnShow(O.panel)
for _, rb in ipairs(O.controls.role) do rb._scripts.OnClick(rb) end
for _, key in ipairs({ "solo", "blizzard" }) do
    local cb = O.controls[key]
    cb._scripts.OnClick(cb)
end
-- The Click-casting page: shown, a key captured, a row painted.
rawset(_G, "C_CVar", { GetCVar = function() return "0" end, SetCVar = function() return true end })
rawset(_G, "IsControlKeyDown", function() return false end)
rawset(_G, "GetBindingAction", function() return nil end)
rawset(_G, "SetOverrideBindingClick", function() end)
rawset(_G, "ClearOverrideBindings", function() end)
rawset(_G, "GetModifiedClick", function() return "ALT" end)
rawset(_G, "GetCursorInfo", function() return nil end)
rawset(_G, "C_Spell", { GetSpellName = function() return "Renew" end, GetSpellSubtext = function() return "Rank 1" end,
                        GetSpellTexture = function() return 1 end })
local CT = GlassRaidFrames.ClickCastOptions._test
CT.page:Show()
local cap = CT.capture()
cap._scripts.OnClick(cap, "LeftButton")
cap._scripts.OnKeyDown(cap, "5")
GlassRaidFrames.ClickCast.Rows()[1].spell = 139
GlassRaidFrames.ClickCastOptions.Refresh()
WoW.tick()

-- The Indicators page: shown, every kind of control used once.
local IT = GlassRaidFrames.IndicatorOptions._test
IT.page:Show()
local iu = IT.ui
iu.anchors[1]._scripts.OnClick(iu.anchors[1])
iu.size:SetValue(14)
iu.kind[3]._scripts.OnClick(iu.kind[3])
iu.color._scripts.OnClick(iu.color)
iu.idBox:SetText("139"); iu.idBox._scripts.OnTextChanged(iu.idBox)
iu.idAdd._scripts.OnClick(iu.idAdd)
iu.rows[#GlassRaidFrames.Indicators.Setup()]._scripts.OnClick(iu.rows[#GlassRaidFrames.Indicators.Setup()])
iu.add._scripts.OnClick(iu.add)
iu.delete._scripts.OnClick(iu.delete); iu.delete._scripts.OnClick(iu.delete)
WoW.tick()

-- Unlock mode and a drag, so the mover's methods are checked too.
GlassRaidFrames.Movers.Unlock()
local mv = GlassRaidFrames.Movers._test.mover()
UIParent._center = { 512, 384 }
mv._center = { 520, 390 }
mv._scripts.OnDragStart(mv); mv._scripts.OnUpdate(mv); mv._scripts.OnDragStop(mv)
GlassRaidFrames.Movers.Lock()

-- Methods the dump cannot list: Blizzard_AuraContainer is a load-on-demand
-- Blizzard addon the dump did not capture. Evidence they exist on Forever:
-- GlassUnitFrames and DinoUnitFrames call every one of them in game, and the
-- probe built these containers on 70009 (FOREVER-PROBE items 1 and 7).
-- Keep this list exact: anything else missing from the dump still fails.
local AURA_CONTAINER_API = {
    ["AuraContainer:AddAuraGroup"] = true, ["AuraContainer:UpdateAllAuras"] = true,
    ["AuraContainer:SetUnit"] = true,
    ["Button:SetIcon"] = true,   -- on the buttons the container creates
    -- The indicators (#19). In Forever's own Blizzard_CustomAuraContainer.lua /
    -- Blizzard_CustomAuraButton.lua / Blizzard_AuraContainerFlowLayout.lua
    -- (wow-ui-source, forever branch); slots, slot filters/enable/size, the
    -- duration texts and the flow growth were used by RaidProbe in game
    -- (FOREVER-PROBE item 10). The group setters are source-only so far.
    ["AuraContainer:AddAuraSlot"] = true, ["AuraContainer:GetAuraSlotFrame"] = true,
    ["AuraContainer:SetAuraSlotEnabled"] = true, ["AuraContainer:SetAuraSlotFilterString"] = true,
    ["AuraContainer:SetAuraSlotCandidateFilters"] = true,
    ["AuraContainer:SetAuraGroupFilterString"] = true, ["AuraContainer:SetAuraGroupMaxFrameCount"] = true,
    ["AuraContainer:SetAuraGroupLayout"] = true, ["AuraContainer:SetAuraGroupEnabled"] = true,
    ["AuraContainer:GetAuraGroupFrameCount"] = true, ["AuraContainer:GetAuraGroupFrame"] = true,
    ["AuraContainer:SetFlowLayoutAnchorPoint"] = true, ["AuraContainer:SetFlowLayoutGrowthDirection"] = true,
    ["Button:SetDurationCooldown"] = true, ["Button:SetDurationText"] = true, ["Button:SetApplicationCount"] = true,
}

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    local wtype = name:match("^(%a+):")
    local ok = widget[name] or documented[method] or AURA_CONTAINER_API[name]
        or (wtype == "AuraContainer" and widget["Frame:" .. method])   -- a Frame underneath
    check(ok, "method exists on Forever: " .. name)
end
check(n >= 2, "recorded the addon's method calls (" .. n .. ")")
done("test_methods")
