-- Survivor UI - Copyright (C) 2026 morderous - GPL-3.0 - github.com/morderous/survivor-ui
-- Survivor UI: the note, once for each player, that the interface hides while
-- a level's cards are up (since v3.0.50, Mover.lua: on a small screen the
-- cards are large and the pieces stood on them). In the middle of the screen
-- as Change UI's box, some seconds into town: keep it so, everything back as
-- before, or the options' Layout tab to pick the pieces.

if SurvivorUI_Standby then return end

-- The native hand fits its content after filling the cards and changing
-- Shift comparison. Refit only when an attribute label actually changes.
local function HookCardCapHints()
	if not (AZSCardsFrame and hooksecurefunc and SurvivorUI_RebornCardCapLines) then return end
	local clearAnalysis, refreshAnalysis = {}, {}
	for index = 1, 4 do
		local button = getglobal("AZSCard" .. index)
		if button and type(button.Fit) == "function" and button.detail then
			local slot = index
			local original, annotated, annotatedHand, refitting
			local capDisplay
			local loggedHand
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
			refreshAnalysis[slot] = function()
				if annotatedHand and annotatedHand == AZS_CARDS and AZSCardsFrame:IsShown()
					and button:IsShown() and not button.saved then button.Fit() end
			end
			hooksecurefunc(button, "Fit", function()
				if refitting or button.saved then return end
				local display = button.detail:GetText()
				local base = display == annotated and original or display
				local hand = AZS_CARDS
				local card = hand and hand.kind == "jewel" and hand.cards and hand.cards[slot]
				capDisplay = SurvivorUI_RebornCardCapLines(card, base)
				local updated = capDisplay
				local analysis = SurvivorUI_RebornAnalysis
				-- A replaced hand may still be animating out. Do not attach the
				-- successor's estimate to already annotated outgoing text.
				if analysis and analysis.WantsCardHints() and (display ~= annotated or hand == annotatedHand) then
					local ok, hint = pcall(analysis.CardText, slot)
					if ok and hint and hint ~= "" then
						updated = (updated and updated ~= "" and updated .. "\n" or "") .. "|cff92dce5" .. hint .. "|r"
					end
				end
				original, annotated, annotatedHand = base, updated, hand
				if updated ~= display then
					SetDetail(updated)
				end
				if card and capDisplay ~= base and loggedHand ~= hand and SurvivorUI_RebornRecording
					and SurvivorUI_RebornRecording() then
					loggedHand = hand
					SurvivorUI_RebornRecord("card_cap_hint", { slot = slot, mode = card.mode, text = capDisplay })
				end
			end)
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
