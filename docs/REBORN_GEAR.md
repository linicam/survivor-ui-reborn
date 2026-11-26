# Gear & Difficulty Analyzer

Select the class, equipment, Campaign map and difficulty in the hero menu, then enter Dalaran mode. Open **Survivor UI → Global → Open Gear & Difficulty** or use `/sui gear` in the world. The native character window's **Upgrades** button opens the same planner. Hover an equipped slot there for its next-star and next-tier previews.

Use **Set Current Configuration as 100% Baseline** once on a familiar configuration for each class. The addon stores the actual map, tier, reported modifiers, equipped item identities, model inputs, active sets, game/data version and time. A later selection leaves the saved configuration in place until you explicitly replace it. Compatible inputs are reevaluated under the current model, even when the server build or model version changes. The UI calls out changed modeled baseline values. Uninterpretable or unsupported configurations remain stored with an explanation. Legacy map-only references and cached gear are left on disk for compatibility and stay outside the live analysis.

The two tabs share the same calculation. **Difficulty & Upgrade Planner** displays early output and survival pressure plus both upgrade plans. **Equipment Simulator** starts from actual gear. Change the tier and stars of supported slots, load either completed plan, or reset to actual gear. The plan and simulator change local previews only.

## Data contracts

- `AZSZONE` supplies the world selection, class, `dt`, `heroic`, and reported modifiers. A known Campaign map and consistent difficulty are required for comparison. The module uses the selected map reported in this world context. A Dalaran-only key cannot identify the selected Campaign map. It has no fallback to a historical run.
- The native addon requests `sync` on world entry. `AZSARMOR` supplies the list of equipped items after `AZSZONE`, including slot, rarity, stars and the native item description fields. An explicit empty list is valid. The currently installed `Units.lua` documents that a hero wearing no equipment may receive no list, which the addon treats as unavailable. The module freezes normalized context fields. Replaced or in-place-mutated tables with a new identity invalidate the gear and search. Equivalent events preserve them. The armor line carries no run ID. A late older line that arrives after a new valid zone event cannot be attributed by this interface.
- The hero menu is a separate Glue Lua environment. The documented World API and its native handlers provide no account collection, ascension permission, ascension price or post-ascension star state. The planner uses equipped gear and drop paths. The restriction for Legendary and higher includes clearing the final map of the next expansion. Dalaran cannot confirm an individual player's completion or eligibility.
- The original game paths are gated out. **Enable Gear & Difficulty** in Global settings controls the two tabs and native previews. The native subscriptions have gated callbacks because `AZS.On` exposes registration only. Completed search results are cached for the current inputs. The only extra `sync` request is when the player enables the feature while in the world.

## Equipment and pressure

For each item, sum `slot stat × tier slot scale` and `class profile stat × tier profile scale`, multiply by the catalog's common factor, then by `1 + min(stars, steps) × star_step + top_star_bonus`. Gear stats use fractions for percent shares and flat units for HP and regeneration. The UI shows pre-rounding sums and percentage-point changes. The native item display rounds HP per piece while the game adds the gear contribution before rounding.

Set thresholds come from `AZS_GEN.setRules` and matching class or shared rows from `AZS_GEN.setBonuses`. In the pinned content, four armor pieces at one star activate the four-piece effect, eight at three activate the eight-piece effect and eight at five empower eligible effects. Weapons are excluded. Verified unconditional shared four-piece gold, pickup, Echo and critical-damage modifiers appear in attributes. Spell-specific, conditional, or otherwise unquantified effects appear as set text. The solver protects active set effects with unquantified combat value.

| Quantity | Formula or source |
| --- | --- |
| Map output demand | Public zone base health factor × standard Campaign tier health factor. |
| Map survival demand | First boss base hit × standard Campaign tier hit factor. A representative early incoming hit. |
| Gear output capacity | `1 + sum of gear damage shares`. Neutral non-gear background and an ability affected by ordinary gear damage. |
| Gear survival capacity | `(class starting HP + flat gear HP) / (1 - min(gear damage reduction, 0.60))`. Standard cap under neutral non-gear assumptions. |
| Each pressure | `100 × target demand / baseline demand × baseline capacity / target capacity`. |
| Combined estimate | Maximum of output and survival pressure, provided both are available. |

Standard tier multipliers are shared with the Campaign analysis. The baseline is user-defined. The `100%` comparison uses a `0.000001` percentage-point tolerance. The pressure model is theoretical and uncalibrated. It excludes spawn density, encounter scripts, affix and challenge scaling, talents, regeneration, movement, crit, cooldown, Echo and special ability or summon behavior. The 60% cap is the documented standard and excludes the Warrior Titan talent exception. An available component can be shown independently.

