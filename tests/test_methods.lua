-- Every widget method the addon calls must exist on this client, for that
-- widget type (WowTestKit's Kit.checkMethods against the pinned build).
--
-- A method the build lacks reads as nil on the stub's widgets, but one the
-- stub implements answers on any type, and an AuraContainer (a type the
-- build's lists lack) answers everything: so the exercise below runs the
-- addon as widely as is cheap, then every recorded "Type:Method" is checked.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

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
GlassRaidFrames.ClickCastOptions.Open()
CT.ui.add._scripts.OnClick(CT.ui.add, "LeftButton")
CT.keyboard()._scripts.OnKeyDown(CT.keyboard(), "5")
CT.state().draft.spell = 139
GlassRaidFrames.ClickCastOptions.Refresh()
CT.ui.rank._scripts.OnClick(CT.ui.rank)
CT.ui.tabs.macro._scripts.OnClick(CT.ui.tabs.macro)
CT.ui.macroIcon._scripts.OnClick(CT.ui.macroIcon)
CT.ui.warning._scripts.OnClick(CT.ui.warning)
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

-- The group layout (#69): built, a party and a raid laid out, pets shown,
-- its mover dragged, its settings clicked.
GlassRaidFramesDB = nil
loadAddon({ layout = true })
local function roster() WoW.layoutHeaders(); WoW.fire("GROUP_ROSTER_UPDATE"); WoW.flushTimers() end
party(2); roster()
GlassRaidFrames.Settings.SetShowPets(true)
raid(8); roster()
GlassRaidFrames.Movers.Unlock()
local lm = GlassRaidFrames.Movers._test.mover()
lm._center = { 520, 390 }
lm._scripts.OnDragStart(lm); lm._scripts.OnUpdate(lm); lm._scripts.OnDragStop(lm)
GlassRaidFrames.Movers.Lock()
local LO = GlassRaidFrames.Options._test
LO.panel._scripts.OnShow(LO.panel)
for _, key in ipairs({ "groupLayout", "layoutHud" }) do LO.controls[key]._scripts.OnClick(LO.controls[key]) end
SlashCmdList.GLASSRAIDFRAMES("layout")
-- The tier preview (every button) and a glide run to its end.
for _, b in ipairs(LO.controls.preview) do b._scripts.OnClick(b) end
GlassRaidFrames.Settings.Preview(40); GlassRaidFrames.Settings.Preview(nil)
local L69 = GlassRaidFrames.Layout._test.L
L69.cells[1]._center, L69.cells[1]._width, L69.cells[1]._height = { 500, 300 }, 96, 60
L69.from = { [L69.cells[1]] = { 400, 270 } }
GlassRaidFrames.Layout.Apply()
WoW.tick(1)

-- Methods the dump cannot list: Blizzard_AuraContainer is a load-on-demand
-- Blizzard addon the dump did not capture, so neither its widget type nor
-- the methods of the buttons it creates are in the build's lists. Each is a
-- mixin method in Forever's own source (wow-ui-source, forever branch,
-- 70959; Blizzard_AuraContainer.xml:5 declares AuraContainer an intrinsic
-- Frame); GlassUnitFrames and DinoUnitFrames call them in game, and the
-- probe built these containers (FOREVER-PROBE items 1, 7 and 10). Keep this
-- list exact: anything else missing from the build still fails.
local SRC = "Interface/AddOns/Blizzard_AuraContainer/"
local allow = {
    ["AuraContainer:SetUnit"] = SRC .. "Blizzard_AuraContainer.lua:40 (AuraContainerSharedMixin)",
    ["AuraContainer:UpdateAllAuras"] = SRC .. "Blizzard_AuraContainer.lua:50 (AuraContainerSharedMixin)",
    ["AuraContainer:SetFlowLayoutAnchorPoint"] = SRC .. "Blizzard_AuraContainerFlowLayout.lua:19",
    ["AuraContainer:SetFlowLayoutGrowthDirection"] = SRC .. "Blizzard_AuraContainerFlowLayout.lua:31",
    ["AuraContainer:AddAuraGroup"] = SRC .. "Blizzard_CustomAuraContainer.lua:286 (CustomAuraContainerSharedMixin)",
    ["AuraContainer:GetAuraGroupFrame"] = SRC .. "Blizzard_CustomAuraContainer.lua:335",
    ["AuraContainer:GetAuraGroupFrameCount"] = SRC .. "Blizzard_CustomAuraContainer.lua:348",
    ["AuraContainer:SetAuraGroupEnabled"] = SRC .. "Blizzard_CustomAuraContainer.lua:363",
    ["AuraContainer:SetAuraGroupFilterString"] = SRC .. "Blizzard_CustomAuraContainer.lua:370",
    ["AuraContainer:SetAuraGroupMaxFrameCount"] = SRC .. "Blizzard_CustomAuraContainer.lua:381",
    ["AuraContainer:SetAuraGroupLayout"] = SRC .. "Blizzard_CustomAuraContainer.lua:409",
    ["AuraContainer:AddAuraSlot"] = SRC .. "Blizzard_CustomAuraContainer.lua:417",
    ["AuraContainer:GetAuraSlotFrame"] = SRC .. "Blizzard_CustomAuraContainer.lua:441",
    ["AuraContainer:SetAuraSlotEnabled"] = SRC .. "Blizzard_CustomAuraContainer.lua:452",
    ["AuraContainer:SetAuraSlotFilterString"] = SRC .. "Blizzard_CustomAuraContainer.lua:459",
    ["AuraContainer:SetAuraSlotCandidateFilters"] = SRC .. "Blizzard_CustomAuraContainer.lua:470",
    -- On the buttons the container creates (a Button in the tests).
    ["Button:SetApplicationCount"] = SRC .. "Blizzard_CustomAuraButton.lua:87 (CustomAuraButtonSharedMixin)",
    ["Button:SetDurationCooldown"] = SRC .. "Blizzard_CustomAuraButton.lua:159",
    ["Button:SetDurationText"] = SRC .. "Blizzard_CustomAuraButton.lua:178",
    ["Button:SetIcon"] = SRC .. "Blizzard_CustomAuraButton.lua:243",
}
-- Any other method on an AuraContainer must be a Frame method in the pinned
-- build (an intrinsic Frame); one that isn't stays unallowed, and fails.
local known = Kit.data("widgetMethods")
for name in pairs(WoW.methodsCalled) do
    local method = name:match("^AuraContainer:(%a+)$")
    if method and not allow[name] and known["Frame:" .. method] then
        allow[name] = "an AuraContainer is an intrinsic Frame (Frame:" .. method .. ")"
    end
end

local recorded = Kit.checkMethods({ allow = allow })
-- The floor: what the exercise records today (207), rounded down, so it can't quietly shrink.
check(recorded >= 200, "the exercise reached the frames, options pages, movers and layout (" .. recorded .. " recorded)")
done("test_methods")
