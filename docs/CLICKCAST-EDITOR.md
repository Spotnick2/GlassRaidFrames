# Click-casting editor (#50)

Open **Options > AddOns > Glass Raid Frames > Click-casting**, or use
`/grf clickcast`. The main page button toggles a dedicated glass window; the old
Click-casting subcategory is removed. The editor requires no additional library.

## Using the editor

- **Input first:** Add binding, record a key or click inside the recording area,
  choose an action, then Add binding to save.
- **Spell first:** Browse, select a learned spell, Create binding, record, save.
- Select a saved row to edit it. Its input, action and rank cells are shortcuts.
  The saved assignment keeps working until Save changes succeeds. Cancel restores
  the saved values. Browse returns to action selection without a selected row.
- Role buttons edit this character's Healer/Caster/Melee/Tank bindings. They do
  not change the active role, automatic role detection or frame layout. The
  header identifies an active role different from the one being edited.
- Default targeting and unit-menu rows explain the implicit left/right clicks.
  Defaults also apply with modifiers unless an explicit assignment overrides
  that combination. Default rows are not written to SavedVariables.
- A conflicting input names the existing action. Replace on save grants a
  replacement only for that draft; choosing another input revokes it. Remove
  requires confirmation. Navigation with unsaved changes offers Save, Discard
  and Keep editing (Save is unavailable for invalid drafts or during combat).
- Quick Bind is optional. Finish text entry with Enter/Escape, hover a spell,
  then press its desired input. Mouse capture requires a fresh press and release
  on that spell. Scrolling or leaving disarms capture. Assignments are visibly
  staged until Apply changes. Escape stops capture without applying anything;
  Discard removes the entire pending batch. Saved conflicts and staged conflicts
  both require explicit replacement. A changed underlying profile blocks batch
  application rather than overwriting an external edit.
- Preview captures only over its sample frame. It describes **saved** assignments
  for the profile being edited, including unavailable spells and implicit
  defaults. It does not cast, target, open menus, run macros or test server-side
  success. Blizzard conflicts and Self Cast can still affect live casting.

## Compatibility and state

The existing spell execution path, keyboard fallback rules, group-tile hover
wrappers, mouse pet-frame scope and single combat queue remain in use. The editor
does not bind keys globally. Buttons 1–5 and Alt/Ctrl/Shift combinations are
supported; mouse-wheel input scrolls. Keyboard inputs already assigned to a
non-action command retain the existing refusal behavior.

Target and Open unit menu compile to secure action types. Keyboard unit actions
use the existing hover-bound buttons with `unit = "mouseover"`. Custom macros
use `macrotext`; they have a 255-byte limit and are never truncated. Use
`[@mouseover]` explicitly when a macro command should address the hovered frame's
unit. Other commands retain normal macro semantics. Names and icons are display
metadata. The icon picker uses actual learned-spell icons and the game's generic
macro icon; it is not a global texture browser.

Saved rows stay at `GlassRaidFramesCharDB.profiles[role].bindings`. Existing
`{key|mouse, spell, pinned}` rows need no migration. New unit/macro rows add
`action = "target"|"togglemenu"|"macro"`, with `macrotext`, optional `name` and
`icon` for macros. Unknown fields survive copies/commits. No destructive cleanup
or automatic deduplication runs when opening the editor.

The catalog contains learned, active spellbook spells, grouped only when exact
rank IDs can be verified. Existing verified indicator families are reused;
other candidates require distinct localized rank subtexts that each resolve
back to the exact learned ID, in the same skill line with the same name/icon.
Rank order follows the verified family or spellbook order, never numeric ID.
Ambiguous entries remain separate. Spell changes invalidate the catalog. The
indicator rank API is unchanged.

Highest retains the established name-based cast behavior. Fixed ranks retain
their exact saved ID. A missing fixed-rank subtext cannot silently become a
highest-rank keyboard cast. Unavailable saved entries remain visible and saved;
the user must explicitly replace them. There is no speculative Healing/Utility
classification or unlearned-spell browser.

