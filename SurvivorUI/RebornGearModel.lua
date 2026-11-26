-- Read-only gear arithmetic and a bounded Pareto search over explicitly priced choices.
if SurvivorUI_Standby then return end

local Gear = {}
SurvivorUI_RebornGearModel = Gear
Gear.version = 1
local BASE = { "common", "uncommon", "rare", "epic", "legendary", "pvp" }
local ORDER = { common = 1, uncommon = 2, rare = 3, epic = 4, pvp = 5, legendary = 6 }
local EPS = 0.000000001

local function Integer(value, maximum)
	local n = tonumber(value)
	return n and n >= 0 and n <= maximum and n == math.floor(n) and n or nil
end

function Gear.Catalog(gen)
	if type(gen) ~= "table" or type(gen.pieces) ~= "table" then return nil end
	local p, tiers = gen.pieces, {}
	local scale = p.scale
	if type(scale) ~= "table" or scale.top ~= 5 or scale.steps ~= 4
		or type(scale.slot) ~= "table" or type(scale.profile) ~= "table"
		or type(scale.starStep) ~= "table" or type(scale.starLast) ~= "table"
		or type(p.slots) ~= "table" or type(p.classProfiles) ~= "table" or type(p.profiles) ~= "table" then return nil end
	for index, key in ipairs(BASE) do
		tiers[key] = { id = index - 1, rank = ORDER[key], slot = scale.slot[index], profile = scale.profile[index],
			step = scale.starStep[index], last = scale.starLast[index] }
	end
	for index, raw in ipairs(gen.gearTiers or {}) do
		tiers[raw.key] = { id = index + 5, rank = raw.rank, slot = raw.slot_scale, profile = raw.profile_scale,
			step = raw.star_step, last = raw.star_last }
	end
	local slots = {}
	for i = 0, 10 do
		local slot = p.slots[i]
		if not slot or not slot.key then return nil end
		slots[slot.key] = { data = slot, index = i }
	end
	return { native = gen, pieces = p, tiers = tiers, slots = slots }
end

function Gear.Piece(catalog, class, slot, tier, stars)
	local s, t = catalog.slots[slot], catalog.tiers[tier]
	local p = catalog.pieces
	local profiles = p.classProfiles[class]
	if not s or not t or not profiles or not Integer(stars, 5) then return nil end
	local profile = s.data.profile and p.profiles[profiles[s.index + 1]]
	local result = {}
	local gain = (1 + math.min(stars, p.scale.steps) * t.step + (stars == p.scale.top and t.last or 0)) * p.scale.factor
	for _, stat in ipairs(s.data.stats) do result[stat[1]] = stat[2] * t.slot * gain end
	for _, stat in ipairs(profile or {}) do result[stat[1]] = (result[stat[1]] or 0) + stat[2] * t.profile * gain end
	return result
end

function Gear.Totals(catalog, class, pieces)
	local stats, counts, sets = {}, {}, {}
	local rules = catalog.native.setRules
	for _, piece in ipairs(pieces) do
		for key, value in pairs(piece.stats) do stats[key] = (stats[key] or 0) + value end
		local slot = catalog.slots[piece.slot]
		if slot.index < 8 then
			local count = counts[piece.tier] or { 0, 0, 0 }
			counts[piece.tier] = count
			if rules then
				for i, stars in ipairs(rules.stars) do
					if piece.stars >= stars then count[i] = count[i] + 1 end
				end
				if piece.stars >= rules.empowerStars then count[3] = count[3] + 1 end
			end
		end
	end
	if not rules or type(catalog.native.setBonuses) ~= "table" then return stats, nil end
	for tier, count in pairs(counts) do
		local result = {}
		for i, need in ipairs(rules.pieces) do
			if count[i] >= need then
				local bonus
				for _, candidate in ipairs(catalog.native.setBonuses) do
					if candidate.rarity == catalog.tiers[tier].id and candidate.pieces == need then
						if candidate.class == class then bonus = candidate; break end
						if candidate.class == "" then bonus = candidate end
					end
				end
				if bonus then
					local strong = count[3] >= rules.pieces[2] and (i == 2 or bonus.follows)
					local v = strong and 2 or 1
					table.insert(result, { pieces = need, strong = strong and true or false,
						text = string.gsub(bonus.text, "{(%w+)}", function(key)
							return bonus[key] and bonus[key][v] or "?"
						end), template = bonus.text, values = { v = bonus.v and bonus.v[v], v2 = bonus.v2 and bonus.v2[v] } })
				end
			end
		end
		if table.getn(result) > 0 then sets[tier] = result end
	end
	return stats, sets
end

