-- Shared equipment evaluation, acquisition quotes and bounded configuration search.
if SurvivorUI_Standby or not SurvivorUI_RebornGearModel then return end

local Gear = SurvivorUI_RebornGearModel
local Planner = { schema = 1, version = 4, data = "Reborn 0.7.4 / zones-v1 21071e86fee66ca7", tolerance = 0.000001 }
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
		or not result.output then return end
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
	if scope == "unsupported" or not demand or not demand.output
		or not eval or not eval.sets or not eval.output then return nil, "incompatible" end
	local changed = not SameNumbers(demand, saved.demand)
		or not SameNumbers({ output = eval.output, survival = eval.survival }, { output = saved.output, survival = saved.survival })
	return { demand = demand, output = eval.output, survival = eval.survival, scope = scope }, changed and "updated" or nil
end

local function Pressure(ratio, reference, capacity)
	local value = 100 * ratio * (reference / capacity)
	return math.abs(value - 100) < EPS and 100 or value
end

function Planner.Difficulty(demand, result, reference)
	if not demand or not result or not reference then return {} end
	local output = result.output and demand.output and reference.demand.output and reference.output
		and Pressure(demand.output / reference.demand.output, reference.output, result.output)
	local survival = result.survival and demand.survival and reference.survival and reference.demand.survival
		and Pressure(demand.survival / reference.demand.survival, reference.survival, result.survival)
	return { output = output, survival = survival }
end

local function Cheaper(gold, acquisitionRank, otherGold, otherRank)
	return gold < otherGold or (gold == otherGold and acquisitionRank < otherRank)
end

local function Protects(catalog, item, req)
	return item and item.tier == req.tier and item.stars >= req.stars and catalog.slots[item.slot].index < 8
end

local function Dominates(a, b)
	-- Choices in the same slot and tier share the acquisition rank.
	return a.tier == b.tier and a.protection == b.protection and a.gold <= b.gold and a.damage >= b.damage
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

local function Candidates(catalog, context, allowed, requirements, result)
	local groups, tiers = {}, Planner.Tiers(catalog)
	local worn, slots = BySlot(context.pieces), Planner.Slots(catalog, context.class)
	-- One worn replacement ranks after any number of newly filled slots.
	local replacementRank = table.getn(slots) + 1
	for index, slot in ipairs(slots) do
		local piece = worn[slot]
		if piece or allowed then
			local group = { priced = {}, legal = {}, top = {}, order = index }
			local highest
			if not piece then
				local empty = { gold = 0, acquisitionRank = 0, damage = 0 }
				group.priced[1], group.legal[1], highest = empty, empty, empty
			end
			local wornRank = piece and catalog.tiers[piece.tier].rank
			for _, tier in ipairs(tiers) do
				local same = piece and tier == piece.tier
				local couldDrop = allowed and allowed[tier] and (not wornRank or catalog.tiers[tier].rank > wornRank)
				local canDrop = couldDrop and Gear.DropSlot(catalog, context.class, slot, tier)
				if couldDrop and not canDrop then result.unverifiedDrops = true end
				if same or canDrop then
					for star = same and piece.stars or 0, catalog.pieces.scale.top do
						local item = same and star == piece.stars and piece or { slot = slot, tier = tier, stars = star }
						local quote = Planner.Quote(catalog, piece, item, allowed, context.class)
						local protection
						for j, req in ipairs(requirements) do
							if Protects(catalog, item, req) then protection = j; break end
						end
						local option = { piece = item, gold = quote.gold, tier = tier, protection = protection,
							acquisitionRank = same and 0 or (piece and replacementRank or 1),
							damage = Gear.Piece(catalog, context.class, slot, tier, star).damage or 0 }
						table.insert(group.legal, option)
						if quote.unknown then result.excluded = true
						else table.insert(group.priced, option) end
						if star == catalog.pieces.scale.top then
							highest = option
							if protection then table.insert(group.top, { piece = item, damage = option.damage,
								protection = protection, held = 1 }) end
						end
					end
				end
			end
			-- For Max Gear a below-top choice must contribute to a protected set.
			for i = table.getn(group.top), 1, -1 do
				if group.top[i].piece == highest.piece then table.remove(group.top, i) end
			end
			table.insert(group.top, 1, highest)
			table.sort(group.priced, function(a, b)
				if a.gold ~= b.gold then return a.gold < b.gold end
				if a.acquisitionRank ~= b.acquisitionRank then return a.acquisitionRank < b.acquisitionRank end
				if not a.piece then return false end
				local ar, br = catalog.tiers[a.tier].rank, catalog.tiers[b.tier].rank
				if ar ~= br then return ar < br end
				return a.piece.stars < b.piece.stars
			end)
			group.priced = RemoveDominated(group.priced)
			local least, most = math.huge, -math.huge
			for _, choice in ipairs(group.priced) do
				least, most = math.min(least, choice.damage), math.max(most, choice.damage)
			end
			group.spread = most - least
			table.insert(groups, group)
		end
	end
	return groups
