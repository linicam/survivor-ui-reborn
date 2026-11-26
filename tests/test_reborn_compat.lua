-- Mocked regression tests for SurvivorUI/RebornCompat.lua.
--
-- Run:  lua tests/test_reborn_compat.lua
-- (Lua 5.1 is the in-game version; this file also runs under Lua 5.4
-- with the shims at the top. It does NOT run the WoW client: AZS_* tables,
-- AZS_RequestAbilities, AZS_GetMeterLoadout and the WoW frame API are all
-- mocked here.)
--
-- Fixtures are labelled:
--   VERIFIED: shape taken from the official AZ Reborn Addon API
--     (https://azreborn.com/guides/addon-api, read 2026-11-25).
--   DEFENSIVE: shape NOT published in the docs (notably AZSGEAR rows and
--     meter-loadout source fields); the test only checks that the code
--     handles the shape defensively and never crashes on a different one.
-- A passing test therefore proves the logic against the documented
-- contract, not that the game sends exactly these rows in-game; see
-- REBORN_COMPATIBILITY.md and /sui reborn probe for in-game verification.

-- Lua 5.4 shims for WoW 1.12 / Lua 5.1 idioms used by the addon.
if not table.getn then table.getn = function(t) return #t end end
if not math.mod then math.mod = function(a, b) return a - math.floor(a / b) * b end end
if not string.gfind then string.gfind = string.gmatch end
if not loadstring then loadstring = load end

local passed, failed = 0, 0
local function check(name, cond, extra)
	if cond then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (extra and (" -- " .. tostring(extra)) or ""))
	end
end
local function eq(name, got, want)
	check(name, got == want, "got=" .. tostring(got) .. " want=" .. tostring(want))
end

-- ---------------------------------------------------------------------------
-- Minimal WoW stubs. Each test file load gets a fresh state via loadfile in
-- a sandbox env is overkill; instead tests run in sequence and reset the
-- mocked AZS_* globals between groups. RebornCompat keeps per-run caches,
-- so a run-id change (or SurvivorUI_RebornForgetRun) resets them.
-- ---------------------------------------------------------------------------

local fakeTime = 1000
function GetTime() return fakeTime end
function time() return fakeTime end

local frames = {}
function CreateFrame(kind, name, parent, template)
	local f = {
		RegisterEvent = function(self, e) end,
		SetScript = function(self, ev, fn) self[ev] = fn end,
	}
	table.insert(frames, f)
	return f
end
UIParent = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) end }
SurvivorUIDB = {}
SurvivorUI_Standby = nil
function SurvivorUI_T(s) return s end
function SurvivorUI_TF(s, ...)
	local values = { ... }
	return (string.gsub(s, "{(%d)}", function(i) local v = values[tonumber(i)] return v ~= nil and tostring(v) or "" end))
end

-- Load RebornCompat.lua from the repo root (tests/..).
local scriptDir = arg and arg[0] or "tests/test_reborn_compat.lua"
local repoRoot = string.gsub(scriptDir, "tests/test_reborn_compat%.lua$", "")
if repoRoot == "" then repoRoot = "." end
local raidNoticeHook
local compatHandlers = {}
AZS = { On = function(prefix, callback) compatHandlers[prefix] = callback end }
RaidNotice_AddMessage = function() end
hooksecurefunc = function(name, callback)
	if name == "RaidNotice_AddMessage" then raidNoticeHook = callback end
end
local chunk = assert(loadfile(repoRoot .. "/SurvivorUI/RebornCompat.lua"))
chunk()

local function resetGame()
	AZS_RUN = nil
	AZS_SCHEDULE = nil
	AZS_UNITS = nil
	AZS_SPELLS = nil
	AZS_SPELLS_UPDATED = nil
	AZS_ABILITIES = nil
	AZS_ABILITIES_UPDATED = nil
	AZS_ZONE = nil
	AZSGEAR = nil
	AZSGEAR_UPDATED = nil
	AZS_STATS = nil
	AZS_CHESTS = nil
	AZS_BANNER = nil
	AZS_BUFFS = nil
	AZS_DEBUFFS = nil
	AZS_CURSES = nil
	AZS_RequestAbilities = nil
	AZS_GetMeterLoadout = nil
	AZS_GetMeterContext = nil
	AZS_GetRunTime = nil
	AZS_API_RunId = nil
	AZS = nil
	SurvivorUI_RebornForgetRun()
	fakeTime = 1000
end

-- ===========================================================================
-- Boss progression (VERIFIED shapes)
-- ===========================================================================
resetGame()
AZS_RUN = { ph = "playing", t = 120, nbs = "known", nbm = "rift", nb = 5, nbc = 3, nbn = "Rift Boss", rift = 42 }
local nb = SurvivorUI_RebornNextBoss()
check("boss rift: mode", nb and nb.mode == "rift")
eq("boss rift: rift value", nb and nb.rift, 42)
eq("boss rift: latest minute", nb and nb.atLatestMinute, 5)
eq("boss rift: name", nb and nb.name, "Rift Boss")
eq("boss rift: number", nb and nb.number, 3)
local text, isRift = SurvivorUI_RebornNextBossText(nb)
eq("boss rift: text", text, "42%")
check("boss rift: text is rift", isRift == true)

resetGame()
-- Missing rift field is missing, not 0 (VERIFIED doc rule).
AZS_RUN = { ph = "playing", t = 10, nbs = "known", nbm = "rift", nb = -1, nbn = "Rift Boss" }
nb = SurvivorUI_RebornNextBoss()
check("boss rift missing: mode", nb and nb.mode == "rift")
eq("boss rift missing: rift is nil, not 0", nb and nb.rift, nil)
eq("boss rift missing: text", SurvivorUI_RebornNextBossText(nb), "")

resetGame()
AZS_RUN = { ph = "playing", t = 300, nbs = "known", nbm = "time", nb = 75, nbc = 2, nbn = "Timed Boss" }
nb = SurvivorUI_RebornNextBoss()
check("boss time: mode", nb and nb.mode == "time")
eq("boss time: countdown", nb and nb.countdown, 75)
eq("boss time: text", SurvivorUI_RebornNextBossText(nb), "in 1:15")

resetGame()
-- Endless: nbm time, nbn empty, nb counts down (VERIFIED).
AZS_RUN = { ph = "playing", t = 1000, endless = 1, nbs = "unknown", nbm = "time", nb = 30, nbc = 9, nbn = "", left = -1 }
nb = SurvivorUI_RebornNextBoss()
check("boss endless: mode time", nb and nb.mode == "time")
eq("boss endless: countdown", nb and nb.countdown, 30)
eq("boss endless: name is nil", nb and nb.name, nil)
eq("boss endless: number", nb and nb.number, 9)

resetGame()
AZS_RUN = { ph = "playing", nbs = "up", nbc = 2, nbn = "" }
nb = SurvivorUI_RebornNextBoss()
check("boss up: mode", nb and nb.mode == "up")
resetGame()
AZS_RUN = { ph = "playing", nbs = "none", nbc = 0 }
nb = SurvivorUI_RebornNextBoss()
check("boss none: mode", nb and nb.mode == "none")
eq("boss none: text nil", SurvivorUI_RebornNextBossText(nb), nil)

resetGame()
-- No Reborn boss fields at all: caller must fall back to the schedule.
AZS_RUN = { ph = "playing", t = 10 }
check("boss no-fields: nil (schedule fallback)", SurvivorUI_RebornNextBoss() == nil)

resetGame()
-- Rift -> time transition: same run, mode changes, no stale rift shown.
AZS_RUN = { ph = "playing", nbs = "known", nbm = "rift", rift = 90, nb = -1 }
nb = SurvivorUI_RebornNextBoss()
check("boss transition: rift first", nb and nb.mode == "rift")
AZS_RUN = { ph = "playing", nbs = "known", nbm = "time", nb = 45 }
nb = SurvivorUI_RebornNextBoss()
check("boss transition: then time", nb and nb.mode == "time")
eq("boss transition: rift cleared", nb and nb.rift, nil)
eq("boss transition: countdown", nb and nb.countdown, 45)

