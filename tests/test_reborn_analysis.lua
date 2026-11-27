-- Model and native-event contract tests. No gameplay command is required.
table.getn = table.getn or function(t) return #t end
dofile("SurvivorUI/RebornAnalysisModel.lua")
dofile("SurvivorUI/RebornMapReference.lua")
local model = SurvivorUI_RebornAnalysisModel
local function near(a, b) assert(math.abs(a - b) < 0.000001, tostring(a) .. " ~= " .. tostring(b)) end
local spell = { key = "shadow_bolt", spell = 686, rank = 1, cdmax = 1.4 }
local card = { key = "shadow_bolt", spell = 686, rank = 2, new = 0, rarity = 4, lines = "d65:0:65c23:0:23" }
local value = assert(model.Skill(card, spell, 0.45))
near(value.damage, 65)
near(value.cooldown.ideal, 1.4 * 0.77)
near(value.meterScenario, 45 * (1.65 / 0.77 - 1))
assert(model.Boosts("d34:0:34")[1].after == 34)
assert(not model.Boosts("d34:0"))
assert(not model.Boosts("d34::34"))
assert(not model.Boosts("d34x"))
assert(not model.Boosts("d34^c13"))
assert(not model.Boosts("d3400000000"))
card.lines = "d65:100:165"
assert(model.Skill(card, spell, 0.45).meterScenario == nil, "conflicting native totals invalidate DPS estimate")
card.lines = "d65a50"
assert(model.Skill(card, spell, 0.45).partial and model.Skill(card, spell, 0.45).meterScenario == nil)
card.lines = "d65"
card.rank = 3
assert(not model.Skill(card, spell, 0.45), "stale rank")
card.rank = 2
assert(not model.Skill(card, { key = "shadow_bolt", spell = 687, rank = 1 }, 0.45))
card.new = 1
assert(not model.Skill(card, spell, 0.45))
card.new = 0
local label = function() return "red" end
local cap = function() return 60, 3 end
local jewel = { mode = "grow", detail = "Damage reduction=4%=9%=+" }
local change = model.Jewelry(jewel, label, cap).changes[1]
near(change.delta, 5)
near(change.room, 3)
jewel.mode = "amulet"
assert(not model.Jewelry(jewel, label, cap).changes[1].room, "replacement cannot assume cap room")
jewel.mode = "grow"
jewel.detail = "Damage reduction=5%=5%=="
assert(not model.Jewelry(jewel, label, cap).changes[1].delta)
jewel.detail = "Damage reduction=5%=10=+"
assert(not model.Jewelry(jewel, label, cap).changes[1].delta)
jewel.detail = "broken"
assert(not model.Jewelry(jewel, label, cap))
local reference = SurvivorUI_RebornMapReference
local maps = 0
for key in pairs(reference) do
	for tier = 0, 5 do assert(model.Map(reference, key, tier)) end
	maps = maps + 1
end
assert(maps == 48 and not model.Map(reference, "community", 0))
assert(not model.Map(reference, "naxx", 6))
local map = model.Map(reference, "naxx", 0)
assert(map.health == 100 and map.bossHealth == 100 and map.bossHit == 100 and map.firstBossHealth == 100)
near(model.Map(reference, "naxx", 5).bossHit, 216)

local samples = {}
for time = 0, 50, 5 do
	samples = model.Observe(samples, { time = time, segment = "wave", cap = 120, alive = time + 30, hpRatio = 1,
		kills = 2 * time, taken = time, level = 3, xp = time })
end
local state = model.Summarize(samples)
assert(table.getn(samples) == 7 and state.elapsed == 30 and state.buildup)
near(state.killsPerMin, 120)
near(state.takenPerSec, 1)
near(state.xpPerSec, 1)
assert(not model.Advice(state, { { meterScenario = 5 }, { meterScenario = 6 } }))
local red = { changes = { { stat = "red", room = 3 } } }
local defense = model.Advice({ survival = true }, { red, red, red })
assert(not defense)
local onlyDefense = model.Advice({ survival = true }, { {}, red })
assert(onlyDefense == 2)
samples = model.Observe(samples, { time = 51, segment = "boss", inBoss = true, hpRatio = 0.1 })
assert(table.getn(samples) == 1 and not model.Summarize(samples).survival)
samples = model.Observe(samples, { time = 80, segment = "boss" })
assert(table.getn(samples) == 1, "history gap resets series")

