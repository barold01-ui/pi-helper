# Project notes (.claude)

Context for working on **PowerInfusionAssignments** — a retail WoW (12.1
"Midnight") priest addon. Read these before making changes; they capture the
non-obvious, hard-won decisions that aren't derivable from the code alone.

- **ARCHITECTURE.md** — module layout, the shared `PI` namespace pattern, saved
  variables, and how to validate edits (lua5.1 parse + luacheck).
- **COOLDOWN-ALERTS.md** — the headline feature and the 12.1 secret-value
  constraints that shape it. READ THIS before touching Notify/Glow/PIReady/Sounds
  — it records what is impossible and must not be re-attempted (e.g. a
  from-cooldown-start timer).
- **CONVENTIONS.md** — the golden rules: PIHelper/ is reference-only, the
  secret-value rule, retail API gotchas, the strata fix, versioning, public copy.
- **TESTING.md** — the `/pi` debug/test commands and what is / isn't verified
  in-game (Grid2 confirmed; other frame addons not).

Current version: **1.6.0** (added Cooldown Alerts). Reference addon `PIHelper/`
will be deleted once feature work settles — do not depend on it.
