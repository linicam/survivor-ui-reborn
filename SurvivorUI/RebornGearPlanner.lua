-- Shared equipment evaluation, acquisition quotes and bounded configuration search.
if SurvivorUI_Standby or not SurvivorUI_RebornGearModel then return end

local Gear = SurvivorUI_RebornGearModel
local Planner = { schema = 1, version = 3, data = "Reborn 0.7.4 / zones-v1 21071e86fee66ca7", tolerance = 0.000001 }
SurvivorUI_RebornGearPlanner = Planner
local EPS = Planner.tolerance
local ARMOR_CAP = 0.60
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

function Planner.Token(value)
	if type(value) == "number" then value = tostring(value) end
	if type(value) ~= "string" then return end
	local token = string.lower((string.gsub(value, "^%s*(.-)%s*$", "%1")))
	if token ~= "" then return token end
end

function Planner.Affixes(value)
	-- The native wire is comma-delimited. Accept an equivalent list without
	-- carrying mutable tables or their addresses into context identity.
	local found, names = {}, {}
	local function Add(raw)
		if type(raw) ~= "string" then return end
		for token in string.gmatch(raw, "[^,]+") do
			local name = Planner.Token(token)
			if name and not found[name] then found[name] = true; table.insert(names, name) end
		end
	end
	if type(value) == "table" then
		for _, raw in ipairs(value) do Add(raw) end
	else Add(value) end
	table.sort(names)
	return table.concat(names, ",")
end

function Planner.Scope(level, modifiers)
	local mode = Planner.Token(modifiers and modifiers.mode)
	if mode and mode ~= "campaign" and mode ~= "standard" and mode ~= "hub" then return "unsupported" end
	local challenge = Planner.Token(modifiers and modifiers.challenge)
	local affixes = Planner.Affixes(modifiers and modifiers.affixes)
	-- 'aff' is legacy metadata. The named affix list and Heroic tier carry
	-- the documented rules, including built-in Heroic modifiers.
	if (level and level > 0) or affixes ~= "" or (challenge and challenge ~= "0") then return "standard-only" end
	return "standard"
end

function Planner.SamePiece(a, b)
	return a and b and a.slot == b.slot and a.tier == b.tier and a.stars == b.stars
end

function Planner.Class(catalog, key)
	return catalog.classes[key]
end

function Planner.Slots(catalog, class)
	local out = {}
	for index = 0, 10 do
		local key = catalog.pieces.slots[index].key
		if Gear.ValidSlot(catalog, class, key) then table.insert(out, key) end
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

function Planner.Quote(catalog, before, after, drops, class)
	if not after then return { gold = 0, kind = "removed" } end
	local same = before and before.tier == after.tier
	local start = same and before.stars or 0
	local farm = drops and drops[after.tier] and Gear.DropSlot(catalog, class, after.slot, after.tier)
	local quote = { gold = 0, kind = same and "stars" or (farm and "farm" or "theoretical") }
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

function Planner.Changes(catalog, actual, simulated, drops, class)
	local previous, target = BySlot(actual), BySlot(simulated)
	local rows, summary = {}, { gold = 0 }
	for index = 0, 10 do
		local slot = catalog.pieces.slots[index].key
		local before, after = previous[slot], target[slot]
		if (before or after) and not Planner.SamePiece(before, after) then
			local quote = Planner.Quote(catalog, before, after, drops, class)
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
	return 1 + damage, classHealth and (classHealth + health) / (1 - math.min(armor, ARMOR_CAP))
end

function Planner.Evaluate(catalog, class, pieces)
	if not catalog.classes[class] or not Gear.ListSize(pieces, 11) then return end
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
	return Planner.Copy({ schema = Planner.schema, version = Planner.version, data = Planner.data, build = context.build, at = context.at,
		class = context.class, zone = context.zone, level = context.level, heroic = context.heroic,
		modifiers = context.modifiers, pieces = context.pieces, stats = result.stats, sets = result.sets,
		demand = context.demand, output = result.output, survival = result.survival })
end

