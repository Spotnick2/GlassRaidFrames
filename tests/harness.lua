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

-- Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for line in io.lines("GlassRaidFrames.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
    end
    return files
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- then ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("GlassRaidFrames", ns)
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
