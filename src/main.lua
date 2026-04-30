hg = require("harfang")
say = require("say")
require("config_gui")
local automaton_controller_lib = require("automaton_controller")

local robot_actions = require("robot_scenario")
local DEBUG_MOVE_START_NODE = "path_0"
local DEBUG_MOVE_TARGET_NODE = "path_1"
local DEBUG_ROTATE_TARGET_NODE_A = "path_0"
local DEBUG_ROTATE_TARGET_NODE_B = "path_1"
local BACKPACK_WEIGHT = 2.4

local MAIN_LIGHT_NAME = "MainLight"
local MAIN_LIGHT_SHADOW_NEAR = 25.0
local MAIN_LIGHT_SHADOW_FAR = 55.0
local COMPOSITING_SETTINGS_PATH = "compositing_tuning.lua"
local COMPOSITING_UI_VIEW_ID = 255
local AMBIANT_AUDIO_ASSET = "audio/ambiant.ogg"

local DEFAULT_COMPOSITING_SETTINGS = {
	COMPOSITING_VIGNETTE_START = 0.72,
	COMPOSITING_VIGNETTE_END = 1.28,
	COMPOSITING_VIGNETTE_STRENGTH = 0.5,
	COMPOSITING_CIRCULAR_BLUR_STRENGTH = 10.0,
	COMPOSITING_CRT_CURVATURE = 0.08,
	COMPOSITING_CRT_MASK_DENSITY = 0.45,
	COMPOSITING_CRT_MASK_INTENSITY = 0.22,
	COMPOSITING_LEFT_LIGHT_SHIFT = 0.0,
	COMPOSITING_STRENGTH_VARIATION_AMPLITUDE = 0.2,
	COMPOSITING_SMOOTH_WOBBLE_SPEED = 0.9,
	COMPOSITING_JITTER_RESPONSE = 6.0,
	COMPOSITING_JITTER_INTERVAL_MIN = 0.1,
	COMPOSITING_JITTER_INTERVAL_MAX = 0.5
}

local COMPOSITING_SETTINGS_ORDER = {
	"COMPOSITING_VIGNETTE_START",
	"COMPOSITING_VIGNETTE_END",
	"COMPOSITING_VIGNETTE_STRENGTH",
	"COMPOSITING_CIRCULAR_BLUR_STRENGTH",
	"COMPOSITING_CRT_CURVATURE",
	"COMPOSITING_CRT_MASK_DENSITY",
	"COMPOSITING_CRT_MASK_INTENSITY",
	"COMPOSITING_LEFT_LIGHT_SHIFT",
	"COMPOSITING_STRENGTH_VARIATION_AMPLITUDE",
	"COMPOSITING_SMOOTH_WOBBLE_SPEED",
	"COMPOSITING_JITTER_RESPONSE",
	"COMPOSITING_JITTER_INTERVAL_MIN",
	"COMPOSITING_JITTER_INTERVAL_MAX"
}

local COMPOSITING_UI_FIELDS = {
	{section = "Lens", key = "COMPOSITING_VIGNETTE_START", label = "Vignette start", min = 0.0, max = 2.0, format = "%.3f"},
	{section = "Lens", key = "COMPOSITING_VIGNETTE_END", label = "Vignette end", min = 0.0, max = 2.0, format = "%.3f"},
	{section = "Lens", key = "COMPOSITING_VIGNETTE_STRENGTH", label = "Vignette strength", min = 0.0, max = 2.0, format = "%.3f"},
	{section = "Lens", key = "COMPOSITING_CIRCULAR_BLUR_STRENGTH", label = "Circular blur strength", min = 0.0, max = 40.0, format = "%.2f"},
	{section = "CRT", key = "COMPOSITING_CRT_CURVATURE", label = "CRT curvature", min = 0.0, max = 0.3, format = "%.3f"},
	{section = "CRT", key = "COMPOSITING_CRT_MASK_DENSITY", label = "CRT mask density", min = 0.0, max = 2.0, format = "%.3f"},
	{section = "CRT", key = "COMPOSITING_CRT_MASK_INTENSITY", label = "CRT mask intensity", min = 0.0, max = 1.0, format = "%.3f"},
	{section = "CRT", key = "COMPOSITING_LEFT_LIGHT_SHIFT", label = "Left light shift", min = 0.0, max = 24.0, format = "%.3f"},
	{section = "Variation", key = "COMPOSITING_STRENGTH_VARIATION_AMPLITUDE", label = "Variation amplitude", min = 0.0, max = 1.0, format = "%.3f"},
	{section = "Variation", key = "COMPOSITING_SMOOTH_WOBBLE_SPEED", label = "Smooth wobble speed", min = 0.0, max = 5.0, format = "%.3f"},
	{section = "Variation", key = "COMPOSITING_JITTER_RESPONSE", label = "Jitter response", min = 0.0, max = 20.0, format = "%.3f"},
	{section = "Variation", key = "COMPOSITING_JITTER_INTERVAL_MIN", label = "Jitter interval min", min = 0.01, max = 2.0, format = "%.3f"},
	{section = "Variation", key = "COMPOSITING_JITTER_INTERVAL_MAX", label = "Jitter interval max", min = 0.01, max = 2.0, format = "%.3f"}
}

