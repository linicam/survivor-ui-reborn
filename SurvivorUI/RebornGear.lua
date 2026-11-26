-- A small world-UI fallback for the separate Reborn hero-menu Lua environment.
if SurvivorUI_Standby or not SurvivorUI_RebornGearModel then return end

local Gear = SurvivorUI_RebornGearModel
local WIDTH, HEIGHT = 590, 510
local panel, context, entries, results
local function T(key) return SurvivorUI_T(key) end

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if type(SurvivorUIDB.rebornGear) ~= "table" then SurvivorUIDB.rebornGear = {} end
	local settings = SurvivorUIDB.rebornGear
	if type(settings.references) ~= "table" then settings.references = {} end
	return settings
end

local function Say(message)
	DEFAULT_CHAT_FRAME:AddMessage(T(message))
end

local function Read(mapOnly)
	local catalog = Gear.Catalog(AZS_GEN)
	local class, zone, tier, background, slot = string.match(context:GetText(),
		"^%s*([%w_]+)%s+([%w_]+)%s+(%d)%s+([%d%.%+%-]+)%s*([%w_]*)%s*$")
	tier, background = tonumber(tier), tonumber(background)
	local pressure = zone and Gear.Pressure(SurvivorUI_RebornMapReference, zone, tier)
	if not pressure or not background or background <= -100 or background > 10000
		or (slot ~= "" and (not catalog or not catalog.slots[slot])) then
		return nil, T("Check class, map key, tier, background and optional slot.")
	end
	local pieces, line = Gear.Parse(catalog, class, entries:GetText())
	if not pieces and mapOnly and string.match(entries:GetText(), "^%s*$") then
		return { catalog = catalog, class = class, zone = zone, tier = tier, pressure = pressure, background = background / 100 }
	end
	if not pieces then return nil, string.format(T("Check gear input (line %d)."), line) end
	local stats, sets = Gear.Totals(catalog, class, pieces.current)
	return { catalog = catalog, class = class, zone = zone, tier = tier, pressure = pressure, slot = slot,
		background = background / 100, pieces = pieces, stats = stats, sets = sets }
end

local function Add(text)
	results:AddMessage(text, 0.9, 0.93, 0.96)
end

local function ActiveSets(sets)
	local list = {}
	for tier, bonuses in pairs(sets or {}) do
		for _, bonus in ipairs(bonuses) do
			local template = AZS_L and AZS_L[bonus.template] or nil
			local text = template and string.gsub(template, "{(%w+)}", function(key)
				return bonus.values[key] or "?"
			end) or bonus.text
			table.insert(list, string.format("%s %d%s · %s", tier, bonus.pieces, bonus.strong and " ★5" or "", text))
		end
	end
	table.sort(list)
	return list
end

local function Delta(old, new)
	local list = {}
	for key, after in pairs(new) do
		local change = after - (old[key] or 0)
		if math.abs(change) > 0.00001 then
			local flat = key == "hp" or key == "regen"
			table.insert(list, string.format("%s %+.2f%s", T(key), flat and change or change * 100, flat and "" or "%"))
		end
	end
	for key, before in pairs(old) do
		if not new[key] and math.abs(before) > 0.00001 then
			local flat = key == "hp" or key == "regen"
			table.insert(list, string.format("%s %+.2f%s", T(key), flat and -before or -100 * before, flat and "" or "%"))
		end
	end
	table.sort(list)
	return table.getn(list) > 0 and table.concat(list, "  ·  ") or T("No modeled attribute change")
end

local function CompareSets(before, after)
	if not before or not after then Add(T("Set data unavailable")); return end
	local oldSet, newSet = ActiveSets(before), ActiveSets(after)
	local oldKeys, newKeys = {}, {}
	for _, key in ipairs(oldSet) do oldKeys[key] = true end
	for _, key in ipairs(newSet) do newKeys[key] = true end
	local changed = false
	for _, key in ipairs(oldSet) do
		if not newKeys[key] then Add(T("Set lost") .. " · " .. key); changed = true end
	end
	for _, key in ipairs(newSet) do
		if not oldKeys[key] then Add(T("Set gained") .. " · " .. key); changed = true end
	end
	if changed then Add(T("Unmodeled set effects can change the best choice.")) end
end

local function Replacement(s, option)
	local pieces, placed = {}, false
	for i, current in ipairs(s.pieces.current) do
		pieces[i] = current.slot == option.slot and option or current
		if current.slot == option.slot then placed = true end
	end
	if not placed then table.insert(pieces, option) end
	return Gear.Totals(s.catalog, s.class, pieces)
end

