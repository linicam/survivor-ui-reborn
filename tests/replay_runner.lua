-- Replay runner: feeds recorded raw payloads through production
-- RebornCompat logic and compares normalized output with the
-- recorded normalized result. Usage:
--   lua tests/replay_runner.lua <fixture.lua>
-- A mismatch means production behavior changed since recording;
-- decide whether the change is the fix or a regression. Replay
-- cannot reproduce native rendering or protected actions.

local fixturePath = arg and arg[1]
if not fixturePath then
	print("usage: lua tests/replay_runner.lua <fixture.lua>")
	os.exit(2)
end

-- Minimal game-environment mocks (mirrors test_reborn_compat.lua).
table.getn = table.getn or function(t) return #t end
SurvivorUIDB = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function GetTime() return 1000 end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
AZS_RequestAbilities = function() end
AZS = { On = function() end }
AZS_GetRunTime = function() return 100 end

dofile("SurvivorUI/RebornCompat.lua")

local events = dofile(fixturePath)
local failures = 0
local checks = 0

local function eq(name, got, want)
	checks = checks + 1
	if got ~= want then
		failures = failures + 1
		print(string.format("FAIL %s -- got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

for i = 1, table.getn(events) do
	local e = events[i]
	if e.type == "abilities_update" and e.data then
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
	elseif e.type == "curse_banner" and e.data and e.data.raw then
		AZS_BANNERS = { e.data.raw }
		local curses = SurvivorUI_RebornCurses()
		eq("seq " .. tostring(e.seq) .. " curse effect", curses.items[1] and curses.items[1].text, e.data.effect or (curses.items[1] and curses.items[1].text))
	end
end

print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
