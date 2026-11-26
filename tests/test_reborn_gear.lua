-- Synthetic catalog and exhaustive checks for the read-only gear planner.
table.getn = table.getn or function(t) return #t end
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornMapReference.lua")
dofile("SurvivorUI/RebornGearModel.lua")
local G = SurvivorUI_RebornGearModel
local keys = { "head", "shoulders", "chest", "waist", "legs", "feet", "wrists", "hands", "main_hand", "off_hand", "ranged" }
AZS_GEN = {
	zones = {
		{ key = "naxx", name = "Naxxramas", world = 1 },
		{ key = "elwynn", name = "Elwynn Forest", world = 1 },
		{ key = "shadowmoon", name = "Shadowmoon Valley", world = 2 },
		{ key = "unmodeled", name = "Unmodeled", world = 2 },
	},
	pieces = {
		scale = { top = 5, steps = 4, factor = 0.7, slot = { 1, 1.7, 2.5, 3.5, 4.6, 4 },
			profile = { 0, 1, 1.6, 2.4, 3.4, 2.9 }, starStep = { 0.64, 0.4, 0.28, 0.17, 0.12, 0.15 },
			starLast = { 3.73, 1.85, 0.85, 0.42, 0.12, 0.22 } },
		slots = {}, classProfiles = { warlock = { 0, 0, 0, 0, 0, 0, 0, 0 }, paladin = { 0, 0, 0, 0, 0, 0, 0, 0 } },
		profiles = { [0] = { { "crit", 0.01 } } },
	},
	gearTiers = {
		{ key = "exotic", rank = 7, slot_scale = 5.6, profile_scale = 4.2, star_step = 0.1, star_last = 0.1, star_factor = 5.8 },
		{ key = "mythic", rank = 8, slot_scale = 6.4, profile_scale = 4.8, star_step = 0.1, star_last = 0.1, star_factor = 7.2 },
		{ key = "elementium", rank = 9, slot_scale = 7.4, profile_scale = 5.4, star_step = 0.1, star_last = 0.1, star_factor = 7.6 },
	},
	setRules = { pieces = { 4, 8 }, stars = { 1, 3 }, empowerStars = 5 },
	setBonuses = {
		{ class = "", rarity = 0, pieces = 4, text = "Pickup +{v}", v = { 12, 18 } },
		{ class = "warlock", rarity = 0, pieces = 8, text = "Hits {v}", v = { 2, 3 } },
	},
}
for i, key in ipairs(keys) do
	AZS_GEN.pieces.slots[i - 1] = { key = key, profile = i <= 8, stats = { { "damage", i == 10 and 0.06 or 0.12 } } }
end
local cat = assert(G.Catalog(AZS_GEN))
local function near(a, b) assert(math.abs(a - b) < 0.0000001, tostring(a) .. " ~= " .. tostring(b)) end
local priceTable = {
	common = { 408, 816, 1496, 2720, 4080 }, uncommon = { 694, 1387, 2543, 4624, 6936 },
	rare = { 1020, 2040, 3740, 6800, 10200 }, epic = { 1428, 2856, 5236, 9520, 14280 },
	pvp = { 1632, 3264, 5984, 10880, 16320 }, legendary = { 1877, 3754, 6882, 12512, 18768 },
	exotic = { 2366, 4733, 8677, 15776, 23664 }, mythic = { 2938, 5875, 10771, 19584, 29376 },
	elementium = { 3101, 6202, 11370, 20672, 31008 },
}
local markedTotal, listedTotal = 0, 0
for tier, prices in pairs(priceTable) do
	for star, price in ipairs(prices) do
		local amount, source = G.StarQuote(cat, "head", tier, star)
		local weapon, weaponSource = G.StarQuote(cat, "main_hand", tier, star)
		local estimated = tier == "exotic" or tier == "elementium" or (tier == "legendary" and star == 5)
		assert(amount == price and weapon == price)
		assert(source == (estimated and "estimated" or "table"))
		assert(weaponSource == (estimated and "estimated" or "weapon"))
		if not estimated then markedTotal = markedTotal + amount end
		if tier ~= "elementium" then listedTotal = listedTotal + amount end
	end
