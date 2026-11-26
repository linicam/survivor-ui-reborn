-- Shared equipment evaluation, acquisition quotes and bounded configuration search.
if SurvivorUI_Standby or not SurvivorUI_RebornGearModel then return end

local Gear = SurvivorUI_RebornGearModel
local Planner = { version = 2, data = "Reborn 0.7.4 / zones-v1 21071e86fee66ca7", tolerance = 0.000001 }
SurvivorUI_RebornGearPlanner = Planner
local EPS = Planner.tolerance
local PACK_TIER = { exotic = 2, mythic = 3, elementium = 4 }
local EFFECTS = {
	["+{v}% gold, +{v2}% pickup range"] = { "gold", "pickup" },
	["{v}% chance for an ability to strike twice"] = { "echo" },
	["+{v}% critical damage"] = { "crit_damage" },
}

function Planner.Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = Planner.Copy(item) end
	return copy
end

local function SameNumbers(before, after)
	if type(before) ~= "table" or type(after) ~= "table" then return false end
	for key, value in pairs(before) do
		if type(value) ~= "number" or type(after[key]) ~= "number" or math.abs(value - after[key]) > EPS then return false end
	end
	for key in pairs(after) do if before[key] == nil then return false end end
	return true
end

function Planner.SamePiece(a, b)
	return a and b and a.slot == b.slot and a.tier == b.tier and a.stars == b.stars
end

function Planner.Class(catalog, key)
	for _, class in ipairs(catalog.native.classes or {}) do
		if class.key == key then return class end
	end
end

function Planner.Slots(catalog, class, pieces)
	local worn, out = {}, {}
	for _, piece in ipairs(pieces) do worn[piece.slot] = true end
	local native = Planner.Class(catalog, class)
	local weapons = native and native.gear and native.gear.weapons
	local double = weapons and weapons[2]
	for _, tier in ipairs(catalog.native.gearTiers or {}) do
		local icons = tier.weapon_icons and tier.weapon_icons[class]
		if icons and icons[2] then double = true end
	end
	for index = 0, 10 do
		local key = catalog.pieces.slots[index].key
		if index < 8 or worn[key] or (native and ((index == 8 and class ~= "hunter")
			or (index == 10 and class == "hunter") or (index == 9 and double))) then
			table.insert(out, key)
		end
	end
	return out
end

function Planner.Tiers(catalog)
	local out = {}
	for key, data in pairs(catalog.tiers) do
		if type(data.rank) == "number" then table.insert(out, key) end
	end
	table.sort(out, function(a, b) return catalog.tiers[a].rank < catalog.tiers[b].rank end)
	return out
end

function Planner.DropTiers(catalog, maps, page)
	if not page then return end
	local out = {}
	for _, data in pairs(maps) do
		if data[7] == page and catalog.tiers[data[8]] then out[data[8]] = true end
	end
	for key, pack in pairs(PACK_TIER) do
		if pack == page and catalog.tiers[key] and catalog.tiers[key].pair == 5 then out[key] = true end
	end
	if next(out) then return out end
end

function Planner.Replace(pieces, slot, tier, stars)
	local out = {}
	for _, piece in ipairs(pieces) do
		if piece.slot ~= slot then
			table.insert(out, piece)
		elseif tier then
			table.insert(out, { slot = slot, tier = tier, stars = stars,
				icon = piece.tier == tier and piece.icon or nil,
				name = piece.tier == tier and piece.name or nil, set = piece.tier == tier and piece.set or nil })
			tier = nil
		end
	end
	if tier then table.insert(out, { slot = slot, tier = tier, stars = stars }) end
	return out
end

