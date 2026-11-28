-- Run the shipped observer, provider, history watcher and progression viewer.
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
local Load = loadstring or load
local function Noop() end
local function Read(path)
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local now = 100
function GetTime() return now end
time, date = os.time, os.date
function getglobal(key) return _G[key] end
function UnitName() return "Test hero" end
function UnitClass() return "Warlock", "WARLOCK" end
function UnitRace() return "Human" end
function GetZoneText() return "Test zone" end
function GetSpellInfo(id) return id == 686 and "Shadow Bolt" or tostring(id), nil, "test_icon" end
UIParent, UISpecialFrames = {}, {}
SurvivorUI_FONT = "Mock font"
SurvivorUIDB = { runHistory = {}, historyKeep = 10 }
local frameList = {}
local function Frame(kind, name, parent)
	local frame = { kind = kind, shown = true, scripts = {}, width = 1, height = 1 }
	function frame:SetScript(event, fn) self.scripts[event] = fn end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:IsShown() return self.shown end
	function frame:SetPoint(...) self.point = { ... } end
	function frame:SetWidth(width) self.width = width end
	function frame:SetHeight(height) self.height = height end
	function frame:GetWidth() return self.width end
	function frame:GetHeight() return self.kind == "ScrollFrame" and 285 or self.height end
	function frame:SetText(text) self.text = text end
	function frame:GetText() return self.text end
	function frame:SetFont(_, size) self.size = size end
	function frame:GetStringWidth()
		local text = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local ascii = #text:gsub("[\128-\255]", "")
		local glyphs = #text:gsub("[\128-\191]", "")
		return self.size * (ascii * 0.58 + glyphs - ascii)
	end
	function frame:GetStringHeight()
		local height = 0
		for line in (self.text or ""):gmatch("[^\n]+") do
			local text = self.text
			self.text = line
			height = height + math.ceil(self:GetStringWidth() / self.width) * (self.size + 2)
			self.text = text
		end
		return height
	end
	function frame:CreateFontString() return Frame("FontString", nil, self) end
	function frame:CreateTexture() return Frame("Texture", nil, self) end
	function frame:GetHighlightTexture() return Frame("Texture", nil, self) end
	function frame:SetScrollChild(child) self.child = child end
	function frame:SetVerticalScroll(value) self.position = value end
	function frame:GetVerticalScroll() return self.position or 0 end
	function frame:SetValue(value)
		self.value = value
		if self.scripts.OnValueChanged then self.scripts.OnValueChanged() end
	end
	function frame:GetValue() return self.value or 0 end
	function frame:EnableMouse(value) self.mouse = value end
	setmetatable(frame, { __index = function(_, key)
		if key:match("^Set") or key:match("^Register") or key:match("^Enable") or key == "ClearAllPoints" or key == "Raise" then
			return Noop
		end
	end })
	if name then _G[name] = frame end
	if kind ~= "FontString" and kind ~= "Texture" then table.insert(frameList, frame) end
	frame.parent = parent
	return frame
end
CreateFrame = Frame
local language = "en"
dofile("SurvivorUI/Locale_zh.lua")
function SurvivorUI_T(key) return language == "zh" and SurvivorUI_WORDS.zh[key] or key end
function SurvivorUI_TF(key, ...)
	local args = { ... }
	return (SurvivorUI_T(key):gsub("{(%d)}", function(index) return tostring(args[tonumber(index)] or "") end))
end