end

local function SetState(requirements)
	-- Mixed-radix digits count the remaining slots for each protected tier.
	local key, stride, places = 0, 1, {}
	for i, req in ipairs(requirements) do
		places[i] = stride
		key = key + req.count * stride
		stride = stride * (req.count + 1)
	end
	local function Consume(state, choice)
		local tier = choice.protection
		local place = tier and places[tier]
		if place and math.floor(state / place) % (requirements[tier].count + 1) > 0 then return state - place end
		return state
	end
	return key, Consume
end

local function Suffix(groups, field, consume)
	local memo = {}
	local terminal = { damage = 0, held = 0 }
	local function Best(index, need)
		local group = groups[index]
		if not group then return need == 0 and terminal or false end
		memo[index] = memo[index] or {}
		local cached = memo[index][need]
		if cached ~= nil then return cached end
		coroutine.yield()
		local best = false
		for _, option in ipairs(group[field]) do
			local rest = Best(index + 1, consume(need, option))
			if rest then
				local held, damage = (option.held or 0) + rest.held, option.damage + rest.damage
				if not best or held < best.held or (held == best.held and damage > best.damage) then
					best = { held = held, damage = damage, choice = option }
				end
			end
		end
		memo[index][need] = best
		return best
	end
	return Best
end

local function ReadPath(groups, best, need, consume)
	local choices = {}
	for i in ipairs(groups) do
		local option = best(i, need).choice
		choices[i] = option
		need = consume(need, option)
	end
	return choices
end

local function Pieces(choices)
	local pieces = {}
	for _, option in ipairs(choices) do
		if option.piece then table.insert(pieces, option.piece) end
	end
	return pieces
end

local function PriceBounds(groups)
	local suffix = { [table.getn(groups) + 1] = { free = 0, rate = 0 } }
	for i = table.getn(groups), 1, -1 do
		local free = -math.huge
		for _, option in ipairs(groups[i].priced) do
			if option.gold == 0 then free = math.max(free, option.damage) end
		end
		local rest = suffix[i + 1]
		local rate = rest.rate
		for _, option in ipairs(groups[i].priced) do
			if option.gold > 0 then rate = math.max(rate, (option.damage - free) / option.gold) end
		end
		suffix[i] = { free = free + rest.free, rate = rate }
	end
	return suffix
end

local function MaxGear(groups, need, consume, catalog, context, reference, allowed)
	local choices, held = {}, 0
	if need == 0 then
		for i, group in ipairs(groups) do choices[i] = group.top[1] end
	else
		local best = Suffix(groups, "top", consume)
		local root = best(1, need)
		if not root then return end
		choices, held = ReadPath(groups, best, need, consume), root.held
	end
	local pieces = Pieces(choices)
	local evaluation = Planner.Evaluate(catalog, context.class, pieces)
	local _, quote = Planner.Changes(catalog, context.pieces, pieces, allowed, context.class)
	return { pieces = pieces, outputPressure = Planner.Difficulty(context.demand, evaluation, reference).output,
		gold = quote.gold, protectedHolds = held }
