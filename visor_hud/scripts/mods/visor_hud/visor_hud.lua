local mod = get_mod("visor_hud")

local Managers = Managers
local Quaternion = Quaternion
local Vector3 = Vector3
local math = math
local Color = Color
local Gui = Gui

local UIHud = require("scripts/managers/ui/ui_hud")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local WorldManager = require("scripts/foundation/managers/world/world_manager")

---------------
-- CONSTANTS --
---------------

local UNCURVED_ELEMENT_NAMES = {
	ConstantElementWatermark = true,
	ConstantElementPopupHandler = true,
	ConstantElementSoftwareCursor = true,
	HudElementPrologueTutorialSequenceTransitionEnd = true,
	HudElementPrologueTutorialInfoBox = true,
	HudElementCrosshair = true,
	HudElementInteraction = true,
	HudElementWorldMarkers = true,
	HudElementEmoteWheel = true,
	HudElementSmartTagging = true,
	HudElementDamageIndicator = true,
}

local SCREEN_ELEMENT_NAMES = {
	HudElementCustomizer = true,
	HudElementTacticalOverlay = true,
	HudElementCutsceneOverlay = true,
	HudElementCutsceneFading = true,
}

local HUD_DRAW_TARGET = {
	UNCURVED = "uncurved",
	CURVED = "curved",
	SCREEN = "screen",
}

local CAMERA_FOLLOW_DELAY_SECONDS = 0.01
local WORLD_PIXELS_PER_SCREEN_HEIGHT = 0.16
local HUD_RENDER_TARGET_MATERIAL = "content/ui/meshes/hud_plane/hud_material_effect_no_curve"

local SCREEN_RENDERER_NAME = "visor_hud_screen_renderer"
local CURVED_RENDERER_NAME = "visor_hud_curved_renderer"
local UNCURVED_RENDER_PASS = "visor_hud_screen_uncurved"
local CURVED_RENDER_PASS   = "visor_hud_screen_curved"

local CURVE_GRID_MAX_HEIGHT_STEP = 2
local CURVE_GRID_MIN_WIDTH = 1

local BITMAP_CURVED_LAYER = 0
local UNCURVED_SCREEN_PASS_LAYER = 1
local CURVED_SCREEN_PASS_LAYER = 2
local SCREEN_PASS_LAYER = 3

local FULLSCREEN_UVS = { { 0, 0 }, { 1, 1 } }

---------------
-- VARIABLES --
---------------

local known_huds = setmetatable({}, { __mode = "k" })
local hud_compositors = setmetatable({}, { __mode = "k" })
local hud_element_draw_targets = setmetatable({}, { __mode = "k" })
local world_enabled_by_name = {}
local gameplay_hooks_enabled = true


---@type string?
local previous_viewport_name

---@type number?
local smoothed_camera_yaw
---@type number?
local smoothed_camera_pitch
---@type number?
local smoothed_camera_x
---@type number?
local smoothed_camera_y
---@type number?
local smoothed_camera_z

local camera_lag_x = 0.0
local camera_lag_y = 0.0

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
	curve_strength     = mod:get("curve_strength"),
	camera_sway        = mod:get("camera_sway"),
	opacity_multiplier = mod:get("opacity_multiplier"),
	horizontal_margin  = mod:get("horizontal_margin"),
	vertical_margin    = mod:get("vertical_margin"),
}

mod.on_setting_changed = function(setting_id)
	mod.settings[setting_id] = mod:get(setting_id)
end

-----------------
-- CAMERA SWAY --
-----------------

local function shortest_angle_delta(target, current)
	return (target - current + math.pi) % (math.pi * 2) - math.pi
end

local function reset_camera_lag()
	smoothed_camera_yaw = nil
	smoothed_camera_pitch = nil
	smoothed_camera_x = nil
	smoothed_camera_y = nil
	smoothed_camera_z = nil
	previous_viewport_name = nil
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z, viewport_name)
	smoothed_camera_yaw = yaw
	smoothed_camera_pitch = pitch
	smoothed_camera_x = position_x
	smoothed_camera_y = position_y
	smoothed_camera_z = position_z
	previous_viewport_name = viewport_name
	camera_lag_x = 0.0
	camera_lag_y = 0.0
