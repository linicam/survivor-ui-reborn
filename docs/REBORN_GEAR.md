# Gear & Difficulty Analyzer

Select the class, equipment, Campaign map and difficulty in the hero menu, then enter Dalaran mode. Open **Survivor UI → Global → Open Gear & Difficulty** or use `/sui gear` in the world. The native character window's **Upgrades** button opens the same planner. Hover an equipped slot there for its next-star and next-tier previews.

Use **Set Current Configuration as 100% Baseline** once on a familiar configuration for each class. The addon stores the actual map, tier, reported modifiers, equipped item identities, model inputs, active sets, game/data version and time. A later selection leaves the baseline in place until you explicitly replace it. Legacy map references and cached gear are left on disk for compatibility. They are excluded from the live analysis. Incompatible baselines remain stored and the UI explains when a new reference is needed.

The two tabs share the same calculation. **Difficulty & Upgrade Planner** displays early output and survival pressure plus both upgrade plans. **Equipment Simulator** starts from actual gear. Change the tier and stars of supported slots, load either completed plan, or reset to actual gear. The plan and simulator change local previews only.

## Data contracts

- `AZSZONE` supplies the world selection, class, `dt`, `heroic`, and reported modifiers. A known Campaign map and consistent difficulty are required for comparison. The module uses the selected map reported in this world context. A Dalaran-only key cannot identify the selected Campaign map. It has no fallback to a historical run.
- The native addon requests `sync` on world entry. `AZSARMOR` supplies the list of equipped items after `AZSZONE`, including slot, rarity, stars and the native item description fields. An explicit empty list is valid. The currently installed `Units.lua` documents that a hero wearing no equipment may receive no list, which the addon treats as unavailable. A new world or change in run/selection invalidates the observation and cancels the previous search.
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

## Plans and gold

Plan A keeps the option to retain and upgrade worn pieces and includes replacement gear from the current expansion's Campaign drops. The public zone table and documented pair/override rule determine standard tiers. The native tier catalog and pack assignment identify the extra end-of-expansion tiers. A drop begins at zero stars for quoting. Replacement acquisition adds a separate gameplay requirement. Inventory ownership and its existing stars, direct ascension and slot-specific account progression are unavailable. Plan B upgrades only the same items and tiers. The player balance does not restrict either search.

A step to stars one through five costs `round(408 | 816 | 1496 | 2720 | 4080 × tier factor)`, rounded per step. The November 16, 2026 price chart's reduction is already in those base prices. Weapons use the same factors. Exotic, Elementium and Legendary's fifth star include formula-derived estimates. If a native factor differs from the verified schedule, the analyzer omits the unknown quote from the solver and indicates that the candidate was excluded. Gold shown for a replacement is the calculable amount spent on stars. No downgrade refund is assumed.

The search uses bounded depth-first enumeration with nonnegative price bounds, optimistic suffix capacity bounds and active set threshold bounds. The all-stars known worn configuration seeds the search. The best feasible result minimizes calculable gold among the applicable candidates. If that is impossible within a completed search, it minimizes remaining pressure then gold. Equal candidates keep the deterministic first result, with slots in native order and choices by cost, tier rank and stars after the seed. The bound can combine per-stat maxima from incompatible choices, which is safe because it only improves the optimistic result. Current supported quantified set effects change neither objective component. Unpriced choices, account-specific paths and unquantified combat effects limit what a completed result proves. A search stopped at its node budget displays the best found and whether it reaches 100%, with no claim of optimum or infeasibility. The UI suspends work off the planner tab and releases unfinished results when it closes.

The native tooltip extension post-hooks `AZSInspect:RefreshDoll` and the slot's existing `OnEnter` using `hooksecurefunc` and `HookScript`. It appends after the host has set the tooltip owner and validates that the slot matches this world's equipped item. Native `OnLeave` closes the tooltip. Simulator and plan icons also expose the preview. The preview evaluates isolated changes and performs no combination search.

Sources: [Addon API](https://azreborn.com/guides/addon-api), [Content reference](https://azreborn.com/guides/content-reference), [Data API](https://azreborn.com/guides/data-api), [Progression guide](https://azreborn.com/guides/progression-and-cosmetics). Public balance data are pinned to `21071e86fee66ca7`. Native contract inspection and offline content comparisons used Reborn 0.7.4. Live Dalaran selection fields, native tooltip rendering and frame timing remain game-verification items.
