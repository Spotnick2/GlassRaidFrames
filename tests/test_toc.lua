-- The manifest, the pinned build and the lifted material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassRaidFrames.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassRaidFramesDB", 1, true), "saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
eq(tocFiles()[1], "Compat.lua", "Compat loads first")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Every kind of file the TOC loads is one Tools/deploy.ps1 copies (it once
-- skipped the XML template, and the headers would have had no children).
local deploy = io.open("Tools/deploy.ps1"):read("*a")
for line in io.lines("GlassRaidFrames.toc") do
    line = line:gsub("%c", "")
    local ext = line:match("^[^#].-(%.%a+)$")
    if ext then check(deploy:find('"' .. ext .. '"', 1, true), "deploy.ps1 copies " .. ext .. " files (" .. line .. ")") end
end

-- The checked-in event list (the stub's fallback when the dump is absent, as
-- on CI) must match the dump's documented events exactly.
if WoW.dumpAvailable then
    local listed, n = {}, 0
    for line in io.lines("tests/events-70009.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then listed[name] = true; n = n + 1 end
    end
    local missing, extra = {}, {}
    for e in pairs(WoW.KNOWN_EVENTS) do if not listed[e] then missing[#missing + 1] = e end end
    for e in pairs(listed) do if not WoW.KNOWN_EVENTS[e] then extra[#extra + 1] = e end end
    eq(#missing, 0, "every dump event is in tests/events-70009.txt (regenerate it): " .. table.concat(missing, ","))
    eq(#extra, 0, "no event in tests/events-70009.txt is missing from the dump: " .. table.concat(extra, ","))
    check(n > 1000, "the fixture holds the full event list (" .. n .. ")")
end

-- Two places that must agree, never derived from each other (porting guide §0).
loadAddon()
eq(GlassRaidFrames.MEASURED_ON_BUILD, "1.60.1.70009", "MEASURED_ON_BUILD")

-- Every texture the material names exists in Media/.
for size, S in pairs(GlassRaidFrames.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = "Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end

-- Glass.lua is a copy of GlassUnitFrames' material on its MAIN branch: only
-- the namespace lines and the header may differ. Read through git, not the
-- working tree, whose branch another session may have switched.
-- The null device by OS: on Linux (CI), "2>nul" would create a file named
-- nul in the repo, which the packager would then ship.
local NULL = package.config:sub(1, 1) == "\\" and "nul" or "/dev/null"
local upstream = io.popen('git -C ../GlassUnitFrames show main:Glass.lua 2>' .. NULL)
local theirs = upstream and upstream:read("*a") or ""
if upstream then upstream:close() end
if theirs ~= "" then
    local function body(s)
        s = s:gsub("\r", "")
        s = s:gsub("^.-\nlocal ADDON = %.%.%.\n", "")
        s = s:gsub("GlassUF", "GlassRaidFrames")
        return s
    end
    check(body(io.open("Glass.lua"):read("*a")) == body(theirs),
        "Glass.lua matches GlassUnitFrames main:Glass.lua (copy it back)")
    local gen = io.popen('git -C ../GlassUnitFrames show main:Tools/make_textures.py 2>' .. NULL)
    local g = gen and gen:read("*a") or ""
    if gen then gen:close() end
    check(g:gsub("\r", "") == io.open("Tools/make_textures.py", "rb"):read("*a"):gsub("\r", ""),
        "Tools/make_textures.py matches GlassUnitFrames main (copy it back)")
else
    io.write("  (Glass.lua upstream check skipped: no ../GlassUnitFrames git repo)\n")
end

done("test_toc")