local function UpgradePreview(s, ref)
	for _, group in ipairs(s.pieces.groups) do
		if s.slot == "" or s.slot == group.slot then
			local current = group.worn and group.worn.choices[1]
			Add(T(group.slot) .. " · " .. (current and (current.tier .. " ★" .. current.stars) or T("No declared equipped piece")))
			for _, entry in ipairs(group.entries) do
				local indices, seen = {}, {}
				local function Include(index)
					if index >= 1 and entry.start + index - 1 <= 5 and not seen[index] then
						seen[index] = true
						table.insert(indices, index)
					end
				end
				Include(current == entry.choices[1] and 2 or 1)
				if s.slot ~= "" then
					if entry ~= group.worn or entry.start < 3 then Include(4 - entry.start) end
					if entry ~= group.worn or entry.start < 5 then Include(6 - entry.start) end
				end
				for _, index in ipairs(indices) do
					local option = entry.choices[index]
					if option then
						Add(string.format(T("%s ★%d · %s · %d extra gold"), option.tier, option.stars, T(option.kind), option.cost))
					else
						local stars = entry.start + index - 1
						option = { slot = entry.slot, tier = entry.tier, stars = stars,
							stats = Gear.Piece(s.catalog, s.class, entry.slot, entry.tier, stars) }
						Add(string.format(T("%s ★%d · price unknown"), option.tier, option.stars))
					end
					Add(Delta(current and current.stats or {}, option.stats))
					local totals, sets = Replacement(s, option)
					local ratio = Gear.Scenario(s.pressure, ref, totals.damage or 0, s.background)
					if ratio then Add(string.format(T("Modeled opening output pressure %.1f%%"), ratio * 100)) end
					CompareSets(s.sets, sets)
				end
			end
		end
	end
end

local function Reference(s, settings)
	local ref = settings.references[s.class]
	if not s.catalog or type(ref) ~= "table" or ref.version ~= Gear.version or ref.background ~= s.background then return nil end
	local pressure = Gear.Pressure(SurvivorUI_RebornMapReference, ref.zone, ref.tier)
	if not pressure or type(ref.pressure) ~= "number" or math.abs(pressure - ref.pressure) > 0.000000001 then return nil end
	if not Gear.ReferenceCurrent(s.catalog, s.class, ref) then return nil end
	return ref
end

local function ShowPlan(s, needed, farm, ref, requirements)
	Add(T(requirements and "Keep currently active sets" or (farm and "Farm & Upgrade" or "Stars Only")))
	local plan, reason = Gear.Optimize(s.pieces, needed, farm, nil, requirements)
	if not plan then
		Add(T(reason == "sets" and "No listed setup keeps these set thresholds."
			or "Search limit reached. Narrow the candidate list."))
		return
	end
	local ratio = Gear.Scenario(s.pressure, ref, plan.power, s.background)
	Add(string.format(T("%d extra gold · modeled pressure %.1f%%"), plan.cost, ratio * 100))
	Add(T(plan.reached and "Target met in the listed damage scenario." or "Best listed damage still leaves a gap."))
	if s.pieces.incomplete then Add(T("Unpriced stars are excluded from the search.")) end
	local current = {}
	for _, piece in ipairs(s.pieces.current) do current[piece.slot] = piece end
	local steps = {}
	for _, item in ipairs(plan.pieces) do
		local old = current[item.slot]
		if old ~= item then table.insert(steps, item) end
	end
	table.sort(steps, function(a, b)
		local function Value(item)
			local old = current[item.slot]
			local gain = item.power - (old and old.power or 0)
			return gain > 0 and item.cost == 0 and math.huge or gain / math.max(item.cost, 1)
		end
		local x, y = Value(a), Value(b)
		if x == y then return s.catalog.slots[a.slot].index < s.catalog.slots[b.slot].index end
		return x > y
	end)
	if table.getn(steps) > 0 then Add(T("Suggested order by piece damage gain per gold")) end
	for _, item in ipairs(steps) do
		local old = current[item.slot]
		local from = old and (old.tier .. " ★" .. old.stars) or "—"
		Add(T(item.slot) .. " · " .. from .. " → " ..
			string.format(T("%s ★%d · %s · %d extra gold"), item.tier, item.stars, T(item.kind), item.cost))
		Add(Delta(old and old.stats or {}, item.stats))
	end
	local stats, sets = Gear.Totals(s.catalog, s.class, plan.pieces)
	Add(T("Total attribute change") .. " · " .. Delta(s.stats, stats))
	CompareSets(s.sets, sets)
	Add(T("Preview set changes before equipping replacements together."))
	return plan
end

