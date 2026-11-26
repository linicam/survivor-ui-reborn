-- A small world-UI fallback for the separate Reborn hero-menu Lua environment.
if SurvivorUI_Standby or not SurvivorUI_RebornGearModel then return end

local Gear = SurvivorUI_RebornGearModel
local WIDTH, MAP_HEIGHT, WORN_HEIGHT, GEAR_HEIGHT = 590, 345, 420, 510
local panel, mapView, wornView, wornScroll, wornContent, advanced, viewButton, context, entries, results
local resetMapButton
local mapLines, wornLines = {}, {}
local blockedZone, previewKey, previewTier, clearPreview, previewAvailable
local liveWorn, pendingReference
local lastLiveMap, lastLiveTier
local ROMAN = { "I", "II", "III", "IV", "V" }
local WORLDS = { "Classic", "The Burning Crusade", "Lich King", "Cataclysm" }
local STAT_NAMES = {
	damage = "Damage", crit = "Critical strike", crit_damage = "Critical damage", cooldown = "Cooldown reduction",
	area = "Area of effect", hp = "Health", armor = "Damage reduction", regen = "Health per second",
	speed = "Movement speed", pickup = "Pickup range", gold = "Gold find",
}
local function T(key) return SurvivorUI_T(key) end

local function Settings()
	SurvivorUIDB = SurvivorUIDB or {}
	if type(SurvivorUIDB.rebornGear) ~= "table" then SurvivorUIDB.rebornGear = {} end
	local settings = SurvivorUIDB.rebornGear
	if type(settings.references) ~= "table" then settings.references = {} end
	return settings
end

local function ClassKey()
	local zone = AZS_ZONE
	if type(zone) == "table" and type(zone.class) == "string" and zone.class ~= "" then
		return string.lower(zone.class)
	end
	if not UnitClass then return end
	local _, token = UnitClass("player")
	local native = token and AZS_GEN and AZS_GEN.classByToken and AZS_GEN.classByToken[token]
	return native and native.key or (token and string.lower(token))
end

local function InHub(zone)
	return type(zone) == "table" and tonumber(zone.hub) == 1
end

local function CampaignPressure(zone)
	if type(zone) ~= "table" or zone == blockedZone or InHub(zone) or (AZS_PG and AZS_PG.active) then return end
	return Gear.Pressure(SurvivorUI_RebornMapReference, zone.zone, tonumber(zone.dt))
end

local function RunIdentity(zone)
	if SurvivorUI_RebornStableRunId then
		local id = SurvivorUI_RebornStableRunId(zone.run)
		if id then return id end
	end
	return zone
end

local function SameMap(reference, key, tier)
	return type(reference) == "table" and reference.zone == key and reference.tier == tier
end

local function LiveSnapshot(zone, class)
	return liveWorn and liveWorn.identity == RunIdentity(zone) and liveWorn.class == class
		and SameMap(liveWorn.snapshot, zone.zone, tonumber(zone.dt)) and liveWorn.snapshot or nil
end

local function SaveWornReference(reference, class, pieces)
	if type(reference.worn) ~= "table" then reference.worn = {} end
	local copy = {}
	for i, piece in ipairs(pieces) do copy[i] = { slot = piece.slot, tier = piece.tier, stars = piece.stars } end
	reference.worn[class] = copy
end

local function StoreWorn()
	local zone = AZS_ZONE
	if not SurvivorUI_RebornActive() or not CampaignPressure(zone) then return end
	local settings = Settings()
	if settings.worn == false or (settings.preview == false and settings.planner == false) then return end
	local class = ClassKey()
	if not class or LiveSnapshot(zone, class) then return end
	local pieces = Gear.Worn(Gear.Catalog(AZS_GEN), class, AZS_ARMOR)
	if not pieces then return end
	if type(settings.wornSnapshots) ~= "table" then settings.wornSnapshots = {} end
	local snapshot = { pieces = pieces, at = time and time(), source = "campaign", zone = zone.zone, tier = tonumber(zone.dt) }
	settings.wornSnapshots[class] = snapshot
	liveWorn = { identity = RunIdentity(zone), class = class, snapshot = snapshot }
	local reference = settings.mapReference
	if SameMap(reference, snapshot.zone, snapshot.tier) then
		local pending = pendingReference and pendingReference.reference == reference and pendingReference.identity == liveWorn.identity
		if pending or type(reference.worn) ~= "table" or not reference.worn[class] then SaveWornReference(reference, class, pieces) end
	end
	pendingReference = nil
	return true
