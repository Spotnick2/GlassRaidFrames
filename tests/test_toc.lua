-- The manifest, the pinned build and the embedded material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassRaidFrames.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassRaidFramesDB", 1, true), "saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Every kind of file the TOC loads is one Tools/deploy.ps1 copies (it once
-- skipped the XML template, and the headers would have had no children).
-- The library's XML line is deployed by LibGlass's own deploy.ps1, which ours calls.
local deploy = io.open("Tools/deploy.ps1"):read("*a")
check(deploy:find("-Addon GlassRaidFrames", 1, true), "deploy.ps1 calls LibGlass's deploy")
for _, line in ipairs(tocLines()) do
    local ext = line ~= LIBGLASS_XML and line:match("(%.%a+)$")
    if ext then check(deploy:find('"' .. ext .. '"', 1, true), "deploy.ps1 copies " .. ext .. " files (" .. line .. ")") end
end

-- The checked-in event list (the stub's fallback when the dump is absent, as
-- on CI) must match the dump's documented events exactly.
if WoW.dumpAvailable then
    local listed, n = {}, 0
    for line in io.lines("tests/events-70338.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then listed[name] = true; n = n + 1 end
    end
    local missing, extra = {}, {}
    for e in pairs(WoW.KNOWN_EVENTS) do if not listed[e] then missing[#missing + 1] = e end end
    for e in pairs(listed) do if not WoW.KNOWN_EVENTS[e] then extra[#extra + 1] = e end end
    eq(#missing, 0, "every dump event is in tests/events-70338.txt (regenerate it): " .. table.concat(missing, ","))
    eq(#extra, 0, "no event in tests/events-70338.txt is missing from the dump: " .. table.concat(extra, ","))
    check(n > 1000, "the fixture holds the full event list (" .. n .. ")")
end

-- Two places that must agree, never derived from each other (porting guide §0).
loadAddon()

-- The XML template's size and Header's default must agree (the template
-- sizes children before Header.ApplySize can).
do
    local xml = io.open("GlassRaidFrames.xml"):read("*a")
    local w, h = xml:match('<Size%s+x="(%d+)"%s+y="(%d+)"')
    local GRFH = GlassRaidFrames.Header
    eq(tonumber(w), GRFH.DEFAULT_W, "GlassRaidFrames.xml width = Header.DEFAULT_W")
    eq(tonumber(h), GRFH.DEFAULT_H, "GlassRaidFrames.xml height = Header.DEFAULT_H")
end

eq(GlassRaidFrames.MEASURED_ON_BUILD, "1.60.1.70338", "MEASURED_ON_BUILD")

-- The packager replaces its version keyword in every shipped file, so a
-- literal one in Lua would turn into the release tag (AltStable's bug).
for _, f in ipairs(tocFiles()) do
    check(not io.open(f):read("*a"):find("@project-version@", 1, true), "no literal version keyword in " .. f)
end

-- The newer-build warning is for dev copies only; a release stays quiet.
local function warned(version, build)
    WoW.reset()
    WoW.addonVersion = version
    local real = GetBuildInfo
    GetBuildInfo = function() return "1.60.1", build, "Sep 23 2026", 16001 end
    loadAddon()
    GetBuildInfo = real
    for _, line in ipairs(WoW.chat) do
        if line:find("is newer than", 1, true) then return true end
    end
    return false
end
check(warned("dev", "99999"), "dev copy warns on a newer build")
check(warned("@" .. "project-version" .. "@", "99999"), "unpackaged checkout warns on a newer build")
check(warned(nil, "99999"), "unreadable version counts as dev")
check(not warned("v1.2.0", "99999"), "release does not warn on a newer build")
check(not warned("dev", "70338"), "no warning on the measured build")

-- Every texture the material names ships with the library (Libs\LibGlass-1.0\Media
-- in the package; the checkout's Media/ here). Our Media/ holds only our own sound.
local root = libGlassRoot()
for size, S in pairs(GlassRaidFrames.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open(root .. "/Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassRaidFrames.Glass.MEDIA, "Interface\\AddOns\\GlassRaidFrames\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")

done("test_toc")