local function Calculate(action)
	results:Clear()
	local state, err = Read(action == "map" or action == "reference")
	if not state then Add(err); return end
	local settings = Settings()
	settings.context, settings.entries = context:GetText(), entries:GetText()
	if action == "reference" then
		local ref = Reference(state, settings)
		if not ref then Add(T("Save a reference with this class and fixed background.")); return end
		Add(string.format(T("Reference %s / %d · %d pieces"), ref.zone, ref.tier, table.getn(ref.gear)))
		for _, item in ipairs(ref.gear) do
			Add(T(item.slot) .. " · " .. item.tier .. " ★" .. item.stars .. " · " .. Delta({}, item.stats))
		end
		for _, label in ipairs(ActiveSets(ref.sets)) do Add(T("Active set") .. " · " .. label) end
		return
	end
	if not state.pieces then
		local ref = Reference(state, settings)
		local base = ref and ref.pressure or Gear.Pressure(SurvivorUI_RebornMapReference, "naxx", 0)
		Add(T("Map / tier") .. " · " .. state.zone .. " / " .. state.tier)
		Add(ref and string.format(T("Reference %s / %d · %d pieces"), ref.zone, ref.tier, table.getn(ref.gear)) or "Naxxramas Normal")
		Add(string.format(T("Map health scaling vs reference %.1f%%"), 100 * state.pressure / base))
		if state.tier >= 3 then Add(T("Heroic affixes can change the actual workload.")) end
		Add(T("Enter gear to calculate equipment-adjusted pressure."))
		return
	end
	local damage = state.stats.damage or 0
	if action == "save" then
		if not state.sets then Add(T("Set data unavailable")); return end
		local gear = {}
		for _, item in ipairs(state.pieces.current) do
			table.insert(gear, { slot = item.slot, tier = item.tier, stars = item.stars, stats = item.stats })
		end
		settings.references[state.class] = { version = Gear.version, pressure = state.pressure, damage = damage,
			background = state.background, gear = gear, sets = state.sets, zone = state.zone, tier = state.tier,
			stats = state.stats }
		Add(T("Reference saved for this class."))
	end
	if action == "record" then
		if SurvivorUI_RebornRecording and SurvivorUI_RebornRecording() then
			SurvivorUI_RebornRecord("gear_analysis", { class = state.class, zone = state.zone, tier = state.tier,
				pieces = state.pieces.current, stats = state.stats, sets = state.sets })
			Add(T("Declared gear recorded."))
		else Add(T("Start Reborn recording first.")) end
		return
	end
	local ref = Reference(state, settings)
	if action == "gear" then UpgradePreview(state, ref); return end
	Add(T("Map / tier") .. " · " .. state.zone .. " / " .. state.tier)
	Add(string.format(T("Listed gear damage +%.2f%%"), damage * 100))
	for _, label in ipairs(ActiveSets(state.sets)) do Add(T("Active set") .. " · " .. label) end
	if not ref then Add(T("Save a reference with this class and fixed background.")); return end
	Add(string.format(T("Reference %s / %d · %d pieces"), ref.zone, ref.tier, table.getn(ref.gear)))
	Add(string.format(T("Map health scaling vs reference %.1f%%"), 100 * state.pressure / ref.pressure))
	Add(string.format(T("Listed damage multiplier vs reference %.1f%%"),
		100 * (1 + state.background + damage) / (1 + state.background + ref.damage)))
	local ratio, needed = Gear.Scenario(state.pressure, ref, damage, state.background)
	Add(string.format(T("Modeled opening output pressure %.1f%%"), 100 * ratio))
	if ratio > 1 then Add(string.format(T("Additional modeled damage required %.1f%%"), 100 * (ratio - 1))) end
	Add(T("Scenario uses listed damage only. Set effects, spawn patterns, crit and cooldown stay separate."))
	if state.tier >= 3 or ref.tier >= 3 then Add(T("Heroic affixes can change the actual workload.")) end
	if action == "stars" or action == "farm" then
		local farm = action == "farm"
		local result = ShowPlan(state, needed, farm, ref)
		if farm and result and state.sets and next(state.sets) then
			local requirements = Gear.SetRequirements(state.sets, state.catalog.native.setRules)
			if not Gear.KeepsSets(result.pieces, requirements) then ShowPlan(state, needed, true, ref, requirements) end
		end
	end
end

local function RunAction(action)
	local settings = Settings()
	local feature = action == "map" and "difficulty" or action == "gear" and "preview"
		or (action == "stars" or action == "farm") and "planner" or action == "record" and "diagnostics"
	if feature and (settings[feature] == false or (feature == "diagnostics" and settings[feature] ~= true)) then
		Say("This gear analysis feature is disabled.")
		return
	end
	local phase = AZS_GetPhase and AZS_GetPhase()
	if phase == "playing" or phase == "choosing" or phase == "paused" then
		Say("Open gear analysis from the hub or outside active combat.")
		return
	end
	local ok = pcall(Calculate, action)
	if not ok then
		results:Clear()
		Add(T("Gear analysis is unavailable for these game data."))
	end
end

