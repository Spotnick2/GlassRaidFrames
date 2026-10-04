# Changelog

## Unreleased

- Glass party and raid frames. Your party in one column; in a raid, one column per group.
  They follow the roster in combat too.
- Each frame shows the name, a class-coloured health bar, Dead and Offline, the leader, raid
  mark and tank/healer role icons, and up to three debuffs. Out-of-range members fade.
- Left-click targets, right-click opens the menu.
- Settings per role: healer, caster, melee, tank. The role follows the talent tree with the
  most points, or pick it yourself per character (`/grf role`). The healer layout sits in the
  lower middle; the others default to the left side. Moving the frames only moves them for
  your current role.
- Options under Game Menu > Options > AddOns > Glass Raid Frames (`/grf options`).
- Pets: an option to show pets (per role, off by default, `/grf pets`) in a column of their own right after your last group, movable on their own in unlock mode.
- Incoming heals show on the health bars, as on Glass Unit Frames.
- A thin power bar under the health bar. The frame's glass rim lights up on mouse-over, and your
  target's frame gets a coloured rim.
- Resizable frames, per role (width and height sliders, or `/grf size <w> <h>`). The default is
  larger, like Cell's, with the name growing with the frame.
- Click-casting (Options > AddOns > Glass Raid Frames > Click-casting): bind a spell to any key
  or modifier+click, per role. Keys work while you hover a group member's frame and never hit
  a stranger in the world; anywhere else they do their usual action-bar action. Drag spells
  from your spellbook, and pin a lower rank with one click. Resurrection binds aim at dead
  group members.
- Blizzard's party and raid frames are hidden (`/grf blizzard` toggles it).
- `/grf unlock` to move the frames, `/grf reset`, `/grf solo` to show your own frame when not
  in a group.
- The glass look comes from LibGlass, a small library shared by the Glass addons, included in
  the download (nothing extra to install).
