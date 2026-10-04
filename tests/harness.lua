-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Every file line of the TOC, in load order (this addon's .lua and .xml files
-- and the embedded library's .xml).
function tocLines()
    local lines = {}
    for line in io.lines("GlassRaidFrames.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- This addon's own Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for _, line in ipairs(tocLines()) do
        if line:match("%.lua$") then files[#files + 1] = line end
    end
    return files
end

-- The embedded LibGlass-1.0 comes from a checkout, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ../LibGlass. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
function libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass there or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- The Lua files the library's XML loads, as paths, in order: what the client
-- runs for the TOC's XML line. A listed file that is missing fails here.
function libGlassScripts()
    local root = libGlassRoot()
    local f = assert(io.open(root .. "/LibGlass-1.0.xml", "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error("LibGlass checkout at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error("LibGlass-1.0.xml at " .. root .. " lists no Script files", 0) end
    return files
end

-- Virtual templates from the addon's XML: their <Size> and whether they
-- inherit a secure template (then their frames are protected).
function xmlTemplates()
    local xml = io.open("GlassRaidFrames.xml"):read("*a")
    for attrs, body in xml:gmatch("<Button%s+([^>]-)>(.-)</Button>") do
        local name = attrs:match('name="([^"]+)"')
        local inherits = attrs:match('inherits="([^"]+)"') or ""
        local w, h = body:match('<Size%s+x="(%d+)"%s+y="(%d+)"')
        if name then
            if w then WoW.templateSizes[name] = { tonumber(w), tonumber(h) } end
            if inherits:find("Secure") then WoW.secureTemplates[name] = true end
        end
    end
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- the library's XML expanded in place (our own XML holds only templates,
-- read by xmlTemplates), then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    xmlTemplates()
    for _, line in ipairs(tocLines()) do
        local files = {}
        if line == LIBGLASS_XML then
            files = libGlassScripts()
        elseif line:match("%.lua$") then
            files = { line }
        elseif line ~= "GlassRaidFrames.xml" then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassRaidFrames", ns)
        end
    end
    if opts.db then GlassRaidFramesDB = opts.db end
    WoW.fire("ADDON_LOADED", "GlassRaidFrames")
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.applyUnitWatch()
    WoW.tick()
    return GlassRaidFrames
end

-- Chat lines printed since the last call.
local seenChat = 0
function newChat()
    local lines = {}
    for i = seenChat + 1, #WoW.chat do lines[#lines + 1] = WoW.chat[i] end
    seenChat = #WoW.chat
    return lines
end

function chatHas(pattern)
    for _, line in ipairs(WoW.chat) do
        if line:find(pattern) then return true end
    end
    return false
end

-- A party: the player and party1..n (n <= 4).
function party(n)
    WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST", player = true, health = 90, maxHealth = 92 })
    for i = 1, n do
        WoW.SetUnit("party" .. i, { name = "Member " .. i, class = "PALADIN", player = true, health = 100, maxHealth = 150 })
    end
end

-- A raid of `n` members, five per subgroup in index order.
function raid(n)
    WoW.raid = {}
    WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST", player = true })
    for i = 1, n do
        local u = "raid" .. i
        WoW.SetUnit(u, { name = "Raider " .. i, class = "WARRIOR", player = true })
        WoW.raid[u] = { index = i, subgroup = math.floor((i - 1) / 5) + 1 }
    end
end

-- The header child currently showing `unit`, or nil.
function childFor(unit)
    for _, c in ipairs(GlassRaidFrames.Header.children) do
        if c:GetAttribute("unit") == unit then return c end
    end
end

-- Let the engine paint: one rendered frame flushes every dirty channel.
function flush() WoW.tick() end