local function EqualStats(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for key, n in pairs(a) do
		if type(b[key]) ~= "number" or math.abs(n - b[key]) > EPS then return false end
	end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

function Gear.ReferenceCurrent(catalog, class, reference)
	if type(reference.gear) ~= "table" or type(reference.sets) ~= "table" or not tonumber(reference.damage) then return false end
	local items = {}
	for i, item in ipairs(reference.gear) do
		local stats = Gear.Piece(catalog, class, item.slot, item.tier, item.stars)
		if not EqualStats(stats, item.stats) then return false end
		items[i] = { stats = stats, slot = item.slot, tier = item.tier, stars = item.stars }
	end
	local stats, sets = Gear.Totals(catalog, class, items)
	if not EqualStats(stats, reference.stats) or not sets
		or math.abs((stats.damage or 0) - reference.damage) > EPS then return false end
	for tier, bonuses in pairs(sets) do
		local old = reference.sets[tier]
		if not old or table.getn(old) ~= table.getn(bonuses) then return false end
		for i, bonus in ipairs(bonuses) do
			if old[i].text ~= bonus.text or old[i].pieces ~= bonus.pieces or old[i].strong ~= bonus.strong then return false end
		end
	end
	for tier in pairs(reference.sets) do if not sets[tier] then return false end end
	return true
end

-- These are declared states. A farm row means the player verified that specific piece can drop.
-- Prices are consecutive incremental costs starting at the next star.
function Gear.Parse(catalog, class, text)
	if not catalog or not catalog.pieces.classProfiles[class] or type(text) ~= "string"
		or string.len(text) > 8192 then return nil, 0 end
	local slots, seen, lineNumber = {}, {}, 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lineNumber = lineNumber + 1
		if not string.match(line, "^%s*$") then
			local slot, tier, star, kind, prices = string.match(line, "^%s*([%w_]+)%s+(%w+)%s+(%d+)%s+(%a+)%s*(.-)%s*$")
			star = Integer(star, 5)
			if not slot or not catalog.slots[slot] or not catalog.tiers[tier] or not star
				or (kind ~= "worn" and kind ~= "owned" and kind ~= "farm") or (kind == "farm" and star ~= 0)
				or seen[slot .. ":" .. tier] then return nil, lineNumber end
			seen[slot .. ":" .. tier] = true
			local group = slots[slot] or { entries = {} }
			slots[slot] = group
			local entry = { slot = slot, tier = tier, start = star, kind = kind, choices = {}, line = lineNumber }
			if kind == "worn" then
				if group.worn then return nil, lineNumber end
				group.worn = entry
			end
			table.insert(group.entries, entry)
			local steps = {}
			if prices ~= "" then
				for price in string.gmatch(prices .. ",", "(.-),") do
					local n = Integer(price, 100000000)
					if not n or n == 0 or not string.match(price, "^%d+$") then return nil, lineNumber end
					table.insert(steps, n)
				end
			end
			if star + table.getn(steps) > 5 then return nil, lineNumber end
			local cost = 0
			for i = 0, table.getn(steps) do
				cost = cost + (steps[i] or 0)
				local stats = Gear.Piece(catalog, class, slot, tier, star + i)
				table.insert(entry.choices, { slot = slot, tier = tier, stars = star + i, cost = cost,
					kind = kind, stats = stats, power = stats.damage or 0, armor = catalog.slots[slot].index < 8 })
			end
		end
	end
	local ordered, current, incomplete = {}, {}, false
	for slot, group in pairs(slots) do
		group.slot = slot
		table.insert(ordered, group)
		for _, entry in ipairs(group.entries) do
			if entry.kind == "farm" and group.worn
				and catalog.tiers[entry.tier].rank <= catalog.tiers[group.worn.tier].rank then return nil, entry.line end
			if entry.choices[table.getn(entry.choices)].stars < 5 then incomplete = true end
		end
	end
	table.sort(ordered, function(a, b) return catalog.slots[a.slot].index < catalog.slots[b.slot].index end)
	for _, group in ipairs(ordered) do
		if group.worn then table.insert(current, group.worn.choices[1]) end
	end
	if table.getn(current) == 0 then return nil, 0 end
	return { groups = ordered, current = current, incomplete = incomplete }
end

function Gear.Pressure(reference, zone, tier)
	local value = SurvivorUI_RebornAnalysisModel.Map(reference, zone, tier)
	return value and value.health / 100 or nil
end

function Gear.Scenario(target, reference, currentDamage, background)
	if not target or not reference or reference.pressure <= 0 then return nil end
	local required = target / reference.pressure * (1 + background + reference.damage) - 1 - background
	return (1 + background + required) / (1 + background + currentDamage), required
end

local function Better(candidate, existing)
	return not existing or candidate.power > existing.power + EPS
		or (math.abs(candidate.power - existing.power) <= EPS and candidate.changes < existing.changes)
end

-- Each tier only needs its strongest active threshold. Preserving it also
-- preserves the lower thresholds on that tier. Unknown combat effects need
-- no numeric ranking for this comparison.
function Gear.SetRequirements(sets, rules)
	local requirements = {}
	for tier, bonuses in pairs(sets or {}) do
		local need, stars = 0, 0
		for _, bonus in ipairs(bonuses) do
			local level = bonus.strong and rules.empowerStars
				or (bonus.pieces == rules.pieces[2] and rules.stars[2] or rules.stars[1])
			if level > stars then
				need = bonus.strong and rules.pieces[2] or bonus.pieces
				stars = level
			end
		end
		if stars > 0 then table.insert(requirements, { tier = tier, stars = stars, count = need }) end
	end
	table.sort(requirements, function(a, b) return a.tier < b.tier end)
	return requirements
end

local function StateCode(requirements, state, piece)
	local nextState, code = {}, 0
	for index, req in ipairs(requirements) do
		local count = state[index] or 0
		if piece.armor and piece.tier == req.tier and piece.stars >= req.stars then
			count = math.min(req.count, count + 1)
		end
		nextState[index], code = count, code * 9 + count
	end
	return code, nextState
end

function Gear.KeepsSets(pieces, requirements)
	local progress = {}
	for _, piece in ipairs(pieces) do local _, nextState = StateCode(requirements, progress, piece); progress = nextState end
	for index, req in ipairs(requirements) do if progress[index] ~= req.count then return false end end
	return true
end

-- Exact only for the scalar gear-damage scenario and declared, priced candidates.
-- Unknown set effects are evaluated and disclosed alongside the resulting configurations.
function Gear.Optimize(plan, needed, farm, limit, requirements)
	requirements = requirements or {}
	local currentPower = 0
	for _, piece in ipairs(plan.current) do currentPower = currentPower + piece.power end
	if currentPower + EPS >= needed and (not requirements[1] or Gear.KeepsSets(plan.current, requirements)) then
		return { cost = 0, pieces = plan.current, power = currentPower, reached = true }
	end
	local states, evaluations = { { cost = 0, power = 0, changes = 0, progress = {}, code = 0 } }, 0
	local full = 0
	for _, req in ipairs(requirements) do full = full * 9 + req.count end
	for _, group in ipairs(plan.groups) do
		local current = group.worn and group.worn.choices[1]
		local options = {}
		if not current then table.insert(options, { cost = 0, power = 0 }) end
		for _, entry in ipairs(group.entries) do
			if farm or entry == group.worn then
				for _, option in ipairs(entry.choices) do table.insert(options, option) end
			end
		end
		local partitions, codes = {}, {}
		for _, prior in ipairs(states) do
			for _, option in ipairs(options) do
				evaluations = evaluations + 1
				if evaluations > (limit or 24000) then return nil, "limit" end
				local cost, power = prior.cost + option.cost, prior.power + option.power
				local change = (option.slot and option ~= current) and 1 or 0
				local code, progress = 0, prior.progress
				if full > 0 then code, progress = StateCode(requirements, prior.progress, option) end
				local partition = partitions[code]
				if not partition then
					partition = { best = {}, costs = {} }
					partitions[code] = partition
					table.insert(codes, code)
				end
				local candidate = { cost = cost, power = power, changes = prior.changes + change,
					prior = prior, piece = option, progress = progress, code = code }
				if not partition.best[cost] then table.insert(partition.costs, cost) end
				if Better(candidate, partition.best[cost]) then partition.best[cost] = candidate end
			end
		end
		states = {}
		table.sort(codes)
		for _, code in ipairs(codes) do
			local partition, power = partitions[code], -1
			table.sort(partition.costs)
			for _, cost in ipairs(partition.costs) do
				if partition.best[cost].power > power + EPS then
					power = partition.best[cost].power
					table.insert(states, partition.best[cost])
				end
			end
		end
	end
	local chosen
	for _, result in ipairs(states) do
		if result.code == full then
			chosen = result
			if result.power + EPS >= needed then break end
		end
	end
	if not chosen then return nil, "sets" end
	local pieces, node = {}, chosen
	while node.piece do
		if node.piece.slot then table.insert(pieces, 1, node.piece) end
		node = node.prior
	end
	return { cost = chosen.cost, power = chosen.power, pieces = pieces, reached = chosen.power + EPS >= needed }
end
