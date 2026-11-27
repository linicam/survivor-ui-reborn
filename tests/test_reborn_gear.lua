-- Synthetic catalog and exhaustive checks for the read-only gear planner.
table.getn = table.getn or function(t) return #t end
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornMapReference.lua")
dofile("SurvivorUI/RebornGearModel.lua")
dofile("SurvivorUI/RebornGearPlanner.lua")
local G, P = SurvivorUI_RebornGearModel, SurvivorUI_RebornGearPlanner
local M = SurvivorUI_RebornAnalysisModel
local maps = SurvivorUI_RebornMapReference
local keys = { "head", "shoulders", "chest", "waist", "legs", "feet", "wrists", "hands", "main_hand", "off_hand", "ranged" }
AZS_GEN = {
	classes = { { key = "warlock", name = "Warlock", health = 165 }, { key = "paladin", name = "Paladin", health = 245 },
		{ key = "hunter", health = 200 }, { key = "rogue", health = 190 } },
	zones = {
		{ key = "naxx", name = "Naxxramas", world = 1 },
		{ key = "elwynn", name = "Elwynn Forest", world = 1 },
		{ key = "shadowmoon", name = "Shadowmoon Valley", world = 2 },
		{ key = "unmodeled", name = "Unmodeled", world = 2 },
	},
	pieces = {
		scale = { top = 5, steps = 4, factor = 0.7, slot = { 1, 1.7, 2.5, 3.5, 4.6, 4 },
			profile = { 0, 1, 1.6, 2.4, 3.4, 2.9 }, starStep = { 0.64, 0.4, 0.28, 0.17, 0.12, 0.15 },
			starLast = { 3.73, 1.85, 0.85, 0.42, 0.12, 0.22 } },
		slots = {}, classProfiles = { warlock = { 0, 0, 0, 0, 0, 0, 0, 0 }, paladin = { 0, 0, 0, 0, 0, 0, 0, 0 } },
		profiles = { [0] = { { "crit", 0.01 } } },
	},
	gearTiers = {
		{ key = "exotic", rank = 7, pair = 5, slot_scale = 5.6, profile_scale = 4.2, star_step = 0.1, star_last = 0.1, star_factor = 5.8 },
		{ key = "mythic", rank = 8, pair = 5, slot_scale = 6.4, profile_scale = 4.8, star_step = 0.1, star_last = 0.1, star_factor = 7.2 },
		{ key = "elementium", rank = 9, pair = 5, slot_scale = 7.4, profile_scale = 5.4, star_step = 0.1, star_last = 0.1, star_factor = 7.6 },
	},
	setRules = { pieces = { 4, 8 }, stars = { 1, 3 }, empowerStars = 5 },
	setBonuses = {
		{ class = "", rarity = 0, pieces = 4, text = "Pickup +{v}", v = { 12, 18 } },
		{ class = "warlock", rarity = 0, pieces = 8, text = "Hits {v}", v = { 2, 3 } },
	},
}
AZS_GEN.pieces.classProfiles.hunter = AZS_GEN.pieces.classProfiles.warlock
AZS_GEN.pieces.classProfiles.rogue = AZS_GEN.pieces.classProfiles.warlock
AZS_GEN.gearTiers[1].weapon_icons = { rogue = { "main" } }
AZS_GEN.gearTiers[2].weapon_icons = { rogue = { "main", "off" } }
for i, key in ipairs(keys) do
	AZS_GEN.pieces.slots[i - 1] = { key = key, profile = i <= 8, stats = { { "damage", i == 10 and 0.06 or 0.12 } } }
end
local cat = assert(G.Catalog(AZS_GEN))
local function near(a, b) assert(math.abs(a - b) < 0.0000001, tostring(a) .. " ~= " .. tostring(b)) end
local priceTable = {
	common = { 408, 816, 1496, 2720, 4080 }, uncommon = { 694, 1387, 2543, 4624, 6936 },
	rare = { 1020, 2040, 3740, 6800, 10200 }, epic = { 1428, 2856, 5236, 9520, 14280 },
	pvp = { 1632, 3264, 5984, 10880, 16320 }, legendary = { 1877, 3754, 6882, 12512, 18768 },
	exotic = { 2366, 4733, 8677, 15776, 23664 }, mythic = { 2938, 5875, 10771, 19584, 29376 },
	elementium = { 3101, 6202, 11370, 20672, 31008 },
}
local markedTotal, listedTotal = 0, 0
for tier, prices in pairs(priceTable) do
	for star, price in ipairs(prices) do
		local amount, source = G.StarQuote(cat, "head", tier, star)
		local weapon, weaponSource = G.StarQuote(cat, "main_hand", tier, star)
		local estimated = tier == "exotic" or tier == "elementium" or (tier == "legendary" and star == 5)
		assert(amount == price and weapon == price)
		assert(source == (estimated and "estimated" or "table"))
		assert(weaponSource == (estimated and "estimated" or "weapon"))
		if not estimated then markedTotal = markedTotal + amount end
		if tier ~= "elementium" then listedTotal = listedTotal + amount end
	end
end
assert(markedTotal * 8 == 1715784 and listedTotal * 8 == 2307656)
assert(not G.StarQuote(cat, "head", "rare", 0) and not G.StarQuote(cat, "head", "rare", 6))
cat.tiers.elementium.starFactor = 7.7
assert(not G.StarQuote(cat, "head", "elementium", 1), "a changed live multiplier invalidates the pinned price")
cat.tiers.elementium.starFactor = 7.6

local function Item(slot, tier, stars) return { slot = slot, tier = tier, stars = stars } end
local function Eval(pieces) return assert(P.Evaluate(cat, "warlock", pieces)) end
local source = { class = "warlock", zone = "naxx", level = 0, heroic = 0, build = "v0.7.4",
	modifiers = { aff = "2", affixes = "" }, demand = M.GearDemand(maps.naxx, 0), at = 100,
	pieces = { Item("head", "common", 0), Item("main_hand", "legendary", 0), Item("chest", "common", 1) } }
table.insert(AZS_GEN.pieces.slots[0].stats, { "hp", 30 })
table.insert(AZS_GEN.pieces.slots[2].stats, { "armor", 0.17 })
local actual = Eval(source.pieces)
local ref = assert(P.Reference(source, actual))
near(G.Piece(cat, "warlock", "main_hand", "common", 0).damage, 0.084)
near(G.Piece(cat, "warlock", "main_hand", "common", 5).damage, 0.61236)
near(G.Piece(cat, "warlock", "main_hand", "exotic", 0).damage, 0.4704)
assert(not G.Piece(cat, "warlock", "main_hand", "common", 6))
assert(not G.Worn(cat, "warlock", { { slot = 0, rarity = 0, stars = 0 }, { slot = 0, rarity = 1, stars = 1 } }))
local worn = assert(G.Worn(cat, "warlock", { { slot = "8", rarity = "7", stars = "2" },
	{ slot = 1, rarity = "" }, { slot = 0, rarity = 4, stars = 0, icon = "inv_test", name = "Test" } }))
