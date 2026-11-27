-- Dalaran and Campaign equipment snapshots, planner and simulator.
if SurvivorUI_Standby or not SurvivorUI_RebornGearPlanner then return end

local Gear, Planner = SurvivorUI_RebornGearModel, SurvivorUI_RebornGearPlanner
local Maps = SurvivorUI_RebornMapReference
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local BORDER = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 }
local GOLD, TEXT, MUTED = { 1, 0.82, 0.42 }, { 0.94, 0.93, 0.89 }, { 0.72, 0.73, 0.76 }
local POSITIVE, NEGATIVE = { 0.55, 1, 0.65 }, { 1, 0.52, 0.52 }
local NEUTRAL = { body = { 0.12, 0.13, 0.16 }, edge = { 0.38, 0.38, 0.43 }, text = TEXT }
local MENU_HEIGHT = 23
local panel, shield, plannerTab, simulatorTab, baselineButton
local header, equipment, effectHeader, effects, divider, planCards, variantButtons, actions
local popup, menuChoice, panelTip
local hubMap, hubDifficulty, refreshGear, targetBox, budgetBox, protection, resetTarget, inputError
local executionShown, draftExplicit
local view, activeView, selectedPlan = "planner", nil, 1
local planVariants = {}
local details, fullPlan, detailOffset, detailStart, windowWidth, windowHeight
local observedZone, worn, state, draft, searches, rendering
local planEffects, simulation
local previewOwner, previewIsNative
local observationOrder, worldEpoch = 0, 0
local worldOrder, zoneOrder, armorOrder, associatedArmorOrder
local armorDisposition = "waiting_armor"
local diagnosticSyncRequested, diagnosticZoneWireSeen
local render, updateSearch, showView, drawComparison
local ROMAN = { "I", "II", "III", "IV", "V" }
local SLOT = { head = "Head", shoulders = "Shoulders", chest = "Chest", waist = "Waist", legs = "Legs",
	feet = "Feet", wrists = "Wrists", hands = "Hands", main_hand = "Main Hand", off_hand = "Off Hand", ranged = "Ranged" }
local TIER = { common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", pvp = "PvP",
	legendary = "Legendary", exotic = "Exotic", mythic = "Mythic", elementium = "Elementium" }
local STATS = {
	{ "damage", "Damage", false, "Output" }, { "crit", "Critical strike" }, { "crit_damage", "Critical damage" },
	{ "cooldown", "Cooldown reduction" }, { "area", "Area of effect" }, { "echo", "Echo" },
	{ "hp", "Health", true, "Survival" }, { "armor", "Damage reduction" }, { "regen", "Health per second", true },
	{ "speed", "Movement speed", false, "Utility" }, { "pickup", "Pickup range" }, { "gold", "Gold find" },
}

local function T(key) return SurvivorUI_T(key) end
local function F(key, ...) return string.format(T(key), ...) end
local function L(key)
	if not key then return "" end
	local localized = AZS_L and AZS_L[key]
	return localized and localized ~= key and localized or T(key)
end

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if type(SurvivorUIDB.rebornGear) ~= "table" then SurvivorUIDB.rebornGear = {} end
	local config = SurvivorUIDB.rebornGear
	if type(config.baselines) ~= "table" then config.baselines = {} end
	return config
end

function SurvivorUI_RebornGearEnabled()
	local config = SurvivorUIDB and SurvivorUIDB.rebornGear
	return SurvivorUI_RebornActive() and (type(config) ~= "table" or config.enabled ~= false)
end

local function MapName(key, live)
	local name = live
	for _, zone in ipairs(AZS_GEN and AZS_GEN.zones or {}) do
		if zone.key == key then name = L(zone.name); break end
	end
	return name or key
end

local function DifficultyName(level)
	return level == 0 and T("Normal") or F("Heroic %s", ROMAN[level] or tostring(level))
end

local function MapTitle(key, level, live)
	if type(key) ~= "string" or type(level) ~= "number" then return T("Selected map or difficulty unavailable") end
	return MapName(key, live) .. " · " .. DifficultyName(level)
end

local function Snapshot(zone)
	if type(zone) ~= "table" then return end
	local run = SurvivorUI_RebornStableRunId and SurvivorUI_RebornStableRunId(zone.run)
	local challenge = Planner.Token(zone.challenge)
	return {
		run = run or Planner.Token(zone.run), class = Planner.Token(zone.class),
		zone = Planner.Token(zone.zone), dt = tonumber(zone.dt), heroic = Planner.Token(zone.heroic),
		hasDifficulty = zone.dt ~= nil,
		hub = tonumber(zone.hub) == 1, aff = Planner.Token(zone.aff), affixes = Planner.Affixes(zone.affixes),
		challenge = challenge ~= "0" and challenge or nil,
		mode = (AZS_PG and AZS_PG.active) and "proving-grounds" or Planner.Token(zone.mode),
		zname = type(zone.zname) == "string" and zone.zname or nil,
	}
end

local function SameZone(a, b)
	if not a or not b then return false end
	local function RuleMode(mode)
		if mode ~= "campaign" and mode ~= "standard" and mode ~= "hub" then return mode end
	end
	return a.run == b.run and a.class == b.class and a.zone == b.zone and a.dt == b.dt
		and (a.heroic or tostring(a.dt)) == (b.heroic or tostring(b.dt)) and a.hub == b.hub and a.affixes == b.affixes
		and a.challenge == b.challenge and RuleMode(a.mode) == RuleMode(b.mode)
end

local function ClearPreview(owner)
	if not previewOwner or (owner and previewOwner ~= owner) then return end
	local previous, tip = previewOwner, previewIsNative and GameTooltip or panelTip
	previewOwner, previewIsNative = nil, nil
	if tip and tip:IsOwned(previous) then tip:Hide() end
end

local function PieceListsEqual(a, b)
	if not a or not b or table.getn(a) ~= table.getn(b) then return false end
	for i, piece in ipairs(a) do
		if not Planner.SamePiece(piece, b[i]) or piece.observed ~= b[i].observed or piece.icon ~= b[i].icon
			or piece.name ~= b[i].name or piece.set ~= b[i].set then return false end
	end
	return true
end

local function ClearState(keepDraft)
	ClearPreview()
	if not (keepDraft and draftExplicit) then draft, draftExplicit = nil, nil end
	state, searches = nil, nil
	planEffects, simulation, planVariants = nil, nil, {}
	if panel then panel:SetScript("OnUpdate", nil) end
end

local function ResolveSelection(zone)
	if not zone then return "waiting_zone", "waiting_zone" end
	local map = not Maps and "map_catalog_unavailable"
		or not zone.zone and "missing_zone_key"
		or (Maps[zone.zone] and "ready" or "unknown_campaign_key")
	local level, heroic = zone.dt, tonumber(zone.heroic)
	if level == nil then return map, zone.hasDifficulty and "invalid_dt" or "missing_dt" end
	if level < 0 or level > 5 or level ~= math.floor(level) then return map, "invalid_dt" end
	if zone.heroic ~= nil and heroic ~= level then
		return map, heroic and "heroic_mismatch" or "invalid_heroic"
	end
	return map, "ready"
end

local function EvaluateState(zone)
	local catalog = Gear.Catalog(AZS_GEN)
	local config = Settings()
	local class, key, level = zone.class, zone.zone, zone.dt
	local heroic = tonumber(zone.heroic)
	local modifiers = { aff = zone.aff, affixes = zone.affixes, challenge = zone.challenge, mode = zone.mode }
	local scope = Planner.Scope(level, modifiers)
	local demand
	local mapStatus, difficultyStatus = ResolveSelection(zone)
	local selected = mapStatus == "ready" and difficultyStatus == "ready"
	if zone.hub then
		key = type(config.hubMap) == "string" and config.hubMap or nil
		level = Planner.Input(config.hubDifficulty, 0, 5, true)
		heroic, modifiers = level, {}
		scope = Planner.Scope(level, modifiers)
		selected = key and Maps and Maps[key] ~= nil
	end
	if selected and level ~= nil and scope ~= "unsupported" then
		demand = SurvivorUI_RebornAnalysisModel.GearDemand(Maps[key], level)
	end
	local context = { class = class, hub = zone.hub, zone = selected and key, level = selected and level, heroic = heroic, scope = scope,
		origin = zone.hub and "dalaran" or "campaign",
		modifiers = modifiers, build = AZS and AZS.ServerBuild, demand = demand,
		pieces = worn, at = time and time() }
	local actual = worn and catalog and class and Planner.Evaluate(catalog, class, worn)
	local saved = class and config.baselines[class]
	local reference, issue
	if catalog and class and Maps then reference, issue = Planner.CheckReference(saved, context, catalog, Maps) end
	local evaluated = { catalog = catalog, context = context, actual = actual, reference = reference, saved = saved,
		issue = issue, current = Planner.Difficulty(demand, actual, reference), policy = Planner.Policy(config) }
	local map = Maps and Maps[context.zone]
	evaluated.drops = catalog and demand and map and Planner.DropTiers(catalog, Maps, map[7])
	return evaluated
end

local function NoteObservation()
	observationOrder = observationOrder + 1
	return observationOrder
end

