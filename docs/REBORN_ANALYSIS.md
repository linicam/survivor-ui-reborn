# Reborn analysis

Open SurvivorUI Options → Level Up! → Reborn analysis. The master switch is off on fresh and existing configurations. Enabling it shows Card values, Campaign pressure reference, and Live Build observations unless those switches were turned off individually. Experimental growth advice is off by default. Research diagnostics is independent of the master switch and requires an active Reborn recording.

## Output

- **Card values** are appended to supported native offers. A matching, already learned skill can show the server's damage bonus preview, an ideal cooldown, and an ideal contribution to current DPS. The last number uses a recent native meter window and exact ability attribution. It assumes unchanged target supply, cast availability, and no indirect effects. Unsupported lines can keep a partial preview but cannot yield a complete DPS estimate.
- **Jewelry previews** preserve native before and after values and show the displayed item's difference for supported numeric lines. A known capped stat can show its remaining character-wide headroom. A piece's difference is not a character-wide stat delta. Replacements with incomplete information keep the game's comparison. Set bonuses, proc uptime, pet damage, and modifier stacking are not inferred.
- **Campaign pressure** is on the existing run tracker header tooltip. Public zone factors and first/final boss templates are compared with Naxxramas Normal. Standard Campaign difficulty factors are taken from 0.7.4. The reference does not model optional challenges, affixes, extra creatures, boss scripts, clock-dependent scaling, or alternate modes.
- **Live Build observations** add sampled low health, enemy count, kills, damage taken, growth, and a recent effective DPS window when available. Boss HP loss is a net change of one identifiable boss. A window crossing a known boss/zone boundary is withheld. Build snapshots do not expose exact spawn health, cooldown downtime, effective shields, or a complete overkill breakdown.
- **Experimental advice** uses repeated low-health or rising-enemy observations. It may suggest a known mitigation option or the leading comparable direct output option. It withholds ties and unsupported choices. Disabling the Card values display leaves the model callable by the advisor.

## Implementation and verification

`RebornAnalysisModel.lua` owns pure parsing, formulas, sample summaries, and optional direction selection. `RebornAnalysis.lua` reads the native feeds and owns per-run sampling, per-hand caching, and the optional diagnostic alignment. CardsNotice appends text using the existing card Fit integration. Tracker adds observations to its header tooltip. Existing RebornCompat cap handling remains independent. The modules never send commands, bind selection keys, or modify the underlying hand.

The run sampler responds to native `AZSRUN` with at most seven samples per window, one every five gameplay seconds plus a segment transition. The native meter is queried on eligible hands, on tracker hover, and at a few points during opt-in diagnostics. In the fully disabled state the new handlers return before processing state or requesting snapshots. The card UI only reflows when displayed text changes. Loading the map reference does not perform a network request.

The generated map reference can be reproduced with `python3 scripts/generate_reborn_maps.py <zones.json> SurvivorUI/RebornMapReference.lua`. Use the [public Data API](https://azreborn.com/guides/data-api) and check the content revision before changing it. The installed client, extracted executable contents, and raw captures are outside this repository.

## Recording

Enable **Research diagnostics** and start the existing recorder with `/sui reborn record start`. Normal interactions already record original offers, native tips, gear changes and selection intent. The analysis adds a run sample, a hand number and model snapshot, a pre-pick state, and an observed-change or unconfirmed result. When a selection is corroborated and enough time elapses before another pick, an additional window is recorded. A superseded pick or unavailable window is expected when several choices are made close together. Rank or jewelry evidence can corroborate a pick. It does not prove that all changes in a following window were caused by the pick.

Stop with `/sui reborn record stop`, then use `/reload` to persist the recording. Existing session budgets and export tooling apply. Keep full captures private. After converting with `scripts/replay_session.py`, use only sanitized, representative observations with explicit assertions in checked-in fixtures. See [official Addon API](https://azreborn.com/guides/addon-api) for meter periods, current snapshots, and field units.