local handlers, emitted = {}, {}
AZS = { On = function(prefix, fn) handlers[prefix] = fn end }
local apiCalls, meterCalls, capCalls = 0, 0, 0
local recording = false
function SurvivorUI_RebornActive() apiCalls = apiCalls + 1; return true end
function SurvivorUI_RebornRunId() return AZS_ZONE.run end
function SurvivorUI_T(key) return key end
function SurvivorUI_RebornRecording() return recording end
function SurvivorUI_RebornRecord(kind, data) table.insert(emitted, { kind = kind, data = data }) end
function SurvivorUI_RebornCardStatKey(key) if key == "Damage reduction" then return "red" end end
function SurvivorUI_RebornStatCap(key, observed)
	capCalls = capCalls + 1
	assert(key == "red")
	return AZS_CAPS.red, math.max(0, AZS_CAPS.red - observed)
end
local ambiguous
function AZS_GetMeterSnapshot(query)
	meterCalls = meterCalls + 1
	assert(query.scope == "self" and query.apiVersion == 1 and query.windowSeconds == 20)
	return { totals = { windowAmount = 100, recentRate = { status = "ready", elapsedSeconds = 20, value = 5 } },
		rows = { { windowAmount = 46, sourceKey = "a" }, { windowAmount = 54, sourceKey = "b" } },
		sources = { a = { kind = "ability", abilityKey = "shadow_bolt", spellIds = { 686 } },
			b = { kind = ambiguous and "ability" or "other", abilityKey = "shadow_bolt", spellIds = { 686 } } } }
end
function SendAddonMessage() error("analysis must not send game actions") end
AZS_ZONE = { run = "azs:r00000001", zone = "naxx", dt = 0 }
AZS_ZONE_UPDATED, AZS_SPELLS_UPDATED, AZS_CAPS_UPDATED, AZS_STATS_UPDATED = 1, 2, 2, 2
AZS_CAPS, AZS_RUNSTATS, AZS_GEAR, AZS_UNITS = { red = 60 }, { red = 57 }, {}, {}
AZS_STATS = { arm = 0.57 }
AZS_SPELLS = { spell }
AZS_CARDS = { kind = "spell", cards = { card } }
SurvivorUIDB = {}
dofile("SurvivorUI/RebornAnalysis.lua")
local analysis = SurvivorUI_RebornAnalysis
local function tick(time, alive, hp)
	AZS_RUN = { ph = "playing", t = time, bs = 0, en = alive, enm = 120, kills = time * 2,
		hp = hp or 100, hpm = 100, taken = time * 3, lvl = 3, xp = time }
	handlers.AZSRUN()