local function TraceGear(trigger, wire, invalidation)
	if not SurvivorUI_RebornRecordGearState or not SurvivorUI_RebornRecording() then return end
	if trigger == "AZSZONE" and type(wire) == "string" and wire ~= "" then diagnosticZoneWireSeen = true end
	local enabled = SurvivorUI_RebornGearEnabled()
	local matched = observedZone and SameZone(observedZone, Snapshot(AZS_ZONE))
	local zone = matched and observedZone or nil
	local current = enabled and zone and (state or EvaluateState(zone)) or nil
	local map, difficulty = ResolveSelection(zone)
	local context = current and current.context
	local equipment
	if not enabled then equipment = "feature_disabled"
	elseif not zone then equipment = observedZone and "context_changed" or "waiting_zone"
	elseif not current.catalog then equipment = "catalog_unavailable"
	elseif not Planner.Class(current.catalog, zone.class) then equipment = "class_unavailable"
	elseif current.actual then equipment = table.getn(worn) == 0 and "known_empty" or "ready"
	elseif worn then equipment = "evaluation_unavailable"
	else equipment = armorDisposition end
	local baseline
	if not current then baseline = equipment
	elseif not current.catalog then baseline = "catalog_unavailable"
	elseif not Planner.Class(current.catalog, zone.class) then baseline = "class_unavailable"
	else baseline = current.issue or (current.reference and "ready" or "missing") end
	local pressure
	if not context then pressure = equipment
	elseif context.hub and not context.demand then pressure = "hub_without_campaign_target"
	elseif not context.hub and map ~= "ready" then pressure = map
	elseif not context.hub and difficulty ~= "ready" then pressure = difficulty
	elseif context.scope == "unsupported" then pressure = "unsupported_mode"
	elseif not context.demand then pressure = "demand_unavailable"
	elseif not current.actual then pressure = equipment
	elseif not current.reference then pressure = "baseline_" .. baseline
	elseif not current.current.output then pressure = "output_unavailable"
	elseif not current.current.survival then pressure = "partial_pressure"
	else pressure = "ready" end

	local demand = context and context.demand
	local plans = pressure == "partial_pressure" and "ready" or pressure
	if plans == "ready" and not current.actual.sets then plans = "sets_unavailable" end
	SurvivorUI_RebornRecordGearState({
		trigger = trigger, worldEpoch = worldEpoch, invalidation = invalidation,
		ordering = { world = worldOrder, zone = zoneOrder, armor = armorOrder, associatedArmor = associatedArmorOrder },
		catalog = { native = type(AZS_GEN) == "table", maps = type(Maps) == "table",
			equipment = current and current.catalog ~= nil or false },
		resolution = { enabled = enabled, map = map, difficulty = difficulty, scope = context and context.scope,
			equipment = equipment, armorDisposition = armorDisposition, armorAssociated = associatedArmorOrder ~= nil,
			acceptedArmorCount = associatedArmorOrder and table.getn(worn) or nil,
			baseline = baseline, pressure = pressure,
			planA = plans == "ready" and not current.drops and current.current.output > current.policy.target and "drop_scope_unavailable" or plans,
			planB = plans,
			saveBaseline = demand and demand.output ~= nil
				and current.actual ~= nil and current.actual.sets ~= nil and current.actual.output ~= nil or false },
	}, observedZone, wire)
end

local function InvalidateGear()
	worn, associatedArmorOrder = nil, nil
	armorDisposition = "waiting_armor"
	ClearState()
end

local function Read()
	local zone = observedZone
	if not zone then return end
	if not SameZone(zone, Snapshot(AZS_ZONE)) then
		observedZone = nil
		InvalidateGear()
		TraceGear("read", nil, "native_context_changed")
		return
	end
	if not state then state = EvaluateState(zone) end
	return state
end

local function RequestDiagnosticSync(fromOpen)
	if diagnosticSyncRequested or diagnosticZoneWireSeen or not SurvivorUI_RebornRecording
		or not SurvivorUI_RebornRecording() or not SurvivorUI_RebornGearEnabled() or not AZS_SendCommand then return end
	local zone = Snapshot(AZS_ZONE)
	if not fromOpen and not (zone and zone.hub and observedZone) then return end
	local map, difficulty = ResolveSelection(zone)
	if map == "ready" and difficulty == "ready" and observedZone and SameZone(observedZone, zone) then return end
	-- Auto recording sees the native entry sync. An unresolved selection
	-- in a late-start recording gets one documented read-only resync.
	diagnosticSyncRequested = true
	TraceGear("sync_request")
	if not pcall(AZS_SendCommand, "sync") then TraceGear("sync_failed") end
end

function SurvivorUI_RebornGearRecordStart()
	if not SurvivorUI_RebornActive() then return end
	diagnosticSyncRequested, diagnosticZoneWireSeen = nil, nil
	TraceGear("record_start")
	RequestDiagnosticSync(false)
end

local function ShortPercent(value)
	return value and string.format("%.1f%%", value) or T("Unavailable")
end

local function Delta(value, percent, lowerIsBetter)
	if tonumber(string.format("%.2f", value)) == 0 then return "—", MUTED end
	local beneficial = (value < 0) == (lowerIsBetter == true)
	return F(percent and "%+.2f pp" or "%+.2f", value), beneficial and POSITIVE or NEGATIVE
end

local function Colored(text, color)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(color[1] * 255), math.floor(color[2] * 255),
		math.floor(color[3] * 255), text)
end

local function PressureDelta(before, after)
	if not before or not after then return Colored(T("Unavailable"), MUTED) end
	return Colored(Delta(after - before, true, true))
end

local function PressureColor(before, after)
	if not before or not after or ShortPercent(before) == ShortPercent(after) then return MUTED end
	return after < before and POSITIVE or NEGATIVE
end

local function TierText(catalog, key)
	local tier = catalog.tiers[key]
	local color = tier and catalog.native.rarityColor and catalog.native.rarityColor[tier.id]
	local name = L(TIER[key] or tier.name or key)
	return color and ("|" .. "c" .. color .. name .. "|r") or name
end

local function ItemText(catalog, piece)
	return piece and (TierText(catalog, piece.tier) .. F(" ★%d", piece.stars)) or T("Empty slot")
end

local function ItemIcon(catalog, class, piece, fallback)
	if not piece then return fallback and ItemIcon(catalog, class, fallback) or "Interface\\Icons\\INV_Misc_QuestionMark" end
	local icon = piece.icon
	local slot, tier = catalog.slots[piece.slot], catalog.tiers[piece.tier]
	if not icon or icon == "" then
		for _, look in ipairs(catalog.native.setLooks or {}) do
			if look.class == class and look.rarity == tier.id then
				for _, row in ipairs(look.pieces) do if row[1] == slot.index then icon = row[4]; break end end
				break
			end
		end
	end
	if icon and icon ~= "" then
		if string.find(icon, "\\", 1, true) then return icon end
		if not piece.icon and not string.match(icon, "^[Ii][Nn][Vv]_") then icon = "INV_" .. icon end
		return "Interface\\Icons\\" .. icon
	end
	if fallback and fallback.icon then return ItemIcon(catalog, class, fallback) end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function SetEffect(bonus)
	return (string.gsub(L(bonus.template), "{(%w+)}", function(key) return bonus.values[key] or "?" end))
end

local function SetLines(catalog, old, new)
	local out = {}
	for _, tier in ipairs(Planner.Tiers(catalog)) do
		local before, after = {}, {}
		for _, bonus in ipairs(old[tier] or {}) do before[bonus.pieces] = bonus end
		for _, bonus in ipairs(new[tier] or {}) do after[bonus.pieces] = bonus end
		for _, n in ipairs(catalog.native.setRules.pieces) do
			local a, b = before[n], after[n]
			if (a or b) and (not a or not b or a.strong ~= b.strong or a.text ~= b.text) then
				local status = not a and "Set gained" or not b and "Set lost" or b.strong and "Set enhanced" or "Set weakened"
				local bonus = b or a
				table.insert(out, F("%s · %s (%d) · %s", T(status), TierText(catalog, tier), n, SetEffect(bonus)))
			end
		end
	end
	return out
end

local function QuoteText(quote)
	local cost = quote.unknown and F("%d gold known · additional price unavailable", quote.gold) or F("%d gold", quote.gold)
	if quote.kind == "farm" then return F("%s in stars · obtain item through drops", cost) end
	if quote.kind == "theoretical" then return F("%s in stars · acquisition unavailable or unknown", cost) end
	if quote.kind == "downgrade" or quote.kind == "removed" then return T("No refund modeled") end
	return cost
end

local function PriceLabel(quote)
	if not quote.unknown then return F("%d gold", quote.gold) end
	return quote.gold > 0 and F("%d gold known", quote.gold) or T("Price unknown")
end

local function AttributePreview(tip, before, after)
	for _, stat in ipairs(STATS) do
		local value = (after[stat[1]] or 0) - (before[stat[1]] or 0)
		local change, color = Delta(value * (stat[3] and 1 or 100), not stat[3])
		if color ~= MUTED then tip:AddLine(L(stat[2]) .. " " .. change, color[1], color[2], color[3], true) end
	end
end

local function PreviewChange(tip, current, pieces, base, before, after, caption)
	local catalog, context = current.catalog, current.context
	local slot = after and after.slot or before.slot
	local setup = Planner.Replace(pieces, slot, after and after.tier, after and after.stars)
	local evaluated = Planner.Evaluate(catalog, context.class, setup)
	if not evaluated then return end
	local quote = Planner.Quote(catalog, before, after, current.drops, context.class)
	tip:AddLine(caption, 1, 0.82, 0.22, true)
	local cost = QuoteText(quote)
	tip:AddLine(quote.estimated and F("%s (estimated price)", cost) or cost, 1, 1, 1, true)
	AttributePreview(tip, base.stats, evaluated.stats)
	if base.sets and evaluated.sets then
		for _, change in ipairs(SetLines(catalog, base.sets, evaluated.sets)) do tip:AddLine(change, 1, 1, 1, true) end
	end
	local from = Planner.Difficulty(context.demand, base, current.reference)
	local to = Planner.Difficulty(context.demand, evaluated, current.reference)
	if (from.output and to.output) or (from.survival and to.survival) then
		tip:AddLine(F("Output pressure %s · Survival pressure %s",
			PressureDelta(from.output, to.output),
			PressureDelta(from.survival, to.survival)), TEXT[1], TEXT[2], TEXT[3], true)
	end
	return quote
end

local function AddPreview(tip, current, pieces, evaluated, item)
	if not item then tip:AddLine(T("Empty slot")); return end
	local catalog, context = current.catalog, current.context
	local function Show(tier, star, caption)
		local quote = PreviewChange(tip, current, pieces, evaluated, item, { slot = item.slot, tier = tier, stars = star }, caption)
		if quote and tier ~= item.tier then
			tip:AddLine(T(quote.progression and "Direct ascension requires clearing the next expansion's final map; eligibility unknown."
				or "Direct ascension eligibility, price and resulting stars are unavailable."), 0.9, 0.82, 0.65, true)
		end
	end
	tip:AddLine(" ")
	if Gear.ValidPiece(catalog, context.class, item.slot, item.tier, item.stars + 1) then
		Show(item.tier, item.stars + 1, F("Next star · ★%d → ★%d", item.stars, item.stars + 1))
	else
		tip:AddLine(T("At maximum stars"), 0.85, 0.85, 0.85)
	end
	local tiers, nextTier = Planner.Tiers(catalog)
	local rank = catalog.tiers[item.tier].rank
	for _, tier in ipairs(tiers) do
		if catalog.tiers[tier].rank > rank and Gear.ValidPiece(catalog, context.class, item.slot, tier, 0) then
			nextTier = tier
			break
		end
	end
	if nextTier then
		Show(nextTier, 0, F("Next tier · %s → %s ★0 (drop preview)", ItemText(catalog, item), TierText(catalog, nextTier)))
	else
		tip:AddLine(T("At maximum tier"), 0.85, 0.85, 0.85)
	end
