-- Survivor UI - Copyright (C) 2026 morderous - GPL-3.0 - github.com/morderous/survivor-ui
-- Survivor UI: the note, once for each player, that the interface hides while
-- a level's cards are up (since v3.0.50, Mover.lua: on a small screen the
-- cards are large and the pieces stood on them). In the middle of the screen
-- as Change UI's box, some seconds into town: keep it so, everything back as
-- before, or the options' Layout tab to pick the pieces.

if SurvivorUI_Standby then return end

local Cards = { skins = {}, refresh = {} }

local function Supports(button)
	return button and button.art and button.icon and button.title and button.rarityText and button.sub
		and button.label and button.detail and button.note and button.texts and button.texts[10]
		and button.rim and button.rimGlow and button.glow and button.pennant and button.crystalGlow
		and button.rule and button.ruleRight and type(button.Fit) == "function"
end

function SurvivorUI_ClassicCardsAvailable()
	if not (SurvivorUI_RebornActive and SurvivorUI_RebornActive() and AZSCardsFrame and hooksecurefunc) then return false end
	for index = 1, 4 do
		if not Supports(getglobal("AZSCard"..index)) then return false end
	end
	return true
end

function SurvivorUI_ClassicCardsOn()
	return SurvivorUI_ClassicCardsAvailable() and (not SurvivorUIDB or SurvivorUIDB.rebornClassicCards ~= false)
end

function SurvivorUI_ToggleClassicCards()
	if not SurvivorUI_ClassicCardsAvailable() then return end
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.rebornClassicCards = not SurvivorUI_ClassicCardsOn()
	for _, refresh in ipairs(Cards.refresh) do refresh() end
end

-- Reposition the native regions within the native button. The button, its
-- animation, input, tooltip hit area and hand geometry still belong to the game.
local function ClassicLayout(button, enabled, spell)
	local skin = Cards.skins[button]
	if not enabled and not (skin and skin.original) then return end
	local regions = { button.icon, button.title, button.rarityText, button.sub, button.label, button.detail, button.note }
	if not skin then
		local panel = CreateFrame("Frame", nil, button)
		panel:SetAllPoints(button)
		panel:SetFrameLevel(button:GetFrameLevel())
		local flat = "Interface\\ChatFrame\\ChatFrameBackground"
		panel:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
		panel:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
		local chrome = { button.art, button.glow, button.pennant, button.rule, button.ruleRight, button.texts[10] }
		for _, group in ipairs({ button.rim, button.rimGlow }) do
			for _, piece in ipairs(group) do table.insert(chrome, piece) end
		end
		skin = { panel = panel, chrome = chrome }
		Cards.skins[button] = skin
		if button.rim[1] then
			hooksecurefunc(button.rim[1], "SetAlpha", function()
				if skin.original and skin.color then
					local c = skin.color
					skin.panel:SetBackdropBorderColor(c[1], c[2], c[3], 0.65 + 0.35 * (button.rimFocus or 0))
				end
			end)
		end
	end
	if not enabled then
		for index, region in ipairs(regions) do
			local original = skin.original[index]
			region:ClearAllPoints()
			for _, point in ipairs(original.points) do region:SetPoint(unpack(point)) end
			region:SetWidth(original.width)
			if region == button.icon then region:SetHeight(original.height) end
			if original.font[1] then region:SetFont(unpack(original.font)) end
			if original.spacing then region:SetSpacing(original.spacing) end
		end
		for index, piece in ipairs(skin.chrome) do
			if skin.shown[index] then piece:Show() end
		end
		if spell == nil then spell = skin.spell end
		if spell then button.crystalGlow:Show() else button.crystalGlow:Hide() end
		skin.panel:Hide()
		skin.original = nil
		return true
	end
	if not skin.original then
		skin.original, skin.shown = {}, {}
		for index, region in ipairs(regions) do
			local points = {}
			for point = 1, region:GetNumPoints() do points[point] = { region:GetPoint(point) } end
			skin.original[index] = { points = points, width = region:GetWidth(), height = region:GetHeight(),
				font = region.GetFont and { region:GetFont() } or {}, spacing = region.GetSpacing and region:GetSpacing() }
		end
		for index, piece in ipairs(skin.chrome) do skin.shown[index] = piece:IsShown() end
	end
	skin.spell = spell
	local width = button:GetWidth()
	local function Place(region, point, relative, anchor, x, y, wide)
		region:ClearAllPoints()
		region:SetPoint(point, relative, anchor, x, y)
		region:SetWidth(wide)
	end
	local function Font(region, size)
		region:SetFont(SurvivorUI_FONT or region:GetFont(), size + (SurvivorUI_FONT_BUMP or 0), "OUTLINE")
	end
	Place(button.icon, "TOPLEFT", button, "TOPLEFT", 15, -27, 40)
	button.icon:SetHeight(40)
	Place(button.rarityText, "TOP", button, "TOP", 23, -19, width - 78)
	Place(button.title, "TOP", button.rarityText, "BOTTOM", 0, -4, width - 78)
	Place(button.sub, "TOP", button.title, "BOTTOM", 0, -4, width - 78)
	Place(button.label, "TOP", button, "TOP", 0, -88, width - 28)
	Place(button.detail, "TOP", button.label, "BOTTOM", 0, -8, width - 28)
	Place(button.note, "BOTTOM", button, "BOTTOM", 0, 16, width - 28)
	Font(button.rarityText, 10)
	Font(button.title, 15)
	Font(button.sub, 10)
	Font(button.label, 12)
	Font(button.note, 10)
	button.label:SetSpacing(3)
	button.detail:SetSpacing(3)
	local function Height(region) return region.GetStringHeight and region:GetStringHeight() or region:GetHeight() end
	local room = button:GetHeight() - 118 - Height(button.label) - Height(button.note)
	for size = 12, 9, -1 do
		Font(button.detail, size)
		if Height(button.detail) <= room then break end
	end
	if Height(button.detail) > room or Height(button.rarityText) + Height(button.title) + Height(button.sub) > 61 then
		return ClassicLayout(button, false, spell)
	end
	for _, piece in ipairs(skin.chrome) do piece:Hide() end
	button.crystalGlow:Hide()
	local r, g, b = button.rarityText:GetTextColor()
	skin.color = { r, g, b }
	skin.panel:SetBackdropBorderColor(r, g, b, 0.65 + 0.35 * (button.rimFocus or 0))
	skin.panel:Show()