end

local function WornSnapshot()
	local settings, class = Settings(), ClassKey()
	local snapshots = settings.wornSnapshots
	local snapshot
	if CampaignPressure(AZS_ZONE) then snapshot = LiveSnapshot(AZS_ZONE, class)
	elseif type(snapshots) == "table" then snapshot = snapshots[class] end
	if type(snapshot) == "table" and type(snapshot.pieces) == "table" then return snapshot, class end
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
	local pieces, line = Gear.Parse(catalog, class, entries:GetText(), true)
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

local function NativeName(name)
	local localized = AZS_L and AZS_L[name]
	return localized and localized ~= name and localized or T(name)
end

local function GearName(key)
	if key == "pvp" then return NativeName("PvP") end
	if key == "deathknight" then return NativeName("Death Knight") end
	if key == "demonhunter" then return NativeName("Demon Hunter") end
	local words = string.gsub(key, "_", " ")
	return NativeName((string.gsub(words, "(%a)(%a*)", function(first, rest) return string.upper(first) .. rest end)))
end

local function DifficultyName(tier)
	return tier == 0 and T("Normal") or SurvivorUI_TF("Heroic {1}", ROMAN[tier])
end

local function MapTitle(zone, tier, liveName)
	local name = type(liveName) == "string" and liveName ~= "" and liveName or nil
	if not name then
		for _, row in ipairs(AZS_GEN and AZS_GEN.zones or {}) do
			if row.key == zone then
				name = row.name and NativeName(row.name)
				break
			end
		end
	end
	return (name or (zone == "naxx" and T("Naxxramas")) or zone) .. " · " .. DifficultyName(tier)
end

local function CurrentMap()
	local zone = AZS_ZONE
	local pressure = CampaignPressure(zone)
	if pressure then return zone.zone, tonumber(zone.dt), pressure, zone.zname end
end

local function TargetMap()
	local pressure = previewKey and Gear.Pressure(SurvivorUI_RebornMapReference, previewKey, previewTier)
	if pressure then return previewKey, previewTier, pressure, nil, true end
	local key, tier, live, name = CurrentMap()
	if live then return key, tier, live, name end
	if InHub(AZS_ZONE) then
		local snapshot = WornSnapshot()
		local recent = snapshot and Gear.Pressure(SurvivorUI_RebornMapReference, snapshot.zone, snapshot.tier)
		if recent then return snapshot.zone, snapshot.tier, recent, nil, false, true end
	end
end

local function DisplayLines(labels, lines)
	for index, line in ipairs(labels) do line:SetText(lines[index] or "") end
end

local function ShowMap(save)
	local settings = Settings()
	local key, tier, pressure, name = CurrentMap()
	local saved = save and pressure
	if saved then
		if not SameMap(settings.mapReference, key, tier) then settings.mapReference = { zone = key, tier = tier } end
		local ref, class = settings.mapReference, ClassKey()
		local snapshot = LiveSnapshot(AZS_ZONE, class)
		if snapshot then SaveWornReference(ref, class, snapshot.pieces); pendingReference = nil
		else pendingReference = { reference = ref, identity = RunIdentity(AZS_ZONE) } end
		clearPreview()
	end
	local preview, recent
	key, tier, pressure, name, preview, recent = TargetMap()
	if preview then resetMapButton:Show() else resetMapButton:Hide() end
	local ref = settings.mapReference
	local refKey, refTier, base = "naxx", 0, nil
	if type(ref) == "table" then
		base = Gear.Pressure(SurvivorUI_RebornMapReference, ref.zone, ref.tier)
		if base then refKey, refTier = ref.zone, ref.tier end
	end
	base = base or Gear.Pressure(SurvivorUI_RebornMapReference, refKey, refTier)
	local lines = { string.format(T("100%% reference: %s"), MapTitle(refKey, refTier, key == refKey and name or nil)) }
	if pressure then
		local caption = preview and "Preview map: %s" or recent and "Last Campaign map: %s" or "Current map: %s"
		table.insert(lines, string.format(T(caption), MapTitle(key, tier, name)))
		table.insert(lines, string.format(T("Map health scaling vs reference %.1f%%"), 100 * pressure / base))
		table.insert(lines, T("Open Gear plan for the upgrades needed to reach your reference."))
		if tier >= 3 or refTier >= 3 then table.insert(lines, T("Heroic affixes can change the actual workload.")) end
	else
		table.insert(lines, T(previewAvailable and "Choose a map above to preview its difficulty."
			or "Enter a Campaign map to read its difficulty and set it as 100%."))
	end
	if save then table.insert(lines, T(saved and "Current map saved as 100%." or "Current map data unavailable. Your reference was kept.")) end
	DisplayLines(mapLines, lines)