end

local hookedInspect, inspectOverview, overviewParent
local hookedSlots = setmetatable({}, { __mode = "k" })
local function NativePreview(owner)
	owner = owner or this
	if not SurvivorUI_RebornGearEnabled() or not AZSInspect or not AZSInspect:IsShown()
		or AZSInspect.unit ~= "player" or not (owner and owner.piece)
		or not (GameTooltip and GameTooltip:IsOwned(owner)) then return end
	local current = Read()
	local index = current and current.catalog and current.catalog.pieces.slots[owner.slot]
	local item = index and current.actual and Planner.BySlot(current.context.pieces)[index.key]
	local tier = item and current.catalog.tiers[item.tier]
	if tier and tier.id == tonumber(owner.piece.rarity) and item.stars == tonumber(owner.piece.stars) then
		if not previewIsNative then ClearPreview() end
		previewOwner, previewIsNative = owner, true
		AddPreview(GameTooltip, current, current.context.pieces, current.actual, item)
		GameTooltip:Show()
	end
end

local function InspectUpdated()
	local inspect, gear = AZSInspect, AZSInspectGear
	if previewIsNative then ClearPreview() end
	if not SurvivorUI_RebornGearEnabled() or not (inspect and inspect.unit == "player" and inspect:IsShown()
		and gear and gear:IsShown()) then
		if inspectOverview then inspectOverview:Hide() end
		return
	end
	for index = 0, 10 do
		local icon = _G["AZSInspectSlot" .. index]
		local owner = icon and icon:GetParent()
		if owner and owner.slot == index and not hookedSlots[owner] and type(owner.HookScript) == "function" then
			owner:HookScript("OnEnter", NativePreview)
			owner:HookScript("OnLeave", function(owner) ClearPreview(owner or this) end)
			hookedSlots[owner] = true
		end
	end
	if not inspectOverview or overviewParent ~= gear then
		if inspectOverview then inspectOverview:Hide() end
		overviewParent = gear
		inspectOverview = CreateFrame("Button", nil, gear, "UIPanelButtonTemplate")
		inspectOverview:SetPoint("TOPRIGHT", gear, "TOPRIGHT", -12, -11)
		inspectOverview:SetWidth(88)
		inspectOverview:SetHeight(22)
		inspectOverview:SetText(T("Upgrades"))
		inspectOverview:SetScript("OnClick", function()
			if SurvivorUI_RebornGearOpen("show") and AZSInspect then AZSInspect:Hide() end
		end)
	end
	inspectOverview:Show()
end

local function InstallInspectHook()
	local inspect = AZSInspect
	if inspect and inspect ~= hookedInspect and type(inspect.RefreshDoll) == "function" and type(hooksecurefunc) == "function" then
		hooksecurefunc(inspect, "RefreshDoll", InspectUpdated)
		if type(inspect.HookScript) == "function" then
			inspect:HookScript("OnHide", function() if previewIsNative then ClearPreview() end end)
		end
		hookedInspect = inspect
	end
	InspectUpdated()
end

local function Font(parent, size, color, justify)
	local label = parent:CreateFontString(nil, "OVERLAY")
	label:SetFont(SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF", size + (SurvivorUI_FONT_BUMP or 0), "OUTLINE")
	label:SetTextColor(color[1], color[2], color[3])
	label:SetJustifyH(justify or "LEFT")
	return label
end

local function Button(parent, caption, size, action, primary)
	local widget = SurvivorUI_GoldButton(parent, size, nil, nil, T(caption), not primary and NEUTRAL or nil)
	widget:SetHeight(24)
	widget.icon:Hide()
	widget.text:ClearAllPoints()
	widget.text:SetPoint("LEFT", widget, "LEFT", 4, 0)
	widget.text:SetPoint("RIGHT", widget, "RIGHT", -4, 0)
	widget.text:SetJustifyH("CENTER")
	widget:SetScript("OnEnter", function() widget:Light(true) end)
	widget:SetScript("OnLeave", function() widget:Light(false) end)
	widget:SetScript("OnMouseDown", function() widget.text:SetAlpha(0.72) end)
	widget:SetScript("OnMouseUp", function() widget.text:SetAlpha(1) end)
	widget:SetScript("OnClick", action)
	return widget
end

local function Control(widget, enabled, selected)
	if enabled then widget:Enable() else widget:Disable() end
	widget.lit = selected
	widget:Light(false)
	widget:SetAlpha(enabled and 1 or 0.44)
end

local function CloseMenu()
	menuChoice = nil
	if popup then popup:Hide() end
end

local function ShowGearTip(row)
	local current = Read()
	if menuChoice or not row.slot or row.context ~= current then return end
	panelTip:SetOwner(row.iconButton, "ANCHOR_RIGHT")
	panelTip:SetText(L(SLOT[row.slot]), GOLD[1], GOLD[2], GOLD[3])
	previewOwner, previewIsNative = row.iconButton, nil
	local comparison, change = row.comparison, row.change
	if row.plan then
		if change then
			local catalog, class = current.catalog, current.context.class
			local function Intrinsic(piece)
				return piece and Gear.Piece(catalog, class, piece.slot, piece.tier, piece.stars) or {}
			end
			local function Name(piece)
				return piece and piece.name and (piece.name .. " · " .. ItemText(catalog, piece)) or ItemText(catalog, piece)
			end
			local after = change.quote.kind == "stars" and change.before and change.before.name
				and (change.before.name .. " · " .. ItemText(catalog, change.after)) or Name(change.after)
			panelTip:AddLine(F("Planned item %s → %s", Name(change.before), after), GOLD[1], GOLD[2], GOLD[3], true)
			local cost = QuoteText(change.quote)
			panelTip:AddLine(change.quote.estimated and F("%s (estimated price)", cost) or cost, TEXT[1], TEXT[2], TEXT[3], true)
			if change.quote.kind == "farm" or change.quote.kind == "theoretical" then
				panelTip:AddLine(T("Direct ascension eligibility, price and resulting stars are unavailable."), TEXT[1], TEXT[2], TEXT[3], true)
			end
			AttributePreview(panelTip, Intrinsic(change.before), Intrinsic(change.after))
		else
			local item = ItemText(current.catalog, row.item)
			if row.item and row.item.name then item = row.item.name .. " · " .. item end
			panelTip:AddLine(item, TEXT[1], TEXT[2], TEXT[3], true)
		end
	else
		panelTip:AddLine(F("Simulated item · %s", ItemText(current.catalog, row.item)), GOLD[1], GOLD[2], GOLD[3], true)
		if change then panelTip:AddLine(QuoteText(change.quote), TEXT[1], TEXT[2], TEXT[3], true) end
		if row.item then
			panelTip:AddLine(T("Preview costs start from this simulated item."), TEXT[1], TEXT[2], TEXT[3], true)
			AddPreview(panelTip, current, comparison.pieces, comparison.evaluation, row.item)
		end
	end
	if panelTip.NumLines then
		for i = 1, panelTip:NumLines() do
			local line = _G["SurvivorUIRebornGearTooltipTextLeft" .. i]
			if line then line:SetFont(SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF", 11 + (SurvivorUI_FONT_BUMP or 0), "OUTLINE") end
		end
	end
	panelTip:Show()
	panelTip:SetBackdropColor(0.06, 0.065, 0.08, 1)
end

local function Row(area)
	area.used = area.used + 1
	local row = area.rows[area.used]
	if not row then
		row = CreateFrame("Frame", nil, area.content)
		row.label = Font(row, 11, TEXT)
		row.cells = {}
		area.rows[area.used] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, -area.y)
	row:SetWidth(area.width)
	row:Show()
	if row.iconButton then row.iconButton:Hide() end
	if row.tier then row.tier:Hide(); row.stars:Hide() end
	for _, cell in ipairs(row.cells) do cell:Hide() end
	row.slot, row.item, row.plan, row.change, row.context, row.comparison = nil, nil, nil, nil, nil, nil
	return row
end

local function Line(area, text, color, inset, labelWidth, minimum)
	local row = Row(area)
	inset = inset or 0
	row.label:ClearAllPoints()
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -2)
	row.label:SetWidth(labelWidth or area.width - inset)
	color = color or TEXT
	row.label:SetTextColor(color[1], color[2], color[3])
	row.label:SetText(text)
	row.height = math.max(minimum or 19, row.label:GetStringHeight() + 4)
	row:SetHeight(row.height)
	area.y = area.y + row.height
	return row
end

local function Cell(area, row, index, text, x, width, align, color, offset)
	local cell = row.cells[index]
	if not cell then
		cell = Font(row, 11, TEXT)
		row.cells[index] = cell
	end
	color = color or TEXT
	offset = offset or 2
	cell:ClearAllPoints()
	cell:SetPoint("TOPLEFT", row, "TOPLEFT", x, -offset)
	cell:SetWidth(width)
	cell:SetJustifyH(align)
	cell:SetTextColor(color[1], color[2], color[3])
	cell:SetText(text)
	cell:Show()
	local height = cell:GetStringHeight() + offset + 2
	if height > row.height then
		area.y = area.y + height - row.height
		row.height = height
		row:SetHeight(height)
	end
end

local function Begin(area)
	area.used, area.y = 0, 0
end

local function Offset(area, requested)
	local value = math.max(0, math.min(requested, area.range))
	if area.bar:GetValue() ~= value then area.bar:SetValue(value) end
	area.scroll:SetVerticalScroll(value)
end

local function Finish(area, reset)
	for i = area.used + 1, table.getn(area.rows) do area.rows[i]:Hide() end
	local extent = math.max(1, area.y + 2)
	if not area.scroll then area.content:SetHeight(extent); return end
	local value = reset and 0 or area.bar:GetValue()
	area.range = math.max(0, extent - area.height)
	area.content:SetHeight(extent)
	area.bar:SetMinMaxValues(0, math.max(1, area.range))
	Offset(area, value)
	if area.range > 0 then area.bar:Show() else area.bar:Hide() end
end

