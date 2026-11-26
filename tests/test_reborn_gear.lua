-- Synthetic catalog and exhaustive checks for the read-only gear planner.
table.getn = table.getn or function(t) return #t end
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornMapReference.lua")
dofile("SurvivorUI/RebornGearModel.lua")
dofile("SurvivorUI/RebornGearPlanner.lua")
local G, P = SurvivorUI_RebornGearModel, SurvivorUI_RebornGearPlanner
local M = SurvivorUI_RebornAnalysisModel
local maps = SurvivorUI_RebornMapReference
local keys = { "head", "shoulders", "chest", "waist", "legs", "feet", "wrists", "hands", "main_hand", "off_hand", "ranged" }
AZS_GEN = {
	classes = { { key = "warlock", name = "Warlock", health = 165 }, { key = "paladin", name = "Paladin", health = 245 },
		{ key = "hunter", health = 200 }, { key = "rogue", health = 190 } },
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
		{ key = "exotic", rank = 7, pair = 5, slot_scale = 5.6, profile_scale = 4.2, star_step = 0.1, star_last = 0.1, star_factor = 5.8 },
		{ key = "mythic", rank = 8, pair = 5, slot_scale = 6.4, profile_scale = 4.8, star_step = 0.1, star_last = 0.1, star_factor = 7.2 },
		{ key = "elementium", rank = 9, pair = 5, slot_scale = 7.4, profile_scale = 5.4, star_step = 0.1, star_last = 0.1, star_factor = 7.6 },
	},
	setRules = { pieces = { 4, 8 }, stars = { 1, 3 }, empowerStars = 5 },
	setBonuses = {
		{ class = "", rarity = 0, pieces = 4, text = "Pickup +{v}", v = { 12, 18 } },
		{ class = "warlock", rarity = 0, pieces = 8, text = "Hits {v}", v = { 2, 3 } },
	},
}
AZS_GEN.pieces.classProfiles.hunter = AZS_GEN.pieces.classProfiles.warlock
AZS_GEN.pieces.classProfiles.rogue = AZS_GEN.pieces.classProfiles.warlock
AZS_GEN.gearTiers[1].weapon_icons = { rogue = { "main" } }
AZS_GEN.gearTiers[2].weapon_icons = { rogue = { "main", "off" } }
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

local function Item(slot, tier, stars) return { slot = slot, tier = tier, stars = stars } end
local function Eval(pieces) return assert(P.Evaluate(cat, "warlock", pieces)) end
local source = { class = "warlock", zone = "naxx", level = 0, heroic = 0, build = "v0.7.4",
	modifiers = { aff = "2", affixes = "" }, demand = M.GearDemand(maps.naxx, 0), at = 100,
	pieces = { Item("head", "common", 0), Item("main_hand", "legendary", 0), Item("chest", "common", 1) } }
table.insert(AZS_GEN.pieces.slots[0].stats, { "hp", 30 })
table.insert(AZS_GEN.pieces.slots[2].stats, { "armor", 0.17 })
local actual = Eval(source.pieces)
local ref = assert(P.Reference(source, actual))
near(G.Piece(cat, "warlock", "main_hand", "common", 0).damage, 0.084)
near(G.Piece(cat, "warlock", "main_hand", "common", 5).damage, 0.61236)
near(G.Piece(cat, "warlock", "main_hand", "exotic", 0).damage, 0.4704)
assert(not G.Piece(cat, "warlock", "main_hand", "common", 6))
assert(not G.Worn(cat, "warlock", { { slot = 0, rarity = 0, stars = 0 }, { slot = 0, rarity = 1, stars = 1 } }))
local worn = assert(G.Worn(cat, "warlock", { { slot = "8", rarity = "7", stars = "2" },
	{ slot = 1, rarity = "" }, { slot = 0, rarity = 4, stars = 0, icon = "inv_test", name = "Test" } }))
