-- Optional, read-only analysis of native Reborn snapshots.
if SurvivorUI_Standby or not SurvivorUI_RebornAnalysisModel then return end

local Model = SurvivorUI_RebornAnalysisModel
local Analysis = {}
SurvivorUI_RebornAnalysis = Analysis

local defaults = { cards = true, map = true, live = true }
local samples, currentRun = {}, nil
local lastSample, ready
local cachedHand, cachedInput, cachedValues, cachedAdvice
local meterHand, meterSegment, handMeter
local pending, handSerial, diagnosticHand, diagnosticSerial = nil, 0
local epochTime
local blockedSpells
local MAX_CARDS, METER_WINDOW = 4, 20
local Num = Model.Number
local function T(key) return SurvivorUI_T(key) end

function Analysis.IsSet(key)
	local options = SurvivorUIDB and SurvivorUIDB.rebornAnalysis
	if type(options) == "table" and options[key] ~= nil then return options[key] == true end
	return defaults[key] == true
end

function Analysis.Enabled(key)
	return Analysis.IsSet("enabled") and Analysis.IsSet(key)
end

local function ClearHand()
	cachedHand, cachedInput, cachedValues, cachedAdvice = nil, nil, nil, nil
	meterHand, meterSegment, handMeter = nil, nil, nil
end

local function Reset()
	currentRun, lastSample, epochTime, ready = nil, nil, nil, nil
	pending, diagnosticHand, diagnosticSerial = nil, nil, nil
	if samples[1] then samples = {} end
	ClearHand()
end

local function Recording()
	return Analysis.IsSet("diagnostics") and SurvivorUI_RebornRecording and SurvivorUI_RebornRecording()
end

local function RuntimeNeeded()
	return Analysis.Enabled("live") or Analysis.Enabled("advisor") or Recording()
end

local function CardsNeeded()
	return Analysis.Enabled("cards") or Analysis.Enabled("advisor")
end

Analysis.WantsCardHints = CardsNeeded

function Analysis.ClearCapture()
	pending, diagnosticHand, diagnosticSerial = nil, nil, nil
end

function Analysis.Toggle(key)
	SurvivorUIDB = SurvivorUIDB or {}
	if type(SurvivorUIDB.rebornAnalysis) ~= "table" then SurvivorUIDB.rebornAnalysis = {} end
	SurvivorUIDB.rebornAnalysis[key] = not Analysis.IsSet(key)
	if key == "diagnostics" then Analysis.ClearCapture() end
	if not RuntimeNeeded() and not CardsNeeded() then
		Reset()
		blockedSpells = nil
	end
	if not RuntimeNeeded() and samples[1] then samples = {} end
	if key == "enabled" or key == "cards" or key == "advisor" then
		ClearHand()
		if Analysis.ClearCardDisplay then Analysis.ClearCardDisplay() end
		if CardsNeeded() and Analysis.RefreshCardDisplay then Analysis.RefreshCardDisplay() end
	end
end

local function Run()
	if not SurvivorUI_RebornActive() or type(AZS_ZONE) ~= "table" or Num(AZS_ZONE.hub) == 1
		or type(AZS_RUN) ~= "table" then return nil end
	local phase = AZS_RUN.ph
	if phase ~= "playing" and phase ~= "choosing" and phase ~= "paused" then return nil end
	return SurvivorUI_RebornRunId()
end

local function Boss()
	local only, count
	for _, row in ipairs(AZS_UNITS or {}) do
		if row.kind == "boss" or row.kind == "final" or row.kind == "rift" then
			count = (count or 0) + 1
			only = row
		end
	end
	return count ~= nil, count == 1 and only or nil
end

local function ReadMeter(run, encounter)
	if not AZS_GetMeterSnapshot or not run then return nil end
	local ok, result = pcall(AZS_GetMeterSnapshot, { apiVersion = 1, runId = run, metric = "damage", scope = "self",
		period = encounter and "encounter" or "run", groupBy = "source", windowSeconds = METER_WINDOW })
	local rate = ok and result and result.totals and result.totals.recentRate
	if not rate or rate.status ~= "ready" or (Num(rate.elapsedSeconds) or 0) < METER_WINDOW - 1 then return nil end
	return result, rate
end

local function SingleRowShare(meter, key, spell)
	local total = meter and meter.totals and Num(meter.totals.windowAmount)
	if not total or total <= 0 or spell <= 0 then return nil end
	local amount
	for _, row in ipairs(meter.rows or {}) do
		local source = meter.sources and meter.sources[row.sourceKey]
		if source and source.kind == "ability" and source.abilityKey == key
			and source.spellIds and Num(source.spellIds[1]) == spell then
			if amount ~= nil then return nil end
			amount = Num(row.windowAmount) or 0
		end
	end
	return amount and amount / total or nil
