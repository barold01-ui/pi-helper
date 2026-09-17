# Cooldown Alerts feature — design & 12.1 constraints

The feature: for a **healer priest** (Discipline 256 / Holy 257) in a **raid**,
when your assigned PI target uses a tracked offensive cooldown, highlight their
raid-frame cell and play a sound — so you know when to cast Power Infusion.
Shadow keeps the plain assign-and-PI flow (no alerts). Raid only for now;
dungeon mode was deferred.

## The 12.1 "secret value" wall (this shapes everything)

Verified against warcraft.wiki `Patch_12.1.0/API_changes` AND confirmed
in-client. In combat / M+ / encounters, another player's aura/cast data is
**secret** — reading it errors:
- `UNIT_AURA` delivers a fully secret payload; index/slot/instanceID aura APIs
  error.
- The spellID/name aura APIs (`C_UnitAuras.GetAuraDataBySpellID`) "still
  callable" BUT "non-secret spells still return non-secrets" — i.e. other
  players' auras in combat still come back secret/nil. **Does not help us.**
- **There is NO event/callback** telling addon Lua that a filtered aura
  appeared. `AuraContainer` (the sanctioned mechanism) only shows a button
  visually; `initializeFrame` fires once at button creation, not per aura.
- The `AuraContainer`/`AuraButton` are **forbidden frames** — confirmed by
  `/pi debug` showing `visibility UNREADABLE (combat=false)` even OUT of combat.

### Consequences (do not re-attempt these)
- **Detection**: the only safe way is Blizzard's `AuraContainer` filtered to our
  spell IDs — the engine shows an `AuraButton` when the buff is present; we
  never read the aura. This is `Notify.lua` + `Glow.lua`.
- **No from-cooldown-start timer.** A fixed "glow for 10s from when they pressed
  it" is IMPOSSIBLE — we can't observe the appearance moment (no callback,
  visibility unreadable). An earlier visibility-polling detector was built and
  DELETED after `UNREADABLE` proved it can't work. Do not rebuild it.
- **Design is glow-WHILE-PRESENT**: the glow rides the aura button's engine-driven
  show/hide, so it lasts as long as the target's cooldown buff.
- **Countdown number** (PI Icon only): the AuraButton's `SetDurationText` lets the
  ENGINE write remaining seconds into our fontstring — the engine may DISPLAY the
  secret-derived value, our Lua just never READS it. A `NumericRuleFormatter`
  (`%.0f`) strips the "s" suffix. This is how the user judges "is their cooldown
  about to expire?" — the addon can't branch on the number (that read is secret),
  but the user can see it.
- **Sound**: `C_UnitAuras.AddAuraSound(spellID, unitToken)` — the CLIENT plays it
  when the buff lands. Combat-locked to add (registered out of combat, retried on
  `PLAYER_REGEN_ENABLED`); `RemoveAuraSound` is allowed in combat. The sound can't
  be perfectly PI-gated (can't re-add mid-fight), so we register only while PI is
  ready and remove on our PI cast; it can't re-arm until combat ends.

## PI-ready gate (`PIReady.lua`)

Alerts only show while our own PI is off cooldown. We can't read PI's remaining
CD in combat (secret), but: our OWN cast is readable (`RegisterUnitEvent
"UNIT_SPELLCAST_SUCCEEDED" "player"`, spell id 10060), and `GetSpellCooldown().isActive`
is never secret. On our PI cast we start a 120s lock; after 100s we poll
`isActive` to release early if a reset (M+ CDR) ended it; we clear the lock on
raid `ENCOUNTER_END` (kill/wipe) and `CHALLENGE_MODE_START`. Casting PI disables
the containers (via the gate) so the glow/sound hide.

## The strata fix (critical for third-party raid frames)

Symptom on Grid2 (frame strata MEDIUM): Pulse Border worked but PI Icon and Flash
Frame were hidden — the cell's own health/status textures drew over our glow;
only the edge border peeked around them. **Fix** (`RaiseAboveCell` in Glow.lua):
lift the glow holder ONE STRATA above the cell (reads the cell's strata, +1) plus
a high frame level. Strata dominates frame level, so the whole glow renders on
top regardless of the frame addon's internal levels. This is general, not
Grid2-specific.

## Two independent glow paths
1. **Real notify**: `AuraContainer` + a holder that is a child of the aura button;
   the engine drives its visibility (glow while buff present). `Notify.lua`
   `RefreshGlow` → `DecorateGlowButton`.
2. **Test preview** (`/pi testglow` and the Notifications "Test" toggle): a
   standalone persistent glow on the target cell or an on-screen box, independent
   of the aura engine. `StartCellGlow`/`StopCellGlow`. While previewing,
   `RefreshGlow` early-returns so the two don't fight.
