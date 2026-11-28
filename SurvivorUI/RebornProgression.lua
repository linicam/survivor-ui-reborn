-- Confirm card commands against the run-scoped native learned and equipment feeds.
if SurvivorUI_Standby then return end

local Progress = {}
SurvivorUI_RebornProgression = Progress

local Model = SurvivorUI_RebornAnalysisModel
local MAX_CHOICES, MAX_PENDING, REPLY_SECONDS = 512, 12, 15
local state, hand, picked, pending, gear, tips, ready, campaign, startedAtBeginning, choiceOrder
local CopySnapshot

local function Changed()
	if Progress.Refresh then Progress.Refresh() end
end

local function Run()
	if SurvivorUI_RebornActive() and AZS_ZONE and tonumber(AZS_ZONE.hub) ~= 1 then
		local id = SurvivorUI_RebornRunId()
		return SurvivorUI_RebornStableRunId(id) or id
	end
end

local function Reset()
	state, hand, picked, pending, gear, tips, ready = nil, nil, nil, {}, nil, {}, nil
	campaign = nil
	startedAtBeginning, choiceOrder = nil, 0
	Changed()
end
Reset()
SurvivorUI_RebornRegisterReset(Reset)

local function Current()
	local run = Run()
	if ready and run and state and state.run == run then return state end
end
Progress.Live = Current

-- Zone sync can happen several times per run. The run-state reply opens
-- observation again after each sync without carrying the old card hand.
function Progress.Zone()
	ready, hand, picked = nil, nil, nil
end

local function ObserveRun()
	local run = Run()
	if not run or not AZS_RUN or not AZS_RUN.ph then return end
	if not state or state.run ~= run then
		Reset()
		startedAtBeginning = tonumber(AZS_RUN.t) == 0 and tonumber(AZS_RUN.lvl) == 1
			and AZS_RUN.ph == "playing" and tonumber(AZS_RUN.endless) ~= 1
		state = { version = 1, run = run, choices = {}, skills = {}, jewelry = {}, complete = startedAtBeginning }
	end
	if tonumber(AZS_RUN.endless) == 1 and not campaign then campaign = CopySnapshot() end
	ready = true
end

local function Expire()
	local now = GetTime()
	for index = table.getn(pending), 1, -1 do
		if now - pending[index].sent > REPLY_SECONDS then table.remove(pending, index) end
	end
end

local function Record(choice)
	local choices = state.choices
	if table.getn(choices) >= MAX_CHOICES then
		local removed = table.remove(choices, 1)
		if removed.kind == "spell" then state.skills[removed.key].historyPartial = true end
		state.complete = false
	end
	table.insert(choices, choice)
	Changed()
	if SurvivorUI_RebornRecording and SurvivorUI_RebornRecording() then
		SurvivorUI_RebornRecord("progression_choice", choice)
	end
end

local function ObserveHand(newHand)
	if not Current() or newHand == hand then return end
	hand, picked = newHand, nil
	Expire()
end

local function MatchCard(rows, card)
	local match
	for _, row in pairs(rows or {}) do
		if row and row.slot == card.slot and row.name == card.name and row.icon == card.icon then
			if match then return nil end
			match = row
		end
	end
	return match
end

local function ItemChanged(before, after)
	return before.amount ~= after.amount or before.text ~= after.text
end

local function SkillIntent(card, choice)
	if type(card.key) ~= "string" or card.key == "" or string.find(card.key, "^dash_") then return end
	local rank, spell, new = tonumber(card.rank), tonumber(card.spell), tonumber(card.new)
	local skill = state.skills[card.key]
	if not rank or not spell or (new ~= 0 and new ~= 1) or (new == 0 and rank < 2)
		or (skill and skill.rank and skill.rank >= rank) then return end
	choice.key, choice.rank, choice.spell = card.key, rank, spell
	choice.type = new == 1 and "acquire" or "enhance"
	choice.affixes = Model.Boosts(card.lines)
	choice.affixesUnknown = not choice.affixes and card.lines and card.lines ~= "" or nil
	return true
end