local function Label(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(T(text))
end

local function Build()
	panel = CreateFrame("Frame", "SurvivorUIRebornGearPanel", UIParent)
	panel:Hide()
	panel:SetWidth(WIDTH); panel:SetHeight(HEIGHT)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
	panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
	panel:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
	panel:RegisterEvent("PLAYER_ENTERING_WORLD")
	panel:SetScript("OnEvent", function() panel:Hide() end)
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
	Label(panel, "Gear & Difficulty", 16, -16)
	Label(panel, "class map tier background% [slot]", 16, -46)
	context = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	context:SetWidth(WIDTH - 38); context:SetHeight(23); context:SetMaxLetters(125)
	context:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -62)
	context:SetAutoFocus(false)
	context:SetScript("OnEscapePressed", function() context:ClearFocus() end)
	Label(panel, "slot quality stars worn/owned/farm [next prices: 100,200]", 16, -95)
	local scroll = CreateFrame("ScrollFrame", "SurvivorUIRebornGearInput", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -112)
	scroll:SetWidth(WIDTH - 52); scroll:SetHeight(112)
	entries = CreateFrame("EditBox", nil, scroll)
	entries:SetWidth(WIDTH - 58); entries:SetMultiLine(true); entries:SetMaxLetters(8192)
	entries:SetFontObject(GameFontHighlightSmall)
	entries:SetAutoFocus(false)
	entries:SetScript("OnEscapePressed", function() entries:ClearFocus() end)
	scroll:SetScrollChild(entries)
	results = CreateFrame("ScrollingMessageFrame", nil, panel)
	results:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -272)
	results:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 17)
	results:SetFontObject(GameFontHighlightSmall)
	results:SetJustifyH("LEFT"); results:SetFading(false); results:SetMaxLines(160)
	results:EnableMouseWheel(true)
	results:SetScript("OnMouseWheel", function(_, delta)
		if (delta or arg1 or 0) > 0 then results:ScrollUp() else results:ScrollDown() end
	end)
	local function ClearResults() results:Clear() end
	context:SetScript("OnTextChanged", ClearResults)
	entries:SetScript("OnTextChanged", ClearResults)
	local actions = {
		{ "save", "Save 100%" }, { "map", "Difficulty" }, { "gear", "Gear preview" },
		{ "stars", "Stars Only" }, { "farm", "Farm & Upgrade" },
	}
	for index, row in ipairs(actions) do
		local action = row[1]
		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		button:SetWidth(108); button:SetHeight(22)
		button:SetPoint("TOPLEFT", panel, "TOPLEFT", 15 + (index - 1) * 112, -236)
		button:SetText(T(row[2]))
		button:SetScript("OnClick", function()
			context:ClearFocus(); entries:ClearFocus()
			RunAction(action)
			results:ScrollToTop()
		end)
	end
	local settings = Settings()
	context:SetText(type(settings.context) == "string" and settings.context or "warlock naxx 0 0")
	entries:SetText(type(settings.entries) == "string" and settings.entries or "")
end

function SurvivorUI_RebornGearOpen(argument)
	if not SurvivorUI_RebornActive() then return end
	local feature = string.match(argument or "", "^toggle%s+(%a+)$")
	if feature == "difficulty" or feature == "preview" or feature == "planner" or feature == "diagnostics" then
		local settings = Settings()
		local enabled = settings[feature]
		if enabled == nil then enabled = feature ~= "diagnostics" end
		settings[feature] = not enabled
		if results then results:Clear() end
		Say(not enabled and "Gear analysis feature enabled." or "This gear analysis feature is disabled.")
		return
	end
	if argument == "off" then
		if panel then panel:Hide() end
		return
	end
	local phase = AZS_GetPhase and AZS_GetPhase()
	if phase == "playing" or phase == "choosing" or phase == "paused" then
		Say("Open gear analysis from the hub or outside active combat.")
		return
	end
	if not panel then Build() end
	if argument == "keys" then
		results:Clear()
		local catalog = Gear.Catalog(AZS_GEN)
		if catalog then
			local slots = {}
			for slot in pairs(catalog.slots) do table.insert(slots, slot) end
			table.sort(slots)
			Add(table.concat(slots, " · "))
		end
		for _, zone in ipairs(AZS_GEN and AZS_GEN.zones or {}) do Add(zone.key .. " · " .. (zone.name or "")) end
		results:ScrollToTop()
		panel:Show()
	elseif argument == "reference" then
		RunAction("reference")
		panel:Show()
	elseif argument == "capture" then
		RunAction("record")
		panel:Show()
	elseif panel:IsShown() then
		if argument ~= "show" then panel:Hide() end
	else
		panel:Show()
		if entries:GetText() == "" then Add(T("Enter values from the game menu. Upgrade prices are optional.")) end
	end
	return panel:IsShown()
end
