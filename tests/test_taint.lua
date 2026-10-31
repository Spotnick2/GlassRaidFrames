-- Never write a global this addon doesn't own (AltStableSync's test_taint).
--
-- Assigning a global Blizzard owns, even to itself (`SlashCmdList =
-- SlashCmdList or {}`), marks the slot tainted by this addon: every secure
-- macro that later reads it runs tainted, its protected calls are blocked and
-- blamed on us (measured on 70235, PORTING-TBC-TO-FOREVER.md "Never reassign
-- a Blizzard global"). A field write (SlashCmdList.FOO = fn) is the supported
-- pattern. This loads every addon file under an environment that records
-- every global write, however spelled, at load time; runtime paths and field
-- writes have their own targeted tests.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The globals this addon owns (anything else written is a failure).
local OURS = { GlassRaidFrames = true, GlassRaidFramesDB = true, GlassRaidFramesCharDB = true,
               SLASH_GLASSRAIDFRAMES1 = true, ClickCastFrames = true }

-- Load `chunk` in an environment that records every global write: `G =`,
-- `_G.G =`, rawset(_G, ...), multi-assignment, inside a branch. Same-table
-- writes count: the client taints the SLOT on any addon write.
local function writesOf(chunk, env)
    local writes = {}
    env = env or setmetatable({}, { __index = _G })
    getmetatable(env).__newindex = function(t, k, v)
        if not OURS[k] then writes[#writes + 1] = tostring(k) end
        rawset(t, k, v)
    end
    -- Installed raw, so the recorder doesn't count its own two writes.
    rawset(env, "_G", env)
    rawset(env, "rawset", function(t, k, v)
        if t == env and not OURS[k] then writes[#writes + 1] = tostring(k) end
        return rawset(t, k, v)
    end)
    setfenv(chunk, env)
    chunk("GlassRaidFrames", {})
    return writes, env
end

-- The recorder catches every spelling (mutation check, in memory).
for _, src in ipairs({
    "SlashCmdList = SlashCmdList or {}",
    "_G.SlashCmdList = SlashCmdList",
    "rawset(_G, 'SlashCmdList', SlashCmdList)",
    "local a; a, SlashCmdList = 1, SlashCmdList",
    "if true then SlashCmdList = SlashCmdList end",
    "UIParent = UIParent",
}) do
    local writes = writesOf(assert(loadstring(src)))
    eq(#writes, 1, "recorder catches: " .. src)
end
eq(#(writesOf(assert(loadstring("GlassRaidFrames = GlassRaidFrames or {}")))), 0, "our own global is allowed")

-- The library first, as the client loads the TOC's XML line (its own repo
-- tests it), then every addon file in TOC order under one recording
-- environment, the way the client runs them.
xmlTemplates()
for _, file in ipairs(libGlassScripts()) do assert(loadfile(file))("GlassRaidFrames", {}) end
local env = setmetatable({}, { __index = _G })
local all = {}
for _, file in ipairs(tocFiles()) do
    local writes = writesOf(assert(loadfile(file)), env)
    for _, w in ipairs(writes) do all[#all + 1] = file .. ": " .. w end
end
eq(#all, 0, "no addon file writes a global it doesn't own: " .. table.concat(all, ", "))
check(type(env.GlassRaidFrames) == "table", "the namespace was made in the recorder")
check(rawget(env, "SlashCmdList") == nil and type(SlashCmdList.GLASSRAIDFRAMES) == "function",
    "the slash command is registered as a field, never by reassigning SlashCmdList")
check(rawget(env, "ClickCastFrames") ~= nil, "ClickCastFrames (Clique's registry, not Blizzard's) is created by rawset: allowed")

done("test_taint")