function Planner.Quote(catalog, before, after, drops)
	if not after then return { gold = 0, kind = "removed" } end
	local same = before and before.tier == after.tier
	local start = same and before.stars or 0
	local quote = { gold = 0, kind = same and "stars" or (drops and drops[after.tier] and "farm" or "theoretical") }
	if same and after.stars < start then quote.kind = "downgrade" end
	if not same and before and catalog.tiers[before.tier].rank >= catalog.tiers.legendary.rank then
		quote.progression = true
	end
	for star = start + 1, after.stars do
		local cost, evidence = Gear.StarQuote(catalog, after.slot, after.tier, star)
		if not cost then quote.unknown = true
		else
			quote.gold = quote.gold + cost
			quote.estimated = quote.estimated or evidence == "estimated"
		end
	end
	return quote
end

local function BySlot(pieces)
	local out = {}
	for _, piece in ipairs(pieces) do out[piece.slot] = piece end
	return out
end
Planner.BySlot = BySlot

function Planner.Changes(catalog, actual, simulated, drops)
	local previous, target = BySlot(actual), BySlot(simulated)
	local rows, summary = {}, { gold = 0 }
	for index = 0, 10 do
		local slot = catalog.pieces.slots[index].key
		local before, after = previous[slot], target[slot]
		if (before or after) and not Planner.SamePiece(before, after) then
			local quote = Planner.Quote(catalog, before, after, drops)
			summary.gold = summary.gold + quote.gold
			summary.unknown = summary.unknown or quote.unknown
			summary.acquisition = summary.acquisition or quote.kind == "farm" or quote.kind == "theoretical"
			summary.estimated = summary.estimated or quote.estimated
			table.insert(rows, { slot = slot, before = before, after = after, quote = quote })
		end
	end
	return rows, summary
end

local function Capacity(classHealth, damage, health, armor)
	-- Standard 60% damage-reduction cap. The Warrior Titan exception and
	-- unobserved talents are outside this equipment-only proxy.
	return 1 + damage, classHealth and (classHealth + health) / (1 - math.min(armor, 0.60))
end

function Planner.Evaluate(catalog, class, pieces)
	local rows, used = {}, {}
	for i, piece in ipairs(pieces) do
		if type(piece) ~= "table" or not piece.slot or used[piece.slot] then return end
		used[piece.slot] = true
		local stats = Gear.Piece(catalog, class, piece.slot, piece.tier, piece.stars)
		if not stats then return end
		rows[i] = { slot = piece.slot, tier = piece.tier, stars = piece.stars, stats = stats }
	end
	local stats, sets = Gear.Totals(catalog, class, rows)
	local opaque = {}
	for tier, bonuses in pairs(sets or {}) do
		for _, bonus in ipairs(bonuses) do
			local effect = bonus.pieces == 4 and not bonus.needs and EFFECTS[bonus.template]
			if effect and tonumber(bonus.values.v) and (not effect[2] or tonumber(bonus.values.v2)) then
				stats[effect[1]] = (stats[effect[1]] or 0) + tonumber(bonus.values.v) / 100
				if effect[2] then stats[effect[2]] = (stats[effect[2]] or 0) + tonumber(bonus.values.v2) / 100 end
			end
			if not effect or effect[1] ~= "gold" then
				opaque[tier] = opaque[tier] or {}
				table.insert(opaque[tier], bonus)
			end
		end
	end
	local native = Planner.Class(catalog, class)
	local base = native and native.health
	local output, survival = Capacity(base, stats.damage or 0, stats.hp or 0, stats.armor or 0)
	return { stats = stats, sets = sets, opaque = opaque, output = output, survival = survival, health = base }
end

function Planner.Reference(context, result)
	if not result or not result.sets or not context.demand or not context.demand.output
		or not context.demand.survival or not result.survival then return end
	return Planner.Copy({ version = Planner.version, data = Planner.data, build = context.build, at = context.at,
		class = context.class, zone = context.zone, level = context.level, heroic = context.heroic,
		modifiers = context.modifiers, pieces = context.pieces, stats = result.stats, sets = result.sets,
		demand = context.demand, output = result.output, survival = result.survival })
end

