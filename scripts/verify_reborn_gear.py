"""Compare gear attributes and benchmark a checkout with external Reborn data."""

import argparse
import csv
from pathlib import Path
from statistics import median
from time import perf_counter, process_time

from lupa import lua51


def verify(lua, expected):
    """Compare three independently extracted values for each CSV row."""
    catalog = lua.globals().SurvivorUI_RebornGearModel
    native = catalog.Catalog(lua.globals().AZS_GEN)
    slots = ("head", "shoulders", "chest", "waist", "legs", "feet", "wrists", "hands")
    with expected.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))[1:]
    assert rows, "reference CSV has no data"
    for tier, stars, _, _, _, weapon, hp, damage, *_ in rows:
        main = catalog.Piece(native, "warlock", "main_hand", tier, int(stars))
        armor = [catalog.Piece(native, "warlock", slot, tier, int(stars)) for slot in slots]
        actual = (100 * main["damage"], sum(p["hp"] or 0 for p in armor),
                  100 * sum(p["damage"] or 0 for p in armor))
        for value, reference in zip(actual, (weapon, hp, damage)):
            assert abs(value - float(reference)) <= 0.00051, (tier, stars, value, reference)
    print(f"Matched {len(rows)} tier/star rows, three independent comparisons per row.")


SCENARIOS = """
local P, G = SurvivorUI_RebornGearPlanner, SurvivorUI_RebornGearModel
local M, maps = SurvivorUI_RebornAnalysisModel, SurvivorUI_RebornMapReference
local cat = assert(G.Catalog(AZS_GEN))
local function Scenario(class, map, level)
    local pieces, context = {}, { class = class, zone = "naxx", level = 0, demand = M.GearDemand(maps.naxx, 0) }
    for i = 0, 8 do
        pieces[i + 1] = { slot = cat.pieces.slots[i].key, tier = "legendary", stars = 1 }
    end
    context.pieces = pieces
    local actual = assert(P.Evaluate(cat, class, pieces))
    local reference = assert(P.Reference(context, actual))
    local target = P.Copy(context)
    target.zone, target.level, target.demand = map, level, M.GearDemand(maps[map], level)
    local drops = assert(P.DropTiers(cat, maps, maps[map][7]))
    local function CheckConfiguration(result)
        local evaluation = assert(P.Evaluate(cat, class, result.pieces))
        local pressure = P.Difficulty(target.demand, evaluation, reference)
        local _, cost = P.Changes(cat, pieces, result.pieces, drops, class)
        -- Earlier source archives used a combined-pressure objective.
        local reported, recalculated = result.outputPressure or result.after,
            result.outputPressure and pressure.output or pressure.combined
        assert(math.abs(recalculated - reported) < P.tolerance and cost.gold == result.gold)
    end
    local function Check(result)
        CheckConfiguration(result)
        if result.maxGear then CheckConfiguration(result.maxGear) end
    end
    return {
        solve = function(allowed) return P.Search(cat, target, actual, reference, allowed and drops, 150000) end,
        check = Check, step = P.Step,
    }
end
return Scenario
"""

RECORDED = """
local P, G = SurvivorUI_RebornGearPlanner, SurvivorUI_RebornGearModel
local M, maps = SurvivorUI_RebornAnalysisModel, SurvivorUI_RebornMapReference
local cat = assert(G.Catalog(AZS_GEN))
local context = { class = "warlock", zone = "naxx", level = 0, demand = M.GearDemand(maps.naxx, 0), pieces = {} }
local stars = { 1, 1, 0, 0, 0, 0, 1, 1, 0 }
for i, level in ipairs(stars) do
    context.pieces[i] = { slot = cat.pieces.slots[i - 1].key, tier = i == 9 and "exotic" or "legendary", stars = level }
end
local actual = assert(P.Evaluate(cat, context.class, context.pieces))
local reference = assert(P.Reference(context, actual))
context.zone, context.level = "shadowmoon", 1
context.demand = M.GearDemand(maps[context.zone], context.level)
local allowed = assert(P.DropTiers(cat, maps, maps[context.zone][7]))
local expected = {
    A = { { 332.2927, 165, 165648 }, { 332.2927, 115.2099, 447498 } },
    B = { { 338.4984, 165, 142802 }, { 338.4984, 118.0221, 398052 } }
}
local function Check(result, drops, row)
    local evaluation = P.Evaluate(cat, context.class, result.pieces)
    local pressure = P.Difficulty(context.demand, evaluation, reference)
    local _, quote = P.Changes(cat, context.pieces, result.pieces, drops, context.class)
    assert(math.abs(pressure.output - result.outputPressure) < P.tolerance and quote.gold == result.gold)
    if row then
        assert(math.abs(pressure.output - row[1]) < 0.00005 and math.abs(pressure.survival - row[2]) < 0.00005
            and result.gold == row[3])
    end
end
return function(mode, target, budget)
    local drops = mode == "A" and allowed or nil
    local policy = P.Policy and P.Policy({ target = target, budget = budget })
    local start = BenchmarkClock()
    local result = P.Search(cat, context, actual, reference, drops, 150000, policy)
    local updates = 0
    while result.worker do P.Step(result, 240); updates = updates + 1 end
    local elapsed = 1000 * (BenchmarkClock() - start)
    assert(not result.error, result.error)
    local chosen = result.affordable or result
    Check(result, drops, target == 100 and expected[mode][1] or nil)
    Check(chosen, drops)
    if target == 100 then
        Check(result.maxGear, drops, expected[mode][2])
        assert(result.complete and result.unreachable)
        if P.Execution then
            local sequence = P.Execution(cat, context, actual, result.maxGear.pieces, reference, drops)
            assert(sequence.preserves and sequence.gold == result.maxGear.gold)
            for _, step in ipairs(sequence.steps) do
                assert(step.afterSets.legendary and step.afterSets.legendary[1].pieces == 4)
            end
            local final = P.BySlot(sequence.pieces)
            for _, piece in ipairs(result.maxGear.pieces) do assert(P.SamePiece(piece, final[piece.slot])) end
        end
    end
    if budget then assert(chosen.gold <= budget) end
    if target == 410 then assert(chosen.gold == 0 and result.minimumTargetCost == 0) end
    return result.visited, result.affordable and result.affordable.visited or 0, updates, chosen.outputPressure,
        chosen.gold, result.minimumTargetCost, result.complete, chosen.complete, elapsed
end
"""