-- ===========================================================================
-- Abilities (VERIFIED AZS_ABILITIES shape; AZS_SPELLS action-bar only)
-- ===========================================================================
resetGame()
local requestCount = 0
AZS_RequestAbilities = function() requestCount = requestCount + 1 end
AZS = { On = function(prefix, fn) end }
AZS_ZONE = { run = "azs:r11111111" }
AZS_SPELLS = {
	{ "fireball", 133, 3, 0, 2.5 },
	{ "frostbolt", 116, 2, 0, 3 },
	{ "berserking", 26297, 1, 0, 60 },
}
AZS_SPELLS_UPDATED = 1
-- Snapshot arrives late (empty at first): spells-only fallback.
AZS_ABILITIES = {}
AZS_ABILITIES_UPDATED = 1
local data = SurvivorUI_RebornAbilities()
eq("abilities delayed: source spells", data.source, "spells")
check("abilities delayed: not complete", data.complete == false)
eq("abilities delayed: actives from spells", table.getn(data.actives), 3)

-- Snapshot arrives: active + passive Demonic Empowerment + racial, with
-- the passive NOT masquerading as the racial. Round 2: the racial section
-- is removed in Reborn, so Berserking (kind="racial", cdmax 60) is
-- re-homed into actives by its cooldown, never dropped.
AZS_ABILITIES = {
	{ key = "fireball", spell = 133, rank = 3, passive = false, kind = "class", cd = 0, cdmax = 2.5, name = "Fireball", icon = "Spell_Fire_Fireball", text = "Hurls a fiery ball." },
	{ key = "frostbolt", spell = 116, rank = 2, passive = false, kind = "class", cd = 0, cdmax = 3, name = "Frostbolt", icon = "Spell_Frost_FrostBolt02", text = "Chills." },
	{ key = "demonic_empowerment", spell = 47193, rank = 1, passive = true, kind = "class", cd = 0, cdmax = 0, name = "Demonic Empowerment", icon = "Spell_Shadow_DemonicEmpathy", text = "Your demons deal more damage." },
	{ key = "berserking", spell = 26297, rank = 1, passive = false, kind = "racial", cd = 0, cdmax = 60, name = "Berserking", icon = "Racial_Troll_Berserk", text = "Attack speed up." },
}
AZS_ABILITIES_UPDATED = 2
data = SurvivorUI_RebornAbilities()
eq("abilities snapshot: source", data.source, "abilities")
check("abilities snapshot: complete", data.complete == true)
eq("abilities snapshot: actives", table.getn(data.actives), 3)
eq("abilities snapshot: passives", table.getn(data.passives), 1)
eq("abilities snapshot: racials", table.getn(data.racials), 0)
eq("abilities snapshot: demonic empowerment is passive", data.passives[1] and data.passives[1].key, "demonic_empowerment")
eq("abilities snapshot: racial is re-homed to actives", data.actives[3] and data.actives[3].key, "berserking")
eq("abilities snapshot: total deduped", table.getn(data.all), 4)
local de = SurvivorUI_RebornAbilityByKey("demonic_empowerment")
check("abilities: Demonic Empowerment found by key", de ~= nil and de.passive == true)

-- Duplicate key in both tables: exactly one entry.
AZS_SPELLS = {
	{ "fireball", 133, 3, 0, 2.5 },
	{ "demonic_empowerment", 47193, 1, 0, 0 },
}
AZS_SPELLS_UPDATED = 3
AZS_ABILITIES_UPDATED = 3
data = SurvivorUI_RebornAbilities()
eq("abilities dedup: total still 4", table.getn(data.all), 4)

-- Request throttling: no per-frame server requests.
requestCount = 0
fakeTime = 2000
-- Reset the throttle by moving time far forward once, then spam.
SurvivorUI_RebornRequestAbilities(true)
eq("abilities throttle: forced request sent", requestCount, 1)
SurvivorUI_RebornRequestAbilities(false)
SurvivorUI_RebornRequestAbilities(false)
eq("abilities throttle: throttled repeats send nothing", requestCount, 1)
fakeTime = 2006
SurvivorUI_RebornRequestAbilities(false)
eq("abilities throttle: no repeat request without a build change", requestCount, 1)
-- Cooldown-only line: stamp moves, signature does not.
AZS_SPELLS_UPDATED = 9999
SurvivorUI_RebornRequestAbilities(false)
eq("abilities throttle: cooldown-only update sends nothing", requestCount, 1)
-- Rank increase: signature changes.
AZS_SPELLS = { { "fireball", 133, 4, 0, 8 } }
SurvivorUI_RebornRequestAbilities(false)
eq("abilities throttle: build change re-requests", requestCount, 2)

-- Rank history = the honest upgrade signal (VERIFIED: only rank exposed).
resetGame()
AZS_ZONE = { run = "azs:r22222222" }
AZS_GetRunTime = function() return 60 end
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 1, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 1
SurvivorUI_RebornAbilities()
eq("rank history: no events at rank 1", table.getn(SurvivorUI_RebornRankEvents()), 0)
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 2, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 2
SurvivorUI_RebornAbilities()
eq("rank history: one event on 1->2", table.getn(SurvivorUI_RebornRankEvents()), 1)
eq("rank history: increases counted", SurvivorUI_RebornRankIncreases("fireball"), 1)
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 3, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 3
SurvivorUI_RebornAbilities()
eq("rank history: second increase counted", SurvivorUI_RebornRankIncreases("fireball"), 2)
-- A lower rank (new run the reset missed) restarts history, is not an upgrade.
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 1, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 4
SurvivorUI_RebornAbilities()
eq("rank history: rank fall restarts, no new event", table.getn(SurvivorUI_RebornRankEvents()), 2)
eq("rank history: increases reset", SurvivorUI_RebornRankIncreases("fireball"), 0)

-- ===========================================================================
-- Jewelry (DEFENSIVE shapes: loadout source fields are not documented)
-- ===========================================================================
resetGame()
AZS_ZONE = { run = "azs:r33333333" }
AZS_GetMeterContext = function() return { runId = "azs:r33333333", ownerId = "hero:Test" } end
AZS_GetMeterLoadout = function(req)
	return {
		runJewelry = { { sourceKey = "jewel:ring:accuria" }, { sourceKey = "jewel:trinket:carrot" } },
		sources = {
			["jewel:ring:accuria"] = { name = "Band of Accuria", icon = "INV_Jewelry_Ring_15", slot = "ring", rank = "IV", rarity = "epic" },
			["jewel:trinket:carrot"] = { name = "Carrot on a Stick", icon = "INV_Misc_Food_33", slot = "trinket", rank = "V", rarity = "uncommon" },
		},
	}
end
local jew = SurvivorUI_RebornJewelry(true)
eq("jewelry loadout: source", jew.source, "loadout")
eq("jewelry loadout: items", table.getn(jew.items), 2)
eq("jewelry loadout: first name", jew.items[1].name, "Band of Accuria")
eq("jewelry loadout: first slot", jew.items[1].slot, "Ring")
eq("jewelry loadout: first rank", jew.items[1].rank, "IV")
eq("jewelry loadout: first rarity", jew.items[1].rarity, "epic")
-- Repeated call: no duplication.
jew = SurvivorUI_RebornJewelry(true)
eq("jewelry loadout: no duplication on refresh", table.getn(jew.items), 2)

-- Repeated upgrade of the same item: rank updates, still one entry.
AZS_GetMeterLoadout = function(req)
	return {
		runJewelry = { { sourceKey = "jewel:ring:accuria" } },
		sources = {
			["jewel:ring:accuria"] = { name = "Band of Accuria", icon = "INV_Jewelry_Ring_15", slot = "ring", rank = "V", rarity = "epic" },
		},
	}
end
jew = SurvivorUI_RebornJewelry(true)
eq("jewelry upgrade: still one item", table.getn(jew.items), 1)
eq("jewelry upgrade: rank updated", jew.items[1].rank, "V")

-- Loadout error: kept, source none, no crash.
AZS_GetMeterLoadout = function(req) return nil, { code = "NO_RUN", message = "no run", retryable = false } end
jew = SurvivorUI_RebornJewelry(true)
eq("jewelry error: source none", jew.source, "none")
eq("jewelry error: items empty", table.getn(jew.items), 0)
check("jewelry error: code kept", jew.error and jew.error.code == "NO_RUN")