end

local function ActiveSets(sets)
	local list = {}
	for tier, bonuses in pairs(sets or {}) do
		for _, bonus in ipairs(bonuses) do
			local template = AZS_L and AZS_L[bonus.template] or nil
			local text = template and string.gsub(template, "{(%w+)}", function(key)
				return bonus.values[key] or "?"
			end) or bonus.text
			table.insert(list, string.format("%s %d%s · %s", GearName(tier), bonus.pieces, bonus.strong and " ★5" or "", text))
		end
	end
	table.sort(list)
	return list
end

local function StatChanges(old, new)
	local list = {}
	local function AddStat(key, delta)
		if math.abs(delta) <= 0.00001 then return end
		local flat = key == "hp" or key == "regen"
		local name = NativeName(STAT_NAMES[key] or key)
		table.insert(list, string.format("%s %+.2f%s", name, flat and delta or delta * 100, flat and "" or "%"))
	end
	for key, after in pairs(new) do
		AddStat(key, after - (old[key] or 0))
	end
	for key, before in pairs(old) do
		if not new[key] then AddStat(key, -before) end
	end
	table.sort(list)
	if not list[1] then list[1] = T("No modeled attribute change") end
	return list
end

local function Delta(old, new)
	return table.concat(StatChanges(old, new), "  ·  ")
end

local function PriceText(catalog, slot, tier, star)
	local amount = Gear.StarQuote(catalog, slot, tier, star)
	if not amount then return T("Price unknown") end
	return string.format(T("%d gold"), amount)
end

local function AddInspectGearPreview(owner)
	if not SurvivorUI_RebornActive() or not AZSInspect or AZSInspect.unit ~= "player" or not (owner and owner.piece)
		or not (GameTooltip and GameTooltip:IsOwned(owner)) then return end
	local settings = SurvivorUIDB and SurvivorUIDB.rebornGear
	if type(settings) == "table" and settings.preview == false then return end
	local class, catalog = ClassKey(), Gear.Catalog(AZS_GEN)
	local pieces = Gear.Worn(catalog, class, { owner.piece })
	local nextStars = pieces and Gear.NextStars(catalog, class, pieces)
	if not nextStars then return end
	local piece, nextStar = pieces[1], nextStars[1]
	GameTooltip:AddLine(" ")
	if nextStar then
		local target = piece.stars + 1
		GameTooltip:AddLine(string.format(T("Next star · ★%d → ★%d"), piece.stars, target), 1, 0.82, 0.22)
		for _, line in ipairs(StatChanges(nextStar.before, nextStar.after)) do
			GameTooltip:AddLine(line, 0.55, 1, 0.65)
		end
		GameTooltip:AddLine(PriceText(catalog, piece.slot, piece.tier, target), 1, 0.82, 0.22)
	else
		GameTooltip:AddLine(T("At five stars"), 0.85, 0.85, 0.85)
	end
	GameTooltip:Show()
end

local hookedInspect, hookedSlots = nil, {}
local inspectOverview
local function HookInspectSlots()
	-- Reborn creates the paper-doll frames lazily inside RefreshDoll.
	for index = 0, 10 do
		local icon = _G["AZSInspectSlot" .. index]
		local owner = icon and icon:GetParent()
		if owner and owner.slot == index and not hookedSlots[owner] and type(owner.HookScript) == "function" then
			owner:HookScript("OnEnter", AddInspectGearPreview)
			hookedSlots[owner] = true
		end
	end
