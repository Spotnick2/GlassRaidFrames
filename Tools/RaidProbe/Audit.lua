-- RaidProbe, the taint and combat-lockdown audit (#78; docs/FOREVER-PROBE.md
-- section 18): what the fixes and the test harness assume, measured in game.
--   18.1 the lockdown's order around the regen events      /fp steps raid lockdown
--   18.2 protection by parent (a tile's body, the holder)   /fp steps raid protected
--   18.3 identity values in a group, in combat              /fp steps raid identity
--   18.4 a raid night: reflows and aura rebinds per roster  /fp raid reflows
--   18.5 a hovered tile that hides                          /fp steps raid hidehover
--   18.6 a drag that combat interrupts                      /fp steps raid dragcombat, dragcombatlegacy
--   18.7 a cursor that doesn't move while the keys change   /fp steps raid stillcursor
--   18.8 the harness's own assumptions on protected calls   /fp steps raid assumptions
-- The same module as RaidProbe.lua (ForeverProbe returns it again by name).
-- Blocked actions are the host's baseline's lines, read after the /reload;
-- Glass Raid Frames' own record of them (GRF.blocked, #78 F4) is read too.
-- Nothing here reads Blizzard's frames by anything but rawget, and every
-- client call that may be missing or throw goes through try() or pcall.

local _, NS = ...
local Probe = ForeverProbe:Module("RaidProbe", { api = 1, cmd = "raid" })

local function say(msg) Probe:Say(tostring(msg)) end
local function show(v) return Probe.Show(v, true) end
local function try(label, fn, ...) return Probe:Try(label, fn, ...) end

local issecret = rawget(_G, "issecretvalue")
local function secret(v) return issecret ~= nil and issecret(v) == true end
local function addon() return rawget(_G, "GlassRaidFrames") end

-- A call's first return as text: "<secret>", "THREW", "MISSING" or its value.
local function kind(fn, ...)
    if type(fn) ~= "function" then return "MISSING" end
    local ok, v = pcall(fn, ...)
    if not ok then return "THREW" end
    if secret(v) then return "<secret>" end
    return show(v)
end

local A = {}   -- the audit's state

--------------------------------------------------------------------------------
-- 18.1 The lockdown's order. The harness's enterCombat and the position
-- setters (#78 F2) assume InCombatLockdown() is already true inside a
-- PLAYER_REGEN_DISABLED handler, and off inside PLAYER_REGEN_ENABLED's (the
-- queue's retry, F3, covers the other case). Logged at every fight.
--------------------------------------------------------------------------------

A.regen = { disabled = {}, enabled = {} }   -- lockdown value -> count
local regenEv = CreateFrame("Frame")
regenEv:SetScript("OnEvent", function(_, event)
    local locked = InCombatLockdown() == true
    local t = event == "PLAYER_REGEN_DISABLED" and A.regen.disabled or A.regen.enabled
    t[locked] = (t[locked] or 0) + 1
    say(string.format("regen: %s with InCombatLockdown()=%s", event, tostring(locked)))
end)
Probe:RegisterEvents(regenEv, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })

local function regenReset() A.regen.disabled, A.regen.enabled = {}, {} return true end
local function regenText()
    local function one(t) return string.format("lockdown on=%d off=%d", t[true] or 0, t[false] or 0) end
    return "DISABLED: " .. one(A.regen.disabled) .. "; ENABLED: " .. one(A.regen.enabled)
end
-- PASS when every DISABLED saw the lockdown on and no ENABLED saw it on, over
-- at least `fights` fights.
local function regenCheck(fights)
    return function()
        local d, e = A.regen.disabled, A.regen.enabled
        local nd, ne = (d[true] or 0) + (d[false] or 0), (e[true] or 0) + (e[false] or 0)
        if nd < fights or ne < fights then
            return false, "fights seen: " .. math.min(nd, ne) .. " of " .. fights, regenText()
        end
        return (d[false] or 0) == 0 and (e[true] or 0) == 0, regenText()
    end
end

Probe:Steps("lockdown", {
    rev = 1,
    title = "The lockdown's order around the regen events (#78, 18.1)",
    { text = "Out of combat. Logging InCombatLockdown() inside every PLAYER_REGEN event from now on.",
      auto = true, run = regenReset },
    { text = "Pull a mob and let the fight end. Then Next.", check = regenCheck(1) },
    { text = "Two more fights (different mobs; your pet pulling counts). Then Next.", check = regenCheck(3) },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.2 Protection by parent: does an AuraContainer child make a tile's body
-- protected? The glide moves bodies; the layout box carries the mover; the
-- holder parents secure buttons (protected, by design).
--------------------------------------------------------------------------------

local function protectedReport()
    local G = addon()
    if not (G and G.Header and G.Header.container) then say("protected: Glass Raid Frames isn't built") return false end
    local cell = G.Header.children and G.Header.children[1]
    local container
    for _, e in pairs(cell and cell.grfInd and cell.grfInd.byKey or {}) do container = e.c break end
    local list = {
        { "a cell", cell }, { "its body", cell and cell.body }, { "an aura container on the body", container },
        { "GlassRaidFramesGrid", rawget(_G, "GlassRaidFramesGrid") },
        { "GlassRaidFramesRaidPets", rawget(_G, "GlassRaidFramesRaidPets") },
        { "GlassRaidFramesPartyPets (the holder)", rawget(_G, "GlassRaidFramesPartyPets") },
        { "GlassRaidFramesLayoutBox", rawget(_G, "GlassRaidFramesLayoutBox") },
        { "GlassRaidFramesContainer (legacy)", rawget(_G, "GlassRaidFramesContainer") },
        { "GlassRaidFramesKeyOwner", rawget(_G, "GlassRaidFramesKeyOwner") },
        { "GlassRaidFramesKeyHeader", rawget(_G, "GlassRaidFramesKeyHeader") },
        { "GlassRaidFramesMover", rawget(_G, "GlassRaidFramesMover") },
    }
    A.bodyProtected = nil
    for _, e in ipairs(list) do
        local f = e[2]
        if f then
            local ok, prot, explicit = pcall(f.IsProtected, f)
            say(string.format("protected: %s -> %s%s (combat=%s)", e[1], ok and show(prot) or "ERR",
                (ok and explicit) and ", explicitly" or "", show(InCombatLockdown())))
            if e[1] == "its body" and ok then A.bodyProtected = prot == true end
        else
            say("protected: " .. e[1] .. " -> absent")
        end
    end
    return true
end
local function bodyCheck()
    return A.bodyProtected == false, "body protected=" .. show(A.bodyProtected)
end

Probe:Steps("protected", {
    rev = 1,
    title = "Protection by parent: a tile's body and its aura containers (#78, 18.2)",
    { text = "Out of combat, Glass Raid Frames built, indicators on. Reading IsProtected() of its frames.",
      auto = true, run = protectedReport, check = bodyCheck },
    { text = "Pull a mob. In combat, press Run: the answers shouldn't change.", button = "Read in combat",
      run = protectedReport, check = bodyCheck },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.3 Identity values in a group, in combat (item 5 was a raid of 2): each
-- UnitName return on its own, GetUnitName (Blizzard's, Lua on Forever: THREW
-- on a secret surname is what #78 F1 is about), class, GUID, roles, leader,
-- UnitIsUnit, UnitExists; and what the tiles show.
--------------------------------------------------------------------------------

local function groupUnits()
    local list = { "player" }
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
    else
        for i = 1, 4 do if UnitExists("party" .. i) then list[#list + 1] = "party" .. i end end
    end
    if UnitExists("target") then list[#list + 1] = "target" end
    return list
end

local function identityReport()
    local sep = rawget(_G, "Constants")
    sep = type(sep) == "table" and rawget(sep, "CharacterNameSeparatorConsts")
    sep = type(sep) == "table" and rawget(sep, "CHARACTERNAME_SURNAME_SEPARATOR")
    say(string.format("identity: combat=%s IsInRaid=%s GetNumGroupMembers=%s surname separator=%s",
        show(InCombatLockdown()), kind(IsInRaid), kind(GetNumGroupMembers), show(sep)))
    local secretNames = 0
    for _, u in ipairs(groupUnits()) do
        local okN, first, sur = pcall(UnitName, u)
        local okC, _, class = pcall(UnitClass, u)
        if okN and (secret(first) or secret(sur)) then secretNames = secretNames + 1 end
        local function part(ok, v) if not ok then return "THREW" end if secret(v) then return "<secret>" end return show(v) end
        say(string.format("  %s: UnitName=%s / %s GetUnitName=%s class=%s guid=%s role=%s leader=%s isTarget=%s exists=%s",
            u, part(okN, first), part(okN, sur), kind(GetUnitName, u, false), part(okC, class), kind(UnitGUID, u),
            kind(UnitGroupRolesAssigned, u), kind(UnitIsGroupLeader, u), kind(UnitIsUnit, u, "target"), kind(UnitExists, u)))
    end
    -- The tiles: a secret name is rendered by the client, never a failure.
    local G = addon()
    local tiles, secretTiles = 0, 0
    local failure = G and G.paintFailures and G.paintFailures["painter name"]
    for _, c in ipairs(G and G.Header and G.Header.AllChildren and G.Header.AllChildren() or {}) do
        if c.unit and c:IsShown() and c.nameText then
            tiles = tiles + 1
            local okT, t = pcall(c.nameText.GetText, c.nameText)
            if okT and secret(t) then secretTiles = secretTiles + 1 end
        end
    end
    say(string.format("  tiles shown=%d with a secret name=%d; units with a secret UnitName=%d; 'painter name' failure=%s",
        tiles, secretTiles, secretNames, show(failure)))
    A.identity = { tiles = tiles, secretTiles = secretTiles, secretNames = secretNames, failure = failure }
    return failure == nil, "painter name failure=" .. show(failure), "secret names=" .. secretNames
end

Probe:Steps("identity", {
    rev = 1,
    title = "Identity values in a group, in combat (#78, 18.3)",
    { text = "In a group (the bigger, the better), out of combat, a member targeted. Reading each unit's name, class, GUID, role and more.",
      auto = true, run = identityReport },
    { text = "Pull a mob. In combat, press Run.", button = "Read in combat", run = identityReport },
    { text = "Still in combat: do the tiles show every member's right name (compare with the raid roster)?",
      ask = true, screenshot = "identity in combat" },
    { text = "Still in combat, if you can: have a member leave and come back, or swap groups. Then press Run.",
      button = "Read again", run = identityReport },
    { text = "Do the tiles still show the right names (no tile keeps someone who moved)?",
      ask = true, screenshot = "identity after a roster change" },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.4 A raid night: every header reflow re-sets each shown child's unit
-- (#78 F7), and each change repaints the tile and rebinds its aura
-- containers. /fp raid reflows counts them per GROUP_ROSTER_UPDATE; again
-- for the totals. The hooks stay (they count nothing while off).
--------------------------------------------------------------------------------

local reflows   -- nil = off
local function reflowsLine()
    if not reflows then return end
    say(string.format("reflows: roster updates=%d unit changes=%d (same token=%d, new token=%d) aura rebinds=%d",
        reflows.rosters, reflows.changes, reflows.same, reflows.changed, reflows.rebinds))
end
local reflowEv = CreateFrame("Frame")
reflowEv:SetScript("OnEvent", function()
    if not reflows then return end
    reflows.rosters = reflows.rosters + 1
    C_Timer.After(0, reflowsLine)   -- after the headers' own update
end)
Probe:RegisterEvents(reflowEv, { "GROUP_ROSTER_UPDATE" })

local function toggleReflows()
    if reflows then
        reflowsLine()
        reflows = nil
        say("reflows: off")
        return
    end
    local G = addon()
    if not (G and G.Header and G.Header.AllChildren) then say("reflows: Glass Raid Frames isn't built") return end
    reflows = { rosters = 0, changes = 0, same = 0, changed = 0, rebinds = 0 }
    for _, c in ipairs(G.Header.AllChildren()) do
        if not c.raidProbeReflow then
            c.raidProbeReflow = true
            c:HookScript("OnAttributeChanged", function(self, name, value)
                if name ~= "unit" or not reflows then return end
                reflows.changes = reflows.changes + 1
                if value == self.raidProbeUnit then reflows.same = reflows.same + 1 else reflows.changed = reflows.changed + 1 end
                self.raidProbeUnit = value
            end)
            local prev = c.onUnitChanged   -- Glass Raid Frames' own field: the aura rebind
            if type(prev) == "function" then
                c.onUnitChanged = function(self, unit)
                    if reflows then reflows.rebinds = reflows.rebinds + 1 end
                    return prev(self, unit)
                end
            end
        end
        c.raidProbeUnit = c:GetAttribute("unit")
    end
    say("reflows: on. Each roster update logs the unit changes it caused; /fp raid reflows again for the totals")
end
Probe:Command("reflows", toggleReflows, "toggle: count unit changes and aura rebinds per roster update (a raid night, #78)")

--------------------------------------------------------------------------------
-- 18.5 A hovered tile that hides (#78 F5): does OnLeave fire; the rim and the
-- tooltip afterwards, and another frame's tooltip left alone.
--------------------------------------------------------------------------------

local function hoverHooks()
    local G = addon()
    if not (G and G.Header and G.Header.AllChildren) then say("hidehover: Glass Raid Frames isn't built") return false end
    A.hover = { leaves = 0, hides = 0 }
    for _, c in ipairs(G.Header.AllChildren()) do
        if not c.raidProbeHover then
            c.raidProbeHover = true
            c:HookScript("OnEnter", function(self, motion)
                if A.hover then A.hover.entered, A.hover.enterMotion = self, motion end
            end)
            c:HookScript("OnLeave", function(self, motion)
                if A.hover then A.hover.leaves = A.hover.leaves + 1; A.hover.leaveMotion = motion end
            end)
            c:HookScript("OnHide", function(self)
                if A.hover then A.hover.hides = A.hover.hides + 1; A.hover.lastHide = self end
            end)
        end
    end
    return true
end

-- The last hidden tile: its rim out, its tooltip state cleared, the tooltip
-- not owned by it any more.
local function hiddenTileState()
    local h = A.hover or {}
    local t = h.lastHide
    local tt = rawget(_G, "GameTooltip")
    local okR, rim = pcall(function() return t.hoverRim:GetAlpha() end)
    local okO, owned = pcall(function() return tt:IsOwned(t) end)
    rim = okR and rim or nil
    owned = okO and owned or nil
    say(string.format("hidehover: hides=%d leaves=%d (last leave motion=%s) hidden tile=%s rim alpha=%s UpdateTooltip=%s "
        .. "tooltip owned by it=%s shown=%s combat=%s", h.hides or 0, h.leaves or 0, show(h.leaveMotion),
        show(t and t:GetName()), show(rim), show(t and rawget(t, "UpdateTooltip") ~= nil), show(owned),
        show(tt and tt:IsShown()), show(InCombatLockdown())))
    return t ~= nil and rim == 0 and not owned, "rim=" .. show(rim), "owned=" .. show(owned), "leaves=" .. (h.leaves or 0)
end

-- Another frame's tooltip, still up after an unrelated tile hid.
local function otherTooltipState()
    local tt = rawget(_G, "GameTooltip")
    local okS, shown = pcall(function() return tt:IsShown() end)
    local okO, owner = pcall(function() return tt:GetOwner() end)
    say(string.format("hidehover: tooltip shown=%s owner=%s", okS and show(shown) or "ERR",
        okO and show(owner and owner.GetName and owner:GetName()) or "ERR"))
    return okS and shown == true, "shown=" .. (okS and show(shown) or "ERR")
end

Probe:Steps("hidehover", {
    rev = 1,
    title = "A hovered tile that hides (#78, 18.5)",
    { text = "Out of combat, in a party of two. Hooking the tiles' OnEnter, OnLeave and OnHide.", auto = true, run = hoverHooks },
    { text = "Hover your partner's tile and hold the cursor there. Have them leave the group. Then Next, without moving the mouse.",
      check = hiddenTileState },
    { text = "Invite them back. Hover YOUR tile (its tooltip up) and hold still; have them leave again. Then Next.",
      check = otherTooltipState },
    { text = "Invite them back. Pull a mob; in combat hover their tile, hold still, and have them leave. Then Next.",
      check = hiddenTileState },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.6 A drag that combat interrupts (#78 F2): the spot is saved as the
-- lockdown begins, nothing protected is touched, and the block is placed
-- there, and announced, when combat ends. One procedure for the group layout,
-- one for the legacy grid and its pets.
--------------------------------------------------------------------------------

local function spots()
    local G = addon()
    local prof = G and G.Profile and G.Profile()
    local mode = (G and G.layoutOn and G.Layout and G.role) and G.Layout.ModeOf(G.role) or "legacy"
    local lp = prof and type(prof.layoutPos) == "table" and prof.layoutPos[mode]
    local function xy(p) return type(p) == "table" and (show(p.x) .. "," .. show(p.y)) or "none" end
    local L = G and G.Layout and G.Layout._test and G.Layout._test.L
    return { mode = mode, layout = xy(lp), pos = xy(prof and prof.pos), petPos = xy(prof and prof.petPos),
             blocked = G and G.blockedTotal or 0, live = L ~= nil and L.live ~= nil }
end
local function spotsLine(label, s)
    say(string.format("drag: %s mode=%s layoutPos=%s pos=%s petPos=%s blocked=%d live=%s", label, s.mode, s.layout, s.pos,
        s.petPos, s.blocked, tostring(s.live)))
end
local function dragSetup()
    A.drag = spots()
    spotsLine("before", A.drag)
    return true
end
-- `field` is the save the interrupted drag must have written.
local function dragCheck(field)
    return function()
        local s = spots()
        spotsLine("after", s)
        local before = A.drag or {}
        local saved = s[field] ~= "none" and s[field] ~= before[field]
        return saved and s.blocked == (before.blocked or 0) and not s.live,
            field .. " " .. show(before[field]) .. " -> " .. show(s[field]), "blocked +" .. (s.blocked - (before.blocked or 0)),
            "live=" .. tostring(s.live)
    end
end
local function placedCheck()
    local G = addon()
    local s = G and G.LayoutState and G.LayoutState()
    say("drag: placed at " .. (s and string.format("l=%.1f b=%.1f base=%.1f mode=%s", s.l, s.b, s.base, s.mode) or "nil"))
    return s ~= nil and not InCombatLockdown(), "state base=" .. show(s and s.base)
end

Probe:Steps("dragcombat", {
    rev = 1,
    title = "A drag that combat interrupts: the group layout (#78, 18.6)",
    { text = "Out of combat, in a party, the group layout on (/grf layout). Reading the saved spots.", auto = true, run = dragSetup },
    { text = "Type /grf unlock, press and HOLD the grid's mover, and have your partner pull a mob so combat starts while you "
        .. "hold it. Release once in combat. Then Next.", check = dragCheck("layout") },
    { text = "Let the fight end. Then Next: the grid should sit where you left it.", check = placedCheck },
    { text = "Does the grid sit where you dragged it?", ask = true, screenshot = "grid after an interrupted drag" },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

Probe:Steps("dragcombatlegacy", {
    rev = 1,
    title = "A drag that combat interrupts: the legacy grid and its pets (#78, 18.6)",
    { text = "Out of combat, in a party, the legacy grid (/grf layout off, then /reload), pets shown (/grf pets). Reading the saved spots.",
      auto = true, run = dragSetup },
    { text = "Type /grf unlock, press and HOLD the grid's mover, and have your partner pull a mob so combat starts while you "
        .. "hold it. Release once in combat. Then Next.", check = dragCheck("pos") },
    { text = "Let the fight end. Then Next.", check = placedCheck },
    { text = "Out of combat: reading the spots again, then the pets.", auto = true, run = dragSetup },
    { text = "Type /grf unlock, press and HOLD the pets' mover, and have your partner pull again. Release once in combat. Then Next.",
      check = dragCheck("petPos") },
    { text = "Let the fight end. Then Next.", check = placedCheck },
    { text = "Do the grid and the pets sit where you dragged them?", ask = true, screenshot = "legacy grid and pets after interrupted drags" },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.7 A cursor that doesn't move while the keys change (the accepted gap):
-- a key-list change clears the hovered frame's bindings and waits for the
-- next OnEnter, whose secure pre-snippet needs `motion`.
--------------------------------------------------------------------------------

local function keyBindings(label)
    local G = addon()
    local keys = G and G.ClickCast and G.ClickCast._test and G.ClickCast._test.keyButtons or {}
    local parts = {}
    for key in pairs(keys) do parts[#parts + 1] = key .. "=" .. kind(GetBindingAction, key, true) end
    table.sort(parts)
    local h = A.hover or {}
    say(string.format("stillcursor: %s live bindings: %s | last OnEnter motion=%s", label,
        #parts > 0 and table.concat(parts, " ") or "no key buttons", show(h.enterMotion)))
    return #parts
end
local function switchRole(to)
    return function()
        local G = addon()
        if not (G and G.Settings and G.Settings.SetRole) then return false, "no Glass Raid Frames" end
        local ok = G.Settings.SetRole(to)
        return ok and keyBindings("after /grf role " .. to .. " under the cursor") >= 0, "role " .. show(G.role)
    end
end

Probe:Steps("stillcursor", {
    rev = 1,
    title = "A cursor that doesn't move while the keys change (#78, 18.7)",
    { text = "Out of combat, in a group, hover keys set for this role (frames only). Hooking the tiles.",
      auto = true, run = function() return hoverHooks() and keyBindings("start") > 0 end },
    { text = "Hover a member's tile and hold still. Press Run: it switches your role to tank, so the keys are re-applied under the cursor.",
      button = "Switch role", run = switchRole("tank") },
    { text = "Still holding still over the tile: press your hover key once. Did it cast on the member?", ask = true,
      check = function() return keyBindings("after the press, still") >= 0 end },
    { text = "Move the cursor off the tile and back on; press the key once. Did it cast on them now?", ask = true,
      check = function() return keyBindings("after re-entering") > 0 end },
    { text = "Restoring your role (from the talents).", auto = true, run = switchRole("auto") },
    { text = "Hover a tile and hold still; have a member join or leave so the tiles reflow under the cursor. Press the key once. "
        .. "Did it cast on whoever the tile shows now?", ask = true,
      check = function() return keyBindings("after a reflow under the cursor") >= 0 end },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

--------------------------------------------------------------------------------
-- 18.8 The harness's assumptions (tests/wow_stubs.lua): RegisterForDrag and
-- SetMovable on a protected frame in combat (not flagged protected in the
-- 70532 docs), and an insecure SetOverrideBindingClick / ClearOverrideBindings
-- in combat on a protected and on a plain owner. The effects are logged; the
-- blocked lines are the host's.
--------------------------------------------------------------------------------

local KEYS = { protected = "CTRL-F11", plain = "CTRL-F12" }

local function assumptionsSetup()
    if InCombatLockdown() then say("assumptions: out of combat only") return false end
    A.secureFrame = A.secureFrame or CreateFrame("Button", "RaidProbeAuditSecure", UIParent, "SecureActionButtonTemplate")
    A.plainFrame = A.plainFrame or CreateFrame("Frame", "RaidProbeAuditPlain", UIParent)
    A.secureFrame:SetMovable(false)
    A.secureFrame:SetAlpha(1)
    ClearOverrideBindings(A.secureFrame)
    ClearOverrideBindings(A.plainFrame)
    say("assumptions: a protected button and a plain frame of the probe's own are ready")
    return true
end

local function assumptionsRun()
    local s, p = A.secureFrame, A.plainFrame
    if not s then say("assumptions: run the setup step first") return false end
    local combat = InCombatLockdown()
    local okM, movable = pcall(s.IsMovable, s)
    local alpha = s:GetAlpha()
    try("RegisterForDrag on the protected button", s.RegisterForDrag, s, "LeftButton")
    try("SetMovable on the protected button", s.SetMovable, s, true)
    try("SetAlpha on the protected button", s.SetAlpha, s, 0.5)
    local okM2, movable2 = pcall(s.IsMovable, s)
    say(string.format("assumptions (combat=%s): IsMovable %s -> %s, alpha %s -> %s", show(combat), okM and show(movable) or "ERR",
        okM2 and show(movable2) or "ERR", show(alpha), show(s:GetAlpha())))
    try("SetOverrideBindingClick, protected owner", SetOverrideBindingClick, s, true, KEYS.protected, s:GetName())
    say("  " .. KEYS.protected .. " live binding after the protected owner: " .. kind(GetBindingAction, KEYS.protected, true))
    try("SetOverrideBindingClick, plain owner", SetOverrideBindingClick, p, true, KEYS.plain, s:GetName())
    say("  " .. KEYS.plain .. " live binding after the plain owner: " .. kind(GetBindingAction, KEYS.plain, true))
    try("ClearOverrideBindings, protected owner", ClearOverrideBindings, s)
    try("ClearOverrideBindings, plain owner", ClearOverrideBindings, p)
    say("  after clearing: " .. KEYS.protected .. "=" .. kind(GetBindingAction, KEYS.protected, true) .. " " .. KEYS.plain .. "="
        .. kind(GetBindingAction, KEYS.plain, true))
    pcall(s.SetMovable, s, false)
    pcall(s.SetAlpha, s, 1)
    return true
end

Probe:Steps("assumptions", {
    rev = 1,
    title = "The test harness's assumptions on protected calls (#78, 18.8)",
    { text = "Out of combat. Making a protected button and a plain frame of the probe's own.", auto = true, run = assumptionsSetup },
    { text = "Pull a mob. In combat, press Run: RegisterForDrag, SetMovable and SetAlpha on the protected button, override "
        .. "bindings from both owners, then cleared. The effects are logged; the blocked lines are the host's.",
      button = "Run in combat", run = assumptionsRun },
    { text = "Out of combat now: press Run again, the baseline.", button = "Run out of combat", run = assumptionsRun },
    { text = "Type /reload (or press Reload now) so the log reaches the disk.", reload = true },
})

-- Seam for tests/test_probe.lua.
NS._test = NS._test or {}
NS._test.audit = { A = A, regenEv = regenEv, regenReset = regenReset, regenCheck = regenCheck, protectedReport = protectedReport,
    bodyCheck = bodyCheck, identityReport = identityReport, toggleReflows = toggleReflows,
    reflows = function() return reflows end, reflowEv = reflowEv, hoverHooks = hoverHooks, hiddenTileState = hiddenTileState,
    otherTooltipState = otherTooltipState, spots = spots, dragSetup = dragSetup, dragCheck = dragCheck,
    placedCheck = placedCheck, keyBindings = keyBindings, assumptionsSetup = assumptionsSetup, assumptionsRun = assumptionsRun }