-- AZSGEAR fallback when there is no loadout function (DEFENSIVE shape).
resetGame()
AZS_GetMeterLoadout = nil
AZSGEAR = {
	{ key = "accuria", name = "Band of Accuria", icon = "INV_Jewelry_Ring_15", slot = "ring", rank = 4 },
}
jew = SurvivorUI_RebornJewelry(true)
eq("jewelry gear fallback: source", jew.source, "gear")
eq("jewelry gear fallback: items", table.getn(jew.items), 1)

-- Aggregate g* shares are reported as an aggregate, never per-item.
resetGame()
AZS_STATS = { gdmg = 0.25, gcd = 0.1, ghp = 0 }
AZS_GetMeterLoadout = function(req) return { runJewelry = {}, sources = {} } end
jew = SurvivorUI_RebornJewelry(true)
check("jewelry aggregate: present", jew.aggregate ~= nil)
eq("jewelry aggregate: gdmg", jew.aggregate and jew.aggregate.gdmg, 0.25)
check("jewelry aggregate: zero ghp not reported", jew.aggregate and jew.aggregate.ghp == nil)
check("jewelry aggregate: not on the item", table.getn(jew.items) == 0)

-- Unknown / empty loadout shape: no crash, source none.
resetGame()
AZS_GetMeterLoadout = function(req) return {} end
jew = SurvivorUI_RebornJewelry(true)
eq("jewelry empty shape: source none", jew.source, "none")
eq("jewelry empty shape: items empty", table.getn(jew.items), 0)

-- ===========================================================================
-- Curses (VERIFIED in game: kind="curse" banner + AZS_BUFFS row)
-- ===========================================================================
resetGame()
local curses = SurvivorUI_RebornCurses()
check("curses: supported", curses.supported == true)
eq("curses: no items without a banner", table.getn(curses.items), 0)
AZS_BANNERS = { { kind = "curse", boss = false, name = "", time = 100,
	text = "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!" } }
AZS_RequestAbilities = function() end
AZS_BUFFS = { { spell = 47241, left = 10 } }
AZS_GetRunTime = function() return 110 end
fakeTime = 102
curses = SurvivorUI_RebornCurses()
eq("curses: one active item", table.getn(curses.items), 1)
eq("curses: effect translated", curses.items[1].text, "Horde surges ")
eq("curses: countdown starts at declared duration", curses.items[1].left, 20)
AZS_GetRunTime = function() return 120 end
eq("curses: countdown measures run time from latch", SurvivorUI_RebornCurses().items[1].left, 10)

-- ===========================================================================
-- Run reset (VERIFIED run id)
-- ===========================================================================
resetGame()
AZS_ZONE = { run = "azs:rAAAA0001" }
AZS_GetRunTime = function() return 60 end
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 1, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 1
SurvivorUI_RebornAbilities()
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 2, passive = false, kind = "class" } }
AZS_ABILITIES_UPDATED = 2
SurvivorUI_RebornAbilities()
eq("run reset: event recorded in run 1", table.getn(SurvivorUI_RebornRankEvents()), 1)
check("run reset: first check establishes run 1", SurvivorUI_RebornCheckRun() == true)
check("run reset: same run id is not a new run", SurvivorUI_RebornCheckRun() == false)
AZS_ZONE = { run = "azs:rAAAA0002" }
check("run reset: new run id detected", SurvivorUI_RebornCheckRun() == true)
eq("run reset: rank events cleared", table.getn(SurvivorUI_RebornRankEvents()), 0)
eq("run reset: increases cleared", SurvivorUI_RebornRankIncreases("fireball"), 0)

-- ===========================================================================
-- Round 2: racial re-homing, rank-history tooltips, jewelry dedup
-- ===========================================================================
resetGame()
AZS_ZONE = { run = "azs:r22222222" }
AZS_RUN = { t = 0 }
AZS_GetRunTime = function() return AZS_RUN.t end
AZS_ABILITIES = {
	{ key = "fireball", spell = 133, rank = 3, passive = false, kind = "class", cd = 0, cdmax = 2.5, name = "Fireball", icon = "Spell_Fire_Fireball", text = "Hurls a fiery ball." },
	{ key = "demonic_empowerment", spell = 47193, rank = 1, passive = false, kind = "class", cd = 0, cdmax = 30, name = "Demonic Empowerment", icon = "Ability_Warlock_DemonicEmpowerment", text = "Empowers your demon." },
	{ key = "demonic_knowledge", spell = 35691, rank = 11, passive = true, kind = "class", cd = 0, cdmax = 0, name = "Demonic Knowledge", icon = "Spell_Shadow_ImprovedVampiricEmbrace", text = "Your demons hit harder." },
	{ key = "berserking", spell = 26297, rank = 1, passive = false, kind = "racial", cd = 0, cdmax = 60, name = "Berserking", icon = "Racial_Troll_Berserk", text = "Attack speed up." },
	{ key = "human_spirit", spell = 20599, rank = 1, passive = false, kind = "racial", cd = 0, cdmax = 0, name = "Human Spirit", icon = "Spell_Holy_MindVision", text = "Spirit up." },
}
AZS_ABILITIES_UPDATED = 1
AZS_SPELLS = {}
data = SurvivorUI_RebornAbilities()
eq("round2 racial: racials list empty", table.getn(data.racials), 0)
eq("round2 racial: actives (fireball, empowerment, berserking)", table.getn(data.actives), 3)
eq("round2 racial: passives (knowledge, human spirit)", table.getn(data.passives), 2)
local keys = {}
for i = 1, table.getn(data.passives) do keys[data.passives[i].key] = true end
check("round2 racial: demonic knowledge is passive", keys["demonic_knowledge"] == true)
check("round2 racial: cdmax-0 racial is passive", keys["human_spirit"] == true)
keys = {}
for i = 1, table.getn(data.actives) do keys[data.actives[i].key] = true end
check("round2 racial: berserking (cdmax 60, cd 0) is active", keys["berserking"] == true)
check("round2 racial: demonic empowerment is active", keys["demonic_empowerment"] == true)

-- Rank rises are recorded for diagnostics but never shown in the
-- tooltip: without concrete upgrade effects, rise timestamps are
-- clutter. Rank 11 is shown as a rank, never as a pick count.
AZS_RUN.t = 72
AZS_ABILITIES[2].rank = 2 -- empowerment 1 -> 2 at 1:12
AZS_ABILITIES_UPDATED = 2
data = SurvivorUI_RebornAbilities()
local de = SurvivorUI_RebornAbilityByKey("demonic_empowerment")
local lines = SurvivorUI_RebornAbilityTooltipLines(de)
local joined = ""
for i = 1, table.getn(lines) do joined = joined .. "|" .. lines[i].text end
check("round2 tooltip: base text", string.find(joined, "Empowers your demon.", 1, true) ~= nil)
check("round2 tooltip: rank line", string.find(joined, "Rank 2", 1, true) ~= nil)
check("round2 tooltip: no history lines", string.find(joined, "1:12", 1, true) == nil)
check("round2 tooltip: no upgrade note", string.find(joined, "Individual upgrade choices are not exposed", 1, true) == nil)
check("round2 tooltip: no passive line for active", string.find(joined, "Passive", 1, true) == nil)
local dk = SurvivorUI_RebornAbilityByKey("demonic_knowledge")
local lines2 = SurvivorUI_RebornAbilityTooltipLines(dk)
local joined2 = ""
for i = 1, table.getn(lines2) do joined2 = joined2 .. "|" .. lines2[i].text end
check("round2 tooltip: passive line present", string.find(joined2, "Passive", 1, true) ~= nil)
check("round2 tooltip: rank 11 shown, not a pick count", string.find(joined2, "Rank 11", 1, true) ~= nil)
local evs = SurvivorUI_RebornRankEventsFor("demonic_empowerment")
eq("round2 tooltip: one rank event", table.getn(evs), 1)
eq("round2 tooltip: event timestamp", evs[1] and evs[1].at, 72)

