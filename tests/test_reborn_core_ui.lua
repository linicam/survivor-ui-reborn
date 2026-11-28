-- Host tests for the presentation boundary. Native game actions are represented
-- by unchanged handler identities, and this suite sends no game commands.
table.getn = table.getn or function(t) return #t end
unpack = unpack or table.unpack
local Load = loadstring or load
local function Read(path)
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local function Section(source, first, last)
	local a = assert(source:find(first, 1, true))
	local b = assert(source:find(last, a + 1, true))
	return source:sub(a, b - 1)
end

local function Noop() end
local function Frame()
	local self = { points = {}, shown = true, width = 268, height = 390, scripts = {}, registrations = {}, spacing = 3 }
	function self:SetScript(event, fn) self.scripts[event] = fn end
	function self:RegisterEvent(event) self.registrations[event] = true end
	function self:Show() self.shown = true end
	function self:Hide() self.shown = false end
	function self:IsShown() return self.shown end
	function self:SetWidth(value) self.width = value end
	function self:SetHeight(value) self.height = value end
	function self:GetWidth() return self.width end
	function self:GetHeight() return self.height end
	function self:SetText(value) self.text = value end
	function self:GetText() return self.text end
	function self:SetAlpha(value) self.alpha = value end
	function self:ClearAllPoints() self.points = {} end
	function self:SetPoint(...) table.insert(self.points, { ... }) end
	function self:GetNumPoints() return #self.points end
	function self:GetPoint(i) return unpack(self.points[i]) end
	function self:SetFont(...) self.font = { ... } end
	function self:GetFont() return unpack(self.font or { "Game font", 14, "OUTLINE" }) end
	function self:GetSpacing() return self.spacing end
	function self:SetSpacing(value) self.spacing = value end
	function self:GetStringHeight() return self.text and self.text ~= "" and (self.stringHeight or 16) or 0 end
	function self:GetTextColor() return 0.7, 0.3, 0.9 end
	function self:GetFrameLevel() return 2 end
	function self:SetFrameLevel() end
	function self:SetBackdrop() end
	function self:SetBackdropColor() end
	function self:SetBackdropBorderColor(...) self.border = { ... } end
	function self:SetAllPoints() end
	return self
end

local frames = {}
function CreateFrame()
	local frame = Frame()
	table.insert(frames, frame)
	return frame
end

function getglobal(key) return _G[key] end
function hooksecurefunc(object, key, after)
	local before = object[key]
	object[key] = function(...) before(...); after(...) end
end

local reborn = true
function SurvivorUI_RebornActive() return reborn end
function SurvivorUI_RebornCardCapLines(card, text)
	return card and card.mode == "grow" and text .. " (addon cap)" or text
end
SurvivorUI_FONT = "Addon font"
SurvivorUIDB = {}
AZSCardsFrame = Frame()
for slot = 1, 4 do
	local card = Frame()
	for _, key in ipairs({ "art", "glow", "pennant", "crystalGlow", "icon", "title", "rarityText", "sub", "label", "detail", "note", "rule", "ruleRight" }) do
		card[key] = Frame()
		card[key]:SetPoint("CENTER", card, "CENTER", 0, 0)
	end
	card.rim, card.rimGlow = { Frame() }, { Frame() }
	card.texts = { [10] = Frame() }
	card.banish, card.scripts.OnClick, card.scripts.OnKeyDown = Frame(), Noop, Noop
	card.icon:SetWidth(60)
	card.icon:SetHeight(60)
	card.Fit = function()
		-- Native Fit measures the current text and resets these fonts and the
		-- bonus anchor. The other region anchors and sizes come from creation.
		local tight = card.detail:GetStringHeight() > 100
		card.label:ClearAllPoints()
		card.label:SetPoint("TOP", card.detail, "BOTTOM", 0, tight and -4 or -8)
		card.label:SetFont("Game font", tight and 11 or 15, "OUTLINE")
		card.title:SetFont("Game title", tight and 14 or 20, "OUTLINE")
		card.detail:SetFont("Game detail", tight and 11 or 13, "OUTLINE")
		card.detail:SetSpacing(tight and 0 or 3)
	end
	_G["AZSCard"..slot] = card
end

dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/CardsNotice.lua")
local card = AZSCard1
local function Hand(kind, count, label, detail, offer)
	AZS_CARDS = { kind = kind, cards = {} }
	for slot = 1, 4 do
		local button = _G["AZSCard"..slot]
		button.saved = nil
		if slot <= count then
			AZS_CARDS.cards[slot] = offer or {}
			button:Show()
			button.label:SetText(label)
			button.detail:SetText(detail)
			if kind == "spell" then button.crystalGlow:Show() else button.crystalGlow:Hide() end
			button.Fit()
		else
			button:Hide()
		end
	end
end

local spellLabel = "+65% damage\n+2 targets"
Hand("spell", 3, spellLabel, "Native first-acquisition description", { lines = "d65:0:65t2:0:2", new = 1 })
assert(SurvivorUI_ClassicCardsOn() and not card.art:IsShown() and card.icon:GetWidth() == 40)
assert(card.label:GetText():find("0% » 65%", 1, true) and card.label:GetText():find("0 » 2", 1, true))
assert(card.detail:GetText() == "Native first-acquisition description" and card.label:GetFont() == "Addon font")
assert(not AZSCard4:IsShown() and card:GetWidth() == 268 and card:GetHeight() == 390)
card.Fit()
assert(select(2, card.label:GetText():gsub("»", "")) == 2, "repeated Fit must not duplicate the terms")
SurvivorUI_ToggleClassicCards()
assert(not SurvivorUI_ClassicCardsOn() and SurvivorUIDB.rebornClassicCards == false and card.art:IsShown())
assert(card.label:GetText() == spellLabel and card.label:GetFont() == "Game font" and card.icon:GetWidth() == 60)
assert(card.crystalGlow:IsShown() and card.scripts.OnClick == Noop and card.scripts.OnKeyDown == Noop)

Hand("jewel", 4, "Luck +75.6%\nGold +63%", "Luck 20% » 75.6%", { mode = "grow" })
assert(card.art:IsShown() and AZSCard4:IsShown() and not card.crystalGlow:IsShown())
SurvivorUI_ToggleClassicCards()
assert(not card.art:IsShown() and not AZSCard4.art:IsShown())
card.saved = { card.detail:GetText() }
card.detail:SetText("Native Shift comparison")
card.Fit()
SurvivorUI_ToggleClassicCards()
assert(card.art:IsShown() and card.detail:GetText() == "Native Shift comparison" and not card.crystalGlow:IsShown())
card.saved = nil
SurvivorUI_ToggleClassicCards()
card.detail.stringHeight = 1000
card.Fit()
assert(card.art:IsShown() and card.label:GetFont() == "Game font", "overflow returns the card to its native presentation")
assert(SurvivorUI_ClassicCardsOn())
reborn = false
assert(not SurvivorUI_ClassicCardsAvailable(), "original clients do not opt into the style")
reborn = true
print("PASS: spell and jewelry card geometry, native restoration, controls, multiple affixes and overflow fallback")

do
	local picks = 0
	local pick = function() picks = picks + 1 end
	card.scripts.OnClick, card.scripts.OnKeyDown = pick, pick
	local function NativeChrome(spell, label, size, y)
		assert(card.art:IsShown() and card.glow:IsShown() and card.rim[1]:IsShown())
		assert(card.pennant:IsShown() and card.texts[10]:IsShown() and card.crystalGlow:IsShown() == spell)
		assert(card.icon:GetWidth() == 60 and card.icon:GetHeight() == 60 and card.icon:GetPoint(1) == "CENTER")
		local face, points = card.label:GetFont()
		local point, relative, anchor, _, offset = card.label:GetPoint(1)
		assert(face == "Game font" and points == size and card.label:GetText() == label)
		assert(point == "TOP" and relative == card.detail and anchor == "BOTTOM" and offset == y)
		assert(card.scripts.OnClick == pick and card.scripts.OnKeyDown == pick)
	end
	card.detail.stringHeight = nil
	Hand("spell", 3, spellLabel, "First spell description", { lines = "d65:0:65t2:0:2", new = 1 })
	card.scripts.OnClick()
	Hand("jewel", 4, "Jewelry bonus", "Current jewelry before and after", { mode = "grow" })
	assert(SurvivorUI_ClassicCardsOn() and not card.art:IsShown())
	assert(card.detail:GetText() == "Current jewelry before and after (addon cap)")
	card.saved = { card.detail:GetText(), "Current note" }
	card.detail:SetText("Current jewelry Shift comparison")
	card.detail.stringHeight = 130
	card.Fit()
	SurvivorUI_ToggleClassicCards()
	NativeChrome(false, "Jewelry bonus", 11, -4)
	assert(card.detail:GetText() == "Current jewelry Shift comparison")
	assert(card.saved[1] == "Current jewelry before and after")
	card.detail:SetText(card.saved[1])
	card.saved, card.detail.stringHeight = nil, nil
	card.Fit()
	NativeChrome(false, "Jewelry bonus", 15, -8)

	SurvivorUI_ToggleClassicCards()
	Hand("jewel", 4, "Different jewelry", "Different comparison", { mode = "grow" })
	card.scripts.OnKeyDown()
	Hand("spell", 3, spellLabel, "Next spell description", { lines = "d65:0:65t2:0:2", new = 1 })
	assert(not AZSCard4:IsShown() and not card.art:IsShown())
	SurvivorUI_ToggleClassicCards()
	NativeChrome(true, spellLabel, 15, -8)
	assert(card.detail:GetText() == "Next spell description" and not card.saved and picks == 2)
	print("PASS: successive spell and jewelry hands restore their own native fit after selection in both directions")
