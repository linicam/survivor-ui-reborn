-- Dalaran and Campaign equipment snapshots, planner and simulator.
if SurvivorUI_Standby or not SurvivorUI_RebornGearPlanner then return end

local Gear, Planner = SurvivorUI_RebornGearModel, SurvivorUI_RebornGearPlanner
local Maps = SurvivorUI_RebornMapReference
local WIDTH = 686
local panel, scroll, content, plannerTab, simulatorTab, baselineButton, loadButtons
local view, rows, used, y = "planner", {}, 0, 0
local observedZone, worn, state, draft, searches, rendering
local previewOwner, previewIsNative
local observationOrder, worldEpoch = 0, 0
local worldOrder, zoneOrder, armorOrder, associatedArmorOrder
local armorDisposition = "waiting_armor"
local diagnosticSyncRequested, diagnosticZoneWireSeen
local render, updateSearch, showView
local ROMAN = { "I", "II", "III", "IV", "V" }
local SLOT = { head = "Head", shoulders = "Shoulders", chest = "Chest", waist = "Waist", legs = "Legs",
	feet = "Feet", wrists = "Wrists", hands = "Hands", main_hand = "Main Hand", off_hand = "Off Hand", ranged = "Ranged" }
local TIER = { common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", pvp = "PvP",
	legendary = "Legendary", exotic = "Exotic", mythic = "Mythic", elementium = "Elementium" }
