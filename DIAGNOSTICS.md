# SurvivorUI Reborn Diagnostics

## Setup (once)

1. Install `SurvivorUI-Reborn.zip` into `Interface/AddOns/`.
2. Extract `SurvivorUI-Reborn-Diagnostics-Helper.zip` anywhere.
3. In game: `/sui reborn record auto on`
4. Run `Test-Diagnostics.bat` once (no gameplay needed). It uploads a
   synthetic session to `test/` in the private diagnostics
   repository and never touches `latest.json`.

## Normal use

1. Open AZ Reborn and play normally.
2. Complete one run and briefly start a second.
3. Exit the game completely.
4. Double-click `Upload-Diagnostics.bat`.
5. Ask Muse or ChatGPT to analyze the latest diagnostic session.

## Recording

Automatic recording starts a session at game start and finalizes it
on logout; a session left active by a crash or reload is marked
`interrupted` and remains uploadable. Manual commands:
`record start|stop|status|clear|mark <text>|auto on|auto off`.

Sessions live in the `SurvivorUIRebornDiagnostics` SavedVariables
database, bounded by event count and approximate serialized size;
low-priority events drop first and drops are counted per type.
Owner identifiers are replaced with stable session-local pseudonyms
(`player-1`, ...). Recording is off by default.

## Upload

The helper parses SavedVariables as data (never executes Lua),
verifies the destination repository is private, uploads
`sessions/<id>/` with the manifest last, verifies every remote file
hash, and updates `latest.json` only for the newest verified
session. Identical re-uploads create no commits; conflicting
contents for an existing session ID are refused.

## Replay

```sh
python3 scripts/replay_session.py <session-dir> fixture.lua
lua tests/replay_runner.lua fixture.lua
```

Replay validates the manifest and hashes first, then feeds recorded
raw payloads through production logic with a simulated clock.
Recorded output is evidence, not ground truth; native rendering and
protected actions cannot be replayed.

## Known limitations

- Curses taken before a `/reload` cannot be reconstructed (no
  banner history in the retell list).
- Ability upgrade effects are only as complete as the native
  tooltip data the client exposes.
- Windows behavior is validated by the self-test on the user's
  machine; CI validates Lua, packaging, and synthetic replay.
