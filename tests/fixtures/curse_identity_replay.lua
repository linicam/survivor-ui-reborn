-- The capture's display language can differ from the replay runner's.
return {
	{ seq = 1, t = 0, type = "run_transition", data = { to = "azs:rfixture" } },
	{ seq = 2, t = 10, type = "curse_banner", data = {
		raw = { id = 1, kind = "curse", text = "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!", time = 10 },
		effect = "敌潮涌动", effectId = "horde_surge", runTime = 10,
	} },
	{ seq = 3, t = 12, type = "curse_banner", data = {
		raw = { id = 2, kind = "curse", text = "涌动平息了。", time = 12 },
		decision = "ending", effect = "敌潮涌动", effectId = "horde_surge", runTime = 12,
	} },
}