end

local function RefreshInspectOverview()
	local inspect, gear = AZSInspect, AZSInspectGear
	local settings = SurvivorUIDB and SurvivorUIDB.rebornGear
	if not (SurvivorUI_RebornActive() and inspect and inspect.unit == "player" and inspect:IsShown()
		and gear and gear:IsShown()) or (type(settings) == "table" and settings.preview == false) then
		if inspectOverview then inspectOverview:Hide() end
		return
	end
	if not inspectOverview then
		inspectOverview = CreateFrame("Button", nil, gear, "UIPanelButtonTemplate")
		inspectOverview:SetPoint("TOPRIGHT", gear, "TOPRIGHT", -12, -11)
		inspectOverview:SetWidth(78); inspectOverview:SetHeight(22)
		inspectOverview:SetText(T("Upgrades"))
		inspectOverview:SetScript("OnClick", function()
			if SurvivorUI_RebornGearOpen("worn") then inspect:Hide() end
		end)
	end
	inspectOverview:Show()
end

local function RefreshInspectGear()
	HookInspectSlots()
	RefreshInspectOverview()
end

local function InstallInspectHook()
	local inspect = AZSInspect
	if not inspect or inspect == hookedInspect or type(inspect.RefreshDoll) ~= "function" or type(hooksecurefunc) ~= "function" then return end
	hooksecurefunc(inspect, "RefreshDoll", RefreshInspectGear)
	hookedInspect = inspect
	RefreshInspectGear()
end

local function MissingWornMessage(settings)
	if settings.worn == false then return T("Worn gear recording is disabled.") end
	if InHub(AZS_ZONE) then return T("No Campaign gear recorded for this class yet.") end
	return T("Waiting for the game's Campaign gear snapshot.")
end

local function DisplayWorn(lines)
	local y = 0
	for i, text in ipairs(lines) do
		local label = wornLines[i]
		if not label then
			label = wornContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetWidth(WIDTH - 54)
			label:SetJustifyH("LEFT")
			label:SetTextColor(0.92, 0.94, 0.98)
			wornLines[i] = label
		end
		label:SetText(text)
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", wornContent, "TOPLEFT", 0, -y)
		label:Show()
		local height = label.GetStringHeight and label:GetStringHeight()
		y = y + math.max(14, height or 0) + 5
	end
	for i = table.getn(lines) + 1, table.getn(wornLines) do wornLines[i]:Hide() end
	wornContent:SetHeight(math.max(1, y))
	wornScroll:SetVerticalScroll(0)
end

local function AddUpgradePlan(lines, settings, catalog, class, snapshot)
	if settings.planner == false then return end
	local key, tier, pressure, name = TargetMap()
	if not pressure then
		table.insert(lines, T("Choose a target under Map difficulty to preview an upgrade plan."))
		return
	end
	table.insert(lines, string.format(T("Upgrade plan for %s · target below 100%%"), MapTitle(key, tier, name)))
	local ref = settings.mapReference
	local refPressure = type(ref) == "table" and Gear.Pressure(SurvivorUI_RebornMapReference, ref.zone, ref.tier)
	local recorded = refPressure and type(ref.worn) == "table" and Gear.WornPlan(catalog, class, ref.worn[class])
	if not recorded then
		table.insert(lines, T("Enter the reference map at its saved difficulty to record baseline gear for this class."))
		return
	end
	local baseline = Gear.Totals(catalog, class, recorded.current)
	local pieces = Gear.WornPlan(catalog, class, snapshot.pieces)
	local plan = pieces and Gear.UnderBaseline(pieces, pressure, { pressure = refPressure, damage = baseline.damage or 0 })
	if not plan then
		table.insert(lines, T("The upgrade plan could not be calculated for this gear."))
		return
	end
	table.insert(lines, string.format(T("Estimated output pressure %.2f%% → %.2f%% · %d gold"), plan.current * 100, plan.after * 100, plan.cost))
	if plan.current < 1 then table.insert(lines, T("Already below 100%. No upgrades needed."))
	elseif plan.reached then table.insert(lines, T("Lowest estimated cost among upgrades to these pieces."))
	else table.insert(lines, T("Best modeled result from these pieces. The target is still out of reach.")) end
	for i, piece in ipairs(plan.pieces) do
		local old = pieces.current[i]
		if piece.stars > old.stars then
			table.insert(lines, string.format("%s · %s · ★%d → ★%d · %s", GearName(piece.slot), GearName(piece.tier), old.stars,
				piece.stars, string.format(T("%d gold"), piece.cost)))
		end
	end
	if plan.cost > 0 then
		local _, before = Gear.Totals(catalog, class, pieces.current)
		local _, after = Gear.Totals(catalog, class, plan.pieces)
		local known = {}
		for _, text in ipairs(ActiveSets(before)) do known[text] = true end
		for _, text in ipairs(ActiveSets(after)) do
			if not known[text] then table.insert(lines, T("Set gained") .. " · " .. text) end
		end
	end
	if pieces.incomplete then table.insert(lines, T("Unpriced stars are excluded from the search.")) end
	table.insert(lines, T("Uses enemy health and listed gear damage. Check star unlocks in Gear."))