end

local function current_camera_pose()
	local player_manager = Managers.player
	local camera_manager = Managers.state and Managers.state.camera

	if not player_manager or not camera_manager then
		return nil, nil
	end

	local player = player_manager:local_player_safe(1)
	local viewport_name = player and player.viewport_name

	if not viewport_name or not camera_manager:has_camera(viewport_name) then
		return nil, nil
	end

	local rotation = camera_manager:camera_rotation(viewport_name)
	local position = camera_manager:camera_position(viewport_name)

	if not rotation or not Quaternion.is_valid(rotation) or not position or not Vector3.is_valid(position) then
		return nil, nil
	end

	return rotation, position, viewport_name
end

local function clamp_screen_offset(offset_x, offset_y, limit)
	local distance = math.sqrt(offset_x * offset_x + offset_y * offset_y)

	if distance <= limit then
		return offset_x, offset_y
	end

	local scale = limit / distance

	return offset_x * scale, offset_y * scale
end

local function movement_limit_pixels(width, height)
	local movement_limit_percent = 2.0

	return math.min(width, height) * movement_limit_percent * 0.01
end

local function update_camera_lag(dt)
	if not dt or dt <= 0 then
		reset_camera_lag()
		return
	end

	local rotation, position, viewport_name = current_camera_pose()

	if not rotation then
		reset_camera_lag()
		return
	end

	local yaw, pitch = Quaternion.to_yaw_pitch_roll(rotation)
	local position_x = position[1]
	local position_y = position[2]
	local position_z = position[3]

	if viewport_name ~= previous_viewport_name or smoothed_camera_yaw == nil then
		set_camera_lag_origin(yaw, pitch, position_x, position_y, position_z, viewport_name)
		return
	end

	local follow_fraction = 1 - math.exp(-dt / CAMERA_FOLLOW_DELAY_SECONDS)

	smoothed_camera_yaw = smoothed_camera_yaw + shortest_angle_delta(yaw, smoothed_camera_yaw) * follow_fraction
	smoothed_camera_pitch = smoothed_camera_pitch + shortest_angle_delta(pitch, smoothed_camera_pitch) * follow_fraction
	smoothed_camera_x = smoothed_camera_x + (position_x - smoothed_camera_x) * follow_fraction
	smoothed_camera_y = smoothed_camera_y + (position_y - smoothed_camera_y) * follow_fraction
	smoothed_camera_z = smoothed_camera_z + (position_z - smoothed_camera_z) * follow_fraction

	local lag_yaw = shortest_angle_delta(smoothed_camera_yaw, yaw)
	local lag_pitch = shortest_angle_delta(smoothed_camera_pitch, pitch)
	local world_lag_x = smoothed_camera_x - position_x
	local world_lag_y = smoothed_camera_y - position_y
	local world_lag_z = smoothed_camera_z - position_z
	local camera_right = Quaternion.right(rotation)
	local camera_up = Quaternion.up(rotation)
	local lag_right = world_lag_x * camera_right[1] + world_lag_y * camera_right[2] + world_lag_z * camera_right[3]
	local lag_up = world_lag_x * camera_up[1] + world_lag_y * camera_up[2] + world_lag_z * camera_up[3]
	local width = RESOLUTION_LOOKUP.width
	local height = RESOLUTION_LOOKUP.height
	local movement_limit = movement_limit_pixels(width, height)
	local world_pixels_per_meter = height * WORLD_PIXELS_PER_SCREEN_HEIGHT
	local camera_sway_scale = tonumber(mod.settings.camera_sway) or 0.0
	local world_sway_scale = camera_sway_scale * 5
	local target_lag_x = -lag_yaw * width * 0.5 * camera_sway_scale + lag_right * world_pixels_per_meter * world_sway_scale
	local target_lag_y = -lag_pitch * height * camera_sway_scale - lag_up * world_pixels_per_meter * world_sway_scale

	local limited_lag_x, limited_lag_y = clamp_screen_offset(target_lag_x, target_lag_y, movement_limit)

	local movement_smoothing_time = math.max(CAMERA_FOLLOW_DELAY_SECONDS * 0.5, 0.05)
	local movement_fraction = 1 - math.exp(-dt / movement_smoothing_time)

	camera_lag_x = camera_lag_x + (limited_lag_x - camera_lag_x) * movement_fraction
	camera_lag_y = camera_lag_y + (limited_lag_y - camera_lag_y) * movement_fraction

	camera_lag_x, camera_lag_y = clamp_screen_offset(camera_lag_x, camera_lag_y, movement_limit)
