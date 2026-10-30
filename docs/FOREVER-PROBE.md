# Forever probe: what GlassRaidFrames needs measured

Milestone 0 of the plan. Nothing here has been measured yet. The design of milestones 1–3
waits on these answers, and each item names the decision it gates.

Addon-agnostic results also go into `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`.

## How to run it

RaidProbe is a **ForeverProbe module** (#44; `C:\Projects\WoW\References\Docs\PROBES.md`, and
ForeverProbe's `docs/GUIDE.md`). Its commands were `/rprobe <command>` until then; the results
below keep the commands as they're now typed.

1. `pwsh Tools\deploy.ps1 -Probe`. It deploys the ForeverProbe checkout first
   (`..\ForeverProbe`), then RaidProbe. A `/reload` loads both, new folders included (guide,
   section 7). Enable GlassRaidFrames too: the probe's tiles use its glass material when it is
   loaded.
2. In game: `/console scriptErrors 1`, then `/fp raid` (the command list). `/fp` opens the
   console where the probe's lines go; they no longer go to chat (`/fp mirror on` copies them
   there for a session).
3. Every line also goes to `RaidProbeDB.log`. A `/reload` writes it to
   `WTF\Account\<account>\SavedVariables\RaidProbe.lua`, which a session reads itself. The log
   accumulates across sessions; `/fp raid log clear` starts over. Blocked and forbidden actions
   are logged by ForeverProbe's baseline, in the same console.
4. Lines stamped with `C` were logged in combat.

You need a group for most items: a party first, then a raid, ideally with a healer class on
your side so real cures exist. A training dummy or a low mob works for combat.

## Checklist

### 1. Group buttons: manual vs header (gates `Roster.lua`)
- [x] `/fp raid build` out of combat: 45 tiles appear, the player's tile shows, and the rest
      follow the roster.
- [ ] Join and leave a party, out of combat and **in combat**. Check the `roster:` lines: the
      right tiles are shown, names are correct, and there is no `ADDON_ACTION_BLOCKED`.
