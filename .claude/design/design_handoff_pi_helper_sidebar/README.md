# Handoff: Power Infusion Assignment Helper — Sidebar Sections (option 2c)

## Overview
Redesign of the options window for a World of Warcraft addon, **Power Infusion Assignment Helper**. The current window is a single scrolling column: two tabs (Configuration / FAQ), a mode dropdown, a macro-name field, a large read-only macro example with a "Select All" button, five checkboxes, and a scale slider at the bottom. It works but reads as one undifferentiated list, and there is nowhere obvious to put new options.

This design keeps exactly the same controls and splits them across a **left navigation rail** — Setup, Behavior, Display, FAQ — so only one short pane shows at a time. The scale control moves out of the panes into a **persistent footer bar** visible in every section, since it applies to the addon as a whole.

**No functionality is added.** The mode dropdown holds only the single option the current addon has; there is no target-selection mode, no macro generation, and no macro-name validation. The FAQ pane is a placeholder for the addon's existing FAQ content.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype showing intended look and behavior, not production code to copy directly. Recreate the design in the target codebase using its own patterns.

The real implementation is a **WoW addon in Lua against the Blizzard UI API** (frames, `Button`, `EditBox`, `CheckButton`, `Slider`, `UIDropDownMenu`, `FontString`, or a config library such as AceGUI/AceConfig). Treat the HTML as a visual and behavioral spec: layout, grouping, states, spacing and copy transfer; the DOM and CSS do not. If the addon already uses a config library, express the rail as that library's tab/tree group rather than hand-rolling frames.

## Fidelity
**High-fidelity.** Colors, type sizes, spacing and row heights are final intent. The palette is deliberately shared with the same author's Scale Frames addon (dark gold-on-brown, square corners) so the two addons look related. The prototype's checkbox sub-descriptions are **draft copy** — replace them with the addon author's own wording.

## Screens / Views

### Options window (single view, four sections)
**Purpose:** configure how the addon reads your PI target and how its assignment window behaves, without a wall of controls.

**Frame**
- Width **720px**; height driven by content, content area `min-height: 400px`. Border `1px solid #4a3a22`, background `#1b1611`, radius 0. Prototype adds `0 0 0 1px #0b0906, 0 18px 40px rgba(0,0,0,0.5)` — optional in-game.
- Three stacked regions: title bar → body (rail + pane) → scale footer.

