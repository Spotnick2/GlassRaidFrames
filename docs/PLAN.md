# GlassRaidFrames: plan (approved 2026-09-28)

## Context

This is a new WoW: Forever 1.60.1 addon (Interface `16001`) in the empty `C:\Projects\GlassRaidFrames`. It gives party and raid frames the same "liquid glass" look as GlassUnitFrames, GlassXp and GlassMiniMapBar.

- **Design reference:** Cell r274 (layout, indicators, click-casting). Streamlined: no module zoo, no layouts or profiles tree, no Spotlight/NPC/Pet frames, no import/export, no raid-debuff database.
- **Headline feature:** click-casting.
- **Second feature:** Decursive-style dispelling. A small box on each frame lights up in the dispel colour, you click it to cure, and a sound plays.

The owner uses Cell today; this replaces it.

**What exploration established** (porting guide, API dump, the two reference addons):

- **Secure snippets are broken.** `WrapScript`, `_onstate-*`, `RegisterStateDriver`/`RegisterAttributeDriver`, `SecureHandlerEnterLeave` and `_initialAttribute-*` all throw. That rules out most of Cell's machinery: headers with snippet init, the `@cell` placeholder rewrite, and the wheel/keyboard `SetBindingClick` snippets.
- **What works:** plain `SecureUnitButtonTemplate` + `SetAttribute` (out of combat), `RegisterForClicks("AnyUp")`, `RegisterUnitWatch`, and insecure Pre/PostClick.
- **`SecureGroupHeaderTemplate` has never been measured.** DinoUF found its init broken and builds `party1-4`/`raid1-40` buttons by hand.
- **Auras are secret in combat for every unit.** Health is secret even out of combat.
  - The answer is Blizzard's `AuraContainer` (`CustomAuraContainerTemplate`): the client picks and draws the auras.
  - Decursive-Forever does exactly this for dispels. It adds one `AddAuraSlot("HARMFUL", {candidateFilters={includeDispelTypes=…}})` per priority, colours the square with `AddDispelTypeTexture` + a `C_CurveUtil` colour curve, and binds mouse button N to the cure of priority N as macrotext.
  - **So the addon never knows who needs a dispel; the *player* sees it**, because the client lights the square. That is how Decursive works on Forever, and we mimic it.
- **Sound:**
  - Out of combat we can read auras (inside `pcall`) and `PlaySoundFile` an `.ogg` we ship. Addon-shipped files play; built-in game paths are refused.
  - In combat the only route is `C_UnitAuras.AddAuraSound(trigger, {unitToken, spellID, soundFileName, outputChannel})`, keyed on spell ID. Decursive learns those IDs out of combat.

## Approach

### Milestone 0: scaffold and probe (issue #1)
- Set up the repo like the siblings: `git init`, a private repo `Spotnick2/GlassRaidFrames`, issue → branch → PR.
- Copy these from `..\GlassUnitFrames` and adapt them:
  - `CLAUDE.md`: keep the Forever facts, testing, workflow and conventions sections. Rewrite "What this is", the layout, and the references (Cell and Decursive as design references, DinoUF `modules\units.lua` for manual group buttons).
  - `.claude/skills/codex-consult/`.
  - `.gitignore`, `.gitattributes`, `.pkgmeta`.
  - `Tools/deploy.ps1` and `Tools/make_textures.py`. The textures need a small-tile variant because raid tiles are about 70×40.
  - `tests/{harness.lua, wow_stubs.lua, run.ps1, test_methods.lua, test_toc.lua}`.
