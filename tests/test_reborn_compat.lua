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
AZS_SPELLS_UPDATED = 9999
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
curses = SurvivorUI_RebornCurses()
eq("curses: one active item", table.getn(curses.items), 1)
eq("curses: effect translated", curses.items[1].text, "Horde surges ")
eq("curses: countdown from buff", curses.items[1].left, 10)

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
eq("round2 jewelry: deduped to 3 items", table.getn(jew.items), 3)
eq("round2 jewelry: duplicate merged count", jew.duplicates, 1)
eq("round2 jewelry: repeat count shown", jew.items[1].count, 2)
eq("round2 jewelry: slot from sourceKey (ring)", jew.items[1].slot, "Ring")
eq("round2 jewelry: slot from sourceKey (trinket)", jew.items[2].slot, "Trinket")
eq("round2 jewelry: slot from sourceKey (neck)", jew.items[3].slot, "Neck")
check("round2 jewelry: two 55s are distinct pieces", jew.items[1].name ~= jew.items[2].name)
eq("round2 jewelry: icon kept", jew.items[1].icon, "INV_Jewelry_Ring_01")
eq("round2 jewelry: rarity kept, not invented", jew.items[3].rarity, "epic")
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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
