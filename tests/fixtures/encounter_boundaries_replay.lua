-- Synthetic API snapshots with independent encounter expectations.
local rift1 = { kind = "rift", id = 11, hp = 40, hpm = 100 }
local rift2 = { kind = "rift", id = 22, hp = 80, hpm = 100 }
local empty = { index = 1, state = "empty", left = 12 }
return {
	{ seq = 1, type = "run_transition", data = { to = "azs:r11111111" } },
	{ seq = 2, type = "rift_snapshot", data = { units = { rift1 }, rift = { st = "boss" }, id = 11, state = "up" } },
	{ seq = 3, type = "rift_snapshot", data = { units = {}, rift = { st = "boss" }, id = 11, state = "up", missing = true } },
	{ seq = 4, type = "rift_snapshot", data = { units = { rift1 }, rift = { st = "done" }, id = 11, state = "up" } },
	{ seq = 5, type = "rift_snapshot", data = { units = {}, rift = { st = "done" }, id = 11, state = "dead" } },
	{ seq = 6, type = "rift_snapshot", data = { units = { rift2 }, rift = { st = "boss" }, id = 22, state = "up" } },
	{ seq = 7, type = "rift_snapshot", data = { units = {}, rift = { st = "done" }, id = 22, state = "dead" } },
	{ seq = 8, type = "guardian_snapshot", data = { lair = empty, stamp = 1, runTime = 30, left = 12 } },
	{ seq = 9, type = "guardian_snapshot", data = { lair = empty, stamp = 1, runTime = 35, left = 7 } },
	{ seq = 10, type = "guardian_snapshot", data = { lair = { index = 1, left = -1 }, stamp = 2, runTime = 36 } },
}