end

-- Pair each verified native before/after value with its already localized
-- bonus line. The native renderer still supplies the gain and its unit.
local function SpellTotals(card, text)
	local model = SurvivorUI_RebornAnalysisModel
	local boosts = card and model and model.Boosts(card.lines)
	if not boosts or not text then return text end
	local rows = {}
	for line in string.gmatch(text, "[^\n]+") do table.insert(rows, line) end
	if table.getn(rows) ~= table.getn(boosts) then return text end
	for index, boost in ipairs(boosts) do
		if boost.before and boost.after then
			local unit = string.find(rows[index], "%", 1, true) and "%" or ""
			rows[index] = rows[index] .. "  |cff9c9ca5"..boost.before..unit.." » "..boost.after..unit.."|r"
		end
	end
	return table.concat(rows, "\n")
end

-- The native hand fits its content after filling the cards and changing
-- Shift comparison. Refit only when an attribute label actually changes.
local function HookCardCapHints()
	if not (AZSCardsFrame and hooksecurefunc and SurvivorUI_RebornCardCapLines) then return end
	local clearAnalysis, refreshAnalysis = {}, {}
	for index = 1, 4 do
		local button = getglobal("AZSCard" .. index)
		if button and type(button.Fit) == "function" and button.detail then
			local slot = index
			local original, annotated, paintedHand, refitting
			local rawLabel, annotatedLabel
			local capDisplay
			local loggedHand
			-- Native FillCards writes the label before fitting. Shift comparison
			-- and late card tips only write the detail, including on an outgoing hand.
			local tracksHand = button.label and pcall(hooksecurefunc, button.label, "SetText", function()
				if not refitting then paintedHand, rawLabel = AZS_CARDS, nil end
			end)
			local function SetDetail(text)
				refitting = true
				button.detail:SetText(text)
				local ok, err = pcall(button.Fit)
				refitting = false
				if not ok then error(err) end
			end
			clearAnalysis[slot] = function()
				if not annotated or annotated == capDisplay then return end
				if button.saved and button.saved[1] == annotated then
					button.saved[1] = capDisplay
				elseif button.detail:GetText() == annotated then
					SetDetail(capDisplay)
				end
				annotated = capDisplay
			end
			local function Decorate()
				if refitting then return end
				local hand = AZS_CARDS
				local modern = Supports(button) and SurvivorUI_ClassicCardsAvailable()
				local classic = modern and SurvivorUI_ClassicCardsOn()
				if modern and not classic then
					if button.saved and button.saved[1] == annotated then button.saved[1] = original end
					if not button.saved and annotated ~= original and button.detail:GetText() == annotated then
						SetDetail(original)
					end
				elseif not button.saved and (not tracksHand or paintedHand == hand) then
					local display = button.detail:GetText()
					local base = display == annotated and original or display
					local card = hand and hand.kind == "jewel" and hand.cards and hand.cards[slot]
					capDisplay = SurvivorUI_RebornCardCapLines(card, base)
					local updated = capDisplay
					local analysis = SurvivorUI_RebornAnalysis
					if tracksHand and paintedHand and analysis and analysis.WantsCardHints() then
						local ok, hint = pcall(analysis.CardText, slot)
						if ok and hint and hint ~= "" then
							updated = (updated and updated ~= "" and updated .. "\n" or "") .. "|cff92dce5" .. hint .. "|r"
						end
					end
					original, annotated = base, updated
					if updated ~= display then
						SetDetail(updated)
					end
					if card and capDisplay ~= base and loggedHand ~= hand and SurvivorUI_RebornRecording
						and SurvivorUI_RebornRecording() then
						loggedHand = hand
						SurvivorUI_RebornRecord("card_cap_hint", { slot = slot, mode = card.mode, text = capDisplay })
					end
				end
				if modern then
					local display = button.label:GetText()
					if rawLabel == nil or display ~= annotatedLabel then rawLabel = display end
					local offer = paintedHand and paintedHand.kind == "spell" and paintedHand.cards and paintedHand.cards[slot]
					annotatedLabel = classic and SpellTotals(offer, rawLabel) or rawLabel
					refitting = true
					if display ~= annotatedLabel then button.label:SetText(annotatedLabel) end
					local returned = ClassicLayout(button, classic, offer and true or false)
					if returned then
						if classic and annotatedLabel ~= rawLabel then button.label:SetText(rawLabel) end
						button.Fit()
					end
					refitting = false
				end
			end
			hooksecurefunc(button, "Fit", Decorate)
			refreshAnalysis[slot] = function()
				if paintedHand and paintedHand == AZS_CARDS and AZSCardsFrame:IsShown()
					and button:IsShown() then Decorate() end
			end
			Cards.refresh[slot] = function()
				if button:IsShown() then button.Fit() end
			end
		end
	end
	if SurvivorUI_RebornAnalysis then
		SurvivorUI_RebornAnalysis.ClearCardDisplay = function()
			for _, clear in pairs(clearAnalysis) do pcall(clear) end
		end
		SurvivorUI_RebornAnalysis.RefreshCardDisplay = function()
			for _, refresh in pairs(refreshAnalysis) do pcall(refresh) end
		end
	end
	return true