Combat stops recording and prevents save/delete/apply. Drafts and staged rows
remain in memory and resume after combat; active-role changes never move them
to another profile. Drafts are session-only, not persisted across logout/reload.

## Hosting in GlassUI

`GRF.ClickCastOptions.Open(parent)` returns the reusable editor content frame and
mounts it in the supplied parent. Without a parent it opens the movable,
resizable standalone shell. The same content and editor state are reused when
reparented; there is no GlassUI dependency, host SavedVariables or host chrome
inside the editor model.

The host supplies at least `MIN_WIDTH` × `MIN_HEIGHT` (900 × 600 UI units), or
scales its viewport accordingly. Content follows parent sizing. The standalone
shell fits the screen and adjusts for UI scale/display changes itself.

Before hiding or navigating away, call
`GRF.ClickCastOptions.RequestClose(function() ...host navigation... end)`.
The callback runs only after unsaved changes are saved or discarded, or when
there are none. Keep editing leaves it uncalled. A forced parent hide releases
capture and retains the draft, but cannot show a navigation confirmation; hosts
should use RequestClose. Opening/reparenting intentionally preserves current
editor state.

## In-game acceptance checklist

Offline tests do not establish secure execution, actual key propagation,
rendering or SavedVariables persistence in the client. The following checks
remain to be performed on Forever; they are not recorded as passed.

- Start with existing mouse/keyboard bindings, a pinned rank and an unavailable
  spell. Open and cancel edits; confirm all saved assignments remain intact.
- Open from the main page and `/grf clickcast`. Check the safe Settings close,
  dragging, resizing to 900 × 600, display changes and UI scales 0.64/0.8/1.0.
  Check long names, contrast, default rows, selection, disabled controls, both
  scrollbars and more than 14 bindings. Verify macro text and cursor scrolling.
- Test keys, mouse 1–5, and Alt/Ctrl/Shift combinations. The activation click,
  Save/Cancel clicks, search typing, macro typing and keys outside explicit
  capture must not create bindings or trigger gameplay actions while consumed.
  Hold a captured key, cancel with Escape, and record again.
- Exercise both creation workflows, spellbook dragging, cell shortcuts, rank
  choices, Browse, Cancel, deletion confirmation and all navigation guard choices.
- Test conflicts with saved and staged rows and repeated inputs in other roles.
  Change active roles while another role's draft is open. Confirm the layout and
  active bindings follow only the established role rules.
- Learn a higher rank: Highest should follow it; a fixed rank must remain fixed.
  Check rank lists on more than one class and on a localized client. Retain and
  clearly flag a spell/rank that becomes unavailable after a talent change.
- Quick Bind several spells, including modifier mouse clicks. Scroll/search
  between captures; Escape, discard, and apply. Confirm no staged entry casts
  before applying and no partial batch applies after a validation failure.
- Try spell, fixed rank, unit action, macro and unbound inputs on the preview.
  Confirm there is no spellcast, target change, real unit menu or macro effect.
- On real GRF frames, verify normal target/menu defaults, explicit target/menu
  mouse and keyboard actions, custom `[@mouseover]` macros, healing, resurrection
  and fixed-rank spells out of and in combat. Check the Self Cast warning against
  the actual behavior and retain the #49 hover-key regression checks.
- Verify mouse bindings on enabled pet frames, keyboard bindings only on member
  frames, and normal keyboard behavior elsewhere, including strangers in-world.
- Enter combat during a draft and during Quick Bind. Existing bindings must keep
  working; capture/save/apply must pause, with drafts intact after combat.
- Exit the client fully and log in again to verify saved roles, macros and pinned
  ranks. `/reload` alone is not a persistence test.

The UI and model tests execute the real handlers under the repository's strict
WoW stubs. The existing casting tests cover the secure reconciliation separately.
The API dump confirms method availability; FrameXML and recorded probes support
the implementation, but new interactions still need the checks above.
