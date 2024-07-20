return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_better_sprint` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_better_sprint", {
			mod_script       = "guarantee_better_sprint/scripts/mods/guarantee_better_sprint/guarantee_better_sprint",
			mod_data         = "guarantee_better_sprint/scripts/mods/guarantee_better_sprint/guarantee_better_sprint_data",
			mod_localization = "guarantee_better_sprint/scripts/mods/guarantee_better_sprint/guarantee_better_sprint_localization",
		})
	end,
	load_before = {
		"guarantee_weapon_swap",
		"guarantee_ability_activation",
	},
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
	},
	packages = {},
}