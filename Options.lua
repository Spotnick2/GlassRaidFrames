-- Options.lua: the settings panel under Game Menu > Options > AddOns > Glass
-- Raid Frames (/grf options). GlassUnitFrames' idiom: a canvas panel
-- registered with Retail's Settings framework (RegisterCanvasLayoutCategory +
-- RegisterAddOnCategory, at PLAYER_LOGIN), template check and radio buttons
-- with our own art only as a fallback, no UIDropDownMenu (choices are radio
-- groups). Built on first show and re-synced from the current state on every
-- show, so a change made with /grf never leaves it stale. Every control goes
-- through GlassRaidFrames.Settings, the helpers /grf uses.

GlassRaidFrames = GlassRaidFrames or {}
local GRF = GlassRaidFrames
local API = GRF.API
local Options = {}
GRF.Options = Options

local panel = CreateFrame("Frame", "GlassRaidFramesOptions")
panel.name = "Glass Raid Frames"
-- Hidden until Settings shows it: a frame born shown and parentless can be
-- reparented into a visible canvas and shown without OnShow firing, which
-- would leave the page blank (code review).
panel:Hide()
local controls = {}      -- refresh callbacks, run on every OnShow
local refreshing = false -- set while syncing controls, so a slider's SetValue doesn't save
local category

local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local CHECK_ART = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}
local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

-- Shared with the Click-casting page (one copy of the fallback styling).
function Options.Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end
local function label(text, template) return Options.Label(content, text, template) end

local col = { x = 16, y = -16 }
local function place(region, height, indent)
    region:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
end

local function header(text)
    col.y = col.y - 6
    place(label(text, "GameFontNormalLarge"), 26)
end

local function note(text)
    local fs = label(text, "GameFontHighlightSmall")
    fs:SetWidth(520)
    place(fs, 18, 4)
    return fs
end

function Options.Button(parent, text, width, onClick)
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
local function button(text, width, onClick) return Options.Button(content, text, width, onClick) end

