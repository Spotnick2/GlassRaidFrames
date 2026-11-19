-- wow_stubs.lua: GlassRaidFrames' WoW: Forever mock for Lua 5.1 unit tests,
-- on WowTestKit (tests/kit.pin; the kit's README is the reference).
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The kit holds the mechanics: check / eq / done, strict globals, secrets,
-- events checked against the pinned build, widgets that record every method
-- called (Kit.checkMethods), protected frames refusing WoW.PROTECTED in combat
-- (WoW.blocked), timers, print and its stray-| check, fire / tick. This file
-- adds GlassRaidFrames' own client APIs and, on top of the kit, what the
-- tests lean on (each with its reason below):
-- - INSECURE handlers: every script the addon sets or hooks runs with
--   WoW.secureCode off, whoever triggered it. Blizzard's header code setting a
--   child's unit fires the addon's hook as insecure code, as in the client;
--   only the client's own header code (WoW.useClientHeaders) runs secure: the
--   kit's refusals skip it, and it reads plain values where the addon would
--   get secrets.
-- - PROTECTED: the kit's list plus the 70532 API docs' IsProtectedFunction
--   methods this addon can reach (WoW.PROTECTED_METHODS, test_protected.lua);
--   the state-driver, unit-watch and override-binding APIs are refused to
--   insecure code in combat; the SecureHandler API errors in combat.
-- - COMBAT order: WoW.enterCombat() turns the lockdown on BEFORE
--   PLAYER_REGEN_DISABLED reaches a handler (Retail's order; FOREVER-PROBE
--   item 18.1 measures it here), WoW.leaveCombat() off before PLAYER_REGEN_ENABLED.
-- - SecureGroupHeaderTemplate: a model of the client's header (or, with
--   WoW.useClientHeaders, Forever's own SecureGroupHeaders.lua).

dofile("tests/kit.lua")
local Methods = WoW.Methods
local secrets = WoW.secrets
WoW.IsSecret = issecretvalue

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

table.insert(WoW.onReset, function()
    WoW.auraSecrecy = {}
    WoW.unitWatch = {}
    WoW.stateDrivers = {}   -- frame -> { state, values } (RegisterStateDriver)
    WoW.secureCode = false   -- true only while the client's own header code runs
    WoW.shift = false
    WoW.alt = false
    WoW.secretFields = {}     -- field -> true: that unit field comes back secret for every unit
    WoW.units = {}
    WoW.raid = nil
    WoW.masterLooter = false
    WoW.resting = false
    WoW.settings = {}
    WoW.atlases = { ["UI-HUD-UnitFrame-Player-Rest-Flipbook"] = true }
    WoW.loadedAddOns = {}
    WoW.rangeTruth = setmetatable({}, { __mode = "k" })
    rawset(_G, "EditModeManagerFrame", nil)
    WoW.CreateBlizzardFrames()
end)

-- Unit fields: exists, health, maxHealth, power, maxPower, powerToken, name,
-- class, player, reaction, dead, connected, visible, tapDenied,
-- casting = { name, channel, remaining }.
function WoW.SetUnit(token, t)
    if t == nil then WoW.units[token] = nil return end
    local u = { exists = true, health = 1000, maxHealth = 1000, power = 500, maxPower = 500,
                powerToken = "MANA", name = token, class = "WARRIOR", player = false, reaction = 5,
                dead = false, connected = true, visible = true, tapDenied = false,
                level = 10, classification = "normal", afk = false,
                leader = false, assistant = false, pvp = false, ffa = false, faction = "Horde" }
    for k, v in pairs(t) do u[k] = v end
    WoW.units[token] = u
end

local function unitField(token, field)
    local u = WoW.units[token]
    if not u then return nil end
    local v = u[field]
    -- Blizzard's own code (WoW.secureCode) reads plain values: a model, so
    -- stock Lua can stand in for the client's header sorting names it has
    -- made secret to the addon.
    if WoW.secretFields[field] and v ~= nil and not WoW.secureCode then return WoW.Secret(token .. "." .. field) end
    return v
end

--------------------------------------------------------------------------------
-- Widgets: what the tests lean on beyond the kit
--------------------------------------------------------------------------------

-- The client's own secure code (the header's) may change a protected frame
-- in combat: the kit's refusal skips it. The kit's Show, Hide, SetPoint,
-- ClearAllPoints, SetAllPoints and SetAttribute refuse again with the kit's
-- own check, which knows nothing of WoW.secureCode, so they are given again
-- below without it (the dispatch has already refused an insecure call; the
-- kit's MIGRATING, "Protected frames").
local kitRefused = WoW.refused
function WoW.refused(w, what)
    if WoW.secureCode then return false end
    return kitRefused(w, what)
end

-- The widget methods the client refuses to insecure code on a protected frame
-- in combat: those the addon or its templates can reach that the 70532
-- generated API docs flag IsProtectedFunction
-- (Blizzard_APIDocumentationGenerated/Simple{Frame,ScriptRegion,
-- ScriptRegionResizing,Button}APIDocumentation.lua; tests/test_protected.lua
-- checks each name against them). A modelled subset, not every flagged method.
-- Not flagged, so not here: RegisterForDrag, SetMovable, SetAlpha.
-- SetAttribute (in the kit's list) is not flagged, but measured to do nothing
-- in combat (PORTING-TBC-TO-FOREVER.md, "Secure click-casting works").
-- WowTestKit #83: the kit's WoW.PROTECTED holds what was measured; SetScale,
-- SetFrameStrata, SetFrameLevel and EnableMouse were measured refused on
-- 70959 (SetAlpha allowed). The rest of this list is the docs' flags.
WoW.PROTECTED_METHODS = { "Show", "Hide", "SetShown", "SetParent", "SetPoint", "SetAllPoints", "ClearAllPoints",
    "ClearPoint", "SetWidth", "SetHeight", "SetSize", "SetScale", "SetFrameStrata", "SetFrameLevel",
    "SetFixedFrameStrata", "SetFixedFrameLevel", "SetToplevel", "SetHitRectInsets", "SetClampedToScreen",
    "EnableMouse", "EnableMouseWheel", "EnableKeyboard", "Raise", "Lower", "SetID", "StartMoving", "StartSizing",
    "StopMovingOrSizing", "RegisterForClicks", "Enable", "Disable", "SetEnabled", "ClearAttribute", "ClearAttributes" }
for _, name in ipairs(WoW.PROTECTED_METHODS) do WoW.PROTECTED[name] = true end

-- The FrameXML APIs that set attributes on the protected
-- SecureStateDriverManager (SecureStateDriver.lua:8-50) and the protected
-- override-binding functions: an insecure call in combat is refused and
-- recorded; the client's own secure code (restricted handles) may still call
-- them. For the bindings this is the harness's assumption until FOREVER-PROBE
-- item 18.8 measures it.
local function secureApi(name)
    if WoW.combat and not WoW.secureCode then
        table.insert(WoW.blocked, name)
        return false
    end
    return true
end

-- The public SecureHandler API (SecureHandlers.lua:427-439): its API frame
-- checks InCombatLockdown() with no exemption for anyone, and errors.
local function handlerApi(name)
    if WoW.combat then
        table.insert(WoW.blocked, name)
        error("Cannot use SecureHandlers API during combat")
    end
end

-- The tests and the header model read a frame's attributes directly (w._attrs).
local kitCreateFrame = CreateFrame
function CreateFrame(...)
    local w = kitCreateFrame(...)
    w._attrs = w._attrs or {}
    return w
end

-- The secure templates the addon uses: explicitly protected (the kit makes
-- every frame above one protected too).
WoW.templates.SecureUnitButtonTemplate = function(w) w._protected = true end
local function header(w, pet)
    w._protected = true
    w._isHeader = true
    w._isPetHeader = pet
    if WoW.clientHeaders then WoW.clientHeaders.dress(w) end
end
WoW.templates.SecureGroupHeaderTemplate = function(w) header(w, false) end
WoW.templates.SecureGroupPetHeaderTemplate = function(w) header(w, true) end

-- Visibility. Show and Hide as the kit's (scripts down the tree, on a change),
-- without the kit's own refusal (above).
function Methods.Show(w) WoW.setShown(w, true) end
function Methods.Hide(w) WoW.setShown(w, false) end
-- A point already set is replaced, as the client does (a frame keeps one
-- anchor per point). WowTestKit #92: the kit's SetPoint adds every anchor.
function Methods.SetPoint(w, point, ...)
    for i = #w._points, 1, -1 do
        if w._points[i][1] == point then table.remove(w._points, i) end
    end
    table.insert(w._points, { point, ... })
end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.ClearPoint(w, point)
    for i = #w._points, 1, -1 do
        if w._points[i][1] == point then table.remove(w._points, i) end
    end
end
-- WowTestKit #89: GetNumPoints, SetScale, the drag state.
function Methods.GetNumPoints(w) return #w._points end
function Methods.SetScale(w, s) w._scale = s end
function Methods.StartMoving(w) w._moving = true end
function Methods.StartSizing(w) w._sizing = true end
function Methods.StopMovingOrSizing(w)
    w._moving = false
    w._points = { { "TOPLEFT", "UIParent", "BOTTOMLEFT", 111, 222 } }   -- where the drag "left" it
end
function Methods.ClearAttribute(w, k) w._attrs[k] = nil end
function Methods.ClearAttributes(w) w._attrs = {} end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end

-- Geometry. No real layout here: a test places a frame by its centre
-- (w._center = { x, y }); edges come from it and the frame's size. A frame
-- without one reads the kit's edges (w._left...).
local kitEdges = { GetLeft = Methods.GetLeft, GetRight = Methods.GetRight, GetTop = Methods.GetTop,
                   GetBottom = Methods.GetBottom, GetCenter = Methods.GetCenter }
local function edge(w, axis, sign, kit)
    if not (w._center and w._width and w._height) then return kitEdges[kit](w) end
    if axis == "x" then return w._center[1] + sign * w._width / 2 end
    return w._center[2] + sign * w._height / 2
end
function Methods.GetLeft(w) return edge(w, "x", -1, "GetLeft") end
function Methods.GetRight(w) return edge(w, "x", 1, "GetRight") end
function Methods.GetBottom(w) return edge(w, "y", -1, "GetBottom") end
function Methods.GetTop(w) return edge(w, "y", 1, "GetTop") end
function Methods.GetCenter(w)
    if w._center then return w._center[1], w._center[2] end
    return kitEdges.GetCenter(w)
end
-- GetRect for a frame placed CENTER-on-UIParent-CENTER (the grid): left and
-- bottom from UIParent's size, else from a test-set _center, else nil.
function Methods.GetRect(w)
    local p = w._points[#w._points]
    local W, H = w._width or 0, w._height or 0
    if p and p[1] == "CENTER" and p[2] == UIParent and p[3] == "CENTER" and (UIParent._width or 0) > 0 then
        return UIParent._width / 2 + p[4] - W / 2, UIParent._height / 2 + p[5] - H / 2, W, H
    end
    if w._center then return w._center[1] - W / 2, w._center[2] - H / 2, W, H end
    return nil
end

-- Scripts and events. An addon's handler is insecure code whoever calls it:
-- the client's secure header code setting a child's unit fires the addon's
-- OnAttributeChanged hook as insecure code, so a protected touch in it is
-- blocked in combat. Every handler the addon sets or hooks runs with
-- WoW.secureCode off, restored afterwards (after an error too: the raw pcall,
-- so an error the handler raises is passed on, not counted as swallowed).
local function insecure(fn)
    return function(...)
        local was = WoW.secureCode
        WoW.secureCode = false
        local ok, err = WoW.rawpcall(fn, ...)
        WoW.secureCode = was
        if not ok then error(err, 0) end
    end
end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn and insecure(fn) or nil end
function Methods.HookScript(w, name, fn)
    local old, hook = w._scripts[name], insecure(fn)
    w._scripts[name] = function(...) if old then old(...) end; hook(...) end
end
-- WowTestKit #79: the client refuses some registrations (returns false);
-- WoW.refuseEvents names them.
local kitRegisterEvent = Methods.RegisterEvent
function Methods.RegisterEvent(w, e)
    if WoW.KNOWN_EVENTS[e] and WoW.refuseEvents and WoW.refuseEvents[e] then return false end
    return kitRegisterEvent(w, e)
end

-- Secure attributes: the dispatch refuses an insecure call on a protected
-- frame in combat. With the client's header code, every attribute change is
-- heard, as in the client (the model below calls the unit hooks itself).
function Methods.SetAttribute(w, k, v)
    w._attrs[k] = v
    if WoW.clientHeaders and w._scripts.OnAttributeChanged then w._scripts.OnAttributeChanged(w, k, v) end
end

-- A rough wrap: about 7 units a character, 14 a line, at the string's width.
function Methods.GetStringHeight(fs)
    local w, text = fs._width, fs._text
    if type(text) ~= "string" or text == "" then return 0 end
    if not w or w <= 0 then return 14 end
    local lines = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + math.max(1, math.ceil(#line * 7 / w))
    end
    return lines * 14
end
function Methods.SetWordWrap(fs, on) fs._wordWrap = on end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
function Methods.SetTexCoord(t, ...) t._texCoord = { ... } end
-- WowTestKit #89: scroll frames and edit box focus.
function Methods.SetScrollChild(sf, child) sf._scrollChild = child end
function Methods.GetScrollChild(sf) return sf._scrollChild end
function Methods.SetVerticalScroll(sf, value)
    sf._verticalScroll = value
    if sf._scripts.OnVerticalScroll then sf._scripts.OnVerticalScroll(sf, value) end
end
function Methods.GetVerticalScroll(sf) return sf._verticalScroll or 0 end
function Methods.SetPropagateKeyboardInput(f, value)
    if WoW.combat then error("SetPropagateKeyboardInput must not be called in combat") end
    f._propagateKeyboard = value
end
function Methods.EnableKeyboard(f, value) f._keyboardEnabled = value end
-- Focus changes fire the edit box's focus scripts, as the client does.
function Methods.SetFocus(e)
    if e._focus then return end
    e._focus = true
    if e._scripts.OnEditFocusGained then e._scripts.OnEditFocusGained(e) end
end
function Methods.ClearFocus(e)
    if not e._focus then return end
    e._focus = false
    if e._scripts.OnEditFocusLost then e._scripts.OnEditFocusLost(e) end
end
function Methods.HasFocus(e) return e._focus == true end
function Methods.SetClipsChildren(w, v) w._clips = v end

-- StatusBar: takes values (secret or not) without inspecting them.
function Methods.SetMinMaxValues(b, lo, hi, interp) b._min, b._max, b._minMaxInterp = lo, hi, interp end
function Methods.GetMinMaxValues(b) return b._min, b._max end   -- WowTestKit #89
function Methods.SetTimerDuration(b, d, interp, dir) b._timer = { duration = d, interp = interp, dir = dir } end

-- PlayerModel (and the aura container: both take a unit).
local function seq(w, what) w._seq = w._seq or {}; table.insert(w._seq, what) end
function Methods.SetUnit(m, unit) m._modelUnit = unit; seq(m, "SetUnit"); return true end
function Methods.ClearModel(m) m._modelUnit = nil end

-- Blizzard's managed aura container (Blizzard_AuraContainer; not in the API
-- dump, shipped by DinoUF on Forever). It records its groups and, as the
-- client does, builds a first batch of 10 buttons at once, running
-- initializeFrame on each (FrameCreationBatchSize, CreateFrameBatch).
function Methods.AddAuraGroup(c, name, filter, spec)
    c._groups = c._groups or {}
    local g = { filter = filter, spec = spec, frames = {} }
    c._groups[name] = g
    seq(c, "AddAuraGroup")
    for i = 1, 10 do
        local frame = WoW.newWidget("Button", c)
        g.frames[i] = frame
        if spec and spec.initializeFrame then spec.initializeFrame(frame) end
    end
end
function Methods.UpdateAllAuras(c) c._refreshes = (c._refreshes or 0) + 1; seq(c, "UpdateAllAuras") end
-- Slots: the client builds the slot's one button at once and runs
-- initializeFrame on it (Blizzard_CustomAuraContainer.lua AddAuraSlot). Keys
-- can't be reused. Building in combat is recorded as blocked: the buttons
-- are locked while auras are secret.
function Methods.AddAuraSlot(c, key, filter, spec)
    c._slots = c._slots or {}
    assert(not c._slots[key], "aura slot '" .. tostring(key) .. "' already exists")
    if WoW.combat then table.insert(WoW.blocked, "AddAuraSlot") end
    local frame = WoW.newWidget("Button", c)
    c._slots[key] = { filter = filter, spec = spec, enabled = true, frame = frame }
    seq(c, "AddAuraSlot")
    if spec and spec.initializeFrame then spec.initializeFrame(frame) end
    return frame
end
local function slot(c, key) return assert(c._slots and c._slots[key], "no aura slot '" .. tostring(key) .. "'") end
function Methods.GetAuraSlotFrame(c, key) return c._slots and c._slots[key] and c._slots[key].frame end
function Methods.SetAuraSlotEnabled(c, key, on)
    assert(type(on) == "boolean", "enabled must be a boolean.")
    slot(c, key).enabled = on
end
function Methods.SetAuraSlotFilterString(c, key, filter) slot(c, key).filter = filter end
function Methods.SetAuraSlotCandidateFilters(c, key, cf) slot(c, key).spec.candidateFilters = cf end
local function group(c, key) return assert(c._groups and c._groups[key], "no aura group '" .. tostring(key) .. "'") end
function Methods.SetAuraGroupFilterString(c, key, filter) group(c, key).filter = filter end
function Methods.SetAuraGroupMaxFrameCount(c, key, n) group(c, key).spec.maxFrameCount = n end
function Methods.SetAuraGroupLayout(c, key, layout) group(c, key).spec.layout = layout end
function Methods.SetAuraGroupEnabled(c, key, on) group(c, key).enabled = on end
function Methods.GetAuraGroupFrameCount(c, key) return #group(c, key).frames end
function Methods.GetAuraGroupFrame(c, key, i) return group(c, key).frames[i] end
function Methods.SetFlowLayoutAnchorPoint(c, point) c._flowAnchor = point end
function Methods.SetFlowLayoutGrowthDirection(c, h, v) c._flowGrowth = { h, v } end
function Methods.SetIcon(b, t) b._icon = t end
function Methods.SetDurationCooldown(b, cd) b._cooldown = cd end
function Methods.SetDurationText(b, fs) b._durationText = fs end
function Methods.SetApplicationCount(b, fs) b._countText = fs end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

SlashCmdList = {}
Enum = {
    LuaCurveType = { Linear = 0 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    UITextureSliceMode = { Stretched = 0, Tiled = 1 },
    -- Not in the dump's enum list; the probe printed its names in game (70205).
    SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 },
}
-- Aura secrecy per spell ID (in the dump; WoW.auraSecrecy overrides).
-- Measured: every spell the defaults use is ContextuallySecret (item 10).
C_Secrets = {
    GetSpellAuraSecrecy = function(id) return WoW.auraSecrecy[id] or Enum.SecrecyLevel.ContextuallySecret end,
}
AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 } }   -- FrameXML (dump _G walk)
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetBuildInfo() return "1.60.1", "70338", "Sep 23 2026", 16001 end
function IsShiftKeyDown() return WoW.shift end
function IsAltKeyDown() return WoW.alt == true end
-- FrameXML's SecureStateDriver.lua: recorded, not evaluated; refused to
-- insecure code in combat (secureApi above). WowTestKit #77: the kit has no
-- state drivers.
function RegisterUnitWatch(frame) if secureApi("RegisterUnitWatch") then WoW.unitWatch[frame] = true end end
function UnregisterUnitWatch(frame)
    if secureApi("UnregisterUnitWatch") then WoW.unitWatch[frame] = nil; frame._unwatched = true end
end
function RegisterStateDriver(frame, state, values)
    if secureApi("RegisterStateDriver") then WoW.stateDrivers[frame] = { state, values } end
end
function UnregisterStateDriver(frame, state) if secureApi("UnregisterStateDriver") then WoW.stateDrivers[frame] = nil end end
function RegisterAttributeDriver(frame, attribute, values)
    if secureApi("RegisterAttributeDriver") then WoW.stateDrivers[frame] = { attribute, values } end
end
function UnregisterAttributeDriver(frame, attribute)
    if secureApi("UnregisterAttributeDriver") then WoW.stateDrivers[frame] = nil end
end
-- Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua:602. The snippet is
-- recorded, not run: a test runs it with its own handle stubs. In combat the
-- API errors for anyone (handlerApi above). WowTestKit #93: the kit's
-- SecureHandlerWrapScript wraps OnClick only, and the hover keys wrap OnEnter,
-- OnLeave and OnHide; the tests read these records (frame._wraps,
-- _executed, _refs).
function SecureHandlerWrapScript(frame, script, header, preBody, postBody)
    handlerApi("SecureHandlerWrapScript")
    assert(type(script) == "string" and type(preBody) == "string", "Invalid wrap")
    assert(header and header._protected, "Header frame must be explicitly protected")
    frame._wraps = frame._wraps or {}
    frame._wraps[script] = { header = header, pre = preBody, post = postBody }
end
function SecureHandlerExecute(frame, body)
    handlerApi("SecureHandlerExecute")
    assert(type(body) == "string", "Invalid snippet body")
    frame._executed = frame._executed or {}
    table.insert(frame._executed, body)
end
function SecureHandlerSetFrameRef(frame, label, ref)
    handlerApi("SecureHandlerSetFrameRef")
    frame._refs = frame._refs or {}
    frame._refs[label] = ref
end

-- In the dump's _G walk, protected: refused to insecure code in combat
-- (secureApi). ClearOverrideBindings drops every override binding `owner`
-- holds; SetOverrideBindingClick binds `key` to click the named button.
function ClearOverrideBindings(owner) secureApi("ClearOverrideBindings") end
function SetOverrideBindingClick(owner, isPriority, key, buttonName, mouseClick) secureApi("SetOverrideBindingClick") end
function SetOverrideBinding(owner, isPriority, key, command) secureApi("SetOverrideBinding") end

-- Blizzard's own unit frames: secure (protected) buttons under UIParent,
-- watched by the client. EditModeManagerFrame stays absent unless a test
-- opens Edit Mode with WoW.SetEditMode.
-- name -> unit the client watches it for (ComboFrame is not unit-watched).
local BLIZZARD_FRAMES = { { "PlayerFrame", "player" }, { "PetFrame", "pet" }, { "TargetFrame", "target" },
                          { "ComboFrame" }, { "TargetFrameToT", "targettarget" },
                          { "FocusFrame", "focus" }, { "FocusFrameToT", "focustarget" },
                          { "PlayerCastingBarFrame" } }
function WoW.CreateBlizzardFrames()
    for _, spec in ipairs(BLIZZARD_FRAMES) do
        local f = CreateFrame("Button", spec[1], UIParent, "SecureUnitButtonTemplate")
        f._blizzard = true
        f.healthbar = CreateFrame("StatusBar", nil, f)
        f.manabar = CreateFrame("StatusBar", nil, f)
        if spec[2] then
            f._attrs.unit = spec[2]
            WoW.unitWatch[f] = true
        end
        Methods.RegisterEvent(f, "PLAYER_ENTERING_WORLD")   -- Blizzard's call, not recorded
    end
end
function WoW.SetEditMode(open)
    if open and not rawget(_G, "EditModeManagerFrame") then
        rawset(_G, "EditModeManagerFrame", WoW.newWidget("Frame", UIParent, "EditModeManagerFrame"))
    end
    local em = rawget(_G, "EditModeManagerFrame")
    if em then em._shown = open end
end

C_ClassColor = { GetClassColor = function(cls)
    if type(cls) ~= "string" then error("bad class") end
    return { r = 0.53, g = 0.53, b = 0.93 }
end }

C_CurveUtil = { CreateCurve = function()
    local c = { points = {} }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, y) table.insert(self.points, { x, y }) end
    return c
end, CreateColorCurve = function()
    local c = { points = {}, color = true }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, col) table.insert(self.points, { x, col }) end
    return c
end }
-- A colour-curve result: a colour object; its components secret when the input was.
local function curveColor(col, secret)
    return { GetRGBA = function()
        if secret then return WoW.Secret("r"), WoW.Secret("g"), WoW.Secret("b"), WoW.Secret("a") end
        return col.r, col.g, col.b, col.a
    end }
