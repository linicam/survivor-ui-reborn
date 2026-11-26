-- RebornDiagnostics.lua: opt-in diagnostic recording for SurvivorUI
-- Reborn. Disabled by default; nothing is recorded until the user
-- runs /sui reborn record start. Sessions persist in the dedicated
-- SurvivorUIRebornDiagnostics SavedVariables database and are
-- exported by the Windows helper (Upload-Diagnostics.ps1), never by
-- the addon itself. Raw observations and normalized addon results
-- are recorded as separate fields so replay can distinguish game
-- behavior from addon decisions.

local SCHEMA = 1
local MAX_EVENTS = 3000
local MAX_BYTES = 2097152
local MAX_SESSIONS = 10
local MAX_COPY_DEPTH = 8
local MAX_COPY_BREADTH = 128
local CRITICAL = {
	session_start = true, session_stop = true, run_transition = true,
	rank_change = true, tooltip = true, curse_banner = true,
	jewelry_update = true, error = true, mark = true,
	boss_unit = true, guardian_lairs = true, card_offer = true, card_action = true,
}

local recording = false
local session = nil
local sessionStart = 0
local pendingTooltips = {}
local pendingBuffs = {}
local tooltipBaselines = {}
local tooltipLegacyInvalid = {}
local lastExtraButtonSignature = nil
local lastCaptureNote = nil
local guardianSignature, guardianSampleAt
local nativeSeen, nativeRun = {}, nil
local nativeSpellTips
local pseudonyms = {}
local pseudonymCount = 0

local function Now()
	return GetTime and GetTime() or 0
end

local function DB()
	if type(SurvivorUIRebornDiagnostics) ~= "table" then
		SurvivorUIRebornDiagnostics = { schema = SCHEMA, sessions = {}, order = {} }
	end
	return SurvivorUIRebornDiagnostics
end

local function SanitizeKey(key)
	local k = string.lower(tostring(key))
	if string.find(k, "owner", 1, true) or string.find(k, "token", 1, true)
		or string.find(k, "password", 1, true) or string.find(k, "secret", 1, true) then
		return true
	end
	return false
end

local function CurrentRunId()
	return SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil
end

local function ObserveGuardianLairs()
	if not recording or type(AZS_LAIRS) ~= "table" then return end
	local zone = AZS_ZONE or {}
	local area = GetRealZoneText and GetRealZoneText() or nil
	local runTime = AZS_GetRunTime and AZS_GetRunTime()
	local signature = { tostring(CurrentRunId()), tostring(zone.map), tostring(area) }
	local rows, counting = {}, false
	for _, lair in ipairs(AZS_LAIRS) do
		local left = tonumber(lair.left)
		counting = counting or (lair.state == "empty" and left and left >= 0)
		table.insert(signature, table.concat({ tostring(lair.index), tostring(lair.state),
			tostring(lair.id), tostring(lair.x), tostring(lair.y) }, "|"))
		table.insert(rows, { index = lair.index, state = lair.state, id = lair.id, name = lair.name,
			x = lair.x, y = lair.y, z = lair.z, left = left })
	end
	signature = table.concat(signature, ";")
	local now = Now()
	if signature ~= guardianSignature or (counting and now - guardianSampleAt >= 15) then
		guardianSignature, guardianSampleAt = signature, now
		SurvivorUI_RebornRecord("guardian_lairs", { map = zone.map, area = area, runTime = runTime, rows = rows })
	end
end

local function BaselineKey(key, run)
	return tostring(run) .. "\0" .. tostring(key)
end

local function ValidTooltipRead(read, run)
	return type(read) == "table" and read.ok == true and read.run == run
		and type(read.lines) == "table" and table.getn(read.lines) > 0
end

-- Bounded deep copy: recorded values must not alias mutable game
-- tables. Depth and breadth are capped; truncation is explicit.
local function CopyValue(value, depth)
	local t = type(value)
	if t ~= "table" then
		if t == "function" or t == "userdata" or t == "thread" then
			return "<" .. t .. ">"
		end
		return value
	end
	if depth >= MAX_COPY_DEPTH then
		return "<truncated>"
	end
	local out = {}
	local count = 0
	for k, v in pairs(value) do
		count = count + 1
		if count > MAX_COPY_BREADTH then
			out.__truncated = true
			break
		end
		if SanitizeKey(k) then
			local raw = tostring(v)
			if not pseudonyms[raw] then
				pseudonymCount = pseudonymCount + 1
				pseudonyms[raw] = "player-" .. pseudonymCount
			end
			out[k] = pseudonyms[raw]
		else
			out[k] = CopyValue(v, depth + 1)
		end
	end
	return out
