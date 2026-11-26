-- Shared read-only equipment arithmetic and the Reborn tier catalog.
if SurvivorUI_Standby then return end

local Gear = {}
SurvivorUI_RebornGearModel = Gear
local BASE = { "common", "uncommon", "rare", "epic", "legendary", "pvp" }
local ORDER = { common = 1, uncommon = 2, rare = 3, epic = 4, pvp = 5, legendary = 6 }
local EPS = 0.000000001
-- From the November 16, 2026 armor price chart. The numbers already include
-- the price reduction. Integer tenths of each factor avoid floating-point rounding.
local STAR_BASE_GOLD = { 408, 816, 1496, 2720, 4080 }
local STAR_FACTORS = { common = 10, uncommon = 17, rare = 25, epic = 35, pvp = 40, legendary = 46,
	exotic = 58, mythic = 72, elementium = 76 }

local function Integer(value, maximum)
	local n = tonumber(value)
	return n and n >= 0 and n <= maximum and n == math.floor(n) and n or nil
end

function Gear.Catalog(gen)
	if type(gen) ~= "table" or type(gen.pieces) ~= "table" then return nil end
	local p, tiers = gen.pieces, {}
	local scale = p.scale
	if type(scale) ~= "table" or not Integer(scale.top, 20) or not Integer(scale.steps, scale.top)
		or type(scale.factor) ~= "number" or scale.factor <= 0
		or type(scale.slot) ~= "table" or type(scale.profile) ~= "table"
		or type(scale.starStep) ~= "table" or type(scale.starLast) ~= "table"
		or type(p.slots) ~= "table" or type(p.classProfiles) ~= "table" or type(p.profiles) ~= "table" then return nil end
	for index, key in ipairs(BASE) do
		tiers[key] = { id = index - 1, rank = ORDER[key], slot = scale.slot[index], profile = scale.profile[index],
			step = scale.starStep[index], last = scale.starLast[index] }
	end
	for index, raw in ipairs(gen.gearTiers or {}) do
		tiers[raw.key] = { id = index + 5, rank = raw.rank, slot = raw.slot_scale, profile = raw.profile_scale,
			step = raw.star_step, last = raw.star_last, starFactor = tonumber(raw.star_factor), pair = raw.pair, name = raw.name }
	end
	for _, tier in pairs(tiers) do
		if type(tier.slot) ~= "number" or type(tier.profile) ~= "number"
			or type(tier.step) ~= "number" or type(tier.last) ~= "number" then return end
	end
	local slots = {}
	for i = 0, 10 do
		local slot = p.slots[i]
		if not slot or not slot.key then return nil end
		slots[slot.key] = { data = slot, index = i }
	end
	return { native = gen, pieces = p, tiers = tiers, slots = slots }
end

function Gear.StarQuote(catalog, slot, tier, targetStar)
	local s, t = catalog.slots[slot], catalog.tiers[tier]
	local base, factor = STAR_BASE_GOLD[targetStar], STAR_FACTORS[tier]
	if not s or not t or not base or not factor then return end
	if t.starFactor and math.abs(t.starFactor * 10 - factor) > EPS then return end
	local estimated = tier == "exotic" or tier == "elementium" or (tier == "legendary" and targetStar == 5)
	return math.floor((base * factor + 5) / 10), estimated and "estimated" or (s.index < 8 and "table" or "weapon")
end

function Gear.Piece(catalog, class, slot, tier, stars)
	local s, t = catalog.slots[slot], catalog.tiers[tier]
	local p = catalog.pieces
	local profiles = p.classProfiles[class]
	if not s or not t or not profiles or not Integer(stars, p.scale.top) then return nil end
	local profile = s.data.profile and p.profiles[profiles[s.index + 1]]
	local result = {}
	local gain = (1 + math.min(stars, p.scale.steps) * t.step + (stars == p.scale.top and t.last or 0)) * p.scale.factor
	for _, stat in ipairs(s.data.stats) do result[stat[1]] = stat[2] * t.slot * gain end
	for _, stat in ipairs(profile or {}) do result[stat[1]] = (result[stat[1]] or 0) + stat[2] * t.profile * gain end
	return result
end

-- AZSARMOR sends numeric slot and rarity IDs. Record the entire worn list or
-- reject the snapshot if a row cannot be mapped.
function Gear.Worn(catalog, class, rows)
	if not catalog or not catalog.pieces.classProfiles[class] or type(rows) ~= "table" then return end
	local byId, used, pieces = {}, {}, {}
	for key, tier in pairs(catalog.tiers) do byId[tier.id] = key end
	for _, row in ipairs(rows) do
		if type(row) ~= "table" then return end
		if row.rarity ~= nil and row.rarity ~= "" then
			local index = Integer(row.slot, 10)
			local slot = index and catalog.pieces.slots[index].key
			local tier = byId[Integer(row.rarity, 9)]
			local stars = Integer(row.stars, catalog.pieces.scale.top)
			if not slot or not tier or not stars or used[slot] then return end
			used[slot] = true
			table.insert(pieces, { slot = slot, tier = tier, stars = stars, icon = row.icon,
				name = row.name, set = row.set, observed = row.stats })
		end
	end
	if not pieces[1] then return end
	table.sort(pieces, function(a, b) return catalog.slots[a.slot].index < catalog.slots[b.slot].index end)
	return pieces
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
						end), template = bonus.text, needs = bonus.needs,
						values = { v = bonus.v and bonus.v[v], v2 = bonus.v2 and bonus.v2[v] } })
				end
			end
		end
		if table.getn(result) > 0 then sets[tier] = result end
	end
	return stats, sets
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
