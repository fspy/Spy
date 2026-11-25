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
2. Get Addons → Install from URL → paste `https://github.com/fspy/Spy`.
3. The release publishes `Spy-forever.zip` and a `release.json` with the `forever`
   flavor, which is what WowUp looks for, so it should verify the client without
   the "unable to verify" warning. If you had the addon installed before, remove
   and re-import it so WowUp fetches the current release again.
4. Updates appear in WowUp like any other addon.

After installing, confirm the path is `Interface/AddOns/Spy/Spy.toc`. If WowUp nested the folder (`Spy/Spy/Spy.toc`) or named it differently, move the inner `Spy` folder so it sits directly in `AddOns/`.

### Git

```sh
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/fspy/Spy.git Spy
```

Update with `git -C Spy pull`.

### Release zip

Download **[Spy.zip](https://github.com/fspy/Spy/releases/latest/download/Spy.zip)**
and extract it into `World of Warcraft/_forever_/Interface/AddOns/` (the zip contains
a `Spy/` folder). Do not use GitHub's "Download ZIP" from the repository root — it
extracts as `Spy-main` and WoW will not load it.

The versioned asset (`Spy-<version>.zip`) is the same file.

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
- **Live Kill On Sight sync** with other players — see below.
- Options window with live preview; minimap button.

## Live Kill On Sight sync

Off by default. Turn it on with `/spysync on`.

Spy joins a hidden chat channel and exchanges addon messages there (the same
technique Happy Camper uses for camps). The lines never appear in chat. Kill On
Sight entries, reasons, notes and the **watched guild list** sync live, with no
`/reload`. Adding or removing a watched guild (and its reason) propagates the
same way.

- Default channel: `SpyKOS`. For a guild or friend group, set your own:
  `/spysync channel spy-kos-my-guild`. Everyone who should share must use the
  same channel name.
- The game can refuse a channel (crowded, locked or switched off); Spy retries
  and moves to `SpyKOSB` … `SpyKOSE`, then falls back to party/raid messages.
- Enabling sync joins the channel in the background and retries if the game's
  channel list is still settling; no `/reload` is needed after `/spysync on`.
  (Installing or updating the addon itself still needs one `/reload`.)
- If a channel still does not deliver, add your friend as a sync partner:
  `/spysync partner <player>`. Every change is also whispered to partners, which
  works without a channel. `/spysync test` prints the channel state and pings
  the channel and partners.
- Everyone in the channel with sync on can add and remove entries. Only use a
  channel with people you trust.
- Both players must run the same sync protocol; update both to fspy.7 or newer.
- Removals leave a tombstone for 90 days; the later change wins, using the
  server clock.
- Notes are shortened to 60 characters in sync, and a snapshot carries at most
  300 entries.

Commands:

| Command | Action |
| --- | --- |
| `/spysync on` / `off` | Turn KOS sync on / off |
| `/spysync status` | Entries, watched guilds, digest, transport and queue |
| `/spysync now` | Send your list and ask the channel for theirs |
| `/spysync channel <name>` | Use a channel (or `off` for party/raid only) |
| `/spysync partner <player>` | Add/remove a whisper sync partner (no channel needed) |
| `/spysync whisper <player>` | Send your list to one player over whisper |
| `/spysync test` | Print channel/partner state and ping both |
| `/spysync debug` | Print every sent, received and applied sync message |

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