assert(#worn == 2 and worn[1].icon == "inv_test" and worn[2].slot == "main_hand" and worn[2].tier == "mythic")
assert(P.Difficulty(source.demand, actual, ref).output == 100 and ref.pieces[1] ~= source.pieces[1])
local reconstructed, issue = P.CheckReference(ref, source, cat, maps)
assert(ref.modifiers ~= source.modifiers and reconstructed ~= ref and issue == nil and reconstructed.scope == "standard")
assert(P.Difficulty(source.demand, actual, reconstructed).output == 100)
assert(not P.CheckReference(ref, { class = "paladin", build = source.build }, cat, maps))
assert(P.CheckReference(ref, { class = "warlock", build = "changed" }, cat, maps))
assert(not P.CheckReference(P.Copy({ version = 1 }), source, cat, maps))
local legacy = P.Copy(ref)
legacy.schema, legacy.version, legacy.data = nil, 2, "older"
assert(P.CheckReference(legacy, source, cat, maps))
local priorVersion = P.Copy(ref)
priorVersion.version, priorVersion.combined = 3, 999
local previousOutput = assert(P.CheckReference(priorVersion, source, cat, maps))
assert(P.Difficulty(source.demand, actual, previousOutput).output == 100 and priorVersion.combined == 999)
local updated = P.Copy(ref)
updated.version, updated.data, updated.output = 900, "compatible new data", 1
local recomputed, warning = P.CheckReference(updated, source, cat, maps)
assert(recomputed.output == actual.output and warning == "updated" and updated.output == 1)
local changedMaps = P.Copy(maps)
changedMaps.naxx[1] = changedMaps.naxx[1] * 1.1
recomputed, warning = P.CheckReference(ref, source, cat, changedMaps)
assert(recomputed and warning == "updated" and recomputed.demand.output ~= ref.demand.output)
for _, field in ipairs({ "schema", "zone", "level", "pieces", "heroic", "modifiers" }) do
	local bad = P.Copy(ref)
	bad[field] = "invalid"
	assert(not P.CheckReference(bad, source, cat, maps), field)
end
local bad = P.Copy(ref)
bad.pieces = { [2] = Item("head", "common", 1) }
assert(not P.CheckReference(bad, source, cat, maps))
bad.pieces = { Item("off_hand", "common", 1) }
assert(not P.CheckReference(bad, source, cat, maps))
local modifiedRef = P.Copy(ref)
modifiedRef.modifiers.affixes = "explosive"
assert(P.CheckReference(modifiedRef, source, cat, maps).scope == "standard-only")
modifiedRef.modifiers.mode = "swarm"
assert(not P.CheckReference(modifiedRef, source, cat, maps))
assert(P.Scope(0, { aff = 1, affixes = " , ", challenge = "0" }) == "standard")
assert(P.Scope(3, {}) == "standard-only" and P.Scope(0, { affixes = "sanguine" }) == "standard-only")
assert(P.Affixes({ " Sanguine ", "explosive", "sanguine" }) == "explosive,sanguine")
local partial = P.Difficulty(M.GearDemand({ 2 }, 0), actual, ref)
assert(partial.output and not partial.survival and not partial.combined)
local noSurvival = P.Copy(source)
noSurvival.demand.survival = nil
local outputOnlyReference = assert(P.Reference(noSurvival, actual))
assert(P.Difficulty(source.demand, actual, outputOnlyReference).output == 100)
assert(not P.Difficulty(source.demand, actual, outputOnlyReference).survival)
local capped = Eval({ Item("chest", "common", 5) })
assert(capped.stats.armor > 0.6)
near(capped.survival, 165 / 0.4)

assert(P.DropTiers(cat, maps, 1).legendary and not P.DropTiers(cat, maps, 1).exotic)
assert(P.DropTiers(cat, maps, 2).exotic and not P.DropTiers(cat, maps, 2).common)
assert(P.DropTiers(cat, maps, 3).mythic and P.DropTiers(cat, maps, 4).elementium)
assert(G.ValidPiece(cat, "hunter", "ranged", "exotic", 1) and not G.ValidPiece(cat, "hunter", "main_hand", "exotic", 1))
assert(G.ValidPiece(cat, "rogue", "off_hand", "exotic", 1) and not G.DropSlot(cat, "rogue", "off_hand", "exotic"))
assert(G.DropSlot(cat, "rogue", "off_hand", "mythic") and G.DropSlot(cat, "rogue", "off_hand", "elementium"))
assert(not G.ValidSlot(cat, "paladin", "off_hand") and not G.ValidSlot(cat, "warlock", "ranged"))
assert(not G.Worn(cat, "paladin", { { slot = 9, rarity = 6, stars = 0 } }))
assert(not G.Worn(cat, "warlock", { [2] = { slot = 0, rarity = 0, stars = 0 } }))
assert(not G.ValidPiece(cat, "hunter", "ranged", "invented", 0) and not G.ValidPiece(cat, "hunter", "ranged", "exotic", 1.5))
local upgrade = P.Quote(cat, source.pieces[2], Item("main_hand", "exotic", 2), P.DropTiers(cat, maps, 2), "warlock")
assert(upgrade.kind == "farm" and upgrade.progression and upgrade.gold == 2366 + 4733 and upgrade.estimated)
assert(P.Quote(cat, source.pieces[2], Item("main_hand", "exotic", 0), P.DropTiers(cat, maps, 1)).kind == "theoretical")
assert(P.Quote(cat, Item("head", "common", 5), Item("head", "common", 2)).gold == 0)

local armor = {}
for i = 1, 8 do armor[i] = Item(keys[i], "common", 5) end
armor[9] = Item("main_hand", "common", 5)
local withSet = Eval(armor)
assert(withSet.sets.common[2].text == "Hits 3" and withSet.sets.common[2].strong)
armor[8].stars = 2
assert(#Eval(armor).sets.common == 1, "a weapon does not count towards the set")
armor[8].stars = 5
AZS_GEN.setBonuses[1].text, AZS_GEN.setBonuses[1].v2 = "+{v}% gold, +{v2}% pickup range", { 30, 45 }
AZS_GEN.setBonuses[1].follows = true
local empowered = Eval(armor)
near(empowered.stats.gold, 0.18)
near(empowered.stats.pickup, 0.45)
assert(#empowered.opaque.common == 1)

local function Finish(search)
	while search.worker do P.Step(search, 151) end
	assert(not search.error, search.error)
	return search
end

local easy = Finish(P.Search(cat, source, actual, ref, nil, 10000))
assert(easy.complete and easy.visited == 0 and easy.outputPressure == 100 and easy.gold == 0)

-- An HP-only armor slot cannot force purchases even if survival pressure
-- exceeds 100%. Max Gear still includes its complete legal star growth.
local headStats = AZS_GEN.pieces.slots[0].stats
AZS_GEN.pieces.slots[0].stats = { { "hp", 40 } }
local outputCase = P.Copy(source)
outputCase.pieces = { Item("head", "legendary", 1), Item("main_hand", "common", 0) }
local outputActual = Eval(outputCase.pieces)
local outputRef = assert(P.Reference(outputCase, outputActual))
local function RunOutput(factor, survival, limit)
	outputCase.demand = { output = outputRef.demand.output * factor, survival = outputRef.demand.survival * survival }
	return Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, limit or 5000))
end
local outputMet = RunOutput(0.95, 3)
assert(outputMet.complete and outputMet.gold == 0 and outputMet.visited == 0 and not outputMet.maxGear)
assert(P.Difficulty(outputCase.demand, outputActual, outputRef).survival > 100)
local cheapest = RunOutput(1.04, 3)
local cheapestPeace = RunOutput(1.04, 0.8)
assert(cheapest.complete and cheapest.gold == 408 and cheapest.outputPressure <= 100)
assert(cheapestPeace.gold == cheapest.gold and cheapestPeace.outputPressure == cheapest.outputPressure)
assert(P.BySlot(cheapest.pieces).head.stars == 1 and P.BySlot(cheapest.pieces).main_hand.stars == 1)
local hardOutput = RunOutput(4, 0.8)
assert(hardOutput.complete and hardOutput.unreachable and hardOutput.maxGear and hardOutput.outputPressure > 100)
assert(P.BySlot(hardOutput.pieces).head.stars == 1 and #hardOutput.maxGear.pieces == 2)
assert(P.BySlot(hardOutput.maxGear.pieces).main_hand.tier == "common")
for _, piece in ipairs(hardOutput.maxGear.pieces) do assert(piece.stars == 5) end
local econ, maxGear = Eval(hardOutput.pieces), Eval(hardOutput.maxGear.pieces)
near(econ.output, maxGear.output)
assert(maxGear.survival > econ.survival and maxGear.stats.hp > econ.stats.hp)
assert(hardOutput.maxGear.gold > hardOutput.gold)
local partialSearch = RunOutput(4, 0.8, 1)
assert(not partialSearch.complete and not partialSearch.unreachable and partialSearch.maxGear)
local savedStarFactor = cat.tiers.common.starFactor
cat.tiers.common.starFactor = 7.7
local unknown = RunOutput(1.04, 3)
local _, unknownQuote = P.Changes(cat, outputCase.pieces, unknown.maxGear.pieces, nil, outputCase.class)
assert(unknown.complete and unknown.excluded and not unknown.unreachable and unknown.verifiedBestOutputPressure <= 100)
assert(unknownQuote.unknown and unknown.maxGear.gold == unknownQuote.gold)
assert(RunOutput(4, 3).unreachable, "even known unpriced paths cannot reach this output target")
do
	local unpricedBudget = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 5000, P.Policy({ budget = 20000 })))
	assert(unpricedBudget.excluded and unpricedBudget.unreachable and unpricedBudget.affordable.gold == 0)
	cat.tiers.common.starFactor = savedStarFactor
	assert(P.Policy({}).target == 100 and P.Policy({}).protectSets and P.Policy({}).budget == nil)
	assert(P.Policy({ budget = 0 }).budget == 0 and P.Policy({ protectSets = false }).protectSets == false)
	assert(P.Policy({ target = math.huge, budget = -1 }).target == 100 and P.Policy({ budget = 0.1 }).budget == nil)
	outputCase.demand = { output = outputRef.demand.output * 1.04, survival = outputRef.demand.survival * 3 }
	for _, budget in ipairs({ 0, 407, 408, 409, 20000 }) do
		local solved = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 5000, P.Policy({ budget = budget })))
		local chosen = solved.affordable or solved
		assert(solved.minimumTargetCost == 408 and solved.complete and chosen.complete)
		assert(chosen.gold == (budget < 408 and 0 or 408) and (chosen.outputPressure <= 100) == (budget >= 408))
	end
	local meets = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 5000, P.Policy({ budget = 20000, target = 150 })))
	assert(meets.minimumTargetCost == 0 and meets.gold == 0 and meets.maxGear.gold > 0)
	for _, target in ipairs({ 60, 100 }) do
		local truncated = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 1, P.Policy({ budget = 9520, target = target })))
		assert(not truncated.complete and not truncated.unreachable and not truncated.affordable.complete)
		assert(truncated.visited == 1 and truncated.affordable.visited == 1 and truncated.minimumTargetCost == nil)
		assert(truncated.gold == 9520 and truncated.outputPressure < 104)
		assert((truncated.outputPressure <= target) == (target == 100))
		assert(truncated.affordable.gold == truncated.gold and truncated.affordable.outputPressure == truncated.outputPressure,
			"R25: both cutoffs must retain the feasible seed already scored by the unrestricted pass")
	end
	local upgraded = { outputCase.pieces[1], Item("main_hand", "common", 1) }
	local exactTarget = P.Difficulty(outputCase.demand, Eval(upgraded), outputRef).output
	local scored = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 4,
		P.Policy({ budget = 9520, target = exactTarget })))
	assert(scored.gold == 408 and scored.outputPressure == exactTarget and scored.affordable.gold == 408)
	assert(not scored.complete and not scored.affordable.complete and scored.minimumTargetCost == nil)
	local overBudget = Finish(P.Search(cat, outputCase, outputActual, outputRef, nil, 1, P.Policy({ budget = 1200, target = 80 })))
	assert(not overBudget.complete and not overBudget.affordable.complete and overBudget.affordable.gold <= 1200)
end
AZS_GEN.pieces.slots[0].stats = headStats

-- Two upgradeable slots. Independently price and evaluate each end state at
-- the 100% display snap, where different raw damage can give equal output.
local function OraclePressureSnap()
	local main = AZS_GEN.pieces.slots[8]
	local beforeMain, beforeHead = main.stats, AZS_GEN.pieces.slots[0].stats
	local common = cat.tiers.common
	local step, last = common.step, common.last
	common.step, common.last = 0.1, 0
	main.stats, AZS_GEN.pieces.slots[0].stats = { { "damage", 2e-7 } }, { { "damage", 1e-7 } }
	local context = P.Copy(source)
	context.pieces = { Item("head", "common", 0), Item("main_hand", "common", 3) }
	local actualGear = Eval(context.pieces)
	local reference = P.Reference(context, actualGear)
	context.demand.output = reference.demand.output * (1 + 1.65e-8)
	local bestGold, bestPressure
	for head = 0, 5 do
		for weapon = 3, 5 do
			local gold = 0
			for star = 1, head do gold = gold + priceTable.common[star] end
			for star = 4, weapon do gold = gold + priceTable.common[star] end
			if gold <= 2720 then
				local pressure = P.Difficulty(context.demand, Eval({ Item("head", "common", head),
					Item("main_hand", "common", weapon) }), reference).output
				if not bestPressure or pressure < bestPressure or (pressure == bestPressure and gold < bestGold) then
					bestGold, bestPressure = gold, pressure
				end
			end
		end
	end
	local solved = Finish(P.Search(cat, context, actualGear, reference, nil, 5000, P.Policy({ target = 99, budget = 2720 })))
	assert(bestPressure == 100 and bestGold == 408)
	assert(solved.affordable.complete and solved.affordable.outputPressure == bestPressure and solved.affordable.gold == bestGold,
		"the budget bound must retain cheaper configurations tied at the snapped pressure")
	common.step, common.last = step, last
	main.stats, AZS_GEN.pieces.slots[0].stats = beforeMain, beforeHead
end
OraclePressureSnap()

-- Independent exhaustive oracle: every available star combination is evaluated
-- with the public full-configuration evaluator, then ordered by the contract.
local function Oracle(context)
	local best, equipment = nil, {}
	local function Visit(i, gold)
		local item = context.pieces[i]
		if item then
			for star = item.stars, 5 do
				equipment[i] = Item(item.slot, item.tier, star)
				local additional = 0
				for step = item.stars + 1, star do additional = additional + G.StarQuote(cat, item.slot, item.tier, step) end
				Visit(i + 1, gold + additional)
			end
			return
		end
		local distance = P.Difficulty(context.demand, Eval(equipment), ref).output
		local reached = distance <= 100
		if not best or (reached and not best.reached)
			or (reached and best.reached and gold < best.gold)
			or (not reached and not best.reached and (distance < best.outputPressure - P.tolerance
				or (math.abs(distance - best.outputPressure) <= P.tolerance and gold < best.gold))) then
			best = { outputPressure = distance, gold = gold, reached = reached }
		end
	end
	Visit(1, 0)
	return best
end
math.randomseed(8245)
for i = 1, 80 do
	local context = P.Copy(source)
	context.demand.output = ref.demand.output * (1 + math.random(1, 210) / 100)
	context.demand.survival = ref.demand.survival * (1 + math.random(1, 210) / 100)
	local expected = Oracle(context)
	local got = Finish(P.Search(cat, context, actual, ref, nil, 5000))
	assert(got.complete and got.gold == expected.gold and (got.outputPressure <= 100) == expected.reached)
	near(got.outputPressure, P.Difficulty(context.demand, Eval(got.pieces), ref).output)
	if not expected.reached then near(got.outputPressure, expected.outputPressure) end