end
local lines = {}
local tooltip = { AddLine = function(_, line) table.insert(lines, line) end }
for time = 0, 500 do tick(time, 40) end
handlers.AZSCARDS()
analysis.AddTrackerTooltip(tooltip)
assert(not analysis.CardText(1) and apiCalls == 0 and meterCalls == 0 and capCalls == 0 and #lines == 0)
analysis.Toggle("enabled")
for time = 0, 25, 5 do tick(time, 40 + time) end
AZS_SPELLS_UPDATED = 0
assert(not analysis.CardText(1))
AZS_SPELLS_UPDATED = 2
local text = assert(analysis.CardText(1))
assert(string.find(text, "+29.9%", 1, true) and meterCalls == 1)
assert(analysis.CardText(1) == text and meterCalls == 1, "same hand reuses native meter result")
ambiguous = true
AZS_CARDS = { kind = "spell", cards = { card } }
assert(not string.find(analysis.CardText(1), "DPS", 1, true), "duplicate matching sources are ambiguous")
ambiguous = nil
analysis.AddTrackerTooltip(tooltip)
assert(#lines > 3)
analysis.Toggle("cards")
analysis.Toggle("advisor")
for time = 30, 45, 5 do tick(time, 65, 25) end
AZS_CARDS = { kind = "jewel", cards = { { mode = "grow", detail = "Damage reduction=4%=7%=+" } } }
assert(analysis.CardText(1) == "Low health · mitigation option", "advisor has independent access to card model")
analysis.Toggle("advisor")
assert(not analysis.CardText(1))
analysis.Toggle("cards")
AZS_UNITS = { { kind = "boss", id = 15, hp = 2500 } }
AZS_CARDS = { kind = "spell", cards = { card } }
assert(not string.find(analysis.CardText(1), "DPS", 1, true), "boss boundary invalidates damage window")
AZS_CARDS = { kind = "jewel", cards = { { mode = "grow", detail = "Damage reduction=4%=7%=+" } } }
assert(string.find(analysis.CardText(1), "3.0 pp to cap", 1, true))
AZS_STATS, AZS_STATS_UPDATED = { arm = 0.59 }, 3
assert(string.find(analysis.CardText(1), "1.0 pp to cap", 1, true), "late sheet refreshes the same hand")
AZS_CAPS, AZS_CAPS_UPDATED = { red = 62 }, 3
assert(string.find(analysis.CardText(1), "3.0 pp to cap", 1, true), "late caps refresh the same hand")
AZS_ZONE = { run = "azs:r00000002", zone = "naxx", dt = 0 }
AZS_ZONE_UPDATED = 3
handlers.AZSZONE()
assert(not analysis.CardText(1))
AZS_ZONE_UPDATED = 4
tick(0, 0)
assert(not string.find(analysis.CardText(1), "cap", 1, true), "old stats not used across runs")
AZS_CARDS = { kind = "spell", cards = { card } }
assert(not analysis.CardText(1), "old spells are blocked until a fresh stamp")
analysis.Toggle("enabled")
analysis.Toggle("diagnostics")
recording = true
AZS_UNITS = {}
tick(1, 0)
AZS_SPELLS = { spell }
AZS_SPELLS_UPDATED = 5
handlers.AZSCARDS()
assert(emitted[#emitted].kind == "analysis_offer")
analysis.RecordPick(AZS_CARDS, 1)
assert(emitted[#emitted].kind == "analysis_pick_before")
local count = #emitted
analysis.RecordPick(AZS_CARDS, 1)
assert(#emitted == count)
AZS_SPELLS = { { key = "shadow_bolt", spell = 686, rank = 2, cdmax = 1.4 } }
AZS_SPELLS_UPDATED = 6
tick(3, 1)
assert(emitted[#emitted].kind == "analysis_pick_result" and emitted[#emitted].data.status == "observed_change")
for time = 8, 23, 5 do tick(time, 4) end
assert(emitted[#emitted - 1].kind == "analysis_pick_window")
assert(emitted[#emitted - 1].data.status == "window_unavailable", "missing earlier window is explicit")
AZS_CARDS = { kind = "jewel", cards = { { mode = "amulet", name = "New amulet", slot = "amulet" } } }
AZS_GEAR = { { slot = "amulet", name = "Previous amulet", amount = 2 } }
handlers.AZSCARDS()
analysis.RecordPick(AZS_CARDS, 1)
assert(emitted[#emitted].data.data.gearSlot[1].name == "Previous amulet")
AZS_GEAR = { { slot = "amulet", name = "New amulet", amount = 1 } }
tick(24, 4)
assert(emitted[#emitted].kind == "analysis_pick_result" and emitted[#emitted].data.status == "observed_change")
assert(emitted[#emitted].data.data.gearSlot[1].name == "New amulet")
AZS_UNITS = { { kind = "boss", id = 20, hp = 250 } }
tick(26, 4)
assert(emitted[#emitted - 1].kind == "analysis_pick_result"
	and emitted[#emitted - 1].data.status == "segment_changed", "boss entry invalidates the diagnostic comparison")
analysis.Toggle("diagnostics")
count = #emitted
tick(28, 4)
handlers.AZSCARDS()
assert(#emitted == count and not analysis.CardText(1))
print("PASS: Reborn analysis math, data boundaries, toggles, hand caching and diagnostics")
