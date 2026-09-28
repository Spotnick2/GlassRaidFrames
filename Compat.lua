-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassRaidFrames.API. Nothing is injected into _G.
--
-- Lifted in part from GlassUnitFrames' Compat.lua (same measured rules); only
-- what the group frames use is here.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = {}
GRF.API = API

-- The build the notes in docs/FOREVER-PROBE.md were measured on. Bump only
-- after re-measuring in game; tests/test_toc.lua pins the same literal.
GRF.MEASURED_ON_BUILD = "1.60.1.70009"

function API.Print(msg)
    print("|cff7fd4ffGlassRF|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (StatusBar, SetFormattedText, SetText) but never compared, added,
-- concatenated, tostring'd or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent/RegisterUnitEvent throw on an unknown name and return false
-- on a refusal. Both count as failure, and every failure is reported: a
-- silently missing handler is the bug this exists to prevent.
GRF.eventFailures = {}

local function report(name, why)
    table.insert(GRF.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

function API.RegisterUnitEvents(frame, events, unit)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterUnitEvent, frame, name, unit)
        if not ok then report(name .. "/" .. unit, tostring(registered))
        elseif registered == false then report(name .. "/" .. unit, "refused") end
    end
end

-- Unit buttons register the UP edge only ("AnyUp"). The porting guide's
-- both-edges rule was measured on SecureActionButtonTemplate, whose handler
-- picks one edge; the SecureUnitButtonTemplate handler dispatches on every
-- registered edge (measured, 70009). Never set "typerelease" either.
function API.UnitButtonClicks()
    return "AnyUp"
end

-- 0..1 fraction -> 0..100, evaluated by the client so a secret health value
-- never meets Lua arithmetic. Built once; nil if the curve API is missing.
local percentCurve
function API.PercentCurve()
    if percentCurve == nil and C_CurveUtil and C_CurveUtil.CreateCurve then
        local curve = C_CurveUtil.CreateCurve()
        local types = Enum and Enum.LuaCurveType
        if types and types.Linear then curve:SetType(types.Linear) end
        curve:AddPoint(0, 0)
        curve:AddPoint(1, 100)
        percentCurve = curve
    end
    return percentCurve or nil
end

-- Health percent (0..100) as whatever the client returns: possibly secret.
function API.HealthPercent(unit)
    local curve = API.PercentCurve()
    if not (curve and UnitHealthPercent) then return nil end
    return UnitHealthPercent(unit, true, curve)
end

-- CreateFrame with a template that may be missing on this client. A missing
-- template doesn't throw, it returns a bare frame (Priestly, GlassUnitFrames),
-- so `proof` names a field the template would have made. Returns the frame
-- and whether the template really applied.
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

-- The one place failures are recorded (first error per key), read by
-- /grf failures and the tests.
GRF.paintFailures = GRF.paintFailures or {}
function API.Fail(key, err)
    if GRF.paintFailures[key] == nil then GRF.paintFailures[key] = tostring(err) end
end

-- Load a load-on-demand Blizzard addon. Returns true, or false and the reason
-- the client gave (e.g. "DISABLED", "MISSING").
function API.LoadBlizzardAddOn(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return false, "no C_AddOns" end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok and loaded then return true end
    local okL, done, reason = pcall(C_AddOns.LoadAddOn, name)
    if okL and done then return true end
    return false, okL and tostring(reason) or tostring(done)
end

-- Whether a texture atlas exists on this client, asked once per name (it
-- can't change during a session). False when C_Texture is absent.
local atlasKnown = {}
function API.AtlasExists(name)
    if atlasKnown[name] == nil then
        local tex = rawget(_G, "C_Texture")
        local ok, v = false, nil
        if tex and tex.GetAtlasExists then ok, v = pcall(tex.GetAtlasExists, name) end
        atlasKnown[name] = ok and not API.IsSecret(v) and v == true
    end
    return atlasKnown[name]
end

-- Class colour from the documented API (RAID_CLASS_COLORS is a FrameXML
-- table the dump cannot confirm). Returns r, g, b or nil.
function API.ClassColor(classFile)
    if API.IsSecret(classFile) then return nil end   -- before ANY test of it
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local c = C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return nil
end