end
-- Step evaluation: the last point at or below x. NOTE: a 0/0 unit is modelled
-- as fraction 0 here; what the real client returns for max 0 is UNMEASURED
-- (#27's in-game check), so tests built on it only prove our side.
local function evalColor(curve, x)
    local col = curve.points[1][2]
    for _, pt in ipairs(curve.points) do if x >= pt[1] then col = pt[2] end end
    return col
end

function UnitExists(u) return WoW.units[u] ~= nil end
function UnitGUID(u)
    local un = WoW.units[u]
    if not un then return nil end
    if WoW.secretFields.guid and not WoW.secureCode then return WoW.Secret(u .. ".guid") end
    return un.guid or ("GUID-" .. tostring(un.name))
end
function UnitHealth(u) return unitField(u, "health") end
function UnitHealthMax(u) return unitField(u, "maxHealth") end
-- Power by type: 0 = mana (fields mana / maxMana, else the display power),
-- 4 = combo points (field combo, max 5); none = the display power.
local function powerFields(u, t)
    if t == 4 then return "combo", nil end
    if t == 0 and WoW.units[u] and WoW.units[u].mana ~= nil then return "mana", "maxMana" end
    return "power", "maxPower"
end
function UnitPower(u, t) return unitField(u, (powerFields(u, t))) end
function UnitPowerMax(u, t)
    local _, mf = powerFields(u, t)
    if mf == nil then return WoW.units[u] and 5 or nil end
    return unitField(u, mf)
end
function UnitPowerType(u) return 0, unitField(u, "powerToken") end
function UnitHealthPercent(u, predicted, curve)
    local h, m = unitField(u, "health"), unitField(u, "maxHealth")
    if h == nil then return nil end
    if secrets[h] or secrets[m] then return WoW.Secret(u .. ".healthPercent") end
    local frac = (m and m > 0) and h / m or 0
    local p1, p2 = curve.points[1], curve.points[2]
    return p1[2] + (p2[2] - p1[2]) * frac
end
function AbbreviateNumbers(n)
    if secrets[n] then return WoW.Secret("abbreviated") end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end
-- UnitName returns the first name, then the surname where a realm would be
-- (measured; CLAUDE.md). The unit field `name` holds "First Surname"; both
-- returns are secret when the field is (each a secret of its own), the
-- surname nil for a unit without one.
function UnitName(u)
    local un = WoW.units[u]
    if not un then return nil end
    local first, sur = tostring(un.name):match("^(%S+)%s+(.+)$")
    if not first then first = un.name end
    if WoW.secretFields.name and not WoW.secureCode then
        return WoW.Secret(u .. ".name"), sur and WoW.Secret(u .. ".surname") or nil
    end
    return first, sur
end
-- Blizzard's GetUnitName is Lua on Forever (Camelot NameUtil.lua:4-12): it
-- truth-tests and concatenates UnitName's returns, so a secret surname throws
-- here as in the client (Lua can't make the truth test throw; the
-- concatenation does). The addon builds the name itself (Frames.FullName).
function GetUnitName(u)
    local name, surname = UnitName(u)
    if surname then return name .. " " .. surname end
    return name
end
function UnitClass(u) return unitField(u, "name"), unitField(u, "class"), 1 end
function UnitIsPlayer(u) return unitField(u, "player") end
function UnitReaction(u) return unitField(u, "reaction") end
function UnitIsConnected(u) return unitField(u, "connected") end
function UnitIsDeadOrGhost(u) return unitField(u, "dead") end
function UnitIsTapDenied(u) return unitField(u, "tapDenied") end
function UnitIsVisible(u) return unitField(u, "visible") end
function UnitLevel(u) return unitField(u, "level") end
function UnitClassification(u) return unitField(u, "classification") end
function UnitIsAFK(u) return unitField(u, "afk") end
function UnitPowerPercent(u, powerType, unmodified, curve)
    local pf, mf = powerFields(u, powerType)
    local p, m = unitField(u, pf), nil
    if pf == "combo" then m = 5 else m = unitField(u, mf) end
    if powerType == 4 and p == nil and WoW.units[u] then p = 0 end
    if p == nil then return nil end
    if curve.color then
        if secrets[p] or secrets[m] then
            -- The stub still knows the real numbers behind the fields it made secret.
            local rp, rm = WoW.units[u][pf] or 0, mf and WoW.units[u][mf] or 5
            return curveColor(evalColor(curve, (rm and rm > 0 and not secrets[rp]) and rp / rm or 0), true)
        end
        return curveColor(evalColor(curve, (m and m > 0) and p / m or 0), false)
    end
    if secrets[p] or secrets[m] then return WoW.Secret(u .. ".powerPercent") end
    local frac = (m and m > 0) and p / m or 0
    local p1, p2 = curve.points[1], curve.points[2]
    return p1[2] + (p2[2] - p1[2]) * frac
end
-- Indicators. Unit fields: raidTarget (index or nil), leader, assistant, pvp,
-- ffa, faction. WoW.masterLooter: the player is master looter.
function GetRaidTargetIndex(u) return unitField(u, "raidTarget") end
function SetRaidTargetIconTexture(tex, index) tex._raidIndex = index end
function Methods.SetSpriteSheetCell(t, cell, rows, cols) t._raidIndex, t._sheet = cell, { rows, cols } end
function UnitIsGroupLeader(u) return unitField(u, "leader") end
function UnitIsGroupAssistant(u) return unitField(u, "assistant") end
function UnitIsPVP(u) return unitField(u, "pvp") end
function UnitIsPVPFreeForAll(u) return unitField(u, "ffa") end
function UnitFactionGroup(u) return unitField(u, "faction") end
function IsMasterLooter() return WoW.masterLooter == true end
function IsResting() return WoW.resting == true end
-- #28. Unit fields: threat (the player's UnitThreatSituation on that mob,
-- nil = not on its list), ownThreat (UnitThreatSituation(unit)), combat.
function UnitThreatSituation(u, mob)
    if mob == nil then return unitField(u, "ownThreat") end
    if u ~= "player" then return nil end   -- the `threat` field models the player's threat only
    return unitField(mob, "threat")