end

local function ShowWorn()
	local settings = Settings()
	if settings.preview == false and settings.planner == false then DisplayWorn({ T("This gear analysis feature is disabled.") }); return end
	local snapshot, class = WornSnapshot()
	local catalog = Gear.Catalog(AZS_GEN)
	if not snapshot or not catalog then
		DisplayWorn({ MissingWornMessage(settings) })
		return
	end
	local native = AZS_ZONE and AZS_ZONE.cname
	local zone = SurvivorUI_TimeZone and SurvivorUI_TimeZone()
	local stamp = snapshot.at and date and date("%Y-%m-%d %H:%M", snapshot.at + (zone or 0))
	local recorded = stamp and string.format(T(zone and "Recorded at %s" or "Recorded at %s UTC"), stamp)
	local lines = { string.format(T("Last recorded gear: %s · %d pieces"), native or GearName(class), table.getn(snapshot.pieces)) }
	local source = snapshot.source == "hub" and T("Recorded in Dalaran Hub")
		or snapshot.source == "campaign" and T("Recorded in a Campaign map")
	if source and recorded then source = source .. " · " .. recorded end
	if source then table.insert(lines, source)
	elseif recorded then table.insert(lines, recorded) end
	AddUpgradePlan(lines, settings, catalog, class, snapshot)
	local rows = settings.preview ~= false and Gear.NextStars(catalog, class, snapshot.pieces)
	if not rows then DisplayWorn(lines); return end
	table.insert(lines, T(rows[1] and "Top next-star gains, ordered by added piece damage" or "All recorded pieces are at five stars."))
	for i = 1, math.min(table.getn(rows), 6) do
		local row = rows[i]
		local piece = row.piece
		table.insert(lines, string.format("%s · %s · ★%d → ★%d · %s", GearName(piece.slot), GearName(piece.tier), piece.stars,
			piece.stars + 1, PriceText(catalog, piece.slot, piece.tier, piece.stars + 1)))
		table.insert(lines, "    " .. Delta(row.before, row.after))
	end
	DisplayWorn(lines)
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
			Add(GearName(group.slot) .. " · " .. (current and (GearName(current.tier) .. " ★" .. current.stars) or T("No declared equipped piece")))
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
						Add(string.format(T("%s ★%d · %s · %d extra gold"), GearName(option.tier), option.stars, T(option.kind), option.cost))
						if option.tablePrice then Add(T("Includes chart-based prices dated 2026-11-16.")) end
					else
						local stars = entry.start + index - 1
						option = { slot = entry.slot, tier = entry.tier, stars = stars,
							stats = Gear.Piece(s.catalog, s.class, entry.slot, entry.tier, stars) }
						if index == 2 and entry == group.worn then
							Add(string.format("%s ★%d · %s", GearName(option.tier), option.stars,
								PriceText(s.catalog, entry.slot, entry.tier, stars)))
						else
							Add(string.format(T("%s ★%d · price unknown"), GearName(option.tier), option.stars))
						end
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
	if s.pieces.usesPriceTable then Add(T("Price source: 2026-11-16 armor table. Weapons use the same tier price.")) end
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
		local from = old and (GearName(old.tier) .. " ★" .. old.stars) or "—"
		Add(GearName(item.slot) .. " · " .. from .. " → " ..
			string.format(T("%s ★%d · %s · %d extra gold"), GearName(item.tier), item.stars, T(item.kind), item.cost))
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
	local state, err = Read(action == "compare" or action == "reference")
	if not state then Add(err); return end
	local settings = Settings()
	settings.context, settings.entries = context:GetText(), entries:GetText()
	if action == "reference" then
		local ref = Reference(state, settings)
		if not ref then Add(T("Save a reference with this class and fixed background.")); return end
		Add(string.format(T("Reference %s / %d · %d pieces"), ref.zone, ref.tier, table.getn(ref.gear)))
		for _, item in ipairs(ref.gear) do
			Add(GearName(item.slot) .. " · " .. GearName(item.tier) .. " ★" .. item.stars .. " · " .. Delta({}, item.stats))
		end
		for _, label in ipairs(ActiveSets(ref.sets)) do Add(T("Active set") .. " · " .. label) end
		return
	end
	if not state.pieces then
		local ref = Reference(state, settings)
		local base = ref and ref.pressure or Gear.Pressure(SurvivorUI_RebornMapReference, "naxx", 0)
		Add(T("Map / tier") .. " · " .. MapTitle(state.zone, state.tier))
		Add(string.format(T("100%% reference: %s"), MapTitle(ref and ref.zone or "naxx", ref and ref.tier or 0)))
		Add(string.format(T("Map health scaling vs reference %.1f%%"), 100 * state.pressure / base))
		if state.tier >= 3 or (ref and ref.tier >= 3) then Add(T("Heroic affixes can change the actual workload.")) end
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
	Add(T("Map / tier") .. " · " .. MapTitle(state.zone, state.tier))
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
	local mapAction = action == "map" or action == "save_map"
	local feature = mapAction and "difficulty" or action == "gear" and "preview"
		or (action == "stars" or action == "farm") and "planner" or action == "record" and "diagnostics"
	if feature and (settings[feature] == false or (feature == "diagnostics" and settings[feature] ~= true)) then
		Say("This gear analysis feature is disabled.")
		return
	end
	local phase = not mapAction and AZS_GetPhase and AZS_GetPhase()
	if phase == "playing" or phase == "choosing" or phase == "paused" then
		Say("Open gear analysis from the hub or outside active combat.")
		return
	end
	local ok
	if mapAction then ok = pcall(ShowMap, action == "save_map") else ok = pcall(Calculate, action) end
	if not ok then
		local message = T("Gear analysis is unavailable for these game data.")
		if mapAction then DisplayLines(mapLines, { message }) else results:Clear(); Add(message) end
	end