-- Jewelry: same sourceKey with two distinct itemInstanceKeys merges
-- (count 2); two different pieces both ranked 55 stay distinct;
-- slots come from sourceKey.
AZS_GetMeterLoadout = function(req)
	return {
		runJewelry = {
			{ sourceKey = "jewel:ring:1", itemInstanceKey = "inst-a" },
			{ sourceKey = "jewel:ring:1", itemInstanceKey = "inst-b" },
			{ sourceKey = "jewel:trinket:2" },
			{ sourceKey = "jewel:neck:3" },
		},
		sources = {
			["jewel:ring:1"] = { name = "Tribal Mark", rank = 55, icon = "INV_Jewelry_Ring_01" },
			["jewel:trinket:2"] = { name = "Horde Mark", rank = 55, icon = "INV_Jewelry_TrinketPVP_02" },
			["jewel:neck:3"] = { name = "Prestor Ring", rank = 63, rarity = "epic", icon = "INV_Jewelry_Necklace_01" },
		},
	}
end
local jew = SurvivorUI_RebornJewelry(true)
-- Distinct itemInstanceKeys are distinct owned pieces: no merge.
eq("round2 jewelry: distinct instances stay distinct", table.getn(jew.items), 4)
eq("round2 jewelry: no duplicates merged", jew.duplicates, 0)
eq("round2 jewelry: slot from sourceKey (ring)", jew.items[1].slot, "Ring")
eq("round2 jewelry: slot from sourceKey (ring 2)", jew.items[2].slot, "Ring")
eq("round2 jewelry: slot from sourceKey (trinket)", jew.items[3].slot, "Trinket")
eq("round2 jewelry: slot from sourceKey (neck)", jew.items[4].slot, "Neck")
check("round2 jewelry: two 55s are distinct pieces", jew.items[1].name ~= jew.items[3].name)
eq("round2 jewelry: icon kept", jew.items[1].icon, "INV_Jewelry_Ring_01")
eq("round2 jewelry: rarity kept, not invented", jew.items[4].rarity, "epic")
check("round2 jewelry: rank-55 ring has no rarity", jew.items[1].rarity == nil)
local raw = SurvivorUI_RebornJewelryRawLines()
local rawJoined = table.concat(raw, "\n")
check("round2 jewelry raw: dumps source fields", string.find(rawJoined, "jewel:ring:1", 1, true) ~= nil and string.find(rawJoined, "Tribal Mark", 1, true) ~= nil)
check("round2 jewelry raw: dumps rank field", string.find(rawJoined, "rank = 55", 1, true) ~= nil)

-- Probe runs without crashing and reports the boss/ability state.
resetGame()
AZS_RUN = { ph = "playing", nbs = "known", nbm = "rift", rift = 10, nb = -1 }
local lines = SurvivorUI_RebornProbe()
check("probe: returns lines", type(lines) == "table" and table.getn(lines) > 5)
local joined = table.concat(lines, "\n")
check("probe: mentions rift", string.find(joined, "rift") ~= nil)
check("probe: mentions curses supported", string.find(joined, "curses: supported=true") ~= nil)

-- Audit regressions: source schemas, field merge, detection, dedup.
resetGame()
AZS_ZONE = { run = "azs:r33333333" }
AZS_SPELLS = { { "fireball", 133, 3, 1, 8 } }
AZS_SPELLS_UPDATED = 10
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 2, passive = false, kind = "class", cd = 0, cdmax = 8, name = "Fireball", icon = "i", text = "t" } }
AZS_ABILITIES_UPDATED = 10
data = SurvivorUI_RebornAbilities()
eq("audit merge: spells rank wins", data.all[1].rank, 3)
eq("audit merge: spells cd wins", data.all[1].cd, 1)
eq("audit merge: metadata kept", data.all[1].name, "Fireball")
AZS_ABILITIES = {}
AZS_ABILITIES_UPDATED = 11
data = SurvivorUI_RebornAbilities()
eq("audit schema: spells cd=1 is not passive", data.all[1].passive, false)
eq("audit schema: spells cdmax from index 5", data.all[1].cdmax, 8)
local savedRequest = AZS_RequestAbilities
AZS_RequestAbilities = nil
AZS_RUN = {}
check("audit detection: meter loadout alone is not Reborn", SurvivorUI_RebornActive() == false)
AZS_RequestAbilities = savedRequest
resetGame()
AZS_ZONE = { run = "azs:r44444444" }
AZS_GetMeterContext = function() return { runId = "azs:r44444444", localOwnerId = "hero:me" } end
AZS_GetMeterLoadout = function()
	return { runJewelry = {
		{ category = "ring", slotId = 1, sourceKey = "jewel:ring" },
		{ category = "ring", slotId = 1, sourceKey = "jewel:ring" },
	}, sources = { ["jewel:ring"] = { name = "Band", rank = 10, kind = "item" } } }
end
local jew2 = SurvivorUI_RebornJewelry(true)
eq("audit jewelry: duplicate records merge", table.getn(jew2.items), 1)
eq("audit jewelry: no instance key, no acquisition count", jew2.items[1].count, 1)

-- PR4 follow-up regressions.
resetGame()
AZS_ZONE = { run = "azs:r55555555" }
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 3, passive = false, kind = "class", cd = 0, cdmax = 8, name = "Fireball", icon = "i", text = "t" } }
AZS_ABILITIES_UPDATED = 20
AZS_SPELLS = { { key = "fireball", spell = 133 } }
AZS_SPELLS_UPDATED = 20
data = SurvivorUI_RebornAbilities()
eq("pr4 merge: missing spells rank keeps snapshot rank", data.all[1].rank, 3)
eq("pr4 merge: missing spells cdmax keeps snapshot cdmax", data.all[1].cdmax, 8)
local goodRequest = function() requestCount = requestCount + 1 end
requestCount = 0
AZS_RequestAbilities = function() error("boom") end
fakeTime = 5000
check("pr4 request: failure reported", SurvivorUI_RebornRequestAbilities(true) == false)
AZS_RequestAbilities = goodRequest
check("pr4 request: retry after failure allowed", SurvivorUI_RebornRequestAbilities(true) == true)
resetGame()
AZS_ZONE = { run = "azs:r66666666" }
AZS_GetMeterContext = function() return { runId = "azs:r66666666", localOwnerId = "hero:me" } end
AZS_GetMeterLoadout = function() return { runJewelry = {}, sources = {} } end
local jew3 = SurvivorUI_RebornJewelry(true)
eq("pr4 jewelry: empty loadout is authoritative", jew3.source, "loadout")
eq("pr4 jewelry: empty loadout has no items", table.getn(jew3.items), 0)
resetGame()
AZS_ZONE = { run = "azs:r77777777" }
AZS_RequestAbilities = function() end
AZS_RUN = { ph = "playing" }
AZS_GetRunTime = function() return 25 end
AZS_BANNERS = {
	{ id = 1, kind = "curse", text = "Проклятие тяготеет над тобой: что-то странное (20 с)!", time = 10 },
	{ id = 2, kind = "curse", text = "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!", time = 900 },
}
local curses2 = SurvivorUI_RebornCurses()
eq("pr4 curse: elapsed historical banner not relatched fresh", table.getn(curses2.items), 1)
eq("pr4 curse: latest historical banner latched", curses2.items[1].effectId, "horde_surge")
AZS_BANNERS = { { id = 3, kind = "curse", text = "Проклятие тяготеет над тобой: что-то странное (20 с)!", time = 950 } }
local curses3 = SurvivorUI_RebornCurses()
check("pr4 curse: unknown effect keeps raw text", string.find(curses3.items[table.getn(curses3.items)].text, "странное", 1, true) ~= nil)

-- Diagnostic recorder: disabled by default, bounded, sanitized.
local nativeDiagnosticHandlers = {}
AZS = { On = function(prefix, callback) nativeDiagnosticHandlers[prefix] = callback end }
dofile("SurvivorUI/RebornDiagnostics.lua")
SurvivorUI_RebornRecord("test_event", { x = 1 })
local st = SurvivorUI_RebornRecordStatus()
eq("diag: inactive by default", st.active, false)
eq("diag: nothing recorded while inactive", st.events, 0)
local sid = SurvivorUI_RebornRecordStart()
check("diag: session id issued", sid ~= nil)
SurvivorUI_RebornRecord("test_event", { ownerId = "hero:secret", value = "Проклятие" })
local db = SurvivorUIRebornDiagnostics
local sess = db.sessions[sid]
check("diag: events recorded", table.getn(sess.events) >= 2)
local foundSanitized = false
for i = 1, table.getn(sess.events) do
	if sess.events[i].type == "test_event" and sess.events[i].data.ownerId == "player-1" then
		foundSanitized = true
	end