assert(#worn == 2 and worn[1].icon == "inv_test" and worn[2].slot == "main_hand" and worn[2].tier == "mythic")
assert(P.Difficulty(source.demand, actual, ref).combined == 100 and ref.pieces[1] ~= source.pieces[1])
local reconstructed, issue = P.CheckReference(ref, source, cat, maps)
assert(ref.modifiers ~= source.modifiers and reconstructed ~= ref and issue == nil and reconstructed.scope == "standard")
assert(P.Difficulty(source.demand, actual, reconstructed).combined == 100)
assert(not P.CheckReference(ref, { class = "paladin", build = source.build }, cat, maps))
assert(P.CheckReference(ref, { class = "warlock", build = "changed" }, cat, maps))
assert(not P.CheckReference(P.Copy({ version = 1 }), source, cat, maps))
local legacy = P.Copy(ref)
legacy.schema, legacy.version, legacy.data = nil, 2, "older"
assert(P.CheckReference(legacy, source, cat, maps))
local updated = P.Copy(ref)
updated.version, updated.data, updated.output = 900, "compatible new data", 1
local recomputed, warning = P.CheckReference(updated, source, cat, maps)
assert(recomputed.output == actual.output and warning == "updated" and updated.output == 1)
local changedMaps = P.Copy(maps)
changedMaps.naxx[1] = changedMaps.naxx[1] * 1.1
recomputed, warning = P.CheckReference(ref, source, cat, changedMaps)
assert(recomputed and warning == "updated" and recomputed.demand.output ~= ref.demand.output)
for _, field in ipairs({ "schema", "zone", "level", "pieces", "heroic", "modifiers" }) do
	local bad = P.Copy(ref)
	bad[field] = "invalid"
	assert(not P.CheckReference(bad, source, cat, maps), field)
end
local bad = P.Copy(ref)
bad.pieces = { [2] = Item("head", "common", 1) }
assert(not P.CheckReference(bad, source, cat, maps))
bad.pieces = { Item("off_hand", "common", 1) }
assert(not P.CheckReference(bad, source, cat, maps))
local modifiedRef = P.Copy(ref)
modifiedRef.modifiers.affixes = "explosive"
assert(P.CheckReference(modifiedRef, source, cat, maps).scope == "standard-only")
modifiedRef.modifiers.mode = "swarm"
assert(not P.CheckReference(modifiedRef, source, cat, maps))
assert(P.Scope(0, { aff = 1, affixes = " , ", challenge = "0" }) == "standard")
assert(P.Scope(3, {}) == "standard-only" and P.Scope(0, { affixes = "sanguine" }) == "standard-only")
assert(P.Affixes({ " Sanguine ", "explosive", "sanguine" }) == "explosive,sanguine")
local partial = P.Difficulty(M.GearDemand({ 2 }, 0), actual, ref)
assert(partial.output and not partial.survival and not partial.combined)
local capped = Eval({ Item("chest", "common", 5) })
assert(capped.stats.armor > 0.6)
near(capped.survival, 165 / 0.4)

assert(P.DropTiers(cat, maps, 1).legendary and not P.DropTiers(cat, maps, 1).exotic)
assert(P.DropTiers(cat, maps, 2).exotic and not P.DropTiers(cat, maps, 2).common)
assert(P.DropTiers(cat, maps, 3).mythic and P.DropTiers(cat, maps, 4).elementium)
assert(G.ValidPiece(cat, "hunter", "ranged", "exotic", 1) and not G.ValidPiece(cat, "hunter", "main_hand", "exotic", 1))
assert(G.ValidPiece(cat, "rogue", "off_hand", "exotic", 1) and not G.DropSlot(cat, "rogue", "off_hand", "exotic"))
assert(G.DropSlot(cat, "rogue", "off_hand", "mythic") and G.DropSlot(cat, "rogue", "off_hand", "elementium"))
assert(not G.ValidSlot(cat, "paladin", "off_hand") and not G.ValidSlot(cat, "warlock", "ranged"))
assert(not G.Worn(cat, "paladin", { { slot = 9, rarity = 6, stars = 0 } }))
assert(not G.Worn(cat, "warlock", { [2] = { slot = 0, rarity = 0, stars = 0 } }))
assert(not G.ValidPiece(cat, "hunter", "ranged", "invented", 0) and not G.ValidPiece(cat, "hunter", "ranged", "exotic", 1.5))
local upgrade = P.Quote(cat, source.pieces[2], Item("main_hand", "exotic", 2), P.DropTiers(cat, maps, 2), "warlock")
assert(upgrade.kind == "farm" and upgrade.progression and upgrade.gold == 2366 + 4733 and upgrade.estimated)
assert(P.Quote(cat, source.pieces[2], Item("main_hand", "exotic", 0), P.DropTiers(cat, maps, 1)).kind == "theoretical")
assert(P.Quote(cat, Item("head", "common", 5), Item("head", "common", 2)).gold == 0)

local armor = {}
for i = 1, 8 do armor[i] = Item(keys[i], "common", 5) end
armor[9] = Item("main_hand", "common", 5)
local withSet = Eval(armor)
assert(withSet.sets.common[2].text == "Hits 3" and withSet.sets.common[2].strong)
armor[8].stars = 2
assert(#Eval(armor).sets.common == 1, "a weapon does not count towards the set")
armor[8].stars = 5
AZS_GEN.setBonuses[1].text, AZS_GEN.setBonuses[1].v2 = "+{v}% gold, +{v2}% pickup range", { 30, 45 }
AZS_GEN.setBonuses[1].follows = true
local empowered = Eval(armor)
near(empowered.stats.gold, 0.18)
near(empowered.stats.pickup, 0.45)
assert(#empowered.opaque.common == 1)

local function Finish(search)
	while search.worker do P.Step(search, 151) end
	assert(not search.error, search.error)
	return search
end

local easy = Finish(P.Search(cat, source, actual, ref, nil, 10000))
assert(easy.complete and easy.visited == 0 and easy.after == 100 and easy.gold == 0)

-- Independent exhaustive oracle: every available star combination is evaluated
-- with the public full-configuration evaluator, then ordered by the contract.
local function Oracle(context)
	local best, equipment = nil, {}
	local function Visit(i, gold)
		local item = context.pieces[i]
		if item then
			for star = item.stars, 5 do
				equipment[i] = Item(item.slot, item.tier, star)
				local additional = 0
				for step = item.stars + 1, star do additional = additional + G.StarQuote(cat, item.slot, item.tier, step) end
				Visit(i + 1, gold + additional)
			end
			return
		end
		local distance = P.Difficulty(context.demand, Eval(equipment), ref).combined
		local reached = distance <= 100
		if not best or (reached and not best.reached)
			or (reached and best.reached and gold < best.gold)
			or (not reached and not best.reached and (distance < best.after - P.tolerance
				or (math.abs(distance - best.after) <= P.tolerance and gold < best.gold))) then
			best = { after = distance, gold = gold, reached = reached }
		end
	end
	Visit(1, 0)
	return best
end
math.randomseed(8245)
for i = 1, 80 do
	local context = P.Copy(source)
	context.demand.output = ref.demand.output * (1 + math.random(1, 210) / 100)
	context.demand.survival = ref.demand.survival * (1 + math.random(1, 210) / 100)
	local expected = Oracle(context)
	local got = Finish(P.Search(cat, context, actual, ref, nil, 5000))
	assert(got.complete and got.gold == expected.gold and (got.after <= 100) == expected.reached)
	near(got.after, P.Difficulty(context.demand, Eval(got.pieces), ref).combined)
	if not expected.reached then near(got.after, expected.after) end
end

local hard = P.Copy(source)
hard.demand = M.GearDemand(maps.naxx, 5)
local limited = Finish(P.Search(cat, hard, actual, ref, nil, 1))
assert(not limited.complete and limited.visited == 1 and limited.after > 100)
local deadline = P.Search(cat, hard, actual, ref, nil, 5000)
P.Step(deadline, 10, function() return true end)
assert(deadline.visited == 0)

local protected = P.Copy(hard)
protected.pieces = armor
local preserves = Finish(P.Search(cat, protected, empowered, ref, { exotic = true }, 12000))
assert(preserves.complete and Eval(preserves.pieces).sets.common[2].strong)

local savedTop = cat.pieces.scale.top
cat.pieces.scale.top = 0
local farming = P.Copy(source)
farming.pieces = { Item("head", "common", 0), Item("main_hand", "common", 0) }
local farmingActual = Eval(farming.pieces)
local farmingReference = assert(P.Reference(farming, farmingActual))
farming.demand = { output = farming.demand.output * 1.2, survival = farming.demand.survival * 1.2 }
local stars = Finish(P.Search(cat, farming, farmingActual, farmingReference, nil, 2000))
local drops = Finish(P.Search(cat, farming, farmingActual, farmingReference, { exotic = true }, 2000))
local _, acquisition = P.Changes(cat, farming.pieces, drops.pieces, { exotic = true }, "warlock")
assert(stars.complete and stars.after > 100 and drops.complete and drops.after <= 100 and drops.gold == 0 and acquisition.acquisition)

-- Oracle for a mixed-tier plan. Use one reachable and one unreachable target,
-- with a four-piece combat effect protected and different HP/armor choices.
cat.pieces.scale.top = 1
table.insert(AZS_GEN.setBonuses, { class = "", rarity = 4, pieces = 4, text = "Conditional damage" })
local mixed = P.Copy(source)
mixed.pieces = {}
for i = 1, 9 do mixed.pieces[i] = Item(keys[i], i <= 4 and "legendary" or "common", 1) end
local mixedActual = Eval(mixed.pieces)
local mixedRef = assert(P.Reference(mixed, mixedActual))
local candidate = {}
for _, factor in ipairs({ 1.08, 1.8 }) do
	mixed.demand = { output = mixedRef.demand.output * factor, survival = mixedRef.demand.survival * factor }
	local expected
	local function Enumerate(i, gold)
		local item = mixed.pieces[i]
		if item then
			candidate[i] = item
			Enumerate(i + 1, gold)
			-- Changing one of the first four pieces would lose the protected set.
			if i > 4 then
				candidate[i] = Item(item.slot, "exotic", 0)
				Enumerate(i + 1, gold)
				candidate[i] = Item(item.slot, "exotic", 1)
				Enumerate(i + 1, gold + 2366)
			end
			return
		end
		local difficulty = P.Difficulty(mixed.demand, Eval(candidate), mixedRef).combined
		local reached = difficulty <= 100
		if not expected or (reached and not expected.reached) or (reached and expected.reached and gold < expected.gold)
			or (not reached and not expected.reached and (difficulty < expected.after - P.tolerance
				or (math.abs(difficulty - expected.after) <= P.tolerance and gold < expected.gold))) then
			expected = { after = difficulty, gold = gold, reached = reached }
		end
	end
	Enumerate(1, 0)
	local first = Finish(P.Search(cat, mixed, mixedActual, mixedRef, { exotic = true }, 12000))
	local second = Finish(P.Search(cat, mixed, mixedActual, mixedRef, { exotic = true }, 12000))
	assert(first.complete and first.gold == expected.gold and (first.after <= 100) == expected.reached)
	assert(first.after == second.after and first.gold == second.gold and #first.pieces == #second.pieces)
	for i, piece in ipairs(first.pieces) do assert(P.SamePiece(piece, second.pieces[i])) end
	if not expected.reached then near(first.after, expected.after) end
	assert(Eval(first.pieces).sets.legendary[1].pieces == 4)
end
local knownText = AZS_GEN.setBonuses[1].text
AZS_GEN.setBonuses[1].text = "Unquantified combat"
local twoSets = Eval(mixed.pieces)
local twoSetsRef = assert(P.Reference(mixed, twoSets))
local bothProtected = Finish(P.Search(cat, mixed, twoSets, twoSetsRef, { exotic = true }, 12000))
assert(bothProtected.complete)
local kept = Eval(bothProtected.pieces).sets
assert(kept.legendary[1].pieces == 4 and kept.common[1].pieces == 4, "both competing protected tiers survive")
AZS_GEN.setBonuses[1].text = knownText
table.remove(AZS_GEN.setBonuses)
cat.pieces.scale.top = savedTop

-- Event and widget mocks follow the native zone-before-armor sync contract.
local widgets, handlers, commands, entries, menus = {}, {}, {}, {}, {}
function CreateFrame(kind, name, parent)
	local w = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, events = {} }
	function w:CreateFontString() return CreateFrame("FontString", nil, self) end
	function w:CreateTexture() return CreateFrame("Texture", nil, self) end
	function w:SetScript(key, fn) self.scripts[key] = fn end
	function w:SetText(text) self.text = text end
	function w:Show() self.shown = true end
	function w:Hide()
		local before = self.shown
		self.shown = false
		if before and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function w:IsShown() return self.shown end
	function w:Enable() self.disabled = false end
	function w:Disable() self.disabled = true end
	function w:RegisterEvent(key) self.events[key] = true end
	function w:UnregisterEvent(key) self.events[key] = nil end
	function w:GetStringHeight() return 14 end
	table.insert(widgets, w)
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetWidth", "SetHeight", "SetFrameStrata",
		"EnableMouse", "SetBackdrop", "SetBackdropColor", "SetScrollChild", "SetVerticalScroll", "SetJustifyH",
		"SetTextColor", "SetTexture" }) do w[method] = function() end end
	return w
end
function UIDropDownMenu_Initialize(menu, fn) menus[menu] = fn end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue(menu, value) menu.value = value end
function UIDropDownMenu_SetText(menu, text) menu.text = text end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) table.insert(entries, info) end
function SurvivorUI_T(text) return text end
function SurvivorUI_RebornActive() return true end
function SurvivorUI_RebornStableRunId(value) return value end
function AZS_SendCommand(command) table.insert(commands, command) end
function time() return 1234 end
AZS = { ServerBuild = "v0.7.4", On = function(event, fn) assert(not handlers[event]); handlers[event] = fn end }
SurvivorUIDB = { rebornGear = { mapReference = { zone = "naxx", tier = 3 }, wornSnapshots = { warlock = { pieces = armor } } } }
local dollSlot = { slot = 0, hooks = 0 }
local secondSlot = { slot = 1, hooks = 0 }
function dollSlot:HookScript(event, fn)
	if event == "OnEnter" then self.hooks, self.afterEnter = self.hooks + 1, fn
	else assert(event == "OnLeave"); self.afterLeave = fn end