end

local function CurrentSpell(card)
	if not ready or ready ~= AZS_ZONE or not AZS_SPELLS_UPDATED or not AZS_ZONE_UPDATED
		or AZS_SPELLS_UPDATED < AZS_ZONE_UPDATED or AZS_SPELLS == blockedSpells then return nil end
	blockedSpells = nil
	for _, spell in ipairs(AZS_SPELLS or {}) do
		if spell.key == card.key then return spell end
	end
end

local function Fresh(stamp)
	return AZS_ZONE_UPDATED and stamp and stamp >= AZS_ZONE_UPDATED
end

local CAP_FIELDS = { red = "arm", crit = "crit", cdr = "cd", echo = "echo" }
local function Cap(key)
	if ready ~= AZS_ZONE or not Fresh(AZS_CAPS_UPDATED) or not Fresh(AZS_STATS_UPDATED)
		or type(AZS_STATS) ~= "table" then return nil end
	local share = Num(AZS_STATS[CAP_FIELDS[key]])
	if share and share >= 0 and share <= 1 then
		local cap, room = SurvivorUI_RebornStatCap(key, 100 * (key == "cdr" and (1 - share) or share))
		return cap, room and room < 0.00001 and 0 or room
	end
end

local function ContextMatches(inBoss, boss)
	return lastSample and lastSample.inBoss == inBoss and lastSample.bossId == (boss and boss.id)
		and lastSample.bossCount == Num(AZS_RUN.bs)
end

local function Assess(hand)
	local values = {}
	if not ready or ready ~= AZS_ZONE or not hand or type(hand.cards) ~= "table" then return values end
	local inBoss, boss = Boss()
	local time = Num(AZS_RUN.t)
	local stageAge = time and epochTime and time - epochTime
	local meter
	-- A full run window can contain the previous arena or boss. Wait for a clean segment.
	if hand.kind == "spell" and stageAge and stageAge >= METER_WINDOW and ContextMatches(inBoss, boss) then
		if meterHand ~= hand or meterSegment ~= lastSample.segment then
			meterHand, meterSegment = hand, lastSample.segment
			handMeter = ReadMeter(currentRun, inBoss)
		end
		meter = handMeter
	end
	for index = 1, MAX_CARDS do
		local card = hand.cards[index]
		if type(card) == "table" then
			if hand.kind == "spell" and card.key then
				local spell = CurrentSpell(card)
				local share = spell and SingleRowShare(meter, card.key, Num(card.spell) or 0)
				values[index] = Model.Skill(card, spell, share)
			elseif hand.kind == "jewel" then
				values[index] = Model.Jewelry(card, SurvivorUI_RebornCardStatKey, Cap)
			end
		end
	end
	return values
end

local function HandValues(hand)
	local input = hand.kind == "spell" and AZS_SPELLS or AZS_STATS
	local stamp = hand.kind == "spell" and AZS_SPELLS_UPDATED or AZS_STATS_UPDATED
	-- Native tables are replaced. Caps can update independently of the character sheet.
	local caps = hand.kind == "jewel" and AZS_CAPS or false
	local capStamp = hand.kind == "jewel" and AZS_CAPS_UPDATED
	local inBoss, boss = Boss()
	local context = ContextMatches(inBoss, boss)
	if cachedHand ~= hand or not cachedInput or cachedInput.sheet ~= input or cachedInput.caps ~= caps
		or cachedInput.stamp ~= stamp or cachedInput.capStamp ~= capStamp
		or cachedInput.sample ~= lastSample or cachedInput.context ~= context then
		local values = Assess(hand)
		local defense
		if context and (Analysis.Enabled("advisor") or Recording()) then
			defense = Model.Advice(Model.Summarize(samples), values)
		end
		cachedInput = { sheet = input, caps = caps, stamp = stamp, capStamp = capStamp, sample = lastSample, context = context }
		cachedHand, cachedValues, cachedAdvice = hand, values, { defense = defense }
	end
	return cachedValues, cachedAdvice
end

