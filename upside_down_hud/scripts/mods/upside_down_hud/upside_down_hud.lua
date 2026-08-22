local mod = get_mod("upside_down_hud")

local UIHud = require("scripts/managers/ui/ui_hud")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

local HUD_PANE_MATERIAL = "content/ui/meshes/hud_plane/hud_material_effect_no_curve"
local UPSIDE_DOWN_UVS = {
	{ 1, 1 },
	{ 0, 0 },
}
local COMPOSITE_RENDER_SETTINGS = {
	scale = 1,
	inverse_scale = 1,
	snap_pixel_positions = false,
	hdr = false,
}
local COMPOSITE_SCENEGRAPH = {}

local function create_hud_pane(hud)
	local world = Managers.world:world(hud._world_name)
	local compositor_name = hud._unique_id .. "upside_down_hud_compositor"
	local pane_name = hud._unique_id .. "upside_down_hud_pane"
	local compositor = Managers.ui:create_renderer(compositor_name, world)
	local pane = Managers.ui:create_renderer(
		pane_name,
		world,
		true,
		compositor.gui,
		compositor.gui_retained,
		HUD_PANE_MATERIAL
	)

	-- A retained Gui keeps its render-pass registration for its lifetime. Add
	-- this once with the pane, not once per frame.
	Gui.render_pass(compositor.gui_retained, 0, pane.base_render_pass, true, pane.render_target)

	hud._upside_down_hud_compositor_name = compositor_name
	hud._upside_down_hud_pane_name = pane_name
	hud._upside_down_hud_compositor = compositor
	hud._upside_down_hud_pane = pane

	-- UIHud continues to lay out, update, and draw every element normally. Its
	-- destination is now one full-screen pane instead of the back buffer.
	hud._ui_renderer = pane
end

local function prepare_hud_pane(hud)
	local compositor = hud._upside_down_hud_compositor
	local pane = hud._upside_down_hud_pane

	UIRenderer.clear_render_pass_queue(compositor)

	-- The retained GUI owns the persistent clearing pass. Register the immediate
	-- GUI with the same pane without erasing the retained panels.
	UIRenderer.add_render_pass(compositor, 0, pane.base_render_pass, false, pane.render_target)
	UIRenderer.add_render_pass(compositor, 1, "to_screen", false)
end

local function draw_hud_pane(hud)
	local compositor = hud._upside_down_hud_compositor
	local pane = hud._upside_down_hud_pane
	local position = Vector3(0, 0, 0)
	local size = Vector3(RESOLUTION_LOOKUP.width, RESOLUTION_LOOKUP.height, 0)
	local previous_base_render_pass = compositor.base_render_pass

	-- Reversing both texture axes is one 180-degree rotation of the completed
	-- pane. No HUD element, widget, scenegraph, or retained draw is modified.
	UIRenderer.begin_pass(compositor, COMPOSITE_SCENEGRAPH, nil, 0, COMPOSITE_RENDER_SETTINGS)
	compositor.base_render_pass = "to_screen"
	UIRenderer.script_draw_bitmap_uv(
		compositor,
		pane.render_target_material,
		position,
		size,
		UPSIDE_DOWN_UVS,
		Color(255, 255, 255, 255),
		nil
	)
	compositor.base_render_pass = previous_base_render_pass
	UIRenderer.end_pass(compositor)
end

local function destroy_hud_pane(hud)
	local pane_name = hud._upside_down_hud_pane_name
	local compositor_name = hud._upside_down_hud_compositor_name

	if pane_name then
		Managers.ui:destroy_renderer(pane_name)
	end

	if compositor_name then
		Managers.ui:destroy_renderer(compositor_name)
	end

	hud._upside_down_hud_compositor_name = nil
	hud._upside_down_hud_pane_name = nil
	hud._upside_down_hud_compositor = nil
	hud._upside_down_hud_pane = nil
end

mod:hook(UIHud, "init", function(func, self, ...)
	local result = func(self, ...)

	create_hud_pane(self)

	return result
end)

mod:hook(UIHud, "draw", function(func, self, ...)
	if not Managers.world:is_world_enabled(self._world_name) then
		return func(self, ...)
	end

	prepare_hud_pane(self)

	local result = func(self, ...)

	draw_hud_pane(self)

	return result
end)

mod:hook(UIHud, "destroy", function(func, self, ...)
	-- The native destroy path must first release every HUD widget from the pane
	-- renderer and destroy UIHud's original renderer by its original name.
	local result = func(self, ...)

	destroy_hud_pane(self)

	return result
end)