end

local function EstimateSize(value, depth)
	local t = type(value)
	if t == "string" then return string.len(value) + 8 end
	if t ~= "table" then return 16 end
	if depth >= MAX_COPY_DEPTH then return 32 end
	local total = 16
	for k, v in pairs(value) do
		total = total + EstimateSize(k, depth + 1) + EstimateSize(v, depth + 1)
	end
	return total
end

function SurvivorUI_RebornRecord(eventType, data)
	if not recording or not session then
		return
	end
	-- Consecutive identical observations are one state, not new
	-- evidence: dedup extra-button states and capture notes so a
	-- per-draw caller cannot exhaust the recording budget.
	if eventType == "extra_button" and type(data) == "table" then
		local signature = tostring(data.button) .. "|" .. tostring(data.spell) ..
			"|" .. tostring(data.pendingSpell) .. "|" .. tostring(data.visible) ..
			"|" .. tostring(data.ownedBinding) .. "|" .. tostring(data.deferred)
		if signature == lastExtraButtonSignature then
			return
		end
		lastExtraButtonSignature = signature
	elseif eventType == "capture_note" and type(data) == "table" then
		if data.text == lastCaptureNote then
			return
		end
		lastCaptureNote = data.text
	end
	local copied = CopyValue(data, 0)
	local size = EstimateSize(copied, 0)
	local critical = CRITICAL[eventType] == true
	-- Reserve the last 10% of the budget for critical lifecycle
	-- evidence; low-priority events drop first and are counted.
	local byteLimit = critical and MAX_BYTES or math.floor(MAX_BYTES * 0.9)
	local eventLimit = critical and MAX_EVENTS or math.floor(MAX_EVENTS * 0.9)
	if session.bytes + size > byteLimit or table.getn(session.events) >= eventLimit then
		session.truncated = true
		session.dropped[eventType] = (session.dropped[eventType] or 0) + 1
		return
	end
	session.bytes = session.bytes + size
	session.seq = session.seq + 1
	if eventType == "curse_banner" and type(data) == "table" and data.effect then
		table.insert(pendingBuffs, { at = Now() + 1, sessionId = session.id, run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil })
		table.insert(pendingBuffs, { at = Now() + 3, sessionId = session.id, run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil })
	end
	table.insert(session.events, {
		seq = session.seq,
		t = math.floor((Now() - sessionStart) * 1000) / 1000,
		run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil,
		type = eventType,
		data = copied,
	})
end

function SurvivorUI_RebornRecording()
	return recording
end

local function NewSessionId(db)
	db.counter = (db.counter or 0) + 1
	local stamp = date and date("%Y-%m-%d-%H%M%S") or ("t" .. tostring(math.floor(Now())))
	return stamp .. "-" .. string.format("%03d", db.counter)
end