end
check("diag: owner identifiers sanitized", foundSanitized)
SurvivorUI_RebornRecord("nested_payload", {
	read = { lines = { { left = "Fireball", color = { 1, 0.5, 0.25 } } } },
	jewelry = { raw = { sources = { s1 = { icon = { path = "icon", meta = { effect = { value = 3 } } } } } } },
})
local nested = sess.events[table.getn(sess.events)].data
eq("diag: nested tooltip color preserved", nested.read.lines[1].color[2], 0.5)
eq("diag: nested jewelry effect preserved", nested.jewelry.raw.sources.s1.icon.meta.effect.value, 3)
eq("diag: stop completes session", SurvivorUI_RebornRecordStop(), sid)
eq("diag: completed status", sess.status, "completed")
SurvivorUI_RebornRecordAuto(true)
eq("diag: auto on starts recording", SurvivorUI_RebornRecordStatus().active, true)
local _, autoStopped = SurvivorUI_RebornRecordAuto(false)
eq("diag: auto off stops recording", autoStopped, true)
eq("diag: auto off inactive", SurvivorUI_RebornRecordStatus().active, false)
-- Repeated identical extra-button updates record one transition.
SurvivorUI_RebornRecordStart()
local db3 = SurvivorUIRebornDiagnostics
local sess3 = db3.sessions[db3.order[table.getn(db3.order)]]
local beforeDedup = table.getn(sess3.events)
for i = 1, 300 do
	SurvivorUI_RebornRecord("extra_button", { button = 12, spell = 20549, visible = true, ownedBinding = false })
	SurvivorUI_RebornRecord("capture_note", { text = "extra button 12 spell=20549 ownedBinding=false" })
end
eq("diag: repeated extra-button state recorded once", table.getn(sess3.events), beforeDedup + 2)
SurvivorUI_RebornRecord("extra_button", { button = 12, spell = nil, visible = false })
eq("diag: extra-button transition recorded", table.getn(sess3.events), beforeDedup + 3)
SurvivorUI_RebornRecordStop()
-- SavedVariables available only after file load: initialization
-- (not file scope) starts auto recording exactly once.
SurvivorUIDB.rebornRecordAuto = true
local sessionsBeforeInit = table.getn(SurvivorUIRebornDiagnostics.order)
SurvivorUI_RebornRecordInitialize()
eq("diag: auto recording starts on initialize", SurvivorUI_RebornRecordStatus().active, true)
eq("diag: initialize creates one session", table.getn(SurvivorUIRebornDiagnostics.order), sessionsBeforeInit + 1)
SurvivorUI_RebornRecordInitialize()
eq("diag: initialize is exactly once", table.getn(SurvivorUIRebornDiagnostics.order), sessionsBeforeInit + 1)
-- Play Again: a new run id records a transition in the same session.
local autoSession = SurvivorUIRebornDiagnostics.sessions[SurvivorUIRebornDiagnostics.order[table.getn(SurvivorUIRebornDiagnostics.order)]]
AZS_ZONE = { run = "azs:playagain1" }
SurvivorUI_RebornCheckRun()
AZS_ZONE = { run = "azs:playagain2" }
SurvivorUI_RebornCheckRun()
local transitions = 0
for i = 1, table.getn(autoSession.events) do
	if autoSession.events[i].type == "run_transition" then transitions = transitions + 1 end
end
check("diag: Play Again records run transitions in one session", transitions >= 2)
SurvivorUI_RebornRecordStop()
SurvivorUIDB.rebornRecordAuto = false
-- Cooldown-only updates do not flood the recorder.
SurvivorUI_RebornRecordStart()
local db2 = SurvivorUIRebornDiagnostics
local sess2 = db2.sessions[db2.order[table.getn(db2.order)]]
AZS_ABILITIES = { { key = "fireball", spell = 133, rank = 3, passive = false, kind = "class", cd = 5, cdmax = 8, name = "Fireball" } }
AZS_SPELLS = { { "fireball", 133, 3, 5, 8 } }
AZS_ABILITIES_UPDATED = 500
AZS_SPELLS_UPDATED = 500
SurvivorUI_RebornAbilities()
local afterFirst = table.getn(sess2.events)
for i = 1, 20 do
	AZS_SPELLS = { { "fireball", 133, 3, 5 - i * 0.1, 8 } }
	AZS_SPELLS_UPDATED = 500 + i
	SurvivorUI_RebornAbilities()
