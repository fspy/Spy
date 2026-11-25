# Spy (Forever) — fspy fork

Enemy-player detector for **World of Warcraft: Forever** (interface `16001`).

This is a community fork of [Spy (Forever) by Zerkaa](https://www.curseforge.com/wow/addons/spy-forever),
which adapts [Spy 1.3.8 by Slipjack](https://www.curseforge.com/wow/addons/spy-classic)
(Created by Immolation) to the Forever client.

## Install

The addon folder **must** be named `Spy` — that is where the game reads
`Spy.toc` and where `SpyDB` / `SpyPerCharDB` live.

### WowUp (GitHub provider)

1. WowUp → Settings → Addon providers → enable **GitHub**.
2. Get Addons → Install from URL → paste `https://github.com/fspy/spy-forever`.
3. Updates appear in WowUp like any other addon.

### Git

```sh
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/fspy/spy-forever.git Spy
```

Update with `git -C Spy pull`.

### Release zip

Download the latest `Spy-*.zip` from
[Releases](https://github.com/fspy/spy-forever/releases) and extract it into
`World of Warcraft/_forever_/Interface/AddOns/` (the zip contains a `Spy/` folder).

## First run

Type `/spy nameplates`, or enable **Options → Nameplates → enemy nameplates** and
**Always show nameplates**. Forever closes the combat log to addons, so Spy sees
enemies through nameplates, your target, focus and mouseover (about 40 yards).
Without "Always show nameplates" the game only shows nameplates in combat.

## Features (inherited from upstream)

- Nearby list with level, class and guild; click a row to target.
- Sound and visual alerts: new enemy, Kill On Sight, stealth (Stealth, Vanish, Prowl).
- Kill On Sight and Ignore lists, with reasons.
- Watched guilds and a watch list for your own faction.
- Statistics, win/loss records, and a combat map with skull markers.
- Sharing detections with party, raid or guild (off by default).
- Options window with live preview; minimap button.

## Commands

| Command | Action |
| --- | --- |
| `/spy` | List all commands |
| `/spy show` / `/spy hide` | Turn Spy on / off |
| `/spy config` | Options |
| `/spy nameplates` | Turn on the nameplate settings Spy needs |
| `/spy stats` | Statistics window |
| `/spy kos <name>` | Add/remove Kill On Sight |
| `/spy ignore <name>` | Add/remove Ignore |
| `/spy guild <guild>` | Add/remove a watched guild |
| `/spy watch <name>` | Add/remove a player of your faction from the watch list |
| `/spy fights` | Show/hide combat map skulls |
| `/spy testsound` | Check that alert sounds play |
| `/spy debug` | Print what Spy can currently see |

## Development

- Client: Forever, interface `16001`, retail-derived API.
- Era/anniversary API differences are handled in `Forever.lua`; read its
  comments before touching detection code.
- Unit information can arrive as **secret values**: guard reads with
  `canaccessvalue()` and `C_Secrets.*` (see `Spy3` and `Forever.lua` for patterns).
- `COMBAT_LOG_EVENT_UNFILTERED` is **not** available. Detection uses
  `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`,
  `UNIT_AURA` and related events.
- Lua is 5.1 (`luac -p` works for a syntax pass). The `Libs/` directory is vendored.
- Bump `## Version:` in `Spy.toc`, tag `v<version>` (without the addon prefix),
  and the release workflow builds `Spy-<version>.zip` with a `Spy/` top-level folder.

## Roadmap

Fork-specific changes are tracked in [CHANGELOG.md](CHANGELOG.md). Planned work:
more alert and detection options on top of the upstream feature set.

## Credits

- Spy by **Immolation** and **Slipjack**; translations by the Spy community.
- Forever port by **Zerkaa**.
- Libraries: Ace3, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets, HereBeDragons.

## License

Upstream Spy (Forever) is published as **All Rights Reserved** on CurseForge, and
Spy Classic carries the same terms. No new license is granted by this repository;
all rights remain with the original authors. This fork exists for personal
development and community testing. If you are an author and want it removed,
open an issue.