- [ ] Convert party → raid in combat, if you can arrange it. Note what shows.
- [ ] `/fp raid header` (do it on a separate `/reload`, so the two builds don't interfere):
      does the header spawn children? Are their units right? Do they survive roster changes in
      and out of combat, and a `/reload`? Do left and right clicks on a child target and open
      the menu?
- **Decision:** use the header only if it passes everything above in combat. Otherwise use
  manual buttons (DinoUF's route).

### 2. Click-cast attributes (gates `ClickCast.lua`)
Click a party member's tile with each combination, in and out of combat. Each click logs what
the secure handler resolved (`click … -> type value`), then `cast sent/succeeded/failed`.
- [ ] shift-left: `spell` = bare name. Does it cast the highest rank?
- [ ] ctrl-left: `spell` = numeric ID. Does it cast, and which rank?
- [ ] alt-left: `spell` = `"Name(Rank n)"`. Does it downrank?
- [ ] shift-right: `macro` + `macrotext` `/cast [@partyN] Name`.
- [ ] middle with any modifier: the `*type3` wildcard.
- [ ] `/fp raid clear`, then shift-left: does it fall back to a plain left click (target)?
- [ ] `/fp raid spell <id>` switches the test spell (out of combat).
- **Decision:** `type=spell` with whichever `spell` form works. If none cast in combat, fall
  back to `macro`.

### 3. The dispel box (gates `Dispel.lua`)
The corner box on each tile has one aura slot per cure you know. It shows the red square for
left, blue for right, yellow for middle.
- [ ] Get a dispellable debuff on a party member (or yourself). Does the box light in the right
      colour, **in combat too**?
- [ ] Click the lit box: does the cure cast on that member, in combat? The log shows
      `click … -> spell <cure>`.
- [ ] Does a debuff that appears *during* combat light the box, and does clicking still reach
      the box? Aura buttons created in combat must not eat the click.
- [ ] Is a debuff of a type you can't cure left unlit?
- [ ] The debuff row (bottom-left icons): do icons show, and do clicks on them reach the tile?
- [ ] `/fp raid enums`: `CustomAuraButtonDispelTypeTextureStyle` has `PreserveAsset`.

### 4. Sounds (gates the alert design)
- [ ] `/fp raid sound`: do you hear the chime (addon `.ogg`) and the raid-warning kit?
      `willPlay` should be true.
- [ ] `/fp raid aurasound` in a group: which struct shapes return a handle and which error? The
      errors name the fields the client expects.
- [ ] `/fp raid aurasound <spellID>` with the ID of a debuff you can reproduce (`/fp raid auras`
      shows IDs out of combat). Does the chime play when it lands **in combat**?
- [ ] `/fp raid aurasound clear` afterwards.
- [ ] `/fp raid auras party1` out of combat: do `HARMFUL` and `HARMFUL|RAID` differ? Is
      `dispelName` readable?
- **Decision:** a dispel-type trigger means full in-combat sound coverage. A spell-ID-only
  trigger means the learned-ID route, with limited coverage.

### 5. Secrecy and range (gates `Frames.lua`)
- [ ] `/fp raid secrets` in a party and in a raid, **out of and in combat**. `S` = secret, `ERR`
      = threw. Check `hp`, `hpMax`, `dead`, `conn`, `role`, `name`, `class`, `guid`,
      `inRange`/`checked`, `leader`, `mark`, and `GetRaidRosterInfo` subgroup.
- [ ] `/fp raid watch`, then walk away from a party member: do `UNIT_IN_RANGE_UPDATE` lines
      arrive, and are the values readable? Is the `UNIT_AURA` payload secret in combat?

### 6. Hiding Blizzard's frames (gates `Blizzard.lua`)
- [ ] `/fp raid hide` in a party and in a raid: which of `PartyFrame` (the classic-style party
      frames, shown by default), `CompactPartyFrame`,
      `CompactRaidFrameContainer` and `CompactRaidFrameManager` exist, and are protected?
      Do they stay hidden?
- [ ] Open and close Edit Mode: do they come back?

### 8. Keyboard hover-casting (gates `ClickCast.lua` scope)
The owner's Cell setup (Anniversary SavedVariables) casts mostly with **keys while hovering a
frame**, not mouse clicks:
- Paladin: 1 Holy Shock, 2 Flash of Light, 3/4/5 Holy Light ranks 7/9/max.
- Priest: 1–8 including Greater Heal rank 2, Renew and Prayer of Healing.
- Shaman: 1–4.
- Resurrection on Shift-R (Alt-R on the druid).

Ranks are pinned (`"635:7"`). Cell does hover keys with restricted snippets, which are broken
here, so three other routes get measured, each out of and **in** combat. Use a helpful test
spell (`/fp raid spell <id>`); pass a rank-specific spell ID to test downranking.
- [ ] `/fp raid mocast`: is `IsMouseoverCastSupported()` true? Then `/fp raid mocast on`, put a
      heal on an action-bar key, hover a probe tile and press the key. Does it cast on the
      hovered member, in combat? What does `mouseoverCastModifier` do? This is the client's own
      feature, so if it works it needs no binding code at all.
- [ ] `/fp raid hoverkeys`: hover a tile and press **8**. Does the `OnEnter bind` line say `ok`
      out of combat, and is it refused in combat (expected)?
- [ ] `/fp raid permkey`: key **9** always runs `/cast [@mouseover,help,nodead] <spell>` from a
      hidden secure button. Does it cast on a hovered tile in combat? What happens when you
      press 9 while hovering nothing? `/fp raid permkey` again releases it.
- **Decision:** keyboard hover-casting is back in scope for milestone 2, through whichever
  route works in combat. With route (c), the addon owns the key only while you are in a group,
  and the options have to say so.

### 9. Spec and role (gates per-role settings, issue #7)
The talent-tab API is gone on Forever, and what `C_SpecializationInfo` returns for Vanilla
trees is unmeasured.
- [ ] `/fp raid spec` on a character with talent points spent. It logs:
      `GetSpecialization`, the `GetSpecializationInfo` rows (name, **role**, **pointsSpent**),
      the active spec group, and whether `EventRegistry` is usable.
- [ ] Spend a talent point, and switch dual spec if available. Which of
      `PLAYER_TALENT_UPDATE`, `CHARACTER_POINTS_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`,
      `PLAYER_SPECIALIZATION_CHANGED` and `TRAIT_CONFIG_UPDATED` are logged? Run `/fp raid spec`
      again after each.
- **Decision:** auto role from the spec if these answer, with the manual `/grf role` override
  either way. Otherwise manual plus a class default.

### 10. Buff and debuff indicators (gates `Indicators.lua`, issue #19)
Only Renew, Power Word: Shield and Weakened Soul are needed. `/fp raid ind` opens a panel of
labelled test containers (numbered like the items below) on yourself. `/fp raid ind party1`
moves it to a party member, in combat too. Do each item out of combat, then in combat.
**Right after casting (within Renew's 15 s), run `/fp raid ind state`:** it logs each aura's
source and filters, and tries to read which rows are lit. The client keeps the buttons' shown
state secret even out of combat (second run), so those reads come back `unknown`: **which rows
light up still needs a look (or a screenshot)**. Everything lands in `RaidProbeDB.log`;
`/reload` writes it to `SavedVariables\RaidProbe.lua`.
- [ ] `/fp raid ind ids`: does every planned spell ID resolve to the right name and rank?
      (A wrong or missing ID shows `nil`.)
- [ ] **1.** Cast Renew and Shield. Does row 1 (`RAID_IN_COMBAT`, no IDs) show both, growing
      left? Row 1b shows all your own buffs, for comparison. `/fp raid ind src` (out of combat)
      prints, for each aura, whether `PLAYER|RAID_IN_COMBAT` keeps it (`IN`) or not (`out`).
- [ ] **2.** Row 2 (your Renew) and 2b (anyone's Renew): icon, swipe and timer text show. If
      your other priest can join: their Renew shows in 2b but **not** in 2.
- [ ] **3.** Shield someone: does row 3's red square show for Weakened Soul? The chat line
      `GetSpellAuraSecrecy(6788 …)` printed when the panel opens says whether the client
      allows it (`NeverSecret` needed). `/fp raid ind src` shows Weakened Soul's `src`.
- [ ] **4.** Row 4 (Renew + Shield IDs): both show, the row grows left, and closes up when one
      ends.
- [ ] **5.** `/fp raid ind reconf` (out of combat): row 2 now tracks Shield at a larger size,
      row 2b stops showing. Again to undo. Any `FAIL` line?
- [ ] **6.** Row 6: with both up, Shield covers Renew (swipe and text too). When Shield
      ends, Renew shows.
- [ ] **7.** `/fp raid fps` (baseline), `/fp raid ind cost`, `/fp raid fps` again. Note the build
      time, button count, heap, and the two fps lines. Then spam heals for a minute and run
      `/fp raid fps` once more.
- [ ] **8.** If you can get a debuff you can dispel: does row 8 (`HARMFUL|RAID`) show it?
- **Decisions:** item 1 decides whether "My heals" needs a spell list. Item 3 decides
  whether a Weakened Soul indicator can ship. Items 4 and 6 decide icon rows and
  single-icon priority. Item 7 decides the default indicator count.

### 7. Scale (gates the tile budget)
- [ ] The `built … in … ms` line after `/fp raid build`.
- [ ] `/fp raid fps` in a raid, out of combat and in combat, with debuffs going on and off.
      Compare with a `/reload` without `/fp raid build`.

## Results

### 4. Sounds (1.60.1.70009, 2026-09-28)
- `PlaySoundFile("Interface\AddOns\RaidProbe\Media\dispel.ogg", "Master")` plays
  (`willPlay = true`, heard). `PlaySound(8959)` plays too.
- `Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }`.
- **`AddAuraSound` requires `spellID`.** Without one (and with `dispelName` or `dispelType`
  instead), it fails with `bad argument #3 … (Current Field: [spellID])`. There's no dispel-type
  trigger. So in combat the alert covers only spell IDs learned out of combat (Decursive's
  route). Out of combat, our own scan plus `PlaySoundFile` covers every dispellable debuff.

### 5. Secrecy (1.60.1.70009, 2026-09-28, raid of 2)
- `C_Secrets.ShouldAurasBeSecret()`: false out of combat, **true in combat**.
- `UnitHealth`: secret, in and out of combat.
- `UnitHealthMax`: plain for the player (92), **secret for the partner**.
- Plain even **in combat**, for both units: `UnitIsDeadOrGhost`, `UnitIsConnected`,
  `UnitGroupRolesAssigned` (`DAMAGER`: roles do come back on Forever), `GetUnitName`,
  `UnitClass`, `UnitGUID`, `UnitIsGroupLeader`, `GetRaidTargetIndex` (nil, unmarked) and
  `GetRaidRosterInfo` (name, rank, subgroup).
- **`UnitInRange` is secret (both returns), even out of combat.** Fade through the client:
  `Frame/Region:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)` or
  `C_CurveUtil.EvaluateColorValueFromBoolean` (both in the dump; the alpha scale, 0-1 or 0-255,
  is to be measured).
- **No `UNIT_IN_RANGE_UPDATE` arrived** while walking out of range and back (watch on for
  30 s), so poll range on a shared ticker.
- The `UNIT_AURA` payload wasn't logged: the probe's watch only covered manual tiles. Nothing
  depends on it, because auras go through `AuraContainer`.

### 6. Hiding Blizzard's frames (1.60.1.70009, 2026-09-28)
- `PartyFrame` (shown), `CompactPartyFrame` (hidden: the raid-style party frames are used in a
  raid), `CompactRaidFrameContainer` (shown) and `CompactRaidFrameManager` (shown) all exist and
  are protected.
- `SetParent(hidden)` out of combat worked for all four, with no errors, and **Edit Mode did not
  bring them back** (owner, visually). The deferred `SetParent` repair hook stayed in place.

### 7. Scale (1.60.1.70009, 2026-09-28, raid of 2)
- The header with 40 precreated children, each with a debuff-row container and a dispel-box
  container (400 row and 40 box aura buttons initialised):
  - 66.4 fps average out of combat, 64.9 in combat;
  - worst single frame 67–69 ms.
- The baseline without the probe wasn't captured, so that spike isn't attributed yet. Recheck
  if stutter is seen.

### 3. The dispel box: deferred
- No character in the group can cure yet (the priest is below Cure Disease at 14; the paladin is
  below Purify). The box's test slot lights for any dispellable type, so lighting and
  click-through can still be checked the next time a dispellable debuff lands. Casting a real
  cure waits for a curer.
- Since the header was chosen, the probe puts the box on header children too:
  `useparent-unit` on the box, whose `unit` can't be set in combat, with its container
  following the child's unit through `OnAttributeChanged`.

### Click-casting routes: tests A-D (1.60.1.70009, 2026-09-29, priest + paladin party)
- **A. Blizzard's Click Cast Bindings** (`C_ClickBindings`; Forever's `SecureUnitButton_OnClick`
  gives it first say on every `SecureUnitButtonTemplate` frame, ours included):
  - the spellbook shows **one entry per spell, at its highest rank** (warlock: Immolate "Rank 2",
    Shadow Bolt "Rank 3"), so a spell binding casts the top rank;
  - **macros can be bound** (the window takes the macro frame), which is how a rank is pinned;
  - casting on our frames wasn't clearly confirmed yet;
  - on that character "Target Unit Frame (Default)" read **Unbound**. Forever's handler then
    refuses `type=target` clicks on every unit frame (`expectBinding` and `bindingType == None`
    → return), ours included.
- **B. Group-only hover key** (`/cast [@mouseover,help,nodead,party][…,raid] Lesser Heal`, then
  `/click [@mouseover,noparty,noraid][@mouseover,noexists][@mouseover,harm][@mouseover,dead]
  ActionButton9`):
  - the partner's frame: Lesser Heal on her (`UnitInParty` true);
  - **two strangers in the world: never healed**, and key 9 fired action button 9 (Smite) instead;
  - nothing hovered: Smite fired;
  - the `[party]`/`[raid]` conditionals apply to the @mouseover unit. **The owner's rule holds.**
- **C. Blizzard's Mouseover Cast** (`enableMouseoverCast`): a stranger hovered in the world was
  **not** healed. With probe item 8 (it casts on our frames in combat), it respects the rule
  natively.
- **D. Alt-9** (the SELFCAST modifier on a *key press*) on the partner's frame cast **on her**.
  Alt self-casts on clicks only (item 2), so Alt-R rez keys work.

### Ranks, macro length, self (1.60.1.70009, 2026-09-29, warlock Morphisto)
- **A lower rank pins by its numeric spell ID.** With Shadow Bolt rank 3 known, a
  `SecureActionButtonTemplate` with `spell = 686` (rank 1) sent `UNIT_SPELLCAST_SENT` spell=686,
  twice. The attribute reaches `CastSpellByID`, which keeps the rank. **Bindings store the exact
  rank's spell ID**, with no rank text and no names.
- **The spellbook holds every rank as its own item** (`C_SpellBook.GetSpellBookItemInfo`: #30
  id 686 "Rank 1", #31 id 695 "Rank 2", #32 id 705 "Rank 3"), although Blizzard's spellbook UI
  shows only the top rank. `C_Spell.GetSpellInfo("Shadow Bolt(Rank n)")` also resolves each ID.
- **A modifier held on a KEY binding does not select `alt-`/`ctrl-` attributes** (measured from
  the log): `CTRL-0`, bound to a button whose `ctrl-type1` was a macro, resolved to the plain
  `type1`/`spell1` and cast Shadow Bolt rank 1, as did `ALT-0`. Mouse clicks do resolve
  modifier prefixes (item 2). So every key binding gets **its own button** with plain
  attributes, which the design already does. The long-macro test must be rerun on its own
  button.
- **Solo, hovering your own frame:** key 9 (the `[party]`/`[raid]` macro) fired action button 9
  (Eureka!, `UnitInParty` false), so `[party]` excludes the player when solo. Still to check in a
  group.
- Test C revisited: the earlier log holds `cast sent: target=<stranger> spell=2050` with no key-9
  press before it, around the Mouseover Cast test. To confirm with the owner whether Blizzard's
  Mouseover Cast healed a hovered stranger.

### 9. Spec and role (1.60.1.70009, 2026-09-28, level-? priest, no talent points)
- **One spec per class.** `GetNumSpecializationsForClassID(5) = 1`. `GetSpecialization() = 1`,
  and `GetSpecializationInfo(1)` = id 1487, name "Priest", **role DAMAGER**, pointsSpent 0; rows
  2-4 are empty. `GetSpecializationRole` and `UnitGroupRolesAssigned("player")` also say
  DAMAGER. **The spec API can't tell Holy from Shadow, or a tank from DPS**, so the automatic role
  can't come from it.
- `C_ClassTalents.GetActiveConfigID()` = 88388: the Vanilla trees appear to live in Retail's
  trait system. `/fp raid traits` maps the config, its trees, currency spent and nodes per subtree
  or column. It's a candidate for "the tree with the most points"; to be run, then run again once
  points are spent.
- **Trait layout (`/fp raid traits nodes`, priest, 0 points):**
  - Config 88388 ("Priest", type 4) has **one** tree (1114), with currency 3820 (quantity, spent
    and spentInTree all 0) and **54 nodes, no subtrees**.
  - The three Vanilla trees are **column clusters on one canvas**, split by gaps of over 2000
    units: posX 1020-2820 (Discipline), 5020-6820 (Holy) and 9080-10880 (Shadow), each at y
    2130-5730.
  - One stray duplicate ("Holy Specialization") sits at x 9280, **y 21300**, off the canvas:
    exclude nodes outside the canvas or not `isVisible`.
  - Forever's trees aren't pure Vanilla (Penance, Divine Aegis and Prayer of Mending are in).
  - **Role rule:** cluster the visible nodes by posX, sum `currentRank` per cluster (trees
    left to right in tab order), and let the tree with the most points pick the role through a
    per-class table. It uses positions only, so it's locale-proof.
  - **A second class confirms it (paladin, 0 points):** config 5079379 ("Paladin"), one tree
    (1100), 50 nodes, the **same column ranges**: 1020-2820 Holy, 5020-6820 Protection,
    9080-10880 Retribution. The order is the tab order, and there is no off-canvas node. The
    layout is shared across classes, so clustering by posX gaps holds.
  - Still to confirm once points are spent: ranks show up in `currentRank` in the right cluster.
- **`EventRegistry` is usable** (`TriggerEvent` and `RegisterCallback` exist), so the
  GlassUnitFrames integration route (#7) is open.

### 8. Keyboard hover-casting (1.60.1.70009, 2026-09-28, priest, header children)
- **The client's mouseover cast works on our frames, in combat.** `IsMouseoverCastSupported()` is
  true. After `C_CVar.SetCVar("enableMouseoverCast", "1")`, Lesser Heal on an action-bar key,
  pressed while hovering the partner's header child, cast on the partner out of combat and in
  combat. There is no `mouseoverCastModifier` CVar (`GetCVar` threw), so no modifier gates it.
- **A permanent override binding works in combat.** Key 9 → a hidden `SecureActionButtonTemplate`
  (both edges registered; PostClick fires twice, one cast) with `macro /cast
  [@mouseover,help,nodead] Lesser Heal` cast on the hovered partner, out of combat and in
  combat. `SetOverrideBindingClick` was set out of combat.
- Hover bindings (`OnEnter` → `SetOverrideBindingClick`) went untested: the probe hooked only
  the manual tiles. They were expected to be refused in combat, and two routes already work,
  so this is dropped.
- **Without a friendly mouseover, a plain dedicated key does nothing** (measured, key 9 with
  nothing hovered): the button is clicked, but no cast is sent, there is no error and no
  self-cast (even with `autoSelfCast = 1`). The key is swallowed.
- **Fallback, first try:**
  - `/click [nomouseover][@mouseover,harm][@mouseover,dead] ActionButton9` after the
    `@mouseover` heal: hovering an **enemy** fired action button 9 (Smite on the mob, in
    combat), so `/click ActionButtonN` works from a secure macro.
  - Hovering **nothing** did nothing, because `nomouseover` isn't a valid macro condition.
  - Retest with `[@mouseover,noexists]`.
- **Fallback works.** The macro was `/cast [@mouseover,help,nodead] <spell>` then
  `/click [@mouseover,noexists][@mouseover,harm][@mouseover,dead] ActionButton9`. With nothing
  hovered, key 9 fired action button 9 (Smite on the target). A friendly frame gets the heal;
  an enemy or nothing gets the key's own action. **A dedicated key never swallows the key.**
  **Item 8 is complete.**
- **Owner's decision: both.** Mouseover cast is the default, with a checkbox for the CVar.
  Optional dedicated keys use the permanent-binding route. Still to measure: what a dedicated
  key does with **no** friendly mouseover, and whether a
  `/click [@mouseover,noexists][@mouseover,harm][@mouseover,dead] ActionButton<n>` fallback line keeps
  the key's action-bar action (`/fp raid permkey fallback`).

### 2. Click-cast attributes (1.60.1.70009, 2026-09-28, priest, header children)
- **All five forms cast out of combat** on a header child: Lesser Heal (2050), logged
  `cast sent … spell=2050`, then `succeeded`.
  - `shift-type1=spell` with `shift-spell1="Lesser Heal"` (name);
  - `ctrl-spell1=2050` (numeric ID);
  - `alt-spell1="Lesser Heal(Rank 1)"` (rank-qualified);
  - `shift-type2=macro` with `/cast [@mouseover,help,nodead] Lesser Heal`;
  - `*type3`/`*spell3` (wildcard).

  Modifier-prefixed attributes resolve independently per button, and the `unit` attribute the
  header set is used as the target.
- **In combat (second run), every form cast.** Name, ID, rank-qualified, the `@mouseover` macro
  and the wildcard all logged `C cast sent` and `succeeded`.
- **Alt goes to the player.** Both alt-left clicks (`alt-spell1`) on the partner's child cast on
  **the player** in combat. Every other form hit the clicked unit. Alt is the client's default
  `SELFCAST` modifier, and it wins over the button's `unit`. This matters for bindings: the owner's
  paladin binds Alt-left and Alt-right in Cell. Next run: an Alt `@mouseover` macro
  (`alt-type2`), and `/fp raid selfcast none` (unbinds the modifier) followed by alt-left again.
- **Self-cast measured (third run).** The client options were Self Cast = "Auto and Key Press",
  key ALT (`GetModifiedClick("SELFCAST") == "ALT"`, `autoSelfCast = 1`). In combat, with ALT:
  - alt-left (`spell`) cast on the player;
  - alt-right (`macro /cast [@mouseover,help,nodead]`) **also** cast on the player, so a macro
    doesn't escape it.

  After `SetModifiedClick("SELFCAST", "NONE")` + `SaveBindings`, alt-left cast on the clicked
  partner, twice, in combat. **Rule: a binding on the SELFCAST modifier always self-casts.** The
  addon detects the conflict and offers to set the key to NONE (a global client setting, only
  with consent, out of combat). It never changes the key on its own.
- One shift-left on the partner also landed on the player, while later identical clicks
  didn't. That fits `autoSelfCast` retargeting an invalid (out-of-range) unit. It's unconfirmed;
  `/fp raid selfcast` now logs the CVar.
- **Clearing a modified binding does not fall back to `type1`.** After clearing `shift-type1`,
  shift-left resolved to `nil`. The template tries `shift-type1`, `*type1`, `shift-type*`,
  `*type*` and a bare `type`, but never `type1`. **Defaults must be `*type1=target` and
  `*type2=togglemenu`**, so that unbound modified clicks still target and open the menu.
- **Still open:**
  - **downranking**, which needs a character with two ranks. Only rank 1 was known, so the ID
    and `Name(Rank 1)` forms were accepted but didn't prove they choose a lower rank.

### 1. Group buttons (1.60.1.70009, 2026-09-28, party of 2, converted to a raid of 2)
- **Manual buttons work, in and out of combat.** 45 `SecureUnitButtonTemplate` tiles with
  `RegisterUnitWatch` on `player`/`party1-4`/`raid1-40`, built out of combat, in 164 ms with
  glass.
  - A member leaving **in combat**: the unit watch hid `party1` (`C roster: … shown tiles:
    player`).
  - Joining out of combat: `party1` showed. Party→raid: `raid1`, `raid2` showed. Raid→party:
    they hid.
  - In a raid in combat, the right tiles stayed shown.
  - **No `ADDON_ACTION_BLOCKED`/`FORBIDDEN` anywhere.**
- As designed, the probe never hides the party set in a raid. In a raid both sets showed
  (`player,party1,raid1,raid2`), which confirms that party tokens stay valid in a raid. The
  roster code has to unwatch the party set out of combat.
- Right-click on a tile opened the menu (`togglemenu`). The one `-> nil` was a right-click on
  the corner box, which has no second cure on that character. That's correct.
- **`SecureGroupHeaderTemplate` spawns children without `initialConfigFunction`**, created out
  of combat in a raid of 2: `child1 = raid1`, `child2 = raid2`, both shown, sized by the XML
  template.
- **The header follows the roster in combat** (second run, same day):
  - Raid→party out of combat: `child1` became `player` and `child2` became `nil`, then
    `party1`.
  - The partner leaving **in combat**: `child2` → `nil`, hidden.
  - Rejoining **in combat**: `child2` → `party1`, shown.
  - No blocked actions.
  - The header's own restricted-free update code runs in combat, and our insecure
    `OnAttributeChanged` on its children fires in combat too.
  - Re-created after `/reload`, it spawned `raid1`/`raid2` again.
- **Third run: the header passes the full lifecycle.**
  - All 40 children were precreated out of combat (`startingIndex = -39`, `Show`, then back to
    `1`), each with its own debuff-row `AuraContainer`.
  - In combat: the partner left (1 shown), rejoined (`party1`, 2 shown), and the group was
    **converted party→raid** (`raid1`, `raid2`), all live.
  - **`container:SetUnit(newUnit)` + `UpdateAllAuras()` succeeded in combat on every
    reassignment.**
  - No blocked actions.
- **Decision: `SecureGroupHeaderTemplate`**, with no `initialConfigFunction`, the child
  template in XML, and all 40 children precreated out of combat. Unlike manual buttons, it
  keeps sorting and grouping in combat. Its aura containers follow each child's unit through
  `OnAttributeChanged`.
- Clicks on header children work: left-click `raid1` → `target`, right-click `raid2` →
  `togglemenu` (fourth run). **Item 1 is complete.**
- **Was open for the header** (resolved by the third run, except clicks):
  1. Children must be **precreated** out of combat (Cell's `startingIndex = -39` trick) so all
     40 exist before combat and can be configured.
  2. A child's unit changes in combat, so its **aura containers must follow with `SetUnit` in
     combat**. With manual buttons the tokens are fixed and this never happens.
  3. Clicks on header children weren't logged: the XML template had no `PostClick`.
- Party→raid conversion in combat is still untested for both approaches.
- The first run's party/raid double set (both shown in a raid) was before the probe hid the
  unused set. That mode switch hasn't been exercised yet.

### 10. Indicators, first run (1.60.1.70205, 2026-10-04, priest, party of 2)

- **`GetSpellAuraSecrecy` is `ContextuallySecret` for all six** planned spells (Renew, PW:S,
  Weakened Soul, Power Infusion, Fear Ward, Thorns). A harmful aura on a friendly is matched by
  ID only when `NeverSecret` (`CanApplyIdentityCandidateFilters`), so **Weakened Soul can't be
  matched by ID**.
- **Cost of the planned defaults is too high:** 40 tiles × 4 containers (3 groups + 1 slot) =
  **1240 buttons, 398 ms to build, Lua heap +49.8 MB; 92.7 → 60.2 fps average, worst frame
  21 → 49 ms**, idle. Groups pre-create 10 buttons each; defaults must lean on slots (1 button
  each), with icon rows rare.
- `ind reconf` (filters, slot size, enable) ran both ways with no failure.
- `PLAYER|RAID_IN_COMBAT` excluded Power Word: Fortitude (right for a "my HoTs" filter).
  Renew and Shield had expired before `src` ran: item 1 still open. Which rows lit wasn't
  captured; `ind state` was added for the next run.

### 10. Indicators, second run (1.60.1.70205, 2026-10-04, priest, solo and in combat)

Seen on the panel (screenshots by the owner), the same out of and in combat:
- **Row 1 `HELPFUL|PLAYER|RAID_IN_COMBAT`: empty.** `src` agrees: Renew and Shield are `out`.
  Vanilla spells don't carry the raid-frame flag here, so **"my heals" needs spell IDs**.
- Row 1b `HELPFUL|PLAYER`: Fortitude, Renew, Shield. Rows 2/2b (Renew slots, mine/anyone):
  Renew with its timer text. **Slots, `PLAYER` and duration text work in combat.**
- **Row 3 (Weakened Soul by ID): empty**, as `ContextuallySecret` predicted. Weakened Soul's
  `src` is the casting priest (`player`, 15 s) and `HARMFUL|PLAYER` keeps it (`src`). It
  already shows in the plain `HARMFUL` debuff row of the real tiles.
- Row 4 (Renew + Shield IDs, row growing left): both show, right-aligned; the order changes
  (client sort). Row 6: **Shield covers Renew** (stacked slots, higher frame level wins).
- Row 8 `HARMFUL|RAID`: no dispellable debuff was available; untested.
- **`IsShown()` on container buttons is secret even out of combat** (`ind state` read
  `<secret>`): an addon can't tell which indicators are lit, only the eye can.
- `ind ids`: all 50 planned IDs resolve to the right names (11 spells, every rank). Subtext
  ("Rank 1") only comes back for ranks the player knows.
- Cosmetic: the default duration text ("28 s") overflows a 16 px icon. `|R` inside a label is
  read as a colour code.
- Not tested: another priest's Renew in the "only mine" slot (no second priest available).

### 11. Hover keys in combat, secure snippets again (1.60.1.70425, 2026-10-15/16, priest, party of 2)
The owner reported a hover key (6 = Lesser Heal) healing them, not the hovered member. Measured
with `/fp steps raid hoverkey`, `hoverkeycombat`, `snippets` and `hoverkeyfix`:
- **`[@mouseover,party]` reads false in combat.** Over the partner's tile (`unit` = party1),
  out of combat every condition of the group-only macro read yes and the heal (2052) landed on
  her. In combat `[@mouseover,party]` read **no** while `UnitInParty("mouseover")` was true;
  `[help]`, `[nodead]`, `[exists]`, `[@party1,exists]` still read yes. So the macro took the
  `/click ActionButton6` fallback, and `autoSelfCast` sent the bar's rank-1 heal to the player.
  `[group]` / `[@mouseover,group]` test the player, not the unit: no help.
  Item 8's test B was only ever run out of combat.
- **Secure snippets run on 70425**, although `loadstring_untainted` is still absent from `_G`:
  `Execute` ran, a `RegisterStateDriver` `[combat] in; out` delivered `out`, then `in` in combat,
  and a `SecureHandlerWrapScript` `OnEnter` running `self:SetBindingClick(true, "7", self)` (with
  `OnLeave` → `self:ClearBindings()`) made 7 click the hovered button, **in combat too**; off the
  button 7 did its normal action. Clique 5.1.3-alpha turned its Forever snippet block off too.
- **The fix, measured:** keys bound only while a group tile is hovered (`ClickCast.lua`). Keys 1,
  4 and 7 with the partner's tile hovered: Renew on her, out of combat and in combat. Off the
  frames: the action-bar action, in and out of combat. Unhovered, `GetBindingAction(key, true)`
  is the base binding: nothing is bound permanently.

### 12. The hover-key member gate on a target frame (1.60.1.70450, 2026-10-18, priest, party of 2)
For #61 (click-casting on any unit frame): a target or focus frame can show a stranger, so its
`OnEnter` snippet asks the restricted `UnitPlayerOrPetInParty` / `UnitPlayerOrPetInRaid` before
binding. `[party]` reads false in combat (item 11), so these were measured with
`/fp steps raid ufgate` (rev 2): a box bound to `target`, wrapped against a
`SecureHandlerBaseTemplate` header, recording the answers on itself and binding 7 only on a yes.
Each press logs `InCombatLockdown()`. Rev 1's fight ended before the presses, and rev 2 checks for that.
- **In combat** (lockdown held for the whole run, every press `combat=true`):
  - party member (Kaleid): `UnitPlayerOrPetInParty("target")` **yes**, so 7 was bound and
    reached the box;
  - yourself, grouped: **yes**;
  - a stranger (Mye Zugga): **no**, so 7 kept its action-bar action (Renew on the target).
- **Out of combat** (run #175): the same three answers.
- Unlike `[party]`, the restricted function keeps answering in combat. No error, and no secret
  (a secret would have thrown on the truth test and left the attribute at `threw`).
- With the boar targeted, the gate read no and 7 fell back to the bar's Renew, which
  `autoSelfCast` sent to the player. That's the expected fallback (step 5 of run #178 hovered
  with the wrong target).
- Not measured: `UnitPlayerOrPetInRaid` in a raid (party only), or a group pet.
- **Then dropped (owner, 2026-10-18):** Cell and EllesmereUI cast on whoever a frame shows,
  strangers included, and so does GlassRaidFrames now. The measurement stays for anyone who
  wants a group-only frame.

### 13. Keys anywhere: a spell's reaction, a world enemy (1.60.1.70450, 2026-10-18, priest Karuzo, run #188)
For #63 (hover keys anywhere for caster, melee and tank). Measured with `/fp steps raid worldkey`
(rev 2). Key 7 was bound for good (`SetOverrideBindingClick`) to Shadow Word: Pain in the shipped
shape (`/cast [@mouseover,harm,nodead] …` then `/click … ActionButton7` on the exact complement),
and key 8 likewise to Renew with `help`. The bar's 7 held Renew.
- **`C_Spell.IsSpellHarmful` / `IsSpellHelpful` answer plainly** for 32 first ranks across eight
  classes, learned or not, with no error and no secret. Damage, debuffs and crowd control
  (589, 585, 8092, 686, 172, 5782, 853, 370, …) read harmful only. Heals and buffs (139, 2050,
  17, 1126, 586 Fade, …) read helpful only. **Both read false** for Resurrection (2006) and for
  Dispel Magic (527, unlearned on Karuzo), so `API.SpellReaction` gives them `help`, as intended.
- **An enemy in the world, in combat:** 7 over the Elder Mottled Boar cast Shadow Word: Pain on
  it (`UNIT_SPELLCAST_SENT` target = the boar, under lockdown). The two presses before that
  failed with only `UNIT_SPELLCAST_FAILED` for 594 and no `SENT` (most likely out of range): the
  macro still picked the spell.
- **An enemy in the world, out of combat:** one press, again `FAILED` for 594 with no `SENT`. The
  macro picked the spell, but no cast landed out of combat in this run.
- **Fallbacks:** 7 over a friendly character, and 7 over nothing in combat, both cast the bar's
  Renew on the player (`autoSelfCast`, as in item 11), never Shadow Word: Pain. 8 over a friendly
  character in the world (Awlie Doombow) cast Renew on her.
- **The bare name casts the highest rank:** 594 (rank 2), not the first rank 589.
- **Rev 2's checks failed falsely** on the two enemy steps. They compared the cast with the first
  rank's ID and read only the step's last cast, which was the owner's own Lesser Heal. Rev 3
  counts any cast of the step, at any rank (by the client's name), sent or failed.
- The release step ran while still in combat and was refused ("out of combat only"). The
  `/reload` dropped the override bindings.

### 14. The group layout, M1-M4 (1.60.1.70450, 2026-10-18, hunter with a pet, party of 2 → raid of 2, run #238)
For #69 (the plan: Glass UI's `docs/GROUP-LAYOUT.md`). Measured with `/fp steps raid layout`
(rev 4), GlassRaidFrames off. Cells 96×60, raid-pet cells 64×28, party-pet buttons 96×30. UIParent
was 2133.3×1200 (scale 0.64, 3840×2160, `useUiScale` 0). Header facts that hold for any addon are
in the porting guide ("`SecureGroupHeaderTemplate` layout: what holds").
- **M1, the sets hold.**
  - The row: a party of 2 gave 198×60, with its bottom at the baseline + 68 (236.9) and centred.
  - The columns (forced; the beta can't gather 6) gave 96×126 with its bottom on the baseline
    (168.9).
  - Swaps out of combat: the batch with the clear held. Without the clear, the old anchors stayed
    on the shown cells (2×2 instead of 2×1, two anchors a cell).
  - The same-value refresh (`point` set to its own value) fired and re-laid every time, so the
    `rpRefresh` fallback never ran.
- **M1, in combat.** Under the forced columns, the other player leaving in combat shrank the grid
  to one cell (96×60), and inviting them back grew it to 96×126. Its bottom stayed at 168.9 and
  nothing was blocked (no `ADDON_ACTION_BLOCKED` in the session). Converting to a raid in combat
  switched the cells from `player, party1` to `raid1, raid2`.
- **A stale column anchor doesn't stretch the cell** (the new `collapse` step). Precreation left the
  grid's child 1 with 2 anchors (the pet header's with 0: no pets were listed, so it was hidden and
  cleared). Two rows back to one without the clear left child 1 with `LEFT` + `BOTTOM`, but it
  stayed 96×60 at the grid's left edge, with the grid at 198×60, through one more pass. So a raid of
  6 falling to 5 in combat under the columns should keep its cells (the columns' `TOP` + `LEFT` pair
  is unmeasured).
- **M2: the raid-pet header follows the grid in combat.** Its top-left stayed 6 right of the grid's
  top-right through 126 → 60 → 126 (top 294.9, 228.9, 294.9). In a raid, the pet was listed
  (`cells=1`, 64×28).
- **M3: the bars.**
  - The main bars' top is 132.6 (MultiBarBottomRight), so the baseline (168.9) clears them by 36.
  - The pet action bar (x 641-896, top 253.1) sits left of a small grid, under GlassUnitFrames'
    player frame. The probe's check failed because its footprint (HALF: 8 columns and 4 pet
    columns) took it in. The owner judged the party and the small raid clear.
  - But the columns' bottom (168.9) is 84 below the pet bar's top. So a grid more than about 340
    wide (5 columns of 80: a raid of 21 or more) would reach over a hunter's or warlock's pet bar.
- **M4: the party-pet holder fails in combat.**
  - Out of combat it holds: in the party the holder was shown, with the pet under the player's
    cell. Under the columns its driver was `hide`. In a raid, `[group:raid]` hid it.
  - **Converting to a raid in combat left it shown** until combat ended (`SecureCmdOptionParse`
    still said `show` 6 s later), on top of the raid-pet column that listed the same pet. The cell
    above it was `raid1`. `[group:raid]` reads false in combat, like `[party]`/`[raid]` (item 11).
  - **The fix holds: `[@raid1,exists] hide; show`** (`/fp steps raid raidunit`, rev 1, run #240,
    same day, party of 2). A frame behind it was shown in the party. A conversion to a raid **in
    combat** hid it within 0.3 s (it parsed `hide`, while `[group:raid]` still parsed `show`). The
    other player leaving, still in combat, showed it again. Nothing was blocked. GlassUI#35 adopts
    it if it holds.
- **The owner's concern:** in the raid, the raid-pet column sat over GlassUnitFrames' target
  debuffs. The probe announces nothing, so GlassUnitFrames didn't move. The build's announced
  rectangle includes the pet column. But a column that appears in combat (a raid's first pet, or a
  conversion) can't push GlassUnitFrames aside until combat ends.
- The run itself:
  - The first leave step failed: combat ended before the other player left. The leave came in the
    next combat, during the rejoin step, and the log has it (`GROUP_ROSTER_UPDATE` under lockdown).
  - Five of the nine screenshots timed out (`no SCREENSHOT_SUCCEEDED within 5 s`). The other four
    were read, then removed.

### 15. The shipped group layout in game (1.60.1.70450, 2026-10-19, GRF#72, two accounts, runs #255-#259 and #184-#186)
Measured with `/fp steps raid grid` (rev 1) on main after #72. Account 1 played healer (HUD; first
as melee, side), account 12 played caster (side) with a pet. UIParent was 2133.3×1200.
- **The layout holds what it announces.** Solo, party of 2 and a raid of 2: the grid's GetRect
  matched the client's size formula and `LayoutState` (top, the bottom at baseline + 68 for the
  row, centred on the HUD), with at most one anchor a cell.
  - Healer HUD: base 168.9, the party's union 967.7..1165.7. The owner: centred above the bars,
    clear of them, GUF's frames beside it.
  - Side (melee, caster): the grid's left edge at 30, its bottom at 575 (507 + 68).
- **Pets.** The party's pet row sat under its owner (Tarthosuk under Kaleid). In the raid of 2, the
  pet went to the column on the grid's right, the holder hid, and the announced width was the grid
  plus one reserved column (198 + 70). The owner: the column is clear of GUF's target and debuffs.
- **Combat** (account 1): the other player leaving emptied the grid, and the invite back refilled
  it (`player, party1`), with the set and the grid's bottom unchanged, no announcement in combat,
  and nothing blocked. One announcement followed after combat. Account 12's in-combat steps ran
  out of order: Next before the leave, and combat ended before the invite.
- **`/grf layout off`** plus `/reload` brought the eight-group grid back where the owner had left
  it (announced as `legacy`), on both accounts. `/grf layout on` brought the layout back.
- **The first placement after a load uses UIParent's size before the UI scale applies**
  (1365.3×768). Right after the `/reload`, the healer's grid was announced at base 108.1, centred
  on 682.7. The caster's side baseline was at 291. Both were corrected 1.1 s later (168.9 and
  1066.6, 507), when an event re-ran the layout. Which event, and whether it comes before the
  loading screen lifts, is unmeasured. GUF follows the wrong first announcement too.
- **The side default sits on side action bars.** At x 30 its first cell covered GlassActionBars'
  vertical bars at the left edge (MultiBar5 and 6, x 2-87). The legacy grid, placed by hand at
  135.7, didn't. The owner: the side grid must coordinate with GAB when a bar is on the left or
  right.
- Both accounts answered "unsure" to "did anything move in combat". The owner saw nothing move,
  but was busy reading the probe panel. The checks found the grid held.

### 16. When UIParent reaches its real size at login (1.60.1.70450, 2026-10-19, two accounts, runs #262 and #190)
Logged by RaidProbe's login logger (`Layout.lua`) on a `/reload`, at UIParent 2133.3×1200 (scale
0.64). In order, all within 0.1 s of the probe loading:
1. `DISPLAY_SIZE_CHANGED` and `UI_SCALE_CHANGED` with UIParent still at **1365.3×768, scale 1**;
2. the same two events again at **2133.3×1200, scale 0.64**;
3. `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD` and `LOADING_SCREEN_DISABLED`, all at the real size.

Glass Raid Frames builds at `ADDON_LOADED`, before step 2, so its first placement used 1365×768
(item 15). Its queued refresh ran 1.2 s after `LOADING_SCREEN_DISABLED`, so the wrong place was
on screen for about a second. So the group layout waits for `PLAYER_LOGIN` before its first
placement and announcement, which snaps, and any re-placement after a screen-size or scale event
snaps too.

**With that fix** (`/fp steps raid login`, run #266-#269, account 1):
- On a `/reload`, `LayoutState` was nil before `PLAYER_LOGIN`. The first announcement came at
  `PLAYER_LOGIN`, already on the real size (base 168.9). A second identical one followed 1 s later
  (the queued scale refresh).
- **A full logout and login** gives the same order: the size was real at `PLAYER_LOGIN` (3.8 s
  after load). The party wasn't listed yet, so the first announcement said nothing is shown
  (width 0). The party arrived and was announced 1.7 s later, as the loading screen lifted
  (`LOADING_SCREEN_DISABLED`). Cells that weren't shown before appear in place; they don't glide.

### 17. The preview and the glide in game (1.60.1.70450, 2026-10-19, healer, party of 2, run #270)
The owner's acceptance of the second half of #69 (GRF#74), `/fp steps raid glide` (rev 1), with
Glass Unit Frames loaded and following. Every answer was yes, and every check passed.
- **The preview** announced each tier's footprint on the baseline (168.9): 10 is 268 wide (two
  columns and the pet column), 20 is 472, and 40 is 822 (eight columns of 80 and two pet columns
  for 12 pets), each 324 high. Glass Unit Frames' player and target glided out beside each, at
  their own height, and back when it ended.
- **Names at 80 wide** were readable, and the long ones were shortened by the client
  ("Drakuza…", "Elegiadel…", "Sumnerw…").
- **The glide:** the owner judged the cells' glide to the side and back as smooth as Glass Unit
  Frames' zoom.
- **Combat starting ended the preview** at once, before the lockdown. Nothing was blocked, and
  nothing was announced in combat. (The preview's end touches only insecure frames and alpha,
  so this says nothing about whether the lockdown was already on: item 18.1.)

### 18. The taint and combat-lockdown audit (#78): what the fixes rest on

The audit (reviewed to consensus with Codex, 2026-10-30; the beta was closed) changed code and
the test harness on assumptions this checklist measures. Guided procedures in RaidProbe,
`/fp steps raid <name>`, from 2026-11-04. Each names the fix it decides.

- [ ] **18.1 The lockdown's order.** Is `InCombatLockdown()` already true inside a
      `PLAYER_REGEN_DISABLED` handler (Retail's order, assumed by the harness's `enterCombat`
      and by the position setters, F2)? Does `PLAYER_REGEN_ENABLED` ever arrive with it still
      true (the queue's retry, F3)? Log both at every fight of a session.
- [ ] **18.2 Protection by parent.** `IsProtected()` of a tile's `body` with indicators attached
      (does an `AuraContainer` child protect its parent?), of the party-pet holder, the layout
      box (`GlassRaidFramesLayoutBox`) and the key owner. Decides whether the glide may ever
      run into a lockdown.
- [ ] **18.3 Identity secrecy at 40, in combat.** Each `UnitName` return separately (player, a
      member, the target), `GetUnitName`, `UnitClass`, `UnitGUID`, roles, leader, `UnitIsUnit`,
      `UnitExists`, `IsInRaid` (item 5 was a raid of 2). The first return handed raw to
      `SetText` renders; a tile whose token moves to another person replaces the old name (F1).
      Also the value of `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR`
      (the fix falls back to a space).
- [ ] **18.4 A raid night.** `/grf failures` afterwards (the blocked-action record, F4), fps with
      roster churn, and a dev counter of `childUnitChanged` calls per `GROUP_ROSTER_UPDATE` and
      the cost of `UpdateAllAuras` on a same-token reflow (F6/F7, deferred until this).
- [ ] **18.5 Hide while hovered.** Does `OnLeave` fire when a hovered tile hides? The rim and
      the tooltip after a hovered tile hides, and after an unrelated tile hides while another
      frame owns the tooltip (F5).
- [ ] **18.6 Interrupted drags**, all three blocks (the layout grid, the legacy grid, the legacy
      pets): the saved coordinates, the placement and the announcement after combat (F2).
- [ ] **18.7 A stationary cursor.** Change the role, a key row or the Anywhere mode, let it apply
      after a fight, and reflow or hide/show tiles under a cursor that does not move; record the
      bindings and the `OnEnter`/`OnLeave` `motion` argument (the accepted gap).
- [ ] **18.8 Harness assumptions.** `RegisterForDrag` and `SetMovable` on a protected frame in
      combat (not flagged protected in the 70532 docs), and an insecure `SetOverrideBindingClick`
      / `ClearOverrideBindings` in combat on a protected and on a plain owner: the effect and
      the blocked-action event, since the client can refuse silently.