local function checkButton(text, radio)
    local cb, templated = API.SafeFrame("CheckButton", content, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate", "text")
    if not templated then
        if radio then
            cb:SetSize(16, 16)
            cb:SetNormalTexture(RADIO_ART)
            cb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
            cb:SetCheckedTexture(RADIO_ART)
            cb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
            cb:SetHighlightTexture(RADIO_ART)
            cb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
        else
            cb:SetSize(24, 24)
            cb:SetNormalTexture(CHECK_ART.normal)
            cb:SetPushedTexture(CHECK_ART.pushed)
            cb:SetHighlightTexture(CHECK_ART.highlight)
            cb:SetCheckedTexture(CHECK_ART.checked)
        end
    elseif not radio then
        cb:SetSize(24, 24)
    end
    local fs = label(text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs
    return cb
end

local function radios(options, get, set)
    local group = {}
    for _, o in ipairs(options) do
        local rb = checkButton(o[2], true)
        rb.value = o[1]
        -- Re-sync the whole panel either way: a refused choice snaps back.
        rb:SetScript("OnClick", function()
            set(o[1])
            controls.refreshAll()
        end)
        place(rb, 22, 8)
        group[#group + 1] = rb
    end
    controls[#controls + 1] = function()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    return group
end

-- Hand-built slider (GlassUnitFrames' idiom): label and value on one line,
-- the track under it. Whole numbers.
local SLIDER_W = 240
local function slider(text, min, max, get, set)
    local fs = label(text)
    local value = label("")
    value:SetPoint("LEFT", fs, "LEFT", SLIDER_W + 12, 0)
    place(fs, 18, 4)
    local s = CreateFrame("Slider", nil, content)
    s:SetSize(SLIDER_W, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    place(s, 26, 8)
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        value:SetText(tostring(v))
        if refreshing then return end
        set(v)
    end)
    controls[#controls + 1] = function()
        local v = get()
        s:SetValue(v)
        value:SetText(tostring(v))
    end
    return s
end

local function checkbox(text, get, set)
    local cb = checkButton(text, false)
    place(cb, 28, 4)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        controls.refreshAll()
    end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local ROLE_NAMES = { HEALER = "Healer", CASTER = "Caster", MELEE = "Melee", TANK = "Tank" }
local SOURCE_TEXT = { talents = "from your talents", class = "your class default", manual = "picked by hand" }

local function closeSettings()
    -- Through the panel's own Close (it commits or prompts for other pages'
    -- changes), not a bare hide: the mover would sit behind the window.
    -- Close(true) = skipTransitionBackToOpeningPanel: plain Close() goes back
    -- to the Game Menu, whose Esc handlers call the protected SpellStopCasting,
    -- which the client then blames on us (ADDON_ACTION_FORBIDDEN, measured in
    -- game; Forever's Blizzard_SettingsPanel.lua ExitWithCommit).
    local sp = rawget(_G, "SettingsPanel")
    if sp and type(sp.Close) == "function" then pcall(sp.Close, sp, true)
    elseif sp and rawget(_G, "HideUIPanel") then pcall(HideUIPanel, sp) end
end

local function build()
    local S = GRF.Settings
    place(label("Glass Raid Frames", "GameFontNormalHuge"), 34)

    header("Role")
    note("Every setting below the role is kept per role: the healer layout and the damage layouts don't move each other.")
    local current = note("")
    controls[#controls + 1] = function()
        current:SetText("Now: |cffffffff" .. (ROLE_NAMES[GRF.role] or "?") .. "|r ("
            .. (SOURCE_TEXT[GRF.roleSource] or "?") .. ")")
    end
    controls.role = radios({
        { "auto", "Automatic (the talent tree with the most points)" },
        { "HEALER", "Healer" }, { "CASTER", "Caster" }, { "MELEE", "Melee" }, { "TANK", "Tank" },
    }, function() return GRF.char.role end, S.SetRole)

    header("Position")
    note("For the current role. Unlocking closes this window; drag the frames, right-click to lock.")
    local unlock = button("Unlock frames", 160, function()
        if S.Unlock() then closeSettings() end
    end)
    place(unlock, 0, 4)
    Options._test.unlock = unlock
    local reset = button("Reset position", 160, S.ResetPosition)
    reset:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
    col.y = col.y - 30

    header("Size")
    note("Each frame's size, for the current role. The frames resize out of combat.")
    local H = GRF.Header
    -- A drag fires a value change per step: resize once it pauses (0.1 s), not
    -- 40 tiles plus an announcement to other addons on every tick.
    -- Each tick SAVES at once, to the role being edited; only the resize waits
    -- for the drag to pause, and it reads whatever is saved then (a role switch
    -- or a Default size meanwhile can't be overwritten: Codex review).
    local scheduled = false
    local function later(w, h)
        S.SaveSize(GRF.role, w, h)
        if scheduled then return end
        scheduled = true
        C_Timer.After(0.1, function()
            scheduled = false
            S.ApplySize()
        end)
    end
    controls.width = slider("Width", H.MIN_W, H.MAX_W, function() return (H.TileSize()) end,
        function(v) later(v, nil) end)
    controls.height = slider("Height", H.MIN_H, H.MAX_H, function() return select(2, H.TileSize()) end,
        function(v) later(nil, v) end)
    place(button("Default size", 160, function()
        S.SetSize(nil, nil)
        controls.refreshAll()
    end), 30, 4)

    header("Frames")
    controls.pets = checkbox("Show pets, under the group frames (this role)",
        function() return GRF.Profile() and GRF.Profile().showPets end, S.SetShowPets)
    controls.solo = checkbox("Show your own frame when not in a group",
        function() return GRF.db.showSolo end, S.SetShowSolo)
    controls.blizzard = checkbox("Hide Blizzard's party and raid frames",
        function() return GRF.db.hideBlizzard end, S.SetHideBlizzard)
    note("Showing Blizzard's frames again takes a /reload.")
end

function controls.refreshAll()
    refreshing = true
    for i, fn in ipairs(controls) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("options control " .. i, err) end   -- shows in /grf failures
    end
    refreshing = false
end

panel:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        build()
    end
    controls.refreshAll()
end)

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local function register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    Options.category = category
    -- The Click-casting page, under this one: registered here, in order,
    -- rather than by its own PLAYER_LOGIN handler (no ordering between frames).
    if GRF.ClickCastOptions then GRF.ClickCastOptions.Register(category) end
end

-- Open the panel; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

local reg = CreateFrame("Frame")
API.RegisterEvents(reg, { "PLAYER_LOGIN" })
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, controls = controls }
