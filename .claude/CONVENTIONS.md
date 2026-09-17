# Conventions & gotchas

## PIHelper/ is REFERENCE ONLY — never copy its code
The `PIHelper/` folder is a **separate reference addon** (author "squided"), kept
only for studying how features work. It is slated for **deletion** and nothing
may depend on it at runtime. Learn the technique and reuse facts (spell IDs,
Blizzard API names, where each raid-frame addon stores its cells), but write our
own implementation and improve on it — never lift files/functions verbatim.

## 12.1 secret values — the golden rule
The engine can DISPLAY secret-derived data; your addon can never READ it to act
on it. Anything touching another player's auras/casts/combat-log in combat is
secret and errors on read. Guard with `issecretvalue()` and `pcall`. See
COOLDOWN-ALERTS.md for the full picture. Do NOT try to build logic that branches
on a value the engine only displays (e.g. "hide if <5s left" — impossible).

## Retail API gotchas encountered
- `SetFont`'s flags arg is not optional (`""` not nil).
- Aura buttons forbid addon scripts: `OnUpdate`/`OnShow` on a child of an aura
  button do NOT fire. Poll from an INDEPENDENT frame if you must (but note their
  visibility is unreadable anyway — see COOLDOWN-ALERTS.md).
- To render a highlight OVER a third-party cell, bump STRATA, not just frame
  level (strata dominates). See RaiseAboveCell.
- `GetStringWidth/Height`, frame sizes, unit tokens, and `IsVisible` can be
  secret in combat — read via pcall + `issecretvalue`, with fallbacks.

## Saved variables
`PowerInfusionAssignmentsDB` is account-wide. Most new option defaults use
`nil`-checks in `InitDB`/`InitTrackingDB`, so they only apply to fresh installs;
an existing character keeps its saved values. Mention this when changing defaults.
`assignments` is wiped on login by design (live raid state, rebroadcast).

## Wire-format compatibility
`ToWire`/`FromWire` keep the 1.4.x-era "Player:Target" addon-message shape and
short/qualified name handling so mixed raids still interop. Don't change the
payload shape casually.

## Versioning / release
Version lives in `PowerInfusionAssignments.toc` (`## Version:`). Bump it + add a
`CHANGELOG.md` entry (plain-bullet style, user-facing) for releases. `CHANGES.txt`
is an auto-generated git-log dump — leave it. Not a git repo in this workspace;
the user handles GitHub pushes.

## Public-facing copy
Don't overclaim raid-frame compatibility on the addon page/changelog — only Grid2
is verified in-game. Say "verified on Grid2" rather than listing untested addons.