end

do
	local plates = Read("SurvivorPlates/SurvivorPlates.lua")
	local gate = assert(Load(Section(plates, "SurvivorPlates_Standby =", "local FLAT =") .. "return 'addon'"))
	local options = Read("SurvivorUI/Options.lua")
	local controls = assert(Load("local needsReload = false\n"
		.. Section(options, "local function PlatesPresentationOn()", "-- The parts the game")
		.. Section(options, "local function GameShown(", "-- The Default's tick")
		.. "return PlatesPresentationOn, TogglePlatesPresentation, GameShown, GameToggle, function() return needsReload end"))
	SurvivorPlatesDB = { hidden = true, show = { elite = true, normal = false }, keysAllowed = true }
	local settings, changes = SurvivorPlatesDB, 0
	AZS_RequestAbilities = function() end
	function GetCVar(key) assert(key == "nameplateShowEnemies"); return "0" end
	function ShowNameplates() changes = changes + 1 end
	function HideNameplates() changes = changes + 1 end
	assert(gate() == "addon" and changes == 0)
	local on, switch, nativeShown, nativeClick, reload = controls()
	local game = { paired = true }
	assert(on() and not nativeShown(game, on), "hidden addon plates still belong to the addon presentation")
	nativeClick(game, on, switch)
	assert(nativeShown(game, on) and reload() and SurvivorPlatesDB == settings and settings.hidden)
	local frameCount = #frames
	SlashCmdList = {}
	dofile("SurvivorPlates/SurvivorPlates.lua")
	assert(#frames == frameCount and changes == 0 and not SlashCmdList.SURVIVORPLATES and not SurvivorPlates_PlateShows,
		"native reload installs no plate engine, visibility writes or world marker claims")
	on, switch, nativeShown, nativeClick, reload = controls()
	assert(not on() and nativeShown(game, on) and not reload())
	SurvivorPlates_Toggle()
	assert(changes == 1, "existing binding can explicitly switch native visibility")
	switch()
	assert(on() and reload() and settings.hidden and settings.keysAllowed and settings.show.elite and not settings.show.normal)
	assert(gate() == "addon")
	print("PASS: Modules native plate selection survives reload and returns to preserved preferences")
end