end
GameTooltip = {
	SetOwner = function(self, owner) self.owner = owner end,
	SetText = function(self, text) self.lines = { text } end,
	IsOwned = function(self, owner) return self.owner == owner end,
	AddLine = function(self, text) table.insert(self.lines, text) end,
	Show = function(self) self.shown = true end,
	Hide = function(self) self.shown = false; self.owner = nil end,
}
function dollSlot:Hover()
	GameTooltip.owner, GameTooltip.lines = self, { "Native tooltip" }
	GameTooltip:Show()
	if self.afterEnter then self.afterEnter(self) end
	return table.concat(GameTooltip.lines, "\n")
end
secondSlot.HookScript, secondSlot.Hover = dollSlot.HookScript, dollSlot.Hover
AZSInspectGear = CreateFrame("Frame")
AZSInspect = { unit = "player", shown = true }
function AZSInspect:IsShown() return self.shown end
function AZSInspect:HookScript(key, fn) assert(key == "OnHide"); self.onHide = fn end
function AZSInspect:Hide() self.shown = false; if self.onHide then self.onHide() end end
function AZSInspect:RefreshDoll(armor)
	AZSInspectSlot0 = { GetParent = function() return dollSlot end }
	AZSInspectSlot1 = { GetParent = function() return secondSlot end }
	dollSlot.piece, secondSlot.piece = nil, nil
	for _, item in ipairs(armor) do
		if tonumber(item.slot) == 0 then dollSlot.piece = item end
		if tonumber(item.slot) == 1 then secondSlot.piece = item end
	end