function Planner.CheckReference(saved, context, catalog, maps)
	if type(saved) ~= "table" then return nil, "missing" end
	if saved.version ~= Planner.version or saved.data ~= Planner.data or saved.build ~= context.build
		or saved.class ~= context.class or type(saved.pieces) ~= "table" or type(saved.sets) ~= "table" then
		return nil, "incompatible"
	end
	local demand = SurvivorUI_RebornAnalysisModel.GearDemand(maps[saved.zone], saved.level)
	local eval = Planner.Evaluate(catalog, saved.class, saved.pieces)
	if not SameNumbers(demand, saved.demand) or not eval or not eval.sets or not SameNumbers(saved.stats, eval.stats)
		or not SameNumbers({ output = saved.output, survival = saved.survival },
			{ output = eval.output, survival = eval.survival }) then return nil, "incompatible" end
	for tier, bonuses in pairs(eval.sets) do
		local old = saved.sets[tier]
		if type(old) ~= "table" or table.getn(old) ~= table.getn(bonuses) then return nil, "incompatible" end
		for i, bonus in ipairs(bonuses) do
			local value = old[i]
			if type(value) ~= "table" or value.text ~= bonus.text or value.strong ~= bonus.strong
				or value.pieces ~= bonus.pieces or value.needs ~= bonus.needs then return nil, "incompatible" end
		end
	end
	for tier in pairs(saved.sets) do if not eval.sets[tier] then return nil, "incompatible" end end
	return saved
end

function Planner.Difficulty(demand, result, reference)
	if not demand or not result or not reference then return {} end
	local output = result.output and demand.output and 100 * (demand.output / reference.demand.output) * (reference.output / result.output)
	local survival = result.survival and demand.survival and reference.survival
		and 100 * (demand.survival / reference.demand.survival) * (reference.survival / result.survival)
	if output and math.abs(output - 100) < EPS then output = 100 end
	if survival and math.abs(survival - 100) < EPS then survival = 100 end
	return { output = output, survival = survival, combined = output and survival and math.max(output, survival) }
end

local function Better(current, gold, best)
	local reached = current <= 100
	if (best.after <= 100) ~= reached then return reached end
	if not reached and math.abs(current - best.after) > EPS then return current < best.after end
	return gold < best.gold
end

