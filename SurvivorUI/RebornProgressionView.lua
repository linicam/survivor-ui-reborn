if SurvivorUI_Standby then return end

local Progress = SurvivorUI_RebornProgression
local T, TF = SurvivorUI_T, SurvivorUI_TF
local SEP = "  ·  "
local RARITIES = { [0] = "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local ORDER = { "d", "c", "t", "a", "u", "k", "m", "h", "b" }
local BOOSTS = { d = "+%d%% damage", c = "-%d%% cooldown", t = "+%d targets", a = "+%d%% area",
	u = "+%d%% duration", k = "+%d%% critical strike", m = "+%d%% damage", h = "+%d%% healing", b = "+%d%% absorb" }

local function BoostTemplate(key, code)
	if key == "demonic_knowledge" and code == "c" then return T("-%d%% attack interval") end
	local native = AZS_GEN and AZS_GEN.cardLines and AZS_GEN.cardLines[code]
	local phrase = native or BOOSTS[code]
	return phrase and (AZS_L and AZS_L[phrase] or T(phrase)) or code.." %d"
end

local function Boost(key, code, value)
	return string.format(BoostTemplate(key, code), value)
end

local function Rarity(rarity)
	local color = AZS_GEN and AZS_GEN.rarityColor and AZS_GEN.rarityColor[rarity]
	if type(color) ~= "string" or not string.find(color, "^%x%x%x%x%x%x%x%x$") then
		local r, g, b = SurvivorUI_RunRarityColor(rarity, true)
		color = string.format("ff%02x%02x%02x", math.floor(255 * r), math.floor(255 * g), math.floor(255 * b))
	end
	return "|c"..color..T(RARITIES[rarity] or "Unknown rarity").."|r"
end

local function Modifiers(key, skill, seen)
	local parts, shown = {}, {}
	local function Add(code)
		if shown[code] then return end
		shown[code] = true
		local total = skill.totals[code]
		if total ~= nil and (not seen or seen[code] ~= total) then
			table.insert(parts, Boost(key, code, total))
		elseif skill.unknown[code] then
			local label = string.gsub(string.gsub(BoostTemplate(key, code), "[+-]?%%d%%%%", ""), "[+-]?%%d", "")
			table.insert(parts, TF("{1} unavailable", (string.gsub(label, "^%s*(.-)%s*$", "%1"))))
		end
	end
	for _, code in ipairs(ORDER) do Add(code) end
	for code in pairs(skill.unknown) do Add(code) end
	return table.concat(parts, SEP)
end

local function Count(skill)
	local complete = skill and skill.complete and not skill.historyPartial
	return TF(complete and "{1} confirmed choices" or "{1} observed choices", skill and skill.count or 0)
end

function Progress.TooltipLines(ability, lines)
	local skill = Progress.Skill(ability.key)
	if not skill or skill.rank ~= tonumber(ability.rank) then
		table.insert(lines, { text = T("Skill upgrade history unavailable"), kind = "progression" })
		return
	end
	-- Demonic Knowledge's current native text already reads out its three
	-- card modifiers. Retain that text and avoid listing the same values again.
	local seen = Progress.BondTotals(ability.key, skill.tip or ability.text)
	local totals = Modifiers(ability.key, skill, seen)
	if totals ~= "" then
		table.insert(lines, { text = TF("Card modifiers: {1}", totals), kind = "progression" })
	end
	local count = Count(skill)
	if skill.acquisitions > 0 then count = count..SEP..TF("{1} acquired · {2} enhanced", skill.acquisitions, skill.count - skill.acquisitions) end
	if not skill.complete or skill.historyPartial then count = count..SEP..T("Partial history") end
	table.insert(lines, { text = count, kind = "progression" })
	local names = {}
	for rarity = 0, 4 do
		if skill.rarities[rarity] then table.insert(names, Rarity(rarity).." ×"..skill.rarities[rarity]) end
	end
	if skill.rarities[-1] then table.insert(names, Rarity(nil).." ×"..skill.rarities[-1]) end
	if table.getn(names) > 0 then table.insert(lines, { text = table.concat(names, SEP), kind = "progression" }) end
end

function Progress.EnhancementText(count, complete)
	if complete then return TF("Enhancements: {1}", count) end
	if count and count > 0 then return TF("Enhancements observed: {1} (partial history)", count) end
	return T("Enhancement count unavailable")
end

function Progress.Enabled()
	return SurvivorUI_RebornActive() and (not SurvivorUIDB or SurvivorUIDB.rebornProgression ~= false)
end

local window, history, context, chronological, collapsed, autoKey
local WIDTH, HEIGHT, PAD = 474, 355, 12
local FONT = { title = 16, detail = 11, row = 12 }
local FLAT = "Interface\\Buttons\\WHITE8X8"
local BORDER = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 } }