- Lift **`Glass.lua` as-is** (it is self-contained; see `GlassUnitFrames/docs/GLASS-MATERIAL.md` §"lifting"). Also lift the reusable parts of **`Compat.lua`**: `IsSecret`, safe `RegisterEvent`, `ClickEdges`, `HealthPercent` curve, `ClassColor`, `Fail`, `LoadBlizzardAddOn`, `NewHealCalculator`, `MEASURED_ON_BUILD`.
- Build **`Tools/RaidProbe/`**, a throwaway `/rprobe` addon that answers the unmeasured questions before we commit to a design. The design gate is the **full lifecycle**, not "it spawned":
  1. **Header versus manual.**
     - Does `SecureGroupHeaderTemplate` spawn children without `initialConfigFunction`, and do those children keep bindings through join, leave, token reuse, party↔raid conversion, subgroup moves and `/reload`, in and out of combat?
     - Does `RegisterUnitWatch` work on `party1`/`raid1`?
  2. **Casting on `SecureUnitButtonTemplate`.**
     - Test independent payloads: `type1`/`spell1`, `shift-type1`/`shift-spell1`, the `*type3` wildcard fallback, `type2=macro` + `macrotext2`, and clearing a key.
     - Test the `spell` attribute three ways: a **numeric ID**, a bare name (highest rank?), and a rank-qualified name ("Dispel Magic(Rank 1)") for downranking.
     - Pass means a cast in combat on a party member. If `type=spell` fails, fall back to the measured macro route (`macrotext` with `[@unit]`).
  3. **The dispel box stack.**
     - Our secure box button, plus an `AuraContainer` anchored to our own frame. Every generated aura button gets `EnableMouse(false)`, its frame level and its dispel texture **inside `initializeFrame`**, as Decursive does at `Dcr_DebuffsFrame.lua:1168` (the buttons become inaccessible later).
     - Verify clicks reach the box when a new aura appears *in combat*, and that `includeDispelTypes` filtering works on party units.
  4. **`AddAuraSound`.** Does its struct accept anything other than a spellID? Does it fire in combat for party units?
  5. **Secrecy** of `UnitHealth`/`UnitHealthMax`, `UnitIsDeadOrGhost`, `UnitIsConnected`, `UnitGroupRolesAssigned` and `GetRaidRosterInfo` subgroup for party and raid tokens. For `UnitInRange`, check both returns (`inRange`, `checkedRange`) and whether `UNIT_IN_RANGE_UPDATE` is delivered.
  6. **Hiding Blizzard's frames**: `CompactPartyFrame`, `CompactRaidFrameContainer` **and** `CompactRaidFrameManager`, by reparenting, across Edit Mode.
  7. **Scale**: 45 tiles × 2 containers (debuff row + dispel box) with 40 live units and aura churn. Measure frame time, and init time.
- Record the results in `docs/FOREVER-PROBE.md`. Addon-agnostic findings go into `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`.

### Milestone 1: glass party and raid frames (issue #2)
Files, in TOC order: `Compat.lua` → `Glass.lua` → `Engine.lua` → `Roster.lua` → `Frames.lua` → `Auras.lua` → `Blizzard.lua` → `Movers.lua` → `GlassRaidFrames.lua` → `Options.lua`.

- **`Roster.lua`**: **`SecureGroupHeaderTemplate`** (decided by probe item 1, 2026-09-28: it follows joins, leaves and party→raid conversion in combat, and child aura containers can `SetUnit` in combat). No `initialConfigFunction`: the child template is XML, and all 40 children are precreated out of combat (`startingIndex = -39`), then configured (glass, bindings, containers). Header attributes (filters, sort, layout) change only out of combat. The manual-button notes below apply only as the fallback.
  - There are 5 party buttons (`player`, `party1-4`) and 40 raid buttons (`raid1-40`), pre-created at `ADDON_LOADED`.
  - On `GROUP_ROSTER_UPDATE` it works out the mode (solo/party/raid). It lays out raid buttons in 8 group columns by `GetRaidRosterInfo` subgroup, with sorting by index and optionally by role.
  - It applies visibility and anchors **only out of combat**, through the single `WhenOutOfCombat` queue (copied from `GlassUnitFrames.lua`).
  - **Visibility ownership:**
    - One always-shown root per mode, and `RegisterUnitWatch` per button decides show/hide.
    - Out of combat, the roster code unwatches and hides the party buttons while in a raid, and the raid buttons while in a party.
    - Every raid button always has a precomputed, non-overlapping slot (raid index → default grid), so a token the watch shows mid-combat lands somewhere sane.
  - **Mid-combat roster change**, accepted degraded behaviour:
    - Geometry and attributes freeze until `PLAYER_REGEN_ENABLED`, then the layout is recomputed from the latest roster.
    - A party→raid conversion may briefly show both sets.
    - **Identity repaints immediately:** name, class colour, health, status and `UpdateAllAuras` on every tile on `GROUP_ROSTER_UPDATE`. A reused `raidN` token then never shows a stale name for a click that would hit someone else.