local function ItemRow(area, current, slot, item, original, comparison, plan, change, labelWidth)
	local row = Line(area, L(SLOT[slot]), change and GOLD or TEXT, 26, labelWidth, 25)
	if not row.iconButton then
		row.iconButton = CreateFrame("Button", nil, row)
		row.iconButton:SetWidth(20)
		row.iconButton:SetHeight(20)
		row.iconButton:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
		row.icon = row.iconButton:CreateTexture(nil, "ARTWORK")
		row.icon:SetAllPoints(row.iconButton)
		row.iconButton:SetScript("OnEnter", function() ShowGearTip(row) end)
		row.iconButton:SetScript("OnLeave", function() ClearPreview(row.iconButton) end)
		row.iconButton:EnableMouseWheel(true)
		row.iconButton:SetScript("OnMouseWheel", area.wheel)
	end
	row.slot, row.item, row.context = slot, item, current
	row.comparison, row.plan, row.change = comparison, plan, change
	row.icon:SetTexture(ItemIcon(current.catalog, current.context.class, item, original))
	row.iconButton:Show()
	return row
end

local function SearchFor(current)
	if searches or not current.current.output or not current.actual.sets then return end
	local context, actual, ref = current.context, current.actual, current.reference
	searches = {
		(current.drops or current.current.output <= current.policy.target) and Planner.Search(current.catalog, context, actual, ref, current.drops,
			150000, current.policy),
		Planner.Search(current.catalog, context, actual, ref, nil, 150000, current.policy),
	}
end

local function ReadyPlan(index)
	local plan = searches and searches[index]
	return plan and (not plan.worker or plan.minimumTargetCost == 0) and not plan.error and plan or nil
end

local function SelectedConfiguration(index)
	local plan = ReadyPlan(index)
	if not plan then return end
	local selected = planVariants[index] or "economy"
	if plan.maxGear and selected == "max" then return plan.maxGear, selected end
	return plan.affordable or plan, "economy"
end

local function Compare(current, pieces)
	local context = current.context
	local evaluation = Planner.Evaluate(current.catalog, context.class, pieces)
	if not evaluation then return end
	local changes, quote = Planner.Changes(current.catalog, context.pieces, pieces, current.drops, context.class)
	return { pieces = pieces, evaluation = evaluation, changes = Planner.BySlot(changes), changed = changes[1] ~= nil,
		count = table.getn(changes), quote = quote,
		pressure = Planner.Difficulty(context.demand, evaluation, current.reference) }
end

local function PlanComparison(current, index)
	local configuration = SelectedConfiguration(index)
	if not configuration then return end
	planEffects = planEffects or {}
	if not planEffects[configuration] then
		planEffects[configuration] = Compare(current, configuration.pieces)
	end
	return planEffects[configuration]
end

local function LoadPlan(index)
	if not Read() then return end
	local plan = SelectedConfiguration(index)
	if not plan then return end
	draft, simulation, draftExplicit = Planner.Copy(plan.pieces), nil, true
	showView("simulator")
end

local function PlanningChanged()
	ClearPreview()
	state, searches, planEffects, simulation = nil, nil, nil, nil
	render()
end

local function SaveBaseline()
	local current = Read()
	local saved = current and Planner.Reference(current.context, current.actual)
	if not saved then return end
	if time then saved.at = time() end
	Settings().baselines[saved.class] = saved
	PlanningChanged()
	TraceGear("baseline_saved")
end


local function Menu(row, field, size, options, set, contextMenu)
	local menu = Button(contextMenu and panel or row, "", size, function()
		if menuChoice and menuChoice.anchor == row[field] then CloseMenu(); return end
		local current, slot, anchor = Read(), row.slot, row[field]
		if not current or (contextMenu and not current.context.hub)
			or (not contextMenu and (activeView ~= "simulator" or not slot)) then return end
		local entries = options(row, current)
		if not entries[1] then return end
		local count = table.getn(entries)
		local visible = math.min(count, 12)
		local total = visible * MENU_HEIGHT + 4
		local bottom = anchor:GetBottom() or 0
		local below = bottom - (panel:GetBottom() or 0)
		local above = (panel:GetTop() or 0) - (anchor:GetTop() or 0)
		popup:ClearAllPoints()
		if below < total and above >= below then popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
		else popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
		popup:SetWidth(size)
		popup:SetHeight(total)
		local choice = { anchor = anchor, first = 1 }
		menuChoice = choice
		for i, entry in ipairs(entries) do
			if entry[1] == anchor.value and count > 12 then choice.first = math.min(i, count - 9); break end
		end
		local function Page()
			for i = 1, visible do
				local item = popup.items[i]
				if not item then
					item = Button(popup, "", size)
					item:SetHeight(MENU_HEIGHT)
					item:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -2 - (i - 1) * MENU_HEIGHT)
					popup.items[i] = item
				end
				local position = i + choice.first - (count > 12 and 2 or 1)
				local entry = entries[position]
				local direction = count > 12 and ((i == 1 and -1) or (i == visible and 1))
				local value = entry and entry[1]
				item:SetWidth(size - 4)
				item.text:SetText(direction and T(direction < 0 and "Previous maps" or "More maps") or entry[2])
				Control(item, not direction or (direction < 0 and choice.first > 1)
					or (direction > 0 and choice.first < count - 9), not direction and value == anchor.value)
				item:SetScript("OnClick", function()
					if menuChoice ~= choice or current ~= Read() or slot ~= row.slot then return end
					if direction then
						choice.first = math.max(1, math.min(count - 9, choice.first + 10 * direction))
						Page()
						return
					end
					CloseMenu()
					set(row, value, current)
				end)
				item:Show()
			end
			for i = visible + 1, table.getn(popup.items) do popup.items[i]:Hide() end
		end
		Page()
		if not previewIsNative then ClearPreview() end
		popup:Show()
	end)
	if not contextMenu then
		menu:EnableMouseWheel(true)
		menu:SetScript("OnMouseWheel", equipment.wheel)
	end
	return menu
end

local function EditSlot(row, tier, star)
	local current = Read()
	if not current or not draft or not row.slot then return end
	if tier and not Gear.ValidPiece(current.catalog, current.context.class, row.slot, tier, star) then return end
	local previous = row.item
	if (not previous and not tier) or (previous and previous.tier == tier and previous.stars == star) then return end
	draft, simulation, draftExplicit = Planner.Replace(draft, row.slot, tier, star), nil, true
	drawComparison(current)
end

local function Acquisition(change, plan)
	local quote = change.quote
	local description
	if quote.kind == "farm" then
		description = change.before and (plan and "Higher-quality drop required" or "Replacement drop required")
			or "Fill empty slot through drops"
	elseif quote.kind == "theoretical" then
		description = change.before and "Replacement acquisition unknown" or "Empty slot · acquisition unknown"
	elseif quote.kind == "removed" or quote.kind == "downgrade" then
		description = "No refund modeled"
	else description = "Stars on worn gear" end
	local note = T(description)
	if quote.estimated then note = note .. " · " .. T("Price estimated") end
	if quote.unknown then note = note .. " · " .. T("Additional price unavailable") end
	return note
end

local function PlanEquipment(current, comparison, plan)
	local area, catalog = equipment, current.catalog
	local nameWidth = math.floor(area.width * 0.28)
	local itemWidth = math.floor(area.width * 0.23)
	local costX = nameWidth + itemWidth * 2
	local function Columns(row, actual, target, gold, color)
		Cell(area, row, 1, actual, nameWidth, itemWidth - 6, "LEFT", color)
		Cell(area, row, 2, target, nameWidth + itemWidth, itemWidth - 6, "LEFT", color)
		Cell(area, row, 3, gold, costX, area.width - costX, "RIGHT", color)
	end
	local heading = Line(area, T("Equipment slot"), GOLD, 0, nameWidth - 6)
	Columns(heading, T("Actual"), T("Plan gear"), T("Upgrade gold"), MUTED)
	if (plan.protectedHolds or 0) > 0 then
		Line(area, F("Lower tier retained in %d slots to preserve active set effects.", plan.protectedHolds), MUTED)
	end
	if not comparison.changed then
		Line(area, T(plan.outputPressure <= current.policy.target and "Output target met. No upgrade is needed for this target."
			or "This result keeps the current gear."), MUTED)
	end
	local original, target = Planner.BySlot(current.context.pieces), Planner.BySlot(comparison.pieces)
	for _, slot in ipairs(Planner.Slots(catalog, current.context.class)) do
		local change, after, before = comparison.changes[slot], target[slot], original[slot]
		if change or ((fullPlan or not comparison.changed) and (after or before)) then
			local row = ItemRow(area, current, slot, after, before, comparison, plan, change, nameWidth - 31)
			Columns(row, ItemText(catalog, before), ItemText(catalog, after), change and PriceLabel(change.quote) or "—", TEXT)
			if change then Cell(area, row, 4, Acquisition(change, true), 26, area.width - 26, "LEFT", MUTED, row.height) end
		end
	end
end

local function ExecutionRows(current, comparison, plan)
	local area, context = equipment, current.context
	comparison.execution = comparison.execution or Planner.Execution(current.catalog, context, current.actual,
		plan.pieces, current.reference, current.drops)
	local execution = comparison.execution
	if not execution.preserves then
		Line(area, T("This sequence loses or weakens an active set effect."), GOLD)
	end
	for i, step in ipairs(execution.steps) do
		local label = L(SLOT[step.slot]) .. " · " .. TierText(current.catalog, step.tier)
		if step.kind == "acquire" then
			label = F("Obtain and equip %s (%s)", label, T(step.quote.kind == "farm" and "Drop required" or "Acquisition unknown"))
		else
			label = F("%s · Stars %d to %d in order · %s", label, step.from, step.stars, PriceLabel(step.quote))
			if step.quote.estimated then label = label .. " · " .. T("Price estimated") end
		end
		Line(area, F("%d. %s", i, label), TEXT)
		local cumulative = F("Calculable total %d gold · Output %s", step.cumulative, ShortPercent(step.output))
		if step.unknown then cumulative = cumulative .. " · " .. T("Additional price unavailable") end
		Line(area, cumulative, MUTED, 15)
		for _, transition in ipairs(SetLines(current.catalog, step.beforeSets, step.afterSets)) do
			Line(area, transition, MUTED, 15)
		end
	end
end