local function JewelIntent(card, choice)
	local mode = card.mode
	if mode ~= "new" and mode ~= "amulet" and mode ~= "grow" and mode ~= "empower" then return end
	local acquire = mode == "new" or mode == "amulet"
	local before = MatchCard(gear, card)
	if not acquire and not before then return end
	choice.type = acquire and "acquire" or "enhance"
	choice.mode, choice.affixes, choice.offeredEffect = mode, Model.JewelryChanges(card.detail), card.effect
	return true, before
end

-- Called by the same post-command observer as the opt-in recorder.
function Progress.Action(offered, action, index)
	if not Current() or offered ~= hand or not hand then return end
	if action ~= "pick" then
		if picked then picked.cancelled = true end
		picked = nil
		return
	end
	local card = hand.cards and hand.cards[index]
	if not card or (picked and picked.index == index) then return end
	if picked then picked.cancelled = true end
	local rarity = tonumber(card.rarity)
	if not rarity or rarity < 0 or rarity > 4 or rarity ~= math.floor(rarity) then rarity = nil end
	local choice = { kind = hand.kind, rarity = rarity,
		level = tonumber(hand.lvl) or tonumber(AZS_RUN.lvl), time = tonumber(AZS_RUN.t) }
	local valid, before
	if hand.kind == "spell" then valid = SkillIntent(card, choice)
	elseif hand.kind == "jewel" then valid, before = JewelIntent(card, choice) end
	if not valid then return end
	choiceOrder = choiceOrder + 1
	choice.order = choiceOrder
	Expire()
	if table.getn(pending) >= MAX_PENDING then table.remove(pending, 1) end
	picked = { card = card, index = index, sent = GetTime(), choice = choice, before = before }
	table.insert(pending, picked)
end

-- Native previews show the compound total. A spell can cap its cooldown
-- or buff duration, so those preview totals cannot establish applied values.
local previewApplies = { d = true, t = true, a = true }
local function BondTotals(key, text)
	if key ~= "demonic_knowledge" or not text then return end
	local damage = string.match(text, "伤害提高([%d.]+)%%")
		or string.match(text, "([%d.]+)%% more damage") or string.match(text, "[Dd]amage[^.%%]-([%d.]+)%%")
	local interval = string.match(text, "攻击间隔缩短([%d.]+)%%")
		or string.match(text, "[Aa]ttack interval[^.%%]-([%d.]+)%%")
	local targets = string.match(text, "额外命中([%d.]+)名")
		or string.match(text, "([%d.]+) extra targets") or string.match(text, "([%d.]+) additional enem")
	if interval then return { d = tonumber(damage), c = tonumber(interval), t = tonumber(targets) } end
end
Progress.BondTotals = BondTotals

local function ApplyTip(skill, key, text, choice)
	if not text then return end
	skill.tip = text
	skill.tipRank = skill.rank
	for code, value in pairs(BondTotals(key, text) or {}) do
		skill.totals[code], skill.unknown[code] = value, nil
	end
	if choice then
		for _, affix in ipairs(choice.affixes or {}) do
			affix.applied = skill.totals[affix.code]
		end
	end
end

function Progress.SpellTip(key, text)
	if not Current() or text == "" then return end
	Expire()
	-- In Session 033 the passive's current description precedes both the
	-- closed hand and the learned snapshot. Hold it until the rank matches.
	for index = table.getn(pending), 1, -1 do
		local intent = pending[index]
		if not intent.cancelled and intent.choice.kind == "spell" and intent.choice.key == key then
			intent.tip = text
			return
		end
	end
	local skill = state.skills[key]
	if skill and skill.tip ~= text then
		local choice = skill.lastChoice
		if GetTime() - (skill.confirmedAt or -REPLY_SECONDS) > REPLY_SECONDS then choice = nil end
		ApplyTip(skill, key, text, choice)
		Changed()
	elseif not skill then
		tips[key] = text
	end
end

local function SkillPick(ability)
	local found, index
	for i, intent in ipairs(pending) do
		local choice = intent.choice
		if not intent.cancelled and choice.kind == "spell" and choice.key == ability.key
			and choice.spell == ability.spell and choice.rank == ability.rank then
			if found and (found.card.lines ~= intent.card.lines or found.choice.rarity ~= choice.rarity
				or found.choice.type ~= choice.type) then return nil end
			if found then found.cancelled = true end
			found, index = intent, i
		end
	end
	if index then table.remove(pending, index) end
	return found