end

if not HookCardCapHints() and hooksecurefunc then
	local cardWatch = CreateFrame("Frame")
	cardWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
	cardWatch:SetScript("OnEvent", function()
		if HookCardCapHints() then this:UnregisterEvent("PLAYER_ENTERING_WORLD") end
	end)
end

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local WIDTH = 440
local PAD = 16
local WAIT = 4                  -- seconds in town before it shows
local TEXT = { 0.9, 0.9, 0.92 }

local shade, box

local function Font(parent, size, color)
	local line = parent:CreateFontString(nil, "OVERLAY")
	line:SetFont(SurvivorUI_FONT, size + (SurvivorUI_FONT_BUMP or 0), "OUTLINE")
	line:SetTextColor(color[1], color[2], color[3])
	return line
end

local function Close()
	shade:Hide()
end

local function Button(label, width, onClick)
	local button = SurvivorUI_GoldButton(box, width, nil, nil, SurvivorUI_T(label))
	button.icon:Hide()
	button.text:ClearAllPoints()
	button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
	button:SetScript("OnClick", function()
		Close()
		onClick()
	end)
	return button
end

local function Build()
	shade = CreateFrame("Frame", "SurvivorUICardsShade", UIParent)
	shade:SetFrameStrata("FULLSCREEN_DIALOG")
	shade:SetAllPoints(UIParent)
	shade:EnableMouse(true)
	shade.dark = shade:CreateTexture(nil, "BACKGROUND")
	shade.dark:SetTexture(FLAT)
	shade.dark:SetVertexColor(0, 0, 0, 0.55)
	shade.dark:SetAllPoints(shade)
	shade:Hide()

	box = CreateFrame("Frame", "SurvivorUICardsNotice", shade)
	box:SetFrameLevel(shade:GetFrameLevel() + 5)
	box:SetWidth(WIDTH)
	box:SetPoint("CENTER", UIParent, "CENTER", 0, -30)
	box:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	box:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
	box:SetBackdropBorderColor(0, 0, 0, 1)
	box:EnableMouse(true)

	local accent = SurvivorUI_ACCENT or { 1, 0.82, 0 }
	local stripe = box:CreateTexture(nil, "ARTWORK")
	stripe:SetTexture(FLAT)
	stripe:SetVertexColor(accent[1], accent[2], accent[3], 1)
	stripe:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
	stripe:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
	stripe:SetHeight(2)

	local title = Font(box, 13, TEXT)
	title:SetPoint("TOP", box, "TOP", 0, -14)
	title:SetText(SurvivorUI_T("Hidden while you choose a card"))
	local text = Font(box, 10, TEXT)
	text:SetWidth(WIDTH - 2 * PAD)
	text:SetPoint("TOP", title, "BOTTOM", 0, -8)
	text:SetText(SurvivorUI_T("Survivor UI now hides itself while you choose a card, so the cards fit on any screen. You can bring it all back as it was, or show only some pieces, such as the meter or the build list."))

	local keep = Button("Keep it hidden", 120, function() end)
	keep:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -66, 14)
	local before = Button("Show as before", 120, function()
		local shown = SurvivorUI_CardsShown()
		for index = 1, table.getn(SurvivorUI_CARD_PIECES) do
			shown[SurvivorUI_CARD_PIECES[index].key] = true
		end
		SurvivorUI_RefreshCards()
	end)
	before:SetPoint("BOTTOM", box, "BOTTOM", 0, 14)
	local choose = Button("Choose pieces", 120, function()
		if SurvivorUI_OpenOptions then
			SurvivorUI_OpenOptions("layout")
		end
	end)
	choose:SetPoint("BOTTOMLEFT", box, "BOTTOM", 66, 14)

	box:SetHeight(14 + title:GetHeight() + 8 + text:GetHeight() + 14 + 17 + 14)
end

local watch = CreateFrame("Frame")
local wait, inTown = 0, 0
watch:SetScript("OnUpdate", function()
	wait = wait + arg1
	if wait < 1 then
		return
	end
	wait = 0
	if not SurvivorUIDB then
		return
	end
	if SurvivorUIDB.cardsNoticeSeen or not AZS_SetOnTopOfScreens then
		this:SetScript("OnUpdate", nil)
		return
	end
	local change = getglobal("SurvivorUIChangeShade")
	if not AZS_GetPhase or AZS_GetPhase() ~= "ready" or (change and change:IsShown()) or not SurvivorUI_GoldButton then
		inTown = 0
		return
	end
	inTown = inTown + 1
	if inTown >= WAIT then
		SurvivorUIDB.cardsNoticeSeen = true
		this:SetScript("OnUpdate", nil)
		Build()
		AZS_SetOnTopOfScreens(shade, true)
		shade:Show()
	end
end)
