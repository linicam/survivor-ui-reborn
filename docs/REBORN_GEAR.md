# Gear & Difficulty Analyzer

Open `/sui gear` in a Reborn hub or other non-combat world. The pre-world character menu uses a separate Glue Lua environment. The in-world fallback has its own read-only controls and never reads the last `AZS_ZONE` as a menu selection. It does not access the account save, invoke the native upgrade button, or send gameplay commands.

## Inputs

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
- Prices are consecutive incremental amounts from the next star. Existing stars are sunk cost. An unpriced star is excluded from the search. The Gear preview can still show that next star's attribute change.

Choose **Save 100%** on the reference map and loadout before editing the target fields. References are stored per class with gear rows, attributes, active sets, map and tier, model version, and fixed background. Changing the background, reference map multiplier, or relevant native gear values invalidates comparison. View with `/sui gear reference`. With a blank loadout, **Difficulty** shows the map scale alone.

## Models and controls

The map uses the map health factor and standard Campaign health-tier factor, relative to the reference, or Naxxramas Normal when no reference is applicable. The optional damage-only scenario divides this ratio by `(1 + fixed background + current listed damage) / (1 + fixed background + reference listed damage)`. These are model inputs, not a verified engine damage stack or a win probability. Spawn rates, opening enemy composition, mitigation, cooldown, critical hits, Echo, special mechanics and set combat benefits are outside the ratio.

Piece attributes come from runtime `AZS_GEN.pieces` and `AZS_GEN.gearTiers`. Fractions are shown as percentage changes and HP/regen as flat changes. Pre-rounding attributes are shown. Four- and eight-piece activation, class-specific selection, and five-star empowerment follow `AZS_GEN.setRules` and `AZS_GEN.setBonuses`. Weapon slots do not count. The planner shows actual set gains and losses separately. Unknown effects may change the best choice.

**Stars Only** keeps worn qualities. **Farm & Upgrade** includes the declared alternatives. The solver finds the cheapest listed plan under the scalar damage-only objective using a Pareto frontier. At the same cost the higher modeled damage wins, then fewer changes. When the target is out of reach it returns the highest listed damage and lowest associated cost. It preserves current gear when it already meets the scenario. A search crossing 24,000 combination evaluations returns an explicit limit. Suggested sequence is by immediate piece-damage gain per gold; inspect set changes before changing several pieces. Prices, collection coverage and drop eligibility are supplied by the player, so this is not an account-wide optimum.

`/sui gear off` closes the panel. `/sui gear toggle difficulty|preview|planner|diagnostics` switches independent features. The module creates no frame until opened and adds no poller or combat handler. Diagnostics defaults off. To record a declared snapshot, enable diagnostics, start `/sui reborn record start`, then use `/sui gear capture`. Stop recording and reload before exporting if needed. Changing or typing values clears the displayed analysis. Planner calculation runs only by explicit request.

Sources: [Public Data API](https://azreborn.com/guides/data-api), [Content reference](https://azreborn.com/guides/content-reference#28-gear-pieces), [Addon API](https://azreborn.com/guides/addon-api), [Progression guide](https://azreborn.com/guides/progression-and-cosmetics). The map reference is pinned to public content revision `21071e86fee66ca7`. Local validation used native 0.7.4 generated gear data without shipping it.
