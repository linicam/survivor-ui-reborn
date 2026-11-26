-- Survivor UI - Copyright (C) 2026 morderous - GPL-3.0 - github.com/morderous/survivor-ui
-- Survivor UI (Reborn fork): Reborn compatibility layer.
--
-- What this file is for: AZ Reborn ships the original game's addon API on
-- top of its own server lines (AzerothSurvivorsAPI, ## Interface: 11200),
-- but several behaviours differ from the original game, and the original
-- SurvivorUI code assumes the original behaviour. This file is the one
-- place that knows about those differences. UI modules (Tracker, BuildList,
-- Jewelry) ask it questions; it never draws anything itself.
--
-- Verified against the official AZ Reborn Addon API
-- (https://azreborn.com/guides/addon-api, read 2026-11-25):
--   * AZS_RUN.nbs / nbm / nb / nbc / nbn / rift drive boss spawning.
--     nbm is "rift" (rift is 0-100; nb is then the latest minute, else -1)
--     or "time" (nb counts down). In Endless nbm is "time", nbn is empty
--     and left is -1. A missing field is missing, never 0; never derive a
--     rift percent from the run clock or from nb.
--   * AZS_ABILITIES is a *requested* snapshot (AZS_RequestAbilities() +
--     AZS.On("AZSABILITIES", ...)) of learned class abilities and selected
--     racials, *including passives*: { key, spell, rank, passive, kind,
--     cd, cdmax, name, icon, text }. kind is "class" or "racial", spell is
--     0 when there is no spell id. It starts empty, clears on AZSZONE /
--     reload, and no request is sent automatically.
--   * AZS_SPELLS ({ key, spell, rank, cd, cdmax }) keeps its action-bar
--     layout only: it is NOT the full learned-ability list.
--   * AZS_GetMeterLoadout() returns a loadout whose data include AZSGEAR;
--     the AZSGEAR row shape is NOT published in the docs, so jewelry
--     parsing here is defensive and every field is probed, never assumed.
--   * AZS_STATS g* fields (ghp, gdmg, gcd, ...) are AGGREGATE jewelry
--     contributions, never per-item effects. They are reported as an
--     aggregate and never attributed to an individual piece.
--   * AZS_ZONE.run is the run id (azs:r<hex>), stable across reload and
--     host handover, new for each run. Run-scoped state is keyed to it.
--   * Tables are replaced on every line: re-read the global each time,
--     never keep a reference; each table has a <TABLE>_UPDATED stamp.
--
-- NOT documented, and therefore NOT invented here:
--   * Per-ability upgrade selections (which card/upgrade was picked, how
--     damage bonuses stack). Only `rank` is exposed. This file tracks
--     rank increases per ability per run and labels them exactly as that:
--     rank history, not upgrade identity.
--   * Curses from cursed chests. The word "curse" does not appear in the
--     official Addon API at all. SurvivorUI_RebornCurses() reports
--     supported = false and the probe lists candidate globals without
--     treating any of them as curse data.
--
-- Debug logging is off by default (SurvivorUIDB.rebornDebug). See
-- /sui reborn ... in SurvivorUI.lua. Nothing here sends addon messages
-- except the documented sync command, and nothing here requests server
-- data every frame: ability requests are throttled to one per 5 seconds
-- at most, loadout refreshes to one per 2 seconds at most.

if SurvivorUI_Standby then return end

local function T(text)
	if SurvivorUI_T then
		return SurvivorUI_T(text)
	end
	return text
end

-- TF(text, a, b, c): SurvivorUI_TF with {1}..{3} filled, or a local
-- substitution when the locale file has not loaded yet (RebornCompat
-- loads before Locale.lua). Only three values: enough for every
-- Reborn string this file owns.
local function TF(text, a, b, c)
	if SurvivorUI_TF then
		return SurvivorUI_TF(text, a, b, c)
	end
	local values = { a, b, c }
	return (string.gsub(T(text), "{(%d)}", function(index)
		local value = values[tonumber(index)]
		return value ~= nil and tostring(value) or ""
	end))
end

-- Run-clock seconds as m:ss, for rank-rise timestamps.
local function FormatRunTime(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 0 then seconds = 0 end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds - math.floor(seconds / 60) * 60)
end

local function Num(v)
	return tonumber(v) or 0
end

local function Field(entry, name, index)
	if type(entry) ~= "table" then
		return nil
	end
	if entry[name] ~= nil then
		return entry[name]
	end
	return entry[index]
end

-- Record the game's own AZSCMD sends so the probe can show how the
-- stock HUD triggers things the API does not describe (account
-- talent actives). Opt-in diagnostics only read this list.
local sentCommands = {}
if hooksecurefunc and SendAddonMessage then
	hooksecurefunc("SendAddonMessage", function(prefix, message)
		if prefix == "AZSCMD" and SurvivorUIDB and SurvivorUIDB.rebornDebug == true then
			table.insert(sentCommands, tostring(message))
			if table.getn(sentCommands) > 12 then
				table.remove(sentCommands, 1)
			end
		end
	end)
end

local function Now()
	if GetTime then
		return GetTime()
	end
	return 0
end

-- Shared per-run caches. Declared here, before any function that touches
-- them, so every reference below is to these locals (Lua resolves
-- upvalues lexically at the point a function is defined).
local abilitiesCache = nil      -- normalised merged ability list
local abilitiesStamp = nil     -- AZS_ABILITIES_UPDATED last seen
local spellsStamp = nil        -- AZS_SPELLS_UPDATED last seen
local abilitiesSeen = {}       -- [key] = true, keys already merged
local lastAbilityRequest = 0
local lastRequestSignature = nil
local lastRecordedSignature = nil
local lastRecordedTexts = {}
local lastRequestCardsStamp = nil
local requestRunId = nil
local abilitiesRequested = false
local rankHistory = {}  -- [key] = { rank, firstSeen, increases }
local rankEvents = {}   -- array of { key, from, to, at }
local jewelryCache = nil
local jewelryStamp = nil
local jewelryError = nil
local lastLoadoutAt = 0
------------------------------------------------------------------------------
-- Detection and run identity

-- True when the Reborn-only signals are present. The original game also
-- exposes AZS_RUN / AZS_SPELLS, so those alone do not prove Reborn; the
-- snapshot ability API and the meter loadout are the Reborn signals, with
-- nbm/rift fields as a fallback. When none of these is present the
-- helpers below return nil / empty and callers keep original behaviour.
function SurvivorUI_RebornActive()
	-- AZS_RequestAbilities is Reborn-only; AZS_GetMeterLoadout also
	-- exists in the original game and proves nothing on its own.
	if AZS_RequestAbilities then
		return true
	end
	local run = AZS_RUN
	if type(run) == "table" and (run.nbm ~= nil or run.nbs ~= nil or run.rift ~= nil) then
		return true
	end
	return false
end

-- The run id, or nil when the game has not told it yet. Older servers
-- saying run=1 are handled by the clock-rewind fallback in callers; here
-- we only report what the game actually says.
function SurvivorUI_RebornRunId()
	if AZS_API_RunId then
		local ok, id = pcall(AZS_API_RunId)
		if ok and id and id ~= "" then
			return tostring(id)
		end
	end
	local zone = AZS_ZONE
	if type(zone) == "table" and zone.run and zone.run ~= "" then
		return tostring(zone.run)
	end
	return nil
end

local lastRunId = nil
local activeCurses = {}
local racialCooldownSample = nil
local seenCurseIds = {}
local curseBoundary = {}
local historyScanStamp = nil
local BannerKey
local capturedBanners = {}
local bannerHandlerRegistered = false
local EnsureBannerHandler
local CaptureAdd
local captureJewelrySignature = nil
local resetWatchers = {}

-- Modules with per-run caches register here; they are called (pcall) when
-- a new run id is first seen. The compat layer's own caches reset first.
function SurvivorUI_RebornRegisterReset(fn)
	if type(fn) == "function" then
		table.insert(resetWatchers, fn)
		-- Catch-up: a watcher registered after the current run was
		-- already observed (load order) still gets its reset once.
		if lastRunId ~= nil then
			pcall(fn)
		end
	end
end

local function ResetOwnCaches()
	abilitiesCache = nil
	abilitiesStamp = nil
	spellsStamp = nil
	abilitiesSeen = {}
	lastAbilityRequest = 0
	lastRequestSignature = nil
	lastRequestCardsStamp = nil
	requestRunId = nil
	abilitiesRequested = false
	rankHistory = {}
	rankEvents = {}
	jewelryCache = nil
	jewelryStamp = nil
	jewelryError = nil
	lastLoadoutAt = 0
	activeCurses = {}
	racialCooldownSample = nil
	seenCurseIds = {}
	historyScanStamp = nil
	-- Run boundary: banner IDs are not guaranteed monotonic across
	-- runs, so record the identity of every banner retained at the
	-- boundary instead of a numeric watermark. History scans skip
	-- those identities and any banner timestamped after the new
	-- run's clock; live handler events bypass the boundary.
	curseBoundary = {}
	if type(AZS_BANNERS) == "table" then
		for i = 1, table.getn(AZS_BANNERS) do
			curseBoundary[BannerKey(AZS_BANNERS[i])] = true
		end
	end
end

-- Call on every draw / poll that already runs: cheap (one string compare).
-- Returns true when a new run started in this call.
function SurvivorUI_RebornCheckRun()
	EnsureBannerHandler()
	local id = SurvivorUI_RebornRunId()
	if id and id ~= lastRunId then
		local first = lastRunId == nil
		lastRunId = id
		if CaptureAdd then CaptureAdd("run transition -> " .. tostring(id)) end
		if SurvivorUI_RebornRecord then
			SurvivorUI_RebornRecord("run_transition", { to = id, first = first })
		end
		ResetOwnCaches()
		if not first then
			for _, fn in pairs(resetWatchers) do
				pcall(fn)
			end
			if SurvivorUI_RebornRecord then
				SurvivorUI_RebornRecord("reset_watchers", { count = table.getn(resetWatchers) })
			end
		end
		return true
	end
	-- Leaving a run: no run id and the game no longer reports a
	-- playing run. Clear run-specific state so the lobby and the
	-- next run never inherit it. A transient missing id mid-run
	-- (ph still "playing") does not reset.
	if not id and lastRunId ~= nil then
		local run = AZS_RUN
		if not (type(run) == "table" and run.ph == "playing") then
			lastRunId = nil
			ResetOwnCaches()
			for _, fn in pairs(resetWatchers) do
				pcall(fn)
			end
			return true
		end
	end
	return false
end

-- For tests / manual reset: forget the current run id so the next check
-- treats the run as new. Does not touch SavedVariables.
function SurvivorUI_RebornForgetRun()
	lastRunId = nil
	ResetOwnCaches()
end

------------------------------------------------------------------------------
-- Debug logging (opt-in, off by default, never spams chat when off)

function SurvivorUI_RebornDebugEnabled()
	return SurvivorUIDB and SurvivorUIDB.rebornDebug == true
end

function SurvivorUI_RebornDebug(...)
	if not SurvivorUI_RebornDebugEnabled() then
		return
	end
	if not DEFAULT_CHAT_FRAME then
		return
	end
	local parts = {}
	local args = { ... }
	for i = 1, table.getn(args) do
		table.insert(parts, tostring(args[i]))
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff8a8a8a[Reborn]|r "..table.concat(parts, " "))
end

function SurvivorUI_RebornSetDebug(on)
	SurvivorUIDB = SurvivorUIDB or {}
	SurvivorUIDB.rebornDebug = on and true or false
end

------------------------------------------------------------------------------
-- Boss progression: AZS_RUN.nbs / nbm / nb / rift / nbc / nbn
--
-- Returns nil when the game has told us nothing Reborn-specific about the
-- next boss (callers then keep the schedule behaviour). Otherwise a table:
--   { mode, state, name, number, rift, countdown, atLatestMinute }
-- mode is one of "rift" | "time" | "up" | "none".
-- rift is nil when the field is absent (missing is not 0); countdown is
-- nil when nb is -1 / absent. Never derive a percent from the clock.

function SurvivorUI_RebornNextBoss()
	local run = AZS_RUN
	if type(run) ~= "table" then
		return nil
	end
	local nbs = run.nbs
	local nbm = run.nbm
	if nbs == nil and nbm == nil and run.rift == nil and run.nb == nil then
		return nil
	end
	local out = {
		state = nbs,
		name = (run.nbn ~= nil and run.nbn ~= "") and run.nbn or nil,
		number = run.nbc ~= nil and Num(run.nbc) or nil,
		rift = nil,
		countdown = nil,
		atLatestMinute = nil,
	}
	if nbs == "none" then
		out.mode = "none"
		return out
	end
	if nbs == "up" then
		out.mode = "up"
		return out
	end
	if nbm == "rift" then
		out.mode = "rift"
		-- Distinguish absent from 0: rift == 0 at the start of a run is real.
		if run.rift ~= nil then
			out.rift = Num(run.rift)
		end
		if run.nb ~= nil and Num(run.nb) >= 0 then
			out.atLatestMinute = Num(run.nb)
		end
		return out
	end
	if nbm == "time" then
		out.mode = "time"
		if run.nb ~= nil and Num(run.nb) >= 0 then
			out.countdown = Num(run.nb)
		end
		return out
	end
	-- nbm empty / unknown but nb counts down: treat as time, as Endless
	-- does; if nb is -1 / absent there is nothing to count down.
	if run.nb ~= nil and Num(run.nb) >= 0 then
		out.mode = "time"
		out.countdown = Num(run.nb)
		return out
	end
	-- Known boss with a name but no mode/countdown: the schedule row (if
	-- any) is the only timing source; report it as schedule-driven.
	if nbs == "known" then
		out.mode = "schedule"
		return out
	end
	return out
end

-- Display text for the next boss, for the tracker / dial. seconds is the
-- run clock (only used to sanity-check a countdown, never to invent a
-- rift percent). Returns text, isRift.
function SurvivorUI_RebornNextBossText(nextBoss)
	if not nextBoss then
		return nil, false
	end
	if nextBoss.mode == "rift" then
		if nextBoss.rift ~= nil then
			return string.format("%d%%", math.floor(nextBoss.rift + 0.5)), true
		end
		return "", true
	end
	if nextBoss.mode == "time" then
		if nextBoss.countdown ~= nil then
			local s = nextBoss.countdown
			return string.format("in %d:%02d", math.floor(s / 60), s - math.floor(s / 60) * 60), false
		end
		return "Next boss", false
	end
	if nextBoss.mode == "up" then
		return "Boss up", false
	end
	if nextBoss.mode == "none" then
		return nil, false
	end
	return nil, false
end

-- The schedule's next due row, if any (re-reads AZS_SCHEDULE every call;
-- the game replaces the table on every line).
function SurvivorUI_RebornScheduleNext()
	local schedule = AZS_SCHEDULE
	if type(schedule) ~= "table" then
		return nil, nil
	end
	for index = 1, table.getn(schedule) do
		local entry = schedule[index]
		if Field(entry, "state", 5) == "due" then
			return entry, index
		end
	end
	return nil, nil
end

-- Bosses alive right now, via the documented getters when present, else
-- AZS_UNITS. Returns an array of { name, hp, hpm, final, enraged }.
function SurvivorUI_RebornLiveBosses()
	local out = {}
	if AZS_GetBosses then
		local ok, bosses = pcall(AZS_GetBosses)
		if ok and type(bosses) == "table" then
			for i = 1, table.getn(bosses) do
				local b = bosses[i]
				if type(b) == "table" then
					table.insert(out, {
						name = Field(b, "name", 2),
						hp = Num(Field(b, "hp", 3)),
						hpm = Num(Field(b, "hpm", 4)),
						final = Field(b, "final", 5) == true or Num(Field(b, "final", 5)) == 1,
						enraged = Field(b, "enraged", 6) == true or Num(Field(b, "enraged", 6)) == 1,
					})
				end
			end
			return out
		end
	end
	-- Fallback: AZS_UNITS { kind, id, name, hp, hpm, state }.
	local units = AZS_UNITS
	if type(units) == "table" then
		for i = 1, table.getn(units) do
			local u = units[i]
			local kind = Field(u, "kind", 1)
			if kind == "boss" or kind == "final" or kind == "rift" then
				table.insert(out, {
					name = Field(u, "name", 3),
					hp = Num(Field(u, "hp", 4)),
					hpm = Num(Field(u, "hpm", 5)),
					final = kind == "final",
					enraged = Num(Field(u, "state", 6)) == 1,
				})
			end
		end
	end
	return out
end

------------------------------------------------------------------------------
-- Abilities: AZS_ABILITIES snapshot merged with AZS_SPELLS
--
-- AZS_ABILITIES is requested, never pushed. Request at most once per 5
-- seconds, on entering the world / zone change / build change, never per
-- frame. The AZSABILITIES handler (registered below when AZS.On exists)
-- refreshes the cache; a stamp poll covers addons where AZS.On is absent.

-- The two sources have different positional schemas and must not
-- share indices: AZS_ABILITIES {key,spell,rank,passive,kind,cd,cdmax,
-- name,icon,text}; AZS_SPELLS {key,spell,rank,cd,cdmax}. Reading a
-- spells row with abilities indices reads its cd as `passive`.
local function NormaliseAbility(entry, fromSpells)
	if type(entry) ~= "table" then
		return nil
	end
	local key = Field(entry, "key", 1)
	if not key or key == "" then
		return nil
	end
	if fromSpells then
		-- Missing stays missing (nil), never zero: a spells row
		-- without a rank must not overwrite snapshot metadata.
		local function NumOrNil(v)
			local n = tonumber(v)
			return n
		end
		return {
			key = key,
			spell = NumOrNil(Field(entry, "spell", 2)),
			rank = NumOrNil(Field(entry, "rank", 3)),
			passive = false,
			kind = nil,
			cd = NumOrNil(Field(entry, "cd", 4)),
			cdmax = NumOrNil(Field(entry, "cdmax", 5)),
			name = nil, icon = nil, text = nil,
			fromSpells = true,
		}
	end
	local passive = Field(entry, "passive", 4)
	return {
		key = key,
		spell = Num(Field(entry, "spell", 2)),
		rank = Num(Field(entry, "rank", 3)),
		passive = passive == true or passive == 1,
		kind = Field(entry, "kind", 5),
		cd = Num(Field(entry, "cd", 6)),
		cdmax = Num(Field(entry, "cdmax", 7)),
		name = Field(entry, "name", 8),
		icon = Field(entry, "icon", 9),
		text = Field(entry, "text", 10),
		fromSpells = false,
	}
end

-- Rebuild the merged cache from the live globals. Field-level merge:
-- identity/name/icon/text/passive/kind from the snapshot (metadata),
-- spell/rank/cd/cdmax from AZS_SPELLS when it carries the ability
-- (the live bar line updates every second; the snapshot is a
-- requested reply and can be older). Order: snapshot order first,
-- then spells-only abilities in bar order.
local function RefreshAbilitiesCache()
	local merged = {}
	local byKey = {}
	local function Add(entry, fromSpells)
		local a = NormaliseAbility(entry, fromSpells)
		if not a then
			return
		end
		local keep = byKey[a.key]
		if not keep then
			byKey[a.key] = a
			table.insert(merged, a)
			return
		end
		if fromSpells then
			if a.spell ~= nil then keep.spell = a.spell end
			if a.rank ~= nil then keep.rank = a.rank end
			if a.cd ~= nil then keep.cd = a.cd end
			if a.cdmax ~= nil then keep.cdmax = a.cdmax end
		end
	end
	local abilities = AZS_ABILITIES
	if type(abilities) == "table" then
		for i = 1, table.getn(abilities) do
			Add(abilities[i], false)
		end
	end
	local spells = AZS_SPELLS
	if type(spells) == "table" then
		for i = 1, table.getn(spells) do
			Add(spells[i], true)
		end
	end
	abilitiesCache = merged
	abilitiesSeen = byKey
	abilitiesStamp = AZS_ABILITIES_UPDATED
	spellsStamp = AZS_SPELLS_UPDATED
	if SurvivorUI_RebornRecord and SurvivorUI_RebornRecording and SurvivorUI_RebornRecording() then
		local parts = {}
		local textChanges = {}
		for i = 1, table.getn(merged) do
			local a = merged[i]
			parts[i] = tostring(a.key) .. "|" .. tostring(a.spell) .. "|" .. tostring(a.rank) ..
				"|" .. tostring(a.passive) .. "|" .. tostring(a.kind) ..
				"|" .. tostring(a.name) .. "|" .. tostring(a.text) ..
				"|" .. tostring(a.cdmax) .. "|" .. tostring(a.icon)
			if lastRecordedTexts[a.key] ~= nil and lastRecordedTexts[a.key] ~= a.text then
				table.insert(textChanges, { key = a.key, from = lastRecordedTexts[a.key], to = a.text, rank = a.rank })
			end
			lastRecordedTexts[a.key] = a.text
		end
		local signature = table.concat(parts, ";")
		if signature ~= lastRecordedSignature then
			lastRecordedSignature = signature
			SurvivorUI_RebornRecord("abilities_update", {
				rawAbilities = AZS_ABILITIES, rawSpells = AZS_SPELLS, normalized = merged,
				textChanges = textChanges,
			})
		end
	end
	TrackRanks(merged)
	for i = 1, table.getn(merged) do
		local a = merged[i]
		if a.kind == "racial" and not a.passive and a.spell and a.spell > 0 then
			racialCooldownSample = {
				spell = a.spell, cd = a.cd or 0, cdmax = a.cdmax or 0,
				atRun = AZS_GetRunTime and AZS_GetRunTime() or 0,
			}
		end
	end
	return merged
end

-- Returns { actives, passives, racials, all, source, complete }.
-- source is "abilities" when the snapshot contributed, "spells" when only
-- the action-bar list was available, "none" when neither has data.
-- complete is true only when the AZS_ABILITIES snapshot is non-empty.
-- Reborn has no racial section: genuine kind="racial" entries are
-- re-homed below by passive/cooldown, never dropped, and `racials` is
-- always empty here (kept only so diagnostics keep their shape).
-- Classification order is deliberate: `passive` first (the boolean
-- signal, cross-checked by cd == 0), then `kind`. Never hit == 0:
-- Demonic Empowerment and Metamorphosis deal no direct hit yet are
-- active (cd 30 / 35). A passive never counts against the 6 active
-- slots; that is enforced by callers rendering passives separately.
-- For a re-homed racial, "has a cooldown" is judged by cdmax (the
-- cooldown the ability has), not cd (the cooldown remaining).
function SurvivorUI_RebornAbilities()
	-- The snapshot table is replaced on every line: re-read it when its
	-- stamp moved, and re-request (throttled) when it is still empty.
	if AZS_ABILITIES_UPDATED ~= abilitiesStamp or AZS_SPELLS_UPDATED ~= spellsStamp then
		RefreshAbilitiesCache()
	elseif not abilitiesCache then
		RefreshAbilitiesCache()
	end
	if (not abilitiesCache or table.getn(abilitiesCache) == 0) and AZS_RequestAbilities then
		SurvivorUI_RebornRequestAbilities(false)
	end
	local all = abilitiesCache or {}
	local actives, passives, racials = {}, {}, {}
	local fromAbilities = false
	if type(AZS_ABILITIES) == "table" and table.getn(AZS_ABILITIES) > 0 then
		fromAbilities = true
	end
	for i = 1, table.getn(all) do
		local a = all[i]
		if a.passive then
			-- A passive is a passive whatever else the snapshot says
			-- about it: Demonic Knowledge (passive, cd 0) lands here
			-- even if a server ever also tagged it racial.
			table.insert(passives, a)
		elseif a.kind == "racial" then
			-- A selected racial, re-homed by cooldown: one with a
			-- cooldown behaves as an active, a cooldown-0 one as a
			-- passive. It is never dropped and never shown in a
			-- dedicated racial section. cdmax is the test, not cd:
			-- cd is the cooldown *remaining* (0 while ready), cdmax
			-- is the cooldown the ability has — Berserking reads
			-- cd 0 / cdmax 60 while ready and is an active.
			if (a.cdmax and a.cdmax > 0) or (a.cd and a.cd > 0) then
				table.insert(actives, a)
			else
				table.insert(passives, a)
			end
		else
			table.insert(actives, a)
		end
	end
	local source = "none"
	if fromAbilities then
		source = "abilities"
	elseif table.getn(all) > 0 then
		source = "spells"
	end
	return {
		actives = actives, passives = passives, racials = racials, all = all,
		source = source, complete = fromAbilities,
	}
end

-- The bar's extra buttons in Reborn: button 7 carries an
-- account-talent active (Divine Steed) and button 12 (the "=" key)
-- the racial active, as the original game places its racial.
-- Reborn's AZS_SPELLS layout leaves both empty, so put the
-- snapshot's extra actives there — only while a button is empty
-- and out of combat, never over the player's own placement.
-- A spellbook entry by its (localized) name: spell id and book
-- index, or nil. The snapshot's racial actives can carry spell 0,
-- while the spellbook always knows the spell itself.
local function SpellbookSpell(name)
	if not name or name == "" or not (GetNumSpellTabs and GetSpellTabInfo and GetSpellName) then
		return nil
	end
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for i = 1, numSpells or 0 do
			local index = offset + i
			if GetSpellName(index, "spell") == name then
				local spellId
				if GetSpellLink then
					local link = GetSpellLink(index, "spell")
					spellId = link and tonumber(string.match(link, "spell:(%d+)"))
				end
				return spellId, index
			end
		end
	end
	return nil
end

local lastPlaceAt = 0
function SurvivorUI_RebornPlaceRacialButton()
	if not SurvivorUI_RebornActive() then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	if not (GetActionInfo and PickupSpell and PlaceAction and ClearCursor) then
		return
	end
	local now = GetTime and GetTime() or 0
	if now - lastPlaceAt < 0.25 then
		return
	end
	lastPlaceAt = now
	local data = SurvivorUI_RebornAbilities()
	if not data.complete then
		return
	end
	local onBar = {}
	for i = 1, table.getn(AZS_SPELLS or {}) do
		onBar[Field(AZS_SPELLS[i], "key", 1)] = true
	end
	local racial
	for i = 1, table.getn(data.actives) do
		local a = data.actives[i]
		if not onBar[a.key] and a.kind == "racial" then
			racial = racial or a
		end
	end
	local function Place(ability, button)
		if not ability then
			return
		end
		local spellId, bookIndex = ability.spell, ability.bookIndex
		if not (spellId and spellId > 0) and not bookIndex then
			spellId, bookIndex = SpellbookSpell(ability.name)
		end
		local icon = ability.icon
		if not icon and bookIndex and GetSpellTexture then
			icon = GetSpellTexture(bookIndex, "spell")
		end
		if SurvivorUI_SetExtraButton then
			SurvivorUI_SetExtraButton(button, (spellId and spellId > 0) and spellId or ability.name, icon)
		end
	end
	if not racial and SurvivorUI_SetExtraButton then
		SurvivorUI_SetExtraButton(12, nil)
	end
	Place(racial, 12)
end

function SurvivorUI_RebornAbilityByKey(key)
	if not key then
		return nil
	end
	local data = SurvivorUI_RebornAbilities()
	for i = 1, table.getn(data.all) do
		if data.all[i].key == key then
			return data.all[i]
		end
	end
	return nil
end

-- Throttled snapshot request. force bypasses the throttle (use only
-- for an explicit user action such as /sui reborn abilities).
-- Build-change detection uses a stable signature of the bar line
-- (key, spell, rank per entry): AZS_SPELLS_UPDATED also moves on
-- cooldown-only lines, which are not build changes. Passive and
-- unslotted upgrades cannot move the bar signature, so a card-line
-- change (AZS_CARDS_UPDATED, when the game sends it) also triggers a
-- request, plus a slow 60s safety refresh while a run is active.
local function BuildSignature()
	local parts = {}
	local spells = AZS_SPELLS
	if type(spells) == "table" then
		for i = 1, table.getn(spells) do
			parts[i] = tostring(Field(spells[i], "key", 1)) .. "|" ..
				tostring(Field(spells[i], "spell", 2)) .. "|" ..
				tostring(Field(spells[i], "rank", 3))
		end
	end
	return table.concat(parts, ";")
end

function SurvivorUI_RebornRequestAbilities(force)
	if not AZS_RequestAbilities then
		return false
	end
	local now = Now()
	local snapshotEmpty = type(AZS_ABILITIES) ~= "table" or table.getn(AZS_ABILITIES) == 0
	local signature = BuildSignature()
	local changed = signature ~= lastRequestSignature
		or (AZS_CARDS_UPDATED ~= nil and AZS_CARDS_UPDATED ~= lastRequestCardsStamp)
	local safetyDue = now - lastAbilityRequest >= 60
	if not force and not snapshotEmpty and not changed and not safetyDue then
		return false
	end
	if not force and now - lastAbilityRequest < 5 then
		return false
	end
	local ok, err = pcall(AZS_RequestAbilities)
	if not ok then
		-- A failed request stays retryable: neither the signature
		-- nor the timestamp advances.
		SurvivorUI_RebornDebug("RequestAbilities failed:", tostring(err))
		return false
	end
	lastAbilityRequest = now
	lastRequestSignature = signature
	lastRequestCardsStamp = AZS_CARDS_UPDATED
	requestRunId = SurvivorUI_RebornRunId()
	abilitiesRequested = true
	if SurvivorUI_RebornRecord then
		SurvivorUI_RebornRecord("abilities_request", { signature = signature, forced = force == true })
	end
	return true
end

function SurvivorUI_RebornAbilitiesRequested()
	return abilitiesRequested
end

-- Register the AZSABILITIES handler as soon as the router exists; if it
-- does not exist yet at load time, the stamp poll in
-- SurvivorUI_RebornAbilities() still picks the snapshot up.
local function RegisterAbilitiesHandler()
	if AZS and AZS.On then
		local ok, err = pcall(AZS.On, "AZSABILITIES", function()
			-- A delayed reply to a previous run's request must not
			-- contaminate the new run: drop it and re-request.
			local current = SurvivorUI_RebornRunId()
			if requestRunId and current and requestRunId ~= current then
				SurvivorUI_RebornRequestAbilities(true)
				return
			end
			RefreshAbilitiesCache()
			SurvivorUI_RebornDebug("AZSABILITIES received:", AZS_ABILITIES and table.getn(AZS_ABILITIES) or 0, "abilities")
		end)
		if ok then
			-- The documented zone line is a reliable run-boundary
			-- signal: drive the reset check from it as well as
			-- from draws.
			pcall(AZS.On, "AZSZONE", function()
				SurvivorUI_RebornCheckRun()
			end)
		end
		if not ok then
			SurvivorUI_RebornDebug("AZS.On(AZSABILITIES) failed:", tostring(err))
		end
	end
end
RegisterAbilitiesHandler()

------------------------------------------------------------------------------
-- Ability rank history (the honest part of "upgrade tracking")
--
-- The API exposes only `rank`. When a rank rises during a run we record
-- it: { key, from, to, at } where `at` is the run clock in seconds.
-- This is NOT an upgrade identity: it cannot say which card was picked,
-- what the upgrade's effect text was, or how bonuses stack, and the UI
-- must say so. Rank history resets with the run id.

function TrackRanks(merged)
	if type(merged) ~= "table" then
		return
	end
	local seconds = 0
	if AZS_GetRunTime then
		local ok, t = pcall(AZS_GetRunTime)
		if ok then seconds = Num(t) end
	end
	if seconds == 0 and type(AZS_RUN) == "table" then
		seconds = Num(AZS_RUN.t)
	end
	for i = 1, table.getn(merged) do
		local a = merged[i]
		if a and a.key then
			local prev = rankHistory[a.key]
			if not prev then
				rankHistory[a.key] = { rank = a.rank, firstSeen = seconds, increases = 0 }
				if SurvivorUI_RebornRecordTooltipSoon then
					SurvivorUI_RebornRecordTooltipSoon(a.key, "baseline")
				end
			elseif a.rank > prev.rank then
				table.insert(rankEvents, { key = a.key, from = prev.rank, to = a.rank, at = seconds })
				if CaptureAdd then CaptureAdd(string.format("rank %s %s -> %s at %s", tostring(a.key), tostring(prev.rank), tostring(a.rank), tostring(seconds))) end
				if SurvivorUI_RebornRecord then
					SurvivorUI_RebornRecord("rank_change", { key = a.key, from = prev.rank, to = a.rank, at = seconds })
					if SurvivorUI_RebornRecordTooltipSoon then
						SurvivorUI_RebornRecordTooltipSoon(a.key)
					end
				end
				prev.rank = a.rank
				prev.increases = prev.increases + 1
			elseif a.rank < prev.rank then
				-- A lower rank than seen before (new run the reset missed,
				-- or a respec): restart this ability's history, do not
				-- count it as an upgrade.
				rankHistory[a.key] = { rank = a.rank, firstSeen = seconds, increases = 0 }
			end
		end
	end
end

function SurvivorUI_RebornRankEvents()
	return rankEvents
end

function SurvivorUI_RebornRankIncreases(key)
	local h = key and rankHistory[key]
	return h and h.increases or 0
end

-- The rank rises observed for one ability this run, in order:
-- { key, from, to, at } with `at` the run clock in seconds. Only rises
-- the addon actually saw are returned; after a /reload the history
-- before the reload is gone and cannot be recovered.
function SurvivorUI_RebornRankEventsFor(key)
	local out = {}
	if not key then
		return out
	end
	for i = 1, table.getn(rankEvents) do
		if rankEvents[i].key == key then
			table.insert(out, rankEvents[i])
		end
	end
	return out
end

-- Lines for an ability tooltip: base text (from the API, when present),
-- passive flag, and rank. Rank-rise history is deliberately not shown:
-- without the concrete upgrade effects (which the API does not expose)
-- a list of rise timestamps is clutter, not information. The rises are
-- still recorded for diagnostics (SurvivorUI_RebornRankEvents).
function SurvivorUI_RebornAbilityTooltipLines(ability)
	local lines = {}
	if not ability then
		return lines
	end
	if ability.text and ability.text ~= "" then
		table.insert(lines, { text = ability.text, kind = "base" })
	end
	if ability.passive then
		table.insert(lines, { text = T("Passive"), kind = "passive" })
	end
	table.insert(lines, { text = TF("Rank {1}", ability.rank or 0), kind = "rank" })
	return lines
end

------------------------------------------------------------------------------
-- Jewelry: meter loadout first, AZSGEAR second, inventory last
--
-- AZS_GetMeterLoadout({ apiVersion=1, runId, ownerId }) returns
-- loadout.runJewelry = { { sourceKey } } and loadout.sources[sourceKey]
-- = { name, ... }. The docs do not publish the source fields, so every
-- field is read defensively from either the entry or its source, and any
-- of name/icon/slot/rank/rarity may be absent. A loadout error is kept
-- (code/message) and reported by diagnostics, never silently swallowed.
-- Refresh at most once per 2 seconds; callers poll already, so this adds
-- no new timer.

local function LoadoutOwner()
	if AZS_GetMeterContext then
		local ok, context = pcall(AZS_GetMeterContext)
		if ok and type(context) == "table" then
			return context.runId, context.localOwnerId or context.ownerId or context.heroId or context.owner
		end
	end
	return nil, nil
end

-- fields is an array of candidate field names, tried in order, source
-- first then entry. (An explicit array, not ..., so this works the same
-- under Lua 5.1 and later versions.)
local function SourceField(source, entry, fields)
	if type(source) == "table" then
		for i = 1, table.getn(fields) do
			if source[fields[i]] ~= nil then return source[fields[i]] end
		end
	end
	if type(entry) == "table" then
		for i = 1, table.getn(fields) do
			if entry[fields[i]] ~= nil then return entry[fields[i]] end
		end
	end
	return nil
end

-- The slot word for a jewelry piece, localized. The source id is
-- tried first: the docs say source ids are "jewel:<slot>", and in
-- practice the payload often carries no slot/kind/type word at all,
-- which is how every piece used to fall back to "Jewelry". The
-- slot/kind/type fields are the fallback; "Jewelry" is the last
-- resort, never an invented slot. Returns the localized word.
local function SlotLabelOf(raw, sourceKey)
	if sourceKey then
		local _, _, word = string.find(tostring(sourceKey), "^jewel:([%a]+)")
		if word then
			local w = string.lower(word)
			if w == "neck" or w == "amulet" or w == "necklace" then return T("Neck") end
			if w == "ring" then return T("Ring") end
			if w == "trinket" then return T("Trinket") end
		end
	end
	if raw and raw ~= "" then
		local s = string.lower(tostring(raw))
		if string.find(s, "neck") or string.find(s, "amulet") then return T("Neck") end
		if string.find(s, "ring") then return T("Ring") end
		if string.find(s, "trinket") then return T("Trinket") end
	end
	return T("Jewelry")
end

-- The dedup key for one normalised piece, in priority order: the
-- sourceKey (one worn slot holds one piece, so a repeated sourceKey
-- is the same piece acquired again), else the entry's own key/id,
-- else (name, slot) as a last resort. Never the name alone: two
-- pieces can share a name, and two pieces can share every displayed
-- label except the name.
local function DedupKeyOf(sourceKey, key, name, slot)
	if sourceKey and sourceKey ~= "" then
		return "src:" .. tostring(sourceKey)
	end
	if key and key ~= "" then
		return "key:" .. tostring(key)
	end
	if name and name ~= "" and slot and slot ~= "" then
		return "name:" .. tostring(name) .. "|" .. tostring(slot)
	end
	return nil
end

-- A jewelry icon as a texture path. The loadout's source icon is a
-- table (seen in game 2026-11-26), not a path string; read the path
-- out of it defensively, and only accept a string that looks like a
-- texture path.
local function IconTextureOf(icon)
	if type(icon) == "string" then
		return icon
	end
	if type(icon) ~= "table" then
		return nil
	end
	-- Deterministic field lookup: a candidate array with nil holes
	-- would make table.getn() stop before later valid fields.
	local function Candidate(value)
		if type(value) == "string" and (string.find(value, "\\", 1, true) or string.find(value, "^Interface")) then
			return value
		end
		return nil
	end
	return Candidate(icon.texture) or Candidate(icon.path) or Candidate(icon.icon)
		or Candidate(icon.file) or Candidate(icon[1])
end

local function NormaliseJewelryEntry(entry, source)
	local name = SourceField(source, entry, { "name", "displayName" })
	local icon = IconTextureOf(SourceField(source, entry, { "icon", "texture" }))
	local slot = SourceField(source, entry, { "slot", "kind", "type", "category" })
	local sourceKey = entry and entry.sourceKey or nil
	local key = SourceField(nil, entry, { "sourceKey", "key", "id" })
	local rank = SourceField(source, entry, { "rank", "level", "lvl" })
	local rarity = SourceField(source, entry, { "rarity", "quality" })
	if type(rarity) == "number" then
		rarity = tostring(rarity)
	end
	-- Roman rank suffix in the name ("Band of Accuria IV") as a fallback.
	if not rank and name then
		local _, _, r = string.find(name, " ([IVXL]+%+?)$")
		if r then rank = r end
	end
	local slotLabel = SlotLabelOf(slot, sourceKey)
	return {
		name = name, icon = icon, slot = slotLabel,
		slotRaw = slot, key = key, rank = rank, rarity = rarity,
		sourceKey = key, count = 1,
		instanceKey = entry and entry.itemInstanceKey or nil,
		dedupKey = DedupKeyOf(sourceKey, key, name, slotLabel),
	}
end

-- Identity: itemInstanceKey identifies a distinct owned piece
-- (verified in-game payloads carry one per runJewelry entry), so
-- distinct instances always stay distinct rows — a shared meter
-- sourceKey (jewel:<slot>) is attribution, not identity. Records
-- without an instance key merge only when they agree on identity
-- key, name, and rank (duplicate API records); differing ranks
-- stay separate rather than inheriting the highest rank.
-- Returns the merged list and the number of entries merged away.
local function DedupJewelryItems(items)
	local seen, out, merged = {}, {}, 0
	for i = 1, table.getn(items) do
		local item = items[i]
		local key
		if item.instanceKey then
			key = "inst:" .. tostring(item.instanceKey)
		elseif item.dedupKey then
			key = item.dedupKey .. "|" .. tostring(item.name) .. "|" .. tostring(item.rank)
		end
		if key and seen[key] then
			local keep = seen[key]
			if not keep.icon and item.icon then keep.icon = item.icon end
			if not keep.rarity and item.rarity then keep.rarity = item.rarity end
			merged = merged + 1
		else
			if key then seen[key] = item end
			table.insert(out, item)
		end
	end
	return out, merged
end

-- Returns { items, source, error, aggregate }.
-- source: "loadout" | "gear" | "inventory" | "none".
-- aggregate: the AZS_STATS g* shares (whole-character jewelry totals),
-- or nil. Callers must display the aggregate separately and must never
-- attribute it to a single piece.
function SurvivorUI_RebornJewelry(force)
	local now = Now()
	if not force and jewelryCache and now - lastLoadoutAt < 2 then
		return jewelryCache
	end
	lastLoadoutAt = now
	local items = {}
	local source = "none"
	local err = nil
	local rawJewelry = nil
	local preDedup = nil
	-- 1. Meter loadout (documented entry point; shape probed, not assumed).
	if AZS_GetMeterLoadout then
		local runId, ownerId = LoadoutOwner()
		local request = { apiVersion = 1 }
		if runId then request.runId = runId end
		if ownerId then request.ownerId = ownerId end
		local ok, loadout, loadoutErr = pcall(AZS_GetMeterLoadout, request)
		if ok and type(loadout) == "table" then
			local runJewelry = loadout.runJewelry
			rawJewelry = { runJewelry = runJewelry, sources = loadout.sources }
			if type(runJewelry) == "table" then
				-- Authoritative even when empty: an empty in-run
				-- list must not fall back to permanent equipment.
				source = "loadout"
				for i = 1, table.getn(runJewelry) do
					local entry = runJewelry[i]
					local src = nil
					if type(loadout.sources) == "table" and entry and entry.sourceKey then
						src = loadout.sources[entry.sourceKey]
					end
					local item = NormaliseJewelryEntry(entry, src)
					if item.name or item.key then
						table.insert(items, item)
					end
				end
			end
		elseif ok and loadout == nil and type(loadoutErr) == "table" then
			err = loadoutErr
			jewelryError = loadoutErr
		elseif not ok then
			err = { code = "call_failed", message = tostring(loadout) }
			jewelryError = err
		end
	end
	-- 2. AZSGEAR global, if the game exposes it (undocumented shape).
	if source == "none" and type(AZSGEAR) == "table" and table.getn(AZSGEAR) > 0 then
		for i = 1, table.getn(AZSGEAR) do
			local item = NormaliseJewelryEntry(AZSGEAR[i], nil)
			if item.name or item.key then
				table.insert(items, item)
			end
		end
		if table.getn(items) > 0 then
			source = "gear"
		end
	end
	-- Dedup: one row per piece, repeats counted, never by name alone.
	local duplicates = 0
	preDedup = items
	items, duplicates = DedupJewelryItems(items)
	-- 3. Aggregate jewelry shares from AZS_STATS (never per-item).
	local aggregate = nil
	if type(AZS_STATS) == "table" then
		local fields = { "ghp", "gdmg", "gcd", "gcrit", "gcm", "garm", "garea", "gcnt", "gecho", "gspd", "greg", "gpick", "ggold" }
		for i = 1, table.getn(fields) do
			local v = AZS_STATS[fields[i]]
			if v ~= nil and Num(v) ~= 0 then
				aggregate = aggregate or {}
				aggregate[fields[i]] = Num(v)
			end
		end
	end
	jewelryCache = { items = items, source = source, error = err, aggregate = aggregate, duplicates = duplicates }
	if CaptureAdd then
		local parts = {}
		for i = 1, table.getn(items) do
			parts[i] = tostring(items[i].instanceKey or items[i].key) .. ":" .. tostring(items[i].rank) ..
				":" .. tostring(items[i].name) .. ":" .. tostring(items[i].rarity) .. ":" .. tostring(items[i].icon)
		end
		local signature = table.concat(parts, ";")
		if signature ~= captureJewelrySignature then
			captureJewelrySignature = signature
			CaptureAdd("jewelry now: " .. signature)
			if SurvivorUI_RebornRecord then
				SurvivorUI_RebornRecord("jewelry_update", {
					source = source, raw = rawJewelry, gear = AZSGEAR,
					preDedup = preDedup, items = items,
					aggregate = aggregate, duplicates = duplicates,
				})
			end
		end
	end
	jewelryStamp = AZSGEAR_UPDATED
	return jewelryCache
end

function SurvivorUI_RebornJewelryError()
	return jewelryError
end

-- In-run jewelry is per-run: forget the loadout cache on a new run so a
-- stale list can never leak into the next run.
SurvivorUI_RebornRegisterReset(function()
	jewelryCache = nil
	jewelryError = nil
	lastLoadoutAt = 0
end)

------------------------------------------------------------------------------
-- Curses (verified in game 2026-11-26): a curse effect arrives as a
-- banner with kind="curse" whose text is Russian server text
-- ("Проклятие тяготеет над тобой: <effect> (<N> с)!"), and the effect
-- itself sits in AZS_BUFFS (spell + left) while it runs. The chest
-- announcement shares kind="curse" but carries no effect. Track the
-- latest effect banner, translate its effect, and count down from
-- the buff when one is present.
-- Stable internal effect identifiers: acquisitions and endings are
-- matched by ID, never by localized display text.
local function CurseEffectId(text)
	local pct = string.match(text, "(%d+)%%")
	if string.find(text, "精英正在伏击", 1, true) then
		return "elite_ambush", nil, true
	end
	if string.find(text, "ты получаешь на", 1, true) and string.find(text, "больше урона", 1, true) then
		return "damage_taken", pct, false
	end
	if string.find(text, "получаемый урон", 1, true) or string.find(text, "урон по вам", 1, true) then
		return "damage_taken", pct, false
	end
	if string.find(text, "исцеление", 1, true) or string.find(text, "лечение", 1, true) then
		return "healing_reduced", pct, false
	end
	if string.find(text, "скорость врагов", 1, true) or string.find(text, "враги быстрее", 1, true) then
		return "enemy_speed", pct, false
	end
	if string.find(text, "орда", 1, true) then
		return "horde_surge", pct, false
	end
	pct = string.match(text, "урон снижен на (%d+)%%")
	if pct then
		return "damage_reduced", pct, false
	end
	pct = string.match(text, "скорость снижена на (%d+)%%")
	if pct then
		return "movement_reduced", pct, false
	end
	pct = string.match(text, "перезарядка увеличена на (%d+)%%")
	if pct then
		return "cooldown_increased", pct, false
	end
	return nil, nil, false
end

local CURSE_DISPLAY = {
	horde_surge = "Horde surges ",
	damage_taken = "Damage taken increased ",
	healing_reduced = "Healing reduced ",
	enemy_speed = "Enemy speed increased ",
	damage_reduced = "Damage reduced ",
	movement_reduced = "Movement speed reduced ",
	cooldown_increased = "Cooldowns increased ",
	elite_ambush = "Elite ambush",
}

local function CurseEffectDisplay(id, pct)
	local key = id and CURSE_DISPLAY[id] or nil
	if not key then
		return nil
	end
	return T(key) .. (pct and (pct .. "%") or "")
end

local function CurseEffectText(text)
	local id, pct = CurseEffectId(text)
	return CurseEffectDisplay(id, pct)
end

-- Explicit ending banners observed in game: "涌动平息了。" ends the
-- horde surge; "你的脆弱消退了。" ends damage taken. Endings clear
-- the matching tracked curse immediately; the duration estimate is
-- only a fallback when no ending banner is observed.
local CURSE_ENDINGS = {
	{ "涌动平息", "horde_surge" },
	{ "脆弱消退", "damage_taken" },
}

local function CurseEndingId(text)
	for i = 1, table.getn(CURSE_ENDINGS) do
		if string.find(text, CURSE_ENDINGS[i][1], 1, true) then
			return CURSE_ENDINGS[i][2]
		end
	end
	return nil
end

local function CurseDuration(text)
	local minutes = tonumber(string.match(text, "%((%d+)%s*мин"))
	if minutes then
		return minutes * 60
	end
	return tonumber(string.match(text, "%((%d+)")) or 0
end

local function DumpBannerValue(value, depth)
	if type(value) ~= "table" then
		return tostring(value)
	end
	if depth >= 2 then
		return "{...}"
	end
	local parts = {}
	for k, v in pairs(value) do
		table.insert(parts, tostring(k) .. "=" .. DumpBannerValue(v, depth + 1))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

BannerKey = function(banner)
	-- IDs are not guaranteed unique across runs: identity is the
	-- composite of id, kind, timestamp, and text.
	return tostring(Field(banner, "id", 1)) .. "|" .. tostring(Field(banner, "kind", 2)) ..
		"|" .. tostring(Field(banner, "time", 6)) .. "|" .. tostring(Field(banner, "text", 5))
end

local function LatchCurseBanner(banner, fromHistory)
	if type(banner) ~= "table" then
		return
	end
	local key = BannerKey(banner)
	if fromHistory and curseBoundary[key] then
		return
	end
	local isCurseKind = Field(banner, "kind", 2) == "curse"
	-- Dedup every curse-kind banner identity (acquisitions, endings,
	-- announcements) before recording or processing it again.
	if isCurseKind and seenCurseIds[key] then
		return
	end
	local text = Field(banner, "text", 5) or ""
	local effectId, pct, eventBased = CurseEffectId(text)
	local isAcquisition = isCurseKind and (string.find(text, "Проклятие", 1, true)
		or string.find(text, "诅咒降临", 1, true))
	if isAcquisition or SurvivorUI_RebornDebugEnabled() then
		table.insert(capturedBanners, DumpBannerValue(banner, 0))
		if table.getn(capturedBanners) > 20 then
			table.remove(capturedBanners, 1)
		end
	end
	if not isAcquisition then
		if isCurseKind then
			seenCurseIds[key] = true
			local endingId = CurseEndingId(text)
			if endingId then
				local endingAt = tonumber(Field(banner, "time", 6))
				local remaining = {}
				for i = 1, table.getn(activeCurses) do
					local curse = activeCurses[i]
					local beforeEnding = not endingAt or not curse.atBanner or curse.atBanner <= endingAt
					if curse.effectId ~= endingId or not beforeEnding then
						table.insert(remaining, curse)
					end
				end
				activeCurses = remaining
				if SurvivorUI_RebornRecord then
					SurvivorUI_RebornRecord("curse_banner", { raw = banner, decision = "ending", effect = CurseEffectDisplay(endingId), effectId = endingId })
				end
				return
			end
			if SurvivorUI_RebornRecord then
				SurvivorUI_RebornRecord("curse_banner", { raw = banner, decision = "announcement" })
			end
		end
		return
	end
	seenCurseIds[key] = true
	if CaptureAdd then CaptureAdd("curse banner: " .. DumpBannerValue(banner, 0)) end
	local duration = CurseDuration(text)
	if eventBased then
		duration = nil
	end
	if SurvivorUI_RebornRecord then
		SurvivorUI_RebornRecord("curse_banner", {
			raw = banner, buffs = AZS_BUFFS, effect = CurseEffectDisplay(effectId, pct),
			effectId = effectId, duration = duration,
		})
	end
	-- Banner timestamps live on the session (GetTime) clock, while
	-- AZS_GetRunTime is the run clock excluding pauses; never
	-- subtract across domains. Countdowns measure run time from
	-- the moment the banner is latched.
	local runNow = AZS_GetRunTime and AZS_GetRunTime() or nil
	table.insert(activeCurses, {
		id = Field(banner, "id", 1), text = text, effectId = effectId, pct = pct,
		atRun = runNow or 0,
		atBanner = tonumber(Field(banner, "time", 6)),
		duration = duration,
	})
end

EnsureBannerHandler = function()
	if bannerHandlerRegistered then
		return
	end
	if AZS_RegisterBannerHandler then
		local ok = pcall(AZS_RegisterBannerHandler, LatchCurseBanner)
		if ok then
			bannerHandlerRegistered = true
		end
	end
end

function SurvivorUI_RebornCurses()
	local items = {}
	if SurvivorUI_RebornActive() then
		EnsureBannerHandler()
		local now = AZS_GetRunTime and AZS_GetRunTime() or nil
		if type(AZS_BANNERS) == "table" then
			-- Skip rescanning unchanged history: the stamp is the
			-- table identity, length, and last banner identity.
			local n = table.getn(AZS_BANNERS)
			local stamp = tostring(AZS_BANNERS) .. ":" .. n .. ":" ..
				(n > 0 and BannerKey(AZS_BANNERS[n]) or "")
			if stamp ~= historyScanStamp then
				historyScanStamp = stamp
				for i = 1, n do
					LatchCurseBanner(AZS_BANNERS[i], true)
				end
			end
		end
		if now then
			local alive = {}
			for i = 1, table.getn(activeCurses) do
				local curse = activeCurses[i]
				local left = nil
				local expired = false
				if curse.duration and curse.duration > 0 then
					left = curse.duration - (now - (curse.atRun or now))
					if left > curse.duration then
						left = curse.duration
					end
					if left <= 0 then
						expired = true
					end
				end
				if not expired then
					table.insert(alive, curse)
					-- Unknown effects keep their original text
					-- rather than a generic label.
					table.insert(items, { text = CurseEffectDisplay(curse.effectId, curse.pct) or curse.text, left = left, raw = curse.text, effectId = curse.effectId })
				end
			end
			activeCurses = alive
		end
	end
	return {
		supported = true,
		items = items,
		reason = "Curse effects arrive as kind=\"curse\" banners (AZS_RegisterBannerHandler, verified in game 2026-11-26). Banners are not retold after a reload, so curses taken before a reload cannot be reconstructed.",
	}
end

-- Racial active cooldown from verified Reborn snapshot data
-- (cd/cdmax in AZS_ABILITIES; sessions 002/003 show cd as the
-- remaining cooldown at sample time). GetSpellCooldown does not
-- cover the auto-cast racial (it is not a spellbook spell), so the
-- overlay interpolates locally from the latest sample on the run
-- clock. Activation between snapshots resyncs at the next snapshot.
function SurvivorUI_RebornRacialCooldown(spell)
	local sample = racialCooldownSample
	if not sample or (spell and sample.spell ~= spell) then
		return nil, nil
	end
	if not sample.cdmax or sample.cdmax <= 0 then
		return nil, nil
	end
	local now = AZS_GetRunTime and AZS_GetRunTime() or sample.atRun
	local remaining = sample.cd - (now - sample.atRun)
	if remaining < 0 then
		remaining = 0
	end
	if remaining > sample.cdmax then
		remaining = sample.cdmax
	end
	return remaining, sample.cdmax
end

------------------------------------------------------------------------------
-- Diagnostics / probe

-- Opt-in diagnostic capture session: bounded (200 lines), records
-- state changes only (run transitions, rank changes, jewelry
-- changes, curse banners), never per-frame data. Disabled unless
-- started with /sui reborn capture start.
local captureActive = false
local captureLines = {}

CaptureAdd = function(text)
	if SurvivorUI_RebornRecord then
		SurvivorUI_RebornRecord("capture_note", { text = text })
	end
	if not captureActive then
		return
	end
	table.insert(captureLines, text)
	if table.getn(captureLines) > 200 then
		table.remove(captureLines, 1)
	end
end

function SurvivorUI_RebornCaptureNote(text)
	CaptureAdd(text)
end

function SurvivorUI_RebornCaptureStart()
	captureActive = true
	captureLines = {}
	captureJewelrySignature = nil
	CaptureAdd("capture start run=" .. tostring(SurvivorUI_RebornRunId()))
	local data = SurvivorUI_RebornAbilities()
	for i = 1, table.getn(data.all) do
		local a = data.all[i]
		CaptureAdd(string.format("ability key=%s spell=%s rank=%s passive=%s",
			tostring(a.key), tostring(a.spell), tostring(a.rank), tostring(a.passive)))
	end
	local jew = SurvivorUI_RebornJewelry(true)
	for i = 1, table.getn(jew.items) do
		local item = jew.items[i]
		CaptureAdd(string.format("jewelry slot=%s name=%s rank=%s inst=%s",
			tostring(item.slot), tostring(item.name), tostring(item.rank), tostring(item.instanceKey)))
	end
end

function SurvivorUI_RebornCaptureStop()
	captureActive = false
end

function SurvivorUI_RebornCaptureLines()
	local out = {}
	for i = 1, table.getn(captureLines) do
		table.insert(out, captureLines[i])
	end
	if table.getn(out) == 0 then
		table.insert(out, "capture: empty (start with /sui reborn capture start)")
	end
	return out
end

-- Native tooltip capture (upgrade investigation): the original game
-- wrote selected upgrades into the button tooltip itself. Dump the
-- raw native lines for slotted abilities (and spellbook lines where
-- the client supports them) so a capture before/after an upgrade
-- choice shows whether Reborn's tooltips carry upgrade sections.
local tooltipScan = nil
local tooltipCaptures = {}

local function ResolveActionSlot(key)
	local spells = AZS_SPELLS or {}
	local count = table.getn(spells)
	for index = 1, count do
		if Field(spells[index], "key", 1) == key then
			return index
		end
	end
	local ability = SurvivorUI_RebornAbilityByKey(key)
	if ability and not ability.passive and ability.kind == "racial" then
		return 12, true
	end
	return nil
end

-- Structured native tooltip reader shared by the manual diagnostic
-- command and the automated recorder. Returns complete snapshots;
-- formatting for chat happens in SurvivorUI_RebornTooltipCapture.
function SurvivorUI_RebornDedupJewelry(items)
	return DedupJewelryItems(items)
end

function SurvivorUI_RebornTooltipRead(key)
	local ability = SurvivorUI_RebornAbilityByKey(key)
	if not ability then
		return { key = key, ok = false, error = "unknown ability" }
	end
	local slot, overlay = ResolveActionSlot(key)
	local out = {
		key = ability.key, spell = ability.spell, rank = ability.rank,
		slot = slot, overlay = overlay == true, ok = false,
		run = SurvivorUI_RebornRunId(), lines = {},
	}
	if not CreateFrame then
		out.error = "CreateFrame unavailable"
		return out
	end
	if not tooltipScan then
		tooltipScan = CreateFrame("GameTooltip", "SurvivorUIRebornTooltipScan", nil, "GameTooltipTemplate")
	end
	local scan = tooltipScan
	local function ReadLines(source)
		local name = scan:GetName()
		local count = scan.NumLines and scan:NumLines() or 0
		out.numLines = count
		out.source = source
		for i = 1, count do
			local left = _G[name .. "TextLeft" .. i]
			local right = _G[name .. "TextRight" .. i]
			local lt = left and left:GetText()
			local rt = right and right:GetText()
			if (lt and lt ~= "") or (rt and rt ~= "") then
				local entry = { left = lt, right = rt }
				if left and left.GetTextColor then
					local r, g, b = left:GetTextColor()
					entry.color = { r, g, b }
				end
				table.insert(out.lines, entry)
			end
		end
	end
	if slot and not overlay and scan.SetAction then
		if GetActionInfo then
			local actionType, actionId = GetActionInfo(slot)
			out.actionType = actionType
			out.actionId = actionId
		end
		local ok, err = pcall(function()
			scan:SetOwner(UIParent, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetAction(slot)
		end)
		if ok then
			ReadLines("action")
			if table.getn(out.lines) == 0 then
				out.error = "empty action tooltip"
			elseif out.actionId and ability.spell and ability.spell > 0 and out.actionId ~= ability.spell then
				out.error = "action identity mismatch"
			else
				out.ok = true
			end
		else
			out.error = tostring(err)
		end
	elseif ability.spell and ability.spell > 0 and scan.SetSpellByID then
		local ok, err = pcall(function()
			scan:SetOwner(UIParent, "ANCHOR_NONE")
			scan:ClearLines()
			scan:SetSpellByID(ability.spell)
		end)
		if ok then
			ReadLines("spell")
			if table.getn(out.lines) == 0 then
				out.error = "empty spell tooltip"
			else
				out.ok = true
			end
		else
			out.error = tostring(err)
		end
	else
		out.error = overlay and "overlay button has no native action tooltip" or "no tooltip API available"
	end
	scan:Hide()
	return out
end

function SurvivorUI_RebornTooltipCapture(target)
	local lines = {}
	local function Add(text)
		table.insert(lines, text)
	end
	local data = SurvivorUI_RebornAbilities()
	local ability
	local numeric = tonumber(target)
	for i = 1, table.getn(data.all) do
		if data.all[i].key == target or (numeric and ResolveActionSlot(data.all[i].key) == numeric) then
			ability = data.all[i]
			break
		end
	end
	if not ability then
		Add("tooltip: no ability matches '" .. tostring(target) .. "'")
		return lines
	end
	local slot, overlay = ResolveActionSlot(ability.key)
	Add(string.format("tooltip ability: key=%s spell=%s rank=%s passive=%s slot=%s overlay=%s",
		tostring(ability.key), tostring(ability.spell), tostring(ability.rank),
		tostring(ability.passive), tostring(slot), tostring(overlay == true)))
	if not CreateFrame then
		Add("tooltip: CreateFrame unavailable")
		return lines
	end
	if not tooltipScan then
		tooltipScan = CreateFrame("GameTooltip", "SurvivorUIRebornTooltipScan", nil, "GameTooltipTemplate")
	end
	local scan = tooltipScan
	local captured = {}
	local function DumpLines(tag)
		local name = scan:GetName()
		local count = scan.NumLines and scan:NumLines() or 30
		Add(string.format("  %s: NumLines=%s", tag, tostring(count)))
		for i = 1, count do
			local left = _G[name .. "TextLeft" .. i]
			local right = _G[name .. "TextRight" .. i]
			local lt = left and left:GetText()
			local rt = right and right:GetText()
			if (lt and lt ~= "") or (rt and rt ~= "") then
				local color = ""
				if left and left.GetTextColor then
					local r, g, b = left:GetTextColor()
					color = string.format(" color=%.2f,%.2f,%.2f", r or 0, g or 0, b or 0)
				end
				local line = string.format("  %s L%d: %s | %s%s", tag, i, tostring(lt), tostring(rt), color)
				Add(line)
				table.insert(captured, line)
			end
		end
	end
	if slot and not overlay then
		if GetActionInfo then
			local kind, id = GetActionInfo(slot)
			Add(string.format("  action info: kind=%s id=%s matchesSpell=%s",
				tostring(kind), tostring(id), tostring(id ~= nil and ability.spell ~= nil and id == ability.spell)))
		else
			Add("  action info: GetActionInfo unavailable")
		end
		if scan.SetAction then
			local ok, err = pcall(function()
				scan:SetOwner(UIParent, "ANCHOR_NONE")
				scan:ClearLines()
				scan:SetAction(slot)
			end)
			if ok then
				DumpLines("action" .. slot)
			else
				Add("  action tooltip read failed: " .. tostring(err))
			end
		else
			Add("  action tooltip: SetAction unavailable")
		end
	elseif overlay then
		Add("  action tooltip: overlay button, no native action tooltip")
	else
		Add("  action tooltip: no action slot")
	end
	if ability.spell and ability.spell > 0 then
		if scan.SetSpellByID then
			local ok, err = pcall(function()
				scan:SetOwner(UIParent, "ANCHOR_NONE")
				scan:ClearLines()
				scan:SetSpellByID(ability.spell)
			end)
			if ok then
				DumpLines("spell" .. ability.spell)
			else
				Add("  spell tooltip read failed: " .. tostring(err))
			end
		else
			Add("  spell tooltip: SetSpellByID unavailable in this client")
		end
	end
	scan:Hide()
	-- Before/after comparison against the previous capture of the
	-- same ability in this session.
	local previous = tooltipCaptures[ability.key]
	if previous then
		local seen = {}
		for i = 1, table.getn(previous) do
			seen[previous[i]] = true
		end
		local added = 0
		for i = 1, table.getn(captured) do
			if not seen[captured[i]] then
				added = added + 1
				Add("  changed/new: " .. captured[i])
			end
		end
		if added == 0 then
			Add("  compare: no tooltip line changes since previous capture")
		end
	else
		Add("  compare: first capture stored; run again after an upgrade choice")
	end
	tooltipCaptures[ability.key] = captured
	return lines
end

function SurvivorUI_RebornTooltipDump()
	local lines = {}
	local data = SurvivorUI_RebornAbilities()
	for i = 1, table.getn(data.all) do
		local part = SurvivorUI_RebornTooltipCapture(data.all[i].key)
		for j = 1, table.getn(part) do
			table.insert(lines, part[j])
		end
	end
	return lines
end

-- One line per fact, safe to copy out of chat. No credentials, tokens, or
-- personal data are ever included.
function SurvivorUI_RebornProbe()
	local lines = {}
	local function Add(text)
		table.insert(lines, text)
	end
	Add("Reborn compat: active=" .. tostring(SurvivorUI_RebornActive()))
	Add("runId=" .. tostring(SurvivorUI_RebornRunId()))
	local run = AZS_RUN
	if type(run) == "table" then
		Add(string.format("AZS_RUN: ph=%s t=%s endless=%s nbs=%s nbm=%s nb=%s nbc=%s nbn=%s rift=%s left=%s",
			tostring(run.ph), tostring(run.t), tostring(run.endless),
			tostring(run.nbs), tostring(run.nbm), tostring(run.nb), tostring(run.nbc),
			tostring(run.nbn), tostring(run.rift), tostring(run.left)))
	else
		Add("AZS_RUN: (absent)")
	end
	local nextBoss = SurvivorUI_RebornNextBoss()
	if nextBoss then
		Add(string.format("nextBoss: mode=%s state=%s name=%s number=%s rift=%s countdown=%s",
			tostring(nextBoss.mode), tostring(nextBoss.state), tostring(nextBoss.name),
			tostring(nextBoss.number), tostring(nextBoss.rift), tostring(nextBoss.countdown)))
	else
		Add("nextBoss: (no Reborn boss fields)")
	end
	Add("AZS_SCHEDULE: " .. (type(AZS_SCHEDULE) == "table" and tostring(table.getn(AZS_SCHEDULE)) .. " rows" or "(absent)"))
	Add("AZS_UNITS: " .. (type(AZS_UNITS) == "table" and tostring(table.getn(AZS_UNITS)) .. " rows" or "(absent)"))
	Add("AZS_SPELLS: " .. (type(AZS_SPELLS) == "table" and tostring(table.getn(AZS_SPELLS)) .. " rows" or "(absent)"))
	Add("AZS_ABILITIES: " .. (type(AZS_ABILITIES) == "table" and tostring(table.getn(AZS_ABILITIES)) .. " rows" or "(absent)")
		.. " requestFn=" .. tostring(AZS_RequestAbilities ~= nil)
		.. " requested=" .. tostring(abilitiesRequested))
	local data = SurvivorUI_RebornAbilities()
	Add(string.format("abilities merged: %d actives, %d passives, %d racials, source=%s complete=%s",
		table.getn(data.actives), table.getn(data.passives), table.getn(data.racials),
		data.source, tostring(data.complete)))
	for i = 1, table.getn(data.all) do
		local a = data.all[i]
		Add(string.format("  ability: key=%s spell=%s rank=%s passive=%s kind=%s name=%s",
			tostring(a.key), tostring(a.spell), tostring(a.rank), tostring(a.passive), tostring(a.kind), tostring(a.name)))
	end
	Add("rankEvents this run: " .. tostring(table.getn(rankEvents)))
	for i = 1, table.getn(rankEvents) do
		local e = rankEvents[i]
		Add(string.format("  rank: %s %s -> %s at %ss", tostring(e.key), tostring(e.from), tostring(e.to), tostring(e.at)))
	end
	local jew = SurvivorUI_RebornJewelry(true)
	Add("jewelry source=" .. tostring(jew.source) .. " items=" .. tostring(table.getn(jew.items))
		.. " loadoutFn=" .. tostring(AZS_GetMeterLoadout ~= nil)
		.. " AZSGEAR=" .. (type(AZSGEAR) == "table" and tostring(table.getn(AZSGEAR)) .. " rows" or "(absent)"))
	if jew.error then
		Add("jewelry error: code=" .. tostring(jew.error.code) .. " message=" .. tostring(jew.error.message))
	end
	for i = 1, table.getn(jew.items) do
		local item = jew.items[i]
		Add(string.format("  jewelry: slot=%s name=%s rank=%s rarity=%s key=%s count=%s icon=%s",
			tostring(item.slot), tostring(item.name), tostring(item.rank), tostring(item.rarity), tostring(item.key),
			tostring(item.count or 1), tostring(item.icon)))
	end
	if jew.duplicates and jew.duplicates > 0 then
		Add("  jewelry duplicates merged this snapshot: " .. tostring(jew.duplicates))
	end
	if jew.aggregate then
		local parts = {}
		for k, v in pairs(jew.aggregate) do
			table.insert(parts, k .. "=" .. tostring(v))
		end
		Add("jewelry aggregate (AZS_STATS g*, whole character, NOT per-item): " .. table.concat(parts, " "))
	else
		Add("jewelry aggregate: (none / AZS_STATS absent or all zero)")
	end
	-- Rift crystals / altar hunt: the API documents no crystal or
	-- altar table, kind, or field, so probe the plausible carriers —
	-- chests (boss flag), banners (kind/text), world-anchor kinds,
	-- and candidate globals — before claiming either feature.
	if type(AZS_CHESTS) == "table" then
		for i = 1, table.getn(AZS_CHESTS) do
			local c = AZS_CHESTS[i]
			Add(string.format("  chest: id=%s boss=%s x=%s y=%s mx=%s my=%s",
				tostring(Field(c, "id", 1)), tostring(Field(c, "boss", 7)),
				tostring(Field(c, "x", 2)), tostring(Field(c, "y", 3)),
				tostring(Field(c, "mx", 5)), tostring(Field(c, "my", 6))))
		end
	end
	if type(AZS_BANNERS) == "table" then
		for i = 1, table.getn(AZS_BANNERS) do
			local b = AZS_BANNERS[i]
			Add(string.format("  banner: kind=%s boss=%s name=%s time=%s text=%s",
				tostring(Field(b, "kind", 2)), tostring(Field(b, "boss", 3)),
				tostring(Field(b, "name", 4)), tostring(Field(b, "time", 6)),
				tostring(Field(b, "text", 5))))
		end
	end
	Add("banner handler: register=" .. tostring(AZS_RegisterBannerHandler ~= nil) .. " registered=" .. tostring(bannerHandlerRegistered))
	for i = 1, table.getn(capturedBanners) do
		Add("  captured banner: " .. capturedBanners[i])
	end
	local tooltipLines = SurvivorUI_RebornTooltipDump()
	for i = 1, table.getn(tooltipLines) do
		Add(tooltipLines[i])
	end
	if AZS_GetWorldAnchors then
		local kinds = { "cache", "guardianLair", "guardian", "elite", "boss", "finalBoss", "enemy", "ping" }
		local ok, answer = pcall(AZS_GetWorldAnchors, { kinds = kinds }, nil, 256)
		if ok and type(answer) == "table" and type(answer.entries) == "table" then
			local census = {}
			for i = 1, table.getn(answer.entries) do
				local kind = tostring(answer.entries[i].kind)
				census[kind] = (census[kind] or 0) + 1
			end
			local parts = {}
			for kind, n in pairs(census) do
				table.insert(parts, kind .. "=" .. tostring(n))
			end
			table.sort(parts)
			Add("world anchors: " .. table.concat(parts, " "))
			for i = 1, table.getn(answer.entries) do
				local e = answer.entries[i]
				if e.kind == "cache" then
					Add(string.format("  anchor cache: name=%s state=%s x=%s y=%s",
						tostring(e.name), tostring(e.state), tostring(e.x), tostring(e.y)))
				elseif e.kind == "guardianLair" then
					Add(string.format("  anchor lair: name=%s state=%s x=%s y=%s occupant=%s",
						tostring(e.name), tostring(e.state), tostring(e.x), tostring(e.y), tostring(e.occupantUnitId)))
				end
			end
		else
			Add("world anchors: (query failed)")
		end
	end
	if type(AZS_BUFFS) == "table" then
		for i = 1, table.getn(AZS_BUFFS) do
			local b = AZS_BUFFS[i]
			local spell = tonumber(Field(b, "spell", 1))
			Add(string.format("  buff: spell=%s name=%s left=%s",
				tostring(spell), tostring(spell and GetSpellInfo and GetSpellInfo(spell)), tostring(Field(b, "left", 2))))
		end
	end
	if type(AZS_DEBUFFS) == "table" then
		for i = 1, table.getn(AZS_DEBUFFS) do
			local d = AZS_DEBUFFS[i]
			Add(string.format("  debuff: id=%s spell=%s stacks=%s secs=%s name=%s",
				tostring(Field(d, "id", 1)), tostring(Field(d, "spell", 2)),
				tostring(Field(d, "stacks", 3)), tostring(Field(d, "secs", 4)),
				tostring(Field(d, "name", 5))))
		end
	end
	Add("crystal candidates: AZS_CRYSTALS=" .. (type(AZS_CRYSTALS) == "table" and tostring(table.getn(AZS_CRYSTALS)) or "absent")
		.. " AZS_ALTAR=" .. (type(AZS_ALTAR) == "table" and "present" or "absent")
		.. " AZS_PORTAL=" .. (type(AZS_PORTAL) == "table" and "present" or "absent")
		.. " AZS_RIFT=" .. (type(AZS_RIFT) == "table" and "present" or "absent"))
	if type(AZS_RIFT) == "table" then
		local keys = {}
		for k in pairs(AZS_RIFT) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for i = 1, table.getn(keys) do
			local k = keys[i]
			local v = AZS_RIFT[k]
			if type(v) == "table" then
				Add("  rift." .. tostring(k) .. " = {" .. tostring(table.getn(v)) .. " rows}")
				for j = 1, math.min(table.getn(v), 8) do
					local row = v[j]
					if type(row) == "table" then
						local parts = {}
						for rk, rv in pairs(row) do
							if type(rv) ~= "table" then
								table.insert(parts, tostring(rk) .. "=" .. tostring(rv))
							end
						end
						table.sort(parts)
						Add("    rift." .. tostring(k) .. "[" .. tostring(j) .. "]: " .. table.concat(parts, " "))
					else
						Add("    rift." .. tostring(k) .. "[" .. tostring(j) .. "] = " .. tostring(row))
					end
				end
			else
				Add("  rift." .. tostring(k) .. " = " .. tostring(v))
			end
		end
	end
	local curses = SurvivorUI_RebornCurses()
	Add("curses: supported=" .. tostring(curses.supported) .. " - " .. curses.reason)
	Add("candidate globals: AZS_CHESTS=" .. (type(AZS_CHESTS) == "table" and tostring(table.getn(AZS_CHESTS)) or "absent")
		.. " AZS_BANNER=" .. (type(AZS_BANNER) == "table" and "present" or "absent")
		.. " AZS_BUFFS=" .. (type(AZS_BUFFS) == "table" and tostring(table.getn(AZS_BUFFS)) or "absent")
		.. " AZS_DEBUFFS=" .. (type(AZS_DEBUFFS) == "table" and tostring(table.getn(AZS_DEBUFFS)) or "absent")
		.. " AZS_CURSES=" .. (type(AZS_CURSES) == "table" and "present" or "absent"))
	Add("debug=" .. tostring(SurvivorUI_RebornDebugEnabled()))
	if GetSpellInfo then
		local name = GetSpellInfo(190784)
		local known = IsPlayerSpell and IsPlayerSpell(190784) or false
		local nameZh = GetSpellInfo("神圣战马")
		Add(string.format("  steed candidate: id190784 name=%s known=%s nameZh=%s",
			tostring(name), tostring(known), tostring(nameZh)))
	end
	if UnitBuff then
		for i = 1, 40 do
			local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
			if not name then
				break
			end
			Add(string.format("  player buff: name=%s spell=%s", tostring(name), tostring(spellId)))
		end
	end
	if EnumerateFrames then
		local frame = EnumerateFrames()
		while frame do
			if frame.GetAttribute then
				local spell = frame:GetAttribute("spell")
				local macro = frame:GetAttribute("macrotext")
				if spell or macro then
					Add(string.format("  spell frame: name=%s spell=%s macro=%s", tostring(frame:GetName()), tostring(spell), tostring(macro)))
				end
			end
			frame = EnumerateFrames(frame)
		end
	end
	if type(AZS_TIMERS) == "table" then
		for i = 1, table.getn(AZS_TIMERS) do
			local t = AZS_TIMERS[i]
			Add(string.format("  timer: name=%s kind=%s ready=%s wait=%s icon=%s",
				tostring(Field(t, "name", 1)), tostring(Field(t, "kind", 3)), tostring(Field(t, "ready", 4)), tostring(Field(t, "wait", 5)), tostring(Field(t, "icon", 2))))
		end
	end
	for i = 1, table.getn(sentCommands) do
		Add("  cmd: " .. sentCommands[i])
	end
	if GetNumSpellTabs and GetSpellTabInfo and GetSpellName then
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, numSpells = GetSpellTabInfo(tab)
			for i = 1, numSpells or 0 do
				local index = offset + i
				local name = GetSpellName(index, "spell")
				if name and (string.find(name, "马", 1, true) or string.find(name, "Steed", 1, true)) then
					local link = GetSpellLink and GetSpellLink(index, "spell")
					Add(string.format("  spellbook: name=%s link=%s", tostring(name), tostring(link)))
				end
			end
		end
	end
	return lines
end

function SurvivorUI_RebornDumpText()
	return table.concat(SurvivorUI_RebornProbe(), "\n")
end

-- Raw jewelry payload dump, for /sui reborn jewelry raw. Prints every
-- field name and value of each runJewelry entry and its sources entry,
-- and of each AZSGEAR row — the normalised view cannot answer what a
-- number like 55/63/1 is, whether a rarity/icon/level field exists
-- under another name, or whether sourceKey is jewel:<slot>. Diagnostics
-- only: call it explicitly, never on a timer. Output is capped so a
-- pathological payload cannot flood chat.
function SurvivorUI_RebornJewelryRawLines()
	local lines = {}
	local function Add(text)
		table.insert(lines, text)
	end
	local function DumpValue(v, depth)
		if type(v) == "table" then
			if depth > 0 then
				return "{...}"
			end
			local parts = {}
			for k2, v2 in pairs(v) do
				table.insert(parts, tostring(k2) .. "=" .. tostring(v2))
			end
			table.sort(parts)
			return "{ " .. table.concat(parts, ", ") .. " }"
		end
		return tostring(v)
	end
	local function DumpTable(label, t)
		if type(t) ~= "table" then
			Add(label .. " = " .. tostring(t))
			return
		end
		local keys = {}
		for k in pairs(t) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		if table.getn(keys) == 0 then
			Add(label .. " = {}")
			return
		end
		for i = 1, table.getn(keys) do
			local k = keys[i]
			Add("  " .. label .. "." .. tostring(k) .. " = " .. DumpValue(t[k], 1))
			-- One level into table values (the source icon is a table):
			-- its scalar fields, so the next probe shows the shape.
			if type(t[k]) == "table" then
				local subkeys = {}
				for sub in pairs(t[k]) do table.insert(subkeys, sub) end
				table.sort(subkeys, function(a, b) return tostring(a) < tostring(b) end)
				for j = 1, table.getn(subkeys) do
					local sub = subkeys[j]
					if type(t[k][sub]) ~= "table" then
						Add("    " .. label .. "." .. tostring(k) .. "." .. tostring(sub) .. " = " .. tostring(t[k][sub]))
					end
				end
			end
		end
	end
	Add("Survivor UI (Reborn): jewelry raw payload")
	if AZS_GetMeterLoadout then
		local runId, ownerId = LoadoutOwner()
		local request = { apiVersion = 1 }
		if runId then request.runId = runId end
		if ownerId then request.ownerId = ownerId end
		local ok, loadout, loadoutErr = pcall(AZS_GetMeterLoadout, request)
		if ok and type(loadout) == "table" then
			DumpTable("loadout", loadout)
			local runJewelry = loadout.runJewelry
			rawJewelry = { runJewelry = runJewelry, sources = loadout.sources }
			if type(runJewelry) == "table" then
				for i = 1, table.getn(runJewelry) do
					DumpTable("runJewelry[" .. tostring(i) .. "]", runJewelry[i])
					local entry = runJewelry[i]
					if type(loadout.sources) == "table" and entry and entry.sourceKey then
						DumpTable("sources[" .. tostring(entry.sourceKey) .. "]", loadout.sources[entry.sourceKey])
					end
				end
			end
		elseif ok then
			Add("loadout = nil, error code=" .. tostring(loadoutErr and loadoutErr.code) .. " message=" .. tostring(loadoutErr and loadoutErr.message))
		else
			Add("loadout call failed: " .. tostring(loadout))
		end
	else
		Add("AZS_GetMeterLoadout: (absent)")
	end
	if type(AZSGEAR) == "table" then
		for i = 1, table.getn(AZSGEAR) do
			DumpTable("AZSGEAR[" .. tostring(i) .. "]", AZSGEAR[i])
		end
	else
		Add("AZSGEAR: (absent)")
	end
	if table.getn(lines) > 200 then
		local capped = {}
		for i = 1, 200 do table.insert(capped, lines[i]) end
		table.insert(capped, "... (truncated at 200 lines)")
		return capped
	end
	return lines
end

-- Entering the world (including after /reload): a new run id resets
-- caches, and the ability snapshot must be re-requested because the game
-- clears AZS_ABILITIES on AZSZONE and sends no request automatically.
local rebornLoader = CreateFrame("Frame")
rebornLoader:RegisterEvent("PLAYER_ENTERING_WORLD")
rebornLoader:SetScript("OnEvent", function()
	SurvivorUI_RebornCheckRun()
	SurvivorUI_RebornRequestAbilities(false)
end)

------------------------------------------------------------------------------
-- Slash diagnostics: /sui reborn ... (wired in SurvivorUI.lua)
--
-- All of these are opt-in and print only when asked. /sui reborn probe
-- prints the full probe; copy it out of chat when reporting a problem.
-- No line here contains credentials, tokens, or personal data.

function SurvivorUI_RebornSlash(argument)
	local arg = argument or ""
	local function Say(text)
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end
	end
	if arg == "debug on" then
		SurvivorUI_RebornSetDebug(true)
		Say("Survivor UI: Reborn debug logging on.")
		return
	elseif arg == "debug off" then
		SurvivorUI_RebornSetDebug(false)
		Say("Survivor UI: Reborn debug logging off.")
		return
	elseif arg == "probe" or arg == "dump" then
		local ok, lines = pcall(SurvivorUI_RebornProbe)
		if not ok then
			Say("Survivor UI (Reborn): probe failed: " .. tostring(lines))
			return
		end
		for i = 1, table.getn(lines) do
			Say(lines[i])
		end
		return
	elseif arg == "boss" then
		local nextBoss = SurvivorUI_RebornNextBoss()
		if not nextBoss then
			Say("Survivor UI (Reborn): no Reborn boss fields (nbm/nbs/nb/rift) in AZS_RUN; using the schedule.")
			return
		end
		local text = SurvivorUI_RebornNextBossText(nextBoss)
		Say(string.format("Survivor UI (Reborn): next boss mode=%s state=%s name=%s number=%s rift=%s countdown=%s (%s)",
			tostring(nextBoss.mode), tostring(nextBoss.state), tostring(nextBoss.name),
			tostring(nextBoss.number), tostring(nextBoss.rift), tostring(nextBoss.countdown),
			tostring(text)))
		return
	elseif arg == "abilities" then
		SurvivorUI_RebornRequestAbilities(true)
		local data = SurvivorUI_RebornAbilities()
		Say(string.format("Survivor UI (Reborn): abilities source=%s complete=%s (%d actives, %d passives, %d racials)",
			data.source, tostring(data.complete),
			table.getn(data.actives), table.getn(data.passives), table.getn(data.racials)))
		for i = 1, table.getn(data.all) do
			local a = data.all[i]
			Say(string.format("  %s rank %s passive=%s kind=%s name=%s",
				tostring(a.key), tostring(a.rank), tostring(a.passive), tostring(a.kind), tostring(a.name)))
		end
		if not data.complete then
			Say("  The AZS_ABILITIES snapshot has not arrived yet; it is requested again automatically (throttled). Try again in a few seconds, in a run.")
		end
		return
	elseif arg == "jewelry raw" then
		local lines = SurvivorUI_RebornJewelryRawLines()
		for i = 1, table.getn(lines) do
			Say(lines[i])
		end
		return
	elseif arg == "jewelry" then
		local jew = SurvivorUI_RebornJewelry(true)
		Say(string.format("Survivor UI (Reborn): jewelry source=%s items=%d duplicates merged=%d", tostring(jew.source), table.getn(jew.items), jew.duplicates or 0))
		if jew.error then
			Say("  loadout error: code=" .. tostring(jew.error.code) .. " message=" .. tostring(jew.error.message))
		end
		for i = 1, table.getn(jew.items) do
			local item = jew.items[i]
			Say(string.format("  %s name=%s rank=%s rarity=%s key=%s count=%s icon=%s",
				tostring(item.slot), tostring(item.name), tostring(item.rank), tostring(item.rarity), tostring(item.key),
				tostring(item.count or 1), tostring(item.icon)))
		end
		if jew.aggregate then
			local parts = {}
			for k, v in pairs(jew.aggregate) do
				table.insert(parts, k .. "=" .. tostring(v))
			end
			Say("  aggregate (whole character, NOT per-item): " .. table.concat(parts, " "))
		end
		if jew.source == "none" then
			Say("  No loadout / AZSGEAR jewelry was returned; the panel falls back to inventory slots.")
		end
		return
	elseif arg == "upgrades" then
		local events = SurvivorUI_RebornRankEvents()
		Say("Survivor UI (Reborn): rank increases this run: " .. tostring(table.getn(events)))
		for i = 1, table.getn(events) do
			local e = events[i]
			Say(string.format("  %s: rank %s -> %s at %ss", tostring(e.key), tostring(e.from), tostring(e.to), tostring(e.at)))
		end
		Say("  Individual upgrade choices are not exposed by the AZ Reborn API; only rank is tracked.")
		return
	elseif string.sub(arg, 1, 8) == "tooltip " then
		local target = string.sub(arg, 9)
		local ok, lines = pcall(SurvivorUI_RebornTooltipCapture, target)
		if not ok then
			Say("Survivor UI (Reborn): tooltip capture failed: " .. tostring(lines))
			return
		end
		for i = 1, table.getn(lines) do
			Say(lines[i])
		end
		return
	elseif arg == "capture start" then
		SurvivorUI_RebornCaptureStart()
		Say("Survivor UI (Reborn): diagnostic capture started (bounded, state changes only).")
		return
	elseif arg == "capture stop" then
		SurvivorUI_RebornCaptureStop()
		Say("Survivor UI (Reborn): diagnostic capture stopped.")
		return
	elseif arg == "capture" then
		local lines = SurvivorUI_RebornCaptureLines()
		for i = 1, table.getn(lines) do
			Say(lines[i])
		end
		return
	elseif arg == "record start" then
		local id = SurvivorUI_RebornRecordStart and SurvivorUI_RebornRecordStart()
		Say("Survivor UI (Reborn): diagnostic recording started, session " .. tostring(id) .. ". Play normally; stop with /sui reborn record stop.")
		return
	elseif arg == "record stop" then
		local id = SurvivorUI_RebornRecordStop and SurvivorUI_RebornRecordStop()
		Say("Survivor UI (Reborn): diagnostic recording stopped, session " .. tostring(id) .. ". Exit the game, then run Upload-Diagnostics.bat.")
		return
	elseif arg == "record status" then
		local st = SurvivorUI_RebornRecordStatus and SurvivorUI_RebornRecordStatus() or {}
		Say(string.format("Survivor UI (Reborn): recording=%s session=%s events=%s runs=%s truncated=%s stored=%s",
			tostring(st.active), tostring(st.sessionId), tostring(st.events), tostring(st.runs), tostring(st.truncated), tostring(st.storedSessions)))
		return
	elseif arg == "record auto on" then
		if SurvivorUI_RebornRecordAuto then SurvivorUI_RebornRecordAuto(true) end
		Say("Survivor UI (Reborn): automatic diagnostic recording on (starts every session).")
		return
	elseif arg == "record auto off" then
		local stopped = false
		if SurvivorUI_RebornRecordAuto then
			local _, wasStopped = SurvivorUI_RebornRecordAuto(false)
			stopped = wasStopped == true
		end
		Say(stopped and "Survivor UI (Reborn): automatic diagnostic recording off; current recording stopped." or "Survivor UI (Reborn): automatic diagnostic recording off.")
		return
	elseif arg == "record clear" then
		if SurvivorUI_RebornRecordClear then SurvivorUI_RebornRecordClear() end
		Say("Survivor UI (Reborn): diagnostic sessions cleared.")
		return
	elseif string.sub(arg, 1, 12) == "record mark " then
		if SurvivorUI_RebornRecordMark then SurvivorUI_RebornRecordMark(string.sub(arg, 13)) end
		Say("Survivor UI (Reborn): mark recorded.")
		return
	elseif arg == "curses" then
		local curses = SurvivorUI_RebornCurses()
		Say("Survivor UI (Reborn): curses supported=" .. tostring(curses.supported) .. ". " .. curses.reason)
		return
	end
	Say("Survivor UI (Reborn): /sui reborn probe | boss | abilities | jewelry | jewelry raw | upgrades | curses | tooltip <key-or-slot> | capture start|stop | debug on|off")
	Say("Survivor UI (Reborn): active=" .. tostring(SurvivorUI_RebornActive()) .. " runId=" .. tostring(SurvivorUI_RebornRunId()))
end