local function EquipmentControls(current, slot, simulated, actual, comparison)
	local area = equipment
	local nameWidth, qualityWidth, starWidth = math.floor(area.width * 0.34), 112, 60
	local change = comparison.changes[slot]
	local row = ItemRow(area, current, slot, simulated, actual, comparison, nil, change, nameWidth - 30)
	if not row.tier then
		row.tier = Menu(row, "tier", qualityWidth, function(widget, ctx)
			local options = { { false, T("Empty slot") } }
			for _, key in ipairs(Planner.Tiers(ctx.catalog)) do
				if Gear.ValidPiece(ctx.catalog, ctx.context.class, widget.slot, key, 0) then
					table.insert(options, { key, TierText(ctx.catalog, key) })
				end
			end
			return options
		end, function(widget, tier, ctx)
			local real = Planner.BySlot(ctx.context.pieces)[widget.slot]
			EditSlot(widget, tier, real and real.tier == tier and real.stars or 0)
		end)
		row.stars = Menu(row, "stars", starWidth, function(widget, ctx)
			local options = {}
			if widget.item then
				for star = 0, ctx.catalog.pieces.scale.top do table.insert(options, { star, F("★%d", star) }) end
			end
			return options
		end, function(widget, star)
			if widget.item then EditSlot(widget, widget.item.tier, star) end
		end)
	end
	row.tier:ClearAllPoints()
	row.tier:SetPoint("TOPLEFT", row, "TOPLEFT", nameWidth, 0)
	row.stars:ClearAllPoints()
	row.stars:SetPoint("TOPLEFT", row.tier, "TOPRIGHT", 6, 0)
	row.tier.value = simulated and simulated.tier or false
	row.tier.text:SetText((simulated and TierText(current.catalog, simulated.tier) or T("Empty slot")) .. "  v")
	Control(row.tier, true, change ~= nil)
	row.tier:Show()
	if simulated then
		row.stars.value = simulated.stars
		row.stars.text:SetText(F("★%d", simulated.stars) .. "  v")
		Control(row.stars, true, change ~= nil)
		row.stars:Show()
	end
	if change then
		local actualLabel = F("Worn: %s", ItemText(current.catalog, actual))
		local cost = PriceLabel(change.quote)
		Cell(area, row, 1, F("%s · %s · %s", actualLabel, cost, Acquisition(change)),
			26, area.width - 26, "LEFT", MUTED, row.height)
	end
end

local function StatRow(area, label, actual, simulated, delta, color, heading)
	local nameWidth = math.max(100, math.floor(area.width * 0.31))
	local cellWidth = math.floor((area.width - nameWidth) / 3)
	local row = Line(area, label, heading and GOLD or TEXT, 0, nameWidth - 5)
	Cell(area, row, 1, actual, nameWidth, cellWidth - 4, "RIGHT", MUTED)
	Cell(area, row, 2, simulated, nameWidth + cellWidth, cellWidth - 4, "RIGHT", TEXT)
	Cell(area, row, 3, delta, nameWidth + cellWidth * 2, cellWidth - 4, "RIGHT", color)
end

local function TableHeading(area, title)
	StatRow(area, T(title), T("Actual"), T(activeView == "planner" and "Plan gear" or "Simulated"), T("Change"), GOLD, true)
end

local function EquipmentStats(area, actual, simulated)
	TableHeading(area, "Equipment attributes")
	for _, stat in ipairs(STATS) do
		if stat[4] then Line(area, T(stat[4]), GOLD) end
		local old = actual[stat[1]] or 0
		local new = simulated and (simulated[stat[1]] or 0)
		local unit = stat[3] and 1 or 100
		local valueFormat = stat[3] and "%.2f" or "%.2f%%"
		local delta, color = "—", MUTED
		if new then delta, color = Delta((new - old) * unit, not stat[3]) end
		StatRow(area, L(stat[2]), string.format(valueFormat, old * unit), new and string.format(valueFormat, new * unit) or "—", delta, color)
	end
end

local PRESSURE = { { "output", "Output pressure" }, { "survival", "Survival pressure" } }
local function PressureRows(area, actual, target)
	TableHeading(area, "Pressure")
	for _, metric in ipairs(PRESSURE) do
		local before, after = actual[metric[1]], target and target[metric[1]]
		local delta, color = "—", MUTED
		if before and after then delta, color = Delta(after - before, true, true) end
		StatRow(area, T(metric[2]), before and ShortPercent(before) or "—", after and ShortPercent(after) or "—",
			delta, color, metric[1] == "output")
	end
	Line(area, T("Lower is better. Plans target output. Survival is a theoretical incoming-hit reference."), MUTED)
end

local function ContextLines(area, current, reserved)
	local context = current and current.context
	if not context then Line(area, T("Waiting for the game's world snapshot."), GOLD); return end
	local class = current.catalog and Planner.Class(current.catalog, context.class)
	local location = context.hub and L("Dalaran") or MapTitle(context.zone, context.level, observedZone.zname)
	Line(area, (class and L(class.name) or T("Class unavailable")) .. " · " .. location, GOLD, 0, area.width - reserved, 25)
	local mapTop
	if context.hub then
		mapTop = area.y
		area.y = area.y + 26
		Line(area, T("Theoretical Campaign preview. Map and tier unlocks are unknown."), MUTED)
	end
	if not current.actual then Line(area, T("Current equipment unavailable. Waiting for the game to send equipped items."), MUTED) end
	if current.saved and current.issue ~= "incompatible" then
		local saved = current.saved
		local offset = SurvivorUI_TimeZone and SurvivorUI_TimeZone()
		local captured = type(saved.at) == "number" and date and date("%Y-%m-%d %H:%M", saved.at + (offset or 0))
		if captured and not offset then captured = F("%s UTC", captured) end
		local label = MapTitle(saved.zone, saved.level)
		if saved.origin == "dalaran" then label = label .. " · " .. T("Manual Dalaran reference") end
		if captured then label = label .. " · " .. captured end
		Line(area, F("100%% reference: %s", label))
	elseif current.issue == "incompatible" then
		Line(area, T("The saved baseline uses incompatible game data. Set a new one when ready."), MUTED)
	elseif context.demand and current.issue == "missing" then
		Line(area, T("Set a 100% baseline for this class to compare difficulty."), MUTED)
	end
	if activeView == "planner" and (current.current.output or current.current.survival) then
		Line(area, F("Output pressure %s · Survival pressure %s", Colored(ShortPercent(current.current.output), GOLD),
			ShortPercent(current.current.survival)))
	end
	if current.issue == "updated" then Line(area, T("The saved setup was reevaluated using current model values."), MUTED) end
	local target = context.scope == "standard-only"
	local baseline = current.reference and current.reference.scope == "standard-only"
	if target or baseline then
		local side = target and baseline and "baseline and target" or target and "target" or "baseline"
		Line(area, F("Standard Campaign comparison. Additional difficulty rules are omitted for the %s.", T(side)), MUTED)
	end
	if context.scope == "unsupported" then Line(area, T("Campaign pressure and plans are unavailable in this mode."), MUTED)
	elseif not context.demand and not context.hub then
		Line(area, T("The game has not reported a supported selected Campaign map and difficulty."), MUTED)
	end
	return mapTop
end

local function PlanStatus(plan, selected)
	if selected.outputPressure <= plan.target then
		return plan.minimumTargetCost ~= nil and "Output target met · lowest priced proven" or "Output target met · best found"
	elseif plan.affordable and not plan.affordable.complete then
		return "Budget search incomplete · best found"
	elseif plan.minimumTargetCost and plan.budget and plan.minimumTargetCost > plan.budget then
		return "Target costs more than the planning budget"
	elseif plan.unreachable then return "Output target unreachable in this scope"
	elseif not plan.complete then return "Search budget reached · output reachability unproven"
	elseif plan.excluded and plan.verifiedBestOutputPressure and plan.verifiedBestOutputPressure <= plan.target then
		return "Output target possible · price incomplete"
	elseif plan.unverifiedDrops then return "Output reachability unknown beyond verified drops"
	elseif plan.excluded then return "Output reachability unknown with unpriced gear"
	else return "Output reachability unproven" end
end

local function UpdateCards(current, top)
	local visible = activeView == "planner" and current and current.context.demand
	local width = math.floor((windowWidth - 42) / 2)
	local height = 0
	for index, card in ipairs(planCards) do
		if not visible then card:Hide()
		else
			local plan = searches and searches[index]
			local configuration, variant = SelectedConfiguration(index)
			local comparison = PlanComparison(current, index)
			local caption, status, limits
			if comparison then
				local quote = comparison.quote
				local output = comparison.pressure.output
				caption = F("%s output · %s", Colored(ShortPercent(output),
					PressureColor(current.current.output, output)), PriceLabel(quote))
				if plan.maxGear then
					local name = variant == "max" and "Max Gear reference" or "Economy"
					caption = T(name) .. " · " .. caption
				end
				status = variant == "max" and T("Quality and stars ceiling") or T(PlanStatus(plan, configuration))
				local flags = {}
				if plan.minimumTargetCost and (plan.budget or variant == "max") then
					table.insert(flags, F("Minimum target star gold: %d", plan.minimumTargetCost))
					if plan.budget and plan.minimumTargetCost > plan.budget then
						table.insert(flags, F("Shortfall: %d", plan.minimumTargetCost - plan.budget))
					end
				elseif plan.outputPressure <= plan.target and plan.minimumTargetCost == nil then
					table.insert(flags, F("Target star gold found: %d", plan.gold))
				end
				if plan.budget and variant == "economy" then table.insert(flags, F("Modeled budget left: %d", plan.budget - quote.gold)) end
				if quote.acquisition then table.insert(flags, T("Drops required · gold covers stars")) end
				if quote.estimated then table.insert(flags, T("Price estimated")) end
				if plan.excluded then table.insert(flags, T("Unpriced options excluded")) end
				if plan.unverifiedDrops then table.insert(flags, T("Unverified drops excluded")) end
				if plan.unreachable and variant == "economy" and not plan.budget then table.insert(flags, T("Best priced output")) end
				if plan.affordable and plan.affordable.complete and variant == "economy" and output > plan.target then
					table.insert(flags, T("Best priced output within budget"))
				end
				limits = table.concat(flags, " · ")
			elseif plan and plan.worker then status = T("Searching equipment combinations…")
			elseif plan and plan.error then status = T("Upgrade search unavailable.")
			elseif current.current.output and index == 1 and not current.drops then status = T("Expansion drop data unavailable.")
			elseif not current.actual then status = T("Waiting for equipment")
			elseif not current.reference then status = T("Comparable baseline required")
			else status = T("Comparable output and equipment data are required.") end
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (index - 1) * (width + 10), -top)
			card:SetWidth(width)
			local y = 8
			for i, text in ipairs({ T(index == 1 and "Plan A · Current expansion drops" or "Plan B · Stars only"),
				caption or "", status or "", limits or "" }) do
				local line = card.lines[i]
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -y)
				line:SetWidth(width - 18)
				line:SetText(text)
				if text ~= "" then y = y + line:GetStringHeight() + 3; line:Show() else line:Hide() end
			end
			height = math.max(height, y + 5)
			Control(card, true, index == selectedPlan)
			card:Show()
		end
	end
	if visible then for _, card in ipairs(planCards) do card:SetHeight(height) end end
	return height > 0 and height + 10 or 0
