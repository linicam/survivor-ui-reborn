-- Exercise the production history watcher before constructing its UI.
table.getn = table.getn or function(value) return #value end
local lastUpdate
function CreateFrame()
	return { SetScript = function(_, event, handler)
		if event == "OnUpdate" then lastUpdate = handler end
	end }
end
local file = assert(io.open("SurvivorUI/RunHistory.lua", "rb"))
local source = file:read("*a")
file:close()
local uiStart = assert(source:find('local talent = CreateFrame("Frame")', 1, true))
assert((loadstring or load)(source:sub(1, uiStart - 1), "@SurvivorUI/RunHistory.lua"))()

local function WatcherFunction(name)
	for i = 1, 50 do
		local key, value = debug.getupvalue(lastUpdate, i)
		if key == name then return value end
		if not key then break end
	end
	error("Missing watcher function: " .. name)
end

SurvivorUIDB = { historyClassKeys = true, runHistory = {} }
function GetTime() return 1000 end
time, date = os.time, os.date
local runId = "azs:r12345678"
function SurvivorUI_RebornStableRunId(candidate) return candidate or runId end
local keep, settle, endlessOf = WatcherFunction("Keep"), WatcherFunction("Settle"), WatcherFunction("EndlessOf")
local function Snapshot(id, zone)
	return { rebornRunId = id, result = "victory", zone = zone,
		hero = "Hero", time = 300, kills = 8, at = 1000 }
end

local saved = Snapshot(runId, "Arena A")
saved.build, saved.buildComplete, saved.pinned = {}, false, true
assert(keep(saved) == saved)
AZS_RUN, AZS_ZONE = { endl = 1, t = 310 }, { zname = "Arena B" }
assert(endlessOf() == saved)
saved.endless = { result = "going" }
local refresh = Snapshot(runId, "Arena B")
refresh.build, refresh.buildComplete = { { name = "Fireball" } }, true
assert(keep(refresh) == saved and #SurvivorUIDB.runHistory == 1)
assert(saved.buildComplete and saved.build[1].name == "Fireball" and saved.pinned and saved.endless)
keep(Snapshot(runId, "Arena B"))
assert(saved.build[1].name == "Fireball")
assert(settle({ runId = "azs:r12345679", result = "defeat" }) == false)

local nextRun = Snapshot("azs:r12345679", "Arena A")
assert(keep(nextRun) == nextRun and #SurvivorUIDB.runHistory == 2)
assert(endlessOf() == nil)
runId = nil
settle({ runId = nextRun.rebornRunId, result = "victory", kills = 23 })
assert(nextRun.kills == 23 and #SurvivorUIDB.runHistory == 2)
settle({ runId = "azs:r12345680", result = "victory", t = 240 })
local fromSummary = SurvivorUIDB.runHistory[1]
assert(fromSummary.rebornRunId == "azs:r12345680" and fromSummary.time == 240)
assert(fromSummary.hero == "?" and fromSummary.summaryOnly and fromSummary.buildComplete == false)
local legacy = Snapshot(nil, "Arena C")
keep(legacy)
keep(Snapshot(nil, "Arena C"))
assert(#SurvivorUIDB.runHistory == 4)
print("Run History identity and summary regression checks passed")
