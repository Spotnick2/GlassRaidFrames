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
-- Clean is the default here (the owner's pick); classic is r5's look.
GRF.LOOKS = { classic = true, clean = true }
GRF.DEFAULT_LOOK = "clean"
-- Clear is LibGlass's own body (tint alpha 0.24); smoked takes the middle of
-- the 0.50-0.80 its notes explored for smoked reading surfaces.
GRF.BODIES = { clear = true, smoked = true }
GRF.SMOKED = 0.65

local current
-- Before the build only (ADDON_LOADED): surfaces built earlier keep their
-- look. An unknown look is the default; `body` is "smoked" or anything else
-- (clear).
function GRF.UseLook(look, body)
    if not GRF.LOOKS[look] then look = GRF.DEFAULT_LOOK end
    body = body == "smoked" and "smoked" or "clear"
    if current and look == GRF.look and body == GRF.body then return end   -- already in use
    local opts = {}
    if look == "clean" then opts.preset = "clean" end
    if body == "smoked" then opts.bodyAlpha = GRF.SMOKED end
    current = lib:New(opts)
    GRF.look, GRF.body = look, body
end
GRF.UseLook(GRF.DEFAULT_LOOK)

GRF.Glass = setmetatable({}, {
    __index = function(_, k) return current[k] end,
    __newindex = function(_, k, v) current[k] = v end,
})