end
eq("diag: cooldown-only updates not recorded", table.getn(sess2.events), afterFirst)
SurvivorUI_RebornRecordStop()
-- Restarted banner IDs with different timestamps stay distinct.
AZS_RUN = { id = "run-key-test" }
SurvivorUI_RebornCheckRun()
AZS_BANNERS = { { 7, "curse", nil, "Проклятие", "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!", 20 } }
eq("banner key: first curse", table.getn(SurvivorUI_RebornCurses().items), 1)
AZS_RUN = { id = "run-key-test-2" }
SurvivorUI_RebornCheckRun()
AZS_BANNERS = { { 7, "curse", nil, "Проклятие", "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!", 20 } }
eq("banner key: reused id in new run still counts", table.getn(SurvivorUI_RebornCurses().items), 1)
AZS_BANNERS = { { 23, "curse", nil, "", "涌动平息了。", 24 } }
eq("curse ending banner clears tracked curse", table.getn(SurvivorUI_RebornCurses().items), 0)
-- Real session 002: damage-taken curse and its ending.
AZS_GetRunTime = function() return 30 end
AZS_BANNERS = { { 18, "curse", nil, "", "Проклятие тяготеет над тобой: ты получаешь на 40% больше урона (20 с)!", 220 } }
local dmgCurses = SurvivorUI_RebornCurses()
eq("curse: damage taken recognized", table.getn(dmgCurses.items), 1)
eq("curse: damage taken id", dmgCurses.items[1].effectId, "damage_taken")
eq("curse: damage taken percent", dmgCurses.items[1].text, "Damage taken increased 40%")
AZS_BANNERS = { { 21, "curse", nil, "", "你的脆弱消退了。", 249 } }
eq("curse: vulnerability ending clears damage taken", table.getn(SurvivorUI_RebornCurses().items), 0)
-- An old ending must not clear a later acquisition.
AZS_BANNERS = { { 71, "curse", nil, "", "Проклятие тяготеет над тобой: ты получаешь на 40% больше урона (20 с)!", 635 } }
eq("curse: later acquisition active", table.getn(SurvivorUI_RebornCurses().items), 1)
AZS_BANNERS = { { 99, "curse", nil, "", "你的脆弱消退了。", 600 } }
eq("curse: old ending does not clear later acquisition", table.getn(SurvivorUI_RebornCurses().items), 1)
-- Real session 003: elite ambush is an event curse with no countdown.
AZS_BANNERS = { { 57, "curse", nil, "", "诅咒降临：精英正在伏击你！", 1239 } }
local ambush = SurvivorUI_RebornCurses()
eq("curse: elite ambush recognized", ambush.items[table.getn(ambush.items)].effectId, "elite_ambush")
eq("curse: elite ambush has no invented countdown", ambush.items[table.getn(ambush.items)].left, nil)
-- Racial cooldown interpolates from the Reborn cd sample.
AZS_GetRunTime = function() return 100 end
AZS_ABILITIES = { { key = "war_stomp", spell = 20549, rank = 1, passive = false, kind = "racial", cd = 10, cdmax = 15, name = "War Stomp", icon = "i", text = "t" } }
AZS_SPELLS = {}
AZS_ABILITIES_UPDATED = (AZS_ABILITIES_UPDATED or 0) + 1
AZS_SPELLS_UPDATED = (AZS_SPELLS_UPDATED or 0) + 1
SurvivorUI_RebornAbilities()
local remaining, cdmax = SurvivorUI_RebornRacialCooldown(20549)
eq("racial cd: sampled remaining", remaining, 10)
eq("racial cd: cdmax", cdmax, 15)
AZS_GetRunTime = function() return 104 end
eq("racial cd: interpolates on run clock", (SurvivorUI_RebornRacialCooldown(20549)), 6)
AZS_SPELLS = { { "shadow_bolt", 686, 1, 0, 0 } }
AZS_SPELLS_UPDATED = (AZS_SPELLS_UPDATED or 0) + 1
SurvivorUI_RebornAbilities()
eq("racial cd: spells-only update keeps sample time", (SurvivorUI_RebornRacialCooldown(20549)), 6)
AZS_GetRunTime = function() return 110 end
eq("racial cd: reaches zero", (SurvivorUI_RebornRacialCooldown(20549)), 0)
local previousAbilityRequest = AZS_RequestAbilities
local renderRequests = 0
AZS_RequestAbilities = function() renderRequests = renderRequests + 1 end
SurvivorUI_RebornRequestAbilities(true)
AZS_RUN.ph = "paused"
fakeTime = fakeTime + 5
SurvivorUI_RebornRacialCooldown(20549, true)
eq("racial cd: overlay does not request while paused", renderRequests, 1)
AZS_RUN.ph = "playing"
SurvivorUI_RebornRacialCooldown(20549, true)
SurvivorUI_RebornRacialCooldown(20549, true)
eq("racial cd: overlay refreshes once without the Build panel", renderRequests, 2)
AZS_RequestAbilities = previousAbilityRequest
AZS_ABILITIES = { { key = "war_stomp", spell = 20549, rank = 1, passive = false, kind = "racial", cd = 12, cdmax = 15, name = "War Stomp", icon = "i", text = "t" } }
AZS_ABILITIES_UPDATED = (AZS_ABILITIES_UPDATED or 0) + 1
SurvivorUI_RebornAbilities()
eq("racial cd: new snapshot resynchronizes", (SurvivorUI_RebornRacialCooldown(20549)), 12)
AZS_ZONE = { run = "azs:racialreset" }
SurvivorUI_RebornCheckRun()
eq("racial cd: reset between runs", (SurvivorUI_RebornRacialCooldown(20549)), nil)
-- Build tooltip lines: passive abilities carry their Reborn text.
local dkLines = SurvivorUI_RebornAbilityTooltipLines({ key = "demonic_knowledge", rank = 31, passive = true, text = "始终生效。你的恶魔随该法术的卡牌成长" })
eq("tooltip lines: passive description first", dkLines[1].text, "始终生效。你的恶魔随该法术的卡牌成长")
eq("tooltip lines: passive label", dkLines[2].kind, "passive")
eq("tooltip lines: rank line", dkLines[3].kind, "rank")
local racialPassiveLines = SurvivorUI_RebornAbilityTooltipLines({ key = "the_human_spirit", rank = 1, passive = true, text = "经验值+20%" })
eq("tooltip lines: racial passive description", racialPassiveLines[1].text, "经验值+20%")
local slottedPassivePlan = SurvivorUI_RebornBuildTooltipPlan({ key = "demonic_knowledge", rank = 31, passive = true, text = "始终生效。你的恶魔随该法术的卡牌成长" })
eq("tooltip plan: slotted passive uses reborn mode", slottedPassivePlan.mode, "reborn")
eq("tooltip plan: slotted passive has base", slottedPassivePlan.hasBase, true)
local noTextPlan = SurvivorUI_RebornBuildTooltipPlan({ key = "demonic_knowledge", rank = 31, passive = true, text = "" })
eq("tooltip plan: empty text is not a base", noTextPlan.hasBase, false)
eq("tooltip plan: missing text stays reborn mode", noTextPlan.mode, "reborn")
-- Session 004: healing reduction and its ending.
AZS_GetRunTime = function() return 60 end
AZS_BANNERS = { { 41, "curse", nil, "", "Проклятие тяготеет над тобой: твоё исцеление снижено на 60% (25 с)!", 900 } }
local healCurses = SurvivorUI_RebornCurses()
eq("curse: healing reduced id", healCurses.items[table.getn(healCurses.items)].effectId, "healing_reduced")
AZS_BANNERS = { { 44, "curse", nil, "", "凋零消退了。", 933 } }
local healGone = true
for i = 1, table.getn(SurvivorUI_RebornCurses().items) do
	if SurvivorUI_RebornCurses().items[i].effectId == "healing_reduced" then healGone = false end
end
eq("curse: wither ending clears healing reduced", healGone, true)
-- Rift Portal boss model (synthetic AZS_UNITS; session 004 has no raw units).
AZS_RUN = { ph = "playing", bk = 5 }
AZS_UNITS = { { kind = "rift", id = 777, name = "暴君魔暴龙", hp = 500, hpm = 1000, state = 0 } }
local riftBosses = SurvivorUI_RebornRiftBosses()
eq("rift boss: tracked", table.getn(riftBosses), 1)
eq("rift boss: identity", riftBosses[1].id, 777)
AZS_UNITS = {}
eq("rift boss: transient disappearance is not death", SurvivorUI_RebornRiftBosses()[1].state, "up")
AZS_RUN = { ph = "playing", bk = 6 }
eq("rift boss: unrelated boss count does not confirm death", SurvivorUI_RebornRiftBosses()[1].state, "up")
eq("rift boss: missing row remains unlocated", SurvivorUI_RebornRiftBosses()[1].missing, true)
AZS_RIFT = { st = "boss" }
AZS_UNITS = { { kind = "rift", id = 777, name = "Rift boss", hp = 50, hpm = 100 } }
eq("rift boss: reappearing row restores live health", SurvivorUI_RebornRiftBosses()[1].healthShare, 0.5)
AZS_UNITS[1].hp = nil
eq("rift boss: missing health stays unknown", SurvivorUI_RebornRiftBosses()[1].healthShare, nil)
AZS_UNITS = {}
AZS_RIFT.st = "done"
eq("rift boss: observed portal completion confirms death", SurvivorUI_RebornRiftBosses()[1].state, "dead")
AZS_RIFT = nil
AZS_UNITS = nil
-- Guardian countdown model (synthetic AZS_LAIRS; no runtime samples yet).
AZS_GetRunTime = function() return 100 end
AZS_LAIRS_UPDATED = 1
local lair = { index = 2, state = "empty", name = "G", id = 9, left = 47 }
eq("guardian: positive left", SurvivorUI_RebornGuardianLeft(lair), 47)
AZS_GetRunTime = function() return 110 end
eq("guardian: decays on run clock", SurvivorUI_RebornGuardianLeft(lair), 37)
AZS_LAIRS_UPDATED = 2
lair.left = 50
eq("guardian: fresh snapshot resyncs", SurvivorUI_RebornGuardianLeft(lair), 50)
lair.left = -1
AZS_LAIRS_UPDATED = 3
eq("guardian: negative left unsupported", SurvivorUI_RebornGuardianLeft(lair), nil)
lair.left = 0
AZS_LAIRS_UPDATED = 4
eq("guardian: zero is valid", SurvivorUI_RebornGuardianLeft(lair), 0)
-- Jewelry: distinct instances sharing category sources (session 004 seq 374).
AZS_GetMeterLoadout = function()
	return {
		runJewelry = {
			{ category = "trinket", slotId = 1, sourceKey = "jewel:trinket", itemInstanceKey = "gear:trinket:chosen", effectSourceKeys = {} },
			{ category = "trinket", slotId = 2, sourceKey = "jewel:trinket", itemInstanceKey = "gear:trinket:insignia", effectSourceKeys = {} },
			{ category = "ring", slotId = 3, sourceKey = "jewel:ring", itemInstanceKey = "gear:ring:quick_strike", effectSourceKeys = {} },
			{ category = "ring", slotId = 4, sourceKey = "jewel:ring", itemInstanceKey = "gear:ring:accuria", effectSourceKeys = {} },
		},
		sources = {
			["jewel:ring"] = { itemKey = "accuria", name = "埃库利亚指环", rank = 520, icon = { path = "Interface\\Icons\\INV_Jewelry_Ring_15" } },
			["jewel:trinket"] = { itemKey = "insignia", name = "部落徽记", rank = 54, icon = { path = "Interface\\Icons\\INV_Jewelry_Talisman_08" } },
		},
	}
