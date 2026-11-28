-- Sanitized Session 033 projection. Only the selected card fields and
-- numerical parts of the learned tooltip are retained. Timing is supplied
-- by the host harness, and early tooltip / closed hand / learned order is preserved.
return {
	bond = {
		{ "d34:0:34", 2, 34, 0, 0 },
		{ "t1:0:1", 0, 34, 0, 1 },
		{ "d34:34:80", 2, 80, 0, 1 },
		{ "t2:1:3", 3, 80, 0, 3 },
		{ "d34:80:141", 2, 141, 0, 3 },
		{ "t1:3:4", 0, 141, 0, 4 },
		{ "c13:0:13", 2, 141, 13, 4 },
		{ "d18:141:184", 0, 184, 13, 4 },
		{ "d25:184:255", 1, 255, 13, 4 },
		{ "c17:13:28", 3, 255, 20, 4 },
	},
	ring = { name = "埃库利亚指环", slot = "ring", icon = "INV_Jewelry_Ring_15", bonus = "accuria" },
	ringFirst = { 36, "伤害+35.7%", 1 },
	ringLater = { 296, "伤害+296.2%", 4 },
	amulet = { name = "原始的附魔南海海藻", slot = "amulet", icon = "INV_Jewelry_Necklace_26", bonus = "south_seas_kelp" },
	amuletFirst = { 1, "幸运+30% · 金币+25%", 0 },
	amuletEmpower = { 2, "幸运+48% · 金币+40%", 0 },
}
