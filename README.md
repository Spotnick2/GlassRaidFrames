# Glass Raid Frames

Liquid-glass party and raid frames with click-casting, for **World of Warcraft: Forever**, in the
glass look shared by the Glass addons. It is a streamlined take on Cell: the group frames, the
click-casting a healer lives on, and settings that follow the role you play, without the module
zoo.

## Install

Install **Glass Raid Frames** from CurseForge or Wago (with their apps), or download the zip from
[GitHub Releases](https://github.com/Spotnick2/GlassRaidFrames/releases) and unzip it into the
`Interface\AddOns` folder inside your Forever game folder. Then `/reload`, or start the game.
Blizzard's party and raid frames are replaced at once. `/grf options` (or Esc > Options > AddOns >
Glass Raid Frames) has every setting, and `/grf clickcast` opens the click-casting editor.

## What it does

**One grid that follows the group.** Your party in one row; a raid in columns of five. The grid
follows the roster by itself, in combat too. A healer gets it centred above the action bars, a
caster, melee or tank at the left side of the screen (`/grf layout hud|side` per role), and
`/grf unlock` moves it. `/grf preview 10|20|40` shows how a raid of that size would sit, without
a raid.

**Each frame** shows the name, a class-coloured health bar with incoming heals, a thin power bar,
Dead or Offline, the leader, the raid mark, tank and healer icons and up to three debuffs.
Members out of range fade. The rim lights up under the mouse, your target's frame gets a coloured
rim, and hovering shows the tooltip. Left-click targets, right-click opens the menu (unless you
bind those clicks to something else).

**Pets**, if you want them (`/grf pets`, per role): in a raid, a column of their own beside the
grid; in a party, under their owners.

**Names** show the first name by default, or the first name and surname initial
("Aldric B."), or the full name (`/grf names first|initial|full`). Give anyone a nickname with
`/grf nick <nickname>` on your target, or in Options; it follows that character on all your
characters.

**Indicators.** Your own Renew and Power Word: Shield (Rejuvenation and Regrowth for druids) show
top-right, only yours. Important buffs from others (Blessing of Protection, Power Infusion,
Blessing of Sacrifice, Innervate, Fear Ward, Thorns) show top-left. The Indicators page under
Options adds your own: pick the spells (drag them from your spellbook or type an ID), only yours
or anyone's, a spot on the frame, icons or a coloured square, with a live preview. They're set up
once per class and shared by all your characters of that class (`/grf ind`).

**Settings per role.** Healer, caster, melee or tank, read from your talent points (a priest's
Discipline and Holy count together as healer), or picked by hand per character (`/grf role`).
Each role keeps its own position, frame size, pets, layout and click-cast bindings. When your
talents move you to a role with no bindings yet, you're offered a copy of the old role's.

### Click-casting

The editor (`/grf clickcast`, or the Click-casting button in Options) binds **mouse buttons 1-5**
with any modifier, and **keys**, to a spell, target, menu or a macro of your own. Drag spells from
your spellbook, pin a lower rank, or use **Quick Bind**: hover a spell in the list, then press
the key or click the button you want. Spells are kept by ID, so the bindings work in any client
language.

- **Mouse clicks** work on the frames. Resurrection spells aim at the dead.
- **Keys** work while you hover a frame, on whoever it shows. For a **healer** that's frames
  only: off a frame, the key does its usual action-bar action, so it never heals someone who
  just walked under your cursor. For a **caster, melee or tank**, keys work anywhere under the
  cursor, so a damage spell hits the enemy you hover. `/grf keys frames|anywhere` changes it
  per role.
- **Other frames:** your bindings also work on Blizzard's unit frames and on frames that
  register for click-casting the way Clique's do (Glass Unit Frames does).
  `/grf clickcast ours` keeps them to these frames.

### The look

**Pearl** glass by default, or **Clean** and **Classic** (`/grf look`), with a clear or **smoked**
body (`/grf body smoked`), after a `/reload`. With **Glass UI** installed you can let it set the
glass for every Glass addon at once. **Glass Unit Frames** places your player and target frames
beside the grid.

## Commands

`/grf help` lists them all.

- `/grf options` - the settings; `/grf clickcast` - the click-casting editor
- `/grf clickcast all|ours` - bindings on every unit frame, or these frames only
- `/grf clickcast copy <role>` - another role's bindings into this role's empty list
- `/grf keys frames|anywhere` - this role's keys: on frames only, or anywhere under the cursor
- `/grf role auto|healer|caster|melee|tank` - the role; auto follows your talents
- `/grf unlock`, `/grf lock`, `/grf reset` - move the grid for this role, or put it back
- `/grf layout hud|side` - this role's place; `/grf preview 10|20|40|off`
- `/grf size <width> <height>|reset` - this role's frame size
- `/grf pets`, `/grf solo` - show pets; show your own frame when you're not in a group
- `/grf names first|initial|full`, `/grf nick <nickname>|clear`
- `/grf ind` - indicators: list them, `/grf ind <n> on|off`, `/grf ind reset`
- `/grf look pearl|clean|classic`, `/grf body clear|smoked` (after a `/reload`)
- `/grf blizzard` - Blizzard's party and raid frames back, or hidden again

## Good to know

- **No dispel highlighting yet.** A Decursive-style box that lights up in the colour of the
  button that cures it is planned. The debuffs show, but nothing tells you which you can cure.
- **No mouse-wheel bindings**, on purpose.
- **One click-casting addon at a time.** Don't run it with Clique: both would bind Blizzard's
  frames and undo each other's key bindings.
- **Bar addons that bind through overrides** (Bartender, ElvUI): where a click-cast key falls
  back to its usual action, it clicks Blizzard's action button for that key, not the bar
  addon's.
- **Some changes wait for combat to end:** moving or resizing the grid, a layout or role change,
  and binding changes. The game doesn't let addons change these frames in combat. You're told
  when one is waiting; your bindings keep working until then.
- **The game picks the auras.** Forever hides aura details from addons in combat, so the frames
  hand them to the game to draw. An indicator for someone else's debuff that the game keeps
  secret can't be matched; the Indicators page says so, and the debuff row still shows it.
- **A binding for a spell you haven't learned** stays saved but does nothing until you learn it
  (after a respec, say). The editor flags it.
- **The glass is painted, not real.** The game gives addons no blur, so it doesn't blur what's
  behind it.

## Bugs and ideas

Open an issue on [GitHub](https://github.com/Spotnick2/GlassRaidFrames/issues). With
`/console scriptErrors 1` on, the error text helps a lot; `/grf failures` lists anything the
frames failed to build or register.

## Credits

- The design follows [Cell](https://www.curseforge.com/wow/addons/cell): its frames, its
  click-casting and its indicators. Decursive shapes the planned dispel box. No code is copied
  from either.
- The glass comes from [LibGlass-1.0](https://github.com/Spotnick2/LibGlass), included in the
  download.

## Development

Lua 5.1, no build step. The tests run with a plain Lua 5.1 and a LibGlass checkout next to this
one (`..\LibGlass`, or `$env:LIBGLASS`):

```powershell
pwsh tests\run.ps1        # syntax check plus every tests\test_*.lua
pwsh Tools\deploy.ps1     # the addon and its LibGlass into your AddOns folder
```

## Licence

MIT; see [LICENSE](LICENSE). LibGlass-1.0 (MIT) and the LibStub it bundles (public domain) ship
under their own terms, listed there.
