-- Pure Reborn analysis. Percentages here are whole percentage points.
if SurvivorUI_Standby then return end

local Model = {}
SurvivorUI_RebornAnalysisModel = Model

function Model.Number(value)
	if type(value) ~= "number" and type(value) ~= "string" then return nil end
	local number = tonumber(value)
	if number and number > -math.huge and number < math.huge then return number end
end

-- The native card renderer consumes a letter, amount and optional before/after totals.
-- Keep the totals as server preview fields. Their multiplier semantics vary by line.
function Model.Boosts(wire)
	if type(wire) ~= "string" or string.len(wire) > 256 then return nil end
	local boosts, nextAt = {}, 1
	while nextAt <= string.len(wire) do
		local first, last, code, amount = string.find(wire, "(%a)(%d+)", nextAt)
		if not first or not string.match(string.sub(wire, nextAt, first - 1), "^[%s,;|]*$") then
			return nil
		end
		local actual = tonumber(amount)
		if actual <= 0 or actual > 10000 or table.getn(boosts) >= 8 then return nil end
		local before, after
		if string.sub(wire, last + 1, last + 1) == ":" then
			local previewFirst, previewLast
			previewFirst, previewLast, before, after = string.find(wire, ":(%d+):(%d+)", last + 1)
			if previewFirst ~= last + 1 then return nil end
			last = previewLast
		end
		table.insert(boosts, { code = code, amount = actual, before = tonumber(before), after = tonumber(after) })
		nextAt = last + 1
	end
	if table.getn(boosts) > 0 then return boosts end
end

-- Derived from the standard rank-card configuration in Reborn 0.7.4.
local DAMAGE = { [0] = 18, 25, 34, 46, 65 }
local COOLDOWN = { [0] = 7, 10, 13, 17, 23 }

function Model.Skill(card, current, share)
	local spell = Model.Number(card.spell)
	if type(current) ~= "table" or Model.Number(card.new) ~= 0 or current.key ~= card.key
		or not spell or spell <= 0 or Model.Number(current.spell) ~= spell then return nil end
	local rank = Model.Number(current.rank)
	if not rank or rank < 1 or Model.Number(card.rank) ~= rank + 1 then return nil end
	local boosts = Model.Boosts(card.lines)
	if not boosts then return nil end
	local rarity = Model.Number(card.rarity)
	local result = { kind = "spell", boosts = boosts }
	local damage, speed = 1, 1
	local complete = true
	for _, boost in ipairs(boosts) do
		if boost.code == "d" and damage == 1 and DAMAGE[rarity] == boost.amount then
			damage = 1 + boost.amount / 100
			result.damage = boost.amount
			result.damageBoost = boost
			if boost.before and boost.after and math.abs((100 + boost.before) * damage - (100 + boost.after)) > 2 then
				complete = false
			end
		elseif boost.code == "c" and speed == 1 and COOLDOWN[rarity] == boost.amount then
			speed = 1 / (1 - boost.amount / 100)
			result.frequency = 100 * (speed - 1)
			local seconds = Model.Number(current.cdmax)
			if seconds and seconds > 0 then
				result.cooldown = { before = seconds, ideal = seconds / speed }
			end
		else
			complete = false
		end
	end
	-- This is a counterfactual for a matching meter row. Its contents may include proc damage.
	if complete and share and share > 0 and share <= 1 then
		result.meterScenario = 100 * share * (damage * speed - 1)
	end
	result.partial = not complete
	return result
end

function Model.Jewelry(card, statKey, readCap)
	if type(card.detail) ~= "string" or card.detail == "" or string.len(card.detail) > 2048 then return nil end
	local result = { kind = "jewel", changes = {} }
	for wire in string.gmatch(card.detail, "[^%^]+") do
		local label, before, after, way = string.match(wire, "^(.-)=(.-)=(.-)=(.)$")
		if not label or label == "" or (way ~= "+" and way ~= "-" and way ~= "=")
			or table.getn(result.changes) >= 8 then return nil end
		local from = Model.Number(string.match(before, "^%+?([%d%.]+)%%$"))
		local to = Model.Number(string.match(after, "^%+?([%d%.]+)%%$"))
		if not from then from = Model.Number(before) end
		if not to then to = Model.Number(after) end
		local percent = string.sub(before, -1) == "%" and string.sub(after, -1) == "%"
		local flat = not string.find(before, "%%") and not string.find(after, "%%")
		local change = { label = label, before = before, after = after, way = way }
		if from and to and (percent or flat) and way ~= "=" then
			change.delta = to - from
			change.percent = percent
		end
		local key = statKey(label)
		if key and percent and change.delta and change.delta > 0 and way == "+"
			and (card.mode == "grow" or card.mode == "empower") then
			change.stat = key
			change.cap, change.room = readCap(key)
		end
		table.insert(result.changes, change)
	end
	if table.getn(result.changes) > 0 then return result end
