-- ClickCastOptions.lua: the "Click-casting" page under Options > AddOns >
-- Glass Raid Frames. One row per binding (per character, per role): what
-- triggers it, the spell (dragged from the spellbook), its rank, warnings,
-- remove. New bindings are captured by pressing a key or clicking.
--
-- Same idiom as Options.lua: a canvas subcategory, created hidden, built on
-- first show and re-synced on every show and after every edit. Every edit
-- goes through GRF.ClickCast, which applies out of combat.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
local CCO = {}
GRF.ClickCastOptions = CCO

local page = CreateFrame("Frame", "GlassRaidFramesClickCastOptions")
page.name = "Click-casting"
page:Hide()
local content = CreateFrame("Frame", nil, page)
content:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
content:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

CCO.MAX_ROWS = 14
local ROW_H = 30
local rows = {}            -- UI rows (reused)
local header, status, capture, blizzList, mouseoverWarn

local MOUSE_NAMES = { "Left click", "Right click", "Middle click", "Button 4", "Button 5" }
local MOUSE_BUTTONS = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true }
local ROLE_NAMES = { HEALER = "Healer", CASTER = "Caster", MELEE = "Melee", TANK = "Tank" }

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function button(parent, text, width, onClick)
    local b, templated = API.SafeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    b:SetSize(width, 22)
    if not templated then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
        b:SetNormalFontObject("GameFontHighlight")
    end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- "Shift + Left click" / "Shift-R key", in the player's words.