end
assert(markedTotal * 8 == 1715784 and listedTotal * 8 == 2307656)
assert(not G.StarQuote(cat, "head", "rare", 0) and not G.StarQuote(cat, "head", "rare", 6))
cat.tiers.elementium.starFactor = 7.7
assert(not G.StarQuote(cat, "head", "elementium", 1), "a changed live multiplier invalidates the pinned price")
cat.tiers.elementium.starFactor = 7.6
local priced = assert(G.Parse(cat, "warlock", "head legendary 3 worn\nmain_hand common 2 worn", true))
assert(priced.incomplete and priced.usesPriceTable)
assert(#priced.groups[1].worn.choices == 2 and priced.groups[1].worn.choices[2].cost == 12512)
assert(priced.groups[2].worn.choices[4].cost == 8296)
local overridden = assert(G.Parse(cat, "warlock", "head common 0 worn 400", true))
assert(not overridden.usesPriceTable and #overridden.groups[1].worn.choices == 2, "a conflicting quote suppresses automatic continuation")
local worn = assert(G.Worn(cat, "warlock", { { slot = "8", rarity = "7", stars = "2" },
	{ slot = 1, rarity = "" }, { slot = 0, rarity = 4, stars = 0 } }))
assert(#worn == 2 and worn[1].tier == "legendary" and worn[2].slot == "main_hand" and worn[2].tier == "mythic")
assert(not G.Worn(cat, "warlock", { { slot = 0, rarity = 0, stars = 0 }, { slot = 0, rarity = 1, stars = 1 } }))
assert(not G.Worn(cat, "warlock", {}) and not G.Worn(cat, "warlock", { { slot = 0, rarity = 2 } }))
local candidate = assert(G.WornPlan(cat, "warlock", { { slot = "head", tier = "elementium", stars = 0 } }))
local source = { pressure = 1, damage = candidate.current[1].power }
local strict = assert(G.UnderBaseline(candidate, 1, source))
assert(strict.current == 1 and strict.after < 1 and strict.reached and strict.cost == 3101 and strict.pieces[1].stars == 1)
local easy = assert(G.UnderBaseline(candidate, 0.9, source))
assert(easy.reached and easy.cost == 0 and easy.pieces[1].stars == 0)
local impossible = assert(G.UnderBaseline(candidate, 12, source))
assert(not impossible.reached and impossible.after >= 1 and impossible.cost == 72353 and impossible.pieces[1].stars == 5)
near(G.Piece(cat, "warlock", "main_hand", "common", 0).damage, 0.084)
near(G.Piece(cat, "warlock", "main_hand", "common", 5).damage, 0.61236)
near(G.Piece(cat, "warlock", "main_hand", "exotic", 0).damage, 0.4704)
assert(not G.Piece(cat, "warlock", "main_hand", "common", 6))
assert(not G.Parse(cat, "warlock", "head rare 2 farm"))
assert(not G.Parse(cat, "warlock", "head rare 2 worn 2,,3"))
assert(not G.Parse(cat, "warlock", "head rare 2 worn\nhead common 0 farm"))
assert(not G.Parse(cat, "warlock", "head rare 2 worn\nhead common 0 worn"))
assert(not G.Parse(cat, "warlock", "head unknown 0 worn"))
local plan = assert(G.Parse(cat, "warlock",
	"main_hand common 4 worn 100\nmain_hand rare 0 farm 200\nmain_hand epic 4 owned 60"))
assert(G.Optimize(plan, 0.1, false).cost == 0)
assert(G.Optimize(plan, 0.5, false).cost == 100)
local solved = G.Optimize(plan, 0.4, true)
assert(solved.cost == 0 and solved.pieces[1].tier == "epic" and solved.pieces[1].stars == 4)
assert(G.Optimize(plan, 99, false).pieces[1].stars == 5 and not G.Optimize(plan, 99, false).reached)
local limited, reason = G.Optimize(plan, 99, true, 2)
assert(not limited and reason == "limit")
local pieces = {}
for i, key in ipairs(keys) do
	pieces[i] = { slot = key, tier = "common", stars = 5, stats = {} }
end
local _, sets = G.Totals(cat, "warlock", pieces)
assert(sets.common[1].text == "Pickup +12" and sets.common[2].text == "Hits 3")
pieces[8].stars = 2
_, sets = G.Totals(cat, "warlock", pieces)
assert(#sets.common == 1, "weapons cannot restore eight armor pieces at three stars")
pieces[8].stars = 3
_, sets = G.Totals(cat, "warlock", pieces)
assert(sets.common[2].text == "Hits 2")
for i = 4, 8 do pieces[i].tier = "rare" end
_, sets = G.Totals(cat, "warlock", pieces)
assert(not sets.common)
local naxx = G.Pressure(SurvivorUI_RebornMapReference, "naxx", 0)
near(naxx, 1)
near(G.Pressure(SurvivorUI_RebornMapReference, "naxx", 5), 2.72)
local ratio, target = G.Scenario(1.2, { pressure = 1, damage = 0.2 }, 0.2, 0.1)
near(ratio, 1.2); near(target, 0.46)

local four = assert(G.Parse(cat, "warlock", table.concat({
	"head common 1 worn 60", "shoulders common 1 worn 1", "chest common 1 worn 100",
	"waist common 1 worn 90", "head legendary 0 farm", "main_hand common 0 worn"
}, "\n")))
local _, active = G.Totals(cat, "warlock", four.current)
local protection = G.SetRequirements(active, cat.native.setRules)
assert(protection[1].stars == 1 and protection[1].count == 4)
local free = assert(G.Optimize(four, 0.65, true))
assert(free.cost == 0 and not G.KeepsSets(free.pieces, protection))
local careful = assert(G.Optimize(four, 0.65, true, nil, protection))
assert(careful.cost == 1 and G.KeepsSets(careful.pieces, protection))
assert(not G.Optimize(four, 99, true, nil, protection).reached)

-- An independent exhaustive enumerator checks the frontier and both tie breaks.
math.randomseed(8245)
local function Exhaustive(options, target, protected)
	local best
	local function Visit(i, cost, power, eligible)
		if i <= #options then
			for _, choice in ipairs(options[i]) do
				local counts = choice.armor and choice.tier == "common" and choice.stars >= 1
				Visit(i + 1, cost + choice.cost, power + choice.power, eligible + (counts and 1 or 0))
			end
			return
		end
		if eligible < protected then return end
		local reaches = power >= target
		if not best or (reaches and not best.reached)
			or (reaches and best.reached and (cost < best.cost or (cost == best.cost and power > best.power)))
			or (not reaches and not best.reached and (power > best.power or (power == best.power and cost < best.cost))) then
			best = { cost = cost, power = power, reached = reaches }
		end
	end
	Visit(1, 0, 0, 0)
	return best
end
for _ = 1, 400 do
	local slots, choices, worn = {}, {}, {}
	for i = 1, 4 do
		local options = { { slot = keys[i], cost = 0, power = 0, armor = true, tier = "common", stars = i - 1 } }
		for j = 1, 4 do
			table.insert(options, { slot = keys[i], cost = math.random(0, 10), power = math.random(0, 10),
				armor = true, tier = j <= 2 and "common" or "rare", stars = math.random(0, 5) })
		end
		local entry = { choices = options }
		slots[i], choices[i], worn[i] = { worn = entry, entries = { entry } }, options, options[1]
	end
	local threshold = math.random(1, 45)
	local expected = Exhaustive(choices, threshold, 0)
	local got = assert(G.Optimize({ groups = slots, current = worn }, threshold, true))
	assert(got.cost == expected.cost and got.power == expected.power and got.reached == expected.reached)
	expected = Exhaustive(choices, threshold, 3)
	got = assert(G.Optimize({ groups = slots, current = worn }, threshold, true, nil,
		{ { tier = "common", stars = 1, count = 3 } }))
	assert(got.cost == expected.cost and got.power == expected.power and got.reached == expected.reached)
end

-- World-UI lifecycle with mock widgets. The module creates no frame until requested.
local widgets, buttons, logs = {}, {}, {}
local count, menus, options = 0, {}, nil
function CreateFrame(kind, name, parent)
	count = count + 1
	local w = { name = name, kind = kind, parent = parent, scripts = {}, shown = true, messages = {} }
	function w:CreateFontString() return CreateFrame("FontString", nil, self) end
	function w:SetText(text)
		self.text = text
		if self.kind == "Button" then buttons[text] = self end
		if self.scripts.OnTextChanged then self.scripts.OnTextChanged() end
	end
	function w:GetText() return self.text or "" end
	function w:SetScript(event, fn) self.scripts[event] = fn end
	function w:Clear() self.messages = {} end
	function w:AddMessage(text) table.insert(self.messages, text) end
	function w:Show() self.shown = true end
	function w:Hide() self.shown = false end
	function w:IsShown() return self.shown end
	table.insert(widgets, w)
	return setmetatable(w, { __index = function() return function() end end })
end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize(menu, fill) menus[menu.name] = fill end
function UIDropDownMenu_SetSelectedValue(menu, value) menu.selectedValue = value end
function UIDropDownMenu_SetText(menu, text) menu.text = text end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) table.insert(options, info) end
local function Pick(name, key)
	options = {}
	menus["SurvivorUIRebornGear" .. name]()
	for _, option in ipairs(options) do
		if option.value == key then option.func(); return true end
	end
	return false
end
function SurvivorUI_T(string) return string end
function SurvivorUI_TF(text, value) return (string.gsub(text, "{1}", value)) end
local reborn, phase = false, "playing"
function SurvivorUI_RebornActive() return reborn end
function SurvivorUI_RebornStableRunId(run) return run end
function AZS_GetPhase() return phase end
local handlers = {}
AZS = { On = function(event, callback) handlers[event] = callback end }
local commands = {}
AZS_SendCommand = function(command) table.insert(commands, command) end
time = function() return 100 end
local dateAt, zone
date = function(_, at) dateAt = at; return "2026-11-26 12:00" end
function SurvivorUI_TimeZone() return zone end
local dollSlot = { slot = 0, hooks = 0 }
function dollSlot:HookScript(event, fn)
	assert(event == "OnEnter")
	self.hooks, self.afterEnter = self.hooks + 1, fn
end
GameTooltip = {
	IsOwned = function(self, owner) return self.owner == owner end,
	AddLine = function(self, text) table.insert(self.lines, text) end,
	Show = function() end,
}
function dollSlot:Hover()
	GameTooltip.owner, GameTooltip.lines = self, { "Native tooltip" }
	if self.afterEnter then self.afterEnter(self) end
	return table.concat(GameTooltip.lines, "\n")
end
AZSInspect = { unit = "player", shown = true }
function AZSInspect:IsShown() return self.shown end
function AZSInspect:Hide() self.shown = false end
function AZSInspect:RefreshDoll(armor)
	AZSInspectSlot0 = { GetParent = function() return dollSlot end }
	dollSlot.piece = armor[1]
end
function hooksecurefunc(target, method, callback)
	local original = target[method]
	target[method] = function(self, ...)
		original(self, ...)
		callback(self, ...)
	end
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(logs, text) end }
dofile("SurvivorUI/RebornGear.lua")
assert(count == 0)
SurvivorUI_RebornGearOpen()
assert(count == 0)
reborn = true
AZS_ZONE = { zone = "naxx", dt = 1, zname = "Naxxramas", class = "warlock" }
phase = "ready"
AZSInspect:RefreshDoll({ { slot = 0, rarity = 0, stars = 0 } })
AZSInspect:RefreshDoll({ { slot = 0, rarity = 0, stars = 0 } })
local tooltip = dollSlot:Hover()
assert(dollSlot.hooks == 1 and string.find(tooltip, "Native tooltip", 1, true))
assert(string.find(tooltip, "Next star · ★0 → ★1", 1, true) and string.find(tooltip, "408 gold", 1, true))
assert(not string.find(tooltip, "(table)", 1, true))
assert(string.find(tooltip, "Damage +5.38%", 1, true))
AZSInspect.unit = "party1"
assert(dollSlot:Hover() == "Native tooltip", "a party member's tooltip is not changed")
AZSInspect.unit = "player"
AZSInspect:RefreshDoll({})
assert(dollSlot:Hover() == "Native tooltip", "an empty slot has no upgrade")
AZSInspect:RefreshDoll({ { slot = 0, rarity = 0, stars = 5 } })
assert(string.find(dollSlot:Hover(), "At five stars", 1, true))
SurvivorUI_RebornGearOpen("toggle preview")
assert(dollSlot:Hover() == "Native tooltip", "disabled previews do not extend native tooltips")
SurvivorUI_RebornGearOpen("toggle preview")
AZS_ARMOR = { { slot = 0, rarity = 8, stars = 0 }, { slot = 8, rarity = 4, stars = 1 } }
handlers.AZSARMOR()
local snapshot = assert(SurvivorUIDB.rebornGear.wornSnapshots.warlock)
assert(count == 0 and snapshot.at == 100 and snapshot.source == "campaign" and #snapshot.pieces == 2,
	"wear is recorded without creating the UI")
AZSInspectGear = { IsShown = function() return AZSInspect.unit == "player" end }
AZSInspect:RefreshDoll(AZS_ARMOR)
local overview = assert(buttons.Upgrades)
assert(overview.parent == AZSInspectGear and overview:IsShown())
AZSInspect:RefreshDoll(AZS_ARMOR)
assert(buttons.Upgrades == overview, "refresh reuses the equipment header button")
AZSInspect.unit = "party1"
AZSInspect:RefreshDoll({})
assert(not overview:IsShown(), "the button is hidden on another character")
AZSInspect.unit = "player"
AZSInspect:RefreshDoll(AZS_ARMOR)
SurvivorUI_RebornGearOpen("toggle preview")
assert(not overview:IsShown(), "disabling gear preview also hides the overview button")
SurvivorUI_RebornGearOpen("toggle preview")
assert(overview:IsShown())
overview.scripts.OnClick()
assert(not AZSInspect:IsShown() and not buttons["Load recorded gear"] and not buttons["Edit gear and prices"] and not buttons["Refresh worn gear"])
assert(SurvivorUI_RebornGearOpen("show"))
local input, items, output, gearPanel, gearView
for _, w in ipairs(widgets) do
	if w.kind == "EditBox" then
		if not input then input = w; gearView = w.parent else items = w end
	end
	if w.kind == "ScrollingMessageFrame" then output = w end
	if w.name == "SurvivorUIRebornGearPanel" then gearPanel = w end
end
local function MapShows(text)
	for _, w in ipairs(widgets) do
		if w.kind == "FontString" and w.parent == buttons["Set current map to 100%"].parent
			and string.find(w:GetText(), text, 1, true) then return true end
	end
	return false
end
local saveMap = buttons["Set current map to 100%"].scripts.OnClick
assert(gearPanel and gearPanel:IsShown() and not gearView:IsShown() and MapShows("179.0%"))
assert(not output:IsShown() and #output.messages == 0, "map results never use the scrolling message frame")
assert(SurvivorUI_RebornGearOpen("show") and MapShows("179.0%"), "opening from options is idempotent")
saveMap()
local mapRef = SurvivorUIDB.rebornGear.mapReference
assert(mapRef.zone == "naxx" and mapRef.tier == 1 and MapShows("100.0%") and MapShows("Naxxramas · Heroic I"))
assert(mapRef.worn.warlock[1].tier == "elementium" and mapRef.worn.warlock[1].stars == 0)
assert(not SurvivorUI_RebornGearOpen() and not gearPanel:IsShown(), "slash command still toggles the panel")
gearPanel.scripts.OnEvent()
assert(SurvivorUI_RebornGearOpen("show"))
saveMap()
assert(SurvivorUIDB.rebornGear.mapReference == mapRef and MapShows("Your reference was kept"), "prior world snapshot is rejected")
AZS_ZONE = { zone = "elwynn", dt = "2", zname = "Elwynn Forest" }
phase = "playing"
handlers.AZSZONE()
local expected = 100 * G.Pressure(SurvivorUI_RebornMapReference, "elwynn", 2) / G.Pressure(SurvivorUI_RebornMapReference, "naxx", 1)
assert(MapShows(string.format("%.1f%%", expected)) and MapShows("Current map: Elwynn Forest · Heroic II"))
saveMap()
mapRef = SurvivorUIDB.rebornGear.mapReference
assert(mapRef.zone == "elwynn" and mapRef.tier == 2 and MapShows("100.0%"), "map can be saved during a run")
AZS_ZONE = { zone = "naxx", dt = 0, hub = 1, class = "warlock" }
phase = nil -- The native API returns nil in the Hub.
AZS_ARMOR = { { slot = 8, rarity = 2, stars = 3 } }
handlers.AZSZONE()
assert(MapShows("Last Campaign map: Naxxramas · Heroic I"))
handlers.AZSARMOR()
assert(SurvivorUIDB.rebornGear.wornSnapshots.warlock == snapshot, "Hub events do not replace the Campaign entry snapshot")
assert(Pick("World", 2) and not Pick("Zone", "elwynn") and not Pick("Zone", "unmodeled"))
assert(Pick("Zone", "shadowmoon") and MapShows("Preview map: Shadowmoon Valley · Normal"))
assert(Pick("Tier", 5) and MapShows("Preview map: Shadowmoon Valley · Heroic V"))
local hubExpected = 100 * G.Pressure(SurvivorUI_RebornMapReference, "shadowmoon", 5) / G.Pressure(SurvivorUI_RebornMapReference, "elwynn", 2)
assert(MapShows(string.format("%.1f%%", hubExpected)))
saveMap()
assert(SurvivorUIDB.rebornGear.mapReference == mapRef and MapShows("Your reference was kept") and MapShows("Preview map: Shadowmoon Valley · Heroic V"))
buttons["Clear map preview"].scripts.OnClick()
assert(MapShows("Last Campaign map: Naxxramas · Heroic I"))
AZS_ZONE = { zone = "naxx" }
phase = "ready"
saveMap()
assert(SurvivorUIDB.rebornGear.mapReference == mapRef and MapShows("Your reference was kept"), "missing difficulty cannot default to Normal")
AZS_ZONE = { zone = "naxx", dt = 6 }
saveMap()
assert(SurvivorUIDB.rebornGear.mapReference == mapRef and MapShows("Your reference was kept"), "unmodeled tiers cannot replace the reference")
AZS_ZONE = { zone = "naxx", dt = 0, class = "paladin", run = "azs:r00000001" }
AZS_PG = { active = true }
saveMap()
assert(SurvivorUIDB.rebornGear.mapReference == mapRef and MapShows("Your reference was kept"))
AZS_PG = nil
saveMap()
mapRef = SurvivorUIDB.rebornGear.mapReference
assert(mapRef.zone == "naxx" and mapRef.tier == 0 and MapShows("Current map: Naxxramas · Normal") and not MapShows("Preview map:"), "save takes the actual map even with a preview selected")
phase = "playing"
SurvivorUI_RebornGearOpen("advanced")
assert(gearView:IsShown())
buttons["Gear preview"].scripts.OnClick()
assert(logs[#logs] == "Open gear analysis from the hub or outside active combat.")
local function WornShows(text)
	for _, w in ipairs(widgets) do
		if w.kind == "FontString" and w.parent and w.parent.name == "SurvivorUIRebornWornContent" and w:IsShown()
			and string.find(w:GetText(), text, 1, true) then return true end
	end
	return false
end
assert(SurvivorUI_RebornGearOpen("worn") and WornShows("Waiting for the game's Campaign gear snapshot"))
AZS_ARMOR = { { slot = 0, rarity = 2, stars = 0 } }
handlers.AZSARMOR()
local fromRun = assert(SurvivorUIDB.rebornGear.wornSnapshots.paladin)
assert(mapRef.worn.paladin[1].stars == 0 and fromRun.source == "campaign")
assert(WornShows("Upgrade plan for Naxxramas · Normal") and WornShows("100.00% → ") and WornShows("1020 gold"))
assert(WornShows("Head · Rare · ★0 → ★1") and WornShows("Lowest estimated cost"))
AZS_ZONE = { zone = "naxx", dt = 0, class = "paladin", run = "azs:r00000001" }
AZS_ARMOR = { { slot = 0, rarity = 2, stars = 5 } }
handlers.AZSARMOR()
assert(SurvivorUIDB.rebornGear.wornSnapshots.paladin == fromRun, "repeated sync in the same run is ignored")
AZS_ZONE = { zone = "elwynn", dt = 0, class = "paladin", run = "azs:r00000002" }
handlers.AZSZONE()
assert(WornShows("Waiting for the game's Campaign gear snapshot"), "a new run does not use stale gear")
handlers.AZSARMOR()
assert(SurvivorUIDB.rebornGear.wornSnapshots.paladin.pieces[1].stars == 5 and mapRef.worn.paladin[1].stars == 0)
assert(WornShows("Already below 100%"))
assert(#commands == 0, "the analyzer never requests refresh commands")
phase = nil
AZS_ZONE = { hub = 1, class = "warlock" }
assert(SurvivorUI_RebornGearOpen("show"))
assert(not gearView:IsShown())
zone = 8 * 3600
assert(SurvivorUI_RebornGearOpen("worn"))
assert(dateAt == 100 + 8 * 3600 and WornShows("Recorded at 2026-11-26 12:00") and not WornShows("12:00 UTC"))
assert(WornShows("Last recorded gear: Warlock · 2 pieces") and WornShows("3101 gold"))
assert(WornShows("Recorded in a Campaign map"), "the Hub still displays the provenance of a fallback snapshot")
assert(WornShows("3754 gold") and WornShows("Enter the reference map at its saved difficulty"))
assert(SurvivorUI_RebornGearOpen("advanced") and gearView:IsShown())
items:SetText("main_hand common 4 worn 100")
buttons["Save gear setup"].scripts.OnClick()
assert(SurvivorUIDB.rebornGear.references.warlock.gear[1].stars == 4)
assert(SurvivorUIDB.rebornGear.mapReference == mapRef, "gear scenarios keep their own references")
input:SetText("warlock naxx 1 0")
assert(#output.messages == 0, "edited input invalidates displayed output")
buttons["Stars Only"].scripts.OnClick()
assert(string.find(table.concat(output.messages, "\n"), "100 extra gold", 1, true))
AZS_GEN.pieces.scale.factor = 0.71
buttons["Compare gear"].scripts.OnClick()
assert(string.find(table.concat(output.messages, "\n"), "Save a reference", 1, true), "changed catalog invalidates reference")
AZS_GEN.pieces.scale.factor = 0.7
input:SetText("warlock naxx 1 0 main_hand")
items:SetText("main_hand common 0 worn\nmain_hand rare 0 farm")
buttons["Gear preview"].scripts.OnClick()
local previews = table.concat(output.messages, "\n")
assert(string.find(previews, "Rare ★3 · farm · 6800 extra gold", 1, true))
assert(string.find(previews, "Common ★5 · worn · 9520 extra gold", 1, true))
SurvivorUI_RebornGearOpen("toggle planner")
buttons["Farm & Upgrade"].scripts.OnClick()
assert(logs[#logs] == "This gear analysis feature is disabled.")
GetLocale = function() return "zhCN" end
dofile("SurvivorUI/Locale_zh.lua")
assert(SurvivorUI_WORDS.zh["Set current map to 100%"] == "将当前地图设为 100%")
assert(SurvivorUI_WORDS.zh.Upgrades == "升星总览")
assert(string.format(SurvivorUI_WORDS.zh["100%% reference: %s"], "纳克萨玛斯") == "100% 基准：纳克萨玛斯")
function SurvivorUI_T(text) return SurvivorUI_WORDS.zh[text] or text end
assert(SurvivorUI_RebornGearOpen("worn") and WornShows("伤害 +") and not WornShows("Damage +"))
AZSInspect:RefreshDoll({ { slot = 0, rarity = 0, stars = 0 } })
local chineseTooltip = dollSlot:Hover()
assert(string.find(chineseTooltip, "下一星", 1, true) and string.find(chineseTooltip, "408 金币", 1, true))
assert(not string.find(chineseTooltip, "价格表", 1, true))
assert(string.find(chineseTooltip, "伤害 +5.38%", 1, true))
print("PASS: gear arithmetic, sets, exhaustive solver comparison, and panel lifecycle")