end

local function ObserveSkill(ability)
	local key, rank = ability.key, ability.rank
	if not rank or rank < 1 then return end
	local skill = state.skills[key]
	if skill and rank < skill.rank then return end
	local advanced = not skill or rank > skill.rank
	if advanced then
		local intent = SkillPick(ability)
		local choice = intent and intent.choice
		local contiguous = skill and rank == skill.rank + 1
		if not skill then
			skill = { totals = {}, unknown = {}, count = 0, acquisitions = 0, rarities = {},
				complete = choice and choice.type == "acquire" or (startedAtBeginning and rank == 1 and tonumber(AZS_RUN.t) == 0) }
			state.skills[key] = skill
		elseif not (choice and contiguous) then
			skill.complete, skill.totals, skill.unknown = false, {}, {}
		end
		skill.rank, skill.spell = rank, ability.spell
		skill.tip, skill.tipRank, skill.lastChoice = nil, nil, choice
		if choice then
			skill.confirmedAt = GetTime()
			skill.count = skill.count + 1
			if choice.type == "acquire" then skill.acquisitions = skill.acquisitions + 1 end
			local rarity = choice.rarity or -1
			skill.rarities[rarity] = (skill.rarities[rarity] or 0) + 1
			if choice.affixesUnknown then skill.totals, skill.unknown = {}, {}; skill.complete = false end
			for _, affix in ipairs(choice.affixes or {}) do
				local code = affix.code
				local applied = previewApplies[code] and affix.after or nil
				affix.applied = applied
				skill.totals[code], skill.unknown[code] = applied, applied == nil or nil
			end
			ApplyTip(skill, key, intent.tip, choice)
			Record(choice)
		end
		if not skill.complete then state.complete = false end
		if tips[key] then
			if not choice then ApplyTip(skill, key, tips[key]) end
			tips[key] = nil
		end
		Changed()
	end
	if ability.snapshotRank == rank and ability.text and BondTotals(key, ability.text)
		and skill.tip ~= ability.text and not skill.tip then
		ApplyTip(skill, key, ability.text, skill.lastChoice)
		Changed()
	end
	local name, icon = ability.name, ability.icon
	if not skill.name and ability.spell and GetSpellInfo then
		local spellName, _, spellIcon = GetSpellInfo(ability.spell)
		name = name or (spellName and SurvivorUI_Native and SurvivorUI_Native(spellName)) or spellName
		icon = icon or spellIcon
	end
	if (name and skill.name ~= name) or (icon and skill.icon ~= icon) then
		skill.name, skill.icon = name or skill.name, icon or skill.icon
		Changed()
	end
end

function Progress.Abilities(rows)
	if not Current() then return end
	Expire()
	for _, ability in ipairs(rows) do ObserveSkill(ability) end
end

function Progress.Skill(key)
	local current = Current()
	return current and key and current.skills[key] or nil
end

function Progress.JewelryCount(item, snapshot)
	local info = snapshot and item.instanceKey and snapshot.jewelry[item.instanceKey]
	return info and info.count, info and info.complete
end

local function EffectValue(text, label)
	for part in string.gmatch((string.gsub(text or "", " · ", "\n")), "[^\n]+") do
		local left, last = string.match(part, "^%s*(.-)%s*([+%-]%d+%.?%d*)%%%s*$")
		if left == label then return tonumber(last) end
		local first, right = string.match(part, "^%s*([+%-]%d+%.?%d*)%%%s*(.-)%s*$")
		if right == label then return tonumber(first) end
	end
end

local function MatchesGearOffer(intent, after)
	local choice = intent.choice
	if choice.mode ~= "grow" then
		local effect = choice.offeredEffect
		return effect and string.gsub(effect, ",%s+", " · ") == after.text or nil
	end
	local matched
	for _, affix in ipairs(choice.affixes or {}) do
		local old = EffectValue(intent.before.text, affix.label)
		local new = EffectValue(after.text, affix.label)
		local from = tonumber(string.match(affix.before, "^([%d.]+)%%$"))
		local to = tonumber(string.match(affix.after, "^([%d.]+)%%$"))
		if old and new and from and to and affix.way == "+" then
			-- The offer may include other worn items in the same stat.
			-- Compare the change, allowing for one-decimal display rounding.
			if math.abs((new - old) - (to - from)) > 0.21 then return false end
			matched = true
		end
	end
	return matched
