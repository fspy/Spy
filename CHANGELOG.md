# Changelog

## 1.3.8-forever30-fspy.8

- A **Sync** page in the addon's options window (not a slash command): enable
  sync, set the channel, see entries/guilds/digest/channel members/queue, add the
  current target as a partner, add a partner by name, remove partners with a
  button, Sync now, Test connection and toggle debug messages.
- A chain icon in the Spy window's title bar shows sync state (green connected,
  yellow waiting, red channel refused, grey off) and opens the Sync page on
  click.
- The slash commands remain as shortcuts for the same actions.

## 1.3.8-forever30-fspy.7

- Watched guilds now sync too: guild name, reason, adds and removals travel in
  the journal, deltas and snapshots, with the same server-clock and 90-day
  tombstone rules as Kill On Sight players.
- The sync digest covers guilds, and `/spysync status` reports entries and
  guilds separately.
- Sync protocol bumped to 2: update every player to fspy.7 or newer.

## 1.3.8-forever30-fspy.6

- Channel joins are retried in the background (every 10 seconds) while sync is
  on, instead of only while a message is waiting. A join that fails silently
  while the game settles its channel list no longer needs a `/reload`; after
  three misses Spy moves to the next backup channel.
- Queued channel messages are kept for up to five minutes while the join is in
  progress, then fall back to party/raid only if every channel was refused.

## 1.3.8-forever30-fspy.5

- Release packaging only: CI now publishes `Spy-forever.zip` and a
  `release.json` (`forever`, interface 16001) next to the versioned zip and
  `Spy.zip`, so WowUp's GitHub provider verifies the client instead of
  warning and falling back to the generic asset.

## 1.3.8-forever30-fspy.4

- `/spysync partner <player>`: every change is also whispered to partners, so
  sync works even when a channel is refused or does not deliver.
- `/spysync test`: prints the addon version, channel, member count, queue,
  partners and join state, then pings the channel and partners.
- `PING`/`PONG`, and debug logs for channel joins/notices, sends with their
  result codes, and received messages.
- `/spysync status` now shows channel members, the queue and partners.

## 1.3.8-forever30-fspy.3

- **Live Kill On Sight sync** with other players, no `/reload`. A hidden addon
  channel carries entries, reasons and notes; party/raid/whisper messages are
  used when no channel is available. Channel failures retry and move to backups
  (`SpyKOSB` … `SpyKOSE`).
- `/spysync on|off|status|now|channel|whisper|debug`, plus options under
  **Data** for the toggle and channel name.
- Per-character sync journal with server-clock timestamps and 90-day tombstones,
  so adds, reason changes and removals converge between players.

## 1.3.8-forever30-fspy.2

- Statistics window: right-clicking any player now offers **Set Kill On Sight reason**,
  whether or not they are already on the Kill On Sight list. Picking a reason adds the
  player to the list automatically, so no `/spy kos` first.
- Statistics window: implemented the real reason submenu (categories → reasons with
  checkmarks and **Clear Reason**) instead of only the "Other" dialog.
- Statistics window: KOS colouring and the **KOS** filter now read the Kill On Sight
  list directly, so players added from another character also count.

## 1.3.8-forever30-fspy.1

- Fork of [Spy (Forever) 1.3.8-forever30](https://www.curseforge.com/wow/addons/spy-forever) by Zerkaa.
- Added GitHub release packaging (`Spy-<version>.zip` with a `Spy/` top-level folder).
- Added repository documentation: install, Forever detection constraints, development notes.
- No gameplay changes yet.
