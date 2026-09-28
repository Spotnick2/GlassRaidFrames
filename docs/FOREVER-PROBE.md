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
- [ ] `/rprobe hide` in a party and in a raid: which of `CompactPartyFrame`,
      `CompactRaidFrameContainer` and `CompactRaidFrameManager` exist, and are protected?
      Do they stay hidden?
- [ ] Open and close Edit Mode: do they come back?

### 7. Scale (gates the tile budget)
- [ ] The `built … in … ms` line after `/rprobe build`.
- [ ] `/rprobe fps` in a raid, out of combat and in combat, with debuffs going on and off.
      Compare with a `/reload` without `/rprobe build`.

## Results

_Not measured yet._
