return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`curve_your_hud` encountered an error loading the Darktide Mod Framework.")

		new_mod("curve_your_hud", {
			mod_script = "curve_your_hud/scripts/mods/curve_your_hud/curve_your_hud",
			mod_data = "curve_your_hud/scripts/mods/curve_your_hud/curve_your_hud_data",
			mod_localization = "curve_your_hud/scripts/mods/curve_your_hud/curve_your_hud_localization",
		})
	end,
	packages = {},
}