def recorded_benchmark(lua, repeat):
    lua.globals().BenchmarkClock = perf_counter
    run = lua.execute(RECORDED)
    has_budget = lua.globals().SurvivorUI_RebornGearPlanner.Policy is not None
    for mode in ("A", "B"):
        cases = [(100, None)]
        if has_budget:
            cost = run(mode, 370, None)[5]
            assert cost and cost > 0
            cases += [(370, cost), (370, cost - 1), (100, 60000), (100, 0), (410, 60000)]
        for target, budget in cases:
            results = [run(mode, target, budget) for _ in range(repeat)]
            nodes, budget_nodes, updates, output, spent, minimum, complete, budget_complete, _ = results[0]
            assert all(row[:-1] == results[0][:-1] for row in results)
            if target == 370 and budget == minimum:
                assert output <= target and spent == minimum
            if target == 370 and budget == minimum - 1:
                assert output > target
            print(f"recorded/{mode} target={target} budget={budget}: nodes={nodes}+{budget_nodes}, updates={updates}, "
                  f"output={output:.4f}%, gold={spent}, target cost={minimum}, complete={complete}/{budget_complete}, "
                  f"offline solver wall median={median(row[-1] for row in results):.3f} ms")


def benchmark(lua, repeat):
    scenario = lua.execute(SCENARIOS)
    print("Class / target / plan: nodes, updates, pressure, gold, reached, complete, CPU, setup, batch wall median/max")
    for key, level in (("shadowmoon", 3), ("terokkar", 0)):
        for cls in ("paladin", "warlock"):
            case = scenario(cls, key, level)
            for label, drops in (("A", True), ("B", None)):
                batches, setups, cpu_total = [], [], 0
                summary = None
                for _ in range(repeat):
                    cpu, start = process_time(), perf_counter()
                    result = case["solve"](drops)
                    setups.append(1000 * (perf_counter() - start))
                    updates = 0
                    while result["worker"]:
                        start = perf_counter()
                        case["step"](result, 240)
                        batches.append(1000 * (perf_counter() - start))
                        updates += 1
                    cpu_total += process_time() - cpu
                    assert not result["error"], result["error"]
                    case["check"](result)
                    max_gear = result["maxGear"]
                    row = (result["visited"], updates, result["outputPressure"] or result["after"], result["gold"],
                           bool(result["complete"]), bool(result["unreachable"]),
                           (max_gear["outputPressure"], max_gear["gold"]) if max_gear else None)
                    assert summary is None or summary == row, "search result changed between repetitions"
                    summary = row
                nodes, updates, pressure, gold, complete, unreachable, max_gear = summary
                print(f"{cls}/{key}-{level}/{label}: {nodes}, {updates}, {pressure:.3f}%, {gold}, "
                      f"{pressure <= 100}, {complete}, {1000 * cpu_total / repeat:.2f} ms, "
                      f"{median(setups):.3f} ms, {median(batches or [0]):.3f}/{max(batches or [0]):.3f} ms")
                if max_gear:
                    print(f"  Max Gear{' (reference)' if not unreachable else ''}: {max_gear[0]:.3f}%, {max_gear[1]} known gold")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-content", type=Path, required=True, help="trusted external Generated/Content.lua")
    parser.add_argument("--gear-csv", type=Path, help="optional independent extraction in the documented CSV format")
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="checkout or exported source revision to benchmark")
    parser.add_argument("--repeat", type=int, default=5, help="deterministic searches per sample for timing")
    parser.add_argument("--recorded", action="store_true", help="verify and benchmark the recorded Warlock loadout")
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be positive")
    lua = lua51.LuaRuntime()
    lua.execute(args.native_content.read_text(encoding="utf-8-sig"))
    for module in ("RebornAnalysisModel", "RebornMapReference", "RebornGearModel", "RebornGearPlanner"):
        lua.globals().dofile(str(args.source_root / "SurvivorUI" / f"{module}.lua"))
    if args.gear_csv:
        verify(lua, args.gear_csv)
    if args.recorded:
        recorded_benchmark(lua, args.repeat)
    else:
        benchmark(lua, args.repeat)


if __name__ == "__main__":
    main()
