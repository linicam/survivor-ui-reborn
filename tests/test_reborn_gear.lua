-- Synthetic catalog and exhaustive checks for the read-only gear planner.
table.getn = table.getn or function(t) return #t end
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornMapReference.lua")
dofile("SurvivorUI/RebornGearModel.lua")
local G = SurvivorUI_RebornGearModel
local keys = { "head", "shoulders", "chest", "waist", "legs", "feet", "wrists", "hands", "main_hand", "off_hand", "ranged" }
AZS_GEN = {
	pieces = {
		scale = { top = 5, steps = 4, factor = 0.7, slot = { 1, 1.7, 2.5, 3.5, 4.6, 4 },
			profile = { 0, 1, 1.6, 2.4, 3.4, 2.9 }, starStep = { 0.64, 0.4, 0.28, 0.17, 0.12, 0.15 },
			starLast = { 3.73, 1.85, 0.85, 0.42, 0.12, 0.22 } },
		slots = {}, classProfiles = { warlock = { 0, 0, 0, 0, 0, 0, 0, 0 } },
		profiles = { [0] = { { "crit", 0.01 } } },
	},
	gearTiers = { { key = "exotic", rank = 7, slot_scale = 5.6, profile_scale = 4.2, star_step = 0.1, star_last = 0.1 } },
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
local count = 0
function CreateFrame(kind, name)
	count = count + 1
	local w = { name = name, kind = kind, scripts = {}, shown = true, messages = {} }
	function w:CreateFontString() return CreateFrame("FontString") end
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
function SurvivorUI_T(string) return string end
local reborn, phase = false, "playing"
function SurvivorUI_RebornActive() return reborn end
function AZS_GetPhase() return phase end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(logs, text) end }
dofile("SurvivorUI/RebornGear.lua")
assert(count == 0)
SurvivorUI_RebornGearOpen()
assert(count == 0)
reborn = true
SurvivorUI_RebornGearOpen()
assert(count == 0 and #logs == 1)
phase = "ready"
SurvivorUI_RebornGearOpen()
local input, items, output
for _, w in ipairs(widgets) do
	if w.kind == "EditBox" then if not input then input = w else items = w end end
	if w.kind == "ScrollingMessageFrame" then output = w end
end
buttons.Difficulty.scripts.OnClick()
assert(string.find(table.concat(output.messages, "\n"), "100.0%", 1, true))
items:SetText("main_hand common 4 worn 100")
buttons["Save 100%"].scripts.OnClick()
assert(SurvivorUIDB.rebornGear.references.warlock.gear[1].stars == 4)
input:SetText("warlock naxx 1 0")
assert(#output.messages == 0, "edited input invalidates displayed output")
buttons["Stars Only"].scripts.OnClick()
assert(string.find(table.concat(output.messages, "\n"), "100 extra gold", 1, true))
AZS_GEN.pieces.scale.factor = 0.71
buttons.Difficulty.scripts.OnClick()
assert(string.find(table.concat(output.messages, "\n"), "Save a reference", 1, true), "changed catalog invalidates reference")
AZS_GEN.pieces.scale.factor = 0.7
input:SetText("warlock naxx 1 0 main_hand")
items:SetText("main_hand common 0 worn\nmain_hand rare 0 farm")
buttons["Gear preview"].scripts.OnClick()
local previews = table.concat(output.messages, "\n")
assert(string.find(previews, "rare ★3 · price unknown", 1, true))
assert(string.find(previews, "common ★5 · price unknown", 1, true))
SurvivorUI_RebornGearOpen("toggle planner")
buttons["Farm & Upgrade"].scripts.OnClick()
assert(logs[#logs] == "This gear analysis feature is disabled.")
print("PASS: gear arithmetic, sets, exhaustive solver comparison, and panel lifecycle")
