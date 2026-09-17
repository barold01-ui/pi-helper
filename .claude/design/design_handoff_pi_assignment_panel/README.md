# Handoff: Power Infusion Assignment Panel — visual redesign (option 2A)

## Overview
This is a visual redesign of the assignment list shown by a World of Warcraft Power Infusion
assignment-helper addon. The panel lists every Priest in the group and the player each one is
assigned to infuse. Nothing about the addon's logic, assignment algorithm, slash commands, or
saved variables changes — this is a presentation-layer change to the frame that currently renders
four lines of `PriestName -> TargetName` text.

The approved direction is **option 2A, "Leader lines"**: a two-column list where priest names sit
on the left, target names are right-aligned on a single axis, and a dotted leader line connects
each pair. The player's own row is marked with a gold tick, and an unassigned target renders in
red so it is the loudest thing in the frame.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes that communicate
intended look, spacing, and colour, not production code to copy. The implementation target here is
a WoW addon, so the task is to **recreate the design using the game's UI API** (Lua + `Frame`/
`FontString`/`Texture`, or an XML template) inside the addon's existing structure and conventions.
Reuse whatever the addon already has: its frame-creation helpers, its font handling, its
`LibSharedMedia` registration if present, its options/saved-variables layer. Do not introduce a new
UI library for this.

The HTML mocks are drawn at **1.5× game scale over a screenshot of the player's UI** so relative
sizes read correctly on screen. Every measurement in the spec below has already been converted back
to **1× game pixels** — use the numbers in this README, not the numbers in the HTML.

## Fidelity
**High fidelity.** Colours, type sizes, spacing, and states are final. Recreate them as closely as
the WoW UI API allows. Two known API limitations and their intended resolutions:

1. **Dotted leader line.** There is no dotted-border primitive. Preferred: a 1px-tall `Texture`
   with a 2×1 px dot texture, `SetHorizTile(true)`, tinted per row. Acceptable fallback: a solid 1px
   texture at 40% of the row's leader alpha (visually very close at this size, and cheaper).
2. **Font.** The mock uses Barlow Semi Condensed SemiBold. If the addon already ships or registers a
   condensed face (Expressway, PT Sans Narrow, Oswald), use it. Otherwise bundle
   Barlow Semi Condensed SemiBold as a TTF in the addon and register it with `LibSharedMedia-3.0`.
   Last-resort fallback is `GameFontNormal`'s Friz Quadrata at the same sizes — the layout still
   works, it just reads wider.

## Screens / Views

### View: Assignment panel (the only view)
- **Purpose:** at a glance, tell the player who they are infusing, and who every other Priest is
  infusing. Read during combat, in peripheral vision.
- **Frame:** single container frame, movable/anchored exactly as the current panel is. Do not change
  its default anchor, drag behaviour, or scale handling.
- **Size:** width **264px** fixed. Height is content-driven:
  `7 (top pad) + 13 (header line) + 5 + 1 (divider) + 6 + rows + 8 (bottom pad)`,
  where each row is 14px of text and rows are separated by a 4px gap.
  For the 4-priest case in the mock this is **≈ 122px**.
- **Background:** flat `rgba(9, 8, 13, 0.84)` → `SetColorTexture(0.035, 0.031, 0.051, 0.84)`.
  No gradient. The current gold/parchment border art is removed.
- **Border:** 1px inset edge, `rgba(255, 255, 255, 0.13)`. Four 1px textures, or a `BackdropTemplate`
  with `edgeSize = 1` and that edge colour.
- **Highlight:** 1px inset line along the top edge only, `rgba(255, 255, 255, 0.07)` (optional; it is
  the "inset 0 1px 0" in the mock and reads as a very faint lip).
- **Corner radius:** the mock uses 3px. WoW cannot round a `SetColorTexture` fill; square corners are
  fine and are the expected result.
- **Padding:** 9px left and right, 7px top, 8px bottom.

#### Component: header
- Text: `POWER INFUSION` (uppercase, literal).
- Font: condensed face, **10px**, semibold, letter-spacing ≈ **1.5px** (WoW has no tracking API —
  if the addon has no letter-spacing helper, render the string with single spaces between letters
  only if it stays on one line; otherwise ship it untracked).
- Colour: `rgba(255, 255, 255, 0.42)` → `SetTextColor(1, 1, 1, 0.42)`.
- Anchored top-left inside the padding box.
- 5px below the header baseline block sits a **1px divider**, full content width,
  `rgba(255, 255, 255, 0.09)`. 6px of space between the divider and the first row.

#### Component: assignment row (repeated per Priest)
Grid per row, all elements vertically centred on the text baseline:

