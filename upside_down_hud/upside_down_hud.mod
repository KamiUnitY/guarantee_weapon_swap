return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`upside_down_hud` encountered an error loading the Darktide Mod Framework.")

		new_mod("upside_down_hud", {
			mod_script = "upside_down_hud/scripts/mods/upside_down_hud/upside_down_hud",
			mod_data = "upside_down_hud/scripts/mods/upside_down_hud/upside_down_hud_data",
			mod_localization = "upside_down_hud/scripts/mods/upside_down_hud/upside_down_hud_localization",
		})
	end,
	packages = {},
}