local function ValueText(value)
	if not value then return nil end
	if value.kind == "spell" then
		local lines = {}
		if value.damage then
			local boost = value.damageBoost
			if boost and boost.before and boost.after then
				table.insert(lines, string.format(T("Damage bonus preview %d%% → %d%%"), boost.before, boost.after))
			else
				table.insert(lines, string.format(T("Skill damage preview +%d%%"), value.damage))
			end
		end
		if value.cooldown then
			local cd = value.cooldown
			table.insert(lines, string.format(T("Ideal CD %.2fs → %.2fs"), cd.before, cd.ideal))
		elseif value.frequency then
			table.insert(lines, string.format(T("Ideal cast rate +%.1f%%"), value.frequency))
		end
		if value.meterScenario then
			table.insert(lines, string.format(T("If the meter row scales · +%.1f%% DPS"), value.meterScenario))
		elseif table.getn(lines) == 0 then
			return T("Combat impact unknown")
		end
		return table.concat(lines, "\n")
	end
	local lines = {}
	for _, change in ipairs(value.changes) do
		if change.delta and change.delta ~= 0 and change.room ~= 0 then
			local units = change.percent and T(" pp") or ""
			local tail = change.room and string.format(T(" · %.1f pp to cap"), change.room) or ""
			table.insert(lines, string.format(T("%s preview %+.1f%s"), change.label, change.delta, units) .. tail)
		end
	end
	if table.getn(lines) == 0 then return nil end
	return table.concat(lines, "\n")
end

function Analysis.CardText(index)
	if not CardsNeeded() or not currentRun or currentRun ~= Run() or ready ~= AZS_ZONE then return nil end
	local hand = AZS_CARDS
	if type(hand) ~= "table" then return nil end
	local values, advice = HandValues(hand)
	local text = Analysis.Enabled("cards") and ValueText(values[index]) or nil
	if Analysis.Enabled("advisor") then
		local reason = advice.defense == index and T("Low health · mitigation option")
		if reason then return text and text .. "\n" .. reason or reason end
	end
	return text
end

local function Tooltip(tooltip)
	local run = Run()
	if not run then return end
	if Analysis.Enabled("map") then
		local tier = Num(AZS_ZONE.dt) or Num(AZS_ZONE.heroic)
		local map = SurvivorUI_RebornMapReference and Model.Map(SurvivorUI_RebornMapReference, AZS_ZONE.zone, tier)
		if map then
			tooltip:AddLine(T("Campaign reference · Naxxramas Normal = 100%"), 1, 0.82, 0)
			tooltip:AddLine(string.format(T("Map health tuning %.0f%% · late factor %.2f"), map.health, map.late), 1, 1, 1)
			if Num(AZS_RUN.bs) == 0 then
				tooltip:AddLine(string.format(T("First boss template · health %.0f%% · hit %.0f%%"),
					map.firstBossHealth, map.firstBossHit), 1, 1, 1)
			end
			tooltip:AddLine(string.format(T("Final boss template · health %.0f%% · hit %.0f%%"), map.bossHealth, map.bossHit), 1, 1, 1)
		end
	end
	if not Analysis.Enabled("live") or run ~= currentRun then return end
	local state = Model.Summarize(samples)
	if not state then return end
	local s = state.latest
	local inBoss, boss = Boss()
	if not ContextMatches(inBoss, boss) then return end
	tooltip:AddLine(T("Build observations"), 1, 0.82, 0)
	if s.alive and s.cap then
		tooltip:AddLine(string.format(T("Horde %.0f/%.0f"), s.alive, s.cap), 1, 1, 1)
	end
	if state.lowest then
		tooltip:AddLine(string.format(T("Lowest sampled health %.0f%%"), 100 * state.lowest), 1, 1, 1)
	end
	if state.killsPerMin then
		tooltip:AddLine(string.format(T("%.0f kills/min over %.0fs"), state.killsPerMin, state.elapsed), 1, 1, 1)
	end
	if state.takenPerSec then
		tooltip:AddLine(string.format(T("Recent damage taken · %.0f/s"), state.takenPerSec), 1, 1, 1)
	end
	if state.buildup then
		tooltip:AddLine(string.format(T("Horde building up · +%.0f enemies"), state.enemyDelta), 1, 0.82, 0)
	end
	if state.survival then
		tooltip:AddLine(T("Repeated low health under damage"), 1, 0.6, 0.45)
	end
	if state.levels and state.levels > 0 then
		tooltip:AddLine(string.format(T("Levels gained · %.0f in %.0fs"), state.levels, state.elapsed), 1, 1, 1)
	elseif state.xpPerSec then
		tooltip:AddLine(string.format(T("Experience · %.1f/s at current level"), state.xpPerSec), 1, 1, 1)
	end
	if state.bossNetHPPerSec then
		tooltip:AddLine(string.format(T("Boss net HP loss · %.0f/s"), state.bossNetHPPerSec), 1, 1, 1)
	end
	local time = Num(AZS_RUN.t)
	if time and epochTime and time - epochTime >= METER_WINDOW then
		local _, rate = ReadMeter(run, s.inBoss)
		if rate and Num(rate.value) then
			tooltip:AddLine(string.format(T("Recent effective DPS · %.0f"), rate.value), 1, 1, 1)
		end
	end