end
function hooksecurefunc(target, method, callback)
	local original = target[method]
	target[method] = function(self, ...)
		original(self, ...)
		callback(self, ...)
	end
end

dofile("SurvivorUI/RebornGear.lua")
local function Find(kind, text, children)
	local function Visible(widget)
		while widget do
			if not widget.shown then return false end
			widget = widget.parent
		end
		return true
	end
	for _, w in ipairs(widgets) do
		if w.kind == kind and Visible(w) and (not children or w.parent == children)
			and type(w.text) == "string" and string.find(w.text, text, 1, true) then return w end
	end
end
local function Click(text)
	local button = assert(Find("Button", text), text)
	assert(not button.disabled, text)
	button.scripts.OnClick()
end
local function Zone(key, level, class, run, affixes)
	AZS_ZONE = { hub = 1, zone = key, dt = level, heroic = level, class = class, run = run, affixes = affixes }
	handlers.AZSZONE()
end
local function Armor(rows)
	AZS_ARMOR = rows
	handlers.AZSARMOR()
	AZSInspect:RefreshDoll(rows)
end
local function SlotMenu(slot, value, field)
	for menu, open in pairs(menus) do
		if menu.shown and menu.parent.shown and menu.parent.slot == slot and string.find(menu.name, field or "tier", 1, true) then
			entries = {}
			open()
			for _, item in ipairs(entries) do if item.value == value then return item.func end end
		end
	end