local function Font(text, size)
	text:SetFont(SurvivorUI_FONT, size + (SurvivorUI_PieceTextStep and SurvivorUI_PieceTextStep("Skill upgrades") or 0))
end

local function Text(owner)
	local text = owner:CreateFontString(nil, "OVERLAY")
	text:SetJustifyH("LEFT")
	return text
end

local function AbilityName(key, skill)
	return skill.name or key, skill.icon
end

local function Clock(seconds)
	if seconds == nil then return "—" end
	return string.format("%d:%02d", math.floor(seconds / 60), math.mod(math.floor(seconds), 60))
end

local function ChoiceDetail(choice)
	local rows = {}
	for _, affix in ipairs(choice.affixes or {}) do
		local line = Boost(choice.key, affix.code, affix.amount)
		local unit = string.find(line, "%", 1, true) and "%" or ""
		if affix.before and affix.after then
			line = line.." ("..TF("Offered {1} → {2}", affix.before..unit, affix.after..unit)..")"
		end
		if affix.applied ~= nil then
			line = line..SEP..TF("Applied total {1}", affix.applied..unit)
		else
			line = line..SEP..T("Applied total unavailable")
		end
		table.insert(rows, line)
	end
	if choice.affixesUnknown then table.insert(rows, T("Card modifiers unavailable")) end
	return table.concat(rows, "\n")
end

