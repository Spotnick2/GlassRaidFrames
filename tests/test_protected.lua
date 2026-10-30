-- The stub's protected-method list (WoW.PROTECTED_METHODS) against the
-- client's own declarations: every name must carry IsProtectedFunction in the
-- generated API docs of the wow-ui-source checkout ($env:WOW_UI_SOURCE, else
-- ..\wow-ui-source; CI has none and sets WOW_UI_SOURCE_OPTIONAL=1), and the
-- names the stub deliberately leaves out must not.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local root = os.getenv("WOW_UI_SOURCE") or "../wow-ui-source"
local DOCS = root .. "/Interface/AddOns/Blizzard_APIDocumentationGenerated/"
local FILES = { "SimpleFrameAPIDocumentation.lua", "SimpleScriptRegionAPIDocumentation.lua",
                "SimpleScriptRegionResizingAPIDocumentation.lua", "SimpleButtonAPIDocumentation.lua" }

local flagged, declared = {}, {}
for _, file in ipairs(FILES) do
    local f = io.open(DOCS .. file, "r")
    if not f then
        if os.getenv("WOW_UI_SOURCE_OPTIONAL") == "1" then
            io.write("test_protected: SKIPPED (no wow-ui-source checkout)\n")
            return
        end
        check(false, "the client's API docs aren't at " .. DOCS .. file .. " (set WOW_UI_SOURCE)")
        done("test_protected")
    end
    local name
    for line in f:lines() do
        local n = line:match('^%s*Name = "([%w_]+)",')
        if n then
            name = n
            declared[name] = true
        elseif name and line:match("^%s*IsProtectedFunction = true,") then
            flagged[name] = true
        end
    end
    f:close()
end
check(next(flagged) ~= nil, "the docs declare protected functions")

for _, name in ipairs(WoW.PROTECTED_METHODS) do
    check(flagged[name], name .. " is flagged IsProtectedFunction in the 70532 docs")
end
for _, name in ipairs({ "RegisterForDrag", "SetMovable", "SetAlpha", "SetAttribute" }) do
    check(declared[name] and not flagged[name], name .. " is declared and NOT flagged (SetAttribute: the measured exception)")
end

done("test_protected")