function SurvivorUI_RebornRecordStart()
	if recording and session then
		return session.id
	end
	local db = DB()
	pendingTooltips = {}
	pendingBuffs = {}
	tooltipBaselines = {}
	lastExtraButtonSignature = nil
	lastCaptureNote = nil
	guardianSignature, guardianSampleAt = nil, 0
	nativeSeen, nativeRun = {}, nil
	pseudonyms = {}
	pseudonymCount = 0
	session = {
		id = NewSessionId(db),
		schema = SCHEMA,
		status = "active",
		addonVersion = "3.0.68",
		addonCommit = SurvivorUI_RebornBuildCommit or "dev",
		gameLanguage = GetLocale and GetLocale() or nil,
		class = UnitClass and select(2, UnitClass("player")) or nil,
		startedAt = time and time() or nil,
		endedAt = nil,
		seq = 0,
		runs = {},
		truncated = false,
		bytes = 0,
		dropped = {},
		events = {},
	}
	sessionStart = Now()
	recording = true
	db.sessions[session.id] = session
	table.insert(db.order, session.id)
	while table.getn(db.order) > MAX_SESSIONS do
		local old = table.remove(db.order, 1)
		db.sessions[old] = nil
		db.droppedSessions = (db.droppedSessions or 0) + 1
	end
	SurvivorUI_RebornRecord("session_start", { run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil })
	if SurvivorUI_RebornAbilities then
		local data = SurvivorUI_RebornAbilities()
		SurvivorUI_RebornRecord("abilities_initial", {
			rawAbilities = AZS_ABILITIES, rawSpells = AZS_SPELLS,
			normalized = data.all, source = data.source,
		})
		if SurvivorUI_RebornTooltipRead and not (nativeSpellTips and type(AZS_SPELLTIPS) == "table") then
			local run = CurrentRunId()
			for i = 1, table.getn(data.all) do
				-- The native tooltip source is established legacy
				-- text for Reborn abilities; once a key reads
				-- invalid, stop rescanning it automatically.
				if not tooltipLegacyInvalid[data.all[i].key] then
					local read = SurvivorUI_RebornTooltipRead(data.all[i].key)
					if ValidTooltipRead(read, run) then
						tooltipBaselines[BaselineKey(data.all[i].key, run)] = read
					else
						tooltipLegacyInvalid[data.all[i].key] = true
					end
					SurvivorUI_RebornRecord("tooltip", { phase = "baseline", read = read })
				end
			end
		end
	end
	if nativeSpellTips and type(AZS_SPELLTIPS) == "table" and next(AZS_SPELLTIPS) then
		SurvivorUI_RebornRecord("native_spell_tips_initial", { tips = AZS_SPELLTIPS })
	end
	ObserveGuardianLairs()
	if SurvivorUI_RebornJewelry then
		local jew = SurvivorUI_RebornJewelry(true)
		SurvivorUI_RebornRecord("jewelry_initial", { source = jew.source, items = jew.items })
	end
	return session.id
end

function SurvivorUI_RebornRecordStop()
	if not recording or not session then
		return nil
	end
	SurvivorUI_RebornRecord("session_stop", {})
	pendingTooltips = {}
	pendingBuffs = {}
	session.status = session.truncated and "truncated" or "completed"
	session.endedAt = time and time() or nil
	recording = false
	local id = session.id
	session = nil
	return id
end

function SurvivorUI_RebornRecordStatus()
	local db = DB()
	local runs = 0
	local events = 0
	if session then
		events = table.getn(session.events)
		local seen = {}
		for i = 1, events do
			local r = session.events[i].run
			if r and not seen[r] then
				seen[r] = true
				runs = runs + 1
			end
		end
	end
	return {
		active = recording,
		sessionId = session and session.id or nil,
		events = events,
		runs = runs,
		truncated = session and session.truncated or false,
		storedSessions = table.getn(db.order),
	}
end

function SurvivorUI_RebornRecordClear()
	SurvivorUIRebornDiagnostics = { schema = SCHEMA, sessions = {}, order = {} }
	recording = false
	session = nil
	pendingTooltips = {}
	pendingBuffs = {}
	tooltipBaselines = {}
end

function SurvivorUI_RebornRecordMark(text)
	SurvivorUI_RebornRecord("mark", { text = text })
end

-- Bounded follow-up tooltip captures after an ability change: the
-- native tooltip may update after the rank does.
function SurvivorUI_RebornRecordTooltipSoon(key, phase)
	if not recording or not session then
		return
	end
	if tooltipLegacyInvalid[key] or (nativeSpellTips and type(AZS_SPELLTIPS) == "table") then
		return
	end
	local run = CurrentRunId()
	local baseline = tooltipBaselines[BaselineKey(key, run)]
	if phase ~= "baseline" and baseline then
		SurvivorUI_RebornRecord("tooltip", { phase = "pre", read = baseline })
	end
	for i = 1, table.getn(pendingTooltips) do
		if pendingTooltips[i].key == key and pendingTooltips[i].run == run then
			return
		end
	end
	table.insert(pendingTooltips, {
		key = key, at = Now() + 1, tries = 0, phase = phase or "post",
		sessionId = session.id,
		run = run,
	})
end

local diagnosticsInitialized = false
local autoStartDone = false
local initDeadline = nil
local nextInitCheck = 0

