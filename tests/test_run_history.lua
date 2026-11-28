-- Exercise the production history watcher before constructing its UI.
table.getn = table.getn or function(value) return #value end
local lastUpdate
local worldEvent
local historySource
function CreateFrame()
	return { RegisterEvent = function() end, SetScript = function(_, event, handler)
		if event == "OnUpdate" then lastUpdate = handler end
		if event == "OnEvent" then worldEvent = handler end
	end }
end
local file = assert(io.open("SurvivorUI/RunHistory.lua", "rb"))
historySource = file:read("*a")
file:close()
local uiStart = assert(historySource:find('local talent = CreateFrame("Frame")', 1, true))
local function LoadHistoryWatcher()
	assert((loadstring or load)(historySource:sub(1, uiStart - 1), "@SurvivorUI/RunHistory.lua"))()
	return lastUpdate
end
LoadHistoryWatcher()

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
local function ReadSection(first, nextSection, source)
	source = source or buildSource
	local start = assert(source:find(first, 1, true))
	local finish = assert(source:find(nextSection, start + 1, true))
	return source:sub(start, finish - 1)
end

local function NoOp() end
local function Color() return 1, 1, 1 end
local function FontString()
	local font = { value = "", size = 9, face = "UnitTest", flags = "OUTLINE", ClearAllPoints = NoOp,
		SetPoint = NoOp, SetTextColor = NoOp, Show = NoOp, Hide = NoOp }
	function font:SetText(value) self.value = value end
	function font:GetText() return self.value end
	function font:SetFont(face, size, flags) self.face, self.size, self.flags = face, size, flags end
	function font:GetFont() return self.face, self.size, self.flags end
	function font:SetWidth(width) self.width = width end
	function font:GetStringWidth()
		local ascii = #self.value:gsub("[\128-\255]", "")
		local glyphs = #self.value:gsub("[\128-\191]", "")
		return self.size * (ascii * 0.6 + glyphs - ascii)
	end
	return font