end

local function UpdateVariants(top)
	local plan = activeView == "planner" and ReadyPlan(selectedPlan)
	local comparison = plan and PlanComparison(Read(), selectedPlan)
	local hasExecution = comparison and comparison.changed
	if hasExecution then
		actions.execution:ClearAllPoints()
		actions.execution:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -top)
		actions.execution.text:SetText(T(executionShown and "Show equipment" or "Execution order"))
		Control(actions.execution, true, executionShown)
		actions.execution:Show()
	else
		actions.execution:Hide()
	end
	if not plan or not plan.maxGear then
		for _, button in ipairs(variantButtons) do button:Hide() end
		return hasExecution and 30 or 0
	end
	local _, active = SelectedConfiguration(selectedPlan)
	variantButtons[1]:ClearAllPoints()
	variantButtons[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -top)
	variantButtons[1].text:SetText(T(plan.unreachable and "Max Gear" or "Max Gear reference"))
	for i, button in ipairs(variantButtons) do
		Control(button, true, active == (i == 1 and "max" or "economy"))
		button:Show()
	end
	return 30
end

local function Details(area, current)
	area.y = area.y + 7
	Line(area, T("Calculation model"), GOLD)
	if current.context.demand then
		Line(area, T("Output uses gear Damage. Survival uses class starting HP, gear HP and Damage Reduction capped at 60%."), MUTED)
		Line(area, T("Survival estimates a representative hit against effective health. Movement, skills, talents and special encounter rules can change actual survival."), MUTED)
		Line(area, T("This equipment comparison cannot predict clear or death probabilities."), MUTED)
		Line(area, T("Critical chance and damage, cooldown, Echo, area and special skill effects are shown separately from modeled output."), MUTED)
		Line(area, T("Economy opens first. If the target is out of reach, it minimizes modeled output pressure among priced configurations, then minimizes gold cost. Max Gear shows the known quality and star ceiling with set protection."), MUTED)
		if current.reference and current.context.demand then
			local map, old = current.context.demand, current.reference.demand
			Line(area, F("Map demand vs. baseline · enemy health %s · first boss hit %s",
				ShortPercent(map.output and 100 * map.output / old.output), ShortPercent(map.survival and 100 * map.survival / old.survival)), MUTED)
		end
	end
	Line(area, T("Gold covers stars. Replacement pieces require drops or separate ownership."), MUTED)
	Line(area, T("Some star prices are model estimates."), MUTED)
	Line(area, T("Direct ascension eligibility, price and resulting stars are unavailable."), MUTED)
	if current.drops then
		local maxTier
		for _, tier in ipairs(Planner.Tiers(current.catalog)) do if current.drops[tier] then maxTier = tier end end
		if maxTier then Line(area, F("Highest drop tier in this expansion: %s", TierText(current.catalog, maxTier)), MUTED) end
		Line(area, T("Direct ascension eligibility unavailable. Legendary or higher requires the next expansion's final clear."), MUTED)
	end
end

local function ConfigureActions(current, comparison)
	local planner = activeView == "planner"
	local count = comparison and comparison.count or 0
	if planner and comparison then
		actions.load:Show()
		if count > 0 then
			actions.full.text:SetText(T(fullPlan and "Show changes only" or "Show full equipment"))
			actions.full:Show()
		else actions.full:Hide() end
	else actions.load:Hide(); actions.full:Hide() end
	if not planner and comparison then actions.reset:Show(); Control(actions.reset, comparison.changed)
	else actions.reset:Hide() end
	for i, button in ipairs(actions.plans) do
		if not planner and ReadyPlan(i) then button:Show() else button:Hide() end
	end
	if current and current.actual then actions.details:Show() else actions.details:Hide() end
	actions.details.text:SetText(T(details and "Hide details" or "Show details"))
end

local stacked, bodyTop, leftWidth, rightWidth, rightX
local function LayoutBody()
	local twoRows = (windowWidth < 574 and (actions.plans[1]:IsShown() or actions.plans[2]:IsShown()))
		or (windowWidth < 480 and actions.full:IsShown())
	local bottom = twoRows and 74 or 48
	actions.details:ClearAllPoints()
	actions.details:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, twoRows and 42 or 12)
	local width = windowWidth - 32
	local height = math.max(1, windowHeight - bottom - bodyTop)
	local leftHeight, rightTop = height, bodyTop
	if stacked then
		-- Reserve room for the entire pinned result plus a scrollable detail viewport.
		leftHeight = math.max(36, math.min(math.floor(height * 0.43), height - effectHeader.y - 62))
		rightTop = bodyTop + leftHeight + 12
	end
	effectHeader.content:ClearAllPoints()
	effectHeader.content:SetPoint("TOPLEFT", panel, "TOPLEFT", rightX, -rightTop)
	effectHeader.content:SetWidth(effectHeader.width)
	effectHeader.content:SetHeight(math.max(1, effectHeader.y))

	local function Place(area, x, top, h)
		area.height = math.max(1, h)
		area.scroll:ClearAllPoints()
		area.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -top)
		area.scroll:SetWidth(area.width)
		area.scroll:SetHeight(area.height)
		area.content:SetWidth(area.width)
	end
	local effectsTop = rightTop + effectHeader.y
	Place(equipment, 16, bodyTop, leftHeight)
	Place(effects, rightX, effectsTop, windowHeight - bottom - effectsTop)

	divider:ClearAllPoints()
	if stacked then
		divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -rightTop + 6)
		divider:SetWidth(width)
		divider:SetHeight(1)
	else
		divider:SetPoint("TOPLEFT", panel, "TOPLEFT", rightX - 10, -bodyTop)
		divider:SetWidth(1)
		divider:SetHeight(height)
	end
end

drawComparison = function(current, reset)
	if not previewIsNative then ClearPreview() end
	Begin(equipment)
	Begin(effectHeader)
	Begin(effects)
	detailStart = nil
	local comparison
	if current and current.actual then
		local planner = activeView == "planner"
		if planner then comparison = PlanComparison(current, selectedPlan)
		else
			draft = draft or Planner.Copy(current.context.pieces)
			simulation = simulation or Compare(current, draft)
			comparison = simulation
		end
		if not planner and comparison then
			local actual, target = Planner.BySlot(current.context.pieces), Planner.BySlot(draft)
			Line(equipment, T("Simulated equipment"), GOLD)
			for _, slot in ipairs(Planner.Slots(current.catalog, current.context.class)) do
				EquipmentControls(current, slot, target[slot], actual[slot], comparison)
			end
			local quote = comparison.quote
			Line(effectHeader, F("Calculable upgrade gold: %d", quote.gold), GOLD)
			local flags = {}
			if quote.unknown then table.insert(flags, T("Additional price unavailable")) end
			if quote.acquisition then table.insert(flags, T("Replacement acquisition is conditional")) end
			if quote.estimated then table.insert(flags, T("Price estimated")) end
			if flags[1] then Line(effectHeader, table.concat(flags, " · "), MUTED) end
		elseif planner and comparison then
			local configuration = SelectedConfiguration(selectedPlan)
			if executionShown and comparison.changed then ExecutionRows(current, comparison, configuration)
			else PlanEquipment(current, comparison, configuration) end
		elseif planner and current.current.output and searches and searches[selectedPlan] and searches[selectedPlan].worker then
			Line(equipment, T("Searching equipment combinations…"), MUTED)
		elseif not planner then
			Line(equipment, T("Gear analysis is unavailable for these game data."), MUTED)
		end

		if current.current.output or current.current.survival then
			PressureRows(effectHeader, current.current, comparison and comparison.pressure)
		end
		local evaluation = comparison and comparison.evaluation
		EquipmentStats(effects, current.actual.stats, evaluation and evaluation.stats)
		if evaluation then
			local sets = current.actual.sets and evaluation.sets and SetLines(current.catalog, current.actual.sets, evaluation.sets)
			if sets and sets[1] then
				effects.y = effects.y + 4
				Line(effects, T("Set changes"), GOLD)
				for _, entry in ipairs(sets) do Line(effects, entry) end
			end
			if next(evaluation.opaque) or next(current.actual.opaque) then
				Line(effects, T("Some active set effects have no quantified combat value."), MUTED)
			end
			if evaluation.sets and next(evaluation.sets) then
				Line(effects, T("Active set effects · outside output model"), GOLD)
				for _, tier in ipairs(Planner.Tiers(current.catalog)) do
					for _, bonus in ipairs(evaluation.sets[tier] or {}) do
						Line(effects, F("%s (%d) · %s", TierText(current.catalog, tier), bonus.pieces, SetEffect(bonus)))
					end
				end
			end
			if current.context.demand and (evaluation.stats.armor or 0) > 0.6 then
				Line(effects, T("Damage reduction is capped at 60% in this model."), MUTED)
			end
		end
		if details then detailStart = effects.y; Details(effects, current) end
	end
	Finish(effectHeader)
	ConfigureActions(current, comparison)
	LayoutBody()
	Finish(equipment, reset)
	Finish(effects, reset)
end

