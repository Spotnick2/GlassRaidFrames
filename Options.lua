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

-- Everything sits in a scroll child: the page outgrew the Settings canvas
-- (about 600 tall, no scrolling of its own; Codex on #39). GlassUnitFrames'
-- idiom: UIPanelScrollFrameTemplate exists on this client (porting guide), and
-- without it a plain ScrollFrame still clips and scrolls by wheel.
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(620, 600)
scroll:SetScrollChild(content)
if not scroll.ScrollBar then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local v = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(v)
    end)
end
-- The template shows its bar even with nothing to scroll: show it only when
-- the content is taller than the canvas.
if scroll.ScrollBar then
    scroll:HookScript("OnScrollRangeChanged", function(self, _, yrange)
        self.ScrollBar:SetShown((yrange or self:GetVerticalScrollRange()) > 0)
    end)
end
-- Keep the content as wide as the visible area.
scroll:SetScript("OnSizeChanged", function(self, w)
    if type(w) == "number" and w > 0 then content:SetWidth(w) end
end)

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

-- As tall as it wraps: a fixed one-line slot lets a two-line note run into the
-- next line (GlassUnitFrames' #96).
local function note(text)
    local fs = label(text, "GameFontHighlightSmall")
    fs:SetWidth(520)
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h ~= h or h <= 0 then h = 14 end
    place(fs, math.max(18, math.ceil(h) + 4), 4)
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

-- Radios across one line, after a title: "Glass  (o) Pearl  (o) Clean  (o) Classic".
-- `step` is the room per choice (100 by default).
local function radioRow(title, options, get, set, step)
    place(label(title), 0, 8)
    local group = {}
    for i, o in ipairs(options) do
        local rb = checkButton(o[2], true)
        rb.value = o[1]
        rb:SetScript("OnClick", function()
            set(o[1])
            controls.refreshAll()
        end)
        rb:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + 60 + (i - 1) * (step or 100), col.y + 3)
        group[#group + 1] = rb
    end
    col.y = col.y - 22
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

    local casting = button("Click-casting", 180, function()
        closeSettings()
        GRF.ClickCastOptions.Open()
    end)
    place(casting, 36, 4)
    controls.clickcast = casting
    controls.clickcastOthers = checkbox("Click-cast on other unit frames too (Blizzard's and other addons')",
        function() return GRF.ClickCast.Everywhere() end, S.SetClickCastOthers)
    note("Clicks and hover keys cast on whoever a hovered frame shows, strangers and pets included: a heal on a friend, a harmful spell on an enemy.")
    controls.keysAnywhere = checkbox("Keys work anywhere under the cursor, the world included (this role)",
        function() return GRF.ClickCast.Anywhere() end, S.SetKeysAnywhere)
    note("Off: keys cast only on a hovered frame, so nobody walking under the cursor takes your heal (the healer's default).")

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

    -- The group layout (#69): built once, so switching takes /reload.
    header("Layout")
    controls.groupLayout = checkbox("One grid sized by the group (takes effect after /reload)",
        function() return GRF.db.groupLayout ~= false end, S.SetGroupLayout)
    note("A row up to 5, then columns of 5. Off: the eight-group grid, with the position it had.")
    controls.layoutHud = checkbox("Centred above the action bars (this role; off: at the side)",
        function() return GRF.Layout.ModeOf(GRF.role) == "hud" end,
        function(on) S.SetLayoutMode(on and "hud" or "side") end)

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
    controls.pets = checkbox("Show pets, beside or under the group frames (this role)",
        function() return GRF.Profile() and GRF.Profile().showPets end, S.SetShowPets)
    controls.solo = checkbox("Show your own frame when not in a group",
        function() return GRF.db.showSolo end, S.SetShowSolo)
    controls.blizzard = checkbox("Hide Blizzard's party and raid frames",
        function() return GRF.db.hideBlizzard end, S.SetHideBlizzard)
    note("Showing Blizzard's frames again takes a /reload.")

    -- The glass (#37, #38): saved now, built after /reload.
    header("Look")
    -- Following Glass UI (#67): said here, and the radios are off for the
    -- session (the decision is made once, at load).
    local suiteStatus = GRF.SuiteStatus()
    if suiteStatus then controls.suiteNote = note(suiteStatus) end
    controls.look = radioRow("Glass", { { "pearl", "Pearl" }, { "clean", "Clean" }, { "classic", "Classic" } },
        function() return GRF.db.look or GRF.DEFAULT_LOOK end, S.SetLook)
    controls.body = radioRow("Body", { { "clear", "Clear" }, { "smoked", "Smoked" } },
        function() return GRF.db.glassBody or "clear" end, S.SetBody)
    if GRF.following then
        for _, group in ipairs({ controls.look, controls.body }) do
            -- Disabled, and seen to be: the label is our own FontString and
            -- the radio art has no disabled look (measured: both stayed bright).
            for _, rb in ipairs(group) do
                rb:SetEnabled(false)
                rb:SetAlpha(0.5)
                rb.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
    note("The look takes effect after /reload.")
    -- Where the suite look is set (and Follow turned on or off), when Glass UI
    -- can open it.
    local openGlassUI = GRF.GlassUIOpener()
    if openGlassUI then
        controls.glassUI = button("Glass UI settings", 160, openGlassUI)
        place(controls.glassUI, 30, 4)
    end

    -- Names (#18): one style for everyone, a nickname per person (by GUID);
    -- account-wide. Last on the page: the nickname list grows downwards.
    header("Names")
    controls.names = radioRow("Show", { { "first", "First name" }, { "initial", "First + initial" }, { "full", "Full name" } },
        function() return GRF.db.nameStyle or "first" end, S.SetNameStyle, 140)
    note("A nickname replaces one person's name on the frames, on all your characters.")
    local box, templated = API.SafeFrame("EditBox", content, "InputBoxTemplate", "Left")
    box:SetSize(160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    if not templated then
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(box)
        bg:SetColorTexture(0, 0, 0, 0.5)
    end
    place(box, 0, 14)   -- the template's left cap sits outside the box
    controls.nickBox = box
    local status = label("", "GameFontNormalSmall")
    controls.nickStatus = status
    local function apply(nick)
        local ok, why = S.SetTargetNickname(nick)
        controls.refreshAll()
        if ok then
            box:SetText("")
            box:ClearFocus()
        end
        status:SetText(ok and "" or ("|cffff8040" .. why .. "|r"))
    end
    local set = button("Nickname your target", 170, function() apply(box:GetText()) end)
    set:SetPoint("LEFT", box, "RIGHT", 10, 0)
    controls.nickSet = set
    local clear = button("Clear", 70, function() apply("") end)
    clear:SetPoint("LEFT", set, "RIGHT", 6, 0)
    controls.nickClear = clear
    status:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    box:SetScript("OnEnterPressed", function() apply(box:GetText()) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    col.y = col.y - 30

    -- The list: one row per nickname, built as needed. The page's height
    -- follows it, so the scroll bar appears once it outgrows the canvas.
    local listTop, rows = col.y, {}
    controls.nickRows = rows
    local empty = label("|cff888888No nicknames yet.|r", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + 8, listTop - 4)
    local function row(i)
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(480, 22)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + 8, listTop - (i - 1) * 22)
        r.text = Options.Label(r, "", "GameFontHighlight")
        r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.remove = Options.Button(r, "Remove", 80, function()
            S.SetNickname(r.guid, nil)
            controls.refreshAll()
        end)
        r.remove:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        rows[i] = r
        return r
    end
    controls[#controls + 1] = function()
        local list = S.Nicknames()
        for i, e in ipairs(list) do
            local r = rows[i] or row(i)
            r.guid = e.guid
            r.text:SetText(e.name .. "  |cff888888->|r  |cffffffff" .. e.nick .. "|r")
            r:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#list == 0)
        content:SetHeight(-(listTop - math.max(1, #list) * 22) + 16)
    end
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
    if GRF.IndicatorOptions then GRF.IndicatorOptions.Register(category) end
end

-- Open the panel; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

local reg = CreateFrame("Frame")
API.RegisterEvents(reg, { "PLAYER_LOGIN" })
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, controls = controls, scroll = scroll, content = content }