end

function Analysis.AddTrackerTooltip(tooltip)
	if Analysis.Enabled("map") or Analysis.Enabled("live") then pcall(Tooltip, tooltip) end
end

local function Record(event, data)
	SurvivorUI_RebornRecord(event, data)
end

local function DiagnosticMeter()
	local inBoss, boss = Boss()
	local time = Num(AZS_RUN.t)
	if not time or not epochTime or time - epochTime < METER_WINDOW or not ContextMatches(inBoss, boss) then return nil end
	local snapshot, rate = ReadMeter(currentRun, inBoss)
	if not snapshot then return nil end
	local rows = {}
	for _, row in ipairs(snapshot.rows or {}) do
		local source = snapshot.sources and snapshot.sources[row.sourceKey]
		local amount = Num(row.windowAmount)
		if source and amount and amount > 0 and table.getn(rows) < 24 then
			table.insert(rows, { key = source.abilityKey or source.talentKey, kind = source.kind,
				spell = source.spellIds and source.spellIds[1], amount = amount })
		end
	end
	return { encounter = inBoss, rate = rate, rows = rows, total = snapshot.totals.windowAmount }
end

local function ReadGear(card)
	local found
	for _, row in ipairs(AZS_GEAR or {}) do
		if card.name and card.slot and card.name == row.name and card.slot == row.slot then
			if found then return nil end
			found = row
		end
	end
	return found
end

local function DiagnosticState(card, kind)
	local spell = kind == "spell" and CurrentSpell(card)
	local gear = kind == "jewel" and ReadGear(card)
	local gearSlot
	if kind == "jewel" and card.slot then
		gearSlot = {}
		for _, row in ipairs(AZS_GEAR or {}) do
			if row.slot == card.slot and table.getn(gearSlot) < 4 then table.insert(gearSlot, row) end
		end
	end
	local tip = spell and AZS_SPELLTIPS and AZS_SPELLTIPS[spell.key]
	return { time = AZS_RUN.t, segment = lastSample and lastSample.segment,
		spell = spell, spellTip = tip, gear = gear, gearSlot = gearSlot,
		stats = Fresh(AZS_STATS_UPDATED) and AZS_RUNSTATS or nil,
		legacyStats = Fresh(AZS_STATS_UPDATED) and AZS_STATS or nil,
		caps = Fresh(AZS_CAPS_UPDATED) and AZS_CAPS or nil, meter = DiagnosticMeter() }
end

-- Called by the existing opt-in command observer. Commands are evidence of intent.
function Analysis.RecordPick(hand, index)
	if not Recording() or currentRun ~= Run() or ready ~= AZS_ZONE or hand ~= diagnosticHand
		or type(hand.cards) ~= "table" or not Num(AZS_RUN.t) then return end
	local card = hand.cards[index]
	if type(card) ~= "table" then return end
	if pending and pending.serial == diagnosticSerial and pending.index == index then return end
	if pending then
		Record("analysis_pick_result", { hand = pending.serial, index = pending.index, status = "superseded" })
	end
	local before = DiagnosticState(card, hand.kind)
	pending = { serial = diagnosticSerial, index = index, card = card, kind = hand.kind,
		time = Num(AZS_RUN.t), previousRank = before.spell and Num(before.spell.rank),
		previousGear = before.gear, gearTable = AZS_GEAR, spellsTable = AZS_SPELLS,
		segment = before.segment, epoch = epochTime, hasBeforeWindow = before.meter ~= nil }
	Record("analysis_pick_before", { hand = diagnosticSerial, index = index, data = before })
end

local function CheckPick(time)
	local p = pending
	if not p then return end
	if not lastSample or p.segment ~= lastSample.segment or p.epoch ~= epochTime then
		Record("analysis_pick_result", { hand = p.serial, index = p.index, status = "segment_changed" })
		pending = nil
		return
	end
	local elapsed = time - p.time
	if not p.confirmed then
		local spell = p.kind == "spell" and p.spellsTable ~= AZS_SPELLS and CurrentSpell(p.card)
		local gear = p.kind == "jewel" and p.gearTable ~= AZS_GEAR and ReadGear(p.card)
		local rank = spell and Num(spell.rank)
		local gearChanged = gear and (not p.previousGear
			or gear.amount ~= p.previousGear.amount or gear.text ~= p.previousGear.text)
		local spellChanged = rank and Num(spell.spell) == Num(p.card.spell) and rank == Num(p.card.rank)
			and (Num(p.card.new) == 1 or (p.previousRank and rank == p.previousRank + 1))
		if spellChanged or gearChanged then
			p.confirmed = time
			Record("analysis_pick_result", { hand = p.serial, index = p.index,
				status = "observed_change", data = DiagnosticState(p.card, p.kind) })
		elseif elapsed > 8 or elapsed < 0 then
			Record("analysis_pick_result", { hand = p.serial, index = p.index, status = "unconfirmed" })
			pending = nil
		end
	elseif time - p.confirmed >= METER_WINDOW then
		local after = DiagnosticState(p.card, p.kind)
		local status = p.hasBeforeWindow and after.meter and "paired" or "window_unavailable"
		Record("analysis_pick_window", { hand = p.serial, index = p.index, status = status, data = after })
		pending = nil
	end