render = function()
	if rendering or not panel or not panel:IsShown() then return end
	CloseMenu()
	rendering = true
	local current = Read()
	local hub = current and current.context.hub
	local previous = activeView
	activeView = view
	Control(plannerTab, true, activeView == "planner")
	Control(simulatorTab, true, activeView == "simulator")

	local demand = current and current.context.demand
	local showBaseline = activeView == "planner" and demand
	if showBaseline then
		baselineButton:Show()
		baselineButton.text:SetText(T(current.saved and "Update 100% Baseline" or "Set 100% Baseline"))
		Control(baselineButton, demand.output and current.actual and current.actual.sets and current.actual.output)
	else baselineButton:Hide() end
	Begin(header)
	local mapTop = ContextLines(header, current, showBaseline and 175 or 0)
	if hub then
		hubMap:ClearAllPoints()
		hubMap:SetPoint("TOPLEFT", header.content, "TOPLEFT", 0, -mapTop)
		hubMap.value, hubDifficulty.value = current.context.zone, current.context.level
		hubMap.text:SetText(hubMap.value and MapName(hubMap.value) or T("Select target map"))
		hubDifficulty.text:SetText(hubDifficulty.value and DifficultyName(hubDifficulty.value) or T("Difficulty"))
		Control(hubDifficulty, current.context.zone ~= nil and current.context.zone ~= false)
		hubMap:Show()
		hubDifficulty:Show()
		if AZS_SendCommand then refreshGear:Show() else refreshGear:Hide() end
	else
		hubMap:Hide(); hubDifficulty:Hide(); refreshGear:Hide()
	end
	local showInputs = activeView == "planner" and current ~= nil
	for _, widget in ipairs({ targetBox, budgetBox, protection, resetTarget }) do
		if showInputs then widget:Show() else widget:Hide() end
	end
	if showInputs then
		local policy = current.policy
		for _, box in ipairs({ targetBox, budgetBox }) do
			if not box.editing then box:SetText(tostring(policy[box.key] or "")) end
		end
		local row = Line(header, T("Target output %"), MUTED, 0, 96, 25)
		Cell(header, row, 1, T("Gold budget"), 207, 92, "LEFT", MUTED)
		local function Place(widget, x)
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
		end
		Place(targetBox, 98)
		Place(resetTarget, 156)
		Place(budgetBox, 300)
		local balance = policy.budget and "Automatic gold balance unavailable" or "Automatic gold balance unavailable · budget unset"
		local protectionX = 0
		if header.width >= 820 then
			protectionX = 400
			Cell(header, row, 2, T(balance), 565, header.width - 565, "LEFT", MUTED)
		else row = Line(header, T(balance), MUTED, 165, header.width - 165, 25) end
		Place(protection, protectionX)
		protection.text:SetText(T(policy.protectSets and "Protect sets: On" or "Protect sets: Off"))
		Control(protection, true, policy.protectSets)
		if not policy.protectSets then
			Line(header, T("Plans may sacrifice set effects outside the output model."), GOLD)
		end
		if inputError then Line(header, T(inputError), GOLD) end
	end
	Finish(header)
	baselineButton:ClearAllPoints()
	baselineButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -76)

	if activeView == "planner" and current then SearchFor(current) end
	local top = 76 + header.y + 6
	top = top + UpdateCards(current, top)
	bodyTop = top + UpdateVariants(top)
	drawComparison(current, previous ~= activeView)

	local work = searches and ((searches[1] and searches[1].worker) or (searches[2] and searches[2].worker))
	panel:SetScript("OnUpdate", activeView == "planner" and work and updateSearch or nil)
	rendering = false
end

updateSearch = function()
	if not searches or activeView ~= "planner" or not SurvivorUI_RebornGearEnabled() then
		panel:SetScript("OnUpdate", nil)
		return
	end
	if not Read() then render(); return end
	local start = debugprofilestop and debugprofilestop()
	local function Deadline() return start and debugprofilestop() - start >= 1.25 end
	local finished
	for i = 1, 2 do
		local plan = searches[i]
		if plan and plan.worker and Planner.Step(plan, 240, Deadline) then finished = true end
	end
	if finished then render() end
end

showView = function(target)
	view, activeView = target, nil
	render()
end

local function NewArea(name, scrollable)
	local area = { rows = {}, range = 0 }
	if not scrollable then
		area.content = CreateFrame("Frame", name, panel)
		return area
	end
	local scroll = CreateFrame("ScrollFrame", name, panel)
	area.scroll = scroll
	area.content = CreateFrame("Frame", nil, scroll)
	area.content:SetHeight(1)
	scroll:SetScrollChild(area.content)

	local bar = CreateFrame("Slider", nil, panel)
	area.bar = bar
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:EnableMouse(true)
	bar:SetBackdrop(BORDER)
	bar:SetBackdropColor(0.12, 0.12, 0.15, 1)
	bar:SetBackdropBorderColor(0.29, 0.29, 0.34, 1)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetTexture(FLAT)
	thumb:SetVertexColor(0.75, 0.60, 0.35, 1)
	thumb:SetWidth(8)
	thumb:SetHeight(28)
	bar:SetThumbTexture(thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		CloseMenu()
		if not previewIsNative then ClearPreview() end
		scroll:SetVerticalScroll(math.min(value or arg1, area.range))
	end)
	area.wheel = function(_, delta)
		if area.range > 0 then Offset(area, bar:GetValue() - (delta or arg1) * 44) end
	end
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseDown", CloseMenu)
	scroll:SetScript("OnMouseWheel", area.wheel)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", area.wheel)
	return area
end

local function SizePanel()
	local availableWidth, availableHeight = math.max(1, UIParent:GetWidth() - 32), math.max(1, UIParent:GetHeight() - 32)
	stacked = availableWidth < 812
	local scale = math.min(1, availableWidth / 432, availableHeight / (stacked and 570 or 510))
	windowWidth = math.min(stacked and 760 or 1160, availableWidth / scale)
	windowHeight = math.min(746, availableHeight / scale)
	panel:SetScale(scale)
	panelTip:SetScale(scale)
	panel:SetWidth(windowWidth)
	panel:SetHeight(windowHeight)
	header.width = windowWidth - 32
	header.content:SetWidth(header.width)
	leftWidth = stacked and header.width or math.floor((header.width - 22) * 0.52)
	rightWidth = stacked and header.width or header.width - leftWidth - 22
	rightX = stacked and 16 or 16 + leftWidth + 22
	equipment.width, effectHeader.width, effects.width = leftWidth - 14, rightWidth - 14, rightWidth - 14
end

local function TargetMaps()
	local ordered, seen, extra = {}, {}, {}
	for _, zone in ipairs(AZS_GEN and AZS_GEN.zones or {}) do
		if Maps and Maps[zone.key] and not seen[zone.key] then
			table.insert(ordered, { zone.key, MapName(zone.key) })
			seen[zone.key] = true
		end
	end
	for key in pairs(Maps or {}) do
		if not seen[key] then table.insert(extra, key) end
	end
	table.sort(extra, function(a, b)
		if Maps[a][7] ~= Maps[b][7] then return Maps[a][7] < Maps[b][7] end
		if Maps[a][1] ~= Maps[b][1] then return Maps[a][1] < Maps[b][1] end
		return a < b
	end)
	for _, key in ipairs(extra) do table.insert(ordered, { key, MapName(key) }) end
	return ordered
end

local function NumericInput(key, width, minimum, maximum, integer, errorText)
	local box = CreateFrame("EditBox", nil, header.content)
	box.key = key
	box:SetWidth(width)
	box:SetHeight(23)
	box:SetAutoFocus(false)
	box:SetMaxLetters(12)
	box:SetFont(SurvivorUI_FONT or "Fonts\\FRIZQT__.TTF", 11 + (SurvivorUI_FONT_BUMP or 0))
	box:SetTextInsets(5, 5, 0, 0)
	box:SetBackdrop(BORDER)
	box:SetBackdropColor(0.12, 0.13, 0.16, 1)
	box:SetBackdropBorderColor(0.38, 0.38, 0.43, 1)
	box:SetScript("OnEditFocusGained", function()
		box.editing = true
		inputError = "Press Enter to apply."
		render()
	end)
	box:SetScript("OnEditFocusLost", function()
		box.editing = nil
		inputError = nil
	end)
	box:SetScript("OnEscapePressed", function()
		box:ClearFocus()
		inputError = nil
		render()
	end)
	box:SetScript("OnEnterPressed", function()
		local raw = box:GetText()
		local value = Planner.Input(raw, minimum, maximum, integer)
		if value == nil and not (key == "budget" and string.match(raw, "^%s*$")) then
			inputError = errorText
			render()
			return
		end
		box:ClearFocus()
		inputError = nil
		local config = Settings()
		if Planner.Policy(config)[key] ~= value then
			config[key] = value
			PlanningChanged()
		else render() end
	end)
	return box
end

local function BuildPlanningControls()
	local mapRow = {}
	hubMap = Menu(mapRow, "map", 166, TargetMaps, function(_, key)
		local config = Settings()
		if config.hubMap == key then return end
		config.hubMap = key
		if not SurvivorUI_RebornAnalysisModel.GearDemand(Maps[key], config.hubDifficulty) then config.hubDifficulty = 0 end
		PlanningChanged()
	end, true)
	mapRow.map = hubMap
	hubDifficulty = Menu(mapRow, "difficulty", 89, function(_, current)
		local entries = {}
		local map = Maps[current.context.zone]
		for level = 0, 5 do
			if SurvivorUI_RebornAnalysisModel.GearDemand(map, level) then table.insert(entries, { level, DifficultyName(level) }) end
		end
		return entries
	end, function(_, level)
		if Settings().hubDifficulty == level then return end
		Settings().hubDifficulty = level
		PlanningChanged()
	end, true)
	mapRow.difficulty = hubDifficulty
	refreshGear = Button(panel, "Refresh equipment", 131, function()
		local current = Read()
		if not current or not current.context.hub or not AZS_SendCommand then return end
		worn, associatedArmorOrder, armorDisposition = nil, nil, "waiting_armor"
		PlanningChanged()
		AZS_SendCommand("sync")
	end)
	hubDifficulty:SetPoint("LEFT", hubMap, "RIGHT", 4, 0)
	refreshGear:SetPoint("LEFT", hubDifficulty, "RIGHT", 4, 0)
	targetBox = NumericInput("target", 54, 1, 10000, false, "Enter a target from 1 to 10000, then press Enter.")
	budgetBox = NumericInput("budget", 92, 0, 1000000000, true, "Enter whole gold from 0 to 1000000000, or leave blank. Press Enter.")
	resetTarget = Button(panel, "Reset", 45, function()
		inputError = nil
		targetBox:ClearFocus()
		if Planner.Policy(Settings()).target ~= 100 then
			Settings().target = nil
			PlanningChanged()
		else render() end
	end)
	protection = Button(panel, "Protect sets: On", 154, function()
		Settings().protectSets = not Planner.Policy(Settings()).protectSets
		PlanningChanged()
	end)
end

