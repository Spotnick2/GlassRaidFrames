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

-- A spell's localized name / rank text from its ID, or nil (unknown, secret
-- or empty). Every name the addon shows or casts comes through here.
local function plainString(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "string" and v ~= "" and not API.IsSecret(v) then return v end
    return nil
end
function API.SpellName(id) return plainString(C_Spell and C_Spell.GetSpellName, id) end
function API.SpellSubtext(id) return plainString(C_Spell and C_Spell.GetSpellSubtext, id) end
function API.SpellTexture(id)
    local ok, tex = pcall(C_Spell.GetSpellTexture, id)
    if ok and not API.IsSecret(tex) then return tex end
    return nil
end

-- Every LEARNED, active spell in the player's spellbook, as { spellID, name }
-- in spellbook order (lowest rank first). Skips future spells, passives and
-- off-spec entries, as Blizzard's own spellbook does
-- (Blizzard_PlayerSpellsFrame.lua). Empty when the API is absent.
function API.SpellBookSpells()
    local out = {}
    local SB = rawget(_G, "C_SpellBook")
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
        return out
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    local okC, n = pcall(SB.GetNumSpellBookSkillLines)
    if not (okC and type(n) == "number") then return out end
    for line = 1, n do
        local okL, li = pcall(SB.GetSpellBookSkillLineInfo, line)
        if okL and type(li) == "table" and li.itemIndexOffset and li.numSpellBookItems then
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local okB, item = pcall(SB.GetSpellBookItemInfo, i, bank)
                if okB and type(item) == "table" and item.spellID and type(item.name) == "string"
                    and (future == nil or item.itemType ~= future) and not item.isPassive and not item.isOffSpec then
                    out[#out + 1] = { spellID = item.spellID, name = item.name }
                end
            end
        end
    end
    return out
end

-- Whether the player has learned this exact spell ID (a rank's own ID
-- counts: measured known=true for each learned Shadow Bolt rank). A name
-- alone proves nothing: C_Spell.GetSpellName answers for unlearned spells.
-- Blizzard's own click-binding UI drops spells failing IsSpellInSpellBook.
function API.SpellKnown(id)
    local SB = rawget(_G, "C_SpellBook")
    if not SB then return false end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if SB.IsSpellKnown then
        local ok, known = pcall(SB.IsSpellKnown, id, bank)
        if ok and not API.IsSecret(known) then return known == true end
    end
    if SB.IsSpellInSpellBook then
        local ok, inBook = pcall(SB.IsSpellInSpellBook, id, bank, false)
        if ok and not API.IsSecret(inBook) then return inBook == true end
    end
    return false
end

-- Blizzard's click-binding profile (a list), or nil when absent.
function API.ClickBindingProfile()
    local CB = rawget(_G, "C_ClickBindings")
    if not (CB and CB.GetProfileInfo) then return nil end
    local ok, profile = pcall(CB.GetProfileInfo)
    if ok and type(profile) == "table" then return profile end
    return nil
end

-- Fire a callback event on Retail's EventRegistry (usable on 70009, probe
-- item 9) for other addons; false when it's absent. Never throws.
function API.TriggerEvent(event, ...)
    local reg = rawget(_G, "EventRegistry")
    if not (reg and reg.TriggerEvent) then return false end
    local ok, err = pcall(reg.TriggerEvent, reg, event, ...)
    if not ok then API.Fail("event " .. event, err) end
    return ok
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

-- Heal prediction, as GlassUnitFrames measured it (its Compat.lua): one
-- calculator per frame, clamped to maximum health where the client offers
-- the mode. nil when the API is absent.
function API.NewHealCalculator()
    local create = rawget(_G, "CreateUnitHealPredictionCalculator")
    if not (create and rawget(_G, "UnitGetDetailedHealPrediction")) then return nil end
    local ok, calc = pcall(create)
    if not ok or not calc then return nil end
    -- DinoUF (incheal.lua, v2.3): on Forever the bar rendered EMPTY until the
    -- overflow percent was set to 1.
    if calc.SetIncomingHealOverflowPercent then pcall(calc.SetIncomingHealOverflowPercent, calc, 1) end
    local modes = Enum and Enum.UnitIncomingHealClampMode
    if modes and modes.MaximumHealth ~= nil and calc.SetIncomingHealClampMode then
        pcall(calc.SetIncomingHealClampMode, calc, modes.MaximumHealth)
    end
    return calc
end

-- (all incoming heals, maximum health), both as the client returns them
-- (secret). GetIncomingHeals' FIRST return is the all-healer total.
function API.IncomingHeals(unit, calc)
    UnitGetDetailedHealPrediction(unit, "player", calc)
    local incoming = calc:GetIncomingHeals()
    return incoming, calc:GetMaximumHealth()
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
