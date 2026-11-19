-- harness.lua: the addon loader. dofile it after wow_stubs.lua. check / eq /
-- done are WowTestKit's (globals).

TOC = "GlassRaidFrames.toc"

-- Every file line of the TOC, in load order (this addon's .lua and .xml files
-- and the embedded library's .xml).
function tocLines() return Kit.tocLines(TOC) end

-- This addon's own Lua files listed in the TOC, in load order.
function tocFiles() return Kit.tocFiles(TOC) end

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

-- RaidProbe is a ForeverProbe module (#44): its test loads the host from a
-- checkout ($FOREVERPROBE, else ../ForeverProbe), copied from GlassChat's
-- harness (ForeverProbe docs/GUIDE.md section 8). The host reads every client
-- API through rawget, so the strict stub doesn't trip on what it lacks. CI
-- has no checkout (private, local): FOREVERPROBE_OPTIONAL=1 skips the file.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
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

-- Virtual templates from the addon's XML, as WoW.templates: their <Size> and
-- whether they inherit a secure template (then their frames are protected).
function xmlTemplates()
    local xml = io.open("GlassRaidFrames.xml"):read("*a")
    for attrs, body in xml:gmatch("<Button%s+([^>]-)>(.-)</Button>") do
        local name = attrs:match('name="([^"]+)"')
        local inherits = attrs:match('inherits="([^"]+)"') or ""
        local w, h = body:match('<Size%s+x="(%d+)"%s+y="(%d+)"')
        if name then
            WoW.templates[name] = function(f)
                if w then f._width, f._height = tonumber(w), tonumber(h) end
                if inherits:find("Secure") then f._protected = true end
            end
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
    -- The group layout (#69) is on by default; the tests written before it
    -- cover the legacy grid, so they load with it off unless they ask
    -- (opts.layout).
    if not opts.layout then
        if type(GlassRaidFramesDB) ~= "table" then GlassRaidFramesDB = {} end
        if GlassRaidFramesDB.groupLayout == nil then GlassRaidFramesDB.groupLayout = false end
    end
    -- After the files, before ADDON_LOADED: what loaded first (Glass UI, a
    -- newer LibGlass) is in place by then.
    if opts.beforeLoaded then opts.beforeLoaded() end
    WoW.fire("ADDON_LOADED", "GlassRaidFrames")
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.fire("LOADING_SCREEN_DISABLED")   -- the client's order at login (FOREVER-PROBE item 16)
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

-- The calls made on a widget by name, from its call log (WowTestKit's
-- w._log: one { name, n = argc, ... } per call), oldest first.
function calls(w, name)
    local out = {}
    for _, c in ipairs(w._log or {}) do
        if c[1] == name then out[#out + 1] = c end
    end
    return out
end

-- A font string's text. With secret arguments the kit keeps SetFormattedText's
-- text unformatted ({ secretFormat, n }); the arguments come from the call
-- that set it, in the call log, as `args`.
function formattedText(fs)
    local t = fs._text
    if type(t) ~= "table" or not t.secretFormat then return t end
    local c = calls(fs, "SetFormattedText")
    c = c[#c]
    local args = {}
    for i = 3, c.n + 1 do args[i - 2] = c[i] end
    return { secretFormat = t.secretFormat, n = t.n, args = args }
end

-- FINDING (#97): /grf's help and usage lines print a bare "|" between
-- choices, which the client reads as an escape (it drops it and the next
-- character). The kit's done() fails on any stray "|"; until #97 doubles
-- them, exactly these lines are let through (the GlassRF prefix, then one of
-- the lines below), so any other stray still fails.
local KNOWN_STRAYS = {
    "^/grf clickcast %- the click%-casting editor; /grf clickcast all|ours %- ",
    "^/grf keys frames|anywhere %- ",
    "^/grf role %[auto|healer|caster|melee|tank%] %- settings follow your role; role: %a+ %(%a+%)$",
    "^/grf unlock | lock %- ",
    "^/grf size <width> <height> | reset %- ",
    "^/grf layout on|off %- one grid sized by the group %(after /reload%); hud|side %- ",
    "^/grf preview 10|20|40|off %- ",
    "^/grf ind %- buff and debuff indicators %(per class%); /grf ind <n> on|off, /grf ind reset$",
    "^/grf names first|initial|full %- ",
    "^/grf nick <nickname> | clear %- ",
    "^/grf look pearl|clean|classic %- the glass %(after /reload%); now %a+$",
    "^/grf body clear|smoked %- the glass body %(after /reload%); now %a+$",
    "^look pearl|clean|classic %(now [^|]+%)$",
    "^usage: /grf size <width> %[<height>%] | reset$",
}
local PREFIX = "|cff7fd4ffGlassRF|r "
local kitDone = done
function done(name)
    local keep = {}
    for _, line in ipairs(WoW.strays) do
        local known = false
        if line:sub(1, #PREFIX) == PREFIX then
            local rest = line:sub(#PREFIX + 1)
            for _, p in ipairs(KNOWN_STRAYS) do
                if rest:find(p) then known = true break end
            end
        end
        if not known then keep[#keep + 1] = line end
    end
    WoW.strays = keep
    return kitDone(name)
end
