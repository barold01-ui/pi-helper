# Changelog

All notable changes to Power Infusion Assignment Helper will be documented in this file.

## [1.5.3]

- fixed a Lua error when raid chat arrived on 12.0 clients that hide chat
  text from addons; !pi simply doesn't answer those lines now

## [1.5.2]

- reworked the assignment window: cleaner list, easier to read at a glance
- no changes to how assignments are worked out or shared

## [1.5.1]

- fixed priests not seeing each other's PI targets
- fixed assignments not coming back after a UI reload
- added /pi debug for troubleshooting

## [1.5.0]

- redesigned the options window with a sidebar; all the same settings
- fixed cross-realm priests dropping off the list, and the warnings not
  firing for them
- fixed zone checks comparing everyone against your own zone
- fixed whispers to cross-realm targets
- PI targets who left the raid now say so instead of "different zone"
- !pi is rate limited and packs its reply into fewer messages
- assignments no longer flicker on loading screens
- performance improvements
- still works alongside priests running 1.4.x

## [1.4.5]

- fixed cross realm class colours

## [1.4.4]

- bump toc for 12.0.7

## [1.4.2]

- some fixes and improvements to recent features

## [1.4.1]

- some fixes and improvements to recent features.
- fixed warnings to only fire while in raid content, not in open world

## [1.3.9]

- add a check to catch PI targets which are not in the raid / not in same zone

## [1.3.7]

- fixed bug in scale slider
- fixed zone checks to correctly detect player zone changes / mismatches
- fixed UI element showing at incorrect times
- added option for non priests to show PI assignment window
- other bugfixes

## [1.3.5]

- added scale slider
- stopped UI elements from loading for non-priest classes

## [1.3.4]

- bump version

## [1.3.1]

- performance improvements
- improvements to "Test Mode"
- added zone filtering (only players in your raid group + zone are shown)

## [1.2.8]

- performance improvements

## [1.2.7]

- bump version to handle commit issue

## [1.2.6]

- Updated error handling, again
- fixed test mode

## [1.2.5]

- Updated error handling

## [1.2.4]

- minor cleanup

## [1.2.3]

### Added
- added some example macros

### Changed
- updated FAQ

## [1.2.2] - 2026-02-02

- update curseforge

## [1.2.1] - 2026-02-02

- add pkgmeta

## [1.2] - 2026-02-02

- testing version updates on Curseforge

## [1.1.0] - 2026-02-02

### Added
- Added "Power Infusion Assignment Helper" heading above the options panel tabs
- Added help text in Mode 1 explaining macro target format (target=yourtarget or @yourtarget)
- Added green hint text "Enter your macro name to get started" when no macro name is configured

### Changed
- Renamed "PI Options" tab to "Configuration"

---

## [1.0.0] - Initial Release

### Features
- Coordinate PI assignments between priests in raid groups
- Automatic macro scanning to detect PI targets (Mode 1)
- Manual mouseover target selection (Mode 2)
- Visual warning when multiple priests have the same PI target
- Optional whisper notifications to PI targets (guild members only)
- !pi command in raid/instance chat to report all PI assignments
- Moveable assignment display frame
- Hide in combat option
- Test mode for previewing the addon outside of raids