function Planner.CheckReference(saved, context, catalog, maps)
	if saved == nil then return nil, "missing" end
	if type(saved) ~= "table" or (saved.schema ~= Planner.schema and not (saved.schema == nil and saved.version == 2))
		or saved.class ~= context.class or type(saved.zone) ~= "string" or type(saved.level) ~= "number"
		or saved.level ~= math.floor(saved.level) or (saved.heroic ~= nil and saved.heroic ~= saved.level)
		or (saved.modifiers ~= nil and type(saved.modifiers) ~= "table") then
		return nil, "incompatible"
	end
	local scope = Planner.Scope(saved.level, saved.modifiers)
	local demand = SurvivorUI_RebornAnalysisModel.GearDemand(maps[saved.zone], saved.level)
	local eval = Planner.Evaluate(catalog, saved.class, saved.pieces)
	if scope == "unsupported" or not demand or not demand.output or not demand.survival
		or not eval or not eval.sets or not eval.survival then return nil, "incompatible" end
	local changed = not SameNumbers(demand, saved.demand)
		or not SameNumbers({ output = eval.output, survival = eval.survival }, { output = saved.output, survival = saved.survival })
	return { demand = demand, output = eval.output, survival = eval.survival, scope = scope }, changed and "updated" or nil
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

local function Protects(catalog, item, req)
	return item and item.tier == req.tier and item.stars >= req.stars and catalog.slots[item.slot].index < 8
end

local function Dominates(a, b)
	-- Same acquisition path and contribution to protected sets. Both
	-- capabilities are monotone in these three gear attributes.
	return a.tier == b.tier and a.protection == b.protection and a.gold <= b.gold
		and a.damage >= b.damage and a.hp >= b.hp and a.armor >= b.armor
end

local function RemoveDominated(group)
	local result = {}
	for _, choice in ipairs(group) do
		local dominated = false
		for _, other in ipairs(result) do
			if Dominates(other, choice) then dominated = true; break end
		end
		if not dominated then
			for i = table.getn(result), 1, -1 do
				if Dominates(choice, result[i]) then table.remove(result, i) end
			end
			table.insert(result, choice)
		end
	end
	return result
end

local function MaxStats(out, choice)
	out.damage = math.max(out.damage, choice.damage)
	out.hp = math.max(out.hp, choice.hp)
	out.armor = math.max(out.armor, choice.armor)
end

local function AddStats(a, b)
	return { damage = a.damage + b.damage, hp = a.hp + b.hp, armor = a.armor + b.armor }
end

local function BoundSuffix(groups, requirements, survivalNeed, yield)
	local zero = { damage = 0, hp = 0, armor = 0 }
	local terminal = { stats = zero, protected = {}, free = { 0, 0, 0 }, rate = { 0, 0, 0 } }
	for j in ipairs(requirements) do terminal.protected[j] = { [0] = zero } end
	local suffix = { [table.getn(groups) + 1] = terminal }
	for i = table.getn(groups), 1, -1 do
		if yield then yield() end
		local maximum = { damage = 0, hp = 0, armor = 0 }
		local matching, free, rate = {}, { 0, 0, 0 }, { 0, 0, 0 }
		for _, choice in ipairs(groups[i]) do
			MaxStats(maximum, choice)
			local j = choice.protection
			if j then
				matching[j] = matching[j] or { damage = 0, hp = 0, armor = 0 }
				MaxStats(matching[j], choice)
			end
			if choice.gold == 0 then
				free[1] = math.max(free[1], choice.damage)
				free[2] = math.max(free[2], choice.hp + survivalNeed * choice.armor)
				free[3] = math.max(free[3], choice.hp)
			end
		end
		for _, choice in ipairs(groups[i]) do
			if choice.gold > 0 then
				rate[1] = math.max(rate[1], (choice.damage - free[1]) / choice.gold)
				rate[2] = math.max(rate[2], (choice.hp + survivalNeed * choice.armor - free[2]) / choice.gold)
				rate[3] = math.max(rate[3], (choice.hp - free[3]) / choice.gold)
			end
		end
		local rest = suffix[i + 1]
		local stats = AddStats(maximum, rest.stats)
		local bound = { stats = stats, protected = {}, free = free, rate = rate }
		for k = 1, 3 do
			free[k] = free[k] + rest.free[k]
			rate[k] = math.max(rate[k], rest.rate[k])
		end
		for j, req in ipairs(requirements) do
			local prior, constrained = rest.protected[j], { [0] = stats }
			for n = 1, req.count do
				local best = prior[n] and AddStats(maximum, prior[n])
				local included = matching[j] and prior[n - 1] and AddStats(matching[j], prior[n - 1])
				if best and included then MaxStats(best, included) end
				constrained[n] = best or included
			end
			bound.protected[j] = constrained
		end
		suffix[i] = bound
	end
	return suffix
