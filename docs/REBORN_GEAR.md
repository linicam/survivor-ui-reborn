# Gear & Difficulty Analyzer

Enter the Campaign map and difficulty you want to use as a reference. Click the Survivor UI button beside the minimap, choose **Global → Open Gear & Difficulty**, then click **Set current map to 100%**. The map page reads the current run's map and tier from `AZS_ZONE`. Opening it in another map shows the new comparison automatically. If the snapshot is still pending, click **Refresh current map**. In the Dalaran Hub or in a run, choose an expansion, map and difficulty to preview the comparison without traveling to that map. Previewing leaves the saved reference intact. The map reference is shared across classes and defaults to Naxxramas Normal. This percentage uses standard Campaign enemy health factors.

`/sui gear` also opens the panel in the world. The character menu uses a separate Glue Lua environment and its AddOns menu manages addon enablement. The analyzer does not access the account save, invoke the native upgrade button, or send gameplay commands.

## Gear planner

The addon records the last valid native `AZSARMOR` snapshot per class in a campaign map. **Gear planner** in the Dalaran Hub shows the recorded time, up to six next-star gains ranked by added piece damage, and their available prices. The observation is local and contains only class, slot, tier, stars and time. It does not read the character menu's owned collection or the account's upgrade eligibility. Use **Load recorded gear** to fill an empty advanced planner for the selected preview map, or **Edit gear and prices** to enter your own loadout. Gear scenarios keep their own references.

### Prices

The November 16, 2026 armor price chart gives the gold base for target stars 1 through 5 as `408, 816, 1496, 2720, 4080`. These values already include the listed 15% reduction. A step costs the base times the quality factor, rounded to a whole gold. A multi-step upgrade adds the individually rounded steps. The chart distinguishes 34 in-game observations from six estimated cells. The planner labels price-table values and uses the same tier price for weapons based on the user-confirmed parity rule. Exotic, Elementium (native `star_factor = 7.6`), and Legendary's fifth star are labeled estimates and are excluded from the gold search unless a price is supplied. A manual quote overrides the chart. A disagreement also stops automatic continuation for that piece. Check the current price and upgrade eligibility in the native Gear window before spending.

The first field is `class map tier background% [slot]`. For example, `warlock naxx 0 0 main_hand` represents Warlock, Naxxramas Normal, an illustrative zero non-gear addition, and a preview restricted to the main hand. Enter Heroic I through V as 1–5. `/sui gear keys` lists zone and slot keys.

Enter one line per known piece as `slot quality stars worn|owned|farm [next-price,next-price,...]`. The prices below are syntax examples, not game prices.

```text
main_hand rare 2 worn 100,200,300
main_hand epic 1 owned 120,180
main_hand legendary 0 farm
head rare 1 worn
```

- `worn` is the currently equipped piece. Include every worn part whose stats should be counted.
- `owned` is an alternative you own, with its current stars.
- `farm` declares a legal, verified drop for this class, slot, and progression. It starts at zero stars with no acquisition gold. If the slot is occupied, its quality must be above the worn piece.
- Enter prices as consecutive steps starting with the next star. The planner can fill consecutive steps covered by the chart or weapon parity. Existing stars are sunk cost. An unpriced or estimate-only star is excluded from the search. The Gear preview can still show its attribute change, including three- and five-star previews when a slot is specified.

Choose **Save gear setup** on the reference map and loadout before editing the target fields. Gear scenario references are stored per class with gear rows, attributes, active sets, map and tier, model version, and fixed background. Changing the background, reference map multiplier, or relevant native gear values invalidates the gear calculation. View with `/sui gear reference`. With a blank loadout, **Compare gear** shows the entered map scale alone.

## Models and controls

The map uses the map health factor and standard Campaign health-tier factor, relative to the reference, or Naxxramas Normal when no reference is applicable. The optional damage-only scenario divides this ratio by `(1 + fixed background + current listed damage) / (1 + fixed background + reference listed damage)`. These are model inputs, not a verified engine damage stack or a win probability. Spawn rates, opening enemy composition, mitigation, cooldown, critical hits, Echo, special mechanics and set combat benefits are outside the ratio.

Piece attributes come from runtime `AZS_GEN.pieces` and `AZS_GEN.gearTiers`. Fractions are shown as percentage changes and HP/regen as flat changes. Pre-rounding attributes are shown. Four- and eight-piece activation, class-specific selection, and five-star empowerment follow `AZS_GEN.setRules` and `AZS_GEN.setBonuses`. Weapon slots do not count. The planner shows actual set gains and losses separately. Unknown effects may change the best choice.

**Stars Only** keeps worn qualities. **Farm & Upgrade** includes the declared alternatives. The solver finds the cheapest listed plan under the scalar damage-only objective using a Pareto frontier. At the same cost the higher modeled damage wins, then fewer changes. When the target is out of reach it returns the highest listed damage and lowest associated cost. It preserves current gear when it already meets the scenario. If the Farm & Upgrade plan would remove a currently active set threshold, a second search preserves those thresholds. It partitions the frontier by capped set counts, so a partial choice is only pruned against another with the same set progress. New set effects may still activate. Each search crossing 24,000 evaluations returns an explicit limit. Suggested sequence is by immediate piece-damage gain per gold. Inspect set changes before changing several pieces. Prices, collection coverage and drop eligibility are supplied by the player, so this is not an account-wide optimum.

`/sui gear off` closes the panel. `/sui gear toggle difficulty|preview|planner|worn|diagnostics` switches independent features. Worn recording consumes the native equipment event and stops when disabled or when both preview and planner are off. The module creates no frame until opened and adds no poller. Diagnostics defaults off. To record a declared snapshot, enable diagnostics, start `/sui reborn record start`, then use `/sui gear capture`. Stop recording and reload before exporting if needed. Changing or typing values clears the displayed analysis. Planner calculation runs only by explicit request.

Sources: [Public Data API](https://azreborn.com/guides/data-api), [Content reference](https://azreborn.com/guides/content-reference#28-gear-pieces), [Addon API](https://azreborn.com/guides/addon-api), [Progression guide](https://azreborn.com/guides/progression-and-cosmetics). The map reference is pinned to public content revision `21071e86fee66ca7`. Local validation used native 0.7.4 generated gear data without shipping it.
