return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`visor_hud` encountered an error loading the Darktide Mod Framework.")

		new_mod("visor_hud", {
			mod_script = "visor_hud/scripts/mods/visor_hud/visor_hud",
			mod_data = "visor_hud/scripts/mods/visor_hud/visor_hud_data",
			mod_localization = "visor_hud/scripts/mods/visor_hud/visor_hud_localization",
		})
	end,
	packages = {},
}