end
function UnitAffectingCombat(u) return unitField(u, "combat") end
-- Hunter pet happiness. WoW.petHappiness (1-3 or nil), WoW.hunterPet.
C_PetInfo = { GetPetHappiness = function()
    if WoW.secretFields.happiness and WoW.petHappiness then return WoW.Secret("happiness") end
    return WoW.petHappiness, 0, 0
end }
function HasPetUI() return WoW.units.pet ~= nil, WoW.hunterPet == true end
-- SecretWhenUnitComparisonRestricted in the docs: secret with
-- WoW.secretFields.isUnit (for an existing unit, to insecure code).
function UnitIsUnit(a, b)
    local ua, ub = WoW.units[a], WoW.units[b]
    if ua ~= nil and WoW.secretFields.isUnit and not WoW.secureCode then return WoW.Secret(a .. "=" .. b) end
    return ua ~= nil and ua == ub
end
-- Retail's Settings framework (names from the dump's _G walk; signatures as
-- Priestly uses them on Forever). WoW.settings records what the addon did.
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name }
        function c:GetID() return 4242 end
        WoW.settings.canvas = c
        return c
    end,
    RegisterAddOnCategory = function(c) WoW.settings.addon = c end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        local c = { frame = frame, name = name, parent = parent }
        WoW.settings.subcategories = WoW.settings.subcategories or {}
        table.insert(WoW.settings.subcategories, c)
        return c
    end,
    OpenToCategory = function(id) WoW.settings.opened = id end,
}
C_Texture = { GetAtlasExists = function(name) return WoW.atlases[name] == true end }
C_AddOns = {
    IsAddOnLoaded = function(name) return WoW.loadedAddOns[name] == true, WoW.loadedAddOns[name] == true end,
    LoadAddOn = function(name) WoW.loadedAddOns[name] = true; return true end,
    -- WoW.addonVersion is the TOC's Version field (nil = unreadable).
    GetAddOnMetadata = function(name, field)
        if name == "GlassRaidFrames" and field == "Version" then return WoW.addonVersion end
        return nil
    end,
}