Named affixes and built-in Heroic rules qualify the calculation as standard Campaign pressure only, for either the baseline or target. The legacy `aff` field alone carries no named modifier evidence. An explicit unsupported mode, including active Proving Grounds, removes the pressure comparison and plans. When the native feed provides only a supported map and tier, the estimate remains scoped to ordinary Campaign pressure. Rift and Endless encounter mechanics are outside that estimate.

## Plans and gold

Plan A keeps the option to retain and upgrade worn pieces and includes replacement gear from the current expansion's Campaign drops. The public zone table and documented pair/override rule determine standard tiers. The native tier catalog and pack assignment identify the extra end-of-expansion tiers. A drop begins at zero stars for quoting. Replacement acquisition adds a separate gameplay requirement. Inventory ownership and its existing stars, direct ascension and slot-specific account progression are unavailable. Plan B upgrades only the same items and tiers. The player balance does not restrict either search.

Equipment normalization, evaluation, previews, and optimization share the same class and slot contract. Native weapon layouts and class or tier weapon lists provide slot evidence. The stock layout retains known ranged and main-hand slots. An explicit pack-tier weapon list that lacks the relevant entry leaves that drop unverified for the slot. The documented Legendary appearance fallback applies when the class has no override. The simulator can still evaluate a legal theoretical class/slot/tier combination whose drop path is unverified.

A step to stars one through five costs `round(408 | 816 | 1496 | 2720 | 4080 × tier factor)`, rounded per step. The November 16, 2026 price chart's reduction is already in those base prices. Weapons use the same factors. Exotic, Elementium and Legendary's fifth star include formula-derived estimates. If a native factor differs from the verified schedule, the analyzer omits the unknown quote from the solver and indicates that the candidate was excluded. Gold shown for a replacement is the calculable amount spent on stars. No downgrade refund is assumed.

The search uses bounded depth-first enumeration with protection-aware suffix bounds on capacity, relaxed minimum gold bounds, and deterministic candidate order. It seeds the search with the best available worn upgrades and a legal full configuration guided by optimistic capacity. A feasible seed can be reduced in cost before enumeration. The best feasible result minimizes calculable gold among comparable candidates. Otherwise it minimizes remaining modeled pressure, then gold within the numerical tolerance. Slots with the largest possible damage spread are decided first, with native order as a tiebreaker. See the [canonical delivery report](reviews/PR-006.md#d-optimization-correctness-and-product-decisions) for proof boundaries and benchmarks. The UI suspends work off the planner tab and releases unfinished results when it closes.

The native tooltip extension post-hooks `AZSInspect:RefreshDoll` and the slot's existing `OnEnter` using `hooksecurefunc` and `HookScript`. It appends after the host sets the tooltip owner and validates that the slot matches this world's equipped item. Simulator icons evaluate adjacent changes from the current simulated loadout. Plan icons compare the actual item with the proposed target and present the isolated pressure next to the full-plan pressure. Tooltip ownership is released on relevant panel, slot, or context changes. Hovering performs no combination search.

## Offline verification

Run the following with Python 3 and Lupa's Lua 5.1 runtime. Supply a trusted, locally accessible `Generated/Content.lua` from the game. The script executes that input as Lua. Use `--source-root` to compare the same data against an earlier checkout or source archive and `--repeat` to smooth CPU timing.

```text
python scripts/verify_reborn_gear.py --native-content <Generated/Content.lua> --repeat 7
python scripts/verify_reborn_gear.py --native-content <Generated/Content.lua> --gear-csv <independent-extraction.csv> --source-root <checkout>
```

The optional UTF-8 CSV has a header. Its first eight columns are tier key, star count, three extraction metadata columns, Warlock main-hand damage as a percentage, eight-armor-piece flat HP, and eight-armor-piece damage as a percentage. Supply values extracted independently of the planner. The verification compares the final three values at a tolerance of 0.00051 in their reported units, allowing a three-decimal reference. The benchmarks compare returned plan pressure and gold with the full public evaluator and check repeatability. Small-space optimum is checked separately by exhaustive enumeration in `tests/test_reborn_gear.lua`. Native game data, local expected CSV, and historical captures remain external.

Sources: [Addon API](https://azreborn.com/guides/addon-api), [Content reference](https://azreborn.com/guides/content-reference), [Data API](https://azreborn.com/guides/data-api), [Progression guide](https://azreborn.com/guides/progression-and-cosmetics). Public balance data are pinned to `21071e86fee66ca7`. Native contract inspection and offline content comparisons used Reborn 0.7.4. Live Dalaran selection fields, native tooltip rendering and frame timing remain game-verification items.