end

local function ShowView(view)
	local equipment = view == "manual"
	if view == "map" then mapView:Show() else mapView:Hide() end
	if view == "worn" then wornView:Show() else wornView:Hide() end
	if equipment then advanced:Show() else advanced:Hide() end
	panel:SetHeight(equipment and GEAR_HEIGHT or (view == "worn" and WORN_HEIGHT or MAP_HEIGHT))
	viewButton:SetText(T(view == "map" and "Gear plan" or "Map difficulty"))
	results:Clear()
	if equipment then results:Show() else results:Hide() end
	if view == "map" then RunAction("map") end
	if view == "worn" then ShowWorn() end
end

local function Label(parent, text, x, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetText(T(text))
	return label
end

local function Picker(parent, suffix, caption, x, width, choices, select)
	Label(parent, caption, x + 16, -273)
	local menu = CreateFrame("Frame", "SurvivorUIRebornGear" .. suffix, parent, "UIDropDownMenuTemplate")
	menu:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -290)
	UIDropDownMenu_SetWidth(menu, width)
	UIDropDownMenu_Initialize(menu, function()
		for _, option in ipairs(choices()) do
			local key, text = option.key, option.name
			local info = UIDropDownMenu_CreateInfo()
			info.value, info.text = key, text
			info.func = function() select(key, text) end
			UIDropDownMenu_AddButton(info)
		end
	end)
	return function(key, text)
		UIDropDownMenu_SetSelectedValue(menu, key)
		UIDropDownMenu_SetText(menu, text)
	end