local function InitializeDiagnostics()
	if diagnosticsInitialized then
		return
	end
	diagnosticsInitialized = true
	-- SavedVariables are populated after addon files execute, so
	-- interrupted-session recovery and the auto-start preference
	-- are read here, on an initialization event, not at file load.
	local db = DB()
	for id, s in pairs(db.sessions) do
		if type(s) == "table" and s.status == "active" then
			s.status = "interrupted"
		end
	end
	if SurvivorUIDB and SurvivorUIDB.rebornRecordAuto == true and not autoStartDone then
		autoStartDone = true
		local sessionId = SurvivorUI_RebornRecordStart()
		if sessionId then
			local message = "SurvivorUI Reborn diagnostics recording started: " .. tostring(sessionId)
			if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
				DEFAULT_CHAT_FRAME:AddMessage(message)
			elseif print then
				print(message)
			end
		end
	end
end

local timer = CreateFrame and CreateFrame("Frame") or nil
if timer then
	local observeAt = 0
	local lastBossKey = nil
	initDeadline = Now() + 60
	timer:SetScript("OnUpdate", function()
		local now = Now()
		if not diagnosticsInitialized then
			-- Bounded fallback: if no initialization event arrives,
			-- retry for up to 60 seconds after load.
			if now >= nextInitCheck and now <= initDeadline then
				nextInitCheck = now + 2
				if SurvivorUIDB ~= nil or SurvivorUIRebornDiagnostics ~= nil then
					InitializeDiagnostics()
				end
			end
			if not diagnosticsInitialized then
				return
			end
		end
		if not recording or not session then
			return
		end
		for i = table.getn(pendingTooltips), 1, -1 do
			local p = pendingTooltips[i]
			local currentRun = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil
			if p.sessionId ~= session.id or p.run ~= currentRun then
				table.remove(pendingTooltips, i)
			elseif now >= p.at then
				if SurvivorUI_RebornTooltipRead then
					local ok, read = pcall(SurvivorUI_RebornTooltipRead, p.key)
					if ok then
						if ValidTooltipRead(read, p.run) then
							tooltipBaselines[BaselineKey(p.key, p.run)] = read
							SurvivorUI_RebornRecord("tooltip", { phase = p.phase or "post", read = read })
						else
							SurvivorUI_RebornRecord("tooltip", { phase = p.phase or "post", key = p.key, ok = false, error = "failed or stale tooltip read", read = read })
						end
					else
						SurvivorUI_RebornRecord("tooltip", { phase = p.phase or "post", key = p.key, ok = false, error = tostring(read) })
					end
				end
				p.tries = p.tries + 1
				if p.tries >= 2 then
					if not tooltipBaselines[BaselineKey(p.key, p.run)] then tooltipLegacyInvalid[p.key] = true end
					table.remove(pendingTooltips, i)
				else
					p.at = now + 2
				end
			end
		end
		for i = table.getn(pendingBuffs), 1, -1 do
			local p = pendingBuffs[i]
			local currentRun = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil
			if p.sessionId ~= session.id or p.run ~= currentRun then
				table.remove(pendingBuffs, i)
			elseif now >= p.at then
				SurvivorUI_RebornRecord("buff_observation", { buffs = AZS_BUFFS })
				table.remove(pendingBuffs, i)
			end
		end
		-- UI-independent observation: refresh shared caches and
		-- boss transitions even when no panel is visible.
		if now >= observeAt then
			observeAt = now + 2
			if SurvivorUI_RebornCheckRun then SurvivorUI_RebornCheckRun() end
			if SurvivorUI_RebornAbilities then SurvivorUI_RebornAbilities() end
			if SurvivorUI_RebornJewelry then SurvivorUI_RebornJewelry() end
			if SurvivorUI_RebornRiftBosses then SurvivorUI_RebornRiftBosses() end
			ObserveGuardianLairs()
			if SurvivorUI_RebornNextBoss then
				local nb = SurvivorUI_RebornNextBoss()
				local key = nb and (tostring(nb.mode) .. "|" .. tostring(nb.state) .. "|" .. tostring(nb.number)) or "none"
				if key ~= lastBossKey then
					lastBossKey = key
					SurvivorUI_RebornRecord("boss_transition", { nextBoss = nb, run = AZS_RUN, rift = AZS_RIFT })
				end
			end
		end
	end)
