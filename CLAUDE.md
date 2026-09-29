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
  addons (`Glass.lua`, lifted from GlassUnitFrames).
- **The basics.** List party and raid members, showing name, class colour, health, role,
  leader, raid mark, dead/offline, range and debuffs.
- **The headline feature: click-casting.** Mouse buttons 1–5 × modifiers bound per character
  to target, menu, spell or macro, set as plain secure attributes.
- **Decursive-style dispelling.** A small box on each frame lights up in the colour of the
  mouse button that cures it. Clicking the box casts the cure, and a sound plays when there is
  something to dispel.
- **Streamlined.** No Cell module zoo, layouts/profiles tree, Spotlight/NPC/Pet frames,
  import/export or raid-debuff database. Mouse-wheel bindings are out.
- **Keyboard hover-casting is in.** Keys pressed while hovering a frame are the owner's main
  healing binds (keys 1–8, Shift-R to resurrect, pinned spell ranks, from their Cell data).
  Cell does it with restricted snippets, which are broken here; probe item 8 picks the route.

**Status: milestone 1 (glass party and raid frames).** Milestone 0's probe settled the
design (`docs/FOREVER-PROBE.md`); the approved plan is `docs/PLAN.md`. Next: click-casting (#3),
then the dispel box and sound (#4). Work goes through GitHub issues and PRs at
`github.com/Spotnick2/GlassRaidFrames` (private), one issue per milestone.

## Layout

TOC load order: `Compat.lua` → `Glass.lua` → `Role.lua` → `Engine.lua` → `Frames.lua` →
`Auras.lua` → `Header.lua` → `GlassRaidFrames.xml` → `Blizzard.lua` → `Movers.lua` →
`ClickCast.lua` → `GlassRaidFrames.lua` → `Options.lua` → `ClickCastOptions.lua`. Planned:
`Dispel.lua`.

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
- **`Glass.lua`**: the material. It is a **copy of GlassUnitFrames `main:Glass.lua`**; only
  the header and namespace lines differ. `tests/test_toc.lua` fails while they differ, and the
  same goes for `Tools/make_textures.py`. Change the material in GlassUnitFrames first, then copy
  it back. `Media/*.tga` come from that generator.
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

  **Self-contained like `Glass.lua`** (no engine, frames or saved variables), so GlassUnitFrames
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
  - **Mouse rows** are attributes on the 40 header children (`<alt-ctrl-shift->type<N>` =
    `spell`). A pinned rank is **its own spell ID** (a numeric `spell` keeps the rank,
    measured); unpinned uses the bare localized name (the highest rank). Blizzard's Click Cast
    Bindings act first on the same click (Forever's `SecureUnitButton_OnClick`).
  - **Key rows**: one hidden `SecureActionButtonTemplate` per key (a modifier held on a key
    binding does **not** select modified attributes, measured), bound with
    `SetOverrideBindingClick`. Its macro is `/cast [@mouseover,help,nodead,party][…,raid]
    <spell>`, then `/click` of the key's own action button on the **exact complement**
    (`[noparty,noraid][noexists][nohelp][dead]`). So **a stranger under the cursor never gets
    the spell** (the owner's rule, measured), and anything else does the key's usual action.
    Rez spells (`ClickCast.REZ`, by ID) swap dead/nodead. The fallback button comes from
    `GetBindingAction(key)` (the base binding) matched to the bars' `.commandName`; a key bound
    to anything else isn't taken over. Macros stay ≤ 255 characters (an 848-character one never
    reached its end, measured).
  - **One reconciliation** (`ClickCast.Apply`): desired vs installed, changing only what
    differs, so our own override can't loop through `UPDATE_BINDINGS`. `ClickCast.Request()`
    queues it through the combat queue (the installed bindings stay until combat ends:
    `pending`). It re-runs on role changes, `SPELLS_CHANGED`, `UPDATE_BINDINGS`, and after the
    build.
  - Capturing an existing binding again returns that row untouched (it never erases its spell).
    An unbound **modified** key (SHIFT-R) falls back, as the client does, to the plain key (R):
    an action button there gets the `/click`, and any other command is noted as lost off-frame.
    Only keys the client accepted count as installed, so a refused one is retried.
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
- **`ClickCastOptions.lua`**: the "Click-casting" subcategory page (under Options.category).
  - Rows show the binding, the spell (dragged from the spellbook: `GetCursorInfo()`'s 4th
    return), a rank button (the spellbook holds every rank as its own item, grouped by the
    client's own name at runtime) and Remove.
  - A capture button takes the next key or click; bare modifiers are ignored, Esc cancels,
    and it's refused in combat.
  - It flags Blizzard's Mouseover Cast (**it casts on hovered strangers, measured**) with a
    turn-off button, lists Blizzard's own spell/macro click bindings, and warns when its
    "Target Unit Frame" is unbound.
- **The name is centred in the tile** (both ways) and shows the **first name**
  (`Frames.ShortName`), as Cell does: Forever's surnames only got a centred name cut short. A
  secret name (grouped) can't be split in Lua, so it goes to `SetText` whole. Dead/Offline is
  small in the top-right corner.
- **Tile size per role** (`profiles[role].size`, `/grf size`, width and height sliders on the
  main page). The default is **82×58** (Cell's look, measured side by side), and
  `GlassRaidFrames.xml` must match `Header.DEFAULT_W/H` (`test_toc`).
  - `Header.ApplySize` runs out of combat. It resizes the 40 precreated children, calls each
    child's `relayout` (`Frames.Layout`: bar height, and the name font at about 28% of the tile's
    height via `Frames.NameSize`, the room Cell's name takes),
    and resets the column offsets and the container. The header chains each child to the
    previous one (Forever's `SecureGroupHeaders.lua:211`), so columns re-flow on their own.
  - The container is centre-anchored, so the grid keeps its centre.
  - Sizes are clamped to `Header.MIN/MAX`. It re-applies on role change.
  - `Glass.lua` stays the pinned copy: the name font is re-set with the same file.
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
- **`Auras.lua`**: a 3-icon debuff row per tile on an `AuraContainer` (`AddAuraGroup` before
  `SetUnit`, then `UpdateAllAuras`). It follows the child's unit, in combat too (measured).
  Buttons are styled only in `initializeFrame`, with `EnableMouse(false)`.
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
  - the login warning when the build differs from `MEASURED_ON_BUILD`.
- **`Media/dispel.ogg`**: the dispel alert, generated by `Tools/make_sound.py`. Never
  hand-edit it.
- **`Tools/RaidProbe/`**: the throwaway measurement addon (`/rprobe help`). It logs every line
  to `RaidProbeDB.log` in SavedVariables, so after a full client exit the session is on disk at
  `WTF\Account\<account>\SavedVariables\RaidProbe.lua` for review.

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`. Advice that cites a TBC or
Classic API is usually stale. Spell IDs are Vanilla's, and so are ranks.

## References: read these before touching an unfamiliar API

- `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there, not into a copy in this repo.
- `C:\Projects\References\forever-api-1.60.1.70009.md` is the full API dump for the current
  build. It lists documented functions and events, enums, **widget methods** (the only list of
  those) and the `_G` walk. It proves a name exists, not that it works. **Presence is not a
  contract.**
- For a live check in game: `/api search <name>`, `/api system list`, `/api <system> list`
  (system names omit `C_`).
- **`C:\Projects\wow-ui-source` is Forever's own FrameXML** (branch `forever`, `version.txt` =
  1.60.1.70009, the dump's build). Read Blizzard code there first (`SecureTemplates.lua`,
  `SecureGroupHeaders.lua`, `Blizzard_AuraContainer`, …): line numbers in in-game error traces
  match it, and they don't match Retail's. Fall back to the Retail branch of
  `Gethe/wow-ui-source` only for what isn't there. For example, Forever's
  `SecureUnitButton_OnClick` is where `C_ClickBindings` gets the first say on every
  `SecureUnitButtonTemplate` frame, ours included.
- `..\GlassUnitFrames\docs\GLASS-MATERIAL.md` is the write-up of the glass material.

## Reference addons

These live in `C:\Projects\References`. They show what works on this client *in practice*,
which the dump can't tell you. Reason about what they do rather than copying it, and **write
our own code**.

- **`Cell-r274-release\Cell` is the design reference** for *what* group frames and
  click-casting do.
  - It is not Forever-aware. Almost all its secure machinery depends on restricted snippets,
    which are broken here:
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

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70009`),
and warn at login when `GetBuildInfo()` differs. Bump it only after re-measuring in game.

## Toolchain and commands

There is no build system, compiler or package manager; the client interprets the Lua directly.
The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). Use it,
not a newer Lua that may be first on `PATH`.

```powershell
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p File.lua             # syntax check; silent on success
pwsh tests\run.ps1                                                   # luac -p on TOC files + probe + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, run from the repo root
python Tools\make_textures.py                                        # regenerate Media\*.tga (a copy of GlassUnitFrames')
python Tools\make_sound.py                                           # regenerate Media\dispel.ogg (numpy + ffmpeg/libvorbis)
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ RaidProbe) into AddOns
```

- **Default AddOns path:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
  The deploy script takes `-AddOnsPath`.
- **Deploy** rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token; the packager needs it.
- **In game:**
  - Run `/console scriptErrors 1` first, because errors are off by default. Then `/reload`.
  - A brand-new addon folder needs a full client restart.
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
- **Secure snippets are broken.** `loadstring_untainted` is missing, so
  `SecureHandlerWrapScript`, `_onstate-*` attributes and `RegisterStateDriver` throw. **Don't
  introduce a `SecureHandler*`.** Plain `SecureActionButtonTemplate` + `SetAttribute` + insecure
  `PreClick`/`PostClick` **works**, in and out of combat.
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
  `PriestlyProbe`; here that is `ToolsRaidProbe`.

## Workflow and releasing (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review (owner-launched) → squash-merge (by
  the owner). Never commit to `main`.
  Commit or push only when asked. Before committing, `luac -p` must be clean and the tests green.
  **After pushing, check the PR's `package-check` run** (`gh run list`, then `gh run view`).
  CI has no API dump: the stub validates events against `tests/events-70009.txt` instead, so
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
- `.pkgmeta` ignores `.github`, `docs`, `tests`, `Tools`, `AGENTS.md`, `CLAUDE.md`, `README.md`,
  `CHANGELOG.md` and `LICENSE`.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it. The
  porting guide has already had to reverse reasoned conclusions (click-casting, "park it off
  screen", persistence).
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