end

local function RemainingCost(bound, index, deficit)
	local gap = deficit - bound.free[index]
	if gap <= 0 then return 0 end
	local rate = bound.rate[index]
	return rate > 0 and gap / rate or math.huge
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
	for _, slot in ipairs(Planner.Slots(catalog, context.class)) do
		local piece = worn[slot]
		if piece or allowed then
			local group = {}
			local sameTier
			if not piece then table.insert(group, { gold = 0, damage = 0, hp = 0, armor = 0 }) end
			for _, tier in ipairs(tiers) do
				local same = piece and tier == piece.tier
				if same or (allowed and allowed[tier] and Gear.DropSlot(catalog, context.class, slot, tier)) then
					for star = same and piece.stars or 0, catalog.pieces.scale.top do
						local candidate = same and star == piece.stars and piece or { slot = slot, tier = tier, stars = star }
						local quote = Planner.Quote(catalog, piece, candidate, allowed, context.class)
						if quote.unknown then result.excluded = true
						else
							local s = Gear.Piece(catalog, context.class, slot, tier, star)
							local protection
							for j, req in ipairs(requirements) do
								if Protects(catalog, candidate, req) then protection = j; break end
							end
							table.insert(group, { piece = candidate, gold = quote.gold, tier = tier, protection = protection,
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
			table.insert(groups, RemoveDominated(group))
			local groupIndex = table.getn(groups)
			local least, most = math.huge, 0
			for _, choice in ipairs(groups[groupIndex]) do
				least, most = math.min(least, choice.damage), math.max(most, choice.damage)
			end
			groups[groupIndex].spread, groups[groupIndex].order = most - least, groupIndex
			if sameTier then
				table.insert(seed, sameTier.piece)
				seedGold = seedGold + sameTier.gold
			end
		end
	end
	table.sort(groups, function(a, b)
		if a.spread == b.spread then return a.order < b.order end
		return a.spread > b.spread
	end)
	-- The most upgraded currently worn pieces give both searches a comparable
	-- starting point, including when the replacement space exceeds its budget.
	local seedPressure = Planner.Difficulty(context.demand, Planner.Evaluate(catalog, context.class, seed), reference).combined
	if seedPressure and Better(seedPressure, seedGold, result) then
		result.after, result.gold, result.pieces = seedPressure, seedGold, Planner.Copy(seed)
	end

	-- These relaxed thresholds include the numerical tolerance at 100%.
	-- EHP >= E requires both HP + E * armor >= E - base and HP >= .4 * E - base.
	result.worker = coroutine.create(function()
		local function Demands(cutoff)
			local rate = 100 / (cutoff + EPS)
			return context.demand.output / reference.demand.output * reference.output * rate - 1,
				context.demand.survival / reference.demand.survival * reference.survival * rate
		end
		local outputNeed, survivalNeed = Demands(100)
		local suffix = BoundSuffix(groups, requirements, survivalNeed, coroutine.yield)
		local path, counts = {}, {}
		local function Bound(i, damage, hp, armor)
			local rest = suffix[i]
			local d, h, a = rest.stats.damage, rest.stats.hp, rest.stats.armor
			for j, req in ipairs(requirements) do
				local need = math.max(0, req.count - (counts[j] or 0))
				local constrained = rest.protected[j][need]
				if not constrained then return end
				d, h, a = math.min(d, constrained.damage), math.min(h, constrained.hp), math.min(a, constrained.armor)
			end
			local output, survival = Capacity(actual.health, damage + d, hp + h, armor + a)
			return Planner.Difficulty(context.demand, { output = output, survival = survival }, reference).combined
		end
		local function Count(choice, delta)
			local j = choice.protection
			if j then counts[j] = (counts[j] or 0) + delta end
		end

		-- Choose one legal full seed using optimistic child bounds. The same
		-- suffix data rules out choices that strand an active set threshold.
		local d, h, a, cost = 0, 0, 0, 0
		local selected = {}
		local terminal = table.getn(groups) + 1
		for i, group in ipairs(groups) do
			local best, bestBound
			for _, choice in ipairs(group) do
				coroutine.yield()
				Count(choice, 1)
				local lower = Bound(i + 1, d + choice.damage, h + choice.hp, a + choice.armor)
				Count(choice, -1)
				if lower and (not bestBound or lower < bestBound - EPS) then best, bestBound = choice, lower end
			end
			if not best then break end
			selected[i] = best
			Count(best, 1)
			d, h, a, cost = d + best.damage, h + best.hp, a + best.armor, cost + best.gold
		end
		local pressure = selected[terminal - 1] and Bound(terminal, d, h, a)
		if pressure and pressure <= 100 then
			-- Strip unnecessary expense from the feasible seed while preserving
			-- the target and all protected sets. This is an incumbent only.
			for i, group in ipairs(groups) do
				local prior = selected[i]
				for _, choice in ipairs(group) do
					if choice.gold >= prior.gold then break end
					coroutine.yield()
					Count(prior, -1)
					Count(choice, 1)
					local nd, nh, na = d - prior.damage + choice.damage, h - prior.hp + choice.hp, a - prior.armor + choice.armor
					local candidate = Bound(terminal, nd, nh, na)
					if candidate and candidate <= 100 then
						selected[i], d, h, a, pressure = choice, nd, nh, na, candidate
						cost = cost - prior.gold + choice.gold
						break
					end
					Count(choice, -1)
					Count(prior, 1)
				end
			end
		end
		if pressure and Better(pressure, cost, result) then
			for _, choice in ipairs(selected) do if choice.piece then table.insert(path, choice.piece) end end
			result.after, result.gold, result.pieces = pressure, cost, Planner.Copy(path)
		end
		path, counts = {}, {}
		local root = Bound(1, 0, 0, 0)
		local priceTie = root and root > 100 and root >= result.after - EPS
		if priceTie then
			outputNeed, survivalNeed = Demands(root)
			suffix = BoundSuffix(groups, requirements, survivalNeed, coroutine.yield)
		end

		local function Visit(i, gold, damage, hp, armor)
			if result.visited >= limit then return false end
			result.visited = result.visited + 1
			coroutine.yield()
			if result.after <= 100 and gold >= result.gold then return true end
			local lower = Bound(i, damage, hp, armor)
			if not lower then return true end
			local cutoff = result.after <= 100 and 100 or result.after
			if lower > cutoff + EPS then return true end
			if result.after <= 100 or priceTie then
				local rest = suffix[i]
				local need = math.max(RemainingCost(rest, 1, outputNeed - damage),
					RemainingCost(rest, 2, survivalNeed - actual.health - hp - survivalNeed * armor),
					RemainingCost(rest, 3, (1 - ARMOR_CAP) * survivalNeed - actual.health - hp))
				if gold + need > result.gold + EPS then return true end
			elseif lower > 100 and lower >= result.after and gold >= result.gold then
				return true
			end
			if not groups[i] then
				if priceTie and lower > root + EPS then return true end
				if Better(lower, gold, result) then
					result.after, result.gold, result.pieces = lower, gold, Planner.Copy(path)
				end
				return true
			end
			for _, choice in ipairs(groups[i]) do
				local item = choice.piece
				if item then table.insert(path, item) end
				Count(choice, 1)
				local done = Visit(i + 1, gold + choice.gold, damage + choice.damage, hp + choice.hp, armor + choice.armor)
				Count(choice, -1)
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
