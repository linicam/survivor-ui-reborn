# Reborn analysis

Open SurvivorUI Options → Level Up! → Reborn analysis. The master switch is off by default. It controls available card details and live observations. The 0.7.4 Campaign reference is archived. The random-equipment client withholds theoretical skill estimates and experimental mitigation recommendations. Research diagnostics is independent of the master switch and requires an active Reborn recording.

## Output

- **Card values** are appended to supported native offers. A matching, already learned skill can show the server's damage bonus preview and an ideal cooldown. A single matching native meter row can illustrate the hypothetical whole-build DPS increase if that entire row scales. The preview assumes unchanged target supply and cast availability. The native meter cannot separate every trigger from the skill row. Multiple matching rows and unsupported lines withhold this number.
- **Jewelry previews** preserve native before and after values and show the displayed item's difference for supported numeric lines. A known capped stat can show its remaining character-wide headroom. A piece's difference is not a character-wide stat delta. Replacements with incomplete information keep the game's comparison. Set bonuses, proc uptime, pet damage, and modifier stacking are not inferred.
- **Campaign pressure (historical)** compared static enemy and boss factors to Naxxramas Normal. The 0.7.4 reference remains in the repository for offline regressions.
- **Live Build observations** add sampled low health, enemy count, kills, damage taken, growth, and a recent effective DPS window when available. Boss HP loss is a net change of one identifiable boss. A window crossing a known boss/zone boundary is withheld. Build snapshots do not expose exact spawn health, cooldown downtime, effective shields, or a complete overkill breakdown.
- **Experimental advice** may suggest a single supported mitigation option during repeated low health with observed incoming damage. Enemy buildup appears as an observation. Unverified meter attribution is excluded from card ranking. Disabling the Card values display leaves the model callable by the advisor.

## Implementation and verification

`RebornAnalysisModel.lua` owns pure parsing, formulas, sample summaries, and optional direction selection. `RebornAnalysis.lua` reads the native feeds and owns per-run sampling, per-hand caching, and the optional diagnostic alignment. CardsNotice appends text using the existing card Fit integration. Tracker adds observations to its header tooltip. Existing RebornCompat cap handling remains independent. The modules never send commands, bind selection keys, or modify the underlying hand.

The run sampler responds to native `AZSRUN` with at most seven samples per window, one every five gameplay seconds plus a segment transition. The native meter is queried on eligible hands, on tracker hover, and at a few points during opt-in diagnostics. In the fully disabled state the new handlers return before processing state or requesting snapshots. The card UI only reflows when displayed text changes. Loading the map reference does not perform a network request.

The generated map reference can be reproduced with `python3 scripts/generate_reborn_maps.py <zones.json> SurvivorUI/RebornMapReference.lua`. The current public snapshot has content revision `21071e86fee66ca7`. Rank-card and tier constants were checked against the installed 0.7.4 configuration. The installed client, extracted executable contents, and raw captures are outside this repository. [Public Data API](https://azreborn.com/guides/data-api)

## Recording

Enable **Research diagnostics** and start the existing recorder with `/sui reborn record start`. Normal interactions already record original offers, native tips, gear changes and selection intent. The analysis adds a run sample, a hand number and model snapshot, a pre-pick state, and an observed-change or unconfirmed result. A later in-segment sample reports whether both meter windows existed. An encounter change or sampling gap interrupts the comparison, and a subsequent choice can supersede the current one. Rank or jewelry evidence can corroborate a pick. It does not prove that all changes in a following window were caused by the pick.

Stop with `/sui reborn record stop`, then use `/reload` to persist the recording. Existing session budgets and export tooling apply. Keep full captures private. After converting with `scripts/replay_session.py`, use only sanitized, representative observations with explicit assertions in checked-in fixtures. See [official Addon API](https://azreborn.com/guides/addon-api) for meter periods, current snapshots, and field units.