end
local jew004 = SurvivorUI_RebornJewelry(true)
eq("jewelry004: four rows", table.getn(jew004.items), 4)
eq("jewelry004: chosen not insignia", jew004.items[1].name ~= "部落徽记", true)
eq("jewelry004: chosen rank unknown", jew004.items[1].rank, nil)
eq("jewelry004: insignia keeps source rank", jew004.items[2].rank, 54)
eq("jewelry004: quick_strike not accuria", jew004.items[3].name ~= "埃库利亚指环", true)
eq("jewelry004: accuria keeps source rank", jew004.items[4].rank, 520)
-- Event curses expire as notifications, not at run end.
AZS_GetRunTime = function() return 200 end
AZS_BANNERS = { { 57, "curse", nil, "", "诅咒降临：精英正在伏击你！", 1239 } }
SurvivorUI_RebornCurses()
AZS_GetRunTime = function() return 215 end
local afterEvent = SurvivorUI_RebornCurses()
local eventStillShown = false
for i = 1, table.getn(afterEvent.items) do
	if afterEvent.items[i].effectId == "elite_ambush" then eventStillShown = true end
end
eq("curse: event notification expires", eventStillShown, false)

-- Reborn caps and native run values use whole percentages.
AZS_ZONE = { hub = 0 }
AZS_RUN = { ph = "playing" }
AZS_RUNSTATS = { cdr = "65", crit = 80, red = 0 }
AZS_CAPS = { cdr = 80, crit = 80, red = 60, echo = 100 }
AZS_GetStatCaps = function() return { cdr = 75, crit = 80 } end
local cap, room = SurvivorUI_RebornStatCap("cdr")
eq("stats: getter cap preferred", cap, 75)
eq("stats: headroom in percentage points", room, 10)
cap, room = SurvivorUI_RebornStatCap("crit")
eq("stats: exact cap", cap, 80)
eq("stats: capped has zero headroom", room, 0)
cap, room = SurvivorUI_RebornStatCap("red")
eq("stats: partial getter falls back per key", cap, 60)
eq("stats: zero is a known current value", room, 60)
cap, room = SurvivorUI_RebornStatCap("echo")
eq("stats: cap before current snapshot", cap, 100)
eq("stats: missing current has unknown headroom", room, nil)
AZS_GetStatCaps = function() error("unavailable") end
AZS_CAPS = { cdr = 60 }
cap, room = SurvivorUI_RebornStatCap("cdr")
eq("stats: replacement snapshot after getter error", cap, 60)
eq("stats: no inferred overflow", room, 0)
AZS_CAPS = {}
eq("stats: missing cap stays unknown", SurvivorUI_RebornStatCap("cdr"), nil)
AZS_CAPS = { cdr = 80 }
AZS_ZONE.hub = "1"
eq("stats: hub does not show run caps", SurvivorUI_RebornStatCap("cdr"), nil)
AZS_ZONE.hub = 0
AZS_RequestAbilities = nil
eq("stats: original client ignored", SurvivorUI_RebornStatCap("cdr"), nil)

-- A shared trinket source forces the fallback name for the other instance.
dofile("SurvivorUI/LocaleData.lua")
dofile("SurvivorUI/Locale.lua")
dofile("SurvivorUI/Locale_zh.lua")
AZS_ZONE.rname = "Human"
local locale = "en"
AZS_GetMeterCapabilities = function() return { languageCode = locale } end
local localeTime = 1000
GetTime = function() return localeTime end
AZS_GetMeterLoadout = function()
	return {
		runJewelry = {
			{ sourceKey = "jewel:trinket", itemInstanceKey = "gear:trinket:tep" },
		},
		sources = { ["jewel:trinket"] = { itemKey = "insignia", name = "Insignia", rank = 25 } },
	}
end
eq("jewelry locale: English fallback", SurvivorUI_RebornJewelry(true).items[1].name, "Talisman of Ephemeral Power")
locale, localeTime = "zh", 1002
local zhJewelry = SurvivorUI_RebornJewelry(true).items[1]
eq("jewelry locale: Chinese fallback", zhJewelry.name, "短暂能量护符")
eq("jewelry locale: instance unchanged", zhJewelry.instanceKey, "gear:trinket:tep")
eq("jewelry locale: meter attribution retained", zhJewelry.sourceKey, "jewel:trinket")
eq("jewelry locale: shared source rank ignored", zhJewelry.rank, nil)

AZS_RequestAbilities = function() end
AZS_RUNSTATS = { crit = 100, cdr = 79 }
AZS_CAPS = { crit = 100, cdr = 80 }
local card = { mode = "grow", detail = "暴击几率=76.9%=83.7%=+^冷却缩减=10%=11%=+" }
local display = "|cff999999暴击几率|r  76.9% » |cff1eff0083.7%|r\n冷却缩减  10% » 11%"
eq("cards: annotate only capped global stat in Chinese",
	SurvivorUI_RebornCardCapLines(card, display),
	"|cff999999暴击几率|r  76.9% » |cff1eff0083.7%|r |cffffc04c(已达上限)|r\n冷却缩减  10% » 11%")
locale, localeTime = "en", 1004
card.detail = "Critical strike chance=76.9%=83.7%=+"
display = "Critical strike chance  76.9% » 83.7%"
eq("cards: capped English label", SurvivorUI_RebornCardCapLines(card, display),
	display .. " |cffffc04c(At cap)|r")
AZS_RUNSTATS.crit = nil
eq("cards: unknown global stat", SurvivorUI_RebornCardCapLines(card, display), display)
AZS_RUNSTATS.crit = 100
card.detail = "Critical strike chance=83.7%=76.9%=-"
eq("cards: decrease carries no hint", SurvivorUI_RebornCardCapLines(card, display), display)
card.mode = "new"
card.detail = "Critical strike chance=76.9%=83.7%=+"
eq("cards: new item is not an upgrade comparison", SurvivorUI_RebornCardCapLines(card, display), display)

local rendered = display
local button = { Fit = function() end, detail = {
	GetText = function() return rendered end,
	SetText = function(_, value) rendered = value end,
} }
AZSCardsFrame = {}
getglobal = function(name) return name == "AZSCard1" and button or nil end
hooksecurefunc = function(object, method, after)
	local native = object[method]
	object[method] = function() native(); after() end
end
card.mode = "grow"
AZS_CARDS = { kind = "jewel", cards = { card } }
dofile("SurvivorUI/CardsNotice.lua")
button.Fit()
local marked = rendered
button.Fit()
eq("cards: repeated native layout adds one hint", rendered, marked)
button.saved = { marked }
rendered = "Equipped item comparison"
button.Fit()
eq("cards: Shift comparison left intact", rendered, "Equipped item comparison")
button.saved = nil
rendered = marked
AZS_CARDS = { kind = "spell", cards = {} }
button.Fit()
eq("cards: next offer clears the old hint", rendered, display)

local hintsEnabled = true
SurvivorUI_RebornAnalysis = {
	WantsCardHints = function() return hintsEnabled end,
	CardText = function(index) assert(index == 1); return "Ideal CD 1.40s → 1.20s" end,
}
button.IsShown = function() return true end
AZSCardsFrame.IsShown = function() return true end
button.label = { SetText = function() end }
-- Reload this mock's Fit from a fresh native function to avoid hooking twice.
button.Fit = function() end
dofile("SurvivorUI/CardsNotice.lua")
AZS_CARDS = { kind = "jewel", cards = { card } }
button.label:SetText("Native card label")
rendered = display
button.Fit()
local analyzed = marked .. "\n|cff92dce5Ideal CD 1.40s → 1.20s|r"
eq("cards: analysis appends after native cap", rendered, analyzed)
button.Fit()
eq("cards: repeated analysis Fit does not duplicate", rendered, analyzed)
local displayedHand = AZS_CARDS
AZS_CARDS = { kind = "jewel", cards = { card } }
SurvivorUI_RebornAnalysis.CardText = function() return "Successor estimate" end
button.Fit()
button.Fit()
eq("cards: outgoing Fit keeps the displayed hand", rendered, analyzed)
AZS_CARDS = displayedHand
SurvivorUI_RebornAnalysis.CardText = function() return "Ideal CD 1.40s → 1.20s" end
button.saved = { rendered }
rendered = "Equipped item comparison"
hintsEnabled = false
SurvivorUI_RebornAnalysis.ClearCardDisplay()
eq("cards: clearing analysis preserves Shift comparison", rendered, "Equipped item comparison")
eq("cards: clearing analysis removes it from restored text", button.saved[1], marked)
rendered = button.saved[1]
button.saved = nil
hintsEnabled = true
SurvivorUI_RebornAnalysis.RefreshCardDisplay()
eq("cards: refresh reattaches analysis to the same hand", rendered, analyzed)
SurvivorUI_RebornAnalysis.CardText = function() error("simulated analysis failure") end
button.Fit()
eq("cards: analysis failure leaves the native cap hint", rendered, marked)
SurvivorUI_RebornAnalysis = nil

