-- Exercise the production TOC and the actual slash handler without a game client.
table.getn = table.getn or function(values) return #values end

local function Read(name)
	local file = assert(io.open("SurvivorUI/" .. name, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local manifest = {}
for name in Read("SurvivorUI.toc"):gmatch("[^\r\n]+") do
	manifest[name] = true
end
for _, name in ipairs({ "RebornGear.lua", "RebornGearModel.lua", "RebornGearPlanner.lua" }) do
	assert(not manifest[name], name .. " must stay offline")
end
for _, name in ipairs({
	"RebornCompat.lua", "RebornDiagnostics.lua", "BuildList.lua", "CharacterPane.lua",
	"RunHistory.lua", "RebornAnalysis.lua", "RebornAnalysisModel.lua", "RebornMapReference.lua",
	"Tracker.lua", "BossBars.lua", "Guardians.lua", "Jewelry.lua",
}) do
	assert(manifest[name], name .. " must still load")
end

local compile = loadstring or load
local slash = assert(Read("SurvivorUI.lua"):match('(SlashCmdList%["SURVIVORUI"%] = function.-\nend)'))
SlashCmdList = {}
assert(compile(slash))()
local message
local messages = 0
DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) message, messages = line, messages + 1 end }
local english = "Gear Analyzer and Equipment Simulator are suspended. Use the game's equipment interface."
dofile("SurvivorUI/Locale_zh.lua")
local chinese = "装备分析器和装备模拟器已暂停。请使用游戏原生装备界面。"
assert(SurvivorUI_WORDS.zh[english] == chinese)

-- Provide the native signals, legacy tables and an opted-in historical profile.
AZS_RequestAbilities = function() end
AZS_GEN = {
	pieces = {}, setRules = { pieces = { 4, 8 } },
	itemRarities = {}, itemRules = { setPieces = { 2, 4 } },
}
local baseline = { schema = 2, output = 1.5 }
local baselines = { warlock = baseline }
local settings = { enabled = true, baselines = baselines }
SurvivorUIDB = { rebornGear = settings }

-- Throw on entry or synchronization even if a similarly named global exists.
local function Unexpected()
	error("Legacy gear runtime invoked")
end
SurvivorUI_RebornGearOpen = Unexpected
SurvivorUI_RebornGearToggle = Unexpected
SurvivorUI_RebornGearRecordStart = Unexpected
AZS_SendCommand = Unexpected
local handlers = {}
AZS = { On = function(prefix, handler) handlers[prefix] = handler end }
for index, version in ipairs({ "0.8.0", "9.9.9", false }) do
	AZS_VERSION = version or nil
	AZS.ServerBuild = version or nil
	local expected = index == 2 and chinese or english
	SurvivorUI_T = function(key)
		return index == 2 and (SurvivorUI_WORDS.zh[key] or key) or key
	end
	for _, command in ipairs({ "gear", "gear show", "gear worn", "gear simulator", "gear on", "gear off", "gear keys" }) do
		local before = messages
		SlashCmdList.SURVIVORUI(command)
		assert(messages == before + 1 and message == expected, command)
	end
end

local options = Read("Options.lua")
assert(not options:find("SurvivorUI_RebornGear", 1, true))
assert(not options:find("Open Gear & Difficulty", 1, true))
assert(not options:find("Enable Gear & Difficulty", 1, true))

-- The general recorder still starts and reads native run jewelry without the legacy callback.
dofile("SurvivorUI/RebornDiagnostics.lua")
assert(not handlers.AZSARMOR and not handlers.AZSHELLO)
local id = assert(SurvivorUI_RebornRecordStart())
AZS_GEAR = { { slot = "ring", name = "Test jewelry", amount = 1 } }
handlers.AZSGEAR("test")
SurvivorUI_RebornRecordStop()
local observed
for _, event in ipairs(SurvivorUIRebornDiagnostics.sessions[id].events) do
	assert(event.type ~= "gear_analyzer")
	if event.type == "native_gear" then observed = event.data.rows[1].name end
end
assert(observed == "Test jewelry")
assert(SurvivorUIDB.rebornGear == settings and settings.enabled == true)
assert(settings.baselines == baselines and baselines.warlock == baseline)
assert(baseline.schema == 2 and baseline.output == 1.5)
print("PASS: legacy gear load exclusion, slash, settings, and independent diagnostics")
