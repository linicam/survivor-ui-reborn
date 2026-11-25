# SurvivorUI Reborn Diagnostics Helper

1. In game: `/sui reborn record start`, play normally, then `/sui reborn record stop`.
2. Exit the game completely (SavedVariables are written on exit/reload).
3. Double-click `Upload-Diagnostics.bat`.

The helper finds the diagnostic SavedVariables file, converts the
latest completed session to JSON, and uploads it to the private
repository `linicam/survivor-ui-reborn-diagnostics` using your
existing GitHub CLI login. It refuses to upload if the destination
repository is public, never uploads unrelated files, and updates
`latest.json` only after the session manifest is verified.

After a successful upload, tell Muse or ChatGPT:
"Analyze the latest diagnostic session."