do
	local source = Read("SurvivorPlates/SurvivorPlates.lua")
	local names = { plateOne = Frame(), plateTwo = Frame(), guardian = Frame(), boss = Frame() }
	local ids = { plateOne = "F130000000000004", plateTwo = "F130000000000005", guardian = "F130000000000006", boss = "F130000000000007" }
	C_NamePlate = { GetNamePlateForUnit = function(unit) return names[unit] end }
	function UnitGUID(unit) return ids[unit] end
	function AZS_RequestAbilities() error("presentation must not request abilities") end
	function AZS_UnitKind(unit) return unit == "plateOne" and "elite" or "normal" end
	function AZS_GetWorldAnchors()
		return { entries = { { unitId = 6, kind = "guardian" }, { unitId = 7, kind = "finalBoss" } } }
	end
	local resolve, refresh, switches = assert(Load(
		Section(source, "local SWITCH =", "local HOVER_RISE")
		.. Section(source, "local overlays =", "-- Each anchor")
		.. "return EnemyKind, ReadAnchors, SWITCH"))()
	local listener = frames[#frames]
	assert(listener.registrations.NAME_PLATE_UNIT_ADDED)
	local selectKind = listener.scripts.OnEvent
	for unit in pairs(names) do selectKind(listener, "NAME_PLATE_UNIT_ADDED", unit) end
	refresh()
	local enabled = { normal = false, elite = true, guardian = true, boss = true }
	local function Kind(unit) return resolve({ plate = names[unit], baseKind = "normal" }, "Shared name", false, 100) end
	assert(Kind("plateOne") == "elite" and enabled[switches[Kind("plateOne")]])
	assert(Kind("plateTwo") == "normal" and not enabled[switches[Kind("plateTwo")]])
	assert(Kind("guardian") == "guardian" and enabled[switches[Kind("guardian")]])
	assert(Kind("boss") == "final" and enabled[switches[Kind("boss")]])
	selectKind(listener, "NAME_PLATE_UNIT_REMOVED", "plateOne")
	assert(Kind("plateOne") == "normal")
	selectKind(listener, "PLAYER_LEAVING_WORLD")
	assert(Kind("guardian") == "normal")
	assert(resolve({ plate = names.plateOne, baseKind = "elite" }, "Known fallback name", false, 100) == "elite")
	print("PASS: non-targeted elite, mixed names, late boss and guardian classification, normal suppression and frame reuse")
end

do
	local source = Read("SurvivorUI/Tracker.lua")
	local head, settings = Frame(), { tracker = true, trackerX = 24 }
	head:Hide()
	local game, drawn, nativeShown, clockUpdates = nil, 0, true, 0
	function AZS_IsHudShown(part) assert(part == "clock"); return nativeShown end
	function AZS_SetHudShown(part, shown)
		assert(part == "clock")
		nativeShown, clockUpdates = shown, clockUpdates + 1
	end
	local apply, update = assert(Load([[
local head, Settings, Game, DrawLook = ...
]] .. Section(source, "-- Claim the Reborn clock", "local elapsed = 0") .. "return ApplyGameHud, UpdateTracker"))(
		head, function() return settings end, function() return game, "playing" end,
		function(data) if data.broken then error("fixture renderer unavailable") end; drawn = drawn + 1 end)
	apply()
	assert(nativeShown and not head:IsShown())
	game = { broken = true }
	assert(not pcall(update) and nativeShown and not head:IsShown())
	game = { target = 1320, hunt = "4,15" }
	assert(update() and drawn == 1 and head:IsShown() and not nativeShown)
	assert(update() and clockUpdates == 1 and drawn == 1)
	settings.tracker = false
	update()
	assert(nativeShown and not head:IsShown() and settings.trackerX == 24)
	settings.noGameClock = true
	apply()
	assert(not nativeShown, "persisted explicit hide keeps its meaning")
	settings.tracker, settings.noGameClock = true, nil
	update()
	game = nil
	update()
	assert(nativeShown and not head:IsShown())
	reborn = false
	apply()
	assert(not nativeShown, "original clock ownership remains driven by the setting")
	reborn = true
	print("PASS: tracker toggle, native clock restoration, display readiness and original-client isolation")
end

do
	local source = Read("SurvivorUI/Tracker.lua")
	local head = Frame()
	local dial = true
	function SurvivorUI_DrawDial() return 140 end
	function SurvivorUI_DialOn() return dial end
	function SurvivorUI_RebornObjectiveText(game) return game.target and "目标时间 22:00 · 小首领 4/15" end
	local draw = assert(Load([[
local head, Frame = ...
local WIDTH = 220
local function HeadText() local row = Frame(); row:SetHeight(12); return row end
local Num = tonumber
local function HideLines() end
]] .. Section(source, "local function Put(", "-- A boss's color") .. [[
local function Draw(game, phase) head.content = -DrawObjectives(game, phase, game.t, -20) end
]] .. Section(source, "local function DrawLook(", "-- Claim the Reborn clock") .. "return DrawLook"))(head, Frame)
	local game = { target = 1320, hunt = "4,15", t = 1200 }
	draw(game, "playing")
	assert(head.content == 154 and head.objectives:IsShown() and head.objectives:GetText():find("4/15", 1, true))
	draw({}, "playing")
	assert(head.content == 140 and not head.objectives:IsShown())
	draw(game, "victory")
	assert(not head.objectives:IsShown())
	dial = false
	head.coin, head.clock, head.shade = Frame(), Frame(), Frame()
	draw(game, "playing")
	assert(head.content == 34 and head.objectives:IsShown())
end
