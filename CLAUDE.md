# PowerInfusionAssignments

WoW addon (retail, `## Interface: 120000, 120007, 120100`) for priests. It has
**two features**:

1. **PI assignment coordination** — each priest's addon works out who *they* are
   PIing, broadcasts it to the other priests, and everyone sees a movable list of
   `Priest -> Target` lines plus warnings (two priests on the same person, PI on a
   tank/healer, target in another zone).
2. **Cooldown alerts** (added 1.6.0) — for a healer priest, highlights the PI
   target's raid-frame cell when they use a tracked cooldown, so you know when to
   press Power Infusion. Visual only as of 2.0.0 — see the Sounds.lua note below.

No build step. Optional dep on LibSharedMedia. Saved variable
`PowerInfusionAssignmentsDB` (account-wide). Published to CurseForge from GitHub
(`barold01-ui/pi-helper`) via `.pkgmeta`.

## Read the `.claude/` docs first

Detailed, current context lives in `.claude/`:
- **`.claude/ARCHITECTURE.md`** — module layout, the shared `PI` namespace,
  saved variables, how to validate edits.
- **`.claude/COOLDOWN-ALERTS.md`** — the alerts feature and the **12.1
  secret-value constraints** that shape it. Read before touching
  Notify/Glow/PIReady — it records what is impossible and must not be
  re-attempted (e.g. a from-cooldown-start timer).
- **`.claude/CONVENTIONS.md`** — golden rules (PIHelper is reference-only, the
  secret-value rule, retail API gotchas, the strata fix, versioning).
- **`.claude/TESTING.md`** — the `/pi` debug/test commands and what is / isn't
  verified in-game.

This file is the higher-level guide plus the deep domain knowledge of the
**assignment/comms** system, which the `.claude/` docs don't re-cover.

## Structure (was single-file until 1.6.0; now modular)

Files share the private addon table via `local _, PI = ...`;
`PowerInfusionAssignments.lua` loads first. See `.claude/ARCHITECTURE.md` for the
per-file table. Everything is still flat and procedural — methods on one `PI`
table, no classes/metatables — just split across files along clear seams.

## Code style

- **Flat and procedural.** Methods on the `PI` table. Prefer the obvious
  repetitive version over a clever abstraction.
- **Tables are reused, not reallocated.** `reuseErrorLines`, `reusePriests`,
  `reuseRows` etc. are file-locals wiped with `wipe()` before each use, because
  the display path runs on a 3-second ticker. Follow that in any new hot path.
- Expensive lookups are cached and invalidated on the event that changes them
  (`classColorCache` on `GROUP_ROSTER_UPDATE`; the macro parse cache only when the
  body changes; `spellMapCache` in Cooldowns).
- Comments explain *why*. User-facing strings are inline English; no localisation.
- **12.1 secret values**: the engine can DISPLAY secret-derived data; your Lua can
  never READ it to act on it. Guard reads of auras/casts/unit tokens/sizes in
  combat with `pcall` + `issecretvalue`. See `.claude/COOLDOWN-ALERTS.md`.

## Assignment system (the deep domain knowledge)

### The ticker is the engine
`StartScanTicker`/`StopScanTicker` (core) own one `C_Timer.NewTicker(3, ...)`.
Each tick, out of combat: `RefreshZones` -> `CleanupStaleAssignments` ->
`UpdateAssignmentFrameVisibility` -> (priests) scan own target ->
`BroadcastAssignment`. `UpdateTickerState` is the single place that decides
whether the ticker exists (priest or `showForNonPriest`, in a raid, not in
combat) — call it, not Start/Stop directly.

### Names are always realm-qualified (Roster.lua)
Every stored name — DB keys, targets, cache keys — is `Name-Realm`. Short names
are ambiguous across connected realms and mixing forms dropped cross-realm
priests out of the group/role/colour lookups. `PI:Qualify`/`GetUnitName`/
`ResolveName` qualify; `PI:ShortName` strips the realm **for display only**.
Anything compared or stored must stay qualified. Identity is resolved once via
`PI:SetIdentity` (called from `InitDB`).

