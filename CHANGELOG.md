# Changelog

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
