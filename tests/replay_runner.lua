-- Replay runner: feeds recorded raw payloads through production
-- RebornCompat logic with a simulated clock derived from recorded
-- event timestamps, and compares normalized output with recorded
-- observations. A mismatch means production behavior changed since
-- recording; decide whether the change is the fix or a regression.
-- Recorded output is evidence, not ground truth. Replay cannot
-- reproduce native rendering or protected actions.
-- Usage: lua tests/replay_runner.lua <fixture.lua>

local fixturePath = arg and arg[1]
if not fixturePath then
	print("usage: lua tests/replay_runner.lua <fixture.lua>")
	os.exit(2)
end

table.getn = table.getn or function(t) return #t end
SurvivorUIDB = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local simTime = 0
local simRunTime = 0
local currentRunId = nil
local runStartTime = 0
function GetTime() return simTime end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
AZS_RequestAbilities = function() end
AZS = { On = function() end }
AZS_GetRunTime = function() return simRunTime end
AZS_API_RunId = function() return currentRunId end
AZS_ZONE = { run = nil }
AZS_RUN = { t = 0 }

dofile("SurvivorUI/RebornCompat.lua")

local events = dofile(fixturePath)
local failures, checks, skipped = 0, 0, 0
local coverage = {}

local function eq(name, got, want)
	checks = checks + 1
	if got ~= want then
		failures = failures + 1
		print(string.format("FAIL %s -- got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

for i = 1, table.getn(events) do
	local e = events[i]
	local before = checks
	simTime = e.t or simTime
	if e.type == "run_transition" then
		currentRunId = e.data and e.data.to or e.run
		runStartTime = simTime
		simRunTime = 0
		AZS_ZONE = { run = currentRunId }
		AZS_RUN = { id = currentRunId, t = 0 }
		SurvivorUI_RebornCheckRun()
		eq("seq " .. tostring(e.seq) .. " run id", SurvivorUI_RebornRunId(), currentRunId)
	else
		if e.run and e.run ~= currentRunId then
			currentRunId = e.run
			runStartTime = simTime
			AZS_ZONE = { run = currentRunId }
		end
		-- Three separate clocks: simTime is session elapsed time,
		-- simRunTime is gameplay/run time (advanced only by recorded
		-- run-time observations or explicit fixture runTime values),
		-- and banner timestamps stay in the raw payloads.
		if e.data and e.data.runTime then
			simRunTime = e.data.runTime
		end
		if type(AZS_RUN) ~= "table" then AZS_RUN = {} end
		AZS_RUN.id = currentRunId
		AZS_RUN.t = simRunTime
	end
	if e.type == "run_transition" then
		-- handled above
	elseif e.type == "abilities_request" then
		-- The request already passed throttling in the captured session.
		SurvivorUI_RebornRequestAbilities(true)
	elseif e.type == "abilities_update" and e.data then
		if e.data.spellsOnly then
			AZS_SPELLS = e.data.rawSpells
			AZS_SPELLS_UPDATED = i
		else
			AZS_ABILITIES = e.data.rawAbilities
			AZS_SPELLS = e.data.rawSpells
			AZS_ABILITIES_UPDATED = i
			AZS_SPELLS_UPDATED = i
		end
		local data = SurvivorUI_RebornAbilities()
		local recorded = e.data.normalized or {}
		eq("seq " .. tostring(e.seq) .. " ability count", table.getn(data.all), table.getn(recorded))
		for j = 1, math.min(table.getn(data.all), table.getn(recorded)) do
			eq("seq " .. tostring(e.seq) .. " key " .. j, data.all[j].key, recorded[j].key)
			eq("seq " .. tostring(e.seq) .. " rank " .. j, data.all[j].rank, recorded[j].rank)
			eq("seq " .. tostring(e.seq) .. " passive " .. j, data.all[j].passive, recorded[j].passive)
		end
		if e.data.expectRacialRemaining ~= nil then
			eq("seq " .. tostring(e.seq) .. " racial remaining", (SurvivorUI_RebornRacialCooldown(20549)), e.data.expectRacialRemaining)
		end
	elseif e.type == "jewelry_update" and e.data then
		local items, duplicates = SurvivorUI_RebornDedupJewelry(e.data.preDedup or {})
		eq("seq " .. tostring(e.seq) .. " jewelry rows", table.getn(items), table.getn(e.data.items or {}))
		eq("seq " .. tostring(e.seq) .. " jewelry duplicates", duplicates, e.data.duplicates or 0)
	elseif e.type == "curse_banner" and e.data and e.data.raw then
		-- Banner timestamps are session-clock values; they never
		-- overwrite the simulated run clock.
		AZS_BANNERS = { e.data.raw }
		local curses = SurvivorUI_RebornCurses()
		if e.data.expectCurseCount ~= nil then
			eq("seq " .. tostring(e.seq) .. " curse count", table.getn(curses.items), e.data.expectCurseCount)
		elseif e.data.expired then
			eq("seq " .. tostring(e.seq) .. " curse expired", table.getn(curses.items), 0)
		elseif e.data.expectActive then
			eq("seq " .. tostring(e.seq) .. " curse active", table.getn(curses.items), 1)
		elseif e.data.effectId then
			local present = false
			for j = 1, table.getn(curses.items) do
				if curses.items[j].effectId == e.data.effectId then present = true end
			end
			eq("seq " .. tostring(e.seq) .. " curse " .. e.data.effectId .. " active",
				present, e.data.decision ~= "ending")
		elseif e.data.effect then
			eq("seq " .. tostring(e.seq) .. " curse effect", curses.items[1] and curses.items[1].text, e.data.effect)
		end
		if e.data.expectEffectId then
			eq("seq " .. tostring(e.seq) .. " curse effect id", curses.items[1] and curses.items[1].effectId, e.data.expectEffectId)
		end
		if e.data.expectLeft ~= nil then
			eq("seq " .. tostring(e.seq) .. " curse left", curses.items[1] and curses.items[1].left, e.data.expectLeft)
		end
	elseif e.type == "boss_transition" and e.data then
		AZS_RUN = e.data.run
		if e.data.run and e.data.run.t then
			simRunTime = e.data.run.t
		end
		if e.data.expectCurseCount ~= nil then
			eq("seq " .. tostring(e.seq) .. " curse count", table.getn(SurvivorUI_RebornCurses().items), e.data.expectCurseCount)
		end
		local nb = SurvivorUI_RebornNextBoss()
		eq("seq " .. tostring(e.seq) .. " boss mode", nb and nb.mode, e.data.nextBoss and e.data.nextBoss.mode)
		eq("seq " .. tostring(e.seq) .. " boss state", nb and nb.state, e.data.nextBoss and e.data.nextBoss.state)
	elseif e.type == "rift_snapshot" then
		AZS_UNITS, AZS_RIFT = e.data.units, e.data.rift
		local bosses = SurvivorUI_RebornRiftBosses()
		local boss
		for _, entry in ipairs(bosses) do
			if entry.id == e.data.id then boss = entry; break end
		end
		eq("seq " .. tostring(e.seq) .. " rift state", boss and boss.state, e.data.state)
		eq("seq " .. tostring(e.seq) .. " rift missing", boss and boss.missing == true, e.data.missing == true)
	elseif e.type == "guardian_snapshot" then
		AZS_LAIRS_UPDATED = e.data.stamp
		eq("seq " .. tostring(e.seq) .. " guardian time", SurvivorUI_RebornGuardianLeft(e.data.lair), e.data.left)
	end
	local counted = coverage[e.type] or { checked = 0, skipped = 0 }
	coverage[e.type] = counted
	if checks > before then counted.checked = counted.checked + 1
	else counted.skipped = counted.skipped + 1; skipped = skipped + 1 end
end

print(string.format("\n%d checks, %d failed, %d events skipped/unsupported", checks, failures, skipped))
local eventTypes = {}
for kind in pairs(coverage) do table.insert(eventTypes, kind) end
table.sort(eventTypes)
for _, kind in ipairs(eventTypes) do
	local counted = coverage[kind]
	print(string.format("  %s: %d checked, %d skipped", kind, counted.checked, counted.skipped))
end
if checks == 0 then
	print("FAIL replay produced zero meaningful checks")
	os.exit(1)
end
if failures > 0 then os.exit(1) end
