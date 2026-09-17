# Testing & verification status

## Slash commands (debug/test)

- `/pi` — open/close the options window (opens on the Setup Guide tab)
- `/pi debug` — toggle session debug printing + dump state
- `/pi status` — dump state without toggling debug
- `/pi notify` — print the notify gates (spec, healer, in-raid, PI-ready,
  tracked-spell count, resolved target unit, whether a cell was found,
  `GlowActive`). First stop when the glow won't show — tells you which gate fails.
- `/pi watchself` — debug mode: drops the healer/raid gates and points detection
  at YOUR OWN cell/buffs, works solo. Add a spammable self-buff's spell ID as a
  Custom buff, then cast it on yourself to trigger. With no raid/party cell the
  glow shows on a box in the screen centre.
- `/pi testglow` — toggle a persistent preview of the current effect on the
  target's cell (or a box), bypassing all gates. Same as the Notifications "Test"
  button.
- `/pi welcome` — clear the first-run flag (so the Setup Guide auto-opens next
  `/reload`) and open it now.

## Verification status (as of v1.6.0)

CONFIRMED IN-GAME:
- Full notify pipeline on **Grid2**: AuraContainer detection + all three effects
  (PI Icon + countdown, Pulse Border, Flash Frame) + the countdown number.
- The sound registers (`AAddAuraSound`) and the assignment sharing/window (long
  shipped) work.

NOT YET VERIFIED (code has lookups in RaidFrames.lua; strata fix should help,
but untested — the frame-finding differs per addon):
- Blizzard default frames, Cell, VuhDo, EllesmereUI, DandersFrames.
- To test one: use its raid frames, `/pi watchself`, add a self-buff as a Custom
  buff, cast it, and check the highlight lands on your cell. If not, `/pi notify`
  shows whether the cell was found (frame-finding) vs. GlowActive false (a gate).

## How to test the notify glow without a real cooldown

1. `/reload`, `/pi debug`, `/pi watchself`
2. Buffs to track → Custom buffs → add a spammable self-buff's *buff (aura)* ID
   (e.g. Renew 139, Power Word: Fortitude 21562)
3. `/pi notify` should read `GlowActive=yes`
4. Cast the buff on yourself → the highlight should appear on your cell.

## In-client risk areas (things static checks can't catch)
- `SetDurationText` binding on the forbidden aura button (the countdown number) —
  pcall-guarded; if it fails you get icon+flash with no number, no breakage.
- Per-addon frame discovery (see above).
- Effect visuals across different cell sizes/shapes.