### One roster pass feeds every lookup (Roster.lua)
`PI:RefreshRoster()` wipes and rebuilds `groupMembers`, `memberZones`,
`memberRoles`, `memberInGuild`, `classColorCache`, `shortToFull`, `rosterNames`
in one loop, and is the only writer. The queries are then O(1) reads. Full
rebuild runs only on roster/zone *events*; the ticker calls the cheaper
`RefreshZones` (reuses `rosterNames`, touches only `GetRaidRosterInfo`), with a
size-mismatch fallback to a full rebuild. Display updates coalesce through
`PI:RequestFrameUpdate()` (one rebuild next frame).

### Two ways to know your own PI target (Macro.lua)
`DB.piMode`: **Mode 1 (macro)** — `ScanMacroAndSave` + `ParseMacroForTarget`
pull the first non-keyword `@Name`/`target=Name` token (`isIgnoredToken` is the
blocklist; capture pattern `[^%],;%[%]%s]+` allows Unicode names). **Mode 2
(mouseover)** — the global `PI_SetPITarget()` stores `UnitName("mouseover")`.
Both end at `PI:SetMyTarget` (whispers on real change if `enableWhispers`, writes
`DB.assignments[myName]`, and re-points the notify glow).

### Communication (Comms.lua) — keep wire compatibility
Prefix `PIAssign`, payload `"Player:Target"` on `RAID`. `BroadcastAssignment`
dedupes on `lastBroadcastedTarget` unless `force`. `OnAddonMessage` keys off the
server-reported `sender`, not the payload name (anti-spoof). `ToWire`/`FromWire`
preserve 1.4.x behaviour (realm stripped when it matches ours, put back using the
*sender's* realm); `RealmOf` splits on the *first* hyphen (realms like
"Azjol-Nerub"). **Don't change the payload shape** — it strands un-updated
priests.

### Display frame (AssignmentFrame.lua)
`PIAssignmentFrame` from the panel handoff in
`.claude/design/design_handoff_pi_assignment_panel/`. `PANEL`=metrics,
`PC`=palette (1× game pixels; `SetScale` is the only conversion). Pooled rows
(`f.rows`, only hidden). `UpdateAssignmentFrame` diffs row descriptors against
`lastRows` field-by-field; `ApplyPanelRows`/`LayoutAssignmentFrame` run only on a
change. Warnings (`CheckForDuplicateTargets`, `CheckForRoleWarnings`,
`CheckTargetProblems`) gate on `instanceType == "raid"`. Width is ~236px, grows
to fit long pairs; test mode tags the header red.
`UpdateAssignmentFrameVisibility` owns show/hide separately.

### `!pi` chat command (Comms.lua)
Every priest hears it, so `ReportAssignmentsToChat` elects one responder (sort
by name, first sends). Three anti-throttle guards must survive any rewrite: the
election, `REPORT_COOLDOWN`, and the 240-char message packing.

### Test mode (core)
`SetTestMode` swaps `DB.assignments` for `TEST_ASSIGNMENTS` (deliberate duplicate
+ fake tank), stashes real ones on `PI.realAssignments`, injects
`TEST_CLASS_COLORS`, and scans your real macro so your own row shows. Force-reset
to `false` in `InitDB`. Bypasses zone filtering, cleanup, visibility — check
`DB.testMode` before anything that deletes/hides rows.

## Cooldown alerts (Cooldowns/PIReady/RaidFrames/Glow/Notify)

Healer-only (Disc 256 / Holy 257), raid-only. Detection uses a Blizzard
`AuraContainer` filtered to tracked spell IDs (the only secret-safe way);
glow-while-present (no from-start timer — impossible); a PI-Icon countdown via
the engine's `SetDurationText`; the glow is lifted one strata above the cell
(`RaiseAboveCell`) so it renders over third-party frames. **Full detail and the
hard constraints are in `.claude/COOLDOWN-ALERTS.md` — read it before editing
these files.**

**`Sounds.lua` is not shipped.** It implements the notify sound via
`C_UnitAuras.AddAuraSound` (presets, combat-locked registration retrying on
`PLAYER_REGEN_ENABLED`) but is **not in the `.toc`, has no callers, and no
Options widget** — the alerts feature is visual-only in 2.0.0. It stays in the
repo as unfinished work and is excluded from the CurseForge zip by `.pkgmeta`.
To revive it: add it to the `.toc`, call `PI:QueueSoundRegister` from
`PI:SetMyTarget`, and add the picker to `CreateOptionsWindow`.