function CCO.BindingText(row)
    if row.mouse then
        local mods, n = GRF.ClickCast.ParseMouse(row.mouse)
        if not n then return "?" end
        local parts = {}
        for _, m in ipairs(GRF.ClickCast.MODIFIERS) do
            if mods:find(m .. "-", 1, true) then parts[#parts + 1] = m:sub(1, 1):upper() .. m:sub(2) end
        end
        parts[#parts + 1] = MOUSE_NAMES[n]
        return table.concat(parts, " + ")
    end
    return tostring(row.key) .. " (key)"
end

--------------------------------------------------------------------------------
-- Ranks: the spellbook holds every rank as its own item (measured), though
-- Blizzard's UI shows only the top one. Items are grouped by the client's own
-- (localized) name at runtime: nothing is compared against a stored name.
--------------------------------------------------------------------------------

function CCO.Ranks(spellID)
    local okN, name = pcall(C_Spell.GetSpellName, spellID)
    if not (okN and type(name) == "string") then return {} end
    local found = {}
    local SB = rawget(_G, "C_SpellBook")
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
        return {}   -- no spellbook API: no rank choice, the row still works (highest rank)
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local okC, n = pcall(SB.GetNumSpellBookSkillLines)
    if not (okC and type(n) == "number") then return {} end
    for line = 1, n do
        local okL, li = pcall(SB.GetSpellBookSkillLineInfo, line)
        if okL and type(li) == "table" and li.itemIndexOffset and li.numSpellBookItems then
            for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local okB, item = pcall(SB.GetSpellBookItemInfo, i, bank)
                if okB and type(item) == "table" and item.name == name and item.spellID then
                    found[#found + 1] = item.spellID
                end
            end
        end
    end
    return found   -- spellbook order: lowest rank first
end

-- Next rank choice: highest (unpinned) -> rank 1 -> rank 2 ... -> highest.
local function cycleRank(row)
    local ranks = CCO.Ranks(row.spell)
    if #ranks < 2 then return end
    if not row.pinned then
        row.spell, row.pinned = ranks[1], true
    else
        local nextID
        for i, id in ipairs(ranks) do
            if id == row.spell then nextID = ranks[i + 1] end
        end
        if nextID then row.spell = nextID else row.spell, row.pinned = ranks[#ranks], nil end
    end
    GRF.ClickCast.Request()
end

local function rankText(row)
    if not row.spell then return "" end
    if not row.pinned then return "highest rank" end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, row.spell)
    return (ok and type(sub) == "string" and sub ~= "") and sub or "pinned"
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- A spell dropped from the cursor (the spellbook): GetCursorInfo()'s 4th
-- return is the spell ID (Blizzard's own click-binding UI reads it so).
local function takeCursorSpell(row)
    local kind, _, _, spellID = GetCursorInfo()
    if kind ~= "spell" or type(spellID) ~= "number" then return false end
    ClearCursor()
    row.spell, row.pinned = spellID, nil
    GRF.ClickCast.Request()
    return true
end

local function makeRow(i)
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(620, ROW_H - 2)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -150 - (i - 1) * ROW_H)
    r.bind = label(r, "")
    r.bind:SetWidth(140)
    r.bind:SetPoint("LEFT", r, "LEFT", 0, 0)

    local slot = CreateFrame("Button", nil, r)
    slot:SetSize(24, 24)
    slot:SetPoint("LEFT", r, "LEFT", 146, 0)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints(slot)
    slot.bg:SetColorTexture(0, 0, 0, 0.5)
    slot:RegisterForClicks("LeftButtonUp")
    slot:SetScript("OnReceiveDrag", function() if r.row and takeCursorSpell(r.row) then CCO.Refresh() end end)
    slot:SetScript("OnClick", function() if r.row and takeCursorSpell(r.row) then CCO.Refresh() end end)
    r.slot = slot

    r.spell = label(r, "")
    r.spell:SetWidth(170)
    r.spell:SetPoint("LEFT", slot, "RIGHT", 6, 0)

    r.rank = button(r, "", 96, function()
        if r.row then cycleRank(r.row); CCO.Refresh() end
    end)
    r.rank:SetPoint("LEFT", r.spell, "RIGHT", 4, 0)

    r.remove = button(r, "Remove", 70, function()
        if r.row then GRF.ClickCast.Remove(r.row); CCO.Refresh() end
    end)
    r.remove:SetPoint("LEFT", r.rank, "RIGHT", 6, 0)

    r.warn = label(r, "", "GameFontNormalSmall")
    r.warn:SetTextColor(1, 0.6, 0.2)
    r.warn:SetWidth(620)
    r.warn:SetPoint("TOPLEFT", r.bind, "BOTTOMLEFT", 0, -1)
    rows[i] = r
    return r
end

local function paintRow(r, row)
    r.row = row
    r.bind:SetText(CCO.BindingText(row))
    if row.spell then
        local okN, name = pcall(C_Spell.GetSpellName, row.spell)
        local okT, tex = pcall(C_Spell.GetSpellTexture, row.spell)
        r.spell:SetText((okN and name) or ("spell " .. row.spell))
        r.slot.icon:SetTexture(okT and tex or nil)
    else
        r.spell:SetText("|cff80ff80drag a spell here|r")
        r.slot.icon:SetTexture(nil)
    end
    r.rank:SetText(rankText(row))
    r.rank:SetShown(row.spell ~= nil and #CCO.Ranks(row.spell) > 1)
    local w = GRF.ClickCast.Warnings(row)
    if not row.spell then w = {} end
    r.warn:SetText(#w > 0 and ("  " .. table.concat(w, "; ")) or "")
    r:Show()
end

--------------------------------------------------------------------------------
-- Capturing a new binding: press a key, or click the capture button.
--------------------------------------------------------------------------------

local function stopCapture()
    capture.listening = false
    capture:EnableKeyboard(false)
    capture:SetText("New binding")
end

local function addBinding(bind, isMouse)
    stopCapture()
    GRF.ClickCast.Set(bind, isMouse, nil)
    CCO.Refresh()
end

local function startCapture()
    if InCombatLockdown() then
        status:SetText("|cffff8040Bindings can't be captured in combat.|r")
        return
    end
    capture.listening = true
    capture:EnableKeyboard(true)
    capture:SetPropagateKeyboardInput(false)
    capture:SetText("Press a key or click here (Esc: cancel)")
end

--------------------------------------------------------------------------------
-- Blizzard's side: its Mouseover Cast (casts on strangers: measured) and its
-- own click bindings (they take a click before ours: SecureUnitButton_OnClick).
--------------------------------------------------------------------------------

local function mouseoverCastOn()
    local ok, v = pcall(C_CVar.GetCVar, "enableMouseoverCast")
    return ok and v == "1"
end

local function blizzardText()
    local CB = rawget(_G, "C_ClickBindings")
    if not (CB and CB.GetProfileInfo) then return "" end
    local ok, profile = pcall(CB.GetProfileInfo)
    if not (ok and type(profile) == "table") then return "" end
    local lines, target = {}, false
    local T = Enum and Enum.ClickBindingType or {}
    local I = Enum and Enum.ClickBindingInteraction or {}
    for _, b in ipairs(profile) do
        if b.type == T.Interaction and b.actionID == I.Target and b.button then target = true end
        if (b.type == T.Spell or b.type == T.Macro or b.type == T.PetAction) and b.button then
            local okM, mods = pcall(GetStringFromModifiers, b.modifiers or 0)
            local what = b.type == T.Macro and "a macro" or "a spell"
            lines[#lines + 1] = ((okM and mods ~= "" and mods .. "-") or "") .. tostring(b.button) .. " (" .. what .. ")"
        end
    end
    local out = ""
    if #lines > 0 then
        out = "Blizzard's Click Cast Bindings also bind: " .. table.concat(lines, ", ")
            .. ". They act before ours on the same click."
    end
    if not target then
        out = out .. (out ~= "" and "\n" or "") .. "Blizzard's \"Target Unit Frame\" click binding is unbound: "
            .. "left-click won't target on unit frames."
    end
    return out
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function CCO.Refresh()
    if not page.built then return end
    header:SetText("Bindings for |cffffffff" .. (ROLE_NAMES[GRF.role] or "?") .. "|r (this character)")
    status:SetText(GRF.ClickCast.pending and "|cffffd040Changes apply when combat ends.|r" or "")
    mouseoverWarn:SetShown(mouseoverCastOn())
    local list = GRF.ClickCast.Rows()
    for i = 1, CCO.MAX_ROWS do
        local row = list[i]
        local r = rows[i] or makeRow(i)
        if row then paintRow(r, row) else r.row = nil; r:Hide() end
    end
    capture:SetEnabled(#list < CCO.MAX_ROWS)
    blizzList:SetText(blizzardText())
end

local function build()
    local title = label(content, "Click-casting", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    local help = label(content, "Keys work while you hover a group member's frame (never a stranger in the world); "
        .. "anywhere else they do their usual action-bar action. Clicks work on the frames. "
        .. "Drag a spell from your spellbook onto a row. Ranks: click to pin a lower one.", "GameFontHighlightSmall")
    help:SetWidth(600)
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    header = label(content, "", "GameFontNormal")
    header:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)

    capture = button(content, "New binding", 260, function(self, mouse)
        if self.listening then
            local n = MOUSE_BUTTONS[mouse]
            if n then addBinding(GRF.ClickCast.MouseBind(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), n), true) end
        else
            startCapture()
        end
    end)
    capture:RegisterForClicks("AnyUp")
    capture:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    capture:SetScript("OnKeyDown", function(self, key)
        if not self.listening or MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" then stopCapture() return end
        addBinding(GRF.ClickCast.KeyBind(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), key), false)
    end)
    capture:SetScript("OnHide", stopCapture)

    status = label(content, "", "GameFontNormalSmall")
    status:SetPoint("LEFT", capture, "RIGHT", 12, 0)

    mouseoverWarn = CreateFrame("Frame", nil, content)
    mouseoverWarn:SetSize(600, 22)
    mouseoverWarn:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -6)
    local mw = label(mouseoverWarn, "|cffff8040Blizzard's Mouseover Cast is on: it also casts on strangers under your cursor.|r", "GameFontNormalSmall")
    mw:SetPoint("LEFT", mouseoverWarn, "LEFT", 0, 0)
    local off = button(mouseoverWarn, "Turn it off", 100, function()
        pcall(C_CVar.SetCVar, "enableMouseoverCast", "0")
        CCO.Refresh()
    end)
    off:SetPoint("LEFT", mw, "RIGHT", 8, 0)

    blizzList = label(content, "", "GameFontHighlightSmall")
    blizzList:SetWidth(600)
    blizzList:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -150 - CCO.MAX_ROWS * ROW_H - 8)
end

page:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        build()
    end
    CCO.Refresh()
end)

-- Registered under the main page, once that exists (PLAYER_LOGIN, after Options.lua).
local reg = CreateFrame("Frame")
API.RegisterEvents(reg, { "PLAYER_LOGIN" })
reg:SetScript("OnEvent", function()
    local parent = GRF.Options and GRF.Options.category
    if parent and Settings and Settings.RegisterCanvasLayoutSubcategory then
        local ok, err = pcall(Settings.RegisterCanvasLayoutSubcategory, parent, page, page.name)
        if not ok then API.Fail("click-casting page", err) end
    end
end)

CCO._test = { page = page, rows = rows, capture = function() return capture end,
              blizzList = function() return blizzList end, mouseoverWarn = function() return mouseoverWarn end }
