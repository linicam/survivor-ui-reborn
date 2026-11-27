-- Exercise the production history watcher before constructing its UI.
table.getn = table.getn or function(value) return #value end
local lastUpdate
function CreateFrame()
	return { RegisterEvent = function() end, SetScript = function(_, event, handler)
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

-- Exercise both Build List consumers with the real compatibility adapter.
-- Only the jewelry rows and inventory/tooltip APIs need host UI stand-ins.
local historyUpdate = lastUpdate
local nativeHandlers = {}
AZS = { On = function(name, handler) nativeHandlers[name] = handler end }
dofile("SurvivorUI/RebornCompat.lua")
local buildFile = assert(io.open("SurvivorUI/BuildList.lua", "rb"))
local buildSource = buildFile:read("*a")
buildFile:close()
local function ReadSection(first, nextSection)
	local start = assert(buildSource:find(first, 1, true))
	local finish = assert(buildSource:find(nextSection, start, true))
	return buildSource:sub(start, finish - 1)
end

local function NoOp() end
local function Color() return 1, 1, 1 end
local rows = {}
local ui = { rows = rows, worn = { title = { SetText = NoOp }, SetHeight = NoOp } }
function ui.GearLine(index)
	if not rows[index] then
		local text = { ClearAllPoints = NoOp, SetPoint = NoOp, SetTextColor = NoOp }
		rows[index] = {
			label = text, tags = text, icon = { SetTexture = NoOp, Show = NoOp, Hide = NoOp },
			Show = function(row) row.shown = true end,
			Hide = function(row) row.shown = false end,
		}
	end
	return rows[index]
end
ui.GearLine(1)
local buildSetup = [[
local ui = ...
local gearLines, worn, GearLine = ui.rows, ui.worn, ui.GearLine
local GEAR_SLOTS = { {11, "Ring"} }
local GEAR_TOP, GEAR_ROW, PLAIN = 20, 18, {1, 1, 1}
local WIDTH, SEPARATOR = 160, " · "
local function Tagged(tag, value) return value .. " " .. tag end
local GEAR_PAINT = { row = {} }
local function Settings() return SurvivorUIDB end
local function ReadPiece() return {rank = 7, tags = "DMG"} end
local function PlaceGear() end
local function PaintGear() end
local function GearText(line, left, right) line.left, line.right = left, right end
local function FitName(line, left) line.left = left end
local function FitTags(line, right) line.right = right end
local function GearWords(label, piece) return label .. "  " .. piece.rank, piece.tags end
local Quality, RarityColor = ui.Color, ui.Color
]]
ui.Color = Color
local drawGear = assert((loadstring or load)(buildSetup
	.. ReadSection("local JEWELRY_TAGS =", "-- For the options' preview")
	.. ReadSection("function SurvivorUI_GearSnapshot()", "-- The armor and the weapons worn")
	.. ReadSection("-- The armor and the weapons worn", "function SurvivorUI_ToggleWorn()")
	.. "return DrawGear", "@BuildList jewelry consumers"))(ui)

function SurvivorUI_T(text) return text end
function UnitName() return "Original Hero" end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Human" end
function getglobal(name) return _G[name] end
local meterCalls = 0
function AZS_GetMeterLoadout()
	meterCalls = meterCalls + 1
	return { runJewelry = {} }
end
local function InventoryLink(_, slot)
	if slot == 11 then return "|cffa335ee|Hitem:123:0|h[Inventory Ring]|h|r" end
end
GetInventoryItemLink = InventoryLink
AZS_RUN, AZS_ZONE = { ph = "victory", t = 600 }, { zname = "Original Arena" }
function AZS_GetPhase() return AZS_RUN.ph end
SurvivorUIDB.jewelryEmpty = false
assert(not SurvivorUI_RebornActive(), "the original Meter API alone does not detect Reborn")
drawGear()
assert(rows[1].shown and rows[1].slot == 11 and rows[1].right == "DMG",
	"original Build List must render the worn inventory ring beside an empty Meter loadout")
local originalGear = SurvivorUI_GearSnapshot()
assert(#originalGear == 1 and originalGear[1].name == "Inventory Ring")
arg1 = 0.6
historyUpdate()
local originalRun = SurvivorUIDB.runHistory[1]
assert(#SurvivorUIDB.runHistory == 5 and originalRun.rebornRunId == nil)
assert(originalRun.gear[1].item == "item:123:0" and originalRun.gear[1].name == "Inventory Ring")
assert(SurvivorUIDB.runHistory[2] == legacy and saved.pinned, "a new snapshot preserves existing history")
assert(meterCalls == 0, "original consumers must skip the Reborn Meter loadout")

-- A detected Reborn client's empty loadout remains authoritative, even
-- with a ring in the inventory and a different fallback gear feed.
AZS_RequestAbilities = NoOp
AZSGEAR = { {key = "fallback", name = "Fallback Ring", slot = "ring"} }
SurvivorUI_RebornForgetRun()
assert(SurvivorUI_RebornActive())
drawGear()
assert(not rows[1].shown and #SurvivorUI_GearSnapshot() == 0 and meterCalls == 1)

function AZS_GetMeterLoadout()
	return {
		runJewelry = {
			{sourceKey = "jewel:ring:accuria", itemInstanceKey = "gear:ring:accuria"},
			{sourceKey = "jewel:ring:accuria", itemInstanceKey = "gear:ring:dragonslayer"},
		},
		sources = { ["jewel:ring:accuria"] = {itemKey = "accuria", name = "Band of Accuria", rank = 4, rarity = "epic"} },
	}
end
SurvivorUI_RebornForgetRun()
drawGear()
local nativeGear = SurvivorUI_GearSnapshot()
assert(#nativeGear == 2 and rows[1].shown and rows[2].shown)
assert(rows[1].rebornItem.instanceKey ~= rows[2].rebornItem.instanceKey)
assert(rows[1].rebornItem.rarity == "epic" and nativeGear[1].name == "Band of Accuria")

AZS_GetMeterLoadout = nil
SurvivorUI_RebornForgetRun()
drawGear()
assert(rows[1].shown and rows[1].rebornItem.name == "Fallback Ring" and not rows[2].shown)
AZSGEAR = nil
SurvivorUI_RebornForgetRun()
drawGear()
local unknown, status = SurvivorUI_GearSnapshot()
assert(not rows[1].shown and #unknown == 0 and status == "unavailable")
assert(SurvivorUI_RunJewelrySummary({ effect = "幸运+75.6% · 金币+63%" }) == "+75.6% LUCK · +63% GOLD")
assert(SurvivorUI_RunJewelrySummary({ effect = "Critical damage +245%" }) == "+245% CRIT DMG")
assert(SurvivorUI_RunJewelrySummary({ effect = "On hit, burn for 40%" }) == "On hit, burn for 40%")
local tip = {}
GameTooltip = {
	SetText = function(_, value) tip[1] = value end,
	AddLine = function(_, value) tip[2] = value end,
	Show = NoOp,
}
SurvivorUI_ShowRunJewelryTooltip({ name = "Full item name", effect = "Luck +75.6%\nSpecial effect" })
assert(tip[1] == "Full item name" and tip[2] == "Luck +75.6%\nSpecial effect")

local charFile = assert(io.open("SurvivorUI/CharacterPane.lua", "rb"))
local character = charFile:read("*a")
charFile:close()
local statsStart = assert(character:find("local function Pct(value)", 1, true))
local statsEnd = assert(character:find("local function ReadsAtMostZero", statsStart, true))
local statValue, sections = assert((loadstring or load)(character:sub(statsStart, statsEnd - 1)
	.. "return StatValue, SECTIONS", "@CharacterPane stat readers"))()
assert(statValue(sections[1].rows[1], { crit = 0 }) == "0.0%")
assert(statValue(sections[1].rows[2], {}) == "-")
assert(statValue(sections[1].rows[3], { dmg = 1.25 }) == "+25%")
assert(statValue(sections[1].rows[4], { cd = 0.85 }) == "+15%")
local contribution, rest = SurvivorUI_StatGear("Damage", { dmg = 1.5, gdmg = 0.2 })
assert(contribution == "+20%" and rest == nil)
assert(SurvivorUI_StatGear("Damage", { dmg = 1.5 }) == nil)
assert(SurvivorUI_StatGear("Damage", { dmg = 1.5, gdmg = 0 }) == "+0%")
contribution, rest = SurvivorUI_StatGear("Damage", { dmg = 1.5, gdmg = 0.2 }, false)
assert(contribution == "+20%" and rest == "+30%")

AZS_GEN = { itemRules = {} }
AZS_ZONE = { run = "azs:r56781234" }
nativeHandlers.AZSZONE()
AZS_GEAR = { { slot = "ring", bonus = "accuria", name = "Native Ring", rarity = 4, text = "Damage +296.2%" } }
nativeHandlers.AZSGEAR()
drawGear()
assert(rows[1].left == "Native Ring" and rows[1].right == "+296.2% DMG")
local gear, gearStatus = SurvivorUI_GearSnapshot()
assert(gearStatus == "observed" and gear[1].effect == AZS_GEAR[1].text and not gear[1].item)
local armor, armorSet, armorStatus = SurvivorUI_ArmorSnapshot()
assert(#armor == 0 and armorStatus == "unavailable")
AZS_ARMOR = { { slot = 8, name = "Native Worn Weapon", rarity = 4 } }
nativeHandlers.AZSARMOR()
armor, armorSet, armorStatus = SurvivorUI_ArmorSnapshot()
assert(armor[1].name == "Native Worn Weapon" and not armorSet and armorStatus == "partial")
AZS_END_LOOT = { { name = "Final reward", rarity = 3 } }
nativeHandlers.AZSENDLOOT()
local loot, lootStatus = SurvivorUI_RebornFinalLootSnapshot()
assert(#loot == 0 and lootStatus == "unavailable")
nativeHandlers.AZSEND()
loot, lootStatus = SurvivorUI_RebornFinalLootSnapshot()
assert(loot[1].name == "Final reward" and lootStatus == "observed" and not loot[1].item)

local completed = Snapshot(AZS_ZONE.run, "Reborn Arena")
completed.gearStatus, completed.armorStatus, completed.lootStatus = "unavailable", "unavailable", "unavailable"
assert(keep(completed) == completed)
local late = Snapshot(AZS_ZONE.run, "Reborn Arena")
late.gear, late.gearStatus, late.armor, late.armorStatus, late.loot, late.lootStatus = gear, gearStatus, armor, armorStatus, loot, lootStatus
assert(keep(late) == completed and completed.gear[1].effect == gear[1].effect and completed.loot[1].name == loot[1].name)
local older = Snapshot("azs:r56781235", "Reborn Arena")
older.gear = { { label = "Preserved historic row" } }
keep(older)
local replay = Snapshot(older.rebornRunId, older.zone)
replay.gear, replay.gearStatus = gear, gearStatus
assert(keep(replay) == older and not older.gearStatus and older.gear[1].label == "Preserved historic row")

AZS_RequestAbilities, GetInventoryItemLink = nil, nil
assert(not SurvivorUI_RebornActive())
drawGear()
assert(not rows[1].shown and SurvivorUI_GearSnapshot()[1].empty)
print("Original and Reborn jewelry rendering, snapshots and Run History capture passed")