end

-- Standard Campaign tier factors in 0.7.4. They do not include challenges, affixes or boss scripts.
local HEALTH = { [0] = 1, 1.79, 1.97, 2.16, 2.45, 2.72 }
local HIT = { [0] = 1, 1.65, 1.77, 1.88, 2.01, 2.16 }

function Model.Map(reference, zone, tier)
	local entry, base = reference[zone], reference.naxx
	if not entry or not base or not HEALTH[tier] then return nil end
	return {
		health = 100 * entry[1] / base[1] * HEALTH[tier],
		late = entry[2],
		bossHealth = 100 * entry[3] / base[3] * HEALTH[tier],
		bossHit = 100 * entry[4] / base[4] * HIT[tier],
		firstBossHealth = 100 * entry[5] / base[5] * HEALTH[tier],
		firstBossHit = 100 * entry[6] / base[6] * HIT[tier],
	}
end

-- A bounded, encounter-local time series of observed run state.
local WINDOW = 30
local STEP = 5

function Model.Observe(samples, sample)
	local last = samples[table.getn(samples)]
	if last and (last.segment ~= sample.segment or sample.time < last.time or sample.time - last.time > 12) then
		samples = {}
		last = nil
	end
	if last and sample.time - last.time < STEP then return samples end
	table.insert(samples, sample)
	while table.getn(samples) > 1 and sample.time - samples[1].time > WINDOW do
		table.remove(samples, 1)
	end
	return samples
end

function Model.Summarize(samples)
	local first, last = samples[1], samples[table.getn(samples)]
	if not first then return nil end
	local elapsed = last.time - first.time
	local out = { latest = last, elapsed = elapsed, lowest = last.hpRatio }
	local lowSamples = 0
	for _, sample in ipairs(samples) do
		if sample.hpRatio then
			out.lowest = math.min(out.lowest or sample.hpRatio, sample.hpRatio)
			if sample.hpRatio <= 0.35 then lowSamples = lowSamples + 1 end
		end
	end
	if elapsed < 15 then return out end
	if last.kills and first.kills and last.kills >= first.kills then
		out.killsPerMin = 60 * (last.kills - first.kills) / elapsed
	end
	if last.taken and first.taken and last.taken >= first.taken then
		out.takenPerSec = (last.taken - first.taken) / elapsed
		if out.takenPerSec > 0 and lowSamples >= 2 and last.hpRatio and last.hpRatio <= 0.35 then
			out.survival = true
		end
	end
	if last.level and first.level and last.level >= first.level then
		out.levels = last.level - first.level
	end
	if first.level and last.level and first.level == last.level and first.xp and last.xp and last.xp >= first.xp then
		out.xpPerSec = (last.xp - first.xp) / elapsed
	end
	if last.alive and first.alive then
		out.enemyDelta = last.alive - first.alive
		local middle = samples[math.floor((table.getn(samples) + 1) / 2)]
		out.buildup = not last.inBoss and last.cap and last.cap > 0 and first.cap == last.cap
			and last.alive / last.cap >= 0.5 and middle.alive and middle.alive > first.alive
			and last.alive > middle.alive and out.killsPerMin and out.killsPerMin > 0
	end
	if last.inBoss and last.bossId and first.bossId == last.bossId
		and first.bossHP and last.bossHP and last.bossHP < first.bossHP then
		out.bossNetHPPerSec = (first.bossHP - last.bossHP) / elapsed
	end
	return out
end

-- The meter cannot establish which triggered damage scales with a spell card.
-- Only a supported mitigation option can currently be tied to a symptom.
function Model.Advice(summary, values)
	if not summary or not summary.survival then return nil end
	local defense
	for index, value in pairs(values) do
		local change = value.changes and table.getn(value.changes) == 1 and value.changes[1]
		if change and change.stat == "red" and change.room and change.room > 0 then
			if defense then return nil end
			defense = index
		end
	end
	return defense
end