end

-------------------------
-- HUD ELEMENT ROUTING --
-------------------------


local function is_gameplay_hud_element(element)
	local hud = element._parent
	local visibility_groups = hud and hud._visibility_groups

	if not visibility_groups then
		return false
	end

	for i = 1, #visibility_groups do
		local visibility_group = visibility_groups[i]

		if visibility_group.name == "alive" then
			local visible_elements = visibility_group.visible_elements

			return visible_elements and visible_elements[element.__class_name] == true or false
		end
	end

	return false
end

local function calculate_hud_element_draw_target(element)
	local element_name = element.__class_name

	if SCREEN_ELEMENT_NAMES[element_name] then
		return HUD_DRAW_TARGET.SCREEN
	end

	local scenegraph = element._ui_scenegraph

	if scenegraph
		and is_gameplay_hud_element(element)
		and not UNCURVED_ELEMENT_NAMES[element_name]
	then
		return HUD_DRAW_TARGET.CURVED
	end

	return HUD_DRAW_TARGET.UNCURVED
end

local function hud_element_draw_target(element)
	local draw_target = hud_element_draw_targets[element]

	if not draw_target then
		draw_target = calculate_hud_element_draw_target(element)
		hud_element_draw_targets[element] = draw_target
	end

	return draw_target
end

----------------------------
-- HUD RENDERER MIGRATION --
----------------------------

local function is_live_widget(value)
	local passes = type(value) == "table" and rawget(value, "passes")
	local pass = type(passes) == "table" and passes[1]
	local data = type(pass) == "table" and rawget(pass, "data")
	local parent_name = type(data) == "table" and rawget(data, "_parent_name")

	return parent_name ~= nil and parent_name == rawget(value, "name")
end

local function release_owned_widgets(value, ui_renderer, visited)
	if type(value) ~= "table" or visited[value] then
		return
	end

	visited[value] = true

	if is_live_widget(value) then
		UIWidget.destroy(ui_renderer, value)
		value.dirty = true
		return
	end

	for key, child in pairs(value) do
		if key ~= "_parent" and type(child) == "table" then
			release_owned_widgets(child, ui_renderer, visited)
		end
	end
end

local function migrate_hud_renderer(hud, source_renderer, destination_renderer)
	local elements = hud._elements_array

	if source_renderer and elements then
		local visited = {}

		for i = 1, #elements do
			release_owned_widgets(elements[i], source_renderer, visited)
		end
	end

	hud._ui_renderer = destination_renderer
	hud._refresh_retained = true
end

----------------------
-- CURVE GENERATION --
----------------------

local function curve_projection(width, height, strength)
	local half_width = width * 0.5
	local vertical_curve = math.tan(math.degrees_to_radians(strength)) * half_width / height

	return {
		width = width,
		height = height,
		half_width = half_width,
		vertical_curve = vertical_curve,
		vertical_fit = 1 / math.max(1, 1 - vertical_curve),
	}
end

local function curve_grid_cell_height(projection, source_x)
	local normalized_x = source_x / projection.width * 2 - 1

	return math.abs(projection.height * (1 - projection.vertical_curve * normalized_x * normalized_x) * projection.vertical_fit)
end

