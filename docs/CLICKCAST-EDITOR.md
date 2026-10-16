# Click-casting editor (#50)

Open **Options > AddOns > Glass Raid Frames > Click-casting**, or use
`/grf clickcast`. The main page button opens a dedicated glass window; the old
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
  both require explicit replacement, as do implicit plain-click target/menu
  defaults. A changed underlying profile blocks batch
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
highest-rank keyboard cast: a bare name is accepted only if the client resolves
it back to that exact saved ID, supporting genuinely unranked pinned spells.
Unavailable saved entries remain visible and saved;
the user must explicitly replace them. There is no speculative Healing/Utility
classification or unlearned-spell browser.

Combat stops recording and prevents save/delete/apply. Drafts and staged rows
remain in memory and resume after combat; active-role changes never move them
to another profile. Drafts are session-only, not persisted across logout/reload.
The editor's separate keyboard listener is hidden during combat, including when
first opened there. Use the close button during combat; editor Escape handling
resumes afterward. No restricted keyboard-setting calls run during combat.
Saved installation failures and fallback notes appear in the table and Warnings,
including when the selected binding is being edited as a draft copy.

The click-casting-only hybrid material separates the moderately smoked shell
from two continuous, darker reading panes extending through the preview/footer.
The shell adds a static feathered pearl reflection and directional silver/cool
rim using LibGlass's existing textures and gradient conventions. Controls have
quieter rims and wash; selected/focused/hovered/recording states keep accents.
Text/icon opacity and the layout are unchanged. No shared instance settings,
library defaults, other addon surfaces, captured scenery or continuous effects
are involved. Pane dimensions follow the window, never the filtered rows.

For other addons adapting this material, the shared recipe and layering values
are in `../References/LIBGLASS-WINDOW-STYLING.md` (relative to the repository root).
It distinguishes the outer shell from reading panels and documents the PetStable
adaptation findings without changing shared-library defaults.

### Temporary developer material comparison

With the editor open, run either command (no reload):

```text
/run GlassRaidFrames.ClickCastOptions.SetMaterialPreview("baseline")
/run GlassRaidFrames.ClickCastOptions.SetMaterialPreview("hybrid")
/run GlassRaidFrames.ClickCastOptions.SetMaterialPreview("reflective")
/run GlassRaidFrames.ClickCastOptions.SetMaterialPreview("altstable")
```

`hybrid` restores the smoked-glass appearance before its final reflection tweak.
`reflective` is the default and restores the accepted treatment with that upper-rim/reflection tweak; fill,
opacity, panes, controls and bottom edge match `hybrid`. Use these two modes for
that comparison. `baseline` retains the older pre-hybrid treatment.
`altstable` remains an opt-in experiment: a clean, clear shell with tint
RGBA (0.13, 0.16, 0.22, 0.24), wash 0.18, rim alpha 1 and no dark shell backing.
Its masked title band uses AltStable's white 0.16-to-0.05 gradient, fitted to this
editor's existing title area. Both reading panes keep their charcoal color and
become opaque, following AltStable's separation of glass chrome and data surface.
Controls are unchanged. Compare `altstable` against `reflective` without reloading;
all prior modes remain available. No AltStable dependency or shared-library edit.
The switch only repaints decorative regions, preserving draft, role,
selection, text focus, capture state and scroll positions. It is session-only,
not saved, and deliberately absent from product controls and `/grf help`.
Retain these developer comparison modes for clear-theme follow-up #52; the
accepted default remains `reflective`.

Compare at the same window size and UI scale over bright terrain, dark interiors,
and moving detailed scenery. Check secondary text, spell names/icons, disabled
buttons, hover/focus/selected states, recording and the preview/footer. Resize
and scroll both panes, filter rows, type a macro and record modified inputs.
If dense content loses readability, strengthen its pane backing first rather
than darkening the entire shell. Offline checks verify state/isolation and API
availability; they do not establish in-game readability or the rendered result.

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
The owner accepted merging the unreleased addon on 2026-10-16 with these checks
as follow-up validation during normal in-game use, rather than merge blockers.

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
  Also open the editor for the first time in combat, press/release gameplay keys,
  close with the mouse, and reopen. No blocked actions or swallowed gameplay keys;
  keyboard capture must resume after combat. Check pinned unranked spells as well
  as ranked spells with temporarily unavailable rank text.
- Exit the client fully and log in again to verify saved roles, macros and pinned
  ranks. `/reload` alone is not a persistence test.

The UI and model tests execute the real handlers under the repository's strict
WoW stubs. The existing casting tests cover the secure reconciliation separately.
The API dump confirms method availability; FrameXML and recorded probes support
the implementation, but new interactions still need the checks above.
