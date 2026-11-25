# SurvivorUI for AZ Reborn — Compatibility Notes

Fork of [morderous/survivor-ui](https://github.com/morderous/survivor-ui)
(v3.0.68, GPL-3.0, author morderous) adapted for
[AZ Reborn](https://azreborn.com/). This branch (`reborn-compat`) is the
Reborn version; do not send its changes upstream as-is — see
[Synchronizing with upstream](#synchronizing-with-upstream) below.

Primary reference: the official AZ Reborn Addon API,
<https://azreborn.com/guides/addon-api>, read in full on 2026-11-25.
Where this document says "verified", it means stated on that page (or on
<https://azreborn.com/guides/data-api>). Where it says "not documented",
it means no occurrence was found on that page — not proof the game lacks
it, only that no supported API exposes it. In-game verification is still
required for several items; see the [testing checklist](#in-game-testing-checklist).

## What changed, in one paragraph

One new file, `SurvivorUI/RebornCompat.lua`, holds everything Reborn-
specific: boss-mode detection, the `AZS_ABILITIES` snapshot merge, the
meter-loadout jewelry reader, rank history, run-id resets, curse
reporting, and diagnostics. `Tracker.lua` and `Dial.lua` prefer live
Rift/time boss data over a schedule `at`; `BuildList.lua` shows passives
and racials from the snapshot instead of assuming `AZS_SPELLS` is
"6 actives + racial last"; the Jewelry panel reads the loadout first and
falls back to inventory slots. Everything else — UI layout, settings,
localization, SurvivorPlates — is untouched.

## Differences between the original game and Reborn

| Area | Original game (what the code assumed) | AZ Reborn (verified) |
|---|---|---|
| Interface | `## Interface: 11200`, WoW 1.12.1 client | `## Interface: 11200` addons load as current on the 3.3.5a rebuild, via the `AzerothSurvivorsAPI` compat layer. Keep `11200`. |
| Install path | `benilla-config\AddOns` | `Interface\AddOns` (players install SurvivorUI themselves; Reborn does not ship it). |
| Boss spawning | `AZS_SCHEDULE` is a complete fixed list of `{at, name, final, state}`; `AZS_RUN.nb` is only read in Endless mode | `AZS_RUN.nbs` (`known`/`unknown`/`up`/`none`), `nbm` (`rift`/`time`), `nb` (countdown, or the latest minute in rift mode, else −1), `nbc` (boss number), `nbn` (name, empty in Endless), `rift` (0–100). In Endless `nbm` is `time`, `nbn` is empty, `left` is −1. A missing field is missing, never 0; never derive a rift percent from the clock or from `nb`. |
| Abilities | `AZS_SPELLS` is the full learned list: 6 slotted actives + racial last, every row's icon/tooltip from the action-bar button at the same index | `AZS_SPELLS` keeps its action-bar layout only. The full list — including passives and selected racials — is the *requested* snapshot `AZS_ABILITIES` (`{key, spell, rank, passive, kind, cd, cdmax, name, icon, text}`, `kind` = `class`/`racial`, `spell` = 0 when none). It starts empty, clears on `AZSZONE`/reload, and no request is sent automatically. |
| Jewelry | Run jewelry occupies real WoW inventory slots 2/11/12/13/14 with real item links, Roman-numeral ranks, and tooltip lines to scrape | Live jewelry is exposed through `AZS_GetMeterLoadout()` (data include `AZSGEAR`); the `AZSGEAR` row shape is **not published** in the docs. Static `jewelry.json` has only `{key, name, icon, slot}` — no rarity, level, or effects. `AZS_STATS` `g*` fields are **aggregate** jewelry contributions, never per-item effects. |
| Run identity | Run resets detected by the run clock rewinding > 3 s (or a chat line) | `AZS_ZONE.run` is the run id (`azs:r<hex>`), stable across reload and host handover, new for each run. |
| Tables | Read once, keep a reference | The game replaces each `AZS_*` table on every line: re-read the global each time; each table has a `<TABLE>_UPDATED` stamp. After `/reload` tables start empty and are re-sent by `sync` on `PLAYER_ENTERING_WORLD`. |

## Root causes of the original issues

### Boss progression
Not a hardcoded table in the addon — a hardcoded *model*. Every boss
line, pip, and countdown assumed a schedule entry carries an absolute
spawn second `at` and a state in `{due, up, dead}`, and `game.nb` was
only read in Endless mode. A Rift-triggered boss has no meaningful `at`,
so it rendered as `0:00` or as no line at all, and nothing in the code
ever read `rift` / `nbm` / `nbs`. Boss *health* was the healthy part: it
is a live lookup in `AZS_UNITS` by name, and it is preserved unchanged.

### In-run jewelry
Zero AZS integration. Both jewelry surfaces read WoW inventory slots
via `GetInventoryItemLink` + `GameTooltip:SetInventoryItem` scraping,
keyed by link text and Roman-numeral rank suffixes. If Reborn jewelry
is virtual (server loadout only, no inventory item), both panels
silently show "empty" — nil link is a normal "slot empty" state. The
one game source that lists run jewelry, `AZS_GetMeterLoadout().runJewelry`,
was only ever read for *other* heroes' meter tooltips, never for the
local player. `JewelryData.lua` values are original-game values
(edition `c.1017.m`) and are not used for live Reborn jewelry.

### Missing abilities (e.g. Demonic Empowerment)
The build list assumed `AZS_SPELLS` is exactly 6 slotted actives plus
the racial last, and every row's icon/tooltip came from the action-bar
button at the same index. A passive in the list displaces an active,
masquerades as the racial, or is dropped; a button-less ability renders
blank anyway. Demonic Empowerment existed in code only as a *buff*
(`LASTING` in `BuildList.lua`), never as a build row. The fix is
general — use `AZS_ABILITIES` — not a hardcoded entry for that spell.
Third-party original-game sources disagree on its numbers, so nothing
about it is hardcoded.

## APIs and events used

| API / event | Used for | Notes |
|---|---|---|
| `AZS_RUN.nbs / nbm / nb / nbc / nbn / rift` | Next-boss mode, Rift %, countdown | Missing ≠ 0. See `SurvivorUI_RebornNextBoss()` |
| `AZS_SCHEDULE`, `AZS_GetUpcomingBosses()`, `AZS_GetBosses()` | Schedule rows (fallback), live bosses | Schedule still shown when it has real `at` values |
| `AZS_UNITS` | Boss health (unchanged) | By name, as before |
| `AZS_RequestAbilities()` + `AZS.On("AZSABILITIES", …)` | Learned abilities incl. passives/racials | Snapshot; throttled to ≤ 1 request / 5 s; re-requested on entering the world |
| `AZS_ABILITIES`, `AZS_SPELLS` | Merged ability list (dedup by key) | Abilities win on conflicts; spells fill gaps while the snapshot is pending |
| `AZS_GetMeterLoadout({apiVersion=1, runId, ownerId})` | In-run jewelry | Returns answer+nil or nil+`{code, message, retryable, …}`; never raises. Refreshed ≤ 1× / 2 s. Row shape probed defensively. |
| `AZSGEAR` (global, if present) | Jewelry fallback | Shape undocumented; same defensive parser |
| `AZS_STATS` `g*` fields | Aggregate jewelry bonuses | Displayed only as a whole-character aggregate, never per item |
| `AZS_ZONE.run` / `AZS_API_RunId()` | Run identity / state reset | New run id clears rank history, jewelry cache, and boss seen/killed state |
| `SendAddonMessage("AZSCMD", "sync", "PARTY")` | Not sent by this addon | The game sends `sync` on every `PLAYER_ENTERING_WORLD`; the addon relies on that |

## Implemented fixes and enhancements

### Phase 1
- **Bosses** (`Tracker.lua`, `Dial.lua`, `RebornCompat.lua`): when the
  next boss is Rift-triggered, the tracker shows `Rift 42%` (the game's
  `rift` value, never a clock-derived percent) and the Dial's thin ring
  shows the remaining share; when time-triggered it shows the live
  `nb` countdown. Schedule lines with a real `at` keep working; a
  Rift boss with no `at` gets no pip and no invented `0:00`. Endless
  mode keeps its timer line, now also fed by `nbm`/`nbs`. Transitions
  (rift → time, campaign → Endless) are re-read every draw from
  `AZS_RUN`, not inferred from the schedule. Run state resets on a new
  run id as well as on clock rewind.
- **Jewelry** (`BuildList.lua`, `RebornCompat.lua`): the Jewelry panel
  reads the meter loadout first (name, icon, slot, rank, rarity where
  the API gives them), then `AZSGEAR`, then inventory slots. Repeated
  acquisitions/upgrades of the same item update one row, never
  duplicate it. Hovering a loadout piece shows its name/rank/rarity
  and states that per-item effects are not exposed. Run jewelry state
  clears on a new run; the permanent Jewelry Collection is unchanged.
- **Abilities** (`BuildList.lua`, `RebornCompat.lua`): the build list
  merges `AZS_ABILITIES` with `AZS_SPELLS`, deduped by key. Actives
  fill the 6 slots, the snapshot's racial is the racial row (not "the
  last entry"), and passives get their own rows under it, with the list
  growing to hold them. Icons fall back to the snapshot's `icon` when
  there is no action-bar button, and the tooltip falls back to the
  snapshot's `text` with a "Passive" line. Run History snapshots use
  the same merged list. Nothing requests abilities every frame.

### Phase 2
- **Ability upgrade tracking — rank history only.** The API exposes
  only `rank`; there is no per-upgrade selection table, event, or
  function in the documented API. The addon therefore tracks rank
  increases per ability per run (`/sui reborn upgrades`): "Fireball:
  rank 1 → 2 at 63s". Tooltips say plainly that individual upgrade
  choices are not exposed. No stacking assumption (additive vs
  multiplicative) is made anywhere, and no upgrade effect text is
  invented. If a future API exposes selections, `TrackRanks` /
  `SurvivorUI_RebornRankEvents` in `RebornCompat.lua` is the place to
  join it.
- **Jewelry effects and tooltips — as far as the API allows.** Name,
  icon, slot, rank, and rarity are shown where the loadout gives them;
  per-item effect text and numeric bonuses are *not* shown, because
  neither the loadout docs nor `jewelry.json` publish them, and
  hardcoding original-game values would be wrong if Reborn rebalanced
  them. Aggregate `g*` bonuses are available in diagnostics and are
  never attributed to a single piece.
- **Curses — not implemented, by design.** No curse table, function,
  event, banner kind, or data file is documented in the official Addon
  API (the word "curse" does not appear on the page at all), and no
  public native-UI/addon example exposing curses was found.
  `SurvivorUI_RebornCurses()` therefore reports `supported = false`
  with that reason, `/sui reborn curses` prints it, and `/sui reborn
  probe` lists candidate globals (`AZS_CHESTS`, `AZS_BANNER`,
  `AZS_BUFFS`, `AZS_DEBUFFS`) so an in-game tester can see what exists
  without any of them being treated as curse data. Do not treat
  `AZS_DEBUFFS` (debuffs on bosses/guardians) or `AZS_CHESTS` (cache
  positions) as curses. If Reborn documents or exposes curse data in
  future, this is the documented blocker to revisit — with in-game
  payloads collected via `/sui reborn probe` first.

## Static data corrections (2026-11-25, from azreborn.com/data/v1)

The addon's hardcoded spell / talent / jewelry tables were script-compared
against the official data (`spells.json` 241, `talents.json` 474,
`legends.json` 237, `amulets.json`, `jewelry.json`) and corrected where
they disagreed. All values come from those files or from `Guide.lua`'s
game-generated tables; nothing was invented.

- **Spell names**: `SpellName()` misspelled 12 of 241 names (hyphens,
  apostrophes, commas, class prefixes, dropped words). All 12 are now in
  `NAMES` (`Avenger's Shield`, `Multi-Shot`, `Death Coil`,
  `Anti-Magic Shell`, `Dragon's Breath`, `Storm, Earth, and Fire`,
  `Summon Black Ox Statue`, `Hundred-Hand Slap`,
  `Invoke Xuen, the White Tiger`, `Song of Chi-Ji`, `Demon's Bite`,
  `Metamorphosis`). No hardcoded spell ids exist anywhere; identity is
  key-based.
- **Effect classes**: HEALING gained Circle of Healing, Riptide, Wild
  Growth, Renewing Mist; LASTING gained Sacred Shield plus the
  self-buff candidates (Shield Wall, Barkskin, Ice Block, Bloodlust /
  Heroism, Arcane Power, Blur, Demon Spikes, …) — each still needs
  in-game `AZS_BUFFS` confirmation, noted in the code. Heal-with-damage
  spells (Death Strike, Penance, Drain Life, …) are deliberately not in
  HEALING: that code assumes a heal has no range.
- **Talents**: 474/474 now match on tree / row / col / ranks. Fixed
  Predatory Strikes (ranks 3 → 5) and Dire Bear Form (row 6 col 0 →
  row 5 col 1); replaced the three phantom talents (Scatter Shot,
  Stormguard, Elemental Sunder) with Ricochet Shots, Earthen Bulwark,
  Unleashed Weapons; added the missing Predatory Instincts and Rending
  Claws; added full Death Knight / Monk / Demon Hunter trees (39 each);
  fixed Priest Holy and Rogue Combat tree icons.
- **Icons**: fixed Demonic Empowerment (`Ability_Warlock_DemonicEmpowerment`,
  was the Remove Curse icon), Devouring Plague, Frost Trap, Stormstrike.
  A name-only map cannot serve both talents and spells, so the meter now
  prefers a `SurvivorUI_SPELL_ICONS` table for damage lines and Run
  History resolves Ferocity / Tranquil Spirit by the run's class.
  Metamorphosis is the one spell with two different official icons
  (Warlock vs Demon Hunter) and is left out of the spell map.
- **Jewelry**: CLASS_SPELLS 103 → 237 entries (all 12 classes, exactly
  the 237 legends), including Demonic Empowerment; the two phantom
  Shaman entries (Lightning Shield, Healing Wave) are removed. Death
  Coil and Metamorphosis are shared by two classes, so the finder's
  class now decides attribution; a leading `Vampiric ` is stripped
  when matching found amulets. `COMMON_TOTALS`: Ring 9 → 12, Trinket
  14 → 32. JewelryData: Eye of Hakkar crit 5% → 4.8%, Onyxia Tooth
  crit damage 20% → 19.5%; Star of Mystaria, Ring of the Devoured,
  Seal of the Damned, Hand of Justice, Major Soulstone take Guide.lua's
  values; the 3 missing rings and 18 missing trinkets are added with
  nil bonuses — official data carries no bonus values for them.
- **Ranges**: Options SPELLS now covers all 241 spells (was 89);
  kill_command 35 → 30 yd, searing_totem 22 → 25 yd, Fireball sample
  35 → 30 yd. Pre-existing melee 7/8 yd entries are kept: they are
  tooltip reach, not data range (official range is 10).

Still unresolved / not fixed, by design: Holy Fire's school
(`spells.json` says Fire, the addon says Holy — needs an in-game
tooltip); `call_of_flame` is flagged legendary in `spells.json` but
has no legend in `legends.json` (official-data gap, nothing invented);
the 23 added SPELLS entries with official range 0 show as "0 yd"
pills; the new DK / Monk / DH range rows do not render in the
Options picker until `CLASSES` lists those classes (extending it
also affects records / fx pickers, so it was left alone); the
"Info shows" prose still names only the original 8 lasting spells.

## Known limitations and unsupported features

- **In-game verification is still required** for: the exact `AZSGEAR` /
  loadout source fields (rarity? rank? effect text?), which campaign
  bosses are Rift- vs time-triggered, the campaign→Endless transition
  values, and whether `AZS_ABILITIES` includes every passive for every
  class. The code is written defensively for all of these, but only a
  real run can confirm them. See the checklist below.
- **Ability upgrades**: rank only (above). No per-upgrade identity,
  counts beyond rank rises, or cumulative bonuses.
- **Curses**: not exposed (above).
- **Jewelry per-item effects**: not exposed (above).
- **Treasure Goblin tracking, jewelry classifications, automation**:
  explicitly out of scope; not implemented.
- The Jewelry Collection (`Jewelry.lua`) remains inventory-based and
  permanent by design; it records pieces actually worn as WoW items.
  In Reborn, loadout-only pieces do not enter the Collection — that is
  a known gap, not a bug in the in-run panel.
- `JewelryData.lua` still holds original-game codex values for the
  Collection's "not found yet" rows; do not treat those as Reborn
  values.

## Diagnostics

Debug logging is **off by default** (`SurvivorUIDB.rebornDebug`).
Diagnostics never send addon messages except through the game's own
sync, never request server data every frame, and never include
credentials, tokens, or personal data. Probe output is plain text you
can copy out of chat.

| Command | What it does |
|---|---|
| `/sui reborn` | Summary + command list |
| `/sui reborn probe` | Full probe: run id, boss mode/fields, schedule/units/spells/abilities counts, merged abilities, rank events, jewelry source + items + loadout error, aggregate `g*`, curse status, candidate globals |
| `/sui reborn boss` | Next-boss mode, state, name, number, rift, countdown |
| `/sui reborn abilities` | Forces one ability snapshot request, then lists merged actives/passives/racials |
| `/sui reborn jewelry` | Forces one loadout refresh, then lists jewelry + aggregate |
| `/sui reborn upgrades` | Rank increases recorded this run |
| `/sui reborn curses` | Curse support status + the documented blocker |
| `/sui reborn debug on` / `off` | Opt-in debug logging to chat |

## In-game testing checklist

Do these in a real AZ Reborn run, in order. For anything unexpected,
run `/sui reborn probe` in that run and keep the output.

### Setup
- [ ] Close the game. Back up existing `SurvivorUI` / `SurvivorPlates`
      folders. Extract `SurvivorUI-Reborn.zip` into `Interface\AddOns\`
      so you have `Interface\AddOns\SurvivorUI` and
      `Interface\AddOns\SurvivorPlates`. Start the game, enable both
      addons if asked, and confirm SurvivorUI loads (minimap S button,
      `/sui` lists commands including `/sui reborn …`).
- [ ] `/sui reborn probe` out of a run: note `active=`, `runId=`,
      and whether `AZS_ABILITIES` / loadout functions exist.

### Bosses
- [ ] Start a run. In the tracker, the next boss line shows either a
      countdown (`in 1:23`) or `Rift NN%` — never `0:00` for a boss
      that has not spawned.
- [ ] If a boss is Rift-triggered: the Rift % rises during the run and
      the Dial's thin ring shrinks as it fills. Note the % at the
      moment the boss spawns.
- [ ] Kill a boss: its line turns slain, its health showed while alive
      (tracker line / boss bar), and the next boss line updates.
- [ ] Reach Endless: the tracker shows the Endless timer line and the
      "Endless bosses slain" count; no Rift % is shown.
- [ ] `/reload` mid-run: boss lines, Rift % / countdown, and slain
      counts come back (via sync). Start a *new* run: no boss from the
      previous run is shown.

### Abilities
- [ ] Learn abilities. The build list shows all of them; compare with
      the game's own build row. No ability is missing, none appears
      twice, and the racial is the row tagged `(racial)`.
- [ ] Warlock: learn Demonic Empowerment. It appears as a passive row
      (hover it: "Passive" + the API description), not as the racial
      and not displacing an active.
- [ ] `/sui reborn abilities`: `source=abilities`, `complete=true`,
      and the listed passives/racials match what you see in the list.
- [ ] Level an ability up: `/sui reborn upgrades` records one rank
      increase for it. The tooltip does *not* claim a specific upgrade
      was picked.

### Jewelry
- [ ] Pick up a ring / amulet / trinket. The Jewelry panel shows it
      (name, rank, rarity where given) within a couple of seconds, and
      updates when it upgrades — one row per piece, no duplicates.
- [ ] Hover a piece: the tooltip shows name/rank/rarity and the note
      about per-item effects not being exposed.
- [ ] `/sui reborn jewelry`: note `source=` (`loadout` / `gear` /
      `inventory`) and any loadout error code. If `source=inventory`
      in Reborn, include the probe output in your report — that is the
      key unknown.
- [ ] `/reload` mid-run, then start a new run: the previous run's
      jewelry does not leak into the new run.

### Curses / upgrades (limitations)
- [ ] Open a cursed chest. `/sui reborn curses` still reports
      `supported=false` (expected until Reborn documents curse data).
      If any curse UI appears anywhere, note exactly what it says and
      run `/sui reborn probe` immediately afterwards — that payload is
      what a future implementation needs.
- [ ] Confirm nothing in the addon claims a specific upgrade or curse
      effect that the game did not tell it.

### Regression
- [ ] Existing settings survive the update (panel positions, options).
      Unrelated features (meter, run panel, tracker, plates) behave as
      before. No Lua errors on load, on run start, or on `/reload`.

## Packaging and releases

Reproducible build, no dev tools needed to *use* the result:

```sh
bash scripts/package.sh        # -> dist/SurvivorUI-Reborn.zip
python3 scripts/validate_addon.py                 # working tree
python3 scripts/validate_addon.py --zip dist/SurvivorUI-Reborn.zip
lua tests/test_reborn_compat.lua                  # mocked tests
```

The ZIP contains exactly:

```
SurvivorUI-Reborn.zip
├── LICENSE
├── SurvivorUI/        (SurvivorUI.toc, Lua, Art, Fonts, Sounds, Bindings.xml)
└── SurvivorPlates/    (SurvivorPlates.toc, Lua, Art, Bindings.xml)
```

No parent directory inside the archive, no `.git`, tests, scripts, CI
config, installer, or docs. `dist/` is git-ignored; CI rebuilds it.

GitHub Actions (`.github/workflows/reborn.yml`) runs on pushes to
`main` / `reborn-compat`, pull requests to `main`, and manual dispatch:
Lua syntax check, mocked tests, manifest validation, packaging, archive
validation, and upload of the ZIP as the `SurvivorUI-Reborn` artifact
(90 days). Only a push of a `v*` tag publishes the ZIP as a release
asset — never create a tag or a release without explicit approval.

## Installation and rollback

1. Download `SurvivorUI-Reborn.zip` — from a GitHub Release asset, or
   from a workflow run's `SurvivorUI-Reborn` artifact (Actions tab →
   the run → Artifacts).
2. Close AZ Reborn completely.
3. Back up `Interface\AddOns\SurvivorUI` and
   `Interface\AddOns\SurvivorPlates` (copy them elsewhere).
4. Delete those two folders, then extract the ZIP into
   `Interface\AddOns\` so the two folders reappear there.
5. Start the game; enable the addons in the game's addon list if asked.
6. Verify: the minimap S button appears and `/sui reborn` prints the
   Reborn summary.
7. Settings live in the game's SavedVariables and are preserved by
   replacing the addon folders (they are not inside them). To roll
   back, close the game, delete the two folders, and restore your
   backup copies.

## Synchronizing with upstream

Keep Reborn changes small and local so upstream merges stay cheap:

- **Do not edit upstream files more than necessary.** Reborn logic
  lives in `RebornCompat.lua`; the patches in `Tracker.lua`,
  `Dial.lua`, `BuildList.lua`, and `SurvivorUI.lua` are narrow call
  sites that degrade gracefully when the compat functions are absent
  (every call is guarded with `SurvivorUI_Reborn… and …`).
- When upstream releases a new version: merge/sync `main` from
  `morderous/survivor-ui` into this fork's `main`, then rebase or merge
  `reborn-compat` onto it. Expect conflicts only in the patched call
  sites listed in the commit history; `RebornCompat.lua` itself should
  merge cleanly.
- Never submit a pull request to `morderous/survivor-ui` from this
  branch, and never copy Reborn-only behaviour (loadout parsing,
  Rift-mode UI) into an upstream PR.
- If Reborn documents new APIs (notably curse data, `AZSGEAR` rows, or
  per-ability upgrade selections), update `RebornCompat.lua` and the
  "Known limitations" section here first, then the UI — and re-run the
  mocked tests with the newly documented shapes as VERIFIED fixtures.

## Validation performed (2026-11-25)

- Lua syntax: `luac -p` on every `SurvivorUI/*.lua` and
  `SurvivorPlates/*.lua` — pass.
- Mocked tests: `lua tests/test_reborn_compat.lua` — 79 checks pass,
  0 fail. Fixtures are labelled VERIFIED (documented API shapes) vs
  DEFENSIVE (undocumented shapes, e.g. `AZSGEAR` rows) in the test
  file header. These prove logic against the documented contract;
  they are **not** in-game verification.
- Packaging: `bash scripts/package.sh` produces a valid
  `SurvivorUI-Reborn.zip` (357 entries) that passes
  `validate_addon.py --zip`.
- **Not verified in-game** (no AZ Reborn runtime was available):
  boss Rift/time behaviour, `AZSGEAR`/loadout field shapes, passive
  coverage for all classes, curse data. See the checklist above.
