hg = require("harfang")
require("config_gui")

local MAIN_LIGHT_NAME = "MainLight"
local MAIN_LIGHT_SHADOW_NEAR = 25.0
local MAIN_LIGHT_SHADOW_FAR = 55.0
local COMPOSITING_VIGNETTE_START = 0.72
local COMPOSITING_VIGNETTE_END = 1.28
local COMPOSITING_VIGNETTE_STRENGTH = 0.5
local COMPOSITING_CIRCULAR_BLUR_STRENGTH = 10.0
local COMPOSITING_STRENGTH_VARIATION_AMPLITUDE = 0.2
local COMPOSITING_SMOOTH_WOBBLE_SPEED = 0.9
local COMPOSITING_JITTER_RESPONSE = 6.0
local COMPOSITING_JITTER_INTERVAL_MIN = 0.1
local COMPOSITING_JITTER_INTERVAL_MAX = 0.5

math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 1000000))

local function open_demo_window(res_x, res_y, default_fullscreen)
	local win = hg.NewWindow("Demo Shadow 2026", res_x, res_y, 32, default_fullscreen)
	hg.RenderInit(win)
	hg.RenderReset(res_x, res_y, hg.RF_VSync | hg.RF_MSAA4X | hg.RF_MaxAnisotropy)
	return win
end

local function random_range(min_value, max_value)
	return min_value + (max_value - min_value) * math.random()
end

local function create_strength_modulator(base_value, phase, wobble_speed_scale)
	return {
		base_value = base_value,
		phase = phase,
		wobble_speed_scale = wobble_speed_scale,
		elapsed = 0.0,
		jitter_value = 0.0,
		jitter_target = 0.0,
		jitter_time_left = 0.0
	}
end

local function update_strength_modulator(modulator, dt_sec)
	modulator.elapsed = modulator.elapsed + dt_sec
	modulator.jitter_time_left = modulator.jitter_time_left - dt_sec

	if modulator.jitter_time_left <= 0.0 then
		modulator.jitter_time_left = random_range(COMPOSITING_JITTER_INTERVAL_MIN, COMPOSITING_JITTER_INTERVAL_MAX)
		modulator.jitter_target = random_range(-1.0, 1.0)
	end

	local jitter_follow = 1.0 - math.exp(-COMPOSITING_JITTER_RESPONSE * dt_sec)
	modulator.jitter_value = modulator.jitter_value + (modulator.jitter_target - modulator.jitter_value) * jitter_follow

	local smooth_value = math.sin(modulator.elapsed * COMPOSITING_SMOOTH_WOBBLE_SPEED * modulator.wobble_speed_scale + modulator.phase)
	local combined_variation = smooth_value * 0.65 + modulator.jitter_value * 0.35
	local strength_scale = 1.0 + COMPOSITING_STRENGTH_VARIATION_AMPLITUDE * combined_variation

	return math.max(0.0, modulator.base_value * strength_scale)
end

local function update_compositing_strengths(pipeline_aaa_config, dt_sec, vignette_modulator, circular_blur_modulator)
	pipeline_aaa_config.compositing_params0 = hg.Vec4(
		COMPOSITING_VIGNETTE_START,
		COMPOSITING_VIGNETTE_END,
		update_strength_modulator(vignette_modulator, dt_sec),
		update_strength_modulator(circular_blur_modulator, dt_sec)
	)
end

local function create_pipeline_aaa(config)
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

	pipeline_aaa_config.z_thickness = 1.0
	pipeline_aaa_config.bloom_bias = 0.61
	pipeline_aaa_config.bloom_intensity = 1.74
	pipeline_aaa_config.bloom_threshold = 1.55
	pipeline_aaa_config.exposure = 1.59
	pipeline_aaa_config.gamma = 2.09
	pipeline_aaa_config.compositing_params0 = hg.Vec4(
		COMPOSITING_VIGNETTE_START,
		COMPOSITING_VIGNETTE_END,
		COMPOSITING_VIGNETTE_STRENGTH,
		COMPOSITING_CIRCULAR_BLUR_STRENGTH
	)
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

local function run_demo_3d(win, res_x, res_y, config)
	local pipeline = hg.CreateForwardPipeline(2048, false)
	local res = hg.PipelineResources()
	local scene = load_main_scene(res)
	local pipeline_aaa, pipeline_aaa_config = create_pipeline_aaa(config)
	local vignette_modulator = create_strength_modulator(COMPOSITING_VIGNETTE_STRENGTH, 0.0, 0.85)
	local circular_blur_modulator = create_strength_modulator(COMPOSITING_CIRCULAR_BLUR_STRENGTH, math.pi * 0.37, 1.15)
	local frame = 0

	while not hg.ReadKeyboard():Key(hg.K_Escape) and hg.IsWindowOpen(win) do
		local dt = hg.TickClock()
		local dt_sec = hg.time_to_sec_f(dt)
		scene:Update(dt)

		if config.enable_aaa then
			update_compositing_strengths(pipeline_aaa_config, dt_sec, vignette_modulator, circular_blur_modulator)
			hg.SubmitSceneToPipeline(
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
			hg.SubmitSceneToPipeline(
				0,
				scene,
				hg.IntRect(0, 0, res_x, res_y),
				true,
				pipeline,
				res
			)
		end

		frame = hg.Frame()
		hg.UpdateWindow(win)
	end
end

local function main(cmd_arg)
	local config = {enable_aaa = true, low_aaa = false}

	hg.InputInit()
	hg.WindowSystemInit()

	if cmd_arg[1] == "--launcher" then
		hg.AddAssetsFolder("data/assets_compiled")
	else
		hg.AddAssetsFolder("assets_compiled")
	end

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
		run_demo_3d(win, res_x, res_y, config)
		hg.RenderShutdown()
		hg.DestroyWindow(win)
	end

	hg.WindowSystemShutdown()
	hg.InputShutdown()
end

main(arg)
