-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - PROTECTED frames: secure-template frames and their ancestors. Touching one
--   under InCombatLockdown() is recorded in WoW.blocked instead of applied.
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare.
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSRF_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70338.md"

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end
function WoW.IsSecret(v) return secrets[v] ~= nil end

--------------------------------------------------------------------------------
-- Known events (from the dump when present)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        -- No dump (CI): the checked-in list generated from it, so validation
        -- stays exactly as strict. test_toc fails if the two ever drift.
        local fixture = io.open("tests/events-70338.txt", "r")
        assert(fixture, "tests/events-70338.txt missing: event validation needs the dump or the fixture")
        for line in fixture:lines() do
            local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
            if name then WoW.KNOWN_EVENTS[name] = true end
        end
        fixture:close()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.fontStrings = {}
    WoW.auraSecrecy = {}
    WoW.blocked = {}
    WoW.chat = {}
    WoW.timers = {}
    WoW.unitWatch = {}
    WoW.stateDrivers = {}   -- frame -> { state, values } (RegisterStateDriver)
    WoW.methodsCalled = {}
    WoW.combat = false
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
    WoW.templateSizes = WoW.templateSizes or {}
    -- XML templates that inherit a secure one (their frames are protected).
    WoW.secureTemplates = WoW.secureTemplates or {}
    rawset(_G, "EditModeManagerFrame", nil)
    if UIParent then WoW.CreateBlizzardFrames() end
end

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
    if WoW.secretFields[field] and v ~= nil then return WoW.Secret(token .. "." .. field) end
    return v
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local function isProtected(w)
    return w._protected == true
end

local function guard(w, what)
    if WoW.combat and isProtected(w) and not WoW.secureCode then   -- the client's own secure code may
        table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what)
        return false
    end
    return true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    local w = setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                             _attrs = {}, _scripts = {}, _events = {}, _unitEvents = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name }, widgetMT)
    return w
end

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    -- A template's <Size> (the client sizes a frame from its template).
    local size = template and WoW.templateSizes and WoW.templateSizes[template]
    if size then w._width, w._height = size[1], size[2] end
    if template == "SecureGroupHeaderTemplate" or template == "SecureGroupPetHeaderTemplate" then
        w._isHeader = true
        w._isPetHeader = template == "SecureGroupPetHeaderTemplate"
        if WoW.clientHeaders then WoW.clientHeaders.dress(w) end
    end
    if template and (template:find("Secure") or WoW.secureTemplates[template]) then
        local p = w
        while p do p._protected = true; p = p._parent end
    end
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    return w
end

-- Visibility / layout (guarded on protected frames).
function Methods.Show(w)
    if not guard(w, "Show") then return end
    local was = w._shown
    w._shown = true
    if not was and w._scripts.OnShow then w._scripts.OnShow(w) end   -- only on a hidden->shown change, as the client
end
function Methods.Hide(w)
    if not guard(w, "Hide") then return end
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end   -- the client fires it only on a visible->hidden change
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
-- A point already set is replaced, as the client does (a frame keeps one
-- anchor per point).
function Methods.SetPoint(w, point, ...)
    if not guard(w, "SetPoint") then return end
    for i = #w._points, 1, -1 do
        if w._points[i][1] == point then table.remove(w._points, i) end
    end
    table.insert(w._points, { point, ... })
end
function Methods.ClearAllPoints(w) if guard(w, "ClearAllPoints") then w._points = {} end end
function Methods.GetNumPoints(w) return #w._points end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if not p then return nil end
    local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
    if type(rel) ~= "table" and type(rel) ~= "string" then
        -- SetPoint(point, x, y) short form is not used by the addon.
    end
    return point, rel, relPoint, x, y
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) if guard(w, "SetSize") then w._width, w._height = x, y end end
function Methods.SetWidth(w, x) if guard(w, "SetWidth") then w._width = x end end
function Methods.SetHeight(w, y) if guard(w, "SetHeight") then w._height = y end end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.GetEffectiveScale() return 0.64 end

-- Scripts and events.
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    if WoW.refuseEvents and WoW.refuseEvents[e] then return false end   -- the client's refusal
    w._events[e] = true
    return true