local function Build()
	shield = CreateFrame("Frame", nil, UIParent)
	shield:Hide()
	shield:SetAllPoints(UIParent)
	shield:SetFrameStrata("FULLSCREEN_DIALOG")
	shield:EnableMouse(true)
	shield:EnableMouseWheel(true)
	shield:SetScript("OnMouseDown", CloseMenu)
	local dim = shield:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints(shield)
	dim:SetTexture(FLAT)
	dim:SetVertexColor(0, 0, 0, 0.42)
	panel = CreateFrame("Frame", "SurvivorUIRebornGearPanel", UIParent)
	panel:Hide()
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(shield:GetFrameLevel() + 10)
	panel:EnableMouse(true)
	panel:SetBackdrop(BORDER)
	panel:SetBackdropColor(0.06, 0.065, 0.08, 1)
	panel:SetBackdropBorderColor(0.65, 0.52, 0.30, 1)
	panel:SetScript("OnMouseDown", CloseMenu)
	local close = Button(panel, "Close", 62, function() panel:Hide() end)
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -12)
	local title = Font(panel, 15, GOLD)
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
	title:SetText(T("Gear & Difficulty"))
	plannerTab = Button(panel, "Difficulty & Upgrade Planner", 200, function()
		if activeView ~= "planner" then showView("planner") end
	end, true)
	plannerTab:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -43)
	simulatorTab = Button(panel, "Equipment Simulator", 145, function()
		if activeView ~= "simulator" then showView("simulator") end
	end, true)
	baselineButton = Button(panel, "Set 100% Baseline", 166, SaveBaseline, true)

	header = NewArea("SurvivorUIRebornGearContext")
	header.content:SetHeight(1)
	header.content:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
	equipment = NewArea("SurvivorUIRebornGearEquipment", true)
	effectHeader = NewArea("SurvivorUIRebornGearResults")
	effects = NewArea("SurvivorUIRebornGearEffects", true)
	BuildPlanningControls()
	divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetTexture(FLAT)
	divider:SetVertexColor(0.42, 0.35, 0.24, 0.75)

	planCards = {}
	for index = 1, 2 do
		local choice = index
		local card = Button(panel, "", 200, function()
			if selectedPlan ~= choice then
				selectedPlan = choice
				Offset(equipment, 0)
				render()
			end
		end)
		card.text:Hide()
		card.lines = { Font(card, 11, GOLD), Font(card, 13, TEXT), Font(card, 11, TEXT), Font(card, 10, MUTED) }
		planCards[index] = card
	end
	variantButtons = {
		Button(panel, "Max Gear", 142, function() planVariants[selectedPlan] = "max"; render() end, true),
		Button(panel, "Economy", 104, function() planVariants[selectedPlan] = "economy"; render() end, true),
	}
	variantButtons[2]:SetPoint("LEFT", variantButtons[1], "RIGHT", 6, 0)

	actions = {}
	actions.execution = Button(panel, "Execution order", 128, function()
		executionShown = not executionShown
		Offset(equipment, 0)
		render()
	end)
	actions.load = Button(panel, "Load in Simulator", 156, function() LoadPlan(selectedPlan) end, true)
	actions.full = Button(panel, "Show full equipment", 144, function() fullPlan = not fullPlan; render() end)
	actions.reset = Button(panel, "Reset to Actual Equipment", 166, function()
		draft, simulation, draftExplicit = nil, nil, nil
		drawComparison(Read())
	end)
	actions.plans = {
		Button(panel, "Load Plan A", 92, function() LoadPlan(1) end),
		Button(panel, "Load Plan B", 92, function() LoadPlan(2) end),
	}
	actions.details = Button(panel, "Show details", 114, function()
		if not details then detailOffset = effects.bar:GetValue() end
		details = not details
		render()
		if details and detailStart then Offset(effects, detailStart)
		elseif not details then Offset(effects, detailOffset or 0) end
	end)
	actions.load:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12)
	actions.full:SetPoint("LEFT", actions.load, "RIGHT", 6, 0)
	actions.reset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12)
	actions.plans[1]:SetPoint("LEFT", actions.reset, "RIGHT", 6, 0)
	actions.plans[2]:SetPoint("LEFT", actions.plans[1], "RIGHT", 6, 0)

	panelTip = CreateFrame("GameTooltip", "SurvivorUIRebornGearTooltip", UIParent, "GameTooltipTemplate")
	panelTip:Hide()
	panelTip:SetFrameStrata("TOOLTIP")
	panelTip:SetClampedToScreen(true)
	panelTip:SetBackdrop(BORDER)
	panelTip:SetBackdropColor(0.06, 0.065, 0.08, 1)
	panelTip:SetBackdropBorderColor(0.65, 0.52, 0.30, 1)

	popup = CreateFrame("Frame", nil, panel)
	popup:Hide()
	popup:EnableMouse(true)
	popup:SetClampedToScreen(true)
	popup:SetFrameLevel(panel:GetFrameLevel() + 40)
	popup:SetBackdrop(BORDER)
	popup:SetBackdropColor(0.07, 0.07, 0.09, 1)
	popup:SetBackdropBorderColor(0.45, 0.40, 0.31, 1)
	popup.items = {}
	-- Frame keyboard focus consumes Escape before the native menu binding.
	-- The client repeats OnKeyDown without OnKeyUp. Wait for its repeat stream
	-- to stop before releasing focus, as the native card picker does for taps.
	local timer = CreateFrame("Frame", nil, panel)
	local escapeAt, escapeMenu
	local function FinishEscape()
		if GetTime() - escapeAt < 0.12 then return end
		local choice = escapeMenu
		escapeAt, escapeMenu = nil, nil
		timer:SetScript("OnUpdate", nil)
		if choice then
			if choice == menuChoice then CloseMenu() end
		elseif not menuChoice then panel:Hide() end
	end
	panel:SetScript("OnKeyDown", function(_, key)
		if (key or arg1) ~= "ESCAPE" then return end
		if not escapeAt then
			escapeMenu = menuChoice
			timer:SetScript("OnUpdate", FinishEscape)
		end
		escapeAt = GetTime()
	end)
	panel:SetScript("OnEvent", function()
		SizePanel()
		render()
	end)
	panel:SetScript("OnHide", function()
		escapeAt, escapeMenu = nil, nil
		timer:SetScript("OnUpdate", nil)
		panel:EnableKeyboard(false)
		panel:UnregisterEvent("UI_SCALE_CHANGED")
		panel:UnregisterEvent("DISPLAY_SIZE_CHANGED")
		shield:Hide()
		CloseMenu()
		targetBox:ClearFocus()
		budgetBox:ClearFocus()
		inputError = nil
		if not previewIsNative then ClearPreview() end
		panel:SetScript("OnUpdate", nil)
		if searches and ((searches[1] and searches[1].worker) or (searches[2] and searches[2].worker)) then
			searches, planEffects = nil, nil
		end
	end)
end

function SurvivorUI_RebornGearOpen(argument)
	if not SurvivorUI_RebornGearEnabled() then return end
	if argument == "off" then if panel then panel:Hide() end; return end
	if not SurvivorUI_GoldButton then return end
	if not panel then Build() end
	if panel:IsShown() and argument ~= "show" and argument ~= "worn" and argument ~= "simulator" then
		panel:Hide()
		return
	end
	SizePanel()
	if GameMenuFrame and GameMenuFrame:IsShown() then shield:Show() end
	panel:Show()
	panel:EnableKeyboard(true)
	panel:RegisterEvent("UI_SCALE_CHANGED")
	panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
	showView(argument == "simulator" and "simulator" or "planner")
	TraceGear("open")
	RequestDiagnosticSync(true)
	return true
end

local function WorldChanged(reason)
	observedZone = nil
	InvalidateGear()
	selectedPlan, fullPlan, details, detailOffset, executionShown = 1, nil, nil, nil, nil
	if reason == "world_enter" then
		worldEpoch, worldOrder = worldEpoch + 1, NoteObservation()
		diagnosticZoneWireSeen = nil
	end
	TraceGear(reason, nil, reason)
	if panel then panel:Hide() end
end

local registered
local function InstallListeners()
	if not SurvivorUI_RebornGearEnabled() or registered or not (AZS and type(AZS.On) == "function") then return end
	registered = true
	AZS.On("AZSZONE", function(msg)
		if not SurvivorUI_RebornGearEnabled() then return end
		local snapshot = Snapshot(AZS_ZONE)
		local changed = not SameZone(observedZone, snapshot)
		if changed then
			InvalidateGear()
		end
		zoneOrder = NoteObservation()
		observedZone = snapshot
		InstallInspectHook()
		if changed then render() end
		TraceGear("AZSZONE", msg, changed and "zone_changed" or nil)
	end)
	AZS.On("AZSARMOR", function()
		if not SurvivorUI_RebornGearEnabled() then return end
		armorOrder = NoteObservation()
		if not observedZone then
			armorDisposition = "armor_before_zone"
			TraceGear("AZSARMOR")
			return
		end
		if not SameZone(observedZone, Snapshot(AZS_ZONE)) then
			observedZone = nil
			InvalidateGear()
			armorDisposition = "armor_context_mismatch"
			render()
			TraceGear("AZSARMOR", nil, "native_context_changed")
			return
		end
		-- The armor wire has no run ID. Only accept it after the current zone
		-- boundary, and never attach an earlier cached armor table at entry.
		local pieces = Gear.Worn(Gear.Catalog(AZS_GEN), observedZone.class, AZS_ARMOR)
		associatedArmorOrder = pieces and armorOrder or nil
		armorDisposition = pieces and "associated" or "armor_rejected"
		if not PieceListsEqual(worn, pieces) then
			worn = pieces
			ClearState(true)
			render()
		end
		InstallInspectHook()
		TraceGear("AZSARMOR")
	end)
	AZS.On("AZSHELLO", function()
		if state and SurvivorUI_RebornGearEnabled() then state.context.build = AZS.ServerBuild end
	end)
end

local lifecycle = CreateFrame("Frame")
lifecycle:SetScript("OnEvent", function(_, name)
	name = name or event
	if name == "PLAYER_ENTERING_WORLD" then WorldChanged("world_enter") end
	InstallListeners()
	if name == "PLAYER_LOGIN" then
		lifecycle:UnregisterEvent("PLAYER_LOGIN")
		if SurvivorUI_RebornGearEnabled() then lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD") end
	end
end)
if SurvivorUI_RebornGearEnabled() then
	lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
	InstallListeners()
	InstallInspectHook()
end
lifecycle:RegisterEvent("PLAYER_LOGIN")

function SurvivorUI_RebornGearToggle()
	local enabled = SurvivorUI_RebornGearEnabled()
	Settings().enabled = not enabled
	if enabled then
		lifecycle:UnregisterEvent("PLAYER_ENTERING_WORLD")
		WorldChanged("feature_disabled")
		InspectUpdated()
	else
		lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
		InstallListeners()
		InstallInspectHook()
		if AZS_SendCommand then AZS_SendCommand("sync") end
	end
end