local STATS = {
	{ "damage", "Damage" }, { "crit", "Critical strike" }, { "crit_damage", "Critical damage" },
	{ "cooldown", "Cooldown reduction" }, { "area", "Area of effect" }, { "hp", "Health", true },
	{ "armor", "Damage reduction" }, { "regen", "Health per second", true }, { "speed", "Movement speed" },
	{ "pickup", "Pickup range" }, { "gold", "Gold find" }, { "echo", "Echo" },
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

local function MapTitle(key, level, live)
	if type(key) ~= "string" or type(level) ~= "number" then return T("Selected map or difficulty unavailable") end
	local name = live
	for _, zone in ipairs(AZS_GEN and AZS_GEN.zones or {}) do
		if zone.key == key then name = L(zone.name); break end
	end
	return (name or key) .. " · " .. (level == 0 and T("Normal") or F("Heroic %s", ROMAN[level] or tostring(level)))
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
	local previous = previewOwner
	previewOwner, previewIsNative = nil, nil
	if GameTooltip and GameTooltip:IsOwned(previous) then GameTooltip:Hide() end
end

local function PieceListsEqual(a, b)
	if not a or not b or table.getn(a) ~= table.getn(b) then return false end
	for i, piece in ipairs(a) do
		if not Planner.SamePiece(piece, b[i]) or piece.observed ~= b[i].observed or piece.icon ~= b[i].icon
			or piece.name ~= b[i].name or piece.set ~= b[i].set then return false end
	end
	return true
end

local function ClearState()
	ClearPreview()
	state, draft, searches = nil, nil, nil
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
	local class, level = zone.class, zone.dt
	local heroic = tonumber(zone.heroic)
	local modifiers = { aff = zone.aff, affixes = zone.affixes, challenge = zone.challenge, mode = zone.mode }
	local scope = Planner.Scope(level, modifiers)
	local demand
	local mapStatus, difficultyStatus = ResolveSelection(zone)
	local selected = mapStatus == "ready" and difficultyStatus == "ready"
	if selected and scope ~= "unsupported" then
		demand = SurvivorUI_RebornAnalysisModel.GearDemand(Maps[zone.zone], level)
	end
	local context = { class = class, zone = selected and zone.zone, level = selected and level, heroic = heroic, scope = scope,
		modifiers = modifiers, build = AZS and AZS.ServerBuild, demand = demand,
		pieces = worn, at = time and time() }
	local actual = worn and catalog and class and Planner.Evaluate(catalog, class, worn)
	local saved = class and Settings().baselines[class]
	local reference, issue
	if catalog and class and Maps then reference, issue = Planner.CheckReference(saved, context, catalog, Maps) end
	local evaluated = { catalog = catalog, context = context, actual = actual, reference = reference, saved = saved,
		issue = issue, current = Planner.Difficulty(demand, actual, reference) }
	local map = Maps and Maps[context.zone]
	evaluated.drops = catalog and map and scope ~= "unsupported" and Planner.DropTiers(catalog, Maps, map[7])
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
	elseif map ~= "ready" then pressure = map
	elseif difficulty ~= "ready" then pressure = difficulty
	elseif context.scope == "unsupported" then pressure = "unsupported_mode"
	elseif not context.demand then pressure = "demand_unavailable"
	elseif not current.actual then pressure = equipment
	elseif not current.reference then pressure = "baseline_" .. baseline
	elseif not current.current.combined then pressure = "partial_pressure"
	else pressure = "ready" end

	local demand = context and context.demand
	local plans = pressure
	if pressure == "ready" and not current.actual.sets then plans = "sets_unavailable" end
	SurvivorUI_RebornRecordGearState({
		trigger = trigger, worldEpoch = worldEpoch, invalidation = invalidation,
		ordering = { world = worldOrder, zone = zoneOrder, armor = armorOrder, associatedArmor = associatedArmorOrder },
		catalog = { native = type(AZS_GEN) == "table", maps = type(Maps) == "table",
			equipment = current and current.catalog ~= nil or false },
		resolution = { enabled = enabled, map = map, difficulty = difficulty, scope = context and context.scope,
			equipment = equipment, armorDisposition = armorDisposition, armorAssociated = associatedArmorOrder ~= nil,
			acceptedArmorCount = associatedArmorOrder and table.getn(worn) or nil,
			baseline = baseline, pressure = pressure,
			planA = plans == "ready" and not current.drops and "drop_scope_unavailable" or plans, planB = plans,
			saveBaseline = demand and demand.output ~= nil and demand.survival ~= nil
				and current.actual ~= nil and current.actual.sets ~= nil and current.actual.survival ~= nil or false },
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

local function DifficultyLine(result)
	return F("Estimated difficulty %s   ·   Output %s   ·   Survival %s",
		ShortPercent(result.combined), ShortPercent(result.output), ShortPercent(result.survival))
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

local function AttributeLines(before, after)
	local out = {}
	for _, stat in ipairs(STATS) do
		local old = before[stat[1]] or 0
		local new = after[stat[1]] or 0
		local delta = new - old
		if math.abs(delta) > Planner.tolerance then
			table.insert(out, stat[3] and F("%s %+.2f", L(stat[2]), delta) or F("%s %+.2f pp", L(stat[2]), delta * 100))
		end
	end
	return out
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
				local effect = string.gsub(L(bonus.template), "{(%w+)}", function(key) return bonus.values[key] or "?" end)
				table.insert(out, F("%s · %s (%d) · %s", T(status), TierText(catalog, tier), n, effect))
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

local function PreviewChange(current, pieces, base, before, after, caption, isolated)
	local catalog, context = current.catalog, current.context
	local slot = after and after.slot or before.slot
	local setup = Planner.Replace(pieces, slot, after and after.tier, after and after.stars)
	local evaluated = Planner.Evaluate(catalog, context.class, setup)
	if not evaluated then return end
	local quote = Planner.Quote(catalog, before, after, current.drops, context.class)
	GameTooltip:AddLine(caption, 1, 0.82, 0.22, true)
	local cost = QuoteText(quote)
	GameTooltip:AddLine(quote.estimated and F("%s (estimated price)", cost) or cost, 1, 1, 1, true)
	for _, change in ipairs(AttributeLines(base.stats, evaluated.stats)) do GameTooltip:AddLine(change, 0.55, 1, 0.65) end
	if base.sets and evaluated.sets then
		for _, change in ipairs(SetLines(catalog, base.sets, evaluated.sets)) do GameTooltip:AddLine(change, 1, 1, 1, true) end
	end
	local from = Planner.Difficulty(context.demand, base, current.reference).combined
	local to = Planner.Difficulty(context.demand, evaluated, current.reference).combined
	if from and to then
		GameTooltip:AddLine(F(isolated and "Isolated item pressure %s → %s" or "Modeled pressure %s → %s",
			ShortPercent(from), ShortPercent(to)), 1, 1, 1, true)
	end
	return quote
end

local function AddPreview(current, pieces, evaluated, item)
	if not item then GameTooltip:AddLine(T("Empty slot")); return end
	local catalog, context = current.catalog, current.context
	local function Show(tier, star, caption)
		local quote = PreviewChange(current, pieces, evaluated, item, { slot = item.slot, tier = tier, stars = star }, caption)
		if quote and tier ~= item.tier then
			GameTooltip:AddLine(T(quote.progression and "Direct ascension requires clearing the next expansion's final map; eligibility unknown."
				or "Direct ascension eligibility, price and resulting stars are unavailable."), 0.9, 0.82, 0.65, true)
		end
	end
	GameTooltip:AddLine(" ")
	if Gear.ValidPiece(catalog, context.class, item.slot, item.tier, item.stars + 1) then
		Show(item.tier, item.stars + 1, F("Next star · ★%d → ★%d", item.stars, item.stars + 1))
	else
		GameTooltip:AddLine(T("At maximum stars"), 0.85, 0.85, 0.85)
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
		GameTooltip:AddLine(T("At maximum tier"), 0.85, 0.85, 0.85)
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
		previewOwner, previewIsNative = owner, true
		AddPreview(current, current.context.pieces, current.actual, item)
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

local function Button(parent, caption, width, action)
	local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	widget:SetWidth(width)
	widget:SetHeight(24)
	widget:SetText(T(caption))
	widget:SetScript("OnClick", action)
	return widget
end

local function Row()
	used = used + 1
	local row = rows[used]
	if not row then
		row = CreateFrame("Frame", nil, content)
		row:SetWidth(WIDTH - 54)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetJustifyH("LEFT")
		row.iconButton = CreateFrame("Button", nil, row)
		row.iconButton:SetWidth(22)
		row.iconButton:SetHeight(22)
		row.iconButton:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
		row.icon = row.iconButton:CreateTexture(nil, "ARTWORK")
		row.icon:SetAllPoints(row.iconButton)
		row.iconButton:SetScript("OnEnter", function()
			local current = Read()
			if not row.slot or not current or not GameTooltip then return end
			GameTooltip:SetOwner(row.iconButton, "ANCHOR_RIGHT")
			GameTooltip:SetText(L(SLOT[row.slot] or row.slot))
			previewOwner, previewIsNative = row.iconButton, nil
			if row.plan then
				local change = row.change
				PreviewChange(current, current.context.pieces, current.actual, change.before, change.after,
					F("Planned item %s → %s", ItemText(current.catalog, change.before), ItemText(current.catalog, change.after)), true)
				GameTooltip:AddLine(F("Full plan modeled pressure %s", ShortPercent(row.plan.after)), 1, 0.82, 0.22, true)
			elseif row.simulated then
				local evaluated = Planner.Evaluate(current.catalog, current.context.class, draft)
				if evaluated then
					GameTooltip:AddLine(F("Simulated item · %s", ItemText(current.catalog, row.item)), 1, 0.82, 0.22, true)
					if row.item then
						GameTooltip:AddLine(T("Preview costs start from this simulated item."), 1, 1, 1, true)
						AddPreview(current, draft, evaluated, row.item)
					end
				end
			end
			GameTooltip:Show()
		end)
		row.iconButton:SetScript("OnLeave", function() ClearPreview(row.iconButton) end)
		rows[used] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetHeight(24)
	row:Show()
	row.iconButton:Hide()
	if row.tier then row.tier:Hide(); row.stars:Hide() end
	if row.action then row.action:Hide() end
	row.slot, row.item, row.simulated, row.plan, row.change = nil, nil, nil, nil, nil
	return row
end

local function Line(text, header, icon, slot, reserve)
	local row = Row()
	row.slot = slot
	local inset = icon and 30 or 0
	row.label:ClearAllPoints()
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -3)
	row.label:SetWidth(WIDTH - 60 - inset - (reserve or 0))
	row.label:SetTextColor(header and 1 or 0.92, header and 0.82 or 0.94, header and 0.22 or 0.98)
	row.label:SetText(text)
	if icon then row.icon:SetTexture(icon); row.iconButton:Show() end
	local height = row.label.GetStringHeight and row.label:GetStringHeight() or 15
	height = math.max(height + 9, 24)
	row:SetHeight(height)
	y = y + height
	return row
end

local function Gap() y = y + 9 end

local function ChangeRows(current, changes, plan)
	for _, row in ipairs(changes) do
		local cat = current.catalog
		local widget = Line(F("%s · %s → %s · %s", L(SLOT[row.slot]), ItemText(cat, row.before), ItemText(cat, row.after), QuoteText(row.quote)),
			false, ItemIcon(cat, current.context.class, row.after, row.before), row.slot)
		widget.plan, widget.change, widget.simulated, widget.item = plan, row, not plan, row.after
	end
end

local function SearchFor(current)
	if searches or not current.current.combined or not current.actual.sets then return end
	local context, actual, ref = current.context, current.actual, current.reference
	searches = {
		current.drops and Planner.Search(current.catalog, context, actual, ref, current.drops, 150000),
		Planner.Search(current.catalog, context, actual, ref, nil, 150000),
	}
end

local function LoadPlan(index)
	if not Read() then return end
	local selected = searches and searches[index]
	if not selected or selected.worker or selected.error then return end
	draft = Planner.Copy(selected.pieces)
	showView("simulator")
end

local function OutputPlan(current, index)
	local title = index == 1 and "Plan A · Current expansion drops" or "Plan B · Stars only"
	local plan = searches and searches[index]
	local head = Line(T(title), true, nil, nil, 165)
	if not plan then
		Line(T(current.current.combined and "Expansion drop data unavailable." or "A comparable baseline and both pressures are required."))
		return
	end
	if not head.action then
		head.action = Button(head, "Load in Simulator", 165)
		head.action:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, 0)
	end
	if plan.worker then
		Line(T("Searching equipment combinations…"))
		return
	end
	if plan.error then Line(T("Upgrade search unavailable.")); return end
	head.action:SetText(T("Load in Simulator"))
	head.action:SetScript("OnClick", function() LoadPlan(index) end)
	head.action:Show()
	local rows, quote = Planner.Changes(current.catalog, current.context.pieces, plan.pieces, current.drops, current.context.class)
	Line(F("Modeled pressure %s → %s · %d gold in upgrades", ShortPercent(current.current.combined), ShortPercent(plan.after), quote.gold))
	if current.current.combined <= 100 then
		Line(T("At or below 100%. No upgrades required."))
		return
	end
	local status
	if plan.after <= 100 then
		status = plan.complete and "Target met · minimum among comparable priced options" or "Target met · best found within the search budget"
	elseif plan.complete and plan.excluded then
		status = "No priced option reaches 100%. Reachability with unpriced options is unknown."
	else
		status = plan.complete and "Target above 100% with these constraints · best achievable" or "Best found within the search budget · reachability unproven"
	end
	Line(T(status))
	if quote.acquisition then Line(T("Gold covers stars. Replacement pieces require drops or separate ownership.")) end
	if index == 1 then
		local maxTier
		for _, tier in ipairs(Planner.Tiers(current.catalog)) do
			if current.drops[tier] then maxTier = tier end
		end
		if maxTier then Line(F("Highest drop tier in this expansion: %s", TierText(current.catalog, maxTier))) end
		Line(T("Direct ascension eligibility unavailable. Legendary or higher requires the next expansion's final clear."))
	end
	if quote.estimated then Line(T("Some star prices are model estimates.")) end
	if plan.excluded then Line(T("Options with unavailable upgrade gold were excluded.")) end
	if next(current.actual.opaque) then Line(T("Preserves active set effects whose combat value is unknown.")) end
	ChangeRows(current, rows, plan)
end

local function SaveBaseline()
	local current = Read()
	local saved = current and Planner.Reference(current.context, current.actual)
	if not saved then return end
	if time then saved.at = time() end
	Settings().baselines[saved.class] = saved
	ClearPreview()
	state, searches = nil, nil
	render()
	TraceGear("baseline_saved")
end

local function ContextLines(current)
	local context = current and current.context
	if not context then Line(T("Waiting for the game's world snapshot."), true); return end
	local class = current.catalog and Planner.Class(current.catalog, context.class)
	Line((class and L(class.name) or T("Class unavailable")) .. " · "
		.. MapTitle(context.zone, context.level, observedZone.zname), true)
	if not current.actual then Line(T("Current equipment unavailable. Waiting for the game to send equipped items.")) end
	if type(current.saved) == "table" then
		local saved = current.saved
		local offset = SurvivorUI_TimeZone and SurvivorUI_TimeZone()
		local captured = type(saved.at) == "number" and date and date("%Y-%m-%d %H:%M", saved.at + (offset or 0))
		if captured and not offset then captured = F("%s UTC", captured) end
		local label = MapTitle(saved.zone, saved.level)
		if captured then label = label .. " · " .. captured end
		Line(F("100%% reference: %s", label))
	elseif current.issue == "missing" then
		Line(T("Set a 100% baseline for this class to compare difficulty."))
	end
	if current.issue == "incompatible" then Line(T("The saved baseline uses incompatible game data. Set a new one when ready.")) end
	if current.issue == "updated" then Line(T("The saved setup was reevaluated using current model values.")) end
	local target = context.scope == "standard-only"
	local baseline = current.reference and current.reference.scope == "standard-only"
	if target or baseline then
		local side = target and baseline and "baseline and target" or target and "target" or "baseline"
		Line(F("Standard Campaign comparison. Additional difficulty rules are omitted for the %s.", T(side)))
	end
	if context.scope == "unsupported" then Line(T("Campaign pressure and plans are unavailable in this mode.")) end
end

local function PlannerView(current)
	if not current then return end
	Line(DifficultyLine(current.current), true)
	if not current.context.demand and current.context.scope ~= "unsupported" then
		Line(T("The game has not reported a supported selected Campaign map and difficulty."))
	end
	if current.actual and not current.actual.survival then Line(T("Survival estimate unavailable for this class data.")) end
	if current.reference and current.context.demand then
		local map = current.context.demand
		local old = current.reference.demand
		Line(F("Map demand vs. baseline · enemy health %s · first boss hit %s",
			ShortPercent(map.output and 100 * map.output / old.output), ShortPercent(map.survival and 100 * map.survival / old.survival)))
	end
	if current.context.demand then
		Line(T("Output uses gear Damage. Survival uses class starting HP, gear HP and Damage Reduction capped at 60%."))
		Line(T("Plans optimize modeled pressure. Gameplay calibration is pending. Critical chance and damage, cooldown, Echo, recovery, movement, area, talents, summons, density and encounter rules such as Rifts and Endless are excluded."))
	end
	Gap()
	SearchFor(current)
	OutputPlan(current, 1)
	Gap()
	OutputPlan(current, 2)
end

local function Menu(row, field, width, offset, options, set)
	local menu = CreateFrame("Frame", "SurvivorUIRebornGearMenu" .. used .. field, row, "UIDropDownMenuTemplate")
	menu:SetPoint("TOPLEFT", row, "TOPLEFT", offset, 3)
	UIDropDownMenu_SetWidth(menu, width)
	UIDropDownMenu_Initialize(menu, function()
		local context, slot = Read(), row.slot
		if not context or not slot then return end
		for _, entry in ipairs(options(row)) do
			local value = entry[1]
			local info = UIDropDownMenu_CreateInfo()
			info.value, info.text = value, entry[2]
			info.func = function()
				if view == "simulator" and context == Read() and slot == row.slot then set(row, value) end
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	return menu
end

local function EditSlot(row, tier, star)
	local current = Read()
	if not current or not draft or not row.slot then return end
	if tier and not Gear.ValidPiece(current.catalog, current.context.class, row.slot, tier, star) then return end
	draft = Planner.Replace(draft, row.slot, tier, star)
	render()
end

local function EquipmentControls(current, slot, simulated, actual)
	local row = Line(L(SLOT[slot]), false, ItemIcon(current.catalog, current.context.class, simulated, actual), slot, 260)
	row.item, row.simulated = simulated, true
	if not row.tier then
		row.tier = Menu(row, "tier", 130, 222, function(widget)
			local ctx = Read()
			local options = { { false, T("Empty slot") } }
			for _, key in ipairs(Planner.Tiers(ctx.catalog)) do
				if Gear.ValidPiece(ctx.catalog, ctx.context.class, widget.slot, key, 0) then
					table.insert(options, { key, TierText(ctx.catalog, key) })
				end
			end
			return options
		end, function(widget, tier)
			local real = Planner.BySlot(Read().context.pieces)[widget.slot]
			EditSlot(widget, tier, real and real.tier == tier and real.stars or 0)
		end)
		row.stars = Menu(row, "stars", 64, 406, function(widget)
			local options = {}
			if widget.item then
				for star = 0, Read().catalog.pieces.scale.top do table.insert(options, { star, F("★%d", star) }) end
			end
			return options
		end, function(widget, star)
			if widget.item then EditSlot(widget, widget.item.tier, star) end
		end)
	end
	UIDropDownMenu_SetSelectedValue(row.tier, simulated and simulated.tier or false)
	UIDropDownMenu_SetText(row.tier, simulated and TierText(current.catalog, simulated.tier) or T("Empty slot"))
	row.tier:Show()
	if simulated then
		UIDropDownMenu_SetSelectedValue(row.stars, simulated.stars)
		UIDropDownMenu_SetText(row.stars, F("★%d", simulated.stars))
		row.stars:Show()
	end
end

local function SimulatorView(current)
	if not current or not current.actual then return end
	local context, catalog = current.context, current.catalog
	draft = draft or Planner.Copy(context.pieces)
	local evaluation = Planner.Evaluate(catalog, context.class, draft)
	if not evaluation then Line(T("Gear analysis is unavailable for these game data.")); return end
	local simulated = Planner.Difficulty(context.demand, evaluation, current.reference)
	Line(DifficultyLine(simulated), true)
	if simulated.combined and current.current.combined then
		Line(F("Compared with actual gear · difficulty %+.2f pp · output %+.2f pp · survival %+.2f pp",
			simulated.combined - current.current.combined, simulated.output - current.current.output,
			simulated.survival - current.current.survival))
	end
	local changes, quote = Planner.Changes(catalog, context.pieces, draft, current.drops, context.class)
	Line(F("Calculable upgrade gold: %d", quote.gold))
	if quote.unknown then Line(T("Some upgrade prices are unavailable.")) end
	if quote.acquisition then Line(T("Replacement gear is hypothetical. Ownership and direct ascension are unavailable here.")) end
	local totals = AttributeLines({}, evaluation.stats)
	if totals[1] then Line(F("Equipment totals · %s", table.concat(totals, "  ·  "))) end
	if (evaluation.stats.armor or 0) > 0.6 then Line(T("Damage reduction is capped at 60% in this model.")) end
	local attrs = AttributeLines(current.actual.stats, evaluation.stats)
	if attrs[1] then Line(table.concat(attrs, "  ·  ")) end
	if current.actual.sets and evaluation.sets then
		for _, entry in ipairs(SetLines(catalog, current.actual.sets, evaluation.sets)) do Line(entry) end
	end
	if next(evaluation.opaque) then Line(T("Some active set effects have no quantified combat value.")) end
	local header = Line(T("Simulated equipment"), true, nil, nil, 165)
	if not header.action then
		header.action = Button(header, "Reset to Actual Equipment", 165)
		header.action:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
	end
	header.action:SetText(T("Reset to Actual Equipment"))
	header.action:SetScript("OnClick", function() draft = nil; render() end)
	header.action:Show()
	local previous, wanted = Planner.BySlot(context.pieces), Planner.BySlot(draft)
	if UIDropDownMenu_Initialize then
		for _, slot in ipairs(Planner.Slots(catalog, context.class)) do
			EquipmentControls(current, slot, wanted[slot], previous[slot])
		end
	end
	if changes[1] then
		Gap()
		Line(T("Changes and acquisition"), true)
		ChangeRows(current, changes)
	end
end

render = function()
	if rendering or not panel or not panel:IsShown() then return end
	if not previewIsNative then ClearPreview() end
	rendering, used, y = true, 0, 0
	local current = Read()
	ContextLines(current)
	if view == "planner" then PlannerView(current) else SimulatorView(current) end
	for i = used + 1, table.getn(rows) do rows[i]:Hide() end
	content:SetHeight(math.max(1, y + 4))
	if baselineButton then
		if view == "planner" then
			baselineButton:Show()
			local demand = current and current.context.demand
			if demand and demand.output and demand.survival and current.actual and current.actual.sets and current.actual.survival then
				baselineButton:Enable()
			else baselineButton:Disable() end
		else baselineButton:Hide() end
	end
	for i, button in ipairs(loadButtons) do
		if view == "simulator" then
			button:Show()
			local plan = searches and searches[i]
			if plan and not plan.worker and not plan.error then button:Enable() else button:Disable() end
		else button:Hide() end
	end
	local work = searches and ((searches[1] and searches[1].worker) or (searches[2] and searches[2].worker))
	panel:SetScript("OnUpdate", view == "planner" and work and updateSearch or nil)
	rendering = false
end

updateSearch = function()
	if not searches or view ~= "planner" or not SurvivorUI_RebornGearEnabled() then
		panel:SetScript("OnUpdate", nil)
		return
	end
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
	view = target
	if target == "planner" then plannerTab:Disable(); simulatorTab:Enable()
	else plannerTab:Enable(); simulatorTab:Disable() end
	scroll:SetVerticalScroll(0)
	render()
end

local function Build()
	panel = CreateFrame("Frame", "SurvivorUIRebornGearPanel", UIParent)
	panel:Hide()
	panel:SetWidth(WIDTH)
	panel:SetHeight(530)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
	panel:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
	if UISpecialFrames then table.insert(UISpecialFrames, "SurvivorUIRebornGearPanel") end
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
	title:SetText(T("Gear & Difficulty"))
	plannerTab = Button(panel, "Difficulty & Upgrade Planner", 210, function() showView("planner") end)
	plannerTab:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42)
	simulatorTab = Button(panel, "Equipment Simulator", 163, function() showView("simulator") end)
	simulatorTab:SetPoint("LEFT", plannerTab, "RIGHT", 6, 0)
	baselineButton = Button(panel, "Set Current Configuration as 100% Baseline", 302, SaveBaseline)
	baselineButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 14)
	loadButtons = {
		Button(panel, "Load Plan A", 130, function() LoadPlan(1) end),
		Button(panel, "Load Plan B", 130, function() LoadPlan(2) end),
	}
	loadButtons[1]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 14)
	loadButtons[2]:SetPoint("LEFT", loadButtons[1], "RIGHT", 8, 0)
	scroll = CreateFrame("ScrollFrame", "SurvivorUIRebornGearScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -77)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 50)
	content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(WIDTH - 54)
	content:SetHeight(1)
	scroll:SetScrollChild(content)
	panel:SetScript("OnHide", function()
		if not previewIsNative then ClearPreview() end
		panel:SetScript("OnUpdate", nil)
		if searches and ((searches[1] and searches[1].worker) or (searches[2] and searches[2].worker)) then searches = nil end
	end)
end

function SurvivorUI_RebornGearOpen(argument)
	if not SurvivorUI_RebornGearEnabled() then return end
	if argument == "off" then if panel then panel:Hide() end; return end
	if not panel then Build() end
	if panel:IsShown() and argument ~= "show" and argument ~= "worn" and argument ~= "simulator" then
		panel:Hide()
		return
	end
	panel:Show()
	showView(argument == "simulator" and "simulator" or "planner")
	TraceGear("open")
	RequestDiagnosticSync(true)
	return true
end

local function WorldChanged(reason)
	observedZone = nil
	InvalidateGear()
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
			ClearState()
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