| Element | Spec |
| --- | --- |
| Own-row tick | 2px wide × 10px tall texture, colour `#D8B46A`, at the left padding edge. Only on the player's own row. |
| Priest name | condensed face, **14px**, semibold. Own row `#FFFFFF` at full alpha; other rows `rgba(255,255,255,0.86)`. Left edge sits 5px right of the tick; rows without a tick are indented **7px** so all names align. |
| Leader | 1px line filling the space between name and target, with 5px clear space on each side, sitting ~3px below the text baseline. Colour: see states. |
| Target name | condensed face, **14px**, semibold, right-aligned to the right padding edge. Colour = target's class colour. |

- Row gap: **4px**. Row text shadow: offset (1, -1), black, alpha 1.0
  (`SetShadowOffset(1, -1)`, `SetShadowColor(0, 0, 0, 1)`).
- Row order is unchanged from the current addon (player first, then the existing sort).

#### Colours per row state
- **Assigned:** target name = `RAID_CLASS_COLORS[class].colorStr` for the target's class.
  Leader = `rgba(255, 255, 255, 0.16)`.
  Reference values from the mock: Warrior `#C69B6D`, Rogue `#FFF569`, Priest `#FFFFFF`.
- **Unassigned (`(none)`):** target text `#FF7B72`; leader `rgba(255, 123, 114, 0.40)` — i.e. the
  leader takes the target colour at 40% alpha whenever the target is unassigned. Keep the literal
  string `(none)`.
- **Player's own row:** gold tick `#D8B46A` and full-white name, in addition to whatever the target
  state dictates. The tick is the only own-row treatment; no background band, no bold weight change.

#### Exact copy in the mock
```
POWER INFUSION
Anamemana    (none)
Priest 4     Tankwarrior
Priest 2     Roguestabber
Priest 3     Roguestabber
```
All names are live data. `POWER INFUSION` and `(none)` are the only literals.

## Interactions & Behavior
Unchanged from the current addon. For completeness, the panel is expected to:
- Rebuild its rows on group/roster change and on any assignment change the addon already listens for
  (`GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`, plus the addon's internal assignment callback).
- Recolour in place rather than tear down and rebuild when only a target changes: keep row frames in
  a pool, `:Hide()` the surplus.
- Keep existing drag-to-move, click-through, and `/pi` configuration behaviour untouched.
- No hover states, no click targets, no animation. The panel is read-only display.
- If the addon supports hiding out of combat / when solo, that behaviour is unchanged.

## State Management
No new state. Rendering inputs per row:
- `priestName` (string), `priestIsPlayer` (boolean)
- `targetName` (string or nil → render `(none)`)
- `targetClass` (class token or nil → used for the class colour)

Row count = number of Priests known to the addon. Widen the panel only if the addon already supports
a user width setting; otherwise names truncate as they do today.

## Design Tokens
```
-- surfaces
bg              rgba(9, 8, 13, 0.84)      0.035 0.031 0.051 a=0.84
border          rgba(255,255,255,0.13)
top-highlight   rgba(255,255,255,0.07)
divider         rgba(255,255,255,0.09)

-- text
header          rgba(255,255,255,0.42)    10px semibold, +1.5px tracking, uppercase
name-self       #FFFFFF                   14px semibold
name-other      rgba(255,255,255,0.86)    14px semibold
target          class colour               14px semibold
target-none     #FF7B72                   14px semibold
accent-self     #D8B46A                   2×10px tick
leader          rgba(255,255,255,0.16)    1px
leader-none     rgba(255,123,114,0.40)    1px

-- spacing (px, game scale)
pad             9 horizontal / 7 top / 8 bottom
header-gap      5 above divider, 6 below
row-gap         4
self-indent     tick 2 + 5 gap; other rows indent 7
leader-inset    5 each side
text-shadow     offset (1, -1), #000 alpha 1
```

## Assets
- No new art. The redesign removes the existing gold/parchment border texture; nothing replaces it.
- Optional font file: Barlow Semi Condensed SemiBold (SIL Open Font License) if the addon has no
  condensed face already.
- `uploads/pasted-1786861125523-0.png` — screenshot of the **current** panel, for before/after.
- `uploads/pasted-1786861084242-0.png` — full-UI screenshot, used as the mock backdrop only.

## Files
- `PI Assignment Panel.dc.html` — the design document. It contains two rounds of exploration; the
  approved design is the section labelled **2A "Leader lines"** (anchor `#2a`, the first option in
  the top section). Everything else in the file is context for how the direction was reached and
  should not be implemented.
- Open it in a browser; the page pans and zooms.