local function say_helper(str)
	local blob, info = say.synthesize(str, {
		lang = "en",
		format = "raw"
	})

	print("say_helper() : " .. info.format, info.sample_count, info.duration_seconds)
	print("say_helper() : " .. blob:GetSize())
end

math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 1000000))

local function open_demo_window(res_x, res_y, default_fullscreen)
	local win = hg.NewWindow("Demo Shadow 2026", res_x, res_y, 32, default_fullscreen)
	hg.RenderInit(win)
	hg.RenderReset(res_x, res_y, hg.RF_VSync | hg.RF_MSAA4X | hg.RF_MaxAnisotropy)
	return win
end

local function draw_line(pos_a, pos_b, line_color, view_id, vtx_line_layout, line_shader)
	local vtx = hg.Vertices(vtx_line_layout, 2)
	vtx:Begin(0):SetPos(pos_a):SetColor0(line_color):End()
	vtx:Begin(1):SetPos(pos_b):SetColor0(line_color):End()
	hg.DrawLines(view_id, vtx, line_shader)
end

local function push_line(lines, pos_a, pos_b, color)
	lines[#lines + 1] = {pos_a = pos_a, pos_b = pos_b, color = color}
end

local function append_automaton_debug_lines(lines, automaton_controller)
	if automaton_controller == nil then
		return
	end

	local debug_draw_state = automaton_controller:GetDebugDrawState()
	if debug_draw_state == nil then
		return
	end

	local root_origin = debug_draw_state.root_pos + hg.Vec3(0.0, 0.05, 0.0)
	local root_logic_origin = root_origin + hg.Vec3(0.0, 0.00, 0.0)
	local root_world_origin = root_origin + hg.Vec3(0.0, 0.08, 0.0)
	local desired_origin = root_origin + hg.Vec3(0.0, 0.16, 0.0)
	local hips_origin = debug_draw_state.hips_pos + hg.Vec3(0.0, 0.03, 0.0)
	local neck_origin = debug_draw_state.neck_pos + hg.Vec3(0.0, 0.04, 0.0)
	local head_origin = debug_draw_state.head_pos + hg.Vec3(0.0, 0.03, 0.0)

	push_line(lines, root_logic_origin, root_logic_origin + debug_draw_state.current_forward * 1.3, hg.Color(1.0, 0.9, 0.1, 1.0))
	push_line(lines, root_world_origin, root_world_origin + debug_draw_state.root_world_forward * 1.15, hg.Color(1.0, 0.5, 0.0, 1.0))
	push_line(lines, desired_origin, desired_origin + debug_draw_state.desired_direction * 1.1, hg.Color(1.0, 0.2, 0.8, 1.0))
	push_line(lines, hips_origin, hips_origin + debug_draw_state.hips_forward * 0.8, hg.Color(0.0, 1.0, 1.0, 1.0))
	push_line(lines, head_origin, head_origin + debug_draw_state.head_forward * 0.65, hg.Color(0.2, 1.0, 0.4, 0.45))
	push_line(lines, neck_origin, neck_origin + debug_draw_state.neck_actual_forward * 0.55, hg.Color(0.0, 0.9, 0.2, 1.0))
	push_line(lines, head_origin, head_origin + debug_draw_state.head_actual_forward * 0.65, hg.Color(0.1, 1.0, 0.1, 1.0))
	push_line(lines, debug_draw_state.left_foot_pos, debug_draw_state.right_foot_pos, hg.Color(0.25, 0.6, 1.0, 1.0))

	if debug_draw_state.target_pos ~= nil then
		local target_pos = hg.Vec3(debug_draw_state.target_pos.x, desired_origin.y, debug_draw_state.target_pos.z)
		push_line(lines, desired_origin, target_pos, hg.Color(1.0, 1.0, 1.0, 1.0))
	end

	if debug_draw_state.look_target_pos ~= nil then
		push_line(lines, neck_origin, debug_draw_state.look_target_pos, hg.Color(1.0, 0.4, 0.4, 0.6))
		push_line(lines, head_origin, debug_draw_state.look_target_pos, hg.Color(1.0, 0.7, 0.2, 0.6))
	end

	if debug_draw_state.look_neck_desired_dir ~= nil then
		push_line(lines, neck_origin, neck_origin + debug_draw_state.look_neck_desired_dir * 0.6, hg.Color(1.0, 0.85, 0.1, 1.0))
	end
	if debug_draw_state.look_neck_applied_dir ~= nil then
		push_line(lines, neck_origin, neck_origin + debug_draw_state.look_neck_applied_dir * 0.72, hg.Color(0.2, 0.75, 1.0, 1.0))
	end
	if debug_draw_state.look_neck_actual_dir ~= nil then
		push_line(lines, neck_origin, neck_origin + debug_draw_state.look_neck_actual_dir * 0.84, hg.Color(0.0, 1.0, 0.25, 1.0))
	end

	if debug_draw_state.look_head_desired_dir ~= nil then
		push_line(lines, head_origin, head_origin + debug_draw_state.look_head_desired_dir * 0.7, hg.Color(1.0, 0.9, 0.15, 1.0))
	end
	if debug_draw_state.look_head_applied_dir ~= nil then
		push_line(lines, head_origin, head_origin + debug_draw_state.look_head_applied_dir * 0.82, hg.Color(0.25, 0.8, 1.0, 1.0))
	end
	if debug_draw_state.look_head_actual_dir ~= nil then
		push_line(lines, head_origin, head_origin + debug_draw_state.look_head_actual_dir * 0.94, hg.Color(0.0, 1.0, 0.3, 1.0))
	end
end

local function clone_compositing_settings(source)
	local copy = {}

	for _, key in ipairs(COMPOSITING_SETTINGS_ORDER) do
		copy[key] = source[key]
	end

	return copy
end

local function sanitize_compositing_settings(settings)
	settings.COMPOSITING_VIGNETTE_START = math.max(0.0, settings.COMPOSITING_VIGNETTE_START)
	settings.COMPOSITING_VIGNETTE_END = math.max(settings.COMPOSITING_VIGNETTE_START + 0.001, settings.COMPOSITING_VIGNETTE_END)
	settings.COMPOSITING_VIGNETTE_STRENGTH = math.max(0.0, settings.COMPOSITING_VIGNETTE_STRENGTH)
	settings.COMPOSITING_CIRCULAR_BLUR_STRENGTH = math.max(0.0, settings.COMPOSITING_CIRCULAR_BLUR_STRENGTH)
	settings.COMPOSITING_CRT_CURVATURE = math.max(0.0, settings.COMPOSITING_CRT_CURVATURE)
	settings.COMPOSITING_CRT_MASK_DENSITY = math.max(0.0, settings.COMPOSITING_CRT_MASK_DENSITY)
	settings.COMPOSITING_CRT_MASK_INTENSITY = math.max(0.0, settings.COMPOSITING_CRT_MASK_INTENSITY)
	settings.COMPOSITING_LEFT_LIGHT_SHIFT = math.max(0.0, settings.COMPOSITING_LEFT_LIGHT_SHIFT)
	settings.COMPOSITING_STRENGTH_VARIATION_AMPLITUDE = math.max(0.0, settings.COMPOSITING_STRENGTH_VARIATION_AMPLITUDE)
	settings.COMPOSITING_SMOOTH_WOBBLE_SPEED = math.max(0.0, settings.COMPOSITING_SMOOTH_WOBBLE_SPEED)
	settings.COMPOSITING_JITTER_RESPONSE = math.max(0.0, settings.COMPOSITING_JITTER_RESPONSE)
	settings.COMPOSITING_JITTER_INTERVAL_MIN = math.max(0.01, settings.COMPOSITING_JITTER_INTERVAL_MIN)
	settings.COMPOSITING_JITTER_INTERVAL_MAX = math.max(settings.COMPOSITING_JITTER_INTERVAL_MIN, settings.COMPOSITING_JITTER_INTERVAL_MAX)
end

local function load_compositing_settings(via_launcher)
	local settings = clone_compositing_settings(DEFAULT_COMPOSITING_SETTINGS)
	local saved_settings

	if via_launcher then
		local module_name = COMPOSITING_SETTINGS_PATH:gsub("%.lua$", "")
		local ok, result = pcall(require, module_name)
		if not ok then
			sanitize_compositing_settings(settings)
			return settings, ("Failed to require %s: %s"):format(module_name, result)
		end
		saved_settings = result
	else
		local file = io.open(COMPOSITING_SETTINGS_PATH, "r")

		if file == nil then
			sanitize_compositing_settings(settings)
			return settings, ("No %s found, using built-in defaults."):format(COMPOSITING_SETTINGS_PATH)
		end

		file:close()

		local chunk, load_err = loadfile(COMPOSITING_SETTINGS_PATH)
		if chunk == nil then
			sanitize_compositing_settings(settings)
			return settings, ("Failed to load %s: %s"):format(COMPOSITING_SETTINGS_PATH, load_err)
		end

		local ok, result = pcall(chunk)
		if not ok then
			sanitize_compositing_settings(settings)
			return settings, ("Failed to evaluate %s: %s"):format(COMPOSITING_SETTINGS_PATH, result)
		end
		saved_settings = result
	end

	if type(saved_settings) ~= "table" then
		sanitize_compositing_settings(settings)
		return settings, ("%s must return a table, using built-in defaults."):format(COMPOSITING_SETTINGS_PATH)
	end

	for _, key in ipairs(COMPOSITING_SETTINGS_ORDER) do
		if type(saved_settings[key]) == "number" then
			settings[key] = saved_settings[key]
		end
	end

	sanitize_compositing_settings(settings)
	return settings, ("Loaded %s."):format(COMPOSITING_SETTINGS_PATH)
end

local function save_compositing_settings(settings)
	local lines = {"-- Saved by the in-game compositing tuning UI.", "return {"}
	sanitize_compositing_settings(settings)

	for _, key in ipairs(COMPOSITING_SETTINGS_ORDER) do
		lines[#lines + 1] = ("\t%s = %.6f,"):format(key, settings[key])
	end

	lines[#lines + 1] = "}"

	local file, open_err = io.open(COMPOSITING_SETTINGS_PATH, "w")
	if file == nil then
		return false, open_err
	end

	local ok, write_err = file:write(table.concat(lines, "\n") .. "\n")
	file:close()

	if ok == nil then
		return false, write_err
	end

	return true, nil
end

local function random_range(min_value, max_value)
	return min_value + (max_value - min_value) * math.random()
end

local function create_strength_modulator(setting_key, phase, wobble_speed_scale)
	return {
		setting_key = setting_key,
		phase = phase,
		wobble_speed_scale = wobble_speed_scale,
		elapsed = 0.0,
		jitter_value = 0.0,
		jitter_target = 0.0,
		jitter_time_left = 0.0
	}
end

local function update_strength_modulator(modulator, settings, dt_sec)
	local interval_min = math.min(settings.COMPOSITING_JITTER_INTERVAL_MIN, settings.COMPOSITING_JITTER_INTERVAL_MAX)
	local interval_max = math.max(settings.COMPOSITING_JITTER_INTERVAL_MIN, settings.COMPOSITING_JITTER_INTERVAL_MAX)
	local base_value = settings[modulator.setting_key]

	modulator.elapsed = modulator.elapsed + dt_sec
	modulator.jitter_time_left = modulator.jitter_time_left - dt_sec

	if modulator.jitter_time_left <= 0.0 then
		modulator.jitter_time_left = random_range(interval_min, interval_max)
		modulator.jitter_target = random_range(-1.0, 1.0)
	end

	local jitter_follow = 1.0 - math.exp(-settings.COMPOSITING_JITTER_RESPONSE * dt_sec)
	modulator.jitter_value = modulator.jitter_value + (modulator.jitter_target - modulator.jitter_value) * jitter_follow

	local smooth_value = math.sin(modulator.elapsed * settings.COMPOSITING_SMOOTH_WOBBLE_SPEED * modulator.wobble_speed_scale + modulator.phase)
	local combined_variation = smooth_value * 0.65 + modulator.jitter_value * 0.35
	local strength_scale = 1.0 + settings.COMPOSITING_STRENGTH_VARIATION_AMPLITUDE * combined_variation

	return math.max(0.0, base_value * strength_scale)
end

local function apply_compositing_settings(pipeline_aaa_config, settings, dt_sec, vignette_modulator, circular_blur_modulator)
	local vignette_strength = settings.COMPOSITING_VIGNETTE_STRENGTH
	local circular_blur_strength = settings.COMPOSITING_CIRCULAR_BLUR_STRENGTH

	if dt_sec ~= nil and vignette_modulator ~= nil and circular_blur_modulator ~= nil then
		vignette_strength = update_strength_modulator(vignette_modulator, settings, dt_sec)
		circular_blur_strength = update_strength_modulator(circular_blur_modulator, settings, dt_sec)
	end

	pipeline_aaa_config.compositing_params0 = hg.Vec4(
		settings.COMPOSITING_VIGNETTE_START,
		settings.COMPOSITING_VIGNETTE_END,
		vignette_strength,
		circular_blur_strength
	)
	pipeline_aaa_config.compositing_params1 = hg.Vec4(
		settings.COMPOSITING_CRT_CURVATURE,
		settings.COMPOSITING_CRT_MASK_DENSITY,
		settings.COMPOSITING_CRT_MASK_INTENSITY,
		settings.COMPOSITING_LEFT_LIGHT_SHIFT
	)
end

local function create_pipeline_aaa(config, compositing_settings)
	if not config.enable_aaa then
		return nil, nil
	end

	local pipeline_aaa_config = hg.ForwardPipelineAAAConfig()

	if config.low_aaa then
		pipeline_aaa_config.temporal_aa_weight = 0.2
		pipeline_aaa_config.sample_count = 1
	else
		pipeline_aaa_config.temporal_aa_weight = 0.05
		pipeline_aaa_config.sample_count = 2
	end

	pipeline_aaa_config.z_thickness = 0.01
	pipeline_aaa_config.bloom_bias = 0.61
	pipeline_aaa_config.bloom_intensity = 1.74 * 1.1
	pipeline_aaa_config.bloom_threshold = 1.55
	pipeline_aaa_config.exposure = 1.59 * 1.1
	pipeline_aaa_config.gamma = 2.09
	pipeline_aaa_config.motion_blur = 0.0
	apply_compositing_settings(pipeline_aaa_config, compositing_settings)

	local pipeline_aaa = hg.CreateForwardPipelineAAAFromAssets("core", pipeline_aaa_config, hg.BR_Half, hg.BR_Half)

	return pipeline_aaa, pipeline_aaa_config
end

local function configure_main_light_shadow_range(scene)
	local main_light_node = scene:GetNode(MAIN_LIGHT_NAME)
	if not main_light_node:IsValid() then
		error(('Light "%s" not found in main_scene.scn'):format(MAIN_LIGHT_NAME))
	end

	local main_light = main_light_node:GetLight()
	if not main_light:IsValid() then
		error(('Node "%s" does not have a valid Light component'):format(MAIN_LIGHT_NAME))
	end

	main_light:SetShadowNear(MAIN_LIGHT_SHADOW_NEAR)
	main_light:SetShadowFar(MAIN_LIGHT_SHADOW_FAR)
end

local function load_main_scene(res)
	local scene = hg.Scene()
	hg.LoadSceneFromAssets("main_scene.scn", scene, res, hg.GetForwardPipelineInfo())

	local cam = scene:GetNode("Camera")
	if not cam:IsValid() then
		error('Camera "Camera" not found in main_scene.scn')
	end

	configure_main_light_shadow_range(scene)
	scene:SetCurrentCamera(cam)
	return scene
end

local function draw_compositing_slider(settings, field)
	local changed
	changed, settings[field.key] = hg.ImGuiSliderFloat(field.label, settings[field.key], field.min, field.max, field.format)
	return changed
end

local function start_robot_scenario(automaton_controller)
	if automaton_controller == nil then
		return
	end

	if type(robot_actions) ~= "table" then
		error("robot_scenario.lua must return an action table")
	end

	automaton_controller:StopActionSequence()
	automaton_controller:RunActionSequence(robot_actions)
end

local function draw_compositing_tuning_ui(settings, ui_state, automaton_controller, show_automaton_debug_draw)
	local current_section = nil

	hg.ImGuiSetNextWindowPos(hg.Vec2(24, 24), hg.ImGuiCond_Once)

	if hg.ImGuiBegin("Compositing Tuning") then
		hg.ImGuiText("TAB: show/hide")
		hg.ImGuiText(("File: %s"):format(COMPOSITING_SETTINGS_PATH))

		if ui_state.dirty then
			hg.ImGuiText("State: unsaved changes")
		else
			hg.ImGuiText("State: saved values")
		end

		if ui_state.status_message ~= "" then
			hg.ImGuiText(ui_state.status_message)
		end

		for _, field in ipairs(COMPOSITING_UI_FIELDS) do
			if field.section ~= current_section then
				hg.ImGuiSpacing()
				hg.ImGuiSeparator()
				hg.ImGuiSpacing()
				hg.ImGuiText(field.section)
				current_section = field.section
			end

			if draw_compositing_slider(settings, field) then
				sanitize_compositing_settings(settings)
				ui_state.dirty = true
				ui_state.status_message = "Modified in memory. Click Save to persist."
			end
		end

		hg.ImGuiSpacing()
		hg.ImGuiSeparator()
		hg.ImGuiSpacing()

		if hg.ImGuiButton("Save compositing_tuning.lua") then
			local saved, save_err = save_compositing_settings(settings)
			if saved then
				ui_state.dirty = false
				ui_state.status_message = ("Saved to %s."):format(COMPOSITING_SETTINGS_PATH)
			else
				ui_state.status_message = ("Save failed: %s"):format(save_err)
			end
		end

		if automaton_controller ~= nil then
			local debug_state = automaton_controller:GetDebugState()

			hg.ImGuiSpacing()
			hg.ImGuiSeparator()
			hg.ImGuiSpacing()
			hg.ImGuiText("Automaton")
			hg.ImGuiText(("State: %s"):format(debug_state.state))
			hg.ImGuiText(("Target: %s"):format(debug_state.target))
			hg.ImGuiText(("Distance: %.3f m"):format(debug_state.distance_to_target))
			hg.ImGuiText(("Yaw error: %.2f deg"):format(debug_state.yaw_error_deg))
			hg.ImGuiText(("Speed: %.3f m/s"):format(debug_state.current_speed))
			hg.ImGuiText(("Gait drive: %.2f"):format(debug_state.gait_drive))
			hg.ImGuiText(("Support foot: %s"):format(debug_state.support_side))
			hg.ImGuiText(("Step progress: %.2f"):format(debug_state.step_progress))
			hg.ImGuiText(("Left hand: %s"):format(debug_state.left_hand))
			hg.ImGuiText(("Right hand: %s"):format(debug_state.right_hand))
			hg.ImGuiText(("Held left: %s"):format(debug_state.held_left))
			hg.ImGuiText(("Held right: %s"):format(debug_state.held_right))
			hg.ImGuiText(("Look target: %s"):format(debug_state.look_target))
			hg.ImGuiText(("Look blend: %.2f"):format(debug_state.look_blend))
			hg.ImGuiText(("Backpack weight: %.2f"):format(debug_state.backpack_weight))
			hg.ImGuiText(("Backpack rot X/Y: %.2f / %.2f deg"):format(debug_state.backpack_pitch_deg, debug_state.backpack_yaw_deg))
			hg.ImGuiText(("Action: %s"):format(debug_state.current_action_type))
			hg.ImGuiText(("Action index: %d"):format(debug_state.action_index))
			hg.ImGuiText(("F1/F2 move %s <-> %s"):format(DEBUG_MOVE_START_NODE, DEBUG_MOVE_TARGET_NODE))
			hg.ImGuiText("F3/F4 left hand lock/unlock")
			hg.ImGuiText("F5/F6 right hand lock/unlock")
			hg.ImGuiText(("F7/F8 rotate toward %s/%s"):format(DEBUG_ROTATE_TARGET_NODE_A, DEBUG_ROTATE_TARGET_NODE_B))
			hg.ImGuiText("F9 rerun robot scenario")
			hg.ImGuiText(("F10 debug draw: %s"):format(show_automaton_debug_draw and "on" or "off"))
			hg.ImGuiText("Debug colors: yellow=compensated root, orange=raw root axis, pink=desired, cyan=pelvis, green=chest, white=target")

			if hg.ImGuiButton(("Move %s -> %s"):format(DEBUG_MOVE_START_NODE, DEBUG_MOVE_TARGET_NODE)) then
				automaton_controller:MoveFromNodeToNode(DEBUG_MOVE_START_NODE, DEBUG_MOVE_TARGET_NODE)
			end
			hg.ImGuiSameLine()
			if hg.ImGuiButton(("Move %s -> %s"):format(DEBUG_MOVE_TARGET_NODE, DEBUG_MOVE_START_NODE)) then
				automaton_controller:MoveFromNodeToNode(DEBUG_MOVE_TARGET_NODE, DEBUG_MOVE_START_NODE)
			end

			if hg.ImGuiButton(("Rotate toward %s"):format(DEBUG_ROTATE_TARGET_NODE_A)) then
				automaton_controller:RotateToNode(DEBUG_ROTATE_TARGET_NODE_A)
			end
			hg.ImGuiSameLine()
			if hg.ImGuiButton(("Rotate toward %s"):format(DEBUG_ROTATE_TARGET_NODE_B)) then
				automaton_controller:RotateToNode(DEBUG_ROTATE_TARGET_NODE_B)
			end

			if hg.ImGuiButton("Run robot scenario") then
				start_robot_scenario(automaton_controller)
			end

			if hg.ImGuiButton("Lock left hand on hand_target_A") then
				automaton_controller:PlaceLeftHandOnNode("hand_target_A")
			end
			hg.ImGuiSameLine()
			if hg.ImGuiButton("Unlock left hand") then
				automaton_controller:UnlockLeftHand()
			end

			if hg.ImGuiButton("Lock right hand on hand_target_A") then
				automaton_controller:PlaceRightHandOnNode("hand_target_A")
			end
			hg.ImGuiSameLine()
			if hg.ImGuiButton("Unlock right hand") then
				automaton_controller:UnlockRightHand()
			end
		end
	end

	hg.ImGuiEnd()
end

local function handle_automaton_debug_controls(keyboard, automaton_controller)
	if automaton_controller == nil then
		return
	end

	if keyboard:Pressed(hg.K_F1) then
		automaton_controller:MoveFromNodeToNode(DEBUG_MOVE_START_NODE, DEBUG_MOVE_TARGET_NODE)
	end

	if keyboard:Pressed(hg.K_F2) then
		automaton_controller:MoveFromNodeToNode(DEBUG_MOVE_TARGET_NODE, DEBUG_MOVE_START_NODE)
	end

	if keyboard:Pressed(hg.K_F3) then
		automaton_controller:PlaceLeftHandOnNode("hand_target_A")
	end

	if keyboard:Pressed(hg.K_F4) then
		automaton_controller:UnlockLeftHand()
	end

	if keyboard:Pressed(hg.K_F5) then
		automaton_controller:PlaceRightHandOnNode("hand_target_A")
	end

	if keyboard:Pressed(hg.K_F6) then
		automaton_controller:UnlockRightHand()
	end

	if keyboard:Pressed(hg.K_F7) then
		automaton_controller:RotateToNode(DEBUG_ROTATE_TARGET_NODE_A)
	end

	if keyboard:Pressed(hg.K_F8) then
		automaton_controller:RotateToNode(DEBUG_ROTATE_TARGET_NODE_B)
	end

	if keyboard:Pressed(hg.K_F9) then
		start_robot_scenario(automaton_controller)
	end
end

local function run_demo_3d(win, res_x, res_y, config, compositing_settings, load_status_message)
	local pipeline = hg.CreateForwardPipeline(2048, false)
	local res = hg.PipelineResources()
	local scene = load_main_scene(res)
	local automaton_controller = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")
	automaton_controller:SetBackpackWeight(BACKPACK_WEIGHT)
	local pipeline_aaa, pipeline_aaa_config = create_pipeline_aaa(config, compositing_settings)
	local vignette_modulator = create_strength_modulator("COMPOSITING_VIGNETTE_STRENGTH", 0.0, 0.85)
	local circular_blur_modulator = create_strength_modulator("COMPOSITING_CIRCULAR_BLUR_STRENGTH", math.pi * 0.37, 1.15)
	local imgui_prg = hg.LoadProgramFromAssets("core/shader/imgui")
	local imgui_img_prg = hg.LoadProgramFromAssets("core/shader/imgui_image")
	local debug_line_layout = hg.VertexLayoutPosFloatColorUInt8()
	local debug_line_shader = hg.LoadProgramFromAssets("shaders/pos_rgb")
	local mouse = hg.Mouse()
	local keyboard = hg.Keyboard()
	local show_compositing_ui = false
	local show_automaton_debug_draw = false
	local ui_state = {dirty = false, status_message = load_status_message or ""}
	local frame = 0
	local ambiant_audio_source

	start_robot_scenario(automaton_controller)
	ambiant_audio_source = hg.StreamOGGAssetStereo(AMBIANT_AUDIO_ASSET, hg.StereoSourceState(1, hg.SR_Loop))

	hg.ImGuiInit(10, imgui_prg, imgui_img_prg)

	while hg.IsWindowOpen(win) do
		mouse:Update()
		keyboard:Update()
		handle_automaton_debug_controls(keyboard, automaton_controller)

		if keyboard:Pressed(hg.K_Tab) then
			show_compositing_ui = not show_compositing_ui
			hg.ImGuiClearInputBuffer()
		end

		if keyboard:Pressed(hg.K_F10) then
			show_automaton_debug_draw = not show_automaton_debug_draw
		end

		if keyboard:Down(hg.K_Escape) then
			break
		end

		local dt = hg.TickClock()
		local dt_sec = hg.time_to_sec_f(dt)
		scene:Update(dt)

		hg.ImGuiBeginFrame(res_x, res_y, dt, mouse:GetState(), keyboard:GetState())

		if show_compositing_ui then
			draw_compositing_tuning_ui(compositing_settings, ui_state, automaton_controller, show_automaton_debug_draw)
		end

		automaton_controller:Update(dt_sec)

		local view_id
		local pass_ids
		if config.enable_aaa then
			apply_compositing_settings(pipeline_aaa_config, compositing_settings, dt_sec, vignette_modulator, circular_blur_modulator)
			view_id, pass_ids = hg.SubmitSceneToPipeline(
				0,
				scene,
				hg.IntRect(0, 0, res_x, res_y),
				true,
				pipeline,
				res,
				pipeline_aaa,
				pipeline_aaa_config,
				frame
			)
		else
			view_id, pass_ids = hg.SubmitSceneToPipeline(
				0,
				scene,
				hg.IntRect(0, 0, res_x, res_y),
				true,
				pipeline,
				res
			)
		end

		if show_automaton_debug_draw then
			local debug_lines = {}
			local opaque_view_id = hg.GetSceneForwardPipelinePassViewId(pass_ids, hg.SFPP_Opaque)

			append_automaton_debug_lines(debug_lines, automaton_controller)

			for i = 1, #debug_lines do
				draw_line(debug_lines[i].pos_a, debug_lines[i].pos_b, debug_lines[i].color, opaque_view_id, debug_line_layout, debug_line_shader)
			end
		end

		hg.SetView2D(COMPOSITING_UI_VIEW_ID, 0, 0, res_x, res_y, -1, 0, hg.CF_Depth, hg.Color.Black, 1, 0)
		hg.ImGuiEndFrame(COMPOSITING_UI_VIEW_ID)

		frame = hg.Frame()
		hg.UpdateWindow(win)
	end

	hg.ImGuiShutdown()
end

local function main(cmd_arg)
	local config = {enable_aaa = true, low_aaa = false}
	local compositing_settings
	local compositing_load_status

	hg.InputInit()
	hg.WindowSystemInit()
	hg.AudioInit()

	say_helper("Shadow Party like it's 2026!")

	local via_launcher = cmd_arg[1] == "--launcher"

	if via_launcher then
		hg.AddAssetsFolder("data/assets_compiled")
	else
		hg.AddAssetsFolder("assets_compiled")
	end

	compositing_settings, compositing_load_status = load_compositing_settings(via_launcher)

	local config_done
	local res_x
	local res_y
	local default_fullscreen
	local low_aaa
	local no_aaa

	hg.ShowCursor()
	config_done, res_x, res_y, default_fullscreen, _, low_aaa, no_aaa = config_gui()

	if no_aaa then
		config.enable_aaa = false
	else
		config.enable_aaa = true
		config.low_aaa = low_aaa and true or false
	end

	if config_done == 1 then
		local win = open_demo_window(res_x, res_y, default_fullscreen)
		run_demo_3d(win, res_x, res_y, config, compositing_settings, compositing_load_status)
		hg.RenderShutdown()
		hg.DestroyWindow(win)
	end

	hg.WindowSystemShutdown()
	hg.AudioShutdown()
	hg.InputShutdown()
end

main(arg)
