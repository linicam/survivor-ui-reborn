# SurvivorUI Reborn Diagnostics Helper

One-time setup:

1. In game: `/sui reborn record auto on`
2. Double-click `Test-Diagnostics.bat`. It uploads a synthetic
   session to `test/` in the private diagnostics repository and
   never changes `latest.json`.

Normal use:

1. Play normally.
2. Exit the game completely (SavedVariables are written on exit/reload).
3. Double-click `Upload-Diagnostics.bat`.

The helper finds the diagnostic SavedVariables file, converts the
latest completed or recoverable session to JSON, and uploads it to
the private repository `linicam/survivor-ui-reborn-diagnostics`
using your existing GitHub CLI login. It refuses to upload if the
destination repository is public, verifies every uploaded file
hash, avoids duplicate commits for identical sessions, and updates
`latest.json` only after verification.

After a successful upload, tell Muse or ChatGPT:
"Analyze the latest diagnostic session."
