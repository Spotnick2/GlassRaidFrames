# Changelog

## v0.1.0 - 2026-11-07

The first release: glass party and raid frames with click-casting, for WoW: Forever.

**The frames**
- Your party in one row, and a raid in columns of five, one grid that follows the roster, in
  combat too. Healers get it centred above the action bars; casters, melee and tanks at the
  left side (`/grf layout hud|side` to choose per role). `/grf preview 10|20|40` shows how a
  raid of that size would sit.
- Each frame shows the name, a class-coloured health bar with incoming heals, a thin power bar,
  Dead and Offline, the leader, the raid mark, tank and healer icons and up to three debuffs.
  Out-of-range members fade. The rim lights up on mouse-over, your target's frame gets a
  coloured rim, and hovering shows the tooltip.
- Left-click targets, right-click opens the menu.
- Pets (per role, off by default, `/grf pets`): in a raid, a column of their own beside the
  grid; in a party, under their owners.
- Names: the first name (the default), the first name and surname initial ("Aldric B."), or the
  full name (`/grf names`). Give anyone a nickname with `/grf nick <nickname>` on your target
  or in Options; it follows that character on all your characters.
- Your heals on the frames: your own Renew and Power Word: Shield (Rejuvenation and Regrowth for
  druids), top-right. Important buffs from others (Blessing of Protection, Power Infusion,
  Blessing of Sacrifice, Innervate, Fear Ward, Thorns), top-left. An Indicators page lets you add your own: pick the spells (drag them from
  your spellbook or type an ID), only yours or anyone's, placed anywhere on the frame, with a
  live preview. Set up once per class, shared by all your characters of that class (`/grf ind`).
- Blizzard's party and raid frames are hidden (`/grf blizzard`). The raid manager on the left
  edge stays, for ready checks and world markers.

**Settings per role**
- Healer, caster, melee or tank, from your talent points (a priest's Discipline and Holy count
  together as healer), or picked by hand per character (`/grf role`). Position, frame size,
  pets, layout and click-cast bindings are kept per role.
- When your talents switch your role to one with no click-cast bindings yet, you're offered a
  copy of the old role's (`/grf clickcast copy <role>` does the same).

**Click-casting**
- A click-casting editor (`/grf clickcast`, or the button in Options): bind mouse buttons 1-5
  with any modifier, and keys, to a spell, target, menu or a macro. Drag spells from your
  spellbook, pin a lower rank, or use Quick Bind: hover a spell, then press the key or click.
- Keys work while you hover a frame. For a healer that's frames only: the key never heals
  someone who walks under your cursor in the world, and does its usual action-bar action there.
  For casters, melee and tanks, keys work anywhere under the cursor, so a damage spell hits the
  enemy you hover (`/grf keys frames|anywhere` per role). Resurrection aims at the dead.
- Your bindings also work on Blizzard's unit frames and on frames that register for
  click-casting (Glass Unit Frames does), or on these frames only (`/grf clickcast ours`).

**The look**
- Pearl glass by default, or Clean and Classic (`/grf look`), with a clear or smoked body
  (`/grf body smoked`). Both take effect after a `/reload`. With Glass UI installed, it can set
  the glass for every Glass addon at once.
- The glass comes from LibGlass, a small library shared by the Glass addons, included in the
  download (nothing extra to install).
- Glass Unit Frames places your player and target frames beside the grid.

Settings: Game Menu > Options > AddOns > Glass Raid Frames (`/grf options`). `/grf help` lists
every command.