end
function Methods.RegisterUnitEvent(w, e, unit)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._unitEvents[e] = unit
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil; w._unitEvents[e] = nil end
function Methods.UnregisterAllEvents(w) w._events = {}; w._unitEvents = {}; w._silenced = true end
function Methods.SetParent(w, p) if guard(w, "SetParent") then w._parent = p end end
function Methods.GetParent(w) return w._parent end
function Methods.GetName(w) return w._name end
function Methods.IsProtected(w) return w._protected == true, w._explicit == true end
function Methods.GetChildren(w)
    local kids = {}
    for _, f in ipairs(WoW.frames) do if f._parent == w then kids[#kids + 1] = f end end
    return unpack(kids)
end
function Methods.GetObjectType(w) return w._type end
function Methods.SetClipsChildren(w, v) w._clips = v end

-- Secure attributes and clicks.
function Methods.SetAttribute(w, k, v)
    if not guard(w, "SetAttribute") then return end
    w._attrs[k] = v
    -- With the client's header code, every attribute change is heard, as in
    -- the client (the model below calls the unit hooks itself).
    if WoW.clientHeaders and w._scripts.OnAttributeChanged then w._scripts.OnAttributeChanged(w, k, v) end
end
function Methods.GetAttribute(w, k) return w._attrs[k] end
function Methods.RegisterForClicks(w, ...) if guard(w, "RegisterForClicks") then w._clicks = { ... } end end
function Methods.StartMoving(w) if guard(w, "StartMoving") then w._moving = true end end
-- No real geometry in the stub: a test sets w._center = { x, y } where it matters.
function Methods.GetCenter(w) if w._center then return w._center[1], w._center[2] end end
-- Edges from a test-set centre and the frame's size (no real layout here).
local function edge(w, axis, sign)
    if not (w._center and w._width and w._height) then return nil end
    if axis == "x" then return w._center[1] + sign * w._width / 2 end
    return w._center[2] + sign * w._height / 2
end
function Methods.GetLeft(w) return edge(w, "x", -1) end
function Methods.GetRight(w) return edge(w, "x", 1) end
function Methods.GetBottom(w) return edge(w, "y", -1) end
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
function Methods.GetTop(w) return edge(w, "y", 1) end
function Methods.StopMovingOrSizing(w)
    if guard(w, "StopMovingOrSizing") then
        w._moving = false
        w._points = { { "TOPLEFT", "UIParent", "BOTTOMLEFT", 111, 222 } }   -- where the drag "left" it
    end
end

-- Regions.
function Methods.CreateTexture(w) local t = newWidget("Texture", w); return t end
function Methods.CreateMaskTexture(w) local t = newWidget("MaskTexture", w); return t end
function Methods.CreateFontString(w)
    local t = newWidget("FontString", w)
    table.insert(WoW.fontStrings, t)   -- a test can find a page's texts
    return t
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
function Methods.CreateAnimationGroup(w)
    local ag = newWidget("AnimationGroup", w)
    ag._plays = 0
    return ag
end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._plays = (ag._plays or 0) + 1 end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.SetTextColor(fs, r, g, b, a) fs._textColor = { r, g, b, a } end
function Methods.SetAlpha(w, a) w._alpha = a end
function Methods.SetTexCoord(t, ...) t._texCoord = { ... } end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    t._gradient = { orientation, c1, c2 }
end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end

-- FontString: the client formats natively and accepts secrets. Model that:
-- with any secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
function Methods.SetText(fs, text) fs._text = text end
function Methods.SetChecked(cb, v) cb._checked = v and true or false end
-- Buttons and edit boxes: enabled state (all in the dump's widget walk).
function Methods.SetEnabled(w, on) w._enabled = on and true or false end
function Methods.Enable(w) w._enabled = true end
function Methods.Disable(w) w._enabled = false end
function Methods.IsEnabled(w) return w._enabled ~= false end
function Methods.GetChecked(cb) return cb._checked == true end
function Methods.LockHighlight(b) b._highlightLocked = true end
function Methods.SetScrollChild(sf, child) sf._scrollChild = child end
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
    if e._scripts and e._scripts.OnEditFocusGained then e._scripts.OnEditFocusGained(e) end
end
function Methods.ClearFocus(e)
    if not e._focus then return end
    e._focus = false
    if e._scripts and e._scripts.OnEditFocusLost then e._scripts.OnEditFocusLost(e) end
end
function Methods.HasFocus(e) return e._focus == true end
function Methods.GetScrollChild(sf) return sf._scrollChild end
-- Button state textures: Set<State>Texture creates the texture, Get<State>Texture returns it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    Methods["Set" .. state .. "Texture"] = function(b, file)
        local t = newWidget("Texture", b)
        t._file = file
        b["_" .. state] = t
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b["_" .. state] end
end
function Methods.UnlockHighlight(b) b._highlightLocked = false end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.GetFont(fs) if fs._font then return fs._font[1], fs._font[2], fs._font[3] end end

-- StatusBar: takes values (secret or not) without inspecting them.
function Methods.SetMinMaxValues(b, lo, hi, interp) b._min, b._max, b._minMaxInterp = lo, hi, interp end
function Methods.GetMinMaxValues(b) return b._min, b._max end
function Methods.SetValue(b, v, interp)
    b._value = v; b._interp = interp
    -- The client fires OnValueChanged for programmatic changes too (userInput false).
    if b._scripts and b._scripts.OnValueChanged then b._scripts.OnValueChanged(b, v, false) end
end
function Methods.GetValue(b) return b._value end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end
function Methods.SetStatusBarColor(b, r, g, bl) b._color = { r, g, bl } end
function Methods.SetTimerDuration(b, d, interp, dir) b._timer = { duration = d, interp = interp, dir = dir } end

-- PlayerModel (and the aura container: both take a unit).
local function seq(w, what) w._seq = w._seq or {}; table.insert(w._seq, what) end
function Methods.SetUnit(m, unit) m._modelUnit = unit; seq(m, "SetUnit"); return true end

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
        local frame = newWidget("Button", c)
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
    local frame = newWidget("Button", c)
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
function Methods.ClearModel(m) m._modelUnit = nil end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

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
function InCombatLockdown() return WoW.combat end
function IsShiftKeyDown() return WoW.shift end
function IsAltKeyDown() return WoW.alt == true end
function RegisterUnitWatch(frame) WoW.unitWatch[frame] = true end
-- FrameXML's (SecureStateDriver.lua): recorded, not evaluated.
function RegisterStateDriver(frame, state, values) WoW.stateDrivers[frame] = { state, values } end
function UnregisterUnitWatch(frame) WoW.unitWatch[frame] = nil; frame._unwatched = true end
-- Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua:602. The snippet is
-- recorded, not run: a test runs it with its own handle stubs.
function SecureHandlerWrapScript(frame, script, header, preBody, postBody)
    assert(type(script) == "string" and type(preBody) == "string", "Invalid wrap")
    assert(header and header._protected, "Header frame must be explicitly protected")
    if WoW.combat then table.insert(WoW.blocked, (frame._name or frame._type) .. ":wrap " .. script) return end
    frame._wraps = frame._wraps or {}
    frame._wraps[script] = { header = header, pre = preBody, post = postBody }
end

-- In the dump's _G walk: drops every override binding `owner` holds.
function ClearOverrideBindings(owner) end
-- In the dump's _G walk: binds `key` to click the named button for `owner`.
function SetOverrideBindingClick(owner, isPriority, key, buttonName, mouseClick) end

-- Post-hook a method, as the client does: the original runs first.
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    rawset(t, name, function(self, ...)
        local r = orig(self, ...)
        fn(self, ...)
        return r
    end)
end

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
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    UIParent._protected = nil   -- the client's UIParent is not protected by its children
end
function WoW.SetEditMode(open)
    if open and not rawget(_G, "EditModeManagerFrame") then
        rawset(_G, "EditModeManagerFrame", newWidget("Frame", UIParent, "EditModeManagerFrame"))
    end
    local em = rawget(_G, "EditModeManagerFrame")
    if em then em._shown = open end
end

C_Timer = { After = function(s, fn) table.insert(WoW.timers, fn) end }
function WoW.flushTimers()
    local run = WoW.timers
    WoW.timers = {}
    for _, fn in ipairs(run) do fn() end
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
    if WoW.secretFields.guid then return WoW.Secret(u .. ".guid") end
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
function GetUnitName(u) return unitField(u, "name") end
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
function UnitIsUnit(a, b)
    local ua, ub = WoW.units[a], WoW.units[b]
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
function Methods.SetAtlas(t, name) t._atlas = name; return true end
function Methods.Stop(ag) ag._stops = (ag._stops or 0) + 1 end
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
-- WoW.templateSizes[template] = { w, h } stands in for the XML <Size>.
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

function WoW.layoutHeader(h)
    if WoW.clientHeaders then return WoW.clientHeaders.update(h) end
    local list = headerUnits(h)
    local i = 1
    while h._attrs["child" .. i] do
        local child = h._attrs["child" .. i]
        local unit = list[i]
        local old = child._attrs.unit
        child._attrs.unit = unit      -- secure header code: never blocked
        child._shown = unit ~= nil
        if old ~= unit and child._scripts.OnAttributeChanged then
            child._scripts.OnAttributeChanged(child, "unit", unit)
        end
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
            local child = CreateFrame(w._attrs.templateType or "Button", nil, w, w._attrs.template)
            local size = WoW.templateSizes[w._attrs.template]
            if size then child._width, child._height = size[1], size[2] end
            w._attrs["child" .. i] = child
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
    rawset(_G, "UnitName", function(u) return unitField(u, "name") end)
    chunk()
    local function secure(fn, ...)
        local was = WoW.secureCode
        WoW.secureCode = true
        local ok, err = pcall(fn, ...)
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

-- Fire an event at every frame registered for it, the way the client does.
-- Unit events reach a RegisterUnitEvent frame only for its unit. Errors are
-- NOT caught: a handler that throws fails the test.
function WoW.fire(event, ...)
    local unit = ...
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler then
            if w._events[event] then handler(w, event, ...)
            elseif w._unitEvents[event] ~= nil and w._unitEvents[event] == unit then handler(w, event, ...) end
        end
    end
end

-- Every event any frame registered, fired for every modelled unit.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
        for e in pairs(w._unitEvents) do seen[e] = true end
    end
    for e in pairs(seen) do
        for u in pairs(WoW.units) do WoW.fire(e, u) end
        WoW.fire(e, "player")
    end
    return seen
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

-- The client's unit watch: show/hide watched frames by UnitExists.
function WoW.applyUnitWatch()
    for frame in pairs(WoW.unitWatch) do
        local exists = WoW.units[frame._attrs.unit] ~= nil
        if exists and not frame._shown then
            frame._shown = true
            if frame._scripts.OnShow then frame._scripts.OnShow(frame) end
        elseif not exists then
            frame._shown = false
        end
    end
end

-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
local allowNil = { GlassRaidFrames = true, GlassRaidFramesDB = true, GlassRaidFramesCharDB = true, LibStub = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
