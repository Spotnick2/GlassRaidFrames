-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method
-- walk, falling back to the documented functions.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSRF_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"
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
for _, cmd in ipairs({ "", "failures", "version" }) do SlashCmdList.GLASSRAIDFRAMES(cmd) end

-- Methods the dump cannot list: Blizzard_AuraContainer is a load-on-demand
-- Blizzard addon the dump did not capture. Evidence they exist on Forever:
-- GlassUnitFrames and DinoUnitFrames call every one of them in game, and the
-- probe built these containers on 70009 (FOREVER-PROBE items 1 and 7).
-- Keep this list exact: anything else missing from the dump still fails.
local AURA_CONTAINER_API = {
    ["AuraContainer:AddAuraGroup"] = true, ["AuraContainer:UpdateAllAuras"] = true,
    ["AuraContainer:SetUnit"] = true,
    ["Button:SetIcon"] = true,   -- on the buttons the container creates
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