end
local function HoverIcon(slot, planned)
	for _, row in ipairs(widgets) do
		if row.slot == slot and row.shown and row.iconButton.shown and (row.plan ~= nil) == planned then
			row.iconButton.scripts.OnEnter()
			return table.concat(GameTooltip.lines, "\n")
		end
	end
end
local function VisiblePanel()
	for _, w in ipairs(widgets) do if w.name == "SurvivorUIRebornGearPanel" then return w end end
end
local function WorldEvent()
	for _, w in ipairs(widgets) do
		if w.events.PLAYER_ENTERING_WORLD then w.scripts.OnEvent(w, "PLAYER_ENTERING_WORLD") end
	end
end
local function DrainSearch()
	local panel = VisiblePanel()
	for i = 1, 2000 do
		if not panel.scripts.OnUpdate then return end
		panel.scripts.OnUpdate()
	end
	error("Search failed to stop")
end

assert(SurvivorUI_RebornGearOpen("show"))
assert(Find("FontString", "Waiting for the game's world snapshot"))
Zone("elwynn", 0, "warlock", "a")
assert(Find("FontString", "Warlock · Elwynn Forest · Normal"))
assert(Find("FontString", "Current equipment unavailable"))
assert(Find("Button", "Set Current Configuration").disabled)
local head = { slot = "0", rarity = "0", stars = "0", icon = "INV_Test", name = "Test item" }
Armor({ head })
assert(not Find("FontString", "100% reference:"))
local tooltip = dollSlot:Hover()
assert(dollSlot.hooks == 1 and string.find(tooltip, "Native tooltip", 1, true))
assert(string.find(tooltip, "408 gold", 1, true) and string.find(tooltip, "Next tier", 1, true))
assert(dollSlot:Hover() == tooltip, "repeat hover rebuilds the same native extension once")
Armor({ head, { slot = 1, rarity = 4, stars = 2 } })
assert(string.find(secondSlot:Hover(), "6882 gold", 1, true) and not string.find(secondSlot:Hover(), "408 gold", 1, true))
dollSlot.afterLeave(dollSlot)
assert(GameTooltip:IsOwned(secondSlot), "leaving another slot does not clear the active tooltip")
AZSInspect:Hide()
assert(not GameTooltip.shown)
AZSInspect.shown = true
Armor({ head })
Click("Set Current Configuration")
local saved = assert(SurvivorUIDB.rebornGear.baselines.warlock)
assert(saved.zone == "elwynn" and saved.level == 0 and saved.at == 1234 and saved.modifiers.affixes == "")
assert(saved.pieces[1].name == "Test item" and saved.pieces[1].stars == 0 and Find("FontString", "Estimated difficulty 100.0%"))
assert(Find("FontString", "No upgrades required"))
assert(string.find(dollSlot:Hover(), "Modeled pressure 100.0% →", 1, true))
assert(Find("FontString", "Output uses gear Damage") and Find("FontString", "calibration is pending"))
Click("Equipment Simulator")
local edit = assert(SlotMenu("head", "legendary"))
edit()
assert(string.find(HoverIcon("head", false), "Simulated item · Legendary", 1, true))
local changeStar = assert(SlotMenu("head", 2, "stars"))
changeStar()
assert(not GameTooltip.shown, "simulator edits clear tooltips")
assert(string.find(HoverIcon("head", false), "★2 → ★3", 1, true))
assert(string.find(HoverIcon("shoulders", false), "Empty slot", 1, true))
assert(Find("FontString", "Compared with actual gear") and Find("FontString", "Replacement gear is hypothetical"))
assert(saved.pieces[1].stars == 0 and saved.pieces[1].tier == "common" and head.rarity == "0")
Armor({ head })
assert(Find("FontString", "Replacement gear is hypothetical"), "duplicate native gear updates preserve the simulation")
AZS_ZONE = P.Copy(AZS_ZONE)
AZS_ZONE.aff = 2
handlers.AZSZONE()
assert(Find("FontString", "Replacement gear is hypothetical"), "replaced equivalent zone and legacy affix metadata keep state")
Click("Load Plan B")
assert(not Find("FontString", "Replacement gear is hypothetical"))
Click("Difficulty & Upgrade Planner")
assert(not Find("Button", "Reset to Actual Equipment"))
edit()
assert(not Find("FontString", "Replacement gear is hypothetical"), "stale dropdown callbacks cannot edit the planner")

