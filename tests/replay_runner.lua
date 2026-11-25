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
function GetTime() return simTime end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
AZS_RequestAbilities = function() end
AZS = { On = function() end }
AZS_GetRunTime = function() return simRunTime end

dofile("SurvivorUI/RebornCompat.lua")

local events = dofile(fixturePath)
local failures, checks, skipped = 0, 0, 0

local function eq(name, got, want)
	checks = checks + 1
	if got ~= want then
		failures = failures + 1
		print(string.format("FAIL %s -- got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

for i = 1, table.getn(events) do
	local e = events[i]
	simTime = e.t or simTime
	if e.type == "run_transition" then
		AZS_RUN = { id = e.data and e.data.to }
		simRunTime = 0
		SurvivorUI_RebornCheckRun()
	elseif e.type == "abilities_update" and e.data then
		AZS_ABILITIES = e.data.rawAbilities
		AZS_SPELLS = e.data.rawSpells
		AZS_ABILITIES_UPDATED = i
		AZS_SPELLS_UPDATED = i
		local data = SurvivorUI_RebornAbilities()
		local recorded = e.data.normalized or {}
		eq("seq " .. tostring(e.seq) .. " ability count", table.getn(data.all), table.getn(recorded))
		for j = 1, math.min(table.getn(data.all), table.getn(recorded)) do
			eq("seq " .. tostring(e.seq) .. " key " .. j, data.all[j].key, recorded[j].key)
			eq("seq " .. tostring(e.seq) .. " rank " .. j, data.all[j].rank, recorded[j].rank)
			eq("seq " .. tostring(e.seq) .. " passive " .. j, data.all[j].passive, recorded[j].passive)
		end
	elseif e.type == "jewelry_update" and e.data then
		local items, duplicates = SurvivorUI_RebornDedupJewelry(e.data.preDedup or {})
		eq("seq " .. tostring(e.seq) .. " jewelry rows", table.getn(items), table.getn(e.data.items or {}))
		eq("seq " .. tostring(e.seq) .. " jewelry duplicates", duplicates, e.data.duplicates or 0)
	elseif e.type == "curse_banner" and e.data and e.data.raw then
		AZS_BANNERS = { e.data.raw }
		local curses = SurvivorUI_RebornCurses()
		if e.data.effect then
			eq("seq " .. tostring(e.seq) .. " curse effect", curses.items[1] and curses.items[1].text, e.data.effect)
		else
			skipped = skipped + 1
		end
	elseif e.type == "boss_transition" and e.data then
		AZS_RUN = e.data.run
		local nb = SurvivorUI_RebornNextBoss()
		eq("seq " .. tostring(e.seq) .. " boss mode", nb and nb.mode, e.data.nextBoss and e.data.nextBoss.mode)
		eq("seq " .. tostring(e.seq) .. " boss state", nb and nb.state, e.data.nextBoss and e.data.nextBoss.state)
	else
		skipped = skipped + 1
	end
end

print(string.format("\n%d checks, %d failed, %d events skipped/unsupported", checks, failures, skipped))
if checks == 0 then
	print("FAIL replay produced zero meaningful checks")
	os.exit(1)
end
if failures > 0 then os.exit(1) end
