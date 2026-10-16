# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassRaidFrames is a **party and raid frames addon for World of Warcraft: Forever 1.60.1**
(Interface `16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same
stack and conventions as the sibling Forever addons `..\GlassUnitFrames` (the closest sibling
and the source of most idioms here), `..\GlassMiniMapBar`, `..\AltStable` and `..\Priestly`.
When this file doesn't cover something, check how GlassUnitFrames handles it before you invent
a new idiom.

**Goal:** replace Cell, which the owner uses today, with a streamlined, glass-styled port.
- **The look.** Group frames in the "liquid glass" material the owner uses across the `Glass*`
  addons (the embedded library LibGlass-1.0, see "The glass material").
- **The basics.** List party and raid members, showing name, class colour, health, role,
  leader, raid mark, dead/offline, range and debuffs.
- **The headline feature: click-casting.** Mouse buttons 1–5 × modifiers bound per character
  to target, menu, spell or macro, set as plain secure attributes.
- **Decursive-style dispelling.** A small box on each frame lights up in the colour of the
  mouse button that cures it. Clicking the box casts the cure, and a sound plays when there is
  something to dispel.
- **Streamlined.** No Cell module zoo, layouts/profiles tree, Spotlight/NPC frames,
  import/export or raid-debuff database. Mouse-wheel bindings are out.
- **Keyboard hover-casting is in.** Keys pressed while hovering a frame are the owner's main
  healing binds (keys 1–8, Shift-R to resurrect, pinned spell ranks, from their Cell data).
  Like Cell, a secure `OnEnter` snippet binds the keys while a tile is hovered (snippets
  threw on early builds and work on 70425; see `ClickCast.lua`).

**Status: milestone 1 (glass party and raid frames).** Milestone 0's probe settled the
design (`docs/FOREVER-PROBE.md`); the approved plan is `docs/PLAN.md`. Next: click-casting (#3),
then the dispel box and sound (#4). Work goes through GitHub issues and PRs at
`github.com/Spotnick2/GlassRaidFrames` (private), one issue per milestone.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` (the embedded material) → `Compat.lua` →
`Glass.lua` → `Role.lua` → `Engine.lua` → `Frames.lua` → `IndicatorDefaults.lua` →
`Indicators.lua` → `Header.lua` → `GlassRaidFrames.xml` → `Blizzard.lua` → `Movers.lua` →
`ClickCast.lua` → `ClickCastCatalog.lua` → `ClickCastEditor.lua` →
`GlassRaidFrames.lua` → `Options.lua` → `ClickCastOptions.lua` →
`IndicatorOptions.lua`. Planned: `Dispel.lua`.

- **`Compat.lua`**: `GlassRaidFrames.API` is the only route to client APIs that moved or may be
  absent. It holds:
  - `IsSecret`;
  - event registration that reports failures;
  - `UnitButtonClicks`;
  - `HealthPercent` via a 0..100 curve;
  - `ClassColor`, `LoadBlizzardAddOn`;
  - `Fail(key, err)`, the **one** failure recorder (`GlassRaidFrames.paintFailures`, read by
    `/grf failures`);
  - `MEASURED_ON_BUILD`.

  It is a subset of GlassUnitFrames' `Compat.lua`; lift more from there when needed rather than
  rewriting.
- **`Glass.lua`**: this addon's instance of the embedded material (see "The glass material").
  Every call site dot-calls it (`Glass.Apply`, `Glass.Bar`, `Glass.MEDIA`, ...).
  - **`GRF.Glass` is a forwarding handle** (#37, #38, GlassUnitFrames' #102 / #101): LibGlass
    r6's `preset` and `bodyAlpha` are construction settings, and the saved choice is only
    readable at ADDON_LOADED, after every file has taken `local Glass = GRF.Glass`.
    `GRF.UseLook(look, body)` builds the instance at ADDON_LOADED, before anything is built.
    So never keep an instance field (`STYLE`, `TUNABLES`, ...) in a file-load local.
  - **The look:** `clean` (LibGlass's preset) **by default**, `classic` = r5's look
    (`db.look = "classic"`). **The body:** clear (LibGlass's tint alpha) or smoked
    (`db.glassBody = "smoked"`, `bodyAlpha = GRF.SMOKED` 0.65). Defaults aren't saved.
    Switching takes `/reload` (`GRF.Settings.SetLook/SetBody`, `/grf look|body`, the main
    page's Look rows).
  - A clean instance builds `Apply(…, "small")` as `thin_small`: anything copying the tile's
    rim reads `Glass.SIZES[g.size]` (the hover and target rims).
- **`Header.lua`**: the layout. **Eight `SecureGroupHeaderTemplate` headers**, one per raid
  group (`groupFilter` 1..8), side by side in one protected container, as in EllesmereUI's
  separated mode. Header 1 also has `showParty`/`showPlayer`, so **the client switches between
  the party column and the raid grid, in combat too; there is no mode code**. No
  `initialConfigFunction` (snippets are broken): the child template in `GlassRaidFrames.xml`
  carries the size. All 40 children are **precreated out of combat** (`startingIndex = -4`, show,
  back to `1`) and dressed once. A child's unit changes in combat; its `OnAttributeChanged`
  hook calls `Engine.SetUnit` and the child's `onUnitChanged` (lower case on purpose: a
  capitalised field on a widget collides with the widget-method namespace). The container
  moves only out of combat (`Header.SetPosition`).
- **`Role.lua`** (#7): which role you play. `HEALER`, `CASTER`, `MELEE` or `TANK`, in
  priority order:
  1. the per-character manual pick (`GlassRaidFramesCharDB.role`, `"auto"` = none);
  2. the talent tree with the most points;
  3. **the last role the talents gave** (`GlassRaidFramesCharDB.talentRole`): the talent API
     doesn't answer at `ADDON_LOADED` or during a loading screen, and a build doesn't change
     without a talent event, so this beats guessing;
  4. a class default.

  Settling at login is quiet. Chat says "role: … (talents)" only on a respec (talents changing a
  talent-given role). `Role.Watch(onChange, register)` takes the caller's reporting registrar
  (`API.RegisterEvents`).

  **Self-contained** (no engine, frames, saved variables or libraries), so GlassUnitFrames
  can lift it for its #35. Forever has one spec per class (always DAMAGER), so the spec API is
  useless here. The three Vanilla trees are **posX clusters in one trait tree** (probe item 9):
  cluster the visible, on-canvas nodes (`y < MAX_Y`) at gaps over `Role.GAP` and sum
  `currentRank` per cluster, left to right = tab order. Anything but three clusters means "don't
  guess". Positions only: **no talent names** (the IDs-not-names rule). `Role.TREES` maps
  class → the role of each tree.
- **Settings per role**: `GlassRaidFramesDB.profiles[role]`, currently holding `pos`. `GRF.Profile()`
  is the current role's table; `Header.PositionOf/SetPosition` and `Movers.Reset` read and write it.
  Defaults: `Header.HEALER_POS` (lower middle, between GlassUnitFrames' player and target) and
  the **left side for caster, melee and tank**, x computed from `UIParent:GetWidth()`. A position
  saved before roles existed (`db.pos`) is copied into **every** role without one (the role
  isn't known yet at load). An unsaved role's side grid is re-placed on `UI_SCALE_CHANGED` /
  `DISPLAY_SIZE_CHANGED`. A role change (talent events via `Role.Watch`, or a pick) re-applies
  through the combat queue and **announces `GlassRaidFrames.LayoutChanged` (role, left, bottom,
  width, height)** through `API.TriggerEvent` (EventRegistry). Every *saved* position (drag stop,
  combat mid-drag) announces from `Header.SetPosition`, and resets announce too. Nothing is
  announced without a placed grid. GlassUnitFrames listens; neither needs the
  other. New per-role settings go in the profile, not at the top of the DB.
- **`Options.lua`**: Game Menu > Options > AddOns > Glass Raid Frames (`/grf options`). The panel
  is created **hidden**, so Settings' `Show()` always fires `OnShow`. The Unlock button closes
  Settings with **`SettingsPanel:Close(true)`**: plain `Close()` goes back to the Game Menu, whose
  Esc handlers call the protected `SpellStopCasting` (ADDON_ACTION_FORBIDDEN blamed on us,
  measured).
  GlassUnitFrames' idiom: a canvas panel registered at `PLAYER_LOGIN`, `UIRadioButtonTemplate` /
  `UICheckButtonTemplate` through `API.SafeFrame` with fallback art, no `UIDropDownMenu`, built
  on first show and re-synced on every show. Every control goes through **`GRF.Settings`**
  (`SetRole`, `SetShowSolo`, `SetHideBlizzard`, `Unlock`, `ResetPosition`), the helpers `/grf`
  also uses.
- **`ClickCast.lua`** (#3): **one binding list per character and per role**
  (`GlassRaidFramesCharDB.profiles[role].bindings`), covering mouse clicks on our frames and
  keyboard keys while hovering. Rows are `{key = "SHIFT-R"}` or `{mouse = "shift-1"}` plus
  `{spell = ID, pinned = true|nil}`: spells by ID, names resolved at apply time.
  - **Mouse rows** are attributes on every header child, group and pet (`Header.AllChildren`), (`<alt-ctrl-shift->type<N>` =
    `spell`). A pinned rank is **its own spell ID** (a numeric `spell` keeps the rank,
    measured); unpinned uses the bare localized name (the highest rank). Blizzard's Click Cast
    Bindings act first on the same click (Forever's `SecureUnitButton_OnClick`).
  - **Key rows**: one hidden `SecureActionButtonTemplate` per key (a modifier held on a key
    binding does **not** select modified attributes, measured), bound **only while a group tile
    is hovered**: a secure `OnEnter` wrap on each group child (`SecureHandlerWrapScript`,
    header `GlassRaidFramesKeyHeader`) runs `control:RunFor(self, <grf-hoverkeys>)`, whose
    lines are `self:SetBindingClick(true, key, button)` (the tile owns the binding); `OnLeave`
    and `OnHide` run `self:ClearBindings()`. Cell's and Clique's design. Our tiles only show
    group members, so **a stranger under the cursor never gets the spell**, in combat too (the
    owner's rule). A `[party]`/`[raid]` macro check **can't** do it: both read false in combat,
    for a member (measured on 70425). Off a tile the key does its usual action. Pets aren't
    wrapped. The macro is `/cast [@mouseover,help,nodead] <spell>`, then `/click` of the key's
    own action button on the **exact complement** (`[noexists][nohelp][dead]`). Rez spells
    (`ClickCast.REZ`, by ID) swap dead/nodead. The fallback button comes from
    `GetBindingAction(key)` (the base binding) matched to the bars' `.commandName`; a key bound
    to anything else isn't taken over. Macros stay ≤ 255 characters (an 848-character one never
    reached its end, measured).
  - **One reconciliation** (`ClickCast.Apply`): desired vs installed, changing only what
    differs, so our own bindings can't loop through `UPDATE_BINDINGS`. `ClickCast.Request()`
    queues it through the combat queue (the installed bindings stay until combat ends:
    `pending`). It re-runs on role changes, `SPELLS_CHANGED`, `UPDATE_BINDINGS`, and after the
    build. Every hover fires `UPDATE_BINDINGS`, so that one re-checks quietly (no `pending`).
    A key-list change clears the tiles' current bindings.
  - Capturing an existing binding again returns that row untouched (it never erases its spell).
    An unbound **modified** key (SHIFT-R) falls back, as the client does, to the plain key (R):
    an action button there gets the `/click`, and any other command is noted as lost on a frame.
    **A row installs only if its spell ID is learned** (`API.SpellKnown`, via `IsSpellKnown` /
    `IsSpellInSpellBook`): a name alone proves nothing, since `C_Spell.GetSpellName` answers
    for unlearned spells. After a respec, `SPELLS_CHANGED` clears the stale binding; the row
    stays saved and flagged. The open editor repaints on every `Request`, not only after
    `Apply`, so a role change in combat shows the new role's rows plus "pending" at once.
    `ClickCast.onApplied` lets the page repaint after a queued apply. **Known limit:** with a
    bar addon that binds through overrides (Bartender, ElvUI), the fallback clicks Blizzard's
    button for the key's base binding, not the addon's.
  - Warnings (`ClickCast.Warnings`): a mouse row on the SELFCAST modifier (clicks self-cast,
    keys don't, measured), a row replacing the plain target/menu click, an unknown spell, a
    macro too long, a key bound to a non-action command.
- **Click-casting editor (#50)**: the main settings page's Click-casting button and
  `/grf clickcast` open a standalone LibGlass window; the old subcategory is removed.
  - `ClickCastEditor.lua` owns drafts, explicit-role transactions, conflict replacement,
    staged Quick Bind and descriptive preview. Editing a role never activates it. Saved
    rows stay live until Save/Apply. Combat stops capture and commits, retaining drafts.
  - `ClickCastCatalog.lua` builds learned spell families using verified ID families or
    exact rank-qualified lookup round trips, not name matching alone. It caches until
    SPELLS_CHANGED and leaves ambiguous spells separate. Indicator ranks are unchanged.
  - `ClickCastOptions.lua` owns the table/browser and input UI. Mouse recording only
    accepts a fresh press/release in the capture area (Quick Bind: an armed spell row).
    Preview has no secure template or execution calls. Existing Blizzard/Self Cast warnings remain.
  - Saved spell rows need no migration. Unit/macro rows add `action` (`target`, `togglemenu`,
    `macro`), `macrotext`, optional display `name`/`icon`. Target/menu keyboard actions use
    the existing hover-bound buttons with `unit="mouseover"`; custom macros retain their
    explicit targeting and the 255-byte limit. The established spell execution path remains.
  - The content is hostable: `ClickCastOptions.Open(parent)` mounts it, and
    `RequestClose(callback)` guards host navigation. Minimum 900×600; the standalone shell
    owns movement/scaling. See `docs/CLICKCAST-EDITOR.md` for the contract and client checklist.
  - Material is local to `ClickCastOptions.lua`: never mutate shared `Glass.STYLE`
    or use instance-wide setters to tune this editor. Its hybrid separates shell
    reflection from continuous dark reading panes; decoration stays below text
    and uses gradient alpha (not `SetAlpha` on gradients). Temporary developer
    `SetMaterialPreview("baseline"|"hybrid"|"reflective"|"altstable")` changes decoration only, preserving
    drafts/input state. Retain the comparison modes for clear-theme follow-up #52;
    `reflective` is the accepted default.
- **Incoming heals** (GlassUnitFrames' recipe, `API.NewHealCalculator` / `API.IncomingHeals`
  from its Compat):
  - a translucent bar with the health bar's **full** width, anchored at the health fill's moving
    edge and clipped at the bar's end;
  - overflow percent 1 (DinoUF saw an empty bar without it);
  - a `heal` channel on `UNIT_HEAL_PREDICTION` and health events, **never spellcast events**
    (they showed damage as heals);
  - cleared for dead or offline units;
  - it follows resizes through `Frames.Layout`.
- **Power bar, hover and target** (Cell's, in glass):
  - A thin `Glass.Bar` along the bottom (`Frames.PowerHeight`, 3-6), coloured by power token
    (`Frames.POWER`), with secret values straight to the bar. The health bar takes the rest.
  - **Hover:** a white additive copy of the glass rim, shown from insecure
    `OnEnter`/`OnLeave` hooks.
  - **Target:** a tinted rim (`Frames.TARGET`) on `PLAYER_TARGET_CHANGED` (a `target`
    channel). `UnitIsUnit(u, "target")` can be secret, so a secret answer goes through
    `SetAlphaFromBoolean`.
- **The name is centred in the tile** (both ways) and shows the **first name** by default
  (`Frames.ShortName`), as Cell does: Forever's surnames only got a centred name cut short. A
  secret name (grouped) can't be split in Lua, so it goes to `SetText` whole. Dead/Offline is
  small in the top-right corner.
  - **Name display** (#18), account-wide: `db.nameStyle` `initial` ("Karuzo M.", a UTF-8
    initial kept whole) or `full`; `first` is the default and isn't saved.
  - **Nicknames** by GUID (`db.nicknames[guid] = {nick, name}`; `name` is only for the list).
    They win over every style, a secret name included, through the tile's plain `b.guid`
    (GUIDs are plain in combat, probe item 5). A secret GUID shows the name.
  - `Frames.NameFor(u, guid)` is the one place that decides. Settings repaint the `name`
    channel (plain Lua: fine in combat). `/grf names`, `/grf nick`, and the main page's Names
    section, last on the page because the nickname list grows downwards.
- **Pets** (#13): a `SecureGroupPetHeaderTemplate` (`Header.petHeader`, **measured working in
  game**) in its own container (`Header.petContainer`).
  - **By default, the column after the last group in use** (`Header.LastColumn`; owner: "dynamic,
    but always a column of its own"). It's anchored to the grid, so it follows it, and is
    re-placed out of combat on `GROUP_ROSTER_UPDATE`.
  - Once moved (unlock mode's second mover), its own saved spot per role
    (`profiles[role].petPos`); reset forgets it.
  - Columns of 5, exactly `PET_COUNT` 20 precreated and dressed (`Header.petChildren`). Tiles
    are `PET_HEIGHT` 60% tall, never under `MIN_H`.
  - Shown per role (`showPets`, off by default); follows "show solo".
  - When hidden, its children release their units, and they re-sync when shown.
  - Pets get a fixed colour (`Frames.PET`).
  - The announced rectangle covers the pets when they're shown.
  - Mouse bindings reach pet tiles (`Header.AllChildren`). Hover keys don't target pets
    (`[party]`/`[raid]`).
- **Tile size per role** (`profiles[role].size`, `/grf size`, width and height sliders on the
  main page). The default is **82×58** (Cell's look, measured side by side), and
  `GlassRaidFrames.xml` must match `Header.DEFAULT_W/H` (`test_toc`).
  - `Header.ApplySize` runs out of combat. It resizes the 40 precreated children, calls each
    child's `relayout` (`Frames.Layout`: bar height, and the name font at about 28% of the tile's
    height via `Frames.NameSize`, the room Cell's name takes),
    and resets the column offsets and the container. The header chains each child to the
    previous one (Forever's `SecureGroupHeaders.lua:211`), so columns re-flow on their own.
  - **Each header's width is set too.** A header centres its first child on its own width
    (`SecureGroupHeaders.lua:202`) and only sets that width in its own layout pass, so a stale
    width shifts the column.
  - A saved spot keeps its centre (the container is centre-anchored). A role still on its
    default is re-placed, because the side default is computed from the grid's width.
  - Each tile's relayout runs under `pcall`, so one failure never half-resizes the grid.
  - Sizes are clamped to `Header.MIN/MAX` (height ≥ 36, below which the debuff row covers the
    name). It re-applies on role change.
  - The sliders save at once but resize when the drag pauses (0.1 s), silently in combat.
  - Known: the glass instance's font registry keeps the names' original size. `Glass.SetFont`
    (unused here) would reset them until the next resize.
  - The material is LibGlass's, not changed here: the name font is re-set with the same file.
- **`Engine.lua`**: who gets painted and when, adapted from GlassUnitFrames' engine for frames
  whose unit changes:
  - a unit→frames map kept by `Engine.SetUnit`;
  - one `RegisterEvent` frame for the unit events (tokens move between frames);
  - channels (`name`, `health`, `indicators`, `range`) flushed once per rendered frame;
  - a full repaint on `GROUP_ROSTER_UPDATE`, because a token can change person without
    changing frame;
  - a shared ticker for range (`UNIT_IN_RANGE_UPDATE` wasn't delivered).
- **`Frames.lua`**: `Frames.Setup` dresses a child out of combat: `*type1=target` and
  `*type2=togglemenu` (**wildcards**: no fallback from `shift-type1` to `type1`), and `AnyUp`.
  **Every visual lives on `b.body`, an insecure child**, so painting and fading never touch the
  secure button: glass, health bar, name, status text, leader, raid mark and role icons. The
  painters follow probe item 5:
  - health goes straight to the bar;
  - dead, offline, leader and role are read through `plain()`;
  - range is secret: `body:SetAlphaFromBoolean(UnitInRange(u), 1, 0.4)`. Your own unit reads
    "unchecked" and never fades;
  - the mark index may be secret: `SetSpriteSheetCell`;
  - role icons show for TANK/HEALER only, because everyone is DAMAGER by default on Forever.
- **`Indicators.lua`** (#19): buffs and debuffs on each tile, drawn by `AuraContainer`s
  (the client picks the auras; their data never reaches Lua). Probe: `FOREVER-PROBE.md` item 10.
  - **Account-wide, per class** (`GlassRaidFramesDB.indicators[classToken].list`, owner: Alliance
    and Horde priests share one setup), seeded from **`IndicatorDefaults.lua`** (data only: rank
    families by first-rank ID, verified with `/fp raid ind ids`; class defaults). Validated once
    per session (junk dropped, values clamped, the debuff row restored).
  - Kinds: `icons` (one **fixed spot per spell**, one aura *slot* = 1 button; owner's pick over
    collapsing rows, which are *groups* = 10 buttons per tile, #21: 1,240 buttons cost 50 MB and
    93 → 60 fps); `icon` / `square` (slots stacked at one spot, **list order = frame level =
    priority**); `debuffs` (the built-in group row, `HARMFUL` or `HARMFUL|RAID`).
  - **Only mine = the `PLAYER` filter token**, per indicator. Spells match by
    `includeSpellIDs` with **every rank** (`Ind.Family`: the built-in family, else learned ranks
    via `API.Ranks` plus the ID). `RAID_IN_COMBAT` doesn't flag Vanilla HoTs (measured).
  - **A debuff on a group member can't be matched by ID unless `NeverSecret`**
    (`C_Secrets.GetSpellAuraSecrecy`; Weakened Soul is `ContextuallySecret`): such an indicator
    is reported unsupported (`Ind.Supported`) and not built. The plain debuff row shows it.
  - One container per indicator per tile, anchored to `b.body` at `Ind.LEVEL` (+12, over the
    rim). Edits go through `Ind.Request()` (the combat queue) and `sync` changes slots in place
    (`SetAuraSlotFilterString` / `CandidateFilters` / `Enabled`, restyle our own regions); a
    removed spell's slot is switched off, a disabled indicator's container is parked and reused
    by the next of its kind, so edits never pile up containers or keys.
  - Every button region is made in `initializeFrame` (backing, icon or square, client swipe,
    timer and stack texts) and only sized, placed, coloured or toggled later; `EnableMouse(false)`.
    The client hides the buttons' shown state (secret even out of combat).
  - Pet tiles (`child.isPet`, set by `Header`) get only the debuff row. Units follow
    `onUnitChanged` (`SetUnit` + `UpdateAllAuras`, in combat too). Per-tile and per-indicator
    `pcall`. `/grf ind` lists, `/grf ind <n|key> on|off`, `/grf ind reset` (`GRF.Settings`).
- **`IndicatorOptions.lua`**: the "Indicators" sub-page (owner's pick over a window of our own:
  gpt-6-astra mockups, 2026-10-04). Three areas: the class's
  indicator list (add, delete with a second click, up/down; the built-in debuff row can't be
  deleted or renamed), the selected one's settings (name box, enabled, only mine, buffs/debuffs,
  kind, a 3×3 anchor grid, X/Y/size sliders, grow buttons, swipe, timer, a palette-cycling
  colour for squares; the debuff row gets every/dispellable and how many instead) and spells
  (rows with up/down/remove; add by spellbook drag or by ID with a live name and an "unknown
  spell" refusal), plus a static preview tile. No dropdowns or popups: toggle-button groups.
  Every edit goes through `GRF.Settings` (`EditIndicator`, `AddIndicator`, `RemoveIndicator`,
  `MoveIndicator`, `AddIndicatorSpell`, ...), saves at once and applies through
  `Ind.Request`; `Ind.pending` shows "Changes apply when combat ends", and `Ind.onChanged`
  repaints the page once per change (from Apply, or from Request when deferred in combat).
  Sliders save at once and apply when the drag pauses (0.1 s). Another rank of a listed spell
  is refused (same family). Changing an indicator's kind rebuilds it (sync retires the old
  kind's container).
- **`Blizzard.lua`**: hides `PartyFrame`, `CompactPartyFrame` and `CompactRaidFrameContainer`
  using GlassUnitFrames' recipe. **`CompactRaidFrameManager` stays**: that side panel holds the
  raid leader's tools (ready check, world markers). The recipe: unregister events, hide, reparent,
  plus a deferred `SetParent` repair that waits for Edit Mode and combat.
- **`Movers.lua`**: `/grf unlock`. One insecure mover, with an explicit size, anchored to the container (never the
  reverse); the container follows the drag through `Header.SetPosition`. Combat locks it and saves the spot it was dragged to.
- **The combat queue isolates each action** (`pcall` per action, failures recorded under
  `queued <key>`), and the build is guarded per header. One failure never costs the rest of
  the queue, the other groups, or hiding Blizzard's frames.
- **`GlassRaidFrames.lua`**:
  - bootstrap and `GlassRaidFramesDB`;
  - **the addon's one combat queue**, `GlassRaidFrames.WhenOutOfCombat(key, fn, message)`,
    which is ordered and runs the build first; `message = false` makes it silent. Don't add a
    second one;
  - the `/grf` command;
  - the login warning (dev copies only) when the build differs from `MEASURED_ON_BUILD`.
- **`Media/dispel.ogg`**: the dispel alert, generated by `Tools/make_sound.py`. Never
  hand-edit it.
- **`Tools/RaidProbe/`**: the throwaway measurement addon, a **ForeverProbe module** (#44): `/fp raid
  <command>` (`/fp raid` lists them), its lines in the `/fp` console, never in chat. Build and change
  it by `..\ForeverProbe\docs\GUIDE.md` (the index is `C:\Projects\WoW\References\PROBES.md`);
  never edit ForeverProbe from here (an issue on `Spotnick2/ForeverProbe` instead).
  - It logs every line to `RaidProbeDB.log` (bound with `Probe:UseLog`); after a `/reload` the session is
    on disk at `WTF\Account\<account>\SavedVariables\RaidProbe.lua`, and the host's
    `ForeverProbe.lua` holds blocked actions and procedure records.
  - `-Probe` / `-ProbeOnly` deploy the ForeverProbe checkout first (`$env:FOREVERPROBE`, else
    `..\ForeverProbe`). `tests/test_probe.lua` loads it (`loadForeverProbe`); CI has no checkout
    (private) and skips it with `FOREVERPROBE_OPTIONAL=1`, so run the tests locally before a probe PR.
  - New in-game experiments go in as guided procedures (`Probe:Steps`), not checklists in chat.

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Advice that cites a TBC or
Classic API is usually stale. Spell IDs are Vanilla's, and so are ranks.

## The glass material

The material is **LibGlass-1.0**, an embedded LibStub library (`..\LibGlass`,
github.com/Spotnick2/LibGlass, public, MIT) that every glass addon embeds. Its repo owns the code,
the textures, the generator (`Tools/make_textures.py`) and the write-up
(`docs/GLASS-MATERIAL.md`), and its `CLAUDE.md` holds the contract (the API, region fields and
texture names only grow; instances; upgrade rules).

- **Material changes are LibGlass PRs**, never edits here. A bug or a need found here goes on a
  LibGlass issue; never edit `..\LibGlass` from this repo's session.
- **How it's embedded:** `.pkgmeta` externals put it in `Libs\LibGlass-1.0\` (the only supported
  path: `MEDIA` is derived from it), and the TOC loads its XML first. `Libs/` is gitignored; a dev
  copy comes from the LibGlass checkout through its own `Tools\deploy.ps1`, which
  `Tools\deploy.ps1` here calls first. The tests load the same checkout.
- **The pin:** `.pkgmeta` pins a tag (`tag: r8`), **never `tag: latest`**. Bump it only in a
  release made anyway: players get library fixes earlier through whichever glass addon ships the
  newest copy (LibStub runs that one). CI reads the pin from `.pkgmeta`
  (`tests/fetch_libglass.sh`), tests against it, and asserts the zip's `Libs/LibGlass-1.0/` is
  exactly that commit's shipped files. No comment on a `.pkgmeta` value line: the packager keeps
  it in the value.
- **`GlassRaidFrames.Glass` is an instance**: `STYLE`, the `TUNABLES` setters and the font
  registry are this addon's own. `Glass.MEDIA` resolves to the winning copy's `Media\`; use it
  only for library textures (`bar_fill`, `rim5_small`, ...). Our own media (`Media\dispel.ogg`)
  has its own path.
- **Colours passed to a glass bar's `SetStatusBarColor` must be plain** (the library's hook
  compares them): never a secret.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there, not into a copy in this repo.
- `C:\Projects\WoW\References\forever-api-1.60.1.70338.md` is the full API dump for the current
  build. It lists documented functions and events, enums, **widget methods** (the only list of
  those) and the `_G` walk. It proves a name exists, not that it works. **Presence is not a
  contract.**
- For a live check in game: `/api search <name>`, `/api system list`, `/api <system> list`
  (system names omit `C_`).
- **`C:\Projects\WoW\wow-ui-source` is Forever's own FrameXML** (branch `forever`, `version.txt` =
  1.60.1.70338, the dump's build). Read Blizzard code there first (`SecureTemplates.lua`,
  `SecureGroupHeaders.lua`, `Blizzard_AuraContainer`, …): line numbers in in-game error traces
  match it, and they don't match Retail's. Fall back to the Retail branch of
  `Gethe/wow-ui-source` only for what isn't there. For example, Forever's
  `SecureUnitButton_OnClick` is where `C_ClickBindings` gets the first say on every
  `SecureUnitButtonTemplate` frame, ours included.
- `..\LibGlass\docs\GLASS-MATERIAL.md` is the write-up of the glass material, and
  `..\LibGlass\CLAUDE.md` its contract.

## Reference addons

These live in `C:\Projects\WoW\References`. They show what works on this client *in practice*,
which the dump can't tell you. Reason about what they do rather than copying it, and **write
our own code**.

- **`Cell-r274-release\Cell` is the design reference** for *what* group frames and
  click-casting do.
  - It is not Forever-aware. Almost all its secure machinery depends on restricted snippets,
    which threw on early builds (they run on 70425; only the hover keys use one here):
    - `SecureGroupHeaderTemplate` with `_initialAttribute-*` / `initialConfigFunction`;
    - `SecureHandlerEnterLeave`/`ShowHide` on the unit button;
    - the `@cell` placeholder rewrite;
    - wheel and keyboard `SetBindingClick` snippets;
    - `RegisterAttributeDriver` visibility.
  - Worth reading:
    - `Modules\ClickCastings\ClickCastings.lua`: `GetAttributeKey`, `ApplyClickCastings` and
      `ClearClickCastings` (plain `SetAttribute`), and the list-pane editing UI;
    - `Indicators\Built-in.lua`;
    - `Defaults\ClickCasting_DefaultSpells_Vanilla.lua`.
- **`Decursive-2.9.0-RC2-19-gfbc816f-forever\Decursive` is the dispel reference.** It is ported
  to Forever (`DC.FOREVER`, `DC.RESTRICTED_AURAS`):
  - `Dcr_DebuffsFrame.lua` ~1124–1256: one `AuraContainer` per micro unit frame, with one
    `AddAuraSlot("HARMFUL", {candidateFilters={includeDispelTypes=…}})` per cure priority. Each
    slot's buttons are configured **only** in `initializeFrame` (`EnableMouse(false)`,
    `AddDispelTypeTexture` with a step colour curve) and never touched again.
  - `Dcr_DebuffsFrame.lua` ~1383–1507: mouse button N → cure N, set out of combat.
  - `Dcr_opt.lua` ~2240–2400: filters and colour curve. `excludeSpellIDs` works only for
    never-secret spells.
  - `Dcr_12_1_Sounds.lua`: `C_UnitAuras.AddAuraSound`, keyed on exact spell IDs.
  - `DCR_init.lua` ~522–641: the Classic cure spell table.
  - It gates aura reads on `C_RestrictedActions` and guards values with `canaccessvalue`.
- **`DinoUnitFrames_Forever_Beta_v3.0` is the Forever reference for group buttons.** Its
  `modules\units.lua` builds `party1-4`/`raid1-40` buttons by hand, because the header's
  initialisation failed here. See its changelog, v2.10–v2.34.

- **`ForeverUI-0.4.42\ForeverUI` is a Forever-native UI suite** with group frames
  (`Modules\Frames\`). It confirms the design: per-group `SecureGroupHeaderTemplate` headers
  with no `initialConfigFunction` ("the error there aborts frame creation entirely"), and a
  secret-safe range fade. Its field notes:
  - names can be **secret in groups** (seen at a dungeon pull);
  - `UnitIsConnected`, `UnitIsDead` and roles can be secret;
  - the raid mark index is secret even solo;
  - registering an unknown event is reported to error catchers even inside `pcall`.

  Its in-combat dispel display uses Blizzard's raid dispel indicator through
  `C_UnitAuras.AddPrivateAuraAnchor` (`Modules\Frames\GameAuras.lua`), which is an
  alternative to Decursive's `includeDispelTypes` slots for milestone 3.

None is licensed for our reuse in the way a copy would need, so write our own code.

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70338`),
and warn at login when `GetBuildInfo()` differs, **dev copies only** (`API.IsDevBuild`: version
`dev`, the unreplaced packager keyword, or unreadable), as GlassUnitFrames does. Bump it only
after re-measuring in game.

## Toolchain and commands

There is no build system, compiler or package manager; the client interprets the Lua directly.
The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). Use it,
not a newer Lua that may be first on `PATH`.

```powershell
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p File.lua             # syntax check; silent on success
pwsh tests\run.ps1                                                   # luac -p on TOC files + probe + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, run from the repo root
python Tools\make_sound.py                                           # regenerate Media\dispel.ogg (numpy + ffmpeg/libvorbis)
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon, its LibGlass (+ ForeverProbe and RaidProbe) into AddOns
```

The tests and the deploy take the LibGlass checkout from `$env:LIBGLASS`, else `..\LibGlass`,
and fail loudly without one. Both warn when it isn't at the `.pkgmeta` pin.

- **Default AddOns path:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
  The deploy script takes `-AddOnsPath`.
- **Deploy** rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token; the packager needs it.
- **In game:**
  - Run `/console scriptErrors 1` first, because errors are off by default. Then `/reload`.
  - A brand-new addon folder needs only `/reload` too (owner, 2026-10-09; ForeverProbe guide,
    section 7). Exit fully only to test persistence.
  - Check the AddOns list shows the addon enabled **and not flagged out of date**.
  - Error delivery stops after 100 errors in a session.

## Addon basics

- One plain `GlassRaidFrames.toc`, with no `_Forever` or `_Camelot` suffix. Use
  `## Interface: 16001`; **`11601` is a transposed-digit bug**.
- One global namespace table, `GlassRaidFrames`. Files start
  `GlassRaidFrames = GlassRaidFrames or {}` and alias it `local GRF = GlassRaidFrames`. The TOC
  order is the load order.
- Consumers reach client APIs through `GRF.API`, never by injecting globals into `_G`. Read the
  porting guide's "False friends" section before aliasing anything.
- **IDs, never names (owner rule: support localized clients).** Spells, talents, cures and
  auras are identified and stored by ID. Never compare against, or save, an English display
  name. A name the client needs (a `/cast` line in a macro) is resolved at runtime from the ID
  with `C_Spell.GetSpellName` (rank text with `C_Spell.GetSpellSubtext`), so it's always the
  client's own localized string. Unit tokens, role tokens (`HEALER`), dispel-type keys
  (`Magic`) and texture/atlas paths are API values, not display text, and are fine.
- Keep a `_test` seam table at the bottom of a file to expose file-local internals to tests.
  Don't promote internals to globals.

## Forever facts that matter for unit frames

These are measured or declared on this client. They are what makes a Classic unit frame addon
not port cleanly.

- **Secret values.** Some unit numbers come back as values you can hold but not read.
  Arithmetic, comparison, `tostring`, concatenation and **truth-testing** all throw, and a
  `x or 0` guard doesn't help. `UnitHealthMax` was measured secret for the player's own
  character. Retail's answer is to hand the secret straight back to the client, and both
  reference addons do this:
  - **Bars:** `StatusBar:SetMinMaxValues` / `SetValue` accept secrets directly.
  - **Percent and colour:** `UnitHealthPercent(unit, usePredicted, curve)` /
    `UnitPowerPercent` with `C_CurveUtil.CreateCurve` / `CreateColorCurve`. Use this instead of
    dividing health by max health.
  - **Text:** `FontString:SetFormattedText` and `AbbreviateNumbers`. EllesmereUI also passes
    percents through `string.format` and relies on a `CurveConstants.ScaleTo100` global. The
    dump lists neither as secret-safe, so measure before relying on them.
  - **Cast bars:** `UnitCastingDuration` / `UnitChannelDuration` return a `LuaDurationObject`.
    Pass it to `StatusBar:SetTimerDuration`, and read time left with `GetRemainingDuration`
    into `SetFormattedText`. Never read start/end times in Lua. See DinoUF `modules\cast.lua`.
  - **Heal prediction:** `CreateUnitHealPredictionCalculator` +
    `UnitGetDetailedHealPrediction(unit, healer, calc)`, feeding the calculator's values
    straight into a StatusBar. See DinoUF `modules\incheal.lua`.

  Test with `issecretvalue(v)` and query policy under `C_Secrets` (`ShouldUnitHealthMaxBeSecret`,
  `ShouldUnitPowerBeSecret`, `ShouldUnitSpellCastingBeSecret`, …). Which unit APIs are secret,
  for which units and when, is **per-API and largely unmeasured**. Probe it; don't assume.
  Store `nil` for unknown, never `0`.
- **Auras are unreadable in combat for every unit**, not just the player.
  `C_UnitAuras.GetAuraDataByIndex` throws; `GetAuraDataBySpellName` quietly returns nil, which
  looks like "not buffed". The `UNIT_AURA` payload is secret too (`isFullUpdate`,
  `updatedAuraInstanceIDs`). Every touch of client data goes **inside one `pcall`**, and
  checking the result a line later is too late. **For unit frame aura icons, don't read auras
  in Lua at all.** Both references use Blizzard's managed container:
  `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`. The client picks,
  sorts and renders the auras. The addon supplies the button look (`SetIcon`,
  `SetDurationCooldown`) and options processed through `C_AuraContainerUtil.*`. See DinoUF
  `modules\auras.lua` (`ForeverEnsureAuraContainer`) and EllesmereUI
  `EUI_UnitFrames_AuraContainers.lua`. A GUID-keyed cache with an "unknown" state is only
  needed for logic that must *know* about an aura.
- **Secure snippets work on 70425** (measured 2026-10-16, `/fp steps raid snippets`): `Execute`,
  a `RegisterStateDriver` + `_onstate-*` (in combat too) and `SecureHandlerWrapScript` `OnEnter`
  with `SetBindingClick`, in combat, although `loadstring_untainted` is still absent from `_G`.
  **They threw on early builds** (70009), which is why most of this addon avoids them; Clique
  5.1.3 turned its Forever block off too. Use one only where nothing plain works (the hover
  keys), and re-measure on a new build. Plain `SecureActionButtonTemplate` + `SetAttribute` +
  insecure `PreClick`/`PostClick` **works**, in and out of combat.
- **`[party]`/`[raid]` macro conditions read false in combat**, for a group member under the
  cursor (`UnitInParty` true; `[help]`, `[nodead]`, `[exists]` fine; measured on 70425). Out of
  combat they work. Don't gate a macro on group membership.
- **Single-unit frames:** `SecureUnitButtonTemplate` + `RegisterUnitWatch(frame)` for
  show/hide. Both references ship this on Forever, and DinoUF's changelog calls its UnitWatch
  path the stable baseline. We haven't measured it ourselves.
- **Party and raid headers: the evidence conflicts. Measure before choosing.** DinoUF found
  that `SecureGroupHeaderTemplate` can't run its restricted `initialConfigFunction` on Forever.
  It builds party and raid children by hand instead: `SecureUnitButtonTemplate` buttons bound
  to fixed `party1-4` / `raid1-40` tokens, with roster-driven visibility and explicit anchoring
  (`modules\units.lua`, changelog v2.10–v2.34). EllesmereUI's raid frames do use
  `SecureGroupHeaderTemplate` with `initialConfigFunction` and claim 16001 support. Probe
  whether a header spawns children on the current build. The manual approach needs every
  layout change deferred out of combat.
- **Combat lockdown:** `SetAttribute` does nothing under `InCombatLockdown()`. A frame that
  parents secure buttons is protected: hiding, moving, re-anchoring or unclamping it in combat
  is silently refused, with `ADDON_ACTION_BLOCKED` blamed on someone else's taint. Parking it
  off screen at alpha 0 doesn't work either. Record the request and apply it on
  `PLAYER_REGEN_ENABLED`. A mid-combat roster change can point a `party2`/`raid3` token at a
  different player; nothing fixes that until combat ends.
- **Click edges depend on the template.** For `SecureActionButtonTemplate` (spell buttons),
  register **both** mouse edges: its handler acts on exactly one, according to
  `ActionButtonUseKeyDown` (measured in Priestly). For **`SecureUnitButtonTemplate`** (our unit
  frames), register **`"AnyUp"`** only, as SUF and DinoUF do. That handler dispatches on every
  registered edge, so both edges could open the menu on press and toggle it shut on release.
  **Never set `typerelease`** on either.
- **`UnitName(unit)` returns only the first name**, with the surname where the realm should be.
  Characters have surnames and first names aren't unique. Display with `GetUnitName(unit, false)`
  and key caches on `UnitGUID`.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals.** Wrap it, treat
  both as failures, and report them. Registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden, so
  use `UNIT_DIED` for deaths.
- No talent spec API. `MAX_PLAYER_LEVEL` is nil, so use `GetMaxPlayerLevel()` (60). The live
  beta cap is lower, so never hardcode it. `MouseIsOver` is absent (use `frame:IsMouseOver()`).
  `ReloadUI()` is protected. `SetRaidTarget` is protected.
- `GetInstanceInfo()` returns the continent outdoors, so gate on `instanceType ~= "none"`.
- Options use the Retail `Settings.RegisterAddOnCategory`, not `InterfaceOptions_AddCategory`.
  Tooltips use `TooltipDataProcessor`: hooking `OnTooltipSetItem` at load can abort
  registration. **Edit Mode is live**, so Blizzard's player and target frames can be moved or
  reset out from under anything anchored to them, and Edit Mode reparents the frames we hide
  (see `Blizzard.lua`).
- **SavedVariables persist as of 70009** (broken through 69977). Code may read them but must cope
  when they're absent. CVar persistence has not been re-measured. **Verify persistence only
  with a full client exit**, never `/reload` or by reading the SV file. Count loads inside the
  addon, or check a key that defaults to nil.

## Testing

The `tests\` harness is modelled on Priestly's: plain Lua 5.1 scripts with no dependencies, a
`tests\wow_stubs.lua` API mock driven through an exported `WoW` table, `tests\harness.lua`
(`check` / `eq` / `loadAddon` / `standardUnits`), and `tests\run.ps1` to run them all. The stub
does four more things:
- It validates event names against the API dump when the dump is present.
- It records any touch of a protected frame in combat in `WoW.blocked`.
- It models `FontString:SetFormattedText` taking secrets without formatting them in Lua.
- It records every widget method called. `test_methods.lua` checks each one exists in the dump,
  closing the gap where a catch-all stub silently swallows a method Forever lacks.

`GlassRaidFrames.paintFailures` collects the errors that painters swallow, so a
secrets test should assert it stays empty. Before trusting a new test, **mutation-test it**:
break the behaviour and confirm it goes red.

- **The stub is an allowlist and must model the client's absences.** It should fail on any read
  of an unstubbed global. Before stubbing one, confirm it exists in the current API dump and
  copy its exact signature. Defining something Forever lacks (like `MouseIsOver`) lets a broken
  call pass.
- **Stub secrets as `newproxy(true)` userdata with metamethods that error.** Don't use a table,
  which `type(v) == "table"` filters would skip. Don't use a coroutine either: it only throws on
  arithmetic and ordering. The proxy also throws on `tostring`, concatenation and
  `string.format` (verified in Lua 5.1). **No Lua 5.1 value can make a truth test or `==`
  throw**, so the stub can't catch `if secret then` or `secret == x`. Those are caught only by
  in-game combat testing and review.
- **Strict globals don't cover methods.** A catch-all `__index` swallows calls to widget methods
  this client lacks. For handlers built on widget methods, **run the handler and assert what it
  produced**, and check the method against the dump's widget-method section.
- Keep one test file that executes every script handler and event the addon installs, because
  strict globals only catch code that actually runs.
- Offline tests can't cover secure clicks, combat lockdown, real secret behaviour or rendering.
  Those need an in-game checklist and a throwaway probe addon under `Tools\`, like the siblings'
  `PriestlyProbe`; here that is `Tools\RaidProbe`, a ForeverProbe module.

## Workflow and releasing (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review (owner-launched) → squash-merge (by
  the owner). Never commit to `main`.
  Commit or push only when asked. Before committing, `luac -p` must be clean and the tests green.
  **After pushing, check the PR's `package-check` run** (`gh run list`, then `gh run view`).
  CI has no API dump: the stub validates events against `tests/events-70338.txt` instead, so
  run a new test once with `GLASSRF_API_DUMP` pointing at a missing file. Milestone 1 sat red
  on CI for several pushes before a review caught it.
- Review policy: use the shared `$wow-addon-review` skill for PR reviews.
- **The owner merges and closes PRs, and launches reviews.** Claude opens the issue, branch and
  PR, runs the tests, and stops there: never `gh pr merge` or close a PR, and never start a Codex
  or Fable review on its own. When the owner posts or points to a review, reconcile it
  (below) and push the fixes to the PR.
- **Adversarial review is mandatory** for plans and significant diffs, **launched by the owner**.
  When asked, run it through the project's `/codex-consult` skill
  (`.claude/skills/codex-consult/`), because Codex is a different model family and so has
  different blind spots. Always hand it `CLAUDE.md` and the porting guide. If Codex is
  unavailable, fall back to Fable. Then reconcile:
  - Verify its claims before acting. It has been right, and it has been confidently wrong.
  - Take its bug-catching seriously.
  - Push back when it adds complexity to a single-owner addon.
- **Fable** is worth using for long-context reading across many files, such as the SUF-vs-DinoUF
  feature inventory. Review use is default-on. Implementation use needs the owner's explicit
  approval each turn.
- Releases are built by **CurseForge's own packager from the tag webhook**, reading `.pkgmeta`.
  Don't add a GitHub release workflow. CI (`package-check.yml`) only dry-runs
  `BigWigsMods/packager` with `-d`. The packager derives the `forever` flavor from
  `## Interface: 16001`.
- **Every tag needs a `CHANGELOG.md` entry committed first**, written for players. The tag name
  sets the channel: `alpha` / `beta` / anything else → Release. That's a distribution channel,
  not a stability claim.
- `.pkgmeta` ignores `.github`, `.claude`, `docs`, `tests`, `Tools`, `CLAUDE.md`, `README.md` and
  `CHANGELOG.md` (`LICENSE` ships), plus LibGlass's `tests`, `docs`, `Tools` and notes under
  `Libs/LibGlass-1.0/` (CurseForge's packager ignores an external's own list). CI asserts the
  zip holds exactly the addon and the library's shipped files.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it. The
  porting guide has already had to reverse reasoned conclusions (click-casting, "park it off
  screen", persistence).
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