local listeners, sends, requests = {}, 0, 0
AZS = { On = function(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end }
local function Emit(event, message)
	for _, fn in ipairs(listeners[event] or {}) do fn(message) end
end
function SendAddonMessage() sends = sends + 1 end
function hooksecurefunc(name, fn)
	if name ~= "SendAddonMessage" then return end
	local before = SendAddonMessage
	SendAddonMessage = function(...) before(...); fn(...) end
end
function AZS_RequestAbilities() requests = requests + 1 end
function AZS_GetRunTime() return AZS_RUN.t end
function AZS_GetPhase() return AZS_RUN.ph end
function AZS_GetRunSummary() return AZS_END end
dofile("SurvivorUI/RebornCompat.lua")
dofile("SurvivorUI/RebornDiagnostics.lua")
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornProgression.lua")
local progress = SurvivorUI_RebornProgression
local rawHistory = Read("SurvivorUI/RunHistory.lua")
local startUI = assert(rawHistory:find('local talent = CreateFrame("Frame")', 1, true))
assert(Load(rawHistory:sub(1, startUI - 1), "@RunHistory watcher"))()
local watcher
for _, frame in ipairs(frameList) do
	if frame.scripts.OnUpdate then watcher = frame.scripts.OnUpdate end
end
assert(watcher)
local function Tick() arg1 = 0.7; watcher() end
function SurvivorUI_GearSnapshot() return {}, "observed" end
function SurvivorUI_ArmorSnapshot() return {}, nil, "unavailable" end
function SurvivorUI_RebornFinalLootSnapshot() return {}, "unavailable" end

local function Start(id, at, level, endless)
	AZS_ZONE = { run = id, zname = "Test zone" }
	AZS_ABILITIES, AZS_SPELLS, AZS_SPELLTIPS, AZS_CARDS = {}, {}, {}, {}
	AZS_ABILITIES_UPDATED, AZS_SPELLS_UPDATED, AZS_END = nil, nil, nil
	Emit("AZSZONE")
	AZS_RUN = { ph = "playing", t = at, lvl = level, endless = endless }
	Emit("AZSRUN")
end
local function Advance(level)
	now = now + 2
	AZS_RUN.t, AZS_RUN.lvl = AZS_RUN.t + 2, level
	Emit("AZSRUN")
end
local function Offer(kind, card)
	AZS_CARDS = { kind = kind or "none", lvl = AZS_RUN.lvl, cards = card and { card } or {} }
	Emit("AZSCARDS")
end
local function Pick(command) SendAddonMessage("AZSCMD", command or "pick 1", "PARTY") end
local function Tip(key, value)
	AZS_SPELLTIPS[key] = value
	Emit("AZSSPELLTIP", "key="..key..";text="..value)
end
local function Learned(rows, active)
	if active then
		AZS_SPELLS, AZS_SPELLS_UPDATED = rows, now
		Emit("AZSSPELLS")
	else
		AZS_ABILITIES, AZS_ABILITIES_UPDATED = rows, now
		Emit("AZSABILITIES")
	end
end
local function Gear(...)
	AZS_GEAR = { ... }
	Emit("AZSGEAR")
end
local function Skill(key, spell, level, rarity, affixes, new)
	return { key = key, spell = spell, rank = level, rarity = rarity, lines = affixes, new = new or 0 }
end
local function Bond(rank, description)
	return { key = "demonic_knowledge", spell = 35691, rank = rank, passive = true,
		name = "恶魔知识", icon = "bond_icon", text = description }
end
local function NativeSpell(rank)
	return { key = "shadow_bolt", spell = 686, rank = rank, cd = 0, cdmax = 1.1 }
end
local fixture = dofile("tests/fixtures/session033_progression.lua")
Start("azs:r00000001", 0, 1)
Learned({ NativeSpell(1) }, true)
Gear()
assert(not SurvivorUI_RebornRecording() and progress.Live().complete)
local bondText
for rank, row in ipairs(fixture.bond) do
	Advance(rank + 1)
	SurvivorUIDB.rebornClassicCards = rank % 2 == 0
	Offer("spell", Skill("demonic_knowledge", 35691, rank, row[2], row[1], rank == 1 and 1))
	Pick()
	Pick()
	bondText = string.format("伤害提高%d%%。攻击间隔缩短%d%%（上限20%%），额外命中%d名敌人。", row[3], row[4], row[5])
	Tip("demonic_knowledge", bondText)
	assert(#progress.Live().choices == rank - 1)
	Offer()
	Learned({ Bond(rank, bondText) }, false)
	Emit("AZSABILITIES")
	assert(#progress.Live().choices == rank)
end
local bond = progress.Skill("demonic_knowledge")
assert(bond.rank == 10 and bond.count == 10 and bond.acquisitions == 1 and bond.complete)
assert(bond.totals.d == 255 and bond.totals.c == 20 and bond.totals.t == 4 and not next(bond.unknown))
assert(bond.rarities[0] == 3 and bond.rarities[1] == 1 and bond.rarities[2] == 4 and bond.rarities[3] == 2)
assert(progress.Live().choices[1].affixes[1].applied == 34)
local cap = progress.Live().choices[10].affixes[1]
assert(cap.amount == 17 and cap.before == 13 and cap.after == 28 and cap.applied == 20)
assert(progress.Live().choices[10].level == 11 and progress.Live().choices[10].time == 20)
assert(requests == 0)

-- A lost selection, unselected offers and actions like banish never count.
Offer("spell", Skill("shadow_bolt", 686, 2, 1, "d25:0:25"))
Pick()
Offer()
now = now + 16
Offer("spell", Skill("shadow_bolt", 686, 2, 4, "d65:0:65a40:0:40"))
Pick("banish 1")
Offer("spell", Skill("shadow_bolt", 686, 2, 4, "d65:0:65a40:0:40"))
Pick("reroll")
Offer("spell", Skill("shadow_bolt", 686, 2, 4, "d65:0:65a40:0:40"))
Pick("skip")
assert(#progress.Live().choices == 10)
Offer("spell", Skill("shadow_bolt", 686, 2, 4, "d65:0:65a40:0:40"))
Pick()
Offer("spell", Skill("shadow_bolt", 686, 3, 0, "c7:0:7"))
Learned({ NativeSpell(2) }, true)
Pick()
Learned({ NativeSpell(3) }, true)
Tip("shadow_bolt", "Deals 140 damage to the nearest enemy.")
assert(progress.Skill("shadow_bolt").count == 2 and progress.Skill("shadow_bolt").acquisitions == 0)
assert(progress.Skill("shadow_bolt").unknown.c and progress.Skill("shadow_bolt").totals.c == nil)
assert(#progress.Live().choices[11].affixes == 2)

local function Jewel(def, mode, effect, detail, rarity)
	return { slot = def.slot, icon = def.icon, name = def.name, mode = mode,
		effect = effect, detail = detail, rarity = rarity }
end
local function Row(def, values)
	local row = Jewel(def, nil, nil, nil, values[3])
	row.bonus, row.amount, row.text = def.bonus, values[1], values[2]
	return row
end
local ring, amulet = fixture.ring, fixture.amulet
local oldRing = Row(ring, fixture.ringFirst)
local other = { name = "屠龙大师之戒", slot = "ring", bonus = "dragonslayer", icon = "INV_Jewelry_Ring_41" }
local otherRow = Row(other, { 8, "暴击几率+8.4%", 1 })
Offer("jewel", Jewel(ring, "new", oldRing.text, "", 1))
Pick()
Gear(oldRing)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 0 and progress.Live().jewelry["gear:ring:accuria"].complete)
Offer("jewel", Jewel(other, "new", otherRow.text, "", 1))
Pick()
Offer()
Gear(oldRing, otherRow)
local newRing = Row(ring, { 64, "伤害+64%", 2 })
Offer("jewel", Jewel(ring, "grow", "伤害+28.3%", "伤害=35.7%=64%=+", 2))
Pick()
Gear(oldRing, otherRow)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 0)
Gear(otherRow, newRing)
Gear(newRing, otherRow)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 1 and progress.Live().jewelry["gear:ring:dragonslayer"].count == 0)
local amuletRow = Row(amulet, fixture.amuletFirst)
Offer("jewel", Jewel(amulet, "amulet", "幸运+30%, 金币+25%", "幸运=48.1%=78.1%=+", 0))
Pick()
Gear(amuletRow, newRing, otherRow)
Offer("jewel", Jewel(amulet, "empower", "幸运+48%, 金币+40%", "等级=1=2=+^金币=25%=40%=+^幸运=97.1%=115.1%=+", 0))
Pick()
Gear(newRing, otherRow, Row(amulet, fixture.amuletEmpower))
local amuletChoice = progress.Live().choices[#progress.Live().choices]
assert(amuletChoice.appliedEffect == "幸运+48% · 金币+40%" and #amuletChoice.affixes == 3)
assert(progress.Live().jewelry["gear:amulet:south_seas_kelp"].count == 1)

-- Finish Campaign, continue the same run, and settle both observations via
-- the real Run History watcher after the World has changed.
AZS_END = { result = "victory", t = AZS_RUN.t }
Emit("AZSEND")
local ending = SurvivorUI_RebornEndObservation()
AZS_RUN.endless = 1
Emit("AZSRUN")
Advance(15)
local better = Row(ring, fixture.ringLater)
Offer("jewel", Jewel(ring, "grow", "伤害+232.2%", "伤害=64%=296.2%=+", 4))
Pick()
Gear(better, otherRow)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 2)
assert(ending.progression.jewelry["gear:ring:accuria"].count == 1)
AZS_END = { result = "defeat", t = AZS_RUN.t, endl = 1 }
Emit("AZSEND")
AZS_ZONE, AZS_RUN = { hub = 1 }, {}
Emit("AZSZONE")
Tick()
local saved = SurvivorUIDB.runHistory[1]
assert(saved and saved.progression.jewelry["gear:ring:accuria"].count == 1)
assert(saved.endless.progression.jewelry["gear:ring:accuria"].count == 2)
assert(saved.progression.skills.demonic_knowledge.totals.c == 20 and not progress.Live())

-- Late attachment, replacement and a same-identity duplicate.
Start("azs:r00000002", 57, 7)
Learned({ NativeSpell(4) }, true)
Gear(oldRing)
assert(not progress.Live().complete and progress.Skill("shadow_bolt").count == 0)
assert(not progress.Live().jewelry["gear:ring:accuria"].complete)
Offer("jewel", Jewel(ring, "grow", "伤害+28.3%", "伤害=35.7%=64%=+", 2))
Pick()
Gear(newRing)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 1 and not progress.Live().jewelry["gear:ring:accuria"].complete)
Offer("jewel", Jewel(other, "new", otherRow.text, "", 1))
Pick()
Gear(otherRow)
assert(not progress.Live().jewelry["gear:ring:accuria"])
assert(progress.Live().jewelry["gear:ring:dragonslayer"].count == 0 and progress.Live().jewelry["gear:ring:dragonslayer"].complete)
Gear(otherRow, otherRow)
assert(not progress.Live().jewelry["gear:ring:dragonslayer"])

-- Distinct hands may arrive before the first fresh gear observation.
Gear(oldRing, otherRow)
Offer("jewel", Jewel(ring, "grow", "伤害+28.3%", "伤害=35.7%=64%=+", 2))
Pick()
Offer("jewel", Jewel(ring, "grow", "伤害+35.2%", "伤害=64%=99.2%=+", 3))
Pick()
Gear(newRing, otherRow)
Gear(Row(ring, { 99, "伤害+99.2%", 3 }), otherRow)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 2)
Offer("jewel", Jewel(ring, "grow", "伤害+2%", "伤害=99.2%=101.2%=+", 0))
Pick()
Gear(Row(ring, { 110, "伤害+110%", 3 }), otherRow)
assert(progress.Live().jewelry["gear:ring:accuria"].count == 2, "unrelated native change cannot confirm the offered delta")

-- Run the actual shared renderer, including old records, localization and
-- sizing at an increased font step with host-provided text metrics.
local function GoldButton(parent, width, _, _, label)
	local button = CreateFrame("Button", nil, parent)
	button:SetWidth(width)
	button.text = button:CreateFontString()
	button.text:SetText(label)
	return button
end
SurvivorUI_GoldButton = GoldButton
function SurvivorUI_RunRarityColor() return 0.8, 0.8, 0.8 end
function SurvivorUI_PieceTextStep() return 3 end
dofile("SurvivorUI/RebornProgressionView.lua")
progress.ShowHistory(saved, saved)
local window = SurvivorUIProgression
assert(window and UISpecialFrames[1] == "SurvivorUIProgression")
assert(window.heading:GetText() == "Skill upgrades" and window.status:GetText():find("Campaign", 1, true))
assert(window.content.rows[1].title:GetText():find("35691", 1, true) == nil)
local bondHeader
for _, row in ipairs(window.content.rows) do if row.key == "demonic_knowledge" then bondHeader = row end end
assert(bondHeader and bondHeader.detail:GetText():find("-20% attack interval", 1, true))
if bondHeader.closed then bondHeader.scripts.OnClick() end
local foundCap
for _, row in ipairs(window.content.rows) do
	if row:IsShown() and row.detail:GetText():find("Offered 13% → 28%", 1, true)
		and row.detail:GetText():find("Applied total 20%", 1, true) then foundCap = true end
end
assert(foundCap and window.range > 0)
window.sort.scripts.OnClick()
assert(window.sort.text:GetText() == "Group by skill")
arg1 = -1
window.scroll.scripts.OnMouseWheel()
assert(window.scroll:GetVerticalScroll() > 0)
language = "zh"
progress.ShowHistory(saved.endless, saved)
assert(window.heading:GetText() == "技能升级" and window.status:GetText():find("无尽", 1, true))
local old = { zone = "Old run", time = 99 }
progress.ShowHistory(old, old)
assert(window.status:GetText():find("技能升级记录不可用", 1, true))
assert(not window.content.rows[1]:IsShown())
local lines = SurvivorUI_RebornAbilityTooltipLines({ key = "shadow_bolt", rank = 4, text = "Current text" })
assert(lines[#lines].text:find("记录不完整", 1, true))
progress.Toggle()
assert(not window:IsShown() and not progress.Enabled() and progress.Live())

AZS_RequestAbilities = nil
Start("original", 0, 1)
Offer("spell", Skill("shadow_bolt", 686, 2, 4, "d65:0:65"))
Pick()
Learned({ NativeSpell(2) }, true)
assert(not progress.Live() and not progress.Enabled() and sends > 0)
print("PASS: progression native events, diagnostics-off choices, Session 033 caps, jewelry identities, history and host viewer")