end

-- Native listeners are registered after the game's snapshot parsers.
local function ObserveNative(key, value, eventType, data)
	if not recording then return end
	local run = CurrentRunId()
	if nativeRun ~= run then nativeSeen, nativeRun = {}, run end
	if nativeSeen[key] == value then return end
	nativeSeen[key] = value
	SurvivorUI_RebornRecord(eventType, data)
end

if AZS and type(AZS.On) == "function" then
	nativeSpellTips = true
	AZS.On("AZSSPELLTIP", function(msg)
		if not recording or type(msg) ~= "string" then return end
		local key, value = string.match(msg, "^key=([^;]+);text=(.*)$")
		if key then ObserveNative("spell:" .. key, value, "native_spell_tip", { key = key, text = value }) end
	end)
	AZS.On("AZSCARDS", function()
		if not recording or type(AZS_CARDS) ~= "table" then return end
		local hand = AZS_CARDS
		SurvivorUI_RebornRecord("card_offer", { hand = hand, stats = AZS_RUNSTATS, caps = AZS_CAPS })
	end)
	AZS.On("AZSCARDTIP", function(msg)
		if recording then SurvivorUI_RebornRecord("native_card_tip", { payload = msg }) end
	end)
	AZS.On("AZSGEAR", function(msg)
		if recording then ObserveNative("gear", msg, "native_gear", { rows = AZS_GEAR }) end
	end)
	AZS.On("AZSHEX", function(msg)
		if recording then ObserveNative("hex", msg, "native_hex", { rows = AZS_HEXES }) end
	end)
	AZS.On("AZSLAIRS", ObserveGuardianLairs)
	local function ObserveRift()
		if not recording or not SurvivorUI_RebornRiftBosses then return end
		if SurvivorUI_RebornCheckRun then SurvivorUI_RebornCheckRun() end
		SurvivorUI_RebornRiftBosses()
	end
	AZS.On("AZSUNITS", ObserveRift)
	AZS.On("AZSRIFT", ObserveRift)
end

if hooksecurefunc and SendAddonMessage then
	hooksecurefunc("SendAddonMessage", function(prefix, command)
		if not recording or prefix ~= "AZSCMD" or type(command) ~= "string" then return end
		local hand = AZS_CARDS
		if type(hand) ~= "table" or (hand.kind ~= "spell" and hand.kind ~= "jewel") then return end
		local action, index = string.match(command, "^(%a+) (%d+)$")
		if action == "pick" or action == "banish" or command == "reroll" or command == "skip" then
			SurvivorUI_RebornRecord("card_action", { action = action or command, index = tonumber(index), kind = hand.kind,
				remainingBanishes = hand.bn, remainingRerolls = hand.rr })
		end
	end)
end

function SurvivorUI_RebornRecordInitialize()
	InitializeDiagnostics()
end

function SurvivorUI_RebornRecordAuto(enabled)
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.rebornRecordAuto = enabled == true
	local stopped = false
	if enabled and not recording then
		SurvivorUI_RebornRecordStart()
	elseif not enabled and recording then
		SurvivorUI_RebornRecordStop()
		stopped = true
	end
	return SurvivorUIDB.rebornRecordAuto, stopped
end

-- Initialization runs on addon/game init events (SavedVariables
-- are available by then), with the bounded OnUpdate fallback above.
if timer and timer.RegisterEvent then
	timer:RegisterEvent("ADDON_LOADED")
	timer:RegisterEvent("PLAYER_LOGIN")
	timer:RegisterEvent("PLAYER_ENTERING_WORLD")
	timer:RegisterEvent("PLAYER_LOGOUT")
	local prior = timer.GetScript and timer:GetScript("OnEvent") or nil
	timer:SetScript("OnEvent", function(self, event, arg1)
		if event == "ADDON_LOADED" and arg1 == "SurvivorUI" then
			InitializeDiagnostics()
		elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
			InitializeDiagnostics()
		elseif event == "PLAYER_LOGOUT" and recording then
			SurvivorUI_RebornRecordStop()
		end
		if prior then prior(self, event, arg1) end
	end)
end