local function Draw(reset)
	local data = history and history.progression or (not history and Progress.Live())
	if data and data.version ~= 1 then data = nil end
	local scroll, content = window.scroll, window.content
	Font(window.heading, FONT.title)
	Font(window.status, FONT.detail)
	window.heading:SetText(T("Skill upgrades"))
	window.sort.text:SetText(T(chronological and "Group by skill" or "Order by time"))
	local status = T(history and "Skill upgrade history unavailable" or "No active run")
	if data then status = T(data.complete and "Current run observed" or "Partial history") end
	if history and data and data.complete then status = T("Saved progression") end
	window.status:SetText(context and (status..SEP..context) or status)
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -math.max(58, 45 + window.status:GetStringHeight()))
	scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 16, PAD)
	local index, top = 0, 0
	local function Add(title, detail, icon, key)
		index = index + 1
		local row = content.rows[index]
		if not row then
			row = CreateFrame("Button", nil, content)
			row:SetWidth(WIDTH - 2 * PAD - 16)
			row.noHoverOutline = true
			row.art = row:CreateTexture(nil, "ARTWORK")
			row.art:SetWidth(17)
			row.art:SetHeight(17)
			row.art:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
			row.title, row.detail = Text(row), Text(row)
			row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -4)
			row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
			row.title:SetWidth(row:GetWidth() - 32)
			row.detail:SetWidth(row:GetWidth() - 32)
			row.detail:SetTextColor(0.74, 0.74, 0.78)
			row:SetHighlightTexture(FLAT)
			row:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.10)
			row:SetScript("OnClick", function()
				if row.key then
					collapsed[row.key] = not row.closed
					Draw()
				end
			end)
			content.rows[index] = row
		end
		row.key = key
		row.closed = key and (collapsed[key] == true or (collapsed[key] == nil and key ~= autoKey))
		row:EnableMouse(key ~= nil)
		Font(row.title, FONT.row)
		Font(row.detail, FONT.detail)
		row.title:SetTextColor(1, key and 0.84 or 1, key and 0.49 or 1)
		row.title:SetText(key and ((row.closed and "+  " or "−  ")..title) or title)
		row.detail:SetText(detail)
		row.art:SetTexture(icon)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
		row:Show()
		local height = math.max(23, row.title:GetStringHeight() + 10
			+ (detail ~= "" and row.detail:GetStringHeight() + 2 or 0))
		row:SetHeight(height)
		top = top + height + (key and 4 or 2)
		return row.closed
	end
	local function AddChoice(choice, skill)
		local title = table.concat({ TF("Lv. {1}", choice.level or "—"), Clock(choice.time), Rarity(choice.rarity),
			T(choice.type == "acquire" and "Acquisition" or "Enhancement") }, SEP)
		local name, icon = AbilityName(choice.key, skill)
		if chronological then title = name..SEP..title else icon = nil end
		Add(title, ChoiceDetail(choice), icon)
	end
	local choices, keys, groups = {}, {}, {}
	if data then
		for _, choice in ipairs(data.choices) do
			if choice.kind == "spell" then
				table.insert(choices, choice)
			end
		end
		table.sort(choices, function(a, b) return a.order < b.order end)
		if not chronological then
			for _, choice in ipairs(choices) do
				groups[choice.key] = groups[choice.key] or {}
				table.insert(groups[choice.key], choice)
			end
		end
		for key in pairs(data.skills) do table.insert(keys, key) end
		table.sort(keys, function(a, b) return AbilityName(a, data.skills[a]) < AbilityName(b, data.skills[b]) end)
		autoKey = autoKey or (choices[table.getn(choices)] or {}).key
		if chronological then
			for index = table.getn(choices), 1, -1 do
				local choice = choices[index]
				AddChoice(choice, data.skills[choice.key])
			end
		else
			for _, key in ipairs(keys) do
				local skill = data.skills[key]
				local name, icon = AbilityName(key, skill)
				local totals = Modifiers(key, skill)
				local detail = Count(skill)
				if totals ~= "" then detail = detail..SEP..totals end
				if not skill.complete or skill.historyPartial then detail = detail..SEP..T("Partial history") end
				local closed = Add(name..SEP..TF("Rank {1}", skill.rank), detail, icon, groups[key] and key)
				if not closed then
					for _, choice in ipairs(groups[key] or {}) do AddChoice(choice, skill) end
				end
			end
		end
		if table.getn(keys) == 0 or (chronological and table.getn(choices) == 0) then
			Add(T("No confirmed skill upgrades yet"), "")
		end
	end
	for i = index + 1, table.getn(content.rows) do content.rows[i]:Hide() end
	content:SetHeight(math.max(1, top))
	window.range = math.max(0, top - scroll:GetHeight())
	window.bar:SetMinMaxValues(0, math.max(1, window.range))
	if window.range > 0 then window.bar:Show() else window.bar:Hide() end
	window.bar:SetValue(reset and 0 or math.min(scroll:GetVerticalScroll(), window.range))
	scroll:SetVerticalScroll(window.bar:GetValue())
end

