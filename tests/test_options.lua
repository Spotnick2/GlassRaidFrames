-- The main options page: a note takes the height it wraps to, so a two-line
-- note never runs into the line under it (GlassUnitFrames' #96).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GRF = loadAddon()
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)

-- Every text placed in the page's one column (anchored to the content frame).
local texts = {}
for _, fs in ipairs(WoW.fontStrings) do
    local p = fs._points[1]
    if p and p[1] == "TOPLEFT" and p[2] == fs._parent and type(fs._text) == "string"
        and fs._parent == O.content then
        texts[#texts + 1] = fs
    end
end
check(#texts > 5, "the page's texts are found")

-- No text's wrapped bottom reaches into the next one placed under it.
local wrapped, overlaps = 0, 0
for _, a in ipairs(texts) do
    local ya, h = a._points[1][5], a:GetStringHeight()
    if h > 14 then wrapped = wrapped + 1 end
    for _, b in ipairs(texts) do
        local yb = b._points[1][5]
        if a ~= b and ya > yb and ya - h < yb then overlaps = overlaps + 1 end
    end
end
check(wrapped >= 1, "some note wraps (the role note)")
eq(overlaps, 0, "no wrapped note overlaps the text under it")

-- The page scrolls (it outgrew the ~600-tall Settings canvas, Codex on #39):
-- the content is a scroll child at least as tall as its lowest text.
eq(O.scroll._scrollChild, O.content, "the page's content is a scroll child")
check(O.scroll:GetParent() == O.panel, "the scroll frame fills the panel")
local lowest = 0
for _, fs in ipairs(texts) do lowest = math.min(lowest, fs._points[1][5] - fs:GetStringHeight()) end
check(lowest < -602, "the page is taller than the canvas (it needs the scroll)")
check(O.content:GetHeight() >= -lowest, "the content holds every text")
done("test_options")