end
local localeFile = assert(io.open("SurvivorUI/Locale.lua", "rb"))
local localeSource = localeFile:read("*a")
localeFile:close()
assert((loadstring or load)(ReadSection("function SurvivorUI_Cut(", "-- Whether the addon", localeSource)))()
SurvivorUI_FONT = "UnitTest"
local rows = {}
local ui = { rows = rows, worn = { title = { SetText = NoOp }, SetHeight = NoOp } }
function ui.GearLine(index)
	if not rows[index] then
		rows[index] = {
			label = FontString(), tags = FontString(), icon = { SetTexture = NoOp, Show = NoOp, Hide = NoOp },
			CreateFontString = FontString,
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
local WIDTH, FONT_BUMP = 160, 0
local function Tagged(tag, value) return value .. " " .. tag end
local GEAR_PAINT = { row = {} }
local function Settings() return SurvivorUIDB end
local function ReadPiece() return {rank = 7, tags = "DMG"} end
local function PlaceGear() end
local function PaintGear() end
local function GearText(line, left, right) line.left, line.right = left, right end
local function GearWords(label, piece) return label .. "  " .. piece.rank, piece.tags end
local Quality, RarityColor = ui.Color, ui.Color
]]
ui.Color = Color
local drawGear = assert((loadstring or load)(buildSetup
	.. ReadSection("local function Letters(", "-- A spell's name fit")
	.. ReadSection("local SEPARATOR =", "-- The quality color a link")
	.. ReadSection("local JEWELRY_TAGS =", "-- For the options' preview")
	.. ReadSection("function SurvivorUI_GearSnapshot(", "-- The armor and the weapons worn")
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

-- A retained Meter loadout and an inventory ring are not current Reborn data.
AZS_RequestAbilities = NoOp
AZSGEAR = { {key = "fallback", name = "Fallback Ring", slot = "ring"} }
SurvivorUI_RebornForgetRun()
assert(SurvivorUI_RebornActive())
for _, capabilities in ipairs({ false, {}, { unknown = true }, { itemRules = {} } }) do
	AZS_GEN = capabilities or nil
	drawGear()
	local unknown, status = SurvivorUI_GearSnapshot()
	assert(not rows[1].shown and #unknown == 0 and status == "unavailable" and meterCalls == 0)
end
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
nativeHandlers.AZSRUN()
AZS_GEAR = { { slot = "ring", bonus = "accuria", name = "Native Ring", rarity = 4, text = "Damage +296.2%" } }
nativeHandlers.AZSGEAR()
drawGear()
assert(rows[1].label:GetText() == "Native Ring" and rows[1].tags:GetText() == "+296.2% DMG")
local gear, gearStatus = SurvivorUI_GearSnapshot()
assert(gearStatus == "observed" and gear[1].effect == AZS_GEAR[1].text and not gear[1].item)
do
	local historyUI = { measure = FontString(), gear = {}, gearTitle = FontString() }
	local function Texture()
		return { SetWidth = NoOp, SetHeight = NoOp, SetPoint = NoOp, SetTexCoord = NoOp,
			SetAllPoints = NoOp, SetVertexColor = NoOp, SetTexture = function(t, value) t.texture = value end }
	end
	function historyUI.Frame()
		return { SetWidth = NoOp, SetHeight = NoOp, EnableMouse = NoOp, CreateTexture = Texture,
			SetScript = function(frame, name, handler) frame[name] = handler end }
	end
	historyUI.Font, historyUI.Texture, historyUI.NoOp = FontString, Texture, NoOp
	local historyDraw = assert((loadstring or load)([[
local buildBox = ...
local CreateFrame, Font, Flat = buildBox.Frame, buildBox.Font, buildBox.Texture
local Edges, Tint, Aside, At, HideAll = buildBox.NoOp, buildBox.NoOp, buildBox.NoOp, buildBox.NoOp, buildBox.NoOp
local GEAR_ROW, INNER, FONT_BUMP, GEAR_TOP = 18, 220, 0, 20
local WHITE, GEAR_SLOT_NAMES = { 1, 1, 1 }, {}
]] .. ReadSection("local function GearLine(", "-- An icon of the armor", historySource)
	.. ReadSection("local function GearLines(", "local function DrawBuild", historySource)
	.. "gearDraw.DrawArmor = function() end\nreturn function(run)\n"
	.. ReadSection("\t-- The jewelry, a line a slot.", "-- The damage by source", historySource)
	, "@RunHistory jewelry rows"))(historyUI)
	local step = 2
	function SurvivorUI_PieceTextStep() return step end
	for _, case in ipairs({
		{ "Ring", "Damage +296.2%\nOn hit, burn for 40%" },
		{ "南海海藻坠饰南海海藻坠饰", "幸运+75.6% · 金币+63%\n命中时触发额外效果" },
	}) do
		AZS_GEAR = { { slot = "ring", bonus = "accuria", name = case[1], text = case[2], amount = 296 } }
		nativeHandlers.AZSGEAR()
		drawGear()
		local withoutIcon = rows[1].tagText
		AZS_GEAR[1].icon = "INV_Jewelry_Ring_41"
		nativeHandlers.AZSGEAR()
		drawGear()
		assert(rows[1].tagText ~= withoutIcon and rows[1].tags:GetText() ~= "")
		assert(rows[1].label:GetStringWidth() + rows[1].tags:GetStringWidth() <= 160 - 8 - 10 - 18)
		assert(not rows[1].tags:GetText():find("296", 1, true) or rows[1].tags:GetText():find("+296.2%", 1, true))
		local snapshot, status = SurvivorUI_GearSnapshot()
		historyDraw({ gear = snapshot, gearStatus = status })
		local row = historyUI.gear[1]
		assert(row.icon.texture and row.label:GetStringWidth() <= row.label.width and row.tags:GetStringWidth() <= row.tags.width)
		assert(row.runJewelry.tags == SurvivorUI_RunJewelrySummary(rows[1].rebornItem))
		_G.this = row
		row.OnEnter()
		assert(tip[1] == case[1] and tip[2] == case[2], "historical hover keeps the full native text")
	end
	SurvivorUI_PieceTextStep = nil
	print("Live and historical jewelry production rows fit icons and scaled enUS/zhCN text")
end
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
AZS_END = { result = "victory", t = 600 }
nativeHandlers.AZSEND()
loot, lootStatus = SurvivorUI_RebornFinalLootSnapshot()
assert(loot[1].name == "Final reward" and lootStatus == "observed" and not loot[1].item)

local completed = Snapshot(AZS_ZONE.run, "Reborn Arena")
completed.gearStatus, completed.armorStatus, completed.lootStatus = "unavailable", "unavailable", "unavailable"
assert(keep(completed) == completed)
local late = Snapshot(AZS_ZONE.run, "Reborn Arena")
late.gear, late.gearStatus, late.armor, late.armorStatus, late.loot, late.lootStatus = gear, gearStatus, armor, armorStatus, loot, lootStatus
assert(keep(late) == completed and completed.gear[1].effect == gear[1].effect and completed.loot[1].name == loot[1].name)
local another = Snapshot(AZS_ZONE.run, "Reborn Arena")
another.gear, another.gearStatus = { { effect = "Damage +900%" } }, "observed"
assert(keep(another) == completed and completed.gear == gear, "Keep does not replace an observed snapshot")
local older = Snapshot("azs:r56781235", "Reborn Arena")
older.gear = { { label = "Preserved historic row" } }
keep(older)
local replay = Snapshot(older.rebornRunId, older.zone)
replay.gear, replay.gearStatus = gear, gearStatus
assert(keep(replay) == older and not older.gearStatus and older.gear[1].label == "Preserved historic row")

do
	local update = LoadHistoryWatcher()
	local world = worldEvent
	local a, b = "azs:r00100001", "azs:r00100002"
	local party, down
	function SurvivorUI_InParty() return party end
	function SurvivorUI_IsDown() return down end
	function AZS_GetRunSummary() return AZS_END end
	function GetZoneText() return "Zone" end
	function UnitName() return "Test Hero" end
	local function Tick() arg1 = 0.6; update() end
	local function Phase(phase, endless)
		AZS_RUN = { ph = phase, t = endless and 1210 or 1200, endless = endless and 1 or 0 }
		nativeHandlers.AZSRUN()
	end
	local function Zone(id, phase)
		AZS_ZONE = { run = id, zname = "Test Zone", hub = not id and 1 or 0 }
		nativeHandlers.AZSZONE()
		if phase then Phase(phase) end
	end
	local function Gear(name, effect)
		AZS_GEAR = name and { { slot = "ring", bonus = "accuria", name = name, amount = 296, text = effect } } or {}
		nativeHandlers.AZSGEAR()
	end
	local function Armor(name)
		AZS_ARMOR = { { slot = 8, name = name } }
		nativeHandlers.AZSARMOR()
	end
	local function Loot(name)
		AZS_END_LOOT = name and { { name = name, rarity = 4 } } or {}
		nativeHandlers.AZSENDLOOT()
	end
	local function Summary(result, seconds, id)
		AZS_END = { result = result, t = seconds, kills = seconds, runId = id,
			dealt = 9765, dmg = 50, caches = 7, chests = 1, txp = 13 }
		AZS_END_UPDATED = 1000 -- Deliberately the same stamp for adjacent notices.
		nativeHandlers.AZSEND()
	end
	local function Reset()
		party, down = nil, nil
		SurvivorUIDB.runHistory = {}
		SurvivorUI_RebornForgetRun()
		update = LoadHistoryWatcher()
		Zone(a, "playing")
	end
	local function First() return SurvivorUIDB.runHistory[1] end
	Reset()
	Gear("Initial", "Damage +100%")
	Armor("Initial armor")
	Phase("victory")
	Tick()
	assert(First().gearStatus == "observed" and First().gear[1].name == "Initial")
	Gear("Final", "Damage +296.2%")
	Armor("Final armor")
	Summary("victory", 1200)
	-- Production replaces these tables. Mutating the mocks also verifies the
	-- event copy survives clients or test hosts that reuse their references.
	AZS_GEAR[1].text, AZS_ARMOR[1].name, AZS_END.kills = "Damage +900%", "Unobserved", 99999
	Tick()
	local campaign = First()
	assert(campaign.gear[1].effect == "Damage +296.2%", "settlement refreshes an already observed end-phase snapshot")
	assert(campaign.armor[1].name == "Final armor" and campaign.kills == 1200)
	assert(campaign.dealt == 9765 and campaign.caches == 7 and campaign.talentXp == 13)
	Loot("Delayed paired reward")
	Tick()
	assert(campaign.lootStatus == "unavailable", "an orphan sidecar cannot settle a run")
	Gear("Later duplicate", "Damage +400%")
	Summary("victory", 1200)
	Tick()
	assert(campaign.gear[1].name == "Final" and campaign.loot[1].name == "Delayed paired reward")
	Loot("Conflicting reward")
	Summary("victory", 1201)
	Tick()
	assert(campaign.time == 1200 and campaign.loot[1].name == "Delayed paired reward")
	update = LoadHistoryWatcher() -- New addon state on the end screen, existing SavedVariables.
	SurvivorUI_RebornForgetRun()
	Zone(a, "victory")
	Gear("Fresh reload snapshot", "Damage +40%")
	Summary("victory", 1200)
	Tick()
	assert(#SurvivorUIDB.runHistory == 1 and First() == campaign and campaign.gear[1].name == "Final")

	Reset()
	Gear("Old", "Damage +100%")
	Phase("victory")
	Tick()
	Gear()
	Loot()
	Summary("victory", 1200)
	Tick()
	assert(First().gearStatus == "observed" and #First().gear == 0 and First().lootStatus == "observed" and #First().loot == 0)
	Reset()
	Gear("Old", "Damage +100%")
	Phase("victory")
	Tick()
	Gear("Partial", nil)
	Summary("victory", 1200)
	Tick()
	assert(First().gear[1].name == "Partial" and First().gearStatus == "partial")
	AZS_GEAR[1].text = "Damage +70%"
	nativeHandlers.AZSGEAR()
	Summary("victory", 1200)
	Tick()
	assert(First().gear[1].effect == "Damage +70%" and First().gearStatus == "observed")

	Reset()
	Gear("Campaign ring", "Damage +100%")
	Armor("Campaign armor")
	Loot("Campaign reward")
	Summary("victory", 1200) -- Native end arrives before the terminal phase.
	Phase("victory")
	Phase("playing", true) -- Continuation before the history watcher polls.
	assert(SurvivorUI_RebornEquipmentObservations().jewelry == nil)
	Loot("Rejected late Campaign reward")
	Summary("victory", 1200)
	Gear("Endless ring", "Damage +200%")
	Armor("Endless armor")
	Loot("Endless reward")
	Summary("defeat", 1210)
	Phase("dead", true)
	Tick()
	campaign = First()
	assert(campaign.result == "victory" and campaign.gear[1].name == "Campaign ring")
	assert(campaign.armor[1].name == "Campaign armor" and campaign.loot[1].name == "Campaign reward")
	assert(campaign.endless.gear[1].name == "Endless ring" and campaign.endless.armor[1].name == "Endless armor")
	assert(campaign.endless.loot[1].name == "Endless reward" and campaign.endless.result == "dead")
	Gear("Delayed Endless", "Damage +55%")
	Summary("defeat", 1210)
	Tick()
	assert(#SurvivorUIDB.runHistory == 1 and campaign.gear[1].name == "Campaign ring" and campaign.endless.gear[1].name == "Endless ring")

	Reset()
	Gear("Outgoing", "Damage +100%")
	Phase("victory")
	Tick()
	Gear("Outgoing final", "Damage +150%")
	Summary("victory", 1200)
	Zone(b)
	Tick() -- Old terminal AZS_RUN remains until the current AZSRUN.
	assert(First().rebornRunId == a and First().gear[1].name == "Outgoing final" and #SurvivorUIDB.runHistory == 1)
	Phase("playing")
	Gear("Incoming", "Damage +200%")
	Loot("Unpaired loot")
	Summary("victory", 1200, a)
	Phase("dead")
	Summary("defeat", 1211, b)
	Tick()
	assert(First().rebornRunId == b and First().gear[1].name == "Incoming" and First().lootStatus == "unavailable")
	assert(SurvivorUIDB.runHistory[2].gear[1].name == "Outgoing final")

	Reset()
	Gear("Before Hub", "Damage +100%")
	Loot("Before Hub reward")
	Summary("left", 1190)
	_G.event = "PLAYER_LEAVING_WORLD"
	world()
	_G.event = "PLAYER_ENTERING_WORLD"
	world()
	Zone(nil, "ready")
	Gear("Stale after Hub", "Damage +900%")
	Summary("left", 1191)
	Tick()
	assert(First().result == "left" and First().gear[1].name == "Before Hub" and First().loot[1].name == "Before Hub reward")
	assert(not SurvivorUI_RebornEquipmentObservations())

	Reset()
	party, down = true, true
	Phase("dead")
	Summary("defeat", 1180)
	Tick()
	assert(not First())
	down = false
	Phase("playing")
	Summary("defeat", 1180)
	Tick()
	assert(not First(), "revival drops the temporary defeat")
	Gear("Co-op final", "Luck +75.6%")
	Summary("victory", 1200)
	Tick()
	assert(not First(), "early co-op end waits for the phase")
	Phase("victory")
	Tick()
	assert(First().gear[1].name == "Co-op final")
	print("Run History native event order, final freshness, mode and world isolation passed")
end

-- Reserve room for the count even beside a long localized name and icon.
AZS_ZONE = { run = "azs:r00000007" }
AZS_RUN = { ph = "playing" }
nativeHandlers.AZSZONE()
nativeHandlers.AZSRUN()
AZS_GEAR = { { slot = "ring", bonus = "accuria", name = "埃库利亚指环的长名称用于测试换行",
	icon = "INV_Jewelry_Ring_15", text = "伤害+296.2% · 幸运+75.6%", amount = 296 } }
nativeHandlers.AZSGEAR()
SurvivorUI_RebornProgression = {
	Live = function() return "live" end,
	JewelryCount = function(_, snapshot)
		if snapshot == "live" then return 2, true end
		if snapshot == "historical" then return 1, false end
	end,
	EnhancementText = function(count, complete) return tostring(count)..":"..tostring(complete) end,
}
drawGear()
assert(rows[1].enhancements:GetText() == "+2")
assert(rows[1].label:GetStringWidth() + rows[1].tags:GetStringWidth() <= 160 - 8 - 10 - 18 - rows[1].countSpace)
local historic = SurvivorUI_GearSnapshot(SurvivorUI_RebornEquipmentObservations(), "historical")
assert(historic[1].enhancements == 1 and historic[1].enhancementsComplete == false)
assert(historic[1].effect == "伤害+296.2% · 幸运+75.6%")
local tipLines = {}
GameTooltip.AddLine = function(_, value) tipLines[#tipLines + 1] = value end
SurvivorUI_ShowRunJewelryTooltip(historic[1])
assert(tipLines[1] == historic[1].effect and tipLines[2] == "1:false")
SurvivorUI_RebornProgression = nil

AZS_RequestAbilities, GetInventoryItemLink = nil, nil
assert(not SurvivorUI_RebornActive())
drawGear()
assert(not rows[1].shown and SurvivorUI_GearSnapshot()[1].empty)
print("Original and Reborn jewelry rendering, snapshots and Run History capture passed")