local curseClock = 300
AZS_GetRunTime = function() return curseClock end
AZS_BANNERS = { {
	id = 214, kind = "curse", time = localeTime,
	text = "Проклятие тяготеет над тобой: враги движутся на 50% быстрее (20 с)!",
} }
local function EnemySpeedCurse()
	for _, effect in ipairs(SurvivorUI_RebornCurses().items) do
		if effect.effectId == "enemy_speed" then return effect end
	end
end
local speedCurse = EnemySpeedCurse()
eq("curse: enemy movement English", speedCurse and speedCurse.text, "Enemy speed increased 50%")
eq("curse: enemy movement duration from banner", speedCurse and speedCurse.left, 20)
locale, localeTime, curseClock = "zh", 1006, 307
speedCurse = EnemySpeedCurse()
eq("curse: enemy movement Chinese", speedCurse and speedCurse.text, "敌人移动速度提高50%")
eq("curse: enemy movement counts down on run clock", speedCurse and speedCurse.left, 13)
local warningText = AZS_BANNERS[1].text
local bossText = "Rift boss appeared"
RaidWarningFrame = {
	slot1 = { GetText = function() return warningText end, SetText = function(_, value) warningText = value end },
	slot2 = { GetText = function() return bossText end, SetText = function(_, value) bossText = value end },
}
raidNoticeHook(RaidWarningFrame, warningText)
eq("curse: native raid warning in Chinese", warningText, "诅咒降临：敌人移动速度提高50%（20秒）！")
eq("curse: adjacent warning stays intact", bossText, "Rift boss appeared")
locale, localeTime = "en", 1008
warningText = AZS_BANNERS[1].text
raidNoticeHook(RaidWarningFrame, warningText)
eq("curse: native raid warning in English", warningText, "Curse: Enemy speed increased 50% (20 sec)!")
curseClock = 320
eq("curse: enemy movement expires", EnemySpeedCurse(), nil)

AZS_SPELLTIPS = {}
local nativeSessionId = SurvivorUI_RebornRecordStart()
AZS_CARDS = { kind = "jewel", cards = { { mode = "grow", detail = "Crit chance=1%=2%=+" } } }
nativeDiagnosticHandlers.AZSCARDS()
nativeDiagnosticHandlers.AZSSPELLTIP("key=war_stomp;text=Stun nearby enemies")
nativeDiagnosticHandlers.AZSSPELLTIP("key=war_stomp;text=Stun nearby enemies")
AZS_LAIRS = { { index = 1, state = "empty", x = 10, y = 20, left = 30 } }
nativeDiagnosticHandlers.AZSLAIRS()
nativeDiagnosticHandlers.AZSLAIRS()
AZS_LAIRS[1] = { index = 1, id = 80, state = "asleep", x = 34, y = 22 }
nativeDiagnosticHandlers.AZSLAIRS()
SurvivorUI_RebornRecordStop()
local nativeEvents = {}
for _, event in ipairs(SurvivorUIRebornDiagnostics.sessions[nativeSessionId].events) do
	nativeEvents[event.type] = nativeEvents[event.type] or {}
	table.insert(nativeEvents[event.type], event.data)
end
eq("diag native: offer logged", nativeEvents.card_offer[1].hand.kind, "jewel")
eq("diag native: unchanged spell tip deduplicated", table.getn(nativeEvents.native_spell_tip), 1)
eq("diag native: empty and respawn recorded without duplicates", table.getn(nativeEvents.guardian_lairs), 2)
eq("diag native: guardian's new position captured", nativeEvents.guardian_lairs[2].rows[1].x, 34)

eq("history identity: native short ID normalized", SurvivorUI_RebornStableRunId("rABCDEF01"), "azs:rabcdef01")
eq("history identity: native prefixed ID retained", SurvivorUI_RebornStableRunId("azs:rabcdef01"), "azs:rabcdef01")
eq("history identity: transient session ID ignored", SurvivorUI_RebornStableRunId("azs:1000:1"), nil)
eq("history identity: protocol placeholder ignored", SurvivorUI_RebornStableRunId("1"), nil)
local spell = { key = "fireball", rank = 3, text = "Base description" }
AZS_ZONE.run = "azs:rabcdef01"
AZS_API_RunId = nil
AZS_SPELLS = {}
AZS_SPELLTIPS.fireball = "Current damage 125"
compatHandlers.AZSSPELLTIP("key=fireball;text=Current damage 125")
AZS_SPELLS = { { key = "fireball", rank = 3 } }
local currentLines = SurvivorUI_RebornAbilityTooltipLines(spell)
eq("spell tips: current text from native event", currentLines[3] and currentLines[3].text, "Current damage 125")
AZS_SPELLTIPS = { fireball = "Current damage 150" }
eq("spell tips: replaced native table invalidates older text", table.getn(SurvivorUI_RebornAbilityTooltipLines(spell)), 2)
compatHandlers.AZSSPELLTIP("key=fireball;text=Current damage 150")
eq("spell tips: same rank accepts refreshed text", SurvivorUI_RebornAbilityTooltipLines(spell)[3].text, "Current damage 150")
spell.text = "Updated ability snapshot"
eq("spell tips: changed description excludes an older native tip", table.getn(SurvivorUI_RebornAbilityTooltipLines(spell)), 2)
spell.text = "Base description"
spell.rank = 4
eq("spell tips: older rank excluded", table.getn(SurvivorUI_RebornAbilityTooltipLines(spell)), 2)
spell.rank = 3
AZS_ZONE.run = "azs:rabcdef02"
eq("spell tips: earlier run excluded", table.getn(SurvivorUI_RebornAbilityTooltipLines(spell)), 2)

for _, sentEarly in ipairs({ false, true }) do
	SurvivorUI_RebornForgetRun()
	AZS_ZONE.run = "azs:r11111111"
	AZS_ABILITIES = {}
	AZS_SPELLS = { { key = "old_spell", rank = 1 } }
	SurvivorUI_RebornCheckRun()
	SurvivorUI_RebornRequestAbilities(true)
	AZS_ZONE.run = "azs:r22222222"
	compatHandlers.AZSZONE()
	if sentEarly then SurvivorUI_RebornRequestAbilities(true) end
	AZS_ABILITIES = { { key = "old_passive", passive = true, rank = 1 } }
	AZS_ABILITIES_UPDATED = 901
	if sentEarly then compatHandlers.AZSABILITIES() end
	local partial = SurvivorUI_RebornAbilities()
	eq("run boundary: late reply does not complete new build", partial.complete, false)
	eq("run boundary: old passive and old action bar excluded", table.getn(partial.all), 0)
	SurvivorUI_RebornRequestAbilities(true)
	AZS_SPELLS = { { key = "new_spell", rank = 1 } }
	AZS_ABILITIES = { { key = "new_passive", passive = true, rank = 1 } }
	AZS_ABILITIES_UPDATED = 902
	eq("run boundary: new reply completes via stamp reader", SurvivorUI_RebornAbilities().complete, true)
	compatHandlers.AZSZONE()
	eq("run boundary: stage sharing run ID keeps accepted data", SurvivorUI_RebornAbilities().complete, true)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
