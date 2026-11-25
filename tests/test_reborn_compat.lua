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
function SurvivorUI_TF(s, ...) return s end

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
eq("boss rift: text", text, "Rift 42%")
check("boss rift: text is rift", isRift == true)

resetGame()
-- Missing rift field is missing, not 0 (VERIFIED doc rule).
AZS_RUN = { ph = "playing", t = 10, nbs = "known", nbm = "rift", nb = -1, nbn = "Rift Boss" }
nb = SurvivorUI_RebornNextBoss()
check("boss rift missing: mode", nb and nb.mode == "rift")
eq("boss rift missing: rift is nil, not 0", nb and nb.rift, nil)
eq("boss rift missing: text", SurvivorUI_RebornNextBossText(nb), "Rift")

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
-- the passive NOT masquerading as the racial.
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
eq("abilities snapshot: actives", table.getn(data.actives), 2)
eq("abilities snapshot: passives", table.getn(data.passives), 1)
eq("abilities snapshot: racials", table.getn(data.racials), 1)
eq("abilities snapshot: demonic empowerment is passive", data.passives[1] and data.passives[1].key, "demonic_empowerment")
eq("abilities snapshot: racial is berserking", data.racials[1] and data.racials[1].key, "berserking")
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
eq("abilities throttle: request after 5s allowed", requestCount, 2)

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
-- Curses (VERIFIED: not documented)
-- ===========================================================================
resetGame()
local curses = SurvivorUI_RebornCurses()
check("curses: not supported", curses.supported == false)
eq("curses: no items invented", table.getn(curses.items), 0)
check("curses: reason explains the blocker", curses.reason ~= nil and string.find(curses.reason, "not documented") ~= nil or string.find(curses.reason, "No curse") ~= nil)

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

-- Probe runs without crashing and reports the boss/ability state.
resetGame()
AZS_RUN = { ph = "playing", nbs = "known", nbm = "rift", rift = 10, nb = -1 }
local lines = SurvivorUI_RebornProbe()
check("probe: returns lines", type(lines) == "table" and table.getn(lines) > 5)
local joined = table.concat(lines, "\n")
check("probe: mentions rift", string.find(joined, "rift") ~= nil)
check("probe: mentions curses unsupported", string.find(joined, "curses: supported=false") ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
