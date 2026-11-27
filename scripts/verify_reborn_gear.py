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
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be positive")
    lua = lua51.LuaRuntime()
    lua.execute(args.native_content.read_text(encoding="utf-8-sig"))
    for module in ("RebornAnalysisModel", "RebornMapReference", "RebornGearModel", "RebornGearPlanner"):
        lua.globals().dofile(str(args.source_root / "SurvivorUI" / f"{module}.lua"))
    if args.gear_csv:
        verify(lua, args.gear_csv)
    benchmark(lua, args.repeat)


if __name__ == "__main__":
    main()