- **`Engine.lua`**: adapted from GlassUF's engine. It keeps one tracker per token, `RegisterUnitEvent`, the channels (name, health, status, role, raidmark), and a flush once per frame.
- **`Frames.lua`**: one glass tile per unit. It uses Glass.lua's tint, rim, masked health bar and gloss, with a class-coloured fill.
  - Name via `GetUnitName(unit,false)`, trimmed.
  - Role icon: shown only when `UnitGroupRolesAssigned` is not NONE.
  - Leader and raid mark (sprite sheet).
  - Dead, ghost and offline text.
  - Out-of-range alpha: `UnitInRange` is **secret even out of combat** (probe item 5), so it goes straight to `SetAlphaFromBoolean(inRange, 1, 0.4)` and is never tested in Lua. It updates on a shared ticker, because `UNIT_IN_RANGE_UPDATE` wasn't delivered.
  - Role icon: `UnitGroupRolesAssigned` is plain and returns roles on Forever (probe item 5). Dead, offline, name, class, leader and roster subgroup are plain in combat.
  - Health via secret-safe `SetValue`, never divided in Lua.
- **`Auras.lua`**: one `AuraContainer` debuff row per tile (HARMFUL, a few icons), using GlassUF's `Auras.lua` order (`AddAuraGroup`, then `SetUnit`, then `UpdateAllAuras`, with a refresh on unit change). Nothing is anchored *to* the container.
- **`Blizzard.lua`**: hide the compact party and raid frames using GlassUF's reparent plus deferred `SetParent` hook pattern.
- **`Movers.lua`**: a simplified GlassUF mover, with one anchor for party and one for raid. It uses the drag-the-insecure-mover rule and works out of combat only.