end

local function GearPick(nextGear)
	local byItem, confirmed = {}, {}
	for i, intent in ipairs(pending) do
		local choice = intent.choice
		if not intent.cancelled and choice.kind == "jewel" then
			local after = MatchCard(nextGear, intent.card)
			local id = after and SurvivorUI_RebornJewelryIdentity(after)
			if id and (choice.type == "acquire" and gear and gear[id] == nil
				or choice.type == "enhance" and intent.before == gear[id] and ItemChanged(intent.before, after)) then
				local matches = MatchesGearOffer(intent, after)
				if matches ~= false then
					local group = byItem[id] or { count = 0, exactCount = 0 }
					local candidate = { index = i, row = after, intent = intent }
					group.candidate, group.count = candidate, group.count + 1
					if matches then group.exact, group.exactCount = candidate, group.exactCount + 1 end
					byItem[id] = group
				end
			end
		end
	end
	local remove = {}
	for id, group in pairs(byItem) do
		if group.count == 1 or group.exactCount == 1 then
			local candidate = group.exact or group.candidate
			confirmed[id], remove[candidate.index] = candidate.intent, true
			for _, later in ipairs(pending) do
				if candidate.intent.before and later.before == candidate.intent.before
					and later.choice.order > candidate.intent.choice.order then later.before = candidate.row end
			end
		end
	end
	for index = table.getn(pending), 1, -1 do
		if remove[index] then table.remove(pending, index) end
	end
	return confirmed
end

function Progress.Gear(rows)
	if not Current() then return end
	Expire()
	local nextGear = {}
	for _, row in ipairs(rows) do
		local id = row and SurvivorUI_RebornJewelryIdentity(row)
		if id then nextGear[id] = nextGear[id] == nil and row or false end
	end
	local confirmed = GearPick(nextGear)
	for id in pairs(state.jewelry) do
		if not nextGear[id] then state.jewelry[id] = nil end
	end
	for id, row in pairs(nextGear) do
		if row then
			local intent = confirmed[id]
			local item = state.jewelry[id]
			if not item then
				state.serial = (state.serial or 0) + 1
				item = { count = 0, instance = state.serial,
					complete = intent ~= nil and intent.choice.type == "acquire" }
				state.jewelry[id] = item
			elseif gear[id] and ItemChanged(gear[id], row) and not intent then
				item.complete = false
			end
			if not item.complete then state.complete = false end
			-- Keep the baseline on unrelated resends and on rarity-only changes.
			if gear and gear[id] and not ItemChanged(gear[id], row) then nextGear[id] = gear[id] end
		end
	end
	for id, intent in pairs(confirmed) do
		local choice, item, after = intent.choice, state.jewelry[id], nextGear[id]
		choice.key, choice.name, choice.appliedEffect = id, after.name, after.text
		if choice.type == "enhance" then item.count = item.count + 1 end
		choice.item = item.instance
		Record(choice)
	end
	gear = nextGear
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		if key ~= "lastChoice" and key ~= "confirmedAt" then copy[key] = Copy(child) end
	end
	return copy
end

CopySnapshot = function()
	local snapshot = Copy(state)
	if table.getn(pending) > 0 then
		Expire()
		for _, intent in ipairs(pending) do
			if not intent.cancelled then snapshot.complete = false; break end
		end
	end
	return snapshot
end

function Progress.Snapshot(run, endless, victory)
	local current = Current()
	if not current or (run and run ~= current.run) then return end
	if not endless and campaign then return campaign end
	local snapshot = CopySnapshot()
	if victory then campaign = snapshot end
	return snapshot
end

if AZS and type(AZS.On) == "function" then
	AZS.On("AZSRUN", ObserveRun)
end
Progress.Offer = ObserveHand