end

local function BuildPreviewPickers(parent)
	clearPreview = function() previewKey, previewTier = nil, nil end
	if not (UIDropDownMenu_Initialize and UIDropDownMenu_SetWidth and UIDropDownMenu_CreateInfo
		and UIDropDownMenu_AddButton and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText) then return end
	local byWorld, worlds, tiers = {}, {}, {}
	for _, zone in ipairs(AZS_GEN and AZS_GEN.zones or {}) do
		local world = tonumber(zone.world)
		if WORLDS[world] and Gear.Pressure(SurvivorUI_RebornMapReference, zone.key, 0) then
			if not byWorld[world] then byWorld[world] = {} end
			table.insert(byWorld[world], { key = zone.key, name = NativeName(zone.name or zone.key) })
		end
	end
	for i, name in ipairs(WORLDS) do
		if byWorld[i] then table.insert(worlds, { key = i, name = NativeName(name) }) end
	end
	if not worlds[1] then return end
	for i = 0, 5 do table.insert(tiers, { key = i, name = DifficultyName(i) }) end
	local world, tier = worlds[1].key, 0
	local setWorld, setZone, setTier
	setWorld = Picker(parent, "World", "Expansion", 0, 135, function() return worlds end, function(key, text)
		world = key
		setWorld(key, text)
		clearPreview()
		RunAction("map")
	end)
	setZone = Picker(parent, "Zone", "Map to preview", 158, 205, function() return byWorld[world] end, function(key, text)
		previewKey, previewTier = key, tier
		setZone(key, text)
		RunAction("map")
	end)
	setTier = Picker(parent, "Tier", "Difficulty", 388, 128, function() return tiers end, function(key, text)
		tier, previewTier = key, key
		setTier(key, text)
		if previewKey then RunAction("map") end
	end)
	clearPreview = function()
		previewKey, previewTier = nil, nil
		setZone(nil, T("Choose a map"))
	end
	setWorld(world, worlds[1].name)
	setTier(tier, tiers[1].name)
	clearPreview()
	previewAvailable = true
end