**1. Title bar**
- Padding `12px 16px`, background `#221b13`, bottom border `1px solid #3a2d1b`.
- Left: "Power Infusion Assignment Helper" — Cinzel 17px `#f2c66d` (stand-in for the game's Friz Quadrata / `GameFontNormalLarge`).
- Right: close button 22×22, background `#4a1a13`, border `1px solid #7c3b23`, glyph `✕` `#e9c69a`, hover background `#5e2118`. In-game: keep the existing red X texture button.

**2. Navigation rail** (left, width **172px**)
- Background `#17120d`, right border `1px solid #3a2d1b`, vertical padding `8px 0`.
- One button per section, `padding: 10px 14px`, font 15px, label left / badge right.
  - Selected: background `#241d14`, left border `3px solid #d9a13b`, label `#f2c66d`.
  - Unselected: transparent background, left border `3px solid transparent` (reserve the width so labels don't shift), label `#c8bba6`, hover background `#221b13`.
  - Badge: 12px `#6e6455`. Setup shows the current macro name; Behavior shows `n/3`; Display shows `n/2`; FAQ has none. Badges are derived state, not new settings.
- Order: **Setup, Behavior, Display, FAQ**. Setup is selected on open.

**3. Content pane** (right, flexible width)
- Padding `18px 20px`, `gap: 16px`, single column.

**Setup**
- Micro-label "MODE" — Barlow 600, 11px, `letter-spacing: 0.16em`, uppercase, `#b08a3d`.
- Dropdown, full width: background `#100d09`, border `1px solid #6d5320`, text `#f0e2c4` 15px, padding `8px 10px`. Single item: "My PI target is set in a macro".
- Row: label "Macro name" 15px `#c8bba6` + text input width 150px (background `#100d09`, border `1px solid #453519`, text `#f0e2c4` 15px, padding `7px 10px`, focus border `#c9922f`). Current value `P`.
- Caption "Example macro, if you need to create one" — 14px `#8b7f6d`.
- Read-only macro block: background `#0c0a07`, border `1px solid #3d3018`, monospace 12.5px, line-height 1.55, text `#8fcf7a` (the green of the current panel), wraps on long tokens. Content is the addon's existing example macro verbatim:
  `/use [@mouseover,nodead,help]Power Infusion;[@YOUR_PI_TARGET_HERE,exists,nodead]Power Infusion;[@player]Power Infusion`
- Button "Select all (Ctrl+C to copy)" — same label as today — background `#4a3a17`, border `1px solid #7a5c22`, text `#f2c66d` 14px, padding `7px 14px`, hover background `#5c4820`. Left-aligned, not full width (the current panel's full-width red button is louder than the action deserves).

**Behavior** — three checkbox rows, in this order:
1. Hide PI assignments in combat *(on by default)*
2. Show PI assignments even if I'm not a priest
3. Enable whispers (guild only)

**Display** — two checkbox rows:
1. Test mode (show fake data)
2. Lock frame *(on by default)*

Checkbox row spec (both panes): full-width button, `padding: 11px 0`, `gap: 12px`, bottom border `1px solid #221b13`, top-aligned. Box 16×16 with `margin-top: 2px`; checked = background `#d9a13b`, border `1px solid #7a5c22`, glyph `✔` in `#0f0d0a`; unchecked = background `#100d09`, border `1px solid #453519`, no glyph. Label 15px — `#f2c66d` when checked, `#c8bba6` when not — with a 13px `#7d7362` description on the line below. The whole row is the hit target.

The current panel's info tooltip icon next to "Enable whispers" is not drawn in the prototype; keep it, or fold its text into that row's description.

**FAQ** — the addon's existing FAQ content, unchanged. The prototype shows a centered placeholder line; do not ship the placeholder.

**4. Scale footer** (persistent, all sections)
- Padding `12px 20px`, background `#221b13`, top border `1px solid #3a2d1b`, `gap: 14px`.
- Label "Scale" 15px `#c8bba6`.
- Track: flex-filling, 20px hit area. 4px unfilled bar `#2c241a` with `1px solid #191309`; 4px fill `#d9a13b` from left to value; handle 9×18px `#f2c66d`, border `1px solid #12100b`, centered on the value (`margin-left: -4px`). The current panel's "Low / High" end labels are dropped — the numeric readout carries that information.
- Stepper: bordered group (border `1px solid #453519`, background `#100d09`) — `−` 26×26 (background `#2a2118`, right divider `1px solid #453519`, 15px `#c9b795`, hover `#3a2d1b`), value 52px wide centered 15px tabular numerals `#f2c66d`, `+` mirroring `−`.
- Range **0.5–2.0**, step **0.05**, current value 1.05. Matches the current slider's range; confirm against the addon's own bounds.

## Interactions & Behavior
- **Rail selection** switches the pane; only one section renders at a time. Setup on open. Selection is view state, not persisted (persisting the last section is fine if trivial).
- **Checkboxes** toggle on click anywhere in the row, write to saved variables immediately, and apply live. Checked state drives the box fill and the label color.
- **Macro name** is a plain text field; changes save on edit. No validation, no lookup.
- **Select all / copy** puts the example macro on the clipboard and the button label becomes "Copied" for ~1.6s, then reverts. In-game, keep today's behavior instead: focus the edit box and select its text so Ctrl+C works.
- **Scale track drag:** pointer-down jumps to that position and starts a drag; move updates continuously; up ends it. Tracking is on the window, so the pointer may leave the track vertically mid-drag. Position maps linearly across the range.
- **Scale stepper:** `−`/`+` move one step and snap to the step grid; both clamp at 0.5 and 2.0. Every value set by drag or stepper is rounded to the nearest step multiple, then clamped.
- **Hover states** are the only transient styling: rail rows, small buttons, copy button. No expand/collapse animation anywhere.
- **Responsive:** none — fixed-width frame.

## State Management
- `section: 'setup' | 'behavior' | 'display' | 'faq'` — view state, initial `'setup'`.
- `macroName: string` — saved variable, current default `'P'`.
- `toggles: { hideCombat, showNonPriest, whispers, testMode, lockFrame }` — booleans, saved variables. Defaults in the prototype: `hideCombat` and `lockFrame` on, the rest off; match the addon's real defaults.
- `scale: number` — saved variable, 0.5–2.0, prototype value 1.05. Applies to the addon's assignment frame (`frame:SetScale`).
- `copied: boolean` — transient UI feedback only, ~1.6s.
- Derived (compute, don't store): rail badges, fill percentage `((v − 0.5) / 1.5) × 100`, formatted value (2 decimals).
- The mode dropdown has one option and no state to manage.

## Design Tokens
Colors
- Surfaces: frame `#1b1611`; rail / inset panel `#17120d`; title bar & footer `#221b13`; selected rail row `#241d14`; hover `#221b13`; code block `#0c0a07`; page background `#0f0d0a`
- Borders: frame `#4a3a22`; region divider `#3a2d1b`; row divider `#221b13`; control `#453519`; code block `#3d3018`; dropdown `#6d5320`; hover / focus `#7a5c22` and `#c9922f`
- Controls: button face `#2a2118`; button hover `#3a2d1b`; inset field `#100d09`; primary button `#4a3a17` on `#7a5c22`, hover `#5c4820`; close button `#4a1a13` on `#7c3b23`, hover `#5e2118`
- Track: unfilled `#2c241a`; fill `#d9a13b`; handle `#f2c66d`
- Text: title & active `#f2c66d`; body `#c8bba6`; field text `#f0e2c4`; button glyph `#c9b795`; micro-label `#b08a3d`; description `#7d7362`; muted `#6e6455`; caption `#8b7f6d`; macro code `#8fcf7a`

Spacing — 2 / 8 / 10 / 12 / 14 / 16 / 18 / 20px. Frame width 720px; rail width 172px; content min-height 400px. Row heights: rail row 40px, checkbox row ~44px, footer 50px.

Typography
- Display: Cinzel 500, 17px — window title. Stand-in for Friz Quadrata; in-game use `GameFontNormalLarge`.
- UI: Barlow Semi Condensed 400/500 — labels and rail 15px, description 13px, caption 14px, badge 12px, scale value 15px tabular.
- Micro-label: Barlow 600, 11px, `letter-spacing: 0.16em`, uppercase.
- Mono: JetBrains Mono 400, 12.5px — macro block. In-game: the default fixed-width game font.

Borders/radius/shadow — radius 0 everywhere; all borders 1px; frame shadow `0 0 0 1px #0b0906, 0 18px 40px rgba(0,0,0,0.5)`.

## Assets
None. Glyphs are text characters: `✔`, `✕`, `−`, `+`. Substitute the addon's existing check and close textures. Cinzel, Barlow Semi Condensed and JetBrains Mono load from Google Fonts in the prototype and are stand-ins for the game fonts.

## Files
- `PI Helper Sidebar.dc.html` — the design, standalone and interactive (rail, checkboxes, scale drag/step, copy). Open in a browser. Values reset on reload; nothing persists.
- `support.js` — runtime required by the HTML. Keep it beside the file; not part of the design.
- Source of truth in the design project: `Power Infusion Helper Options.dc.html`, option `2c`. That file also holds two rejected alternatives — `2a` labelled sections in one column, `2b` a macro card above switch rows — useful for context.

`accent` exists as a prototype prop (gold `#d9a13b` default, plus blue/green/purple) because alternate color schemes are still being explored. Ship the gold values above unless told otherwise, but keep the accent in one place so a scheme swap stays cheap.