## Options window (Options.lua)

`CreateOptionsWindow` builds `PIOptionsWindow` in Lua (no XML/library). Tabs:
**Setup Guide** (opens by default; auto-shown on first install), **Macro Setup**,
**Raid Options**, **Notifications**, **Buffs to track**, **Custom buffs**,
**Behavior / Display**, **FAQ**. `C`=palette; `Fill`/`Edge`/`Outline`/`Label` are
the styling primitives (flat fills + hairline borders; `SetBackdrop` can't do the
square corners). `CreateNavButton`/`SelectSection` own the rail;
`CreateToggleRow` builds checkbox rows (each takes get/set; `set` calls the
matching refresh). A title-bar **Window scale** slider scales the whole window
(applies on release to avoid a feedback loop — the slider is a child of the frame
it scales). Read-only macro/URL boxes re-set text in `OnTextChanged` and swallow
`OnChar` while letting Ctrl+C/A through.

## Known hazards

- **Never compare a short name to a stored one** — display is the only place
  `ShortName` belongs.
- **`GetZoneText` takes no arguments** — another player's zone comes only from
  `GetRaidRosterInfo`'s 7th return (cached in `memberZones`).
- **Roster data goes blank across a loading screen** — `IsPlayerInZone` treats an
  unknown zone as a match and cleanup only drops people who left the group.
- **Combat.** Ticker stops, `ScanMacroAndSave` refuses to run (restricted APIs).
  Plus the 12.1 secret-value wall for the alerts feature.
- **`SendChatMessage` throttling** can disconnect a player — see `!pi` guards.
- **Protocol compatibility** — don't change the addon-message payload.
- **The ticker is the budget** — per-tick work is O(raid size), no string
  building; per-player API calls belong in `RefreshRoster`, not `RefreshZones`.
- **PIHelper/ is a reference addon** — never copy its code; it will be deleted.

## When adding a new option

1. Default it in `InitDB` (core) or `InitTrackingDB` (Cooldowns) — `if DB.x == nil`
   for booleans so `false` survives a reload. Note: defaults only apply to fresh
   saved vars (account-wide DB), so existing chars keep old values.
2. Add the widget in `CreateOptionsWindow`, anchored off its pane like neighbours.
3. In the widget's handler, write the DB value *and* call the refresh it affects
   (`UpdateAssignmentFrameVisibility`, `UpdateFrameLock`, `UpdateTickerState`,
   `QueueGlowUpdate`, ...).
4. If it changes whether the addon polls, route through `UpdateTickerState`.

## Checking your work

Parse-check every file with Lua 5.1 (the client's embedded version), and lint:

```
lua5.1 -e "assert(loadfile([[File.lua]]))"     # 0 = parses
luacheck File.lua                               # expect 0 ERRORS
```

Warnings are almost all WoW-global noise + benign `unused argument 'self'`.
`luacheck --only 211 221 231 311` (minus `self`) catches real dead code /
orphaned locals — the trick that has caught missing functions. `--only 113`
lists undefined vars; all should be real WoW APIs (an orphaned local shows here).

`check.lua` (repo only, excluded from the CurseForge build by `.pkgmeta`) stubs
the WoW API and drives the **assignment core** through a cross-realm raid (macro
parsing, whispers, broadcast, inbound, warnings, `!pi`, cleanup). It predates the
1.6.0 refactor/alerts — it exercises the assignment logic, not the new modules,
and can't catch a mistyped WoW API (a stub is whatever the harness says). The
only real check for runtime/frame/secret-value behaviour is in-game — see
`.claude/TESTING.md`.

## Releasing

`.toc` `## Version`, the top entry in `CHANGELOG.md`, and the git tag carry the
same version and must match. `CHANGES.txt` is the packager's commit dump.
CurseForge builds from the tag pushed to GitHub, so tag *after* the version bump
is committed. Don't overclaim raid-frame compatibility in public copy — only
Grid2 is verified in-game.
