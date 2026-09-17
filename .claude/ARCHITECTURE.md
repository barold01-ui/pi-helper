# Architecture

PowerInfusionAssignments is a WoW (retail, 12.1 "Midnight") addon that helps
priests coordinate Power Infusion assignments and alerts healer priests when
their PI target uses a big cooldown.

## Shared namespace

Every file starts with `local ADDON_NAME, PI = ...` (or `local _, PI = ...`) to
capture the private addon table WoW passes each file. `PowerInfusionAssignments.lua`
must load first — it captures `PI` and sets `PI.MSG_PREFIX`, which later files
read at load time. All cross-file state and API goes through `PI:Method()` /
`PI.field`; there are no globals except the ones WoW requires (the `PI_SetPITarget`
macro function, and the `SLASH_*` / `PowerInfusionAssignmentsDB` saved variable).

## File layout (load order = .toc order)

| File | Responsibility |
|---|---|
| `PowerInfusionAssignments.lua` | Core: namespace, `MSG_PREFIX`, `Debug`, `InitDB`, `SetTestMode`, scan ticker, combat flag, panel visibility/lock, `CleanupStaleAssignments`, `DumpState`, slash command, the event frame + dispatch, first-run window popup |
| `Roster.lua` | Identity (`SetIdentity`, `GetPlayerName`), name/wire helpers (`Qualify`, `ShortName`, `RealmOf`, `ToWire`, `FromWire`, `ResolveName`), all per-member caches + `RefreshRoster`/`RefreshZones`, class colours, group/zone/role queries, `GetUnitTokenForName` |
| `Comms.lua` | Addon-message networking (`BroadcastAssignment`, `RequestAssignments`, `OnAddonMessage`) and the `!pi` chat report |
| `Macro.lua` | Macro parsing, `PI_SetPITarget` (mouseover capture), `SetMyTarget`, the two scan modes |
| `AssignmentFrame.lua` | The on-screen assignment panel: palette, pooled rows, warnings, layout, diff-driven `UpdateAssignmentFrame`, test-mode header tag |
| `Cooldowns.lua` | Cooldown/buff catalog (per DPS spec), enabled-spell-ID set (`GetTrackedSpellSet`), custom buffs, `IsHealerSpec`, all notify/effect DB defaults (`InitTrackingDB`) |
| `PIReady.lua` | Tracks whether our own PI is off cooldown (the gate for showing alerts). See COOLDOWN-ALERTS.md |
| `Sounds.lua` | Notify sound via `C_UnitAuras.AddAuraSound` + LibSharedMedia sound list |
| `RaidFrames.lua` | Find the assigned target's raid/party cell across frame addons (`FindUnitFrame`) |
| `Glow.lua` | The highlight effects (PI Icon + countdown, Pulse Border, Flash Frame) painted on the target's cell |
| `Notify.lua` | The engine: binds a Blizzard `AuraContainer` to the target's cell, filtered to tracked spell IDs; drives the glow; test-preview toggle; `/pi notify` diagnostics |
| `Options.lua` | The `/pi` options window (all tabs, palette, widgets), plus `SetError`/`SetSuccess` |

## Saved variables

`PowerInfusionAssignmentsDB` — **account-wide** (`## SavedVariables`, not
per-character). `assignments` is wiped on login (live raid state, rebroadcast).
`OptionalDeps: LibSharedMedia-3.0, SharedMedia` so LSM loads first when present.

## Validation

No in-repo test suite. Validate edits with the local tools:
- Parse (WoW's Lua): `lua5.1 -e "assert(loadfile([[File.lua]]))"`
- Lint: `luacheck File.lua` — expect 0 ERRORS. Warnings are almost all WoW-global
  noise (`--only 113` lists undefined vars; all should be real WoW APIs) plus
  benign `unused argument 'self'` on `PI:` methods and a pre-existing unused
  `foundName` in Macro.lua. Use `--only 211 221 231 311` (minus `self`) to catch
  real dead code / orphaned locals — the trick that has caught missing functions.
Static checks can't verify runtime; the frame/aura/secret-value behaviour only
shows in-client. See TESTING.md.