end

function Planner.Search(catalog, context, actual, reference, allowed, limit)
	local current = Planner.Difficulty(context.demand, actual, reference).output
	if not current or not actual.sets then return end
	local result = { outputPressure = current, gold = 0, acquisitionRank = 0,
		pieces = Planner.Copy(context.pieces), complete = current <= 100, visited = 0 }
	if result.complete then return result end
	local requirements = Gear.SetRequirements(actual.opaque, catalog.native.setRules)
	local groups = Candidates(catalog, context, allowed, requirements, result)
	local need, consume = SetState(requirements)
	local ratio = context.demand.output / reference.demand.output
	local function AtDamage(damage) return Pressure(ratio, reference.output, 1 + damage) end

	result.worker = coroutine.create(function()
		-- Native slot order makes equal-quality Max Gear choices reproducible.
		local nativeOrder = {}
		for i, group in ipairs(groups) do nativeOrder[i] = group end
		table.sort(groups, function(a, b)
			if a.spread == b.spread then return a.order < b.order end
			return a.spread > b.spread
		end)
		local best = Suffix(groups, "priced", consume)
		local root = assert(best(1, need), "No legal completion for the worn setup")
		local seed = ReadPath(groups, best, need, consume)
		local seedGold, seedRank = 0, 0
		for _, option in ipairs(seed) do
			seedGold, seedRank = seedGold + option.gold, seedRank + option.acquisitionRank
		end
		local seedPieces = Pieces(seed)
		local seedOutput = Planner.Difficulty(context.demand, Planner.Evaluate(catalog, context.class, seedPieces), reference).output
		if seedOutput <= 100 or seedOutput < current - EPS then
			result.outputPressure, result.gold, result.acquisitionRank, result.pieces = seedOutput, seedGold, seedRank, seedPieces
		end

		-- Anchor the unreachable tolerance to the exact maximum Damage. The
		-- small Damage guard only loosens bounds against sum-order roundoff.
		local guard = 1e-10
		local bestPressure = AtDamage(root.damage)
		local target = (bestPressure <= 100 or seedOutput <= 100) and 100 or bestPressure + EPS
		local requiredDamage = 100 * ratio * reference.output / (target + (target == 100 and EPS or 0)) - 1
		local prices = PriceBounds(groups)
		local path = {}
		local function Visit(i, remaining, gold, rank, damage)
			if result.visited >= limit then return false end
			result.visited = result.visited + 1
			coroutine.yield()
			if not Cheaper(gold, rank, result.gold, result.acquisitionRank) then return true end
			local rest = best(i, remaining)
			if not rest or damage + rest.damage + guard < requiredDamage then return true end
			local bound = prices[i]
			local gap = requiredDamage - damage - bound.free - guard
			if gap > 0 and (bound.rate == 0 or gold + gap / bound.rate > result.gold + EPS) then return true end
			local group = groups[i]
			if not group then
				local pressure = AtDamage(damage)
				if pressure <= target then
					result.outputPressure, result.gold, result.acquisitionRank, result.pieces = pressure, gold, rank, Pieces(path)
				end
				return true
			end
			for _, option in ipairs(group.priced) do
				path[i] = option
				if not Visit(i + 1, consume(remaining, option), gold + option.gold, rank + option.acquisitionRank,
					damage + option.damage) then return false end
			end
			path[i] = nil
			return true
		end
		result.complete = Visit(1, need, 0, 0, 0)
		if result.outputPressure > 100 then
			local legal = result.excluded and Suffix(groups, "legal", consume)(1, need) or root
			result.verifiedBestOutputPressure = AtDamage(legal.damage)
			result.unreachable = result.complete and not result.unverifiedDrops and AtDamage(legal.damage + guard) > 100
			result.maxGear = MaxGear(nativeOrder, need, consume, catalog, context, reference, allowed)
		end
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