local function calculate_curve_grid_boundaries(projection)
	local column_count = math.ceil(
		math.abs(curve_grid_cell_height(projection, 0) - curve_grid_cell_height(projection, projection.half_width))
		* (1 + math.sqrt(2)) / CURVE_GRID_MAX_HEIGHT_STEP
	)
	column_count = math.max(4, column_count)
	column_count = column_count + column_count % 2

	local columns_per_side = column_count * 0.5
	local boundaries = { 0 }

	for i = 1, columns_per_side do
		local boundary_x = projection.half_width * (1 - math.sqrt(1 - i / columns_per_side))

		if boundary_x - boundaries[#boundaries] >= CURVE_GRID_MIN_WIDTH then
			boundaries[#boundaries + 1] = boundary_x
		elseif i == columns_per_side then
			boundaries[math.max(2, #boundaries)] = boundary_x
		end
	end

	for i = #boundaries - 1, 1, -1 do
		boundaries[#boundaries + 1] = projection.width - boundaries[i]
	end

	return boundaries
end

local function rebuild_curve_cells(compositor, width, height, strength, horizontal_margin, vertical_margin)
	local content_width = math.max(width - horizontal_margin * 2, 1)
	local content_height = math.max(height - vertical_margin * 2, 1)
	local projection = curve_projection(content_width, content_height, strength)
	local cells = {}
	local source_boundaries = calculate_curve_grid_boundaries(projection)

	for column = 1, #source_boundaries - 1 do
		local source_left = source_boundaries[column]
		local source_right = source_boundaries[column + 1]
		local source_center_x = (source_left + source_right) * 0.5
		local curved_height = curve_grid_cell_height(projection, source_center_x)
		local source_uv_half_height = content_height / curved_height * 0.5

		cells[#cells + 1] = {
			position_x = horizontal_margin + source_left,
			right_x = horizontal_margin + source_right,
			position_y = vertical_margin,
			height = content_height,
			uvs = {
				{ source_left / content_width, 0.5 - source_uv_half_height },
				{ source_right / content_width, 0.5 + source_uv_half_height },
			},
		}
	end

	compositor.curve_cells = cells
	compositor.curve_width = width
	compositor.curve_height = height
	compositor.curve_strength = strength
	compositor.curve_horizontal_margin = horizontal_margin
	compositor.curve_vertical_margin = vertical_margin

	return cells
end

local function ensure_curve_cells(compositor, width, height, strength, horizontal_margin, vertical_margin)
	if compositor.curve_cells
		and compositor.curve_width == width
		and compositor.curve_height == height
		and compositor.curve_strength == strength
		and compositor.curve_horizontal_margin == horizontal_margin
		and compositor.curve_vertical_margin == vertical_margin
	then
		return compositor.curve_cells
	end

	return rebuild_curve_cells(compositor, width, height, strength, horizontal_margin, vertical_margin)
end

--------------------
-- HUD COMPOSITOR --
--------------------

local function get_or_create_hud_compositor(hud)
	if hud_compositors[hud] then
		return hud_compositors[hud]
	end

	local original_renderer = hud._ui_renderer

	if not original_renderer or original_renderer.render_target then
		return nil
	end

	local world = Managers.world:world(hud._world_name)
	local screen_renderer = Managers.ui:create_renderer(SCREEN_RENDERER_NAME, world)

	screen_renderer.render_pass_flag = "render_pass"
	screen_renderer.base_render_pass = "to_screen"

	local curved_renderer = Managers.ui:create_renderer(
		CURVED_RENDERER_NAME,
		world,
		true,
		screen_renderer.gui,
		screen_renderer.gui_retained,
		HUD_RENDER_TARGET_MATERIAL
	)

	Gui.render_pass(
		screen_renderer.gui_retained,
		BITMAP_CURVED_LAYER,
		curved_renderer.base_render_pass,
		true,
		curved_renderer.render_target
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		UNCURVED_SCREEN_PASS_LAYER,
		UNCURVED_RENDER_PASS,
		false
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		CURVED_SCREEN_PASS_LAYER,
		CURVED_RENDER_PASS,
		false
	)
	Gui.render_pass(
		screen_renderer.gui_retained,
		SCREEN_PASS_LAYER,
		screen_renderer.base_render_pass,
		false
	)

	local compositor = {
		original_renderer = original_renderer,
		screen_renderer = screen_renderer,
		curved_renderer = curved_renderer,
	}

	hud_compositors[hud] = compositor
	migrate_hud_renderer(hud, original_renderer, curved_renderer)

	return compositor
end

local function destroy_hud_compositor(hud, restore_original_renderer)
	local compositor = hud_compositors[hud]

	if not compositor then
		return
	end

	hud_compositors[hud] = nil

	if restore_original_renderer and hud._ui_renderer == compositor.curved_renderer then
		migrate_hud_renderer(hud, compositor.curved_renderer, compositor.original_renderer)
	end

	Managers.ui:destroy_renderer(CURVED_RENDERER_NAME)
	Managers.ui:destroy_renderer(SCREEN_RENDERER_NAME)
end

local function ensure_known_hud_compositors()
	for hud in pairs(known_huds) do
		get_or_create_hud_compositor(hud)
	end
end

local function destroy_all_hud_compositors()
	for hud in pairs(hud_compositors) do
		destroy_hud_compositor(hud, true)
	end
end

-----------------
-- HUD DRAWING --
-----------------

local function composite_hud(compositor)
	local screen_renderer = compositor.screen_renderer
	local curved_renderer = compositor.curved_renderer

	UIRenderer.clear_render_pass_queue(screen_renderer)
	UIRenderer.add_render_pass(
		screen_renderer,
		BITMAP_CURVED_LAYER,
		curved_renderer.base_render_pass,
		false,
		curved_renderer.render_target
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		UNCURVED_SCREEN_PASS_LAYER,
		UNCURVED_RENDER_PASS,
		false
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		CURVED_SCREEN_PASS_LAYER,
		CURVED_RENDER_PASS,
		false
	)
	UIRenderer.add_render_pass(
		screen_renderer,
		SCREEN_PASS_LAYER,
		"to_screen",
		false
	)

	local width = RESOLUTION_LOOKUP.width
	local height = RESOLUTION_LOOKUP.height
	local strength = tonumber(mod.settings.curve_strength) or 0
	local horizontal_margin = tonumber(mod.settings.horizontal_margin) or 0
	local vertical_margin = tonumber(mod.settings.vertical_margin) or 0
	local content_width = width - horizontal_margin * 2
	local content_height = height - vertical_margin * 2
	local previous_base_render_pass = screen_renderer.base_render_pass
	local color = Color(255, 255, 255, 255)
	local scenegraph = {}
	local render_settings = {
		scale = 1,
	}

	UIRenderer.begin_pass(screen_renderer, scenegraph, nil, 0, render_settings)
	screen_renderer.base_render_pass = CURVED_RENDER_PASS

	local cells = math.abs(strength) > 0
		and ensure_curve_cells(compositor, width, height, strength, horizontal_margin, vertical_margin)
	local draw_count = cells and #cells or 1
	local scale = screen_renderer.scale or 1
	local snapped_lag_x = math.floor(camera_lag_x + 0.5)
	local snapped_lag_y = math.floor(camera_lag_y + 0.5)

	for i = 1, draw_count do
		local cell = cells and cells[i]
		local left = math.floor((cell and cell.position_x or horizontal_margin) + 0.5) + snapped_lag_x
		local right = math.floor((cell and cell.right_x or horizontal_margin + content_width) + 0.5) + snapped_lag_x
		local top = math.floor((cell and cell.position_y or vertical_margin) + 0.5) + snapped_lag_y
		local bottom = math.floor((cell and cell.position_y + cell.height or vertical_margin + content_height) + 0.5) + snapped_lag_y
		local position = Vector3(left / scale, top / scale, BITMAP_CURVED_LAYER)
		local size = Vector3((right - left) / scale, (bottom - top) / scale, 0)

		UIRenderer.script_draw_bitmap_uv(
			screen_renderer,
			curved_renderer.render_target_material,
			position,
			size,
			cell and cell.uvs or FULLSCREEN_UVS,
			color,
			nil
		)
	end

	screen_renderer.base_render_pass = previous_base_render_pass
	UIRenderer.end_pass(screen_renderer)
end

local function draw_hud_elements(hud, dt, t, input_service, ui_renderer, draw_target, base_render_pass)
	local render_settings = hud._render_settings
	local saved_start_layer = render_settings.start_layer
	local saved_base_render_pass = ui_renderer.base_render_pass
	local alpha_multiplier = render_settings.alpha_multiplier or 1
	local opacity_multiplier = tonumber(mod.settings.opacity_multiplier)
	local currently_visible_elements = hud._currently_visible_elements
	local elements_hud_scale_lookup = hud._elements_hud_scale_lookup
	local elements_array = hud._elements_array
	local elements_hud_retained_mode_lookup = hud._elements_hud_retained_mode_lookup

	for i = 1, #elements_array do
		local element = elements_array[i]
		local element_name = element.__class_name

		if hud_element_draw_target(element) == draw_target
			and currently_visible_elements[element_name]
			and element.draw
		then
			local hud_scale_applied = false
			local opacity = not SCREEN_ELEMENT_NAMES[element_name]
				and opacity_multiplier or 1

			if elements_hud_scale_lookup[element_name] then
				hud_scale_applied = true
				hud:_apply_hud_scale()
			end

			render_settings.force_retained_mode = elements_hud_retained_mode_lookup[element_name]
			render_settings.alpha_multiplier = alpha_multiplier * opacity
			ui_renderer.base_render_pass = base_render_pass or saved_base_render_pass

			element:draw(dt, t, ui_renderer, render_settings, input_service)
			render_settings.alpha_multiplier = alpha_multiplier

			if hud_scale_applied then
				hud:_abort_hud_scale()
			end
		end
	end

	ui_renderer.base_render_pass = saved_base_render_pass
	render_settings.start_layer = saved_start_layer
end

local function is_world_enabled(world_name)
	if world_enabled_by_name[world_name] == nil then
		world_enabled_by_name[world_name] = Managers.world:is_world_enabled(world_name) == true
	end

	return world_enabled_by_name[world_name]
end

------------------
-- UI HUD HOOKS --
------------------

mod:hook(UIHud, "init", function(func, self, ...)
	local result = func(self, ...)

	known_huds[self] = true
	world_enabled_by_name[self._world_name] = Managers.world:is_world_enabled(self._world_name) == true
	get_or_create_hud_compositor(self)

	return result
end)

mod:hook(UIHud, "draw", function(func, self, dt, t, input_service)
	local compositor = is_world_enabled(self._world_name) and get_or_create_hud_compositor(self)

	if not compositor then
		return func(self, dt, t, input_service)
	end

	composite_hud(compositor)
	draw_hud_elements(self, dt, t, input_service, compositor.screen_renderer, HUD_DRAW_TARGET.UNCURVED, UNCURVED_RENDER_PASS)
	draw_hud_elements(self, dt, t, input_service, compositor.curved_renderer, HUD_DRAW_TARGET.CURVED)
	draw_hud_elements(self, dt, t, input_service, compositor.screen_renderer, HUD_DRAW_TARGET.SCREEN)
end)

mod:hook(UIHud, "destroy", function(func, self, ...)
	local result = func(self, ...)

	destroy_hud_compositor(self, false)
	known_huds[self] = nil

	return result
end)

----------------
-- WORLD HOOK --
----------------

mod:hook(WorldManager, "enable_world", function(func, self, world_name, enabled, ...)
	local result = func(self, world_name, enabled, ...)

	world_enabled_by_name[world_name] = enabled == true

	return result
end)

--------------------
-- ON EVERY FRAME --
--------------------

mod.update = function(dt)
	if not mod:is_enabled() or not gameplay_hooks_enabled then
		return
	end

	update_camera_lag(dt)
end

------------------------
-- GAMEPLAY LIFECYCLE --
------------------------

local function gameplay_scene_is_active()
	return not not (Managers.state and Managers.state.game_mode)
end

local function set_gameplay_hooks_enabled(enabled)
	enabled = not not enabled

	gameplay_hooks_enabled = enabled

	if not enabled then
		reset_camera_lag()
		destroy_all_hud_compositors()
	end

	if enabled then
		world_enabled_by_name = {}
		mod:enable_all_hooks()
		ensure_known_hud_compositors()
	else
		mod:disable_all_hooks()
	end
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
	if state_name == "StateGameplay" then
		set_gameplay_hooks_enabled(mod:is_enabled() and status == "enter")
	end
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
	set_gameplay_hooks_enabled(mod:is_enabled() and gameplay_scene_is_active())
end

---------------------------
-- ON ENABLED / DISABLED --
---------------------------

mod.on_enabled = function()
	set_gameplay_hooks_enabled(gameplay_scene_is_active())
end

mod.on_disabled = function()
	set_gameplay_hooks_enabled(false)
end

--------------------
-- INITIALIZATION --
--------------------

set_gameplay_hooks_enabled(mod:is_enabled() and gameplay_scene_is_active())