local function Create()
	window = CreateFrame("Frame", "SurvivorUIProgression", UIParent)
	window:SetWidth(WIDTH)
	window:SetHeight(HEIGHT)
	window:SetPoint("CENTER", UIParent, "CENTER", 0, 28)
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:SetBackdrop(BORDER)
	window:SetBackdropColor(0.04, 0.04, 0.065, 0.97)
	window:SetBackdropBorderColor(0.61, 0.50, 0.27, 1)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function() window:StartMoving() end)
	window:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	window:SetScript("OnHide", function() window:SetScript("OnUpdate", nil) end)
	if UISpecialFrames then table.insert(UISpecialFrames, "SurvivorUIProgression") end
	window.heading = Text(window)
	window.heading:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -11)
	window.heading:SetTextColor(1, 0.82, 0.3)
	window.status = Text(window)
	window.status:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -37)
	window.status:SetWidth(WIDTH - 2 * PAD)
	window.status:SetTextColor(0.74, 0.74, 0.78)

	local close = SurvivorUI_GoldButton(window, 25, nil, nil, "×")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -12)
	close.text:ClearAllPoints()
	close.text:SetPoint("CENTER", close, "CENTER", 0, 0)
	close:SetScript("OnClick", function() window:Hide() end)
	window.sort = SurvivorUI_GoldButton(window, 111, nil, nil, "")
	window.sort:SetPoint("RIGHT", close, "LEFT", -8, 0)
	window.sort.text:ClearAllPoints()
	window.sort.text:SetPoint("CENTER", window.sort, "CENTER", 0, 0)
	window.sort:SetScript("OnClick", function() chronological = not chronological; Draw(true) end)

	local scroll = CreateFrame("ScrollFrame", nil, window)
	window.scroll = scroll
	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(WIDTH - 2 * PAD - 16)
	content:SetHeight(1)
	content.rows = {}
	scroll:SetScrollChild(content)
	window.content = content
	local bar = CreateFrame("Slider", nil, window)
	bar:SetOrientation("VERTICAL")
	bar:SetValueStep(1)
	bar:SetWidth(8)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -3)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 3)
	bar:SetBackdrop(BORDER)
	bar:SetBackdropColor(0.12, 0.12, 0.15, 1)
	bar:SetBackdropBorderColor(0.24, 0.24, 0.27, 1)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetTexture(FLAT)
	thumb:SetVertexColor(0.64, 0.52, 0.29, 1)
	thumb:SetWidth(8)
	thumb:SetHeight(22)
	bar:SetThumbTexture(thumb)
	bar:SetScript("OnValueChanged", function() scroll:SetVerticalScroll(bar:GetValue()) end)
	window.bar = bar
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function()
		bar:SetValue(math.max(0, math.min(window.range, bar:GetValue() - (arg1 or 0) * 46)))
	end)
end

local function Show(moment, run)
	if not Progress.Enabled() then return end
	if not window then Create() end
	history = moment
	context = run and table.concat({ run.zone or "?", T(moment == run and run.result == "victory" and "Campaign"
		or moment ~= run and "Endless" or "Run"), Clock(moment.time) }, SEP) or nil
	chronological, collapsed, autoKey = false, {}, nil
	window:Show()
	window:Raise()
	Draw(true)
end
Progress.Show = function() Show() end
Progress.ShowHistory = Show

function Progress.Refresh()
	if window and window:IsShown() and not history then
		window:SetScript("OnUpdate", function()
			window:SetScript("OnUpdate", nil)
			Draw()
		end)
	end
end

function Progress.Toggle()
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.rebornProgression = not Progress.Enabled()
	if not Progress.Enabled() and window then window:Hide() end
	if SurvivorUIBuild and SurvivorUIBuild:IsShown() then Progress.BuildEntry(SurvivorUIBuild) end
	if SurvivorUI_RefreshHistoryProgression then SurvivorUI_RefreshHistoryProgression() end
end

function Progress.BuildEntry(list)
	if not Progress.Enabled() then
		if list.progression then list.progression:Hide() end
		return
	end
	if not list.progression then
		local button = CreateFrame("Button", nil, list)
		button:SetPoint("LEFT", list.title, "RIGHT", 10, 0)
		button:SetHeight(17)
		button.text = Text(button)
		button.text:SetAllPoints(button)
		button:SetScript("OnEnter", function() button.text:SetTextColor(1, 0.92, 0.62) end)
		button:SetScript("OnLeave", function() button.text:SetTextColor(0.79, 0.72, 0.55) end)
		button:SetScript("OnClick", Progress.Show)
		button.text:SetTextColor(0.79, 0.72, 0.55)
		list.progression = button
	end
	local button = list.progression
	local label = T("Skill picks")
	if button.text:GetText() ~= label or button.face ~= SurvivorUI_FONT then
		button.face = SurvivorUI_FONT
		button.text:SetFont(SurvivorUI_FONT, 10)
		button.text:SetText(label)
		button:SetWidth(button.text:GetStringWidth() + 3)
	end
	button:Show()
end