local function Build()
	panel = CreateFrame("Frame", "SurvivorUIRebornGearPanel", UIParent)
	panel:Hide()
	panel:SetWidth(WIDTH); panel:SetHeight(MAP_HEIGHT)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true)
	panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
	panel:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
	panel:RegisterEvent("PLAYER_ENTERING_WORLD")
	panel:SetScript("OnEvent", function()
		blockedZone = AZS_ZONE
		pendingReference = nil
		clearPreview()
		panel:Hide()
	end)
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
	Label(panel, "Gear & Difficulty", 16, -16)
	viewButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	viewButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, -12)
	viewButton:SetWidth(122); viewButton:SetHeight(22)
	viewButton:SetScript("OnClick", function()
		context:ClearFocus(); entries:ClearFocus()
		ShowView(mapView:IsShown() and "worn" or "map")
	end)
	mapView = CreateFrame("Frame", nil, panel)
	mapView:SetAllPoints(panel)
	wornView = CreateFrame("Frame", nil, panel)
	wornView:SetAllPoints(panel)
	advanced = CreateFrame("Frame", nil, panel)
	advanced:SetAllPoints(panel)
	Label(mapView, "The current map is shown automatically. Use the selectors below to preview another map.", 16, -48)
	for index, row in ipairs({ { "save_map", "Set current map to 100%" }, { "map", "Clear map preview" } }) do
		local action = row[1]
		local button = CreateFrame("Button", nil, mapView, "UIPanelButtonTemplate")
		button:SetPoint("TOPLEFT", mapView, "TOPLEFT", 16 + (index - 1) * 204, -76)
		button:SetWidth(196); button:SetHeight(24)
		button:SetText(T(row[2]))
		if action == "map" then resetMapButton = button; button:Hide() end
		button:SetScript("OnClick", function()
			if action == "map" then clearPreview() end
			RunAction(action)
		end)
	end
	BuildPreviewPickers(mapView)
	for index = 1, 6 do
		local label = Label(mapView, "", 16, -109 - (index - 1) * 22)
		label:SetWidth(WIDTH - 32)
		label:SetJustifyH("LEFT")
		if index == 3 then label:SetTextColor(1, 0.82, 0.22) else label:SetTextColor(0.92, 0.94, 0.98) end
		mapLines[index] = label
	end
	wornScroll = CreateFrame("ScrollFrame", "SurvivorUIRebornWornScroll", wornView, "UIPanelScrollFrameTemplate")
	wornScroll:SetPoint("TOPLEFT", wornView, "TOPLEFT", 16, -51)
	wornScroll:SetPoint("BOTTOMRIGHT", wornView, "BOTTOMRIGHT", -32, 16)
	wornContent = CreateFrame("Frame", "SurvivorUIRebornWornContent", wornScroll)
	wornContent:SetWidth(WIDTH - 54)
	wornContent:SetHeight(1)
	wornScroll:SetScrollChild(wornContent)
	Label(advanced, "class map tier background% [slot]", 16, -46)
	context = CreateFrame("EditBox", nil, advanced, "InputBoxTemplate")
	context:SetWidth(WIDTH - 38); context:SetHeight(23); context:SetMaxLetters(125)
	context:SetPoint("TOPLEFT", advanced, "TOPLEFT", 20, -62)
	context:SetAutoFocus(false)
	context:SetScript("OnEscapePressed", function() context:ClearFocus() end)
	Label(advanced, "slot quality stars worn/owned/farm [next prices: 100,200]", 16, -95)
	local scroll = CreateFrame("ScrollFrame", "SurvivorUIRebornGearInput", advanced, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", advanced, "TOPLEFT", 16, -112)
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
		{ "save", "Save gear setup" }, { "compare", "Compare gear" }, { "gear", "Gear preview" },
		{ "stars", "Stars Only" }, { "farm", "Farm & Upgrade" },
	}
	for index, row in ipairs(actions) do
		local action = row[1]
		local button = CreateFrame("Button", nil, advanced, "UIPanelButtonTemplate")
		button:SetWidth(108); button:SetHeight(22)
		button:SetPoint("TOPLEFT", advanced, "TOPLEFT", 15 + (index - 1) * 112, -236)
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
	if feature == "difficulty" or feature == "preview" or feature == "planner" or feature == "diagnostics" or feature == "worn" then
		local settings = Settings()
		local enabled = settings[feature]
		if enabled == nil then enabled = feature ~= "diagnostics" end
		settings[feature] = not enabled
		if results then results:Clear() end
		if feature == "difficulty" and enabled then DisplayLines(mapLines, {}) end
		if (feature == "worn" or feature == "preview" or feature == "planner")
			and panel and panel:IsShown() and wornView:IsShown() then ShowWorn() end
		if feature == "preview" then RefreshInspectOverview() end
		Say(not enabled and "Gear analysis feature enabled." or "This gear analysis feature is disabled.")
		return
	end
	if argument == "off" then
		if panel then panel:Hide() end
		return
	end
	if not panel then Build() end
	if argument == "worn" then
		ShowView("worn")
		panel:Show()
	elseif argument == "advanced" then
		ShowView("manual")
		panel:Show()
	elseif argument == "keys" then
		ShowView("manual")
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
		ShowView("manual")
		RunAction("reference")
		panel:Show()
	elseif argument == "capture" then
		ShowView("manual")
		RunAction("record")
		panel:Show()
	elseif panel:IsShown() and argument ~= "show" then
		panel:Hide()
	else
		if not panel:IsShown() or not mapView:IsShown() then ShowView("map") end
		panel:Show()
	end
	return panel:IsShown()
end

if AZS and type(AZS.On) == "function" then
	AZS.On("AZSZONE", function()
		local key, tier = CurrentMap()
		if key and (key ~= lastLiveMap or tier ~= lastLiveTier) and clearPreview then clearPreview() end
		lastLiveMap, lastLiveTier = key, tier
		if panel and panel:IsShown() then
			if mapView:IsShown() then RunAction("map") elseif wornView:IsShown() then ShowWorn() end
		end
	end)
	AZS.On("AZSARMOR", function()
		InstallInspectHook()
		if StoreWorn() and panel and panel:IsShown() and wornView:IsShown() then ShowWorn() end
	end)
end
InstallInspectHook()