### Milestone 2: click-casting (issue #3)
- **`ClickCast.lua`**: data model from Cell, simplified. It is per character in `GlassRaidFramesCharDB.bindings` = list of `{key = "shift-1", type = "target"|"menu"|"spell"|"macro", value = spellID|macrotext}`.
  - Mouse buttons 1–5 × modifiers (none, shift, ctrl, alt and their combinations).
  - Spells are stored **by ID**, and cast with `type=spell` and the `spell` attribute in whichever form probe item 2 proves. By default the addon **casts the highest rank you know**. A binding can pin a specific rank for downranking only if the probe shows a rank-qualified or numeric `spell` works. Names come from `C_Spell.GetSpellInfo(id).name` (a struct).
  - The button's `unit` attribute supplies the target, so there is no `@cell` rewrite.
  - It re-resolves on `SPELLS_CHANGED`.
  - It is applied to all 45 buttons out of combat, clearing old keys first (Cell's `ClearClickCastings` idea).
  - Defaults: `*type1=target`, `*type2=togglemenu`, **with wildcards**. The template never falls back from `shift-type1` to `type1`, so an unbound modified click would otherwise do nothing (probe item 2).
  - **Self-cast conflict** (probe item 2): the client's SELFCAST modifier (`GetModifiedClick("SELFCAST")`, ALT by default) overrides the button's unit, and a macro too. A binding using that modifier is flagged in the options, with a one-click "set Self Cast Key to None" (`SetModifiedClick` + `SaveBindings`), offered with consent and out of combat only.
- **Keyboard hover-casting: both routes** (owner's choice after probe item 8, 2026-09-28):
  - **Default:** the client's own mouseover cast. The options have a checkbox for the `enableMouseoverCast` CVar. Heals on action-bar keys cast on the hovered frame, in combat, with no binding code, and keys keep their normal action when nothing is hovered.
  - **Optional dedicated keys** (Cell-style, e.g. key 3 = Holy Light rank 7): `SetOverrideBindingClick` (set out of combat while in a group) to one hidden `SecureActionButtonTemplate` per key (both edges), with `macro /cast [@mouseover,help,nodead] <spell>`. Measured working in combat. A second line, `/click [@mouseover,noexists][@mouseover,harm][@mouseover,dead] ActionButton<n>` (the button the key is bound to on the action bar), keeps the key's normal action when no living friendly frame is hovered. Measured in probe item 8: a dedicated key never swallows the key.
  - Mouse-wheel bindings stay out. Rank pinning is required (probe item 2).
- **Options**: a "Click-casting" page in a canvas panel, built GlassUF `Options.lua` style.
  - A binding row list and an "add binding" capture button. It captures the pressed mouse button and modifiers, and refuses duplicates.
  - A type picker using radio buttons (no `UIDropDownMenu`, per sibling rule).
  - A spell picker: a scrollable grid of the player's spellbook icons (`C_SpellBook`), with a text box for an ID.

### Milestone 3: Decursive-style dispel (issue #4)
- **Before building, compare with ForeverUI's route** (`Modules/Frames/GameAuras.lua`): `C_UnitAuras.AddPrivateAuraAnchor` with Blizzard's raid dispel indicator. It uses holder attributes such as `dispel-indicator-option = DispellableByMe`, and the client does the "can I cure this" test. Probe both routes; keep the click-to-cure box either way.
- **`Dispel.lua`**: our own cure table for Vanilla spell IDs, per class:
  - Priest: Dispel Magic, Cure/Abolish Disease.
  - Paladin: Purify, Cleanse.
  - Druid: Remove Curse, Cure/Abolish Poison.
  - Shaman: Cure Poison, Cure Disease.
  - Mage: Remove Lesser Curse.

  - Known cures come from `C_SpellBook.IsSpellKnown` on `SPELLS_CHANGED`, with an explicit preference: Abolish over Cure, Cleanse over Purify, and the rank list for Dispel Magic.
  - The chosen spell per type is **deduplicated by spell**, as Decursive's `Dcr_opt.lua:2334` does. The types it cures are unioned into that spell's filter; a paladin's Cleanse, for example, is **one** slot covering Magic, Poison and Disease.
  - The result is an ordered list of cure *slots* (priority 1, 2, …), with at most 3 for any Vanilla class.
- **The dispel box**, per tile:
  - A small secure button in a corner that we own. It is precreated with the tiles.
  - Its hit area is **always present**. Its visibility never depends on aura state, because a secure frame can't be shown or hidden from a secret.
  - Behind it sits an `AuraContainer` anchored to our own frame, with one aura slot per cure slot (HARMFUL, `includeDispelTypes` = that slot's union).
  - It follows Decursive's rules: the generated buttons get `EnableMouse(false)` and are configured entirely in `initializeFrame`. Higher priorities get higher frame levels, so they stack on top.
  - **Colour = which mouse button to press**, as in Decursive (for example priority 1 red = left, priority 2 blue = right, priority 3 yellow = middle), set with `AddDispelTypeTexture` and a step colour curve.
  - Clicks: **left = slot 1, right = slot 2, middle = slot 3**, as `type=spell` attributes set out of combat. The box has no modifier bindings.
  - The box sits above the tile, so its clicks never reach the tile's click-cast bindings. The rest of the tile keeps them.
  - A tooltip on hover (insecure OnEnter) names each colour and button, and the cure it casts.
- **Sound**:
  - **Out of combat:** a `UNIT_AURA` handler plays a shipped `Media/Sounds/dispel.ogg`.
    - All payload and aura reads happen inside `pcall`.
    - It keeps a per-unit afflicted state (true, false or **unknown** when a read fails) plus a roster-wide count. The sound fires when the count goes from 0 to ≥1 and re-arms only when the **whole roster** is clear.
    - The state is reconciled on roster changes and when combat ends.
  - **In combat, coverage is limited unless the probe proves otherwise.** If `AddAuraSound` has no dispel-type trigger, use Decursive's route:
    - Record dispellable spell IDs seen out of combat in SavedVariables.
    - Register unit × ID sounds out of combat only, and remove stale handles on roster changes.
    - Out of combat, the addon's own sound plays instead, so there are no double alerts.
    - A debuff never seen before won't sound in combat, and the options will say so.

### Milestone 4: polish (later issues, one each)
Heal prediction, aggro border, options for size and spacing, a CHANGELOG, and the first CurseForge tag.

## Adversarial review (Codex gpt-6-astra, high)
It reported 11 findings. All were verified against the cited files and folded in above:
- Identity repaints right away on roster change; visibility ownership and degraded conversion are spelled out.
- Dispel-box click-through follows Decursive's `initializeFrame` and `EnableMouse(false)`.
- Cure slots are deduplicated by spell, and colour means priority.
- The roster-wide sound state keeps an "unknown" value.
- In-combat sound is stated as coverage-limited.
- Explicit rank semantics.
- Lifecycle-level probe gates.
- A scale probe.
- `UnitInRange` reads both returns.
- `CompactRaidFrameContainer` is added.

It found no defect in the probe-first approach, the fixed cure-to-button mapping, the protected out-of-combat scan, the reparenting, the mover direction, or the scope.

## Critical files
- **New** (in `C:\Projects\GlassRaidFrames`): `GlassRaidFrames.toc`, `Compat.lua`, `Glass.lua`, `Engine.lua`, `Roster.lua`, `Frames.lua`, `Auras.lua`, `ClickCast.lua`, `Dispel.lua`, `Blizzard.lua`, `Movers.lua`, `GlassRaidFrames.lua`, `Options.lua`, `CLAUDE.md`, `docs/FOREVER-PROBE.md`, `Tools/RaidProbe/`, `tests/`.
- **Reused from `..\GlassUnitFrames`**:
  - `Glass.lua` (verbatim).
  - `Compat.lua` (subset).
  - `Engine.lua` (tracker, channels, flush).
  - `GlassUnitFrames.lua` (`WhenOutOfCombat`, slash-command pattern).
  - `Blizzard.lua` (reparent and deferred hook).
  - `Auras.lua` (container order).
  - `Movers.lua`.
  - `Options.lua` (canvas panel, `Settings` helpers).
  - `tests/*` harness and `Tools/*`.
- **Design references (read, don't copy; write our own code):**
  - Cell `Modules/ClickCastings/ClickCastings.lua` (`ApplyClickCastings`, `GetAttributeKey`, list pane UI), `Indicators/Built-in.lua`, `Defaults/ClickCasting_DefaultSpells_Vanilla.lua`.
  - Decursive `Dcr_DebuffsFrame.lua:1124-1256` (container slots), `Dcr_DebuffsFrame.lua:1383-1507` (`UpdateAttributes`), `Dcr_opt.lua:2242-2301` (filters and colour curve), `Dcr_12_1_Sounds.lua`, `DCR_init.lua:522-641` (Classic spell table).
  - DinoUF `modules\units.lua` (manual party and raid buttons).

## Verification
- **Offline:** `pwsh tests\run.ps1` (luac -p on TOC files and every `tests\test_*.lua`).
  - The tests cover roster layout and mode switching, out-of-combat deferral (`WoW.blocked` stays empty), binding encoding into attributes, the cure-slot mapping per class, and the strict-global and widget-method checks against the 70009 dump.
  - Each new test is mutation-tested before it is trusted.
- **In game:** `pwsh Tools\deploy.ps1`, `/console scriptErrors 1`, then a full restart for the new folder. The checklist:
  - Solo, party of 2 to 5, and a raid with a group change, both out of and in combat.
  - Every binding (modifier × button) casts on the clicked member, in combat too.
  - A dispellable debuff lights the box in the right colour. Left and right click cure the right type. The sound plays out of combat, and in combat per the probe outcome.
  - Blizzard compact frames stay hidden across Edit Mode.
- Adversarial review of this plan and of significant PRs through `/codex-consult` **when the owner launches it**.