-- Raid roster: WoW.raid = { [unit] = { index = n, subgroup = g } } while in a raid.
function IsInRaid() return WoW.raid ~= nil end
local function partyCount()
    local n = 0
    for i = 1, 4 do if WoW.units["party" .. i] then n = n + 1 end end
    return n
end
function IsInGroup() return WoW.raid ~= nil or partyCount() > 0 end
-- A raid's members, or the party with you (0 alone).
function GetNumGroupMembers()
    if WoW.raid then
        local n = 0
        for _ in pairs(WoW.raid) do n = n + 1 end
        return n
    end
    local n = partyCount()
    return n > 0 and n + 1 or 0
end
function GetNumSubgroupMembers() return partyCount() end
function UnitInRaid(u) return WoW.raid and WoW.raid[u] and WoW.raid[u].index or nil end
function GetRaidRosterInfo(index)
    for u, r in pairs(WoW.raid or {}) do
        if r.index == index then return unitField(u, "name"), 0, r.subgroup end
    end
end

-- Unit field `role` (UnitGroupRolesAssigned; plain on Forever, measured).
function UnitGroupRolesAssigned(u) return unitField(u, "role") or "NONE" end
-- Range is SECRET on Forever even out of combat (measured): the stub always
-- returns secrets, so any Lua test of it throws. Unit field `inRange` is the
-- truth the client would act on (read by SetAlphaFromBoolean below).
function UnitInRange(u)
    if not WoW.units[u] then return false, false end
    local s = WoW.Secret(u .. ".inRange")
    -- Your own unit is "unchecked": inRange reads false (EllesmereUI, on Forever).
    WoW.rangeTruth[s] = u ~= "player" and u ~= "pet" and WoW.units[u].inRange ~= false
    return s, WoW.Secret(u .. ".checkedRange")