end

local hard = P.Copy(source)
hard.demand = M.GearDemand(maps.naxx, 5)
local limited = Finish(P.Search(cat, hard, actual, ref, nil, 1))
assert(not limited.complete and limited.visited == 1 and limited.outputPressure > 100)
local deadline = P.Search(cat, hard, actual, ref, nil, 5000)
P.Step(deadline, 10, function() return true end)
assert(deadline.visited == 0)

local protected = P.Copy(hard)
protected.pieces = armor
local preserves = Finish(P.Search(cat, protected, empowered, ref, { exotic = true }, 12000, P.Policy({})))
assert(preserves.complete and Eval(preserves.pieces).sets.common[2].strong)
do
	local sequence = P.Execution(cat, protected, empowered, preserves.maxGear.pieces, ref, { exotic = true })
	assert(sequence.preserves and #sequence.steps > 0 and sequence.gold == preserves.maxGear.gold)
	for _, step in ipairs(sequence.steps) do assert(step.afterSets.common[2].strong) end
end

local savedTop = cat.pieces.scale.top
cat.pieces.scale.top = 0
local farming = P.Copy(source)
farming.pieces = { Item("head", "common", 0), Item("main_hand", "common", 0) }
local farmingActual = Eval(farming.pieces)
local farmingReference = assert(P.Reference(farming, farmingActual))
farming.demand = { output = farming.demand.output * 1.2, survival = farming.demand.survival * 1.2 }
local stars = Finish(P.Search(cat, farming, farmingActual, farmingReference, nil, 2000))
local drops = Finish(P.Search(cat, farming, farmingActual, farmingReference, { exotic = true }, 2000))
local _, acquisition = P.Changes(cat, farming.pieces, drops.pieces, { exotic = true }, "warlock")
assert(stars.complete and stars.outputPressure > 100 and drops.complete and drops.outputPressure <= 100 and drops.gold == 0 and acquisition.acquisition)
do
	local fallback = Finish(P.Search(cat, farming, farmingActual, farmingReference, { exotic = true }, 1,
		P.Policy({ budget = 0 })))
	local _, quote = P.Changes(cat, farming.pieces, fallback.affordable.pieces, { exotic = true }, "warlock")
	assert(not fallback.complete and not fallback.affordable.complete and not fallback.minimumTargetCost)
	assert(fallback.affordable.gold == 0 and fallback.affordable.outputPressure <= 100 and quote.acquisition and not quote.unknown)
end

-- Oracle for a mixed-tier plan. Use one reachable and one unreachable target,
-- with a four-piece combat effect protected and different HP/armor choices.
cat.pieces.scale.top = 1
table.insert(AZS_GEN.setBonuses, { class = "", rarity = 4, pieces = 4, text = "Conditional damage" })
local mixed = P.Copy(source)
mixed.pieces = {}
for i = 1, 9 do mixed.pieces[i] = Item(keys[i], i <= 4 and "legendary" or "common", 1) end
local mixedActual = Eval(mixed.pieces)
local mixedRef = assert(P.Reference(mixed, mixedActual))
local candidate = {}
for _, factor in ipairs({ 1.08, 1.8 }) do
	mixed.demand = { output = mixedRef.demand.output * factor, survival = mixedRef.demand.survival * factor }
	local expected
	local function Enumerate(i, gold)
		local item = mixed.pieces[i]
		if item then
			candidate[i] = item
			Enumerate(i + 1, gold)
			-- Changing one of the first four pieces would lose the protected set.
			if i > 4 then
				candidate[i] = Item(item.slot, "exotic", 0)
				Enumerate(i + 1, gold)
				candidate[i] = Item(item.slot, "exotic", 1)
				Enumerate(i + 1, gold + 2366)
			end
			return
		end
		local difficulty = P.Difficulty(mixed.demand, Eval(candidate), mixedRef).output
		local reached = difficulty <= 100
		if not expected or (reached and not expected.reached) or (reached and expected.reached and gold < expected.gold)
			or (not reached and not expected.reached and (difficulty < expected.outputPressure - P.tolerance
				or (math.abs(difficulty - expected.outputPressure) <= P.tolerance and gold < expected.gold))) then
			expected = { outputPressure = difficulty, gold = gold, reached = reached }
		end
	end
	Enumerate(1, 0)
	local first = Finish(P.Search(cat, mixed, mixedActual, mixedRef, { exotic = true }, 12000))
	local second = Finish(P.Search(cat, mixed, mixedActual, mixedRef, { exotic = true }, 12000))
	assert(first.complete and first.gold == expected.gold and (first.outputPressure <= 100) == expected.reached)
	assert(first.outputPressure == second.outputPressure and first.gold == second.gold and #first.pieces == #second.pieces)
	for i, piece in ipairs(first.pieces) do assert(P.SamePiece(piece, second.pieces[i])) end
	if not expected.reached then near(first.outputPressure, expected.outputPressure) end
	assert(Eval(first.pieces).sets.legendary[1].pieces == 4)
end
local knownText = AZS_GEN.setBonuses[1].text
AZS_GEN.setBonuses[1].text = "Unquantified combat"
local twoSets = Eval(mixed.pieces)
local twoSetsRef = assert(P.Reference(mixed, twoSets))
mixed.demand.output = twoSetsRef.demand.output * 10
local bothProtected = Finish(P.Search(cat, mixed, twoSets, twoSetsRef, { exotic = true }, 12000))
assert(bothProtected.complete)
local kept = Eval(bothProtected.pieces).sets
assert(kept.legendary[1].pieces == 4 and kept.common[1].pieces == 4, "both competing protected tiers survive")
assert(bothProtected.unreachable and bothProtected.maxGear.protectedHolds == 8)
local maxSets = Eval(bothProtected.maxGear.pieces).sets
assert(maxSets.legendary[1].pieces == 4 and maxSets.common[1].pieces == 4)
do
	local sequence = P.Execution(cat, mixed, twoSets, bothProtected.maxGear.pieces, twoSetsRef, { exotic = true })
	assert(sequence.preserves and #sequence.steps > 0 and sequence.gold == bothProtected.maxGear.gold)
	for _, step in ipairs(sequence.steps) do
		assert(step.afterSets.legendary[1].pieces == 4 and step.afterSets.common[1].pieces == 4)
	end
	local unprotected = Finish(P.Search(cat, mixed, twoSets, twoSetsRef, { exotic = true }, 12000,
		P.Policy({ protectSets = false, budget = 0 })))
	local protectedBudget = Finish(P.Search(cat, mixed, twoSets, twoSetsRef, { exotic = true }, 12000, P.Policy({ budget = 0 })))
	assert(unprotected.affordable.complete and unprotected.affordable.gold == 0)
	assert(unprotected.affordable.outputPressure < protectedBudget.affordable.outputPressure)
	assert(not Eval(unprotected.maxGear.pieces).sets.legendary and not Eval(unprotected.maxGear.pieces).sets.common)
	local lost = P.Execution(cat, mixed, twoSets, unprotected.maxGear.pieces, twoSetsRef, { exotic = true })
	assert(not lost.preserves and lost.gold == unprotected.maxGear.gold)
end
AZS_GEN.setBonuses[1].text = knownText

-- Five actual Legendary pieces compete to fill four protected slots. One is
-- free to take the higher-quality drop. Enumerate which slot maximizes output.
local constrained = P.Copy(mixed)
constrained.pieces[5].tier = "legendary"
constrained.pieces[9].tier = "mythic"
local constrainedActual = Eval(constrained.pieces)
local constrainedRef = assert(P.Reference(constrained, constrainedActual))
constrained.demand.output = constrainedRef.demand.output * 10
local maxA = Finish(P.Search(cat, constrained, constrainedActual, constrainedRef, { exotic = true }, 12000))
local expectedMax = math.huge
for keepOut = 1, 5 do
	local draft = P.Copy(constrained.pieces)
	for i = 1, 8 do if i == keepOut or i > 5 then draft[i].tier = "exotic" end end
	expectedMax = math.min(expectedMax, P.Difficulty(constrained.demand, Eval(draft), constrainedRef).output)
end
assert(maxA.unreachable and maxA.maxGear.protectedHolds == 4)
near(maxA.maxGear.outputPressure, expectedMax)
local cappedA = P.BySlot(maxA.maxGear.pieces)
assert(cappedA.main_hand.tier == "mythic", "prior higher-quality gear stays worn")
for _, piece in ipairs(maxA.maxGear.pieces) do assert(piece.stars == cat.pieces.scale.top) end
table.remove(constrained.pieces, 8)
constrainedActual = Eval(constrained.pieces)
local withEmpty = Finish(P.Search(cat, constrained, constrainedActual, constrainedRef, { exotic = true }, 12000))
assert(P.BySlot(withEmpty.maxGear.pieces).hands.tier == "exotic", "Max Gear may fill a verified empty slot")

local rogueCase = P.Copy(constrained)
rogueCase.class, rogueCase.pieces = "rogue", { Item("main_hand", "common", 0) }
local rogueActual = assert(P.Evaluate(cat, "rogue", rogueCase.pieces))
local rogueRef = assert(P.Reference(rogueCase, rogueActual))
rogueCase.demand.output = rogueRef.demand.output * 15
local unknownDrop = Finish(P.Search(cat, rogueCase, rogueActual, rogueRef, { exotic = true }, 12000))
assert(unknownDrop.complete and unknownDrop.unverifiedDrops and not unknownDrop.unreachable)
assert(not P.BySlot(unknownDrop.maxGear.pieces).off_hand, "unknown drop is excluded from the reference configuration")
do
	local unknownBudget = Finish(P.Search(cat, rogueCase, rogueActual, rogueRef, { exotic = true }, 12000, P.Policy({ budget = 0 })))
	assert(unknownBudget.affordable.gold == 0 and not unknownBudget.unreachable and unknownBudget.unverifiedDrops)
end

-- Quality is not a substitute for the computed Damage of a configuration.
local scaleSlot, scaleProfile = cat.tiers.exotic.slot, cat.tiers.exotic.profile
cat.tiers.exotic.slot, cat.tiers.exotic.profile = 0.25, 0
local ceilingCase = P.Copy(mixed)
ceilingCase.pieces = { Item("main_hand", "legendary", 1) }
local ceilingActual = Eval(ceilingCase.pieces)
local ceilingRef = assert(P.Reference(ceilingCase, ceilingActual))
ceilingCase.demand.output = ceilingRef.demand.output * 15
local qualityCeiling = Finish(P.Search(cat, ceilingCase, ceilingActual, ceilingRef, { exotic = true }, 12000))
assert(qualityCeiling.unreachable and qualityCeiling.maxGear.outputPressure > qualityCeiling.outputPressure)
assert(P.BySlot(qualityCeiling.maxGear.pieces).main_hand.tier == "exotic")
cat.tiers.exotic.slot, cat.tiers.exotic.profile = scaleSlot, scaleProfile
table.remove(AZS_GEN.setBonuses)

-- A deliberately output-limited Warlock. Cheap armor swaps only change
-- survival or unmodeled stats. Check both reachable and unreachable ties.
local originalDrop = G.DropSlot
local chosenSlots = { chest = 2, legs = 4, head = 0, main_hand = 8 }
local armorStats = {}
for _, index in pairs(chosenSlots) do armorStats[index] = AZS_GEN.pieces.slots[index].stats end
for _, index in ipairs({ 0, 2, 4 }) do AZS_GEN.pieces.slots[index].stats = { { "hp", 25 }, { "area", 0.02 } } end
G.DropSlot = function(catalog, class, slot, tier)
	return chosenSlots[slot] and originalDrop(catalog, class, slot, tier)
end
local tie = P.Copy(source)
tie.pieces = { Item("chest", "legendary", 0), Item("legs", "legendary", 0), Item("main_hand", "legendary", 0) }
local tieActual = Eval(tie.pieces)
local tieRef = assert(P.Reference(tie, tieActual))
local tieDrops = { uncommon = true, exotic = true }
local legalSlots = { "chest", "legs", "main_hand", "head" }
for _, factor in ipairs({ 1.04, 2 }) do
	tie.demand = { output = tieRef.demand.output * factor, survival = tieRef.demand.survival * 0.70 }
	local best, choices = nil, {}
	local function Enumerate(i, gold, replacements, fills)
		local slot = legalSlots[i]
		if slot then
			local worn = tie.pieces[i]
			if not worn then Enumerate(i + 1, gold, replacements, fills) end
			for _, tier in ipairs(worn and { "legendary", "exotic" } or { "uncommon", "exotic" }) do
				for star = 0, 1 do
					choices[i] = Item(slot, tier, star)
					local price = star == 1 and priceTable[tier][star] or 0
					Enumerate(i + 1, gold + price, replacements + (worn and tier ~= worn.tier and 1 or 0), fills + (worn and 0 or 1))
				end
			end
			choices[i] = nil
			return
		end
		local after = P.Difficulty(tie.demand, Eval(choices), tieRef).output
		local reached = after <= 100
		local less = best and (gold < best.gold or (gold == best.gold and (replacements < best.replacements
			or (replacements == best.replacements and fills < best.fills))))
		if not best or (reached and not best.reached) or (reached and best.reached and less)
			or (not reached and not best.reached and (after < best.outputPressure - P.tolerance
				or (math.abs(after - best.outputPressure) <= P.tolerance and less))) then
			best = { outputPressure = after, reached = reached, gold = gold, replacements = replacements, fills = fills }
		end
	end
	Enumerate(1, 0, 0, 0)
	local plan = Finish(P.Search(cat, tie, tieActual, tieRef, tieDrops, 12000))
	local result = P.BySlot(plan.pieces)
	assert(plan.complete and (plan.outputPressure <= 100) == best.reached and plan.gold == best.gold)
	assert(best.replacements == 1 and best.fills == 0 and not result.head)
	assert(P.SamePiece(result.chest, tie.pieces[1]) and P.SamePiece(result.legs, tie.pieces[2]), "retain worn armor in pressure and gold ties")
	assert(result.main_hand.tier == "exotic")
	local _, quote = P.Changes(cat, tie.pieces, plan.pieces, tieDrops, tie.class)
	assert(quote.gold == plan.gold)
	near(plan.outputPressure, P.Difficulty(tie.demand, Eval(plan.pieces), tieRef).output)
	if not best.reached then near(plan.outputPressure, best.outputPressure) end
	local hypothetical = P.Replace(tie.pieces, "chest", "uncommon", 0)
	assert(Eval(hypothetical).stats.hp < tieActual.stats.hp, "simulator can still evaluate the downgrade")
end

-- The first feasible zero-gold arrangement can spend two drops even though
-- a different branch with one drop reaches the same target at the same gold.
cat.pieces.scale.top = 0
AZS_GEN.pieces.slots[2].stats = { { "damage", 0.12 } }
AZS_GEN.pieces.slots[4].stats = { { "damage", 0.12 } }
AZS_GEN.pieces.slots[8].stats = { { "damage", 0.20 } }
tieActual = Eval(tie.pieces)
tie.demand = P.Copy(ref.demand)
tieRef = assert(P.Reference(tie, tieActual))
tie.demand = { output = tieRef.demand.output * (1 + 0.13 / tieActual.output), survival = tieRef.demand.survival * 0.70 }
local twoDrops = { Item("chest", "exotic", 0), Item("legs", "exotic", 0), tie.pieces[3] }
local oneDrop = P.Replace(tie.pieces, "main_hand", "exotic", 0)
assert(P.Difficulty(tie.demand, Eval(twoDrops), tieRef).output <= 100)
assert(P.Difficulty(tie.demand, Eval(oneDrop), tieRef).output <= 100)
local cheaperAcquisition = Finish(P.Search(cat, tie, tieActual, tieRef, { exotic = true }, 12000))
local changes, quote = P.Changes(cat, tie.pieces, cheaperAcquisition.pieces, { exotic = true }, tie.class)
assert(cheaperAcquisition.complete and cheaperAcquisition.outputPressure <= 100 and quote.gold == 0)
assert(#changes == 1 and changes[1].slot == "main_hand", "search a same-gold branch when it can use fewer drops")
for index, stats in pairs(armorStats) do AZS_GEN.pieces.slots[index].stats = stats end
G.DropSlot = originalDrop
cat.pieces.scale.top = savedTop

-- Independently enumerate a mixed-quality space with one eligible empty
-- slot and two worn choices. Check both target cost and affordable output.
local function BudgetOracles()
	local context = P.Copy(source)
	context.pieces = {}
	for i = 1, 9 do
		if i ~= 3 then table.insert(context.pieces, Item(keys[i], i == 1 and "rare" or i == 9 and "common" or "mythic",
			(i == 1 or i == 9) and 2 or 5)) end
	end
	local actualGear = Eval(context.pieces)
	local reference = P.Reference(context, actualGear)
	local choices = {}
	local combinations = {}
	local function Enumerate(i, gold, rank, allowDrops)
		if i > 9 then
			local pieces = {}
			for _, key in ipairs(keys) do if choices[key] then table.insert(pieces, choices[key]) end end
			table.insert(combinations, { pieces = pieces, evaluation = Eval(pieces), gold = gold, rank = rank })
			return
		end
		local slot = keys[i]
		local before = P.BySlot(context.pieces)[slot]
		local function Stars(tier, first, rankCost)
			local additional = 0
			for s = first, 5 do
				if s > first then additional = additional + priceTable[tier][s] end
				choices[slot] = Item(slot, tier, s)
				Enumerate(i + 1, gold + additional, rank + rankCost, allowDrops)
			end
		end
		if before then Stars(before.tier, before.stars, 0)
		else choices[slot] = nil; Enumerate(i + 1, gold, rank, allowDrops) end
		if allowDrops and (i == 1 or i == 3 or i == 9) then Stars("exotic", 0, before and 10 or 1) end
	end
	local count = 0
	for _, mode in ipairs({ "A", "B" }) do
		local allowed = mode == "A" and { exotic = true } or nil
		combinations = {}
		Enumerate(1, 0, 0, allowed)
		for _, target in ipairs({ 72, 100, 118, 175 }) do
			context.demand.output = 1.4 * reference.demand.output
			for _, budget in ipairs({ 0, 2365, 2366, 8125, 24000, 50000, 170000 }) do
				local minimum, winner, winnerPressure
				local currentPressure = P.Difficulty(context.demand, actualGear, reference).output
				for _, row in ipairs(combinations) do
					local pressure = P.Difficulty(context.demand, row.evaluation, reference).output
					local meets = pressure <= target
					if meets then minimum = math.min(minimum or math.huge, row.gold) end
					if row.gold <= budget then
						local winnerMeets = winner and winnerPressure <= target
						local cheaper = winner and (row.gold < winner.gold or (row.gold == winner.gold and row.rank < winner.rank))
						if not winner or (meets and (not winnerMeets or cheaper))
							or (not meets and not winnerMeets and (pressure < winnerPressure - 1e-10
								or (math.abs(pressure - winnerPressure) < 1e-10 and cheaper))) then
							winner, winnerPressure = row, pressure
						end
					end
				end
				local solution = Finish(P.Search(cat, context, actualGear, reference, allowed, 20000,
					P.Policy({ target = target, budget = budget })))
				local chosen = solution.affordable or solution
				assert(solution.complete and chosen.complete and solution.minimumTargetCost == minimum)
				local _, quote = P.Changes(cat, context.pieces, chosen.pieces, allowed, context.class)
				assert(chosen.gold == quote.gold and chosen.gold == winner.gold and chosen.gold <= budget)
				if currentPressure <= target then
					assert(chosen.acquisitionRank == 0 and chosen.gold == 0)
				elseif winnerPressure <= target then
					assert(chosen.outputPressure <= target and chosen.acquisitionRank == winner.rank)
				else
					near(chosen.outputPressure, winnerPressure)
					assert(chosen.acquisitionRank == winner.rank)
				end
				count = count + 1
			end
		end
	end
	assert(count == 56)
end
BudgetOracles()

local function ExecutionTransition()
	local context = P.Copy(source)
	context.pieces = {}
	for i = 1, 8 do
		context.pieces[i] = Item(keys[i], "common", (i == 1 or i == 2 or i == 7 or i == 8) and 1 or 0)
	end
	local equipped = Eval(context.pieces)
	local reference = P.Reference(context, equipped)
	local target = P.Replace(context.pieces, "head", "exotic", 2)
	target = P.Replace(target, "shoulders", "exotic", 1)
	target = P.Replace(target, "chest", "common", 2)
	target = P.Replace(target, "legs", "common", 1)
	local drops = { exotic = true }
	local sequence = P.Execution(cat, context, equipped, target, reference, drops)
	local _, quote = P.Changes(cat, context.pieces, target, drops, context.class)
	assert(sequence.preserves and sequence.gold == quote.gold)
	local acquired, total = {}, 0
	for _, step in ipairs(sequence.steps) do
		assert(step.afterSets.common and step.afterSets.common[1].pieces == 4)
		if step.kind == "acquire" then
			assert(step.stars == 0 and step.quote.kind == "farm")
			acquired[step.slot] = true
		else
			assert(step.stars > step.from)
			if step.tier == "exotic" then assert(acquired[step.slot] and step.from == 0) end
		end
		total = total + step.quote.gold
		assert(total == step.cumulative and step.output)
	end
	local final = P.BySlot(sequence.pieces)
	for _, piece in ipairs(target) do assert(P.SamePiece(piece, final[piece.slot])) end
end
AZS_GEN.setBonuses[1].text = "Unquantified combat"
ExecutionTransition()
AZS_GEN.setBonuses[1].text = knownText

-- Event and widget mocks follow the native zone-before-armor sync contract.
local widgets, handlers, commands = {}, {}, {}
function CreateFrame(kind, name, parent)
	local w = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, events = {} }
	function w:CreateFontString() return CreateFrame("FontString", nil, self) end
	function w:CreateTexture() return CreateFrame("Texture", nil, self) end
	function w:SetScript(key, fn) self.scripts[key] = fn end
	function w:SetText(text) self.text = text end
	function w:GetText() return self.text end
	function w:ClearFocus() if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
	function w:Show() self.shown = true end
	function w:Hide()
		local before = self.shown
		self.shown = false
		if before and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function w:IsShown() return self.shown end
	function w:Enable() self.disabled = false end
	function w:Disable() self.disabled = true end
	function w:RegisterEvent(key) self.events[key] = true end
	function w:UnregisterEvent(key) self.events[key] = nil end
	function w:GetStringHeight()
		if type(self.text) ~= "string" then return 14 end
		local text = string.gsub(string.gsub(self.text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
		local glyphs = #string.gsub(text, "[\128-\191]", "")
		return 14 * math.max(1, math.ceil(glyphs * 6 / math.max(1, self.width or 200)))
	end
	function w:SetWidth(value) self.width = value end
	function w:SetHeight(value) self.height = value end
	function w:SetScale(value) self.scale = value end
	function w:GetWidth() return self.width end
	function w:GetHeight() return self.height end
	function w:SetFrameStrata(value) self.strata = value end
	function w:SetFrameLevel(value) self.level = value end
	function w:GetFrameLevel() return self.level or 1 end
	function w:GetTop() return self.top or 500 end
	function w:GetBottom() return self.bottom or 0 end
	function w:SetMinMaxValues(low, high) self.low, self.high = low, high end
	function w:GetMinMaxValues() return self.low, self.high end
	function w:SetValue(value)
		self.value = value
		if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
	end
	function w:GetValue() return self.value end
	function w:EnableKeyboard(value) self.keyboard = value end
	function w:EnableMouse(value) self.mouse = value end
	function w:EnableMouseWheel(value) self.wheel = value end
	function w:SetVerticalScroll(value) self.offset = value end
	function w:SetBackdropColor(r, g, b, a) self.backgroundAlpha = a end
	function w:SetTextColor(r, g, b) self.textColor = { r, g, b } end
	function w:SetPoint(...) self.point = { ... } end
	function w:ClearAllPoints() self.point = nil end
	function w:SetScrollChild(child) self.scrollChild = child end
	table.insert(widgets, w)
	for _, method in ipairs({ "SetAllPoints", "SetBackdrop", "SetBackdropBorderColor",
		"SetJustifyH", "SetTexture", "SetFont", "SetAlpha", "SetThumbTexture",
		"SetVertexColor", "SetOrientation", "SetClampedToScreen", "SetAutoFocus", "SetMaxLetters", "SetTextInsets" }) do w[method] = function() end end
	if kind == "GameTooltip" then
		for _, method in ipairs({ "SetOwner", "SetText", "IsOwned", "AddLine", "Hide" }) do w[method] = GameTooltip[method] end
		function w:NumLines() return #self.lines end
	end
	return w
end
function SurvivorUI_GoldButton(parent, width, _, _, caption)
	local button = CreateFrame("Button", nil, parent)
	button:SetWidth(width)
	button.icon = button:CreateTexture()
	button.text = button:CreateFontString()
	button.text:SetText(caption)
	function button:Light(hot) self.hot = hot end
	return button
end
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetWidth(1024)
UIParent:SetHeight(768)
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent)
GameMenuFrame:Hide()
function SurvivorUI_T(text) return text end
function SurvivorUI_RebornActive() return true end
function SurvivorUI_RebornStableRunId(value) return value end
function AZS_SendCommand(command) table.insert(commands, command) end
function time() return 1234 end
local clock = 0
function GetTime() return clock end
AZS = { ServerBuild = "v0.7.4", On = function(event, fn) assert(not handlers[event]); handlers[event] = fn end }
SurvivorUIDB = { rebornGear = { mapReference = { zone = "naxx", tier = 3 }, wornSnapshots = { warlock = { pieces = armor } } } }
local dollSlot = { slot = 0, hooks = 0 }
local secondSlot = { slot = 1, hooks = 0 }
function dollSlot:HookScript(event, fn)
	if event == "OnEnter" then self.hooks, self.afterEnter = self.hooks + 1, fn
	else assert(event == "OnLeave"); self.afterLeave = fn end
end
GameTooltip = {
	SetOwner = function(self, owner) self.owner = owner end,
	SetText = function(self, text) self.lines, self.colors = { text }, {} end,
	IsOwned = function(self, owner) return self.owner == owner end,
	AddLine = function(self, text, r, g, b)
		table.insert(self.lines, text)
		self.colors[#self.lines] = { r, g, b }
	end,
	Show = function(self) self.shown = true end,
	Hide = function(self) self.shown = false; self.owner = nil end,
}
function dollSlot:Hover()
	GameTooltip.owner, GameTooltip.lines, GameTooltip.colors = self, { "Native tooltip" }, {}
	GameTooltip:Show()
	if self.afterEnter then self.afterEnter(self) end
	return table.concat(GameTooltip.lines, "\n")
end
secondSlot.HookScript, secondSlot.Hover = dollSlot.HookScript, dollSlot.Hover
AZSInspectGear = CreateFrame("Frame")
AZSInspect = { unit = "player", shown = true }
function AZSInspect:IsShown() return self.shown end
function AZSInspect:HookScript(key, fn) assert(key == "OnHide"); self.onHide = fn end
function AZSInspect:Hide() self.shown = false; if self.onHide then self.onHide() end end
function AZSInspect:RefreshDoll(armor)
	AZSInspectSlot0 = { GetParent = function() return dollSlot end }
	AZSInspectSlot1 = { GetParent = function() return secondSlot end }
	dollSlot.piece, secondSlot.piece = nil, nil
	for _, item in ipairs(armor) do
		if tonumber(item.slot) == 0 then dollSlot.piece = item end
		if tonumber(item.slot) == 1 then secondSlot.piece = item end
	end
end
function hooksecurefunc(target, method, callback)
	local original = target[method]
	target[method] = function(self, ...)
		original(self, ...)
		callback(self, ...)
	end
end

dofile("SurvivorUI/RebornGear.lua")
local originalSearch, searchCalls, searchLimit = P.Search, 0
function P.Search(catalog, context, actual, reference, allowed, limit, policy)
	searchCalls = searchCalls + 1
	return originalSearch(catalog, context, actual, reference, allowed, searchLimit or limit, policy)
end
local function Named(name)
	for _, widget in ipairs(widgets) do if widget.name == "SurvivorUIRebornGear" .. name then return widget end end
end
local function Find(kind, text, children)
	local function Visible(widget)
		while widget do
			if not widget.shown then return false end
			widget = widget.parent
		end
		return true
	end
	for _, w in ipairs(widgets) do
		local caption = type(w.text) == "table" and w.text.text or w.text
		if w.kind == "Button" and w.lines then caption = w.lines[1].text end
		if w.kind == kind and Visible(w) and (not children or w.parent == children)
			and type(caption) == "string" and string.find(caption, text, 1, true) then return w end
	end
end
local function Click(text)
	local button = assert(Find("Button", text), text)
	assert(not button.disabled, text)
	button.scripts.OnClick()
end
local function Input(key)
	for _, widget in ipairs(widgets) do
		if widget.kind == "EditBox" and widget.key == key then return widget end
	end
end
local function Enter(key, value)
	local box = assert(Input(key))
	box.scripts.OnEditFocusGained()
	box:SetText(value)
	box.scripts.OnEnterPressed()
end
local function Zone(key, level, class, run, affixes, hub)
	AZS_ZONE = { hub = hub or (key == "dalaran" and 1 or 0), zone = key, dt = level, heroic = level, class = class, run = run, affixes = affixes }
	handlers.AZSZONE()
end
local function Armor(rows)
	AZS_ARMOR = rows
	handlers.AZSARMOR()
	AZSInspect:RefreshDoll(rows)
end
local function SlotMenu(slot, value, field)
	for _, row in ipairs(widgets) do
		local menu = row[field or "tier"]
		if row.shown and row.slot == slot and menu and menu.shown then
			menu.scripts.OnClick()
			local tierNames = { legendary = "Legendary", common = "Common" }
			local option = type(value) == "number" and ("★" .. value) or tierNames[value] or "Empty slot"
			for _, popup in ipairs(widgets) do
				if popup.items and popup.shown then return assert(Find("Button", option, popup), option).scripts.OnClick end
			end
		end
	end
end
local function HoverIcon(slot, planned)
	for _, row in ipairs(widgets) do
		if row.slot == slot and row.shown and row.iconButton.shown and (row.plan ~= nil) == planned then
			row.iconButton.scripts.OnEnter()
			local tip = Named("Tooltip")
			if tip.shown then return table.concat(tip.lines, "\n") end
		end
	end
end
local function TooltipColor(text, tip)
	tip = tip or GameTooltip
	for i, line in ipairs(tip.lines) do
		if string.find(line, text, 1, true) then return tip.colors[i] end
	end
end
local function StatCells(parent, label)
	for _, row in ipairs(widgets) do
		if row.parent == parent and row.shown and row.label and row.label.text == label then return row.cells end
	end
end
local function VisiblePanel()
	for _, w in ipairs(widgets) do if w.name == "SurvivorUIRebornGearPanel" then return w end end
end
local function WorldEvent()
	for _, w in ipairs(widgets) do
		if w.events.PLAYER_ENTERING_WORLD then w.scripts.OnEvent(w, "PLAYER_ENTERING_WORLD") end
	end
end
local function DrainSearch()
	local panel = VisiblePanel()
	for i = 1, 2000 do
		if not panel.scripts.OnUpdate then return end
		panel.scripts.OnUpdate()
	end
	error("Search failed to stop")
end

assert(SurvivorUI_RebornGearOpen("show"))
assert(Find("FontString", "Waiting for the game's world snapshot"))
Zone("elwynn", 0, "warlock", "a")
assert(Find("FontString", "Warlock · Elwynn Forest · Normal"))
assert(Find("FontString", "Current equipment unavailable"))
assert(Find("Button", "Set 100% Baseline").disabled)
assert(Find("FontString", "Waiting for equipment"))
local head = { slot = "0", rarity = "0", stars = "0", icon = "INV_Test", name = "Test item" }
Armor({ head })
assert(not Find("FontString", "100% reference:"))
assert(Find("FontString", "Comparable baseline required"))
local tooltip = dollSlot:Hover()
assert(dollSlot.hooks == 1 and string.find(tooltip, "Native tooltip", 1, true))
assert(string.find(tooltip, "408 gold", 1, true) and string.find(tooltip, "Next tier", 1, true))
assert(dollSlot:Hover() == tooltip, "repeat hover rebuilds the same native extension once")
Armor({ head, { slot = 1, rarity = 4, stars = 2 } })
assert(string.find(secondSlot:Hover(), "6882 gold", 1, true) and not string.find(secondSlot:Hover(), "408 gold", 1, true))
dollSlot.afterLeave(dollSlot)
assert(GameTooltip:IsOwned(secondSlot), "leaving another slot does not clear the active tooltip")
AZSInspect:Hide()
assert(not GameTooltip.shown)
AZSInspect.shown = true
Armor({ head })
Click("Set 100% Baseline")
local saved = assert(SurvivorUIDB.rebornGear.baselines.warlock)
assert(saved.zone == "elwynn" and saved.level == 0 and saved.origin == "campaign" and saved.at == 1234 and saved.modifiers.affixes == "")
assert(saved.pieces[1].name == "Test item" and saved.pieces[1].stars == 0)
assert(StatCells(Named("Results"), "Output pressure")[1].text == "100.0%")
assert(StatCells(Named("Results"), "Survival pressure")[1].text == "100.0%")
assert(not Find("Button", "Max Gear") and not Find("Button", "Economy"))
assert(Find("FontString", "No upgrade is needed for this target"))
assert(Find("FontString", "Lower is better"))
assert(string.find(dollSlot:Hover(), "Output pressure |cff8cffa5-", 1, true))
assert(TooltipColor("Damage +")[2] == 1)
assert(not Find("FontString", "Output uses gear Damage"))
Click("Show details")
assert(Find("FontString", "Output uses gear Damage") and Find("FontString", "separately from modeled output"))
assert(Find("FontString", "Survival estimates a representative hit"))
Click("Hide details")
local highHead = P.Copy(head)
highHead.stars = "5"
Armor({ highHead })
assert(string.find(dollSlot:Hover(), "Next tier", 1, true))
assert(TooltipColor("Damage -")[1] == 1 and TooltipColor("Damage -")[2] < 0.6)
Armor({ head })
Click("Equipment Simulator")
local edit = assert(SlotMenu("head", "legendary"))
edit()
assert(string.find(HoverIcon("head", false), "Simulated item · Legendary", 1, true))
assert(TooltipColor("Damage +", Named("Tooltip"))[2] == 1)
assert(Named("Tooltip").backgroundAlpha == 1 and not GameTooltip:IsOwned(Named("Tooltip")))
local changeStar = assert(SlotMenu("head", 2, "stars"))
changeStar()
assert(not Named("Tooltip").shown, "simulator edits clear its tooltip")
assert(string.find(HoverIcon("head", false), "★2 → ★3", 1, true))
assert(string.find(HoverIcon("shoulders", false), "Empty slot", 1, true))
assert(StatCells(Named("Results"), "Output pressure") and Find("FontString", "Replacement acquisition is conditional"))
assert(SlotMenu("head", "common"))()
assert(string.find(HoverIcon("head", false), "Simulated item · Common", 1, true), "manual simulator allows lower tiers")
assert(SlotMenu("head", "legendary"))()
assert(saved.pieces[1].stars == 0 and saved.pieces[1].tier == "common" and head.rarity == "0")
Armor({ head })
assert(Find("FontString", "Replacement acquisition is conditional"), "duplicate native gear updates preserve the simulation")
AZS_ZONE = P.Copy(AZS_ZONE)
AZS_ZONE.aff = 2
handlers.AZSZONE()
assert(Find("FontString", "Replacement acquisition is conditional"), "replaced equivalent zone and legacy affix metadata keep state")
Click("Load Plan B")
assert(not Find("FontString", "Replacement acquisition is conditional"))
Click("Difficulty & Upgrade Planner")
assert(not Find("Button", "Reset to Actual Equipment"))
edit()
assert(not Find("FontString", "Replacement acquisition is conditional"), "stale dropdown callbacks cannot edit the planner")

Zone("naxx", 1, "warlock", "b")
assert(Find("FontString", "Naxxramas · Heroic I") and Find("FontString", "Current equipment unavailable"))
assert(Find("FontString", "Additional difficulty rules are omitted for the target"))
assert(Find("Button", "Update 100% Baseline").disabled)
Armor({ head })
assert(VisiblePanel().scripts.OnUpdate, "both plans are event-triggered, then sliced")
assert(Find("FontString", "Searching equipment combinations…"))
Click("Equipment Simulator")
assert(not VisiblePanel().scripts.OnUpdate, "simulator editing suspends optimizer work")
Click("Difficulty & Upgrade Planner")
DrainSearch()
assert(Find("FontString", "Plan A") and Find("FontString", "Plan B"))
local planned = assert(HoverIcon("head", true))
assert(string.find(planned, "Planned item Test item · Common ★0 →", 1, true))
assert(not string.find(planned, "pressure", 1, true) and not string.find(planned, "Set ", 1, true))
assert(string.find(planned, "Damage +", 1, true) and string.find(planned, "obtain item through drops", 1, true))
local gearPane, effectsPane = Named("Equipment"), Named("Effects")
assert(gearPane.point[5] == Named("Results").point[5] and gearPane.point[4] + gearPane.width < effectsPane.point[4])
assert(Find("FontString", "Equipment slot") and StatCells(effectsPane.scrollChild, "Damage"))
local lastStat = StatCells(effectsPane.scrollChild, "Gold find")[1].parent
assert(-lastStat.point[5] + lastStat.height <= effectsPane.height + 30, "standard viewport shows the core attribute groups")
local planA, planB = assert(Find("Button", "Plan A")), assert(Find("Button", "Plan B"))
assert(planA.lit and not planB.lit and string.find(planA.lines[2].text, "gold") and string.find(planB.lines[2].text, "gold"))
local searched = searchCalls
local damageA = StatCells(effectsPane.scrollChild, "Damage")[2].text
local pressureA = StatCells(Named("Results"), "Output pressure")[2].text
Click("Plan B · Stars only")
assert(planB.lit and not planA.lit and searchCalls == searched and not VisiblePanel().scripts.OnUpdate)
local damageB = StatCells(effectsPane.scrollChild, "Damage")[2].text
assert(damageB ~= damageA, "selection updates the complete right-hand configuration")
Click("Equipment Simulator")
assert(SlotMenu("head", 2, "stars"))()
local independentlyEditedDamage = StatCells(effectsPane.scrollChild, "Damage")[2].text
Click("Difficulty & Upgrade Planner")
Click("Plan A · Current expansion drops")
assert(StatCells(effectsPane.scrollChild, "Damage")[2].text == damageA and not Named("Tooltip").shown)
Click("Equipment Simulator")
assert(StatCells(effectsPane.scrollChild, "Damage")[2].text == independentlyEditedDamage)
Click("Difficulty & Upgrade Planner")
local function PlanRows()
	local count = 0
	for _, row in ipairs(widgets) do if row.parent == gearPane.scrollChild and row.shown and row.slot then count = count + 1 end end
	return count
end
local changedRows = PlanRows()
Click("Show full equipment")
assert(PlanRows() >= changedRows and Find("Button", "Show changes only"))
Click("Show changes only")
assert(PlanRows() == changedRows)
Click("Load in Simulator")
assert(StatCells(effectsPane.scrollChild, "Damage")[2].text == damageA)
assert(StatCells(Named("Results"), "Output pressure")[2].text == pressureA)
assert(searchCalls == searched)
Click("Equipment Simulator")
assert(not Named("Tooltip").shown)
Click("Load Plan A")
assert(Find("FontString", "Calculable upgrade gold:") and not VisiblePanel().scripts.OnUpdate)
if Find("Button", "Reset to Actual Equipment") then Click("Reset to Actual Equipment") end
assert(SlotMenu("head", false))()
local lostDamage = assert(Find("FontString", "-8.40 pp"))
assert(lostDamage.textColor[1] == 1 and lostDamage.textColor[2] < 0.6)
local noChange = StatCells(effectsPane.scrollChild, "Critical strike")[3]
assert(noChange.textColor[1] == 0.72 and noChange.textColor[2] == 0.73)
local morePressure = StatCells(Named("Results"), "Output pressure")[3]
assert(string.find(morePressure.text, "+", 1, true) and morePressure.textColor[1] == 1, "higher pressure is red")
assert(Find("Button", "Reset to Actual Equipment"))
Click("Reset to Actual Equipment")
assert(Find("FontString", "Calculable upgrade gold: 0") and Find("Button", "Reset to Actual Equipment").disabled)
Click("Difficulty & Upgrade Planner")
assert(saved == SurvivorUIDB.rebornGear.baselines.warlock)
do
	Click("Equipment Simulator")
	assert(SlotMenu("head", 2, "stars"))()
	Click("Difficulty & Upgrade Planner")
	local beforeSettings = searchCalls
	local targetBox = Input("target")
	targetBox.scripts.OnEditFocusGained()
	targetBox:SetText("8")
	targetBox:SetText("80")
	assert(searchCalls == beforeSettings)
	targetBox.scripts.OnEnterPressed()
	assert(searchCalls == beforeSettings + 2 and SurvivorUIDB.rebornGear.target == 80)
	Enter("budget", "0")
	assert(searchCalls == beforeSettings + 4 and SurvivorUIDB.rebornGear.budget == 0)
	Click("Protect sets: On")
	assert(searchCalls == beforeSettings + 6 and SurvivorUIDB.rebornGear.protectSets == false)
	assert(Find("FontString", "Plans may sacrifice set effects"))
	DrainSearch()
	assert(Find("FontString", "Modeled budget left: 0"))
	Click("Execution order")
	assert(Find("FontString", "Obtain and equip") and searchCalls == beforeSettings + 6)
	Click("Show equipment")
	Enter("budget", "-1")
	assert(Find("FontString", "Enter whole gold") and SurvivorUIDB.rebornGear.budget == 0)
	Input("budget"):ClearFocus()
	assert(Input("budget"):GetText() == "0" and not Find("FontString", "Enter whole gold"),
		"blurring an invalid edit must restore the committed budget")
	Input("budget").scripts.OnEditFocusGained()
	Input("budget"):SetText("12345")
	Input("budget").scripts.OnEscapePressed()
	assert(VisiblePanel():IsShown() and Input("budget"):GetText() == "0" and searchCalls == beforeSettings + 6)
	Enter("budget", "")
	Click("Protect sets: Off")
	Click("Reset")
	assert(P.Policy(SurvivorUIDB.rebornGear).target == 100 and SurvivorUIDB.rebornGear.budget == nil)
	assert(saved == SurvivorUIDB.rebornGear.baselines.warlock)
	Click("Equipment Simulator")
	assert(string.find(HoverIcon("head", false), "★2 → ★3", 1, true))
	Click("Difficulty & Upgrade Planner")
end
searchLimit = 1
Zone("shadowmoon", 5, "warlock", "budget")
Armor({ head })
DrainSearch()
assert(Find("FontString", "reachability unproven"))
assert(Find("Button", "Economy").lit and Find("Button", "Max Gear reference"))
do
	Enter("budget", "1000000")
	DrainSearch()
	Click("Plan B · Stars only")
	assert(planB.lines[3].text:find("Budget search incomplete", 1, true))
	assert(not planB.lines[4].text:find("Best priced output within budget", 1, true))
	local spent = assert(planB.lines[2].text:match("(%d+) gold"))
	assert(tonumber(spent) > 0)
	local pressure = StatCells(Named("Results"), "Output pressure")[2].text
	assert(pressure ~= StatCells(Named("Results"), "Output pressure")[1].text)
	Click("Load in Simulator")
	assert(Find("FontString", "Calculable upgrade gold: " .. spent))
	assert(StatCells(Named("Results"), "Output pressure")[2].text == pressure)
	Click("Difficulty & Upgrade Planner")
	Enter("budget", "")
end
searchLimit = nil
local uiHeadStats = AZS_GEN.pieces.slots[0].stats
AZS_GEN.pieces.slots[0].stats = { { "hp", 30 } }
Zone("shadowmoon", 5, "warlock", "max-and-economy")
Armor({ head, { slot = 8, rarity = 4, stars = 0 } })
DrainSearch()
Click("Plan A · Current expansion drops")
assert(Find("Button", "Economy").lit and planA.lines[2].text:find("Economy ·", 1, true))
Click("Plan B · Stars only")
assert(Find("Button", "Economy").lit and Find("FontString", "Output target unreachable in this scope"))
local economyHP = StatCells(effectsPane.scrollChild, "Health")[2].text
local economyGold = assert(planB.lines[2].text:match("(%d+) gold"))
local bOutput = StatCells(Named("Results"), "Output pressure")[2].text
local bSearches = searchCalls
Click("Max Gear")
local maxHP = StatCells(effectsPane.scrollChild, "Health")[2].text
assert(tonumber(maxHP) > tonumber(economyHP) and StatCells(Named("Results"), "Output pressure")[2].text == bOutput)
assert(planB.lines[2].text:find("Max Gear reference ·", 1, true))
local maxGold = assert(planB.lines[2].text:match("(%d+) gold"))
assert(tonumber(maxGold) > tonumber(economyGold))
local maxHeadTip = assert(HoverIcon("head", true))
Click("Plan A · Current expansion drops")
assert(Find("Button", "Economy").lit)
Click("Max Gear")
Click("Plan B · Stars only")
assert(Find("Button", "Max Gear").lit and searchCalls == bSearches)
assert(HoverIcon("head", true) == maxHeadTip)
Click("Load in Simulator")
assert(StatCells(effectsPane.scrollChild, "Health")[2].text == maxHP and searchCalls == bSearches)
assert(Find("FontString", "Calculable upgrade gold: " .. maxGold))
Click("Difficulty & Upgrade Planner")
Click("Economy")
assert(StatCells(effectsPane.scrollChild, "Health")[2].text == economyHP)
Click("Plan A · Current expansion drops")
assert(Find("Button", "Max Gear").lit)
Click("Plan B · Stars only")
assert(Find("Button", "Economy").lit and searchCalls == bSearches)
Click("Load in Simulator")
assert(StatCells(effectsPane.scrollChild, "Health")[2].text == economyHP and searchCalls == bSearches)
assert(Find("FontString", "Calculable upgrade gold: " .. economyGold))
Click("Difficulty & Upgrade Planner")
do
	local starQuote = G.StarQuote
	G.StarQuote = function(catalog, slot, tier, star)
		if tier == "legendary" and star == 5 then return end
		return starQuote(catalog, slot, tier, star)
	end
	Zone("shadowmoon", 5, "warlock", "unpriced-ceiling")
	Armor({ head, { slot = 8, rarity = 4, stars = 0 } })
	DrainSearch()
	Click("Plan B · Stars only")
	assert(planB.lines[4].text:find("Unpriced options excluded", 1, true))
	Click("Max Gear")
	assert(planB.lines[2].text:find("gold known", 1, true))
	assert(planB.lines[4].text:find("Additional price unavailable", 1, true)
		and not planB.lines[4].text:find("Unpriced options excluded", 1, true),
		"Max Gear can include steps with incomplete quotes")
	Click("Execution order")
	assert(Find("FontString", "Additional price unavailable"))
	Click("Show equipment")
	G.StarQuote = starQuote
end
AZS_GEN.pieces.slots[0].stats = uiHeadStats
AZS_ZONE.affixes = { "Sanguine", "Explosive" }
handlers.AZSZONE()
assert(Find("FontString", "Current equipment unavailable"), "in-place modifier changes invalidate gear")
Armor({ head })
AZS_ZONE.affixes = { "explosive", "sanguine" }
handlers.AZSZONE()
assert(not Find("FontString", "Current equipment unavailable"), "equivalent affix lists preserve gear")
AZS_ZONE.mode = "swarm"
handlers.AZSZONE()
Armor({ head })
assert(Find("FontString", "Campaign pressure and plans are unavailable in this mode"))
assert(not VisiblePanel().scripts.OnUpdate and not Find("Button", "Update 100% Baseline"))
AZS_ZONE.zone, AZS_ZONE.dt, AZS_ZONE.heroic = "elwynn", 0, 0
Armor({ head })
assert(Find("FontString", "Waiting for the game's world snapshot"), "armor before an announced zone is rejected")
Zone("elwynn", 0, "warlock", "changed-run", "sanguine")
Armor({ head })
assert(string.find(dollSlot:Hover(), "Next star", 1, true))
local foreign = {}
GameTooltip:SetOwner(foreign)
GameTooltip:SetText("Unrelated tooltip")
Zone("elwynn", 0, "warlock", "later-run", "sanguine")
assert(GameTooltip:IsOwned(foreign) and GameTooltip.shown)
assert(Find("FontString", "Current equipment unavailable"), "a replaced run ID invalidates the inherited gear")
Zone("naxx", 0, "paladin", "c")
Armor({})
Click("Set 100% Baseline")
assert(#SurvivorUIDB.rebornGear.baselines.paladin.pieces == 0 and SurvivorUIDB.rebornGear.baselines.warlock == saved)
Zone("dalaran", 0, "paladin", "d")
assert(Find("FontString", "Theoretical Campaign preview"))
assert(not Find("Button", "Update 100% Baseline") and Find("Button", "Difficulty & Upgrade Planner"))
assert(not StatCells(Named("Results"), "Output pressure") and not Find("FontString", "Plan A") and Find("FontString", "100% reference:"))
Armor({ head })
Click("Select target map")
Click("Elwynn Forest")
maps.elwynn[9] = 1
Click("Normal")
assert(not Find("Button", "Heroic II"))
Click("Heroic I")
maps.elwynn[9] = nil
DrainSearch()
assert(StatCells(Named("Results"), "Output pressure") and Find("FontString", "Plan A"))
assert(SurvivorUIDB.rebornGear.baselines.paladin.zone == "naxx")
Click("Equipment Simulator")
assert(SlotMenu("head", "legendary"))()
Click("Difficulty & Upgrade Planner")
Click("Update 100% Baseline")
assert(SurvivorUIDB.rebornGear.baselines.paladin.zone == "elwynn"
	and SurvivorUIDB.rebornGear.baselines.paladin.level == 1
	and SurvivorUIDB.rebornGear.baselines.paladin.origin == "dalaran"
	and SurvivorUIDB.rebornGear.baselines.warlock == saved)
Click("Equipment Simulator")
assert(Find("FontString", "Equipment attributes") and Find("FontString", "Actual") and Find("FontString", "Simulated"))
assert(Find("FontString", "Output") and Find("FontString", "Survival") and Find("FontString", "Utility"))
assert(Find("FontString", "pp") and Find("FontString", "%"), "only the delta column uses percentage points")
assert(Find("FontString", "Calculable upgrade gold") and Find("FontString", "Worn:"))
assert(string.find(HoverIcon("head", false), "pressure", 1, true))
assert(SurvivorUIDB.rebornGear.baselines.paladin.pieces[1].tier == "common" and head.rarity == "0")
Zone("elwynn", 0, "paladin", "physical-hub", nil, 1)
Armor({ head })
assert(Find("FontString", "Theoretical Campaign preview") and not Find("Button", "Update 100% Baseline") and not VisiblePanel().scripts.OnUpdate)
WorldEvent()
assert(not VisiblePanel():IsShown() and not VisiblePanel().scripts.OnUpdate)
assert(SurvivorUI_RebornGearOpen("show") and Find("FontString", "Waiting for the game's world snapshot"))
Zone("naxx", 0, "warlock", "e")
assert(Find("FontString", "Warlock · Naxxramas · Normal") and not Find("Button", "Heroic I"))
assert(Find("FontString", "Current equipment unavailable"))
Armor({ head })
SurvivorUIDB.rebornGear.hubMap, SurvivorUIDB.rebornGear.hubDifficulty = nil, nil
AZSInspect.unit = "party1"
AZSInspect:RefreshDoll({ head })
assert(dollSlot:Hover() == "Native tooltip")
AZSInspect.unit = "player"
AZSInspect:RefreshDoll({ head })
assert(dollSlot.hooks == 1 and Find("Button", "Upgrades", AZSInspectGear))
dollSlot:Hover()
assert(GameTooltip.shown)
SurvivorUI_RebornGearToggle()
assert(not GameTooltip.shown)
assert(not SurvivorUI_RebornGearEnabled() and not VisiblePanel():IsShown() and not VisiblePanel().scripts.OnUpdate)
assert(dollSlot:Hover() == "Native tooltip" and not SurvivorUI_RebornGearOpen() and #commands == 0)
SurvivorUI_RebornGearToggle()
assert(#commands == 1 and commands[1] == "sync")

GetLocale = function() return "zhCN" end
dofile("SurvivorUI/Locale_zh.lua")
function SurvivorUI_T(text) return SurvivorUI_WORDS.zh[text] or text end
Zone("elwynn", 0, "warlock", "f")
Armor({ head })
assert(SurvivorUI_RebornGearOpen("show") and StatCells(Named("Results"), "输出压力")[1].text == "100.0%")
assert(Find("FontString", "目标输出压力") and Find("FontString", "金币预算") and Find("Button", "保护套装：开启"))
assert(string.find(dollSlot:Hover(), "408 金币", 1, true) and string.find(dollSlot:Hover(), "下一品质", 1, true))
Click("查看说明")
assert(Find("FontString", "默认显示经济方案"))
Click("收起说明")
Click("Equipment Simulator") -- This persistent tab was built before the mock switched locale.
GameTooltip:SetOwner(foreign)
GameTooltip:SetText("Unrelated tooltip")
GameTooltip:Show()
assert(string.find(HoverIcon("head", false), "模拟装备", 1, true))
VisiblePanel():Hide()
assert(not Named("Tooltip").shown and GameTooltip:IsOwned(foreign) and GameTooltip.shown)
GameTooltip:Hide()

-- The host menu handles Escape before special windows. Check the analyzer's
-- input path, without claiming that a mocked event dispatch proves native focus.
GameMenuFrame:Show()
UIParent:SetWidth(525)
UIParent:SetHeight(420)
assert(SurvivorUI_RebornGearOpen("simulator"))
local panel = VisiblePanel()
local shade, popup, keyTimer
for _, widget in ipairs(widgets) do
	if widget.parent == UIParent and widget ~= panel and widget.strata == "FULLSCREEN_DIALOG" then shade = widget end
	if widget.parent == panel and widget.items then popup = widget end
end
near(panel.width * panel.scale, 493)
near(panel.height * panel.scale, 388)
assert(panel.backgroundAlpha == 1 and gearPane.point[4] == effectsPane.point[4] and gearPane.point[5] > effectsPane.point[5])
assert(shade.shown and shade.mouse and shade.wheel and shade.level == nil and panel.level > shade:GetFrameLevel())
assert(panel.keyboard and GameMenuFrame.shown and popup:GetFrameLevel() > panel:GetFrameLevel())
assert(Find("FontString", "装备属性") and Find("FontString", "辅助"))
local fixedSummary = Named("Results").point
local previousContext = Named("Context").point
gearPane.scripts.OnMouseWheel(gearPane, -1)
assert(gearPane.offset > 0 and effectsPane.offset == 0)
effectsPane.scripts.OnMouseWheel(effectsPane, -1)
assert(effectsPane.offset > 0 and gearPane.offset <= 44)
local effectOffset, editSearches = effectsPane.offset, searchCalls
local localizedStar = assert(SlotMenu("head", 2, "stars"))
assert(not HoverIcon("head", false), "an open popup suppresses analyzer tooltips")
localizedStar()
assert(effectsPane.offset == effectOffset and searchCalls == editSearches)
assert(Named("Context").point == previousContext and Named("Results").point[5] <= fixedSummary[5])
assert(StatCells(effectsPane.scrollChild, "伤害")[3].text:find("个百分点"))
local function OpenTier()
	for _, row in ipairs(widgets) do
		if row.slot == "head" and row.shown and row.tier and row.tier.shown then row.tier.scripts.OnClick(); return end
	end
	error("No visible tier control")
end
OpenTier()
assert(popup.shown)
panel.scripts.OnKeyDown(panel, "ESCAPE")
for _, widget in ipairs(widgets) do
	if widget.parent == panel and widget.scripts.OnUpdate then keyTimer = widget end
end
assert(keyTimer)
clock = 0.06
panel.scripts.OnKeyDown(panel, "ESCAPE")
clock = 0.13
keyTimer.scripts.OnUpdate()
assert(popup.shown and panel.shown, "pending repeat stream retains focus")
clock = 0.20
keyTimer.scripts.OnUpdate()
assert(not popup.shown and panel.shown and GameMenuFrame.shown)
OpenTier()
assert(popup.shown)
gearPane.scripts.OnMouseWheel(gearPane, -1)
assert(not popup.shown and gearPane.offset > 44 and effectsPane.offset == effectOffset)
HoverIcon("head", false)
panel.scripts.OnKeyDown(panel, "ESCAPE")
clock = 0.34
keyTimer.scripts.OnUpdate()
assert(not panel.shown and not panel.keyboard and not shade.shown and not keyTimer.scripts.OnUpdate)
assert(GameMenuFrame.shown and not Named("Tooltip").shown, "dismissing the analyzer leaves the native menu and clears its own tooltip")
assert(not panel.events.DISPLAY_SIZE_CHANGED and not panel.events.UI_SCALE_CHANGED)
assert(SurvivorUI_RebornGearOpen("show") and panel.events.DISPLAY_SIZE_CHANGED and panel.events.UI_SCALE_CHANGED)
UIParent:SetWidth(465)
panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
near(panel.width * panel.scale, 433)
assert(panel.scale < 1 and shade.shown)
assert(SurvivorUI_T("Close") == "关闭")
do
	local config = SurvivorUIDB.rebornGear
	config.hubMap, config.hubDifficulty = "shadowmoon", 5
	Zone("dalaran", 0, "warlock", "narrow-hub")
	Armor({ head })
	Enter("budget", "60000")
	DrainSearch()
	assert(gearPane.height >= 55 and effectsPane.height >= 48)
	assert(Find("FontString", "模型估算预算余额") and StatCells(Named("Results"), "输出压力"))
	local previousCommands = #commands
	Click("Refresh equipment")
	assert(#commands == previousCommands + 1 and commands[#commands] == "sync")
	assert(Find("FontString", "暂未读到当前穿戴") and not panel.scripts.OnUpdate)
	Armor({ head })
	assert(Find("FontString", "暂未读到当前穿戴"))
	handlers.AZSZONE()
	Armor({ highHead })
	DrainSearch()
	assert(not Find("FontString", "暂未读到当前穿戴"))
	config.hubMap, config.hubDifficulty, config.budget = nil, nil, nil
end
Click("Close") -- The persistent frame was built while the mock was enUS.
assert(GameMenuFrame.shown and not panel.shown and not shade.shown)
GameMenuFrame:Hide()
UIParent:SetWidth(1024)
UIParent:SetHeight(768)

Zone("elwynn", 0, "warlock", "late", "explosive")
Armor({ head })
dollSlot:Hover()
WorldEvent()
assert(not GameTooltip.shown, "world entry clears the tracked native extension")

-- Feed each view the same completed plan across a real set threshold. The
-- mock controls candidate selection only; both views run the real evaluator.
function P.Search(_, context, actual, reference, drops, _, policy)
	local target = drops and P.Replace(context.pieces, "chest", "common", 1) or context.pieces
	local _, quote = P.Changes(cat, context.pieces, target, drops, context.class)
	return { pieces = target, gold = quote.gold, complete = true, target = policy.target,
		outputPressure = P.Difficulty(context.demand, drops and Eval(target) or actual, reference).output }
end
Zone("naxx", 1, "warlock", "set-comparison")
Armor({ { slot = 0, rarity = 0, stars = 1 }, { slot = 1, rarity = 0, stars = 1 },
	{ slot = 2, rarity = 0, stars = 0 }, { slot = 3, rarity = 0, stars = 1 } })
assert(SurvivorUI_RebornGearOpen("show"))
local set = assert(Find("FontString", "套装激活"))
local fullDamage = StatCells(effectsPane.scrollChild, "伤害")[2].text
local setPressure = StatCells(Named("Results"), "输出压力")[2].text
local setLabel = set.text
Click("方案 B · 仅升星")
assert(not Find("FontString", "套装激活"))
Click("方案 A · 当前资料片掉落")
Click("Load in Simulator")
assert(Find("FontString", "可计算的升级金币：408") and Find("FontString", setLabel))
assert(StatCells(effectsPane.scrollChild, "伤害")[2].text == fullDamage)
assert(StatCells(Named("Results"), "输出压力")[2].text == setPressure)
P.Search = originalSearch
WorldEvent()

-- Load the real recorder for the native feed and late-start integration.
dofile("SurvivorUI/RebornDiagnostics.lua")
local function GearEvents(trigger)
	local db = SurvivorUIRebornDiagnostics
	local results = {}
	if not db or not db.order[1] then return results end
	for _, event in ipairs(db.sessions[db.order[#db.order]].events) do
		if event.type == "gear_analyzer" and (not trigger or event.data.trigger == trigger) then
			table.insert(results, event.data)
		end
	end
	return results
end
local function Last(trigger)
	local events = GearEvents(trigger)
	return assert(events[#events], trigger)
end
local cvarReads = 0
function GetCVar(key)
	cvarReads = cvarReads + 1
	if key == "azsZone" then return "12" end
	if key == "azsDifficulty" then return "1" end
	if key == "azsModeShown" then error("PrivateCVarError") end
end
local rawArmor = { { slot = "0", rarity = "4", stars = "1", name = "PrivateItemText", icon = "PrivateIcon" } }
AZS_ZONE, AZS_ARMOR = {}, rawArmor
handlers.AZSARMOR()
Zone("dalaran", 0, "warlock", "azs:r00000001")
AZS_ZONE.map, AZS_ZONE.hero = 571, "PrivateHeroText"
Armor(rawArmor)
assert(#GearEvents() == 0 and cvarReads == 0, "recording off avoids diagnostic projection and CVar reads")

local priorCommands = #commands
local session = assert(SurvivorUI_RebornRecordStart())
assert(#commands == priorCommands + 1 and commands[#commands] == "sync")
assert(SurvivorUI_RebornRecordStart() == session and #commands == priorCommands + 1)
local initial = Last("record_start")
assert(initial.ordering.world < initial.ordering.zone and initial.ordering.zone < initial.ordering.armor)
assert(initial.ordering.associatedArmor == initial.ordering.armor)
assert(initial.resolution.map == "unknown_campaign_key" and initial.resolution.difficulty == "ready")
assert(initial.resolution.equipment == "ready" and not initial.resolution.saveBaseline)
assert(initial.resolution.planA == "hub_without_campaign_target" and initial.resolution.planB == "hub_without_campaign_target")
assert(initial.armor.source == "AZS_ARMOR" and initial.armor.rows[1].stars == 1)
assert(initial.rawZone.fields.map == 571 and not initial.rawZone.fields.hero)
assert(initial.cvarCandidates.azsDifficulty.value == "1")
assert(initial.cvarCandidates.azsMenuMapZone.status == "absent")
assert(initial.cvarCandidates.azsModeShown.status == "query_error" and not initial.cvarCandidates.azsModeShown.value)
assert(Last("sync_request").resolution.pressure == "hub_without_campaign_target")

handlers.AZSZONE("zone=dalaran;dt=0;heroic=0;hub=1;selected_zone=naxx;selected_tier=1;owner_token=PrivateTokenText")
local zoneEvent = Last("AZSZONE")
assert(zoneEvent.wireZone.fields.dt == "0" and zoneEvent.rawZone.fields.dt == 0, "wire and parsed representations are independent")
assert(zoneEvent.wireZone.candidates.selected_zone == "naxx" and zoneEvent.wireZone.candidates.selected_tier == "1")
assert(not zoneEvent.wireZone.candidates.owner_token and zoneEvent.resolution.map == "unknown_campaign_key")
Armor(rawArmor)
local armorCount = #GearEvents("AZSARMOR")
Armor(rawArmor)
assert(#GearEvents("AZSARMOR") == armorCount, "equivalent replays do not grow the recorder")
AZS_GEAR = {}
handlers.AZSGEAR("")
local native = SurvivorUIRebornDiagnostics.sessions[session].events
local jewelry = native[#native]
assert(jewelry.type == "native_gear" and jewelry.data.source == "AZS_GEAR" and #jewelry.data.rows == 0)
assert(SurvivorUI_RebornGearOpen("show") and Last("open").resolution.equipment == "ready")

WorldEvent()
local boundary = Last("world_enter")
assert(boundary.invalidation == "world_enter" and not boundary.resolution.armorAssociated)
Armor(rawArmor)
assert(Last("AZSARMOR").resolution.armorDisposition == "armor_before_zone")
Zone("naxx", 1, "warlock", "azs:r00000002")
Armor({})
local empty = Last("AZSARMOR")
assert(empty.resolution.equipment == "known_empty" and empty.resolution.pressure == "ready" and empty.resolution.saveBaseline)
assert(empty.resolution.planA == "ready" and empty.resolution.planB == "ready")
assert(empty.ordering.zone > empty.ordering.world and empty.ordering.armor > empty.ordering.zone)
local bossHit = maps.naxx[6]
maps.naxx[6] = nil
Zone("naxx", 1, "warlock", "azs:r00000003")
Armor({})
local partialDiagnosis = Last("AZSARMOR").resolution
assert(partialDiagnosis.pressure == "partial_pressure" and partialDiagnosis.planA == "ready"
	and partialDiagnosis.planB == "ready" and partialDiagnosis.saveBaseline)
maps.naxx[6] = bossHit
AZS_ZONE.dt = nil
handlers.AZSZONE()
assert(Last("AZSZONE").resolution.difficulty == "missing_dt")
AZS_ZONE.dt = "Normal"
handlers.AZSZONE()
assert(Last("AZSZONE").resolution.difficulty == "invalid_dt")
AZS_ZONE.dt, AZS_ZONE.heroic = 1, 2
handlers.AZSZONE()
assert(Last("AZSZONE").resolution.difficulty == "heroic_mismatch")
local function AssertNoPrivate(value)
	if type(value) == "table" then
		for key, item in pairs(value) do AssertNoPrivate(key); AssertNoPrivate(item) end
	elseif type(value) == "string" then
		assert(not string.find(value, "Private", 1, true))
	end
end
AssertNoPrivate(GearEvents())
assert(SurvivorUI_RebornRecordStop() == session)
local controlsBefore = #commands
WorldEvent()
AZS_ZONE = {}
assert(SurvivorUI_RebornRecordStart())
assert(#commands == controlsBefore, "auto recording before zone arrival leaves native entry sync alone")
assert(SurvivorUI_RebornGearOpen("show") and #commands == controlsBefore + 1)
assert(SurvivorUI_RebornGearOpen("show") and #commands == controlsBefore + 1)
SurvivorUI_RebornRecordStop()
print("PASS: gear arithmetic, both constraints, oracle, snapshot isolation, previews, and runtime lifecycle")
