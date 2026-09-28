# Forever probe: what GlassRaidFrames needs measured

Milestone 0 of the plan. Nothing here has been measured yet. The design of milestones 1–3
waits on these answers, and each item names the decision it gates.

Addon-agnostic results also go into `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`.

## How to run it

1. `pwsh Tools\deploy.ps1 -Probe`, then **restart the client**, because RaidProbe is a new
   folder. Enable GlassRaidFrames too: the probe's tiles use its glass material when it is
   loaded.
2. In game: `/console scriptErrors 1`, then `/rprobe help`.
3. Everything the probe prints also goes to `RaidProbeDB.log`. When done, **exit the client
   fully**, which is what flushes SavedVariables, then share
   `WTF\Account\<account>\SavedVariables\RaidProbe.lua`. The log survives `/reload` and
   accumulates across sessions; `/rprobe log clear` starts over.
4. Lines stamped with `C` were logged in combat.

You need a group for most items: a party first, then a raid, ideally with a healer class on
your side so real cures exist. A training dummy or a low mob works for combat.

## Checklist

### 1. Group buttons: manual vs header (gates `Roster.lua`)
- [ ] `/rprobe build` out of combat: 45 tiles appear, the player's tile shows, and the rest
      follow the roster.
- [ ] Join and leave a party, out of combat and **in combat**. Check the `roster:` lines: the
      right tiles are shown, names are correct, and there is no `ADDON_ACTION_BLOCKED`.
- [ ] Convert party → raid in combat, if you can arrange it. Note what shows.
- [ ] `/rprobe header` (do it on a separate `/reload`, so the two builds don't interfere):
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
- [ ] `/rprobe clear`, then shift-left: does it fall back to a plain left click (target)?
- [ ] `/rprobe spell <id>` switches the test spell (out of combat).
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
- [ ] `/rprobe enums`: `CustomAuraButtonDispelTypeTextureStyle` has `PreserveAsset`.

### 4. Sounds (gates the alert design)
- [ ] `/rprobe sound`: do you hear the chime (addon `.ogg`) and the raid-warning kit?
      `willPlay` should be true.
- [ ] `/rprobe aurasound` in a group: which struct shapes return a handle and which error? The
      errors name the fields the client expects.
- [ ] `/rprobe aurasound <spellID>` with the ID of a debuff you can reproduce (`/rprobe auras`
      shows IDs out of combat). Does the chime play when it lands **in combat**?
- [ ] `/rprobe aurasound clear` afterwards.
- [ ] `/rprobe auras party1` out of combat: do `HARMFUL` and `HARMFUL|RAID` differ? Is
      `dispelName` readable?
- **Decision:** a dispel-type trigger means full in-combat sound coverage. A spell-ID-only
  trigger means the learned-ID route, with limited coverage.

### 5. Secrecy and range (gates `Frames.lua`)
- [ ] `/rprobe secrets` in a party and in a raid, **out of and in combat**. `S` = secret, `ERR`
      = threw. Check `hp`, `hpMax`, `dead`, `conn`, `role`, `name`, `class`, `guid`,
      `inRange`/`checked`, `leader`, `mark`, and `GetRaidRosterInfo` subgroup.
- [ ] `/rprobe watch`, then walk away from a party member: do `UNIT_IN_RANGE_UPDATE` lines
      arrive, and are the values readable? Is the `UNIT_AURA` payload secret in combat?

### 6. Hiding Blizzard's frames (gates `Blizzard.lua`)
- [ ] `/rprobe hide` in a party and in a raid: which of `PartyFrame` (the classic-style party
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
spell (`/rprobe spell <id>`); pass a rank-specific spell ID to test downranking.
- [ ] `/rprobe mocast`: is `IsMouseoverCastSupported()` true? Then `/rprobe mocast on`, put a
      heal on an action-bar key, hover a probe tile and press the key. Does it cast on the
      hovered member, in combat? What does `mouseoverCastModifier` do? This is the client's own
      feature, so if it works it needs no binding code at all.
- [ ] `/rprobe hoverkeys`: hover a tile and press **8**. Does the `OnEnter bind` line say `ok`
      out of combat, and is it refused in combat (expected)?
- [ ] `/rprobe permkey`: key **9** always runs `/cast [@mouseover,help,nodead] <spell>` from a
      hidden secure button. Does it cast on a hovered tile in combat? What happens when you
      press 9 while hovering nothing? `/rprobe permkey` again releases it.
- **Decision:** keyboard hover-casting is back in scope for milestone 2, through whichever
  route works in combat. With route (c), the addon owns the key only while you are in a group,
  and the options have to say so.

### 7. Scale (gates the tile budget)
- [ ] The `built … in … ms` line after `/rprobe build`.
- [ ] `/rprobe fps` in a raid, out of combat and in combat, with debuffs going on and off.
      Compare with a `/reload` without `/rprobe build`.

## Results

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
- **Still open for the header** (the probe now tests all three):
  1. Children must be **precreated** out of combat (Cell's `startingIndex = -39` trick) so all
     40 exist before combat and can be configured.
  2. A child's unit changes in combat, so its **aura containers must follow with `SetUnit` in
     combat**. With manual buttons the tokens are fixed and this never happens.
  3. Clicks on header children weren't logged: the XML template had no `PostClick`.
- Party→raid conversion in combat is still untested for both approaches.
- The first run's party/raid double set (both shown in a raid) was before the probe hid the
  unused set. That mode switch hasn't been exercised yet.
