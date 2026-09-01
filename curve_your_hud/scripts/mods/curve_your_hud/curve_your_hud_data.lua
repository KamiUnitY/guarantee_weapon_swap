local mod = get_mod("curve_your_hud")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "curve_strength",
				type = "numeric",
				default_value = -7.5,
				range = { -20, 20 },
				decimals_number = 1,
  				step_size_value = 0.5,
			},
			{
				setting_id = "camera_sway",
				type = "numeric",
				default_value = -0.25,
				range = { -1.0, 1.0 },
				decimals_number = 2,
  				step_size_value = 0.05,
			},
			{
				setting_id = "opacity_multiplier",
				type = "numeric",
				default_value = 0.85,
				range = { 0, 1 },
				decimals_number = 2,
				step_size_value = 0.05,
			},
			{
				setting_id = "horizontal_margin",
				type = "numeric",
				default_value = 0,
				range = { -100, 200 },
				decimals_number = 0,
				step_size_value = 5,
			},
			{
				setting_id = "vertical_margin",
				type = "numeric",
				default_value = -15,
				range = { -100, 200 },
				decimals_number = 0,
				step_size_value = 5,
			},
		},
	},
}