end

local function ObserveRun()
	if not CardsNeeded() and not RuntimeNeeded() then return end
	local run = Run()
	if not run then
		if currentRun then Reset() end
		return
	end
	local r = AZS_RUN
	local time = Num(r.t)
	if not time or time < 0 then return end
	if currentRun ~= run or (lastSample and time < lastSample.time) then
		Reset()
		currentRun = run
	end
	ready = AZS_ZONE
	local inBoss, boss = Boss()
	if ContextMatches(inBoss, boss) and time - lastSample.time < 5 then
		if pending and Recording() then CheckPick(time) end
		return
	end
	local id = boss and boss.id
	local segment = tostring(AZS_ZONE.zone) .. ":" .. tostring(r.bs) .. ":" .. tostring(inBoss) .. ":" .. tostring(id)
	if not lastSample or lastSample.segment ~= segment or time - lastSample.time > 12 then epochTime = time end
	local hp, max = Num(r.hp), Num(r.hpm)
	local sample = { time = time, segment = segment, inBoss = inBoss, bossId = id, bossCount = Num(r.bs),
		bossHP = boss and Num(boss.hp), bossMax = boss and Num(boss.hpm), hp = hp, hpMax = max,
		hpRatio = hp and max and max > 0 and hp / max or nil, taken = Num(r.taken), shield = Num(r.sh),
		level = Num(r.lvl), xp = Num(r.xp), xpNext = Num(r.xpn), kills = Num(r.kills),
		alive = Num(r.en), cap = Num(r.enm), rift = Num(r.rift), phase = r.ph }
	lastSample = sample
	if RuntimeNeeded() then samples = Model.Observe(samples, sample) end
	if CardsNeeded() and Analysis.RefreshCardDisplay then Analysis.RefreshCardDisplay() end
	if Recording() then
		CheckPick(time)
		Record("analysis_run_sample", { zone = AZS_ZONE.zone, tier = AZS_ZONE.dt or AZS_ZONE.heroic, sample = sample })
	elseif pending then pending = nil end
end

local function RefreshInputs(kind)
	if CardsNeeded() and Analysis.RefreshCardDisplay and type(AZS_CARDS) == "table" and AZS_CARDS.kind == kind then
		Analysis.RefreshCardDisplay()
	end
end

local function ObserveOffer()
	if not CardsNeeded() and not Recording() then return end
	if not currentRun or currentRun ~= Run() or ready ~= AZS_ZONE then return end
	local hand = AZS_CARDS
	if not Recording() or diagnosticHand == hand or type(hand) ~= "table"
		or type(hand.cards) ~= "table" or not hand.cards[1] then return end
	handSerial = handSerial + 1
	diagnosticHand, diagnosticSerial = hand, handSerial
	local values, advice = HandValues(hand)
	Record("analysis_offer", { hand = handSerial, zone = AZS_ZONE.zone, tier = AZS_ZONE.dt or AZS_ZONE.heroic,
		time = AZS_RUN.t, values = values, advice = advice, summary = Model.Summarize(samples) })
end

if AZS and type(AZS.On) == "function" then
	AZS.On("AZSRUN", ObserveRun)
	AZS.On("AZSZONE", function()
		if currentRun or CardsNeeded() or Recording() then
			Reset()
			blockedSpells = AZS_SPELLS
		end
	end)
	AZS.On("AZSSPELLS", function() RefreshInputs("spell") end)
	AZS.On("AZS", function() RefreshInputs("jewel") end)
	AZS.On("AZSCAPS", function() RefreshInputs("jewel") end)
	AZS.On("AZSUNITS", function() RefreshInputs("spell") end)
	AZS.On("AZSCARDS", ObserveOffer)
	AZS.On("AZSEND", function()
		if currentRun then Reset() end
		blockedSpells = nil
	end)
end