function Planner.Search(catalog, context, actual, reference, allowed, limit)
	local current = Planner.Difficulty(context.demand, actual, reference).combined
	if not current or not actual.sets then return end
	local result = { after = current, gold = 0, pieces = Planner.Copy(context.pieces), complete = current <= 100, visited = 0 }
	if result.complete then return result end
	local requirements = Gear.SetRequirements(actual.opaque, catalog.native.setRules)
	local groups, tiers = {}, Planner.Tiers(catalog)
	local seed, seedGold = {}, 0
	local worn = BySlot(context.pieces)
	for _, slot in ipairs(Planner.Slots(catalog, context.class, context.pieces)) do
		local piece = worn[slot]
		if piece or allowed then
			local group = {}
			local sameTier
			if not piece then table.insert(group, { gold = 0, damage = 0, hp = 0, armor = 0 }) end
			for _, tier in ipairs(tiers) do
				local same = piece and tier == piece.tier
				if same or (allowed and allowed[tier]) then
					for star = same and piece.stars or 0, catalog.pieces.scale.top do
						local candidate = same and star == piece.stars and piece or { slot = slot, tier = tier, stars = star }
						local quote = Planner.Quote(catalog, piece, candidate, allowed)
						if quote.unknown then result.excluded = true
						else
							local s = Gear.Piece(catalog, context.class, slot, tier, star)
							table.insert(group, { piece = candidate, gold = quote.gold,
								damage = s.damage or 0, hp = s.hp or 0, armor = s.armor or 0 })
							if same then sameTier = group[table.getn(group)] end
						end
					end
				end
			end
			table.sort(group, function(a, b)
				if a.gold ~= b.gold then return a.gold < b.gold end
				if not a.piece or not b.piece then return not a.piece end
				local ar, br = catalog.tiers[a.piece.tier].rank, catalog.tiers[b.piece.tier].rank
				if ar ~= br then return ar < br end
				return a.piece.stars < b.piece.stars
			end)
			table.insert(groups, group)
			if sameTier then
				table.insert(seed, sameTier.piece)
				seedGold = seedGold + sameTier.gold
			end
		end
	end
	-- The most upgraded currently worn pieces give both searches a comparable
	-- starting point, including when the replacement space exceeds its budget.
	local seedPressure = Planner.Difficulty(context.demand, Planner.Evaluate(catalog, context.class, seed), reference).combined
	if seedPressure and Better(seedPressure, seedGold, result) then
		result.after, result.gold, result.pieces = seedPressure, seedGold, Planner.Copy(seed)
	end

	-- Optimistic suffix bounds may mix incompatible choices. This can only
	-- improve the bound because all three modeled piece stats are monotone.
	local suffix = { [table.getn(groups) + 1] = { damage = 0, hp = 0, armor = 0, counts = {} } }
	local function CountsFor(group, req)
		for _, choice in ipairs(group) do
			local item = choice.piece
			if item and catalog.slots[item.slot].index < 8 and item.tier == req.tier and item.stars >= req.stars then return 1 end
		end
		return 0
	end
	for i = table.getn(groups), 1, -1 do
		local damage, hp, armor, counts = 0, 0, 0, {}
		for _, choice in ipairs(groups[i]) do
			damage, hp, armor = math.max(damage, choice.damage), math.max(hp, choice.hp), math.max(armor, choice.armor)
		end
		local rest = suffix[i + 1]
		for j, req in ipairs(requirements) do counts[j] = (rest.counts[j] or 0) + CountsFor(groups[i], req) end
		suffix[i] = { damage = rest.damage + damage, hp = rest.hp + hp, armor = rest.armor + armor, counts = counts }
	end

	result.worker = coroutine.create(function()
		local path, counts = {}, {}
		local function Visit(i, gold, damage, hp, armor)
			if result.visited >= limit then return false end
			result.visited = result.visited + 1
			coroutine.yield()
			local rest = suffix[i]
			for j, req in ipairs(requirements) do
				if (counts[j] or 0) + (rest.counts[j] or 0) < req.count then return true end
			end
			if result.after <= 100 and gold >= result.gold then return true end
			local output, survival = Capacity(actual.health, damage + rest.damage, hp + rest.hp, armor + rest.armor)
			local lower = Planner.Difficulty(context.demand, { output = output, survival = survival }, reference).combined
			local cutoff = result.after <= 100 and 100 or result.after
			if lower > cutoff + EPS then return true end
			if not groups[i] then
				if Better(lower, gold, result) then
					result.after, result.gold, result.pieces = lower, gold, Planner.Copy(path)
				end
				return true
			end
			for _, choice in ipairs(groups[i]) do
				local item = choice.piece
				if item then table.insert(path, item) end
				for j, req in ipairs(requirements) do
					if item and catalog.slots[item.slot].index < 8 and item.tier == req.tier and item.stars >= req.stars then
						counts[j] = (counts[j] or 0) + 1
					end
				end
				local done = Visit(i + 1, gold + choice.gold, damage + choice.damage, hp + choice.hp, armor + choice.armor)
				for j, req in ipairs(requirements) do
					if item and catalog.slots[item.slot].index < 8 and item.tier == req.tier and item.stars >= req.stars then counts[j] = counts[j] - 1 end
				end
				if item then table.remove(path) end
				if not done then return false end
			end
			return true
		end
		result.complete = Visit(1, 0, 0, 0, 0)
	end)
	return result
end

function Planner.Step(result, batch, deadline)
	for i = 1, batch do
		if deadline and deadline() then return end
		local ok, err = coroutine.resume(result.worker)
		if not ok or coroutine.status(result.worker) == "dead" then
			result.worker, result.error = nil, not ok and err or nil
			return true
		end
	end
end
