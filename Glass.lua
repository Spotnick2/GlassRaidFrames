-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Its contract, write-up and textures are
-- there: material changes are LibGlass PRs, not edits here.
--
-- An instance, not the library itself: STYLE, the live setters and the font
-- registry are this addon's own, never another glass addon's. Every call site
-- keeps the dot-call shape (Glass.Apply, Glass.Bar, Glass.MEDIA, ...).

--
-- The look (#37) and the body (#38): LibGlass r6's preset and bodyAlpha are
-- construction settings, and the saved choice is only readable at
-- ADDON_LOADED, after every file has taken its `local Glass = GRF.Glass`. So
-- GRF.Glass forwards to the instance in use, picked once by GRF.UseLook before
-- anything is built; switching needs /reload (GlassUnitFrames' #102 / #101).
-- The instance's functions are closures bound to it, so a forwarded
-- Glass.Apply(...) is that instance's own.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local lib = LibStub("LibGlass-1.0")
-- Pearl is the default (the owner, #67: the suite's look, LibGlass r11);
-- clean is r6's preset, classic r5's look.
GRF.LOOKS = { pearl = true, clean = true, classic = true }
GRF.DEFAULT_LOOK = "pearl"
GRF.PEARL_MINOR = 11     -- LibGlass r11 brought preset = "pearl"
-- Clear is LibGlass's own body (tint alpha 0.24); smoked takes the middle of
-- the 0.50-0.80 its notes explored for smoked reading surfaces.
GRF.BODIES = { clear = true, smoked = true }
GRF.SMOKED = 0.65

local current
-- Before the build only (ADDON_LOADED): surfaces built earlier keep their
-- look. An unknown look is the default; `body` is "smoked" or anything else
-- (clear). Pearl needs r11: an older winning LibGlass, or a Pearl build that
-- throws, builds clean instead and sets GRF.lookFallback. Classic is no
-- preset (r6-r10 refuse "classic"; r11 takes both).
function GRF.UseLook(look, body)
    if not GRF.LOOKS[look] then look = GRF.DEFAULT_LOOK end
    body = body == "smoked" and "smoked" or "clear"
    local _, minor = LibStub:GetLibrary("LibGlass-1.0", true)
    local fallback = look == "pearl" and not (type(minor) == "number" and minor >= GRF.PEARL_MINOR)
    if fallback then look = "clean" end
    if current and look == GRF.look and body == GRF.body then   -- already in use
        GRF.lookFallback = fallback or nil
        return
    end
    local opts = { preset = look ~= "classic" and look or nil }
    if body == "smoked" then opts.bodyAlpha = GRF.SMOKED end
    local ok, inst = pcall(lib.New, lib, opts)
    if not ok and look == "pearl" then
        fallback, look, opts.preset = true, "clean", "clean"
        inst = lib:New(opts)
    elseif not ok then
        error(inst, 0)
    end
    current = inst
    GRF.look, GRF.body, GRF.lookFallback = look, body, fallback or nil
end
GRF.UseLook(GRF.DEFAULT_LOOK)

-- The suite theme (#67, Glass UI's docs/SUITE.md, API 1). When the player
-- turns Follow on in Glass UI, its Theme answer says "pearl" and this addon
-- builds LibGlass's Pearl preset instead of its own look; the look and body
-- are then suspended (refused, never written) but stay saved. Decided once,
-- at ADDON_LOADED, before anything is built (GlassUnitFrames' #129).
GRF.following = nil      -- "pearl" while this session built the suite theme
GRF.suiteFailure = nil   -- why Pearl was asked for and not built

-- Glass UI's Suite table, or nil: anything but API 1 exactly counts as absent
-- (the released Glass UI has no Suite at all).
local function suite()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then return nil end
    return S
end

-- The answer's preset, read under pcall: a junk answer can't throw at us.
local function presetOf(answer)
    if type(answer) ~= "table" then return nil end
    local ok, preset = pcall(function() return answer.preset end)
    return ok and preset == "pearl" and preset or nil
end

-- Ask Glass UI and, when told Pearl, build it. Returns the Suite table (nil
-- when Glass UI doesn't speak the API) and LibGlass's MINOR at the attempt.
-- Afterwards GRF.following or GRF.suiteFailure says what happened.
function GRF.UseSuite(addon)
    local S = suite()
    if not S then return nil end
    local ok, answer = pcall(S.Theme, addon)
    local preset = ok and presetOf(answer) or nil
    local _, minor = LibStub:GetLibrary("LibGlass-1.0", true)
    if not preset then return S, minor end
    if type(minor) ~= "number" or minor < GRF.PEARL_MINOR then
        GRF.suiteFailure = "library-too-old"
        return S, minor
    end
    local built, inst = pcall(lib.New, lib, { preset = preset })
    if not built then
        GRF.suiteFailure = "build-failed"
        return S, minor
    end
    current = inst
    GRF.following = preset
    return S, minor
end

-- What the player reads while the suite theme owns the look, or after it
-- failed, or when the local Pearl fell back to Clean; else nil.
function GRF.SuiteStatus()
    if GRF.following then return "Look: following Glass UI (Pearl), set in Glass UI" end
    if GRF.suiteFailure then return "own look: " .. GRF.suiteFailure end
    if GRF.lookFallback then return GRF.PEARL_FALLBACK end
end
GRF.PEARL_FALLBACK = "Pearl needs LibGlass r11 or newer: Clean in use"

GRF.Glass = setmetatable({}, {
    __index = function(_, k) return current[k] end,
    __newindex = function(_, k, v) current[k] = v end,
})
