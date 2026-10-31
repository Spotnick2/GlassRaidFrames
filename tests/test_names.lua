-- The name display (#18): first name (default), first name + surname initial,
-- or the full name, for everyone; a nickname per person, keyed by GUID,
-- account-wide. A secret name goes to the client whole; a nickname still wins.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

party(2)
WoW.SetUnit("party1", { name = "Karuzo Memphisto", class = "PRIEST", player = true })
WoW.SetUnit("party2", { name = "Karuzo Éclair", class = "MAGE", player = true })
local GRF = loadAddon()
local F, S = GRF.Frames, GRF.Settings
flush()

local function shown(unit) return childFor(unit).nameText._text end

-- The styles, on their own.
eq(F.DisplayName("Karuzo Memphisto"), "Karuzo", "default: the first name")
eq(F.DisplayName("Karuzo Memphisto", "initial"), "Karuzo M.", "first + surname initial")
eq(F.DisplayName("Karuzo Éclair", "initial"), "Karuzo É.", "a multi-byte initial stays whole")
eq(F.DisplayName("Karuzo Memphisto", "full"), "Karuzo Memphisto", "the full name")
eq(F.DisplayName("Karuzo", "initial"), "Karuzo", "no surname: the first name")
eq(F.DisplayName("Karuzo Memphisto", "full", "Healz"), "Healz", "a nickname wins")
local secret = WoW.Secret("name")
check(F.DisplayName(secret, "initial") == secret, "a secret name goes through whole (initial)")
check(F.DisplayName(secret, "full") == secret, "and in full")
eq(F.DisplayName(secret, "first", "Healz"), "Healz", "a nickname wins over a secret name")

-- The tiles: first names by default; both Karuzos read the same.
eq(shown("party1"), "Karuzo", "tile: first name by default")
eq(shown("party2"), "Karuzo", "the alt reads the same (the issue)")
eq(GRF.db.nameStyle, nil, "the default isn't saved")

-- A style for everyone, painted at once, in combat too (plain Lua).
WoW.combat = true
check(S.SetNameStyle("initial"), "initial accepted")
flush()
eq(shown("party1"), "Karuzo M.", "tile: Karuzo M.")
eq(shown("party2"), "Karuzo É.", "tile: Karuzo É.")
eq(#WoW.blocked, 0, "no protected touch in combat")
WoW.combat = false
check(not S.SetNameStyle("nickname"), "junk refused")
eq(GRF.db.nameStyle, "initial", "saved, junk didn't touch it")
SlashCmdList.GLASSRAIDFRAMES("names full")
flush()
eq(shown("party1"), "Karuzo Memphisto", "/grf names full")
SlashCmdList.GLASSRAIDFRAMES("names first")
eq(GRF.db.nameStyle, nil, "/grf names first: back to the default (not saved)")

-- Nicknames: on the target, by GUID; kept with the case typed.
WoW.SetUnit("target", { name = "Karuzo Memphisto", class = "PRIEST", player = true })
SlashCmdList.GLASSRAIDFRAMES("nick Healz")
flush()
eq(shown("party1"), "Healz", "the target's tile shows the nickname")
eq(shown("party2"), "Karuzo", "the other Karuzo doesn't")
local saved = GRF.db.nicknames[UnitGUID("party1")]
check(saved and saved.nick == "Healz" and saved.name == "Karuzo Memphisto", "saved by GUID, with the full name for the list")
-- It follows the person, not the tile: party1 and party2 swap tokens.
WoW.SetUnit("party1", { name = "Karuzo Éclair", class = "MAGE", player = true })
WoW.SetUnit("party2", { name = "Karuzo Memphisto", class = "PRIEST", player = true })
WoW.fire("GROUP_ROSTER_UPDATE")
flush()
eq(shown("party2"), "Healz", "the nickname follows the person")
eq(shown("party1"), "Karuzo", "not the token")
-- A secret name in combat: the nickname still shows (GUIDs are plain, probe item 5).
WoW.secretFields.name = true
WoW.fire("UNIT_NAME_UPDATE", "party2")
flush()
eq(shown("party2"), "Healz", "a secret name: the nickname still shows")
WoW.secretFields.name = nil
-- A secret GUID: no nickname (unknown person), never an error.
WoW.secretFields.guid = true
WoW.fire("GROUP_ROSTER_UPDATE")
flush()
eq(shown("party2"), "Karuzo", "a secret GUID: the name, not a guess")
WoW.secretFields.guid = nil
WoW.fire("GROUP_ROSTER_UPDATE")
flush()

-- The full name from UnitName's two returns (Frames.FullName): Blizzard's
-- GetUnitName is Lua on Forever and throws on a secret surname (#78 F1).
eq(F.FullName("party1"), "Karuzo Éclair", "FullName: first and surname joined")
WoW.SetUnit("focus", { name = "Draku", player = true })
eq(F.FullName("focus"), "Draku", "no surname: the first name alone")
WoW.secretFields.name = true
local f1, s1 = F.FullName("party1")
check(WoW.IsSecret(f1) and WoW.IsSecret(s1), "a secret name: both returns, unchanged, no throw")
local f2, s2 = F.FullName("focus")
check(WoW.IsSecret(f2) and s2 == nil, "a secret first name with no surname: the first alone")
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()
check(WoW.IsSecret(shown("party1")), "the default style: the tile gets the secret first name")
eq(next(GRF.paintFailures), nil, "without a failure")
-- The full and initial styles can't join or split a secret: both returns go
-- to SetFormattedText, where the client joins them (Codex on #80: first
-- names aren't unique, so a tile must not drop the surname).
local function formatted(t)
    return type(t) == "table" and t.secretFormat == "%s%s%s" and t.n == 3
        and WoW.IsSecret(t.args[1]) and t.args[2] == " " and WoW.IsSecret(t.args[3])
end
S.SetNameStyle("full"); flush()
check(formatted(shown("party1")), "full: first, the separator and the surname, formatted by the client")
S.SetNameStyle("initial"); flush()
check(formatted(shown("party1")), "initial: the same (a secret surname has no initial)")
eq(next(GRF.paintFailures), nil, "without a failure")
-- A plain first name with a secret surname: the first style needs no join.
local unitName0 = UnitName
rawset(_G, "UnitName", function(u) if u == "party1" then return "Karuzo", WoW.Secret("name") end return unitName0(u) end)
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()
local mixed = shown("party1")
check(type(mixed) == "table" and mixed.args[1] == "Karuzo" and WoW.IsSecret(mixed.args[3]),
    "initial, a plain first name and a secret surname: formatted by the client")
S.SetNameStyle("first"); flush()
eq(shown("party1"), "Karuzo", "first: the plain first name, the secret surname not needed")
rawset(_G, "UnitName", unitName0)
-- The target's nickname while its name is secret: never truth-tested, and
-- the list keeps the name it had.
check(S.SetTargetNickname("Hidden"), "a nickname for a target whose name is secret")
eq(GRF.db.nicknames[UnitGUID("target")].nick, "Hidden", "saved")
eq(GRF.db.nicknames[UnitGUID("target")].name, "Karuzo Memphisto", "with the list name kept from before")
WoW.secretFields.name = nil
S.SetTargetNickname("Healz")
-- The read failing: a stale name is cleared, never kept.
local unitName = UnitName
rawset(_G, "UnitName", function() error("no") end)
eq(F.FullName("party1"), nil, "a failing read gives nil")
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()
eq(shown("party1"), nil, "and the tile's text is cleared")
rawset(_G, "UnitName", unitName)
WoW.fire("UNIT_NAME_UPDATE", "party1"); flush()
eq(shown("party1"), "Karuzo", "back: the first name")
WoW.SetUnit("focus", nil)

-- Refusals: no target, a non-player, a long nickname; the pipe is stripped.
WoW.SetUnit("target", nil)
local ok, why = S.SetTargetNickname("X")
check(not ok and why:find("target a player"), "no target: refused")
WoW.SetUnit("target", { name = "Wolf", player = false })
check(not S.SetTargetNickname("Doggo"), "a non-player: refused")
WoW.SetUnit("target", { name = "Karuzo Memphisto", class = "PRIEST", player = true })
check(not S.SetTargetNickname(string.rep("x", S.NICK_MAX + 1)), "too long: refused")
eq(GRF.db.nicknames[UnitGUID("target")].nick, "Healz", "and the old one kept")
check(S.SetTargetNickname("  He|cffal  "), "trimmed, pipes stripped")
eq(GRF.db.nicknames[UnitGUID("target")].nick, "Hecffal", "no escape sequence saved")

-- The list and removal (slash).
WoW.SetUnit("focus", { name = "Draku Stone", player = true })
S.SetNickname(UnitGUID("focus"), "Tank", "Draku Stone")
local list = S.Nicknames()
eq(#list, 2, "two nicknames")
eq(list[1].name, "Draku Stone", "listed by name")
newChat()
SlashCmdList.GLASSRAIDFRAMES("nick")
check(chatHas("1%. Draku Stone %-> Tank"), "/grf nick lists them")
SlashCmdList.GLASSRAIDFRAMES("nick remove 1")
eq(GRF.db.nicknames[UnitGUID("focus")], nil, "/grf nick remove 1")
SlashCmdList.GLASSRAIDFRAMES("nick clear")
flush()
eq(GRF.db.nicknames[UnitGUID("target")], nil, "/grf nick clear: the target's is gone")
eq(shown("party2"), "Karuzo", "and the tile shows the name again")

-- The options page: the style radios, the box and buttons, the list.
local O = GRF.Options._test
O.panel._scripts.OnShow(O.panel)
local C = O.controls
check(C.names and #C.names == 3, "three style radios")
check(C.names[1]._checked, "First name checked")
C.names[2]._scripts.OnClick(C.names[2])
eq(GRF.db.nameStyle, "initial", "clicking First + initial saves it")
C.nickBox:SetText("Healz")
C.nickSet._scripts.OnClick(C.nickSet)
eq(GRF.db.nicknames[UnitGUID("target")].nick, "Healz", "the box + button nickname the target")
eq(C.nickBox:GetText(), "", "the box empties")
eq(#C.nickRows, 1, "one row in the list")
check(C.nickRows[1].text._text:find("Healz"), "it shows the nickname")
local h1 = O.content:GetHeight()
S.SetNickname("Player-2", "Two", "Bob Two")
O.panel._scripts.OnShow(O.panel)
eq(#C.nickRows, 2, "a second row")
eq(O.content:GetHeight(), h1 + 22, "the page grows with the list")
C.nickRows[1].remove._scripts.OnClick(C.nickRows[1].remove)
eq(GRF.db.nicknames["Player-2"], nil, "Remove deletes that one (Bob Two, first by name)")
check(not C.nickRows[2]._shown, "and its row goes")
WoW.SetUnit("target", nil)
C.nickSet._scripts.OnClick(C.nickSet)
check(C.nickStatus._text:find("target a player"), "no target: the page says why")

-- The Indicators preview follows the name settings after it was built.
rawset(_G, "C_Spell", { GetSpellName = function() return nil end, GetSpellTexture = function() return nil end })
local IOT = GRF.IndicatorOptions._test
IOT.page:Show()
eq(IOT.ui.preview.name._text, "Karuzo E.", "the preview: your name in the current style")
IOT.page:Hide()
S.SetNameStyle("full")
IOT.page:Show()
eq(IOT.ui.preview.name._text, "Karuzo Elegia", "a style changed since: the preview follows")
S.SetNickname(UnitGUID("player"), "Me", "Karuzo Elegia")
GRF.IndicatorOptions.Refresh()
eq(IOT.ui.preview.name._text, "Me", "and your nickname")
eq(GRF.paintFailures["indicators page"], nil, "the page repainted cleanly")

-- Saved junk is dropped at load.
GlassRaidFrames = nil
dofile("tests/wow_stubs.lua")
party(1)
GRF = loadAddon({ db = { nameStyle = "loud", nicknames = { good = { nick = "A", name = "N" }, bad = { nick = "" },
    worse = "x", [5] = { nick = "B" } } } })
eq(GRF.db.nameStyle, nil, "a junk style dropped")
check(GRF.db.nicknames.good and not GRF.db.nicknames.bad and not GRF.db.nicknames.worse and not GRF.db.nicknames[5],
    "junk nicknames dropped, the good one kept")
eq(next(GRF.paintFailures), nil, "nothing failed")
done("test_names")