Zone("naxx", 1, "warlock", "b")
assert(Find("FontString", "Naxxramas · Heroic I") and Find("FontString", "Current equipment unavailable"))
assert(Find("FontString", "Additional difficulty rules are omitted for the target"))
assert(Find("Button", "Set Current Configuration").disabled)
Armor({ head })
assert(VisiblePanel().scripts.OnUpdate, "both plans are event-triggered, then sliced")
Click("Equipment Simulator")
assert(not VisiblePanel().scripts.OnUpdate, "simulator editing suspends optimizer work")
Click("Difficulty & Upgrade Planner")
DrainSearch()
assert(Find("FontString", "Plan A") and Find("FontString", "Plan B"))
local planned = assert(HoverIcon("head", true))
assert(string.find(planned, "Planned item Common ★0 →", 1, true))
assert(string.find(planned, "Isolated item pressure", 1, true) and string.find(planned, "Full plan modeled pressure", 1, true))
Click("Equipment Simulator")
assert(not GameTooltip.shown)
Click("Load Plan A")
assert(Find("FontString", "Calculable upgrade gold:") and not VisiblePanel().scripts.OnUpdate)
Click("Reset to Actual Equipment")
assert(Find("FontString", "Calculable upgrade gold: 0") and not Find("FontString", "Changes and acquisition"))
Click("Difficulty & Upgrade Planner")
assert(saved == SurvivorUIDB.rebornGear.baselines.warlock)
AZS_ZONE.affixes = { "Sanguine", "Explosive" }
handlers.AZSZONE()
assert(Find("FontString", "Current equipment unavailable"), "in-place modifier changes invalidate gear")
Armor({ head })
AZS_ZONE.affixes = { "explosive", "sanguine" }
handlers.AZSZONE()
assert(not Find("FontString", "Current equipment unavailable"), "equivalent affix lists preserve gear")
AZS_ZONE.mode = "swarm"
handlers.AZSZONE()
Armor({ head })
assert(Find("FontString", "Campaign pressure and plans are unavailable in this mode"))
assert(not VisiblePanel().scripts.OnUpdate and Find("Button", "Set Current Configuration").disabled)
AZS_ZONE.zone, AZS_ZONE.dt, AZS_ZONE.heroic = "elwynn", 0, 0
Armor({ head })
assert(Find("FontString", "Waiting for the game's world snapshot"), "armor before an announced zone is rejected")
Zone("elwynn", 0, "warlock", "changed-run", "sanguine")
Armor({ head })
assert(string.find(dollSlot:Hover(), "Next star", 1, true))
local foreign = {}
GameTooltip:SetOwner(foreign)
GameTooltip:SetText("Unrelated tooltip")
Zone("elwynn", 0, "warlock", "later-run", "sanguine")
assert(GameTooltip:IsOwned(foreign) and GameTooltip.shown)
assert(Find("FontString", "Current equipment unavailable"), "a replaced run ID invalidates the inherited gear")
Zone("naxx", 0, "paladin", "c")
Armor({})
Click("Set Current Configuration")
assert(#SurvivorUIDB.rebornGear.baselines.paladin.pieces == 0 and SurvivorUIDB.rebornGear.baselines.warlock == saved)
Zone("dalaran", 0, "paladin", "d")
assert(Find("FontString", "Selected map or difficulty unavailable"))
assert(Find("Button", "Set Current Configuration").disabled)
WorldEvent()
assert(not VisiblePanel():IsShown() and not VisiblePanel().scripts.OnUpdate)
assert(SurvivorUI_RebornGearOpen("show") and Find("FontString", "Waiting for the game's world snapshot"))
Zone("naxx", 0, "warlock", "e")
Armor({ head })
AZSInspect.unit = "party1"
AZSInspect:RefreshDoll({ head })
assert(dollSlot:Hover() == "Native tooltip")
AZSInspect.unit = "player"
AZSInspect:RefreshDoll({ head })
assert(dollSlot.hooks == 1 and Find("Button", "Upgrades", AZSInspectGear))
dollSlot:Hover()
assert(GameTooltip.shown)
SurvivorUI_RebornGearToggle()
assert(not GameTooltip.shown)
assert(not SurvivorUI_RebornGearEnabled() and not VisiblePanel():IsShown() and not VisiblePanel().scripts.OnUpdate)
assert(dollSlot:Hover() == "Native tooltip" and not SurvivorUI_RebornGearOpen() and #commands == 0)
SurvivorUI_RebornGearToggle()
assert(#commands == 1 and commands[1] == "sync")

GetLocale = function() return "zhCN" end
dofile("SurvivorUI/Locale_zh.lua")
function SurvivorUI_T(text) return SurvivorUI_WORDS.zh[text] or text end
Zone("elwynn", 0, "warlock", "f")
Armor({ head })
assert(SurvivorUI_RebornGearOpen("show") and Find("FontString", "预计难度 100.0%"))
assert(string.find(dollSlot:Hover(), "408 金币", 1, true) and string.find(dollSlot:Hover(), "下一品质", 1, true))
Click("装备模拟器")
assert(string.find(HoverIcon("head", false), "模拟装备", 1, true))
VisiblePanel():Hide()
assert(not GameTooltip.shown, "closing the analyzer clears only its own tip")
Zone("elwynn", 0, "warlock", "late", "explosive")
Armor({ head })
dollSlot:Hover()
WorldEvent()
assert(not GameTooltip.shown, "world entry clears the tracked native extension")
print("PASS: gear arithmetic, both constraints, oracle, snapshot isolation, previews, and runtime lifecycle")