end
function Methods.SetAlphaFromBoolean(w, v, yes, no)
    local truth = v
    if secrets[v] then truth = WoW.rangeTruth[v] end
    w._alpha = truth and yes or no
    w._alphaFromBoolean = true
end

--------------------------------------------------------------------------------
-- SecureGroupHeaderTemplate, as far as the addon relies on it (measured in
-- the probe, FOREVER-PROBE item 1): children are created from the "template"
-- attribute while the header is shown with startingIndex <= 0 (1 - startingIndex
-- of them), exposed as "child<n>" attributes; WoW.layoutHeaders() assigns units
-- (the client does it on roster changes, in combat too) and fires each child's
-- OnAttributeChanged("unit", ...) when its unit changes.
-- The child template's size is its XML <Size> (harness.lua's xmlTemplates).
--------------------------------------------------------------------------------

-- Pets as Forever's SecureGroupPetHeader_Update finds them (GetPetUnit):
-- raidpetN in a raid; the player's pet and partypetN otherwise.
local function petUnits(h)
    local a, list = h._attrs, {}
    if WoW.raid then
        if not a.showRaid then return list end
        local byIndex = {}
        for u, r in pairs(WoW.raid) do
            local pet = "raidpet" .. r.index
            if WoW.units[pet] then byIndex[#byIndex + 1] = { r.index, pet } end
        end
        table.sort(byIndex, function(x, y) return x[1] < y[1] end)
        for _, e in ipairs(byIndex) do list[#list + 1] = e[2] end
        return list
    end
    local grouped = false
    for i = 1, 4 do if WoW.units["party" .. i] then grouped = true end end
    if not grouped then
        -- Solo: only with showSolo (SecureGroupPetHeader_Update's solo branch).
        if a.showSolo and WoW.units.pet then list[1] = "pet" end
        return list
    end
    if not a.showParty then return list end
    if a.showPlayer and WoW.units.pet then list[#list + 1] = "pet" end
    for i = 1, 4 do
        if WoW.units["partypet" .. i] then list[#list + 1] = "partypet" .. i end
    end
    return list
end

local function headerUnits(h)
    if h._isPetHeader then return petUnits(h) end
    local a = h._attrs
    local list = {}
    if WoW.raid and a.showRaid then
        local want = {}
        for g in tostring(a.groupFilter or "1,2,3,4,5,6,7,8"):gmatch("%d+") do want[tonumber(g)] = true end
        local byIndex = {}
        for u, r in pairs(WoW.raid) do
            if want[r.subgroup] and WoW.units[u] then byIndex[#byIndex + 1] = { r.index, u } end
        end
        table.sort(byIndex, function(x, y) return x[1] < y[1] end)
        for _, e in ipairs(byIndex) do list[#list + 1] = e[2] end
    elseif not WoW.raid then
        local party = {}
        for i = 1, 4 do if WoW.units["party" .. i] then party[#party + 1] = "party" .. i end end
        if (#party > 0 and a.showParty) or a.showSolo then
            if a.showPlayer or #party == 0 then list[1] = "player" end
            for _, u in ipairs(party) do list[#list + 1] = u end
        end
    end
    return list
end

-- The client's header (or unit watch) shows or hides a frame securely: its
-- OnShow/OnHide fire, the addon's hooks among them (insecure, see HookScript).
local function secureShown(w, shown) WoW.setShown(w, shown) end

function WoW.layoutHeader(h)
    if WoW.clientHeaders then return WoW.clientHeaders.update(h) end
    local list = headerUnits(h)
    local i = 1
    while h._attrs["child" .. i] do
        local child = h._attrs["child" .. i]
        local unit = list[i]
        local old = child._attrs.unit
        -- As configureChildren does (SecureGroupHeaders.lua:213-237): a shown
        -- child gets its unit, then Show; a spare is hidden, then its unit cleared.
        if unit == nil then secureShown(child, false) end
        child._attrs.unit = unit      -- secure header code: never blocked
        if old ~= unit and child._scripts.OnAttributeChanged then
            child._scripts.OnAttributeChanged(child, "unit", unit)
        end
        if unit ~= nil then secureShown(child, true) end
        i = i + 1
    end
end

function WoW.layoutHeaders()
    for _, w in ipairs(WoW.frames) do
        if w._isHeader and w._shown then WoW.layoutHeader(w) end
    end
end

local plainShow = Methods.Show
function Methods.Show(w)
    plainShow(w)
    if not w._isHeader or WoW.clientHeaders then return end   -- the client's: its OnShow updates
    local start = w._attrs.startingIndex
    if type(start) == "number" and start <= 0 then
        local want = 1 - start
        local n = 0
        while w._attrs["child" .. (n + 1)] do n = n + 1 end
        for i = n + 1, want do
            w._attrs["child" .. i] = CreateFrame(w._attrs.templateType or "Button", nil, w, w._attrs.template)
        end
    end
    WoW.layoutHeader(w)
end

-- Blizzard's own header code (#69's harness): after
-- WoW.useClientHeaders(file), header templates run Forever's
-- SecureGroupHeaders.lua instead of the model above. Created hidden, as the
-- template is; laid out on OnShow, on attribute changes, and by
-- WoW.layoutHeaders() (the roster events). Secure code: never blocked.
function WoW.useClientHeaders(file)
    local chunk = loadfile(file)
    if not chunk then return false end
    -- What the file reads, at load and while it lays out.
    rawset(string, "trim", function(v) return (v:gsub("^%s+", ""):gsub("%s+$", "")) end)
    rawset(table, "wipe", function(t) for k in pairs(t) do t[k] = nil end return t end)
    rawset(_G, "strsplit", function(sep, v)
        local out = {}
        for piece in (v .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end)
    rawset(_G, "GetFrameHandle", function(f) return f end)
    rawset(_G, "GetManagedEnvironment", function() return {} end)
    rawset(_G, "CallRestrictedClosure", function() error("the harness runs no snippets") end)
    rawset(_G, "scrub", function(...) return ... end)
    rawset(_G, "CLASS_SORT_ORDER", {})
    rawset(_G, "GetPartyAssignment", function() return false end)
    chunk()
    local function secure(fn, ...)
        local was = WoW.secureCode
        WoW.secureCode = true
        local ok, err = WoW.rawpcall(fn, ...)
        WoW.secureCode = was
        if not ok then error(err, 0) end
    end
    WoW.clientHeaders = {
        dress = function(h)
            local pet = h._isPetHeader
            local update = pet and SecureGroupPetHeader_Update or SecureGroupHeader_Update
            local changed = pet and SecureGroupPetHeader_OnAttributeChanged or SecureGroupHeader_OnAttributeChanged
            h._shown = false
            h._scripts.OnShow = function(self) secure(update, self) end
            h._scripts.OnAttributeChanged = function(self, k, v) secure(changed, self, k, v) end
        end,
        update = function(h)
            if not Methods.IsVisible(h) then return end
            secure(h._isPetHeader and SecureGroupPetHeader_Update or SecureGroupHeader_Update, h)
        end,
    }
    return true
end

local function durationFor(u, channel)
    local un = WoW.units[u]
    local c = un and un.casting
    if not c or (c.channel == true) ~= channel then return nil end
    return { GetRemainingDuration = function()
        if WoW.secretFields.castRemaining then return WoW.Secret("remaining") end
        return c.remaining or 1.25
    end }
end
function UnitCastingDuration(u) return durationFor(u, false) end

function UnitChannelDuration(u) return durationFor(u, true) end

-- Heal prediction: unit field `incoming` (all healers).
function CreateUnitHealPredictionCalculator()
    local c = { clamp = nil }
    function c:SetIncomingHealClampMode(m) self.clamp = m end
    function c:SetIncomingHealOverflowPercent(p) self.overflow = p end
    function c:GetIncomingHeals()
        return self._incoming, 0, self._incoming, false
    end
    function c:GetMaximumHealth() return self._max end
    return c
end
function UnitGetDetailedHealPrediction(u, healer, calc)
    calc._incoming = unitField(u, "incoming") or 0
    calc._max = unitField(u, "maxHealth")
end
function UnitCastingInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not c or c.channel then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    return c.name
end
function UnitChannelInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not (c and c.channel) then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    return c.name
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Combat as the client orders it (Retail; FOREVER-PROBE item 18.1 measures
-- it on Forever): the lockdown is on before PLAYER_REGEN_DISABLED reaches a
-- handler, and off before PLAYER_REGEN_ENABLED does.
function WoW.enterCombat() WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED") end
function WoW.leaveCombat() WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED") end

-- Every event any frame registered, fired for every modelled unit and for
-- "player", sorted. WowTestKit #94: the kit fires a plain registration once
-- with no payload, and the engine registers its unit events with
-- RegisterEvent (one frame for every token, Engine.lua), so its handler would
-- get no unit and paint nothing: the combat and secrets tests' "everything
-- fires" would no longer reach the painters. On the client a plainly
-- registered unit event arrives once per unit, with that unit.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
        for e in pairs(w._unitEvents) do seen[e] = true end
    end
    local list, units = {}, {}
    for e in pairs(seen) do list[#list + 1] = e end
    for u in pairs(WoW.units) do units[#units + 1] = u end
    table.sort(list); table.sort(units)
    for _, e in ipairs(list) do
        for _, u in ipairs(units) do WoW.fire(e, u) end
        WoW.fire(e, "player")
    end
    return list
end

-- The client's unit watch: show/hide watched frames by UnitExists.
function WoW.applyUnitWatch()
    for frame in pairs(WoW.unitWatch) do
        secureShown(frame, WoW.units[frame._attrs.unit] ~= nil)
    end
end

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassRaidFrames = true, GlassRaidFramesDB = true, GlassRaidFramesCharDB = true, LibStub = true })
