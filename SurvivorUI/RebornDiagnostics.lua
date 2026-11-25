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
local MAX_SESSIONS = 10

local recording = false
local session = nil
local sessionStart = 0
local pendingTooltips = {}

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
	if depth >= 4 then
		return "<truncated>"
	end
	local out = {}
	local count = 0
	for k, v in pairs(value) do
		count = count + 1
		if count > 64 then
			out.__truncated = true
			break
		end
		if SanitizeKey(k) then
			out[k] = "<sanitized>"
		else
			out[k] = CopyValue(v, depth + 1)
		end
	end
	return out
end

function SurvivorUI_RebornRecord(eventType, data)
	if not recording or not session then
		return
	end
	if table.getn(session.events) >= MAX_EVENTS then
		session.truncated = true
		return
	end
	session.seq = session.seq + 1
	table.insert(session.events, {
		seq = session.seq,
		t = math.floor((Now() - sessionStart) * 1000) / 1000,
		run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil,
		type = eventType,
		data = CopyValue(data, 0),
	})
end

local function NewSessionId()
	if date then
		return date("%Y-%m-%d-%H%M%S")
	end
	return "session-" .. tostring(math.floor(Now()))
end

function SurvivorUI_RebornRecordStart()
	local db = DB()
	session = {
		id = NewSessionId(),
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
		events = {},
	}
	sessionStart = Now()
	recording = true
	db.sessions[session.id] = session
	table.insert(db.order, session.id)
	while table.getn(db.order) > MAX_SESSIONS do
		local old = table.remove(db.order, 1)
		db.sessions[old] = nil
	end
	SurvivorUI_RebornRecord("session_start", { run = SurvivorUI_RebornRunId and SurvivorUI_RebornRunId() or nil })
	if SurvivorUI_RebornAbilities then
		local data = SurvivorUI_RebornAbilities()
		SurvivorUI_RebornRecord("abilities_initial", {
			rawAbilities = AZS_ABILITIES, rawSpells = AZS_SPELLS,
			normalized = data.all, source = data.source,
		})
	end
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
end

function SurvivorUI_RebornRecordMark(text)
	SurvivorUI_RebornRecord("mark", { text = text })
end

-- Bounded follow-up tooltip captures after an ability change: the
-- native tooltip may update after the rank does.
function SurvivorUI_RebornRecordTooltipSoon(key)
	if not recording then
		return
	end
	table.insert(pendingTooltips, { key = key, at = Now() + 1, tries = 0 })
end

local timer = CreateFrame and CreateFrame("Frame") or nil
if timer then
	timer:SetScript("OnUpdate", function()
		if not recording or table.getn(pendingTooltips) == 0 then
			return
		end
		local now = Now()
		for i = table.getn(pendingTooltips), 1, -1 do
			local p = pendingTooltips[i]
			if now >= p.at then
				if SurvivorUI_RebornTooltipCapture then
					local ok, lines = pcall(SurvivorUI_RebornTooltipCapture, p.key)
					SurvivorUI_RebornRecord("tooltip", { key = p.key, ok = ok, lines = lines })
				end
				p.tries = p.tries + 1
				if p.tries >= 2 then
					table.remove(pendingTooltips, i)
				else
					p.at = now + 2
				end
			end
		end
	end)
end

-- A session left "active" by a reload or crash is interrupted, not
-- completed; it stays available for export.
local db = DB()
for id, s in pairs(db.sessions) do
	if type(s) == "table" and s.status == "active" then
		s.status = "interrupted"
	end
end
